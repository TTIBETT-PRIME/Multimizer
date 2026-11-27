. "$PSScriptRoot/lib.ps1"
# 7.1.1 / 7.2.0: kararlılık katmanı. Uygulamanın açılmaması / tema değişince kapanması gibi hataların yeniden ortaya çıkmasını önler:
#  - hata günlüğü sınırı, hata fırtınası, güvenli başlangıç, görünümü sıfırlama, ayar dosyasına atomik yazım
#  - Windows'un korudugu kayıt değerleri ("Windows engelliyor": hata değil), günlükten geri alma
#  - sol menü yoğunluğu, duman testi kuyruğu / günlük okuyucusu
#  - derlenmiş betikte bağlantı (AST) denetimleri

Import-Fn 'Write-CrashLog', 'Test-ErrorBurst', 'Set-SettingsKeys', 'Register-UiError', 'Stop-ErrorStorm', 'Invoke-BootGuard', 'Confirm-BootOk',
    'Show-StartFailure', 'Reset-UiSettings', 'Invoke-CliResetUi', 'Save-JsonFile', 'Read-JsonFile', 'Get-SafeLookKeys'
Import-Fn 'Test-AccessDeniedEx', 'Test-RegDenied', 'Get-RegDeniedList', 'Save-RegDenied', 'Register-RegDenied', 'Clear-RegDenied', 'Get-RegOpLabel',
    'Test-TweakBlocked', 'Remove-LastJournalItem', 'Get-RegDeniedText', 'Invoke-RegOp', 'Resolve-RegPath', 'Get-TargetSid', 'Test-RegWriteBlocked',
    'Open-Journal', 'Add-Journal', 'Format-RegData', 'ConvertTo-RegData', 'Test-RegEqual', 'ConvertTo-BackupText', 'Job_TweakStateIds', 'Get-RegNoAdminText'
Import-Fn 'Get-RailHeight', 'Update-RailDensity', 'Test-RailShown', 'Refresh-RailGroups'
Import-Fn 'New-SmokeStep', 'New-SmokeQueue', 'Get-SmokeActions', 'Add-SmokeLine', 'Add-SmokeError', 'Add-SmokeWarn', 'Read-SmokeLogDelta', 'Get-SmokeScope', 'Add-SmokeLookParts', 'Add-SmokeBoardEditParts', 'Add-SmokeExpect', 'Test-SmokeExpected', 'Get-SmokeExpectMissing'
Import-Var 'SmokeExpect', 'SmokeSafe', 'SmokeBadIds', 'RegDenyPath', 'RegDenyName', 'SmokeThemes', 'SmokeLayouts', 'SmokeLimitSec', 'SmokeScopes', 'SmokeDesigns', 'SmokeGlassOps', 'SmokeGlassThemeOp', 'SmokePresets'
Import-Var 'DesignInfo', 'GlassInfo', 'GlassSteps', 'SmokeSafeSelect', 'SmokeOverrides', 'HomeInfo', 'LookPresetNames', 'StLookParts'

# gerçek Save-Settings başka adla yüklenir (aşağıdaki sahte Save-Settings ile karışmasın)
function Import-FnAs([string]$Name, [string]$As) {
    $f = @(Get-AstFunctions | Where-Object { $_.Name -eq $Name }) | Select-Object -Last 1
    $txt = $f.Extent.Text -replace ('^function\s+' + [regex]::Escape($Name)), ('function ' + $As)
    . ([scriptblock]::Create($txt))
    Set-Item -Path ('function:global:' + $As) -Value (Get-Item ('function:' + $As)).ScriptBlock
}
Import-FnAs 'Save-Settings' 'Save-SettingsReal'

