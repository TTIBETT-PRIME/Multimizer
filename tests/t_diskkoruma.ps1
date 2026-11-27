. "$PSScriptRoot/lib.ps1"
# Disk koruma eklentisi (Eklenti\DiskKoruma.ps1): BitLocker komutları sahte işlevlerle değiştirilir; gerçek sürücüye hiçbir şey yazılmaz.
Import-Fn 'Get-BlDriveName', 'New-BlResult', 'Test-BlDirWritable', 'Get-BlFreeName', 'Get-BlKeysOf', 'Save-BlKeyFile', 'Undo-BlEnable', 'Invoke-BlEnable',
    'Invoke-BlAutoUnlock', 'Invoke-BlSimple', 'Job_BlOp',
    'Get-BlState', 'Test-BlEnablePlan', 'Get-BlKeyFileName', 'Format-BlKeyFile', 'Get-BlScope', 'Get-BlScopeText', 'Test-BlKeyDir'

# ---- sahte ortam ----
$script:Logs = New-Object System.Collections.ArrayList
$script:Calls = New-Object System.Collections.ArrayList
$script:Throw = @{}
function Write-WhLog([string]$Message, [string]$Level = 'INFO') { [void]$script:Logs.Add($Level + ': ' + $Message) }
function Add-Call([string]$Text) { [void]$script:Calls.Add($Text) }
function Fmt-Bound($Bound) {
    $parts = @()
    foreach ($k in @($Bound.Keys | Sort-Object)) { if ($k -ne 'ErrorAction') { $parts += ($k + '=' + [string]$Bound[$k]) } }
    return ($parts -join ' ')
}
function Enable-BitLocker {
    [CmdletBinding()] param([string]$MountPoint, [string]$EncryptionMethod, [switch]$UsedSpaceOnly, [switch]$TpmProtector, [switch]$RecoveryPasswordProtector)
    Add-Call ('Enable-BitLocker ' + (Fmt-Bound $PSBoundParameters))
    if ($script:Throw.ContainsKey('Enable-BitLocker')) { throw $script:Throw['Enable-BitLocker'] }
}
function Add-BitLockerKeyProtector {
    [CmdletBinding()] param([string]$MountPoint, [switch]$RecoveryPasswordProtector)
    Add-Call ('Add-BitLockerKeyProtector ' + (Fmt-Bound $PSBoundParameters))
    if ($script:Throw.ContainsKey('Add-BitLockerKeyProtector')) { throw $script:Throw['Add-BitLockerKeyProtector'] }
}
function Disable-BitLocker {
    [CmdletBinding()] param([string]$MountPoint)
    Add-Call ('Disable-BitLocker ' + (Fmt-Bound $PSBoundParameters))
    if ($script:Throw.ContainsKey('Disable-BitLocker')) { throw $script:Throw['Disable-BitLocker'] }
}
function Suspend-BitLocker {
    [CmdletBinding()] param([string]$MountPoint, [int]$RebootCount)
    Add-Call ('Suspend-BitLocker ' + (Fmt-Bound $PSBoundParameters))
    if ($script:Throw.ContainsKey('Suspend-BitLocker')) { throw $script:Throw['Suspend-BitLocker'] }
}
function Lock-BitLocker {
    [CmdletBinding()] param([string]$MountPoint, [switch]$ForceDismount)
    Add-Call ('Lock-BitLocker ' + (Fmt-Bound $PSBoundParameters))
    if ($script:Throw.ContainsKey('Lock-BitLocker')) { throw $script:Throw['Lock-BitLocker'] }
}
function Enable-BitLockerAutoUnlock {
    [CmdletBinding()] param([string]$MountPoint)
    Add-Call ('Enable-BitLockerAutoUnlock ' + (Fmt-Bound $PSBoundParameters))
    if ($script:Throw.ContainsKey('Enable-BitLockerAutoUnlock')) { throw $script:Throw['Enable-BitLockerAutoUnlock'] }
}

$secret = '111111-222222-333333-444444-555555-666666-777777-888888'
$guid = '{5E1A1B2C-0000-4000-8000-123456789ABC}'
$script:KeyResult = @{ Ok = $true; Keys = @(@{ Id = $guid; Password = $secret }) }
function Job_BitLockerKey($P) { return @{ Ok = $script:KeyResult.Ok; Drive = [string]$P.Drive; Keys = @($script:KeyResult.Keys) } }

