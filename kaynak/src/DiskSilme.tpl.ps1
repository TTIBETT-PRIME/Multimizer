# ==================================================================
#  Multimizer eklentisi: disk silme (boş alan temizliği, TRIM, ayrılmamış alan, bölüm ve tüm disk silme).
#  Çözüm Merkezi "Kalıcı silme" sekmesinde kullanıcı onay verdikten sonra yüklenir; tek başına çalıştırılmaz.
#  Bu dosya derleme sırasında "build\src" altındaki kaynaklardan üretilir (DiskSilme.tpl.ps1 + WipeEngine.cs); elle değiştirmeyin.
#  Ana betikten kullanılanlar: Write-WhLog, Test-JobCancel, Set-JobProgress, Format-Size ve çekirdekteki Get-Wipe* işlevleri.
#
#  Güvenlik kuralları:
#   1. Var olan dosyalara dokunulmaz: boş alan temizliği yalnızca kendi geçici klasörüne yazar ve iş bitince (iptalde de) siler.
#   2. Ham disk yazımı yalnızca çekirdekteki denetimlerden geçen disklere yapılır: Windows, Multimizer ya da geçici dosyaların
#      bulunduğu, çevrimdışı, salt okunur ve havuz üyesi diskler reddedilir; disk, onaydaki boyut/ad/seri numarasıyla yeniden karşılaştırılır.
#   3. "Ayrılmamış alan" kapsamında yalnızca bölüm tablosunun ve Windows’un bildirdiği bölümlerin DIŞINDA kalan boşluklar yazılır;
#      her iki kaynak birleştirilir, çözülemeyen düzenler tamamen dolu sayılır, diskin başında ve sonunda 1 MiB korunur.
#   4. Bölüm ve tüm disk silmede önce Windows’un kendi komutları (Remove-Partition, Clear-Disk) çalışır, ardından alan üzerine yazılır.
#   5. Yazılan her şey anahtardan yeniden üretilebilen AES-256-CTR akışıdır; doğrulama için ek veri saklanmaz.
#  Sınırlar: SSD’lerde üzerine yazma NIST SP 800-88 Rev.1 anlamında "Clear" düzeyindedir; denetleyicinin ayırdığı gizli hücrelere
#  ulaşılamaz. Yedekler, gölge kopyalar, bulut eşleşmeleri ve dosya adı kayıtları (MFT, USN) bu yöntemle silinmez.
#  Hiçbir standart için belgelendirme iddiası yoktur.
# ==================================================================

# Motoru bu oturuma derler. Dönüş: '' = hazır, aksi hâlde neden.
function global:Initialize-MmWipe {
    if ($null -ne ('Mm.WipeEngine' -as [type])) { return '' }
    $src = @'
#@@WIPEENGINE@@
'@
    try {
        if ($PSVersionTable.PSEdition -ne 'Core') {
            Add-Type -TypeDefinition $src -Language CSharp -ReferencedAssemblies @('System.dll', 'System.Core.dll') -IgnoreWarnings -ErrorAction Stop
        } else {
            Add-Type -TypeDefinition $src -Language CSharp -IgnoreWarnings -ErrorAction Stop
        }
    } catch {
        # başka bir iş aynı anda derlemiş olabilir
        if ($null -ne ('Mm.WipeEngine' -as [type])) { return '' }
        $m = [string]$_.Exception.Message
        try { if ($null -ne $_.Exception.InnerException) { $m += ' ' + [string]$_.Exception.InnerException.Message } } catch { }
        return ('Silme motoru derlenemedi: ' + $m)
    }
    return ''
}

# .NET yöntem çağrısı hatalarında asıl iletiyi verir
function global:Get-WipeErrorText($Err) {
    $ex = $Err.Exception
    $depth = 0
    while ($null -ne $ex.InnerException -and $depth -lt 5) { $ex = $ex.InnerException; $depth++ }
    return [string]$ex.Message
}

function global:Test-WipeAdmin {
    try { return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) } catch { return $false }
}

# Engine nesnesi için yardımcılar: @{ Start; Length; StreamPos } listesinden Mm.WipeExtent[] üretir
function global:ConvertTo-WipeExtents($List) {
    $out = New-Object 'System.Collections.Generic.List[Mm.WipeExtent]'
    foreach ($e in @($List)) {
        if ($null -eq $e) { continue }
        $x = New-Object Mm.WipeExtent
        $x.Start = [long][double]$e.Start
        $x.Length = [long][double]$e.Length
        if ($null -ne $e.Tag) { $x.Tag = [string]$e.Tag }
        if ($null -ne $e.StreamPos) { $x.StreamPos = [long][double]$e.StreamPos }
        $out.Add($x)
    }
    return , $out.ToArray()
}

# ilerleme bildirimi: motorun geri çağrısı bu oturum durumunu okur
function global:New-WipeCallback([string]$Label, [double]$Total, [double]$Base) {
    $global:MmWipeProg = @{ Sw = [System.Diagnostics.Stopwatch]::StartNew(); Total = $Total; Base = $Base; Label = $Label }
    return [Mm.WipeProgress]{
        param([string]$stage, [long]$done, [long]$total)
        $g = $global:MmWipeProg
        $all = [double]$g.Total
        $cur = [double]$g.Base + [double]$done
        $pct = 0
        if ($all -gt 0) { $pct = [int][math]::Min(1000, [math]::Floor($cur * 1000.0 / $all)) }
        Set-JobProgress $pct 1000 (Get-WipeProgressLabel ([string]$g.Label) $stage $cur $all ([double]$g.Sw.Elapsed.TotalSeconds))
        return (-not (Test-JobCancel))
    }
}

# ---------------- boş alan temizleme ----------------
# Silinmiş dosyaların diskte kalan kalıntılarını (kurtarma programlarının bulabildiği alanı) AES-256-CTR akışıyla üzerine yazar.
# Var olan hiçbir dosyaya dokunulmaz: sürücüde gizli bir klasör açılır, boş alan bu klasörde geçici dosyalarla doldurulur ve
# iş bitince (iptal ya da hata olsa da) klasör silinir. Windows’un ve açık programların çalışabilmesi için sürücüde pay bırakılır.
# Kanarya doğrulaması: iş başlarken bilinen içerikli küçük dosyalar yazılıp silinir (silinmiş dosya benzetimi), birimdeki fiziksel konumları
# kaydedilir; temizlikten sonra aynı konumlar doğrudan birimden okunup eski içeriğin kalıp kalmadığına bakılır.
# Sınırlar: SSD’lerde denetleyici veriyi başka hücrelere taşıdığı için tam güvence vermez; çok küçük dosyalar (MFT içinde saklananlar)
# ve dosya adları bu yöntemle silinmez. Bırakılan pay temizlenmez.

# Birim bilgisi: @{ Free; Total } (bayt). Ayrı bir işlev olması testlerde sahte birim kullanılmasını sağlar.
function global:Get-WipeVolume([string]$Root) {
    $r = @{ Free = [double]0; Total = [double]0 }
    try {
        $full = [System.IO.Path]::GetFullPath($Root)
        $di = New-Object System.IO.DriveInfo -ArgumentList ([System.IO.Path]::GetPathRoot($full))
        $r.Free = [double]$di.AvailableFreeSpace
        $r.Total = [double]$di.TotalSize
    } catch { }
    return $r
}

