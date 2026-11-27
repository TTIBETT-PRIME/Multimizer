# ==================================================================
#  Multimizer eklentisi: güvenli silme (dosya ve klasörleri üzerine yazarak siler).
#  Yalnızca kullanıcı "Güvenli sil" ya da Çözüm Merkezi / Kalıcı silme sekmesinden dosya ya da klasör silince yüklenir; tek başına çalıştırılmaz.
#  Boş alan temizliği, TRIM, ayrılmamış alan, bölüm ve disk silme DiskSilme eklentisindedir.
#  Ana betikten kullanılanlar: Test-SecureDeleteAllowed, Get-FilesBySize, Format-Size, Write-WhLog, Test-JobCancel, Set-JobProgress, Step-JobProgress.
#
#  Kurallar:
#   1. Silinemeyen yerler Test-SecureDeleteAllowed ile reddedilir (sürücü kökü, Windows, Program Files, kullanıcı klasörlerinin kendisi, Multimizer).
#   2. Kısayol ve birleşim noktalarının (symlink, junction) hedefine girilmez; yalnızca bağlantının kendisi kaldırılır.
#   3. Bulutta duran (indirilmemiş) dosyalar atlanır: yazmak için açmak dosyayı indirir.
#   4. Dosya içeriği istenen geçiş sayısı kadar rastgele veriyle üzerine yazılır, adlandırılmış (alternatif) veri akışları da yazılır,
#      dosya birkaç kez yeniden adlandırılıp silinir.
#  Sınırlar: SSD ve flash belleklerde denetleyici veriyi başka hücrelere taşıdığı için dosya bazında üzerine yazma güvence vermez; NTFS sıkıştırması,
#  EFS, seyrek dosya ve gölge kopyalar eski kopyaları bırakabilir; dosya adı kayıtları (MFT, USN) ve yedekler silinmez.
#  Bu durumlarda sürücünün boş alanını temizleyin (Kalıcı silme > Boş alanı temizle) ya da diski şifreleyin.
# ==================================================================

# Dosyanın adlandırılmış (alternatif) veri akışları: @{ Name; Length } dizisi. Windows dışında ya da okunamazsa boş.
function global:Get-SecureStreams([string]$Path) {
    $out = New-Object System.Collections.ArrayList
    try {
        foreach ($s in @(Get-Item -LiteralPath $Path -Stream '*' -Force -ErrorAction Stop)) {
            $n = [string]$s.Stream
            if ($n -ne '' -and $n -ne ':$DATA') { [void]$out.Add(@{ Name = $n; Length = [long]$s.Length }) }
        }
    } catch { }
    return , $out.ToArray()
}

# Dosyanın durumu: @{ Link (bağlantı); Skip (atlanma nedeni ya da ''); Warn (uyarı metinleri) }
function global:Get-SecureFileState($Fi) {
    $r = @{ Link = $false; Skip = ''; Warn = @() }
    $a = 0
    try { $a = [int]$Fi.Attributes } catch { $a = 0 }
    if (($a -band 0x400) -ne 0) { $r.Link = $true; return $r }
    if (($a -band 0x400000) -ne 0 -or ($a -band 0x40000) -ne 0 -or ($a -band 0x1000) -ne 0) {
        $r.Skip = 'Bulutta duran dosya (bu bilgisayarda yerel kopyası yok); açılırsa indirilir. Atlandı.'
        return $r
    }
    $w = New-Object System.Collections.ArrayList
    if (($a -band 0x800) -ne 0) { [void]$w.Add('NTFS sıkıştırması açık dosya: üzerine yazma fiziksel alanı garanti etmez') }
    if (($a -band 0x4000) -ne 0) { [void]$w.Add('EFS ile şifreli dosya: eski şifreli kopya diskte kalabilir') }
    if (($a -band 0x200) -ne 0) { [void]$w.Add('seyrek dosya: boş bölgeler yazılmaz') }
    $r.Warn = $w.ToArray()
    return $r
}

# Açık bir akışın içeriğini Passes kez rastgele veriyle yazar, sonra boyutunu sıfırlar
function global:Write-SecureOverwrite($Stream, [int]$Passes, $Rng) {
    $buf = New-Object byte[] 1048576
    $len = [long]$Stream.Length
    for ($p = 1; $p -le $Passes; $p++) {
        [void]$Stream.Seek(0, [System.IO.SeekOrigin]::Begin)
        $left = $len
        while ($left -gt 0) {
            $Rng.GetBytes($buf)
            $n = [int][math]::Min([long]$buf.Length, $left)
            $Stream.Write($buf, 0, $n)
            $left -= $n
        }
        $Stream.Flush()
    }
    $Stream.SetLength(0)
    $Stream.Flush()
}

