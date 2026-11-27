# ==================================================================
#  Multimizer eklentisi: silinen dosyaları geri getirme. Yalnızca Çözüm Merkezi "Silinen dosyalar" sekmesinde tarama ya da
#  kurtarma başlatılınca yüklenir; tek başına çalıştırılmaz.
#  Bu dosya derleme sırasında "build\src" altındaki kaynaklardan üretilir (Kurtarma.tpl.ps1 + RcEngine.cs); elle değiştirmeyin.
#  Ana betikten kullanılanlar: Write-WhLog, Test-JobCancel, Set-JobProgress, Format-Size.
#
#  Güvenlik kuralları:
#   1. Taranan sürücüye ya da imaja hiçbir şey yazılmaz; sürücü yalnızca okunur.
#   2. Kurtarılan dosyalar, taranan sürücüden FARKLI bir sürücüye yazılır; aynı sürücü seçilirse işlem başlamaz.
#   3. Hedefte var olan hiçbir dosyanın üzerine yazılmaz; her kurtarma yeni bir klasöre gider.
#   4. Hedefte yeterli boş yer yoksa işlem başlamaz.
#  Kaynaklar: sürücü harfi (E:), fiziksel disk (PhysicalDrive2; sürücü harfi olmayan bölümler ve USB bellekler dahil) ya da ham imaj.
#  Dosya sistemleri: NTFS ve FAT12/16/32 ve exFAT (silinmiş kayıtlardan ad, klasör ve tarih + imza taraması), ext2/3/4 (boş bloklarda
#  imza taraması), diğer her biçim ve bozuk birimler (ReFS, HFS+, APFS, Btrfs, XFS ...: tüm alanda imza taraması).
#  Sınırlar: SSD'lerde TRIM silinen verinin çoğunu temizler; üzerine yazılmış, sıkıştırılmış (NTFS) ya da şifrelenmiş (EFS, BitLocker,
#  LUKS) dosyalar kurtarılamaz; imza taramasında dosya adı ve tarihi bilinmez, parçalı dosyalar bulunamayabilir; FAT'ta parça bilgisi
#  silinir, bu yüzden parçalanmış dosyalar bozuk çıkabilir.
# ==================================================================

