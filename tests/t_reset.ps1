# 10.0.0: varsayilan gorunum (beyaz + sade), eski kaydin gorunumunun bir kez tasinmasi ve "Ayarlari sifirla"
# (cekirdek, kopyalar, geri alma, arayuz akisi, komut satiri). Linux'ta WPF yok: pencere ve denetimler kucuk sahte nesnelerle taklit edilir;
# gercek islevler AST ile derlenmis betikten alinir. Dosya islemleri gecici bir klasorde yapilir.
. "$PSScriptRoot/lib.ps1"

Add-Type -ReferencedAssemblies @([psobject].Assembly.Location, 'System.Collections', 'System.Runtime', 'netstandard') -TypeDefinition @'
namespace System.Windows.Threading {
    public class DispatcherTimer {
        public System.TimeSpan Interval;
        public object TickHandler;
        public bool Running;
        public int StartCount;
        public int StopCount;
        public void Add_Tick(object h) { TickHandler = h; }
        public void Start() { Running = true; StartCount++; }
        public void Stop() { Running = false; StopCount++; }
    }
}
'@

Import-Fn 'Get-DefaultSettings', 'Get-Settings', 'Save-Settings', 'Save-JsonFile', 'Read-JsonFile', 'ConvertTo-Hashtable', 'Format-Tr', 'Get-SafeLookKeys', 'Get-LookPreset'
Import-Fn 'ConvertTo-ResetScope', 'Get-ResetKeyList', 'Get-ValueSig', 'Get-ResetResult', 'Get-SettingsBackupDir', 'Get-SettingsBackupFiles', 'Save-SettingsBackup', 'Get-ResetBackups'
Import-Fn 'Read-SettingsBackup', 'Restore-SettingsFromBackup', 'Test-GuiRunning', 'Reset-SettingsFile', 'Invoke-CliResetSettings'
Import-Fn 'New-Choice', 'Set-ComboChoices', 'Select-ComboKey', 'Get-ComboKey'
Import-Fn 'Initialize-StReset', 'Update-StReset', 'Load-StReset', 'Complete-StReset', 'Invoke-StResetRun', 'Invoke-StResetUndo', 'Init-StReset', 'Initialize-LookNotice'
Import-Var 'ResetLookKeys', 'ResetPrefKeys', 'ResetKeepKeys'
Import-Fn 'Get-UndoableJournals'

