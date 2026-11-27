. "$PSScriptRoot/lib.ps1"
# Gerçek makinede görülen hatalar (mods\147_realfix_core.ps1, 148_realfix_state.ps1, patches\p64_gercek_duzeltmeler.py):
# yeniden başlatma komutu, bilgisayar kapanırken biten oturum, güvenli kipten çıkış, güç kipi (Modern Bekleme), görsel efektlerin anında uygulanması,
# bekleyen dosya işlemleri, sapma denetimi, Defender dışlama bulgusu. Yerel işlevler (WH.Sys) sahte bir sınıfla değiştirilir; sistem değişmez.
Import-Fn 'Get-RestartArgLine', 'Start-SystemRestart', 'Test-PendingRenameReal', 'Test-EndedBySystem', 'Test-SafeModeRelease', 'Update-SafeModeState', 'Step-CleanStreak',
    'Get-PwModeKeyFor', 'Get-PwModeKeyOfGuid', 'Get-PwModeInfo', 'Test-PwUseMode', 'Test-PwModernStandby', 'Invoke-PowerModeOp', 'Undo-PowerMode', 'Initialize-SysNative',
    'Get-MaskBit', 'Test-LiveRefreshNeeded', 'Invoke-LiveRefresh', 'Get-GpuTemp', 'Get-GpuOffText', 'Get-TempSubText', 'Get-ExclTitle', 'Get-ExclDetail', 'Get-ExclAction',
    'Get-PendingReboot', 'Get-TweakPending', 'Get-DriftedIds'
Import-Var 'PwModes', 'LiveMaskBits', 'LiveRegRx', 'PwKnown', 'GuidRx', 'FuncStateful', 'AuditLogonSubs'
$src = [System.IO.File]::ReadAllText($script:TestPath)

# ======================= 1) yeniden başlatma =======================
Assert-Eq (Get-RestartArgLine $false 30) '/r /t 30 /c "Multimizer: yeniden baslatma"' 'yeniden başlatma: açıklama tırnak içinde, tek satır'
Assert-Eq (Get-RestartArgLine $true 30) '/r /fw /t 30 /c "Multimizer: yeniden baslatma"' 'UEFI yeniden başlatma: /fw eklenir'
Assert-True (-not $src.Contains("'/c', 'Multimizer: yeniden baslatma'")) 'eski (tırnaksız, bozuk) shutdown çağrısı kaynakta kalmadı'
Assert-True (-not $src.Contains("'/c', 'Multimizer: UEFI ayarlarina yeniden baslatma'")) 'eski UEFI shutdown çağrısı kaynakta kalmadı'
Assert-Eq ([regex]::Matches($src, '\[void\]\(Start-SystemRestart \$false 30\)').Count) 1 'Request-Reboot doğrulamalı işlevi çağırır'
Assert-Eq ([regex]::Matches($src, '\[void\]\(Start-SystemRestart \$true 30\)').Count) 1 'UEFI yeniden başlatma doğrulamalı işlevi çağırır'
$script:SpArgs = $null; $script:SpCode = 0
function Start-Process { param($FilePath, $ArgumentList, $WindowStyle, [switch]$Wait, [switch]$PassThru, $ErrorAction) $script:SpArgs = @{ File = $FilePath; Args = $ArgumentList; Wait = [bool]$Wait }; return @{ ExitCode = $script:SpCode } }
$env:WINDIR = '/tmp/w'
Assert-True (Start-SystemRestart $false 30) 'çıkış kodu 0: başarılı'
Assert-True ([string]$script:SpArgs.File -match 'shutdown\.exe$' -and $script:SpArgs.Wait) 'shutdown.exe beklenerek çalıştırılır'
Assert-True ($script:SpArgs.Args -is [string]) 'bağımsız değişkenler tek dize olarak verilir (PowerShell boşluklu öğeyi tırnaklamaz)'
$script:SpCode = 1190; $threw = $false
try { [void](Start-SystemRestart $false 30) } catch { $threw = $true }
Assert-True $threw 'çıkış kodu 0 değilse hata fırlatılır (sessizce "yapıldı" denmez)'

