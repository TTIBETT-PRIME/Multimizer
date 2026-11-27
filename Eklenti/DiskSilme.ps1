# ==================================================================
#  Multimizer eklentisi: disk silme (boş alan temizliği, TRIM, ayrılmamış alan, bölüm ve tüm disk silme).
#  Çözüm Merkezi "Kalıcı silme" sekmesinde kullanıcı onay verdikten sonra yüklenir; tek başına çalıştırılmaz.
#  Bu dosya derleme sırasında "build\src" altındaki kaynaklardan üretilir (DiskSilme.tpl.ps1 + WipeEngine.cs); elle değiştirmeyin.
#  Ana betikten kullanılanlar: Write-WhLog, Test-JobCancel, Set-JobProgress, Format-Size ve çekirdekteki Get-Wipe* işlevleri.
#
#  Güvenlik kuralları:
#   1. Var olan dosyalara dokunulmaz: boş alan temizliği yalnızca kendi geçici klasörüne yazar ve iş bitince (iptalde de) siler.
#   2. Ham disk yazımı yalnızca çekirdekteki denetimlerden geçen disklere yapılır: Windows, Multimizer ya da geçici dosyaların
#      bulunduğu, çevrimdışı, salt okunur ve havuz üyesi diskler reddedilir; disk, onaydaki boyut/ad/seri numarasıyla yeniden karşılaştırılır.
#   3. "Ayrılmamış alan" kapsamında yalnızca bölüm tablosunun ve Windows’un bildirdiği bölümlerin DIŞINDA kalan boşluklar yazılır;
#      her iki kaynak birleştirilir, çözülemeyen düzenler tamamen dolu sayılır, diskin başında ve sonunda 1 MiB korunur.
#   4. Bölüm ve tüm disk silmede önce Windows’un kendi komutları (Remove-Partition, Clear-Disk) çalışır, ardından alan üzerine yazılır.
#   5. Yazılan her şey anahtardan yeniden üretilebilen AES-256-CTR akışıdır; doğrulama için ek veri saklanmaz.
#  Sınırlar: SSD’lerde üzerine yazma NIST SP 800-88 Rev.1 anlamında "Clear" düzeyindedir; denetleyicinin ayırdığı gizli hücrelere
#  ulaşılamaz. Yedekler, gölge kopyalar, bulut eşleşmeleri ve dosya adı kayıtları (MFT, USN) bu yöntemle silinmez.
#  Hiçbir standart için belgelendirme iddiası yoktur.
# ==================================================================