# ---------------- sahte ortam ----------------
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('mm-sifirla-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
[void](New-Item -ItemType Directory -Path $tmp -Force)
$sync = @{ DataDir = $tmp; SettingsFile = (Join-Path $tmp 'ayarlar.json') }
$script:Toasts = New-Object System.Collections.ArrayList
$script:Logs = New-Object System.Collections.ArrayList
$script:Crash = New-Object System.Collections.ArrayList
$script:Applied = New-Object System.Collections.ArrayList
$script:Confirm = $null
$script:RestartOk = $true; $script:RestartCalls = 0; $script:ExitCalls = 0; $script:Opened = ''
$script:StLoading = $false; $script:SmokeMode = $false; $script:VisOn = 'Visible'
function global:Show-Toast([string]$Text, [string]$Kind = 'info') { [void]$script:Toasts.Add($Kind + '|' + $Text) }
function global:Show-Confirm($Title, $Text, $OkText, $OnOk, [bool]$Danger = $false) { $script:Confirm = @{ Title = [string]$Title; Text = [string]$Text; OkText = [string]$OkText; OnOk = $OnOk; Danger = $Danger } }
function global:Invoke-Safe([scriptblock]$Block, [string]$Label) { & $Block }
function global:Write-WhLog([string]$Text, [string]$Level = 'INFO') { [void]$script:Logs.Add($Level + '|' + $Text) }
function global:Write-CrashLog([string]$Text) { [void]$script:Crash.Add($Text) }
function global:Restart-App { $script:RestartCalls++; return [bool]$script:RestartOk }
function global:Exit-App { $script:ExitCalls++ }
function global:Open-Folder([string]$Path) { $script:Opened = $Path }
function global:Select-HomeMode([string]$Name) { [void]$script:Applied.Add('home:' + $Name); $script:Settings.HomeMode = $Name; return $true }
function global:Apply-LookPreset([string]$Key) {
    [void]$script:Applied.Add('preset:' + $Key)
    $p = Get-LookPreset $Key
    $script:Settings.Theme = [string]$p.Theme; $script:Settings.Layout = [string]$p.Layout; $script:Settings.Zoom = [int]$p.Zoom; $script:Settings.Design = [string]$p.Design
    $script:Settings.Backdrop = [string]$p.Backdrop; $script:Settings.WinOpacity = [int]$p.Opacity
    foreach ($k in @('DsNav', 'DsRadius', 'DsFont', 'DsGraph', 'DsSkin')) { $script:Settings[$k] = 'Auto' }
}
function Reset-Env {
    Get-ChildItem -LiteralPath $tmp -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    $sync.DataDir = $tmp
    $script:Toasts.Clear(); $script:Logs.Clear(); $script:Crash.Clear(); $script:Applied.Clear()
    $script:Confirm = $null; $script:RestartOk = $true; $script:RestartCalls = 0; $script:ExitCalls = 0; $script:Opened = ''
}
function Write-SettingsJson($Obj) { [System.IO.File]::WriteAllText($sync.SettingsFile, (ConvertTo-Json -InputObject $Obj -Depth 8), (New-Object System.Text.UTF8Encoding($false))) }
function Read-SettingsJson { return (ConvertTo-Hashtable (Read-JsonFile $sync.SettingsFile)) }
function New-Legacy([hashtable]$Over) {
    # 9.x'ten kalma kayit: LookVersion ve LookNotice yok
    $d = Get-DefaultSettings
    $d.Remove('LookVersion'); $d.Remove('LookNotice')
    $d.Theme = 'Neon'; $d.Layout = 'Ayrintili'
    foreach ($k in @($Over.Keys)) { $d[$k] = $Over[$k] }
    return $d
}
function New-FakeButton {
    $b = [pscustomobject]@{ IsEnabled = $true; ClickHandler = $null }
    Add-Member -InputObject $b -MemberType ScriptMethod -Name Add_Click -Value { param($h) $this.ClickHandler = $h }
    return $b
}

# ======================= 1) varsayilanlar =======================
$d = Get-DefaultSettings
Assert-Eq $d.Theme 'Acik' 'varsayilan tema beyaz (Acik)'
Assert-Eq $d.Layout 'Sade' 'varsayilan yerlesim sade'
Assert-Eq $d.Design 'Klasik' 'varsayilan tasarim klasik'
Assert-Eq $d.Backdrop 'Yok' 'varsayilan saydamlik kapali'
Assert-Eq $d.WinOpacity 100 'varsayilan opaklik %100'
Assert-Eq $d.Zoom 100 'varsayilan yakinlastirma %100'
Assert-Eq $d.HomeMode 'Pano' 'varsayilan ana ekran pano'
Assert-Eq $d.LookVersion 10 'gorunum surumu 10'
Assert-Eq $d.LookNotice $false 'gorunum bilgisi varsayilan kapali'
$safe = Get-SafeLookKeys 0
Assert-Eq ($safe.Theme + '|' + $safe.Layout + '|' + $safe.HomeMode) 'Neon|Ayrintili|Klasik' 'guvenli gorunum bilerek Neon + Ayrintili + klasik ana ekran kalir (en sinanmis yol)'
Assert-Eq ((Get-LookPreset 'Varsayilan').Theme + '|' + (Get-LookPreset 'Varsayilan').Layout) 'Acik|Sade' 'hazir gorunum Varsayilan = beyaz + sade'
Assert-Eq ((Get-LookPreset 'KoyuNeon').Theme + '|' + (Get-LookPreset 'KoyuNeon').Layout) 'Neon|Ayrintili' 'hazir gorunum Koyu neon = eski varsayilan'

# ======================= 2) kapsam adi ve anahtar listeleri =======================
foreach ($n in @('', $null, 'Gorunum', 'gorunum', 'GORUNUM', ' gorunum ', 'look')) { Assert-Eq (ConvertTo-ResetScope $n) 'Gorunum' ("kapsam: '" + [string]$n + "' = Gorunum") }
foreach ($n in @('Tercihler', 'tercihler', 'TERCIHLER', 'tumu', 'hepsi', 'all')) { Assert-Eq (ConvertTo-ResetScope $n) 'Tercihler' ("kapsam: '" + $n + "' = Tercihler") }
foreach ($n in @('x', 'hepsini', 'gorunumu', 'Ayar')) { Assert-Eq (ConvertTo-ResetScope $n) '' ("kapsam: '" + $n + "' taninmaz") }
$kl = @(Get-ResetKeyList 'Gorunum'); $ka = @(Get-ResetKeyList 'Tercihler')
Assert-Eq $kl.Count $script:ResetLookKeys.Count 'gorunum kapsami: gorunum anahtarlari'
Assert-Eq $ka.Count ($script:ResetLookKeys.Count + $script:ResetPrefKeys.Count) 'tercihler kapsami: gorunum + tercih anahtarlari'
Assert-Eq (@($ka | Select-Object -Unique).Count) $ka.Count 'anahtar listesinde tekrar yok'
Assert-Eq (@($script:ResetPrefKeys | Where-Object { $script:ResetLookKeys -contains $_ }).Count) 0 'gorunum ve tercih listeleri ayri'
foreach ($k in $ka) { Assert-True ($d.ContainsKey($k)) ('anahtarin varsayilani var: ' + $k) }
foreach ($k in @('Theme', 'Layout', 'Zoom', 'Design', 'HomeMode', 'Backdrop', 'WinOpacity', 'DsNav', 'DsRadius', 'DsFont', 'DsGraph', 'DsSkin', 'ReduceMotion', 'SmoothScroll', 'ToTopButton', 'FocusRing', 'WidgetCorner', 'WidgetOpacity', 'WidgetX', 'WidgetY')) { Assert-True ($kl -contains $k) ('gorunum kapsaminda: ' + $k) }
foreach ($k in @('Language', 'Mode', 'ExpertConfirm', 'RestorePoint', 'HideConsole', 'TrayMinimize', 'TrayOnMinimize', 'TrayHints', 'Notify', 'MonitorSec', 'MonGpu', 'KeepLogDays', 'WipePasses', 'DebugLog', 'Board', 'BoardCustom')) { Assert-True (($ka -contains $k) -and -not ($kl -contains $k)) ('yalnizca tercihler kapsaminda: ' + $k) }
# beyaz liste: Windows'ta yapilan degisiklikleri, zamanlanmis gorevleri, yedek, ag koruma ve kuruluma ait kayitlari etkileyen anahtarlar sifirlanmaz
foreach ($k in @('AppliedIds', 'AutoRules', 'BackupSources', 'BackupDest', 'BackupMode', 'BackupSchedEnabled', 'BlockedDevices', 'KnownDevices', 'DeviceNames', 'NetOff', 'NetWatch', 'KillSwitch', 'KillSwitchPrev', 'KsAllowLan', 'GwBaseline',
                 'Games', 'MaintItems', 'MaintEnabled', 'MaintDay', 'MaintTime', 'ReportEnabled', 'UpdateUrl', 'Autostart', 'Installed', 'FirstRunDone', 'BootTries', 'CrashStreak', 'LastBackup', 'LastGuard', 'RegDenied',
                 'OptRam', 'OptGuard', 'OptFocus', 'VpnName', 'VpnBaseHash', 'DohAuto', 'Org', 'Contact', 'UseCase', 'LookVersion', 'LookNotice')) {
    Assert-True (-not ($ka -contains $k)) ('sifirlama kapsaminda degil: ' + $k)
}
Assert-Eq (Get-ValueSig @(1, 2)) (Get-ValueSig @(1, 2)) 'imza: ayni dizi ayni imza'
Assert-True ((Get-ValueSig @(1, 2)) -cne (Get-ValueSig @(2, 1))) 'imza: sirasi farkli dizi farkli imza'
Assert-True ((Get-ValueSig $null) -cne (Get-ValueSig '')) 'imza: bos deger ile bos metin ayrisir'
Assert-True ((Get-ValueSig 100) -cne (Get-ValueSig '100')) 'imza: sayi ile metin ayrisir'

# ======================= 3) Get-ResetResult (saf) =======================
$cur = Get-DefaultSettings
$cur.Theme = 'Holo'; $cur.Layout = 'Kompakt'; $cur.Zoom = 120; $cur.Design = 'Komuta'; $cur.Backdrop = 'Akrilik'; $cur.WinOpacity = 80; $cur.DsNav = 'Fly'; $cur.ReduceMotion = $true; $cur.WidgetX = 300
$cur.Language = 'de'; $cur.Mode = 'Uzman'; $cur.KeepLogDays = 14; $cur.WipePasses = 7; $cur.Board = @('a', 'b'); $cur.BoardCustom = $true
$cur.BackupSources = @('C:\Belgeler'); $cur.NetOff = @('x'); $cur.UpdateUrl = 'https://ornek.invalid'; $cur.Autostart = $true; $cur.LastBackup = '2026-11-01'; $cur.Foo = 'bar'
$r = Get-ResetResult $cur 'Gorunum'
Assert-Eq $r.Scope 'Gorunum' 'sonuc: kapsam'
Assert-Eq ($r.Settings.Theme + '|' + $r.Settings.Layout + '|' + $r.Settings.Zoom + '|' + $r.Settings.Design + '|' + $r.Settings.Backdrop + '|' + $r.Settings.WinOpacity + '|' + $r.Settings.DsNav) 'Acik|Sade|100|Klasik|Yok|100|Auto' 'gorunum sifirlandi'
Assert-Eq ($r.Settings.ReduceMotion.ToString() + '|' + $r.Settings.WidgetX) 'False|-1' 'hareket ve mini izleyici konumu sifirlandi'
Assert-Eq ((@($r.Changed) | Sort-Object) -join ',') 'Backdrop,Design,DsNav,Layout,ReduceMotion,Theme,WidgetX,WinOpacity,Zoom' 'degisen anahtarlar yalnizca farkli olanlardir'
Assert-Eq ($r.Settings.Language + '|' + $r.Settings.Mode + '|' + $r.Settings.KeepLogDays + '|' + $r.Settings.WipePasses + '|' + $r.Settings.BoardCustom) 'de|Uzman|14|7|True' 'gorunum kapsami tercihlere dokunmaz'
Assert-Eq (@($r.Settings.Board).Count) 2 'gorunum kapsami pano duzenine dokunmaz'
Assert-Eq (@($r.Settings.BackupSources) -join ';') 'C:\Belgeler' 'yedek kaynaklari korunur'
Assert-Eq (@($r.Settings.NetOff) -join ';') 'x' 'ag koruma kaydi korunur'
Assert-Eq ($r.Settings.UpdateUrl + '|' + $r.Settings.Autostart + '|' + $r.Settings.LastBackup + '|' + $r.Settings.Foo) 'https://ornek.invalid|True|2026-11-01|bar' 'listede olmayan anahtarlar (bilinmeyenler dahil) korunur'
Assert-Eq ($r.Settings.LookVersion.ToString() + '|' + $r.Settings.LookNotice) '10|False' 'sifirlanan gorunum yeni kayit sayilir (eski varsayilana tasima yeniden calismaz)'
Assert-Eq ($cur.Theme + '|' + $cur.Language + '|' + $cur.Zoom) 'Holo|de|120' 'girdi tablosu degistirilmez'
$r2 = Get-ResetResult $cur 'Tercihler'
Assert-Eq ($r2.Settings.Language + '|' + $r2.Settings.Mode + '|' + $r2.Settings.KeepLogDays + '|' + $r2.Settings.WipePasses + '|' + $r2.Settings.BoardCustom) 'auto|Kullanici|60|1|False' 'tercihler sifirlandi'
Assert-Eq (@($r2.Settings.Board).Count) 0 'pano duzeni sifirlandi'
Assert-Eq ($r2.Settings.Theme + '|' + $r2.Settings.Layout) 'Acik|Sade' 'tercihler kapsami gorunumu de sifirlar'
Assert-Eq (@($r2.Settings.BackupSources) -join ';') 'C:\Belgeler' 'tercihler kapsami da yedek kaynaklarina dokunmaz'
Assert-Eq ($r2.Settings.UpdateUrl + '|' + $r2.Settings.Autostart + '|' + $r2.Settings.Foo) 'https://ornek.invalid|True|bar' 'tercihler kapsami kuruluma ait kayitlara dokunmaz'
Assert-True ((@($r2.Changed) -contains 'Language') -and (@($r2.Changed) -contains 'Board') -and (@($r2.Changed) -contains 'Theme')) 'tercihler: degisenlerde dil, pano ve tema var'
$r3 = Get-ResetResult $r2.Settings 'Tercihler'
Assert-Eq @($r3.Changed).Count 0 'sifirlama ikinci kez degisiklik bulmaz'
$r4 = Get-ResetResult @{} 'Gorunum'
Assert-Eq $r4.Settings.Theme 'Acik' 'bos tablo: varsayilan tema yazilir'
Assert-Eq @($r4.Changed).Count $script:ResetLookKeys.Count 'bos tablo: eksik anahtarlar degisen sayilir'

# ======================= 4) kopyalar: yazma, saklama, siralama, okuma =======================
Reset-Env
Assert-Eq @(Get-ResetBackups).Count 0 'kopya yokken liste bos'
Assert-Eq (Get-SettingsBackupDir) (Join-Path $tmp 'AyarYedekleri') 'kopya klasoru veri klasorunun altinda'
$b1 = Save-SettingsBackup @{ Theme = 'Neon'; Mode = 'Kullanici'; Marker = 'bir' } 'gorunum'
Assert-True ($b1 -ne '' -and (Test-Path -LiteralPath $b1)) 'kopya yazildi'
Assert-True (([System.IO.Path]::GetFileName($b1)) -match '^ayarlar-\d{8}-\d{6}-gorunum\.json$') 'kopya adi: damga + etiket'
Assert-Eq (Read-SettingsBackup $b1).Marker 'bir' 'kopya okunur'
$b2 = Save-SettingsBackup @{ Theme = 'Koyu'; Mode = 'Kullanici'; Marker = 'iki' } 'tercihler'
$b3 = Save-SettingsBackup @{ Theme = 'Kum'; Mode = 'Kullanici'; Marker = 'uc' } 'geri-alma'
$b4 = Save-SettingsBackup @{ Theme = 'Uzay'; Mode = 'Kullanici'; Marker = 'dort' } 'gorunum'
Assert-True (@($b1, $b2, $b3, $b4 | Select-Object -Unique).Count -eq 4) 'ayni saniyede yazilan kopyalar birbirini ezmez'
$lst = @(Get-ResetBackups)
Assert-Eq $lst.Count 3 'liste: geri alma oncesi kopya listelenmez'
Assert-Eq ((@($lst | ForEach-Object { (Read-SettingsBackup $_.Path).Marker })) -join ',') 'dort,iki,bir' 'liste: yeniden eskiye (ayni saniyedeki kopyalarda olusturulma sirasi)'
Assert-Eq ($lst[0].Scope + '|' + $lst[1].Scope + '|' + $lst[2].Scope) 'gorunum|tercihler|gorunum' 'liste: kapsamlar'
Assert-True ($lst[0].Time -is [datetime] -and $lst[0].Time -gt [datetime]::MinValue) 'liste: zaman damgasi okunur'
Assert-Eq @(Get-SettingsBackupFiles).Count 4 'tum kopyalar (geri alma dahil) dosya listesinde'
# tanimsiz adli dosyalar listelenmez ve silinmez
$foreign = Join-Path (Get-SettingsBackupDir) 'ayarlar-benim.json'
[System.IO.File]::WriteAllText($foreign, '{"Theme":"x","Mode":"y"}')
Assert-Eq @(Get-ResetBackups).Count 3 'baska adli dosya listelenmez'
# saklama: en yeni 10 kopya
foreach ($i in 1..12) { [void](Save-SettingsBackup @{ Theme = 'T'; Mode = 'M'; N = $i } 'gorunum') }
$files = @(Get-SettingsBackupFiles)
Assert-Eq $files.Count 10 'saklama: en fazla 10 kopya'
Assert-Eq (Read-SettingsBackup $files[0].Path).N 12 'saklama: en yeni kopya durur'
Assert-Eq (Read-SettingsBackup $files[9].Path).N 3 'saklama: en eski silinenler arasindan sonuncu kalan 3'
Assert-True (Test-Path -LiteralPath $foreign) 'saklama: baska adli dosyaya dokunulmaz'
Assert-Eq @(Get-ResetBackups).Count 10 'saklama sonrasi liste'
# okuma dogrulamasi
$junk = Join-Path $tmp 'bozuk.json'; [System.IO.File]::WriteAllText($junk, 'bu json degil {')
Assert-True ($null -eq (Read-SettingsBackup $junk)) 'bozuk kopya okunmaz'
$noKeys = Join-Path $tmp 'bos.json'; [System.IO.File]::WriteAllText($noKeys, '{"Baska":1}')
Assert-True ($null -eq (Read-SettingsBackup $noKeys)) 'ayar dosyasina benzemeyen kopya okunmaz'
Assert-True ($null -eq (Read-SettingsBackup (Join-Path $tmp 'yok.json'))) 'olmayan kopya okunmaz'
Assert-True ($null -ne (Read-SettingsBackup $files[0].Path)) 'gecerli kopya okunur'
# yazilamayan klasor
Reset-Env
[System.IO.File]::WriteAllText((Join-Path $tmp 'engel'), 'dosya')
$sync.DataDir = Join-Path $tmp 'engel\alt'
Assert-Eq (Save-SettingsBackup @{ Theme = 'Neon'; Mode = 'x' } 'gorunum') '' 'klasor olusturulamazsa kopya bos doner'
Assert-Eq @(Get-ResetBackups).Count 0 'olmayan klasorde liste bos'
$sync.DataDir = $tmp

# ======================= 5) geri yukleme =======================
Reset-Env
Write-SettingsJson @{ Theme = 'Koyu'; Mode = 'Kullanici'; Language = 'tr'; LookVersion = 10 }
$old = Save-SettingsBackup @{ Theme = 'Neon'; Layout = 'Ayrintili'; Mode = 'Uzman'; Language = 'de' } 'gorunum'
$curS = @{ Theme = 'Koyu'; Mode = 'Kullanici'; Language = 'tr'; LookVersion = 10 }
Assert-True (Restore-SettingsFromBackup $old $curS) 'geri yukleme basarili'
$back = Read-SettingsJson
Assert-Eq ($back.Theme + '|' + $back.Mode + '|' + $back.Language) 'Neon|Uzman|de' 'ayar dosyasi kopyadaki degerlere dondu'
Assert-Eq ($back.LookVersion.ToString() + '|' + $back.LookNotice) '10|False' 'geri yuklenen kayitta gorunum surumu yazilir (eski gorunum yeniden tasinmaz)'
$gl = @(Get-SettingsBackupFiles | Where-Object { $_.Scope -eq 'geri-alma' })
Assert-Eq $gl.Count 1 'geri yuklemeden once gecerli ayarlarin kopyasi saklandi'
Assert-Eq (Read-SettingsBackup $gl[0].Path).Theme 'Koyu' 'saklanan kopya geri yukleme oncesi degerleri tasir'
Assert-Eq @(Get-ResetBackups).Count 1 'geri alma oncesi kopya sifirlama listesine girmez'
$before = Get-Content -LiteralPath $sync.SettingsFile -Raw
Assert-True (-not (Restore-SettingsFromBackup $junk $curS)) 'bozuk kopya geri yuklenmez'
Assert-Eq (Get-Content -LiteralPath $sync.SettingsFile -Raw) $before 'basarisiz geri yukleme ayar dosyasina dokunmaz'
Assert-True (-not (Restore-SettingsFromBackup (Join-Path $tmp 'yok.json') $curS)) 'olmayan kopya geri yuklenmez'

# ======================= 6) eski kaydin gorunumu bir kez yeni varsayilana tasinir (Get-Settings) =======================
# 6a) hic dokunulmamis eski varsayilan (Neon + Ayrintili)
Reset-Env
Write-SettingsJson (New-Legacy @{ KeepLogDays = 30; Zoom = 110; Language = 'de' })
$g = Get-Settings
Assert-Eq ($g.Theme + '|' + $g.Layout + '|' + $g.Design + '|' + $g.Backdrop) 'Acik|Sade|Klasik|Yok' 'eski varsayilan kayit: beyaz ve sade olur'
Assert-Eq ($g.LookNotice.ToString() + '|' + $g.LookVersion) 'True|10' 'eski varsayilan kayit: bilgi bekliyor, surum 10'
Assert-Eq ($g.KeepLogDays.ToString() + '|' + $g.Zoom + '|' + $g.Language) '30|110|de' 'eski varsayilan kayit: tercihler ve yakinlastirma korunur'
$bk = @(Get-ResetBackups)
Assert-Eq $bk.Count 1 'eski varsayilan kayit: gecis oncesi kopya yazildi'
Assert-Eq $bk[0].Scope 'gorunum' 'kopya gorunum etiketli'
Assert-Eq ((Read-SettingsBackup $bk[0].Path).Theme + '|' + (Read-SettingsBackup $bk[0].Path).Layout) 'Neon|Ayrintili' 'kopya eski gorunumu tasir'
Assert-Eq (Read-SettingsJson).Theme 'Neon' 'Get-Settings dosyaya yazmaz (kayit arayuz tarafindan yapilir)'
# kayit sonrasi tekrar okuma: ikinci gecis ve ikinci kopya yok
Save-Settings $g
$g2 = Get-Settings
Assert-Eq ($g2.Theme + '|' + $g2.Layout + '|' + $g2.LookNotice) 'Acik|Sade|True' 'kayittan sonra gorunum kalici; bilgi hala bekliyor'
Assert-Eq @(Get-ResetBackups).Count 1 'kayittan sonra ikinci gecis ve ikinci kopya olmaz'
# geri al: eski gorunum geri gelir ve yeniden tasinmaz
Assert-True (Restore-SettingsFromBackup $bk[0].Path $g2) 'gecis kopyasi geri yuklenir'
$g3 = Get-Settings
Assert-Eq ($g3.Theme + '|' + $g3.Layout + '|' + $g3.LookNotice) 'Neon|Ayrintili|False' 'geri alinca eski gorunum kalir, yeniden tasinmaz'
Assert-Eq @(Get-ResetBackups).Count 1 'geri alma ikinci gecis kopyasi uretmez'

# 6b) secilmis ozel gorunum de (kopyasi alinarak) yeni varsayilana tasinir; yakinlastirma, ana ekran biçimi ve pano korunur
Reset-Env
Write-SettingsJson (New-Legacy @{ Theme = 'Holo'; Layout = 'Kompakt'; Design = 'Komuta'; Backdrop = 'Akrilik'; WinOpacity = 100; DsNav = 'Fly'; HomeMode = 'Pano'; BoardCustom = $true; Board = @('a'); Zoom = 120 })
$g = Get-Settings
Assert-Eq ($g.Theme + '|' + $g.Layout + '|' + $g.Design + '|' + $g.Backdrop + '|' + $g.DsNav) 'Acik|Sade|Klasik|Yok|Auto' 'ozel gorunum: yeni varsayilana tasinir'
Assert-Eq ($g.Zoom.ToString() + '|' + $g.HomeMode + '|' + $g.BoardCustom + '|' + @($g.Board).Count) '120|Pano|True|1' 'ozel gorunum: yakinlastirma, ana ekran biçimi ve pano korunur'
Assert-Eq $g.LookNotice $true 'ozel gorunum: bilgi bekliyor'
$bk = @(Get-ResetBackups)
Assert-Eq $bk.Count 1 'ozel gorunum: kopya yazildi'
Assert-Eq ((Read-SettingsBackup $bk[0].Path).Theme + '|' + (Read-SettingsBackup $bk[0].Path).Design + '|' + (Read-SettingsBackup $bk[0].Path).Backdrop) 'Holo|Komuta|Akrilik' 'ozel gorunum: kopya eski gorunumu tasir'

# 6c) zaten yeni varsayilan gorunumdeki eski kayit: bilgi ve kopya yok
Reset-Env
Write-SettingsJson (New-Legacy @{ Theme = 'Acik'; Layout = 'Sade'; KeepLogDays = 20 })
$g = Get-Settings
Assert-Eq ($g.Theme + '|' + $g.Layout + '|' + $g.LookNotice + '|' + $g.KeepLogDays) 'Acik|Sade|False|20' 'zaten beyaz ve sade: bilgi yok'
Assert-Eq @(Get-ResetBackups).Count 0 'zaten beyaz ve sade: kopya yok'

# 6d) gorunum anahtari olmayan kayit (yeni ya da kismi): bilgi ve kopya yok
Reset-Env
Write-SettingsJson @{ Language = 'en' }
$g = Get-Settings
Assert-Eq ($g.Theme + '|' + $g.Layout + '|' + $g.Language + '|' + $g.LookNotice) 'Acik|Sade|en|False' 'gorunum anahtari olmayan kayit: varsayilan gorunum, bilgi yok'
Assert-Eq @(Get-ResetBackups).Count 0 'gorunum anahtari olmayan kayit: kopya yok'

# 6e) surumu olan kayit: secim korunur
Reset-Env
Write-SettingsJson @{ Theme = 'Neon'; Layout = 'Ayrintili'; Mode = 'Kullanici'; LookVersion = 10; Language = 'tr' }
$g = Get-Settings
Assert-Eq ($g.Theme + '|' + $g.Layout + '|' + $g.LookNotice) 'Neon|Ayrintili|False' 'surumu olan kayit: gorunum korunur'
Assert-Eq @(Get-ResetBackups).Count 0 'surumu olan kayit: kopya yok'

# 6f) kopya yazilamazsa gorunume dokunulmaz
Reset-Env
Write-SettingsJson (New-Legacy @{ Theme = 'Holo' })
$sync.DataDir = Join-Path $tmp 'engel\alt'
[System.IO.File]::WriteAllText((Join-Path $tmp 'engel'), 'dosya')
$g = Get-Settings
Assert-Eq ($g.Theme + '|' + $g.LookNotice) 'Holo|False' 'kopya yazilamazsa gorunum korunur ve bilgi gosterilmez'
$sync.DataDir = $tmp

# 6g) dosya yok / bozuk
Reset-Env
$g = Get-Settings
Assert-Eq ($g.Theme + '|' + $g.Layout + '|' + $g.LookNotice + '|' + $g.LookVersion) 'Acik|Sade|False|10' 'ayar dosyasi yoksa varsayilanlar'
[System.IO.File]::WriteAllText($sync.SettingsFile, '{ bozuk json')
$g = Get-Settings
Assert-Eq ($g.Theme + '|' + $g.Layout + '|' + $g.LookNotice) 'Acik|Sade|False' 'bozuk ayar dosyasinda varsayilanlar, hata yok'

# ======================= 7) Reset-SettingsFile ve komut satiri =======================
Reset-Env
$custom = Get-DefaultSettings; $custom.Theme = 'Holo'; $custom.Layout = 'Kompakt'; $custom.Language = 'de'; $custom.KeepLogDays = 7; $custom.BackupSources = @('D:\Yedek')
Write-SettingsJson $custom
$Deger = 'Gorunum'
Assert-Eq (Invoke-CliResetSettings) 0 'komut satiri: gorunum sifirlama basarili'
$f = Read-SettingsJson
Assert-Eq ($f.Theme + '|' + $f.Layout + '|' + $f.Language + '|' + $f.KeepLogDays) 'Acik|Sade|de|7' 'komut satiri gorunum: yalnizca gorunum sifirlandi'
Assert-Eq (@($f.BackupSources) -join ';') 'D:\Yedek' 'komut satiri: yedek kaynaklari korundu'
Assert-Eq @(Get-ResetBackups).Count 1 'komut satiri: kopya yazildi'
Assert-Eq ((Read-SettingsBackup @(Get-ResetBackups)[0].Path).Theme) 'Holo' 'komut satiri: kopya onceki gorunumu tasir'
Assert-True (@($script:Logs | Where-Object { $_ -like 'OK|*2 ayar degisti*' -or $_ -like 'OK|*2 ayar de*' }).Count -ge 1) 'komut satiri: degisen ayar sayisi bildirildi (2)'
Assert-True (@($script:Logs | Where-Object { $_ -like 'INFO|*AyarYedekleri*' }).Count -ge 1) 'komut satiri: kopya yolu bildirildi'
$script:Logs.Clear()
$Deger = 'Tercihler'
Assert-Eq (Invoke-CliResetSettings) 0 'komut satiri: tercihler sifirlama basarili'
$f = Read-SettingsJson
Assert-Eq ($f.Language + '|' + $f.KeepLogDays + '|' + $f.Mode) 'auto|60|Kullanici' 'komut satiri tercihler: dil ve gunluk suresi sifirlandi'
Assert-Eq (@($f.BackupSources) -join ';') 'D:\Yedek' 'komut satiri tercihler: yedek kaynaklari yine korundu'
Assert-True (@($script:Logs | Where-Object { $_ -like 'OK|Uygulama tercihleri*' }).Count -eq 1) 'komut satiri: tercihler bildirimi'
$script:Logs.Clear()
$before = Get-Content -LiteralPath $sync.SettingsFile -Raw; $nb = @(Get-ResetBackups).Count
$Deger = 'yanlis'
Assert-Eq (Invoke-CliResetSettings) 1 'komut satiri: bilinmeyen kapsam hata kodu 1'
Assert-True (@($script:Logs | Where-Object { $_ -like 'ERR|*AyarSifirla*' }).Count -eq 1) 'komut satiri: kullanim iletisi'
Assert-Eq (Get-Content -LiteralPath $sync.SettingsFile -Raw) $before 'komut satiri: bilinmeyen kapsam dosyaya dokunmaz'
Assert-Eq @(Get-ResetBackups).Count $nb 'komut satiri: bilinmeyen kapsam kopya yazmaz'
$script:Logs.Clear()
# bos deger = gorunum
$custom = Get-DefaultSettings; $custom.Theme = 'Hacker'; Write-SettingsJson $custom
$Deger = ''
Assert-Eq (Invoke-CliResetSettings) 0 'komut satiri: bos deger gorunum sayilir'
Assert-Eq (Read-SettingsJson).Theme 'Acik' 'komut satiri: bos deger gorunumu sifirladi'
# ayar dosyasi yokken
Reset-Env
$Deger = 'Gorunum'
Assert-Eq (Invoke-CliResetSettings) 0 'komut satiri: ayar dosyasi yokken de calisir'
Assert-True (Test-Path -LiteralPath $sync.SettingsFile) 'komut satiri: ayar dosyasi olusturuldu'
Assert-True (@($script:Logs | Where-Object { $_ -like 'OK|*0 ayar*' }).Count -ge 1) 'komut satiri: degisen ayar yok bildirimi'
# kopya yazilamazsa sifirlama yapilmaz
Reset-Env
$custom = Get-DefaultSettings; $custom.Theme = 'Holo'; Write-SettingsJson $custom
[System.IO.File]::WriteAllText((Join-Path $tmp 'engel'), 'dosya')
$sync.DataDir = Join-Path $tmp 'engel\alt'
$sync.SettingsFile = Join-Path $tmp 'ayarlar.json'
$before = Get-Content -LiteralPath $sync.SettingsFile -Raw
Assert-Eq (Invoke-CliResetSettings) 1 'komut satiri: kopya yazilamazsa hata kodu 1'
Assert-Eq (Get-Content -LiteralPath $sync.SettingsFile -Raw) $before 'komut satiri: kopya yazilamazsa ayarlar degismez'
Assert-True (@($script:Logs | Where-Object { $_ -like 'ERR|*yap*lmad*' }).Count -ge 1) 'komut satiri: kopya hatasi bildirildi'
$sync.DataDir = $tmp

# arayuz acikken komut satirindan sifirlama yapilmaz (baska surecte tutulan adli mutex)
Reset-Env
$custom = Get-DefaultSettings; $custom.Theme = 'Holo'; Write-SettingsJson $custom
Assert-True (-not (Test-GuiRunning)) 'arayuz kapaliyken Test-GuiRunning yanlis'
$pwshExe = (Get-Process -Id $PID).Path
$hold = '$m = New-Object System.Threading.Mutex($false, ''Global\Multimizer-Arayuz''); [void]$m.WaitOne(0); Start-Sleep -Seconds 90'
$enc = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($hold))
$holder = $null
try {
    $holder = Start-Process -FilePath $pwshExe -ArgumentList @('-NoProfile', '-EncodedCommand', $enc) -PassThru -RedirectStandardOutput (Join-Path $tmp 'tutucu.out') -RedirectStandardError (Join-Path $tmp 'tutucu.err')
    $busy = $false
    foreach ($i in 1..60) { if (Test-GuiRunning) { $busy = $true; break }; Start-Sleep -Milliseconds 250 }
    Assert-True $busy 'baska surec adli mutex''i tutarken Test-GuiRunning dogru'
    if ($busy) {
        $before = Get-Content -LiteralPath $sync.SettingsFile -Raw
        $Deger = 'Gorunum'; $script:Logs.Clear()
        Assert-Eq (Invoke-CliResetSettings) 3 'komut satiri: arayuz aciksa hata kodu 3'
        Assert-Eq (Get-Content -LiteralPath $sync.SettingsFile -Raw) $before 'komut satiri: arayuz aciksa ayarlar degismez'
        Assert-Eq @(Get-ResetBackups).Count 0 'komut satiri: arayuz aciksa kopya yazilmaz'
        Assert-True (@($script:Logs | Where-Object { $_ -like 'ERR|*kapat*' }).Count -ge 1) 'komut satiri: arayuz aciksa uyari'
    }
} finally {
    if ($null -ne $holder) { try { Stop-Process -Id $holder.Id -Force -ErrorAction SilentlyContinue } catch { }; try { $holder.WaitForExit(5000) | Out-Null } catch { } }
}
Assert-True (-not (Test-GuiRunning)) 'tutan surec ölünce (terk edilmis mutex) arayuz kapali sayilir'