# Motoru bu oturuma derler. Dönüş: '' = hazır, aksi hâlde neden.
function global:Initialize-MmRecover {
    if ($null -ne ('Mm.RcEngine' -as [type])) { return '' }
    $src = @'
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
                    if (err == 5) throw new IOException("S\u00fcr\u00fcc\u00fcye eri\u015fim engellendi. Multimizer uygulamas\u0131n\u0131 y\u00f6netici olarak \u00e7al\u0131\u015ft\u0131r\u0131n.");
                    if (err == 2 || err == 3) throw new IOException("S\u00fcr\u00fcc\u00fc bulunamad\u0131: " + letter + ":");
                    throw new IOException("S\u00fcr\u00fcc\u00fc a\u00e7\u0131lamad\u0131 (Windows hata kodu " + err + ").");
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
                    if (err2 == 5) throw new IOException("Diske eri\u015fim engellendi. Multimizer uygulamas\u0131n\u0131 y\u00f6netici olarak \u00e7al\u0131\u015ft\u0131r\u0131n.");
                    if (err2 == 2 || err2 == 3 || err2 == 21) throw new IOException("Disk bulunamad\u0131 ya da haz\u0131r de\u011fil: Disk " + dn);
                    throw new IOException("Disk a\u00e7\u0131lamad\u0131 (Windows hata kodu " + err2 + ").");
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
            if (n < 512) throw new IOException("Kaynak okunamad\u0131 (bo\u015f ya da eri\u015filemiyor).");
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
                if (partition > 0) throw new IOException("B\u00f6l\u00fcm bulunamad\u0131: bu kaynakta tek bir birim var.");
                fs = parts[0].Fs;
                partLength = devLength > 0 ? devLength : 0;
            }
            else if (parts.Count > 0)
            {
                PartitionCount = parts.Count;
                if (partition < 0 || partition >= parts.Count) throw new IOException("B\u00f6l\u00fcm bulunamad\u0131: " + (partition + 1) + ". b\u00f6l\u00fcm yok (kaynakta " + parts.Count + " b\u00f6l\u00fcm var).");
                RcPartInfo pick = parts[partition];
                baseOffset = pick.Start;
                partLength = pick.Length;
                fs = pick.Fs;
                b = new byte[4096];
                if (ReadDev(baseOffset, b, 0, 4096) < 512) throw new IOException("B\u00f6l\u00fcm\u00fcn ba\u015f\u0131 okunamad\u0131.");
            }
            else
            {
                // bölüm tablosu da dosya sistemi de yok: tüm kaynak ham taranır
                PartitionCount = 1;
                if (partition > 0) throw new IOException("B\u00f6l\u00fcm bulunamad\u0131: bu kaynakta b\u00f6l\u00fcm tablosu yok.");
                fs = "";
                partLength = devLength > 0 ? devLength : 0;
            }
            if (devLength > 0 && partLength > 0 && baseOffset + partLength > devLength) partLength = devLength - baseOffset;
            if (fs == "BITLOCKER") throw new IOException("S\u00fcr\u00fcc\u00fc BitLocker ile kilitli. \u00d6nce s\u00fcr\u00fcc\u00fcn\u00fcn kilidini a\u00e7\u0131n.");
            if (fs == "LUKS") throw new IOException("B\u00f6l\u00fcm LUKS ile \u015fifrelenmi\u015f; parola olmadan i\u00e7eri\u011fi okunamaz ve kurtar\u0131lamaz.");
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
                    InitRaw(whole ? "T\u00fcm disk" : fs);
                    if (whole)
                    {
                        OpenNote = "T\u00fcm disk, b\u00f6l\u00fcm d\u00fczenine bak\u0131lmadan dosya imzalar\u0131na g\u00f6re taran\u0131yor. Silinmi\u015f ya da kaybolmu\u015f b\u00f6l\u00fcmlerden kalan dosyalar da bulunabilir; dosya adlar\u0131 ve klas\u00f6rler okunamaz, var olan dosyalar da listelenebilir.";
                        int enc = 0;
                        foreach (RcPartInfo q in parts) { if (q.Fs == "BITLOCKER" || q.Fs == "LUKS") enc++; }
                        if (enc > 0) OpenNote += " \u015eifrelenmi\u015f " + enc + " b\u00f6l\u00fcm var (BitLocker ya da LUKS); bunlar\u0131n i\u00e7indeki dosyalar \u015fifreli oldu\u011fundan imzayla bulunamaz, \u00f6nce kilitleri a\u00e7\u0131lmal\u0131d\u0131r.";
                    }
                    else if (fs == "") OpenNote = "Dosya sistemi tan\u0131namad\u0131; t\u00fcm alan dosya imzalar\u0131na g\u00f6re taran\u0131yor. Silinmi\u015f dosyalarla birlikte var olan dosyalar da listelenebilir.";
                    else OpenNote = fs + " dosya sisteminde silinmi\u015f kay\u0131tlar okunam\u0131yor; t\u00fcm alan dosya imzalar\u0131na g\u00f6re taran\u0131yor. Silinmi\u015f dosyalarla birlikte var olan dosyalar da listelenebilir.";
                }
            }
            catch (Exception ex)
            {
                if (RawMode || ex is OperationCanceledException) throw;
                // dosya sistemi yapısı bozuk: tüm alanı imza ile tara
                string why = (ex is IOException) ? ex.Message.TrimEnd('.') : "yap\u0131 \u00e7\u00f6z\u00fcmlenemedi";
                ResetStructures();
                InitRaw(fs);
                OpenNote = fs + " dosya sistemi bozuk g\u00f6r\u00fcn\u00fcyor (" + why + "). T\u00fcm alan dosya imzalar\u0131na g\u00f6re taran\u0131yor; var olan dosyalar da listelenebilir.";
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

        // Dosya sistemi tanınmayan ya da bozuk alan: tamamı "bo\u015f" sayılır ve imza ile taranır.
        void InitRaw(string name)
        {
            long size = partLength;
            if (size <= 0 && devLength > 0) size = devLength - baseOffset;
            if (devLength > 0 && baseOffset + size > devLength) size = devLength - baseOffset;
            if (size < 4096) throw new IOException("Kayna\u011f\u0131n boyutu okunamad\u0131 ya da \u00e7ok k\u00fc\u00e7\u00fck; tarama yap\u0131lam\u0131yor.");
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
            if (Fs != "NTFS") throw new IOException("Bu i\u015flem yaln\u0131zca NTFS s\u00fcr\u00fcc\u00fclerde yap\u0131labilir.");
        }

        void InitNtfs(byte[] b)
        {
            int bps = U16(b, 11);
            sbyte spc = (sbyte)b[13];
            if (bps < 512 || bps > 4096 || (bps & (bps - 1)) != 0) throw new IOException("NTFS \u00f6ny\u00fckleme kayd\u0131 ge\u00e7ersiz.");
            long cs = 0;
            if (spc > 0) cs = (long)bps * spc;
            else if (spc < 0 && spc > -30) cs = 1L << (-spc);
            if (cs < 512 || cs > (64L << 20)) throw new IOException("NTFS k\u00fcme boyutu ge\u00e7ersiz.");
            ClusterSize = cs;
            long totalSectors = (long)U64(b, 40);
            ClusterCount = totalSectors * bps / cs;
            if (ClusterCount <= 0) throw new IOException("NTFS birim boyutu ge\u00e7ersiz.");
            long mftLcn = (long)U64(b, 48);
            sbyte rc = (sbyte)b[64];
            if (rc > 0) RecSize = (int)(rc * cs);
            else if (rc < 0 && rc > -20) RecSize = 1 << (-rc);
            else RecSize = 0;
            if (RecSize < 512 || RecSize > 65536) throw new IOException("NTFS kay\u0131t boyutu ge\u00e7ersiz.");
            firstCluster = 0;
            dataStart = 0;
            VolumeBytes = ClusterCount * cs;
            if (mftLcn <= 0 || mftLcn >= ClusterCount) throw new IOException("MFT konumu ge\u00e7ersiz.");
            byte[] r0 = new byte[RecSize];
            if (ReadVol(mftLcn * cs, r0, 0, RecSize) < RecSize) throw new IOException("Dosya tablosu (MFT) okunamad\u0131.");
            NtRec m = ParseNtRec(r0, 0, 0, true, true);
            if (m == null || !m.HasData || m.DataResident || m.Runs == null || m.Runs.Count == 0) throw new IOException("Dosya tablosu (MFT) okunamad\u0131.");
            mftRuns = m.Runs;
            mftSize = m.RealSize;
            if (m.HasAttrList)
            {
                List<RcRun> whole = FinalRuns(m);
                if (whole != null) mftRuns = whole;
            }
            NtRec bm = ReadNtRec(6, true, true);
            if (bm == null || !bm.HasData || bm.DataResident) throw new IOException("K\u00fcme haritas\u0131 ($Bitmap) okunamad\u0131.");
            List<RcRun> bmRuns = FinalRuns(bm);
            if (bmRuns == null) throw new IOException("K\u00fcme haritas\u0131 ($Bitmap) okunamad\u0131.");
            long need = (ClusterCount + 7) / 8;
            if (need > (1500L << 20)) throw new IOException("S\u00fcr\u00fcc\u00fc bu s\u00fcr\u00fcm i\u00e7in \u00e7ok b\u00fcy\u00fck.");
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
                if (!dirs.TryGetValue(cur, out d)) { parts.Add("[bilinmeyen klas\u00f6r]"); break; }
                bool ok = (d.Seq == seq) || (!d.InUse && d.Seq == ((seq + 1) & 0xFFFF));
                if (!ok) { parts.Add("[bilinmeyen klas\u00f6r]"); break; }
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
                if ((ci & 255) == 0 && !Tick(prog, "Silinmi\u015f dosyalar de\u011ferlendiriliyor", ci, cands.Count)) { Canceled = true; return res; }
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
                if (chance == 0) note = "Disk alan\u0131 ba\u015fka dosyalarca kullan\u0131l\u0131yor; b\u00fcy\u00fck olas\u0131l\u0131kla \u00fczerine yaz\u0131lm\u0131\u015f.";
                else if (chance < 100) note = "Disk alan\u0131 k\u0131smen yeniden kullan\u0131lm\u0131\u015f; dosya eksik ya da bozuk olabilir.";
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
            if (bps < 512 || bps > 4096 || (bps & (bps - 1)) != 0 || spc == 0 || (spc & (spc - 1)) != 0 || nfat < 1 || fatSz == 0 || rsv == 0) throw new IOException("FAT \u00f6ny\u00fckleme kayd\u0131 ge\u00e7ersiz.");
            fatOff = (long)rsv * bps;
            fatBytesTotal = fatSz * bps;
            rootDirOff = (rsv + nfat * fatSz) * bps;
            rootDirBytes = (long)rootEnt * 32;
            ClusterSize = (long)bps * spc;
            long rootSec = ((long)rootEnt * 32 + bps - 1) / bps;
            long dataSec = rsv + nfat * fatSz + rootSec;
            if (tot <= dataSec) throw new IOException("FAT birim boyutu ge\u00e7ersiz.");
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
            if (bps < 512 || bps > 4096 || (bps & (bps - 1)) != 0 || spc == 0 || (spc & (spc - 1)) != 0 || nfat < 1 || fatSz == 0 || rsv == 0) throw new IOException("FAT32 \u00f6ny\u00fckleme kayd\u0131 ge\u00e7ersiz.");
            fatKind = 32;
            fatOff = (long)rsv * bps;
            fatBytesTotal = fatSz * bps;
            rootCluster = U32(b, 44);
            ClusterSize = (long)bps * spc;
            long dataSec = rsv + nfat * fatSz;
            if (tot <= dataSec) throw new IOException("FAT32 birim boyutu ge\u00e7ersiz.");
            ClusterCount = (tot - dataSec) / spc;
            dataStart = dataSec * bps;
            firstCluster = 2;
            VolumeBytes = tot * bps;
            long fatBytes = Math.Min((ClusterCount + 2) * 4, fatSz * bps);
            if (fatBytes > (1000L << 20)) throw new IOException("S\u00fcr\u00fcc\u00fc bu s\u00fcr\u00fcm i\u00e7in \u00e7ok b\u00fcy\u00fck.");
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
            if (bpsShift < 9 || bpsShift > 12 || spcShift > 25 - bpsShift) throw new IOException("exFAT \u00f6ny\u00fckleme kayd\u0131 ge\u00e7ersiz.");
            long bps = 1L << bpsShift;
            long spc = 1L << spcShift;
            ClusterSize = bps * spc;
            long fatSec = U32(b, 80);
            long heapOff = U32(b, 88);
            long cnt = U32(b, 92);
            long rootCl = U32(b, 96);
            if (cnt <= 0 || cnt > 0xFFFFFFF0L || heapOff <= 0) throw new IOException("exFAT birim boyutu ge\u00e7ersiz.");
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
            if (bmCl < 2 || bmLen <= 0) throw new IOException("exFAT ay\u0131rma haritas\u0131 bulunamad\u0131.");
            long need = (cnt + 7) / 8;
            if (need > (1000L << 20)) throw new IOException("S\u00fcr\u00fcc\u00fc bu s\u00fcr\u00fcm i\u00e7in \u00e7ok b\u00fcy\u00fck.");
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
                        it.Note = RawMode ? "\u0130mza taramas\u0131yla bulundu; dosya ad\u0131 ve tarihi bilinmiyor. Silinmi\u015f mi, var olan bir dosya m\u0131 oldu\u011fu anla\u015f\u0131lam\u0131yor." : "\u0130mza taramas\u0131yla bulundu; dosya ad\u0131 ve tarihi bilinmiyor.";
                        res.Add(it);
                        skipUntil = off + ((len + ClusterSize - 1) / ClusterSize) * ClusterSize;
                    }
                    doneFree += n;
                    if (!Tick(prog, RawMode ? "T\u00fcm alan taran\u0131yor" : "Bo\u015f alan taran\u0131yor", doneFree, totalFree)) { Canceled = true; return res; }
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
                if (LastNote.Length == 0 && it.Length > 4096 && HeadIsZero(it.Offset)) LastNote = "Dosyan\u0131n ba\u015f\u0131 s\u0131f\u0131rlarla dolu; veri silinmi\u015f ya da SSD TRIM ile temizlenmi\u015f olabilir.";
                return done;
            }
            RequireNtfs();
            NtRec r = ReadNtRec(it.Rec, true, true);
            if (r == null) throw new IOException("Dosya kayd\u0131 okunamad\u0131.");
            if (r.InUse || !String.Equals(r.Name, it.Name, StringComparison.Ordinal)) throw new IOException("Bu kay\u0131t yeniden kullan\u0131lm\u0131\u015f; ayn\u0131 numaral\u0131 kay\u0131t art\u0131k ba\u015fka bir dosyaya ait.");
            if (r.Compressed || r.Encrypted) throw new IOException("Dosya s\u0131k\u0131\u015ft\u0131r\u0131lm\u0131\u015f ya da \u015fifreli (EFS); kurtar\u0131lamaz.");
            if (r.HasData && r.DataResident)
            {
                if (r.BadData) throw new IOException("Dosya verisi okunamad\u0131.");
                dest.Write(r.Raw, r.DataOff, r.DataLen);
                return r.DataLen;
            }
            List<RcRun> runs = FinalRuns(r);
            if (runs == null) throw new IOException("Dosyan\u0131n k\u00fcme haritas\u0131 eksik ya da bozuk.");
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
                if (!Tick(prog, "Kurtar\u0131l\u0131yor", pos, size)) throw new OperationCanceledException();
            }
            if (size > 4096 && allZero) LastNote = "Dosyan\u0131n ba\u015f\u0131 s\u0131f\u0131rlarla dolu; veri silinmi\u015f ya da SSD TRIM ile temizlenmi\u015f olabilir.";
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
                if (!Tick(prog, "Kurtar\u0131l\u0131yor", pos, length)) throw new OperationCanceledException();
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

// Multimizer kurtarma motoru, ikinci bölüm (partial): FAT ve exFAT klasör taraması, ext2/3/4 blok haritası.
// Bu dosya yalnızca OKUR; RcEngine.cs ile birlikte tek parça olarak derlenir (build.py ek kaynakları birleştirir).
// C# 5 uyumlu yazılmıştır.

