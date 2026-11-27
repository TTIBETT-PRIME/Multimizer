. "$PSScriptRoot/lib.ps1"
# Windows özelliği / bileşeni işlemleri (mods\158_servis.ps1, patches\p74_servis.py), güç planı ayarı (p75_guc_plani.py),
# toplu ölçüm partisi (p73) ve denetimin kurtarma listesi (155). Gerçek DISM burada çalıştırılamaz: dism.exe yerine sahte
# Invoke-DismExe çıkış kodları döndürür; mantık (yerel kaynak → Windows Update kaynağı, meşgulken reddetme, zaman aşımı) sınanır.
Import-Fn 'Get-DismCodeText', 'Set-WinFeatureState', 'Set-WinCapabilityState', 'Get-DismExePath', 'Get-WinFeatureWmi', 'Get-WinFeatureInfo', 'Assert-DismReady', 'Test-DismRebootCode'
Import-Var 'DismLimitMin', 'WmiFeatState'
$script:DismTimedOut = $false   # betikteki son atama Invoke-DismExe içindeki "$true"; başlangıç değeri elle verilir
$src = [System.IO.File]::ReadAllText($script:TestPath)

function Write-WhLog([string]$Message, [string]$Level = 'INFO') { [void]$global:LogLines.Add($Level + ' ' + $Message) }
$global:LogLines = New-Object System.Collections.ArrayList
$global:DismCalls = New-Object System.Collections.ArrayList
$global:DismCodes = New-Object System.Collections.Queue
$global:Busy = ''
function Invoke-DismExe([string[]]$DismArgs, [int]$LimitMin = 0) { [void]$global:DismCalls.Add(($DismArgs -join ' ')); return [int]$global:DismCodes.Dequeue() }
function Get-ServicingBusy { return $global:Busy }
function Reset-Dism([int[]]$Codes) { $global:DismCalls.Clear(); $global:DismCodes.Clear(); foreach ($c in $Codes) { $global:DismCodes.Enqueue($c) }; $global:Busy = '' }

# ======================= 1) DISM kodlarının açıklaması =======================
Assert-True ((Get-DismCodeText (-2146498529)) -like '0x800F081F*kaynak*') '0x800F081F (işaretli tamsayı) kaynak bulunamadı olarak açıklanır'
Assert-True ((Get-DismCodeText 2148468767) -like '0x800F081F*') 'aynı kod işaretsiz yazılınca da tanınır'
Assert-True ((Get-DismCodeText (-2145124319)) -like '0x80240021*zaman*') '0x80240021 Windows Update zaman aşımı olarak açıklanır (gerçek bilgisayardaki hata)'
Assert-True ((Get-DismCodeText (-1)) -like ('*' + $script:DismLimitMin + ' dakika*')) 'süre dolması (-1) dakika sınırıyla açıklanır'
Assert-True ((Get-DismCodeText 87) -eq 'kod 0x00000057') 'bilinmeyen kod onaltılık yazılır'
Assert-Eq $script:DismLimitMin 15 'DISM işlemi en çok 15 dakika beklenir'

# ======================= 2) Windows özelliği aç/kapat =======================
Reset-Dism @(0)
Assert-Eq (Set-WinFeatureState 'WorkFolders-Client' $false) $false 'kapatma başarılı (0): yeniden başlatma gerekmez'
Assert-True ($global:DismCalls[0] -like '/Online /Disable-Feature /FeatureName:WorkFolders-Client /NoRestart /Quiet') 'kapatma yalnızca yerel, sessiz ve yeniden başlatmasız'
Reset-Dism @(3010)
Assert-Eq (Set-WinFeatureState 'VirtualMachinePlatform' $false) $true 'kapatma 3010: yeniden başlatma gerekir (başarılı sayılır)'

Reset-Dism @(0)
Assert-Eq (Set-WinFeatureState 'WorkFolders-Client' $true) $false 'açma yerel kaynakla başarılı'
Assert-Eq $global:DismCalls.Count 1 'yerel kaynak yetince Windows Update denenmez'
Assert-True ($global:DismCalls[0] -like '*/Enable-Feature /FeatureName:WorkFolders-Client /All /NoRestart /LimitAccess /Quiet') 'açma önce /LimitAccess ile (Windows Update''e gitmez, asılı kalmaz)'

Reset-Dism @((-2146498529), 3010)
Assert-Eq (Set-WinFeatureState 'NetFx3' $true) $true 'yerel kaynak yetmeyince Windows Update kaynağıyla açılır (3010)'
Assert-Eq $global:DismCalls.Count 2 'ikinci deneme yapıldı'
Assert-True ($global:DismCalls[1] -notlike '*LimitAccess*') 'ikinci deneme Windows Update kaynağını kullanır'
Assert-True (@($global:LogLines | Where-Object { $_ -like '*Windows Update kaynağı deneniyor*' }).Count -ge 1) 'ikinci deneme günlüğe yazılır'

Reset-Dism @((-2146498529))
$global:Busy = 'Windows Update şu anda bir güncelleme kuruyor'
$err = ''
try { [void](Set-WinFeatureState 'NetFx3' $true) } catch { $err = $_.Exception.Message }
Assert-True ($err -like '*Windows Update şu anda*güncelleme bitince*') 'Windows Update meşgulken ikinci deneme yapılmaz; ne yapılacağı yazılır'
Assert-Eq $global:DismCalls.Count 1 'meşgulken Windows Update kaynağı denenmez (1,5 saatlik asılı kalma engellenir)'

