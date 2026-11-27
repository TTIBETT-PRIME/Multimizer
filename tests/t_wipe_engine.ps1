. "$PSScriptRoot/lib.ps1"
# Silme motoru (Eklenti\DiskSilme.ps1 içindeki Mm.WipeEngine): AES-256-CTR akışı, imaj üzerinde yazma ve doğrulama, bölüm düzeni, hata ve iptal.
# Gerçek diske dokunulmaz; yalnızca geçici imaj dosyaları ve tests\gen_images.py ile üretilen sentetik imajlar kullanılır.
Import-Fn 'Format-Size'
[void](Import-Ext 'DiskSilme')

$script:Logs = New-Object System.Collections.ArrayList
function Write-WhLog([string]$Message, [string]$Level = 'INFO') { [void]$script:Logs.Add($Level + ': ' + $Message) }
function Set-JobProgress($Done, $Total, [string]$Label = '') { }
function Test-JobCancel { return $false }

$MiB = 1048576
$root = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$imgDir = Join-Path (Join-Path $root 'work') 'img'
if (-not (Test-Path -LiteralPath (Join-Path $imgDir 'expect.json')) -or -not (Test-Path -LiteralPath (Join-Path $imgDir 'gpt_valid.img'))) {
    [void][System.IO.Directory]::CreateDirectory($imgDir)
    & python3 (Join-Path $PSScriptRoot 'gen_images.py') $imgDir | Out-Null
}
function Img([string]$Name) { return (Join-Path $imgDir $Name) }
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('mm-silme-motor-' + [System.Guid]::NewGuid().ToString('N').Substring(0, 8))
[void][System.IO.Directory]::CreateDirectory($tmp)
function Hash-Bytes([byte[]]$B) { return [Convert]::ToBase64String((New-Object System.Security.Cryptography.SHA256Managed).ComputeHash($B)) }
function Same-Bytes($A, $B) { return ((Hash-Bytes $A) -eq (Hash-Bytes $B)) }
function New-Img([string]$Name, [int]$Size, [byte]$Fill) {
    $p = Join-Path $tmp $Name
    $b = New-Object byte[] $Size
    if ($Fill -ne 0) { for ($i = 0; $i -lt $b.Length; $i++) { $b[$i] = $Fill } }
    [System.IO.File]::WriteAllBytes($p, $b)
    return $p
}
function Get-Region([string]$Path, [long]$Pos, [int]$Len) {
    $fs = [System.IO.File]::OpenRead($Path)
    try { [void]$fs.Seek($Pos, [System.IO.SeekOrigin]::Begin); $b = New-Object byte[] $Len; [void]$fs.Read($b, 0, $Len); return $b } finally { $fs.Dispose() }
}
function New-Ext([long]$Start, [long]$Length) { return New-Object Mm.WipeExtent -ArgumentList $Start, $Length, 'sinama' }
$noProg = $null

# =====================================================================
#  1) derleme
# =====================================================================
Assert-Eq (Initialize-MmWipe) '' 'motor derleniyor'
Assert-True ($null -ne ('Mm.WipeEngine' -as [type]) -and $null -ne ('Mm.WipeTarget' -as [type]) -and $null -ne ('Mm.WipeLayout' -as [type])) 'türler yüklü'
Assert-Eq (Initialize-MmWipe) '' 'ikinci çağrı sorunsuz'

# =====================================================================
#  2) AES-256-CTR akışı
# =====================================================================
$key = [Mm.WipeEngine]::NewKey()
Assert-Eq $key.Length 32 'anahtar 32 bayt'
Assert-True (-not (Same-Bytes $key ([Mm.WipeEngine]::NewKey()))) 'her anahtar farklı'
$ws = [Mm.WipeStream]::new(0, $key, 0)
$ref = New-Object byte[] 40000
$ws.Fill($ref, 0, 40000, 0)
$part = New-Object byte[] 40000
$ws.Fill($part, 0, 4003, 0)
$ws.Fill($part, 4003, 35997, 4003)
Assert-True (Same-Bytes $ref $part) 'parçalı üretim tek seferlikle aynı'
foreach ($pos in @(1, 15, 16, 17, 4096, 12345, 39000)) {
    $n = [math]::Min(777, 40000 - $pos)
    $x = New-Object byte[] $n
    $ws.Fill($x, 0, $n, $pos)
    $slice = New-Object byte[] $n
    [Array]::Copy($ref, $pos, $slice, 0, $n)
    Assert-True (Same-Bytes $x $slice) ("rastgele erişim: konum $pos")
}
$distinct = @($ref | Sort-Object -Unique).Count
Assert-True ($distinct -ge 250) 'rastgele akışta bayt çeşitliliği yüksek'
$zeros = @($ref | Where-Object { $_ -eq 0 }).Count
Assert-True ($zeros -lt 400) 'sıfır baytı oranı makul'
$ws1 = [Mm.WipeStream]::new(0, $key, 1)
$p1 = New-Object byte[] 40000
$ws1.Fill($p1, 0, 40000, 0)
Assert-True (-not (Same-Bytes $ref $p1)) 'her geçiş ayrı bir akış'
$wsk = [Mm.WipeStream]::new(0, ([Mm.WipeEngine]::NewKey()), 0)
$pk = New-Object byte[] 40000
$wsk.Fill($pk, 0, 40000, 0)
Assert-True (-not (Same-Bytes $ref $pk)) 'her anahtar ayrı bir akış'
$wsz = [Mm.WipeStream]::new(1, $key, 0)
$z = New-Object byte[] 5000; for ($i = 0; $i -lt 5000; $i++) { $z[$i] = 7 }
$wsz.Fill($z, 0, 5000, 0)
Assert-Eq @($z | Where-Object { $_ -ne 0 }).Count 0 'sıfır kipi: hepsi 0'
$wso = [Mm.WipeStream]::new(2, $key, 0)
$o = New-Object byte[] 5000
$wso.Fill($o, 0, 5000, 0)
Assert-Eq @($o | Where-Object { $_ -ne 255 }).Count 0 'bir kipi: hepsi 0xFF'
$threw = $false
try { [void][Mm.WipeStream]::new(0, (New-Object byte[] 0), 0) } catch { $threw = $true }
Assert-True $threw 'anahtarsız rastgele akış kurulamaz'
foreach ($s in @($ws, $ws1, $wsk, $wsz, $wso)) { $s.Dispose() }

