# ==================================================================
#  GÜNCELLEME DENETİMİ (isteğe bağlı; yalnızca siz başlatınca)
#  Uygulama kendiliğinden hiçbir adrese bağlanmaz. “Güncellemeleri denetle”ye basınca Ayarlar’da verdiğiniz HTTPS adresinden küçük bir
#  bildirim dosyası (JSON) okunur: yalnızca sürüm numarası, indirme adresi ve SHA-256 özeti. Kimlik, bilgisayar adı ya da başka veri gönderilmez.
#  İndirme yalnızca onayınızla yapılır; dosyanın SHA-256 özeti bildirimdekiyle tutmazsa dosya silinir. Hiçbir şey kendiliğinden kurulmaz ya da çalıştırılmaz.
#  Bildirim biçimi (kendi dosyanız):  { "version": "9.0.1", "url": "https://.../Multimizer-9.0.1.zip", "sha256": "64 onaltılık hane", "size": 2900000, "notes": "...", "page": "https://..." }
#  GitHub’ın “releases/latest” yanıtı da okunur (tag_name, Multimizer-*.zip eki, ekin sha256 özeti); özet yoksa yalnızca duyurulur, indirme kapalı kalır.
#  SHA-256 dosyanın bozulmadığını ve yolda değişmediğini gösterir; yayıncı hesabının ele geçirilmesine karşı koruma değildir.
# ==================================================================
$script:UpdateMaxManifest = 262144
$script:UpdateMaxDownload = 314572800
$script:UpdateMaxHops = 5
$script:UpdateAgent = 'Multimizer-Guncelleme'

# '9.0.1' ya da 'v9.0.1' -> dört sayı; geçersizse $null
function ConvertTo-AppVersionParts([string]$V) {
    $t = $V.Trim()
    if ($t.StartsWith('v', [StringComparison]::OrdinalIgnoreCase)) { $t = $t.Substring(1) }
    if ($t -notmatch '^[0-9]{1,5}(\.[0-9]{1,5}){1,3}\z') { return $null }
    $parts = New-Object System.Collections.ArrayList
    foreach ($p in $t.Split('.')) { [void]$parts.Add([int]$p) }
    while ($parts.Count -lt 4) { [void]$parts.Add(0) }
    return , $parts.ToArray()
}

# -1: A < B, 0: eşit, 1: A > B, $null: karşılaştırılamaz (biçim geçersiz)
function Compare-AppVersion([string]$A, [string]$B) {
    $pa = ConvertTo-AppVersionParts $A
    $pb = ConvertTo-AppVersionParts $B
    if ($null -eq $pa -or $null -eq $pb) { return $null }
    for ($i = 0; $i -lt 4; $i++) {
        if ($pa[$i] -lt $pb[$i]) { return -1 }
        if ($pa[$i] -gt $pb[$i]) { return 1 }
    }
    return 0
}

# '' = adres kullanılabilir, aksi halde nedeni. Yalnızca HTTPS, kullanıcı bilgisiz, varsayılan kapı.
function Test-UpdateUrl([string]$Url) {
    if ([string]::IsNullOrWhiteSpace($Url)) { return 'Önce güncelleme bildirim adresini (HTTPS) girin.' }
    if ($Url.Length -gt 600 -or $Url -match '[\s\x00-\x1f]') { return 'Adres geçersiz (boşluk ya da denetim karakteri içeriyor, ya da çok uzun).' }
    $u = $null
    if (-not [System.Uri]::TryCreate($Url, [System.UriKind]::Absolute, [ref]$u)) { return 'Adres geçersiz.' }
    if ($u.Scheme -ne 'https') { return 'Adres https:// ile başlamalı; şifresiz bağlantı kullanılmaz.' }
    if ($u.UserInfo -ne '') { return 'Adres kullanıcı adı ya da parola içeremez.' }
    if ($u.Host -eq '' -or -not $u.IsDefaultPort) { return 'Adres geçersiz (sunucu adı yok ya da özel bir kapı kullanıyor).' }
    return ''
}

