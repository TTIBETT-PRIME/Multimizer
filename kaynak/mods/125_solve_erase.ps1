# ==================================================================
#  ÇÖZÜM MERKEZİ: "Kalıcı silme" sekmesi
#  Dört düzeyde silme: dosya ve klasör (Job_SecureDelete, Araçlar sayfasıyla ortak), sürücülerin boş alanı (Job_WipeFree), disklerin
#  ayrılmamış alanı, tek bölüm ve tüm disk (Job_WipeRaw). İşler "GüvenliSilme" ve "DiskSilme" eklentilerindedir; burada yalnızca
#  seçenekler, onay metinleri ve sonuç gösterimi var. Geri döndürülemez işlemlerde (bölüm ve disk) hedefin adı elle yazdırılır.
#  Silinen dosya kurtarma sekmesiyle aynı kaynakları kullanır: sürücü, harfsiz bölüm, tüm disk ve USB bellek.
# ==================================================================
$script:ErPendDrive = ''
$script:ErLast = $null
$script:ErPend = $null
$script:ErOpts = @{ Method = 'random'; Verify = 'sample'; After = 'none' }
$script:ErLoading = $false
$script:ErTypedExpect = ''
$script:ErTypedAct = $null

# ---------------- saf yardımcılar (testlenir) ----------------
# Seçili yazma yöntemi, doğrulama ve sonraki adım (geçersiz değerler varsayılana döner)
function Get-ErOptions {
    return @{ Method = (Get-WipeMethodKey ([string]$script:ErOpts.Method)); Verify = (Get-WipeVerifyKey ([string]$script:ErOpts.Verify)); After = (Get-WipeAfterKey ([string]$script:ErOpts.After)) }
}

# Boş alan temizleme için sürücü satırları. Kilitli, dosya sistemi olmayan ya da boş yeri çok az olan sürücüler listelenmez.
# Dönüş: @{ Drive; Title; Detail; BrCol; Free; Size; Media; Bus; IsOs; Trim } dizisi
function Get-ErDriveModels($Disks, [string]$OsDrive) {
    $out = New-Object System.Collections.ArrayList
    foreach ($d in @($Disks)) {
        if ($null -eq $d) { continue }
        if ([string]$d.State -eq 'locked') { continue }
        if (([string]$d.Fs).Trim() -eq '') { continue }
        $free = [double]$d.Free
        if ($free -lt 67108864) { continue }
        $isOs = ([string]$d.Drive -eq $OsDrive)
        $media = [string]$d.Media
        $usb = ([string]$d.Bus -eq 'USB' -or [string]$d.Type -eq 'Removable')
        $det = 'Boş alan: ' + (Format-Size $free) + '. Silinmiş dosyaların kalıntıları üzerine yazılır; var olan dosyalara dokunulmaz.'
        $br = 'BrInfo'
        $trim = $false
        if ($media -eq 'SSD' -and -not $usb) {
            $det += ' SSD’de tam güvence vermez (denetleyici veriyi başka hücrelere taşır); asıl çözüm disk şifrelemesidir.'
            $br = 'BrWarn'
            $trim = $true
        } elseif ($usb) {
            $det += ' Çıkarılabilir bellekte işlem yavaş olabilir.'
        }
        if ($isOs) { $det += ' Windows sürücüsünde işlem boyunca bilgisayarı kullanmamanız önerilir.' }
        [void]$out.Add(@{ Drive = [string]$d.Drive; Title = (Get-RcVolumeName $d $OsDrive); Detail = $det; BrCol = $br; Free = $free; Size = [double]$d.Size; Media = $media; Bus = [string]$d.Bus; IsOs = $isOs; Trim = $trim })
    }
    return , $out.ToArray()
}

# Bir geçişte yazılacak boş alan (bayt): boş alan eksi bırakılan pay
function Get-ErFreeWork($T) {
    $w = [double]$T.Free - (Get-WipeReserve ([double]$T.Size) ($T.IsOs -eq $true))
    if ($w -lt 0) { $w = [double]0 }
    return $w
}

# Boş alan temizleme onay metni. Opts: @{ Method; Verify } (verilmezse varsayılanlar)
function Get-ErFreeConfirmText($T, $Opts = $null) {
    $method = 'random'
    $verify = 'sample'
    if ($null -ne $Opts) { $method = Get-WipeMethodKey ([string]$Opts.Method); $verify = Get-WipeVerifyKey ([string]$Opts.Verify) }
    $modes = Get-WipeModes $method
    $est = Get-WipeEstimate (Get-ErFreeWork $T) $modes.Count 'none' ([string]$T.Bus) ([string]$T.Media)
    $msg = [string]$T.Drive + ' sürücüsünün boş alanı (' + (Format-Size ([double]$T.Free)) + ') üzerine yazılarak temizlenecek.' + "`r`n`r`n"
    $msg += '•  Var olan dosyalarınıza dokunulmaz; yalnızca daha önce silinmiş dosyaların diskte kalan izleri yok edilir.' + "`r`n"
    $msg += '•  Yöntem: ' + (Get-WipeMethodName $method) + '. Tahmini süre: ' + $est.Text + '. İstediğiniz an iptal edebilirsiniz.' + "`r`n"
    $pay = '%1'
    if ($T.IsOs -eq $true) { $pay = '%3' }
    $msg += '•  İşlem sırasında sürücüde yaklaşık ' + $pay + ' pay boş bırakılır; geçici dosyalar iş bitince (iptal etseniz de) silinir.' + "`r`n"
    if ($verify -ne 'none') {
        $msg += '•  Doğrulama: işe başlarken bilinen içerikli küçük test dosyaları yazılıp silinir; temizlikten sonra aynı konumlar doğrudan sürücüden okunarak eski verinin kalıp kalmadığına bakılır.' + "`r`n"
    }
    $msg += '•  Bu sırada o sürücüye başka şey kaydetmeyin; sürücü geçici olarak neredeyse dolu görünür.'
    if ([string]$T.Media -eq 'SSD') { $msg += "`r`n`r`n" + 'Not: Bu bir SSD. SSD’lerde boş alan temizleme tam güvence vermez ve diski gereksiz yıprattığı için yalnızca gerçekten gerekiyorsa yapın. Bitince silinen alanlar sürücüye de bildirilir (TRIM).' }
    if ($T.IsOs -eq $true) { $msg += "`r`n`r`n" + 'Windows sürücüsü: işlem bitene kadar program kurmayın, güncelleme yapmayın ve büyük dosya indirmeyin.' }
    return $msg
}