# =====================================================================
#  3) imaj üzerinde yazma ve doğrulama
# =====================================================================
$img = New-Img 'a.img' (16 * $MiB) 165
$headBefore = Hash-Bytes (Get-Region $img 0 $MiB)
$tailBefore = Hash-Bytes (Get-Region $img (5 * $MiB) (11 * $MiB))
$t = [Mm.WipeTarget]::Open($img, $true)
Assert-True ($t.Length -eq 16 * $MiB -and $t.IsDevice -eq $false -and $t.Writable -eq $true) 'imaj hedefi açıldı'
$ext = [Mm.WipeExtent[]]@((New-Ext $MiB (4 * $MiB)))
$r = [Mm.WipeEngine]::Fill($t, $ext, [int[]]@(0, 0), $key, $noProg)
Assert-True ($r.Error -eq '' -and $r.WriteErrors -eq 0 -and $r.Canceled -eq $false) 'iki geçiş hatasız'
Assert-Eq $r.Written (8 * $MiB) 'yazılan = aralık x geçiş'
Assert-Eq $r.Planned (8 * $MiB) 'planlanan'
Assert-Eq $r.Passes 2 'geçiş sayısı'
Assert-Eq (Hash-Bytes (Get-Region $img 0 $MiB)) $headBefore 'aralık öncesi değişmedi'
Assert-Eq (Hash-Bytes (Get-Region $img (5 * $MiB) (11 * $MiB))) $tailBefore 'aralık sonrası değişmedi'
$v = [Mm.WipeEngine]::Verify($t, $ext, 0, $key, 1, 0, $noProg)
Assert-True ($v.Error -eq '' -and $v.BadUnits -eq 0 -and $v.Verified -eq 4 * $MiB) 'tam doğrulama: son geçiş eşleşir'
$v0 = [Mm.WipeEngine]::Verify($t, $ext, 0, $key, 0, 0, $noProg)
Assert-True ($v0.BadUnits -gt 0 -and $v0.FirstBad -ge $MiB) 'önceki geçişin akışıyla doğrulama başarısız (geçişler farklı)'
$vs = [Mm.WipeEngine]::Verify($t, $ext, 0, $key, 1, 12, $noProg)
Assert-True ($vs.Error -eq '' -and $vs.BadUnits -eq 0 -and $vs.Verified -gt 0 -and $vs.Verified -le 4 * $MiB) 'örnekle doğrulama'
$vo = [Mm.WipeEngine]::Verify($t, $ext, 0, ([Mm.WipeEngine]::NewKey()), 1, 0, $noProg)
Assert-True ($vo.BadUnits -gt 0) 'yanlış anahtarla doğrulama başarısız'
$t.Dispose()
# bozulma: yazılan alanda tek bayt değişirse tam doğrulama yakalar
$fsb = [System.IO.File]::Open($img, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite)
[void]$fsb.Seek(3 * $MiB + 123, [System.IO.SeekOrigin]::Begin)
$cur = $fsb.ReadByte()
[void]$fsb.Seek(3 * $MiB + 123, [System.IO.SeekOrigin]::Begin)
$fsb.WriteByte([byte](($cur + 1) % 256))
$fsb.Dispose()
$t = [Mm.WipeTarget]::Open($img, $false)
$vb = [Mm.WipeEngine]::Verify($t, $ext, 0, $key, 1, 0, $noProg)
Assert-True ($vb.BadUnits -eq 1 -and $vb.FirstBad -eq $MiB) 'tek baytlık bozulma tam doğrulamada yakalanır (birim başlangıcı bildirilir)'
$wr = [Mm.WipeEngine]::Fill($t, $ext, [int[]]@(0), $key, $noProg)
Assert-True ($wr.Error -ne '') 'salt okunur açılan hedefe yazılamaz'
$t.Dispose()

