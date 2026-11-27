. "$PSScriptRoot/lib.ps1"
# Canlı özellik denetimi (mods\155_live_audit.ps1, 156_live_audit2.ps1; patches\p69_ozellik.py).
# Gerçek Windows'ta yapılan işlemlerin kendisi burada sınanamaz; burada denetimin KENDİ mantığı sınanır: karşılaştırmalar, ayar grupları,
# çökme sonrası geri yükleme, araç denemeleri (parola, şifreleme, silme, yeniden adlandırma geçici klasörde gerçek dosyalarla) ve bölüm yönlendirici.
Import-Fn 'Get-LiveDir', 'Get-LiveMode', 'Format-LiveMs', 'Add-LiveRow', 'Get-LiveCount', 'Get-LiveLogMark', 'Get-LiveLogSince', 'Select-LiveLines',
    'Invoke-LiveJob', 'ConvertTo-LiveUInt', 'Test-LiveDataEqual', 'Test-LiveRawEqual', 'Format-LiveRaw', 'Compare-LiveItem', 'Get-LiveShort', 'Compare-LiveSnap',
    'ConvertTo-LiveHex', 'ConvertFrom-LiveHex', 'ConvertTo-LiveSerial', 'Save-LiveInflight', 'Clear-LiveInflight', 'Restore-LiveItem', 'Restore-LiveFunc', 'Restore-LiveSnap', 'Restore-LiveInflight',
    'Get-LiveGroup', 'Get-LiveExpectMismatch', 'Get-LiveJournalAfter', 'Get-LiveSandbox', 'Get-LiveResultSummary', 'Get-LiveReadJobs',
    'Test-LivePassword', 'Test-LiveRename', 'Test-LiveCrypt', 'Test-LiveSecureDelete', 'Test-LiveTools', 'Test-LiveJobs', 'Test-SmokeLive', 'Complete-LiveAudit',
    'Invoke-LiveGuarded', 'Test-LivePreviewOn', 'Add-LiveBlocked', 'Get-LiveWhy', 'Get-LivePlanFiles', 'Test-LiveOpMeasurable', 'Get-LiveUnkLevel', 'Get-LiveServicingBlock', 'Test-LiveRetryDeferred', 'Get-LiveBuildTag', 'Add-LiveCompTouched', 'Get-LiveOpCompName', 'Add-LiveTouched', 'Test-LiveMovedOutside', 'Remove-LiveUnrestoredDone', 'Get-LiveUnrestoredFile', 'Get-LiveUnrestored', 'Save-LiveUnrestoredList', 'Add-LiveUnrestored', 'Restore-LiveUnrestored', 'Test-LiveFeatureTrips', 'Get-LiveFeatureOrder', 'Get-LiveRebootNeed', 'Get-CbsRebootPending', 'Get-LiveCapRemovals', 'Test-LiveCapLive', 'Get-LiveSnap', 'Add-LiveFlat', 'ConvertFrom-LiveJsonList', 'Test-LiveItemCurrent', 'Get-LiveKeepPreviewWhy', 'Test-LiveRoundTrips', 'Get-LiveApplicable', 'Get-LiveRiskFile', 'Get-LiveRiskyNames', 'Add-LiveRisky', 'Test-LiveDismItem', 'Get-LiveDismBlock', 'Get-LiveProcNames', 'Wait-LiveCbsIdle', 'Get-LiveFeatChange', 'Get-LiveOneWayBlock', 'Test-LiveComponents', 'Get-LiveCapState', 'Get-LiveAppxState', 'Add-SmokeExpect', 'Test-SmokeExpected', 'Get-SmokeExpectMissing',
    'Get-PasswordSets', 'Get-PasswordBits', 'Get-PasswordStrengthText', 'Get-NextPwLength', 'Get-SafeFileName', 'Split-FileName', 'Get-RenamePlan', 'Test-RenameDirAllowed',
    'Job_RenameScan', 'Invoke-RenamePairs', 'Invoke-RenameOp', 'Undo-RenameItem', 'Format-Size', 'Test-SecureDeleteAllowed', 'Get-FilesBySize'
Import-Var 'LiveFuncLive', 'LiveOneWay', 'LiveKeepPreview', 'LiveCapPrefer', 'LiveFeatLight', 'LiveStopKinds', 'FuncStateful', 'LiveAdminOnlyOps', 'LiveSvcBlock0', 'LiveCbsHard', 'LiveCbsSoft', 'LiveRestoreFailed', 'PwCharSets', 'PwLengths', 'RenameModes', 'RenameMax', 'WalkSkipDirs', 'LiveGuardNames', 'LiveBlocked', 'LiveOkFalseInfo', 'SmokeExpect'
[void](Import-Ext 'Parola'); [void](Import-Ext 'Sifreleme'); [void](Import-Ext 'GuvenliSilme')
$src = [System.IO.File]::ReadAllText($script:TestPath)

