# ==================================================================
#  DIL DESTEGI: cekirdek (dil dosyalari, Tr islevi, otomatik dil secimi, sagdan sola yazim)
# ==================================================================
# Kaynak dil Turkcedir; Turkce metnin kendisi kimliktir (gettext tarzi), bu yuzden Turkce icin dil dosyasi yoktur.
# Dil dosyasi: veri\dil\<kod>.lang (UTF-8). Ust bilgi satirlari "#anahtar: deger" bicimindedir, sonra her satir
#   Turkce metin <SEKME> ceviri
# Kacis: \\ -> \   \t -> sekme   \n -> satir sonu   \r -> satir basi.
# Sablon: kimlikte {0} {1} ... dinamik parcayi gosterir ("Silindi: {0} dosya"). Ceviri bu yer tutucularin sirasini degistirebilir.
# Arama sirasi: secili dil (birebir, bastaki/sondaki bosluk, sablon) -> Ingilizce -> Turkce (metin oldugu gibi kalir).
# Kullanicinin kendi dil dosyalari %ProgramData%\Multimizer\dil klasorune konur; ayni kodlu uygulama dosyasinin yerine gecer.

$script:LangOn = $false          # Turkce disinda bir dil etkin mi
$script:LangCode = 'tr'
$script:LangTag = 'tr-TR'
$script:LangRtl = $false
$script:LangName = ''
$script:LangPrimary = $null      # @{ Code; Map; Tpl; Meta; N; NTpl }
$script:LangFallback = $null     # Ingilizce paket (secili dil Ingilizce degilse)
$script:LangList = $null
$script:LangTrack = $false       # kalite denetimi: istenen ama cevirisi olmayan metinleri sayar
$script:LangMiss = $null
$script:LangSeen = $null
$script:LangKeyLen = 5
$script:LangCache = $null         # metin -> cevrilmis metin (yalnizca izleme kapaliyken)
$script:LangPrefixRx = New-Object System.Text.RegularExpressions.Regex(('^(\s*(?:>>>|' + [char]0x2192 + ')\s+)(.+)$'), [System.Text.RegularExpressions.RegexOptions]::Singleline)
$script:LangBracketRx = New-Object System.Text.RegularExpressions.Regex('^(.*?)\s{2}\[(.+)\]\s*$', [System.Text.RegularExpressions.RegexOptions]::Singleline)
$script:LangCountRx = New-Object System.Text.RegularExpressions.Regex('^(.+?) \(([^()]+)\)$', [System.Text.RegularExpressions.RegexOptions]::Singleline)
$script:LangUpperRx = New-Object System.Text.RegularExpressions.Regex('\p{Lu}{2}')
$script:LangLowerRx = New-Object System.Text.RegularExpressions.Regex('\p{Ll}')
$script:LangFull = $true             # son Find-LangText sonucu eksiksiz cevrildi mi (parcalara bolunen metinlerde)
$script:LangLetterRx = New-Object System.Text.RegularExpressions.Regex('\p{L}{2}')
$script:LangUpperCulture = $null   # buyuk harf donusumunde kullanilan kultur (etkin dilin kulturu)
$script:LangLogRx = New-Object System.Text.RegularExpressions.Regex('^(\d\d:\d\d:\d\d\s+\S+\s+)(.+)$', [System.Text.RegularExpressions.RegexOptions]::Singleline)
$script:LangOut = $null           # izleme acikken Tr'nin urettigi cevrilmis metinler (cift cevirinin eksik sayilmamasi icin)
$script:LangPctStyle = 0         # yuzde yazimi: 0 = %40 (Turkce), 1 = 40%, 2 = 40 % (bolunmez bosluk)