# ======================= 2) bekleyen dosya işlemleri =======================
Assert-True (-not (Test-PendingRenameReal @('*1\??\C:\Windows\System32\gamingservicesproxy_17.dll.0', ''))) 'yalnızca açılışta silinecek dosya: yeniden başlatma gerekmez'
Assert-True (-not (Test-PendingRenameReal @('\??\C:\a.tmp'))) 'tek öğeli (hedefsiz) kayıt sayılmaz'
Assert-True (Test-PendingRenameReal @('\??\C:\a.new', '!\??\C:\a.dll')) 'dosya değiştiren çift: yeniden başlatma gerekir'
Assert-True (Test-PendingRenameReal @('\??\C:\x.tmp', '', '\??\C:\b.new', '\??\C:\b.sys')) 'karışık listede bir değiştirme varsa sayılır'
Assert-True (-not (Test-PendingRenameReal @())) 'boş liste'
Assert-True (-not (Test-PendingRenameReal $null)) 'değer yok'
$script:RegSub = @{}; $script:Pfro = @('\??\C:\t.tmp', '')
function Get-RegSubKeyNames([string]$p) { return @($script:RegSub[$p]) }
function Get-RegValue([string]$p, [string]$n, $d) { if ($n -eq 'PendingFileRenameOperations') { return $script:Pfro }; return $d }
Assert-Eq (Get-PendingReboot).Count 0 'Get-PendingReboot: silme kayıtları bulgu üretmez'
$script:Pfro = @('\??\C:\b.new', '\??\C:\b.sys')
Assert-Eq (Get-PendingReboot).Count 1 'Get-PendingReboot: dosya değiştirme bulgu üretir'

