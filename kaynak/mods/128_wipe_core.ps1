# ==================================================================
#  KALICI SİLME ÇEKİRDEĞİ (9.0.0): yöntemler, süre tahmini, disk korumaları ve kimlik denetimi.
#  Burada yalnızca okuyan ve karar veren işlevler var; diske yazan kod Eklenti\DiskSilme.ps1 dosyasındadır ve yalnızca
#  kullanıcı onay verdikten sonra yüklenir. Hiçbir işlev Windows Update, Defender, Güvenlik Duvarı ya da UAC’ye dokunmaz.
#  Güvenlik kuralları:
#   1. Windows’un çalıştığı, Multimizer’ın ya da geçici dosyaların bulunduğu disklere doğrudan yazılmaz (yalnızca boş alan temizliği yapılır).
#   2. Çevrimdışı, salt okunur, depolama havuzu üyesi ve kümelenmiş disklere dokunulmaz.
#   3. Disk, onay verildiği andaki boyut, ad ve seri numarasıyla işlem anında yeniden karşılaştırılır; uyuşmazsa işlem başlamaz.
#   4. Geri döndürülemez işlemler (bölüm ya da disk silme) için hedefin adı elle yazdırılır.
# ==================================================================

# ---------------- yöntemler ----------------
# Anahtarlar: random (tek geçiş rastgele), zero (tek geçiş sıfır), dod3 (sıfır, bir, rastgele), random3 (üç geçiş rastgele)
function Get-WipeMethodKey([string]$Method) {
    $m = ([string]$Method).Trim().ToLowerInvariant()
    if (@('random', 'zero', 'dod3', 'random3') -contains $m) { return $m }
    return 'random'
}

# Geçiş desenleri: 0 = rastgele (AES-256-CTR akışı), 1 = sıfır, 2 = 0xFF
function Get-WipeModes([string]$Method) {
    switch (Get-WipeMethodKey $Method) {
        'zero'    { return , @(1) }
        'dod3'    { return , @(1, 2, 0) }
        'random3' { return , @(0, 0, 0) }
    }
    return , @(0)
}

function Get-WipeMethodName([string]$Method) {
    switch (Get-WipeMethodKey $Method) {
        'zero'    { return 'tek geçiş sıfır' }
        'dod3'    { return '3 geçiş (sıfır, bir, rastgele)' }
        'random3' { return '3 geçiş rastgele' }
    }
    return 'tek geçiş rastgele'
}

# Açılır liste öğeleri: @{ Key; Name } dizileri (arayüz New-Choice ile çevirir)
function Get-WipeMethodList {
    return , @(
        @{ Key = 'random'; Name = 'Tek geçiş rastgele (önerilir)' },
        @{ Key = 'zero'; Name = 'Tek geçiş sıfır (hızlı)' },
        @{ Key = 'dod3'; Name = '3 geçiş: sıfır, bir, rastgele' },
        @{ Key = 'random3'; Name = '3 geçiş rastgele (yavaş)' }
    )
}

function Get-WipeVerifyKey([string]$Verify) {
    $v = ([string]$Verify).Trim().ToLowerInvariant()
    if (@('none', 'sample', 'full') -contains $v) { return $v }
    return 'sample'
}

function Get-WipeVerifyList {
    return , @(
        @{ Key = 'sample'; Name = 'Doğrula: örnekle (hızlı)' },
        @{ Key = 'full'; Name = 'Doğrula: tamamını oku (yavaş)' },
        @{ Key = 'none'; Name = 'Doğrulama yapma' }
    )
}

function Get-WipeVerifyName([string]$Verify) {
    switch (Get-WipeVerifyKey $Verify) {
        'full' { return 'tamamı geri okunup karşılaştırılır' }
        'none' { return 'doğrulama yapılmaz' }
    }
    return 'örnekler geri okunup karşılaştırılır'
}

# Disk ya da bölüm silindikten sonra ne yapılsın: none (boş bırak), ntfs, exfat, fat32
function Get-WipeAfterKey([string]$After) {
    $a = ([string]$After).Trim().ToLowerInvariant()
    if (@('none', 'ntfs', 'exfat', 'fat32') -contains $a) { return $a }
    return 'none'
}