namespace Mm
{
    public sealed partial class RcEngine
    {
        // ---------------- FAT geometrisi ----------------
        int fatKind;                     // 12 | 16 | 32; exFAT için 0
        long fatOff;                     // birinci FAT'ın birim içindeki bayt konumu
        long fatBytesTotal;              // FAT'ın bayt uzunluğu
        long rootDirOff;                 // FAT12/16 kök klasörü
        long rootDirBytes;
        long rootCluster;                // FAT32 kök klasörün ilk kümesi
        long exRootCl;                   // exFAT kök klasörün ilk kümesi
        readonly byte[] fatWin = new byte[1 << 16];
        long fatWinStart = -1;
        int fatWinLen;

        // FAT'tan bir bayt (önbellekli pencere); sınır dışı ya da okunamazsa -1
        int FatByte(long pos)
        {
            if (pos < 0 || pos >= fatBytesTotal) return -1;
            if (fatWinStart < 0 || pos < fatWinStart || pos >= fatWinStart + fatWinLen)
            {
                long st = pos - (pos % 4096);
                int want = (int)Math.Min((long)fatWin.Length, fatBytesTotal - st);
                fatWinLen = want <= 0 ? 0 : ReadVol(fatOff + st, fatWin, 0, want);
                fatWinStart = st;
                if (pos >= fatWinStart + fatWinLen) return -1;
            }
            return fatWin[pos - fatWinStart];
        }

        // FAT girdisinin ham değeri; okunamazsa -1
        long FatEntry(long cl)
        {
            if (fatKind == 12)
            {
                long idx = cl + (cl >> 1);
                int a12 = FatByte(idx);
                int b12 = FatByte(idx + 1);
                if (a12 < 0 || b12 < 0) return -1;
                int v12 = a12 | (b12 << 8);
                return (cl & 1) != 0 ? (v12 >> 4) : (v12 & 0x0FFF);
            }
            if (fatKind == 16)
            {
                int a16 = FatByte(cl * 2);
                int b16 = FatByte(cl * 2 + 1);
                if (a16 < 0 || b16 < 0) return -1;
                return a16 | (b16 << 8);
            }
            long v32 = 0;
            for (int i = 3; i >= 0; i--)
            {
                int x = FatByte(cl * 4 + i);
                if (x < 0) return -1;
                v32 = (v32 << 8) | (long)(byte)x;
            }
            return v32 & 0x0FFFFFFFL;
        }

        // ---------------- FAT: ad ve tarih yardımcıları ----------------
        // CP437'nin üst yarısı (0x80-0xFF); kısa adlardaki ASCII dışı baytlar için
        const string Cp437High =
            "\u00c7\u00fc\u00e9\u00e2\u00e4\u00e0\u00e5\u00e7\u00ea\u00eb\u00e8\u00ef\u00ee\u00ec\u00c4\u00c5" +
            "\u00c9\u00e6\u00c6\u00f4\u00f6\u00f2\u00fb\u00f9\u00ff\u00d6\u00dc\u00a2\u00a3\u00a5\u20a7\u0192" +
            "\u00e1\u00ed\u00f3\u00fa\u00f1\u00d1\u00aa\u00ba\u00bf\u2310\u00ac\u00bd\u00bc\u00a1\u00ab\u00bb" +
            "\u2591\u2592\u2593\u2502\u2524\u2561\u2562\u2556\u2555\u2563\u2551\u2557\u255d\u255c\u255b\u2510" +
            "\u2514\u2534\u252c\u251c\u2500\u253c\u255e\u255f\u255a\u2554\u2569\u2566\u2560\u2550\u256c\u2567" +
            "\u2568\u2564\u2565\u2559\u2558\u2552\u2553\u256b\u256a\u2518\u250c\u2588\u2584\u258c\u2590\u2580" +
            "\u03b1\u00df\u0393\u03c0\u03a3\u03c3\u00b5\u03c4\u03a6\u0398\u03a9\u03b4\u221e\u03c6\u03b5\u2229" +
            "\u2261\u00b1\u2265\u2264\u2320\u2321\u00f7\u2248\u00b0\u2219\u00b7\u221a\u207f\u00b2\u25a0\u00a0";

        static char Cp437(byte c) { return c < 0x80 ? (char)c : Cp437High[c - 0x80]; }

        // 8.3 adında geçebilecek bayt mı (uzun adlarda serbest olan + , ; = [ ] hoşgörülür)
        static bool ValidSfnChar(byte c)
        {
            if (c < 0x20 || c == 0x7F) return false;
            switch (c)
            {
                case 0x22: case 0x2A: case 0x2E: case 0x2F: case 0x3A: case 0x3C: case 0x3E: case 0x3F: case 0x5C: case 0x7C:
                    return false;
            }
            return true;
        }

        static int LfnSum(byte[] t)
        {
            int sum = 0;
            for (int i = 0; i < 11; i++) sum = (((sum & 1) << 7) + (sum >> 1) + t[i]) & 0xFF;
            return sum;
        }

        // Silinmiş kısa adın ilk baytı kaybolur; uzun ad girdilerindeki sağlama toplamından geri bulunur. Bulunamazsa -1.
        static int RecoverFirstByte(byte[] t, int sum)
        {
            byte[] c = new byte[11];
            Buffer.BlockCopy(t, 0, c, 0, 11);
            for (int pass = 0; pass < 3; pass++)
            {
                for (int v = 0x05; v < 256; v++)
                {
                    if (v != 0x05 && !ValidSfnChar((byte)v)) continue;
                    bool upper = v >= 0x41 && v <= 0x5A;
                    bool digit = v >= 0x30 && v <= 0x39;
                    if (pass == 0 && !upper) continue;
                    if (pass == 1 && !digit) continue;
                    if (pass == 2 && (upper || digit)) continue;
                    c[0] = (byte)v;
                    if (LfnSum(c) == sum) return v;
                }
            }
            return -1;
        }

        static string ShortName(byte[] t, int caseFlags)
        {
            StringBuilder sb = new StringBuilder();
            int bl = 8;
            while (bl > 0 && t[bl - 1] == 0x20) bl--;
            for (int i = 0; i < bl; i++)
            {
                char ch = Cp437(t[i]);
                if ((caseFlags & 0x08) != 0) ch = Char.ToLowerInvariant(ch);
                sb.Append(ch);
            }
            int el = 3;
            while (el > 0 && t[8 + el - 1] == 0x20) el--;
            if (el > 0)
            {
                sb.Append('.');
                for (int k = 0; k < el; k++)
                {
                    char ce = Cp437(t[8 + k]);
                    if ((caseFlags & 0x10) != 0) ce = Char.ToLowerInvariant(ce);
                    sb.Append(ce);
                }
            }
            return sb.ToString();
        }

        // idx numaralı kısa ad girdisinin hemen önündeki uzun ad (LFN) girdilerinden adı çıkarır; yoksa null
        static string ReadLfn(byte[] d, int idx, int sum)
        {
            StringBuilder sb = new StringBuilder();
            bool ended = false;
            int got = 0;
            int[] offs = new int[] { 1, 3, 5, 7, 9, 14, 16, 18, 20, 22, 24, 28, 30 };
            for (int k = 1; k <= 20 && idx - k >= 0 && !ended; k++)
            {
                int o = (idx - k) * 32;
                if (d[o + 11] != 0x0F || d[o + 12] != 0 || d[o + 13] != (byte)sum) break;
                bool dele = d[o] == 0xE5;
                if (!dele && (d[o] & 0x3F) != k) break;
                foreach (int po in offs)
                {
                    int ch = d[o + po] | (d[o + po + 1] << 8);
                    if (ch == 0 || ch == 0xFFFF) { ended = true; break; }
                    sb.Append((char)ch);
                }
                got++;
                if (!dele && (d[o] & 0x40) != 0) ended = true;
            }
            if (got == 0 || sb.Length == 0) return null;
            return sb.ToString();
        }

        // Dizin verisindeki idx numaralı kısa ad girdisinin görünen adı: uzun ad varsa o, yoksa 8.3 adı
        static string FatName(byte[] d, int idx, bool del)
        {
            int o = idx * 32;
            byte[] t = new byte[11];
            Buffer.BlockCopy(d, o, t, 0, 11);
            string lfn = null;
            if (idx > 0)
            {
                int po = (idx - 1) * 32;
                if (d[po + 11] == 0x0F && d[po + 12] == 0)
                {
                    int sum = d[po + 13];
                    bool ok;
                    if (del)
                    {
                        int fb = RecoverFirstByte(t, sum);
                        ok = fb >= 0;
                        if (ok) t[0] = (byte)fb;
                    }
                    else ok = LfnSum(t) == sum;
                    if (ok) lfn = ReadLfn(d, idx, sum);
                }
            }
            if (lfn != null) return lfn;
            if (t[0] == 0xE5 && del) t[0] = 0x5F;
            else if (t[0] == 0x05) t[0] = 0xE5;
            return ShortName(t, d[o + 12]);
        }

        // Kısa ad alanı bir dosya adına benziyor mu (bozuk/rastgele veriyi ayıklamak için)
        static bool FatNamePlausible(byte[] d, int o, bool del)
        {
            for (int i = del ? 1 : 0; i < 11; i++)
            {
                byte c = d[o + i];
                if (i == 0 && c == 0x05) continue;
                if (!ValidSfnChar(c)) return false;
            }
            if (!del && d[o] == 0x20) return false;
            if ((d[o + 11] & 0xC0) != 0) return false;
            return true;
        }