function Get-LangUnescaped([string]$s) {
    if ($s.IndexOf([char]92) -lt 0) { return $s }
    $sb = New-Object System.Text.StringBuilder
    $n = $s.Length
    $i = 0
    while ($i -lt $n) {
        $c = $s[$i]
        if ($c -eq [char]92 -and ($i + 1) -lt $n) {
            $d = $s[$i + 1]
            if ($d -eq 't') { [void]$sb.Append("`t"); $i += 2; continue }
            if ($d -eq 'n') { [void]$sb.Append("`n"); $i += 2; continue }
            if ($d -eq 'r') { [void]$sb.Append("`r"); $i += 2; continue }
            if ($d -eq '\') { [void]$sb.Append('\'); $i += 2; continue }
        }
        [void]$sb.Append($c)
        $i++
    }
    return $sb.ToString()
}

function Get-LangFolders {
    $list = New-Object System.Collections.ArrayList
    $app = ''
    try { $app = Get-AppFolder } catch { $app = '' }
    if ($app -ne '') { [void]$list.Add([System.IO.Path]::Combine($app, 'veri', 'dil')) }
    $pd = ''
    try { $pd = [Environment]::GetFolderPath('CommonApplicationData') } catch { $pd = '' }
    if ($pd -ne '') { [void]$list.Add([System.IO.Path]::Combine($pd, 'Multimizer', 'dil')) }
    return $list.ToArray()
}

# Sablon kimligini ({0} ...) duzenli ifadeye cevirir ve paketin dizinine ekler
function Add-LangTemplate($Pack, [string]$Id, [string]$Out) {
    $parts = [regex]::Split($Id, '\{(\d+)\}')
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('^')
    $lits = 0
    $longest = ''
    for ($i = 0; $i -lt $parts.Length; $i++) {
        if (($i % 2) -eq 0) {
            $lit = [string]$parts[$i]
            if ($lit.Length -gt $longest.Length) { $longest = $lit }
            # bitisik yer tutucular (ornek "{0}{1}") belirsizdir: sablon olarak eklenmez
            if ($i -gt 0 -and $i -lt ($parts.Length - 1) -and $lit.Length -eq 0) { return }
            $lits += $lit.Trim().Length
            [void]$sb.Append([regex]::Escape($lit))
        } else {
            [void]$sb.Append('(?<g' + [string]$parts[$i] + '>.*?)')
        }
    }
    [void]$sb.Append('\z')
    # tek basina anlam tasimayan sablonlar ("{0}: {1}") her metinle eslesirdi
    if ($lits -lt 2) { return }
    # Duzenli ifade ilk kullanimda kurulur (acilista binlerce sablonu derlemek gereksiz bekletir)
    $rx = $null
    $key = [string]$parts[0]
    if ($key.Length -gt $script:LangKeyLen) { $key = $key.Substring(0, $script:LangKeyLen) }
    $list = $null
    if (-not $Pack.Tpl.TryGetValue($key, [ref]$list)) {
        $list = New-Object System.Collections.ArrayList
        $Pack.Tpl[$key] = $list
    }
    $suf = [string]$parts[$parts.Length - 1]
    [void]$list.Add(@{ Rx = $rx; Src = $sb.ToString(); Out = $Out; W = $lits; Id = $Id; Suf = $suf; Lit = $longest })
    $Pack.NTpl = [int]$Pack.NTpl + 1
}

# Dil dosyasinin metnini okur (ust bilgi + metinler)
function Read-LangPack([string]$Text, [string]$Code) {
    $pack = @{
        Code = $Code
        Map = (New-Object 'System.Collections.Generic.Dictionary[string,string]' ([System.StringComparer]::Ordinal))
        Tpl = (New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::Ordinal))
        Meta = @{}
        N = 0
        NTpl = 0
    }
    foreach ($ln0 in ($Text -split "`n")) {
        $ln = $ln0
        if ($ln.Length -gt 0 -and $ln[$ln.Length - 1] -eq "`r") { $ln = $ln.Substring(0, $ln.Length - 1) }
        if ($ln.Length -eq 0) { continue }
        if ($ln[0] -eq '#') {
            $m = [regex]::Match($ln, '^#\s*([A-Za-z]+)\s*:\s*(.*)$')
            if ($m.Success) { $pack.Meta[$m.Groups[1].Value.ToLowerInvariant()] = $m.Groups[2].Value.Trim() }
            continue
        }
        $tab = $ln.IndexOf([char]9)
        if ($tab -lt 1) { continue }
        $out = Get-LangUnescaped ($ln.Substring($tab + 1))
        if ($out.Length -eq 0) { continue }
        $id = Get-LangUnescaped ($ln.Substring(0, $tab))
        if ($id.IndexOf([char]123) -ge 0 -and [regex]::IsMatch($id, '\{\d+\}')) { Add-LangTemplate $pack $id $out } else { $pack.Map[$id] = $out }
        $pack.N = [int]$pack.N + 1
    }
    # ayni on ekli sablonlarda uzun (ayrintili) olan once denenir
    foreach ($k in @($pack.Tpl.Keys)) {
        $l = $pack.Tpl[$k]
        if ($l.Count -gt 1) {
            $sorted = @($l | Sort-Object -Property @{ Expression = { -[int]$_.W } })
            $nl = New-Object System.Collections.ArrayList
            foreach ($e in $sorted) { [void]$nl.Add($e) }
            $pack.Tpl[$k] = $nl
        }
    }
    return $pack
}

# Ust bilgi satirlarini okur (dosyanin tamamini yuklemeden)
function Read-LangHeader([string]$Path) {
    $meta = @{}
    $sr = $null
    try {
        $sr = New-Object System.IO.StreamReader($Path, [System.Text.Encoding]::UTF8)
        while ($true) {
            $ln = $sr.ReadLine()
            if ($null -eq $ln) { break }
            if ($ln.Length -eq 0) { continue }
            if ($ln[0] -ne '#') { break }
            $m = [regex]::Match($ln, '^#\s*([A-Za-z]+)\s*:\s*(.*)$')
            if ($m.Success) { $meta[$m.Groups[1].Value.ToLowerInvariant()] = $m.Groups[2].Value.Trim() }
        }
    } catch { } finally { if ($null -ne $sr) { $sr.Dispose() } }
    return $meta
}

# Kullanilabilir diller: Turkce (kaynak) + bulunan dil dosyalari. Ayni kodda kullanici dosyasi uygulama dosyasinin yerine gecer.
# Donus listesi acilir (virgulsuz); cagiran @(Get-LangList) yazar.
function Get-LangList([bool]$Refresh = $false) {
    if (-not $Refresh -and $null -ne $script:LangList) { return $script:LangList }
    $res = New-Object System.Collections.ArrayList
    [void]$res.Add(@{ Code = 'tr'; Native = 'T' + [char]0x00FC + 'rk' + [char]0x00E7 + 'e'; English = 'Turkish'; Rtl = $false; Tag = 'tr-TR'; Match = 'tr'; Path = ''; Coverage = 100; User = $false })
    $byCode = @{}
    $folders = @(Get-LangFolders)
    $isUser = $false
    foreach ($dir in $folders) {
        if (-not (Test-Path -LiteralPath $dir -PathType Container)) { $isUser = $true; continue }
        foreach ($f in @(Get-ChildItem -LiteralPath $dir -Filter '*.lang' -File -ErrorAction SilentlyContinue)) {
            $code = $f.BaseName.ToLowerInvariant()
            if ($code -cnotmatch '^[a-z]{2,3}(-[a-z0-9]{2,8})?$' -or $code -eq 'tr') { continue }
            $h = Read-LangHeader $f.FullName
            $nm = [string]$h['native']
            if ($nm -eq '') { $nm = $code }
            $en = [string]$h['name']
            if ($en -eq '') { $en = $code }
            $rtl = ([string]$h['rtl'] -eq '1')
            $tag = [string]$h['tag']
            if ($tag -eq '') { $tag = $code }
            $mt = [string]$h['match']
            if ($mt -eq '') { $mt = $code }
            $cov = 0
            try { $cov = [int]$h['coverage'] } catch { $cov = 0 }
            $byCode[$code] = @{ Code = $code; Native = $nm; English = $en; Rtl = $rtl; Tag = $tag; Match = $mt.ToLowerInvariant(); Path = $f.FullName; Coverage = $cov; User = $isUser }
        }
        $isUser = $true
    }
    foreach ($k in @($byCode.Keys | Sort-Object)) { [void]$res.Add($byCode[$k]) }
    $script:LangList = $res
    return $res
}