# Bırakılacak pay (Get-WipeReserve) çekirdekte; onay penceresi de aynı hesabı kullanır.

# Önceki bir çalışmadan (uygulama kapanmış, elektrik kesilmiş) kalan geçici klasörleri kaldırır
function global:Remove-WipeLeftovers([string]$Root) {
    $n = 0
    try {
        foreach ($d in @(Get-ChildItem -LiteralPath $Root -Directory -Force -ErrorAction Stop | Where-Object { $_.Name -like '.mm-bosalan-*' })) {
            try { [System.IO.Directory]::Delete($d.FullName, $true); $n++ } catch { }
        }
    } catch { }
    return $n
}

# Dosyanın birim içindeki konumları. Dönüş: @{ Cluster; Extents = @(@{ Start; Length }) }; Windows dışında ya da okunamazsa Extents boş.
function global:Get-WipeFileExtents([string]$Path) {
    $r = @{ Cluster = [long]0; Extents = @() }
    try {
        $c = [long]0
        $arr = [Mm.WipeFs]::QueryExtents($Path, [ref]$c)
        $r.Cluster = $c
        $list = New-Object System.Collections.ArrayList
        for ($i = 0; $i + 1 -lt $arr.Length; $i += 2) { [void]$list.Add(@{ Start = [long]$arr[$i]; Length = [long]$arr[$i + 1] }) }
        $r.Extents = $list.ToArray()
    } catch { }
    return $r
}

# Birimi (X:) yalnızca okumak için açar. Ayrı bir işlev olması testlerde sahte birim kullanılmasını sağlar.
function global:Open-WipeRead([string]$Spec) {
    return [Mm.WipeTarget]::Open($Spec, $false)
}

# Silinmiş dosya benzetimi: bilinen içerikli küçük dosyalar yazılır, birimdeki konumları kaydedilir, dosyalar silinir.
# Dönüş: @{ Key; Items = @(@{ Pass; Extents = @(@{ Start; Length; StreamPos }) }); Units; Files }
function global:New-WipeCanary([string]$Dir, [int]$Files = 6, [int]$FileBytes = 262144) {
    $c = @{ Key = $null; Items = @(); Units = [long]0; Files = 0 }
    $key = [Mm.WipeEngine]::NewKey()
    $c.Key = $key
    $items = New-Object System.Collections.ArrayList
    $buf = New-Object byte[] 65536
    for ($i = 1; $i -le $Files; $i++) {
        $path = Join-Path $Dir ('kanarya-' + $i.ToString('D2') + '.tmp')
        $ws = [Mm.WipeStream]::new(0, $key, $i)
        $fs = $null
        try {
            $fs = New-Object System.IO.FileStream -ArgumentList $path, ([System.IO.FileMode]::CreateNew), ([System.IO.FileAccess]::Write), ([System.IO.FileShare]::Read), 65536, ([System.IO.FileOptions]::WriteThrough)
            $pos = [long]0
            while ($pos -lt $FileBytes) {
                $n = [int][math]::Min(65536, $FileBytes - $pos)
                $ws.Fill($buf, 0, $n, $pos)
                $fs.Write($buf, 0, $n)
                $pos += $n
            }
            $fs.Flush($true)
        } catch {
            $path = ''
        } finally {
            if ($null -ne $fs) { $fs.Dispose() }
            $ws.Dispose()
        }
        if ($path -eq '') { continue }
        $c.Files++
        $q = Get-WipeFileExtents $path
        [System.IO.File]::Delete($path)
        $ext = @($q.Extents)
        if ($ext.Count -eq 0) { continue }
        # sıkıştırılmış ya da seyrek dosyada konumlar içerikle eşleşmez: toplam uzunluk dosya boyutunu karşılamalı
        $sum = [long]0
        foreach ($e in $ext) { $sum += [long]$e.Length }
        if ($sum -lt $FileBytes -or $sum -gt ($FileBytes + 2 * [long]$q.Cluster + 65536)) { continue }
        $fpos = [long]0
        $list = New-Object System.Collections.ArrayList
        foreach ($e in $ext) {
            [void]$list.Add(@{ Start = [long]$e.Start; Length = [long]$e.Length; StreamPos = $fpos })
            $fpos += [long]$e.Length
        }
        [void]$items.Add(@{ Pass = $i; Extents = $list.ToArray() })
        $c.Units += [long][math]::Floor($sum / 4096)
    }
    $c.Items = $items.ToArray()
    return $c
}

# Kanarya konumlarını doğrudan birimden okur. Dönüş: @{ Checked; Units; Same; Zeroed; Changed; Error }
function global:Test-WipeCanary($Canary, [string]$Spec) {
    $res = @{ Checked = $false; Units = [long]0; Same = [long]0; Zeroed = [long]0; Changed = [long]0; Error = '' }
    if ($null -eq $Canary -or @($Canary.Items).Count -eq 0) { return $res }
    $t = $null
    try {
        $t = Open-WipeRead $Spec
        foreach ($it in @($Canary.Items)) {
            $arr = ConvertTo-WipeExtents @($it.Extents)
            $r = [Mm.WipeEngine]::Probe($t, $arr, 0, $Canary.Key, [int]$it.Pass, $null)
            if ($r.Error -ne '') { $res.Error = [string]$r.Error; continue }
            $res.Units += [long]$r.Units
            $res.Same += [long]$r.Same
            $res.Zeroed += [long]$r.Zeroed
            $res.Changed += [long]$r.Changed
        }
        $res.Checked = ($res.Units -gt 0)
    } catch {
        $res.Error = Get-WipeErrorText $_
    } finally {
        if ($null -ne $t) { try { $t.Dispose() } catch { } }
    }
    return $res
}

# Kanarya sonucu: @{ Level (ok | warn | info | none); Text }
function global:Get-WipeCanaryVerdict($Pre, $Post) {
    if ($null -eq $Post -or $Post.Checked -ne $true) {
        return @{ Level = 'none'; Text = 'Doğrulama yapılamadı: bu birimde dosya konumları okunamadı.' }
    }
    $total = [long]$Post.Units
    if ($null -eq $Pre -or $Pre.Checked -ne $true -or [long]$Pre.Same -le 0) {
        if ([long]$Post.Same -gt 0) {
            return @{ Level = 'warn'; Text = ([string]$Post.Same + ' / ' + [string]$total + ' test birimi hâlâ okunabiliyor; bırakılan payda kalmış ya da yazılamamış olabilir.') }
        }
        return @{ Level = 'info'; Text = 'Silinen test verisi, temizlemeden önce de okunamıyordu (SSD üzerindeki TRIM işlemi olabilir). Boş alan yine de yazıldı; sınama bilgi vermedi.' }
    }
    if ([long]$Post.Same -eq 0) {
        return @{ Level = 'ok'; Text = ('Doğrulandı: silinmiş test dosyalarının ' + [string]$Pre.Same + ' / ' + [string]$Pre.Units + ' birimi temizlemeden önce okunabiliyordu, sonra hiçbiri okunamıyor.') }
    }
    return @{ Level = 'warn'; Text = ('Silinmiş test dosyalarının ' + [string]$Post.Same + ' / ' + [string]$total + ' birimi temizlemeden sonra da okunabiliyor; bırakılan payda kalmış ya da yazılamamış olabilir.') }
}