# Bölümlerin dışında kalan boşluk tahmini (Windows’un bildirdiği bölümlere göre). Motor gerçek düzeni diskten okur;
# bu sayı yalnızca satırda gösterilir. Başta ve sonda 1 MiB korunur, 8 MiB’tan küçük boşluklar sayılmaz.
# Dönüş: @{ Bytes; Count }
function Get-ErGapEstimate($Dk) {
    $r = @{ Bytes = [double]0; Count = 0 }
    $len = [double]$Dk.Size
    $guard = [double]1048576
    $minGap = [double]8388608
    if ($len -le ($guard * 2 + $minGap)) { return $r }
    $iv = New-Object System.Collections.ArrayList
    foreach ($pt in @($Dk.Parts)) {
        if ($null -eq $pt) { continue }
        $l = [double]$pt.Size
        if ($l -le 0) { continue }
        [void]$iv.Add(@{ S = [double]$pt.Offset; E = ([double]$pt.Offset + $l) })
    }
    $sorted = $iv.ToArray() | Sort-Object { $_.S }
    $cursor = $guard
    $limit = $len - $guard
    foreach ($x in @($sorted)) {
        if ($null -eq $x) { continue }
        if ($x.S -gt $cursor) {
            $end = [math]::Min($x.S, $limit)
            if (($end - $cursor) -ge $minGap) { $r.Bytes += ($end - $cursor); $r.Count++ }
        }
        if ($x.E -gt $cursor) { $cursor = $x.E }
    }
    if (($limit - $cursor) -ge $minGap) { $r.Bytes += ($limit - $cursor); $r.Count++ }
    return $r
}

# Bölümün Türkçe tür adı (Windows’un bildirdiği tür)
function Get-ErPartTypeName([string]$Type) {
    switch (([string]$Type).Trim()) {
        'System'   { return 'EFI sistem bölümü' }
        'Reserved' { return 'Microsoft ayrılmış bölüm' }
        'Recovery' { return 'Windows kurtarma bölümü' }
        'Basic'    { return 'veri bölümü' }
        'IFS'      { return 'veri bölümü' }
        'Logical'  { return 'mantıksal bölüm' }
        'Extended' { return 'genişletilmiş bölüm' }
        'XBOX'     { return 'oyun bölümü' }
    }
    return ''
}

# Disk silme bölümü için disk ve bölüm satırları.
# Dönüş: @{ Number; Title; Detail; BrCol; Blocked ('' ya da neden); Gap (bayt); GapCount; Btn1; Btn2; Parts = @(@{ Number; Title; Detail; BrCol; Blocked; Btn1 }) } dizisi
function Get-ErDiskModels($Phys) {
    $out = New-Object System.Collections.ArrayList
    foreach ($dk in @($Phys)) {
        if ($null -eq $dk) { continue }
        if ([double]$dk.Size -le 0) { continue }
        $why = Test-WipeDiskAllowed $dk 'Disk'
        $gap = Get-ErGapEstimate $dk
        $parts = New-Object System.Collections.ArrayList
        $det = New-Object System.Collections.ArrayList
        $style = ([string]$dk.Style).Trim()
        if ($style -eq '' -or $style -eq 'RAW') { $style = 'bölüm tablosu yok' }
        [void]$det.Add($style)
        $pcount = @($dk.Parts).Count
        if ($pcount -eq 0) { [void]$det.Add('bölüm yok') } else { [void]$det.Add([string]$pcount + ' bölüm') }
        if (@($dk.Letters).Count -gt 0) { [void]$det.Add('sürücüler: ' + (@($dk.Letters) -join ', ')) }
        if ($gap.Bytes -gt 0) { [void]$det.Add('ayrılmamış alan: yaklaşık ' + (Format-Size $gap.Bytes)) }
        $m = @{ Number = [int]$dk.Number; Title = (Get-RcDiskName $dk); Detail = ($det.ToArray() -join '  ·  '); BrCol = 'BrInfo'; Blocked = $why; Gap = [double]$gap.Bytes; GapCount = [int]$gap.Count
            Btn1 = ''; Btn2 = ''; Parts = @() }
        if ($why -ne '') {
            $m.Detail = $why
            $m.BrCol = 'BrWarn'
        } else {
            if ($gap.Bytes -gt 0) { $m.Btn1 = 'Ayrılmamış alanı sil' }
            $m.Btn2 = 'Diski tamamen sil'
            $sorted = @(@($dk.Parts) | Sort-Object { [double]$_.Offset })
            foreach ($pt in $sorted) {
                if ($null -eq $pt) { continue }
                $pwhy = Test-WipePartAllowed $dk $pt
                $t = 'Bölüm ' + [string]$pt.Number
                $lbl = ([string]$pt.Label).Trim()
                if ([string]$pt.Letter -ne '') {
                    $t += '  ·  ' + [string]$pt.Letter
                    if ($lbl -ne '') { $t += '  ' + $lbl }
                } else { $t += '  ·  sürücü harfi yok' }
                $fs = ([string]$pt.Fs).Trim()
                if ($fs -ne '') { $t += '  ·  ' + $fs }
                $t += '  ·  ' + (Format-Size ([double]$pt.Size))
                $tn = Get-ErPartTypeName ([string]$pt.Type)
                $pd = ''
                if ($tn -ne '') { $pd = $tn.Substring(0, 1).ToUpperInvariant() + $tn.Substring(1) + '.' }
                $pm = @{ Number = [int]$pt.Number; Title = $t; Detail = $pd; BrCol = 'BrInfo'; Blocked = $pwhy; Btn1 = 'Bölümü sil' }
                if ($pwhy -ne '') { $pm.Detail = $pwhy; $pm.BrCol = 'BrWarn'; $pm.Btn1 = '' }
                [void]$parts.Add($pm)
            }
            $m.Parts = $parts.ToArray()
        }
        [void]$out.Add($m)
    }
    return , $out.ToArray()
}

