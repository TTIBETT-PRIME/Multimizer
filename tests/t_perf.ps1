. "$PSScriptRoot/lib.ps1"
# 7.1: Güç, Oyun, Sıkıştırma, Akıllı temizlik, Akıllı bakım (kurallar), genişletilmiş katalog, yeni ekranların bağlantıları

Import-Fn 'Get-PwDef', 'Get-PwList', 'Get-PwActive', 'Find-PwScheme', 'Get-PwName', 'Get-PwValue', 'Get-PwSnapshot', 'Format-PwValue', 'Compare-PwSnapshot',
    'Get-PwSafeName', 'Get-PwUniqueName', 'New-PwBuiltin', 'Invoke-PowerSetOp', 'Invoke-PowerCustomOp', 'Undo-PowerNewItem', 'Invoke-PowerDeleteOp', 'Undo-PowerDelItem',
    'Limit-PwPct', 'Invoke-PowerCpuMaxOp', 'Undo-PowerCpuMaxItem', 'New-PowerSetSteps', 'New-PowerCustomSteps', 'Job_PowerPreview', 'Job_PowerInfo', 'Get-PwLive', 'Get-PwBatteryWear', 'Job_PowerStates'
function Test-PwUseMode([string]$PlanKey) { return $false }   # bu testte klasik güç planı yolu sınanır (Modern Bekleme yolu: t_realfix)
Import-Fn 'Format-Percent', 'Convert-LangPercent', 'Tr', 'Format-Tr'
$script:LangPctStyle = 0; $script:LangOn = $false
Import-Fn 'Get-GmSteamLibraries', 'Get-GmSteamGames', 'Get-GmEpicGames', 'Get-GmGogGames', 'Find-GmMainExe', 'Job_GameScan', 'Get-GmFlags', 'Get-GmRunning', 'Test-GmExePath',
    'Invoke-GameFlagsOp', 'New-GameFlagSteps', 'Job_GameBoost', 'Merge-DxGlobal', 'Invoke-DxGlobalOp', 'DxGlobalOp'
Import-Fn 'Clear-FileList', 'Remove-FilesSafe', 'Get-FilesSafe', 'Remove-EmptyDirs', 'Clear-Folders', 'Format-Size', 'Invoke-CleanShader', 'Invoke-CleanThumbs', 'Invoke-CleanRecent', 'Invoke-CleanPrefetch',
    'Invoke-CleanAppCaches', 'Invoke-CleanSetupLogs', 'Get-CapList', 'Read-CapListFresh', 'Test-CapOn', 'Start-StateBatch', 'Stop-StateBatch', 'Invoke-CapOp', 'Undo-CapItem', 'CapOp', 'NetLatencyOp'
Import-Fn 'Test-CompressAllowed', 'Get-CpEstimate', 'Get-CpDriveFree', 'Invoke-CompactExe', 'Invoke-CompressOp', 'Undo-CompressItem', 'Get-CompactOsState', 'Invoke-CompactOsOp', 'Undo-CompactOsItem',
    'New-CompressSteps', 'Job_CompressEstimate', 'Job_CompressScan', 'Get-DirSizeFast'
Import-Fn 'Get-ThermalTemp', 'New-AuRule', 'Get-AuRuleText', 'Test-AuRule', 'Get-BoostTargets', 'Get-PrivacyShieldIds', 'Get-CatalogFor', 'Test-OsOk', 'Test-WhenOk', 'Get-CatalogItem',
    'Job_TweakStateIds', 'Add-LifeRow'
Import-Fn 'RegOp', 'RegDel', 'FuncOp', 'FeatOp', 'SvcOp', 'TaskOp', 'Add-Tweak', 'Test-RegWriteBlocked', 'Resolve-RegPath', 'Get-TargetSid'
Import-Var 'ThermAcpiRetryAt', 'GuidRx', 'PwKnown', 'PwSet', 'PwTemplates', 'GmBadExe', 'GmSkipApp', 'GmFsoFlag', 'GmGpuKey', 'GmLayersKey', 'CpAlgos', 'CpSkipExt', 'CpBinExt', 'CpTextExt',
    'AuWhen', 'AuDo', 'AuTemplates', 'CriticalProcs', 'RegDenyPath', 'RegDenyName'

$script:Log = New-Object System.Collections.ArrayList
$script:Jr = New-Object System.Collections.ArrayList
function Write-WhLog { param([string]$Message, [string]$Level = 'INFO') [void]$script:Log.Add($Level + '|' + $Message) }
function Write-LogFile { param($Line) }
function Add-Plan([string]$Message) { $script:Changes++; [void]$script:Log.Add('PLAN|' + $Message) }
function Add-Done([string]$Message) { $script:Changes++; [void]$script:Log.Add('OK|' + $Message) }
function Add-Skip([string]$Message) { $script:Skipped++; [void]$script:Log.Add('SKIP|' + $Message) }
function Add-Err([string]$Message) { $script:Errors++; [void]$script:Log.Add('ERR|' + $Message) }
function Add-Journal($Item) { [void]$script:Jr.Add($Item) }
function Log-Has([string]$Needle) { foreach ($l in $script:Log) { if ($l.Contains($Needle)) { return $true } }; return $false }
function Reset-T { $script:Log.Clear(); $script:Jr.Clear(); $script:Changes = 0; $script:Skipped = 0; $script:Errors = 0; $script:FreedBytes = 0.0 }
function Test-JobCancel { return $false }
function Set-JobProgress { param($a, $b, $c) }
function Step-JobProgress { param($a) }
$sync = @{ BackupDir = [System.IO.Path]::GetTempPath(); ReportDir = [System.IO.Path]::GetTempPath(); Profile = @{ WinMajor = '11'; IsLaptop = $true; DiskType = 'SSD' }; TargetSid = '' }
$script:MoreOps = @{}; $script:MoreUndo = @{}; $script:ExtraActions = @{}; $script:FuncOps = @{}

# ======================= 1) GÜÇ =======================
# sahte powercfg: planlar, değerler ve çağrı kaydı
$script:PcCalls = New-Object System.Collections.ArrayList
$script:PcPlans = [ordered]@{ '381b4222-f694-41f0-9685-ff5bb260df2e' = 'Dengeli'; '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c' = 'Yüksek performans'; 'aaaaaaaa-1111-2222-3333-444444444444' = 'Benim planım' }
$script:PcActive = '381b4222-f694-41f0-9685-ff5bb260df2e'
$script:PcVals = @{}
$script:PcDupFail = $false
function global:powercfg.exe {
    $a = @($args | ForEach-Object { [string]$_ })
    [void]$script:PcCalls.Add(($a -join ' '))
    $global:LASTEXITCODE = 0
    switch ($a[0]) {
        '/list' {
            'Mevcut Güç Düzenleri'
            '-----------------------------------'
            foreach ($g in $script:PcPlans.Keys) { $star = ''; if ($g -eq $script:PcActive) { $star = ' *' }; ('Güç Düzeni GUID''si: ' + $g + '  (' + $script:PcPlans[$g] + ')' + $star) }
        }
        '/getactivescheme' { ('Güç Düzeni GUID''si: ' + $script:PcActive + '  (' + $script:PcPlans[$script:PcActive] + ')') }
        '/query' {
            $k = $a[1] + '|' + $a[3]
            $v = @(10, 20)
            if ($script:PcVals.ContainsKey($k)) { $v = $script:PcVals[$k] }
            ('Güç Ayarı GUID''si: ' + $a[3] + '  (bir ayar)')
            '  Olası En Küçük Ayar: 0x00000000'
            '  Olası En Büyük Ayar: 0x00000064'
            '  Olası Ayarlar artışı: 0x00000001'
            ('  Geçerli AC Güç Ayarı Dizini: 0x' + ('{0:x8}' -f [int64]$v[0]))
            ('  Geçerli DC Güç Ayarı Dizini: 0x' + ('{0:x8}' -f [int64]$v[1]))
        }
        '/setactive' { if ($script:PcPlans.Contains($a[1])) { $script:PcActive = $a[1] } else { $global:LASTEXITCODE = 1 } }
        '/duplicatescheme' {
            if ($script:PcDupFail) { $global:LASTEXITCODE = 1; 'Hata: desteklenmiyor'; return }
            $new = 'bbbbbbbb-1111-2222-3333-' + ('{0:d12}' -f $script:PcCalls.Count)
            if ($a.Count -ge 3) { $new = $a[2] }
            $script:PcPlans[$new] = ('Kopya ' + $script:PcPlans[$a[1]])
            ('Güç Düzeni GUID''si: ' + $new + '  (' + $script:PcPlans[$new] + ')')
        }
        '/changename' { if ($script:PcPlans.Contains($a[1])) { $script:PcPlans[$a[1]] = $a[2] } }
        '/setacvalueindex' { $k = $a[1] + '|' + $a[3]; $o = @(0, 0); if ($script:PcVals.ContainsKey($k)) { $o = $script:PcVals[$k] }; $script:PcVals[$k] = @([int64]$a[4], $o[1]) }
        '/setdcvalueindex' { $k = $a[1] + '|' + $a[3]; $o = @(0, 0); if ($script:PcVals.ContainsKey($k)) { $o = $script:PcVals[$k] }; $script:PcVals[$k] = @($o[0], [int64]$a[4]) }
        '/delete' { $script:PcPlans.Remove($a[1]) }
        '/export' { [System.IO.File]::WriteAllText($a[1], 'pow') }
        '/import' { $script:PcPlans[$a[2]] = 'geri gelen' }
    }
}

