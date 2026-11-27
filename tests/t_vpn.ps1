. "$PSScriptRoot/lib.ps1"
Import-Fn 'Get-VpnIpKind','ConvertFrom-VpnCidr','ConvertFrom-WgEndpoint','Test-WgKey','ConvertFrom-WgConfig','ConvertTo-WgConfText','Get-WgSummary','ConvertTo-WgName',
    'Get-VpnDir','Get-WgConfPath','Get-WgSvcState','Get-WgTunnels','Save-WgConfig','Import-WgConfFile','Start-WgTunnel','Stop-WgTunnel','Remove-WgConfig',
    'Get-WinVpnProfiles','Test-VpnProfileName','Test-VpnServerText','Add-WinVpnProfile','Set-WinVpnStrong','Connect-WinVpn','Disconnect-WinVpn','Remove-WinVpnProfile','Get-VpnActive','Get-VpnClients',
    'ConvertTo-IpLong','ConvertFrom-IpLong','Format-IpRange','Get-IpRangesExcept4','Resolve-VpnHostIps','Get-TunnelDns','Get-TunnelAddrs','Get-KsContext','New-KsRuleSpecs','New-KsRule',
    'Get-KsState','Test-KsPreconditions','Restore-KsState','Disable-KillSwitchNow','Invoke-KsOffAction','Invoke-KillSwitchOp','Undo-KillSwitchItem','New-KsStep','Test-KsConnectivity','Job_KsVerify',
    'Get-OsBuildNumber','Test-DohSupported','Get-DohExisting','Get-DohState','Invoke-DohRegOp','Undo-DohRegItem','New-DohSteps','New-SmartNameStep',
    'New-DnsSteps','Get-ShortHash','ConvertFrom-CfTrace','New-LeakReport','Job_LeakTest','Job_VpnStatus','Job_VpnAction','Job_KsContext','Chk_Vpn',
    'Get-JsonProp','ConvertTo-Hashtable','Get-DefaultSettings','Get-Settings','Save-Settings','Save-JsonFile','Read-JsonFile','Write-WhLog','Write-LogFile','Add-Skip','Add-Plan','Add-Done','Add-Err','Set-JobProgress','Step-JobProgress','Test-JobCancel'
