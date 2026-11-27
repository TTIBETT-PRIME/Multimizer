. "$PSScriptRoot/lib.ps1"
# Çözüm Merkezi çekirdeği: sorun gidericiler (tablo bütünlüğü, plan adımları, işlemler sahte klasör ve sahte hizmetlerle) ve disk koruma/sağlık planlayıcısı.
Import-Fn 'New-SolveAction', 'Get-SlvTroubleSteps', 'Get-SlvSymptom', 'FuncOp', 'Invoke-FuncOp', 'Stop-SlvService', 'Invoke-RenewIpOp', 'Invoke-NetStackResetOp', 'Invoke-RestartAudioOp',
    'Invoke-ClearSpoolerOp', 'Invoke-ResetWuComponentsOp', 'Get-IconCacheFiles', 'Invoke-RebuildIconCacheOp',
    'Get-BlMethodName', 'Get-BlScope', 'Get-BlScopeText', 'Get-BlState', 'Test-BlEnablePlan', 'Test-BlKeyDir', 'Get-BlKeyFileName', 'Format-SlvMedia', 'Get-SlvDiskRows', 'Add-DiskProtectFindings', 'Add-VolumeHealthFindings',
    'Invoke-ChkdskRepairOp', 'Invoke-SlvDriveAction', 'Invoke-BlResumeAction', 'Get-DiskErrorEvents', 'Get-DiskErrorSummary', 'Get-DiskErrCount', 'Add-DiskErrorFindings',
    'Chk_DiskProtect', 'Chk_DiskErrors', 'Format-Size', 'Get-BlProtectorName', 'Add-Finding', 'New-RunFix', 'New-StepsFix', 'New-FixInfo'
Import-Var 'SlvTabs', 'SlvSymptoms', 'PageTitles', 'ClTabs'