# Bir GitHub deposunun adresi (https://github.com/sahip/depo) verildiyse, o deponun “en son sürüm” API adresine çevirir.
# Başka adresler olduğu gibi kalır; geçersiz adres de değişmeden döner (denetimi Test-UpdateUrl yapar).
function ConvertTo-UpdateFeedUrl([string]$Url) {
    $t = $Url.Trim()
    if ((Test-UpdateUrl $t) -ne '') { return $t }
    $u = New-Object System.Uri($t)
    if ($u.Host -ne 'github.com' -and $u.Host -ne 'www.github.com') { return $t }
    $seg = @($u.AbsolutePath.Trim('/').Split('/') | Where-Object { $_ -ne '' })
    if ($seg.Count -lt 2) { return $t }
    $owner = [string]$seg[0]
    $repo = ([string]$seg[1]) -replace '(?i)\.git\z', ''
    if ($owner -cnotmatch '^[A-Za-z0-9][A-Za-z0-9\-]{0,38}\z') { return $t }
    if ($repo -cnotmatch '^[A-Za-z0-9._\-]{1,100}\z' -or $repo -match '^\.+\z') { return $t }
    if ($seg.Count -gt 2 -and [string]$seg[2] -ne 'releases') { return $t }
    return ('https://api.github.com/repos/' + $owner + '/' + $repo + '/releases/latest')
}

# Bildirimdeki metni düz ve kısa tutar: denetim karakterleri atılır, en çok 600 karakter
function Format-UpdateNotes([string]$Text) {
    $t = ($Text -replace '[\x00-\x08\x0b\x0c\x0e-\x1f]', '').Trim()
    $t = ($t -replace '\r\n', "`n" -replace '\n{3,}', "`n`n")
    if ($t.Length -gt 600) { $t = $t.Substring(0, 597) + '...' }
    return $t
}

# Bildirim nesnesini (ConvertFrom-Json çıktısı) doğrular.
# Dönüş: @{ Ok; Version; Url; Sha256; Size; Notes; Page; Download; Why; Error }   Ok = sürüm okunabildi, Download = güvenle indirilebilir
function ConvertFrom-UpdateInfo($Obj) {
    $r = @{ Ok = $false; Version = ''; Url = ''; Sha256 = ''; Size = [long]0; Notes = ''; Page = ''; Download = $false; Why = ''; Error = '' }
    if ($null -eq $Obj) { $r.Error = 'Bildirim dosyası boş.'; return $r }
    $ver = [string](Get-JsonProp $Obj 'version')
    $url = [string](Get-JsonProp $Obj 'url')
    $sha = [string](Get-JsonProp $Obj 'sha256')
    $size = Get-JsonProp $Obj 'size'
    $notes = [string](Get-JsonProp $Obj 'notes')
    $page = [string](Get-JsonProp $Obj 'page')
    $tag = [string](Get-JsonProp $Obj 'tag_name')
    if ($ver -eq '' -and $tag -ne '') {
        $ver = $tag
        $page = [string](Get-JsonProp $Obj 'html_url')
        $notes = [string](Get-JsonProp $Obj 'body')
        foreach ($a in @(Get-JsonProp $Obj 'assets')) {
            $nm = [string](Get-JsonProp $a 'name')
            if ($nm -match '(?i)^Multimizer-[0-9]+(\.[0-9]+){1,3}\.zip\z') {
                $url = [string](Get-JsonProp $a 'browser_download_url')
                $size = Get-JsonProp $a 'size'
                $dg = [string](Get-JsonProp $a 'digest')
                if ($dg -match '(?i)^sha256:([0-9a-f]{64})\z') { $sha = $Matches[1] }
                break
            }
        }
    }
    if ($null -eq (ConvertTo-AppVersionParts $ver)) { $r.Error = 'Bildirimdeki sürüm numarası geçersiz.'; return $r }
    $r.Version = $ver.Trim()
    if ($r.Version.StartsWith('v', [StringComparison]::OrdinalIgnoreCase)) { $r.Version = $r.Version.Substring(1) }
    $r.Ok = $true
    $r.Notes = Format-UpdateNotes $notes
    if ($page -ne '' -and (Test-UpdateUrl $page) -eq '') { $r.Page = $page }
    $n = [long]0
    if ($null -ne $size -and [long]::TryParse([string]$size, [ref]$n) -and $n -gt 0 -and $n -le $script:UpdateMaxDownload) { $r.Size = $n }
    if ($url -eq '') { $r.Why = 'Bildirimde indirme adresi yok.'; return $r }
    $uw = Test-UpdateUrl $url
    if ($uw -ne '') { $r.Why = 'İndirme adresi güvenli değil: ' + $uw; return $r }
    $uu = New-Object System.Uri($url)
    if ($uu.AbsolutePath -notmatch '(?i)\.zip\z') { $r.Why = 'İndirme adresi bir ZIP dosyasına çıkmıyor.'; return $r }
    if ($sha -notmatch '(?i)^[0-9a-f]{64}\z') { $r.Why = 'Bildirimde SHA-256 özeti yok; güvenliğiniz için indirme kapalı.'; return $r }
    $r.Url = $url
    $r.Sha256 = $sha.ToLowerInvariant()
    $r.Download = $true
    return $r
}