# ======================= 3) oturum: bilgisayar kapanırken sona erme, güvenli kip =======================
$boot = [DateTime]'2026-11-13 09:00:00'
Assert-True (Test-EndedBySystem ([DateTime]'2026-11-12 02:25:30') $boot) 'son iz açılıştan önce: oturum bilgisayar kapanırken bitmiş'
Assert-True (-not (Test-EndedBySystem ([DateTime]'2026-11-13 10:00:00') $boot)) 'son iz açılıştan sonra: gerçek beklenmedik kapanma'
Assert-True (-not (Test-EndedBySystem ([DateTime]'2026-11-12 02:25:30') ([DateTime]::MinValue))) 'açılış zamanı okunamadıysa çökme sayılır (temkinli)'
Assert-True (Test-SafeModeRelease $true '' 0 $false 0) 'eski sürümden kalan otomatik güvenli kip bu sürüme geçişte bir kez kapatılır'
Assert-True (-not (Test-SafeModeRelease $true 'user' 9 $false 0)) 'kullanıcının açtığı güvenli kip kendiliğinden kapanmaz'
Assert-True (-not (Test-SafeModeRelease $true 'auto' 2 $false 1)) 'iki sorunsuz oturum yetmez'
Assert-True (Test-SafeModeRelease $true 'auto' 3 $false 1) 'üç sorunsuz oturumdan sonra kapanır'
Assert-True (-not (Test-SafeModeRelease $true 'auto' 5 $true 1)) 'önceki oturum çöktüyse kapanmaz'
Assert-True (-not (Test-SafeModeRelease $false 'auto' 5 $false 1)) 'güvenli kip zaten kapalı'
$script:Saved = @{}
function Set-CoreSettingKeys($Keys) { foreach ($k in @($Keys.Keys)) { $script:Saved[[string]$k] = $Keys[$k]; $script:Settings[[string]$k] = $Keys[$k] } }
$script:Settings = @{ SafeRender = $true; SafeRenderWhy = ''; CleanStreak = 0; FixLevel = 0 }
$script:SafeRenderAuto = $false; $script:PrevCrashed = $false; $script:SafeReleased = $false
Assert-True (-not (Update-SafeModeState $true)) 'geçiş: kalıcı güvenli kip kapatıldı'
Assert-True ($script:Saved.SafeRender -eq $false -and [int]$script:Saved.FixLevel -eq 1 -and $script:SafeReleased) 'geçiş kaydedildi (SafeRender kapalı, FixLevel 1)'
$script:Saved = @{}; $script:Settings = @{ SafeRender = $true; SafeRenderWhy = 'user'; CleanStreak = 7; FixLevel = 1 }
Assert-True (Update-SafeModeState $true) 'elle açılmış güvenli kip korunur'
Assert-Eq $script:Saved.Count 0 'elle açılmış kipte ayar yazılmaz'
$script:Saved = @{}; $script:Settings = @{ SafeRender = $true; SafeRenderWhy = 'auto'; CleanStreak = 2; FixLevel = 1 }; $script:PrevCrashed = $true
Assert-True (Update-SafeModeState $true) 'çökme sonrası güvenli kip sürer'
Assert-Eq ([int]$script:Saved.CleanStreak) 0 'çökme sorunsuz oturum sayacını sıfırlar'
$script:PrevCrashed = $false; $script:Saved = @{}; $script:Settings = @{ SafeRender = $true; CleanStreak = 1 }
Step-CleanStreak
Assert-Eq ([int]$script:Saved.CleanStreak) 2 'düzgün kapanış sayacı artırır'
$script:Saved = @{}; $script:Settings = @{ SafeRender = $false; CleanStreak = 1 }
Step-CleanStreak
Assert-Eq $script:Saved.Count 0 'güvenli kip kapalıyken sayaç tutulmaz'
Assert-True ($src.Contains('-and (Test-SessionEndedBySystem)) { $script:PrevBySystem = $true; $prev = $null }')) 'Start-SessionTrace: bilgisayar kapanırken biten oturum çökme sayılmaz'
Assert-True ($src.Contains('    $persist = Update-SafeModeState $persist')) 'güvenli kip kararı çıkış kuralından geçer'
Assert-True ($src.Contains('        if (($tick % 5) -eq 3) {')) 'sıcaklık güvenli kipte de okunur'
Assert-True (-not $src.Contains('if ($sync.SafeMon -eq $true) { $last.Temp = -1.0 }')) 'güvenli kip sıcaklığı sıfırlamaz'
Assert-True ($src.Contains('$m.GpuTemp = [double]$last.GpuTemp')) 'izleme verisinde ekran kartı sıcaklığı var'