# TRIM durumu: on | off | unknown (fsutil: DisableDeleteNotify = 0 ise TRIM açıktır)
function global:Get-WipeTrimState {
    try {
        $o = @(& fsutil.exe behavior query DisableDeleteNotify 2>&1 | ForEach-Object { [string]$_ })
        foreach ($l in $o) {
            if ($l -match 'NTFS\s+DisableDeleteNotify\s*=\s*(\d)') { if ($Matches[1] -eq '0') { return 'on' } else { return 'off' } }
        }
        foreach ($l in $o) {
            if ($l -match 'DisableDeleteNotify\s*=\s*(\d)') { if ($Matches[1] -eq '0') { return 'on' } else { return 'off' } }
        }
    } catch { }
    return 'unknown'
}

# Birime TRIM gönderir (SSD ve ince sağlanan birimler). Dönüş: @{ Ok; Error; Note }
function global:Invoke-WipeTrim([string]$Letter) {
    $r = @{ Ok = $false; Error = ''; Note = '' }
    $l = ([string]$Letter).Trim().Substring(0, 1).ToUpperInvariant()
    try {
        if ((Get-WipeTrimState) -eq 'off') { $r.Note = 'Windows silme bildirimleri (TRIM) kapalı görünüyor; yine de yeniden TRIM istendi.' }
        Optimize-Volume -DriveLetter $l -ReTrim -ErrorAction Stop | Out-Null
        $r.Ok = $true
    } catch {
        $r.Error = Get-WipeErrorText $_
    }
    return $r
}

