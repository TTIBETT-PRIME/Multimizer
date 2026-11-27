. "$PSScriptRoot/lib.ps1"
Import-Fn 'Get-VpnIpKind','ConvertFrom-VpnCidr','ConvertFrom-WgEndpoint','Test-WgKey','ConvertFrom-WgConfig','ConvertTo-WgConfText','Get-WgSummary','ConvertTo-WgName',
    'ConvertTo-IpLong','ConvertFrom-IpLong','Format-IpRange','Get-IpRangesExcept4','New-KsRuleSpecs','Disable-KillSwitchNow','Get-KsState','Job_KsVerify','Invoke-CliEmergency',
    'Test-PrivateIp','Get-ProtectedIps','Test-DevBlockAllowed','Test-NetBlocked','Get-NetOffList',
    'Job_SpeedTest','Job_LeakTest','Job_WingetCheck','Job_WingetUpgrade','Job_WingetInstall','Job_WingetPin','Job_WingetPinList','Job_WuSearch','Job_WuInstall','Job_DnsBench','Job_Ping','Job_Health',
    'Get-DefaultSettings','Get-Settings','ConvertTo-Hashtable','Read-JsonFile','Get-JsonProp'
Import-Fn 'New-WuPauseSteps','New-WuDeferSteps','New-WuDriverSteps','Get-WuControlState','ConvertFrom-WuTime','Job_InstalledUpdates','Job_WuUninstall',
    'Test-RegWriteBlocked','Resolve-RegPath','Get-TargetSid','RegOp','RegDel','Get-RecycleVerdict','Job_RecycleFiles','Get-DupFullGroups','Job_LargeFiles','Job_Duplicates',
    'Test-SecureDeleteAllowed','Find-Restic','Get-ResticRepoPath','New-ResticBackupArgs','Format-ProcessArg','Invoke-Restic','Job_ResticBackup','Job_ResticSnapshots','Job_ResticRestore'
Import-Var 'NetFeatures','WgNameRe','VpnNameRe','VpnHostRe','WgMaxBytes','UseCases','RegDenyPath','RegDenyName','WuUxKey','WuPolKey','RoboExcludeDirs','RoboExcludeFiles',
    'Page_optimize','Page_company','Page_clean','Page_updates','Page_backup','Page_settings','XamlMain','Page_gaming','Page_power','Page_smart'
$script:Settings = @{ NetOff = @() }
$sync = @{ Settings = $script:Settings }
function Get-Settings { return $script:Settings }
function Get-NetIPAddress { param($AddressFamily, $ErrorAction) throw 'yok' }