# Tek bir istek (yönlendirme izlenmez). Dest boşsa gövde belleğe okunur, doluysa dosyaya yazılır; SHA-256 okunurken hesaplanır.
# Dönüş: @{ Code; Location; Bytes; Sha256; Length; Error }
function Send-UpdateHop([string]$Url, [string]$Dest, [long]$MaxBytes, [int]$TimeoutSec) {
    $res = @{ Code = 0; Location = ''; Bytes = $null; Sha256 = ''; Length = [long]0; Error = '' }
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }
    $resp = $null
    $st = $null
    $fs = $null
    $sha = $null
    try {
        $rq = [System.Net.HttpWebRequest]::Create($Url)
        $rq.Method = 'GET'
        $rq.AllowAutoRedirect = $false
        $rq.Timeout = $TimeoutSec * 1000
        $rq.ReadWriteTimeout = $TimeoutSec * 1000
        $rq.UserAgent = [string]$script:UpdateAgent
        try { $rq.Proxy = [System.Net.WebRequest]::GetSystemWebProxy(); $rq.Proxy.Credentials = [System.Net.CredentialCache]::DefaultCredentials } catch { }
        try {
            $resp = $rq.GetResponse()
        } catch [System.Net.WebException] {
            $resp = $_.Exception.Response
            if ($null -eq $resp) { throw }
        }
        $res.Code = [int]$resp.StatusCode
        $loc = $resp.Headers['Location']
        if ($null -ne $loc) { $res.Location = [string]$loc }
        if ($res.Code -ge 200 -and $res.Code -lt 300) {
            if ($resp.ContentLength -gt $MaxBytes) { $res.Error = 'Dosya beklenenden büyük (sınır ' + (Format-Size $MaxBytes) + ').'; return $res }
            $st = $resp.GetResponseStream()
            $buf = New-Object 'byte[]' 65536
            $total = [long]0
            $ms = $null
            if ($Dest -eq '') { $ms = New-Object System.IO.MemoryStream } else { $fs = New-Object System.IO.FileStream($Dest, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None) }
            $sha = [System.Security.Cryptography.SHA256]::Create()
            while ($true) {
                $n = $st.Read($buf, 0, $buf.Length)
                if ($n -le 0) { break }
                $total += $n
                if ($total -gt $MaxBytes) { $res.Error = 'Dosya beklenenden büyük (sınır ' + (Format-Size $MaxBytes) + ').'; break }
                [void]$sha.TransformBlock($buf, 0, $n, $null, 0)
                if ($null -ne $ms) { $ms.Write($buf, 0, $n) } else { $fs.Write($buf, 0, $n) }
                if (Test-JobCancel) { $res.Error = 'İptal edildi.'; break }
            }
            if ($res.Error -eq '') {
                [void]$sha.TransformFinalBlock((New-Object 'byte[]' 0), 0, 0)
                $res.Sha256 = (([System.BitConverter]::ToString($sha.Hash)) -replace '-', '').ToLowerInvariant()
                $res.Length = $total
                if ($null -ne $ms) { $res.Bytes = $ms.ToArray() }
            }
        }
    } catch {
        $res.Error = 'Bağlantı kurulamadı ya da kesildi: ' + $_.Exception.Message
    } finally {
        if ($null -ne $fs) { try { $fs.Dispose() } catch { } }
        if ($null -ne $st) { try { $st.Dispose() } catch { } }
        if ($null -ne $resp) { try { $resp.Close() } catch { } }
        if ($null -ne $sha) { try { $sha.Dispose() } catch { } }
    }
    return $res
}

