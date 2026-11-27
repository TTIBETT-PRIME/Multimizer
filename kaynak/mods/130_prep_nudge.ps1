# ==================================================================
#  AÇILIŞTA HAZIRLIK UYARISI
#  Her sürümün ilk açılışında bir kez, arka planda ve sessizce Hazırlık denetimi yapılır (yalnızca okuma; ağa çıkılmaz).
#  Zorunlu bir bileşen eksik ya da bozuksa bir onay penceresi, yalnızca önerilen bileşenler eksikse küçük bir bildirim gösterilir.
#  Hiçbir şey kurulmaz ya da değiştirilmez; kurulum yalnızca Çözüm Merkezi > Hazırlık sekmesinden, onayla yapılır.
#  İlk çalıştırma ekranı (kullanım amacı seçimi) açıksa, pencere gizliyse ya da başka bir iş sürüyorsa uygun ana kadar beklenir.
# ==================================================================
$script:PrepNudgeTimer = $null
$script:PrepNudgeTicks = 0

# Uyarıya konu olan satırlar. Yönetici hakkı, Sistem Koruması, internet ve isteğe bağlı bileşenler uyarı sebebi sayılmaz.
$script:PrepNudgeKeys = @('ps', 'net', 'csc', 'wmi', 'data', 'ext', 'os', 'winget', 'space')

function Test-PrepNudgeKey([string]$Key) {
    if ($script:PrepNudgeKeys -contains $Key) { return $true }
    if ($Key.StartsWith('vc', [StringComparison]::Ordinal)) { return $true }
    return $false
}

# Başlık listesi tek satıra: ilk Max başlık, kalanı sayı olarak
function Get-PrepNudgeNames($Titles, [int]$Max = 2) {
    $all = @($Titles | Where-Object { [string]$_ -ne '' })
    $take = New-Object System.Collections.ArrayList
    foreach ($t in $all) { if ($take.Count -ge $Max) { break }; [void]$take.Add([string]$t) }
    $s = ($take.ToArray() -join ', ')
    $more = $all.Count - $take.Count
    if ($more -gt 0) { $s += ' ve ' + [string]$more + ' bileşen daha' }
    return $s
}

# Saf mantık: denetim sonucundan uyarı kararı.
# @{ Show; Kind (bad | warn | info); Req (zorunlu eksik başlıkları); Rec (önerilen eksik başlıkları); Title; Text (onay penceresi); Toast (bildirim) }
function Get-PrepNudgeModel($State) {
    $m = @{ Show = $false; Kind = 'info'; Req = @(); Rec = @(); Title = ''; Text = ''; Toast = '' }
    if ($null -eq $State) { return $m }
    try { if ($State -is [hashtable] -and $State.ContainsKey('Failed') -and $State['Failed'] -eq $true) { return $m } } catch { }
    $items = $null
    try { $items = Get-PrepItems $State $false } catch { return $m }
    $req = New-Object System.Collections.ArrayList
    $rec = New-Object System.Collections.ArrayList
    foreach ($it in @($items)) {
        $st = [string]$it.Status
        if ($st -ne 'bad' -and $st -ne 'warn') { continue }
        if (-not (Test-PrepNudgeKey ([string]$it.Key))) { continue }
        if ($st -eq 'bad' -and [string]$it.Group -eq 'req') { [void]$req.Add([string]$it.Title) } else { [void]$rec.Add([string]$it.Title) }
    }
    $m.Req = $req.ToArray()
    $m.Rec = $rec.ToArray()
    if ($req.Count -eq 0 -and $rec.Count -eq 0) { return $m }
    $m.Show = $true
    if ($req.Count -gt 0) {
        $m.Kind = 'bad'
        $m.Title = 'Hazırlık: eksik bileşen var'
        $lines = New-Object System.Collections.ArrayList
        foreach ($t in $req) { if ($lines.Count -ge 4) { break }; [void]$lines.Add('•  ' + $t) }
        $txt = 'Multimizer’ın düzgün çalışması için gereken şu bileşenlerde sorun bulundu:' + "`r`n`r`n" + ($lines.ToArray() -join "`r`n")
        $more = $req.Count - $lines.Count
        if ($more -gt 0) { $txt += "`r`n" + '•  ve ' + [string]$more + ' bileşen daha' }
        if ($rec.Count -gt 0) { $txt += "`r`n`r`n" + 'Ayrıca ' + [string]$rec.Count + ' önerilen bileşen eksik ya da eski.' }
        $txt += "`r`n`r`n" + 'Nedenleri ve giderme adımları Çözüm Merkezi > Hazırlık sekmesinde. Bu denetim yalnızca okudu: hiçbir şey kurulmadı ya da değiştirilmedi. Bu uyarı bu sürümde yeniden gösterilmez.'
        $m.Text = $txt
        $m.Toast = 'Hazırlık: ' + [string]$req.Count + ' zorunlu bileşende sorun var (' + (Get-PrepNudgeNames $req.ToArray() 2) + '). Çözüm Merkezi > Hazırlık sekmesine bakın.'
        return $m
    }
    $m.Kind = 'warn'
    $m.Title = 'Hazırlık: öneri var'
    $m.Text = ''
    $m.Toast = 'Hazırlık: ' + [string]$rec.Count + ' önerilen bileşen eksik ya da eski (' + (Get-PrepNudgeNames $rec.ToArray() 2) + '). Çözüm Merkezi > Hazırlık sekmesinden giderebilirsiniz.'
    return $m
}