Reset-Dism @((-1), (-1))
$err = ''
try { [void](Set-WinFeatureState 'VirtualMachinePlatform' $true) } catch { $err = $_.Exception.Message }
Assert-True ($err -like '*dakikada bitmedi*yeniden başlatıp*') 'süre dolarsa açık bir hata verilir'
Assert-Eq $global:DismCalls.Count 1 'yerel deneme süre sınırını aşınca Windows Update ile ikinci uzun deneme yapılmaz (cihazda 20 + 7 dakika asılı kaldı)'
Reset-Dism @((-1))
$err = ''
try { [void](Set-WinCapabilityState 'App.StepsRecorder~~~~0.0.1.0' $true) } catch { $err = $_.Exception.Message }
Assert-True ($err -like '*dakikada bitmedi*yeniden başlatıp*' -and $global:DismCalls.Count -eq 1) 'bileşende de yerel süre aşımından sonra Windows Update denenmez'
# bu oturumda bir DISM süre sınırını aştıysa yeni DISM işlemi hiç başlatılmaz
$script:DismTimedOut = $true
Reset-Dism @(0, 0, 0)
$err = ''
try { [void](Set-WinFeatureState 'WorkFolders-Client' $false) } catch { $err = $_.Exception.Message }
Assert-True ($err -like '*süre sınırını aştı*yeniden başlatıp*') 'süre aşımından sonra özellik işlemi açık hatayla reddedilir'
$err = ''
try { [void](Set-WinCapabilityState 'App.StepsRecorder~~~~0.0.1.0' $true) } catch { $err = $_.Exception.Message }
Assert-True ($err -like '*süre sınırını aştı*') 'süre aşımından sonra bileşen işlemi de reddedilir'
Assert-Eq $global:DismCalls.Count 0 'süre aşımından sonra dism.exe çağrılmaz'
$script:DismTimedOut = $false
Assert-True ((Get-DismCodeText (-2146498286)) -like '0x800F0912*Windows Update*') '0x800F0912 (cihazda Sanal Makine Platformu) açıklanır'
Assert-True ((Get-DismCodeText (-2145123272)) -like '0x80240438*ulaşılamadı*') '0x80240438 (cihazda İş Klasörleri) açıklanır'
Assert-True ((Get-DismCodeText 2148469072) -like '0x800F0950*') '0x800F0950 açıklanır'

Reset-Dism @((-2146498529), (-2146498529))
$err = ''
try { [void](Set-WinFeatureState 'NetFx3' $true) } catch { $err = $_.Exception.Message }
Assert-True ($err -like '*yerel kaynak 0x800F081F*Windows Update kaynağı 0x800F081F*') 'iki kaynağın sonucu da hata metninde'

$err = ''
try { [void](Set-WinFeatureState 'Kötü; adı' $true) } catch { $err = $_.Exception.Message }
Assert-True ($err -like 'Geçersiz Windows özelliği adı*') 'geçersiz özellik adı reddedilir (komut satırına karışmaz)'

# ======================= 3) Windows bileşeni kur/kaldır =======================
Reset-Dism @(0)
Assert-Eq (Set-WinCapabilityState 'App.StepsRecorder~~~~0.0.1.0' $false) $false 'bileşen kaldırma'
Assert-True ($global:DismCalls[0] -like '/Online /Remove-Capability /CapabilityName:App.StepsRecorder~~~~0.0.1.0 /NoRestart /Quiet') 'kaldırma komutu'
Reset-Dism @((-2146498529), 0)
Assert-Eq (Set-WinCapabilityState 'App.StepsRecorder~~~~0.0.1.0' $true) $false 'geri kurma: yerel kaynak yetmezse Windows Update'
Assert-True ($global:DismCalls[0] -like '*/Add-Capability*/LimitAccess*' -and $global:DismCalls[1] -notlike '*LimitAccess*') 'önce yerel, sonra Windows Update'

# ======================= 4) motor: özellik/bileşen işlemleri yeni yolu kullanır =======================
Assert-True ($src -notmatch 'Enable-WindowsOptionalFeature -Online -FeatureName \$name') 'Invoke-FeatureOp artık doğrudan Enable-WindowsOptionalFeature çağırmıyor'
Assert-True ($src -notmatch 'Enable-WindowsOptionalFeature -Online -FeatureName \$it\.Name') 'geri alma da doğrudan çağırmıyor'
Assert-True ($src -notmatch 'Add-WindowsCapability -Online -Name \(\[string\]\$It\.Name\)') 'bileşen geri kurma da yeni yoldan'
$fo = [regex]::Match($src, '(?s)function Invoke-FeatureOp\(\$Op\) \{.*?\r?\n\}\r?\n').Value
Assert-True ($fo.IndexOf('Get-ServicingBusy') -ge 0 -and $fo.IndexOf('Get-ServicingBusy') -lt $fo.IndexOf('Add-Journal')) 'özellik değişikliği Windows Update meşgulken başlamaz (günlükten önce denetlenir)'
Assert-True ($fo -match 'Set-WinFeatureState \$name \$wantOn') 'özellik değişikliği süre sınırlı yoldan'
$co = [regex]::Match($src, '(?s)function Invoke-CapOp\(\$Op\) \{.*?\r?\n\}\r?\n').Value
Assert-True ($co.IndexOf('Get-ServicingBusy') -ge 0 -and $co.IndexOf('Get-ServicingBusy') -lt $co.IndexOf('Add-Journal')) 'bileşen değişikliği Windows Update meşgulken başlamaz'
$ix = [regex]::Match($src, '(?s)function Invoke-DismExe.*?\r?\n\}\r?\n').Value
Assert-True ($ix -match 'WaitForExit\(\$LimitMin \* 60000\)' -and $ix -match 'Kill\(\)' -and $ix -match 'ParentProcessId') 'süre dolunca dism.exe ve yardımcı süreci kapatılır'
Assert-True ($ix -match 'CreateNoWindow = \$true') 'DISM penceresiz çalışır'
Assert-True ($ix -match '\$script:DismTimedOut = \$true') 'süre dolunca oturum bayrağı açılır (sonraki DISM işlemleri asılı kalmaz)'
Assert-True ($src -match 'Sysnative\\dism\.exe' -and $src -match 'Is64BitOperatingSystem') '32 bit PowerShell 64 bit Windows''ta Sysnative üzerinden 64 bit DISM kullanır'