$script:Env = $null
$script:Disks = @()
function Get-SlvEnv { return $script:Env }
function Get-SlvDisks { return , $script:Disks }

$script:KeyDirVerdict = ''
function Test-BlKeyDir([string]$Dir, [string]$Drive) { return $script:KeyDirVerdict }

# gerçek biçimlendirici: denetimde bozulabilsin diye sarmalanır
$script:RealFormat = (Get-Item 'function:Format-BlKeyFile').ScriptBlock
$script:BadFormat = $false
function Format-BlKeyFile([string]$Drive, $Keys) { if ($script:BadFormat) { return 'bos dosya' } return (& $script:RealFormat $Drive $Keys) }

function New-Disk([string]$Drive, [string]$Type, [string]$Media, [int]$Conv = 0, [int]$Prot = 0, [string]$Fs = 'NTFS') {
    $bl = @{ Drive = $Drive; Protection = $Prot; Conversion = $Conv; Percent = 0; Types = @(); RecoveryIds = @(); HasRecovery = $false }
    return @{ Drive = $Drive; Letter = $Drive.Substring(0, 1); Label = ''; FileSystem = $Fs; DriveType = $Type; Size = [double]500GB; Free = [double]200GB; DiskNumber = 0; Media = $Media; Bus = ''; DiskName = ''; DiskHealth = 'Healthy'; Dirty = $false; Bl = $bl }
}
function Reset-World {
    $script:Logs.Clear(); $script:Calls.Clear(); $script:Throw = @{}; $script:BadFormat = $false; $script:KeyDirVerdict = ''
    $script:KeyResult = @{ Ok = $true; Keys = @(@{ Id = $guid; Password = $secret }) }
    $script:Env = @{ IsAdmin = $true; Edition = 'Pro'; Win11 = $true; TpmPresent = $true; TpmReady = $true; SecureBoot = $true; OsDrive = 'C:'; CanEnable = $true; OnBattery = $false; HasBattery = $false; OsBlState = '' }
    $script:Disks = @((New-Disk 'C:' 'Fixed' 'SSD'), (New-Disk 'D:' 'Fixed' 'HDD'), (New-Disk 'E:' 'Removable' '' 0 0 'exFAT'), (New-Disk 'F:' 'Fixed' 'SSD'))
}
function Calls-Of([string]$Prefix) { return , @($script:Calls | Where-Object { $_.StartsWith($Prefix) }) }
function Logs-HaveSecret { foreach ($l in $script:Logs) { if ($l.Contains($secret) -or $l.Contains($guid)) { return $true } } return $false }

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('mmdk' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $tmp | Out-Null
$kd = Join-Path $tmp 'anahtar'
$plainFile = Join-Path $tmp 'dosya.txt'
Set-Content -LiteralPath $plainFile -Value 'x'

# =====================================================================
#  1) yardımcılar
# =====================================================================
Assert-Eq (Get-BlDriveName 'c') 'C:' 'harf tek başına: C:'
Assert-Eq (Get-BlDriveName ' d: ') 'D:' 'boşluk kırpılır'
Assert-Eq (Get-BlDriveName 'E:') 'E:' 'olduğu gibi'
Assert-Eq (Get-BlDriveName 'C:\x') '' 'yol sürücü değildir'
Assert-Eq (Get-BlDriveName '') '' 'boş'
Assert-Eq (Get-BlDriveName '1:') '' 'rakam sürücü değildir'
$nr = New-BlResult 'Lock' 'D:'
Assert-True ($nr.Ok -eq $false -and $nr.Op -eq 'Lock' -and $nr.Drive -eq 'D:' -and $nr.NeedsReboot -eq $false) 'boş sonuç hazır'

Assert-Eq (Test-BlDirWritable $kd) '' 'olmayan klasör oluşturulup yazılabilir sayılır'
Assert-True (Test-Path -LiteralPath $kd -PathType Container) 'klasör oluşturuldu'
Assert-Eq @(Get-ChildItem -LiteralPath $kd -Force).Count 0 'deneme dosyası silindi'
$under = Join-Path $plainFile 'alt'
Assert-True ((Test-BlDirWritable $under).StartsWith('Klasöre yazılamadı')) 'dosyanın altı yazılamaz'

$f1 = Join-Path $tmp 'ad.txt'
Assert-Eq (Get-BlFreeName $f1) $f1 'boş ad olduğu gibi'
Set-Content -LiteralPath $f1 -Value 'a'
Assert-Eq (Get-BlFreeName $f1) (Join-Path $tmp 'ad (2).txt') 'dolu ad: (2)'
Set-Content -LiteralPath (Join-Path $tmp 'ad (2).txt') -Value 'b'
Assert-Eq (Get-BlFreeName $f1) (Join-Path $tmp 'ad (3).txt') 'dolu ad: (3)'

# anahtar dosyası
Reset-World
$keys = @(@{ Id = $guid; Password = $secret })
$sv = Save-BlKeyFile 'D:' $kd $keys
Assert-True ($sv.Ok -eq $true) 'anahtar dosyası yazıldı'
Assert-True (Test-Path -LiteralPath $sv.Path) 'dosya var'
$txt = [System.IO.File]::ReadAllText($sv.Path)
Assert-True ($txt.Contains($secret) -and $txt.Contains($guid)) 'dosyada anahtar ve kimlik var'
$bytes = [System.IO.File]::ReadAllBytes($sv.Path)
Assert-True ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) 'UTF-8 imzalı (Not Defteri doğru açar)'
Assert-True ((Split-Path -Leaf $sv.Path) -like 'BitLocker-kurtarma-D-*.txt') 'dosya adı sürücüyü içerir'
$sv2 = Save-BlKeyFile 'D:' $kd $keys
Assert-True ($sv2.Ok -eq $true -and $sv2.Path -ne $sv.Path) 'ikinci kayıt öncekinin üzerine yazmaz'
Assert-True (Test-Path -LiteralPath $sv.Path) 'önceki dosya duruyor'
$svEmpty = Save-BlKeyFile 'D:' $kd @()
Assert-True ($svEmpty.Ok -eq $false -and $svEmpty.Error -ne '') 'anahtarsız kayıt reddedilir'
$before = @(Get-ChildItem -LiteralPath $kd -Force).Count
$script:BadFormat = $true
$svBad = Save-BlKeyFile 'D:' $kd $keys
$script:BadFormat = $false
Assert-True ($svBad.Ok -eq $false -and $svBad.Error -match 'doğrulanamadı') 'içerik doğrulanamazsa başarısız'
Assert-Eq @(Get-ChildItem -LiteralPath $kd -Force).Count $before 'başarısız kayıttan dosya kalmaz'
$svUn = Save-BlKeyFile 'D:' $under $keys
Assert-True ($svUn.Ok -eq $false -and $svUn.Error -ne '') 'yazılamayan klasör hata verir'

