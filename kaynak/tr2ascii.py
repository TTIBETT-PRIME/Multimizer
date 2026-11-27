# -*- coding: utf-8 -*-
"""Multimizer derleme yardimcisi: Unicode kaynak -> ASCII PowerShell.

Windows PowerShell 5.1, BOM'suz .ps1 dosyalarini ANSI okur; bu yuzden uretilen betik yalnizca ASCII icerir.
Kurallar (eski surumle ayni bicim; yamalarin capalari buna gore yazilir):
  * tek tirnakli dizgi:  'Sistem çökmeleri'  ->  ('Sistem ' + [char]0x00E7 + '' + [char]0x00F6 + 'kmeleri')
  * cift tirnakli dizgi: ayni bicim, parcalar cift tirnakla
  * yorum satirlari: Turkce harfler ASCII karsiligina cevrilir
  * @'...'@ / @"..."@ blogu: icerik '<' ile basliyorsa (XAML) ASCII disi karakterler &#xHHHH; olur, degilse hata
  * dizgi, yorum ya da blok disinda ASCII disi karakter: hata (tanimlayici, anahtar vb. icin Turkce harf kullanilmaz)
Her ASCII disi karakter BMP icinde olmalidir.
"""
import re
import unicodedata

TR = {
    'ç': 'c', 'Ç': 'C', 'ğ': 'g', 'Ğ': 'G', 'ı': 'i', 'İ': 'I', 'ö': 'o', 'Ö': 'O', 'ş': 's', 'Ş': 'S', 'ü': 'u', 'Ü': 'U',
    '’': "'", '‘': "'", '“': '"', '”': '"', '„': '"', '–': '-', '—': '-', '…': '...', '·': '.', '•': '*', '→': '->', '←': '<-',
    '↑': '^', '↓': 'v', '×': 'x', '≥': '>=', '≤': '<=', '≠': '!=', '«': '<<', '»': '>>', '°': 'o', '²': '2', '³': '3', '½': '1/2',
    '✓': 'v', '✔': 'v', '✕': 'x', '✗': 'x', '●': '*', '○': 'o', '■': '#', '□': '[]', '▲': '^', '▼': 'v', '►': '>', '◄': '<',
    ' ': ' ', '​': '', '€': 'EUR', '£': 'GBP', '©': '(c)', '®': '(R)', '™': '(TM)', '§': 'S.', '±': '+/-', 'µ': 'u',
}


def translit(s):
    out = []
    for ch in s:
        if ord(ch) < 128:
            out.append(ch)
        elif ch in TR:
            out.append(TR[ch])
        else:
            d = unicodedata.normalize('NFKD', ch)
            d = ''.join(c for c in d if ord(c) < 128)
            out.append(d if d else '?')
    return ''.join(out)


def _hex4(ch):
    o = ord(ch)
    if o > 0xFFFF:
        raise ValueError('BMP disi karakter: U+%X' % o)
    return '[char]0x%04X' % o


def _has_nonascii(s):
    for ch in s:
        if ord(ch) > 127:
            return True
    return False


def _concat(content, q):
    """content: dizgi govdesi (tirnaksiz). Donus: ('..' + [char]0x.... + '..')"""
    runs = []
    cur = []
    chars = []
    for ch in content:
        if ord(ch) > 127:
            runs.append(''.join(cur))
            cur = []
            chars.append(_hex4(ch))
        else:
            cur.append(ch)
    runs.append(''.join(cur))
    parts = []
    for i, r in enumerate(runs):
        if q == '"' and r.endswith('`') and (len(r) - len(r.rstrip('`'))) % 2 == 1:
            raise ValueError('ters tirnak kacisi ASCII disi karakterden once: %r' % r[-12:])
        parts.append(q + r + q)
        if i < len(chars):
            parts.append(chars[i])
    return '(' + ' + '.join(parts) + ')'


def _xml_escape_nonascii(s):
    return ''.join(('&#x%04X;' % ord(ch)) if ord(ch) > 127 else ch for ch in s)


def xaml(s):
    """XAML/XML parcasi: her ASCII disi karakter sayisal karakter basvurusu olur."""
    return _xml_escape_nonascii(s)


def _line_of(src, pos):
    return src.count('\n', 0, pos) + 1


def _skip_single(src, i):
    """src[i] == "'" ; kapanis tirnaginin dizini"""
    j = i + 1
    n = len(src)
    while j < n:
        if src[j] == "'":
            if j + 1 < n and src[j + 1] == "'":
                j += 2
                continue
            return j
        j += 1
    raise ValueError('kapanmamis tek tirnak (satir %d)' % _line_of(src, i))


def _skip_subexpr(src, i):
    """src[i:i+2] == '$(' ; eslesen ')' dizini"""
    depth = 0
    j = i + 1
    n = len(src)
    while j < n:
        c = src[j]
        if c == '(':
            depth += 1
        elif c == ')':
            depth -= 1
            if depth == 0:
                return j
        elif c == "'":
            j = _skip_single(src, j)
        elif c == '"':
            j = _skip_double(src, j)
        j += 1
    raise ValueError('kapanmamis $( (satir %d)' % _line_of(src, i))


