# ==================================================================
#  GÜNCELLEME DENETİMİ: arayüz (Ayarlar > Uygulama kartı)
#  Hiçbir şey kendiliğinden çalışmaz: “Güncellemeleri denetle”ye ve “İndir”e yalnızca siz basarsınız. İndirme ayrıca onay penceresinden geçer.
#  İndirilen ZIP açılmaz ve çalıştırılmaz; SHA-256 özeti bildirimdekiyle tutmazsa dosya silinir.
#  Aynı kartta “Dosya bütünlüğünü denetle” düğmesi, yan dosyaların (Eklenti, veri) derleme sırasında yazılan özetlerle tutup tutmadığına bakar.
# ==================================================================
$script:UpdLast = $null
$script:UpdBusy = $false
$script:UpdPending = $null
$script:UpdGot = ''
$script:UpdDone = $null
$script:IntBusy = $false

# Metin denetimine renk türüne göre yazar (good | warn | bad | dim)
function Set-StUpdText($Ctl, [string]$Text, [string]$Kind = 'dim') {
    $Ctl.Text = $Text
    $key = 'BrDim'
    if ($Kind -eq 'bad') { $key = 'BrBad' } elseif ($Kind -eq 'good') { $key = 'BrGood' } elseif ($Kind -eq 'warn') { $key = 'BrWarn' }
    $Ctl.Foreground = (Get-Br $key)
}

# Saf mantık: denetim sonucundan görünüm. R boşsa henüz denetlenmemiştir.
# Dönüş: @{ Text; Kind; CanGet; Page; Info }
function Get-UpdateStateModel($R, [string]$Current) {
    $m = @{ Text = ''; Kind = 'dim'; CanGet = $false; Page = ''; Info = $null }
    if ($null -eq $R) {
        $m.Text = 'Çalışan sürüm: ' + $Current + '. Güncelleme denetimi yalnızca “Güncellemeleri denetle”ye bastığınızda yapılır; uygulama kendiliğinden hiçbir adrese bağlanmaz.'
        return $m
    }
    if ((Get-JsonProp $R 'Ok') -ne $true) {
        $e = [string](Get-JsonProp $R 'Error')
        if ($e -eq '') { $e = 'bilinmeyen hata' }
        $m.Text = 'Denetim yapılamadı: ' + $e
        $m.Kind = 'bad'
        return $m
    }
    $info = Get-JsonProp $R 'Info'
    $latest = [string](Get-JsonProp $R 'Latest')
    $at = [string](Get-JsonProp $R 'At')
    $m.Info = $info
    $m.Page = [string](Get-JsonProp $info 'Page')
    $cmp = Compare-AppVersion $latest $Current
    if ($cmp -eq 1) {
        $m.Kind = 'warn'
        $t = 'Yeni sürüm var: ' + $latest + ' (çalışan: ' + $Current + ').'
        $notes = [string](Get-JsonProp $info 'Notes')
        if ($notes -ne '') { $t += "`r`n" + $notes }
        if ((Get-JsonProp $info 'Download') -eq $true) {
            $m.CanGet = $true
            $t += "`r`n" + 'İndirme hazır'
            $sz = [long](Get-JsonProp $info 'Size')
            if ($sz -gt 0) { $t += ' (' + (Format-Size $sz) + ')' }
            $t += '; “İndir”e bastığınızda önce onayınız istenir.'
        } else {
            $t += "`r`n" + 'İndirme kapalı: ' + [string](Get-JsonProp $info 'Why')
        }
        $m.Text = $t + "`r`n" + 'Denetlendi: ' + $at
        return $m
    }
    $m.Kind = 'good'
    if ($cmp -eq 0) { $m.Text = 'Güncelsiniz: çalışan sürüm (' + $Current + ') yayımlanan en son sürümle aynı.' }
    elseif ($cmp -eq -1) { $m.Text = 'Çalışan sürüm (' + $Current + '), yayımlanan en son sürümden (' + $latest + ') daha yeni; yapılacak bir şey yok.' }
    else { $m.Kind = 'warn'; $m.Text = 'Sürümler karşılaştırılamadı (çalışan: ' + $Current + ', yayımlanan: ' + $latest + ').' }
    $m.Text += ' Denetlendi: ' + $at
    return $m
}