# ======================= 4) güç kipi =======================
Add-Type -TypeDefinition @'
using System;
namespace WH { public static class Sys {
  public static bool Modern = true; public static string Mode = "00000000-0000-0000-0000-000000000000"; public static string Ac = ""; public static string Dc = "";
  public static uint Rc = 0; public static bool Stick = true; public static double Temp = 48.0; public static int SpiCalls = 0; public static int Casts = 0; public static int Anim = -1;
  public static double GpuTemp() { return Temp; }
  public static bool ModernStandby() { return Modern; }
  public static string GetMode() { return Mode; }
  public static string GetUserMode(bool dc) { return dc ? Dc : Ac; }
  public static uint SetMode(string ac, string dc) { if (Rc != 0) return Rc; Ac = ac; Dc = dc; if (Stick) Mode = ac; return 0; }
  public static bool SetSpiBool(uint a, bool on) { SpiCalls++; return true; }
  public static bool SetSpiUi(uint a, uint v) { SpiCalls++; return true; }
  public static bool SetMinAnimate(bool on) { Anim = on ? 1 : 0; SpiCalls++; return true; }
  public static void Broadcast(string area) { Casts++; }
} }
'@
$script:SysNativeOk = $null
Assert-True (Initialize-SysNative) 'yerel sınıf bulunduğunda yeniden derlenmez'
Assert-Eq (Get-GpuTemp) 48.0 'ekran kartı sıcaklığı okunur'
[WH.Sys]::Temp = -1.0
Assert-Eq (Get-GpuTemp) (-1.0) 'sıcaklık yoksa -1'
Assert-Eq (Get-PwModeKeyFor 'High') 'Perf' 'Yüksek performans -> En iyi performans kipi'
Assert-Eq (Get-PwModeKeyFor 'Ultimate') 'Perf' 'Nihai performans -> En iyi performans kipi'
Assert-Eq (Get-PwModeKeyFor 'Best') 'Perf' 'oyun kipi -> En iyi performans kipi'
Assert-Eq (Get-PwModeKeyFor 'Balanced') 'Balanced' 'Dengeli -> Dengeli kip'
Assert-Eq (Get-PwModeKeyFor 'Saver') 'Saver' 'Güç tasarrufu -> En iyi güç verimliliği'
Assert-Eq (Get-PwModeKeyFor 'a1b2c3d4-0000-0000-0000-000000000000') '' 'özel plan GUID kip değildir'
Assert-Eq (Get-PwModeKeyOfGuid 'DED574B5-45A0-4F42-8737-46345C09C238') 'Perf' 'kip GUID çözümü büyük/küçük harfe duyarsız'
Assert-True (Test-PwUseMode 'High') 'Modern Bekleme: Yüksek performans kiple uygulanır'
Assert-True (-not (Test-PwUseMode 'a1b2c3d4-0000-0000-0000-000000000000')) 'özel plan her zaman plan olarak uygulanır'
[WH.Sys]::Modern = $false
Assert-True (-not (Test-PwUseMode 'High')) 'Modern Bekleme yoksa klasik güç planı kullanılır'
[WH.Sys]::Modern = $true
$mi = Get-PwModeInfo
Assert-True ($mi.Ok -and $mi.Key -eq 'Balanced' -and $mi.Modern) 'kip bilgisi: Dengeli, Modern Bekleme'

$script:Log = New-Object System.Collections.ArrayList; $script:Jr = New-Object System.Collections.ArrayList; $script:Preview = $false
function Add-Skip([string]$m) { [void]$script:Log.Add('SKIP ' + $m) }
function Add-Plan([string]$m) { [void]$script:Log.Add('PLAN ' + $m) }
function Add-Done([string]$m) { [void]$script:Log.Add('OK ' + $m) }
function Add-Journal($i) { [void]$script:Jr.Add($i) }
function Write-WhLog([string]$m, [string]$l) { [void]$script:Log.Add($l + ' ' + $m) }
$script:ActiveGuid = [string]$script:PwKnown.Balanced.Guid
function Get-PwActive { return @{ Guid = $script:ActiveGuid; Name = 'Dengeli' } }
$script:PcfgCalls = New-Object System.Collections.ArrayList
function powercfg.exe { [void]$script:PcfgCalls.Add(($args -join ' ')); $global:LASTEXITCODE = 0; if ($args[0] -eq '/setactive') { $script:ActiveGuid = [string]$args[1] } }

