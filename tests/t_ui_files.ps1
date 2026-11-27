. "$PSScriptRoot/lib.ps1"
Import-Fn 'Get-DupFullGroups', 'Get-UseCaseTitle', 'Job_BitLockerAddKey', 'Get-TargetSid', 'Resolve-RegPath', 'Test-RegWriteBlocked',
    'RegOp', 'RegDel', 'ConvertFrom-WuTime', 'Get-WuControlState', 'New-WuPauseSteps', 'New-WuDeferSteps', 'New-WuDriverSteps'
Import-Var 'UseCases', 'RegDenyPath', 'RegDenyName', 'WuUxKey', 'WuPolKey'

# ---- ortak bakliklar ----
$script:Log = New-Object System.Collections.ArrayList
function Write-WhLog { param([string]$Text, [string]$Level = 'INFO') [void]$script:Log.Add($Level + '|' + $Text) }
function Log-Has([string]$Needle) { foreach ($l in $script:Log) { if ($l.Contains($Needle)) { return $true } }; return $false }
$sync = @{ TargetSid = '' }

# ======================= 1) kopya gruplarinda en az biri kalmali =======================
$two = @(@{ Group = '1' }, @{ Group = '1' })
Assert-Eq @(Get-DupFullGroups $two @{ '1' = 2 }).Count 1 'iki kopyanin ikisi de isaretli: grup yakalanir'
Assert-Eq @(Get-DupFullGroups $two @{ '1' = 3 }).Count 0 'uc kopyadan ikisi isaretli: sorun yok'
Assert-Eq @(Get-DupFullGroups @() @{ '1' = 2 }).Count 0 'hic isaret yok: sorun yok'
$mix = @(@{ Group = '1' }, @{ Group = '2' }, @{ Group = '2' })
$full = @(Get-DupFullGroups $mix @{ '1' = 2; '2' = 2 })
Assert-Eq $full.Count 1 'iki gruptan yalnizca biri tamamen isaretli'
Assert-Eq $full[0] '2' 'tamamen isaretli grup 2'
Assert-Eq @(Get-DupFullGroups @(@{ Group = '7' }) @{ '1' = 2 }).Count 0 'bilinmeyen grup yok sayilir'

# ======================= 2) kullanim turleri =======================
Assert-True ($script:UseCases.Count -ge 4) 'en az dort kullanim turu'
foreach ($k in @($script:UseCases.Keys)) {
    $u = $script:UseCases[$k]
    Assert-True ([string]$u.T -ne '' -and [string]$u.D -ne '' -and [string]$u.Hint -ne '' -and [string]$u.Page -ne '') ($k + ': metinler dolu')
    Assert-Eq (Get-UseCaseTitle $k) $u.T ($k + ': baslik')
}
foreach ($must in 'home', 'gamer', 'privacy', 'helper') { Assert-True ($script:UseCases.Contains($must)) ('plandaki tur var: ' + $must) }
Assert-Eq (Get-UseCaseTitle 'yok') 'Seçilmedi' 'bilinmeyen anahtar'
Assert-Eq (Get-UseCaseTitle '') 'Seçilmedi' 'bos anahtar'
# secim kutusunun dugmeleri (ilk acilis sorusu) sola hizali BtnChoice stiliyle cizilir; BtnGhost ortalar ve baslik / aciklama hizasi bozulurdu
$scFn = @(Get-AstFunctions | Where-Object { ($_.Name -replace '^global:', '') -eq 'Show-Choice' }) | Select-Object -Last 1
$scTxt = ''
if ($null -ne $scFn) { $scTxt = [string]$scFn.Extent.Text }
Assert-True ($scTxt.Length -gt 200) 'Show-Choice islevi derlenmis dosyada bulunur'
Assert-True ($scTxt.Contains("FindResource('BtnChoice')") -and -not $scTxt.Contains("FindResource('BtnGhost')")) 'secim kutusu dugmeleri BtnChoice stiliyle cizilir (sola hizali)'
Assert-True (-not $scTxt.Contains('HorizontalContentAlignment')) 'secim kutusu: hiza stilden gelir, dugme ayrica ayarlanmaz'

