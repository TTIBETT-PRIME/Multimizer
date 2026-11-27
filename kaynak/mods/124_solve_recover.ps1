# ==================================================================
#  ÇÖZÜM MERKEZİ: "Silinen dosyalar" sekmesi
#  Sürücüyü ya da disk imajını yalnızca okur; bulunan dosyaları taranandan FARKLI bir sürücüye, yeni bir klasöre kaydeder.
#  Tarama ve kurtarma işleri "Kurtarma" eklentisindedir (Job_RecoverScan, Job_RecoverFiles); bu dosya arayüzü ve saf yardımcıları içerir.
# ==================================================================
$script:RcSelKey = ''
$script:RcSource = ''
$script:RcSourceKind = ''
$script:RcPart = 0
$script:RcImage = ''
$script:RcImageParts = 1
$script:RcDisk = -1
$script:RcPartCache = @{}
$script:RcPartPend = ''
$script:RcItems = @()
$script:RcMeta = $null
$script:RcScanError = ''
$script:RcGroup = 'all'
$script:RcDest = ''
$script:RcLastRun = $null
$script:RcLoading = $false
$script:RcFindTimer = $null
$script:RcRowCap = 300
$script:RcMaxResults = 20000
$script:RcPendItems = @()
$script:RcPendSource = ''
$script:RcPendPart = 0
$script:RcPendDest = ''
$script:RcPendMode = ''
$script:RcGroupNames = [ordered]@{ all = 'Tümü'; img = 'Resimler'; doc = 'Belgeler'; media = 'Ses ve video'; arch = 'Arşivler'; other = 'Diğer' }

# ---------------- saf yardımcılar (arayüzden bağımsız, testlenir) ----------------
function Get-RcExtTable {
    $defs = @(
        @{ G = 'img'; E = 'jpg jpeg jpe png gif bmp webp heic heif tif tiff ico svg psd raw cr2 cr3 nef arw dng orf rw2' },
        @{ G = 'doc'; E = 'pdf doc docx dot dotx xls xlsx xlsm ppt pptx odt ods odp txt rtf csv md epub xml html htm json msg eml pst one' },
        @{ G = 'media'; E = 'mp4 m4v avi mkv mov wmv flv webm mpg mpeg 3gp mp3 wav flac aac ogg m4a wma opus' },
        @{ G = 'arch'; E = 'zip rar 7z gz tgz tar bz2 xz cab iso apk jar' }
    )
    $t = @{}
    foreach ($d in $defs) {
        foreach ($x in ([string]$d.E).Split(' ')) { if ($x -ne '') { $t[$x] = [string]$d.G } }
    }
    return $t
}
$script:RcExtGroup = Get-RcExtTable

# Dosya uzantısının tür grubu: img | doc | media | arch | other
function Get-RcGroup([string]$Ext) {
    $e = ([string]$Ext).Trim().TrimStart('.').ToLowerInvariant()
    $g = $script:RcExtGroup[$e]
    if ($null -eq $g) { return 'other' }
    return [string]$g
}

# Listelenebilir (şansı sıfırdan büyük) dosyaların tür grubuna göre sayısı
function Get-RcGroupCounts($Items) {
    $c = @{ all = 0; img = 0; doc = 0; media = 0; arch = 0; other = 0 }
    foreach ($it in @($Items)) {
        if ($null -eq $it -or [int]$it.Chance -le 0) { continue }
        $c.all++
        $g = $script:RcExtGroup[([string]$it.Ext).Trim().TrimStart('.').ToLowerInvariant()]
        if ($null -eq $g) { $g = 'other' }
        $c[[string]$g]++
    }
    return $c
}

function Format-RcChance([int]$Chance) {
    $w = 'düşük'
    if ($Chance -ge 90) { $w = 'çok yüksek' } elseif ($Chance -ge 70) { $w = 'yüksek' } elseif ($Chance -ge 40) { $w = 'orta' }
    return ('%' + [string]$Chance + '  ·  ' + $w)
}

function Get-RcChanceBr([int]$Chance) {
    if ($Chance -ge 70) { return 'BrGood' }
    if ($Chance -ge 40) { return 'BrWarn' }
    return 'BrBad'
}

# FILETIME (UTC) -> yerel saat; geçersizse $null
function ConvertFrom-RcTime($Ft) {
    try {
        $v = [long]$Ft
        if ($v -le 0) { return $null }
        $d = [System.DateTime]::FromFileTimeUtc($v)
        if ($d.Year -lt 1990 -or $d.Year -gt 2100) { return $null }
        return $d.ToLocalTime()
    } catch { return $null }
}

function Format-RcDate($Ft) {
    $d = ConvertFrom-RcTime $Ft
    if ($null -eq $d) { return '' }
    return $d.ToString('dd.MM.yyyy HH:mm')
}

# Ham dosya adlarındaki denetim karakterleri ve eşsiz vekil karakterler XAML'i bozar; ekranda "_" gösterilir
function Remove-RcControl([string]$Text) {
    if ($null -eq $Text -or $Text -eq '') { return '' }
    $t = [regex]::Replace($Text, '[\u0000-\u001F\u007F\uFFFE\uFFFF]', '_')
    return [regex]::Replace($t, '[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]', '_')
}

# Bulunan bir dosyanın satır metinleri: @{ Title; Detail; Tag; BrCol }
function New-RcRowModel($It) {
    $name = Remove-RcControl ([string]$It.Name)
    if ($name.Trim() -eq '') { $name = '(adsız)' }
    $parts = New-Object System.Collections.ArrayList
    if ([string]$It.Kind -eq 'carve') {
        [void]$parts.Add('İmza taramasıyla bulundu')
    } else {
        $p = Remove-RcControl ([string]$It.Path)
        if ($p -eq '') { $p = '(sürücünün kökü)' }
        [void]$parts.Add($p)
    }
    [void]$parts.Add((Format-Size ([double]$It.Length)))
    $m = Format-RcDate $It.Modified
    if ($m -ne '') { [void]$parts.Add('değişiklik ' + $m) }
    if ([string]$It.Kind -ne 'carve') {
        $dd = Format-RcDate $It.Deleted
        if ($dd -ne '') { [void]$parts.Add('silinme ' + $dd) }
    }
    $det = ($parts.ToArray() -join '  ·  ')
    $note = Remove-RcControl ([string]$It.Note)
    if ($note -ne '') { $det += "`r`n" + $note }
    $ch = [int]$It.Chance
    return @{ Title = $name; Detail = $det; Tag = (Format-RcChance $ch); BrCol = (Get-RcChanceBr $ch) }
}