# P: Drive ("D:") ya da Root (geçici dosyaların yazılacağı klasör), Reserve (bırakılacak pay, bayt; verilmezse sürücü boyutuna göre),
#    FileMax (tek geçici dosyanın en büyük boyutu), StallBytes (boş alan azalmıyorsa kaç bayttan sonra vazgeçileceği),
#    Method (random | zero | dod3 | random3), Canary ($false: kanarya doğrulaması yapma), Trim ($true: bitince TRIM gönder)
#    VolSpec (yalnızca sınama: kanarya okumasının yapılacağı birim belirteci)
# Dönüş: @{ Ok; Kind; Drive; Written; Reserve; Canceled; Error; Method; Passes; Seconds; Canary; Verdict; Trim }
function global:Job_WipeFree($P) {
    $res = @{ Ok = $false; Kind = 'Free'; Drive = ''; Written = [double]0; Reserve = [double]0; Canceled = $false; Error = ''; Method = 'random'; Passes = 1; Seconds = [double]0
        Canary = $null; Verdict = $null; Trim = $null }
    $sw0 = [System.Diagnostics.Stopwatch]::StartNew()
    $root = ([string]$P.Root).Trim()
    if ($root -eq '') {
        $d = ([string]$P.Drive).Trim()
        if ($d -cnotmatch '^[A-Za-z]:?[\\/]?$') { $res.Error = 'Geçerli bir sürücü seçilmedi.'; Write-WhLog $res.Error 'ERR'; return $res }
        $root = $d.Substring(0, 1).ToUpperInvariant() + ':\'
    }
    $res.Drive = $root
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { $res.Error = ($root + ' bulunamadı ya da hazır değil.'); Write-WhLog $res.Error 'ERR'; return $res }
    $isOs = $false
    try { if ($root.Length -ge 1 -and [string]$env:SystemDrive -ne '' -and $root.Substring(0, 1).ToUpperInvariant() -eq ([string]$env:SystemDrive).Substring(0, 1).ToUpperInvariant()) { $isOs = $true } } catch { }
    $vol = Get-WipeVolume $root
    if ($vol.Total -le 0) { $res.Error = 'Sürücü bilgisi okunamadı.'; Write-WhLog $res.Error 'ERR'; return $res }
    $reserve = [double]0
    if ($null -ne $P.Reserve) { $reserve = [double]$P.Reserve }
    if ($reserve -le 0) { $reserve = Get-WipeReserve $vol.Total $isOs }
    $res.Reserve = $reserve
    $todo = $vol.Free - $reserve
    if ($todo -lt 1048576) { $res.Error = 'Sürücüde temizlenecek yeterli boş alan yok.'; Write-WhLog $res.Error 'WARN'; return $res }
    $fileMax = [long]1073741824
    if ($null -ne $P.FileMax -and [long]$P.FileMax -gt 0) { $fileMax = [long]$P.FileMax }
    $stallBytes = [double]268435456
    if ($null -ne $P.StallBytes -and [double]$P.StallBytes -gt 0) { $stallBytes = [double]$P.StallBytes }
    $method = Get-WipeMethodKey ([string]$P.Method)
    $modes = Get-WipeModes $method
    $res.Method = $method
    $res.Passes = @($modes).Count
    $ie = Initialize-MmWipe
    if ($ie -ne '') { $res.Error = $ie; Write-WhLog $res.Error 'ERR'; return $res }

    Write-WhLog ('--- BOŞ ALAN TEMİZLEME: ' + $root + ' (' + (Format-Size $todo) + ' üzerine yazılacak, ' + (Format-Size $reserve) + ' pay bırakılacak, ' + (Get-WipeMethodName $method) + ') ---') 'STEP'
    $left = Remove-WipeLeftovers $root
    if ($left -gt 0) { Write-WhLog ([string]$left + ' eski geçici klasör kaldırıldı.') 'INFO' }
    $vol = Get-WipeVolume $root
    $todo = $vol.Free - $reserve
    $dir = Join-Path $root ('.mm-bosalan-' + [System.Guid]::NewGuid().ToString('N').Substring(0, 12))
    $chunk = 4194304
    $buf = New-Object byte[] $chunk
    $key = [Mm.WipeEngine]::NewKey()
    $volSpec = ''
    if ($root -cmatch '^[A-Za-z]:') { $volSpec = $root.Substring(0, 1).ToUpperInvariant() + ':' }
    # yalnızca sınama: kanarya okumasının yapılacağı birim belirteci (yalnızca okunur açılır)
    if ($null -ne $P.VolSpec -and ([string]$P.VolSpec).Trim() -ne '') { $volSpec = ([string]$P.VolSpec).Trim() }
    $written = [double]0
    $totalWork = $todo * $res.Passes
    $fs = $null
    $pre = $null
    $canary = $null
    try {
        [void][System.IO.Directory]::CreateDirectory($dir)
        try { (New-Object System.IO.DirectoryInfo -ArgumentList $dir).Attributes = [System.IO.FileAttributes]::Hidden } catch { }
        # kanarya: silinmiş dosya benzetimi (yalnızca birim harfi bilinen, 16 MB'tan fazla boşu olan birimlerde)
        if ($P.Canary -ne $false -and $volSpec -ne '' -and $todo -gt 16777216) {
            try {
                $canary = New-WipeCanary $dir
                if (@($canary.Items).Count -gt 0) {
                    $pre = Test-WipeCanary $canary $volSpec
                    Write-WhLog ('Kanarya: ' + [string]@($canary.Items).Count + ' test dosyası yazılıp silindi, birimdeki konumları kaydedildi.') 'INFO'
                } else { Write-WhLog 'Kanarya: dosya konumları okunamadı; doğrulama yapılamayacak.' 'INFO'; $canary = $null }
            } catch { Write-WhLog ('Kanarya hazırlanamadı: ' + (Get-WipeErrorText $_)) 'WARN'; $canary = $null }
        }
        for ($pass = 0; $pass -lt $res.Passes -and -not $res.Canceled -and $res.Error -eq ''; $pass++) {
            if ($pass -gt 0) {
                # önceki geçişin dosyalarını sil; klasörü yeniden aç
                if ($null -ne $fs) { try { $fs.Dispose() } catch { }; $fs = $null }
                [System.IO.Directory]::Delete($dir, $true)
                [void][System.IO.Directory]::CreateDirectory($dir)
                try { (New-Object System.IO.DirectoryInfo -ArgumentList $dir).Attributes = [System.IO.FileAttributes]::Hidden } catch { }
            }
            $v1 = Get-WipeVolume $root
            $avail = $v1.Free - $reserve
            $startFree = $v1.Free
            $passWritten = [double]0
            $ws = [Mm.WipeStream]::new([int]$modes[$pass], $key, $pass)
            $streamPos = [long]0
            $fileNo = 0
            $curLeft = [long]0
            $tick = 0
            try {
                while ($avail -gt 0) {
                    if (Test-JobCancel) { $res.Canceled = $true; Write-WhLog 'İptal edildi.' 'WARN'; break }
                    if ($null -eq $fs -or $curLeft -le 0) {
                        if ($null -ne $fs) { $fs.Flush($true); $fs.Dispose(); $fs = $null }
                        $fileNo++
                        $path = Join-Path $dir ('bos-' + $fileNo.ToString('D5') + '.tmp')
                        $fs = New-Object System.IO.FileStream -ArgumentList $path, ([System.IO.FileMode]::CreateNew), ([System.IO.FileAccess]::Write), ([System.IO.FileShare]::None), 65536, ([System.IO.FileOptions]::WriteThrough)
                        $curLeft = $fileMax
                    }
                    $n = [long][math]::Min([math]::Min([double]$chunk, $avail), [double]$curLeft)
                    if ($n -le 0) { break }
                    $ws.Fill($buf, 0, [int]$n, $streamPos)
                    try { $fs.Write($buf, 0, [int]$n) }
                    catch [System.IO.IOException] { Write-WhLog ('Yazma durdu (disk dolu ya da kota): ' + $_.Exception.Message) 'INFO'; break }
                    $streamPos += $n
                    $written += [double]$n
                    $passWritten += [double]$n
                    $curLeft -= $n
                    $avail -= [double]$n
                    $tick++
                    if (($tick % 16) -eq 0 -or $avail -lt 67108864) {
                        # gerçek boş alanla eşitle; beklendiği gibi azalmıyorsa (sıkıştırma, seyrek birim) vazgeç
                        $fs.Flush($true)
                        $v2 = Get-WipeVolume $root
                        $avail = $v2.Free - $reserve
                        $used = $startFree - $v2.Free
                        if ($passWritten -ge $stallBytes -and $used -lt ($passWritten * 0.5)) {
                            $res.Error = 'Boş alan beklendiği gibi azalmıyor (sıkıştırılmış ya da seyrek bir birim olabilir); işlem durduruldu.'
                            Write-WhLog $res.Error 'WARN'
                            break
                        }
                    }
                    if (($tick % 8) -eq 0) {
                        $pct = 1000
                        if ($totalWork -gt 0) { $pct = [int][math]::Min(1000, [math]::Floor($written * 1000.0 / $totalWork)) }
                        $lbl = 'Boş alan temizleniyor'
                        if ($res.Passes -gt 1) { $lbl += ' (' + [string]($pass + 1) + '/' + [string]$res.Passes + '. geçiş)' }
                        Set-JobProgress $pct 1000 (Get-WipeProgressLabel $lbl '' $written $totalWork ([double]$sw0.Elapsed.TotalSeconds))
                    }
                }
                if ($null -ne $fs) { $fs.Flush($true); $fs.Dispose(); $fs = $null }
            } finally {
                $ws.Dispose()
            }
            if ($res.Passes -gt 1 -and -not $res.Canceled -and $res.Error -eq '') { Write-WhLog ([string]($pass + 1) + '. geçiş bitti: ' + (Format-Size $passWritten)) 'INFO' }
        }
        if ($null -ne $fs) { $fs.Flush($true); $fs.Dispose(); $fs = $null }
        # kanarya: geçici dosyalar silinmeden önce aynı konumları yeniden oku
        if ($null -ne $canary -and -not $res.Canceled -and $res.Error -eq '') {
            $post = Test-WipeCanary $canary $volSpec
            $res.Canary = @{ Pre = $pre; Post = $post; Files = @($canary.Items).Count }
            $res.Verdict = Get-WipeCanaryVerdict $pre $post
            $lvl = 'INFO'
            if ($res.Verdict.Level -eq 'warn') { $lvl = 'WARN' }
            Write-WhLog ('Doğrulama: ' + [string]$res.Verdict.Text) $lvl
        }
    } catch {
        $res.Error = $_.Exception.Message
        Write-WhLog ('Boş alan temizlenemedi: ' + $res.Error) 'ERR'
    } finally {
        if ($null -ne $fs) { try { $fs.Dispose() } catch { } }
        $gone = $false
        for ($t = 0; $t -lt 5 -and -not $gone; $t++) {
            try { if (Test-Path -LiteralPath $dir) { [System.IO.Directory]::Delete($dir, $true) }; $gone = $true }
            catch { Start-Sleep -Milliseconds 400 }
        }
        if (-not $gone) { Write-WhLog ('Geçici klasör silinemedi, elle silin: ' + $dir) 'WARN' }
    }
    $res.Written = $written
    $res.Ok = ($res.Error -eq '' -and -not $res.Canceled -and $written -gt 0)
    if ($res.Ok -and $P.Trim -eq $true -and $volSpec -ne '') {
        $res.Trim = Invoke-WipeTrim $volSpec
        if ($res.Trim.Ok) { Write-WhLog 'TRIM gönderildi: silinen alanlar sürücüye bildirildi.' 'INFO' } else { Write-WhLog ('TRIM gönderilemedi: ' + [string]$res.Trim.Error) 'WARN' }
    }
    $res.Seconds = [double]$sw0.Elapsed.TotalSeconds
    $tail = ''
    if ($res.Canceled) { $tail = ' (iptal edildi)' }
    Write-WhLog ('Boş alan temizleme bitti: ' + (Format-Size $written) + ' üzerine yazıldı' + $tail) 'INFO'
    return $res
}

