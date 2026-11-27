# -*- coding: utf-8 -*-
"""Multimizer derleyicisi.

  base.ps1                 : 8.0.0 yayininin ASCII betigi (degistirilmez; yamalar uzerine eklenir)
  mods/*.ps1               : yeni moduller (UTF-8; tr2ascii ile ASCII'ye cevrilir)
  patches/pNN_*.py         : apply(b) islevi olan yamalar (alfabetik sirayla uygulanir)
  static/                  : Baslat.bat, Tani.ps1, Acilis.ps1 (src/Acilis.tpl.ps1 + baslatma_dil.tsv'den uretilir), Eklenti/, veri/, araclar/ (olduklari gibi kopyalanir)

Iki yerlesim vardir:
  gelistirme  : build/ yan yana out/ ve static/ ile; cikti out/ altina yazilir.
  depo        : kaynak/ deponun icindedir (dizin adi "kaynak"); yan dosyalar (Baslat.bat, Tani.ps1, araclar/, veri/, Eklenti/)
                deponun kokunde durur ve Multimizer.ps1 ile uretilen eklentiler (Kurtarma, DiskSilme) yerinde yenilenir.
Eklenti ve veri dosyalarinin SHA-256 ozetleri betigin icindeki $script:PackHash tablosuna yazilir. Cikti belirlenimlidir:
ayni kaynaktan her seferinde ayni bayt dizisi cikar.
"""
import glob
import hashlib
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
from tr2ascii import convert, xaml as xaml_escape  # noqa: E402

DEPO = os.path.basename(HERE) == 'kaynak'
OUT = ROOT if DEPO else os.path.join(ROOT, 'out')
VERSION = '10.1.0'

MODULE_TITLES = {}  # modul govdesinin ilk satirlari kendi basligini tasir; burada yalnizca ASCII baslik tutulur


def marker(stem, title=None):
    t = title or MODULE_TITLES.get(stem) or stem
    return '# ---------------- ' + t + ' ----------------'


CORE_END_RE = re.compile(r'^\}\n# =+\n#  Cekirdegi yukle:', re.M)


class Build:
    def __init__(self, text):
        self.t = text.replace('\r\n', '\n')
        self.added = []

    # ---- metin yardimcilari
    def _prep(self, s, raw, xaml):
        if raw:
            return s
        if xaml:
            return xaml_escape(s)
        return convert(s, 'yama')

    def rep(self, old, new, count=1, raw=False, xaml=False, name=None):
        o = self._prep(old, raw, xaml)
        nw = self._prep(new, raw, xaml)
        c = self.t.count(o)
        if c != count:
            raise SystemExit('rep (%s): "%s" beklenen %d, bulunan %d' % (name or '', o[:90].replace('\n', '\\n'), count, c))
        self.t = self.t.replace(o, nw)

    def after(self, anchor, new, raw=False, xaml=False, count=1):
        a = self._prep(anchor, raw, xaml)
        nw = self._prep(new, raw, xaml)
        c = self.t.count(a)
        if c != count:
            raise SystemExit('after: "%s" beklenen %d, bulunan %d' % (a[:90].replace('\n', '\\n'), count, c))
        self.t = self.t.replace(a, a + nw)

    def before(self, anchor, new, raw=False, xaml=False, count=1):
        a = self._prep(anchor, raw, xaml)
        nw = self._prep(new, raw, xaml)
        c = self.t.count(a)
        if c != count:
            raise SystemExit('before: "%s" beklenen %d, bulunan %d' % (a[:90].replace('\n', '\\n'), count, c))
        self.t = self.t.replace(a, nw + a)

    def sub_re(self, pat, new, count=1, flags=0, raw=False):
        nw = new if raw else convert(new, 'yama')
        r = re.compile(pat, flags)
        found = len(r.findall(self.t))
        if found != count:
            raise SystemExit('sub_re: "%s" beklenen %d, bulunan %d' % (pat[:80], count, found))
        self.t = r.sub(lambda m: nw, self.t)

    def has(self, s, raw=False):
        return self._prep(s, raw, False) in self.t

    # ---- modul ekleme
    def read_mod(self, fname):
        p = os.path.join(HERE, 'mods', fname)
        with open(p, encoding='utf-8-sig') as f:
            return f.read().replace('\r\n', '\n')

    def add_core(self, fname, subs=(), title=None):
        src = self.read_mod(fname)
        for old, new in subs:
            if src.count(old) != 1:
                raise SystemExit('add_core %s: "%s" beklenen 1, bulunan %d' % (fname, old[:60], src.count(old)))
            src = src.replace(old, new)
        conv = convert(src, fname)
        m = CORE_END_RE.search(self.t)
        if m is None:
            raise SystemExit('cekirdek sonu bulunamadi')
        pos = m.start()
        stem = os.path.splitext(fname)[0]
        self.t = self.t[:pos] + '\n' + marker(stem, title) + '\n' + conv.rstrip('\n') + '\n' + self.t[pos:]
        self.added.append(('core', fname))

    def add_ui(self, fname, before_anchor, subs=(), title=None):
        src = self.read_mod(fname)
        for old, new in subs:
            if src.count(old) != 1:
                raise SystemExit('add_ui %s: "%s" beklenen 1, bulunan %d' % (fname, old[:60], src.count(old)))
            src = src.replace(old, new)
        conv = convert(src, fname)
        if self.t.count(before_anchor) != 1:
            raise SystemExit('add_ui %s: capa "%s" beklenen 1, bulunan %d' % (fname, before_anchor[:60], self.t.count(before_anchor)))
        stem = os.path.splitext(fname)[0]
        self.t = self.t.replace(before_anchor, marker(stem, title) + '\n' + conv.rstrip('\n') + '\n\n' + before_anchor)
        self.added.append(('ui', fname))


