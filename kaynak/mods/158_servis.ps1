# ---------------- Windows bileşen servisi (DISM): meşgul denetimi ve süre sınırlı çalıştırma ----------------
# Gerçek bilgisayarda (17.11.2026) Windows Update bir güncelleme kurarken Enable-WindowsOptionalFeature 1,5 saat bekleyip
# 0x80240021 (Windows Update zaman aşımı) verdi; o sürede işlem asılı kaldı ve özellik geri açılamadı.
# Windows özelliği ve bileşen işlemleri artık:
#  1) DISM'i ayrı bir süreçte çalıştırır ve en çok $script:DismLimitMin dakika bekler; asılı kalırsa süreci kapatıp açık bir hata verir,
#  2) özelliği önce yalnızca yerel kaynakla açmayı dener (/LimitAccess: Windows Update'e gitmez, saniyeler içinde sonuçlanır),
#  3) yerel kaynak yetmezse ve Windows Update o anda güncelleme kurmuyorsa Windows Update kaynağıyla (yine süre sınırlı) dener.
$script:DismLimitMin = 15
# Bu oturumda DISM "once yeniden baslatin" turunden bir kodla reddetti mi (canli denetim kurtarmayi buna gore erteler)
$script:DismNeedsReboot = $false
# Bu oturumda bir DISM süre sınırını aştı mı? Aştıysa bileşen hizmeti (TrustedInstaller) işi arka planda sürdürüyor olabilir:
# gerçek bilgisayarda (17.11.2026) süre dolunca kapatılan DISM'den sonraki özellik işlemi 20 dakika asılı kaldı. Bu bayrak açıkken
# yeni DISM işlemi başlatılmaz; açık bir hata ile yeniden başlatma istenir.
$script:DismTimedOut = $false

# Windows Update şu anda güncelleme kuruyor mu? Dönüş: '' (hayır) ya da nedeni anlatan metin
function Get-ServicingBusy {
    try {
        $inst = New-Object -ComObject Microsoft.Update.Installer
        if ([bool]$inst.IsBusy) { return 'Windows Update şu anda bir güncelleme kuruyor' }
    } catch { }
    return ''
}

# dism.exe yolu (32 bit PowerShell 64 bit Windows'ta Sysnative üzerinden; 32 bit DISM çalışan 64 bit sisteme hizmet veremez)
function Get-DismExePath {
    $p = Join-Path $env:WINDIR 'System32\dism.exe'
    try { if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { $p = Join-Path $env:WINDIR 'Sysnative\dism.exe' } } catch { }
    return $p
}

# DISM çıkış kodunun onaltılık yazımı ve açıklaması
function Get-DismCodeText([int64]$Code) {
    if ($Code -eq -1) { return ('DISM ' + $script:DismLimitMin + ' dakikada bitmedi (Windows Update meşgul olabilir)') }
    $u = [uint32]($Code -band 0xFFFFFFFFL)
    $hex = '0x' + $u.ToString('X8')
    switch ($hex) {
        '0x800F081F' { return ($hex + ': Windows bu özelliğin kaynak dosyalarını bulamadı') }
        '0x800F0906' { return ($hex + ': kaynak dosyalar indirilemedi (internet bağlantısı)') }
        '0x800F0907' { return ($hex + ': kurum ilkesi Windows Update kaynağını engelliyor') }
        '0x800F0954' { return ($hex + ': Windows Update kaynağına ulaşılamadı (kurum ilkesi / WSUS)') }
        '0x80240021' { return ($hex + ': Windows Update zaman aşımına uğradı') }
        '0x800F0922' { return ($hex + ': işlem tamamlanamadı') }
        '0x800F080C' { return ($hex + ': Windows bu özellik adını tanımıyor') }
        '0x80070005' { return ($hex + ': erişim reddedildi (yönetici izni gerekir)') }
        '0x800F0831' { return ($hex + ': bileşen deposunda eksik paket var') }
        '0x800F082F' { return ($hex + ': Windows bekleyen bir işlem için yeniden başlatılmayı bekliyor') }
        '0x80070BC9' { return ($hex + ': önceki bir kurulum yeniden başlatma bekliyor') }
        '0x800F0806' { return ($hex + ': bekleyen bir bileşen işlemi var; önce bilgisayarı yeniden başlatın') }
        '0x800F0912' { return ($hex + ': özelliğin dosyaları bu bilgisayarda yok; Windows Update’ten indirilmesi gerekiyor') }
        '0x800F0915' { return ($hex + ': özelliğin içeriği hiçbir kaynakta bulunamadı') }
        '0x800F0950' { return ($hex + ': bu Windows sürümü için isteğe bağlı içerik bulunamadı') }
        '0x80240438' { return ($hex + ': Windows Update hizmetine ulaşılamadı (ağ, güvenlik duvarı ya da vekil sunucu)') }
        '0x0000371B' { return ($hex + ': Windows bileşen kurulum adımı başarısız oldu (çoğunlukla bekleyen bir değişiklik yüzünden)') }
    }
    return ('kod ' + $hex)
}