# Bir kulturun (ornek "de-DE", "zh-Hans-CN") en uygun dil kodunu bulur; yoksa ''
function Find-LangForCulture([string]$CultureName) {
    $c = $CultureName.ToLowerInvariant()
    if ($c -eq '') { return '' }
    $best = ''
    $bestLen = 0
    foreach ($l in @(Get-LangList)) {
        foreach ($m in ([string]$l.Match -split ',')) {
            $mm = $m.Trim()
            if ($mm -eq '') { continue }
            if (($c -eq $mm -or $c.StartsWith(($mm + '-'), [System.StringComparison]::Ordinal)) -and $mm.Length -gt $bestLen) { $best = [string]$l.Code; $bestLen = $mm.Length }
        }
    }
    return $best
}

function Get-SystemLangCode {
    $name = ''
    try { $name = [System.Globalization.CultureInfo]::CurrentUICulture.Name } catch { $name = '' }
    $code = Find-LangForCulture $name
    if ($code -ne '') { return $code }
    return 'en'
}

# Ayar degeri (auto | kod) -> kullanilacak dil kodu. Bilinmeyen kod otomatik gibi islenir.
function Resolve-LangCode([string]$Want) {
    $w = $Want.Trim().ToLowerInvariant()
    if ($w -eq '' -or $w -eq 'auto') { $w = Get-SystemLangCode }
    if ($w -eq 'tr') { return 'tr' }
    foreach ($l in @(Get-LangList)) { if ([string]$l.Code -eq $w) { return $w } }
    $c = Find-LangForCulture $w
    if ($c -ne '') { return $c }
    foreach ($l in @(Get-LangList)) { if ([string]$l.Code -eq 'en') { return 'en' } }
    return 'tr'
}

function Import-LangPackFile([string]$Code) {
    foreach ($l in @(Get-LangList)) {
        if ([string]$l.Code -ne $Code -or [string]$l.Path -eq '') { continue }
        try {
            $txt = [System.IO.File]::ReadAllText([string]$l.Path, [System.Text.Encoding]::UTF8)
            return (Read-LangPack $txt $Code)
        } catch {
            try { Write-WhLog ('Dil dosyasi okunamad' + [char]0x0131 + ' (' + $Code + '): ' + $_.Exception.Message) 'WARN' } catch { }
        }
    }
    return $null
}

# Etkin dili ayarlar. 'tr' kaynak dildir (cevri yapilmaz).
function Set-LangActive([string]$Code) {
    $script:LangCache = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([System.StringComparer]::Ordinal)
    $script:LangPrimary = $null
    $script:LangFallback = $null
    $script:LangOn = $false
    $script:LangRtl = $false
    $script:LangPctStyle = 0
    $script:LangUpperCulture = $null
    $script:LangCode = 'tr'
    $script:LangTag = 'tr-TR'
    $script:LangName = 'T' + [char]0x00FC + 'rk' + [char]0x00E7 + 'e'
    if ($Code -eq 'tr') { return }
    $p = Import-LangPackFile $Code
    if ($null -eq $p) { return }
    $script:LangPrimary = $p
    $script:LangCode = $Code
    $script:LangPctStyle = Get-LangPercentStyle $Code
    foreach ($l in @(Get-LangList)) {
        if ([string]$l.Code -eq $Code) { $script:LangRtl = [bool]$l.Rtl; $script:LangTag = [string]$l.Tag; $script:LangName = [string]$l.Native }
    }
    try { $script:LangUpperCulture = [System.Globalization.CultureInfo]::GetCultureInfo([string]$script:LangTag) } catch { $script:LangUpperCulture = $null }
    if ($Code -ne 'en') { $script:LangFallback = Import-LangPackFile 'en' }
    $script:LangOn = $true
}

# Acilista bir kez: komut satiri (-Dil), ortam (MM_DIL), ayar (Language) sirasiyla bakilir
function Initialize-Lang {
    $want = ''
    try { $want = [string]$script:Settings.Language } catch { $want = '' }
    $env1 = ''
    try { $env1 = [string]$env:MM_DIL } catch { $env1 = '' }
    if ($env1 -ne '') { $want = $env1 }
    $arg = ''
    try { $arg = [string]$Dil } catch { $arg = '' }
    if ($arg -ne '') { $want = $arg }
    $code = 'tr'
    try { $code = Resolve-LangCode $want } catch { $code = 'tr' }
    try { Set-LangActive $code } catch { $script:LangOn = $false }
    $tr = ''
    try { $tr = [string]$env:MM_DIL_IZLE } catch { $tr = '' }
    if ($tr -eq '1' -and $script:LangOn) { Enable-LangTrack }
}

function Enable-LangTrack {
    $script:LangTrack = $true
    $script:LangMiss = New-Object 'System.Collections.Generic.Dictionary[string,int]' ([System.StringComparer]::Ordinal)
    $script:LangSeen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    $script:LangOut = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
}

function Find-LangIn($Pack, [string]$s, [int]$Depth) {
    $v = $null
    if ($Pack.Map.TryGetValue($s, [ref]$v)) { return $v }
    # bastaki ve sondaki bosluklar korunur
    $ls = $s.Length - $s.TrimStart().Length
    $te = $s.Length - $s.TrimEnd().Length
    if (($ls + $te) -gt 0 -and ($ls + $te) -lt $s.Length) {
        $core = $s.Substring($ls, $s.Length - $ls - $te)
        if ($Pack.Map.TryGetValue($core, [ref]$v)) { return ($s.Substring(0, $ls) + $v + $s.Substring($s.Length - $te)) }
    }
    if ($Pack.NTpl -gt 0 -and $Depth -lt 4) {
        $max = $s.Length
        if ($max -gt $script:LangKeyLen) { $max = $script:LangKeyLen }
        for ($n = 0; $n -le $max; $n++) {
            $list = $null
            if ($Pack.Tpl.TryGetValue($s.Substring(0, $n), [ref]$list)) {
                foreach ($e in $list) {
                    if ($e.Suf.Length -gt 0 -and -not $s.EndsWith($e.Suf, [System.StringComparison]::Ordinal)) { continue }
                    if ($e.Lit.Length -gt 1 -and $s.IndexOf($e.Lit, [System.StringComparison]::Ordinal) -lt 0) { continue }
                    $rx = $e.Rx
                    if ($null -eq $rx) {
                        try { $rx = New-Object System.Text.RegularExpressions.Regex([string]$e.Src, [System.Text.RegularExpressions.RegexOptions]::Singleline) } catch { $rx = $false }
                        $e.Rx = $rx
                    }
                    if ($rx -is [bool]) { continue }
                    $m = $rx.Match($s)
                    if ($m.Success) { return (Format-LangTemplate $e $m $Depth) }
                }
            }
        }
    }
    return $null
}