# Bölüm ve disk silme için işlem planı (hiçbir şey değiştirmez). Scope: Unallocated | Partition | Disk
# Dönüş: @{ Ok; Why; Params; Title; Text; OkText; Expect (yazdırılacak metin; Unallocated için boş); Bytes; Label }
function New-ErRawPlan([string]$Scope, $Dk, [int]$PartNo, $Opts) {
    $pl = @{ Ok = $false; Why = ''; Params = $null; Title = ''; Text = ''; OkText = ''; Expect = ''; Bytes = [double]0; Label = '' }
    if (@('Unallocated', 'Partition', 'Disk') -notcontains $Scope) { $pl.Why = 'Bilinmeyen silme kapsamı.'; return $pl }
    if ($null -eq $Dk) { $pl.Why = 'Disk bulunamadı; listeyi yenileyip yeniden deneyin.'; return $pl }
    $why = Test-WipeDiskAllowed $Dk $Scope
    if ($why -ne '') { $pl.Why = $why; return $pl }
    $part = $null
    if ($Scope -eq 'Partition') {
        foreach ($x in @($Dk.Parts)) { if ($null -ne $x -and [int]$x.Number -eq $PartNo) { $part = $x } }
        $why = Test-WipePartAllowed $Dk $part
        if ($why -ne '') { $pl.Why = $why; return $pl }
    }
    $method = Get-WipeMethodKey ([string]$Opts.Method)
    $verify = Get-WipeVerifyKey ([string]$Opts.Verify)
    $after = Get-WipeAfterKey ([string]$Opts.After)
    if ($Scope -eq 'Unallocated') { $after = 'none' }
    $bytes = [double]$Dk.Size
    if ($Scope -eq 'Partition') { $bytes = [double]$part.Size }
    if ($Scope -eq 'Unallocated') {
        $bytes = [double](Get-ErGapEstimate $Dk).Bytes
        if ($bytes -le 0) { $pl.Why = 'Bu diskte silinecek ayrılmamış alan yok.'; return $pl }
    }
    if ($after -eq 'fat32' -and $Scope -ne 'Unallocated' -and $bytes -gt [double]34359738368) {
        $pl.Why = 'FAT32 yalnızca 32 GB boyuta kadar biçimlenebilir; “Sonra” seçeneğinde NTFS ya da exFAT seçin.'
        return $pl
    }
    $exp = Get-WipeExpect $Dk
    if ($null -ne $part) { $exp.PartOffset = [double]$part.Offset; $exp.PartSize = [double]$part.Size }
    $pn = 0
    if ($null -ne $part) { $pn = [int]$part.Number }
    $pl.Params = @{ Scope = $Scope; Disk = [int]$Dk.Number; Part = $pn; Expect = $exp; Method = $method; Verify = $verify; After = $after }
    $pl.Bytes = $bytes
    $modes = Get-WipeModes $method
    $est = Get-WipeEstimate $bytes $modes.Count $verify ([string]$Dk.Bus) ([string]$Dk.Media)
    $nm = 'Disk ' + [string]$Dk.Number
    $dn = ([string]$Dk.Name).Trim()
    if ($dn -ne '') { $nm += '  ' + $dn }
    $letters = (@($Dk.Letters) -join ', ')
    $lines = New-Object System.Collections.ArrayList
    if ($Scope -eq 'Disk') {
        $head = $nm + ' (' + (Format-Size ([double]$Dk.Size)) + ') tamamen silinecek.'
        $l1 = '•  Diskteki tüm bölümler kaldırılır ve disk baştan sona üzerine yazılır'
        if ($letters -ne '') { $l1 += ' (' + $letters + ')' }
        [void]$lines.Add($l1 + '. Geri getirilemez; kurtarma programları da bulamaz.')
        $pl.Expect = 'Disk ' + [string]$Dk.Number
        $pl.Title = 'Diski tamamen sil'
        $pl.OkText = 'Diski sil'
        $pl.Label = 'Disk ' + [string]$Dk.Number + ' siliniyor'
    } elseif ($Scope -eq 'Partition') {
        $pt = 'bölüm ' + [string]$part.Number
        if ([string]$part.Letter -ne '') { $pt += ' (' + [string]$part.Letter + ')' }
        $head = 'Disk ' + [string]$Dk.Number + ' üzerindeki ' + $pt + ' (' + (Format-Size ([double]$part.Size)) + ') silinecek.'
        [void]$lines.Add('•  Bölümdeki tüm dosyalar kaldırılır ve alan üzerine yazılır. Geri getirilemez. Diskin diğer bölümlerine dokunulmaz.')
        $pl.Expect = 'Disk ' + [string]$Dk.Number + ' Bölüm ' + [string]$part.Number
        $pl.Title = 'Bölümü sil'
        $pl.OkText = 'Bölümü sil'
        $pl.Label = 'Disk ' + [string]$Dk.Number + ' bölüm ' + [string]$part.Number + ' siliniyor'
    } else {
        $head = $nm + ': bölümlerin dışında kalan boş alan (yaklaşık ' + (Format-Size $bytes) + ') üzerine yazılacak.'
        [void]$lines.Add('•  Mevcut bölümlere ve dosyalara dokunulmaz; yalnızca daha önce silinmiş bölümlerden artakalan alan yazılır. Diskin başındaki ve sonundaki 1 MB korunur.')
        $pl.Title = 'Ayrılmamış alanı sil'
        $pl.OkText = 'Sil'
        $pl.Label = 'Disk ' + [string]$Dk.Number + ' ayrılmamış alan siliniyor'
        if (@($Dk.Parts).Count -eq 0) {
            # bölüm yoksa tüm disk ayrılmamış sayılır; bölümler yanlışlıkla kaybolmuş olabilir, bu yüzden adı yazdırılır
            $pl.Expect = 'Disk ' + [string]$Dk.Number
            $pl.Title = 'Diski ayrılmamış alan olarak sil'
            [void]$lines.Add('•  Diskte hiç bölüm görünmüyor, bu yüzden tüm disk ayrılmamış sayılır. Bölümleri yanlışlıkla kaybettiyseniz önce Silinen dosyalar sekmesinde bu diski taratın; bu işlem içeriği geri getirilemez biçimde siler.')
        }
    }
    [void]$lines.Add('•  Yöntem: ' + (Get-WipeMethodName $method) + '; doğrulama: ' + (Get-WipeVerifyName $verify) + '.')
    if ($Scope -ne 'Unallocated') { [void]$lines.Add('•  Sonunda: ' + (Get-WipeAfterName $after) + '.') }
    [void]$lines.Add('•  Tahmini süre: ' + $est.Text + '. İstediğiniz an iptal edebilirsiniz.')
    if ($Scope -ne 'Unallocated') { [void]$lines.Add('•  İşlem sırasında diski ya da USB belleği çıkarmayın. İptal ederseniz alan yarım silinmiş kalır.') }
    $txt = $head + "`r`n`r`n" + ($lines.ToArray() -join "`r`n")
    if ([string]$Dk.Media -eq 'SSD' -or [string]$Dk.Bus -eq 'USB') {
        $txt += "`r`n`r`n" + 'Not: SSD ve USB belleklerde denetleyici veriyi başka hücrelere taşıyabilir; üzerine yazma bu yüzden tam güvence vermez (NIST SP 800-88 “Clear” düzeyi). Cihaz elden çıkarılacaksa üreticinin güvenli silme aracını ya da şifreleme kullanın.'
    }
    $pl.Text = $txt
    $pl.Ok = $true
    return $pl
}