Reset-World
$kk = Get-BlKeysOf 'D:'
Assert-Eq @($kk).Count 1 'anahtar okundu'
$script:KeyResult = @{ Ok = $false; Keys = @() }
$kk = Get-BlKeysOf 'D:'
Assert-Eq @($kk).Count 0 'okunamayınca boş dizi'
Reset-World
Assert-True ((Undo-BlEnable 'D:') -eq $true) 'geri alma başarılı'
Assert-Eq (Calls-Of 'Disable-BitLocker').Count 1 'geri alma Disable-BitLocker çağırır'
Assert-True ((Calls-Of 'Disable-BitLocker')[0] -eq 'Disable-BitLocker MountPoint=D:') 'geri alma yalnızca ilgili sürücüde'
$script:Throw['Disable-BitLocker'] = 'olmadı'
Assert-True ((Undo-BlEnable 'D:') -eq $false) 'geri alma başarısızsa false'

# =====================================================================
#  2) şifrelemeyi başlat: veri sürücüsü
# =====================================================================
Reset-World
$r = Invoke-BlEnable @{ Drive = 'D:'; KeyDir = $kd }
Assert-True ($r.Ok -eq $true) ('HDD veri sürücüsü: başarılı ' + $r.Error)
$en = Calls-Of 'Enable-BitLocker'
Assert-Eq $en.Count 1 'bir kez etkinleştirildi'
Assert-Eq $en[0] 'Enable-BitLocker EncryptionMethod=XtsAes256 MountPoint=D: RecoveryPasswordProtector=True' 'HDD: tüm sürücü, kurtarma parolası koruyucusu'
Assert-Eq (Calls-Of 'Add-BitLockerKeyProtector').Count 0 'veri sürücüsünde ayrı koruyucu eklenmez'
Assert-True (Test-Path -LiteralPath $r.KeyPath) 'anahtar dosyası yazıldı'
Assert-True (([System.IO.File]::ReadAllText($r.KeyPath)).Contains($secret)) 'dosyada anahtar var'
Assert-True ($r.Message.Contains($r.KeyPath)) 'ileti dosya yolunu söyler'
Assert-True ($r.NeedsReboot -eq $false) 'veri sürücüsü yeniden başlatma istemez'
Assert-Eq (Calls-Of 'Enable-BitLockerAutoUnlock').Count 0 'sistem sürücüsü şifresizken otomatik açma denenmez'
Assert-True ($r.Message -match 'Otomatik açma etkinleştirilemedi' -and $r.Message -match 'sistem sürücüsü şifreli değil') 'otomatik açma neden olmadı söylenir'
Assert-True (-not (Logs-HaveSecret)) 'günlükte anahtar yok'