        // DOS tarih/saat -> FILETIME (UTC). utcMin: biliniyorsa UTC'ye göre dakika farkı; Int32.MinValue ise yerel saat sayılır.
        static long DosTime(int date, int time, int tenMs, int utcMin)
        {
            if (date == 0) return 0;
            int year = 1980 + (date >> 9);
            int month = (date >> 5) & 15;
            int day = date & 31;
            int hour = time >> 11;
            int min = (time >> 5) & 63;
            int sec = (time & 31) * 2;
            if (month < 1 || month > 12 || day < 1 || day > 31 || hour > 23 || min > 59 || sec > 59) return 0;
            try
            {
                DateTime dt = new DateTime(year, month, day, hour, min, sec, DateTimeKind.Unspecified);
                if (tenMs > 0 && tenMs < 200) dt = dt.AddMilliseconds(tenMs * 10.0);
                if (utcMin != Int32.MinValue)
                {
                    DateTime u = DateTime.SpecifyKind(dt.AddMinutes(-utcMin), DateTimeKind.Utc);
                    return u.ToFileTimeUtc();
                }
                return DateTime.SpecifyKind(dt, DateTimeKind.Local).ToFileTimeUtc();
            }
            catch (ArgumentException) { return 0; }
        }

        static bool DosStampPlausible(int date, int time)
        {
            if (date != 0)
            {
                int month = (date >> 5) & 15;
                int day = date & 31;
                if (month < 1 || month > 12 || day < 1 || day > 31) return false;
            }
            if ((time >> 11) > 23 || ((time >> 5) & 63) > 59 || (time & 31) > 29) return false;
            return true;
        }

        // ---------------- FAT: klasör verisini okuma ----------------
        // Kullanımdaki klasör: FAT zincirini izler (en çok 2 MiB)
        byte[] ReadFatDir(long startCl)
        {
            long maxBytes = 2L << 20;
            long limit = Math.Min(1L << 20, maxBytes / ClusterSize + 4);
            MemoryStream ms = new MemoryStream();
            byte[] cbuf = new byte[ClusterSize];
            long cl = startCl;
            long guard = 0;
            while (cl >= 2 && cl < ClusterCount + 2 && guard++ < limit && ms.Length < maxBytes)
            {
                int got = ReadVol(ClusterOffset(cl), cbuf, 0, (int)ClusterSize);
                if (got < ClusterSize) break;
                ms.Write(cbuf, 0, (int)ClusterSize);
                long nx = FatEntry(cl);
                if (nx < 2 || nx >= ClusterCount + 2) break;
                cl = nx;
            }
            if (ms.Length == 0) return null;
            return ms.ToArray();
        }

        byte[] ReadFatRoot()
        {
            if (fatKind == 32) return ReadFatDir(rootCluster);
            if (rootDirBytes <= 0 || rootDirBytes > (4L << 20)) return null;
            byte[] r = new byte[rootDirBytes];
            if (ReadVol(rootDirOff, r, 0, (int)rootDirBytes) < rootDirBytes) return null;
            return r;
        }

        static bool LooksLikeDirCluster(byte[] c)
        {
            int first = c[0];
            if (first == 0x00 || first == 0xE5) return true;
            if (c[11] == 0x0F) return true;
            return ValidSfnChar(c[0]) && FatNamePlausible(c, 0, false);
        }

        // Silinmiş klasör: FAT zinciri silindiği için kümeler ardışık varsayılır. İlk kümedeki "." girdisi doğrulanır.
        byte[] ReadDeletedFatDir(long startCl)
        {
            MemoryStream ms = new MemoryStream();
            byte[] cbuf = new byte[ClusterSize];
            long cl = startCl;
            int count = 0;
            while (cl < ClusterCount + 2 && count < 64 && ms.Length < (2L << 20))
            {
                if (count > 0 && IsUsed(cl)) break;
                int got = ReadVol(ClusterOffset(cl), cbuf, 0, (int)ClusterSize);
                if (got < ClusterSize) break;
                if (count == 0)
                {
                    if (ClusterSize < 64 || cbuf[0] != 0x2E || cbuf[1] != 0x20 || cbuf[32] != 0x2E || cbuf[33] != 0x2E) return null;
                    long dotCl = U16(cbuf, 26);
                    if (fatKind == 32) dotCl |= ((long)U16(cbuf, 20)) << 16;
                    if (dotCl != startCl) return null;
                }
                else if (!LooksLikeDirCluster(cbuf)) break;
                ms.Write(cbuf, 0, (int)ClusterSize);
                count++;
                bool end = false;
                for (int p = 0; p < ClusterSize; p += 32) { if (cbuf[p] == 0x00) { end = true; break; } }
                if (end) break;
                cl++;
            }
            if (ms.Length == 0) return null;
            return ms.ToArray();
        }

        sealed class DirJob
        {
            public byte[] Data;
            public string Path;
            public int Depth;
            public bool Deleted;
        }

        // ---------------- FAT: silinmiş girdileri bulma ----------------
        List<RcItem> ScanFatDeleted(RcProgress prog, int maxItems)
        {
            List<RcItem> res = new List<RcItem>();
            Queue<DirJob> q = new Queue<DirJob>();
            HashSet<long> seen = new HashSet<long>();
            byte[] rootData = ReadFatRoot();
            if (rootData == null) throw new IOException("K\u00f6k klas\u00f6r okunamad\u0131.");
            DirJob rj = new DirJob();
            rj.Data = rootData;
            rj.Path = "";
            rj.Depth = 0;
            rj.Deleted = false;
            q.Enqueue(rj);
            long done = 0;
            long known = 1;
            while (q.Count > 0)
            {
                DirJob j = q.Dequeue();
                done++;
                if (!Tick(prog, "Klas\u00f6rler okunuyor", done, known)) { Canceled = true; return res; }
                known += ParseFatDir(j, q, seen, res, maxItems);
                if (res.Count >= maxItems) { Truncated = true; break; }
            }
            if (!VerifyHeads(res, prog)) Canceled = true;
            return res;
        }

        // Bir klasörün girdilerini işler; kuyruğa eklenen alt klasör sayısını verir.
        int ParseFatDir(DirJob j, Queue<DirJob> q, HashSet<long> seen, List<RcItem> res, int maxItems)
        {
            int added = 0;
            byte[] d = j.Data;
            int n = d.Length / 32;
            for (int i = 0; i < n; i++)
            {
                int o = i * 32;
                byte first = d[o];
                if (first == 0x00) break;
                StatRecords++;
                int attr = d[o + 11];
                if (attr == 0x0F) continue;
                if ((attr & 0x08) != 0) continue;
                if (first == 0x2E) continue;
                bool del = first == 0xE5;
                if (!FatNamePlausible(d, o, del)) continue;
                bool isDir = (attr & 0x10) != 0;
                long cl = U16(d, o + 26);
                if (fatKind == 32) cl |= ((long)U16(d, o + 20)) << 16;
                long size = U32(d, o + 28);
                int wtime = U16(d, o + 22);
                int wdate = U16(d, o + 24);
                if (del && !DosStampPlausible(wdate, wtime)) continue;
                if (isDir)
                {
                    if (j.Depth >= 28 || cl < 2 || cl >= ClusterCount + 2) continue;
                    if (!seen.Add(cl)) continue;
                    byte[] sub = del ? ReadDeletedFatDir(cl) : ReadFatDir(cl);
                    if (sub == null) continue;
                    string dn = FatName(d, i, del);
                    DirJob nj = new DirJob();
                    nj.Data = sub;
                    nj.Path = j.Path.Length == 0 ? dn : j.Path + "\\" + dn;
                    nj.Depth = j.Depth + 1;
                    nj.Deleted = j.Deleted || del;
                    q.Enqueue(nj);
                    added++;
                    continue;
                }
                if (!del && !j.Deleted) continue;
                if (size == 0 || cl < 2 || cl >= ClusterCount + 2) continue;
                long need = (size + ClusterSize - 1) / ClusterSize;
                if (cl - 2 + need > ClusterCount) continue;
                string name = FatName(d, i, del);
                if (name.Length == 0) continue;
                long free = 0;
                for (long c = 0; c < need; c++) { if (!IsUsed(cl + c)) free++; }
                int chance = (int)(free * 100 / need);
                if (free > 0 && chance == 0) chance = 1;
                if (need > 1 && chance > 85) chance = 85;
                string note = "";
                if (free == 0) note = "Disk alan\u0131 ba\u015fka dosyalarca kullan\u0131l\u0131yor; b\u00fcy\u00fck olas\u0131l\u0131kla \u00fczerine yaz\u0131lm\u0131\u015f.";
                else if (free < need) note = "Disk alan\u0131 k\u0131smen yeniden kullan\u0131lm\u0131\u015f; dosya eksik ya da bozuk olabilir.";
                if (res.Count >= maxItems) { Truncated = true; return added; }
                RcItem it = new RcItem();
                it.Kind = "fat";
                it.Offset = ClusterOffset(cl);
                it.Length = size;
                it.Name = name;
                it.Path = j.Path;
                it.Ext = ExtOf(name);
                it.Modified = DosTime(wdate, wtime, 0, Int32.MinValue);
                it.Deleted = 0;
                it.Chance = chance;
                it.Note = note;
                res.Add(it);
                StatDeleted++;
                Own(cl, cl + need);
            }
            return added;
        }

