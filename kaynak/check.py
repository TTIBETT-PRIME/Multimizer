#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Statik denetimler: PowerShell (AST, tools/check.ps1) + XAML + $ui adlari + C# 5 uyumu + belgeler."""
import os
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
DEPO = os.path.basename(HERE) == 'kaynak'  # depo yerlesimi: kaynak/ deponun icindedir, uretilen dosyalar deponun kokundedir
OUT = os.path.join(ROOT, 'Multimizer.ps1') if DEPO else os.path.join(ROOT, 'out', 'Multimizer.ps1')
_LOCAL_PWSH = os.path.join(ROOT, 'pwsh7', 'pwsh')
PWSH = os.environ.get('PWSH') or (_LOCAL_PWSH if os.path.isfile(_LOCAL_PWSH) else (shutil.which('pwsh') or 'pwsh'))

issues = []


def issue(sec, msg):
    issues.append('[%s] %s' % (sec, msg))


def line_of(text, pos):
    return text.count('\n', 0, pos) + 1


def main():
    env = dict(os.environ, DOTNET_SYSTEM_GLOBALIZATION_INVARIANT='1')
    r = subprocess.run([PWSH, '-NoProfile', '-File', os.path.join(HERE, 'tools', 'check.ps1'), '-Path', OUT],
                       capture_output=True, text=True, env=env, timeout=600)
    out = (r.stdout + r.stderr).strip()
    for ln in out.split('\n'):
        ln = ln.strip()
        if ln.startswith('['):
            issues.append(ln)
        elif ln and 'temiz' not in ln and 'sorun' not in ln:
            issues.append('[powershell] ' + ln)
    text = open(OUT, encoding='ascii', newline='').read().replace('\r\n', '\n')

    # ---- ad cakismasi: 8.0.0 tabaninda olmayan bir islev ya da betik degiskeni birden fazla tanimlanmissa yenisi eskisinin ustune yazar
    base_text = open(os.path.join(HERE, 'base.ps1'), encoding='ascii', newline='').read().replace('\r\n', '\n')
    fn_re = re.compile(r'^function\s+([A-Za-z_][\w\-:\.]*)', re.M)
    var_re = re.compile(r'^\$script:(\w+)\s*=', re.M)
    for label, rx in (('islev', fn_re), ('degisken', var_re)):
        now = {}
        for m in rx.finditer(text):
            k = m.group(1).lower()
            now[k] = now.get(k, 0) + 1
        was = {}
        for m in rx.finditer(base_text):
            k = m.group(1).lower()
            was[k] = was.get(k, 0) + 1
        for k, c in sorted(now.items()):
            if c > 1 and c > was.get(k, 0):
                issue('cakisma', '%s birden fazla tanimli: %s (%d kez; tabanda %d)' % (label, k, c, was.get(k, 0)))

    # ---- dizi donusu: 'return , $dizi' ile donen islev @( ) icinde ya da dogrudan boru hattinda cagrilirsa dizi TEK nesne olarak gelir
    #      (@(Fn).Count hep 1 olur; foreach bir kez doner; Fn | Where-Object butun diziyi tek oge sayar). Once degiskene alinmali: $x = Fn; @($x)
    comma_check(text)

    # ---- XAML: iyi bicimlilik
    xaml_docs = 0
    parts = {}
    for m in re.finditer(r"\$script:(\w+)\s*=\s*@'\n(.*?)\n'@", text, re.S):
        body = m.group(2)
        if not body.lstrip().startswith('<'):
            continue
        parts[m.group(1)] = (body, m)
    # bolunmus kabuk: Head + Tail birlikte bir belge olusturur
    for hn in [k for k in parts if k.endswith('Head') and k[:-4] + 'Tail' in parts]:
        tn = hn[:-4] + 'Tail'
        hb, hm = parts.pop(hn)
        tb, _tm = parts.pop(tn)
        parts[hn[:-4] + 'Kabuk'] = (hb + '\n' + tb, hm)
    for key, (body, m) in sorted(parts.items(), key=lambda kv: kv[1][1].start()):
        xaml_docs += 1
        b = re.sub(r'@@\w+@@', 'x', body)
        # xmlns bildirimi olmayan parcalar (satir sablonlari, kaynaklar) icin kok sarmalayici
        try:
            ET.fromstring('<root xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" xmlns:shell="clr-namespace:System.Windows.Shell" xmlns:sys="clr-namespace:System;assembly=mscorlib">' + re.sub(r'<\?xml[^>]*\?>', '', b) + '</root>')
        except ET.ParseError as e:
            issue('xaml', '%s (satir %d): %s' % (key, line_of(text, m.start()), e))
        b2 = re.sub(r'<(ControlTemplate|DataTemplate)\b.*?</\1>', '', b, flags=re.S)
        names = re.findall(r'x:Name="([A-Za-z0-9_]+)"', b2)
        dup = sorted(set(n for n in names if names.count(n) > 1))
        if dup:
            issue('xaml', '%s: yinelenen x:Name %s' % (key, ', '.join(dup[:6])))

    # ---- $ui.X adlari
    names = set(re.findall(r'x:Name="([A-Za-z0-9_]+)"', text))
    assigned = set(re.findall(r"\$ui\.([A-Za-z_][A-Za-z0-9_]*)\s*=[^=]", text)) | set(re.findall(r"\$ui\['([A-Za-z0-9_]+)'\]\s*=[^=]", text))
    refs = {}
    for m in re.finditer(r"\$ui\.([A-Za-z_][A-Za-z0-9_]*)", text):
        refs.setdefault(m.group(1), m.start())
    for m in re.finditer(r"\$ui\['([A-Za-z0-9_]+)'\]", text):
        refs.setdefault(m.group(1), m.start())
    for k, pos in sorted(refs.items()):
        if k in names or k in assigned:
            continue
        if k in ('Keys', 'Count', 'ContainsKey', 'Add', 'Remove', 'Values', 'Contains', 'Clear', 'PSObject', 'GetEnumerator'):
            continue
        issue('ui', '$ui.%s icin x:Name yok (satir %d)' % (k, line_of(text, pos)))

    # ---- C# 5 uyumu (Add-Type govdeleri)
    cs_rules = [
        (r'\$"', 'dizgi enterpolasyonu ($"...")'), (r'\$@"', 'dizgi enterpolasyonu'), (r'\w\?\.\w', 'bos kosullu erisim (?.)'), (r'\w\?\[', 'bos kosullu dizin (?[)'),
        (r'\bnameof\s*\(', 'nameof'), (r'\bout\s+var\b', 'out var'), (r'\bis\s+[A-Za-z_][\w.]*\s+[a-z_]\w*\s*[)&|;]', 'desen eslestirme (is T x)'),
        (r'^\s*(?:public|private|internal|protected)[^;{=]*\)\s*=>', 'ifade govdeli uye (=>)'), (r'^\s*(?:public|private|internal|protected)[^;{(=]*\s=>', 'ifade govdeli ozellik (=>)'),
        (r'\{\s*get;\s*(?:private\s+|protected\s+)?set;\s*\}\s*=', 'otomatik ozellik baslaticisi'), (r'\)\s*when\s*\(', 'istisna filtresi (when)'), (r'\busing\s+static\b', 'using static'),
        (r'\?\?\s*throw\b', 'throw ifadesi'), (r'\b0b[01]', 'ikili sabit'), (r'\b\d_\d', 'rakam ayiraci'), (r'\bdefault\s*[;,)]', 'default sabiti (C# 7.1)'), (r'\bstring\?|\bint\?\?', 'bos olabilen referans'),
    ]
    for m in re.finditer(r"@(['\"])\n(.*?)\n\1@", text, re.S):
        body = m.group(2)
        if not re.search(r'\busing\s+System|\bnamespace\s+\w|\bpublic\s+(?:static\s+)?class\b|\[DllImport', body):
            continue
        clean = re.sub(r'//[^\n]*', '', body)
        clean = re.sub(r'"(?:\\.|[^"\\])*"', '""', clean)
        base_line = line_of(text, m.start(2))
        for pat, what in cs_rules:
            for mm in re.finditer(pat, clean, re.M):
                issue('cs5', 'satir %d: %s' % (base_line + clean.count('\n', 0, mm.start()), what))

    # ---- C# 5 uyumu (Roslyn, dil surumu C# 5): ana betik, eklentiler ve build/src altindaki .cs dosyalari
    cs_files = [OUT]
    edir = os.path.join(os.path.dirname(OUT), 'Eklenti')
    if os.path.isdir(edir):
        cs_files += [os.path.join(edir, fn) for fn in sorted(os.listdir(edir)) if fn.lower().endswith('.ps1')]
    sdir = os.path.join(HERE, 'src')
    if os.path.isdir(sdir):
        cs_files += [os.path.join(sdir, fn) for fn in sorted(os.listdir(sdir)) if fn.lower().endswith('.cs')]
    r5 = subprocess.run([PWSH, '-NoProfile', '-File', os.path.join(HERE, 'tools', 'csharp5.ps1'), '-Files', '|'.join(cs_files)],
                        capture_output=True, text=True, env=env, timeout=600)
    for ln in (r5.stdout + r5.stderr).strip().split('\n'):
        ln = ln.strip()
        if ln.startswith('[cs5]'):
            issues.append(ln)
        elif ln and not ln.startswith('cs5 temiz'):
            issues.append('[cs5] ' + ln)

    # ---- belgeler: surum tutarliligi, uretilen belgenin guncelligi ve belgelerde adi gecen test takimlarinin varligi
    docs_check(text, env)

    print('XAML belgesi: %d  | $ui adi: %d  | x:Name: %d' % (xaml_docs, len(refs), len(names)))
    if issues:
        for s in issues:
            print(s)
        print('SORUN: %d' % len(issues))
        sys.exit(1)
    print('denetimler temiz')