# Motoru bu oturuma derler. Dönüş: '' = hazır, aksi hâlde neden.
function global:Initialize-MmWipe {
    if ($null -ne ('Mm.WipeEngine' -as [type])) { return '' }
    $src = @'
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
            if (pos < 0 || pos + count > Length) throw new IOException("Yazma, hedefin s\u0131n\u0131rlar\u0131n\u0131n d\u0131\u015f\u0131nda.");
            if (FailFrom >= 0 && pos < FailTo && pos + count > FailFrom) throw new IOException("Yazma hatas\u0131 (benzetim).");
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
                if (err == 5) throw new IOException("Eri\u015fim engellendi. Multimizer uygulamas\u0131n\u0131 y\u00f6netici olarak \u00e7al\u0131\u015ft\u0131r\u0131n; disk salt okunur ya da ba\u015fka bir program taraf\u0131ndan kullan\u0131l\u0131yor olabilir.");
                if (err == 2 || err == 3 || err == 21) throw new IOException("Disk bulunamad\u0131 ya da haz\u0131r de\u011fil.");
                if (err == 19) throw new IOException("Disk yazmaya kar\u015f\u0131 korumal\u0131.");
                throw new IOException("Disk a\u00e7\u0131lamad\u0131 (Windows hata kodu " + err + ").");
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
            if ((pos % Sector) != 0 || (count % Sector) != 0) throw new IOException("Okuma sekt\u00f6r s\u0131n\u0131r\u0131na hizal\u0131 de\u011fil.");
            long np;
            if (!SetFilePointerEx(h, pos, out np, 0u)) throw new IOException("Konuma gidilemedi (Windows hata kodu " + Marshal.GetLastWin32Error() + ").");
            EnsureBuf(count);
            uint rd;
            if (!ReadFile(h, buf, (uint)count, out rd, IntPtr.Zero)) throw new IOException("Okunamad\u0131 (Windows hata kodu " + Marshal.GetLastWin32Error() + ").");
            Marshal.Copy(buf, dst, off, (int)rd);
            return (int)rd;
        }

        public override void Write(long pos, byte[] src, int off, int count)
        {
            if (!Writable) throw new IOException("Ayg\u0131t salt okunur a\u00e7\u0131ld\u0131.");
            if ((pos % Sector) != 0 || (count % Sector) != 0) throw new IOException("Yazma sekt\u00f6r s\u0131n\u0131r\u0131na hizal\u0131 de\u011fil.");
            long np;
            if (!SetFilePointerEx(h, pos, out np, 0u)) throw new IOException("Konuma gidilemedi (Windows hata kodu " + Marshal.GetLastWin32Error() + ").");
            EnsureBuf(count);
            Marshal.Copy(src, off, buf, count);
            uint wr;
            if (!WriteFile(h, buf, (uint)count, out wr, IntPtr.Zero))
            {
                int err = Marshal.GetLastWin32Error();
                if (err == 5) throw new UnauthorizedAccessException("Bu alana yaz\u0131lam\u0131yor: b\u00f6l\u00fcm Windows taraf\u0131ndan kullan\u0131l\u0131yor ya da disk korumal\u0131.");
                throw new IOException("Yaz\u0131lamad\u0131 (Windows hata kodu " + err + ").");
            }
            if ((int)wr != count) throw new IOException("Eksik yaz\u0131ld\u0131.");
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
                if (write) throw new IOException("Birimlere do\u011frudan yaz\u0131lmaz.");
                WipeWinDev vd = new WipeWinDev("\\\\.\\" + s.Substring(0, 1).ToUpperInvariant() + ":", false);
                return new WipeTarget(vd, true, false, s.Substring(0, 1).ToUpperInvariant() + ":");
            }
            if (s.StartsWith("\\\\.\\", StringComparison.Ordinal) || s.StartsWith("\\\\?\\", StringComparison.Ordinal)) throw new IOException("Bu ayg\u0131t yolu desteklenmiyor.");
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
            if (!Writable) throw new IOException("Hedef salt okunur a\u00e7\u0131ld\u0131.");
            if (IsDevice && ((pos % dev.Sector) != 0 || (count % dev.Sector) != 0)) throw new IOException("Yazma konumu sekt\u00f6r s\u0131n\u0131r\u0131na hizal\u0131 de\u011fil.");
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
            WipeExtent whole = new WipeExtent(0, len, "t\u00fcm disk");
            byte[] b0 = new byte[4096];
            int n = t.ReadAt(0, b0, 0, 4096);
            if (n < 512) { note = "Diskin ba\u015f\u0131 okunamad\u0131."; return new WipeExtent[] { whole }; }
            if (IsZero(b0, 0, Math.Min(n, 4096)))
            {
                style = "BOS";
                note = "B\u00f6l\u00fcm tablosu yok; disk bo\u015f g\u00f6r\u00fcn\u00fcyor.";
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
                if (hsz < 92 || hsz > 512) { style = "BILINMIYOR"; note = "GPT ba\u015fl\u0131\u011f\u0131 ge\u00e7ersiz."; return new WipeExtent[] { whole }; }
                uint crcStored = U32(hdr, 16);
                byte[] hcopy = new byte[hsz];
                Buffer.BlockCopy(hdr, 0, hcopy, 0, (int)hsz);
                hcopy[16] = 0; hcopy[17] = 0; hcopy[18] = 0; hcopy[19] = 0;
                if (Crc32(hcopy, 0, (int)hsz) != crcStored) { style = "BILINMIYOR"; note = "GPT ba\u015fl\u0131\u011f\u0131n\u0131n sa\u011flama toplam\u0131 tutmuyor."; return new WipeExtent[] { whole }; }
                long firstUsable = (long)U64(hdr, 40);
                long lastUsable = (long)U64(hdr, 48);
                long entLba = (long)U64(hdr, 72);
                long cnt = U32(hdr, 80);
                long esz = U32(hdr, 84);
                uint arrCrc = U32(hdr, 88);
                if (cnt <= 0 || cnt > 1024 || esz < 128 || esz > 1024 || entLba < 2 || firstUsable < 2 || lastUsable < firstUsable)
                { style = "BILINMIYOR"; note = "GPT b\u00f6l\u00fcm dizisi ge\u00e7ersiz."; return new WipeExtent[] { whole }; }
                long arrBytes = cnt * esz;
                byte[] arr = new byte[arrBytes];
                int got = t.ReadAt(entLba * gss, arr, 0, (int)arrBytes);
                if (got < arrBytes || Crc32(arr, 0, (int)arrBytes) != arrCrc) { style = "BILINMIYOR"; note = "GPT b\u00f6l\u00fcm dizisinin sa\u011flama toplam\u0131 tutmuyor."; return new WipeExtent[] { whole }; }
                // koruyucu MBR + başlık + dizi
                occ.Add(new WipeExtent(0, firstUsable * gss, "GPT ba\u015f\u0131"));
                long tailStart = (lastUsable + 1) * gss;
                if (tailStart < len) occ.Add(new WipeExtent(tailStart, len - tailStart, "GPT sonu"));
                for (int i = 0; i < cnt; i++)
                {
                    int o = (int)(i * esz);
                    if (IsZero(arr, o, 16)) continue;
                    long first = (long)U64(arr, o + 32);
                    long last = (long)U64(arr, o + 40);
                    if (first < firstUsable || last < first || (last + 1) * gss > len)
                    { style = "BILINMIYOR"; note = "GPT b\u00f6l\u00fcm girdisi diskin d\u0131\u015f\u0131na ta\u015f\u0131yor."; return new WipeExtent[] { whole }; }
                    occ.Add(new WipeExtent(first * gss, (last - first + 1) * gss, "b\u00f6l\u00fcm"));
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
                    if (status != 0x00 && status != 0x80) { note = "B\u00f6l\u00fcm tablosu ge\u00e7ersiz."; return new WipeExtent[] { whole }; }
                    long lba = U32(b0, o + 8);
                    long cnt = U32(b0, o + 12);
                    if (type == 0) continue;
                    if (type == 0xEE) { gptProtective = true; continue; }
                    if (lba < 1 || cnt < 1 || (lba + cnt) * (long)ss > len) { note = "B\u00f6l\u00fcm girdisi diskin d\u0131\u015f\u0131na ta\u015f\u0131yor."; return new WipeExtent[] { whole }; }
                    used++;
                    mbr.Add(new WipeExtent(lba * ss, cnt * ss, "b\u00f6l\u00fcm"));
                }
                if (gptProtective) { style = "BILINMIYOR"; note = "Koruyucu MBR var ama GPT ba\u015fl\u0131\u011f\u0131 okunamad\u0131."; return new WipeExtent[] { whole }; }
                if (used == 0) { style = "BILINMIYOR"; note = "B\u00f6l\u00fcm tablosu bo\u015f ya da tan\u0131nmad\u0131."; return new WipeExtent[] { whole }; }
                style = "MBR";
                return mbr.ToArray();
            }
            // tablosuz tek birim (süper disket) ya da tanınmayan veri
            style = "BIRIM";
            note = "Diskin ba\u015f\u0131nda b\u00f6l\u00fcm tablosu yok; tek bir dosya sistemi ya da tan\u0131nmayan veri var.";
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
            if (len <= g * 2) return new WipeExtent[] { new WipeExtent(0, len, "ba\u015f ve son") };
            return new WipeExtent[] { new WipeExtent(0, g, "ba\u015f"), new WipeExtent(len - g, g, "son") };
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
            if (e - s >= minGap && e > s) res.Add(new WipeExtent(s, e - s, "ayr\u0131lmam\u0131\u015f"));
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
            if (ext == null || ext.Length == 0) return "Silinecek aral\u0131k yok.";
            long len = t.Length;
            long prevEnd = -1;
            List<WipeExtent> sorted = new List<WipeExtent>(ext);
            sorted.Sort(delegate(WipeExtent a, WipeExtent b) { return a.Start.CompareTo(b.Start); });
            foreach (WipeExtent e in sorted)
            {
                if (e.Start < 0 || e.Length <= 0) return "Ge\u00e7ersiz aral\u0131k.";
                if (len > 0 && e.End > len) return "Aral\u0131k diskin d\u0131\u015f\u0131na ta\u015f\u0131yor.";
                if (e.Start < prevEnd) return "Aral\u0131klar \u00e7ak\u0131\u015f\u0131yor.";
                prevEnd = e.End;
                if (t.IsDevice)
                {
                    if ((e.Start % t.SectorSize) != 0) return "Aral\u0131k sekt\u00f6r s\u0131n\u0131r\u0131na hizal\u0131 de\u011fil.";
                    if ((e.Length % t.SectorSize) != 0) return "Aral\u0131k uzunlu\u011fu sekt\u00f6r boyutunun kat\u0131 de\u011fil.";
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
            if (modes == null || modes.Length == 0) { r.Error = "Ge\u00e7i\u015f belirtilmedi."; return r; }
            if (!t.Writable) { r.Error = "Hedef yazmaya a\u00e7\u0131k de\u011fil."; return r; }
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
                                        if (r.WriteErrors >= MaxWriteErrors) r.Error = "\u00c7ok say\u0131da yazma hatas\u0131 oldu (" + ex2.Message + "). Disk bozuk olabilir.";
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
                                if (!prog("Yaz\u0131l\u0131yor", r.Written, r.Planned)) { r.Canceled = true; break; }
                            }
                        }
                        if (r.Canceled || r.Error.Length > 0) break;
                    }
                    try { t.Flush(); } catch (IOException) { }
                }
            }
            if (prog != null && !r.Canceled && r.Error.Length == 0) prog("Yaz\u0131l\u0131yor", r.Written, r.Planned);
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
                    if (!prog("Do\u011frulan\u0131yor", r.Verified, planned)) { r.Canceled = true; return false; }
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
                if (prog != null && !r.Canceled) prog("Do\u011frulan\u0131yor", r.Verified, planned);
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
            if (prog != null && !r.Canceled) prog("Do\u011frulan\u0131yor", r.Verified, planned);
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
            if (ext == null || ext.Length == 0) { r.Error = "S\u0131nanacak aral\u0131k yok."; return r; }
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
                    if (e.Start < 0 || e.Length <= 0 || (len > 0 && e.End > len)) { r.Error = "S\u0131nama aral\u0131\u011f\u0131 ge\u00e7ersiz."; return r; }
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
'@
    try {
        if ($PSVersionTable.PSEdition -ne 'Core') {
            Add-Type -TypeDefinition $src -Language CSharp -ReferencedAssemblies @('System.dll', 'System.Core.dll') -IgnoreWarnings -ErrorAction Stop
        } else {
            Add-Type -TypeDefinition $src -Language CSharp -IgnoreWarnings -ErrorAction Stop
        }
    } catch {
        # başka bir iş aynı anda derlemiş olabilir
        if ($null -ne ('Mm.WipeEngine' -as [type])) { return '' }
        $m = [string]$_.Exception.Message
        try { if ($null -ne $_.Exception.InnerException) { $m += ' ' + [string]$_.Exception.InnerException.Message } } catch { }
        return ('Silme motoru derlenemedi: ' + $m)
    }
    return ''
}

# .NET yöntem çağrısı hatalarında asıl iletiyi verir
function global:Get-WipeErrorText($Err) {
    $ex = $Err.Exception
    $depth = 0
    while ($null -ne $ex.InnerException -and $depth -lt 5) { $ex = $ex.InnerException; $depth++ }
    return [string]$ex.Message
}

function global:Test-WipeAdmin {
    try { return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) } catch { return $false }
}

# Engine nesnesi için yardımcılar: @{ Start; Length; StreamPos } listesinden Mm.WipeExtent[] üretir
function global:ConvertTo-WipeExtents($List) {
    $out = New-Object 'System.Collections.Generic.List[Mm.WipeExtent]'
    foreach ($e in @($List)) {
        if ($null -eq $e) { continue }
        $x = New-Object Mm.WipeExtent
        $x.Start = [long][double]$e.Start
        $x.Length = [long][double]$e.Length
        if ($null -ne $e.Tag) { $x.Tag = [string]$e.Tag }
        if ($null -ne $e.StreamPos) { $x.StreamPos = [long][double]$e.StreamPos }
        $out.Add($x)
    }
    return , $out.ToArray()
}

