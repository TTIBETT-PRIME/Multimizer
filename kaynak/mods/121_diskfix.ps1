# ==================================================================
#  DİSK KORUMA VE SAĞLIK (9.0.0): sürücü modeli, BitLocker etkinleştirme planı, dosya sistemi ve G/Ç hata denetimi.
#  Okuyan ve planlayan işlevler burada; BitLocker’ı açan, askıya alan, kilitleyen ve kaldıran işlevler Eklenti\DiskKoruma.ps1
#  dosyasındadır ve yalnızca kullanıcı ilgili düğmeye basınca yüklenir. Her değiştirme işlemi önce planlanır ve onay ister.
# ==================================================================

function Get-BlMethodName([int]$Method) {
    switch ($Method) {
        1 { return 'AES-128 (yayıcılı)' }
        2 { return 'AES-256 (yayıcılı)' }
        3 { return 'AES-128' }
        4 { return 'AES-256' }
        5 { return 'Donanım şifrelemesi' }
        6 { return 'XTS-AES 128' }
        7 { return 'XTS-AES 256' }
        default { return '' }
    }
}

# Okur. Dönüş: @{ IsAdmin; Edition; Win11; TpmPresent; TpmReady; SecureBoot; OsDrive; CanEnable; OnBattery; HasBattery; OsBlState (Job_SlvDisks doldurur) }
function Get-SlvEnv {
    $adm = $false
    try { $adm = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) } catch { $adm = $false }
    $e = @{ IsAdmin = $adm; Edition = ''; Win11 = $false; TpmPresent = $false; TpmReady = $false; SecureBoot = $null; OsDrive = ([string]$env:SystemDrive).ToUpperInvariant(); CanEnable = $false; OnBattery = $false; HasBattery = $false; OsBlState = '' }
    $p = $null
    try { $p = $sync.Profile } catch { $p = $null }
    if ($null -ne $p) { $e.Edition = [string]$p.Edition; $e.Win11 = ($p.IsWin11 -eq $true) }
    try { $t = Get-Tpm -ErrorAction Stop; $e.TpmPresent = ($t.TpmPresent -eq $true); $e.TpmReady = ($t.TpmReady -eq $true) } catch { }
    try { $e.SecureBoot = [bool](Confirm-SecureBootUEFI -ErrorAction Stop) } catch { $e.SecureBoot = $null }
    $e.CanEnable = (($null -ne (Get-Command -Name 'Enable-BitLocker' -ErrorAction Ignore)) -and ($e.Edition -ne 'Home'))
    try {
        $bt = @(Get-CimInstance -ClassName Win32_Battery -ErrorAction Stop)
        if ($bt.Count -gt 0) { $e.HasBattery = $true; $e.OnBattery = ([int]$bt[0].BatteryStatus -eq 1) }
    } catch { }
    return $e
}

# Okur. Her bölüm için: Drive (C:), Letter, Label, FileSystem, DriveType, Size, Free, DiskNumber, Media, Bus, DiskName, DiskHealth, Dirty, Bl (Get-BitLockerVolumes satırı ya da $null)
function Get-SlvDisks {
    $bl = @{}
    foreach ($b in @(Get-BitLockerVolumes)) { $bl[([string]$b.Drive).ToUpperInvariant()] = $b }
    $phys = @{}
    try { foreach ($pd in @(Get-PhysicalDisk -ErrorAction Stop)) { $phys[[string]$pd.DeviceId] = $pd } } catch { }
    $dirty = @{}
    try {
        foreach ($wv in @(Get-CimInstance -ClassName Win32_Volume -Filter 'DriveType=3' -ErrorAction Stop)) {
            if ([string]$wv.DriveLetter -ne '') { $dirty[([string]$wv.DriveLetter).ToUpperInvariant()] = ($wv.DirtyBitSet -eq $true) }
        }
    } catch { }
    $out = New-Object System.Collections.ArrayList
    $vols = @()
    try { $vols = @(Get-Volume -ErrorAction Stop | Where-Object { $_.DriveLetter -and ($_.DriveType -eq 'Fixed' -or $_.DriveType -eq 'Removable') }) } catch { $vols = @() }
    foreach ($v in $vols) {
        $dl = ([string]$v.DriveLetter).ToUpperInvariant() + ':'
        $row = @{ Drive = $dl; Letter = [string]$v.DriveLetter; Label = [string]$v.FileSystemLabel; FileSystem = [string]$v.FileSystem; DriveType = [string]$v.DriveType; Size = [double]$v.Size; Free = [double]$v.SizeRemaining
            DiskNumber = -1; Media = ''; Bus = ''; DiskName = ''; DiskHealth = ''; Dirty = ($dirty.ContainsKey($dl) -and $dirty[$dl] -eq $true); Bl = $null }
        try { $pt = Get-Partition -DriveLetter $v.DriveLetter -ErrorAction Stop | Select-Object -First 1; $row.DiskNumber = [int]$pt.DiskNumber } catch { }
        if ($row.DiskNumber -ge 0 -and $phys.ContainsKey([string]$row.DiskNumber)) {
            $pd = $phys[[string]$row.DiskNumber]
            $row.Media = [string]$pd.MediaType; $row.Bus = [string]$pd.BusType; $row.DiskName = [string]$pd.FriendlyName; $row.DiskHealth = [string]$pd.HealthStatus
        }
        if ($bl.ContainsKey($dl)) { $row.Bl = $bl[$dl] }
        [void]$out.Add($row)
    }
    return , $out.ToArray()
}

