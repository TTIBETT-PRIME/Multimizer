# ==================================================================
#  AYARLARI SIFIRLA (arayuz): Ayarlar > Sifirlama karti ve yeni gorunum bilgisi
#  Gorunum kapsami anlik uygulanir (hazir gorunum "Varsayilan" + ana ekran bicimi); Tercihler kapsami ayarlari yazar ve uygulamayi yeniden baslatir.
#  Her sifirlamadan once ayarlarin kopyasi saklanir (bkz. 143_settings_reset_core.ps1); "Son sifirlamayi geri al" kopyayi geri yukler.
# ==================================================================
$script:ResetPending = ''
$script:ResetUndoPath = ''
$script:LookNoticeTimer = $null
$script:LookNoticeTicks = 0

# Kapsam listesini doldurur (bir kez, sayfa kurulurken)
function Initialize-StReset {
    if ($null -eq $ui.st_ResetScope) { return }
    $ch = New-Object System.Collections.ArrayList
    [void]$ch.Add((New-Choice 'Gorunum' 'Yalnızca görünüm'))
    [void]$ch.Add((New-Choice 'Tercihler' 'Tüm uygulama tercihleri'))
    [void]$ch.Add((New-Choice 'Fabrika' 'Her şey: tercihler ve Windows’ta yapılan değişiklikler'))
    Set-ComboChoices $ui.st_ResetScope $ch.ToArray()
}

# Kapsam notunu, geri alma dugmesini ve son sifirlama satirini gunceller
function Update-StReset {
    if ($null -eq $ui.st_ResetScope) { return }
    $scope = Get-ComboKey $ui.st_ResetScope
    if ($scope -eq '') { $scope = 'Gorunum' }
    if ($scope -eq 'Fabrika') {
        $ui.st_ResetNote.Text = 'Multimizer’ın bu bilgisayarda yaptığı ve geri alınabilen bütün değişiklikler (ayarlar, hizmetler, görevler, güç) yeniden eskiye doğru geri alınır; ardından uygulamanın tüm ayarları varsayılana döner ve uygulama yeniden başlar. Silinen dosyalar ve kaldırılan uygulamalar geri gelmez.'
    } elseif ($scope -eq 'Tercihler') {
        $ui.st_ResetNote.Text = 'Görünüme ek olarak dil, kullanım kipi, bildirimler, tepsi davranışı, izleme aralığı, günlük saklama süresi, güvenli silme geçiş sayısı ve ana ekran pano düzeni sıfırlanır. Uygulama yeniden başlatılır.'
    } else {
        $ui.st_ResetNote.Text = 'Tema, yerleşim, yakınlaştırma, tasarım, saydamlık, ana ekran biçimi, hareket ve kaydırma seçenekleri ile mini izleyici konumu sıfırlanır. Değişiklik hemen uygulanır; yeniden başlatma gerekmez.'
    }
    $bk = @(Get-ResetBackups)
    $ui.st_ResetUndo.IsEnabled = ($bk.Count -gt 0)
    if ($bk.Count -eq 0) {
        $ui.st_ResetState.Text = 'Henüz sıfırlama yapılmadı.'
    } else {
        $when = ([datetime]$bk[0].Time).ToString('dd.MM.yyyy HH:mm')
        if ([string]$bk[0].Scope -eq 'fabrika') { $ui.st_ResetState.Text = (Format-Tr 'Son sıfırlama: {0} (her şey)' $when) }
        elseif ([string]$bk[0].Scope -eq 'tercihler') { $ui.st_ResetState.Text = (Format-Tr 'Son sıfırlama: {0} (uygulama tercihleri)' $when) }
        else { $ui.st_ResetState.Text = (Format-Tr 'Son sıfırlama: {0} (görünüm)' $when) }
    }
}

function Load-StReset {
    if ($null -eq $ui.st_ResetScope) { return }
    if ((Get-ComboKey $ui.st_ResetScope) -eq '') { [void](Select-ComboKey $ui.st_ResetScope 'Gorunum') }
    Update-StReset
}