$script:Preview = $true
Invoke-PowerModeOp 'High'
Assert-True (@($script:Log | Where-Object { $_ -like 'PLAN Güç kipi: Dengeli*En iyi performans' }).Count -eq 1) 'önizleme: kip değişimi gösterilir'
Assert-Eq $script:Jr.Count 0 'önizleme günlüğe yazmaz'
Assert-Eq ([string][WH.Sys]::Mode) '00000000-0000-0000-0000-000000000000' 'önizleme sistemi değiştirmez'
$script:Preview = $false; $script:Log.Clear()
[WH.Sys]::Ac = '00000000-0000-0000-0000-000000000000'; [WH.Sys]::Dc = '961cc777-2547-4f9d-8174-7d86181b8a7a'
Invoke-PowerModeOp 'High'
Assert-Eq ([string][WH.Sys]::Mode) 'ded574b5-45a0-4f42-8737-46345c09c238' 'uygula: kip En iyi performans'
Assert-True (@($script:Log | Where-Object { $_ -like 'OK Güç kipi: En iyi performans (doğrulandı)' }).Count -eq 1) 'uygula: doğrulama sonrası "yapıldı"'
Assert-Eq $script:Jr.Count 1 'uygula: bir günlük kaydı'
Assert-True ([string]$script:Jr[0].T -eq 'PowerMode' -and [string]$script:Jr[0].Dc -eq '961cc777-2547-4f9d-8174-7d86181b8a7a') 'günlük: önceki fiş ve pil kipi saklanır'
Assert-Eq $script:PcfgCalls.Count 0 'Dengeli plan etkinken powercfg çağrılmaz'
$script:Log.Clear()
Invoke-PowerModeOp 'Ultimate'
Assert-True (@($script:Log | Where-Object { $_ -like 'SKIP Güç kipi zaten*' }).Count -eq 1) 'aynı kip: atlanır'
Undo-PowerMode $script:Jr[0]
Assert-True ([string][WH.Sys]::Ac -eq '00000000-0000-0000-0000-000000000000' -and [string][WH.Sys]::Dc -eq '961cc777-2547-4f9d-8174-7d86181b8a7a') 'geri al: fiş ve pil kipi eski değerine döner'
# Windows kipi değiştirmezse
[WH.Sys]::Stick = $false; [WH.Sys]::Mode = '00000000-0000-0000-0000-000000000000'; $threw = ''
try { Invoke-PowerModeOp 'High' } catch { $threw = $_.Exception.Message }
Assert-True ($threw -like 'Güç kipi doğrulanamadı*') 'kip yerine oturmadıysa hata (sahte başarı yok)'
[WH.Sys]::Stick = $true; [WH.Sys]::Rc = 5; $threw = ''
try { Invoke-PowerModeOp 'High' } catch { $threw = $_.Exception.Message }
Assert-True ($threw -like 'Windows güç kipini değiştirmedi (kod 5)*') 'işlev hata kodu döndürürse hata'
[WH.Sys]::Rc = 0
# etkin plan Dengeli değilse önce Dengeli'ye geçilir
$script:ActiveGuid = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'; $script:Jr.Clear(); $script:PcfgCalls.Clear()
Invoke-PowerModeOp 'Saver'
Assert-True ($script:PcfgCalls.Count -eq 1 -and [string]$script:PcfgCalls[0] -like '/setactive 381b4222*') 'kip yalnızca Dengeli planında geçerli: önce Dengeli etkinleştirilir'
Assert-True ($script:Jr.Count -eq 2 -and [string]$script:Jr[0].T -eq 'Power' -and [string]$script:Jr[1].T -eq 'PowerMode') 'günlük: önce plan, sonra kip'
Assert-Eq ([string][WH.Sys]::Mode) '961cc777-2547-4f9d-8174-7d86181b8a7a' 'kip: En iyi güç verimliliği'
Assert-True ($src.Contains('    if (Test-PwUseMode $key) { Invoke-PowerModeOp $key; return }')) 'Invoke-PowerSetOp güç kipine yönlenir'
Assert-True ($src.Contains("        'PowerMode' { Undo-PowerMode `$it }")) 'geri alma PowerMode kaydını tanır'