# Fiziksel diskler (sürücü harfi olsun olmasın): Silinen dosyalar sekmesi harfsiz bölümleri ve bozuk diskleri de taramak için kullanır.
# Dönüş: @{ Number; Name; Size; Bus; Media; Style; IsSystem; Offline; Letters (sürücü harfleri); UniqueId; Serial; ReadOnly; Clustered; Pool; Sector;
#         Roles (diske doğrudan yazmayı engelleyen nedenler); Parts (@{ Number; Offset; Size; Letter; Type; IsSystem; IsBoot; IsActive; Fs; Label }) } dizisi
# Silme sekmesi bu kayıtları kullanır; kimlik alanları (UniqueId, Serial, Name, Size) onay anındaki karşılaştırma içindir.
function Get-SlvPhysDisks {
    $out = New-Object System.Collections.ArrayList
    $disks = @()
    try { $disks = @(Get-Disk -ErrorAction Stop) } catch { return , $out.ToArray() }
    $pds = @{}
    try { foreach ($pd in @(Get-PhysicalDisk -ErrorAction Stop)) { $pds[[string]$pd.DeviceId] = $pd } } catch { }
    $vols = @{}
    try { foreach ($v in @(Get-Volume -ErrorAction Stop)) { if ($v.DriveLetter) { $vols[([string]$v.DriveLetter).ToUpperInvariant() + ':'] = $v } } } catch { }
    # Windows’un, Multimizer’ın ya da geçici dosyaların bulunduğu sürücüler (silme sekmesi bu disklere doğrudan yazmaz)
    $prot = @{}
    try { $prot = Get-WipeProtectedLetters } catch { $prot = @{} }
    foreach ($dk in $disks) {
        $n = [int]$dk.Number
        $row = @{ Number = $n; Name = ([string]$dk.FriendlyName).Trim(); Size = [double]$dk.Size; Bus = [string]$dk.BusType; Media = ''; Style = [string]$dk.PartitionStyle
            IsSystem = ($dk.IsSystem -eq $true -or $dk.IsBoot -eq $true); Offline = ($dk.IsOffline -eq $true); Letters = @(); Parts = @()
            UniqueId = ([string]$dk.UniqueId).Trim(); Serial = ([string]$dk.SerialNumber).Trim(); ReadOnly = ($dk.IsReadOnly -eq $true); Clustered = ($dk.IsClustered -eq $true)
            Pool = $false; Sector = 512; Roles = @() }
        try { if ([int]$dk.LogicalSectorSize -ge 512) { $row.Sector = [int]$dk.LogicalSectorSize } } catch { }
        if ($pds.ContainsKey([string]$n)) {
            $row.Media = [string]$pds[[string]$n].MediaType
            try { $row.Pool = (@($pds[[string]$n].CannotPoolReason) -contains 'In a Pool') } catch { }
        }
        $letters = New-Object System.Collections.ArrayList
        $plist = New-Object System.Collections.ArrayList
        $roles = New-Object System.Collections.ArrayList
        try {
            foreach ($pt in @(Get-Partition -DiskNumber $n -ErrorAction Stop)) {
                $l = ''
                if ($pt.DriveLetter) { $l = ([string]$pt.DriveLetter).ToUpperInvariant() + ':' }
                $fs = ''
                $lbl = ''
                if ($l -ne '' -and $vols.ContainsKey($l)) { $fs = [string]$vols[$l].FileSystem; $lbl = [string]$vols[$l].FileSystemLabel }
                [void]$plist.Add(@{ Number = [int]$pt.PartitionNumber; Offset = [double]$pt.Offset; Size = [double]$pt.Size; Letter = $l; Type = [string]$pt.Type
                    IsSystem = ($pt.IsSystem -eq $true); IsBoot = ($pt.IsBoot -eq $true); IsActive = ($pt.IsActive -eq $true); Fs = $fs; Label = $lbl })
                if ($l -ne '') {
                    [void]$letters.Add($l)
                    if ($prot.ContainsKey($l)) { [void]$roles.Add(($l + ' sürücüsü: ' + [string]$prot[$l])) }
                }
            }
        } catch { }
        $row.Letters = $letters.ToArray()
        $row.Parts = $plist.ToArray()
        $row.Roles = $roles.ToArray()
        [void]$out.Add($row)
    }
    return , $out.ToArray()
}