# Dosyanın üzerine yazar, adını birkaç kez değiştirir ve siler. Dönüş: yazılan dosyanın boyutu (bayt).
# Bağlantı ise yalnızca bağlantı kaldırılır (0 döner); bulutta duran dosya için hata fırlatılır.
function global:Remove-FileSecure([string]$Path, [int]$Passes = 1) {
    $fi = New-Object System.IO.FileInfo -ArgumentList $Path
    if (-not $fi.Exists) { return 0.0 }
    if ($Passes -lt 1) { $Passes = 1 }
    if ($Passes -gt 35) { $Passes = 35 }
    $st = Get-SecureFileState $fi
    if ($st.Link) { [System.IO.File]::Delete($Path); return 0.0 }
    if ($st.Skip -ne '') { throw $st.Skip }
    $len = [double]$fi.Length
    try { $fi.Attributes = [System.IO.FileAttributes]::Normal } catch { }
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $fs = $null
    try {
        $fs = New-Object System.IO.FileStream -ArgumentList $Path, ([System.IO.FileMode]::Open), ([System.IO.FileAccess]::Write), ([System.IO.FileShare]::None), 65536, ([System.IO.FileOptions]::WriteThrough)
        Write-SecureOverwrite $fs $Passes $rng
        $fs.Dispose(); $fs = $null
        # adlandırılmış veri akışları (NTFS): her biri aynı şekilde yazılır; yazılamayan olursa uyarı için hata fırlatılmaz
        $full = $fi.FullName
        foreach ($s in (Get-SecureStreams $Path)) {
            $sfs = $null
            try {
                $sfs = New-Object System.IO.FileStream -ArgumentList ('\\?\' + $full + ':' + [string]$s.Name), ([System.IO.FileMode]::Open), ([System.IO.FileAccess]::Write), ([System.IO.FileShare]::None), 4096, ([System.IO.FileOptions]::WriteThrough)
                Write-SecureOverwrite $sfs $Passes $rng
            } catch { Write-WhLog ('Alternatif veri akışı yazılamadı (' + $Path + ':' + [string]$s.Name + '): ' + $_.Exception.Message) 'WARN' }
            finally { if ($null -ne $sfs) { $sfs.Dispose() } }
        }
    } finally {
        if ($null -ne $fs) { $fs.Dispose() }
        $rng.Dispose()
    }
    # dosya adı da iz bırakmasın: aynı uzunlukta rastgele adlarla üç kez yeniden adlandırıp sil
    $dir = $fi.DirectoryName
    $nameLen = [math]::Max(8, $fi.Name.Length)
    $cur = $Path
    for ($i = 0; $i -lt 3; $i++) {
        $rn = ([System.Guid]::NewGuid().ToString('N') + [System.Guid]::NewGuid().ToString('N') + [System.Guid]::NewGuid().ToString('N')).Substring(0, $nameLen)
        $next = Join-Path $dir $rn
        try { [System.IO.File]::Move($cur, $next); $cur = $next } catch { break }
    }
    [System.IO.File]::Delete($cur)
    return $len
}

# Bağlantı noktalarına girmeden boş klasörleri alttan yukarı kaldırır. Dönüş: kaldırılamayan öğe sayısı
function global:Remove-SecureDirTree([string]$Path) {
    $left = 0
    $di = New-Object System.IO.DirectoryInfo -ArgumentList $Path
    if (-not $di.Exists) { return 0 }
    $subs = @()
    try { $subs = @($di.GetDirectories()) } catch { $left++ }
    foreach ($s in $subs) {
        if (($s.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            try { [System.IO.Directory]::Delete($s.FullName, $false) } catch { $left++ }
        } else { $left += (Remove-SecureDirTree $s.FullName) }
    }
    try { [System.IO.Directory]::Delete($Path, $false) } catch { $left++ }
    return $left
}

# P: Paths (dosya ve/veya klasör yolları), Passes (üzerine yazma geçişi, 1-35; verilmezse 1)
# Dönüş: @{ Ok; Files; Failed; Skipped; Bytes; Passes; Warnings (metin dizisi) }
function global:Job_SecureDelete($P) {
    $files = 0; $failed = 0; $skipped = 0; $bytes = 0.0
    $passes = 1
    if ($null -ne $P.Passes) { try { $passes = [int]$P.Passes } catch { $passes = 1 } }
    if ($passes -lt 1) { $passes = 1 }
    if ($passes -gt 35) { $passes = 35 }
    $warn = @{}
    $targets = @($P.Paths | ForEach-Object { [string]$_ } | Where-Object { $_ -ne '' })
    Write-WhLog ('--- GÜVENLİ SİLME (' + [string]$targets.Count + ' öğe, ' + [string]$passes + ' geçiş, geri getirilemez) ---') 'STEP'
    foreach ($t in $targets) {
        if (Test-JobCancel) { Write-WhLog 'İptal edildi.' 'WARN'; break }
        $why = Test-SecureDeleteAllowed $t
        if ($why -ne '') { Write-WhLog ($t + ': ' + $why) 'SKIP'; $failed++; continue }
        if (Test-Path -LiteralPath $t -PathType Container) {
            $root = New-Object System.IO.DirectoryInfo -ArgumentList $t
            if (($root.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                try { [System.IO.Directory]::Delete($t, $false); Write-WhLog ('Bağlantı kaldırıldı, hedefine dokunulmadı: ' + $t) 'INFO' }
                catch { $failed++; Write-WhLog ('Bağlantı kaldırılamadı: ' + $t + ' (' + $_.Exception.Message + ')') 'ERR' }
                continue
            }
            $list = Get-FilesBySize $t 0 1000000
            Set-JobProgress 0 $list.Count 'Güvenli siliniyor'
            foreach ($f in $list) {
                if (Test-JobCancel) { break }
                $name = [string]$f.FullName
                $st = Get-SecureFileState $f
                if ($st.Skip -ne '') { $skipped++; Write-WhLog ($name + ': ' + $st.Skip) 'SKIP'; Step-JobProgress; continue }
                foreach ($w in @($st.Warn)) { if ($warn.ContainsKey($w)) { $warn[$w]++ } else { $warn[$w] = 1 } }
                try { $bytes += (Remove-FileSecure $name $passes); $files++ }
                catch { $failed++; Write-WhLog ('Silinemedi: ' + $name + ' (' + $_.Exception.Message + ')') 'ERR' }
                Step-JobProgress
            }
            $left = Remove-SecureDirTree $t
            if ($left -gt 0) { Write-WhLog ('Klasör tamamen kaldırılamadı (içinde silinemeyen ya da atlanan ' + [string]$left + ' öğe kaldı): ' + $t) 'WARN' }
        } elseif (Test-Path -LiteralPath $t -PathType Leaf) {
            $fi = New-Object System.IO.FileInfo -ArgumentList $t
            $st = Get-SecureFileState $fi
            if ($st.Skip -ne '') { $skipped++; Write-WhLog ($t + ': ' + $st.Skip) 'SKIP'; continue }
            foreach ($w in @($st.Warn)) { if ($warn.ContainsKey($w)) { $warn[$w]++ } else { $warn[$w] = 1 } }
            try { $bytes += (Remove-FileSecure $t $passes); $files++ }
            catch { $failed++; Write-WhLog ('Silinemedi: ' + $t + ' (' + $_.Exception.Message + ')') 'ERR' }
        } else { Write-WhLog ('Bulunamadı: ' + $t) 'SKIP' }
    }
    $wl = New-Object System.Collections.ArrayList
    foreach ($k in $warn.Keys) { [void]$wl.Add([string]$warn[$k] + ' dosya, ' + $k); Write-WhLog ('Uyarı: ' + [string]$warn[$k] + ' dosya, ' + $k) 'WARN' }
    Write-WhLog ('Güvenli silme bitti: ' + [string]$files + ' dosya, ' + (Format-Size $bytes) + ', ' + [string]$failed + ' başarısız, ' + [string]$skipped + ' atlandı') 'INFO'
    return @{ Ok = ($failed -eq 0 -and $skipped -eq 0); Files = $files; Failed = $failed; Skipped = $skipped; Bytes = $bytes; Passes = $passes; Warnings = $wl.ToArray() }
}
