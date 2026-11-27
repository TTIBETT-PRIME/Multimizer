# ==================================================================
#  YARDIMCILAR (cekirdek): parola uretici, toplu yeniden adlandirma, once/sonra karnesi, internete baglanan programlar,
#  acik kaynak lisans bilgisi ve alternatif onerici, Firefox gizlilik ilkeleri, yardim paketi, yeni bilgisayar adimlari.
#  Bu dosya arayuze dokunmaz. Sistemi degistiren iki islem (yeniden adlandirma, guvenlik duvari engeli) plan motorundan gecer:
#  once onizleme, sonra uygulama; her ikisi de Gecmis sayfasindan geri alinir.
# ==================================================================

# ---------------- parola uretici ----------------
# Karistirilan karakterler (0 O o 1 l I) hicbir kumede yoktur.
$script:PwCharSets = [ordered]@{
    Lower  = 'abcdefghijkmnpqrstuvwxyz'
    Upper  = 'ABCDEFGHJKLMNPQRSTUVWXYZ'
    Digit  = '23456789'
    Symbol = '!#$%&*+-=?@_'
}
$script:PwLengths = @(12, 16, 20, 24, 32)

# Secilen karakter kumeleri (kucuk harf her zaman vardir). Uretim Eklenti\Parola.ps1 icindedir: New-RandomPassword <uzunluk> <kumeler>
function Get-PasswordSets([bool]$Upper, [bool]$Digit, [bool]$Symbol) {
    $sets = New-Object System.Collections.ArrayList
    [void]$sets.Add([string]$script:PwCharSets.Lower)
    if ($Upper) { [void]$sets.Add([string]$script:PwCharSets.Upper) }
    if ($Digit) { [void]$sets.Add([string]$script:PwCharSets.Digit) }
    if ($Symbol) { [void]$sets.Add([string]$script:PwCharSets.Symbol) }
    return , [string[]]$sets.ToArray()
}

# Yaklasik entropi (bit): uzunluk x log2(havuz)
function Get-PasswordBits([int]$Length, [bool]$Upper, [bool]$Digit, [bool]$Symbol) {
    $n = ((Get-PasswordSets $Upper $Digit $Symbol) -join '').Length
    return [int][math]::Floor($Length * [math]::Log($n, 2))
}

function Get-PasswordStrengthText([int]$Bits) {
    if ($Bits -lt 60) { return 'zayıf' }
    if ($Bits -lt 80) { return 'iyi' }
    if ($Bits -lt 110) { return 'güçlü' }
    return 'çok güçlü'
}

# Listedeki bir sonraki uzunluk (son degerden sonra basa doner)
function Get-NextPwLength([int]$Current) {
    $a = @($script:PwLengths)
    for ($i = 0; $i -lt $a.Count; $i++) { if ([int]$a[$i] -gt $Current) { return [int]$a[$i] } }
    return [int]$a[0]
}

# ---------------- toplu yeniden adlandirma ----------------
$script:RenameModes = @('Number', 'Replace', 'DatePrefix', 'Lower', 'Dash')
$script:RenameMax = 5000

# Dosya adinda gecersiz karakterleri atar; sondaki nokta ve boslugu kirpar
function Get-SafeFileName([string]$Name) {
    $s = [regex]::Replace([string]$Name, '[\\/:\*\?"<>\|\x00-\x1F]', '')
    return $s.Trim().TrimEnd('.', ' ')
}

function Split-FileName([string]$Name) {
    $i = $Name.LastIndexOf('.')
    if ($i -le 0) { return @{ Stem = $Name; Ext = '' } }
    return @{ Stem = $Name.Substring(0, $i); Ext = $Name.Substring($i) }
}

# Saf: yeniden adlandirma plani.
#   Items: @(@{ Name; Time }) (yalnizca adi degisecek dosyalar)   Existing: klasordeki butun adlar
#   Mode : Number (Arg = temel ad) | Replace (Arg = 'eski=>yeni') | DatePrefix | Lower | Dash
#   Donus: @{ Rows = @(@{ Old; New; Problem }); Changes; Problems; Error }
function Get-RenamePlan($Items, [string]$Mode, [string]$Arg, $Existing = @()) {
    $res = @{ Rows = @(); Changes = 0; Problems = 0; Error = '' }
    if ($script:RenameModes -notcontains $Mode) { $res.Error = 'Bilinmeyen yeniden adlandırma türü.'; return $res }
    $list = @(@($Items) | Where-Object { $null -ne $_ -and [string]$_.Name -ne '' } | Sort-Object { ([string]$_.Name).ToLowerInvariant() })
    $from = ''; $to = ''
    if ($Mode -eq 'Replace') {
        $ix = ([string]$Arg).IndexOf('=>')
        if ($ix -le 0) { $res.Error = 'Biçim: eski=>yeni (örnek: IMG_=>Tatil ). Silmek için sağ tarafı boş bırakın.'; return $res }
        $from = ([string]$Arg).Substring(0, $ix); $to = ([string]$Arg).Substring($ix + 2)
    }
    $base = Get-SafeFileName ([string]$Arg)
    if ($Mode -eq 'Number' -and $base -eq '') { $base = 'Dosya' }
    $pad = [math]::Max(2, ([string]$list.Count).Length)
    $rows = New-Object System.Collections.ArrayList
    $n = 0
    foreach ($it in $list) {
        $n++
        $old = [string]$it.Name
        $p = Split-FileName $old
        $new = $old
        switch ($Mode) {
            'Number' { $new = $base + ' ' + ([string]$n).PadLeft($pad, '0') + [string]$p.Ext }
            'Replace' { $new = [regex]::Replace([string]$p.Stem, [regex]::Escape($from), $to.Replace('$', '$$'), 'IgnoreCase') + [string]$p.Ext }
            'DatePrefix' {
                $d = ''
                try { $d = ([datetime]$it.Time).ToString('yyyy-MM-dd') } catch { $d = '' }
                if ($d -ne '' -and -not $old.StartsWith($d)) { $new = $d + ' ' + $old }
            }
            'Lower' { $new = $old.ToLowerInvariant() }
            'Dash' { $new = ([regex]::Replace([string]$p.Stem, '[\s_]+', '-')).Trim('-') + [string]$p.Ext }
        }
        $new = Get-SafeFileName $new
        if ($new -ceq $old) { continue }
        $empty = ($new.Trim() -eq '' -or ([string]$p.Ext -ne '' -and $new -eq [string]$p.Ext))
        [void]$rows.Add(@{ Old = $old; New = $new; Problem = ''; Empty = $empty })
    }
    # sorunlar: bos ad, cok uzun ad, ayni ad, klasorde kalan baska dosyayla cakisma
    $leaving = @{}
    foreach ($r in $rows) { $leaving[([string]$r.Old).ToLowerInvariant()] = $true }
    $seen = @{}
    foreach ($r in $rows) { $k = ([string]$r.New).ToLowerInvariant(); if ($seen.ContainsKey($k)) { $seen[$k] = [int]$seen[$k] + 1 } else { $seen[$k] = 1 } }
    $stay = @{}
    foreach ($e in @($Existing)) { $k = ([string]$e).ToLowerInvariant(); if ($k -ne '' -and -not $leaving.ContainsKey($k)) { $stay[$k] = $true } }
    $bad = 0
    foreach ($r in $rows) {
        $k = ([string]$r.New).ToLowerInvariant()
        if ($r.Empty -eq $true) { $r.Problem = 'ad boş kalıyor' }
        elseif (([string]$r.New).Length -gt 240) { $r.Problem = 'ad çok uzun' }
        elseif ([int]$seen[$k] -gt 1) { $r.Problem = 'aynı ad birden çok dosyaya düşüyor' }
        elseif ($stay.ContainsKey($k)) { $r.Problem = 'klasörde bu adda başka bir dosya var' }
        if ([string]$r.Problem -ne '') { $bad++ }
    }
    $res.Rows = $rows.ToArray(); $res.Changes = $rows.Count; $res.Problems = $bad
    return $res
}