# Yönlendirmeleri elle izler: her adım HTTPS olmalı, en çok $script:UpdateMaxHops yönlendirme.
# Dönüş: @{ Ok; Bytes; Sha256; Length; FinalUrl; Error }
function Invoke-UpdateFetch([string]$Url, [string]$Dest, [long]$MaxBytes, [int]$TimeoutSec = 20) {
    $out = @{ Ok = $false; Bytes = $null; Sha256 = ''; Length = [long]0; FinalUrl = $Url; Error = '' }
    $cur = $Url
    for ($hop = 0; $hop -le $script:UpdateMaxHops; $hop++) {
        $why = Test-UpdateUrl $cur
        if ($why -ne '') { $out.Error = $why; return $out }
        $r = Send-UpdateHop $cur $Dest $MaxBytes $TimeoutSec
        if ([string]$r.Error -ne '') { $out.Error = [string]$r.Error; return $out }
        $code = [int]$r.Code
        if ($code -ge 300 -and $code -lt 400 -and $code -ne 304) {
            $loc = [string]$r.Location
            if ($loc -eq '') { $out.Error = 'Sunucu başka bir adrese yönlendirdi ama adres vermedi.'; return $out }
            $next = ''
            try { $next = (New-Object System.Uri((New-Object System.Uri($cur)), $loc)).AbsoluteUri } catch { $out.Error = 'Yönlendirme adresi geçersiz.'; return $out }
            $cur = $next
            continue
        }
        if ($code -ge 200 -and $code -lt 300) {
            $out.Ok = $true
            $out.Bytes = $r.Bytes
            $out.Sha256 = [string]$r.Sha256
            $out.Length = [long]$r.Length
            $out.FinalUrl = $cur
            return $out
        }
        $out.Error = 'Sunucu ' + [string]$code + ' yanıtı verdi.'
        return $out
    }
    $out.Error = 'Çok fazla yönlendirme.'
    return $out
}

# Denetim işi: P.Url = bildirim adresi, P.Current = çalışan sürüm
function Job_UpdateCheck($P) {
    $url = ''
    $cur = ''
    try { $url = [string]$P.Url } catch { $url = '' }
    try { $cur = [string]$P.Current } catch { $cur = '' }
    $out = @{ Ok = $false; Current = $cur; Latest = ''; Newer = $false; Info = $null; Error = ''; At = (Get-Date).ToString('dd.MM.yyyy HH:mm') }
    $why = Test-UpdateUrl $url
    if ($why -ne '') { $out.Error = $why; Write-WhLog ('Güncelleme denetimi yapılmadı: ' + $why) 'WARN'; return $out }
    $feed = ConvertTo-UpdateFeedUrl $url
    $hostName = (New-Object System.Uri($feed)).Host
    Write-WhLog ('Güncelleme denetimi: ' + $hostName + ' adresinden küçük bir bildirim dosyası okunuyor (kimlik ya da kişisel veri gönderilmez).') 'INFO'
    Set-JobProgress 0 1 'Güncelleme denetleniyor'
    $f = Invoke-UpdateFetch $feed '' $script:UpdateMaxManifest 20
    if ($f.Ok -ne $true) {
        $out.Error = [string]$f.Error
        if ($hostName -eq 'api.github.com' -and $out.Error -match '\b404\b') { $out.Error += ' Depo gizli olabilir ya da henüz bir sürüm yayımlanmamış olabilir.' }
        Write-WhLog ('Güncelleme denetimi başarısız: ' + $out.Error) 'ERR'
        return $out
    }
    $txt = ''
    try { $txt = (New-Object System.Text.UTF8Encoding($false)).GetString([byte[]]$f.Bytes).TrimStart([char]0xFEFF) } catch { $txt = '' }
    $obj = $null
    try { $obj = ConvertFrom-Json -InputObject $txt } catch { $obj = $null }
    if ($null -eq $obj) { $out.Error = 'Bildirim dosyası okunamadı (geçerli bir JSON değil).'; Write-WhLog $out.Error 'ERR'; return $out }
    $info = ConvertFrom-UpdateInfo $obj
    if ($info.Ok -ne $true) { $out.Error = [string]$info.Error; Write-WhLog ('Güncelleme bildirimi geçersiz: ' + $out.Error) 'ERR'; return $out }
    $cmp = Compare-AppVersion ([string]$info.Version) $cur
    $out.Ok = $true
    $out.Info = $info
    $out.Latest = [string]$info.Version
    $out.Newer = ($cmp -eq 1)
    if ($out.Newer) { Write-WhLog ('Yeni sürüm var: ' + $out.Latest + ' (çalışan: ' + $cur + ')') 'OK' } else { Write-WhLog ('Güncelsiniz (yayımlanan en son sürüm: ' + $out.Latest + ')') 'OK' }
    Set-JobProgress 1 1
    return $out
}