        // ---------------- içerik doğrulaması (FAT ve exFAT) ----------------
        static string SniffTypeForExt(string ext)
        {
            switch (ext)
            {
                case "jpg": case "jpeg": case "jpe": return "jpg";
                case "png": return "png";
                case "gif": return "gif";
                case "bmp": return "bmp";
                case "pdf": return "pdf";
                case "zip": case "docx": case "xlsx": case "pptx": case "odt": case "ods": case "odp": case "epub": case "apk": case "jar": return "zip";
                case "doc": case "xls": case "ppt": return "ole";
                case "mp4": case "m4a": case "m4v": return "mp4";
                case "sqlite": return "sqlite";
                case "7z": return "7z";
                case "wav": case "avi": case "webp": return "riff";
            }
            return null;
        }

        static void AddNote(RcItem it, string text)
        {
            if (it.Note.Length > 0) it.Note += " ";
            it.Note += text;
        }

        // Dosyanın ilk baytlarına bakar: sıfırlarla doluysa ya da uzantıya uymuyorsa kurtarma şansını düşürür.
        void HeadCheck(RcItem it)
        {
            if (it.Chance <= 0 || it.Length < 16) return;
            byte[] hb = new byte[32];
            if (ReadVol(it.Offset, hb, 0, 32) < 32) return;
            bool zero = true;
            for (int i = 0; i < 32; i++) { if (hb[i] != 0) { zero = false; break; } }
            if (zero)
            {
                if (it.Length >= 64)
                {
                    if (it.Chance > 5) it.Chance = 5;
                    AddNote(it, "Dosyan\u0131n ba\u015f\u0131 s\u0131f\u0131rlarla dolu; veri silinmi\u015f ya da SSD TRIM ile temizlenmi\u015f olabilir.");
                }
                return;
            }
            string want = SniffTypeForExt(it.Ext);
            if (want == null) return;
            string have = Sniff(hb, 0, 32);
            if (have != want)
            {
                if (it.Chance > 20) it.Chance = 20;
                AddNote(it, "Dosyan\u0131n ba\u015f\u0131 beklenen bi\u00e7imde de\u011fil; ba\u015fka veriyle \u00fczerine yaz\u0131lm\u0131\u015f olabilir.");
            }
        }

        bool VerifyHeads(List<RcItem> res, RcProgress prog)
        {
            List<RcItem> order = new List<RcItem>(res);
            order.Sort(delegate(RcItem a, RcItem b) { return a.Offset.CompareTo(b.Offset); });
            for (int i = 0; i < order.Count; i++)
            {
                if ((i & 63) == 0 && !Tick(prog, "Dosya ba\u015fl\u0131klar\u0131 denetleniyor", i, order.Count)) return false;
                HeadCheck(order[i]);
            }
            return true;
        }

        bool HeadIsZero(long offset)
        {
            byte[] hb = new byte[64];
            if (ReadVol(offset, hb, 0, 64) < 64) return false;
            for (int i = 0; i < 64; i++) { if (hb[i] != 0) return false; }
            return true;
        }

        // Kurtarma anında: dosyanın ilk kümesi sonradan kullanıma alındıysa kurtarma reddedilir.
        void CheckFatRange(RcItem it)
        {
            if (it.Length <= 0 || it.Offset < dataStart || ClusterSize <= 0) throw new IOException("Dosya konumu ge\u00e7ersiz.");
            long cl = (it.Offset - dataStart) / ClusterSize + firstCluster;
            if (it.Offset != ClusterOffset(cl)) throw new IOException("Dosya konumu ge\u00e7ersiz.");
            long need = (it.Length + ClusterSize - 1) / ClusterSize;
            if (cl < firstCluster || cl + need > firstCluster + ClusterCount) throw new IOException("Dosya konumu ge\u00e7ersiz.");
            if (IsUsed(cl)) throw new IOException("Bu dosyan\u0131n disk alan\u0131 sonradan ba\u015fka bir dosyaya verilmi\u015f; kurtar\u0131lamaz.");
        }

        // ---------------- exFAT: silinmiş girdi kümeleri ----------------
        sealed class ExJob
        {
            public byte[] Data;
            public string Path;
            public int Depth;
            public bool Deleted;
        }

        long ExFatEntry(long cl)
        {
            long v = 0;
            for (int i = 3; i >= 0; i--)
            {
                int x = FatByte(cl * 4 + i);
                if (x < 0) return -1;
                v = (v << 8) | (long)(byte)x;
            }
            return v;
        }

        // noFat: kümeler ardışık (FAT kullanılmaz). length: klasörün bayt uzunluğu, bilinmiyorsa 0.
        byte[] ReadExDir(long startCl, long length, bool noFat)
        {
            long maxBytes = length > 0 ? Math.Min(length, 64L << 20) : (4L << 20);
            MemoryStream ms = new MemoryStream();
            byte[] cbuf = new byte[ClusterSize];
            long cl = startCl;
            long guard = 0;
            while (cl >= 2 && cl < ClusterCount + 2 && ms.Length < maxBytes && guard++ < 4000000)
            {
                int got = ReadVol(ClusterOffset(cl), cbuf, 0, (int)ClusterSize);
                if (got < ClusterSize) break;
                ms.Write(cbuf, 0, (int)ClusterSize);
                if (noFat) { cl++; continue; }
                long nx = ExFatEntry(cl);
                if (nx < 2 || nx >= ClusterCount + 2) break;
                cl = nx;
            }
            if (ms.Length == 0) return null;
            return ms.ToArray();
        }

        // Girdi kümesinin sağlama toplamı. Silinmiş kümelerde "kullan\u0131mda" biti sıfırlanmıştır; hesapta geri konur.
        static bool ExSetChecksumOk(byte[] d, int o, int sc)
        {
            int total = (sc + 1) * 32;
            uint sum = 0;
            for (int i = 0; i < total; i++)
            {
                if (i == 2 || i == 3) continue;
                uint v = d[o + i];
                if ((i & 31) == 0) v |= 0x80u;
                sum = ((((sum & 1u) != 0) ? 0x8000u : 0u) + (sum >> 1) + v) & 0xFFFFu;
            }
            return sum == (uint)U16(d, o + 2);
        }

        static long ExTime(byte[] d, int o, int tsOff, int incOff, int utcOff)
        {
            uint ts = U32(d, o + tsOff);
            int date = (int)(ts >> 16);
            int time = (int)(ts & 0xFFFFu);
            int inc = d[o + incOff];
            int u = d[o + utcOff];
            int utcMin = Int32.MinValue;
            if ((u & 0x80) != 0)
            {
                int off = u & 0x7F;
                if (off >= 64) off -= 128;
                utcMin = off * 15;
            }
            return DosTime(date, time, inc > 199 ? 0 : inc, utcMin);
        }

        List<RcItem> ScanExfatDeleted(RcProgress prog, int maxItems)
        {
            List<RcItem> res = new List<RcItem>();
            Queue<ExJob> q = new Queue<ExJob>();
            HashSet<long> seen = new HashSet<long>();
            byte[] rootData = ReadExDir(exRootCl, 0, false);
            if (rootData == null) throw new IOException("K\u00f6k klas\u00f6r okunamad\u0131.");
            ExJob rj = new ExJob();
            rj.Data = rootData;
            rj.Path = "";
            rj.Depth = 0;
            rj.Deleted = false;
            q.Enqueue(rj);
            long done = 0;
            long known = 1;
            while (q.Count > 0)
            {
                ExJob j = q.Dequeue();
                done++;
                if (!Tick(prog, "Klas\u00f6rler okunuyor", done, known)) { Canceled = true; return res; }
                known += ParseExDir(j, q, seen, res, maxItems);
                if (res.Count >= maxItems) { Truncated = true; break; }
            }
            if (!VerifyHeads(res, prog)) Canceled = true;
            return res;
        }