def _strip_comment(ln):
    """Satirdaki # yorumunu (tirnak disindaysa) atar."""
    q = None
    for i, ch in enumerate(ln):
        if q:
            if ch == q:
                q = None
        elif ch in '\'"':
            q = ch
        elif ch == '#' and (i == 0 or ln[i - 1] in ' \t;{('):
            return ln[:i]
    return ln


def comma_check(text):
    code = '\n'.join(_strip_comment(ln) for ln in text.split('\n'))
    pos = [(m.start(), m.group(1)) for m in re.finditer(r'(?m)^function ([A-Za-z][A-Za-z0-9_\-]*)', code)]
    comma = set()
    for i, (st, name) in enumerate(pos):
        en = pos[i + 1][0] if i + 1 < len(pos) else len(code)
        rets = [r.strip() for r in re.findall(r'\breturn\b([^\n]*)', code[st:en])]
        if any(r.startswith(',') for r in rets):
            comma.add(name)
    if not comma:
        return
    names = sorted(comma, key=len, reverse=True)
    rx = re.compile(r'(?<![A-Za-z0-9_\-\$\.\'"])(' + '|'.join(re.escape(n) for n in names) + r')(?![A-Za-z0-9_\-])')
    for m in rx.finditer(code):
        ls = code.rfind('\n', 0, m.start()) + 1
        pre = code[ls:m.start()]
        if re.match(r'\s*function\s+$', pre):
            continue
        kind = None
        if re.search(r'@\(\s*$', pre):
            kind = '@(%s ...)' % m.group(1)
        else:
            i = m.end()
            depth = 0
            q = None
            while i < len(code):
                ch = code[i]
                if q:
                    if ch == q:
                        q = None
                elif ch in '\'"':
                    q = ch
                elif ch in '([{':
                    depth += 1
                elif ch in ')]}':
                    if depth == 0:
                        break
                    depth -= 1
                elif ch in '\n;' and depth == 0:
                    break
                elif ch == '|' and depth == 0:
                    if code[i:i + 2] != '||':
                        kind = '%s ... |' % m.group(1)
                    break
                i += 1
        if kind:
            issue('dizi', 'satir %d: %s  (islev diziyi tek nesne dondurur; once degiskene alin)' % (line_of(code, m.start()), kind))


