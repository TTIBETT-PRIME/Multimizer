# ==================================================================
#  GERCEK MAKINE DUZELTMELERI (durum ve metinler)
#  Guvenli kipin kendiliginden kapanmasi, olculemeyen degerlerin nedeni, guc kipi satiri, Defender dislama bulgusu.
# ==================================================================

$script:SafeReleased = $false
$script:PrevBySystem = $false

# Oturum acilirken: guvenli cizim kalici mi kalsin?  Girdi: ayardaki kalici deger (bu acilista otomatik acildiysa $true).
# Elle acilmamis guvenli kip, art arda uc sorunsuz oturumdan sonra (ya da bu surume ilk geciste bir kez) kapatilir.
# Cekirdek: ayar anahtarlarini dosyaya ve bellekteki kopyaya yazar (arayuzdeki Set-SettingsKeys'in cekirdek karsiligi)
function Set-CoreSettingKeys($Keys) {
    try {
        $st = Get-Settings
        foreach ($k in @($Keys.Keys)) { $st[[string]$k] = $Keys[$k] }
        Save-Settings $st
    } catch { }
    if ($null -ne $script:Settings) { foreach ($k in @($Keys.Keys)) { try { $script:Settings[[string]$k] = $Keys[$k] } catch { } } }
}

function Update-SafeModeState([bool]$Persist) {
    $keys = @{}
    $why = ''; $clean = 0; $fix = 0
    try { $why = [string]$script:Settings.SafeRenderWhy } catch { }
    try { $clean = [int]$script:Settings.CleanStreak } catch { }
    try { $fix = [int]$script:Settings.FixLevel } catch { }
    if ($script:SafeRenderAuto) { $why = 'auto'; $keys['SafeRenderWhy'] = 'auto' }
    if ($script:PrevCrashed -and $clean -ne 0) { $clean = 0; $keys['CleanStreak'] = 0 }
    $out = $Persist
    if (Test-SafeModeRelease $Persist $why $clean ([bool]$script:PrevCrashed) $fix) {
        $keys['SafeRender'] = $false; $keys['SafeRenderWhy'] = ''; $keys['CleanStreak'] = 0; $keys['CrashStreak'] = 0
        $script:SafeReleased = $true
        $out = $false
    }
    if ($fix -lt 1) { $keys['FixLevel'] = 1; $keys['OptCrypto'] = $true }   # dosya sifreleme artik varsayilan olarak acik
    if ($keys.Count -gt 0) { Set-CoreSettingKeys $keys }
    return $out
}

# Duzgun kapanan her oturum sayilir (guvenli kipten cikis karari icin)
function Step-CleanStreak {
    if ($script:Settings.SafeRender -ne $true) { return }
    $n = 0
    try { $n = [int]$script:Settings.CleanStreak } catch { }
    if ($n -lt 99) { Set-CoreSettingKeys @{ CleanStreak = ($n + 1) } }
}

# Ekran karti yuku okunamadiginda gosterilecek neden
function Get-GpuOffText {
    if ($sync.SafeMon -eq $true) { return 'güvenli kipte kapalı' }
    if ($sync.NoGpu -eq $true) { return 'ayarlardan kapalı' }
    # izleme dongusu ilk olcumu henuz yapmadiysa "olculemedi" demek yanlis olur
    if ($sync.MonWarmGpu -ne $false) { return 'ölçülüyor…' }
    return 'ölçülemedi'
}

# Sicaklik okunamadiginda alt yazi: ilk olcum beklenirken "olculuyor", sonrasinda "sensor yok"
function Get-TempOffText {
    if ($sync.MonWarmTemp -ne $false) { return 'ölçülüyor…' }
    return 'sensör yok'
}

# Sicaklik alt yazisi: ekran karti sicakligi okunuyorsa eklenir
function Get-TempSubText($M, [string]$Base) {
    $g = -1.0
    try { if ($M.ContainsKey('GpuTemp')) { $g = [double]$M.GpuTemp } } catch { }
    if ($g -gt 0) { return ((Tr $Base) + ' · ' + (Tr 'ekran kartı') + ' ' + [string][int]$g + '°') }
    return $Base
}

# Guc sayfasi: etkin planin yanina yururlukteki guc kipi
function Update-PwModeLine($Info) {
    try {
        $m = $Info.Mode
        if ($null -eq $m -or $m.Ok -ne $true -or $null -eq $ui.pw_LivePlan) { return }
        $t = [string]$ui.pw_LivePlan.Text + '  ·  ' + (Tr 'Güç kipi') + ': ' + (Tr ([string]$m.Name))
        if ($m.Modern -eq $true) { $t += '  (' + (Tr 'Modern Bekleme: performans düzeyi güç kipiyle ayarlanır') + ')' }
        $ui.pw_LivePlan.Text = $t
    } catch { }
}

# ---------------- Defender dislama bulgusu ----------------
function Get-ExclTitle([int]$Count) { return ('Defender dışlama listesi: ' + [string]$Count + ' öğe') }

function Get-ExclDetail($Pref) {
    $all = New-Object System.Collections.ArrayList
    foreach ($x in @($Pref.ExclusionPath)) { if ([string]$x -ne '') { [void]$all.Add([string]$x) } }
    foreach ($x in @($Pref.ExclusionProcess)) { if ([string]$x -ne '') { [void]$all.Add([string]$x) } }
    foreach ($x in @($Pref.ExclusionExtension)) { if ([string]$x -ne '') { [void]$all.Add('*.' + ([string]$x).TrimStart('.')) } }
    $shown = @($all | Select-Object -First 5)
    $t = 'Taranmayanlar: ' + ($shown -join '; ')
    if ($all.Count -gt $shown.Count) { $t += ' (+' + [string]($all.Count - $shown.Count) + ')' }
    return ($t + '. Zararlılar kendilerini dışlamaya ekleyebilir; tanımadığınız öğeyi Windows Güvenliği’nden kaldırın. Multimizer bu listeyi değiştirmez.')
}

function Get-ExclAction { return @{ Kind = 'Url'; Url = 'windowsdefender://exclusions'; Label = 'Dışlamaları aç' } }
