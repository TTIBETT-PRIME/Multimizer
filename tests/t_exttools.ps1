. "$PSScriptRoot/lib.ps1"
# Araçlar > Dış araçlar sekmesi (mods\132_exttools_core.ps1 ve 133_exttools_ui.ps1): katalog bütünlüğü, izin listesi, kurulu araç bulma (geçici klasörlerle),
# denetim ve kurulum işleri (sahte winget ile), satır/onay/bildirim kuralları ve sayfa akışı (sahte arayüzle). Gerçek kurulum yapılmaz, hiçbir araç çalıştırılmaz.
Import-Fn 'Get-JsonProp', 'Get-PrepWingetResult',
    'Get-ExtToolCatalog', 'Get-ExtTool', 'Test-ExtToolId', 'Expand-ExtToolPaths', 'Find-ExtToolExe', 'Get-ExtToolStates', 'Job_ExtToolScan', 'Job_ExtToolInstall',
    'Get-ExtToolGroups', 'Get-ExtToolStateFor', 'Get-ExtToolRowModel', 'Get-ExtToolConfirmText', 'Get-ExtToolInstallModel',
    'Load-TlExt', 'Complete-TlExt', 'Render-TlExt', 'Invoke-TlExtAction', 'Open-ExtTool', 'Start-ExtToolInstall', 'Complete-ExtToolInstall', 'Invoke-TlRefresh', 'Set-TlTab'
Import-Var 'ExtToolGroups', 'ExtToolRows', 'TlTabs', 'H_TlExtAct', 'H_TlExtPage', 'SmokeSafe', 'BoardActions', 'BoardActionAccent', 'BoardSearchWords', 'CmdPages'
$script:ExtToolCache = $null; $script:ExtToolState = $null; $script:ExtToolLoading = $false; $script:ExtToolPending = $null
$script:WhLog = New-Object System.Collections.ArrayList
function Write-WhLog([string]$Message, [string]$Level = 'INFO') { [void]$script:WhLog.Add($Level + '|' + $Message) }
. "$PSScriptRoot/uifake.ps1"
$src = [System.IO.File]::ReadAllText($script:TestPath)
$null = Get-AstFunctions

