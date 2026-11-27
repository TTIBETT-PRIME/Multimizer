. "$PSScriptRoot/lib.ps1"
Import-Fn 'Format-Size','Format-Duration','RegOp','RegDel','Test-SecureDeleteAllowed','Test-BackupDest','Get-FilesBySize',
    'Get-RecycleVerdict','Move-ToRecycle','Job_RecycleFiles','ConvertFrom-WuTime','Get-WuControlState','Job_WuControl','New-WuPauseSteps','New-WuDeferSteps','New-WuDriverSteps',
    'Job_InstalledUpdates','Get-WusaResult','Job_WuUninstall','Job_WingetPin','Job_WingetPinList','ConvertFrom-WingetTable',
    'Get-BlProtectorName','Get-BlStatusText','Get-BitLockerVolumes','Job_BitLockerInfo','Job_BitLockerKey','Format-BlKeyFile','Chk_BitLocker','Chk_Defender',
    'Find-Restic','Get-ResticRepoPath','Test-ResticRepo','New-ResticBackupArgs','Format-ProcessArg','Invoke-Restic','Get-ResticSummary','Get-ResticErrorText',
    'Job_ResticBackup','Job_ResticSnapshots','Job_ResticRestore'
Import-Var 'WuUxKey','WuPolKey','RoboExcludeDirs','RoboExcludeFiles','WalkSkipDirs'

