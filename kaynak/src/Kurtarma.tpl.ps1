# ==================================================================
#  Multimizer eklentisi: silinen dosyaları geri getirme. Yalnızca Çözüm Merkezi "Silinen dosyalar" sekmesinde tarama ya da
#  kurtarma başlatılınca yüklenir; tek başına çalıştırılmaz.
#  Bu dosya derleme sırasında "build\src" altındaki kaynaklardan üretilir (Kurtarma.tpl.ps1 + RcEngine.cs); elle değiştirmeyin.
#  Ana betikten kullanılanlar: Write-WhLog, Test-JobCancel, Set-JobProgress, Format-Size.
#
#  Güvenlik kuralları:
#   1. Taranan sürücüye ya da imaja hiçbir şey yazılmaz; sürücü yalnızca okunur.
#   2. Kurtarılan dosyalar, taranan sürücüden FARKLI bir sürücüye yazılır; aynı sürücü seçilirse işlem başlamaz.
#   3. Hedefte var olan hiçbir dosyanın üzerine yazılmaz; her kurtarma yeni bir klasöre gider.
#   4. Hedefte yeterli boş yer yoksa işlem başlamaz.
#  Kaynaklar: sürücü harfi (E:), fiziksel disk (PhysicalDrive2; sürücü harfi olmayan bölümler ve USB bellekler dahil) ya da ham imaj.
#  Dosya sistemleri: NTFS ve FAT12/16/32 ve exFAT (silinmiş kayıtlardan ad, klasör ve tarih + imza taraması), ext2/3/4 (boş bloklarda
#  imza taraması), diğer her biçim ve bozuk birimler (ReFS, HFS+, APFS, Btrfs, XFS ...: tüm alanda imza taraması).
#  Sınırlar: SSD'lerde TRIM silinen verinin çoğunu temizler; üzerine yazılmış, sıkıştırılmış (NTFS) ya da şifrelenmiş (EFS, BitLocker,
#  LUKS) dosyalar kurtarılamaz; imza taramasında dosya adı ve tarihi bilinmez, parçalı dosyalar bulunamayabilir; FAT'ta parça bilgisi
#  silinir, bu yüzden parçalanmış dosyalar bozuk çıkabilir.
# ==================================================================

# Motoru bu oturuma derler. Dönüş: '' = hazır, aksi hâlde neden.
function global:Initialize-MmRecover {
    if ($null -ne ('Mm.RcEngine' -as [type])) { return '' }
    $src = @'
#@@RCENGINE@@
'@
    try {
        if ($PSVersionTable.PSEdition -ne 'Core') {
            Add-Type -TypeDefinition $src -Language CSharp -ReferencedAssemblies @('System.dll', 'System.Core.dll') -IgnoreWarnings -ErrorAction Stop
        } else {
            Add-Type -TypeDefinition $src -Language CSharp -IgnoreWarnings -ErrorAction Stop
        }
    } catch {
        # başka bir iş aynı anda derlemiş olabilir
        if ($null -ne ('Mm.RcEngine' -as [type])) { return '' }
        $m = [string]$_.Exception.Message
        try { if ($null -ne $_.Exception.InnerException) { $m += ' ' + [string]$_.Exception.InnerException.Message } } catch { }
        return ('Kurtarma motoru derlenemedi: ' + $m)
    }
    return ''
}

# .NET yöntem çağrısı hatalarında asıl iletiyi verir
function global:Get-RcErrorText($Err) {
    $ex = $Err.Exception
    $depth = 0
    while ($null -ne $ex.InnerException -and $depth -lt 5) { $ex = $ex.InnerException; $depth++ }
    return [string]$ex.Message
}

