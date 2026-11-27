// Multimizer kurtarma motoru, ikinci bölüm (partial): FAT ve exFAT klasör taraması, ext2/3/4 blok haritası.
// Bu dosya yalnızca OKUR; RcEngine.cs ile birlikte tek parça olarak derlenir (build.py ek kaynakları birleştirir).
// C# 5 uyumlu yazılmıştır.
using System;
using System.Collections.Generic;
using System.IO;
using System.Text;

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
            "ÇüéâäàåçêëèïîìÄÅ" +
            "ÉæÆôöòûùÿÖÜ¢£¥₧ƒ" +
            "áíóúñÑªº¿⌐¬½¼¡«»" +
            "░▒▓│┤╡╢╖╕╣║╗╝╜╛┐" +
            "└┴┬├─┼╞╟╚╔╩╦╠═╬╧" +
            "╨╤╥╙╘╒╓╫╪┘┌█▄▌▐▀" +
            "αßΓπΣσµτΦΘΩδ∞φε∩" +
            "≡±≥≤⌠⌡÷≈°∙·√ⁿ²■ ";

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
            if (rootData == null) throw new IOException("Kök klasör okunamadı.");
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
                if (!Tick(prog, "Klasörler okunuyor", done, known)) { Canceled = true; return res; }
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
                if (free == 0) note = "Disk alanı başka dosyalarca kullanılıyor; büyük olasılıkla üzerine yazılmış.";
                else if (free < need) note = "Disk alanı kısmen yeniden kullanılmış; dosya eksik ya da bozuk olabilir.";
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
                    AddNote(it, "Dosyanın başı sıfırlarla dolu; veri silinmiş ya da SSD TRIM ile temizlenmiş olabilir.");
                }
                return;
            }
            string want = SniffTypeForExt(it.Ext);
            if (want == null) return;
            string have = Sniff(hb, 0, 32);
            if (have != want)
            {
                if (it.Chance > 20) it.Chance = 20;
                AddNote(it, "Dosyanın başı beklenen biçimde değil; başka veriyle üzerine yazılmış olabilir.");
            }
        }

        bool VerifyHeads(List<RcItem> res, RcProgress prog)
        {
            List<RcItem> order = new List<RcItem>(res);
            order.Sort(delegate(RcItem a, RcItem b) { return a.Offset.CompareTo(b.Offset); });
            for (int i = 0; i < order.Count; i++)
            {
                if ((i & 63) == 0 && !Tick(prog, "Dosya başlıkları denetleniyor", i, order.Count)) return false;
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
            if (it.Length <= 0 || it.Offset < dataStart || ClusterSize <= 0) throw new IOException("Dosya konumu geçersiz.");
            long cl = (it.Offset - dataStart) / ClusterSize + firstCluster;
            if (it.Offset != ClusterOffset(cl)) throw new IOException("Dosya konumu geçersiz.");
            long need = (it.Length + ClusterSize - 1) / ClusterSize;
            if (cl < firstCluster || cl + need > firstCluster + ClusterCount) throw new IOException("Dosya konumu geçersiz.");
            if (IsUsed(cl)) throw new IOException("Bu dosyanın disk alanı sonradan başka bir dosyaya verilmiş; kurtarılamaz.");
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

        // Girdi kümesinin sağlama toplamı. Silinmiş kümelerde "kullanımda" biti sıfırlanmıştır; hesapta geri konur.
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
            if (rootData == null) throw new IOException("Kök klasör okunamadı.");
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
                if (!Tick(prog, "Klasörler okunuyor", done, known)) { Canceled = true; return res; }
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
                if (free == 0) note = "Disk alanı başka dosyalarca kullanılıyor; büyük olasılıkla üzerine yazılmış.";
                else if (free < need) note = "Disk alanı kısmen yeniden kullanılmış; dosya eksik ya da bozuk olabilir.";
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
            if (logBs < 0 || logBs > 6) throw new IOException("ext blok boyutu geçersiz.");
            long bs = 1024L << logBs;
            if ((incompat & 0x10u) != 0) throw new IOException("ext meta_bg düzeni bu sürümde desteklenmiyor.");
            if ((rocompat & 0x200u) != 0) throw new IOException("ext bigalloc düzeni bu sürümde desteklenmiyor.");
            bool is64 = (incompat & 0x80u) != 0;
            long blocks = blocksLo;
            int descSize = 32;
            if (is64)
            {
                blocks |= ((long)U32(b, so + 336)) << 32;
                descSize = U16(b, so + 254);
                if (descSize < 64 || descSize > 1024 || (descSize & (descSize - 1)) != 0) throw new IOException("ext grup tanımlayıcı boyutu geçersiz.");
            }
            if (bpg == 0 || bpg > 8 * bs || (bpg & 7) != 0 || blocks <= fdb || fdb > 1) throw new IOException("ext süper blok geçersiz.");
            long groups = (blocks - fdb + bpg - 1) / bpg;
            if (groups > 1000000 || groups * descSize > (64L << 20)) throw new IOException("Sürücü bu sürüm için çok büyük.");
            ClusterSize = bs;
            ClusterCount = blocks - fdb;
            firstCluster = fdb;
            dataStart = fdb * bs;
            VolumeBytes = blocks * bs;
            long need = (ClusterCount + 7) / 8;
            if (need > (1000L << 20)) throw new IOException("Sürücü bu sürüm için çok büyük.");
            bitmap = new byte[need];
            byte[] gdt = new byte[groups * descSize];
            if (ReadVol((fdb + 1) * bs, gdt, 0, gdt.Length) < gdt.Length) throw new IOException("ext grup tanımlayıcı tablosu okunamadı.");
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
