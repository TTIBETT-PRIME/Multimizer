# ---------------- Dokunma hedefleri: Otomatik / Normal / Büyük ----------------
# Ayarlar > Görünüm'de "Dokunma hedefleri". Büyük kipte sekme, onay kutusu, seçenek ve düğmeler en az 40 px (Kompakt yerleşimde 32 px) olur.
# Otomatik: dokunmatik ekran varsa Büyük. Normal kipte hiçbir ölçü değişmez.
# Kaynak sözlüğünde iki sayı tutulur (stiller DynamicResource ile okur, bu yüzden değişiklik anında uygulanır):
#  TouchMin    : sekme, onay kutusu ve anahtar için alt sınır (Normal 24 px: WCAG 2.2 AA 2.5.8; Büyük 40 ya da 32 px)
#  TouchBtnMin : düğmeler için alt sınır (Normal 0 = yalnızca kendi ölçüsü; Büyük 40 ya da 32 px)
$script:TouchKeys = @('Auto', 'Normal', 'Large')
$script:TouchScreenCache = $null
$script:TouchMode = 'Normal'
$script:TouchMinNow = 24.0

function ConvertTo-TouchKey($Value) {
    $t = [string]$Value
    foreach ($k in $script:TouchKeys) { if ($k -ceq $t) { return $k } }
    return 'Auto'
}

# Bilgisayarda dokunmatik ekran var mı (WPF tablet aygıtları; ilk sonuç saklanır)
function Test-TouchScreen {
    if ($null -ne $script:TouchScreenCache) { return [bool]$script:TouchScreenCache }
    $r = $false
    try {
        foreach ($d in @([System.Windows.Input.Tablet]::TabletDevices)) {
            if ($d.Type -eq [System.Windows.Input.TabletDeviceType]::Touch) { $r = $true; break }
        }
    } catch { $r = $false }
    $script:TouchScreenCache = $r
    return $r
}

# Saf: ayardaki anahtardan etkin kip (Normal | Large); $HasTouch Otomatik için dokunmatik ekran var mı
function Get-TouchMode([string]$Key, [bool]$HasTouch) {
    $k = ConvertTo-TouchKey $Key
    if ($k -eq 'Auto') { if ($HasTouch) { return 'Large' }; return 'Normal' }
    return $k
}

# Saf: kip ve yerleşime göre alt sınır (px)
function Get-TouchMin([string]$Mode, [string]$Layout) {
    if ($Mode -ne 'Large') { return 24.0 }
    if ($Layout -eq 'Kompakt') { return 32.0 }
    return 40.0
}

function Set-TouchTargets([string]$Layout = '') {
    if ($Layout -eq '') { $Layout = [string]$script:LayoutName }
    $key = ConvertTo-TouchKey ([string]$script:Settings.TouchTargets)
    $hasTouch = $false
    if ($key -eq 'Auto') { $hasTouch = Test-TouchScreen }
    $mode = Get-TouchMode $key $hasTouch
    $min = Get-TouchMin $mode $Layout
    $btn = 0.0
    if ($mode -eq 'Large') { $btn = $min }
    $res = $script:Win.Resources
    $res['TouchMin'] = [double]$min
    $res['TouchBtnMin'] = [double]$btn
    $script:TouchMode = $mode
    $script:TouchMinNow = $min
    # sol menu dugmelerinin yuksekligi de alt siniri izler (Get-RailHeight $script:TouchMinNow'u okur)
    try { $script:RailH = 0; Update-RailDensity } catch { }
}