# ======================= 3) BitLocker kurtarma anahtari ekleme =======================
$script:Vols = @()
function Get-BitLockerVolumes { return $script:Vols }
$script:AddCalls = New-Object System.Collections.ArrayList
$script:AddFail = $false
function Add-BitLockerKeyProtector {
    param($MountPoint, [switch]$RecoveryPasswordProtector, $ErrorAction)
    [void]$script:AddCalls.Add([string]$MountPoint)
    if ($script:AddFail) { throw 'erisim reddedildi' }
    return @{ KeyProtector = @{ RecoveryPassword = '111111-222222-333333' } }
}
function Reset-Bl { $script:Log.Clear(); $script:AddCalls.Clear(); $script:AddFail = $false }

Reset-Bl
$r = Job_BitLockerAddKey @{ Drive = 'C:\Windows' }
Assert-Eq $r.Ok $false 'gecersiz surucu reddedilir'
Assert-Eq $script:AddCalls.Count 0 'gecersiz surucu icin komut calismaz'

Reset-Bl
$script:Vols = @()
$r = Job_BitLockerAddKey @{ Drive = 'C' }
Assert-Eq $r.Ok $false 'BitLocker bilgisi yoksa Ok=false'
Assert-Eq $script:AddCalls.Count 0 'bilgi yoksa komut calismaz'

Reset-Bl
$script:Vols = @(@{ Drive = 'C:'; Protection = 0; Conversion = 0; Percent = 0; Types = @(); RecoveryIds = @(); HasRecovery = $false })
$r = Job_BitLockerAddKey @{ Drive = 'C:' }
Assert-Eq $r.Ok $false 'sifreli olmayan surucuye anahtar eklenmez'
Assert-Eq $script:AddCalls.Count 0 'sifreli degilse komut calismaz'

Reset-Bl
$script:Vols = @(@{ Drive = 'C:'; Protection = 1; Conversion = 1; Percent = 100; Types = @(1, 3); RecoveryIds = @('{x}'); HasRecovery = $true })
$r = Job_BitLockerAddKey @{ Drive = 'C:' }
Assert-Eq $r.Ok $true 'anahtar zaten varsa Ok=true'
Assert-Eq $r.Existing $true 'anahtar zaten var isaretlenir'
Assert-Eq $script:AddCalls.Count 0 'anahtar varken ikincisi eklenmez'

Reset-Bl
$script:Vols = @(@{ Drive = 'C:'; Protection = 1; Conversion = 1; Percent = 100; Types = @(1); RecoveryIds = @(); HasRecovery = $false })
$r = Job_BitLockerAddKey @{ Drive = 'c' }
Assert-Eq $r.Ok $true 'anahtar eklenir'
Assert-Eq $r.Existing $false 'yeni anahtar'
Assert-Eq $script:AddCalls.Count 1 'tek komut'
Assert-Eq $script:AddCalls[0] 'C:' 'kucuk harf surucu C: olur'
Assert-True (Log-Has 'eklendi') 'gunluge eklendi yazilir'
Assert-True (-not (Log-Has '111111')) 'anahtar gunluge yazilmaz'

Reset-Bl
$script:AddFail = $true
$r = Job_BitLockerAddKey @{ Drive = 'C:' }
Assert-Eq $r.Ok $false 'komut hata verirse Ok=false'
Assert-True (Log-Has 'eklenemedi') 'hata gunluge yazilir'
Assert-True (-not (Log-Has '111111')) 'hata durumunda da anahtar yazilmaz'