# Kaynağı doğrular. Dönüş: @{ Ok; Kind (Drive | Disk | Image); Source; Letter; DiskNumber; Error }
function global:Resolve-RcSource([string]$Source) {
    $res = @{ Ok = $false; Kind = ''; Source = ''; Letter = ''; DiskNumber = -1; Error = '' }
    $s = ([string]$Source).Trim()
    if ($s -eq '') { $res.Error = 'Taranacak sürücü, disk ya da disk imajı seçilmedi.'; return $res }
    if ([Mm.RcEngine]::IsDiskSpec($s)) {
        $num = [int]([regex]::Match($s, '\d+$').Value)
        $res.Ok = $true; $res.Kind = 'Disk'; $res.Source = ('PhysicalDrive' + [string]$num); $res.DiskNumber = $num
        return $res
    }
    if ([Mm.RcEngine]::IsDriveSpec($s)) {
        $letter = $s.Substring(0, 1).ToUpperInvariant()
        if (-not (Test-Path -LiteralPath ($letter + ':\'))) { $res.Error = ($letter + ': sürücüsü bulunamadı ya da hazır değil.'); return $res }
        $res.Ok = $true; $res.Kind = 'Drive'; $res.Source = ($letter + ':'); $res.Letter = $letter
        return $res
    }
    if (Test-Path -LiteralPath $s -PathType Leaf) { $res.Ok = $true; $res.Kind = 'Image'; $res.Source = $s; return $res }
    $res.Error = ('Disk imajı bulunamadı: ' + $s)
    return $res
}

function global:Get-RcDirRoot([string]$Dir) {
    try { return [string][System.IO.Path]::GetPathRoot([System.IO.Path]::GetFullPath($Dir)) } catch { return '' }
}

# Hedef klasörü denetler. Dönüş: '' = uygun, aksi hâlde neden. Need: gereken bayt
function global:Test-RcDestination($Src, [string]$Dest, [double]$Need) {
    $d = ([string]$Dest).Trim()
    if ($d -eq '') { return 'Kurtarma klasörü seçilmedi.' }
    if (-not [System.IO.Path]::IsPathRooted($d)) { return 'Kurtarma klasörü tam bir yol olmalı (örneğin D:\Kurtarilan).' }
    $root = Get-RcDirRoot $d
    if ($root -eq '') { return 'Kurtarma klasörü yolu geçersiz.' }
    $isUnc = $root.StartsWith('\\')
    if ($Src.Kind -eq 'Drive' -and -not $isUnc -and $root.Length -ge 1 -and $root.Substring(0, 1).ToUpperInvariant() -eq [string]$Src.Letter) {
        return ('Kurtarma klasörü, taranan ' + [string]$Src.Letter + ': sürücüsünde olamaz. Kurtarılan dosyalar silinmiş dosyaların yerine yazılıp onları yok edebilir; başka bir sürücü ya da USB bellek seçin.')
    }
    if ($Src.Kind -eq 'Disk' -and -not $isUnc -and $root.Length -ge 1) {
        $dn = -2
        try { $dn = [int](@(Get-Partition -DriveLetter $root.Substring(0, 1) -ErrorAction Stop)[0]).DiskNumber } catch { $dn = -2 }
        if ($dn -eq [int]$Src.DiskNumber) {
            return ('Kurtarma klasörü, taranan diskte (Disk ' + [string]$Src.DiskNumber + ') olamaz. Kurtarılan dosyalar, silinmiş dosyaların yerine yazılıp onları yok edebilir; başka bir disk ya da USB bellek seçin.')
        }
    }
    try {
        if (-not (Test-Path -LiteralPath $d -PathType Container)) { [void][System.IO.Directory]::CreateDirectory($d) }
        $probe = Join-Path $d ('.mm-deneme-' + [System.Guid]::NewGuid().ToString('N') + '.tmp')
        [System.IO.File]::WriteAllText($probe, 'x')
        [System.IO.File]::Delete($probe)
    } catch {
        return ('Kurtarma klasörüne yazılamadı: ' + $_.Exception.Message)
    }
    if (-not $isUnc) {
        try {
            $di = New-Object System.IO.DriveInfo -ArgumentList $root.Substring(0, 1)
            $free = [double]$di.AvailableFreeSpace
            $want = $Need * 1.02 + 16777216
            if ($free -lt $want) {
                return ('Kurtarma klasöründe yeterli boş yer yok: ' + (Format-Size $Need) + ' gerekiyor, ' + (Format-Size $free) + ' var.')
            }
        } catch { }
    }
    return ''
}

# Var olan bir dosyanın üzerine yazmaz: ad doluysa " (2)", " (3)" ... ekler
function global:Get-RcFreeName([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $Path }
    $dir = Split-Path -Parent $Path
    $base = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    $ext = [System.IO.Path]::GetExtension($Path)
    for ($i = 2; $i -lt 1000; $i++) {
        $c = Join-Path $dir ($base + ' (' + [string]$i + ')' + $ext)
        if (-not (Test-Path -LiteralPath $c)) { return $c }
    }
    return (Join-Path $dir ($base + '-' + [System.Guid]::NewGuid().ToString('N').Substring(0, 8) + $ext))
}

function global:ConvertTo-RcDate($FileTime) {
    try {
        $ft = [long]$FileTime
        if ($ft -le 0) { return $null }
        return [System.DateTime]::FromFileTimeUtc($ft)
    } catch { return $null }
}

# Motorun bölüm listesini düz tablolara çevirir: @{ Index; Start; Length; Fs; Kind } dizisi
function global:Convert-RcParts($List) {
    $out = New-Object System.Collections.ArrayList
    foreach ($p in @($List)) {
        if ($null -eq $p) { continue }
        [void]$out.Add(@{ Index = [int]$p.Index; Start = [double]$p.Start; Length = [double]$p.Length; Fs = [string]$p.Fs; Kind = [string]$p.Kind })
    }
    return , $out.ToArray()
}

# P: Source (E:, PhysicalDrive2 ya da imaj dosyası). Yalnızca bölüm düzenini okur (hızlıdır).
# Dönüş: @{ Ok; Error; Parts (Convert-RcParts) }
function global:Job_RecoverParts($P) {
    $res = @{ Ok = $false; Error = ''; Parts = @() }
    $err = Initialize-MmRecover
    if ($err -ne '') { $res.Error = $err; Write-WhLog $err 'ERR'; return $res }
    $src = Resolve-RcSource ([string]$P.Source)
    if ($src.Ok -ne $true) { $res.Error = [string]$src.Error; return $res }
    try {
        $res.Parts = Convert-RcParts ([Mm.RcEngine]::ListPartitions([string]$src.Source))
        $res.Ok = $true
    } catch {
        $res.Error = Get-RcErrorText $_
        Write-WhLog ('Bölümler okunamadı: ' + $res.Error) 'WARN'
    }
    return $res
}

# P: Source (E:, PhysicalDrive2 ya da imaj dosyası), Mode (Quick | Deep | Both), Types (imza türleri; boş = hepsi), MaxResults, Partition
# Dönüş: @{ Ok; Error; Note; Fs; Method (mft | fat | exfat | free | raw); Raw; ClusterSize; VolumeBytes; FreeBytes; Items (Mm.RcItem dizisi);
#          Stats; Truncated; Canceled; Mode; Partitions; PartList }
function global:Job_RecoverScan($P) {
    $res = @{ Ok = $false; Error = ''; Note = ''; Fs = ''; Method = ''; Raw = $false; ClusterSize = 0; VolumeBytes = [double]0; FreeBytes = [double]0; Items = @(); Stats = @{}; Truncated = $false; Canceled = $false; Mode = ''; Partitions = 1; PartList = @() }
    $err = Initialize-MmRecover
    if ($err -ne '') { $res.Error = $err; Write-WhLog $err 'ERR'; return $res }
    $src = Resolve-RcSource ([string]$P.Source)
    if ($src.Ok -ne $true) { $res.Error = [string]$src.Error; Write-WhLog ([string]$src.Error) 'ERR'; return $res }
    $mode = [string]$P.Mode
    if ($mode -ne 'Quick' -and $mode -ne 'Deep' -and $mode -ne 'Both') { $mode = 'Quick' }
    $res.Mode = $mode
    $max = 20000
    if ($null -ne $P.MaxResults -and [int]$P.MaxResults -gt 0) { $max = [int]$P.MaxResults }
    $part = 0
    if ($null -ne $P.Partition) { $part = [int]$P.Partition }
    $types = @()
    if ($null -ne $P.Types) { $types = @($P.Types | ForEach-Object { [string]$_ } | Where-Object { $_ -ne '' }) }
    Write-WhLog ('--- SİLİNEN DOSYALAR: ' + [string]$src.Source + ' taranıyor (salt okunur) ---') 'STEP'
    $cb = [Mm.RcProgress]{
        param([string]$stage, [long]$done, [long]$total)
        $pct = 0
        if ($total -gt 0) { $pct = [int][math]::Min(1000, [math]::Floor($done * 1000.0 / $total)) }
        Set-JobProgress $pct 1000 $stage
        return (-not (Test-JobCancel))
    }
    $eng = $null
    try {
        $eng = [Mm.RcEngine]::Open([string]$src.Source, $part)
        $res.Fs = [string]$eng.Fs
        $res.Method = [string]$eng.Method
        $res.Raw = ($eng.RawMode -eq $true)
        $res.Note = [string]$eng.OpenNote
        $res.ClusterSize = [int]$eng.ClusterSize
        $res.VolumeBytes = [double]$eng.VolumeBytes
        $res.FreeBytes = [double]$eng.StatFreeBytes
        $res.Partitions = [int]$eng.PartitionCount
        $res.PartList = Convert-RcParts $eng.PartList
        Write-WhLog ('Dosya sistemi: ' + $res.Fs + ', küme ' + (Format-Size ([double]$eng.ClusterSize)) + ', ' + $(if ($res.Raw) { 'taranacak alan ' } else { 'boş alan ' }) + (Format-Size $res.FreeBytes)) 'INFO'
        if ($res.Note -ne '') { Write-WhLog $res.Note 'WARN' }
        $hasNames = ($eng.HasNames -eq $true)
        $doMeta = $hasNames -and ($mode -eq 'Quick' -or $mode -eq 'Both')
        $doCarve = ($mode -eq 'Deep' -or $mode -eq 'Both' -or -not $hasNames)
        if ($mode -eq 'Quick' -and -not $hasNames) {
            Write-WhLog ($res.Fs + ' dosya sistemi silinen dosya adlarını okunabilir bırakmıyor; imza taraması yapılıyor.') 'INFO'
        }
        $items = New-Object System.Collections.ArrayList
        $metaCount = 0
        if ($doMeta) {
            $list = $eng.ScanDeleted($cb, $max)
            foreach ($it in $list) { [void]$items.Add($it) }
            $metaCount = $items.Count
            Write-WhLog ([string]$metaCount + ' silinmiş dosya kaydı bulundu.') 'INFO'
        }
        if ($doCarve -and -not $eng.Canceled -and $items.Count -lt $max) {
            $left = $max - $items.Count
            $list2 = $eng.Carve($types, $cb, $left)
            foreach ($it in $list2) { [void]$items.Add($it) }
            Write-WhLog ([string]($items.Count - $metaCount) + ' dosya imza taramasıyla bulundu.') 'INFO'
        }
        $res.Items = @($items.ToArray())
        $res.Truncated = ($eng.Truncated -eq $true)
        $res.Canceled = ($eng.Canceled -eq $true)
        $res.Stats = @{ Records = [double]$eng.StatRecords; Deleted = [double]$eng.StatDeleted; Skipped = [double]$eng.StatSkipped; ReadErrors = [double]$eng.ReadErrors; FromTable = $metaCount; Carved = ($items.Count - $metaCount) }
        if ($eng.StatSkipped -gt 0) { Write-WhLog ([string]$eng.StatSkipped + ' kayıt atlandı (sıkıştırılmış, şifreli ya da bozuk).') 'INFO' }
        if ($eng.ReadErrors -gt 0) { Write-WhLog ([string]$eng.ReadErrors + ' okuma hatası oldu; ilgili bölgeler sıfır sayıldı.') 'WARN' }
        if ($res.Truncated) { Write-WhLog ('Sonuç sayısı ' + [string]$max + ' ile sınırlandı; türü daraltıp yeniden tarayabilirsiniz.') 'WARN' }
        if ($res.Canceled) { Write-WhLog 'Tarama iptal edildi; o ana kadar bulunanlar listelendi.' 'WARN' }
        $res.Ok = $true
    } catch {
        $res.Error = Get-RcErrorText $_
        Write-WhLog ('Tarama yapılamadı: ' + $res.Error) 'ERR'
    } finally {
        if ($null -ne $eng) { $eng.Dispose() }
    }
    return $res
}

# P: Source, Dest (kurtarma klasörü), Items (Mm.RcItem dizisi), KeepPaths ($true: eski klasör yapısı korunur), Partition
# Dönüş: @{ Ok; Error; Dir; Done; Failed; Bytes; Report; Canceled; Results }
function global:Job_RecoverFiles($P) {
    $res = @{ Ok = $false; Error = ''; Dir = ''; Done = 0; Failed = 0; Bytes = [double]0; Report = ''; Canceled = $false; Results = @() }
    $err = Initialize-MmRecover
    if ($err -ne '') { $res.Error = $err; Write-WhLog $err 'ERR'; return $res }
    $src = Resolve-RcSource ([string]$P.Source)
    if ($src.Ok -ne $true) { $res.Error = [string]$src.Error; Write-WhLog ([string]$src.Error) 'ERR'; return $res }
    $items = @($P.Items | Where-Object { $null -ne $_ })
    if ($items.Count -eq 0) { $res.Error = 'Kurtarılacak dosya seçilmedi.'; Write-WhLog $res.Error 'ERR'; return $res }
    $need = [double]0
    foreach ($it in $items) { $need += [double]$it.Length }
    $why = Test-RcDestination $src ([string]$P.Dest) $need
    if ($why -ne '') { $res.Error = $why; Write-WhLog $why 'ERR'; return $res }
    $keep = ($P.KeepPaths -eq $true)
    $part = 0
    if ($null -ne $P.Partition) { $part = [int]$P.Partition }

    # her kurtarma yeni bir klasöre gider
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $runDir = Join-Path ([string]$P.Dest).Trim() ('Multimizer-Kurtarma-' + $stamp)
    $n = 2
    while (Test-Path -LiteralPath $runDir) { $runDir = Join-Path ([string]$P.Dest).Trim() ('Multimizer-Kurtarma-' + $stamp + '-' + [string]$n); $n++ }
    try { [void][System.IO.Directory]::CreateDirectory($runDir) }
    catch { $res.Error = ('Kurtarma klasörü oluşturulamadı: ' + $_.Exception.Message); Write-WhLog $res.Error 'ERR'; return $res }
    $res.Dir = $runDir
    Write-WhLog ('--- DOSYA KURTARMA: ' + [string]$items.Count + ' dosya, ' + (Format-Size $need) + ' -> ' + $runDir + ' ---') 'STEP'

    $doneBytes = [double]0
    $curBase = [double]0
    $cb = [Mm.RcProgress]{
        param([string]$stage, [long]$done, [long]$total)
        $all = $need
        if ($all -le 0) { $all = 1 }
        $pct = [int][math]::Min(1000, [math]::Floor(($curBase + [double]$done) * 1000.0 / $all))
        Set-JobProgress $pct 1000 'Kurtarılıyor'
        return (-not (Test-JobCancel))
    }
    $eng = $null
    $rows = New-Object System.Collections.ArrayList
    try {
        $eng = [Mm.RcEngine]::Open([string]$src.Source, $part)
        foreach ($it in $items) {
            if (Test-JobCancel) { $res.Canceled = $true; Write-WhLog 'İptal edildi.' 'WARN'; break }
            $row = @{ Name = [string]$it.Name; Path = ''; Ok = $false; Bytes = [double]0; Note = '' }
            $name = [Mm.RcEngine]::SafeName([string]$it.Name)
            $dir = $runDir
            if ([string]$it.Kind -eq 'carve') {
                $dir = Join-Path $runDir 'İmza taraması'
            } elseif ($keep) {
                $rel = [Mm.RcEngine]::SafeRelPath([string]$it.Path)
                if ($rel -ne '') { $dir = Join-Path $runDir $rel }
            }
            if (($dir.Length + $name.Length + 2) -gt 240) { $dir = $runDir }
            if (($dir.Length + $name.Length + 2) -gt 240) {
                $ext = [System.IO.Path]::GetExtension($name)
                $name = $name.Substring(0, [math]::Max(1, 240 - $dir.Length - 2 - $ext.Length)) + $ext
            }
            $target = ''
            $fs = $null
            $okFile = $false
            try {
                [void][System.IO.Directory]::CreateDirectory($dir)
                $target = Get-RcFreeName (Join-Path $dir $name)
                $fs = New-Object System.IO.FileStream -ArgumentList $target, ([System.IO.FileMode]::CreateNew), ([System.IO.FileAccess]::Write), ([System.IO.FileShare]::None), 65536
                $curBase = $doneBytes
                $got = [long]$eng.Extract($it, $fs, $cb)
                $fs.Flush()
                $row.Bytes = [double]$got
                if ($got -lt [long]$it.Length) {
                    $row.Note = 'Okunabilen veri beklenenden kısa; dosya kaydedilmedi.'
                } else {
                    $okFile = $true
                    $row.Note = [string]$eng.LastNote
                }
            } catch [System.OperationCanceledException] {
                $res.Canceled = $true
                $row.Note = 'İptal edildi.'
            } catch {
                $row.Note = (Get-RcErrorText $_)
            } finally {
                if ($null -ne $fs) { $fs.Dispose() }
            }
            if ($okFile) {
                $dt = ConvertTo-RcDate $it.Modified
                if ($null -ne $dt) { try { [System.IO.File]::SetLastWriteTimeUtc($target, $dt) } catch { } }
                $row.Ok = $true
                $row.Path = $target
                $res.Done++
                $res.Bytes += [double]$row.Bytes
                $doneBytes += [double]$it.Length
            } else {
                if ($target -ne '' -and (Test-Path -LiteralPath $target)) { try { [System.IO.File]::Delete($target) } catch { } }
                $res.Failed++
                Write-WhLog ('Kurtarılamadı: ' + [string]$it.Name + ' (' + [string]$row.Note + ')') 'WARN'
            }
            [void]$rows.Add($row)
            if ($res.Canceled) { Write-WhLog 'İptal edildi.' 'WARN'; break }
        }
    } catch {
        $res.Error = Get-RcErrorText $_
        Write-WhLog ('Kurtarma yapılamadı: ' + $res.Error) 'ERR'
    } finally {
        if ($null -ne $eng) { $eng.Dispose() }
    }
    $res.Results = @($rows.ToArray())

    # özet rapor (noktalı virgülle ayrılmış, Excel'de açılır)
    try {
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.AppendLine('Dosya;Kaydedilen yol;Boyut (bayt);Durum;Not')
        foreach ($r in $rows) {
            $st = 'Kurtarılamadı'
            if ($r.Ok -eq $true) { $st = 'Kurtarıldı' }
            $line = @([string]$r.Name, [string]$r.Path, [string][long]$r.Bytes, $st, [string]$r.Note) | ForEach-Object { '"' + ([string]$_).Replace('"', '""') + '"' }
            [void]$sb.AppendLine(($line -join ';'))
        }
        $rp = Join-Path $runDir 'Kurtarma-Raporu.csv'
        [System.IO.File]::WriteAllText($rp, $sb.ToString(), (New-Object System.Text.UTF8Encoding($true)))
        $res.Report = $rp
    } catch { }
    Write-WhLog ('Kurtarma tamamlandı: ' + [string]$res.Done + ' dosya, ' + (Format-Size $res.Bytes) + ', ' + [string]$res.Failed + ' kurtarılamadı') 'INFO'
    $res.Ok = ($res.Error -eq '' -and $res.Done -gt 0)
    return $res
}
