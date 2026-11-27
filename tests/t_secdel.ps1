. "$PSScriptRoot/lib.ps1"
# Dosya ve klasör kalıcı silme eklentisi (Eklenti\GuvenliSilme.ps1): üzerine yazma, bağlantılara girmeme, bulut/sıkıştırma uyarıları, geçiş sayısı sınırları.
Import-Fn 'Format-Size', 'Test-SecureDeleteAllowed', 'Get-FilesBySize'
Import-Var 'WalkSkipDirs'
[void](Import-Ext 'GuvenliSilme')

$script:Logs = New-Object System.Collections.ArrayList
$script:CancelNow = $false
function Write-WhLog([string]$Message, [string]$Level = 'INFO') { [void]$script:Logs.Add($Level + ': ' + $Message) }
function Log-Has([string]$Needle) { foreach ($l in $script:Logs) { if ($l.Contains($Needle)) { return $true } }; return $false }
function Set-JobProgress($Done, $Total, [string]$Label = '') { }
function Step-JobProgress { }
function Test-JobCancel { return $script:CancelNow }
function Get-AppFolder { return $script:FakeApp }
$script:FakeApp = ''

$root = Join-Path ([System.IO.Path]::GetTempPath()) ('mm-secdel-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
[void][System.IO.Directory]::CreateDirectory($root)
function Write-Bytes([string]$Path, [int]$Size, [byte]$Fill) {
    $b = New-Object byte[] $Size
    if ($Fill -ne 0) { for ($i = 0; $i -lt $b.Length; $i++) { $b[$i] = $Fill } }
    [System.IO.File]::WriteAllBytes($Path, $b)
}
$canLink = $true
try {
    $probeT = Join-Path $root 'probe-hedef.txt'
    [System.IO.File]::WriteAllText($probeT, 'x')
    [void](New-Item -ItemType SymbolicLink -Path (Join-Path $root 'probe-bag') -Target $probeT -ErrorAction Stop)
    Remove-Item -LiteralPath (Join-Path $root 'probe-bag') -Force
    Remove-Item -LiteralPath $probeT -Force
} catch { $canLink = $false }

# =====================================================================
#  1) dosya durumu
# =====================================================================
$s0 = Get-SecureFileState ([pscustomobject]@{ Attributes = 32 })
Assert-True ($s0.Link -eq $false -and $s0.Skip -eq '' -and @($s0.Warn).Count -eq 0) 'durum: sıradan dosya'
$s1 = Get-SecureFileState ([pscustomobject]@{ Attributes = 0x400 })
Assert-True ($s1.Link -eq $true -and $s1.Skip -eq '') 'durum: bağlantı'
foreach ($a in @(0x400000, 0x40000, 0x1000)) {
    $sx = Get-SecureFileState ([pscustomobject]@{ Attributes = $a })
    Assert-True ($sx.Skip -match 'Bulutta duran dosya' -and $sx.Link -eq $false) ('durum: bulutta duran dosya atlanır (öznitelik ' + $a + ')')
}
$sc = Get-SecureFileState ([pscustomobject]@{ Attributes = 0x800 })
Assert-True ($sc.Skip -eq '' -and (@($sc.Warn) -join '|') -match 'sıkıştırması') 'durum: sıkıştırılmış dosya uyarısı'
$se = Get-SecureFileState ([pscustomobject]@{ Attributes = 0x4000 })
Assert-True ((@($se.Warn) -join '|') -match 'EFS') 'durum: EFS uyarısı'
$ss = Get-SecureFileState ([pscustomobject]@{ Attributes = 0x200 })
Assert-True ((@($ss.Warn) -join '|') -match 'seyrek') 'durum: seyrek dosya uyarısı'
$sm = Get-SecureFileState ([pscustomobject]@{ Attributes = (0x800 -bor 0x4000 -bor 0x200) })
Assert-Eq @($sm.Warn).Count 3 'durum: üç uyarı birlikte'
$sl = Get-SecureFileState ([pscustomobject]@{ Attributes = (0x400 -bor 0x400000) })
Assert-True ($sl.Link -eq $true -and $sl.Skip -eq '') 'durum: bağlantı bulut işaretinden önce gelir'
$sn = Get-SecureFileState ([pscustomobject]@{ Name = 'x' })
Assert-True ($sn.Link -eq $false -and $sn.Skip -eq '') 'durum: öznitelik okunamazsa sıradan sayılır'
$strm = Get-SecureStreams (Join-Path $root 'yok.txt')
Assert-Eq $strm.Count 0 'veri akışları: Windows dışında ya da dosya yoksa boş'

# =====================================================================
#  2) üzerine yazma
# =====================================================================
foreach ($passes in @(1, 3)) {
    $ms = New-Object System.IO.MemoryStream
    $orig = New-Object byte[] 3000000
    for ($i = 0; $i -lt $orig.Length; $i++) { $orig[$i] = 170 }
    $ms.Write($orig, 0, $orig.Length)
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    Write-SecureOverwrite $ms $passes $rng
    $rng.Dispose()
    Assert-Eq $ms.Length 0 ("üzerine yazma: akış sıfırlanır ($passes geçiş)")
    $buf = $ms.GetBuffer()
    $same = 0
    for ($i = 0; $i -lt 3000000; $i += 997) { if ($buf[$i] -eq 170) { $same++ } }
    Assert-True ($same -lt 40) ("üzerine yazma: özgün içerik kalmaz ($passes geçiş, 0xAA örnek sayısı $same / 3009)")
    $seen = New-Object 'System.Collections.Generic.HashSet[byte]'
    for ($i = 0; $i -lt 100000; $i++) { [void]$seen.Add($buf[$i]) }
    Assert-True ($seen.Count -ge 250) ("üzerine yazma: veri rastgele ($passes geçiş)")
    $ms.Dispose()
}

# =====================================================================
#  3) tek dosya
# =====================================================================
$f1 = Join-Path $root 'bir.bin'
Write-Bytes $f1 1500000 170
$hard = Join-Path $root 'bir-sert.bin'
$hardOk = $true
try { [void](New-Item -ItemType HardLink -Path $hard -Target $f1 -ErrorAction Stop) } catch { $hardOk = $false }
$len = Remove-FileSecure $f1
Assert-Eq $len 1500000.0 'dosya: boyut döner'
Assert-True (-not (Test-Path -LiteralPath $f1)) 'dosya: silindi'
if ($hardOk) {
    Assert-Eq (Get-Item -LiteralPath $hard).Length 0 'dosya: aynı veriyi gösteren sert bağdan da özgün içerik okunamaz (içerik yazılıp sıfırlandı)'
    Remove-Item -LiteralPath $hard -Force
}
Assert-Eq @(Get-ChildItem -LiteralPath $root -Force | Where-Object { $_.Name -notlike 'probe*' }).Count 0 'dosya: yeniden adlandırma artığı kalmaz'
$f0 = Join-Path $root 'bos.txt'
[System.IO.File]::WriteAllBytes($f0, (New-Object byte[] 0))
Assert-Eq (Remove-FileSecure $f0) 0.0 'dosya: boş dosya silinir'
Assert-True (-not (Test-Path -LiteralPath $f0)) 'dosya: boş dosya kalmadı'
Assert-Eq (Remove-FileSecure (Join-Path $root 'hic-yok.bin')) 0.0 'dosya: olmayan dosya sıfır döner'
$fr = Join-Path $root 'salt-okunur.txt'
[System.IO.File]::WriteAllText($fr, 'korumali icerik')
(Get-Item -LiteralPath $fr).Attributes = [System.IO.FileAttributes]::ReadOnly
Assert-Eq (Remove-FileSecure $fr) 15.0 'dosya: salt okunur dosya da silinir'
Assert-True (-not (Test-Path -LiteralPath $fr)) 'dosya: salt okunur dosya kalmadı'
foreach ($p in @(0, -4, 1, 3, 99)) {
    $fp = Join-Path $root ('gecis' + $p + '.bin')
    Write-Bytes $fp 70000 1
    Assert-Eq (Remove-FileSecure $fp $p) 70000.0 ("dosya: geçiş sayısı $p kabul edilir")
    Assert-True (-not (Test-Path -LiteralPath $fp)) ("dosya: geçiş sayısı $p ile silindi")
}
if ($canLink) {
    $target = Join-Path $root 'asil.txt'
    [System.IO.File]::WriteAllText($target, 'asil dosya dokunulmamali')
    $lnk = Join-Path $root 'kisayol.txt'
    [void](New-Item -ItemType SymbolicLink -Path $lnk -Target $target)
    Assert-Eq (Remove-FileSecure $lnk) 0.0 'bağlantı: yalnızca bağlantı kaldırılır'
    Assert-True (-not (Test-Path -LiteralPath $lnk)) 'bağlantı: kısayol silindi'
    Assert-Eq ([System.IO.File]::ReadAllText($target)) 'asil dosya dokunulmamali' 'bağlantı: hedef dosya aynen duruyor'
    Remove-Item -LiteralPath $target -Force
}

# =====================================================================
#  4) iş: dosya ve klasörler
# =====================================================================
$dir = Join-Path $root 'silinecek'
$sub = Join-Path $dir 'alt/derin'
[void][System.IO.Directory]::CreateDirectory($sub)
Write-Bytes (Join-Path $dir 'a.txt') 1000 7
Write-Bytes (Join-Path $sub 'b.txt') 2500 8
Write-Bytes (Join-Path $sub 'bos.txt') 0 0
$single = Join-Path $root 'tek.txt'
Write-Bytes $single 4096 9
$script:Logs.Clear()
$r = Job_SecureDelete @{ Paths = @($dir, $single, (Join-Path $root 'hic-yok'), '') }
Assert-True ($r.Ok -eq $true -and $r.Failed -eq 0 -and $r.Skipped -eq 0) 'iş: olmayan yol başarısızlık sayılmaz'
Assert-Eq $r.Files 4 'iş: dört dosya silindi'
Assert-Eq $r.Bytes 7596.0 'iş: toplam bayt'
Assert-Eq $r.Passes 1 'iş: varsayılan geçiş sayısı bir'
Assert-True (-not (Test-Path -LiteralPath $dir) -and -not (Test-Path -LiteralPath $single)) 'iş: klasör ve dosya kalmadı'
Assert-True (Log-Has 'Bulunamadı') 'iş: olmayan yol günlüğe yazıldı'
Assert-Eq @($r.Warnings).Count 0 'iş: uyarı yok'

$r2 = Job_SecureDelete @{ Paths = @() }
Assert-True ($r2.Ok -eq $true -and $r2.Files -eq 0) 'iş: yol verilmezse bir şey yapılmaz'
$map = @(@($null, 1), @(0, 1), @(-3, 1), @(1, 1), @(3, 3), @(35, 35), @(36, 35), @(99, 35), @('abc', 1), @('4', 4))
foreach ($c in $map) {
    $pp = @{ Paths = @(); Passes = $c[0] }
    if ($null -eq $c[0]) { $pp = @{ Paths = @() } }
    $rr = Job_SecureDelete $pp
    Assert-Eq $rr.Passes $c[1] ('iş: geçiş sayısı ' + [string]$c[0] + ' -> ' + [string]$c[1])
}
$mp = Join-Path $root 'cok-gecis.bin'
Write-Bytes $mp 33333 5
$r3 = Job_SecureDelete @{ Paths = @($mp); Passes = 3 }
Assert-True ($r3.Ok -eq $true -and $r3.Files -eq 1 -and $r3.Passes -eq 3 -and $r3.Bytes -eq 33333.0) 'iş: üç geçişle tek dosya'
Assert-True ((($script:Logs -join '|') -match '3 geçiş')) 'iş: geçiş sayısı günlükte'

# korunan yollar reddedilir, dokunulmaz
$script:FakeApp = Join-Path $root 'Uygulama'
[void][System.IO.Directory]::CreateDirectory($script:FakeApp)
Write-Bytes (Join-Path $script:FakeApp 'Multimizer.ps1') 500 3
$script:Logs.Clear()
$r4 = Job_SecureDelete @{ Paths = @($script:FakeApp, (Join-Path $script:FakeApp 'Multimizer.ps1'), '/') }
Assert-True ($r4.Ok -eq $false -and $r4.Failed -eq 3 -and $r4.Files -eq 0) 'korumalı yollar: üçü de reddedildi'
Assert-True (Test-Path -LiteralPath (Join-Path $script:FakeApp 'Multimizer.ps1')) 'korumalı yollar: dosya yerinde'
Assert-True (Log-Has 'SKIP: ') 'korumalı yollar: günlükte neden yazılı'
Assert-True (Log-Has 'silinemez') 'korumalı yollar: neden “silinemez” sözcüğünü taşır'
$script:FakeApp = ''

# iptal
$cf = Join-Path $root 'iptal.bin'
Write-Bytes $cf 5000 4
$script:CancelNow = $true
$r5 = Job_SecureDelete @{ Paths = @($cf) }
$script:CancelNow = $false
Assert-True ($r5.Files -eq 0 -and (Test-Path -LiteralPath $cf)) 'iptal: hiçbir şey silinmedi'
Assert-True (Log-Has 'İptal edildi') 'iptal: günlüğe yazıldı'
Remove-Item -LiteralPath $cf -Force

# bağlantılar: klasör içindeki kısayolun hedefine girilmez
if ($canLink) {
    $outer = Join-Path $root 'disarida'
    [void][System.IO.Directory]::CreateDirectory($outer)
    $keep = Join-Path $outer 'sakla.txt'
    [System.IO.File]::WriteAllText($keep, 'baska yerdeki veri')
    $keepFile = Join-Path $root 'sakla2.txt'
    [System.IO.File]::WriteAllText($keepFile, 'baska dosya')
    $d2 = Join-Path $root 'icinde-baglanti'
    [void][System.IO.Directory]::CreateDirectory($d2)
    Write-Bytes (Join-Path $d2 'normal.txt') 800 6
    [void](New-Item -ItemType SymbolicLink -Path (Join-Path $d2 'klasor-baglantisi') -Target $outer)
    [void](New-Item -ItemType SymbolicLink -Path (Join-Path $d2 'dosya-baglantisi.txt') -Target $keepFile)
    $script:Logs.Clear()
    $r6 = Job_SecureDelete @{ Paths = @($d2) }
    Assert-True ($r6.Failed -eq 0 -and $r6.Skipped -eq 0 -and $r6.Ok -eq $true) 'bağlantılı klasör: sorunsuz'
    Assert-True (-not (Test-Path -LiteralPath $d2)) 'bağlantılı klasör: kaldırıldı'
    Assert-Eq ([System.IO.File]::ReadAllText($keep)) 'baska yerdeki veri' 'bağlantılı klasör: klasör bağlantısının hedefi aynen duruyor'
    Assert-Eq ([System.IO.File]::ReadAllText($keepFile)) 'baska dosya' 'bağlantılı klasör: dosya bağlantısının hedefi aynen duruyor'
    # kökün kendisi bağlantıysa yalnızca bağlantı kaldırılır
    $rootLink = Join-Path $root 'kok-baglantisi'
    [void](New-Item -ItemType SymbolicLink -Path $rootLink -Target $outer)
    $script:Logs.Clear()
    $r7 = Job_SecureDelete @{ Paths = @($rootLink) }
    Assert-True (-not (Test-Path -LiteralPath $rootLink) -and (Test-Path -LiteralPath $keep)) 'kök bağlantısı: yalnızca bağlantı kalktı, hedef duruyor'
    Assert-True (Log-Has 'Bağlantı kaldırıldı') 'kök bağlantısı: günlüğe yazıldı'
    Assert-Eq ([System.IO.File]::ReadAllText($keep)) 'baska yerdeki veri' 'kök bağlantısı: hedef içeriği aynen'
    # ağaç temizliği
    $t3 = Join-Path $root 'agac'
    [void][System.IO.Directory]::CreateDirectory((Join-Path $t3 'a/b'))
    [void](New-Item -ItemType SymbolicLink -Path (Join-Path $t3 'a/b/c-baglanti') -Target $outer)
    Assert-Eq (Remove-SecureDirTree $t3) 0 'ağaç: bağlantı içeren boş klasörler kalmadan kalkar'
    Assert-True (-not (Test-Path -LiteralPath $t3) -and (Test-Path -LiteralPath $keep)) 'ağaç: hedef korundu'
}
$t4 = Join-Path $root 'dolu-agac'
[void][System.IO.Directory]::CreateDirectory((Join-Path $t4 'x'))
[System.IO.File]::WriteAllText((Join-Path $t4 'x/kalan.txt'), 'kalan')
Assert-True ((Remove-SecureDirTree $t4) -ge 1) 'ağaç: içinde dosya kalan klasör kaldırılamaz ve sayılır'
Assert-True (Test-Path -LiteralPath (Join-Path $t4 'x/kalan.txt')) 'ağaç: dosyaya dokunulmadı'
Assert-Eq (Remove-SecureDirTree (Join-Path $root 'olmayan-agac')) 0 'ağaç: olmayan klasör sorun değil'

# =====================================================================
#  5) bulut ve uyarı davranışı (durum işlevi değiştirilerek)
# =====================================================================
$origState = (Get-Item function:Get-SecureFileState).ScriptBlock
function Get-SecureFileState($Fi) {
    if ([string]$Fi.Name -like '*.bulut') { return @{ Link = $false; Skip = 'Bulutta duran dosya (sahte). Atlandı.'; Warn = @() } }
    if ([string]$Fi.Name -like '*.uyari') { return @{ Link = $false; Skip = ''; Warn = @('NTFS sıkıştırması açık dosya: sahte uyarı') } }
    return (& $origState $Fi)
}
$d5 = Join-Path $root 'karisik'
[void][System.IO.Directory]::CreateDirectory($d5)
Write-Bytes (Join-Path $d5 'a.uyari') 100 1
Write-Bytes (Join-Path $d5 'b.uyari') 100 1
Write-Bytes (Join-Path $d5 'c.bulut') 100 1
Write-Bytes (Join-Path $d5 'd.txt') 100 1
$script:Logs.Clear()
$r8 = Job_SecureDelete @{ Paths = @($d5) }
Assert-Eq $r8.Files 3 'karışık klasör: üç dosya silindi'
Assert-Eq $r8.Skipped 1 'karışık klasör: bulutta duran dosya atlandı'
Assert-True ($r8.Ok -eq $false) 'karışık klasör: atlanan varsa Ok=false'
Assert-True (Test-Path -LiteralPath (Join-Path $d5 'c.bulut')) 'karışık klasör: atlanan dosya yerinde'
Assert-True (-not (Test-Path -LiteralPath (Join-Path $d5 'a.uyari')) -and -not (Test-Path -LiteralPath (Join-Path $d5 'd.txt'))) 'karışık klasör: diğerleri silindi'
Assert-Eq @($r8.Warnings).Count 1 'karışık klasör: aynı uyarı tek satırda toplanır'
Assert-True ($r8.Warnings[0] -match '^2 dosya, NTFS sıkıştırması') 'karışık klasör: uyarı sayısı'
Assert-True (Log-Has 'SKIP: ') 'karışık klasör: atlama günlükte'
Assert-True (Log-Has 'Klasör tamamen kaldırılamadı') 'karışık klasör: kalan öğe uyarısı'
$cloudSingle = Join-Path $root 'tek.bulut'
Write-Bytes $cloudSingle 50 1
$r9 = Job_SecureDelete @{ Paths = @($cloudSingle) }
Assert-True ($r9.Skipped -eq 1 -and $r9.Files -eq 0 -and (Test-Path -LiteralPath $cloudSingle)) 'tek bulut dosyası: atlandı ve yerinde'
$warnSingle = Join-Path $root 'tek.uyari'
Write-Bytes $warnSingle 50 1
$r10 = Job_SecureDelete @{ Paths = @($warnSingle) }
Assert-True ($r10.Files -eq 1 -and $r10.Ok -eq $true -and @($r10.Warnings).Count -eq 1 -and $r10.Warnings[0] -match '^1 dosya, ') 'tek uyarılı dosya: silindi ve uyarı verildi'
Assert-True (-not (Test-Path -LiteralPath $warnSingle)) 'tek uyarılı dosya: kalmadı'
Set-Item -Path function:Get-SecureFileState -Value $origState

Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
Show-Result