Import-Var 'FwKsGroup','WgNameRe','VpnNameRe','VpnHostRe','WgMaxBytes','VpnAdapterRe','DohProviders','VpnClientDefs'
$script:Changes = 0; $script:Skipped = 0; $script:Errors = 0; $script:Preview = $false
$script:MoreOps = @{}; $script:MoreUndo = @{}; $script:ExtraActions = @{}
$script:MoreOps['KillSwitch'] = 'Invoke-KillSwitchOp'; $script:MoreUndo['KillSwitch'] = 'Undo-KillSwitchItem'
$script:MoreOps['DohReg'] = 'Invoke-DohRegOp'; $script:MoreUndo['DohReg'] = 'Undo-DohRegItem'

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('mmvpn' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $tmp | Out-Null
$sync = @{ DataDir = $tmp; SettingsFile = (Join-Path $tmp 'settings.json'); LogFile = ''; Queue = (New-Object System.Collections.Queue); Echo = $false }
$J = $null

# ---- ortak yardimcilar ----
$script:Jrnl = New-Object System.Collections.ArrayList
function Add-Journal($o) { [void]$script:Jrnl.Add($o) }
function Start-Sleep { param([int]$Seconds, [int]$Milliseconds) }
function Reset-Counters { $script:Changes = 0; $script:Skipped = 0; $script:Errors = 0; $script:Jrnl.Clear() }
$script:Findings = New-Object System.Collections.ArrayList
function Add-Finding { param([string]$Id, [string]$Cat, [string]$Status, [string]$Title, [string]$Detail = '', $Action = $null, [int]$Weight = -1, $Fix = $null) [void]$script:Findings.Add(@{ Id = $Id; Status = $Status; Title = $Title; Action = $Action; Fix = $Fix; Weight = $Weight }) }
function New-RunFix { param([string]$Key, [string]$Label, [string]$Mode = '') return @{ Kind = 'Run'; Key = $Key; Mode = $Mode } }

# ---- anahtar uretimi ----
function New-Key([int]$Seed) { return [Convert]::ToBase64String([byte[]](1..32 | ForEach-Object { [byte](($_ * $Seed) % 251) })) }
$K1 = New-Key 7; $K2 = New-Key 11; $K3 = New-Key 13
$goodConf = @"
# Ornek (yorum)
[Interface]
PrivateKey = $K1   # satir sonu yorumu
Address = 10.64.0.2/32, fd00::2/128
DNS = 10.64.0.1, 2606:4700:4700::1111, vpn.example.net
MTU = 1380

[Peer]
PublicKey = $K2
PresharedKey = $K3
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = 203.0.113.10:51820
PersistentKeepalive = 25
"@

# ======================= 1) temel dogrulayicilar =======================
Assert-Eq (Get-VpnIpKind '1.2.3.4') 4 'ipv4'
Assert-Eq (Get-VpnIpKind '255.255.255.255') 4 'ipv4 ust sinir'
Assert-Eq (Get-VpnIpKind '256.1.1.1') 0 'ipv4 octet 256'
Assert-Eq (Get-VpnIpKind '1.2.3') 0 'ipv4 eksik'
Assert-Eq (Get-VpnIpKind '::1') 6 'ipv6 loopback'
Assert-Eq (Get-VpnIpKind '2606:4700:4700::1111') 6 'ipv6'
Assert-Eq (Get-VpnIpKind 'fe80::1%12') 0 'zone id reddedilir'
Assert-Eq (Get-VpnIpKind 'host.example') 0 'ad ip degil'
Assert-Eq (Get-VpnIpKind '') 0 'bos'
$c = ConvertFrom-VpnCidr '10.0.0.2/32'; Assert-True ($c.Kind -eq 4 -and $c.Prefix -eq 32) 'cidr v4'
$c = ConvertFrom-VpnCidr '10.0.0.2'; Assert-Eq $c.Prefix 32 'prefixsiz v4 = 32'
$c = ConvertFrom-VpnCidr 'fd00::2'; Assert-Eq $c.Prefix 128 'prefixsiz v6 = 128'
Assert-True ($null -eq (ConvertFrom-VpnCidr '10.0.0.2/33')) 'v4 prefix 33'
Assert-True ($null -eq (ConvertFrom-VpnCidr 'fd00::/129')) 'v6 prefix 129'
Assert-True ($null -eq (ConvertFrom-VpnCidr '10.0.0.2/abc')) 'prefix harf'
Assert-True ($null -eq (ConvertFrom-VpnCidr 'abc/24')) 'adres harf'
Assert-Eq (ConvertFrom-VpnCidr '0.0.0.0/0').Prefix 0 '/0 kabul'

$e = ConvertFrom-WgEndpoint '203.0.113.10:51820'; Assert-True ($e.Host -eq '203.0.113.10' -and $e.Port -eq 51820 -and $e.IsIp) 'endpoint v4'
$e = ConvertFrom-WgEndpoint '[2001:db8::1]:443'; Assert-True ($e.Host -eq '2001:db8::1' -and $e.Port -eq 443) 'endpoint v6'
$e = ConvertFrom-WgEndpoint 'vpn.example.com:51820'; Assert-True ($e.Host -eq 'vpn.example.com' -and -not $e.IsIp) 'endpoint ad'
foreach ($bad in @('203.0.113.10', '203.0.113.10:0', '203.0.113.10:65536', '300.1.1.1:80', 'host name:80', '2001:db8::1:443', '[2001:db8::1]', '-bad.example:80', 'a;b:80', ':80', '')) {
    Assert-True ($null -eq (ConvertFrom-WgEndpoint $bad)) ('gecersiz endpoint: ' + $bad)
}
Assert-True (Test-WgKey $K1) 'anahtar gecerli'
Assert-True (-not (Test-WgKey 'abc')) 'kisa anahtar'
Assert-True (-not (Test-WgKey ($K1.Substring(0, 43) + 'A'))) 'sonu = olmayan'
Assert-True (-not (Test-WgKey ('!' + $K1.Substring(1)))) 'gecersiz karakter'

# ======================= 2) yapilandirma cozumleyici =======================
$cfg = ConvertFrom-WgConfig $goodConf
Assert-True $cfg.Ok ('gecerli yapilandirma: ' + ($cfg.Errors -join '|'))
Assert-Eq @($cfg.Interface.Address).Count 2 'iki adres'
Assert-Eq (@($cfg.Interface.Dns) -join ',') '10.64.0.1,2606:4700:4700::1111' 'dns ip listesi'
Assert-Eq (@($cfg.Interface.Search) -join ',') 'vpn.example.net' 'dns arama alani'
Assert-Eq $cfg.Interface.Mtu 1380 'mtu'
Assert-True ($cfg.Full4 -and $cfg.Full6) 'tam tunel'
Assert-Eq @($cfg.Endpoints).Count 1 'tek endpoint'
Assert-Eq @($cfg.Warnings).Count 0 'uyari yok'
$sm = Get-WgSummary $cfg
Assert-Eq $sm.Endpoint '203.0.113.10:51820' 'ozet endpoint'
Assert-Eq (@($sm.Addresses) -join ',') '10.64.0.2,fd00::2' 'ozet adresler (prefixsiz)'
Assert-True (-not (($sm | ConvertTo-Json -Depth 5) -match [regex]::Escape($K1))) 'ozet ozel anahtar icermez'

# kanonik yazim gidis-donus
$txt = ConvertTo-WgConfText $cfg
Assert-True ($txt -notmatch '#') 'kanonik metinde yorum yok'
$cfg2 = ConvertFrom-WgConfig $txt
Assert-True $cfg2.Ok 'kanonik metin yeniden cozulur'
Assert-Eq (ConvertTo-WgConfText $cfg2) $txt 'gidis-donus ayni'
Assert-Eq $cfg2.Peers[0].PresharedKey $K3 'psk korunur'
Assert-Eq $cfg2.Peers[0].Keepalive 25 'keepalive'

function Get-Err([string]$Text) { $r = ConvertFrom-WgConfig $Text; return $r }
$hdr = "[Interface]`nPrivateKey = $K1`nAddress = 10.0.0.2/32`n"
$peer = "[Peer]`nPublicKey = $K2`nAllowedIPs = 0.0.0.0/0`nEndpoint = 1.2.3.4:51820`n"
Assert-True (-not (Get-Err ($hdr + "PostUp = calc.exe`n" + $peer)).Ok) 'PostUp reddedilir'
Assert-True (((Get-Err ($hdr + "PostUp = calc.exe`n" + $peer)).Errors -join ' ') -match 'PostUp') 'PostUp hata metni'
foreach ($k in @('PreUp', 'PreDown', 'PostDown', 'postup')) { Assert-True (-not (Get-Err ($hdr + "$k = x`n" + $peer)).Ok) ($k + ' reddedilir') }
Assert-True (-not (Get-Err ($hdr + "Foo = bar`n" + $peer)).Ok) 'bilinmeyen anahtar'
Assert-True (-not (Get-Err ("[Interface]`nPrivateKey = $K1`nAddress = 10.0.0.2/32`n[Bilinmeyen]`nA = b`n" + $peer)).Ok) 'bilinmeyen bolum'
Assert-True (-not (Get-Err ($hdr + "[Interface]`nPrivateKey = $K1`n" + $peer)).Ok) 'iki Interface'
Assert-True (-not (Get-Err ("PrivateKey = $K1`n" + $peer)).Ok) 'bolum disi satir'
Assert-True (-not (Get-Err ($hdr)).Ok) 'peer yok'
Assert-True (-not (Get-Err ($peer)).Ok) 'interface yok'
Assert-True (-not (Get-Err ("[Interface]`nPrivateKey = bozuk`nAddress = 10.0.0.2/32`n" + $peer)).Ok) 'bozuk ozel anahtar'
Assert-True (-not (Get-Err ("[Interface]`nPrivateKey = $K1`nAddress = 10.0.0.999/32`n" + $peer)).Ok) 'bozuk adres'
Assert-True (-not (Get-Err ("[Interface]`nPrivateKey = $K1`n" + $peer)).Ok) 'adres yok'
Assert-True (-not (Get-Err ($hdr + "MTU = 100`n" + $peer)).Ok) 'mtu cok kucuk'
Assert-True (-not (Get-Err ($hdr + "MTU = 9000`n" + $peer)).Ok) 'mtu cok buyuk'
Assert-True (-not (Get-Err ($hdr + "ListenPort = 70000`n" + $peer)).Ok) 'listenport'
Assert-True (-not (Get-Err ($hdr + "DNS = 1.2.3.4, bad host!`n" + $peer)).Ok) 'dns bozuk'
Assert-True (-not (Get-Err ($hdr + "[Peer]`nPublicKey = $K2`nAllowedIPs = 0.0.0.0/0`n")).Ok) 'endpoint yok'
Assert-True (-not (Get-Err ($hdr + "[Peer]`nPublicKey = $K2`nEndpoint = 1.2.3.4:51820`n")).Ok) 'allowedips yok'
Assert-True (-not (Get-Err ($hdr + "[Peer]`nAllowedIPs = 0.0.0.0/0`nEndpoint = 1.2.3.4:51820`n")).Ok) 'publickey yok'
Assert-True (-not (Get-Err ($hdr + "[Peer]`nPublicKey = $K2`nAllowedIPs = 0.0.0.0/0, 10.0.0.0/40`nEndpoint = 1.2.3.4:51820`n")).Ok) 'allowedips bozuk'
Assert-True (-not (Get-Err ($hdr + "[Peer]`nPublicKey = $K2`nAllowedIPs = 0.0.0.0/0`nEndpoint = nowhere`n")).Ok) 'endpoint bozuk'
Assert-True (-not (Get-Err ($hdr + "[Peer]`nPublicKey = $K2`nPresharedKey = x`nAllowedIPs = 0.0.0.0/0`nEndpoint = 1.2.3.4:51820`n")).Ok) 'psk bozuk'
Assert-True (-not (Get-Err ($hdr + "[Peer]`nPublicKey = $K2`nAllowedIPs = 0.0.0.0/0`nEndpoint = 1.2.3.4:51820`nPersistentKeepalive = abc`n")).Ok) 'keepalive bozuk'
Assert-True (-not (Get-Err '').Ok) 'bos'
Assert-True (-not (Get-Err ("a" * 70000)).Ok) 'cok buyuk'
Assert-True (-not (Get-Err ($goodConf + [string][char]0 + 'x')).Ok) 'NUL karakter'
# ozel anahtar hata metinlerinde gorunmez
$r = Get-Err ("[Interface]`nPrivateKey = $K1`nAddress = 10.0.0.999/32`nFoo = $K1`n" + $peer)
Assert-True ((($r.Errors -join ' ') -notmatch [regex]::Escape($K1))) 'hata metni anahtar icermez'
$r = Get-Err ("[Interface]`nPrivateKey = " + $K1.Substring(0, 40) + "`nAddress = 10.0.0.2/32`n" + $peer)
Assert-True ((($r.Errors -join ' ') -notmatch [regex]::Escape($K1.Substring(0, 40)))) 'bozuk anahtar metne yazilmaz'
# BOM, CRLF, tekrarlanan anahtarlar
$bom = [string][char]0xFEFF + ($goodConf -replace "`n", "`r`n")
Assert-True (Get-Err $bom).Ok 'BOM + CRLF'
$multi = "[Interface]`nPrivateKey = $K1`nAddress = 10.0.0.2/32`nAddress = fd00::2/128`nDNS = 1.1.1.1`nDNS = 9.9.9.9`n[Peer]`nPublicKey = $K2`nAllowedIPs = 0.0.0.0/1`nAllowedIPs = 128.0.0.0/1`nEndpoint = 1.2.3.4:51820`n"
$r = Get-Err $multi
Assert-True $r.Ok 'tekrarlayan anahtarlar'
Assert-Eq @($r.Interface.Address).Count 2 'adresler birikir'
Assert-Eq @($r.Interface.Dns).Count 2 'dns birikir'
Assert-Eq @($r.Peers[0].AllowedIPs).Count 2 'allowedips birikir'
Assert-True (-not $r.Full4) '/1 + /1 tam tunel sayilmaz (yalniz /0)'
# uyarilar
$r = Get-Err ($hdr + "DNS = 1.1.1.1`n[Peer]`nPublicKey = $K2`nAllowedIPs = 10.0.0.0/24`nEndpoint = 1.2.3.4:51820`n")
Assert-True ($r.Ok -and ((@($r.Warnings) -join ' ') -match 'bölünmüş')) 'bolunmus tunel uyarisi'
$r = Get-Err ($hdr + "DNS = 1.1.1.1`n" + $peer)
Assert-True ($r.Ok -and ((@($r.Warnings) -join ' ') -match 'IPv6')) 'ipv6 sizinti uyarisi'
$r = Get-Err ($hdr + $peer)
Assert-True ($r.Ok -and ((@($r.Warnings) -join ' ') -match 'DNS tanımlı değil')) 'dns yok uyarisi'
$r = Get-Err ($hdr + "Table = off`n" + $peer)
Assert-True ($r.Ok -and ((@($r.Warnings) -join ' ') -match 'Table')) 'Table yok sayilir'

# ======================= 3) adlandirma ve dosya islemleri =======================
Assert-Eq (ConvertTo-WgName 'C:\x\Ev Agi (Türkiye).conf') 'Ev_Agi_Turkiye' 'ad temizleme'
Assert-Eq (ConvertTo-WgName 'sırça.conf') 'sirca' 'noktasiz i'
Assert-Eq (ConvertTo-WgName '....conf') 'tunel' 'bos ad'
Assert-Eq (ConvertTo-WgName 'con.conf') 'wg-con' 'ayrilmis ad'
Assert-Eq (ConvertTo-WgName 'nul') 'wg-nul' 'ayrilmis ad 2'
Assert-True ((ConvertTo-WgName ('a' * 80 + '.conf')).Length -le 32) '32 karakter siniri'
Assert-True ((ConvertTo-WgName '..\..\evil;rm.conf') -match $script:WgNameRe) 'yol kacisi temizlenir'
foreach ($n in @('wg0', 'Ev_Agi', 'a=b+c.d-e')) { Assert-True ($n -match $script:WgNameRe) ('gecerli ad ' + $n) }
foreach ($n in @('', 'a b', 'a;b', '../x', ('a' * 33), 'a"b')) { Assert-True ($n -notmatch $script:WgNameRe) ('gecersiz ad [' + $n + ']') }
$thrown = ''; try { [void](Get-WgConfPath 'a b') } catch { $thrown = 'hata' }
Assert-True ($thrown -ne '') 'Get-WgConfPath gecersiz ad firlatir'

$src = Join-Path $tmp 'Ev Agi.conf'
[System.IO.File]::WriteAllText($src, $goodConf)
$imp = Import-WgConfFile $src
Assert-Eq $imp.Name 'Ev_Agi' 'ice aktarilan ad'
$dst = Join-Path (Join-Path $tmp 'vpn') 'Ev_Agi.conf'
Assert-True (Test-Path -LiteralPath $dst) 'vpn klasorune yazildi'
$bytes = [System.IO.File]::ReadAllBytes($dst)
Assert-True (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF)) 'BOM yok'
Assert-True (([System.IO.File]::ReadAllText($dst)) -notmatch '#') 'yorumlar silindi'
$imp2 = Import-WgConfFile $src
Assert-Eq $imp2.Name 'Ev_Agi-2' 'ayni ad ikinci kez numaralanir'
$imp3 = Import-WgConfFile $src
Assert-Eq $imp3.Name 'Ev_Agi-3' 'ucuncu'
$badSrc = Join-Path $tmp 'kotu.conf'
[System.IO.File]::WriteAllText($badSrc, $goodConf + "`nPostUp = calc.exe`n")
$thrown = ''; try { [void](Import-WgConfFile $badSrc) } catch { $thrown = $_.Exception.Message }
Assert-True ($thrown -match 'reddedildi') 'kotu dosya ice aktarilmaz'
Assert-True (-not (Test-Path -LiteralPath (Join-Path (Join-Path $tmp 'vpn') 'kotu.conf'))) 'kotu dosya yazilmadi'
$bigSrc = Join-Path $tmp 'buyuk.conf'
[System.IO.File]::WriteAllText($bigSrc, ('#' * 70000))
$thrown = ''; try { [void](Import-WgConfFile $bigSrc) } catch { $thrown = $_.Exception.Message }
Assert-True ($thrown -match '64 KB') 'cok buyuk dosya'
$thrown = ''; try { [void](Import-WgConfFile $tmp) } catch { $thrown = $_.Exception.Message }
Assert-True ($thrown -ne '') 'klasor ice aktarilmaz'

