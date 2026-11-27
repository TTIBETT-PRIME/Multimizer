. "$PSScriptRoot/lib.ps1"
Import-Fn 'Get-AppFolder','Get-TextSha256','Get-PackFileText','Get-OuiMap','ConvertTo-MacKey','Format-Mac','Test-RandomMac','Get-MacVendor','ConvertTo-IpNum','ConvertFrom-IpNum','Get-SubnetTargets','Test-InSubnet','Test-UsableMac',
    'New-NbstatQuery','ConvertFrom-NbstatReply','New-DnsQuery','Read-DnsName','ConvertFrom-DnsPacket','Add-MdnsRecords','New-MdnsEvidence','ConvertFrom-SsdpReply','ConvertFrom-UpnpXml',
    'Get-DevTypeInfo','ConvertFrom-RuleTable','Get-RuleTable','New-Score','Add-Score','Add-OsHint','Invoke-RuleTable','ConvertTo-CleanText','Test-GenericDevName','Get-NameCandidates',
    'Get-DeviceClass','Get-DeviceTitle','Get-DeviceSummary','Get-DeviceRisks'
Import-Var 'PackHash','OuiMap','VmMacPrefixes','DevTypes','DevTypeOrder','RuleVendor','RuleHost','RuleMdns','RuleUpnp','RuleSsdp','RuleHttp','RuleCache'
$sync = @{ ScriptPath = $script:TestPath }

# ---------- OUI ----------
$m = Get-OuiMap
Assert-True ($m.Count -gt 30000) ("OUI sayisi yeterli: " + $m.Count)
Assert-Eq $m['B827EB'] 'Raspberry Pi Foundation' 'OUI Raspberry Pi'
Assert-Eq $m['F0F61C'] 'Apple' 'OUI Apple'
Assert-True (-not ($m.Values | Where-Object { $_ -match '[^\x20-\x7E]' })) 'OUI adlari ASCII'
Assert-True (-not ($m.Values | Where-Object { $_ -match '^(IEEE Registration|Fiberhome Telecommunicatio)' -and $_.Length -ge 26 })) 'yarim kesilmis ad yok'

# ---------- MAC ----------
Assert-Eq (ConvertTo-MacKey 'aa:bb:cc:dd:ee:ff') 'AABBCCDDEEFF' 'mac iki nokta'
Assert-Eq (ConvertTo-MacKey 'AA-BB-CC-DD-EE-FF') 'AABBCCDDEEFF' 'mac tire'
Assert-Eq (ConvertTo-MacKey 'aabb.ccdd.eeff') 'AABBCCDDEEFF' 'mac cisco nokta'
Assert-Eq (ConvertTo-MacKey 'aa:bb:cc') '' 'mac kisa'
Assert-Eq (ConvertTo-MacKey '') '' 'mac bos'
Assert-Eq (Format-Mac 'AABBCCDDEEFF') 'AA-BB-CC-DD-EE-FF' 'mac bicim'
Assert-True (Test-RandomMac '02AABBCCDDEE') 'yerel yonetilen 02'
Assert-True (Test-RandomMac 'DAA1B2C3D4E5') 'yerel yonetilen DA'
Assert-True (-not (Test-RandomMac 'F0F61CAABBCC')) 'evrensel F0'
Assert-True (-not (Test-RandomMac 'ABC')) 'gecersiz anahtar'
Assert-Eq (Get-MacVendor 'F0F61C112233') 'Apple' 'uretici Apple'
Assert-Eq (Get-MacVendor '525400112233') 'QEMU / KVM' 'sanal makine onceligi (yerel yonetilen olsa da)'
Assert-Eq (Get-MacVendor '0A1122334455') '' 'rastgele mac uretici vermez'
Assert-Eq (Get-MacVendor 'ABC') '' 'gecersiz'
Assert-True (Test-UsableMac 'F0F61C112233') 'kullanilabilir mac'
Assert-True (-not (Test-UsableMac 'FFFFFFFFFFFF')) 'yayin mac'
Assert-True (-not (Test-UsableMac '01005E000001')) 'coklu yayin mac'
Assert-True (-not (Test-UsableMac '333300000001')) 'IPv6 coklu yayin'
Assert-True (-not (Test-UsableMac '000000000000')) 'sifir mac'

