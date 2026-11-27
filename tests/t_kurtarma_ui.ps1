. "$PSScriptRoot/lib.ps1"
# Çözüm Merkezi "Silinen dosyalar" sekmesi: saf yardımcılar (tür grupları, satır metinleri, süzme/sıralama, sürücü seçici, hedef denetimi)
# ve sahte denetimlerle çizim/işlem akışı.
Import-Fn 'Format-Size', 'New-Choice', 'Set-ComboChoices', 'Select-ComboKey', 'Get-ComboKey',
    'Get-RcExtTable', 'Get-RcGroup', 'Get-RcGroupCounts', 'Format-RcChance', 'Get-RcChanceBr', 'ConvertFrom-RcTime', 'Format-RcDate', 'Remove-RcControl',
    'New-RcRowModel', 'Get-RcDisplay', 'Get-RcVolumeName', 'Get-RcVolumeChoices', 'Resolve-RcKey', 'Test-RcDestUi', 'Get-RcSummaryLines', 'Get-RcConfirmText', 'Get-RcFootText',
    'Get-RcDiskName', 'Get-RcFsText', 'Get-RcPartText', 'Get-RcPartLetter', 'New-RcChoice', 'Add-RcSourceChoices', 'Get-RcSelectedLetters', 'Start-RcParts', 'Complete-RcParts',
    'Get-RcSelectedChoice', 'Set-RcSourceFromKey', 'Reset-RcResults', 'Update-RcVolumeCombo', 'Update-RcTypeCombo', 'Select-RcVolume', 'Select-RcGroup', 'Select-RcImage', 'Select-RcDest',
    'Invoke-RcAction', 'Update-RcFoot', 'Add-RcIntro', 'Add-RcResultRow', 'Render-RcBody', 'Render-SlRecover', 'Start-RcScan', 'Complete-RcScan', 'Start-RcRecover', 'Start-RcRecoverJob', 'Complete-RcRecover'
Import-Var 'RcExtGroup', 'RcGroupNames', 'RcRowCap', 'RcMaxResults'
# durum değişkenlerinin başlangıç değerleri (üretim kodundaki üst düzey atamalarla aynı)
$script:RcSelKey = ''; $script:RcSource = ''; $script:RcSourceKind = ''; $script:RcPart = 0; $script:RcImage = ''; $script:RcImageParts = 1
$script:RcDisk = -1; $script:RcPartCache = @{}; $script:RcPartPend = ''
$script:RcItems = @(); $script:RcMeta = $null; $script:RcScanError = ''; $script:RcGroup = 'all'; $script:RcDest = ''; $script:RcLastRun = $null; $script:RcLoading = $false
$script:RcPendItems = @(); $script:RcPendSource = ''; $script:RcPendPart = 0; $script:RcPendDest = ''; $script:RcPendMode = ''
. "$PSScriptRoot/uifake.ps1"

function New-It([string]$Kind, [string]$Name, [string]$Path, [long]$Len, [int]$Chance, [long]$Mod = 0, [long]$Del = 0, [string]$Note = '') {
    $ext = ''
    if ($Name.Contains('.')) { $ext = $Name.Substring($Name.LastIndexOf('.') + 1).ToLowerInvariant() }
    return [pscustomobject]@{ Kind = $Kind; Rec = 0; Offset = 0; Length = $Len; Name = $Name; Path = $Path; Ext = $ext; Modified = $Mod; Deleted = $Del; Chance = $Chance; Note = $Note }
}

# =====================================================================
#  1) tür grupları
# =====================================================================
Assert-Eq (Get-RcGroup 'JPG') 'img' 'JPG resim'
Assert-Eq (Get-RcGroup '.png') 'img' 'noktalı uzantı'
Assert-Eq (Get-RcGroup 'docx') 'doc' 'docx belge'
Assert-Eq (Get-RcGroup 'PDF') 'doc' 'pdf belge'
Assert-Eq (Get-RcGroup 'mp4') 'media' 'mp4 ses/video'
Assert-Eq (Get-RcGroup 'flac') 'media' 'flac ses/video'
Assert-Eq (Get-RcGroup 'zip') 'arch' 'zip arşiv'
Assert-Eq (Get-RcGroup '7z') 'arch' '7z arşiv'
Assert-Eq (Get-RcGroup 'sqlite') 'other' 'sqlite diğer'
Assert-Eq (Get-RcGroup '') 'other' 'uzantısız diğer'
Assert-Eq (Get-RcGroup 'xyz') 'other' 'bilinmeyen diğer'
$seen = @{}
foreach ($k in @($script:RcExtGroup.Keys)) {
    Assert-True ($k -cmatch '^[a-z0-9]+$') "uzantı küçük harf ve noktasız: $k"
    Assert-True (@('img', 'doc', 'media', 'arch') -contains [string]$script:RcExtGroup[$k]) "geçerli grup: $k"
}
Assert-Eq (@($script:RcGroupNames.Keys) -join ',') 'all,img,doc,media,arch,other' 'grup sırası'
# motorun imza taramasının ürettiği her uzantı bir gruba düşer (diğer değil, sqlite hariç)
foreach ($e in @('jpg', 'png', 'gif', 'bmp', 'pdf', 'zip', 'docx', 'xlsx', 'pptx', 'odt', 'ods', 'epub', 'apk', 'jar', 'doc', 'xls', 'ppt', 'mp4', 'wav', 'avi', 'webp', '7z')) {
    Assert-True ((Get-RcGroup $e) -ne 'other') "motor uzantısı gruplu: $e"
}

$cnt = Get-RcGroupCounts @(
    (New-It 'mft' 'a.jpg' 'x' 10 100), (New-It 'mft' 'b.JPG' 'x' 10 50), (New-It 'mft' 'c.pdf' 'x' 10 90), (New-It 'mft' 'd.mp3' 'x' 10 80),
    (New-It 'mft' 'e.zip' 'x' 10 80), (New-It 'mft' 'f.xyz' 'x' 10 80), (New-It 'mft' 'g.jpg' 'x' 10 0), $null)
Assert-Eq $cnt.all 6 'sayım: tümü (şansı sıfır olan sayılmaz)'
Assert-Eq $cnt.img 2 'sayım: resim'
Assert-Eq $cnt.doc 1 'sayım: belge'
Assert-Eq $cnt.media 1 'sayım: ses/video'
Assert-Eq $cnt.arch 1 'sayım: arşiv'
Assert-Eq $cnt.other 1 'sayım: diğer'
$cnt0 = Get-RcGroupCounts @()
Assert-Eq $cnt0.all 0 'boş liste sayımı'

# =====================================================================
#  2) şans metni ve renk
# =====================================================================
Assert-True ((Format-RcChance 100) -match '^%100\s+\S\s+çok yüksek$') 'şans 100'
Assert-True ((Format-RcChance 90) -match 'çok yüksek') 'şans 90'
Assert-True ((Format-RcChance 89) -match 'yüksek' -and (Format-RcChance 89) -notmatch 'çok') 'şans 89'
Assert-True ((Format-RcChance 70) -match 'yüksek') 'şans 70'
Assert-True ((Format-RcChance 69) -match 'orta') 'şans 69'
Assert-True ((Format-RcChance 40) -match 'orta') 'şans 40'
Assert-True ((Format-RcChance 39) -match 'düşük') 'şans 39'
Assert-True ((Format-RcChance 1) -match 'düşük') 'şans 1'
Assert-Eq (Get-RcChanceBr 100) 'BrGood' 'renk 100'
Assert-Eq (Get-RcChanceBr 70) 'BrGood' 'renk 70'
Assert-Eq (Get-RcChanceBr 69) 'BrWarn' 'renk 69'
Assert-Eq (Get-RcChanceBr 40) 'BrWarn' 'renk 40'
Assert-Eq (Get-RcChanceBr 39) 'BrBad' 'renk 39'

# =====================================================================
#  3) tarih ve metin temizliği
# =====================================================================
Assert-True ($null -eq (ConvertFrom-RcTime 0)) 'tarih: sıfır'
Assert-True ($null -eq (ConvertFrom-RcTime -5)) 'tarih: eksi'
Assert-True ($null -eq (ConvertFrom-RcTime 9223372036854775807)) 'tarih: taşan değer'
Assert-True ($null -eq (ConvertFrom-RcTime 100000000)) 'tarih: 1601 yılı geçersiz sayılır'
Assert-True ($null -eq (ConvertFrom-RcTime 'abc')) 'tarih: metin'
$dt = ConvertFrom-RcTime 133604154000000000
Assert-Eq $dt.ToUniversalTime().ToString('yyyy-MM-dd HH:mm') '2024-05-17 10:30' 'tarih: geçerli FILETIME'
Assert-Eq (Format-RcDate 0) '' 'tarih metni: boş'
Assert-True ((Format-RcDate 133604154000000000) -match '^\d{2}\.\d{2}\.\d{4} \d{2}:\d{2}$') 'tarih metni biçimi'

Assert-Eq (Remove-RcControl 'rapor.docx') 'rapor.docx' 'temiz ad aynı kalır'
Assert-Eq (Remove-RcControl ('a' + [char]0 + 'b' + [char]1 + 'c' + [char]31 + 'd' + [char]127 + 'e')) 'a_b_c_d_e' 'denetim karakterleri'
Assert-Eq (Remove-RcControl ('x' + [char]0xD800 + 'y')) 'x_y' 'eşsiz üst vekil'
Assert-Eq (Remove-RcControl ('x' + [char]0xDC00 + 'y')) 'x_y' 'eşsiz alt vekil'
Assert-Eq (Remove-RcControl ('x' + [char]0xFFFE + [char]0xFFFF + 'y')) 'x__y' 'geçersiz Unicode karakterleri'
$emoji = 'a' + [char]0xD83D + [char]0xDE00 + 'b'
Assert-Eq (Remove-RcControl $emoji) $emoji 'geçerli vekil çifti korunur'
Assert-Eq (Remove-RcControl 'Güneş şöyle ğ İ ı') 'Güneş şöyle ğ İ ı' 'Türkçe harfler korunur'
Assert-Eq (Remove-RcControl '') '' 'boş metin'
Assert-Eq (Remove-RcControl $null) '' 'null metin'