$l = @(Get-PwList)
Assert-Eq $l.Count 3 'powercfg /list Türkçe çıktısı: 3 plan'
Assert-Eq @($l | Where-Object { $_.Active }).Count 1 'tek etkin plan'
Assert-Eq ([string]($l | Where-Object { $_.Active }).Name) 'Dengeli' 'etkin plan adı parantez içinden'
$a = Get-PwActive
Assert-Eq $a.Guid '381b4222-f694-41f0-9685-ff5bb260df2e' 'etkin plan GUID'
Assert-Eq (Find-PwScheme 'High' $l).Name 'Yüksek performans' 'bilinen GUID ile bulunur'
Assert-True ($null -eq (Find-PwScheme 'Ultimate' $l)) 'olmayan plan $null'
$l2 = @($l) + @(@{ Guid = 'cccccccc-0000-0000-0000-000000000000'; Name = 'Nihai Performans'; Active = $false })
Assert-Eq (Find-PwScheme 'Ultimate' $l2).Guid 'cccccccc-0000-0000-0000-000000000000' 'rastgele GUID ile kopyalanmış Nihai plan adından bulunur'
$cpuMax = Get-PwDef 'CpuMax'
$script:PcVals[('381b4222-f694-41f0-9685-ff5bb260df2e|' + $cpuMax.Id)] = @(100, 80)
$v = Get-PwValue '381b4222-f694-41f0-9685-ff5bb260df2e' $cpuMax
Assert-Eq ([string]$v.Ac + '/' + [string]$v.Dc) '100/80' 'AC/DC değeri dilden bağımsız okunur (son iki onaltılık)'
$snap = Get-PwSnapshot '381b4222-f694-41f0-9685-ff5bb260df2e'
Assert-Eq $snap.Count $script:PwSet.Count 'görüntüde her ayar var'
Assert-Eq (Format-PwValue (Get-PwDef 'Display') 0) 'Hiçbir zaman' '0 sn = hiçbir zaman'
Assert-Eq (Format-PwValue (Get-PwDef 'Display') 600) '10 dk' '600 sn = 10 dk'
Assert-Eq (Format-PwValue (Get-PwDef 'Sleep') 7200) '2 sa' '7200 sn = 2 sa'
Assert-Eq (Format-PwValue (Get-PwDef 'Boost') 2) 'Agresif' 'seçenek adı'
Assert-Eq (Format-PwValue (Get-PwDef 'CpuMin') 5) '%5' 'yüzde'
$d = @(Compare-PwSnapshot @{ CpuMax = @{ Ac = 100; Dc = 100 } } @{ CpuMax = @{ Ac = 80; Dc = 100 }; Display = @{ Ac = 60; Dc = 60 } })
Assert-Eq $d.Count 2 'fark: değişen ve yeni ayar'
Assert-True ($d[0].Parts -match 'fişte: %100 → %80' -and $d[0].Parts -notmatch 'pilde') 'yalnızca değişen taraf yazılır'
Assert-Eq (Get-PwSafeName '  Oyun "plan"; & del  ') 'Oyun plan  del' 'plan adındaki tehlikeli karakterler atılır'
Assert-Eq (Get-PwSafeName '') 'Özel plan' 'boş ad'
Assert-Eq (Get-PwUniqueName 'Benim planım' $l) 'Benim planım (2)' 'aynı adlı plan varsa numaralanır'

# plan değiştirme: önizleme değiştirmez, uygulama günlüğe yazar
Reset-T; $script:Preview = $true; $script:PcCalls.Clear()
Invoke-PowerSetOp @{ T = 'PowerSet'; Key = 'High' }
Assert-True (Log-Has 'Güç planı: Dengeli → Yüksek performans') 'önizleme satırı'
Assert-True (Log-Has 'İşlemci en yüksek durumu') 'önizleme farkları listelenir'
Assert-Eq @($script:PcCalls | Where-Object { $_ -match '^/setactive' }).Count 0 'önizlemede plan değişmez'
Assert-Eq $script:PcActive '381b4222-f694-41f0-9685-ff5bb260df2e' 'önizlemede etkin plan aynı'
Reset-T; $script:Preview = $false
Invoke-PowerSetOp @{ T = 'PowerSet'; Key = 'High' }
Assert-Eq $script:PcActive '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c' 'uygulama planı değiştirir'
Assert-Eq $script:Jr.Count 1 'günlüğe bir kayıt'
Assert-Eq ([string]$script:Jr[0].T + ':' + [string]$script:Jr[0].Guid) 'Power:381b4222-f694-41f0-9685-ff5bb260df2e' 'önceki plan kaydedilir (mevcut Power geri alması kullanılır)'
Reset-T
Invoke-PowerSetOp @{ T = 'PowerSet'; Key = 'High' }
Assert-True (Log-Has 'zaten') 'zaten etkinse atlanır'
Assert-Eq $script:Jr.Count 0 'atlanınca günlük yazılmaz'
# Nihai: yoksa yerleşik şablondan oluşturulur (aynı GUID ile)
Reset-T
Invoke-PowerSetOp @{ T = 'PowerSet'; Key = 'Ultimate' }
Assert-Eq $script:PcActive 'e9a42b02-d5df-448d-aa00-03f14749eb61' 'Nihai plan oluşturulup etkinleşir'
Assert-True (@($script:PcCalls | Where-Object { $_ -eq '/duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 e9a42b02-d5df-448d-aa00-03f14749eb61' }).Count -eq 1) 'yerleşik GUID ile kopyalanır'
# Oyun kipi (Best): Nihai oluşturulamazsa Yüksek performans
$script:PcPlans.Remove('e9a42b02-d5df-448d-aa00-03f14749eb61'); $script:PcActive = '381b4222-f694-41f0-9685-ff5bb260df2e'
$script:PcDupFail = $true
Reset-T
Invoke-PowerSetOp @{ T = 'PowerSet'; Key = 'Best' }
Assert-Eq $script:PcActive '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c' 'Nihai desteklenmiyorsa Yüksek performansa geçilir'
Reset-T
$err = ''
try { Invoke-PowerSetOp @{ T = 'PowerSet'; Key = 'Ultimate' } } catch { $err = $_.Exception.Message }
Assert-True ($err -match 'oluşturulamadı') 'Nihai oluşturulamazsa açık hata'
$script:PcDupFail = $false
$script:PcActive = '381b4222-f694-41f0-9685-ff5bb260df2e'

