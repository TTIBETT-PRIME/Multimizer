. "$PSScriptRoot/lib.ps1"
Import-Fn 'Get-AppFolder','Get-TextSha256','Get-PackFileText','Get-OuiMap','ConvertTo-MacKey','Format-Mac','Test-RandomMac','Get-MacVendor','ConvertTo-IpNum','ConvertFrom-IpNum','Test-InSubnet','Test-UsableMac',
    'New-MdnsEvidence','Get-DevTypeInfo','ConvertFrom-RuleTable','Get-RuleTable','New-Score','Add-Score','Add-OsHint','Invoke-RuleTable','ConvertTo-CleanText','Test-GenericDevName','Get-NameCandidates',
    'Get-DeviceClass','Get-DeviceTitle','Get-DeviceSummary','Get-DeviceRisks',
    'Get-LanFile','Get-KnownSet','Get-DevNameMap','Read-LanHistory','Get-GwBaselineKey','Test-GatewayBaseline','Set-GwBaseline','Get-NeighborIps6','Get-ProtectedIps','Test-DevBlockAllowed',
    'Get-FwDevRuleName','Get-DevAddrList','New-FwDevRules','Invoke-FwDevOp','Undo-FwDevItem','New-DevBlockStep','Get-DevBlockRows','Update-DevBlockIps','Job_LanScan','Read-LanLast','Job_ArpCheck','Invoke-GwTrustAction',
    'ConvertTo-Hashtable','Get-DefaultSettings','Get-Settings','Save-Settings','Save-JsonFile','Read-JsonFile','Write-WhLog','Write-LogFile','Test-PrivateIp','Add-Skip','Add-Plan','Add-Done','Add-Err',
    'Test-JobCancel','Set-JobProgress','Step-JobProgress'