# =====================================================================
#  4) satır modeli
# =====================================================================
$m1 = New-RcRowModel (New-It 'mft' 'Rapor 2024.docx' 'Belgeler\Eski' 2097152 100 133604154000000000 133604154000000000)
Assert-Eq $m1.Title 'Rapor 2024.docx' 'satır: başlık'
Assert-True ($m1.Detail -match 'Belgeler\\Eski') 'satır: klasör yolu'
Assert-True ($m1.Detail -match '2(\.|,)0 MB|2 MB') 'satır: boyut'
Assert-True ($m1.Detail -match 'değişiklik 17\.05\.2024|değişiklik 1[67]\.05\.2024') 'satır: değişiklik tarihi'
Assert-True ($m1.Detail -match 'silinme ') 'satır: silinme tarihi'
Assert-Eq $m1.BrCol 'BrGood' 'satır: renk'
Assert-True ($m1.Tag -match '%100') 'satır: şans'
$m2 = New-RcRowModel (New-It 'carve' 'kurtarilan_00001.jpg' '' 4096 85 0 0 'İmza taramasıyla bulundu; dosya adı ve tarihi bilinmiyor.')
Assert-True ($m2.Detail -match 'İmza taramasıyla bulundu') 'carve: açıklama'
Assert-True ($m2.Detail -notmatch 'silinme') 'carve: silinme tarihi yok'
Assert-True ($m2.Detail -notmatch 'değişiklik') 'carve: değişiklik tarihi yok'
$m3 = New-RcRowModel (New-It 'mft' 'k.txt' '' 10 50 0 0 'Disk alanı kısmen yeniden kullanılmış; dosya eksik ya da bozuk olabilir.')
Assert-True ($m3.Detail -match 'sürücünün kökü') 'kök klasör metni'
Assert-True ($m3.Detail -match 'kısmen yeniden') 'not eklenir'
Assert-Eq $m3.BrCol 'BrWarn' 'orta şans rengi'
$m4 = New-RcRowModel (New-It 'mft' ('x' + [char]1 + 'y.txt') ('a' + [char]0 + 'b') 5 100)
Assert-Eq $m4.Title 'x_y.txt' 'başlıktan denetim karakteri atılır'
Assert-True ($m4.Detail -match 'a_b') 'yoldan denetim karakteri atılır'
$m5 = New-RcRowModel (New-It 'mft' '   ' 'x' 5 100)
Assert-Eq $m5.Title '(adsız)' 'boş ad'
# rastgele çöp adlar XML'e güvenle yazılabilir (XamlReader bozuk karakterde çöker)
$rng = New-Object System.Random 12345
$okXml = $true
for ($i = 0; $i -lt 400; $i++) {
    $sb = New-Object System.Text.StringBuilder
    $len = $rng.Next(1, 40)
    for ($j = 0; $j -lt $len; $j++) { [void]$sb.Append([char]$rng.Next(0, 65536)) }
    $nm = $sb.ToString()
    $m = New-RcRowModel (New-It 'mft' $nm $nm 100 100 0 0 $nm)
    try { [void][System.Xml.XmlConvert]::VerifyXmlChars([string]$m.Title); [void][System.Xml.XmlConvert]::VerifyXmlChars([string]$m.Detail) } catch { $okXml = $false }
}
Assert-True $okXml 'rastgele adlarla satır metni XML için geçerli (400 deneme)'

# =====================================================================
#  5) süzme ve sıralama
# =====================================================================
$items = @(
    (New-It 'mft' 'a.jpg' 'Resimler' 100 70 0 500),
    (New-It 'mft' 'b.jpg' 'Resimler\Tatil' 100 100 0 100),
    (New-It 'mft' 'c.docx' 'Belgeler' 100 100 0 900),
    (New-It 'mft' 'd.mp3' 'Müzik' 100 0 0 50),
    (New-It 'carve' 'kurtarilan_00001.png' '' 100 85 0 0),
    (New-It 'mft' 'e.zip' 'Arşiv' 100 40 0 10),
    (New-It 'mft' 'ÖNEMLİ.pdf' 'Belgeler' 100 100 0 900)
)
$d = Get-RcDisplay $items 'all' '' 300
Assert-Eq $d.Total 7 'görüntü: toplam'
Assert-Eq $d.Hidden 1 'görüntü: şansı sıfır olan gizlenir'
Assert-Eq $d.Matched 6 'görüntü: eşleşen'
$names = @($d.Rows | ForEach-Object { [string]$items[$_.Idx].Name })
Assert-Eq ($names -join ',') 'c.docx,ÖNEMLİ.pdf,b.jpg,kurtarilan_00001.png,a.jpg,e.zip' 'sıra: şans, sonra silinme zamanı, sonra ad'
$dg = Get-RcDisplay $items 'img' '' 300
Assert-Eq (@($dg.Rows | ForEach-Object { [string]$items[$_.Idx].Name }) -join ',') 'b.jpg,kurtarilan_00001.png,a.jpg' 'tür süzgeci: resim'
$dd = Get-RcDisplay $items 'doc' '' 300
Assert-Eq @($dd.Rows).Count 2 'tür süzgeci: belge'
$dq = Get-RcDisplay $items 'all' 'tatil' 300
Assert-Eq @($dq.Rows).Count 1 'arama: klasör adında (büyük/küçük harf duyarsız)'
$dq2 = Get-RcDisplay $items 'all' 'ÖNEMLİ' 300
Assert-Eq @($dq2.Rows).Count 1 'arama: Türkçe büyük harf'
$dq3 = Get-RcDisplay $items 'img' 'docx' 300
Assert-Eq @($dq3.Rows).Count 0 'tür ve arama birlikte'
$dc = Get-RcDisplay $items 'all' '' 2
Assert-Eq @($dc.Rows).Count 2 'satır sınırı'
Assert-Eq $dc.Matched 6 'sınırda eşleşen sayısı korunur'
$de = Get-RcDisplay @() 'all' '' 300
Assert-Eq $de.Total 0 'boş liste'
Assert-Eq @($de.Rows).Count 0 'boş liste satırı yok'
$dn = Get-RcDisplay @($null, (New-It 'mft' 'x.txt' '' 5 100)) 'all' '' 300
Assert-Eq @($dn.Rows).Count 1 'null öğe atlanır'
Assert-Eq $dn.Rows[0].Idx 1 'indeks özgün listeye göre'