# ---- ortak bakliklar ----
$script:Log = New-Object System.Collections.ArrayList
function Write-WhLog { param([string]$Text, [string]$Level = 'INFO') [void]$script:Log.Add($Level + '|' + $Text) }
function Write-Thanks { }
function Set-JobProgress { param($a, $b, $c) }
function Step-JobProgress { }
function Test-JobCancel { return $false }
function Reset-Counters { }
$script:Settings = @{ BackupSources = @(); BackupDest = ''; LastBackup = '' }
function Get-Settings { return $script:Settings }
function Save-Settings { param($s) $script:Settings = $s }
$script:Findings = New-Object System.Collections.ArrayList
function Add-Finding { param([string]$Id, [string]$Cat, [string]$Status, [string]$Title, [string]$Detail = '', $Action = $null, [int]$Weight = -1, $Fix = $null) [void]$script:Findings.Add(@{ Id = $Id; Status = $Status; Title = $Title; Detail = $Detail; Action = $Action; Weight = $Weight }) }
function Log-Has([string]$Needle) { foreach ($l in $script:Log) { if ($l.Contains($Needle)) { return $true } }; return $false }
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('mmfiles' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $tmp | Out-Null
$env:COMPUTERNAME = 'TESTPC'

# ======================= 1) Geri Donusum Kutusu karari =======================
Assert-Eq (Get-RecycleVerdict '/tmp/x/a.bin' 1000 'Fixed' 100000) '' 'normal dosya izinli'
Assert-True ((Get-RecycleVerdict '/tmp/x/a.bin' 1000 'Removable' 100000) -match 'Çıkarılabilir') 'cikarilabilir surucu reddedilir'
Assert-True ((Get-RecycleVerdict '/tmp/x/a.bin' 1000 'Network' 100000) -match 'kalıcı') 'ag surucusu reddedilir'
Assert-True ((Get-RecycleVerdict '/tmp/x/a.bin' 4000 'Fixed' 100000) -match 'sığmayabilir') 'cok buyuk dosya reddedilir (%3 siniri)'
Assert-Eq (Get-RecycleVerdict '/tmp/x/a.bin' 3000 'Fixed' 100000) '' 'sinirin altindaki dosya izinli'
Assert-Eq (Get-RecycleVerdict '/tmp/x/a.bin' 999999 'Fixed' 0) '' 'surucu boyutu bilinmiyorsa boyut siniri uygulanmaz'
$env:WINDIR = '/tmp/mmwin'
Assert-True ((Get-RecycleVerdict '/tmp/mmwin/system32/x.dll' 10 'Fixed' 1000000) -match 'Windows') 'Windows klasoru reddedilir'
$env:WINDIR = ''

$d1 = Join-Path $tmp 'src'; New-Item -ItemType Directory -Path $d1 | Out-Null
$fa = Join-Path $d1 'a.bin'; $fb = Join-Path $d1 'b.bin'; $fc = Join-Path $d1 'c.bin'
[System.IO.File]::WriteAllBytes($fa, (New-Object byte[] 100)); [System.IO.File]::WriteAllBytes($fb, (New-Object byte[] 200)); [System.IO.File]::WriteAllBytes($fc, (New-Object byte[] 300))
$script:Recycled = New-Object System.Collections.ArrayList
function Move-ToRecycle { param([string]$Path) if ($Path -like '*b.bin') { throw 'kilitli' }; [void]$script:Recycled.Add($Path); Remove-Item -LiteralPath $Path -Force }
$script:Log.Clear()
$r = Job_RecycleFiles @{ Paths = @($fa, $fb, (Join-Path $d1 'yok.bin'), '') }
Assert-Eq $r.Moved 1 'bir dosya gonderildi'
Assert-Eq $r.Failed 1 'kilitli dosya hata sayilir'
Assert-Eq $r.Skipped 1 'olmayan dosya atlanir'
Assert-True (-not (Test-Path -LiteralPath $fa)) 'a.bin kutuya gitti'
Assert-True (Test-Path -LiteralPath $fb) 'b.bin yerinde'
Assert-True ($r.Ok -eq $false) 'hata varsa Ok degil'
Assert-Eq $r.Bytes 100.0 'bayt toplami'
$r2 = Job_RecycleFiles @{ Paths = @($fc) }
Assert-True ($r2.Ok -and $r2.Moved -eq 1) 'temiz calisma Ok'

# ======================= 2) Windows Update denetimi =======================
$script:Reg = @{}
function Get-RegValue { param([string]$Path, [string]$Name, $Default = $null) $k = $Path + '|' + $Name; if ($script:Reg.ContainsKey($k)) { return $script:Reg[$k] }; return $Default }
Assert-True ($null -eq (ConvertFrom-WuTime '')) 'bos zaman -> null'
Assert-True ($null -eq (ConvertFrom-WuTime 'abc')) 'bozuk zaman -> null'
$t = ConvertFrom-WuTime '2030-05-01T10:30:00Z'
Assert-True ($null -ne $t -and $t.Year -eq 2030 -and $t.Hour -eq 10) 'ISO zaman cozulur'
$s0 = Get-WuControlState
Assert-True (-not $s0.Paused -and -not $s0.DeferOn -and -not $s0.NoDrivers) 'varsayilan: hicbir sey acik degil'
$fut = (Get-Date).ToUniversalTime().AddDays(10).ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
$past = (Get-Date).ToUniversalTime().AddDays(-3).ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
$script:Reg[$script:WuUxKey + '|PauseUpdatesExpiryTime'] = $fut
$s1 = Get-WuControlState
Assert-True ($s1.Paused -and $s1.Until -gt (Get-Date).ToUniversalTime().AddDays(9)) 'duraklatma okunur'
$script:Reg[$script:WuUxKey + '|PauseUpdatesExpiryTime'] = $past
Assert-True (-not (Get-WuControlState).Paused) 'suresi dolan duraklatma sayilmaz'
$script:Reg[$script:WuPolKey + '|DeferFeatureUpdates'] = 1
$script:Reg[$script:WuPolKey + '|DeferFeatureUpdatesPeriodInDays'] = 180
$script:Reg[$script:WuPolKey + '|ExcludeWUDriversInQualityUpdate'] = 1
$s2 = Get-WuControlState
Assert-True ($s2.DeferOn -and $s2.DeferDays -eq 180 -and $s2.NoDrivers) 'erteleme ve surucu ayari okunur'
$script:Reg[$script:WuPolKey + '|DeferFeatureUpdates'] = 0
Assert-True (-not (Get-WuControlState).DeferOn) 'DeferFeatureUpdates=0 ise erteleme yok'

$ps = @(New-WuPauseSteps 7)
Assert-Eq $ps.Count 1 'duraklatma tek adim'
Assert-Eq @($ps[0].Ops).Count 6 'duraklatma 6 deger yazar'
$ex = @($ps[0].Ops | Where-Object { $_.Name -eq 'PauseUpdatesExpiryTime' })[0]
$st0 = @($ps[0].Ops | Where-Object { $_.Name -eq 'PauseUpdatesStartTime' })[0]
Assert-True ($ex.Kind -eq 'String' -and $ex.Value -match '^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$') 'bitis ISO dizgesi'
$dd = ([datetime]::Parse($ex.Value, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal) - [datetime]::Parse($st0.Value, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal)).TotalDays
Assert-True ([math]::Abs($dd - 7) -lt 0.01) 'sure 7 gun'
Assert-True ($ps[0].Ops[0].Path -eq 'HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings') 'Ayarlar uygulamasinin anahtari'
Assert-Eq @(New-WuPauseSteps 36).Count 0 '35 gunu asan duraklatma reddedilir'
Assert-Eq @(New-WuPauseSteps -1).Count 0 'eksi gun reddedilir'
$rs = @(New-WuPauseSteps 0)
Assert-True ($rs[0].Id -eq 'WuResume' -and @($rs[0].Ops | Where-Object { $_.Del -eq $true }).Count -eq 6) 'devam ettirme 6 degeri siler'
$df = @(New-WuDeferSteps 365)
Assert-True ($df.Count -eq 1 -and @($df[0].Ops | Where-Object { $_.Name -eq 'DeferFeatureUpdatesPeriodInDays' })[0].Value -eq 365) '365 gun erteleme'
Assert-Eq @(New-WuDeferSteps 366).Count 0 '365 gunu asan erteleme reddedilir'
$dof = @(New-WuDeferSteps 0)
Assert-True ($dof[0].Id -eq 'WuDeferOff' -and @($dof[0].Ops | Where-Object { $_.Del -eq $true }).Count -eq 2) 'erteleme kaldirma'
$dv = @(New-WuDriverSteps $true)
Assert-True ($dv[0].Ops[0].Name -eq 'ExcludeWUDriversInQualityUpdate' -and $dv[0].Ops[0].Value -eq 1) 'surucu disla'
$dv2 = @(New-WuDriverSteps $false)
Assert-True ($dv2[0].Ops[0].Del -eq $true) 'surucuyu geri al = deger silinir'
# guvenlik kapisi: hicbir adim Update'i kapatan degerlere dokunmaz
$allSteps = @($ps) + @($rs) + @($df) + @($dof) + @($dv) + @($dv2)
$bad = @($allSteps | ForEach-Object { $_.Ops } | Where-Object { $_.Name -match '^(NoAutoUpdate|DisableWindowsUpdateAccess|WUServer|UseWUServer|DoNotConnectToWindowsUpdateInternetLocations|AUOptions)$' })
Assert-Eq $bad.Count 0 'Windows Update kapatan deger yazilmaz'

# kurulu guncellemeler
function Get-HotFix { param($ErrorAction) 
    [pscustomobject]@{ HotFixID = 'KB5034123'; Description = 'Security Update'; InstalledOn = [datetime]'2026-09-10'; InstalledBy = 'NT AUTHORITY\SYSTEM' }
    [pscustomobject]@{ HotFixID = 'KB5030000'; Description = 'Update'; InstalledOn = [datetime]'2026-10-01'; InstalledBy = 'x' }
    [pscustomobject]@{ HotFixID = 'garbage'; Description = 'x'; InstalledOn = $null; InstalledBy = '' }
    [pscustomobject]@{ HotFixID = 'KB1'; Description = 'x'; InstalledOn = $null; InstalledBy = '' }
    [pscustomobject]@{ HotFixID = 'KB5011111'; Description = 'Hotfix'; InstalledOn = $null; InstalledBy = '' }
}
$iu = Job_InstalledUpdates @{}
$rows = @($iu.Rows)
Assert-Eq $rows.Count 3 'yalnizca gecerli KB kimlikleri'
Assert-Eq $rows[0].Id 'KB5030000' 'en yeni ustte'
Assert-Eq $rows[2].Id 'KB5011111' 'tarihsiz en altta'
Assert-Eq $rows[0].DateText '2026-10-01' 'tarih metni'

Assert-True ((Get-WusaResult 0).Ok) 'wusa 0 = basari'
$w3010 = Get-WusaResult 3010
Assert-True ($w3010.Ok -and $w3010.Reboot) 'wusa 3010 = basari + yeniden baslat'
Assert-True ((Get-WusaResult 2359302).Skip) 'wusa 2359302 = zaten yok'
Assert-True ((Get-WusaResult -2145124329).Skip -and (Get-WusaResult -2145124329).Text -match 'Güncelleme geçmişi') 'LCU kaldirilamaz yonlendirme'
Assert-True ((Get-WusaResult 5).Text -match 'erişim') 'erisim reddedildi'
Assert-True ((Get-WusaResult 87).Text -match '87') 'bilinmeyen kod metne girer'
# wusa cagrisi: yalnizca gecerli KB, dogru bicimde
$script:WusaCalls = New-Object System.Collections.ArrayList
$env:WINDIR = '/tmp/mmwin'
function Start-Process { param($FilePath, $ArgumentList, [switch]$Wait, [switch]$PassThru, $WindowStyle) [void]$script:WusaCalls.Add([string]$ArgumentList); $c = 0; if ([string]$ArgumentList -match 'kb:5030000') { $c = 3010 }; if ([string]$ArgumentList -match 'kb:5011111') { $c = 2359302 }; return [pscustomobject]@{ ExitCode = $c } }
$script:Log.Clear()
$u = Job_WuUninstall @{ Ids = @('KB5034123', 'KB5030000', 'KB5011111', 'rm -rf', 'KB12', 'KB5034123; calc') }
Assert-Eq $script:WusaCalls.Count 3 'yalnizca 3 gecerli KB cagrildi'
Assert-Eq $script:WusaCalls[0] '/uninstall /kb:5034123 /quiet /norestart' 'wusa argumanlari'
Assert-True ($u.Reboot -eq $true) '3010 -> yeniden baslatma isaretlenir'
Assert-Eq $u.Removed 2 'iki kaldirma basarili'
Assert-True ($u.Ok) 'atlanan hata sayilmaz'
$env:WINDIR = ''
Remove-Item function:Start-Process

# ======================= 3) winget sabitleme =======================
$script:WgCalls = New-Object System.Collections.ArrayList
function Invoke-WingetRaw { param([string[]]$WgArgs) [void]$script:WgCalls.Add($WgArgs -join ' '); if ($WgArgs[0] -eq 'pin' -and $WgArgs[1] -eq 'list') { return @{ Code = 0; Lines = @('Name   Id          Version  Source  Pin type', '----------------------------------------------', 'Git    Git.Git     2.45.0   winget  Pinning') } }; $c = 0; if ($WgArgs -contains 'Bad.Pkg') { $c = 1 }; return @{ Code = $c; Lines = @('x') } }
function Write-WingetLines { param($Lines) }
$script:Log.Clear()
$pn = Job_WingetPin @{ Action = 'add'; Ids = @('Git.Git', 'Bad.Pkg', 'x; calc') }
Assert-Eq $pn.Done 1 'bir paket sabitlendi'
Assert-True (-not $pn.Ok) 'hata varsa Ok degil'
Assert-Eq $script:WgCalls[0] 'pin add --id Git.Git --exact --accept-source-agreements --disable-interactivity' 'pin add argumanlari'
Assert-Eq $script:WgCalls.Count 2 'gecersiz kimlik cagrilmaz'
$script:WgCalls.Clear()
$pr = Job_WingetPin @{ Action = 'remove'; Ids = @('Git.Git') }
Assert-True ($pr.Ok -and $script:WgCalls[0] -like 'pin remove --id Git.Git*') 'pin remove'
$px = Job_WingetPin @{ Action = 'delete'; Ids = @('Git.Git') }
Assert-True (-not $px.Ok -and $px.Done -eq 0) 'bilinmeyen eylem reddedilir'
$pl = Job_WingetPinList @{}
Assert-Eq (@($pl.Ids) -join ',') 'Git.Git' 'sabitli listesi'

# ======================= 4) BitLocker =======================
Assert-Eq (Get-BlProtectorName 3) 'Kurtarma parolası' 'koruyucu adi'
Assert-Eq (Get-BlProtectorName 99) 'Bilinmeyen' 'bilinmeyen koruyucu'
Assert-Eq (Get-BlStatusText 1 1 100) 'Şifreli ve koruma açık' 'durum: acik'
Assert-Eq (Get-BlStatusText 0 1 100) 'Şifreli ama koruma askıda' 'durum: askida'
Assert-Eq (Get-BlStatusText 0 0 0) 'Şifreli değil' 'durum: degil'
Assert-Eq (Get-BlStatusText 1 2 37) 'Şifreleniyor (%37)' 'durum: suruyor'
$script:Bl = @{
    'C:' = @{ Prot = 1; Conv = 1; Pct = 100; Rec = @('{ID-1}'); Types = @(1, 3); Pass = '111111-222222-333333-444444-555555-666666-777777-888888' }
    'D:' = @{ Prot = 0; Conv = 0; Pct = 0; Rec = @(); Types = @(); Pass = '' }
}
function Get-CimInstance { param($Namespace, $ClassName, $Filter, $ErrorAction)
    foreach ($k in $script:Bl.Keys) {
        if ($Filter -and $Filter -notlike ("*'" + $k + "'*")) { continue }
        [pscustomobject]@{ DriveLetter = $k; ProtectionStatus = $script:Bl[$k].Prot }
    }
}
function Invoke-CimMethod { param($InputObject, $MethodName, $Arguments, $ErrorAction)
    $d = $script:Bl[[string]$InputObject.DriveLetter]
    switch ($MethodName) {
        'GetConversionStatus' { return [pscustomobject]@{ ConversionStatus = $d.Conv; EncryptionPercentage = $d.Pct } }
        'GetKeyProtectors' { if ($Arguments.KeyProtectorType -eq 3) { return [pscustomobject]@{ VolumeKeyProtectorID = @($d.Rec) } } else { return [pscustomobject]@{ VolumeKeyProtectorID = @($d.Types | ForEach-Object { '{T' + $_ + '}' }) } } }
        'GetKeyProtectorType' { return [pscustomobject]@{ KeyProtectorType = [int](([string]$Arguments.VolumeKeyProtectorID).Trim('{T}')) } }
        'GetKeyProtectorNumericalPassword' { return [pscustomobject]@{ NumericalPassword = $d.Pass } }
    }
}
$vols = @(Get-BitLockerVolumes)
Assert-Eq $vols.Count 2 'iki surucu'
$vc = @($vols | Where-Object { $_.Drive -eq 'C:' })[0]
Assert-True ($vc.HasRecovery -and $vc.Protection -eq 1 -and (@($vc.Types) -join ',') -eq '1,3') 'C: kurtarma parolasi var'
$info = Job_BitLockerInfo @{}
$ci = @($info.Rows | Where-Object { $_.Drive -eq 'C:' })[0]
Assert-True ($ci.Protected -and $ci.HasRecovery -and $ci.Protectors -eq 'TPM, Kurtarma parolası') 'C: satiri'
$di = @($info.Rows | Where-Object { $_.Drive -eq 'D:' })[0]
Assert-True ((-not $di.Protected) -and (-not $di.Encrypted)) 'D: sifreli degil'
$script:Log.Clear()
$k = Job_BitLockerKey @{ Drive = 'c' }
Assert-True ($k.Ok -and $k.Keys.Count -eq 1 -and $k.Keys[0].Password -like '111111-*') 'anahtar okunur (c -> C:)'
Assert-True (-not (Log-Has '111111')) 'parola gunluge yazilmaz'
Assert-True (-not (Job_BitLockerKey @{ Drive = 'C:\x' }).Ok) 'gecersiz surucu reddedilir'
Assert-True (-not (Job_BitLockerKey @{ Drive = 'D:' }).Ok) 'anahtari olmayan surucu Ok degil'
$txt = Format-BlKeyFile 'C:' $k.Keys
Assert-True ($txt -match 'TESTPC' -and $txt -match '111111-222222' -and $txt -match 'DIŞINDA') 'anahtar dosyasi metni'
# saglik denetimi
$env:SystemDrive = 'C:'
$script:Findings.Clear()
Chk_BitLocker
Assert-True (@($script:Findings | Where-Object { $_.Id -eq 'bl' -and $_.Status -eq 'ok' }).Count -eq 1) 'C: sifreli -> ok'
$kf = @($script:Findings | Where-Object { $_.Id -eq 'bl-key' })
Assert-True ($kf.Count -eq 1 -and $kf[0].Status -eq 'info' -and $kf[0].Action.Page -eq 'backup' -and $kf[0].Action.Sub -eq 'bl') 'anahtar kopyasi hatirlatmasi'
$script:Bl['C:'].Rec = @(); $script:Bl['C:'].Types = @(1)
$script:Findings.Clear(); Chk_BitLocker
$kf2 = @($script:Findings | Where-Object { $_.Id -eq 'bl-key' })
Assert-True ($kf2.Count -eq 1 -and $kf2[0].Status -eq 'warn' -and $kf2[0].Weight -eq 6) 'kurtarma parolasi yoksa uyari'
$script:Bl['C:'].Prot = 0; $script:Bl['C:'].Conv = 0
$script:Findings.Clear(); Chk_BitLocker
Assert-True (@($script:Findings | Where-Object { $_.Id -eq 'bl' -and $_.Status -eq 'warn' }).Count -eq 1 -and @($script:Findings | Where-Object { $_.Id -eq 'bl-key' }).Count -eq 0) 'sifreli degil -> uyari, anahtar bulgusu yok'
$env:SystemDrive = 'Z:'
$script:Findings.Clear(); Chk_BitLocker
Assert-True (@($script:Findings | Where-Object { $_.Id -eq 'bl' -and $_.Status -eq 'info' }).Count -eq 1) 'surucu bulunamazsa bilgi'
Remove-Item function:Get-CimInstance; Remove-Item function:Invoke-CimMethod

# ======================= 4b) Defender tarama yasi =======================
# Hic taranmadiysa Defender 4294967295 (UInt32.MaxValue) dondurur; [int] donusumu tasar ve iki deger birlikte yitirilirdi
function Get-CimInstance { param($Namespace, $ClassName, $ErrorAction) return @() }
function Get-MpPreference { param($ErrorAction) return [pscustomobject]@{ ExclusionPath = @(); ExclusionExtension = @(); ExclusionProcess = @() } }
function New-MpStatus($Quick, $Full) { return [pscustomobject]@{ RealTimeProtectionEnabled = $true; AntivirusSignatureAge = 1; QuickScanAge = $Quick; FullScanAge = $Full; IsTamperProtected = $true } }
function Get-ScanFinding { return @($script:Findings | Where-Object { $_.Id -eq 'av-scan' }) }
$never = [uint32]4294967295
function Get-MpComputerStatus { param($ErrorAction) return (New-MpStatus $never $never) }
$script:Findings.Clear(); $Error.Clear(); Chk_Defender
Assert-Eq @(Get-ScanFinding).Count 1 'hic taranmadi (4294967295 / 4294967295) -> uyari'
Assert-Eq $Error.Count 0 'hic taranmadi: donusum hatasi uretilmez'
function Get-MpComputerStatus { param($ErrorAction) return (New-MpStatus $never 5) }
$script:Findings.Clear(); Chk_Defender
Assert-Eq @(Get-ScanFinding).Count 0 'hizli tarama hic yok ama 5 gun once tam tarama var -> uyari yok'
function Get-MpComputerStatus { param($ErrorAction) return (New-MpStatus 3 $never) }
$script:Findings.Clear(); Chk_Defender
Assert-Eq @(Get-ScanFinding).Count 0 '3 gun once hizli tarama var, tam tarama hic yok -> uyari yok'
function Get-MpComputerStatus { param($ErrorAction) return (New-MpStatus 20 40) }
$script:Findings.Clear(); Chk_Defender
Assert-Eq @(Get-ScanFinding).Count 1 '20 / 40 gun -> uyari'
function Get-MpComputerStatus { param($ErrorAction) return (New-MpStatus 20 10) }
$script:Findings.Clear(); Chk_Defender
Assert-Eq @(Get-ScanFinding).Count 0 'tam tarama 10 gun once -> uyari yok'
function Get-MpComputerStatus { param($ErrorAction) return (New-MpStatus $null $null) }
$script:Findings.Clear(); Chk_Defender
Assert-Eq @(Get-ScanFinding).Count 0 'degerler okunamazsa (bos) yanlis uyari verilmez'
Remove-Item function:Get-CimInstance, function:Get-MpPreference, function:Get-MpComputerStatus, function:New-MpStatus, function:Get-ScanFinding

# ======================= 5) restic =======================
Assert-Eq (Format-ProcessArg 'abc') 'abc' 'bosluksuz arguman aynen'
Assert-Eq (Format-ProcessArg 'a b') '"a b"' 'bosluklu arguman tirnaklanir'
Assert-Eq (Format-ProcessArg '') '""' 'bos arguman'
Assert-Eq (Format-ProcessArg 'a "b" c') '"a \"b\" c"' 'ic tirnak kacirilir'
Assert-Eq (Format-ProcessArg 'C:\dir with space\') '"C:\dir with space\\"' 'sondaki ters bolu ikilenir'
Assert-Eq (Get-ResticRepoPath '/mnt/yedek') '/mnt/yedek/Multimizer-TESTPC.restic' 'depo yolu'
$ba = New-ResticBackupArgs '/r' @('/src a', '/src b') $true
Assert-True ($ba[0] -eq 'backup' -and $ba -contains '--dry-run' -and $ba -contains '--json') 'yedek argumanlari + onizleme'
Assert-True (($ba[($ba.Count - 2)] -eq '/src a') -and ($ba[($ba.Count - 1)] -eq '/src b')) 'kaynaklar sonda'
Assert-True ($ba -contains 'node_modules' -and $ba -contains '*.tmp') 'cop adlar disarida'
$ba2 = New-ResticBackupArgs '/r' @('/s') $false
Assert-True ($ba2 -notcontains '--dry-run') 'gercek yedekte dry-run yok'
Assert-True ($null -eq (Get-ResticSummary @('{"message_type":"status","percent_done":0.5}', 'oyle bir satir'))) 'ozet yoksa null'
$sm = Get-ResticSummary @('{"message_type":"status","percent_done":0.5}', '{"message_type":"summary","total_files_processed":12,"total_bytes_processed":3456,"data_added":789,"snapshot_id":"abcd1234"}')
Assert-True ($sm.total_files_processed -eq 12 -and $sm.snapshot_id -eq 'abcd1234') 'ozet satiri'
Assert-True ((Get-ResticErrorText 'Fatal: wrong password or no key found' 1) -match 'Parola yanlış') 'yanlis parola metni'
Assert-True ((Get-ResticErrorText 'repository is already locked by PID 1' 1) -match 'kilitli') 'kilit metni'
Assert-True ((Get-ResticErrorText '' 7) -match '7') 'bos hata -> kod'

# sahte restic
$fake = Join-Path $tmp 'restic'
$script:FakeLog = Join-Path $tmp 'restic-calls.txt'
@'
#!/bin/bash
echo "$*" >> "$FAKE_LOG"
cmd="$1"; shift
repo=""; target=""; dry=0; snap=""
args=("$@")
for ((i=0;i<${#args[@]};i++)); do
  case "${args[$i]}" in
    --repo) repo="${args[$((i+1))]}";;
    --target) target="${args[$((i+1))]}";;
    --dry-run) dry=1;;
  esac
done
if [ "$cmd" = "init" ]; then
  if [ -z "$RESTIC_PASSWORD" ]; then echo "Fatal: no password" >&2; exit 1; fi
  mkdir -p "$repo"; echo "{}" > "$repo/config"; echo "created restic repository"; exit 0
fi
if [ "$RESTIC_PASSWORD" != "dogru-parola-123" ]; then echo "Fatal: wrong password or no key found" >&2; exit 1; fi
case "$cmd" in
  backup)
    echo '{"message_type":"status","percent_done":0.4}'
    if [ $dry = 1 ]; then
      echo '{"message_type":"summary","total_files_processed":5,"total_bytes_processed":1000,"data_added":500}'
    else
      echo '{"message_type":"summary","total_files_processed":5,"total_bytes_processed":1000,"data_added":500,"snapshot_id":"abcdef0123456789abcdef0123456789"}'
      echo '[{"id":"abcdef0123456789abcdef0123456789","short_id":"abcdef01","time":"2026-10-12T20:00:00.123456789+03:00","hostname":"TESTPC","paths":["/s1","/s2"]},{"id":"0123456789abcdef0123456789abcdef","short_id":"01234567","time":"2026-10-05T20:00:00Z","hostname":"TESTPC","paths":["/s1"]}]' > "$repo/snaps.json"
    fi
    exit 0;;
  snapshots)
    if [ -f "$repo/snaps.json" ]; then cat "$repo/snaps.json"; else echo '[]'; fi; exit 0;;
  forget) echo "forgot"; exit 0;;
  restore)
    mkdir -p "$target/s1"; echo hi > "$target/s1/restored.txt"; echo "restoring"; exit 0;;