# Bir sürücünün şifreleme durumu: none | encrypted | suspended | working | locked | unknown
function Get-BlState($Disk) {
    $b = $Disk.Bl
    if ($null -eq $b) { return 'unknown' }
    $c = [int]$b.Conversion
    $p = [int]$b.Protection
    if ($c -eq 0) { return 'none' }
    if ($c -ge 2 -and $c -le 5) { return 'working' }
    if ($c -eq 1) {
        if ($p -eq 1) { return 'encrypted' }
        if ($p -eq 0) { return 'suspended' }
        return 'unknown'
    }
    if ($c -lt 0 -and $p -eq 2) { return 'locked' }
    return 'unknown'
}

# Şifreleme kapsamı: mekanik diskte tüm sürücü (silinmiş dosyaların kalıntıları da şifrelenir); SSD ve çıkarılabilir sürücüde
# yalnızca kullanılan alan (SSD’de silinen alanı zaten TRIM boşaltır). Dönüş: Full | Used
function Get-BlScope($Vol) {
    if ([string]$Vol.Media -eq 'HDD') { return 'Full' }
    return 'Used'
}

function Get-BlScopeText([string]$Scope) {
    if ($Scope -eq 'Full') { return 'tüm sürücü; silinmiş dosyaların kalıntıları da şifrelenir' }
    return 'yalnızca kullanılan alan'
}

# BitLocker’ı bu sürücüde açmak mümkün mü? Yalnızca planlar, hiçbir şey değiştirmez.
# Dönüş: @{ Ok; Why; Method (Tpm | RecoveryPassword | DeviceEncryption | ''); Steps; Warnings; NeedsReboot; IsOs }
function Test-BlEnablePlan($Vol, $Sys) {
    $r = @{ Ok = $false; Why = ''; Method = ''; Steps = @(); Warnings = @(); NeedsReboot = $false; IsOs = $false; Scope = ''; Cipher = '' }
    $drive = ([string]$Vol.Drive).ToUpperInvariant()
    $isOs = ($drive -eq ([string]$Sys.OsDrive).ToUpperInvariant())
    $r.IsOs = $isOs
    $state = Get-BlState $Vol
    if ($state -ne 'none') {
        if ($state -eq 'unknown') { $r.Why = 'Şifreleme durumu okunamadı; Multimizer’ı yönetici olarak çalıştırın.' } else { $r.Why = 'Bu sürücü zaten şifreli ya da şifreleniyor.' }
        return $r
    }
    if ($Sys.IsAdmin -ne $true) { $r.Why = 'Şifrelemeyi başlatmak için Multimizer’ı yönetici olarak çalıştırın.'; return $r }
    if (@('NTFS', 'FAT32', 'exFAT') -notcontains [string]$Vol.FileSystem) { $r.Why = 'Bu dosya sistemi şifrelenemez (NTFS, FAT32 ya da exFAT olmalı).'; return $r }
    if ($Sys.CanEnable -ne $true) {
        if ([string]$Sys.Edition -eq 'Home' -and $isOs -and $Sys.TpmPresent -eq $true) {
            $r.Ok = $true; $r.Method = 'DeviceEncryption'
            $r.Steps = @('Windows Home’da tam BitLocker yoktur. Ayarlar > Gizlilik ve güvenlik > Cihaz şifrelemesi sayfası açılır; oradan açtığınızda Windows kurtarma anahtarını Microsoft hesabınıza kaydeder.')
            return $r
        }
        $r.Why = 'Bu Windows sürümünde BitLocker yok (Home). Cihaz şifrelemesi için TPM 2.0 gerekir; yoksa 7-Zip, VeraCrypt gibi açık kaynak araçlar kullanılabilir.'
        return $r
    }
    if ($isOs) {
        if ($Sys.TpmPresent -ne $true) { $r.Why = 'Bu bilgisayarda TPM bulunamadı ya da BIOS’ta kapalı. Sistem diskini şifrelemek için TPM gerekir; BIOS/UEFI’de “fTPM / PTT” seçeneğini açın.'; return $r }
        if ($Sys.TpmReady -ne $true) { $r.Why = 'TPM var ama kullanıma hazır değil. Windows Güvenliği > Cihaz güvenliği > Güvenlik işlemcisi ayrıntılarından TPM’i hazırlayın.'; return $r }
        $r.Method = 'Tpm'
        $r.Scope = Get-BlScope $Vol
        $r.Cipher = 'XtsAes256'
        $r.Steps = @('TPM koruyucusu eklenir (şifre sormadan açılır).', 'Kurtarma parolası oluşturulur ve sizin seçtiğiniz klasöre kaydedilip doğrulanır.', ('Yeniden başlatınca donanım sınaması yapılır ve şifreleme arka planda başlar (XTS-AES 256, ' + (Get-BlScopeText $r.Scope) + ').'))
        $r.NeedsReboot = $true
        if ($Sys.SecureBoot -eq $false) { $r.Warnings += 'Güvenli Önyükleme (Secure Boot) kapalı; BitLocker yine çalışır ama önyükleme zinciri korunmaz.' }
    } else {
        $r.Method = 'RecoveryPassword'
        $r.Scope = Get-BlScope $Vol
        $r.Cipher = 'XtsAes256'
        if ([string]$Vol.DriveType -eq 'Removable') { $r.Cipher = 'Aes256' }
        $r.Steps = @('Kurtarma parolası oluşturulur ve sizin seçtiğiniz klasöre kaydedilip doğrulanır.', ('Sürücü şifrelenmeye başlar (' + $(if ($r.Cipher -eq 'Aes256') { 'AES-256' } else { 'XTS-AES 256' }) + ', ' + (Get-BlScopeText $r.Scope) + ').'), 'Sistem diski de şifreliyse sürücü oturum açınca kendiliğinden açılır.')
        if ([string]$Vol.DriveType -eq 'Removable') { $r.Warnings += 'Çıkarılabilir sürücü takıldığı her bilgisayarda kurtarma parolası ister. Parolayı kaybederseniz verilere erişilemez.' }
    }
    if ($Sys.HasBattery -eq $true -and $Sys.OnBattery -eq $true) { $r.Warnings += 'Dizüstü pil ile çalışıyor; şifreleme sürerken şarj cihazını takın.' }
    if ([double]$Vol.Size -gt 0 -and [double]$Vol.Free / [double]$Vol.Size -lt 0.05) { $r.Warnings += 'Sürücüde boş alan %5’in altında; şifrelemeden önce yer açmanız önerilir.' }
    $r.Ok = $true
    return $r
}