# ---- tunel listesi (hizmet durumu sahte) ----
$script:SvcStates = @{}
function Get-WgSvcState([string]$Name) { if ($script:SvcStates.ContainsKey($Name)) { return [string]$script:SvcStates[$Name] }; return '' }
function Get-Service { [CmdletBinding()] param([string]$Name) return @([pscustomobject]@{ Name = 'WireGuardTunnel$Disarida'; Status = 'Running' }) }
$script:SvcStates['Ev_Agi'] = 'Running'
$list = @(Get-WgTunnels)
Assert-Eq $list.Count 4 'uc kendi + bir dis tunel'
$mine = @($list | Where-Object { $_.Name -eq 'Ev_Agi' })[0]
Assert-True ($mine.Mine -and $mine.Up -and $mine.Endpoint -eq '203.0.113.10:51820') 'kendi tunel bilgisi'
$foreign = @($list | Where-Object { $_.Name -eq 'Disarida' })[0]
Assert-True ((-not $foreign.Mine) -and $foreign.Up) 'dis tunel listelenir'
$stopped = @($list | Where-Object { $_.Name -eq 'Ev_Agi-2' })[0]
Assert-True ((-not $stopped.Up) -and $stopped.State -eq '') 'calismayan tunel'
$noDir = $sync.DataDir; $sync.DataDir = Join-Path $tmp 'yok-klasor'
$l0 = @(Get-WgTunnels)
Assert-True (-not (Test-Path -LiteralPath (Join-Path $sync.DataDir 'vpn'))) 'okuma vpn klasoru olusturmaz'
$sync.DataDir = $noDir

# ---- baglan / kes / sil ----
$script:Proc = New-Object System.Collections.ArrayList
$script:ExeOk = $true
function Get-WgExe { if ($script:ExeOk) { return 'C:\Program Files\WireGuard\wireguard.exe' }; return '' }
function Start-Process { [CmdletBinding()] param([string]$FilePath, [string]$ArgumentList, [switch]$Wait, [switch]$PassThru, [string]$WindowStyle)
    [void]$script:Proc.Add(@{ Exe = $FilePath; Args = $ArgumentList })
    if ($ArgumentList -like '/installtunnelservice*') { $n = [System.IO.Path]::GetFileNameWithoutExtension(($ArgumentList -replace '^/installtunnelservice "', '' -replace '"$', '')); $script:SvcStates[$n] = 'Running' }
    if ($ArgumentList -like '/uninstalltunnelservice*') { $n = ($ArgumentList -replace '^/uninstalltunnelservice ', ''); [void]$script:SvcStates.Remove($n) }
    return [pscustomobject]@{ ExitCode = 0 } }
function Wait-WgState([string]$Name, [bool]$Running, [int]$Secs) { $st = Get-WgSvcState $Name; if ($Running) { return ($st -eq 'Running') }; return ($st -eq '') }
Import-Fn 'Start-WgTunnel','Stop-WgTunnel','Remove-WgConfig'
$script:Proc.Clear(); $script:SvcStates.Clear()
$did = Start-WgTunnel 'Ev_Agi'
Assert-True $did 'tunel baglandi'
Assert-Eq $script:Proc.Count 1 'tek komut'
Assert-True ($script:Proc[0].Args -match '^/installtunnelservice "[^"]+Ev_Agi\.conf"$') 'installtunnelservice bicimi'
Assert-Eq (Get-WgSvcState 'Ev_Agi') 'Running' 'hizmet calisiyor'
$did = Start-WgTunnel 'Ev_Agi'
Assert-True (-not $did) 'zaten bagliyken tekrar baglanmaz'
Assert-Eq $script:Proc.Count 1 'ek komut yok'
$did = Stop-WgTunnel 'Ev_Agi'
Assert-True $did 'tunel kesildi'
Assert-Eq $script:Proc[1].Args '/uninstalltunnelservice Ev_Agi' 'uninstalltunnelservice'
$did = Stop-WgTunnel 'Ev_Agi'
Assert-True (-not $did) 'olmayan hizmet kesilmez'
$thrown = ''; try { [void](Stop-WgTunnel 'a b; calc') } catch { $thrown = $_.Exception.Message }
Assert-True ($thrown -match 'Geçersiz') 'kesmede ad dogrulanir'
$thrown = ''; try { [void](Start-WgTunnel 'yok-olan') } catch { $thrown = $_.Exception.Message }
Assert-True ($thrown -match 'yok') 'olmayan yapilandirma'
$script:ExeOk = $false
$thrown = ''; try { [void](Start-WgTunnel 'Ev_Agi') } catch { $thrown = $_.Exception.Message }
Assert-True ($thrown -match 'kurulu değil') 'WireGuard yoksa hata'
$script:ExeOk = $true
# eski/bozuk yapilandirma baglanmaz
[System.IO.File]::WriteAllText((Join-Path (Join-Path $tmp 'vpn') 'bozuk.conf'), "[Interface]`nPostUp = x`n")
$thrown = ''; try { [void](Start-WgTunnel 'bozuk') } catch { $thrown = $_.Exception.Message }
Assert-True ($thrown -match 'geçersiz') 'bozuk yapilandirma baglanmaz'
# silme
$script:SvcStates['Ev_Agi-2'] = 'Running'
$script:Proc.Clear()
Remove-WgConfig 'Ev_Agi-2'
Assert-True (-not (Test-Path -LiteralPath (Join-Path (Join-Path $tmp 'vpn') 'Ev_Agi-2.conf'))) 'yapilandirma silindi'
Assert-True (($script:Proc | Where-Object { $_.Args -like '/uninstalltunnelservice*' }).Count -ge 1) 'silmeden once hizmet kaldirildi'

# ======================= 4) Windows VPN profilleri =======================
foreach ($n in @('VPN', 'Is VPN-1', 'a.b_c')) { Assert-True (Test-VpnProfileName $n) ('profil adi ' + $n) }
foreach ($n in @('', ' x', '-x', 'a"b', 'a;b', ('a' * 41), 'a|b')) { Assert-True (-not (Test-VpnProfileName $n)) ('gecersiz profil adi [' + $n + ']') }
foreach ($n in @('vpn.example.com', '203.0.113.5', '2001:db8::1')) { Assert-True (Test-VpnServerText $n) ('sunucu ' + $n) }
foreach ($n in @('', 'a b', 'a;b', '999.1.1.1', '-x.com', 'x..com;')) { Assert-True (-not (Test-VpnServerText $n)) ('gecersiz sunucu [' + $n + ']') }
$script:IkeCalls = New-Object System.Collections.ArrayList
$script:Conns = @()
function Get-VpnConnection { [CmdletBinding()] param([switch]$AllUserConnection)
    if ($AllUserConnection) { return @([pscustomobject]@{ Name = 'Sirket'; ServerAddress = 'gw.sirket.com'; TunnelType = 'Ikev2'; AuthenticationMethod = @('Eap'); EncryptionLevel = 'Required'; SplitTunneling = $false; ConnectionStatus = 'Connected' }, [pscustomobject]@{ Name = 'Ortak'; ServerAddress = 'a'; TunnelType = 'Ikev2'; AuthenticationMethod = @('Eap'); EncryptionLevel = 'Required'; SplitTunneling = $false; ConnectionStatus = 'Disconnected' }) }
    return @([pscustomobject]@{ Name = 'Ortak'; ServerAddress = 'a'; TunnelType = 'Ikev2'; AuthenticationMethod = @('MSChapv2'); EncryptionLevel = 'Required'; SplitTunneling = $true; ConnectionStatus = 'Disconnected' }) }