# ilerleme bildirimi: motorun geri çağrısı bu oturum durumunu okur
function global:New-WipeCallback([string]$Label, [double]$Total, [double]$Base) {
    $global:MmWipeProg = @{ Sw = [System.Diagnostics.Stopwatch]::StartNew(); Total = $Total; Base = $Base; Label = $Label }
    return [Mm.WipeProgress]{
        param([string]$stage, [long]$done, [long]$total)
        $g = $global:MmWipeProg
        $all = [double]$g.Total
        $cur = [double]$g.Base + [double]$done
        $pct = 0
        if ($all -gt 0) { $pct = [int][math]::Min(1000, [math]::Floor($cur * 1000.0 / $all)) }
        Set-JobProgress $pct 1000 (Get-WipeProgressLabel ([string]$g.Label) $stage $cur $all ([double]$g.Sw.Elapsed.TotalSeconds))
        return (-not (Test-JobCancel))
    }
}

# ---------------- boş alan temizleme ----------------
# Silinmiş dosyaların diskte kalan kalıntılarını (kurtarma programlarının bulabildiği alanı) AES-256-CTR akışıyla üzerine yazar.
# Var olan hiçbir dosyaya dokunulmaz: sürücüde gizli bir klasör açılır, boş alan bu klasörde geçici dosyalarla doldurulur ve
# iş bitince (iptal ya da hata olsa da) klasör silinir. Windows’un ve açık programların çalışabilmesi için sürücüde pay bırakılır.
# Kanarya doğrulaması: iş başlarken bilinen içerikli küçük dosyalar yazılıp silinir (silinmiş dosya benzetimi), birimdeki fiziksel konumları
# kaydedilir; temizlikten sonra aynı konumlar doğrudan birimden okunup eski içeriğin kalıp kalmadığına bakılır.
# Sınırlar: SSD’lerde denetleyici veriyi başka hücrelere taşıdığı için tam güvence vermez; çok küçük dosyalar (MFT içinde saklananlar)
# ve dosya adları bu yöntemle silinmez. Bırakılan pay temizlenmez.

# Birim bilgisi: @{ Free; Total } (bayt). Ayrı bir işlev olması testlerde sahte birim kullanılmasını sağlar.
function global:Get-WipeVolume([string]$Root) {
    $r = @{ Free = [double]0; Total = [double]0 }
    try {
        $full = [System.IO.Path]::GetFullPath($Root)
        $di = New-Object System.IO.DriveInfo -ArgumentList ([System.IO.Path]::GetPathRoot($full))
        $r.Free = [double]$di.AvailableFreeSpace
        $r.Total = [double]$di.TotalSize
    } catch { }
    return $r
}

# Bırakılacak pay (Get-WipeReserve) çekirdekte; onay penceresi de aynı hesabı kullanır.

# Önceki bir çalışmadan (uygulama kapanmış, elektrik kesilmiş) kalan geçici klasörleri kaldırır
function global:Remove-WipeLeftovers([string]$Root) {
    $n = 0
    try {
        foreach ($d in @(Get-ChildItem -LiteralPath $Root -Directory -Force -ErrorAction Stop | Where-Object { $_.Name -like '.mm-bosalan-*' })) {
            try { [System.IO.Directory]::Delete($d.FullName, $true); $n++ } catch { }
        }
    } catch { }
    return $n
}

# Dosyanın birim içindeki konumları. Dönüş: @{ Cluster; Extents = @(@{ Start; Length }) }; Windows dışında ya da okunamazsa Extents boş.
function global:Get-WipeFileExtents([string]$Path) {
    $r = @{ Cluster = [long]0; Extents = @() }
    try {
        $c = [long]0
        $arr = [Mm.WipeFs]::QueryExtents($Path, [ref]$c)
        $r.Cluster = $c
        $list = New-Object System.Collections.ArrayList
        for ($i = 0; $i + 1 -lt $arr.Length; $i += 2) { [void]$list.Add(@{ Start = [long]$arr[$i]; Length = [long]$arr[$i + 1] }) }
        $r.Extents = $list.ToArray()
    } catch { }
    return $r
}

# Birimi (X:) yalnızca okumak için açar. Ayrı bir işlev olması testlerde sahte birim kullanılmasını sağlar.
function global:Open-WipeRead([string]$Spec) {
    return [Mm.WipeTarget]::Open($Spec, $false)
}

# Silinmiş dosya benzetimi: bilinen içerikli küçük dosyalar yazılır, birimdeki konumları kaydedilir, dosyalar silinir.
# Dönüş: @{ Key; Items = @(@{ Pass; Extents = @(@{ Start; Length; StreamPos }) }); Units; Files }
function global:New-WipeCanary([string]$Dir, [int]$Files = 6, [int]$FileBytes = 262144) {
    $c = @{ Key = $null; Items = @(); Units = [long]0; Files = 0 }
    $key = [Mm.WipeEngine]::NewKey()
    $c.Key = $key
    $items = New-Object System.Collections.ArrayList
    $buf = New-Object byte[] 65536
    for ($i = 1; $i -le $Files; $i++) {
        $path = Join-Path $Dir ('kanarya-' + $i.ToString('D2') + '.tmp')
        $ws = [Mm.WipeStream]::new(0, $key, $i)
        $fs = $null
        try {
            $fs = New-Object System.IO.FileStream -ArgumentList $path, ([System.IO.FileMode]::CreateNew), ([System.IO.FileAccess]::Write), ([System.IO.FileShare]::Read), 65536, ([System.IO.FileOptions]::WriteThrough)
            $pos = [long]0
            while ($pos -lt $FileBytes) {
                $n = [int][math]::Min(65536, $FileBytes - $pos)
                $ws.Fill($buf, 0, $n, $pos)
                $fs.Write($buf, 0, $n)
                $pos += $n
            }
            $fs.Flush($true)
        } catch {
            $path = ''
        } finally {
            if ($null -ne $fs) { $fs.Dispose() }
            $ws.Dispose()
        }
        if ($path -eq '') { continue }
        $c.Files++
        $q = Get-WipeFileExtents $path
        [System.IO.File]::Delete($path)
        $ext = @($q.Extents)
        if ($ext.Count -eq 0) { continue }
        # sıkıştırılmış ya da seyrek dosyada konumlar içerikle eşleşmez: toplam uzunluk dosya boyutunu karşılamalı
        $sum = [long]0
        foreach ($e in $ext) { $sum += [long]$e.Length }
        if ($sum -lt $FileBytes -or $sum -gt ($FileBytes + 2 * [long]$q.Cluster + 65536)) { continue }
        $fpos = [long]0
        $list = New-Object System.Collections.ArrayList
        foreach ($e in $ext) {
            [void]$list.Add(@{ Start = [long]$e.Start; Length = [long]$e.Length; StreamPos = $fpos })
            $fpos += [long]$e.Length
        }
        [void]$items.Add(@{ Pass = $i; Extents = $list.ToArray() })
        $c.Units += [long][math]::Floor($sum / 4096)
    }
    $c.Items = $items.ToArray()
    return $c
}

# Kanarya konumlarını doğrudan birimden okur. Dönüş: @{ Checked; Units; Same; Zeroed; Changed; Error }
function global:Test-WipeCanary($Canary, [string]$Spec) {
    $res = @{ Checked = $false; Units = [long]0; Same = [long]0; Zeroed = [long]0; Changed = [long]0; Error = '' }
    if ($null -eq $Canary -or @($Canary.Items).Count -eq 0) { return $res }
    $t = $null
    try {
        $t = Open-WipeRead $Spec
        foreach ($it in @($Canary.Items)) {
            $arr = ConvertTo-WipeExtents @($it.Extents)
            $r = [Mm.WipeEngine]::Probe($t, $arr, 0, $Canary.Key, [int]$it.Pass, $null)
            if ($r.Error -ne '') { $res.Error = [string]$r.Error; continue }
            $res.Units += [long]$r.Units
            $res.Same += [long]$r.Same
            $res.Zeroed += [long]$r.Zeroed
            $res.Changed += [long]$r.Changed
        }
        $res.Checked = ($res.Units -gt 0)
    } catch {
        $res.Error = Get-WipeErrorText $_
    } finally {
        if ($null -ne $t) { try { $t.Dispose() } catch { } }
    }
    return $res
}

