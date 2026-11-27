# ==================================================================
#  ÇÖZÜM MERKEZİ: "Hazırlık" sekmesi
#  Multimizer’ın ve araçlarının çalışması için gereken bileşenleri (PowerShell, .NET Framework, C# derleyicisi, Visual C++, DirectX, winget,
#  boş alan, WMI, eklentiler) denetler. Denetim yalnızca okur; eksikler yalnızca onayınızla, Microsoft’un winget aracıyla ve paket özeti
#  doğrulanarak kurulur. Toplama ve kurulum işleri 127_prep_core.ps1 içindedir; burada satırlar, onaylar ve sonuç iletileri var.
# ==================================================================
$script:PrepState = $null
$script:PrepItems = @()
$script:PrepLoading = $false
$script:PrepPending = $null

function Get-PrepBr([string]$Status) {
    if ($Status -eq 'bad') { return 'BrBad' }
    if ($Status -eq 'warn') { return 'BrWarn' }
    if ($Status -eq 'ok') { return 'BrGood' }
    return 'BrInfo'
}

# Kurulum işinin sonucu -> bildirim: @{ Text; Kind (good | warn | bad) }
function Get-PrepInstallModel($R) {
    if ($null -eq $R) { return @{ Text = 'Kurulum tamamlanamadı; günlüğe bakın.'; Kind = 'bad' } }
    $done = [int](Get-JsonProp $R 'Done')
    $failed = [int](Get-JsonProp $R 'Failed')
    $reboot = ((Get-JsonProp $R 'Reboot') -eq $true)
    $items = @(@(Get-JsonProp $R 'Items') | Where-Object { $null -ne $_ })
    if ($R.Ok -eq $true) {
        $t = [string]$done + ' bileşen kuruldu.'
        $kind = 'good'
        if ($reboot) { $t += ' Etkili olması için bilgisayarı yeniden başlatın.'; $kind = 'warn' }
        return @{ Text = $t; Kind = $kind }
    }
    if ($R.Canceled -eq $true) { return @{ Text = 'Kurulum iptal edildi (' + [string]$done + ' bileşen kurulmuştu).'; Kind = 'warn' } }
    $why = [string](Get-JsonProp $R 'Error')
    $bad = @($items | Where-Object { $_.Ok -ne $true })
    if ($bad.Count -gt 0) {
        $parts = New-Object System.Collections.ArrayList
        foreach ($b in $bad) {
            if ($parts.Count -ge 2) { break }
            $nm = [string]$b.Id
            if ($script:PrepPackages.ContainsKey($nm)) { $nm = [string]$script:PrepPackages[$nm] }
            [void]$parts.Add($nm + ': ' + [string]$b.Text)
        }
        $why = ($parts.ToArray() -join '; ')
        if ($bad.Count -gt 2) { $why += ' (+' + [string]($bad.Count - 2) + ' bileşen daha)' }
    }
    if ($why -eq '') { $why = 'Kurulum tamamlanamadı; günlüğe bakın.' }
    $t = $why
    if ($done -gt 0) { $t = [string]$done + ' bileşen kuruldu, ' + [string]$failed + ' kurulamadı. ' + $why }
    return @{ Text = $t; Kind = 'bad' }
}

# ---------------- çizim ----------------
function Load-SlPrep {
    if ($script:PrepLoading -eq $true) { return }
    $script:PrepLoading = $true
    $ok = Start-Async 'PrepCheck' 'Job_PrepCheck' @{} {
        param($r)
        Complete-SlPrep $r
    } 'Hazırlık denetleniyor' $false $true
    if (-not $ok) { $script:PrepLoading = $false }
}

function Complete-SlPrep($R) {
    $script:PrepLoading = $false
    if ($null -eq $R -or $R.Ok -ne $true) { $script:PrepState = @{ Failed = $true } } else { $script:PrepState = $R.State }
    $script:PrepItems = @()
    if ([string]$script:UiState.Page -eq 'solve' -and $script:SlTab -eq 'prep') { Render-SlPrep }
}

$script:H_PrAct = { param($s, $e) Invoke-Safe { Invoke-PrepAction $s.Tag } 'Eylem' }