function Add-VpnConnection { [CmdletBinding()] param([string]$Name, [string]$ServerAddress, [string]$TunnelType, [string]$AuthenticationMethod, [string]$EncryptionLevel, [switch]$Force) [void]$script:IkeCalls.Add("add|$Name|$ServerAddress|$TunnelType|$AuthenticationMethod|$EncryptionLevel") }
function Set-VpnConnectionIPsecConfiguration { [CmdletBinding()] param([string]$ConnectionName, [string]$AuthenticationTransformConstants, [string]$CipherTransformConstants, [string]$EncryptionMethod, [string]$IntegrityCheckMethod, [string]$DHGroup, [string]$PfsGroup, [switch]$Force) [void]$script:IkeCalls.Add("ipsec|$ConnectionName|$CipherTransformConstants|$DHGroup|$PfsGroup") }
function Remove-VpnConnection { [CmdletBinding()] param([string]$Name, [switch]$AllUserConnection, [switch]$Force) [void]$script:IkeCalls.Add("del|$Name|$AllUserConnection") }
$pr = @(Get-WinVpnProfiles)
Assert-Eq $pr.Count 2 'iki profil (tekrar yok)'
$sirket = @($pr | Where-Object { $_.Name -eq 'Sirket' })[0]
Assert-True ($sirket.Connected -and $sirket.AllUser) 'tum kullanicilar profili bagli'
Assert-True (@($pr | Where-Object { $_.Name -eq 'Ortak' })[0].Split) 'kullanici profili once gelir'
Add-WinVpnProfile 'Yeni' 'vpn.example.com'
Assert-Eq $script:IkeCalls[0] 'add|Yeni|vpn.example.com|Ikev2|MSChapv2|Required' 'Add-VpnConnection parametreleri'
$thrown = ''; try { Add-WinVpnProfile 'Ortak' 'x.example.com' } catch { $thrown = $_.Exception.Message }
Assert-True ($thrown -match 'zaten var') 'ayni ad reddedilir'
$thrown = ''; try { Add-WinVpnProfile 'a;b' 'x.example.com' } catch { $thrown = $_.Exception.Message }
Assert-True ($thrown -match 'Profil adı') 'gecersiz ad reddedilir'
$thrown = ''; try { Add-WinVpnProfile 'Iyi' 'bad host' } catch { $thrown = $_.Exception.Message }
Assert-True ($thrown -match 'Sunucu') 'gecersiz sunucu reddedilir'
Set-WinVpnStrong 'Yeni'
Assert-Eq $script:IkeCalls[1] 'ipsec|Yeni|GCMAES128|Group14|PFS2048' 'guclu paket'
Remove-WinVpnProfile 'Yeni' $false; Remove-WinVpnProfile 'Sirket' $true
Assert-Eq $script:IkeCalls[2] 'del|Yeni|False' 'profil sil'
Assert-Eq $script:IkeCalls[3] 'del|Sirket|True' 'tum kullanicilar profil sil'
$thrown = ''; try { Remove-WinVpnProfile 'a"b' $false } catch { $thrown = $_.Exception.Message }
Assert-True ($thrown -match 'Geçersiz') 'silmede ad dogrulanir'
$thrown = ''; try { Connect-WinVpn 'a;b' } catch { $thrown = $_.Exception.Message }
Assert-True ($thrown -match 'Geçersiz') 'baglanmada ad dogrulanir'
$thrown = ''; try { Disconnect-WinVpn 'a|b' } catch { $thrown = $_.Exception.Message }
Assert-True ($thrown -match 'Geçersiz') 'kesmede ad dogrulanir'

# ---- etkin VPN algilama ----
function Get-WgTunnels { return @(@{ Name = 'Ev_Agi'; Mine = $true; Up = $true }, @{ Name = 'Durgun'; Mine = $true; Up = $false }) }
function Get-WinVpnProfiles { return @(@{ Name = 'Sirket'; Connected = $true; Server = 'gw.sirket.com' }, @{ Name = 'Ortak'; Connected = $false; Server = 'a' }) }
function Get-NetAdapter { [CmdletBinding()] param([switch]$Physical)
    return @([pscustomobject]@{ Name = 'Ethernet'; InterfaceDescription = 'Intel(R) Ethernet'; Status = 'Up' },
        [pscustomobject]@{ Name = 'Ev_Agi'; InterfaceDescription = 'WireGuard Tunnel'; Status = 'Up' },
        [pscustomobject]@{ Name = 'Mullvad'; InterfaceDescription = 'Mullvad Tunnel'; Status = 'Up' },
        [pscustomobject]@{ Name = 'OpenVPN TAP'; InterfaceDescription = 'TAP-Windows Adapter V9'; Status = 'Disconnected' },
        [pscustomobject]@{ Name = 'vEthernet'; InterfaceDescription = 'Hyper-V Virtual Ethernet'; Status = 'Up' }) }
$act = Get-VpnActive
Assert-Eq @($act.Wg).Count 1 'etkin wg'
Assert-Eq @($act.Ike).Count 1 'etkin ike'
Assert-Eq @($act.Other).Count 1 'baska istemci (yalniz Up olan, wg harici)'
Assert-Eq $act.Other[0].Name 'Mullvad' 'baska istemci adi'
Assert-True $act.Any 'any'
function Get-InstalledPrograms { return @(@{ Name = 'WireGuard'; Version = '0.5.3' }, @{ Name = 'Mullvad VPN'; Version = '2024.1' }, @{ Name = 'Protonmail Bridge'; Version = '1' }) }
$cl = @(Get-VpnClients)
Assert-Eq $cl.Count 6 'alti istemci'
Assert-True (@($cl | Where-Object { $_.Name -eq 'WireGuard' })[0].Installed) 'WireGuard kurulu'
Assert-True (@($cl | Where-Object { $_.Name -eq 'Mullvad VPN' })[0].Installed) 'Mullvad kurulu'
Assert-True (-not @($cl | Where-Object { $_.Name -eq 'Proton VPN' })[0].Installed) 'Proton Mail Proton VPN sayilmaz'
foreach ($d in $script:VpnClientDefs) { Assert-True ($d.Id -match '^[A-Za-z0-9][A-Za-z0-9\.\-_\+]*$') ('winget kimligi gecerli: ' + $d.Id) }

# ======================= 5) IPv4 aralik hesabi ve kill-switch kurallari =======================
Assert-Eq (ConvertTo-IpLong '1.2.3.4') 16909060 'ip -> long'
Assert-Eq (ConvertFrom-IpLong 16909060) '1.2.3.4' 'long -> ip'
Assert-Eq (ConvertFrom-IpLong 4294967295) '255.255.255.255' 'ust sinir'
Assert-Eq (ConvertFrom-IpLong 0) '0.0.0.0' 'alt sinir'
Assert-Eq ((Get-IpRangesExcept4 @('10.64.0.1')) -join ' ') '0.0.0.0-10.64.0.0 10.64.0.2-255.255.255.255' 'tek adres disi'
Assert-Eq ((Get-IpRangesExcept4 @()) -join ' ') '0.0.0.0-255.255.255.255' 'bos liste = hepsi'
Assert-Eq ((Get-IpRangesExcept4 @('1.1.1.1', '1.1.1.2')) -join ' ') '0.0.0.0-1.1.1.0 1.1.1.3-255.255.255.255' 'bitisik adresler'
Assert-Eq ((Get-IpRangesExcept4 @('0.0.0.0', '255.255.255.255')) -join ' ') '0.0.0.1-255.255.255.254' 'uc adresler'
Assert-Eq ((Get-IpRangesExcept4 @('9.9.9.9', '2606:4700:4700::1111', '9.9.9.9')) -join ' ') '0.0.0.0-9.9.9.8 9.9.9.10-255.255.255.255' 'v6 yok sayilir, tekrar tek'
Assert-Eq ((Get-IpRangesExcept4 @('8.8.8.8', '1.1.1.1')) -join ' ') '0.0.0.0-1.1.1.0 1.1.1.2-8.8.8.7 8.8.8.9-255.255.255.255' 'siralama'
function Test-InRanges([string]$Ip, $Ranges) {
    $v = ConvertTo-IpLong $Ip
    foreach ($r in $Ranges) {
        $p = ([string]$r) -split '-'
        $a = ConvertTo-IpLong $p[0]; $b = $a; if ($p.Count -gt 1) { $b = ConvertTo-IpLong $p[1] }
        if ($v -ge $a -and $v -le $b) { return $true }
    }
    return $false
}
$rg = Get-IpRangesExcept4 @('10.64.0.1', '203.0.113.10')
Assert-True (-not (Test-InRanges '10.64.0.1' $rg)) 'dns araliga girmez'
Assert-True (-not (Test-InRanges '203.0.113.10' $rg)) 'endpoint araliga girmez'
Assert-True (Test-InRanges '192.168.1.1' $rg) 'yerel dns araliga girer'
Assert-True (Test-InRanges '8.8.8.8' $rg) 'genel dns araliga girer'
Assert-True (Test-InRanges '10.64.0.2' $rg) 'komsu adres araliga girer'