def _skip_double(src, i):
    """src[i] == '"' ; kapanis tirnaginin dizini ($( ... ) icindeki tirnaklar atlanir)"""
    j = i + 1
    n = len(src)
    while j < n:
        c = src[j]
        if c == '`':
            j += 2
            continue
        if c == '"':
            if j + 1 < n and src[j + 1] == '"':
                j += 2
                continue
            return j
        if c == '$' and j + 1 < n and src[j + 1] == '(':
            j = _skip_subexpr(src, j) + 1
            continue
        j += 1
    raise ValueError('kapanmamis cift tirnak (satir %d)' % _line_of(src, i))


_COMMENT_PREV_OK = set(' \t\r\n;{}(),|&=')


def convert(src, name='?'):
    out = []
    i = 0
    n = len(src)
    while i < n:
        c = src[i]
        # blok yorum
        if c == '<' and src.startswith('<#', i):
            j = src.find('#>', i + 2)
            if j < 0:
                raise ValueError('%s: kapanmamis <# (satir %d)' % (name, _line_of(src, i)))
            out.append(translit(src[i:j + 2]))
            i = j + 2
            continue
        # satir yorumu
        if c == '#':
            prev = src[i - 1] if i > 0 else '\n'
            if prev in _COMMENT_PREV_OK:
                j = src.find('\n', i)
                if j < 0:
                    j = n
                out.append(translit(src[i:j]))
                i = j
                continue
        # here-string
        if c == '@' and i + 1 < n and src[i + 1] in ('"', "'"):
            q = src[i + 1]
            m = re.match(r'[ \t]*\r?\n', src[i + 2:])
            if m:
                body_start = i + 2 + m.end()
                end_m = re.compile(r'^' + re.escape(q) + '@', re.M).search(src, body_start)
                if end_m is None:
                    raise ValueError('%s: kapanmamis here-string (satir %d)' % (name, _line_of(src, i)))
                body = src[body_start:end_m.start()]
                head = src[i:body_start]
                if _has_nonascii(body):
                    if body.lstrip().startswith('<'):
                        body = _xml_escape_nonascii(body)
                    else:
                        raise ValueError('%s: here-string icinde ASCII disi karakter (satir %d)' % (name, _line_of(src, i)))
                out.append(head + body + src[end_m.start():end_m.end()])
                i = end_m.end()
                continue
        # tek tirnak
        if c == "'":
            j = _skip_single(src, i)
            body = src[i + 1:j]
            if _has_nonascii(body):
                out.append(_concat(body, "'"))
            else:
                out.append(src[i:j + 1])
            i = j + 1
            continue
        # cift tirnak
        if c == '"':
            j = _skip_double(src, i)
            body = src[i + 1:j]
            if _has_nonascii(body):
                if '$(' in body:
                    # alt ifade icinde ASCII disi karakter varsa hata
                    stripped = body
                    k = 0
                    while True:
                        k = stripped.find('$(', k)
                        if k < 0:
                            break
                        e = _skip_subexpr(stripped, k)
                        if _has_nonascii(stripped[k:e + 1]):
                            raise ValueError('%s: $( ) icinde ASCII disi karakter (satir %d)' % (name, _line_of(src, i)))
                        k = e + 1
                out.append(_concat_dq(body))
            else:
                out.append(src[i:j + 1])
            i = j + 1
            continue
        if ord(c) > 127:
            raise ValueError('%s: dizgi/yorum disinda ASCII disi karakter %r (satir %d)' % (name, c, _line_of(src, i)))
        out.append(c)
        i += 1
    return ''.join(out)


def _concat_dq(body):
    """Cift tirnakli govde: $( ... ) bolumleri bolunmez; yalnizca disindaki ASCII disi karakterler ayrilir."""
    runs = []
    cur = []
    chars = []
    k = 0
    n = len(body)
    while k < n:
        ch = body[k]
        if ch == '$' and k + 1 < n and body[k + 1] == '(':
            e = _skip_subexpr(body, k)
            cur.append(body[k:e + 1])
            k = e + 1
            continue
        if ch == '`' and k + 1 < n:
            cur.append(body[k:k + 2])
            k += 2
            continue
        if ord(ch) > 127:
            runs.append(''.join(cur))
            cur = []
            chars.append(_hex4(ch))
        else:
            cur.append(ch)
        k += 1
    runs.append(''.join(cur))
    parts = []
    for i, r in enumerate(runs):
        parts.append('"' + r + '"')
        if i < len(chars):
            parts.append(chars[i])
    return '(' + ' + '.join(parts) + ')'


if __name__ == '__main__':
    import sys
    data = open(sys.argv[1], encoding='utf-8-sig').read()
    sys.stdout.write(convert(data, sys.argv[1]))