# özel plan
Reset-T; $script:Preview = $true
Invoke-PowerCustomOp @{ T = 'PowerCustom'; Name = 'Oyun'; Base = 'High'; Values = @{ CpuMin = @{ Ac = 100; Dc = 50 }; Display = @{ Ac = 1800; Dc = $null } }; Activate = $true }
Assert-True (Log-Has 'Özel güç planı oluşturulacak: “Oyun”') 'özel plan önizlemesi'
Assert-True (Log-Has 'fişte %100, pilde %50') 'özel değerler önizlemede'
Assert-True (Log-Has 'Ekranı kapatma süresi: fişte 30 dk') 'yalnızca verilen taraf yazılır'
Assert-Eq @($script:PcCalls | Where-Object { $_ -match '^/duplicatescheme' -and $_ -notmatch 'e9a42b02' }).Count 0 'önizlemede plan kopyalanmaz'
Reset-T; $script:Preview = $false; $script:PcCalls.Clear()
Invoke-PowerCustomOp @{ T = 'PowerCustom'; Name = 'Oyun'; Base = 'High'; Values = @{ CpuMin = @{ Ac = 100; Dc = 50 }; Display = @{ Ac = 1800; Dc = $null } }; Activate = $true }
$newG = [string]$script:Jr[0].Guid
Assert-Eq ([string]$script:Jr[0].T) 'PowerNew' 'yeni plan günlüğe yazılır'
Assert-Eq ([string]$script:Jr[0].Prev) '381b4222-f694-41f0-9685-ff5bb260df2e' 'önceki etkin plan kaydedilir'
Assert-Eq $script:PcActive $newG 'yeni plan etkin'
Assert-Eq $script:PcPlans[$newG] 'Oyun' 'plan adı verildi'
$cpuMin = Get-PwDef 'CpuMin'
Assert-Eq ($script:PcVals[$newG + '|' + $cpuMin.Id] -join '/') '100/50' 'fişte ve pilde değer yazıldı'
Assert-Eq @($script:PcCalls | Where-Object { $_ -match '^/setdcvalueindex .* 3c0bc021' }).Count 0 'boş bırakılan taraf (pilde ekran) yazılmaz'
$newItem = $script:Jr[0]
Reset-T
Undo-PowerNewItem $newItem
Assert-True ($null -eq $script:PcPlans[$newG]) 'geri almada oluşturulan plan silinir'
Assert-Eq $script:PcActive '381b4222-f694-41f0-9685-ff5bb260df2e' 'geri almada önceki plana dönülür'
# silme: yerleşik plan silinmez, özel plan dışa aktarılıp silinir, geri getirilir
Reset-T
Invoke-PowerDeleteOp @{ T = 'PowerDelete'; Guid = '381b4222-f694-41f0-9685-ff5bb260df2e' }
Assert-True (Log-Has 'yerleşik planları silinmez') 'yerleşik plan silinmez'
Assert-True ($script:PcPlans.Contains('381b4222-f694-41f0-9685-ff5bb260df2e')) 'Dengeli yerinde'
$script:PcActive = 'aaaaaaaa-1111-2222-3333-444444444444'
Reset-T
Invoke-PowerDeleteOp @{ T = 'PowerDelete'; Guid = 'aaaaaaaa-1111-2222-3333-444444444444' }
Assert-True (-not $script:PcPlans.Contains('aaaaaaaa-1111-2222-3333-444444444444')) 'özel plan silindi'
Assert-Eq $script:PcActive '381b4222-f694-41f0-9685-ff5bb260df2e' 'silinen plan etkinse Dengeli plana geçilir'
Assert-True (Test-Path -LiteralPath ([string]$script:Jr[0].File)) 'silmeden önce dışa aktarım dosyası yazılır'
Undo-PowerDelItem $script:Jr[0]
Assert-True ($script:PcPlans.Contains('aaaaaaaa-1111-2222-3333-444444444444')) 'geri almada plan aynı GUID ile geri gelir'
Assert-Eq $script:PcActive 'aaaaaaaa-1111-2222-3333-444444444444' 'geri almada yeniden etkin'
Remove-Item -LiteralPath ([string]$script:Jr[0].File) -Force -ErrorAction SilentlyContinue
# işlemci üst sınırı (ısı yönetimi)
$script:PcActive = '381b4222-f694-41f0-9685-ff5bb260df2e'
$script:PcVals[('381b4222-f694-41f0-9685-ff5bb260df2e|' + $cpuMax.Id)] = @(100, 90)
Reset-T
Invoke-PowerCpuMaxOp @{ T = 'PowerCpuMax'; Value = 80 }
Assert-Eq ($script:PcVals[('381b4222-f694-41f0-9685-ff5bb260df2e|' + $cpuMax.Id)] -join '/') '80/80' 'üst sınır %80'
Assert-Eq ([string]$script:Jr[0].Ac + '/' + [string]$script:Jr[0].Dc) '100/90' 'eski değerler kaydedildi'
Reset-T
Invoke-PowerCpuMaxOp @{ T = 'PowerCpuMax'; Value = 5 }
Assert-Eq ($script:PcVals[('381b4222-f694-41f0-9685-ff5bb260df2e|' + $cpuMax.Id)] -join '/') '30/30' 'en az %30 (bilgisayar kilitlenmesin)'
Undo-PowerCpuMaxItem @{ T = 'PowerCpuMax'; Guid = '381b4222-f694-41f0-9685-ff5bb260df2e'; Ac = 100; Dc = 90 }
Assert-Eq ($script:PcVals[('381b4222-f694-41f0-9685-ff5bb260df2e|' + $cpuMax.Id)] -join '/') '100/90' 'geri alma eski değere döner'
Reset-T
Invoke-PowerCpuMaxOp @{ T = 'PowerCpuMax'; Ac = 100; Dc = 90 }
Assert-True (Log-Has 'zaten') 'aynı değerse atlanır'
# önizleme işi
$r = Job_PowerPreview @{ Key = 'High' }
Assert-True ($r.Diff.Count -ge 0 -and $r.Note -eq '') 'var olan plan önizlemesi notsuz'
$r = Job_PowerPreview @{ Key = 'Saver' }
Assert-True ($r.Note -match 'henüz yok') 'olmayan plan için not'
$r = Job_PowerPreview @{ Base = 'High'; Values = @{ CpuMax = @{ Ac = 70; Dc = $null } } }
Assert-True (@($r.Diff | Where-Object { $_.K -eq 'CpuMax' }).Count -eq 1) 'özel değer farkı'
# adımlar
$st = @(New-PowerSetSteps 'Ultimate')
Assert-Eq $st[0].Title 'Güç planı: Nihai performans' 'adım başlığı bilinen ad'
Assert-Eq (@(New-PowerSetSteps 'Best')[0].Title) 'Güç planı: Nihai performans' 'oyun kipi adımı'
Assert-Eq (@(New-PowerSetSteps 'aaaa' 'Benim planım')[0].Title) 'Güç planı: Benim planım' 'verilen etiket kullanılır'
$cs = @(New-PowerCustomSteps 'x"y' 'Balanced' @{ CpuMax = @{ Ac = 80; Dc = 80 } } $true)
Assert-Eq $cs[0].Ops[0].T 'PowerCustom' 'özel plan adımı'
# şablonlar: her değer oluşturucu seçenekleri arasında bulunmalı (yoksa şablon yüklenince değer kaybolur)
foreach ($tk in $script:PwTemplates.Keys) {
    foreach ($k in @($script:PwTemplates[$tk]['Values'].Keys)) {
        $df = Get-PwDef $k
        Assert-True ($null -ne $df) ('şablon ayarı bilinir: ' + $tk + '.' + $k)
    }
}

# ======================= 2) OYUN =======================
$root = Join-Path ([System.IO.Path]::GetTempPath()) ('mm-gm-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root -Force | Out-Null
try {
    $steam = Join-Path $root 'Steam'; $lib2 = Join-Path $root 'Lib2'
    foreach ($d in @((Join-Path $steam 'steamapps/common/Oyun A/bin'), (Join-Path $lib2 'steamapps/common/OyunB'), (Join-Path $steam 'steamapps/common/Steamworks Shared'))) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    [System.IO.File]::WriteAllText((Join-Path $steam 'steamapps/libraryfolders.vdf'), ('"libraryfolders"' + "`n{`n" + ' "0" { "path" "' + $steam.Replace('\', '\\') + '" }' + "`n" + ' "1" { "path" "' + $lib2.Replace('\', '\\') + '" }' + "`n}"))
    [System.IO.File]::WriteAllText((Join-Path $steam 'steamapps/appmanifest_1.acf'), '"AppState" { "appid" "1" "name" "Oyun A" "installdir" "Oyun A" "SizeOnDisk" "5000" }')
    [System.IO.File]::WriteAllText((Join-Path $lib2 'steamapps/appmanifest_2.acf'), '"AppState" { "appid" "2" "name" "Oyun B" "installdir" "OyunB" }')
    [System.IO.File]::WriteAllText((Join-Path $steam 'steamapps/appmanifest_3.acf'), '"AppState" { "appid" "228980" "name" "Steamworks Common Redistributables" "installdir" "Steamworks Shared" }')
    [System.IO.File]::WriteAllBytes((Join-Path $steam 'steamapps/common/Oyun A/bin/OyunA.exe'), (New-Object byte[] 5000))
    [System.IO.File]::WriteAllBytes((Join-Path $steam 'steamapps/common/Oyun A/unins000.exe'), (New-Object byte[] 90000))
    [System.IO.File]::WriteAllBytes((Join-Path $steam 'steamapps/common/Oyun A/UnityCrashHandler64.exe'), (New-Object byte[] 80000))
    $script:FakeReg = @{ 'HKLM\SOFTWARE\WOW6432Node\Valve\Steam|InstallPath' = $steam }
    function global:Get-RegValue([string]$Path, [string]$Name, $Default = $null) { $k = $Path + '|' + $Name; if ($script:FakeReg.ContainsKey($k)) { return $script:FakeReg[$k] }; return $Default }
    $libs = @(Get-GmSteamLibraries)
    Assert-Eq $libs.Count 2 'Steam kitaplıkları libraryfolders.vdf içinden'
    $g = @(Get-GmSteamGames)
    Assert-Eq $g.Count 2 'iki oyun (Steamworks gibi araçlar atlanır)'
    Assert-Eq ([string]($g | Where-Object { $_.Name -eq 'Oyun A' }).Size) '5000' 'boyut manifestten'
    $exe = Find-GmMainExe ([string]($g | Where-Object { $_.Name -eq 'Oyun A' }).Dir) ''
    Assert-True ($exe -like '*OyunA.exe') ('ana exe: kaldırıcı ve çökme aracı seçilmez -> ' + $exe)
    # Epic
    $epicDir = Join-Path $root 'EpicGame'; New-Item -ItemType Directory -Path $epicDir -Force | Out-Null
    [System.IO.File]::WriteAllBytes((Join-Path $epicDir 'Game.exe'), (New-Object byte[] 100))
    $man = Join-Path $root 'ProgramData/Epic/EpicGamesLauncher/Data/Manifests'; New-Item -ItemType Directory -Path $man -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $man 'x.item'), (@{ DisplayName = 'Epic Oyun'; InstallLocation = $epicDir; LaunchExecutable = 'Game.exe'; InstallSize = 123 } | ConvertTo-Json))
    $oldPd = $env:ProgramData; $env:ProgramData = (Join-Path $root 'ProgramData')
    $eg = @(Get-GmEpicGames)
    $env:ProgramData = $oldPd
    Assert-Eq $eg.Count 1 'Epic manifestinden oyun'
    Assert-True ([string]$eg[0].Exe -like '*Game.exe') 'Epic çalıştırılabilir dosyası'
    # tarama işi: elle eklenen + tekrar yok
    function global:Get-GmEpicGames { }
    function global:Get-GmGogGames { }
    $custom = Join-Path $root 'Elle/oyun.exe'; New-Item -ItemType Directory -Path (Split-Path $custom) -Force | Out-Null; [System.IO.File]::WriteAllBytes($custom, (New-Object byte[] 10))
    $r = Job_GameScan @{ Custom = @(@{ Name = 'Elle Oyun'; Exe = $custom }, @{ Name = 'yok'; Exe = (Join-Path $root 'yok.exe') }) }
    Assert-Eq @($r.Games).Count 3 'Steam 2 + elle 1 (olmayan dosya atlanır)'
    Assert-True (@($r.Games | Where-Object { $_.Store -eq 'Elle' }).Count -eq 1) 'elle eklenen işaretli'
    Assert-True ($null -ne @($r.Games)[0].Flags) 'oyun ayarı durumu okunur'
    # çalışan oyun algısı
    $gdir = [string]($g | Where-Object { $_.Name -eq 'Oyun A' }).Dir
    function global:Get-Process { param($Id, $ErrorAction) if ($null -ne $Id) { return [pscustomobject]@{ Id = $Id; ProcessName = 'oyuna'; PriorityClass = 'Normal' } }; return @([pscustomobject]@{ Id = 11; ProcessName = 'oyuna'; Path = (Join-Path $gdir 'bin/OyunA.exe') }, [pscustomobject]@{ Id = 12; ProcessName = 'explorer'; Path = 'C:\Windows\explorer.exe' }) }
    $run = @(Get-GmRunning @(@{ Name = 'Oyun A'; Dir = $gdir }, @{ Name = 'Oyun B'; Dir = (Join-Path $lib2 'steamapps/common/OyunB') }))
    Assert-Eq $run.Count 1 'yalnızca oyun klasöründeki işlem'
    Assert-Eq ([string]$run[0].Name + ':' + [string]$run[0].Pid) 'Oyun A:11' 'çalışan oyun ve işlem numarası'
    Assert-Eq @(Get-GmRunning @()).Count 0 'oyun listesi boşsa işlem taranmaz'
    Remove-Item function:\global:Get-Process
    # oyun başına ayar: yalnızca HKCU grafik/uyumluluk değerleri
    $script:RegOps = New-Object System.Collections.ArrayList
    function global:Invoke-RegOp($Op) { [void]$script:RegOps.Add($Op) }
    function global:Test-GmExePath([string]$Exe) { return $true }
    $script:FakeReg[$script:GmLayersKey + '|C:\G\g.exe'] = '~ RUNASADMIN'
    Reset-T
    Invoke-GameFlagsOp @{ T = 'GameFlags'; Exe = 'C:\G\g.exe'; Gpu = $true; Fso = $true }
    Assert-Eq $script:RegOps.Count 2 'iki kayıt değeri'
    Assert-Eq ([string]$script:RegOps[0].Path + '|' + [string]$script:RegOps[0].Value) 'HKCU\Software\Microsoft\DirectX\UserGpuPreferences|GpuPreference=2;' 'yüksek performanslı GPU tercihi'
    Assert-Eq ([string]$script:RegOps[1].Value) '~ RUNASADMIN DISABLEDXMAXIMIZEDWINDOWEDMODE' 'var olan uyumluluk bayrağı korunur'
    $script:RegOps.Clear()
    $script:FakeReg[$script:GmLayersKey + '|C:\G\g.exe'] = '~ RUNASADMIN DISABLEDXMAXIMIZEDWINDOWEDMODE'
    Invoke-GameFlagsOp @{ T = 'GameFlags'; Exe = 'C:\G\g.exe'; Gpu = $false; Fso = $false }
    Assert-True ($script:RegOps[0].Del -eq $true) 'GPU tercihi kaldırılır'
    Assert-Eq ([string]$script:RegOps[1].Value) '~ RUNASADMIN' 'yalnızca kendi bayrağımız çıkarılır'
    $script:RegOps.Clear()
    $script:FakeReg[$script:GmLayersKey + '|C:\G\g.exe'] = '~ DISABLEDXMAXIMIZEDWINDOWEDMODE'
    Invoke-GameFlagsOp @{ T = 'GameFlags'; Exe = 'C:\G\g.exe'; Gpu = $null; Fso = $false }
    Assert-Eq $script:RegOps.Count 1 'GPU dokunulmaz (null)'
    Assert-True ($script:RegOps[0].Del -eq $true) 'tek bayrak kalmayınca değer silinir'
    $script:FakeReg[$script:GmGpuKey + '|C:\G\g.exe'] = 'GpuPreference=2;'
    $f = Get-GmFlags 'C:\G\g.exe'
    Assert-True ($f.Gpu -and $f.Fso) 'durum okunur'
    Remove-Item function:\global:Test-GmExePath
    Import-Fn 'Test-GmExePath'
    Assert-True (-not (Test-GmExePath 'C:\x\"a.exe')) 'tırnaklı yol reddedilir'
    Assert-True (-not (Test-GmExePath 'C:\x\a.bat')) 'exe olmayan reddedilir'
    Assert-True (-not (Test-GmExePath 'relative\a.exe')) 'göreli yol reddedilir'
    # DirectX genel ayarları birleştirme
    Assert-Eq (Merge-DxGlobal 'AutoHDREnable=1;SwapEffectUpgradeEnable=0;' @{ SwapEffectUpgradeEnable = '1'; VRROptimizeEnable = '1' }) 'AutoHDREnable=1;SwapEffectUpgradeEnable=1;VRROptimizeEnable=1;' 'diğer DirectX ayarları korunur'
    Assert-Eq (Merge-DxGlobal '' @{ VRROptimizeEnable = '1' }) 'VRROptimizeEnable=1;' 'boştan oluşturma'
    $script:RegOps.Clear()
    $script:FakeReg[$script:GmGpuKey + '|DirectXUserGlobalSettings'] = 'AutoHDREnable=1;'
    Invoke-DxGlobalOp (DxGlobalOp @{ VRROptimizeEnable = '1' })
    Assert-Eq ([string]$script:RegOps[0].Value) 'AutoHDREnable=1;VRROptimizeEnable=1;' 'işlem birleştirilmiş değeri yazar'
    Remove-Item function:\global:Invoke-RegOp
    Remove-Item function:\global:Get-RegValue
} finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }

# ======================= 3) AKILLI TEMİZLİK EKLERİ =======================
$root = Join-Path ([System.IO.Path]::GetTempPath()) ('mm-cl-' + [guid]::NewGuid().ToString('N'))
try {
    $la = Join-Path $root 'Local'; $ap = Join-Path $root 'Roaming'
    foreach ($d in @('D3DSCache/a', 'NVIDIA/DXCache', 'NVIDIA/Kalsin', 'Microsoft/Windows/Explorer', 'Steam/htmlcache')) { New-Item -ItemType Directory -Path (Join-Path $la $d) -Force | Out-Null }
    foreach ($d in @('Microsoft/Windows/Recent/AutomaticDestinations', 'discord/Cache', 'discord/Local Storage')) { New-Item -ItemType Directory -Path (Join-Path $ap $d) -Force | Out-Null }
    $files = @{
        'Local/D3DSCache/a/s.bin' = 100; 'Local/NVIDIA/DXCache/x.bin' = 200; 'Local/NVIDIA/Kalsin/ayar.txt' = 50
        'Local/Microsoft/Windows/Explorer/thumbcache_256.db' = 300; 'Local/Microsoft/Windows/Explorer/iconcache_16.db' = 40; 'Local/Microsoft/Windows/Explorer/ExplorerStartupLog.etl' = 10
        'Roaming/Microsoft/Windows/Recent/belge.docx.lnk' = 5; 'Roaming/Microsoft/Windows/Recent/AutomaticDestinations/f01b4d95cf55d32a.automaticDestinations-ms' = 7
        'Roaming/discord/Cache/data_0' = 70; 'Roaming/discord/Local Storage/leveldb.ldb' = 9; 'Local/Steam/htmlcache/c' = 11
    }
    foreach ($k in $files.Keys) { [System.IO.File]::WriteAllBytes((Join-Path $root $k), (New-Object byte[] $files[$k])) }
    function global:Get-TargetProfile { return @{ LocalAppData = $la; AppData = $ap; Home = $root; Temp = $root } }
    $oldPd = $env:ProgramData; $env:ProgramData = (Join-Path $root 'PD')
    Reset-T; $script:Preview = $true
    Invoke-CleanShader
    Assert-Eq ([double]$script:LastClean.Bytes) 300 'önizleme: yalnızca gölgelendirici önbellekleri sayılır'
    Assert-True (Test-Path (Join-Path $root 'Local/NVIDIA/DXCache/x.bin')) 'önizlemede silinmez'
    $script:Preview = $false
    Invoke-CleanShader
    Assert-True (-not (Test-Path (Join-Path $root 'Local/NVIDIA/DXCache/x.bin'))) 'DXCache temizlendi'
    Assert-True (Test-Path (Join-Path $root 'Local/NVIDIA/Kalsin/ayar.txt')) 'NVIDIA altındaki başka klasöre dokunulmaz'
    Invoke-CleanThumbs
    Assert-True (-not (Test-Path (Join-Path $root 'Local/Microsoft/Windows/Explorer/thumbcache_256.db'))) 'küçük resim önbelleği silindi'
    Assert-True (Test-Path (Join-Path $root 'Local/Microsoft/Windows/Explorer/ExplorerStartupLog.etl')) 'Explorer klasöründeki başka dosyaya dokunulmaz'
    Invoke-CleanRecent
    Assert-True (-not (Test-Path (Join-Path $root 'Roaming/Microsoft/Windows/Recent/belge.docx.lnk'))) 'son kullanılan kısayolu silindi'
    Assert-True (Test-Path (Join-Path $root 'Roaming/Microsoft/Windows/Recent/AutomaticDestinations/f01b4d95cf55d32a.automaticDestinations-ms')) 'sabitlenmiş Hızlı erişim (atlama listeleri) korunur'
    Invoke-CleanAppCaches
    Assert-True (-not (Test-Path (Join-Path $root 'Roaming/discord/Cache/data_0'))) 'Discord önbelleği silindi'
    Assert-True (Test-Path (Join-Path $root 'Roaming/discord/Local Storage/leveldb.ldb')) 'Discord oturum verisi korunur'
    Assert-True (-not (Test-Path (Join-Path $root 'Local/Steam/htmlcache/c'))) 'Steam web önbelleği silindi'
    Assert-True ($script:FreedBytes -gt 0) 'açılan alan sayılır'
    $env:ProgramData = $oldPd
    Remove-Item function:\global:Get-TargetProfile
} finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
# Windows bileşenleri (Steps Recorder ...)
$script:CapState = @{ 'App.StepsRecorder~~~~0.0.1.0' = 'Installed'; 'MathRecognizer~~~~0.0.1.0' = 'NotPresent' }
$script:CapCalls = New-Object System.Collections.ArrayList
$script:CapReads = 0
function global:Get-WindowsCapability { param([switch]$Online, $ErrorAction) $script:CapReads++; foreach ($k in $script:CapState.Keys) { [pscustomobject]@{ Name = $k; State = $script:CapState[$k] } } }
function global:Remove-WindowsCapability { param([switch]$Online, $Name, $ErrorAction) [void]$script:CapCalls.Add('-' + $Name); $script:CapState[$Name] = 'NotPresent' }
function global:Add-WindowsCapability { param([switch]$Online, $Name, $ErrorAction) [void]$script:CapCalls.Add('+' + $Name); $script:CapState[$Name] = 'Installed' }
# değişiklik dism.exe ile yapılır (Set-WinCapabilityState; çıkış kodları ve kaynak sırası t_servis'te sınanır); burada günlük ve geri alma akışı sınanır
function global:Set-WinCapabilityState([string]$Name, [bool]$Present) { if ($Present) { Add-WindowsCapability -Online -Name $Name } else { Remove-WindowsCapability -Online -Name $Name }; return $false }
function global:Get-ServicingBusy { return $global:CapBusy }
$global:CapBusy = ''
$script:CapCache = $null
Reset-T; $script:Preview = $true
Invoke-CapOp (CapOp 'App.StepsRecorder')
Assert-True (Log-Has 'kaldırılacak: App.StepsRecorder~~~~0.0.1.0') 'bileşen önizlemesi'
Assert-Eq $script:CapCalls.Count 0 'önizlemede kaldırılmaz'
Reset-T; $script:Preview = $false
Invoke-CapOp (CapOp 'App.StepsRecorder')
Assert-Eq ($script:CapCalls -join ',') '-App.StepsRecorder~~~~0.0.1.0' 'bileşen kaldırıldı'
Assert-Eq ([string]$script:Jr[0].T + ':' + [string]$script:Jr[0].WasInstalled) 'Cap:True' 'günlüğe yazıldı'
Undo-CapItem $script:Jr[0]
Assert-Eq $script:CapState['App.StepsRecorder~~~~0.0.1.0'] 'Installed' 'geri alma bileşeni yeniden kurar'
# Windows Update meşgulken bileşen değiştirilmez ve günlüğe yazılmaz
Reset-T; $script:CapCache = $null; $script:CapCalls.Clear(); $global:CapBusy = 'Windows Update güncelleme kuruyor'
Invoke-CapOp (CapOp 'App.StepsRecorder')
Assert-Eq $script:CapCalls.Count 0 'meşgulken bileşen değiştirilmez'
Assert-Eq @($script:Jr).Count 0 'meşgulken günlüğe yazılmaz'
$global:CapBusy = ''
Reset-T; $script:CapCache = $null
Invoke-CapOp (CapOp 'MathRecognizer')
Assert-True (Log-Has 'zaten uygun') 'yüklü değilse atlanır'
Invoke-CapOp (CapOp 'Olmayan.Bilesen')
Assert-True (Log-Has 'bu sürümde yok') 'olmayan bileşen'
Invoke-CapOp (CapOp 'a;b')
Assert-True (Log-Has 'Geçersiz bileşen adı') 'geçersiz ad reddedilir'
# Bileşen durumu bayat okunmaz (cihazda 18.11.2026: kaldırmadan sonra doğrulama "tam uygulanamadı" diyordu)
$script:StateBatch = $null; $script:CapState['App.StepsRecorder~~~~0.0.1.0'] = 'Installed'
Reset-T; $script:Preview = $false
Invoke-CapOp (CapOp 'App.StepsRecorder')
$script:CapState['App.StepsRecorder~~~~0.0.1.0'] = 'UninstallPending'   # Windows yeniden başlatmayı bekliyor
Reset-T; $script:Preview = $true
Invoke-CapOp (CapOp 'App.StepsRecorder')
Assert-True ((Log-Has 'zaten uygun') -and -not (Log-Has 'kaldırılacak')) 'kaldırmadan hemen sonraki ölçüm tazedir; yeniden başlatma bekleyen kaldırma uygulanmış sayılır'
$script:CapState['App.StepsRecorder~~~~0.0.1.0'] = 'InstallPending'
Reset-T; $script:Preview = $true
Invoke-CapOp (CapOp 'App.StepsRecorder')
Assert-True (Log-Has 'kaldırılacak: App.StepsRecorder') 'yeniden başlatma bekleyen kurulum kurulu sayılır'
Reset-T; $script:Preview = $false; $script:CapCalls.Clear()
Invoke-CapOp (CapOp 'App.StepsRecorder' 'Installed')
Assert-True ((Log-Has 'zaten uygun') -and $script:CapCalls.Count -eq 0) 'bekleyen kurulum ikinci kez kurulmaz'
$script:CapState['App.StepsRecorder~~~~0.0.1.0'] = 'Installed'
Reset-T; $script:Preview = $true; $script:CapReads = 0
Invoke-CapOp (CapOp 'App.StepsRecorder'); Invoke-CapOp (CapOp 'MathRecognizer')
Assert-Eq $script:CapReads 2 'parti dışında her ölçüm listeyi yeniden okur'
$script:CapReads = 0
Start-StateBatch
try { Invoke-CapOp (CapOp 'App.StepsRecorder'); Invoke-CapOp (CapOp 'MathRecognizer'); Invoke-CapOp (CapOp 'App.StepsRecorder') } finally { Stop-StateBatch }
Assert-Eq $script:CapReads 1 'toplu ölçüm partisinde liste bir kez okunur'
Assert-True ($null -eq $script:StateBatch) 'parti bitince önbellek bırakılır'
$script:CapReads = 0; $script:Preview = $false
Start-StateBatch
try { Invoke-CapOp (CapOp 'MathRecognizer'); Invoke-CapOp (CapOp 'MathRecognizer') } finally { Stop-StateBatch }
Assert-Eq $script:CapReads 2 'gerçek uygulamada parti içinde de her okuma tazedir'
Assert-True ((Test-CapOn 'Installed') -and (Test-CapOn 'InstallPending') -and -not (Test-CapOn 'UninstallPending') -and -not (Test-CapOn 'NotPresent') -and -not (Test-CapOn '')) 'kurulu sayılan durumlar'
$script:Preview = $false

