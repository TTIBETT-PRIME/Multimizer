// Multimizer silme motoru. Yalnızca çağıranın verdiği aralıkların üzerine yazar; verilmeyen hiçbir bölgeye dokunmaz.
// Kurtarma motorundan (RcEngine, salt okunur) bilerek ayrı derlenir: yazma yeteneği olan kod yalnızca silme eklentisindedir.
// Yapılanlar:
//   WipeStream   AES-256-CTR ile üretilen, her konumdan yeniden hesaplanabilen rastgele akış (ya da sıfır / 0xFF deseni)
//   WipeTarget   fiziksel disk (PhysicalDriveN) ya da imaj dosyası; hizalı okuma ve yazma
//   WipeLayout   MBR (EBR dahil) ve GPT (başlık ve dizi sağlama toplamları doğrulanarak) okunur; bölümlerin dışındaki boşluklar bulunur
//   WipeEngine   aralıkları üzerine yazma, yazılanı geri okuyup doğrulama
//   WipeFs       dosyanın birim içindeki konumları (FSCTL_GET_RETRIEVAL_POINTERS), boş alan temizliği doğrulaması için
// Doğrulama: yazılan akış anahtardan yeniden üretildiği için ek veri saklanmadan her konum kontrol edilebilir.
// C# 5 uyumlu yazılmıştır (Windows PowerShell 5.1 içindeki derleyici için).
using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace Mm
{
    // stage: aşama adı, done/total: ilerleme. false dönerse iş iptal edilir.
    public delegate bool WipeProgress(string stage, long done, long total);

    public sealed class WipeExtent
    {
        public long Start;
        public long Length;
        public string Tag = "";
        // Probe için: aralığın başına karşılık gelen akış konumu (-1: aralığın kendi konumu). Dosya içinden yazılıp
        // birimde başka yerde duran veriyi (kanarya dosyaları) beklenen akışla karşılaştırmak için kullanılır.
        public long StreamPos = -1;
        public WipeExtent() { }
        public WipeExtent(long start, long length, string tag) { Start = start; Length = length; Tag = tag; }
        public long End { get { return Start + Length; } }
    }

    public sealed class WipeReport
    {
        public long Planned;            // yazılması planlanan bayt (tüm geçişler)
        public long Written;            // yazılan bayt
        public long Verified;           // geri okunup karşılaştırılan bayt
        public long BadUnits;           // beklenenden farklı çıkan birim sayısı
        public long FirstBad = -1;      // ilk farklı birimin konumu
        public int WriteErrors;
        public long FirstWriteError = -1;
        public int Passes;
        public bool Canceled;
        public string Error = "";
        public double Seconds;
        // Probe sonuçları (4096 baytlık birimler): beklenen akışla aynı / tamamen sıfır / başka içerik
        public long Units;
        public long Same;
        public long Zeroed;
        public long Changed;
    }

    // ---------------- akış üreteci ----------------
    public sealed class WipeStream : IDisposable
    {
        public const int ModeRandom = 0;
        public const int ModeZero = 1;
        public const int ModeOnes = 2;

        readonly int mode;
        Aes aes;
        ICryptoTransform enc;
        byte[] nonce = new byte[8];
        byte[] ctr = new byte[0];
        byte[] ks = new byte[0];

        // key: ana anahtar (herhangi uzunlukta); pass: geçiş numarası. Her geçiş ayrı bir akıştır.
        public WipeStream(int mode, byte[] key, int pass)
        {
            this.mode = mode;
            if (mode != ModeRandom) return;
            if (key == null || key.Length == 0) throw new ArgumentException("Anahtar yok.");
            byte[] seed = new byte[key.Length + 4];
            Buffer.BlockCopy(key, 0, seed, 0, key.Length);
            seed[key.Length] = (byte)pass;
            seed[key.Length + 1] = (byte)(pass >> 8);
            seed[key.Length + 2] = (byte)(pass >> 16);
            seed[key.Length + 3] = (byte)(pass >> 24);
            byte[] h;
            using (SHA512 sha = SHA512.Create()) { h = sha.ComputeHash(seed); }
            byte[] k = new byte[32];
            Buffer.BlockCopy(h, 0, k, 0, 32);
            Buffer.BlockCopy(h, 32, nonce, 0, 8);
            aes = Aes.Create();
            aes.Mode = CipherMode.ECB;
            aes.Padding = PaddingMode.None;
            aes.KeySize = 256;
            aes.Key = k;
            enc = aes.CreateEncryptor();
        }

        public int Mode { get { return mode; } }

        // dst[off .. off+count) alanını akışın pos konumundan başlayan baytlarıyla doldurur (pos herhangi bir değer olabilir)
        public void Fill(byte[] dst, int off, int count, long pos)
        {
            if (count <= 0) return;
            if (mode == ModeZero) { Array.Clear(dst, off, count); return; }
            if (mode == ModeOnes)
            {
                for (int i = 0; i < count; i++) dst[off + i] = 0xFF;
                return;
            }
            long blk = pos >> 4;
            int skip = (int)(pos & 15);
            int need = (skip + count + 15) & ~15;
            if (ks.Length < need)
            {
                ks = new byte[need];
                ctr = new byte[need];
                // sayaç bloğunun ikinci yarısı (nonce) sabittir; yalnızca bir kez yazılır
                for (int o = 8; o + 8 <= need; o += 16) Buffer.BlockCopy(nonce, 0, ctr, o, 8);
            }
            int nb = need >> 4;
            for (int i = 0; i < nb; i++)
            {
                long b = blk + i;
                int o = i << 4;
                ctr[o] = (byte)b; ctr[o + 1] = (byte)(b >> 8); ctr[o + 2] = (byte)(b >> 16); ctr[o + 3] = (byte)(b >> 24);
                ctr[o + 4] = (byte)(b >> 32); ctr[o + 5] = (byte)(b >> 40); ctr[o + 6] = (byte)(b >> 48); ctr[o + 7] = (byte)(b >> 56);
            }
            enc.TransformBlock(ctr, 0, need, ks, 0);
            Buffer.BlockCopy(ks, skip, dst, off, count);
        }

        public void Dispose()
        {
            if (enc != null) { enc.Dispose(); enc = null; }
            if (aes != null) { ((IDisposable)aes).Dispose(); aes = null; }
        }
    }

    // ---------------- aygıt soyutlaması ----------------
    abstract class WipeDev : IDisposable
    {
        public long Length;
        public int Sector = 512;
        public abstract int Read(long pos, byte[] dst, int off, int count);
        public abstract void Write(long pos, byte[] src, int off, int count);
        public abstract void Flush();
        public abstract void Dispose();
    }

    sealed class WipeFileDev : WipeDev
    {
        FileStream fs;
        public long FailFrom = -1;
        public long FailTo = -1;
        public WipeFileDev(string path, bool write)
        {
            FileAccess fa = write ? FileAccess.ReadWrite : FileAccess.Read;
            FileShare sh = FileShare.ReadWrite | FileShare.Delete;
            fs = new FileStream(path, FileMode.Open, fa, sh, 4096, FileOptions.None);
            Length = fs.Length;
        }
        public override int Read(long pos, byte[] dst, int off, int count)
        {
            if (pos < 0 || count <= 0 || pos >= Length) return 0;
            fs.Seek(pos, SeekOrigin.Begin);
            int got = 0;
            while (got < count)
            {
                int n = fs.Read(dst, off + got, count - got);
                if (n <= 0) break;
                got += n;
            }
            return got;
        }
        public override void Write(long pos, byte[] src, int off, int count)
        {
            if (pos < 0 || pos + count > Length) throw new IOException("Yazma, hedefin sınırlarının dışında.");
            if (FailFrom >= 0 && pos < FailTo && pos + count > FailFrom) throw new IOException("Yazma hatası (benzetim).");
            fs.Seek(pos, SeekOrigin.Begin);
            fs.Write(src, off, count);
        }
        public override void Flush() { fs.Flush(true); }
        public override void Dispose() { if (fs != null) { fs.Dispose(); fs = null; } }
    }

    // Windows fiziksel diski (\\.\PhysicalDriveN) ya da birimi (\\.\X:). Yalnızca kernel32 çağrıları.
    // Aygıt doğrudan (FILE_FLAG_NO_BUFFERING) açılır: okunan veri önbellekten değil aygıttan gelir (yazılanı doğrulamak için şarttır).
    // Doğrudan G/Ç için konum, uzunluk ve bellek adresi sektör boyutuna hizalı olmalıdır; bellek için 4096 hizalı bir yerel tampon kullanılır.
    sealed class WipeWinDev : WipeDev
    {
        SafeFileHandle h;
        IntPtr raw = IntPtr.Zero;
        IntPtr buf = IntPtr.Zero;
        int bufSize = 0;
        public readonly bool Writable;

        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern SafeFileHandle CreateFile(string name, uint access, uint share, IntPtr security, uint disposition, uint flags, IntPtr template);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool SetFilePointerEx(SafeFileHandle h, long dist, out long newPos, uint method);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool ReadFile(SafeFileHandle h, IntPtr buf, uint count, out uint read, IntPtr overlapped);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool WriteFile(SafeFileHandle h, IntPtr buf, uint count, out uint written, IntPtr overlapped);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool FlushFileBuffers(SafeFileHandle h);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool DeviceIoControl(SafeFileHandle h, uint code, IntPtr inBuf, uint inSize, byte[] outBuf, uint outSize, out uint returned, IntPtr overlapped);

        const uint IoctlDiskGetLengthInfo = 0x0007405C;
        const uint IoctlDiskGetGeometryEx = 0x000700A0;

        public WipeWinDev(string path, bool write)
        {
            Writable = write;
            uint access = 0x80000000u;                       // GENERIC_READ
            uint flags = 0x20000000u;                        // FILE_FLAG_NO_BUFFERING
            if (write) { access |= 0x40000000u; flags |= 0x80000000u; }   // GENERIC_WRITE, FILE_FLAG_WRITE_THROUGH
            h = CreateFile(path, access, 3u, IntPtr.Zero, 3u, flags, IntPtr.Zero);
            if (h.IsInvalid)
            {
                int err = Marshal.GetLastWin32Error();
                if (err == 5) throw new IOException("Erişim engellendi. Multimizer uygulamasını yönetici olarak çalıştırın; disk salt okunur ya da başka bir program tarafından kullanılıyor olabilir.");
                if (err == 2 || err == 3 || err == 21) throw new IOException("Disk bulunamadı ya da hazır değil.");
                if (err == 19) throw new IOException("Disk yazmaya karşı korumalı.");
                throw new IOException("Disk açılamadı (Windows hata kodu " + err + ").");
            }
            byte[] b8 = new byte[8];
            uint ret;
            if (DeviceIoControl(h, IoctlDiskGetLengthInfo, IntPtr.Zero, 0, b8, 8, out ret, IntPtr.Zero)) Length = BitConverter.ToInt64(b8, 0);
            byte[] geo = new byte[64];
            if (DeviceIoControl(h, IoctlDiskGetGeometryEx, IntPtr.Zero, 0, geo, 64, out ret, IntPtr.Zero))
            {
                int bps = BitConverter.ToInt32(geo, 20);
                if (bps >= 512 && bps <= 65536) Sector = bps;
            }
        }

        void EnsureBuf(int n)
        {
            if (buf != IntPtr.Zero && bufSize >= n) return;
            FreeBuf();
            int size = n + 8192;
            raw = Marshal.AllocHGlobal(size);
            long a = raw.ToInt64();
            long al = (a + 4095) & ~4095L;
            buf = new IntPtr(al);
            bufSize = size - (int)(al - a);
        }

        void FreeBuf()
        {
            if (raw != IntPtr.Zero) { Marshal.FreeHGlobal(raw); raw = IntPtr.Zero; buf = IntPtr.Zero; bufSize = 0; }
        }

        public override int Read(long pos, byte[] dst, int off, int count)
        {
            if (pos < 0 || count <= 0) return 0;
            if ((pos % Sector) != 0 || (count % Sector) != 0) throw new IOException("Okuma sektör sınırına hizalı değil.");
            long np;
            if (!SetFilePointerEx(h, pos, out np, 0u)) throw new IOException("Konuma gidilemedi (Windows hata kodu " + Marshal.GetLastWin32Error() + ").");
            EnsureBuf(count);
            uint rd;
            if (!ReadFile(h, buf, (uint)count, out rd, IntPtr.Zero)) throw new IOException("Okunamadı (Windows hata kodu " + Marshal.GetLastWin32Error() + ").");
            Marshal.Copy(buf, dst, off, (int)rd);
            return (int)rd;
        }

        public override void Write(long pos, byte[] src, int off, int count)
        {
            if (!Writable) throw new IOException("Aygıt salt okunur açıldı.");
            if ((pos % Sector) != 0 || (count % Sector) != 0) throw new IOException("Yazma sektör sınırına hizalı değil.");
            long np;
            if (!SetFilePointerEx(h, pos, out np, 0u)) throw new IOException("Konuma gidilemedi (Windows hata kodu " + Marshal.GetLastWin32Error() + ").");
            EnsureBuf(count);
            Marshal.Copy(src, off, buf, count);
            uint wr;
            if (!WriteFile(h, buf, (uint)count, out wr, IntPtr.Zero))
            {
                int err = Marshal.GetLastWin32Error();
                if (err == 5) throw new UnauthorizedAccessException("Bu alana yazılamıyor: bölüm Windows tarafından kullanılıyor ya da disk korumalı.");
                throw new IOException("Yazılamadı (Windows hata kodu " + err + ").");
            }
            if ((int)wr != count) throw new IOException("Eksik yazıldı.");
        }

        public override void Flush() { if (Writable && h != null && !h.IsClosed) FlushFileBuffers(h); }
        public override void Dispose()
        {
            if (h != null) { h.Dispose(); h = null; }
            FreeBuf();
        }
    }

    // ---------------- hedef ----------------
    public sealed class WipeTarget : IDisposable
    {
        const long Align = 4096;
        WipeDev dev;
        byte[] scratch = new byte[0];
        public readonly bool IsDevice;
        public readonly bool Writable;
        public readonly string Spec;

        WipeTarget(WipeDev d, bool isDevice, bool writable, string spec)
        {
            dev = d; IsDevice = isDevice; Writable = writable; Spec = spec;
        }

        public long Length { get { return dev.Length; } }
        public int SectorSize { get { return dev.Sector; } }

        // "PhysicalDrive3" / "\\.\PhysicalDrive3" -> 3
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

        static bool IsDriveSpec(string s)
        {
            string t = s.Trim();
            return t.Length == 2 && Char.IsLetter(t[0]) && t[1] == ':';
        }

        // spec: "PhysicalDriveN" (disk), "X:" (birim; yalnızca okuma) ya da imaj dosyası yolu. Aygıt yolu başka biçimde verilirse reddedilir.
        // Yalnızca sınama için: imaj dosyasını açar ve [failFrom, failTo) aralığına değen her yazmada IOException verir.
        public static WipeTarget OpenFaulty(string path, long failFrom, long failTo)
        {
            WipeFileDev fd = new WipeFileDev(path, true);
            fd.FailFrom = failFrom; fd.FailTo = failTo;
            return new WipeTarget(fd, false, true, path);
        }

        public static WipeTarget Open(string spec, bool write)
        {
            if (spec == null || spec.Trim().Length == 0) throw new IOException("Hedef belirtilmedi.");
            string s = spec.Trim();
            int dn;
            if (DiskNumberOf(s, out dn))
            {
                WipeWinDev wd = new WipeWinDev("\\\\.\\PhysicalDrive" + dn, write);
                return new WipeTarget(wd, true, write, "PhysicalDrive" + dn);
            }
            if (IsDriveSpec(s))
            {
                if (write) throw new IOException("Birimlere doğrudan yazılmaz.");
                WipeWinDev vd = new WipeWinDev("\\\\.\\" + s.Substring(0, 1).ToUpperInvariant() + ":", false);
                return new WipeTarget(vd, true, false, s.Substring(0, 1).ToUpperInvariant() + ":");
            }
            if (s.StartsWith("\\\\.\\", StringComparison.Ordinal) || s.StartsWith("\\\\?\\", StringComparison.Ordinal)) throw new IOException("Bu aygıt yolu desteklenmiyor.");
            WipeFileDev fd = new WipeFileDev(s, write);
            return new WipeTarget(fd, false, write, s);
        }

        public int ReadAt(long pos, byte[] dst, int off, int count)
        {
            if (count <= 0 || pos < 0) return 0;
            if (!IsDevice) return dev.Read(pos, dst, off, count);
            long al = Math.Max(Align, (long)dev.Sector);
            long a0 = pos - (pos % al);
            long a1 = ((pos + count + al - 1) / al) * al;
            if (dev.Length > 0 && a1 > dev.Length) a1 = ((dev.Length + dev.Sector - 1) / dev.Sector) * dev.Sector;
            int alen = (int)(a1 - a0);
            if (alen <= 0) return 0;
            if (scratch.Length < alen) scratch = new byte[alen];
            int got = dev.Read(a0, scratch, 0, alen);
            int skip = (int)(pos - a0);
            int avail = got - skip;
            if (avail <= 0) return 0;
            int take = Math.Min(count, avail);
            Buffer.BlockCopy(scratch, skip, dst, off, take);
            return take;
        }

        // Aygıtlarda konum ve uzunluk sektör boyutunun katı olmalıdır (imaj dosyalarında serbest)
        public void WriteAt(long pos, byte[] src, int off, int count)
        {
            if (!Writable) throw new IOException("Hedef salt okunur açıldı.");
            if (IsDevice && ((pos % dev.Sector) != 0 || (count % dev.Sector) != 0)) throw new IOException("Yazma konumu sektör sınırına hizalı değil.");
            dev.Write(pos, src, off, count);
        }

        public void Flush() { dev.Flush(); }

        public void Dispose()
        {
            if (dev != null) { dev.Dispose(); dev = null; }
        }
    }

    // ---------------- bölüm düzeni ----------------
    public static class WipeLayout
    {
        static uint[] crcTable;

        static uint Crc32(byte[] b, int off, int count)
        {
            if (crcTable == null)
            {
                uint[] t = new uint[256];
                for (uint i = 0; i < 256; i++)
                {
                    uint c = i;
                    for (int k = 0; k < 8; k++) c = ((c & 1) != 0) ? (0xEDB88320u ^ (c >> 1)) : (c >> 1);
                    t[i] = c;
                }
                crcTable = t;
            }
            uint crc = 0xFFFFFFFFu;
            for (int i = 0; i < count; i++) crc = crcTable[(crc ^ b[off + i]) & 0xFF] ^ (crc >> 8);
            return crc ^ 0xFFFFFFFFu;
        }

        static uint U32(byte[] b, int o) { return (uint)(b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24)); }
        static ulong U64(byte[] b, int o) { return (ulong)U32(b, o) | ((ulong)U32(b, o + 4) << 32); }

        static bool IsZero(byte[] b, int o, int n)
        {
            for (int i = 0; i < n; i++) { if (b[o + i] != 0) return false; }
            return true;
        }

        // Bölüm tablosu yapıları ve bölümler dahil, diskte "dolu" sayılan aralıklar.
        // style: GPT | MBR | BOS (tablo yok, ilk 4 KiB sıfır) | BIRIM (diskin başında tek dosya sistemi var) | BILINMIYOR (çözülemedi: tüm disk dolu sayılır)
        public static WipeExtent[] ReadOccupied(WipeTarget t, out string style, out string note)
        {
            style = "BILINMIYOR";
            note = "";
            List<WipeExtent> occ = new List<WipeExtent>();
            long len = t.Length;
            WipeExtent whole = new WipeExtent(0, len, "tüm disk");
            byte[] b0 = new byte[4096];
            int n = t.ReadAt(0, b0, 0, 4096);
            if (n < 512) { note = "Diskin başı okunamadı."; return new WipeExtent[] { whole }; }
            if (IsZero(b0, 0, Math.Min(n, 4096)))
            {
                style = "BOS";
                note = "Bölüm tablosu yok; disk boş görünüyor.";
                return new WipeExtent[0];
            }
            int ss = t.SectorSize;
            // GPT: LBA1'de başlık
            byte[] hdr = new byte[4096];
            int gpos = -1;
            int gss = 512;
            if (t.ReadAt(512, hdr, 0, 512) >= 512 && hdr[0] == 'E' && hdr[1] == 'F' && hdr[2] == 'I' && hdr[3] == ' ' && hdr[4] == 'P' && hdr[5] == 'A' && hdr[6] == 'R' && hdr[7] == 'T') { gpos = 512; gss = 512; }
            else if (t.ReadAt(4096, hdr, 0, 512) >= 512 && hdr[0] == 'E' && hdr[1] == 'F' && hdr[2] == 'I' && hdr[3] == ' ' && hdr[4] == 'P' && hdr[5] == 'A' && hdr[6] == 'R' && hdr[7] == 'T') { gpos = 4096; gss = 4096; }
            if (gpos > 0)
            {
                style = "GPT";
                uint hsz = U32(hdr, 12);
                if (hsz < 92 || hsz > 512) { style = "BILINMIYOR"; note = "GPT başlığı geçersiz."; return new WipeExtent[] { whole }; }
                uint crcStored = U32(hdr, 16);
                byte[] hcopy = new byte[hsz];
                Buffer.BlockCopy(hdr, 0, hcopy, 0, (int)hsz);
                hcopy[16] = 0; hcopy[17] = 0; hcopy[18] = 0; hcopy[19] = 0;
                if (Crc32(hcopy, 0, (int)hsz) != crcStored) { style = "BILINMIYOR"; note = "GPT başlığının sağlama toplamı tutmuyor."; return new WipeExtent[] { whole }; }
                long firstUsable = (long)U64(hdr, 40);
                long lastUsable = (long)U64(hdr, 48);
                long entLba = (long)U64(hdr, 72);
                long cnt = U32(hdr, 80);
                long esz = U32(hdr, 84);
                uint arrCrc = U32(hdr, 88);
                if (cnt <= 0 || cnt > 1024 || esz < 128 || esz > 1024 || entLba < 2 || firstUsable < 2 || lastUsable < firstUsable)
                { style = "BILINMIYOR"; note = "GPT bölüm dizisi geçersiz."; return new WipeExtent[] { whole }; }
                long arrBytes = cnt * esz;
                byte[] arr = new byte[arrBytes];
                int got = t.ReadAt(entLba * gss, arr, 0, (int)arrBytes);
                if (got < arrBytes || Crc32(arr, 0, (int)arrBytes) != arrCrc) { style = "BILINMIYOR"; note = "GPT bölüm dizisinin sağlama toplamı tutmuyor."; return new WipeExtent[] { whole }; }
                // koruyucu MBR + başlık + dizi
                occ.Add(new WipeExtent(0, firstUsable * gss, "GPT başı"));
                long tailStart = (lastUsable + 1) * gss;
                if (tailStart < len) occ.Add(new WipeExtent(tailStart, len - tailStart, "GPT sonu"));
                for (int i = 0; i < cnt; i++)
                {
                    int o = (int)(i * esz);
                    if (IsZero(arr, o, 16)) continue;
                    long first = (long)U64(arr, o + 32);
                    long last = (long)U64(arr, o + 40);
                    if (first < firstUsable || last < first || (last + 1) * gss > len)
                    { style = "BILINMIYOR"; note = "GPT bölüm girdisi diskin dışına taşıyor."; return new WipeExtent[] { whole }; }
                    occ.Add(new WipeExtent(first * gss, (last - first + 1) * gss, "bölüm"));
                }
                return occ.ToArray();
            }
            // MBR
            if (n >= 512 && b0[510] == 0x55 && b0[511] == 0xAA)
            {
                int used = 0;
                bool gptProtective = false;
                List<WipeExtent> mbr = new List<WipeExtent>();
                mbr.Add(new WipeExtent(0, ss, "MBR"));
                for (int i = 0; i < 4; i++)
                {
                    int o = 446 + 16 * i;
                    int status = b0[o];
                    int type = b0[o + 4];
                    if (status != 0x00 && status != 0x80) { note = "Bölüm tablosu geçersiz."; return new WipeExtent[] { whole }; }
                    long lba = U32(b0, o + 8);
                    long cnt = U32(b0, o + 12);
                    if (type == 0) continue;
                    if (type == 0xEE) { gptProtective = true; continue; }
                    if (lba < 1 || cnt < 1 || (lba + cnt) * (long)ss > len) { note = "Bölüm girdisi diskin dışına taşıyor."; return new WipeExtent[] { whole }; }
                    used++;
                    mbr.Add(new WipeExtent(lba * ss, cnt * ss, "bölüm"));
                }
                if (gptProtective) { style = "BILINMIYOR"; note = "Koruyucu MBR var ama GPT başlığı okunamadı."; return new WipeExtent[] { whole }; }
                if (used == 0) { style = "BILINMIYOR"; note = "Bölüm tablosu boş ya da tanınmadı."; return new WipeExtent[] { whole }; }
                style = "MBR";
                return mbr.ToArray();
            }
            // tablosuz tek birim (süper disket) ya da tanınmayan veri
            style = "BIRIM";
            note = "Diskin başında bölüm tablosu yok; tek bir dosya sistemi ya da tanınmayan veri var.";
            return new WipeExtent[] { whole };
        }

        // Diskin başındaki ve sonundaki guard baytlık bölgeler (bölüm tablosu yapıları burada durur). Disk bu iki bölgeyi
        // ayırmaya yetmeyecek kadar küçükse tek bölge döner.
        public static WipeExtent[] EdgeGuards(long length, long guard, int sector)
        {
            if (sector < 512) sector = 512;
            long g = ((guard + sector - 1) / sector) * sector;
            long len = (length / sector) * sector;
            if (len <= 0) return new WipeExtent[0];
            if (len <= g * 2) return new WipeExtent[] { new WipeExtent(0, len, "baş ve son") };
            return new WipeExtent[] { new WipeExtent(0, g, "baş"), new WipeExtent(len - g, g, "son") };
        }

        // Dolu aralıkların dışında kalan boşluklar. headGuard/tailGuard: diskin başında ve sonunda dokunulmayacak bayt;
        // minGap: bundan küçük boşluklar atlanır; align: boşluklar bu değere hizalanarak içe doğru daraltılır (4096)
        public static WipeExtent[] Gaps(long length, WipeExtent[] occupied, long headGuard, long tailGuard, long minGap, long align)
        {
            List<WipeExtent> occ = new List<WipeExtent>();
            foreach (WipeExtent e in occupied) { if (e != null && e.Length > 0) occ.Add(e); }
            occ.Sort(delegate(WipeExtent a, WipeExtent b) { return a.Start.CompareTo(b.Start); });
            long lo = Math.Max(0, headGuard);
            long hi = length - Math.Max(0, tailGuard);
            List<WipeExtent> res = new List<WipeExtent>();
            if (hi <= lo) return res.ToArray();
            long cur = lo;
            foreach (WipeExtent e in occ)
            {
                if (e.End <= cur) continue;
                if (e.Start >= hi) break;
                if (e.Start > cur) AddGap(res, cur, Math.Min(e.Start, hi), minGap, align);
                if (e.End > cur) cur = e.End;
                if (cur >= hi) break;
            }
            if (cur < hi) AddGap(res, cur, hi, minGap, align);
            return res.ToArray();
        }

        static void AddGap(List<WipeExtent> res, long s, long e, long minGap, long align)
        {
            if (align > 1)
            {
                s = ((s + align - 1) / align) * align;
                e = (e / align) * align;
            }
            if (e - s >= minGap && e > s) res.Add(new WipeExtent(s, e - s, "ayrılmamış"));
        }
    }

    // ---------------- yazma ve doğrulama ----------------
    public static class WipeEngine
    {
        public const int Block = 4 * 1024 * 1024;
        public const int Unit = 64 * 1024;
        const int ProbeUnit = 4096;
        const int MaxWriteErrors = 32;

        public static byte[] NewKey()
        {
            byte[] k = new byte[32];
            using (RandomNumberGenerator rng = RandomNumberGenerator.Create()) { rng.GetBytes(k); }
            return k;
        }

        static int Seed(byte[] key)
        {
            if (key == null || key.Length < 4) return 17;
            return BitConverter.ToInt32(key, 0);
        }

        static long Total(WipeExtent[] ext)
        {
            long total = 0;
            foreach (WipeExtent e in ext) total += e.Length;
            return total;
        }

        // Aralıkların sınır ve hizalama denetimi. Dönüş: "" = uygun, aksi hâlde neden
        public static string CheckExtents(WipeTarget t, WipeExtent[] ext)
        {
            if (ext == null || ext.Length == 0) return "Silinecek aralık yok.";
            long len = t.Length;
            long prevEnd = -1;
            List<WipeExtent> sorted = new List<WipeExtent>(ext);
            sorted.Sort(delegate(WipeExtent a, WipeExtent b) { return a.Start.CompareTo(b.Start); });
            foreach (WipeExtent e in sorted)
            {
                if (e.Start < 0 || e.Length <= 0) return "Geçersiz aralık.";
                if (len > 0 && e.End > len) return "Aralık diskin dışına taşıyor.";
                if (e.Start < prevEnd) return "Aralıklar çakışıyor.";
                prevEnd = e.End;
                if (t.IsDevice)
                {
                    if ((e.Start % t.SectorSize) != 0) return "Aralık sektör sınırına hizalı değil.";
                    if ((e.Length % t.SectorSize) != 0) return "Aralık uzunluğu sektör boyutunun katı değil.";
                }
            }
            return "";
        }

        // modes: her geçişin deseni (WipeStream.ModeRandom / ModeZero / ModeOnes). Aralıklar sırayla her geçişte yazılır.
        public static WipeReport Fill(WipeTarget t, WipeExtent[] ext, int[] modes, byte[] key, WipeProgress prog)
        {
            WipeReport r = new WipeReport();
            DateTime t0 = DateTime.UtcNow;
            r.Passes = modes == null ? 0 : modes.Length;
            if (modes == null || modes.Length == 0) { r.Error = "Geçiş belirtilmedi."; return r; }
            if (!t.Writable) { r.Error = "Hedef yazmaya açık değil."; return r; }
            string bad = CheckExtents(t, ext);
            if (bad.Length > 0) { r.Error = bad; return r; }
            long total = Total(ext);
            r.Planned = total * modes.Length;
            byte[] buf = new byte[Block];
            int lastTick = Environment.TickCount;
            for (int p = 0; p < modes.Length && !r.Canceled && r.Error.Length == 0; p++)
            {
                using (WipeStream ws = new WipeStream(modes[p], key, p))
                {
                    foreach (WipeExtent e in ext)
                    {
                        long pos = e.Start;
                        long end = e.End;
                        while (pos < end)
                        {
                            int n = (int)Math.Min((long)Block, end - pos);
                            ws.Fill(buf, 0, n, pos);
                            bool ok = false;
                            for (int attempt = 0; attempt < 2 && !ok; attempt++)
                            {
                                try { t.WriteAt(pos, buf, 0, n); ok = true; }
                                catch (UnauthorizedAccessException ex) { r.Error = ex.Message; break; }
                                catch (IOException ex2)
                                {
                                    if (attempt == 1)
                                    {
                                        r.WriteErrors++;
                                        if (r.FirstWriteError < 0) r.FirstWriteError = pos;
                                        if (r.WriteErrors >= MaxWriteErrors) r.Error = "Çok sayıda yazma hatası oldu (" + ex2.Message + "). Disk bozuk olabilir.";
                                    }
                                }
                            }
                            if (r.Error.Length > 0) break;
                            pos += n;
                            if (ok) r.Written += n; else r.Planned -= n;
                            int now = Environment.TickCount;
                            if (prog != null && (now - lastTick > 150 || pos >= end))
                            {
                                lastTick = now;
                                if (!prog("Yazılıyor", r.Written, r.Planned)) { r.Canceled = true; break; }
                            }
                        }
                        if (r.Canceled || r.Error.Length > 0) break;
                    }
                    try { t.Flush(); } catch (IOException) { }
                }
            }
            if (prog != null && !r.Canceled && r.Error.Length == 0) prog("Yazılıyor", r.Written, r.Planned);
            r.Seconds = (DateTime.UtcNow - t0).TotalSeconds;
            return r;
        }

        // Birimleri okuyup beklenen akışla karşılaştırır (Verify'in ortak gövdesi)
        static bool VerifyUnits(WipeTarget t, List<long[]> units, long planned, WipeStream ws, WipeReport r, WipeProgress prog)
        {
            byte[] got = new byte[Block];
            byte[] want = new byte[Block];
            int lastTick = Environment.TickCount;
            foreach (long[] u in units)
            {
                int n = (int)u[1];
                int rd = t.ReadAt(u[0], got, 0, n);
                ws.Fill(want, 0, n, u[0]);
                bool same = (rd == n);
                if (same)
                {
                    for (int i = 0; i < n; i++) { if (got[i] != want[i]) { same = false; break; } }
                }
                r.Verified += n;
                if (!same)
                {
                    r.BadUnits++;
                    if (r.FirstBad < 0) r.FirstBad = u[0];
                }
                int now = Environment.TickCount;
                if (prog != null && now - lastTick > 150)
                {
                    lastTick = now;
                    if (!prog("Doğrulanıyor", r.Verified, planned)) { r.Canceled = true; return false; }
                }
            }
            return true;
        }

        // Yazılan akışı geri okuyup karşılaştırır. samples <= 0: tamamı; aksi hâlde her aralığın başı ve sonu + dağılmış rastgele samples birim (64 KiB).
        // mode ve pass, yazmada kullanılanlarla (son geçişle) aynı olmalıdır.
        public static WipeReport Verify(WipeTarget t, WipeExtent[] ext, int mode, byte[] key, int pass, int samples, WipeProgress prog)
        {
            WipeReport r = new WipeReport();
            DateTime t0 = DateTime.UtcNow;
            r.Passes = 1;
            string bad = CheckExtents(t, ext);
            if (bad.Length > 0) { r.Error = bad; return r; }
            List<long[]> units = new List<long[]>();   // {konum, uzunluk}
            long planned = 0;
            if (samples <= 0)
            {
                // tamamı: birimler sırayla üretilir, büyük disklerde listeye yığılmaz
                planned = Total(ext);
                r.Planned = planned;
                using (WipeStream ws = new WipeStream(mode, key, pass))
                {
                    foreach (WipeExtent e in ext)
                    {
                        long pos = e.Start;
                        List<long[]> one = new List<long[]>();
                        while (pos < e.End)
                        {
                            int n = (int)Math.Min((long)Block, e.End - pos);
                            one.Add(new long[] { pos, n });
                            pos += n;
                            if (one.Count >= 64 || pos >= e.End)
                            {
                                if (!VerifyUnits(t, one, planned, ws, r, prog)) { r.Seconds = (DateTime.UtcNow - t0).TotalSeconds; return r; }
                                one.Clear();
                            }
                        }
                    }
                }
                if (prog != null && !r.Canceled) prog("Doğrulanıyor", r.Verified, planned);
                r.Seconds = (DateTime.UtcNow - t0).TotalSeconds;
                return r;
            }
            Random rnd = new Random(Seed(key) ^ 0x5A17);
            long total = Total(ext);
            foreach (WipeExtent e in ext)
            {
                long first = e.Start;
                int fl = (int)Math.Min((long)Unit, e.Length);
                units.Add(new long[] { first, fl });
                if (e.Length > Unit)
                {
                    long lastStart = e.End - Math.Min((long)Unit, e.Length);
                    if (t.IsDevice) lastStart -= (lastStart % t.SectorSize);
                    if (lastStart >= first + fl) units.Add(new long[] { lastStart, e.End - lastStart > Unit ? Unit : e.End - lastStart });
                }
            }
            for (int i = 0; i < samples && total > Unit; i++)
            {
                long pick = (long)(rnd.NextDouble() * (double)(total - Unit));
                // pick, aralıklar arasında dağıtılmış bayt sayısıdır; gerçek konuma çevir
                long acc = 0;
                foreach (WipeExtent e in ext)
                {
                    if (pick < acc + e.Length)
                    {
                        long pos2 = e.Start + (pick - acc);
                        if (t.IsDevice) pos2 -= (pos2 % t.SectorSize);
                        long ulen = Math.Min((long)Unit, e.End - pos2);
                        if (t.IsDevice) ulen -= (ulen % t.SectorSize);
                        if (ulen > 0) units.Add(new long[] { pos2, ulen });
                        break;
                    }
                    acc += e.Length;
                }
            }
            units.Sort(delegate(long[] a, long[] b) { return a[0].CompareTo(b[0]); });
            foreach (long[] u in units) planned += u[1];
            r.Planned = planned;
            using (WipeStream ws2 = new WipeStream(mode, key, pass))
            {
                if (!VerifyUnits(t, units, planned, ws2, r, prog)) { r.Seconds = (DateTime.UtcNow - t0).TotalSeconds; return r; }
            }
            if (prog != null && !r.Canceled) prog("Doğrulanıyor", r.Verified, planned);
            r.Seconds = (DateTime.UtcNow - t0).TotalSeconds;
            return r;
        }

        // Kanarya sınaması: aralıklardaki her 4096 baytlık birim, beklenen akışla aynı mı (Same), tamamen sıfır mı (Zeroed)
        // ya da başka bir içerik mi (Changed)? Aralığın StreamPos değeri verilmişse akış o konumdan başlar.
        // Aygıtı yalnızca okur.
        public static WipeReport Probe(WipeTarget t, WipeExtent[] ext, int mode, byte[] key, int pass, WipeProgress prog)
        {
            WipeReport r = new WipeReport();
            DateTime t0 = DateTime.UtcNow;
            r.Passes = 1;
            if (ext == null || ext.Length == 0) { r.Error = "Sınanacak aralık yok."; return r; }
            long len = t.Length;
            byte[] got = new byte[ProbeUnit];
            byte[] want = new byte[ProbeUnit];
            long planned = 0;
            foreach (WipeExtent e in ext) planned += e.Length;
            r.Planned = planned;
            int lastTick = Environment.TickCount;
            using (WipeStream ws = new WipeStream(mode, key, pass))
            {
                foreach (WipeExtent e in ext)
                {
                    if (e.Start < 0 || e.Length <= 0 || (len > 0 && e.End > len)) { r.Error = "Sınama aralığı geçersiz."; return r; }
                    long pos = e.Start;
                    while (pos < e.End)
                    {
                        int n = (int)Math.Min((long)ProbeUnit, e.End - pos);
                        int rd = t.ReadAt(pos, got, 0, n);
                        long sp = (e.StreamPos >= 0) ? (e.StreamPos + (pos - e.Start)) : pos;
                        ws.Fill(want, 0, n, sp);
                        r.Units++;
                        if (rd < n) { r.Changed++; }
                        else
                        {
                            bool same = true;
                            bool zero = true;
                            for (int i = 0; i < n; i++)
                            {
                                byte g = got[i];
                                if (g != want[i]) same = false;
                                if (g != 0) zero = false;
                                if (!same && !zero) break;
                            }
                            if (same) r.Same++;
                            else if (zero) r.Zeroed++;
                            else r.Changed++;
                        }
                        pos += n;
                        r.Verified += n;
                        int now = Environment.TickCount;
                        if (prog != null && now - lastTick > 150)
                        {
                            lastTick = now;
                            if (!prog("Denetleniyor", r.Verified, planned)) { r.Canceled = true; return r; }
                        }
                    }
                }
            }
            r.Seconds = (DateTime.UtcNow - t0).TotalSeconds;
            return r;
        }

        // Aralıkta rastgele seçilen birimlerin tamamen sıfır olup olmadığını denetler. Dönüş: sıfır olmayan birim sayısı
        public static long CountNonZeroUnits(WipeTarget t, WipeExtent[] ext, int samples, byte[] key)
        {
            long bad = 0;
            byte[] buf = new byte[Unit];
            Random rnd = new Random(Seed(key) ^ 0x2B3C);
            foreach (WipeExtent e in ext)
            {
                int cnt = samples <= 0 ? (int)Math.Min(1024L, (e.Length + Unit - 1) / Unit) : Math.Max(1, samples / Math.Max(1, ext.Length));
                for (int i = 0; i < cnt; i++)
                {
                    long pos = e.Start;
                    if (e.Length > Unit) pos = e.Start + (long)(rnd.NextDouble() * (double)(e.Length - Unit));
                    if (t.IsDevice) pos -= (pos % t.SectorSize);
                    int n = (int)Math.Min((long)Unit, e.End - pos);
                    if (t.IsDevice) n -= (n % t.SectorSize);
                    if (n <= 0) continue;
                    int rd = t.ReadAt(pos, buf, 0, n);
                    for (int k = 0; k < rd; k++) { if (buf[k] != 0) { bad++; break; } }
                }
            }
            return bad;
        }
    }

    // ---------------- dosya sistemi bilgisi ----------------
    public static class WipeFs
    {
        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern SafeFileHandle CreateFile(string name, uint access, uint share, IntPtr security, uint disposition, uint flags, IntPtr template);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool DeviceIoControl(SafeFileHandle h, uint code, byte[] inBuf, uint inSize, byte[] outBuf, uint outSize, out uint returned, IntPtr overlapped);
        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern bool GetDiskFreeSpace(string root, out uint spc, out uint bps, out uint freeClusters, out uint totalClusters);

        const uint FsctlGetRetrievalPointers = 0x00090073;

        // Dosyanın birim içindeki konumları: {bayt konumu, bayt uzunluğu, ...}. Küçük (MFT içinde saklanan), seyrek ya da okunamayan dosyalar için boş dizi.
        // Yalnızca Windows'ta çalışır; dosyayı açmadan yalnızca nitelik okur, veriye dokunmaz.
        public static long[] QueryExtents(string path, out long clusterSize)
        {
            clusterSize = 0;
            string root = Path.GetPathRoot(Path.GetFullPath(path));
            uint spc, bps, fc, tc;
            if (!GetDiskFreeSpace(root, out spc, out bps, out fc, out tc)) return new long[0];
            clusterSize = (long)spc * (long)bps;
            SafeFileHandle h = CreateFile(path, 0x80u, 7u, IntPtr.Zero, 3u, 0x02000000u, IntPtr.Zero);
            if (h.IsInvalid) return new long[0];
            List<long> res = new List<long>();
            try
            {
                long startVcn = 0;
                for (int round = 0; round < 64; round++)
                {
                    byte[] inb = BitConverter.GetBytes(startVcn);
                    byte[] outb = new byte[65536];
                    uint ret;
                    bool ok = DeviceIoControl(h, FsctlGetRetrievalPointers, inb, 8, outb, (uint)outb.Length, out ret, IntPtr.Zero);
                    int err = ok ? 0 : Marshal.GetLastWin32Error();
                    if (!ok && err != 234) break;   // 234: ERROR_MORE_DATA (kalan parçalar sonraki turda)
                    int count = BitConverter.ToInt32(outb, 0);
                    long vcn = BitConverter.ToInt64(outb, 8);
                    long lastNext = vcn;
                    for (int i = 0; i < count; i++)
                    {
                        int o = 16 + i * 16;
                        if (o + 16 > outb.Length) break;
                        long next = BitConverter.ToInt64(outb, o);
                        long lcn = BitConverter.ToInt64(outb, o + 8);
                        long clusters = next - vcn;
                        if (lcn >= 0 && clusters > 0)
                        {
                            res.Add(lcn * clusterSize);
                            res.Add(clusters * clusterSize);
                        }
                        vcn = next;
                        lastNext = next;
                    }
                    if (ok) break;
                    startVcn = lastNext;
                }
            }
            finally { h.Dispose(); }
            return res.ToArray();
        }
    }
}