# sıfır, bir ve karışık desenler
$img2 = New-Img 'b.img' (8 * $MiB) 90
$t = [Mm.WipeTarget]::Open($img2, $true)
$ext2 = [Mm.WipeExtent[]]@((New-Ext (2 * $MiB) (3 * $MiB)))
$r = [Mm.WipeEngine]::Fill($t, $ext2, [int[]]@(1), $key, $noProg)
Assert-True ($r.Error -eq '' -and $r.Written -eq 3 * $MiB) 'sıfır geçişi'
Assert-Eq @((Get-Region $img2 (2 * $MiB) 4096) | Where-Object { $_ -ne 0 }).Count 0 'alan sıfırlandı'
Assert-Eq ((Get-Region $img2 (2 * $MiB - 1) 1)[0]) 90 'komşu bayt (önce) dokunulmadı'
Assert-Eq ((Get-Region $img2 (5 * $MiB) 1)[0]) 90 'komşu bayt (sonra) dokunulmadı'
$vz = [Mm.WipeEngine]::Verify($t, $ext2, 1, $key, 0, 0, $noProg)
Assert-True ($vz.BadUnits -eq 0 -and $vz.Verified -eq 3 * $MiB) 'sıfır doğrulaması'
Assert-Eq ([Mm.WipeEngine]::CountNonZeroUnits($t, $ext2, 0, $key)) 0 'sıfır olmayan birim yok'
$r = [Mm.WipeEngine]::Fill($t, $ext2, [int[]]@(2), $key, $noProg)
Assert-Eq @((Get-Region $img2 (3 * $MiB) 4096) | Where-Object { $_ -ne 255 }).Count 0 'bir geçişi: hepsi 0xFF'
Assert-True ([Mm.WipeEngine]::CountNonZeroUnits($t, $ext2, 0, $key) -gt 0) 'sıfır olmayan birimler sayılır'
$r = [Mm.WipeEngine]::Fill($t, $ext2, [int[]]@(1, 2, 0), $key, $noProg)
Assert-True ($r.Error -eq '' -and $r.Written -eq 9 * $MiB -and $r.Passes -eq 3) 'üç geçiş: sıfır, bir, rastgele'
$vm = [Mm.WipeEngine]::Verify($t, $ext2, 0, $key, 2, 0, $noProg)
Assert-True ($vm.BadUnits -eq 0) 'son geçiş (rastgele, akış 2) doğrulanır'
$e0 = [Mm.WipeEngine]::Fill($t, $ext2, [int[]]@(), $key, $noProg)
Assert-True ($e0.Error -ne '') 'geçişsiz çağrı reddedilir'
$t.Dispose()

# =====================================================================
#  4) aralık denetimi
# =====================================================================
$t = [Mm.WipeTarget]::Open($img2, $true)
Assert-True ([Mm.WipeEngine]::CheckExtents($t, $null) -ne '') 'aralık yok'
Assert-True ([Mm.WipeEngine]::CheckExtents($t, [Mm.WipeExtent[]]@()) -ne '') 'boş aralık listesi'
Assert-True ([Mm.WipeEngine]::CheckExtents($t, [Mm.WipeExtent[]]@((New-Ext -1 100))) -match 'Geçersiz') 'eksi başlangıç'
Assert-True ([Mm.WipeEngine]::CheckExtents($t, [Mm.WipeExtent[]]@((New-Ext 10 0))) -match 'Geçersiz') 'sıfır uzunluk'
Assert-True ([Mm.WipeEngine]::CheckExtents($t, [Mm.WipeExtent[]]@((New-Ext (7 * $MiB) (2 * $MiB)))) -match 'dışına') 'diskin dışına taşan aralık'
Assert-True ([Mm.WipeEngine]::CheckExtents($t, [Mm.WipeExtent[]]@((New-Ext 0 (3 * $MiB)), (New-Ext (2 * $MiB) $MiB))) -match 'çakış') 'çakışan aralıklar'
Assert-Eq ([Mm.WipeEngine]::CheckExtents($t, [Mm.WipeExtent[]]@((New-Ext (5 * $MiB) $MiB), (New-Ext 0 $MiB)))) '' 'sırasız ama uygun aralıklar'
$bad = [Mm.WipeEngine]::Fill($t, [Mm.WipeExtent[]]@((New-Ext (7 * $MiB) (2 * $MiB))), [int[]]@(0), $key, $noProg)
Assert-True ($bad.Error -match 'dışına' -and $bad.Written -eq 0) 'geçersiz aralıkta hiçbir şey yazılmaz'
$t.Dispose()

# =====================================================================
#  5) iptal ve yazma hataları
# =====================================================================
$img3 = New-Img 'c.img' (16 * $MiB) 165
$t = [Mm.WipeTarget]::Open($img3, $true)
$two = [Mm.WipeExtent[]]@((New-Ext 0 (4 * $MiB)), (New-Ext (8 * $MiB) (4 * $MiB)))
$cancel = [Mm.WipeProgress]{ param([string]$stage, [long]$done, [long]$total) return $false }
$r = [Mm.WipeEngine]::Fill($t, $two, [int[]]@(0), $key, $cancel)
Assert-True ($r.Canceled -eq $true -and $r.Written -eq 4 * $MiB) 'iptal: ilk aralıktan sonra durur'
Assert-Eq ((Get-Region $img3 (8 * $MiB) 16)[0]) 165 'iptalde ikinci aralığa dokunulmadı'
$cont = [Mm.WipeProgress]{ param([string]$stage, [long]$done, [long]$total) return $true }
$r = [Mm.WipeEngine]::Fill($t, $two, [int[]]@(0), $key, $cont)
Assert-True ($r.Canceled -eq $false -and $r.Written -eq 8 * $MiB) 'ilerleme bildirimi devam derse tamamlanır'
$t.Dispose()