$ctx = @{ Endpoints = @('203.0.113.10'); TunnelAddrs = @('10.64.0.2', 'fd00::2'); Alias = 'Ev_Agi'; Dns = @('10.64.0.1'); AllowLan = $true }
$sp = @(New-KsRuleSpecs $ctx)
$ids = ($sp | ForEach-Object { $_.Id }) -join ','
Assert-Eq $ids 'endpoint,tunnel,ras,alias,lan,dhcp4,dhcp6,dns4-udp,dns4-tcp,dns6-udp,dns6-tcp' 'kural kimlikleri ve sirasi'
Assert-True (@($sp | Where-Object { $_.Id -eq 'alias' })[0].Opt) 'alias kurali istege bagli'
Assert-True (-not @($sp | Where-Object { $_.Id -eq 'endpoint' })[0].Opt) 'endpoint kurali zorunlu'
foreach ($s in $sp) { Assert-True (@('Allow', 'Block') -contains $s.P.Action) ('eylem ' + $s.Id); Assert-Eq $s.P.Direction 'Outbound' ('yon ' + $s.Id) }
$d4 = @($sp | Where-Object { $_.Id -eq 'dns4-udp' })[0]
Assert-Eq $d4.P.Action 'Block' 'dns kurali engelleme'
Assert-True (-not (Test-InRanges '10.64.0.1' $d4.P.RemoteAddress)) 'tunel dns engel disinda'
Assert-True (-not (Test-InRanges '203.0.113.10' $d4.P.RemoteAddress)) 'endpoint engel disinda'
Assert-True (Test-InRanges '192.168.1.1' $d4.P.RemoteAddress) 'yerel dns engelli'
Assert-Eq (@($d4.P.RemotePort) -join ',') '53,853' 'dns portlari'
$ctx2 = @{ Endpoints = @('203.0.113.10'); TunnelAddrs = @(); Alias = ''; Dns = @(); AllowLan = $false }
$sp2 = @(New-KsRuleSpecs $ctx2)
Assert-Eq (($sp2 | ForEach-Object { $_.Id }) -join ',') 'endpoint,ras,dhcp4,dhcp6' 'dns yok, lan yok, alias yok'
$ctx3 = @{ Endpoints = @('2001:db8::1'); TunnelAddrs = @('10.0.0.2'); Alias = 'x'; Dns = @('10.0.0.1'); AllowLan = $true }
Assert-True (-not (@(New-KsRuleSpecs $ctx3) | Where-Object { $_.Id -like 'dns6*' })) 'v6 endpoint varken v6 dns engeli eklenmez'
$ctx4 = @{ Endpoints = @('198.51.100.7'); TunnelAddrs = @('10.0.0.2'); Alias = 'x'; Dns = @('198.51.100.7'); AllowLan = $true }
$d44 = @(New-KsRuleSpecs $ctx4 | Where-Object { $_.Id -eq 'dns4-tcp' })[0]
Assert-True (-not (Test-InRanges '198.51.100.7' $d44.P.RemoteAddress)) 'dns = endpoint durumu'
Assert-True (@(New-KsRuleSpecs $ctx | Where-Object { $_.Id -eq 'lan' })[0].P.RemoteAddress -contains 'LocalSubnet') 'yerel ag anahtar sozcugu'
$stp = New-KsStep @{ Kind = 'wg'; Name = 'Ev_Agi'; Alias = 'Ev_Agi'; Endpoints = @('1.2.3.4'); TunnelAddrs = @('10.0.0.2'); Dns = @('10.0.0.1'); AllowLan = $true } $true
Assert-True ($stp.Ops[0].T -eq 'KillSwitch' -and $stp.Ops[0].On -eq $true -and $stp.Ops[0].Endpoints[0] -eq '1.2.3.4') 'adim kurulur'
Assert-True ((New-KsStep @{} $false).Ops[0].On -eq $false) 'kapatma adimi'

# ---- sahte guvenlik duvari ----
$script:Fw = @{}
$script:Prof = @{ Domain = 'Allow'; Private = 'Allow'; Public = 'Allow' }
$script:ProfEnabled = @{ Domain = 'True'; Private = 'True'; Public = 'True' }
$script:FailOn = ''
function New-NetFirewallRule { [CmdletBinding()] param([string]$Name, [string]$DisplayName, [string]$Group, [string]$Profile, [string]$Enabled, [string]$Direction, [string]$Action, [string[]]$RemoteAddress, [string[]]$LocalAddress, [string]$InterfaceType, [string[]]$InterfaceAlias, [string]$Protocol, [string[]]$LocalPort, [string[]]$RemotePort)
    if ($script:FailOn -ne '' -and $Name -like ('*' + $script:FailOn)) { Write-Error 'kural eklenemedi'; return }
    $script:Fw[$Name] = [pscustomobject]@{ Name = $Name; Group = $Group; Action = $Action; Direction = $Direction } }
function Get-NetFirewallRule { [CmdletBinding()] param([string]$Group) $r = @($script:Fw.Values | Where-Object { $_.Group -eq $Group }); if ($r.Count -eq 0) { Write-Error 'yok'; return }; return $r }
function Remove-NetFirewallRule { [CmdletBinding()] param([string]$Group, [string]$Name)
    if ($Group -ne '') { foreach ($k in @($script:Fw.Keys)) { if ($script:Fw[$k].Group -eq $Group) { [void]$script:Fw.Remove($k) } } }
    if ($Name -ne '') { foreach ($k in @($script:Fw.Keys)) { if ($k -like $Name) { [void]$script:Fw.Remove($k) } } } }
function Get-NetFirewallProfile { [CmdletBinding()] param() return @($script:Prof.Keys | ForEach-Object { [pscustomobject]@{ Name = $_; Enabled = $script:ProfEnabled[$_]; DefaultOutboundAction = $script:Prof[$_] } }) }
function Set-NetFirewallProfile { [CmdletBinding()] param([string]$Name, [string]$DefaultOutboundAction, [string]$DefaultInboundAction) $script:Prof[$Name] = $DefaultOutboundAction }
Import-Fn 'Get-KsState','Test-KsPreconditions','Restore-KsState','Disable-KillSwitchNow'

# ayar dosyasi
Save-Settings (Get-DefaultSettings)
Assert-True (-not (Get-KsState).On) 'baslangicta kapali'
$op = @{ T = 'KillSwitch'; On = $true; Kind = 'wg'; Name = 'Ev_Agi'; Alias = 'Ev_Agi'; Endpoints = @('203.0.113.10'); TunnelAddrs = @('10.64.0.2'); Dns = @('10.64.0.1'); AllowLan = $true }

# onizleme
Reset-Counters; $script:Preview = $true
Invoke-KillSwitchOp $op
$script:Preview = $false
Assert-Eq $script:Fw.Count 0 'onizleme kural eklemez'
Assert-True ($script:Prof.Values -notcontains 'Block') 'onizleme profili degistirmez'
Assert-True ($script:Changes -ge 1) 'onizleme plan satiri'
Assert-Eq $script:Jrnl.Count 0 'onizleme gunluk yazmaz'

# gercek uygulama
Reset-Counters
Invoke-KillSwitchOp $op
Assert-Eq $script:Fw.Count 11 'on bir kural'
Assert-True (@($script:Fw.Values | Where-Object { $_.Group -eq $script:FwKsGroup }).Count -eq 11) 'hepsi kill-switch grubunda'
Assert-Eq (($script:Prof.Values | Where-Object { $_ -eq 'Block' }).Count) 3 'uc profil Block'
$s = Get-Settings
Assert-True ($s.KillSwitch -eq $true) 'ayar: acik'
Assert-Eq (Get-JsonProp $s.KillSwitchPrev 'Public') 'Allow' 'eski deger kaydedildi'
Assert-Eq $script:Jrnl.Count 1 'gunluk kaydi'
Assert-Eq $script:Jrnl[0].T 'KillSwitch' 'gunluk turu'
$st = Get-KsState
Assert-True ($st.On -and $st.Effective -and $st.Rules -eq 11) 'durum etkin'

# yeniden uygulama: eski deger korunur
$script:Prof['Private'] = 'Block'
Reset-Counters
Invoke-KillSwitchOp $op
$s = Get-Settings
Assert-Eq (Get-JsonProp $s.KillSwitchPrev 'Private') 'Allow' 'yeniden uygulamada ilk eski deger korunur'
Assert-Eq $script:Fw.Count 11 'kurallar cogalmaz'

# kapatma
Reset-Counters
Disable-KillSwitchNow
Assert-Eq $script:Fw.Count 0 'kurallar silindi'
Assert-True ($script:Prof.Values -notcontains 'Block') 'profiller geri yuklendi'
$s = Get-Settings
Assert-True ($s.KillSwitch -eq $false) 'ayar: kapali'
Assert-True (-not (Get-KsState).On) 'durum kapali'
# kapaliyken cagrilirsa kullanicinin kendi Block ayarina dokunmaz
$script:Prof['Public'] = 'Block'
Disable-KillSwitchNow
Assert-Eq $script:Prof['Public'] 'Block' 'kullanicinin kendi Block ayari korunur'
$script:Prof['Public'] = 'Allow'
# kapat islemi
Reset-Counters
Invoke-KillSwitchOp @{ T = 'KillSwitch'; On = $false }
Assert-Eq $script:Skipped 1 'kapaliyken kapat atlanir'
# onceden Block olan profil geri yuklenirken Block kalir
$script:Prof['Domain'] = 'Block'
Reset-Counters
Invoke-KillSwitchOp $op
Disable-KillSwitchNow
Assert-Eq $script:Prof['Domain'] 'Block' 'onceden Block olan profil Block kalir'
Assert-Eq $script:Prof['Public'] 'Allow' 'digerleri Allow'
$script:Prof['Domain'] = 'Allow'
# acik iken kapat islemi
Reset-Counters
Invoke-KillSwitchOp $op
Reset-Counters
Invoke-KillSwitchOp @{ T = 'KillSwitch'; On = $false }
Assert-True ($script:Changes -ge 1 -and $script:Fw.Count -eq 0) 'kapat islemi kurallari siler'