# ======================= 5) güç planı ayarı =======================
$pp = [regex]::Match($src, '(?s)function Invoke-PowerPlan \{.*?\r?\n\}\r?\n').Value
Assert-True ($pp -match "Invoke-PowerSetOp @\{ T = 'PowerSet'; Key = 'High' \}") 'Yüksek Performans ayarı Güç sayfasıyla aynı yolu kullanır (Modern Bekleme''de güç kipi)'
Assert-True ($pp -notmatch 'duplicatescheme') 'gizli planı her uygulamada kopyalayan eski yol kaldırıldı'
Assert-True ($src -match "Add-Journal @\{ T = 'Power'; Guid = \[string\]\`$act\.Guid; Created = \`$created \}") 'oluşturulan plan günlüğe yazılır'
Assert-True ($src -match "powercfg\.exe /delete \`$cr") 'geri alınca uygulamanın oluşturduğu plan silinir'

# ======================= 6) toplu ölçüm partisi =======================
Import-Fn 'Start-StateBatch', 'Stop-StateBatch', 'Get-TaskCached', 'Get-MpPrefCached'
$global:TaskAll = 0; $global:TaskOne = 0; $global:MpRead = 0
function Get-ScheduledTask { param([string]$TaskPath, [string]$TaskName, $ErrorAction)
    if ($TaskName -eq '') { $global:TaskAll++; return @([pscustomobject]@{ TaskPath = '\A\'; TaskName = 'Bir'; State = 'Ready' }, [pscustomobject]@{ TaskPath = '\A\'; TaskName = 'Iki'; State = 'Disabled' }) }
    $global:TaskOne++; if ($TaskName -eq 'Bir') { return [pscustomobject]@{ TaskPath = $TaskPath; TaskName = 'Bir'; State = 'Ready' } }; return $null }
function Get-MpPreference { param($ErrorAction) $global:MpRead++; return [pscustomobject]@{ PUAProtection = 1 } }
$script:IsAdmin = $true
$script:Preview = $true
$script:StateBatch = $null
[void](Get-TaskCached '\A\' 'Bir'); [void](Get-TaskCached '\A\' 'Bir')
Assert-Eq $global:TaskOne 2 'parti dışında her okuma tazedir'
Start-StateBatch
$t1 = Get-TaskCached '\A\' 'Bir'; $t2 = Get-TaskCached '\a\' 'iki'; $t3 = Get-TaskCached '\A\' 'Yok'
Assert-Eq $global:TaskAll 1 'partide görev listesi bir kez okunur'
Assert-Eq ([string]$t2.State) 'Disabled' 'büyük/küçük harf duyarsız eşleşme'
Assert-True ($null -eq $t3) 'yönetici tam listede olmayan görevi tek tek sormaz'
Start-StateBatch; Stop-StateBatch
Assert-True ($null -ne $script:StateBatch) 'iç içe parti: içteki bitince dıştaki sürer'
[void](Get-MpPrefCached); [void](Get-MpPrefCached)
Assert-Eq $global:MpRead 1 'partide Defender tercihleri bir kez okunur'
$script:Preview = $false
[void](Get-MpPrefCached)
Assert-Eq $global:MpRead 2 'gerçek uygulamada (önizleme değil) parti olsa bile taze okunur'
$script:Preview = $true
Stop-StateBatch
Assert-True ($null -eq $script:StateBatch) 'parti kapandı'
[void](Get-MpPrefCached)
Assert-Eq $global:MpRead 3 'parti kapanınca yine taze okunur (geri almadan sonra eski değer görünmez)'
foreach ($fn in @('Job_TweakStates', 'Job_TweakStateIds', 'Get-DriftedIds')) {
    $body = [regex]::Match($src, '(?s)function ' + $fn + '[\(\s\{].*?\r?\n\}\r?\n').Value
    Assert-True ($body -match 'Start-StateBatch' -and $body -match 'finally \{ Stop-StateBatch \}') ($fn + ' toplu ölçümü partide yapar ve her durumda kapatır')
}

# ======================= 6) özellik durumunun okunması (DISM yönetici ister → WMI) =======================
Assert-True ((Get-DismCodeText (-2146498513)) -like '0x800F082F*yeniden*') '0x800F082F bekleyen yeniden başlatma olarak açıklanır'
$global:CimAll = 0; $global:CimOne = 0; $global:DismRead = 0
$global:CimRows = @(
    [pscustomobject]@{ Name = 'WorkFolders-Client'; InstallState = 1 },
    [pscustomobject]@{ Name = 'SMB1Protocol'; InstallState = 2 },
    [pscustomobject]@{ Name = 'NetFx3'; InstallState = 3 },
    [pscustomobject]@{ Name = 'Garip'; InstallState = 4 })
function Get-CimInstance { param($ClassName, $Filter, $ErrorAction)
    if ($ClassName -ne 'Win32_OptionalFeature') { throw 'beklenmeyen sınıf' }
    if ([string]::IsNullOrEmpty($Filter)) { $global:CimAll++; return $global:CimRows }
    $global:CimOne++
    $n = [regex]::Match($Filter, "Name='([^']*)'").Groups[1].Value
    return @($global:CimRows | Where-Object { $_.Name -ceq $n })
}
function Get-WindowsOptionalFeature { param([switch]$Online, $FeatureName, $ErrorAction) $global:DismRead++; throw 'The requested operation requires elevation.' }
$script:StateBatch = $null
$script:IsAdmin = $false
$f = Get-WinFeatureInfo 'WorkFolders-Client'
Assert-Eq ([string]$f.State) 'Enabled' 'yönetici değilken özellik WMI ile okunur (1 = açık)'
Assert-Eq $global:DismRead 0 'yönetici değilken DISM hiç denenmez'
Assert-Eq ([string](Get-WinFeatureInfo 'SMB1Protocol').State) 'Disabled' 'WMI 2 = kapalı'
Assert-Eq ([string](Get-WinFeatureInfo 'NetFx3').State) 'DisabledWithPayloadRemoved' 'WMI 3 = kaynak dosyaları kaldırılmış (açık sayılmaz)'
Assert-True ($null -eq (Get-WinFeatureInfo 'Microsoft-Hyper-V-All')) 'bu sürümde olmayan özellik $null döner (Home sürümünde Hyper-V)'
$thrown = $false; try { [void](Get-WinFeatureInfo 'Garip') } catch { $thrown = $true }
Assert-True $thrown 'belirsiz durum (4) okunamadı sayılır, tahmin edilmez'
$thrown = $false; try { [void](Get-WinFeatureWmi "x' OR '1'='1") } catch { $thrown = $true }
Assert-True $thrown 'geçersiz ad sorguya girmez'
Assert-True ($global:CimAll -eq 0 -and $global:CimOne -ge 4) 'parti dışında özellik tek tek sorulur'
Start-StateBatch
[void](Get-WinFeatureInfo 'WorkFolders-Client'); [void](Get-WinFeatureInfo 'SMB1Protocol'); [void](Get-WinFeatureInfo 'Yok-Ozellik')
Assert-Eq $global:CimAll 1 'partide tüm özellikler bir kez okunur'
Stop-StateBatch
# yönetici: önce DISM; DISM bir kez çökerse partide bir daha denenmez, WMI kullanılır
$script:IsAdmin = $true; $global:DismRead = 0; $global:CimAll = 0
Start-StateBatch
Assert-Eq ([string](Get-WinFeatureInfo 'WorkFolders-Client').State) 'Enabled' 'yönetici: DISM çökünce WMI yedeği'
[void](Get-WinFeatureInfo 'SMB1Protocol')
Assert-Eq $global:DismRead 1 'DISM partide bir kez denendi'
Stop-StateBatch
function Get-WindowsOptionalFeature { param([switch]$Online, $FeatureName, $ErrorAction) $global:DismRead++; return [pscustomobject]@{ FeatureName = $FeatureName; State = 'EnablePending' } }
Assert-Eq ([string](Get-WinFeatureInfo 'WorkFolders-Client').State) 'EnablePending' 'yönetici: DISM okuyabiliyorsa onun ayrıntılı durumu kullanılır'
function Get-CimInstance { param($ClassName, $Filter, $ErrorAction) throw 'WMI kapalı' }
function Get-WindowsOptionalFeature { param([switch]$Online, $FeatureName, $ErrorAction) throw 'DISM hatası' }
$msg = ''; try { [void](Get-WinFeatureInfo 'SMB1Protocol') } catch { $msg = $_.Exception.Message }
Assert-True ($msg -like 'DISM hatası*WMI*') 'ikisi de okuyamazsa iki neden de bildirilir'
$script:IsAdmin = $false
$fop = [regex]::Match($src, '(?s)function Invoke-FeatureOp\(.*?\r?\n\}\r?\n').Value
Assert-True ($fop -match 'Get-WinFeatureInfo \$name' -and $fop -notmatch 'Get-WindowsOptionalFeature') 'ayar motoru özellik durumunu ortak okuyucudan alır'
Assert-True ($fop -match "@\('Enabled', 'EnablePending'\) -contains") 'açılması yeniden başlatma bekleyen özellik açık sayılır (ikinci kez uygulanmaz)'
$snap = [regex]::Match($src, '(?s)function Get-LiveFeatSnap\(.*?\r?\n\}\r?\n').Value
Assert-True ($snap -match "EnablePending'\) \{ \`$s.State = 'Enabled'" -and $snap -match "DisablePending'\) \{ \`$s.State = 'Disabled'") 'bağımsız okuyucu da bekleyen durumu etkin durum sayar'
Assert-True ($snap -match 'Win32_OptionalFeature') 'bağımsız okuyucu yönetici değilken WMI ile okur'
Remove-Item function:Get-CimInstance -ErrorAction SilentlyContinue
Remove-Item function:Get-WindowsOptionalFeature -ErrorAction SilentlyContinue

# ---------- 7) DISM bileşen deposu temizliği: bekleyen yeniden başlatmada ertelenir (cihazda 0x800F0806) ----------
Import-Fn 'Get-CbsRebootPending', 'Invoke-DismCleanup'
$global:CbsKeys = @('Packages')
function Get-RegSubKeyNames([string]$Path) { return $global:CbsKeys }
Assert-Eq (Get-CbsRebootPending) '' 'bileşen servisi beklemiyor'
$global:CbsKeys = @('Packages', 'PackagesPending'); Assert-Eq (Get-CbsRebootPending) 'PackagesPending' 'bekleyen paket işlemi'
$global:CbsKeys = @('RebootPending'); Assert-Eq (Get-CbsRebootPending) 'RebootPending' 'yeniden başlatma bekleniyor'
Assert-True ((Get-DismCodeText (-2146498554)) -like '0x800F0806*yeniden başlatın*') '0x800F0806 açıklanır'
$global:Skips = New-Object System.Collections.ArrayList; $global:Plans = New-Object System.Collections.ArrayList; $global:Dones = New-Object System.Collections.ArrayList
function Add-Skip([string]$M) { [void]$global:Skips.Add($M) }
function Add-Plan([string]$M) { [void]$global:Plans.Add($M) }
function Add-Done([string]$M) { [void]$global:Dones.Add($M) }
function Get-ServicingBusy { return $global:SvcBusyT }
$global:SvcBusyT = ''
$script:Preview = $false; $script:DismTimedOut = $false
Reset-Dism @(0)
Invoke-DismCleanup
Assert-Eq $global:DismCalls.Count 0 'yeniden başlatma beklenirken DISM temizliği çalışmaz'
Assert-True ($global:Skips.Count -eq 1 -and [string]$global:Skips[0] -like '*ertelendi*RebootPending*') 'ertelenme nedeni yazılır'
$script:Preview = $true; $global:Skips.Clear()
Invoke-DismCleanup
Assert-True ($global:Skips.Count -eq 1 -and $global:Plans.Count -eq 0) 'önizlemede de ertelenme görünür'
$global:CbsKeys = @('Packages'); $script:Preview = $true; $global:Skips.Clear()
Invoke-DismCleanup
Assert-Eq $global:Plans.Count 1 'engel yokken önizleme planlar'
$script:Preview = $false; Reset-Dism @(0)
Invoke-DismCleanup
Assert-True ($global:DismCalls.Count -eq 1 -and [string]$global:DismCalls[0] -like '*StartComponentCleanup*' -and $global:Dones.Count -eq 1) 'engel yokken temizlik süre sınırlı DISM ile çalışır'
Reset-Dism @(-2146498554); $err = ''
try { Invoke-DismCleanup } catch { $err = $_.Exception.Message }
Assert-True ($err -like '*tamamlanamadı*0x800F0806*') 'DISM hatası açıklamalı yazılır (yalnızca sayı değil)'
$global:SvcBusyT = 'Windows Update şu anda bir güncelleme kuruyor'; $global:Skips.Clear(); Reset-Dism @(0)
Invoke-DismCleanup
Assert-True ($global:DismCalls.Count -eq 0 -and [string]$global:Skips[0] -like '*ertelendi*Windows Update*') 'Windows Update kurarken temizlik ertelenir'
$script:DismTimedOut = $true; $global:SvcBusyT = ''; $err = ''; Reset-Dism @(0)
try { Invoke-DismCleanup } catch { $err = $_.Exception.Message }
Assert-True ($err -like '*süre sınırını aştı*' -and $global:DismCalls.Count -eq 0) 'oturumda DISM süre aşımı olduysa temizlik başlamaz'
$script:DismTimedOut = $false; $script:Preview = $false


# ---------- 8) Mağaza uygulaması kaldırma: kaldırma başarılıysa sonradan gelen kayıt hatası işi bozmaz (cihazda 18.11.2026) ----------
Import-Fn 'Invoke-AppxOp', 'Get-AppxSafe', 'Test-AppxStillThere', 'Test-PathNotFoundError'
function Test-ProtectedApp([string]$Name) { return ($Name -like 'Microsoft.WindowsStore*') }
function Add-Journal($It) { [void]$global:Journal.Add($It) }
$global:Journal = New-Object System.Collections.ArrayList
$global:AxInstalled = New-Object System.Collections.ArrayList   # PackageFullName listesi (her kullanıcıda kurulu)
$global:AxProv = New-Object System.Collections.ArrayList
$global:AxRemoveErr = ''        # Remove-AppxPackage -AllUsers bu iletiyle hata atar
$global:AxRemoveErrUser = ''    # tek kullanıcı denemesi bu iletiyle hata atar
$global:AxRemoveDoes = $true    # hata atsa da paketi kaldırır mı
$global:AxProvErr = $null       # Remove-AppxProvisionedPackage bu istisnayı atar
$global:AxProvCalls = 0
function New-AxPkg([string]$Full) { $n = $Full.Split('_')[0]; return [pscustomobject]@{ Name = $n; PackageFullName = $Full; InstallLocation = ('C:\Program Files\WindowsApps\' + $Full); NonRemovable = $false; PackageUserInformation = @([pscustomobject]@{ InstallState = 'Installed' }) } }
function Get-AppxPackage { param([switch]$AllUsers, [string]$Name, $ErrorAction)
    return @($global:AxInstalled | Where-Object { $_.Split('_')[0] -like $Name } | ForEach-Object { New-AxPkg $_ }) }
function Remove-AppxPackage { param([string]$Package, [switch]$AllUsers, $ErrorAction)
    if ($AllUsers -and $global:AxRemoveErr -ne '') { if ($global:AxRemoveDoes) { $global:AxInstalled.Remove($Package) }; throw $global:AxRemoveErr }
    if (-not $AllUsers -and $global:AxRemoveErrUser -ne '') { throw $global:AxRemoveErrUser }
    $global:AxInstalled.Remove($Package) }
function Get-AppxProvisionedPackage { param([switch]$Online, $ErrorAction) return @($global:AxProv | ForEach-Object { [pscustomobject]@{ DisplayName = $_.Split('_')[0]; PackageName = $_ } }) }
function Remove-AppxProvisionedPackage { param([switch]$Online, [string]$PackageName, $ErrorAction)
    $global:AxProvCalls++
    if ($null -ne $global:AxProvErr) { throw $global:AxProvErr }
    $global:AxProv.Remove($PackageName) }
function Reset-Ax([string[]]$Inst, [string[]]$Prov) {
    $global:AxInstalled.Clear(); foreach ($x in $Inst) { [void]$global:AxInstalled.Add($x) }
    $global:AxProv.Clear(); foreach ($x in $Prov) { [void]$global:AxProv.Add($x) }
    $global:AxRemoveErr = ''; $global:AxRemoveErrUser = ''; $global:AxRemoveDoes = $true; $global:AxProvErr = $null; $global:AxProvCalls = 0
    $script:Provisioned = $null; $global:Dones.Clear(); $global:Skips.Clear(); $global:Plans.Clear(); $global:Journal.Clear(); $global:LogLines.Clear()
}
$hub = 'Microsoft.MicrosoftOfficeHub_19.2502.0.0_x64__8wekyb3d8bbwe'
$hubProv = 'Microsoft.MicrosoftOfficeHub_18.2008.0.0_neutral_~_8wekyb3d8bbwe'
$script:Preview = $false

Reset-Ax @($hub) @($hubProv)
Invoke-AppxOp @{ T = 'Appx'; Name = 'Microsoft.MicrosoftOfficeHub' }
Assert-True ($global:AxInstalled.Count -eq 0 -and $global:AxProv.Count -eq 0 -and $global:Dones.Count -eq 1) 'sorunsuz kaldırma: paket ve otomatik kurulum kaydı gider, kaldırıldı yazılır'
Assert-True ($global:Journal.Count -eq 1 -and @($global:Journal[0].Full)[0] -eq $hub) 'geri alma günlüğüne paketin tam adı yazılır'

Reset-Ax @($hub) @($hubProv)
$global:AxProvErr = New-Object System.Runtime.InteropServices.COMException('Sistem belirtilen yolu bulamıyor.', -2147024893)
$err = ''
try { Invoke-AppxOp @{ T = 'Appx'; Name = 'Microsoft.MicrosoftOfficeHub' } } catch { $err = $_.Exception.Message }
Assert-Eq $err '' 'cihazdaki durum: kayıt dosyaları yokken (0x80070003) kaldırma hata vermez'
Assert-True ($global:Dones.Count -eq 1 -and $global:AxInstalled.Count -eq 0) 'uygulama kaldırıldı olarak yazılır'
Assert-True (@($global:LogLines | Where-Object { $_ -like 'INFO *zaten silinmiş*' }).Count -eq 1) 'kayıt dosyalarının zaten silinmiş olduğu bilgi olarak yazılır (uyarı değil)'
Assert-True (@($script:Provisioned).Count -eq 0) 'oturumdaki otomatik kurulum listesi tazelenir'

Reset-Ax @($hub) @($hubProv)
$global:AxProvErr = New-Object System.InvalidOperationException('Erişim engellendi.')
$err = ''
try { Invoke-AppxOp @{ T = 'Appx'; Name = 'Microsoft.MicrosoftOfficeHub' } } catch { $err = $_.Exception.Message }
Assert-True ($err -eq '' -and $global:Dones.Count -eq 1) 'kayıt başka nedenle silinemese de uygulama kaldırılmış sayılır'
Assert-True (@($global:LogLines | Where-Object { $_ -like 'WARN *otomatik kurulum kaydı kaldırılamadı*Erişim engellendi*' }).Count -eq 1) 'kalan kayıt nedeniyle uyarı olarak yazılır'

Reset-Ax @($hub) @()
$global:AxRemoveErr = 'Dağıtım başarısız oldu: 0x80070003'; $global:AxRemoveDoes = $true
$err = ''
try { Invoke-AppxOp @{ T = 'Appx'; Name = 'Microsoft.MicrosoftOfficeHub' } } catch { $err = $_.Exception.Message }
Assert-True ($err -eq '' -and $global:Dones.Count -eq 1) 'kaldırma hata verse de paket gittiyse başarılı sayılır'

Reset-Ax @($hub) @()
$global:AxRemoveErr = 'Erişim engellendi'; $global:AxRemoveDoes = $false; $global:AxRemoveErrUser = 'Paket kullanımda'
$err = ''
try { Invoke-AppxOp @{ T = 'Appx'; Name = 'Microsoft.MicrosoftOfficeHub' } } catch { $err = $_.Exception.Message }
Assert-True ($err -like '*kaldırılamadı (Microsoft.MicrosoftOfficeHub)*19.2502*Paket kullanımda*' -and $global:Dones.Count -eq 0) 'paket gerçekten kalırsa hangi paketin neden kalmadığı yazılır'

Reset-Ax @($hub) @()
$global:AxRemoveErr = 'Erişim engellendi'; $global:AxRemoveDoes = $false
Invoke-AppxOp @{ T = 'Appx'; Name = 'Microsoft.MicrosoftOfficeHub' }
Assert-True ($global:Dones.Count -eq 1 -and $global:AxInstalled.Count -eq 0) 'tüm kullanıcılardan kaldırılamazsa geçerli kullanıcıdan kaldırılır'

Reset-Ax @('Microsoft.WindowsStore_22410.1401.0.0_x64__8wekyb3d8bbwe') @()
Invoke-AppxOp @{ T = 'Appx'; Name = 'Microsoft.WindowsStore' }
Assert-True ($global:AxInstalled.Count -eq 1 -and $global:Skips.Count -eq 1 -and $global:Journal.Count -eq 0) 'korumalı uygulamaya dokunulmaz'

Reset-Ax @($hub) @($hubProv); $script:Preview = $true
Invoke-AppxOp @{ T = 'Appx'; Name = 'Microsoft.MicrosoftOfficeHub' }
Assert-True ($global:Plans.Count -eq 1 -and $global:AxInstalled.Count -eq 1 -and $global:AxProvCalls -eq 0) 'önizleme hiçbir şeyi kaldırmaz'
$script:Preview = $false

Assert-True (Test-PathNotFoundError (New-Object System.Exception('dış', (New-Object System.Runtime.InteropServices.COMException('iç', -2147024893))))) 'iç içe hatadaki 0x80070003 tanınır'
Assert-True (-not (Test-PathNotFoundError (New-Object System.Exception('Erişim engellendi')))) 'başka hata yol bulunamadı sayılmaz'

# ---------- 9) disk optimizasyonu disk türünü sistem profilinden okur (önceden hep "Unknown") ----------
Import-Fn 'Invoke-OptimizeDrive'
$global:OptArgs = $null
function Optimize-Volume { param([string]$DriveLetter, [switch]$ReTrim, [switch]$Defrag, $ErrorAction) $global:OptArgs = @{ L = $DriveLetter; T = [bool]$ReTrim; D = [bool]$Defrag } }
$env:SystemDrive = 'C:'
$sync = @{ Profile = @{ DiskType = 'SSD' } }
$global:Plans.Clear(); $script:Preview = $true
Invoke-OptimizeDrive
Assert-True ([string]$global:Plans[0] -like '*disk türü: SSD*') 'önizleme gerçek disk türünü gösterir'
$script:Preview = $false; $global:Dones.Clear()
Invoke-OptimizeDrive
Assert-True ($global:OptArgs.T -and -not $global:OptArgs.D -and $global:OptArgs.L -eq 'C') 'SSD''de TRIM seçilir'
$sync = @{ Profile = @{ DiskType = 'HDD' } }
Invoke-OptimizeDrive
Assert-True ($global:OptArgs.D -and -not $global:OptArgs.T) 'HDD''de birleştirme seçilir'
$sync = @{ Profile = $null }
Invoke-OptimizeDrive
Assert-True (-not $global:OptArgs.D -and -not $global:OptArgs.T) 'tür bilinmiyorsa seçimi Windows yapar'

# ---------- 10) "önce yeniden başlatın" kodları: Windows Update kaynağı denenmez (cihazda 18.11.2026 İş Klasörleri 0x371B) ----------
Assert-True (Test-DismRebootCode 14107) '0x371B (bileşen kurulum adımı) yeniden başlatma kodu'
Assert-True (Test-DismRebootCode -2146498554) '0x800F0806 (bekleyen işlem) yeniden başlatma kodu'
Assert-True (-not (Test-DismRebootCode -2146498530) -and -not (Test-DismRebootCode 0) -and -not (Test-DismRebootCode 3010) -and -not (Test-DismRebootCode -1)) 'kaynak eksikliği, başarı ve süre aşımı yeniden başlatma kodu sayılmaz'
Assert-True ((Get-DismCodeText 14107) -like '0x0000371B: *bekleyen bir değişiklik*') '0x371B açıklaması'
$script:DismNeedsReboot = $false; $script:DismTimedOut = $false
Reset-Dism @(14107, 0)
$err = ''
try { [void](Set-WinFeatureState 'WorkFolders-Client' $true) } catch { $err = $_.Exception.Message }
Assert-True ($err -like '*açılamadı (WorkFolders-Client): 0x0000371B*yeniden başlatıp*' -and $global:DismCalls.Count -eq 1) 'yeniden başlatma kodunda Windows Update kaynağı denenmez, yeniden başlatma önerilir'
Assert-True $script:DismNeedsReboot 'yeniden başlatma gereği oturumda işaretlenir'
$script:DismNeedsReboot = $false
Reset-Dism @(-2146498554, 0)
$err = ''
try { [void](Set-WinCapabilityState 'XPS.Viewer~~~~0.0.1.0' $true) } catch { $err = $_.Exception.Message }
Assert-True ($err -like '*kurulamadı (XPS.Viewer*0x800F0806*yeniden başlatıp*' -and $global:DismCalls.Count -eq 1 -and $script:DismNeedsReboot) 'bileşende de bekleyen işlem kodunda Windows Update denenmez'
$script:DismNeedsReboot = $false
Reset-Dism @(-2146498030, 14107)
$err = ''
try { [void](Set-WinFeatureState 'NetFx3' $true) } catch { $err = $_.Exception.Message }
Assert-True ($global:DismCalls.Count -eq 2 -and $script:DismNeedsReboot) 'Windows Update denemesi yeniden başlatma koduyla dönerse de işaretlenir'
$script:DismNeedsReboot = $false

# ---------- 11) geri alma: hata veren kayıt yedekte kalır, yeniden denenebilir ----------
Import-Fn 'Invoke-Undo', 'Save-UndoRemainder', 'Read-Journal', 'Get-JsonProp'
function Set-JobProgress { }
function Step-JobProgress { }
function Invoke-LiveRefresh { return $null }
function Write-LogFile([string]$M) { }
function Set-WinFeatureState([string]$Name, [bool]$On) { if ($global:FailFeat -contains $Name) { throw ('Windows özelliği açılamadı (' + $Name + '): 0x0000371B. Bilgisayarı yeniden başlatıp tekrar deneyin.') }; [void]$global:FeatDone.Add($Name); return $false }
$global:FeatDone = New-Object System.Collections.ArrayList
$jdir = Join-Path ([System.IO.Path]::GetTempPath()) ('mm-undo-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $jdir)
$jf = Join-Path $jdir 'yedek-20261118-202608.jsonl'
$hdr = '{"Tool":"Multimizer","Version":"10.1.0","Format":2,"Created":"2026-11-18 20:26:08","Computer":"PC","User":"PC\\u","Sid":""}'
$l1 = '{"T":"Feature","Name":"WorkFolders-Client","WasEnabled":true}'
$l2 = '{"T":"Feature","Name":"Printing-Foundation-InternetPrinting-Client","WasEnabled":true}'
[System.IO.File]::WriteAllText($jf, ($hdr + "`r`n" + $l1 + "`r`n" + $l2 + "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
$global:FailFeat = @('WorkFolders-Client')
$global:Dones.Clear(); $global:Errs = New-Object System.Collections.ArrayList; $global:LogLines.Clear()
function Add-Err([string]$M) { [void]$global:Errs.Add($M) }
Invoke-Undo $jf
Assert-True (Test-Path -LiteralPath $jf) 'bir kayıt geri alınamazsa yedek "geri alındı" diye işaretlenmez (Geçmiş''te kalır)'
$left = Read-Journal $jf
Assert-True (@($left.Items).Count -eq 1 -and [string]@($left.Items)[0].Name -eq 'WorkFolders-Client' -and [bool]@($left.Items)[0].WasEnabled) 'yedekte yalnızca geri alınamayan kayıt kalır (başarıyla geri alınan ikinci kez uygulanmaz)'
Assert-True ([string](Get-JsonProp $left.Header 'Created') -eq '2026-11-18 20:26:08') 'yedeğin başlığı korunur'
Assert-True ($global:FeatDone -contains 'Printing-Foundation-InternetPrinting-Client' -and $global:Errs.Count -eq 1) 'diğer kayıt geri alındı, hata bir kez yazıldı'
Assert-True (@($global:LogLines | Where-Object { $_ -like 'WARN 1 kayıt geri alınamadı; bu yedek Geçmiş sayfasında kaldı*' }).Count -eq 1) 'kullanıcıya yeniden deneyebileceği söylenir'
# yeniden başlatmadan sonra tekrar: bu kez geri alınır ve yedek işaretlenir
$global:FailFeat = @(); $global:FeatDone.Clear(); $global:Errs.Clear()
Invoke-Undo $jf
Assert-True (-not (Test-Path -LiteralPath $jf) -and (Test-Path -LiteralPath ([System.IO.Path]::ChangeExtension($jf, '.geri-alindi.jsonl')))) 'tekrar denemede geri alınınca yedek "geri alındı" olur'
Assert-True (@($global:FeatDone) -join ',' -eq 'WorkFolders-Client' -and $global:Errs.Count -eq 0) 'tekrar denemede yalnızca kalan kayıt geri alınır'
# hepsi başarılıysa eskisi gibi
$jf2 = Join-Path $jdir 'yedek-20261118-202700.jsonl'
[System.IO.File]::WriteAllText($jf2, ($hdr + "`r`n" + $l2 + "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
Invoke-Undo $jf2
Assert-True (-not (Test-Path -LiteralPath $jf2)) 'hata yoksa yedek "geri alındı" olarak işaretlenir'
Remove-Item -LiteralPath $jdir -Recurse -Force -ErrorAction SilentlyContinue

# ---------- 12) Optimize özeti: Windows bileşeni kaldırma seçiliyse geri kurulumun Windows Update'e bağlı olduğu yazılır ----------
Import-Fn 'Update-OpUi'
function Tr($T) { return $T }
function Set-Visible($E, [bool]$V) { }
function Get-OpSelectedIds { return $global:OpSel }
$global:OpCat = @{
    'FeatStepsRec' = @{ Id = 'FeatStepsRec'; Cat = 'Ozellik'; Title = 'Adım Kaydedicisi'; Reboot = $true; Irrev = $false; Ops = @(@{ T = 'Cap'; Match = 'App.StepsRecorder'; State = 'Absent' }) }
    'FeatWorkFolders' = @{ Id = 'FeatWorkFolders'; Cat = 'Ozellik'; Title = 'İş Klasörleri'; Reboot = $true; Irrev = $false; Ops = @(@{ T = 'Feature'; Name = 'WorkFolders-Client'; State = 'Disabled' }) }
}
function Get-CatalogItem([string]$Id) { return $global:OpCat[$Id] }
$ui = @{ op_Foot = [pscustomobject]@{ Text = '' }; op_PDrift = [pscustomobject]@{ Content = '' }; op_UserText = [pscustomobject]@{ Text = '' } }
$script:OpDrift = @(); $script:CatNames = @{ Ozellik = 'Windows özellikleri' }; $script:OpPreset = 'custom'
$global:OpSel = @('FeatStepsRec', 'FeatWorkFolders')
Update-OpUi
Assert-True ([string]$ui.op_UserText.Text -like "*`r`n1 Windows bileşeni kaldırılacak. Geri alırken dosyaları Windows Update’ten yeniden indirilir*") 'bileşen kaldırma seçiliyse özet uyarır'
$global:OpSel = @('FeatWorkFolders')
Update-OpUi
Assert-True ([string]$ui.op_UserText.Text -notlike '*Windows bileşeni kaldırılacak*') 'bileşen kaldırma yoksa uyarı çıkmaz'

Show-Result