Reset-World
$script:Disks = @((New-Disk 'C:' 'Fixed' 'SSD' 1 1), (New-Disk 'D:' 'Fixed' 'SSD'))
$r = Invoke-BlEnable @{ Drive = 'D:'; KeyDir = $kd }
Assert-True ($r.Ok -eq $true) 'SSD veri sürücüsü: başarılı'
Assert-Eq (Calls-Of 'Enable-BitLocker')[0] 'Enable-BitLocker EncryptionMethod=XtsAes256 MountPoint=D: RecoveryPasswordProtector=True UsedSpaceOnly=True' 'SSD: yalnızca kullanılan alan'
Assert-Eq (Calls-Of 'Enable-BitLockerAutoUnlock').Count 1 'sistem sürücüsü şifreliyken otomatik açma denenir'
Assert-Eq (Calls-Of 'Enable-BitLockerAutoUnlock')[0] 'Enable-BitLockerAutoUnlock MountPoint=D:' 'otomatik açma ilgili sürücüde'
Assert-True ($r.Message -match 'kendiliğinden açılacak') 'ileti otomatik açmayı söyler'

Reset-World
$script:Disks = @((New-Disk 'C:' 'Fixed' 'SSD' 2 1), (New-Disk 'D:' 'Fixed' 'SSD'))
$r = Invoke-BlEnable @{ Drive = 'D:'; KeyDir = $kd }
Assert-Eq (Calls-Of 'Enable-BitLockerAutoUnlock').Count 1 'sistem sürücüsü şifreleniyorken de otomatik açma denenir'

Reset-World
$script:Disks = @((New-Disk 'C:' 'Fixed' 'SSD' 1 1), (New-Disk 'D:' 'Fixed' 'SSD'))
$script:Throw['Enable-BitLockerAutoUnlock'] = 'Windows reddetti'
$r = Invoke-BlEnable @{ Drive = 'D:'; KeyDir = $kd }
Assert-True ($r.Ok -eq $true) 'otomatik açma olmazsa şifreleme yine başarılı'
Assert-True ($r.Message -match 'Windows reddetti') 'otomatik açma hatası iletide'
Assert-Eq (Calls-Of 'Disable-BitLocker').Count 0 'otomatik açma hatası şifrelemeyi geri almaz'

Reset-World
$r = Invoke-BlEnable @{ Drive = 'F:'; KeyDir = $kd; Full = $true }
Assert-Eq (Calls-Of 'Enable-BitLocker')[0] 'Enable-BitLocker EncryptionMethod=XtsAes256 MountPoint=F: RecoveryPasswordProtector=True' 'Full istenince SSD de tüm sürücü'

Reset-World
$r = Invoke-BlEnable @{ Drive = 'E:'; KeyDir = $kd }
Assert-True ($r.Ok -eq $true) 'çıkarılabilir sürücü: başarılı'
Assert-Eq (Calls-Of 'Enable-BitLocker')[0] 'Enable-BitLocker EncryptionMethod=Aes256 MountPoint=E: RecoveryPasswordProtector=True UsedSpaceOnly=True' 'çıkarılabilir: AES-256 (eski Windows ile uyumlu)'
Assert-Eq (Calls-Of 'Enable-BitLockerAutoUnlock').Count 0 'çıkarılabilir sürücüde otomatik açma denenmez'

