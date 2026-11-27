# ==================================================================
#  KURULUM TEKLIFI (arayuz): uygulama kurulu degilken ilk acilista "kurulsun mu?" diye sorar.
#  "Kur" secilirse sira sudur: (1) eksik bilesenler denetlenir, (2) eksikler winget ile kurulur, (3) uygulama kalici klasore kopyalanir ve kisayollar eklenir.
#  Bilesen kurulumu basarisiz olsa da uygulama kurulur; eksik kalanlar Cozum Merkezi > Hazirlik sekmesinde gorunur.
#  "Kurmadan kullan" secilirse bir daha sorulmaz (Ayarlar > Kur her zaman kullanilabilir). Pencere kapatilirsa sonraki acilista yeniden sorulur.
# ==================================================================
$script:SetupTimer = $null
$script:SetupPkgs = @()

# Saf: kurulum teklifi gosterilmeli mi?
function Test-InstallOfferNeeded($Settings, [string]$ScriptPath, [string]$InstallDir, [bool]$Smoke) {
    if ($Smoke -or $null -eq $Settings) { return $false }
    if ($Settings.Installed -eq $true -or $Settings.InstallAsked -eq $true) { return $false }
    if ([string]$ScriptPath -eq '' -or [string]$InstallDir -eq '') { return $false }
    # Klasor adi elle ayrilir: yol ayiricisi hem \ hem / olabilir
    $norm = ([string]$ScriptPath).Replace('/', '\')
    $cut = $norm.LastIndexOf('\')
    if ($cut -le 0) { return $false }
    $here = $norm.Substring(0, $cut).TrimEnd('\')
    $inst = ([string]$InstallDir).Replace('/', '\').TrimEnd('\')
    if ([string]::Equals($here, $inst, [System.StringComparison]::OrdinalIgnoreCase)) { return $false }
    return $true
}

# Saf: kurulacak bilesenlerin ozeti (onay metni icin)
function Get-SetupDepsText($Pkgs) {
    $pk = @($Pkgs | Where-Object { $null -ne $_ })
    if ($pk.Count -eq 0) { return 'Eksik bileşen yok.' }
    return ((@($pk | ForEach-Object { [string]$_.Name }) -join ', '))
}

function Show-InstallOffer {
    $opts = @(
        @{ Key = 'install'; Title = 'Kur (önerilir)'; Detail = 'Önce eksik bileşenler (Visual C++, .NET, DirectX) denetlenir ve winget deposundan kurulur; sonra uygulama kalıcı klasöre kopyalanır, Başlat menüsüne ve masaüstüne kısayol eklenir. Zamanlanmış bakım, yedekleme ve rapor kurulumla kullanılabilir.' },
        @{ Key = 'portable'; Title = 'Kurmadan kullan'; Detail = 'Uygulama bulunduğu klasörden çalışır; bilgisayara dosya kopyalanmaz ve kısayol eklenmez. İstediğiniz zaman Ayarlar > Kur ile kurabilirsiniz.' }
    )
    Show-Choice 'Multimizer bu bilgisayara kurulsun mu?' 'Kurulum yalnızca bu bilgisayarda kalır: hesap açılmaz, internete veri gönderilmez. Kaldırmak için Ayarlar > Kurulumu kaldır yeterlidir.' $opts 'Daha sonra sor' {
        param($key)
        if ([string]$key -eq 'install') { Start-SetupInstall }
        elseif ([string]$key -eq 'portable') { Set-SettingsKeys @{ InstallAsked = $true }; Show-Toast 'Kurmadan kullanılıyor. Ayarlar > Kur ile dilediğiniz zaman kurabilirsiniz.' 'info' }
    }
}

# 1) bilesen denetimi
function Start-SetupInstall {
    Set-SettingsKeys @{ InstallAsked = $true }
    $ok = Start-Async 'SetupPrep' 'Job_PrepCheck' @{} {
        param($r)
        Invoke-Safe {
            $pk = @()
            if ($null -ne $r -and $r.Ok -eq $true) {
                try {
                    # Get-PrepInstallList diziyi tek nesne olarak dondurur; once degiskene alinir, sonra suzulur
                    $all = Get-PrepInstallList (Get-PrepItems $r.State $false)
                    $pk = @(@($all) | Where-Object { $null -ne $_ -and (Test-PrepPackage ([string]$_.Id)) -eq '' })
                } catch { $pk = @() }
            } else { Write-WhLog 'Bileşen denetimi yapılamadı; uygulama kurulumu sürüyor.' 'WARN' }
            if ($pk.Count -gt 0) { Start-SetupDeps $pk } else { Write-WhLog 'Eksik bileşen yok.' 'OK'; Start-SetupCopy }
        } 'Kurulum'
    } 'Kurulum 1/3: bileşenler denetleniyor'
    if (-not $ok) { Show-Toast 'Kurulum başlatılamadı; süren işlem bitince Ayarlar > Kur ile yeniden deneyin.' 'warn' }
}

# 2) eksik bilesenler
function Start-SetupDeps($Pkgs) {
    $script:SetupPkgs = @($Pkgs)
    Write-WhLog ('Eksik bileşenler: ' + (Get-SetupDepsText $script:SetupPkgs)) 'INFO'
    $ids = @($script:SetupPkgs | ForEach-Object { [string]$_.Id })
    $ok = Start-Async 'SetupDeps' 'Job_PrepInstall' @{ Ids = $ids } {
        param($r)
        Invoke-Safe {
            $script:PrepState = $null
            if ($null -eq $r -or [int]$r.Failed -gt 0 -or [string]$r.Error -ne '') {
                Write-WhLog 'Bazı bileşenler kurulamadı; uygulama yine de kurulacak. Eksik kalanlar Çözüm Merkezi > Hazırlık sekmesinde görünür.' 'WARN'
            }
            Start-SetupCopy
        } 'Kurulum'
    } 'Kurulum 2/3: eksik bileşenler kuruluyor'
    if (-not $ok) { Start-SetupCopy }
}

# 3) uygulama dosyalari ve kisayollar
function Start-SetupCopy {
    [void](Start-Async 'Install' 'Job_Install' @{ Desktop = $true } {
        param($r)
        Invoke-Safe {
            if ($null -ne $r -and $r.Ok -eq $true) {
                $script:Settings = Get-Settings
                Show-Toast 'Kurulum tamamlandı. Multimizer artık Başlat menüsünden ve masaüstündeki kısayoldan açılır.' 'good'
            } else { Show-Toast 'Kurulum tamamlanamadı; ayrıntı günlükte. Ayarlar > Kur ile yeniden deneyebilirsiniz.' 'bad' }
            try { if ($null -ne $ui.st_InstState) { Update-StInstall } } catch { }
        } 'Kurulum'
    } 'Kurulum 3/3: uygulama kuruluyor')
}

# Pencere gorununce bir kez sorar (ilk acilis sorusundan once). Duman testinde ve kurulu kopyada sorulmaz.
function Initialize-InstallOffer {
    $need = $false
    try { $need = Test-InstallOfferNeeded $script:Settings ([string]$sync.ScriptPath) (Get-InstallDir) ([bool]$script:SmokeMode) } catch { $need = $false }
    if (-not $need) { return }
    $script:SetupTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:SetupTimer.Interval = [TimeSpan]::FromMilliseconds(1500)
    $script:SetupTimer.Add_Tick({
        try {
            if (-not $script:Win.IsVisible) { return }
            if ($ui.Overlay.Visibility -eq $script:VisOn -or $null -ne $script:Cur) { return }
            $script:SetupTimer.Stop()
            if (Test-InstallOfferNeeded $script:Settings ([string]$sync.ScriptPath) (Get-InstallDir) ([bool]$script:SmokeMode)) { Show-InstallOffer }
        } catch { try { $script:SetupTimer.Stop() } catch { }; Write-CrashLog ('Kurulum teklifi: ' + $_.Exception.Message) }
    })
    $script:SetupTimer.Start()
}