# Sablonun yer tutucularini yakalanan parcalarla (onlar da cevrilerek) doldurur
function Format-LangTemplate($E, $M, [int]$Depth) {
    $out = [string]$E.Out
    $sb = New-Object System.Text.StringBuilder
    $pos = 0
    foreach ($x in [regex]::Matches($out, '\{(\d+)\}')) {
        [void]$sb.Append($out.Substring($pos, $x.Index - $pos))
        $g = $M.Groups['g' + $x.Groups[1].Value]
        if ($g.Success) {
            $part = [string]$g.Value
            $tp = $null
            if ($part.Length -ge 2) { $tp = Find-LangText $part ($Depth + 1) }
            if ($null -ne $tp) { [void]$sb.Append($tp) } else { [void]$sb.Append($part) }
        } else { [void]$sb.Append($x.Value) }
        $pos = $x.Index + $x.Length
    }
    [void]$sb.Append($out.Substring($pos))
    return $sb.ToString()
}

# Yalnizca kayitli ceviriler: birebir, bastaki/sondaki bosluk ve sablon (secili dil, sonra Ingilizce yedek)
function Find-LangDirect([string]$s, [int]$Depth) {
    $r = $null
    if ($null -ne $script:LangPrimary) { $r = Find-LangIn $script:LangPrimary $s $Depth; if ($null -ne $r) { return $r } }
    if ($null -ne $script:LangFallback) { $r = Find-LangIn $script:LangFallback $s $Depth; if ($null -ne $r) { return $r } }
    return $null
}

# Cumle sonu ve ayirac noktalama: Cince ve Japoncada tam genislikli isaretler kullanilir
function Get-LangPunct([string]$P) {
    $c = [string]$script:LangCode
    if ($c -eq 'zh' -or $c -eq 'zh-hant' -or $c -eq 'ja') {
        if ($P -eq '.') { return [string][char]0x3002 }
        if ($P -eq ';') { return [string][char]0xFF1B }
    }
    return $P
}