# dism.exe'yi ayrı süreçte, süre sınırıyla çalıştırır. Dönüş: çıkış kodu (-1: süre doldu, süreç kapatıldı)
function Invoke-DismExe([string[]]$DismArgs, [int]$LimitMin = 0) {
    if ($LimitMin -le 0) { $LimitMin = $script:DismLimitMin }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = Get-DismExePath
    $psi.Arguments = ($DismArgs -join ' ')
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    if ($null -eq $p) { throw 'dism.exe başlatılamadı.' }
    if (-not $p.WaitForExit($LimitMin * 60000)) {
        # asılı kalan DISM ve yardımcı süreci (DismHost.exe) kapatılır; işlem bileşen servisinde tamamlanmamışsa geri sarılır
        try { foreach ($ch in @(Get-CimInstance -ClassName Win32_Process -Filter ('ParentProcessId=' + [string]$p.Id) -ErrorAction Stop)) { try { Stop-Process -Id ([int]$ch.ProcessId) -Force -ErrorAction Stop } catch { } } } catch { }
        try { $p.Kill() } catch { }
        try { [void]$p.WaitForExit(5000) } catch { }
        $script:DismTimedOut = $true
        return -1
    }
    return [int]$p.ExitCode
}

# Bileşen servisi (CBS) yeniden başlatma bekliyor mu? Dönüş: '' ya da bekleyen anahtarın adı. Bekleyen işlem varken
# DISM bileşen deposu temizliği 0x800F0806 ile başarısız olur (cihazda 18.11.2026).
# Bu DISM kodu kaynak eksikliği değil, bekleyen bir değişiklik / yeniden başlatma gereği mi? O zaman Windows Update kaynağıyla
# ikinci deneme işe yaramaz (cihazda 0x371B iki kaynakta da aynı geldi); hemen yeniden başlatma önerilir.
function Test-DismRebootCode([int64]$Code) {
    if ($Code -eq 0 -or $Code -eq -1 -or $Code -eq 3010) { return $false }
    $hex = '0x' + ([uint32]($Code -band 0xFFFFFFFFL)).ToString('X8')
    return (@('0x800F0806', '0x800F082F', '0x80070BC9', '0x0000371B') -contains $hex)
}

function Get-CbsRebootPending {
    try {
        $cbs = Get-RegSubKeyNames 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing'
        foreach ($k in @('RebootPending', 'RebootInProgress', 'PackagesPending')) { if ($cbs -contains $k) { return $k } }
    } catch { }
    return ''
}

# Bu oturumda bir DISM süre sınırını aştıysa yeni DISM işlemi başlatılmaz (bileşen hizmeti hâlâ çalışıyor olabilir)
function Assert-DismReady {
    if ($script:DismTimedOut) { throw 'önceki bir DISM işlemi süre sınırını aştı; Windows bileşen hizmeti hâlâ çalışıyor olabilir. Bilgisayarı yeniden başlatıp tekrar deneyin.' }
}