# İşlem sonucu satırı: @{ Title; Detail; BrCol; Toast }. Kind: Free (varsayılan) | Raw | Trim
function Get-ErResultModel($R) {
    $kind = [string](Get-JsonProp $R 'Kind')
    if ($kind -eq 'Raw') { return (Get-ErRawResultModel $R) }
    if ($kind -eq 'Trim') { return (Get-ErTrimResultModel $R) }
    return (Get-ErFreeResultModel $R)
}

function Get-ErFreeResultModel($R) {
    $drv = [string](Get-JsonProp $R 'Drive')
    $written = [double](Get-JsonProp $R 'Written')
    if ($R.Ok -eq $true) {
        $det = (Format-Size $written) + ' üzerine yazıldı'
        $mk = [string](Get-JsonProp $R 'Method')
        if ($mk -ne '') { $det += ' (' + (Get-WipeMethodName $mk) + ')' }
        $det += '. Sürücüdeki silinmiş dosya kalıntıları artık kurtarma programlarıyla bulunamaz.'
        $br = 'BrGood'
        $vd = Get-JsonProp $R 'Verdict'
        if ($null -ne $vd) {
            $det += ' ' + [string]$vd.Text
            if ([string]$vd.Level -eq 'warn') { $br = 'BrWarn' }
        }
        $tr = Get-JsonProp $R 'Trim'
        if ($null -ne $tr) {
            if ($tr.Ok -eq $true) { $det += ' Silinen alanlar sürücüye bildirildi (TRIM).' } else { $det += ' TRIM gönderilemedi: ' + [string]$tr.Error }
        }
        $ttl = $drv + ' boş alanı temizlendi'
        return @{ Title = $ttl; Detail = $det; BrCol = $br; Toast = ($ttl + ' (' + (Format-Size $written) + ').') }
    }
    if ($R.Canceled -eq $true) {
        $ttl = $drv + ' boş alan temizleme iptal edildi'
        $det = (Format-Size $written) + ' üzerine yazılmıştı; geçici dosyalar silindi.'
        return @{ Title = $ttl; Detail = $det; BrCol = 'BrWarn'; Toast = ($ttl + '. ' + $det) }
    }
    $m = [string](Get-JsonProp $R 'Error')
    if ($m -eq '') { $m = 'İşlem tamamlanamadı; ayrıntı günlükte.' }
    $ttl = $drv + ' boş alan temizlenemedi'
    return @{ Title = $ttl; Detail = $m; BrCol = 'BrBad'; Toast = ($ttl + '. ' + $m) }
}

function Get-ErTrimResultModel($R) {
    $drv = [string](Get-JsonProp $R 'Drive')
    if ($R.Ok -eq $true) {
        $det = 'Silinen alanlar sürücüye bildirildi; SSD bunları arka planda boşaltır.'
        $nt = [string](Get-JsonProp $R 'Note')
        if ($nt -ne '') { $det += ' ' + $nt }
        $ttl = $drv + ' için TRIM gönderildi'
        return @{ Title = $ttl; Detail = $det; BrCol = 'BrGood'; Toast = ($ttl + '.') }
    }
    $m = [string](Get-JsonProp $R 'Error')
    if ($m -eq '') { $m = 'İşlem tamamlanamadı; ayrıntı günlükte.' }
    $ttl = $drv + ' için TRIM gönderilemedi'
    return @{ Title = $ttl; Detail = $m; BrCol = 'BrBad'; Toast = ($ttl + '. ' + $m) }
}