$img4 = New-Img 'd.img' (16 * $MiB) 165
$t = [Mm.WipeTarget]::OpenFaulty($img4, 2 * $MiB, 3 * $MiB)
$r = [Mm.WipeEngine]::Fill($t, ([Mm.WipeExtent[]]@((New-Ext 0 (8 * $MiB)))), [int[]]@(0), $key, $noProg)
Assert-True ($r.WriteErrors -eq 1 -and $r.FirstWriteError -eq 0 -and $r.Error -eq '') 'tek bozuk blok sayılır, işlem sürer'
Assert-Eq $r.Written (4 * $MiB) 'yalnızca yazılabilen blok yazıldı'
Assert-Eq $r.Planned (4 * $MiB) 'planlanan, yazılamayan kadar azalır'
Assert-Eq ((Get-Region $img4 0 16)[0]) 165 'hata veren blok yazılmadı'
$t.Dispose()
$big = Join-Path $tmp 'sparse.img'
$fsb = [System.IO.File]::Create($big); $fsb.SetLength(200 * $MiB); $fsb.Dispose()
$t = [Mm.WipeTarget]::OpenFaulty($big, 0, 200 * $MiB)
$r = [Mm.WipeEngine]::Fill($t, ([Mm.WipeExtent[]]@((New-Ext 0 (160 * $MiB)))), [int[]]@(0), $key, $noProg)
Assert-True ($r.WriteErrors -ge 32 -and $r.Error -match 'Çok sayıda yazma hatası') 'art arda hatada işlem durur'
$t.Dispose()

# =====================================================================
#  6) kanarya sınaması (Probe)
# =====================================================================
$img5 = New-Img 'e.img' (8 * $MiB) 77
$t = [Mm.WipeTarget]::Open($img5, $true)
$pe = [Mm.WipeExtent[]]@((New-Ext $MiB (2 * $MiB)))
$null = [Mm.WipeEngine]::Fill($t, $pe, [int[]]@(0), $key, $noProg)
# Fill akışı aralığın gerçek konumundan başlatır (StreamPos verilmediğinde konum = disk konumu)
$p = [Mm.WipeEngine]::Probe($t, $pe, 0, $key, 0, $noProg)
Assert-True ($p.Units -eq 512 -and $p.Same -eq 512 -and $p.Zeroed -eq 0 -and $p.Changed -eq 0) 'sınama: yazılan akışla aynı'
$null = [Mm.WipeEngine]::Fill($t, $pe, [int[]]@(1), $key, $noProg)
$p = [Mm.WipeEngine]::Probe($t, $pe, 0, $key, 0, $noProg)
Assert-True ($p.Zeroed -eq 512 -and $p.Same -eq 0 -and $p.Changed -eq 0) 'sınama: sıfırlanmış'
$p = [Mm.WipeEngine]::Probe($t, ([Mm.WipeExtent[]]@((New-Ext (4 * $MiB) (1 * $MiB)))), 0, $key, 0, $noProg)
Assert-True ($p.Changed -eq 256 -and $p.Same -eq 0 -and $p.Zeroed -eq 0) 'sınama: başka içerik'
# StreamPos: dosya içinde 0'dan başlayan akış, birimde başka konuma yazılmış
$t.Dispose()
$wsx = [Mm.WipeStream]::new(0, $key, 3)
$data = New-Object byte[] 8192
$wsx.Fill($data, 0, 8192, 0)
$wsx.Dispose()
$fsw = [System.IO.File]::Open($img5, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite)
[void]$fsw.Seek(6 * $MiB, [System.IO.SeekOrigin]::Begin); $fsw.Write($data, 0, 8192); $fsw.Dispose()
$t = [Mm.WipeTarget]::Open($img5, $false)
$sp = New-Ext (6 * $MiB) 8192
$sp.StreamPos = 0
$p = [Mm.WipeEngine]::Probe($t, ([Mm.WipeExtent[]]@($sp)), 0, $key, 3, $noProg)
Assert-True ($p.Units -eq 2 -and $p.Same -eq 2) 'sınama: akış konumu (StreamPos) dikkate alınır'
$pbad = [Mm.WipeEngine]::Probe($t, ([Mm.WipeExtent[]]@((New-Ext (7 * $MiB) (2 * $MiB)))), 0, $key, 0, $noProg)
Assert-True ($pbad.Error -ne '') 'sınama: diskin dışındaki aralık reddedilir'
$pnone = [Mm.WipeEngine]::Probe($t, $null, 0, $key, 0, $noProg)
Assert-True ($pnone.Error -ne '') 'sınama: aralıksız çağrı reddedilir'
$t.Dispose()