# ======================= 8) arayuz akisi =======================
Reset-Env
$ui = @{}
$ui.st_ResetScope = New-FakeCombo
Add-Member -InputObject $ui.st_ResetScope -MemberType ScriptMethod -Name Add_SelectionChanged -Value { param($h) $this | Add-Member -NotePropertyName ChangeHandler -NotePropertyValue $h -Force }
$ui.st_ResetNote = [pscustomobject]@{ Text = '' }
$ui.st_ResetState = [pscustomobject]@{ Text = '' }
$ui.st_ResetRun = New-FakeButton; $ui.st_ResetUndo = New-FakeButton; $ui.st_ResetFolder = New-FakeButton
$ui.Overlay = [pscustomobject]@{ Visibility = 'Collapsed' }
Initialize-StReset
Assert-Eq (@($ui.st_ResetScope.Items | ForEach-Object { $_['Key'] }) -join ',') 'Gorunum,Tercihler,Fabrika' 'kapsam listesi: görünüm, tercihler ve her şey'
Load-StReset
Assert-Eq (Get-ComboKey $ui.st_ResetScope) 'Gorunum' 'yukle: varsayilan kapsam gorunum'
Assert-True ($ui.st_ResetNote.Text -like '*yeniden başlatma gerekmez*') 'gorunum kapsami notu: yeniden baslatma gerekmez'
Assert-True ($ui.st_ResetNote.Text -like '*ana ekran biçimi*') 'gorunum kapsami notu: ana ekran biçimi de sayilir'
Assert-Eq $ui.st_ResetUndo.IsEnabled $false 'kopya yokken geri alma dugmesi kapali'
Assert-Eq $ui.st_ResetState.Text 'Henüz sıfırlama yapılmadı.' 'kopya yokken durum satiri'
[void](Select-ComboKey $ui.st_ResetScope 'Tercihler'); Update-StReset
Assert-True ($ui.st_ResetNote.Text -like '*Uygulama yeniden başlatılır*') 'tercihler kapsami notu: yeniden baslatilir'
[void](Select-ComboKey $ui.st_ResetScope 'Gorunum')
Init-StReset
Assert-True ($null -ne $ui.st_ResetScope.ChangeHandler -and $null -ne $ui.st_ResetRun.ClickHandler -and $null -ne $ui.st_ResetUndo.ClickHandler -and $null -ne $ui.st_ResetFolder.ClickHandler) 'dugme ve liste olaylari baglandi'
# kapsam degisince not guncellenir (yukleme sirasinda degil)
[void](Select-ComboKey $ui.st_ResetScope 'Tercihler'); $script:StLoading = $true; $ui.st_ResetNote.Text = ''
& $ui.st_ResetScope.ChangeHandler $null $null
Assert-Eq $ui.st_ResetNote.Text '' 'yukleme sirasinda secim degisimi yok sayilir'
$script:StLoading = $false
& $ui.st_ResetScope.ChangeHandler $null $null
Assert-True ($ui.st_ResetNote.Text -like '*Uygulama yeniden başlatılır*') 'secim degisince kapsam notu guncellenir'
[void](Select-ComboKey $ui.st_ResetScope 'Gorunum')
# klasor dugmesi
& $ui.st_ResetFolder.ClickHandler $null $null
Assert-Eq $script:Opened (Get-SettingsBackupDir) 'klasor dugmesi kopya klasorunu acar'
Assert-True (Test-Path -LiteralPath (Get-SettingsBackupDir) -PathType Container) 'klasor yoksa olusturulur'