function Get-ErRawResultModel($R) {
    $scope = [string](Get-JsonProp $R 'Scope')
    $no = [int](Get-JsonProp $R 'Disk')
    $what = 'Disk ' + [string]$no
    if ($no -lt 0) { $what = 'Disk imajı' }
    $nm = ([string](Get-JsonProp $R 'Name')).Trim()
    if ($scope -eq 'Partition') { $what += ' bölüm ' + [string](Get-JsonProp $R 'Part') }
    elseif ($scope -eq 'Unallocated') { $what += ' ayrılmamış alanı' }
    elseif ($nm -ne '') { $what += '  ' + $nm }
    $written = [double](Get-JsonProp $R 'Written')
    $notes = @(@(Get-JsonProp $R 'Notes') | Where-Object { $null -ne $_ -and [string]$_ -ne '' })
    if ($R.Nothing -eq $true) {
        $det = 'Silinecek ayrılmamış alan bulunamadı.'
        if ($notes.Count -gt 0) { $det = [string]$notes[0] }
        return @{ Title = ($what + ': yapılacak bir şey yok'); Detail = $det; BrCol = 'BrInfo'; Toast = ($what + ': ' + $det) }
    }
    if ($R.Ok -eq $true) {
        $mk = [string](Get-JsonProp $R 'Method')
        $det = (Format-Size $written) + ' yazıldı'
        if ($mk -ne '') { $det += ' (' + (Get-WipeMethodName $mk) + ')' }
        $det += '.'
        $vk = [string](Get-JsonProp $R 'VerifyKind')
        if ($vk -ne '') { $det += ' Doğrulama: ' + (Format-Size ([double](Get-JsonProp $R 'Verified'))) + ' aygıttan geri okundu, fark yok.' }
        else { $det += ' Doğrulama yapılmadı.' }
        $ad = [string](Get-JsonProp $R 'AfterDone')
        if ($ad -ne '') {
            $det += ' ' + $ad.Substring(0, 1).ToUpperInvariant() + $ad.Substring(1) + '.'
            $lt = [string](Get-JsonProp $R 'Letter')
            if ($lt -ne '') { $det += ' Yeni sürücü: ' + $lt }
        }
        $sec = [double](Get-JsonProp $R 'Seconds')
        if ($sec -gt 0) { $det += ' Süre: ' + (Format-Duration $sec) + '.' }
        $br = 'BrGood'
        foreach ($n in $notes) { $det += ' ' + [string]$n; $br = 'BrWarn' }
        $ttl = $what + ' silindi'
        return @{ Title = $ttl; Detail = $det; BrCol = $br; Toast = ($ttl + ' (' + (Format-Size $written) + ').') }
    }
    if ($R.Canceled -eq $true) {
        $ttl = $what + ' silme iptal edildi'
        $det = (Format-Size $written) + ' yazılmıştı.'
        if ($R.Started -eq $true) { $det += ' Bölümler zaten kaldırıldı; alan yarım silinmiş durumda. Gerekirse işlemi yeniden başlatın.' }
        return @{ Title = $ttl; Detail = $det; BrCol = 'BrWarn'; Toast = ($ttl + '. ' + $det) }
    }
    $m = [string](Get-JsonProp $R 'Error')
    if ($m -eq '') { $m = 'İşlem tamamlanamadı; ayrıntı günlükte.' }
    $det = $m
    if ($R.Started -eq $true) { $det += ' Bölümler kaldırılmıştı; alan tamamen silinmemiş olabilir, işlemi yeniden başlatın.' }
    $ttl = $what + ' silinemedi'
    return @{ Title = $ttl; Detail = $det; BrCol = 'BrBad'; Toast = ($ttl + '. ' + $det) }
}

# Dosya ve klasör silme sonucu (Araçlar sayfası ve bu sekme ortak kullanır): @{ Text; Kind (good | warn | info); Warnings }
function Get-ErSecureResultModel($R) {
    $files = [int](Get-JsonProp $R 'Files')
    $failed = [int](Get-JsonProp $R 'Failed')
    $skipped = [int](Get-JsonProp $R 'Skipped')
    $bytes = [double](Get-JsonProp $R 'Bytes')
    $passes = [int](Get-JsonProp $R 'Passes')
    $warn = @(@(Get-JsonProp $R 'Warnings') | Where-Object { $null -ne $_ -and [string]$_ -ne '' })
    if ($files -eq 0 -and $failed -eq 0 -and $skipped -eq 0) { return @{ Text = 'Silinecek dosya bulunamadı.'; Kind = 'info'; Warnings = $warn } }
    $t = [string]$files + ' dosya kalıcı silindi (' + (Format-Size $bytes) + ')'
    if ($passes -gt 1) { $t += ', ' + [string]$passes + ' geçiş' }
    $t += '.'
    $kind = 'good'
    if ($skipped -gt 0) { $t += ' ' + [string]$skipped + ' öğe atlandı (bulutta duran dosya).'; $kind = 'warn' }
    if ($failed -gt 0) { $t += ' ' + [string]$failed + ' öğe silinemedi; günlüğe bakın.'; $kind = 'warn' }
    return @{ Text = $t; Kind = $kind; Warnings = $warn }
}

function Show-SecureDeleteResult($R) {
    $m = Get-ErSecureResultModel $R
    Show-Toast ([string]$m.Text) ([string]$m.Kind)
    if (@($m.Warnings).Count -gt 0) {
        $lines = New-Object System.Collections.ArrayList
        foreach ($w in @($m.Warnings)) { [void]$lines.Add('•  ' + [string]$w) }
        Show-Message 'Üzerine yazma garantisi sınırlı' (($lines.ToArray() -join "`r`n") + "`r`n`r`n" + 'Bu dosyaların eski kopyaları diskte kalmış olabilir. Sürücünün boş alanını temizleyin (Çözüm Merkezi > Kalıcı silme > Boş alanı temizle) ya da diski şifreleyin.')
    }
}

# Sonuçtan sonra “Kurtarma motoruyla dene” için kaynak anahtarı ('' = gösterme)
function Get-ErRecoverKey($R) {
    if ($null -eq $R) { return '' }
    $kind = [string](Get-JsonProp $R 'Kind')
    if ($kind -eq 'Trim') { return '' }
    if ([double](Get-JsonProp $R 'Written') -le 0) { return '' }
    if ($kind -eq 'Raw') {
        $n = [int](Get-JsonProp $R 'Disk')
        if ($n -lt 0) { return '' }
        return ('PD:' + [string]$n + ':all')
    }
    $d = ([string](Get-JsonProp $R 'Drive')).Trim()
    if ($d -cmatch '^[A-Za-z]:') { return ($d.Substring(0, 1).ToUpperInvariant() + ':') }
    return ''
}

# ---------------- çizim ----------------
$script:H_ErAct = { param($s, $e) Invoke-Safe { Invoke-ErAction $s.Tag } 'Eylem' }