# Kanarya sonucu: @{ Level (ok | warn | info | none); Text }
function global:Get-WipeCanaryVerdict($Pre, $Post) {
    if ($null -eq $Post -or $Post.Checked -ne $true) {
        return @{ Level = 'none'; Text = 'Doğrulama yapılamadı: bu birimde dosya konumları okunamadı.' }
    }
    $total = [long]$Post.Units
    if ($null -eq $Pre -or $Pre.Checked -ne $true -or [long]$Pre.Same -le 0) {
        if ([long]$Post.Same -gt 0) {
            return @{ Level = 'warn'; Text = ([string]$Post.Same + ' / ' + [string]$total + ' test birimi hâlâ okunabiliyor; bırakılan payda kalmış ya da yazılamamış olabilir.') }
        }
        return @{ Level = 'info'; Text = 'Silinen test verisi, temizlemeden önce de okunamıyordu (SSD üzerindeki TRIM işlemi olabilir). Boş alan yine de yazıldı; sınama bilgi vermedi.' }
    }
    if ([long]$Post.Same -eq 0) {
        return @{ Level = 'ok'; Text = ('Doğrulandı: silinmiş test dosyalarının ' + [string]$Pre.Same + ' / ' + [string]$Pre.Units + ' birimi temizlemeden önce okunabiliyordu, sonra hiçbiri okunamıyor.') }
    }
    return @{ Level = 'warn'; Text = ('Silinmiş test dosyalarının ' + [string]$Post.Same + ' / ' + [string]$total + ' birimi temizlemeden sonra da okunabiliyor; bırakılan payda kalmış ya da yazılamamış olabilir.') }
}

# TRIM durumu: on | off | unknown (fsutil: DisableDeleteNotify = 0 ise TRIM açıktır)
function global:Get-WipeTrimState {
    try {
        $o = @(& fsutil.exe behavior query DisableDeleteNotify 2>&1 | ForEach-Object { [string]$_ })
        foreach ($l in $o) {
            if ($l -match 'NTFS\s+DisableDeleteNotify\s*=\s*(\d)') { if ($Matches[1] -eq '0') { return 'on' } else { return 'off' } }
        }
        foreach ($l in $o) {
            if ($l -match 'DisableDeleteNotify\s*=\s*(\d)') { if ($Matches[1] -eq '0') { return 'on' } else { return 'off' } }
        }
    } catch { }
    return 'unknown'
}

# Birime TRIM gönderir (SSD ve ince sağlanan birimler). Dönüş: @{ Ok; Error; Note }
function global:Invoke-WipeTrim([string]$Letter) {
    $r = @{ Ok = $false; Error = ''; Note = '' }
    $l = ([string]$Letter).Trim().Substring(0, 1).ToUpperInvariant()
    try {
        if ((Get-WipeTrimState) -eq 'off') { $r.Note = 'Windows silme bildirimleri (TRIM) kapalı görünüyor; yine de yeniden TRIM istendi.' }
        Optimize-Volume -DriveLetter $l -ReTrim -ErrorAction Stop | Out-Null
        $r.Ok = $true
    } catch {
        $r.Error = Get-WipeErrorText $_
    }
    return $r
}