function Render-SlPrep {
    $ui.sl_List.Children.Clear()
    $S = $script:PrepState
    if ($null -eq $S) {
        Add-Note $ui.sl_List 'Hazırlık denetleniyor...'
        Load-SlPrep
        return
    }
    if ($S.Failed -eq $true) {
        Add-Note $ui.sl_List 'Denetim yapılamadı. “Denetle”ye basarak yeniden deneyin; sorun sürerse günlüğe bakın.' 'warn'
        return
    }
    $expert = ([string]$script:UiState.Mode -eq 'Expert')
    $script:PrepItems = Get-PrepItems $S $expert
    Add-Note $ui.sl_List 'Multimizer’ın ve araçlarının her bilgisayarda sorunsuz çalışması için gereken bileşenleri denetler. Denetim yalnızca okur. Eksikler yalnızca onayınızla, Microsoft’un winget aracıyla ve paket özeti doğrulanarak kurulur; internetten başka hiçbir şey indirilmez.'
    $sum = Get-PrepSummary $script:PrepItems
    $br = 'BrGood'
    if ($sum.Level -eq 'bad') { $br = 'BrBad' } elseif ($sum.Level -eq 'warn') { $br = 'BrWarn' }
    $fixList = Get-PrepInstallList $script:PrepItems
    $nFix = $fixList.Count
    $b1 = ''
    $sdata = @{ Do = '' }
    if ($nFix -gt 0) { $b1 = 'Eksikleri gider'; $sdata = @{ Do = 'FixAll' } }
    $srow = New-ItemRow @{ Title = 'Durum'; Detail = [string]$sum.Text; BrCol = $br; Btn1 = $b1 } $sdata $false $false
    if ($b1 -ne '') { $srow.FindName('Act').Add_Click($script:H_PrAct) }
    [void]$ui.sl_List.Children.Add($srow)
    $groups = @(@{ K = 'req'; T = 'Zorunlu bileşenler' }, @{ K = 'rec'; T = 'Önerilen bileşenler' }, @{ K = 'opt'; T = 'İsteğe bağlı bileşenler' })
    foreach ($g in $groups) {
        $rows = @($script:PrepItems | Where-Object { [string]$_.Group -eq [string]$g.K })
        if ($rows.Count -eq 0) { continue }
        Add-HeadRow $ui.sl_List ([string]$g.T)
        foreach ($it in $rows) {
            $lbl = ''
            $data = @{ Do = ''; Key = [string]$it.Key }
            if ($null -ne $it.Fix -and [string]$it.Status -ne 'ok') {
                $lbl = [string]$it.Fix.Label
                $data = @{ Key = [string]$it.Key }
                foreach ($fk in @($it.Fix.Keys)) { $data[$fk] = $it.Fix[$fk] }
            }
            $row = New-ItemRow @{ Title = [string]$it.Title; Detail = [string]$it.Detail; BrCol = (Get-PrepBr ([string]$it.Status)); Btn1 = $lbl } $data $false $false
            if ($lbl -ne '') { $row.FindName('Act').Add_Click($script:H_PrAct) }
            [void]$ui.sl_List.Children.Add($row)
        }
    }
    $ui.sl_Foot.Text = 'Denetlendi: ' + [string]$S.At + '  ·  Kurulumlardan sonra “Denetle”ye basarak sonucu doğrulayın.'
}

# ---------------- işlemler ----------------
function Invoke-PrepAction($T) {
    if ($null -eq $T) { return }
    switch ([string]$T.Do) {
        'Winget' { Start-PrepInstall @(@{ Id = [string]$T.Id; Name = [string]$T.Name }) }
        'FixAll' { Start-PrepFixAll }
        'Url'    { Open-Url ([string]$T.Url) }
        'Page'   { Open-Page ([string]$T.Page) ([string]$T.Sub) }
        'Wmi'    { Start-PrepWmi }
    }
}