# Metnin cevirisini bulur; yoksa $null. Sonucun eksiksiz cevrilip cevrilmedigi $script:LangFull'a yazilir:
# kayitli (birebir, bosluk, sablon) ceviri eksiksizdir; parcalara bolunerek bulunan ceviri ancak cevrilmesi gereken her parca bulunduysa eksiksizdir.
# Birden cok bolme yolu varsa ilk eksiksiz sonuc doner; hicbiri eksiksiz degilse ilk kismi sonuc doner.
function Find-LangText([string]$s, [int]$Depth) {
    $script:LangFull = $true
    $r = Find-LangDirect $s $Depth
    if ($null -ne $r) { return $r }
    $script:LangFull = $false
    if ($Depth -ge 3 -or $s.Length -lt 2) { return $null }
    $nd = $Depth + 1
    $best = $null
    $res = $null
    $tf = $false
    $n1 = $s.Length

    # yalnizca buyuk/kucuk harf farki olan metin ("Yedek ve Kurtarma" / "Yedek ve kurtarma" / "YEDEK VE KURTARMA")
    if ($n1 -ge 3 -and $n1 -le 160 -and $s.IndexOf([char]10) -lt 0) {
        $fz = Find-LangFolded $s
        if ($null -ne $fz) {
            if ($script:LangUpperRx.IsMatch($s) -and -not $script:LangLowerRx.IsMatch($s)) { $fz = Convert-LangUpper $fz }
            $script:LangFull = $true
            return $fz
        }
    }

    # cok satirli metin: her satir ayri cevrilir
    if ($s.IndexOf([char]10) -ge 0) {
        $lines = $s -split "`n"
        $any = $false
        $all = $true
        $outl = New-Object System.Collections.ArrayList
        foreach ($ln in $lines) {
            $core = $ln
            $cr = ''
            if ($core.Length -gt 0 -and $core[$core.Length - 1] -eq [char]13) { $core = $core.Substring(0, $core.Length - 1); $cr = "`r" }
            $t = $null
            if ($core.Length -ge 2) { $t = Find-LangText $core $nd; $tf = $script:LangFull }
            if ($null -ne $t) { $any = $true; if (-not $tf) { $all = $false }; [void]$outl.Add($t + $cr) }
            else { if ($script:LangLetterRx.IsMatch($core)) { $all = $false }; [void]$outl.Add($ln) }
        }
        if ($any) {
            $res = ($outl.ToArray() -join "`n")
            if ($all) { $script:LangFull = $true; return $res }
            if ($null -eq $best) { $best = $res }
        }
    }
    if ($n1 -gt 700) { return $best }

    # "Parca  ·  Parca" biciminde birlesik metin (etiket + kategori gibi): her parca ayri cevrilir
    if ($s.IndexOf([char]0x00B7) -ge 0) {
        foreach ($sep in @(('  ' + [char]0x00B7 + '  '), (' ' + [char]0x00B7 + ' '))) {
            if ($s.IndexOf($sep, [System.StringComparison]::Ordinal) -lt 0) { continue }
            $segs = $s.Split(@($sep), [System.StringSplitOptions]::None)
            if ($segs.Count -lt 2) { continue }
            $anySeg = $false
            $allSeg = $true
            $outSeg = New-Object System.Collections.ArrayList
            foreach ($sg in $segs) {
                $ts = $null
                if ($sg.Length -ge 2) { $ts = Find-LangText $sg $nd; $tf = $script:LangFull }
                if ($null -ne $ts) { $anySeg = $true; if (-not $tf) { $allSeg = $false }; [void]$outSeg.Add($ts) }
                else { if ($script:LangLetterRx.IsMatch($sg)) { $allSeg = $false }; [void]$outSeg.Add($sg) }
            }
            if ($anySeg) {
                $res = ($outSeg.ToArray() -join $sep)
                if ($allSeg) { $script:LangFull = $true; return $res }
                if ($null -eq $best) { $best = $res }
            }
            break
        }
    }

    # onek isareti (">>> ", "→  " gibi): onek korunur, kalan metin cevrilir
    $pm = $script:LangPrefixRx.Match($s)
    if ($pm.Success -and $pm.Groups[2].Value.Length -ge 2) {
        $tp = Find-LangText $pm.Groups[2].Value $nd
        $tf = $script:LangFull
        if ($null -ne $tp) {
            $res = $pm.Groups[1].Value + $tp
            if ($tf) { $script:LangFull = $true; return $res }
            if ($null -eq $best) { $best = $res }
        }
    }

    # "SS:DD:SS  SEVIYE  ileti" gunluk satiri: yalnizca ileti cevrilir
    if ($n1 -ge 14 -and $s[2] -eq ':' -and $s[5] -eq ':') {
        $lm = $script:LangLogRx.Match($s)
        if ($lm.Success) {
            $lt = Find-LangText $lm.Groups[2].Value $nd
            $tf = $script:LangFull
            if ($null -ne $lt) {
                $res = $lm.Groups[1].Value + $lt
                if ($tf) { $script:LangFull = $true; return $res }
                if ($null -eq $best) { $best = $res }
            }
        }
    }

    # "metin  [not]" biciminde sona eklenmis koseli parantezli not: metin ve not parcalari ayri cevrilir
    if ($s[$n1 - 1] -eq ']' -and $s.IndexOf('  [', [System.StringComparison]::Ordinal) -gt 0) {
        $bm = $script:LangBracketRx.Match($s)
        if ($bm.Success) {
            $hd = $bm.Groups[1].Value
            $tg = $bm.Groups[2].Value
            $hdT = Find-LangText $hd $nd
            $hf = $script:LangFull
            $tgT = Find-LangTag $tg $nd
            $gf = $script:LangFull
            if ($null -ne $hdT -or $null -ne $tgT) {
                $full = ($null -ne $hdT -and $hf -and $null -ne $tgT -and $gf)
                if ($null -eq $hdT) { $hdT = $hd }
                if ($null -eq $tgT) { $tgT = $tg }
                $res = ($hdT + '  [' + $tgT + ']')
                if ($full) { $script:LangFull = $true; return $res }
                if ($null -eq $best) { $best = $res }
            }
        }
    }

    # "sol " + ok + " sag" biciminde kural ya da yonlendirme: iki yan ayri cevrilir
    $arrow = ' ' + [char]0x2192 + ' '
    $ai = $s.IndexOf($arrow, [System.StringComparison]::Ordinal)
    if ($ai -gt 0 -and $ai + 3 -lt $n1) {
        $la = $s.Substring(0, $ai)
        $ra = $s.Substring($ai + 3)
        $laT = $null; $raT = $null; $lf = $true; $rf = $true
        if ($la.Length -ge 2) { $laT = Find-LangText $la $nd; $lf = $script:LangFull }
        if ($ra.Length -ge 2) { $raT = Find-LangText $ra $nd; $rf = $script:LangFull }
        if ($null -ne $laT -or $null -ne $raT) {
            $full = ($null -ne $laT -and $lf -and $null -ne $raT -and $rf)
            if ($null -eq $laT) { $laT = $la }
            if ($null -eq $raT) { $raT = $ra }
            $res = ($laT + $arrow + $raT)
            if ($full) { $script:LangFull = $true; return $res }
            if ($null -eq $best) { $best = $res }
        }
    }

    # cumle sonundaki nokta: nokta olmadan kayitli metin bulunursa sonuna dilin cumle sonu isareti eklenir
    if ($n1 -ge 4 -and $s[$n1 - 1] -eq '.' -and $s[$n1 - 2] -ne '.') {
        $tp = Find-LangText $s.Substring(0, $n1 - 1) $nd
        $tf = $script:LangFull
        if ($null -ne $tp) {
            $res = $tp
            $lc = [int]$tp[$tp.Length - 1]
            if ($lc -ne 46 -and $lc -ne 33 -and $lc -ne 63 -and $lc -ne 0x2026 -and $lc -ne 0x3002 -and $lc -ne 0xFF01 -and $lc -ne 0xFF1F) { $res = $tp + (Get-LangPunct '.') }
            if ($tf) { $script:LangFull = $true; return $res }
            if ($null -eq $best) { $best = $res }
        }
    }

    # "Metin (3)" ya da "Metin (not)" biciminde parantezli ek: metin ve (sayi degilse) ek cevrilir, sayac korunur
    if ($n1 -ge 6 -and $s[$n1 - 1] -eq ')') {
        $cm = $script:LangCountRx.Match($s)
        if ($cm.Success) {
            $hdc = Find-LangText $cm.Groups[1].Value $nd
            $hcf = $script:LangFull
            $tl = $cm.Groups[2].Value
            $tlT = $null
            if ($tl.Length -ge 3 -and -not [char]::IsDigit($tl[0])) { $tlT = Find-LangTag $tl $nd }
            if ($null -ne $hdc -or $null -ne $tlT) {
                $full = ($null -ne $hdc -and $hcf)
                if ($null -eq $hdc) { $hdc = $cm.Groups[1].Value }
                if ($null -eq $tlT) { $tlT = $tl }
                $res = ($hdc + ' (' + $tlT + ')')
                if ($full) { $script:LangFull = $true; return $res }
                if ($null -eq $best) { $best = $res }
            }
        }
    }

    # "Metin..." biciminde sonu uc nokta olan ilerleme metni
    if ($n1 -ge 6) {
        $el = ''
        if ($s.EndsWith('...', [System.StringComparison]::Ordinal)) { $el = '...' } elseif ($s[$n1 - 1] -eq [char]0x2026) { $el = [string][char]0x2026 }
        if ($el.Length -gt 0) {
            $hde = Find-LangText $s.Substring(0, $n1 - $el.Length) $nd
            $tf = $script:LangFull
            if ($null -ne $hde) {
                $res = $hde + $el
                if ($tf) { $script:LangFull = $true; return $res }
                if ($null -eq $best) { $best = $res }
            }
        }
    }

    # "Etiket: deger" ya da "Ad: aciklama": etiket cevrilir (iki nokta ile ya da iki noktasiz kayitli olabilir), kalan metin bulunabilirse cevrilir
    if ($n1 -ge 6) {
        $ci = $s.IndexOf(': ', [System.StringComparison]::Ordinal)
        $guard = 0
        while ($ci -gt 1 -and $ci + 2 -lt $n1 -and $guard -lt 3) {
            $guard++
            $labT = Find-LangDirect $s.Substring(0, $ci + 1) $nd
            if ($null -eq $labT) {
                $labN = Find-LangText $s.Substring(0, $ci) $nd
                if ($null -ne $labN -and $script:LangFull) { $labT = $labN + ':' }
            }
            if ($null -ne $labT) {
                $rest = $s.Substring($ci + 2)
                $restT = $null
                $rf = $false
                if ($rest.Length -ge 2) { $restT = Find-LangText $rest $nd; $rf = $script:LangFull }
                $full = ($null -ne $restT -and $rf)
                if ($null -eq $restT) { $restT = $rest }
                $glue = ' '
                if ($labT[$labT.Length - 1] -eq [char]0xFF1A) { $glue = '' }
                $res = ($labT + $glue + $restT)
                if ($full) { $script:LangFull = $true; return $res }
                if ($null -eq $best) { $best = $res }
                break
            }
            $ci = $s.IndexOf(': ', $ci + 2, [System.StringComparison]::Ordinal)
        }
    }

    # birden cok cumleden ya da ";" ile ayrilmis parcalardan olusan metin: her parca (ya da ardisik parcalar) ayri cevrilir
    if ($n1 -ge 14) {
        $jr = Find-LangJoined $s '. ' $Depth
        $jf = $script:LangFull
        if ($null -ne $jr) {
            if ($jf) { $script:LangFull = $true; return $jr }
            if ($null -eq $best) { $best = $jr }
        }
        if ($s.IndexOf('; ', [System.StringComparison]::Ordinal) -gt 0) {
            $jr = Find-LangJoined $s '; ' $Depth
            $jf = $script:LangFull
            if ($null -ne $jr) {
                if ($jf) { $script:LangFull = $true; return $jr }
                if ($null -eq $best) { $best = $jr }
            }
        }
    }

    # TAMAMI BUYUK HARFLI baslik ("YEDEK VE KURTARMA"): kucuk harfli karsiligi cevrilir, sonuc buyuk harfe cevrilir
    if ($n1 -ge 3 -and $n1 -le 80 -and $script:LangUpperRx.IsMatch($s) -and -not $script:LangLowerRx.IsMatch($s)) {
        $lo = Convert-LangTrLower $s
        $up = Find-LangText (Convert-LangTrUpperFirst $lo) $nd
        $uf = $script:LangFull
        if ($null -eq $up) { $up = Find-LangText $lo $nd; $uf = $script:LangFull }
        if ($null -ne $up) {
            $res = Convert-LangUpper $up
            if ($uf) { $script:LangFull = $true; return $res }
            if ($null -eq $best) { $best = $res }
        }
    }
    $script:LangFull = $false
    return $best
}