# ---------- IPv4 ----------
Assert-Eq (ConvertTo-IpNum '192.168.1.10') 3232235786 'ip sayi'
Assert-Eq (ConvertFrom-IpNum 3232235786) '192.168.1.10' 'ip geri'
Assert-Eq (ConvertTo-IpNum '300.1.1.1') -1 'gecersiz ip'
Assert-Eq (ConvertTo-IpNum 'fe80::1') -1 'ipv6 reddedilir'
$t = Get-SubnetTargets '192.168.1.10' 24
Assert-Eq $t.Count 253 '/24: 254 adres - kendi adresim'
Assert-True (-not ($t -contains '192.168.1.10')) 'kendi adresim yok'
Assert-True (-not ($t -contains '192.168.1.0') -and -not ($t -contains '192.168.1.255')) 'ag ve yayin adresi yok'
Assert-Eq (Get-SubnetTargets '10.0.0.5' 16).Count 253 '/16 -> /24 dilimi (genis aglar taranmaz)'
Assert-Eq (Get-SubnetTargets '10.0.0.5' 22).Count 1021 '/22 tam'
Assert-Eq (Get-SubnetTargets '192.168.0.9' 30).Count 1 '/30'
Assert-True (Test-InSubnet '192.168.1.77' '192.168.1.10' 24) 'ayni alt ag'
Assert-True (-not (Test-InSubnet '192.168.2.77' '192.168.1.10' 24)) 'farkli alt ag'

# ---------- NBSTAT ----------
$q = New-NbstatQuery
Assert-Eq $q.Length 50 'NBSTAT sorgu uzunlugu'
Assert-Eq $q[47] 0x21 'NBSTAT tur'
function New-NbReply([object[]]$Names, [byte[]]$Mac) {
    $b = New-Object System.Collections.Generic.List[byte]
    $b.AddRange([byte[]](0x4D, 0x4D, 0x84, 0x00, 0, 0, 0, 1, 0, 0, 0, 0))
    $b.Add(0x20); $b.AddRange([System.Text.Encoding]::ASCII.GetBytes('CKAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA')); $b.Add(0)
    $b.AddRange([byte[]](0, 0x21, 0, 1, 0, 0, 0, 0, 0, 0))
    $b.Add([byte]$Names.Count)
    foreach ($n in $Names) {
        $b.AddRange([System.Text.Encoding]::ASCII.GetBytes(([string]$n.N).PadRight(15)))
        $b.Add([byte]$n.S); $b.Add([byte]$n.F1); $b.Add(0)
    }
    $b.AddRange($Mac)
    return , $b.ToArray()
}
$rep = New-NbReply @(@{ N = 'LAPTOP-01'; S = 0; F1 = 0x04 }, @{ N = 'WORKGROUP'; S = 0; F1 = 0x84 }, @{ N = 'LAPTOP-01'; S = 0x20; F1 = 0x04 }) ([byte[]](0xF0, 0xF6, 0x1C, 1, 2, 3))
$nb = ConvertFrom-NbstatReply $rep
Assert-Eq $nb.Name 'LAPTOP-01' 'NBSTAT ad'
Assert-Eq $nb.Workgroup 'WORKGROUP' 'NBSTAT calisma grubu'
Assert-True ($nb.Server -eq $true) 'NBSTAT dosya sunucusu'
Assert-Eq $nb.Mac 'F0F61C010203' 'NBSTAT mac'
Assert-True ($null -eq (ConvertFrom-NbstatReply ([byte[]](1, 2, 3)))) 'NBSTAT kisa paket'
$noresp = $rep.Clone(); $noresp[2] = 0
Assert-True ($null -eq (ConvertFrom-NbstatReply $noresp)) 'NBSTAT yanit bayragi yok'
$zeroMac = New-NbReply @(@{ N = 'PRINTER'; S = 0; F1 = 0x04 }) ([byte[]](0, 0, 0, 0, 0, 0))
Assert-Eq (ConvertFrom-NbstatReply $zeroMac).Mac '' 'NBSTAT sifir mac atilir'
$trunc = New-NbReply @(@{ N = 'ABC'; S = 0; F1 = 4 }) ([byte[]](1, 2))
Assert-Eq (ConvertFrom-NbstatReply $trunc).Name 'ABC' 'NBSTAT eksik mac bayti hata vermez'