# =====================================================================
#  7) hedef açma kuralları
# =====================================================================
function Test-Throws([scriptblock]$Body) { try { & $Body; return $false } catch { return $true } }
Assert-True (Test-Throws { [void][Mm.WipeTarget]::Open('', $false) }) 'boş hedef reddedilir'
Assert-True (Test-Throws { [void][Mm.WipeTarget]::Open('\\.\C:', $false) }) 'ham birim yolu reddedilir'
Assert-True (Test-Throws { [void][Mm.WipeTarget]::Open('\\.\Harddisk0Partition1', $false) }) 'diğer aygıt yolları reddedilir'
Assert-True (Test-Throws { [void][Mm.WipeTarget]::Open('\\?\Volume{12345678-1234-1234-1234-123456789012}', $false) }) 'birim GUID yolu reddedilir'
Assert-True (Test-Throws { [void][Mm.WipeTarget]::Open('C:', $true) }) 'birime doğrudan yazma reddedilir'
Assert-True (Test-Throws { [void][Mm.WipeTarget]::Open((Join-Path $tmp 'yok.img'), $false) }) 'olmayan imaj'
$dn = 0
Assert-True ([Mm.WipeTarget]::DiskNumberOf('PhysicalDrive3', [ref]$dn) -and $dn -eq 3) 'disk numarası: PhysicalDrive3'
Assert-True ([Mm.WipeTarget]::DiskNumberOf('\\.\PHYSICALDRIVE12', [ref]$dn) -and $dn -eq 12) 'disk numarası: aygıt yolu'
Assert-True (-not [Mm.WipeTarget]::DiskNumberOf('PhysicalDrive', [ref]$dn)) 'numarasız ad'
Assert-True (-not [Mm.WipeTarget]::DiskNumberOf('PhysicalDrive1a', [ref]$dn)) 'rakam olmayan ek'
Assert-True (-not [Mm.WipeTarget]::DiskNumberOf('PhysicalDrive12345', [ref]$dn)) 'çok uzun numara'
Assert-True (-not [Mm.WipeTarget]::DiskNumberOf('disk.img', [ref]$dn)) 'dosya adı disk değil'
Assert-True (-not [Mm.WipeTarget]::DiskNumberOf($null, [ref]$dn)) 'boş değer'
Assert-Eq (Resolve-WipeTarget @{ Disk = 3 }).Spec 'PhysicalDrive3' 'iş hedefi: disk numarası'
Assert-Eq (Resolve-WipeTarget @{ Disk = 3 }).Kind 'Disk' 'iş hedefi: tür'
Assert-True ((Resolve-WipeTarget @{ Disk = -1 }).Ok -eq $false) 'iş hedefi: eksi numara'
Assert-True ((Resolve-WipeTarget @{ Disk = 100000 }).Ok -eq $false) 'iş hedefi: çok büyük numara'
Assert-True ((Resolve-WipeTarget @{ }).Ok -eq $false) 'iş hedefi: boş'
Assert-True ((Resolve-WipeTarget @{ Image = (Join-Path $tmp 'yok.img') }).Ok -eq $false) 'iş hedefi: olmayan imaj'
$rt = Resolve-WipeTarget @{ Image = $img; Disk = 2 }
Assert-True ($rt.Ok -eq $true -and $rt.Kind -eq 'Image' -and $rt.Number -eq 2) 'iş hedefi: imaj'

# =====================================================================
#  8) bölüm düzeni: MBR, GPT, tablosuz, bozuk
# =====================================================================
function Read-Occupied([string]$Path) {
    $t = [Mm.WipeTarget]::Open($Path, $false)
    try {
        $style = ''; $note = ''
        $occ = [Mm.WipeLayout]::ReadOccupied($t, [ref]$style, [ref]$note)
        return @{ Style = $style; Note = $note; Occ = @($occ); Length = $t.Length }
    } finally { $t.Dispose() }
}
function Overlaps($A, $B) { return ($A.Start -lt $B.End -and $B.Start -lt $A.End) }

$m = Read-Occupied (Img 'mbr2.img')
Assert-Eq $m.Style 'MBR' 'mbr2: MBR tanındı'
$parts = @($m.Occ | Where-Object { $_.Tag -eq 'bölüm' })
Assert-Eq $parts.Count 2 'mbr2: iki bölüm'
$b0 = Get-Region (Img 'mbr2.img') 0 512
$expectParts = New-Object System.Collections.ArrayList
for ($i = 0; $i -lt 4; $i++) {
    $o = 446 + 16 * $i
    if ($b0[$o + 4] -ne 0) { [void]$expectParts.Add(@{ Start = [long][BitConverter]::ToUInt32($b0, $o + 8) * 512; Length = [long][BitConverter]::ToUInt32($b0, $o + 12) * 512 }) }
}
Assert-Eq $expectParts.Count 2 'mbr2: tabloda iki girdi (bağımsız ayrıştırma)'
for ($i = 0; $i -lt 2; $i++) {
    Assert-True ($parts[$i].Start -eq $expectParts[$i].Start -and $parts[$i].Length -eq $expectParts[$i].Length) "mbr2: bölüm $i konumu tabloyla aynı"
}
Assert-True (@($m.Occ | Where-Object { $_.Tag -eq 'MBR' -and $_.Start -eq 0 }).Count -eq 1) 'mbr2: MBR sektörü dolu sayılır'
$gaps = [Mm.WipeLayout]::Gaps($m.Length, [Mm.WipeExtent[]]$m.Occ, $MiB, $MiB, 8 * $MiB, 4096)
foreach ($g in $gaps) {
    foreach ($oc in $m.Occ) { Assert-True (-not (Overlaps $g $oc)) ('mbr2: boşluk dolu alanla çakışmaz ' + $g.Start) }
    Assert-True ($g.Length -ge 8 * $MiB -and ($g.Start % 4096) -eq 0 -and ($g.Length % 4096) -eq 0) 'mbr2: boşluk hizalı ve yeterince büyük'
    Assert-True ($g.Start -ge $MiB -and $g.End -le $m.Length - $MiB) 'mbr2: baş ve son korunur'
}