# ---- sahte ortam
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('mm-live-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
[void][System.IO.Directory]::CreateDirectory($tmp)
$bk = Join-Path $tmp 'yedek'; [void][System.IO.Directory]::CreateDirectory($bk)
$logFile = Join-Path $tmp 'gunluk.txt'; [System.IO.File]::WriteAllText($logFile, '')
$sync = @{ BackupDir = $bk; LogFile = $logFile; Profile = $null }
$script:SmokeLines = New-Object System.Collections.ArrayList
$script:SmokeErrs2 = New-Object System.Collections.ArrayList
$script:SmokeWarns2 = New-Object System.Collections.ArrayList
function Add-SmokeLine([string]$Text) { [void]$script:SmokeLines.Add($Text) }
function Add-SmokeError([string]$Where, [string]$Msg) { [void]$script:SmokeErrs2.Add($Where + '|' + $Msg) }
function Add-SmokeWarn([string]$Text) { [void]$script:SmokeWarns2.Add($Text) }
function Invoke-SmokeFlush { }
function Write-WhLog([string]$Message, [string]$Level = 'INFO') { [System.IO.File]::AppendAllText($logFile, ((Get-Date -Format 'HH:mm:ss') + ' ' + $Level.PadRight(5) + ' ' + $Message + "`n")) }
function Set-JobProgress($Done, $Total, [string]$Label = '') { }
function Step-JobProgress { }
function Test-JobCancel { return $false }
function Get-AppFolder { return $tmp }
function Test-OsOk($Os, $Pr) { return $true }
function Import-MmExt([string]$Name) { return @{ Ok = $true; Error = ''; Blocked = $false } }
$script:LiveRows = New-Object System.Collections.ArrayList
$script:LiveMode = ''; $script:LiveDowngraded = $false; $script:LiveState = @{}; $script:LiveT0 = $null; $script:LiveApplicable = $null
$script:LiveTsv = (Join-Path $tmp 'ozellik.tsv')
$env:MM_OZELLIK_KIP = 'oku'
$script:IsAdmin = $false

# sahte kayıt defteri
$script:FakeReg = @{}
function Resolve-RegPath([string]$Path) { return $Path }
function Get-LiveRegRaw([string]$Path, [string]$Name) {
    $k = $Path + '|' + $Name
    $r = @{ KeyExists = $true; Exists = $false; Kind = ''; Data = $null; Err = '' }
    if ($script:FakeReg.ContainsKey($k)) { $r.Exists = $true; $r.Kind = [string]$script:FakeReg[$k].Kind; $r.Data = $script:FakeReg[$k].Data }
    return $r
}
function Set-RegData([string]$Path, [string]$Name, [string]$Kind, $Value) { $script:FakeReg[$Path + '|' + $Name] = @{ Kind = $Kind; Data = $Value } }
function Remove-RegData([string]$Path, [string]$Name, $KeyToo) { [void]$script:FakeReg.Remove($Path + '|' + $Name) }

# ======================= 1) sayı, metin, karşılaştırma =======================
Assert-Eq (Format-LiveMs 250) '250 ms' 'süre: milisaniye'
Assert-True ((Format-LiveMs 2500) -like '2?5 sn') 'süre: saniye'
Assert-True ((Format-LiveMs 120000) -like '2 dk') 'süre: dakika'
Assert-Eq (Get-LiveShort ('a   b' + (' ' * 3) + 'c') 90) 'a b c' 'kısa metin: boşluklar sıkıştırılır'
Assert-True ((Get-LiveShort ('x' * 200) 50).Length -le 51) 'kısa metin: sınır'

Assert-True (Test-LiveDataEqual 'DWord' 1 1) 'DWord eşit'
Assert-True (-not (Test-LiveDataEqual 'DWord' 1 0)) 'DWord farklı'
Assert-True (Test-LiveDataEqual 'DWord' 4294967295 -1) 'DWord: işaretli ve işaretsiz aynı bit düzeni eşit sayılır'
Assert-True (Test-LiveDataEqual 'String' '200' '200') 'String eşit'
Assert-True (-not (Test-LiveDataEqual 'String' '200' '20')) 'String farklı'
Assert-True (Test-LiveDataEqual 'Binary' ([byte[]](1, 2, 3)) ([byte[]](1, 2, 3))) 'Binary eşit'
Assert-True (-not (Test-LiveDataEqual 'Binary' ([byte[]](1, 2, 3)) ([byte[]](1, 2, 4)))) 'Binary farklı'
Assert-True (Test-LiveDataEqual 'MultiString' @('a', 'b') @('a', 'b')) 'MultiString eşit'
Assert-True (-not (Test-LiveDataEqual 'MultiString' @('a', 'b') @('a'))) 'MultiString farklı'

$rx = @{ K = 'Reg'; Path = 'HKCU\X'; Name = 'A'; Raw = @{ Exists = $true; Kind = 'DWord'; Data = 1; KeyExists = $true } }
$ry = @{ K = 'Reg'; Path = 'HKCU\X'; Name = 'A'; Raw = @{ Exists = $true; Kind = 'DWord'; Data = 0; KeyExists = $true } }
Assert-Eq (Compare-LiveItem $rx $rx) '' 'aynı kayıt değeri: fark yok'
Assert-True ((Compare-LiveItem $rx $ry) -like '*HKCU\X\A*') 'farklı kayıt değeri: fark bildirilir'
$rz = @{ K = 'Reg'; Path = 'HKCU\X'; Name = 'A'; Raw = @{ Exists = $false; Kind = ''; Data = $null; KeyExists = $true } }
Assert-True ((Compare-LiveItem $rx $rz) -ne '') 'değer silinmiş: fark bildirilir'
$sA = @{ K = 'Svc'; Name = 'S'; Start = 2; Delayed = $false; Status = 'Running'; Exists = $true }
$sB = @{ K = 'Svc'; Name = 'S'; Start = 4; Delayed = $false; Status = 'Stopped'; Exists = $true }
Assert-Eq (Compare-LiveItem $sA $sA) '' 'aynı hizmet: fark yok'
Assert-True ((Compare-LiveItem $sA $sB) -like '*hizmet S*') 'farklı hizmet: fark bildirilir'
$pA = @{ K = 'Func'; Name = 'PowerMode'; Data = 'ac=;dc=;cur=aaa' }
$pB = @{ K = 'Func'; Name = 'PowerMode'; Data = 'ac=bbb;dc=bbb;cur=aaa' }
$pC = @{ K = 'Func'; Name = 'PowerMode'; Data = 'ac=;dc=;cur=ccc' }
Assert-Eq (Compare-LiveItem $pA $pB) '' 'güç kipi: boş kullanıcı kipi ile yazılmış kullanıcı kipi aynı yürürlükteki kip ise fark sayılmaz'
Assert-True ((Compare-LiveItem $pA $pC) -like '*güç kipi*') 'güç kipi: yürürlükteki kip değişirse fark bildirilir'
$fA = @{ K = 'Func'; Name = 'HibernateOff'; Data = 'hib=1' }
$fB = @{ K = 'Func'; Name = 'HibernateOff'; Data = 'hib=0' }
Assert-True ((Compare-LiveItem $fA $fB) -like '*HibernateOff*') 'işlev: fark bildirilir'
$dSame = Compare-LiveSnap @($rx, $sA) @($rx, $sA)
$dTwo = Compare-LiveSnap @($rx, $sA) @($ry, $sB)
Assert-Eq $dSame.Count 0 'anlık görüntü: aynı'
Assert-Eq $dTwo.Count 2 'anlık görüntü: iki fark'

# ======================= 2) ayar grupları =======================
$script:LiveFuncLive = @('PowerPlan', 'HibernateOff')
$script:LiveOneWay = @('OptimizeDrive', 'CleanTemp')
$script:LiveKeepPreview = @('CleanRestorePoints')
function New-Cat([string]$Id, $Ops, [bool]$Irrev = $false) { return @{ Id = $Id; OS = 'All'; Ops = $Ops; Irrev = $Irrev } }
Assert-Eq (Get-LiveGroup (New-Cat 'a' @(@{ T = 'Reg'; Path = 'HKCU\X'; Name = 'A' }))) 'hkcu' 'grup: yalnız HKCU kaydı'
Assert-Eq (Get-LiveGroup (New-Cat 'b' @(@{ T = 'Reg'; Path = 'HKCU\X'; Name = 'A' }, @{ T = 'Reg'; Path = 'HKLM\Y'; Name = 'B' }))) 'hklm' 'grup: karışık kök HKLM grubuna girer'
Assert-Eq (Get-LiveGroup (New-Cat 'c' @(@{ T = 'Reg'; Path = 'HKLM\Y'; Name = 'B' }, @{ T = 'Svc'; Name = 'S' }))) 'hizmet' 'grup: kayıt + hizmet'
Assert-Eq (Get-LiveGroup (New-Cat 'd' @(@{ T = 'Svc'; Name = 'S' }, @{ T = 'Task'; Name = 'T' }))) 'hizmet' 'grup: hizmet + görev'
Assert-Eq (Get-LiveGroup (New-Cat 'e' @(@{ T = 'Mp'; Name = 'M' }))) 'ozel' 'grup: Defender ayarı özel'
Assert-Eq (Get-LiveGroup (New-Cat 'f' @(@{ T = 'Func'; Name = 'HibernateOff' }))) 'ozel' 'grup: geri alınabilir işlev özel'
Assert-Eq (Get-LiveGroup (New-Cat 'g' @(@{ T = 'Func'; Name = 'OptimizeDrive' }))) 'tekyon' 'grup: tek yönlü işlev canlı denenir, ikinci önizlemeyle doğrulanır'
Assert-Eq (Get-LiveGroup (New-Cat 'g2' @(@{ T = 'Func'; Name = 'CleanTemp' }) $true)) 'tekyon' 'grup: geri alınamaz temizlik de tek yönlü gruba girer'
Assert-Eq (Get-LiveGroup (New-Cat 'g3' @(@{ T = 'Func'; Name = 'CleanRestorePoints' }))) 'onizleme' 'grup: kurtarma noktası silen işlev yalnız önizleme'
Assert-Eq (Get-LiveGroup (New-Cat 'g4' @(@{ T = 'Func'; Name = 'BilinmeyenIslev' }))) 'onizleme' 'grup: listede olmayan işlev yalnız önizleme'
Assert-Eq (Get-LiveGroup (New-Cat 'h' @(@{ T = 'Cap'; Name = 'X' }))) 'bilesen' 'grup: Windows bileşeni kaldırma bileşen bölümünde (temsilci canlı tur)'
Assert-Eq (Get-LiveGroup (New-Cat 'h2' @(@{ T = 'Feature'; Name = 'WorkFolders-Client'; State = 'Disabled' }))) 'bilesen' 'grup: Windows özelliği bileşen bölümünde (hepsi canlı denenir; hafifler önce)'
Assert-Eq (Get-LiveGroup (New-Cat 'h3' @(@{ T = 'Feature'; Name = 'SMB1Protocol'; State = 'Disabled' }, @{ T = 'Reg'; Path = 'HKLM\Y'; Name = 'B' }))) 'bilesen' 'grup: özellik + kayıt da bileşen bölümünde'
Assert-True ($script:LiveFeatLight -contains 'Printing-Foundation-InternetPrinting-Client' -and $script:LiveFeatLight -contains 'WorkFolders-Client') 'hafif özellik listesi'
foreach ($hv in @('VirtualMachinePlatform', 'Microsoft-Windows-Subsystem-Linux', 'NetFx3', 'Microsoft-Hyper-V-All', 'Containers-DisposableClientVM', 'DirectPlay', 'LegacyComponents')) {
    Assert-True ($script:LiveFeatLight -notcontains $hv) ('ağır özellik hafif listesinde değil (sona bırakılır): ' + $hv)
}
Assert-True (Test-LiveOpMeasurable @{ T = 'Feature' }) 'ölçülebilir: Windows özelliği'
Assert-Eq (Get-LiveUnkLevel @('Smb1(Feature+Reg)', 'FeatStepsRec(Cap)', 'FeatXps(Cap+Feature)') $false) 'BILGI' 'yönetici değilken yalnızca DISM ile okunan bileşenler ölçülemiyorsa bilgi'
Assert-Eq (Get-LiveUnkLevel @('Smb1(Feature+Reg)', 'Telemetry(Reg+Svc+Task)') $false) 'UYARI' 'yönetici gerektirmeyen bir ayar ölçülemiyorsa uyarı'
Assert-Eq (Get-LiveUnkLevel @('FeatStepsRec(Cap)') $true) 'UYARI' 'yönetici kipinde ölçülemeyen her ayar uyarı'
Assert-Eq (Get-LiveUnkLevel @('Bozuk') $false) 'UYARI' 'biçimi tanınmayan kimlik uyarı'
Assert-True (Test-LiveOpMeasurable @{ T = 'Mp' }) 'ölçülebilir: Defender'
Assert-True (Test-LiveOpMeasurable @{ T = 'Func'; Name = 'PowerPlan' }) 'ölçülebilir: güç planı işlevi'
Assert-True (-not (Test-LiveOpMeasurable @{ T = 'Func'; Name = 'CleanTemp' })) 'ölçülemez: tek yönlü temizlik'
Assert-True (-not (Test-LiveOpMeasurable @{ T = 'Hosts' })) 'ölçülemez: tanımsız tür'
Assert-Eq (Get-LiveGroup (New-Cat 'i' @(@{ T = 'Reg'; Path = 'HKLM\Y'; Name = 'B' }) $true)) 'onizleme' 'grup: geri alınamaz ayar yalnız önizleme'
Assert-Eq (Get-LivePlanFiles @('Geçici dosyalar: 12 dosya, 3 MB', 'Hata raporları: 3 dosya, 1 KB')) 15 'plan satırlarından dosya sayısı toplanır'
Assert-Eq (Get-LivePlanFiles @('DNS önbelleği temizlenecek')) -1 'dosya sayısı olmayan planda -1'
Assert-Eq (Get-LiveOneWayBlock 'CleanTemp') '' 'geçici dosya temizliği canlı denenebilir'

# yalnızca önizlenenler (cihaz bulgusu 18.11.2026): kurtarma noktası, Windows.old ve son kullanılanlar listesi canlı silinmez
Import-Var 'LiveKeepPreview', 'LiveKeepPreviewWhy'
Assert-Eq (Get-LiveGroup (New-Cat 'g5' @(@{ T = 'Func'; Name = 'CleanMgr' }))) 'onizleme' 'grup: Windows.old silen Disk Temizleme yalnız önizleme'
Assert-Eq (Get-LiveGroup (New-Cat 'g6' @(@{ T = 'Func'; Name = 'CleanRecent' }))) 'onizleme' 'grup: son kullanılanlar listesini silen işlev yalnız önizleme'
Assert-True ((Get-LiveKeepPreviewWhy (New-Cat 'g3' @(@{ T = 'Func'; Name = 'CleanRestorePoints' }))) -like '*geri yükleme noktalarını*') 'önizleme nedeni yazılır'
Assert-Eq (Get-LiveKeepPreviewWhy (New-Cat 'g' @(@{ T = 'Func'; Name = 'OptimizeDrive' }))) '' 'canlı işlevde önizleme nedeni yok'
# tam kipte önizleme grubu gerçek uygulanmaz (bu satır yokken cihazda eski geri yükleme noktaları silindi)
$keepApp = $script:LiveApplicable
$script:LiveApplicable = @((New-Cat 'rp' @(@{ T = 'Func'; Name = 'CleanRestorePoints' })), (New-Cat 'tt' @(@{ T = 'Func'; Name = 'OptimizeDrive' })))
$script:LiveMode = 'tam'
$global:RtModes = New-Object System.Collections.ArrayList
function Invoke-LiveRoundTrip($C, [string]$Mode) { [void]$global:RtModes.Add([string]$C.Id + ':' + $Mode) }
$rowsBefore = @($script:LiveRows).Count
Test-LiveRoundTrips 'onizleme'
Test-LiveRoundTrips 'tekyon'
Assert-Eq (@($global:RtModes) -join ',') 'rp:oku,tt:tam' 'tam kipte: önizleme grubu yalnızca önizlenir, tek yönlü grup canlı denenir'
Assert-True ((@($script:LiveRows | Select-Object -Skip $rowsBefore | Where-Object { [string]$_.Kimlik -eq 'neden:rp' })).Count -eq 1) 'önizlenen ayarın nedeni yazılır'
Assert-True ((@($script:LiveRows | Select-Object -Skip $rowsBefore | Where-Object { [string]$_.Kimlik -eq 'grup:onizleme' -and [string]$_.Ayrinti -like '*yalnızca önizlenir*' })).Count -eq 1) 'grup satırı önizleme kuralını söyler'
Remove-Item function:Invoke-LiveRoundTrip -ErrorAction SilentlyContinue
$script:LiveApplicable = $keepApp; $script:LiveMode = ''
$script:LiveKeepPreview = @('CleanRestorePoints')

# JSON listesi: Windows PowerShell 5.1 ConvertFrom-Json diziyi tek nesne verir; ic ice yazilmis dosya da duz okunur
$nested = '[[[{"Id":"FeatWorkFolders","Items":[{"K":"Feature","Name":"WorkFolders-Client","State":"Enabled"}]}]],{"Id":"FeatHyperV","Items":[{"K":"Feature","Name":"VirtualMachinePlatform","State":"Enabled"}]}]'
$fl = @(ConvertFrom-LiveJsonList $nested)
Assert-Eq $fl.Count 2 'iç içe yazılmış kurtarma listesi düz okunur (cihazdaki dosya)'
Assert-Eq (@($fl | ForEach-Object { [string]$_.Id }) -join ',') 'FeatWorkFolders,FeatHyperV' 'düz liste sırası korunur'
Assert-Eq @(ConvertFrom-LiveJsonList '[]').Count 0 'boş JSON dizisi boş liste'
Assert-Eq @(ConvertFrom-LiveJsonList '{"Id":"Tek"}').Count 1 'tek nesne bir öğe'
Assert-Eq @(ConvertFrom-LiveJsonList '').Count 0 'boş metin boş liste'
# PS 5.1 davranışı (ConvertFrom-Json diziyi tek nesne verir) taklit edilerek dosya gidiş-dönüşü iç içe geçmemeli
function ConvertFrom-Json { param([Parameter(ValueFromPipeline = $true)]$InputObject) Microsoft.PowerShell.Utility\ConvertFrom-Json -InputObject $InputObject -NoEnumerate }
Save-LiveUnrestoredList @(@{ Id = 'A'; Time = 't'; Why = 'w'; Items = @(@{ K = 'Feature'; Name = 'X'; State = 'Enabled' }) }, @{ Id = 'B'; Time = 't'; Why = 'w'; Items = @(@{ K = 'Feature'; Name = 'Y'; State = 'Enabled' }) })
Add-LiveUnrestored 'C' @(@{ K = 'Feature'; Name = 'Z'; State = 'Enabled' }) 'w'
Add-LiveUnrestored 'D' @(@{ K = 'Feature'; Name = 'Q'; State = 'Enabled' }) 'w'
$ur = @(Get-LiveUnrestored)
Assert-Eq (@($ur | ForEach-Object { [string]$_.Id }) -join ',') 'A,B,C,D' 'PS 5.1 davranışında kurtarma listesi düz kalır (her yazışta iç içe geçmez)'
$rawU = [System.IO.File]::ReadAllText((Get-LiveUnrestoredFile))
Assert-True ($rawU -notmatch '\[\s*\[') 'kurtarma dosyasında iç içe dizi yok'
Assert-Eq ((@(Get-LiveRiskyNames) | Sort-Object) -join ',') 'Q,X,Y,Z' 'PS 5.1 davranışında risk listesi adları ayrı ayrı okunur'
Remove-Item function:ConvertFrom-Json -ErrorAction SilentlyContinue
Save-LiveUnrestoredList @()
try { Remove-Item -LiteralPath (Get-LiveRiskFile) -Force -ErrorAction SilentlyContinue } catch { }

# ======================= 3) çökme sonrası geri yükleme =======================
$script:FakeReg['HKCU\Z|Var'] = @{ Kind = 'DWord'; Data = 7 }
$script:FakeReg['HKCU\Z|Ikili'] = @{ Kind = 'Binary'; Data = [byte[]](1, 2, 3, 4) }
$cat = @{ Id = 'deneme'; Ops = @(@{ T = 'Reg'; Path = 'HKCU\Z'; Name = 'Var'; Value = 1 }, @{ T = 'Reg'; Path = 'HKCU\Z'; Name = 'Ikili'; Value = @(9) }, @{ T = 'Reg'; Path = 'HKCU\Z'; Name = 'Yok'; Value = 1 }) }
function Get-LiveSnapFake($C) {
    $items = New-Object System.Collections.ArrayList
    foreach ($op in @($C.Ops)) { [void]$items.Add(@{ K = 'Reg'; Path = [string]$op.Path; Name = [string]$op.Name; Raw = (Get-LiveRegRaw ([string]$op.Path) ([string]$op.Name)) }) }
    return , $items.ToArray()
}
$snap0 = Get-LiveSnapFake $cat
$ser = ConvertTo-LiveSerial $snap0
Assert-Eq @($ser).Count 3 'seri hâle çevirme: üç öğe'
$json = ConvertTo-Json -InputObject @{ Id = 'deneme'; Items = $ser } -Depth 8
$back = ConvertFrom-Json -InputObject $json
Assert-Eq @($back.Items).Count 3 'JSON gidiş dönüş: öğeler iç içe değil (düz dizi)'
Assert-Eq ([string]@($back.Items)[0].K) 'Reg' 'JSON gidiş dönüş: alan adları korunur'
Assert-Eq ([string]@($back.Items)[1].Data) '01020304' 'Binary veri kurtarma dosyasında onaltılık metin olarak tutulur'
Assert-Eq (ConvertTo-LiveHex ([byte[]](0, 15, 16, 255))) '000f10ff' 'onaltılık: sıfır ve 255 dâhil iki hane'
Assert-Eq (ConvertTo-LiveHex $null) '' 'onaltılık: boş veri boş metin'
$hb = ConvertFrom-LiveHex '000F10ff'
Assert-True ($hb -is [byte[]]) 'onaltılık geri çevirme byte dizisi döndürür'
Assert-Eq ($hb -join ',') '0,15,16,255' 'onaltılık geri çevirme: büyük/küçük harf'
$he = ConvertFrom-LiveHex ''
Assert-True ($he -is [byte[]] -and $he.Length -eq 0) 'onaltılık: boş metin boş dizi'
$hx = ''; try { [void](ConvertFrom-LiveHex 'AQID') } catch { $hx = $_.Exception.Message }
Assert-True ($hx -ne '') 'onaltılık değil (eski base64 biçimi): hata verir, sessizce yanlış yazmaz'
$hx = ''; try { [void](ConvertFrom-LiveHex 'abc') } catch { $hx = $_.Exception.Message }
Assert-True ($hx -ne '') 'tek sayıda hane: hata verir'

$script:LiveMode = ''; $env:MM_OZELLIK_KIP = 'oku'; $script:IsAdmin = $false
Clear-LiveInflight
Save-LiveInflight 'deneme' $snap0
Assert-True (Test-Path -LiteralPath (Join-Path (Get-LiveDir) 'ozellik-yarim.json')) 'yarım kalan durum diske yazıldı'
# deneme "çöker": değerler değişmiş kalır
$script:FakeReg['HKCU\Z|Var'] = @{ Kind = 'DWord'; Data = 1 }
$script:FakeReg['HKCU\Z|Ikili'] = @{ Kind = 'Binary'; Data = [byte[]](9) }
$script:FakeReg['HKCU\Z|Yok'] = @{ Kind = 'DWord'; Data = 1 }
# okuma kipinde dokunulmaz, yalnızca uyarılır
$rowsBefore = @($script:LiveRows).Count
Restore-LiveInflight
Assert-Eq ([int]$script:FakeReg['HKCU\Z|Var'].Data) 1 'okuma kipi: geri yükleme yapılmaz'
Assert-True ((@($script:LiveRows | Select-Object -Skip $rowsBefore | Where-Object { $_.Durum -eq 'UYARI' })).Count -ge 1) 'okuma kipi: yarım kalan durum uyarısı'
# tam kipte (yönetici) geri yüklenir
$script:LiveMode = ''; $env:MM_OZELLIK_KIP = 'tam'; $script:IsAdmin = $true
Restore-LiveInflight
Assert-Eq ([int]$script:FakeReg['HKCU\Z|Var'].Data) 7 'tam kip: DWord eski değerine döndü'
Assert-Eq (($script:FakeReg['HKCU\Z|Ikili'].Data -join ',')) '1,2,3,4' 'tam kip: Binary eski değerine döndü'
Assert-True (-not $script:FakeReg.ContainsKey('HKCU\Z|Yok')) 'tam kip: sonradan oluşan değer silindi'
Assert-True (-not (Test-Path -LiteralPath (Join-Path (Get-LiveDir) 'ozellik-yarim.json'))) 'geri yüklemeden sonra yarım kalan dosya silindi'
# yönetici değilse tam kip istense bile okuma kipine iner
$script:LiveMode = ''; $script:LiveDowngraded = $false; $script:IsAdmin = $false
Assert-Eq (Get-LiveMode) 'oku' 'yönetici değil: tam kip okuma kipine iner'
Assert-True ($script:LiveDowngraded -eq $true) 'yönetici değil: düşürme işaretlenir'
$script:LiveMode = ''; $env:MM_OZELLIK_KIP = ''; Assert-Eq (Get-LiveMode) 'oku' 'varsayılan kip: oku'
$env:MM_OZELLIK_KIP = 'oku'; $script:LiveMode = ''

# ======================= 3b) kalıcı kurtarma listesi (geri yüklenemeyen değişiklikler) =======================
Save-LiveUnrestoredList @()
Assert-Eq @(Get-LiveUnrestored).Count 0 'kurtarma listesi boş'
Add-LiveUnrestored 'FeatWorkFolders' @(@{ K = 'Reg'; Path = 'HKCU\Z'; Name = 'Kurt'; Exists = $true; Kind = 'DWord'; Data = 5; KeyExists = $true }) 'özellik WorkFolders-Client: Enabled -> Disabled'
Add-LiveUnrestored 'FeatHyperV' @(@{ K = 'Reg'; Path = 'HKCU\Z'; Name = 'Kurt2'; Exists = $true; Kind = 'DWord'; Data = 6; KeyExists = $true }) 'VirtualMachinePlatform'
Add-LiveUnrestored 'FeatWorkFolders' @(@{ K = 'Reg'; Path = 'HKCU\Z'; Name = 'Kurt'; Exists = $true; Kind = 'DWord'; Data = 5; KeyExists = $true }) 'ikinci kez'
$ul = @(Get-LiveUnrestored)
Assert-Eq $ul.Count 2 'aynı ayar listede bir kez tutulur'
Assert-True (Test-Path -LiteralPath (Get-LiveUnrestoredFile)) 'kurtarma listesi diske yazıldı'
# okuma kipi: yalnızca bildirir, dokunmaz
$script:LiveMode = ''; $env:MM_OZELLIK_KIP = 'oku'; $script:IsAdmin = $false
$rowsBefore = @($script:LiveRows).Count
Restore-LiveUnrestored
Assert-True (-not $script:FakeReg.ContainsKey('HKCU\Z|Kurt')) 'okuma kipi: kurtarma listesindeki değer yazılmaz'
Assert-Eq (@($script:LiveRows | Select-Object -Skip $rowsBefore | Where-Object { $_.Alan -eq 'kurtarma' -and $_.Durum -eq 'UYARI' })).Count 2 'okuma kipi: her bekleyen değişiklik uyarı olarak yazılır'
# tam kip: geri yükler, başarılıları listeden siler
$script:LiveMode = ''; $env:MM_OZELLIK_KIP = 'tam'; $script:IsAdmin = $true
$rowsBefore = @($script:LiveRows).Count
Restore-LiveUnrestored
Assert-Eq ([int]$script:FakeReg['HKCU\Z|Kurt'].Data) 5 'tam kip: kurtarma listesindeki değer geri yazıldı'
Assert-Eq (@($script:LiveRows | Select-Object -Skip $rowsBefore | Where-Object { $_.Alan -eq 'kurtarma' -and $_.Durum -eq 'OK' })).Count 2 'tam kip: geri yüklenenler OK'
Assert-Eq @(Get-LiveUnrestored).Count 0 'tam kip: başarılı olanlar listeden silindi'
Assert-True (-not (Test-Path -LiteralPath (Get-LiveUnrestoredFile))) 'liste boşalınca dosya silinir'
# yarım kalan tur geri yüklenemezse kaybolmaz: kurtarma listesine taşınır
Save-LiveInflight 'FeatX' @(@{ K = 'Feature'; Name = 'WorkFolders-Client'; State = 'Enabled' })
function Get-ServicingBusy { return '' }
function Get-LiveFeatSnap([string]$Name) { return @{ K = 'Feature'; Name = $Name; State = 'Disabled' } }
function Set-WinFeatureState([string]$Name, [bool]$On) { throw 'Windows Update zaman aşımı (sınama)' }
$rowsBefore = @($script:LiveRows).Count
Restore-LiveInflight
Assert-True (-not (Test-Path -LiteralPath (Join-Path (Get-LiveDir) 'ozellik-yarim.json'))) 'yarım kalan dosya işlendi'
Assert-Eq @(Get-LiveUnrestored).Count 1 'geri yüklenemeyen yarım tur kurtarma listesine taşındı'
Assert-True ((@($script:LiveRows | Select-Object -Skip $rowsBefore | Where-Object { $_.Durum -eq 'HATA' })).Count -ge 1) 'geri yüklenemeyince HATA yazılır'
# bileşen turu engeli: Windows Update kuruyorsa ya da bileşen servisi yeniden başlatma bekliyorsa tur yapılmaz
function Get-ServicingBusy { return $global:SvcBusy }
function Get-RegSubKeyNames([string]$Path) { return $global:CbsKeys }
$global:SvcBusy = ''; $global:CbsKeys = @('Packages', 'Version')
Assert-Eq (Get-LiveServicingBlock) '' 'engel yok: tur yapılabilir'
$global:CbsKeys = @('Packages', 'RebootPending')
Assert-True ((Get-LiveServicingBlock) -like '*yeniden başlatılmayı bekliyor*') 'bileşen servisi yeniden başlatma bekliyorsa tur yapılmaz'
$global:CbsKeys = @('Packages', 'PackagesPending')
Assert-True ((Get-LiveServicingBlock) -like '*PackagesPending*') 'bekleyen paket işlemi de engeldir'
$global:CbsKeys = @('RebootInProgress')
Assert-True ((Get-LiveServicingBlock) -like '*RebootInProgress*') 'süren yeniden başlatma işlemi de engeldir'
$global:CbsKeys = @('Packages', 'RebootPending')
$global:SvcBusy = 'Windows Update şu anda bir güncelleme kuruyor'
Assert-Eq (Get-LiveServicingBlock) 'Windows Update şu anda bir güncelleme kuruyor' 'Windows Update meşgulse o neden bildirilir'
Remove-Item function:Get-ServicingBusy -ErrorAction SilentlyContinue
Remove-Item function:Get-RegSubKeyNames -ErrorAction SilentlyContinue

# Windows özelliği turları: hepsi canlı denenir (hafifler önce, ağırlar sonra); başlangıç engeli bir kez okunur
$fl = @(
    (New-Cat 'FeatHyperV' @(@{ T = 'Feature'; Name = 'Microsoft-Hyper-V-All'; State = 'Disabled' }, @{ T = 'Feature'; Name = 'VirtualMachinePlatform'; State = 'Disabled' })),
    (New-Cat 'FeatIpp' @(@{ T = 'Feature'; Name = 'Printing-Foundation-InternetPrinting-Client'; State = 'Disabled' })),
    (New-Cat 'NoFeat' @(@{ T = 'Reg'; Path = 'HKCU\X'; Name = 'A' })),
    (New-Cat 'FeatNetFx3' @(@{ T = 'Feature'; Name = 'NetFx3'; State = 'Enabled' })),
    (New-Cat 'FeatWorkFolders' @(@{ T = 'Feature'; Name = 'WorkFolders-Client'; State = 'Disabled' })))
Assert-Eq ((@(Get-LiveFeatureOrder $fl) | ForEach-Object { [string]$_.Id }) -join ',') 'FeatIpp,FeatWorkFolders,FeatHyperV,FeatNetFx3' 'özellik turu sırası: hafifler önce, ağırlar sonra; özelliksiz ayar yok'
$global:Trips = New-Object System.Collections.ArrayList
function Invoke-LiveRoundTrip($C, [string]$Mode) { [void]$global:Trips.Add([string]$C.Id + ':' + $Mode) }
function Get-ServicingBusy { return $global:SvcBusy }
function Get-LiveServicingBlock { return $global:SvcBlock }
$global:SvcBusy = ''; $global:SvcBlock = ''; $script:LiveSvcBlock0 = ''; $script:LiveStopKinds = New-Object System.Collections.ArrayList
$rowsBefore = @($script:LiveRows).Count
Test-LiveFeatureTrips $fl
Assert-Eq (@($global:Trips) -join ',') 'FeatIpp:tam,FeatWorkFolders:tam,FeatHyperV:tam,FeatNetFx3:tam' 'tam kip: ağır özellikler dahil hepsi canlı denenir'
Assert-Eq (@($script:LiveRows | Select-Object -Skip $rowsBefore | Where-Object { [string]$_.Kimlik -like 'agir:*' -and $_.Durum -eq 'BILGI' })).Count 2 'ağır özellik turu önceden bilgi satırıyla duyurulur'
$global:Trips.Clear(); $script:LiveSvcBlock0 = 'Windows bir bileşen değişikliği için yeniden başlatılmayı bekliyor'
$rowsBefore = @($script:LiveRows).Count
Test-LiveFeatureTrips $fl
Assert-Eq (@($global:Trips) -join ',') 'FeatIpp:oku,FeatWorkFolders:oku,FeatHyperV:oku,FeatNetFx3:oku' 'başlangıçta yeniden başlatma bekleniyorsa özellikler değiştirilmez, yalnızca okunup önizlenir'
Assert-Eq (@($script:LiveRows | Select-Object -Skip $rowsBefore | Where-Object { $_.Durum -eq 'BILGI' -and [string]$_.Kimlik -like 'tur:*' })).Count 4 'her atlanan tur bilgi satırı yazar'
$global:Trips.Clear(); $script:LiveSvcBlock0 = ''; $global:SvcBusy = 'Windows Update şu anda bir güncelleme kuruyor'
Test-LiveFeatureTrips $fl
Assert-Eq @($global:Trips | Where-Object { $_ -like '*:tam' }).Count 0 'Windows Update kurulum yaparken tur yapılmaz'
Assert-Eq $global:Trips.Count 4 'Windows Update kurulum yaparken de her özellik önizlenir'
$global:Trips.Clear(); $global:SvcBusy = ''; $script:LiveStopKinds = New-Object System.Collections.ArrayList; [void]$script:LiveStopKinds.Add('Feature')
Test-LiveFeatureTrips $fl
Assert-Eq @($global:Trips | Where-Object { $_ -like '*:tam' }).Count 0 'bir özellik geri yüklenemediyse kalan özellik turları durur'
$script:LiveStopKinds = New-Object System.Collections.ArrayList

# özellik turunun güvenlik kuralları (cihaz bulgusu, 17.11.2026: Sanal Makine Platformu kapatılınca geri açılamadı)
$global:FeatState = @{ 'VirtualMachinePlatform' = 'Enabled'; 'Microsoft-Hyper-V-All' = ''; 'Printing-Foundation-InternetPrinting-Client' = 'Enabled'; 'NetFx3' = 'Disabled'; 'WorkFolders-Client' = 'Disabled' }
function Get-LiveFeatSnap([string]$Name) { return @{ K = 'Feature'; Name = $Name; State = [string]$global:FeatState[$Name] } }
Assert-Eq (Get-LiveFeatChange @{ Name = 'VirtualMachinePlatform'; State = 'Disabled' }) 'kapat' 'değişiklik yönü: açık özellik kapatılacak'
Assert-Eq (Get-LiveFeatChange @{ Name = 'NetFx3'; State = 'Enabled' }) 'ac' 'değişiklik yönü: kapalı özellik açılacak'
Assert-Eq (Get-LiveFeatChange @{ Name = 'WorkFolders-Client'; State = 'Disabled' }) '' 'değişiklik yönü: zaten istenen durumda'
Assert-Eq (Get-LiveFeatChange @{ Name = 'Microsoft-Hyper-V-All'; State = 'Disabled' }) '' 'değişiklik yönü: bu sürümde olmayan özellik değişmez'
$global:FeatState['Printing-Foundation-InternetPrinting-Client'] = 'EnablePending'
Assert-Eq (Get-LiveFeatChange @{ Name = 'Printing-Foundation-InternetPrinting-Client'; State = 'Disabled' }) 'kapat' 'yeniden başlatmada açılacak özellik açık sayılır'
$global:FeatState['Printing-Foundation-InternetPrinting-Client'] = 'Enabled'
Save-LiveUnrestoredList @()
try { Remove-Item -LiteralPath (Get-LiveRiskFile) -Force -ErrorAction SilentlyContinue } catch { }
$env:MM_OZELLIK_AGIR = ''
# 1) açık ağır özelliği kapatan tur varsayılan olarak yapılmaz (yalnızca okunur/önizlenir); hafif olan ve kapalı ağırı açan yapılır
$global:Trips.Clear(); $rowsBefore = @($script:LiveRows).Count
Test-LiveFeatureTrips $fl
Assert-Eq (@($global:Trips) -join ',') 'FeatIpp:tam,FeatWorkFolders:tam,FeatHyperV:oku,FeatNetFx3:tam' 'açık ağır özellik kapatılmaz; hafif özellik ve kapalı ağır özelliği açan tur yapılır'
$hr = @($script:LiveRows | Select-Object -Skip $rowsBefore | Where-Object { [string]$_.Kimlik -eq 'tur:FeatHyperV' -and $_.Durum -eq 'BILGI' })
Assert-True ($hr.Count -eq 1 -and [string]$hr[0].Ayrinti -like '*MM_OZELLIK_AGIR=1*') 'kapatılmayan ağır özellik nedeni ve bilerek deneme yolu yazılır'
# bilerek denenirse yapılır
$env:MM_OZELLIK_AGIR = '1'; $global:Trips.Clear()
Test-LiveFeatureTrips $fl
Assert-Eq (@($global:Trips | Where-Object { $_ -eq 'FeatHyperV:tam' })).Count 1 'MM_OZELLIK_AGIR=1: açık ağır özellik de canlı denenir'
# 2) bu bilgisayarda daha önce geri yüklenemeyen özellik bir daha değiştirilmez (bilerek deneme ayarı olsa bile)
Add-LiveRisky @(@{ K = 'Feature'; Name = 'VirtualMachinePlatform'; State = 'Enabled' }, @{ K = 'Reg'; Name = 'X' }) 'sınama: geri açılamadı'
Add-LiveRisky @(@{ K = 'Feature'; Name = 'VirtualMachinePlatform'; State = 'Enabled' }) 'ikinci kez'
Assert-Eq (@(Get-LiveRiskyNames) -join ',') 'VirtualMachinePlatform' 'risk listesi: yalnızca özellik/bileşen, her ad bir kez'
$global:Trips.Clear(); $rowsBefore = @($script:LiveRows).Count
Test-LiveFeatureTrips $fl
Assert-Eq (@($global:Trips | Where-Object { $_ -eq 'FeatHyperV:oku' })).Count 1 'riskli özellik: tur yalnızca önizlenir'
Assert-True ((@($script:LiveRows | Select-Object -Skip $rowsBefore | Where-Object { [string]$_.Ayrinti -like '*daha önce geri yüklenemedi*' })).Count -eq 1) 'riskli özelliğin nedeni yazılır'
$env:MM_OZELLIK_AGIR = ''
# risk listesi geçişi: kurtarma listesindeki ve yarım kalan özellikler de riskli sayılır
try { Remove-Item -LiteralPath (Get-LiveRiskFile) -Force -ErrorAction SilentlyContinue } catch { }
Save-LiveUnrestoredList @(@{ Id = 'FeatWorkFolders'; Time = 't'; Why = 'w'; Items = @(@{ K = 'Feature'; Name = 'WorkFolders-Client'; State = 'Enabled' }) })
Save-LiveInflight 'FeatHyperV' @(@{ K = 'Feature'; Name = 'VirtualMachinePlatform'; State = 'Enabled' })
Assert-Eq ((@(Get-LiveRiskyNames) | Sort-Object) -join ',') 'VirtualMachinePlatform,WorkFolders-Client' 'kurtarma listesindeki ve yarım kalan özellik riskli sayılır'
Clear-LiveInflight; Save-LiveUnrestoredList @()
# Add-LiveUnrestored risk listesine de yazar
Add-LiveUnrestored 'FeatIpp' @(@{ K = 'Feature'; Name = 'Printing-Foundation-InternetPrinting-Client'; State = 'Enabled' }) 'sınama'
Save-LiveUnrestoredList @()
Assert-True (@(Get-LiveRiskyNames) -contains 'Printing-Foundation-InternetPrinting-Client') 'geri yüklenemeyen özellik kalıcı risk listesine yazılır (kurtarma listesi boşalsa da)'
try { Remove-Item -LiteralPath (Get-LiveRiskFile) -Force -ErrorAction SilentlyContinue } catch { }
# 3) bileşen hizmeti meşgulse tur başlamaz ve kalan DISM turları durur
function Wait-LiveCbsIdle([int]$MaxSec = 180) { return $global:CbsBusy }
$global:CbsBusy = 'dism'; $global:Trips.Clear(); $script:LiveStopKinds = New-Object System.Collections.ArrayList; $rowsBefore = @($script:LiveRows).Count
Test-LiveFeatureTrips $fl
Assert-Eq @($global:Trips | Where-Object { $_ -like '*:tam' }).Count 0 'bileşen hizmeti meşgulken özellik turu yapılmaz'
Assert-True (($script:LiveStopKinds -contains 'Feature') -and ($script:LiveStopKinds -contains 'Cap')) 'bileşen hizmeti meşgulse özellik ve bileşen turları durur'
Assert-True ((@($script:LiveRows | Select-Object -Skip $rowsBefore | Where-Object { [string]$_.Ayrinti -like '*bileşen hizmeti önceki işi sürdürüyor (dism)*' })).Count -eq 1) 'meşgul neden yazılır'
$global:CbsBusy = ''; $script:LiveStopKinds = New-Object System.Collections.ArrayList
# 4) bir tur DISM süre sınırını aşarsa kalan DISM turları yapılmaz
function Invoke-LiveRoundTrip($C, [string]$Mode) { [void]$global:Trips.Add([string]$C.Id + ':' + $Mode); if ($Mode -eq 'tam') { $script:DismTimedOut = $true } }
$script:DismTimedOut = $false; $global:Trips.Clear(); $rowsBefore = @($script:LiveRows).Count
Test-LiveFeatureTrips $fl
Assert-Eq (@($global:Trips) -join ',') 'FeatIpp:tam,FeatWorkFolders:oku,FeatHyperV:oku,FeatNetFx3:oku' 'DISM süre sınırını aşınca kalan özellik turları yalnızca önizlenir'
Assert-True ((@($script:LiveRows | Select-Object -Skip $rowsBefore | Where-Object { [string]$_.Kimlik -eq 'dism:FeatIpp' -and $_.Durum -eq 'UYARI' })).Count -eq 1) 'DISM süre aşımı uyarısı bir kez yazılır'
$script:DismTimedOut = $false; $script:LiveStopKinds = New-Object System.Collections.ArrayList; $script:LiveSvcBlock0 = $null
# 5) bu denetimde önceki bir tur yeniden başlatma bıraktıysa özelliği KAPATAN tur yapılmaz; açan tur yapılır
#    (cihazda 18.11.2026: XPS turundan sonra İş Klasörleri kapatıldı ve 0x371B ile geri açılamadı)
function Wait-LiveCbsIdle([int]$MaxSec = 180) { return '' }
function Get-CbsRebootPending { return $global:CbsPend }
function Invoke-LiveRoundTrip($C, [string]$Mode) { [void]$global:Trips.Add([string]$C.Id + ':' + $Mode); if ($Mode -eq 'tam' -and [string]$C.Id -eq 'FeatIpp') { $global:CbsPend = 'RebootPending' } }
$global:FeatState['WorkFolders-Client'] = 'Enabled'
$global:CbsPend = ''; $script:DismNeedsReboot = $false; $script:DismTimedOut = $false; $global:Trips.Clear(); $rowsBefore = @($script:LiveRows).Count
Test-LiveFeatureTrips $fl
Assert-Eq (@($global:Trips) -join ',') 'FeatIpp:tam,FeatWorkFolders:oku,FeatHyperV:oku,FeatNetFx3:tam' 'önceki tur yeniden başlatma bıraktıysa kapatan tur önizlenir, açan tur yapılır'
$pr = @($script:LiveRows | Select-Object -Skip $rowsBefore | Where-Object { [string]$_.Kimlik -eq 'tur:FeatWorkFolders' -and $_.Durum -eq 'BILGI' })
Assert-True ($pr.Count -eq 1 -and [string]$pr[0].Ayrinti -like '*yeniden başlatma bekliyor (RebootPending)*WorkFolders-Client canlı kapatılmadı*') 'atlanan turun nedeni yazılır'
$global:CbsPend = ''; $script:DismNeedsReboot = $true; $global:Trips.Clear()
Test-LiveFeatureTrips $fl
Assert-Eq (@($global:Trips) -join ',') 'FeatIpp:oku,FeatWorkFolders:oku,FeatHyperV:oku,FeatNetFx3:tam' 'DISM "önce yeniden başlatın" dediyse kapatan turlar önizlenir'
$script:DismNeedsReboot = $false; $global:CbsPend = ''; $global:FeatState['WorkFolders-Client'] = 'Disabled'
$script:LiveStopKinds = New-Object System.Collections.ArrayList; $script:LiveSvcBlock0 = $null
Remove-Item function:Get-CbsRebootPending -ErrorAction SilentlyContinue
Import-Fn 'Get-CbsRebootPending'
# Windows bileşenini de kaldıran öğe varsayılan olarak yalnızca önizlenir (cihazda 18.11.2026: XPS Görüntüleyici ve
# Adım Kaydedicisi Windows Update'ten 0x800F0950 ile geri kurulamadı); MM_BILESEN_CANLI=1 ile canlı denenir
$script:LiveCapWhy = 'neden'
function Get-LiveCapState([string]$M) { return [string]$global:CapSt[$M] }
$global:CapSt = @{ 'XPS.Viewer' = 'kurulu' }
$flx = @((New-Cat 'FeatXps' @(@{ T = 'Feature'; Name = 'Printing-XPSServices-Features'; State = 'Disabled' }, @{ T = 'Cap'; Match = 'XPS.Viewer'; State = 'Absent' })))
$global:FeatState['Printing-XPSServices-Features'] = 'Disabled'
function Invoke-LiveRoundTrip($C, [string]$Mode) { [void]$global:Trips.Add([string]$C.Id + ':' + $Mode) }
$env:MM_BILESEN_CANLI = $null; $global:Trips.Clear(); $rowsBefore = @($script:LiveRows).Count
Test-LiveFeatureTrips $flx
Assert-Eq (@($global:Trips) -join ',') 'FeatXps:oku' 'bileşen kaldıran öğe varsayılan olarak yalnızca önizlenir'
$xr = @($script:LiveRows | Select-Object -Skip $rowsBefore | Where-Object { [string]$_.Kimlik -eq 'tur:FeatXps' -and $_.Durum -eq 'BILGI' })
Assert-True ($xr.Count -eq 1 -and [string]$xr[0].Ayrinti -like '*kaldırma canlı denenmedi (XPS.Viewer)*MM_BILESEN_CANLI=1*') 'neden ve seçenek yazılır'
$env:MM_BILESEN_CANLI = '1'; $global:Trips.Clear()
Test-LiveFeatureTrips $flx
Assert-Eq (@($global:Trips) -join ',') 'FeatXps:tam' 'MM_BILESEN_CANLI=1 ile canlı denenir'
$env:MM_BILESEN_CANLI = $null
$global:CapSt['XPS.Viewer'] = 'kaldirilmis'; $global:Trips.Clear()
Test-LiveFeatureTrips $flx
Assert-Eq (@($global:Trips) -join ',') 'FeatXps:tam' 'bileşen zaten kaldırılmışsa tur engellenmez (kaldırılacak bir şey yok)'
Assert-Eq @(Get-LiveCapRemovals (New-Cat 'X' @(@{ T = 'Cap'; Match = 'XPS.Viewer'; State = 'Installed' }))).Count 0 'kuran bileşen işlemi kaldırma sayılmaz'
Remove-Item function:Get-LiveCapState -ErrorAction SilentlyContinue
Import-Fn 'Get-LiveCapState'
# tur sırası: kapatanlar önce, açanlar sonra, Windows bileşenini de kaldıranlar en son (her grupta hafifler önce)
$fl2 = @(
    (New-Cat 'FeatXps' @(@{ T = 'Feature'; Name = 'Printing-XPSServices-Features'; State = 'Disabled' }, @{ T = 'Cap'; Match = 'XPS.Viewer'; State = 'NotPresent' })),
    (New-Cat 'FeatNetFx3' @(@{ T = 'Feature'; Name = 'NetFx3'; State = 'Enabled' })),
    (New-Cat 'FeatTelnetOn' @(@{ T = 'Feature'; Name = 'TelnetClient'; State = 'Enabled' })),
    (New-Cat 'FeatWorkFolders' @(@{ T = 'Feature'; Name = 'WorkFolders-Client'; State = 'Disabled' })),
    (New-Cat 'FeatHyperV' @(@{ T = 'Feature'; Name = 'VirtualMachinePlatform'; State = 'Disabled' })))
Assert-Eq ((@(Get-LiveFeatureOrder $fl2) | ForEach-Object { [string]$_.Id }) -join ',') 'FeatWorkFolders,FeatHyperV,FeatTelnetOn,FeatNetFx3,FeatXps' 'sıra: kapatan turlar önce, açanlar sonra, bileşeni de kaldıranlar en son'
Remove-Item function:Wait-LiveCbsIdle -ErrorAction SilentlyContinue
Import-Fn 'Wait-LiveCbsIdle'
Assert-Eq (Wait-LiveCbsIdle 1) '' 'bileşen hizmeti süreçleri yokken beklemeden döner'
Assert-Eq (Get-LiveProcNames @('mm-olmayan-surec-xyz')) '' 'çalışmayan süreç adı boş döner'
Assert-True (Test-LiveDismItem @{ K = 'Feature' }) 'özellik öğesi DISM gerektirir'
Assert-True (-not (Test-LiveDismItem @{ K = 'Reg' })) 'kayıt defteri öğesi DISM gerektirmez'
# 5) başlangıç kurtarması: engel varsa DISM gerektiren öğe denenmez, listede kalır; başarısız ad ikinci kez denenmez
$global:FeatState['WorkFolders-Client'] = 'Disabled'
$global:FeatCalls = New-Object System.Collections.ArrayList
function Set-WinFeatureState([string]$Name, [bool]$On) { [void]$global:FeatCalls.Add($Name + '=' + $On); if ($global:FeatFail) { throw ('sınama: açılamadı ' + $Name) }; return $false }
$global:FeatFail = $false; $script:LiveRestoreFailed.Clear()
$script:LiveMode = ''; $env:MM_OZELLIK_KIP = 'tam'; $script:IsAdmin = $true
Save-LiveUnrestoredList @(@{ Id = 'FeatWorkFolders'; Time = 't'; Why = 'w'; Items = @(@{ K = 'Feature'; Name = 'WorkFolders-Client'; State = 'Enabled' }) })
$global:SvcBlock = 'Windows bir bileşen değişikliği için yeniden başlatılmayı bekliyor (RebootPending)'
$rowsBefore = @($script:LiveRows).Count
Restore-LiveUnrestored
Assert-Eq $global:FeatCalls.Count 0 'yeniden başlatma beklenirken özellik geri yüklemesi denenmez'
Assert-Eq @(Get-LiveUnrestored).Count 1 'denenmeyen öğe kurtarma listesinde kalır'
Assert-True ((@($script:LiveRows | Select-Object -Skip $rowsBefore | Where-Object { $_.Durum -eq 'UYARI' -and [string]$_.Ayrinti -like '*yeniden başlatıp*' })).Count -eq 1) 'bekletilen geri yükleme yeniden başlatma önerisiyle yazılır'
Assert-True ($script:LiveStopKinds -contains 'Feature') 'bekletilen özellik varken özellik turları durur'
# öğe zaten eski durumundaysa (ör. elle geri açıldı) yeniden başlatma beklense de listeden düşer, DISM çağrılmaz
$global:FeatState['WorkFolders-Client'] = 'Enabled'
$rowsBefore = @($script:LiveRows).Count
Restore-LiveUnrestored
Assert-Eq $global:FeatCalls.Count 0 'zaten eski durumundaki özellik için DISM çağrılmaz'
Assert-Eq @(Get-LiveUnrestored).Count 0 'zaten eski durumundaki özellik kurtarma listesinden çıkar'
Assert-True ((@($script:LiveRows | Select-Object -Skip $rowsBefore | Where-Object { $_.Durum -eq 'OK' -and [string]$_.Ayrinti -like '*zaten eski durumunda*' })).Count -eq 1) 'zaten eski durumda satırı yazılır'
# bileşen içeriği bu derleme için Windows Update'te yoksa (0x800F0950) aynı derlemede 3 gün dolmadan yeniden denenmez
# (gerçek bilgisayar 18.11.2026: Adım Kaydedicisi önizleme derlemesinde geri kurulamadı, her tam denetim aynı hatayı yazacaktı)
$nowT = [datetime]'2026-11-24T10:00:00'
$eD = [pscustomobject]@{ Id = 'FeatStepsRec'; Time = '2026-11-18T22:52:12'; Why = 'App.StepsRecorder: içerik bulunamadı (0x800F0950)'; Build = '26300.9974'; Tried = '2026-11-24T08:00:00'; Items = @() }
Assert-True (Test-LiveRetryDeferred $eD '26300.9974' $nowT) 'bileşen: aynı derlemede 3 günden yeni 0x800F0950 ertelenir'
Assert-True (-not (Test-LiveRetryDeferred $eD '26300.10001' $nowT)) 'bileşen: derleme değişince yeniden denenir'
Assert-True (-not (Test-LiveRetryDeferred $eD '26300.9974' ([datetime]'2026-11-28T10:00:00'))) 'bileşen: 3 gün geçince yeniden denenir'
Assert-True (-not (Test-LiveRetryDeferred ([pscustomobject]@{ Why = 'Windows Update zaman aşımı'; Build = '26300.9974'; Tried = '2026-11-24T08:00:00' }) '26300.9974' $nowT)) 'bileşen: başka hata ertelenmez'
Assert-True (-not (Test-LiveRetryDeferred ([pscustomobject]@{ Why = 'x 0x800F0950'; Build = ''; Tried = '' }) '26300.9974' $nowT)) 'bileşen: derlemesi kaydedilmemiş eski kayıt yeniden denenir'
Assert-True (Test-LiveRetryDeferred ([pscustomobject]@{ Why = 'x 0x800F0950'; Build = '26300.9974'; Tried = ([datetime]'2026-11-24T09:00:00') }) '26300.9974' $nowT) 'bileşen: tarih nesnesi olarak okunan deneme zamanı da çalışır'
Assert-True (-not (Test-LiveRetryDeferred ([pscustomobject]@{ Why = 'x 0x800F0950'; Build = '26300.9974'; Tried = 'bozuk' }) '26300.9974' $nowT)) 'bileşen: okunamayan deneme zamanı ertelemez'
# başlangıç kurtarması: eski kayıt bir kez denenir; 0x800F0950 ile başarısız olunca UYARI yazılır, derleme ve deneme zamanı kaydedilir
function Get-LiveBuildTag { return '26300.9974' }
$global:CapCalls = New-Object System.Collections.ArrayList
function Set-WinCapabilityState([string]$Name, [bool]$On) { [void]$global:CapCalls.Add($Name + '=' + $On); throw ('sınama: ' + $Name + ': içerik bu Windows sürümü için bulunamadı (0x800F0950)') }
function Get-LiveCapState([string]$Name) { return 'yok' }
$global:SvcBlock = ''
$script:LiveRestoreFailed.Clear(); $script:LiveStopKinds.Clear()
Save-LiveUnrestoredList @(@{ Id = 'FeatStepsRec'; Time = '2026-11-18T22:52:12'; Why = 'bileşen geri kurulamadı: App.StepsRecorder'; Items = @(@{ K = 'Cap'; Name = 'App.StepsRecorder'; Data = 'kurulu' }) })
$rowsBefore = @($script:LiveRows).Count
Restore-LiveUnrestored
Assert-Eq $global:CapCalls.Count 1 'bileşen: derlemesi kaydedilmemiş kayıt bir kez denenir'
$newRows = @($script:LiveRows | Select-Object -Skip $rowsBefore | Where-Object { $_.Alan -eq 'kurtarma' })
Assert-True ($newRows.Count -eq 1 -and [string]$newRows[0].Durum -eq 'UYARI') ('bileşen: içerik yoksa (0x800F0950) HATA değil UYARI: ' + (@($newRows | ForEach-Object { [string]$_.Durum }) -join ','))
$ul2 = @(Get-LiveUnrestored)
Assert-True ($ul2.Count -eq 1 -and [string]$ul2[0].Build -eq '26300.9974' -and [string]$ul2[0].Why -match '0x800F0950' -and [string]$ul2[0].Tried -ne '' -and ([string]$ul2[0].Time -eq '2026-11-18T22:52:12' -or ($ul2[0].Time -is [datetime] -and $ul2[0].Time -eq [datetime]'2026-11-18T22:52:12'))) 'bileşen: derleme, deneme zamanı ve son hata kaydedilir, ilk zaman korunur'
Assert-True (@($ul2[0].Items).Count -eq 1 -and [string]@($ul2[0].Items)[0].Name -eq 'App.StepsRecorder') 'bileşen: kayıttaki öğe korunur'
# aynı derlemede hemen ardından: denenmez, UYARI ile bildirilir, listede kalır
$script:LiveRestoreFailed.Clear()
$rowsBefore = @($script:LiveRows).Count
Restore-LiveUnrestored
Assert-Eq $global:CapCalls.Count 1 'bileşen: aynı derlemede yeniden denenmez'
$newRows = @($script:LiveRows | Select-Object -Skip $rowsBefore | Where-Object { $_.Alan -eq 'kurtarma' })
Assert-True ($newRows.Count -eq 1 -and [string]$newRows[0].Durum -eq 'UYARI' -and [string]$newRows[0].Ayrinti -like '*Windows güncellenince*') 'bileşen: ertelenen deneme bildirilir'
Assert-Eq @(Get-LiveUnrestored).Count 1 'bileşen: ertelenen kayıt listede kalır'
# derleme değişince yeniden denenir
function Get-LiveBuildTag { return '26300.10001' }
$script:LiveRestoreFailed.Clear()
Restore-LiveUnrestored
Assert-Eq $global:CapCalls.Count 2 'bileşen: Windows güncellenince yeniden denenir'
# başka bir hatayla başarısız olan geri yükleme HATA olarak kalır
function Set-WinCapabilityState([string]$Name, [bool]$On) { [void]$global:CapCalls.Add($Name + '=' + $On); throw 'sınama: ağ yok' }
$script:LiveRestoreFailed.Clear()
Save-LiveUnrestoredList @(@{ Id = 'FeatStepsRec'; Time = 't'; Why = 'w'; Items = @(@{ K = 'Cap'; Name = 'App.StepsRecorder'; Data = 'kurulu' }) })
$rowsBefore = @($script:LiveRows).Count
Restore-LiveUnrestored
$newRows = @($script:LiveRows | Select-Object -Skip $rowsBefore | Where-Object { $_.Alan -eq 'kurtarma' })
Assert-True ($newRows.Count -eq 1 -and [string]$newRows[0].Durum -eq 'HATA') 'bileşen: başka nedenle geri yüklenemeyen HATA kalır'
Save-LiveUnrestoredList @()
$script:LiveRestoreFailed.Clear(); $script:LiveStopKinds.Clear()
Remove-Item function:\Set-WinCapabilityState, function:\Get-LiveCapState, function:\Get-LiveBuildTag -ErrorAction SilentlyContinue
Import-Fn 'Get-LiveCapState', 'Get-LiveBuildTag'
Assert-True (Test-LiveItemCurrent @{ K = 'Feature'; Name = 'WorkFolders-Client'; State = 'Enabled' }) 'güncel durum denetimi: açık'
Assert-True (-not (Test-LiveItemCurrent @{ K = 'Feature'; Name = 'NetFx3'; State = 'Enabled' })) 'güncel durum denetimi: kapalı özellik açık istenmiş'
Assert-True (-not (Test-LiveItemCurrent @{ K = 'Reg'; Name = 'X' })) 'güncel durum denetimi: kayıt öğesi DISM dışı'
$global:FeatState['WorkFolders-Client'] = 'Disabled'
Save-LiveUnrestoredList @(@{ Id = 'FeatWorkFolders'; Time = 't'; Why = 'w'; Items = @(@{ K = 'Feature'; Name = 'WorkFolders-Client'; State = 'Enabled' }) })
$global:SvcBlock = ''; $script:LiveStopKinds = New-Object System.Collections.ArrayList; $global:FeatFail = $true
Restore-LiveUnrestored
Assert-Eq (@($global:FeatCalls) -join ',') 'WorkFolders-Client=True' 'engel kalkınca geri yükleme denenir'
Assert-True ($script:LiveRestoreFailed.Contains('WorkFolders-Client')) 'başarısız geri yükleme bu denetimde işaretlenir'
Save-LiveInflight 'FeatWorkFolders' @(@{ K = 'Feature'; Name = 'WorkFolders-Client'; State = 'Enabled' })
Restore-LiveInflight
Assert-Eq $global:FeatCalls.Count 1 'aynı özellik aynı denetimde ikinci kez (uzun süre) denenmez'
Assert-Eq @(Get-LiveUnrestored).Count 1 'ikinci kez denenmeyen yarım öğe kurtarma listesinde tek kayıt olarak kalır'
$global:FeatFail = $false; $script:LiveRestoreFailed.Clear(); $script:LiveStopKinds = New-Object System.Collections.ArrayList
Save-LiveUnrestoredList @(); Clear-LiveInflight
try { Remove-Item -LiteralPath (Get-LiveRiskFile) -Force -ErrorAction SilentlyContinue } catch { }
$script:LiveMode = ''; $env:MM_OZELLIK_KIP = 'oku'; $script:IsAdmin = $false
function Get-LiveFeatSnap([string]$Name) { return @{ K = 'Feature'; Name = $Name; State = 'Disabled' } }
Remove-Item function:Set-WinFeatureState -ErrorAction SilentlyContinue
Remove-Item function:Invoke-LiveRoundTrip -ErrorAction SilentlyContinue
Remove-Item function:Get-ServicingBusy -ErrorAction SilentlyContinue
Remove-Item function:Get-LiveServicingBlock -ErrorAction SilentlyContinue
Import-Fn 'Get-LiveServicingBlock'

# Windows özelliği geri yükleme: yalnızca durum farklıysa DISM çağrılır
$global:FeatCalls = New-Object System.Collections.ArrayList
function Set-WinFeatureState([string]$Name, [bool]$On) { [void]$global:FeatCalls.Add($Name + '=' + $On); return $false }
Restore-LiveItem @{ K = 'Feature'; Name = 'WorkFolders-Client'; State = 'Enabled' }
Assert-Eq (@($global:FeatCalls) -join ',') 'WorkFolders-Client=True' 'özellik açık olmalıydı ama kapalı: açılır'
$global:FeatCalls.Clear()
Restore-LiveItem @{ K = 'Feature'; Name = 'WorkFolders-Client'; State = 'Disabled' }
Assert-Eq $global:FeatCalls.Count 0 'durum zaten aynıysa DISM çağrılmaz'
Restore-LiveItem @{ K = 'Feature'; Name = 'Microsoft-Hyper-V-All'; State = '' }
Assert-Eq $global:FeatCalls.Count 0 'bu sürümde olmayan özelliğe dokunulmaz'
Save-LiveUnrestoredList @()
$script:LiveMode = ''; $env:MM_OZELLIK_KIP = 'oku'; $script:IsAdmin = $false
Remove-Item function:Get-LiveFeatSnap -ErrorAction SilentlyContinue
Remove-Item function:Set-WinFeatureState -ErrorAction SilentlyContinue

# ======================= 4) satır yazımı, sayaçlar, TSV =======================
$script:LiveRows.Clear(); $script:SmokeErrs2.Clear(); $script:SmokeWarns2.Clear(); $script:SmokeLines.Clear()
$script:LiveTsv = ''
$tsvPath = Join-Path ([System.IO.Path]::GetTempPath()) 'Multimizer-duman-ozellik.tsv'
if (Test-Path -LiteralPath $tsvPath) { Remove-Item -LiteralPath $tsvPath -Force }
Add-LiveRow 'a' 'x1' 'OK' 'tamam'
Add-LiveRow 'a' 'x2' 'HATA' "satır`nsonu`tvar"
Add-LiveRow 'b' 'x3' 'UYARI' 'dikkat'
Add-LiveRow 'b' 'x4' 'BILGI' 'bilgi'
Assert-Eq (Get-LiveCount 'OK') 1 'sayaç: tamam'
Assert-Eq (Get-LiveCount 'HATA') 1 'sayaç: hata'
Assert-Eq $script:SmokeErrs2.Count 1 'HATA satırı duman hatası sayılır'
Assert-Eq $script:SmokeWarns2.Count 1 'UYARI satırı duman uyarısı sayılır'
Assert-True ($script:SmokeErrs2[0] -notmatch "[\r\n\t]") 'satır sonu ve sekme ayrıntıdan temizlenir'
$tsv = [System.IO.File]::ReadAllLines($tsvPath)
Assert-Eq $tsv.Count 5 'TSV: başlık + 4 satır'
Assert-True ($tsv[0] -like 'Alan*Kimlik*Durum*') 'TSV başlığı'

# ======================= 5) günlük yakalama =======================
$mk = Get-LiveLogMark
Write-WhLog 'birinci' 'INFO'
Write-WhLog 'ikinci hata' 'ERR'
Write-WhLog 'plan satırı' 'PLAN'
$ln = Get-LiveLogSince $mk
Assert-Eq $ln.Count 3 'günlük: işaretten sonraki satırlar'
$lnE = Select-LiveLines $ln 'ERR'
$lnP = Select-LiveLines $ln 'PLAN'
$lnN = Select-LiveLines (Get-LiveLogSince (Get-LiveLogMark)) 'ERR'
Assert-Eq $lnE.Count 1 'günlük: ERR süzgeci'
Assert-Eq $lnP.Count 1 'günlük: PLAN süzgeci'
Assert-Eq $lnN.Count 0 'günlük: işaret sonrası boş'

# ======================= 6) iş çağrısı =======================
function Job_Deneme1($P) { return @{ Ok = $true; Rows = @(1, 2, 3) } }
function Job_Deneme2($P) { throw 'patladı' }
function Job_Deneme3($P) { Write-Output 'metin'; return @{ Ok = $true } }
$r1 = Invoke-LiveJob 'Job_Deneme1' @{}
Assert-True ($r1.Err -eq '' -and $r1.Out.Ok -eq $true) 'iş: normal sonuç'
$r2 = Invoke-LiveJob 'Job_Deneme2' @{}
Assert-True ($r2.Err -like '*patladı*') 'iş: çöken iş yakalanır'
$r3 = Invoke-LiveJob 'Job_Deneme3' @{}
Assert-True ($r3.Out -is [hashtable] -and $r3.Out.Ok -eq $true) 'iş: çıktı akışına yazılan metin sonucu bozmaz'
Assert-Eq (Get-LiveResultSummary @{ Ok = $true; Rows = @(1, 2, 3); Ad = 'x' }) 'Ad=x Ok=True Rows=3' 'sonuç özeti'
Assert-Eq (Get-LiveResultSummary $null) 'sonuç boş' 'sonuç özeti: boş'

# ======================= 7) araçlar (gerçek dosyalarla) =======================
$script:LiveRows.Clear(); $script:SmokeErrs2.Clear()
Test-LivePassword
$pw = @($script:LiveRows | Where-Object { $_.Kimlik -eq 'parola' })
Assert-Eq $pw.Count 1 'parola denemesi bir satır yazar'
Assert-Eq $pw[0].Durum 'OK' ('parola denemesi geçer: ' + $pw[0].Ayrinti)

$script:LiveRows.Clear()
$script:SmokeExpect.Clear()
$global:MmCryptIter = 12000   # sınama hızı için (çözücü 10000'in altını reddeder); biçim aynı
Test-LiveCrypt
$cr = @($script:LiveRows | Where-Object { $_.Kimlik -eq 'sifreleme' })
Assert-Eq $cr.Count 1 'şifreleme denemesi bir satır yazar'
Assert-Eq $cr[0].Durum 'OK' ('şifreleme denemesi geçer: ' + $cr[0].Ayrinti)
# olumsuz denemeler (yanlış parola, bozuk dosya, kısa parola) günlüğe ERR yazar; bunlar "beklenen satır" olarak kaydedilmiş olmalı
Assert-Eq $script:SmokeExpect.Count 3 'şifreleme: üç olumsuz deneme için beklenen günlük satırı kaydedildi'
$logTxt = [System.IO.File]::ReadAllText($logFile)
foreach ($ln in ($logTxt -split "`r?`n")) { if ($ln -match '^\d\d:\d\d:\d\d\s+ERR\s') { [void](Test-SmokeExpected $ln) } }
Assert-Eq (@(Get-SmokeExpectMissing) -join ' | ') '' 'şifreleme: olumsuz denemelerin üçü de günlüğe yazıldı ve beklenenlerle eşleşti'

$script:LiveRows.Clear()
Test-LiveSecureDelete
$sd = @($script:LiveRows | Where-Object { $_.Kimlik -eq 'guvenli-silme' })
Assert-Eq $sd.Count 1 'güvenli silme denemesi bir satır yazar'
Assert-Eq $sd[0].Durum 'OK' ('güvenli silme denemesi geçer: ' + $sd[0].Ayrinti)

# sahte motor: Job_Plan / Job_Undo yalnızca "Rename" işlemini çalıştırır (gerçek motor Windows'ta sınanır)
$script:Preview = $false; $script:Silent = $false; $script:JItems = $null; $script:FakeErr = 0
function Add-Plan($t) { }
function Add-Skip($t) { }
function Add-Done($t) { }
function Add-Err($t) { $script:FakeErr++ }
function Add-Journal($it) { [void]$script:JItems.Add($it) }
function Job_Plan($P) {
    $script:JItems = New-Object System.Collections.ArrayList
    $script:Preview = ($P.Preview -eq $true)
    $script:FakeErr = 0
    $chg = 0
    foreach ($s in @($P.Steps)) { foreach ($op in @($s.Ops)) { if ([string]$op.T -eq 'Rename') { Invoke-RenameOp $op; $chg += @($op.Pairs).Count } } }
    if (-not $script:Preview -and $script:JItems.Count -gt 0) {
        $f = Join-Path $sync.BackupDir ('yedek-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '.jsonl')
        [System.IO.File]::WriteAllText($f, ((@($script:JItems) | ForEach-Object { ConvertTo-Json -InputObject $_ -Depth 6 -Compress }) -join "`n"))
    }
    return @{ Changes = $chg; Skipped = 0; Errors = $script:FakeErr }
}
function Job_Undo($P) {
    $script:FakeErr = 0
    foreach ($ln2 in [System.IO.File]::ReadAllLines([string]$P.File)) { if ($ln2.Trim() -ne '') { Undo-RenameItem (ConvertFrom-Json $ln2) } }
    return @{ Errors = $script:FakeErr }
}
$script:LiveRows.Clear()
Test-LiveRename
$rn = @($script:LiveRows | Where-Object { $_.Kimlik -eq 'adlandir' })
Assert-Eq $rn.Count 1 'yeniden adlandırma denemesi bir satır yazar'
Assert-Eq $rn[0].Durum 'OK' ('yeniden adlandırma denemesi geçer: ' + $rn[0].Ayrinti)

# ======================= 8) iş listesi ve yönlendirici =======================
$jobs = @(Get-LiveReadJobs)
Assert-True ($jobs.Count -ge 40) ('okuma işleri listesi dolu: ' + $jobs.Count)
$groups = @($jobs | ForEach-Object { $_.Group } | Sort-Object -Unique)
foreach ($g in @('sistem', 'depolama', 'guncelleme', 'ag', 'oyun', 'saglik')) { Assert-True ($groups -contains $g) ('iş grubu var: ' + $g) }
# listedeki her iş ana betikte gerçekten tanımlı olmalı (adı yanlış yazılmış bir iş "bu sürümde yok" diye sessizce atlanırdı)
$ast = $script:Ast
$defined = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Name -replace '^global:', '' })
$missing = @($jobs | Where-Object { $defined -notcontains [string]$_.Fn } | ForEach-Object { $_.Fn })
Assert-Eq ($missing -join ',') '' 'okuma işlerinin hepsi tanımlı'
# her iş yalnızca bir kez listelenir
$dup = @($jobs | Group-Object { $_.Fn } | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
Assert-Eq ($dup -join ',') '' 'okuma işleri tekrar etmiyor'
# listede eylem işi (kalıcı değişiklik yapanlar) bulunmamalı
$actionJobs = @('Job_Plan', 'Job_Undo', 'Job_UndoAll', 'Job_Repair', 'Job_Maint', 'Job_Kill', 'Job_Restore', 'Job_Backup', 'Job_Uninstall', 'Job_Install', 'Job_ServiceAction', 'Job_WuInstall', 'Job_WuUninstall', 'Job_NetReset', 'Job_VpnAction', 'Job_FixAll', 'Job_Guard', 'Job_WingetUpgrade', 'Job_WingetInstall', 'Job_PublicWifi', 'Job_ProfileApply', 'Job_SlvDiskOp', 'Job_RecycleFiles', 'Job_RecycleRestore', 'Job_BitLockerEnable', 'Job_BitLockerAddKey', 'Job_GameBoost', 'Job_Focus', 'Job_Priority')
$bad = @($jobs | Where-Object { $actionJobs -contains [string]$_.Fn } | ForEach-Object { $_.Fn })
Assert-Eq ($bad -join ',') '' 'okuma listesinde eylem işi yok'
# SmartZero yalnızca önizleme olarak çağrılır
$sz = @($jobs | Where-Object { $_.Fn -eq 'Job_SmartZero' })
Assert-True ($sz.Count -eq 1 -and $sz[0].Arg.Preview -eq $true) 'SmartZero yalnızca önizleme'

$script:LiveRows.Clear(); $script:SmokeErrs2.Clear()
Test-SmokeLive 'bilinmeyen'
Assert-True ((@($script:LiveRows | Where-Object { $_.Durum -eq 'HATA' })).Count -ge 1) 'bilinmeyen bölüm hata sayılır'
$script:LiveRows.Clear(); $script:SmokeErrs2.Clear()
Test-LiveJobs 'sistem'   # Linux'ta işler yok ya da çöker; yönlendirici ve sarmalayıcı çökmemeli
Assert-True ($script:LiveRows.Count -ge 1) 'iş taraması satır yazar'

# ======================= 9) okuma bekçisi =======================
# Okuma işleri sisteme yazmaya kalkarsa bekçi işlemi yapmadan engeller ve HATA olarak bildirir; iş bitince asıl komutlar eski haline döner.
. ([scriptblock]::Create(@'
function Invoke-Op($Op) { $global:FakeOpCalls++; return 'gercek-op' }
function Invoke-Plan($Steps, [bool]$RestorePoint) { $global:FakePlanCalls++; foreach ($s in @($Steps)) { Invoke-Op $s } }
function Job_YazanTest($P) {
    Set-Service -Name 'Foo' -StartupType Disabled
    Set-RegData 'HKCU\Bekci' 'Y' 'DWord' 1
    Stop-Process -Id 99999 -ErrorAction SilentlyContinue
    Invoke-Op @{ T = 'Reg'; Name = 'n'; Path = 'p' }
    Invoke-Plan @(@{ T = 'Reg' }) $false
    return @{ Ok = $true }
}
function Job_OnizlemeTest($P) {
    $script:Preview = $true
    Invoke-Plan @(@{ T = 'Reg' }, @{ T = 'Svc' }) $false
    return @{ Ok = $true; Preview = $true }
}
function Job_TemizTest($P) { return @{ Ok = $true; Rows = 3 } }
function Job_KsContext($P) { return @{ Ok = $false; Why = 'Etkin VPN yok' } }
function Job_BasarisizTest($P) { return @{ Ok = $false; Errors = 2 } }
'@))
foreach ($n in @('Invoke-Op', 'Invoke-Plan', 'Job_YazanTest', 'Job_OnizlemeTest', 'Job_TemizTest', 'Job_KsContext', 'Job_BasarisizTest')) { Set-Item -Path ('function:global:' + $n) -Value (Get-Item ('function:' + $n)).ScriptBlock }

$global:FakeOpCalls = 0; $global:FakePlanCalls = 0; $script:Preview = $false
$g1 = Invoke-LiveGuarded 'Job_YazanTest' @{}
Assert-True ($g1 -is [hashtable] -and $g1.Err -eq '') ('bekçi: iş çökmeden bitti: ' + $g1.Err)
Assert-Eq ([int]$script:LiveBlocked.Count) 5 'bekçi: beş yazma denemesi yakalandı'
Assert-Eq $global:FakeOpCalls 0 'bekçi: Invoke-Op asıl işlevi çalıştırmadı'
Assert-Eq $global:FakePlanCalls 0 'bekçi: Invoke-Plan asıl işlevi çalıştırmadı'
Assert-True (-not $script:FakeReg.ContainsKey('HKCU\Bekci|Y')) 'bekçi: kayıt defterine yazılmadı'
Set-RegData 'HKCU\Bekci' 'Z' 'DWord' 1
Assert-True ($script:FakeReg.ContainsKey('HKCU\Bekci|Z')) 'bekçi bitince Set-RegData eski haline döndü'
Assert-Eq (Invoke-Op @{}) 'gercek-op' 'bekçi bitince Invoke-Op eski haline döndü'
Assert-True (-not (Test-Path 'function:Set-Service')) 'bekçi bitince Set-Service gölgesi kalmadı'
Assert-True (-not (Test-Path 'function:Stop-Process')) 'bekçi bitince Stop-Process gölgesi kalmadı'

$global:FakeOpCalls = 0; $global:FakePlanCalls = 0; $script:Preview = $false
$g2 = Invoke-LiveGuarded 'Job_OnizlemeTest' @{}
Assert-Eq ([int]$script:LiveBlocked.Count) 0 'bekçi: önizleme açıkken engel yok'
Assert-Eq $global:FakePlanCalls 1 'bekçi: önizlemede Invoke-Plan çalıştı'
Assert-Eq $global:FakeOpCalls 2 'bekçi: önizlemede Invoke-Op çalıştı'
Assert-Eq ([bool]$script:Preview) $false 'bekçi: önizleme bayrağı iş bitince eski haline döndü'

# bekçi altında çöken iş de gölgeleri geride bırakmaz
. ([scriptblock]::Create('function Job_CokenTest($P) { Set-Service -Name x; throw ''deneme çöküşü'' }'))
Set-Item -Path 'function:global:Job_CokenTest' -Value (Get-Item 'function:Job_CokenTest').ScriptBlock
$g3 = Invoke-LiveGuarded 'Job_CokenTest' @{}
Assert-True ($g3.Err -like '*deneme çöküşü*') 'bekçi: iş çökmesi Err olarak döner'
Assert-True (-not (Test-Path 'function:Set-Service')) 'bekçi: çöken işten sonra gölge kalmadı'

# Get-LiveWhy
Assert-Eq (Get-LiveWhy @{ Why = 'neden' }) 'neden' 'Get-LiveWhy: Why alanını okur'
Assert-Eq (Get-LiveWhy @{ Errors = 2 }) '2 adım hata verdi' 'Get-LiveWhy: Errors sayısını yazar'
Assert-Eq (Get-LiveWhy @{ Ok = $false }) '' 'Get-LiveWhy: neden yoksa boş'

# Test-LiveJobs: yazmaya kalkışan HATA, temiz OK, "Ok=false" bilgi/uyarı ayrımı
function Get-LiveReadJobs {
    return @(
        @{ Fn = 'Job_YazanTest'; Arg = @{}; Group = 'sistem'; Slow = $false },
        @{ Fn = 'Job_TemizTest'; Arg = @{}; Group = 'sistem'; Slow = $false },
        @{ Fn = 'Job_KsContext'; Arg = @{}; Group = 'sistem'; Slow = $false },
        @{ Fn = 'Job_BasarisizTest'; Arg = @{}; Group = 'sistem'; Slow = $false }
    )
}
$script:LiveRows.Clear(); $script:SmokeErrs2.Clear(); $script:SmokeWarns2.Clear(); $script:Preview = $false
Test-LiveJobs 'sistem'
$r1 = @($script:LiveRows | Where-Object { $_.Kimlik -eq 'Job_YazanTest' })
Assert-True ($r1.Count -eq 1 -and $r1[0].Durum -eq 'HATA' -and $r1[0].Ayrinti -like '*bekçi*') ('yazmaya kalkışan okuma işi HATA olur: ' + ($r1 | ForEach-Object { $_.Durum + ' ' + $_.Ayrinti }))
$r2 = @($script:LiveRows | Where-Object { $_.Kimlik -eq 'Job_TemizTest' })
Assert-True ($r2.Count -eq 1 -and $r2[0].Durum -eq 'OK') 'temiz okuma işi OK olur'
$r3 = @($script:LiveRows | Where-Object { $_.Kimlik -eq 'Job_KsContext' })
Assert-True ($r3.Count -eq 1 -and $r3[0].Durum -eq 'BILGI' -and $r3[0].Ayrinti -like '*Etkin VPN yok*') 'KsContext boş dönmesi BILGI sayılır'
$r4 = @($script:LiveRows | Where-Object { $_.Kimlik -eq 'Job_BasarisizTest' })
Assert-True ($r4.Count -eq 1 -and $r4[0].Durum -eq 'UYARI' -and $r4[0].Ayrinti -like '*2 adım hata*') 'başarısız dönen iş UYARI olur ve nedeni yazar'
Assert-Eq ([int]$script:SmokeErrs2.Count) 1 'yalnızca bekçiye takılan iş hata sayıldı'

# Statik güvence: okuma listesindeki hiçbir iş, ÖNİZLEME dışında gerçek planı çalıştıran yola ulaşamaz
$graph = @{}
foreach ($fnAst in @($script:AllFns)) {
    $nm = $fnAst.Name -replace '^global:', ''
    $calls = New-Object System.Collections.ArrayList
    foreach ($c in @($fnAst.Body.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true))) {
        $cn = $c.GetCommandName()
        if ($cn) { [void]$calls.Add([string]$cn) }
    }
    $graph[$nm] = $calls.ToArray()
}
$planWriters = @('Job_Plan', 'Invoke-Plan', 'Invoke-Undo', 'Job_Undo', 'Job_UndoAll', 'Invoke-RestorePoint', 'Disable-KillSwitchNow', 'Restore-KsState', 'Invoke-KsOffAction', 'Start-KsOn', 'Start-KsOffNow', 'Job_KsApply', 'Job_Kill', 'Job_Focus', 'Job_Priority')
$reaching = New-Object System.Collections.ArrayList
foreach ($j in @($jobs)) {
    $seen = @{}; $queue = New-Object System.Collections.Queue; $queue.Enqueue([string]$j.Fn)
    $hit = ''
    while ($queue.Count -gt 0 -and $hit -eq '') {
        $cur = [string]$queue.Dequeue()
        if ($seen.ContainsKey($cur)) { continue }
        $seen[$cur] = $true
        if ($planWriters -contains $cur) { $hit = $cur; break }
        if ($graph.ContainsKey($cur)) { foreach ($c in $graph[$cur]) { if (-not $seen.ContainsKey($c)) { $queue.Enqueue($c) } } }
    }
    if ($hit -ne '') { [void]$reaching.Add([string]$j.Fn + '->' + $hit) }
}
$allowedReach = @('Job_SmartZero', 'Job_Adaptive')
Assert-True ((@($reaching | Where-Object { $_ -like 'Job_SmartZero->*' }).Count -eq 1) -and (@($reaching | Where-Object { $_ -like 'Job_Adaptive->*' }).Count -eq 1)) ('çağrı grafiği çalışıyor (SmartZero ve Adaptive plan yoluna ulaşır): ' + ($reaching -join ', '))
$unexpected = @($reaching | Where-Object { $allowedReach -notcontains ($_ -split '->')[0] })
Assert-Eq ($unexpected -join ' | ') '' 'okuma işleri gerçek plan / geri alma / kill-switch yoluna ulaşmıyor'
foreach ($nmReach in $allowedReach) {
    $e = @($jobs | Where-Object { $_.Fn -eq $nmReach })
    Assert-True ($e.Count -eq 1 -and $e[0].Arg.Preview -eq $true) ($nmReach + ' yalnızca önizleme argümanıyla çağrılır')
}

# bölüm yönlendirici kaynakta kayıtlı mı
foreach ($k in @('ortam', 'olcum', 'tur', 'etki', 'sapma', 'arac', 'is', 'sensor', 'bulgu', 'ozet')) { Assert-True ($src.Contains("'" + $k + "'")) ('yönlendirici anahtarı kayıtlı: ' + $k) }
# duman kapsamı ve adımlar bağlı
Assert-True ($src -match "ozellik = @\('ozellik'\)") 'duman kapsamı: ozellik tanımlı'
Assert-True ($src -match 'LiveCheck. \{ Test-SmokeLive \$arg \}') 'duman adımı: LiveCheck yönlendirilir'
Assert-True ($src -notmatch "tam\s+= @\([^)]*'ozellik'") '"tam" kapsamı canlı denetimi içermez (gerçek ayar yazar)'
Assert-True ($src -match "SmokeLimitSec = 10800") 'bu kapsamın süre sınırı uzatıldı (bileşen geri kurma ve DISM dahil)'
# başlatıcılar
$araclar = Join-Path (Split-Path -Parent $script:TestDir) 'build/static/araclar'
if (Test-Path -LiteralPath $araclar) {
    foreach ($n in @('Duman-Ozellik.cmd', 'Duman-OzellikOku.cmd')) {
        $bytes = [System.IO.File]::ReadAllBytes((Join-Path $araclar $n))
        $ascii = $true; foreach ($b in $bytes) { if ($b -gt 127) { $ascii = $false } }
        Assert-True $ascii ($n + ': yalnızca ASCII')
        $txt = [System.Text.Encoding]::ASCII.GetString($bytes)
        Assert-True ($txt.Contains("`r`n") -and -not ($txt -replace "`r`n", '').Contains("`n")) ($n + ': CRLF')
    }
    $tamCmd = [System.IO.File]::ReadAllText((Join-Path $araclar 'Duman-Ozellik.cmd'))
    Assert-True ($tamCmd.Contains('MM_OZELLIK_KIP=tam') -and $tamCmd.Contains('-Verb RunAs') -and $tamCmd.Contains('net session')) 'tam başlatıcı: yönetici ister ve tam kip kurar'
    # yönetici penceresi kullanıcının ortam değişkenlerini almaz: isteğe bağlı seçimler jetonlu dosyayla aktarılır, dosya çalıştırılmaz
    Assert-True ($tamCmd.Contains("-ArgumentList '/secim','%MM_JETON%'") -and $tamCmd.Contains('Multimizer-duman-secim-%MM_JETON%.txt')) 'tam başlatıcı: seçimler yükseltmede jetonla aktarılır'
    foreach ($v in @('MM_OZELLIK_AGIR', 'MM_UYGULAMA_CANLI', 'MM_BILESEN_CANLI')) {
        Assert-True ($tamCmd.Contains('if defined ' + $v + ' >> "%MM_SECIM%" echo ' + $v + '=%' + $v + '%') -and $tamCmd.Contains('if /i "%%A"=="' + $v + '" set "' + $v + '=%%B"')) ('tam başlatıcı: ' + $v + ' yazılır ve izin listesiyle okunur')
    }
    Assert-True ($tamCmd.Contains('for /f "usebackq tokens=1,* delims==" %%A in ("%MM_SECIM%")') -and -not ($tamCmd -match '(?im)^\s*call\s+"%MM_SECIM%"')) 'tam başlatıcı: seçim dosyası okunur, çalıştırılmaz'
    Assert-True ($tamCmd.Contains('findstr /r "^[0-9][0-9]*$"') -and $tamCmd.Contains('del "%MM_SECIM%"')) 'tam başlatıcı: jeton yalnızca rakam, dosya okununca silinir'
    $okuCmd = [System.IO.File]::ReadAllText((Join-Path $araclar 'Duman-OzellikOku.cmd'))
    Assert-True ($okuCmd.Contains('MM_OZELLIK_KIP=oku') -and -not $okuCmd.Contains('RunAs')) 'okuma başlatıcısı: yükselmez'
}

try { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue } catch { }
# bileşen durumu: yeniden başlatma bekleyen kurulum kurulu, bekleyen kaldırma kaldırılmış sayılır
$global:LcCaps = @()
function Get-WindowsCapability { param([switch]$Online, $ErrorAction) return $global:LcCaps }
$global:LcCaps = @([pscustomobject]@{ Name = 'XPS.Viewer~~~~0.0.1.0'; State = 'InstallPending' })
Assert-Eq (Get-LiveCapState 'XPS.Viewer') 'kurulu' 'canlı ölçüm: bekleyen kurulum kurulu'
$global:LcCaps = @([pscustomobject]@{ Name = 'XPS.Viewer~~~~0.0.1.0'; State = 'UninstallPending' })
Assert-Eq (Get-LiveCapState 'XPS.Viewer') 'kaldirilmis' 'canlı ölçüm: bekleyen kaldırma kaldırılmış'
$global:LcCaps = @()
Assert-Eq (Get-LiveCapState 'XPS.Viewer') 'yok' 'canlı ölçüm: bileşen yok'
Remove-Item function:\Get-WindowsCapability -ErrorAction SilentlyContinue

# bağımsız geri yükleme: Windows yeniden başlatma beklerken kapatılmış özellik DISM ile açılmaya çalışılmaz (cihazda 15 dakika asılı kaldı)
$global:FeatState = @{ 'WorkFolders-Client' = 'Disabled' }
function Get-LiveFeatSnap([string]$Name) { return @{ K = 'Feature'; Name = $Name; State = [string]$global:FeatState[$Name] } }
$global:FeatSet = 0
function Set-WinFeatureState([string]$Name, [bool]$On) { $global:FeatSet++; return $false }
function Get-CbsRebootPending { return 'RebootPending' }
$err = ''
try { Restore-LiveItem @{ K = 'Feature'; Name = 'WorkFolders-Client'; State = 'Enabled' } } catch { $err = $_.Exception.Message }
Assert-True ($err -like '*yeniden başlatılmayı bekliyor (RebootPending)*WorkFolders-Client*yeniden açılacak*' -and $global:FeatSet -eq 0) 'yeniden başlatma beklenirken özellik açılmaya çalışılmaz; neden yazılır'
function Get-CbsRebootPending { return '' }
$script:DismNeedsReboot = $true; $err = ''
try { Restore-LiveItem @{ K = 'Feature'; Name = 'WorkFolders-Client'; State = 'Enabled' } } catch { $err = $_.Exception.Message }
Assert-True ($err -like '*(DISM)*' -and $global:FeatSet -eq 0) 'DISM yeniden başlatma istediyse de açılmaya çalışılmaz'
$script:DismNeedsReboot = $false
Restore-LiveItem @{ K = 'Feature'; Name = 'WorkFolders-Client'; State = 'Enabled' }
Assert-Eq $global:FeatSet 1 'yeniden başlatma beklenmiyorsa özellik açılır'
$global:FeatSet = 0; $global:FeatState['WorkFolders-Client'] = 'Enabled'
function Get-CbsRebootPending { return 'RebootPending' }
Restore-LiveItem @{ K = 'Feature'; Name = 'WorkFolders-Client'; State = 'Disabled' }
Assert-Eq $global:FeatSet 1 'kapatma yönündeki geri yükleme bekleyen yeniden başlatmada da yapılır'
Remove-Item function:Get-CbsRebootPending, function:Set-WinFeatureState -ErrorAction SilentlyContinue

# anlık görüntü ve karşılaştırma Windows bileşenini de kapsar (kurtarma listesine girebilsin)
function Get-LiveCapState([string]$M) { return [string]$global:CapSt[$M] }
$global:CapSt = @{ 'XPS.Viewer' = 'kurulu' }
$snapX = @(Get-LiveSnap (New-Cat 'FeatXps' @(@{ T = 'Cap'; Match = 'XPS.Viewer'; State = 'Absent' })))
Assert-True ($snapX.Count -eq 1 -and [string]$snapX[0].K -eq 'Cap' -and [string]$snapX[0].Data -eq 'kurulu' -and [string]$snapX[0].Name -eq 'XPS.Viewer') 'bileşen anlık görüntüye girer'
Assert-Eq (Compare-LiveItem @{ K = 'Cap'; Name = 'XPS.Viewer'; Data = 'kurulu' } @{ K = 'Cap'; Name = 'XPS.Viewer'; Data = 'kaldirilmis' }) 'bileşen XPS.Viewer: kurulu -> kaldirilmis' 'bileşen farkı yazılır'
Assert-Eq (Compare-LiveItem @{ K = 'Cap'; Name = 'XPS.Viewer'; Data = 'kurulu' } @{ K = 'Cap'; Name = 'XPS.Viewer'; Data = 'okunamadi' }) '' 'okunamayan bileşen fark sayılmaz'
Remove-Item function:Get-LiveCapState -ErrorAction SilentlyContinue

# ---------------- son durum: denetimin dokunmadığı bileşen dışarıdan değişirse HATA değil UYARI (24.11.2026: XPS Görüntüleyici) ----------------
$cX = @{ Id = 'FeatXpsT'; Ops = @(@{ T = 'Feature'; Name = 'Printing-XPSServices-Features'; State = 'Disabled' }, @{ T = 'Cap'; Match = 'XPS.Viewer'; State = 'Absent' }) }
$cR = @{ Id = 'RegT'; Ops = @(@{ T = 'Reg'; Path = 'HKCU\X'; Name = 'Y'; Value = 1 }) }
$script:LiveTouchedIds = @{}; $script:LiveCompTouched = @{}
Assert-True (Test-LiveMovedOutside $cX) 'son durum: dokunulmamış bileşen ayarı dışarıdan değişmiş sayılır'
Assert-True (-not (Test-LiveMovedOutside $cR)) 'son durum: kayıt defteri ayarı dışarıdan sayılmaz'
Assert-True (-not (Test-LiveMovedOutside @{ Id = 'Bos'; Ops = @() })) 'son durum: işlemsiz ayar dışarıdan sayılmaz'
Add-LiveCompTouched 'Cap' 'XPS.Viewer'
Assert-True (-not (Test-LiveMovedOutside $cX)) 'son durum: denetimin dokunduğu bileşen dışarıdan sayılmaz'
$script:LiveCompTouched = @{}
Add-LiveTouched $cX
Assert-True ($script:LiveCompTouched.ContainsKey('Feature:Printing-XPSServices-Features') -and $script:LiveCompTouched.ContainsKey('Cap:XPS.Viewer')) 'son durum: canlı tur bileşen adlarını işaretler'
Assert-True (-not (Test-LiveMovedOutside $cX)) 'son durum: canlı turu yapılan ayar dışarıdan sayılmaz'
$script:LiveTouchedIds = @{}; $script:LiveCompTouched = @{}
$script:LiveMode = 'tam'
function Read-SmokeLogDelta { return @() }
function Get-SmokeExpectMissing { return @() }
function Get-LiveApplicable { return @($cX, $cR) }
$global:PendNow = @{ FeatXpsT = 1; RegT = 0 }
function Get-TweakPending($C) { return [int]$global:PendNow[[string]$C.Id] }
$script:LiveState = @{ FeatXpsT = 0; RegT = 0 }
function Get-LiveCapState([string]$Name) { return 'kurulu' }
Save-LiveUnrestoredList @(@{ Id = 'FeatXps'; Time = '2026-11-18T22:49:00'; Why = 'w'; Items = @(@{ K = 'Cap'; Name = 'XPS.Viewer'; Data = 'kurulu' }) },
    @{ Id = 'FeatBaska'; Time = 't'; Why = 'w'; Items = @(@{ K = 'Cap'; Name = 'Baska.Bilesen'; Data = 'yok' }) })
$rowsBefore = @($script:LiveRows).Count
Complete-LiveAudit
$new = @($script:LiveRows | Select-Object -Skip $rowsBefore)
$dis = @($new | Where-Object { $_.Kimlik -eq 'dis-degisiklik' })
Assert-True ($dis.Count -eq 1 -and [string]$dis[0].Durum -eq 'UYARI' -and [string]$dis[0].Ayrinti -like '*FeatXpsT (0→1)*') 'son durum: dışarıdan değişen bileşen UYARI olarak yazılır'
$sd = @($new | Where-Object { $_.Kimlik -eq 'son-durum' })
Assert-True ($sd.Count -eq 1 -and [string]$sd[0].Durum -eq 'OK' -and [string]$sd[0].Ayrinti -like '1 ayarın*') ('son durum: denetimin kendi ayarları aynıysa HATA yok: ' + (@($sd | ForEach-Object { [string]$_.Durum + ' ' + [string]$_.Ayrinti }) -join ' / '))
$kr = @($new | Where-Object { $_.Alan -eq 'kurtarma' -and $_.Kimlik -eq 'FeatXps' })
Assert-True ($kr.Count -eq 1 -and [string]$kr[0].Durum -eq 'OK') 'son durum: eski durumuna dönen kurtarma kaydı listeden çıkarılır'
$ulx = @(Get-LiveUnrestored)
Assert-True ($ulx.Count -eq 1 -and [string]$ulx[0].Id -eq 'FeatBaska') 'son durum: eski durumuna dönmeyen kayıt listede kalır'
$kl = @($new | Where-Object { $_.Kimlik -eq 'kurtarma-listesi' })
Assert-True ($kl.Count -eq 1 -and [string]$kl[0].Ayrinti -like '1 değişiklik*' -and [string]$kl[0].Ayrinti -notlike '*FeatXps:*') 'son durum: kurtarma satırı yalnızca kalan kaydı sayar'
# denetimin kendi değiştirdiği (kayıt defteri) ayar farklı kalırsa HATA kalır
$global:PendNow = @{ FeatXpsT = 0; RegT = 1 }
$rowsBefore = @($script:LiveRows).Count
Complete-LiveAudit
$sd = @($script:LiveRows | Select-Object -Skip $rowsBefore | Where-Object { $_.Kimlik -eq 'son-durum' })
Assert-True ($sd.Count -eq 1 -and [string]$sd[0].Durum -eq 'HATA' -and [string]$sd[0].Ayrinti -like '*RegT (0→1)*') 'son durum: denetimin ayarı farklı kaldıysa HATA'
# okuma kipinde kurtarma listesine dokunulmaz
$script:LiveMode = 'oku'
Save-LiveUnrestoredList @(@{ Id = 'FeatXps'; Time = 't'; Why = 'w'; Items = @(@{ K = 'Cap'; Name = 'XPS.Viewer'; Data = 'kurulu' }) })
Remove-LiveUnrestoredDone
Assert-Eq @(Get-LiveUnrestored).Count 1 'son durum: okuma kipinde kurtarma listesi değişmez'
Save-LiveUnrestoredList @()
$script:LiveMode = ''
Remove-Item function:Get-LiveCapState, function:Get-TweakPending, function:Get-LiveApplicable -ErrorAction SilentlyContinue

# 26.11.2026 (b17 tam denetim): tur/Search HATA - WSearch Stop-Service -NoWait ile durdurulurken geri alma hemen Start-Service çağırdı,
# hizmet 'StopPending' olduğu için sessizce başarısız oldu. Geri alma artık 'Stopped' olunca başlatır.
$undoSvc = [regex]::Match($src, '(?s)''Svc'' \{\s+if \(\$null -ne \$it\.Start\).*?Add-Done \(\(''Hizmet geri al').Value
Assert-True ($undoSvc -match '''Stopped''\) \{ Start-Service') 'hizmet geri alma: StopPending bitmeden Start-Service çağrılmaz'
Assert-True ($undoSvc -match 'for \(\$k = 0; \$k -lt 60') 'hizmet geri alma: bekleme döngüsü sınırlı'

Show-Result