function Invoke-ErAction($T) {
    switch ([string]$T.Do) {
        'ErFree'    { Start-ErFree $T }
        'ErTrim'    { Start-ErTrim $T }
        'ErGap'     { Start-ErRaw 'Unallocated' ([int]$T.Disk) 0 }
        'ErPart'    { Start-ErRaw 'Partition' ([int]$T.Disk) ([int]$T.Part) }
        'ErDisk'    { Start-ErRaw 'Disk' ([int]$T.Disk) 0 }
        'ErRecover' {
            if ([string]$T.Key -ne '') {
                $script:RcSelKey = [string]$T.Key
                if (-not (Select-TabChip 'sl' 'recover')) { Set-SlTab 'recover' }
            }
        }
    }
}

function Add-ErRow($Model, $Data) {
    $row = New-ItemRow $Model $Data $false $false
    if ([string]$Model.Btn1 -ne '') { $row.FindName('Act').Add_Click($script:H_ErAct) }
    if ([string]$Model.Btn2 -ne '') { $row.FindName('Act2').Add_Click($script:H_ErAct) }
    [void]$ui.sl_List.Children.Add($row)
    return $row
}

function Render-SlErase {
    $ui.sl_List.Children.Clear()
    if ($null -ne $script:ErLast) {
        $m = Get-ErResultModel $script:ErLast
        $key = Get-ErRecoverKey $script:ErLast
        $b1 = ''
        if ($key -ne '') { $b1 = 'Kurtarma motoruyla dene' }
        [void](Add-ErRow @{ Title = $m.Title; Detail = $m.Detail; BrCol = $m.BrCol; Btn1 = $b1 } @{ Do = 'ErRecover'; Key = $key })
    }
    Add-HeadRow $ui.sl_List 'Dosya ve klasörleri kalıcı sil'
    Add-Note $ui.sl_List 'Normal silme dosyayı yalnızca listeden kaldırır; içeriği diskte kalır ve kurtarma programları geri getirebilir. Kalıcı silme önce dosyanın üzerine rastgele veri yazar (geçiş sayısı Ayarlar’dan seçilir), sonra siler. Geri Dönüşüm Kutusu’na gitmez ve geri getirilemez. Kısayol noktaları izlenmez, bulutta duran dosyalar atlanır. Yukarıdaki düğmelerle bir dosya ya da klasör seçin; silmeden önce ne olacağı yazılır ve onayınız istenir.'
    Add-HeadRow $ui.sl_List 'Boş alanı temizle (silinmiş dosya kalıntıları)'
    Add-Note $ui.sl_List 'Daha önce normal yolla sildiğiniz dosyaların izleri, üzerine yeni veri yazılana kadar boş alanda kalır. Bilgisayarı satmadan, vermeden ya da hassas dosyalar sildikten sonra bu izleri yok edebilirsiniz. Yöntem, doğrulama ve “Sonra” seçenekleri yukarıdaki listelerden seçilir.'
    if ($null -eq $script:SlDisks) {
        Add-Note $ui.sl_List 'Sürücüler okunuyor...'
        Load-SlDisk
        return
    }
    if ($script:SlDisks.Failed -eq $true) {
        Add-Note $ui.sl_List 'Sürücü listesi okunamadı. Multimizer’ı yönetici olarak çalıştırdığınızdan emin olun, sonra “Yenile”ye basın.' 'warn'
        return
    }
    $models = Get-ErDriveModels @($script:SlDisks.Disks) ([string]$script:SlDisks.Sys.OsDrive)
    if (@($models).Count -eq 0) {
        Add-Note $ui.sl_List 'Temizlenebilecek sürücü bulunamadı (kilitli sürücüler ve boş yeri çok az olanlar listelenmez).' 'warn'
    }
    foreach ($m in $models) {
        $b2 = ''
        if ($m.Trim -eq $true) { $b2 = 'TRIM gönder' }
        $data = @{ Do = 'ErFree'; Drive = [string]$m.Drive; Free = [double]$m.Free; Size = [double]$m.Size; Media = [string]$m.Media; Bus = [string]$m.Bus; IsOs = ($m.IsOs -eq $true); Trim = ($m.Trim -eq $true) }
        $row = New-ItemRow @{ Title = [string]$m.Title; Detail = [string]$m.Detail; BrCol = [string]$m.BrCol; Btn1 = 'Boş alanı temizle'; Btn2 = $b2 } $data $false $false
        $row.FindName('Act').Add_Click($script:H_ErAct)
        if ($b2 -ne '') {
            $row.FindName('Act2').Tag = @{ Do = 'ErTrim'; Drive = [string]$m.Drive }
            $row.FindName('Act2').Add_Click($script:H_ErAct)
        }
        [void]$ui.sl_List.Children.Add($row)
    }

    Add-HeadRow $ui.sl_List 'Diskleri ve bölümleri sil'
    Add-Note $ui.sl_List 'Silinen dosya kurtarma sekmesiyle aynı kapsamda çalışır: sürücü harfi olmayan bölümler, tüm disk ve USB bellekler dahil. “Ayrılmamış alanı sil” bölümlerin dışında kalan, eski bölümlerden artakalan alanı yazar; bölüm ve disk silmede önce Windows bölümleri kaldırır, sonra alan doğrudan aygıttan üzerine yazılır. Geri getirilemez; bu yüzden hedefin adını yazarak onaylarsınız.'
    if ($script:IsAdmin -ne $true) { Add-Note $ui.sl_List 'Multimizer yönetici olarak çalışmıyor; disk, bölüm ve ayrılmamış alan silmek için yönetici olarak yeniden başlatın.' 'warn' }
    $dm = Get-ErDiskModels @($script:SlDisks.Phys)
    if (@($dm).Count -eq 0) {
        Add-Note $ui.sl_List 'Silinebilecek disk bulunamadı. Yeni bir USB bellek taktıysanız yukarıdaki “Yenile”ye basın.' 'warn'
    }
    foreach ($d in $dm) {
        $dmodel = @{ Title = [string]$d.Title; Detail = [string]$d.Detail; BrCol = [string]$d.BrCol; Btn1 = [string]$d.Btn1; Btn2 = [string]$d.Btn2 }
        $drow = New-ItemRow $dmodel @{ Do = 'ErGap'; Disk = [int]$d.Number } $false $false
        if ($d.Btn1 -ne '') { $drow.FindName('Act').Add_Click($script:H_ErAct) }
        if ($d.Btn2 -ne '') {
            $drow.FindName('Act2').Tag = @{ Do = 'ErDisk'; Disk = [int]$d.Number }
            $drow.FindName('Act2').Add_Click($script:H_ErAct)
        }
        [void]$ui.sl_List.Children.Add($drow)
        foreach ($p in @($d.Parts)) {
            $pm = @{ Title = ('      ' + [string]$p.Title); Detail = [string]$p.Detail; BrCol = [string]$p.BrCol; Btn1 = [string]$p.Btn1 }
            $prow = New-ItemRow $pm @{ Do = 'ErPart'; Disk = [int]$d.Number; Part = [int]$p.Number } $false $false
            if ($p.Btn1 -ne '') { $prow.FindName('Act').Add_Click($script:H_ErAct) }
            [void]$ui.sl_List.Children.Add($prow)
        }
    }

    Add-HeadRow $ui.sl_List 'Bilmeniz gerekenler'
    Add-Note $ui.sl_List 'Üzerine yazma, silinen verinin kurtarma programlarıyla geri getirilmesini engeller. SSD ve USB belleklerde denetleyici veriyi başka hücrelere taşıyabildiği için bu yöntem NIST SP 800-88 Rev.1 sınıflandırmasında “Clear” düzeyindedir; cihaz elden çıkarılacaksa üreticinin güvenli silme aracı ya da şifreleme ve anahtar silme daha güvenlidir. Bir standart için belgelendirme iddiası yoktur.'
    Add-Note $ui.sl_List 'Yedekler, gölge kopyalar (geri yükleme noktaları), OneDrive gibi bulut eşleşmeleri ve dosya adı kayıtları bu yöntemle silinmez. Windows’un çalıştığı, Multimizer’ın ya da geçici dosyaların bulunduğu diske doğrudan yazılmaz (yalnızca o sürücülerin boş alanı temizlenir); çevrimdışı, salt okunur ve depolama havuzu üyesi disklere dokunulmaz.'
    Add-Note $ui.sl_List 'Her işlemden sonra “Kurtarma motoruyla dene” düğmesi, aynı kaynağı Silinen dosyalar sekmesinde taratıp sonucu sınamanızı sağlar.'
    $ui.sl_Foot.Text = 'Kalıcı silme geri alınamaz. Windows Update, Defender ve Güvenlik Duvarı’na dokunulmaz.'
}