$m = Read-Occupied (Img 'mbr_ext.img')
Assert-Eq $m.Style 'MBR' 'mbr_ext: MBR tanındı'
$extTable = Get-Region (Img 'mbr_ext.img') 0 512
$lastEnd = 0
for ($i = 0; $i -lt 4; $i++) {
    $o = 446 + 16 * $i
    if ($extTable[$o + 4] -ne 0) { $e = ([long][BitConverter]::ToUInt32($extTable, $o + 8) + [long][BitConverter]::ToUInt32($extTable, $o + 12)) * 512; if ($e -gt $lastEnd) { $lastEnd = $e } }
}
Assert-True (@($m.Occ | Where-Object { $_.End -ge $lastEnd }).Count -ge 1) 'mbr_ext: genişletilmiş bölüm kapsayıcısı dolu sayılır (mantıksal bölümler dahil)'
$gaps = [Mm.WipeLayout]::Gaps($m.Length, [Mm.WipeExtent[]]$m.Occ, 0, 0, 4096, 512)
foreach ($g in $gaps) { foreach ($oc in $m.Occ) { Assert-True (-not (Overlaps $g $oc)) 'mbr_ext: boşluk dolu alanla çakışmaz' } }

$m = Read-Occupied (Img 'gpt_valid.img')
Assert-Eq $m.Style 'GPT' 'gpt_valid: GPT tanındı'
# bağımsız ayrıştırma: LBA1 başlığı, bölüm dizisi
$hdr = Get-Region (Img 'gpt_valid.img') 512 92
$entLba = [long][BitConverter]::ToUInt64($hdr, 72)
$cnt = [int][BitConverter]::ToUInt32($hdr, 80)
$esz = [int][BitConverter]::ToUInt32($hdr, 84)
$arr = Get-Region (Img 'gpt_valid.img') ($entLba * 512) ($cnt * $esz)
$want = New-Object System.Collections.ArrayList
for ($i = 0; $i -lt $cnt; $i++) {
    $o = $i * $esz
    $nz = $false
    for ($k = 0; $k -lt 16; $k++) { if ($arr[$o + $k] -ne 0) { $nz = $true } }
    if ($nz) { [void]$want.Add(@{ Start = [long][BitConverter]::ToUInt64($arr, $o + 32) * 512; End = ([long][BitConverter]::ToUInt64($arr, $o + 40) + 1) * 512 }) }
}
$got = @($m.Occ | Where-Object { $_.Tag -eq 'bölüm' })
Assert-Eq $want.Count 3 'gpt_valid: tabloda üç bölüm (bağımsız ayrıştırma)'
Assert-Eq $got.Count 3 'gpt_valid: üç bölüm bulundu'
for ($i = 0; $i -lt $want.Count; $i++) { Assert-True ($got[$i].Start -eq $want[$i].Start -and $got[$i].End -eq $want[$i].End) ('gpt_valid: bölüm ' + $i + ' konumu') }
Assert-True (@($m.Occ | Where-Object { $_.Tag -eq 'GPT başı' -and $_.Start -eq 0 -and $_.Length -eq 34 * 512 }).Count -eq 1) 'gpt_valid: GPT başı (MBR + başlık + dizi) dolu'
Assert-True (@($m.Occ | Where-Object { $_.Tag -eq 'GPT sonu' -and $_.End -eq $m.Length -and $_.Length -eq 33 * 512 }).Count -eq 1) 'gpt_valid: GPT sonu (yedek tablo) dolu'
$gaps = [Mm.WipeLayout]::Gaps($m.Length, [Mm.WipeExtent[]]$m.Occ, $MiB, $MiB, 8 * $MiB, 4096)
Assert-Eq $gaps.Count 2 'gpt_valid: 8 MB üstü iki boşluk (sondaki 5 MB atlanır)'
Assert-True ($gaps[0].Start -eq 9 * $MiB -and $gaps[0].End -eq 20 * $MiB) 'gpt_valid: ilk boşluk 9-20 MB'
Assert-True ($gaps[1].Start -eq 30 * $MiB -and $gaps[1].End -eq 50 * $MiB) 'gpt_valid: ikinci boşluk 30-50 MB'
$gaps = [Mm.WipeLayout]::Gaps($m.Length, [Mm.WipeExtent[]]$m.Occ, $MiB, $MiB, 4096, 4096)
Assert-Eq $gaps.Count 3 'gpt_valid: küçük eşikte üç boşluk'
foreach ($g in $gaps) { foreach ($oc in $m.Occ) { Assert-True (-not (Overlaps $g $oc)) 'gpt_valid: boşluk dolu alanla çakışmaz' } }
# üretecin yalın GPT imajları sağlama toplamı taşımaz: temkinli davranılıp tüm disk dolu sayılır
foreach ($name in @('gpt.img', 'gpt_multi.img')) {
    $mm = Read-Occupied (Img $name)
    Assert-True ($mm.Style -eq 'BILINMIYOR' -and $mm.Note -match 'sağlama' -and $mm.Occ.Count -eq 1 -and $mm.Occ[0].Length -eq $mm.Length) ($name + ': sağlama toplamı geçersiz GPT tüm disk dolu sayılır')
}