def docs_check(text, env):
    """docs8 altindaki belgeler betikle ayni surumu tasir, uretilen STANDARTLAR.md gunceldir, belgelerde anilan test takimlari vardir."""
    docs = ROOT if DEPO else os.path.join(HERE, 'docs8')
    if not os.path.isdir(docs):
        issue('belge', 'belge klasoru yok: ' + docs)
        return

    def rd(name):
        with open(os.path.join(docs, name), encoding='utf-8-sig', newline='') as f:
            return f.read().replace('\r\n', '\n')

    mv = re.search(r"\$script:AppVersion = '([0-9]+\.[0-9]+\.[0-9]+)'", text)
    if not mv:
        issue('belge', 'betikte $script:AppVersion bulunamadi')
        return
    ver = mv.group(1)

    ch = rd('CHANGELOG.md')
    mh = re.search(r'^## ([0-9]+\.[0-9]+\.[0-9]+)\b', ch, re.M)
    if not mh or mh.group(1) != ver:
        issue('belge', 'CHANGELOG.md ilk surum basligi %s, betik %s' % (mh.group(1) if mh else 'yok', ver))
    first = rd('OKUBENI.txt').split('\n', 1)[0]
    if ('v' + ver) not in first:
        issue('belge', 'OKUBENI.txt ilk satiri v%s icermiyor' % ver)
    if ('(' + ver + ')') not in rd('MIMARI.md'):
        issue('belge', 'MIMARI.md "(%s)" ile baslayan guncel durum notunu icermiyor' % ver)

    # baska surum numarasi: README / OKUBENI / SECURITY / CONTRIBUTING / MIMARI yalnizca guncel surumu anabilir (IP adresleri ve 4 gruplu sayilar sayilmaz)
    ver_pat = re.compile(r'(?<![0-9.])([0-9]+\.[0-9]+\.[0-9]+)(?![0-9]|\.[0-9])')
    for name in ('README.md', 'OKUBENI.txt', 'SECURITY.md', 'CONTRIBUTING.md', 'MIMARI.md'):
        body = rd(name)
        for i, ln in enumerate(body.split('\n'), 1):
            for m in ver_pat.finditer(ln):
                if m.group(1) != ver:
                    issue('belge', '%s satir %d: eski ya da yabanci surum numarasi %s' % (name, i, m.group(1)))

    # doldurulmamis yer tutucular (@@ADI@@)
    for name in ('README.md', 'OKUBENI.txt', 'SECURITY.md', 'CONTRIBUTING.md', 'MIMARI.md', 'CHANGELOG.md'):
        for m in sorted(set(re.findall(r'@@[A-Z0-9_]+@@', rd(name)))):
            issue('belge', '%s: doldurulmamis yer tutucu %s' % (name, m))

    # paket sirasinda docs_fill.py'nin doldurdugu yer tutucular (__TAKIM__, __DENETIM__, __DIL__, __KAPSAM__, __K_<dil>__): baska bicimli olani doldurulmaz
    known = re.compile(r'^__(TAKIM|DENETIM|DIL|KAPSAM|K_(en|de|zh|zh_hant|ja|ar|fr|es|it|pt|ru|ko))__$')
    for name in ('README.md', 'OKUBENI.txt', 'SECURITY.md', 'CONTRIBUTING.md', 'MIMARI.md', 'CHANGELOG.md'):
        for m in sorted(set(re.findall(r'__[A-Za-z][A-Za-z0-9_]*__', rd(name)))):
            if not known.match(m):
                issue('belge', '%s: docs_fill.py tanimayan yer tutucu %s' % (name, m))

    # uretilen belge
    gen = os.path.join(HERE, 'tools', 'gen_standartlar.py')
    if os.path.isfile(gen):
        rg = subprocess.run([sys.executable, '-I', gen, '--check'], capture_output=True, text=True, env=env, timeout=300)
        if rg.returncode != 0:
            issue('belge', 'STANDARTLAR.md guncel degil: ' + (rg.stdout + rg.stderr).strip().replace('\n', ' | ')[:300])

    # belgelerde adi gecen test takimlari
    tdir = os.path.join(ROOT, 'tests')
    have = set(os.path.splitext(fn)[0] for fn in os.listdir(tdir)) if os.path.isdir(tdir) else set()
    for name in ('README.md', 'OKUBENI.txt', 'CONTRIBUTING.md', 'MIMARI.md'):
        for m in sorted(set(re.findall(r'\bt_[a-z0-9_]+\b', rd(name)))):
            if m not in have:
                issue('belge', '%s: %s adinda bir test takimi yok' % (name, m))

    # belgelerde yazan takim sayisi gercek sayiyla ayni olmali (README, MIMARI ve CHANGELOG'daki ilk "Testler." maddesi)
    n_tests = len([fn for fn in os.listdir(tdir) if re.match(r't_[a-z0-9_]+\.ps1$', fn)]) if os.path.isdir(tdir) else 0
    for name in ('README.md', 'MIMARI.md'):
        for m in re.finditer(r'\b([0-9]+) takım', rd(name)):
            if int(m.group(1)) != n_tests:
                issue('belge', '%s: "%s takım" yazıyor, tests/ altında %d takım var' % (name, m.group(1), n_tests))
    mt = re.search(r'^- \*\*Testler\.\*\* (\S+) takım', ch, re.M)
    if mt and mt.group(1) != '__TAKIM__' and (not mt.group(1).isdigit() or int(mt.group(1)) != n_tests):
        issue('belge', 'CHANGELOG.md: ilk "Testler." maddesi %s takım yazıyor, tests/ altında %d takım var (ya da __TAKIM__ yer tutucusu olmalı)' % (mt.group(1), n_tests))


if __name__ == '__main__':
    main()