# ======================= 4) Windows Update denetimi adimlari guvenlik kapisindan gecer =======================
$all = New-Object System.Collections.ArrayList
foreach ($st in @((New-WuPauseSteps 7), (New-WuPauseSteps 0), (New-WuPauseSteps 35), (New-WuDeferSteps 180), (New-WuDeferSteps 365), (New-WuDeferSteps 0), (New-WuDriverSteps $true), (New-WuDriverSteps $false))) {
    foreach ($x in @($st)) { [void]$all.Add($x) }
}
Assert-Eq $all.Count 8 'sekiz adim'
$blocked = 0; $disabling = 0; $ops = 0
foreach ($stp in $all) {
    foreach ($op in @($stp.Ops)) {
        $ops++
        if ((Test-RegWriteBlocked (Resolve-RegPath ([string]$op.Path)) ([string]$op.Name)) -ne '') { $blocked++ }
        if ([string]$op.Name -match '^(NoAutoUpdate|AUOptions|DisableWindowsUpdateAccess|SetDisableUXWUAccess)$') { $disabling++ }
    }
}
Assert-True ($ops -ge 20) ('islem sayisi makul: ' + $ops)
Assert-Eq $blocked 0 'hicbir adim guvenlik kapisina takilmaz'
Assert-Eq $disabling 0 'Windows Update kapatan deger yazilmaz'
Assert-Eq @(New-WuPauseSteps 36).Count 0 '36 gun duraklatma reddedilir'
Assert-Eq @(New-WuPauseSteps -1).Count 0 'eksi gun reddedilir'
Assert-Eq @(New-WuDeferSteps 366).Count 0 '366 gun erteleme reddedilir'

# ======================= 5) derlenmis dosyada ekran bagi =======================
$src = [System.IO.File]::ReadAllText($script:TestPath)
$names = @('cl_Tab_big', 'cl_Tab_dup', 'cl_FScan', 'cl_FPick', 'cl_FAuto', 'cl_FRecycle',
    'up_Tab_ctl', 'up_Tab_inst', 'up_Pause', 'up_Resume', 'up_Defer', 'up_DeferOff', 'up_DrvToggle', 'up_Uninstall', 'up_Pin', 'up_Unpin', 'up_PinList',
    'bk_Tab_bl', 'bk_BlRefresh', 'bk_BlWeb', 'bk_ModeRestic', 'bk_ResticInfo', 'bk_ResticGet', 'bk_ResticSnaps', 'st_UseCase', 'st_UseCaseText', 'OvChoices')
foreach ($n in $names) {
    $c = ([regex]::Matches($src, '<[A-Za-z]+ x:Name="' + $n + '"')).Count
    Assert-Eq $c 1 ('x:Name tek: ' + $n)
}
# sekme dizileri
Assert-True ($src -match "\`$script:ClTabs = @\('clean', 'disk', 'big', 'dup'(, 'compress')?\)") 'temizlik sekme dizisi'
Assert-True ($src -match "\`$script:UpTabs = @\('wu', 'winget', 'ctl', 'inst', 'hist'\)") 'guncelleme sekme dizisi'
Assert-True ($src -match "\`$script:BkTabs = @\('files', 'recycle', 'shadow', 'points', 'recover', 'bl', 'kit'\)") 'yedek sekme dizisi'
# her sekme anahtari icin Set-*Tab/Render dali var
foreach ($k in 'big', 'dup') { Assert-True ($src -match ("'" + $k + "' \{")) ('Set-ClTab dali: ' + $k) }
foreach ($k in 'ctl', 'inst') { Assert-True ($src -match ("'" + $k + "' \{ Render-Up")) ('Render-UpCurrent dali: ' + $k) }
Assert-True ($src -match "'bl' \{ Show-OnlyBar 'bk'") 'Set-BkTab dali: bl'
# her Show-OnlyBar adi gercek bir dugme: butun bar adlari XAML'de tanimli
$barNames = New-Object System.Collections.ArrayList
foreach ($m in [regex]::Matches($src, "Show-OnlyBar '(cl|up|bk)' @\(([^)]*)\)")) {
    foreach ($q in [regex]::Matches($m.Groups[2].Value, "'([A-Za-z_]+)'")) { [void]$barNames.Add($q.Groups[1].Value) }
}
Assert-True ($barNames.Count -gt 30) ('bar adlari okundu: ' + $barNames.Count)
foreach ($bn in ($barNames | Sort-Object -Unique)) { Assert-True ($src -match ('x:Name="' + $bn + '"')) ('bar dugmesi tanimli: ' + $bn) }
# eski ad kalmadi
Assert-True ($src -notmatch 'WinHizlandirici\.ps1') 'eski dosya adi yok'

Remove-Variable src
Show-Result