function Get-WipeAfterList {
    return , @(
        @{ Key = 'none'; Name = 'Sonra: boş bırak' },
        @{ Key = 'ntfs'; Name = 'Sonra: NTFS olarak biçimle' },
        @{ Key = 'exfat'; Name = 'Sonra: exFAT olarak biçimle' },
        @{ Key = 'fat32'; Name = 'Sonra: FAT32 olarak biçimle (en çok 32 GB)' }
    )
}

function Get-WipeAfterName([string]$After) {
    switch (Get-WipeAfterKey $After) {
        'ntfs'  { return 'NTFS olarak biçimlenir' }
        'exfat' { return 'exFAT olarak biçimlenir' }
        'fat32' { return 'FAT32 olarak biçimlenir' }
    }
    return 'boş (ayrılmamış) bırakılır'
}

# ---------------- süre ve ilerleme ----------------
function Format-WipeEta([double]$Seconds) {
    if ($Seconds -lt 0 -or [double]::IsNaN($Seconds) -or [double]::IsInfinity($Seconds)) { return 'bilinmiyor' }
    $s = [int][math]::Round($Seconds)
    if ($s -lt 45) { return 'bir dakikadan az' }
    $m = [int][math]::Round($s / 60.0)
    if ($m -lt 60) { return [string]$m + ' dk' }
    $h = [int][math]::Floor($m / 60.0)
    $mm = $m - $h * 60
    if ($h -ge 48) { return [string][int][math]::Round($h / 24.0) + ' gün' }
    if ($mm -eq 0) { return [string]$h + ' sa' }
    return [string]$h + ' sa ' + [string]$mm + ' dk'
}

# Ortama göre beklenen yazma hızı (bayt/sn). Şifre akışı üretimi de işlemciyi sınırlar (yaklaşık 450 MB/sn).
function Get-WipeRate([string]$Bus, [string]$Media) {
    $r = [double]80MB
    if ($Bus -eq 'USB') { $r = [double]25MB }
    elseif ($Media -eq 'HDD') { $r = [double]110MB }
    elseif ($Bus -eq 'NVMe') { $r = [double]450MB }
    elseif ($Media -eq 'SSD') { $r = [double]350MB }
    elseif ($Bus -eq 'SD' -or $Bus -eq 'MMC') { $r = [double]20MB }
    return $r
}

# Tahmini süre: @{ Lo; Hi (sn); Text }. Passes: yazma geçişi sayısı; Verify: none | sample | full
function Get-WipeEstimate([double]$Bytes, [int]$Passes, [string]$Verify, [string]$Bus, [string]$Media) {
    if ($Passes -lt 1) { $Passes = 1 }
    $rate = Get-WipeRate $Bus $Media
    $work = $Bytes * $Passes
    if ((Get-WipeVerifyKey $Verify) -eq 'full') { $work += $Bytes }
    elseif ((Get-WipeVerifyKey $Verify) -eq 'sample') { $work += [math]::Min($Bytes, [double]256MB) }
    $lo = $work / $rate
    $hi = $lo * 2.2
    $txt = 'yaklaşık ' + (Format-WipeEta $lo)
    if ($lo -ge 90) { $txt = 'yaklaşık ' + (Format-WipeEta $lo) + ' – ' + (Format-WipeEta $hi) }
    return @{ Lo = $lo; Hi = $hi; Text = $txt }
}

# İş paneli etiketi: "Disk 2 siliniyor · Yazılıyor · %37 · 85 MB/sn · kalan 12 dk"
function Get-WipeProgressLabel([string]$Label, [string]$Stage, [double]$Done, [double]$Total, [double]$Seconds) {
    $t = $Label
    if ($Stage -ne '') { $t += ' · ' + $Stage }
    if ($Total -gt 0) { $t += ' · %' + [string][int][math]::Floor([math]::Min($Done, $Total) * 100.0 / $Total) }
    if ($Seconds -ge 3 -and $Done -gt 0) {
        $rate = $Done / $Seconds
        $t += ' · ' + (Format-Size $rate) + '/sn'
        if ($Total -gt $Done) { $t += ' · kalan ' + (Format-WipeEta (($Total - $Done) / $rate)) }
    }
    return $t
}