# ---------- DNS / mDNS ----------
$dq = New-DnsQuery '_airplay._tcp.local' 12 $true
Assert-Eq $dq[5] 1 'DNS soru sayisi'
Assert-Eq $dq[12] 8 'DNS ilk etiket uzunlugu'
Assert-Eq $dq[$dq.Length - 2] 0x80 'unicast-yanit biti'
function Add-Name($b, [string]$n) { foreach ($l in $n.Split('.')) { $lb = [System.Text.Encoding]::UTF8.GetBytes($l); $b.Add([byte]$lb.Length); $b.AddRange($lb) }; $b.Add(0) }
function Add-Rr($b, [string]$name, [int]$type, [byte[]]$rd) {
    Add-Name $b $name
    $b.Add(0); $b.Add([byte]$type); $b.Add(0); $b.Add(1); $b.AddRange([byte[]](0, 0, 0, 120)); $b.Add([byte]([math]::Floor($rd.Length / 256))); $b.Add([byte]($rd.Length % 256)); $b.AddRange($rd)
}
function New-Rd([scriptblock]$f) { $l = New-Object System.Collections.Generic.List[byte]; & $f $l; return , $l.ToArray() }
$pk = New-Object System.Collections.Generic.List[byte]
$pk.AddRange([byte[]](0, 0, 0x84, 0, 0, 0, 0, 4, 0, 0, 0, 0))
$ptr = New-Rd { param($l) Add-Name $l 'Salon._googlecast._tcp.local' }
Add-Rr $pk '_googlecast._tcp.local' 12 $ptr
$srv = New-Rd { param($l) $l.AddRange([byte[]](0, 0, 0, 0, 0x1F, 0x49)); Add-Name $l 'Chromecast-abc.local' }
Add-Rr $pk 'Salon._googlecast._tcp.local' 33 $srv
$txt = New-Rd { param($l) foreach ($s in @('id=abc123', 'fn=Salon TV', 'md=Chromecast', 'ca=5')) { $sb = [System.Text.Encoding]::UTF8.GetBytes($s); $l.Add([byte]$sb.Length); $l.AddRange($sb) } }
Add-Rr $pk 'Salon._googlecast._tcp.local' 16 $txt
Add-Rr $pk 'Chromecast-abc.local' 1 ([byte[]](192, 168, 1, 44))
$recs = ConvertFrom-DnsPacket $pk.ToArray()
Assert-Eq $recs.Count 4 'DNS 4 kayit'
Assert-Eq $recs[0].Data 'Salon._googlecast._tcp.local' 'PTR verisi'
Assert-Eq $recs[1].Data.Port 8009 'SRV portu'
Assert-Eq $recs[1].Data.Target 'Chromecast-abc.local' 'SRV hedefi'
Assert-Eq $recs[2].Data['fn'] 'Salon TV' 'TXT fn'
Assert-Eq $recs[2].Data['ca'] '5' 'TXT ca'
Assert-Eq $recs[3].Data '192.168.1.44' 'A kaydi'
$ev = New-MdnsEvidence
Add-MdnsRecords $ev $recs
Assert-True ($ev.Services.Contains('_googlecast._tcp.local')) 'hizmet eklendi'
Assert-Eq $ev.Instances['_googlecast._tcp.local'] 'Salon' 'ornek adi'
Assert-Eq $ev.Host 'Chromecast-abc' 'ana makine adi (.local atilir)'
Assert-Eq $ev.Txt['md'] 'Chromecast' 'TXT birlesti'
# sikistirilmis ad isaretcisi + dongu korumasi
$cmp = [byte[]](0, 0, 0x84, 0, 0, 0, 0, 1, 0, 0, 0, 0, 5, 0x6C, 0x6F, 0x63, 0x61, 0x6C, 0, 0, 12, 0, 1, 0, 0, 0, 120, 0, 2, 0xC0, 12)
$r2 = ConvertFrom-DnsPacket $cmp
Assert-Eq $r2.Count 1 'sikistirilmis ad cozuldu'
Assert-Eq $r2[0].Data 'local' 'sikistirilmis PTR'
$loop = [byte[]](0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0xC0, 12, 0, 1, 0, 1)
$rr = Read-DnsName $loop 12
Assert-True ($rr.Next -ge 0) 'isaretci dongusu sonsuz degil'
Assert-Eq (ConvertFrom-DnsPacket ([byte[]](1, 2, 3))).Count 0 'kisa DNS paketi'
$garbage = [byte[]](0, 0, 0x84, 0, 0, 0, 0, 9, 0, 0, 0, 0, 1, 2, 3)
Assert-Eq (ConvertFrom-DnsPacket $garbage).Count 0 'bozuk DNS paketi hata vermez'