# ---------------- işlemler ----------------
# Elle yazdırılan onay: kutuya beklenen metin yazılmadıkça işlem başlamaz. Pencere kapandıktan sonra çağrıldığı için
# eşleşmezse yalnızca bildirim verir; kullanıcı düğmeye yeniden basar.
function Show-TypedConfirm([string]$Title, [string]$Text, [string]$OkText, [string]$Expect, [scriptblock]$OnOk) {
    $script:ErTypedExpect = $Expect
    $script:ErTypedAct = $OnOk
    $full = $Text + "`r`n`r`n" + 'Onaylamak için kutuya şunu yazın:  ' + $Expect
    Show-Overlay $Title $full $OkText $true $true $true '' {
        param($typed)
        if (-not (Test-WipeTyped ([string]$typed) $script:ErTypedExpect)) {
            Show-Toast 'Yazdığınız metin eşleşmedi; hiçbir şey silinmedi.' 'warn'
            return
        }
        $act = $script:ErTypedAct
        $script:ErTypedAct = $null
        if ($null -ne $act) { & $act }
    }
}

function Find-ErDisk([int]$No) {
    $d = $script:SlDisks
    if ($null -eq $d -or $d.Failed -eq $true -or $null -eq $d.Phys) { return $null }
    foreach ($x in @($d.Phys)) { if ($null -ne $x -and [int]$x.Number -eq $No) { return $x } }
    return $null
}

function Start-ErFree($T) {
    $ep = Get-ExtProblem 'DiskSilme'
    if ($ep -ne '') { Show-Message 'Boş alan temizleme kullanılamıyor' $ep; return }
    $o = Get-ErOptions
    $script:ErPendDrive = [string]$T.Drive
    $script:ErPend = @{ Kind = 'Free'; Drive = [string]$T.Drive; Method = [string]$o.Method; Verify = [string]$o.Verify; Trim = ($T.Trim -eq $true) }
    Show-Confirm 'Boş alanı temizle' (Get-ErFreeConfirmText $T $o) 'Temizle' {
        $p = $script:ErPend
        [void](Start-Async 'WipeFree' 'Job_WipeFree' @{ Drive = [string]$p.Drive; Method = [string]$p.Method; Canary = ([string]$p.Verify -ne 'none'); Trim = ($p.Trim -eq $true) } {
            param($r)
            Complete-ErFree $r
        } ([string]$p.Drive + ' boş alanı temizleniyor'))
    }
}

function Start-ErTrim($T) {
    $ep = Get-ExtProblem 'DiskSilme'
    if ($ep -ne '') { Show-Message 'TRIM kullanılamıyor' $ep; return }
    $script:ErPendDrive = [string]$T.Drive
    $script:ErPend = @{ Kind = 'Trim'; Drive = [string]$T.Drive }
    $txt = [string]$T.Drive + ' sürücüsü için silinmiş alanların SSD’ye bildirilmesi (TRIM) istenecek.' + "`r`n`r`n" + '•  Hiçbir dosyaya dokunulmaz; Windows zaten silinen alanları bildirir, bu işlem bekleyen bildirimleri hemen gönderir.' + "`r`n" + '•  Süre sürücü boyutuna göre saniyelerden dakikalara uzayabilir.'
    Show-Confirm 'TRIM gönder' $txt 'Gönder' {
        $p = $script:ErPend
        [void](Start-Async 'WipeTrim' 'Job_TrimVolume' @{ Drive = [string]$p.Drive } {
            param($r)
            Complete-ErTrim $r
        } ([string]$p.Drive + ' için TRIM gönderiliyor'))
    }
}