# Karşılaştırma için metni sadeleştirir: Türkçe harfler ASCII karşılığına çevrilir, boşluklar tekleştirilir, küçük harfe indirilir.
# Böylece "Disk 2 Bölüm 1" yerine "disk 2 bolum 1" yazılması da kabul edilir.
function ConvertTo-WipeFold([string]$Text) {
    $s = [string]$Text
    $pairs = @(@(246, 'o'), @(214, 'o'), @(252, 'u'), @(220, 'u'), @(305, 'i'), @(304, 'i'), @(351, 's'), @(350, 's'), @(231, 'c'), @(199, 'c'), @(287, 'g'), @(286, 'g'))
    foreach ($p in $pairs) { $s = $s.Replace([string][char][int]$p[0], [string]$p[1]) }
    $s = ($s -replace '\s+', ' ').Trim()
    return $s.ToLowerInvariant()
}

# Elle yazılan onay metni eşleşiyor mu? Büyük/küçük harf, Türkçe harf ve fazla boşluk önemsenmez.
function Test-WipeTyped([string]$Typed, [string]$Expect) {
    $b = ConvertTo-WipeFold $Expect
    if ($b -eq '') { return $false }
    return ((ConvertTo-WipeFold $Typed) -eq $b)
}

# Sürücüde bırakılacak pay: toplamın %1'i (en az 512 MB); Windows sürücüsünde %3 (en az 2 GB)
function Get-WipeReserve([double]$Total, [bool]$IsOs) {
    $pct = 0.01
    $min = [double]536870912
    if ($IsOs) { $pct = 0.03; $min = [double]2147483648 }
    return [double][math]::Max($min, [math]::Floor($Total * $pct))
}

# ---------------- korumalar ----------------
# Doğrudan yazılmaması gereken sürücü harfleri: @{ 'C:' = 'neden' }
function Get-WipeProtectedLetters {
    $map = @{}
    $sd = ([string]$env:SystemDrive).Trim().ToUpperInvariant()
    if ($sd.Length -ge 2) { $map[$sd.Substring(0, 2)] = 'Windows bu sürücüde çalışıyor' }
    $adds = New-Object System.Collections.ArrayList
    $app = ''
    try { $app = [string](Get-AppFolder) } catch { $app = '' }
    [void]$adds.Add(@($app, 'Multimizer bu sürücüde çalışıyor'))
    $tmp = ''
    try { $tmp = [System.IO.Path]::GetTempPath() } catch { $tmp = '' }
    [void]$adds.Add(@($tmp, 'geçici dosyalar bu sürücüde duruyor'))
    [void]$adds.Add(@([string]$env:USERPROFILE, 'kullanıcı profili bu sürücüde'))
    foreach ($a in $adds) {
        $p = ([string]$a[0]).Trim()
        if ($p.Length -ge 2 -and $p.Substring(1, 1) -eq ':') {
            $l = $p.Substring(0, 1).ToUpperInvariant() + ':'
            if (-not $map.ContainsKey($l)) { $map[$l] = [string]$a[1] }
        }
    }
    try {
        foreach ($pf in @(Get-CimInstance -ClassName Win32_PageFileUsage -ErrorAction Stop)) {
            $n = ([string]$pf.Name).Trim()
            if ($n.Length -ge 2 -and $n.Substring(1, 1) -eq ':') {
                $l = $n.Substring(0, 1).ToUpperInvariant() + ':'
                if (-not $map.ContainsKey($l)) { $map[$l] = 'sayfa dosyası bu sürücüde' }
            }
        }
    } catch { }
    return $map
}