$m = Read-Occupied (Img 'blank.img')
Assert-True ($m.Style -eq 'BOS' -and $m.Occ.Count -eq 0) 'boş disk: tablo yok, dolu alan yok'
$m = Read-Occupied (Img 'raw.img')
Assert-True ($m.Style -eq 'BOS' -and $m.Occ.Count -eq 0) 'raw.img: ilk 4 KB sıfırsa tablo yok sayılır'
foreach ($name in @('ntfs.img', 'fat32.img', 'exfat.img', 'ext4.img', 'bitlocker.img', 'luks.img')) {
    $m = Read-Occupied (Img $name)
    Assert-True (($m.Style -eq 'BIRIM' -or $m.Style -eq 'BILINMIYOR') -and $m.Occ.Count -eq 1 -and $m.Occ[0].Start -eq 0 -and $m.Occ[0].Length -eq $m.Length) ($name + ': tablosuz birim tamamen dolu sayılır')
}

# bozuk düzenler "tamamen dolu" sayılır (hiçbir şey ayrılmamış sayılmaz)
function Test-WholeDisk($M) { return ($M.Style -eq 'BILINMIYOR' -and $M.Occ.Count -eq 1 -and $M.Occ[0].Start -eq 0 -and $M.Occ[0].Length -eq $M.Length) }
function Patch-Byte([string]$Path, [long]$Pos) {
    $fsx = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite)
    try {
        [void]$fsx.Seek($Pos, [System.IO.SeekOrigin]::Begin); $b = $fsx.ReadByte()
        [void]$fsx.Seek($Pos, [System.IO.SeekOrigin]::Begin); $fsx.WriteByte([byte](($b + 1) % 256))
    } finally { $fsx.Dispose() }
}
$c1 = Join-Path $tmp 'gpt-bozuk-dizi.img'
Copy-Item -LiteralPath (Img 'gpt_valid.img') -Destination $c1
Patch-Byte $c1 (1024 + 40)
Assert-True (Test-WholeDisk (Read-Occupied $c1)) 'GPT dizisinin sağlama toplamı bozuksa tüm disk dolu'
$c2 = Join-Path $tmp 'gpt-bozuk-baslik.img'
Copy-Item -LiteralPath (Img 'gpt_valid.img') -Destination $c2
Patch-Byte $c2 (512 + 48)
Assert-True (Test-WholeDisk (Read-Occupied $c2)) 'GPT başlığının sağlama toplamı bozuksa tüm disk dolu'
$c3 = Join-Path $tmp 'gpt-baslik-yok.img'
Copy-Item -LiteralPath (Img 'gpt_valid.img') -Destination $c3
$fsx = [System.IO.File]::Open($c3, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite)
[void]$fsx.Seek(512, [System.IO.SeekOrigin]::Begin); $fsx.Write((New-Object byte[] 512), 0, 512); $fsx.Dispose()
Assert-True (Test-WholeDisk (Read-Occupied $c3)) 'koruyucu MBR var ama GPT başlığı yoksa tüm disk dolu'
$c4 = Join-Path $tmp 'mbr-tasan.img'
Copy-Item -LiteralPath (Img 'mbr2.img') -Destination $c4
$fsx = [System.IO.File]::Open($c4, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite)
[void]$fsx.Seek(446 + 12, [System.IO.SeekOrigin]::Begin); $fsx.Write([byte[]]@(255, 255, 255, 127), 0, 4); $fsx.Dispose()
Assert-True (Test-WholeDisk (Read-Occupied $c4)) 'MBR girdisi diskin dışına taşıyorsa tüm disk dolu'
$c5 = Join-Path $tmp 'mbr-durum.img'
Copy-Item -LiteralPath (Img 'mbr2.img') -Destination $c5
$fsx = [System.IO.File]::Open($c5, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite)
[void]$fsx.Seek(446, [System.IO.SeekOrigin]::Begin); $fsx.WriteByte(5); $fsx.Dispose()
Assert-True (Test-WholeDisk (Read-Occupied $c5)) 'geçersiz durum baytı varsa tüm disk dolu'
$c6 = Join-Path $tmp 'mbr-bos-tablo.img'
$mb = New-Object byte[] (4 * $MiB); $mb[100] = 1; $mb[510] = 0x55; $mb[511] = 0xAA
[System.IO.File]::WriteAllBytes($c6, $mb)
Assert-True (Test-WholeDisk (Read-Occupied $c6)) 'bölümsüz MBR imzası: tüm disk dolu'
$c7 = Join-Path $tmp 'kucuk.img'
[System.IO.File]::WriteAllBytes($c7, (New-Object byte[] 100))
Assert-True (Test-WholeDisk (Read-Occupied $c7)) 'okunamayan baş: tüm disk dolu'

