. "$PSScriptRoot/lib.ps1"
Import-Fn 'Get-FileHashHex', 'Job_FileInfo', 'Remove-FileSecure', 'Test-SecureDeleteAllowed', 'Job_SecureDelete', 'Get-FilesBySize', 'Format-Size'
Import-Var 'WalkSkipDirs'

$script:Log = New-Object System.Collections.ArrayList
function Write-WhLog { param([string]$Text, [string]$Level = 'INFO') [void]$script:Log.Add($Level + '|' + $Text) }
function Log-Has([string]$Needle) { foreach ($l in $script:Log) { if ($l.Contains($Needle)) { return $true } }; return $false }
function Set-JobProgress { param($a, $b, $c) }
function Step-JobProgress { param($a) }
function Test-JobCancel { return $false }
function Get-AuthenticodeSignature { param($LiteralPath, $ErrorAction) return [pscustomobject]@{ Status = 'NotSigned'; SignerCertificate = $null } }

$root = Join-Path ([System.IO.Path]::GetTempPath()) ('mm-jobs-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root -Force | Out-Null
try {
    # ======================= ozet =======================
    $f = Join-Path $root 'abc.txt'
    [System.IO.File]::WriteAllBytes($f, [System.Text.Encoding]::ASCII.GetBytes('abc'))
    Assert-Eq (Get-FileHashHex $f 0) 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad' 'SHA-256 bilinen deger'
    Assert-Eq (Get-FileHashHex $f 2) (Get-FileHashHex $f 2) 'kismi ozet tutarli'
    $r = Job_FileInfo @{ Path = $f }
    Assert-Eq $r.Ok $true 'Job_FileInfo basarili'
    Assert-Eq $r.Sha256 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad' 'Job_FileInfo ozeti'
    Assert-Eq $r.Size 3.0 'Job_FileInfo boyutu'
    Assert-Eq $r.Name 'abc.txt' 'Job_FileInfo adi'
    $r = Job_FileInfo @{ Path = (Join-Path $root 'yok.txt') }
    Assert-Eq $r.Ok $false 'olmayan dosya: Ok=false'

    # ======================= guvenli silme =======================
    $big = Join-Path $root 'buyuk.bin'
    $bytes = New-Object byte[] 3000000
    (New-Object System.Random 7).NextBytes($bytes)
    [System.IO.File]::WriteAllBytes($big, $bytes)
    $len = Remove-FileSecure $big
    Assert-Eq $len 3000000.0 'Remove-FileSecure boyutu dondurur'
    Assert-True (-not (Test-Path -LiteralPath $big)) 'dosya silindi'
    Assert-Eq @(Get-ChildItem -LiteralPath $root -Filter '*.tmp').Count 0 'gecici ad dosyasi kalmaz'
    Assert-Eq (Remove-FileSecure (Join-Path $root 'yok.bin')) 0.0 'olmayan dosya 0 doner'

    $dir = Join-Path $root 'silinecek'
    $sub = Join-Path $dir 'alt/derin'
    New-Item -ItemType Directory -Path $sub -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $dir 'a.txt'), 'birinci')
    [System.IO.File]::WriteAllText((Join-Path $sub 'b.txt'), 'ikinci dosya')
    [System.IO.File]::WriteAllText((Join-Path $sub 'bos.txt'), '')
    $single = Join-Path $root 'tek.txt'
    [System.IO.File]::WriteAllText($single, 'tek dosya')
    $script:Log.Clear()
    $r = Job_SecureDelete @{ Paths = @($dir, $single, (Join-Path $root 'hic-yok')) }
    Assert-True (-not (Test-Path -LiteralPath $dir)) 'klasor ve icindekiler silindi'
    Assert-True (-not (Test-Path -LiteralPath $single)) 'tek dosya silindi'
    Assert-Eq $r.Files 4 'dort dosya silindi'
    Assert-Eq $r.Failed 0 'basarisiz yok (olmayan yol atlanir)'
    Assert-Eq $r.Ok $true 'Ok=true'
    Assert-True (Log-Has 'hic-yok') 'olmayan yol gunluge yazilir'

    # sistem klasorleri silinmez
    $fakeWin = Join-Path $root 'Windows'
    $fakeSys = Join-Path $fakeWin 'System32'
    New-Item -ItemType Directory -Path $fakeSys -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $fakeSys 'onemli.dll'), 'x')
    $fakeProg = Join-Path $root 'Program Files'
    New-Item -ItemType Directory -Path $fakeProg -Force | Out-Null
    $oldWin = $env:WINDIR; $oldPf = $env:ProgramFiles; $oldSd = $env:SystemDrive; $oldUp = $env:USERPROFILE
    $env:WINDIR = $fakeWin; $env:ProgramFiles = $fakeProg; $env:SystemDrive = $root; $env:USERPROFILE = (Join-Path $root 'Kullanici')
    try {
        Assert-True ((Test-SecureDeleteAllowed $fakeWin) -ne '') 'Windows klasoru silinemez'
        Assert-True ((Test-SecureDeleteAllowed $fakeSys) -ne '') 'Windows alt klasoru silinemez'
        Assert-True ((Test-SecureDeleteAllowed $fakeProg) -ne '') 'Program Files silinemez'
        Assert-True ((Test-SecureDeleteAllowed $root) -ne '') 'sistem surucusu koku silinemez'
        Assert-True ((Test-SecureDeleteAllowed '/') -ne '') 'kok dizin silinemez'
        Assert-Eq (Test-SecureDeleteAllowed (Join-Path $root 'serbest/klasor')) '' 'sistem disi klasor serbest'
        $script:Log.Clear()
        $r = Job_SecureDelete @{ Paths = @($fakeSys) }
        Assert-True (Test-Path -LiteralPath (Join-Path $fakeSys 'onemli.dll')) 'sistem dosyasi yerinde'
        Assert-Eq $r.Ok $false 'sistem klasoru icin Ok=false'
        Assert-Eq $r.Failed 1 'sistem klasoru basarisiz sayilir'
    } finally { $env:WINDIR = $oldWin; $env:ProgramFiles = $oldPf; $env:SystemDrive = $oldSd; $env:USERPROFILE = $oldUp }

    # ======================= boyuta gore dosya listesi =======================
    $scan = Join-Path $root 'tara'
    New-Item -ItemType Directory -Path (Join-Path $scan 'a/b') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $scan 'node_modules') -Force | Out-Null
    [System.IO.File]::WriteAllBytes((Join-Path $scan 'kucuk.bin'), (New-Object byte[] 10))
    [System.IO.File]::WriteAllBytes((Join-Path $scan 'a/orta.bin'), (New-Object byte[] 5000))
    [System.IO.File]::WriteAllBytes((Join-Path $scan 'a/b/buyuk.bin'), (New-Object byte[] 90000))
    [System.IO.File]::WriteAllBytes((Join-Path $scan 'node_modules/gizli.bin'), (New-Object byte[] 70000))
    $list = Get-FilesBySize $scan 1000
    $names = @($list | ForEach-Object { $_.Name } | Sort-Object)
    Assert-True ($names -contains 'orta.bin' -and $names -contains 'buyuk.bin') 'esigin ustundeki dosyalar listelenir'
    Assert-True ($names -notcontains 'kucuk.bin') 'esigin altindaki dosya listelenmez'
    $two = Get-FilesBySize $scan 0 2
    Assert-Eq $two.Count 2 'en fazla sayisi uygulanir'
    $none = Get-FilesBySize (Join-Path $root 'yok') 0
    Assert-Eq $none.Count 0 'olmayan klasor bos liste'
} finally {
    try { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue } catch { }
}
Show-Result