# Ayiracla (". " ya da "; ") birlestirilmis parcalari cevirir. Her konumda once en uzun ardisik parca grubu aranir
# (kataloga birden cok cumleli metin olarak girmis olabilir); bulunamayan parca oldugu gibi kalir.
function Find-LangJoined([string]$s, [string]$Sep, [int]$Depth) {
    $script:LangFull = $false
    $parts = $s.Split(@($Sep), [System.StringSplitOptions]::None)
    $n = $parts.Count
    if ($n -lt 2 -or $n -gt 14) { return $null }
    $punct = $Sep.Substring(0, 1)
    $pOut = Get-LangPunct $punct
    $outp = New-Object System.Collections.ArrayList
    $any = $false
    $all = $true
    $i = 0
    while ($i -lt $n) {
        $hit = $null
        $hitJ = $i
        $hitFull = $false
        for ($j = $n - 1; $j -ge $i; $j--) {
            if ($i -eq 0 -and $j -eq $n - 1) { continue }
            $core = ($parts[$i..$j] -join $Sep)
            $last = ($j -eq $n - 1)
            $multi = ($j -gt $i)
            $t = $null
            $tfull = $true
            if (-not $last) {
                if ($multi) { $t = Find-LangDirect ($core + $punct) ($Depth + 1) } else { $t = Find-LangText ($core + $punct) ($Depth + 1); $tfull = $script:LangFull }
            }
            if ($null -eq $t -and $core.Length -ge 3) {
                $t0 = $null
                if ($multi) { $t0 = Find-LangDirect $core ($Depth + 1); $tfull = $true } else { $t0 = Find-LangText $core ($Depth + 1); $tfull = $script:LangFull }
                if ($null -ne $t0) {
                    $t = $t0
                    if (-not $last) {
                        $lc = [int]$t0[$t0.Length - 1]
                        if ($lc -ne [int]$punct[0] -and $lc -ne [int]$pOut[0]) { $t = $t0 + $pOut }
                    }
                }
            }
            if ($null -ne $t) { $hit = $t; $hitJ = $j; $hitFull = $tfull; break }
        }
        if ($null -ne $hit) {
            $any = $true
            if (-not $hitFull) { $all = $false }
            [void]$outp.Add($hit)
            $i = $hitJ + 1
        } else {
            $own = $parts[$i]
            if ($i -lt $n - 1) { $own = $own + $punct }
            if ($script:LangLetterRx.IsMatch($own)) { $all = $false }
            [void]$outp.Add($own)
            $i++
        }
    }
    if (-not $any) { $script:LangFull = $false; return $null }
    $script:LangFull = $all
    return ($outp.ToArray() -join ' ')
}

# Turkce buyuk/kucuk harf donusumu (kulturden bagimsiz): I -> dotless i, dotted I -> i
function Convert-LangTrLower([string]$s) {
    return $s.Replace([string][char]0x0130, 'i').Replace('I', [string][char]0x0131).ToLowerInvariant()
}

function Convert-LangTrUpperFirst([string]$s) {
    if ($s.Length -eq 0) { return $s }
    $c = [int]$s[0]
    $u = ([string]$s[0]).ToUpperInvariant()
    if ($c -eq 105) { $u = [string][char]0x0130 } elseif ($c -eq 0x0131) { $u = 'I' }
    return ($u + $s.Substring(1))
}