# Test-Step gövdelerini çıkar
$t = $null; $e = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($env:MM_BUILD, [ref]$t, [ref]$e)
$cmds = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Test-Step' }, $true)
function Get-StepBody([string]$Needle) {
    foreach ($c in $cmds) {
        $first = $c.CommandElements[1].Extent.Text
        if ($first.Contains($Needle)) {
            foreach ($el in $c.CommandElements) { if ($el -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) { return [scriptblock]::Create($el.ScriptBlock.Extent.Text.Trim().TrimStart('{').TrimEnd('}')) } }
        }
    }
    return $null
}
function Run-Step([string]$Needle) {
    $b = Get-StepBody $Needle
    if ($null -eq $b) { Assert-True $false ('sinama adimi bulunamadi: ' + $Needle); return }
    $out = @(& $b)
    $r = $null; if ($out.Count -gt 0) { $r = $out[$out.Count - 1] }
    $ok = -not (($r -is [string] -and $r -ne '') -or ($r -is [bool] -and $r -eq $false))
    Assert-True $ok ($Needle + ' -> ' + [string]$r)
}
Run-Step 'VPN: WireGuard yap'
Run-Step 'VPN: kill-switch kurallar'
Run-Step 'cihaz engelleme kendi bilgisayar'
# internet istekleri adımı (Test-NetBlocked bağlı $script:Settings)
Run-Step 'nternet istekleri: her'
# dosya ve güncelleme özellikleri (p12 adımları)
Run-Step 'ncelleme denetimi: duraklat'
Run-Step 'Dosya temizli'
Run-Step 'ifreli yedek: depo yolu'
Run-Step 'enek var olan sayfa ve sekmeye'
Run-Step 'z: yeni sekmelerin'
# kurtarma ve silme motorlarının derlenmesini sınayan adım (sahte bağımlılıklarla): her hata nedeniyle birlikte döner
$engBody = Get-StepBody 'Kurtarma ve silme motorlar'
Assert-True ($null -ne $engBody) 'motor sinama adimi var'
$script:EngExt = @{ Kurtarma = $true; DiskSilme = $true }
$script:EngRc = ''
$script:EngWp = ''
$script:EngLines = @(@{ Ok = $true; Text = 'tamam' })
$script:EngCalls = New-Object System.Collections.ArrayList
function Import-MmExt([string]$Name) { [void]$script:EngCalls.Add('ext:' + $Name); return @{ Ok = ($script:EngExt[$Name] -eq $true); Error = ('yuklenemedi ' + $Name) } }
function Initialize-MmRecover { [void]$script:EngCalls.Add('rc'); return $script:EngRc }
function Initialize-MmWipe { [void]$script:EngCalls.Add('wp'); return $script:EngWp }
function Invoke-WipeSelfCheck { [void]$script:EngCalls.Add('self'); return @{ Ok = $true; Lines = $script:EngLines } }
function Run-Eng { $script:EngCalls.Clear(); $o = @(& $engBody); if ($o.Count -gt 0) { return $o[$o.Count - 1] } return $null }
Assert-True ($null -eq (Run-Eng)) 'motor adimi: her sey tamamsa sonuc yok'
Assert-Eq ($script:EngCalls -join ',') 'ext:Kurtarma,rc,ext:DiskSilme,wp,self' 'motor adimi: sira eklenti, motor, eklenti, motor, ozdenetim'
$script:EngExt.Kurtarma = $false
Assert-True ((Run-Eng) -like 'Kurtarma eklentisi: yuklenemedi Kurtarma') 'motor adimi: kurtarma eklentisi yuklenemezse nedeni doner'
Assert-Eq ($script:EngCalls -join ',') 'ext:Kurtarma' 'motor adimi: kurtarma eklentisi yoksa baska bir sey calismaz'
$script:EngExt.Kurtarma = $true
$script:EngRc = 'derleme hatasi CS1002'
Assert-True ((Run-Eng) -like 'Kurtarma motoru: derleme hatasi CS1002') 'motor adimi: kurtarma motoru derlenemezse nedeni doner'
Assert-Eq ($script:EngCalls -join ',') 'ext:Kurtarma,rc' 'motor adimi: kurtarma motoru derlenmezse silme denenmez'
$script:EngRc = ''
$script:EngExt.DiskSilme = $false
Assert-True ((Run-Eng) -like 'Disk silme eklentisi: yuklenemedi DiskSilme') 'motor adimi: silme eklentisi yuklenemezse nedeni doner'
$script:EngExt.DiskSilme = $true
$script:EngWp = 'derleme hatasi CS0103'
Assert-True ((Run-Eng) -like 'Silme motoru: derleme hatasi CS0103') 'motor adimi: silme motoru derlenemezse nedeni doner'
Assert-Eq ($script:EngCalls -join ',') 'ext:Kurtarma,rc,ext:DiskSilme,wp' 'motor adimi: silme motoru derlenmezse ozdenetim calismaz'
$script:EngWp = ''
$script:EngLines = @(@{ Ok = $true; Text = 'bir' }, @{ Ok = $false; Text = 'Aralik disindaki baytlar degisti' }, @{ Ok = $true; Text = 'uc' })
Assert-True ((Run-Eng) -like 'Silme motoru *zdenetimi: Aralik disindaki baytlar degisti') 'motor adimi: ozdenetim basarisizsa ilk basarisiz satir doner'
$script:EngLines = @(@{ Ok = $true; Text = 'bir' }, @{ Ok = $true; Text = 'iki' })
Assert-True ($null -eq (Run-Eng)) 'motor adimi: butun ozdenetim satirlari tamamsa sonuc yok'
# adım uyarı kipindedir (ortamsal bir engel sınamayı başarısız saymaz) ve eklenti listesi başlığı yedi eklentiyi de sayar
$engCmd = $cmds | Where-Object { $_.CommandElements[1].Extent.Text.Contains('Kurtarma ve silme motorlar') } | Select-Object -First 1
Assert-True ($null -ne $engCmd -and $engCmd.CommandElements[$engCmd.CommandElements.Count - 1].Extent.Text -eq '$true') 'motor adimi uyari kipinde'
$extCmd = $cmds | Where-Object { $_.CommandElements[1].Extent.Text.Contains('Eklentiler y') } | Select-Object -First 1
Assert-True ($null -ne $extCmd -and $extCmd.CommandElements[1].Extent.Text.Contains('0x015F + ''ifreleme') -and $extCmd.CommandElements[1].Extent.Text.Contains('disk silme')) 'eklenti adimi basligi disk koruma, kurtarma ve disk silmeyi de sayar'
# güvenlik kapıları ve izin listeleri adımı: gerçek işlevlerle sınanır (Linux'ta ortam değişkenleri boş olsa da kapılar yine reddeder)
Import-Fn 'Test-PrepPackage','Test-ExtToolId','Get-ExtToolCatalog','Get-ExtTool','Test-UpdateUrl','Compare-AppVersion','ConvertTo-AppVersionParts','Test-WipeDiskAllowed','Test-WipePartAllowed','Test-WipeIdentity','Test-WipeTyped','ConvertTo-WipeFold','Test-SecureDeleteAllowed'
Import-Var 'PrepPackages','ExtToolRows'
$script:ExtToolCache = $null
$gateStubs = @('Job_SlvDisks','Job_SlvDiskOp','Job_PcInfo','Job_PrepCheck','Job_PrepInstall','Job_ExtToolScan','Job_ExtToolInstall','Job_IntegrityCheck','Chk_Posture','Chk_Crashes','Chk_AppCrashes','Chk_BootTime','Chk_DiskProtect','Chk_DiskErrors','Get-PostureCoverage','Test-BlEnablePlan')
foreach ($n in $gateStubs) { Set-Item -Path ('function:global:' + $n) -Value { } }
# Linux'ta WINDIR ve SystemDrive tanımsızdır; kapının gerçek değerlerle sınanması için biçim olarak Windows'unkine benzer yollar verilir
$env:WINDIR = '/mm-test/Windows'
$env:SystemDrive = '/mm-test'
$gateBody = Get-StepBody 'izin listeleri yerinde'
Assert-True ($null -ne $gateBody) 'kapi adimi var'
function Run-Gate { $o = @(& $gateBody); if ($o.Count -gt 0) { return $o[$o.Count - 1] } return $null }
$gateRes = Run-Gate
Assert-True ($null -eq $gateRes) ('kapi adimi: gercek kapilarla sonuc yok -> ' + [string]$gateRes)
# adım boş geçmesin: her kapı bozulunca ilgili neden döner
Remove-Item -Path 'function:Chk_Posture'
Assert-True ((Run-Gate) -like 'eksik: Chk_Posture') 'kapi adimi: eksik islevi adiyla soyler'
Set-Item -Path 'function:global:Chk_Posture' -Value { }
$script:PrepPackages['Baska.Paket'] = 'x'
Assert-True ((Run-Gate) -like 'Haz*izin listesi d*paket kabul edildi') 'kapi adimi: izin listesine sizan paket yakalanir'
$script:PrepPackages.Remove('Baska.Paket')
function Test-UpdateUrl([string]$Url) { return '' }
Assert-True ((Run-Gate) -like 'G*ifresiz (http) adres kabul edildi') 'kapi adimi: http adres kabul eden kapi yakalanir'
Import-Fn 'Test-UpdateUrl'
function Test-WipeDiskAllowed($Live, [string]$Scope) { return '' }
Assert-True ((Run-Gate) -like 'Silme: Windows*diske do*dan yazma izni verildi') 'kapi adimi: sistem diskine izin veren kapi yakalanir'
Import-Fn 'Test-WipeDiskAllowed'
function Test-SecureDeleteAllowed([string]$Path) { return '' }
Assert-True ((Run-Gate) -like 'Silme: s*r*c* k*k* ya da Windows klas*r* silinebilir say*ld*') 'kapi adimi: surucu kokunu silinebilir sayan kapi yakalanir'
Import-Fn 'Test-SecureDeleteAllowed'
function Compare-AppVersion([string]$A, [string]$B) { return 0 }
Assert-True ((Run-Gate) -like 'G*s*r*m kar*la*t*rmas* yanl*') 'kapi adimi: bozuk surum karsilastirmasi yakalanir'
Import-Fn 'Compare-AppVersion'
Assert-True ($null -eq (Run-Gate)) 'kapi adimi: kapilar geri yuklenince yine sonuc yok'
# kapalıyken işi engeller
$script:Settings = @{ NetOff = @('speed') }
Assert-True (Test-NetBlocked 'Job_SpeedTest') 'hiz testi kapaliyken engellenir'
Assert-True (-not (Test-NetBlocked 'Job_Health')) 'saglik taramasi engellenmez'
Show-Result