esac
exit 2
'@ | Set-Content -LiteralPath $fake -Encoding ascii
& chmod +x $fake
$env:FAKE_LOG = $script:FakeLog
$old = $env:PATH
$env:PATH = $tmp + [System.IO.Path]::PathSeparator + $env:PATH
Assert-Eq (Find-Restic) $fake 'Find-Restic PATH icinde bulur'
$env:PATH = $old
Assert-Eq (Find-Restic) '' 'restic yoksa bos dondurur'
function Find-Restic { return $fake }

$ir = Invoke-Restic $fake @('snapshots', '--repo', '/x') 'yanlis'
Assert-True ($ir.Code -eq 1 -and $ir.Err -match 'wrong password') 'Invoke-Restic: yanlis parola stderr + kod'
$seen = New-Object System.Collections.ArrayList
$ir2 = Invoke-Restic $fake @('backup', '--repo', '/x', '--json') 'dogru-parola-123' { param($l) [void]$seen.Add($l) }
Assert-True ($ir2.Code -eq 0 -and $ir2.Lines.Count -eq 2 -and $seen.Count -eq 2) 'Invoke-Restic: satirlar ve geri cagri'

$src1 = Join-Path $tmp 's1'; $src2 = Join-Path $tmp 's2'; $dest = Join-Path $tmp 'hedef'
foreach ($d in $src1, $src2, $dest) { New-Item -ItemType Directory -Path $d | Out-Null }
[System.IO.File]::WriteAllText((Join-Path $src1 'x.txt'), 'merhaba'); [System.IO.File]::WriteAllText((Join-Path $src2 'y.txt'), 'dunya')
$script:Settings.BackupSources = @($src1, $src2); $script:Settings.BackupDest = $dest
$repo = Get-ResticRepoPath $dest