# Canlı disk modeli (hiçbir şey değiştirmez). Dönüş: $null (disk yok) ya da
# @{ Number; Name; Size; UniqueId; Serial; Bus; Media; Style; IsSystem; IsBoot; Offline; ReadOnly; Clustered; Pool; Sector; Letters; Roles; Parts }
# Parts: @{ Number; Offset; Size; Letter; Type; IsSystem; IsBoot; IsActive; Fs; Label }
function Get-WipeDiskLive([int]$Number) {
    $dk = $null
    try { $dk = Get-Disk -Number $Number -ErrorAction Stop } catch { return $null }
    if ($null -eq $dk) { return $null }
    $m = @{ Number = $Number; Name = ([string]$dk.FriendlyName).Trim(); Size = [double]$dk.Size; UniqueId = ([string]$dk.UniqueId).Trim(); Serial = ([string]$dk.SerialNumber).Trim()
        Bus = [string]$dk.BusType; Media = ''; Style = [string]$dk.PartitionStyle; IsSystem = ($dk.IsSystem -eq $true); IsBoot = ($dk.IsBoot -eq $true)
        Offline = ($dk.IsOffline -eq $true); ReadOnly = ($dk.IsReadOnly -eq $true); Clustered = ($dk.IsClustered -eq $true); Pool = $false; Sector = 512
        Letters = @(); Roles = @(); Parts = @() }
    try { if ([int]$dk.LogicalSectorSize -ge 512) { $m.Sector = [int]$dk.LogicalSectorSize } } catch { }
    try {
        $pd = Get-PhysicalDisk -ErrorAction Stop | Where-Object { [string]$_.DeviceId -eq [string]$Number } | Select-Object -First 1
        if ($null -ne $pd) {
            $m.Media = [string]$pd.MediaType
            try { $m.Pool = (@($pd.CannotPoolReason) -contains 'In a Pool') } catch { }
        }
    } catch { }
    $letters = New-Object System.Collections.ArrayList
    $parts = New-Object System.Collections.ArrayList
    $vols = @{}
    try { foreach ($v in @(Get-Volume -ErrorAction Stop)) { if ($v.DriveLetter) { $vols[([string]$v.DriveLetter).ToUpperInvariant() + ':'] = $v } } } catch { }
    try {
        foreach ($pt in @(Get-Partition -DiskNumber $Number -ErrorAction Stop)) {
            $l = ''
            if ($pt.DriveLetter) { $l = ([string]$pt.DriveLetter).ToUpperInvariant() + ':' }
            $fs = ''
            $lbl = ''
            if ($l -ne '' -and $vols.ContainsKey($l)) { $fs = [string]$vols[$l].FileSystem; $lbl = [string]$vols[$l].FileSystemLabel }
            [void]$parts.Add(@{ Number = [int]$pt.PartitionNumber; Offset = [double]$pt.Offset; Size = [double]$pt.Size; Letter = $l; Type = [string]$pt.Type
                IsSystem = ($pt.IsSystem -eq $true); IsBoot = ($pt.IsBoot -eq $true); IsActive = ($pt.IsActive -eq $true); Fs = $fs; Label = $lbl })
            if ($l -ne '') { [void]$letters.Add($l) }
        }
    } catch { }
    $m.Letters = $letters.ToArray()
    $m.Parts = $parts.ToArray()
    $prot = Get-WipeProtectedLetters
    $roles = New-Object System.Collections.ArrayList
    foreach ($l in $m.Letters) {
        if ($prot.ContainsKey($l)) { [void]$roles.Add(($l + ' sürücüsü: ' + [string]$prot[$l])) }
    }
    $m.Roles = $roles.ToArray()
    return $m
}