# Windows özelliğini açar/kapatır (dism.exe, süre sınırlı). Dönüş: $true = yeniden başlatma gerekiyor. Başarısızlıkta açıklamalı hata atar.
function Set-WinFeatureState([string]$Name, [bool]$On) {
    if ($Name -cnotmatch '^[A-Za-z0-9\.\-_]{2,120}$') { throw ('Geçersiz Windows özelliği adı: ' + $Name) }
    Assert-DismReady
    if (-not $On) {
        $rc = Invoke-DismExe @('/Online', '/Disable-Feature', ('/FeatureName:' + $Name), '/NoRestart', '/Quiet')
        if ($rc -eq 0) { return $false }
        if ($rc -eq 3010) { return $true }
        throw ('Windows özelliği kapatılamadı (' + $Name + '): ' + (Get-DismCodeText $rc))
    }
    $rc = Invoke-DismExe @('/Online', '/Enable-Feature', ('/FeatureName:' + $Name), '/All', '/NoRestart', '/LimitAccess', '/Quiet')
    if ($rc -eq 0) { return $false }
    if ($rc -eq 3010) { return $true }
    $first = Get-DismCodeText $rc
    # yerel deneme süre sınırını aştıysa bileşen hizmeti meşguldür: Windows Update kaynağıyla ikinci bir uzun deneme yapılmaz
    if (Test-DismRebootCode $rc) { $script:DismNeedsReboot = $true }
    if ($rc -eq -1 -or (Test-DismRebootCode $rc)) { throw ('Windows özelliği açılamadı (' + $Name + '): ' + $first + '. Bilgisayarı yeniden başlatıp tekrar deneyin.') }
    $busy = Get-ServicingBusy
    if ($busy -ne '') { throw ('Windows özelliği açılamadı (' + $Name + '): ' + $first + '. ' + $busy + '; güncelleme bitince (gerekirse yeniden başlatıp) tekrar deneyin.') }
    Write-WhLog ('Yerel kaynak yetmedi (' + $first + '); Windows Update kaynağı deneniyor: ' + $Name) 'INFO'
    $rc2 = Invoke-DismExe @('/Online', '/Enable-Feature', ('/FeatureName:' + $Name), '/All', '/NoRestart', '/Quiet')
    if ($rc2 -eq 0) { return $false }
    if ($rc2 -eq 3010) { return $true }
    if (Test-DismRebootCode $rc2) { $script:DismNeedsReboot = $true }
    throw ('Windows özelliği açılamadı (' + $Name + '): yerel kaynak ' + $first + '; Windows Update kaynağı ' + (Get-DismCodeText $rc2) + '. Bilgisayarı yeniden başlatıp tekrar deneyin.')
}