# Listelenecek dosyalar: tür ve arama süzgeci, şansa göre sıralama, satır sınırı.
# Dönüş: @{ Rows (Idx, Chance dizisi); Matched; Hidden; Total }  (Hidden: şansı sıfır olduğu için gizlenenler)
function Get-RcDisplay($Items, [string]$Group, [string]$Query, [int]$Cap) {
    $q = ([string]$Query).Trim()
    $list = New-Object System.Collections.ArrayList
    $hidden = 0
    $i = -1
    foreach ($it in @($Items)) {
        $i++
        if ($null -eq $it) { continue }
        if ([int]$it.Chance -le 0) { $hidden++; continue }
        if ($Group -ne 'all' -and $Group -ne '') {
            $g = $script:RcExtGroup[([string]$it.Ext).Trim().TrimStart('.').ToLowerInvariant()]
            if ($null -eq $g) { $g = 'other' }
            if ([string]$g -ne $Group) { continue }
        }
        if ($q -ne '') {
            $nm = [string]$it.Name
            $pt = [string]$it.Path
            if ($nm.IndexOf($q, [System.StringComparison]::OrdinalIgnoreCase) -lt 0 -and $pt.IndexOf($q, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }
        }
        [void]$list.Add([pscustomobject]@{ Idx = $i; Chance = [int]$it.Chance; Del = [long]$it.Deleted; Name = [string]$it.Name })
    }
    $matched = $list.Count
    $sorted = @($list.ToArray() | Sort-Object -Property @{ Expression = 'Chance'; Descending = $true }, @{ Expression = 'Del'; Descending = $true }, @{ Expression = 'Name'; Descending = $false })
    if ($Cap -gt 0 -and $sorted.Count -gt $Cap) { $sorted = @($sorted | Select-Object -First $Cap) }
    return @{ Rows = $sorted; Matched = $matched; Hidden = $hidden; Total = ($i + 1) }
}

# Sürücü seçicideki satır metni
function Get-RcVolumeName($D, [string]$OsDrive) {
    $parts = New-Object System.Collections.ArrayList
    $head = [string]$D.Drive
    $lbl = ([string]$D.Label).Trim()
    if ($lbl -ne '') { $head += '  ' + $lbl }
    [void]$parts.Add($head)
    $fs = ([string]$D.Fs).Trim()
    if ($fs -eq '') { $fs = 'dosya sistemi yok' }
    [void]$parts.Add($fs)
    if ([double]$D.Size -gt 0) { [void]$parts.Add((Format-Size ([double]$D.Size))) }
    if ([string]$D.Bus -eq 'USB') { [void]$parts.Add('USB') }
    elseif ([string]$D.Media -eq 'SSD' -or [string]$D.Media -eq 'HDD') { [void]$parts.Add([string]$D.Media) }
    if ([string]$D.Drive -eq $OsDrive) { [void]$parts.Add('Windows') }
    if ([string]$D.State -eq 'locked') { [void]$parts.Add('kilitli') }
    return ($parts.ToArray() -join '  ·  ')
}

# Fiziksel diskin seçici satırındaki adı: "Disk 2  SanDisk Ultra  ·  29,8 GB  ·  USB"
function Get-RcDiskName($Dk) {
    $head = 'Disk ' + [string]$Dk.Number
    $nm = ([string]$Dk.Name).Trim()
    if ($nm -ne '') { $head += '  ' + $nm }
    $parts = New-Object System.Collections.ArrayList
    [void]$parts.Add($head)
    if ([double]$Dk.Size -gt 0) { [void]$parts.Add((Format-Size ([double]$Dk.Size))) }
    if ([string]$Dk.Bus -eq 'USB') { [void]$parts.Add('USB') }
    elseif ([string]$Dk.Media -eq 'SSD' -or [string]$Dk.Media -eq 'HDD') { [void]$parts.Add([string]$Dk.Media) }
    if ($Dk.IsSystem -eq $true) { [void]$parts.Add('Windows') }
    return ($parts.ToArray() -join '  ·  ')
}

# Bölümün dosya sistemi adı (şifreli bölümler açıkça belirtilir)
function Get-RcFsText([string]$Fs) {
    $f = ([string]$Fs).Trim()
    if ($f -ceq 'BITLOCKER') { return 'BitLocker (şifreli)' }
    if ($f -ceq 'LUKS') { return 'LUKS (şifreli)' }
    if ($f -eq '') { return 'biçim tanınmadı' }
    return $f
}

# Bölümün seçici satırındaki metni: "bölüm 2/3  ·  NTFS  ·  50 GB  ·  E:"
function Get-RcPartText($P, [int]$Count, [string]$Letter) {
    $t = 'bölüm ' + [string]([int]$P.Index + 1) + '/' + [string]$Count
    $t += '  ·  ' + (Get-RcFsText ([string]$P.Fs))
    if ([double]$P.Length -gt 0) { $t += '  ·  ' + (Format-Size ([double]$P.Length)) }
    if ($Letter -ne '') { $t += '  ·  ' + $Letter }
    return $t
}

# Bölümün Windows’ta sürücü harfi var mı? Başlangıç konumuna göre eşleştirilir; yoksa ''
function Get-RcPartLetter($Dk, $P) {
    if ($null -eq $Dk) { return '' }
    foreach ($wp in @($Dk.Parts)) {
        if ($null -eq $wp) { continue }
        if ([math]::Abs([double]$wp.Offset - [double]$P.Start) -lt 1 -and [string]$wp.Letter -ne '') { return [string]$wp.Letter }
    }
    return ''
}

function New-RcChoice([string]$Key, [string]$Name, [string]$Kind) {
    $c = New-Choice $Key $Name
    $c.Kind = $Kind
    $c.Locked = $false
    $c.Media = ''
    $c.Removable = $false
    $c.IsOs = $false
    $c.Loaded = $true
    $c.Whole = $false
    $c.DiskNo = -1
    $c.Letters = @()
    return $c
}

# Bir fiziksel diskin ya da imajın seçici satırları. Bölümler okunduysa her bölüm ayrı satırdır, ayrıca "tüm disk" satırı eklenir;
# okunmadıysa disk için tek satır döner (Loaded = $false) ve seçilince bölümler okunur.
# $KeyBase: 'PD:2' ya da 'IMG'; $Cache: Job_RecoverParts sonucu ($null = okunmadı); $Dk: fiziksel disk bilgisi ($null = imaj); $KnownParts: imajda bilinen bölüm sayısı
function Add-RcSourceChoices($Out, [string]$Kind, [string]$Title, [string]$KeyBase, $Cache, $Dk, [int]$KnownParts) {
    $isDisk = ($Kind -eq 'Disk')
    $loaded = ($null -ne $Cache -and $Cache.Ok -eq $true)
    $dn = -1
    $letters = @()
    $media = ''
    $isOs = $false
    $removable = $false
    if ($isDisk -and $null -ne $Dk) {
        $dn = [int]$Dk.Number
        $letters = @($Dk.Letters)
        $isOs = ($Dk.IsSystem -eq $true)
        $removable = ([string]$Dk.Bus -eq 'USB')
        $media = [string]$Dk.Media
    }
    if (-not $loaded) {
        if ($isDisk -or $KnownParts -le 1) {
            $name = $Title
            if ($isDisk) {
                if ($null -ne $Cache -and [string]$Cache.Error -ne '') { $name += '  ·  bölümler okunamadı' } else { $name += '  ·  bölümleri okumak için seçin' }
            }
            $k = $KeyBase
            if (-not $isDisk) { $k = $KeyBase + ':0' }
            $c = New-RcChoice $k $name $Kind
            $c.Loaded = (-not $isDisk)
            $c.DiskNo = $dn; $c.Letters = $letters; $c.IsOs = $isOs; $c.Removable = $removable; $c.Media = $media
            [void]$Out.Add($c)
            return
        }
        for ($i = 0; $i -lt $KnownParts; $i++) {
            $c = New-RcChoice ($KeyBase + ':' + [string]$i) ($Title + '  ·  bölüm ' + [string]($i + 1) + '/' + [string]$KnownParts) $Kind
            [void]$Out.Add($c)
        }
        return
    }
    $list = @($Cache.Parts)
    if ($list.Count -eq 0) {
        $c = New-RcChoice ($KeyBase + ':0') ($Title + '  ·  bölüm düzeni ya da dosya sistemi tanınmadı (tüm alan imza taraması)') $Kind
        $c.DiskNo = $dn; $c.Letters = $letters; $c.IsOs = $isOs; $c.Removable = $removable; $c.Media = $media
        [void]$Out.Add($c)
        return
    }
    $single = ($list.Count -eq 1 -and [string]$list[0].Kind -eq 'birim')
    foreach ($p in $list) {
        $label = ''
        if ($single) {
            $label = (Get-RcFsText ([string]$p.Fs))
            if ([double]$p.Length -gt 0) { $label += '  ·  ' + (Format-Size ([double]$p.Length)) }
        } else {
            $label = Get-RcPartText $p $list.Count (Get-RcPartLetter $Dk $p)
        }
        $c = New-RcChoice ($KeyBase + ':' + [string][int]$p.Index) ($Title + '  ·  ' + $label) $Kind
        $c.Locked = ([string]$p.Fs -ceq 'BITLOCKER')
        $c.DiskNo = $dn; $c.Letters = $letters; $c.IsOs = $isOs; $c.Removable = $removable; $c.Media = $media
        [void]$Out.Add($c)
    }
    if (-not $single) {
        $c = New-RcChoice ($KeyBase + ':all') ($Title + '  ·  tüm disk, bölümlere bakmadan (imza taraması)') $Kind
        $c.Whole = $true
        $c.DiskNo = $dn; $c.Letters = $letters; $c.IsOs = $isOs; $c.Removable = $removable; $c.Media = $media
        [void]$Out.Add($c)
    }
}

# Sürücü seçicinin öğeleri (New-Choice biçiminde; Kind, Locked, Media, Removable, IsOs, Loaded, Whole, DiskNo, Letters eklenir).
# $Phys: fiziksel diskler (Job_SlvDisks), $Cache: kaynak adı (PhysicalDrive2 ya da imaj yolu) -> Job_RecoverParts sonucu
function Get-RcVolumeChoices($Disks, [string]$OsDrive, [string]$Image, [int]$Parts, $Phys = $null, $Cache = $null) {
    $out = New-Object System.Collections.ArrayList
    foreach ($d in @($Disks)) {
        if ($null -eq $d) { continue }
        $c = New-RcChoice ([string]$d.Drive) (Get-RcVolumeName $d $OsDrive) 'Drive'
        $c.Locked = ([string]$d.State -eq 'locked')
        $c.Media = [string]$d.Media
        $c.Removable = ([string]$d.Type -eq 'Removable' -or [string]$d.Bus -eq 'USB')
        $c.IsOs = ([string]$d.Drive -eq $OsDrive)
        [void]$out.Add($c)
    }
    foreach ($dk in @($Phys)) {
        if ($null -eq $dk -or [double]$dk.Size -le 0) { continue }
        $src = 'PhysicalDrive' + [string]$dk.Number
        $cached = $null
        if ($null -ne $Cache -and $Cache.ContainsKey($src)) { $cached = $Cache[$src] }
        Add-RcSourceChoices $out 'Disk' (Get-RcDiskName $dk) ('PD:' + [string]$dk.Number) $cached $dk 0
    }
    if ($Image -ne '') {
        $cached = $null
        if ($null -ne $Cache -and $Cache.ContainsKey($Image)) { $cached = $Cache[$Image] }
        $fn = [System.IO.Path]::GetFileName($Image)
        Add-RcSourceChoices $out 'Image' ('Disk imajı: ' + $fn) 'IMG' $cached $null $Parts
    }
    return , $out.ToArray()
}

# Seçici anahtarı -> kaynak. Dönüş: @{ Kind (Drive | Disk | Image | ''); Source; Part (-1: tüm disk); Disk (fiziksel disk numarası, yoksa -1) }
# Anahtarlar: "E:" (sürücü), "PD:2" (disk, bölümler okunmadı), "PD:2:1" (disk 2, ikinci bölüm), "PD:2:all" (tüm disk), "IMG:1", "IMG:all"
function Resolve-RcKey([string]$Key, [string]$Image) {
    if ($Key -match '^IMG:all$') { return @{ Kind = 'Image'; Source = $Image; Part = -1; Disk = -1 } }
    if ($Key -match '^IMG:(\d+)$') { return @{ Kind = 'Image'; Source = $Image; Part = [int]$Matches[1]; Disk = -1 } }
    if ($Key -match '^PD:(\d{1,4}):all$') { $n = [int]$Matches[1]; return @{ Kind = 'Disk'; Source = ('PhysicalDrive' + [string]$n); Part = -1; Disk = $n } }
    if ($Key -match '^PD:(\d{1,4}):(\d+)$') { $n = [int]$Matches[1]; return @{ Kind = 'Disk'; Source = ('PhysicalDrive' + [string]$n); Part = [int]$Matches[2]; Disk = $n } }
    if ($Key -match '^PD:(\d{1,4})$') { $n = [int]$Matches[1]; return @{ Kind = 'Disk'; Source = ('PhysicalDrive' + [string]$n); Part = 0; Disk = $n } }
    if ($Key -cmatch '^[A-Za-z]:$') { return @{ Kind = 'Drive'; Source = $Key.ToUpperInvariant(); Part = 0; Disk = -1 } }
    return @{ Kind = ''; Source = ''; Part = 0; Disk = -1 }
}

# Kurtarma klasörü, taranan sürücüde ya da diskte olmamalı (eklenti de aynısını denetler). $DiskLetters: taranan fiziksel diskteki sürücü harfleri
# Dönüş: '' = uygun, aksi hâlde neden
function Test-RcDestUi([string]$Source, [string]$Kind, [string]$Dest, $DiskLetters = $null) {
    $d = ([string]$Dest).Trim()
    if ($d -eq '') { return 'Kurtarma klasörü seçilmedi.' }
    if ($d -cnotmatch '^([A-Za-z]:[\\/]|\\\\[^\\/])') { return 'Kurtarma klasörü tam bir yol olmalı (örneğin D:\Kurtarilan).' }
    if ($Kind -eq 'Drive' -and $Source.Length -ge 1 -and $d.Length -ge 2 -and $d.Substring(1, 1) -eq ':' -and $d.Substring(0, 1).ToUpperInvariant() -eq $Source.Substring(0, 1).ToUpperInvariant()) {
        return ('Kurtarma klasörü, taranan ' + $Source.Substring(0, 1).ToUpperInvariant() + ': sürücüsünde olamaz. Kurtarılan dosyalar, silinmiş dosyaların yerine yazılıp onları yok edebilir; başka bir sürücü ya da USB bellek seçin.')
    }
    if ($Kind -eq 'Disk' -and $d.Length -ge 2 -and $d.Substring(1, 1) -eq ':') {
        $l = $d.Substring(0, 1).ToUpperInvariant() + ':'
        foreach ($x in @($DiskLetters)) {
            if (([string]$x).ToUpperInvariant() -eq $l) {
                $no = ''
                if ($Source -match '(\d+)$') { $no = $Matches[1] }
                return ('Kurtarma klasörü, taranan diskte (Disk ' + $no + ') olamaz. Kurtarılan dosyalar, silinmiş dosyaların yerine yazılıp onları yok edebilir; başka bir disk ya da USB bellek seçin.')
            }
        }
    }
    return ''
}

# Tarama sonuç özeti: @{ T; K (dim | warn) } satırları
function Get-RcSummaryLines($Meta, [int]$Found, [int]$Hidden) {
    $out = New-Object System.Collections.ArrayList
    $method = [string]$Meta.Method
    $deep = ([string]$Meta.Mode -eq 'Both' -or [string]$Meta.Mode -eq 'Deep')
    $mode = 'hızlı tarama'
    if ($method -eq 'raw') { $mode = 'tüm alanda imza taraması' }
    elseif ($method -eq 'free') { $mode = 'boş alanda imza taraması' }
    elseif ($deep) { $mode = 'derin tarama' }
    elseif ($method -eq '' -and [string]$Meta.Fs -ne 'NTFS') { $mode = 'imza taraması' }
    $l1 = [string]$Meta.Fs
    if ([int]$Meta.ClusterSize -gt 0) { $l1 += '  ·  küme ' + (Format-Size ([double]$Meta.ClusterSize)) }
    if ([double]$Meta.FreeBytes -gt 0) {
        if ($Meta.Raw -eq $true) { $l1 += '  ·  taranan alan ' + (Format-Size ([double]$Meta.FreeBytes)) } else { $l1 += '  ·  boş alan ' + (Format-Size ([double]$Meta.FreeBytes)) }
    }
    $l1 += '  ·  ' + $mode
    [void]$out.Add(@{ T = $l1; K = 'dim' })
    if ([string]$Meta.Note -ne '') { [void]$out.Add(@{ T = [string]$Meta.Note; K = 'warn' }) }
    $st = $Meta.Stats
    if ($Found -gt 0) {
        $l2 = [string]$Found + ' dosya bulundu'
        if ($null -ne $st) {
            $a = [int]$st.FromTable
            $b = [int]$st.Carved
            if ($a -gt 0 -and $b -gt 0) { $l2 += ' (' + [string]$a + ' silinmiş kayıttan, ' + [string]$b + ' imza taramasıyla)' }
            elseif ($b -gt 0 -and $a -eq 0) { $l2 += ' (imza taramasıyla; dosya adı ve tarihi bilinmez)' }
        }
        [void]$out.Add(@{ T = ($l2 + '.'); K = 'dim' })
    }
    if ($Hidden -gt 0) { [void]$out.Add(@{ T = ([string]$Hidden + ' kayıt, disk alanı başka dosyalarca kullanıldığı (üzerine yazıldığı) için listelenmedi.'); K = 'dim' }) }
    if ($null -ne $st -and [int]$st.Skipped -gt 0) { [void]$out.Add(@{ T = ([string][int]$st.Skipped + ' kayıt atlandı: sıkıştırılmış, şifreli ya da bozuk dosyalar kurtarılamaz.'); K = 'dim' }) }
    if ($null -ne $st -and [double]$st.ReadErrors -gt 0) { [void]$out.Add(@{ T = ([string][int]$st.ReadErrors + ' okuma hatası oldu; ilgili bölgeler sıfır sayıldı, disk sorunlu olabilir.'); K = 'warn' }) }
    if ($Meta.Truncated -eq $true) { [void]$out.Add(@{ T = ('Sonuçlar ilk ' + [string]$script:RcMaxResults + ' kayıtla sınırlı; türü ya da sürücüyü daraltıp yeniden tarayabilirsiniz.'); K = 'warn' }) }
    if ($Meta.Canceled -eq $true) { [void]$out.Add(@{ T = 'Tarama yarıda kesildi; o ana kadar bulunanlar listelendi.'; K = 'warn' }) }
    return , $out.ToArray()
}

# Onay penceresinin metni
function Get-RcConfirmText($Items, [string]$Dest) {
    $n = 0
    $bytes = [double]0
    $low = 0
    foreach ($it in @($Items)) {
        $n++
        $bytes += [double]$it.Length
        if ([int]$it.Chance -lt 70) { $low++ }
    }
    $t = [string]$n + ' dosya (' + (Format-Size $bytes) + ') kurtarılacak.' + "`r`n`r`n"
    $t += 'Kaydedileceği yer: ' + $Dest + "`r`n" + 'Bu klasörün içinde “Multimizer-Kurtarma-…” adında yeni bir klasör açılır; var olan hiçbir dosyanın üzerine yazılmaz.' + "`r`n`r`n"
    $t += 'Taranan sürücüye ya da imaja hiçbir şey yazılmaz.'
    if ($low -gt 0) { $t += "`r`n`r`n" + [string]$low + ' dosyanın kurtarılma şansı düşük ya da orta; bunlar eksik ya da bozuk çıkabilir.' }
    return $t
}

function Get-RcFootText([int]$Count, [double]$Bytes, [string]$Dest) {
    $t = 'Seçili: ' + [string]$Count + ' dosya'
    if ($Count -gt 0) { $t += '  ·  ' + (Format-Size $Bytes) }
    if ($Dest -ne '') { $t += '  ·  Hedef: ' + $Dest } else { $t += '  ·  Hedef klasör henüz seçilmedi' }
    return $t
}

# ---------------- seçiciler ----------------
function Get-RcSelectedChoice {
    $it = $ui.sl_RcVol.SelectedItem
    if ($null -eq $it) { return $null }
    return $it
}

# Seçili anahtardan kaynak bilgisini yeniler; sonuçlar başka bir kaynağa aitse temizler
function Set-RcSourceFromKey {
    $r = Resolve-RcKey $script:RcSelKey $script:RcImage
    if ($null -ne $script:RcMeta -and ([string]$script:RcMeta.Source -ne [string]$r.Source -or [int]$script:RcMeta.Part -ne [int]$r.Part)) { Reset-RcResults }
    $script:RcSource = [string]$r.Source
    $script:RcSourceKind = [string]$r.Kind
    $script:RcPart = [int]$r.Part
    $script:RcDisk = [int]$r.Disk
    # önceden seçilen kurtarma klasörü yeni kaynakta geçersizse unutulur
    if ($script:RcDest -ne '') {
        $why = Test-RcDestUi $script:RcSource $script:RcSourceKind $script:RcDest (Get-RcSelectedLetters)
        if ($why -ne '') { $script:RcDest = '' }
    }
}

# Seçili fiziksel diskteki sürücü harfleri (kurtarma klasörü bu diskte olamaz)
function Get-RcSelectedLetters {
    $ch = Get-RcSelectedChoice
    if ($null -eq $ch -or [string]$ch.Kind -ne 'Disk') { return @() }
    return @($ch.Letters)
}

function Reset-RcResults {
    $script:RcItems = @()
    $script:RcMeta = $null
    $script:RcScanError = ''
    $script:RcLastRun = $null
}

function Update-RcVolumeCombo {
    $disks = @()
    $phys = @()
    $os = ''
    $d = $script:SlDisks
    if ($null -ne $d -and $d.Failed -ne $true) {
        $disks = @($d.Disks)
        $os = [string]$d.Sys.OsDrive
        if ($null -ne $d.Phys) { $phys = @($d.Phys) }
    }
    $choices = Get-RcVolumeChoices $disks $os $script:RcImage $script:RcImageParts $phys $script:RcPartCache
    $script:RcLoading = $true
    try {
        Set-ComboChoices $ui.sl_RcVol $choices
        $key = $script:RcSelKey
        $found = $false
        foreach ($c in $choices) { if ([string]$c.Key -eq $key) { $found = $true } }
        if (-not $found) {
            $key = ''
            foreach ($c in $choices) { if ($c.IsOs -eq $true) { $key = [string]$c.Key; break } }
            if ($key -eq '' -and @($choices).Count -gt 0) { $key = [string]@($choices)[0].Key }
        }
        if ($key -ne '') { [void](Select-ComboKey $ui.sl_RcVol $key) }
        $script:RcSelKey = $key
    } finally { $script:RcLoading = $false }
    Set-RcSourceFromKey
}

function Update-RcTypeCombo {
    $cnt = Get-RcGroupCounts $script:RcItems
    $list = New-Object System.Collections.ArrayList
    foreach ($k in @($script:RcGroupNames.Keys)) {
        $nm = [string]$script:RcGroupNames[$k]
        if ($null -ne $script:RcMeta) { $nm += ' (' + [string]$cnt[$k] + ')' }
        [void]$list.Add((New-Choice $k $nm))
    }
    $script:RcLoading = $true
    try {
        Set-ComboChoices $ui.sl_RcType $list.ToArray()
        if (-not (Select-ComboKey $ui.sl_RcType $script:RcGroup)) { $script:RcGroup = 'all'; [void](Select-ComboKey $ui.sl_RcType 'all') }
    } finally { $script:RcLoading = $false }
}

function Select-RcVolume {
    if ($script:RcLoading -eq $true) { return }
    $k = Get-ComboKey $ui.sl_RcVol
    if ($k -eq '') { return }
    $script:RcSelKey = $k
    Set-RcSourceFromKey
    Update-RcTypeCombo
    Render-RcBody
    $ch = Get-RcSelectedChoice
    if ($null -ne $ch -and $ch.Loaded -eq $false -and [string]$ch.Kind -eq 'Disk') { Start-RcParts $script:RcSource }
}

function Select-RcGroup {
    if ($script:RcLoading -eq $true) { return }
    $k = Get-ComboKey $ui.sl_RcType
    if ($k -eq '') { return }
    $script:RcGroup = $k
    Render-RcBody
}

function Select-RcImage {
    $f = Select-OpenFile 'Ham disk imajı (*.img;*.dd;*.raw;*.bin;*.001)|*.img;*.dd;*.raw;*.bin;*.001|Tüm dosyalar (*.*)|*.*'
    if ($f -eq '') { return }
    $script:RcImage = $f
    $script:RcImageParts = 1
    $script:RcSelKey = 'IMG:0'
    $script:RcPartCache.Remove($f)
    Reset-RcResults
    Update-RcVolumeCombo
    Update-RcTypeCombo
    Render-RcBody
    Start-RcParts $f
}

function Select-RcDest {
    $d = Select-Folder 'Kurtarılan dosyaların kaydedileceği klasörü seçin (taranan sürücüden farklı bir sürücüde olmalı)'
    if ($d -eq '') { return '' }
    $why = Test-RcDestUi $script:RcSource $script:RcSourceKind $d (Get-RcSelectedLetters)
    if ($why -ne '') { Show-Toast $why 'warn'; return '' }
    $script:RcDest = $d
    Update-RcFoot
    return $d
}

# ---------------- çizim ----------------
$script:H_RcChk = { param($s, $e) Invoke-Safe { Update-RcFoot } 'Seçim' }
$script:H_RcAct = { param($s, $e) Invoke-Safe { Invoke-RcAction $s.Tag } 'Eylem' }

function Invoke-RcAction($T) {
    switch ([string]$T.Do) {
        'RcBin'    { Open-Path 'shell:RecycleBinFolder' }
        'RcDir'    { if ([string]$T.Dir -ne '') { Open-Folder ([string]$T.Dir) } }
        'RcReport' { if ([string]$T.Report -ne '') { Open-Path ([string]$T.Report) } }
    }
}

function Update-RcFoot {
    if ([string]$script:UiState.Page -ne 'solve' -or $script:SlTab -ne 'recover') { return }
    $n = 0
    $bytes = [double]0
    $chk = Get-CheckedData $ui.sl_List
    foreach ($d in $chk) {
        if ($d -is [hashtable] -and $d.ContainsKey('Idx')) { $n++; $bytes += [double]$d.Len }
    }
    $ui.sl_Foot.Text = (Get-RcFootText $n $bytes $script:RcDest)
}

function Add-RcIntro {
    Add-HeadRow $ui.sl_List 'Silinen dosyaları geri getir'
    Add-Note $ui.sl_List 'Multimizer sürücüyü yalnızca okur; taranan sürücüye, diske ya da imaja hiçbir şey yazılmaz. Bulunan dosyalar her zaman taranandan FARKLI bir sürücüye ya da diske, yeni bir klasöre kaydedilir ve var olan hiçbir dosyanın üzerine yazılmaz.'
    $row = New-ItemRow @{ Title = 'Önce Geri Dönüşüm Kutusu’na bakın'; Detail = 'Dosyayı Delete tuşuyla sildiyseniz büyük olasılıkla oradadır; sağ tıklayıp “Geri yükle” demeniz yeter. Ek tarama gerekmez.'; BrCol = 'BrInfo'; Btn1 = 'Aç' } @{ Do = 'RcBin' } $false $false
    $row.FindName('Act').Add_Click($script:H_RcAct)
    [void]$ui.sl_List.Children.Add($row)
    Add-Note $ui.sl_List 'Taranabilenler: harf almış her sürücü (dahili disk, USB bellek, SD kart, harici disk), harf almamış bölümler, fiziksel diskin tamamı ve ham disk imajları (.img, .dd, .raw, .bin). NTFS, FAT12/16/32 ve exFAT’ta silinmiş dosya kayıtları okunur: dosya adı, klasörü ve tarihi korunur. ext2/3/4’te boş bloklar, ReFS, APFS, HFS+, Btrfs, XFS gibi diğer biçimlerde ve bozuk ya da bölümü silinmiş disklerde tüm alan dosya imzalarına göre taranır; bu durumda dosya adı ve tarihi bilinmez.'
    Add-Note $ui.sl_List 'Hızlı tarama silinmiş dosya kayıtlarını okur. Derin tarama boş alanı ayrıca dosya imzalarına göre tarar (resim, belge, arşiv, ses ve video); adı bilinmeyen dosyalar da bulunur ama uzun sürebilir. Kayıt tutmayan biçimlerde hızlı tarama da imza taraması yapar.'
    $ch = Get-RcSelectedChoice
    if ($null -ne $ch) {
        $isDrive = ([string]$ch.Kind -eq 'Drive')
        if ($ch.Locked -eq $true) {
            if ($isDrive) { Add-Note $ui.sl_List 'Bu sürücü BitLocker ile kilitli. Önce kilidini açın; kilitli bir sürücüde okunabilir dosya yoktur.' 'warn' }
            else { Add-Note $ui.sl_List 'Bu bölüm BitLocker ile kilitli. Önce kilidini açın; kilitli bir bölümde okunabilir dosya yoktur.' 'warn' }
        }
        if ($ch.IsOs -eq $true) {
            if ($isDrive) { Add-Note $ui.sl_List 'Windows sürücüsünü tarıyorsunuz. Bilgisayar çalışırken bu sürücüye sürekli yeni veri yazılır ve silinen dosyaların yerini kaplar; kurtarmak istediğiniz bir dosya varsa bilgisayarı mümkün olduğunca az kullanın.' 'warn' }
            else { Add-Note $ui.sl_List 'Windows’un kurulu olduğu diski tarıyorsunuz. Bilgisayar çalışırken bu diske sürekli yeni veri yazılır ve silinen dosyaların yerini kaplar; kurtarmak istediğiniz bir dosya varsa bilgisayarı mümkün olduğunca az kullanın.' 'warn' }
        }
        if ([string]$ch.Media -eq 'SSD' -and $ch.Removable -ne $true) { Add-Note $ui.sl_List 'Bu bir SSD. Windows silinen verileri TRIM ile hemen temizler; bu yüzden listede bulunan dosyaların içi boş çıkabilir. SSD’de kurtarma şansı mekanik diske göre çok daha düşüktür.' 'warn' }
        if ([string]$ch.Kind -eq 'Image') { Add-Note $ui.sl_List 'Disk imajı salt okunur açılır; ham imajlar (.img, .dd, .raw, .bin) desteklenir.' }
        if ([string]$ch.Kind -eq 'Disk') { Add-Note $ui.sl_List 'Fiziksel disk salt okunur açılır. Harf almamış bölümler, Windows’un tanımadığı biçimler (ext4 gibi) ve bölüm tablosu bozulmuş diskler de taranabilir. Bölümü silinmiş ya da biçimlendirilmiş bir diskte dosya arıyorsanız “tüm disk” satırını seçin.' }
        if ($ch.Whole -eq $true) { Add-Note $ui.sl_List 'Tüm disk seçildi: bölüm düzeni yok sayılır, diskin tamamı dosya imzalarına göre taranır. Büyük disklerde saatler sürebilir; dosya adları ve klasörler bilinmez, var olan dosyalar da listelenebilir.' 'warn' }
    }
    if ($script:IsAdmin -ne $true -and ($script:RcSourceKind -eq 'Drive' -or $script:RcSourceKind -eq 'Disk')) { Add-Note $ui.sl_List 'Multimizer yönetici olarak çalışmıyor; sürücüler ve diskler okunamaz. Yönetici olarak yeniden başlatın ya da bir disk imajı seçin.' 'warn' }
    Add-Note $ui.sl_List 'Silinen dosyanın bulunduğu alana yeni veri yazıldıysa dosya geri getirilemez. Bu yüzden kurtarmak istediğiniz dosya varsa o sürücüye yeni bir şey kaydetmeyin.'
}

function Add-RcResultRow {
    $r = $script:RcLastRun
    if ($null -eq $r) { return }
    $done = 0
    $failed = 0
    if ($null -ne $r.Done) { $done = [int]$r.Done }
    if ($null -ne $r.Failed) { $failed = [int]$r.Failed }
    $title = ''
    $det = ''
    $br = 'BrGood'
    if ($done -gt 0) {
        $title = 'Kurtarma tamamlandı: ' + [string]$done + ' dosya, ' + (Format-Size ([double]$r.Bytes))
        $det = 'Kaydedilen klasör: ' + [string]$r.Dir
        if ($failed -gt 0) { $det += "`r`n" + [string]$failed + ' dosya kurtarılamadı; nedenleri raporda yazıyor.'; $br = 'BrWarn' }
        if ($r.Canceled -eq $true) { $det += "`r`n" + 'İşlem yarıda kesildi.'; $br = 'BrWarn' }
    } else {
        $title = 'Hiçbir dosya kurtarılamadı'
        $det = [string]$r.Error
        if ($det -eq '') { $det = 'Dosyaların disk alanı artık okunamıyor ya da başka veriyle dolu olabilir. Ayrıntı raporda ve günlükte.' }
        $br = 'BrBad'
    }
    $b1 = ''
    $b2 = ''
    if ([string]$r.Dir -ne '' -and (Test-Path -LiteralPath ([string]$r.Dir))) { $b1 = 'Klasörü aç' }
    if ([string]$r.Report -ne '' -and (Test-Path -LiteralPath ([string]$r.Report))) { $b2 = 'Raporu aç' }
    $row = New-ItemRow @{ Title = $title; Detail = $det; BrCol = $br; Btn1 = $b1; Btn2 = $b2 } @{ Do = 'RcDir'; Dir = [string]$r.Dir; Report = [string]$r.Report } $false $false
    if ($b1 -ne '') { $row.FindName('Act').Add_Click($script:H_RcAct) }
    if ($b2 -ne '') {
        $a2 = $row.FindName('Act2')
        $a2.Tag = @{ Do = 'RcReport'; Dir = [string]$r.Dir; Report = [string]$r.Report }
        $a2.Add_Click($script:H_RcAct)
    }
    [void]$ui.sl_List.Children.Add($row)
}

function Render-RcBody {
    $ui.sl_List.Children.Clear()
    if ($null -ne $script:SlDisks -and $script:SlDisks.Failed -eq $true) { Add-Note $ui.sl_List 'Sürücü listesi okunamadı; yine de “Disk imajı seç...” ile bir imaj açabilirsiniz.' 'warn' }
    if ($script:RcScanError -ne '') { Add-Note $ui.sl_List $script:RcScanError 'bad' }
    Add-RcResultRow
    $meta = $script:RcMeta
    if ($null -eq $meta) {
        Add-RcIntro
        Update-RcFoot
        return
    }
    $q = [string]$ui.sl_RcFind.Text
    $disp = Get-RcDisplay $script:RcItems $script:RcGroup $q $script:RcRowCap
    foreach ($ln in (Get-RcSummaryLines $meta ([int]$disp.Total - [int]$disp.Hidden) ([int]$disp.Hidden))) { Add-Note $ui.sl_List ([string]$ln.T) ([string]$ln.K) }
    $rows = @($disp.Rows)
    if ($rows.Count -eq 0) {
        if ([int]$disp.Total - [int]$disp.Hidden -le 0) {
            Add-Note $ui.sl_List 'Silinmiş dosya bulunamadı. SSD’lerde TRIM verileri temizlemiş olabilir; “Derin tara” boş alanı dosya imzalarına göre de arar.' 'warn'
        } else {
            Add-Note $ui.sl_List 'Bu süzgece uyan dosya yok. Tür seçimini ya da arama kutusunu değiştirin.'
        }
        Update-RcFoot
        return
    }
    $head = 'Kurtarılabilecek dosyalar (' + [string]$rows.Count
    if ([int]$disp.Matched -gt $rows.Count) { $head += ' / ' + [string]$disp.Matched }
    Add-HeadRow $ui.sl_List ($head + ')')
    if ([int]$disp.Matched -gt $rows.Count) { Add-Note $ui.sl_List ('Liste, kurtarılma şansı en yüksek ' + [string]$rows.Count + ' dosyayı gösterir. Diğerlerini görmek için türü ya da arama kutusunu kullanın.') }
    foreach ($e in $rows) {
        $it = $script:RcItems[[int]$e.Idx]
        if ($null -eq $it) { continue }
        $m = New-RcRowModel $it
        $row = New-ItemRow $m @{ Idx = [int]$e.Idx; Len = [double]$it.Length } $true $false
        $c = $row.FindName('Chk')
        $c.Add_Checked($script:H_RcChk)
        $c.Add_Unchecked($script:H_RcChk)
        [void]$ui.sl_List.Children.Add($row)
    }
    Update-RcFoot
}

function Render-SlRecover {
    $ui.sl_List.Children.Clear()
    if ($null -eq $script:SlDisks) {
        foreach ($ck in @($script:RcPartCache.Keys)) { if ([string]$ck -like 'PhysicalDrive*') { $script:RcPartCache.Remove($ck) } }
        Update-RcVolumeCombo
        Update-RcTypeCombo
        Add-Note $ui.sl_List 'Sürücüler okunuyor...'
        Load-SlDisk
        return
    }
    Update-RcVolumeCombo
    Update-RcTypeCombo
    Render-RcBody
}

# ---------------- işlemler ----------------
function Start-RcScan([string]$Mode) {
    if ($script:RcSource -eq '') { Show-Toast 'Önce taranacak sürücüyü, diski ya da disk imajını seçin.' 'warn'; return }
    $ch = Get-RcSelectedChoice
    if ($null -ne $ch -and $ch.Locked -eq $true) {
        if ($script:RcSourceKind -eq 'Drive') { Show-Toast ($script:RcSource + ' sürücüsü BitLocker ile kilitli; önce kilidini açın.') 'warn' }
        else { Show-Toast 'Bu bölüm BitLocker ile kilitli; önce kilidini açın.' 'warn' }
        return
    }
    if (($script:RcSourceKind -eq 'Drive' -or $script:RcSourceKind -eq 'Disk') -and $script:IsAdmin -ne $true) { Show-Toast 'Sürücüyü ya da diski okumak için Multimizer’ın yönetici olarak çalışması gerekir.' 'warn'; return }
    if ($null -ne $ch -and $ch.Loaded -eq $false -and $script:RcSourceKind -eq 'Disk') {
        Show-Toast 'Diskin bölümleri okunuyor; bitince bir bölüm seçip yeniden tarayın.' 'info'
        Start-RcParts $script:RcSource
        return
    }
    $script:RcPendSource = $script:RcSource
    $script:RcPendPart = $script:RcPart
    $script:RcPendMode = $Mode
    $lbl = 'Silinen dosyalar taranıyor (salt okunur)'
    if ($Mode -eq 'Both') { $lbl = 'Derin tarama yapılıyor (salt okunur)' }
    [void](Start-Async 'RcScan' 'Job_RecoverScan' @{ Source = $script:RcSource; Mode = $Mode; Partition = $script:RcPart; MaxResults = $script:RcMaxResults } {
        param($r)
        Complete-RcScan $r
    } $lbl)
}

# Fiziksel diskin ya da imajın bölümlerini (yalnızca bölüm düzeni; hızlı) arka planda okur
function Start-RcParts([string]$Source) {
    if ($Source -eq '' -or $script:RcPartPend -ne '') { return }
    if ($Source -match '^PhysicalDrive\d+$' -and $script:IsAdmin -ne $true) {
        $m = 'Fiziksel diskin bölümlerini okumak için Multimizer’ın yönetici olarak çalışması gerekir.'
        $script:RcScanError = $m
        Show-Toast $m 'warn'
        Render-RcBody
        return
    }
    $script:RcPartPend = $Source
    $started = Start-Async 'RcParts' 'Job_RecoverParts' @{ Source = $Source } {
        param($r)
        Complete-RcParts $r
    } 'Bölümler okunuyor'
    if ($started -ne $true) { $script:RcPartPend = '' }
}

function Complete-RcParts($R) {
    $src = $script:RcPartPend
    $script:RcPartPend = ''
    if ($src -eq '') { return }
    if ($null -eq $R) { $R = @{ Ok = $false; Error = 'Bölümler okunamadı.'; Parts = @() } }
    $script:RcPartCache[$src] = @{ Ok = ($R.Ok -eq $true); Error = [string]$R.Error; Parts = @($R.Parts) }
    if ($R.Ok -ne $true) {
        $m = [string]$R.Error
        if ($m -eq '') { $m = 'Bölümler okunamadı.' }
        $script:RcScanError = $m
        Show-Toast $m 'bad'
    } else {
        $script:RcScanError = ''
        # seçili öğe bu diskin "bölümleri okumak için seçin" satırıysa ilk bölüme geçilir
        if ($script:RcSelKey -match '^PD:(\d+)$' -and ('PhysicalDrive' + $Matches[1]) -eq $src) { $script:RcSelKey = $script:RcSelKey + ':0' }
    }
    if ([string]$script:UiState.Page -eq 'solve' -and $script:SlTab -eq 'recover') {
        Update-RcVolumeCombo
        Update-RcTypeCombo
        Render-RcBody
    }
}

function Complete-RcScan($R) {
    $script:RcLastRun = $null
    if ($null -eq $R -or $R.Ok -ne $true) {
        $m = 'Tarama yapılamadı.'
        if ($null -ne $R -and [string]$R.Error -ne '') { $m = [string]$R.Error }
        $script:RcScanError = $m
        $script:RcItems = @()
        $script:RcMeta = $null
        Show-Toast $m 'bad'
    } else {
        $script:RcScanError = ''
        $script:RcItems = @($R.Items)
        $parts = 1
        if ($null -ne $R.Partitions) { $parts = [int]$R.Partitions }
        $script:RcMeta = @{ Source = $script:RcPendSource; Part = $script:RcPendPart; Fs = [string]$R.Fs; ClusterSize = [int]$R.ClusterSize; VolumeBytes = [double]$R.VolumeBytes; FreeBytes = [double]$R.FreeBytes
            Mode = [string]$R.Mode; Truncated = ($R.Truncated -eq $true); Canceled = ($R.Canceled -eq $true); Stats = $R.Stats; Partitions = $parts
            Method = [string]$R.Method; Raw = ($R.Raw -eq $true); Note = [string]$R.Note }
        $n = 0
        foreach ($it in $script:RcItems) { if ([int]$it.Chance -gt 0) { $n++ } }
        if ($n -gt 0) { Show-Toast ([string]$n + ' silinmiş dosya bulundu.') 'good' } else { Show-Toast 'Kurtarılabilir silinmiş dosya bulunamadı.' 'info' }
        if ($script:RcImage -ne '' -and $script:RcPendSource -eq $script:RcImage -and $parts -gt 1 -and $script:RcImageParts -ne $parts) {
            $script:RcImageParts = $parts
            Update-RcVolumeCombo
        }
    }
    if ([string]$script:UiState.Page -eq 'solve' -and $script:SlTab -eq 'recover') {
        Update-RcTypeCombo
        Render-RcBody
    }
}

function Start-RcRecover {
    if ($null -eq $script:RcMeta) { Show-Toast 'Önce bir tarama yapın.' 'warn'; return }
    $chk = Get-CheckedData $ui.sl_List
    $items = New-Object System.Collections.ArrayList
    foreach ($d in $chk) {
        if ($d -is [hashtable] -and $d.ContainsKey('Idx')) {
            $it = $script:RcItems[[int]$d.Idx]
            if ($null -ne $it) { [void]$items.Add($it) }
        }
    }
    if ($items.Count -eq 0) { Show-Toast 'Kurtarılacak dosyaları işaretleyin.' 'warn'; return }
    if ($script:RcDest -eq '') {
        $dd = Select-RcDest
        if ($dd -eq '') { return }
    }
    $why = Test-RcDestUi $script:RcSource $script:RcSourceKind $script:RcDest (Get-RcSelectedLetters)
    if ($why -ne '') { Show-Toast $why 'warn'; return }
    $script:RcPendItems = $items.ToArray()
    $script:RcPendSource = $script:RcSource
    $script:RcPendPart = $script:RcPart
    $script:RcPendDest = $script:RcDest
    Show-Confirm 'Dosyaları kurtar' (Get-RcConfirmText $script:RcPendItems $script:RcPendDest) 'Kurtar' { Start-RcRecoverJob }
}

function Start-RcRecoverJob {
    [void](Start-Async 'RcFiles' 'Job_RecoverFiles' @{ Source = $script:RcPendSource; Partition = $script:RcPendPart; Dest = $script:RcPendDest; Items = $script:RcPendItems; KeepPaths = $true } {
        param($r)
        Complete-RcRecover $r
    } 'Dosyalar kurtarılıyor')
}

function Complete-RcRecover($R) {
    if ($null -eq $R) { $R = @{ Ok = $false; Done = 0; Failed = 0; Bytes = 0; Dir = ''; Report = ''; Error = 'Kurtarma tamamlanamadı.'; Canceled = $false } }
    $script:RcLastRun = $R
    if ($R.Ok -eq $true) { Show-Toast ([string]$R.Done + ' dosya kurtarıldı.') 'good' }
    elseif ($R.Canceled -eq $true) { Show-Toast 'Kurtarma iptal edildi.' 'warn' }
    else {
        $m = 'Hiçbir dosya kurtarılamadı.'
        if ([string]$R.Error -ne '') { $m = [string]$R.Error }
        Show-Toast $m 'bad'
    }
    if ([string]$script:UiState.Page -eq 'solve' -and $script:SlTab -eq 'recover') { Render-RcBody }
}

function Init-SlRecover {
    $t = New-Object System.Windows.Threading.DispatcherTimer
    $t.Interval = [TimeSpan]::FromMilliseconds(320)
    $t.Add_Tick({
        $script:RcFindTimer.Stop()
        try { if ([string]$script:UiState.Page -eq 'solve' -and $script:SlTab -eq 'recover') { Render-RcBody } } catch { Write-CrashLog ('Silinen dosyalar süzgeci: ' + $_.Exception.Message) }
    })
    $script:RcFindTimer = $t
    $ui.sl_RcFind.Add_TextChanged({ if ($null -ne $script:RcFindTimer) { $script:RcFindTimer.Stop(); $script:RcFindTimer.Start() } })
    $ui.sl_RcVol.Add_SelectionChanged({ Invoke-Safe { Select-RcVolume } 'Sürücü seçimi' })
    $ui.sl_RcType.Add_SelectionChanged({ Invoke-Safe { Select-RcGroup } 'Tür süzgeci' })
    $ui.sl_RcImg.Add_Click({ Invoke-Safe { Select-RcImage } 'Disk imajı' })
    $ui.sl_RcQuick.Add_Click({ Invoke-Safe { Start-RcScan 'Quick' } 'Hızlı tarama' })
    $ui.sl_RcDeep.Add_Click({ Invoke-Safe { Start-RcScan 'Both' } 'Derin tarama' })
    $ui.sl_RcDest.Add_Click({ Invoke-Safe { [void](Select-RcDest) } 'Kurtarma klasörü' })
    $ui.sl_RcRun.Add_Click({ Invoke-Safe { Start-RcRecover } 'Kurtar' })
    $ui.sl_RcAll.Add_Click({ Invoke-Safe { Set-RowChecks $ui.sl_List { param($d) $true }; Update-RcFoot } 'Hepsini seç' })
    $ui.sl_RcNone.Add_Click({ Invoke-Safe { Set-RowChecks $ui.sl_List { param($d) $false }; Update-RcFoot } 'Seçimi temizle' })
}