# ---- sahte ortam ----
$script:Findings = New-Object System.Collections.ArrayList
$script:Plans = New-Object System.Collections.ArrayList
$script:Dones = New-Object System.Collections.ArrayList
$script:Skips = New-Object System.Collections.ArrayList
$script:Logs = New-Object System.Collections.ArrayList
$script:Calls = New-Object System.Collections.ArrayList
$script:Preview = $false
$script:MoreOps = @{}
$script:ExtraActions = @{}
$script:FuncOps = @{}
$script:AutoFixRuns = @()
function Add-Plan([string]$Message) { [void]$script:Plans.Add($Message) }
function Add-Done([string]$Message) { [void]$script:Dones.Add($Message) }
function Add-Skip([string]$Message) { [void]$script:Skips.Add($Message) }
function Write-WhLog([string]$Message, [string]$Level = 'INFO') { [void]$script:Logs.Add($Level + ': ' + $Message) }
function Reset-All { $script:Findings.Clear(); $script:Plans.Clear(); $script:Dones.Clear(); $script:Skips.Clear(); $script:Logs.Clear(); $script:Calls.Clear() }
function Steps-Of([string]$Key) { $x = Get-SlvTroubleSteps $Key; return , @($x) }
function Find-F([string]$Id) { foreach ($f in $script:Findings) { if ($f.Id -eq $Id) { return $f } } return $null }

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('mmsolve' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $tmp | Out-Null
$win = Join-Path $tmp 'win'
New-Item -ItemType Directory -Path $win | Out-Null
$env:WINDIR = $win
$la = Join-Path $tmp 'yerel'
New-Item -ItemType Directory -Path $la | Out-Null
$env:LOCALAPPDATA = $la
$env:SystemDrive = 'C:'

# =====================================================================
#  1) sorun giderici tablosu
# =====================================================================
$syms = @($script:SlvSymptoms)
Assert-True ($syms.Count -ge 9) 'en az dokuz belirti tanımlı'
Assert-Eq (($script:SlvTabs) -join ',') 'scan,disk,recover,erase,trouble,pc,prep' 'Çözüm Merkezi sekmeleri'

$allowedFn = @('FlushDns', 'RenewIp', 'NetStackReset', 'TimeSync', 'RestartAudio', 'ClearSpooler', 'ResetWuComponents', 'RebuildIconCache', 'CleanTemp', 'CleanWer', 'OptimizeDrive', 'CleanUpdateCache', 'CleanDumps')
$keys = @{}
$stepIds = @{}
$validPages = @($script:PageTitles.Keys) + @('startup', 'wu', 'compress', 'solve')
foreach ($s in $syms) {
    $k = [string]$s.K
    Assert-True ($k -cmatch '^[a-z]+$') "anahtar küçük harf: $k"
    Assert-True (-not $keys.ContainsKey($k)) "yinelenen belirti: $k"
    $keys[$k] = $true
    Assert-True (([string]$s.T).Length -ge 10) "başlık yazılı: $k"
    Assert-True (([string]$s.D).Length -ge 40) "açıklama yazılı: $k"
    Assert-True (([string]$s.T + [string]$s.D) -notmatch '(?i)\b(yapay zek|chatgpt|gpt|as an ai)') "açıklama kalıntısı yok: $k"
    Assert-True (($s.Reboot -is [bool])) "Reboot mantıksal: $k"
    if ($s.Reboot -eq $true) { Assert-True (@($s.Steps).Count -gt 0) "yeniden başlatma yalnızca adımı olan belirtide: $k" }
    foreach ($st in @($s.Steps)) {
        Assert-True (-not $stepIds.ContainsKey([string]$st.Id)) ("yinelenen adım kimliği: " + $st.Id)
        $stepIds[[string]$st.Id] = $true
        Assert-True (([string]$st.Title).Length -gt 3) ("adım başlığı: " + $st.Id)
        Assert-True ($allowedFn -contains [string]$st.Fn) ("adım yalnızca bilinen güvenli işlemlerden: " + $st.Fn)
    }
    foreach ($g in @($s.Guided)) {
        Assert-True (([string]$g.Label).Length -gt 3) "yönlendirme etiketi: $k"
        if ($null -ne $g.Url) { Assert-True (([string]$g.Url) -cmatch '^ms-settings:[a-z\-]+$') ("yalnızca Ayarlar bağlantısı: " + $g.Url) }
        else {
            Assert-True ($validPages -contains [string]$g.Page) ("yönlendirilen sayfa var: " + $g.Page)
            if ([string]$g.Sub -ne '') {
                if ([string]$g.Page -eq 'clean') { Assert-True ($script:ClTabs -contains [string]$g.Sub) ("temizlik alt sekmesi var: " + $g.Sub) }
                if ([string]$g.Page -eq 'solve') { Assert-True ($script:SlvTabs -contains [string]$g.Sub) ("Çözüm Merkezi alt sekmesi var: " + $g.Sub) }
            }
        }
    }
}
foreach ($k in 'net', 'time', 'audio', 'print', 'wu', 'shell', 'slow', 'full', 'bsod') { Assert-True ($keys.ContainsKey($k)) "yaygın belirti var: $k" }

# ---- FuncOp kaydı: her işlem ya Invoke-FuncOp anahtarında ya da $script:FuncOps tablosunda
$swFn = @($script:Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-FuncOp' }, $true)) | Select-Object -First 1
$sw = @($swFn.Body.FindAll({ param($n) $n -is [System.Management.Automation.Language.SwitchStatementAst] }, $true)) | Select-Object -First 1
$registered = @{}
foreach ($c in $sw.Clauses) { $lab = $c.Item1; if ($lab -is [System.Management.Automation.Language.StringConstantExpressionAst]) { $registered[[string]$lab.Value] = 'switch' } }
$fnOpsInBuild = @{}
foreach ($a in @($script:Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true))) {
    if ($a.Left.Extent.Text -match "^\`$script:FuncOps\['([^']+)'\]$") {
        $nm = $Matches[1]
        $val = $a.Right.Extent.Text.Trim().Trim("'")
        $fnOpsInBuild[$nm] = $val
        $registered[$nm] = 'table'
        $script:FuncOps[$nm] = $val
    }
}
foreach ($s in $syms) { foreach ($st in @($s.Steps)) { Assert-True ($registered.ContainsKey([string]$st.Fn)) ("işlem kayıtlı: " + $st.Fn) } }
$allFnNames = @{}
foreach ($f in (Get-AstFunctions)) { $allFnNames[$f.Name] = $true }
foreach ($k in $fnOpsInBuild.Keys) { Assert-True ($allFnNames.ContainsKey($fnOpsInBuild[$k])) ("kayıtlı işlev tanımlı: $k -> " + $fnOpsInBuild[$k]) }
foreach ($k in 'RenewIp', 'NetStackReset', 'RestartAudio', 'ClearSpooler', 'ResetWuComponents', 'RebuildIconCache') { Assert-True ($fnOpsInBuild.ContainsKey($k)) "yeni işlem tabloda: $k" }
Assert-True ($script:MoreOps.Count -eq 0) 'sahte ortam: MoreOps başlangıçta boş'

# =====================================================================
#  2) plan adımları
# =====================================================================
foreach ($s in $syms) {
    $st = Steps-Of ([string]$s.K)
    Assert-Eq $st.Count @($s.Steps).Count ("adım sayısı: " + $s.K)
    for ($i = 0; $i -lt $st.Count; $i++) {
        Assert-Eq @($st[$i].Ops).Count 1 ("her adımda tek işlem: " + $st[$i].Id)
        Assert-Eq $st[$i].Ops[0].T 'Func' ("işlem türü Func: " + $st[$i].Id)
        Assert-Eq $st[$i].Ops[0].Name ([string]$s.Steps[$i].Fn) ("işlem adı: " + $st[$i].Id)
        $wantRb = ($s.Reboot -eq $true -and $i -eq $st.Count - 1)
        Assert-Eq $st[$i].Reboot $wantRb ("yeniden başlatma yalnızca son adımda: " + $st[$i].Id)
    }
}
Assert-Eq (Steps-Of 'zzz').Count 0 'bilinmeyen belirti: adım yok'
Assert-Eq (Steps-Of 'bsod').Count 0 'mavi ekran belirtisi doğrudan işlem çalıştırmaz'
Assert-Eq (Steps-Of 'net').Count 3 'ağ: üç adım'
Assert-Eq (Get-SlvSymptom 'print').K 'print' 'belirti bulundu'
Assert-True ($null -eq (Get-SlvSymptom 'yok')) 'olmayan belirti boş'
Assert-Eq (New-SolveAction 'disk' '' 'Diskler').Page 'solve' 'eylem sayfası'
Assert-Eq (New-SolveAction 'disk' '' 'Diskler').Sub 'disk' 'eylem alt sekmesi'
Assert-Eq (New-SolveAction 'disk' 'D:' 'Diskler').Arg 'D:' 'eylem bağımsız değişkeni'

# =====================================================================
#  3) işlemler: önizleme hiçbir şey çalıştırmaz
# =====================================================================
function Add-Call([string]$Text) { [void]$script:Calls.Add($Text) }
function ipconfig.exe { Add-Call ('ipconfig ' + ($args -join ' ')); $global:LASTEXITCODE = 0 }
$script:NetshFail = ''
$script:NetshFailCode = 1
function netsh.exe { $t = ($args -join ' '); Add-Call ('netsh ' + $t); if ($script:NetshFail -ne '' -and $t -eq $script:NetshFail) { $global:LASTEXITCODE = $script:NetshFailCode } else { $global:LASTEXITCODE = 0 } }
function Start-Sleep { [CmdletBinding()] param([int]$Seconds, [int]$Milliseconds) }
$script:SvcStatus = @{}
function Get-Service {
    [CmdletBinding()] param([string]$Name)
    if (-not $script:SvcStatus.ContainsKey($Name)) { return }
    $o = [pscustomobject]@{ Name = $Name; Status = $script:SvcStatus[$Name] }
    Add-Member -InputObject $o -MemberType ScriptMethod -Name Refresh -Value { $this.Status = $script:SvcStatus[$this.Name] }
    $o
}
$script:StopStuck = @{}
function Stop-Service { [CmdletBinding()] param([string]$Name, [switch]$Force) Add-Call ('stop ' + $Name); if (-not $script:StopStuck.ContainsKey($Name)) { $script:SvcStatus[$Name] = 'Stopped' } }
function Start-Service { [CmdletBinding()] param([string]$Name) Add-Call ('start ' + $Name); $script:SvcStatus[$Name] = 'Running' }
function Restart-Service { [CmdletBinding()] param([string]$Name, [switch]$Force) Add-Call ('restart ' + $Name); $script:SvcStatus[$Name] = 'Running' }

$script:Preview = $true
foreach ($fn in 'Invoke-RenewIpOp', 'Invoke-NetStackResetOp', 'Invoke-RestartAudioOp', 'Invoke-ClearSpoolerOp', 'Invoke-ResetWuComponentsOp', 'Invoke-RebuildIconCacheOp') {
    Reset-All
    & $fn
    Assert-Eq $script:Plans.Count 1 "önizleme tek plan satırı: $fn"
    Assert-Eq $script:Dones.Count 0 "önizleme bitti demez: $fn"
    Assert-Eq $script:Calls.Count 0 "önizleme dış komut çalıştırmaz: $fn"
}
Reset-All
$op = FuncOp 'RenewIp'
Invoke-FuncOp $op
Assert-Eq $script:Plans.Count 1 'Invoke-FuncOp: tabloya kayıtlı işlem çağrılır'
$bad = $null
try { Invoke-FuncOp (FuncOp 'OlmayanIslem') } catch { $bad = $_.Exception.Message }
Assert-True ($null -ne $bad) 'Invoke-FuncOp: bilinmeyen işlem hata verir'
$script:Preview = $false

# =====================================================================
#  4) işlemler: sahte hizmet ve komutlarla gerçek akış
# =====================================================================
Reset-All
Invoke-RenewIpOp
Assert-Eq ($script:Calls -join '|') 'ipconfig /release|ipconfig /renew' 'IP: bırak ve yenile'
Assert-Eq $script:Dones.Count 1 'IP: tamamlandı'

Reset-All
Invoke-NetStackResetOp
Assert-Eq ($script:Calls -join '|') 'netsh winsock reset|netsh int ip reset' 'ağ yığını: iki sıfırlama'
Assert-Eq $script:Dones.Count 1 'ağ yığını: tamamlandı'
Assert-Eq $script:Skips.Count 0 'ağ yığını: uyarı yok'
Reset-All
$script:NetshFail = 'winsock reset'
$err = ''
try { Invoke-NetStackResetOp } catch { $err = $_.Exception.Message }
Assert-True ($err -match 'Winsock') 'ağ yığını: Winsock hatası bildirilir'
Assert-Eq $script:Dones.Count 0 'ağ yığını: hatada tamamlandı denmez'
Assert-True ($script:Calls -notcontains 'netsh int ip reset') 'ağ yığını: Winsock başarısızsa devam etmez'
Reset-All
$script:NetshFail = 'int ip reset'
Invoke-NetStackResetOp
Assert-Eq $script:Skips.Count 1 'ağ yığını: TCP/IP kısmen tamamlanınca uyarı'
Assert-Eq $script:Dones.Count 1 'ağ yığını: yine de tamamlandı'
$script:NetshFail = ''

# hizmet durdurma
Reset-All
$script:SvcStatus = @{ Spooler = 'Running' }
Assert-True (Stop-SlvService 'Spooler') 'hizmet durduruldu'
Assert-True ($script:Calls -contains 'stop Spooler') 'Stop-Service çağrıldı'
Reset-All
$script:SvcStatus = @{ Spooler = 'Stopped' }
Assert-True (Stop-SlvService 'Spooler') 'zaten duran hizmet: doğru'
Assert-True ($script:Calls -notcontains 'stop Spooler') 'duran hizmete durdurma gönderilmez'
Assert-True (-not (Stop-SlvService 'Olmayan')) 'olmayan hizmet: yanlış'
Reset-All
$script:SvcStatus = @{ wuauserv = 'Running' }
$script:StopStuck = @{ wuauserv = $true }
Assert-True (-not (Stop-SlvService 'wuauserv')) 'durmayan hizmet: zaman aşımı sonrası yanlış'
$script:StopStuck = @{}

# ses
Reset-All
$script:SvcStatus = @{ AudioEndpointBuilder = 'Running'; Audiosrv = 'Running' }
Invoke-RestartAudioOp
Assert-Eq ($script:Calls -join '|') 'restart AudioEndpointBuilder|restart Audiosrv' 'ses: önce uç nokta oluşturucu'
Assert-Eq $script:Dones.Count 1 'ses: tamamlandı'
Reset-All
$script:SvcStatus = @{ AudioEndpointBuilder = 'Running' }
Invoke-RestartAudioOp
Assert-Eq $script:Skips.Count 1 'ses: olmayan hizmet atlanır'
Assert-Eq $script:Dones.Count 1 'ses: kalanıyla tamamlanır'

# yazdırma kuyruğu
$sys32 = Join-Path $win 'System32'
New-Item -ItemType Directory -Path $sys32 | Out-Null
$spool = Join-Path (Join-Path $sys32 'spool') 'PRINTERS'
New-Item -ItemType Directory -Path $spool | Out-Null
foreach ($n in '00001.SPL', '00001.SHD', '00002.SPL') { Set-Content -LiteralPath (Join-Path $spool $n) -Value 'x' }
New-Item -ItemType Directory -Path (Join-Path $spool 'alt') | Out-Null
Set-Content -LiteralPath (Join-Path (Join-Path $spool 'alt') 'dokunma.txt') -Value 'x'
Reset-All
$script:SvcStatus = @{ Spooler = 'Running' }
Invoke-ClearSpoolerOp
Assert-Eq @(Get-ChildItem -LiteralPath $spool -File).Count 0 'kuyruk dosyaları silindi'
Assert-True (Test-Path -LiteralPath (Join-Path (Join-Path $spool 'alt') 'dokunma.txt')) 'alt klasöre dokunulmadı'
Assert-True ($script:Dones[0] -match '3 bekleyen') 'üç iş silindi'
Assert-True ($script:Calls -contains 'start Spooler') 'Biriktirici yeniden başlatıldı'
Reset-All
$script:SvcStatus = @{ Spooler = 'Running' }
$script:StopStuck = @{ Spooler = $true }
Invoke-ClearSpoolerOp
Assert-Eq $script:Skips.Count 1 'Biriktirici durmadıysa uyarı'
$script:StopStuck = @{}
Remove-Item -LiteralPath $spool -Recurse -Force
Reset-All
$script:SvcStatus = @{ Spooler = 'Running' }
Invoke-ClearSpoolerOp
Assert-Eq $script:Dones.Count 1 'kuyruk klasörü yoksa da hata vermez'

# Windows Update bileşenleri
$sd = Join-Path $win 'SoftwareDistribution'
$cr = Join-Path $sys32 'catroot2'
New-Item -ItemType Directory -Path $sd | Out-Null
New-Item -ItemType Directory -Path $cr | Out-Null
Set-Content -LiteralPath (Join-Path $sd 'ornek.dat') -Value 'x'
Reset-All
$script:SvcStatus = @{ wuauserv = 'Running'; bits = 'Running'; cryptsvc = 'Running'; msiserver = 'Stopped' }
Invoke-ResetWuComponentsOp
Assert-True (-not (Test-Path -LiteralPath $sd)) 'SoftwareDistribution kenara alındı'
Assert-True (-not (Test-Path -LiteralPath $cr)) 'catroot2 kenara alındı'
$bakSd = @(Get-ChildItem -LiteralPath $win | Where-Object { $_.Name -match '^SoftwareDistribution\.bak-\d{8}-\d{6}$' })
$bakCr = @(Get-ChildItem -LiteralPath $sys32 | Where-Object { $_.Name -match '^catroot2\.bak-\d{8}-\d{6}$' })
Assert-Eq $bakSd.Count 1 'SoftwareDistribution yedeği oluştu'
Assert-Eq $bakCr.Count 1 'catroot2 yedeği oluştu'
Assert-True (Test-Path -LiteralPath (Join-Path $bakSd[0].FullName 'ornek.dat')) 'içerik silinmedi, taşındı'
foreach ($sv in 'wuauserv', 'bits', 'cryptsvc', 'msiserver') { Assert-True ($script:Calls -contains ('start ' + $sv)) "hizmet yeniden başlatıldı: $sv" }
Assert-True ($script:Dones[0] -match '2 klasör') 'iki klasör yedeklendi'

# bir klasör taşınamazsa hizmetler yine de başlatılır
foreach ($old in @(Get-ChildItem -LiteralPath $win | Where-Object { $_.Name -like 'SoftwareDistribution.bak-*' })) { Remove-Item -LiteralPath $old.FullName -Recurse -Force }
foreach ($old in @(Get-ChildItem -LiteralPath $sys32 | Where-Object { $_.Name -like 'catroot2.bak-*' })) { Remove-Item -LiteralPath $old.FullName -Recurse -Force }
New-Item -ItemType Directory -Path $sd -Force | Out-Null
New-Item -ItemType Directory -Path $cr -Force | Out-Null
$script:RenameFail = 'catroot2'
function Rename-Item {
    [CmdletBinding()] param([string]$LiteralPath, [string]$NewName)
    if ($script:RenameFail -ne '' -and $LiteralPath -like ('*' + $script:RenameFail)) { throw 'erişim engellendi' }
    Microsoft.PowerShell.Management\Rename-Item -LiteralPath $LiteralPath -NewName $NewName
}
Reset-All
$script:SvcStatus = @{ wuauserv = 'Running'; bits = 'Running'; cryptsvc = 'Running'; msiserver = 'Running' }
$err = ''
try { Invoke-ResetWuComponentsOp } catch { $err = $_.Exception.Message }
Assert-True ($err -match 'erişim') 'taşıma hatası yukarı bildirilir'
foreach ($sv in 'wuauserv', 'bits', 'cryptsvc', 'msiserver') { Assert-True ($script:Calls -contains ('start ' + $sv)) "hata olsa da hizmet başlatıldı: $sv" }
Assert-Eq $script:Dones.Count 0 'hatada tamamlandı denmez'
Remove-Item -LiteralPath 'function:Rename-Item'

# simge önbelleği
$ex = Join-Path (Join-Path (Join-Path $la 'Microsoft') 'Windows') 'Explorer'
New-Item -ItemType Directory -Path $ex -Force | Out-Null
foreach ($n in 'iconcache_32.db', 'iconcache_idx.db', 'iconcache_256.db', 'thumbcache_32.db') { Set-Content -LiteralPath (Join-Path $ex $n) -Value 'x' }
Set-Content -LiteralPath (Join-Path $la 'IconCache.db') -Value 'x'
Assert-Eq @(Get-IconCacheFiles).Count 4 'dört simge önbelleği dosyası bulundu (küçük resim önbelleği sayılmaz)'
$script:ExplorerUp = $true
$script:AutoRestart = $true
$script:Stopped = 0
function Get-Process { [CmdletBinding()] param([string]$Name) if ($script:ExplorerUp) { [pscustomobject]@{ Name = 'explorer' } } }
function Stop-Process { [CmdletBinding()] param([Parameter(ValueFromPipeline = $true)]$InputObject, [switch]$Force) process { $script:Stopped++; $script:ExplorerUp = $script:AutoRestart } }
function Start-Process { [CmdletBinding()] param([string]$FilePath) Add-Call ('process ' + $FilePath); $script:ExplorerUp = $true }
Reset-All
Invoke-RebuildIconCacheOp
Assert-Eq @(Get-IconCacheFiles).Count 0 'simge önbelleği silindi'
Assert-True (Test-Path -LiteralPath (Join-Path $ex 'thumbcache_32.db')) 'küçük resim önbelleğine dokunulmadı'
Assert-Eq $script:Stopped 1 'Gezgin bir kez durduruldu'
Assert-True ($script:Calls -notcontains 'process explorer.exe') 'Gezgin kendiliğinden döndüyse ikinci kez açılmaz'
Assert-True ($script:Dones[0] -match '4 dosya') 'dört dosya silindi'

foreach ($n in 'iconcache_32.db', 'iconcache_idx.db') { Set-Content -LiteralPath (Join-Path $ex $n) -Value 'x' }
$script:AutoRestart = $false
$script:Stopped = 0
Reset-All
Invoke-RebuildIconCacheOp
Assert-True ($script:Calls -contains 'process explorer.exe') 'Gezgin dönmediyse elle açılır'
Assert-Eq @(Get-IconCacheFiles).Count 0 'ikinci denemede de silindi'

# kullanımda kalan dosya
Set-Content -LiteralPath (Join-Path $ex 'iconcache_idx.db') -Value 'x'
$script:RemoveFail = 'iconcache_idx'
function Remove-Item {
    [CmdletBinding()] param([string]$LiteralPath, [switch]$Force, [switch]$Recurse)
    if ($script:RemoveFail -ne '' -and $LiteralPath -like ('*' + $script:RemoveFail + '*')) { throw 'dosya kullanımda' }
    Microsoft.PowerShell.Management\Remove-Item -LiteralPath $LiteralPath -Force:$Force -Recurse:$Recurse
}
$script:AutoRestart = $true
$script:ExplorerUp = $true
$script:Stopped = 0
Reset-All
Invoke-RebuildIconCacheOp
Assert-Eq $script:Stopped 3 'kilitli dosya: üç deneme yapıldı'
Assert-Eq $script:Skips.Count 1 'kilitli dosya: uyarı yazıldı'
Assert-True ($script:Skips[0] -match '1 önbellek') 'kilitli dosya sayısı'
Assert-Eq $script:Dones.Count 1 'kilitli dosya: yine de tamamlandı'
Microsoft.PowerShell.Management\Remove-Item -LiteralPath 'function:Remove-Item'
$script:RemoveFail = ''
foreach ($fnm in 'Get-Process', 'Stop-Process', 'Start-Process') { Remove-Item -LiteralPath ('function:' + $fnm) }

# =====================================================================
#  5) disk: durum, plan ve satırlar
# =====================================================================
function New-Bl([int]$Conv, [int]$Prot, [bool]$Rec = $true, [int]$Pct = 100) { return @{ Drive = 'C:'; Protection = $Prot; Conversion = $Conv; Percent = $Pct; Types = @(1, 3); RecoveryIds = @('{id}'); HasRecovery = $Rec } }
function New-Vol([string]$Drive, [string]$Fs = 'NTFS', [string]$Type = 'Fixed', $Bl = $null, [bool]$Dirty = $false, [string]$Health = 'Healthy', [double]$Size = 500e9, [double]$Free = 200e9) {
    return @{ Drive = $Drive; Letter = $Drive.Substring(0, 1); Label = ''; FileSystem = $Fs; DriveType = $Type; Size = $Size; Free = $Free; DiskNumber = 0; Media = 'SSD'; Bus = 'NVMe'; DiskName = 'Test Disk'; DiskHealth = $Health; Dirty = $Dirty; Bl = $Bl }
}
function New-Sys([hashtable]$Over = @{}) {
    $s = @{ IsAdmin = $true; Edition = 'Pro'; Win11 = $true; TpmPresent = $true; TpmReady = $true; SecureBoot = $true; OsDrive = 'C:'; CanEnable = $true; OnBattery = $false; HasBattery = $false }
    foreach ($k in $Over.Keys) { $s[$k] = $Over[$k] }
    return $s
}

Assert-Eq (Get-BlMethodName 7) 'XTS-AES 256' 'yöntem adı XTS-AES 256'
Assert-Eq (Get-BlMethodName 6) 'XTS-AES 128' 'yöntem adı XTS-AES 128'
Assert-Eq (Get-BlMethodName 0) '' 'yöntem yok'

Assert-Eq (Get-BlState (New-Vol 'C:')) 'unknown' 'okunamayan durum'
Assert-Eq (Get-BlState (New-Vol 'C:' -Bl (New-Bl 0 0))) 'none' 'şifresiz'
Assert-Eq (Get-BlState (New-Vol 'C:' -Bl (New-Bl 1 1))) 'encrypted' 'şifreli ve korumalı'
Assert-Eq (Get-BlState (New-Vol 'C:' -Bl (New-Bl 1 0))) 'suspended' 'şifreli, koruma askıda'
Assert-Eq (Get-BlState (New-Vol 'C:' -Bl (New-Bl 2 0))) 'working' 'şifreleniyor'
Assert-Eq (Get-BlState (New-Vol 'C:' -Bl (New-Bl 3 1))) 'working' 'çözülüyor'
Assert-Eq (Get-BlState (New-Vol 'C:' -Bl (New-Bl 4 1))) 'working' 'duraklatıldı'
Assert-Eq (Get-BlState (New-Vol 'D:' -Bl (New-Bl -1 2))) 'locked' 'kilitli sürücü'
Assert-Eq (Get-BlState (New-Vol 'D:' -Bl (New-Bl -1 1))) 'unknown' 'tutarsız durum bilinmiyor sayılır'

# ---- etkinleştirme planı
$osUn = New-Vol 'C:' -Bl (New-Bl 0 0)
$p = Test-BlEnablePlan $osUn (New-Sys)
Assert-True $p.Ok 'sistem diski: TPM hazır, Pro -> uygun'
Assert-Eq $p.Method 'Tpm' 'sistem diski yöntemi TPM'
Assert-True $p.NeedsReboot 'sistem diski yeniden başlatma ister'
Assert-True $p.IsOs 'sistem diski işaretli'
Assert-Eq @($p.Steps).Count 3 'üç adım'
Assert-Eq @($p.Warnings).Count 0 'uyarı yok'
$p = Test-BlEnablePlan $osUn (New-Sys @{ SecureBoot = $false })
Assert-True ($p.Ok -and @($p.Warnings).Count -eq 1) 'Güvenli Önyükleme kapalıysa uyarı, engel değil'
$p = Test-BlEnablePlan $osUn (New-Sys @{ IsAdmin = $false })
Assert-True (-not $p.Ok -and $p.Why -match 'yönetici') 'yönetici değilse plan yok'
$p = Test-BlEnablePlan $osUn (New-Sys @{ TpmPresent = $false; TpmReady = $false })
Assert-True (-not $p.Ok -and $p.Why -match 'TPM') 'TPM yoksa plan yok'
$p = Test-BlEnablePlan $osUn (New-Sys @{ TpmReady = $false })
Assert-True (-not $p.Ok -and $p.Why -match 'hazır değil') 'TPM hazır değilse plan yok'
$p = Test-BlEnablePlan $osUn (New-Sys @{ Edition = 'Home'; CanEnable = $false })
Assert-True ($p.Ok -and $p.Method -eq 'DeviceEncryption') 'Home + TPM: cihaz şifrelemesi'
$p = Test-BlEnablePlan $osUn (New-Sys @{ Edition = 'Home'; CanEnable = $false; TpmPresent = $false })
Assert-True (-not $p.Ok -and $p.Why -match 'Home') 'Home + TPM yok: plan yok'
$dataHome = Test-BlEnablePlan (New-Vol 'D:' -Bl (New-Bl 0 0)) (New-Sys @{ Edition = 'Home'; CanEnable = $false })
Assert-True (-not $dataHome.Ok) 'Home sürümünde veri sürücüsü şifrelenemez'
$p = Test-BlEnablePlan (New-Vol 'C:' -Bl (New-Bl 1 1)) (New-Sys)
Assert-True (-not $p.Ok -and $p.Why -match 'zaten') 'zaten şifreli: plan yok'
$p = Test-BlEnablePlan (New-Vol 'C:') (New-Sys)
Assert-True (-not $p.Ok -and $p.Why -match 'okunamad') 'durum okunamadıysa plan yok'
$p = Test-BlEnablePlan (New-Vol 'D:' 'ReFS' -Bl (New-Bl 0 0)) (New-Sys)
Assert-True (-not $p.Ok -and $p.Why -match 'dosya sistemi') 'ReFS şifrelenmez'
$p = Test-BlEnablePlan (New-Vol 'D:' -Bl (New-Bl 0 0)) (New-Sys)
Assert-True ($p.Ok -and $p.Method -eq 'RecoveryPassword' -and -not $p.NeedsReboot -and -not $p.IsOs) 'veri sürücüsü: kurtarma parolası, yeniden başlatma yok'
$p = Test-BlEnablePlan (New-Vol 'E:' 'exFAT' 'Removable' -Bl (New-Bl 0 0)) (New-Sys)
Assert-True ($p.Ok -and @($p.Warnings).Count -eq 1 -and $p.Warnings[0] -match 'Çıkarılabilir') 'çıkarılabilir sürücü uyarısı'
$p = Test-BlEnablePlan (New-Vol 'D:' -Bl (New-Bl 0 0) -Free 10e9) (New-Sys @{ HasBattery = $true; OnBattery = $true })
Assert-Eq @($p.Warnings).Count 2 'pil ve düşük boş alan uyarıları'

# ---- anahtar klasörü
Assert-Eq (Test-BlKeyDir 'D:\Anahtarlar' 'C:') '' 'başka sürücü uygun'
Assert-Eq (Test-BlKeyDir 'e:\' 'C:') '' 'kök klasör uygun'
Assert-True ((Test-BlKeyDir 'C:\Users\x' 'C:') -match 'şifrelenecek sürücü') 'aynı sürücü reddedilir'
Assert-True ((Test-BlKeyDir 'c:\x' 'C') -match 'şifrelenecek sürücü') 'harf biçimi önemsiz'
Assert-True ((Test-BlKeyDir '' 'C:') -ne '') 'boş klasör reddedilir'
Assert-True ((Test-BlKeyDir 'D:\a*b' 'C:') -match 'geçersiz') 'joker karakter reddedilir'
Assert-True ((Test-BlKeyDir 'Anahtarlar' 'C:') -ne '') 'göreli yol reddedilir'
Assert-True ((Test-BlKeyDir '\\sunucu\paylasim' 'C:') -ne '') 'ağ yolu reddedilir'
$env:COMPUTERNAME = 'OFIS-PC'
Assert-Eq (Get-BlKeyFileName 'c:') 'BitLocker-kurtarma-C-OFIS-PC.txt' 'anahtar dosya adı'
$env:COMPUTERNAME = 'PC ad/ı'
Assert-Eq (Get-BlKeyFileName 'D:') 'BitLocker-kurtarma-D-PCad.txt' 'dosya adında geçersiz karakterler atılır'

Assert-Eq (Format-SlvMedia @{ Media = 'SSD'; Bus = 'NVMe' }) 'SSD (NVMe)' 'NVMe SSD'
Assert-Eq (Format-SlvMedia @{ Media = 'HDD'; Bus = 'SATA' }) 'HDD' 'HDD'
Assert-Eq (Format-SlvMedia @{ Media = 'Unspecified'; Bus = 'USB' }) 'USB' 'USB bellek'
Assert-Eq (Format-SlvMedia @{ Media = ''; Bus = '' }) '' 'bilinmeyen'

# ---- satırlar
function Get-Do($Rows) { return @($Rows | Where-Object { $_.Kind -eq 'row' } | ForEach-Object { $_.Do }) }
$sysEnv = New-Sys
$r = Get-SlvDiskRows (New-Vol 'C:' -Bl (New-Bl 1 1)) $sysEnv
Assert-Eq $r[0].Kind 'head' 'ilk satır başlık'
Assert-True ($r[0].Title -match 'C:' -and $r[0].Title -match 'NTFS' -and $r[0].Title -match 'SSD') 'başlıkta sürücü, dosya sistemi ve tür'
Assert-Eq ((Get-Do $r) -join ',') 'BlKey,BlSuspend,DiskScan,DiskOptimize' 'şifreli sistem diski: kilitleme yok'
$r = Get-SlvDiskRows (New-Vol 'D:' -Bl (New-Bl 1 1)) $sysEnv
Assert-Eq ((Get-Do $r) -join ',') 'BlKey,BlSuspend,BlLock,DiskScan,DiskOptimize' 'şifreli veri diski: kilitlenebilir'
$r = Get-SlvDiskRows (New-Vol 'C:' -Bl (New-Bl 1 1 $false)) $sysEnv
Assert-True ((Get-Do $r) -contains 'BlAddKey') 'anahtarsız şifreli disk: anahtar ekle'
Assert-True ((Get-Do $r) -notcontains 'BlKey') 'anahtarsız disk: anahtarı göster yok'
$r = Get-SlvDiskRows (New-Vol 'C:' -Bl (New-Bl 1 0)) $sysEnv
Assert-True ((Get-Do $r) -contains 'BlResume') 'askıda: korumayı sürdür'
$r = Get-SlvDiskRows (New-Vol 'C:' -Bl (New-Bl 2 0 $true 37)) $sysEnv
Assert-True (@($r | Where-Object { $_.Title -match '%37' }).Count -eq 1) 'şifreleme yüzdesi gösterilir'
Assert-True ((Get-Do $r) -notcontains 'BlEnable') 'şifrelenirken başlat düğmesi yok'
$r = Get-SlvDiskRows $osUn $sysEnv
Assert-True ((Get-Do $r) -contains 'BlEnable') 'şifresiz ve uygun: başlat düğmesi'
$en = @($r | Where-Object { $_.Do -eq 'BlEnable' })[0]
Assert-Eq $en.Br 'BrWarn' 'şifresiz sistem diski uyarı renginde'
$r = Get-SlvDiskRows (New-Vol 'D:' -Bl (New-Bl 0 0)) $sysEnv
Assert-Eq (@($r | Where-Object { $_.Do -eq 'BlEnable' })[0].Br) 'BrFaint' 'şifresiz veri diski sakin renkte'
$r = Get-SlvDiskRows $osUn (New-Sys @{ IsAdmin = $false })
Assert-True ((Get-Do $r) -notcontains 'BlEnable') 'yönetici değilken başlat düğmesi yok'
Assert-True (@($r | Where-Object { $_.Detail -match 'yönetici' }).Count -ge 1) 'nedeni yazılır'
$r = Get-SlvDiskRows (New-Vol 'C:' -Bl (New-Bl 0 0)) (New-Sys @{ Edition = 'Home'; CanEnable = $false })
$en = @($r | Where-Object { $_.Do -eq 'BlEnable' })[0]
Assert-Eq $en.Label 'Cihaz şifrelemesini aç' 'Home: cihaz şifrelemesi düğmesi'
$r = Get-SlvDiskRows (New-Vol 'D:' -Bl (New-Bl -1 2)) $sysEnv
Assert-True (@($r | Where-Object { $_.Title -match 'kilitli' }).Count -eq 1) 'kilitli sürücü bildirilir'
Assert-True (@($r | Where-Object { $_.Kind -eq 'row' -and $_.Do -ne '' }).Count -eq 0) 'kilitli sürücüde hiçbir işlem düğmesi yok'
$r = Get-SlvDiskRows (New-Vol 'D:' 'NTFS' 'Fixed' (New-Bl 0 0) $false 'Warning') $sysEnv
Assert-True ((Get-Do $r) -contains 'Backup') 'disk sağlığı bozuksa yedekleme önerilir'
$r = Get-SlvDiskRows (New-Vol 'D:' 'NTFS' 'Fixed' (New-Bl 0 0) $true) $sysEnv
Assert-True ((Get-Do $r) -contains 'DiskRepair' -and (Get-Do $r) -notcontains 'DiskScan') 'kirli bit: onar, tara yok'
$r = Get-SlvDiskRows (New-Vol 'D:' 'exFAT' 'Fixed' (New-Bl 0 0)) $sysEnv
Assert-True ((Get-Do $r) -notcontains 'DiskScan') 'NTFS olmayan sürücüde tarama yok'
Assert-True ((Get-Do $r) -contains 'DiskOptimize') 'iyileştirme her sürücüde'
foreach ($row in $r) { Assert-True (([string]$row.Title + [string]$row.Detail) -notmatch '(?i)yapay zek|chatgpt') 'satırlarda açıklama kalıntısı yok' }

# ---- şifreleme kapsamı, otomatik açma ve kaldırma düğmeleri
$pOs = Test-BlEnablePlan $osUn (New-Sys)
Assert-True ($pOs.Scope -eq 'Used' -and $pOs.Cipher -eq 'XtsAes256') 'SSD sistem diski: kullanılan alan, XTS-AES 256'
Assert-True ((@($pOs.Steps) -join ' ') -match 'yalnızca kullanılan alan') 'adım metni kapsamı söyler (SSD)'
$hdd = New-Vol 'D:' -Bl (New-Bl 0 0)
$hdd.Media = 'HDD'
$pH = Test-BlEnablePlan $hdd (New-Sys)
Assert-True ($pH.Scope -eq 'Full' -and (@($pH.Steps) -join ' ') -match 'tüm sürücü') 'mekanik disk: tüm sürücü'
$rem = Test-BlEnablePlan (New-Vol 'E:' 'exFAT' 'Removable' -Bl (New-Bl 0 0)) (New-Sys)
Assert-True ($rem.Cipher -eq 'Aes256' -and (@($rem.Steps) -join ' ') -match 'AES-256') 'çıkarılabilir sürücü: AES-256'
Assert-Eq (Get-BlScope @{ Media = 'HDD' }) 'Full' 'kapsam: HDD'
Assert-Eq (Get-BlScope @{ Media = 'SSD' }) 'Used' 'kapsam: SSD'
Assert-Eq (Get-BlScope @{}) 'Used' 'kapsam: bilinmeyen'

$r = Get-SlvDiskRows (New-Vol 'D:' -Bl (New-Bl 1 1)) $sysEnv
$susp = @($r | Where-Object { $_.Do -eq 'BlSuspend' })[0]
Assert-Eq $susp.Do2 'BlDisable' 'askıya alma satırında şifrelemeyi kaldırma düğmesi var'
Assert-True ($susp.Label2 -match 'kaldır') 'kaldırma düğmesinin etiketi'
$osEnc = New-Sys @{ OsBlState = 'encrypted' }
$r = Get-SlvDiskRows (New-Vol 'D:' -Bl (New-Bl 1 1)) $osEnc
Assert-Eq ((Get-Do $r) -join ',') 'BlKey,BlSuspend,BlAutoUnlock,BlLock,DiskScan,DiskOptimize' 'sistem şifreli, veri sürücüsü otomatik açılmıyor: düğme çıkar'
$au = @($r | Where-Object { $_.Do -eq 'BlAutoUnlock' })[0]
Assert-True ($au.Title -match 'Otomatik açma kapalı' -and $au.Br -eq 'BrWarn') 'otomatik açma satırı uyarı renginde'
$r = Get-SlvDiskRows (New-Vol 'D:' -Bl (New-Bl 1 1)) (New-Sys @{ OsBlState = 'working' })
Assert-True ((Get-Do $r) -contains 'BlAutoUnlock') 'sistem şifrelenirken de düğme çıkar'
$withExt = New-Bl 1 1
$withExt.Types = @(1, 2, 3)
$r = Get-SlvDiskRows (New-Vol 'D:' -Bl $withExt) $osEnc
Assert-True ((Get-Do $r) -notcontains 'BlAutoUnlock') 'otomatik açma zaten açıksa düğme yok'
$r = Get-SlvDiskRows (New-Vol 'D:' -Bl (New-Bl 1 1)) (New-Sys @{ OsBlState = 'none' })
Assert-True ((Get-Do $r) -notcontains 'BlAutoUnlock') 'sistem şifresizken düğme yok'
$r = Get-SlvDiskRows (New-Vol 'E:' 'exFAT' 'Removable' -Bl (New-Bl 1 1)) $osEnc
Assert-True ((Get-Do $r) -notcontains 'BlAutoUnlock') 'çıkarılabilir sürücüde düğme yok'
$r = Get-SlvDiskRows (New-Vol 'C:' -Bl (New-Bl 1 1)) $osEnc
Assert-True ((Get-Do $r) -notcontains 'BlAutoUnlock') 'sistem sürücüsünde düğme yok'

# =====================================================================
#  6) disk: bulgular
# =====================================================================
Reset-All
Add-DiskProtectFindings @((New-Vol 'C:' -Bl (New-Bl 1 1))) $sysEnv
Assert-Eq (Find-F 'bl').Status 'ok' 'şifreli sistem diski: tamam'
Assert-True ($null -eq (Find-F 'bl-key')) 'anahtar varsa uyarı yok'
Reset-All
Add-DiskProtectFindings @((New-Vol 'C:' -Bl (New-Bl 1 1 $false))) $sysEnv
Assert-Eq (Find-F 'bl-key').Status 'warn' 'anahtarsız şifreli disk: uyarı'
Assert-Eq (Find-F 'bl-key').Action.Sub 'disk' 'eylem Diskler sekmesine gider'
Reset-All
Add-DiskProtectFindings @((New-Vol 'C:' -Bl (New-Bl 1 0))) $sysEnv
$f = Find-F 'bl'
Assert-Eq $f.Status 'warn' 'askıda: uyarı'
Assert-Eq $f.Fix.Kind 'Run' 'askıda: tek tıkla düzeltme'
Assert-Eq $f.Fix.Key 'BlResume' 'düzeltme BlResume'
Assert-Eq $f.Fix.Mode 'Click' 'düzeltme onay ister'
Reset-All
Add-DiskProtectFindings @((New-Vol 'C:' -Bl (New-Bl 2 0 $true 12))) $sysEnv
Assert-Eq (Find-F 'bl').Status 'info' 'şifreleniyor: bilgi'
Assert-True ((Find-F 'bl').Detail -match '%12') 'yüzde yazılır'
Reset-All
Add-DiskProtectFindings @($osUn) $sysEnv
$f = Find-F 'bl'
Assert-Eq $f.Status 'info' 'masaüstünde şifresiz sistem diski: bilgi'
Assert-Eq $f.Action.Sub 'disk' 'eylem Diskler sekmesi'
Reset-All
Add-DiskProtectFindings @($osUn) (New-Sys @{ HasBattery = $true })
Assert-Eq (Find-F 'bl').Status 'warn' 'dizüstünde şifresiz sistem diski: uyarı'
Reset-All
Add-DiskProtectFindings @($osUn) (New-Sys @{ TpmPresent = $false; TpmReady = $false })
Assert-True ((Find-F 'bl').Detail -match 'TPM') 'neden bulguda yazılır'
Reset-All
Add-DiskProtectFindings @() (New-Sys @{ Edition = 'Home' })
Assert-True ((Find-F 'bl').Title -match 'Home') 'Home: bilgi'
Reset-All
Add-DiskProtectFindings @() $sysEnv
Assert-True ((Find-F 'bl').Title -match 'okunamad') 'okunamadı'
Reset-All
Add-DiskProtectFindings @((New-Vol 'C:' -Bl (New-Bl 1 1)), (New-Vol 'D:' -Bl (New-Bl 0 0)), (New-Vol 'E:' 'exFAT' 'Removable' -Bl (New-Bl 0 0)), (New-Vol 'F:' -Bl (New-Bl 1 1))) $sysEnv
Assert-True ((Find-F 'bl-data').Title -match 'D:') 'şifresiz veri sürücüsü bildirilir'
Assert-True ((Find-F 'bl-data').Title -notmatch 'E:|F:|C:') 'çıkarılabilir, şifreli ve sistem sürücüsü sayılmaz'

Reset-All
Add-VolumeHealthFindings @((New-Vol 'D:' -Dirty $true), (New-Vol 'E:'))
Assert-Eq $script:Findings.Count 1 'yalnızca kirli sürücü için bulgu'
$f = Find-F 'fs-dirty-D'
Assert-Eq $f.Status 'warn' 'kirli bit: uyarı'
Assert-Eq $f.Fix.Kind 'Steps' 'onarım adımlı düzeltme'
Assert-Eq $f.Fix.Mode 'Click' 'onay ister'
Assert-Eq $f.Fix.Steps[0].Ops[0].T 'ChkdskRepair' 'işlem ChkdskRepair'
Assert-Eq $f.Fix.Steps[0].Ops[0].Drive 'D:' 'işlem sürücüsü'
Assert-Eq $f.Fix.Steps[0].Reboot $false 'veri sürücüsü yeniden başlatma istemez'
Reset-All
$env:SystemDrive = 'C:'
Add-VolumeHealthFindings @((New-Vol 'C:' -Dirty $true))
Assert-Eq (Find-F 'fs-dirty-C').Fix.Steps[0].Reboot $true 'sistem sürücüsü yeniden başlatmada onarılır'
Assert-True ((Find-F 'fs-dirty-C').Detail -match 'yeniden başlatma') 'bulgu bunu söyler'

# ---- onarım işlemi
Reset-All
$script:Preview = $true
Invoke-ChkdskRepairOp @{ T = 'ChkdskRepair'; Drive = 'd:' }
Assert-Eq $script:Plans.Count 1 'onarım önizlemesi'
$script:Preview = $false
$script:RepairCalls = New-Object System.Collections.ArrayList
function Repair-Volume { [CmdletBinding()] param([string]$DriveLetter, [switch]$Scan, [switch]$SpotFix, [switch]$OfflineScanAndFix) [void]$script:RepairCalls.Add($DriveLetter + ':' + [string]$Scan + ':' + [string]$SpotFix); 'NoErrorsFound' }
Invoke-ChkdskRepairOp @{ T = 'ChkdskRepair'; Drive = 'd:' }
Assert-Eq ($script:RepairCalls -join '|') 'D:False:True' 'SpotFix ile onarım'
Assert-Eq $script:Dones.Count 1 'onarım tamamlandı'
$err = ''
try { Invoke-ChkdskRepairOp @{ T = 'ChkdskRepair'; Drive = 'C:\Windows' } } catch { $err = $_.Exception.Message }
Assert-True ($err -match 'Geçersiz') 'geçersiz sürücü reddedilir'
$err = ''
try { Invoke-ChkdskRepairOp @{ T = 'ChkdskRepair'; Drive = 'D: /f' } } catch { $err = $_.Exception.Message }
Assert-True ($err -match 'Geçersiz') 'komut sızdırma reddedilir'
Assert-Eq $script:RepairCalls.Count 1 'geçersiz istek komut çalıştırmaz'

# ---- çevrimiçi tarama ve iyileştirme
Reset-All
$script:OptCalls = New-Object System.Collections.ArrayList
function Optimize-Volume { [CmdletBinding()] param([string]$DriveLetter) [void]$script:OptCalls.Add($DriveLetter) }
Invoke-SlvDriveAction 'scan' @{ Drive = 'd:' }
Assert-Eq ($script:RepairCalls[1]) 'D:True:False' 'salt okunur tarama'
Invoke-SlvDriveAction 'optimize' @{ Drive = 'D:' }
Assert-Eq ($script:OptCalls -join ',') 'D' 'iyileştirme'
$err = ''
try { Invoke-SlvDriveAction 'scan' @{ Drive = 'DD' } } catch { $err = $_.Exception.Message }
Assert-True ($err -match 'geçersiz') 'sürücü harfi doğrulanır'

# ---- korumayı sürdür
$script:ResumeCalls = New-Object System.Collections.ArrayList
function Resume-BitLocker { [CmdletBinding()] param([string]$MountPoint) [void]$script:ResumeCalls.Add($MountPoint) }
Invoke-BlResumeAction @{ Drive = 'd' }
Invoke-BlResumeAction @{}
Assert-Eq ($script:ResumeCalls -join ',') 'd:,C:' 'sürücü verilmezse sistem sürücüsü'
$err = ''
try { Invoke-BlResumeAction @{ Drive = 'C:\x' } } catch { $err = $_.Exception.Message }
Assert-True ($err -match 'geçersiz') 'sürücü doğrulanır'

# =====================================================================
#  7) disk hataları
# =====================================================================
function New-Ev([int]$Id, [int]$DaysAgo = 1, [string]$Src = 'disk') { return @{ Time = (Get-Date).AddDays(-$DaysAgo); Id = $Id; Source = $Src } }
$s0 = Get-DiskErrorSummary @()
Assert-Eq $s0.Total 0 'olay yok'
$s1 = Get-DiskErrorSummary @((New-Ev 7), (New-Ev 7 2), (New-Ev 153 3), (New-Ev 52 5))
Assert-Eq $s1.Total 4 'toplam'
Assert-Eq (Get-DiskErrCount $s1 7) 2 'kod 7 iki kez'
Assert-Eq (Get-DiskErrCount $s1 11) 0 'kod 11 yok'
Assert-True ($s1.Last -gt (Get-Date).AddDays(-2)) 'son kayıt en yenisi'

Reset-All
Add-DiskErrorFindings $s0 30
Assert-Eq (Find-F 'disk-io').Status 'ok' 'hata yoksa tamam'
Reset-All
Add-DiskErrorFindings (Get-DiskErrorSummary @((New-Ev 52))) 30
Assert-Eq (Find-F 'disk-pred').Status 'bad' 'arıza öngörüsü: kötü'
Assert-Eq (Find-F 'disk-pred').Action.Sub 'recover' 'önce yedekle ve kurtar'
Assert-True ($null -eq (Find-F 'disk-io')) 'öngörü varken “hata yok” denmez'
Reset-All
Add-DiskErrorFindings (Get-DiskErrorSummary @((New-Ev 7), (New-Ev 55 2 'Ntfs'))) 30
Assert-Eq (Find-F 'disk-io').Status 'warn' 'bozuk blok ve dosya sistemi hatası: uyarı'
Assert-True ((Find-F 'disk-io').Title -match '2 disk') 'sayı başlıkta'
Reset-All
Add-DiskErrorFindings (Get-DiskErrorSummary @((New-Ev 153), (New-Ev 153), (New-Ev 153), (New-Ev 51), (New-Ev 140 1 'Ntfs'))) 30
Assert-Eq (Find-F 'disk-io').Status 'info' 'yalnızca yeniden denemeler: bilgi'
Reset-All
Add-DiskErrorFindings (Get-DiskErrorSummary @((New-Ev 153), (New-Ev 153))) 30
Assert-Eq (Find-F 'disk-io').Status 'ok' 'birkaç yeniden deneme önemsiz'

# ---- olay okuma
$script:WinEvents = @()
function Get-WinEvent {
    [CmdletBinding()] param($FilterHashtable, $MaxEvents)
    if ($script:WinEvents.Count -eq 0) { throw 'No events were found that match the specified selection criteria.' }
    foreach ($e in $script:WinEvents) { [pscustomobject]@{ TimeCreated = $e.Time; Id = $e.Id; ProviderName = $e.Source } }
}
$ev0 = Get-DiskErrorEvents 30
Assert-Eq @($ev0).Count 0 'olay bulunamadı: boş dizi'
$script:WinEvents = @((New-Ev 7), (New-Ev 153 2))
$ev = Get-DiskErrorEvents 30
Assert-Eq $ev.Count 2 'iki olay okundu'
Assert-Eq $ev[0].Id 7 'kimlik'

# ---- uçtan uca
function Get-SlvEnv { return (New-Sys) }
function Get-SlvDisks { return , @((New-Vol 'C:' -Bl (New-Bl 1 0)), (New-Vol 'D:' -Dirty $true -Bl (New-Bl 0 0))) }
Reset-All
Chk_DiskProtect
Assert-Eq (Find-F 'bl').Status 'warn' 'Chk_DiskProtect: askıda bulundu'
Assert-True ($null -ne (Find-F 'fs-dirty-D')) 'Chk_DiskProtect: kirli sürücü bulundu'
Assert-True ($null -ne (Find-F 'bl-data')) 'Chk_DiskProtect: şifresiz veri sürücüsü bulundu'
Reset-All
$script:WinEvents = @((New-Ev 52), (New-Ev 7))
Chk_DiskErrors
Assert-True ($null -ne (Find-F 'disk-pred') -and $null -ne (Find-F 'disk-io')) 'Chk_DiskErrors: iki bulgu'

Remove-Item -LiteralPath $tmp -Recurse -Force
Show-Result