Import-Var 'PackHash','OuiMap','VmMacPrefixes','DevTypes','DevTypeOrder','RuleVendor','RuleHost','RuleMdns','RuleUpnp','RuleSsdp','RuleHttp','RuleCache','FwDevGroup','ProbePorts'
$script:Changes = 0; $script:Skipped = 0; $script:Errors = 0
$script:MoreOps = @{}; $script:MoreUndo = @{}

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('mmlan' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $tmp | Out-Null
$sync = @{ DataDir = $tmp; SettingsFile = (Join-Path $tmp 'settings.json'); LogFile = ''; ScriptPath = $script:TestPath; Queue = (New-Object System.Collections.Queue); Echo = $false }
$J = $null

# ---- Windows islevlerinin yerine gecenler ----
$script:Fw = @{}
$script:Jrnl = New-Object System.Collections.ArrayList
function Add-Journal($o) { [void]$script:Jrnl.Add($o) }
function New-NetFirewallRule { [CmdletBinding()] param([string]$Name, [string]$DisplayName, [string]$Description, [string]$Group, [string]$Direction, [string]$Action, $RemoteAddress, [string]$Profile)
    if ($script:Fw.ContainsKey($Name)) { Write-Error 'var'; return }
    $script:Fw[$Name] = [pscustomobject]@{ Name = $Name; DisplayName = $DisplayName; Description = $Description; Group = $Group; Direction = $Direction; Action = $Action; RemoteAddress = @($RemoteAddress); Enabled = 'True' } }
function Get-NetFirewallRule { [CmdletBinding()] param([string]$Name, [string]$Group)
    if ($Name -ne '') { if ($script:Fw.ContainsKey($Name)) { return $script:Fw[$Name] } else { Write-Error 'yok'; return } }
    if ($Group -ne '') { return @($script:Fw.Values | Where-Object { $_.Group -eq $Group }) }
    return @($script:Fw.Values) }
function Remove-NetFirewallRule { [CmdletBinding()] param([string[]]$Name) foreach ($n in $Name) { [void]$script:Fw.Remove($n) } }
function Set-NetFirewallRule { [CmdletBinding()] param([string]$Name, $RemoteAddress, [string]$Description) if (-not $script:Fw.ContainsKey($Name)) { Write-Error 'yok'; return }; $script:Fw[$Name].RemoteAddress = @($RemoteAddress); $script:Fw[$Name].Description = $Description }
function Get-NetNeighbor { [CmdletBinding()] param([string]$AddressFamily) return @() }
function Get-NetIPAddress { [CmdletBinding()] param([string]$AddressFamily) return @([pscustomobject]@{ IPAddress = '192.168.1.10' }, [pscustomobject]@{ IPAddress = '127.0.0.1' }) }
function Get-NetRoute { [CmdletBinding()] param([string]$DestinationPrefix) return @([pscustomobject]@{ NextHop = '192.168.1.1' }) }
function Get-DnsClientServerAddress { [CmdletBinding()] param([string]$AddressFamily) return @([pscustomobject]@{ ServerAddresses = @('192.168.1.1', '1.1.1.1') }) }

# ---- ag ilkelleri (sahte) ----
$script:World = @{}
function Get-LanContext { return @{ Ok = $true; Error = ''; Ip = '192.168.1.10'; Prefix = 24; Gateway = '192.168.1.1'; Mac = 'F0F61C000010'; Alias = 'Wi-Fi'; Index = 5; Wifi = $true; Ssid = 'EvAgi'; Category = 'Private'; Dns = @('192.168.1.1'); Targets = @('192.168.1.1', '192.168.1.23', '192.168.1.30', '192.168.1.99') } }
function Invoke-PingSweep($Targets, [int]$TimeoutMs = 700, [int]$Batch = 96) { $r = @{}; foreach ($ip in $script:World.Alive) { $r[$ip] = @{ Ttl = 64; Rtt = 3 } }; $r['192.168.1.30'] = @{ Ttl = 255; Rtt = 5 }; return $r }
function Get-NeighborMacs { return $script:World.Macs }
function Resolve-NamesBatch($Ips, [int]$WaitMs = 2500) { return @{ '192.168.1.1' = 'router.lan' } }
function Invoke-NbtScan($Ips, [int]$WaitMs = 1600) { return @{} }
function Invoke-MdnsScan($LiveIps, [string]$LocalIp, [int]$WaitMs = 2800) {
    $m = New-MdnsEvidence
    [void]$m.Services.Add('_companion-link._tcp.local'); $m.Txt['rpmd'] = 'iPhone14,5'; $m.Instances['_companion-link._tcp.local'] = 'Ayse iPhone'
    return @{ '192.168.1.23' = $m } }
function Invoke-SsdpScan([string]$LocalIp, [int]$WaitMs = 2600) { return @{} }
function Get-UpnpInfo($Locations, [string]$Ip) { return $null }
function Invoke-PortProbe($Ips, $Ports, [int]$TimeoutMs = 650, [int]$Batch = 160) { return @{ '192.168.1.30' = @(80, 631, 9100); '192.168.1.99' = @(23) } }
function Get-HttpSummary([string]$Ip, [int]$Port) { return @{ Status = 200; Server = 'HP HTTP Server'; Title = 'HP OfficeJet 3830'; Realm = '' } }
function Test-PrivateIp2 { }

$script:World.Alive = @('192.168.1.1', '192.168.1.23', '192.168.1.30', '192.168.1.99')
$script:World.Macs = @{ '192.168.1.1' = 'B0BE76AABB01'; '192.168.1.23' = 'DA11223344AA'; '192.168.1.30' = 'F4F5D8010203'; '192.168.1.99' = '8CAAB5000099' }

# ---- 1) ilk tarama ----
$r = Job_LanScan @{ Deep = $true }
Assert-True ($r.Ok -eq $true) 'tarama basarili'
Assert-Eq @($r.Devices).Count 5 'bu bilgisayar + 4 cihaz'
$byIp = @{}; foreach ($d in $r.Devices) { $byIp[$d.Ip] = $d }
Assert-Eq $byIp['192.168.1.1'].Type 'router' 'ag gecidi yonlendirici'
Assert-True ($byIp['192.168.1.1'].IsGateway -eq $true) 'gateway bayragi'
Assert-Eq $byIp['192.168.1.10'].Type 'self' 'kendi bilgisayarim'
Assert-Eq $byIp['192.168.1.23'].Type 'phone' 'iPhone'
Assert-Eq $byIp['192.168.1.23'].Name 'Ayse iPhone' 'iPhone adi'
Assert-True ($byIp['192.168.1.23'].Random -eq $true) 'rastgele MAC isaretli'
Assert-Eq $byIp['192.168.1.30'].Type 'printer' 'yazici'
Assert-Eq $byIp['192.168.1.30'].HttpTitle 'HP OfficeJet 3830' 'web basligi'
Assert-Eq $byIp['192.168.1.99'].Type 'iot' 'telnet acik IoT/kamera benzeri'  # uretici Espressif -> iot
Assert-True (@($byIp['192.168.1.99'].Risks | Where-Object { $_.Sev -eq 'bad' }).Count -eq 1) 'telnet riski'
Assert-Eq $r.Devices[0].Ip '192.168.1.1' 'siralama: once ag gecidi'
Assert-Eq $r.Devices[1].Ip '192.168.1.10' 'siralama: sonra bu bilgisayar'
Assert-Eq @($r.Alerts | Where-Object { $_.Key -eq 'new-dev' }).Count 0 'ilk taramada yeni cihaz alarmi yok'
Assert-Eq @($r.Alerts | Where-Object { $_.Key -eq 'risk' }).Count 1 'ciddi risk alarmi'
Assert-Eq $r.Arp.Status 'new' 'ag gecidi taban cizgisi ilk kez'
Assert-True (Test-Path (Join-Path $tmp 'lan-last.json')) 'son tarama diske yazildi'
Assert-True (Test-Path (Join-Path $tmp 'lan-history.json')) 'gecmis diske yazildi'
$last = Read-LanLast
Assert-Eq @($last.Devices).Count 5 'diskten okunan cihaz sayisi'
Assert-Eq ([datetime](Get-Settings).LastNetScan).ToString('s') $r.At 'son tarama zamani'
Assert-True ($byIp['192.168.1.99'].New -eq $true) 'tanidik degil -> yeni'
Assert-True ($byIp['192.168.1.1'].New -eq $false -and $byIp['192.168.1.10'].New -eq $false) 'ag gecidi ve kendim yeni sayilmaz'

# ---- 2) ikinci tarama: yeni cihaz, tanidik isaretleme ----
$S = Get-Settings; $S.KnownDevices = @('DA11223344AA', 'F4F5D8010203'); $S.DeviceNames = @{ 'F4F5D8010203' = 'Ofis yazicisi' }; Save-Settings $S
$script:World.Alive += '192.168.1.77'
$script:World.Macs['192.168.1.77'] = '3C5AB4777777'
$r2 = Job_LanScan @{ Deep = $false }
$by2 = @{}; foreach ($d in $r2.Devices) { $by2[$d.Ip] = $d }
Assert-True ($by2['192.168.1.77'].Fresh -eq $true) 'yeni katilan cihaz taze'
Assert-True ($by2['192.168.1.99'].Fresh -eq $false) 'onceki cihaz taze degil'
Assert-Eq @($r2.Alerts | Where-Object { $_.Key -eq 'new-dev' }).Count 1 'yeni cihaz alarmi'
Assert-True ($by2['192.168.1.23'].Known -eq $true -and $by2['192.168.1.23'].New -eq $false) 'tanidik cihaz'
Assert-Eq $by2['192.168.1.30'].Name 'Ofis yazicisi' 'kullanicinin verdigi ad'
Assert-Eq $by2['192.168.1.30'].NameSrc 'sizin adınız' 'ad kaynagi'
Assert-Eq $r2.Arp.Status 'ok' 'ag gecidi degismedi'
Assert-Eq $by2['192.168.1.30'].Ports.Count 0 'hizli taramada port yok (yeni kayit)'

# ---- 3) ag gecidi MAC degisti / yinelenen MAC ----
$script:World.Macs['192.168.1.1'] = '00AABBCCDDEE'
$r3 = Job_LanScan @{ Deep = $false }
Assert-Eq $r3.Arp.Status 'changed' 'ag gecidi MAC degisikligi'
Assert-Eq @($r3.Alerts | Where-Object { $_.Key -eq 'gw-changed' }).Count 1 'degisiklik alarmi'
$script:World.Macs['192.168.1.99'] = '00AABBCCDDEE'
$r4 = Job_LanScan @{ Deep = $false }
Assert-Eq @($r4.Alerts | Where-Object { $_.Key -eq 'gw-dup' }).Count 1 'ayni MAC ikinci adreste alarmi'
$script:World.Macs['192.168.1.99'] = '8CAAB5000099'
# guvenilir sayma
Invoke-GwTrustAction @{}
$r5 = Job_LanScan @{ Deep = $false }
Assert-Eq $r5.Arp.Status 'ok' 'guvenilir kaydedilince tekrar uyari yok'

# ---- 4) engelleme ----
Assert-Eq (Test-DevBlockAllowed '192.168.1.1') 'Ağ geçidi (yönlendirici) engellenemez; internet bağlantınız kesilirdi.' 'ag gecidi engellenemez'
Assert-True ((Test-DevBlockAllowed '192.168.1.10') -match 'kendi adresi') 'kendimi engelleyemem'
Assert-True ((Test-DevBlockAllowed '8.8.8.8') -match 'yerel') 'ortak adres engellenmez'
Assert-True ((Test-DevBlockAllowed '169.254.3.3') -match 'yerel') 'link-local engellenmez'
Assert-Eq (Test-DevBlockAllowed '192.168.1.99') '' 'normal cihaz engellenebilir'
Invoke-FwDevOp @{ T = 'FwDev'; Mac = '8CAAB5000099'; Ip = '192.168.1.99'; Name = 'Supheli'; On = $true }
Assert-Eq $script:Fw.Count 2 'iki kural (gelen+giden)'
Assert-True ($script:Fw['Multimizer-dev-8CAAB5000099-in'].Direction -eq 'Inbound') 'gelen kural'
Assert-True ($script:Fw['Multimizer-dev-8CAAB5000099-out'].Action -eq 'Block') 'giden kural engel'
Assert-Eq $script:Jrnl.Count 1 'gunluge yazildi'
Assert-Eq $script:Jrnl[0].T 'FwDev' 'gunluk turu'
$before = $script:Fw.Count
Invoke-FwDevOp @{ T = 'FwDev'; Mac = '8CAAB5000099'; Ip = '192.168.1.99'; Name = 'Supheli'; On = $true }
Assert-Eq $script:Fw.Count $before 'ikinci engelleme yinelenmez'
Invoke-FwDevOp @{ T = 'FwDev'; Mac = 'B0BE76AABB01'; Ip = '192.168.1.1'; Name = 'Router'; On = $true }
Assert-Eq $script:Fw.Count $before 'ag gecidi engellenmedi'
Invoke-FwDevOp @{ T = 'FwDev'; Mac = 'zz'; Ip = '192.168.1.5'; Name = 'x'; On = $true }
Assert-Eq $script:Fw.Count $before 'gecersiz MAC reddedildi'
$rows = Get-DevBlockRows
Assert-Eq $rows.Count 1 'engel satiri'
Assert-Eq $rows[0].Mac '8CAAB5000099' 'engel satiri MAC'
Assert-Eq $rows[0].Ip '192.168.1.99' 'engel satiri IP'
Assert-Eq $rows[0].Name 'Supheli' 'engel satiri ad'
# tarama engel bayragini gosterir
$r6 = Job_LanScan @{ Deep = $false }
$by6 = @{}; foreach ($d in $r6.Devices) { $by6[$d.Ip] = $d }
Assert-True ($by6['192.168.1.99'].Blocked -eq $true) 'engelli bayragi'
# DHCP ile adres degisti -> kural tasinir
$script:World.Alive = @($script:World.Alive | Where-Object { $_ -ne '192.168.1.99' }) + '192.168.1.120'
$script:World.Macs.Remove('192.168.1.99'); $script:World.Macs['192.168.1.120'] = '8CAAB5000099'
$r7 = Job_LanScan @{ Deep = $false }
Assert-True (@($script:Fw['Multimizer-dev-8CAAB5000099-in'].RemoteAddress) -contains '192.168.1.120') 'kural yeni adrese tasindi'
Assert-True ($script:Fw['Multimizer-dev-8CAAB5000099-in'].Description.StartsWith('192.168.1.120|')) 'kural aciklamasi guncellendi'
# cevrimdisi engelli
$script:World.Alive = @($script:World.Alive | Where-Object { $_ -ne '192.168.1.120' }); $script:World.Macs.Remove('192.168.1.120')
$r8 = Job_LanScan @{ Deep = $false }
Assert-Eq @($r8.BlockedOffline).Count 1 'cevrimdisi engelli listelenir'
# geri alma
Undo-FwDevItem @{ T = 'FwDev'; Mac = '8CAAB5000099'; Ip = '192.168.1.120'; Name = 'Supheli' }
Assert-Eq $script:Fw.Count 0 'geri al: kurallar silindi'
Invoke-FwDevOp @{ T = 'FwDev'; Mac = '8CAAB5000099'; Ip = '192.168.1.120'; Name = 'Supheli'; On = $true }
Invoke-FwDevOp @{ T = 'FwDev'; Mac = '8CAAB5000099'; Ip = '192.168.1.120'; Name = 'Supheli'; On = $false }
Assert-Eq $script:Fw.Count 0 'engel kaldirma'
Assert-Eq $script:Jrnl[$script:Jrnl.Count - 1].T 'FwDevDel' 'kaldirma gunlugu'
Undo-FwDevItem @{ T = 'FwDevDel'; Mac = '8CAAB5000099'; Ip = '192.168.1.120'; Name = 'Supheli' }
Assert-Eq $script:Fw.Count 2 'kaldirmayi geri al: kurallar geri geldi'
# onizleme modu degisiklik yapmaz
$script:Fw.Clear(); $script:Preview = $true
Invoke-FwDevOp @{ T = 'FwDev'; Mac = '8CAAB5000099'; Ip = '192.168.1.120'; Name = 'Supheli'; On = $true }
Assert-Eq $script:Fw.Count 0 'onizleme kural eklemez'
$script:Preview = $false
$st = New-DevBlockStep @{ MacKey = '8CAAB5000099'; Ip = '192.168.1.120'; Name = 'Supheli' } $true
Assert-Eq $st.Ops[0].T 'FwDev' 'adim turu'
Assert-True ($st.Reboot -eq $false) 'yeniden baslatma gerekmez'

# ---- 5) ARP denetimi ----
$script:World.Macs['192.168.1.1'] = '00AABBCCDDEE'
$ac = Job_ArpCheck @{}
Assert-Eq $ac.Status 'ok' 'ARP denetimi: taban cizgisi ile ayni'
$script:World.Macs['192.168.1.1'] = '11AABBCCDDEE'
$ac = Job_ArpCheck @{}
Assert-Eq $ac.Status 'changed' 'ARP denetimi: degisim'

Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
Show-Result