# 8a) gorunum sifirlama
$cust = Get-DefaultSettings; $cust.Theme = 'Holo'; $cust.Layout = 'Kompakt'; $cust.Zoom = 120; $cust.Language = 'de'; $cust.ReduceMotion = $true; $cust.SmoothScroll = $false; $cust.ToTopButton = $false; $cust.FocusRing = $false
$cust.WidgetCorner = 'BL'; $cust.WidgetOpacity = 60; $cust.WidgetX = 10; $cust.WidgetY = 20; $cust.HomeMode = 'Klasik'
$script:Settings = $cust
Write-SettingsJson $cust
$script:Toasts.Clear(); $script:Applied.Clear()
Invoke-StResetRun
Assert-Eq ($script:Confirm.Title + '|' + $script:Confirm.OkText + '|' + $script:Confirm.Danger) 'Ayarları sıfırla|Sıfırla|False' 'gorunum onayi: baslik, dugme, tehlikeli degil'
Assert-True ($script:Confirm.Text -like '*beyaz tema, sade yerleşim*') 'gorunum onayi: ne olacagi yazilir'
Assert-Eq @(Get-ResetBackups).Count 0 'onay verilmeden kopya yazilmaz'
& $script:Confirm.OnOk
Assert-Eq (($script:Applied) -join ',') 'preset:Varsayilan,home:Pano' 'gorunum: Varsayilan hazir gorunum ve varsayilan ana ekran uygulandi'
$sg = $script:Settings
Assert-Eq ($sg.Theme + '|' + $sg.Layout + '|' + $sg.Zoom + '|' + $sg.HomeMode) 'Acik|Sade|100|Pano' 'gorunum: bellekteki ayarlar sifirlandi'
Assert-Eq ($sg.ReduceMotion.ToString() + '|' + $sg.SmoothScroll + '|' + $sg.ToTopButton + '|' + $sg.FocusRing) 'False|True|True|True' 'gorunum: hareket ve kaydirma anahtarlari sifirlandi'
Assert-Eq ($sg.WidgetCorner + '|' + $sg.WidgetOpacity + '|' + $sg.WidgetX + '|' + $sg.WidgetY) 'TR|100|-1|-1' 'gorunum: mini izleyici konumu sifirlandi'
Assert-Eq $sg.Language 'de' 'gorunum: dile dokunulmaz'
Assert-Eq ($sg.LookVersion.ToString() + '|' + $sg.LookNotice) '10|False' 'gorunum: surum yazilir, bilgi kapali'
$fs = Read-SettingsJson
Assert-Eq ($fs.Theme + '|' + $fs.Layout + '|' + $fs.Language) 'Acik|Sade|de' 'gorunum: dosyaya yazildi'
$bk = @(Get-ResetBackups)
Assert-Eq $bk.Count 1 'gorunum: bir kopya yazildi'
Assert-Eq ((Read-SettingsBackup $bk[0].Path).Theme + '|' + $bk[0].Scope) 'Holo|gorunum' 'gorunum: kopya onceki degerleri tasir'
Assert-Eq $script:Toasts[$script:Toasts.Count - 1] 'good|Görünüm varsayılan değerlere döndürüldü.' 'gorunum: basari bildirimi'
Assert-Eq $script:RestartCalls 0 'gorunum: yeniden baslatma yok'
Assert-Eq $ui.st_ResetUndo.IsEnabled $true 'gorunum: geri alma dugmesi acildi'
Assert-True ($ui.st_ResetState.Text -like 'Son sıfırlama: * (görünüm)') 'gorunum: durum satiri son sifirlamayi gosterir'
# onay tekrar tetiklenirse ikinci kez calismaz
$nApplied = $script:Applied.Count
& $script:Confirm.OnOk
Assert-Eq $script:Applied.Count $nApplied 'onay eylemi bir kez calisir (bekleyen kapsam temizlenir)'
Assert-Eq @(Get-ResetBackups).Count 1 'ikinci tetikleme ikinci kopya yazmaz'

