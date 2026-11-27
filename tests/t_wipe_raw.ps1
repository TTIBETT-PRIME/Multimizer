. "$PSScriptRoot/lib.ps1"
# Ham disk silme işi (Eklenti\DiskSilme.ps1 içindeki Job_WipeRaw): ayrılmamış alan, bölüm ve tüm disk kapsamları; korumalar, kimlik denetimi, iptal, hata yolları.
# Gerçek diske dokunulmaz: hedef olarak tests\gen_images.py ile üretilen sentetik imajların kopyaları kullanılır; Windows depolama komutları (Remove-Partition,
# Clear-Disk, New-Partition, Format-Volume) sahte işlevlerle değiştirilir ve çağrıları kaydedilir.
Import-Fn 'Format-Size', 'Format-Duration', 'Get-WipeMethodKey', 'Get-WipeModes', 'Get-WipeMethodName', 'Get-WipeVerifyKey', 'Get-WipeVerifyName', 'Get-WipeAfterKey', 'Get-WipeAfterName',
    'Get-WipeProgressLabel', 'Format-WipeEta', 'Test-WipeDiskAllowed', 'Test-WipePartAllowed', 'Test-WipeIdentity', 'Get-WipeExpect'
[void](Import-Ext 'DiskSilme')

$script:Logs = New-Object System.Collections.ArrayList
$script:Progress = New-Object System.Collections.ArrayList
$script:CancelAfter = -1
$script:CancelCalls = 0
function Write-WhLog([string]$Message, [string]$Level = 'INFO') { [void]$script:Logs.Add($Level + ': ' + $Message) }
function Set-JobProgress($Done, $Total, [string]$Label = '') { [void]$script:Progress.Add(@($Done, $Total, $Label)) }
function Test-JobCancel { $script:CancelCalls++; return ($script:CancelAfter -ge 0 -and $script:CancelCalls -gt $script:CancelAfter) }
function Log-Has([string]$Needle) { foreach ($l in $script:Logs) { if ($l.Contains($Needle)) { return $true } }; return $false }

$MiB = 1048576
$root = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$imgDir = Join-Path (Join-Path $root 'work') 'img'
if (-not (Test-Path -LiteralPath (Join-Path $imgDir 'expect.json')) -or -not (Test-Path -LiteralPath (Join-Path $imgDir 'gpt_valid.img'))) {
    [void][System.IO.Directory]::CreateDirectory($imgDir)
    & python3 (Join-Path $PSScriptRoot 'gen_images.py') $imgDir | Out-Null
}
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('mm-wiperaw-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
[void][System.IO.Directory]::CreateDirectory($tmp)
$sha = [System.Security.Cryptography.SHA256]::Create()

function Copy-Image([string]$Name) {
    $dst = Join-Path $tmp ('k' + [guid]::NewGuid().ToString('N').Substring(0, 6) + '-' + $Name)
    [System.IO.File]::Copy((Join-Path $imgDir $Name), $dst, $true)
    return $dst
}
function Hash-Region([string]$Path, [long]$Pos, [long]$Len) {
    $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        [void]$fs.Seek($Pos, [System.IO.SeekOrigin]::Begin)
        $b = New-Object byte[] $Len
        $n = 0
        while ($n -lt $Len) { $k = $fs.Read($b, $n, [int]($Len - $n)); if ($k -le 0) { break }; $n += $k }
        return [Convert]::ToBase64String($sha.ComputeHash($b))
    } finally { $fs.Dispose() }
}
function Hash-Fill([long]$Len, [byte]$B) {
    $a = New-Object byte[] $Len
    if ($B -ne 0) { [Array]::Fill[byte]($a, $B) }
    return [Convert]::ToBase64String($sha.ComputeHash($a))
}
function Is-Fill([string]$Path, [long]$Pos, [long]$Len, [byte]$B) { return ((Hash-Region $Path $Pos $Len) -eq (Hash-Fill $Len $B)) }
function Hash-All([string]$Path) { return (Hash-Region $Path 0 ([System.IO.FileInfo]$Path).Length) }
function Distinct-Count([string]$Path, [long]$Pos) {
    $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        [void]$fs.Seek($Pos, [System.IO.SeekOrigin]::Begin)
        $b = New-Object byte[] 65536
        [void]$fs.Read($b, 0, 65536)
        $seen = New-Object 'System.Collections.Generic.HashSet[byte]'
        foreach ($x in $b) { [void]$seen.Add($x) }
        return $seen.Count
    } finally { $fs.Dispose() }
}