# onizleme (depo yok): hicbir sey yazilmaz
$script:Log.Clear()
$pv = Job_ResticBackup @{ Preview = $true; Password = 'dogru-parola-123' }
Assert-True ($pv.Ok -and $pv.Preview -and $pv.Files -eq 2) 'depo yokken onizleme dosyalari sayar'
Assert-True (-not (Test-Path -LiteralPath $repo)) 'onizleme depo olusturmaz'
# kisa parola
Assert-True (-not (Job_ResticBackup @{ Preview = $false; Password = 'kisa' }).Ok) 'kisa parola reddedilir'
# hedef kaynagin icinde
if ([System.IO.Path]::DirectorySeparatorChar -eq '\') {
    $script:Settings.BackupDest = $src1
    Assert-True (-not (Job_ResticBackup @{ Preview = $false; Password = 'dogru-parola-123' }).Ok) 'hedef kaynagin icindeyse reddedilir'
}
$script:Settings.BackupDest = $dest
# gercek yedek
Set-Content -LiteralPath $script:FakeLog -Value '' -Encoding ascii
$rb = Job_ResticBackup @{ Preview = $false; Password = "dogru-parola-123" }
Assert-True $rb.Ok 'sifreli yedek basarili'
Assert-Eq $rb.Files 5.0 'islenen dosya sayisi'
Assert-Eq $rb.Snapshot 'abcdef0123456789abcdef0123456789' 'sürüm kimligi'
Assert-True (Test-ResticRepo $repo) 'depo olustu'
Assert-True ($script:Settings.LastBackup -match '^\d{4}-\d\d-\d\d \d\d:\d\d$') 'son yedek tarihi yazildi'
$calls = Get-Content -LiteralPath $script:FakeLog | Where-Object { $_ -ne '' }
Assert-True ($calls[0] -like 'init --repo *') 'ilk cagri init'
Assert-True ($calls[1] -like 'backup --repo * --json --tag multimizer --exclude-caches*') 'ikinci cagri backup'
Assert-True ($calls[1] -like ('*' + $src1 + ' ' + $src2)) 'kaynaklar komutta'
Assert-True ($calls[2] -like 'forget --repo * --tag multimizer --keep-last 7 --keep-weekly 4 --keep-monthly 6 --prune') 'surum politikasi'
Assert-True (-not (($calls -join "`n") -match 'dogru-parola')) 'parola komut satirinda gorunmez'
Assert-True (-not (Log-Has 'dogru-parola')) 'parola gunlukte gorunmez'
# ikinci yedek init yapmaz
Set-Content -LiteralPath $script:FakeLog -Value '' -Encoding ascii
$rb2 = Job_ResticBackup @{ Preview = $false; Password = 'dogru-parola-123' }
$calls2 = Get-Content -LiteralPath $script:FakeLog | Where-Object { $_ -ne '' }
Assert-True ($rb2.Ok -and $calls2[0] -like 'backup *') 'depo varsa init yapilmaz'
# yanlis parola
$script:Log.Clear()
$rw = Job_ResticBackup @{ Preview = $false; Password = 'yanlis-parola-1' }
Assert-True (-not $rw.Ok -and (Log-Has 'Parola yanlış')) 'yanlis parola acik bir metinle bildirilir'
# depo varken onizleme: restic --dry-run
Set-Content -LiteralPath $script:FakeLog -Value '' -Encoding ascii
$pv2 = Job_ResticBackup @{ Preview = $true; Password = 'dogru-parola-123' }
$calls3 = Get-Content -LiteralPath $script:FakeLog | Where-Object { $_ -ne '' }
Assert-True ($pv2.Ok -and $pv2.Preview -and @($calls3).Count -eq 1 -and @($calls3)[0] -like '*--dry-run*') 'depo varken onizleme dry-run, forget yok'
Assert-Eq $pv2.Added 500.0 'onizlemede eklenecek veri'