# 8b) tercihler sifirlama
$cust = Get-DefaultSettings; $cust.Theme = 'Holo'; $cust.Language = 'de'; $cust.KeepLogDays = 5; $cust.BackupSources = @('E:\Veri'); $cust.Autostart = $true
$script:Settings = $cust; Write-SettingsJson $cust
$script:Toasts.Clear(); $script:Applied.Clear(); $script:RestartCalls = 0; $script:ExitCalls = 0
[void](Select-ComboKey $ui.st_ResetScope 'Tercihler')
Invoke-StResetRun
Assert-Eq ($script:Confirm.Title + '|' + $script:Confirm.OkText + '|' + $script:Confirm.Danger) 'Ayarları sıfırla|Sıfırla|True' 'tercihler onayi: tehlikeli dugme'
Assert-True ($script:Confirm.Text -like '*uygulama yeniden başlatılacak*') 'tercihler onayi: yeniden baslatma bildirilir'
& $script:Confirm.OnOk
Assert-Eq ($script:RestartCalls.ToString() + '|' + $script:ExitCalls) '1|1' 'tercihler: yeniden baslatilir ve cikilir'
$sg = $script:Settings
Assert-Eq ($sg.Language + '|' + $sg.KeepLogDays + '|' + $sg.Theme) 'auto|60|Acik' 'tercihler: bellekteki ayarlar sifirlandi'
Assert-Eq (@($sg.BackupSources) -join ';') 'E:\Veri' 'tercihler: yedek kaynaklari korundu'
Assert-Eq $sg.Autostart $true 'tercihler: Windows ile baslatma ayarina dokunulmaz'
$fs = Read-SettingsJson
Assert-Eq ($fs.Language + '|' + $fs.KeepLogDays + '|' + (@($fs.BackupSources) -join ';')) 'auto|60|E:\Veri' 'tercihler: dosyaya yazildi'
Assert-Eq @(Get-ResetBackups | Where-Object { $_.Scope -eq 'tercihler' }).Count 1 'tercihler: tercihler etiketli kopya yazildi'
# yeniden baslatilamazsa cikilmaz, ayarlar bir sonraki acilista gecerli olur
$cust = Get-DefaultSettings; $cust.Language = 'ja'; $script:Settings = $cust; Write-SettingsJson $cust
$script:Toasts.Clear(); $script:RestartCalls = 0; $script:ExitCalls = 0; $script:RestartOk = $false
Complete-StReset 'Tercihler'
Assert-Eq ($script:RestartCalls.ToString() + '|' + $script:ExitCalls) '1|0' 'tercihler: yeniden baslatilamazsa cikilmaz'
Assert-True ($script:Toasts[$script:Toasts.Count - 1] -like 'warn|Uygulama yeniden başlatılamadı; kapatıp elle açın. Sıfırlanan ayarlar*') 'tercihler: elle acma uyarisi'
Assert-Eq (Read-SettingsJson).Language 'auto' 'tercihler: yeniden baslatilamasa da ayarlar yazildi'
$script:RestartOk = $true