# İndirme onay penceresinin metni
function Get-UpdateConfirmText($Info) {
    $b = [string][char]0x2022 + '  '
    $hostName = ''
    try { $hostName = (New-Object System.Uri([string](Get-JsonProp $Info 'Url'))).Host } catch { $hostName = '' }
    $t = 'Multimizer ' + [string](Get-JsonProp $Info 'Version') + ' indirilecek.' + "`r`n`r`n"
    $t += $b + 'Kaynak: ' + $hostName + ' (yalnızca HTTPS).' + "`r`n"
    $sz = [long](Get-JsonProp $Info 'Size')
    if ($sz -gt 0) { $t += $b + 'Boyut: ' + (Format-Size $sz) + "`r`n" }
    $t += $b + 'İndirilen dosyanın SHA-256 özeti bildirimdekiyle karşılaştırılır; tutmazsa dosya silinir.' + "`r`n"
    $t += $b + 'Dosya yalnızca indirilir; açılmaz, kurulmaz, çalıştırılmaz. Kurmak için ZIP’i kendiniz bir klasöre çıkarır, yeni sürümde Ayarlar > Uygulama > “Kur / güncelle”yi kullanırsınız.' + "`r`n"
    $t += $b + 'SHA-256 dosyanın bozulmadığını gösterir, yayıncının kimliğini kanıtlamaz; adresin güvendiğiniz kaynağa ait olduğundan emin olun.'
    return $t
}

# İndirme işinin sonucu -> görünüm: @{ Text; Kind; Path }
function Get-UpdateDoneModel($R) {
    if ($null -eq $R) { return @{ Text = 'İndirme tamamlanamadı. Ayarlar > İnternet istekleri bölümünde “Güncelleme denetimi ve indirme” kapalı olabilir; günlüğe bakın.'; Kind = 'bad'; Path = '' } }
    if ((Get-JsonProp $R 'Ok') -ne $true) {
        $e = [string](Get-JsonProp $R 'Error')
        if ($e -eq '') { $e = 'bilinmeyen hata' }
        return @{ Text = 'İndirilemedi: ' + $e; Kind = 'bad'; Path = '' }
    }
    $p = [string](Get-JsonProp $R 'Path')
    $t = 'İndirildi ve SHA-256 özeti doğrulandı: ' + $p
    if ((Get-JsonProp $R 'Already') -eq $true) { $t = 'Bu sürüm zaten indirilmiş ve özeti doğru: ' + $p }
    $sz = [long](Get-JsonProp $R 'Size')
    if ($sz -gt 0) { $t += ' (' + (Format-Size $sz) + ')' }
    $t += "`r`n" + 'ZIP’i bir klasöre çıkarın; yeni sürümü açıp Ayarlar > Uygulama > “Kur / güncelle”ye basın. Bu dosyaya Multimizer dokunmaz.'
    return @{ Text = $t; Kind = 'good'; Path = $p }
}

# Dosya bütünlüğü sonucu -> görünüm: @{ Text; Kind }
function Get-IntegrityModel($R, [bool]$Expert = $false) {
    if ($null -eq $R -or (Get-JsonProp $R 'Ok') -ne $true) {
        $e = [string](Get-JsonProp $R 'Error')
        if ($e -eq '') { $e = 'bilinmeyen hata' }
        return @{ Text = 'Denetlenemedi: ' + $e; Kind = 'bad' }
    }
    $total = [int](Get-JsonProp $R 'Total')
    $good = [int](Get-JsonProp $R 'Good')
    $bad = @(Get-JsonProp $R 'Bad' | Where-Object { $null -ne $_ })
    $m = @{ Text = ''; Kind = 'good' }
    if ($bad.Count -eq 0) {
        $m.Text = 'Yan dosyalar (Eklenti, veri) eksiksiz ve doğru: ' + [string]$good + ' / ' + [string]$total + '.'
    } else {
        $parts = New-Object System.Collections.ArrayList
        foreach ($b in $bad) {
            $why = 'özeti uyuşmuyor'
            $k = [string](Get-JsonProp $b 'Kind')
            if ($k -eq 'missing') { $why = 'yok' } elseif ($k -eq 'read') { $why = 'okunamadı' }
            [void]$parts.Add([string](Get-JsonProp $b 'Rel') + ' (' + $why + ')')
        }
        $m.Kind = 'warn'
        $m.Text = 'Sorunlu yan dosya: ' + ($parts.ToArray() -join ', ') + '. İlgili özellikler kullanılamayabilir; ZIP dosyasını eksiksiz yeniden çıkarın.'
    }
    $h = [string](Get-JsonProp $R 'ScriptSha256')
    if ($Expert -and $h -ne '') { $m.Text += "`r`n" + 'Betiğin SHA-256 özeti: ' + $h }
    $m.Text += "`r`n" + 'Denetlendi: ' + [string](Get-JsonProp $R 'At')
    return $m
}