# Buyuk/kucuk harfi farkli yazilmis metinler icin kucuk harfe indirilmis dizin (ilk kullanimda kurulur): secili dil, sonra Ingilizce yedek
function Find-LangFolded([string]$s) {
    $k = Convert-LangTrLower $s.Trim()
    if ($k.Length -lt 3) { return $null }
    foreach ($p in @($script:LangPrimary, $script:LangFallback)) {
        if ($null -eq $p) { continue }
        if ($null -eq $p.Fold) {
            $f = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([System.StringComparer]::Ordinal)
            foreach ($kv in $p.Map.GetEnumerator()) {
                $lk = Convert-LangTrLower ([string]$kv.Key)
                if (-not $f.ContainsKey($lk)) { $f[$lk] = [string]$kv.Value }
            }
            $p.Fold = $f
        }
        $v = $null
        if ($p.Fold.TryGetValue($k, [ref]$v)) { return $v }
    }
    return $null
}

# Cevrilen basligi etkin dilin kulturune gore buyuk harfe cevirir (Cince, Japonca, Arapca gibi buyuk/kucuk harfi olmayan dillerde degismez)
function Convert-LangUpper([string]$s) {
    $cu = $script:LangUpperCulture
    if ($null -eq $cu) { return $s.ToUpperInvariant() }
    return $s.ToUpper($cu)
}

# Koseli parantez ici not: butun olarak, yoksa ", " ile ayrilmis parcalar halinde cevrilir
function Find-LangTag([string]$s, [int]$Depth) {
    $r = Find-LangText $s $Depth
    if ($null -ne $r) { return $r }
    $script:LangFull = $false
    if ($Depth -ge 3) { return $null }
    $i = $s.IndexOf(', ', [System.StringComparison]::Ordinal)
    while ($i -gt 0) {
        $left = $s.Substring(0, $i)
        $lt = Find-LangText $left ($Depth + 1)
        $lf = $script:LangFull
        if ($null -ne $lt) {
            $right = $s.Substring($i + 2)
            $rt = Find-LangTag $right ($Depth + 1)
            $rf = $script:LangFull
            if ($null -eq $rt) { $rt = $right; $rf = $false }
            $script:LangFull = ($lf -and $rf)
            return ($lt + ', ' + $rt)
        }
        $i = $s.IndexOf(', ', $i + 2, [System.StringComparison]::Ordinal)
    }
    $script:LangFull = $false
    return $null
}

function Add-LangMiss([string]$s) {
    if ($null -eq $script:LangMiss) { return }
    if (-not [regex]::IsMatch($s, '[^\W\d_]{2}')) { return }
    # daha once cevrilmis bir ciktinin yeniden Tr'den gecmesi eksik sayilmaz
    if ($null -ne $script:LangOut -and $script:LangOut.Contains($s)) { return }
    # boyut, hiz, sicaklik gibi yalnizca olcu degeri olan ve dosya yolu olan metinler cevrilmez
    if ([regex]::IsMatch($s, '^[\d.,\s]+(?:[KMGT]i?B(?:/s)?|[Mm]b/s|[Kk]b/s|%|ms|s|MHz|GHz|W|V|rpm)$')) { return }
    if ([regex]::IsMatch($s, '^[A-Za-z]:\\')) { return }
    $n = 0
    if ($script:LangMiss.TryGetValue($s, [ref]$n)) { $script:LangMiss[$s] = $n + 1 } else { $script:LangMiss[$s] = 1 }
}

# Yuzde yazimi: Turkcede "%40"; Almanca, Fransizca, Ispanyolca, Rusca gibi dillerde "40 %" (bolunmez bosluk),
# Ingilizce, Cince, Japonca, Arapca gibi dillerde "40%"
$script:LangPctRx = New-Object System.Text.RegularExpressions.Regex('(?<![\p{L}\p{N}\\/%._])%(\d+(?:[.,]\d+)?)(?![\p{L}\p{N}\x27’])')

function Get-LangPercentStyle([string]$Code) {
    $c = $Code.ToLowerInvariant()
    $i = $c.IndexOf('-')
    if ($i -gt 0) { $c = $c.Substring(0, $i) }
    if ($c -eq 'tr') { return 0 }
    foreach ($x in @('de', 'fr', 'es', 'ru', 'pl', 'cs', 'sk', 'sl', 'hr', 'sr', 'bg', 'uk', 'sv', 'nb', 'no', 'da', 'fi', 'nl', 'hu', 'ro', 'el', 'lt', 'lv', 'et')) {
        if ($c -eq $x) { return 2 }
    }
    return 1
}

function Convert-LangPercent([string]$s) {
    if ([int]$script:LangPctStyle -eq 0 -or $s.IndexOf('%') -lt 0) { return $s }
    $rep = '${1}%'
    if ([int]$script:LangPctStyle -eq 2) { $rep = '${1}' + [string][char]0x00A0 + '%' }
    return $script:LangPctRx.Replace($s, $rep)
}

# Sayisal degeri etkin dilin yuzde bicimiyle yazar: Format-Percent 40 -> %40 / 40% / 40 %
function Format-Percent($V) { return (Convert-LangPercent ('%' + [string]$V)) }

# Sagdan sola dillerde yalnizca Latin harf ve rakamdan olusan cok sozcuklu metinler (surum, birim, donanim adi gibi)
# sozcuk sirasi ters dizilir ("Windows 11 Home" -> "Home 11 Windows"); soldan saga isaretiyle (LRM) sarilarak duzeltilir
$script:LangBidiRx = New-Object System.Text.RegularExpressions.Regex('[֐-ࣿיִ-﷿ﹰ-﻿]')

function Convert-LangBidi([string]$s) {
    if ($s.Length -lt 3 -or $s.Length -gt 600) { return $s }
    $c0 = $s[0]
    if ($c0 -eq [char]0x200E -or $c0 -eq [char]0x200F) { return $s }
    if ($script:LangBidiRx.IsMatch($s)) { return $s }
    if (-not [regex]::IsMatch($s, '[A-Za-z0-9]')) { return $s }
    if (-not [regex]::IsMatch($s, '[\s.:;!?)\]]')) { return $s }
    return ([string][char]0x200E + $s + [string][char]0x200E)
}