# =====================================================================
#  1) katalog bütünlüğü
# =====================================================================
$cat = Get-ExtToolCatalog
Assert-Eq $cat.Count 9 'katalog: dokuz araç'
Assert-Eq $script:ExtToolRows.Count 9 'katalog: dokuz satır'
$expectedIds = @('7zip.7zip', 'CGSecurity.TestDisk', 'CrystalDewWorld.CrystalDiskInfo', 'Microsoft.PowerToys', 'Microsoft.Sysinternals.Suite', 'REALiX.HWiNFO', 'voidtools.Everything', 'WinDirStat.WinDirStat', 'WireGuard.WireGuard')
Assert-Eq ((@($cat | ForEach-Object { [string]$_.Id }) | Sort-Object) -join ',') (($expectedIds | Sort-Object) -join ',') 'katalog: doğrulanmış dokuz winget kimliği'
$groupKeys = @($script:ExtToolGroups | ForEach-Object { ([string]$_).Split('|')[0] })
Assert-Eq ($groupKeys -join ',') 'disk,sistem,ag,verim' 'katalog: grup sırası'
foreach ($g in $script:ExtToolGroups) { Assert-Eq (([string]$g).Split('|').Count) 2 ('katalog: grup satırı iki alanlı ' + $g) }
foreach ($row in $script:ExtToolRows) { Assert-Eq (([string]$row).Split('|').Count) 7 ('katalog: satır yedi alanlı ' + ([string]$row).Split('|')[0]) }
$seenId = @{}; $seenName = @{}
foreach ($t in $cat) {
    $id = [string]$t.Id
    Assert-True ($id -cmatch '^[A-Za-z0-9][A-Za-z0-9\.\-_\+]*\z') ('katalog: kimlik biçimi ' + $id)
    Assert-True (-not $seenId.ContainsKey($id.ToLowerInvariant())) ('katalog: kimlik tekil ' + $id)
    Assert-True (-not $seenName.ContainsKey(([string]$t.Name).ToLowerInvariant())) ('katalog: ad tekil ' + $id)
    $seenId[$id.ToLowerInvariant()] = $true; $seenName[([string]$t.Name).ToLowerInvariant()] = $true
    foreach ($f in @('Name', 'Group', 'Publisher', 'Desc', 'Home', 'Exe')) { Assert-True ([string]$t[$f] -ne '' -and [string]$t[$f] -eq ([string]$t[$f]).Trim()) ('katalog: ' + $f + ' dolu ve kırpılmış ' + $id) }
    Assert-True ($groupKeys -contains [string]$t.Group) ('katalog: grup tanımlı ' + $id)
    Assert-True ([string]$t.Home -cmatch '^https://[a-z0-9][a-z0-9\.\-]*\.[a-z]{2,}/\S*\z') ('katalog: sayfa adresi https ' + $id)
    Assert-True (([string]$t.Desc).Length -ge 40 -and ([string]$t.Desc).Length -le 260 -and ([string]$t.Desc).EndsWith('.')) ('katalog: açıklama uzunluğu ve noktası ' + $id)
    Assert-True (([string]$t.Name).Length -le 28) ('katalog: ad kısa ' + $id)
    $pats = @(([string]$t.Exe).Split(';'))
    Assert-True ($pats.Count -ge 1) ('katalog: en az bir çalıştırılabilir dosya yolu ' + $id)
    foreach ($p in $pats) {
        Assert-True ($p -cmatch '^(%[A-Za-z0-9\(\)]+%|\{WG\})\\[^\\/:"<>|]') ('katalog: yol bir ortam değişkeniyle ya da {WG} ile başlar ' + $p)
        Assert-True ($p.EndsWith('.exe') -and -not $p.Contains('..') -and -not $p.Contains('/') -and -not $p.Contains(' \')) ('katalog: yol .exe ile biter, üst klasöre çıkmaz ' + $p)
    }
}
foreach ($g in $groupKeys) { Assert-True (@($cat | Where-Object { [string]$_.Group -eq $g }).Count -ge 1) ('katalog: grupta araç var ' + $g) }
$c1 = Get-ExtToolCatalog; $c2 = Get-ExtToolCatalog
Assert-True ([object]::ReferenceEquals($c1, $c2)) 'katalog: ikinci çağrı önbellekten gelir'
Assert-True ((Get-ExtTool 'wireguard.wireguard').Name -eq 'WireGuard' -and $null -eq (Get-ExtTool 'Yok.Yok') -and $null -eq (Get-ExtTool '')) 'katalog: kimlikle arama (büyük/küçük harf önemsiz)'
# Microsoft araçları Microsoft yayıncısıyla, WireGuard resmî istemcisi olarak sunulur
Assert-True ((Get-ExtTool 'Microsoft.PowerToys').Publisher -match 'Microsoft' -and (Get-ExtTool 'Microsoft.Sysinternals.Suite').Publisher -match 'Microsoft') 'katalog: Microsoft araçlarının yayıncısı'
Assert-True ((Get-ExtTool 'WireGuard.WireGuard').Desc -match 'resmî') 'katalog: WireGuard açıklaması resmî istemciyi söyler'
# açıklamalar abartı ya da güvence içermez
foreach ($t in $cat) { Assert-True (([string]$t.Desc) -notmatch '(?i)garanti|%100|en iyi|mükemmel|sertifika') ('katalog: açıklama abartısız ' + [string]$t.Id) }

# =====================================================================
#  2) izin listesi
# =====================================================================
foreach ($t in $cat) { Assert-Eq (Test-ExtToolId ([string]$t.Id)) '' ('izin listesi: kurulabilir ' + [string]$t.Id) }
Assert-Eq (Test-ExtToolId 'crystaldewworld.crystaldiskinfo') '' 'izin listesi: büyük/küçük harf önemsiz'
Assert-True ((Test-ExtToolId 'Vendor.Tool') -match 'izin listesinde değil') 'izin listesi: listede olmayan kimlik reddedilir'
Assert-True ((Test-ExtToolId 'Microsoft.DirectX') -match 'izin listesinde değil') 'izin listesi: Hazırlık paketleri bu listeye ait değildir'
Assert-True ((Test-ExtToolId '7zip.7zip; calc') -match 'Geçersiz paket kimliği') 'izin listesi: komut eklemeye çalışan kimlik reddedilir'
Assert-True ((Test-ExtToolId '7zip.7zip --source evil') -match 'Geçersiz') 'izin listesi: boşluklu kimlik reddedilir'
Assert-True ((Test-ExtToolId '..\evil') -match 'Geçersiz') 'izin listesi: yol benzeri kimlik reddedilir'
Assert-True ((Test-ExtToolId '') -match 'Geçersiz') 'izin listesi: boş kimlik reddedilir'
Assert-True ((Test-ExtToolId '-v') -match 'Geçersiz') 'izin listesi: tire ile başlayan (seçenek gibi) kimlik reddedilir'
Assert-True ((Test-ExtToolId "7zip.7zip`n") -match 'Geçersiz') 'izin listesi: sonunda satır sonu olan kimlik reddedilir'
Assert-True ((Test-ExtToolId "7zip.7zip`r`ncalc") -match 'Geçersiz') 'izin listesi: satır sonlu komut reddedilir'
Assert-True ((Test-ExtToolId ('7zip.7zip' + [char]0x00A0)) -match 'Geçersiz') 'izin listesi: görünmez boşluklu kimlik reddedilir'

# =====================================================================
#  3) kurulu aracı bulma (geçici klasörlerle; hiçbir şey çalıştırılmaz)
# =====================================================================
$root = Join-Path ([System.IO.Path]::GetTempPath()) ('mm_ext_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$pf = Join-Path $root 'pf'; $pf86 = Join-Path $root 'pf86'; $lad = Join-Path $root 'lad'
[void](New-Item -ItemType Directory -Path $pf, $pf86, $lad -Force)
$env:ProgramFiles = $pf; ${env:ProgramFiles(x86)} = $pf86; $env:LOCALAPPDATA = $lad
function New-TestFile([string]$Path) { [void](New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force); [System.IO.File]::WriteAllText($Path, 'x') }
function St([string]$Id) { foreach ($s in (Get-ExtToolStates)) { if ([string]$s.Id -eq $Id) { return $s } }; return $null }

$e = Expand-ExtToolPaths '%ProgramFiles%\A\b.exe;{WG}\Links\x.exe;%MM_NO_SUCH_VAR%\gone.exe; ;'
Assert-Eq $e.Count 3 'yol açma: değişkenli yol, iki winget kökü; tanımsız değişkenli yol atlanır'
Assert-True ($e[0].StartsWith($pf) -and $e[0].EndsWith('\A\b.exe')) 'yol açma: ProgramFiles genişler'
Assert-True ($e[1].StartsWith($lad) -and $e[1].Contains('Microsoft') -and $e[1].EndsWith('\Links\x.exe')) 'yol açma: kullanıcı winget kökü'
Assert-True ($e[2].StartsWith($pf) -and $e[2].Contains('WinGet') -and $e[2].EndsWith('\Links\x.exe')) 'yol açma: makine winget kökü'
Assert-Eq (Expand-ExtToolPaths '').Count 0 'yol açma: boş kalıp'
Assert-Eq (Expand-ExtToolPaths '%MM_NO_SUCH_VAR%\a.exe').Count 0 'yol açma: yalnızca tanımsız değişken'

$st = Get-ExtToolStates
Assert-Eq $st.Count 9 'durum: her araç için bir kayıt'
Assert-True (@($st | Where-Object { $_.Installed -eq $true }).Count -eq 0 -and @($st | Where-Object { [string]$_.Path -ne '' }).Count -eq 0) 'durum: hiçbir dosya yokken hiçbiri kurulu görünmez'
Assert-Eq ((@($st | ForEach-Object { [string]$_.Id }) | Sort-Object) -join ',') (($expectedIds | Sort-Object) -join ',') 'durum: kayıtlar katalogla aynı kimlikler'

New-TestFile (Join-Path $pf '7-Zip/7zFM.exe')
$s = St '7zip.7zip'
Assert-True ($s.Installed -eq $true -and $s.Path -eq (Join-Path $pf '7-Zip/7zFM.exe')) '7-Zip: ProgramFiles altında bulunur'
Assert-True ((St 'voidtools.Everything').Installed -eq $false) 'Everything: başka araç etkilenmez'
New-TestFile (Join-Path $pf86 'Everything/Everything.exe')
Assert-True ((St 'voidtools.Everything').Installed -eq $true) 'Everything: ProgramFiles(x86) altında bulunur'
New-TestFile (Join-Path $lad 'PowerToys/PowerToys.exe')
Assert-True ((St 'Microsoft.PowerToys').Installed -eq $true) 'PowerToys: kullanıcı başına kurulum bulunur'
New-TestFile (Join-Path $lad 'Microsoft/WinGet/Links/procexp64.exe')
Assert-True ((St 'Microsoft.Sysinternals.Suite').Installed -eq $true) 'Sysinternals: winget Links bağlantısı bulunur'
Assert-True ((St 'CGSecurity.TestDisk').Installed -eq $false) 'TestDisk: kurulmadan bulunmaz'
New-TestFile (Join-Path $lad 'Microsoft/WinGet/Packages/CGSecurity.TestDisk_Microsoft.Winget.Source_8wekyb3d8bbwe/testdisk-7.3-WIP/qphotorec_win.exe')
$s = St 'CGSecurity.TestDisk'
Assert-True ($s.Installed -eq $true -and $s.Path.EndsWith('qphotorec_win.exe')) 'TestDisk: winget paket klasöründe joker karakterle bulunur'

# joker karakterden önceki bölümde [ ] gibi karakterler olsa da bulunur
$lad2 = Join-Path $root 'kullanici[1]'
$env:LOCALAPPDATA = $lad2
New-TestFile (Join-Path $lad2 'Microsoft/WinGet/Packages/CGSecurity.TestDisk_Microsoft.Winget.Source_8wekyb3d8bbwe/photorec_win.exe')
Assert-True ((St 'CGSecurity.TestDisk').Installed -eq $true) 'TestDisk: kullanıcı klasörü adında köşeli parantez olsa da bulunur'
$env:LOCALAPPDATA = $lad

# makine genelindeki winget kökü
New-TestFile (Join-Path $pf 'WinGet/Links/zz_test.exe')
$fake = @{ Exe = '{WG}\Links\zz_test.exe' }
Assert-True ((Find-ExtToolExe $fake) -eq (Join-Path $pf 'WinGet/Links/zz_test.exe')) 'winget kökü: ProgramFiles\WinGet de aranır'
Assert-Eq (Find-ExtToolExe @{ Exe = '{WG}\Links\yok_boyle.exe' }) '' 'winget kökü: dosya yoksa boş'

# klasör, dosya yerine geçmez; yol sırası korunur
[void](New-Item -ItemType Directory -Path (Join-Path $pf 'CrystalDiskInfo/DiskInfo64.exe') -Force)
Assert-True ((St 'CrystalDewWorld.CrystalDiskInfo').Installed -eq $false) 'CrystalDiskInfo: exe adlı klasör kurulu sayılmaz'
New-TestFile (Join-Path $pf 'CrystalDiskInfo/DiskInfo32.exe')
Assert-True ((St 'CrystalDewWorld.CrystalDiskInfo').Path.EndsWith('DiskInfo32.exe')) 'CrystalDiskInfo: yalnızca gerçek dosya sayılır'
Remove-Item -LiteralPath (Join-Path $pf 'CrystalDiskInfo/DiskInfo64.exe') -Force
New-TestFile (Join-Path $pf 'CrystalDiskInfo/DiskInfo64.exe')
Assert-True ((St 'CrystalDewWorld.CrystalDiskInfo').Path.EndsWith('DiskInfo64.exe')) 'CrystalDiskInfo: yol sırası korunur (64 bit önce)'
Assert-True ((St 'WireGuard.WireGuard').Installed -eq $false -and (St 'WinDirStat.WinDirStat').Installed -eq $false -and (St 'REALiX.HWiNFO').Installed -eq $false) 'durum: olmayan araçlar kurulu görünmez'

# denetim işi
$script:WhLog.Clear()
$r = Job_ExtToolScan @{}
Assert-True ($r.Ok -eq $true -and $r.Items.Count -eq 9 -and [string]$r.At -match '^\d{2}\.\d{2}\.\d{4} \d{2}:\d{2}$') 'denetim işi: sonuç, dokuz kayıt ve zaman damgası'
Assert-Eq (@($r.Items | Where-Object { $_.Installed -eq $true }).Count) 6 'denetim işi: kurulu altı araç sayılır'
Assert-True (($script:WhLog | Where-Object { $_ -match 'Kurulu dış araç: 6 / 9' }).Count -eq 1 -and ($script:WhLog | Where-Object { $_ -match '^ERR\|' }).Count -eq 0) 'denetim işi: günlüğe sayı yazılır, hata yok'
$r = Job_ExtToolScan $null
Assert-True ($r.Ok -eq $true) 'denetim işi: parametresiz de çalışır'
function Get-ExtToolStates { throw 'okuma hatası' }
$script:WhLog.Clear()
$r = Job_ExtToolScan @{}
Assert-True ($r.Ok -eq $false -and $r.Error -match 'okuma hatası' -and ($script:WhLog | Where-Object { $_ -match '^ERR\|.*denetlenemedi' }).Count -eq 1) 'denetim işi: okuma hatası başarısızlık olarak döner ve günlüğe yazılır'
Remove-Item function:Get-ExtToolStates
Import-Fn 'Get-ExtToolStates'

# =====================================================================
#  4) denetim yalnızca okur: komut listesi
# =====================================================================
function Get-FnCommands([string]$Name) {
    $f = @($script:AllFns | Where-Object { $_.Name -eq $Name }) | Select-Object -Last 1
    $found = @($f.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true) | ForEach-Object { $_.GetCommandName() } | Where-Object { $null -ne $_ })
    foreach ($n in $found) { $n }
}
$readOnlyFns = @('Get-ExtToolCatalog', 'Get-ExtTool', 'Test-ExtToolId', 'Expand-ExtToolPaths', 'Find-ExtToolExe', 'Get-ExtToolStates', 'Job_ExtToolScan', 'Get-ExtToolGroups', 'Get-ExtToolStateFor', 'Get-ExtToolRowModel', 'Get-ExtToolConfirmText', 'Get-ExtToolInstallModel')
$allowed = @('Get-ExtToolCatalog', 'Get-ExtTool', 'Test-ExtToolId', 'Expand-ExtToolPaths', 'Find-ExtToolExe', 'Get-ExtToolStates', 'Get-ExtToolGroups', 'Get-ExtToolStateFor', 'Get-JsonProp',
    'New-Object', 'Get-ChildItem', 'Test-Path', 'Select-Object', 'Write-WhLog', 'Get-Date', 'ForEach-Object')
foreach ($fn in $readOnlyFns) {
    $bad = @(Get-FnCommands $fn | Where-Object { $allowed -notcontains $_ })
    Assert-True ($bad.Count -eq 0) ('yalnızca okuma: ' + $fn + ' yalnızca izinli komutları çağırır ' + ($bad -join ','))
}
$forbidden = @('Start-Process', 'Invoke-Expression', 'Invoke-WebRequest', 'Invoke-RestMethod', 'Remove-Item', 'Set-Content', 'Add-Content', 'Out-File', 'New-Item', 'Set-ItemProperty', 'Invoke-WingetRaw', 'Start-Job', 'Invoke-Command', 'Add-Type', 'Set-Service', 'Stop-Service')
foreach ($fn in @($readOnlyFns + @('Load-TlExt', 'Complete-TlExt', 'Render-TlExt'))) {
    $hit = @(Get-FnCommands $fn | Where-Object { $forbidden -contains $_ })
    Assert-True ($hit.Count -eq 0) ('yalnızca okuma: ' + $fn + ' yazan ya da çalıştıran komut çağırmaz ' + ($hit -join ','))
}
# kurulum işi yalnızca winget i ve izinli yardımcıları çağırır
$instCmds = @(Get-FnCommands 'Job_ExtToolInstall')
$instAllowed = @('Write-WhLog', 'Test-ExtToolId', 'Get-ExtTool', 'Get-WingetPath', 'Set-JobProgress', 'Invoke-WingetRaw', 'Write-WingetLines', 'Get-PrepWingetResult', 'Find-ExtToolExe')
Assert-True (@($instCmds | Where-Object { $instAllowed -notcontains $_ }).Count -eq 0) ('kurulum işi: yalnızca izinli komutlar ' + (@($instCmds | Where-Object { $instAllowed -notcontains $_ }) -join ','))
Assert-True (@($instCmds | Where-Object { $_ -eq 'Invoke-WingetRaw' }).Count -eq 1) 'kurulum işi: winget tek yerden çağrılır'
Assert-True ((Get-FnCommands 'Open-ExtTool') -contains 'Open-Path' -and -not ((Get-FnCommands 'Open-ExtTool') -contains 'Start-Process')) 'araç açma: Open-Path ile açılır (Duman turunda açılmaz)'

# =====================================================================
#  5) kurulum işi (sahte winget ile)
# =====================================================================
$script:WgCalls = New-Object System.Collections.ArrayList
$script:WgCodes = @{}
$script:WgThrow = @{}
$script:WgPath = 'C:\winget.exe'
$script:WgSim = $null
$script:WgLines = 0
function Get-WingetPath { return $script:WgPath }
function Invoke-WingetRaw([string[]]$WgArgs) {
    [void]$script:WgCalls.Add($WgArgs -join ' ')
    $id = ''
    for ($k = 0; $k -lt $WgArgs.Count; $k++) { if ($WgArgs[$k] -eq '--id') { $id = $WgArgs[$k + 1] } }
    if ($script:WgThrow.ContainsKey($id)) { throw $script:WgThrow[$id] }
    $code = 0
    if ($script:WgCodes.ContainsKey($id)) { $code = $script:WgCodes[$id] }
    if ($code -eq 0 -and $null -ne $script:WgSim) { & $script:WgSim }
    return @{ Lines = @('indiriliyor', 'kuruluyor'); Code = $code }
}
function Write-WingetLines($Lines) { $script:WgLines += @($Lines).Count }
function Set-JobProgress([int]$Done, [int]$Total, [string]$Label = '') { }
function Reset-WgTest { $script:WgCalls.Clear(); $script:WgCodes = @{}; $script:WgThrow = @{}; $script:WgLines = 0; $script:WgSim = $null; $script:WhLog.Clear() }
$wdsExe = Join-Path $pf 'WinDirStat/WinDirStat.exe'

Reset-WgTest
$script:WgSim = { New-TestFile $wdsExe }
$r = Job_ExtToolInstall @{ Id = 'WinDirStat.WinDirStat' }
Assert-True ($r.Ok -eq $true -and $r.Id -eq 'WinDirStat.WinDirStat' -and $r.Name -eq 'WinDirStat' -and $r.Code -eq 0 -and $r.Reboot -eq $false -and $r.Already -eq $false -and $r.Text -eq 'kuruldu') 'kurulum işi: kuruldu'
Assert-Eq $r.Path $wdsExe 'kurulum işi: kurulumdan sonra çalıştırılabilir dosya bulunur'
Assert-Eq $script:WgCalls.Count 1 'kurulum işi: tek winget çağrısı'
Assert-Eq $script:WgCalls[0] 'install --id WinDirStat.WinDirStat --exact --silent --accept-package-agreements --accept-source-agreements --disable-interactivity' 'kurulum işi: winget bağımsız değişkenleri (tam eşleşme, sessiz, etkileşimsiz)'
Assert-True ($script:WgLines -eq 2 -and ($script:WhLog | Where-Object { $_ -match '^STEP\|=== Kuruluyor: WinDirStat \(WinDirStat\.WinDirStat' }).Count -eq 1 -and ($script:WhLog | Where-Object { $_ -match '^OK\|WinDirStat: kuruldu' }).Count -eq 1) 'kurulum işi: günlük ve winget çıktısı'

# küçük harfle verilen kimlik winget e katalogdaki yazımıyla gider
Reset-WgTest
$r = Job_ExtToolInstall @{ Id = 'windirstat.windirstat' }
Assert-True ($r.Ok -eq $true -and $r.Id -ceq 'WinDirStat.WinDirStat' -and $script:WgCalls[0] -cmatch '--id WinDirStat\.WinDirStat ') 'kurulum işi: kimlik katalogdaki yazımla gönderilir'

# zaten kurulu, yeniden başlatma, özet uyuşmazlığı, bulunamadı
Reset-WgTest
$script:WgCodes['7zip.7zip'] = -1978335189
$r = Job_ExtToolInstall @{ Id = '7zip.7zip' }
Assert-True ($r.Ok -eq $true -and $r.Already -eq $true -and $r.Text -eq 'zaten kurulu' -and $r.Path -eq (Join-Path $pf '7-Zip/7zFM.exe')) 'kurulum işi: zaten kurulu başarı sayılır, dosya bulunur'
Reset-WgTest
$script:WgCodes['REALiX.HWiNFO'] = 3010
$r = Job_ExtToolInstall @{ Id = 'REALiX.HWiNFO' }
Assert-True ($r.Ok -eq $true -and $r.Reboot -eq $true -and $r.Text -match 'yeniden başlatma' -and $r.Path -eq '') 'kurulum işi: yeniden başlatma gerekir; dosya yoksa yol boş'
Reset-WgTest
$script:WgCodes['WireGuard.WireGuard'] = -1978335215
$r = Job_ExtToolInstall @{ Id = 'WireGuard.WireGuard' }
Assert-True ($r.Ok -eq $false -and $r.Text -match 'özeti paketle uyuşmadı' -and $r.Text -match 'kurulmadı' -and $r.Path -eq '' -and ($script:WhLog | Where-Object { $_ -match '^ERR\|WireGuard: ' }).Count -eq 1) 'kurulum işi: özet uyuşmazlığı kurulmaz ve günlüğe hata yazılır'
Reset-WgTest
$script:WgCodes['WireGuard.WireGuard'] = -1978335212
$r = Job_ExtToolInstall @{ Id = 'WireGuard.WireGuard' }
Assert-True ($r.Ok -eq $false -and $r.Text -match 'bulunamadı' -and $r.Name -eq 'WireGuard') 'kurulum işi: winget deposunda bulunamadı'
Reset-WgTest
$script:WgCodes['WireGuard.WireGuard'] = -1978334966
$r = Job_ExtToolInstall @{ Id = 'WireGuard.WireGuard' }
Assert-True ($r.Ok -eq $false -and $r.Reboot -eq $true -and $r.Text -match 'önce bilgisayarı') 'kurulum işi: önce yeniden başlatma gerekiyorsa başarı sayılmaz'

# winget özel durum verirse
Reset-WgTest
$script:WgThrow['WireGuard.WireGuard'] = 'winget çalıştırılamadı'
$r = Job_ExtToolInstall @{ Id = 'WireGuard.WireGuard' }
Assert-True ($r.Ok -eq $false -and $r.Code -eq -1 -and $r.Text -eq 'winget çıkış kodu -1' -and ($script:WhLog | Where-Object { $_ -match 'winget çalıştırılamadı' }).Count -eq 1) 'kurulum işi: winget özel durum verirse başarısız ve günlüğe yazılır'

# izin listesi dışı ve geçersiz kimlikler winget e hiç gönderilmez
foreach ($bad in @('Vendor.Tool', 'Microsoft.DirectX', '7zip.7zip; calc', '7zip.7zip --source evil', '..\evil', '', '-v', "7zip.7zip`n")) {
    Reset-WgTest
    $r = Job_ExtToolInstall @{ Id = $bad }
    Assert-True ($r.Ok -eq $false -and $script:WgCalls.Count -eq 0 -and $r.Name -eq '' -and $r.Text -ne '' -and ($script:WhLog | Where-Object { $_ -match '^ERR\|' }).Count -eq 1) ('kurulum işi: reddedilir, winget çağrılmaz: [' + ($bad -replace "`n", '\n') + ']')
}
Reset-WgTest
$r = Job_ExtToolInstall @{ }
Assert-True ($r.Ok -eq $false -and $script:WgCalls.Count -eq 0) 'kurulum işi: kimlik anahtarı yoksa güvenli'
$r = Job_ExtToolInstall $null
Assert-True ($r.Ok -eq $false -and $script:WgCalls.Count -eq 0) 'kurulum işi: parametresiz güvenli'

# winget yoksa
Reset-WgTest
$script:WgPath = ''
$r = Job_ExtToolInstall @{ Id = '7zip.7zip' }
Assert-True ($r.Ok -eq $false -and $r.Text -match 'winget bulunamadı' -and $r.Text -match 'App Installer' -and $script:WgCalls.Count -eq 0 -and $r.Name -eq '7-Zip') 'kurulum işi: winget yoksa kurulum denenmez, nedeni söylenir'
$script:WgPath = 'C:\winget.exe'

# =====================================================================
#  6) saf mantık: gruplar, durum arama, satır görünümü, onay metni, bildirim
# =====================================================================
$gr = Get-ExtToolGroups
Assert-True ($gr.Count -eq 4 -and $gr[0].K -eq 'disk' -and $gr[0].T -eq 'Disk ve veri' -and $gr[2].K -eq 'ag' -and $gr[2].T -eq 'Ağ ve güvenlik' -and $gr[3].T -eq 'Verimlilik') 'gruplar: dört grup, Türkçe başlıklar'
$state = @{ Ok = $true; At = '09.11.2026 15:00'; Items = @(@{ Id = '7zip.7zip'; Installed = $true; Path = 'C:\a\7zFM.exe' }, @{ Id = 'WireGuard.WireGuard'; Installed = $false; Path = '' }) }
Assert-True ((Get-ExtToolStateFor $state '7zip.7zip').Installed -eq $true -and (Get-ExtToolStateFor $state 'WireGuard.WireGuard').Installed -eq $false) 'durum arama: kayıt bulunur'
Assert-True ((Get-ExtToolStateFor $state 'Microsoft.PowerToys').Installed -eq $false -and (Get-ExtToolStateFor $null '7zip.7zip').Installed -eq $false -and (Get-ExtToolStateFor @{ Failed = $true } '7zip.7zip').Installed -eq $false) 'durum arama: kayıt yoksa ya da durum bozuksa kurulu değil sayılır'

$tool = Get-ExtTool '7zip.7zip'
$m = Get-ExtToolRowModel $tool (Get-ExtToolStateFor $state '7zip.7zip') $false
Assert-True ($m.Title -eq '7-Zip' -and $m.Tag -eq 'Kurulu' -and $m.BrCol -eq 'BrGood' -and $m.Btn1 -eq 'Aç' -and $m.Btn2 -eq 'Sayfa') 'satır: kurulu araç Aç ve Sayfa düğmeleriyle'
Assert-True ($m.Data.Installed -eq $true -and $m.Data.Path -eq 'C:\a\7zFM.exe' -and $m.Data.Id -eq '7zip.7zip' -and $m.Data.Name -eq '7-Zip' -and $m.Data.Home -eq $tool.Home) 'satır: veri nesnesi'
Assert-True ($m.Detail.StartsWith('Igor Pavlov · ') -and $m.Detail -notmatch 'winget:') 'satır: ayrıntı yayıncı ve açıklama; kullanıcı kipinde winget kimliği yok'
$m = Get-ExtToolRowModel $tool (Get-ExtToolStateFor $state '7zip.7zip') $true
Assert-True ($m.Detail.EndsWith(' · winget: 7zip.7zip')) 'satır: uzman kipinde winget kimliği görünür'
$m = Get-ExtToolRowModel (Get-ExtTool 'WireGuard.WireGuard') (Get-ExtToolStateFor $state 'WireGuard.WireGuard') $false
Assert-True ($m.Tag -eq 'Kurulu değil' -and $m.BrCol -eq 'BrFaint' -and $m.Btn1 -eq 'Kur' -and $m.Btn2 -eq 'Sayfa' -and $m.Data.Installed -eq $false -and $m.Data.Path -eq '') 'satır: eksik araç Kur ve Sayfa düğmeleriyle'
$m = Get-ExtToolRowModel $tool $null $false
Assert-True ($m.Btn1 -eq 'Kur' -and $m.Data.Installed -eq $false) 'satır: durum yoksa kurulu değil'

$ct = Get-ExtToolConfirmText (Get-ExtTool 'WireGuard.WireGuard')
Assert-True ($ct.Contains('WireGuard') -and $ct.Contains('WireGuard LLC') -and $ct.Contains('winget') -and $ct.Contains('SHA-256') -and $ct.Contains('uyuşmazsa kurulmaz')) 'onay metni: araç, yayıncı, winget ve özet doğrulaması'
Assert-True ($ct.Contains('lisans koşullarını kabul') -and $ct.Contains('Sayfa') -and $ct.Contains('yönetici onayı') -and $ct.Contains('parçası değildir') -and $ct.Contains('dokunulmaz')) 'onay metni: lisans kabulü, yönetici onayı, Multimizer parçası değil, kişisel dosyalara dokunulmaz'
Assert-True ($ct -notmatch 'otomatik|kendiliğinden') 'onay metni: otomatik işlem vaadi yok'

$mi = Get-ExtToolInstallModel $null
Assert-True ($mi.Kind -eq 'bad' -and $mi.Text -match 'tamamlanamadı') 'bildirim: sonuç yoksa hata'
$mi = Get-ExtToolInstallModel @{ Ok = $true; Name = '7-Zip'; Id = '7zip.7zip'; Path = 'C:\x.exe'; Reboot = $false; Already = $false; Text = 'kuruldu' }
Assert-True ($mi.Kind -eq 'good' -and $mi.Text -eq ('7-Zip kuruldu. ' + [char]0x201C + 'Aç' + [char]0x201D + ' ile başlatabilirsiniz.')) 'bildirim: kuruldu'
$mi = Get-ExtToolInstallModel @{ Ok = $true; Name = '7-Zip'; Path = 'C:\x.exe'; Already = $true }
Assert-True ($mi.Kind -eq 'good' -and $mi.Text.StartsWith('7-Zip zaten kuruluymuş.')) 'bildirim: zaten kurulu'
$mi = Get-ExtToolInstallModel @{ Ok = $true; Name = 'HWiNFO'; Path = ''; Reboot = $false }
Assert-True ($mi.Kind -eq 'warn' -and $mi.Text -match 'beklenen konumda bulunamadı' -and $mi.Text -match 'Başlat menüsünden') 'bildirim: kuruldu ama dosya bulunamadı -> uyarı'
$mi = Get-ExtToolInstallModel @{ Ok = $true; Name = 'HWiNFO'; Path = 'C:\h.exe'; Reboot = $true }
Assert-True ($mi.Kind -eq 'warn' -and $mi.Text -match 'yeniden başlatın') 'bildirim: yeniden başlatma -> uyarı'
$mi = Get-ExtToolInstallModel @{ Ok = $false; Name = 'WireGuard'; Text = 'indirilen dosyanın özeti paketle uyuşmadı; güvenliğiniz için kurulmadı' }
Assert-True ($mi.Kind -eq 'bad' -and $mi.Text.StartsWith('WireGuard kurulamadı: ') -and $mi.Text -match 'kurulmadı') 'bildirim: başarısız'
$mi = Get-ExtToolInstallModel @{ Ok = $false; Id = 'x.y' }
Assert-True ($mi.Kind -eq 'bad' -and $mi.Text -eq 'x.y kurulamadı: bilinmeyen hata') 'bildirim: ad yoksa kimlik, neden yoksa bilinmeyen hata'
$mi = Get-ExtToolInstallModel @{ Ok = $false }
Assert-True ($mi.Text.StartsWith('Araç kurulamadı')) 'bildirim: ad ve kimlik yoksa genel ad'

# =====================================================================
#  7) sayfa akışı (sahte arayüzle)
# =====================================================================
$ui = @{}
foreach ($n in @('tl_List', 'tl_Foot', 'tl_Refresh')) { $ui[$n] = New-FakeCtl }
$script:UiState = @{ Page = 'tools'; Mode = 'Kullanici' }
$script:TlTab = 'ext'
$script:ExtToolState = $null; $script:ExtToolLoading = $false; $script:ExtToolPending = $null
function Click($Ctl) { foreach ($h in @($Ctl.Handlers)) { & $h $Ctl $null } }
function Rows { foreach ($c in $ui.tl_List.Children) { if ($null -ne $c.Vars) { $c } } }

Reset-Fake
Render-TlExt
Assert-True ($ui.tl_List.Children.Count -eq 1 -and $ui.tl_List.Children[0].Text -match 'denetleniyor') 'çizim: durum yokken "denetleniyor" notu'
Assert-True ($script:Asyncs.Count -eq 1 -and $script:Asyncs[0].Name -eq 'ExtScan' -and $script:Asyncs[0].Entry -eq 'Job_ExtToolScan' -and $script:Asyncs[0].Label -eq 'Dış araçlar denetleniyor') 'çizim: denetim işi başlatılır'
Render-TlExt; Load-TlExt
Assert-Eq $script:Asyncs.Count 1 'çizim: denetim sürerken ikinci iş başlatılmaz'
$job = $script:Asyncs[0]
$real = Job_ExtToolScan @{}
& $job.OnDone $real
Assert-True ($script:ExtToolLoading -eq $false -and $script:ExtToolState.Ok -eq $true) 'tamamlanma: yükleniyor işareti kalkar, durum saklanır'
$rows = Rows
Assert-Eq $rows.Count 9 'çizim: dokuz araç satırı'
$heads = @($ui.tl_List.Children | Where-Object { $_.Head -eq $true } | ForEach-Object { [string]$_.Text })
Assert-Eq ($heads -join '|') 'Disk ve veri|Sistem ve donanım|Ağ ve güvenlik|Verimlilik' 'çizim: grup başlıkları sırayla'
Assert-True ($ui.tl_List.Children[0].Kind -eq 'dim' -and $ui.tl_List.Children[0].Text -match 'kopyalamaz' -and $ui.tl_List.Children[0].Text -match 'onayınızla' -and $ui.tl_List.Children[0].Text -match 'winget') 'çizim: açıklama notu ilkeyi söyler'
Assert-True ($ui.tl_Foot.Text -eq ('Denetlendi: ' + [string]$real.At + '  ·  Kurulumdan sonra ' + [char]0x201C + 'Yenile' + [char]0x201D + 'ye basarak sonucu doğrulayın.')) 'çizim: alt bilgi'
$instIds = @($real.Items | Where-Object { $_.Installed -eq $true } | ForEach-Object { [string]$_.Id })
foreach ($rw in $rows) {
    $d = $rw.Tag
    $isInst = $instIds -contains [string]$d.Id
    Assert-True (($d.Installed -eq $isInst) -and ($rw.Vars.Btn1 -eq $(if ($isInst) { 'Aç' } else { 'Kur' })) -and $rw.Vars.Btn2 -eq 'Sayfa') ('çizim: düğmeler denetime uyar ' + [string]$d.Id)
    Assert-True ($rw.Vars.Tag -eq $(if ($isInst) { 'Kurulu' } else { 'Kurulu değil' }) -and $rw.Vars.BrCol -eq $(if ($isInst) { 'BrGood' } else { 'BrFaint' })) ('çizim: durum etiketi ve renk ' + [string]$d.Id)
    Assert-True ($rw.Named.Act.Handlers.Count -eq 1 -and $rw.Named.Act2.Handlers.Count -eq 1 -and $rw.Named.Chk.Visibility -eq $script:VisOff) ('çizim: işleyiciler bağlı, onay kutusu gizli ' + [string]$d.Id)
    Assert-True ($rw.Vars.Detail -notmatch 'winget:') ('çizim: kullanıcı kipinde winget kimliği yok ' + [string]$d.Id)
}
# satırlar, başlıklarının altında sıralanır
$order = @($ui.tl_List.Children | ForEach-Object { if ($_.Head -eq $true) { 'H:' + $_.Text } elseif ($null -ne $_.Vars) { 'R:' + $_.Vars.Title } })
Assert-True ($order[0] -eq 'H:Disk ve veri' -and ($order -join ',').IndexOf('H:Sistem ve donanım') -gt ($order -join ',').IndexOf('R:CrystalDiskInfo')) 'çizim: satırlar kendi grubunun altında'

# uzman kipi
$script:UiState = @{ Page = 'tools'; Mode = 'Expert' }
Render-TlExt
Assert-True (@(Rows | Where-Object { $_.Vars.Detail -match 'winget: ' }).Count -eq 9) 'çizim: uzman kipinde her satırda winget kimliği'
$script:UiState = @{ Page = 'tools'; Mode = 'Kullanici' }
Render-TlExt

# kurulu aracı aç
Reset-Fake
$inst = @(Rows | Where-Object { $_.Tag.Installed -eq $true })[0]
Click $inst.Named.Act
Assert-True ($script:Opened.Count -eq 1 -and $script:Opened[0] -eq ('path:' + [string]$inst.Tag.Path) -and $script:Toasts.Count -eq 0 -and $script:Confirms.Count -eq 0) 'açma: kurulu araç Open-Path ile açılır, onay istenmez'
# dosya denetimden sonra silinmişse
$gone = Join-Path $pf '7-Zip/7zFM.exe'
$z = @(Rows | Where-Object { $_.Tag.Id -eq '7zip.7zip' })[0]
Remove-Item -LiteralPath $gone -Force
Reset-Fake
Click $z.Named.Act
Assert-True ($script:Opened.Count -eq 0 -and $script:Toasts.Count -eq 1 -and $script:Toasts[0].T -eq '7-Zip bulunamadı; liste yenileniyor.' -and $script:Toasts[0].K -eq 'warn') 'açma: dosya yoksa açılmaz, uyarılır'
Assert-True ($null -eq $script:ExtToolState -and $script:Asyncs.Count -eq 1 -and $script:Asyncs[0].Name -eq 'ExtScan') 'açma: dosya yoksa liste yeniden denetlenir'
$script:ExtToolLoading = $false
& $script:Asyncs[0].OnDone (Job_ExtToolScan @{})
Assert-True ((@(Rows | Where-Object { $_.Tag.Id -eq '7zip.7zip' })[0]).Vars.Btn1 -eq 'Kur') 'açma: yenilenen listede 7-Zip artık Kur'

# eksik aracı kur: onay istenir, onaylanmadan iş başlamaz
Reset-Fake
$miss = @(Rows | Where-Object { $_.Tag.Id -eq 'WireGuard.WireGuard' })[0]
Click $miss.Named.Act
Assert-True ($script:Confirms.Count -eq 1 -and $script:Confirms[0].Title -eq 'Dış aracı kur' -and $script:Confirms[0].Ok -eq 'Kur' -and $script:Confirms[0].Danger -eq $false -and $script:Confirms[0].Text.Contains('WireGuard') -and $script:Confirms[0].Text.Contains('SHA-256')) 'kurma: onay penceresi araç ve doğrulamayı söyler'
Assert-Eq $script:Asyncs.Count 0 'kurma: onaylanmadan hiçbir iş başlamaz'
Assert-True ($script:ExtToolPending.Id -eq 'WireGuard.WireGuard') 'kurma: bekleyen araç saklanır'
& $script:Confirms[0].OnOk
$a = $script:Asyncs[$script:Asyncs.Count - 1]
Assert-True ($script:Asyncs.Count -eq 1 -and $a.Name -eq 'ExtInstall' -and $a.Entry -eq 'Job_ExtToolInstall' -and $a.Params.Id -eq 'WireGuard.WireGuard' -and $a.Params.Count -eq 1 -and $a.Label -eq 'WireGuard kuruluyor') 'kurma: onaydan sonra iş yalnızca o kimlikle başlar'
# iş bitince
Reset-Fake
$script:ExtToolState = @{ Ok = $true; Items = @(); At = 'x' }
& $a.OnDone @{ Ok = $true; Name = 'WireGuard'; Id = 'WireGuard.WireGuard'; Path = 'C:\wg.exe'; Reboot = $false; Already = $false; Text = 'kuruldu' }
Assert-True ($script:Toasts.Count -eq 1 -and $script:Toasts[0].K -eq 'good' -and $script:Toasts[0].T.StartsWith('WireGuard kuruldu.') -and $null -eq $script:ExtToolPending) 'kurma: bitince bildirim, bekleyen temizlenir'
Assert-True ($script:Asyncs.Count -eq 1 -and $script:Asyncs[0].Name -eq 'ExtScan') 'kurma: bitince liste yeniden denetlenir'
$script:ExtToolLoading = $false
Reset-Fake
Complete-ExtToolInstall @{ Ok = $false; Name = 'WireGuard'; Text = 'winget deposunda bulunamadı' }
Assert-True ($script:Toasts.Count -eq 1 -and $script:Toasts[0].K -eq 'bad' -and $script:Toasts[0].T -eq 'WireGuard kurulamadı: winget deposunda bulunamadı') 'kurma: başarısız bildirim'
$script:ExtToolLoading = $false
Reset-Fake
$script:TlTab = 'win'; $ui.tl_List.Children.Clear()
Complete-ExtToolInstall $null
Assert-True ($script:Toasts[0].K -eq 'bad' -and $script:Asyncs.Count -eq 0 -and $ui.tl_List.Children.Count -eq 0) 'kurma: başka sekmedeyken liste çizilmez'
$script:TlTab = 'ext'

# izin listesi dışı kimlik onay penceresine bile gelmez
Reset-Fake
Start-ExtToolInstall @{ Id = 'Vendor.Tool'; Name = 'Yok' }
Assert-True ($script:Confirms.Count -eq 1 -and $script:Confirms[0].Message -eq $true -and $script:Confirms[0].Title -eq 'Bu araç kurulamaz' -and $script:Confirms[0].Text -match 'izin listesinde değil' -and $null -eq $script:Confirms[0].OnOk -and $script:Asyncs.Count -eq 0) 'kurma: izin listesi dışı kimlik reddedilir, onay ve iş yok'
Reset-Fake
Invoke-TlExtAction $null
Assert-True ($script:Confirms.Count -eq 0 -and $script:Asyncs.Count -eq 0 -and $script:Opened.Count -eq 0) 'eylem: veri yoksa hiçbir şey yapılmaz'

# Sayfa düğmesi
Reset-Fake
$script:ExtToolLoading = $false
Complete-TlExt (Job_ExtToolScan @{})
Reset-Fake
$any = @(Rows)[0]
Click $any.Named.Act2
Assert-True ($script:Opened.Count -eq 1 -and $script:Opened[0] -eq ('url:' + [string]$any.Tag.Home) -and ([string]$any.Tag.Home).StartsWith('https://')) 'sayfa: resmî sayfa tarayıcıda açılır'

# denetim sonucu
$script:ExtToolState = $null
Reset-Fake
Complete-TlExt $null
Assert-True ($script:ExtToolState.Failed -eq $true -and $ui.tl_List.Children.Count -eq 1 -and $ui.tl_List.Children[0].Kind -eq 'warn' -and $ui.tl_List.Children[0].Text -match 'Denetim yapılamadı' -and $script:Asyncs.Count -eq 0) 'tamamlanma: başarısız denetim uyarı notu gösterir, yeniden iş başlatmaz'
Complete-TlExt @{ Ok = $false; Error = 'x' }
Assert-True ($script:ExtToolState.Failed -eq $true) 'tamamlanma: Ok=false başarısız sayılır'
$script:TlTab = 'win'; $ui.tl_List.Children.Clear()
Complete-TlExt @{ Ok = $true; Items = @(); At = 'a' }
Assert-True ($ui.tl_List.Children.Count -eq 0 -and $script:ExtToolState.Ok -eq $true) 'tamamlanma: başka sekmedeyken çizilmez'
$script:TlTab = 'ext'; $script:UiState = @{ Page = 'history'; Mode = 'Kullanici' }
Complete-TlExt @{ Ok = $true; Items = @(); At = 'a' }
Assert-Eq $ui.tl_List.Children.Count 0 'tamamlanma: başka sayfadayken çizilmez'
$script:UiState = @{ Page = 'tools'; Mode = 'Kullanici' }

# Yenile düğmesi sekmeye göre davranır
$script:ProcRenders = 0
function Render-TlProcs { $script:ProcRenders++ }
function Render-TlWin { $script:TabCalls += 'win' }
function Render-TlRepair { $script:TabCalls += 'repair' }
function Render-TlFiles { $script:TabCalls += 'files' }
function Render-TlSys { $script:TabCalls += 'sys' }
$script:TabCalls = @()
$script:ExtToolState = @{ Ok = $true; Items = @(); At = 'x' }; $script:ExtToolLoading = $false
Reset-Fake
$script:TlTab = 'ext'
Invoke-TlRefresh
Assert-True ($script:ProcRenders -eq 0 -and $script:Asyncs.Count -eq 1 -and $script:Asyncs[0].Name -eq 'ExtScan') 'yenile: Dış araçlar sekmesinde yalnızca bu liste yeniden denetlenir'
$script:TlTab = 'procs'; $script:TlProcs = @(1, 2); $script:ExtToolState = @{ Ok = $true; Items = @(); At = 'x' }
Invoke-TlRefresh
Assert-True ($script:ProcRenders -eq 1 -and $null -eq $script:TlProcs -and $null -ne $script:ExtToolState) 'yenile: İşlemler sekmesinde davranış değişmedi'

# sekme geçişi
$script:BarShown = $null
Reset-Fake
$script:ExtToolState = $null; $script:ExtToolLoading = $false
Set-TlTab 'ext'
Assert-True ($script:TlTab -eq 'ext' -and ($script:BarShown -join ',') -eq 'tl_Refresh' -and $script:Asyncs.Count -eq 1) 'sekme: Dış araçlar yalnızca Yenile düğmesini gösterir ve listeyi çizer'
foreach ($k in @('win', 'procs', 'repair', 'files', 'sys')) { $script:TabCalls = @(); Set-TlTab $k; Assert-True ($script:TlTab -eq $k) ('sekme: ' + $k + ' hâlâ açılır') }
Assert-Eq ($script:TabCalls -join ',') 'sys' 'sekme: son sekme çizildi'

# =====================================================================
#  8) bağlantılar: XAML, sekme listesi, Duman turu, arama, komut, pano
# =====================================================================
Assert-Eq ($script:TlTabs -join ',') 'win,procs,repair,files,sys,ext,kit' 'sekmeler: Dış araçlar ve ardından Yardımcılar'
$pageXaml = [regex]::Match($src, '(?s)\$script:Page_tools = @''\r?\n(.*?)\r?\n''@').Groups[1].Value
Assert-True ($pageXaml.Length -gt 500) 'XAML: Araçlar sayfası bulundu'
foreach ($k in $script:TlTabs) { Assert-Eq ([regex]::Matches($pageXaml, 'x:Name="tl_Tab_' + $k + '"').Count) 1 ('XAML: sekme düğmesi bir kez ' + $k) }
Assert-True ($pageXaml -match 'x:Name="tl_Tab_ext" Content="D&#x0131;&#x015F; ara&#x00E7;lar" Tag="ext" GroupName="tl_tabs" Style="\{DynamicResource Chip\}"/>') 'XAML: Dış araçlar sekmesi doğru etiket, etiket değeri ve grupla'
Assert-True ($pageXaml.IndexOf('tl_Tab_sys') -lt $pageXaml.IndexOf('tl_Tab_ext')) 'XAML: Dış araçlar sekmesi Sistem sekmesinden sonra'
Assert-True ($pageXaml -match 'yerle&#x015F;ik d&#x0131;&#x015F; ara&#x00E7;lar&#x0131; tek yerden kurun ve a&#x00E7;&#x0131;n') 'XAML: sayfa açıklaması Dış araçları anlatır'
Assert-True ($pageXaml -match 'x:Name="tl_Refresh"') 'XAML: Yenile düğmesi var'
Assert-True ($script:SmokeSafe -contains 'tl_Refresh') 'Duman turu: tl_Refresh güvenli düğme (yalnızca okuma)'
Assert-True ($src.Contains("@('tools', 'tl_Tab_ext', 'tl_Refresh')")) 'Duman turu: Dış araçlar sekmesi açılıp yenilenir'
Assert-True ($src.Contains('$ui.tl_Refresh.Add_Click({ Invoke-Safe { Invoke-TlRefresh } ' + "'Yenile' })")) 'bağlantı: Yenile düğmesi sekmeye göre işleyiciyi çağırır'
Assert-True ($src -notmatch '\$ui\.tl_Refresh\.Add_Click\(\{ Invoke-Safe \{ \$script:TlProcs') 'bağlantı: eski doğrudan işleyici kalmadı'
$ea = $script:BoardActions['extools']
Assert-True ($null -ne $ea -and $ea.Page -eq 'tools' -and $ea.Sub -eq 'ext' -and $ea.Fn -eq '' -and $ea.T -eq 'Dış araçlar' -and $script:BoardActionAccent['extools'] -eq 'BrAccent' -and $src.Contains('x:Key="' + [string]$ea.Ico + '"')) 'pano: Dış araçlar hızlı eylemi'
Assert-Eq $script:CmdPages['harici'] 'tools:ext' 'komut: harici -> Dış araçlar'
Assert-Eq $script:CmdPages['disaraclar'] 'tools:ext' 'komut: disaraclar -> Dış araçlar'
foreach ($w in @('photorec', 'crystaldiskinfo', 'sysinternals', 'hwinfo', 'powertoys', '7zip', 'winget')) { Assert-True ((' ' + [string]$script:BoardSearchWords['tools'] + ' ').Contains(' ' + $w + ' ')) ('arama: Araçlar sayfası ' + $w + ' ile bulunur') }

# temizlik
Remove-Item -LiteralPath $root -Recurse -Force
Show-Result
