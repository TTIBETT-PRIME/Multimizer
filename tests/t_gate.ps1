. "$PSScriptRoot/lib.ps1"
# Güvenlik kapısı: Windows Update, Defender, Güvenlik Duvarı, UAC ve Microsoft Store kapatılmaz (README'deki söz).
# Kayıt defteri yazma katmanı + katalogun TAMAMI (temel + genişletilmiş) kod düzeyinde denetlenir. Yasak listesinin kendisi
# yazdırılmaz; yalnızca "engellendi mi" sonucu sınanır. Kurallar yalnızca eklenebilir: aşağıdaki "engelli olmalı" listesi gevşetilemez.

Import-Fn 'RegOp', 'RegDel', 'FuncOp', 'FeatOp', 'SvcOp', 'TaskOp', 'MpOp', 'FwOp', 'EvtOp', 'CapOp', 'DxGlobalOp', 'NetLatencyOp', 'Add-Tweak', 'Add-RegTweak', 'Test-RegWriteBlocked', 'Resolve-RegPath', 'Get-TargetSid'
Import-Var 'RegDenyPath', 'RegDenyName', 'SvcLockList'

$sync = @{ TargetSid = '' }

# ======================= 1) engelli olmalı =======================
$mustBlock = @(
    # Defender (ilke)
    @('HKLM\SOFTWARE\Policies\Microsoft\Windows Defender', 'DisableAntiSpyware'),
    @('HKLM\SOFTWARE\Policies\Microsoft\Windows Defender', 'DisableRoutinelyTakingAction'),
    @('HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection', 'DisableRealtimeMonitoring'),
    @('HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection', 'DisableBehaviorMonitoring'),
    @('HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection', 'DisableOnAccessProtection'),
    @('HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection', 'DisableIOAVProtection'),
    # Defender (kendi anahtarları, Kurcalama Koruması) - 7.1.1'de eklendi
    @('HKLM\SOFTWARE\Microsoft\Windows Defender', 'DisableAntiSpyware'),
    @('HKLM\SOFTWARE\Microsoft\Windows Defender', 'DisableAntiVirus'),
    @('HKLM\SOFTWARE\Microsoft\Windows Defender\Real-Time Protection', 'DisableRealtimeMonitoring'),
    @('HKLM\SOFTWARE\Microsoft\Windows Defender\Features', 'TamperProtection'),
    # Güvenlik Duvarı
    @('HKLM\SOFTWARE\Policies\Microsoft\WindowsFirewall\DomainProfile', 'EnableFirewall'),
    @('HKLM\SOFTWARE\Policies\Microsoft\WindowsFirewall\StandardProfile', 'EnableFirewall'),
    @('HKLM\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\StandardProfile', 'EnableFirewall'),
    # UAC
    @('HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System', 'EnableLUA'),
    @('HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System', 'ConsentPromptBehaviorAdmin'),
    @('HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System', 'PromptOnSecureDesktop'),
    @('HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System', 'FilterAdministratorToken'),
    @('HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System', 'LocalAccountTokenFilterPolicy'),
    # Windows Update
    @('HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU', 'NoAutoUpdate'),
    @('HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU', 'AUOptions'),
    @('HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU', 'UseWUServer'),
    @('HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate', 'DisableWindowsUpdateAccess'),
    @('HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate', 'DoNotConnectToWindowsUpdateInternetLocations'),
    @('HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate', 'WUServer'),
    @('HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate', 'SetDisableUXWUAccess'),
    # Microsoft Store - 7.1.1'de eklendi
    @('HKLM\SOFTWARE\Policies\Microsoft\WindowsStore', 'RemoveWindowsStore'),
    @('HKLM\SOFTWARE\Policies\Microsoft\WindowsStore', 'DisableStoreApps'),
    @('HKLM\SOFTWARE\Policies\Microsoft\WindowsStore', 'RequirePrivateStoreOnly'),
    # SmartScreen, Güvenlik Merkezi uyarıları, Sistem Koruması - 7.1.1'de eklendi
    @('HKLM\SOFTWARE\Policies\Microsoft\Windows\System', 'EnableSmartScreen'),
    @('HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer', 'SmartScreenEnabled'),
    @('HKLM\SOFTWARE\Microsoft\Security Center', 'AntiVirusDisableNotify'),
    @('HKLM\SOFTWARE\Microsoft\Security Center', 'FirewallDisableNotify'),
    @('HKLM\SOFTWARE\Microsoft\Security Center', 'UpdatesDisableNotify'),
    @('HKLM\SOFTWARE\Policies\Microsoft\Windows NT\SystemRestore', 'DisableSR'),
    @('HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore', 'DisableSR')
)
foreach ($svc in @('WinDefend', 'WdNisSvc', 'WdFilter', 'Sense', 'SecurityHealthService', 'wscsvc', 'mpssvc', 'BFE', 'wuauserv', 'UsoSvc', 'WaaSMedicSvc')) {
    $mustBlock += , @(('HKLM\SYSTEM\CurrentControlSet\Services\' + $svc), 'Start')
}
foreach ($pair in $mustBlock) {
    Assert-True ((Test-RegWriteBlocked $pair[0] $pair[1]) -ne '') ('engelli olmalı: ' + $pair[0].Replace('HKLM\SOFTWARE\', 'HKLM\S\') + ' \ ' + $pair[1])
}

# ======================= 2) izinli olmalı (gereksiz engel katalogu bozmasın) =======================
$mustAllow = @(
    @('HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection', 'AllowTelemetry'),
    @('HKLM\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization', 'DODownloadMode'),
    @('HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU', 'NoAutoRebootWithLoggedOnUsers'),
    @('HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate', 'SetActiveHours'),
    @('HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate', 'DeferFeatureUpdates'),
    @('HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate', 'ExcludeWUDriversInQualityUpdate'),
    @('HKLM\SOFTWARE\Policies\Microsoft\WindowsStore', 'AutoDownload'),
    @('HKLM\SYSTEM\CurrentControlSet\Control\Lsa', 'RunAsPPL'),
    @('HKLM\SOFTWARE\Policies\Microsoft\Dsh', 'AllowNewsAndInterests'),
    @('HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System', 'InactivityTimeoutSecs'),
    @('HKU\S-1-5-21-1\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced', 'TaskbarDa')
)
foreach ($pair in $mustAllow) {
    Assert-Eq (Test-RegWriteBlocked $pair[0] $pair[1]) '' ('izinli olmalı: ' + $pair[0].Replace('HKLM\SOFTWARE\', 'HKLM\S\') + ' \ ' + $pair[1])
}

# ======================= 3) katalogun tamamı =======================
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
. ([scriptblock]::Create($src.Substring($i0, $i1 - $i0)))
$baseN = $script:Catalog.Count
. ([scriptblock]::Create($src.Substring($k0, $k1 - $k0)))
Assert-True ($baseN -ge 80) ('temel katalog yüklendi: ' + $baseN)
Assert-True ($script:Catalog.Count -ge $baseN + 100) ('genişletilmiş katalog yüklendi: ' + $script:Catalog.Count)

$ids = @($script:Catalog | ForEach-Object { [string]$_.Id })
Assert-True ($ids -notcontains 'StoreOff') 'Microsoft Store''u kapatan ayar katalogda yok'
$badName = '^(DisableAntiSpyware|DisableAntiVirus|DisableRealtimeMonitoring|DisableBehaviorMonitoring|DisableOnAccessProtection|DisableIOAVProtection|EnableLUA|ConsentPromptBehaviorAdmin|ConsentPromptBehaviorUser|PromptOnSecureDesktop|EnableSmartScreen|SmartScreenEnabled|NoAutoUpdate|AUOptions|DisableWindowsUpdateAccess|SetDisableUXWUAccess|RemoveWindowsStore|DisableStoreApps|RequirePrivateStoreOnly|EnableFirewall|TamperProtection|AntiVirusDisableNotify|FirewallDisableNotify|UpdatesDisableNotify|DisableSR)$'
$badReg = @(); $blocked = @(); $badSvc = @(); $badTask = @(); $badFeat = @(); $badFw = @()
foreach ($c in $script:Catalog) {
    foreach ($op in @($c.Ops)) {
        switch ([string]$op.T) {
            'Reg' {
                if ([string]$op.Name -match $badName) { $badReg += [string]$c.Id }
                if ((Test-RegWriteBlocked (Resolve-RegPath ([string]$op.Path)) ([string]$op.Name)) -ne '') { $blocked += [string]$c.Id }
            }
            'Svc' {
                foreach ($rx in @($script:SvcLockList)) { if ([string]$op.Name -match $rx) { $badSvc += ([string]$c.Id + ':' + [string]$op.Name) } }
            }
            'Task' {
                if ([string]$op.Path -match 'WindowsUpdate|UpdateOrchestrator|Windows Defender|SystemRestore|WindowsBackup') { $badTask += ([string]$c.Id + ':' + [string]$op.Name) }
            }
            'Feature' {
                if ([string]$op.Name -match 'Defender|Firewall|SmartScreen|Windows-Defender') { $badFeat += ([string]$c.Id + ':' + [string]$op.Name) }
            }
            'Fw' {
                # güvenlik duvarı profilleri kapatılmaz; yalnızca kural grupları (ör. Uzak Masaüstü) açılıp kapatılabilir
                if ([string]$op.Group -ne '@FirewallAPI.dll,-28752') { $badFw += [string]$c.Id }
            }
        }
    }
}
Assert-Eq ($badReg -join ',') '' 'katalog: güvenlik kapısını kapatan kayıt değeri yok'
Assert-Eq ($blocked -join ',') '' 'katalog: hiçbir ayar güvenlik kapısına takılmıyor'
Assert-Eq ($badSvc -join ',') '' 'katalog: kilitli hizmetlere dokunulmuyor'
Assert-Eq ($badTask -join ',') '' 'katalog: Windows Update / Defender / Sistem Koruması görevlerine dokunulmuyor'
Assert-Eq ($badFeat -join ',') '' 'katalog: Defender / Güvenlik Duvarı / SmartScreen özelliklerine dokunulmuyor'
Assert-Eq ($badFw -join ',') '' 'katalog: güvenlik duvarı profilleri değil, yalnızca kural grupları'

Show-Result
