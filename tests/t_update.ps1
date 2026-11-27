. "$PSScriptRoot/lib.ps1"
# Güncelleme denetimi ve dosya bütünlüğü (mods\134_update_core.ps1 ve 135_update_ui.ps1): sürüm karşılaştırma, adres kuralları, bildirim ayrıştırma,
# gerçek HTTP katmanı (yerel sunucuyla), yönlendirme/boyut/özet kuralları, indirme işi, bütünlük denetimi, arayüz akışı ve "kendiliğinden bağlanmaz" yapısı.
# Dış ağa hiçbir istek gitmez; yalnızca 127.0.0.1 üzerindeki geçici sunucu kullanılır.
$env:no_proxy = '127.0.0.1,localhost'; $env:NO_PROXY = '127.0.0.1,localhost'
Import-Fn 'Get-JsonProp', 'Format-Size', 'Test-JobCancel', 'Set-JobProgress',
    'ConvertTo-AppVersionParts', 'Compare-AppVersion', 'Test-UpdateUrl', 'ConvertTo-UpdateFeedUrl', 'Format-UpdateNotes', 'ConvertFrom-UpdateInfo',
    'Send-UpdateHop', 'Invoke-UpdateFetch', 'Job_UpdateCheck', 'Get-UpdateDir', 'Job_UpdateDownload',
    'Get-AppFolder', 'Get-TextSha256', 'Get-PackFileText', 'Get-PackIntegrity', 'Job_IntegrityCheck',
    'Set-StUpdText', 'Get-UpdateStateModel', 'Get-UpdateConfirmText', 'Get-UpdateDoneModel', 'Get-IntegrityModel',
    'Update-StUpdateView', 'Load-StUpdate', 'Save-StUpdateUrl', 'Start-UpdateCheck', 'Complete-UpdateCheck', 'Start-UpdateDownload', 'Complete-UpdateDownload',
    'Start-IntegrityCheck', 'Complete-IntegrityCheck', 'Init-StUpdate', 'Test-NetBlocked', 'Get-NetBlockText', 'Get-SmokeActions'
Import-Var 'UpdateMaxManifest', 'UpdateMaxDownload', 'UpdateMaxHops', 'UpdateAgent', 'SmokeSafe', 'NetFeatures'
$script:UpdLast = $null; $script:UpdBusy = $false; $script:UpdPending = $null; $script:UpdGot = ''; $script:UpdDone = $null; $script:IntBusy = $false
$script:WhLog = New-Object System.Collections.ArrayList
function Write-WhLog([string]$Message, [string]$Level = 'INFO') { [void]$script:WhLog.Add($Level + '|' + $Message) }
function Sha-Hex([byte[]]$B) { $h = [System.Security.Cryptography.SHA256]::Create(); try { return (([System.BitConverter]::ToString($h.ComputeHash($B))) -replace '-', '').ToLowerInvariant() } finally { $h.Dispose() } }
function J([string]$S) { return (ConvertFrom-Json -InputObject $S) }
. "$PSScriptRoot/uifake.ps1"
$src = [System.IO.File]::ReadAllText($script:TestPath)
$null = Get-AstFunctions
$sha = ('ab' * 32)

# =====================================================================
#  1) sürüm numaraları
# =====================================================================
Assert-Eq ((ConvertTo-AppVersionParts '9.0.1') -join '.') '9.0.1.0' 'sürüm: üç parça dörde tamamlanır'
Assert-Eq ((ConvertTo-AppVersionParts 'v9.1') -join '.') '9.1.0.0' 'sürüm: baştaki v atılır, iki parça tamamlanır'
Assert-Eq ((ConvertTo-AppVersionParts 'V10.2.3.4') -join '.') '10.2.3.4' 'sürüm: büyük V de kabul edilir, dört parça'
Assert-Eq ((ConvertTo-AppVersionParts " 9.0.0`n") -join '.') '9.0.0.0' 'sürüm: baştaki/sondaki boşluk kırpılır'
foreach ($bad in @('', 'abc', '9', 'v', '9.0.0-beta', '9..0', '9.0.0.0.0', '.9.0', '9.0.', '9.0.0 beta', '100000.0', '9.0.0+1', '-9.0.0', '9,0,0', ('v' + [char]0xFF19 + '.0.0'), '9.0.0;calc', '9.0.0/../x')) {
    Assert-True ($null -eq (ConvertTo-AppVersionParts $bad)) ('sürüm: geçersiz biçim reddedilir [' + $bad + ']')
}
Assert-Eq (Compare-AppVersion '9.0.0' '9.0.0') 0 'karşılaştırma: eşit'
Assert-Eq (Compare-AppVersion '9.0.1' '9.0.0') 1 'karşılaştırma: yama sürümü büyük'
Assert-Eq (Compare-AppVersion '9.0.0' '9.0.1') -1 'karşılaştırma: yama sürümü küçük'
Assert-Eq (Compare-AppVersion '10.0.0' '9.9.9') 1 'karşılaştırma: sayısal (10 > 9), metin sırası değil'
Assert-Eq (Compare-AppVersion '9.10.0' '9.9.0') 1 'karşılaştırma: 9.10 > 9.9'
Assert-Eq (Compare-AppVersion 'v9.1' '9.1.0') 0 'karşılaştırma: v öneki ve eksik parça eşit sayılır'
Assert-Eq (Compare-AppVersion '9.0.0.1' '9.0.0') 1 'karşılaştırma: dördüncü parça'
Assert-Eq (Compare-AppVersion '8.0.0' '9.0.0') -1 'karşılaştırma: ana sürüm'
Assert-Eq (Compare-AppVersion '9.0.0' '9.0.0.0') 0 'karşılaştırma: sondaki sıfır önemsiz'
Assert-True ($null -eq (Compare-AppVersion 'x' '9.0.0') -and $null -eq (Compare-AppVersion '9.0.0' '') -and $null -eq (Compare-AppVersion '' '')) 'karşılaştırma: geçersiz biçim $null döner'

# =====================================================================
#  2) adres kuralları
# =====================================================================
foreach ($ok in @('https://github.com/sahip/depo', 'https://example.com/update.json', 'https://example.com:443/x', 'HTTPS://EXAMPLE.COM/x', 'https://api.github.com/repos/o/r/releases/latest', 'https://[::1]/x', 'https://192.168.1.5/m.json')) {
    Assert-Eq (Test-UpdateUrl $ok) '' ('adres: geçerli ' + $ok)
}
Assert-True ((Test-UpdateUrl '') -match 'Önce') 'adres: boş'
Assert-True ((Test-UpdateUrl '   ') -match 'Önce') 'adres: yalnızca boşluk'
Assert-True ((Test-UpdateUrl $null) -match 'Önce') 'adres: null'
foreach ($x in @('http://example.com/x', 'ftp://example.com/x', 'file:///c:/x', 'javascript:alert(1)', '//example.com/x', 'example.com/x', 'data:text/plain,abc', 'ms-settings:privacy')) {
    Assert-True ((Test-UpdateUrl $x) -ne '') ('adres: https dışı reddedilir ' + $x)
}
Assert-True ((Test-UpdateUrl 'http://example.com/x') -match 'https://') 'adres: http için neden metni https der'
Assert-True ((Test-UpdateUrl 'https://user:pw@example.com/x') -match 'kullanıcı adı') 'adres: kullanıcı bilgisi reddedilir'
Assert-True ((Test-UpdateUrl 'https://user@example.com/x') -ne '') 'adres: yalnızca kullanıcı adı da reddedilir'
Assert-True ((Test-UpdateUrl 'https://example.com:8443/x') -ne '') 'adres: özel kapı reddedilir'
Assert-True ((Test-UpdateUrl 'https://exa mple.com/x') -match 'geçersiz') 'adres: boşluklu ana makine reddedilir'
Assert-True ((Test-UpdateUrl "https://example.com/x`n") -match 'geçersiz') 'adres: satır sonu reddedilir'
Assert-True ((Test-UpdateUrl "https://example.com/x`t") -match 'geçersiz') 'adres: sekme reddedilir'
Assert-True ((Test-UpdateUrl ("https://example.com/" + ('a' * 600))) -match 'uzun') 'adres: çok uzun reddedilir'
Assert-True ((Test-UpdateUrl 'https://') -ne '' -and (Test-UpdateUrl 'https:///x') -ne '') 'adres: ana makinesiz reddedilir'

# GitHub depo adresi -> en son sürüm API adresi
$api = 'https://api.github.com/repos/ttibett/Multimizer/releases/latest'
foreach ($g in @('https://github.com/ttibett/Multimizer', 'https://github.com/ttibett/Multimizer/', 'https://github.com/ttibett/Multimizer.git', 'https://GitHub.com/ttibett/Multimizer', 'https://www.github.com/ttibett/Multimizer',
                 'https://github.com/ttibett/Multimizer/releases', 'https://github.com/ttibett/Multimizer/releases/latest', 'https://github.com/ttibett/Multimizer/releases/tag/v9.0.0', ' https://github.com/ttibett/Multimizer ')) {
    Assert-Eq (ConvertTo-UpdateFeedUrl $g) $api ('besleme: GitHub depo adresi API adresine çevrilir [' + $g + ']')
}
foreach ($g in @('https://github.com/ttibett', 'https://github.com/ttibett/Multimizer/issues', 'https://github.com/ttibett/Multimizer/archive/main.zip', 'https://github.com/-kotu/depo', 'https://github.com/ttibett/depo%2Fx',
                 'https://example.com/ttibett/Multimizer', 'https://api.github.com/repos/o/r/releases/latest', 'http://github.com/o/r', 'https://github.com/')) {
    Assert-Eq (ConvertTo-UpdateFeedUrl $g) $g.Trim() ('besleme: çevrilmeyen adres değişmez [' + $g + ']')
}
Assert-True ((ConvertTo-UpdateFeedUrl 'https://github.com/o/..') -notmatch 'api.github.com/repos/o/\.\.') 'besleme: üst klasör kaçışı API adresi olmaz'
Assert-True ((Test-UpdateUrl (ConvertTo-UpdateFeedUrl 'https://github.com/ttibett/Multimizer')) -eq '') 'besleme: çevrilen adres de https kurallarından geçer'

# =====================================================================
#  3) bildirim metni ve ayrıştırma
# =====================================================================
Assert-Eq (Format-UpdateNotes "a`u{0007}b`u{000B}c") 'abc' 'notlar: denetim karakterleri atılır'
Assert-Eq (Format-UpdateNotes "a`r`n`r`n`r`n`r`nb") "a`n`nb" 'notlar: CRLF düzeltilir, üç ve fazla boş satır ikiye iner'
Assert-Eq (Format-UpdateNotes "  x  ") 'x' 'notlar: kırpılır'
$long = Format-UpdateNotes ('x' * 700)
Assert-True ($long.Length -eq 600 -and $long.EndsWith('...')) 'notlar: 600 karakterde kesilir'
Assert-Eq (Format-UpdateNotes '') '' 'notlar: boş'