def sha_text(path):
    with open(path, 'rb') as f:
        raw = f.read()
    txt = raw.decode('utf-8-sig').replace('\r\n', '\n')
    return hashlib.sha256(txt.encode('utf-8')).hexdigest()


def pack_files(static_dir):
    """Ozet tablosuna giren yan dosyalar: Eklenti/ ve veri/ altindaki (alt klasorler dahil) .ps1 .txt .json .csv .lang dosyalari."""
    rels = []
    for sub in ('Eklenti', 'veri'):
        d = os.path.join(static_dir, sub)
        if not os.path.isdir(d):
            continue
        for root, dirs, files in os.walk(d):
            dirs.sort()
            for fn in sorted(files):
                if fn.lower().endswith(('.ps1', '.txt', '.json', '.csv', '.lang')):
                    rel = os.path.relpath(os.path.join(root, fn), static_dir).replace(os.sep, '/')
                    rels.append(rel)
    return sorted(rels)


def stamp_hashes(text, static_dir):
    rels = pack_files(static_dir)
    lines = ["$script:PackHash = @{"]
    for r in rels:
        lines.append("    '%s' = '%s'" % (r, sha_text(os.path.join(static_dir, *r.split('/')))))
    lines.append('}')
    block = '\n'.join(lines)
    pat = re.compile(r"\$script:PackHash = @\{\n(?:    '[^']+' = '[0-9a-f]{64}'\n)+\}")
    if len(pat.findall(text)) != 1:
        raise SystemExit('PackHash blogu bulunamadi')
    return pat.sub(lambda m: block, text)


# ---------------------------------------------------------------------------------------------
#  Dil destegi: arayuz metni atamalarini Tr ile sarma
#    $x.Text = ifade   ->   $x.Text = (Tr $(ifade))        (Text, Content, ToolTip, Header, Title, BalloonTipText, BalloonTipTitle)
#  Atamalarin konumlari betigin sozdizimi agacindan (tools/i18n_wrap.ps1; PowerShell gerekir) bulunur. Sonuc, metnin ozetiyle birlikte
#  wrapmap.json dosyasinda saklanir: kaynak degismediyse yeniden derlemek icin PowerShell gerekmez.
#  Sarilmaz: veri nesnelerine yapilan atamalar ($r $res $out $pl $m $d $l), satirinda "# Tr:yok" olanlar, zaten Tr/Convert-LogLineText/Format-Tr ile baslayanlar.
# ---------------------------------------------------------------------------------------------
WRAP_SKIP_ROOTS = ('r', 'res', 'out', 'pl', 'm', 'd', 'l')
WRAP_MARK = '# Tr:yok'
WRAP_PROPS_SKIP = ('Description',)