        int ParseExDir(ExJob j, Queue<ExJob> q, HashSet<long> seen, List<RcItem> res, int maxItems)
        {
            int added = 0;
            byte[] d = j.Data;
            int n = d.Length / 32;
            int i = 0;
            while (i < n)
            {
                int o = i * 32;
                int t = d[o];
                if (t == 0x00) break;
                StatRecords++;
                if (t != 0x85 && t != 0x05) { i++; continue; }
                bool del = t == 0x05;
                int sc = d[o + 1];
                if (sc < 2 || sc > 18 || i + sc >= n) { i++; continue; }
                int so = o + 32;
                if (d[so] != (del ? 0x40 : 0xC0)) { i++; continue; }
                int nameLen = d[so + 3];
                int nameEntries = (nameLen + 14) / 15;
                if (nameLen == 0 || nameEntries != sc - 1) { i++; continue; }
                if (!ExSetChecksumOk(d, o, sc)) { i++; continue; }
                StringBuilder sb = new StringBuilder();
                bool namesOk = true;
                for (int k = 0; k < nameEntries; k++)
                {
                    int no = so + 32 + k * 32;
                    if (d[no] != (del ? 0x41 : 0xC1)) { namesOk = false; break; }
                    for (int c = 0; c < 15 && sb.Length < nameLen; c++) sb.Append((char)(d[no + 2 + c * 2] | (d[no + 3 + c * 2] << 8)));
                }
                if (!namesOk) { i++; continue; }
                i += sc + 1;
                int attr = U16(d, o + 4);
                bool isDir = (attr & 0x10) != 0;
                bool noFat = (d[so + 1] & 0x02) != 0;
                long validLen = (long)U64(d, so + 8);
                long firstCl = U32(d, so + 20);
                long dataLen = (long)U64(d, so + 24);
                string name = sb.ToString();
                if (name.Length == 0) name = "_";
                if (isDir)
                {
                    if (j.Depth >= 28 || firstCl < 2 || firstCl >= ClusterCount + 2) continue;
                    if (!seen.Add(firstCl)) continue;
                    byte[] sub = ReadExDir(firstCl, dataLen, noFat || del);
                    if (sub == null) continue;
                    ExJob nj = new ExJob();
                    nj.Data = sub;
                    nj.Path = j.Path.Length == 0 ? name : j.Path + "\\" + name;
                    nj.Depth = j.Depth + 1;
                    nj.Deleted = j.Deleted || del;
                    q.Enqueue(nj);
                    added++;
                    continue;
                }
                if (!del && !j.Deleted) continue;
                if (dataLen <= 0 || validLen <= 0 || firstCl < 2 || firstCl >= ClusterCount + 2) continue;
                long need = (dataLen + ClusterSize - 1) / ClusterSize;
                if (firstCl - 2 + need > ClusterCount) continue;
                long free = 0;
                for (long c2 = 0; c2 < need; c2++) { if (!IsUsed(firstCl + c2)) free++; }
                int chance = (int)(free * 100 / need);
                if (free > 0 && chance == 0) chance = 1;
                if (need > 1 && !noFat && chance > 85) chance = 85;
                string note = "";
                if (free == 0) note = "Disk alan\u0131 ba\u015fka dosyalarca kullan\u0131l\u0131yor; b\u00fcy\u00fck olas\u0131l\u0131kla \u00fczerine yaz\u0131lm\u0131\u015f.";
                else if (free < need) note = "Disk alan\u0131 k\u0131smen yeniden kullan\u0131lm\u0131\u015f; dosya eksik ya da bozuk olabilir.";
                if (res.Count >= maxItems) { Truncated = true; return added; }
                RcItem it = new RcItem();
                it.Kind = "fat";
                it.Offset = ClusterOffset(firstCl);
                it.Length = dataLen;
                it.Name = name;
                it.Path = j.Path;
                it.Ext = ExtOf(name);
                it.Modified = ExTime(d, o, 12, 21, 23);
                it.Deleted = 0;
                it.Chance = chance;
                it.Note = note;
                res.Add(it);
                StatDeleted++;
                Own(firstCl, firstCl + need);
            }
            return added;
        }

        // ---------------- ext2/3/4: blok haritası ----------------
        // Boş (ayrılmamış) bloklar bitmap'e alınır; silinen dosyaların adları çıkarılamaz, boş bloklar imza ile taranır.
        void InitExt(byte[] b)
        {
            int so = 1024;
            long blocksLo = U32(b, so + 4);
            long fdb = U32(b, so + 20);
            int logBs = (int)U32(b, so + 24);
            long bpg = U32(b, so + 32);
            uint incompat = U32(b, so + 96);
            uint rocompat = U32(b, so + 100);
            if (logBs < 0 || logBs > 6) throw new IOException("ext blok boyutu ge\u00e7ersiz.");
            long bs = 1024L << logBs;
            if ((incompat & 0x10u) != 0) throw new IOException("ext meta_bg d\u00fczeni bu s\u00fcr\u00fcmde desteklenmiyor.");
            if ((rocompat & 0x200u) != 0) throw new IOException("ext bigalloc d\u00fczeni bu s\u00fcr\u00fcmde desteklenmiyor.");
            bool is64 = (incompat & 0x80u) != 0;
            long blocks = blocksLo;
            int descSize = 32;
            if (is64)
            {
                blocks |= ((long)U32(b, so + 336)) << 32;
                descSize = U16(b, so + 254);
                if (descSize < 64 || descSize > 1024 || (descSize & (descSize - 1)) != 0) throw new IOException("ext grup tan\u0131mlay\u0131c\u0131 boyutu ge\u00e7ersiz.");
            }
            if (bpg == 0 || bpg > 8 * bs || (bpg & 7) != 0 || blocks <= fdb || fdb > 1) throw new IOException("ext s\u00fcper blok ge\u00e7ersiz.");
            long groups = (blocks - fdb + bpg - 1) / bpg;
            if (groups > 1000000 || groups * descSize > (64L << 20)) throw new IOException("S\u00fcr\u00fcc\u00fc bu s\u00fcr\u00fcm i\u00e7in \u00e7ok b\u00fcy\u00fck.");
            ClusterSize = bs;
            ClusterCount = blocks - fdb;
            firstCluster = fdb;
            dataStart = fdb * bs;
            VolumeBytes = blocks * bs;
            long need = (ClusterCount + 7) / 8;
            if (need > (1000L << 20)) throw new IOException("S\u00fcr\u00fcc\u00fc bu s\u00fcr\u00fcm i\u00e7in \u00e7ok b\u00fcy\u00fck.");
            bitmap = new byte[need];
            byte[] gdt = new byte[groups * descSize];
            if (ReadVol((fdb + 1) * bs, gdt, 0, gdt.Length) < gdt.Length) throw new IOException("ext grup tan\u0131mlay\u0131c\u0131 tablosu okunamad\u0131.");
            byte[] gb = new byte[bs];
            bool csum = (rocompat & 0x410u) != 0;
            for (long g = 0; g < groups; g++)
            {
                int o = (int)(g * descSize);
                long bb = U32(gdt, o);
                if (is64) bb |= ((long)U32(gdt, o + 32)) << 32;
                int gflags = U16(gdt, o + 18);
                long firstBit = g * bpg;
                long nbits = Math.Min(bpg, ClusterCount - firstBit);
                if (nbits <= 0) break;
                long byteOff = firstBit >> 3;
                long nbytes = (nbits + 7) >> 3;
                if (csum && (gflags & 0x2) != 0) continue;
                long errs = ReadErrors;
                if (bb < fdb || bb >= blocks || ReadVol(bb * bs, gb, 0, (int)bs) < bs || ReadErrors != errs)
                {
                    for (long k = 0; k < nbytes; k++) bitmap[byteOff + k] = 0xFF;
                    continue;
                }
                Buffer.BlockCopy(gb, 0, bitmap, (int)byteOff, (int)nbytes);
            }
        }
    }
}
'@
    try {
        if ($PSVersionTable.PSEdition -ne 'Core') {
            Add-Type -TypeDefinition $src -Language CSharp -ReferencedAssemblies @('System.dll', 'System.Core.dll') -IgnoreWarnings -ErrorAction Stop
        } else {
            Add-Type -TypeDefinition $src -Language CSharp -IgnoreWarnings -ErrorAction Stop
        }
    } catch {
        # başka bir iş aynı anda derlemiş olabilir
        if ($null -ne ('Mm.RcEngine' -as [type])) { return '' }
        $m = [string]$_.Exception.Message
        try { if ($null -ne $_.Exception.InnerException) { $m += ' ' + [string]$_.Exception.InnerException.Message } } catch { }
        return ('Kurtarma motoru derlenemedi: ' + $m)
    }
    return ''
}

# .NET yöntem çağrısı hatalarında asıl iletiyi verir
function global:Get-RcErrorText($Err) {
    $ex = $Err.Exception
    $depth = 0
    while ($null -ne $ex.InnerException -and $depth -lt 5) { $ex = $ex.InnerException; $depth++ }
    return [string]$ex.Message
}