$mjson = '{"version":"9.1.0","url":"https://example.com/dl/Multimizer-9.1.0.zip","sha256":"' + $sha.ToUpperInvariant() + '","size":2900000,"notes":"Yeni\u0007 \u00e7ok iyi","page":"https://example.com/s"}'
$r = ConvertFrom-UpdateInfo (J $mjson)
Assert-True ($r.Ok -eq $true -and $r.Download -eq $true -and $r.Why -eq '' -and $r.Error -eq '') 'bildirim: tam kayıt indirilebilir'
Assert-Eq $r.Version '9.1.0' 'bildirim: sürüm'
Assert-Eq $r.Url 'https://example.com/dl/Multimizer-9.1.0.zip' 'bildirim: adres'
Assert-Eq $r.Sha256 $sha 'bildirim: özet küçük harfe çevrilir'
Assert-Eq $r.Size ([long]2900000) 'bildirim: boyut'
Assert-Eq $r.Notes ('Yeni ' + [char]0x00E7 + 'ok iyi') 'bildirim: not temizlenir'
Assert-Eq $r.Page 'https://example.com/s' 'bildirim: sayfa'
Assert-Eq (ConvertFrom-UpdateInfo (J '{"version":"v9.1.0"}')).Version '9.1.0' 'bildirim: v öneki atılır'
$noSha = ConvertFrom-UpdateInfo (J '{"version":"9.1.0","url":"https://example.com/a.zip"}')
Assert-True ($noSha.Ok -eq $true -and $noSha.Download -eq $false -and $noSha.Why -match 'SHA-256') 'bildirim: özet yoksa indirme kapalı, sürüm okunur'
foreach ($badSha in @(('ab' * 31), ('ab' * 33), ('g' * 64), ($sha + "`n"), (' ' + $sha), '')) {
    $x = ConvertFrom-UpdateInfo (J ('{"version":"9.1.0","url":"https://example.com/a.zip","sha256":"' + ($badSha -replace "`n", '\n') + '"}'))
    Assert-True ($x.Ok -eq $true -and $x.Download -eq $false) ('bildirim: geçersiz özet indirmeyi kapatır [' + $badSha.Length + ']')
}
foreach ($u in @('http://example.com/a.zip', 'ftp://example.com/a.zip', 'https://u:p@example.com/a.zip', 'https://example.com:8443/a.zip', 'file:///c:/a.zip')) {
    $x = ConvertFrom-UpdateInfo (J ('{"version":"9.1.0","url":"' + $u + '","sha256":"' + $sha + '"}'))
    Assert-True ($x.Ok -eq $true -and $x.Download -eq $false -and $x.Why -match 'güvenli değil') ('bildirim: güvensiz indirme adresi kapatılır ' + $u)
}
foreach ($u in @('https://example.com/a.exe', 'https://example.com/a.zip.exe', 'https://example.com/a?f=a.zip', 'https://example.com/a.zip/', 'https://example.com/')) {
    $x = ConvertFrom-UpdateInfo (J ('{"version":"9.1.0","url":"' + $u + '","sha256":"' + $sha + '"}'))
    Assert-True ($x.Ok -eq $true -and $x.Download -eq $false -and $x.Why -match 'ZIP') ('bildirim: ZIP olmayan adres kapatılır ' + $u)
}
$x = ConvertFrom-UpdateInfo (J ('{"version":"9.1.0","sha256":"' + $sha + '"}'))
Assert-True ($x.Ok -eq $true -and $x.Download -eq $false -and $x.Why -match 'adresi yok') 'bildirim: indirme adresi yoksa kapalı'
foreach ($v in @('', 'latest', '9.0.0-rc1', 'abc', '9', 'v')) {
    $x = ConvertFrom-UpdateInfo (J ('{"version":"' + $v + '","url":"https://example.com/a.zip","sha256":"' + $sha + '"}'))
    Assert-True ($x.Ok -eq $false -and $x.Error -match 'geçersiz' -and $x.Download -eq $false) ('bildirim: geçersiz sürüm reddedilir [' + $v + ']')
}
Assert-True ((ConvertFrom-UpdateInfo $null).Ok -eq $false -and (ConvertFrom-UpdateInfo $null).Error -match 'boş') 'bildirim: null nesne'
Assert-True ((ConvertFrom-UpdateInfo (J '[1,2]')).Ok -eq $false) 'bildirim: dizi gelirse reddedilir'
foreach ($sz in @('0', '-5', '"abc"', '99999999999', 'null')) {
    $x = ConvertFrom-UpdateInfo (J ('{"version":"9.1.0","url":"https://example.com/a.zip","sha256":"' + $sha + '","size":' + $sz + '}'))
    Assert-True ($x.Size -eq 0 -and $x.Download -eq $true) ('bildirim: kabul edilmeyen boyut 0 olur, indirme sürer [' + $sz + ']')
}
foreach ($pg in @('http://example.com/s', 'javascript:alert(1)', 'https://u:p@example.com/s', 'not a url')) {
    $x = ConvertFrom-UpdateInfo (J ('{"version":"9.1.0","page":"' + $pg + '"}'))
    Assert-Eq $x.Page '' ('bildirim: güvensiz sürüm sayfası alınmaz [' + $pg + ']')
}
$x = ConvertFrom-UpdateInfo @{ version = '9.2.0'; url = 'https://example.com/a.zip'; sha256 = $sha }
Assert-True ($x.Ok -eq $true -and $x.Download -eq $true) 'bildirim: sözlük nesnesi de okunur'

# GitHub "releases/latest" yanıtı
$gh = '{"tag_name":"v9.2.0","html_url":"https://github.com/o/r/releases/tag/v9.2.0","body":"Notlar","assets":[' +
    '{"name":"source.zip","browser_download_url":"https://github.com/o/r/releases/download/v9.2.0/source.zip","size":10,"digest":"sha256:' + ('cd' * 32) + '"},' +
    '{"name":"Multimizer-9.2.0.zip.sig","browser_download_url":"https://github.com/o/r/releases/download/v9.2.0/Multimizer-9.2.0.zip.sig","size":5,"digest":"sha256:' + ('ee' * 32) + '"},' +
    '{"name":"Multimizer-9.2.0.zip","browser_download_url":"https://github.com/o/r/releases/download/v9.2.0/Multimizer-9.2.0.zip","size":2800000,"digest":"sha256:' + $sha.ToUpperInvariant() + '"}]}'
$x = ConvertFrom-UpdateInfo (J $gh)
Assert-True ($x.Ok -eq $true -and $x.Download -eq $true -and $x.Version -eq '9.2.0' -and $x.Sha256 -eq $sha -and $x.Size -eq 2800000) 'GitHub: doğru ek seçilir, özet ve boyut alınır'
Assert-Eq $x.Url 'https://github.com/o/r/releases/download/v9.2.0/Multimizer-9.2.0.zip' 'GitHub: indirme adresi Multimizer-*.zip ekidir'
Assert-Eq $x.Page 'https://github.com/o/r/releases/tag/v9.2.0' 'GitHub: sürüm sayfası'
Assert-Eq $x.Notes 'Notlar' 'GitHub: sürüm notları'
$x = ConvertFrom-UpdateInfo (J ($gh -replace '"digest":"sha256:[A-Fa-f0-9]{64}"\}\]\}', '"digest":null}]}'))
Assert-True ($x.Ok -eq $true -and $x.Download -eq $false -and $x.Why -match 'SHA-256' -and $x.Version -eq '9.2.0') 'GitHub: özetsiz ek yalnızca duyurulur, indirme kapalı'
$x = ConvertFrom-UpdateInfo (J '{"tag_name":"v9.2.0","html_url":"https://github.com/o/r/releases/tag/v9.2.0","assets":[]}')
Assert-True ($x.Ok -eq $true -and $x.Download -eq $false -and $x.Why -match 'adresi yok') 'GitHub: ek yoksa kapalı'
$x = ConvertFrom-UpdateInfo (J '{"tag_name":"v9.2.0"}')
Assert-True ($x.Ok -eq $true -and $x.Download -eq $false) 'GitHub: ek alanı hiç yoksa çökmez'
$x = ConvertFrom-UpdateInfo (J ('{"tag_name":"v9.2.0","assets":[{"name":"multimizer-9.2.0.ZIP","browser_download_url":"https://github.com/o/r/releases/download/v9.2.0/m.zip","size":1,"digest":"sha256:' + $sha + '"}]}'))
Assert-True ($x.Download -eq $true) 'GitHub: ek adındaki harf büyüklüğü önemsiz'
$x = ConvertFrom-UpdateInfo (J ('{"tag_name":"v9.2.0","assets":[{"name":"Multimizer-9.2.0.zip","browser_download_url":"http://github.com/x/Multimizer-9.2.0.zip","size":1,"digest":"sha256:' + $sha + '"}]}'))
Assert-True ($x.Download -eq $false -and $x.Why -match 'güvenli değil') 'GitHub: http ek adresi kapatılır'
$x = ConvertFrom-UpdateInfo (J '{"tag_name":"v9.2.0","assets":[{"name":"Multimizer-9.2.0.zip","browser_download_url":"https://github.com/x/m.zip","digest":"md5:abcdef"}]}')
Assert-True ($x.Download -eq $false -and $x.Why -match 'SHA-256') 'GitHub: sha256 dışı özet kabul edilmez'
foreach ($alg in @('sha512', 'sha1', 'md5', 'sha384', 'blake3', 'sha256x')) {
    $x = ConvertFrom-UpdateInfo (J ('{"tag_name":"v9.2.0","assets":[{"name":"Multimizer-9.2.0.zip","browser_download_url":"https://github.com/x/m.zip","digest":"' + $alg + ':' + $sha + '"}]}'))
    Assert-True ($x.Download -eq $false -and $x.Why -match 'SHA-256') ('GitHub: 64 haneli ama başka algoritma etiketli özet kabul edilmez [' + $alg + ']')
}
$x = ConvertFrom-UpdateInfo (J ('{"tag_name":"v9.2.0","assets":[{"name":"Multimizer-9.2.0.zip","browser_download_url":"https://github.com/x/m.zip","digest":"' + $sha + '"}]}'))
Assert-True ($x.Download -eq $false -and $x.Why -match 'SHA-256') 'GitHub: etiketsiz özet kabul edilmez'
$x = ConvertFrom-UpdateInfo (J ('{"tag_name":"v9.2.0","assets":[{"name":"Multimizer-9.2.0.zip","browser_download_url":"https://github.com/x/m.zip","digest":"SHA256:' + $sha + '"}]}'))
Assert-True ($x.Download -eq $true -and $x.Sha256 -eq $sha) 'GitHub: sha256 etiketinde harf büyüklüğü önemsiz'
$x = ConvertFrom-UpdateInfo (J ('{"version":"9.5.0","tag_name":"v1.0.0","url":"https://example.com/a.zip","sha256":"' + $sha + '"}'))
Assert-Eq $x.Version '9.5.0' 'bildirim: version alanı varsa tag_name yok sayılır'