# İndirme klasörü: veri klasörünün altındaki Guncelleme
function Get-UpdateDir {
    return (Join-Path ([string]$sync.DataDir) 'Guncelleme')
}

# İndirme işi: P.Url, P.Sha256, P.Version, P.Size. Önce geçici dosyaya iner, özet tutarsa adını değiştirir; tutmazsa siler. Hiçbir şey çalıştırılmaz.
# Dönüş: @{ Ok; Path; Size; Sha256; Already; Error }
function Job_UpdateDownload($P) {
    $url = ''
    $sha = ''
    $ver = ''
    try { $url = [string]$P.Url } catch { $url = '' }
    try { $sha = ([string]$P.Sha256).ToLowerInvariant() } catch { $sha = '' }
    try { $ver = [string]$P.Version } catch { $ver = '' }
    $out = @{ Ok = $false; Path = ''; Size = [long]0; Sha256 = ''; Already = $false; Error = '' }
    $why = Test-UpdateUrl $url
    if ($why -ne '') { $out.Error = $why; Write-WhLog ('Güncelleme indirilmedi: ' + $why) 'ERR'; return $out }
    if ($sha -notmatch '^[0-9a-f]{64}\z') { $out.Error = 'SHA-256 özeti geçersiz; güvenliğiniz için indirilmedi.'; Write-WhLog $out.Error 'ERR'; return $out }
    if ($null -eq (ConvertTo-AppVersionParts $ver)) { $out.Error = 'Sürüm numarası geçersiz.'; Write-WhLog $out.Error 'ERR'; return $out }
    if ((New-Object System.Uri($url)).AbsolutePath -notmatch '(?i)\.zip\z') { $out.Error = 'İndirme adresi bir ZIP dosyasına çıkmıyor.'; Write-WhLog $out.Error 'ERR'; return $out }
    $dir = Get-UpdateDir
    $dirErr = ''
    try { if (-not (Test-Path -LiteralPath $dir -PathType Container)) { [void](New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop) } } catch { $dirErr = $_.Exception.Message }
    if ($dirErr -eq '' -and -not (Test-Path -LiteralPath $dir -PathType Container)) { $dirErr = 'o ad başka bir dosyaya ait' }
    if ($dirErr -ne '') { $out.Error = 'İndirme klasörü oluşturulamadı: ' + $dirErr; Write-WhLog $out.Error 'ERR'; return $out }
    $final = Join-Path $dir ('Multimizer-' + $ver.TrimStart('v', 'V') + '.zip')
    $tmp = $final + '.indiriliyor'
    if (Test-Path -LiteralPath $final -PathType Leaf) {
        $have = ''
        try { $have = (Get-FileHash -LiteralPath $final -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant() } catch { $have = '' }
        if ($have -eq $sha) {
            $out.Ok = $true; $out.Already = $true; $out.Path = $final; $out.Sha256 = $have
            try { $out.Size = (Get-Item -LiteralPath $final -ErrorAction Stop).Length } catch { }
            Write-WhLog ('Bu sürüm zaten indirilmiş ve özeti doğru: ' + $final) 'OK'
            return $out
        }
    }
    Write-WhLog ('Güncelleme indiriliyor (' + (New-Object System.Uri($url)).Host + '); dosya yalnızca indirilir, çalıştırılmaz.') 'STEP'
    Set-JobProgress 0 1 'Güncelleme indiriliyor'
    $f = Invoke-UpdateFetch $url $tmp $script:UpdateMaxDownload 30
    if ($f.Ok -ne $true) {
        try { if (Test-Path -LiteralPath $tmp -PathType Leaf) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue } } catch { }
        $out.Error = [string]$f.Error
        Write-WhLog ('Güncelleme indirilemedi: ' + $out.Error) 'ERR'
        return $out
    }
    if ([string]$f.Sha256 -ne $sha) {
        try { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue } catch { }
        $out.Error = 'İndirilen dosyanın SHA-256 özeti bildirimdekiyle uyuşmadı; güvenliğiniz için dosya silindi.'
        Write-WhLog $out.Error 'ERR'
        return $out
    }
    try {
        if (Test-Path -LiteralPath $final -PathType Leaf) { Remove-Item -LiteralPath $final -Force -ErrorAction Stop }
        Move-Item -LiteralPath $tmp -Destination $final -Force -ErrorAction Stop
    } catch {
        $out.Error = 'İndirilen dosya yerine konamadı: ' + $_.Exception.Message
        Write-WhLog $out.Error 'ERR'
        return $out
    }
    $out.Ok = $true
    $out.Path = $final
    $out.Size = [long]$f.Length
    $out.Sha256 = [string]$f.Sha256
    Write-WhLog ('Güncelleme indirildi ve SHA-256 özeti doğrulandı: ' + $final) 'OK'
    Set-JobProgress 1 1
    return $out
}