# =====================================================================
#  3) şifrelemeyi başlat: sistem sürücüsü
# =====================================================================
Reset-World
$r = Invoke-BlEnable @{ Drive = 'C:'; KeyDir = $kd }
Assert-True ($r.Ok -eq $true) ('sistem sürücüsü: başarılı ' + $r.Error)
Assert-Eq (Calls-Of 'Enable-BitLocker')[0] 'Enable-BitLocker EncryptionMethod=XtsAes256 MountPoint=C: TpmProtector=True UsedSpaceOnly=True' 'sistem: TPM koruyucusu, kullanılan alan (SSD)'
Assert-Eq (Calls-Of 'Add-BitLockerKeyProtector').Count 1 'sistem sürücüsüne kurtarma parolası eklenir'
Assert-Eq (Calls-Of 'Add-BitLockerKeyProtector')[0] 'Add-BitLockerKeyProtector MountPoint=C: RecoveryPasswordProtector=True' 'kurtarma parolası C: için'
$order = @($script:Calls | ForEach-Object { ($_ -split ' ')[0] })
Assert-True ($order.IndexOf('Enable-BitLocker') -lt $order.IndexOf('Add-BitLockerKeyProtector')) 'önce etkinleştirme, sonra anahtar'
Assert-True ($r.NeedsReboot -eq $true) 'sistem sürücüsü yeniden başlatma ister'
Assert-True ($r.Message -match 'yeniden başlatınca') 'ileti yeniden başlatmayı söyler'
Assert-True (Test-Path -LiteralPath $r.KeyPath) 'sistem sürücüsü anahtar dosyası var'
Assert-Eq (Calls-Of 'Enable-BitLockerAutoUnlock').Count 0 'sistem sürücüsünde otomatik açma yok'
Assert-True (-not (Logs-HaveSecret)) 'sistem: günlükte anahtar yok'

Reset-World
$script:Disks = @((New-Disk 'C:' 'Fixed' 'HDD'), (New-Disk 'D:' 'Fixed' 'HDD'))
$r = Invoke-BlEnable @{ Drive = 'C:'; KeyDir = $kd }
Assert-Eq (Calls-Of 'Enable-BitLocker')[0] 'Enable-BitLocker EncryptionMethod=XtsAes256 MountPoint=C: TpmProtector=True' 'mekanik sistem diski: tüm sürücü'

# =====================================================================
#  4) reddedilen ve geri alınan durumlar
# =====================================================================
Reset-World
$script:Env.Edition = 'Home'; $script:Env.CanEnable = $false
$r = Invoke-BlEnable @{ Drive = 'C:'; KeyDir = $kd }
Assert-True ($r.Ok -eq $false -and $r.Error -match 'Ayarlar') 'Home: Ayarlar sayfasına yönlendirir'
Assert-Eq $script:Calls.Count 0 'Home: hiçbir BitLocker komutu çalışmaz'

Reset-World
$script:Env.IsAdmin = $false
$r = Invoke-BlEnable @{ Drive = 'D:'; KeyDir = $kd }
Assert-True ($r.Ok -eq $false -and $r.Error -match 'yönetici') 'yönetici değil: reddedilir'
Assert-Eq $script:Calls.Count 0 'yönetici değil: komut çalışmaz'

Reset-World
$script:Disks = @((New-Disk 'C:' 'Fixed' 'SSD'), (New-Disk 'D:' 'Fixed' 'HDD' 1 1))
$r = Invoke-BlEnable @{ Drive = 'D:'; KeyDir = $kd }
Assert-True ($r.Ok -eq $false -and $r.Error -match 'zaten') 'zaten şifreli sürücü reddedilir'
Assert-Eq $script:Calls.Count 0 'zaten şifreli: komut çalışmaz'

Reset-World
$r = Invoke-BlEnable @{ Drive = 'Z:'; KeyDir = $kd }
Assert-True ($r.Ok -eq $false -and $r.Error -match 'bulunamadı') 'olmayan sürücü'
$r = Invoke-BlEnable @{ Drive = 'C:\x'; KeyDir = $kd }
Assert-True ($r.Ok -eq $false -and $r.Error -match 'Geçersiz') 'geçersiz sürücü adı'
Assert-Eq $script:Calls.Count 0 'geçersiz istekte komut çalışmaz'