function Start-ErRaw([string]$Scope, [int]$DiskNo, [int]$PartNo) {
    $ep = Get-ExtProblem 'DiskSilme'
    if ($ep -ne '') { Show-Message 'Disk silme kullanılamıyor' $ep; return }
    if ($script:IsAdmin -ne $true) {
        Show-Message 'Yönetici izni gerekli' 'Disk, bölüm ve ayrılmamış alan silmek için Multimizer’ın yönetici olarak çalışması gerekir. Uygulamayı yönetici olarak yeniden başlatın.'
        return
    }
    $pl = New-ErRawPlan $Scope (Find-ErDisk $DiskNo) $PartNo (Get-ErOptions)
    if (-not $pl.Ok) { Show-Message 'Bu işlem yapılamaz' ([string]$pl.Why); return }
    $script:ErPend = @{ Kind = 'Raw'; Scope = $Scope; Params = $pl.Params; Label = [string]$pl.Label; Disk = $DiskNo }
    if ([string]$pl.Expect -ne '') {
        Show-TypedConfirm ([string]$pl.Title) ([string]$pl.Text) ([string]$pl.OkText) ([string]$pl.Expect) { Invoke-ErRawJob }
    } else {
        Show-Confirm ([string]$pl.Title) ([string]$pl.Text) ([string]$pl.OkText) { Invoke-ErRawJob } $true
    }
}

function Invoke-ErRawJob {
    $p = $script:ErPend
    if ($null -eq $p -or [string]$p.Kind -ne 'Raw') { return }
    [void](Start-Async 'WipeRaw' 'Job_WipeRaw' $p.Params {
        param($r)
        Complete-ErRaw $r
    } ([string]$p.Label))
}

# Ortak sonuç işleyici
function Complete-ErResult($R, [string]$Kind) {
    $drive = $script:ErPendDrive
    $scope = ''
    $disk = -1
    if ($null -ne $script:ErPend) {
        if ($null -ne $script:ErPend.Scope) { $scope = [string]$script:ErPend.Scope }
        if ($null -ne $script:ErPend.Disk) { $disk = [int]$script:ErPend.Disk }
    }
    if ($null -eq $R) {
        $R = @{ Ok = $false; Kind = $Kind; Drive = $drive; Scope = $scope; Disk = $disk; Written = 0; Canceled = $false; Error = 'İşlem tamamlanamadı; günlüğe bakın.' }
    } elseif ($null -ne $R.ExtError) {
        $R = @{ Ok = $false; Kind = $Kind; Drive = $drive; Scope = $scope; Disk = $disk; Written = 0; Canceled = $false; Error = [string]$R.ExtError }
    }
    $script:ErLast = $R
    $m = Get-ErResultModel $R
    $kindT = 'bad'
    if ($R.Ok -eq $true) { $kindT = 'good' } elseif ($R.Canceled -eq $true) { $kindT = 'warn' }
    if ($R.Nothing -eq $true) { $kindT = 'info' }
    Show-Toast ([string]$m.Toast) $kindT
    $script:SlDisks = $null
    # bölümler değiştiyse kurtarma sekmesinin önbelleğindeki bölüm bilgileri geçersizdir
    try {
        if ($null -ne $script:RcPartCache) {
            foreach ($ck in @($script:RcPartCache.Keys)) { if ([string]$ck -like 'PhysicalDrive*') { $script:RcPartCache.Remove($ck) } }
        }
    } catch { }
    if ([string]$script:UiState.Page -eq 'solve' -and $script:SlTab -eq 'erase') { Render-SlErase }
}

function Complete-ErFree($R) { Complete-ErResult $R 'Free' }
function Complete-ErTrim($R) { Complete-ErResult $R 'Trim' }
function Complete-ErRaw($R) { Complete-ErResult $R 'Raw' }

function Select-ErOption([string]$Which) {
    if ($script:ErLoading -eq $true) { return }
    $combo = $ui.sl_ErMethod
    if ($Which -eq 'Verify') { $combo = $ui.sl_ErVerify } elseif ($Which -eq 'After') { $combo = $ui.sl_ErAfter }
    $k = Get-ComboKey $combo
    if ($k -eq '') { return }
    $script:ErOpts[$Which] = $k
}

function Init-SlErase {
    $ui.sl_ErFile.Add_Click({ Invoke-Safe { Start-TlWipe $false } 'Dosyayı kalıcı sil' })
    $ui.sl_ErFolder.Add_Click({ Invoke-Safe { Start-TlWipe $true } 'Klasörü kalıcı sil' })
    $ui.sl_ErRefresh.Add_Click({ Invoke-Safe { $script:SlDisks = $null; Render-SlErase } 'Diskleri yenile' })
    $script:ErLoading = $true
    try {
        $ml = Get-WipeMethodList
        $c1 = New-Object System.Collections.ArrayList
        foreach ($x in $ml) { [void]$c1.Add((New-Choice ([string]$x.Key) ([string]$x.Name))) }
        Set-ComboChoices $ui.sl_ErMethod $c1.ToArray()
        [void](Select-ComboKey $ui.sl_ErMethod ([string]$script:ErOpts.Method))
        $vl = Get-WipeVerifyList
        $c2 = New-Object System.Collections.ArrayList
        foreach ($x in $vl) { [void]$c2.Add((New-Choice ([string]$x.Key) ([string]$x.Name))) }
        Set-ComboChoices $ui.sl_ErVerify $c2.ToArray()
        [void](Select-ComboKey $ui.sl_ErVerify ([string]$script:ErOpts.Verify))
        $al = Get-WipeAfterList
        $c3 = New-Object System.Collections.ArrayList
        foreach ($x in $al) { [void]$c3.Add((New-Choice ([string]$x.Key) ([string]$x.Name))) }
        Set-ComboChoices $ui.sl_ErAfter $c3.ToArray()
        [void](Select-ComboKey $ui.sl_ErAfter ([string]$script:ErOpts.After))
    } finally { $script:ErLoading = $false }
    $ui.sl_ErMethod.Add_SelectionChanged({ Invoke-Safe { Select-ErOption 'Method' } 'Silme yöntemi' })
    $ui.sl_ErVerify.Add_SelectionChanged({ Invoke-Safe { Select-ErOption 'Verify' } 'Silme doğrulaması' })
    $ui.sl_ErAfter.Add_SelectionChanged({ Invoke-Safe { Select-ErOption 'After' } 'Silme sonrası' })
}