def _find_powershell():
    for cand in (os.environ.get('MM_PWSH'), shutil.which('pwsh'), shutil.which('powershell'), shutil.which('powershell.exe')):
        if cand and os.path.exists(cand):
            return cand
    return None


def wrap_rows(text):
    """Sarilabilir atamalarin ham listesi: [{s, e, l, t, p}]. Onbellek metnin SHA-256 ozetiyle eslesirse kullanilir."""
    digest = hashlib.sha256(text.encode('ascii')).hexdigest()
    mp = os.path.join(HERE, 'wrapmap.json')
    if os.path.isfile(mp):
        try:
            with open(mp, encoding='utf-8') as f:
                d = json.load(f)
            if d.get('sha') == digest and isinstance(d.get('rows'), list):
                return d['rows']
        except (OSError, ValueError):
            pass
    exe = _find_powershell()
    if exe is None:
        raise SystemExit('dil destegi: kaynak degisti ve PowerShell (pwsh ya da powershell) bulunamadi; wrapmap.json yenilenemiyor. '
                         'MM_PWSH ortam degiskenine PowerShell yolunu yazin.')
    tool = os.path.join(HERE, 'tools', 'i18n_wrap.ps1')
    with tempfile.TemporaryDirectory() as td:
        src = os.path.join(td, 'Multimizer.ps1')
        dst = os.path.join(td, 'wrap.json')
        with open(src, 'w', encoding='ascii', newline='') as f:
            f.write(text)
        cmd = [exe, '-NoProfile']
        if os.path.basename(exe).lower().startswith('powershell'):
            cmd += ['-ExecutionPolicy', 'Bypass']
        cmd += ['-File', tool, '-Path', src, '-Out', dst]
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
        if r.returncode != 0 or not os.path.isfile(dst):
            raise SystemExit('dil destegi: i18n_wrap.ps1 basarisiz: ' + (r.stdout + r.stderr).strip()[:400])
        with open(dst, encoding='utf-8-sig') as f:
            rows = json.load(f)
    if isinstance(rows, dict):
        rows = [rows]
    with open(mp, 'w', encoding='utf-8', newline='\n') as f:
        json.dump({'sha': digest, 'rows': rows}, f, ensure_ascii=True, separators=(',', ':'))
        f.write('\n')
    return rows


def i18n_wrap(text):
    if not text.isascii():
        raise SystemExit('dil destegi: metin ASCII degil')
    rows = wrap_rows(text)
    lines = text.split('\n')
    edits = []
    skip_rhs = re.compile(r'\(?\s*(?:Tr|Convert-LogLineText|Format-Tr)(?![A-Za-z0-9_-])')
    for r in rows:
        t = str(r['t'])
        m = re.match(r'\$([A-Za-z_][A-Za-z0-9_]*)', t)
        if m and m.group(1).lower() in WRAP_SKIP_ROOTS:
            continue
        if str(r['p']) in WRAP_PROPS_SKIP:
            continue
        if WRAP_MARK in lines[int(r['l']) - 1]:
            continue
        s0, e0 = int(r['s']), int(r['e'])
        if skip_rhs.match(text[s0:e0]):
            continue
        edits.append((s0, e0))
    edits.sort(reverse=True)
    for s0, e0 in edits:
        text = text[:s0] + '(Tr $(' + text[s0:e0] + '))' + text[e0:]
    print('dil destegi: %d atama Tr ile sarildi' % len(edits))
    return text


def ascii_strings_cs(src):
    """C# metnindeki dizgi sabitlerinde ASCII disi karakterleri \\uXXXX kacisina cevirir (derleyici kodlamasindan bagimsiz olsun diye)."""
    def esc(m):
        out = []
        for ch in m.group(0):
            o = ord(ch)
            if o < 128:
                out.append(ch)
            elif o <= 0xFFFF:
                out.append('\\u%04x' % o)
            else:
                o -= 0x10000
                out.append('\\u%04x\\u%04x' % (0xD800 + (o >> 10), 0xDC00 + (o & 0x3FF)))
        return ''.join(out)
    return re.sub(r'"(?:\\.|[^"\\\n])*"', esc, src)