Reset-World
$script:KeyDirVerdict = 'Anahtarı şifrelenecek sürücüye kaydetmeyin.'
$r = Invoke-BlEnable @{ Drive = 'D:'; KeyDir = $kd }
Assert-True ($r.Ok -eq $false -and $r.Error -match 'şifrelenecek sürücüye') 'anahtar hedef sürücüde olamaz'
Assert-Eq $script:Calls.Count 0 'konum uygun değilken komut çalışmaz'

Reset-World
$r = Invoke-BlEnable @{ Drive = 'D:'; KeyDir = $under }
Assert-True ($r.Ok -eq $false -and $r.Error -match 'yazılamadı') 'yazılamayan klasör reddedilir'
Assert-Eq $script:Calls.Count 0 'yazılamayan klasörde komut çalışmaz (önce yazma denenir)'

Reset-World
$script:Throw['Enable-BitLocker'] = 'TPM hazır değil'
$r = Invoke-BlEnable @{ Drive = 'C:'; KeyDir = $kd }
Assert-True ($r.Ok -eq $false -and $r.Error -match 'BitLocker etkinleştirilemedi' -and $r.Error -match 'TPM hazır değil') 'etkinleştirme hatası iletilir'
Assert-Eq (Calls-Of 'Disable-BitLocker').Count 1 'yarım kalmış olabilecek şifreleme temizlenir'
Assert-Eq (Calls-Of 'Add-BitLockerKeyProtector').Count 0 'etkinleştirme olmadan anahtar eklenmez'

Reset-World
$script:KeyResult = @{ Ok = $false; Keys = @() }
$n0 = @(Get-ChildItem -LiteralPath $kd -Force).Count
$r = Invoke-BlEnable @{ Drive = 'D:'; KeyDir = $kd }
Assert-True ($r.Ok -eq $false -and $r.Error -match 'okunamadı' -and $r.Error -match 'geri alındı') 'anahtar okunamazsa şifreleme geri alınır'
Assert-Eq (Calls-Of 'Disable-BitLocker').Count 1 'geri alma çalıştı'
Assert-Eq @(Get-ChildItem -LiteralPath $kd -Force).Count $n0 'anahtar dosyası oluşmadı'

Reset-World
$script:BadFormat = $true
$n0 = @(Get-ChildItem -LiteralPath $kd -Force).Count
$r = Invoke-BlEnable @{ Drive = 'D:'; KeyDir = $kd }
Assert-True ($r.Ok -eq $false -and $r.Error -match 'doğrulanamadı' -and $r.Error -match 'geri alındı') 'dosya doğrulanamazsa şifreleme geri alınır'
Assert-Eq (Calls-Of 'Disable-BitLocker').Count 1 'doğrulama hatası: geri alma çalıştı'
Assert-Eq @(Get-ChildItem -LiteralPath $kd -Force).Count $n0 'doğrulanamayan dosya silindi'
Assert-Eq (Calls-Of 'Enable-BitLockerAutoUnlock').Count 0 'başarısız akışta otomatik açma denenmez'

Reset-World
$script:BadFormat = $true
$script:Throw['Disable-BitLocker'] = 'meşgul'
$r = Invoke-BlEnable @{ Drive = 'D:'; KeyDir = $kd }
Assert-True ($r.Ok -eq $false -and $r.Error -match 'geri alınamadı' -and $r.Error -match 'Denetim Masası') 'geri alma da olmazsa kullanıcıya yol gösterilir'

Reset-World
$script:Throw['Add-BitLockerKeyProtector'] = 'koruyucu eklenemedi'
$r = Invoke-BlEnable @{ Drive = 'C:'; KeyDir = $kd }
Assert-True ($r.Ok -eq $false -and $r.Error -match 'Kurtarma anahtarı oluşturulamadı' -and $r.Error -match 'geri alındı') 'sistem: koruyucu eklenemezse geri alınır'
Assert-Eq (Calls-Of 'Disable-BitLocker').Count 1 'sistem: geri alma çalıştı'
Assert-True ($r.NeedsReboot -eq $false) 'başarısız akış yeniden başlatma istemez'

