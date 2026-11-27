// Multimizer kurtarma motoru. Yalnızca OKUR: kaynak sürücüye, diske ya da imaj dosyasına hiçbir şey yazılmaz.
// Dosya sistemleri:
//   NTFS            silinmiş dosya kayıtları (ad, klasör, tarih) + boş alanda imza taraması
//   FAT12/16/32     silinmiş klasör girdileri (uzun adlar dahil) + boş alanda imza taraması
//   exFAT           silinmiş girdi kümeleri (sağlama toplamı doğrulamalı) + boş alanda imza taraması
//   ext2/3/4        blok haritasına göre boş bloklarda imza taraması
//   diğerleri       (ReFS, HFS+, APFS, Btrfs, XFS, F2FS, bozuk ya da biçimlendirilmiş birimler) tüm birimde imza taraması
// Kaynak: sürücü harfi (E:), fiziksel disk (PhysicalDrive2) ya da ham imaj dosyası; MBR (genişletilmiş bölümler dahil) ve GPT okunur.
// C# 5 uyumlu yazılmıştır (Windows PowerShell 5.1 içindeki derleyici için). Dosyanın devamı RcEngineFs.cs içindedir (partial).
using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace Mm
{
    // stage: aşama adı, done/total: ilerleme. false dönerse iş iptal edilir.
    public delegate bool RcProgress(string stage, long done, long total);

    // Kaynaktaki bir bölüm (ya da bölümsüz tek birim)
    public sealed class RcPartInfo
    {
        public int Index;
        public long Start;           // kaynak içindeki bayt konumu
        public long Length;          // bayt, bilinmiyorsa 0
        public string Fs = "";       // NTFS, FAT32, exFAT, ext4, Btrfs ... ; tanınmıyorsa boş
        public string Kind = "";     // MBR:07, GPT gibi kısa ad
    }

    public sealed class RcItem
    {
        public string Kind = "";     // mft | fat | carve   (fat: FAT ve exFAT silinmiş girdileri)
        public long Rec;             // NTFS kayıt numarası (mft)
        public long Offset;          // bölüm içindeki bayt konumu (carve, fat)
        public long Length;          // bayt
        public string Name = "";
        public string Path = "";
        public string Ext = "";
        public long Modified;        // son yazma zamanı, FILETIME (UTC), bilinmiyorsa 0
        public long Deleted;         // kayıt değişim zamanı (silinme anına yakın), FILETIME (UTC)
        public int Chance;           // 0..100
        public string Note = "";
    }

    public sealed class RcRun
    {
        public long Lcn;             // -1: seyrek (sıfırlarla dolu) bölge
        public long Len;             // küme sayısı
        public RcRun(long lcn, long len) { Lcn = lcn; Len = len; }
    }

    public sealed partial class RcEngine : IDisposable
    {
        // ---------------- alanlar ----------------
        Stream dev;
        long baseOffset;
        long devLength = -1;             // kaynağın toplam bayt uzunluğu, bilinmiyorsa -1
        long partLength;                 // seçili bölümün bayt uzunluğu, bilinmiyorsa 0
        byte[] scratch = new byte[0];
        public string Fs = "";
        public long ClusterSize;
        public long ClusterCount;
        public long VolumeBytes;
        public int RecSize;
        public int PartitionCount;       // kaynaktaki bölüm sayısı (bölümsüz tek birimse 1)
        public bool RawMode;             // dosya sistemi tanınmadı ya da bozuk: tüm birim imza ile taranır
        public string Method = "";       // mft | fat | exfat | free | raw
        public bool HasNames;            // ScanDeleted dosya adı ve klasörlerini verir (NTFS, FAT, exFAT)
        public string OpenNote = "";     // kullanıcıya gösterilecek açılış notu (ör. dosya sistemi tanınamadı)
        readonly List<RcPartInfo> parts = new List<RcPartInfo>();
        long firstCluster;
        long dataStart;
        byte[] bitmap = new byte[0];
        List<RcRun> mftRuns = new List<RcRun>();
        long mftSize;
        public long ReadErrors;
        public bool Canceled;
        public bool Truncated;
        public long StatRecords;
        public long StatDeleted;
        public long StatSkipped;
        public long StatFreeBytes;
        public string LastNote = "";
        readonly System.Diagnostics.Stopwatch tickWatch = System.Diagnostics.Stopwatch.StartNew();

        // İlerleme bildirimini seyreltir (en çok ~8 kez/sn). false: kullanıcı iptal etti.
        bool Tick(RcProgress prog, string stage, long done, long total)
        {
            if (prog == null) return true;
            if (done < total && tickWatch.ElapsedMilliseconds < 120) return true;
            tickWatch.Reset();
            tickWatch.Start();
            return prog(stage, done, total);
        }

        const long Align = 4096;

        // ---------------- açma ----------------
        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern SafeFileHandle CreateFile(string name, uint access, uint share, IntPtr security, uint disposition, uint flags, IntPtr template);

        // Yalnızca aygıt uzunluğunu sorgular (IOCTL_DISK_GET_LENGTH_INFO); aygıta hiçbir şey yazmaz ve durumunu değiştirmez.
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool DeviceIoControl(SafeFileHandle h, uint code, IntPtr inBuf, uint inSize, out long outBuf, uint outSize, out uint returned, IntPtr overlapped);

        const uint IoctlDiskGetLengthInfo = 0x0007405C;

        static long QueryLength(SafeFileHandle h)
        {
            long len;
            uint ret;
            try
            {
                if (DeviceIoControl(h, IoctlDiskGetLengthInfo, IntPtr.Zero, 0, out len, 8, out ret, IntPtr.Zero) && len > 0) return len;
            }
            catch (Exception) { }
            return -1;
        }

        public static bool IsDriveSpec(string s)
        {
            if (s == null) return false;
            string t = s.Trim();
            if (t.Length == 1) return Char.IsLetter(t[0]);
            if (t.Length == 2) return Char.IsLetter(t[0]) && t[1] == ':';
            if (t.Length == 3) return Char.IsLetter(t[0]) && t[1] == ':' && (t[2] == '\\' || t[2] == '/');
            return false;
        }

        // "PhysicalDrive3" ya da "\\.\PhysicalDrive3" -> 3
        public static bool DiskNumberOf(string s, out int number)
        {
            number = -1;
            if (s == null) return false;
            string t = s.Trim();
            if (t.StartsWith("\\\\.\\", StringComparison.Ordinal)) t = t.Substring(4);
            string up = t.ToUpperInvariant();
            if (!up.StartsWith("PHYSICALDRIVE", StringComparison.Ordinal)) return false;
            string d = up.Substring(13);
            if (d.Length == 0 || d.Length > 4) return false;
            foreach (char ch in d) { if (ch < '0' || ch > '9') return false; }
            number = Int32.Parse(d);
            return true;
        }

        public static bool IsDiskSpec(string s)
        {
            int n;
            return DiskNumberOf(s, out n);
        }

        static RcEngine OpenStream(string source)
        {
            if (source == null || source.Trim().Length == 0) throw new IOException("Kaynak belirtilmedi.");
            Stream s;
            long len = -1;
            int dn;
            if (IsDriveSpec(source))
            {
                string letter = source.Trim().Substring(0, 1).ToUpperInvariant();
                SafeFileHandle h = CreateFile("\\\\.\\" + letter + ":", 0x80000000u, 7u, IntPtr.Zero, 3u, 0u, IntPtr.Zero);
                if (h.IsInvalid)
                {
                    int err = Marshal.GetLastWin32Error();
                    if (err == 5) throw new IOException("Sürücüye erişim engellendi. Multimizer uygulamasını yönetici olarak çalıştırın.");
                    if (err == 2 || err == 3) throw new IOException("Sürücü bulunamadı: " + letter + ":");
                    throw new IOException("Sürücü açılamadı (Windows hata kodu " + err + ").");
                }
                len = QueryLength(h);
                s = new FileStream(h, FileAccess.Read, 4096, false);
            }
            else if (DiskNumberOf(source, out dn))
            {
                SafeFileHandle h2 = CreateFile("\\\\.\\PhysicalDrive" + dn, 0x80000000u, 7u, IntPtr.Zero, 3u, 0u, IntPtr.Zero);
                if (h2.IsInvalid)
                {
                    int err2 = Marshal.GetLastWin32Error();
                    if (err2 == 5) throw new IOException("Diske erişim engellendi. Multimizer uygulamasını yönetici olarak çalıştırın.");
                    if (err2 == 2 || err2 == 3 || err2 == 21) throw new IOException("Disk bulunamadı ya da hazır değil: Disk " + dn);
                    throw new IOException("Disk açılamadı (Windows hata kodu " + err2 + ").");
                }
                len = QueryLength(h2);
                s = new FileStream(h2, FileAccess.Read, 4096, false);
            }
            else
            {
                FileStream fs0 = new FileStream(source.Trim(), FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
                try { len = fs0.Length; } catch (Exception) { len = -1; }
                s = fs0;
            }
            RcEngine e = new RcEngine();
            e.dev = s;
            e.devLength = len;
            return e;
        }

        public static RcEngine Open(string source, int partition)
        {
            RcEngine e = OpenStream(source);
            try { e.Detect(partition); }
            catch { e.Dispose(); throw; }
            return e;
        }

        // Yalnızca bölüm düzenini okur (dosya sistemini açmaz): hızlıdır.
        public static RcPartInfo[] ListPartitions(string source)
        {
            RcEngine e = OpenStream(source);
            try
            {
                e.LoadLayout();
                return e.parts.ToArray();
            }
            finally { e.Dispose(); }
        }

        public RcPartInfo[] PartList { get { return parts.ToArray(); } }

        public void Dispose()
        {
            if (dev != null) { dev.Dispose(); dev = null; }
        }

        // ---------------- ham okuma ----------------
        int ReadDev(long pos, byte[] dst, int off, int count)
        {
            if (count <= 0 || pos < 0) return 0;
            long a0 = pos - (pos % Align);
            long a1 = ((pos + count + Align - 1) / Align) * Align;
            int alen = (int)(a1 - a0);
            if (scratch.Length < alen) scratch = new byte[alen];
            dev.Seek(a0, SeekOrigin.Begin);
            int got = 0;
            while (got < alen)
            {
                int n = dev.Read(scratch, got, alen - got);
                if (n <= 0) break;
                got += n;
            }
            int skip = (int)(pos - a0);
            int avail = got - skip;
            if (avail <= 0) return 0;
            int take = Math.Min(count, avail);
            Buffer.BlockCopy(scratch, skip, dst, off, take);
            return take;
        }

        // Bölüm içindeki konumdan okur. Okunamayan sektörler sıfır sayılır (ReadErrors artar).
        public int ReadVol(long volPos, byte[] dst, int off, int count)
        {
            if (volPos < 0 || count <= 0) return 0;
            try { return ReadDev(baseOffset + volPos, dst, off, count); }
            catch (IOException)
            {
                ReadErrors++;
                Array.Clear(dst, off, count);
                return count;
            }
        }

        static ushort U16(byte[] b, int o) { return (ushort)(b[o] | (b[o + 1] << 8)); }
        static uint U32(byte[] b, int o) { return (uint)(b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24)); }
        static ulong U64(byte[] b, int o) { return (ulong)U32(b, o) | ((ulong)U32(b, o + 4) << 32); }

        static bool Eq(byte[] b, int o, string s)
        {
            if (o < 0 || o + s.Length > b.Length) return false;
            for (int i = 0; i < s.Length; i++) { if (b[o + i] != (byte)s[i]) return false; }
            return true;
        }

        long ClusterOffset(long cluster) { return dataStart + (cluster - firstCluster) * ClusterSize; }

        public bool IsUsed(long cluster)
        {
            if (RawMode) return false;
            long i = cluster - firstCluster;
            if (i < 0) return true;
            long by = i >> 3;
            if (by >= bitmap.Length) return true;
            return (bitmap[by] & (1 << (int)(i & 7))) != 0;
        }

        // ---------------- tanıma ----------------
        static string SniffFs(byte[] b)
        {
            if (Eq(b, 3, "NTFS    ")) return "NTFS";
            if (Eq(b, 3, "EXFAT   ")) return "exFAT";
            if (Eq(b, 3, "-FVE-FS-")) return "BITLOCKER";
            if (Eq(b, 82, "FAT32   ")) return "FAT32";
            if (Eq(b, 54, "FAT16   ")) return "FAT16";
            if (Eq(b, 54, "FAT12   ")) return "FAT12";
            return "";
        }

        // ext2/3/4 ailesinin adı (özellik bayraklarına göre)
        static string ExtFlavor(byte[] b)
        {
            uint compat = U32(b, 1024 + 92);
            uint incompat = U32(b, 1024 + 96);
            uint rocompat = U32(b, 1024 + 100);
            if ((incompat & 0xFFFFFFC0u) != 0 || (rocompat & 0xFFFFFFF8u) != 0) return "ext4";
            if ((compat & 0x4u) != 0) return "ext3";
            return "ext2";
        }

        // Birimin (ya da bölümün) ilk 4096 baytına bakarak dosya sistemini tanır; tanıyamazsa "".
        // pos: b'nin kaynak içindeki konumu (Btrfs gibi uzak imzalar için).
        string SniffFsAt(long pos, byte[] b)
        {
            string s = SniffFs(b);
            if (s != "") return s;
            if (b.Length < 4096) return "";
            if (Eq(b, 3, "ReFS") && b[7] == 0) return "ReFS";
            if (U16(b, 1080) == 0xEF53) return ExtFlavor(b);
            if (Eq(b, 0, "XFSB")) return "XFS";
            if (Eq(b, 0, "LUKS") && b[4] == 0xBA && b[5] == 0xBE) return "LUKS";
            if (Eq(b, 32, "NXSB")) return "APFS";
            if (b[1024] == 0x48 && (b[1025] == 0x2B || b[1025] == 0x58) && b[1026] == 0 && (b[1027] == 4 || b[1027] == 5)) return "HFS+";
            if (U32(b, 1024) == 0xF2F52010u) return "F2FS";
            if (Eq(b, 512, "LABELONE")) return "LVM";
            byte[] bt = new byte[16];
            if (ReadDev(pos + 65536 + 64, bt, 0, 16) >= 8 && Eq(bt, 0, "_BHRfS_M")) return "Btrfs";
            return "";
        }

        static bool IsMsrGuid(byte[] e, int o)
        {
            byte[] g = new byte[] { 0x16, 0xE3, 0xC9, 0xE3, 0x5C, 0x0B, 0xB8, 0x4D, 0x81, 0x7D, 0xF9, 0x2D, 0xF0, 0x02, 0x15, 0xAE };
            for (int i = 0; i < 16; i++) { if (e[o + i] != g[i]) return false; }
            return true;
        }

        void AddPart(List<RcPartInfo> res, long start, long length, string kind)
        {
            if (start < 0 || length <= 0) return;
            if (devLength > 0 && start >= devLength) return;
            RcPartInfo pi = new RcPartInfo();
            pi.Start = start;
            pi.Length = length;
            pi.Kind = kind;
            byte[] pb = new byte[4096];
            if (ReadDev(start, pb, 0, 4096) >= 512) pi.Fs = SniffFsAt(start, pb);
            pi.Index = res.Count;
            res.Add(pi);
        }

        // Genişletilmiş bölümdeki mantıksal bölümler (EBR zinciri)
        void AddLogical(List<RcPartInfo> res, long extLba)
        {
            long cur = extLba;
            byte[] eb = new byte[512];
            for (int guard = 0; guard < 128; guard++)
            {
                if (ReadDev(cur * 512L, eb, 0, 512) < 512 || eb[510] != 0x55 || eb[511] != 0xAA) break;
                int t1 = eb[446 + 4];
                long rel1 = U32(eb, 446 + 8);
                long cnt1 = U32(eb, 446 + 12);
                if (t1 != 0 && cnt1 > 0 && t1 != 0x05 && t1 != 0x0F && t1 != 0x85) AddPart(res, (cur + rel1) * 512L, cnt1 * 512L, "MBR:" + t1.ToString("X2"));
                int t2 = eb[446 + 16 + 4];
                long rel2 = U32(eb, 446 + 16 + 8);
                if ((t2 == 0x05 || t2 == 0x0F || t2 == 0x85) && rel2 > 0) cur = extLba + rel2; else break;
            }
        }

        // GUID bölüm tablosu; bulunamazsa false
        bool AddGpt(List<RcPartInfo> res)
        {
            byte[] h = new byte[512];
            int ss = 512;
            if (!(ReadDev(512, h, 0, 512) >= 512 && Eq(h, 0, "EFI PART")))
            {
                if (ReadDev(4096, h, 0, 512) >= 512 && Eq(h, 0, "EFI PART")) ss = 4096; else return false;
            }
            long entLba = (long)U64(h, 72);
            long cnt = U32(h, 80);
            long esz = U32(h, 84);
            if (esz < 128 || esz > 1024 || cnt <= 0 || cnt > 256 || entLba <= 1 || entLba > (1L << 40)) return false;
            byte[] e = new byte[cnt * esz];
            int got = ReadDev(entLba * ss, e, 0, e.Length);
            for (int i = 0; i < cnt && (i + 1) * esz <= got; i++)
            {
                int o = (int)(i * esz);
                bool empty = true;
                for (int k = 0; k < 16; k++) { if (e[o + k] != 0) { empty = false; break; } }
                if (empty) continue;
                long first = (long)U64(e, o + 32);
                long last = (long)U64(e, o + 40);
                if (first <= 0 || last < first || last > (1L << 50)) continue;
                if (IsMsrGuid(e, o)) continue;
                AddPart(res, first * ss, (last - first + 1) * ss, "GPT");
            }
            return true;
        }

        // Bölüm tablosundaki (MBR, genişletilmiş bölümler, GPT) tüm bölümler; dosya sistemi tanınmasa da listelenir.
        List<RcPartInfo> FindPartitions(byte[] b0)
        {
            List<RcPartInfo> res = new List<RcPartInfo>();
            if (b0.Length < 512 || b0[510] != 0x55 || b0[511] != 0xAA) return res;
            bool gpt = false;
            List<RcPartInfo> mbr = new List<RcPartInfo>();
            for (int i = 0; i < 4; i++)
            {
                int o = 446 + 16 * i;
                int type = b0[o + 4];
                long lba = U32(b0, o + 8);
                long cnt = U32(b0, o + 12);
                if (type == 0xEE) { gpt = true; continue; }
                if (type == 0 || lba == 0 || cnt == 0) continue;
                if (type == 0x05 || type == 0x0F || type == 0x85) { AddLogical(mbr, lba); continue; }
                AddPart(mbr, lba * 512L, cnt * 512L, "MBR:" + type.ToString("X2"));
            }
            if (gpt)
            {
                List<RcPartInfo> g = new List<RcPartInfo>();
                if (AddGpt(g)) return g;
            }
            return mbr;
        }

        // Kaynağın ilk sektörlerinden bölüm düzenini çıkarır. Dönüş: ilk 4096 bayt; fs: kaynağın başındaki dosya sistemi ("" = bölüm tablosu ya da tanınmayan veri)
        byte[] LoadLayout()
        {
            byte[] b = new byte[4096];
            int n = ReadDev(0, b, 0, 4096);
            if (n < 512) throw new IOException("Kaynak okunamadı (boş ya da erişilemiyor).");
            parts.Clear();
            string fs = SniffFsAt(0, b);
            if (fs == "")
            {
                parts.AddRange(FindPartitions(b));
                for (int i = 0; i < parts.Count; i++) parts[i].Index = i;
            }
            else
            {
                RcPartInfo pi = new RcPartInfo();
                pi.Index = 0;
                pi.Start = 0;
                pi.Length = devLength > 0 ? devLength : 0;
                pi.Fs = fs;
                pi.Kind = "birim";
                parts.Add(pi);
            }
            return b;
        }

        void Detect(int partition)
        {
            byte[] b = LoadLayout();
            string fs;
            bool whole = false;
            if (partition == -1)
            {
                // Tüm disk: bölüm düzenine bakılmaz, kaynağın tamamı dosya imzalarıyla taranır (silinmiş ya da kaybolmuş bölümlerden dosya bulmak için)
                PartitionCount = parts.Count > 0 ? parts.Count : 1;
                fs = "";
                whole = true;
                partLength = devLength > 0 ? devLength : 0;
            }
            else if (parts.Count == 1 && parts[0].Start == 0 && parts[0].Kind == "birim")
            {
                PartitionCount = 1;
                if (partition > 0) throw new IOException("Bölüm bulunamadı: bu kaynakta tek bir birim var.");
                fs = parts[0].Fs;
                partLength = devLength > 0 ? devLength : 0;
            }
            else if (parts.Count > 0)
            {
                PartitionCount = parts.Count;
                if (partition < 0 || partition >= parts.Count) throw new IOException("Bölüm bulunamadı: " + (partition + 1) + ". bölüm yok (kaynakta " + parts.Count + " bölüm var).");
                RcPartInfo pick = parts[partition];
                baseOffset = pick.Start;
                partLength = pick.Length;
                fs = pick.Fs;
                b = new byte[4096];
                if (ReadDev(baseOffset, b, 0, 4096) < 512) throw new IOException("Bölümün başı okunamadı.");
            }
            else
            {
                // bölüm tablosu da dosya sistemi de yok: tüm kaynak ham taranır
                PartitionCount = 1;
                if (partition > 0) throw new IOException("Bölüm bulunamadı: bu kaynakta bölüm tablosu yok.");
                fs = "";
                partLength = devLength > 0 ? devLength : 0;
            }
            if (devLength > 0 && partLength > 0 && baseOffset + partLength > devLength) partLength = devLength - baseOffset;
            if (fs == "BITLOCKER") throw new IOException("Sürücü BitLocker ile kilitli. Önce sürücünün kilidini açın.");
            if (fs == "LUKS") throw new IOException("Bölüm LUKS ile şifrelenmiş; parola olmadan içeriği okunamaz ve kurtarılamaz.");
            Fs = fs;
            try
            {
                if (fs == "NTFS") { InitNtfs(b); Method = "mft"; HasNames = true; }
                else if (fs == "FAT32") { InitFat32(b); Method = "fat"; HasNames = true; }
                else if (fs == "FAT16" || fs == "FAT12") { InitFat16(b); Method = "fat"; HasNames = true; }
                else if (fs == "exFAT") { InitExfat(b); Method = "exfat"; HasNames = true; }
                else if (fs == "ext2" || fs == "ext3" || fs == "ext4") { InitExt(b); Method = "free"; }
                else
                {
                    InitRaw(whole ? "Tüm disk" : fs);
                    if (whole)
                    {
                        OpenNote = "Tüm disk, bölüm düzenine bakılmadan dosya imzalarına göre taranıyor. Silinmiş ya da kaybolmuş bölümlerden kalan dosyalar da bulunabilir; dosya adları ve klasörler okunamaz, var olan dosyalar da listelenebilir.";
                        int enc = 0;
                        foreach (RcPartInfo q in parts) { if (q.Fs == "BITLOCKER" || q.Fs == "LUKS") enc++; }
                        if (enc > 0) OpenNote += " Şifrelenmiş " + enc + " bölüm var (BitLocker ya da LUKS); bunların içindeki dosyalar şifreli olduğundan imzayla bulunamaz, önce kilitleri açılmalıdır.";
                    }
                    else if (fs == "") OpenNote = "Dosya sistemi tanınamadı; tüm alan dosya imzalarına göre taranıyor. Silinmiş dosyalarla birlikte var olan dosyalar da listelenebilir.";
                    else OpenNote = fs + " dosya sisteminde silinmiş kayıtlar okunamıyor; tüm alan dosya imzalarına göre taranıyor. Silinmiş dosyalarla birlikte var olan dosyalar da listelenebilir.";
                }
            }
            catch (Exception ex)
            {
                if (RawMode || ex is OperationCanceledException) throw;
                // dosya sistemi yapısı bozuk: tüm alanı imza ile tara
                string why = (ex is IOException) ? ex.Message.TrimEnd('.') : "yapı çözümlenemedi";
                ResetStructures();
                InitRaw(fs);
                OpenNote = fs + " dosya sistemi bozuk görünüyor (" + why + "). Tüm alan dosya imzalarına göre taranıyor; var olan dosyalar da listelenebilir.";
            }
            StatFreeBytes = CountFreeClusters() * ClusterSize;
        }

        void ResetStructures()
        {
            bitmap = new byte[0];
            mftRuns = new List<RcRun>();
            mftSize = 0;
            firstCluster = 0;
            dataStart = 0;
            ClusterSize = 0;
            ClusterCount = 0;
            VolumeBytes = 0;
            RecSize = 0;
            fatKind = 0;
            Method = "";
            HasNames = false;
        }

        // Dosya sistemi tanınmayan ya da bozuk alan: tamamı "boş" sayılır ve imza ile taranır.
        void InitRaw(string name)
        {
            long size = partLength;
            if (size <= 0 && devLength > 0) size = devLength - baseOffset;
            if (devLength > 0 && baseOffset + size > devLength) size = devLength - baseOffset;
            if (size < 4096) throw new IOException("Kaynağın boyutu okunamadı ya da çok küçük; tarama yapılamıyor.");
            bool modern = name == "ReFS" || name == "APFS" || name == "HFS+" || name == "Btrfs" || name == "XFS" || name == "F2FS" || name == "LVM";
            RawMode = true;
            Method = "raw";
            HasNames = false;
            Fs = name.Length > 0 ? name : "Bilinmeyen";
            ClusterSize = modern ? 4096 : 512;
            ClusterCount = size / ClusterSize;
            firstCluster = 0;
            dataStart = 0;
            VolumeBytes = size;
            bitmap = new byte[0];
        }

        long CountFreeClusters()
        {
            if (RawMode) return ClusterCount;
            long free = 0;
            long full = ClusterCount >> 3;
            if (full > bitmap.Length) full = bitmap.Length;
            for (long i = 0; i < full; i++)
            {
                int v = bitmap[i];
                v = v - ((v >> 1) & 0x55);
                v = (v & 0x33) + ((v >> 2) & 0x33);
                v = (v + (v >> 4)) & 0x0F;
                free += 8 - v;
            }
            for (long c = firstCluster + (full << 3); c < firstCluster + ClusterCount; c++) { if (!IsUsed(c)) free++; }
            return free;
        }

        // ---------------- NTFS ----------------
        sealed class DataPart
        {
            public long StartVcn;
            public List<RcRun> Runs;
        }

        sealed class NtRec
        {
            public long Num;
            public bool InUse;
            public bool IsDir;
            public int Seq;
            public long BaseRef;
            public long ParentRef;
            public string Name = "";
            public int NameRank;
            public long SizeFn;
            public long Created;
            public long Modified;
            public long MftChanged;
            public long FnModified;
            public bool HasData;
            public bool DataResident;
            public int DataOff;
            public int DataLen;
            public long RealSize;
            public long InitSize;
            public List<RcRun> Runs;
            public List<DataPart> More = new List<DataPart>();
            public bool Compressed;
            public bool Encrypted;
            public bool BadData;
            public bool HasAttrList;
            public bool AttrListResident;
            public int AttrOff;
            public int AttrLen;
            public byte[] Raw;
        }

        sealed class DirInfo
        {
            public string Name;
            public long ParentRec;
            public int ParentSeq;
            public int Seq;
            public bool InUse;
        }

        void RequireNtfs()
        {
            if (Fs != "NTFS") throw new IOException("Bu işlem yalnızca NTFS sürücülerde yapılabilir.");
        }

        void InitNtfs(byte[] b)
        {
            int bps = U16(b, 11);
            sbyte spc = (sbyte)b[13];
            if (bps < 512 || bps > 4096 || (bps & (bps - 1)) != 0) throw new IOException("NTFS önyükleme kaydı geçersiz.");
            long cs = 0;
            if (spc > 0) cs = (long)bps * spc;
            else if (spc < 0 && spc > -30) cs = 1L << (-spc);
            if (cs < 512 || cs > (64L << 20)) throw new IOException("NTFS küme boyutu geçersiz.");
            ClusterSize = cs;
            long totalSectors = (long)U64(b, 40);
            ClusterCount = totalSectors * bps / cs;
            if (ClusterCount <= 0) throw new IOException("NTFS birim boyutu geçersiz.");
            long mftLcn = (long)U64(b, 48);
            sbyte rc = (sbyte)b[64];
            if (rc > 0) RecSize = (int)(rc * cs);
            else if (rc < 0 && rc > -20) RecSize = 1 << (-rc);
            else RecSize = 0;
            if (RecSize < 512 || RecSize > 65536) throw new IOException("NTFS kayıt boyutu geçersiz.");
            firstCluster = 0;
            dataStart = 0;
            VolumeBytes = ClusterCount * cs;
            if (mftLcn <= 0 || mftLcn >= ClusterCount) throw new IOException("MFT konumu geçersiz.");
            byte[] r0 = new byte[RecSize];
            if (ReadVol(mftLcn * cs, r0, 0, RecSize) < RecSize) throw new IOException("Dosya tablosu (MFT) okunamadı.");
            NtRec m = ParseNtRec(r0, 0, 0, true, true);
            if (m == null || !m.HasData || m.DataResident || m.Runs == null || m.Runs.Count == 0) throw new IOException("Dosya tablosu (MFT) okunamadı.");
            mftRuns = m.Runs;
            mftSize = m.RealSize;
            if (m.HasAttrList)
            {
                List<RcRun> whole = FinalRuns(m);
                if (whole != null) mftRuns = whole;
            }
            NtRec bm = ReadNtRec(6, true, true);
            if (bm == null || !bm.HasData || bm.DataResident) throw new IOException("Küme haritası ($Bitmap) okunamadı.");
            List<RcRun> bmRuns = FinalRuns(bm);
            if (bmRuns == null) throw new IOException("Küme haritası ($Bitmap) okunamadı.");
            long need = (ClusterCount + 7) / 8;
            if (need > (1500L << 20)) throw new IOException("Sürücü bu sürüm için çok büyük.");
            long have = Math.Min(need, bm.RealSize);
            bitmap = new byte[have];
            ReadRuns(bmRuns, 0, bitmap, 0, (int)have, bm.RealSize);
        }

        static int NsRank(int ns)
        {
            if (ns == 1 || ns == 3) return 3;
            if (ns == 0) return 2;
            return 1;
        }

        // Çalışma kopyası üzerinde güncelleme dizisi (fixup) uygular ve öznitelikleri okur.
        NtRec ParseNtRec(byte[] buf, int off, long num, bool decodeData, bool keepRaw)
        {
            if (off < 0 || off + RecSize > buf.Length) return null;
            if (!(buf[off] == 0x46 && buf[off + 1] == 0x49 && buf[off + 2] == 0x4C && buf[off + 3] == 0x45)) return null;
            int usaOff = U16(buf, off + 4);
            int usaCnt = U16(buf, off + 6);
            if (usaOff < 42 || usaCnt < 2 || usaOff + usaCnt * 2 > RecSize) return null;
            byte[] r = new byte[RecSize];
            Buffer.BlockCopy(buf, off, r, 0, RecSize);
            int usn = U16(r, usaOff);
            for (int i = 1; i < usaCnt; i++)
            {
                int end = i * 512 - 2;
                if (end + 2 > RecSize) break;
                if (U16(r, end) != usn) return null;
                r[end] = r[usaOff + 2 * i];
                r[end + 1] = r[usaOff + 2 * i + 1];
            }
            NtRec x = new NtRec();
            x.Num = num;
            int flags = U16(r, 0x16);
            x.InUse = (flags & 1) != 0;
            x.IsDir = (flags & 2) != 0;
            x.Seq = U16(r, 0x10);
            x.BaseRef = (long)(U64(r, 0x20) & 0x0000FFFFFFFFFFFFUL);
            int p = U16(r, 0x14);
            int used = (int)Math.Min((long)U32(r, 0x18), (long)RecSize);
            int guard = 0;
            while (p + 16 <= used && guard++ < 64)
            {
                uint type = U32(r, p);
                if (type == 0xFFFFFFFFu) break;
                int len = (int)U32(r, p + 4);
                if (len < 16 || p + len > used) break;
                bool nonRes = r[p + 8] != 0;
                int nameLen = r[p + 9];
                int aflags = U16(r, p + 12);
                if (type == 0x10u && !nonRes)
                {
                    int co = p + U16(r, p + 20);
                    int cl = (int)U32(r, p + 16);
                    if (cl >= 32 && co >= p && co + cl <= p + len)
                    {
                        x.Created = (long)U64(r, co);
                        x.Modified = (long)U64(r, co + 8);
                        x.MftChanged = (long)U64(r, co + 16);
                    }
                }
                else if (type == 0x30u && !nonRes)
                {
                    int co = p + U16(r, p + 20);
                    int cl = (int)U32(r, p + 16);
                    if (cl >= 66 && co >= p && co + cl <= p + len)
                    {
                        int nl = r[co + 64];
                        int ns = r[co + 65];
                        if (nl > 0 && co + 66 + nl * 2 <= p + len)
                        {
                            int rank = NsRank(ns);
                            if (rank > x.NameRank)
                            {
                                x.NameRank = rank;
                                x.Name = Encoding.Unicode.GetString(r, co + 66, nl * 2);
                                x.ParentRef = (long)U64(r, co);
                                x.SizeFn = (long)U64(r, co + 48);
                                x.FnModified = (long)U64(r, co + 16);
                            }
                        }
                    }
                }
                else if (type == 0x20u)
                {
                    x.HasAttrList = true;
                    if (!nonRes)
                    {
                        x.AttrListResident = true;
                        x.AttrOff = p + U16(r, p + 20);
                        x.AttrLen = (int)U32(r, p + 16);
                        if (x.AttrOff < p || x.AttrOff + x.AttrLen > p + len) { x.AttrLen = 0; x.BadData = true; }
                    }
                }
                else if (type == 0x80u && nameLen == 0)
                {
                    if (!nonRes)
                    {
                        x.HasData = true;
                        x.DataResident = true;
                        x.DataLen = (int)U32(r, p + 16);
                        x.DataOff = p + U16(r, p + 20);
                        if (x.DataOff < p || x.DataLen < 0 || x.DataOff + x.DataLen > p + len) { x.DataLen = 0; x.BadData = true; }
                        x.RealSize = x.DataLen;
                        x.InitSize = x.DataLen;
                        if ((aflags & 0x4000) != 0) x.Encrypted = true;
                        if ((aflags & 0x0001) != 0) x.Compressed = true;
                    }
                    else
                    {
                        long startVcn = (long)U64(r, p + 16);
                        if (startVcn == 0)
                        {
                            x.HasData = true;
                            x.DataResident = false;
                            x.RealSize = (long)U64(r, p + 48);
                            x.InitSize = (long)U64(r, p + 56);
                            if ((aflags & 0x0001) != 0) x.Compressed = true;
                            if ((aflags & 0x4000) != 0) x.Encrypted = true;
                            if (decodeData)
                            {
                                int ro = U16(r, p + 32);
                                x.Runs = DecodeRuns(r, p + ro, p + len);
                                if (x.Runs == null) x.BadData = true;
                            }
                        }
                        else if (decodeData)
                        {
                            DataPart dp = new DataPart();
                            dp.StartVcn = startVcn;
                            int ro = U16(r, p + 32);
                            dp.Runs = DecodeRuns(r, p + ro, p + len);
                            if (dp.Runs == null) x.BadData = true; else x.More.Add(dp);
                        }
                    }
                }
                p += len;
            }
            if (x.Modified == 0) x.Modified = x.FnModified;
            if (keepRaw) x.Raw = r;
            return x;
        }

        List<RcRun> DecodeRuns(byte[] r, int p, int end)
        {
            List<RcRun> runs = new List<RcRun>();
            long lcn = 0;
            if (p < 0 || end > r.Length) return null;
            while (p < end)
            {
                int h = r[p];
                if (h == 0) break;
                int lenSz = h & 0x0F;
                int offSz = h >> 4;
                p++;
                if (lenSz == 0 || lenSz > 8 || offSz > 8 || p + lenSz + offSz > end) return null;
                long len = 0;
                for (int i = 0; i < lenSz; i++) len |= (long)r[p + i] << (8 * i);
                p += lenSz;
                if (len <= 0) return null;
                if (offSz == 0)
                {
                    runs.Add(new RcRun(-1, len));
                }
                else
                {
                    long delta = 0;
                    for (int i = 0; i < offSz; i++) delta |= (long)r[p + i] << (8 * i);
                    if (offSz < 8 && (r[p + offSz - 1] & 0x80) != 0) delta -= 1L << (8 * offSz);
                    p += offSz;
                    lcn += delta;
                    if (lcn < 0 || lcn + len > ClusterCount) return null;
                    runs.Add(new RcRun(lcn, len));
                }
            }
            return runs;
        }

        NtRec ReadNtRec(long num, bool decodeData, bool keepRaw)
        {
            long pos = num * RecSize;
            if (num < 0 || pos + RecSize > mftSize) return null;
            byte[] b = new byte[RecSize];
            if (ReadRuns(mftRuns, pos, b, 0, RecSize, mftSize) < RecSize) return null;
            return ParseNtRec(b, 0, num, decodeData, keepRaw);
        }

        // Küme listesinden (veri akışı) okur.
        int ReadRuns(List<RcRun> runs, long dataPos, byte[] dst, int off, int count, long limit)
        {
            if (dataPos < 0 || dataPos >= limit || count <= 0) return 0;
            if (dataPos + count > limit) count = (int)(limit - dataPos);
            int done = 0;
            long runStart = 0;
            foreach (RcRun r in runs)
            {
                long runBytes = r.Len * ClusterSize;
                long runEnd = runStart + runBytes;
                if (dataPos + done < runEnd)
                {
                    while (done < count && dataPos + done < runEnd)
                    {
                        long within = dataPos + done - runStart;
                        int n = (int)Math.Min((long)(count - done), runBytes - within);
                        if (r.Lcn < 0) Array.Clear(dst, off + done, n);
                        else
                        {
                            int got = ReadVol(ClusterOffset(r.Lcn) + within, dst, off + done, n);
                            if (got < n) Array.Clear(dst, off + done + got, n - got);
                        }
                        done += n;
                    }
                    if (done >= count) break;
                }
                runStart = runEnd;
            }
            return done;
        }

        // Ek kayıtlardaki ($ATTRIBUTE_LIST) veri parçalarını toplar ve uçtan uca küme listesini verir.
        List<RcRun> FinalRuns(NtRec x)
        {
            if (x.BadData) return null;
            List<DataPart> parts = new List<DataPart>();
            if (x.Runs != null) { DataPart d0 = new DataPart(); d0.StartVcn = 0; d0.Runs = x.Runs; parts.Add(d0); }
            foreach (DataPart m in x.More) parts.Add(m);
            if (x.HasAttrList && x.AttrListResident && x.Raw != null && x.AttrLen > 0)
            {
                int p = x.AttrOff;
                int end = x.AttrOff + x.AttrLen;
                int guard = 0;
                while (p + 26 <= end && guard++ < 4096)
                {
                    uint type = U32(x.Raw, p);
                    int rl = U16(x.Raw, p + 4);
                    if (rl < 26 || p + rl > end) break;
                    int nl = x.Raw[p + 6];
                    if (type == 0x80u && nl == 0)
                    {
                        long vcn = (long)U64(x.Raw, p + 8);
                        long rec = (long)(U64(x.Raw, p + 16) & 0x0000FFFFFFFFFFFFUL);
                        if (rec != x.Num)
                        {
                            NtRec e = ReadNtRec(rec, true, false);
                            if (e == null || e.BaseRef != x.Num) return null;
                            if (e.BadData) return null;
                            if (vcn == 0 && e.Runs != null)
                            {
                                DataPart d1 = new DataPart(); d1.StartVcn = 0; d1.Runs = e.Runs; parts.Add(d1);
                                if (!x.HasData && e.HasData) { x.HasData = true; x.RealSize = e.RealSize; x.InitSize = e.InitSize; }
                                if (e.Compressed) x.Compressed = true;
                                if (e.Encrypted) x.Encrypted = true;
                            }
                            foreach (DataPart m2 in e.More) { if (m2.StartVcn == vcn) parts.Add(m2); }
                        }
                    }
                    p += rl;
                }
            }
            if (parts.Count == 0) return null;
            parts.Sort(delegate(DataPart a, DataPart b) { return a.StartVcn.CompareTo(b.StartVcn); });
            List<RcRun> all = new List<RcRun>();
            long next = 0;
            foreach (DataPart d in parts)
            {
                if (d.StartVcn != next) return null;
                foreach (RcRun r in d.Runs) { all.Add(r); next += r.Len; }
            }
            return all;
        }

        static string BuildPath(Dictionary<long, DirInfo> dirs, long parentRef)
        {
            long cur = parentRef & 0x0000FFFFFFFFFFFFL;
            int seq = (int)((parentRef >> 48) & 0xFFFF);
            List<string> parts = new List<string>();
            int guard = 0;
            while (guard++ < 64)
            {
                if (cur == 5) break;
                DirInfo d;
                if (!dirs.TryGetValue(cur, out d)) { parts.Add("[bilinmeyen klasör]"); break; }
                bool ok = (d.Seq == seq) || (!d.InUse && d.Seq == ((seq + 1) & 0xFFFF));
                if (!ok) { parts.Add("[bilinmeyen klasör]"); break; }
                parts.Add(d.Name);
                cur = d.ParentRec;
                seq = d.ParentSeq;
            }
            parts.Reverse();
            return String.Join("\\", parts.ToArray());
        }

        long FreeInRange(long lcn, long n)
        {
            long c = 0;
            for (long i = 0; i < n; i++) { if (!IsUsed(lcn + i)) c++; }
            return c;
        }

        int ChanceOf(List<RcRun> runs, long size)
        {
            long need = (size + ClusterSize - 1) / ClusterSize;
            if (need <= 0) return 100;
            long free = 0;
            long seen = 0;
            foreach (RcRun r in runs)
            {
                if (seen >= need) break;
                long take = Math.Min(r.Len, need - seen);
                if (r.Lcn < 0) free += take;
                else
                {
                    if (r.Lcn + take > ClusterCount) return 0;
                    free += FreeInRange(r.Lcn, take);
                }
                seen += take;
            }
            if (seen < need) return 0;
            int ch = (int)(free * 100 / need);
            if (free > 0 && ch == 0) ch = 1;
            if (free < need && ch >= 100) ch = 99;
            return ch;
        }

        static bool IsNoiseName(string n)
        {
            if (n.Length == 0) return true;
            if (n[0] == '$') return !(n.Length > 2 && (n[1] == 'R' || n[1] == 'r'));
            return false;
        }

        static string ExtOf(string name)
        {
            int i = name.LastIndexOf('.');
            if (i < 0 || i == name.Length - 1 || name.Length - i > 9) return "";
            return name.Substring(i + 1).ToLowerInvariant();
        }

        // Silinmiş kayıtları bulur: NTFS (dosya tablosu), FAT (klasör girdileri) ya da exFAT (girdi kümeleri).
        // Dosya adı bilgisi taşımayan biçimlerde (ext, ham tarama) boş liste döner; onlar için Carve kullanılır.
        public List<RcItem> ScanDeleted(RcProgress prog, int maxItems)
        {
            if (Method == "fat") return ScanFatDeleted(prog, maxItems);
            if (Method == "exfat") return ScanExfatDeleted(prog, maxItems);
            if (Method != "mft") return new List<RcItem>();
            return ScanNtfsDeleted(prog, maxItems);
        }

        // Silinmiş NTFS dosya kayıtlarını bulur. Dosyanın küme alanı hâlâ boşsa kurtarma şansı yüksektir.
        List<RcItem> ScanNtfsDeleted(RcProgress prog, int maxItems)
        {
            RequireNtfs();
            List<RcItem> res = new List<RcItem>();
            Dictionary<long, DirInfo> dirs = new Dictionary<long, DirInfo>();
            List<NtRec> cands = new List<NtRec>();
            long total = mftSize / RecSize;
            int chunkRecs = (int)Math.Max(1L, (4L << 20) / RecSize);
            byte[] chunk = new byte[chunkRecs * RecSize];
            for (long first = 0; first < total; first += chunkRecs)
            {
                int cnt = (int)Math.Min((long)chunkRecs, total - first);
                int got = ReadRuns(mftRuns, first * RecSize, chunk, 0, cnt * RecSize, mftSize);
                int good = got / RecSize;
                for (int i = 0; i < good; i++)
                {
                    int off = i * RecSize;
                    // hızlı eleme: yalnızca "FILE" imzalı ana kayıtlardan klasörler ve kullanımda olmayan dosyalar ilgilidir
                    if (!(chunk[off] == 0x46 && chunk[off + 1] == 0x49 && chunk[off + 2] == 0x4C && chunk[off + 3] == 0x45)) continue;
                    int flags = U16(chunk, off + 0x16);
                    bool inUse = (flags & 1) != 0;
                    bool isDir = (flags & 2) != 0;
                    StatRecords++;
                    if ((U64(chunk, off + 0x20) & 0x0000FFFFFFFFFFFFUL) != 0) continue;
                    if (inUse && !isDir) continue;
                    long num = first + i;
                    NtRec r = ParseNtRec(chunk, off, num, true, false);
                    if (r == null) continue;
                    if (r.IsDir)
                    {
                        if (r.Name.Length == 0) continue;
                        DirInfo d = new DirInfo();
                        d.Name = r.Name;
                        d.ParentRec = r.ParentRef & 0x0000FFFFFFFFFFFFL;
                        d.ParentSeq = (int)((r.ParentRef >> 48) & 0xFFFF);
                        d.Seq = r.Seq;
                        d.InUse = r.InUse;
                        dirs[num] = d;
                    }
                    else if (num >= 16 && !IsNoiseName(r.Name))
                    {
                        cands.Add(r);
                    }
                }
                if (!Tick(prog, "Dosya tablosu okunuyor", first + cnt, total)) { Canceled = true; return res; }
            }
            long ci = 0;
            foreach (NtRec c in cands)
            {
                ci++;
                if ((ci & 255) == 0 && !Tick(prog, "Silinmiş dosyalar değerlendiriliyor", ci, cands.Count)) { Canceled = true; return res; }
                NtRec full = c;
                if (c.HasAttrList)
                {
                    if (!c.AttrListResident) { StatSkipped++; continue; }
                    NtRec again = ReadNtRec(c.Num, true, true);
                    if (again == null) { StatSkipped++; continue; }
                    full = again;
                }
                int chance = 0;
                long size = 0;
                List<RcRun> runs = null;
                if (full.HasData && full.DataResident)
                {
                    size = full.DataLen;
                    chance = full.BadData ? 0 : 100;
                }
                else
                {
                    if (full.HasData || full.HasAttrList) runs = FinalRuns(full);
                    if (runs == null || !full.HasData) { StatSkipped++; continue; }
                    size = full.RealSize;
                    chance = ChanceOf(runs, size);
                }
                if (full.Compressed || full.Encrypted) { StatSkipped++; continue; }
                if (size <= 0) { StatSkipped++; continue; }
                StatDeleted++;
                string note = "";
                if (chance == 0) note = "Disk alanı başka dosyalarca kullanılıyor; büyük olasılıkla üzerine yazılmış.";
                else if (chance < 100) note = "Disk alanı kısmen yeniden kullanılmış; dosya eksik ya da bozuk olabilir.";
                if (res.Count >= maxItems) { Truncated = true; break; }
                RcItem it = new RcItem();
                it.Kind = "mft";
                it.Rec = c.Num;
                it.Length = size;
                it.Name = c.Name;
                it.Path = BuildPath(dirs, c.ParentRef);
                it.Ext = ExtOf(c.Name);
                it.Modified = full.Modified;
                it.Deleted = full.MftChanged;
                it.Chance = chance;
                it.Note = note;
                res.Add(it);
                if (runs != null)
                {
                    foreach (RcRun rr in runs) { if (rr.Lcn >= 0) Own(rr.Lcn, rr.Lcn + rr.Len); }
                }
            }
            return res;
        }

        // Derin tarama sırasında, silinmiş dosya kaydı olan alanları yeniden saymamak için: başlangıç kümesi -> bitiş kümesi (dahil değil)
        readonly Dictionary<long, long> ownedEnd = new Dictionary<long, long>();

        void Own(long startCl, long endCl)
        {
            long cur;
            if (ownedEnd.TryGetValue(startCl, out cur)) { if (endCl > cur) ownedEnd[startCl] = endCl; }
            else ownedEnd[startCl] = endCl;
        }

        // ---------------- FAT32 / exFAT ----------------
        void InitFat16(byte[] b)
        {
            int bps = U16(b, 11);
            int spc = b[13];
            int rsv = U16(b, 14);
            int nfat = b[16];
            int rootEnt = U16(b, 17);
            long tot = U16(b, 19);
            if (tot == 0) tot = U32(b, 32);
            long fatSz = U16(b, 22);
            if (bps < 512 || bps > 4096 || (bps & (bps - 1)) != 0 || spc == 0 || (spc & (spc - 1)) != 0 || nfat < 1 || fatSz == 0 || rsv == 0) throw new IOException("FAT önyükleme kaydı geçersiz.");
            fatOff = (long)rsv * bps;
            fatBytesTotal = fatSz * bps;
            rootDirOff = (rsv + nfat * fatSz) * bps;
            rootDirBytes = (long)rootEnt * 32;
            ClusterSize = (long)bps * spc;
            long rootSec = ((long)rootEnt * 32 + bps - 1) / bps;
            long dataSec = rsv + nfat * fatSz + rootSec;
            if (tot <= dataSec) throw new IOException("FAT birim boyutu geçersiz.");
            ClusterCount = (tot - dataSec) / spc;
            dataStart = dataSec * bps;
            firstCluster = 2;
            VolumeBytes = tot * bps;
            bool fat12 = ClusterCount < 4085;
            Fs = fat12 ? "FAT12" : "FAT16";
            fatKind = fat12 ? 12 : 16;
            long entries = ClusterCount + 2;
            long fatBytes = fat12 ? (entries * 3 + 1) / 2 : entries * 2;
            if (fatBytes > fatSz * bps) fatBytes = fatSz * bps;
            byte[] fat = new byte[fatBytes];
            int got = ReadVol((long)rsv * bps, fat, 0, (int)fatBytes);
            bitmap = new byte[(ClusterCount + 7) / 8];
            for (long i = 0; i < ClusterCount; i++)
            {
                long n = i + 2;
                bool used = true;
                if (fat12)
                {
                    long idx = n + (n >> 1);
                    if (idx + 2 <= got)
                    {
                        int v = fat[idx] | (fat[idx + 1] << 8);
                        v = (n & 1) != 0 ? (v >> 4) : (v & 0x0FFF);
                        used = v != 0;
                    }
                }
                else
                {
                    long idx = n * 2;
                    if (idx + 2 <= got) used = U16(fat, (int)idx) != 0;
                }
                if (used) bitmap[i >> 3] |= (byte)(1 << (int)(i & 7));
            }
        }

        void InitFat32(byte[] b)
        {
            int bps = U16(b, 11);
            int spc = b[13];
            int rsv = U16(b, 14);
            int nfat = b[16];
            long tot = U32(b, 32);
            long fatSz = U32(b, 36);
            if (bps < 512 || bps > 4096 || (bps & (bps - 1)) != 0 || spc == 0 || (spc & (spc - 1)) != 0 || nfat < 1 || fatSz == 0 || rsv == 0) throw new IOException("FAT32 önyükleme kaydı geçersiz.");
            fatKind = 32;
            fatOff = (long)rsv * bps;
            fatBytesTotal = fatSz * bps;
            rootCluster = U32(b, 44);
            ClusterSize = (long)bps * spc;
            long dataSec = rsv + nfat * fatSz;
            if (tot <= dataSec) throw new IOException("FAT32 birim boyutu geçersiz.");
            ClusterCount = (tot - dataSec) / spc;
            dataStart = dataSec * bps;
            firstCluster = 2;
            VolumeBytes = tot * bps;
            long fatBytes = Math.Min((ClusterCount + 2) * 4, fatSz * bps);
            if (fatBytes > (1000L << 20)) throw new IOException("Sürücü bu sürüm için çok büyük.");
            byte[] fat = new byte[fatBytes];
            int got = ReadVol((long)rsv * bps, fat, 0, (int)fatBytes);
            bitmap = new byte[(ClusterCount + 7) / 8];
            for (long i = 0; i < ClusterCount; i++)
            {
                long idx = (i + 2) * 4;
                bool used = true;
                if (idx + 4 <= got) used = (U32(fat, (int)idx) & 0x0FFFFFFFu) != 0;
                if (used) bitmap[i >> 3] |= (byte)(1 << (int)(i & 7));
            }
        }

        // exFAT: kümeler FAT ile ya da ardışık (FAT girdisi 0) olabilir
        byte[] ReadExfatChain(long startCl, long maxBytes, long fatByteOff, long clusterCountLimit)
        {
            MemoryStream ms = new MemoryStream();
            long cl = startCl;
            byte[] cbuf = new byte[ClusterSize];
            byte[] ent = new byte[4];
            int guard = 0;
            while (cl >= 2 && cl < clusterCountLimit + 2 && ms.Length < maxBytes && guard++ < 4000000)
            {
                int n = ReadVol(ClusterOffset(cl), cbuf, 0, (int)ClusterSize);
                if (n < ClusterSize) break;
                ms.Write(cbuf, 0, (int)ClusterSize);
                long next = 0;
                if (ReadVol(fatByteOff + cl * 4, ent, 0, 4) == 4) next = U32(ent, 0);
                if (next == 0) next = cl + 1;
                if (next >= 0xFFFFFFF7L) break;
                cl = next;
            }
            return ms.ToArray();
        }

        void InitExfat(byte[] b)
        {
            int bpsShift = b[108];
            int spcShift = b[109];
            if (bpsShift < 9 || bpsShift > 12 || spcShift > 25 - bpsShift) throw new IOException("exFAT önyükleme kaydı geçersiz.");
            long bps = 1L << bpsShift;
            long spc = 1L << spcShift;
            ClusterSize = bps * spc;
            long fatSec = U32(b, 80);
            long heapOff = U32(b, 88);
            long cnt = U32(b, 92);
            long rootCl = U32(b, 96);
            if (cnt <= 0 || cnt > 0xFFFFFFF0L || heapOff <= 0) throw new IOException("exFAT birim boyutu geçersiz.");
            fatKind = 0;
            fatOff = fatSec * bps;
            fatBytesTotal = (long)U32(b, 84) * bps;
            exRootCl = rootCl;
            ClusterCount = cnt;
            dataStart = heapOff * bps;
            firstCluster = 2;
            VolumeBytes = (long)U64(b, 72) * bps;
            byte[] root = ReadExfatChain(rootCl, 4L << 20, fatOff, cnt);
            long bmCl = 0;
            long bmLen = 0;
            for (int o = 0; o + 32 <= root.Length; o += 32)
            {
                int t = root[o];
                if (t == 0) break;
                if (t == 0x81) { bmCl = U32(root, o + 20); bmLen = (long)U64(root, o + 24); break; }
            }
            if (bmCl < 2 || bmLen <= 0) throw new IOException("exFAT ayırma haritası bulunamadı.");
            long need = (cnt + 7) / 8;
            if (need > (1000L << 20)) throw new IOException("Sürücü bu sürüm için çok büyük.");
            byte[] bm = ReadExfatChain(bmCl, Math.Min(bmLen, need), fatOff, cnt);
            bitmap = new byte[need];
            Buffer.BlockCopy(bm, 0, bitmap, 0, (int)Math.Min((long)bm.Length, need));
            // okunamayan kısım dolu sayılır
            for (long i = bm.Length; i < need; i++) bitmap[i] = 0xFF;
        }

        // ---------------- imza taraması ----------------
        // Okuma penceresi: art arda okumalarda önbellek kullanır
        sealed class Rdr
        {
            readonly RcEngine e;
            public readonly long Limit;
            readonly byte[] win = new byte[1 << 16];
            long winStart = -1;
            int winLen;

            public Rdr(RcEngine eng, long limit) { e = eng; Limit = limit; }

            bool Ensure(long p)
            {
                if (p < 0 || p >= Limit) return false;
                if (winStart >= 0 && p >= winStart && p < winStart + winLen) return true;
                winStart = p - (p % 4096);
                long want = Math.Min((long)win.Length, Limit - winStart);
                winLen = want <= 0 ? 0 : e.ReadVol(winStart, win, 0, (int)want);
                return p >= winStart && p < winStart + winLen;
            }

            public int Peek(long p)
            {
                if (!Ensure(p)) return -1;
                return win[p - winStart];
            }

            public long U16BE(long p) { int a = Peek(p); int b = Peek(p + 1); if (a < 0 || b < 0) return -1; return (a << 8) | b; }
            public long U16LE(long p) { int a = Peek(p); int b = Peek(p + 1); if (a < 0 || b < 0) return -1; return (b << 8) | a; }
            public long U32BE(long p)
            {
                long v = 0;
                for (int i = 0; i < 4; i++) { int a = Peek(p + i); if (a < 0) return -1; v = (v << 8) | (long)(byte)a; }
                return v;
            }
            public long U32LE(long p)
            {
                long v = 0;
                for (int i = 3; i >= 0; i--) { int a = Peek(p + i); if (a < 0) return -1; v = (v << 8) | (long)(byte)a; }
                return v;
            }
            public long U64LE(long p)
            {
                long v = 0;
                for (int i = 7; i >= 0; i--) { int a = Peek(p + i); if (a < 0) return -1; v = (v << 8) | (long)(byte)a; }
                return v;
            }
            public long U64BE(long p)
            {
                long v = 0;
                for (int i = 0; i < 8; i++) { int a = Peek(p + i); if (a < 0) return -1; v = (v << 8) | (long)(byte)a; }
                return v;
            }

            public bool Match(long p, string s)
            {
                for (int i = 0; i < s.Length; i++) { if (Peek(p + i) != (int)s[i]) return false; }
                return true;
            }

            public byte[] Bytes(long p, int n)
            {
                if (p < 0 || p + n > Limit) return null;
                byte[] b = new byte[n];
                if (e.ReadVol(p, b, 0, n) < n) return null;
                return b;
            }

            // p'den başlayarak ilk 'v' baytının konumunu verir; yoksa -1
            public long FindByte(long p, byte v, long max)
            {
                if (max > Limit) max = Limit;
                while (p < max)
                {
                    if (!Ensure(p)) return -1;
                    int idx = (int)(p - winStart);
                    int lim = (int)Math.Min((long)winLen, max - winStart);
                    if (lim <= idx) return -1;
                    int f = Array.IndexOf(win, v, idx, lim - idx);
                    if (f >= 0) return winStart + f;
                    p = winStart + lim;
                }
                return -1;
            }
        }

        static string Sniff(byte[] b, int p, int avail)
        {
            if (avail < 16) return null;
            if (b[p] == 0xFF && b[p + 1] == 0xD8 && b[p + 2] == 0xFF && b[p + 3] >= 0xC0 && b[p + 3] != 0xFF) return "jpg";
            if (b[p] == 0x89 && b[p + 1] == 0x50 && b[p + 2] == 0x4E && b[p + 3] == 0x47 && b[p + 4] == 0x0D && b[p + 5] == 0x0A && b[p + 6] == 0x1A && b[p + 7] == 0x0A) return "png";
            if (b[p] == 0x47 && b[p + 1] == 0x49 && b[p + 2] == 0x46 && b[p + 3] == 0x38 && (b[p + 4] == 0x37 || b[p + 4] == 0x39) && b[p + 5] == 0x61) return "gif";
            if (b[p] == 0x42 && b[p + 1] == 0x4D && b[p + 6] == 0 && b[p + 7] == 0 && b[p + 8] == 0 && b[p + 9] == 0)
            {
                uint dib = U32(b, p + 14);
                if (dib == 12 || dib == 40 || dib == 52 || dib == 56 || dib == 64 || dib == 108 || dib == 124) return "bmp";
            }
            if (Eq(b, p, "%PDF-1.") || Eq(b, p, "%PDF-2.")) return "pdf";
            if (b[p] == 0x50 && b[p + 1] == 0x4B && b[p + 2] == 0x03 && b[p + 3] == 0x04 && b[p + 5] == 0 && b[p + 4] <= 63 && avail >= 30)
            {
                int method = U16(b, p + 8);
                int nameLen = U16(b, p + 26);
                bool okMethod = method == 0 || method == 8 || method == 9 || method == 12 || method == 14 || method == 93 || method == 95 || method == 98 || method == 99;
                if (okMethod && nameLen >= 1 && nameLen <= 512) return "zip";
            }
            if (b[p] == 0xD0 && b[p + 1] == 0xCF && b[p + 2] == 0x11 && b[p + 3] == 0xE0 && b[p + 4] == 0xA1 && b[p + 5] == 0xB1 && b[p + 6] == 0x1A && b[p + 7] == 0xE1) return "ole";
            if (Eq(b, p + 4, "ftyp") && b[p] == 0 && b[p + 1] == 0 && b[p + 2] == 0 && b[p + 3] >= 12 && b[p + 3] <= 64) return "mp4";
            if (Eq(b, p, "SQLite format 3") && b[p + 15] == 0) return "sqlite";
            if (b[p] == 0x37 && b[p + 1] == 0x7A && b[p + 2] == 0xBC && b[p + 3] == 0xAF && b[p + 4] == 0x27 && b[p + 5] == 0x1C) return "7z";
            if (Eq(b, p, "RIFF") && (Eq(b, p + 8, "WAVE") || Eq(b, p + 8, "AVI ") || Eq(b, p + 8, "WEBP"))) return "riff";
            return null;
        }

        static long MinLength(string t)
        {
            switch (t)
            {
                case "jpg": return 1024;
                case "png": return 67;
                case "gif": return 14;
                case "bmp": return 54;
                case "pdf": return 100;
                case "zip": return 100;
                case "mp4": return 1000;
                case "sqlite": return 512;
                case "7z": return 32;
                case "riff": return 44;
                case "ole": return 512;
            }
            return 1;
        }

        // Dosyanın bayt uzunluğunu yapısından çıkarır. Bulunamazsa -1.
        long Determine(string t, long start, Rdr r)
        {
            switch (t)
            {
                case "jpg": return DetJpeg(r, start);
                case "png": return DetPng(r, start);
                case "gif": return DetGif(r, start);
                case "bmp": return DetBmp(r, start);
                case "pdf": return DetPdf(r, start);
                case "zip": return DetZip(r, start);
                case "mp4": return DetMp4(r, start);
                case "sqlite": return DetSqlite(r, start);
                case "7z": return Det7z(r, start);
                case "riff": return DetRiff(r, start);
                case "ole": return DetOle(r, start);
            }
            return -1;
        }

        static long DetJpeg(Rdr r, long start)
        {
            long p = start + 2;
            bool sof = false;
            bool sos = false;
            int guard = 0;
            while (guard++ < 200000)
            {
                int b = r.Peek(p);
                if (b != 0xFF) return -1;
                int m = r.Peek(p + 1);
                while (m == 0xFF) { p++; m = r.Peek(p + 1); }
                if (m < 0) return -1;
                p += 2;
                if (m == 0xD9) return (sof && sos) ? p - start : -1;
                if (m == 0x00 || m == 0x01 || m == 0xD8 || (m >= 0xD0 && m <= 0xD7)) continue;
                long len = r.U16BE(p);
                if (len < 2) return -1;
                if (m >= 0xC0 && m <= 0xCF && m != 0xC4 && m != 0xC8 && m != 0xCC) sof = true;
                p += len;
                if (m == 0xDA)
                {
                    sos = true;
                    while (true)
                    {
                        int c = r.Peek(p);
                        if (c < 0) return -1;
                        if (c == 0xFF)
                        {
                            int d = r.Peek(p + 1);
                            if (d < 0) return -1;
                            if (d == 0x00 || (d >= 0xD0 && d <= 0xD7)) { p += 2; continue; }
                            break;
                        }
                        p++;
                    }
                }
            }
            return -1;
        }

        static bool IsAlpha(int c) { return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z'); }

        static long DetPng(Rdr r, long start)
        {
            long p = start + 8;
            bool first = true;
            int guard = 0;
            while (guard++ < 500000)
            {
                long len = r.U32BE(p);
                if (len < 0 || len > 0x7FFFFFFFL) return -1;
                int t0 = r.Peek(p + 4), t1 = r.Peek(p + 5), t2 = r.Peek(p + 6), t3 = r.Peek(p + 7);
                if (!IsAlpha(t0) || !IsAlpha(t1) || !IsAlpha(t2) || !IsAlpha(t3)) return -1;
                if (first)
                {
                    if (len != 13 || t0 != 'I' || t1 != 'H' || t2 != 'D' || t3 != 'R') return -1;
                    first = false;
                }
                p += 12 + len;
                if (p > r.Limit) return -1;
                if (t0 == 'I' && t1 == 'E' && t2 == 'N' && t3 == 'D') return p - start;
            }
            return -1;
        }

        static long SkipSub(Rdr r, long p)
        {
            int g = 0;
            while (g++ < 10000000)
            {
                int n = r.Peek(p);
                if (n < 0) return -1;
                p += 1;
                if (n == 0) return p;
                p += n;
            }
            return -1;
        }

        static long DetGif(Rdr r, long start)
        {
            long p = start + 6;
            int flags = r.Peek(p + 4);
            if (flags < 0) return -1;
            p += 7;
            if ((flags & 0x80) != 0) p += 3 * (1 << ((flags & 7) + 1));
            int guard = 0;
            while (guard++ < 1000000)
            {
                int b = r.Peek(p);
                if (b < 0) return -1;
                if (b == 0x3B) return p + 1 - start;
                if (b == 0x21) { p += 2; p = SkipSub(r, p); if (p < 0) return -1; continue; }
                if (b == 0x2C)
                {
                    int f = r.Peek(p + 9);
                    if (f < 0) return -1;
                    p += 10;
                    if ((f & 0x80) != 0) p += 3 * (1 << ((f & 7) + 1));
                    p += 1;
                    p = SkipSub(r, p);
                    if (p < 0) return -1;
                    continue;
                }
                return -1;
            }
            return -1;
        }

        static long DetBmp(Rdr r, long start)
        {
            long size = r.U32LE(start + 2);
            if (size < 54 || size > (1L << 29)) return -1;
            if (start + size > r.Limit) return -1;
            return size;
        }

        static bool IsDigit(int c) { return c >= '0' && c <= '9'; }

        static long DetPdf(Rdr r, long start)
        {
            long p = start + 8;
            long max = Math.Min(r.Limit, start + (128L << 20));
            long lastEnd = -1;
            while (p < max)
            {
                long q = r.FindByte(p, (byte)'%', max);
                if (q < 0) break;
                if (r.Match(q, "%%EOF"))
                {
                    long e = q + 5;
                    if (r.Peek(e) == '\r') e++;
                    if (r.Peek(e) == '\n') e++;
                    lastEnd = e;
                    // artımlı güncelleme: arkasından yeni nesneler / xref geliyorsa devam et
                    bool more = false;
                    if (r.Match(e, "xref") || r.Match(e, "trailer")) more = true;
                    else if (IsDigit(r.Peek(e)))
                    {
                        long k = e;
                        while (IsDigit(r.Peek(k)) && k < e + 10) k++;
                        if (r.Peek(k) == ' ')
                        {
                            k++;
                            long k2 = k;
                            while (IsDigit(r.Peek(k2)) && k2 < k + 6) k2++;
                            if (k2 > k && r.Peek(k2) == ' ' && r.Match(k2 + 1, "obj")) more = true;
                        }
                    }
                    if (!more) return lastEnd - start;
                    p = e;
                    continue;
                }
                if (r.Match(q, "%PDF-")) { return lastEnd > 0 ? lastEnd - start : -1; }
                p = q + 1;
            }
            return lastEnd > 0 ? lastEnd - start : -1;
        }

        static long DetZip(Rdr r, long start)
        {
            long p = start;
            long max = Math.Min(r.Limit, start + (1L << 30));
            int guard = 0;
            while (p + 22 <= max && guard++ < 50000000)
            {
                long q = r.FindByte(p, (byte)0x50, max);
                if (q < 0 || q + 22 > max) break;
                if (r.Peek(q + 1) == 0x4B && r.Peek(q + 2) == 0x05 && r.Peek(q + 3) == 0x06)
                {
                    long cdSize = r.U32LE(q + 12);
                    long cdOff = r.U32LE(q + 16);
                    long cl = r.U16LE(q + 20);
                    if (cdSize >= 0 && cdOff >= 0 && cl >= 0 && cdOff + cdSize == q - start && q + 22 + cl <= r.Limit) return q + 22 + cl - start;
                }
                p = q + 1;
            }
            return -1;
        }

        static bool ValidTopAtom(int a, int b, int c, int d)
        {
            string s = "" + (char)a + (char)b + (char)c + (char)d;
            switch (s)
            {
                case "ftyp": case "moov": case "mdat": case "free": case "skip": case "wide": case "uuid":
                case "meta": case "moof": case "mfra": case "sidx": case "styp": case "pdin": case "pnot":
                    return true;
            }
            return false;
        }

        static long DetMp4(Rdr r, long start)
        {
            long p = start;
            bool moov = false;
            bool mdat = false;
            int atoms = 0;
            while (atoms++ < 100000)
            {
                long size = r.U32BE(p);
                if (size < 0) break;
                int a = r.Peek(p + 4), b = r.Peek(p + 5), c = r.Peek(p + 6), d = r.Peek(p + 7);
                if (a < 0 || d < 0) break;
                if (size == 1) { size = r.U64BE(p + 8); }
                if (size < 8) break;
                if (!ValidTopAtom(a, b, c, d)) break;
                if (p + size > r.Limit) return -1;
                if (a == 'm' && b == 'o' && c == 'o' && d == 'v') moov = true;
                if (a == 'm' && b == 'o' && c == 'o' && d == 'f') moov = true;
                if (a == 'm' && b == 'd' && c == 'a' && d == 't') mdat = true;
                p += size;
            }
            if (!moov || !mdat || p <= start) return -1;
            return p - start;
        }

        static long DetSqlite(Rdr r, long start)
        {
            long ps = r.U16BE(start + 16);
            if (ps == 1) ps = 65536;
            if (ps < 512 || ps > 65536 || (ps & (ps - 1)) != 0) return -1;
            long pages = r.U32BE(start + 28);
            long chg = r.U32BE(start + 24);
            long vvf = r.U32BE(start + 92);
            if (pages <= 0 || chg != vvf) return -1;
            long len = pages * ps;
            if (len > (4L << 30) || start + len > r.Limit) return -1;
            return len;
        }

        static uint[] crcTable;

        static uint Crc32(byte[] data, int off, int len)
        {
            if (crcTable == null)
            {
                uint[] t = new uint[256];
                for (uint i = 0; i < 256; i++)
                {
                    uint c = i;
                    for (int k = 0; k < 8; k++) c = (c & 1) != 0 ? (0xEDB88320u ^ (c >> 1)) : (c >> 1);
                    t[i] = c;
                }
                crcTable = t;
            }
            uint crc = 0xFFFFFFFFu;
            for (int i = 0; i < len; i++) crc = crcTable[(crc ^ data[off + i]) & 0xFF] ^ (crc >> 8);
            return crc ^ 0xFFFFFFFFu;
        }

        static long Det7z(Rdr r, long start)
        {
            byte[] h = r.Bytes(start, 32);
            if (h == null) return -1;
            if (Crc32(h, 12, 20) != U32(h, 8)) return -1;
            long off = (long)U64(h, 12);
            long size = (long)U64(h, 20);
            if (off < 0 || size < 0 || off > (1L << 40) || size > (1L << 34)) return -1;
            long total = 32 + off + size;
            if (start + total > r.Limit) return -1;
            return total;
        }

        static long DetRiff(Rdr r, long start)
        {
            long size = r.U32LE(start + 4);
            if (size < 36 || size > 0xFFFFFFF0L) return -1;
            long total = size + 8;
            if (start + total > r.Limit) return -1;
            return total;
        }

        static long DetOle(Rdr r, long start)
        {
            if (r.U16LE(start + 0x1C) != 0xFFFE) return -1;
            long shift = r.U16LE(start + 0x1E);
            if (shift != 9 && shift != 12) return -1;
            long nFat = r.U32LE(start + 0x2C);
            if (nFat < 1 || nFat > 100000) return -1;
            long ss = 1L << (int)shift;
            long perFat = ss / 4;
            long difat = r.U32LE(start + 0x44);
            long nDifat = r.U32LE(start + 0x48);
            List<long> fatSecs = new List<long>();
            for (long i = 0; i < 109 && fatSecs.Count < nFat; i++)
            {
                long sec = r.U32LE(start + 0x4C + i * 4);
                if (sec >= 0 && sec < 0xFFFFFFFAL) fatSecs.Add(sec);
            }
            long guard = 0;
            while (fatSecs.Count < nFat && difat >= 0 && difat < 0xFFFFFFFAL && guard < nDifat && guard < 2000)
            {
                guard++;
                byte[] d = r.Bytes(start + (difat + 1) * ss, (int)ss);
                if (d == null) return -1;
                for (long i = 0; i < perFat - 1 && fatSecs.Count < nFat; i++)
                {
                    long sec = U32(d, (int)(i * 4));
                    if (sec < 0xFFFFFFFAL) fatSecs.Add(sec);
                }
                difat = U32(d, (int)((perFat - 1) * 4));
            }
            long maxIdx = -1;
            for (int i = 0; i < fatSecs.Count; i++)
            {
                byte[] fat = r.Bytes(start + (fatSecs[i] + 1) * ss, (int)ss);
                if (fat == null) return -1;
                for (long j = 0; j < perFat; j++)
                {
                    if (U32(fat, (int)(j * 4)) != 0xFFFFFFFFu) maxIdx = Math.Max(maxIdx, i * perFat + j);
                }
            }
            if (maxIdx < 0) return -1;
            long total = (maxIdx + 2) * ss;
            if (start + total > r.Limit) return -1;
            return total;
        }

        // Taranan dosyanın gerçek uzantısı (zip ve ole için içerikten)
        string ExtFor(string t, long start, long len)
        {
            if (t == "zip")
            {
                int headN = (int)Math.Min(len, 8192L);
                byte[] hb = new byte[headN];
                int hg = ReadVol(start, hb, 0, headN);
                int tailN = (int)Math.Min(len, 262144L);
                byte[] tb = new byte[tailN];
                int tg = ReadVol(start + len - tailN, tb, 0, tailN);
                string s1 = Encoding.ASCII.GetString(hb, 0, hg) + "\n" + Encoding.ASCII.GetString(tb, 0, tg);
                if (s1.IndexOf("word/document.xml", StringComparison.Ordinal) >= 0) return "docx";
                if (s1.IndexOf("xl/workbook.xml", StringComparison.Ordinal) >= 0) return "xlsx";
                if (s1.IndexOf("ppt/presentation.xml", StringComparison.Ordinal) >= 0) return "pptx";
                if (s1.IndexOf("application/vnd.oasis.opendocument.text", StringComparison.Ordinal) >= 0) return "odt";
                if (s1.IndexOf("application/vnd.oasis.opendocument.spreadsheet", StringComparison.Ordinal) >= 0) return "ods";
                if (s1.IndexOf("application/epub+zip", StringComparison.Ordinal) >= 0) return "epub";
                if (s1.IndexOf("AndroidManifest.xml", StringComparison.Ordinal) >= 0 && s1.IndexOf("classes.dex", StringComparison.Ordinal) >= 0) return "apk";
                if (s1.IndexOf("META-INF/MANIFEST.MF", StringComparison.Ordinal) >= 0) return "jar";
                return "zip";
            }
            if (t == "ole")
            {
                int n = (int)Math.Min(len, 8L << 20);
                byte[] b = new byte[n];
                int got = ReadVol(start, b, 0, n);
                if (HasUtf16(b, got, "WordDocument")) return "doc";
                if (HasUtf16(b, got, "Workbook") || HasUtf16(b, got, "Book")) return "xls";
                if (HasUtf16(b, got, "PowerPoint Document")) return "ppt";
                return "ole";
            }
            if (t == "riff")
            {
                byte[] b = new byte[12];
                ReadVol(start, b, 0, 12);
                if (Eq(b, 8, "WAVE")) return "wav";
                if (Eq(b, 8, "AVI ")) return "avi";
                return "webp";
            }
            return t;
        }

        static bool HasUtf16(byte[] b, int n, string s)
        {
            byte[] pat = Encoding.Unicode.GetBytes(s);
            int last = n - pat.Length;
            for (int i = 0; i <= last; i += 2)
            {
                if (b[i] != pat[0]) continue;
                bool ok = true;
                for (int k = 1; k < pat.Length; k++) { if (b[i + k] != pat[k]) { ok = false; break; } }
                if (ok) return true;
            }
            return false;
        }

        // Boş (ayrılmamış) kümelerde bilinen dosya imzalarını arar ve yapılarını doğrulayarak dosyaları çıkarır.
        // types: sniff türleri (jpg, png, gif, bmp, pdf, zip, ole, mp4, sqlite, 7z, riff); boş ise hepsi.
        public List<RcItem> Carve(string[] types, RcProgress prog, int maxItems)
        {
            List<RcItem> res = new List<RcItem>();
            HashSet<string> want = new HashSet<string>();
            if (types != null) { foreach (string t in types) { if (t != null && t.Length > 0) want.Add(t.ToLowerInvariant()); } }
            long chunkClusters = Math.Max(1L, (8L << 20) / ClusterSize);
            long last = firstCluster + ClusterCount;
            long totalFree = StatFreeBytes / ClusterSize;
            long doneFree = 0;
            long skipUntil = 0;
            int seqNo = 0;
            byte[] buf = new byte[chunkClusters * ClusterSize];
            long cl = firstCluster;
            while (cl < last)
            {
                // sıradaki boş bölgenin başı
                while (cl < last && IsUsed(cl))
                {
                    long i2 = cl - firstCluster;
                    if ((i2 & 7) == 0 && (i2 >> 3) < bitmap.Length && bitmap[i2 >> 3] == 0xFF) cl += 8; else cl++;
                }
                if (cl >= last) break;
                long runStart = cl;
                while (cl < last && !IsUsed(cl)) cl++;
                long runEnd = cl;
                long areaEnd = ClusterOffset(runEnd);
                Rdr rd = new Rdr(this, areaEnd);
                for (long c = runStart; c < runEnd; c += chunkClusters)
                {
                    long n = Math.Min(chunkClusters, runEnd - c);
                    int bytes = (int)(n * ClusterSize);
                    int got = ReadVol(ClusterOffset(c), buf, 0, bytes);
                    for (long k = 0; k < n; k++)
                    {
                        long cluster = c + k;
                        long off = ClusterOffset(cluster);
                        if (off < skipUntil) continue;
                        int pos = (int)(k * ClusterSize);
                        if (pos + 16 > got) break;
                        string t = Sniff(buf, pos, got - pos);
                        if (t == null) continue;
                        if (want.Count > 0 && !want.Contains(t)) continue;
                        long ownEnd;
                        if (ownedEnd.TryGetValue(cluster, out ownEnd))
                        {
                            long oe = ClusterOffset(ownEnd);
                            if (oe > skipUntil) skipUntil = oe;
                            continue;
                        }
                        long len = Determine(t, off, rd);
                        if (len < MinLength(t)) continue;
                        if (off + len > areaEnd) continue;
                        string ext = ExtFor(t, off, len);
                        if (res.Count >= maxItems) { Truncated = true; return res; }
                        RcItem it = new RcItem();
                        seqNo++;
                        it.Kind = "carve";
                        it.Offset = off;
                        it.Length = len;
                        it.Ext = ext;
                        it.Name = "kurtarilan_" + seqNo.ToString("D5") + "." + ext;
                        it.Path = "";
                        it.Chance = RawMode ? 75 : 85;
                        it.Note = RawMode ? "İmza taramasıyla bulundu; dosya adı ve tarihi bilinmiyor. Silinmiş mi, var olan bir dosya mı olduğu anlaşılamıyor." : "İmza taramasıyla bulundu; dosya adı ve tarihi bilinmiyor.";
                        res.Add(it);
                        skipUntil = off + ((len + ClusterSize - 1) / ClusterSize) * ClusterSize;
                    }
                    doneFree += n;
                    if (!Tick(prog, RawMode ? "Tüm alan taranıyor" : "Boş alan taranıyor", doneFree, totalFree)) { Canceled = true; return res; }
                }
            }
            return res;
        }

        // ---------------- kopyalama (yalnızca hedef akışa yazar) ----------------
        public long Extract(RcItem it, Stream dest)
        {
            return Extract(it, dest, null);
        }

        // prog çağrısı false dönerse OperationCanceledException fırlatılır.
        public long Extract(RcItem it, Stream dest, RcProgress prog)
        {
            LastNote = "";
            if (it.Kind == "carve") return CopyRange(it.Offset, it.Length, dest, prog);
            if (it.Kind == "fat")
            {
                CheckFatRange(it);
                long done = CopyRange(it.Offset, it.Length, dest, prog);
                if (LastNote.Length == 0 && it.Length > 4096 && HeadIsZero(it.Offset)) LastNote = "Dosyanın başı sıfırlarla dolu; veri silinmiş ya da SSD TRIM ile temizlenmiş olabilir.";
                return done;
            }
            RequireNtfs();
            NtRec r = ReadNtRec(it.Rec, true, true);
            if (r == null) throw new IOException("Dosya kaydı okunamadı.");
            if (r.InUse || !String.Equals(r.Name, it.Name, StringComparison.Ordinal)) throw new IOException("Bu kayıt yeniden kullanılmış; aynı numaralı kayıt artık başka bir dosyaya ait.");
            if (r.Compressed || r.Encrypted) throw new IOException("Dosya sıkıştırılmış ya da şifreli (EFS); kurtarılamaz.");
            if (r.HasData && r.DataResident)
            {
                if (r.BadData) throw new IOException("Dosya verisi okunamadı.");
                dest.Write(r.Raw, r.DataOff, r.DataLen);
                return r.DataLen;
            }
            List<RcRun> runs = FinalRuns(r);
            if (runs == null) throw new IOException("Dosyanın küme haritası eksik ya da bozuk.");
            return CopyRuns(runs, r.RealSize, r.InitSize, dest, prog);
        }

        long CopyRuns(List<RcRun> runs, long size, long initSize, Stream dest, RcProgress prog)
        {
            byte[] buf = new byte[1 << 20];
            long pos = 0;
            bool allZero = true;
            while (pos < size)
            {
                int want = (int)Math.Min((long)buf.Length, size - pos);
                int got = ReadRuns(runs, pos, buf, 0, want, size);
                if (got <= 0) break;
                if (pos < 65536 && allZero)
                {
                    int chk = (int)Math.Min((long)got, 65536 - pos);
                    for (int i = 0; i < chk; i++) { if (buf[i] != 0) { allZero = false; break; } }
                }
                if (initSize > 0 && initSize < size && pos + got > initSize)
                {
                    int z0 = (int)Math.Max(0L, initSize - pos);
                    Array.Clear(buf, z0, got - z0);
                }
                dest.Write(buf, 0, got);
                pos += got;
                if (!Tick(prog, "Kurtarılıyor", pos, size)) throw new OperationCanceledException();
            }
            if (size > 4096 && allZero) LastNote = "Dosyanın başı sıfırlarla dolu; veri silinmiş ya da SSD TRIM ile temizlenmiş olabilir.";
            return pos;
        }

        long CopyRange(long offset, long length, Stream dest, RcProgress prog)
        {
            byte[] buf = new byte[1 << 20];
            long pos = 0;
            while (pos < length)
            {
                int want = (int)Math.Min((long)buf.Length, length - pos);
                int got = ReadVol(offset + pos, buf, 0, want);
                if (got <= 0) break;
                dest.Write(buf, 0, got);
                pos += got;
                if (!Tick(prog, "Kurtarılıyor", pos, length)) throw new OperationCanceledException();
            }
            return pos;
        }

        // ---------------- hedef yolu yardımcıları ----------------
        public static string SafeName(string name)
        {
            if (name == null) name = "";
            StringBuilder sb = new StringBuilder();
            foreach (char ch in name)
            {
                if (ch < 32 || ch == '<' || ch == '>' || ch == ':' || ch == '"' || ch == '/' || ch == '\\' || ch == '|' || ch == '?' || ch == '*') sb.Append('_');
                else sb.Append(ch);
            }
            string s = sb.ToString().TrimEnd(' ', '.');
            s = s.TrimStart(' ');
            if (s.Length == 0 || s == "." || s == "..") s = "_" + s;
            string up = s.ToUpperInvariant();
            int dot = up.IndexOf('.');
            string stem = dot >= 0 ? up.Substring(0, dot) : up;
            string[] reserved = new string[] { "CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9" };
            foreach (string rsv in reserved) { if (stem == rsv) { s = "_" + s; break; } }
            if (s.Length > 120)
            {
                string ext = "";
                int di = s.LastIndexOf('.');
                if (di > 0 && s.Length - di <= 10) ext = s.Substring(di);
                s = s.Substring(0, 120 - ext.Length) + ext;
            }
            return s;
        }

        // Bölüm adlarını tek tek güvenli hâle getirip '\' ile birleştirir (üst klasöre çıkamaz)
        public static string SafeRelPath(string path)
        {
            if (path == null || path.Length == 0) return "";
            List<string> parts = new List<string>();
            foreach (string seg in path.Split(new char[] { '\\', '/' }))
            {
                if (seg.Length == 0) continue;
                string s = SafeName(seg);
                if (s.Length > 60) s = s.Substring(0, 60);
                parts.Add(s);
                if (parts.Count >= 12) break;
            }
            return String.Join(Path.DirectorySeparatorChar.ToString(), parts.ToArray());
        }
    }
}