def _gen_addon(static_dir, tpl_name, cs_main, cs_glob, marker, out_name):
    """Bir eklenti = sablon (.tpl.ps1) + C# kaynagi. Sablondaki isaret satiri C# kaynagiyla degistirilir."""
    src_dir = os.path.join(HERE, 'src')
    tpl_path = os.path.join(src_dir, tpl_name)
    cs_path = os.path.join(src_dir, cs_main)
    if not (os.path.exists(tpl_path) and os.path.exists(cs_path)):
        return
    tpl = open(tpl_path, encoding='utf-8', newline='').read().replace('\r\n', '\n')
    cs = open(cs_path, encoding='utf-8', newline='').read().replace('\r\n', '\n')
    # ek partial kaynaklar (RcEngineFs.cs ...): using satirlari ilk dosyadan gelir, burada atilir
    for extra in sorted(glob.glob(os.path.join(src_dir, cs_glob))):
        if os.path.basename(extra) == cs_main:
            continue
        part = open(extra, encoding='utf-8', newline='').read().replace('\r\n', '\n')
        part = re.sub(r'(?m)^using [A-Za-z0-9_.]+;[ \t]*\n', '', part)
        cs = cs.rstrip('\n') + '\n\n' + part
    cs = ascii_strings_cs(cs).strip('\n')
    if re.search(r"(?m)^'@", cs):
        raise SystemExit(cs_main + ": satir basinda '@ olamaz")
    if tpl.count(marker) != 1:
        raise SystemExit(tpl_name + ': ' + marker + ' isareti bir kez olmali')
    out = tpl.replace(marker, cs)
    os.makedirs(os.path.join(static_dir, 'Eklenti'), exist_ok=True)
    with open(os.path.join(static_dir, 'Eklenti', out_name), 'w', encoding='utf-8', newline='') as f:
        f.write(out)


def generate_addons(static_dir):
    """build/src altindaki kaynaklardan uretilen eklentiler:
    Kurtarma = Kurtarma.tpl.ps1 + RcEngine*.cs, DiskSilme = DiskSilme.tpl.ps1 + WipeEngine.cs"""
    _gen_addon(static_dir, 'Kurtarma.tpl.ps1', 'RcEngine.cs', 'RcEngine?*.cs', '#@@RCENGINE@@', 'Kurtarma.ps1')
    _gen_addon(static_dir, 'DiskSilme.tpl.ps1', 'WipeEngine.cs', 'WipeEngine?*.cs', '#@@WIPEENGINE@@', 'DiskSilme.ps1')