# 8c) kopya yazilamazsa hicbir sey sifirlanmaz
$cust = Get-DefaultSettings; $cust.Theme = 'Holo'; $script:Settings = $cust; Write-SettingsJson $cust
Reset-Env; $script:Settings = $cust
[System.IO.File]::WriteAllText((Join-Path $tmp 'engel'), 'dosya')
$sync.DataDir = Join-Path $tmp 'engel\alt'
Write-SettingsJson $cust
foreach ($sc in @('Gorunum', 'Tercihler')) {
    $script:Toasts.Clear(); $script:Applied.Clear(); $script:RestartCalls = 0
    Complete-StReset $sc
    Assert-Eq $script:Toasts[$script:Toasts.Count - 1] 'bad|Ayar kopyası yazılamadı; sıfırlama yapılmadı.' ($sc + ': kopya yazilamazsa hata bildirimi')
    Assert-Eq ($script:Settings.Theme + '|' + $script:Applied.Count + '|' + $script:RestartCalls) 'Holo|0|0' ($sc + ': kopya yazilamazsa hicbir sey uygulanmaz')
}
Assert-Eq (Read-SettingsJson).Theme 'Holo' 'kopya yazilamazsa dosya degismez'
$sync.DataDir = $tmp

# 8d) son sifirlamayi geri al
Reset-Env
$ui.st_ResetUndo.IsEnabled = $true
$script:Toasts.Clear()
Invoke-StResetUndo
Assert-Eq $script:Toasts[$script:Toasts.Count - 1] 'info|Geri alınacak bir ayar kopyası yok.' 'geri al: kopya yoksa bilgi'
Assert-True ($null -eq $script:Confirm) 'geri al: kopya yoksa onay sorulmaz'
$cust = Get-DefaultSettings; $cust.Theme = 'Hacker'; $cust.Language = 'ar'; $cust.LookVersion = 10
$bkp = Save-SettingsBackup $cust 'gorunum'
$now = Get-DefaultSettings; $script:Settings = $now; Write-SettingsJson $now
$script:Toasts.Clear(); $script:RestartCalls = 0; $script:ExitCalls = 0
Invoke-StResetUndo
Assert-Eq $script:Confirm.Title 'Son sıfırlamayı geri al' 'geri al: onay basligi'
Assert-Eq $script:Confirm.OkText 'Geri yükle' 'geri al: onay dugmesi'
Assert-Eq (Read-SettingsJson).Theme 'Acik' 'onay verilmeden ayarlar degismez'
& $script:Confirm.OnOk
Assert-Eq ((Read-SettingsJson).Theme + '|' + (Read-SettingsJson).Language) 'Hacker|ar' 'geri al: kopya ayar dosyasina yazildi'
Assert-Eq ($script:Settings.Theme + '|' + $script:Settings.Language) 'Hacker|ar' 'geri al: bellekteki ayarlar dosyadan yenilendi'
Assert-Eq ($script:RestartCalls.ToString() + '|' + $script:ExitCalls) '1|1' 'geri al: yeniden baslatilir'
# bozuk kopya
Reset-Env
$bad = Save-SettingsBackup @{ Theme = 'x'; Mode = 'y' } 'gorunum'
[System.IO.File]::WriteAllText($bad, 'bozuk')
$script:Settings = Get-DefaultSettings; Write-SettingsJson $script:Settings
Invoke-StResetUndo
& $script:Confirm.OnOk
Assert-Eq $script:Toasts[$script:Toasts.Count - 1] 'bad|Ayar kopyası okunamadı; geri alma yapılmadı.' 'geri al: bozuk kopyada hata bildirimi'
Assert-Eq $script:RestartCalls 0 'geri al: bozuk kopyada yeniden baslatma yok'
# yeniden baslatilamazsa
Reset-Env
[void](Save-SettingsBackup @{ Theme = 'Kum'; Mode = 'y' } 'tercihler')
$script:Settings = Get-DefaultSettings; Write-SettingsJson $script:Settings
$script:RestartOk = $false
Invoke-StResetUndo
& $script:Confirm.OnOk
Assert-Eq $script:Toasts[$script:Toasts.Count - 1] 'warn|Uygulama yeniden başlatılamadı; kapatıp elle açın.' 'geri al: yeniden baslatilamazsa uyari'
Assert-Eq $script:ExitCalls 0 'geri al: yeniden baslatilamazsa cikilmaz'
$script:RestartOk = $true