# =====================================================================
#  6) sürücü seçici
# =====================================================================
$disks = @(
    @{ Drive = 'C:'; Type = 'Fixed'; State = 'none'; Label = 'Windows'; Fs = 'NTFS'; Size = [double]255GB; Free = [double]100GB; Media = 'SSD'; Bus = 'NVMe'; DiskName = 'A' },
    @{ Drive = 'D:'; Type = 'Fixed'; State = 'locked'; Label = 'Veri'; Fs = 'NTFS'; Size = [double]1TB; Free = [double]500GB; Media = 'HDD'; Bus = 'SATA'; DiskName = 'B' },
    @{ Drive = 'E:'; Type = 'Removable'; State = 'none'; Label = ''; Fs = 'exFAT'; Size = [double]32GB; Free = [double]10GB; Media = 'Unspecified'; Bus = 'USB'; DiskName = 'C' },
    @{ Drive = 'F:'; Type = 'Fixed'; State = 'unknown'; Label = ''; Fs = ''; Size = [double]0; Free = [double]0; Media = ''; Bus = ''; DiskName = '' }
)
$n1 = Get-RcVolumeName $disks[0] 'C:'
Assert-True ($n1 -match '^C:  Windows' -and $n1 -match 'NTFS' -and $n1 -match 'SSD' -and $n1 -match 'Windows$') 'ad: sistem sürücüsü'
$n2 = Get-RcVolumeName $disks[1] 'C:'
Assert-True ($n2 -match 'HDD' -and $n2 -match 'kilitli' -and $n2 -notmatch 'Windows$') 'ad: kilitli HDD'
$n3 = Get-RcVolumeName $disks[2] 'C:'
Assert-True ($n3 -match '^E:  ·|^E:\s+\S' -and $n3 -match 'exFAT' -and $n3 -match 'USB') 'ad: USB bellek'
$n4 = Get-RcVolumeName $disks[3] 'C:'
Assert-True ($n4 -match 'dosya sistemi yok') 'ad: dosya sistemi yok'
$ch = Get-RcVolumeChoices $disks 'C:' '' 1
Assert-Eq @($ch).Count 4 'seçici: dört sürücü'
Assert-Eq $ch[0].Key 'C:' 'seçici: anahtar'
Assert-True ($ch[0].IsOs -eq $true -and $ch[1].IsOs -eq $false) 'seçici: sistem işareti'
Assert-True ($ch[1].Locked -eq $true -and $ch[0].Locked -eq $false) 'seçici: kilit işareti'
Assert-True ($ch[2].Removable -eq $true -and $ch[0].Removable -eq $false) 'seçici: çıkarılabilir'
Assert-Eq $ch[0].Kind 'Drive' 'seçici: tür'
$ch2 = Get-RcVolumeChoices $disks 'C:' 'E:\yedek\disk.img' 1
Assert-Eq @($ch2).Count 5 'seçici: imaj eklenir'
Assert-Eq $ch2[4].Key 'IMG:0' 'imaj anahtarı'
Assert-True ($ch2[4].Name -match 'disk\.img') 'imaj adı'
Assert-Eq $ch2[4].Kind 'Image' 'imaj türü'
$ch3 = Get-RcVolumeChoices $disks 'C:' 'E:\yedek\disk.img' 3
Assert-Eq @($ch3).Count 7 'seçici: üç bölümlü imaj'
Assert-True ($ch3[5].Name -match '2/3') 'bölüm numarası'
$ch4 = Get-RcVolumeChoices @() 'C:' '' 1
Assert-Eq @($ch4).Count 0 'seçici: boş'
$ch5 = Get-RcVolumeChoices @() 'C:' 'x.img' 0
Assert-Eq @($ch5).Count 1 'seçici: yalnızca imaj, bölüm sayısı en az 1'
$r1 = Resolve-RcKey 'D:' 'x.img'
Assert-True ($r1.Kind -eq 'Drive' -and $r1.Source -eq 'D:' -and $r1.Part -eq 0) 'anahtar: sürücü'
$r2 = Resolve-RcKey 'IMG:2' 'x.img'
Assert-True ($r2.Kind -eq 'Image' -and $r2.Source -eq 'x.img' -and $r2.Part -eq 2) 'anahtar: imaj bölümü'
$r3 = Resolve-RcKey '' 'x.img'
Assert-True ($r3.Kind -eq '' -and $r3.Source -eq '') 'anahtar: boş'
$r4 = Resolve-RcKey 'd:' ''
Assert-Eq $r4.Source 'D:' 'anahtar: küçük harf büyütülür'
$k1 = Resolve-RcKey 'PD:2' ''
Assert-True ($k1.Kind -eq 'Disk' -and $k1.Source -eq 'PhysicalDrive2' -and $k1.Part -eq 0 -and $k1.Disk -eq 2) 'anahtar: disk (bölümler okunmadı)'
$k2 = Resolve-RcKey 'PD:11:3' ''
Assert-True ($k2.Kind -eq 'Disk' -and $k2.Source -eq 'PhysicalDrive11' -and $k2.Part -eq 3 -and $k2.Disk -eq 11) 'anahtar: disk bölümü'
$k3 = Resolve-RcKey 'PD:1:all' ''
Assert-True ($k3.Kind -eq 'Disk' -and $k3.Source -eq 'PhysicalDrive1' -and $k3.Part -eq -1 -and $k3.Disk -eq 1) 'anahtar: tüm disk'
$k4 = Resolve-RcKey 'IMG:all' 'x.img'
Assert-True ($k4.Kind -eq 'Image' -and $k4.Source -eq 'x.img' -and $k4.Part -eq -1) 'anahtar: tüm imaj'
Assert-Eq (Resolve-RcKey 'PD:' '').Kind '' 'anahtar: eksik disk numarası geçersiz'
Assert-Eq (Resolve-RcKey 'PD:x' '').Kind '' 'anahtar: sayı olmayan disk geçersiz'
Assert-Eq (Resolve-RcKey 'PD:12345' '').Kind '' 'anahtar: çok uzun disk numarası geçersiz'
Assert-Eq (Resolve-RcKey 'PD:1:2:3' '').Kind '' 'anahtar: fazladan parça geçersiz'
Assert-Eq (Resolve-RcKey 'CD:1' '').Kind '' 'anahtar: bilinmeyen ön ek geçersiz'
Assert-Eq (Resolve-RcKey 'E:\x' '').Kind '' 'anahtar: yol sürücü anahtarı değildir'

# fiziksel diskler ve bölümleri
$phys = @(
    @{ Number = 0; Name = 'Samsung SSD 980'; Size = [double]500GB; Bus = 'NVMe'; Media = 'SSD'; Style = 'GPT'; IsSystem = $true; Offline = $false; Letters = @('C:')
       Parts = @(@{ Offset = [double]1048576; Size = [double]100MB; Letter = ''; Type = 'System' }, @{ Offset = [double]420000000; Size = [double]255GB; Letter = 'C:'; Type = 'Basic' }) },
    @{ Number = 1; Name = 'SanDisk Ultra'; Size = [double]29GB; Bus = 'USB'; Media = 'Unspecified'; Style = 'MBR'; IsSystem = $false; Offline = $false; Letters = @('E:')
       Parts = @(@{ Offset = [double]1048576; Size = [double]14GB; Letter = 'E:'; Type = 'IFS' }, @{ Offset = [double]15000000000; Size = [double]15GB; Letter = ''; Type = 'Unknown' }) },
    @{ Number = 2; Name = 'Kart okuyucu'; Size = [double]0; Bus = 'USB'; Media = ''; Style = 'RAW'; IsSystem = $false; Offline = $false; Letters = @(); Parts = @() },
    @{ Number = 3; Name = 'WD Elements'; Size = [double]2TB; Bus = 'USB'; Media = 'HDD'; Style = 'RAW'; IsSystem = $false; Offline = $false; Letters = @(); Parts = @() }
)
$dn0 = Get-RcDiskName $phys[0]
Assert-True ($dn0 -match '^Disk 0  Samsung SSD 980' -and $dn0 -match 'SSD' -and $dn0 -match 'Windows$') 'disk adı: sistem diski'
$dn1 = Get-RcDiskName $phys[1]
Assert-True ($dn1 -match '^Disk 1  SanDisk Ultra' -and $dn1 -match 'USB' -and $dn1 -notmatch 'Windows') 'disk adı: USB'
Assert-Eq (Get-RcFsText 'BITLOCKER') 'BitLocker (şifreli)' 'dosya sistemi metni: BitLocker'
Assert-Eq (Get-RcFsText 'LUKS') 'LUKS (şifreli)' 'dosya sistemi metni: LUKS'
Assert-Eq (Get-RcFsText '') 'biçim tanınmadı' 'dosya sistemi metni: boş'
Assert-Eq (Get-RcFsText 'ext4') 'ext4' 'dosya sistemi metni: ext4'
Assert-Eq (Get-RcPartLetter $phys[1] @{ Start = [double]1048576 }) 'E:' 'bölüm harfi başlangıç konumundan bulunur'
Assert-Eq (Get-RcPartLetter $phys[1] @{ Start = [double]15000000000 }) '' 'harfsiz bölüm'
Assert-Eq (Get-RcPartLetter $null @{ Start = [double]1 }) '' 'disk bilgisi yoksa harf yok'
# bölümler henüz okunmadı
$cp0 = Get-RcVolumeChoices @() 'C:' '' 1 $phys $null
Assert-Eq @($cp0).Count 3 'seçici: sıfır boyutlu disk (kart okuyucu) listelenmez'
Assert-True ($cp0[0].Key -eq 'PD:0' -and $cp0[0].Kind -eq 'Disk' -and $cp0[0].Loaded -eq $false -and $cp0[0].DiskNo -eq 0 -and $cp0[0].IsOs -eq $true) 'seçici: sistem diski satırı'
Assert-True ($cp0[0].Name -match 'bölümleri okumak için seçin') 'seçici: bölümler okunmadı notu'
Assert-True ($cp0[1].Key -eq 'PD:1' -and $cp0[1].Removable -eq $true -and @($cp0[1].Letters) -contains 'E:') 'seçici: USB disk satırı'
Assert-Eq $cp0[2].Key 'PD:3' 'seçici: harfsiz disk de listelenir'
# bölümler okundu
$pcache = @{
    'PhysicalDrive1' = @{ Ok = $true; Error = ''; Parts = @(@{ Index = 0; Start = [double]1048576; Length = [double]14GB; Fs = 'exFAT'; Kind = 'MBR:07' }, @{ Index = 1; Start = [double]15000000000; Length = [double]15GB; Fs = 'ext4'; Kind = 'MBR:83' }) }
    'PhysicalDrive3' = @{ Ok = $true; Error = ''; Parts = @() }
    'PhysicalDrive0' = @{ Ok = $true; Error = ''; Parts = @(@{ Index = 0; Start = [double]0; Length = [double]500GB; Fs = 'NTFS'; Kind = 'birim' }) }
}
$cp1 = Get-RcVolumeChoices @() 'C:' '' 1 $phys $pcache
Assert-Eq (@($cp1 | ForEach-Object { $_.Key }) -join ',') 'PD:0:0,PD:1:0,PD:1:1,PD:1:all,PD:3:0' 'seçici: bölümler ve tüm disk satırı'
Assert-True ($cp1[0].Name -match 'NTFS' -and $cp1[0].Name -notmatch 'bölüm 1/1') 'seçici: bölümsüz tek birim sade yazılır'
Assert-True ($cp1[1].Name -match 'bölüm 1/2' -and $cp1[1].Name -match 'exFAT' -and $cp1[1].Name -match 'E:') 'seçici: harfli bölüm'
Assert-True ($cp1[2].Name -match 'bölüm 2/2' -and $cp1[2].Name -match 'ext4' -and $cp1[2].Name -notmatch 'E:') 'seçici: harfsiz ext4 bölümü'
Assert-True ($cp1[3].Whole -eq $true -and $cp1[3].Name -match 'tüm disk' -and $cp1[1].Whole -eq $false) 'seçici: tüm disk satırı'
Assert-True ($cp1[1].Loaded -eq $true -and $cp1[1].Kind -eq 'Disk' -and $cp1[1].DiskNo -eq 1) 'seçici: yüklenmiş bölüm satırı'
Assert-True ($cp1[4].Name -match 'bölüm düzeni ya da dosya sistemi tanınmadı') 'seçici: tanınmayan disk tek satır, imza taraması'
Assert-Eq @($cp1 | Where-Object { $_.Key -eq 'PD:0:all' }).Count 0 'seçici: tek birimde tüm disk satırı yok'
# BitLocker bölümü kilitli sayılır
$pcache2 = @{ 'PhysicalDrive1' = @{ Ok = $true; Error = ''; Parts = @(@{ Index = 0; Start = [double]1; Length = [double]1GB; Fs = 'BITLOCKER'; Kind = 'GPT' }, @{ Index = 1; Start = [double]2; Length = [double]1GB; Fs = 'NTFS'; Kind = 'GPT' }) } }
$cp2 = Get-RcVolumeChoices @() 'C:' '' 1 @($phys[1]) $pcache2
Assert-True ($cp2[0].Locked -eq $true -and $cp2[1].Locked -eq $false -and $cp2[0].Name -match 'BitLocker \(şifreli\)') 'seçici: BitLocker bölümü kilitli'
# okunamayan disk
$pcache3 = @{ 'PhysicalDrive1' = @{ Ok = $false; Error = 'Diske erişim engellendi.'; Parts = @() } }
$cp3 = Get-RcVolumeChoices @() 'C:' '' 1 @($phys[1]) $pcache3
Assert-True ($cp3[0].Key -eq 'PD:1' -and $cp3[0].Loaded -eq $false -and $cp3[0].Name -match 'bölümler okunamadı') 'seçici: bölümleri okunamayan disk'
# imaj: bölümler okundu
$icache = @{ 'E:\yedek\disk.img' = @{ Ok = $true; Error = ''; Parts = @(@{ Index = 0; Start = [double]1048576; Length = [double]100GB; Fs = 'NTFS'; Kind = 'GPT' }, @{ Index = 1; Start = [double]100000000000; Length = [double]50GB; Fs = 'ext4'; Kind = 'GPT' }) } }
$ci = Get-RcVolumeChoices @() 'C:' 'E:\yedek\disk.img' 1 @() $icache
Assert-Eq (@($ci | ForEach-Object { $_.Key }) -join ',') 'IMG:0,IMG:1,IMG:all' 'seçici: imaj bölümleri ve tüm imaj'
Assert-True ($ci[0].Name -match 'disk\.img' -and $ci[0].Name -match 'bölüm 1/2' -and $ci[0].Name -match 'NTFS' -and $ci[1].Name -match 'ext4') 'seçici: imaj bölüm adları'
Assert-True ($ci[2].Whole -eq $true -and $ci[2].Kind -eq 'Image') 'seçici: tüm imaj satırı'
$ci2 = Get-RcVolumeChoices @() 'C:' 'E:\yedek\disk.img' 1 @() @{ 'E:\yedek\disk.img' = @{ Ok = $true; Error = ''; Parts = @() } }
Assert-Eq @($ci2).Count 1 'seçici: bölümsüz tanınmayan imaj tek satır'
Assert-True ($ci2[0].Key -eq 'IMG:0' -and $ci2[0].Name -match 'tanınmadı') 'seçici: tanınmayan imaj açıklaması'