# Bu diske doğrudan yazılabilir mi? Scope: Unallocated | Partition | Disk. Dönüş: '' = uygun, aksi hâlde neden.
function Test-WipeDiskAllowed($Live, [string]$Scope) {
    if ($null -eq $Live) { return 'Disk bulunamadı (çıkarılmış olabilir).' }
    if ($Live.IsSystem -eq $true -or $Live.IsBoot -eq $true) { return 'Windows bu diskte çalışıyor. Bu diske doğrudan yazılmaz; yalnızca sürücülerin boş alanı temizlenebilir.' }
    $roles = @($Live.Roles)
    if ($roles.Count -gt 0) { return ('Bu diske doğrudan yazılmaz: ' + [string]$roles[0] + '.') }
    if ($Live.Offline -eq $true) { return 'Disk çevrimdışı. Disk Yönetimi’nden çevrimiçi yapıp yeniden deneyin.' }
    if ($Live.ReadOnly -eq $true) { return 'Disk salt okunur (yazma korumalı).' }
    if ($Live.Pool -eq $true) { return 'Disk bir depolama alanları havuzunun üyesi; havuzu Windows’tan kaldırmadan silinemez.' }
    if ($Live.Clustered -eq $true) { return 'Disk bir küme yapısının parçası; silinemez.' }
    if ([string]$Live.Bus -eq 'Spaces') { return 'Bu bir Depolama Alanları sanal diski; Windows’tan yönetilmeli.' }
    if ([double]$Live.Size -le 0) { return 'Disk boyutu okunamadı.' }
    if (@('Unallocated', 'Partition', 'Disk') -notcontains $Scope) { return 'Bilinmeyen silme kapsamı.' }
    return ''
}

# Bölüm silinebilir mi? Dönüş: '' = uygun, aksi hâlde neden.
function Test-WipePartAllowed($Live, $Part) {
    if ($null -eq $Part) { return 'Bölüm bulunamadı (disk değişmiş olabilir).' }
    if ($Part.IsSystem -eq $true -or $Part.IsBoot -eq $true) { return 'Bu bölüm Windows’a ait; silinemez.' }
    if ([double]$Part.Size -le 0) { return 'Bölüm boyutu okunamadı.' }
    return ''
}

# Onay anındaki bilgiler (Expect) işlem anındaki canlı diskle uyuşuyor mu? Dönüş: '' = uyuşuyor, aksi hâlde neden.
function Test-WipeIdentity($Live, $Expect) {
    if ($null -eq $Live) { return 'Disk bulunamadı (çıkarılmış olabilir).' }
    if ($null -eq $Expect) { return 'Disk kimliği doğrulanamadı; işlem başlatılmadı.' }
    $bad = $false
    if ($null -ne $Expect.Size -and [double]$Expect.Size -gt 0 -and [double]$Live.Size -ne [double]$Expect.Size) { $bad = $true }
    $en = ([string]$Expect.Name).Trim()
    if ($en -ne '' -and ([string]$Live.Name).Trim() -ne '' -and $en.ToLowerInvariant() -ne ([string]$Live.Name).Trim().ToLowerInvariant()) { $bad = $true }
    $eu = ([string]$Expect.UniqueId).Trim()
    if ($eu -ne '' -and ([string]$Live.UniqueId).Trim() -ne '' -and $eu.ToLowerInvariant() -ne ([string]$Live.UniqueId).Trim().ToLowerInvariant()) { $bad = $true }
    $es = ([string]$Expect.Serial).Trim()
    if ($es -ne '' -and ([string]$Live.Serial).Trim() -ne '' -and $es.ToLowerInvariant() -ne ([string]$Live.Serial).Trim().ToLowerInvariant()) { $bad = $true }
    if ($bad) { return 'Disk, onay verdiğiniz andan sonra değişmiş görünüyor (boyut, ad ya da seri numarası uyuşmuyor). Güvenliğiniz için işlem başlatılmadı; diskleri yenileyip yeniden seçin.' }
    return ''
}

# Disk satırından bir silme hedefi bilgisi çıkarır (onay anındaki kimlik): @{ Size; Name; UniqueId; Serial }
function Get-WipeExpect($Disk) {
    return @{ Size = [double]$Disk.Size; Name = ([string]$Disk.Name).Trim(); UniqueId = ([string]$Disk.UniqueId).Trim(); Serial = ([string]$Disk.Serial).Trim() }
}

