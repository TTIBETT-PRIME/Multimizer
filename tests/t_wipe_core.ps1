. "$PSScriptRoot/lib.ps1"
# Kalıcı silme çekirdeği (mods\128_wipe_core.ps1): yöntemler, süre tahmini, ilerleme etiketi, elle yazdırılan onay, disk korumaları,
# kimlik denetimi ve dosya silme korumaları. Burada yalnızca karar veren işlevler sınanır; hiçbir şey diske yazılmaz.
Import-Fn 'Format-Size', 'Get-WipeMethodKey', 'Get-WipeModes', 'Get-WipeMethodName', 'Get-WipeMethodList', 'Get-WipeVerifyKey', 'Get-WipeVerifyList', 'Get-WipeVerifyName',
    'Get-WipeAfterKey', 'Get-WipeAfterList', 'Get-WipeAfterName', 'Format-WipeEta', 'Get-WipeRate', 'Get-WipeEstimate', 'Get-WipeProgressLabel',
    'ConvertTo-WipeFold', 'Test-WipeTyped', 'Get-WipeReserve', 'Get-WipeProtectedLetters', 'Get-WipeDiskLive', 'Test-WipeDiskAllowed', 'Test-WipePartAllowed',
    'Test-WipeIdentity', 'Get-WipeExpect', 'Test-SecureDeleteAllowed'

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('mm-wipecore-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
[void][System.IO.Directory]::CreateDirectory($tmp)
$GB = [double]1073741824
$MB = [double]1048576

# =====================================================================
#  1) yöntem, doğrulama ve "sonra" anahtarları
# =====================================================================
Assert-Eq (Get-WipeMethodKey 'zero') 'zero' 'yöntem: zero'
Assert-Eq (Get-WipeMethodKey ' DoD3 ') 'dod3' 'yöntem: büyük harf ve boşluk önemsiz'
Assert-Eq (Get-WipeMethodKey 'random3') 'random3' 'yöntem: random3'
Assert-Eq (Get-WipeMethodKey 'gutmann') 'random' 'yöntem: bilinmeyen değer varsayılana döner'
Assert-Eq (Get-WipeMethodKey '') 'random' 'yöntem: boş değer varsayılana döner'
Assert-Eq (Get-WipeMethodKey $null) 'random' 'yöntem: null varsayılana döner'

Assert-Eq ((Get-WipeModes 'random') -join ',') '0' 'geçiş: rastgele tek geçiş'
Assert-Eq ((Get-WipeModes 'zero') -join ',') '1' 'geçiş: sıfır tek geçiş'
Assert-Eq ((Get-WipeModes 'dod3') -join ',') '1,2,0' 'geçiş: sıfır, bir, rastgele'
Assert-Eq ((Get-WipeModes 'random3') -join ',') '0,0,0' 'geçiş: üç kez rastgele'
Assert-Eq ((Get-WipeModes 'bilinmeyen') -join ',') '0' 'geçiş: bilinmeyen yöntem tek rastgele'
Assert-Eq (Get-WipeModes 'dod3').Count 3 'geçiş sayısı dizi olarak döner'
Assert-Eq (Get-WipeModes 'zero').Count 1 'tek geçişli yöntem de dizi döner'

foreach ($k in @('random', 'zero', 'dod3', 'random3')) { Assert-True ((Get-WipeMethodName $k) -ne '') ('yöntem adı var: ' + $k) }
Assert-True ((Get-WipeMethodName 'dod3') -match '3 geçiş' -and (Get-WipeMethodName 'random3') -match '3 geçiş' -and (Get-WipeMethodName 'zero') -match 'sıfır') 'yöntem adları'
$ml = Get-WipeMethodList
Assert-Eq $ml.Count 4 'yöntem listesi dört öğe'
Assert-Eq (($ml | ForEach-Object { $_.Key }) -join ',') 'random,zero,dod3,random3' 'yöntem anahtarları ve sırası'
Assert-True ($ml[0].Name -match 'önerilir') 'varsayılan yöntem önerilir olarak işaretli'
Assert-Eq @($ml | Where-Object { [string]$_.Name -eq '' }).Count 0 'her yöntemin adı var'
foreach ($m in $ml) { Assert-Eq (Get-WipeMethodKey ([string]$m.Key)) ([string]$m.Key) ('listedeki anahtar geçerli: ' + $m.Key) }

Assert-Eq (Get-WipeVerifyKey 'full') 'full' 'doğrulama: full'
Assert-Eq (Get-WipeVerifyKey 'NONE') 'none' 'doğrulama: büyük harf önemsiz'
Assert-Eq (Get-WipeVerifyKey 'x') 'sample' 'doğrulama: bilinmeyen değer örnekleme'
Assert-Eq (Get-WipeVerifyKey $null) 'sample' 'doğrulama: null örnekleme'
$vl = Get-WipeVerifyList
Assert-Eq (($vl | ForEach-Object { $_.Key }) -join ',') 'sample,full,none' 'doğrulama listesi sırası'
Assert-True ((Get-WipeVerifyName 'full') -match 'tamamı' -and (Get-WipeVerifyName 'none') -match 'yapılmaz' -and (Get-WipeVerifyName 'sample') -match 'örnek') 'doğrulama adları'

Assert-Eq (Get-WipeAfterKey 'ntfs') 'ntfs' 'sonra: ntfs'
Assert-Eq (Get-WipeAfterKey ' ExFAT') 'exfat' 'sonra: exfat'
Assert-Eq (Get-WipeAfterKey 'fat32') 'fat32' 'sonra: fat32'
Assert-Eq (Get-WipeAfterKey 'ext4') 'none' 'sonra: bilinmeyen değer boş bırakır'
Assert-Eq (Get-WipeAfterKey '') 'none' 'sonra: boş değer boş bırakır'
$al = Get-WipeAfterList
Assert-Eq (($al | ForEach-Object { $_.Key }) -join ',') 'none,ntfs,exfat,fat32' 'sonra listesi sırası'
Assert-True ((Get-WipeAfterName 'ntfs') -match 'NTFS' -and (Get-WipeAfterName 'exfat') -match 'exFAT' -and (Get-WipeAfterName 'fat32') -match 'FAT32' -and (Get-WipeAfterName 'none') -match 'boş') 'sonra adları'
Assert-True (($al | Where-Object { $_.Key -eq 'fat32' }).Name -match '32 GB') 'FAT32 sınırı listede yazılı'

# =====================================================================
#  2) süre ve ilerleme
# =====================================================================
Assert-Eq (Format-WipeEta -1) 'bilinmiyor' 'süre: negatif bilinmiyor'
Assert-Eq (Format-WipeEta ([double]::NaN)) 'bilinmiyor' 'süre: NaN bilinmiyor'
Assert-Eq (Format-WipeEta ([double]::PositiveInfinity)) 'bilinmiyor' 'süre: sonsuz bilinmiyor'
Assert-Eq (Format-WipeEta 10) 'bir dakikadan az' 'süre: 10 sn'
Assert-Eq (Format-WipeEta 44) 'bir dakikadan az' 'süre: 44 sn'
Assert-Eq (Format-WipeEta 45) '1 dk' 'süre: 45 sn bir dakika'
Assert-Eq (Format-WipeEta 600) '10 dk' 'süre: 10 dk'
Assert-Eq (Format-WipeEta 3600) '1 sa' 'süre: tam saat'
Assert-Eq (Format-WipeEta 5400) '1 sa 30 dk' 'süre: saat ve dakika'
Assert-Eq (Format-WipeEta 7380) '2 sa 3 dk' 'süre: 2 sa 3 dk'
Assert-Eq (Format-WipeEta (50 * 3600)) '2 gün' 'süre: 50 saat gün olarak'
Assert-Eq (Format-WipeEta (100 * 3600)) '4 gün' 'süre: 100 saat'

Assert-Eq (Get-WipeRate 'USB' 'SSD') ([double](25 * $MB)) 'hız: USB en yavaş'
Assert-Eq (Get-WipeRate 'SATA' 'HDD') ([double](110 * $MB)) 'hız: HDD'
Assert-Eq (Get-WipeRate 'NVMe' 'SSD') ([double](450 * $MB)) 'hız: NVMe'
Assert-Eq (Get-WipeRate 'SATA' 'SSD') ([double](350 * $MB)) 'hız: SATA SSD'
Assert-Eq (Get-WipeRate 'SD' '') ([double](20 * $MB)) 'hız: SD kart'
Assert-Eq (Get-WipeRate 'MMC' '') ([double](20 * $MB)) 'hız: MMC'
Assert-Eq (Get-WipeRate '' '') ([double](80 * $MB)) 'hız: bilinmeyen ortam'

$e1 = Get-WipeEstimate ([double](110 * $MB)) 1 'none' 'SATA' 'HDD'
Assert-Eq $e1.Lo 1 'tahmin: 110 MB HDD bir saniye'
Assert-True ([math]::Abs($e1.Hi - 2.2) -lt 0.0001) 'tahmin: üst sınır 2,2 katı'
Assert-Eq $e1.Text 'yaklaşık bir dakikadan az' 'tahmin metni: kısa iş'
$e2 = Get-WipeEstimate ([double](110 * $GB)) 3 'full' 'SATA' 'HDD'
$work2 = [double](110 * $GB) * 4
Assert-True ([math]::Abs($e2.Lo - $work2 / [double](110 * $MB)) -lt 0.001) 'tahmin: üç geçiş ve tam doğrulama dört kat iş'
Assert-True ($e2.Text -match '^yaklaşık .+ . .+$') 'tahmin metni: uzun işte aralık yazılır'
$e3 = Get-WipeEstimate ([double](1 * $GB)) 1 'sample' 'NVMe' 'SSD'
Assert-True ([math]::Abs($e3.Lo - (([double](1 * $GB) + [double](256 * $MB)) / [double](450 * $MB))) -lt 0.001) 'tahmin: örnek doğrulama en çok 256 MB ekler'
$e4 = Get-WipeEstimate ([double](100 * $MB)) 1 'sample' 'NVMe' 'SSD'
Assert-True ([math]::Abs($e4.Lo - ([double](200 * $MB) / [double](450 * $MB))) -lt 0.001) 'tahmin: örnek doğrulama boyutu aşmaz'
$e5 = Get-WipeEstimate ([double](110 * $MB)) 0 'none' 'SATA' 'HDD'
Assert-Eq $e5.Lo 1 'tahmin: sıfır geçiş bir sayılır'
$e6 = Get-WipeEstimate ([double](110 * $MB)) 1 'bilinmeyen' 'SATA' 'HDD'
Assert-True ($e6.Lo -gt 1) 'tahmin: bilinmeyen doğrulama örnekleme sayılır'

$l1 = Get-WipeProgressLabel 'Disk 2 siliniyor' 'Yazılıyor' 50 100 10
Assert-Eq $l1 'Disk 2 siliniyor · Yazılıyor · %50 · 5 B/sn · kalan bir dakikadan az' 'ilerleme etiketi: tam'
$l2 = Get-WipeProgressLabel 'Disk 2 siliniyor' '' 50 100 1
Assert-Eq $l2 'Disk 2 siliniyor · %50' 'ilerleme etiketi: 3 saniyeden önce hız yok'
$l3 = Get-WipeProgressLabel 'Boş alan' '' 0 0 100
Assert-Eq $l3 'Boş alan' 'ilerleme etiketi: toplam bilinmiyorsa yalnızca ad'
$l4 = Get-WipeProgressLabel 'X' '' 150 100 20
Assert-True ($l4 -match '%100' -and $l4 -notmatch 'kalan') 'ilerleme etiketi: yüzde 100 aşılmaz, bitince kalan süre yok'
$l5 = Get-WipeProgressLabel 'X' '' 0 100 20
Assert-True ($l5 -match '%0' -and $l5 -notmatch '/sn') 'ilerleme etiketi: hiç yazılmadıysa hız yok'

# =====================================================================
#  3) elle yazdırılan onay
# =====================================================================
Assert-Eq (ConvertTo-WipeFold 'Disk 2 Bölüm 1') 'disk 2 bolum 1' 'sadeleştirme: Türkçe harfler ve küçük harf'
Assert-Eq (ConvertTo-WipeFold ('ÇĞİÖŞÜ' + ' ' + 'çğıöşü')) 'cgiosu cgiosu' 'sadeleştirme: büyük ve küçük Türkçe harfler'
Assert-Eq (ConvertTo-WipeFold '  Disk    7  ') 'disk 7' 'sadeleştirme: fazla boşluklar'
Assert-Eq (ConvertTo-WipeFold "Disk`t3`r`n") 'disk 3' 'sadeleştirme: sekme ve satır sonu'
Assert-Eq (ConvertTo-WipeFold '') '' 'sadeleştirme: boş metin'
Assert-Eq (ConvertTo-WipeFold $null) '' 'sadeleştirme: null'

Assert-True (Test-WipeTyped 'Disk 2' 'Disk 2') 'onay: aynı metin'
Assert-True (Test-WipeTyped 'disk 2' 'Disk 2') 'onay: küçük harf'
Assert-True (Test-WipeTyped '  DISK   2 ' 'Disk 2') 'onay: büyük harf ve boşluk'
Assert-True (Test-WipeTyped 'disk 2 bolum 1' 'Disk 2 Bölüm 1') 'onay: Türkçe harfsiz yazım'
Assert-True (Test-WipeTyped 'DİSK 2 BÖLÜM 1' 'Disk 2 Bölüm 1') 'onay: Türkçe büyük harfler'
Assert-True (-not (Test-WipeTyped 'disk 3' 'Disk 2')) 'onay: farklı numara kabul edilmez'
Assert-True (-not (Test-WipeTyped 'disk 2 bolum 2' 'Disk 2 Bölüm 1')) 'onay: farklı bölüm kabul edilmez'
Assert-True (-not (Test-WipeTyped 'disk' 'Disk 2')) 'onay: eksik metin kabul edilmez'
Assert-True (-not (Test-WipeTyped 'disk 2 ' 'Disk 22')) 'onay: önek kabul edilmez'
Assert-True (-not (Test-WipeTyped '' 'Disk 2')) 'onay: boş metin kabul edilmez'
Assert-True (-not (Test-WipeTyped 'x' '')) 'onay: beklenen metin boşsa hiçbir şey kabul edilmez'
Assert-True (-not (Test-WipeTyped '' '')) 'onay: ikisi de boşsa kabul edilmez'

# =====================================================================
#  4) bırakılan pay
# =====================================================================
Assert-Eq (Get-WipeReserve ([double](100 * $GB)) $false) 1073741824 'pay: 100 GB için %1'
Assert-Eq (Get-WipeReserve ([double](10 * $GB)) $false) 536870912 'pay: küçük sürücüde en az 512 MB'
Assert-Eq (Get-WipeReserve ([double](50 * $GB)) $true) 2147483648 'pay: Windows sürücüsünde en az 2 GB'
Assert-Eq (Get-WipeReserve ([double](1024 * $GB)) $true) ([math]::Floor(1024 * $GB * 0.03)) 'pay: Windows sürücüsünde %3'
Assert-Eq (Get-WipeReserve ([double](1024 * $GB)) $false) ([math]::Floor(1024 * $GB * 0.01)) 'pay: %1'
Assert-Eq (Get-WipeReserve ([double]0) $false) 536870912 'pay: toplam bilinmiyorsa en az 512 MB'

# =====================================================================
#  5) disk korumaları
# =====================================================================
function New-Live([hashtable]$Over = @{}) {
    $m = @{ Number = 2; Name = 'Örnek Disk'; Size = [double](500 * $GB); UniqueId = 'ABC123'; Serial = 'SN-1'; Bus = 'SATA'; Media = 'HDD'; Style = 'GPT'
        IsSystem = $false; IsBoot = $false; Offline = $false; ReadOnly = $false; Clustered = $false; Pool = $false; Sector = 512
        Letters = @(); Roles = @(); Parts = @() }
    foreach ($k in $Over.Keys) { $m[$k] = $Over[$k] }
    return $m
}
Assert-Eq (Test-WipeDiskAllowed (New-Live) 'Disk') '' 'uygun disk'
Assert-Eq (Test-WipeDiskAllowed (New-Live) 'Partition') '' 'uygun disk: bölüm kapsamı'
Assert-Eq (Test-WipeDiskAllowed (New-Live) 'Unallocated') '' 'uygun disk: ayrılmamış alan kapsamı'
Assert-True ((Test-WipeDiskAllowed $null 'Disk') -match 'bulunamadı') 'disk yok'
Assert-True ((Test-WipeDiskAllowed (New-Live @{ IsSystem = $true }) 'Disk') -match 'Windows bu diskte çalışıyor') 'sistem diski reddedilir'
Assert-True ((Test-WipeDiskAllowed (New-Live @{ IsBoot = $true }) 'Unallocated') -match 'Windows bu diskte çalışıyor') 'önyükleme diski reddedilir (ayrılmamış alan da)'
Assert-True ((Test-WipeDiskAllowed (New-Live @{ IsSystem = $true }) 'Partition') -match 'doğrudan yazılmaz') 'sistem diskinde bölüm de reddedilir'
Assert-True ((Test-WipeDiskAllowed (New-Live @{ Roles = @('D: sürücüsü: Multimizer bu sürücüde çalışıyor') }) 'Disk') -match 'D: sürücüsü: Multimizer') 'Multimizer diski reddedilir'
Assert-True ((Test-WipeDiskAllowed (New-Live @{ Roles = @('E: sürücüsü: geçici dosyalar bu sürücüde duruyor', 'F: sürücüsü: sayfa dosyası bu sürücüde') }) 'Disk') -match 'geçici dosyalar') 'ilk rol nedeni söylenir'
Assert-True ((Test-WipeDiskAllowed (New-Live @{ Offline = $true }) 'Disk') -match 'çevrimdışı') 'çevrimdışı disk'
Assert-True ((Test-WipeDiskAllowed (New-Live @{ ReadOnly = $true }) 'Disk') -match 'salt okunur') 'salt okunur disk'
Assert-True ((Test-WipeDiskAllowed (New-Live @{ Pool = $true }) 'Disk') -match 'havuz') 'depolama havuzu üyesi'
Assert-True ((Test-WipeDiskAllowed (New-Live @{ Clustered = $true }) 'Disk') -match 'küme') 'kümelenmiş disk'
Assert-True ((Test-WipeDiskAllowed (New-Live @{ Bus = 'Spaces' }) 'Disk') -match 'Depolama Alanları') 'depolama alanları sanal diski'
Assert-True ((Test-WipeDiskAllowed (New-Live @{ Size = [double]0 }) 'Disk') -match 'boyutu okunamadı') 'boyutu bilinmeyen disk'
Assert-True ((Test-WipeDiskAllowed (New-Live) 'Hepsi') -match 'Bilinmeyen silme kapsamı') 'bilinmeyen kapsam'
Assert-Eq (Test-WipeDiskAllowed (New-Live @{ Bus = 'USB'; Media = 'Unspecified' }) 'Disk') '' 'USB bellek serbest'

$okPart = @{ Number = 2; Offset = [double](20 * $MB); Size = [double](10 * $MB); Letter = 'F:'; Type = 'Basic'; IsSystem = $false; IsBoot = $false; IsActive = $false; Fs = 'NTFS'; Label = 'Veri' }
Assert-Eq (Test-WipePartAllowed (New-Live) $okPart) '' 'uygun bölüm'
Assert-True ((Test-WipePartAllowed (New-Live) $null) -match 'bulunamadı') 'bölüm yok'
$sysPart = @{ Number = 1; Offset = [double]$MB; Size = [double](100 * $MB); Letter = ''; Type = 'System'; IsSystem = $true; IsBoot = $false }
$bootPart = @{ Number = 3; Offset = [double](200 * $MB); Size = [double](100 * $GB); Letter = 'C:'; Type = 'Basic'; IsSystem = $false; IsBoot = $true }
Assert-True ((Test-WipePartAllowed (New-Live) $sysPart) -match 'Windows.a ait') 'sistem bölümü reddedilir'
Assert-True ((Test-WipePartAllowed (New-Live) $bootPart) -match 'Windows.a ait') 'önyükleme bölümü reddedilir'
Assert-True ((Test-WipePartAllowed (New-Live) @{ Number = 4; Size = [double]0; IsSystem = $false; IsBoot = $false }) -match 'boyutu okunamadı') 'boyutsuz bölüm'

# =====================================================================
#  6) kimlik denetimi
# =====================================================================
$live = New-Live
$exp = Get-WipeExpect $live
Assert-Eq $exp.Size ([double](500 * $GB)) 'kimlik: boyut'
Assert-Eq $exp.Name 'Örnek Disk' 'kimlik: ad'
Assert-Eq $exp.UniqueId 'ABC123' 'kimlik: benzersiz kimlik'
Assert-Eq $exp.Serial 'SN-1' 'kimlik: seri numarası'
$padded = Get-WipeExpect (New-Live @{ Name = '  Disk  '; UniqueId = ' U1 '; Serial = ' S1 ' })
Assert-True ($padded.Name -eq 'Disk' -and $padded.UniqueId -eq 'U1' -and $padded.Serial -eq 'S1') 'kimlik: boşluklar kırpılır'
Assert-Eq (Test-WipeIdentity $live $exp) '' 'kimlik: aynı disk'
Assert-True ((Test-WipeIdentity $null $exp) -match 'bulunamadı') 'kimlik: disk çıkarılmış'
Assert-True ((Test-WipeIdentity $live $null) -match 'doğrulanamadı') 'kimlik: onay bilgisi yok'
Assert-True ((Test-WipeIdentity (New-Live @{ Size = [double](250 * $GB) }) $exp) -match 'değişmiş') 'kimlik: boyut farklı'
Assert-True ((Test-WipeIdentity (New-Live @{ Name = 'Başka Disk' }) $exp) -match 'değişmiş') 'kimlik: ad farklı'
Assert-True ((Test-WipeIdentity (New-Live @{ UniqueId = 'ZZZ' }) $exp) -match 'değişmiş') 'kimlik: kimlik farklı'
Assert-True ((Test-WipeIdentity (New-Live @{ Serial = 'SN-2' }) $exp) -match 'değişmiş') 'kimlik: seri numarası farklı'
Assert-Eq (Test-WipeIdentity (New-Live @{ Name = 'örnek disk'; UniqueId = 'abc123'; Serial = 'sn-1' }) @{ Size = [double](500 * $GB); Name = 'Örnek Disk'; UniqueId = 'ABC123'; Serial = 'SN-1' }) '' 'kimlik: büyük/küçük harf önemsiz'
Assert-Eq (Test-WipeIdentity (New-Live @{ Name = ''; UniqueId = ''; Serial = '' }) $exp) '' 'kimlik: disk bilgi vermiyorsa o alan karşılaştırılmaz'
Assert-Eq (Test-WipeIdentity $live @{ Size = [double]0; Name = ''; UniqueId = ''; Serial = '' }) '' 'kimlik: onayda boş alanlar karşılaştırılmaz'
Assert-Eq (Test-WipeIdentity $live @{ Size = [double](500 * $GB) }) '' 'kimlik: yalnızca boyut verilmişse'

# =====================================================================
#  7) canlı disk modeli (sahte depolama komutlarıyla)
# =====================================================================
$script:FakeDisk = $null
$script:FakeParts = @()
$script:FakePhys = @()
$script:FakeVols = @()
$script:FakePage = @()
$script:FakeApp = ''
function Get-Disk { [CmdletBinding()] param([int]$Number) if ($null -eq $script:FakeDisk -or $script:FakeDisk.Number -ne $Number) { throw 'disk yok' }; return $script:FakeDisk }
function Get-PhysicalDisk { [CmdletBinding()] param() return $script:FakePhys }
function Get-Volume { [CmdletBinding()] param() return $script:FakeVols }
function Get-Partition { [CmdletBinding()] param([int]$DiskNumber) return $script:FakeParts }
function Get-CimInstance { [CmdletBinding()] param([string]$ClassName) return $script:FakePage }
function Get-AppFolder { return $script:FakeApp }

$saveSd = $env:SystemDrive; $saveUp = $env:USERPROFILE
$env:SystemDrive = 'C:'
$env:USERPROFILE = 'C:\Users\ali'
$script:FakeApp = 'C:\Araclar\Multimizer'
$script:FakeDisk = [pscustomobject]@{ Number = 2; FriendlyName = ' Test USB '; Size = 32GB; UniqueId = ' UID-9 '; SerialNumber = ' S9 '; BusType = 'USB'; PartitionStyle = 'MBR'
    IsSystem = $false; IsBoot = $false; IsOffline = $false; IsReadOnly = $false; IsClustered = $false; LogicalSectorSize = 4096 }
$script:FakePhys = @([pscustomobject]@{ DeviceId = '1'; MediaType = 'SSD'; CannotPoolReason = @() }, [pscustomobject]@{ DeviceId = '2'; MediaType = 'Unspecified'; CannotPoolReason = @('Removable Media') })
$script:FakeVols = @([pscustomobject]@{ DriveLetter = 'f'; FileSystem = 'exFAT'; FileSystemLabel = 'BELLEK' })
$script:FakeParts = @(
    [pscustomobject]@{ PartitionNumber = 1; Offset = 1048576; Size = 20GB; DriveLetter = 'f'; Type = 'IFS'; IsSystem = $false; IsBoot = $false; IsActive = $true },
    [pscustomobject]@{ PartitionNumber = 2; Offset = 21474836480; Size = 8GB; DriveLetter = $null; Type = 'Basic'; IsSystem = $false; IsBoot = $false; IsActive = $false })
$lv = Get-WipeDiskLive 2
Assert-True ($null -ne $lv) 'canlı disk: okundu'
Assert-True ($lv.Number -eq 2 -and $lv.Name -eq 'Test USB' -and $lv.UniqueId -eq 'UID-9' -and $lv.Serial -eq 'S9') 'canlı disk: kimlik alanları kırpılır'
Assert-True ($lv.Bus -eq 'USB' -and $lv.Style -eq 'MBR' -and $lv.Media -eq 'Unspecified' -and $lv.Sector -eq 4096) 'canlı disk: veri yolu, tür, ortam, sektör'
Assert-Eq $lv.Size ([double](32 * $GB)) 'canlı disk: boyut'
Assert-True ($lv.Pool -eq $false -and $lv.Offline -eq $false -and $lv.ReadOnly -eq $false) 'canlı disk: durum alanları'
Assert-Eq @($lv.Parts).Count 2 'canlı disk: iki bölüm'
Assert-True ($lv.Parts[0].Letter -eq 'F:' -and $lv.Parts[0].Fs -eq 'exFAT' -and $lv.Parts[0].Label -eq 'BELLEK' -and $lv.Parts[0].IsActive -eq $true) 'canlı disk: bölüm harfi, dosya sistemi ve etiketi'
Assert-True ($lv.Parts[1].Letter -eq '' -and $lv.Parts[1].Fs -eq '' -and $lv.Parts[1].Number -eq 2) 'canlı disk: harfsiz bölüm'
Assert-Eq (@($lv.Letters) -join ',') 'F:' 'canlı disk: sürücü harfleri'
Assert-Eq @($lv.Roles).Count 0 'canlı disk: korunan rol yok'
Assert-Eq (Test-WipeDiskAllowed $lv 'Disk') '' 'canlı disk: silinebilir'
$script:FakeDisk = $null
Assert-Eq $null (Get-WipeDiskLive 2) 'canlı disk: disk yoksa null'
$script:FakeDisk = [pscustomobject]@{ Number = 2; FriendlyName = 'Disk'; Size = 8GB; UniqueId = ''; SerialNumber = ''; BusType = 'SATA'; PartitionStyle = 'GPT'
    IsSystem = $false; IsBoot = $false; IsOffline = $true; IsReadOnly = $true; IsClustered = $true; LogicalSectorSize = 0 }
$script:FakePhys = @([pscustomobject]@{ DeviceId = '2'; MediaType = 'HDD'; CannotPoolReason = @('In a Pool') })
$lv2 = Get-WipeDiskLive 2
Assert-True ($lv2.Offline -eq $true -and $lv2.ReadOnly -eq $true -and $lv2.Clustered -eq $true -and $lv2.Pool -eq $true -and $lv2.Media -eq 'HDD') 'canlı disk: çevrimdışı, salt okunur, kümeli ve havuz üyesi'
Assert-Eq $lv2.Sector 512 'canlı disk: sektör boyutu okunamazsa 512'
# korunan sürücü rolleri
$script:FakeDisk = [pscustomobject]@{ Number = 3; FriendlyName = 'Veri'; Size = 1TB; UniqueId = 'U3'; SerialNumber = 'S3'; BusType = 'SATA'; PartitionStyle = 'GPT'
    IsSystem = $false; IsBoot = $false; IsOffline = $false; IsReadOnly = $false; IsClustered = $false; LogicalSectorSize = 512 }
$script:FakePhys = @()
$script:FakeVols = @()
$script:FakeParts = @(
    [pscustomobject]@{ PartitionNumber = 1; Offset = 1048576; Size = 100GB; DriveLetter = 'C'; Type = 'Basic'; IsSystem = $false; IsBoot = $false; IsActive = $false },
    [pscustomobject]@{ PartitionNumber = 2; Offset = 200GB; Size = 100GB; DriveLetter = 'D'; Type = 'Basic'; IsSystem = $false; IsBoot = $false; IsActive = $false },
    [pscustomobject]@{ PartitionNumber = 3; Offset = 400GB; Size = 100GB; DriveLetter = 'E'; Type = 'Basic'; IsSystem = $false; IsBoot = $false; IsActive = $false })
$script:FakePage = @([pscustomobject]@{ Name = 'D:\pagefile.sys' })
$script:FakeApp = 'E:\Multimizer'
$lv3 = Get-WipeDiskLive 3
Assert-Eq @($lv3.Roles).Count 3 'canlı disk: üç korunan sürücü'
Assert-True ((@($lv3.Roles) -join '|') -match 'C: sürücüsü: Windows bu sürücüde çalışıyor') 'rol: Windows sürücüsü'
Assert-True ((@($lv3.Roles) -join '|') -match 'D: sürücüsü: sayfa dosyası bu sürücüde') 'rol: sayfa dosyası'
Assert-True ((@($lv3.Roles) -join '|') -match 'E: sürücüsü: Multimizer bu sürücüde çalışıyor') 'rol: Multimizer'
Assert-True ((Test-WipeDiskAllowed $lv3 'Disk') -match 'doğrudan yazılmaz') 'korunan sürücüsü olan disk reddedilir'
Assert-True ((Test-WipeDiskAllowed $lv3 'Unallocated') -match 'doğrudan yazılmaz') 'korunan sürücüsü olan diskte ayrılmamış alan da reddedilir'
# kullanıcı profili sürücüsü
$env:USERPROFILE = 'H:\Users\ali'
$script:FakeApp = ''
$script:FakePage = @()
$pl = Get-WipeProtectedLetters
Assert-Eq $pl['C:'] 'Windows bu sürücüde çalışıyor' 'korunan harf: Windows'
Assert-Eq $pl['H:'] 'kullanıcı profili bu sürücüde' 'korunan harf: kullanıcı profili'
Assert-True (-not $pl.ContainsKey('E:')) 'korunan harf: Multimizer yolu yoksa eklenmez'
$env:SystemDrive = $saveSd; $env:USERPROFILE = $saveUp
Remove-Item function:Get-Disk, function:Get-PhysicalDisk, function:Get-Volume, function:Get-Partition, function:Get-CimInstance

# =====================================================================
#  8) dosya ve klasör silme korumaları
# =====================================================================
$base = Join-Path $tmp 'sd'
$saved = @{}
foreach ($n in @('WINDIR', 'ProgramFiles', 'ProgramFiles(x86)', 'ProgramData', 'USERPROFILE', 'PUBLIC', 'SystemDrive', 'APPDATA', 'LOCALAPPDATA', 'OneDrive', 'OneDriveConsumer', 'OneDriveCommercial')) {
    $saved[$n] = [Environment]::GetEnvironmentVariable($n)
}
$env:WINDIR = $base + '/Windows'
$env:ProgramFiles = $base + '/Program Files'
[Environment]::SetEnvironmentVariable('ProgramFiles(x86)', $base + '/Program Files (x86)')
$env:ProgramData = $base + '/ProgramData'
$env:USERPROFILE = $base + '/Users/ali'
$env:PUBLIC = $base + '/Users/Public'
$env:SystemDrive = $base
$env:APPDATA = $base + '/Users/ali/AppData/Roaming'
$env:LOCALAPPDATA = $base + '/Users/ali/AppData/Local'
$env:OneDrive = $base + '/Users/ali/OneDrive'
$env:OneDriveConsumer = ''
$env:OneDriveCommercial = ''
$script:FakeApp = $base + '/Araclar/Multimizer'
function Get-AppFolder { return $script:FakeApp }

Assert-True ((Test-SecureDeleteAllowed '/') -eq 'Sürücü kökü silinemez.') 'kök dizin silinemez'
Assert-True ((Test-SecureDeleteAllowed $base) -match 'Sistem klasörü silinemez') 'sistem sürücüsünün kökü silinemez'
Assert-True ((Test-SecureDeleteAllowed ($base + '/')) -match 'Sistem klasörü silinemez') 'sonda ayraç olsa da sistem sürücüsü silinemez'
Assert-True ((Test-SecureDeleteAllowed $env:WINDIR) -match 'Sistem klasörü silinemez') 'Windows klasörü silinemez'
Assert-True ((Test-SecureDeleteAllowed ($env:WINDIR + '/')) -match 'Sistem klasörü silinemez') 'sonunda ayraçlı Windows klasörü silinemez'
Assert-True ((Test-SecureDeleteAllowed ($base + '/WINDOWS')) -match 'Sistem klasörü silinemez') 'büyük/küçük harf farkı korumayı aşmaz'
Assert-True ((Test-SecureDeleteAllowed ($env:WINDIR + '/System32')) -match 'Windows ve program klasörlerinin içi silinemez') 'Windows alt klasörü silinemez'
Assert-True ((Test-SecureDeleteAllowed ($env:WINDIR + '/System32/drivers/etc/hosts')) -match 'içi silinemez') 'Windows içindeki dosya silinemez'
Assert-True ((Test-SecureDeleteAllowed ($env:ProgramFiles + '/Uygulama/a.dll')) -match 'içi silinemez') 'Program Files içi silinemez'
Assert-True ((Test-SecureDeleteAllowed $env:ProgramFiles) -match 'Sistem klasörü silinemez') 'Program Files silinemez'
Assert-True ((Test-SecureDeleteAllowed ($base + '/Program Files (x86)/X')) -match 'içi silinemez') 'Program Files (x86) içi silinemez'
Assert-True ((Test-SecureDeleteAllowed $env:ProgramData) -match 'Sistem klasörü silinemez') 'ProgramData silinemez'
Assert-Eq (Test-SecureDeleteAllowed ($env:ProgramData + '/Firma/eski')) '' 'ProgramData altındaki klasör silinebilir'
Assert-True ((Test-SecureDeleteAllowed ($base + '/Users')) -match 'Sistem klasörü silinemez') 'Users klasörü silinemez'
Assert-True ((Test-SecureDeleteAllowed $env:PUBLIC) -match 'Sistem klasörü silinemez') 'Public klasörü silinemez'
Assert-True ((Test-SecureDeleteAllowed $env:USERPROFILE) -match 'Sistem klasörü silinemez') 'kullanıcı profili silinemez'
foreach ($n in @('AppData', 'Downloads', 'Desktop', 'Documents', 'Pictures', 'Music', 'Videos')) {
    Assert-True ((Test-SecureDeleteAllowed ($env:USERPROFILE + '/' + $n)) -match 'Kullanıcı klasörlerinin kendisi silinemez') ('kişisel klasörün kendisi silinemez: ' + $n)
}
Assert-True ((Test-SecureDeleteAllowed $env:APPDATA) -match 'Kullanıcı klasörlerinin kendisi silinemez') 'Roaming klasörünün kendisi silinemez'
Assert-True ((Test-SecureDeleteAllowed $env:LOCALAPPDATA) -match 'Kullanıcı klasörlerinin kendisi silinemez') 'Local klasörünün kendisi silinemez'
Assert-True ((Test-SecureDeleteAllowed $env:OneDrive) -match 'Kullanıcı klasörlerinin kendisi silinemez') 'OneDrive klasörünün kendisi silinemez'
Assert-Eq (Test-SecureDeleteAllowed ($env:USERPROFILE + '/Downloads/eski.zip')) '' 'İndirilenler içindeki dosya silinebilir'
Assert-Eq (Test-SecureDeleteAllowed ($env:USERPROFILE + '/Documents/Eski Proje')) '' 'Belgeler içindeki klasör silinebilir'
Assert-Eq (Test-SecureDeleteAllowed ($env:APPDATA + '/Program/onbellek')) '' 'AppData içindeki klasör silinebilir'
Assert-Eq (Test-SecureDeleteAllowed ($env:OneDrive + '/Eski')) '' 'OneDrive içindeki klasör silinebilir'
Assert-Eq (Test-SecureDeleteAllowed ($base + '/Veri/Eski Fotoğraflar')) '' 'sistem dışı klasör silinebilir'
Assert-True ((Test-SecureDeleteAllowed $script:FakeApp) -match 'Multimizer.ın çalıştığı klasör silinemez') 'Multimizer klasörü silinemez'
Assert-True ((Test-SecureDeleteAllowed ($script:FakeApp + '/Eklenti/X.ps1')) -match 'Multimizer.ın çalıştığı klasör silinemez') 'Multimizer klasörünün içi silinemez'
Assert-True ((Test-SecureDeleteAllowed ($base + '/Araclar')) -match 'Multimizer.ın çalıştığı klasörü içeriyor') 'Multimizer klasörünü içeren klasör silinemez'
Assert-Eq (Test-SecureDeleteAllowed ($base + '/Araclar/Baska')) '' 'Multimizer yanındaki klasör silinebilir'
Assert-Eq (Test-SecureDeleteAllowed ($base + '/AraclarX')) '' 'ad öneki aynı olan klasör korunmaz'
Assert-True ((Test-SecureDeleteAllowed ("kotu`0yol")) -eq 'Geçersiz yol.') 'geçersiz karakterli yol reddedilir'
# reddedilen her yol "silinemez" sözcüğünü taşır (geri yükleme hedefi denetimi bu sözcüğe bakar)
foreach ($p in @('/', $base, $env:WINDIR, ($env:WINDIR + '/x'), $env:ProgramData, $env:USERPROFILE, ($env:USERPROFILE + '/Desktop'), $script:FakeApp, ($script:FakeApp + '/x'), ($base + '/Araclar'))) {
    Assert-True ((Test-SecureDeleteAllowed $p) -match 'silinemez') ('ret iletisi "silinemez" içerir: ' + $p)
}
# uygulama klasörü bilinmiyorsa yalnızca diğer korumalar çalışır
$script:FakeApp = ''
Assert-Eq (Test-SecureDeleteAllowed ($base + '/Araclar/Multimizer')) '' 'uygulama klasörü bilinmiyorsa o koruma uygulanmaz'
Assert-True ((Test-SecureDeleteAllowed $env:WINDIR) -match 'Sistem klasörü') 'uygulama klasörü bilinmese de Windows korunur'

foreach ($n in $saved.Keys) { [Environment]::SetEnvironmentVariable($n, $saved[$n]) }
Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
Show-Result