# geri alma kaydi
Reset-Counters
Invoke-KillSwitchOp $op
$jr = $script:Jrnl[0]
Undo-KillSwitchItem ([pscustomobject]@{ T = 'KillSwitch'; Prev = [pscustomobject]@{ Domain = 'Allow'; Private = 'Allow'; Public = 'Allow' } })
Assert-True ($script:Fw.Count -eq 0 -and $script:Prof.Values -notcontains 'Block') 'gunluk geri alma'
Assert-True ((Get-Settings).KillSwitch -eq $false) 'geri alma ayari'

# ara adimda hata -> tamamen geri alinir
$script:FailOn = 'ras'
Reset-Counters
$thrown = ''; try { Invoke-KillSwitchOp $op } catch { $thrown = $_.Exception.Message }
Assert-True ($thrown -match 'geri dönüldü|eski duruma') 'zorunlu kural hatasi atilir'
Assert-Eq $script:Fw.Count 0 'hata sonrasi kural kalmaz'
Assert-True ($script:Prof.Values -notcontains 'Block') 'hata sonrasi profil Block degil'
Assert-True ((Get-Settings).KillSwitch -ne $true) 'hata sonrasi ayar acik degil'
# istege bagli kural hatasi gormezden gelinir
$script:FailOn = 'alias'
Reset-Counters
Invoke-KillSwitchOp $op
Assert-Eq $script:Fw.Count 10 'alias kurali eklenemedi ama kalan kurulu'
Assert-True ((Get-KsState).Effective) 'alias olmadan da etkin'
Disable-KillSwitchNow
$script:FailOn = ''

# on kosullar
Reset-Counters
Invoke-KillSwitchOp @{ T = 'KillSwitch'; On = $true; Kind = 'wg'; Name = 'x'; Alias = 'x'; Endpoints = @(); TunnelAddrs = @('10.0.0.2'); Dns = @(); AllowLan = $true }
Assert-True ($script:Skipped -eq 1 -and $script:Fw.Count -eq 0) 'endpoint yoksa kurulmaz'
$script:ProfEnabled['Public'] = 'False'
Reset-Counters
Invoke-KillSwitchOp $op
Assert-True ($script:Skipped -eq 1 -and $script:Fw.Count -eq 0 -and $script:Prof.Values -notcontains 'Block') 'guvenlik duvari kapaliyken kurulmaz'
$script:ProfEnabled['Public'] = 'True'

# ---- baglam ----
$confDir = Join-Path $tmp 'vpn'
Copy-Item (Join-Path $confDir 'Ev_Agi.conf') (Join-Path $confDir 'Aktif.conf')
function Get-DnsClientServerAddress { [CmdletBinding()] param([string]$InterfaceAlias, [int]$InterfaceIndex, [string]$AddressFamily)
    if ($InterfaceAlias -eq 'Aktif') { return @([pscustomobject]@{ ServerAddresses = @('10.64.0.1', 'fe80::1', 'bozuk') }) }
    if ($InterfaceAlias -eq 'Sirket') { return @([pscustomobject]@{ ServerAddresses = @('172.16.0.53') }) }
    return @() }
function Get-NetIPAddress { [CmdletBinding()] param([string]$InterfaceAlias, [string]$AddressFamily)
    if ($InterfaceAlias -eq 'Sirket') { return @([pscustomobject]@{ IPAddress = '172.16.9.9' }, [pscustomobject]@{ IPAddress = 'fe80::5%9' }) }
    return @() }
$script:Hosts = @{ 'gw.sirket.com' = @('198.51.100.20', '198.51.100.21') }
function Resolve-VpnHostIps([string]$HostName) { if ((Get-VpnIpKind $HostName) -ne 0) { return @($HostName) }; if ($script:Hosts.ContainsKey($HostName)) { return $script:Hosts[$HostName] }; return @() }
$a1 = @{ Wg = @(@{ Name = 'Aktif'; Mine = $true; Up = $true }); Ike = @(); Other = @(); Any = $true }
$k = Get-KsContext $a1 $true
Assert-True $k.Ok ('wg baglami: ' + $k.Why)
Assert-Eq $k.Kind 'wg' 'tur'
Assert-Eq (@($k.Endpoints) -join ',') '203.0.113.10' 'endpoint'
Assert-Eq (@($k.TunnelAddrs) -join ',') '10.64.0.2,fd00::2' 'tunel adresleri (yapilandirmadan)'
Assert-Eq (@($k.Dns) -join ',') '10.64.0.1' 'dns: link-local ve bozuk elenir'
Assert-True ($k.AllowLan -eq $true) 'yerel ag izni'
$k = Get-KsContext $a1 $false
Assert-True ($k.AllowLan -eq $false) 'yerel ag izni kapali'
$a2 = @{ Wg = @(@{ Name = 'Disarida'; Mine = $false; Up = $true }); Ike = @(); Other = @(); Any = $true }
$k = Get-KsContext $a2 $true
Assert-True ((-not $k.Ok) -and $k.Why -match 'içe aktarılmamış') 'dis wg tunel icin kurulmaz'
$a3 = @{ Wg = @(); Ike = @(@{ Name = 'Sirket'; Server = 'gw.sirket.com'; Connected = $true }); Other = @(); Any = $true }
$k = Get-KsContext $a3 $true
Assert-True $k.Ok 'ike baglami'
Assert-Eq (@($k.Endpoints) -join ',') '198.51.100.20,198.51.100.21' 'ike sunucu adresleri cozulur'
Assert-Eq (@($k.TunnelAddrs) -join ',') '172.16.9.9' 'ike tunel adresi (link-local elenir)'
Assert-Eq (@($k.Dns) -join ',') '172.16.0.53' 'ike dns'
$a4 = @{ Wg = @(); Ike = @(); Other = @(@{ Name = 'Mullvad'; Desc = 'Mullvad Tunnel' }); Any = $true }
$k = Get-KsContext $a4 $true
Assert-True ((-not $k.Ok) -and $k.Why -match 'Mullvad') 'baska istemci varken kurulmaz'
$a5 = @{ Wg = @(); Ike = @(); Other = @(); Any = $false }
$k = Get-KsContext $a5 $true
Assert-True ((-not $k.Ok) -and $k.Why -match 'Etkin bir VPN') 'VPN yokken kurulmaz'
Assert-Eq (@(Get-TunnelDns 'Yok' @('1.1.1.1', 'x')) -join ',') '1.1.1.1' 'dns yedek listesi'

# ---- dogrulama isi (otomatik geri alma) ----
$script:Conn = @{ Tcp = $true; Dns = $true }
function Test-KsConnectivity { return $script:Conn }
Import-Fn 'Job_KsVerify'
Invoke-KillSwitchOp $op
$r = Job_KsVerify @{}
Assert-True ($r.Ok -and -not $r.Reverted) 'dogrulama basarili'
Assert-True ((Get-KsState).Effective) 'basarili dogrulamada kill-switch acik kalir'
$script:Conn = @{ Tcp = $false; Dns = $false }
$r = Job_KsVerify @{}
Assert-True ((-not $r.Ok) -and $r.Reverted) 'dogrulama basarisiz: geri alinir'
Assert-True ($r.Why -match 'İnternet') 'neden: internet'
Assert-True ((-not (Get-KsState).On) -and $script:Prof.Values -notcontains 'Block') 'geri alma sonucu eski durum'
Invoke-KillSwitchOp $op
$script:Conn = @{ Tcp = $true; Dns = $false }
$r = Job_KsVerify @{}
Assert-True ($r.Reverted -and $r.Why -match 'Ad çözümleme') 'neden: dns'
Assert-True (-not (Get-KsState).On) 'dns hatasinda da geri alinir'
Assert-Eq (Invoke-KsOffAction @{}) $null 'KsOff eylemi'