# Anahtar dosyasının konumu güvenli mi? '' = uygun. Anahtar, şifrelenen sürücüde saklanırsa işe yaramaz.
function Test-BlKeyDir([string]$Dir, [string]$Drive) {
    $d = ([string]$Dir).Trim()
    if ($d -eq '') { return 'Anahtarın kaydedileceği klasörü seçin.' }
    if ($d -match '[\*\?"<>\|]') { return 'Klasör yolunda geçersiz karakter var.' }
    if ($d.Length -lt 3 -or $d.Substring(1, 2) -ne ':\') { return 'Anahtar yerel bir sürücüdeki klasöre kaydedilmeli (ör. D:\Anahtarlar).' }
    $dl = $d.Substring(0, 1).ToUpperInvariant()
    $target = ([string]$Drive).Trim().TrimEnd(':').ToUpperInvariant()
    if ($dl -eq $target) { return 'Anahtarı şifrelenecek sürücüye kaydetmeyin; sürücüye erişemediğinizde anahtara da erişemezsiniz. USB bellek ya da başka bir sürücü seçin.' }
    return ''
}

function Get-BlKeyFileName([string]$Drive) {
    $l = ([string]$Drive).Trim().TrimEnd(':').ToUpperInvariant()
    $pc = ([string]$env:COMPUTERNAME) -creplace '[^A-Za-z0-9\-_]', ''
    if ($pc -eq '') { $pc = 'PC' }
    return ('BitLocker-kurtarma-' + $l + '-' + $pc + '.txt')
}

# ---------------- sürücü bölümleri: arayüzde gösterilecek satırlar ----------------
function Format-SlvMedia($D) {
    $m = [string]$D.Media
    $b = [string]$D.Bus
    $t = ''
    if ($m -eq 'SSD') { $t = 'SSD' } elseif ($m -eq 'HDD') { $t = 'HDD' }
    if ($b -eq 'NVMe') { if ($t -eq '') { $t = 'NVMe' } else { $t = $t + ' (NVMe)' } }
    elseif ($b -eq 'USB') { if ($t -eq '') { $t = 'USB' } else { $t = $t + ' (USB)' } }
    return $t
}

# Dönüş: dizi; her öğe @{ Kind = 'head' | 'row'; Title; Detail; Br; Do; Label }  (Do boşsa düğme yok)
function Get-SlvDiskRows($D, $Sys) {
    $rows = New-Object System.Collections.ArrayList
    $name = [string]$D.Drive
    if ([string]$D.Label -ne '') { $name += '  ' + [string]$D.Label }
    $head = $name
    $media = Format-SlvMedia $D
    $bits = New-Object System.Collections.ArrayList
    if ([string]$D.FileSystem -ne '') { [void]$bits.Add([string]$D.FileSystem) }
    if ([double]$D.Size -gt 0) { [void]$bits.Add((Format-Size ([double]$D.Size)) + ', ' + (Format-Size ([double]$D.Free)) + ' boş') }
    if ($media -ne '') { [void]$bits.Add($media) }
    if ([string]$D.DiskName -ne '') { [void]$bits.Add([string]$D.DiskName) }
    [void]$rows.Add(@{ Kind = 'head'; Title = $head + '   ' + ($bits.ToArray() -join '  ·  ') })

    $state = Get-BlState $D
    $plan = Test-BlEnablePlan $D $Sys
    $isOs = (([string]$D.Drive).ToUpperInvariant() -eq ([string]$Sys.OsDrive).ToUpperInvariant())
    $b = $D.Bl
    if ($state -eq 'encrypted') {
        $det = 'Şifreli ve koruma açık.'
        if ($null -ne $b) { $mn = @($b.Types | ForEach-Object { Get-BlProtectorName ([int]$_) }); if ($mn.Count -gt 0) { $det += ' Koruyucular: ' + ($mn -join ', ') + '.' } }
        if ($null -ne $b -and $b.HasRecovery -ne $true) { [void]$rows.Add(@{ Kind = 'row'; Title = 'BitLocker: kurtarma anahtarı tanımlı değil'; Detail = $det + ' Anahtar olmadan bir donanım ya da BIOS değişikliğinden sonra verilere erişilemeyebilir.'; Br = 'BrBad'; Do = 'BlAddKey'; Label = 'Kurtarma anahtarı ekle' }) }
        else { [void]$rows.Add(@{ Kind = 'row'; Title = 'BitLocker: şifreli'; Detail = $det; Br = 'BrGood'; Do = 'BlKey'; Label = 'Anahtarı göster'; Do2 = 'BlSave'; Label2 = 'Dosyaya kaydet...' }) }
        $rows.Add(@{ Kind = 'row'; Title = 'BitLocker işlemleri'; Detail = 'Güncelleme ya da BIOS değişikliği öncesinde koruma geçici olarak askıya alınabilir.'; Br = 'BrFaint'; Do = 'BlSuspend'; Label = 'Korumayı askıya al'; Do2 = 'BlDisable'; Label2 = 'Şifrelemeyi kaldır...' }) | Out-Null
        if (-not $isOs -and [string]$D.DriveType -eq 'Fixed' -and $null -ne $b -and @($b.Types) -notcontains 2 -and ($Sys.OsBlState -eq 'encrypted' -or $Sys.OsBlState -eq 'working')) {
            $rows.Add(@{ Kind = 'row'; Title = 'Otomatik açma kapalı'; Detail = 'Bu sürücü her açılışta kurtarma anahtarı isteyebilir. Otomatik açma, sistem sürücüsü açılınca bu sürücüyü de açar (yalnızca bu bilgisayarda).'; Br = 'BrWarn'; Do = 'BlAutoUnlock'; Label = 'Otomatik açmayı aç' }) | Out-Null
        }
        if (-not $isOs -and [string]$D.DriveType -ne '') { $rows.Add(@{ Kind = 'row'; Title = 'Sürücüyü kilitle'; Detail = 'Kilitlenen sürücüye parola ya da kurtarma anahtarı olmadan erişilemez.'; Br = 'BrFaint'; Do = 'BlLock'; Label = 'Kilitle' }) | Out-Null }
    } elseif ($state -eq 'suspended') {
        [void]$rows.Add(@{ Kind = 'row'; Title = 'BitLocker: koruma askıda'; Detail = 'Sürücü şifreli ama koruma kapalı; veriler şu anda anahtarsız okunabilir. İşiniz bitince korumayı sürdürün.'; Br = 'BrWarn'; Do = 'BlResume'; Label = 'Korumayı sürdür' })
    } elseif ($state -eq 'working') {
        $pc = 0; if ($null -ne $b) { $pc = [int]$b.Percent }
        [void]$rows.Add(@{ Kind = 'row'; Title = 'BitLocker: işlem sürüyor (%' + [string]$pc + ')'; Detail = 'Şifreleme ya da şifre çözme arka planda sürüyor. Bilgisayar kapanırsa kaldığı yerden devam eder.'; Br = 'BrInfo'; Do = ''; Label = '' })
    } elseif ($state -eq 'none') {
        if ($plan.Ok -eq $true) {
            $lbl = 'Şifrelemeyi başlat'
            if ($plan.Method -eq 'DeviceEncryption') { $lbl = 'Cihaz şifrelemesini aç' }
            $br = 'BrFaint'; if ($isOs) { $br = 'BrWarn' }
            [void]$rows.Add(@{ Kind = 'row'; Title = 'BitLocker: şifreli değil'; Detail = (($plan.Steps | Select-Object -First 1) + ' Bilgisayar çalınır ya da kaybolursa diskteki dosyalara erişilebilir.'); Br = $br; Do = 'BlEnable'; Label = $lbl })
        } else {
            [void]$rows.Add(@{ Kind = 'row'; Title = 'BitLocker: şifreli değil'; Detail = [string]$plan.Why; Br = 'BrFaint'; Do = ''; Label = '' })
        }
    } elseif ($state -eq 'locked') {
        [void]$rows.Add(@{ Kind = 'row'; Title = 'BitLocker: sürücü kilitli'; Detail = 'Sürücü şifreli ve kilitli. Dosya Gezgini’nde sürücüye çift tıklayıp parolayı ya da kurtarma anahtarını girerek açın.'; Br = 'BrInfo'; Do = ''; Label = '' })
        return , $rows.ToArray()
    } else {
        [void]$rows.Add(@{ Kind = 'row'; Title = 'BitLocker durumu okunamadı'; Detail = 'Yönetici olarak çalıştırın ya da bu Windows sürümünde BitLocker olmayabilir.'; Br = 'BrFaint'; Do = ''; Label = '' })
    }
    if ([string]$D.DiskHealth -ne '' -and [string]$D.DiskHealth -ne 'Healthy') {
        [void]$rows.Add(@{ Kind = 'row'; Title = 'Disk sağlığı: ' + [string]$D.DiskHealth; Detail = 'Windows bu diskin sağlığının bozulduğunu bildiriyor. Önemli dosyalarınızı hemen yedekleyin.'; Br = 'BrBad'; Do = 'Backup'; Label = 'Yedekleme sayfası' })
    }
    if ($D.Dirty -eq $true) {
        [void]$rows.Add(@{ Kind = 'row'; Title = 'Dosya sistemi hata bildirmiş (kirli bit)'; Detail = 'Windows bu sürücünün düzgün kapanmadığını ya da dosya sistemi hatası bulduğunu işaretlemiş. Onarım sürücüyü kısa süre kullanılamaz yapabilir; sistem sürücüsü yeniden başlatmada onarılır.'; Br = 'BrWarn'; Do = 'DiskRepair'; Label = 'Onar' })
    } elseif ([string]$D.FileSystem -eq 'NTFS') {
        [void]$rows.Add(@{ Kind = 'row'; Title = 'Dosya sistemi denetimi'; Detail = 'Çevrimiçi, salt okunur tarama yapar; hiçbir şeyi değiştirmez.'; Br = 'BrFaint'; Do = 'DiskScan'; Label = 'Tara' })
    }
    $rows.Add(@{ Kind = 'row'; Title = 'Sürücü iyileştirme'; Detail = 'SSD’de TRIM, mekanik diskte birleştirme çalıştırır.'; Br = 'BrFaint'; Do = 'DiskOptimize'; Label = 'İyileştir' }) | Out-Null
    return , $rows.ToArray()
}

# ---------------- bulgular ----------------
function Add-DiskProtectFindings($Disks, $Sys) {
    $osd = ([string]$Sys.OsDrive).ToUpperInvariant()
    $os = $null
    foreach ($d in @($Disks)) { if (([string]$d.Drive).ToUpperInvariant() -eq $osd) { $os = $d } }
    $act = New-SolveAction 'disk' '' 'Diskler sekmesi'
    $state = 'unknown'
    if ($null -ne $os) { $state = Get-BlState $os }
    if ($state -eq 'unknown') {
        if ([string]$Sys.Edition -eq 'Home') {
            Add-Finding 'bl' 'sec' 'info' 'Disk şifreleme: Windows Home’da tam BitLocker yok' 'Home sürümünde yalnızca “Cihaz şifrelemesi” bulunur ve TPM 2.0 gerektirir. Ayarlar > Gizlilik ve güvenlik > Cihaz şifrelemesi sayfasına bakın.' $act 0
        } else {
            Add-Finding 'bl' 'sec' 'info' 'Disk şifreleme (BitLocker) durumu okunamadı' 'Multimizer’ı yönetici olarak çalıştırın. Bu sürümde BitLocker bulunmuyor da olabilir.' $act 0
        }
    } elseif ($state -eq 'encrypted') {
        Add-Finding 'bl' 'sec' 'ok' 'Sistem diski şifreli (BitLocker)' 'Bilgisayar çalınırsa diskteki dosyalara erişilemez.'
        if ($os.Bl.HasRecovery -ne $true) {
            Add-Finding 'bl-key' 'sec' 'warn' 'BitLocker kurtarma anahtarı tanımlı değil' 'Disk şifreli ama kurtarma anahtarı yok. BIOS güncellemesi ya da donanım değişikliğinden sonra Windows anahtar sorarsa verilere erişemezsiniz. Anahtar ekleyip bilgisayarın dışında saklayın.' (New-SolveAction 'disk' '' 'Anahtar ekle')
        }
    } elseif ($state -eq 'suspended') {
        Add-Finding 'bl' 'sec' 'warn' 'BitLocker koruması askıda' 'Sistem diski şifreli ama koruma geçici olarak kapatılmış; bu sırada veriler anahtarsız okunabilir. Güncelleme ya da BIOS işi bittiyse korumayı sürdürün.' $act -1 (New-RunFix 'BlResume' 'Korumayı sürdür' 'Click')
    } elseif ($state -eq 'working') {
        Add-Finding 'bl' 'sec' 'info' 'Sistem diski şifreleniyor' ('Şifreleme arka planda sürüyor (%' + [string]$os.Bl.Percent + '). Bilgisayar kapanırsa kaldığı yerden devam eder.') $null 0
    } else {
        $plan = Test-BlEnablePlan $os $Sys
        $detail = 'Sistem diski şifreli değil. Bilgisayar çalınır ya da kaybolursa diskteki dosyalara erişilebilir.'
        if ($plan.Ok -eq $true) {
            if ($plan.Method -eq 'DeviceEncryption') { $detail += ' Cihaz şifrelemesini Çözüm Merkezi’nden açabilirsiniz.' }
            else { $detail += ' Çözüm Merkezi şifrelemeyi sizin yerinize başlatır; anahtarı kaydetmeniz yeterli.' }
        } else { $detail += ' ' + [string]$plan.Why }
        $st = 'warn'
        if ($Sys.HasBattery -ne $true) { $st = 'info' }
        Add-Finding 'bl' 'sec' $st 'Sistem diski şifreli değil' $detail (New-SolveAction 'disk' '' 'Şifrelemeyi başlat')
    }
    $open = New-Object System.Collections.ArrayList
    foreach ($d in @($Disks)) {
        if (([string]$d.Drive).ToUpperInvariant() -eq $osd -or [string]$d.DriveType -ne 'Fixed') { continue }
        if ((Get-BlState $d) -eq 'none' -and [double]$d.Size -gt 0) { [void]$open.Add([string]$d.Drive) }
    }
    if ($open.Count -gt 0) {
        Add-Finding 'bl-data' 'sec' 'info' ('Şifrelenmemiş veri sürücüleri: ' + ($open.ToArray() -join ', ')) 'Bu sürücülerdeki dosyalar bilgisayar çalınırsa okunabilir. İsterseniz Çözüm Merkezi’nden şifreleyebilirsiniz.' (New-SolveAction 'disk' '' 'Diskler sekmesi') 0
    }
}

function Add-VolumeHealthFindings($Disks) {
    foreach ($d in @($Disks)) {
        $dr = [string]$d.Drive
        if ($d.Dirty -eq $true) {
            $isOs = ($dr.ToUpperInvariant() -eq ([string]$env:SystemDrive).ToUpperInvariant())
            $note = ''
            if ($isOs) { $note = ' Sistem sürücüsü bir sonraki yeniden başlatmada onarılır.' }
            Add-Finding ('fs-dirty-' + $dr.TrimEnd(':')) 'maint' 'warn' ($dr + ' sürücüsünde dosya sistemi hatası işaretli') ('Windows bu sürücüyü “kirli” olarak işaretlemiş: düzgün kapanmamış ya da dosya sistemi hatası bulunmuş olabilir.' + $note) $null -1 (New-StepsFix 'Click' 'Sürücüyü onar' @(@{ Id = 'chkdsk-' + $dr.TrimEnd(':'); Title = $dr + ' sürücüsünü onar'; Ops = @(@{ T = 'ChkdskRepair'; Drive = $dr }); Reboot = $isOs }))
        }
    }
}

# ---------------- dosya sistemi onarımı (önizleme ve günlük destekli) ----------------
function Invoke-ChkdskRepairOp($Op) {
    $dr = ([string]$Op.Drive).Trim().ToUpperInvariant()
    if ($dr -cnotmatch '^[A-Z]:?$') { throw ('Geçersiz sürücü: ' + $dr) }
    $letter = $dr.Substring(0, 1)
    if ($script:Preview) { Add-Plan ($letter + ': sürücüsünde dosya sistemi onarımı (Repair-Volume -SpotFix) çalıştırılacak'); return }
    $r = Repair-Volume -DriveLetter $letter -SpotFix -ErrorAction Stop
    Add-Done ($letter + ': sürücüsü onarıldı ya da yeniden başlatmada onarılmak üzere işaretlendi (' + [string]$r + ')')
}
$script:MoreOps['ChkdskRepair'] = 'Invoke-ChkdskRepairOp'

# Çevrimiçi salt okunur tarama ve iyileştirme eylemleri (Job_Action anahtarlarıyla çağrılır; P.Drive tek harf)
function Invoke-SlvDriveAction([string]$Kind, $P) {
    $dr = ([string]$P.Drive).Trim().TrimEnd(':').ToUpperInvariant()
    if ($dr -cnotmatch '^[A-Z]$') { throw 'Sürücü harfi geçersiz.' }
    if ($Kind -eq 'scan') {
        Write-WhLog ($dr + ': sürücüsü taranıyor (salt okunur)...') 'INFO'
        $r = Repair-Volume -DriveLetter $dr -Scan -ErrorAction Stop
        Write-WhLog ($dr + ': tarama sonucu: ' + [string]$r) 'OK'
    } elseif ($Kind -eq 'optimize') {
        Write-WhLog ($dr + ': sürücü iyileştiriliyor...') 'INFO'
        Optimize-Volume -DriveLetter $dr -ErrorAction Stop | Out-Null
        Write-WhLog ($dr + ': sürücü iyileştirildi.') 'OK'
    }
}

function Invoke-BlResumeAction($P) {
    $d = ''
    try { $d = ([string]$P.Drive).Trim() } catch { $d = '' }
    if ($d -eq '') { $d = [string]$env:SystemDrive }
    if ($d.Length -eq 1) { $d += ':' }
    if ($d -cnotmatch '^[A-Za-z]:$') { throw 'Sürücü geçersiz.' }
    Resume-BitLocker -MountPoint $d -ErrorAction Stop | Out-Null
    Write-WhLog ($d + ' için BitLocker koruması sürdürüldü.') 'OK'
}
$script:ExtraActions['BlResume'] = 'Invoke-BlResumeAction'

# ---------------- disk G/Ç hataları (olay günlüğü) ----------------
# Disk: 7 bozuk blok, 11 denetleyici hatası, 51 disk belleği G/Ç hatası, 52 arıza öngörüsü (S.M.A.R.T.), 153 yeniden denenen G/Ç, 157 aygıt beklenmedik çıkarıldı; Ntfs: 55 dosya sistemi bozuk, 140 yazma tutarsızlığı
function Get-DiskErrorEvents([int]$Days = 30) {
    $out = New-Object System.Collections.ArrayList
    $evs = @()
    try { $evs = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = @('disk', 'Ntfs', 'Microsoft-Windows-Ntfs'); Id = @(7, 11, 51, 52, 55, 140, 153, 157); StartTime = (Get-Date).AddDays(-$Days) } -MaxEvents 500 -ErrorAction Stop) } catch { $evs = @() }
    foreach ($e in $evs) { [void]$out.Add(@{ Time = [datetime]$e.TimeCreated; Id = [int]$e.Id; Source = [string]$e.ProviderName }) }
    return , $out.ToArray()
}