# ======================= 9) gorunum degisti bilgisi (tek seferlik) =======================
Reset-Env
$script:LookNoticeTimer = $null
$script:Settings = Get-DefaultSettings; $script:Settings.LookNotice = $true
$script:SmokeMode = $true
Initialize-LookNotice
Assert-True ($null -eq $script:LookNoticeTimer) 'duman kipinde bilgi zamanlayicisi kurulmaz'
$script:SmokeMode = $false; $script:Settings.LookNotice = $false
Initialize-LookNotice
Assert-True ($null -eq $script:LookNoticeTimer) 'bilgi bekleyen yoksa zamanlayici kurulmaz'
$script:Settings.LookNotice = $true
$script:Win = [pscustomobject]@{ IsVisible = $false }
Initialize-LookNotice
$tm = $script:LookNoticeTimer
Assert-True ($null -ne $tm -and $tm.Running -and $tm.Interval.TotalSeconds -eq 2 -and $null -ne $tm.TickHandler) 'bilgi zamanlayicisi 2 sn araliklarla baslar'
$script:Toasts.Clear()
& $tm.TickHandler $null $null
Assert-True ($script:Toasts.Count -eq 0 -and $tm.Running -and $script:Settings.LookNotice -eq $true) 'pencere gorunmezken bilgi gosterilmez, zamanlayici surer'
$script:Win.IsVisible = $true; $ui.Overlay.Visibility = 'Visible'
& $tm.TickHandler $null $null
Assert-True ($script:Toasts.Count -eq 0 -and $tm.Running) 'ust katman aciksa bilgi beklenir'
$ui.Overlay.Visibility = 'Collapsed'
& $tm.TickHandler $null $null
Assert-Eq $script:Toasts.Count 1 'bilgi bir kez gosterilir'
Assert-True ($script:Toasts[0] -like 'info|Görünüm güncellendi: varsayılan tema beyaz ve sade oldu.*Ayarlar > Sıfırlama*') 'bilgi metni: yeni varsayilan ve geri donus yolu'
Assert-True ((-not $tm.Running) -and $script:Settings.LookNotice -eq $false) 'bilgiden sonra zamanlayici durur, bayrak kapanir'
Assert-Eq (Read-SettingsJson).LookNotice $false 'bilgi bayragi dosyaya yazildi (bir daha gosterilmez)'
# 30 denemeden sonra vazgecilir
$script:Settings.LookNotice = $true; $script:Win.IsVisible = $false; $script:Toasts.Clear()
Initialize-LookNotice
$tm = $script:LookNoticeTimer
foreach ($i in 1..31) { & $tm.TickHandler $null $null }
Assert-True ((-not $tm.Running) -and $script:Toasts.Count -eq 0) '30 denemede pencere gorunmediyse zamanlayici bilgi gostermeden durur'