# =====================================================================
#  4) gerçek HTTP katmanı (127.0.0.1 üzerindeki geçici sunucu)
# =====================================================================
$root = Join-Path ([System.IO.Path]::GetTempPath()) ('mm_upd_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
[void](New-Item -ItemType Directory -Path $root -Force)
$payload = New-Object 'byte[]' 70000
for ($i = 0; $i -lt $payload.Length; $i++) { $payload[$i] = [byte]($i % 251) }
$tcp = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0)
$tcp.Start(); $port = $tcp.LocalEndpoint.Port; $tcp.Stop()
$lst = New-Object System.Net.HttpListener
$lst.Prefixes.Add('http://127.0.0.1:' + $port + '/')
$lst.Start()
$rs = [runspacefactory]::CreateRunspace(); $rs.Open()
$psv = [powershell]::Create(); $psv.Runspace = $rs
[void]$psv.AddScript({
    param($l, $port, [byte[]]$file)
    while ($l.IsListening) {
        $ctx = $null
        try { $ctx = $l.GetContext() } catch { break }
        $res = $ctx.Response
        try {
            $path = $ctx.Request.Url.AbsolutePath
            if ($path -eq '/ok.json') {
                $b = [System.Text.Encoding]::UTF8.GetBytes('{"version":"9.1.0"}')
                $res.StatusCode = 200; $res.ContentType = 'application/json'; $res.ContentLength64 = $b.Length
                $res.OutputStream.Write($b, 0, $b.Length)
            }
            elseif ($path -eq '/redir') { $res.StatusCode = 302; $res.AddHeader('Location', '/ok.json') }
            elseif ($path -eq '/redir-abs') { $res.StatusCode = 301; $res.AddHeader('Location', ('http://127.0.0.1:' + $port + '/ok.json')) }
            elseif ($path -eq '/redir-noloc') { $res.StatusCode = 302 }
            elseif ($path -eq '/nf') { $res.StatusCode = 404; $b = [System.Text.Encoding]::UTF8.GetBytes('yok'); $res.ContentLength64 = $b.Length; $res.OutputStream.Write($b, 0, $b.Length) }
            elseif ($path -eq '/big') { $b = New-Object 'byte[]' 5000; $res.StatusCode = 200; $res.ContentLength64 = $b.Length; $res.OutputStream.Write($b, 0, $b.Length) }
            elseif ($path -eq '/chunked') {
                $res.StatusCode = 200; $res.SendChunked = $true
                $b = New-Object 'byte[]' 1000
                for ($k = 0; $k -lt 5; $k++) { $res.OutputStream.Write($b, 0, $b.Length); $res.OutputStream.Flush() }
            }
            elseif ($path -eq '/file') { $res.StatusCode = 200; $res.ContentLength64 = $file.Length; $res.OutputStream.Write($file, 0, $file.Length) }
            elseif ($path -eq '/liar') {
                # başlıkta çok büyük uzunluk bildirir, birkaç bayt gönderip bağlantıyı koparır
                $res.StatusCode = 200; $res.ContentLength64 = 9000000
                $b = New-Object 'byte[]' 10
                $res.OutputStream.Write($b, 0, $b.Length); $res.OutputStream.Flush()
                Start-Sleep -Milliseconds 150
                $res.Abort()
            }
            elseif ($path -eq '/empty') { $res.StatusCode = 200; $res.ContentLength64 = 0 }
            elseif ($path -eq '/hang') { Start-Sleep -Milliseconds 2500; $res.StatusCode = 200; $res.ContentLength64 = 0 }
            else { $res.StatusCode = 500 }
        } catch { } finally { try { $res.Close() } catch { } }
    }
}).AddArgument($lst).AddArgument($port).AddArgument($payload)
$null = $psv.BeginInvoke()
$base = 'http://127.0.0.1:' + $port