# ======================= 6) DoH =======================
$script:Build = 22621
function Get-OsBuildNumber { return $script:Build }
function Add-DnsClientDohServerAddress { [CmdletBinding()] param([string]$ServerAddress, [string]$DohTemplate, [bool]$AutoUpgrade, [bool]$AllowFallbackToUdp) $script:Doh[$ServerAddress] = [pscustomobject]@{ ServerAddress = $ServerAddress; DohTemplate = $DohTemplate; AutoUpgrade = $AutoUpgrade; AllowFallbackToUdp = $AllowFallbackToUdp }; [void]$script:DohLog.Add("add|$ServerAddress") }
function Set-DnsClientDohServerAddress { [CmdletBinding()] param([string]$ServerAddress, [string]$DohTemplate, [bool]$AutoUpgrade, [bool]$AllowFallbackToUdp) $script:Doh[$ServerAddress] = [pscustomobject]@{ ServerAddress = $ServerAddress; DohTemplate = $DohTemplate; AutoUpgrade = $AutoUpgrade; AllowFallbackToUdp = $AllowFallbackToUdp }; [void]$script:DohLog.Add("set|$ServerAddress|$AutoUpgrade") }
function Remove-DnsClientDohServerAddress { [CmdletBinding()] param([string]$ServerAddress) [void]$script:Doh.Remove($ServerAddress); [void]$script:DohLog.Add("rm|$ServerAddress") }
function Get-DnsClientDohServerAddress { [CmdletBinding()] param() return @($script:Doh.Values) }
$script:DohLog = New-Object System.Collections.ArrayList
$script:Doh = @{
    '1.1.1.1' = [pscustomobject]@{ ServerAddress = '1.1.1.1'; DohTemplate = 'https://cloudflare-dns.com/dns-query'; AutoUpgrade = $false; AllowFallbackToUdp = $false }
    '1.0.0.1' = [pscustomobject]@{ ServerAddress = '1.0.0.1'; DohTemplate = 'https://cloudflare-dns.com/dns-query'; AutoUpgrade = $false; AllowFallbackToUdp = $false }
    '8.8.8.8' = [pscustomobject]@{ ServerAddress = '8.8.8.8'; DohTemplate = 'https://dns.google/dns-query'; AutoUpgrade = $true; AllowFallbackToUdp = $false }
}
Assert-True (Test-DohSupported) 'Windows 11 desteklenir'
$script:Build = 19045
Assert-True (-not (Test-DohSupported)) 'Windows 10 desteklenmez'
Reset-Counters
Invoke-DohRegOp @{ T = 'DohReg'; Provider = 'cloudflare' }
Assert-Eq $script:Skipped 1 'Win10 da atlanir'
Assert-Eq $script:DohLog.Count 0 'Win10 da komut yok'
$script:Build = 22621
Reset-Counters; $script:Preview = $true
Invoke-DohRegOp @{ T = 'DohReg'; Provider = 'cloudflare' }
$script:Preview = $false
Assert-Eq $script:DohLog.Count 0 'onizleme degistirmez'
Reset-Counters
Invoke-DohRegOp @{ T = 'DohReg'; Provider = 'cloudflare' }
Assert-True ($script:Doh['1.1.1.1'].AutoUpgrade -and $script:Doh['1.0.0.1'].AutoUpgrade) 'var olan kayitlar guncellendi'
Assert-True ($script:Doh.ContainsKey('2606:4700:4700::1111') -and $script:Doh['2606:4700:4700::1111'].AutoUpgrade) 'v6 kayitlar eklendi'
Assert-True ($script:Doh['1.1.1.1'].AllowFallbackToUdp) 'duz DNS yedegi acik'
Assert-Eq $script:Jrnl[0].T 'DohReg' 'gunluk'
Assert-Eq @($script:Jrnl[0].Added).Count 2 'iki yeni kayit'
Assert-Eq @($script:Jrnl[0].Changed).Count 2 'iki degisen kayit'
$jr = $script:Jrnl[0]
Reset-Counters
Invoke-DohRegOp @{ T = 'DohReg'; Provider = 'cloudflare' }
Assert-Eq $script:Skipped 1 'zaten kayitliyken atlanir'
Undo-DohRegItem $jr
Assert-True (-not $script:Doh.ContainsKey('2606:4700:4700::1111')) 'geri alma: eklenenler silindi'
Assert-True (-not $script:Doh['1.1.1.1'].AutoUpgrade) 'geri alma: eski deger'
Assert-True ($script:Doh['8.8.8.8'].AutoUpgrade) 'dokunulmayan kayit'
# kapatma
Reset-Counters
Invoke-DohRegOp @{ T = 'DohReg'; Provider = 'off' }
Assert-True (-not $script:Doh['8.8.8.8'].AutoUpgrade) 'kapatinca AutoUpgrade false'
Assert-True ($script:Doh.ContainsKey('8.8.8.8')) 'kayit silinmez'
Reset-Counters
Invoke-DohRegOp @{ T = 'DohReg'; Provider = 'off' }
Assert-Eq $script:Skipped 1 'zaten kapaliyken atlanir'
Reset-Counters
Invoke-DohRegOp @{ T = 'DohReg'; Provider = 'bilinmeyen' }
Assert-Eq $script:Skipped 1 'bilinmeyen saglayici'
foreach ($k2 in $script:DohProviders.Keys) {
    $p = $script:DohProviders[$k2]
    Assert-True ($p.Tpl -match '^https://[a-z0-9.\-]+/dns-query$') ('sablon ' + $k2)
    foreach ($ip in $p.Ips) { Assert-True ((Get-VpnIpKind $ip) -ne 0) ('doh adresi ' + $ip) }
}
# durum
function Get-NetAdapter { [CmdletBinding()] param([switch]$Physical) return @([pscustomobject]@{ Name = 'Ethernet'; Status = 'Up'; ifIndex = 3 }) }
$script:DnsNow = @('1.1.1.1', '1.0.0.1')
function Get-DnsClientServerAddress { [CmdletBinding()] param([string]$InterfaceAlias, [int]$InterfaceIndex, [string]$AddressFamily) return @([pscustomobject]@{ ServerAddresses = $script:DnsNow }) }
$ds = Get-DohState
Assert-True ($ds.Supported -and -not $ds.Active) 'doh kapali durumu'
Invoke-DohRegOp @{ T = 'DohReg'; Provider = 'cloudflare' }
$ds = Get-DohState
Assert-True ($ds.Active -and $ds.Provider -eq 'Cloudflare') 'doh acik durumu'
$script:DnsNow = @('1.1.1.1', '192.168.1.1')
Assert-True (-not (Get-DohState).Active) 'bir sunucu kapsanmiyorsa etkin degil'
# adimlar
$ad = @(@{ Index = 3; Name = 'Ethernet' })
$st = @(New-DohSteps 'quad9' $ad)
Assert-Eq $st.Count 2 'quad9: doh + dns adimi'
Assert-Eq $st[0].Ops[0].T 'DohReg' 'ilk adim doh'
Assert-Eq $st[1].Ops[0].T 'Dns' 'ikinci adim dns'
Assert-Eq (@($st[1].Ops[0].Servers) -join ',') '9.9.9.9,149.112.112.112' 'dns yalniz v4'
$st = @(New-DohSteps 'off' $ad)
Assert-True ($st.Count -eq 1 -and $st[0].Ops[0].Provider -eq 'off') 'kapatma adimi'
Assert-Eq @(New-DohSteps 'x' $ad).Count 0 'bilinmeyen saglayici adim uretmez'
$sn = New-SmartNameStep
Assert-True ($sn.Ops[0].T -eq 'Reg' -and $sn.Ops[0].Name -eq 'DisableSmartNameResolution' -and $sn.Ops[0].Value -eq 1) 'akilli ad cozumleme adimi'

# ======================= 7) sizinti denetimi =======================
$tr = ConvertFrom-CfTrace "fl=1f1`nh=www.cloudflare.com`nip=203.0.113.77`nts=1`nvisit_scheme=https`nuag=x`ncolo=IST`nsliver=none`nhttp=http/2`nloc=TR`ntls=TLSv1.3`nwarp=off`ngateway=off"
Assert-True ($tr.Ok -and $tr.Ip -eq '203.0.113.77' -and $tr.Loc -eq 'TR' -and $tr.Warp -eq 'off' -and $tr.Colo -eq 'IST') 'trace cozumlenir'
$tr = ConvertFrom-CfTrace "ip=<script>`nloc=<b>x`nwarp=evil`ncolo=toolongcolo"
Assert-True ((-not $tr.Ok) -and $tr.Loc -eq '' -and $tr.Warp -eq '' -and $tr.Colo -eq '') 'trace alanlari dogrulanir'
$tr = ConvertFrom-CfTrace "ip=2001:db8::5`nloc=de"
Assert-True ($tr.Ok -and $tr.Ip -eq '2001:db8::5' -and $tr.Loc -eq 'DE') 'v6 trace'
Assert-True (-not (ConvertFrom-CfTrace '').Ok) 'bos trace'
Assert-Eq (Get-ShortHash '1.2.3.4') (Get-ShortHash '1.2.3.4') 'ozet kararli'
Assert-True ((Get-ShortHash '1.2.3.4') -ne (Get-ShortHash '1.2.3.5')) 'ozet ayirir'
Assert-Eq (Get-ShortHash 'x').Length 16 'ozet 16 karakter'
$t4 = @{ Ok = $true; Ip = '203.0.113.77'; Loc = 'TR'; Warp = 'off' }
$base = Get-ShortHash '198.51.100.9'
$same = Get-ShortHash '203.0.113.77'
function Status-Of($rows, [string]$Like) { return (@($rows | Where-Object { $_.Title -like $Like }) | ForEach-Object { $_.Status }) -join ',' }
$rows = New-LeakReport $t4 $true $base $null @() $false
Assert-Eq (Status-Of $rows 'Adresiniz VPN kapalıyken ölçülenden farklı*') 'ok' 'adres farkli = ok'
$rows = New-LeakReport $t4 $true $same $null @() $false
Assert-Eq (Status-Of $rows 'Adresiniz VPN kapalıyken ölçülenle aynı*') 'bad' 'adres ayni = kotu'
$rows = New-LeakReport $t4 $true '' $null @() $false
Assert-Eq (Status-Of $rows 'Karşılaştırma için*') 'info' 'taban yok = bilgi'
$rows = New-LeakReport $t4 $false '' $null @() $false
Assert-Eq (Status-Of $rows 'VPN etkin değil') 'info' 'VPN yok'
Assert-True (@($rows).Count -eq 2) 'VPN yokken yalniz iki satir'
$rows = New-LeakReport $t4 $true $base @{ Ok = $true; Ip = '2001:db8::5' } @() $false
Assert-Eq (Status-Of $rows 'IPv6 trafiği tünel dışından*') 'bad' 'ipv6 sizintisi'
$rows = New-LeakReport $t4 $true $base @{ Ok = $false } @() $false
Assert-Eq (Status-Of $rows 'IPv6 sızıntısı bulunmadı') 'ok' 'ipv6 yok'
$rows = New-LeakReport $t4 $true $base $null @('192.168.1.1') $false
Assert-Eq (Status-Of $rows 'Tünel dışındaki bağdaştırıcılarda DNS*') 'warn' 'fiziksel dns uyarisi'
$rows = New-LeakReport $t4 $true $base $null @('192.168.1.1') $true
Assert-Eq (Status-Of $rows 'Tünel dışı DNS sorguları kill-switch ile engelli') 'ok' 'kill-switch varken dns ok'
$rows = New-LeakReport $t4 $true $base $null @() $false
Assert-Eq (Status-Of $rows 'Tünel dışında tanımlı DNS sunucusu yok') 'ok' 'dns yok'
$rows = New-LeakReport @{ Ok = $true; Ip = '203.0.113.77'; Loc = ''; Warp = 'on' } $true $base $null @() $false
Assert-Eq (Status-Of $rows 'Cloudflare WARP*') 'info' 'warp bilgisi'