# ======================= 10) baglanti: XAML adlari, sayfa kurulumu, komut satiri =======================
$src = [System.IO.File]::ReadAllText($env:MM_BUILD)
foreach ($n in @('st_ResetScope', 'st_ResetNote', 'st_ResetRun', 'st_ResetUndo', 'st_ResetFolder', 'st_ResetState')) {
    Assert-Eq ([regex]::Matches($src, 'x:Name="' + $n + '"').Count) 1 ('XAML: ' + $n + ' bir kez tanimli')
}
$iRs = $src.IndexOf('x:Name="st_ResetScope"'); $iAb = $src.IndexOf('Text="HAKKINDA"')
Assert-True ($iRs -gt 0 -and $iAb -gt $iRs) 'sifirlama karti HAKKINDA kartindan once'
function Get-FnText([string]$Name) { $f = @(Get-AstFunctions | Where-Object { ($_.Name -replace '^global:', '') -eq $Name }) | Select-Object -Last 1; if ($null -eq $f) { return '' }; return [string]$f.Extent.Text }
$pageText = Get-FnText 'Init-Page_settings'
Assert-True ($pageText.Contains('Initialize-StReset') -and $pageText.Contains('Init-StReset')) 'Init-Page_settings sifirlama kartini baglar'
$loadAll = ''
foreach ($f in @(Get-AstFunctions)) { if ($f.Extent.Text.Contains('Load-StReset') -and ($f.Name -replace '^global:', '') -ne 'Load-StReset') { $loadAll += $f.Name + ';' } }
Assert-True ($loadAll -ne '') ('Load-StReset ayarlar sayfasi yuklenirken cagrilir (' + $loadAll + ')')
Assert-True ((Get-FnText 'Start-UiTimers').Contains('Initialize-LookNotice')) 'Start-UiTimers gorunum bilgisini kurar'
Assert-True ($src.Contains("'ayarsifirla' { `$code = Invoke-CliResetSettings }")) 'komut satiri: AyarSifirla gorevi baglandi'
Assert-True ([regex]::Matches($src, 'AyarSifirla').Count -ge 4) 'yardim metni ve ust bilgi AyarSifirla gorevini anlatir'
Assert-True ($src.Contains("'ayarsifirla'") -and $src.IndexOf("'ayarsifirla'") -lt $src.IndexOf("'gorunumsifirla'")) 'AyarSifirla, GorunumSifirla kolundan once'

try { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue } catch { }
# ======================= her şey (Fabrika) kapsamı =======================
Assert-Eq (ConvertTo-ResetScope 'Fabrika') 'Fabrika' 'kapsam adı: Fabrika'
Assert-Eq (ConvertTo-ResetScope 'hersey') 'Fabrika' 'kapsam adı: hersey'
$fk = @(Get-ResetKeyList 'Fabrika')
Assert-True ($fk -contains 'AppliedIds' -and $fk -contains 'MaintEnabled' -and $fk -contains 'Theme' -and $fk -contains 'SafeRender') 'her şey: uygulanan ayar kaydı, bakım, görünüm ve güvenli çizim sıfırlanır'
foreach ($kk in @('Installed', 'LookVersion', 'FixLevel', 'PrepSeen')) { Assert-True ($fk -notcontains $kk) ("her şey: $kk korunur") }
$cur = Get-DefaultSettings
$cur.AppliedIds = @('Telemetry', 'Ads'); $cur.Theme = 'Neon'; $cur.MaintEnabled = $true; $cur.Installed = $true; $cur.SafeRender = $true
$fr = Get-ResetResult $cur 'Fabrika'
Assert-Eq @($fr.Settings.AppliedIds).Count 0 'her şey: uygulanan ayar listesi boşalır'
Assert-True ($fr.Settings.Installed -eq $true) 'her şey: kurulum bilgisi korunur'
Assert-True ($fr.Settings.SafeRender -ne $true -and $fr.Settings.MaintEnabled -ne $true) 'her şey: güvenli çizim ve zamanlanmış bakım kapalıya döner'
Assert-True (@($fr.Changed) -contains 'AppliedIds' -and @($fr.Changed) -contains 'Theme') 'her şey: değişen anahtarlar raporlanır'
$jd = Join-Path ([System.IO.Path]::GetTempPath()) ('mm-j-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $jd -Force)
foreach ($n in @('yedek-20261003-101434.jsonl', 'yedek-20261112-161151.jsonl', 'yedek-20261007-205808.geri.reg', 'yedek-20261003-101434.geri-alindi.jsonl', 'yedek-20261021-092321.jsonl', 'baska.jsonl')) { [System.IO.File]::WriteAllText((Join-Path $jd $n), '{}') }
$uj = @(Get-UndoableJournals $jd | ForEach-Object { [System.IO.Path]::GetFileName($_) })
Assert-Eq ($uj -join ',') 'yedek-20261112-161151.jsonl,yedek-20261021-092321.jsonl,yedek-20261003-101434.jsonl' 'günlükler yeniden eskiye; geri alınmışlar ve başka dosyalar yok'
Assert-Eq @(Get-UndoableJournals (Join-Path $jd 'yok')).Count 0 'klasör yoksa boş liste'
Remove-Item -LiteralPath $jd -Recurse -Force -ErrorAction SilentlyContinue

Show-Result
