#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Kurtarma motoru testleri icin sentetik disk imajlari uretir (NTFS, FAT12/16/32, exFAT, bolum tablolu imajlar).
Hicbir ucuncu taraf imajindan ya da araciyla uretilmis dosyadan yararlanilmaz; her bayt burada olusturulur.
Kullanim: gen_images.py <cikti_klasoru>   -> imajlar + expect.json"""
import datetime
import hashlib
import io
import json
import os
import random
import struct
import sys
import zipfile
import zlib

CL = 4096
SEC = 512
REC = 1024


def sha(b):
    return hashlib.sha256(bytes(b)).hexdigest()


def ft(y, m, d, hh=0, mm=0, ss=0):
    dt = datetime.datetime(y, m, d, hh, mm, ss, tzinfo=datetime.timezone.utc)
    return int((dt.timestamp() + 11644473600) * 10000000)


def rnd(seed, n):
    r = random.Random(seed)
    return bytes(r.getrandbits(8) for _ in range(n))


def pad8(n):
    return (n + 7) & ~7


# ------------------------------------------------------------------ dosya icerikleri
def make_jpeg(seed, size):
    r = random.Random(seed)
    out = bytearray(b'\xff\xd8')
    out += b'\xff\xe0' + struct.pack('>H', 16) + b'JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00'
    out += b'\xff\xdb' + struct.pack('>H', 67) + b'\x00' + bytes(r.getrandbits(6) + 1 for _ in range(64))
    out += b'\xff\xc0' + struct.pack('>H', 17) + b'\x08\x00\x10\x00\x10\x03\x01\x22\x00\x02\x11\x01\x03\x11\x01'
    out += b'\xff\xc4' + struct.pack('>H', 20) + b'\x00' + bytes([1] + [0] * 15) + b'\x00'
    out += b'\xff\xda' + struct.pack('>H', 12) + b'\x03\x01\x00\x02\x11\x03\x11\x00\x3f\x00'
    body = bytearray()
    while len(body) < size - len(out) - 2:
        v = r.getrandbits(8)
        if v == 0xFF:
            body += b'\xff\x00'
        else:
            body.append(v)
        if len(body) % 700 == 699:
            body += b'\xff' + bytes([0xD0 + (len(body) // 700) % 8])
    out += body + b'\xff\xd9'
    return bytes(out)


def png_chunk(t, data):
    c = struct.pack('>I', len(data)) + t + data
    return c + struct.pack('>I', zlib.crc32(t + data) & 0xFFFFFFFF)


def make_png(seed, w, h):
    raw = b''.join(b'\x00' + rnd(seed + y, w * 3) for y in range(h))
    return (b'\x89PNG\r\n\x1a\n' + png_chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
            + png_chunk(b'IDAT', zlib.compress(raw, 6)) + png_chunk(b'IEND', b''))


def make_gif(seed):
    out = bytearray(b'GIF89a')
    out += struct.pack('<HHBBB', 8, 8, 0x80 | 0x01, 0, 0)
    out += bytes([0, 0, 0, 255, 255, 255, 255, 0, 0, 0, 0, 255])
    out += b'\x21\xf9\x04\x00\x00\x00\x00\x00'
    out += b'\x2c' + struct.pack('<HHHHB', 0, 0, 8, 8, 0)
    out += b'\x02'
    data = rnd(seed, 40)
    out += bytes([len(data)]) + data + b'\x00'
    out += b'\x3b'
    return bytes(out)


def make_pdf(seed, size):
    head = b'%PDF-1.4\n%\xe2\xe3\xcf\xd3\n1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n'
    tail = b'xref\n0 3\n0000000000 65535 f \ntrailer\n<< /Size 3 /Root 1 0 R >>\nstartxref\n9\n%%EOF\n'
    filler_len = max(0, size - len(head) - len(tail) - 40)
    r = random.Random(seed)
    filler = bytes(r.choice(b'abcdefghijklmnop qrstuvwxyz0123456789\n') for _ in range(filler_len))
    mid = b'4 0 obj\n<< /Length %d >>\nstream\n' % filler_len + filler + b'\nendstream\nendobj\n'
    return head + mid + tail


def make_zip(kind):
    bio = io.BytesIO()
    with zipfile.ZipFile(bio, 'w', zipfile.ZIP_DEFLATED) as z:
        z.writestr('[Content_Types].xml', '<?xml version="1.0"?><Types xmlns="x"></Types>')
        if kind == 'docx':
            z.writestr('word/document.xml', '<w:document>' + 'Merhaba dunya. ' * 200 + '</w:document>')
        elif kind == 'xlsx':
            z.writestr('xl/workbook.xml', '<workbook>' + 'sayfa ' * 200 + '</workbook>')
        else:
            z.writestr('metin.txt', 'duz zip ' * 300)
    return bio.getvalue()


def make_bmp(w, h, seed):
    row = (w * 3 + 3) & ~3
    pix = rnd(seed, row * h)
    hdr = b'BM' + struct.pack('<IHHI', 54 + len(pix), 0, 0, 54)
    dib = struct.pack('<IiiHHIIiiII', 40, w, h, 1, 24, 0, len(pix), 2835, 2835, 0, 0)
    return hdr + dib + pix


def make_sqlite(seed, pages=4, ps=1024):
    b = bytearray(rnd(seed, pages * ps))
    b[0:16] = b'SQLite format 3\x00'
    struct.pack_into('>H', b, 16, ps)
    b[18] = 1
    b[19] = 1
    b[20] = 0
    b[21:24] = bytes([64, 32, 32])
    struct.pack_into('>I', b, 24, 7)
    struct.pack_into('>I', b, 28, pages)
    struct.pack_into('>I', b, 92, 7)
    return bytes(b)


def make_7z(seed, packed=1500, nxt=96):
    body = rnd(seed, packed)
    header = rnd(seed + 1, nxt)
    start = struct.pack('<QQI', packed, nxt, zlib.crc32(header) & 0xFFFFFFFF)
    return b'7z\xbc\xaf\x27\x1c' + b'\x00\x04' + struct.pack('<I', zlib.crc32(start) & 0xFFFFFFFF) + start + body + header


def make_mp4(seed, mdat_len=6000):
    ftyp = struct.pack('>I', 24) + b'ftypisom' + struct.pack('>I', 0x200) + b'isomiso2'
    mdat = struct.pack('>I', 8 + mdat_len) + b'mdat' + rnd(seed, mdat_len)
    mvhd = struct.pack('>I', 108) + b'mvhd' + bytes(100)
    moov = struct.pack('>I', 8 + len(mvhd)) + b'moov' + mvhd
    return ftyp + mdat + moov


def make_wav(seed, n=5000):
    data = rnd(seed, n)
    fmt = struct.pack('<4sIHHIIHH', b'fmt ', 16, 1, 1, 8000, 8000, 1, 8)
    return b'RIFF' + struct.pack('<I', 4 + len(fmt) + 8 + n) + b'WAVE' + fmt + b'data' + struct.pack('<I', n) + data


def make_ole(name='WordDocument'):
    hdr = bytearray(512)
    hdr[0:8] = bytes([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1])
    struct.pack_into('<HHHHH', hdr, 24, 0x3E, 3, 0xFFFE, 9, 6)
    struct.pack_into('<I', hdr, 44, 1)           # FAT sektor sayisi
    struct.pack_into('<I', hdr, 48, 1)           # ilk dizin sektoru
    struct.pack_into('<I', hdr, 56, 4096)
    struct.pack_into('<I', hdr, 60, 0xFFFFFFFE)
    struct.pack_into('<I', hdr, 68, 0xFFFFFFFE)
    for i in range(109):
        struct.pack_into('<I', hdr, 76 + 4 * i, 0 if i == 0 else 0xFFFFFFFF)
    fat = bytearray(b'\xff' * 512)
    struct.pack_into('<I', fat, 0, 0xFFFFFFFD)
    struct.pack_into('<I', fat, 4, 0xFFFFFFFE)
    d = bytearray(512)
    for idx, nm in enumerate(('Root Entry', name)):
        e = nm.encode('utf-16-le')
        d[idx * 128:idx * 128 + len(e)] = e
        struct.pack_into('<H', d, idx * 128 + 64, len(e) + 2)
    return bytes(hdr + fat + d)


# ------------------------------------------------------------------ NTFS
def attr_res(atype, content, name='', flags=0, aid=0):
    nm = name.encode('utf-16-le')
    coff = pad8(0x18 + len(nm))
    length = pad8(coff + len(content))
    b = bytearray(length)
    struct.pack_into('<II', b, 0, atype, length)
    b[9] = len(name)
    struct.pack_into('<HHH', b, 0x0A, 0x18, flags, aid)
    struct.pack_into('<I', b, 0x10, len(content))
    struct.pack_into('<H', b, 0x14, coff)
    b[0x18:0x18 + len(nm)] = nm
    b[coff:coff + len(content)] = content
    return bytes(b)


def attr_nonres(atype, runs, start_vcn, last_vcn, alloc, real, init, name='', flags=0, aid=0):
    nm = name.encode('utf-16-le')
    roff = pad8(0x40 + len(nm))
    length = pad8(roff + len(runs) + 1)
    b = bytearray(length)
    struct.pack_into('<II', b, 0, atype, length)
    b[8] = 1
    b[9] = len(name)
    struct.pack_into('<HHH', b, 0x0A, 0x40, flags, aid)
    struct.pack_into('<QQ', b, 0x10, start_vcn, last_vcn)
    struct.pack_into('<H', b, 0x20, roff)
    struct.pack_into('<QQQ', b, 0x28, alloc, real, init)
    b[0x40:0x40 + len(nm)] = nm
    b[roff:roff + len(runs)] = runs
    return bytes(b)


def enc_runs(runs):
    """runs: [(lcn | None, uzunluk)]; lcn None = seyrek"""
    out = bytearray()
    prev = 0
    for lcn, ln in runs:
        lb = ln.to_bytes(max(1, (ln.bit_length() + 7) // 8), 'little')
        if lcn is None:
            out.append(len(lb))
            out += lb
            continue
        delta = lcn - prev
        n = 1
        while not (-(1 << (8 * n - 1)) <= delta < (1 << (8 * n - 1))):
            n += 1
        db = delta.to_bytes(n, 'little', signed=True)
        out.append((n << 4) | len(lb))
        out += lb + db
        prev = lcn
    return bytes(out)


def std_info(created, modified, changed):
    return attr_res(0x10, struct.pack('<QQQQI', created, modified, changed, modified, 0x20) + bytes(36))


def file_name(parent, seq, name, ns, size, modified):
    nm = name.encode('utf-16-le')
    c = struct.pack('<QQQQQQQII', parent | (seq << 48), modified, modified, modified, modified, size, size, 0x20, 0)
    c += bytes([len(name), ns]) + nm
    return attr_res(0x30, c, flags=0, aid=0)


def build_record(num, seq, flags, attrs, base=0, bad_fixup=False):
    rec = bytearray(REC)
    rec[0:4] = b'FILE'
    struct.pack_into('<HH', rec, 4, 0x30, 3)
    struct.pack_into('<HHHH', rec, 0x10, seq, 1, 0x38, flags)
    struct.pack_into('<I', rec, 0x1C, REC)
    struct.pack_into('<Q', rec, 0x20, base)
    struct.pack_into('<H', rec, 0x28, len(attrs) + 1)
    struct.pack_into('<I', rec, 0x2C, num)
    p = 0x38
    for a in attrs:
        rec[p:p + len(a)] = a
        p += len(a)
    struct.pack_into('<I', rec, p, 0xFFFFFFFF)
    used = pad8(p + 8)
    if used > 1020:
        raise SystemExit('kayit tasti: %d' % used)
    struct.pack_into('<I', rec, 0x18, used)
    usn = 0x0005
    struct.pack_into('<H', rec, 0x30, usn)
    for i in range(2):
        end = (i + 1) * 512 - 2
        rec[0x32 + 2 * i:0x34 + 2 * i] = rec[end:end + 2]
        struct.pack_into('<H', rec, end, 0x1234 if (bad_fixup and i == 1) else usn)
    return bytes(rec)


def index_root():
    return attr_res(0x90, struct.pack('<IIII', 0x30, 1, 0x1000, 1) + struct.pack('<IIII', 16, 32, 32, 0) + bytes(16) , name='$I30')


def attr_list(entries):
    """entries: [(tip, vcn, kayit_no, seq)]"""
    out = bytearray()
    for t, vcn, rec, seq in entries:
        e = bytearray(32)
        struct.pack_into('<IHBB', e, 0, t, 32, 0, 26)
        struct.pack_into('<Q', e, 8, vcn)
        struct.pack_into('<Q', e, 16, rec | (seq << 48))
        out += e
    return attr_res(0x20, bytes(out))


class Ntfs:
    def __init__(self, clusters=2048):
        self.n = clusters
        self.img = bytearray(clusters * CL)
        self.used = set()
        self.records = {}
        self.expect = {'deleted': [], 'carve': [], 'inuse': []}
        # MFT: 128 kayit = 32 kume. A: VCN0-5 -> LCN4-9, B: VCN6-31 -> LCN20-45
        self.late = []

    def mark(self, lcn, n):
        for i in range(n):
            self.used.add(lcn + i)

    def write_clusters(self, runs, data):
        pos = 0
        for lcn, ln in runs:
            take = min(len(data) - pos, ln * CL)
            if take > 0:
                self.img[lcn * CL:lcn * CL + take] = data[pos:pos + take]
            pos += ln * CL

    def mft_pos(self, num):
        off = num * REC
        vcn = off // CL
        if vcn < 6:
            return (4 + vcn) * CL + off % CL
        return (20 + vcn - 6) * CL + off % CL

    def put(self, num, rec):
        self.records[num] = rec

    def finish(self, path):
        # $MFT kaydi (parcali + oznitelik listesi), kayit 20 ek kayit
        t0 = ft(2023, 1, 1)
        mft_runs_a = enc_runs([(4, 6)])
        mft_runs_b = enc_runs([(20, 26)])
        al = attr_list([(0x10, 0, 0, 1), (0x30, 0, 0, 1), (0x80, 0, 0, 1), (0x80, 6, 20, 1)])
        r0 = build_record(0, 1, 1, [
            std_info(t0, t0, t0), al, file_name(5, 5, '$MFT', 3, 65536, t0),
            attr_nonres(0x80, mft_runs_a, 0, 5, 131072, 131072, 131072, aid=3)])
        self.put(0, r0)
        self.put(20, build_record(20, 1, 1, [attr_nonres(0x80, mft_runs_b, 6, 31, 0, 0, 0, aid=1)], base=0 | (1 << 48)))
        for runs, content in self.late:
            self.write_clusters(runs, content)
        # $Bitmap (kayit 6)
        self.mark(12, 1)
        bm = bytearray(self.n // 8)
        for c in self.used:
            bm[c >> 3] |= 1 << (c & 7)
        self.write_clusters([(12, 1)], bytes(bm))
        self.put(6, build_record(6, 6, 1, [std_info(t0, t0, t0), file_name(5, 5, '$Bitmap', 3, len(bm), t0),
                                          attr_nonres(0x80, enc_runs([(12, 1)]), 0, 0, CL, len(bm), len(bm), aid=2)]))
        # kok dizin (kayit 5)
        self.put(5, build_record(5, 5, 3, [std_info(t0, t0, t0), file_name(5, 5, '.', 3, 0, t0), index_root()]))
        for num, rec in self.records.items():
            p = self.mft_pos(num)
            self.img[p:p + REC] = rec
        # onyukleme sektoru
        b = bytearray(512)
        b[0:3] = b'\xeb\x52\x90'
        b[3:11] = b'NTFS    '
        struct.pack_into('<HBH', b, 11, 512, 8, 0)
        b[21] = 0xF8
        struct.pack_into('<HH', b, 24, 63, 255)
        struct.pack_into('<Q', b, 40, self.n * 8 - 1)
        struct.pack_into('<QQ', b, 48, 4, 4)
        b[64] = 0xF6
        b[68] = 1
        struct.pack_into('<Q', b, 72, 0x1122334455667788)
        b[510:512] = b'\x55\xaa'
        self.img[0:512] = b
        open(path, 'wb').write(self.img)


def build_ntfs(path):
    N = Ntfs(2048)
    t_mod = ft(2024, 5, 17, 10, 30, 0)
    t_del = ft(2024, 6, 1, 8, 0, 0)
    t_cre = ft(2024, 1, 2, 3, 4, 5)
    N.mark(0, 10)      # onyukleme + MFT A
    N.mark(20, 26)     # MFT B
    ROOT = 5
    exp = N.expect
    next_rec = [24]

    def new_rec():
        r = next_rec[0]
        next_rec[0] += 1
        if r == 30 or r == 20:
            r = next_rec[0]
            next_rec[0] += 1
        return r

    def resident_file(name, content, parent=(ROOT, 5), inuse=False, seq=1, ns=1, extra_names=(), flags_data=0, kind='deleted', path='', mod=None, size_override=None, key=None):
        num = new_rec()
        mod = mod or t_mod
        attrs = [std_info(t_cre, mod, t_del)]
        for (nm, nsp) in extra_names:
            attrs.append(file_name(parent[0], parent[1], nm, nsp, len(content), mod))
        attrs.append(file_name(parent[0], parent[1], name, ns, len(content), mod))
        attrs.append(attr_res(0x80, content, flags=flags_data, aid=9))
        N.put(num, build_record(num, seq if inuse else seq + 1, 1 if inuse else 0, attrs))
        if kind == 'deleted':
            exp['deleted'].append({'key': key or name, 'name': name, 'path': path, 'size': len(content), 'chance': 100, 'sha': sha(content), 'mod': mod, 'rec': num})
        return num

    def nonres_file(name, content, runs, parent=(ROOT, 5), inuse=False, extra_flags=0, key=None, path='', chance=100, expect=True, size=None, ext_record=None):
        num = new_rec()
        size = len(content) if size is None else size
        nclus = sum(l for _, l in runs if _ is not None) if True else 0
        total_clusters = sum(l for _, l in runs)
        attrs = [std_info(t_cre, t_mod, t_del), file_name(parent[0], parent[1], name, 1, size, t_mod),
                 attr_nonres(0x80, enc_runs(runs), 0, total_clusters - 1, total_clusters * CL, size, size, flags=extra_flags, aid=4)]
        N.put(num, build_record(num, 1 if inuse else 2, 1 if inuse else 0, attrs))
        for lcn, ln in runs:
            if lcn is not None and inuse:
                N.mark(lcn, ln)
        if content is not None:
            if inuse:
                N.late.append(([(a, b) for a, b in runs if a is not None], content))
            else:
                N.write_clusters([(a, b) for a, b in runs if a is not None], content)
        if expect:
            exp['deleted'].append({'key': key or name, 'name': name, 'path': path, 'size': size, 'chance': chance, 'sha': sha(content), 'mod': t_mod, 'rec': num})
        return num

    # ---- dizinler
    N.put(40, build_record(40, 1, 3, [std_info(t_cre, t_mod, t_mod), file_name(ROOT, 5, 'Belgeler', 1, 0, t_mod), index_root()]))
    N.put(41, build_record(41, 2, 2, [std_info(t_cre, t_mod, t_del), file_name(40, 1, 'Eski', 1, 0, t_mod), index_root()]))
    N.put(42, build_record(42, 6, 3, [std_info(t_cre, t_mod, t_mod), file_name(ROOT, 5, 'Yeni', 1, 0, t_mod), index_root()]))
    next_rec[0] = 43

    # ---- kullanimda olan dosyalar (listelenmemeli)
    keep = b'Bu dosya silinmedi.\n' * 20
    num = new_rec()
    N.put(num, build_record(num, 1, 1, [std_info(t_cre, t_mod, t_mod), file_name(ROOT, 5, 'keep.txt', 1, len(keep), t_mod), attr_res(0x80, keep, aid=1)]))
    nonres_file('keep.bin', rnd(11, 2 * CL), [(60, 2)], inuse=True, expect=False)
    nonres_file('yeni.bin', rnd(12, 2 * CL), [(200, 2)], inuse=True, expect=False)
    nonres_file('yeni2.bin', rnd(13, 2 * CL), [(302, 2)], inuse=True, expect=False)
    nonres_file('cross.bin', rnd(14, CL), [(802, 1)], inuse=True, expect=False)

    # ---- silinmis, yerlesik (resident) dosyalar
    notlar = ('Toplanti notlari: ozel karakterler iceren Turkce metin. Çalışma, öğrenme, ğüşıİ. ' * 4).encode('utf-8')
    resident_file('notlar.txt', notlar, parent=(40, 1), path='Belgeler')
    resident_file('eski.docx', b'PK-eski-belge-icerigi' * 5, parent=(41, 1), path='Belgeler\\Eski')
    resident_file('yetim.txt', b'yetim dosya icerigi ' * 6, parent=(42, 5), path='[bilinmeyen klasör]')
    resident_file('Program Dosyaları.txt', b'DOS ve Win32 adlari olan dosya\n' * 3, extra_names=[('PROGRA~1.TXT', 2)], key='dosya-adlari')
    resident_file('$RABCDEF.docx', b'geri donusum kutusundan kalan veri ' * 3)
    resident_file('$IABCDEF.docx', b'geri donusum bilgi dosyasi', kind='skip')
    resident_file('sifir.txt', b'', kind='skip')

    # ---- silinmis, yer kaplayan dosyalar
    jpg = make_jpeg(21, 19500)
    nonres_file('foto.jpg', jpg, [(100, 5)])
    pdf = make_pdf(22, 30000)
    nonres_file('rapor.pdf', pdf, [(120, 3), (110, 5)])
    nonres_file('ezilmis.dat', rnd(23, 2 * CL - 50), [(200, 2)], chance=0)
    nonres_file('yarim.dat', rnd(24, 4 * CL - 10), [(300, 4)], chance=50)
    # oznitelik listeli parcali dosya: kayit 25 + ek kayit 30
    uzun = (b'UZUN-DOSYA-0123456789ABCDEF' * 800)[:20380]
    num = 25
    runs1 = [(400, 2)]
    runs2 = [(405, 3)]
    N.write_clusters([(400, 2), (405, 3)], uzun)
    al = attr_list([(0x10, 0, num, 2), (0x30, 0, num, 2), (0x80, 0, num, 2), (0x80, 2, 30, 1)])
    N.put(num, build_record(num, 2, 0, [std_info(t_cre, t_mod, t_del), al, file_name(ROOT, 5, 'uzun.bin', 1, len(uzun), t_mod),
                                         attr_nonres(0x80, enc_runs(runs1), 0, 1, 5 * CL, len(uzun), len(uzun), aid=4)]))
    N.put(30, build_record(30, 1, 0, [attr_nonres(0x80, enc_runs(runs2), 2, 4, 0, 0, 0, aid=1)], base=num | (2 << 48)))
    exp['deleted'].append({'key': 'uzun.bin', 'name': 'uzun.bin', 'path': '', 'size': len(uzun), 'chance': 100, 'sha': sha(uzun), 'mod': t_mod, 'rec': num})

    # ---- atlanmasi gerekenler
    nonres_file('sikisik.dat', rnd(31, CL), [(500, 1)], extra_flags=1, expect=False)
    nonres_file('efs.dat', rnd(32, CL), [(502, 1)], extra_flags=0x4000, expect=False)
    nonres_file('bozuk.dat', None, [(5000, 2)], expect=False, size=8192)
    # bozuk guncelleme dizisi
    num = new_rec()
    N.put(num, build_record(num, 2, 0, [std_info(t_cre, t_mod, t_del), file_name(ROOT, 5, 'yirtik.txt', 1, 10, t_mod), attr_res(0x80, b'0123456789', aid=1)], bad_fixup=True))

    # ---- kayit numarasi ile eslesmeyen "ek kayit" (kullanimda olmayan, ana kayit sifir degil) otomatik atlanir

    # ---- sahipsiz (kaydi olmayan) dosyalar: imza taramasi hedefleri
    orphans = []

    def orphan(lcn, name, data):
        N.write_clusters([(lcn, (len(data) + CL - 1) // CL)], data)
        exp['carve'].append({'name': name, 'lcn': lcn, 'size': len(data), 'sha': sha(data), 'ext': name.rsplit('.', 1)[1], 'offset': lcn * CL})

    orphan(600, 'orphan.jpg', make_jpeg(41, 9000))
    orphan(610, 'orphan.png', make_png(42, 24, 16))
    orphan(620, 'orphan.gif', make_gif(43))
    orphan(630, 'orphan.pdf', make_pdf(44, 7000))
    orphan(640, 'orphan.docx', make_zip('docx'))
    orphan(650, 'orphan.xlsx', make_zip('xlsx'))
    orphan(660, 'orphan.bmp', make_bmp(30, 20, 45))
    orphan(670, 'orphan.sqlite', make_sqlite(46))
    orphan(690, 'orphan.7z', make_7z(47))
    orphan(700, 'orphan.mp4', make_mp4(48))
    orphan(720, 'orphan.wav', make_wav(49))
    orphan(740, 'orphan.doc', make_ole())
    orphan(750, 'orphan.zip', make_zip('zip'))
    # tuzak: imzasi var ama yapisi bozuk (taranmamali)
    N.write_clusters([(760, 1)], b'\x89PNG\r\n\x1a\n' + rnd(50, 200))
    N.write_clusters([(765, 1)], b'\xff\xd8\xff\xe0' + rnd(51, 300))
    # tuzak: dosya bos alanin disina tasiyor (hemen sonrasi dolu kume)
    big = make_bmp(40, 60, 52)           # yaklasik 7 KB, ama yalnizca 1 kume bos alan kalmadan dolu kume geliyor
    N.write_clusters([(801, 2)], big)    # 802 kumesi dolu (cross.bin); kayit sonunda cross.bin verisi onu ezer
    exp['trap_bmp_lcn'] = 801

    N.finish(path)
    # bayraklar: kullanimda kumeler
    exp['clusters'] = N.n
    exp['mft_records'] = 128
    exp['jpg_foto_lcn'] = 100
    return exp


# ------------------------------------------------------------------ FAT ailesi
def build_fat32(path, orphans):
    spc, rsv, nfat, bps = 8, 32, 2, 512
    clusters = 1024
    fatsz = ((clusters + 2) * 4 + 511) // 512
    total = rsv + nfat * fatsz + clusters * spc
    img = bytearray(total * bps)
    b = bytearray(512)
    b[0:3] = b'\xeb\x58\x90'
    b[3:11] = b'MSDOS5.0'
    struct.pack_into('<HBHB', b, 11, bps, spc, rsv, nfat)
    b[21] = 0xF8
    struct.pack_into('<I', b, 32, total)
    struct.pack_into('<I', b, 36, fatsz)
    struct.pack_into('<I', b, 44, 2)
    struct.pack_into('<HH', b, 48, 1, 6)
    b[66] = 0x29
    b[82:90] = b'FAT32   '
    b[510:512] = b'\x55\xaa'
    img[0:512] = b
    fat = bytearray(fatsz * 512)
    struct.pack_into('<I', fat, 0, 0x0FFFFFF8)
    struct.pack_into('<I', fat, 4, 0x0FFFFFFF)
    struct.pack_into('<I', fat, 8, 0x0FFFFFFF)      # kok dizin (kume 2)
    for c in (3, 4, 5):                               # kullanimdaki dosya: 3 -> 4 -> 5 -> son
        struct.pack_into('<I', fat, 4 * c, 0x0FFFFFFF if c == 5 else c + 1)
    for k in range(nfat):
        img[(rsv + k * fatsz) * 512:(rsv + (k + 1) * fatsz) * 512] = fat
    data0 = (rsv + nfat * fatsz) * 512
    exp = []
    for lcn, name, data in orphans:
        off = data0 + (lcn - 2) * spc * 512
        img[off:off + len(data)] = data
        exp.append({'name': name, 'offset': off, 'size': len(data), 'sha': sha(data), 'ext': name.rsplit('.', 1)[1]})
    # kullanimdaki dosya verisi (listelenmemeli): kume 3 icinde jpeg imzasi, ama kume dolu
    sig = make_jpeg(60, 3000)
    img[data0 + (3 - 2) * spc * 512:data0 + (3 - 2) * spc * 512 + len(sig)] = sig
    open(path, 'wb').write(img)
    return exp


def build_fat16(path, fat12=False):
    bps = 512
    if fat12:
        spc, rsv, nfat, rootent, total, fatsz = 1, 1, 2, 224, 2880, 9
    else:
        spc, rsv, nfat, rootent, total, fatsz = 4, 1, 2, 512, 32768, 32
    rootsec = rootent * 32 // 512
    clusters = (total - rsv - nfat * fatsz - rootsec) // spc
    img = bytearray(total * bps)
    b = bytearray(512)
    b[0:3] = b'\xeb\x3c\x90'
    b[3:11] = b'MSDOS5.0'
    struct.pack_into('<HBHB', b, 11, bps, spc, rsv, nfat)
    struct.pack_into('<H', b, 17, rootent)
    struct.pack_into('<H', b, 19, total if total < 65536 else 0)
    b[21] = 0xF0 if fat12 else 0xF8
    struct.pack_into('<H', b, 22, fatsz)
    b[54:62] = b'FAT12   ' if fat12 else b'FAT16   '
    b[510:512] = b'\x55\xaa'
    img[0:512] = b
    fat = bytearray(fatsz * 512)
    if fat12:
        def set12(n, v):
            idx = n + (n >> 1)
            cur = fat[idx] | (fat[idx + 1] << 8)
            cur = (cur & 0x000F) | (v << 4) if n & 1 else (cur & 0xF000) | v
            fat[idx] = cur & 0xFF
            fat[idx + 1] = cur >> 8
        set12(0, 0xFF0)
        set12(1, 0xFFF)
        for c in (2, 3):
            set12(c, 0xFFF if c == 3 else c + 1)
    else:
        struct.pack_into('<HH', fat, 0, 0xFFF8, 0xFFFF)
        for c in (2, 3):
            struct.pack_into('<H', fat, 2 * c, 0xFFFF if c == 3 else c + 1)
    for k in range(nfat):
        img[(rsv + k * fatsz) * 512:(rsv + (k + 1) * fatsz) * 512] = fat
    data0 = (rsv + nfat * fatsz + rootsec) * 512
    cs = spc * 512
    exp = []
    items = [(50, 'a.gif', make_gif(70)), (60, 'b.jpg', make_jpeg(71, 1800))]
    if not fat12:
        items.append((300, 'c.png', make_png(72, 20, 12)))
    for lcn, name, data in items:
        off = data0 + (lcn - 2) * cs
        img[off:off + len(data)] = data
        exp.append({'name': name, 'offset': off, 'size': len(data), 'sha': sha(data), 'ext': name.rsplit('.', 1)[1]})
    open(path, 'wb').write(img)
    return {'clusters': clusters, 'items': exp}


def build_exfat(path, orphans):
    bpsS, spcS = 9, 3
    bps, cs = 512, 4096
    clusters = 1024
    fat_off = 24
    heap_off = 64
    total = heap_off + clusters * 8
    img = bytearray(total * bps)
    b = bytearray(512)
    b[0:3] = b'\xeb\x76\x90'
    b[3:11] = b'EXFAT   '
    struct.pack_into('<Q', b, 64, 0)
    struct.pack_into('<Q', b, 72, total)
    struct.pack_into('<IIII', b, 80, fat_off, 8, heap_off, clusters)
    struct.pack_into('<I', b, 96, 4)
    struct.pack_into('<I', b, 100, 0xCAFEBABE)
    struct.pack_into('<H', b, 104, 0x0100)
    b[108] = bpsS
    b[109] = spcS
    b[110] = 1
    b[510:512] = b'\x55\xaa'
    img[0:512] = b
    fat = bytearray(8 * 512)
    struct.pack_into('<III', fat, 0, 0xFFFFFFF8, 0xFFFFFFFF, 0xFFFFFFFF)
    struct.pack_into('<II', fat, 12, 0xFFFFFFFF, 0xFFFFFFFF)
    img[fat_off * 512:fat_off * 512 + len(fat)] = fat
    # tahsis haritasi (kume 2): 2, 3, 4 ve 5-6 (kullanimdaki dosya) dolu
    bm = bytearray((clusters + 7) // 8)
    for c in (2, 3, 4, 5, 6):
        i = c - 2
        bm[i >> 3] |= 1 << (i & 7)
    def coff(c):
        return heap_off * 512 + (c - 2) * cs
    img[coff(2):coff(2) + len(bm)] = bm
    root = bytearray(cs)
    root[0] = 0x81
    struct.pack_into('<I', root, 20, 2)
    struct.pack_into('<Q', root, 24, len(bm))
    img[coff(4):coff(4) + cs] = root
    exp = []
    for lcn, name, data in orphans:
        off = coff(lcn)
        img[off:off + len(data)] = data
        exp.append({'name': name, 'offset': coff(lcn) - 0, 'size': len(data), 'sha': sha(data), 'ext': name.rsplit('.', 1)[1]})
    open(path, 'wb').write(img)
    return exp


# ------------------------------------------------------------------ bolum tablolu imajlar
def wrap_mbr(path, parts):
    """parts: [(tip, imaj_baytlari)] -> MBR + 2048 sektor bosluk + bolumler"""
    out = bytearray(2048 * 512)
    lba = 2048
    table = []
    for t, data in parts:
        pad = (-len(data)) % 512
        data = data + bytes(pad)
        table.append((t, lba, len(data) // 512, len(out)))
        out += data
        out += bytes((-len(out)) % (1024 * 1024))
        lba = len(out) // 512
    mbr = bytearray(512)
    for i, (t, l, n, _) in enumerate(table):
        mbr[446 + 16 * i + 4] = t
        struct.pack_into('<II', mbr, 446 + 16 * i + 8, l, n)
    mbr[510:512] = b'\x55\xaa'
    out[0:512] = mbr
    open(path, 'wb').write(out)


def wrap_gpt(path, data):
    out = bytearray(34 * 512)
    start_lba = 2048
    out += bytes(start_lba * 512 - len(out))
    out += data
    mbr = bytearray(512)
    mbr[446 + 4] = 0xEE
    struct.pack_into('<II', mbr, 446 + 8, 1, 0xFFFFFFFF)
    mbr[510:512] = b'\x55\xaa'
    out[0:512] = mbr
    hdr = bytearray(512)
    hdr[0:8] = b'EFI PART'
    struct.pack_into('<IIII', hdr, 8, 0x00010000, 92, 0, 0)
    struct.pack_into('<QQ', hdr, 24, 1, 0)
    struct.pack_into('<QQ', hdr, 40, 34, 0)
    struct.pack_into('<Q', hdr, 72, 2)
    struct.pack_into('<III', hdr, 80, 128, 128, 0)
    ent = bytearray(128)
    ent[0:16] = bytes([0xA2, 0xA0, 0xD0, 0xEB, 0xE5, 0xB9, 0x33, 0x44, 0x87, 0xC0, 0x68, 0xB6, 0xB7, 0x26, 0x99, 0xC7])
    ent[16:32] = bytes(range(1, 17))
    struct.pack_into('<QQ', ent, 32, start_lba, start_lba + len(data) // 512 - 1)
    out[512:1024] = hdr
    out[1024:1024 + 128] = ent
    open(path, 'wb').write(out)



# ------------------------------------------------------------------ FAT/exFAT klasorleri (silinmis girdiler)
def dos_stamp(y, mo, d, hh, mi, ss):
    return ((y - 1980) << 9) | (mo << 5) | d, (hh << 11) | (mi << 5) | (ss // 2)


def lfn_sum(sfn11):
    s = 0
    for c in sfn11:
        s = (((s & 1) << 7) + (s >> 1) + c) & 0xFF
    return s


def sfn11(name, ext=''):
    return (name.upper().ljust(8)[:8] + ext.upper().ljust(3)[:3]).encode('cp437')


def lfn_entries(longname, name11):
    """uzun ad girdileri, diskteki sirayla (son parca once)"""
    units = list(struct.unpack('<%dH' % (len(longname.encode('utf-16-le')) // 2), longname.encode('utf-16-le')))
    if len(units) % 13 != 0:
        units.append(0)
        while len(units) % 13 != 0:
            units.append(0xFFFF)
    n = len(units) // 13
    cs = lfn_sum(name11)
    offs = [1, 3, 5, 7, 9, 14, 16, 18, 20, 22, 24, 28, 30]
    out = []
    for k in range(1, n + 1):
        e = bytearray(32)
        e[0] = k | (0x40 if k == n else 0)
        e[11] = 0x0F
        e[13] = cs
        for i, o in enumerate(offs):
            struct.pack_into('<H', e, o, units[13 * (k - 1) + i])
        out.append(bytes(e))
    out.reverse()
    return out


def sfn_entry(name11, attr, cl, size, stamp, case_flags=0):
    e = bytearray(32)
    e[0:11] = name11
    e[11] = attr
    e[12] = case_flags
    date, tm = stamp
    struct.pack_into('<HHH', e, 14, tm, date, date)
    struct.pack_into('<H', e, 20, cl >> 16)
    struct.pack_into('<HH', e, 22, tm, date)
    struct.pack_into('<H', e, 26, cl & 0xFFFF)
    struct.pack_into('<I', e, 28, size)
    return bytes(e)


def mark_deleted(entries):
    out = []
    for e in entries:
        b = bytearray(e)
        b[0] = 0xE5
        out.append(bytes(b))
    return out


class FatFs:
    """FAT32 imaji (512 bayt sektor, 4 KiB kume, 1024 kume); dizinler ve dosyalar elle yerlestirilir"""
    def __init__(self, clusters=1024):
        self.spc, self.rsv, self.nfat, self.bps = 8, 32, 2, 512
        self.clusters = clusters
        self.fatsz = ((clusters + 2) * 4 + 511) // 512
        self.total = self.rsv + self.nfat * self.fatsz + clusters * self.spc
        self.img = bytearray(self.total * self.bps)
        self.fat = bytearray(self.fatsz * 512)
        struct.pack_into('<I', self.fat, 0, 0x0FFFFFF8)
        struct.pack_into('<I', self.fat, 4, 0x0FFFFFFF)
        self.data0 = (self.rsv + self.nfat * self.fatsz) * 512
        self.cs = self.spc * 512

    def coff(self, c):
        return self.data0 + (c - 2) * self.cs

    def chain(self, lst):
        for i, c in enumerate(lst):
            struct.pack_into('<I', self.fat, 4 * c, lst[i + 1] if i + 1 < len(lst) else 0x0FFFFFFF)

    def put(self, cl, data):
        o = self.coff(cl)
        self.img[o:o + len(data)] = data

    def finish(self, path=None):
        b = bytearray(512)
        b[0:3] = b'\xeb\x58\x90'
        b[3:11] = b'MSDOS5.0'
        struct.pack_into('<HBHB', b, 11, self.bps, self.spc, self.rsv, self.nfat)
        b[21] = 0xF8
        struct.pack_into('<I', b, 32, self.total)
        struct.pack_into('<I', b, 36, self.fatsz)
        struct.pack_into('<I', b, 44, 2)
        struct.pack_into('<HH', b, 48, 1, 6)
        b[66] = 0x29
        b[82:90] = b'FAT32   '
        b[510:512] = b'\x55\xaa'
        self.img[0:512] = b
        for k in range(self.nfat):
            o = (self.rsv + k * self.fatsz) * 512
            self.img[o:o + len(self.fat)] = self.fat
        if path:
            open(path, 'wb').write(self.img)
        return bytes(self.img)


def build_fat32_dirs(path):
    """silinmis dosya/klasorler, uzun adlar, kume siniri asan uzun ad, kismen ezilmis dosyalar"""
    F = FatFs()
    st1 = dos_stamp(2023, 7, 14, 9, 30, 44)
    st2 = dos_stamp(2022, 12, 31, 23, 59, 58)
    exp = {'deleted': [], 'orphans': [], 'stamps': {'a': [2023, 7, 14, 9, 30, 44], 'b': [2022, 12, 31, 23, 59, 58]}}

    def deleted(name, path_, size, chance, cl, data, key=None, stamp='a', **extra):
        d = {'key': key or name, 'name': name, 'path': path_, 'size': size, 'chance': chance, 'offset': F.coff(cl), 'stamp': stamp}
        if data is not None and chance >= 85 or (data is not None and chance == 100):
            d['sha'] = sha(data)
        d.update(extra)
        exp['deleted'].append(d)

    # ---- kullanimdaki dosyalar
    F.chain([10, 11])
    keep = b'Bu dosya silinmedi.\n' * 300
    F.put(10, keep[:8192])
    F.chain([12])
    F.put(12, b'tut')
    F.chain([51])
    F.put(51, rnd(201, 4096))              # KULLAN.BIN: KISMI.BIN'in ikinci kumesini kapliyor
    F.chain([70, 71])
    F.put(70, rnd(202, 8192))              # YENI.DAT: EZILDI.DAT'in kumelerini kapliyor

    # ---- silinmis dosyalarin verileri (FAT girdileri sifir = bos)
    docx = make_zip('docx')
    F.put(20, docx)
    deleted('Toplantı Notları 2024 Nisan.docx', 'BELGELER', len(docx), 100, 20, docx)
    pdf = make_pdf(203, 9000)
    F.put(30, pdf)
    deleted('_APOR.PDF', 'BELGELER', len(pdf), 85, 30, pdf, key='rapor-pdf')
    jpg1 = make_jpeg(204, 6000)
    F.put(40, jpg1)
    deleted('Eski Fotoğraf.jpg', 'BELGELER\\_SKI', len(jpg1), 85, 40, jpg1)
    kismi = rnd(205, 3 * 4096 - 100)
    F.put(50, kismi[:4096])
    F.put(52, kismi[8192:])
    deleted('_ISMI.BIN', 'BELGELER\\_SKI', len(kismi), 66, 50, None, note='kısmen')
    derin = b'derin klasorde silinmis dosya\n' * 10
    F.put(97 + 0, derin)
    deleted('_ERIN.TXT', 'BELGELER\\_SKI\\_LT', len(derin), 100, 97, derin)
    readme = b'hello readme\n'
    F.put(60, readme)
    deleted('_eadme.txt', '', len(readme), 100, 60, readme, stamp='b')
    deleted('_ZILDI.DAT', '', 8192 - 7, 0, 70, None, note='üzerine yazılmış')
    F.put(80, bytes(6000))
    deleted('_OSLUK.JPG', '', 6000, 5, 80, None, note='sıfırlarla')
    F.put(85, rnd(206, 3000))
    deleted('_AHTE.JPG', '', 3000, 20, 85, None, note='beklenen biçimde değil')
    jpg2 = make_jpeg(207, 6000)
    F.put(90, jpg2)
    deleted('_OTO.JPG', '', len(jpg2), 85, 90, jpg2)
    F.put(96, rnd(208, 4096))              # SILIK klasorunun "kumesi" baska veriyle ezilmis

    # ---- ESKI (silinmis klasor, kume 4): "." ve ".." + dosyalar + ic ice silinmis klasor ALT (kume 97 degil, 98)
    # derin.txt verisi 97. kumede; ALT klasoru 98. kumede
    eski = bytearray(F.cs)
    ents = []
    ents.append(sfn_entry(b'.          ', 0x10, 4, 0, st1))
    ents.append(sfn_entry(b'..         ', 0x10, 3, 0, st1))
    n1 = sfn11('ESKIFO~1', 'JPG')
    ents += mark_deleted(lfn_entries('Eski Fotoğraf.jpg', n1)) + mark_deleted([sfn_entry(n1, 0x20, 40, len(jpg1), st1)])
    ents += mark_deleted([sfn_entry(sfn11('KISMI', 'BIN'), 0x20, 50, len(kismi), st1)])
    ents += mark_deleted([sfn_entry(sfn11('ALT'), 0x10, 98, 0, st1)])
    for i, e in enumerate(ents):
        eski[i * 32:i * 32 + 32] = e
    F.put(4, bytes(eski))
    alt = bytearray(F.cs)
    ents = [sfn_entry(b'.          ', 0x10, 98, 0, st1), sfn_entry(b'..         ', 0x10, 4, 0, st1)]
    ents += mark_deleted([sfn_entry(sfn11('DERIN', 'TXT'), 0x20, 97, len(derin), st1)])
    for i, e in enumerate(ents):
        alt[i * 32:i * 32 + 32] = e
    F.put(98, bytes(alt))

    # ---- BELGELER (kume 3 -> 5): kume sinirini asan uzun ad
    bel = []
    bel.append(sfn_entry(b'.          ', 0x10, 3, 0, st1))
    bel.append(sfn_entry(b'..         ', 0x10, 0, 0, st1))
    for i in range(124):
        bel.append(sfn_entry(sfn11('F%04d' % i, 'TXT'), 0x20, 0, 0, st1))
    n2 = sfn11('TOPLAN~1', 'DOC')
    lf = lfn_entries('Toplantı Notları 2024 Nisan.docx', n2)
    assert len(lf) == 3
    bel += mark_deleted(lf) + mark_deleted([sfn_entry(n2, 0x20, 20, len(docx), st1)])
    assert len(bel) == 130
    bel += mark_deleted([sfn_entry(sfn11('RAPOR', 'PDF'), 0x20, 30, len(pdf), st1)])
    bel += mark_deleted([sfn_entry(sfn11('ESKI'), 0x10, 4, 0, st1)])
    bel.append(sfn_entry(sfn11('TUT', 'TXT'), 0x20, 12, 3, st1))
    bel.append(sfn_entry(sfn11('SILIK'), 0x10, 96, 0, st1))       # canli girdi: silinmis degil, hedef ezilmis; listelenmez
    buf = bytearray(2 * F.cs)
    for i, e in enumerate(bel):
        buf[i * 32:i * 32 + 32] = e
    F.chain([3, 5])
    F.put(3, bytes(buf[:F.cs]))
    F.put(5, bytes(buf[F.cs:]))

    # ---- kok dizin (kume 2)
    root = []
    root.append(sfn_entry(b'MM-DIRS    ', 0x08, 0, 0, st1))                     # birim etiketi
    root.append(sfn_entry(sfn11('KEEP', 'TXT'), 0x20, 10, len(keep[:8192]) - 0, st1))
    root.append(sfn_entry(sfn11('BELGELER'), 0x10, 3, 0, st1))
    root.append(sfn_entry(sfn11('KULLAN', 'BIN'), 0x20, 51, 4096, st1))
    root.append(sfn_entry(sfn11('YENI', 'DAT'), 0x20, 70, 8192, st1))
    root += mark_deleted([sfn_entry(b'README  TXT', 0x20, 60, len(readme), st2, case_flags=0x18)])
    root += mark_deleted([sfn_entry(sfn11('EZILDI', 'DAT'), 0x20, 70, 8192 - 7, st1)])
    root += mark_deleted([sfn_entry(sfn11('BOS', 'TXT'), 0x20, 0, 0, st1)])          # bos dosya: listelenmez
    root += mark_deleted([sfn_entry(sfn11('BOSLUK', 'JPG'), 0x20, 80, 6000, st1)])
    root += mark_deleted([sfn_entry(sfn11('SAHTE', 'JPG'), 0x20, 85, 3000, st1)])
    root += mark_deleted([sfn_entry(sfn11('FOTO', 'JPG'), 0x20, 90, len(jpg2), st1)])
    garbage = bytearray(32)
    garbage[0] = 0xE5
    garbage[1:11] = bytes([1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
    garbage[11] = 0x20
    root.append(bytes(garbage))
    # yirtik tarih: silinmis ama gecersiz tarih -> bozuk sayilir
    bad = bytearray(sfn_entry(sfn11('TARIH', 'DAT'), 0x20, 100, 100, st1))
    bad[0] = 0xE5
    struct.pack_into('<H', bad, 24, (43 << 9) | (13 << 5) | 40)
    root.append(bytes(bad))
    rb = bytearray(F.cs)
    for i, e in enumerate(root):
        rb[i * 32:i * 32 + 32] = e
    F.chain([2])
    F.put(2, bytes(rb))
    # ---- girdisiz (sahipsiz) iki dosya: imza taramasi hedefi
    o1 = make_jpeg(209, 7000)
    F.put(120, o1)
    o2 = make_png(210, 24, 16)
    F.put(130, o2)
    exp['orphans'] = [{'name': 'orphan.jpg', 'offset': F.coff(120), 'size': len(o1), 'sha': sha(o1)},
                      {'name': 'orphan.png', 'offset': F.coff(130), 'size': len(o2), 'sha': sha(o2)}]
    exp['clusters'] = F.clusters
    data = F.finish(path)
    return exp, data


def build_fat16_dirs(path, fat12=False):
    """FAT12/16: sabit kok dizin, silinmis dosya ve silinmis alt klasor"""
    bps = 512
    if fat12:
        spc, rsv, nfat, rootent, total, fatsz = 1, 1, 2, 224, 2880, 9
    else:
        spc, rsv, nfat, rootent, total, fatsz = 4, 1, 2, 512, 32768, 32
    rootsec = rootent * 32 // 512
    img = bytearray(total * bps)
    b = bytearray(512)
    b[0:3] = b'\xeb\x3c\x90'
    b[3:11] = b'MSDOS5.0'
    struct.pack_into('<HBHB', b, 11, bps, spc, rsv, nfat)
    struct.pack_into('<H', b, 17, rootent)
    struct.pack_into('<H', b, 19, total if total < 65536 else 0)
    b[21] = 0xF0 if fat12 else 0xF8
    struct.pack_into('<H', b, 22, fatsz)
    b[54:62] = b'FAT12   ' if fat12 else b'FAT16   '
    b[510:512] = b'\x55\xaa'
    img[0:512] = b
    fat = bytearray(fatsz * 512)

    def set12(n, v):
        idx = n + (n >> 1)
        cur = fat[idx] | (fat[idx + 1] << 8)
        cur = ((cur & 0x000F) | (v << 4)) if n & 1 else ((cur & 0xF000) | v)
        fat[idx] = cur & 0xFF
        fat[idx + 1] = cur >> 8

    def setfat(n, v):
        if fat12:
            set12(n, v & 0xFFF)
        else:
            struct.pack_into('<H', fat, 2 * n, v & 0xFFFF)
    end = 0xFFF if fat12 else 0xFFFF
    if fat12:
        set12(0, 0xFF0)
        set12(1, 0xFFF)
    else:
        struct.pack_into('<HH', fat, 0, 0xFFF8, 0xFFFF)
    data0 = (rsv + nfat * fatsz + rootsec) * 512
    cs = spc * 512
    root0 = (rsv + nfat * fatsz) * 512

    def coff(c):
        return data0 + (c - 2) * cs
    st = dos_stamp(2021, 5, 6, 7, 8, 10)
    exp = {'deleted': [], 'stamp': [2021, 5, 6, 7, 8, 10]}
    # kullanimdaki dosya: kume 2,3 (zincir)
    setfat(2, 3)
    setfat(3, end)
    img[coff(2):coff(2) + 5] = b'canli'
    # silinmis: kok dizinde NOTLAR.TXT (3 kume, tek tek: 5,6,7 cift/tek kume karisimi), alt klasor DOKUMAN (kume 10, silinmis) icinde ICERIK.DOC (kume 13)
    notlar = (b'notlar satiri\n' * 400)[:min(3 * cs - 50, 5000)]
    nclus = (len(notlar) + cs - 1) // cs
    img[coff(5):coff(5) + len(notlar)] = notlar
    ic = make_ole()
    img[coff(13):coff(13) + len(ic)] = ic
    sub = bytearray(cs)
    ents = [sfn_entry(b'.          ', 0x10, 10, 0, st), sfn_entry(b'..         ', 0x10, 0, 0, st)]
    ents += mark_deleted([sfn_entry(sfn11('ICERIK', 'DOC'), 0x20, 13, len(ic), st)])
    for i, e in enumerate(ents):
        sub[i * 32:i * 32 + 32] = e
    img[coff(10):coff(10) + cs] = sub
    for i in range(3):
        pass
    root = [sfn_entry(sfn11('CANLI', 'TXT'), 0x20, 2, 5, st)]
    root += mark_deleted([sfn_entry(sfn11('NOTLAR', 'TXT'), 0x20, 5, len(notlar), st)])
    root += mark_deleted([sfn_entry(sfn11('DOKUMAN'), 0x10, 10, 0, st)])
    gif = make_gif(211)
    img[coff(9):coff(9) + len(gif)] = gif
    root += mark_deleted([sfn_entry(sfn11('TEK', 'GIF'), 0x20, 9, len(gif), st)])
    rb = bytearray(rootent * 32)
    for i, e in enumerate(root):
        rb[i * 32:i * 32 + 32] = e
    img[root0:root0 + len(rb)] = rb
    for k in range(nfat):
        img[(rsv + k * fatsz) * 512:(rsv + (k + 1) * fatsz) * 512] = fat
    exp['deleted'] = [
        {'name': '_OTLAR.TXT', 'path': '', 'size': len(notlar), 'chance': 100 if nclus == 1 else 85, 'offset': coff(5), 'sha': sha(notlar)},
        {'name': '_EK.GIF', 'path': '', 'size': len(gif), 'chance': 100, 'offset': coff(9), 'sha': sha(gif)},
        {'name': '_CERIK.DOC', 'path': '_OKUMAN', 'size': len(ic), 'chance': 100 if len(ic) <= cs else 85, 'offset': coff(13), 'sha': sha(ic)},
    ]
    open(path, 'wb').write(img)
    return exp


# ------------------------------------------------------------------ exFAT klasorleri
def ex_checksum(entries):
    s = 0
    for ei, e in enumerate(entries):
        for i in range(32):
            if ei == 0 and i in (2, 3):
                continue
            s = ((((s << 15) | (s >> 1)) & 0xFFFF) + e[i]) & 0xFFFF
    return s


def ex_set(name, attr, cl, dlen, nofat, stamp, deleted=False, vlen=None, utc=0x00, corrupt_name=False):
    units = name.encode('utf-16-le')
    nunits = len(units) // 2
    nent = (nunits + 14) // 15
    e0 = bytearray(32)
    e0[0] = 0x85
    e0[1] = 1 + nent
    struct.pack_into('<H', e0, 4, attr)
    date, tm = stamp
    ts = (date << 16) | tm
    struct.pack_into('<III', e0, 8, ts, ts, ts)
    e0[22] = utc
    e0[23] = utc
    e0[24] = utc
    e1 = bytearray(32)
    e1[0] = 0xC0
    e1[1] = 0x03 if nofat else 0x01
    e1[3] = nunits
    struct.pack_into('<Q', e1, 8, dlen if vlen is None else vlen)
    struct.pack_into('<I', e1, 20, cl)
    struct.pack_into('<Q', e1, 24, dlen)
    ents = [e0, e1]
    for k in range(nent):
        en = bytearray(32)
        en[0] = 0xC1
        chunk = units[k * 30:(k + 1) * 30]
        en[2:2 + len(chunk)] = chunk
        ents.append(en)
    struct.pack_into('<H', e0, 2, ex_checksum(ents))
    if corrupt_name:
        ents[2][6] ^= 0x55
    if deleted:
        for e in ents:
            e[0] &= 0x7F
    return b''.join(bytes(e) for e in ents)


def build_exfat_dirs(path):
    bps, cs = 512, 4096
    clusters = 1024
    fat_off, fat_len, heap_off = 24, 9, 64
    total = heap_off + clusters * 8
    img = bytearray(total * bps)
    b = bytearray(512)
    b[0:3] = b'\xeb\x76\x90'
    b[3:11] = b'EXFAT   '
    struct.pack_into('<Q', b, 72, total)
    struct.pack_into('<IIII', b, 80, fat_off, fat_len, heap_off, clusters)
    struct.pack_into('<I', b, 96, 4)
    struct.pack_into('<I', b, 100, 0xCAFEBABE)
    struct.pack_into('<H', b, 104, 0x0100)
    b[108] = 9
    b[109] = 3
    b[110] = 1
    b[510:512] = b'\x55\xaa'
    img[0:512] = b
    fat = bytearray(fat_len * 512)
    struct.pack_into('<III', fat, 0, 0xFFFFFFF8, 0xFFFFFFFF, 0xFFFFFFFF)   # 0, 1, 2 (bitmap)
    struct.pack_into('<I', fat, 4 * 4, 0xFFFFFFFF)                          # kok dizin: kume 4
    img[fat_off * 512:fat_off * 512 + len(fat)] = fat

    def coff(c):
        return heap_off * 512 + (c - 2) * cs
    used = {2, 4, 6, 7, 61}
    stamp = dos_stamp(2024, 3, 1, 12, 0, 0)
    stamp2 = dos_stamp(2020, 1, 2, 3, 4, 6)
    exp = {'deleted': []}

    def d(name, path_, size, chance, cl, data, **extra):
        e = {'name': name, 'path': path_, 'size': size, 'chance': chance, 'offset': coff(cl)}
        if data is not None:
            e['sha'] = sha(data)
        e.update(extra)
        exp['deleted'].append(e)

    root = bytearray(cs)
    pos = 0

    def add(blob):
        nonlocal pos
        root[pos:pos + len(blob)] = blob
        pos += len(blob)
    bmentry = bytearray(32)
    bmentry[0] = 0x81
    struct.pack_into('<I', bmentry, 20, 2)
    struct.pack_into('<Q', bmentry, 24, (clusters + 7) // 8)
    add(bytes(bmentry))
    lbl = bytearray(32)
    lbl[0] = 0x83
    lbl[1] = 2
    lbl[2:6] = 'MM'.encode('utf-16-le')
    add(bytes(lbl))
    # kullanimdaki dosya ve klasor
    live = b'canli dosya\n' * 5
    img[coff(6):coff(6) + len(live)] = live
    add(ex_set('canli.txt', 0x20, 6, len(live), True, stamp))
    add(ex_set('Klasör', 0x10, 7, cs, True, stamp))
    # Klasor (kume 7): silinmis dosya ve silinmis alt klasor Alt (kume 8, 1 kume)
    kl = bytearray(cs)
    kpos = 0
    ic = b'iceride silinmis dosya\n' * 8
    img[coff(20):coff(20) + len(ic)] = ic
    blob = ex_set('içeride.txt', 0x20, 20, len(ic), True, stamp, deleted=True)
    kl[kpos:kpos + len(blob)] = blob
    kpos += len(blob)
    blob = ex_set('Alt', 0x10, 8, cs, True, stamp, deleted=True)
    kl[kpos:kpos + len(blob)] = blob
    img[coff(7):coff(7) + cs] = kl
    d('içeride.txt', 'Klasör', len(ic), 100, 20, ic)
    alt = bytearray(cs)
    pdf = make_pdf(301, 9000)
    img[coff(30):coff(30) + len(pdf)] = pdf
    blob = ex_set('derin.pdf', 0x20, 30, len(pdf), True, stamp, deleted=True)
    alt[0:len(blob)] = blob
    img[coff(8):coff(8) + cs] = alt
    d('derin.pdf', 'Klasör\\Alt', len(pdf), 100, 30, pdf)
    # kokte silinmis dosyalar
    jpg = make_jpeg(302, 6000)
    img[coff(40):coff(40) + len(jpg)] = jpg
    add(ex_set('Silinmiş Fotoğraf.jpg', 0x20, 40, len(jpg), True, stamp, deleted=True))
    d('Silinmiş Fotoğraf.jpg', '', len(jpg), 100, 40, jpg)
    big = rnd(303, 6000)
    img[coff(50):coff(50) + len(big)] = big
    add(ex_set('buyuk.bin', 0x20, 50, len(big), False, stamp, deleted=True))
    d('buyuk.bin', '', len(big), 85, 50, big)
    kismi = rnd(304, 3 * 4096 - 10)
    img[coff(60):coff(60) + 4096] = kismi[:4096]
    img[coff(61):coff(61) + 4096] = rnd(305, 4096)
    img[coff(62):coff(62) + 4096 - 10] = kismi[8192:]
    add(ex_set('kismi.dat', 0x20, 60, len(kismi), True, stamp, deleted=True))
    d('kismi.dat', '', len(kismi), 66, 60, None, note='kısmen')
    zt = b'zaman damgasi denemesi\n' * 4
    img[coff(70):coff(70) + len(zt)] = zt
    add(ex_set('zaman.txt', 0x20, 70, len(zt), True, stamp, deleted=True, utc=0x8C))
    d('zaman.txt', '', len(zt), 100, 70, zt, utc=True)
    add(ex_set('bozuk_toplam.txt', 0x20, 75, 10, True, stamp, deleted=True, corrupt_name=True))
    add(ex_set('sifir.bin', 0x20, 76, 4096, True, stamp, deleted=True, vlen=0))
    add(ex_set('eski_tarih.txt', 0x20, 77, 20, True, stamp2, deleted=True))
    img[coff(77):coff(77) + 20] = b'eski tarihli dosya.\n'
    d('eski_tarih.txt', '', 20, 100, 77, b'eski tarihli dosya.\n', stamp2=True)
    img[coff(4):coff(4) + cs] = root
    # sahipsiz dosyalar
    o1 = make_jpeg(306, 7000)
    img[coff(100):coff(100) + len(o1)] = o1
    o2 = make_png(307, 24, 16)
    img[coff(110):coff(110) + len(o2)] = o2
    exp['orphans'] = [{'name': 'orphan.jpg', 'offset': coff(100), 'size': len(o1), 'sha': sha(o1)},
                      {'name': 'orphan.png', 'offset': coff(110), 'size': len(o2), 'sha': sha(o2)}]
    # tahsis haritasi (kume 2)
    bm = bytearray((clusters + 7) // 8)
    for c in used:
        i = c - 2
        bm[i >> 3] |= 1 << (i & 7)
    img[coff(2):coff(2) + len(bm)] = bm
    open(path, 'wb').write(img)
    return exp, bytes(img)


# ------------------------------------------------------------------ ext2/3/4
def build_ext(path, bs=4096, flavor='ext4', size=8 * 1024 * 1024):
    blocks = size // bs
    fdb = 1 if bs == 1024 else 0
    bpg = 8 * bs if bs > 1024 else 8192
    img = bytearray(size)
    sb = bytearray(1024)
    struct.pack_into('<II', sb, 0, 128, blocks)
    struct.pack_into('<I', sb, 20, fdb)
    lg = {1024: 0, 2048: 1, 4096: 2}[bs]
    struct.pack_into('<II', sb, 24, lg, lg)
    struct.pack_into('<II', sb, 32, bpg, bpg)
    struct.pack_into('<I', sb, 40, 128)
    struct.pack_into('<H', sb, 56, 0xEF53)
    struct.pack_into('<H', sb, 58, 1)
    struct.pack_into('<I', sb, 76, 1)
    struct.pack_into('<H', sb, 88, 256)
    compat, incompat, rocompat = 0, 0x2, 0x3
    if flavor == 'ext3':
        compat = 0x4
    if flavor == 'ext4':
        compat, incompat, rocompat = 0x4, 0x2 | 0x40 | 0x200, 0x1 | 0x2 | 0x8 | 0x20
    if flavor == 'ext4ro':        # yalniz salt-okunur uyumluluk bayragi (dir_nlink) ext4 oldugunu gosterir
        compat, incompat, rocompat = 0x4, 0x2, 0x1 | 0x2 | 0x20
    if flavor == 'ext4hi':        # yalniz yuksek bit (casefold) ext4 oldugunu gosterir
        compat, incompat, rocompat = 0x4, 0x2 | 0x20000, 0x1 | 0x2
    struct.pack_into('<III', sb, 92, compat, incompat, rocompat)
    img[1024:2048] = sb
    gd_block = fdb + 1
    bitmap_block = gd_block + 1
    inode_bitmap_block = bitmap_block + 1
    inode_table = inode_bitmap_block + 1
    gd = bytearray(32)
    struct.pack_into('<III', gd, 0, bitmap_block, inode_bitmap_block, inode_table)
    img[gd_block * bs:gd_block * bs + 32] = gd
    used = set(range(0, 16 if bs >= 4096 else 40))        # ust veri, GDT, haritalar, i-dugum tablosu
    live = make_jpeg(401, 5000)
    live_blk = 100
    for k in range((len(live) + bs - 1) // bs):
        used.add(live_blk + k)
    img[live_blk * bs:live_blk * bs + len(live)] = live
    items = []

    def orphan(blk, name, data):
        img[blk * bs:blk * bs + len(data)] = data
        items.append({'name': name, 'offset': blk * bs, 'size': len(data), 'sha': sha(data), 'ext': name.rsplit('.', 1)[1]})
    orphan(300, 'o1.jpg', make_jpeg(402, 7000))
    orphan(320, 'o2.png', make_png(403, 24, 16))
    orphan(340, 'o3.pdf', make_pdf(404, 6000))
    orphan(360, 'o4.docx', make_zip('docx'))
    orphan(380, 'o5.gif', make_gif(405))
    bm = bytearray(bs)
    for blk in used:
        i = blk - fdb
        if i >= 0:
            bm[i >> 3] |= 1 << (i & 7)
    for i in range(blocks - fdb, bs * 8):
        bm[i >> 3] |= 1 << (i & 7)
    img[bitmap_block * bs:bitmap_block * bs + bs] = bm
    open(path, 'wb').write(img)
    return {'items': items, 'bs': bs, 'live_offset': live_blk * bs, 'blocks': blocks}, bytes(img)


# ------------------------------------------------------------------ taninmayan biçimler (ham tarama)
SNIFFS = {
    'btrfs': (65600, b'_BHRfS_M'), 'xfs': (0, b'XFSB'), 'apfs': (32, b'NXSB'), 'hfsplus': (1024, b'H+\x00\x04'),
    'f2fs': (1024, struct.pack('<I', 0xF2F52010)), 'lvm': (512, b'LABELONE'), 'refs': (3, b'ReFS\x00'),
}


def build_sniff(path, key):
    img = bytearray(512 * 1024)
    off, sig = SNIFFS[key]
    img[off:off + len(sig)] = sig
    jpg = make_jpeg(501, 8000)
    png = make_png(502, 20, 12)
    img[131072:131072 + len(jpg)] = jpg
    img[163840:163840 + len(png)] = png
    open(path, 'wb').write(img)
    return {'items': [{'offset': 131072, 'size': len(jpg), 'sha': sha(jpg)}, {'offset': 163840, 'size': len(png), 'sha': sha(png)}]}


def build_rawimg(path):
    img = bytearray(1024 * 1024)
    jpg = make_jpeg(511, 9000)
    png = make_png(512, 20, 12)
    pdf = make_pdf(513, 7000)
    img[512 * 301:512 * 301 + len(jpg)] = jpg
    img[512 * 700:512 * 700 + len(png)] = png
    img[512 * 1200:512 * 1200 + len(pdf)] = pdf
    open(path, 'wb').write(img)
    return {'items': [{'offset': 512 * 301, 'size': len(jpg), 'sha': sha(jpg)}, {'offset': 512 * 700, 'size': len(png), 'sha': sha(png)},
                      {'offset': 512 * 1200, 'size': len(pdf), 'sha': sha(pdf)}]}


def wrap_mbr_ext(path, prim, ext_logicals):
    """prim: [(tip, bayt)]; ext_logicals: [(tip, bayt)] genisletilmis bolum (0x05) icindeki mantiksal bolumler. Bolumler 1 MiB hizali."""
    MB = 1024 * 1024
    out = bytearray(1 * MB)
    table = []
    for t, data in prim:
        start = len(out)
        pad = (-len(data)) % MB
        out += data + bytes(pad)
        table.append((t, start // 512, (len(data) + pad) // 512))
    ext_start = len(out)
    ext = bytearray()
    ebr_pos = 0
    for i, (t, data) in enumerate(ext_logicals):
        ebr = bytearray(512)
        pad = (-len(data)) % MB
        part_sectors = (len(data) + pad) // 512
        # mantiksal bolum EBR'den 2048 sektor sonra
        ebr[446 + 4] = t
        struct.pack_into('<II', ebr, 446 + 8, 2048, part_sectors)
        if i + 1 < len(ext_logicals):
            nxt = ebr_pos + 2048 + part_sectors
            ebr[446 + 16 + 4] = 0x05
            struct.pack_into('<II', ebr, 446 + 16 + 8, nxt, 2048 + len(ext_logicals[i + 1][1]) // 512)
        ebr[510:512] = b'\x55\xaa'
        base = ebr_pos * 512
        need = base + 512 + 2048 * 512 - 512 + len(data) + pad
        if len(ext) < need:
            ext += bytes(need - len(ext))
        ext[base:base + 512] = ebr
        ext[base + 2048 * 512:base + 2048 * 512 + len(data)] = data
        ebr_pos = ebr_pos + 2048 + part_sectors
    out += ext
    table.append((0x05, ext_start // 512, len(ext) // 512))
    mbr = bytearray(512)
    for i, (t, l, n) in enumerate(table):
        mbr[446 + 16 * i + 4] = t
        struct.pack_into('<II', mbr, 446 + 16 * i + 8, l, n)
    mbr[510:512] = b'\x55\xaa'
    out[0:512] = mbr
    open(path, 'wb').write(out)


GUID_ESP = bytes([0x28, 0x73, 0x2A, 0xC1, 0x1F, 0xF8, 0xD2, 0x11, 0xBA, 0x4B, 0x00, 0xA0, 0xC9, 0x3E, 0xC9, 0x3B])
GUID_MSR = bytes([0x16, 0xE3, 0xC9, 0xE3, 0x5C, 0x0B, 0xB8, 0x4D, 0x81, 0x7D, 0xF9, 0x2D, 0xF0, 0x02, 0x15, 0xAE])
GUID_BASIC = bytes([0xA2, 0xA0, 0xD0, 0xEB, 0xE5, 0xB9, 0x33, 0x44, 0x87, 0xC0, 0x68, 0xB6, 0xB7, 0x26, 0x99, 0xC7])
GUID_LINUX = bytes([0xAF, 0x3D, 0xC6, 0x0F, 0x83, 0x84, 0x72, 0x47, 0x8E, 0x79, 0x3D, 0x69, 0xD8, 0x47, 0x7D, 0xE4])


def wrap_gpt_multi(path, parts):
    """parts: [(tur_guid, bayt)] -> koruyucu MBR + GPT + hizali bolumler"""
    MB = 1024 * 1024
    out = bytearray(1 * MB)
    ents = []
    for g, data in parts:
        start = len(out) // 512
        pad = (-len(data)) % MB
        out += data + bytes(pad)
        ents.append((g, start, start + (len(data) + pad) // 512 - 1))
    mbr = bytearray(512)
    mbr[446 + 4] = 0xEE
    struct.pack_into('<II', mbr, 446 + 8, 1, 0xFFFFFFFF)
    mbr[510:512] = b'\x55\xaa'
    out[0:512] = mbr
    hdr = bytearray(512)
    hdr[0:8] = b'EFI PART'
    struct.pack_into('<IIII', hdr, 8, 0x00010000, 92, 0, 0)
    struct.pack_into('<QQ', hdr, 24, 1, len(out) // 512 - 1)
    struct.pack_into('<QQ', hdr, 40, 34, len(out) // 512 - 34)
    struct.pack_into('<Q', hdr, 72, 2)
    struct.pack_into('<III', hdr, 80, 128, 128, 0)
    tbl = bytearray(128 * 128)
    for i, (g, a, z) in enumerate(ents):
        e = bytearray(128)
        e[0:16] = g
        e[16:32] = bytes(range(1 + i, 17 + i))
        struct.pack_into('<QQ', e, 32, a, z)
        tbl[i * 128:(i + 1) * 128] = e
    out[512:1024] = hdr
    out[1024:1024 + len(tbl)] = tbl
    open(path, 'wb').write(out)


def make_gpt_valid(path):
    """Gecerli sagliama toplamli, yedek tablolu GPT imaji (64 MiB, 3 bolum, aralarinda ayrilmamis alan). Silme motoru testleri icin.
    Bolumler 0xAA / 0xBB / 0xCC ile, ayrilmamis bolgeler 0xDD ile doldurulur."""
    MB = 1024 * 1024
    size = 64 * MB
    last = size // 512 - 1
    img = bytearray(b'\xdd' * size)
    parts = [(GUID_ESP, 2048, 2048 + 8 * MB // 512 - 1, 0xAA), (GUID_BASIC, 20 * MB // 512, 20 * MB // 512 + 10 * MB // 512 - 1, 0xBB),
             (GUID_LINUX, 50 * MB // 512, 50 * MB // 512 + 8 * MB // 512 - 1, 0xCC)]
    for g, a, z, fill in parts:
        img[a * 512:(z + 1) * 512] = bytes([fill]) * ((z + 1 - a) * 512)
    tbl = bytearray(128 * 128)
    for i, (g, a, z, fill) in enumerate(parts):
        e = bytearray(128)
        e[0:16] = g
        e[16:32] = bytes(range(33 + i, 49 + i))
        struct.pack_into('<QQQ', e, 32, a, z, 0)
        name = ('Bolum%d' % (i + 1)).encode('utf-16le')
        e[56:56 + len(name)] = name
        tbl[i * 128:(i + 1) * 128] = e
    tcrc = zlib.crc32(bytes(tbl)) & 0xFFFFFFFF
    # koruyucu MBR
    mbr = bytearray(512)
    mbr[446 + 4] = 0xEE
    struct.pack_into('<II', mbr, 446 + 8, 1, min(last, 0xFFFFFFFF))
    mbr[510:512] = b'\x55\xaa'
    img[0:512] = mbr

    def header(cur, other, ent_lba):
        h = bytearray(512)
        h[0:8] = b'EFI PART'
        struct.pack_into('<IIII', h, 8, 0x00010000, 92, 0, 0)
        struct.pack_into('<QQ', h, 24, cur, other)
        struct.pack_into('<QQ', h, 40, 34, last - 33)
        h[56:72] = bytes(range(101, 117))
        struct.pack_into('<Q', h, 72, ent_lba)
        struct.pack_into('<III', h, 80, 128, 128, tcrc)
        struct.pack_into('<I', h, 16, zlib.crc32(bytes(h[:92])) & 0xFFFFFFFF)
        return h

    img[512:1024] = header(1, last, 2)
    img[1024:1024 + len(tbl)] = tbl
    img[(last - 32) * 512:(last - 32) * 512 + len(tbl)] = tbl
    img[last * 512:(last + 1) * 512] = header(last, 1, last - 32)
    open(path, 'wb').write(img)


def main():
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    expect = {}
    expect['ntfs'] = build_ntfs(os.path.join(out, 'ntfs.img'))

    orph = [(100, 'f1.jpg', make_jpeg(81, 6000)), (110, 'f2.png', make_png(82, 20, 10)), (120, 'f3.pdf', make_pdf(83, 5000)),
            (130, 'f4.docx', make_zip('docx')), (140, 'f5.gif', make_gif(84))]
    expect['fat32'] = build_fat32(os.path.join(out, 'fat32.img'), orph)
    expect['exfat'] = build_exfat(os.path.join(out, 'exfat.img'), orph)
    expect['fat16'] = build_fat16(os.path.join(out, 'fat16.img'), False)
    expect['fat12'] = build_fat16(os.path.join(out, 'fat12.img'), True)

    ntfs_bytes = open(os.path.join(out, 'ntfs.img'), 'rb').read()
    fat_bytes = open(os.path.join(out, 'fat32.img'), 'rb').read()
    exfat_bytes = open(os.path.join(out, 'exfat.img'), 'rb').read()
    wrap_mbr(os.path.join(out, 'mbr2.img'), [(0x07, ntfs_bytes), (0x0C, fat_bytes)])
    wrap_gpt(os.path.join(out, 'gpt.img'), exfat_bytes)

    # ---- yeni: klasor agaclari, ext, taninmayan biçimler, bolum tablolari
    fx, fat_bytes_d = build_fat32_dirs(os.path.join(out, 'fat32d.img'))
    expect['fat32d'] = fx
    expect['fat16d'] = build_fat16_dirs(os.path.join(out, 'fat16d.img'), False)
    expect['fat12d'] = build_fat16_dirs(os.path.join(out, 'fat12d.img'), True)
    ex, exfat_bytes_d = build_exfat_dirs(os.path.join(out, 'exfatd.img'))
    expect['exfatd'] = ex
    e4, ext4_bytes = build_ext(os.path.join(out, 'ext4.img'), 4096, 'ext4')
    expect['ext4'] = e4
    e3, ext3_bytes = build_ext(os.path.join(out, 'ext3.img'), 4096, 'ext3')
    expect['ext3'] = e3
    e2, ext2_bytes = build_ext(os.path.join(out, 'ext2k.img'), 1024, 'ext2')
    expect['ext2k'] = e2
    expect['ext4ro'] = build_ext(os.path.join(out, 'ext4ro.img'), 4096, 'ext4ro')[0]
    expect['ext4hi'] = build_ext(os.path.join(out, 'ext4hi.img'), 4096, 'ext4hi')[0]
    expect['sniff'] = {}
    for k in SNIFFS:
        expect['sniff'][k] = build_sniff(os.path.join(out, 'sniff_' + k + '.img'), k)
    luks = bytearray(256 * 1024)
    luks[0:6] = b'LUKS\xba\xbe'
    open(os.path.join(out, 'luks.img'), 'wb').write(luks)
    expect['rawimg'] = build_rawimg(os.path.join(out, 'raw.img'))
    # bozuk NTFS: onyukleme sektorunde MFT konumu sifirlanmis -> ham taramaya duser
    bad = bytearray(ntfs_bytes)
    bad[48:56] = bytes(8)
    open(os.path.join(out, 'ntfs_bozuk.img'), 'wb').write(bad)
    # bozuk FAT32: kok kume numarasi gecersiz
    badf = bytearray(fat_bytes_d)
    struct.pack_into('<HBH', badf, 11, 512, 0, 32)
    open(os.path.join(out, 'fat32_bozuk.img'), 'wb').write(badf)
    sn_btrfs = open(os.path.join(out, 'sniff_btrfs.img'), 'rb').read()
    wrap_mbr_ext(os.path.join(out, 'mbr_ext.img'), [(0x0C, fat_bytes_d), (0x83, ext4_bytes)], [(0x07, exfat_bytes_d), (0x83, sn_btrfs)])
    make_gpt_valid(os.path.join(out, 'gpt_valid.img'))
    wrap_gpt_multi(os.path.join(out, 'gpt_multi.img'), [(GUID_ESP, fat_bytes_d), (GUID_MSR, bytes(1024 * 1024)), (GUID_BASIC, ntfs_bytes), (GUID_LINUX, ext4_bytes)])

    open(os.path.join(out, 'blank.img'), 'wb').write(bytes(1024 * 1024))
    bl = bytearray(1024 * 1024)
    bl[3:11] = b'-FVE-FS-'
    bl[510:512] = b'\x55\xaa'
    open(os.path.join(out, 'bitlocker.img'), 'wb').write(bl)
    open(os.path.join(out, 'ntfs_trunc.img'), 'wb').write(ntfs_bytes[:len(ntfs_bytes) // 2])
    json.dump(expect, open(os.path.join(out, 'expect.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    print('imajlar hazir:', out)


if __name__ == '__main__':
    main()