# is: sizinti sinamasi
$script:Http = "ip=203.0.113.77`nloc=TR`nwarp=off`ncolo=IST"
$script:HttpUrls = New-Object System.Collections.ArrayList
$script:HttpFail = $false
function Invoke-VpnHttp([string]$Url, [int]$TimeoutMs) { [void]$script:HttpUrls.Add($Url); if ($script:HttpFail) { throw 'baglanti yok' }; if ($Url -like '*2606*') { throw 'ipv6 yok' }; return $script:Http }
function Test-HasGlobalIpv6 { return $true }
function Get-PhysicalDnsServers($a) { return @() }
$script:ActNow = @{ Wg = @(); Ike = @(); Other = @(); Any = $false }
function Get-VpnActive { return $script:ActNow }
Import-Fn 'Job_LeakTest'
Save-Settings (Get-DefaultSettings)
$r = Job_LeakTest @{}
Assert-True ($r.Ok -and $r.Ip -eq '203.0.113.77' -and -not $r.Vpn) 'VPN yok: sinama'
Assert-Eq $script:HttpUrls.Count 1 'VPN yokken tek istek'
Assert-Eq $script:HttpUrls[0] 'https://www.cloudflare.com/cdn-cgi/trace' 'adres'
Assert-Eq (Get-Settings).VpnBaseHash (Get-ShortHash '203.0.113.77') 'taban ozet kaydedildi'
Assert-True (-not ((Get-Content -LiteralPath $sync.SettingsFile -Raw) -match '203\.0\.113\.77')) 'ayar dosyasinda ham adres yok'
$script:ActNow = @{ Wg = @(@{ Name = 'Ev_Agi'; Mine = $true; Up = $true }); Ike = @(); Other = @(); Any = $true }
$script:Http = "ip=198.51.100.200`nloc=NL"
$script:HttpUrls.Clear()
$r = Job_LeakTest @{}
Assert-True ($r.Ok -and $r.Vpn) 'VPN var: sinama'
Assert-Eq $script:HttpUrls.Count 2 'VPN + v6 varsa iki istek'
Assert-Eq (Status-Of $r.Rows 'Adresiniz VPN kapalıyken ölçülenden farklı*') 'ok' 'farkli adres'
Assert-Eq (Get-Settings).VpnBaseHash (Get-ShortHash '203.0.113.77') 'VPN varken taban ozet degismez'
$script:Http = "ip=203.0.113.77`nloc=TR"
$r = Job_LeakTest @{}
Assert-Eq (Status-Of $r.Rows 'Adresiniz VPN kapalıyken ölçülenle aynı*') 'bad' 'ayni adres tespit edilir'
$script:HttpFail = $true
$r = Job_LeakTest @{}
Assert-True ((-not $r.Ok) -and $r.Why -match 'baglanti') 'ag hatasi'
$script:HttpFail = $false

# ======================= 8) VPN eylemleri ve saglik denetimi =======================
function Get-WgSvcState([string]$Name) { if ($script:SvcStates.ContainsKey($Name)) { return [string]$script:SvcStates[$Name] }; return '' }
Import-Fn 'Import-WgConfFile','Job_VpnAction'
$script:SvcStates.Clear()
$r = Job_VpnAction @{ Op = 'WgImport'; Path = $src }
Assert-True ($r.Ok -and $r.Name -like 'Ev_Agi*') 'WgImport'
$r = Job_VpnAction @{ Op = 'WgImport'; Path = $badSrc }
Assert-True ((-not $r.Ok) -and $r.Msg -match 'reddedildi') 'WgImport kotu dosya'
$r = Job_VpnAction @{ Op = 'WgImport'; Path = (Join-Path $tmp 'yok.conf') }
Assert-True (-not $r.Ok) 'WgImport olmayan dosya'
$r = Job_VpnAction @{ Op = 'Bilinmeyen'; Name = 'x' }
Assert-True ((-not $r.Ok) -and $r.Msg -match 'Bilinmeyen') 'bilinmeyen islem'
Invoke-KillSwitchOp $op
$r = Job_VpnAction @{ Op = 'WgUp'; Name = 'Ev_Agi' }
Assert-True ((-not $r.Ok) -and $r.Msg -match 'kill-switch') 'kill-switch aciksa tunel degistirilmez'
$r = Job_VpnAction @{ Op = 'IkeUp'; Name = 'Sirket' }
Assert-True ((-not $r.Ok) -and $r.Msg -match 'kill-switch') 'kill-switch aciksa yeni baglanti kurulmaz'
Disable-KillSwitchNow
$script:Proc.Clear()
$r = Job_VpnAction @{ Op = 'WgUp'; Name = 'Ev_Agi' }
Assert-True $r.Ok 'WgUp'
$r = Job_VpnAction @{ Op = 'WgDown'; Name = 'Ev_Agi' }
Assert-True ($r.Ok -and $r.Msg -match 'kesildi') 'WgDown'
$r = Job_VpnAction @{ Op = 'IkeAdd'; Name = 'Ofis'; Server = 'vpn.ofis.com' }
Assert-True $r.Ok 'IkeAdd'
$r = Job_VpnAction @{ Op = 'IkeAdd'; Name = 'Ofis;'; Server = 'vpn.ofis.com' }
Assert-True (-not $r.Ok) 'IkeAdd gecersiz ad'

# saglik denetimi
function Status-Ids { return (($script:Findings | ForEach-Object { $_.Id }) -join ',') }
$script:Findings.Clear()
$script:ActNow = @{ Wg = @(); Ike = @(); Other = @(); Any = $false }
function Get-NetConnectionProfile { [CmdletBinding()] param() return @($script:NetProf) }
$script:NetProf = [pscustomobject]@{ Name = 'KafeWifi'; NetworkCategory = 'Public'; IPv4Connectivity = 'Internet'; IPv6Connectivity = 'NoTraffic' }
Invoke-KillSwitchOp $op
Chk_Vpn
Assert-True ($script:Findings.Count -ge 1 -and $script:Findings[0].Id -eq 'vpn-ks-orphan' -and $script:Findings[0].Status -eq 'bad') 'kill-switch var ama VPN yok = kotu'
Assert-Eq $script:Findings[0].Fix.Key 'KsOff' 'duzeltme: KsOff'
Disable-KillSwitchNow
$script:Findings.Clear()
Chk_Vpn
Assert-True ((Status-Ids) -match 'vpn-public-novpn') 'genel agda VPN yok = bilgi'
$pubF = @($script:Findings | Where-Object { $_.Id -eq 'vpn-public-novpn' })[0]
Assert-True ($pubF.Action.Page -eq 'network' -and $pubF.Action.Sub -eq 'vpn' -and $pubF.Status -eq 'info') 'bulgu sayfa ve sekmeye yonlendirir'
Assert-Eq $pubF.Weight 0 'bilgi bulgusu puan dusurmez'
Assert-True ((Status-Ids) -match 'vpn-doh-off') 'doh kapali = bilgi'
$script:Findings.Clear()
$script:ActNow = @{ Wg = @(@{ Name = 'Ev_Agi'; Mine = $true; Up = $true }); Ike = @(); Other = @(); Any = $true }
Chk_Vpn
Assert-True ((Status-Ids) -notmatch 'vpn-public-novpn') 'VPN varken genel ag uyarisi yok'
# kismi durum
$script:Findings.Clear()
Invoke-KillSwitchOp $op
foreach ($pn in @('Domain', 'Private', 'Public')) { $script:Prof[$pn] = 'Allow' }
Chk_Vpn
Assert-True ((Status-Ids) -match 'vpn-ks-partial') 'kurallar var ama Block degil = yarim'
Disable-KillSwitchNow

# ======================= 9) durum isi =======================
function Get-WgExe { return 'C:\x\wireguard.exe' }
function Get-WgTunnels { return @(@{ Name = 'Ev_Agi'; Mine = $true; Up = $false }) }
function Get-WinVpnProfiles { return @() }
function Get-VpnClients { return @(@{ Id = 'x'; Name = 'x'; Installed = $false }) }
function Get-VpnActive { return @{ Wg = @(); Ike = @(); Other = @(); Any = $false } }
Import-Fn 'Job_VpnStatus'
$r = Job_VpnStatus @{}
Assert-True ($r.WgExe -ne '' -and @($r.Tunnels).Count -eq 1 -and $null -ne $r.Ks -and $null -ne $r.Doh -and $r.AllowLan -eq $true) 'Job_VpnStatus'
$s = Get-Settings; $s.KsAllowLan = $false; Save-Settings $s
Assert-True ((Job_VpnStatus @{}).AllowLan -eq $false) 'yerel ag ayari okunur'

Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
Show-Result