# ======================= 4) SIKIŞTIRMA =======================
foreach ($p in @('C:\', 'C:', 'C:\Windows', 'c:\windows\system32', 'C:\Windows\WinSxS', 'C:\Program Files\Windows Defender', 'C:\ProgramData\Microsoft\Windows Defender\Scans',
        'C:\Program Files\WindowsApps\Foo', 'C:\Users\ali', 'C:\Program Files', 'C:\Program Files (x86)', 'C:\ProgramData', 'C:\$Recycle.Bin', 'C:\System Volume Information', 'C:\Users\ali\OneDrive\Belgeler',
        'C:\Users\ali\AppData\Local\Packages\X', 'D:\Recovery', 'relative\path', '')) {
    Assert-True ((Test-CompressAllowed $p) -ne '') ('reddedilir: ' + $p)
}
$root = Join-Path ([System.IO.Path]::GetTempPath()) ('mm-cp-' + [guid]::NewGuid().ToString('N'))
try {
    foreach ($d in @('bin', 'data', 'media')) { New-Item -ItemType Directory -Path (Join-Path $root $d) -Force | Out-Null }
    [System.IO.File]::WriteAllBytes((Join-Path $root 'bin/game.exe'), (New-Object byte[] 1000))
    [System.IO.File]::WriteAllBytes((Join-Path $root 'data/a.json'), (New-Object byte[] 1000))
    [System.IO.File]::WriteAllBytes((Join-Path $root 'media/v.mp4'), (New-Object byte[] 1000))
    [System.IO.File]::WriteAllBytes((Join-Path $root 'x.zz'), (New-Object byte[] 1000))
    $e = Get-CpEstimate $root
    Assert-Eq ([string]$e.Bytes) '4000' 'toplam boyut'
    Assert-Eq ([string]$e.Skip) '1000' 'zaten sıkışık dosya (mp4) ayrı sayılır'
    Assert-Eq ([string]$e.Save) ([string]([math]::Round(0.38 * 1000 + 0.55 * 1000 + 0.22 * 1000, 0))) 'tahmini kazanç türlere göre'
    $e2 = Get-CpEstimate $root 2
    Assert-True ($e2.Cut -eq $true -and $e2.Files -eq 2) 'çok dosyalı klasörde ölçüm sınırı'
    # sıkıştırma işlemi: compact.exe çağrıları (alt klasör alt klasör), yöntem, günlük
    $script:Cx = New-Object System.Collections.ArrayList
    function global:compact.exe { [void]$script:Cx.Add((@($args | ForEach-Object { [string]$_ }) -join ' ')); $global:LASTEXITCODE = 0 }
    function global:Test-CompressAllowed([string]$Path) { return '' }
    $script:Free = 1000.0
    function global:Get-CpDriveFree([string]$Path) { $script:Free += 500.0; return $script:Free }
    Reset-T; $script:Preview = $true
    Invoke-CompressOp @{ T = 'Compress'; Path = $root; Algo = 'lzx'; Mode = 'compress' }
    Assert-True (Log-Has 'Klasör sıkıştırılacak') 'önizleme satırı'
    Assert-Eq $script:Cx.Count 0 'önizlemede compact çalışmaz'
    Reset-T; $script:Preview = $false
    Invoke-CompressOp @{ T = 'Compress'; Path = $root; Algo = 'lzx'; Mode = 'compress' }
    Assert-Eq $script:Cx.Count 4 'kök dosyalar + 3 alt klasör ayrı ayrı (iptal edilebilir)'
    Assert-True (@($script:Cx | Where-Object { $_ -match '/exe:lzx' }).Count -eq 4) 'yöntem her çağrıda'
    Assert-True (@($script:Cx | Where-Object { $_ -match '^/c /s:' }).Count -eq 3) 'alt klasörler /s ile'
    Assert-Eq ([string]$script:Jr[0].T) 'Compress' 'günlüğe yazıldı'
    Assert-True (Log-Has 'yer açıldı') 'gerçek kazanç boş alan farkından'
    $script:Cx.Clear(); Reset-T
    Invoke-CompressOp @{ T = 'Compress'; Path = $root; Algo = 'lznt1'; Mode = 'compress' }
    Assert-True (@($script:Cx | Where-Object { $_ -match '/exe' }).Count -eq 0) 'klasik NTFS yönteminde /exe yok'
    Assert-True ($script:Cx[0] -eq ('/c ' + $root + ' /i /q')) 'klasik yöntemde kök klasör de işaretlenir'
    $script:Cx.Clear(); Reset-T
    Undo-CompressItem @{ T = 'Compress'; Path = $root; Algo = 'lzx' }
    Assert-Eq $script:Cx.Count 2 'geri alma: NTFS ve yürütülebilir sıkıştırması ikisi de kaldırılır'
    Assert-True ($script:Cx[1] -match '/u .*/exe$') 'yürütülebilir sıkıştırması /u /exe ile'
    $script:Cx.Clear(); Reset-T
    Invoke-CompressOp @{ T = 'Compress'; Path = $root; Algo = 'bilinmeyen'; Mode = 'compress' }
    Assert-True (@($script:Cx | Where-Object { $_ -match '/exe:xpress4k' }).Count -gt 0) 'bilinmeyen yöntem yerine hızlı yöntem'
    Remove-Item function:\global:Test-CompressAllowed
    Import-Fn 'Test-CompressAllowed'
    Reset-T
    Invoke-CompressOp @{ T = 'Compress'; Path = 'C:\Windows'; Algo = 'lzx'; Mode = 'compress' }
    Assert-True (Log-Has 'Sıkıştırılmadı') 'işlem içinde de güvenlik denetimi'
    # CompactOS durumu (Windows diline göre)
    $script:CosOut = 'The system is not in the Compact state because Windows determined that this system is not suitable.'
    function global:compact.exe { $global:LASTEXITCODE = 0; [void]$script:Cx.Add((@($args) -join ' ')); return $script:CosOut }
    Assert-Eq (Get-CompactOsState) 'off' 'İngilizce: kapalı'
    $script:CosOut = 'The system is in the Compact state. It will remain in this state unless an administrator changes it.'
    Assert-Eq (Get-CompactOsState) 'on' 'İngilizce: açık'
    $script:CosOut = 'Sistem Sıkıştırılmış durumda değil.'
    Assert-Eq (Get-CompactOsState) 'off' 'Türkçe: kapalı'
    $script:CosOut = 'Sistem Sıkıştırılmış durumda.'
    Assert-Eq (Get-CompactOsState) 'on' 'Türkçe: açık'
    $script:CosOut = ''
    Assert-Eq (Get-CompactOsState) 'unknown' 'boş çıktı: bilinmiyor'
    $script:CosOut = 'Sistem Sıkıştırılmış durumda değil.'
    $script:Cx.Clear(); Reset-T
    Invoke-CompactOsOp @{ T = 'CompactOs'; State = 'always' }
    Assert-True (@($script:Cx | Where-Object { $_ -eq '/compactos:always' }).Count -eq 1) 'CompactOS açılır'
    Assert-Eq ([string]$script:Jr[0].Prev) 'off' 'önceki durum kaydedilir'
    $script:Cx.Clear()
    Undo-CompactOsItem $script:Jr[0]
    Assert-True (@($script:Cx | Where-Object { $_ -eq '/compactos:never' }).Count -eq 1) 'geri alma CompactOS kapatır'
    $script:Cx.Clear(); Reset-T
    Undo-CompactOsItem @{ T = 'CompactOs'; Prev = 'unknown'; State = 'always' }
    Assert-Eq $script:Cx.Count 0 'önceki durum bilinmiyorsa geri almada dokunulmaz'
    $err = ''
    try { Invoke-CompactOsOp @{ T = 'CompactOs'; State = 'evet' } } catch { $err = $_.Exception.Message }
    Assert-True ($err -ne '') 'geçersiz durum reddedilir'
    Remove-Item function:\global:compact.exe
    Remove-Item function:\global:Get-CpDriveFree
    $st = @(New-CompressSteps @('D:\A', 'D:\B') 'lzx')
    Assert-Eq $st.Count 2 'klasör başına bir adım'
    Assert-Eq ([string]$st[1].Ops[0].Mode) 'compress' 'varsayılan kip'
    $r = Job_CompressEstimate @{ Path = 'C:\Windows' }
    Assert-True ($r.Ok -eq $false -and [string]$r.Why -ne '') 'ölçüm işi de reddeder'
} finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }

# ======================= 5) AKILLI BAKIM: kurallar ve performans artırıcı =======================
$now = Get-Date '2026-03-02 03:00:10'
function New-Rt { return @{ Since = $null; Fired = $false; Prev = $null; LastFire = $null; Day = '' } }
$r = @{ Id = 'a'; On = $true; Name = 'x'; When = @{ Kind = 'Battery'; Op = 'lt'; Val = 20; For = 0 }; Do = @{ Kind = 'Power'; Arg = 'Saver' }; Cool = 30 }
$rt = New-Rt
Assert-True (-not (Test-AuRule $r @{ Battery = 50; HasBattery = $true } $rt $now)) 'pil yüksekken tetiklenmez'
Assert-True (Test-AuRule $r @{ Battery = 15; HasBattery = $true } $rt $now) 'pil düşünce tetiklenir'
Assert-True (-not (Test-AuRule $r @{ Battery = 14; HasBattery = $true } $rt $now.AddMinutes(1))) 'koşul sürerken ikinci kez tetiklenmez'
Assert-True (-not (Test-AuRule $r @{ Battery = 60; HasBattery = $true } $rt $now.AddMinutes(2))) 'koşul biter'
Assert-True (-not (Test-AuRule $r @{ Battery = 10; HasBattery = $true } $rt $now.AddMinutes(5))) 'bekleme süresi içinde yeniden tetiklenmez'
Assert-True (Test-AuRule $r @{ Battery = 10; HasBattery = $true } $rt $now.AddMinutes(40)) 'bekleme bitince yeniden tetiklenir'
$rt = New-Rt
Assert-True (-not (Test-AuRule $r @{ Battery = 5; HasBattery = $false } $rt $now)) 'pili olmayan bilgisayarda pil kuralı çalışmaz'
$g = @{ Id = 'g'; On = $true; Name = 'g'; When = @{ Kind = 'Game'; Arg = 'stop' }; Do = @{ Kind = 'Power'; Arg = 'Balanced' }; Cool = 0 }
$rt = New-Rt
Assert-True (-not (Test-AuRule $g @{ GameOn = $false } $rt $now)) 'ilk ölçüm kenar sayılmaz'
Assert-True (-not (Test-AuRule $g @{ GameOn = $true } $rt $now.AddSeconds(10))) 'oyun açılınca "kapanınca" kuralı çalışmaz'
Assert-True (Test-AuRule $g @{ GameOn = $false } $rt $now.AddSeconds(20)) 'oyun kapanınca çalışır'
$t = @{ Id = 't'; On = $true; Name = 't'; When = @{ Kind = 'Time'; At = '03:00'; Days = @(1) }; Do = @{ Kind = 'Clean' }; Cool = 0 }
$rt = New-Rt
Assert-True (Test-AuRule $t @{} $rt $now) 'Pazartesi 03:00 tetiklenir'
Assert-True (-not (Test-AuRule $t @{} $rt $now.AddSeconds(30))) 'aynı gün ikinci kez çalışmaz'
Assert-True (-not (Test-AuRule $t @{} (New-Rt) $now.AddDays(1))) 'başka gün çalışmaz'
$t.When.Days = @()
Assert-True (Test-AuRule $t @{} (New-Rt) $now.AddDays(1)) 'her gün seçiliyse çalışır'
$lg = @{ Id = 'l'; On = $true; Name = 'l'; When = @{ Kind = 'Logon'; Arg = 'start' }; Do = @{ Kind = 'Health' }; Cool = 0 }
$rt = New-Rt
Assert-True (Test-AuRule $lg @{ Started = $true } $rt $now) 'açılışta bir kez'
Assert-True (-not (Test-AuRule $lg @{ Started = $true } $rt $now.AddSeconds(2))) 'açılış kuralı tekrar etmez'
$tm = @{ Id = 'm'; On = $true; Name = 'm'; When = @{ Kind = 'Temp'; Op = 'gt'; Val = 88; For = 30 }; Do = @{ Kind = 'Cap'; Arg = '80' }; Cool = 30 }
Assert-True (-not (Test-AuRule $tm @{ Temp = -1 } (New-Rt) $now)) 'sıcaklık okunamıyorsa çalışmaz'
Assert-True (-not (Test-AuRule @{ When = @{ Kind = 'Bilinmeyen' }; Do = @{ Kind = 'Notify' } } @{} (New-Rt) $now)) 'bilinmeyen koşul'
# şablonlar
foreach ($tp in $script:AuTemplates) {
    $x = New-AuRule $tp
    Assert-True ($x.On -eq $false -and $x.Id.Length -eq 8) ('şablon kapalı ve kimlikli: ' + $tp.Name)
    Assert-True ((Get-AuRuleText $x) -match '→') ('şablon özeti: ' + $tp.Name)
}
$x1 = New-AuRule $script:AuTemplates[0]; $x1.When.Val = 33
Assert-Eq ([string]$script:AuTemplates[0].When.Val) '20' 'kural şablonun kopyasıdır (şablon değişmez)'
Assert-True ((Get-AuRuleText @{ When = @{ Kind = 'Ram'; Op = 'gt'; Val = 90; For = 120 }; Do = @{ Kind = 'Mem' } }) -match 'en az 120 sn') 'süre özeti'
Assert-True ((Get-AuRuleText @{ When = @{ Kind = 'Time'; At = '03:00'; Days = @(0, 6) }; Do = @{ Kind = 'Clean' } }) -match 'Pazar, Cumartesi 03:00') 'gün özeti'
# performans artırıcı: sistem işlemi, pencereli program ve kendimiz seçilmez
$top = @(
    @{ Name = 'svchost'; Cpu = 60; Pid = 100; Win = $false },
    @{ Name = 'chrome'; Cpu = 50; Pid = 101; Win = $true },
    @{ Name = 'powershell'; Cpu = 40; Pid = 102; Win = $false },
    @{ Name = 'Indexer'; Cpu = 35; Pid = 103; Win = $false },
    @{ Name = 'kucuk'; Cpu = 5; Pid = 104; Win = $false }
)
$bt = @(Get-BoostTargets $top)
Assert-Eq $bt.Count 1 'yalnızca pencere açmamış, sistem dışı, yüklü arka plan işlemi'
Assert-Eq ([string]$bt[0].Name) 'Indexer' 'doğru işlem seçilir'
# donanım ömrü satırı
$rows = New-Object System.Collections.ArrayList
Add-LifeRow $rows 'a' 'b' 'warn' 'c'
Assert-Eq ([string]$rows[0].Status) 'warn' 'ömür satırı'
# sıcaklık: WMI yoksa -1
$script:ThermAcpiRetryAt = [DateTime]::MinValue
function global:Get-CimInstance { param($Namespace, $ClassName, $OperationTimeoutSec, $ErrorAction) throw 'yok' }
Assert-Eq (Get-ThermalTemp) '-1' 'sensör yoksa -1'
# ACPI sorgusu başarısız olunca 10 dakika yeniden denenmez (yönetici izni yoksa her turda hata üretmesin)
Assert-True ($script:ThermAcpiRetryAt -gt [DateTime]::UtcNow.AddMinutes(9)) 'ACPI hatası: yeniden deneme 10 dakika sonraya ertelenir'
$script:AcpiCalls = 0
function global:Get-CimInstance { param($Namespace, $ClassName, $OperationTimeoutSec, $ErrorAction) if ($ClassName -eq 'MSAcpi_ThermalZoneTemperature') { $script:AcpiCalls++ }; throw 'yok' }
Assert-Eq (Get-ThermalTemp) '-1' 'geri çekilme sırasında da -1'
Assert-Eq $script:AcpiCalls 0 'geri çekilme sırasında ACPI sorgulanmaz'
$script:ThermAcpiRetryAt = [DateTime]::UtcNow.AddSeconds(-1)
[void](Get-ThermalTemp)
Assert-Eq $script:AcpiCalls 1 'süre dolunca ACPI yeniden sorgulanır'
$script:ThermAcpiRetryAt = [DateTime]::MinValue
function global:Get-CimInstance { param($Namespace, $ClassName, $OperationTimeoutSec, $ErrorAction) if ($ClassName -eq 'MSAcpi_ThermalZoneTemperature') { return @([pscustomobject]@{ CurrentTemperature = 3282 }, [pscustomobject]@{ CurrentTemperature = 3532 }) }; throw 'yok' }
Assert-True ([string](Get-ThermalTemp) -match '^80(\.\d)?$') 'en yüksek ACPI bölgesi (3532 → 80 °C)'
$script:ThermAcpiRetryAt = [DateTime]::MinValue
function global:Get-CimInstance { param($Namespace, $ClassName, $OperationTimeoutSec, $ErrorAction) if ($ClassName -eq 'MSAcpi_ThermalZoneTemperature') { return @([pscustomobject]@{ CurrentTemperature = 2732 }) }; if ($ClassName -like '*ThermalZoneInformation') { return @([pscustomobject]@{ Temperature = 330 }) }; throw 'yok' }
Assert-Eq (Get-ThermalTemp) '56.9' 'ACPI geçersizse performans sayacı'
Remove-Item function:\global:Get-CimInstance