# surumler
$sn = Job_ResticSnapshots @{ Password = 'dogru-parola-123' }
Assert-True ($sn.Ok -and $sn.Rows.Count -eq 2) 'iki surum'
Assert-Eq $sn.Rows[0].Short 'abcdef01' 'en yeni ustte'
Assert-True ($sn.Rows[0].TimeText -match '^2026-10-1[23] \d\d:\d\d$') 'zaman metni'
Assert-Eq $sn.Rows[0].Paths '/s1, /s2' 'yollar'
Assert-True (-not (Job_ResticSnapshots @{ Password = 'yanlis' }).Ok) 'surum listesi yanlis parolada Ok degil'
$sn0 = Job_ResticSnapshots @{ Dest = (Join-Path $tmp 'baska'); Password = 'dogru-parola-123' }
Assert-True ($sn0.Ok -and $sn0.Rows.Count -eq 0) 'depo yoksa bos liste'

# geri yukleme
$tg = Join-Path $tmp 'geri'; New-Item -ItemType Directory -Path $tg | Out-Null
Assert-True (-not (Job_ResticRestore @{ Password = 'dogru-parola-123'; Snapshot = 'zzz'; Target = $tg }).Ok) 'gecersiz surum kimligi'
Assert-True (-not (Job_ResticRestore @{ Password = 'dogru-parola-123'; Snapshot = 'latest; calc'; Target = $tg }).Ok) 'enjeksiyon reddedilir'
Assert-True (-not (Job_ResticRestore @{ Password = 'dogru-parola-123'; Snapshot = 'latest'; Target = (Join-Path $tmp 'yok') }).Ok) 'hedef klasor yoksa reddedilir'
[System.IO.File]::WriteAllText((Join-Path $tg 'var.txt'), 'x')
Assert-True (-not (Job_ResticRestore @{ Password = 'dogru-parola-123'; Snapshot = 'latest'; Target = $tg }).Ok) 'dolu klasore geri yukleme reddedilir'
Remove-Item -LiteralPath (Join-Path $tg 'var.txt')
$rr = Job_ResticRestore @{ Password = 'dogru-parola-123'; Snapshot = 'abcdef01'; Target = $tg }
Assert-True ($rr.Ok -and (Test-Path -LiteralPath (Join-Path $tg 's1/restored.txt'))) 'geri yukleme calisir'

# zamanlanmis / komut satiri yedegi sifreli kipte atlanmali (Job_Backup yama ile degisti)
Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
Show-Result