# ======================= 5) görsel efektlerin anında uygulanması =======================
[byte[]]$mask = 0x90, 0x12, 0x03, 0x80, 0x10, 0, 0, 0
Assert-Eq (Get-MaskBit $mask 1) $false 'maske: menü animasyonu kapalı'
Assert-Eq (Get-MaskBit $mask 4) $true 'maske: bit 4 açık'
Assert-Eq (Get-MaskBit $mask 33) $false 'maske: istemci alanı animasyonu kapalı'
Assert-Eq (Get-MaskBit $mask 36) $true 'maske: bit 36 açık'
Assert-True ($null -eq (Get-MaskBit $mask 80)) 'maske dışındaki bit: yok'
Assert-True (Test-LiveRefreshNeeded @(@{ T = 'Reg'; Path = 'HKCU\Control Panel\Desktop'; Name = 'UserPreferencesMask' })) 'masaüstü ayarı: anında uygulama gerekir'
Assert-True (Test-LiveRefreshNeeded @(@{ T = 'Reg'; Path = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'; Name = 'EnableTransparency' })) 'saydamlık: anında uygulama gerekir'
Assert-True (-not (Test-LiveRefreshNeeded @(@{ T = 'Reg'; Path = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name = 'AllowTelemetry' }, @{ T = 'Svc'; Name = 'DiagTrack' }))) 'ilgisiz ayar: gerekmez'
function Get-RegValue([string]$p, [string]$n, $d) {
    if ($n -eq 'UserPreferencesMask') { return , $mask }
    if ($n -eq 'MinAnimate') { return '0' } if ($n -eq 'DragFullWindows') { return '0' } if ($n -eq 'MenuShowDelay') { return '200' }
    return $d
}
[WH.Sys]::SpiCalls = 0; [WH.Sys]::Casts = 0
$n = Invoke-LiveRefresh @(@{ T = 'Reg'; Path = 'HKCU\Control Panel\Desktop'; Name = 'UserPreferencesMask' })
Assert-Eq $n ($script:LiveMaskBits.Count + 3) 'maske bitleri, MinAnimate, DragFullWindows ve MenuShowDelay uygulanır'
Assert-Eq ([int][WH.Sys]::Anim) 0 'pencere küçültme animasyonu kapatıldı'
Assert-Eq ([int][WH.Sys]::Casts) 4 'ayar değişikliği yayını yapıldı'
[WH.Sys]::SpiCalls = 0
Assert-Eq (Invoke-LiveRefresh @(@{ T = 'Svc'; Name = 'x' })) 0 'görsel ayar yoksa hiçbir çağrı yapılmaz'
Assert-Eq ([int][WH.Sys]::SpiCalls) 0 'gereksiz SystemParametersInfo çağrısı yok'
Assert-True ($src.Contains('try { [void](Invoke-LiveRefresh @($script:JItems)) } catch { }; Close-Journal }')) 'plan bitince görsel ayarlar oturuma uygulanır'
Assert-True ($src.Contains('    try { [void](Invoke-LiveRefresh $items) } catch { }')) 'geri almada da uygulanır'

# ======================= 6) arayüz metinleri =======================
function Tr($t) { return $t }
$sync = @{ SafeMon = $true; NoGpu = $false }
Assert-Eq (Get-GpuOffText) 'güvenli kipte kapalı' 'GPU: güvenli kip nedeni söylenir'
$sync.SafeMon = $false; $sync.NoGpu = $true
Assert-Eq (Get-GpuOffText) 'ayarlardan kapalı' 'GPU: ayardan kapalı'
$sync.NoGpu = $false; $sync.MonWarmGpu = $false
Assert-Eq (Get-GpuOffText) 'ölçülemedi' 'GPU: gerçekten ölçülemedi'
Assert-Eq (Get-TempSubText @{ Temp = 60.0; GpuTemp = 48.0 } 'sistem') ('sistem ' + [char]0x00B7 + ' ekran kartı 48' + [char]0x00B0) 'sıcaklık alt yazısında ekran kartı'
Assert-Eq (Get-TempSubText @{ Temp = 60.0; GpuTemp = -1.0 } 'sistem') 'sistem' 'ekran kartı sıcaklığı yoksa eklenmez'
Assert-Eq (Get-TempSubText @{ Temp = 60.0 } 'sistem') 'sistem' 'eski izleme verisiyle uyumlu'

# ======================= 7) Defender dışlamaları =======================
$pref = @{ ExclusionPath = @('C:\Proje', 'D:\Oyun'); ExclusionProcess = @('a.exe'); ExclusionExtension = @('.iso', 'bak', 'x', 'y') }
Assert-Eq (Get-ExclTitle 7) 'Defender dışlama listesi: 7 öğe' 'başlık'
$d = Get-ExclDetail $pref
Assert-True ($d.StartsWith('Taranmayanlar: C:\Proje; D:\Oyun; a.exe; *.iso; *.bak (+2).')) 'ayrıntı: ilk beş öğe ve kalan sayısı'
Assert-True ($d.Contains('Multimizer bu listeyi değiştirmez')) 'ayrıntı: uygulama Defender ayarına dokunmaz'
$a = Get-ExclAction
Assert-True ($a.Kind -eq 'Url' -and $a.Url -eq 'windowsdefender://exclusions' -and $a.Label -ne '') 'eylem: dışlamalar sayfası açılır'
Assert-True ($src.Contains("Add-Finding 'av-excl' 'sec' 'info' (Get-ExclTitle `$cnt) (Get-ExclDetail `$pref) (Get-ExclAction) }")) 'bulguda eylem var'

# ======================= 8) sapma: görevler sayılmaz =======================
$script:Changes = 0; $script:Skipped = 0; $script:Errors = 0; $script:Silent = $false
function Invoke-Op($op) { if ([bool]$op.Pending) { $script:Changes++ } }
$item = @{ Ops = @(@{ T = 'Reg'; Pending = $false }, @{ T = 'Task'; Pending = $true }) }
Assert-Eq (Get-TweakPending $item) 1 'durum denetimi: yeniden açılmış görev eksik sayılır'
Assert-Eq (Get-TweakPending $item $true) 0 'sapma denetimi: yalnızca görev geri döndüyse sapma yok'
$item2 = @{ Ops = @(@{ T = 'Reg'; Pending = $true }, @{ T = 'Task'; Pending = $true }) }
Assert-Eq (Get-TweakPending $item2 $true) 1 'sapma denetimi: kayıt değeri geri döndüyse sapma var'
Assert-Eq (Get-TweakPending @{ Ops = @(@{ T = 'Task'; Pending = $true }) } $true) (-1) 'yalnızca görevden oluşan ayar sapma denetimine girmez'
Assert-True ($src.Contains('if ((Get-TweakPending $c $true) -gt 0) { [void]$out.Add([string]$id) }')) 'Get-DriftedIds görevleri saymaz'

# ======================= 8b) ölçüm kapsamı: Defender, olay günlüğü, bileşen, durumu okunabilen işlevler =======================
Assert-Eq (Get-TweakPending @{ Ops = @(@{ T = 'Mp'; Pending = $true }) }) 1 'Defender tercihi ölçülür'
Assert-Eq (Get-TweakPending @{ Ops = @(@{ T = 'EvtLog'; Pending = $false }) }) 0 'olay günlüğü boyutu ölçülür (uygun)'
Assert-Eq (Get-TweakPending @{ Ops = @(@{ T = 'Cap'; Pending = $true }) }) 1 'Windows bileşeni ölçülür'
Assert-Eq (Get-TweakPending @{ Ops = @(@{ T = 'Func'; Name = 'PowerPlan'; Pending = $true }) }) 1 'güç planı işlevi ölçülür'
Assert-Eq (Get-TweakPending @{ Ops = @(@{ T = 'Func'; Name = 'AuditLogon'; Pending = $false }) }) 0 'denetim ilkesi işlevi ölçülür'
Assert-Eq (Get-TweakPending @{ Ops = @(@{ T = 'Func'; Name = 'CleanTemp'; Pending = $true }) }) (-1) 'tek yönlü temizlik işlevi ölçülmez'
Assert-Eq (Get-TweakPending @{ Ops = @(@{ T = 'Feature'; Pending = $false }, @{ T = 'DxGlobal'; Pending = $true }, @{ T = 'NetLatency'; Pending = $false }) }) 1 'Windows özelliği, DirectX ve ağ gecikmesi ayarları ölçülür'
function Invoke-Op($op) { if ([bool]$op.Unread) { $script:OpUnreadable = $true }; if ([bool]$op.Pending) { $script:Changes++ } }
Assert-Eq (Get-TweakPending @{ Ops = @(@{ T = 'Cap'; Unread = $true }) }) (-1) 'durumu okunamayan (yetki) işlem "uygulanmış" sayılmaz, ölçülemez döner'
Assert-Eq (Get-TweakPending @{ Ops = @(@{ T = 'Reg'; Pending = $false }) }) 0 'okunamama bayrağı her ölçümde sıfırlanır'
Assert-True ($src.Contains("if (`$script:CapReadFailed) { `$script:OpUnreadable = `$true; Add-Skip")) 'bileşen listesi okunamazsa işlem ölçülemez işaretlenir'
Assert-True ($src.Contains("if (`$null -eq `$f -and `$readErr -ne '') { `$script:OpUnreadable = `$true;")) 'Windows özelliği okunamazsa ölçülemez işaretlenir'
Assert-Eq (Get-TweakPending @{ Ops = @(@{ T = 'Func'; Name = 'CleanTemp'; Pending = $true }, @{ T = 'Reg'; Pending = $false }) }) 0 'karışık ayarda yalnızca ölçülebilen işlemler sayılır'
$eksik = @(@('PowerPlan', 'HibernateOff', 'GuestOff', 'NetBiosOff', 'LockoutPolicy', 'AuditLogon') | Where-Object { $script:FuncStateful -notcontains $_ })
Assert-Eq $eksik.Count 0 'durumu okunabilen işlev listesi tam'
Assert-Eq @($script:AuditLogonSubs).Count 4 'denetim ilkesi dört alt kategori'
Assert-True ($src.Contains("if (Test-AuditLogonOn) { Add-Skip ('Denetim ilkesi zaten etkin")) 'denetim ilkesi mevcut durumu okur, açıksa atlar'
Assert-True ($src -notmatch 'MpPrefCache\b' -and $src -notmatch 'MpPrefAt') 'Defender tercihinde süreli önbellek yok (geri almadan sonra eski değeri gösteriyordu); toplu ölçüm partisi kullanılır'
Assert-True ($src.Contains('$cur = (Get-MpPrefCached).$name')) 'Defender okuması önbellekten'

# ======================= ilk ölçüm gelene kadar "ölçülüyor" =======================
Import-Fn 'Get-GpuOffText', 'Get-TempOffText'
$sync = @{ SafeMon = $false; NoGpu = $false }
Assert-Eq (Get-GpuOffText) ('ölçülüyor' + [char]0x2026) 'izleme başlamadan: ekran kartı "ölçülüyor"'
Assert-Eq (Get-TempOffText) ('ölçülüyor' + [char]0x2026) 'izleme başlamadan: sıcaklık "ölçülüyor"'
$sync.MonWarmGpu = $false; $sync.MonWarmTemp = $true
Assert-Eq (Get-GpuOffText) 'ölçülemedi' 'ilk ölçümden sonra değer yoksa: ölçülemedi'
Assert-Eq (Get-TempOffText) ('ölçülüyor' + [char]0x2026) 'sıcaklık 3. turda okunur; o zamana kadar bekler'
$sync.MonWarmTemp = $false
Assert-Eq (Get-TempOffText) 'sensör yok' 'ilk ölçümden sonra değer yoksa: sensör yok'
$sync.SafeMon = $true
Assert-Eq (Get-GpuOffText) 'güvenli kipte kapalı' 'güvenli kip nedeni önce gelir'
$sync.SafeMon = $false; $sync.NoGpu = $true
Assert-Eq (Get-GpuOffText) 'ayarlardan kapalı' 'ayar nedeni önce gelir'
$srcRf = [System.IO.File]::ReadAllText($script:TestPath)
Assert-True ($srcRf.Contains('$sync.MonWarmGpu = ($tick -lt 1); $sync.MonWarmTemp = ($tick -lt 3)')) 'izleme döngüsü ilk ölçüm durumunu yayımlar'
Assert-True (-not [regex]::IsMatch($srcRf, "\`$sub = \('sens' \+ \[char\]0x00F6 \+ 'r yok'\)")) 'pano kartında sabit "sensör yok" kalmadı'

Show-Result