def generate_launcher(static_dir):
    """Acilis.ps1 = src/Acilis.tpl.ps1 + src/baslatma_dil.tsv (acilis ekrani metinleri, ASCII \\uXXXX olarak gomulur)."""
    src_dir = os.path.join(HERE, 'src')
    tpl_path = os.path.join(src_dir, 'Acilis.tpl.ps1')
    tsv_path = os.path.join(src_dir, 'baslatma_dil.tsv')
    if not (os.path.exists(tpl_path) and os.path.exists(tsv_path)):
        return
    tpl = open(tpl_path, encoding='utf-8', newline='').read().replace('\r\n', '\n')
    marker = '#@@DILTABLOSU@@'
    if tpl.count(marker) != 1:
        raise SystemExit('Acilis.tpl.ps1: ' + marker + ' isareti bir kez olmali')
    rows = [ln.rstrip('\n') for ln in open(tsv_path, encoding='utf-8', newline='').read().replace('\r\n', '\n').split('\n')]
    rows = [r for r in rows if r.strip() and not r.startswith('#')]
    head = rows[0].split('\t')
    if head[0] != 'anahtar':
        raise SystemExit('baslatma_dil.tsv: ilk sutun "anahtar" olmali')
    langs = head[1:]
    keys = []
    cols = dict((l, []) for l in langs)
    for r in rows[1:]:
        c = r.split('\t')
        if len(c) != len(head):
            raise SystemExit('baslatma_dil.tsv: sutun sayisi uyusmuyor: ' + c[0])
        keys.append(c[0])
        for l, v in zip(langs, c[1:]):
            cols[l].append(v)

    def esc(t):
        out = []
        for ch in t:
            o = ord(ch)
            if ch == '\\':
                out.append('\\\\')
            elif ch == "'":
                out.append('\\u0027')
            elif 32 <= o < 127:
                out.append(ch)
            elif o > 0xFFFF:
                o -= 0x10000
                out.append('\\u%04x\\u%04x' % (0xD800 + (o >> 10), 0xDC00 + (o & 0x3FF)))
            else:
                out.append('\\u%04x' % o)
        return ''.join(out)
    lines = ["$script:LTKeys = @(" + ', '.join("'%s'" % k for k in keys) + ")", "$script:LTData = @{"]
    for l in langs:
        lines.append("    '%s' = @(" % l)
        for i, v in enumerate(cols[l]):
            lines.append("        '%s'%s" % (esc(v), ',' if i < len(cols[l]) - 1 else ''))
        lines.append("    )")
    lines.append("}")
    out = tpl.replace(marker, '\n'.join(lines))
    bad = [ch for ch in out if ord(ch) > 127]
    if bad:
        raise SystemExit('Acilis.ps1 ASCII degil: %r' % bad[0])
    with open(os.path.join(static_dir, 'Acilis.ps1'), 'w', encoding='utf-8', newline='') as f:
        f.write(out.replace('\n', '\r\n'))


def check_patch_source(path):
    # Gecersiz kacis dizisi ('\D' gibi) bugun yalnizca uyari, ileride hata; onbellekli derlemede de gorunmez. Burada hata sayilir.
    import warnings
    with open(path, encoding='utf-8') as f:
        src = f.read()
    with warnings.catch_warnings():
        warnings.simplefilter('error', SyntaxWarning)
        try:
            compile(src, path, 'exec')
        except SyntaxError as e:
            raise SystemExit('yama derlenemedi (%s, satir %s): %s' % (os.path.basename(path), e.lineno, e.msg))


def load_patches():
    res = []
    for p in sorted(glob.glob(os.path.join(HERE, 'patches', 'p*.py'))):
        check_patch_source(p)
        name = os.path.splitext(os.path.basename(p))[0]
        spec = importlib.util.spec_from_file_location(name, p)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        res.append((name, mod))
    return res


def copy_static(dst, static_dir):
    for item in os.listdir(static_dir):
        s = os.path.join(static_dir, item)
        d = os.path.join(dst, item)
        if os.path.isdir(s):
            if os.path.exists(d):
                shutil.rmtree(d)
            shutil.copytree(s, d)
        else:
            shutil.copy2(s, d)


def main():
    with open(os.path.join(HERE, 'base.ps1'), encoding='ascii', newline='') as f:
        base = f.read()
    b = Build(base)
    for name, mod in load_patches():
        mod.apply(b)
    b.t = i18n_wrap(b.t)
    static_dir = ROOT if DEPO else os.path.join(HERE, 'static')
    generate_addons(static_dir)
    generate_launcher(static_dir)
    text = stamp_hashes(b.t, static_dir)
    # ASCII denetimi
    bad = [ch for ch in set(text) if ord(ch) > 127]
    if bad:
        i = next(k for k, ch in enumerate(text) if ord(ch) > 127)
        raise SystemExit('cikti ASCII degil: %r satir %d' % (text[i], text.count('\n', 0, i) + 1))
    os.makedirs(OUT, exist_ok=True)
    if not DEPO:
        copy_static(OUT, static_dir)
    with open(os.path.join(OUT, 'Multimizer.ps1'), 'w', encoding='ascii', newline='') as f:
        f.write(text.replace('\n', '\r\n'))
    print('uretildi: %s  %d satir  %d bayt  modul=%d' % (os.path.relpath(os.path.join(OUT, 'Multimizer.ps1'), ROOT), text.count('\n') + 1, len(text), len(b.added)))


if __name__ == '__main__':
    main()