# =====================================================================
#  7) hedef denetimi, metinler
# =====================================================================
Assert-True ((Test-RcDestUi 'C:' 'Drive' '') -match 'seçilmedi') 'hedef boş'
Assert-True ((Test-RcDestUi 'C:' 'Drive' 'kurtarilan') -match 'tam bir yol') 'hedef göreli'
Assert-True ((Test-RcDestUi 'C:' 'Drive' 'C:\Kurtarilan') -match 'C: sürücüsünde olamaz') 'hedef aynı sürücü'
Assert-True ((Test-RcDestUi 'C:' 'Drive' 'c:\Kurtarilan') -match 'C: sürücüsünde olamaz') 'hedef aynı sürücü (küçük harf)'
Assert-True ((Test-RcDestUi 'c:' 'Drive' 'C:\') -match 'olamaz') 'kaynak küçük harf'
Assert-Eq (Test-RcDestUi 'C:' 'Drive' 'D:\Kurtarilan') '' 'hedef başka sürücü'
Assert-Eq (Test-RcDestUi 'C:' 'Drive' '\\sunucu\paylasim\kurtar') '' 'ağ yolu'
Assert-Eq (Test-RcDestUi 'E:\disk.img' 'Image' 'E:\Kurtarilan') '' 'imaj kaynağında aynı sürücü serbest'
Assert-True ((Test-RcDestUi 'PhysicalDrive1' 'Disk' 'E:\Kurtarilan' @('E:', 'F:')) -match 'taranan diskte \(Disk 1\) olamaz') 'hedef taranan diskte'
Assert-True ((Test-RcDestUi 'PhysicalDrive1' 'Disk' 'f:\Kurtarilan' @('E:', 'F:')) -match 'olamaz') 'hedef taranan diskte (küçük harf)'
Assert-Eq (Test-RcDestUi 'PhysicalDrive1' 'Disk' 'D:\Kurtarilan' @('E:', 'F:')) '' 'hedef başka diskte'
Assert-Eq (Test-RcDestUi 'PhysicalDrive1' 'Disk' '\\sunucu\paylasim\kurtar' @('E:')) '' 'disk taraması: ağ yolu serbest'
Assert-Eq (Test-RcDestUi 'PhysicalDrive3' 'Disk' 'E:\Kurtarilan' @()) '' 'harfsiz diskte hedef serbest'
Assert-True ((Test-RcDestUi 'PhysicalDrive1' 'Disk' 'kurtarilan' @('E:')) -match 'tam bir yol') 'disk taraması: göreli hedef'

$meta = @{ Source = 'C:'; Part = 0; Fs = 'NTFS'; ClusterSize = 4096; VolumeBytes = [double]255GB; FreeBytes = [double]100GB; Mode = 'Both'; Truncated = $true; Canceled = $true
    Stats = @{ Records = 1000; Deleted = 30; Skipped = 4; ReadErrors = 2; FromTable = 25; Carved = 5 }; Partitions = 1 }
$sl = Get-RcSummaryLines $meta 30 3
$stx = (@($sl | ForEach-Object { [string]$_.T }) -join ' | ')
Assert-True ($stx -match 'NTFS' -and $stx -match 'derin tarama' -and $stx -match 'boş alan') 'özet: ilk satır'
Assert-True ($stx -match '30 dosya bulundu \(25 silinmiş kayıttan, 5 imza taramasıyla\)') 'özet: bulunan'
Assert-True ($stx -match '3 kayıt.*listelenmedi') 'özet: gizlenen'
Assert-True ($stx -match '4 kayıt atlandı') 'özet: atlanan'
Assert-True ($stx -match '2 okuma hatası') 'özet: okuma hatası'
Assert-True ($stx -match 'ilk 20000 kayıtla sınırlı') 'özet: kesilmiş'
Assert-True ($stx -match 'yarıda kesildi') 'özet: iptal'
Assert-Eq @($sl | Where-Object { $_.K -eq 'warn' }).Count 3 'özet: üç uyarı satırı'
$meta2 = @{ Source = 'E:'; Part = 0; Fs = 'exFAT'; ClusterSize = 32768; VolumeBytes = [double]32GB; FreeBytes = [double]10GB; Mode = 'Quick'; Truncated = $false; Canceled = $false
    Stats = @{ Records = 0; Deleted = 0; Skipped = 0; ReadErrors = 0; FromTable = 0; Carved = 12 }; Partitions = 1 }
$sl2 = Get-RcSummaryLines $meta2 12 0
$stx2 = (@($sl2 | ForEach-Object { [string]$_.T }) -join ' | ')
Assert-True ($stx2 -match 'imza taraması' -and $stx2 -match 'adı ve tarihi bilinmez') 'özet: yöntem bilgisi olmayan eski meta'
Assert-Eq @($sl2 | Where-Object { $_.K -eq 'warn' }).Count 0 'özet: uyarı yok'
$metaFat = @{ Source = 'E:'; Part = 0; Fs = 'exFAT'; ClusterSize = 32768; VolumeBytes = [double]32GB; FreeBytes = [double]10GB; Mode = 'Quick'; Truncated = $false; Canceled = $false; Method = 'exfat'; Raw = $false; Note = ''
    Stats = @{ Records = 0; Deleted = 7; Skipped = 0; ReadErrors = 0; FromTable = 7; Carved = 0 }; Partitions = 1 }
$slF = Get-RcSummaryLines $metaFat 7 0
$stxF = (@($slF | ForEach-Object { [string]$_.T }) -join ' | ')
Assert-True ($stxF -match 'exFAT' -and $stxF -match 'hızlı tarama' -and $stxF -match 'boş alan' -and $stxF -notmatch 'imza') 'özet: exFAT hızlı tarama kayıtları okur'
Assert-True ($stxF -match '7 dosya bulundu\.') 'özet: exFAT bulunan'
$metaExt = @{ Source = 'PhysicalDrive3'; Part = 1; Fs = 'ext4'; ClusterSize = 4096; VolumeBytes = [double]8GB; FreeBytes = [double]3GB; Mode = 'Quick'; Truncated = $false; Canceled = $false; Method = 'free'; Raw = $false; Note = ''
    Stats = @{ Records = 0; Deleted = 0; Skipped = 0; ReadErrors = 0; FromTable = 0; Carved = 5 }; Partitions = 2 }
$slE = Get-RcSummaryLines $metaExt 5 0
$stxE = (@($slE | ForEach-Object { [string]$_.T }) -join ' | ')
Assert-True ($stxE -match 'ext4' -and $stxE -match 'boş alanda imza taraması' -and $stxE -match 'adı ve tarihi bilinmez') 'özet: ext boş alanda imza taraması'
$metaRaw = @{ Source = 'E:\x.img'; Part = 0; Fs = 'Btrfs'; ClusterSize = 4096; VolumeBytes = [double]1GB; FreeBytes = [double]1GB; Mode = 'Quick'; Truncated = $false; Canceled = $false; Method = 'raw'; Raw = $true
    Note = 'Btrfs dosya sisteminde silinmiş kayıtlar okunamıyor; tüm alan dosya imzalarına göre taranıyor.'
    Stats = @{ Records = 0; Deleted = 0; Skipped = 0; ReadErrors = 0; FromTable = 0; Carved = 2 }; Partitions = 1 }
$slR = Get-RcSummaryLines $metaRaw 2 0
$stxR = (@($slR | ForEach-Object { [string]$_.T }) -join ' | ')
Assert-True ($stxR -match 'tüm alanda imza taraması' -and $stxR -match 'taranan alan' -and $stxR -notmatch 'boş alan') 'özet: ham mod'
Assert-Eq @($slR | Where-Object { $_.K -eq 'warn' }).Count 1 'özet: ham modun nedeni uyarı olarak gösterilir'
Assert-True ($stxR -match 'Btrfs dosya sisteminde silinmiş kayıtlar okunamıyor') 'özet: ham mod nedeni metni'
$sl3 = Get-RcSummaryLines $meta2 0 0
Assert-Eq @($sl3).Count 1 'özet: sonuç yoksa yalnızca ilk satır'

$cit = @((New-It 'mft' 'a.doc' '' 1048576 100), (New-It 'mft' 'b.doc' '' 1048576 50))
$ctx = Get-RcConfirmText $cit 'D:\Kurtarilan'
Assert-True ($ctx -match '2 dosya' -and $ctx -match 'D:\\Kurtarilan' -and $ctx -match 'üzerine yazılmaz' -and $ctx -match 'hiçbir şey yazılmaz') 'onay metni'
Assert-True ($ctx -match '1 dosyanın kurtarılma şansı düşük') 'onay metni: düşük şans uyarısı'
Assert-True ((Get-RcConfirmText @((New-It 'mft' 'a.doc' '' 10 100)) 'D:\K') -notmatch 'düşük ya da orta') 'onay metni: uyarı yalnızca gerekince'
Assert-Eq (Get-RcFootText 0 0 '') 'Seçili: 0 dosya  ·  Hedef klasör henüz seçilmedi'.Replace('  ·  ', "  $([char]0x00B7)  ") 'alt metin: boş'
Assert-True ((Get-RcFootText 3 2097152 'D:\K') -match '^Seçili: 3 dosya\s+\S\s+2.*MB\s+\S\s+Hedef: D:\\K$') 'alt metin: dolu'

# =====================================================================
#  8) çizim ve işlem akışı (sahte denetimlerle)
# =====================================================================
$script:IsAdmin = $true
$script:UiState = @{ Page = 'solve' }
$script:SlTab = 'recover'
$script:StLoading = $false
$ui = @{}
foreach ($n in @('sl_List', 'sl_RcVol', 'sl_RcType', 'sl_RcFind', 'sl_Foot')) { $ui[$n] = New-FakeCtl }
$script:SlDisks = $null

# 8a) sürücüler henüz okunmadıysa
Render-SlRecover
Assert-Eq $script:Loads 1 'sürücüler okunmamışsa yükleme istenir'
Assert-True ($null -ne (Find-NoteLike $ui.sl_List 'okunuyor')) 'okunuyor notu'
Assert-Eq $ui.sl_RcType.Items.Count 6 'tür seçici hazır'

# 8b) sürücüler geldi
$script:SlDisks = @{ Ok = $true; Sys = @{ OsDrive = 'C:'; IsAdmin = $true }; Disks = $disks }
Render-SlRecover
Assert-Eq $ui.sl_RcVol.Items.Count 4 'sürücü seçici dolu'
Assert-Eq (Get-ComboKey $ui.sl_RcVol) 'C:' 'varsayılan: sistem sürücüsü'
Assert-Eq $script:RcSource 'C:' 'kaynak ayarlandı'
Assert-Eq $script:RcSourceKind 'Drive' 'kaynak türü'
Assert-True ($null -ne (Find-NoteLike $ui.sl_List 'yalnızca okur')) 'giriş metni'
Assert-True ($null -ne (Find-NoteLike $ui.sl_List 'Windows sürücüsünü')) 'sistem sürücüsü uyarısı'
Assert-True ($null -ne (Find-NoteLike $ui.sl_List 'SSD')) 'SSD uyarısı'
$binRow = @(Get-RowsOf $ui.sl_List)[0]
Assert-True ($binRow.Vars.Title -match 'Geri Dönüşüm' -and $binRow.Tag.Do -eq 'RcBin') 'geri dönüşüm kutusu satırı'
Invoke-RcAction $binRow.Tag
Assert-Eq $script:Opened[0] 'path:shell:RecycleBinFolder' 'geri dönüşüm kutusu açılır'
Assert-True ($ui.sl_Foot.Text -match 'Seçili: 0 dosya') 'alt metin: seçim yok'

# 8c) kilitli sürücü taranmaz
Reset-Fake
$script:RcSelKey = 'D:'
Select-ComboKey $ui.sl_RcVol 'D:' | Out-Null
Select-RcVolume
Assert-Eq $script:RcSource 'D:' 'D: seçildi'
Assert-True ($null -ne (Find-NoteLike $ui.sl_List 'kilitli')) 'kilitli sürücü uyarısı'
Start-RcScan 'Quick'
Assert-Eq $script:Asyncs.Count 0 'kilitli sürücü için iş başlamaz'
Assert-True ((Get-LastToast).T -match 'kilitli') 'kilit bildirimi'

# 8d) yönetici değilse sürücü taranmaz
Reset-Fake
$script:RcSelKey = 'C:'
Select-ComboKey $ui.sl_RcVol 'C:' | Out-Null
Select-RcVolume
$script:IsAdmin = $false
Start-RcScan 'Quick'
Assert-Eq $script:Asyncs.Count 0 'yönetici değilse iş başlamaz'
Assert-True ((Get-LastToast).T -match 'yönetici') 'yönetici bildirimi'
Render-RcBody
Assert-True ($null -ne (Find-NoteLike $ui.sl_List 'yönetici olarak çalışmıyor')) 'yönetici uyarısı çizilir'
$script:IsAdmin = $true

# 8e) hızlı tarama başlatılır, sonuç çizilir
Reset-Fake
Start-RcScan 'Quick'
Assert-Eq $script:Asyncs.Count 1 'tarama işi başladı'
$a = $script:Asyncs[0]
Assert-True ($a.Entry -eq 'Job_RecoverScan' -and $a.Params.Source -eq 'C:' -and $a.Params.Mode -eq 'Quick' -and $a.Params.Partition -eq 0 -and $a.Params.MaxResults -eq 20000) 'tarama parametreleri'
Assert-True ($a.Label -match 'salt okunur') 'tarama etiketi'
$scanItems = @(
    (New-It 'mft' 'Tatil.jpg' 'Resimler' 3145728 100 133604154000000000 133604154000000000),
    (New-It 'mft' 'Rapor.docx' 'Belgeler' 65536 100 133604154000000000 133604154000000000),
    (New-It 'mft' 'Eski.zip' 'Arşiv' 1000000 45 0 133604154000000000 'Disk alanı kısmen yeniden kullanılmış; dosya eksik ya da bozuk olabilir.'),
    (New-It 'mft' 'Silinmis.txt' '' 1000 0 0 0 'Disk alanı başka dosyalarca kullanılıyor; büyük olasılıkla üzerine yazılmış.'),
    (New-It 'carve' 'kurtarilan_00001.png' '' 20000 85 0 0)
)
$fakeScan = @{ Ok = $true; Error = ''; Fs = 'NTFS'; ClusterSize = 4096; VolumeBytes = [double]255GB; FreeBytes = [double]100GB; Items = $scanItems; Truncated = $false; Canceled = $false; Mode = 'Quick'; Partitions = 1
    Stats = @{ Records = 100; Deleted = 4; Skipped = 1; ReadErrors = 0; FromTable = 4; Carved = 1 } }
& $a.OnDone $fakeScan
Assert-True ($null -ne $script:RcMeta) 'meta kaydedildi'
Assert-Eq $script:RcMeta.Source 'C:' 'meta kaynağı'
Assert-Eq $script:RcItems.Count 5 'öğeler saklandı'
Assert-True ((Get-LastToast).T -match '4 silinmiş dosya bulundu') 'bulunan sayısı bildirimi'
$rows = @(Get-RowsOf $ui.sl_List | Where-Object { $_.Vars.Title -notmatch 'Geri Dönüşüm Kutusu' })
Assert-Eq $rows.Count 4 'dört satır (şansı sıfır gizli)'
Assert-Eq (($rows | ForEach-Object { $_.Vars.Title }) -join ',') 'Rapor.docx,Tatil.jpg,kurtarilan_00001.png,Eski.zip' 'satır sırası'
Assert-True ($rows[0].Named.Chk.Visibility -eq 'Visible' -and $rows[0].Named.Chk.IsChecked -eq $false) 'onay kutusu görünür ve işaretsiz'
Assert-True ($rows[0].Named.Chk.Handlers.Count -eq 2) 'onay kutusu olayları bağlı'
Assert-Eq $rows[0].Tag.Idx 1 'satır indeksi özgün listeye göre'
Assert-Eq $rows[0].Tag.Len 65536 'satır boyutu'
Assert-True ($null -ne (Find-NoteLike $ui.sl_List '4 dosya bulundu')) 'özet satırı'
Assert-True ($null -ne (Find-NoteLike $ui.sl_List 'üzerine yazıldığı')) 'gizlenen kayıt notu'
Assert-Eq $ui.sl_RcType.Items.Count 6 'tür seçici sayılarla yenilendi'
Assert-True ($ui.sl_RcType.Items[1].Name -match 'Resimler \(2\)') 'resim sayısı (jpg + png)'
Assert-True ($ui.sl_RcType.Items[0].Name -match 'Tümü \(4\)') 'tümü sayısı'

# 8f) seçim, hedef, kurtarma
Reset-Fake
Start-RcRecover
Assert-True ((Get-LastToast).T -match 'işaretleyin') 'seçim yoksa uyarı'
Assert-Eq $script:Confirms.Count 0 'seçim yokken onay yok'
$rows[0].Named.Chk.IsChecked = $true
$rows[1].Named.Chk.IsChecked = $true
Update-RcFoot
Assert-True ($ui.sl_Foot.Text -match 'Seçili: 2 dosya' -and $ui.sl_Foot.Text -match 'Hedef klasör henüz seçilmedi') 'alt metin: iki seçili'
$script:PickFolder = ''
Reset-Fake
Start-RcRecover
Assert-Eq $script:Confirms.Count 0 'hedef seçilmezse onay yok'
$script:PickFolder = 'C:\Kurtarilan'
Start-RcRecover
Assert-Eq $script:Confirms.Count 0 'aynı sürücü hedefi reddedilir'
Assert-True ((Get-LastToast).T -match 'C: sürücüsünde olamaz') 'aynı sürücü bildirimi'
Assert-Eq $script:RcDest '' 'reddedilen hedef kaydedilmez'
Reset-Fake
$script:PickFolder = 'D:\Kurtarilan'
Start-RcRecover
Assert-Eq $script:RcDest 'D:\Kurtarilan' 'hedef kaydedildi'
Assert-Eq $script:Confirms.Count 1 'onay penceresi açıldı'
$cf = $script:Confirms[0]
Assert-True ($cf.Title -eq 'Dosyaları kurtar' -and $cf.Ok -eq 'Kurtar' -and $cf.Text -match '2 dosya' -and $cf.Text -match 'D:\\Kurtarilan') 'onay içeriği'
Assert-True ($cf.Danger -eq $false) 'kurtarma tehlikeli işlem sayılmaz'
Assert-Eq $script:Asyncs.Count 0 'onaydan önce iş başlamaz'
Assert-Eq $script:RcPendItems.Count 2 'bekleyen öğeler'
& $cf.OnOk
Assert-Eq $script:Asyncs.Count 1 'onaydan sonra iş başladı'
$b = $script:Asyncs[0]
Assert-True ($b.Entry -eq 'Job_RecoverFiles' -and $b.Params.Source -eq 'C:' -and $b.Params.Dest -eq 'D:\Kurtarilan' -and $b.Params.KeepPaths -eq $true -and @($b.Params.Items).Count -eq 2) 'kurtarma parametreleri'
Assert-True (@($b.Params.Items)[0].Name -eq 'Rapor.docx' -and @($b.Params.Items)[1].Name -eq 'Tatil.jpg') 'kurtarılacak öğeler seçilenler'

# 8g) sonuç kartı
$td = Join-Path ([System.IO.Path]::GetTempPath()) ('mmrcui' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $td | Out-Null
$rep = Join-Path $td 'Kurtarma-Raporu.csv'
Set-Content -LiteralPath $rep -Value 'x'
& $b.OnDone @{ Ok = $true; Error = ''; Dir = $td; Done = 2; Failed = 0; Bytes = [double]3211264; Report = $rep; Canceled = $false; Results = @() }
Assert-True ((Get-LastToast).T -match '2 dosya kurtarıldı') 'kurtarma bildirimi'
$res = @(Get-RowsOf $ui.sl_List | Where-Object { $_.Vars.Title -match '^Kurtarma tamamlandı' })
Assert-Eq $res.Count 1 'sonuç kartı çizildi'
Assert-True ($res[0].Vars.Detail -match [regex]::Escape($td)) 'sonuç kartı klasörü gösterir'
Assert-True ($res[0].Vars.Btn1 -eq 'Klasörü aç' -and $res[0].Vars.Btn2 -eq 'Raporu aç') 'sonuç kartı düğmeleri'
Assert-Eq $res[0].Named.Act2.Tag.Do 'RcReport' 'ikinci düğme rapor açar'
Reset-Fake
Invoke-RcAction $res[0].Named.Act.Tag
Invoke-RcAction $res[0].Named.Act2.Tag
Assert-Eq $script:Opened[0] ('folder:' + $td) 'klasör açılır'
Assert-Eq $script:Opened[1] ('path:' + $rep) 'rapor açılır'
# kısmi başarı ve başarısızlık
Complete-RcRecover @{ Ok = $true; Error = ''; Dir = $td; Done = 1; Failed = 2; Bytes = [double]100; Report = ''; Canceled = $true; Results = @() }
$res2 = @(Get-RowsOf $ui.sl_List | Where-Object { $_.Vars.Title -match '^Kurtarma tamamlandı' })
Assert-True ($res2[0].Vars.Detail -match '2 dosya kurtarılamadı' -and $res2[0].Vars.Detail -match 'yarıda kesildi' -and $res2[0].Vars.BrCol -eq 'BrWarn') 'kısmi sonuç uyarı rengi'
Assert-Eq $res2[0].Vars.Btn2 '' 'rapor yoksa düğme yok'
Complete-RcRecover @{ Ok = $false; Error = 'Kurtarma klasörüne yazılamadı: izin yok'; Dir = ''; Done = 0; Failed = 0; Bytes = [double]0; Report = ''; Canceled = $false; Results = @() }
$res3 = @(Get-RowsOf $ui.sl_List | Where-Object { $_.Vars.Title -match 'Hiçbir dosya kurtarılamadı' })
Assert-True ($res3.Count -eq 1 -and $res3[0].Vars.Detail -match 'izin yok' -and $res3[0].Vars.BrCol -eq 'BrBad') 'başarısız sonuç'
Assert-True ((Get-LastToast).K -eq 'bad') 'başarısızlık bildirimi'
Complete-RcRecover $null
Assert-True ((Get-LastToast).K -eq 'bad') 'boş sonuç hata sayılır'
Remove-Item -LiteralPath $td -Recurse -Force

# 8h) tür süzgeci ve arama
Reset-Fake
$script:RcLastRun = $null
Select-ComboKey $ui.sl_RcType 'img' | Out-Null
Select-RcGroup
Assert-Eq $script:RcGroup 'img' 'tür seçildi'
$rows2 = @(Get-RowsOf $ui.sl_List | Where-Object { $_.Tag -is [hashtable] -and $_.Tag.ContainsKey('Idx') })
Assert-Eq $rows2.Count 2 'yalnızca resimler'
$ui.sl_RcFind.Text = 'tatil'
Render-RcBody
$rows3 = @(Get-RowsOf $ui.sl_List | Where-Object { $_.Tag -is [hashtable] -and $_.Tag.ContainsKey('Idx') })
Assert-Eq $rows3.Count 1 'arama sonucu'
$ui.sl_RcFind.Text = 'olmayan-ad'
Render-RcBody
Assert-True ($null -ne (Find-NoteLike $ui.sl_List 'süzgece uyan dosya yok')) 'eşleşme yoksa not'
$ui.sl_RcFind.Text = ''
Select-ComboKey $ui.sl_RcType 'all' | Out-Null
Select-RcGroup

# 8i) hepsini seç / temizle (şansı sıfır olanlar listelenmediği için seçilmez)
Reset-Fake
Render-RcBody
Set-RowChecks $ui.sl_List { param($d) $true }
Update-RcFoot
Assert-True ($ui.sl_Foot.Text -match 'Seçili: 4 dosya') 'hepsini seç'
Set-RowChecks $ui.sl_List { param($d) $false }
Update-RcFoot
Assert-True ($ui.sl_Foot.Text -match 'Seçili: 0 dosya') 'seçimi temizle'

# 8j) sürücü değişince sonuçlar silinir
Reset-Fake
$script:RcSelKey = 'E:'
Select-ComboKey $ui.sl_RcVol 'E:' | Out-Null
Select-RcVolume
Assert-True ($null -eq $script:RcMeta -and $script:RcItems.Count -eq 0) 'başka sürücüye geçince sonuçlar temizlenir'
Assert-True ($null -ne (Find-NoteLike $ui.sl_List 'yalnızca okur')) 'giriş metni yeniden çizilir'

# 8k) tarama hatası
Reset-Fake
Start-RcScan 'Both'
$c1 = $script:Asyncs[0]
Assert-Eq $c1.Params.Mode 'Both' 'derin tarama kipi'
Assert-True ($c1.Label -match 'Derin') 'derin tarama etiketi'
& $c1.OnDone @{ Ok = $false; Error = 'Sürücüye erişim engellendi. Multimizer uygulamasını yönetici olarak çalıştırın.' }
Assert-True ($script:RcScanError -match 'erişim engellendi') 'hata kaydedildi'
Assert-True ($null -ne (Find-NoteLike $ui.sl_List 'erişim engellendi')) 'hata ekranda'
Assert-True ((Get-LastToast).K -eq 'bad') 'hata bildirimi'
& $c1.OnDone $null
Assert-True ($script:RcScanError -match 'yapılamadı') 'boş sonuç hata sayılır'

# 8l) hiçbir şey bulunamadı
Reset-Fake
Start-RcScan 'Quick'
& $script:Asyncs[0].OnDone @{ Ok = $true; Error = ''; Fs = 'exFAT'; ClusterSize = 32768; VolumeBytes = [double]32GB; FreeBytes = [double]10GB; Items = @(); Truncated = $false; Canceled = $false; Mode = 'Quick'; Partitions = 1
    Stats = @{ Records = 0; Deleted = 0; Skipped = 0; ReadErrors = 0; FromTable = 0; Carved = 0 } }
Assert-True ((Get-LastToast).T -match 'bulunamadı') 'sonuç yok bildirimi'
Assert-True ($null -ne (Find-NoteLike $ui.sl_List 'Silinmiş dosya bulunamadı')) 'sonuç yok notu'

# 8m) disk imajı: seçilince bölüm düzeni okunur
Reset-Fake
$script:PickFile = ''
Select-RcImage
Assert-Eq $script:RcImage '' 'iptal edilirse imaj seçilmez'
Assert-Eq $script:Asyncs.Count 0 'iptal edilirse bölümler okunmaz'
$script:PickFile = 'E:\yedek\disk.img'
Select-RcImage
Assert-Eq $script:RcImage 'E:\yedek\disk.img' 'imaj kaydedildi'
Assert-Eq (Get-ComboKey $ui.sl_RcVol) 'IMG:0' 'imaj seçili'
Assert-Eq $script:RcSource 'E:\yedek\disk.img' 'imaj kaynak oldu'
Assert-Eq $script:RcSourceKind 'Image' 'imaj türü'
Assert-True ($null -ne (Find-NoteLike $ui.sl_List 'Disk imajı salt okunur')) 'imaj notu'
Assert-True ($null -eq (Find-NoteLike $ui.sl_List 'Windows sürücüsünü')) 'imajda sistem sürücüsü uyarısı yok'
Assert-Eq $script:Asyncs.Count 1 'bölüm düzenini okuma işi başladı'
$pj = $script:Asyncs[0]
Assert-True ($pj.Entry -eq 'Job_RecoverParts' -and $pj.Params.Source -eq 'E:\yedek\disk.img' -and $pj.Label -match 'Bölümler') 'bölüm okuma parametreleri'
Assert-Eq $script:RcPartPend 'E:\yedek\disk.img' 'bölüm okuması bekleniyor'
& $pj.OnDone @{ Ok = $true; Error = ''; Parts = @(@{ Index = 0; Start = [double]1048576; Length = [double]1GB; Fs = 'NTFS'; Kind = 'GPT' }, @{ Index = 1; Start = [double]1074790400; Length = [double]1GB; Fs = 'ext4'; Kind = 'GPT' }) }
Assert-Eq $script:RcPartPend '' 'bölüm okuması bitti'
Assert-Eq $ui.sl_RcVol.Items.Count 7 'iki imaj bölümü ve tüm imaj satırı seçicide'
Assert-Eq (Get-ComboKey $ui.sl_RcVol) 'IMG:0' 'seçim korundu'
Assert-True ($ui.sl_RcVol.Items[4].Name -match 'bölüm 1/2' -and $ui.sl_RcVol.Items[4].Name -match 'NTFS' -and $ui.sl_RcVol.Items[5].Name -match 'ext4') 'bölüm adları dosya sistemini gösterir'
Reset-Fake
$script:IsAdmin = $false
Start-RcScan 'Quick'
Assert-Eq $script:Asyncs.Count 1 'imaj için yönetici gerekmez'
$script:IsAdmin = $true
& $script:Asyncs[0].OnDone @{ Ok = $true; Error = ''; Fs = 'NTFS'; Method = 'mft'; Raw = $false; Note = ''; ClusterSize = 4096; VolumeBytes = [double]1GB; FreeBytes = [double]1MB; Items = @((New-It 'mft' 'x.txt' '' 10 100)); Truncated = $false; Canceled = $false; Mode = 'Quick'; Partitions = 2
    Stats = @{ Records = 10; Deleted = 1; Skipped = 0; ReadErrors = 0; FromTable = 1; Carved = 0 } }
Assert-Eq $ui.sl_RcVol.Items.Count 7 'tarama sonrası seçici aynı'
Assert-Eq (Get-ComboKey $ui.sl_RcVol) 'IMG:0' 'tarama sonrası seçim korundu'
Assert-True ($null -ne $script:RcMeta -and $script:RcItems.Count -eq 1) 'tarama sonuçları korunur'
Assert-Eq $script:RcMeta.Method 'mft' 'yöntem kaydedildi'
Select-ComboKey $ui.sl_RcVol 'IMG:1' | Out-Null
Select-RcVolume
Assert-Eq $script:RcPart 1 'ikinci bölüm seçildi'
Assert-True ($null -eq $script:RcMeta) 'bölüm değişince sonuçlar temizlenir'
Start-RcScan 'Quick'
Assert-Eq $script:Asyncs[1].Params.Partition 1 'bölüm numarası işe geçer'
# tüm imaj: bölüm düzeni yok sayılır
Select-ComboKey $ui.sl_RcVol 'IMG:all' | Out-Null
Select-RcVolume
Assert-Eq $script:RcPart -1 'tüm imaj: bölüm -1'
Assert-True ($null -ne (Find-NoteLike $ui.sl_List 'Tüm disk seçildi')) 'tüm imaj uyarısı'
Start-RcScan 'Quick'
Assert-Eq $script:Asyncs[2].Params.Partition -1 'tüm imaj taraması -1 ile başlar'
Select-ComboKey $ui.sl_RcVol 'IMG:1' | Out-Null
Select-RcVolume
# imaj kaynağında hedef herhangi bir sürücüde olabilir
$script:RcMeta = @{ Source = 'E:\yedek\disk.img'; Part = 1; Fs = 'NTFS'; ClusterSize = 4096; VolumeBytes = [double]1GB; FreeBytes = [double]1MB; Mode = 'Quick'; Truncated = $false; Canceled = $false; Stats = @{ Records = 1; Deleted = 1; Skipped = 0; ReadErrors = 0; FromTable = 1; Carved = 0 }; Partitions = 2 }
$script:RcItems = @((New-It 'mft' 'x.txt' '' 10 100))
$script:RcDest = ''
Render-RcBody
$rowsI = @(Get-RowsOf $ui.sl_List | Where-Object { $_.Tag -is [hashtable] -and $_.Tag.ContainsKey('Idx') })
$rowsI[0].Named.Chk.IsChecked = $true
Reset-Fake
$script:PickFolder = 'E:\Kurtarilan'
Start-RcRecover
Assert-Eq $script:Confirms.Count 1 'imajdan kurtarma aynı sürücüye yazılabilir'
# bölüm okuma başarısız
Reset-Fake
$script:RcPartCache = @{}
$script:PickFile = 'E:\yedek\bozuk.img'
Select-RcImage
& $script:Asyncs[0].OnDone @{ Ok = $false; Error = 'Kaynak okunamadı (boş ya da erişilemiyor).'; Parts = @() }
Assert-True ($script:RcScanError -match 'okunamadı') 'bölüm okuma hatası kaydedildi'
Assert-True ((Get-LastToast).K -eq 'bad') 'bölüm okuma hatası bildirimi'
Assert-True ($null -ne (Find-NoteLike $ui.sl_List 'okunamadı')) 'bölüm okuma hatası ekranda'
Assert-Eq $ui.sl_RcVol.Items.Count 5 'bölümleri okunamayan imaj tek satır'
& $script:Asyncs[0].OnDone $null
Assert-Eq $script:RcPartPend '' 'tekrarlanan tamamlanma zararsız'
$script:RcScanError = ''
$script:RcImage = 'E:\yedek\disk.img'
$script:RcSelKey = 'IMG:0'
Reset-RcResults

# 8o) fiziksel disk ve USB bellek: seçilince bölümleri okunur
Reset-Fake
$script:RcImage = ''
$script:RcPartCache = @{}
$script:RcSelKey = ''
Reset-RcResults
$script:SlDisks = @{ Ok = $true; Sys = @{ OsDrive = 'C:'; IsAdmin = $true }; Disks = $disks; Phys = $phys }
Render-SlRecover
Assert-Eq $ui.sl_RcVol.Items.Count 7 'seçici: 4 sürücü ve 3 fiziksel disk (boyutu sıfır olan yok)'
Assert-Eq (Get-ComboKey $ui.sl_RcVol) 'C:' 'varsayılan yine sistem sürücüsü'
$script:RcDest = 'E:\Kurtarilan'
Select-ComboKey $ui.sl_RcVol 'PD:1' | Out-Null
Select-RcVolume
Assert-Eq $script:RcDest '' 'taranacak diskteki eski kurtarma klasörü unutulur'
Assert-Eq $script:RcSourceKind 'Disk' 'kaynak türü: disk'
Assert-Eq $script:RcSource 'PhysicalDrive1' 'kaynak: fiziksel disk'
Assert-Eq $script:RcDisk 1 'disk numarası'
Assert-True ($null -ne (Find-NoteLike $ui.sl_List 'Fiziksel disk salt okunur')) 'fiziksel disk notu'
Assert-True ($null -eq (Find-NoteLike $ui.sl_List 'kurulu olduğu diski tarıyorsunuz')) 'USB diskte sistem diski uyarısı yok'
Assert-Eq $script:Asyncs.Count 1 'diskin bölümlerini okuma işi başladı'
$dj = $script:Asyncs[0]
Assert-True ($dj.Entry -eq 'Job_RecoverParts' -and $dj.Params.Source -eq 'PhysicalDrive1') 'bölüm okuma parametreleri (disk)'
Select-RcVolume
Assert-Eq $script:Asyncs.Count 1 'okuma sürerken ikinci iş başlamaz'
Start-RcScan 'Quick'
Assert-Eq $script:Asyncs.Count 1 'bölümler okunmadan tarama başlamaz'
& $dj.OnDone @{ Ok = $true; Error = ''; Parts = @(@{ Index = 0; Start = [double]1048576; Length = [double]14GB; Fs = 'exFAT'; Kind = 'MBR:07' }, @{ Index = 1; Start = [double]15000000000; Length = [double]15GB; Fs = 'ext4'; Kind = 'MBR:83' }) }
Assert-Eq (Get-ComboKey $ui.sl_RcVol) 'PD:1:0' 'ilk bölüm seçildi'
Assert-Eq $ui.sl_RcVol.Items.Count 9 'seçici: bölümler eklendi'
Assert-Eq $script:RcPart 0 'bölüm numarası'
Assert-Eq (@(Get-RcSelectedLetters) -join ',') 'E:' 'seçili diskteki harfler'
Select-ComboKey $ui.sl_RcVol 'PD:1:1' | Out-Null
Select-RcVolume
Assert-Eq $script:RcPart 1 'ikinci bölüm (ext4) seçildi'
$script:RcDest = 'D:\Kurtarilan'
Select-ComboKey $ui.sl_RcVol 'PD:1:0' | Out-Null
Select-RcVolume
Assert-Eq $script:RcDest 'D:\Kurtarilan' 'başka diskteki klasör korunur'
Select-ComboKey $ui.sl_RcVol 'PD:1:1' | Out-Null
Select-RcVolume
$script:RcDest = ''
Reset-Fake
Start-RcScan 'Quick'
Assert-Eq $script:Asyncs.Count 1 'bölüm taraması başladı'
$sj = $script:Asyncs[0]
Assert-True ($sj.Entry -eq 'Job_RecoverScan' -and $sj.Params.Source -eq 'PhysicalDrive1' -and $sj.Params.Partition -eq 1 -and $sj.Params.Mode -eq 'Quick') 'disk bölümü tarama parametreleri'
& $sj.OnDone @{ Ok = $true; Error = ''; Fs = 'ext4'; Method = 'free'; Raw = $false; Note = ''; ClusterSize = 4096; VolumeBytes = [double]15GB; FreeBytes = [double]5GB; Items = @((New-It 'carve' 'kurtarilan_00001.jpg' '' 7000 85)); Truncated = $false; Canceled = $false; Mode = 'Quick'; Partitions = 2
    Stats = @{ Records = 0; Deleted = 0; Skipped = 0; ReadErrors = 0; FromTable = 0; Carved = 1 } }
Assert-Eq $script:RcMeta.Source 'PhysicalDrive1' 'meta kaynağı disk'
Assert-Eq $script:RcMeta.Method 'free' 'meta yöntemi'
Assert-True ($null -ne (Find-NoteLike $ui.sl_List 'boş alanda imza taraması')) 'ext özeti'
Assert-Eq $ui.sl_RcVol.Items.Count 9 'tarama sonrası seçici aynı'
# kurtarma klasörü taranan diskte olamaz
Reset-Fake
$script:PickFolder = 'E:\Kurtarilan'
Assert-Eq (Select-RcDest) '' 'taranan diskteki klasör reddedilir'
Assert-True ((Get-LastToast).T -match 'taranan diskte \(Disk 1\)') 'taranan disk bildirimi'
Assert-Eq $script:RcDest '' 'reddedilen hedef kaydedilmez'
$script:PickFolder = 'D:\Kurtarilan'
Assert-Eq (Select-RcDest) 'D:\Kurtarilan' 'başka diskteki klasör kabul edilir'
$script:RcDest = ''
# tüm disk
Select-ComboKey $ui.sl_RcVol 'PD:1:all' | Out-Null
Select-RcVolume
Assert-Eq $script:RcPart -1 'tüm disk: bölüm -1'
Assert-True ($null -ne (Find-NoteLike $ui.sl_List 'Tüm disk seçildi')) 'tüm disk uyarısı'
Reset-Fake
Start-RcScan 'Quick'
Assert-Eq $script:Asyncs[0].Params.Partition -1 'tüm disk taraması -1 ile başlar'
# yönetici değilse disk taranmaz ve bölümler okunmaz
Reset-Fake
$script:IsAdmin = $false
Start-RcScan 'Quick'
Assert-Eq $script:Asyncs.Count 0 'yönetici değilse disk taranmaz'
Assert-True ((Get-LastToast).T -match 'yönetici') 'disk için yönetici bildirimi'
Select-ComboKey $ui.sl_RcVol 'PD:3' | Out-Null
Select-RcVolume
Assert-Eq $script:Asyncs.Count 0 'yönetici değilse bölümler okunmaz'
Assert-True ($script:RcScanError -match 'yönetici') 'yönetici hatası ekranda'
Assert-True ($null -ne (Find-NoteLike $ui.sl_List 'yönetici')) 'yönetici notu çizilir'
$script:IsAdmin = $true
$script:RcScanError = ''
# harfsiz disk: bölüm tablosu yok, tek satır
Reset-Fake
Select-ComboKey $ui.sl_RcVol 'PD:3' | Out-Null
Select-RcVolume
Assert-Eq $script:Asyncs.Count 1 'harfsiz disk için bölümler okunur'
& $script:Asyncs[0].OnDone @{ Ok = $true; Error = ''; Parts = @() }
Assert-Eq (Get-ComboKey $ui.sl_RcVol) 'PD:3:0' 'bölüm düzeni yoksa tek satır seçilir'
Assert-Eq $script:RcPart 0 'bölüm 0'
Assert-Eq (@(Get-RcSelectedLetters).Count) 0 'harfsiz diskte harf yok'
Reset-Fake
Start-RcScan 'Both'
Assert-True ($script:Asyncs[0].Params.Source -eq 'PhysicalDrive3' -and $script:Asyncs[0].Params.Partition -eq 0 -and $script:Asyncs[0].Params.Mode -eq 'Both') 'bölüm tablosu olmayan disk taranır'
# BitLocker bölümü
Reset-Fake
$script:RcPartCache['PhysicalDrive1'] = @{ Ok = $true; Error = ''; Parts = @(@{ Index = 0; Start = [double]1048576; Length = [double]14GB; Fs = 'BITLOCKER'; Kind = 'MBR:07' }, @{ Index = 1; Start = [double]15000000000; Length = [double]15GB; Fs = 'ext4'; Kind = 'MBR:83' }) }
$script:RcSelKey = 'PD:1:0'
Update-RcVolumeCombo
Select-ComboKey $ui.sl_RcVol 'PD:1:0' | Out-Null
Select-RcVolume
Assert-True ($null -ne (Find-NoteLike $ui.sl_List 'Bu bölüm BitLocker ile kilitli')) 'kilitli bölüm uyarısı'
Start-RcScan 'Quick'
Assert-Eq $script:Asyncs.Count 0 'kilitli bölüm taranmaz'
Assert-True ((Get-LastToast).T -match 'bölüm BitLocker ile kilitli') 'kilitli bölüm bildirimi'
# bölümleri okunamayan disk yeniden denenebilir
Reset-Fake
$script:RcPartCache = @{}
Select-ComboKey $ui.sl_RcVol 'PD:0' | Out-Null
Select-RcVolume
Assert-Eq $script:Asyncs.Count 1 'sistem diskinin bölümleri okunur'
Assert-True ($null -ne (Find-NoteLike $ui.sl_List 'kurulu olduğu diski tarıyorsunuz')) 'sistem diski uyarısı'
& $script:Asyncs[0].OnDone @{ Ok = $false; Error = 'Disk bulunamadı ya da hazır değil: Disk 0'; Parts = @() }
Assert-Eq (Get-ComboKey $ui.sl_RcVol) 'PD:0' 'okunamayan diskte seçim aynı kalır'
Assert-True ($ui.sl_RcVol.Items[4].Name -match 'bölümler okunamadı') 'okunamadı etiketi'
Assert-True ($null -ne (Find-NoteLike $ui.sl_List 'Disk bulunamadı')) 'okuma hatası ekranda'
Reset-Fake
Start-RcScan 'Quick'
Assert-Eq $script:Asyncs.Count 1 'tarama düğmesi bölümleri yeniden okumayı dener'
Assert-Eq $script:Asyncs[0].Entry 'Job_RecoverParts' 'yeniden deneme bölüm işidir'
# disk listesi yenilenince fiziksel disk önbelleği silinir, imaj önbelleği kalır
$script:RcPartCache = @{ 'PhysicalDrive1' = @{ Ok = $true; Error = ''; Parts = @() }; 'E:\yedek\disk.img' = @{ Ok = $true; Error = ''; Parts = @() } }
$script:SlDisks = $null
Reset-Fake
Render-SlRecover
Assert-True (-not $script:RcPartCache.ContainsKey('PhysicalDrive1') -and $script:RcPartCache.ContainsKey('E:\yedek\disk.img')) 'yenilemede yalnızca disk önbelleği silinir'
Assert-Eq $script:Loads 1 'yenilemede sürücü listesi yeniden istenir'
$script:SlDisks = @{ Ok = $true; Sys = @{ OsDrive = 'C:'; IsAdmin = $true }; Disks = $disks; Phys = $phys }
$script:RcPartCache = @{}

# 8n) sürücü listesi okunamadıysa yine de imaj açılabilir
Reset-Fake
$script:SlDisks = @{ Failed = $true }
$script:RcSelKey = ''
$script:RcImage = ''
Reset-RcResults
Render-SlRecover
Assert-Eq $ui.sl_RcVol.Items.Count 0 'sürücü yok'
Assert-True ($null -ne (Find-NoteLike $ui.sl_List 'okunamadı')) 'okunamadı notu'
Start-RcScan 'Quick'
Assert-True ((Get-LastToast).T -match 'seçin') 'kaynak yoksa uyarı'
Assert-Eq $script:Asyncs.Count 0 'kaynak yokken iş başlamaz'

Show-Result