# =====================================================================
#  5) diğer işlemler
# =====================================================================
Reset-World
$r = Invoke-BlSimple 'Suspend' 'D:'
Assert-True ($r.Ok -eq $true -and $r.Message -match 'askıya alındı') 'askıya alma'
Assert-Eq (Calls-Of 'Suspend-BitLocker')[0] 'Suspend-BitLocker MountPoint=D: RebootCount=1' 'askıya alma: bir yeniden başlatma'

Reset-World
$script:Env.IsAdmin = $false
$r = Invoke-BlSimple 'Suspend' 'D:'
Assert-True ($r.Ok -eq $false -and $r.Error -match 'yönetici') 'yönetici değilken işlem reddedilir'
Assert-Eq $script:Calls.Count 0 'yönetici değilken komut çalışmaz'

Reset-World
$r = Invoke-BlSimple 'Lock' 'D:'
Assert-True ($r.Ok -eq $true -and $r.Message -match 'kilitlendi') 'kilitleme'
Assert-Eq (Calls-Of 'Lock-BitLocker')[0] 'Lock-BitLocker MountPoint=D:' 'kilitleme zorla ayırmadan yapılır (açık dosyalar korunur)'
$r = Invoke-BlSimple 'Lock' 'C:'
Assert-True ($r.Ok -eq $false -and $r.Error -match 'kilitlenemez') 'sistem sürücüsü kilitlenmez'
Assert-Eq (Calls-Of 'Lock-BitLocker').Count 1 'sistem sürücüsü için kilit komutu çalışmadı'
Reset-World
$script:Throw['Lock-BitLocker'] = 'sürücü kullanımda'
$r = Invoke-BlSimple 'Lock' 'D:'
Assert-True ($r.Ok -eq $false -and $r.Error -match 'açık dosya') 'kullanımdaki sürücü: açıklama'

Reset-World
$r = Invoke-BlSimple 'Disable' 'D:'
Assert-True ($r.Ok -eq $true -and $r.Message -match 'şifre çözme başladı') 'şifrelemeyi kaldırma'
Assert-Eq (Calls-Of 'Disable-BitLocker')[0] 'Disable-BitLocker MountPoint=D:' 'kaldırma ilgili sürücüde'

Reset-World
$script:Disks = @((New-Disk 'C:' 'Fixed' 'SSD' 1 1), (New-Disk 'D:' 'Fixed' 'HDD' 1 1))
$r = Invoke-BlSimple 'AutoUnlock' 'D:'
Assert-True ($r.Ok -eq $true) 'otomatik açma açıldı'
Assert-Eq (Calls-Of 'Enable-BitLockerAutoUnlock')[0] 'Enable-BitLockerAutoUnlock MountPoint=D:' 'otomatik açma ilgili sürücüde'
$r = Invoke-BlSimple 'AutoUnlock' 'C:'
Assert-True ($r.Ok -eq $false -and $r.Error -match 'veri sürücüleri') 'sistem sürücüsü için otomatik açma yok'
Reset-World
$r = Invoke-BlSimple 'AutoUnlock' 'D:'
Assert-True ($r.Ok -eq $false -and $r.Error -match 'sistem sürücüsü şifreli değil') 'sistem şifresizken otomatik açma reddedilir'

Reset-World
$r = Invoke-BlSimple 'Yok' 'D:'
Assert-True ($r.Ok -eq $false -and $r.Error -match 'Bilinmeyen') 'bilinmeyen işlem'
$r = Invoke-BlSimple 'Suspend' ''
Assert-True ($r.Ok -eq $false -and $r.Error -match 'Geçersiz') 'sürücü adı yoksa reddedilir'
Assert-Eq $script:Calls.Count 0 'hatalı isteklerde komut çalışmaz'
Reset-World
$script:Throw['Suspend-BitLocker'] = 'ayrıcalık yok'
$r = Invoke-BlSimple 'Suspend' 'D:'
Assert-True ($r.Ok -eq $false -and $r.Error -match 'ayrıcalık yok') 'komut hatası iletilir'