# ---------- SSDP / UPnP ----------
$ss = ConvertFrom-SsdpReply "HTTP/1.1 200 OK`r`nCACHE-CONTROL: max-age=1800`r`nLOCATION: http://192.168.1.1:49152/rootDesc.xml`r`nSERVER: Linux/3.10 UPnP/1.0 miniupnpd/2.1`r`nST: urn:schemas-upnp-org:device:InternetGatewayDevice:1`r`nUSN: uuid:abc::urn:schemas-upnp-org:device:InternetGatewayDevice:1`r`n`r`n"
Assert-Eq $ss.Location 'http://192.168.1.1:49152/rootDesc.xml' 'SSDP konum'
Assert-Eq $ss.St 'urn:schemas-upnp-org:device:InternetGatewayDevice:1' 'SSDP ST'
Assert-True ($ss.Server -match 'miniupnpd') 'SSDP sunucu'
$xml = '<?xml version="1.0"?><root xmlns="urn:schemas-upnp-org:device-1-0"><device><deviceType>urn:schemas-upnp-org:device:MediaRenderer:1</deviceType><friendlyName>Oturma Odasi TV</friendlyName><manufacturer>Samsung Electronics</manufacturer><modelName>UE55</modelName><modelDescription>Samsung TV</modelDescription></device></root>'
$up = ConvertFrom-UpnpXml $xml
Assert-Eq $up.Friendly 'Oturma Odasi TV' 'UPnP ad'
Assert-Eq $up.Manufacturer 'Samsung Electronics' 'UPnP uretici'
Assert-Eq $up.Model 'UE55' 'UPnP model'
$xxe = '<?xml version="1.0"?><!DOCTYPE r [<!ENTITY x SYSTEM "file:///etc/passwd">]><root><device><friendlyName>&x;</friendlyName></device></root>'
$ux = ConvertFrom-UpnpXml $xxe
Assert-Eq $ux.Friendly '' 'DTD/XXE reddedilir'
Assert-Eq (ConvertFrom-UpnpXml 'degil xml').Friendly '' 'bozuk xml hata vermez'