# Onaydan sonra: kopya alinir, sonra kapsama gore sifirlanir
function Complete-StReset([string]$Scope) {
    $tag = 'gorunum'
    if ($Scope -eq 'Tercihler') { $tag = 'tercihler' }
    if ($Scope -eq 'Fabrika') { $tag = 'fabrika' }
    $bk = Save-SettingsBackup $script:Settings $tag
    if ($bk -eq '') { Show-Toast 'Ayar kopyası yazılamadı; sıfırlama yapılmadı.' 'bad'; return }
    $def = Get-DefaultSettings
    if ($Scope -eq 'Fabrika') {
        # once Windows'taki degisiklikler geri alinir (arka planda), sonra ayarlar sifirlanir ve uygulama yeniden baslar
        [void](Start-Async 'UndoAll' 'Job_UndoAll' @{} {
            param($r)
            Invoke-Safe {
                if ($null -eq $r) { Show-Toast 'Değişiklikler geri alınamadı; ayarlar sıfırlanmadı. Ayrıntı günlükte.' 'bad'; return }
                $script:Settings = Get-Settings
                $res = Get-ResetResult $script:Settings 'Fabrika'
                foreach ($k in @($res.Settings.Keys)) { $script:Settings[[string]$k] = $res.Settings[$k] }
                Save-Settings $script:Settings
                if ([int]$r.Errors -gt 0) { Write-WhLog (Format-Tr 'Tümünü geri alma: {0} işlem geri alınamadı; ayrıntı yukarıda.' ([int]$r.Errors)) 'WARN' }
                if (Restart-App) { Exit-App } else { Show-Toast 'Her şey sıfırlandı. Uygulama yeniden başlatılamadı; kapatıp elle açın.' 'warn' }
            } 'Sıfırlama'
        } 'Tüm değişiklikler geri alınıyor')
        return
    }
    if ($Scope -eq 'Tercihler') {
        $r = Get-ResetResult $script:Settings 'Tercihler'
        foreach ($k in @($r.Settings.Keys)) { $script:Settings[[string]$k] = $r.Settings[$k] }
        Save-Settings $script:Settings
        if (Restart-App) { Exit-App } else { Show-Toast 'Uygulama yeniden başlatılamadı; kapatıp elle açın. Sıfırlanan ayarlar bir sonraki açılışta geçerli olur.' 'warn' }
        return
    }
    # Gorunum: anahtarlar varsayilana yazilir, hazir gorunum (tema, yerlesim, tasarim, saydamlik, yakinlastirma) ve ana ekran bicimi anlik uygulanir
    foreach ($k in @('ReduceMotion', 'SmoothScroll', 'ToTopButton', 'FocusRing', 'WidgetCorner', 'WidgetOpacity', 'WidgetX', 'WidgetY')) { $script:Settings[$k] = $def[$k] }
    Apply-LookPreset 'Varsayilan'
    [void](Select-HomeMode ([string]$def.HomeMode))
    $script:Settings.LookVersion = 10
    $script:Settings.LookNotice = $false
    Save-Settings $script:Settings
    try { Update-StReset } catch { }
    Show-Toast 'Görünüm varsayılan değerlere döndürüldü.' 'good'
}

function Invoke-StResetRun {
    $scope = Get-ComboKey $ui.st_ResetScope
    if ($scope -eq '') { $scope = 'Gorunum' }
    $script:ResetPending = $scope
    $danger = $false
    if ($scope -eq 'Fabrika') {
        $danger = $true
        $nj = @(Get-UndoableJournals ([string]$sync.BackupDir)).Count
        $txt = (Format-Tr 'Multimizer’ın bu bilgisayarda yaptığı geri alınabilir bütün değişiklikler ({0} kayıt dosyası) geri alınacak, ardından uygulamanın tüm ayarları varsayılana dönecek ve uygulama yeniden başlatılacak. Silinen dosyalar ve kaldırılan uygulamalar geri gelmez. Önceki ayarlarınızın kopyası saklanır.' $nj)
    } elseif ($scope -eq 'Tercihler') {
        $danger = $true
        $txt = 'Tüm uygulama tercihleri varsayılan değerlere döndürülecek ve uygulama yeniden başlatılacak. Windows üzerinde yapılan değişiklikler, zamanlanmış görevler, yedekleme ayarları ve ağ koruması değişmez. Önceki ayarlarınızın kopyası saklanır.'
    } else {
        $txt = 'Görünüm varsayılan değerlere döndürülecek: beyaz tema, sade yerleşim, %100 yakınlaştırma, klasik tasarım. Önceki ayarlarınızın kopyası saklanır; Ayarlar > Sıfırlama bölümünden geri alabilirsiniz.'
    }
    Show-Confirm 'Ayarları sıfırla' $txt 'Sıfırla' {
        Invoke-Safe {
            $sc = [string]$script:ResetPending
            $script:ResetPending = ''
            if ($sc -eq '') { return }
            Complete-StReset $sc
        } 'Sıfırlama'
    } $danger
}