# Arayuz metnini etkin dile cevirir. Turkce secili ya da metin dize degilse oldugu gibi doner.
function Tr($Text) {
    if (-not $script:LangOn) { return $Text }
    if ($Text -isnot [string]) { return $Text }
    $s = [string]$Text
    if ($s.Length -lt 2) { return $s }
    $c = $script:LangCache
    $hit = $null
    if (-not $script:LangTrack -and $null -ne $c -and $c.TryGetValue($s, [ref]$hit)) { return $hit }
    $r = Find-LangText $s 0
    if ($null -ne $r) {
        if ($r.IndexOf('%') -ge 0) { $r = Convert-LangPercent $r }
        if ($script:LangRtl) { $r = Convert-LangBidi $r }
        if ($script:LangTrack) { if (-not $script:LangFull -and [regex]::IsMatch($r, '[\u011F\u0131\u0130\u015E\u015F\u011E]')) { Add-LangMiss $s }; [void]$script:LangSeen.Add($r); [void]$script:LangOut.Add($r) } elseif ($null -ne $c -and $s.Length -le 400) { if ($c.Count -ge 20000) { $c.Clear() }; $c[$s] = $r }
        return $r
    }
    $s2 = $s
    if ($s.IndexOf('%') -ge 0) { $s2 = Convert-LangPercent $s2 }
    if ($script:LangRtl) { $s2 = Convert-LangBidi $s2 }
    if ($script:LangTrack) { Add-LangMiss $s; [void]$script:LangSeen.Add($s2) } elseif ($null -ne $c -and $s.Length -le 400) { if ($c.Count -ge 20000) { $c.Clear() }; $c[$s] = $s2 }
    return $s2
}

# Cevirili metne ornekle degerler koyar: Format-Tr 'Silindi: {0} dosya' 5
function Format-Tr([string]$Id, $Args0 = $null, $Args1 = $null, $Args2 = $null) {
    $t = Tr $Id
    $vals = @($Args0, $Args1, $Args2)
    for ($i = 0; $i -lt 3; $i++) {
        if ($t.Contains('{' + [string]$i + '}')) { $t = $t.Replace('{' + [string]$i + '}', [string]$vals[$i]) }
    }
    return $t
}

# ---------------- XAML ----------------
# Metin ozniteliklerinin degerlerini cevirir ("{" ile baslayan baglamalar ve @@Yer@@ tutucular dokunulmaz)
$script:LangXamlRx = New-Object System.Text.RegularExpressions.Regex('(\b(?:Text|Content|ToolTip|Header|Title|Watermark)=")([^"]*)(")')

function ConvertTo-XamlAttr([string]$s) {
    $e = $s.Replace('&', '&amp;').Replace('<', '&lt;').Replace('"', '&quot;')
    if ($e.IndexOf([char]10) -ge 0 -or $e.IndexOf([char]13) -ge 0 -or $e.IndexOf([char]9) -ge 0) { $e = $e.Replace("`r", '&#13;').Replace("`n", '&#10;').Replace("`t", '&#9;') }
    return $e
}

function Convert-XamlText([string]$Xaml) {
    if (-not $script:LangOn) { return $Xaml }
    $sb = New-Object System.Text.StringBuilder
    $pos = 0
    foreach ($m in $script:LangXamlRx.Matches($Xaml)) {
        $val = $m.Groups[2].Value
        if ($val.Length -lt 2 -or $val[0] -eq [char]123 -or $val.Contains('@@')) { continue }
        $plain = [System.Net.WebUtility]::HtmlDecode($val)
        $tr = Tr $plain
        if ([string]$tr -ceq $plain) { continue }
        [void]$sb.Append($Xaml.Substring($pos, $m.Groups[2].Index - $pos))
        [void]$sb.Append((ConvertTo-XamlAttr ([string]$tr)))
        $pos = $m.Groups[2].Index + $m.Groups[2].Length
    }
    if ($pos -eq 0) { return $Xaml }
    [void]$sb.Append($Xaml.Substring($pos))
    return $sb.ToString()
}

# Pencerenin dil etiketi (yazi tipi secimi icin) ve yazim yonu
function Set-WindowLanguage($Win) {
    if ($null -eq $Win -or -not $script:LangOn) { return }
    try { $Win.Language = [System.Windows.Markup.XmlLanguage]::GetLanguage($script:LangTag) } catch { }
    if ($script:LangRtl) { try { $Win.FlowDirection = [System.Windows.FlowDirection]::RightToLeft } catch { } }
}

# XAML metnini ceviri uygulayarak nesneye cevirir (XamlReader.Parse yerine kullanilir)
function Read-LocalXaml([string]$Xaml) {
    $x = $Xaml
    if ($script:LangOn) { $x = Convert-XamlText $Xaml }
    $obj = [System.Windows.Markup.XamlReader]::Parse($x)
    if ($script:LangOn -and $obj -is [System.Windows.Window]) { Set-WindowLanguage $obj }
    return , $obj
}

# ---------------- gunluk satiri ----------------
# "SS:DD:SS  SEVIYE  ileti" bicimindeki satirda yalnizca ileti cevrilir
function Convert-LogLineText([string]$Line) {
    if (-not $script:LangOn -or $Line.Length -lt 14) { return $Line }
    $m = [regex]::Match($Line, '^(\d\d:\d\d:\d\d\s+\S+\s+)(.+)$')
    if ($m.Success) { return ($m.Groups[1].Value + (Tr $m.Groups[2].Value)) }
    return (Tr $Line)
}

# ---------------- kalite denetimi ----------------
function Save-LangMiss {
    if ($null -eq $script:LangMiss) { return '' }
    $path = Join-Path ([System.IO.Path]::GetTempPath()) 'Multimizer-dil-eksik.txt'
    $sb = New-Object System.Text.StringBuilder
    foreach ($k in @($script:LangMiss.Keys | Sort-Object)) {
        [void]$sb.Append([string]$script:LangMiss[$k] + "`t" + $k.Replace('\', '\\').Replace("`t", '\t').Replace("`r", '\r').Replace("`n", '\n') + "`r`n")
    }
    [System.IO.File]::WriteAllText($path, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
    return $path
}