# ---------- kural tablolari ----------
foreach ($tn in @(@('vendor', $script:RuleVendor), @('host', $script:RuleHost), @('mdns', $script:RuleMdns), @('upnp', $script:RuleUpnp), @('ssdp', $script:RuleSsdp), @('http', $script:RuleHttp))) {
    $lines = @(($tn[1] -split "`n") | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' -and -not $_.StartsWith('#') })
    $rules = Get-RuleTable $tn[0]
    Assert-True ($rules.Count -gt 3) ($tn[0] + ' tablosu bos degil')
    Assert-Eq $rules.Count $lines.Count ($tn[0] + ': hicbir satir sessizce dusmedi')
    foreach ($r in $rules) {
        foreach ($mm in $r.Map) { if (-not ($script:DevTypes.Contains([string]$mm.T))) { Assert-True $false ($tn[0] + ': bilinmeyen tur ' + $mm.T) } }
    }
    Assert-True (-not ($tn[1] -match '[^\x00-\x7F]')) ($tn[0] + ' tablosu ASCII')
}

# ---------- temizleme ve adlar ----------
Assert-Eq (ConvertTo-CleanText "  Kamera`t|`r`n  Salon  ") 'Kamera / Salon' 'kontrol karakteri ve | temizlenir'
Assert-Eq (ConvertTo-CleanText ('a' * 100) 10) 'aaaaaaaaaa' 'uzunluk siniri'
Assert-Eq (ConvertTo-CleanText $null) '' 'null'
Assert-True (Test-GenericDevName '192-168-1-5') 'ip benzeri ad genel'
Assert-True (Test-GenericDevName 'AA:BB:CC:DD:EE:FF') 'mac benzeri ad genel'
Assert-True (-not (Test-GenericDevName 'Ayse''nin telefonu')) 'gercek ad'

# ---------- siniflandirici ----------
function New-Ev([hashtable]$o) {
    $e = @{ Ip = '192.168.1.50'; Mac = ''; Vendor = ''; Random = $false; Ttl = 0; Rdns = ''; Nb = $null; Mdns = $null; Ssdp = $null; Upnp = $null; Ports = @(); Http = $null; IsGateway = $false; IsSelf = $false; UserName = '' }
    foreach ($k in $o.Keys) { $e[$k] = $o[$k] }
    return $e
}
function New-Md([string[]]$Svc, [hashtable]$Txt = @{}, [hashtable]$Inst = @{}, [string]$HostName = '') {
    $m = New-MdnsEvidence
    foreach ($s in $Svc) { [void]$m.Services.Add($s) }
    foreach ($k in $Txt.Keys) { $m.Txt[$k] = $Txt[$k] }
    foreach ($k in $Inst.Keys) { $m.Instances[$k] = $Inst[$k] }
    $m.Host = $HostName
    return $m
}
$c = Get-DeviceClass (New-Ev @{ IsSelf = $true })
Assert-Eq $c.Type 'self' 'kendi bilgisayarim'
Assert-Eq $c.Conf 100 'self guven'
$c = Get-DeviceClass (New-Ev @{ IsGateway = $true; Vendor = 'TP-LINK'; Ttl = 64; Ports = @(53, 80) })
Assert-Eq $c.Type 'router' 'ag gecidi yonlendirici'
Assert-True ($c.Conf -ge 60) ('router guveni: ' + $c.Conf)
$c = Get-DeviceClass (New-Ev @{ Vendor = 'Apple'; Mdns = (New-Md @('_companion-link._tcp.local', '_airplay._tcp.local') @{ rpmd = 'iPhone14,5' } @{ '_companion-link._tcp.local' = 'Ayse''nin iPhone''u' }) })
Assert-Eq $c.Type 'phone' 'iPhone'
Assert-Eq $c.Os 'iOS' 'iPhone iOS'
Assert-Eq $c.Model 'iPhone14,5' 'iPhone modeli'
Assert-Eq $c.Name 'Ayse''nin iPhone''u' 'cihazin bildirdigi ad'
Assert-Eq $c.NameSrc 'mDNS' 'ad kaynagi'
$c = Get-DeviceClass (New-Ev @{ Vendor = 'Google'; Mdns = (New-Md @('_googlecast._tcp.local') @{ ca = '5'; md = 'Chromecast'; fn = 'Salon TV' }) })
Assert-Eq $c.Type 'tv' 'Chromecast (goruntu cikisi)'
Assert-Eq $c.Name 'Salon TV' 'Cast adi'
$c = Get-DeviceClass (New-Ev @{ Vendor = 'Google'; Mdns = (New-Md @('_googlecast._tcp.local') @{ ca = '198660'; md = 'Google Nest Mini' }) })
Assert-Eq $c.Type 'speaker' 'Nest Mini (yalniz ses)'
$c = Get-DeviceClass (New-Ev @{ Vendor = 'Hewlett Packard'; Mdns = (New-Md @('_ipp._tcp.local', '_printer._tcp.local') @{ ty = 'HP OfficeJet 3830' }) })
Assert-Eq $c.Type 'printer' 'IPP yazici'
Assert-Eq $c.Model 'HP OfficeJet 3830' 'yazici modeli'
$c = Get-DeviceClass (New-Ev @{ Vendor = 'Hikvision'; Ports = @(80, 554) })
Assert-Eq $c.Type 'camera' 'kamera (uretici + RTSP)'
$c = Get-DeviceClass (New-Ev @{ Vendor = 'Raspberry Pi Foundation'; Ports = @(22) })
Assert-Eq $c.Type 'sbc' 'Raspberry Pi'
$c = Get-DeviceClass (New-Ev @{ Ttl = 128; Nb = @{ Name = 'DESKTOP-AB12'; Workgroup = 'WORKGROUP'; Server = $true; Mac = '' }; Ports = @(135, 445) })
Assert-Eq $c.Type 'pc' 'Windows bilgisayar'
Assert-Eq $c.Os 'Windows' 'Windows isletim sistemi'
Assert-Eq $c.Name 'DESKTOP-AB12' 'NetBIOS adi'
$c = Get-DeviceClass (New-Ev @{ Random = $true })
Assert-Eq $c.Type 'phone' 'rastgele MAC telefon sayilir'
Assert-True ($c.Conf -lt 60) ('rastgele MAC guveni dusuk: ' + $c.Conf)
$c = Get-DeviceClass (New-Ev @{ Vendor = 'Samsung'; Ports = @(8001, 8002) })
Assert-Eq $c.Type 'tv' 'Samsung TV (8001)'
$c = Get-DeviceClass (New-Ev @{})
Assert-Eq $c.Type 'unknown' 'hic ipucu yok -> tanimsiz'
Assert-True ($c.Why.Count -ge 1) 'tanimsizin nedeni yazilir'
$c = Get-DeviceClass (New-Ev @{ UserName = 'Mutfak kamerasi' })
Assert-Eq $c.Name 'Mutfak kamerasi' 'kullanici adi onceliklidir'
Assert-Eq $c.NameSrc 'sizin adınız' 'ad kaynagi kullanici'
$c = Get-DeviceClass (New-Ev @{ Ssdp = @{ Server = 'Linux/3.10 UPnP/1.0 miniupnpd/2.1'; Sts = @('urn:schemas-upnp-org:device:InternetGatewayDevice:1'); Locations = @() } })
Assert-Eq $c.Type 'router' 'UPnP IGD yonlendirici'
# zararli metinler tur belirlemeyi/gorunumu bozmaz
$c = Get-DeviceClass (New-Ev @{ Mdns = (New-Md @('_ipp._tcp.local') @{ ty = ("Evil`r`n|Printer" + ('x' * 200)) }) })
Assert-True ($c.Model.Length -le 50 -and $c.Model -notmatch "[\r\n|]") 'model metni temizlenir'
$c = Get-DeviceClass (New-Ev @{ Http = @{ 80 = @{ Status = 200; Server = 'lighttpd'; Title = 'Network Camera'; Realm = '' } } })
Assert-Eq $c.Type 'camera' 'web basligi: Network Camera'
Assert-Eq (Get-DeviceTitle @{ Name = ''; Type = 'printer'; Vendor = 'Brother'; Ip = '192.168.1.9' }) 'Brother · Yazıcı / tarayıcı' 'baslik: uretici + tur'
Assert-Eq (Get-DeviceTitle @{ Name = ''; Type = 'unknown'; Vendor = ''; Ip = '192.168.1.9' }) 'Cihaz 192.168.1.9' 'baslik: tanimsiz'
Assert-Eq (Get-DeviceSummary @{ Vendor = 'Apple'; Model = 'iPhone14,5'; Os = 'iOS' }) 'Apple · iPhone14,5 · iOS' 'ozet'

# ---------- riskler ----------
$rk = Get-DeviceRisks @{ Type = 'camera'; Ports = @(23, 554); Http = $null; New = $false }
Assert-True (@($rk | Where-Object { $_.Sev -eq 'bad' }).Count -ge 1) 'telnet kirmizi'
Assert-True (@($rk | Where-Object { $_.Text -match 'RTSP' }).Count -eq 1) 'RTSP bilgisi'
$rk = Get-DeviceRisks @{ Type = 'pc'; Ports = @(445, 3389); Http = $null; New = $false }
Assert-Eq @($rk | Where-Object { $_.Text -match 'SMB' }).Count 0 'bilgisayarda SMB risk sayilmaz'
Assert-Eq @($rk | Where-Object { $_.Text -match 'Uzak' }).Count 1 'RDP uyarisi'
$rk = Get-DeviceRisks @{ Type = 'printer'; Ports = @(445, 80); Http = @{ 80 = @{ Realm = 'admin'; Title = ''; Server = '' } }; New = $false }
Assert-Eq $rk.Count 2 'yazicida SMB + sifresiz yonetim'
$rk = Get-DeviceRisks @{ Type = 'unknown'; Ports = @(); Http = $null; New = $true }
Assert-Eq $rk.Count 1 'yeni tanimsiz cihaz uyarisi'
$rk = Get-DeviceRisks @{ Type = 'tv'; Ports = $null; Http = $null; New = $false }
Assert-Eq $rk.Count 0 'risk yok'
# ---------- port yoklaması (APM): süre dolan bağlantı gözlenmeyen görev hatası bırakmaz ----------
# Gerçek bilgisayarda (18.11.2026) ConnectAsync + Close() sonrası 20 "gözlenmeyen görev hatası" (TcpClient.EndConnect NullReference) görüldü.
Import-Fn 'Invoke-PortProbe', 'Job_PortCheck'
Import-Var 'CommonPorts'
function Test-PrivateIp([string]$Ip) { return $true }
function Test-JobCancel { return $false }
function Set-JobProgress { param($a, $b, $c) }
function Step-JobProgress { param($a) }
function Write-WhLog([string]$Message, [string]$Level = 'INFO') { }
$lst = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0)
$lst.Start()
$openPort = ([System.Net.IPEndPoint]$lst.LocalEndpoint).Port
$tmpL = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0); $tmpL.Start(); $closedPort = ([System.Net.IPEndPoint]$tmpL.LocalEndpoint).Port; $tmpL.Stop()
$pr = Invoke-PortProbe @('127.0.0.1') @($openPort, $closedPort) 900 160
Assert-True ($pr.ContainsKey('127.0.0.1') -and (@($pr['127.0.0.1']) -contains $openPort)) 'port yoklaması: açık port bulunur'
Assert-True (@($pr['127.0.0.1']) -notcontains $closedPort) 'port yoklaması: kapalı port açık sayılmaz'
$pr2 = Invoke-PortProbe @('127.0.0.1', '127.0.0.2') @($openPort) 900 1
Assert-True (@($pr2['127.0.0.1']) -contains $openPort) 'port yoklaması: küçük partilerde de doğru sonuç'
$pc = Job_PortCheck @{ Host = '127.0.0.1' }
Assert-True ([bool]$pc.Ok) 'port denetimi işi çalışır'
$lst.Stop()
$srcP = [System.IO.File]::ReadAllText($script:TestPath)
Assert-True ($srcP -notmatch '\.ConnectAsync\(') 'port yoklaması ConnectAsync kullanmaz (süre dolunca gözlenmeyen görev hatası bırakmaz)'
Show-Result