# Uyarı için uygun an: pencere görünür ve küçültülmemiş, ilk çalıştırma ekranı bitmiş, açık pencere (onay kutusu) ve çalışan iş yok
function Test-PrepNudgeReady {
    if (-not $script:Win.IsVisible) { return $false }
    if ($script:Win.WindowState -eq [System.Windows.WindowState]::Minimized) { return $false }
    if ($script:Settings.FirstRunDone -ne $true) { return $false }
    if ($ui.Overlay.Visibility -eq $script:VisOn) { return $false }
    if ($null -ne $script:Cur) { return $false }
    return $true
}

function Complete-PrepNudge($R) {
    if ($null -eq $R -or $R.Ok -ne $true -or $null -eq $R.State) {
        Write-WhLog 'Hazırlık açılış denetimi tamamlanamadı; sonraki açılışta yeniden denenecek.' 'WARN'
        return
    }
    # sürüm bir kez işaretlenir: denetim sonucu ne olursa olsun aynı sürümde yeniden sorulmaz
    try {
        $script:Settings.PrepSeen = [string]$script:AppVersion
        Save-Settings $script:Settings
    } catch { }
    $m = Get-PrepNudgeModel $R.State
    if ($m.Show -ne $true) {
        Write-WhLog 'Hazırlık: eksik ya da eski bileşen yok.' 'INFO'
        return
    }
    Write-WhLog ('Hazırlık: ' + [string]@($m.Req).Count + ' zorunlu, ' + [string]@($m.Rec).Count + ' önerilen bileşende sorun var.') 'WARN'
    $busy = $false
    try { if ($ui.Overlay.Visibility -eq $script:VisOn) { $busy = $true } } catch { }
    if ($m.Kind -eq 'bad' -and -not $busy) {
        Show-Confirm ([string]$m.Title) ([string]$m.Text) 'Hazırlık sekmesini aç' { Open-Page 'solve' 'prep' }
    } else {
        $k = 'warn'
        if ($m.Kind -eq 'bad') { $k = 'bad' }
        Show-Toast ([string]$m.Toast) $k
    }
}

function Start-PrepNudgeCheck {
    $ok = $false
    try {
        $ok = Start-Async 'PrepNudge' 'Job_PrepCheck' @{ NoNet = $true } {
            param($r)
            Complete-PrepNudge $r
        } 'Hazırlık denetleniyor' $true $true
    } catch { Write-CrashLog ('PrepNudge başlatılamadı: ' + $_.Exception.Message) }
    if ($ok -ne $true) { Write-WhLog 'Hazırlık açılış denetimi başlatılamadı; sonraki açılışta yeniden denenecek.' 'WARN' }
}

function Invoke-PrepNudgeTick {
    if ([string]$script:Settings.PrepSeen -eq [string]$script:AppVersion) { $script:PrepNudgeTimer.Stop(); return }
    $script:PrepNudgeTicks = [int]$script:PrepNudgeTicks + 1
    if (-not (Test-PrepNudgeReady)) { return }
    $script:PrepNudgeTimer.Stop()
    Start-PrepNudgeCheck
}

# Açılışta çağrılır: bu sürümde henüz denetlenmediyse zamanlayıcıyı kurar. Duman testinde ve otomatik testlerde çalışmaz.
function Initialize-PrepNudge {
    if ($script:SmokeMode -eq $true) { return }
    if ([string]$script:Settings.PrepSeen -eq [string]$script:AppVersion) { return }
    $script:PrepNudgeTicks = 0
    $script:PrepNudgeTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:PrepNudgeTimer.Interval = [TimeSpan]::FromSeconds(20)
    $script:PrepNudgeTimer.Add_Tick({
        try { Invoke-PrepNudgeTick } catch { Write-CrashLog ('PrepNudge: ' + $_.Exception.Message) }
    })
    $script:PrepNudgeTimer.Start()
}