# ---------------- görünüm ----------------
function Update-StUpdateView {
    $m = Get-UpdateStateModel $script:UpdLast ([string]$script:AppVersion)
    $text = [string]$m.Text
    $kind = [string]$m.Kind
    $d = $script:UpdDone
    if ($null -ne $d) {
        $text += "`r`n`r`n" + [string]$d.Text
        if ([string]$d.Kind -eq 'bad') { $kind = 'bad' }
    }
    Set-StUpdText $ui.st_UpdState $text $kind
    $busy = ($script:UpdBusy -eq $true)
    $ui.st_UpdCheck.IsEnabled = (-not $busy)
    $ui.st_UpdGet.IsEnabled = (-not $busy)
    if ($m.CanGet -eq $true) { $ui.st_UpdGet.Visibility = $script:VisOn } else { $ui.st_UpdGet.Visibility = $script:VisOff }
    if ([string]$m.Page -ne '') { $ui.st_UpdPage.Visibility = $script:VisOn } else { $ui.st_UpdPage.Visibility = $script:VisOff }
    if ([string]$script:UpdGot -ne '') { $ui.st_UpdFolder.Visibility = $script:VisOn } else { $ui.st_UpdFolder.Visibility = $script:VisOff }
    $ui.st_IntCheck.IsEnabled = ($script:IntBusy -ne $true)
}

function Load-StUpdate {
    $u = ''
    try { $u = [string]$script:Settings.UpdateUrl } catch { $u = '' }
    $ui.st_UpdUrl.Text = $u
    Update-StUpdateView
}

# Adres kutusundaki değeri doğrular ve kaydeder; geçersizse kaydetmez ve nedenini söyler
function Save-StUpdateUrl {
    $t = ([string]$ui.st_UpdUrl.Text).Trim()
    $cur = ''
    try { $cur = [string]$script:Settings.UpdateUrl } catch { $cur = '' }
    if ($t -eq $cur) { return $true }
    if ($t -ne '') {
        $why = Test-UpdateUrl $t
        if ($why -ne '') { Show-Toast $why 'warn'; return $false }
    }
    $script:Settings.UpdateUrl = $t
    Save-Settings $script:Settings
    $script:UpdLast = $null
    $script:UpdDone = $null
    Update-StUpdateView
    return $true
}

# ---------------- işlemler ----------------
function Start-UpdateCheck {
    if ($script:UpdBusy -eq $true) { return }
    if (-not (Save-StUpdateUrl)) { return }
    $url = ''
    try { $url = [string]$script:Settings.UpdateUrl } catch { $url = '' }
    $why = Test-UpdateUrl $url
    if ($why -ne '') { Show-Toast $why 'warn'; return }
    $script:UpdBusy = $true
    $script:UpdDone = $null
    Update-StUpdateView
    $ok = Start-Async 'UpdCheck' 'Job_UpdateCheck' @{ Url = $url; Current = [string]$script:AppVersion } {
        param($r)
        Complete-UpdateCheck $r
    } 'Güncelleme denetleniyor'
    if (-not $ok) { $script:UpdBusy = $false; Update-StUpdateView }
}