# Dosya bütünlüğü: derleme sırasında betiğe yazılan özetlerle yan dosyaları (Eklenti, veri) karşılaştırır. Yalnızca okur.
# Dönüş: @{ Total; Good; Bad = @( @{ Rel; Kind } ) }   Kind: missing | read | hash
function Get-PackIntegrity {
    $bad = New-Object System.Collections.ArrayList
    $keys = @($script:PackHash.Keys | Sort-Object)
    foreach ($rel in $keys) {
        $r = Get-PackFileText ([string]$rel)
        if ($r.Ok -ne $true) { [void]$bad.Add(@{ Rel = [string]$rel; Kind = [string]$r.Kind }) }
    }
    return @{ Total = $keys.Count; Good = ($keys.Count - $bad.Count); Bad = $bad.ToArray() }
}

# Arka plan işi: yan dosyaların özetleri + çalışan betiğin kendi SHA-256 özeti (yayımlanan özetle karşılaştırmak için). Yalnızca okur.
function Job_IntegrityCheck($P) {
    $out = @{ Ok = $false; Total = 0; Good = 0; Bad = @(); ScriptPath = ''; ScriptSha256 = ''; Error = ''; At = (Get-Date).ToString('dd.MM.yyyy HH:mm') }
    try {
        Set-JobProgress 0 1 'Dosya bütünlüğü denetleniyor'
        $r = Get-PackIntegrity
        $out.Total = [int]$r.Total
        $out.Good = [int]$r.Good
        $out.Bad = @($r.Bad)
        $sp = ''
        try { $sp = [string]$sync.ScriptPath } catch { $sp = '' }
        if ($sp -ne '' -and (Test-Path -LiteralPath $sp -PathType Leaf)) {
            $out.ScriptPath = $sp
            try { $out.ScriptSha256 = (Get-FileHash -LiteralPath $sp -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant() } catch { $out.ScriptSha256 = '' }
        }
        $out.Ok = $true
        if ($out.Bad.Count -eq 0) { Write-WhLog ('Dosya bütünlüğü: ' + [string]$out.Good + ' / ' + [string]$out.Total + ' yan dosya doğru.') 'OK' }
        else {
            Write-WhLog ('Dosya bütünlüğü: ' + [string]$out.Good + ' / ' + [string]$out.Total + ' yan dosya doğru; ' + [string]$out.Bad.Count + ' dosyada sorun var.') 'WARN'
            foreach ($b in $out.Bad) { Write-WhLog ('  sorunlu: ' + [string]$b.Rel + ' (' + [string]$b.Kind + ')') 'WARN' }
        }
        Set-JobProgress 1 1
    } catch {
        $out.Error = $_.Exception.Message
        Write-WhLog ('Dosya bütünlüğü denetlenemedi: ' + $out.Error) 'ERR'
    }
    return $out
}

# “İnternet istekleri” listesine eklenir; kapatılırsa iki iş de hiç başlamaz.
$script:NetFeatures['update'] = @{ T = 'Güncelleme denetimi ve indirme'; D = 'Yalnızca “Güncellemeleri denetle”ye bastığınızda, Ayarlar’da verdiğiniz HTTPS adresinden küçük bir sürüm bildirimi okur. İndirme ayrıca onayınızı ister; kimlik ya da kişisel veri gönderilmez.'; Jobs = @('Job_UpdateCheck', 'Job_UpdateDownload') }