# ======================= 6) GENİŞLETİLMİŞ KATALOG (betikteki tanımlar çalıştırılır) =======================
$src = [System.IO.File]::ReadAllText($env:MM_BUILD)
$i0 = $src.IndexOf('$script:CatNames = [ordered]@{')
$i1 = $src.IndexOf('# ---------------- katalog yardimcilari ----------------')
Assert-True ($i0 -gt 0 -and $i1 -gt $i0) 'temel katalog bölümü bulundu'
$k0 = $src.IndexOf('# ---------------- Genisletilmis ayar katalogu ----------------')
$k1 = $src.IndexOf("`n# ---------------- ", $k0 + 20)
$kEnd = $src.IndexOf("`n}`n# =", $k0 + 20)
if ($kEnd -lt 0) { $kEnd = $src.IndexOf("`n}`r`n# =", $k0 + 20) }
if ($k1 -lt 0 -or ($kEnd -gt 0 -and $kEnd -lt $k1)) { $k1 = $kEnd }
Assert-True ($k0 -gt 0) 'genişletilmiş katalog bölümü bulundu'
$script:Catalog = New-Object System.Collections.ArrayList
$baseCode = $src.Substring($i0, $i1 - $i0)
. ([scriptblock]::Create($baseCode))
$baseN = $script:Catalog.Count
$extCode = $src.Substring($k0, $k1 - $k0)
. ([scriptblock]::Create($extCode))
$extN = $script:Catalog.Count - $baseN
Assert-True ($extN -ge 100) ('yeni ayar sayısı: ' + $extN)
Assert-Eq $script:ExtTweakIds.Count $extN 'her yeni ayar kayıtlı'
$ids = @{}
$dup = @()
foreach ($c in $script:Catalog) { if ($ids.ContainsKey([string]$c.Id)) { $dup += [string]$c.Id }; $ids[[string]$c.Id] = $true }
Assert-Eq ($dup -join ',') '' 'kimlikler benzersiz'
$badName = '^(DisableAntiSpyware|DisableRealtimeMonitoring|DisableBehaviorMonitoring|EnableLUA|ConsentPromptBehaviorAdmin|PromptOnSecureDesktop|EnableSmartScreen|SmartScreenEnabled|NoAutoUpdate|AUOptions|DisableWindowsUpdateAccess|RemoveWindowsStore|EnableFirewall|TamperProtection)$'
$blocked = @(); $badVals = @(); $noOps = @(); $catBad = @()
foreach ($id in $script:ExtTweakIds) {
    $c = @($script:Catalog | Where-Object { $_.Id -eq $id })[0]
    if (@($c.Ops).Count -eq 0) { $noOps += $id }
    if (-not $script:CatNames.Contains([string]$c.Cat)) { $catBad += $id }
    if ([int]$c.Level -lt 1 -or [int]$c.Level -gt 4) { $catBad += ($id + ':level') }
    if ([string]$c.Title -eq '' -or ([string]$c.Desc).Length -lt 20) { $catBad += ($id + ':text') }
    foreach ($op in @($c.Ops)) {
        if ([string]$op.T -ne 'Reg') { continue }
        if ([string]$op.Name -match $badName) { $badVals += $id }
        if ((Test-RegWriteBlocked (Resolve-RegPath ([string]$op.Path)) ([string]$op.Name)) -ne '') { $blocked += $id }
        if ($op.Del -ne $true -and @('DWord', 'String', 'QWord') -notcontains [string]$op.Kind) { $badVals += ($id + ':tür') }
        if ([string]$op.Path -notmatch '^(HKLM|HKCU)\\') { $badVals += ($id + ':yol') }
        if ([string]$op.Kind -eq 'DWord' -and ([int64]$op.Value -lt 0 -or [int64]$op.Value -gt 4294967295)) { $badVals += ($id + ':değer') }
    }
}
Assert-Eq ($noOps -join ',') '' 'her ayarın işlemi var'
Assert-Eq ($catBad -join ',') '' 'kategori, düzey ve metinler geçerli'
Assert-Eq ($badVals -join ',') '' 'Defender/UAC/SmartScreen/Windows Update/Mağaza kapatan değer yok; türler ve yollar geçerli'
Assert-Eq ($blocked -join ',') '' 'hiçbiri güvenlik kapısına takılmıyor'
foreach ($must in @('PrivTailored', 'UiHidden', 'SysLongPaths', 'FeatStepsRec', 'GameHags', 'GameNagle', 'Shader', 'Thumbs', 'SetupLogs', 'Delivery', 'AppCaches', 'OldRestorePts', 'Perm_webcam', 'SysEdgeClean', 'UiCtxClean')) {
    Assert-True ($ids.ContainsKey($must)) ('katalogda: ' + $must)
}
# gizlilik kalkanı yalnızca düzey 1-2 gizlilik ayarlarını alır
$sync.Profile = @{ WinMajor = '11'; IsLaptop = $true; DiskType = 'SSD' }
$ps = @(Get-PrivacyShieldIds)
Assert-True ($ps.Count -ge 15) ('gizlilik kalkanı ayar sayısı: ' + $ps.Count)
foreach ($id in $ps) { $c = Get-CatalogItem $id; Assert-True ([string]$c.Cat -eq 'Gizlilik' -and [int]$c.Level -le 2) ('kalkan: ' + $id) }
Assert-True ($ps -notcontains 'Perm_webcam') 'izin kapatmaları (düzey 4) kalkana girmez'
# düzey 4 (yalnızca elle) olanlar hazır profillere girmez: Level 4 sayısı
Assert-True (@($script:Catalog | Where-Object { [int]$_.Level -eq 4 }).Count -ge 40) 'zevk ve kullanım tercihleri yalnızca elle seçilir'
# yeni uygulama girdileri: kodek ve çekirdek paketleri yok
$appSrc = $src.Substring($k0, $k1 - $k0)
foreach ($bad in @('Microsoft.HEVCVideoExtension', 'Microsoft.VP9VideoExtensions', 'Microsoft.WebMediaExtensions', 'Microsoft.UI.Xaml', 'Microsoft.WindowsStore', 'Microsoft.WindowsAppRuntime', 'Microsoft.SecHealthUI')) {
    Assert-True (-not $appSrc.Contains("P = '" + $bad)) ('kaldırma listesinde yok: ' + $bad)
}