function Invoke-StResetUndo {
    $bk = @(Get-ResetBackups)
    if ($bk.Count -eq 0) { Show-Toast 'Geri alınacak bir ayar kopyası yok.' 'info'; return }
    $script:ResetUndoPath = [string]$bk[0].Path
    Show-Confirm 'Son sıfırlamayı geri al' 'Son sıfırlamadan önceki ayarlar geri yüklenecek ve uygulama yeniden başlatılacak.' 'Geri yükle' {
        Invoke-Safe {
            $p = [string]$script:ResetUndoPath
            $script:ResetUndoPath = ''
            if ($p -eq '') { return }
            if (Restore-SettingsFromBackup $p $script:Settings) {
                $script:Settings = Get-Settings
                if (Restart-App) { Exit-App } else { Show-Toast 'Uygulama yeniden başlatılamadı; kapatıp elle açın.' 'warn' }
            } else {
                Show-Toast 'Ayar kopyası okunamadı; geri alma yapılmadı.' 'bad'
            }
        } 'Sıfırlama'
    }
}

function Init-StReset {
    if ($null -eq $ui.st_ResetScope) { return }
    $ui.st_ResetScope.Add_SelectionChanged({
        if ($script:StLoading) { return }
        Invoke-Safe { Update-StReset } 'Sıfırlama'
    })
    $ui.st_ResetRun.Add_Click({ Invoke-Safe { Invoke-StResetRun } 'Sıfırlama' })
    $ui.st_ResetUndo.Add_Click({ Invoke-Safe { Invoke-StResetUndo } 'Sıfırlama' })
    $ui.st_ResetFolder.Add_Click({
        Invoke-Safe {
            $d = Get-SettingsBackupDir
            if (-not (Test-Path -LiteralPath $d -PathType Container)) { [void](New-Item -ItemType Directory -Path $d -Force) }
            Open-Folder $d
        } 'Sıfırlama'
    })
}

# Gorunum eski varsayilandan yeni varsayilana (beyaz, sade) tasindiysa pencere gorununce bir kez bilgi verilir
function Initialize-LookNotice {
    if ($script:SmokeMode -eq $true) { return }
    if ($script:Settings.LookNotice -ne $true) { return }
    $script:LookNoticeTicks = 0
    $script:LookNoticeTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:LookNoticeTimer.Interval = [TimeSpan]::FromSeconds(2)
    $script:LookNoticeTimer.Add_Tick({
        try {
            $script:LookNoticeTicks++
            if ($script:LookNoticeTicks -gt 30) { $script:LookNoticeTimer.Stop(); return }
            if (-not $script:Win.IsVisible) { return }
            if ($ui.Overlay.Visibility -eq $script:VisOn) { return }
            $script:LookNoticeTimer.Stop()
            $script:Settings.LookNotice = $false
            Save-Settings $script:Settings
            Show-Toast 'Görünüm güncellendi: varsayılan tema beyaz ve sade oldu. Önceki görünüme Ayarlar > Sıfırlama bölümünden dönebilirsiniz.' 'info'
        } catch { Write-CrashLog ('LookNotice: ' + $_.Exception.Message) }
    })
    $script:LookNoticeTimer.Start()
}