# Pkgs: @( @{ Id; Name } ). Onay penceresinde neyin kurulacağı yazılır; onaylanmadan hiçbir şey indirilmez.
function Start-PrepInstall($Pkgs) {
    $pk = @($Pkgs | Where-Object { $null -ne $_ })
    if ($pk.Count -eq 0) { Show-Toast 'Kurulacak eksik bileşen yok.' 'info'; return }
    foreach ($x in $pk) {
        $why = Test-PrepPackage ([string]$x.Id)
        if ($why -ne '') { Show-Message 'Bu bileşen kurulamaz' $why; return }
    }
    $script:PrepPending = $pk
    $lines = @($pk | ForEach-Object { '•  ' + [string]$_.Name })
    $txt = 'Şu bileşenler Microsoft’un winget aracıyla kurulacak:' + "`r`n`r`n" + ($lines -join "`r`n") + "`r`n`r`n"
    $txt += '•  Paketler winget deposundan indirilir; paket özeti (SHA-256) winget tarafından doğrulanır, uyuşmazsa kurulmaz.' + "`r`n"
    $txt += '•  İnternet bağlantısı gerekir; kurulum birkaç dakika sürebilir. Ayarlarınıza ve kişisel dosyalarınıza dokunulmaz.' + "`r`n"
    $txt += '•  Bazı paketler kurulumdan sonra bilgisayarın yeniden başlatılmasını isteyebilir.'
    Show-Confirm 'Eksik bileşenleri kur' $txt 'Kur' {
        $ids = @($script:PrepPending | ForEach-Object { [string]$_.Id })
        [void](Start-Async 'PrepInstall' 'Job_PrepInstall' @{ Ids = $ids } {
            param($r)
            Complete-PrepInstall $r
        } 'Bileşenler kuruluyor')
    }
}

function Start-PrepFixAll {
    if ($null -eq $script:PrepState -or $script:PrepState.Failed -eq $true) { Show-Toast 'Önce denetimin bitmesini bekleyin.' 'warn'; return }
    $pk = Get-PrepInstallList $script:PrepItems
    Start-PrepInstall $pk
}

function Complete-PrepInstall($R) {
    $script:PrepState = $null
    $m = Get-PrepInstallModel $R
    Show-Toast ([string]$m.Text) ([string]$m.Kind)
    if ([string]$script:UiState.Page -eq 'solve' -and $script:SlTab -eq 'prep') { Render-SlPrep }
}

function Start-PrepWmi {
    $txt = 'WMI deposu Microsoft’un kendi aracıyla (winmgmt) doğrulanacak.' + "`r`n`r`n"
    $txt += '•  Depo tutarlıysa hiçbir şey değişmez.' + "`r`n"
    $txt += '•  Tutarsız çıkarsa “winmgmt /salvagerepository” ile onarılır; depodaki okunabilir veriler korunur ve WMI hizmeti kısa süre yeniden başlar.' + "`r`n"
    $txt += '•  İşlem bir dakikadan kısa sürer. Açık işlerinizi kaydetmeniz yeterli, yeniden başlatma gerekmez.'
    Show-Confirm 'WMI deposunu doğrula ve onar' $txt 'Çalıştır' {
        [void](Start-Async 'PrepWmi' 'Job_PrepWmi' @{} {
            param($r)
            Complete-PrepWmi $r
        } 'WMI deposu denetleniyor')
    }
}

function Complete-PrepWmi($R) {
    $script:PrepState = $null
    if ($null -eq $R) { Show-Toast 'WMI denetimi tamamlanamadı; günlüğe bakın.' 'bad' }
    else {
        $t = [string](Get-JsonProp $R 'Text')
        if ($t -eq '') { $t = 'WMI denetimi tamamlandı.' }
        if ($R.Ok -eq $true) { Show-Toast $t 'good' } else { Show-Toast $t 'bad' }
    }
    if ([string]$script:UiState.Page -eq 'solve' -and $script:SlTab -eq 'prep') { Render-SlPrep }
}

function Init-SlPrep {
    $ui.sl_PrCheck.Add_Click({ Invoke-Safe { $script:PrepState = $null; Render-SlPrep } 'Denetle' })
    $ui.sl_PrFix.Add_Click({ Invoke-Safe { Start-PrepFixAll } 'Eksikleri gider' })
}
