# ---------------- Tema: "Sistem ayarını kullan" (Windows'un açık/koyu uygulama ayarını izler) ----------------
# Ayarlarda Theme = 'Sistem' saklanır; etkin tema her an Windows'tan çözülür: yüksek karşıtlık açıksa Yuksek, uygulamalar
# için koyu kip seçiliyse Koyu, açık kip ya da ayar yoksa Acik. Windows'ta kip değişince 3 sn içinde tema da değişir.
$script:SystemThemeInfo = @{
    T = 'Sistem ayarını kullan'
    D = 'Windows’un açık ya da koyu uygulama ayarını izler; Windows’ta değiştirdiğinizde Multimizer da değişir. Yüksek karşıtlık açıksa yüksek karşıtlık teması kullanılır.'
}
$script:SysThemeTimer = $null
$script:SysThemeErr = $false

function Get-SystemThemeKey {
    try { if (-not $script:SafeBoot -and [System.Windows.SystemParameters]::HighContrast) { return 'Yuksek' } } catch { }
    $v = 1
    try { $v = [int](Get-RegValue 'HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'AppsUseLightTheme' 1) } catch { $v = 1 }
    if ($v -eq 0) { return 'Koyu' }
    return 'Acik'
}

# Ayarlar listesinde seçili gösterilecek değer: "Sistem" korunur, diğer adlar tema anahtarına çevrilir
function ConvertTo-ThemeChoice([string]$Name) {
    if ([string]$Name -eq 'Sistem') { return 'Sistem' }
    return (ConvertTo-ThemeKey $Name)
}

# "Sistem ayarını kullan" seçiliyken Windows'un kipi değiştiyse temayı yeniden uygular
function Update-SystemTheme {
    if ([string]$script:Settings.Theme -ne 'Sistem') { return $false }
    $k = Get-SystemThemeKey
    if ($k -eq [string]$script:ThemeName) { return $false }
    try { Add-Trace ('görünüm: Windows kipi değişti, tema ' + $k) } catch { }
    Set-AppTheme $k
    try { Update-StAppearanceText } catch { }
    return $true
}

function Start-SystemThemeWatch {
    if ($null -ne $script:SysThemeTimer) { return }
    $script:SysThemeTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:SysThemeTimer.Interval = [TimeSpan]::FromSeconds(3)
    $script:SysThemeTimer.Add_Tick({
        try { [void](Update-SystemTheme) }
        catch {
            if (-not $script:SysThemeErr) { $script:SysThemeErr = $true; Write-CrashLog ('Sistem teması: ' + $_.Exception.Message) }
        }
    })
    $script:SysThemeTimer.Start()
}