# giriş noktası
Reset-World
$r = Job_BlOp @{ Op = 'Enable'; Drive = 'd'; KeyDir = $kd }
Assert-True ($r.Ok -eq $true -and $r.Drive -eq 'D:') 'Job_BlOp: Enable yönlendirilir, sürücü adı düzeltilir'
Reset-World
$r = Job_BlOp @{ Op = 'Suspend'; Drive = 'D:' }
Assert-True ($r.Ok -eq $true -and $r.Op -eq 'Suspend') 'Job_BlOp: basit işlem'
Reset-World
$script:Env = $null
$r = Job_BlOp @{ Op = 'Suspend'; Drive = 'D:' }
Assert-True ($r.Ok -eq $false -and [string]$r.Error -ne '') 'Job_BlOp: beklenmeyen hata sonuç tablosuna çevrilir'
Assert-True ($r -is [hashtable]) 'Job_BlOp her zaman tablo döndürür'

# =====================================================================
#  6) kapsam ve plan metni
# =====================================================================
Reset-World
Assert-Eq (Get-BlScope @{ Media = 'HDD' }) 'Full' 'HDD: tüm sürücü'
Assert-Eq (Get-BlScope @{ Media = 'SSD' }) 'Used' 'SSD: kullanılan alan'
Assert-Eq (Get-BlScope @{ Media = '' }) 'Used' 'bilinmeyen ortam: kullanılan alan'
Assert-Eq (Get-BlScope @{ Media = 'Unspecified' }) 'Used' 'belirsiz ortam: kullanılan alan'
Assert-True ((Get-BlScopeText 'Full') -match 'tüm sürücü') 'kapsam metni: tüm'
Assert-True ((Get-BlScopeText 'Used') -match 'kullanılan alan') 'kapsam metni: kullanılan'
$pl = Test-BlEnablePlan (New-Disk 'D:' 'Fixed' 'HDD') $script:Env
Assert-True ($pl.Ok -eq $true -and $pl.Scope -eq 'Full' -and $pl.Cipher -eq 'XtsAes256') 'plan: HDD veri sürücüsü'
Assert-True ((@($pl.Steps) -join ' ') -match 'tüm sürücü') 'plan adımları kapsamı söyler'
$pl = Test-BlEnablePlan (New-Disk 'E:' 'Removable' '' 0 0 'exFAT') $script:Env
Assert-True ($pl.Cipher -eq 'Aes256' -and (@($pl.Steps) -join ' ') -match 'AES-256') 'plan: çıkarılabilir sürücü AES-256'
$pl = Test-BlEnablePlan (New-Disk 'C:' 'Fixed' 'SSD') $script:Env
Assert-True ($pl.Ok -eq $true -and $pl.Method -eq 'Tpm' -and $pl.Scope -eq 'Used' -and $pl.NeedsReboot -eq $true) 'plan: sistem sürücüsü TPM'

# =====================================================================
#  7) kaynak denetimi: eklenti yalnızca BitLocker komutlarını çağırır
# =====================================================================
$srcPath = Join-Path (Join-Path ([System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($env:MM_BUILD))) 'Eklenti') 'DiskKoruma.ps1'
$src = [System.IO.File]::ReadAllText($srcPath)
Assert-True (-not $src.Contains('ForceDismount')) 'zorla ayırma kullanılmaz'
foreach ($bad in 'Format-Volume', 'Clear-Disk', 'Remove-Partition', 'Initialize-Disk', 'diskpart', 'Set-Disk', 'Resize-Partition', 'cipher.exe', 'cipher /') { Assert-True (-not ($src -match ('(?i)' + [regex]::Escape($bad)))) ("eklenti şunu çağırmaz: $bad") }
Assert-True (-not ($src -match 'Write-WhLog[^\r\n]*Password')) 'günlüğe anahtar yazılmaz'
Assert-True (-not $src.Contains([string][char]0x2019)) 'tırnak yerine yazım işareti kullanılmaz (PowerShell tek tırnak sayar)'
foreach ($cmd in 'Enable-BitLocker', 'Add-BitLockerKeyProtector', 'Disable-BitLocker', 'Suspend-BitLocker', 'Lock-BitLocker', 'Enable-BitLockerAutoUnlock') { Assert-True ($src.Contains($cmd)) "komut kullanılıyor: $cmd" }
Assert-True (-not ($src -match '(?i)Invoke-Expression|iex |DownloadString|Start-BitsTransfer|Invoke-WebRequest')) 'eklenti ağa çıkmaz, dizge çalıştırmaz'
Assert-True ($src.Contains('-ErrorAction Stop')) 'komutlar hatada durur'

Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
Show-Result