# ---------------- sahte ortam ----------------
$root = Join-Path ([System.IO.Path]::GetTempPath()) ('mm-stab-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root -Force | Out-Null
$script:Log = New-Object System.Collections.ArrayList
function Write-WhLog { param([string]$Message, [string]$Level = 'INFO') [void]$script:Log.Add($Level + '|' + $Message) }
$global:FakeAdmin = $true
function global:Test-ProcAdmin { return [bool]$global:FakeAdmin }
function Log-Has([string]$Needle) { foreach ($l in $script:Log) { if ($l.Contains($Needle)) { return $true } }; return $false }
function Add-Skip([string]$Message) { $script:Skipped++; Write-WhLog $Message 'SKIP' }
function Add-Plan([string]$Message) { $script:Changes++; Write-WhLog $Message 'PLAN' }
function Add-Done([string]$Message) { $script:Changes++; Write-WhLog $Message 'OK' }
function Add-Err([string]$Message) { $script:Errors++; Write-WhLog $Message 'ERR' }
function Reset-T { $script:Log.Clear(); $script:Changes = 0; $script:Skipped = 0; $script:Errors = 0 }
function Test-JobCancel { return $false }

# sahte ayar dosyası: "disk" ve bellekteki nesne ayrı tutulur
$script:Disk = @{}
$script:GetFails = $false
$script:SaveFails = $false
$script:Saves = 0
function Get-Settings {
    if ($script:GetFails) { throw 'ayar dosyası okunamadı' }
    $h = @{}
    foreach ($k in $script:Disk.Keys) { $h[$k] = $script:Disk[$k] }
    return $h
}
function Save-Settings($S) {
    if ($script:SaveFails) { throw 'ayar dosyası yazılamadı' }
    $d = @{}
    foreach ($k in $S.Keys) { $d[$k] = $S[$k] }
    $script:Disk = $d
    $script:Saves++
}
function Restart-Process { $script:Settings = Get-Settings; $script:SafeBoot = $false; $script:UiErrTotal = 0 }

$sync = @{
    SettingsFile = (Join-Path $root 'ayarlar.json'); BackupDir = $root; Version = '7.1.1'; RunUser = 'deneme'; TargetSid = ''
    RegDenied = [hashtable]::Synchronized(@{})
}
$script:LogDir = Join-Path $root 'log'
New-Item -ItemType Directory -Path $script:LogDir -Force | Out-Null
$script:SmokeMode = $false
$script:SmokeErrs = New-Object System.Collections.ArrayList
$script:SmokeCur = ''
$script:SmokeLog = ''
$script:SmokeWarns = 0
$script:RegDeniedMax = 60

try {
    # ======================= 1) hata günlüğü (sınırlı) =======================
    $script:CrashSeen = @{}; $script:CrashBytes = -1; $script:CrashDay = ''; $script:CrashMaxBytes = 1048576; $script:CrashLineMax = 6000
    $day = Get-Date -Format 'yyyyMMdd'
    $cf = Join-Path $script:LogDir ('hata-' + $day + '.txt')
    Write-CrashLog 'ilk hata'
    Assert-True (Test-Path -LiteralPath $cf) 'hata günlüğü oluştu'
    $bytes = [System.IO.File]::ReadAllBytes($cf)
    Assert-True ($bytes.Length -gt 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) 'hata günlüğü UTF-8 (BOM) yazılır'
    Assert-Eq @([System.IO.File]::ReadAllLines($cf)).Count 1 'ilk hata tek satır'
    Write-CrashLog 'ilk hata'
    Write-CrashLog 'ilk hata'
    Assert-Eq @([System.IO.File]::ReadAllLines($cf)).Count 1 'aynı ileti 60 sn içinde yeniden yazılmaz'
    Assert-Eq $script:CrashSeen['ilk hata'].N 2 'bastırılan tekrarlar sayılır'
    Write-CrashLog 'ikinci hata'
    Assert-Eq @([System.IO.File]::ReadAllLines($cf)).Count 2 'farklı ileti yazılır'
    $script:CrashSeen['ilk hata'].T = [DateTime]::UtcNow.AddSeconds(-61)
    Write-CrashLog 'ilk hata'
    $ls = @([System.IO.File]::ReadAllLines($cf))
    Assert-Eq $ls.Count 3 '60 sn sonra aynı ileti yeniden yazılır'
    Assert-True ($ls[2] -like '*bu ileti son bir dakikada 2 kez daha tekrarland*') 'bastırılan tekrar sayısı satıra not düşülür'
    Write-CrashLog ('x' * 10000)
    $ls = @([System.IO.File]::ReadAllLines($cf))
    Assert-True ($ls[$ls.Count - 1].Length -le 6020 -and $ls[$ls.Count - 1].EndsWith('...')) 'çok uzun ileti 6000 karakterde kesilir'

    # günlük boyutu sınırı: dolunca yeni satır yazılmaz, yeniden başlatmada da yazılmaz
    Remove-Item -LiteralPath $cf -Force
    $script:CrashSeen = @{}; $script:CrashBytes = -1; $script:CrashDay = ''; $script:CrashMaxBytes = 2000
    for ($i = 0; $i -lt 60; $i++) { Write-CrashLog ('hata numarası ' + $i + ' ' + ('y' * 80)) }
    $len1 = (Get-Item -LiteralPath $cf).Length
    Assert-True ($len1 -lt 2000 + 600) 'günlük sınırı aşıldığında dosya büyümeyi bırakır'
    for ($i = 100; $i -lt 110; $i++) { Write-CrashLog ('yeni hata ' + $i) }
    Assert-Eq (Get-Item -LiteralPath $cf).Length $len1 'sınırdan sonra yeni satır yazılmaz'
    $script:CrashSeen = @{}; $script:CrashBytes = -1; $script:CrashDay = ''
    Write-CrashLog 'yeniden başlatıldıktan sonra'
    Assert-Eq (Get-Item -LiteralPath $cf).Length $len1 'süreç yeniden başlayınca da sınır geçerli (dosya boyutundan okunur)'

    # duman kipinde hata günlüğüne yazılan her şey duman hatası sayılır
    $script:SmokeMode = $true; $script:SmokeErrs.Clear()
    $script:CrashSeen = @{}; $script:CrashBytes = -1; $script:CrashDay = ''; $script:CrashMaxBytes = 1048576
    Write-CrashLog 'duman kipinde hata'
    Assert-Eq $script:SmokeErrs.Count 1 'duman kipinde hata günlüğü yazımı duman hatası olur'
    $script:SmokeMode = $false; $script:SmokeErrs.Clear()

    # ======================= 2) hata fırtınası =======================
    $script:BurstSeen = @{}
    $r = @(1..6 | ForEach-Object { Test-ErrorBurst 'aynı hata' })
    Assert-Eq ($r -join ',') 'False,False,False,True,True,True' 'aynı hata: ilk 3 geçer, sonrası bastırılır'
    Assert-Eq (Test-ErrorBurst 'başka hata') $false 'başka ileti ayrı sayılır'
    $script:BurstSeen['aynı hata'].T = [DateTime]::UtcNow.AddSeconds(-11)
    Assert-Eq (Test-ErrorBurst 'aynı hata') $false '10 sn sonra sayaç sıfırlanır'
    Assert-Eq $script:BurstSeen['aynı hata'].N 1 'sayaç 1 olur'
    $script:BurstSeen = @{}
    $ka = ('k' * 200) + 'A'; $kb = ('k' * 200) + 'B'
    [void](Test-ErrorBurst $ka); [void](Test-ErrorBurst $kb); [void](Test-ErrorBurst $ka)
    Assert-Eq (Test-ErrorBurst $kb) $true 'ilk 200 karakteri aynı olan iletiler aynı sayılır'

    $script:UiErrTimes = New-Object System.Collections.ArrayList; $script:UiErrTotal = 0; $script:StormLimit = 25
    $res = @(1..25 | ForEach-Object { Register-UiError })
    Assert-Eq (@($res[0..23] | Where-Object { $_ -eq $true }).Count) 0 '24 hata fırtına sayılmaz'
    Assert-Eq $res[24] $true '25. hata (5 sn içinde) fırtınayı bildirir'
    Assert-Eq $script:UiErrTotal 25 'toplam hata sayısı tutulur'
    $script:UiErrTimes.Clear()
    $old = [DateTime]::UtcNow.Ticks - 60000000L
    1..24 | ForEach-Object { [void]$script:UiErrTimes.Add($old) }
    Assert-Eq (Register-UiError) $false '5 sn öncesine ait hatalar fırtınaya eklenmez'
    Assert-Eq $script:UiErrTimes.Count 1 'eski kayıtlar düşer'

    # ======================= 3) ayara güvenli yazım =======================
    $script:Disk = @{ Theme = 'Hacker'; BootTries = 0; Diger = 'dosyadaki' }
    $script:Settings = @{ Theme = 'Hacker'; BootTries = 0; Diger = 'bellekteki-eski' }
    Set-SettingsKeys @{ Theme = 'Neon' }
    Assert-Eq $script:Disk.Theme 'Neon' 'anahtar dosyaya yazıldı'
    Assert-Eq $script:Disk.Diger 'dosyadaki' 'dosyadaki diğer anahtarlar korunur (eski bellek nesnesi dosyayı ezmez)'
    Assert-Eq $script:Settings.Theme 'Neon' 'bellekteki nesneye de yansır'
    Assert-Eq $script:Settings.Diger 'bellekteki-eski' 'bellekte yalnızca verilen anahtar değişir'
    $script:GetFails = $true
    $threw = $false
    try { Set-SettingsKeys @{ BootTries = 5 } } catch { $threw = $true }
    Assert-True (-not $threw) 'ayar dosyası okunamasa da hata fırlatılmaz'
    Assert-Eq $script:Settings.BootTries 5 'dosya okunamasa da bellek güncellenir'
    $script:GetFails = $false; $script:SaveFails = $true
    $threw = $false
    try { Set-SettingsKeys @{ BootTries = 6 } } catch { $threw = $true }
    Assert-True (-not $threw) 'ayar dosyası yazılamasa da hata fırlatılmaz'
    Assert-Eq $script:Settings.BootTries 6 'dosya yazılamasa da bellek güncellenir'
    $script:SaveFails = $false

    # ======================= 4) güvenli başlangıç =======================
    $script:Disk = @{ Theme = 'Hacker'; Layout = 'Sade'; Zoom = 130; OptWidget = $true; BootTries = 0; Design = 'Morpheus'; Backdrop = 'Akrilik'; WinOpacity = 60 }
    Restart-Process
    Invoke-BootGuard
    Assert-Eq $script:Disk.BootTries 1 '1. açılış: sayaç 1'
    Assert-Eq $script:SafeBoot $false '1. açılış güvenli başlangıç değil'
    Restart-Process; Invoke-BootGuard      # pencere hiç açılamadı (Confirm-BootOk çağrılmadı)
    Assert-Eq $script:Disk.BootTries 2 '2. açılış: sayaç 2'
    Assert-Eq $script:SafeBoot $false '2. açılış güvenli başlangıç değil'
    Assert-Eq $script:Disk.Theme 'Hacker' 'iki başarısız açılıştan sonra tema henüz korunur'
    Assert-Eq $script:Disk.Layout 'Sade' 'iki başarısız açılıştan sonra yerleşim henüz korunur'
    Assert-Eq $script:Disk.Zoom 130 'iki başarısız açılıştan sonra yakınlaştırma henüz korunur'
    Assert-Eq "$($script:Disk.Design)|$($script:Disk.Backdrop)|$($script:Disk.WinOpacity)" 'Morpheus|Akrilik|60' 'iki başarısız açılıştan sonra tasarım ve saydamlık henüz korunur'
    Restart-Process; Invoke-BootGuard
    Assert-Eq $script:SafeBoot $true '3. açılış güvenli başlangıç olur'
    Assert-Eq $script:Disk.Theme 'Neon' 'güvenli başlangıçta tema Neon yapılır'
    Assert-Eq $script:Disk.Layout 'Ayrintili' 'güvenli başlangıçta yerleşim Ayrıntılı yapılır'
    Assert-Eq $script:Disk.Zoom 100 'güvenli başlangıçta yakınlaştırma %100 yapılır'
    Assert-Eq $script:Disk.OptWidget $false 'güvenli başlangıçta mini izleyici kapanır'
    Assert-Eq "$($script:Disk.Design)|$($script:Disk.Backdrop)|$($script:Disk.WinOpacity)" 'Klasik|Yok|100' 'güvenli başlangıçta tasarım Klasik, saydamlık kapalı olur'
    Assert-Eq $script:Disk.BootTries 1 'güvenli başlangıçta sayaç 1'
    Confirm-BootOk
    Assert-Eq $script:Disk.BootTries 0 'ana pencere hatasız açılınca sayaç sıfırlanır'
    $saves0 = $script:Saves
    Confirm-BootOk
    Assert-Eq $script:Saves $saves0 'sayaç zaten 0 ise ayar dosyasına yazılmaz'
    $script:Disk = @{ BootTries = 1 }; Restart-Process; $script:UiErrTotal = 3
    Confirm-BootOk
    Assert-Eq $script:Disk.BootTries 1 'yakalanmamış hata varken açılış başarılı sayılmaz'
    # duman kipinde güvenli başlangıç mantığı ayara dokunmaz
    $script:SmokeMode = $true
    $script:Disk = @{ Theme = 'Hacker'; BootTries = 2 }; Restart-Process
    Invoke-BootGuard; Confirm-BootOk; Show-StartFailure 'x'
    Assert-Eq $script:Disk.Theme 'Hacker' 'duman kipinde tema değişmez'
    Assert-Eq $script:Disk.BootTries 2 'duman kipinde sayaç değişmez'
    $script:SmokeMode = $false
    # başlatma hatası: sonraki açılış güvenli olur
    $script:Disk = @{ Theme = 'Yuksek'; BootTries = 0 }; Restart-Process
    Show-StartFailure 'deneme hatası'
    Assert-Eq $script:Disk.BootTries 2 'başlatma hatasından sonra sayaç 2 yapılır'
    Restart-Process; Invoke-BootGuard
    Assert-Eq $script:SafeBoot $true 'başlatma hatasından sonraki açılış güvenli başlangıçtır'
    Assert-Eq $script:Disk.Theme 'Neon' 'başlatma hatasından sonra tema varsayılana döner'

    # hata fırtınası: kapanır, sonraki açılış varsayılan görünümle olur
    $global:StormN = @{ Pump = 0; Mon = 0; Hide = 0; Shut = 0 }
    $script:PumpTimer = New-Object psobject; Add-Member -InputObject $script:PumpTimer -MemberType ScriptMethod -Name Stop -Value { $global:StormN.Pump++ }
    $script:MonTimer = New-Object psobject; Add-Member -InputObject $script:MonTimer -MemberType ScriptMethod -Name Stop -Value { $global:StormN.Mon++ }
    $script:Win = New-Object psobject; Add-Member -InputObject $script:Win -MemberType ScriptMethod -Name Hide -Value { $global:StormN.Hide++ }
    Add-Member -InputObject $script:Win -MemberType ScriptMethod -Name Close -Value { }
    $script:App = New-Object psobject; Add-Member -InputObject $script:App -MemberType ScriptMethod -Name Shutdown -Value { $global:StormN.Shut++ }
    $script:Disk = @{ Theme = 'Hacker'; Layout = 'Hacker'; Zoom = 80; OptWidget = $true; BootTries = 0; Design = 'Komuta'; Backdrop = 'Mica'; WinOpacity = 70; HomeMode = 'Pano'; DsNav = 'Fly'; DsRadius = 'Pill'; DsFont = 'Mono'; DsGraph = 'none'; DsSkin = 'Glass' }; Restart-Process
    $script:StormDone = $false; $script:Quitting = $false
    Remove-Item -LiteralPath $cf -Force -ErrorAction SilentlyContinue
    $script:CrashSeen = @{}; $script:CrashBytes = -1; $script:CrashDay = ''
    Stop-ErrorStorm
    Assert-Eq $script:StormDone $true 'fırtına işaretlendi'
    Assert-Eq $script:Quitting $true 'kapanış işaretlendi'
    Assert-Eq $global:StormN.Shut 1 'uygulama kapatıldı'
    Assert-Eq $global:StormN.Hide 1 'pencere gizlendi'
    Assert-Eq $script:Disk.Theme 'Neon' 'fırtınadan sonra tema varsayılana döner'
    Assert-Eq $script:Disk.Layout 'Ayrintili' 'fırtınadan sonra yerleşim varsayılana döner'
    Assert-Eq $script:Disk.Zoom 100 'fırtınadan sonra yakınlaştırma %100 olur'
    Assert-Eq $script:Disk.OptWidget $false 'fırtınadan sonra mini izleyici kapanır'
    Assert-Eq "$($script:Disk.Design)|$($script:Disk.Backdrop)|$($script:Disk.WinOpacity)" 'Klasik|Yok|100' 'fırtınadan sonra tasarım Klasik, saydamlık kapalı olur'
    Assert-Eq "$($script:Disk.HomeMode)|$($script:Disk.DsNav)|$($script:Disk.DsRadius)|$($script:Disk.DsFont)|$($script:Disk.DsGraph)|$($script:Disk.DsSkin)" 'Klasik|Auto|Auto|Auto|Auto|Auto' 'fırtınadan sonra ana ekran en sınanmış biçime (klasik durum panosu), tasarım ayrıntıları tasarımın değerine döner'
    Assert-Eq $script:Disk.BootTries 2 'fırtınadan sonra sonraki açılış güvenli olur'
    Assert-True ((Test-Path -LiteralPath $cf) -and ([System.IO.File]::ReadAllText($cf) -like '*Hata d*ng*algılandı*') -or ([System.IO.File]::ReadAllText($cf) -like '*Hata d*ng*: 5 saniyede 25*')) 'hata döngüsü günlüğe yazıldı'
    Stop-ErrorStorm
    Assert-Eq $global:StormN.Shut 1 'ikinci çağrı bir şey yapmaz'
    $script:SmokeMode = $true; $script:StormDone = $false; $script:Disk = @{ Theme = 'Hacker'; BootTries = 0 }; Restart-Process
    Stop-ErrorStorm
    Assert-Eq $script:Disk.Theme 'Hacker' 'duman kipinde fırtına ayarları değiştirmez'
    $script:SmokeMode = $false; $script:SmokeErrs.Clear()

    # ======================= 4b) güvenli görünüm anahtarları =======================
    $slk = Get-SafeLookKeys
    Assert-Eq (@($slk.Keys | Sort-Object) -join ',') 'Backdrop,BootTries,Design,DsFont,DsGraph,DsNav,DsRadius,DsSkin,HomeMode,Layout,OptWidget,Theme,TouchTargets,WinOpacity,Zoom' 'güvenli görünüm anahtarları: tema, yerleşim, yakınlaştırma, tasarım ve ayrıntıları, ana ekran, saydamlık, dokunma hedefleri (Normal), mini izleyici, açılış sayacı'
    Assert-Eq "$($slk.Theme)|$($slk.Layout)|$($slk.Zoom)|$($slk.Design)|$($slk.HomeMode)|$($slk.Backdrop)|$($slk.WinOpacity)|$($slk.OptWidget)" 'Neon|Ayrintili|100|Klasik|Klasik|Yok|100|False' 'güvenli görünüm: varsayılan tema ve yerleşim, Klasik tasarım, klasik durum panosu, saydamlık kapalı'
    Assert-Eq ((Get-SafeLookKeys).BootTries) 0 'güvenli görünüm: açılış sayacı varsayılan sıfır'
    Assert-Eq ((Get-SafeLookKeys 2).BootTries) 2 'güvenli görünüm: açılış sayacı verilen değer'
    foreach ($pp in @('Nav', 'Radius', 'Font', 'Graph', 'Skin')) { Assert-Eq $slk[('Ds' + $pp)] 'Auto' "güvenli görünüm: Ds$pp tasarımın kendi değerinde" }
    Assert-True ($script:DesignInfo.Contains([string]$slk.Design) -and $script:HomeInfo.Contains([string]$slk.HomeMode) -and $script:GlassInfo.Contains([string]$slk.Backdrop) -and @($script:GlassSteps) -contains [int]$slk.WinOpacity) 'güvenli görünüm değerleri geçerli tablo anahtarları'

    # ======================= 5) görünümü sıfırla =======================
    $script:Disk = @{ HomeMode = 'Pano'; DsNav = 'Fly'; DsRadius = 'Pill'; DsFont = 'Mono'; DsGraph = 'none'; DsSkin = 'Glass'; Theme = 'Hacker'; Layout = 'Kompakt'; Zoom = 80; SmoothScroll = $false; ToTopButton = $false; FocusRing = $false; ReduceMotion = $true; OptWidget = $true; WidgetX = 120; WidgetY = 340; BootTries = 2; Mode = 'Expert'; Notify = $true; TrayMinimize = $true; TrayOnMinimize = $false; Design = 'Sifir'; Backdrop = 'Akrilik'; WinOpacity = 50 }
    $st = Reset-UiSettings
    Assert-Eq $script:Disk.Theme 'Neon' 'tema Neon'
    Assert-Eq $script:Disk.Layout 'Ayrintili' 'yerleşim Ayrıntılı'
    Assert-Eq $script:Disk.Design 'Klasik' 'tasarım Klasik'
    Assert-Eq $script:Disk.Backdrop 'Yok' 'arka plan efekti kapalı'
    Assert-Eq $script:Disk.WinOpacity 100 'pencere opaklığı %100'
    Assert-Eq "$($script:Disk.HomeMode)|$($script:Disk.DsNav)|$($script:Disk.DsRadius)|$($script:Disk.DsFont)|$($script:Disk.DsGraph)|$($script:Disk.DsSkin)" 'Klasik|Auto|Auto|Auto|Auto|Auto' 'ana ekran klasik durum panosu, tasarım ayrıntıları tasarımın değerinde'
    Assert-Eq $script:Disk.Zoom 100 'yakınlaştırma %100'
    Assert-Eq $script:Disk.SmoothScroll $true 'yumuşak kaydırma açık'
    Assert-Eq $script:Disk.ToTopButton $true 'başa dön düğmesi açık'
    Assert-Eq $script:Disk.FocusRing $true 'odak çerçevesi açık'
    Assert-Eq $script:Disk.TrayMinimize $true 'tepsi ayarlarına dokunulmaz (kapatma)'
    Assert-Eq $script:Disk.TrayOnMinimize $false 'tepsi ayarlarına dokunulmaz (küçültme)'
    Assert-Eq $script:Disk.ReduceMotion $false 'hareket azaltma kapalı'
    Assert-Eq $script:Disk.OptWidget $false 'mini izleyici kapalı'
    Assert-Eq $script:Disk.WidgetX -1 'mini izleyici konumu sıfırlandı (x)'
    Assert-Eq $script:Disk.WidgetY -1 'mini izleyici konumu sıfırlandı (y)'
    Assert-Eq $script:Disk.BootTries 0 'açılış sayacı sıfır'
    Assert-Eq $script:Disk.Mode 'Expert' 'görünümle ilgisiz ayarlara dokunulmaz (kip)'
    Assert-Eq $script:Disk.Notify $true 'görünümle ilgisiz ayarlara dokunulmaz (bildirim)'
    Reset-T
    $rc = Invoke-CliResetUi
    Assert-Eq $rc 0 'GorunumSifirla çıkış kodu 0'
    Assert-True (Log-Has 'OK|') 'GorunumSifirla sonucu günlüğe yazılır'

    # ======================= 6) ayar dosyasına atomik yazım =======================
    $jf = Join-Path $root 'deneme.json'
    $ad = 'Tu' + [char]0x011F + 'ra'
    Save-JsonFile @{ Ad = $ad; N = 3 } $jf 6
    $o = Read-JsonFile $jf
    Assert-Eq $o.Ad $ad 'Türkçe karakterler korunur'
    Assert-Eq $o.N 3 'değer korunur'
    Assert-Eq @(Get-ChildItem -LiteralPath $root -Filter 'deneme.json.*.tmp').Count 0 'geçici dosya kalmaz'
    Save-JsonFile @{ Ad = 'ikinci'; N = 4 } $jf 6
    Assert-Eq (Read-JsonFile $jf).N 4 'var olan dosyanın üzerine yazılır'
    Assert-Eq @(Get-ChildItem -LiteralPath $root -Filter 'deneme.json.*.tmp').Count 0 'üzerine yazmada da geçici dosya kalmaz'
    # atomik değiştirme gerçekten çalışmalı: $null yedek adı boş dizgiye dönüşür ve File.Replace sessizce başarısız olup yedek yola düşerdi
    $Error.Clear()
    Save-JsonFile @{ Ad = 'ucuncu'; N = 5 } $jf 6
    Assert-Eq $Error.Count 0 'var olan dosya atomik değiştirilir (yutulan hata yok, yedek yola düşülmez)'
    Assert-Eq (Read-JsonFile $jf).N 5 'atomik değiştirme sonrası değer doğru'
    $raw = [System.IO.File]::ReadAllBytes($jf)
    Assert-True (-not ($raw[0] -eq 0xEF -and $raw[1] -eq 0xBB)) 'ayar dosyasında BOM yok'
    # paylaşılan RegDenied listesi: bellekteki eski nesne kaydedilse bile liste silinmez
    $sync.RegDenied.Clear()
    $sync.RegDenied['hklm\software\policies\microsoft\dsh\allownewsandinterests'] = $true
    Save-SettingsReal @{ Theme = 'Neon'; RegDenied = @() }
    $o = Read-JsonFile $sync.SettingsFile
    Assert-Eq $o.Theme 'Neon' 'Save-Settings ayarı yazar'
    Assert-Eq @($o.RegDenied).Count 1 'eski bellek nesnesi RegDenied listesini silmez'
    Assert-Eq @($o.RegDenied)[0] 'hklm\software\policies\microsoft\dsh\allownewsandinterests' 'liste içeriği doğru'
    $sync.RegDenied.Clear()

    # ======================= 7) Windows'un korumaya aldığı kayıt değerleri =======================
    $ux = [System.UnauthorizedAccessException]::new('x')
    Assert-True (Test-AccessDeniedEx $ux) 'UnauthorizedAccessException tanınır'
    Assert-True (Test-AccessDeniedEx ([System.Security.SecurityException]::new('x'))) 'SecurityException tanınır'
    Assert-True (Test-AccessDeniedEx ([System.Management.Automation.MethodInvocationException]::new('sarmalı', $ux))) 'MethodInvocationException içindeki erişim reddi tanınır'
    $deep = [System.InvalidOperationException]::new('a', [System.InvalidOperationException]::new('b', [System.Management.Automation.MethodInvocationException]::new('c', $ux)))
    Assert-True (Test-AccessDeniedEx $deep) 'iç içe özel durum zincirinde erişim reddi bulunur'
    Assert-True (-not (Test-AccessDeniedEx ([System.IO.IOException]::new('disk')))) 'başka hata erişim reddi sayılmaz'
    Assert-True (-not (Test-AccessDeniedEx $null)) 'boş değer erişim reddi sayılmaz'

    $path = 'HKLM\SOFTWARE\Policies\Microsoft\Dsh'
    $nm = 'AllowNewsAndInterests'
    $op = @{ T = 'Reg'; Path = $path; Name = $nm; Kind = 'DWord'; Value = 0 }
    $lab = Get-RegOpLabel $op
    Assert-Eq $lab 'HKLM\SOFTWARE\Policies\Microsoft\Dsh\AllowNewsAndInterests' 'işlem etiketi yol\ad biçimindedir'
    Assert-Eq (Test-RegWriteBlocked $path $nm) '' 'Pencere Öğeleri ilkesi güvenlik kapısında değil (yalnızca Windows yazdırmıyor)'

    $script:Disk = @{ Theme = 'Neon' }
    $sync.RegDenied.Clear()
    Register-RegDenied $lab
    Assert-True (Test-RegDenied $lab) 'kaydedilen değer korumalı sayılır'
    Assert-True (Test-RegDenied $lab.ToUpperInvariant()) 'büyük/küçük harf ayrımı yapılmaz'
    Assert-Eq @($script:Disk.RegDenied).Count 1 'liste ayar dosyasına yazıldı'
    Assert-Eq @($script:Disk.RegDenied)[0] $lab.ToLowerInvariant() 'liste küçük harfle saklanır'
    Register-RegDenied $lab
    Assert-Eq @(Get-RegDeniedList).Count 1 'aynı değer iki kez eklenmez'
    $item = @{ Id = 't1'; Ops = @( @{ T = 'Svc'; Name = 'x' }, $op ) }
    Assert-Eq (Test-TweakBlocked $item) $true 'korumalı değeri yazan ayar "Windows engelliyor" sayılır'
    Assert-Eq (Test-TweakBlocked @{ Id = 't2'; Ops = @( @{ T = 'Reg'; Path = 'HKLM\SOFTWARE\Baska'; Name = 'A'; Kind = 'DWord'; Value = 1 } ) }) $false 'başka ayar etkilenmez'
    Assert-Eq (Test-TweakBlocked $null) $false 'boş ayar engelli sayılmaz'
    Clear-RegDenied $lab
    Assert-Eq (Test-RegDenied $lab) $false 'temizlenen değer artık korumalı sayılmaz'
    Assert-Eq @($script:Disk.RegDenied).Count 0 'liste dosyadan da silinir'
    Assert-Eq (Test-TweakBlocked $item) $false 'liste boşken ayar engelli sayılmaz'
    for ($i = 0; $i -lt 70; $i++) { Register-RegDenied ('HKLM\SOFTWARE\Deneme\Anahtar' + $i + '\Ad') }
    Assert-Eq @(Get-RegDeniedList).Count 60 'liste en çok 60 kayıt tutar'
    Assert-True (@($script:Disk.RegDenied).Count -le 60) 'dosyaya en çok 60 kayıt yazılır'
    $sync.RegDenied.Clear()
    Assert-True ((Get-RegDeniedText $lab).Contains($lab)) 'neden metni hangi değer olduğunu söyler'

    # günlükten son kaydı çıkarma
    $jfile = Join-Path $root 'yedek-1.jsonl'
    Open-Journal $jfile
    Add-Journal @{ T = 'Reg'; Path = 'A'; Name = 'a'; Existed = $false }
    Add-Journal @{ T = 'Reg'; Path = 'B'; Name = 'b'; Existed = $true }
    Assert-Eq @([System.IO.File]::ReadAllLines($jfile)).Count 3 'günlük: başlık + 2 kayıt'
    Remove-LastJournalItem
    $jl = @([System.IO.File]::ReadAllLines($jfile))
    Assert-Eq $script:JItems.Count 1 'bellekteki günlükten son kayıt çıktı'
    Assert-Eq $jl.Count 2 'dosyadan son kayıt çıktı'
    Assert-True ($jl[0] -like '*"Tool":"Multimizer"*') 'başlık satırı korunur'
    Assert-True ($jl[1] -like '*"Path":"A"*') 'kalan kayıt ilk kayıt'
    Remove-LastJournalItem; Remove-LastJournalItem
    Assert-Eq @([System.IO.File]::ReadAllLines($jfile)).Count 1 'tüm kayıtlar çıkınca başlık kalır'
    Assert-Eq $script:JItems.Count 0 'bellek günlüğü boş'

    # Invoke-RegOp: yazma reddedilirse hata değil, atlama
    $script:RegState = @{}
    $script:SetMode = 'ok'; $script:DelMode = 'ok'; $script:SetCalls = 0
    function Get-RegInfo([string]$Path, [string]$Name) {
        $k = $Path + '\' + $Name
        if ($script:RegState.ContainsKey($k)) { $s = $script:RegState[$k]; return @{ KeyExists = $true; Exists = $true; Kind = $s.Kind; Value = $s.Value } }
        return @{ KeyExists = $false; Exists = $false; Kind = $null; Value = $null }
    }
    function Throw-Mode([string]$Mode) {
        switch ($Mode) {
            'denied' { throw [System.UnauthorizedAccessException]::new('Erişim engellendi') }
            'wrapped' { throw [System.Management.Automation.MethodInvocationException]::new('sarmalandı', [System.UnauthorizedAccessException]::new('Erişim engellendi')) }
            'other' { throw [System.IO.IOException]::new('disk hatası') }
        }
    }
    function Set-RegData([string]$Path, [string]$Name, [string]$Kind, $Value) {
        $script:SetCalls++
        Throw-Mode $script:SetMode
        $script:RegState[$Path + '\' + $Name] = @{ Kind = $Kind; Value = $Value }
    }
    function Remove-RegData([string]$Path, [string]$Name, [bool]$RemoveEmptyKey) {
        $script:SetCalls++
        Throw-Mode $script:DelMode
        $script:RegState.Remove($Path + '\' + $Name)
    }
    $script:Disk = @{ Theme = 'Neon' }
    $sync.RegDenied.Clear()
    Reset-T
    Open-Journal (Join-Path $root 'yedek-2.jsonl')
    $script:Preview = $false
    $script:SetMode = 'wrapped'
    $threw = $false
    try { Invoke-RegOp $op } catch { $threw = $true }
    Assert-True (-not $threw) 'Windows yazdırmayınca hata fırlatılmaz'
    Assert-Eq $script:Errors 0 'hata sayılmaz'
    Assert-Eq $script:Skipped 1 'atlandı olarak sayılır'
    Assert-Eq $script:Changes 0 'değişiklik sayılmaz'
    Assert-Eq $script:JItems.Count 0 'yazılamayan değişiklik geri alma günlüğünden çıkarılır'
    Assert-Eq @([System.IO.File]::ReadAllLines($script:JFile)).Count 1 'günlük dosyasında yalnızca başlık kalır'
    Assert-True (Test-RegDenied $lab) 'değer korumalı olarak kaydedilir'
    Assert-Eq @($script:Disk.RegDenied).Count 1 'korumalı değer ayar dosyasına yazılır'
    Assert-True (Log-Has 'SKIP|Windows bu kay') 'neden açıkça yazılır'
    # önizleme ve doğrulama artık "uygulanacak" saymaz
    Reset-T; $script:Preview = $true; $calls0 = $script:SetCalls
    Invoke-RegOp $op
    Assert-Eq $script:Changes 0 'önizleme korumalı değeri "uygulanacak" saymaz'
    Assert-Eq $script:Skipped 1 'önizleme atlandı der'
    Assert-Eq $script:SetCalls $calls0 'önizleme yazma denemez'
    # başka bir özel durum yutulmaz
    $sync.RegDenied.Clear(); Reset-T; $script:Preview = $false; $script:SetMode = 'other'
    $msg = ''
    try { Invoke-RegOp $op } catch { $msg = [string]$_.Exception.Message }
    Assert-Eq $msg 'disk hatası' 'erişim reddi dışındaki hata olduğu gibi iletilir'
    Assert-Eq (Test-RegDenied $lab) $false 'erişim reddi dışındaki hata değeri korumalı yapmaz'
    # Windows ileride izin verirse yazılır ve kayıt silinir
    Register-RegDenied $lab; Reset-T; $script:Preview = $false; $script:SetMode = 'ok'
    Invoke-RegOp $op
    Assert-Eq $script:Changes 1 'izin verilince değer yazılır'
    Assert-Eq (Test-RegDenied $lab) $false 'başarılı yazımdan sonra korumalı kaydı silinir'
    Assert-Eq @($script:Disk.RegDenied).Count 0 'ayar dosyasından da silinir'
    Assert-True ($script:JItems.Count -ge 1) 'başarılı değişiklik günlükte kalır'
    # silme yolu
    $opDel = @{ T = 'Reg'; Path = $path; Name = $nm; Del = $true }
    Reset-T; $script:DelMode = 'denied'; $threw = $false
    try { Invoke-RegOp $opDel } catch { $threw = $true }
    Assert-True (-not $threw) 'silme reddedilirse hata fırlatılmaz'
    Assert-Eq $script:Errors 0 'silme: hata sayılmaz'
    Assert-Eq $script:Skipped 1 'silme: atlandı'
    Assert-True (Test-RegDenied $lab) 'silme: değer korumalı kaydedilir'
    Reset-T; $script:Preview = $true
    Invoke-RegOp $opDel
    Assert-Eq $script:Changes 0 'silme önizlemesi korumalı değeri saymaz'
    Reset-T; $script:Preview = $false; $script:DelMode = 'ok'
    Invoke-RegOp $opDel
    Assert-Eq $script:Changes 1 'silme izin verilince yapılır'
    Assert-Eq (Test-RegDenied $lab) $false 'silme sonrası korumalı kaydı silinir'
    # yönetici olmayan oturumda (yalnızca -Duman) erişim reddi "Windows korumalı" demek değildir: kalıcı kayıt tutulmaz, ileti yönetici izni ister
    $global:FakeAdmin = $false
    $sync.RegDenied.Clear(); Reset-T; $script:Preview = $false; $script:SetMode = 'denied'
    $threw = $false
    try { Invoke-RegOp $op } catch { $threw = $true }
    Assert-True (-not $threw) 'yönetici değilken yazma reddi hata fırlatmaz'
    Assert-Eq $script:Skipped 1 'yönetici değilken atlandı sayılır'
    Assert-Eq (Test-RegDenied $lab) $false 'yönetici değilken değer kalıcı korumalı yapılmaz'
    Assert-Eq @($script:Disk.RegDenied).Count 0 'yönetici değilken ayar dosyasına korumalı kaydı yazılmaz'
    Assert-True (Log-Has 'Yönetici izni gerekiyor') 'yönetici değilken neden açıkça yazılır'
    Assert-True (-not (Log-Has 'Windows bu kay')) 'yönetici değilken "Windows korumaya aldı" denmez'
    Register-RegDenied $lab
    Assert-Eq (Test-RegDenied $lab) $false 'Register-RegDenied yönetici değilken kayıt tutmaz'
    Assert-True ((Get-RegNoAdminText $lab).Contains($lab)) 'yönetici iletisi değerin adını taşır'
    Reset-T; $script:DelMode = 'denied'; $threw = $false
    try { Invoke-RegOp $opDel } catch { $threw = $true }
    Assert-True (-not $threw) 'yönetici değilken silme reddi hata fırlatmaz'
    Assert-Eq (Test-RegDenied $lab) $false 'yönetici değilken silme de kalıcı kayıt tutmaz'
    $global:FakeAdmin = $true; $script:SetMode = 'ok'; $script:DelMode = 'ok'; $sync.RegDenied.Clear()
    # güvenlik kapısı bundan etkilenmez: yazma hiç denenmez, korumalı listeye de eklenmez
    $opGate = @{ T = 'Reg'; Path = 'HKLM\SOFTWARE\Policies\Microsoft\Windows Defender'; Name = 'DisableAntiSpyware'; Kind = 'DWord'; Value = 1 }
    Reset-T; $script:Preview = $false; $calls0 = $script:SetCalls
    Invoke-RegOp $opGate
    Assert-Eq $script:SetCalls $calls0 'güvenlik kapısındaki değere yazılmaz'
    Assert-True (Log-Has 'venlik kap') 'güvenlik kapısı nedeni yazılır'
    Assert-Eq @(Get-RegDeniedList).Count 0 'güvenlik kapısı değeri korumalı listeye girmez'

    # ayar durumları: korumalı ayar "uygulanmış" gösterilmez (-3), bekleyenler ve uygulananlar değişmez
    $script:FakeCat = @{
        a = @{ Id = 'a'; Pending = 0; Ops = @($op) }
        b = @{ Id = 'b'; Pending = 2; Ops = @($op) }
        c = @{ Id = 'c'; Pending = 0; Ops = @(@{ T = 'Reg'; Path = 'HKLM\SOFTWARE\Baska'; Name = 'Z'; Kind = 'DWord'; Value = 1 }) }
    }
    function Get-CatalogItem([string]$Id) { return $script:FakeCat[$Id] }
    function Get-TweakPending($Item) { return [int]$Item.Pending }
    Register-RegDenied $lab
    $r = Job_TweakStateIds @{ Ids = @('a', 'b', 'c') }
    Assert-Eq $r.States['a'] -3 'korumalı ve bekleyeni olmayan ayar -3 (Windows engelliyor)'
    Assert-Eq $r.States['b'] 2 'bekleyen işlemi olan ayar -3 olmaz'
    Assert-Eq $r.States['c'] 0 'korumasız ayar uygulanmış kalır'
    $sync.RegDenied.Clear()

    # ======================= 8) sol menü yoğunluğu =======================
    $script:RailMax = 56; $script:RailMin = 40
    Assert-Eq (Get-RailHeight 900 16) 56 'yer bolsa en yüksek düğme (56)'
    Assert-Eq (Get-RailHeight 640 16) 40 'yer azsa en alçak düğme (40)'
    Assert-Eq (Get-RailHeight 700 16) 43 'ara değer yuvarlanır (700 / 16)'
    Assert-Eq (Get-RailHeight 100 0) 56 'düğme yoksa varsayılan'
    $badRail = 0
    foreach ($av in 300..1300) {
        foreach ($cn in 1..20) {
            $h = Get-RailHeight $av $cn
            if ($h -lt 40 -or $h -gt 56) { $badRail++ }
            $nat = [math]::Floor($av / $cn)
            if ($nat -ge 40 -and $nat -le 56 -and ($h * $cn) -gt $av) { $badRail++ }
        }
    }
    Assert-Eq $badRail 0 'her pencere yüksekliği ve düğme sayısında yükseklik 40-56 arası; sığabiliyorsa taşmaz'
    # Update-RailDensity: sahte düğmelerle
    $script:PageTitles = [ordered]@{}
    $ui = @{}
    function Set-Visible($El, [bool]$On) { if ($On) { $El.Visibility = 'Visible' } else { $El.Visibility = 'Collapsed' } }
    $script:RailGroups = New-Object System.Collections.ArrayList
    $script:RailGroupsOn = $false
    foreach ($i in 1..16) { $k = 'p' + $i; $script:PageTitles[$k] = $k; $ui['Rail_' + $k] = [pscustomobject]@{ Visibility = 'Visible'; Height = 56.0; Parent = $null } }
    $script:VisOn = 'Visible'; $script:RailH = 0
    $ui['RailHost'] = [pscustomobject]@{ ActualHeight = 700.0 }
    Update-RailDensity
    Assert-Eq $ui['Rail_p1'].Height 42.0 '700 px pencere, 16 düğme: (700 - 20) / 16 = 42'
    Assert-Eq $ui['Rail_p16'].Height 42.0 'tüm düğmeler aynı yükseklikte'
    Assert-True ((42 * 16) -le (700 - 20)) 'düğmeler kaydırma payıyla birlikte sığar'
    $ui['RailHost'].ActualHeight = 0.0
    Update-RailDensity
    Assert-Eq $ui['Rail_p1'].Height 42.0 'pencere henüz ölçülmediyse yükseklik değişmez'
    foreach ($i in 9..16) { $ui['Rail_p' + $i].Visibility = 'Collapsed' }
    $ui['RailHost'].ActualHeight = 840.0
    Update-RailDensity
    Assert-Eq $ui['Rail_p1'].Height 56.0 'az düğme görünürse en yüksek düğme'
    Assert-Eq $ui['Rail_p16'].Height 56.0 'gizli düğmelerin yüksekliği de güncellenir (tekrar görününce taşmaz)'

    # açılır menü grupları (Sade yerleşim): kapalı grubun düğmeleri sayılmaz, görünen başlıklar yer kaplar
    foreach ($i in 9..16) { $ui['Rail_p' + $i].Visibility = 'Visible' }
    $pa = [pscustomobject]@{ Tag = 'rg:ana'; Visibility = 'Visible' }
    $pb = [pscustomobject]@{ Tag = 'rg:hiz'; Visibility = 'Visible' }
    foreach ($i in 1..8) { $ui['Rail_p' + $i].Parent = $pa }
    foreach ($i in 9..16) { $ui['Rail_p' + $i].Parent = $pb }
    Assert-True (Test-RailShown $ui['Rail_p1']) 'açık grubun görünen düğmesi sayılır'
    $pb.Visibility = 'Collapsed'
    Assert-True (-not (Test-RailShown $ui['Rail_p9'])) 'kapalı grubun düğmesi sayılmaz'
    $ui['Rail_p1'].Visibility = 'Collapsed'
    Assert-True (-not (Test-RailShown $ui['Rail_p1'])) 'gizli düğme sayılmaz'
    $ui['Rail_p1'].Visibility = 'Visible'
    Assert-True (-not (Test-RailShown $null)) 'boş düğme sayılmaz'
    Assert-True (Test-RailShown ([pscustomobject]@{ Visibility = 'Visible'; Parent = [pscustomobject]@{ Tag = 'baska' } })) 'ilgisiz kapta duran düğme sayılır'
    $ga = @{ Key = 'ana'; Pages = @('p1', 'p2'); Header = [pscustomobject]@{ Visibility = 'Collapsed' }; Open = $true; Shown = 0 }
    $gb = @{ Key = 'hiz'; Pages = @('p9', 'p10', 'p11'); Header = [pscustomobject]@{ Visibility = 'Collapsed' }; Open = $false; Shown = 0 }
    $gc = @{ Key = 'tek'; Pages = @('p16'); Header = [pscustomobject]@{ Visibility = 'Collapsed' }; Open = $true; Shown = 0 }
    [void]$script:RailGroups.Add($ga); [void]$script:RailGroups.Add($gb); [void]$script:RailGroups.Add($gc)
    $script:RailGroupsOn = $false
    Refresh-RailGroups
    Assert-Eq $ga.Header.Visibility 'Collapsed' 'gruplar kapalı kipteyken başlık görünmez'
    $script:RailGroupsOn = $true
    Refresh-RailGroups
    Assert-Eq $ga.Header.Visibility 'Visible' 'grup kipinde birden çok sayfası olan grubun başlığı görünür'
    Assert-Eq $gb.Header.Visibility 'Visible' 'kapalı grubun da başlığı görünür (açılabilsin)'
    Assert-Eq $gc.Header.Visibility 'Collapsed' 'tek sayfalı grubun başlığı görünmez'
    Assert-Eq $ga.Shown 2 'grupta görünen düğme sayısı'
    foreach ($i in 9..11) { $ui['Rail_p' + $i].Visibility = 'Collapsed' }
    Refresh-RailGroups
    Assert-Eq $gb.Header.Visibility 'Collapsed' 'grupta görünen düğme yoksa başlık da görünmez'
    # yükseklik: kapalı grubun düğmeleri ve başlıklar hesaba katılır
    foreach ($i in 9..16) { $ui['Rail_p' + $i].Visibility = 'Visible' }
    $pb.Visibility = 'Visible'
    $gb.Header.Visibility = 'Visible'; $ga.Header.Visibility = 'Visible'
    $script:RailH = 0
    $ui['RailHost'].ActualHeight = 840.0
    $script:RailGroupsOn = $false
    foreach ($g in @($ga, $gb, $gc)) { $g.Header.Visibility = 'Collapsed' }
    Update-RailDensity
    $hPlain = $ui['Rail_p1'].Height
    Assert-Eq $hPlain 51.0 '16 düğme, başlıksız: (840 - 20) / 16 = 51'
    $script:RailGroupsOn = $true; $script:RailH = 0
    Update-RailDensity
    Assert-True ($ui['Rail_p1'].Height -le $hPlain) 'grup başlıkları düğme yüksekliğini artırmaz'
    $hdrCount = @(@($ga, $gb, $gc) | Where-Object { $_.Header.Visibility -eq 'Visible' }).Count
    Assert-True (($ui['Rail_p1'].Height * 16 + 32 * $hdrCount) -le 820) 'düğmeler ve görünen başlıklar birlikte sığar'
    $pb.Visibility = 'Collapsed'; $script:RailH = 0
    Update-RailDensity
    Assert-True ($ui['Rail_p1'].Height -gt $hPlain - 0.5 -or $ui['Rail_p1'].Height -eq 56.0) 'bir grup kapanınca kalan düğmeler en az eskisi kadar yüksek olur'
    $script:RailGroups.Clear(); $script:RailGroupsOn = $false

    # ======================= 9) duman testi kuyruğu =======================
    Assert-True ($script:SmokeSafe.Count -ge 20) 'güvenli düğme listesi dolu'
    Assert-Eq (@($script:SmokeSafe | Select-Object -Unique).Count) $script:SmokeSafe.Count 'güvenli düğme listesinde yineleme yok'
    $danger = '(Apply|Uygula|Remove|Kaldir|Delete|Sil|Clean|Temizle|Install|Kur$|Fix|Repair|Onar|Kill|Stop|Block|Engelle|Kick|Reset|Format|Disable|Restore|Wipe|Encrypt)'
    # st_DsReset ve st_BoardReset yalnızca bu pencerenin görünümünü (tasarım ayrıntıları, ana ekran düzeni) varsayılana döndürür; duman testi kopya ayar dosyasıyla çalışır
    $dg = @($script:SmokeSafe | Where-Object { $_ -match $danger -and $_ -notin @('st_DsReset', 'st_BoardReset') })
    Assert-Eq ($dg -join ',') '' 'güvenli düğme listesinde eylem düğmesi yok'
    Assert-Eq (@($script:SmokeSafeSelect | Select-Object -Unique).Count) $script:SmokeSafeSelect.Count 'güvenli liste kümesinde yineleme yok'
    Assert-Eq (@($script:SmokeSafeSelect | Where-Object { $_ -notmatch '^st_[A-Za-z]+Sel$' }).Count) 0 'güvenli liste kümesi yalnızca Ayarlar açılır listelerinden oluşur'
    Assert-Eq (@($script:SmokeSafe | Where-Object { $_ -match 'Sel$' }).Count) 0 'açılır listeler güvenli düğme listesinde değil (seçimle sınanır)'
    $acts = @(Get-SmokeActions)
    Assert-Eq (@($acts | Where-Object { $script:SmokeSafe -notcontains $_[2] }).Count) 0 'salt okunur eylem listesindeki her düğme güvenli listededir'

    Assert-Eq ($script:SmokeThemes -join ',') 'Neon,Koyu,Acik,Kum,Yuksek,Hacker,Cam,Holo,Akis,Uzay' 'duman testinin temaları on temadır'
    Assert-Eq ($script:SmokeLayouts -join ',') 'Ayrintili,Kompakt,Sade,Hacker' 'duman testinin yerleşimleri dört yerleşimdir'
    foreach ($startTheme in @('Neon', 'Koyu', 'Acik', 'Yuksek', 'Hacker', 'Cam', 'Holo', 'Akis', 'Uzay')) {
      foreach ($startLayout in @('Ayrintili', 'Sade')) {
        $tag = $startTheme + '/' + $startLayout
        $q = New-SmokeQueue $startTheme @('panel', 'optimize', 'settings') { param($k) @() } $startLayout
        $steps = @($q.ToArray())
        $themeArgs = @($steps | Where-Object { $_.Kind -eq 'Theme' } | ForEach-Object { $_.Arg })
        foreach ($t in $script:SmokeThemes) { Assert-True (($themeArgs -contains $t) -or ($t -eq $startTheme)) ($tag + ': tema ' + $t + ' denenir') }
        Assert-Eq (@($themeArgs | Where-Object { $script:SmokeThemes -notcontains $_ }).Count) 0 ($tag + ': yalnızca bilinen temalar denenir')
        Assert-Eq $themeArgs[$themeArgs.Count - 1] $startTheme ($tag + ': son tema adımı başlangıç temasıdır')
        $layoutArgs = @($steps | Where-Object { $_.Kind -eq 'Layout' } | ForEach-Object { $_.Arg })
        Assert-Eq $layoutArgs[$layoutArgs.Count - 1] $startLayout ($tag + ': son yerleşim adımı başlangıç yerleşimidir')
        Assert-Eq (@($layoutArgs | Where-Object { $script:SmokeLayouts -notcontains $_ }).Count) 0 ($tag + ': yalnızca bilinen yerleşimler denenir')
        $clicks = @($steps | Where-Object { $_.Kind -eq 'Click' })
        Assert-Eq (@($clicks | Where-Object { $script:SmokeSafe -notcontains $_.Arg }).Count) 0 ($tag + ': tüm tıklamalar güvenli listededir')
        $sel = @($steps | Where-Object { $_.Kind -eq 'Select' } | ForEach-Object { [string]$_.Arg })
        $thSel = @($sel | Where-Object { $_ -like 'st_ThemeSel|*' })
        Assert-Eq $thSel.Count 10 ($tag + ': on temaya tema listesinden geçilir')
        Assert-Eq $thSel[$thSel.Count - 1] ('st_ThemeSel|' + $startTheme) ($tag + ': tema seçimlerinde başlangıç teması en sona kalır')
        $lySel = @($sel | Where-Object { $_ -like 'st_LayoutSel|*' })
        Assert-Eq ($lySel -join ',') 'st_LayoutSel|Kompakt,st_LayoutSel|Sade,st_LayoutSel|Hacker,st_LayoutSel|Ayrintili' ($tag + ': dört yerleşim listeden seçilir, ayrıntılı ile bitirilir')
        $prSel = @($sel | Where-Object { $_ -like 'st_LookSel|*' })
        Assert-Eq $prSel.Count 9 ($tag + ': dört eski ve beş yeni hazır görünüm listeden seçilir')
        $zmSel = @($sel | Where-Object { $_ -like 'st_ZoomSel|*' })
        Assert-Eq ($zmSel -join ',') 'st_ZoomSel|130,st_ZoomSel|80,st_ZoomSel|100' ($tag + ': yakınlaştırma %130, %80 ve %100 denenir')
        $dsSel = @($sel | Where-Object { $_ -like 'st_DesignSel|*' }).Count
        $hmSel = @($sel | Where-Object { $_ -like 'st_HomeSel|*' }).Count
        $bdSel = @($sel | Where-Object { $_ -like 'st_BackdropSel|*' }).Count
        $opSel = @($sel | Where-Object { $_ -like 'st_OpacitySel|*' }).Count
        $ovSel = @($sel | Where-Object { $_ -match '^st_Ds(Nav|Radius|Font|Graph|Skin)Sel\|' }).Count
        $edC = @($clicks | Where-Object { $_.Arg -eq 'bd_BtnEdit' }).Count
        $beC = @($clicks | Where-Object { $_.Arg -eq 'st_BoardEdit' }).Count
        $brC = @($clicks | Where-Object { $_.Arg -eq 'st_BoardReset' }).Count
        $drC = @($clicks | Where-Object { $_.Arg -eq 'st_DsReset' }).Count
        Assert-Eq "$dsSel|$hmSel|$bdSel|$opSel|$ovSel" ('19|' + $script:SmokeDesigns.Count + '|7|12|' + ($script:SmokeOverrides.Count + 5)) ($tag + ': tasarım, ana ekran, saydamlık, opaklık ve tasarım ayrıntısı listelerinden seçim sayıları')
        Assert-Eq "$edC|$beC|$brC|$drC" '15|5|5|1' ($tag + ': pano düzenleme, ana ekranı düzenle, düzeni sıfırla ve ayrıntıları sıfırla düğmelerine tıklanır')
        Assert-Eq $sel.Count (10 + 4 + 9 + 3 + $dsSel + $hmSel + $bdSel + $opSel + $ovSel) ($tag + ': seçimler = 10 tema + 4 yerleşim + 9 hazır görünüm + 3 yakınlaştırma + tasarım + ana ekran + saydamlık + opaklık + ayrıntı')
        $hmC = @($clicks | Where-Object { $_.Arg -eq 'BtnHome' }).Count
        Assert-Eq $hmC 1 ($tag + ': ana sayfa emblemine bir kez tıklanır (başka sayfadan durum panosuna dönüş)')
        Assert-Eq $clicks.Count (2 + $hmC + $acts.Count + $edC + $beC + $brC + $drC) ($tag + ': tıklamalar = 2 başlık düğmesi (günlük, komut satırı) + ana sayfa emblemi + salt okunur eylemler + pano düzenleme düğmeleri')
        Assert-Eq ($steps[$steps.Count - 1].Kind) 'Finish' ($tag + ': kuyruk Finish ile biter')
        $tray = @($steps | Where-Object { $_.Kind -like 'Tray*' } | ForEach-Object { if ($_.Kind -eq 'TrayCheck' -or $_.Kind -eq 'TrayClose') { $_.Kind + ':' + $_.Arg } else { $_.Kind } })
        $trayWant = 'TrayHide,TrayCheck:hidden,TraySignal,TrayWait,TrayCheck:shown,TrayHide,TrayShow,TrayCheck:shown,' +
            'TrayClose:btn,TrayCheck:hidden,TrayShow,TrayCheck:shown,TrayClose:alt,TrayCheck:hidden,TrayShow,TrayCheck:shown,' +
            'TrayMinOff,TrayCheck:minimized,TrayShow,TrayCheck:shown,TrayDone,' +
            'TrayCloseBusy,TrayCheck:hidden,TrayShow,TrayCheck:shown,TrayDone'
        Assert-Eq ($tray -join ',') $trayWant ($tag + ': tepsi adımları sırayla (simge durumu, sinyal, X, Alt+F4, tepsi kapalıyken küçültme, işlem sürerken X)')
        Assert-Eq (@($steps | Where-Object { $_.Kind -eq 'Console' }).Count) 1 ($tag + ': konsol hızlı düzenleme denetimi var')
        $rails = @($steps | Where-Object { $_.Kind -eq 'Rail' } | ForEach-Object { $_.Arg })
        Assert-Eq (($rails[0..2]) -join ',') 'fit,warn,fit' ($tag + ': sol menü denetimleri (varsayılan ve küçük pencere)')
        Assert-Eq (@($rails | Where-Object { $_ -eq 'fit' -or $_ -eq 'warn' }).Count) $rails.Count ($tag + ': sol menü denetimi yalnızca fit / warn')
        Assert-True ($rails.Count -ge 3 + 4 + 8) ($tag + ': her yerleşimde ve her tema-yerleşim eşleşmesinde sol menü sığma denetimi var')
        Assert-Eq (($steps | Where-Object { $_.Kind -eq 'Size' } | ForEach-Object { $_.Arg }) -join ',') ((@('1060x660,1380x840') * (1 + $script:SmokeDesigns.Count)) -join ',') ($tag + ': pencere en küçük boyuta indirilir ve varsayılana döner (önce sol menü denemesi, sonra her tasarım için)')
        $pageKinds = @($steps | Where-Object { $_.Kind -eq 'Page' -and $_.Arg -notin @('panel', 'optimize', 'settings') })
        Assert-True ($pageKinds.Count -gt 0) ($tag + ': eylem sayfaları gezilir')
        Assert-True ((@($steps | Where-Object { $_.Kind -eq 'Shot' }).Count) -gt 40) ($tag + ': ekran görüntüleri alınır (her tema, yerleşim, eşleşme, yakınlaştırma)')
        $kinds = @($steps | ForEach-Object { $_.Kind })
        $ci = [array]::IndexOf($kinds, 'Console')
        $ti = [array]::IndexOf($kinds, 'TrayHide')
        Assert-True ($ci -ge 0 -and $ti -gt $ci) ($tag + ': konsol denetimi tepsi denemesinden önce')
        # yerleşim ve yakınlaştırma doğrulamaları
        Assert-Eq (@($steps | Where-Object { $_.Kind -eq 'LayoutCheck' }).Count) 8 ($tag + ': 4 yerleşim + 4 hazır görünüm için kalıcı doğrulama')
        Assert-Eq (@($steps | Where-Object { $_.Kind -eq 'LayoutGeo' }).Count) 13 ($tag + ': 13 tema x yerleşim eşleşmesi için geometri doğrulaması')
        Assert-Eq (@($steps | Where-Object { $_.Kind -eq 'ZoomCheck' }).Count) 3 ($tag + ': yakınlaştırma doğrulamaları')
        $lcArgs = @($steps | Where-Object { $_.Kind -eq 'LayoutCheck' } | ForEach-Object { $_.Arg })
        foreach ($l in $script:SmokeLayouts) { Assert-True ($lcArgs -contains $l) ($tag + ': yerleşim ' + $l + ' doğrulanır') }
        $geoArgs = @($steps | Where-Object { $_.Kind -eq 'LayoutGeo' } | ForEach-Object { $_.Arg })
        foreach ($l in $script:SmokeLayouts) { Assert-True ($geoArgs -contains $l) ($tag + ': eşleşmede yerleşim ' + $l + ' görülür') }
        # her tema en az bir kez kalabalık olmayan bir yerleşimle de görüntülenir (Kompakt, Sade ya da Hacker)
        $pairs = @()
        $cur = ''
        foreach ($st in $steps) {
            if ($st.Kind -eq 'Theme') { $cur = [string]$st.Arg }
            elseif ($st.Kind -eq 'Layout' -and $cur -ne '') { $pairs += ($cur + '/' + [string]$st.Arg) }
        }
        foreach ($t in $script:SmokeThemes) {
            $calm = @($pairs | Where-Object { $_ -like ($t + '/*') -and $_ -ne ($t + '/Ayrintili') })
            Assert-True ($calm.Count -ge 1) ($tag + ': tema ' + $t + ' sade bir yerleşimle de denenir')
        }
        # kaydırma ve kısayol adımları sırayla
        $scroll = @($steps | Where-Object { $_.Kind -in @('ScrollMark', 'Wheel', 'Keys', 'ScrollCheck', 'ToTop', 'SmoothOff', 'SmoothOn') } | ForEach-Object { if ($_.Arg -ne '') { $_.Kind + ':' + $_.Arg } else { $_.Kind } })
        $scrollWant = 'Keys:Top,ScrollMark,Wheel:down,ScrollCheck:moved,Wheel:down,ScrollCheck:moved,ToTop:visible,Wheel:up,ScrollCheck:moved,Keys:PageDown,ScrollCheck:moved,Keys:PageUp,ScrollCheck:moved,Keys:Bottom,ScrollCheck:bottom,Keys:Top,ScrollCheck:top,ToTop:hidden,SmoothOff,Wheel:down,ScrollCheck:moved,SmoothOn,Keys:Top'
        Assert-Eq ($scroll -join ',') $scrollWant ($tag + ': kaydırma adımları (tekerlek, PageDown/PageUp, Home/End, başa dön, yumuşak kaydırma kapalı yol)')
        Assert-Eq ((@($steps | Where-Object { $_.Kind -eq 'HotKey' } | ForEach-Object { $_.Arg })) -join ',') 'NextPage,PrevPage,Settings' ($tag + ': kısayol adımları')
        $hi = [array]::IndexOf($kinds, 'Health')
        $bi = [array]::IndexOf($kinds, 'TrayCloseBusy')
        Assert-True ($hi -ge 0 -and $bi -gt $hi) ($tag + ': işlem sürerken X, sağlık taraması başladıktan sonra denenir')
        $di = [array]::IndexOf($kinds[($bi + 1)..($kinds.Count - 1)], 'Drain')
        Assert-True ($di -ge 0) ($tag + ': işlem sürerken X denemesinden sonra iş bitene kadar beklenir')
        # son adımlar: başlangıç teması ve yerleşimi geri yüklenir
        $lastKinds = @($steps[($steps.Count - 5)..($steps.Count - 1)] | ForEach-Object { $_.Kind })
        Assert-Eq ($lastKinds -join ',') 'Theme,Layout,Page,Drain,Finish' ($tag + ': kuyruk tema ve yerleşimi geri yükleyerek biter')
        # toplam bekleme süresi zaman aşımının yarısını aşmaz (ağır adımlara pay kalsın)
        $waitSec = 0.0
        foreach ($st in $steps) { $waitSec += [double]$st.Wait / 1000.0 }
        Assert-True ($waitSec -lt ([double]$script:SmokeLimitSec / 2.0)) ($tag + ': adım beklemeleri toplamı zaman aşımının yarısından az (' + [string][int]$waitSec + ' sn)')
      }
    }

    # ======================= 9b) duman testi kapsamları (hızlı yineleme için kısa kuyruklar) =======================
    Assert-Eq ((@($script:SmokeScopes.Keys) | Sort-Object) -join ',') 'dil,gorunum,kullanim,ozellik,saydam,tam,tasarim,tepsi,ust' 'duman testi kapsamları: tam, tepsi, gorunum, tasarim, saydam, dil, ust, kullanim, ozellik'
    $scopeSaved = $env:MM_DUMAN_KAPSAM
    try {
        $env:MM_DUMAN_KAPSAM = $null
        Assert-Eq (Get-SmokeScope) 'tam' 'kapsam ortam değişkeni yoksa tam'
        $env:MM_DUMAN_KAPSAM = 'tepsi'
        Assert-Eq (Get-SmokeScope) 'tepsi' 'kapsam: tepsi'
        $env:MM_DUMAN_KAPSAM = '  Gorunum '
        Assert-Eq (Get-SmokeScope) 'gorunum' 'kapsam adında büyük küçük harf ve boşluk önemsenmez'
        $env:MM_DUMAN_KAPSAM = 'bilinmeyen'
        Assert-Eq (Get-SmokeScope) 'tam' 'bilinmeyen kapsam tama döner'
    } finally { $env:MM_DUMAN_KAPSAM = $scopeSaved }
    $sk = @('panel', 'optimize', 'settings')
    $qTam = New-SmokeQueue 'Neon' $sk { param($k) @() } 'Ayrintili'
    $qTamAd = New-SmokeQueue 'Neon' $sk { param($k) @() } 'Ayrintili' 'tam'
    $qYok = New-SmokeQueue 'Neon' $sk { param($k) @() } 'Ayrintili' 'yok'
    Assert-Eq $qTamAd.Count $qTam.Count 'kapsam verilmezse tam kuyruk kurulur'
    Assert-Eq $qYok.Count $qTam.Count 'bilinmeyen kapsam tam kuyruk kurar'
    $tepsi = @((New-SmokeQueue 'Koyu' $sk { param($k) @() } 'Sade' 'tepsi').ToArray())
    $tk = @($tepsi | ForEach-Object { $_.Kind })
    Assert-True ($tepsi.Count -lt 70 -and $tepsi.Count -lt $qTam.Count / 5) ('tepsi kapsamı kısadır (' + $tepsi.Count + ' adım, tam ' + $qTam.Count + ')')
    Assert-True (($tk -contains 'TraySignal') -and ($tk -contains 'TrayWait') -and ($tk -contains 'TrayCloseBusy') -and ($tk -contains 'Health')) 'tepsi kapsamı sinyal, bekleme ve işlem sürerken X yollarını içerir'
    Assert-True (-not ($tk -contains 'Click') -and -not ($tk -contains 'Size') -and -not ($tk -contains 'Wheel')) 'tepsi kapsamı tıklama, boyut ve kaydırma adımı içermez'
    Assert-Eq (@($tepsi | Where-Object { $_.Kind -eq 'Theme' } | ForEach-Object { $_.Arg } | Select-Object -Unique) -join ',') 'Koyu' 'tepsi kapsamında tema değişmez'
    Assert-Eq (@($tepsi | Where-Object { $_.Kind -eq 'Layout' } | ForEach-Object { $_.Arg } | Select-Object -Unique) -join ',') 'Ayrintili,Sade' 'tepsi kapsamında yerleşim yalnızca ayrıntıya ve başlangıca ayarlanır'
    Assert-Eq ($tepsi[$tepsi.Count - 1].Kind) 'Finish' 'tepsi kapsamı Finish ile biter'
    Assert-Eq ($tepsi[0].Kind + ':' + $tepsi[0].Arg) 'Page:panel' 'tepsi kapsamı panel sayfasıyla başlar'
    $gor = @((New-SmokeQueue 'Neon' $sk { param($k) @() } 'Ayrintili' 'gorunum').ToArray())
    $gk = @($gor | ForEach-Object { $_.Kind })
    Assert-True ($gor.Count -gt 100 -and $gor.Count -lt $qTam.Count / 2) ('görünüm kapsamı tam kuyruğun yarısından kısadır (' + $gor.Count + ' adım, tam ' + $qTam.Count + ')')
    $pageRx = '^sayfa \S+ / (' + ($script:SmokeThemes -join '|') + ')$'
    Assert-Eq (@($gor | Where-Object { $_.Kind -eq 'Page' -and $_.Label -match $pageRx }).Count) ($sk.Count * $script:SmokeThemes.Count) 'görünüm kapsamında her tema her sayfayı açar'
    Assert-True (-not (@($gk | Where-Object { $_ -like 'Tray*' }).Count) -and -not ($gk -contains 'Health') -and -not ($gk -contains 'Wheel')) 'görünüm kapsamı tepsi, tarama ve kaydırma adımı içermez'
    Assert-Eq (@($gor | Where-Object { $_.Kind -eq 'Select' -and $_.Arg -like 'st_ThemeSel|*' }).Count) 10 'görünüm kapsamında on temaya tema listesinden geçilir'
    Assert-Eq (@($gor | Where-Object { $_.Kind -eq 'Click' -and $script:SmokeSafe -notcontains $_.Arg }).Count) 0 'görünüm kapsamının tıklamaları güvenli listededir'
    Assert-True ((@($gor | Where-Object { $_.Kind -eq 'Shot' }).Count) -gt 60) 'görünüm kapsamı ekran görüntüsü alır'
    Assert-True (-not ($gk -contains 'DesignCheck') -and -not ($gk -contains 'GlassCheck') -and -not ($gk -contains 'BoardAdd')) 'görünüm kapsamı tasarım, saydamlık ve pano adımı içermez'

    # tasarım kapsamı: her tasarım ve her tema denenir, sonunda Klasik tasarıma dönülür
    $tas = @((New-SmokeQueue 'Neon' $sk { param($k) @() } 'Ayrintili' 'tasarim').ToArray())
    $tsk = @($tas | ForEach-Object { $_.Kind })
    $nd = $script:SmokeDesigns.Count
    Assert-Eq ($script:SmokeDesigns -join ',') 'Klasik,Atolye,Sifir,Morpheus,Komuta' 'duman testi Klasik dahil beş tasarımı sınar'
    Assert-Eq ($tas[0].Kind + ':' + $tas[0].Arg) 'Page:panel' 'tasarım kapsamı panel sayfasıyla başlar'
    Assert-Eq (@($tas | Where-Object { $_.Kind -eq 'Click' -and $script:SmokeSafe -notcontains $_.Arg }).Count) 0 'tasarım kapsamının tıklamaları güvenli listededir'
    Assert-Eq (@($tas | Where-Object { $_.Kind -eq 'Select' -and $script:SmokeSafeSelect -notcontains $_.Arg.Split('|')[0] }).Count) 0 'tasarım kapsamının liste seçimleri güvenli liste kümesindedir'
    $dsSelT = @($tas | Where-Object { $_.Kind -eq 'Select' -and $_.Arg -like 'st_DesignSel|*' } | ForEach-Object { [string]$_.Arg.Substring(13) })
    Assert-Eq $dsSelT.Count (2 * $nd + 5) 'tasarım kapsamı: her tasarım iki kez (ilk deneme, tema dizisi) ve beş kez ayrıntı/Klasik dönüşü seçilir'
    Assert-Eq $dsSelT[$dsSelT.Count - 1] 'Klasik' 'tasarım kapsamı son tasarım seçimiyle Klasik tasarıma döner'
    $dcs = @($tas | Where-Object { $_.Kind -eq 'DesignCheck' })
    Assert-Eq $dcs.Count (2 * $nd + 2) 'tasarım kapsamı: her tasarım iki kez (pano, klasik ana ekran) ve iki Klasik dönüşü doğrulanır'
    Assert-Eq $dcs[$dcs.Count - 1].Arg 'Klasik' 'tasarım kapsamı: son tasarım doğrulaması Klasik'
    $navOv = @($script:SmokeOverrides | Where-Object { $_[0] -eq 'Nav' }).Count
    Assert-Eq (@($tas | Where-Object { $_.Kind -eq 'NavMenu' }).Count) ($nd + $navOv) 'tasarım kapsamı: menü denemesi her tasarımda ve her menü biçimi ayrıntısında'
    foreach ($k in @('BoardAdd', 'BoardRemove', 'BoardLayoutMenu', 'BoardPreset')) { Assert-Eq (@($tas | Where-Object { $_.Kind -eq $k }).Count) $nd ('tasarım kapsamı: ' + $k + ' her tasarımda bir kez') }
    Assert-Eq (@($tas | Where-Object { $_.Kind -eq 'Click' -and $_.Arg -eq 'st_BoardReset' }).Count) $nd 'tasarım kapsamı: ana ekran düzenini sıfırla her tasarımda bir kez'
    Assert-Eq (@($tas | Where-Object { $_.Kind -eq 'BoardCheck' -and $_.Arg -eq 'reset' }).Count) $nd 'tasarım kapsamı: sıfırlamadan sonra pano doğrulanır'
    Assert-Eq (@($tas | Where-Object { $_.Kind -eq 'HomeCheck' }).Count) (3 * $nd) 'tasarım kapsamı: ana ekran biçimi her tasarımda üç kez doğrulanır'
    Assert-Eq ((@($tas | Where-Object { $_.Kind -eq 'PresetCheck' } | ForEach-Object { $_.Arg })) -join ',') ($script:SmokePresets -join ',') 'tasarım kapsamı: hazır görünümlerin hepsi doğrulanır'
    Assert-Eq ((@($tas | Where-Object { $_.Kind -eq 'Select' -and $_.Arg -like 'st_LookSel|*' } | ForEach-Object { $_.Arg })) -join ',') ((@($script:SmokePresets | ForEach-Object { 'st_LookSel|' + $_ })) -join ',') 'tasarım kapsamı: hazır görünümler listeden sırayla seçilir'
    $curD = ''
    $seenDT = @{}
    foreach ($st in $tas) {
        if ($st.Kind -eq 'Select' -and $st.Arg -like 'st_DesignSel|*') { $curD = [string]$st.Arg.Substring(13) }
        elseif ($st.Kind -eq 'Theme') { $seenDT[$curD + '/' + [string]$st.Arg] = $true }
    }
    foreach ($d in $script:SmokeDesigns) { foreach ($t in $script:SmokeThemes) { Assert-True ($seenDT.ContainsKey($d + '/' + $t)) ('tasarım kapsamı: ' + $d + ' tasarımı ' + $t + ' temasıyla denenir') } }
    Assert-Eq (@($tas | Where-Object { $_.Kind -eq 'Size' } | ForEach-Object { $_.Arg }) -join ',') ((@('1060x660,1380x840') * $nd) -join ',') 'tasarım kapsamı: her tasarım en küçük pencerede denenir ve varsayılan boyuta döner'
    Assert-True (-not (@($tsk | Where-Object { $_ -like 'Tray*' }).Count) -and -not ($tsk -contains 'Health') -and -not ($tsk -contains 'Wheel') -and -not ($tsk -contains 'GlassCheck') -and -not ($tsk -contains 'Rail')) 'tasarım kapsamı tepsi, tarama, kaydırma, sol menü sığma ve saydamlık adımı içermez'
    Assert-Eq ((@($tas[($tas.Count - 5)..($tas.Count - 1)] | ForEach-Object { $_.Kind })) -join ',') 'Theme,Layout,Page,Drain,Finish' 'tasarım kapsamı tema ve yerleşimi geri yükleyerek biter'
    $tasShots = @($tas | Where-Object { $_.Kind -eq 'Shot' -or $_.Kind -eq 'Screen' } | ForEach-Object { $_.Kind + ':' + $_.Arg })
    Assert-Eq (@($tasShots | Select-Object -Unique).Count) $tasShots.Count 'tasarım kapsamı: görüntü dosya adları benzersiz (biri ötekinin üzerine yazmaz)'
    Assert-True ($tasShots.Count -gt 10 * $nd) ('tasarım kapsamı çok sayıda görüntü alır (' + $tasShots.Count + ')')
    $tasWait = 0.0
    foreach ($st in $tas) { $tasWait += [double]$st.Wait / 1000.0 }
    Assert-True ($tasWait -lt ([double]$script:SmokeLimitSec / 2.0)) ('tasarım kapsamı: adım beklemeleri toplamı zaman aşımının yarısından az (' + [string][int]$tasWait + ' sn)')
    Assert-True (-not ($tsk -contains 'Design') -and -not ($tsk -contains 'Glass')) 'başlangıç tasarımı Klasik ve saydamlık kapalıysa başa ve sona geri yükleme adımı eklenmez'
    # başlangıç tasarımı ya da saydamlığı farklıysa kuyruk Klasik / düz pencereyle başlar ve sonda kullanıcının ayarlarını geri yükler
    $tasD = @((New-SmokeQueue 'Neon' $sk { param($k) @() } 'Sade' 'tasarim' 'Morpheus' 'Akrilik|70').ToArray())
    Assert-Eq ($tasD[0].Kind + ':' + $tasD[0].Arg + ',' + $tasD[1].Kind + ':' + $tasD[1].Arg) 'Design:Klasik,Glass:Yok|100' 'başlangıç tasarımı Morpheus ise kuyruk Klasik tasarım ve düz pencereyle başlar'
    Assert-Eq ((@($tasD[($tasD.Count - 7)..($tasD.Count - 1)] | ForEach-Object { $_.Kind + ':' + $_.Arg })) -join ',') 'Design:Morpheus,Glass:Akrilik|70,Theme:Neon,Layout:Sade,Page:panel,Drain:,Finish:' 'kuyruk sonunda tasarım, saydamlık, tema ve yerleşim kullanıcının değerlerine döner'
    $tasH = @((New-SmokeQueue 'Neon' $sk { param($k) @() } 'Sade' 'tasarim' 'Morpheus' 'Akrilik|70' 'Klasik|Fly|Pill|Mono|none|Glass').ToArray())
    Assert-Eq ((@($tasH[0..2] | ForEach-Object { $_.Kind + ':' + $_.Arg })) -join ',') 'Design:Klasik,Glass:Yok|100,HomeSet:Pano|Auto|Auto|Auto|Auto|Auto' 'başlangıçta ana ekran klasik ve ayrıntılar seçiliyse kuyruk pano ve tasarımın kendi değerleriyle başlar'
    Assert-Eq ((@($tasH[($tasH.Count - 8)..($tasH.Count - 1)] | ForEach-Object { $_.Kind + ':' + $_.Arg })) -join ',') 'Design:Morpheus,Glass:Akrilik|70,HomeSet:Klasik|Fly|Pill|Mono|none|Glass,Theme:Neon,Layout:Sade,Page:panel,Drain:,Finish:' 'kuyruk sonunda ana ekran biçimi ve ayrıntılar kullanıcının değerlerine döner'
    Assert-Eq (@($tas | Where-Object { $_.Kind -eq 'HomeSet' }).Count) 0 'başlangıç durumu bilinen değerdeyse HomeSet adımı eklenmez'

    # saydam kapsamı: her saydamlık düğmesine ve opaklığa tıklanır, hemen ardından doğrulanır ve gerçek ekran görüntüsü alınır
    $say = @((New-SmokeQueue 'Neon' $sk { param($k) @() } 'Ayrintili' 'saydam').ToArray())
    $sayk = @($say | ForEach-Object { $_.Kind })
    Assert-Eq ($say[0].Kind + ':' + $say[0].Arg) 'Page:panel' 'saydam kapsamı panel sayfasıyla başlar'
    Assert-Eq (@($say | Where-Object { $_.Kind -eq 'Click' -and $script:SmokeSafe -notcontains $_.Arg }).Count) 0 'saydam kapsamının tıklamaları güvenli listededir'
    Assert-Eq (@($say | Where-Object { $_.Kind -eq 'Select' -and $script:SmokeSafeSelect -notcontains $_.Arg.Split('|')[0] }).Count) 0 'saydam kapsamının liste seçimleri güvenli liste kümesindedir'
    $bdClicks = @($say | Where-Object { $_.Kind -eq 'Select' -and $_.Arg -like 'st_BackdropSel|*' } | ForEach-Object { [string]$_.Arg.Substring(15) })
    Assert-Eq $bdClicks.Count 7 'saydam kapsamı: yedi saydamlık seçimi (iki efekt, sayfa dizisi, üç tasarım eşleşmesi, kapatma)'
    Assert-Eq $bdClicks[$bdClicks.Count - 1] 'Yok' 'saydam kapsamı pencereyi düz renge döndürerek biter'
    foreach ($m in @('Mica', 'Akrilik')) { Assert-True ($bdClicks -contains $m) ('saydam kapsamı ' + $m + ' seçeneğini listeden seçer') }
    $pendG = ''
    $okG = 0
    $badG = 0
    $pendO = ''
    $okO = 0
    $badO = 0
    $curM = ''
    $seenMT = @{}
    foreach ($st in $say) {
        if ($st.Kind -eq 'Select' -and $st.Arg -like 'st_BackdropSel|*') {
            if ($pendG -ne '') { $badG++ }
            $pendG = [string]$st.Arg.Substring(15)
            $curM = $pendG
        }
        elseif ($st.Kind -eq 'Select' -and $st.Arg -like 'st_OpacitySel|*') {
            if ($pendO -ne '') { $badO++ }
            $pendO = [string]$st.Arg.Substring(14)
        }
        elseif ($st.Kind -eq 'GlassCheck') {
            if ($pendG -ne '') { if ($st.Arg -like ($pendG + '|*')) { $okG++ } else { $badG++ }; $pendG = '' }
            if ($pendO -ne '') { if ($st.Arg -like ('*|' + $pendO)) { $okO++ } else { $badO++ }; $pendO = '' }
        }
        elseif ($st.Kind -eq 'Theme') { $seenMT[$curM + '/' + [string]$st.Arg] = $true }
    }
    Assert-Eq ($okG.ToString() + '|' + $badG.ToString() + '|' + $pendG) '7|0|' 'saydam kapsamı: her saydamlık düğmesinden sonra aynı seçenek doğrulanır'
    Assert-Eq ($okO.ToString() + '|' + $badO.ToString() + '|' + $pendO) '12|0|' 'saydam kapsamı: her opaklık düğmesinden sonra aynı opaklık doğrulanır'
    foreach ($m in @('Mica', 'Akrilik')) { foreach ($t in $script:SmokeThemes) { Assert-True ($seenMT.ContainsKey($m + '/' + $t)) ('saydam kapsamı: ' + $m + ' seçeneği ' + $t + ' temasıyla denenir') } }
    $nOps = 0
    foreach ($m in @($script:SmokeGlassOps.Keys)) { $nOps += @($script:SmokeGlassOps[$m]).Count }
    Assert-Eq (@($say | Where-Object { $_.Kind -eq 'Screen' }).Count) (1 + $nOps + $script:SmokeGlassOps.Count * $script:SmokeThemes.Count + 1 + 4 + 3 + 1) 'saydam kapsamı: kapalı, her opaklık, her tema, açık liste, dört sayfa, üç tasarım eşleşmesi ve geri dönüş için gerçek ekran görüntüsü'
    $sayShots = @($say | Where-Object { $_.Kind -eq 'Shot' -or $_.Kind -eq 'Screen' } | ForEach-Object { $_.Kind + ':' + $_.Arg })
    Assert-Eq (@($sayShots | Select-Object -Unique).Count) $sayShots.Count 'saydam kapsamı: görüntü dosya adları benzersiz'
    $dsSay = @($say | Where-Object { $_.Kind -eq 'Select' -and $_.Arg -like 'st_DesignSel|*' } | ForEach-Object { $_.Arg })
    Assert-Eq ($dsSay -join ',') 'st_DesignSel|Morpheus,st_DesignSel|Komuta,st_DesignSel|Atolye,st_DesignSel|Klasik' 'saydam kapsamı: üç tasarım saydamlıkla denenir ve Klasik tasarıma dönülür'
    Assert-True (-not (@($sayk | Where-Object { $_ -like 'Tray*' }).Count) -and -not ($sayk -contains 'Health') -and -not ($sayk -contains 'Wheel') -and -not ($sayk -contains 'BoardAdd') -and -not ($sayk -contains 'Size')) 'saydam kapsamı tepsi, tarama, kaydırma, pano düzenleme ve boyut adımı içermez'
    Assert-Eq ((@($say[($say.Count - 5)..($say.Count - 1)] | ForEach-Object { $_.Kind })) -join ',') 'Theme,Layout,Page,Drain,Finish' 'saydam kapsamı tema ve yerleşimi geri yükleyerek biter'
    $sayWait = 0.0
    foreach ($st in $say) { $sayWait += [double]$st.Wait / 1000.0 }
    Assert-True ($sayWait -lt ([double]$script:SmokeLimitSec / 2.0)) ('saydam kapsamı: adım beklemeleri toplamı zaman aşımının yarısından az (' + [string][int]$sayWait + ' sn)')
    $sayD = @((New-SmokeQueue 'Koyu' $sk { param($k) @() } 'Sade' 'saydam' 'Komuta' 'Akrilik|60').ToArray())
    Assert-Eq ($sayD[0].Kind + ':' + $sayD[0].Arg + ',' + $sayD[1].Kind + ':' + $sayD[1].Arg) 'Design:Klasik,Glass:Yok|100' 'saydam kapsamı da Klasik tasarım ve düz pencereyle başlar'
    Assert-Eq ((@($sayD[($sayD.Count - 7)..($sayD.Count - 1)] | ForEach-Object { $_.Kind + ':' + $_.Arg })) -join ',') 'Design:Komuta,Glass:Akrilik|60,Theme:Koyu,Layout:Sade,Page:panel,Drain:,Finish:' 'saydam kapsamı sonunda kullanıcının tasarımı ve saydamlığı geri yüklenir'
    # dil kapsamı: tek temada her sayfa ve sekme gezilir; her ekran görüntüsünün ardından dil denetimi adımı gelir
    $env:MM_DUMAN_KAPSAM = $null
    $dilKeys = @('panel', 'settings')
    $qDil = New-SmokeQueue 'Neon' $dilKeys { param($k) if ($k -eq 'settings') { @('Dil', 'Görünüm') } else { @() } } 'Ayrintili' 'dil'
    $dilSteps = @($qDil.ToArray())
    $dilKinds = @($dilSteps | ForEach-Object { $_.Kind })
    Assert-Eq (@($dilKinds | Where-Object { $_ -eq 'LangScan' }).Count) 4 'dil kapsamı: iki sayfa ve iki sekme için dört dil denetimi adımı'
    Assert-Eq (@($dilSteps | Where-Object { $_.Kind -eq 'Theme' -and $_.Arg -ne 'Neon' }).Count) 0 'dil kapsamı: başlangıç temasından başka temaya geçilmez (tek temada gezilir)'
    $dilBad = 0
    for ($di = 0; $di -lt $dilSteps.Count; $di++) {
        if ($dilSteps[$di].Kind -eq 'LangScan' -and ($di -eq 0 -or $dilSteps[$di - 1].Kind -ne 'Shot')) { $dilBad++ }
    }
    Assert-Eq $dilBad 0 'dil kapsamı: her dil denetimi bir ekran görüntüsünün hemen ardından gelir'
    Assert-Eq ((@($dilSteps | Where-Object { $_.Kind -eq 'LangScan' } | ForEach-Object { $_.Arg })) -join ',') 'panel,settings,settings/Dil,settings/Görünüm' 'dil kapsamı: denetim adımlarının konumu sayfa ve sekme adını taşır'
    Assert-True (@($dilKinds | Where-Object { $_ -in @('Tray', 'TrayHide', 'Mode', 'Widget', 'Overlay', 'Toasts', 'Templates', 'Zoom', 'Design', 'Glass') }).Count -eq 0) 'dil kapsamı: tepsi, tasarım ve saydamlık adımları yok'
    $dilTail = @($dilKinds[($dilKinds.Count - 5)..($dilKinds.Count - 1)])
    Assert-Eq ($dilTail -join ',') 'Theme,Layout,Page,Drain,Finish' 'dil kapsamı: kuyruk tema ve yerleşimi geri yükleyerek biter'
    $tamKinds = @((New-SmokeQueue 'Neon' $dilKeys { param($k) @() } 'Ayrintili' 'tam').ToArray() | ForEach-Object { $_.Kind })
    Assert-True (@($tamKinds | Where-Object { $_ -eq 'LangScan' }).Count -eq 0) 'tam kapsamda dil denetimi adımı yok'
    # Duman-Dil.cmd: ASCII, CRLF; dil kapsamını ve izlemeyi açar, Duman-Testi.cmd'yi sessiz çağırır, sonuçları dil klasörlerine kopyalar
    $dp = Join-Path $script:TestDir 'araclar/Duman-Dil.cmd'
    Assert-True (Test-Path -LiteralPath $dp) 'Duman-Dil.cmd araclar klasöründe'
    if (Test-Path -LiteralPath $dp) {
        $db = [System.IO.File]::ReadAllBytes($dp)
        Assert-Eq (@($db | Where-Object { $_ -ge 128 }).Count) 0 'Duman-Dil.cmd yalnızca ASCII'
        $dt = [System.Text.Encoding]::ASCII.GetString($db)
        Assert-True ((($dt -replace "`r`n", '').IndexOf("`n") -lt 0)) 'Duman-Dil.cmd satır sonları CRLF'
        Assert-True ($dt -match 'set "MM_DUMAN_KAPSAM=dil"') 'Duman-Dil.cmd dil kapsamını ayarlar'
        Assert-True ($dt -match 'set "MM_DIL_IZLE=1"') 'Duman-Dil.cmd dil izlemeyi açar'
        Assert-True ($dt -match 'set "MM_DIL=%~1"') 'Duman-Dil.cmd her dil için MM_DIL ayarlar'
        Assert-True ($dt -match 'call "%MM_HERE%Duman-Testi\.cmd" /sessiz') 'Duman-Dil.cmd Duman-Testi.cmd dosyasını sessiz çağırır'
        # shift %0 değerini de kaydırır: klasör yolu bağımsız değişkenler okunmadan önce saklanmalı ve sonrasında %~dp0 kullanılmamalı
        $dtLines = @($dt -split "`r`n")
        $hereIdx = -1; $shiftIdx = -1; $dp0After = 0
        for ($li = 0; $li -lt $dtLines.Count; $li++) {
            $ln = $dtLines[$li]
            if ($ln -match '^\s*rem\b') { continue }
            if ($hereIdx -lt 0 -and $ln -match 'set "MM_HERE=%~dp0"') { $hereIdx = $li; continue }
            if ($shiftIdx -lt 0 -and $ln -match '\bshift\b') { $shiftIdx = $li }
            if ($shiftIdx -ge 0 -and $ln -match '%~dp0') { $dp0After++ }
        }
        Assert-True ($hereIdx -ge 0 -and ($shiftIdx -lt 0 -or $hereIdx -lt $shiftIdx)) 'Duman-Dil.cmd: klasör yolu shift öncesinde MM_HERE içine alınır'
        Assert-Eq $dp0After 0 'Duman-Dil.cmd: shift sonrasında %~dp0 kullanılmaz'
        Assert-True ($dt -match 'Multimizer-duman-dil\.txt') 'Duman-Dil.cmd dil raporunu toplar'
        Assert-True ($dt -match 'set "MM_LANGS=tr en de zh ja ar"') 'Duman-Dil.cmd varsayılan diller: tr en de zh ja ar'
    }
    # tam kuyrukta görüntü adları benzersiz (aynı adla kaydedilen görüntü ötekinin üzerine yazılırdı)
    $allShots = @($qTam.ToArray() | Where-Object { $_.Kind -eq 'Shot' -or $_.Kind -eq 'Screen' } | ForEach-Object { $_.Kind + ':' + $_.Arg })
    $dupShots = @($allShots | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
    Assert-Eq ($dupShots -join ',') '' 'tam kuyrukta hiçbir görüntü adı iki kez kullanılmaz'
    # kapsam sarmalayıcıları: ASCII, CRLF, doğru kapsam adı ve asıl betiği çağırır
    foreach ($w in @(@('Duman-Tepsi.cmd', 'tepsi'), @('Duman-Gorunum.cmd', 'gorunum'), @('Duman-Dokunma.cmd', 'dokunma'), @('Duman-Tasarim.cmd', 'tasarim'), @('Duman-Saydam.cmd', 'saydam'), @('Duman-Ust.cmd', 'ust'))) {
        $wp = Join-Path $script:TestDir ('araclar/' + $w[0])
        Assert-True (Test-Path -LiteralPath $wp) ($w[0] + ' araclar klasöründe')
        if (Test-Path -LiteralPath $wp) {
            $wb = [System.IO.File]::ReadAllBytes($wp)
            Assert-Eq (@($wb | Where-Object { $_ -ge 128 }).Count) 0 ($w[0] + ' yalnızca ASCII')
            $wt = [System.Text.Encoding]::ASCII.GetString($wb)
            Assert-True ((($wt -replace "`r`n", '').IndexOf("`n") -lt 0)) ($w[0] + ' satır sonları CRLF')
            Assert-True ($wt -match ('set "MM_DUMAN_KAPSAM=' + $w[1] + '"')) ($w[0] + ' kapsamı ' + $w[1] + ' olarak ayarlar')
            Assert-True ($script:SmokeScopes.ContainsKey($w[1])) ($w[0] + ': kapsam adı tanımlı')
            Assert-True ($wt -match 'call "%~dp0Duman-Testi\.cmd" %\*') ($w[0] + ' Duman-Testi.cmd dosyasını çağırır')
        }
    }

    # ======================= 10) duman testi günlük okuyucusu =======================
    $lf = Join-Path $root 'kayit.txt'
    $rows = @(
        '12:00:01  INFO  Başladı',
        '12:00:02  ERR   Gerçek bir hata',
        '   devam satırı',
        '12:00:03  WARN  Bir uyarı',
        "HATA-AKISI: The term 'Foo' is not recognized  [CommandNotFoundException; ObjectNotFound; Foo]",
        'HATA-AKISI: Access denied  [UnauthorizedAccessException; PermissionDenied]'
    )
    [System.IO.File]::WriteAllText($lf, (($rows -join "`r`n") + "`r`n"), (New-Object System.Text.UTF8Encoding($true)))
    $script:LogFile = $lf; $script:SmokeLogPos = 0; $script:SmokeErrs = New-Object System.Collections.ArrayList; $script:SmokeWarns = 0; $script:SmokeCur = 'deneme'
    $n = Read-SmokeLogDelta
    Assert-Eq $n 2 'ERR kaydı ve program hatası kimlikli akış kaydı hata sayılır'
    Assert-Eq $script:SmokeWarns 2 'WARN ve diğer akış kayıtları yalnızca uyarıdır'
    Assert-Eq $script:SmokeErrs.Count 2 'iki hata listelenir'
    Assert-True ($script:SmokeErrs[0].Msg -like '*devam satırı*') 'çok satırlı girdi birleştirilir'
    Assert-Eq (Read-SmokeLogDelta) 0 'aynı kayıtlar ikinci kez sayılmaz'
    [System.IO.File]::AppendAllText($lf, "12:00:09  ERR   ikinci hata`r`n", (New-Object System.Text.UTF8Encoding($true)))
    Assert-Eq (Read-SmokeLogDelta) 1 'yalnızca yeni girdi sayılır'

    # beklenen (bilerek yapılan olumsuz deneme) satırları hata sayılmaz ama yazıldıkları doğrulanır
    $script:SmokeExpect.Clear()
    Add-SmokeExpect 'beklenen hata' 1 'beklenen hata satırı yazılmadı'
    Add-SmokeExpect 'beklenen uyarı' 2 'beklenen uyarı satırları yazılmadı'
    Add-SmokeExpect 'hiç yazılmayacak' 1 'yazılmayan satır'
    $w0 = $script:SmokeWarns
    [System.IO.File]::AppendAllText($lf, "12:01:00  ERR   beklenen hata burada`r`n12:01:01  WARN  beklenen uyarı 1`r`n12:01:02  WARN  beklenen uyarı 2`r`n12:01:03  WARN  beklenen uyarı 3`r`n12:01:04  ERR   beklenen hata ikinci kez`r`n", (New-Object System.Text.UTF8Encoding($true)))
    $nx = Read-SmokeLogDelta
    Assert-Eq $nx 1 'beklenen ERR satırı hata sayılmaz; fazladan gelen aynı satır hata sayılır'
    Assert-Eq ($script:SmokeWarns - $w0) 1 'beklenen WARN satırları uyarı sayılmaz; fazladan gelen sayılır'
    $miss = @(Get-SmokeExpectMissing)
    Assert-Eq $miss.Count 1 'yazılmayan beklenen satır eksik listesinde'
    Assert-True ($miss[0] -like '*yazılmayan satır*' -and $miss[0] -like '*beklenen 1, görülen 0*') 'eksik beklenen satırın nedeni ve sayısı yazılır'
    Assert-True (Test-SmokeExpected 'hiç yazılmayacak burada') 'beklenti metne uyunca tüketilir'
    Assert-Eq @(Get-SmokeExpectMissing).Count 0 'tüketilen beklenti eksik sayılmaz'
    Assert-True (-not (Test-SmokeExpected 'hiç yazılmayacak burada')) 'tüketilen beklenti ikinci kez eşleşmez'
    $script:SmokeExpect.Clear()

    # ======================= 11) derlenmiş betikte bağlantı denetimleri (AST) =======================
    $text = [System.IO.File]::ReadAllText($env:MM_BUILD)
    $ast = $script:Ast
    $fns = @(Get-AstFunctions)
    $dups = @($fns | Group-Object { $_.Name } | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
    Assert-Eq ($dups -join ',') '' 'hiçbir işlev iki kez tanımlı değil (PowerShell sessizce sonuncuyu kullanır)'
    $pn = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
    foreach ($p in @('Tepsi', 'Cli', 'Gorev', 'Profil', 'Deger', 'OzTest', 'Sessiz', 'Duman')) { Assert-True ($pn -contains $p) ('parametre: -' + $p) }
    # duman testinin her adım türünün bir işleyicisi var (yoksa gerçek bilgisayarda "bilinmeyen adım türü" hatası çıkar)
    $handlers = @{}
    foreach ($fname in @('Invoke-SmokeStep', 'Invoke-SmokeStepLook')) {
        $fd = @($fns | Where-Object { $_.Name -eq $fname })
        Assert-Eq $fd.Count 1 ($fname + ' tek kez tanımlı')
        if ($fd.Count -eq 1) {
            $sws = @($fd[0].FindAll({ param($n) $n -is [System.Management.Automation.Language.SwitchStatementAst] }, $true))
            foreach ($sw in $sws) {
                foreach ($cl in $sw.Clauses) {
                    if ($cl.Item1 -is [System.Management.Automation.Language.StringConstantExpressionAst]) { $handlers[[string]$cl.Item1.Value] = $fname }
                }
            }
        }
    }
    $usedKinds = @($qTam.ToArray() | ForEach-Object { [string]$_.Kind } | Select-Object -Unique)
    $noHandler = @($usedKinds | Where-Object { -not $handlers.ContainsKey($_) })
    Assert-Eq ($noHandler -join ',') '' 'tam kuyruktaki her adım türünün işleyicisi var'
    foreach ($k in @('Design', 'Glass', 'HomeSet', 'HomeCheck', 'OverrideCheck', 'ComboCheck', 'DropDownCheck', 'Check', 'Reveal', 'DesignCheck', 'GlassCheck', 'PresetCheck', 'BoardCheck', 'BoardAdd', 'BoardRemove', 'BoardLayoutMenu', 'BoardPreset', 'BoardReset', 'NavMenu', 'Screen', 'Backdrop', 'GlassVisible', 'Drag')) { Assert-Eq ([string]$handlers[$k]) 'Invoke-SmokeStepLook' ('adım türü ' + $k + ' tasarım/saydamlık işleyicisinde') }
    Assert-True ($text -match 'default \{ \[void\]\(Invoke-SmokeStepLook \$St\) \}') 'bilinmeyen adım türleri tasarım/saydamlık işleyicisine gider ve çıktısı atılır (sızan değer yeniden denemeye yol açmaz)'
    Assert-True ($text -match 'if \(\$script:RunFailed\) \{ return 4 \}') 'pencere açılamazsa çıkış kodu 4'
    Assert-True ($text -match 'if \(\$script:StormDone -and -not \$script:SmokeMode\) \{ return 5 \}') 'hata fırtınasında çıkış kodu 5'
    Assert-True ($text -match 'Add_DispatcherUnhandledException' -and $text -match '\$storm = Register-UiError' -and $text -match 'if \(\$storm\) \{ Stop-ErrorStorm \}') 'yakalanmamış hata -> fırtına denetimi bağlı'
    Assert-True ($text -match '\[void\]\$app\.Run\(\$w\)') 'Run çağrısı try içinde, hata günlüğe ve ileti kutusuna gider'
    Assert-True ($text -match 'Show-StartFailure \$runMsg' -and $text -match 'Show-StartFailure \$msg') 'başlatma hataları kullanıcıya gösterilir'
    Assert-True ($text -match 'if \(-not \$script:RunFailed\) \{ try \{ Confirm-BootOk \}') 'normal kapanışta açılış sayacı sıfırlanır'
    # Get-AppxPackage -AllUsers yalnızca Get-AppxSafe içinde
    $appx = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Get-AppxPackage' }, $true))
    Assert-True ($appx.Count -ge 2) 'Get-AppxPackage çağrıları bulundu'
    $outside = 0
    foreach ($c in $appx) {
        $allUsers = @($c.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] -and $_.ParameterName -eq 'AllUsers' }).Count -gt 0
        if (-not $allUsers) { continue }
        $p = $c.Parent
        while ($null -ne $p -and $p -isnot [System.Management.Automation.Language.FunctionDefinitionAst]) { $p = $p.Parent }
        if ($null -eq $p -or @('Get-AppxSafe', 'Get-LiveAppxState') -notcontains $p.Name) { $outside++ }
    }
    Assert-Eq $outside 0 'Get-AppxPackage -AllUsers yalnızca Get-AppxSafe ve bağımsız denetim okuması içinde çağrılır (yönetici değilken sonlandırıcı hata verir; ikisi de try içinde)'
    # arayüz öğeleri
    Assert-True ($text -match 'x:Name="RailHost"' -and $text -match 'x:Name="RailScroll"') 'sol menü ölçüm öğeleri tanımlı'
    # dış dünyayı açan yardımcılar duman kipinde atlanır
    foreach ($fnn in @('Open-Path', 'Open-Url', 'Open-Folder')) {
        $f = @($fns | Where-Object { $_.Name -eq $fnn })[0]
        $first = $f.Body.EndBlock.Statements[0].Extent.Text
        Assert-True ($first -like '*SmokeMode*') ($fnn + ': ilk satır duman kipi korumasıdır')
    }
    # konsol koruması
    Assert-True ($text -match 'function Initialize-ConsoleGuard' -and $text -match 'function Restore-ConsoleGuard') 'konsol koruması işlevleri tanımlı'
    Assert-True ($text -match 'if \(-not \$Cli\) \{ Initialize-ConsoleGuard \}') 'konsol koruması CLI dışında açılır'
    Assert-Eq ([regex]::Matches($text, 'try \{ Restore-ConsoleGuard \} catch \{ \}')).Count 3 'konsol kipi üç çıkış yolunda geri yüklenir (normal çıkış, -OzTest, açık olan ikinci kopya)'
    $iGuard = $text.IndexOf('if (-not $Cli) { Initialize-ConsoleGuard }')
    $iSplash = $text.IndexOf('if (-not $Cli) { Start-Splash }')
    $iWpf = $text.IndexOf('Add-Type -AssemblyName PresentationFramework, PresentationCore')
    Assert-True ($iGuard -gt 0 -and $iSplash -gt $iGuard -and $iWpf -gt $iSplash) 'konsol koruması açılış ekranından, açılış ekranı arayüz kitaplıklarından önce kurulur'
    Assert-True ($text.IndexOf('# Sabit bant (konsolda gorunur)') -lt 0) 'eski düz bant kaldırıldı (yerine açılış ekranı: t_splash.ps1)'
    $iRest = $text.LastIndexOf('try { Restore-ConsoleGuard } catch { }')
    $iThanks = $text.LastIndexOf("Write-Host ''")
    Assert-True ($iRest -gt 0 -and $iThanks -gt $iRest) 'son satır yazılmadan önce konsol kipi geri yüklenir'
    # kayıt defteri yazma yolu: önce güvenlik kapısı, sonra okuma, korumalı değer işleme
    $ro = @($fns | Where-Object { $_.Name -eq 'Invoke-RegOp' })[0].Extent.Text
    Assert-True ($ro.IndexOf('Test-RegWriteBlocked') -ge 0 -and $ro.IndexOf('Test-RegWriteBlocked') -lt $ro.IndexOf('Get-RegInfo')) 'Invoke-RegOp: güvenlik kapısı ilk kontrol'
    Assert-Eq ([regex]::Matches($ro, 'Test-AccessDeniedEx')).Count 2 'Invoke-RegOp: yazma ve silme yolunda erişim reddi işlenir'
    Assert-Eq ([regex]::Matches($ro, 'Remove-LastJournalItem')).Count 2 'Invoke-RegOp: reddedilen değişiklik günlükten çıkarılır'
    Assert-Eq ([regex]::Matches($ro, 'Test-RegDenied \$label')).Count 2 'Invoke-RegOp: önizleme korumalı değeri atlar'
    # ayar durumları ve doğrulama
    Assert-True ($text -match '\$pv = Get-TweakPending \$c\s+if \(\$pv -eq 0 -and \(Test-TweakBlocked \$c\)\) \{ \$pv = -3 \}') 'ayar durumları: korumalı ayar -3 olur'
    Assert-True ($text -match 'if \(\$p -eq 0 -and \(Test-TweakBlocked \$c\)\) \{') 'plan sonrası doğrulama: korumalı ayar "uygulanmış" kaydedilmez'
    Assert-True ($text -match "'Games', 'RegDenied'(, 'Board')?\)") 'RegDenied ayar listesi dizi olarak okunur'
    # temizlik taramasında erişilemeyen klasör hata akışına yazılmaz
    Assert-True ($text -match 'Test-Path -LiteralPath \$Root -ErrorAction SilentlyContinue') 'temizlik taraması erişim hatalarını sessize alır'
    # hata akışı kayıtları ayrıntılı
    Assert-True ($text -match 'FullyQualifiedErrorId' -and $text -match 'HATA-AKISI: \.\.\. toplam') 'HATA-AKISI kayıtları kimlik, kategori ve komut satırı yazar; en çok 8'
    # ASCII + CRLF (Windows PowerShell 5.1 BOM'suz dosyayı yerel kod sayfasıyla okur)
    $bytesAll = [System.IO.File]::ReadAllBytes($env:MM_BUILD)
    $nonAscii = 0; $lonelyLf = 0
    for ($i = 0; $i -lt $bytesAll.Length; $i++) {
        if ($bytesAll[$i] -ge 128) { $nonAscii++ }
        if ($bytesAll[$i] -eq 10 -and ($i -eq 0 -or $bytesAll[$i - 1] -ne 13)) { $lonelyLf++ }
    }
    Assert-Eq $nonAscii 0 'Multimizer.ps1 yalnızca ASCII'
    Assert-Eq $lonelyLf 0 'Multimizer.ps1 satır sonları CRLF'
    # Tani.ps1: konsolu geri getirir
    $tani = [System.IO.File]::ReadAllText((Join-Path $script:TestDir 'Tani.ps1'))
    Assert-True ($tani -match 'function Show-ThisConsole' -and $tani -match 'if \(-not \$shown\) \{\s+Show-ThisConsole') 'Tani.ps1 raporu göstermeden önce konsolu geri getirir'

    # Gerçek cihazda bulundu: duman testi gerçek ayar dosyasının kopyasıyla koşar; kopyada önceki bir çökmeden kalma kalıcı "güvenli çizim"
    # varsa saydamlık hiç uygulanmaz ve Mica / Akrilik denetimleri bir şey ölçmez. Kopya varsayılan olarak normal çizime çevrilir.
    $tn = $text -replace "`r`n", "`n"
    $dStart = $tn.IndexOf("    try {`n        `$realSt = Join-Path")
    $dTail = "`n    } catch { }"
    $dEnd = -1
    if ($dStart -ge 0) { $dEnd = $tn.IndexOf($dTail, $dStart) }
    Assert-True ($dStart -ge 0 -and $dEnd -gt $dStart) 'duman: ayar kopyası bloğu bulunur'
    if ($dStart -ge 0 -and $dEnd -gt $dStart) {
        $blk = $tn.Substring($dStart, $dEnd - $dStart + $dTail.Length)
        $pdRoot = Join-Path $root 'duman-pd'
        New-Item -ItemType Directory -Path (Join-Path $pdRoot 'Multimizer') -Force | Out-Null
        $realFile = Join-Path (Join-Path $pdRoot 'Multimizer') 'ayarlar.json'
        $sample = "{`n    `"Theme`":  `"Holo`",`n    `"SafeRender`":  true,`n    `"CrashStreak`":  3,`n    `"Backdrop`":  `"Akrilik`"`n}"
        [System.IO.File]::WriteAllText($realFile, $sample, (New-Object System.Text.UTF8Encoding($false)))
        $saveEnv = @{ PD = $env:ProgramData; G = $env:MM_DUMAN_GUVENLI }
        try {
            $env:ProgramData = $pdRoot
            $script:AppName = 'Multimizer'
            foreach ($mode in @('', '1')) {
                $env:MM_DUMAN_GUVENLI = $mode
                $script:SettingsFile = Join-Path $root ('duman-ayar-' + $(if ($mode -eq '') { 'normal' } else { 'guvenli' }) + '.json')
                $Guvenli = [switch]$false
                . ([scriptblock]::Create($blk))
                $jj = ConvertFrom-Json -InputObject ([System.IO.File]::ReadAllText($script:SettingsFile))
                $tag = $(if ($mode -eq '') { 'varsayılan' } else { 'MM_DUMAN_GUVENLI=1' })
                if ($mode -eq '') {
                    Assert-Eq ([string]$jj.SafeRender) 'False' ('duman ayar kopyası (' + $tag + '): kalıcı güvenli çizim kapatılır')
                    Assert-True (-not $Guvenli.IsPresent) ('duman ayar kopyası (' + $tag + '): güvenli kip istenmez')
                } else {
                    Assert-Eq ([string]$jj.SafeRender) 'True' ('duman ayar kopyası (' + $tag + '): güvenli çizim açık kalır')
                    Assert-True ($Guvenli.IsPresent) ('duman ayar kopyası (' + $tag + '): güvenli kip istenir')
                }
                Assert-Eq ([int]$jj.CrashStreak) 0 ('duman ayar kopyası (' + $tag + '): art arda çökme sayacı sıfırlanır (kopya otomatik güvenli kipe geçmez)')
                Assert-Eq ([string]$jj.Theme + '|' + [string]$jj.Backdrop) 'Holo|Akrilik' ('duman ayar kopyası (' + $tag + '): diğer ayarlar korunur')
                $rawCopy = [System.IO.File]::ReadAllBytes($script:SettingsFile)
                Assert-True (-not ($rawCopy.Length -ge 3 -and $rawCopy[0] -eq 0xEF -and $rawCopy[1] -eq 0xBB -and $rawCopy[2] -eq 0xBF)) ('duman ayar kopyası (' + $tag + '): BOM eklenmez (uygulamanın kendi yazımıyla aynı biçim)')
            }
            Assert-Eq ([System.IO.File]::ReadAllText($realFile)) $sample 'duman ayar kopyası: gerçek ayar dosyasına dokunulmaz'
        } finally {
            $env:ProgramData = $saveEnv.PD
            $env:MM_DUMAN_GUVENLI = $saveEnv.G
        }
    }
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
Show-Result