$r = Send-UpdateHop ($base + '/ok.json') '' 10000 10
Assert-True ($r.Code -eq 200 -and $r.Error -eq '') 'HTTP: 200 yanıtı'
Assert-Eq ([System.Text.Encoding]::UTF8.GetString([byte[]]$r.Bytes)) '{"version":"9.1.0"}' 'HTTP: gövde belleğe okunur'
Assert-Eq $r.Sha256 (Sha-Hex ([System.Text.Encoding]::UTF8.GetBytes('{"version":"9.1.0"}'))) 'HTTP: özet okunurken hesaplanır'
Assert-Eq $r.Length ([long]19) 'HTTP: uzunluk'
$r = Send-UpdateHop ($base + '/redir') '' 10000 10
Assert-True ($r.Code -eq 302 -and $r.Location -eq '/ok.json' -and $null -eq $r.Bytes) 'HTTP: yönlendirme izlenmez, adres döner'
$r = Send-UpdateHop ($base + '/redir-abs') '' 10000 10
Assert-True ($r.Code -eq 301 -and $r.Location -eq ($base + '/ok.json')) 'HTTP: mutlak yönlendirme adresi döner'
$r = Send-UpdateHop ($base + '/redir-noloc') '' 10000 10
Assert-True ($r.Code -eq 302 -and $r.Location -eq '') 'HTTP: Location yoksa boş'
$r = Send-UpdateHop ($base + '/nf') '' 10000 10
Assert-True ($r.Code -eq 404 -and $r.Error -eq '' -and $null -eq $r.Bytes) 'HTTP: 404 kodu hata fırlatmadan döner'
$r = Send-UpdateHop ($base + '/big') '' 1000 10
Assert-True ($r.Error -match 'büyük' -and $null -eq $r.Bytes) 'HTTP: Content-Length sınırı aşarsa gövde okunmaz'
$r = Send-UpdateHop ($base + '/big') '' 5000 10
Assert-True ($r.Error -eq '' -and $r.Length -eq 5000) 'HTTP: sınıra eşit boyut kabul edilir'
$r = Send-UpdateHop ($base + '/liar') '' 1000000 10
Assert-True ($r.Error -match 'büyük' -and $null -eq $r.Bytes -and $r.Length -eq 0) 'HTTP: başlıkta bildirilen uzunluk sınırı aşarsa gövde hiç okunmaz'
$r = Send-UpdateHop ($base + '/chunked') '' 2000 10
Assert-True ($r.Error -match 'büyük' -and $null -eq $r.Bytes) 'HTTP: uzunluğu bilinmeyen akışta sınır okunurken uygulanır'
$r = Send-UpdateHop ($base + '/chunked') '' 5000 10
Assert-True ($r.Error -eq '' -and $r.Length -eq 5000) 'HTTP: parçalı akış tamamı okunur'
$dest = Join-Path $root 'dl.bin'
$r = Send-UpdateHop ($base + '/file') $dest 1000000 10
Assert-True ($r.Code -eq 200 -and $r.Error -eq '' -and $null -eq $r.Bytes -and $r.Length -eq 70000) 'HTTP: dosyaya indirme (birden çok 64 KB okuma)'
Assert-Eq $r.Sha256 (Sha-Hex $payload) 'HTTP: dosya özeti içerikle aynı'
Assert-Eq (Sha-Hex ([System.IO.File]::ReadAllBytes($dest))) (Sha-Hex $payload) 'HTTP: yazılan dosya içeriği aynı'
Assert-True (-not [string]::IsNullOrEmpty($r.Sha256) -and $r.Sha256.Length -eq 64) 'HTTP: özet 64 hane'
$r = Send-UpdateHop ($base + '/empty') '' 1000 10
Assert-True ($r.Error -eq '' -and $r.Length -eq 0 -and $r.Sha256 -eq 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855') 'HTTP: boş gövde, boş verinin özeti'
$dest2 = Join-Path $root 'cap.bin'
$r = Send-UpdateHop ($base + '/chunked') $dest2 2000 10
Assert-True ($r.Error -match 'büyük') 'HTTP: dosyaya indirirken de sınır uygulanır'
$r = Send-UpdateHop 'http://127.0.0.1:1/x' '' 1000 3
Assert-True ($r.Error -match 'Bağlantı' -and $r.Code -eq 0) 'HTTP: bağlantı kurulamazsa hata metni'
$r = Send-UpdateHop ($base + '/hang') '' 1000 1
Assert-True ($r.Error -match 'Bağlantı') 'HTTP: zaman aşımı hata olarak döner'
Start-Sleep -Milliseconds 1800
$J = @{ Done = 0; Total = 0; Label = ''; Cancel = $true }
$r = Send-UpdateHop ($base + '/file') (Join-Path $root 'iptal.bin') 1000000 10
$J = $null
Assert-True ($r.Error -match 'İptal' -and $null -eq $r.Bytes) 'HTTP: iptal istenirse indirme okunurken durur'
Assert-True ($null -eq $J) 'HTTP: iş tablosu testten sonra temizlendi'

try { $lst.Stop(); $lst.Close() } catch { }
try { $psv.Stop(); $psv.Dispose(); $rs.Close() } catch { }

# =====================================================================
#  5) yönlendirmeleri elle izleyen yükleyici (sahte tek adım)
# =====================================================================
$script:HopMap = @{}
$script:HopLog = New-Object System.Collections.ArrayList
function Send-UpdateHop([string]$Url, [string]$Dest, [long]$MaxBytes, [int]$TimeoutSec) {
    [void]$script:HopLog.Add(@{ Url = $Url; Dest = $Dest; Max = $MaxBytes; Timeout = $TimeoutSec })
    if ($script:HopMap.ContainsKey($Url)) { return $script:HopMap[$Url] }
    return @{ Code = 404; Location = ''; Bytes = $null; Sha256 = ''; Length = [long]0; Error = '' }
}
function Hop($Code, [string]$Loc = '', $Bytes = $null, [string]$Err = '') { return @{ Code = $Code; Location = $Loc; Bytes = $Bytes; Sha256 = ('f' * 64); Length = [long]3; Error = $Err } }
$B = [System.Text.Encoding]::UTF8.GetBytes('abc')
$A1 = 'https://example.com/a'
$script:HopMap = @{ $A1 = (Hop 200 '' $B) }
$f = Invoke-UpdateFetch $A1 '' 1000
Assert-True ($f.Ok -eq $true -and $f.FinalUrl -eq $A1 -and $f.Sha256 -eq ('f' * 64) -and $f.Length -eq 3 -and $f.Error -eq '') 'yükleyici: doğrudan 200'
Assert-True ($script:HopLog.Count -eq 1 -and $script:HopLog[0].Max -eq 1000 -and $script:HopLog[0].Timeout -eq 20 -and $script:HopLog[0].Dest -eq '') 'yükleyici: sınır ve varsayılan 20 sn zaman aşımı aktarılır'
$script:HopLog.Clear()
$script:HopMap = @{ $A1 = (Hop 302 'https://cdn.example.com/b'); 'https://cdn.example.com/b' = (Hop 200 '' $B) }
$f = Invoke-UpdateFetch $A1 'C:\x\y.part' 5000 30
Assert-True ($f.Ok -eq $true -and $f.FinalUrl -eq 'https://cdn.example.com/b') 'yükleyici: https yönlendirmesi izlenir'
Assert-True ($script:HopLog.Count -eq 2 -and $script:HopLog[1].Dest -eq 'C:\x\y.part' -and $script:HopLog[1].Timeout -eq 30) 'yükleyici: hedef dosya ve zaman aşımı her adıma aktarılır'
$script:HopLog.Clear()
$script:HopMap = @{ $A1 = (Hop 301 '/rel/c'); 'https://example.com/rel/c' = (Hop 200 '' $B) }
$f = Invoke-UpdateFetch $A1 '' 5000
Assert-True ($f.Ok -eq $true -and $f.FinalUrl -eq 'https://example.com/rel/c') 'yükleyici: göreli Location mevcut adrese göre çözülür'
$script:HopMap = @{ $A1 = (Hop 302 'http://evil.example.com/b'); 'http://evil.example.com/b' = (Hop 200 '' $B) }
$script:HopLog.Clear()
$f = Invoke-UpdateFetch $A1 '' 5000
Assert-True ($f.Ok -eq $false -and $f.Error -match 'https://' -and $script:HopLog.Count -eq 1) 'yükleyici: https adresinden http adresine düşürme reddedilir, ikinci istek atılmaz'
$script:HopMap = @{ $A1 = (Hop 302 'https://user:pw@cdn.example.com/b') }
$f = Invoke-UpdateFetch $A1 '' 5000
Assert-True ($f.Ok -eq $false -and $f.Error -match 'kullanıcı adı') 'yükleyici: kullanıcı bilgili yönlendirme reddedilir'
$script:HopMap = @{ $A1 = (Hop 302 'https://cdn.example.com:8443/b') }
$f = Invoke-UpdateFetch $A1 '' 5000
Assert-True ($f.Ok -eq $false) 'yükleyici: özel kapıya yönlendirme reddedilir'
$script:HopMap = @{ $A1 = (Hop 302 '') }
$f = Invoke-UpdateFetch $A1 '' 5000
Assert-True ($f.Ok -eq $false -and $f.Error -match 'adres vermedi') 'yükleyici: Location olmayan yönlendirme'
$script:HopMap = @{ $A1 = (Hop 302 'file:///c:/windows/win.ini') }
$f = Invoke-UpdateFetch $A1 '' 5000
Assert-True ($f.Ok -eq $false) 'yükleyici: file: yönlendirmesi reddedilir'
# yönlendirme sayısı: en çok UpdateMaxHops
$script:HopMap = @{}
for ($i = 0; $i -le 8; $i++) { $script:HopMap['https://example.com/h' + $i] = (Hop 302 ('https://example.com/h' + ($i + 1))) }
$script:HopMap['https://example.com/h' + ($script:UpdateMaxHops + 1)] = (Hop 200 '' $B)
$script:HopLog.Clear()
$f = Invoke-UpdateFetch 'https://example.com/h0' '' 5000
Assert-True ($f.Ok -eq $false -and $f.Error -match 'Çok fazla yönlendirme') 'yükleyici: sınırdan fazla yönlendirme reddedilir'
Assert-Eq $script:HopLog.Count ($script:UpdateMaxHops + 1) 'yükleyici: tam olarak sınır kadar yönlendirme izlenir, ilk istek dahil'
$script:HopMap = @{}
for ($i = 0; $i -lt $script:UpdateMaxHops; $i++) { $script:HopMap['https://example.com/g' + $i] = (Hop 302 ('https://example.com/g' + ($i + 1))) }
$script:HopMap['https://example.com/g' + $script:UpdateMaxHops] = (Hop 200 '' $B)
$f = Invoke-UpdateFetch 'https://example.com/g0' '' 5000
Assert-True ($f.Ok -eq $true) 'yükleyici: sınıra kadar yönlendirme kabul edilir'
$script:HopMap = @{ $A1 = (Hop 404) }
$f = Invoke-UpdateFetch $A1 '' 5000
Assert-True ($f.Ok -eq $false -and $f.Error -match '404') 'yükleyici: 404 kodu hata metnine girer'
$script:HopMap = @{ $A1 = (Hop 304) }
$f = Invoke-UpdateFetch $A1 '' 5000
Assert-True ($f.Ok -eq $false -and $f.Error -match '304') 'yükleyici: 304 yönlendirme sayılmaz'
$script:HopMap = @{ $A1 = (Hop 500) }
Assert-True ((Invoke-UpdateFetch $A1 '' 5000).Error -match '500') 'yükleyici: 500 hatası'
$script:HopMap = @{ $A1 = (Hop 0 '' $null 'Bağlantı kurulamadı ya da kesildi: x') }
$f = Invoke-UpdateFetch $A1 '' 5000
Assert-True ($f.Ok -eq $false -and $f.Error -match 'Bağlantı kurulamadı') 'yükleyici: aktarım hatası olduğu gibi döner'
$script:HopLog.Clear()
$f = Invoke-UpdateFetch 'http://example.com/a' '' 5000
Assert-True ($f.Ok -eq $false -and $script:HopLog.Count -eq 0) 'yükleyici: http adresi için hiç istek atılmaz'
$f = Invoke-UpdateFetch '' '' 5000
Assert-True ($f.Ok -eq $false -and $script:HopLog.Count -eq 0) 'yükleyici: boş adres için hiç istek atılmaz'
$script:HopMap = @{ $A1 = (Hop 200 '' $null) }
Assert-True ((Invoke-UpdateFetch $A1 'C:\x\y.part' 5000).Ok -eq $true -and $null -eq (Invoke-UpdateFetch $A1 'C:\x\y.part' 5000).Bytes) 'yükleyici: dosyaya inen yanıtta Bytes boştur'

# =====================================================================
#  6) denetim işi
# =====================================================================
$sync = @{ DataDir = (Join-Path $root 'veri'); ScriptPath = (Join-Path $root 'app/Multimizer.ps1') }
$script:FetchLog = New-Object System.Collections.ArrayList
$script:FetchResult = $null
function Invoke-UpdateFetch([string]$Url, [string]$Dest, [long]$MaxBytes, [int]$TimeoutSec = 20) {
    [void]$script:FetchLog.Add(@{ Url = $Url; Dest = $Dest; Max = $MaxBytes; Timeout = $TimeoutSec })
    $r = $script:FetchResult
    if ($r -is [scriptblock]) { return (& $r $Url $Dest $MaxBytes) }
    return $r
}
function Body([string]$Text, [bool]$Bom = $false) {
    $e = New-Object System.Text.UTF8Encoding($false)
    $b = $e.GetBytes($Text)
    if ($Bom) { $b = [byte[]](@(0xEF, 0xBB, 0xBF) + $b) }
    return @{ Ok = $true; Bytes = $b; Sha256 = 'x'; Length = [long]$b.Length; FinalUrl = 'https://example.com/m.json'; Error = '' }
}
$mj = '{"version":"9.1.0","url":"https://example.com/Multimizer-9.1.0.zip","sha256":"' + $sha + '","size":123,"notes":"Yenilikler"}'
$script:FetchResult = Body $mj
$o = Job_UpdateCheck @{ Url = 'https://example.com/m.json'; Current = '9.0.0' }
Assert-True ($o.Ok -eq $true -and $o.Newer -eq $true -and $o.Latest -eq '9.1.0' -and $o.Current -eq '9.0.0' -and $o.Error -eq '') 'denetim: yeni sürüm bulunur'
Assert-True ($o.Info.Download -eq $true -and $o.Info.Sha256 -eq $sha -and $o.Info.Notes -eq 'Yenilikler') 'denetim: bildirim ayrıntıları işe taşınır'
Assert-True ($o.At -match '^\d{2}\.\d{2}\.\d{4} \d{2}:\d{2}$') 'denetim: zaman damgası biçimi'
Assert-True ($script:FetchLog.Count -eq 1 -and $script:FetchLog[0].Url -eq 'https://example.com/m.json' -and $script:FetchLog[0].Dest -eq '' -and $script:FetchLog[0].Max -eq $script:UpdateMaxManifest) 'denetim: tek istek, bellek içi, bildirim boyut sınırıyla'
Assert-True ($script:UpdateMaxManifest -le 1048576 -and $script:UpdateMaxManifest -ge 65536) 'denetim: bildirim boyut sınırı makul'
Assert-True (@($script:WhLog | Where-Object { $_ -match '^INFO\|Güncelleme denetimi: example.com' }).Count -eq 1 -and @($script:WhLog | Where-Object { $_ -match '^OK\|Yeni sürüm var: 9.1.0' }).Count -eq 1) 'denetim: günlük satırları (ana makine adı, sonuç)'
Assert-True (@($script:WhLog | Where-Object { $_ -match 'example.com/m.json' -or $_ -match $sha }).Count -eq 0) 'denetim: günlüğe tam adres ya da özet yazılmaz'
$o = Job_UpdateCheck @{ Url = 'https://example.com/m.json'; Current = '9.1.0' }
Assert-True ($o.Ok -eq $true -and $o.Newer -eq $false -and $o.Latest -eq '9.1.0') 'denetim: aynı sürüm güncel sayılır'
$o = Job_UpdateCheck @{ Url = 'https://example.com/m.json'; Current = '10.0.0' }
Assert-True ($o.Ok -eq $true -and $o.Newer -eq $false) 'denetim: çalışan sürüm yayımlanandan yeniyse güncelleme önerilmez'
$script:FetchResult = Body $mj $true
Assert-True ((Job_UpdateCheck @{ Url = 'https://example.com/m.json'; Current = '9.0.0' }).Ok -eq $true) 'denetim: BOM içeren JSON okunur'
$script:FetchLog.Clear()
$script:FetchResult = Body '{"tag_name":"v9.3.0","html_url":"https://github.com/ttibett/Multimizer/releases/tag/v9.3.0","assets":[]}'
$o = Job_UpdateCheck @{ Url = 'https://github.com/ttibett/Multimizer'; Current = '9.0.0' }
Assert-True ($o.Ok -eq $true -and $o.Newer -eq $true -and $o.Latest -eq '9.3.0') 'denetim: GitHub depo adresiyle çalışır'
Assert-Eq $script:FetchLog[0].Url $api 'denetim: depo adresi API adresine çevrilip istenir'
$script:FetchResult = @{ Ok = $false; Bytes = $null; Sha256 = ''; Length = [long]0; FinalUrl = $api; Error = 'Sunucu 404 yanıtı verdi.' }
$o = Job_UpdateCheck @{ Url = 'https://github.com/ttibett/Multimizer'; Current = '9.0.0' }
Assert-True ($o.Ok -eq $false -and $o.Error -match '404' -and $o.Error -match 'gizli') 'denetim: GitHub 404 için ipucu eklenir'
$o = Job_UpdateCheck @{ Url = 'https://example.com/m.json'; Current = '9.0.0' }
Assert-True ($o.Ok -eq $false -and $o.Error -match '404' -and $o.Error -notmatch 'gizli') 'denetim: ipucu yalnızca GitHub API için'
$script:FetchResult = Body 'bu json değil'
$o = Job_UpdateCheck @{ Url = 'https://example.com/m.json'; Current = '9.0.0' }
Assert-True ($o.Ok -eq $false -and $o.Error -match 'JSON') 'denetim: bozuk JSON'
$script:FetchResult = Body ''
Assert-True ((Job_UpdateCheck @{ Url = 'https://example.com/m.json'; Current = '9.0.0' }).Ok -eq $false) 'denetim: boş yanıt'
$script:FetchResult = Body '{"version":"yok"}'
$o = Job_UpdateCheck @{ Url = 'https://example.com/m.json'; Current = '9.0.0' }
Assert-True ($o.Ok -eq $false -and $o.Error -match 'sürüm numarası') 'denetim: geçersiz sürüm numarası'
$script:FetchResult = @{ Ok = $false; Bytes = $null; Sha256 = ''; Length = [long]0; FinalUrl = ''; Error = 'Bağlantı kurulamadı ya da kesildi: x' }
$o = Job_UpdateCheck @{ Url = 'https://example.com/m.json'; Current = '9.0.0' }
Assert-True ($o.Ok -eq $false -and $o.Error -match 'Bağlantı' -and @($script:WhLog | Where-Object { $_ -match '^ERR\|Güncelleme denetimi başarısız' }).Count -ge 1) 'denetim: bağlantı hatası günlüğe ve sonuca yazılır'
$script:FetchLog.Clear()
foreach ($bad in @('', 'http://example.com/m.json', 'ftp://x/y', 'https://u:p@example.com/m.json')) {
    $o = Job_UpdateCheck @{ Url = $bad; Current = '9.0.0' }
    Assert-True ($o.Ok -eq $false -and $o.Error -ne '') ('denetim: geçersiz adres işi başlatmaz [' + $bad + ']')
}
Assert-Eq $script:FetchLog.Count 0 'denetim: geçersiz adreslerde hiç istek atılmaz'
$o = Job_UpdateCheck $null
Assert-True ($o.Ok -eq $false -and $script:FetchLog.Count -eq 0) 'denetim: parametresiz çağrı çökmez, istek atmaz'
$script:FetchResult = Body $mj
$o = Job_UpdateCheck @{ Url = 'https://example.com/m.json' }
Assert-True ($o.Ok -eq $true -and $o.Newer -eq $false) 'denetim: çalışan sürüm verilmezse yeni sayılmaz'

# =====================================================================
#  7) indirme işi
# =====================================================================
$script:WhLog.Clear(); $script:FetchLog.Clear()
$dlPayload = [System.Text.Encoding]::UTF8.GetBytes('zip-icerigi-' + ('x' * 100))
$dlSha = Sha-Hex $dlPayload
$script:FetchResult = {
    param($Url, $Dest, $Max)
    [System.IO.File]::WriteAllBytes($Dest, $script:DlBytes)
    return @{ Ok = $true; Bytes = $null; Sha256 = (Sha-Hex $script:DlBytes); Length = [long]$script:DlBytes.Length; FinalUrl = $Url; Error = '' }
}
$script:DlBytes = $dlPayload
$updDir = Join-Path $sync.DataDir 'Guncelleme'
Assert-Eq (Get-UpdateDir) $updDir 'indirme: klasör veri klasörünün altındaki Guncelleme'
$P = @{ Url = 'https://example.com/dl/Multimizer-9.1.0.zip'; Sha256 = $dlSha.ToUpperInvariant(); Version = '9.1.0'; Size = 123 }
$o = Job_UpdateDownload $P
$final = Join-Path $updDir 'Multimizer-9.1.0.zip'
Assert-True ($o.Ok -eq $true -and $o.Already -eq $false -and $o.Path -eq $final -and $o.Sha256 -eq $dlSha -and $o.Size -eq $dlPayload.Length -and $o.Error -eq '') 'indirme: özet tutunca dosya yerine konur'
Assert-True ((Test-Path -LiteralPath $final -PathType Leaf) -and -not (Test-Path -LiteralPath ($final + '.indiriliyor'))) 'indirme: kalıcı dosya var, geçici dosya yok'
Assert-Eq (Sha-Hex ([System.IO.File]::ReadAllBytes($final))) $dlSha 'indirme: dosya içeriği doğru'
Assert-True ($script:FetchLog.Count -eq 1 -and $script:FetchLog[0].Dest -eq ($final + '.indiriliyor') -and $script:FetchLog[0].Max -eq $script:UpdateMaxDownload -and $script:FetchLog[0].Timeout -eq 30) 'indirme: önce geçici dosyaya, indirme boyut sınırıyla'
Assert-True ($script:UpdateMaxDownload -le 524288000 -and $script:UpdateMaxDownload -ge 52428800) 'indirme: boyut sınırı makul'
Assert-True (@($script:WhLog | Where-Object { $_ -match '^OK\|Güncelleme indirildi ve SHA-256 özeti doğrulandı' }).Count -eq 1) 'indirme: günlük satırı'
# aynı sürüm yeniden istenirse ağa gitmez
$script:FetchLog.Clear()
$o = Job_UpdateDownload $P
Assert-True ($o.Ok -eq $true -and $o.Already -eq $true -and $o.Path -eq $final -and $script:FetchLog.Count -eq 0) 'indirme: özeti doğru dosya zaten varsa yeniden indirilmez'
# bozulmuş dosya yeniden indirilir
[System.IO.File]::WriteAllText($final, 'bozuk')
$o = Job_UpdateDownload $P
Assert-True ($o.Ok -eq $true -and $o.Already -eq $false -and $script:FetchLog.Count -eq 1 -and (Sha-Hex ([System.IO.File]::ReadAllBytes($final))) -eq $dlSha) 'indirme: özeti tutmayan eski dosya yenisiyle değişir'
# özet uyuşmazlığı
Remove-Item -LiteralPath $final -Force
$script:FetchLog.Clear()
$P2 = @{ Url = 'https://example.com/dl/Multimizer-9.1.0.zip'; Sha256 = $sha; Version = 'v9.1.0'; Size = 1 }
$o = Job_UpdateDownload $P2
Assert-True ($o.Ok -eq $false -and $o.Error -match 'uyuşmadı' -and $o.Error -match 'silindi') 'indirme: özet uyuşmazsa hata'
Assert-True (-not (Test-Path -LiteralPath $final) -and -not (Test-Path -LiteralPath ($final + '.indiriliyor'))) 'indirme: özet uyuşmazsa hiçbir dosya kalmaz'
Assert-True (@($script:WhLog | Where-Object { $_ -match '^ERR\|İndirilen dosyanın SHA-256' }).Count -eq 1) 'indirme: uyuşmazlık günlüğe ERR olarak yazılır'
# v öneki dosya adına girmez
$script:DlBytes = $dlPayload
$o = Job_UpdateDownload @{ Url = 'https://example.com/dl/x.zip'; Sha256 = $dlSha; Version = 'v9.2.0' }
Assert-True ($o.Ok -eq $true -and (Split-Path -Leaf $o.Path) -eq 'Multimizer-9.2.0.zip') 'indirme: dosya adı v öneksiz'
# aktarım hatası
Remove-Item -LiteralPath (Join-Path $updDir 'Multimizer-9.2.0.zip') -Force
$script:FetchResult = {
    param($Url, $Dest, $Max)
    [System.IO.File]::WriteAllBytes($Dest, [byte[]](1, 2, 3))
    return @{ Ok = $false; Bytes = $null; Sha256 = ''; Length = [long]0; FinalUrl = $Url; Error = 'Dosya beklenenden büyük (sınır 300 MB).' }
}
$o = Job_UpdateDownload @{ Url = 'https://example.com/dl/x.zip'; Sha256 = $dlSha; Version = '9.3.0' }
Assert-True ($o.Ok -eq $false -and $o.Error -match 'büyük') 'indirme: aktarım hatası sonuca yazılır'
Assert-True (@(Get-ChildItem -LiteralPath $updDir -Filter '*9.3.0*').Count -eq 0) 'indirme: yarım kalan geçici dosya silinir'
# geçersiz girdiler ağa gitmez, dosya bırakmaz
$script:FetchLog.Clear()
$cases = @(
    @{ N = 'http adresi'; P = @{ Url = 'http://example.com/a.zip'; Sha256 = $dlSha; Version = '9.1.0' } },
    @{ N = 'zip olmayan adres'; P = @{ Url = 'https://example.com/a.exe'; Sha256 = $dlSha; Version = '9.1.0' } },
    @{ N = 'kısa özet'; P = @{ Url = 'https://example.com/a.zip'; Sha256 = 'abc'; Version = '9.1.0' } },
    @{ N = 'özet yok'; P = @{ Url = 'https://example.com/a.zip'; Sha256 = ''; Version = '9.1.0' } },
    @{ N = 'sürüm yok'; P = @{ Url = 'https://example.com/a.zip'; Sha256 = $dlSha; Version = '' } },
    @{ N = 'yol kaçışlı sürüm'; P = @{ Url = 'https://example.com/a.zip'; Sha256 = $dlSha; Version = '..\..\evil' } },
    @{ N = 'komutlu sürüm'; P = @{ Url = 'https://example.com/a.zip'; Sha256 = $dlSha; Version = '9.1.0;calc' } },
    @{ N = 'kullanıcı bilgili adres'; P = @{ Url = 'https://u:p@example.com/a.zip'; Sha256 = $dlSha; Version = '9.1.0' } }
)
foreach ($c in $cases) {
    $o = Job_UpdateDownload $c.P
    Assert-True ($o.Ok -eq $false -and $o.Error -ne '') ('indirme: geçersiz girdi reddedilir (' + $c.N + ')')
}
Assert-Eq $script:FetchLog.Count 0 'indirme: geçersiz girdilerde hiç istek atılmaz'
Assert-True ((Job_UpdateDownload $null).Ok -eq $false) 'indirme: parametresiz çağrı çökmez'
Assert-True (@(Get-ChildItem -LiteralPath $updDir -File).Count -eq 0) 'indirme: hatalı denemelerden sonra klasörde artık dosya kalmaz'
# klasör oluşturulamıyorsa
$blockedRoot = Join-Path $root 'engelli'
[void](New-Item -ItemType Directory -Path $blockedRoot -Force)
[System.IO.File]::WriteAllText((Join-Path $blockedRoot 'Guncelleme'), 'x')
$sync = @{ DataDir = $blockedRoot; ScriptPath = '' }
$script:FetchLog.Clear()
$o = Job_UpdateDownload $P
Assert-True ($o.Ok -eq $false -and $o.Error -match 'klasörü oluşturulamadı' -and $script:FetchLog.Count -eq 0) 'indirme: indirme klasörü oluşturulamazsa hata verir, ağa gitmez'
$sync = @{ DataDir = (Join-Path $root 'veri'); ScriptPath = (Join-Path $root 'app/Multimizer.ps1') }

# =====================================================================
#  8) dosya bütünlüğü
# =====================================================================
$app = Join-Path $root 'app'
[void](New-Item -ItemType Directory -Path (Join-Path $app 'veri'), (Join-Path $app 'Eklenti') -Force)
$t1 = "satir 1`nsatir 2`n"
[System.IO.File]::WriteAllText((Join-Path $app 'veri/a.txt'), $t1.Replace("`n", "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
[System.IO.File]::WriteAllText((Join-Path $app 'veri/b.txt'), "iki`n", (New-Object System.Text.UTF8Encoding($false)))
[System.IO.File]::WriteAllText((Join-Path $app 'Eklenti/c.ps1'), "degismis`n", (New-Object System.Text.UTF8Encoding($false)))
[System.IO.File]::WriteAllText($sync.ScriptPath, 'betik-icerigi', (New-Object System.Text.UTF8Encoding($false)))
$script:PackHash = @{
    'veri/a.txt' = (Get-TextSha256 $t1)
    'veri/b.txt' = (Get-TextSha256 "iki`n")
    'veri/yok.txt' = ('ab' * 32)
    'Eklenti/c.ps1' = (Get-TextSha256 "orijinal`n")
}
$pi = Get-PackIntegrity
Assert-True ($pi.Total -eq 4 -and $pi.Good -eq 2 -and @($pi.Bad).Count -eq 2) 'bütünlük: dört dosyadan ikisi sorunlu'
$kinds = @{}; foreach ($b in $pi.Bad) { $kinds[[string]$b.Rel] = [string]$b.Kind }
Assert-True ($kinds['veri/yok.txt'] -eq 'missing' -and $kinds['Eklenti/c.ps1'] -eq 'hash') 'bütünlük: eksik ve değişmiş dosya türleri'
Assert-True (-not $kinds.ContainsKey('veri/a.txt')) 'bütünlük: satır sonu (CRLF/LF) farkı sorun sayılmaz'
$script:WhLog.Clear()
$ji = Job_IntegrityCheck @{}
Assert-True ($ji.Ok -eq $true -and $ji.Total -eq 4 -and $ji.Good -eq 2 -and @($ji.Bad).Count -eq 2 -and $ji.Error -eq '') 'bütünlük işi: sonuç'
Assert-Eq $ji.ScriptSha256 (Sha-Hex ([System.Text.Encoding]::UTF8.GetBytes('betik-icerigi'))) 'bütünlük işi: betiğin kendi SHA-256 özeti'
Assert-Eq $ji.ScriptPath $sync.ScriptPath 'bütünlük işi: betik yolu'
Assert-True (@($script:WhLog | Where-Object { $_ -match '^WARN\|Dosya bütünlüğü: 2 / 4' }).Count -eq 1 -and @($script:WhLog | Where-Object { $_ -match '^WARN\|  sorunlu: ' }).Count -eq 2) 'bütünlük işi: sorunlu dosyalar günlüğe WARN'
Assert-True ($ji.At -match '^\d{2}\.\d{2}\.\d{4} \d{2}:\d{2}$') 'bütünlük işi: zaman damgası'
$script:PackHash = @{ 'veri/a.txt' = (Get-TextSha256 $t1); 'veri/b.txt' = (Get-TextSha256 "iki`n") }
$script:WhLog.Clear()
$ji = Job_IntegrityCheck @{}
Assert-True ($ji.Ok -eq $true -and $ji.Good -eq 2 -and @($ji.Bad).Count -eq 0) 'bütünlük işi: sorun yoksa'
Assert-True (@($script:WhLog | Where-Object { $_ -match '^OK\|Dosya bütünlüğü: 2 / 2 yan dosya doğru' }).Count -eq 1) 'bütünlük işi: sorun yoksa OK satırı'
$sync = @{ DataDir = $root; ScriptPath = (Join-Path $root 'yok/Multimizer.ps1') }
$ji = Job_IntegrityCheck @{}
Assert-True ($ji.Ok -eq $true -and $ji.ScriptSha256 -eq '' -and $ji.ScriptPath -eq '') 'bütünlük işi: betik dosyası bulunamazsa özet boş'
$sync = @{ DataDir = (Join-Path $root 'veri'); ScriptPath = (Join-Path $root 'app/Multimizer.ps1') }

# =====================================================================
#  9) görünüm kuralları (saf mantık)
# =====================================================================
$m = Get-UpdateStateModel $null '9.0.0'
Assert-True ($m.Kind -eq 'dim' -and $m.CanGet -eq $false -and $m.Page -eq '' -and $m.Text -match 'kendiliğinden hiçbir adrese bağlanmaz' -and $m.Text -match '9\.0\.0') 'görünüm: denetim öncesi metin kendiliğinden bağlanmadığını söyler'
$newer = @{ Ok = $true; Current = '9.0.0'; Latest = '9.1.0'; Newer = $true; Error = ''; At = '09.11.2026 14:31'; Info = (ConvertFrom-UpdateInfo (J $mjson)) }
$m = Get-UpdateStateModel $newer '9.0.0'
Assert-True ($m.Kind -eq 'warn' -and $m.CanGet -eq $true -and $m.Page -eq 'https://example.com/s' -and $m.Text -match 'Yeni sürüm var: 9\.1\.0' -and $m.Text -match 'İndirme hazır' -and $m.Text -match '3 MB' -and $m.Text -match '09\.11\.2026 14:31' -and $m.Text -match 'onayınız') 'görünüm: yeni sürüm, indirilebilir'
$off = @{ Ok = $true; Current = '9.0.0'; Latest = '9.1.0'; Newer = $true; Error = ''; At = 'x'; Info = (ConvertFrom-UpdateInfo (J '{"version":"9.1.0","page":"https://example.com/s"}')) }
$m = Get-UpdateStateModel $off '9.0.0'
Assert-True ($m.Kind -eq 'warn' -and $m.CanGet -eq $false -and $m.Text -match 'İndirme kapalı: Bildirimde indirme adresi yok' -and $m.Page -eq 'https://example.com/s') 'görünüm: indirme kapalıysa nedeni söylenir, sayfa düğmesi kalır'
$same = @{ Ok = $true; Current = '9.1.0'; Latest = '9.1.0'; Newer = $false; Error = ''; At = 'x'; Info = (ConvertFrom-UpdateInfo (J $mjson)) }
$m = Get-UpdateStateModel $same '9.1.0'
Assert-True ($m.Kind -eq 'good' -and $m.CanGet -eq $false -and $m.Text -match 'Güncelsiniz') 'görünüm: güncel'
$m = Get-UpdateStateModel $same '10.0.0'
Assert-True ($m.Kind -eq 'good' -and $m.CanGet -eq $false -and $m.Text -match 'daha yeni') 'görünüm: çalışan sürüm daha yeni'
$m = Get-UpdateStateModel $same 'abc'
Assert-True ($m.Kind -eq 'warn' -and $m.Text -match 'karşılaştırılamadı') 'görünüm: çalışan sürüm okunamazsa uyarı'
$m = Get-UpdateStateModel @{ Ok = $false; Error = 'Sunucu 404 yanıtı verdi.' } '9.0.0'
Assert-True ($m.Kind -eq 'bad' -and $m.Text -match 'Denetim yapılamadı: Sunucu 404' -and $m.CanGet -eq $false) 'görünüm: hata'
$m = Get-UpdateStateModel @{ Ok = $false; Error = '' } '9.0.0'
Assert-True ($m.Text -match 'bilinmeyen hata') 'görünüm: hata metni boşsa bilinmeyen hata'
$ci = Get-UpdateConfirmText (ConvertFrom-UpdateInfo (J $mjson))
Assert-True ($ci -match 'Multimizer 9\.1\.0 indirilecek' -and $ci -match 'example\.com' -and $ci -match 'SHA-256' -and $ci -match 'çalıştırılmaz' -and $ci -match 'kimliğini kanıtlamaz' -and $ci -match 'Kur / güncelle') 'onay metni: kaynak, özet, çalıştırılmama ve sınırlar'
Assert-True ($ci -notmatch 'dl/Multimizer' -and $ci -notmatch $sha) 'onay metni: tam adres ve özet gösterilmez'
$d = Get-UpdateDoneModel @{ Ok = $true; Path = 'C:\x\Multimizer-9.1.0.zip'; Size = 2900000; Already = $false }
Assert-True ($d.Kind -eq 'good' -and $d.Path -eq 'C:\x\Multimizer-9.1.0.zip' -and $d.Text -match 'İndirildi ve SHA-256 özeti doğrulandı' -and $d.Text -match 'Kur / güncelle' -and $d.Text -match 'dokunmaz') 'indirme sonucu: başarı'
$d = Get-UpdateDoneModel @{ Ok = $true; Path = 'C:\x\a.zip'; Size = 0; Already = $true }
Assert-True ($d.Text -match 'zaten indirilmiş') 'indirme sonucu: zaten var'
$d = Get-UpdateDoneModel @{ Ok = $false; Error = 'özet uyuşmadı' }
Assert-True ($d.Kind -eq 'bad' -and $d.Path -eq '' -and $d.Text -match 'İndirilemedi: özet uyuşmadı') 'indirme sonucu: hata'
$d = Get-UpdateDoneModel $null
Assert-True ($d.Kind -eq 'bad' -and $d.Text -match 'İnternet istekleri') 'indirme sonucu: iş sonuç vermediyse internet anahtarı ipucu'
$g = Get-IntegrityModel @{ Ok = $true; Total = 9; Good = 9; Bad = @(); ScriptSha256 = ('1f' * 32); At = 'x' } $false
Assert-True ($g.Kind -eq 'good' -and $g.Text -match '9 / 9' -and $g.Text -notmatch '1f1f') 'bütünlük görünümü: sorun yok, kullanıcı kipinde özet gösterilmez'
$g = Get-IntegrityModel @{ Ok = $true; Total = 9; Good = 9; Bad = @(); ScriptSha256 = ('1f' * 32); At = 'x' } $true
Assert-True ($g.Text -match ('Betiğin SHA-256 özeti: ' + ('1f' * 32))) 'bütünlük görünümü: uzman kipinde betik özeti gösterilir'
$g = Get-IntegrityModel @{ Ok = $true; Total = 9; Good = 6; Bad = @(@{ Rel = 'veri/oui.txt'; Kind = 'missing' }, @{ Rel = 'Eklenti/Bellek.ps1'; Kind = 'hash' }, @{ Rel = 'Eklenti/Kurtarma.ps1'; Kind = 'read' }); ScriptSha256 = ''; At = 'x' } $false
Assert-True ($g.Kind -eq 'warn' -and $g.Text -match 'veri/oui\.txt \(yok\)' -and $g.Text -match 'Bellek\.ps1 \(özeti uyuşmuyor\)' -and $g.Text -match 'Kurtarma\.ps1 \(okunamadı\)' -and $g.Text -match 'yeniden çıkarın') 'bütünlük görünümü: sorunlu dosyalar ve nedenleri'
$g = Get-IntegrityModel @{ Ok = $false; Error = 'x' } $false
Assert-True ($g.Kind -eq 'bad' -and $g.Text -match 'Denetlenemedi: x') 'bütünlük görünümü: hata'
$g = Get-IntegrityModel $null $false
Assert-True ($g.Kind -eq 'bad' -and $g.Text -match 'bilinmeyen hata') 'bütünlük görünümü: sonuç yoksa'
$g = Get-IntegrityModel @{ Ok = $true; Total = 2; Good = 2; At = 'x' } $false
Assert-True ($g.Kind -eq 'good') 'bütünlük görünümü: Bad alanı hiç yoksa sorun yok sayılır'

# =====================================================================
# 10) Ayarlar kartı akışı (sahte arayüzle)
# =====================================================================
$ui = @{}
foreach ($n in @('st_UpdUrl', 'st_UpdCheck', 'st_UpdGet', 'st_UpdPage', 'st_UpdFolder', 'st_UpdState', 'st_IntCheck', 'st_IntState')) { $ui[$n] = New-FakeCtl }
$ui.st_UpdGet.Visibility = $script:VisOff; $ui.st_UpdPage.Visibility = $script:VisOff; $ui.st_UpdFolder.Visibility = $script:VisOff
$script:Settings = @{ UpdateUrl = '' }
$script:SaveCount = 0
function Save-Settings($S) { $script:SaveCount++ }
function Get-Br([string]$Key) { return $Key }
$script:AppVersion = '9.0.0'
$script:UiState = @{ Mode = 'Kullanici' }
$script:StLoading = $false
Reset-Fake
function Click($Ctl) { foreach ($h in @($Ctl.Handlers)) { & $h $Ctl $null } }
function Vis($Ctl) { return ([string]$Ctl.Visibility -eq $script:VisOn) }

Load-StUpdate
Assert-Eq $ui.st_UpdUrl.Text '' 'kart: adres kutusu ayardan dolar'
Assert-True ($ui.st_UpdState.Text -match 'kendiliğinden hiçbir adrese bağlanmaz' -and $ui.st_UpdState.Foreground -eq 'BrDim') 'kart: ilk metin ve renk'
Assert-True (-not (Vis $ui.st_UpdGet) -and -not (Vis $ui.st_UpdPage) -and -not (Vis $ui.st_UpdFolder) -and $ui.st_UpdCheck.IsEnabled -eq $true -and $ui.st_IntCheck.IsEnabled -eq $true) 'kart: başlangıçta indir/sayfa/klasör gizli, denetim düğmeleri açık'
Init-StUpdate
foreach ($n in @('st_UpdUrl', 'st_UpdCheck', 'st_UpdGet', 'st_UpdPage', 'st_UpdFolder', 'st_IntCheck')) { Assert-True ($ui[$n].Handlers.Count -ge 1) ('kart: işleyici bağlı ' + $n) }
# adres yok
Click $ui.st_UpdCheck
Assert-True ($script:Asyncs.Count -eq 0 -and (Get-LastToast).K -eq 'warn' -and (Get-LastToast).T -match 'Önce') 'kart: adres yokken iş başlamaz, uyarı çıkar'
# geçersiz adres
$ui.st_UpdUrl.Text = 'http://example.com/m.json'
Click $ui.st_UpdCheck
Assert-True ($script:Asyncs.Count -eq 0 -and $script:SaveCount -eq 0 -and (Get-LastToast).T -match 'https://' -and $script:Settings.UpdateUrl -eq '') 'kart: http adresi kaydedilmez ve iş başlamaz'
# geçerli adres
$ui.st_UpdUrl.Text = '  https://example.com/m.json  '
Click $ui.st_UpdCheck
Assert-Eq $script:Settings.UpdateUrl 'https://example.com/m.json' 'kart: adres kırpılıp ayara yazılır'
Assert-Eq $script:SaveCount 1 'kart: ayar bir kez kaydedilir'
Assert-True ($script:Asyncs.Count -eq 1 -and $script:Asyncs[0].Entry -eq 'Job_UpdateCheck' -and $script:Asyncs[0].Params.Url -eq 'https://example.com/m.json' -and $script:Asyncs[0].Params.Current -eq '9.0.0') 'kart: denetim işi doğru parametrelerle başlar'
Assert-True ($script:UpdBusy -eq $true -and $ui.st_UpdCheck.IsEnabled -eq $false) 'kart: iş sürerken Denetle kapalı'
Click $ui.st_UpdCheck
Assert-Eq $script:Asyncs.Count 1 'kart: iş sürerken ikinci denetim başlamaz'
# sonuç: yeni sürüm
& $script:Asyncs[0].OnDone $newer
Assert-True ($script:UpdBusy -eq $false -and $ui.st_UpdCheck.IsEnabled -eq $true) 'kart: iş bitince düğme açılır'
Assert-True ((Vis $ui.st_UpdGet) -and (Vis $ui.st_UpdPage) -and -not (Vis $ui.st_UpdFolder) -and $ui.st_UpdState.Text -match 'Yeni sürüm var: 9\.1\.0' -and $ui.st_UpdState.Foreground -eq 'BrWarn') 'kart: yeni sürümde İndir ve Sürüm sayfası görünür, renk uyarı'
Assert-True ((Get-LastToast).K -eq 'warn' -and (Get-LastToast).T -match '^Yeni sürüm var' -and (Get-LastToast).T -notmatch "`n") 'kart: bildirim yalnızca ilk satırı taşır'
# indir: önce onay
Reset-Fake
Click $ui.st_UpdGet
Assert-True ($script:Asyncs.Count -eq 0 -and $script:Confirms.Count -eq 1 -and $script:Confirms[0].Title -eq 'Güncellemeyi indir' -and $script:Confirms[0].Ok -eq 'İndir' -and $script:Confirms[0].Danger -eq $false) 'kart: İndir onay penceresi açar, onaydan önce iş başlamaz'
Assert-True ($script:Confirms[0].Text -match 'SHA-256' -and $script:Confirms[0].Text -match 'example\.com') 'kart: onay metni kaynak ve özet kuralını söyler'
& $script:Confirms[0].OnOk
Assert-True ($script:Asyncs.Count -eq 1 -and $script:Asyncs[0].Entry -eq 'Job_UpdateDownload' -and $script:Asyncs[0].Params.Url -eq 'https://example.com/dl/Multimizer-9.1.0.zip' -and $script:Asyncs[0].Params.Sha256 -eq $sha -and $script:Asyncs[0].Params.Version -eq '9.1.0' -and $script:Asyncs[0].Params.Size -eq 2900000) 'kart: onaydan sonra indirme işi bildirimdeki değerlerle başlar'
Assert-True ($script:UpdBusy -eq $true -and $ui.st_UpdGet.IsEnabled -eq $false -and $ui.st_UpdCheck.IsEnabled -eq $false) 'kart: indirirken düğmeler kapalı'
$okDl = @{ Ok = $true; Path = (Join-Path $updDir 'Multimizer-9.1.0.zip'); Size = 2900000; Sha256 = $sha; Already = $false; Error = '' }
$od = $script:Asyncs[0].OnDone
Reset-Fake
& $od $okDl
Assert-True ($script:UpdBusy -eq $false -and $script:UpdGot -eq $okDl.Path -and (Vis $ui.st_UpdFolder)) 'kart: indirme sonrası klasör düğmesi görünür'
Assert-True ($ui.st_UpdState.Text -match 'Yeni sürüm var' -and $ui.st_UpdState.Text -match 'İndirildi ve SHA-256 özeti doğrulandı' -and $ui.st_UpdState.Foreground -eq 'BrWarn') 'kart: durum metni denetim ve indirme sonucunu birlikte gösterir'
Assert-True ((Get-LastToast).K -eq 'good' -and (Get-LastToast).T -match '^İndirildi') 'kart: indirme bildirimi'
Click $ui.st_UpdFolder
Assert-True ($script:Opened.Contains('folder:' + $updDir)) 'kart: klasör düğmesi indirme klasörünü açar'
# sayfa
Reset-Fake
Click $ui.st_UpdPage
Assert-True ($script:Opened.Count -eq 1 -and $script:Opened[0] -eq 'url:https://example.com/s') 'kart: Sürüm sayfası doğrulanmış adresi açar'
$script:UpdLast = @{ Ok = $true; Current = '9.0.0'; Latest = '9.1.0'; Newer = $true; Error = ''; At = 'x'; Info = @{ Page = 'javascript:alert(1)'; Download = $false; Why = 'x'; Version = '9.1.0'; Notes = '' } }
Reset-Fake
Click $ui.st_UpdPage
Assert-Eq $script:Opened.Count 0 'kart: güvensiz sayfa adresi açılmaz'
$script:UpdLast = $newer
# başarısız indirme
Reset-Fake
$script:UpdBusy = $true
Complete-UpdateDownload @{ Ok = $false; Error = 'İndirilen dosyanın SHA-256 özeti bildirimdekiyle uyuşmadı; güvenliğiniz için dosya silindi.' }
Assert-True ($script:UpdBusy -eq $false -and $ui.st_UpdState.Foreground -eq 'BrBad' -and $ui.st_UpdState.Text -match 'İndirilemedi' -and (Get-LastToast).K -eq 'bad') 'kart: indirme hatası kırmızı gösterilir'
Complete-UpdateDownload $null
Assert-True ($ui.st_UpdState.Text -match 'İnternet istekleri' -and (Get-LastToast).K -eq 'bad') 'kart: indirme işi sonuç vermezse internet anahtarı ipucu'
# denetim hata / null
$script:UpdBusy = $true
Complete-UpdateCheck $null
Assert-True ($script:UpdBusy -eq $false -and $ui.st_UpdState.Foreground -eq 'BrBad' -and $ui.st_UpdState.Text -match 'İnternet istekleri' -and -not (Vis $ui.st_UpdGet)) 'kart: denetim işi sonuç vermezse (ör. anahtar kapalı) açıklayıcı hata'
Complete-UpdateCheck @{ Ok = $true; Current = '9.0.0'; Latest = '9.0.0'; Newer = $false; Error = ''; At = '09.11.2026 14:31'; Info = (ConvertFrom-UpdateInfo (J '{"version":"9.0.0"}')) }
Assert-True ($ui.st_UpdState.Foreground -eq 'BrGood' -and $ui.st_UpdState.Text -match 'Güncelsiniz' -and -not (Vis $ui.st_UpdGet) -and -not (Vis $ui.st_UpdPage)) 'kart: güncelken İndir/sayfa gizli, yeşil'
Assert-True ($ui.st_UpdState.Text -notmatch 'İndirildi') 'kart: yeni denetim sonucu eski indirme mesajını temizler'
# adres değişince eski sonuç düşer
$script:UpdLast = $newer; $script:UpdDone = @{ Text = 'eski'; Kind = 'good' }
$ui.st_UpdUrl.Text = 'https://example.com/baska.json'
$lf = $ui.st_UpdUrl.Handlers[0]
$before = $script:SaveCount
& $lf $ui.st_UpdUrl $null
Assert-True ($script:Settings.UpdateUrl -eq 'https://example.com/baska.json' -and $script:SaveCount -eq $before + 1 -and $null -eq $script:UpdLast -and $null -eq $script:UpdDone -and -not (Vis $ui.st_UpdGet)) 'kart: adres değişince kaydedilir, eski sonuç ve indirme düğmesi düşer'
& $lf $ui.st_UpdUrl $null
Assert-Eq $script:SaveCount ($before + 1) 'kart: değişmeyen adres yeniden kaydedilmez'
$ui.st_UpdUrl.Text = 'ftp://x'
& $lf $ui.st_UpdUrl $null
Assert-True ($script:Settings.UpdateUrl -eq 'https://example.com/baska.json' -and (Get-LastToast).K -eq 'warn') 'kart: odak kaybında geçersiz adres kaydedilmez, uyarı çıkar'
$ui.st_UpdUrl.Text = ''
& $lf $ui.st_UpdUrl $null
Assert-Eq $script:Settings.UpdateUrl '' 'kart: adres silinirse özellik kapanır (boş adres kaydedilir)'
$script:StLoading = $true
$ui.st_UpdUrl.Text = 'https://example.com/z.json'
& $lf $ui.st_UpdUrl $null
Assert-Eq $script:Settings.UpdateUrl '' 'kart: sayfa yüklenirken (StLoading) odak olayı kayıt yapmaz'
$script:StLoading = $false
# İş başlatılamazsa bayraklar sıfırlanır
$ui.st_UpdUrl.Text = 'https://example.com/m.json'; $script:Settings.UpdateUrl = 'https://example.com/m.json'
function Start-Async { param([string]$Name, [string]$Entry, $Params = $null, [scriptblock]$OnDone = $null, [string]$Label = '', [bool]$Quiet = $false, [bool]$Queue = $false) return $false }
$script:UpdBusy = $false
Click $ui.st_UpdCheck
Assert-True ($script:UpdBusy -eq $false -and $ui.st_UpdCheck.IsEnabled -eq $true) 'kart: iş başlatılamazsa Denetle yeniden açılır'
$script:UpdLast = $newer
Reset-Fake
Click $ui.st_UpdGet
& $script:Confirms[0].OnOk
Assert-True ($script:UpdBusy -eq $false -and $ui.st_UpdGet.IsEnabled -eq $true) 'kart: indirme başlatılamazsa düğmeler yeniden açılır'
$script:IntBusy = $false
Click $ui.st_IntCheck
Assert-True ($script:IntBusy -eq $false -and $ui.st_IntCheck.IsEnabled -eq $true) 'kart: bütünlük işi başlatılamazsa düğme yeniden açılır'
. "$PSScriptRoot/uifake.ps1"
Reset-Fake
# indirilebilir sonuç yokken İndir
$script:UpdLast = $null
Start-UpdateDownload
Assert-True ($script:Confirms.Count -eq 0 -and $script:Asyncs.Count -eq 0 -and (Get-LastToast).K -eq 'warn') 'kart: denetimsiz İndir çağrısı onay penceresi açmaz'
# başka bir iş sürerken İndir çağrısı yok sayılır (düğme kapalı olsa da koruma işlev içinde)
Reset-Fake
$script:UpdLast = $newer
$script:UpdBusy = $true
Start-UpdateDownload
Assert-True ($script:Confirms.Count -eq 0 -and $script:Asyncs.Count -eq 0) 'kart: iş sürerken İndir çağrısı onay penceresi açmaz'
$script:UpdBusy = $false
# bütünlük
Reset-Fake
$script:IntBusy = $false
Click $ui.st_IntCheck
Assert-True ($script:Asyncs.Count -eq 1 -and $script:Asyncs[0].Entry -eq 'Job_IntegrityCheck' -and $script:IntBusy -eq $true -and $ui.st_IntCheck.IsEnabled -eq $false) 'kart: bütünlük işi başlar, düğme kapanır'
Click $ui.st_IntCheck
Assert-Eq $script:Asyncs.Count 1 'kart: bütünlük işi sürerken ikinci başlamaz'
& $script:Asyncs[0].OnDone @{ Ok = $true; Total = 9; Good = 9; Bad = @(); ScriptSha256 = ('1f' * 32); At = 'x' }
Assert-True ($script:IntBusy -eq $false -and $ui.st_IntCheck.IsEnabled -eq $true -and $ui.st_IntState.Foreground -eq 'BrGood' -and $ui.st_IntState.Text -match '9 / 9' -and $ui.st_IntState.Text -notmatch '1f1f') 'kart: bütünlük sonucu yeşil, kullanıcı kipinde özet yok'
$script:UiState.Mode = 'Expert'
Complete-IntegrityCheck @{ Ok = $true; Total = 9; Good = 8; Bad = @(@{ Rel = 'veri/oui.txt'; Kind = 'hash' }); ScriptSha256 = ('1f' * 32); At = 'x' }
Assert-True ($ui.st_IntState.Foreground -eq 'BrWarn' -and $ui.st_IntState.Text -match 'oui\.txt' -and $ui.st_IntState.Text -match '1f1f' -and (Get-LastToast).K -eq 'warn') 'kart: uzman kipinde sorun ve betik özeti gösterilir'
$script:UiState.Mode = 'Kullanici'
Complete-IntegrityCheck $null
Assert-True ($ui.st_IntState.Foreground -eq 'BrBad') 'kart: bütünlük işi sonuç vermezse hata'
# Settings sayfası yeniden gösterilince sonuç korunur
$script:UpdLast = $newer; $script:UpdDone = $null
Load-StUpdate
Assert-True ($ui.st_UpdState.Text -match 'Yeni sürüm var' -and (Vis $ui.st_UpdGet)) 'kart: sayfa yeniden açılınca son sonuç korunur'

# =====================================================================
# 11) yapı: kendiliğinden bağlanmaz, komut listesi, kablolama
# =====================================================================
function Get-FnText([string]$Name) { $f = @($script:AllFns | Where-Object { $_.Name -eq $Name }) | Select-Object -Last 1; if ($null -eq $f) { return '' }; return $f.Extent.Text }
function Get-FnCmds([string]$Name) {
    $f = @($script:AllFns | Where-Object { $_.Name -eq $Name }) | Select-Object -Last 1
    if ($null -eq $f) { return }
    foreach ($c in $f.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)) { $c.GetCommandName() }
}
# Çağıran işlevleri bulur: bu işlev adını komut olarak çağıran ya da dize olarak anan tüm işlevler
function Get-Callers([string]$Target) {
    $out = New-Object System.Collections.ArrayList
    foreach ($f in $script:AllFns) {
        $hit = $false
        foreach ($c in $f.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)) { if ($c.GetCommandName() -eq $Target) { $hit = $true } }
        foreach ($s in $f.FindAll({ param($n) $n -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $n.Value -eq $Target }, $true)) { $hit = $true }
        if ($hit -and $f.Name -ne $Target) { [void]$out.Add($f.Name) }
    }
    return , @($out | Sort-Object -Unique)
}
$updFns = @('ConvertTo-AppVersionParts', 'Compare-AppVersion', 'Test-UpdateUrl', 'ConvertTo-UpdateFeedUrl', 'Format-UpdateNotes', 'ConvertFrom-UpdateInfo', 'Send-UpdateHop', 'Invoke-UpdateFetch', 'Job_UpdateCheck', 'Get-UpdateDir', 'Job_UpdateDownload', 'Get-PackIntegrity', 'Job_IntegrityCheck')
$allowed = @('get-jsonprop', 'test-updateurl', 'convertto-appversionparts', 'compare-appversion', 'convertto-updatefeedurl', 'format-updatenotes', 'convertfrom-updateinfo', 'send-updatehop', 'invoke-updatefetch',
    'get-updatedir', 'get-packintegrity', 'get-packfiletext', 'test-jobcancel', 'set-jobprogress', 'write-whlog', 'format-size', 'new-object', 'join-path', 'test-path', 'new-item', 'remove-item', 'move-item', 'get-item',
    'get-filehash', 'convertfrom-json', 'get-date', 'where-object', 'sort-object')
foreach ($fn in $updFns) {
    $bad = @(Get-FnCmds $fn | Where-Object { $_ -and $allowed -notcontains $_.ToLowerInvariant() })
    Assert-True ($bad.Count -eq 0) ('yapı: ' + $fn + ' yalnızca izinli komutları çağırır' + $(if ($bad.Count) { ' (' + ($bad -join ',') + ')' } else { '' }))
}
$coreText = ($updFns | ForEach-Object { Get-FnText $_ }) -join "`n"
foreach ($pat in @('Start-Process', 'Invoke-Expression', '\biex\b', 'Expand-Archive', 'Invoke-WebRequest', 'Invoke-RestMethod', 'Start-BitsTransfer', 'Invoke-Item', 'WebClient', 'DownloadFile', 'DownloadString', 'Add-Type', 'Set-ExecutionPolicy', 'Register-ScheduledTask', 'Set-ItemProperty', 'New-ItemProperty', 'netsh', 'schtasks', 'ZipFile', 'Assembly\]::Load')) {
    Assert-True ($coreText -notmatch $pat) ('yapı: güncelleme çekirdeği ' + $pat + ' kullanmaz')
}
Assert-True ($coreText -match 'AllowAutoRedirect = \$false') 'yapı: otomatik yönlendirme kapalı (yönlendirmeleri uygulama kendisi doğrular)'
Assert-True ($coreText -match 'SecurityProtocolType\]::Tls12') 'yapı: TLS 1.2'
Assert-True ((Get-FnText 'Send-UpdateHop') -notmatch 'Credentials = \[System.Net.NetworkCredential\]' -and (Get-FnText 'Send-UpdateHop') -notmatch 'Authorization') 'yapı: kimlik bilgisi ya da yetki başlığı gönderilmez'
Assert-True ((Get-FnText 'Send-UpdateHop') -notmatch 'Headers\.Add|Headers\[''(?!Location)' -and (Get-FnText 'Send-UpdateHop') -notmatch 'MachineName|UserName|COMPUTERNAME|USERNAME|USERDOMAIN|Get-CimInstance|Get-WmiObject') 'yapı: istekte ek başlık, bilgisayar ya da kullanıcı adı yok'
Assert-Eq $script:UpdateAgent 'Multimizer-Guncelleme' 'yapı: kullanıcı aracı adı sabit, sürüm ya da bilgisayar bilgisi içermez'

# kendiliğinden çalışmaz: tetikleyici yalnızca düğme işleyicileri
Assert-Eq ((Get-Callers 'Start-UpdateCheck') -join ',') 'Init-StUpdate' 'yapı: Start-UpdateCheck yalnızca Ayarlar kartı düğmesinden çağrılır'
Assert-Eq ((Get-Callers 'Start-UpdateDownload') -join ',') 'Init-StUpdate' 'yapı: Start-UpdateDownload yalnızca İndir düğmesinden çağrılır'
Assert-Eq ((Get-Callers 'Job_UpdateCheck') -join ',') 'Start-UpdateCheck' 'yapı: denetim işi yalnızca Start-UpdateCheck içinden başlatılır'
Assert-Eq ((Get-Callers 'Job_UpdateDownload') -join ',') 'Start-UpdateDownload' 'yapı: indirme işi yalnızca Start-UpdateDownload içinden başlatılır'
Assert-Eq ((Get-Callers 'Invoke-UpdateFetch') -join ',') 'Job_UpdateCheck,Job_UpdateDownload' 'yapı: ağ istekleri yalnızca iki iş tarafından yapılır'
Assert-Eq ((Get-Callers 'Send-UpdateHop') -join ',') 'Invoke-UpdateFetch' 'yapı: tek adım istekçisi yalnızca Invoke-UpdateFetch tarafından çağrılır'
$dlAst = @($script:AllFns | Where-Object { $_.Name -eq 'Start-UpdateDownload' }) | Select-Object -Last 1
$dlCmds = @($dlAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true))
$conf = @($dlCmds | Where-Object { $_.GetCommandName() -eq 'Show-Confirm' })
$asy = @($dlCmds | Where-Object { $_.GetCommandName() -eq 'Start-Async' })
Assert-True ($conf.Count -eq 1 -and $asy.Count -eq 1 -and $asy[0].Extent.StartOffset -ge $conf[0].Extent.StartOffset -and $asy[0].Extent.EndOffset -le $conf[0].Extent.EndOffset) 'yapı: indirme işi yalnızca Show-Confirm onay bloğunun içinde başlatılır'
$uses = @($script:AllFns | Where-Object { $_.Extent.Text -match '\.UpdateUrl\b|\bUpdateUrl\s+=' } | ForEach-Object { $_.Name } | Sort-Object -Unique)
Assert-Eq ($uses -join ',') 'Get-DefaultSettings,Load-StUpdate,Save-StUpdateUrl,Start-UpdateCheck' 'yapı: UpdateUrl ayarına yalnızca varsayılanlar ve Ayarlar kartı dokunur'
Assert-True ($src -match "UpdateUrl\s+= ''") 'ayar: UpdateUrl varsayılanı boş (özellik kapalı)'
# ayarlar sayfası kablolaması
$ls = Get-FnText 'Load-StExtra'; $ip = Get-FnText 'Init-Page_settings'
Assert-True ($ls -match 'Load-StUpdate' -and $ls.IndexOf('Load-StUpdate') -gt $ls.IndexOf('Render-StNet')) 'kablolama: Load-StExtra Load-StUpdate çağırır'
Assert-True ($ip -match 'Init-StUpdate' -and $ip.IndexOf('Init-StUpdate') -lt $ip.IndexOf('Init-StExtra')) 'kablolama: Init-Page_settings Init-StUpdate çağırır'
$pageText = $src
foreach ($n in @('st_UpdUrl', 'st_UpdCheck', 'st_UpdGet', 'st_UpdPage', 'st_UpdFolder', 'st_UpdState', 'st_IntCheck', 'st_IntState')) {
    Assert-True ([regex]::Matches($pageText, 'x:Name="' + $n + '"').Count -eq 1) ('kablolama: XAML adı tek ' + $n)
}
Assert-True ($src -match 'x:Name="st_UpdGet"[^>]*Visibility="Collapsed"' -and $src -match 'x:Name="st_UpdPage"[^>]*Visibility="Collapsed"' -and $src -match 'x:Name="st_UpdFolder"[^>]*Visibility="Collapsed"') 'kablolama: İndir, sayfa ve klasör düğmeleri başta gizli'
Assert-True ($src -match 'x:Name="st_UpdUrl" MaxLength="600"') 'kablolama: adres kutusu 600 karakterle sınırlı'
# internet anahtarı
$ua = @($script:Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$script:NetFeatures[''update'']' }, $true))
Assert-Eq $ua.Count 1 'internet anahtarı: update kaydı tek yerde eklenir'
. ([scriptblock]::Create($ua[0].Extent.Text))
Assert-True ($script:NetFeatures.Contains('update') -and @($script:NetFeatures['update'].Jobs).Count -eq 2 -and @($script:NetFeatures['update'].Jobs) -contains 'Job_UpdateCheck' -and @($script:NetFeatures['update'].Jobs) -contains 'Job_UpdateDownload') 'internet anahtarı: iki iş de update anahtarına bağlı'
Assert-True ([string]$script:NetFeatures['update'].T -ne '' -and [string]$script:NetFeatures['update'].D -match 'bastığınızda' -and [string]$script:NetFeatures['update'].D -match 'kişisel veri gönderilmez') 'internet anahtarı: açıklama kullanıcı başlatmasını ve verisizliği söyler'
function Get-NetOffList { return @($script:FakeOff) }
$script:FakeOff = @()
Assert-True ((Test-NetBlocked 'Job_UpdateCheck') -eq $false -and (Test-NetBlocked 'Job_UpdateDownload') -eq $false) 'internet anahtarı: açıkken iş engellenmez'
$script:FakeOff = @('update')
Assert-True ((Test-NetBlocked 'Job_UpdateCheck') -eq $true -and (Test-NetBlocked 'Job_UpdateDownload') -eq $true -and (Test-NetBlocked 'Job_Ping') -eq $false -and (Test-NetBlocked 'Job_IntegrityCheck') -eq $false) 'internet anahtarı: kapalıyken yalnızca iki güncelleme işi engellenir, bütünlük denetimi (ağsız) engellenmez'
Assert-True ((Get-NetBlockText 'Job_UpdateCheck') -match 'Güncelleme denetimi ve indirme' -and (Get-NetBlockText 'Job_UpdateCheck') -match 'kapalı') 'internet anahtarı: engel metni özelliğin adını söyler'
$script:FakeOff = @()
# Duman turu
Assert-True ($script:SmokeSafe -contains 'st_IntCheck' -and $script:SmokeSafe -notcontains 'st_UpdCheck' -and $script:SmokeSafe -notcontains 'st_UpdGet') 'Duman: bütünlük düğmesi güvenli, ağ kullanan düğmeler değil'
$acts = @(Get-SmokeActions | Where-Object { $_[2] -eq 'st_IntCheck' })
Assert-True ($acts.Count -eq 1 -and $acts[0][0] -eq 'settings' -and $acts[0][1] -eq '') 'Duman: tur Ayarlar sayfasında bütünlük denetimini açar'
Assert-True (@(Get-SmokeActions | Where-Object { $_[2] -match '^st_Upd' }).Count -eq 0) 'Duman: tur ağ kullanan güncelleme düğmelerine basmaz'
# derlenen metinde başlıkta söz verilen kurallar
Assert-True ($src -match 'releases/latest' -and $src -match 'Multimizer-\[0-9\]\+' ) 'belge: GitHub besleme biçimi kodda tanımlı'
Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
Show-Result