# --- sahte canlı disk ve Windows depolama komutları ---
$script:LiveModel = $null
$script:IsAdmin = $true
$script:Calls = New-Object System.Collections.ArrayList
$script:FailRemove = $false
$script:FailClear = $false
$script:FailNew = $false
$script:NewLetter = 'F:'
function Get-WipeDiskLive([int]$Number) { return $script:LiveModel }
function Test-WipeAdmin { return $script:IsAdmin }
function Invoke-WipeRemovePartition([int]$Disk, [int]$Part) { [void]$script:Calls.Add("remove:$Disk/$Part"); if ($script:FailRemove) { throw 'bölüm kaldırılamadı (sahte)' } }
function Invoke-WipeClearDisk([int]$Disk) { [void]$script:Calls.Add("clear:$Disk"); if ($script:FailClear) { throw 'disk temizlenemedi (sahte)' } }
function Update-WipeStorage { [void]$script:Calls.Add('update') }
function Invoke-WipeNewVolume([int]$Disk, [bool]$Whole, [double]$Offset, [double]$Size, [string]$Fs, [string]$Style) {
    [void]$script:Calls.Add(('new:{0}/{1}/{2}/{3}/{4}/{5}' -f $Disk, $Whole, $Offset, $Size, $Fs, $Style))
    if ($script:FailNew) { throw 'biçimlenemedi (sahte)' }
    return $script:NewLetter
}
function Reset-Raw { $script:Calls.Clear(); $script:Logs.Clear(); $script:Progress.Clear(); $script:CancelAfter = -1; $script:CancelCalls = 0; $script:FailRemove = $false; $script:FailClear = $false; $script:FailNew = $false; $script:NewLetter = 'F:'; $script:IsAdmin = $true }
function New-RawLive([hashtable]$Over = @{}) {
    $m = @{ Number = 5; Name = 'Sentetik Disk'; Size = [double](64 * $MiB); UniqueId = 'IMG-UID'; Serial = 'IMG-SN'; Bus = 'USB'; Media = 'Unspecified'; Style = 'GPT'
        IsSystem = $false; IsBoot = $false; Offline = $false; ReadOnly = $false; Clustered = $false; Pool = $false; Sector = 512
        Letters = @('F:'); Roles = @()
        Parts = @(
            @{ Number = 1; Offset = [double](1 * $MiB); Size = [double](8 * $MiB); Letter = ''; Type = 'System'; IsSystem = $false; IsBoot = $false; IsActive = $false; Fs = ''; Label = '' },
            @{ Number = 2; Offset = [double](20 * $MiB); Size = [double](10 * $MiB); Letter = 'F:'; Type = 'Basic'; IsSystem = $false; IsBoot = $false; IsActive = $false; Fs = 'NTFS'; Label = 'Veri' },
            @{ Number = 3; Offset = [double](50 * $MiB); Size = [double](8 * $MiB); Letter = ''; Type = 'Basic'; IsSystem = $false; IsBoot = $false; IsActive = $false; Fs = ''; Label = '' }) }
    foreach ($k in $Over.Keys) { $m[$k] = $Over[$k] }
    return $m
}
function Run-Raw([hashtable]$P, $Live = $null) {
    Reset-Raw
    if ($null -eq $Live) { $Live = New-RawLive }
    if ($Live -is [string] -and $Live -eq 'YOK') { $Live = $null }
    $script:LiveModel = $Live
    if (-not $P.ContainsKey('Expect')) { $P.Expect = Get-WipeExpect $Live }
    if (-not $P.ContainsKey('Disk')) { $P.Disk = 5 }
    return (Job_WipeRaw $P)
}
function Calls-Text { return ($script:Calls -join ' ; ') }