# P: Drive ("D:") ya da Root (geçici dosyaların yazılacağı klasör), Reserve (bırakılacak pay, bayt; verilmezse sürücü boyutuna göre),
#    FileMax (tek geçici dosyanın en büyük boyutu), StallBytes (boş alan azalmıyorsa kaç bayttan sonra vazgeçileceği),
#    Method (random | zero | dod3 | random3), Canary ($false: kanarya doğrulaması yapma), Trim ($true: bitince TRIM gönder)
#    VolSpec (yalnızca sınama: kanarya okumasının yapılacağı birim belirteci)
# Dönüş: @{ Ok; Kind; Drive; Written; Reserve; Canceled; Error; Method; Passes; Seconds; Canary; Verdict; Trim }
function global:Job_WipeFree($P) {
    $res = @{ Ok = $false; Kind = 'Free'; Drive = ''; Written = [double]0; Reserve = [double]0; Canceled = $false; Error = ''; Method = 'random'; Passes = 1; Seconds = [double]0
        Canary = $null; Verdict = $null; Trim = $null }
    $sw0 = [System.Diagnostics.Stopwatch]::StartNew()
    $root = ([string]$P.Root).Trim()
    if ($root -eq '') {
        $d = ([string]$P.Drive).Trim()
        if ($d -cnotmatch '^[A-Za-z]:?[\\/]?$') { $res.Error = 'Geçerli bir sürücü seçilmedi.'; Write-WhLog $res.Error 'ERR'; return $res }
        $root = $d.Substring(0, 1).ToUpperInvariant() + ':\'
    }
    $res.Drive = $root
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { $res.Error = ($root + ' bulunamadı ya da hazır değil.'); Write-WhLog $res.Error 'ERR'; return $res }
    $isOs = $false
    try { if ($root.Length -ge 1 -and [string]$env:SystemDrive -ne '' -and $root.Substring(0, 1).ToUpperInvariant() -eq ([string]$env:SystemDrive).Substring(0, 1).ToUpperInvariant()) { $isOs = $true } } catch { }
    $vol = Get-WipeVolume $root
    if ($vol.Total -le 0) { $res.Error = 'Sürücü bilgisi okunamadı.'; Write-WhLog $res.Error 'ERR'; return $res }
    $reserve = [double]0
    if ($null -ne $P.Reserve) { $reserve = [double]$P.Reserve }
    if ($reserve -le 0) { $reserve = Get-WipeReserve $vol.Total $isOs }
    $res.Reserve = $reserve
    $todo = $vol.Free - $reserve
    if ($todo -lt 1048576) { $res.Error = 'Sürücüde temizlenecek yeterli boş alan yok.'; Write-WhLog $res.Error 'WARN'; return $res }
    $fileMax = [long]1073741824
    if ($null -ne $P.FileMax -and [long]$P.FileMax -gt 0) { $fileMax = [long]$P.FileMax }
    $stallBytes = [double]268435456
    if ($null -ne $P.StallBytes -and [double]$P.StallBytes -gt 0) { $stallBytes = [double]$P.StallBytes }
    $method = Get-WipeMethodKey ([string]$P.Method)
    $modes = Get-WipeModes $method
    $res.Method = $method
    $res.Passes = @($modes).Count
    $ie = Initialize-MmWipe
    if ($ie -ne '') { $res.Error = $ie; Write-WhLog $res.Error 'ERR'; return $res }

    Write-WhLog ('--- BOŞ ALAN TEMİZLEME: ' + $root + ' (' + (Format-Size $todo) + ' üzerine yazılacak, ' + (Format-Size $reserve) + ' pay bırakılacak, ' + (Get-WipeMethodName $method) + ') ---') 'STEP'
    $left = Remove-WipeLeftovers $root
    if ($left -gt 0) { Write-WhLog ([string]$left + ' eski geçici klasör kaldırıldı.') 'INFO' }
    $vol = Get-WipeVolume $root
    $todo = $vol.Free - $reserve
    $dir = Join-Path $root ('.mm-bosalan-' + [System.Guid]::NewGuid().ToString('N').Substring(0, 12))
    $chunk = 4194304
    $buf = New-Object byte[] $chunk
    $key = [Mm.WipeEngine]::NewKey()
    $volSpec = ''
    if ($root -cmatch '^[A-Za-z]:') { $volSpec = $root.Substring(0, 1).ToUpperInvariant() + ':' }
    # yalnızca sınama: kanarya okumasının yapılacağı birim belirteci (yalnızca okunur açılır)
    if ($null -ne $P.VolSpec -and ([string]$P.VolSpec).Trim() -ne '') { $volSpec = ([string]$P.VolSpec).Trim() }
    $written = [double]0
    $totalWork = $todo * $res.Passes
    $fs = $null
    $pre = $null
    $canary = $null
    try {
        [void][System.IO.Directory]::CreateDirectory($dir)
        try { (New-Object System.IO.DirectoryInfo -ArgumentList $dir).Attributes = [System.IO.FileAttributes]::Hidden } catch { }
        # kanarya: silinmiş dosya benzetimi (yalnızca birim harfi bilinen, 16 MB'tan fazla boşu olan birimlerde)
        if ($P.Canary -ne $false -and $volSpec -ne '' -and $todo -gt 16777216) {
            try {
                $canary = New-WipeCanary $dir
                if (@($canary.Items).Count -gt 0) {
                    $pre = Test-WipeCanary $canary $volSpec
                    Write-WhLog ('Kanarya: ' + [string]@($canary.Items).Count + ' test dosyası yazılıp silindi, birimdeki konumları kaydedildi.') 'INFO'
                } else { Write-WhLog 'Kanarya: dosya konumları okunamadı; doğrulama yapılamayacak.' 'INFO'; $canary = $null }
            } catch { Write-WhLog ('Kanarya hazırlanamadı: ' + (Get-WipeErrorText $_)) 'WARN'; $canary = $null }
        }
        for ($pass = 0; $pass -lt $res.Passes -and -not $res.Canceled -and $res.Error -eq ''; $pass++) {
            if ($pass -gt 0) {
                # önceki geçişin dosyalarını sil; klasörü yeniden aç
                if ($null -ne $fs) { try { $fs.Dispose() } catch { }; $fs = $null }
                [System.IO.Directory]::Delete($dir, $true)
                [void][System.IO.Directory]::CreateDirectory($dir)
                try { (New-Object System.IO.DirectoryInfo -ArgumentList $dir).Attributes = [System.IO.FileAttributes]::Hidden } catch { }
            }
            $v1 = Get-WipeVolume $root
            $avail = $v1.Free - $reserve
            $startFree = $v1.Free
            $passWritten = [double]0
            $ws = [Mm.WipeStream]::new([int]$modes[$pass], $key, $pass)
            $streamPos = [long]0
            $fileNo = 0
            $curLeft = [long]0
            $tick = 0
            try {
                while ($avail -gt 0) {
                    if (Test-JobCancel) { $res.Canceled = $true; Write-WhLog 'İptal edildi.' 'WARN'; break }
                    if ($null -eq $fs -or $curLeft -le 0) {
                        if ($null -ne $fs) { $fs.Flush($true); $fs.Dispose(); $fs = $null }
                        $fileNo++
                        $path = Join-Path $dir ('bos-' + $fileNo.ToString('D5') + '.tmp')
                        $fs = New-Object System.IO.FileStream -ArgumentList $path, ([System.IO.FileMode]::CreateNew), ([System.IO.FileAccess]::Write), ([System.IO.FileShare]::None), 65536, ([System.IO.FileOptions]::WriteThrough)
                        $curLeft = $fileMax
                    }
                    $n = [long][math]::Min([math]::Min([double]$chunk, $avail), [double]$curLeft)
                    if ($n -le 0) { break }
                    $ws.Fill($buf, 0, [int]$n, $streamPos)
                    try { $fs.Write($buf, 0, [int]$n) }
                    catch [System.IO.IOException] { Write-WhLog ('Yazma durdu (disk dolu ya da kota): ' + $_.Exception.Message) 'INFO'; break }
                    $streamPos += $n
                    $written += [double]$n
                    $passWritten += [double]$n
                    $curLeft -= $n
                    $avail -= [double]$n
                    $tick++
                    if (($tick % 16) -eq 0 -or $avail -lt 67108864) {
                        # gerçek boş alanla eşitle; beklendiği gibi azalmıyorsa (sıkıştırma, seyrek birim) vazgeç
                        $fs.Flush($true)
                        $v2 = Get-WipeVolume $root
                        $avail = $v2.Free - $reserve
                        $used = $startFree - $v2.Free
                        if ($passWritten -ge $stallBytes -and $used -lt ($passWritten * 0.5)) {
                            $res.Error = 'Boş alan beklendiği gibi azalmıyor (sıkıştırılmış ya da seyrek bir birim olabilir); işlem durduruldu.'
                            Write-WhLog $res.Error 'WARN'
                            break
                        }
                    }
                    if (($tick % 8) -eq 0) {
                        $pct = 1000
                        if ($totalWork -gt 0) { $pct = [int][math]::Min(1000, [math]::Floor($written * 1000.0 / $totalWork)) }
                        $lbl = 'Boş alan temizleniyor'
                        if ($res.Passes -gt 1) { $lbl += ' (' + [string]($pass + 1) + '/' + [string]$res.Passes + '. geçiş)' }
                        Set-JobProgress $pct 1000 (Get-WipeProgressLabel $lbl '' $written $totalWork ([double]$sw0.Elapsed.TotalSeconds))
                    }
                }
                if ($null -ne $fs) { $fs.Flush($true); $fs.Dispose(); $fs = $null }
            } finally {
                $ws.Dispose()
            }
            if ($res.Passes -gt 1 -and -not $res.Canceled -and $res.Error -eq '') { Write-WhLog ([string]($pass + 1) + '. geçiş bitti: ' + (Format-Size $passWritten)) 'INFO' }
        }
        if ($null -ne $fs) { $fs.Flush($true); $fs.Dispose(); $fs = $null }
        # kanarya: geçici dosyalar silinmeden önce aynı konumları yeniden oku
        if ($null -ne $canary -and -not $res.Canceled -and $res.Error -eq '') {
            $post = Test-WipeCanary $canary $volSpec
            $res.Canary = @{ Pre = $pre; Post = $post; Files = @($canary.Items).Count }
            $res.Verdict = Get-WipeCanaryVerdict $pre $post
            $lvl = 'INFO'
            if ($res.Verdict.Level -eq 'warn') { $lvl = 'WARN' }
            Write-WhLog ('Doğrulama: ' + [string]$res.Verdict.Text) $lvl
        }
    } catch {
        $res.Error = $_.Exception.Message
        Write-WhLog ('Boş alan temizlenemedi: ' + $res.Error) 'ERR'
    } finally {
        if ($null -ne $fs) { try { $fs.Dispose() } catch { } }
        $gone = $false
        for ($t = 0; $t -lt 5 -and -not $gone; $t++) {
            try { if (Test-Path -LiteralPath $dir) { [System.IO.Directory]::Delete($dir, $true) }; $gone = $true }
            catch { Start-Sleep -Milliseconds 400 }
        }
        if (-not $gone) { Write-WhLog ('Geçici klasör silinemedi, elle silin: ' + $dir) 'WARN' }
    }
    $res.Written = $written
    $res.Ok = ($res.Error -eq '' -and -not $res.Canceled -and $written -gt 0)
    if ($res.Ok -and $P.Trim -eq $true -and $volSpec -ne '') {
        $res.Trim = Invoke-WipeTrim $volSpec
        if ($res.Trim.Ok) { Write-WhLog 'TRIM gönderildi: silinen alanlar sürücüye bildirildi.' 'INFO' } else { Write-WhLog ('TRIM gönderilemedi: ' + [string]$res.Trim.Error) 'WARN' }
    }
    $res.Seconds = [double]$sw0.Elapsed.TotalSeconds
    $tail = ''
    if ($res.Canceled) { $tail = ' (iptal edildi)' }
    Write-WhLog ('Boş alan temizleme bitti: ' + (Format-Size $written) + ' üzerine yazıldı' + $tail) 'INFO'
    return $res
}