# Kaynağı doğrular. Dönüş: @{ Ok; Kind (Drive | Disk | Image); Source; Letter; DiskNumber; Error }
function global:Resolve-RcSource([string]$Source) {
    $res = @{ Ok = $false; Kind = ''; Source = ''; Letter = ''; DiskNumber = -1; Error = '' }
    $s = ([string]$Source).Trim()
    if ($s -eq '') { $res.Error = 'Taranacak sürücü, disk ya da disk imajı seçilmedi.'; return $res }
    if ([Mm.RcEngine]::IsDiskSpec($s)) {
        $num = [int]([regex]::Match($s, '\d+$').Value)
        $res.Ok = $true; $res.Kind = 'Disk'; $res.Source = ('PhysicalDrive' + [string]$num); $res.DiskNumber = $num
        return $res
    }
    if ([Mm.RcEngine]::IsDriveSpec($s)) {
        $letter = $s.Substring(0, 1).ToUpperInvariant()
        if (-not (Test-Path -LiteralPath ($letter + ':\'))) { $res.Error = ($letter + ': sürücüsü bulunamadı ya da hazır değil.'); return $res }
        $res.Ok = $true; $res.Kind = 'Drive'; $res.Source = ($letter + ':'); $res.Letter = $letter
        return $res
    }
    if (Test-Path -LiteralPath $s -PathType Leaf) { $res.Ok = $true; $res.Kind = 'Image'; $res.Source = $s; return $res }
    $res.Error = ('Disk imajı bulunamadı: ' + $s)
    return $res
}

function global:Get-RcDirRoot([string]$Dir) {
    try { return [string][System.IO.Path]::GetPathRoot([System.IO.Path]::GetFullPath($Dir)) } catch { return '' }
}

# Hedef klasörü denetler. Dönüş: '' = uygun, aksi hâlde neden. Need: gereken bayt
function global:Test-RcDestination($Src, [string]$Dest, [double]$Need) {
    $d = ([string]$Dest).Trim()
    if ($d -eq '') { return 'Kurtarma klasörü seçilmedi.' }
    if (-not [System.IO.Path]::IsPathRooted($d)) { return 'Kurtarma klasörü tam bir yol olmalı (örneğin D:\Kurtarilan).' }
    $root = Get-RcDirRoot $d
    if ($root -eq '') { return 'Kurtarma klasörü yolu geçersiz.' }
    $isUnc = $root.StartsWith('\\')
    if ($Src.Kind -eq 'Drive' -and -not $isUnc -and $root.Length -ge 1 -and $root.Substring(0, 1).ToUpperInvariant() -eq [string]$Src.Letter) {
        return ('Kurtarma klasörü, taranan ' + [string]$Src.Letter + ': sürücüsünde olamaz. Kurtarılan dosyalar silinmiş dosyaların yerine yazılıp onları yok edebilir; başka bir sürücü ya da USB bellek seçin.')
    }
    if ($Src.Kind -eq 'Disk' -and -not $isUnc -and $root.Length -ge 1) {
        $dn = -2
        try { $dn = [int](@(Get-Partition -DriveLetter $root.Substring(0, 1) -ErrorAction Stop)[0]).DiskNumber } catch { $dn = -2 }
        if ($dn -eq [int]$Src.DiskNumber) {
            return ('Kurtarma klasörü, taranan diskte (Disk ' + [string]$Src.DiskNumber + ') olamaz. Kurtarılan dosyalar, silinmiş dosyaların yerine yazılıp onları yok edebilir; başka bir disk ya da USB bellek seçin.')
        }
    }
    try {
        if (-not (Test-Path -LiteralPath $d -PathType Container)) { [void][System.IO.Directory]::CreateDirectory($d) }
        $probe = Join-Path $d ('.mm-deneme-' + [System.Guid]::NewGuid().ToString('N') + '.tmp')
        [System.IO.File]::WriteAllText($probe, 'x')
        [System.IO.File]::Delete($probe)
    } catch {
        return ('Kurtarma klasörüne yazılamadı: ' + $_.Exception.Message)
    }
    if (-not $isUnc) {
        try {
            $di = New-Object System.IO.DriveInfo -ArgumentList $root.Substring(0, 1)
            $free = [double]$di.AvailableFreeSpace
            $want = $Need * 1.02 + 16777216
            if ($free -lt $want) {
                return ('Kurtarma klasöründe yeterli boş yer yok: ' + (Format-Size $Need) + ' gerekiyor, ' + (Format-Size $free) + ' var.')
            }
        } catch { }
    }
    return ''
}

# Var olan bir dosyanın üzerine yazmaz: ad doluysa " (2)", " (3)" ... ekler
function global:Get-RcFreeName([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $Path }
    $dir = Split-Path -Parent $Path
    $base = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    $ext = [System.IO.Path]::GetExtension($Path)
    for ($i = 2; $i -lt 1000; $i++) {
        $c = Join-Path $dir ($base + ' (' + [string]$i + ')' + $ext)
        if (-not (Test-Path -LiteralPath $c)) { return $c }
    }
    return (Join-Path $dir ($base + '-' + [System.Guid]::NewGuid().ToString('N').Substring(0, 8) + $ext))
}

function global:ConvertTo-RcDate($FileTime) {
    try {
        $ft = [long]$FileTime
        if ($ft -le 0) { return $null }
        return [System.DateTime]::FromFileTimeUtc($ft)
    } catch { return $null }
}

# Motorun bölüm listesini düz tablolara çevirir: @{ Index; Start; Length; Fs; Kind } dizisi
function global:Convert-RcParts($List) {
    $out = New-Object System.Collections.ArrayList
    foreach ($p in @($List)) {
        if ($null -eq $p) { continue }
        [void]$out.Add(@{ Index = [int]$p.Index; Start = [double]$p.Start; Length = [double]$p.Length; Fs = [string]$p.Fs; Kind = [string]$p.Kind })
    }
    return , $out.ToArray()
}

# P: Source (E:, PhysicalDrive2 ya da imaj dosyası). Yalnızca bölüm düzenini okur (hızlıdır).
# Dönüş: @{ Ok; Error; Parts (Convert-RcParts) }
function global:Job_RecoverParts($P) {
    $res = @{ Ok = $false; Error = ''; Parts = @() }
    $err = Initialize-MmRecover
    if ($err -ne '') { $res.Error = $err; Write-WhLog $err 'ERR'; return $res }
    $src = Resolve-RcSource ([string]$P.Source)
    if ($src.Ok -ne $true) { $res.Error = [string]$src.Error; return $res }
    try {
        $res.Parts = Convert-RcParts ([Mm.RcEngine]::ListPartitions([string]$src.Source))
        $res.Ok = $true
    } catch {
        $res.Error = Get-RcErrorText $_
        Write-WhLog ('Bölümler okunamadı: ' + $res.Error) 'WARN'
    }
    return $res
}

# P: Source (E:, PhysicalDrive2 ya da imaj dosyası), Mode (Quick | Deep | Both), Types (imza türleri; boş = hepsi), MaxResults, Partition
# Dönüş: @{ Ok; Error; Note; Fs; Method (mft | fat | exfat | free | raw); Raw; ClusterSize; VolumeBytes; FreeBytes; Items (Mm.RcItem dizisi);
#          Stats; Truncated; Canceled; Mode; Partitions; PartList }
function global:Job_RecoverScan($P) {
    $res = @{ Ok = $false; Error = ''; Note = ''; Fs = ''; Method = ''; Raw = $false; ClusterSize = 0; VolumeBytes = [double]0; FreeBytes = [double]0; Items = @(); Stats = @{}; Truncated = $false; Canceled = $false; Mode = ''; Partitions = 1; PartList = @() }
    $err = Initialize-MmRecover
    if ($err -ne '') { $res.Error = $err; Write-WhLog $err 'ERR'; return $res }
    $src = Resolve-RcSource ([string]$P.Source)
    if ($src.Ok -ne $true) { $res.Error = [string]$src.Error; Write-WhLog ([string]$src.Error) 'ERR'; return $res }
    $mode = [string]$P.Mode
    if ($mode -ne 'Quick' -and $mode -ne 'Deep' -and $mode -ne 'Both') { $mode = 'Quick' }
    $res.Mode = $mode
    $max = 20000
    if ($null -ne $P.MaxResults -and [int]$P.MaxResults -gt 0) { $max = [int]$P.MaxResults }
    $part = 0
    if ($null -ne $P.Partition) { $part = [int]$P.Partition }
    $types = @()
    if ($null -ne $P.Types) { $types = @($P.Types | ForEach-Object { [string]$_ } | Where-Object { $_ -ne '' }) }
    Write-WhLog ('--- SİLİNEN DOSYALAR: ' + [string]$src.Source + ' taranıyor (salt okunur) ---') 'STEP'
    $cb = [Mm.RcProgress]{
        param([string]$stage, [long]$done, [long]$total)
        $pct = 0
        if ($total -gt 0) { $pct = [int][math]::Min(1000, [math]::Floor($done * 1000.0 / $total)) }
        Set-JobProgress $pct 1000 $stage
        return (-not (Test-JobCancel))
    }
    $eng = $null
    try {
        $eng = [Mm.RcEngine]::Open([string]$src.Source, $part)
        $res.Fs = [string]$eng.Fs
        $res.Method = [string]$eng.Method
        $res.Raw = ($eng.RawMode -eq $true)
        $res.Note = [string]$eng.OpenNote
        $res.ClusterSize = [int]$eng.ClusterSize
        $res.VolumeBytes = [double]$eng.VolumeBytes
        $res.FreeBytes = [double]$eng.StatFreeBytes
        $res.Partitions = [int]$eng.PartitionCount
        $res.PartList = Convert-RcParts $eng.PartList
        Write-WhLog ('Dosya sistemi: ' + $res.Fs + ', küme ' + (Format-Size ([double]$eng.ClusterSize)) + ', ' + $(if ($res.Raw) { 'taranacak alan ' } else { 'boş alan ' }) + (Format-Size $res.FreeBytes)) 'INFO'
        if ($res.Note -ne '') { Write-WhLog $res.Note 'WARN' }
        $hasNames = ($eng.HasNames -eq $true)
        $doMeta = $hasNames -and ($mode -eq 'Quick' -or $mode -eq 'Both')
        $doCarve = ($mode -eq 'Deep' -or $mode -eq 'Both' -or -not $hasNames)
        if ($mode -eq 'Quick' -and -not $hasNames) {
            Write-WhLog ($res.Fs + ' dosya sistemi silinen dosya adlarını okunabilir bırakmıyor; imza taraması yapılıyor.') 'INFO'
        }
        $items = New-Object System.Collections.ArrayList
        $metaCount = 0
        if ($doMeta) {
            $list = $eng.ScanDeleted($cb, $max)
            foreach ($it in $list) { [void]$items.Add($it) }
            $metaCount = $items.Count
            Write-WhLog ([string]$metaCount + ' silinmiş dosya kaydı bulundu.') 'INFO'
        }
        if ($doCarve -and -not $eng.Canceled -and $items.Count -lt $max) {
            $left = $max - $items.Count
            $list2 = $eng.Carve($types, $cb, $left)
            foreach ($it in $list2) { [void]$items.Add($it) }
            Write-WhLog ([string]($items.Count - $metaCount) + ' dosya imza taramasıyla bulundu.') 'INFO'
        }
        $res.Items = @($items.ToArray())
        $res.Truncated = ($eng.Truncated -eq $true)
        $res.Canceled = ($eng.Canceled -eq $true)
        $res.Stats = @{ Records = [double]$eng.StatRecords; Deleted = [double]$eng.StatDeleted; Skipped = [double]$eng.StatSkipped; ReadErrors = [double]$eng.ReadErrors; FromTable = $metaCount; Carved = ($items.Count - $metaCount) }
        if ($eng.StatSkipped -gt 0) { Write-WhLog ([string]$eng.StatSkipped + ' kayıt atlandı (sıkıştırılmış, şifreli ya da bozuk).') 'INFO' }
        if ($eng.ReadErrors -gt 0) { Write-WhLog ([string]$eng.ReadErrors + ' okuma hatası oldu; ilgili bölgeler sıfır sayıldı.') 'WARN' }
        if ($res.Truncated) { Write-WhLog ('Sonuç sayısı ' + [string]$max + ' ile sınırlandı; türü daraltıp yeniden tarayabilirsiniz.') 'WARN' }
        if ($res.Canceled) { Write-WhLog 'Tarama iptal edildi; o ana kadar bulunanlar listelendi.' 'WARN' }
        $res.Ok = $true
    } catch {
        $res.Error = Get-RcErrorText $_
        Write-WhLog ('Tarama yapılamadı: ' + $res.Error) 'ERR'
    } finally {
        if ($null -ne $eng) { $eng.Dispose() }
    }
    return $res
}

# P: Source, Dest (kurtarma klasörü), Items (Mm.RcItem dizisi), KeepPaths ($true: eski klasör yapısı korunur), Partition
# Dönüş: @{ Ok; Error; Dir; Done; Failed; Bytes; Report; Canceled; Results }
function global:Job_RecoverFiles($P) {
    $res = @{ Ok = $false; Error = ''; Dir = ''; Done = 0; Failed = 0; Bytes = [double]0; Report = ''; Canceled = $false; Results = @() }
    $err = Initialize-MmRecover
    if ($err -ne '') { $res.Error = $err; Write-WhLog $err 'ERR'; return $res }
    $src = Resolve-RcSource ([string]$P.Source)
    if ($src.Ok -ne $true) { $res.Error = [string]$src.Error; Write-WhLog ([string]$src.Error) 'ERR'; return $res }
    $items = @($P.Items | Where-Object { $null -ne $_ })
    if ($items.Count -eq 0) { $res.Error = 'Kurtarılacak dosya seçilmedi.'; Write-WhLog $res.Error 'ERR'; return $res }
    $need = [double]0
    foreach ($it in $items) { $need += [double]$it.Length }
    $why = Test-RcDestination $src ([string]$P.Dest) $need
    if ($why -ne '') { $res.Error = $why; Write-WhLog $why 'ERR'; return $res }
    $keep = ($P.KeepPaths -eq $true)
    $part = 0
    if ($null -ne $P.Partition) { $part = [int]$P.Partition }

    # her kurtarma yeni bir klasöre gider
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $runDir = Join-Path ([string]$P.Dest).Trim() ('Multimizer-Kurtarma-' + $stamp)
    $n = 2
    while (Test-Path -LiteralPath $runDir) { $runDir = Join-Path ([string]$P.Dest).Trim() ('Multimizer-Kurtarma-' + $stamp + '-' + [string]$n); $n++ }
    try { [void][System.IO.Directory]::CreateDirectory($runDir) }
    catch { $res.Error = ('Kurtarma klasörü oluşturulamadı: ' + $_.Exception.Message); Write-WhLog $res.Error 'ERR'; return $res }
    $res.Dir = $runDir
    Write-WhLog ('--- DOSYA KURTARMA: ' + [string]$items.Count + ' dosya, ' + (Format-Size $need) + ' -> ' + $runDir + ' ---') 'STEP'

    $doneBytes = [double]0
    $curBase = [double]0
    $cb = [Mm.RcProgress]{
        param([string]$stage, [long]$done, [long]$total)
        $all = $need
        if ($all -le 0) { $all = 1 }
        $pct = [int][math]::Min(1000, [math]::Floor(($curBase + [double]$done) * 1000.0 / $all))
        Set-JobProgress $pct 1000 'Kurtarılıyor'
        return (-not (Test-JobCancel))
    }
    $eng = $null
    $rows = New-Object System.Collections.ArrayList
    try {
        $eng = [Mm.RcEngine]::Open([string]$src.Source, $part)
        foreach ($it in $items) {
            if (Test-JobCancel) { $res.Canceled = $true; Write-WhLog 'İptal edildi.' 'WARN'; break }
            $row = @{ Name = [string]$it.Name; Path = ''; Ok = $false; Bytes = [double]0; Note = '' }
            $name = [Mm.RcEngine]::SafeName([string]$it.Name)
            $dir = $runDir
            if ([string]$it.Kind -eq 'carve') {
                $dir = Join-Path $runDir 'İmza taraması'
            } elseif ($keep) {
                $rel = [Mm.RcEngine]::SafeRelPath([string]$it.Path)
                if ($rel -ne '') { $dir = Join-Path $runDir $rel }
            }
            if (($dir.Length + $name.Length + 2) -gt 240) { $dir = $runDir }
            if (($dir.Length + $name.Length + 2) -gt 240) {
                $ext = [System.IO.Path]::GetExtension($name)
                $name = $name.Substring(0, [math]::Max(1, 240 - $dir.Length - 2 - $ext.Length)) + $ext
            }
            $target = ''
            $fs = $null
            $okFile = $false
            try {
                [void][System.IO.Directory]::CreateDirectory($dir)
                $target = Get-RcFreeName (Join-Path $dir $name)
                $fs = New-Object System.IO.FileStream -ArgumentList $target, ([System.IO.FileMode]::CreateNew), ([System.IO.FileAccess]::Write), ([System.IO.FileShare]::None), 65536
                $curBase = $doneBytes
                $got = [long]$eng.Extract($it, $fs, $cb)
                $fs.Flush()
                $row.Bytes = [double]$got
                if ($got -lt [long]$it.Length) {
                    $row.Note = 'Okunabilen veri beklenenden kısa; dosya kaydedilmedi.'
                } else {
                    $okFile = $true
                    $row.Note = [string]$eng.LastNote
                }
            } catch [System.OperationCanceledException] {
                $res.Canceled = $true
                $row.Note = 'İptal edildi.'
            } catch {
                $row.Note = (Get-RcErrorText $_)
            } finally {
                if ($null -ne $fs) { $fs.Dispose() }
            }
            if ($okFile) {
                $dt = ConvertTo-RcDate $it.Modified
                if ($null -ne $dt) { try { [System.IO.File]::SetLastWriteTimeUtc($target, $dt) } catch { } }
                $row.Ok = $true
                $row.Path = $target
                $res.Done++
                $res.Bytes += [double]$row.Bytes
                $doneBytes += [double]$it.Length
            } else {
                if ($target -ne '' -and (Test-Path -LiteralPath $target)) { try { [System.IO.File]::Delete($target) } catch { } }
                $res.Failed++
                Write-WhLog ('Kurtarılamadı: ' + [string]$it.Name + ' (' + [string]$row.Note + ')') 'WARN'
            }
            [void]$rows.Add($row)
            if ($res.Canceled) { Write-WhLog 'İptal edildi.' 'WARN'; break }
        }
    } catch {
        $res.Error = Get-RcErrorText $_
        Write-WhLog ('Kurtarma yapılamadı: ' + $res.Error) 'ERR'
    } finally {
        if ($null -ne $eng) { $eng.Dispose() }
    }
    $res.Results = @($rows.ToArray())

    # özet rapor (noktalı virgülle ayrılmış, Excel'de açılır)
    try {
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.AppendLine('Dosya;Kaydedilen yol;Boyut (bayt);Durum;Not')
        foreach ($r in $rows) {
            $st = 'Kurtarılamadı'
            if ($r.Ok -eq $true) { $st = 'Kurtarıldı' }
            $line = @([string]$r.Name, [string]$r.Path, [string][long]$r.Bytes, $st, [string]$r.Note) | ForEach-Object { '"' + ([string]$_).Replace('"', '""') + '"' }
            [void]$sb.AppendLine(($line -join ';'))
        }
        $rp = Join-Path $runDir 'Kurtarma-Raporu.csv'
        [System.IO.File]::WriteAllText($rp, $sb.ToString(), (New-Object System.Text.UTF8Encoding($true)))
        $res.Report = $rp
    } catch { }
    Write-WhLog ('Kurtarma tamamlandı: ' + [string]$res.Done + ' dosya, ' + (Format-Size $res.Bytes) + ', ' + [string]$res.Failed + ' kurtarılamadı') 'INFO'
    $res.Ok = ($res.Error -eq '' -and $res.Done -gt 0)
    return $res
}