# EdgeGuards ve Gaps
$eg = [Mm.WipeLayout]::EdgeGuards(100 * $MiB, $MiB, 512)
Assert-True ($eg.Count -eq 2 -and $eg[0].Start -eq 0 -and $eg[0].Length -eq $MiB -and $eg[1].End -eq 100 * $MiB -and $eg[1].Length -eq $MiB) 'baş ve son korumaları'
$eg = [Mm.WipeLayout]::EdgeGuards(100 * $MiB + 100, $MiB, 512)
Assert-True ($eg[1].End -eq 100 * $MiB) 'son koruma sektöre yuvarlanmış uzunlukta biter'
$eg = [Mm.WipeLayout]::EdgeGuards(1500000, $MiB, 512)
Assert-True ($eg.Count -eq 1 -and $eg[0].Start -eq 0 -and $eg[0].Length -eq 1499648) 'küçük diskte tek bölge'
Assert-Eq ([Mm.WipeLayout]::EdgeGuards(0, $MiB, 512)).Count 0 'boş disk'
$eg = [Mm.WipeLayout]::EdgeGuards(100 * $MiB, 1000, 4096)
Assert-True ($eg[0].Length -eq 4096) 'koruma sektöre yukarı yuvarlanır'

$occ = [Mm.WipeExtent[]]@((New-Ext (10 * $MiB) (10 * $MiB)), (New-Ext (50 * $MiB) (10 * $MiB)))
$g = [Mm.WipeLayout]::Gaps(100 * $MiB, $occ, $MiB, $MiB, 8 * $MiB, 4096)
Assert-Eq $g.Count 3 'üç boşluk'
Assert-True ($g[0].Start -eq $MiB -and $g[0].End -eq 10 * $MiB) 'ilk boşluk: baştan korumadan sonra'
Assert-True ($g[1].Start -eq 20 * $MiB -and $g[1].End -eq 50 * $MiB) 'aradaki boşluk'
Assert-True ($g[2].Start -eq 60 * $MiB -and $g[2].End -eq 99 * $MiB) 'son boşluk: sondan korumadan önce'
$g = [Mm.WipeLayout]::Gaps(100 * $MiB, $occ, $MiB, $MiB, 35 * $MiB, 4096)
Assert-True ($g.Count -eq 1 -and $g[0].Start -eq 60 * $MiB) 'eşikten küçük boşluklar atlanır'
$occ2 = [Mm.WipeExtent[]]@((New-Ext (10 * $MiB + 100) (10 * $MiB)))
$g = [Mm.WipeLayout]::Gaps(40 * $MiB, $occ2, 0, 0, 4096, 4096)
Assert-True ($g[0].End -eq 10 * $MiB -and ($g[1].Start % 4096) -eq 0 -and $g[1].Start -ge 20 * $MiB + 100) 'boşluklar dolu alana değmeyecek biçimde içe doğru hizalanır'
Assert-Eq ([Mm.WipeLayout]::Gaps(10 * $MiB, ([Mm.WipeExtent[]]@()), 6 * $MiB, 6 * $MiB, 0, 1)).Count 0 'korumalar diski kaplarsa boşluk yok'
Assert-Eq ([Mm.WipeLayout]::Gaps(10 * $MiB, ([Mm.WipeExtent[]]@((New-Ext 0 (10 * $MiB)))), 0, 0, 0, 1)).Count 0 'tamamen dolu disk'
$g = [Mm.WipeLayout]::Gaps(10 * $MiB, ([Mm.WipeExtent[]]@()), 0, 0, 0, 1)
Assert-True ($g.Count -eq 1 -and $g[0].Length -eq 10 * $MiB) 'boş disk tek boşluk'
$g = [Mm.WipeLayout]::Gaps(100 * $MiB, ([Mm.WipeExtent[]]@((New-Ext (30 * $MiB) (5 * $MiB)), (New-Ext (32 * $MiB) (5 * $MiB)))), $MiB, $MiB, 4096, 4096)
Assert-True ($g.Count -eq 2 -and $g[1].Start -eq 37 * $MiB) 'üst üste binen dolu alanlar birleşik sayılır'

# =====================================================================
#  9) kendi kendine denetim
# =====================================================================
$sc = Invoke-WipeSelfCheck
Assert-True ($sc.Ok -eq $true -and @($sc.Lines).Count -ge 3) 'kendi kendine denetim geçer'
Assert-True (@($sc.Lines | Where-Object { $_.Ok -ne $true }).Count -eq 0) 'denetim satırlarının hepsi başarılı'
Assert-True (@(Get-ChildItem -LiteralPath ([System.IO.Path]::GetTempPath()) -Filter 'mm-silme-deneme-*' -ErrorAction SilentlyContinue).Count -eq 0) 'geçici deneme imajı silindi'

# kaynak imajlar değişmedi
foreach ($f in @('mbr2.img', 'gpt.img', 'ntfs.img', 'blank.img')) { Assert-True (Test-Path -LiteralPath (Img $f)) ($f + ' duruyor') }

Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
Show-Result