# ---------------- dosya ve klasör silme korumaları ----------------
# Bu yol kalıcı silinebilir mi? '' = evet, aksi hâlde neden. Silinmeyenler: sürücü kökü; Windows, Program Files ve içleri; ProgramData, Users,
# kullanıcı profilinin, AppData’nın ve kişisel klasörlerin (Masaüstü, Belgeler, İndirilenler ...) kendisi; Multimizer’ın çalıştığı klasör ve içi.
# Mesajlar "silinemez" sözcüğünü taşır: geri yükleme hedefi denetimi bu sözcüğe bakarak yalnızca silme yasaklarını geçer.
function Test-SecureDeleteAllowed([string]$Path) {
    $full = ''
    try { $full = [System.IO.Path]::GetFullPath($Path) } catch { return 'Geçersiz yol.' }
    $sep = [string][System.IO.Path]::DirectorySeparatorChar
    $t = $full.TrimEnd('\', '/')
    if ($t.Length -le 3) { return 'Sürücü kökü silinemez.' }
    $deny = New-Object System.Collections.ArrayList
    foreach ($v in @($env:WINDIR, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData, $env:USERPROFILE, $env:PUBLIC, $env:SystemDrive)) {
        if (-not [string]::IsNullOrEmpty($v)) { [void]$deny.Add(([string]$v).TrimEnd('\', '/')) }
    }
    $sd = ([string]$env:SystemDrive).TrimEnd('\', '/')
    if ($sd -ne '') { foreach ($n in @('Users', 'Documents and Settings')) { [void]$deny.Add($sd + $sep + $n) } }
    foreach ($d in $deny) {
        if ($t.Equals($d, [StringComparison]::OrdinalIgnoreCase)) { return 'Sistem klasörü silinemez.' }
    }
    foreach ($v in @($env:WINDIR, $env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if ([string]::IsNullOrEmpty($v)) { continue }
        $pre = ([string]$v).TrimEnd('\', '/') + $sep
        if ($t.StartsWith($pre, [StringComparison]::OrdinalIgnoreCase)) { return 'Windows ve program klasörlerinin içi silinemez.' }
    }
    # kullanıcının kişisel klasörlerinin kendisi (içindeki dosya ve alt klasörler silinebilir)
    $own = New-Object System.Collections.ArrayList
    foreach ($v in @($env:APPDATA, $env:LOCALAPPDATA, $env:OneDrive, $env:OneDriveConsumer, $env:OneDriveCommercial)) {
        if (-not [string]::IsNullOrEmpty($v)) { [void]$own.Add(([string]$v).TrimEnd('\', '/')) }
    }
    if (-not [string]::IsNullOrEmpty($env:USERPROFILE)) {
        $up = ([string]$env:USERPROFILE).TrimEnd('\', '/')
        foreach ($n in @('AppData', 'Downloads', 'Desktop', 'Documents', 'Pictures', 'Music', 'Videos')) { [void]$own.Add($up + $sep + $n) }
    }
    foreach ($f in @('Desktop', 'MyDocuments', 'MyPictures', 'MyMusic', 'MyVideos', 'ApplicationData', 'LocalApplicationData', 'CommonApplicationData')) {
        try { $p = [Environment]::GetFolderPath($f); if (-not [string]::IsNullOrEmpty($p)) { [void]$own.Add($p.TrimEnd('\', '/')) } } catch { }
    }
    foreach ($d in $own) {
        if ($d.Length -gt 3 -and $t.Equals($d, [StringComparison]::OrdinalIgnoreCase)) { return 'Kullanıcı klasörlerinin kendisi silinemez; içindeki dosyaları ya da alt klasörleri seçin.' }
    }
    # Multimizer’ın çalıştığı klasör (ve onu içeren klasörler)
    $app = ''
    try { $app = ([string](Get-AppFolder)).TrimEnd('\', '/') } catch { $app = '' }
    if ($app.Length -gt 3) {
        if ($t.Equals($app, [StringComparison]::OrdinalIgnoreCase) -or $t.StartsWith($app + $sep, [StringComparison]::OrdinalIgnoreCase)) { return 'Multimizer’ın çalıştığı klasör silinemez.' }
        if ($app.StartsWith($t + $sep, [StringComparison]::OrdinalIgnoreCase)) { return 'Bu klasör, Multimizer’ın çalıştığı klasörü içeriyor; silinemez.' }
    }
    return ''
}