function Complete-UpdateCheck($R) {
    $script:UpdBusy = $false
    if ($null -eq $R) { $R = @{ Ok = $false; Error = 'İş sonuç döndürmedi. Ayarlar > İnternet istekleri bölümünde “Güncelleme denetimi ve indirme” kapalı olabilir; günlüğe bakın.' } }
    $script:UpdLast = $R
    $script:UpdDone = $null
    Update-StUpdateView
    $m = Get-UpdateStateModel $R ([string]$script:AppVersion)
    $first = ([string]$m.Text -split "\r?\n")[0]
    Show-Toast $first ([string]$m.Kind)
}

# Onay penceresi açılır; “İndir” denmeden hiçbir şey indirilmez
function Start-UpdateDownload {
    if ($script:UpdBusy -eq $true) { return }
    $m = Get-UpdateStateModel $script:UpdLast ([string]$script:AppVersion)
    if ($m.CanGet -ne $true -or $null -eq $m.Info) { Show-Toast 'Önce “Güncellemeleri denetle”ye basın; indirilebilir bir sürüm bulunamadı.' 'warn'; return }
    $script:UpdPending = $m.Info
    Show-Confirm 'Güncellemeyi indir' (Get-UpdateConfirmText $m.Info) 'İndir' {
        $i = $script:UpdPending
        if ($null -eq $i) { return }
        $script:UpdBusy = $true
        Update-StUpdateView
        $ok = Start-Async 'UpdDownload' 'Job_UpdateDownload' @{ Url = [string]$i.Url; Sha256 = [string]$i.Sha256; Version = [string]$i.Version; Size = [long]$i.Size } {
            param($r)
            Complete-UpdateDownload $r
        } 'Güncelleme indiriliyor'
        if (-not $ok) { $script:UpdBusy = $false; Update-StUpdateView }
    }
}

function Complete-UpdateDownload($R) {
    $script:UpdBusy = $false
    $script:UpdPending = $null
    $m = Get-UpdateDoneModel $R
    if ([string]$m.Path -ne '') { $script:UpdGot = [string]$m.Path }
    $script:UpdDone = @{ Text = [string]$m.Text; Kind = [string]$m.Kind }
    Update-StUpdateView
    Show-Toast ([string]($m.Text -split "\r?\n")[0]) ([string]$m.Kind)
}

function Start-IntegrityCheck {
    if ($script:IntBusy -eq $true) { return }
    $script:IntBusy = $true
    Update-StUpdateView
    $ok = Start-Async 'IntCheck' 'Job_IntegrityCheck' @{} {
        param($r)
        Complete-IntegrityCheck $r
    } 'Dosya bütünlüğü denetleniyor' $true
    if (-not $ok) { $script:IntBusy = $false; Update-StUpdateView }
}

function Complete-IntegrityCheck($R) {
    $script:IntBusy = $false
    $m = Get-IntegrityModel $R ([string]$script:UiState.Mode -eq 'Expert')
    Set-StUpdText $ui.st_IntState ([string]$m.Text) ([string]$m.Kind)
    Update-StUpdateView
    Show-Toast ([string]($m.Text -split "\r?\n")[0]) ([string]$m.Kind)
}

function Init-StUpdate {
    $ui.st_UpdUrl.Add_LostFocus({ if (-not $script:StLoading) { Invoke-Safe { [void](Save-StUpdateUrl) } 'Güncelleme' } })
    $ui.st_UpdCheck.Add_Click({ Invoke-Safe { Start-UpdateCheck } 'Güncelleme' })
    $ui.st_UpdGet.Add_Click({ Invoke-Safe { Start-UpdateDownload } 'Güncelleme' })
    $ui.st_UpdPage.Add_Click({
        Invoke-Safe {
            $m = Get-UpdateStateModel $script:UpdLast ([string]$script:AppVersion)
            $p = [string]$m.Page
            if ($p -ne '' -and (Test-UpdateUrl $p) -eq '') { Open-Url $p }
        } 'Sürüm sayfası'
    })
    $ui.st_UpdFolder.Add_Click({ Invoke-Safe { Open-Folder (Get-UpdateDir) } 'Klasör' })
    $ui.st_IntCheck.Add_Click({ Invoke-Safe { Start-IntegrityCheck } 'Bütünlük' })
}