# P: Drive ("D:"). Silinmiş dosyaların SSD’ye bildirilmesini sağlar (TRIM). Dönüş: @{ Ok; Kind; Drive; Error; Note; Seconds }
function global:Job_TrimVolume($P) {
    $res = @{ Ok = $false; Kind = 'Trim'; Drive = ''; Error = ''; Note = ''; Seconds = [double]0 }
    $d = ([string]$P.Drive).Trim()
    if ($d -cnotmatch '^[A-Za-z]:?[\\/]?$') { $res.Error = 'Geçerli bir sürücü seçilmedi.'; Write-WhLog $res.Error 'ERR'; return $res }
    $res.Drive = $d.Substring(0, 1).ToUpperInvariant() + ':'
    if (-not (Test-Path -LiteralPath ($res.Drive + '\') -PathType Container)) { $res.Error = ($res.Drive + ' bulunamadı ya da hazır değil.'); Write-WhLog $res.Error 'ERR'; return $res }
    Write-WhLog ('--- TRIM: ' + $res.Drive + ' ---') 'STEP'
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Set-JobProgress 0 0 ($res.Drive + ' için TRIM gönderiliyor')
    $t = Invoke-WipeTrim $res.Drive
    $res.Ok = ($t.Ok -eq $true)
    $res.Error = [string]$t.Error
    $res.Note = [string]$t.Note
    $res.Seconds = [double]$sw.Elapsed.TotalSeconds
    if ($res.Ok) { Write-WhLog 'TRIM gönderildi.' 'INFO' } else { Write-WhLog ('TRIM gönderilemedi: ' + $res.Error) 'ERR' }
    return $res
}

# ---------------- ham disk silme ----------------
# Kapsamlar: Unallocated (bölümlerin dışında kalan boşluklar), Partition (tek bölüm), Disk (tüm disk).
# Bölüm ve disk kapsamında önce Windows’un kendi komutları çalışır (Remove-Partition, Clear-Disk), ardından alan doğrudan
# aygıttan üzerine yazılır. Disk silmede son geçiş sıfır değilse diskin başı ve sonu (bölüm tablosu yapıları) sıfırlanır; böylece disk
# Windows’a "boş" görünür ve rastgele veri bir bölüm tablosu gibi yorumlanmaz.

function global:New-WipeRawResult([string]$Scope) {
    return @{ Ok = $false; Kind = 'Raw'; Scope = $Scope; Disk = -1; Part = 0; Name = ''; Size = [double]0; Target = ''; Method = ''; Passes = 0; Verify = ''; After = ''
        Planned = [double]0; Written = [double]0; Verified = [double]0; BadUnits = [double]0; WriteErrors = 0; Seconds = [double]0; Canceled = $false; Error = ''
        Started = $false; Nothing = $false; Notes = @(); Ranges = 0; Style = ''; AfterDone = ''; Letter = ''; VerifyKind = '' }
}

# Hedef belirtimi. Gerçek disk yalnızca tamsayıdan üretilir; Image yalnızca sınama içindir ve var olan bir dosya olmalıdır.
function global:Resolve-WipeTarget($P) {
    $res = @{ Ok = $false; Kind = ''; Spec = ''; Number = -1; Error = '' }
    $img = ([string]$P.Image).Trim()
    $num = -1
    if ($null -ne $P.Disk) { try { $num = [int]$P.Disk } catch { $num = -1 } }
    if ($img -ne '') {
        $full = ''
        try { $full = [System.IO.Path]::GetFullPath($img) } catch { $full = '' }
        if ($full -eq '' -or -not (Test-Path -LiteralPath $full -PathType Leaf)) { $res.Error = 'Disk imajı bulunamadı.'; return $res }
        $res.Ok = $true; $res.Kind = 'Image'; $res.Spec = $full; $res.Number = $num
        return $res
    }
    if ($num -lt 0 -or $num -gt 9999) { $res.Error = 'Geçerli bir disk seçilmedi.'; return $res }
    $res.Ok = $true; $res.Kind = 'Disk'; $res.Spec = ('PhysicalDrive' + [string]$num); $res.Number = $num
    return $res
}

# Windows’un bildirdiği bölümler (ayrılmamış alan hesabında "dolu" sayılır)
function global:Get-WipeWinExtents($Live) {
    $list = New-Object System.Collections.ArrayList
    foreach ($pt in @($Live.Parts)) {
        if ($null -eq $pt) { continue }
        $l = [double]$pt.Size
        if ($l -gt 0) { [void]$list.Add(@{ Start = [double]$pt.Offset; Length = $l; Tag = 'Windows bölümü' }) }
    }
    return , $list.ToArray()
}

# Windows depolama komutları (ayrı işlevler: sınamada sahtelerle değiştirilir). Hata olursa istisna fırlatırlar.
function global:Invoke-WipeRemovePartition([int]$Disk, [int]$Part) {
    Remove-Partition -DiskNumber $Disk -PartitionNumber $Part -Confirm:$false -ErrorAction Stop
}

function global:Invoke-WipeClearDisk([int]$Disk) {
    Clear-Disk -Number $Disk -RemoveData -RemoveOEM -Confirm:$false -ErrorAction Stop
}

function global:Update-WipeStorage {
    try { Update-HostStorageCache -ErrorAction Stop } catch { }
}

# Silinen alana yeni bölüm açar ve biçimler. Whole: tüm disk (diski başlatır); aksi hâlde Offset/Size bölgesine bölüm. Dönüş: sürücü harfi ('' olabilir)
function global:Invoke-WipeNewVolume([int]$Disk, [bool]$Whole, [double]$Offset, [double]$Size, [string]$Fs, [string]$Style) {
    if ($Whole) {
        Initialize-Disk -Number $Disk -PartitionStyle $Style -ErrorAction Stop
        $pt = New-Partition -DiskNumber $Disk -UseMaximumSize -AssignDriveLetter -ErrorAction Stop
    } else {
        $pt = New-Partition -DiskNumber $Disk -Offset ([uint64]$Offset) -Size ([uint64]$Size) -AssignDriveLetter -ErrorAction Stop
    }
    $letter = ''
    if ($pt.DriveLetter) { $letter = [string]$pt.DriveLetter }
    if ($letter -eq '') { return '' }
    $fsName = 'NTFS'
    if ($Fs -eq 'exfat') { $fsName = 'exFAT' } elseif ($Fs -eq 'fat32') { $fsName = 'FAT32' }
    Format-Volume -DriveLetter $letter -FileSystem $fsName -Confirm:$false -ErrorAction Stop | Out-Null
    return ($letter.ToUpperInvariant() + ':')
}

# Hedefi doğrulayıp yazma planını çıkarır (hiçbir şey değiştirmez). Dönüş: @{ Ok; Error; Live; Part; Extents (@{Start;Length;Tag}); Style; Note; Length; Sector }
function global:Get-WipeRawPlan($P, $Tg, [string]$Scope) {
    $pl = @{ Ok = $false; Error = ''; Live = $null; Part = $null; Extents = @(); Style = ''; Note = ''; Length = [double]0; Sector = 512 }
    $live = Get-WipeDiskLive $Tg.Number
    $why = Test-WipeDiskAllowed $live $Scope
    if ($why -ne '') { $pl.Error = $why; return $pl }
    $why = Test-WipeIdentity $live $P.Expect
    if ($why -ne '') { $pl.Error = $why; return $pl }
    $pl.Live = $live
    $pl.Sector = [int]$live.Sector
    if ($Scope -eq 'Partition') {
        $part = $null
        foreach ($pt in @($live.Parts)) { if ([int]$pt.Number -eq [int]$P.Part) { $part = $pt } }
        $why = Test-WipePartAllowed $live $part
        if ($why -ne '') { $pl.Error = $why; return $pl }
        $ex = $P.Expect
        if ($null -ne $ex -and $null -ne $ex.PartOffset -and ([double]$part.Offset -ne [double]$ex.PartOffset -or [double]$part.Size -ne [double]$ex.PartSize)) {
            $pl.Error = 'Bölüm, onay verdiğiniz andan sonra değişmiş görünüyor. Güvenliğiniz için işlem başlatılmadı; diskleri yenileyip yeniden seçin.'
            return $pl
        }
        $pl.Part = $part
    }
    $ro = $null
    try {
        $ro = [Mm.WipeTarget]::Open([string]$Tg.Spec, $false)
        $len = [double]$ro.Length
        $pl.Length = $len
        if ($Tg.Kind -eq 'Disk' -and [math]::Abs($len - [double]$live.Size) -gt [double]$live.Sector) {
            $pl.Error = 'Aygıtın boyutu Windows tarafından bildirilenden farklı; işlem başlatılmadı.'
            return $pl
        }
        $sector = [int]$ro.SectorSize
        $pl.Sector = $sector
        if ($Scope -eq 'Disk') {
            $whole = [long]([math]::Floor($len / $sector) * $sector)
            $pl.Extents = @(@{ Start = [double]0; Length = [double]$whole; Tag = 'tüm disk' })
        } elseif ($Scope -eq 'Partition') {
            $so = [double]$pl.Part.Offset
            $sl = [double]$pl.Part.Size
            if (($so % $sector) -ne 0 -or ($sl % $sector) -ne 0 -or ($so + $sl) -gt $len) {
                $pl.Error = 'Bölümün konumu sektör sınırına uymuyor ya da diskin dışına taşıyor; işlem başlatılmadı.'
                return $pl
            }
            $pl.Extents = @(@{ Start = $so; Length = $sl; Tag = 'bölüm' })
        } else {
            $style = ''
            $note = ''
            $occ = [Mm.WipeLayout]::ReadOccupied($ro, [ref]$style, [ref]$note)
            $all = New-Object 'System.Collections.Generic.List[Mm.WipeExtent]'
            foreach ($x in $occ) { $all.Add($x) }
            $winExt = ConvertTo-WipeExtents (Get-WipeWinExtents $live)
            foreach ($x in $winExt) { $all.Add($x) }
            $guard = [long]1048576
            $gaps = [Mm.WipeLayout]::Gaps([long]$len, $all.ToArray(), $guard, $guard, [long]8388608, [long]$sector)
            $pl.Style = $style
            $pl.Note = $note
            $ex2 = New-Object System.Collections.ArrayList
            foreach ($g in $gaps) { [void]$ex2.Add(@{ Start = [double]$g.Start; Length = [double]$g.Length; Tag = 'ayrılmamış' }) }
            $pl.Extents = $ex2.ToArray()
        }
    } catch {
        $pl.Error = Get-WipeErrorText $_
        return $pl
    } finally {
        if ($null -ne $ro) { try { $ro.Dispose() } catch { } }
    }
    $pl.Ok = $true
    return $pl
}

# P: Scope (Unallocated | Partition | Disk), Disk (numara), Part (bölüm numarası; Partition için), Expect (@{ Size; Name; UniqueId; Serial; PartOffset; PartSize }),
#    Method, Verify (none | sample | full), After (none | ntfs | exfat | fat32), Image (yalnızca sınama: disk yerine imaj dosyası)
function global:Job_WipeRaw($P) {
    $scope = ([string]$P.Scope).Trim()
    $res = New-WipeRawResult $scope
    $sw0 = [System.Diagnostics.Stopwatch]::StartNew()
    if (@('Unallocated', 'Partition', 'Disk') -notcontains $scope) { $res.Error = 'Bilinmeyen silme kapsamı.'; Write-WhLog $res.Error 'ERR'; return $res }
    $method = Get-WipeMethodKey ([string]$P.Method)
    $verify = Get-WipeVerifyKey ([string]$P.Verify)
    $after = Get-WipeAfterKey ([string]$P.After)
    if ($scope -eq 'Unallocated') { $after = 'none' }
    $modes = Get-WipeModes $method
    $res.Method = $method; $res.Verify = $verify; $res.After = $after; $res.Passes = $modes.Count
    $tg = Resolve-WipeTarget $P
    if (-not $tg.Ok) { $res.Error = $tg.Error; Write-WhLog $res.Error 'ERR'; return $res }
    $res.Disk = $tg.Number; $res.Part = 0
    if ($null -ne $P.Part) { $res.Part = [int]$P.Part }
    $res.Target = $tg.Spec
    if ($tg.Kind -eq 'Disk' -and -not (Test-WipeAdmin)) { $res.Error = 'Disk silmek için Multimizer uygulamasını yönetici olarak çalıştırın.'; Write-WhLog $res.Error 'ERR'; return $res }
    $ie = Initialize-MmWipe
    if ($ie -ne '') { $res.Error = $ie; Write-WhLog $res.Error 'ERR'; return $res }

    # ---- plan: canlı disk, korumalar, kimlik, aralıklar (henüz hiçbir şey değişmedi) ----
    $pl = Get-WipeRawPlan $P $tg $scope
    if (-not $pl.Ok) { $res.Error = $pl.Error; Write-WhLog ('Silme başlatılmadı: ' + $res.Error) 'ERR'; return $res }
    $live = $pl.Live
    $res.Name = [string]$live.Name
    $res.Size = [double]$live.Size
    $res.Style = [string]$pl.Style
    $extList = @($pl.Extents)
    $res.Ranges = $extList.Count
    $sector = [int]$pl.Sector
    $len = [double]$pl.Length
    if ($extList.Count -eq 0) {
        $res.Ok = $true; $res.Nothing = $true
        $res.Notes = @('Ayrılmamış alan bulunamadı; yapılacak bir şey yok.' + $(if ([string]$pl.Note -ne '') { ' ' + [string]$pl.Note } else { '' }))
        Write-WhLog ('Disk ' + [string]$tg.Number + ': ' + $res.Notes[0]) 'INFO'
        return $res
    }
    $bytes = [double]0
    foreach ($e in $extList) { $bytes += [double]$e.Length }
    if ($after -eq 'fat32' -and $scope -ne 'Unallocated' -and $bytes -gt [double]34359738368) {
        $res.Error = 'FAT32 yalnızca 32 GB boyuta kadar biçimlenebilir; NTFS ya da exFAT seçin. Hiçbir şey silinmedi.'
        Write-WhLog $res.Error 'ERR'
        return $res
    }
    $res.Planned = $bytes * $modes.Count
    $what = 'Disk ' + [string]$tg.Number + '  ' + [string]$live.Name
    Write-WhLog ('--- KALICI SİLME (' + $scope + '): ' + $what + ', ' + (Format-Size $bytes) + ', ' + (Get-WipeMethodName $method) + ', doğrulama: ' + (Get-WipeVerifyName $verify) + ' ---') 'STEP'
    Write-WhLog ('Hedef kimliği: boyut ' + (Format-Size ([double]$live.Size)) + ', seri ' + [string]$live.Serial + ', kimlik ' + [string]$live.UniqueId + ', ' + [string]$extList.Count + ' aralık') 'INFO'

    # ---- yıkıcı hazırlık: bölümü kaldır ya da diski temizle ----
    $partOffset = [double]0
    $partSize = [double]0
    try {
        if ($scope -eq 'Partition') {
            $partOffset = [double]$pl.Part.Offset; $partSize = [double]$pl.Part.Size
            Write-WhLog ('Bölüm ' + [string]$P.Part + ' kaldırılıyor...') 'STEP'
            Invoke-WipeRemovePartition ([int]$tg.Number) ([int]$P.Part)
            $res.Started = $true
        } elseif ($scope -eq 'Disk') {
            Write-WhLog ('Disk ' + [string]$tg.Number + ' temizleniyor (bölümler kaldırılıyor)...') 'STEP'
            Invoke-WipeClearDisk ([int]$tg.Number)
            $res.Started = $true
        }
    } catch {
        $res.Error = 'Windows bölümü kaldıramadı: ' + (Get-WipeErrorText $_) + ' Hiçbir veri yazılmadı.'
        Write-WhLog $res.Error 'ERR'
        return $res
    }
    if ($res.Started) { Update-WipeStorage }

    # ---- yazma ----
    $key = [Mm.WipeEngine]::NewKey()
    $arr = ConvertTo-WipeExtents $extList
    $lastMode = [int]$modes[$modes.Count - 1]
    $tidy = ($scope -eq 'Disk' -and $lastMode -ne 1)
    $edges = $null
    if ($tidy) { $edges = [Mm.WipeLayout]::EdgeGuards([long]$len, [long]1048576, $sector) }
    $edgeBytes = [double]0
    if ($tidy) { foreach ($g in $edges) { $edgeBytes += [double]$g.Length } }
    $verifyBytes = [double]0
    if ($verify -eq 'full') { $verifyBytes = $bytes } elseif ($verify -eq 'sample') { $verifyBytes = [math]::Min($bytes, [double]33554432) }
    $totalWork = $res.Planned + $edgeBytes + $verifyBytes + $edgeBytes
    $wr = $null
    $t = $null
    try {
        $t = [Mm.WipeTarget]::Open([string]$tg.Spec, $true)
        $cb = New-WipeCallback ('Disk ' + [string]$tg.Number + ' siliniyor') $totalWork 0
        $wr = [Mm.WipeEngine]::Fill($t, $arr, [int[]]$modes, $key, $cb)
        $res.Written = [double]$wr.Written
        $res.WriteErrors = [int]$wr.WriteErrors
        if ($wr.Canceled) { $res.Canceled = $true; Write-WhLog 'İptal edildi.' 'WARN' }
        elseif ($wr.Error -ne '') { $res.Error = [string]$wr.Error; Write-WhLog ('Yazma durdu: ' + $res.Error) 'ERR' }
        elseif ($wr.WriteErrors -gt 0) {
            $res.Notes += ([string]$wr.WriteErrors + ' bölgeye yazılamadı (ilk konum ' + (Format-Size ([double]$wr.FirstWriteError)) + '); disk hasarlı olabilir.')
            Write-WhLog $res.Notes[$res.Notes.Count - 1] 'WARN'
        }
        if (-not $res.Canceled -and $res.Error -eq '' -and $tidy) {
            $cb2 = New-WipeCallback ('Disk ' + [string]$tg.Number + ' siliniyor') $totalWork ($res.Planned)
            $tr = [Mm.WipeEngine]::Fill($t, $edges, [int[]]@(1), $key, $cb2)
            if ($tr.Error -ne '') { $res.Error = [string]$tr.Error; Write-WhLog ('Disk başı/sonu sıfırlanamadı: ' + $res.Error) 'ERR' }
            elseif ($tr.Canceled) { $res.Canceled = $true }
        }
    } catch {
        $res.Error = Get-WipeErrorText $_
        Write-WhLog ('Silme hatası: ' + $res.Error) 'ERR'
    } finally {
        if ($null -ne $t) { try { $t.Dispose() } catch { } }
    }

    # ---- doğrulama: yazılanı aygıttan yeniden oku ----
    if ($res.Error -eq '' -and -not $res.Canceled -and $verify -ne 'none') {
        $v = $null
        try {
            $t2 = [Mm.WipeTarget]::Open([string]$tg.Spec, $false)
            try {
                $vext = $arr
                if ($tidy) {
                    $g0 = [long]$edges[0].Length
                    $vlist = New-Object System.Collections.ArrayList
                    foreach ($e in $extList) {
                        $s = [double]$e.Start; $l = [double]$e.Length
                        if ($s -lt $g0) { $l -= ($g0 - $s); $s = [double]$g0 }
                        if ($edges.Count -gt 1 -and ($s + $l) -gt [double]$edges[1].Start) { $l = [double]$edges[1].Start - $s }
                        if ($l -gt 0) { [void]$vlist.Add(@{ Start = $s; Length = $l }) }
                    }
                    $vext = ConvertTo-WipeExtents $vlist.ToArray()
                }
                $samples = 0
                if ($verify -eq 'sample') { $samples = 256 }
                $cb3 = New-WipeCallback ('Disk ' + [string]$tg.Number + ' doğrulanıyor') $totalWork ($res.Planned + $edgeBytes)
                if ($vext.Count -gt 0) {
                    $v = [Mm.WipeEngine]::Verify($t2, $vext, $lastMode, $key, ($modes.Count - 1), $samples, $cb3)
                    $res.Verified = [double]$v.Verified
                    $res.BadUnits = [double]$v.BadUnits
                    if ($v.Canceled) { $res.Canceled = $true }
                    elseif ($v.Error -ne '') { $res.Error = 'Doğrulama yapılamadı: ' + [string]$v.Error; Write-WhLog $res.Error 'ERR' }
                    elseif ($v.BadUnits -gt 0) {
                        $res.Error = 'Doğrulama başarısız: ' + [string]$v.BadUnits + ' birim yazılandan farklı okundu (ilk konum ' + (Format-Size ([double]$v.FirstBad)) + '). Disk hasarlı ya da yazma önbelleği olan bir bağdaştırıcıda olabilir.'
                        Write-WhLog $res.Error 'ERR'
                    }
                }
                if ($tidy -and $res.Error -eq '' -and -not $res.Canceled) {
                    $z = [Mm.WipeEngine]::Verify($t2, $edges, 1, $key, 0, 0, $null)
                    $res.Verified += [double]$z.Verified
                    if ($z.BadUnits -gt 0) { $res.Notes += 'Diskin başı/sonu sıfırlanamadı olabilir.'; Write-WhLog $res.Notes[$res.Notes.Count - 1] 'WARN' }
                }
            } finally { $t2.Dispose() }
        } catch {
            $res.Error = 'Doğrulama yapılamadı: ' + (Get-WipeErrorText $_)
            Write-WhLog $res.Error 'ERR'
        }
        $res.VerifyKind = $verify
    }

    # ---- sonra: yeni bölüm ve biçim ----
    if ($res.Error -eq '' -and -not $res.Canceled -and $after -ne 'none' -and $scope -ne 'Unallocated') {
        try {
            # 2 TB altındaki USB bellekler ve zaten MBR olan diskler MBR, diğerleri GPT olarak başlatılır
            $style = 'GPT'
            if ($len -lt 2199023255552 -and ([string]$live.Bus -eq 'USB' -or [string]$live.Style -eq 'MBR')) { $style = 'MBR' }
            Write-WhLog ('Yeni bölüm açılıyor ve ' + (Get-WipeAfterName $after) + '...') 'STEP'
            $letter = Invoke-WipeNewVolume ([int]$tg.Number) ($scope -eq 'Disk') $partOffset $partSize $after $style
            $res.Letter = [string]$letter
            $res.AfterDone = (Get-WipeAfterName $after)
            Update-WipeStorage
        } catch {
            $res.Notes += ('Yeni bölüm açılamadı: ' + (Get-WipeErrorText $_) + ' Alan silinmiş durumda; Disk Yönetimi uygulamasından bölüm açabilirsiniz.')
            Write-WhLog $res.Notes[$res.Notes.Count - 1] 'WARN'
        }
    } elseif ($res.Started) { Update-WipeStorage }

    $res.Ok = ($res.Error -eq '' -and -not $res.Canceled)
    $res.Seconds = [double]$sw0.Elapsed.TotalSeconds
    $verb = 'bitti'
    if ($res.Canceled) { $verb = 'iptal edildi' } elseif (-not $res.Ok) { $verb = 'tamamlanamadı' }
    Write-WhLog ('KAYIT: ' + $what + ' (' + $scope + ') silme ' + $verb + ': ' + (Format-Size $res.Written) + ' yazıldı, ' + (Format-Size $res.Verified) + ' doğrulandı, ' + [string][int][math]::Round($res.Seconds) + ' sn') 'INFO'
    return $res
}

# ---------------- kendi kendine denetim ----------------
# Motorun bu bilgisayarda çalıştığını, hiçbir veriye dokunmadan gösterir: derleme, geçici bir imaj üzerinde yazma ve doğrulama,
# dosya konumu sorgusu ve (yönetici ise) sistem diskinin ilk sektörünü SALT OKUNUR açma. Dönüş: @{ Ok; Lines = @(@{ Ok; Text }) }
function global:Invoke-WipeSelfCheck {
    $lines = New-Object System.Collections.ArrayList
    $ok = $true
    $ie = Initialize-MmWipe
    if ($ie -ne '') { return @{ Ok = $false; Lines = @(@{ Ok = $false; Text = $ie }) } }
    [void]$lines.Add(@{ Ok = $true; Text = 'Silme motoru derlendi.' })
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('mm-silme-deneme-' + [System.Guid]::NewGuid().ToString('N').Substring(0, 8) + '.img')
    try {
        $bytes = New-Object byte[] 8388608
        for ($i = 0; $i -lt $bytes.Length; $i++) { $bytes[$i] = 165 }
        [System.IO.File]::WriteAllBytes($tmp, $bytes)
        $key = [Mm.WipeEngine]::NewKey()
        $t = [Mm.WipeTarget]::Open($tmp, $true)
        try {
            $ext = ConvertTo-WipeExtents @(@{ Start = 1048576; Length = 4194304 })
            $r = [Mm.WipeEngine]::Fill($t, $ext, [int[]]@(0, 0), $key, $null)
            $v = [Mm.WipeEngine]::Verify($t, $ext, 0, $key, 1, 0, $null)
            $good = ($r.Error -eq '' -and $v.Error -eq '' -and $v.BadUnits -eq 0 -and $r.Written -eq 8388608)
            [void]$lines.Add(@{ Ok = $good; Text = 'Geçici imaj üzerinde yazma ve doğrulama (2 geçiş, 4 MB).' })
            if (-not $good) { $ok = $false }
        } finally { $t.Dispose() }
        $after = [System.IO.File]::ReadAllBytes($tmp)
        $same = $true
        foreach ($i in @(0, 1048575, 5242880, 5242881, 8388607)) { if ($after[$i] -ne 165) { $same = $false } }
        [void]$lines.Add(@{ Ok = $same; Text = 'Aralığın dışındaki baytlar değişmedi.' })
        if (-not $same) { $ok = $false }
        if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) {
            $q = Get-WipeFileExtents $tmp
            $qok = (@($q.Extents).Count -gt 0 -and [long]$q.Cluster -gt 0)
            [void]$lines.Add(@{ Ok = $qok; Text = 'Dosyanın birimdeki konumu sorgulandı (kanarya doğrulaması için gerekli).' })
            if (-not $qok) { $ok = $false }
            if (Test-WipeAdmin) {
                $dn = -1
                try { $dn = [int](@(Get-Partition -DriveLetter ([string]$env:SystemDrive).Substring(0, 1) -ErrorAction Stop)[0]).DiskNumber } catch { $dn = -1 }
                if ($dn -ge 0) {
                    $ro = $null
                    try {
                        $ro = [Mm.WipeTarget]::Open(('PhysicalDrive' + [string]$dn), $false)
                        $b = New-Object byte[] 4096
                        $n = $ro.ReadAt(0, $b, 0, 4096)
                        [void]$lines.Add(@{ Ok = ($n -ge 512); Text = ('Sistem diski (Disk ' + [string]$dn + ') doğrudan, salt okunur açıldı; ilk sektör okundu.') })
                        if ($n -lt 512) { $ok = $false }
                    } catch {
                        [void]$lines.Add(@{ Ok = $false; Text = ('Disk doğrudan açılamadı: ' + (Get-WipeErrorText $_)) })
                        $ok = $false
                    } finally { if ($null -ne $ro) { $ro.Dispose() } }
                }
            } else {
                [void]$lines.Add(@{ Ok = $true; Text = 'Disk doğrudan açma denemesi atlandı (yönetici değil).' })
            }
        }
    } catch {
        [void]$lines.Add(@{ Ok = $false; Text = (Get-WipeErrorText $_) })
        $ok = $false
    } finally {
        try { if (Test-Path -LiteralPath $tmp) { [System.IO.File]::Delete($tmp) } } catch { }
    }
    return @{ Ok = $ok; Lines = $lines.ToArray() }
}