# Windows bileşenini (isteğe bağlı özellik / FOD) kaldırır ya da kurar (dism.exe, süre sınırlı). Dönüş: $true = yeniden başlatma gerekiyor
function Set-WinCapabilityState([string]$Name, [bool]$Present) {
    if ($Name -cnotmatch '^[A-Za-z0-9\.\-_~]{3,160}$') { throw ('Geçersiz Windows bileşeni adı: ' + $Name) }
    Assert-DismReady
    if (-not $Present) {
        $rc = Invoke-DismExe @('/Online', '/Remove-Capability', ('/CapabilityName:' + $Name), '/NoRestart', '/Quiet')
        if ($rc -eq 0) { return $false }
        if ($rc -eq 3010) { return $true }
        throw ('Windows bileşeni kaldırılamadı (' + $Name + '): ' + (Get-DismCodeText $rc))
    }
    $rc = Invoke-DismExe @('/Online', '/Add-Capability', ('/CapabilityName:' + $Name), '/LimitAccess', '/NoRestart', '/Quiet')
    if ($rc -eq 0) { return $false }
    if ($rc -eq 3010) { return $true }
    $first = Get-DismCodeText $rc
    if (Test-DismRebootCode $rc) { $script:DismNeedsReboot = $true }
    if ($rc -eq -1 -or (Test-DismRebootCode $rc)) { throw ('Windows bileşeni kurulamadı (' + $Name + '): ' + $first + '. Bilgisayarı yeniden başlatıp tekrar deneyin.') }
    $busy = Get-ServicingBusy
    if ($busy -ne '') { throw ('Windows bileşeni kurulamadı (' + $Name + '): ' + $first + '. ' + $busy + '; güncelleme bitince tekrar deneyin.') }
    Write-WhLog ('Yerel kaynak yetmedi (' + $first + '); Windows Update kaynağı deneniyor: ' + $Name) 'INFO'
    $rc2 = Invoke-DismExe @('/Online', '/Add-Capability', ('/CapabilityName:' + $Name), '/NoRestart', '/Quiet')
    if ($rc2 -eq 0) { return $false }
    if ($rc2 -eq 3010) { return $true }
    if (Test-DismRebootCode $rc2) { $script:DismNeedsReboot = $true }
    throw ('Windows bileşeni kurulamadı (' + $Name + '): yerel kaynak ' + $first + '; Windows Update kaynağı ' + (Get-DismCodeText $rc2) + '. İnternet bağlantısını denetleyip tekrar deneyin.')
}

# Windows isteğe bağlı özelliğinin durumu. DISM (Get-WindowsOptionalFeature) yönetici ister; yönetici değilken ya da DISM
# okuyamazsa Win32_OptionalFeature (WMI, standart kullanıcıya açık) kullanılır. Dönüş: $null = bu sürümde yok; aksi halde
# FeatureName/State taşıyan nesne (State: Enabled, Disabled, DisabledWithPayloadRemoved...). Okunamazsa hata fırlatır.
$script:WmiFeatState = @{ 1 = 'Enabled'; 2 = 'Disabled'; 3 = 'DisabledWithPayloadRemoved' }
function Get-WinFeatureWmi([string]$Name) {
    if ($Name -cnotmatch '^[A-Za-z0-9\.\-_]{2,120}$') { throw ('Geçersiz Windows özelliği adı: ' + $Name) }
    $b = $script:StateBatch
    $st = $null
    if ($null -ne $b) {
        if ($null -eq $b.Feat) {
            $m = @{}
            foreach ($x in @(Get-CimInstance -ClassName Win32_OptionalFeature -ErrorAction Stop)) { if ($null -ne $x) { $m[[string]$x.Name] = [int]$x.InstallState } }
            $b.Feat = $m
        }
        if (-not $b.Feat.ContainsKey($Name)) { return $null }
        $st = [int]$b.Feat[$Name]
    } else {
        $q = @(Get-CimInstance -ClassName Win32_OptionalFeature -Filter ("Name='" + $Name + "'") -ErrorAction Stop | Where-Object { $null -ne $_ })
        if ($q.Count -eq 0) { return $null }
        $st = [int]$q[0].InstallState
    }
    if (-not $script:WmiFeatState.ContainsKey($st)) { throw ('Windows özelliğinin durumu belirsiz (' + $Name + ', InstallState=' + $st + ')') }
    return [pscustomobject]@{ FeatureName = $Name; State = [string]$script:WmiFeatState[$st]; Source = 'wmi' }
}

function Get-WinFeatureInfo([string]$Name) {
    $err = ''
    $b = $script:StateBatch
    $skipDism = ((-not [bool]$script:IsAdmin) -or ($null -ne $b -and [bool]$b.FeatDismBad))
    if (-not $skipDism) {
        try { return (Get-WindowsOptionalFeature -Online -FeatureName $Name -ErrorAction Stop) }
        catch { $err = $_.Exception.Message; if ($null -ne $b) { $b.FeatDismBad = $true } }
    }
    try { return (Get-WinFeatureWmi $Name) }
    catch {
        if ($err -eq '') { $err = $_.Exception.Message } else { $err = $err + ' / WMI: ' + $_.Exception.Message }
        throw $err
    }
}