# Sistem klasorlerinde toplu yeniden adlandirma yapilmaz. '' = izin var
function Test-RenameDirAllowed([string]$Dir) {
    if ([string]$Dir -eq '') { return 'Klasör seçilmedi.' }
    $d = ([string]$Dir).TrimEnd('\') + '\'
    $blocked = New-Object System.Collections.ArrayList
    foreach ($v in @($env:WINDIR, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData)) { if ([string]$v -ne '') { [void]$blocked.Add(([string]$v).TrimEnd('\') + '\') } }
    foreach ($b in $blocked) { if ($d.StartsWith([string]$b, [StringComparison]::OrdinalIgnoreCase)) { return 'Windows ve program klasörlerinde toplu yeniden adlandırma yapılmaz.' } }
    if ($d -cmatch '^[A-Za-z]:\\$') { return 'Sürücünün kök klasöründe toplu yeniden adlandırma yapılmaz; bir alt klasör seçin.' }
    return ''
}

# Klasordeki dosyalar (alt klasorler, gizli ve sistem dosyalari haric)
function Job_RenameScan($P) {
    $dir = [string]$P.Dir
    $why = Test-RenameDirAllowed $dir
    if ($why -ne '') { return @{ Ok = $false; Error = $why } }
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { return @{ Ok = $false; Error = 'Klasör bulunamadı.' } }
    $items = New-Object System.Collections.ArrayList
    foreach ($f in @(Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue)) {
        if (($f.Attributes -band [System.IO.FileAttributes]::Hidden) -or ($f.Attributes -band [System.IO.FileAttributes]::System)) { continue }
        [void]$items.Add(@{ Name = [string]$f.Name; Time = $f.LastWriteTime })
        if ($items.Count -gt $script:RenameMax) { return @{ Ok = $false; Error = ('Klasörde ' + [string]$script:RenameMax + ' dosyadan fazlası var; daha küçük bir klasör seçin.') } }
    }
    return @{ Ok = $true; Dir = $dir; Items = $items.ToArray() }
}

# Iki asamali yeniden adlandirma (ad degis tokusunda cakisma olmaz). Donus: basarili ciftler
function Invoke-RenamePairs([string]$Dir, $Pairs) {
    $tmp = New-Object System.Collections.ArrayList
    $tag = '~mm-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '-'
    $i = 0
    try {
        foreach ($p in @($Pairs)) {
            $i++
            $t = $tag + [string]$i
            Rename-Item -LiteralPath (Join-Path $Dir ([string]$p.Old)) -NewName $t -ErrorAction Stop
            [void]$tmp.Add(@{ Tmp = $t; Old = [string]$p.Old; New = [string]$p.New })
        }
    } catch {
        foreach ($x in $tmp) { try { Rename-Item -LiteralPath (Join-Path $Dir ([string]$x.Tmp)) -NewName ([string]$x.Old) -ErrorAction Stop } catch { } }
        throw ('Yeniden adlandırma başlatılamadı, hiçbir dosya değişmedi: ' + $_.Exception.Message)
    }
    $done = New-Object System.Collections.ArrayList
    foreach ($x in $tmp) {
        try {
            Rename-Item -LiteralPath (Join-Path $Dir ([string]$x.Tmp)) -NewName ([string]$x.New) -ErrorAction Stop
            [void]$done.Add(@{ Old = [string]$x.Old; New = [string]$x.New })
        } catch {
            try { Rename-Item -LiteralPath (Join-Path $Dir ([string]$x.Tmp)) -NewName ([string]$x.Old) -ErrorAction Stop } catch { }
            Add-Err (([string]$x.Old) + ': ' + $_.Exception.Message)
        }
    }
    return $done.ToArray()
}

# Op: @{ T = 'Rename'; Dir; Pairs = @(@{ Old; New }) }
function Invoke-RenameOp($Op) {
    $dir = [string]$Op.Dir
    $pairs = @($Op.Pairs)
    $why = Test-RenameDirAllowed $dir
    if ($why -ne '') { throw $why }
    if ($pairs.Count -eq 0) { Add-Skip 'Adı değişecek dosya yok'; return }
    if ($script:Preview) {
        $k = 0
        foreach ($p in $pairs) {
            $k++
            if ($k -le 25) { Add-Plan (([string]$p.Old) + '  →  ' + ([string]$p.New)) }
        }
        if ($pairs.Count -gt 25) { Add-Plan ('... ve ' + [string]($pairs.Count - 25) + ' dosya daha') }
        return
    }
    $done = @(Invoke-RenamePairs $dir $pairs)
    if ($done.Count -gt 0) {
        Add-Journal @{ T = 'Rename'; Dir = $dir; Pairs = $done }
        Add-Done ([string]$done.Count + ' dosya yeniden adlandırıldı: ' + $dir)
    }
}

function Undo-RenameItem($It) {
    $dir = [string]$It.Dir
    $back = New-Object System.Collections.ArrayList
    foreach ($p in @($It.Pairs)) {
        if (Test-Path -LiteralPath (Join-Path $dir ([string]$p.New))) { [void]$back.Add(@{ Old = [string]$p.New; New = [string]$p.Old }) }
    }
    if ($back.Count -eq 0) { Add-Skip 'Yeniden adlandırılan dosyalar yerinde değil; geri alınacak bir şey yok'; return }
    $done = @(Invoke-RenamePairs $dir $back.ToArray())
    Add-Done ([string]$done.Count + ' dosyanın adı eski hâline döndü: ' + $dir)
}
$script:MoreOps['Rename'] = 'Invoke-RenameOp'
$script:MoreUndo['Rename'] = 'Undo-RenameItem'

# ---------------- once / sonra karnesi ----------------
$script:ScoreBefore = $null
$script:ScoreKeep = 400

function Get-ScoreFile { return (Join-Path $script:DataDir 'karne.jsonl') }

# Olcum: calisan hizmet, islem, bos bellek (MB), sistem surucusunde bos alan (GB)
function Get-ScoreSnapshot {
    $s = @{ Time = (Get-Date).ToString('s'); Svc = -1; Proc = -1; FreeMb = -1; DiskFreeGb = -1.0 }
    try { $s.Svc = @(Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Running' }).Count } catch { }
    try { $s.Proc = @(Get-Process -ErrorAction SilentlyContinue).Count } catch { }
    try { $os = Get-CimInstance -ClassName Win32_OperatingSystem -OperationTimeoutSec 5 -ErrorAction Stop; $s.FreeMb = [int]([double]$os.FreePhysicalMemory / 1024) } catch { }
    try { $d = New-Object System.IO.DriveInfo ([string]$env:SystemDrive); $s.DiskFreeGb = [math]::Round($d.AvailableFreeSpace / 1GB, 1) } catch { }
    return $s
}

# Saf: iki olcum arasindaki fark (olculemeyen deger 0 sayilir)
function Get-ScoreDelta($A, $B) {
    $d = @{ Svc = 0; Proc = 0; FreeMb = 0; DiskFreeGb = 0.0 }
    if ($null -eq $A -or $null -eq $B) { return $d }
    foreach ($k in @('Svc', 'Proc', 'FreeMb')) { if ([int]$A[$k] -ge 0 -and [int]$B[$k] -ge 0) { $d[$k] = [int]$B[$k] - [int]$A[$k] } }
    if ([double]$A.DiskFreeGb -ge 0 -and [double]$B.DiskFreeGb -ge 0) { $d.DiskFreeGb = [math]::Round([double]$B.DiskFreeGb - [double]$A.DiskFreeGb, 1) }
    return $d
}

function Format-Signed($V, [string]$Unit = '') {
    $n = [double]$V
    $nf = New-Object System.Globalization.NumberFormatInfo
    $nf.NumberDecimalSeparator = ','
    $t = ([math]::Abs($n)).ToString('0.#', $nf)
    if ($n -gt 0) { return ('+' + $t + $Unit) }
    if ($n -lt 0) { return ('−' + $t + $Unit) }
    return ('0' + $Unit)
}

# Saf: "çalışan hizmet 142 → 139 (−3) · işlem 201 → 196 (−5) · boş bellek 6100 → 6400 MB (+300) · boş alan 120 → 122 GB (+2)"
function Format-ScoreLine($A, $B) {
    if ($null -eq $A -or $null -eq $B) { return '' }
    $d = Get-ScoreDelta $A $B
    $p = New-Object System.Collections.ArrayList
    if ([int]$A.Svc -ge 0 -and [int]$B.Svc -ge 0) { [void]$p.Add('çalışan hizmet ' + [string]$A.Svc + ' → ' + [string]$B.Svc + ' (' + (Format-Signed $d.Svc) + ')') }
    if ([int]$A.Proc -ge 0 -and [int]$B.Proc -ge 0) { [void]$p.Add('işlem ' + [string]$A.Proc + ' → ' + [string]$B.Proc + ' (' + (Format-Signed $d.Proc) + ')') }
    if ([int]$A.FreeMb -ge 0 -and [int]$B.FreeMb -ge 0) { [void]$p.Add('boş bellek ' + [string]$A.FreeMb + ' → ' + [string]$B.FreeMb + ' MB (' + (Format-Signed $d.FreeMb) + ')') }
    if ([double]$A.DiskFreeGb -ge 0 -and [double]$B.DiskFreeGb -ge 0) { [void]$p.Add('boş alan ' + [string]$A.DiskFreeGb + ' → ' + [string]$B.DiskFreeGb + ' GB (' + (Format-Signed $d.DiskFreeGb) + ')') }
    return ($p -join ' · ')
}

function Read-ScoreEntries([int]$Max = 60) {
    $out = New-Object System.Collections.ArrayList
    try {
        $f = Get-ScoreFile
        if (Test-Path -LiteralPath $f) {
            foreach ($l in @(Get-Content -LiteralPath $f -Encoding UTF8 -ErrorAction Stop)) {
                if ([string]$l -eq '') { continue }
                try { $o = ConvertTo-Hashtable ($l | ConvertFrom-Json); if ($o -is [hashtable] -and $o.ContainsKey('A') -and $o.ContainsKey('B')) { [void]$out.Add($o) } } catch { }
            }
        }
    } catch { }
    $a = $out.ToArray()
    if ($a.Count -gt $Max) { $a = @($a[($a.Count - $Max)..($a.Count - 1)]) }
    [array]::Reverse($a)
    return , $a
}

function Add-ScoreEntry([string]$Label, $A, $B, [int]$Changes) {
    try {
        $f = Get-ScoreFile
        $line = (@{ Label = $Label; Changes = $Changes; A = $A; B = $B } | ConvertTo-Json -Compress -Depth 4)
        $lines = New-Object System.Collections.ArrayList
        if (Test-Path -LiteralPath $f) { foreach ($l in @(Get-Content -LiteralPath $f -Encoding UTF8 -ErrorAction SilentlyContinue)) { if ([string]$l -ne '') { [void]$lines.Add([string]$l) } } }
        [void]$lines.Add($line)
        while ($lines.Count -gt $script:ScoreKeep) { $lines.RemoveAt(0) }
        [System.IO.File]::WriteAllLines($f, [string[]]$lines.ToArray(), (New-Object System.Text.UTF8Encoding($false)))
        return $true
    } catch { return $false }
}

# Plan basinda ve sonunda cagrilir (yalnizca gercek uygulamada). Degisiklik yoksa kayit yazilmaz.
function Start-ScoreMeasure { if (-not $script:Preview) { try { $script:ScoreBefore = Get-ScoreSnapshot } catch { $script:ScoreBefore = $null } } }

function Complete-ScoreMeasure([string]$Label) {
    if ($script:Preview -or $null -eq $script:ScoreBefore) { return }
    $a = $script:ScoreBefore
    $script:ScoreBefore = $null
    if ([int]$script:Changes -le 0) { return }
    try {
        $b = Get-ScoreSnapshot
        $t = Format-ScoreLine $a $b
        if ($t -ne '') { Write-WhLog ('Karne (önce → sonra): ' + $t) 'INFO' }
        [void](Add-ScoreEntry $Label $a $b ([int]$script:Changes))
    } catch { }
}

# Saf: son N gundeki kayitlarin ozeti
function Get-ScoreSummary($Entries, [int]$Days, [datetime]$Now) {
    $r = @{ Count = 0; Changes = 0; Svc = 0; DiskFreeGb = 0.0 }
    foreach ($e in @($Entries)) {
        if ($null -eq $e) { continue }
        $t = [datetime]::MinValue
        try { $t = [datetime]::Parse([string]$e.B.Time, [System.Globalization.CultureInfo]::InvariantCulture) } catch { continue }
        if (($Now - $t).TotalDays -gt $Days) { continue }
        $d = Get-ScoreDelta $e.A $e.B
        $r.Count++; $r.Changes += [int]$e.Changes; $r.Svc += [int]$d.Svc
        if ([double]$d.DiskFreeGb -gt 0) { $r.DiskFreeGb = [math]::Round([double]$r.DiskFreeGb + [double]$d.DiskFreeGb, 1) }
    }
    return $r
}

# Kendi isleminde calisan hizmetlerin bellek kullanimi (paylasilan svchost islemleri sayilmaz)
function Get-ServiceMemTop([int]$N = 8) {
    $out = New-Object System.Collections.ArrayList
    try {
        $svc = @(Get-CimInstance -ClassName Win32_Service -OperationTimeoutSec 8 -ErrorAction Stop | Where-Object { [int]$_.ProcessId -gt 0 -and [string]$_.State -eq 'Running' })
        $byPid = @{}
        foreach ($s in $svc) { $k = [string]$s.ProcessId; if (-not $byPid.ContainsKey($k)) { $byPid[$k] = New-Object System.Collections.ArrayList }; [void]$byPid[$k].Add($s) }
        foreach ($k in @($byPid.Keys)) {
            if ($byPid[$k].Count -ne 1) { continue }
            $s = $byPid[$k][0]
            try {
                $p = Get-Process -Id ([int]$k) -ErrorAction Stop
                [void]$out.Add(@{ Name = [string]$s.Name; Display = [string]$s.DisplayName; Mb = [int]($p.WorkingSet64 / 1MB) })
            } catch { }
        }
    } catch { }
    return @($out.ToArray() | Sort-Object { -1 * [int]$_.Mb } | Select-Object -First $N)
}

function Job_ScoreView($P) {
    $boots = @()
    try { $boots = @((Get-BootEvents 30).Boots | Sort-Object { $_.Time } -Descending | Select-Object -First 6) } catch { $boots = @() }
    return @{ Ok = $true; Now = (Get-ScoreSnapshot); Entries = (Read-ScoreEntries 40); Services = @(Get-ServiceMemTop 8); Boots = $boots }
}

# ---------------- internete baglanan programlar ----------------
function Test-PrivateAddress([string]$Ip) {
    $a = ([string]$Ip).Trim().ToLowerInvariant()
    if ($a -eq '' -or $a -eq '::' -or $a -eq '0.0.0.0') { return $true }
    if ($a -eq '::1' -or $a.StartsWith('127.')) { return $true }
    if ($a.StartsWith('10.') -or $a.StartsWith('192.168.') -or $a.StartsWith('169.254.')) { return $true }
    if ($a -match '^172\.(1[6-9]|2\d|3[01])\.') { return $true }
    if ($a -match '^100\.(6[4-9]|[7-9]\d|1[01]\d|12[0-7])\.') { return $true }
    if ($a.StartsWith('fe80:') -or $a.StartsWith('fc') -or $a.StartsWith('fd')) { return $true }
    return $false
}

# Saf: baglantilari programa gore toplar.
#   Conns: @(@{ Pid; Remote; Port })   Procs: @{ pid = @{ Name; Path } }
#   Donus: @(@{ Name; Path; Count; Hosts; Sample; Ports }) internet baglantisi en cok olandan aza
function Get-NetTalkers($Conns, $Procs) {
    $by = @{}
    foreach ($c in @($Conns)) {
        if ($null -eq $c) { continue }
        $ip = [string]$c.Remote
        if (Test-PrivateAddress $ip) { continue }
        $procId = [string]$c.Pid
        $name = 'PID ' + $procId; $path = ''
        if ($null -ne $Procs -and $Procs.ContainsKey($procId)) { $name = [string]$Procs[$procId].Name; $path = [string]$Procs[$procId].Path }
        $k = $path
        if ($k -eq '') { $k = 'ad:' + $name }
        $k = $k.ToLowerInvariant()
        if (-not $by.ContainsKey($k)) { $by[$k] = @{ Name = $name; Path = $path; Count = 0; Ips = @{}; Ports = @{} } }
        $by[$k].Count++
        $by[$k].Ips[$ip] = $true
        $by[$k].Ports[[string]$c.Port] = $true
    }
    $out = New-Object System.Collections.ArrayList
    foreach ($k in @($by.Keys)) {
        $e = $by[$k]
        $ips = @($e.Ips.Keys | Sort-Object)
        [void]$out.Add(@{ Name = [string]$e.Name; Path = [string]$e.Path; Count = [int]$e.Count; Hosts = $ips.Count; Sample = (@($ips | Select-Object -First 3) -join ', '); Ports = (@($e.Ports.Keys | Sort-Object { [int]$_ } | Select-Object -First 4) -join ', ') })
    }
    return @($out.ToArray() | Sort-Object @{ Expression = { [int]$_.Count }; Descending = $true }, @{ Expression = { [string]$_.Name } })
}

function Job_NetTalkers($P) {
    $conns = New-Object System.Collections.ArrayList
    $procs = @{}
    try {
        foreach ($c in @(Get-NetTCPConnection -State Established -ErrorAction Stop)) {
            [void]$conns.Add(@{ Pid = [int]$c.OwningProcess; Remote = [string]$c.RemoteAddress; Port = [int]$c.RemotePort })
        }
    } catch { return @{ Ok = $false; Error = $_.Exception.Message } }
    foreach ($procId in @($conns | ForEach-Object { [string]$_.Pid } | Select-Object -Unique)) {
        try {
            $p = Get-Process -Id ([int]$procId) -ErrorAction Stop
            $path = ''
            try { $path = [string]$p.Path } catch { $path = '' }
            $procs[$procId] = @{ Name = [string]$p.ProcessName; Path = $path }
        } catch { }
    }
    $rows = @(Get-NetTalkers $conns.ToArray() $procs)
    foreach ($r in $rows) {
        $r.Blocked = $false; $r.CanBlock = $false; $r.Why = ''
        if ([string]$r.Path -ne '') {
            try { $r.Why = [string](Test-FwBlockAllowed ([string]$r.Path)); $r.CanBlock = ($r.Why -eq '') } catch { }
            try { [void](Get-NetFirewallRule -Name (Get-FwRuleId ([string]$r.Path)) -ErrorAction Stop); $r.Blocked = $true } catch { }
        } else { $r.Why = 'Program yolu okunamadı (sistem işlemi olabilir).' }
    }
    return @{ Ok = $true; Rows = $rows; Total = $conns.Count; At = (Get-Date).ToString('HH:mm:ss') }
}

# ---------------- acik kaynak: lisans bilgisi ve alternatif onerici ----------------
# Open: kaynak kodu herkese acik mi.  Lic: lisans kisa adi.
$script:FossMeta = @{
    '7zip.7zip'                              = @{ Open = $true;  Lic = 'LGPL-2.1' }
    'VideoLAN.VLC'                           = @{ Open = $true;  Lic = 'GPL-2.0' }
    'Mozilla.Firefox'                        = @{ Open = $true;  Lic = 'MPL-2.0' }
    'Brave.Brave'                            = @{ Open = $true;  Lic = 'MPL-2.0' }
    'Mozilla.Thunderbird'                    = @{ Open = $true;  Lic = 'MPL-2.0' }
    'TheDocumentFoundation.LibreOffice'      = @{ Open = $true;  Lic = 'MPL-2.0' }
    'Notepad++.Notepad++'                    = @{ Open = $true;  Lic = 'GPL-3.0' }
    'WinMerge.WinMerge'                      = @{ Open = $true;  Lic = 'GPL-2.0' }
    'Audacity.Audacity'                      = @{ Open = $true;  Lic = 'GPL-3.0' }
    'OBSProject.OBSStudio'                   = @{ Open = $true;  Lic = 'GPL-2.0' }
    'Inkscape.Inkscape'                      = @{ Open = $true;  Lic = 'GPL-2.0' }
    'KeePassXCTeam.KeePassXC'                = @{ Open = $true;  Lic = 'GPL-2.0+' }
    'Bitwarden.Bitwarden'                    = @{ Open = $true;  Lic = 'GPL-3.0' }
    'IDRIX.VeraCrypt'                        = @{ Open = $true;  Lic = 'Apache-2.0' }
    'Microsoft.Sysinternals.Autoruns'        = @{ Open = $false; Lic = 'Ücretsiz (Microsoft)' }
    'Microsoft.Sysinternals.ProcessExplorer' = @{ Open = $false; Lic = 'Ücretsiz (Microsoft)' }
    'BleachBit.BleachBit'                    = @{ Open = $true;  Lic = 'GPL-3.0' }
    'WinDirStat.WinDirStat'                  = @{ Open = $true;  Lic = 'GPL-3.0' }
    'voidtools.Everything'                   = @{ Open = $false; Lic = 'Ücretsiz' }
    'CGSecurity.TestDisk'                    = @{ Open = $true;  Lic = 'GPL-2.0' }
    'Rufus.Rufus'                            = @{ Open = $true;  Lic = 'GPL-3.0' }
    'WiresharkFoundation.Wireshark'          = @{ Open = $true;  Lic = 'GPL-2.0' }
    'Insecure.Nmap'                          = @{ Open = $true;  Lic = 'değiştirilmiş GPL-2.0' }
    'SumatraPDF.SumatraPDF'                  = @{ Open = $true;  Lic = 'GPL-3.0' }
    'GIMP.GIMP'                              = @{ Open = $true;  Lic = 'GPL-3.0' }
    'ShareX.ShareX'                          = @{ Open = $true;  Lic = 'GPL-3.0' }
    'qBittorrent.qBittorrent'                = @{ Open = $true;  Lic = 'GPL-3.0' }
    'HandBrake.HandBrake'                    = @{ Open = $true;  Lic = 'GPL-2.0' }
}

# Alternatif onericinin kullandigi araclar da Ucretsiz araclar listesinde yer alir (kimlikler winget deposunda dogrulandi)
$script:FossToolsMore = @(
    @{ Id = 'SumatraPDF.SumatraPDF';   N = 'SumatraPDF';  Cat = 'Günlük'; D = 'Hafif ve hızlı PDF, e-kitap ve çizgi roman okuyucu; arka plan hizmeti kurmaz.' },
    @{ Id = 'GIMP.GIMP';               N = 'GIMP';        Cat = 'Günlük'; D = 'Katmanlı görüntü düzenleme ve fotoğraf rötuşu.' },
    @{ Id = 'ShareX.ShareX';           N = 'ShareX';      Cat = 'Günlük'; D = 'Ekran görüntüsü ve ekran kaydı; düzenleme ve açıklama araçlarıyla.' },
    @{ Id = 'qBittorrent.qBittorrent'; N = 'qBittorrent'; Cat = 'Günlük'; D = 'Reklamsız torrent istemcisi.' },
    @{ Id = 'HandBrake.HandBrake';     N = 'HandBrake';   Cat = 'Günlük'; D = 'Videoları yaygın biçimlere dönüştürür ve küçültür.' }
)

# Saf: iki listeyi birlestirir (ayni kimlik bir kez); kategoriler ilk gorundukleri sirayla tek blok olur (liste basliklari kategori degisince yazilir)
function Get-FossToolsMerged($Base, $More) {
    $all = New-Object System.Collections.ArrayList
    $seen = @{}
    foreach ($t in (@($Base) + @($More))) {
        if ($null -eq $t -or [string]$t.Id -eq '' -or $seen.ContainsKey([string]$t.Id)) { continue }
        $seen[[string]$t.Id] = $true
        [void]$all.Add($t)
    }
    $cats = New-Object System.Collections.ArrayList
    foreach ($t in $all) { if (-not $cats.Contains([string]$t.Cat)) { [void]$cats.Add([string]$t.Cat) } }
    $ord = New-Object System.Collections.ArrayList
    foreach ($c in $cats) { foreach ($t in $all) { if ([string]$t.Cat -eq [string]$c) { [void]$ord.Add($t) } } }
    return $ord.ToArray()
}
$script:FossTools = @(Get-FossToolsMerged $script:FossToolsBase $script:FossToolsMore)

function Get-FossMeta([string]$Id) {
    if ($script:FossMeta.ContainsKey($Id)) { return $script:FossMeta[$Id] }
    return $null
}

# Arac satirinin lisans eki: " · Açık kaynak (GPL-3.0)" ya da " · Ücretsiz, kapalı kaynak"
function Get-FossLicenseText([string]$Id) {
    $m = Get-FossMeta $Id
    if ($null -eq $m) { return '' }
    if ($m.Open -eq $true) { return ('Açık kaynak (' + [string]$m.Lic + ')') }
    return ('Kapalı kaynak · ' + [string]$m.Lic)
}

# "Yalnizca acik kaynak" suzgeci aciksa kapali kaynakli arac gizlenir (lisansi bilinmeyen arac gizlenmez)
function Test-FossHidden($Tool, [bool]$OpenOnly) {
    if (-not $OpenOnly) { return $false }
    $m = Get-FossMeta ([string]$Tool.Id)
    return ($null -ne $m -and $m.Open -ne $true)
}

# Kurulu program adi -> acik kaynak karsiligi. Rx: kurulu programin goruntu adi.
$script:AltRules = @(
    @{ Rx = '(?i)^WinRAR\b';                              Id = '7zip.7zip';                         Name = '7-Zip';        Why = 'rar dahil aynı arşivleri açar; deneme süresi ve satın alma uyarısı yoktur' }
    @{ Rx = '(?i)^WinZip\b';                              Id = '7zip.7zip';                         Name = '7-Zip';        Why = 'zip ve 7z arşivlerini açar ve oluşturur; abonelik gerektirmez' }
    @{ Rx = '(?i)Adobe (Acrobat|Reader)';                 Id = 'SumatraPDF.SumatraPDF';             Name = 'SumatraPDF';   Why = 'PDF’leri çok hızlı açar; arka plan hizmeti ve güncelleyici kurmaz' }
    @{ Rx = '(?i)^Foxit (PDF )?Reader';                   Id = 'SumatraPDF.SumatraPDF';             Name = 'SumatraPDF';   Why = 'hafif PDF okuyucu; reklam ve hesap istemez' }
    @{ Rx = '(?i)Microsoft (Office|365)\b';               Id = 'TheDocumentFoundation.LibreOffice'; Name = 'LibreOffice';  Why = 'Word, Excel ve PowerPoint dosyalarını açar; hesap ve abonelik gerektirmez' }
    @{ Rx = '(?i)^(Google Chrome|Opera( GX)?( Stable)?|Yandex)\b'; Id = 'Mozilla.Firefox';          Name = 'Firefox';      Why = 'izleme koruması varsayılan olarak açıktır; reklam şirketine bağlı değildir' }
    @{ Rx = '(?i)^(uTorrent|µTorrent|BitTorrent)\b';      Id = 'qBittorrent.qBittorrent';           Name = 'qBittorrent';  Why = 'reklamsızdır; aynı işi yapar' }
    @{ Rx = '(?i)^(CCleaner)\b';                          Id = 'BleachBit.BleachBit';               Name = 'BleachBit';    Why = 'aynı temizliği yapar; arka planda çalışan izleyici ve satış ekranı yoktur (Multimizer’ın Temizlik sayfası da aynı işi görür)' }
    @{ Rx = '(?i)^(Adobe Photoshop|Corel PaintShop)';     Id = 'GIMP.GIMP';                         Name = 'GIMP';         Why = 'katmanlı görüntü düzenleme; abonelik gerektirmez' }
    @{ Rx = '(?i)^(Lightshot|Snagit)\b';                  Id = 'ShareX.ShareX';                     Name = 'ShareX';       Why = 'ekran görüntüsü ve kaydı; yükleme yapmadan yerelde çalışabilir' }
    @{ Rx = '(?i)^(LastPass|Dashlane|1Password)\b';       Id = 'KeePassXCTeam.KeePassXC';           Name = 'KeePassXC';    Why = 'parolalar yalnızca sizin bilgisayarınızdaki şifreli dosyada durur' }
    @{ Rx = '(?i)^(Any Video Converter|Freemake)';        Id = 'HandBrake.HandBrake';               Name = 'HandBrake';    Why = 'video dönüştürür; filigran ve ek yazılım teklifi yoktur' }
)

# Saf: kurulu program adlarindan oneriler. Karsiligi zaten kuruluysa onerilmez; ayni karsilik bir kez onerilir.
#   Donus: @(@{ Have; Id; Name; Why })
function Get-AltSuggestions($InstalledNames) {
    $names = @(@($InstalledNames) | ForEach-Object { [string]$_ } | Where-Object { $_ -ne '' })
    $out = New-Object System.Collections.ArrayList
    $used = @{}
    foreach ($r in $script:AltRules) {
        $hit = @($names | Where-Object { $_ -match [string]$r.Rx } | Select-Object -First 1)
        if ($hit.Count -eq 0) { continue }
        $alt = [string]$r.Name
        if (@($names | Where-Object { $_ -match ('(?i)^(Mozilla )?' + [regex]::Escape($alt)) }).Count -gt 0) { continue }
        if ($used.ContainsKey([string]$r.Id)) { continue }
        $used[[string]$r.Id] = $true
        [void]$out.Add(@{ Have = [string]$hit[0]; Id = [string]$r.Id; Name = $alt; Why = [string]$r.Why })
    }
    return $out.ToArray()
}

function Job_AltScan($P) {
    $names = @()
    # Get-InstalledPrograms diziyi tek nesne olarak dondurur: once degiskene alinir, sonra gezilir
    try { $progs = Get-InstalledPrograms; $names = @(@($progs) | ForEach-Object { [string]$_.Name } | Where-Object { $_ -ne '' }) } catch { return @{ Ok = $false } }
    return @{ Ok = $true; Rows = @(Get-AltSuggestions $names); Count = $names.Count }
}

# ---------------- Firefox gizlilik ilkeleri ----------------
# Mozilla'nin belgelenmis kurumsal ilkeleri (Software\Policies\Mozilla\Firefox). Firefox kurulu degilse zararsizdir.
$ffx = 'HKLM\SOFTWARE\Policies\Mozilla\Firefox'
Add-RegTweak -Id 'PrivFirefoxTele' -Cat 'Gizlilik' -Level 2 -Title 'Firefox: telemetriyi, çalışmaları ve varsayılan tarayıcı ajanını kapat' `
    -Desc 'Firefox’un kullanım verisi göndermesi, deneysel “çalışmalar” (Studies) kurması ve arka planda çalışan varsayılan tarayıcı ajanı ilkeyle kapatılır. Firefox ayarlarında “kuruluşunuz tarafından yönetiliyor” yazısı görünür; geri aldığınızda kaybolur. Firefox kurulu değilse etkisizdir.' `
    -Reg @(($ffx + '|DisableTelemetry|DWord|1'), ($ffx + '|DisableFirefoxStudies|DWord|1'), ($ffx + '|DisableDefaultBrowserAgent|DWord|1'))
Add-RegTweak -Id 'PrivFirefoxSponsor' -Cat 'Gizlilik' -Level 2 -Title 'Firefox: sponsorlu kısayolları, sponsorlu önerileri ve tanıtım iletilerini kapat' `
    -Desc 'Yeni sekme sayfasındaki sponsorlu kısayollar ve hikâyeler, adres çubuğundaki sponsorlu öneriler ile eklenti ve özellik tanıtımları kapatılır. Yer imleriniz, geçmişiniz ve arama motorunuz değişmez.' `
    -Reg @(($ffx + '\FirefoxHome|SponsoredTopSites|DWord|0'), ($ffx + '\FirefoxHome|SponsoredPocket|DWord|0'), ($ffx + '\FirefoxHome|SponsoredStories|DWord|0'),
           ($ffx + '\FirefoxSuggest|SponsoredSuggestions|DWord|0'), ($ffx + '\FirefoxSuggest|ImproveSuggest|DWord|0'),
           ($ffx + '\UserMessaging|ExtensionRecommendations|DWord|0'), ($ffx + '\UserMessaging|FeatureRecommendations|DWord|0'), ($ffx + '\UserMessaging|MoreFromMozilla|DWord|0'))
$script:FirefoxTweakIds = @('PrivFirefoxTele', 'PrivFirefoxSponsor')

function Test-FirefoxInstalled {
    foreach ($k in @('HKLM\SOFTWARE\Mozilla\Mozilla Firefox', 'HKLM\SOFTWARE\WOW6432Node\Mozilla\Mozilla Firefox', 'HKCU\Software\Mozilla\Mozilla Firefox')) {
        try { $subs = Get-RegSubKeyNames $k; if (@($subs).Count -gt 0) { return $true } } catch { }
    }
    return $false
}

# ---------------- yardim paketi ----------------
# Saf: metinden kisisel izleri siler (kullanici adi, bilgisayar adi, kullanici klasoru, IPv4, MAC, e-posta)
function Protect-SupportText([string]$Text, [string]$User, [string]$Computer) {
    $t = [string]$Text
    if ($t -eq '') { return '' }
    # once e-posta, MAC ve IP: kullanici adi e-posta adresinin parcasi olabilir
    $t = [regex]::Replace($t, '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}', '<e-posta>')
    $t = [regex]::Replace($t, '(?<![0-9A-Fa-f])(?:[0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}(?![0-9A-Fa-f])', '<mac>')
    $t = [regex]::Replace($t, '(?<![\d.])(?:\d{1,3}\.){3}\d{1,3}(?![\d.])', '<ip>')
    if ([string]$User -ne '') {
        $t = [regex]::Replace($t, '(?i)([A-Za-z]:\\Users\\)' + [regex]::Escape($User), '${1}<kullanıcı>')
        if ($User.Length -ge 3) { $t = [regex]::Replace($t, '(?i)(?<![A-Za-z0-9])' + [regex]::Escape($User) + '(?![A-Za-z0-9])', '<kullanıcı>') }
    }
    if ([string]$Computer -ne '' -and $Computer.Length -ge 3) { $t = [regex]::Replace($t, '(?i)(?<![A-Za-z0-9])' + [regex]::Escape($Computer) + '(?![A-Za-z0-9])', '<bilgisayar>') }
    return $t
}

# Saf: pakete girecek ayar kopyasi (kisi, kurum, ag ve yol bilgisi cikarilir)
$script:SupportDropKeys = @('Contact', 'Org', 'BackupDest', 'BackupSources', 'GwBaseline', 'DeviceNames', 'KnownDevices', 'BlockedDevices', 'VpnName', 'VpnBaseHash', 'KillSwitchPrev', 'UpdateUrl', 'Games', 'NetOff')
function Get-SupportSettings($Settings) {
    $o = @{}
    if ($null -eq $Settings) { return $o }
    foreach ($k in @($Settings.Keys)) { if ($script:SupportDropKeys -notcontains [string]$k) { $o[[string]$k] = $Settings[$k] } }
    return $o
}

# Paketi hazirlar: surum, sistem ozeti, ayarlar (arindirilmis), son gunluk ve iz dosyalari (arindirilmis). Donus: @{ Ok; Path; Files; Error }
function Job_SupportBundle($P) {
    $dest = [string]$P.Dest
    if ($dest -eq '' -or -not (Test-Path -LiteralPath $dest -PathType Container)) { return @{ Ok = $false; Error = 'Hedef klasör bulunamadı.' } }
    $user = [string]$env:USERNAME; $pc = [string]$env:COMPUTERNAME
    $work = Join-Path ([System.IO.Path]::GetTempPath()) ('mm-yardim-' + [guid]::NewGuid().ToString('N'))
    $n = 0
    try {
        [void](New-Item -ItemType Directory -Path $work -Force)
        $enc = New-Object System.Text.UTF8Encoding($true)
        $info = New-Object System.Collections.ArrayList
        [void]$info.Add('Multimizer ' + [string]$script:AppVersion)
        try { $os = Get-CimInstance -ClassName Win32_OperatingSystem -OperationTimeoutSec 5 -ErrorAction Stop; [void]$info.Add([string]$os.Caption + ' derleme ' + [string]$os.BuildNumber + ' ' + [string]$os.OSArchitecture) } catch { }
        try { $cs = Get-CimInstance -ClassName Win32_ComputerSystem -OperationTimeoutSec 5 -ErrorAction Stop; [void]$info.Add([string]$cs.Manufacturer + ' ' + [string]$cs.Model + ' · bellek ' + [string][int]([double]$cs.TotalPhysicalMemory / 1GB) + ' GB') } catch { }
        try { [void]$info.Add('PowerShell ' + $PSVersionTable.PSVersion.ToString() + ' · kültür ' + [System.Globalization.CultureInfo]::CurrentUICulture.Name) } catch { }
        [void]$info.Add('Hazırlandı: ' + (Get-Date).ToString('yyyy-MM-dd HH:mm'))
        [System.IO.File]::WriteAllText((Join-Path $work 'ozet.txt'), (Protect-SupportText ($info -join "`r`n") $user $pc), $enc); $n++
        try { [System.IO.File]::WriteAllText((Join-Path $work 'ayarlar.json'), (Protect-SupportText ((Get-SupportSettings (Get-Settings)) | ConvertTo-Json -Depth 6) $user $pc), $enc); $n++ } catch { }
        $files = @()
        try { $files = @(Get-ChildItem -LiteralPath $script:LogDir -File -ErrorAction Stop | Where-Object { $_.Name -match '^(kayit-|hata-|oturum-iz)' } | Sort-Object LastWriteTime -Descending | Select-Object -First 8) } catch { $files = @() }
        foreach ($f in $files) {
            try {
                $txt = [System.IO.File]::ReadAllText($f.FullName)
                if ($txt.Length -gt 400000) { $txt = $txt.Substring($txt.Length - 400000) }
                [System.IO.File]::WriteAllText((Join-Path $work $f.Name), (Protect-SupportText $txt $user $pc), $enc); $n++
            } catch { }
        }
        $zip = Join-Path $dest ('Multimizer-yardim-' + (Get-Date -Format 'yyyyMMdd-HHmm') + '.zip')
        if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force -ErrorAction Stop }
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
        [System.IO.Compression.ZipFile]::CreateFromDirectory($work, $zip)
        return @{ Ok = $true; Path = $zip; Files = $n }
    } catch { return @{ Ok = $false; Error = $_.Exception.Message } }
    finally { try { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue } catch { } }
}

# ---------------- yeni bilgisayar / format sonrasi adimlari ----------------
# Saf: adim listesi. State: @{ Applied (uygulanan ayar sayisi); BackupDest; UseCase; PrepSeen; AppVersion }
#   Donus: @(@{ Key; Title; Detail; Done; Page; Tab; Btn })
function Get-SetupSteps($State) {
    $ap = 0; try { $ap = [int]$State.Applied } catch { }
    $steps = New-Object System.Collections.ArrayList
    [void]$steps.Add(@{ Key = 'updates'; Title = '1 · Windows ve sürücü güncellemeleri'; Detail = 'Önce Windows’u güncelleyin: güvenlik yamaları ve sürücüler diğer adımların sağlıklı çalışması için gerekir.'; Done = $false; Page = 'updates'; Tab = ''; Btn = 'Güncellemeler' })
    [void]$steps.Add(@{ Key = 'prep'; Title = '2 · Eksik bileşenler (Hazırlık)'; Detail = 'Oyunların ve programların istediği çalışma zamanları (Visual C++, .NET, DirectX) denetlenir; eksik olan tek tıkla kurulur.'; Done = ([string]$State.PrepSeen -ne '' -and [string]$State.PrepSeen -eq [string]$State.AppVersion); Page = 'solve'; Tab = 'prep'; Btn = 'Hazırlık' })
    [void]$steps.Add(@{ Key = 'tune'; Title = '3 · Önerilen ayarlar'; Detail = 'Donanımınıza ve kullanım türünüze göre önerilen gizlilik ve performans ayarları. Önce önizleme gösterilir; her şey geri alınabilir.'; Done = ($ap -gt 0); Page = 'optimize'; Tab = ''; Btn = 'İyileştir' })
    [void]$steps.Add(@{ Key = 'apps'; Title = '4 · Temel programlar (açık kaynak)'; Detail = 'Tarayıcı, arşiv, ofis, medya oynatıcı gibi temel programlar winget deposundan imza doğrulamasıyla kurulur.'; Done = $false; Page = 'apps'; Tab = 'foss'; Btn = 'Programlar' })
    [void]$steps.Add(@{ Key = 'backup'; Title = '5 · Yedekleme hedefi'; Detail = 'Belgelerinizin düzenli kopyası için bir hedef (ikinci disk ya da harici disk) seçin.'; Done = ([string]$State.BackupDest -ne ''); Page = 'backup'; Tab = ''; Btn = 'Yedekleme' })
    [void]$steps.Add(@{ Key = 'health'; Title = '6 · Son denetim'; Detail = 'Sağlık taraması güvenlik, performans ve bakım durumunu tek ekranda gösterir.'; Done = $false; Page = 'board'; Tab = ''; Btn = 'Durum' })
    return $steps.ToArray()
}

# ---------------- disk sifrelemeyi acma ----------------
# Windows Home: BitLocker yonetimi yoktur; sistem surucusu Ayarlar'daki "Cihaz sifrelemesi" ile sifrelenir.
function Test-HomeEdition([string]$EditionId = '') {
    $e = $EditionId
    if ($e -eq '') { $e = [string](Get-RegValue 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion' 'EditionID' '') }
    return ($e -match '^Core')
}

# Saf: bu surucu icin sifrelemeyi acma yolu.  'Enable' (uygulama icinden) | 'Panel' (Windows BitLocker penceresi) | 'Settings' (Cihaz sifrelemesi) | 'None'
function Get-BlEnableRoute([string]$Drive, [string]$SystemDrive, [bool]$IsHome) {
    $d = ([string]$Drive).TrimEnd('\').ToUpperInvariant()
    $s = ([string]$SystemDrive).TrimEnd('\').ToUpperInvariant()
    if ($d -cnotmatch '^[A-Z]:$') { return 'None' }
    if ($IsHome) { if ($d -eq $s) { return 'Settings' } else { return 'None' } }
    if ($d -eq $s) { return 'Enable' }
    return 'Panel'
}

# Sistem surucusunde BitLocker'i baslatir: TPM + 48 haneli kurtarma parolasi, yalnizca kullanilan alan.
# Windows once donanim sinamasi ister; sifreleme yeniden baslatmadan sonra baslar. Sonuc geri okunarak dogrulanir.
function Job_BitLockerEnable($P) {
    $drive = ([string]$P.Drive).TrimEnd('\')
    if ($drive -cnotmatch '^[A-Za-z]:$') { return @{ Ok = $false; Error = 'Geçersiz sürücü.' } }
    if ((Get-BlEnableRoute $drive ([string]$env:SystemDrive) (Test-HomeEdition)) -ne 'Enable') { return @{ Ok = $false; Error = 'Bu sürücü uygulama içinden şifrelenemez.' } }
    $exe = Join-Path (Join-Path $env:WINDIR 'System32') 'manage-bde.exe'
    if (-not (Test-Path -LiteralPath $exe)) { return @{ Ok = $false; Error = 'manage-bde.exe bulunamadı.' } }
    Write-WhLog ('=== BitLocker açılıyor: ' + $drive) 'STEP'
    $txt = ''
    try { $txt = (& $exe -on $drive -UsedSpaceOnly -RecoveryPassword 2>&1 | Out-String) } catch { return @{ Ok = $false; Error = $_.Exception.Message } }
    $code = $LASTEXITCODE
    # kurtarma parolasi gunluge yazilmaz
    $safe = [regex]::Replace($txt, '(\d{6}-){7}\d{6}', '<kurtarma parolası gizlendi>')
    foreach ($l in @($safe -split "`r?`n")) { if ($l.Trim() -ne '') { Write-WhLog ('   ' + $l.Trim()) 'INFO' } }
    if ($code -ne 0) { Write-WhLog ('manage-bde çıkış kodu ' + [string]$code) 'ERR'; return @{ Ok = $false; Error = ('Windows şifrelemeyi başlatmadı (kod ' + [string]$code + '). Ayrıntı günlükte.') } }
    $v = @(Get-BitLockerVolumes | Where-Object { ([string]$_.Drive).TrimEnd('\') -ieq $drive } | Select-Object -First 1)
    $has = ($v.Count -gt 0 -and $v[0].HasRecovery -eq $true)
    if (-not $has) { Write-WhLog 'BitLocker komutu tamamlandı ama kurtarma anahtarı doğrulanamadı.' 'WARN' }
    else { Write-WhLog 'BitLocker başlatıldı; kurtarma anahtarı tanımlı (doğrulandı).' 'OK' }
    return @{ Ok = $true; Verified = $has; Reboot = ($txt -match '(?i)restart|yeniden ba') }
}