# P: Drive ("D:"). Silinmiş dosyaların SSD’ye bildirilmesini sağlar (TRIM). Dönüş: @{ Ok; Kind; Drive; Error; Note; Seconds }
function global:Job_TrimVolume($P) {
    $res = @{ Ok = $false; Kind = 'Trim'; Drive = ''; Error = ''; Note = ''; Seconds = [double]0 }
    $d = ([string]$P.Drive).Trim()
    if ($d -cnotmatch '^[A-Za-z]:?[\\/]?$') { $res.Error = 'Geçerli bir sürücü seçilmedi.'; Write-WhLog $res.Error 'ERR'; return $res }
    $res.Drive = $d.Substring(0, 1).ToUpperInvariant() + ':'
    if (-not (Test-Path -LiteralPath ($res.Drive + '\') -PathType Container)) { $res.Error = ($res.Drive + ' bulunamadı ya da hazır değil.'); Write-WhLog $res.Error 'ERR'; return $res }
    Write-WhLog ('--- TRIM: ' + $res.Drive + ' ---') 'STEP'
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Set-JobProgress 0 0 ($res.Drive + ' için TRIM gönderiliyor')
    $t = Invoke-WipeTrim $res.Drive
    $res.Ok = ($t.Ok -eq $true)
    $res.Error = [string]$t.Error
    $res.Note = [string]$t.Note
    $res.Seconds = [double]$sw.Elapsed.TotalSeconds
    if ($res.Ok) { Write-WhLog 'TRIM gönderildi.' 'INFO' } else { Write-WhLog ('TRIM gönderilemedi: ' + $res.Error) 'ERR' }
    return $res
}

# ---------------- ham disk silme ----------------
# Kapsamlar: Unallocated (bölümlerin dışında kalan boşluklar), Partition (tek bölüm), Disk (tüm disk).
# Bölüm ve disk kapsamında önce Windows’un kendi komutları çalışır (Remove-Partition, Clear-Disk), ardından alan doğrudan
# aygıttan üzerine yazılır. Disk silmede son geçiş sıfır değilse diskin başı ve sonu (bölüm tablosu yapıları) sıfırlanır; böylece disk
# Windows’a "boş" görünür ve rastgele veri bir bölüm tablosu gibi yorumlanmaz.

function global:New-WipeRawResult([string]$Scope) {
    return @{ Ok = $false; Kind = 'Raw'; Scope = $Scope; Disk = -1; Part = 0; Name = ''; Size = [double]0; Target = ''; Method = ''; Passes = 0; Verify = ''; After = ''
        Planned = [double]0; Written = [double]0; Verified = [double]0; BadUnits = [double]0; WriteErrors = 0; Seconds = [double]0; Canceled = $false; Error = ''
        Started = $false; Nothing = $false; Notes = @(); Ranges = 0; Style = ''; AfterDone = ''; Letter = ''; VerifyKind = '' }
}

# Hedef belirtimi. Gerçek disk yalnızca tamsayıdan üretilir; Image yalnızca sınama içindir ve var olan bir dosya olmalıdır.
function global:Resolve-WipeTarget($P) {
    $res = @{ Ok = $false; Kind = ''; Spec = ''; Number = -1; Error = '' }
    $img = ([string]$P.Image).Trim()
    $num = -1
    if ($null -ne $P.Disk) { try { $num = [int]$P.Disk } catch { $num = -1 } }
    if ($img -ne '') {
        $full = ''
        try { $full = [System.IO.Path]::GetFullPath($img) } catch { $full = '' }
        if ($full -eq '' -or -not (Test-Path -LiteralPath $full -PathType Leaf)) { $res.Error = 'Disk imajı bulunamadı.'; return $res }
        $res.Ok = $true; $res.Kind = 'Image'; $res.Spec = $full; $res.Number = $num
        return $res
    }
    if ($num -lt 0 -or $num -gt 9999) { $res.Error = 'Geçerli bir disk seçilmedi.'; return $res }
    $res.Ok = $true; $res.Kind = 'Disk'; $res.Spec = ('PhysicalDrive' + [string]$num); $res.Number = $num
    return $res
}

# Windows’un bildirdiği bölümler (ayrılmamış alan hesabında "dolu" sayılır)
function global:Get-WipeWinExtents($Live) {
    $list = New-Object System.Collections.ArrayList
    foreach ($pt in @($Live.Parts)) {
        if ($null -eq $pt) { continue }
        $l = [double]$pt.Size
        if ($l -gt 0) { [void]$list.Add(@{ Start = [double]$pt.Offset; Length = $l; Tag = 'Windows bölümü' }) }
    }
    return , $list.ToArray()
}

# Windows depolama komutları (ayrı işlevler: sınamada sahtelerle değiştirilir). Hata olursa istisna fırlatırlar.
function global:Invoke-WipeRemovePartition([int]$Disk, [int]$Part) {
    Remove-Partition -DiskNumber $Disk -PartitionNumber $Part -Confirm:$false -ErrorAction Stop
}

function global:Invoke-WipeClearDisk([int]$Disk) {
    Clear-Disk -Number $Disk -RemoveData -RemoveOEM -Confirm:$false -ErrorAction Stop
}

function global:Update-WipeStorage {
    try { Update-HostStorageCache -ErrorAction Stop } catch { }
}

# Silinen alana yeni bölüm açar ve biçimler. Whole: tüm disk (diski başlatır); aksi hâlde Offset/Size bölgesine bölüm. Dönüş: sürücü harfi ('' olabilir)
function global:Invoke-WipeNewVolume([int]$Disk, [bool]$Whole, [double]$Offset, [double]$Size, [string]$Fs, [string]$Style) {
    if ($Whole) {
        Initialize-Disk -Number $Disk -PartitionStyle $Style -ErrorAction Stop
        $pt = New-Partition -DiskNumber $Disk -UseMaximumSize -AssignDriveLetter -ErrorAction Stop
    } else {
        $pt = New-Partition -DiskNumber $Disk -Offset ([uint64]$Offset) -Size ([uint64]$Size) -AssignDriveLetter -ErrorAction Stop
    }
    $letter = ''
    if ($pt.DriveLetter) { $letter = [string]$pt.DriveLetter }
    if ($letter -eq '') { return '' }
    $fsName = 'NTFS'
    if ($Fs -eq 'exfat') { $fsName = 'exFAT' } elseif ($Fs -eq 'fat32') { $fsName = 'FAT32' }
    Format-Volume -DriveLetter $letter -FileSystem $fsName -Confirm:$false -ErrorAction Stop | Out-Null
    return ($letter.ToUpperInvariant() + ':')
}

# Hedefi doğrulayıp yazma planını çıkarır (hiçbir şey değiştirmez). Dönüş: @{ Ok; Error; Live; Part; Extents (@{Start;Length;Tag}); Style; Note; Length; Sector }
function global:Get-WipeRawPlan($P, $Tg, [string]$Scope) {
    $pl = @{ Ok = $false; Error = ''; Live = $null; Part = $null; Extents = @(); Style = ''; Note = ''; Length = [double]0; Sector = 512 }
    $live = Get-WipeDiskLive $Tg.Number
    $why = Test-WipeDiskAllowed $live $Scope
    if ($why -ne '') { $pl.Error = $why; return $pl }
    $why = Test-WipeIdentity $live $P.Expect
    if ($why -ne '') { $pl.Error = $why; return $pl }
    $pl.Live = $live
    $pl.Sector = [int]$live.Sector
    if ($Scope -eq 'Partition') {
        $part = $null
        foreach ($pt in @($live.Parts)) { if ([int]$pt.Number -eq [int]$P.Part) { $part = $pt } }
        $why = Test-WipePartAllowed $live $part
        if ($why -ne '') { $pl.Error = $why; return $pl }
        $ex = $P.Expect
        if ($null -ne $ex -and $null -ne $ex.PartOffset -and ([double]$part.Offset -ne [double]$ex.PartOffset -or [double]$part.Size -ne [double]$ex.PartSize)) {
            $pl.Error = 'Bölüm, onay verdiğiniz andan sonra değişmiş görünüyor. Güvenliğiniz için işlem başlatılmadı; diskleri yenileyip yeniden seçin.'
            return $pl
        }
        $pl.Part = $part
    }
    $ro = $null
    try {
        $ro = [Mm.WipeTarget]::Open([string]$Tg.Spec, $false)
        $len = [double]$ro.Length
        $pl.Length = $len
        if ($Tg.Kind -eq 'Disk' -and [math]::Abs($len - [double]$live.Size) -gt [double]$live.Sector) {
            $pl.Error = 'Aygıtın boyutu Windows tarafından bildirilenden farklı; işlem başlatılmadı.'
            return $pl
        }
        $sector = [int]$ro.SectorSize
        $pl.Sector = $sector
        if ($Scope -eq 'Disk') {
            $whole = [long]([math]::Floor($len / $sector) * $sector)
            $pl.Extents = @(@{ Start = [double]0; Length = [double]$whole; Tag = 'tüm disk' })
        } elseif ($Scope -eq 'Partition') {
            $so = [double]$pl.Part.Offset
            $sl = [double]$pl.Part.Size
            if (($so % $sector) -ne 0 -or ($sl % $sector) -ne 0 -or ($so + $sl) -gt $len) {
                $pl.Error = 'Bölümün konumu sektör sınırına uymuyor ya da diskin dışına taşıyor; işlem başlatılmadı.'
                return $pl
            }
            $pl.Extents = @(@{ Start = $so; Length = $sl; Tag = 'bölüm' })
        } else {
            $style = ''
            $note = ''
            $occ = [Mm.WipeLayout]::ReadOccupied($ro, [ref]$style, [ref]$note)
            $all = New-Object 'System.Collections.Generic.List[Mm.WipeExtent]'
            foreach ($x in $occ) { $all.Add($x) }
            $winExt = ConvertTo-WipeExtents (Get-WipeWinExtents $live)
            foreach ($x in $winExt) { $all.Add($x) }
            $guard = [long]1048576
            $gaps = [Mm.WipeLayout]::Gaps([long]$len, $all.ToArray(), $guard, $guard, [long]8388608, [long]$sector)
            $pl.Style = $style
            $pl.Note = $note
            $ex2 = New-Object System.Collections.ArrayList
            foreach ($g in $gaps) { [void]$ex2.Add(@{ Start = [double]$g.Start; Length = [double]$g.Length; Tag = 'ayrılmamış' }) }
            $pl.Extents = $ex2.ToArray()
        }
    } catch {
        $pl.Error = Get-WipeErrorText $_
        return $pl
    } finally {
        if ($null -ne $ro) { try { $ro.Dispose() } catch { } }
    }
    $pl.Ok = $true
    return $pl
}

# P: Scope (Unallocated | Partition | Disk), Disk (numara), Part (bölüm numarası; Partition için), Expect (@{ Size; Name; UniqueId; Serial; PartOffset; PartSize }),
#    Method, Verify (none | sample | full), After (none | ntfs | exfat | fat32), Image (yalnızca sınama: disk yerine imaj dosyası)
function global:Job_WipeRaw($P) {
    $scope = ([string]$P.Scope).Trim()
    $res = New-WipeRawResult $scope
    $sw0 = [System.Diagnostics.Stopwatch]::StartNew()
    if (@('Unallocated', 'Partition', 'Disk') -notcontains $scope) { $res.Error = 'Bilinmeyen silme kapsamı.'; Write-WhLog $res.Error 'ERR'; return $res }
    $method = Get-WipeMethodKey ([string]$P.Method)
    $verify = Get-WipeVerifyKey ([string]$P.Verify)
    $after = Get-WipeAfterKey ([string]$P.After)
    if ($scope -eq 'Unallocated') { $after = 'none' }
    $modes = Get-WipeModes $method
    $res.Method = $method; $res.Verify = $verify; $res.After = $after; $res.Passes = $modes.Count
    $tg = Resolve-WipeTarget $P
    if (-not $tg.Ok) { $res.Error = $tg.Error; Write-WhLog $res.Error 'ERR'; return $res }
    $res.Disk = $tg.Number; $res.Part = 0
    if ($null -ne $P.Part) { $res.Part = [int]$P.Part }
    $res.Target = $tg.Spec
    if ($tg.Kind -eq 'Disk' -and -not (Test-WipeAdmin)) { $res.Error = 'Disk silmek için Multimizer uygulamasını yönetici olarak çalıştırın.'; Write-WhLog $res.Error 'ERR'; return $res }
    $ie = Initialize-MmWipe
    if ($ie -ne '') { $res.Error = $ie; Write-WhLog $res.Error 'ERR'; return $res }

    # ---- plan: canlı disk, korumalar, kimlik, aralıklar (henüz hiçbir şey değişmedi) ----
    $pl = Get-WipeRawPlan $P $tg $scope
    if (-not $pl.Ok) { $res.Error = $pl.Error; Write-WhLog ('Silme başlatılmadı: ' + $res.Error) 'ERR'; return $res }
    $live = $pl.Live
    $res.Name = [string]$live.Name
    $res.Size = [double]$live.Size
    $res.Style = [string]$pl.Style
    $extList = @($pl.Extents)
    $res.Ranges = $extList.Count
    $sector = [int]$pl.Sector
    $len = [double]$pl.Length
    if ($extList.Count -eq 0) {
        $res.Ok = $true; $res.Nothing = $true
        $res.Notes = @('Ayrılmamış alan bulunamadı; yapılacak bir şey yok.' + $(if ([string]$pl.Note -ne '') { ' ' + [string]$pl.Note } else { '' }))
        Write-WhLog ('Disk ' + [string]$tg.Number + ': ' + $res.Notes[0]) 'INFO'
        return $res
    }
    $bytes = [double]0
    foreach ($e in $extList) { $bytes += [double]$e.Length }
    if ($after -eq 'fat32' -and $scope -ne 'Unallocated' -and $bytes -gt [double]34359738368) {
        $res.Error = 'FAT32 yalnızca 32 GB boyuta kadar biçimlenebilir; NTFS ya da exFAT seçin. Hiçbir şey silinmedi.'
        Write-WhLog $res.Error 'ERR'
        return $res
    }
    $res.Planned = $bytes * $modes.Count
    $what = 'Disk ' + [string]$tg.Number + '  ' + [string]$live.Name
    Write-WhLog ('--- KALICI SİLME (' + $scope + '): ' + $what + ', ' + (Format-Size $bytes) + ', ' + (Get-WipeMethodName $method) + ', doğrulama: ' + (Get-WipeVerifyName $verify) + ' ---') 'STEP'
    Write-WhLog ('Hedef kimliği: boyut ' + (Format-Size ([double]$live.Size)) + ', seri ' + [string]$live.Serial + ', kimlik ' + [string]$live.UniqueId + ', ' + [string]$extList.Count + ' aralık') 'INFO'

    # ---- yıkıcı hazırlık: bölümü kaldır ya da diski temizle ----
    $partOffset = [double]0
    $partSize = [double]0
    try {
        if ($scope -eq 'Partition') {
            $partOffset = [double]$pl.Part.Offset; $partSize = [double]$pl.Part.Size
            Write-WhLog ('Bölüm ' + [string]$P.Part + ' kaldırılıyor...') 'STEP'
            Invoke-WipeRemovePartition ([int]$tg.Number) ([int]$P.Part)
            $res.Started = $true
        } elseif ($scope -eq 'Disk') {
            Write-WhLog ('Disk ' + [string]$tg.Number + ' temizleniyor (bölümler kaldırılıyor)...') 'STEP'
            Invoke-WipeClearDisk ([int]$tg.Number)
            $res.Started = $true
        }
    } catch {
        $res.Error = 'Windows bölümü kaldıramadı: ' + (Get-WipeErrorText $_) + ' Hiçbir veri yazılmadı.'
        Write-WhLog $res.Error 'ERR'
        return $res
    }
    if ($res.Started) { Update-WipeStorage }

    # ---- yazma ----
    $key = [Mm.WipeEngine]::NewKey()
    $arr = ConvertTo-WipeExtents $extList
    $lastMode = [int]$modes[$modes.Count - 1]
    $tidy = ($scope -eq 'Disk' -and $lastMode -ne 1)
    $edges = $null
    if ($tidy) { $edges = [Mm.WipeLayout]::EdgeGuards([long]$len, [long]1048576, $sector) }
    $edgeBytes = [double]0
    if ($tidy) { foreach ($g in $edges) { $edgeBytes += [double]$g.Length } }
    $verifyBytes = [double]0
    if ($verify -eq 'full') { $verifyBytes = $bytes } elseif ($verify -eq 'sample') { $verifyBytes = [math]::Min($bytes, [double]33554432) }
    $totalWork = $res.Planned + $edgeBytes + $verifyBytes + $edgeBytes
    $wr = $null
    $t = $null
    try {
        $t = [Mm.WipeTarget]::Open([string]$tg.Spec, $true)
        $cb = New-WipeCallback ('Disk ' + [string]$tg.Number + ' siliniyor') $totalWork 0
        $wr = [Mm.WipeEngine]::Fill($t, $arr, [int[]]$modes, $key, $cb)
        $res.Written = [double]$wr.Written
        $res.WriteErrors = [int]$wr.WriteErrors
        if ($wr.Canceled) { $res.Canceled = $true; Write-WhLog 'İptal edildi.' 'WARN' }
        elseif ($wr.Error -ne '') { $res.Error = [string]$wr.Error; Write-WhLog ('Yazma durdu: ' + $res.Error) 'ERR' }
        elseif ($wr.WriteErrors -gt 0) {
            $res.Notes += ([string]$wr.WriteErrors + ' bölgeye yazılamadı (ilk konum ' + (Format-Size ([double]$wr.FirstWriteError)) + '); disk hasarlı olabilir.')
            Write-WhLog $res.Notes[$res.Notes.Count - 1] 'WARN'
        }
        if (-not $res.Canceled -and $res.Error -eq '' -and $tidy) {
            $cb2 = New-WipeCallback ('Disk ' + [string]$tg.Number + ' siliniyor') $totalWork ($res.Planned)
            $tr = [Mm.WipeEngine]::Fill($t, $edges, [int[]]@(1), $key, $cb2)
            if ($tr.Error -ne '') { $res.Error = [string]$tr.Error; Write-WhLog ('Disk başı/sonu sıfırlanamadı: ' + $res.Error) 'ERR' }
            elseif ($tr.Canceled) { $res.Canceled = $true }
        }
    } catch {
        $res.Error = Get-WipeErrorText $_
        Write-WhLog ('Silme hatası: ' + $res.Error) 'ERR'
    } finally {
        if ($null -ne $t) { try { $t.Dispose() } catch { } }
    }

    # ---- doğrulama: yazılanı aygıttan yeniden oku ----
    if ($res.Error -eq '' -and -not $res.Canceled -and $verify -ne 'none') {
        $v = $null
        try {
            $t2 = [Mm.WipeTarget]::Open([string]$tg.Spec, $false)
            try {
                $vext = $arr
                if ($tidy) {
                    $g0 = [long]$edges[0].Length
                    $vlist = New-Object System.Collections.ArrayList
                    foreach ($e in $extList) {
                        $s = [double]$e.Start; $l = [double]$e.Length
                        if ($s -lt $g0) { $l -= ($g0 - $s); $s = [double]$g0 }
                        if ($edges.Count -gt 1 -and ($s + $l) -gt [double]$edges[1].Start) { $l = [double]$edges[1].Start - $s }
                        if ($l -gt 0) { [void]$vlist.Add(@{ Start = $s; Length = $l }) }
                    }
                    $vext = ConvertTo-WipeExtents $vlist.ToArray()
                }
                $samples = 0
                if ($verify -eq 'sample') { $samples = 256 }
                $cb3 = New-WipeCallback ('Disk ' + [string]$tg.Number + ' doğrulanıyor') $totalWork ($res.Planned + $edgeBytes)
                if ($vext.Count -gt 0) {
                    $v = [Mm.WipeEngine]::Verify($t2, $vext, $lastMode, $key, ($modes.Count - 1), $samples, $cb3)
                    $res.Verified = [double]$v.Verified
                    $res.BadUnits = [double]$v.BadUnits
                    if ($v.Canceled) { $res.Canceled = $true }
                    elseif ($v.Error -ne '') { $res.Error = 'Doğrulama yapılamadı: ' + [string]$v.Error; Write-WhLog $res.Error 'ERR' }
                    elseif ($v.BadUnits -gt 0) {
                        $res.Error = 'Doğrulama başarısız: ' + [string]$v.BadUnits + ' birim yazılandan farklı okundu (ilk konum ' + (Format-Size ([double]$v.FirstBad)) + '). Disk hasarlı ya da yazma önbelleği olan bir bağdaştırıcıda olabilir.'
                        Write-WhLog $res.Error 'ERR'
                    }
                }
                if ($tidy -and $res.Error -eq '' -and -not $res.Canceled) {
                    $z = [Mm.WipeEngine]::Verify($t2, $edges, 1, $key, 0, 0, $null)
                    $res.Verified += [double]$z.Verified
                    if ($z.BadUnits -gt 0) { $res.Notes += 'Diskin başı/sonu sıfırlanamadı olabilir.'; Write-WhLog $res.Notes[$res.Notes.Count - 1] 'WARN' }
                }
            } finally { $t2.Dispose() }
        } catch {
            $res.Error = 'Doğrulama yapılamadı: ' + (Get-WipeErrorText $_)
            Write-WhLog $res.Error 'ERR'
        }
        $res.VerifyKind = $verify
    }

    # ---- sonra: yeni bölüm ve biçim ----
    if ($res.Error -eq '' -and -not $res.Canceled -and $after -ne 'none' -and $scope -ne 'Unallocated') {
        try {
            # 2 TB altındaki USB bellekler ve zaten MBR olan diskler MBR, diğerleri GPT olarak başlatılır
            $style = 'GPT'
            if ($len -lt 2199023255552 -and ([string]$live.Bus -eq 'USB' -or [string]$live.Style -eq 'MBR')) { $style = 'MBR' }
            Write-WhLog ('Yeni bölüm açılıyor ve ' + (Get-WipeAfterName $after) + '...') 'STEP'
            $letter = Invoke-WipeNewVolume ([int]$tg.Number) ($scope -eq 'Disk') $partOffset $partSize $after $style
            $res.Letter = [string]$letter
            $res.AfterDone = (Get-WipeAfterName $after)
            Update-WipeStorage
        } catch {
            $res.Notes += ('Yeni bölüm açılamadı: ' + (Get-WipeErrorText $_) + ' Alan silinmiş durumda; Disk Yönetimi uygulamasından bölüm açabilirsiniz.')
            Write-WhLog $res.Notes[$res.Notes.Count - 1] 'WARN'
        }
    } elseif ($res.Started) { Update-WipeStorage }

    $res.Ok = ($res.Error -eq '' -and -not $res.Canceled)
    $res.Seconds = [double]$sw0.Elapsed.TotalSeconds
    $verb = 'bitti'
    if ($res.Canceled) { $verb = 'iptal edildi' } elseif (-not $res.Ok) { $verb = 'tamamlanamadı' }
    Write-WhLog ('KAYIT: ' + $what + ' (' + $scope + ') silme ' + $verb + ': ' + (Format-Size $res.Written) + ' yazıldı, ' + (Format-Size $res.Verified) + ' doğrulandı, ' + [string][int][math]::Round($res.Seconds) + ' sn') 'INFO'
    return $res
}

# ---------------- kendi kendine denetim ----------------
# Motorun bu bilgisayarda çalıştığını, hiçbir veriye dokunmadan gösterir: derleme, geçici bir imaj üzerinde yazma ve doğrulama,
# dosya konumu sorgusu ve (yönetici ise) sistem diskinin ilk sektörünü SALT OKUNUR açma. Dönüş: @{ Ok; Lines = @(@{ Ok; Text }) }
function global:Invoke-WipeSelfCheck {
    $lines = New-Object System.Collections.ArrayList
    $ok = $true
    $ie = Initialize-MmWipe
    if ($ie -ne '') { return @{ Ok = $false; Lines = @(@{ Ok = $false; Text = $ie }) } }
    [void]$lines.Add(@{ Ok = $true; Text = 'Silme motoru derlendi.' })
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('mm-silme-deneme-' + [System.Guid]::NewGuid().ToString('N').Substring(0, 8) + '.img')
    try {
        $bytes = New-Object byte[] 8388608
        for ($i = 0; $i -lt $bytes.Length; $i++) { $bytes[$i] = 165 }
        [System.IO.File]::WriteAllBytes($tmp, $bytes)
        $key = [Mm.WipeEngine]::NewKey()
        $t = [Mm.WipeTarget]::Open($tmp, $true)
        try {
            $ext = ConvertTo-WipeExtents @(@{ Start = 1048576; Length = 4194304 })
            $r = [Mm.WipeEngine]::Fill($t, $ext, [int[]]@(0, 0), $key, $null)
            $v = [Mm.WipeEngine]::Verify($t, $ext, 0, $key, 1, 0, $null)
            $good = ($r.Error -eq '' -and $v.Error -eq '' -and $v.BadUnits -eq 0 -and $r.Written -eq 8388608)
            [void]$lines.Add(@{ Ok = $good; Text = 'Geçici imaj üzerinde yazma ve doğrulama (2 geçiş, 4 MB).' })
            if (-not $good) { $ok = $false }
        } finally { $t.Dispose() }
        $after = [System.IO.File]::ReadAllBytes($tmp)
        $same = $true
        foreach ($i in @(0, 1048575, 5242880, 5242881, 8388607)) { if ($after[$i] -ne 165) { $same = $false } }
        [void]$lines.Add(@{ Ok = $same; Text = 'Aralığın dışındaki baytlar değişmedi.' })
        if (-not $same) { $ok = $false }
        if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) {
            $q = Get-WipeFileExtents $tmp
            $qok = (@($q.Extents).Count -gt 0 -and [long]$q.Cluster -gt 0)
            [void]$lines.Add(@{ Ok = $qok; Text = 'Dosyanın birimdeki konumu sorgulandı (kanarya doğrulaması için gerekli).' })
            if (-not $qok) { $ok = $false }
            if (Test-WipeAdmin) {
                $dn = -1
                try { $dn = [int](@(Get-Partition -DriveLetter ([string]$env:SystemDrive).Substring(0, 1) -ErrorAction Stop)[0]).DiskNumber } catch { $dn = -1 }
                if ($dn -ge 0) {
                    $ro = $null
                    try {
                        $ro = [Mm.WipeTarget]::Open(('PhysicalDrive' + [string]$dn), $false)
                        $b = New-Object byte[] 4096
                        $n = $ro.ReadAt(0, $b, 0, 4096)
                        [void]$lines.Add(@{ Ok = ($n -ge 512); Text = ('Sistem diski (Disk ' + [string]$dn + ') doğrudan, salt okunur açıldı; ilk sektör okundu.') })
                        if ($n -lt 512) { $ok = $false }
                    } catch {
                        [void]$lines.Add(@{ Ok = $false; Text = ('Disk doğrudan açılamadı: ' + (Get-WipeErrorText $_)) })
                        $ok = $false
                    } finally { if ($null -ne $ro) { $ro.Dispose() } }
                }
            } else {
                [void]$lines.Add(@{ Ok = $true; Text = 'Disk doğrudan açma denemesi atlandı (yönetici değil).' })
            }
        }
    } catch {
        [void]$lines.Add(@{ Ok = $false; Text = (Get-WipeErrorText $_) })
        $ok = $false
    } finally {
        try { if (Test-Path -LiteralPath $tmp) { [System.IO.File]::Delete($tmp) } } catch { }
    }
    return @{ Ok = $ok; Lines = $lines.ToArray() }
}