# ======================= 7) YENİ EKRANLAR: bağlantılar ve -OzTest adımları =======================
Assert-True ($src -match '\$script:ClTabs = @\(''clean'', ''disk'', ''big'', ''dup'', ''compress''\)') 'Sıkıştır sekmesi'
Assert-True ($src.Contains("'compress' {")) 'Set-ClTab sıkıştır dalı'
Assert-True ($src.Contains('Init-ClCompress')) 'Sıkıştır düğmeleri bağlanır'
Assert-True ($src.Contains("if (Get-Command -Name 'Update-MonitorExtras'")) 'izleyici zamanlayıcısı ek işleri çağırır'
Assert-True ($src.Contains('$m.Temp = $last.Temp') -and $src.Contains('Get-ThermalTemp')) 'izleyici sıcaklığı ölçer'
Assert-True ($src.Contains('Get-GmRunning @($sync.GameDirs)') -and $src.Contains('$m.Games = $last.Games')) 'çalışan oyun izleyici iş parçacığında aranır'
Assert-True ($src.Contains("@('Dumps', 'Shader', 'Thumbs', 'AppCaches') -notcontains `$id")) 'bedeli olan temizlik kategorileri kendiliğinden işaretlenmez'
Assert-True ($src.Contains('$sync.GameDirs = @(')) 'oyun klasörleri izleyiciye verilir'
Assert-True ($src.Contains('Pid = $id; Win = $false')) 'izleyici işlem numarasını taşır'
Assert-True (-not $src.Contains('P = $p }') -and $src.Contains('$p.Dispose()')) 'işlem nesnesi sonuçta taşınmaz (iş parçacıkları arası) ve Dispose edilir'
Assert-True ($src.Contains('$script:FuncOps.ContainsKey([string]$Op.Name)')) 'işlev dağıtıcı yeni temizlik işlevlerini tanır'
Assert-True ($src.Contains('$defs = @($defs) + @($script:CleanExtraDefs)')) 'tarama yeni kategorileri de ölçer'
Assert-True ($src.Contains("'gucplani' { `$code = Invoke-CliPower }")) 'komut satırı: GucPlani'
Assert-True ($src.Contains("[string]`$Deger = ''")) 'komut satırı -Deger parametresi'
Assert-True ($src.Contains('Save-JsonFile $S $sync.SettingsFile 8')) 'ayarlar iç içe kurallar için yeterli derinlikte kaydedilir'
Assert-True ($src -match "\`$script:AppVersion = '10\.1\.0'") 'sürüm 10.1.0'
foreach ($pg in @('power', 'gaming', 'smart')) {
    Assert-True ($src.Contains('x:Name="Rail_' + $pg + '"')) ('menüde: ' + $pg)
    Assert-True ($src.Contains('function Init-Page_' + $pg + ' {')) ('sayfa hazırlığı: ' + $pg)
    Assert-True ($src.Contains('function Show-Page_' + $pg + ' {')) ('sayfa gösterimi: ' + $pg)
}
# sayfa XAML'leri ve satır şablonları: XML olarak geçerli ve ekran kodunun kullandığı adlar tanımlı
$xamlNames = New-Object System.Collections.Generic.HashSet[string]
foreach ($v in @('Page_power', 'Page_gaming', 'Page_smart', 'Row_Step1', 'Row_Step2', 'Row_Input', 'Row_Buttons', 'XamlWidget')) {
    $m = [regex]::Match($src, '(?s)\$script:' + $v + ' = @''\r?\n(.*?)\r?\n''@')
    Assert-True $m.Success ('XAML bulundu: ' + $v)
    $ok = $true
    try { [void]([xml]$m.Groups[1].Value) } catch { $ok = $false }
    Assert-True $ok ('XAML geçerli XML: ' + $v)
    foreach ($n in [regex]::Matches($m.Groups[1].Value, 'x:Name="([^"]+)"')) { [void]$xamlNames.Add($n.Groups[1].Value) }
}
$ui0 = $src.IndexOf('# ---------------- Ekranlar: guc, oyun, akilli bakim, sikistirma ----------------')
$uiEnd = $src.IndexOf('function Init-Page_backup {', $ui0)
# ust cubuk modulu (kendi XAML'i ve t_header.ps1 takimi var) ayni konuma eklenir; bu denetimin kapsami disindadir
$hdrAt = $src.IndexOf('#  UST CUBUK (arayuz)', $ui0)
if ($hdrAt -gt $ui0 -and $hdrAt -lt $uiEnd) { $uiEnd = $hdrAt }
$uiCode = $src.Substring($ui0, $uiEnd - $ui0)
$miss = @()
foreach ($m in [regex]::Matches($uiCode, '\$ui\.((?:pw|gm|sm|wd)_\w+)')) { if (-not $xamlNames.Contains($m.Groups[1].Value)) { $miss += $m.Groups[1].Value } }
Assert-Eq (($miss | Select-Object -Unique) -join ',') '' 'ekran kodunun kullandığı her alan XAML icinde var'
foreach ($m in [regex]::Matches($uiCode, "FindName\('(\w+)'\)")) {
    $n = $m.Groups[1].Value
    Assert-True ($xamlNames.Contains($n) -or @('Act', 'Act2', 'Chk', 'Det', 'Tag', 'Items') -contains $n) ('FindName alanı var: ' + $n)
}
foreach ($m in [regex]::Matches($uiCode, "FindName\(\`$side \+ '(\w+)'\)")) {
    foreach ($s in @('Ac', 'Dc')) { Assert-True ($xamlNames.Contains($s + $m.Groups[1].Value)) ('adım seçici alanı: ' + $s + $m.Groups[1].Value) }
}
# -OzTest adımlarını gerçek gövdeleriyle çalıştır
$t = $null; $e = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($env:MM_BUILD, [ref]$t, [ref]$e)
$cmds = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Test-Step' }, $true)
function Run-Step([string]$Needle) {
    $b = $null
    foreach ($c in $cmds) {
        if ($c.CommandElements[1].Extent.Text.Contains($Needle)) {
            foreach ($el in $c.CommandElements) { if ($el -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) { $b = [scriptblock]::Create($el.ScriptBlock.Extent.Text.Trim().TrimStart('{').TrimEnd('}')) } }
        }
    }
    if ($null -eq $b) { Assert-True $false ('sınama adımı bulunamadı: ' + $Needle); return }
    $out = @(& $b)
    $r = $null; if ($out.Count -gt 0) { $r = $out[$out.Count - 1] }
    $ok = -not (($r -is [string] -and $r -ne '') -or ($r -is [bool] -and $r -eq $false))
    Assert-True $ok ($Needle + ' -> ' + [string]$r)
}
Import-Fn 'Invoke-PowerSetOp', 'Get-PwSafeName', 'Get-GmSteamGames', 'Get-GmEpicGames', 'Get-GmGogGames', 'Test-GmExePath', 'Get-CpDriveFree', 'Test-CompressAllowed', 'Get-CatalogItem', 'Get-CatalogFor', 'Get-PwLive', 'Job_GameScan', 'Invoke-GameFlagsOp', 'Job_GameBoost', 'Job_Lifespan', 'Job_SmartZero', 'Job_PrivacyStatus', 'Get-PwBatteryWear'
function Test-PwUseMode([string]$PlanKey) { return $false }   # bu testte klasik güç planı yolu sınanır (Modern Bekleme yolu: t_realfix)
foreach ($k in @('PowerSet', 'PowerCustom', 'PowerDelete', 'PowerCpuMax', 'Cap', 'NetLatency', 'DxGlobal', 'GameFlags', 'Compress', 'CompactOs')) { $script:MoreOps[$k] = 'x' }
foreach ($k in @('PowerNew', 'PowerDel', 'PowerCpuMax', 'Cap', 'Compress', 'CompactOs')) { $script:MoreUndo[$k] = 'x' }
foreach ($k in @('CleanShader', 'CleanThumbs', 'CleanSetupLogs', 'CleanDelivery', 'CleanAppCaches', 'CleanPrefetch', 'CleanRecent', 'CleanRestorePoints')) { $script:FuncOps[$k] = 'x' }
Import-Var 'CleanExtraDefs', 'SmSafeClean', 'PageTitles', 'XamlMain', 'Page_power', 'Page_gaming', 'Page_smart', 'Page_clean', 'XamlWidget', 'Row_Step1', 'Row_Step2', 'Row_Buttons', 'Row_Input', 'ClTabs'
foreach ($fn in @('Invoke-CleanShader', 'Invoke-CleanThumbs', 'Invoke-CleanSetupLogs', 'Invoke-CleanDelivery', 'Invoke-CleanAppCaches')) { Import-Fn $fn }
Run-Step 'plan tablosu'
Run-Step 'Oyun: oyun ba'
Run-Step 'Windows, g'
Run-Step 'kural motoru'
Run-Step 'kimlikler benzersiz'
Run-Step 'Oyun, Ak'
Show-Result