# =====================================================================
#  1) hedef çözümleme, aralıklar, sonuç şekli
# =====================================================================
Assert-Eq (Initialize-MmWipe) '' 'motor derleniyor'
$imgA = Copy-Image 'gpt_valid.img'
$t1 = Resolve-WipeTarget @{ Image = $imgA; Disk = 5 }
Assert-True ($t1.Ok -eq $true -and $t1.Kind -eq 'Image' -and $t1.Number -eq 5 -and $t1.Spec -eq $imgA) 'hedef: imaj'
$t2 = Resolve-WipeTarget @{ Disk = 7 }
Assert-True ($t2.Ok -eq $true -and $t2.Kind -eq 'Disk' -and $t2.Spec -eq 'PhysicalDrive7' -and $t2.Number -eq 7) 'hedef: fiziksel disk yalnızca tamsayıdan üretilir'
foreach ($bad in @(-1, 10000, 'abc')) {
    $tb = Resolve-WipeTarget @{ Disk = $bad }
    Assert-True ($tb.Ok -eq $false -and $tb.Error -match 'Geçerli bir disk') ("hedef: geçersiz disk numarası [$bad]")
}
$tn = Resolve-WipeTarget @{ }
Assert-True ($tn.Ok -eq $false -and $tn.Error -match 'Geçerli bir disk') 'hedef: disk numarası yok'
$tm = Resolve-WipeTarget @{ Image = (Join-Path $tmp 'yok.img'); Disk = 1 }
Assert-True ($tm.Ok -eq $false -and $tm.Error -match 'imajı bulunamadı') 'hedef: olmayan imaj'
$td = Resolve-WipeTarget @{ Image = $tmp; Disk = 1 }
Assert-True ($td.Ok -eq $false -and $td.Error -match 'imajı bulunamadı') 'hedef: klasör imaj sayılmaz'
$tinj = Resolve-WipeTarget @{ Disk = '1; Remove-Item C:\' }
Assert-True ($tinj.Ok -eq $false) 'hedef: komut parçası içeren değer reddedilir'

$we = Get-WipeWinExtents (New-RawLive)
Assert-Eq $we.Count 3 'Windows aralıkları: üç bölüm'
Assert-True ($we[1].Start -eq [double](20 * $MiB) -and $we[1].Length -eq [double](10 * $MiB) -and $we[1].Tag -eq 'Windows bölümü') 'Windows aralıkları: konum, uzunluk, etiket'
$we2 = Get-WipeWinExtents @{ Parts = @(@{ Offset = 0; Size = 0 }, $null, @{ Offset = [double]$MiB; Size = [double]4096 }) }
Assert-Eq $we2.Count 1 'Windows aralıkları: boyutsuz ve boş öğeler atlanır'
$we3 = Get-WipeWinExtents @{ Parts = @() }
Assert-Eq $we3.Count 0 'Windows aralıkları: bölüm yok'

$rr = New-WipeRawResult 'Disk'
Assert-True ($rr.Ok -eq $false -and $rr.Kind -eq 'Raw' -and $rr.Scope -eq 'Disk' -and $rr.Disk -eq -1 -and $rr.Written -eq 0 -and $rr.Started -eq $false -and $rr.Nothing -eq $false -and @($rr.Notes).Count -eq 0) 'sonuç şekli: varsayılanlar'

# =====================================================================
#  2) plan (hiçbir şey değiştirmez)
# =====================================================================
Reset-Raw
$script:LiveModel = New-RawLive
$tgA = Resolve-WipeTarget @{ Image = $imgA; Disk = 5 }
$hashBefore = Hash-All $imgA
$planU = Get-WipeRawPlan @{ Expect = (Get-WipeExpect $script:LiveModel) } $tgA 'Unallocated'
Assert-True ($planU.Ok -eq $true -and $planU.Style -eq 'GPT' -and $planU.Length -eq [double](64 * $MiB)) 'plan: ayrılmamış alan tamam, GPT, boyut'
Assert-Eq @($planU.Extents).Count 2 'plan: iki boşluk'
Assert-True ($planU.Extents[0].Start -eq [double](9 * $MiB) -and $planU.Extents[0].Length -eq [double](11 * $MiB)) 'plan: birinci boşluk 9–20 MiB'
Assert-True ($planU.Extents[1].Start -eq [double](30 * $MiB) -and $planU.Extents[1].Length -eq [double](20 * $MiB)) 'plan: ikinci boşluk 30–50 MiB'
Assert-True ($planU.Extents[0].Tag -eq 'ayrılmamış') 'plan: boşluklar “ayrılmamış” diye etiketli'
$planD = Get-WipeRawPlan @{ Expect = (Get-WipeExpect $script:LiveModel) } $tgA 'Disk'
Assert-True ($planD.Ok -eq $true -and @($planD.Extents).Count -eq 1 -and $planD.Extents[0].Start -eq 0 -and $planD.Extents[0].Length -eq [double](64 * $MiB) -and $planD.Extents[0].Tag -eq 'tüm disk') 'plan: tüm disk tek aralık'
$planP = Get-WipeRawPlan @{ Part = 2; Expect = (Get-WipeExpect $script:LiveModel) } $tgA 'Partition'
Assert-True ($planP.Ok -eq $true -and @($planP.Extents).Count -eq 1 -and $planP.Extents[0].Start -eq [double](20 * $MiB) -and $planP.Extents[0].Length -eq [double](10 * $MiB) -and $planP.Part.Number -eq 2) 'plan: bölüm aralığı'
Assert-Eq (Hash-All $imgA) $hashBefore 'plan: imaj değişmedi'
Assert-Eq $script:Calls.Count 0 'plan: Windows komutu çağrılmadı'
# disk dışı Windows bölümü raw düzende yoksa boşluğu böler
$liveExtra = New-RawLive
$liveExtra.Parts = @($liveExtra.Parts) + @(@{ Number = 9; Offset = [double](9 * $MiB); Size = [double](5 * $MiB); Letter = ''; Type = 'Basic'; IsSystem = $false; IsBoot = $false; Fs = ''; Label = '' })
$script:LiveModel = $liveExtra
$planX = Get-WipeRawPlan @{ Expect = (Get-WipeExpect $liveExtra) } $tgA 'Unallocated'
Assert-True ($planX.Ok -eq $true -and @($planX.Extents).Count -eq 1 -and $planX.Extents[0].Start -eq [double](30 * $MiB)) 'plan: yalnızca Windows tarafından bildirilen bölüm de dolu sayılır'
# hatalar
$script:LiveModel = New-RawLive @{ IsSystem = $true }
$pe = Get-WipeRawPlan @{ Expect = @{ Size = [double](64 * $MiB) } } $tgA 'Unallocated'
Assert-True ($pe.Ok -eq $false -and $pe.Error -match 'Windows bu diskte') 'plan: sistem diski reddedilir'
$script:LiveModel = $null
$pe = Get-WipeRawPlan @{ Expect = @{ Size = [double](64 * $MiB) } } $tgA 'Disk'
Assert-True ($pe.Ok -eq $false -and $pe.Error -match 'bulunamadı') 'plan: disk yok'
$script:LiveModel = New-RawLive
$pe = Get-WipeRawPlan @{ Expect = @{ Size = [double](32 * $MiB); Name = 'Başka' } } $tgA 'Disk'
Assert-True ($pe.Ok -eq $false -and $pe.Error -match 'değişmiş') 'plan: kimlik uyuşmuyor'
$pe = Get-WipeRawPlan @{ Part = 77; Expect = (Get-WipeExpect $script:LiveModel) } $tgA 'Partition'
Assert-True ($pe.Ok -eq $false -and $pe.Error -match 'Bölüm bulunamadı') 'plan: olmayan bölüm'
$exOff = Get-WipeExpect $script:LiveModel; $exOff.PartOffset = [double](21 * $MiB); $exOff.PartSize = [double](10 * $MiB)
$pe = Get-WipeRawPlan @{ Part = 2; Expect = $exOff } $tgA 'Partition'
Assert-True ($pe.Ok -eq $false -and $pe.Error -match 'Bölüm, onay verdiğiniz andan sonra değişmiş') 'plan: bölüm konumu değişmiş'
$liveMis = New-RawLive
$liveMis.Parts = @(@{ Number = 4; Offset = [double](20 * $MiB + 100); Size = [double](10 * $MiB); Letter = ''; Type = 'Basic'; IsSystem = $false; IsBoot = $false; Fs = ''; Label = '' })
$script:LiveModel = $liveMis
$pe = Get-WipeRawPlan @{ Part = 4; Expect = (Get-WipeExpect $liveMis) } $tgA 'Partition'
Assert-True ($pe.Ok -eq $false -and $pe.Error -match 'sektör sınırına uymuyor') 'plan: hizasız bölüm'
$liveOut = New-RawLive
$liveOut.Parts = @(@{ Number = 4; Offset = [double](60 * $MiB); Size = [double](10 * $MiB); Letter = ''; Type = 'Basic'; IsSystem = $false; IsBoot = $false; Fs = ''; Label = '' })
$script:LiveModel = $liveOut
$pe = Get-WipeRawPlan @{ Part = 4; Expect = (Get-WipeExpect $liveOut) } $tgA 'Partition'
Assert-True ($pe.Ok -eq $false -and $pe.Error -match 'diskin dışına taşıyor') 'plan: diskin dışına taşan bölüm'
Assert-Eq (Hash-All $imgA) $hashBefore 'plan hataları: imaj değişmedi'

# =====================================================================
#  3) ayrılmamış alan
# =====================================================================
# 3a) sıfır yöntemi, tam doğrulama; "sonra" seçeneği yok sayılır
$img = Copy-Image 'gpt_valid.img'
$sz = ([System.IO.FileInfo]$img).Length
$h = @{
    Head = (Hash-Region $img 0 $MiB); Esp = (Hash-Region $img (1 * $MiB) (8 * $MiB)); Basic = (Hash-Region $img (20 * $MiB) (10 * $MiB))
    Linux = (Hash-Region $img (50 * $MiB) (8 * $MiB)); Tail = (Hash-Region $img (58 * $MiB) (6 * $MiB)) }
Assert-True (Is-Fill $img (9 * $MiB) (11 * $MiB) 221) 'ayrılmamış: başlangıçta boşluk 0xDD ile dolu'
$r = Run-Raw @{ Scope = 'Unallocated'; Image = $img; Method = 'zero'; Verify = 'full'; After = 'ntfs' }
Assert-True ($r.Ok -eq $true -and $r.Canceled -eq $false -and $r.Error -eq '' -and $r.Nothing -eq $false) 'ayrılmamış: başarılı'
Assert-True ($r.Scope -eq 'Unallocated' -and $r.After -eq 'none' -and $r.Method -eq 'zero' -and $r.Passes -eq 1 -and $r.Verify -eq 'full') 'ayrılmamış: seçenekler (sonra=boş zorunlu)'
Assert-True ($r.Ranges -eq 2 -and $r.Planned -eq [double](31 * $MiB) -and $r.Written -eq [double](31 * $MiB)) 'ayrılmamış: iki aralık, 31 MiB yazıldı'
Assert-True ($r.Verified -eq [double](31 * $MiB) -and $r.BadUnits -eq 0 -and $r.VerifyKind -eq 'full') 'ayrılmamış: 31 MiB doğrulandı, hatalı birim yok'
Assert-True ($r.Started -eq $false -and $r.Style -eq 'GPT' -and $r.Name -eq 'Sentetik Disk' -and $r.Disk -eq 5 -and $r.Target -eq $img) 'ayrılmamış: başlamadı bayrağı, tablo türü, ad, hedef'
Assert-Eq $script:Calls.Count 0 'ayrılmamış: hiçbir Windows depolama komutu çağrılmadı'
Assert-True ((Is-Fill $img (9 * $MiB) (11 * $MiB) 0) -and (Is-Fill $img (30 * $MiB) (20 * $MiB) 0)) 'ayrılmamış: iki boşluk sıfırlandı'
Assert-True ((Hash-Region $img 0 $MiB) -eq $h.Head -and (Hash-Region $img (1 * $MiB) (8 * $MiB)) -eq $h.Esp -and (Hash-Region $img (20 * $MiB) (10 * $MiB)) -eq $h.Basic -and (Hash-Region $img (50 * $MiB) (8 * $MiB)) -eq $h.Linux -and (Hash-Region $img (58 * $MiB) (6 * $MiB)) -eq $h.Tail) 'ayrılmamış: bölümler, tablo yapıları ve uç bölgeler aynen duruyor'
Assert-Eq ([System.IO.FileInfo]$img).Length $sz 'ayrılmamış: imaj boyutu değişmedi'
Assert-True (Log-Has 'KAYIT: ') 'ayrılmamış: kayıt satırı yazıldı'
Assert-True (Log-Has 'Hedef kimliği') 'ayrılmamış: hedef kimliği günlükte'
Assert-True ($script:Progress.Count -ge 1 -and $script:Progress[$script:Progress.Count - 1][2] -match 'Disk 5') 'ayrılmamış: ilerleme etiketinde disk numarası'

# 3b) rastgele yazma, örnek doğrulama
$img = Copy-Image 'gpt_valid.img'
$r = Run-Raw @{ Scope = 'Unallocated'; Image = $img; Method = 'random'; Verify = 'sample' }
Assert-True ($r.Ok -eq $true -and $r.Written -eq [double](31 * $MiB) -and $r.VerifyKind -eq 'sample' -and $r.Verified -gt 0 -and $r.Verified -le [double](31 * $MiB)) 'ayrılmamış rastgele: yazıldı ve örnek doğrulandı'
Assert-True ((Distinct-Count $img (10 * $MiB)) -ge 250 -and (Distinct-Count $img (40 * $MiB)) -ge 250) 'ayrılmamış rastgele: boşluklar rastgele veriyle dolu'
Assert-True ((Hash-Region $img (1 * $MiB) (8 * $MiB)) -eq $h.Esp -and (Hash-Region $img (20 * $MiB) (10 * $MiB)) -eq $h.Basic -and (Hash-Region $img (50 * $MiB) (8 * $MiB)) -eq $h.Linux) 'ayrılmamış rastgele: bölümler aynen duruyor'

# 3c) doğrulamasız, üç geçiş (sıfır, bir, rastgele): son geçiş rastgele
$img = Copy-Image 'gpt_valid.img'
$r = Run-Raw @{ Scope = 'Unallocated'; Image = $img; Method = 'dod3'; Verify = 'none' }
Assert-True ($r.Ok -eq $true -and $r.Passes -eq 3 -and $r.Written -eq [double](93 * $MiB) -and $r.Verified -eq 0 -and $r.VerifyKind -eq '') 'ayrılmamış 3 geçiş: üç kat yazıldı, doğrulama yok'
Assert-True ((Distinct-Count $img (10 * $MiB)) -ge 250) 'ayrılmamış 3 geçiş: son geçiş rastgele'

# 3d) Windows’un bildirdiği ek bölüm boşluğu böler
$img = Copy-Image 'gpt_valid.img'
$r = Run-Raw @{ Scope = 'Unallocated'; Image = $img; Method = 'zero'; Verify = 'full' } $liveExtra
Assert-True ($r.Ok -eq $true -and $r.Ranges -eq 1 -and $r.Written -eq [double](20 * $MiB)) 'ek Windows bölümü: yalnızca 30–50 MiB yazıldı'
Assert-True ((Is-Fill $img (9 * $MiB) (11 * $MiB) 221) -and (Is-Fill $img (30 * $MiB) (20 * $MiB) 0)) 'ek Windows bölümü: 9–20 MiB aralığına dokunulmadı'

# 3e) yapısı çözülemeyen imaj: tümü dolu sayılır, yapılacak bir şey yok
$img = Copy-Image 'ntfs.img'
$hn = Hash-All $img
$liveN = New-RawLive @{ Size = [double](([System.IO.FileInfo]$img).Length); Parts = @() }
$r = Run-Raw @{ Scope = 'Unallocated'; Image = $img; Method = 'zero'; Verify = 'none' } $liveN
Assert-True ($r.Ok -eq $true -and $r.Nothing -eq $true -and $r.Written -eq 0 -and $r.Ranges -eq 0 -and @($r.Notes).Count -ge 1) 'çözülemeyen düzen: yapılacak bir şey yok'
Assert-True ($r.Notes[0] -match 'Ayrılmamış alan bulunamadı') 'çözülemeyen düzen: neden yazılı'
Assert-Eq (Hash-All $img) $hn 'çözülemeyen düzen: imaj değişmedi'
Assert-Eq $script:Calls.Count 0 'çözülemeyen düzen: Windows komutu çağrılmadı'
$img = Copy-Image 'mbr2.img'
$hm = Hash-All $img
$liveM = New-RawLive @{ Size = [double](([System.IO.FileInfo]$img).Length); Parts = @() }
$r = Run-Raw @{ Scope = 'Unallocated'; Image = $img } $liveM
Assert-True ($r.Ok -eq $true -and $r.Nothing -eq $true) 'küçük MBR imajı: 8 MiB boşluk yok'
Assert-Eq (Hash-All $img) $hm 'küçük MBR imajı: değişmedi'

# 3f) bölüm tablosu olmayan disk: tüm disk ayrılmamış sayılır, uçlarda 1 MiB korunur
$bos = Join-Path $tmp 'bos40.img'
$b40 = New-Object byte[] (40 * $MiB)
[Array]::Fill[byte]($b40, [byte]90, 4096, ($MiB - 4096))
[Array]::Fill[byte]($b40, [byte]90, (39 * $MiB), $MiB)
[System.IO.File]::WriteAllBytes($bos, $b40)
$liveB = New-RawLive @{ Size = [double](40 * $MiB); Parts = @(); Letters = @() }
$r = Run-Raw @{ Scope = 'Unallocated'; Image = $bos; Method = 'random'; Verify = 'full' } $liveB
Assert-True ($r.Ok -eq $true -and $r.Ranges -eq 1 -and $r.Written -eq [double](38 * $MiB) -and $r.Verified -eq [double](38 * $MiB)) 'boş tablo: tüm disk (uçlar hariç) yazıldı ve doğrulandı'
Assert-True ((Distinct-Count $bos (10 * $MiB)) -ge 250) 'boş tablo: ortası rastgele'
Assert-True ((Is-Fill $bos (4096) ($MiB - 4096) 90) -and (Is-Fill $bos (39 * $MiB) $MiB 90) -and (Is-Fill $bos 0 4096 0)) 'boş tablo: baştaki ve sondaki 1 MiB korundu'

# =====================================================================
#  4) bölüm silme
# =====================================================================
$img = Copy-Image 'gpt_valid.img'
$r = Run-Raw @{ Scope = 'Partition'; Part = 2; Image = $img; Method = 'random'; Verify = 'full'; After = 'ntfs' }
Assert-True ($r.Ok -eq $true -and $r.Started -eq $true -and $r.Part -eq 2 -and $r.Written -eq [double](10 * $MiB) -and $r.Verified -eq [double](10 * $MiB) -and $r.BadUnits -eq 0) 'bölüm: yazıldı ve doğrulandı'
Assert-True ($r.After -eq 'ntfs' -and $r.Letter -eq 'F:' -and $r.AfterDone -match 'NTFS') 'bölüm: yeni bölüm açıldı, harf bildirildi'
Assert-Eq (Calls-Text) ('remove:5/2 ; update ; new:5/False/' + [string](20 * $MiB) + '/' + [string](10 * $MiB) + '/ntfs/MBR ; update') 'bölüm: komut sırası (kaldır, yenile, aç, yenile); USB bellek MBR'
Assert-True ((Distinct-Count $img (22 * $MiB)) -ge 250 -and -not (Is-Fill $img (20 * $MiB) (10 * $MiB) 187)) 'bölüm: alan rastgele veriyle yazıldı'
Assert-True ((Hash-Region $img (1 * $MiB) (8 * $MiB)) -eq $h.Esp -and (Hash-Region $img (50 * $MiB) (8 * $MiB)) -eq $h.Linux -and (Hash-Region $img 0 $MiB) -eq $h.Head -and (Hash-Region $img (58 * $MiB) (6 * $MiB)) -eq $h.Tail) 'bölüm: diğer bölümler ve tablo yapıları aynen'
Assert-True (Is-Fill $img (9 * $MiB) (11 * $MiB) 221) 'bölüm: komşu boşluğa dokunulmadı'
Assert-True (Log-Has 'Bölüm 2 kaldırılıyor') 'bölüm: günlük'

# yeni bölüm açılamazsa not düşer, iş başarılı sayılır
$img = Copy-Image 'gpt_valid.img'
Reset-Raw; $script:FailNew = $true
$script:LiveModel = New-RawLive
$r = Job_WipeRaw @{ Scope = 'Partition'; Part = 2; Image = $img; Disk = 5; Method = 'zero'; Verify = 'sample'; After = 'exfat'; Expect = (Get-WipeExpect $script:LiveModel) }
Assert-True ($r.Ok -eq $true -and $r.Letter -eq '' -and $r.AfterDone -eq '' -and @($r.Notes).Count -eq 1 -and $r.Notes[0] -match 'Yeni bölüm açılamadı' -and $r.Notes[0] -match 'biçimlenemedi') 'bölüm: biçimleme hatası nota yazılır, iş başarılı'
Assert-True (Is-Fill $img (20 * $MiB) (10 * $MiB) 0) 'bölüm: biçimleme hatasında da alan silinmişti'
# FAT32 küçük bölüme açılır; biçim sonrası boş bırak
$img = Copy-Image 'gpt_valid.img'
$r = Run-Raw @{ Scope = 'Partition'; Part = 2; Image = $img; Method = 'zero'; Verify = 'none'; After = 'fat32' }
Assert-True ($r.Ok -eq $true -and $r.AfterDone -match 'FAT32' -and (Calls-Text) -match '/fat32/') 'bölüm: FAT32 küçük bölümde serbest'
$img = Copy-Image 'gpt_valid.img'
$r = Run-Raw @{ Scope = 'Partition'; Part = 2; Image = $img; Method = 'zero'; Verify = 'none'; After = 'none' }
Assert-True ($r.Ok -eq $true -and $r.AfterDone -eq '' -and $r.Letter -eq '' -and (Calls-Text) -eq 'remove:5/2 ; update ; update') 'bölüm: sonra=boş ise yeni bölüm açılmaz, depolama iki kez yenilenir (başta ve sonda)'

# =====================================================================
#  5) tüm disk
# =====================================================================
$img = Copy-Image 'gpt_valid.img'
$r = Run-Raw @{ Scope = 'Disk'; Image = $img; Method = 'random'; Verify = 'full'; After = 'exfat' } (New-RawLive @{ Bus = 'SATA'; Media = 'HDD' })
Assert-True ($r.Ok -eq $true -and $r.Started -eq $true -and $r.Written -eq [double](64 * $MiB) -and $r.Verified -eq [double](64 * $MiB) -and $r.BadUnits -eq 0) 'disk: tamamı yazıldı ve doğrulandı'
Assert-Eq (Calls-Text) 'clear:5 ; update ; new:5/True/0/0/exfat/GPT ; update' 'disk: komut sırası; SATA disk GPT olarak başlatılır'
Assert-True ($r.Letter -eq 'F:' -and $r.AfterDone -match 'exFAT') 'disk: yeni bölüm ve harf'
Assert-True ((Is-Fill $img 0 $MiB 0) -and (Is-Fill $img (63 * $MiB) $MiB 0)) 'disk: baştaki ve sondaki 1 MiB sıfırlandı (tablo yapıları kalmaz)'
Assert-True ((Distinct-Count $img (10 * $MiB)) -ge 250 -and (Distinct-Count $img (40 * $MiB)) -ge 250 -and (Distinct-Count $img (60 * $MiB)) -ge 250) 'disk: orta bölge rastgele'
Assert-True ((Hash-Region $img (1 * $MiB) (8 * $MiB)) -ne $h.Esp -and (Hash-Region $img (20 * $MiB) (10 * $MiB)) -ne $h.Basic -and (Hash-Region $img (50 * $MiB) (8 * $MiB)) -ne $h.Linux) 'disk: bölümlerin içeriği kalmadı'
# USB bellek ve MBR kararı
$img = Copy-Image 'gpt_valid.img'
$r = Run-Raw @{ Scope = 'Disk'; Image = $img; Method = 'zero'; Verify = 'sample'; After = 'ntfs' } (New-RawLive @{ Bus = 'USB' })
Assert-True ($r.Ok -eq $true -and (Calls-Text) -match 'new:5/True/0/0/ntfs/MBR') 'disk: USB bellek MBR olarak başlatılır'
Assert-True (Is-Fill $img 0 (64 * $MiB) 0) 'disk sıfır yöntemi: tüm imaj sıfır'
Assert-Eq $r.Written ([double](64 * $MiB)) 'disk sıfır yöntemi: yalnızca bir kez yazıldı (uç sıfırlama gerekmez)'
$img = Copy-Image 'gpt_valid.img'
$r = Run-Raw @{ Scope = 'Disk'; Image = $img; Method = 'zero'; Verify = 'none'; After = 'none' } (New-RawLive @{ Bus = 'SATA'; Style = 'MBR'; Media = 'SSD' })
Assert-True ($r.Ok -eq $true -and (Calls-Text) -eq 'clear:5 ; update ; update') 'disk: sonra=boş ise yalnızca temizlenir, depolama başta ve sonda yenilenir'
$img = Copy-Image 'gpt_valid.img'
$r = Run-Raw @{ Scope = 'Disk'; Image = $img; Method = 'zero'; Verify = 'none'; After = 'ntfs' } (New-RawLive @{ Bus = 'SATA'; Style = 'MBR' })
Assert-True ((Calls-Text) -match '/ntfs/MBR') 'disk: zaten MBR olan disk MBR kalır'
# üç geçiş (sıfır, bir, rastgele) tam doğrulama
$img = Copy-Image 'gpt_valid.img'
$r = Run-Raw @{ Scope = 'Disk'; Image = $img; Method = 'dod3'; Verify = 'full'; After = 'none' }
Assert-True ($r.Ok -eq $true -and $r.Passes -eq 3 -and $r.Written -eq [double](192 * $MiB) -and $r.Verified -eq [double](64 * $MiB) -and $r.BadUnits -eq 0) 'disk 3 geçiş: üç kat yazıldı, son geçiş doğrulandı'
Assert-True ((Is-Fill $img 0 $MiB 0) -and (Is-Fill $img (63 * $MiB) $MiB 0) -and (Distinct-Count $img (30 * $MiB)) -ge 250) 'disk 3 geçiş: uçlar sıfır, orta rastgele'
# doğrulamasız
$img = Copy-Image 'gpt_valid.img'
$r = Run-Raw @{ Scope = 'Disk'; Image = $img; Method = 'random'; Verify = 'none'; After = 'none' }
Assert-True ($r.Ok -eq $true -and $r.Verified -eq 0 -and $r.VerifyKind -eq '' -and (Is-Fill $img 0 $MiB 0)) 'disk: doğrulamasız çalışır, uçlar yine sıfırlanır'

# =====================================================================
#  6) korumalar: hiçbir şey yazılmaz, hiçbir komut çağrılmaz
# =====================================================================
function Test-Refused([string]$Name, [hashtable]$P, $Live, [string]$Pattern) {
    $im = Copy-Image 'gpt_valid.img'
    $before = Hash-All $im
    $P.Image = $im
    $r = Run-Raw $P $Live
    Assert-True ($r.Ok -eq $false -and $r.Error -match $Pattern) ("reddedildi: $Name")
    Assert-Eq (Hash-All $im) $before ("reddedildi, imaj değişmedi: $Name")
    Assert-Eq $script:Calls.Count 0 ("reddedildi, Windows komutu çağrılmadı: $Name")
    Assert-True ($r.Started -eq $false -and $r.Written -eq 0) ("reddedildi, başlamadı: $Name")
    Remove-Item -LiteralPath $im -Force -ErrorAction SilentlyContinue
}
Test-Refused 'sistem diski' @{ Scope = 'Disk'; Method = 'zero' } (New-RawLive @{ IsSystem = $true }) 'Windows bu diskte çalışıyor'
Test-Refused 'önyükleme diski, ayrılmamış alan' @{ Scope = 'Unallocated'; Method = 'zero' } (New-RawLive @{ IsBoot = $true }) 'Windows bu diskte çalışıyor'
Test-Refused 'Multimizer diski' @{ Scope = 'Disk'; Method = 'zero' } (New-RawLive @{ Roles = @('E: sürücüsü: Multimizer bu sürücüde çalışıyor') }) 'Multimizer bu sürücüde'
Test-Refused 'çevrimdışı disk' @{ Scope = 'Disk'; Method = 'zero' } (New-RawLive @{ Offline = $true }) 'çevrimdışı'
Test-Refused 'salt okunur disk' @{ Scope = 'Partition'; Part = 2; Method = 'zero' } (New-RawLive @{ ReadOnly = $true }) 'salt okunur'
Test-Refused 'havuz üyesi disk' @{ Scope = 'Disk'; Method = 'zero' } (New-RawLive @{ Pool = $true }) 'havuz'
Test-Refused 'kümelenmiş disk' @{ Scope = 'Disk'; Method = 'zero' } (New-RawLive @{ Clustered = $true }) 'küme'
Test-Refused 'disk yok' @{ Scope = 'Disk'; Method = 'zero'; Expect = @{ Size = [double](64 * $MiB) } } 'YOK' 'bulunamadı'
Test-Refused 'boyut değişmiş' @{ Scope = 'Disk'; Method = 'zero'; Expect = @{ Size = [double](32 * $MiB) } } (New-RawLive) 'değişmiş'
Test-Refused 'ad değişmiş' @{ Scope = 'Unallocated'; Method = 'zero'; Expect = @{ Size = [double](64 * $MiB); Name = 'Başka Disk' } } (New-RawLive) 'değişmiş'
Test-Refused 'seri numarası değişmiş' @{ Scope = 'Partition'; Part = 2; Method = 'zero'; Expect = @{ Size = [double](64 * $MiB); Serial = 'BASKA' } } (New-RawLive) 'değişmiş'
Test-Refused 'kimlik değişmiş' @{ Scope = 'Disk'; Method = 'zero'; Expect = @{ Size = [double](64 * $MiB); UniqueId = 'BASKA' } } (New-RawLive) 'değişmiş'
Test-Refused 'onay bilgisi yok' @{ Scope = 'Disk'; Method = 'zero'; Expect = $null } (New-RawLive) 'doğrulanamadı'
Test-Refused 'olmayan bölüm' @{ Scope = 'Partition'; Part = 42; Method = 'zero' } (New-RawLive) 'Bölüm bulunamadı'
$lsys = New-RawLive; $lsys.Parts[0].IsSystem = $true
Test-Refused 'Windows bölümü' @{ Scope = 'Partition'; Part = 1; Method = 'zero' } $lsys 'Windows.a ait'
$exMoved = Get-WipeExpect (New-RawLive); $exMoved.PartOffset = [double](22 * $MiB); $exMoved.PartSize = [double](10 * $MiB)
Test-Refused 'bölüm konumu değişmiş' @{ Scope = 'Partition'; Part = 2; Method = 'zero'; Expect = $exMoved } (New-RawLive) 'onay verdiğiniz andan sonra değişmiş'
Test-Refused 'bilinmeyen kapsam' @{ Scope = 'Hepsi'; Method = 'zero' } (New-RawLive) 'Bilinmeyen silme kapsamı'
Test-Refused 'boş kapsam' @{ Scope = ''; Method = 'zero' } (New-RawLive) 'Bilinmeyen silme kapsamı'

# imaj yoksa, disk numarası geçersizse
Reset-Raw
$script:LiveModel = New-RawLive
$r = Job_WipeRaw @{ Scope = 'Disk'; Disk = 5; Image = (Join-Path $tmp 'yok.img'); Expect = (Get-WipeExpect $script:LiveModel) }
Assert-True ($r.Ok -eq $false -and $r.Error -match 'imajı bulunamadı' -and $script:Calls.Count -eq 0) 'olmayan imaj: hata, komut yok'
$r = Job_WipeRaw @{ Scope = 'Disk'; Disk = -3; Expect = (Get-WipeExpect $script:LiveModel) }
Assert-True ($r.Ok -eq $false -and $r.Error -match 'Geçerli bir disk' -and $script:Calls.Count -eq 0) 'geçersiz disk numarası: hata, komut yok'

# gerçek aygıt yolu: yönetici değilse hiç denenmez; yöneticiyken bile aygıt açılamazsa hiçbir yıkıcı komut çalışmaz
Reset-Raw
$script:IsAdmin = $false
$script:LiveModel = New-RawLive
$r = Job_WipeRaw @{ Scope = 'Disk'; Disk = 5; Expect = (Get-WipeExpect $script:LiveModel) }
Assert-True ($r.Ok -eq $false -and $r.Error -match 'yönetici olarak' -and $script:Calls.Count -eq 0) 'gerçek disk: yönetici değilse reddedilir'
$script:IsAdmin = $true
$r = Job_WipeRaw @{ Scope = 'Disk'; Disk = 5; Expect = (Get-WipeExpect $script:LiveModel) }
Assert-True ($r.Ok -eq $false -and $r.Error -ne '' -and $r.Started -eq $false) 'gerçek disk: aygıt açılamazsa işlem başlamaz'
Assert-Eq $script:Calls.Count 0 'gerçek disk: aygıt açılamayınca Windows komutu çağrılmadı (plan, yıkıcı adımdan önce)'
Assert-True (Log-Has 'Silme başlatılmadı') 'gerçek disk: günlükte neden'

# 40 GB’lık seyrek imaj: FAT32 sınırı, hiçbir şey yazılmadan reddedilir
$big = Join-Path $tmp 'seyrek40g.img'
$fsz = [System.IO.File]::Create($big); $fsz.SetLength([long]40 * 1024 * $MiB); $fsz.Dispose()
$liveBig = New-RawLive @{ Size = [double]([long]40 * 1024 * $MiB); Parts = @() }
$r = Run-Raw @{ Scope = 'Disk'; Image = $big; Method = 'zero'; Verify = 'none'; After = 'fat32' } $liveBig
Assert-True ($r.Ok -eq $false -and $r.Error -match 'FAT32 yalnızca 32 GB' -and $r.Written -eq 0 -and $script:Calls.Count -eq 0 -and $r.Started -eq $false) 'FAT32: 32 GB üstü diskte işlem başlamaz'
$r = Run-Raw @{ Scope = 'Partition'; Part = 5; Image = $big; Method = 'zero'; Verify = 'none'; After = 'fat32' } (New-RawLive @{ Size = [double]([long]40 * 1024 * $MiB); Parts = @(@{ Number = 5; Offset = [double]$MiB; Size = [double]([long]36 * 1024 * $MiB); Letter = ''; Type = 'Basic'; IsSystem = $false; IsBoot = $false; Fs = ''; Label = '' }) })
Assert-True ($r.Ok -eq $false -and $r.Error -match 'FAT32 yalnızca 32 GB' -and $script:Calls.Count -eq 0) 'FAT32: 32 GB üstü bölümde işlem başlamaz'
Remove-Item -LiteralPath $big -Force

# =====================================================================
#  7) hata ve iptal
# =====================================================================
# bölüm kaldırma başarısız: hiçbir veri yazılmaz
$img = Copy-Image 'gpt_valid.img'
$hb = Hash-All $img
Reset-Raw
$script:LiveModel = New-RawLive
$script:FailRemove = $true
$r = Job_WipeRaw @{ Scope = 'Partition'; Part = 2; Image = $img; Disk = 5; Method = 'zero'; Verify = 'none'; Expect = (Get-WipeExpect $script:LiveModel) }
Assert-True ($r.Ok -eq $false -and $r.Started -eq $false -and $r.Written -eq 0 -and $r.Error -match 'Windows bölümü kaldıramadı' -and $r.Error -match 'Hiçbir veri yazılmadı') 'bölüm kaldırılamadı: işlem durur'
Assert-Eq (Hash-All $img) $hb 'bölüm kaldırılamadı: imaj değişmedi'
Assert-Eq (Calls-Text) 'remove:5/2' 'bölüm kaldırılamadı: başka komut çağrılmadı'
# disk temizleme başarısız
Reset-Raw
$script:LiveModel = New-RawLive
$script:FailClear = $true
$r = Job_WipeRaw @{ Scope = 'Disk'; Image = $img; Disk = 5; Method = 'zero'; Verify = 'none'; Expect = (Get-WipeExpect $script:LiveModel) }
Assert-True ($r.Ok -eq $false -and $r.Started -eq $false -and $r.Error -match 'disk temizlenemedi') 'disk temizlenemedi: işlem durur'
Assert-Eq (Hash-All $img) $hb 'disk temizlenemedi: imaj değişmedi'
Assert-Eq (Calls-Text) 'clear:5' 'disk temizlenemedi: yalnızca temizleme denendi'

# iptal: bölümler kaldırıldıktan sonra
$img = Copy-Image 'gpt_valid.img'
Reset-Raw
$script:LiveModel = New-RawLive
$script:CancelAfter = 0
$r = Job_WipeRaw @{ Scope = 'Partition'; Part = 2; Image = $img; Disk = 5; Method = 'random'; Verify = 'full'; After = 'ntfs'; Expect = (Get-WipeExpect $script:LiveModel) }
Assert-True ($r.Canceled -eq $true -and $r.Ok -eq $false -and $r.Started -eq $true) 'iptal: iptal edildi, bölüm kaldırılmıştı'
Assert-True ($r.Letter -eq '' -and $r.Verified -eq 0) 'iptal: doğrulama ve biçimleme yapılmadı'
Assert-True ((Calls-Text) -notmatch 'new:') 'iptal: yeni bölüm açılmadı'
Assert-True ((Calls-Text) -match 'remove:5/2' -and (Calls-Text) -match 'update') 'iptal: depolama yenilendi'
Assert-True (Log-Has 'İptal edildi') 'iptal: günlükte'
Assert-True (Log-Has 'iptal edildi') 'iptal: kayıt satırında'
# iptal: ayrılmamış alan, hiçbir komut yok
$img = Copy-Image 'gpt_valid.img'
Reset-Raw
$script:LiveModel = New-RawLive
$script:CancelAfter = 0
$r = Job_WipeRaw @{ Scope = 'Unallocated'; Image = $img; Disk = 5; Method = 'random'; Verify = 'sample'; Expect = (Get-WipeExpect $script:LiveModel) }
Assert-True ($r.Canceled -eq $true -and $r.Ok -eq $false -and $r.Started -eq $false -and $script:Calls.Count -eq 0) 'iptal: ayrılmamış alanda komut yok'
Assert-True ((Hash-Region $img (1 * $MiB) (8 * $MiB)) -eq $h.Esp -and (Hash-Region $img (20 * $MiB) (10 * $MiB)) -eq $h.Basic) 'iptal: bölümlere dokunulmadı'

Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
Show-Result