# Dönüş: @{ Counts (kimlik -> adet); Last; Total }
function Get-DiskErrorSummary($Events) {
    $c = @{}
    $last = [datetime]'2000-01-01'
    $total = 0
    foreach ($e in @($Events)) {
        $k = [string][int]$e.Id
        if ($c.ContainsKey($k)) { $c[$k] = [int]$c[$k] + 1 } else { $c[$k] = 1 }
        if ($e.Time -gt $last) { $last = $e.Time }
        $total++
    }
    return @{ Counts = $c; Last = $last; Total = $total }
}

function Get-DiskErrCount($Sum, [int]$Id) {
    $k = [string]$Id
    if ($Sum.Counts.ContainsKey($k)) { return [int]$Sum.Counts[$k] }
    return 0
}

function Add-DiskErrorFindings($Sum, [int]$Days) {
    $d = [string]$Days
    $pred = Get-DiskErrCount $Sum 52
    $bad = (Get-DiskErrCount $Sum 7) + (Get-DiskErrCount $Sum 11) + (Get-DiskErrCount $Sum 55)
    $soft = (Get-DiskErrCount $Sum 51) + (Get-DiskErrCount $Sum 153) + (Get-DiskErrCount $Sum 140)
    $act = New-SolveAction 'disk' '' 'Diskler sekmesi'
    if ($pred -gt 0) {
        Add-Finding 'disk-pred' 'maint' 'bad' 'Windows bir diskin yakında bozulacağını bildirdi' ('Son ' + $d + ' günde disk sürücüsü arıza öngörüsü (S.M.A.R.T.) bildirdi. Bu uyarı ciddiye alınmalıdır: önemli dosyalarınızı hemen başka bir sürücüye yedekleyin ve diski değiştirmeyi planlayın.') (New-SolveAction 'recover' '' 'Yedekle ve kurtar') 14
    }
    if ($bad -gt 0) {
        Add-Finding 'disk-io' 'maint' 'warn' ('Son ' + $d + ' günde ' + [string]$bad + ' disk ya da dosya sistemi hatası') ('Windows bozuk blok, denetleyici hatası ya da dosya sistemi bozulması kaydetmiş (son kayıt ' + $Sum.Last.ToString('dd.MM.yyyy HH:mm') + '). Diskin bağlantı kablosunu ve portunu denetleyin, Diskler sekmesinden dosya sistemi taraması yapın ve yedek alın; sürerse diski değiştirin.') $act 6
    } elseif ($soft -ge 5) {
        Add-Finding 'disk-io' 'maint' 'info' ('Son ' + $d + ' günde ' + [string]$soft + ' disk G/Ç yeniden denemesi') 'Disk işlemleri yeniden denenmiş ya da zaman aşımına uğramış. Genellikle gevşek bir USB ya da SATA bağlantısından, zayıf güç kaynağından veya yavaşlayan bir diskten olur.' $act 0
    } elseif ($pred -eq 0) {
        Add-Finding 'disk-io' 'maint' 'ok' ('Son ' + $d + ' günde disk hatası kaydı yok') ''
    }
}

function Chk_DiskProtect {
    $sys = Get-SlvEnv
    $disks = Get-SlvDisks
    Add-DiskProtectFindings $disks $sys
    Add-VolumeHealthFindings $disks
}

function Chk_DiskErrors {
    $days = 30
    $sum = Get-DiskErrorSummary (Get-DiskErrorEvents $days)
    Add-DiskErrorFindings $sum $days
}
