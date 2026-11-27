. "$PSScriptRoot/lib.ps1"
# Kurtarma eklentisi (Eklenti\Kurtarma.ps1): sentetik NTFS/FAT/exFAT imajları üzerinde silinmiş dosya bulma, imza taraması ve kopyalama.
# Gerçek sürücüye dokunulmaz; imajlar tests\gen_images.py ile bu testte üretilir ve hiçbir üçüncü taraf verisi içermez.
Import-Fn 'Initialize-MmRecover', 'Get-RcErrorText', 'Resolve-RcSource', 'Get-RcDirRoot', 'Test-RcDestination', 'Get-RcFreeName', 'ConvertTo-RcDate',
    'Job_RecoverScan', 'Job_RecoverFiles', 'Job_RecoverParts', 'Convert-RcParts', 'Format-Size'

# ---- sahte ortam ----
$script:Logs = New-Object System.Collections.ArrayList
$script:Prog = New-Object System.Collections.ArrayList
$script:CancelAfter = -1
$script:CancelCalls = 0
function Write-WhLog([string]$Message, [string]$Level = 'INFO') { [void]$script:Logs.Add($Level + ': ' + $Message) }
function Set-JobProgress([int]$Done, [int]$Total, [string]$Label = '') { [void]$script:Prog.Add(($Label + '|' + [string]$Done + '/' + [string]$Total)) }
function Test-JobCancel {
    $script:CancelCalls++
    if ($script:CancelAfter -ge 0 -and $script:CancelCalls -gt $script:CancelAfter) { return $true }
    return $false
}
function Reset-Mocks { $script:Logs.Clear(); $script:Prog.Clear(); $script:CancelAfter = -1; $script:CancelCalls = 0 }
function Get-Sha([string]$Path) { return ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash).ToLowerInvariant() }

# ---- imajlar ----
$root = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$imgDir = Join-Path (Join-Path $root 'work') 'img'
if (-not (Test-Path -LiteralPath (Join-Path $imgDir 'expect.json')) -or -not (Test-Path -LiteralPath (Join-Path $imgDir 'gpt_multi.img'))) {
    [void][System.IO.Directory]::CreateDirectory($imgDir)
    & python3 (Join-Path $PSScriptRoot 'gen_images.py') $imgDir | Out-Null
}
$exp = Get-Content -LiteralPath (Join-Path $imgDir 'expect.json') -Raw -Encoding UTF8 | ConvertFrom-Json
function Img([string]$Name) { return (Join-Path $imgDir $Name) }
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('mm-kurtarma-' + [System.Guid]::NewGuid().ToString('N').Substring(0, 8))
[void][System.IO.Directory]::CreateDirectory($tmp)

# ---- motor derlenir ----
Assert-Eq (Initialize-MmRecover) '' 'motor derleniyor'
Assert-True ($null -ne ('Mm.RcEngine' -as [type])) 'tür yüklü'
Assert-Eq (Initialize-MmRecover) '' 'ikinci çağrı sorunsuz'

# ---- salt okunur: imajların özeti işlemlerden sonra değişmez ----
$before = @{}
foreach ($f in @(Get-ChildItem -LiteralPath $imgDir -Filter '*.img')) { $before[$f.Name] = (Get-Sha $f.FullName) + '|' + $f.LastWriteTimeUtc.Ticks }

# ---- yardımcılar ----
Assert-True ([Mm.RcEngine]::IsDriveSpec('E')) 'sürücü: E'
Assert-True ([Mm.RcEngine]::IsDriveSpec('e:')) 'sürücü: e:'
Assert-True ([Mm.RcEngine]::IsDriveSpec('D:\')) 'sürücü: D:\'
Assert-True (-not [Mm.RcEngine]::IsDriveSpec('E:\klasor')) 'klasör yolu sürücü sayılmaz'
Assert-True (-not [Mm.RcEngine]::IsDriveSpec('')) 'boş sürücü değil'
Assert-True (-not [Mm.RcEngine]::IsDriveSpec('disk.img')) 'dosya adı sürücü değil'
Assert-Eq ([Mm.RcEngine]::SafeName('a<b>c:d"e/f\g|h?i*j.txt')) 'a_b_c_d_e_f_g_h_i_j.txt' 'geçersiz karakterler'
Assert-Eq ([Mm.RcEngine]::SafeName('CON')) '_CON' 'ayrılmış ad'
Assert-Eq ([Mm.RcEngine]::SafeName('nul.txt')) '_nul.txt' 'ayrılmış ad uzantılı'
Assert-Eq ([Mm.RcEngine]::SafeName('LPT1')) '_LPT1' 'LPT1'
Assert-Eq ([Mm.RcEngine]::SafeName('rapor. ')) 'rapor' 'sondaki nokta ve boşluk'
Assert-Eq ([Mm.RcEngine]::SafeName('..')) '_' 'iki nokta'
Assert-Eq ([Mm.RcEngine]::SafeName('')) '_' 'boş ad'
Assert-True (([Mm.RcEngine]::SafeName(('x' * 300) + '.pdf')).Length -le 120) 'uzun ad kısaltılır'
Assert-True (([Mm.RcEngine]::SafeName(('x' * 300) + '.pdf')).EndsWith('.pdf')) 'uzantı korunur'
$sep = [string][System.IO.Path]::DirectorySeparatorChar
Assert-Eq ([Mm.RcEngine]::SafeRelPath('Belgeler\Eski')) ('Belgeler' + $sep + 'Eski') 'göreli yol'
Assert-Eq ([Mm.RcEngine]::SafeRelPath('..\..\etc\x')) ('_' + $sep + '_' + $sep + 'etc' + $sep + 'x') 'üst klasöre çıkamaz'
Assert-Eq ([Mm.RcEngine]::SafeRelPath('')) '' 'boş yol'
Assert-True ((Format-Size 1536) -ne '') 'Format-Size çalışır'
Assert-True ($null -eq (ConvertTo-RcDate 0)) 'sıfır tarih yok'
Assert-True ($null -eq (ConvertTo-RcDate -5)) 'eksi tarih yok'
Assert-Eq ((ConvertTo-RcDate 133604154000000000).ToString('yyyy-MM-dd HH:mm:ss')) '2024-05-17 10:30:00' 'FILETIME çevirimi'

# ---- kaynak doğrulama ----
$s1 = Resolve-RcSource (Img 'ntfs.img')
Assert-True ($s1.Ok -eq $true -and $s1.Kind -eq 'Image') 'imaj kaynağı'
$s2 = Resolve-RcSource (Join-Path $tmp 'yok.img')
Assert-True ($s2.Ok -ne $true -and $s2.Error -match 'bulunamad') 'olmayan imaj'
$s3 = Resolve-RcSource ''
Assert-True ($s3.Ok -ne $true -and $s3.Error -match 'seçilmedi') 'boş kaynak'

# ---- NTFS: hızlı tarama ----
Reset-Mocks
$r = Job_RecoverScan @{ Source = (Img 'ntfs.img'); Mode = 'Quick' }
Assert-True ($r.Ok -eq $true) 'NTFS hızlı tarama başarılı'
Assert-Eq $r.Fs 'NTFS' 'dosya sistemi NTFS'
Assert-Eq $r.ClusterSize 4096 'küme boyutu'
Assert-Eq ([int]$r.Partitions) 1 'tek birimli imajda bölüm sayısı 1'
Assert-Eq $r.Items.Count 10 'silinmiş dosya sayısı'
Assert-Eq $r.Stats.Deleted 10 'istatistik: silinmiş'
Assert-Eq $r.Stats.Skipped 4 'istatistik: atlanan (sıkıştırılmış, şifreli, bozuk, boş)'
Assert-Eq $r.Stats.FromTable 10 'istatistik: tablodan'
Assert-Eq $r.Stats.Carved 0 'hızlı taramada imza yok'
Assert-True ($r.Truncated -ne $true -and $r.Canceled -ne $true) 'kesilmedi'
foreach ($bad in @('keep.txt', 'keep.bin', 'sikisik.dat', 'efs.dat', 'sifir.txt', '$IABCDEF.docx', 'bozuk.dat', 'yirtik.txt', 'yeni.bin', 'Belgeler', 'Eski')) {
    Assert-True (@($r.Items | Where-Object { $_.Name -ceq $bad }).Count -eq 0) ('listede olmamalı: ' + $bad)
}
foreach ($d in @($exp.ntfs.deleted)) {
    $m = @($r.Items | Where-Object { $_.Name -ceq [string]$d.name })
    Assert-Eq $m.Count 1 ('listede bir kez: ' + $d.name)
    if ($m.Count -ne 1) { continue }
    $it = $m[0]
    Assert-Eq $it.Kind 'mft' ($d.name + ': tür')
    Assert-Eq $it.Length ([long]$d.size) ($d.name + ': boyut')
    Assert-Eq $it.Chance ([int]$d.chance) ($d.name + ': şans')
    Assert-Eq $it.Path ([string]$d.path) ($d.name + ': yol')
    Assert-Eq $it.Modified ([long]$d.mod) ($d.name + ': değiştirme zamanı')
    Assert-Eq $it.Rec ([long]$d.rec) ($d.name + ': kayıt no')
    Assert-True ($it.Deleted -gt $it.Modified) ($d.name + ': silinme zamanı sonra')
}
$yarim = @($r.Items | Where-Object { $_.Name -ceq 'yarim.dat' })[0]
Assert-True ($yarim.Note -match 'kısmen') 'yarım dosya notu'
$ezil = @($r.Items | Where-Object { $_.Name -ceq 'ezilmis.dat' })[0]
Assert-True ($ezil.Note -match 'üzerine yazılmış') 'ezilmiş dosya notu'
Assert-Eq (@($r.Items | Where-Object { $_.Name -ceq 'foto.jpg' })[0].Ext) 'jpg' 'uzantı'
Assert-True (@($script:Prog | Where-Object { $_ -like 'Dosya tablosu okunuyor|*' }).Count -ge 1) 'ilerleme bildirildi'
Assert-True (@($script:Logs | Where-Object { $_ -like 'STEP:*SİLİNEN DOSYALAR*' }).Count -eq 1) 'günlük başlığı'

# ---- NTFS: derin tarama (yalnızca imza) ----
Reset-Mocks
$r2 = Job_RecoverScan @{ Source = (Img 'ntfs.img'); Mode = 'Deep' }
Assert-True ($r2.Ok -eq $true) 'NTFS derin tarama'
Assert-Eq $r2.Items.Count 14 'derin tarama: 13 sahipsiz + 1 silinmiş fotoğraf'
foreach ($c in @($exp.ntfs.carve)) {
    $m = @($r2.Items | Where-Object { $_.Offset -eq [long]$c.offset })
    Assert-Eq $m.Count 1 ('imza bulundu: ' + $c.name)
    if ($m.Count -ne 1) { continue }
    Assert-Eq $m[0].Length ([long]$c.size) ($c.name + ': uzunluk')
    Assert-Eq $m[0].Ext ([string]$c.ext) ($c.name + ': uzantı')
    Assert-Eq $m[0].Kind 'carve' ($c.name + ': tür')
}
Assert-True (@($r2.Items | Where-Object { $_.Offset -eq 760L * 4096 }).Count -eq 0) 'bozuk PNG tuzağı atlandı'
Assert-True (@($r2.Items | Where-Object { $_.Offset -eq 765L * 4096 }).Count -eq 0) 'bozuk JPEG tuzağı atlandı'
Assert-True (@($r2.Items | Where-Object { $_.Offset -eq [long]$exp.ntfs.trap_bmp_lcn * 4096 }).Count -eq 0) 'boş alanın dışına taşan dosya atlandı'
Assert-True (@($r2.Items | Where-Object { $_.Offset -eq 802L * 4096 }).Count -eq 0) 'dolu küme taranmadı'

# ---- NTFS: ikisi birden, kopyalar elenir ----
Reset-Mocks
$r3 = Job_RecoverScan @{ Source = (Img 'ntfs.img'); Mode = 'Both' }
Assert-Eq $r3.Items.Count 23 'ikisi birden: 10 + 13'
Assert-Eq @($r3.Items | Where-Object { $_.Kind -eq 'carve' }).Count 13 'imza ile bulunan 13'
Assert-Eq @($r3.Items | Where-Object { $_.Kind -eq 'carve' -and $_.Offset -eq 100L * 4096 }).Count 0 'silinmiş fotoğraf bir kez listelenir'
Assert-Eq $r3.Stats.Carved 13 'istatistik: imza'

# ---- tür süzgeci, sınır, iptal ----
$r4 = Job_RecoverScan @{ Source = (Img 'ntfs.img'); Mode = 'Deep'; Types = @('png', 'gif') }
Assert-Eq $r4.Items.Count 2 'yalnızca png ve gif'
$r5 = Job_RecoverScan @{ Source = (Img 'ntfs.img'); Mode = 'Quick'; MaxResults = 3 }
Assert-Eq $r5.Items.Count 3 'sonuç sınırı'
Assert-True ($r5.Truncated -eq $true) 'sınır aşıldı bilgisi'
Reset-Mocks
$script:CancelAfter = 0
$r6 = Job_RecoverScan @{ Source = (Img 'ntfs.img'); Mode = 'Both' }
Assert-True ($r6.Canceled -eq $true) 'tarama iptali'
Assert-True ($r6.Items.Count -lt 23) 'iptalde eksik liste'
Reset-Mocks

# ---- FAT32 / exFAT: hızlı tarama silinmiş girdilere bakar, derin tarama imza arar (bu imajlarda kök klasör boş, dosyalar sahipsiz) ----
foreach ($t in @(@('fat32.img', 'FAT32', 'fat'), @('exfat.img', 'exFAT', 'exfat'))) {
    Reset-Mocks
    $q = Job_RecoverScan @{ Source = (Img $t[0]); Mode = 'Quick' }
    Assert-True ($q.Ok -eq $true) ($t[1] + ': hızlı tarama')
    Assert-Eq $q.Method $t[2] ($t[1] + ': yöntem')
    Assert-True ($q.Raw -ne $true) ($t[1] + ': ham mod değil')
    Assert-Eq $q.Items.Count 0 ($t[1] + ': kök klasör boş, silinmiş girdi yok')
    Assert-Eq $q.Stats.Carved 0 ($t[1] + ': hızlı taramada imza yok')
    Reset-Mocks
    $rr = Job_RecoverScan @{ Source = (Img $t[0]); Mode = 'Deep' }
    Assert-True ($rr.Ok -eq $true) ($t[1] + ': derin tarama')
    Assert-Eq $rr.Fs $t[1] ($t[1] + ': ad')
    $e = $exp.($t[1].ToLowerInvariant())
    Assert-Eq $rr.Items.Count @($e).Count ($t[1] + ': dosya sayısı')
    Assert-Eq $rr.Stats.FromTable 0 ($t[1] + ': tablodan yok')
    foreach ($c in @($e)) {
        $m = @($rr.Items | Where-Object { $_.Offset -eq [long]$c.offset })
        Assert-Eq $m.Count 1 ($t[1] + ': ' + $c.name + ' bulundu')
        if ($m.Count -eq 1) { Assert-Eq $m[0].Length ([long]$c.size) ($t[1] + ': ' + $c.name + ' uzunluk'); Assert-Eq $m[0].Ext ([string]$c.ext) ($t[1] + ': ' + $c.name + ' uzantı') }
    }
    $rb = Job_RecoverScan @{ Source = (Img $t[0]); Mode = 'Both' }
    Assert-Eq $rb.Items.Count @($e).Count ($t[1] + ': ikisi birden de aynı sayıda')
}
foreach ($t in @(@('fat16.img', 'FAT16'), @('fat12.img', 'FAT12'))) {
    $rr = Job_RecoverScan @{ Source = (Img $t[0]); Mode = 'Deep' }
    Assert-True ($rr.Ok -eq $true) ($t[1] + ': tarama')
    Assert-Eq $rr.Fs $t[1] ($t[1] + ': ad')
    $e = $exp.($t[1].ToLowerInvariant())
    Assert-Eq $rr.Items.Count @($e.items).Count ($t[1] + ': dosya sayısı')
    foreach ($c in @($e.items)) {
        $m = @($rr.Items | Where-Object { $_.Offset -eq [long]$c.offset })
        Assert-Eq $m.Count 1 ($t[1] + ': ' + $c.name + ' bulundu')
        if ($m.Count -eq 1) { Assert-Eq $m[0].Length ([long]$c.size) ($t[1] + ': ' + $c.name + ' uzunluk') }
    }
}

# ---- bölüm tabloları ----
$m0 = Job_RecoverScan @{ Source = (Img 'mbr2.img'); Mode = 'Quick'; Partition = 0 }
Assert-True ($m0.Ok -eq $true -and $m0.Fs -eq 'NTFS' -and $m0.Items.Count -eq 10) 'MBR: ilk bölüm NTFS'
Assert-Eq ([int]$m0.Partitions) 2 'MBR: bölüm sayısı bildirilir'
$m1 = Job_RecoverScan @{ Source = (Img 'mbr2.img'); Mode = 'Deep'; Partition = 1 }
Assert-True ($m1.Ok -eq $true -and $m1.Fs -eq 'FAT32' -and $m1.Items.Count -eq 5) 'MBR: ikinci bölüm FAT32'
$m1q = Job_RecoverScan @{ Source = (Img 'mbr2.img'); Mode = 'Quick'; Partition = 1 }
Assert-True ($m1q.Ok -eq $true -and $m1q.Fs -eq 'FAT32' -and $m1q.Items.Count -eq 0) 'MBR: ikinci bölüm hızlı taramada silinmiş girdi yok'
Assert-Eq ([int]$m1.Partitions) 2 'MBR: ikinci bölüm seçilince de bölüm sayısı aynı'
$m2 = Job_RecoverScan @{ Source = (Img 'mbr2.img'); Mode = 'Quick'; Partition = 5 }
Assert-True ($m2.Ok -ne $true -and $m2.Error -match 'Bölüm bulunamadı') 'MBR: olmayan bölüm'
$g = Job_RecoverScan @{ Source = (Img 'gpt.img'); Mode = 'Deep' }
Assert-True ($g.Ok -eq $true -and $g.Fs -eq 'exFAT' -and $g.Items.Count -eq 5) 'GPT: exFAT bölümü'
Assert-Eq ([int]$g.Partitions) 1 'GPT: tek bölüm'

# ---- hatalı kaynaklar ----
$b1 = Job_RecoverScan @{ Source = (Img 'blank.img'); Mode = 'Quick' }
Assert-True ($b1.Ok -eq $true -and $b1.Raw -eq $true -and $b1.Method -eq 'raw' -and $b1.Items.Count -eq 0) 'boş imaj: ham tarama, bulunacak bir şey yok'
Assert-Eq $b1.Fs 'Bilinmeyen' 'boş imaj: dosya sistemi bilinmiyor'
Assert-True ($b1.Note -match 'tanınamadı') 'boş imaj: açıklama'
$b2 = Job_RecoverScan @{ Source = (Img 'bitlocker.img'); Mode = 'Quick' }
Assert-True ($b2.Ok -ne $true -and $b2.Error -match 'BitLocker') 'BitLocker kilitli'
$b3 = Job_RecoverScan @{ Source = (Join-Path $tmp 'yok.img'); Mode = 'Quick' }
Assert-True ($b3.Ok -ne $true -and $b3.Error -match 'bulunamad') 'olmayan kaynak'
$threw = $false
try { $b4 = Job_RecoverScan @{ Source = (Img 'ntfs_trunc.img'); Mode = 'Both' } } catch { $threw = $true }
Assert-True (-not $threw) 'yarım imaj istisna fırlatmaz'
Assert-True ($b4.Ok -eq $true -or [string]$b4.Error -ne '') 'yarım imaj: sonuç ya da açıklama var'

# ---- kopyalama: NTFS ----
$ntfs = Img 'ntfs.img'
$dest = Join-Path $tmp 'hedef'
$sel = @($r.Items)
Reset-Mocks
$x = Job_RecoverFiles @{ Source = $ntfs; Dest = $dest; Items = $sel; KeepPaths = $true }
Assert-True ($x.Ok -eq $true) 'kurtarma başarılı'
Assert-Eq $x.Done 10 'kurtarılan sayısı'
Assert-Eq $x.Failed 0 'kurtarılamayan yok'
Assert-True ($x.Dir.StartsWith($dest)) 'yeni klasör hedefin içinde'
Assert-True ((Split-Path -Leaf $x.Dir) -like 'Multimizer-Kurtarma-*') 'klasör adı'
Assert-True (Test-Path -LiteralPath $x.Report) 'rapor yazıldı'
$rep = [System.IO.File]::ReadAllText($x.Report)
Assert-True ($rep.StartsWith([string][char]0xFEFF) -or $rep.StartsWith('Dosya;')) 'rapor başlığı'
Assert-True ($rep -match 'notlar.txt') 'raporda dosya adı'
$byName = @{}
foreach ($row in @($x.Results)) { $byName[[string]$row.Name] = $row }
foreach ($d in @($exp.ntfs.deleted)) {
    $row = $byName[[string]$d.name]
    Assert-True ($null -ne $row -and $row.Ok -eq $true) ($d.name + ': kaydedildi')
    if ($null -eq $row -or $row.Ok -ne $true) { continue }
    Assert-True (Test-Path -LiteralPath $row.Path) ($d.name + ': dosya var')
    if ([int]$d.chance -eq 100) {
        Assert-Eq (Get-Sha $row.Path) ([string]$d.sha) ($d.name + ': içerik özeti')
    }
    $fi = Get-Item -LiteralPath $row.Path
    Assert-Eq $fi.LastWriteTimeUtc.ToString('yyyy-MM-dd HH:mm:ss') '2024-05-17 10:30:00' ($d.name + ': değiştirme tarihi geri yazıldı')
    Assert-Eq $fi.Length ([long]$d.size) ($d.name + ': boyut')
    $rel = $row.Path.Substring($x.Dir.Length).TrimStart('/', '\')
    $wantRel = ([string]$d.path).Replace('\', $sep)
    if ($wantRel -ne '') { Assert-True ($rel.StartsWith($wantRel + $sep)) ($d.name + ': klasör yapısı korundu (' + $rel + ')') } else { Assert-True (-not ($rel.Contains($sep))) ($d.name + ': kökte (' + $rel + ')') }
}
# yarım dosya: ilk iki küme özgün, sonrası başka dosyanın verisi
$yp = $byName['yarim.dat'].Path
$orig = $null
$bytes = [System.IO.File]::ReadAllBytes($yp)
$img = [System.IO.File]::ReadAllBytes($ntfs)
$same = $true
for ($i = 0; $i -lt 8192; $i++) { if ($bytes[$i] -ne $img[300 * 4096 + $i]) { $same = $false; break } }
Assert-True $same 'yarim.dat: özgün kümeler okundu'
# ezilmiş dosya: şimdi yeni.bin'in kümelerinde, içerik özgünle aynı olmamalı
$ezSha = [string](@($exp.ntfs.deleted | Where-Object { $_.name -eq 'ezilmis.dat' })[0].sha)
Assert-True ((Get-Sha $byName['ezilmis.dat'].Path) -ne $ezSha) 'ezilmis.dat: üzerine yazılmış veri özgün değil'

# ikinci kurtarma ilkinin üzerine yazmaz
$x2 = Job_RecoverFiles @{ Source = $ntfs; Dest = $dest; Items = @($sel[0]); KeepPaths = $false }
Assert-True ($x2.Ok -eq $true -and $x2.Dir -ne $x.Dir) 'ikinci kurtarma yeni klasöre gider'
Assert-True (Test-Path -LiteralPath $x.Dir) 'ilk klasör duruyor'
$flat = @(Get-ChildItem -LiteralPath $x2.Dir -File | Where-Object { $_.Name -ne 'Kurtarma-Raporu.csv' })
Assert-Eq $flat.Count 1 'klasör yapısı korunmayınca dosya kökte'

# ---- kopyalama: imza ile bulunanlar ----
Reset-Mocks
$carved = @($r3.Items | Where-Object { $_.Kind -eq 'carve' })
$dest2 = Join-Path $tmp 'hedef2'
$y = Job_RecoverFiles @{ Source = $ntfs; Dest = $dest2; Items = $carved; KeepPaths = $true }
Assert-True ($y.Ok -eq $true) 'imza kurtarma başarılı'
Assert-Eq $y.Done 13 '13 dosya'
foreach ($c in @($exp.ntfs.carve)) {
    $row = @($y.Results | Where-Object { $_.Ok -eq $true -and (Get-Item -LiteralPath $_.Path).Length -eq [long]$c.size -and (Get-Sha $_.Path) -eq [string]$c.sha })
    Assert-Eq $row.Count 1 ('imza: ' + $c.name + ' içeriği birebir aynı')
}
Assert-True (@($y.Results | Where-Object { $_.Path -like '*İmza taraması*' }).Count -eq 13) 'imza dosyaları kendi klasöründe'
# FAT32 / exFAT / FAT16 / FAT12 / GPT içeriği birebir
foreach ($t in @(@('fat32.img', 'fat32', @($exp.fat32)), @('exfat.img', 'exfat', @($exp.exfat)), @('fat16.img', 'fat16', @($exp.fat16.items)), @('fat12.img', 'fat12', @($exp.fat12.items)))) {
    $sc = Job_RecoverScan @{ Source = (Img $t[0]); Mode = 'Deep' }
    $d3 = Join-Path $tmp ('hedef-' + $t[1])
    $z = Job_RecoverFiles @{ Source = (Img $t[0]); Dest = $d3; Items = @($sc.Items); KeepPaths = $false }
    Assert-True ($z.Ok -eq $true -and $z.Done -eq $t[2].Count) ($t[1] + ': kopyalama')
    foreach ($c in $t[2]) {
        $hit = @($z.Results | Where-Object { $_.Ok -eq $true -and (Get-Sha $_.Path) -eq [string]$c.sha })
        Assert-Eq $hit.Count 1 ($t[1] + ': ' + $c.name + ' birebir')
    }
}
$gs = Job_RecoverScan @{ Source = (Img 'gpt.img'); Mode = 'Deep' }
$gz = Job_RecoverFiles @{ Source = (Img 'gpt.img'); Dest = (Join-Path $tmp 'hedef-gpt'); Items = @($gs.Items) }
$gOk = 0
foreach ($c in @($exp.exfat)) { if (@($gz.Results | Where-Object { $_.Ok -eq $true -and (Get-Sha $_.Path) -eq [string]$c.sha }).Count -eq 1) { $gOk++ } }
Assert-Eq $gOk 5 'GPT içindeki exFAT dosyaları birebir'

# ---- bölüm düzenleri: Job_RecoverParts ----
$pn = Job_RecoverParts @{ Source = (Img 'ntfs.img') }
Assert-True ($pn.Ok -eq $true -and @($pn.Parts).Count -eq 1 -and $pn.Parts[0].Fs -eq 'NTFS' -and $pn.Parts[0].Kind -eq 'birim') 'bölümsüz imaj: tek birim'
$pm = Job_RecoverParts @{ Source = (Img 'mbr_ext.img') }
Assert-True ($pm.Ok -eq $true) 'MBR+EBR: okundu'
Assert-Eq @($pm.Parts).Count 4 'MBR+EBR: dört bölüm (iki birincil, iki mantıksal)'
Assert-Eq (@($pm.Parts | ForEach-Object { $_.Fs }) -join ',') 'FAT32,ext4,exFAT,Btrfs' 'MBR+EBR: dosya sistemleri sırayla'
Assert-Eq (@($pm.Parts | ForEach-Object { $_.Index }) -join ',') '0,1,2,3' 'MBR+EBR: sıra numaraları'
Assert-Eq ([double]$pm.Parts[0].Start) 1048576 'MBR+EBR: ilk bölüm konumu'
Assert-Eq ([double]$pm.Parts[0].Length) 5242880 'MBR+EBR: ilk bölüm uzunluğu'
Assert-Eq $pm.Parts[0].Kind 'MBR:0C' 'MBR+EBR: tür kodu'
Assert-Eq $pm.Parts[2].Kind 'MBR:07' 'MBR+EBR: mantıksal bölüm tür kodu'
Assert-True ([double]$pm.Parts[2].Start -gt [double]$pm.Parts[1].Start) 'MBR+EBR: mantıksal bölümler genişletilmiş alanda'
$pg = Job_RecoverParts @{ Source = (Img 'gpt_multi.img') }
Assert-Eq (@($pg.Parts | ForEach-Object { $_.Fs }) -join ',') 'FAT32,NTFS,ext4' 'GPT: MSR bölümü listelenmez'
Assert-True (@($pg.Parts | Where-Object { $_.Kind -ne 'GPT' }).Count -eq 0) 'GPT: tür'
$pb = Job_RecoverParts @{ Source = (Img 'blank.img') }
Assert-True ($pb.Ok -eq $true -and @($pb.Parts).Count -eq 0) 'boş imaj: bölüm yok'
$py = Job_RecoverParts @{ Source = (Join-Path $tmp 'yok.img') }
Assert-True ($py.Ok -ne $true -and $py.Error -match 'bulunamad') 'olmayan kaynak: bölüm listesi hata verir'
$pe = Job_RecoverParts @{ Source = '' }
Assert-True ($pe.Ok -ne $true -and $pe.Error -match 'seçilmedi') 'boş kaynak: bölüm listesi hata verir'

# ---- çok bölümlü imajlar: her bölüm kendi biçimiyle taranır ----
$px = @(
    @('mbr_ext.img', 0, 'FAT32', 'fat', 10, 4), @('mbr_ext.img', 1, 'ext4', 'free', 5, 4), @('mbr_ext.img', 2, 'exFAT', 'exfat', 7, 4), @('mbr_ext.img', 3, 'Btrfs', 'raw', 2, 4),
    @('gpt_multi.img', 0, 'FAT32', 'fat', 10, 3), @('gpt_multi.img', 1, 'NTFS', 'mft', 10, 3), @('gpt_multi.img', 2, 'ext4', 'free', 5, 3)
)
foreach ($t in $px) {
    Reset-Mocks
    $w = Job_RecoverScan @{ Source = (Img $t[0]); Mode = 'Quick'; Partition = [int]$t[1] }
    $lbl = $t[0] + ' bölüm ' + [string]$t[1]
    Assert-True ($w.Ok -eq $true) ($lbl + ': tarama')
    Assert-Eq $w.Fs $t[2] ($lbl + ': dosya sistemi')
    Assert-Eq $w.Method $t[3] ($lbl + ': yöntem')
    Assert-Eq $w.Items.Count $t[4] ($lbl + ': dosya sayısı')
    Assert-Eq ([int]$w.Partitions) $t[5] ($lbl + ': bölüm sayısı')
    Assert-Eq @($w.PartList).Count $t[5] ($lbl + ': bölüm listesi')
}
$wx = Job_RecoverScan @{ Source = (Img 'mbr_ext.img'); Mode = 'Quick'; Partition = 4 }
Assert-True ($wx.Ok -ne $true -and $wx.Error -match 'Bölüm bulunamadı') 'MBR+EBR: olmayan bölüm'
$wy = Job_RecoverScan @{ Source = (Img 'gpt_multi.img'); Mode = 'Quick'; Partition = 3 }
Assert-True ($wy.Ok -ne $true -and $wy.Error -match 'Bölüm bulunamadı') 'GPT: olmayan bölüm (MSR sayılmaz)'
# bölümdeki dosyalar birebir kurtarılır (bölüm başlangıcı doğru hesaplanıyor)
$wp = Job_RecoverScan @{ Source = (Img 'gpt_multi.img'); Mode = 'Quick'; Partition = 0 }
$wz = Job_RecoverFiles @{ Source = (Img 'gpt_multi.img'); Dest = (Join-Path $tmp 'hedef-gptp0'); Items = @($wp.Items | Where-Object { $_.Chance -eq 100 }); Partition = 0; KeepPaths = $true }
Assert-True ($wz.Ok -eq $true -and $wz.Done -eq 3) 'GPT bölüm 0: yüzde yüz şanslı üç dosya'
foreach ($d in @($exp.fat32d.deleted | Where-Object { [int]$_.chance -eq 100 })) {
    Assert-Eq @($wz.Results | Where-Object { $_.Ok -eq $true -and (Get-Sha $_.Path) -eq [string]$d.sha }).Count 1 ('GPT bölüm 0: ' + $d.name + ' birebir')
}
$we = Job_RecoverScan @{ Source = (Img 'mbr_ext.img'); Mode = 'Quick'; Partition = 2 }
$wf = Job_RecoverFiles @{ Source = (Img 'mbr_ext.img'); Dest = (Join-Path $tmp 'hedef-mbrp2'); Items = @($we.Items | Where-Object { $_.Chance -eq 100 }); Partition = 2; KeepPaths = $true }
Assert-True ($wf.Ok -eq $true -and $wf.Done -eq 5) 'MBR mantıksal exFAT bölümü: beş dosya'
foreach ($d in @($exp.exfatd.deleted | Where-Object { [int]$_.chance -eq 100 })) {
    Assert-Eq @($wf.Results | Where-Object { $_.Ok -eq $true -and (Get-Sha $_.Path) -eq [string]$d.sha }).Count 1 ('MBR mantıksal bölüm: ' + $d.name + ' birebir')
}
$wh = Job_RecoverScan @{ Source = (Img 'mbr_ext.img'); Mode = 'Quick'; Partition = 3 }
$wi = Job_RecoverFiles @{ Source = (Img 'mbr_ext.img'); Dest = (Join-Path $tmp 'hedef-mbrp3'); Items = @($wh.Items); Partition = 3 }
Assert-True ($wi.Ok -eq $true -and $wi.Done -eq 2) 'MBR mantıksal Btrfs bölümü: ham tarama sonuçları kurtarılır'
foreach ($c in @($exp.sniff.btrfs.items)) {
    Assert-Eq @($wi.Results | Where-Object { $_.Ok -eq $true -and (Get-Sha $_.Path) -eq [string]$c.sha }).Count 1 ('Btrfs bölümü: ' + [string]$c.offset + ' birebir')
}

# ---- tüm disk: bölüm düzenine bakılmadan imza taraması (bölüm tablosu silinmiş ya da bozulmuş diskler için) ----
function Test-WholeDisk([string]$Label, [string]$Image, $Want, [int]$Count) {
    Reset-Mocks
    $w = Job_RecoverScan @{ Source = (Img $Image); Mode = 'Quick'; Partition = -1 }
    Assert-True ($w.Ok -eq $true) ($Label + ': tüm disk taraması')
    Assert-Eq $w.Fs 'Tüm disk' ($Label + ': ad')
    Assert-Eq $w.Method 'raw' ($Label + ': yöntem')
    Assert-True ($w.Raw -eq $true) ($Label + ': ham tarama')
    Assert-Eq ([int]$w.ClusterSize) 512 ($Label + ': sektör hizası')
    Assert-Eq ([double]$w.VolumeBytes) ([double](Get-Item -LiteralPath (Img $Image)).Length) ($Label + ': boyut kaynağın tamamı')
    Assert-True ($w.Note -match 'bölüm düzenine bakılmadan') ($Label + ': açıklama')
    Assert-Eq ([int]$w.Partitions) $Count ($Label + ': bölüm sayısı bilgisi')
    Assert-Eq $w.Stats.FromTable 0 ($Label + ': kayıt tablosu kullanılmaz')
    Assert-True ($w.Stats.Carved -ge @($Want).Count) ($Label + ': imzayla bulunan sayısı')
    $ok = 0
    foreach ($d in @($Want)) {
        $abs = [long]$d.Abs
        $m = @($w.Items | Where-Object { $_.Kind -eq 'carve' -and $_.Offset -eq $abs -and $_.Length -eq [long]$d.Size })
        Assert-Eq $m.Count 1 ($Label + ': ' + $d.Name + ' konumda bulundu')
        if ($m.Count -eq 1) { $ok++ }
    }
    $dest = Join-Path $tmp ('hedef-tum-' + $Label.Replace(' ', '_'))
    $sel = @($w.Items | Where-Object { $o = $_.Offset; @($Want | Where-Object { [long]$_.Abs -eq $o }).Count -gt 0 })
    Assert-Eq $sel.Count @($Want).Count ($Label + ': seçilen öğe sayısı')
    $rr = Job_RecoverFiles @{ Source = (Img $Image); Dest = $dest; Items = $sel; Partition = -1 }
    Assert-True ($rr.Ok -eq $true -and $rr.Done -eq @($Want).Count) ($Label + ': hepsi kurtarıldı')
    # aynı içerikli dosyalar birden çok bölümde olabilir: özet başına beklenen adet kadar kurtarılmış dosya olmalı
    foreach ($g in @($Want | Group-Object { [string]$_.Sha })) {
        $res = @($rr.Results | Where-Object { $_.Ok -eq $true -and (Get-Sha $_.Path) -eq [string]$g.Name })
        Assert-Eq $res.Count $g.Count ($Label + ': ' + [string]@($g.Group)[0].Name + ' birebir')
    }
    return $w
}
$pw = @($pm.Parts | ForEach-Object { [long]$_.Start })
$wantM = New-Object System.Collections.ArrayList
foreach ($o in @($exp.fat32d.orphans)) { [void]$wantM.Add(@{ Name = 'FAT32 ' + $o.name; Abs = $pw[0] + [long]$o.offset; Size = [long]$o.size; Sha = [string]$o.sha }) }
foreach ($o in @($exp.ext4.items)) { [void]$wantM.Add(@{ Name = 'ext4 ' + $o.name; Abs = $pw[1] + [long]$o.offset; Size = [long]$o.size; Sha = [string]$o.sha }) }
foreach ($o in @($exp.exfatd.orphans)) { [void]$wantM.Add(@{ Name = 'exFAT ' + $o.name; Abs = $pw[2] + [long]$o.offset; Size = [long]$o.size; Sha = [string]$o.sha }) }
$bi = 0
foreach ($o in @($exp.sniff.btrfs.items)) { $bi++; [void]$wantM.Add(@{ Name = ('Btrfs ' + [string]$bi); Abs = $pw[3] + [long]$o.offset; Size = [long]$o.size; Sha = [string]$o.sha }) }
$wm = Test-WholeDisk 'MBR+EBR dört bölüm' 'mbr_ext.img' $wantM 4
Assert-Eq @($wm.Items | Where-Object { $_.Kind -ne 'carve' }).Count 0 'MBR+EBR tüm disk: yalnızca imza kayıtları'
$pg2 = @($pg.Parts | ForEach-Object { [long]$_.Start })
$wantG = New-Object System.Collections.ArrayList
foreach ($o in @($exp.fat32d.orphans)) { [void]$wantG.Add(@{ Name = 'FAT32 ' + $o.name; Abs = $pg2[0] + [long]$o.offset; Size = [long]$o.size; Sha = [string]$o.sha }) }
foreach ($c in @($exp.ntfs.carve)) { [void]$wantG.Add(@{ Name = 'NTFS ' + $c.name; Abs = $pg2[1] + [long]$c.offset; Size = [long]$c.size; Sha = [string]$c.sha }) }
foreach ($o in @($exp.ext4.items)) { [void]$wantG.Add(@{ Name = 'ext4 ' + $o.name; Abs = $pg2[2] + [long]$o.offset; Size = [long]$o.size; Sha = [string]$o.sha }) }
[void](Test-WholeDisk 'GPT üç bölüm' 'gpt_multi.img' $wantG 3)
# bölümsüz birim ve bölüm tablosu olmayan alan da aynı yolla taranır
$wantN = New-Object System.Collections.ArrayList
foreach ($c in @($exp.ntfs.carve)) { [void]$wantN.Add(@{ Name = 'NTFS ' + $c.name; Abs = [long]$c.offset; Size = [long]$c.size; Sha = [string]$c.sha }) }
[void](Test-WholeDisk 'bölümsüz NTFS birimi' 'ntfs.img' $wantN 1)
$wantR = New-Object System.Collections.ArrayList
$ri = 0
foreach ($c in @($exp.rawimg.items)) { $ri++; [void]$wantR.Add(@{ Name = ('ham ' + [string]$ri); Abs = [long]$c.offset; Size = [long]$c.size; Sha = [string]$c.sha }) }
[void](Test-WholeDisk 'bölümsüz ham alan' 'raw.img' $wantR 1)
Reset-Mocks
$wb = Job_RecoverScan @{ Source = (Img 'blank.img'); Mode = 'Quick'; Partition = -1 }
Assert-True ($wb.Ok -eq $true -and $wb.Items.Count -eq 0 -and $wb.Method -eq 'raw') 'boş alan: tüm disk taraması hatasız, sonuç yok'
# şifreli birim: dosyalar imzayla bulunamaz, kullanıcıya açıkça söylenir
$wl = Job_RecoverScan @{ Source = (Img 'bitlocker.img'); Mode = 'Quick'; Partition = -1 }
Assert-True ($wl.Ok -eq $true -and $wl.Note -match 'Şifrelenmiş 1 bölüm var \(BitLocker ya da LUKS\)') 'BitLocker birimi: tüm disk notu şifreyi belirtir'
$wl2 = Job_RecoverScan @{ Source = (Img 'luks.img'); Mode = 'Quick'; Partition = -1 }
Assert-True ($wl2.Ok -eq $true -and $wl2.Note -match 'Şifrelenmiş 1 bölüm var') 'LUKS birimi: tüm disk notu şifreyi belirtir'
# olmayan kaynak ve iptal
$wn = Job_RecoverScan @{ Source = (Join-Path $tmp 'yok.img'); Mode = 'Quick'; Partition = -1 }
Assert-True ($wn.Ok -ne $true -and $wn.Error -match 'bulunamad') 'tüm disk: olmayan kaynak hata verir'
Reset-Mocks
$script:CancelAfter = 0
$wc = Job_RecoverScan @{ Source = (Img 'mbr_ext.img'); Mode = 'Quick'; Partition = -1 }
Assert-True ($wc.Canceled -eq $true) 'tüm disk: iptal edilebilir'
Reset-Mocks

# ---- FAT12/16/32 ve exFAT: silinmiş girdilerden ad, klasör, tarih ----
function Get-StampTicks($A) { return ([DateTime]::new([int]$A[0], [int]$A[1], [int]$A[2], [int]$A[3], [int]$A[4], [int]$A[5], [DateTimeKind]::Local)).ToFileTimeUtc() }
function Test-DeletedList([string]$Label, $Result, $Want, [scriptblock]$StampOf) {
    Assert-True ($Result.Ok -eq $true) ($Label + ': tarama')
    Assert-Eq $Result.Items.Count @($Want).Count ($Label + ': dosya sayısı')
    Assert-Eq $Result.Stats.FromTable @($Want).Count ($Label + ': istatistik: kayıttan')
    Assert-Eq $Result.Stats.Carved 0 ($Label + ': hızlı taramada imza yok')
    foreach ($d in @($Want)) {
        $m = @($Result.Items | Where-Object { $_.Name -ceq [string]$d.name -and $_.Path -ceq [string]$d.path })
        Assert-Eq $m.Count 1 ($Label + ': listede bir kez: ' + $d.path + '\' + $d.name)
        if ($m.Count -ne 1) { continue }
        $it = $m[0]
        $lb = $Label + ': ' + $d.name
        Assert-Eq $it.Kind 'fat' ($lb + ': tür')
        Assert-Eq $it.Length ([long]$d.size) ($lb + ': boyut')
        Assert-Eq $it.Chance ([int]$d.chance) ($lb + ': şans')
        Assert-Eq $it.Offset ([long]$d.offset) ($lb + ': konum')
        Assert-Eq $it.Deleted 0L ($lb + ': silinme zamanı kayıtlı değil')
        Assert-Eq $it.Modified (& $StampOf $d) ($lb + ': değiştirme zamanı')
        Assert-Eq $it.Ext ([System.IO.Path]::GetExtension([string]$d.name).TrimStart('.').ToLowerInvariant()) ($lb + ': uzantı')
        if ($null -ne $d.note) { Assert-True ($it.Note -match [regex]::Escape([string]$d.note)) ($lb + ': not (' + $it.Note + ')') } else { Assert-Eq $it.Note '' ($lb + ': not yok') }
    }
}

Reset-Mocks
$fd = Job_RecoverScan @{ Source = (Img 'fat32d.img'); Mode = 'Quick' }
Test-DeletedList 'FAT32 klasörlü' $fd $exp.fat32d.deleted { param($d) Get-StampTicks $exp.fat32d.stamps.([string]$d.stamp) }
Assert-Eq $fd.Method 'fat' 'FAT32 klasörlü: yöntem'
Assert-Eq $fd.Fs 'FAT32' 'FAT32 klasörlü: ad'
Assert-Eq $fd.ClusterSize 4096 'FAT32 klasörlü: küme boyutu'
foreach ($bad in @('KEEP.TXT', 'KULLAN.BIN', 'YENI.DAT', 'TUT.TXT', 'BOS.TXT', 'TARIH.DAT', 'MM-DIRS', 'SILIK', 'BELGELER', 'EZILDI.DAT', 'BOSLUK.JPG', 'FOTO.JPG')) {
    Assert-True (@($fd.Items | Where-Object { $_.Name -ceq $bad }).Count -eq 0) ('FAT32 klasörlü: listede olmamalı: ' + $bad)
}
Assert-True (@($script:Logs | Where-Object { $_ -like 'INFO: 10 silinmiş dosya kaydı bulundu.' }).Count -eq 1) 'FAT32 klasörlü: günlük'
Assert-True (@($script:Prog | Where-Object { $_ -like '*|*' }).Count -ge 1) 'FAT32 klasörlü: ilerleme bildirildi'

$f16 = Job_RecoverScan @{ Source = (Img 'fat16d.img'); Mode = 'Quick' }
Test-DeletedList 'FAT16 klasörlü' $f16 $exp.fat16d.deleted { param($d) Get-StampTicks $exp.fat16d.stamp }
Assert-Eq $f16.Fs 'FAT16' 'FAT16 klasörlü: ad'
$f12 = Job_RecoverScan @{ Source = (Img 'fat12d.img'); Mode = 'Quick' }
Test-DeletedList 'FAT12 klasörlü' $f12 $exp.fat12d.deleted { param($d) Get-StampTicks $exp.fat12d.stamp }
Assert-Eq $f12.Fs 'FAT12' 'FAT12 klasörlü: ad'

$exd = Job_RecoverScan @{ Source = (Img 'exfatd.img'); Mode = 'Quick' }
Test-DeletedList 'exFAT klasörlü' $exd $exp.exfatd.deleted {
    param($d)
    if ($null -ne $d.utc) { return ([DateTime]::new(2024, 3, 1, 9, 0, 0, [DateTimeKind]::Utc)).ToFileTimeUtc() }
    if ($null -ne $d.stamp2) { return (Get-StampTicks @(2020, 1, 2, 3, 4, 6)) }
    return (Get-StampTicks @(2024, 3, 1, 12, 0, 0))
}
Assert-Eq $exd.Method 'exfat' 'exFAT klasörlü: yöntem'
foreach ($bad in @('canli.txt', 'Klasör', 'bozuk_toplam.txt', 'sifir.bin', 'Alt')) {
    Assert-True (@($exd.Items | Where-Object { $_.Name -ceq $bad }).Count -eq 0) ('exFAT klasörlü: listede olmamalı: ' + $bad)
}

# karma mod: kayıtlar + imza; kayıtlı dosyalar ikinci kez listelenmez
$fb = Job_RecoverScan @{ Source = (Img 'fat32d.img'); Mode = 'Both' }
Assert-Eq $fb.Stats.FromTable 10 'FAT32 klasörlü: karma: kayıttan 10'
foreach ($o in @($exp.fat32d.orphans)) { Assert-Eq @($fb.Items | Where-Object { $_.Kind -eq 'carve' -and $_.Offset -eq [long]$o.offset }).Count 1 ('FAT32 klasörlü: karma: sahipsiz ' + $o.name) }
foreach ($d in @($exp.fat32d.deleted | Where-Object { [int]$_.chance -ge 85 })) {
    Assert-Eq @($fb.Items | Where-Object { $_.Offset -eq [long]$d.offset }).Count 1 ('FAT32 klasörlü: karma: yinelenen yok: ' + $d.name)
}

# ---- FAT / exFAT: kurtarma, içerik ve tarih ----
$fdz = Job_RecoverFiles @{ Source = (Img 'fat32d.img'); Dest = (Join-Path $tmp 'hedef-fatd'); Items = @($fd.Items); KeepPaths = $true }
$fdBy = @{}
foreach ($row in @($fdz.Results)) { $fdBy[[string]$row.Name] = $row }
foreach ($d in @($exp.fat32d.deleted)) {
    $row = $fdBy[[string]$d.name]
    Assert-True ($null -ne $row) ('FAT32 klasörlü: sonuç satırı: ' + $d.name)
    if ($null -eq $row) { continue }
    if ($null -ne $d.sha -and [int]$d.chance -ge 85) {
        Assert-True ($row.Ok -eq $true) ($d.name + ': kaydedildi')
        if ($row.Ok -eq $true) {
            Assert-Eq (Get-Sha $row.Path) ([string]$d.sha) ($d.name + ': içerik özeti')
            Assert-Eq (Get-Item -LiteralPath $row.Path).LastWriteTimeUtc.ToFileTimeUtc() (Get-StampTicks $exp.fat32d.stamps.([string]$d.stamp)) ($d.name + ': tarih geri yazıldı')
            $rel = $row.Path.Substring($fdz.Dir.Length).TrimStart('/', '\')
            $wantRel = ([string]$d.path).Replace('\', $sep)
            if ($wantRel -ne '') { Assert-True ($rel.StartsWith($wantRel + $sep)) ($d.name + ': klasör yapısı (' + $rel + ')') } else { Assert-True (-not $rel.Contains($sep)) ($d.name + ': kökte (' + $rel + ')') }
        }
    }
}
$zil = $fdBy['_ZILDI.DAT']
Assert-True ($zil.Ok -ne $true -and $zil.Note -match 'sonradan başka bir dosyaya verilmiş') 'ezilmiş FAT dosyası kurtarılmaz, neden söylenir'
Assert-True (-not (Test-Path -LiteralPath (Join-Path $fdz.Dir '_ZILDI.DAT'))) 'ezilmiş FAT dosyasından kalıntı dosya yok'
# kısmen kullanılmış: ilk ve son küme özgün, ortadaki başkasının
$kis = $fdBy['_ISMI.BIN']
Assert-True ($kis.Ok -eq $true) '_ISMI.BIN: kısmen de olsa kaydedildi'
$kb = [System.IO.File]::ReadAllBytes($kis.Path)
$fimg = [System.IO.File]::ReadAllBytes((Img 'fat32d.img'))
$k0 = [long](@($exp.fat32d.deleted | Where-Object { $_.name -eq '_ISMI.BIN' })[0].offset)
$same0 = $true
for ($i = 0; $i -lt 4096; $i++) { if ($kb[$i] -ne $fimg[$k0 + $i]) { $same0 = $false; break } }
Assert-True $same0 '_ISMI.BIN: ilk küme özgün'
Assert-Eq $kb.Length 12188 '_ISMI.BIN: boyut korunur'
# sıfırlarla dolu baş: şans çok düşük, yine de istenirse sıfırlar yazılır; not durumu açıklar
$sf = $fdBy['_OSLUK.JPG']
Assert-True ($sf.Ok -eq $true -and $sf.Note -match 'sıfır') 'sıfır başlı dosya: kaydedilir ama not düşülür'

$exz = Job_RecoverFiles @{ Source = (Img 'exfatd.img'); Dest = (Join-Path $tmp 'hedef-exd'); Items = @($exd.Items); KeepPaths = $true }
$exBy = @{}
foreach ($row in @($exz.Results)) { $exBy[[string]$row.Name] = $row }
foreach ($d in @($exp.exfatd.deleted)) {
    $row = $exBy[[string]$d.name]
    Assert-True ($null -ne $row -and $row.Ok -eq $true) ('exFAT klasörlü: kaydedildi: ' + $d.name)
    if ($null -eq $row -or $row.Ok -ne $true) { continue }
    if ($null -ne $d.sha) { Assert-Eq (Get-Sha $row.Path) ([string]$d.sha) ('exFAT klasörlü: içerik: ' + $d.name) }
    $rel = $row.Path.Substring($exz.Dir.Length).TrimStart('/', '\')
    $wantRel = ([string]$d.path).Replace('\', $sep)
    if ($wantRel -ne '') { Assert-True ($rel.StartsWith($wantRel + $sep)) ('exFAT klasörlü: klasör yapısı: ' + $d.name + ' (' + $rel + ')') } else { Assert-True (-not $rel.Contains($sep)) ('exFAT klasörlü: kökte: ' + $d.name) }
}
$zt = $exBy['zaman.txt']
Assert-Eq (Get-Item -LiteralPath $zt.Path).LastWriteTimeUtc.ToString('yyyy-MM-dd HH:mm:ss') '2024-03-01 09:00:00' 'exFAT: saat dilimi farkı uygulanır (+03:00 -> UTC)'

# FAT16 / FAT12 klasörlü: kurtarma
foreach ($t in @(@('fat16d.img', $f16, $exp.fat16d), @('fat12d.img', $f12, $exp.fat12d))) {
    $zz = Job_RecoverFiles @{ Source = (Img $t[0]); Dest = (Join-Path $tmp ('hedef-' + $t[0])); Items = @($t[1].Items); KeepPaths = $true }
    Assert-True ($zz.Ok -eq $true -and $zz.Done -eq 3) ($t[0] + ': üç dosya kurtarıldı')
    foreach ($d in @($t[2].deleted)) { Assert-Eq @($zz.Results | Where-Object { $_.Ok -eq $true -and (Get-Sha $_.Path) -eq [string]$d.sha }).Count 1 ($t[0] + ': ' + $d.name + ' birebir') }
    Assert-True (@($zz.Results | Where-Object { $_.Path -like '*_OKUMAN*' }).Count -eq 1) ($t[0] + ': silinmiş alt klasör yolu korunur')
}

# ---- bayat FAT öğesi: tarama ile kurtarma arasında alan yeniden kullanılırsa reddedilir ----
$st = New-Object Mm.RcItem
$st.Kind = 'fat'; $st.Offset = [long](@($exp.fat32d.deleted | Where-Object { $_.name -eq '_ZILDI.DAT' })[0].offset); $st.Length = 4096; $st.Name = 'bayat.dat'
$st2 = New-Object Mm.RcItem
$st2.Kind = 'fat'; $st2.Offset = 100; $st2.Length = 4096; $st2.Name = 'hizasiz.dat'
$st3 = New-Object Mm.RcItem
$st3.Kind = 'fat'; $st3.Offset = 99999999L * 4096; $st3.Length = 4096; $st3.Name = 'disarida.dat'
$sz = Job_RecoverFiles @{ Source = (Img 'fat32d.img'); Dest = (Join-Path $tmp 'hedef-bayat'); Items = @($st, $st2, $st3) }
Assert-Eq $sz.Done 0 'bayat ya da geçersiz FAT öğeleri kaydedilmez'
Assert-Eq $sz.Failed 3 'bayat ya da geçersiz FAT öğeleri reddedilir'
Assert-Eq @(Get-ChildItem -LiteralPath $sz.Dir -Recurse -File | Where-Object { $_.Name -ne 'Kurtarma-Raporu.csv' }).Count 0 'bayat öğelerden kalıntı yok'

# ---- ext2/3/4: boş bloklarda imza taraması ----
foreach ($t in @(@('ext4', 'ext4', 4096), @('ext3', 'ext3', 4096), @('ext2k', 'ext2', 1024), @('ext4ro', 'ext4', 4096), @('ext4hi', 'ext4', 4096))) {
    Reset-Mocks
    $ee = $exp.($t[0])
    $er = Job_RecoverScan @{ Source = (Img ($t[0] + '.img')); Mode = 'Quick' }
    $lb = $t[1] + ' (' + [string]$t[2] + ' bayt blok)'
    Assert-True ($er.Ok -eq $true) ($lb + ': tarama')
    Assert-Eq $er.Fs $t[1] ($lb + ': ad')
    Assert-Eq $er.Method 'free' ($lb + ': yöntem')
    Assert-True ($er.Raw -ne $true) ($lb + ': ham mod değil')
    Assert-Eq $er.ClusterSize $t[2] ($lb + ': blok boyutu')
    Assert-Eq $er.Items.Count @($ee.items).Count ($lb + ': dosya sayısı')
    Assert-True (@($er.Items | Where-Object { $_.Offset -eq [long]$ee.live_offset }).Count -eq 0) ($lb + ': kullanımdaki dosya listelenmez')
    foreach ($c in @($ee.items)) {
        $m = @($er.Items | Where-Object { $_.Offset -eq [long]$c.offset })
        Assert-Eq $m.Count 1 ($lb + ': ' + $c.name + ' bulundu')
        if ($m.Count -eq 1) { Assert-Eq $m[0].Length ([long]$c.size) ($lb + ': ' + $c.name + ' uzunluk'); Assert-Eq $m[0].Ext ([string]$c.ext) ($lb + ': ' + $c.name + ' uzantı'); Assert-Eq $m[0].Kind 'carve' ($lb + ': tür') }
    }
    $ez = Job_RecoverFiles @{ Source = (Img ($t[0] + '.img')); Dest = (Join-Path $tmp ('hedef-' + $t[0])); Items = @($er.Items) }
    Assert-True ($ez.Ok -eq $true -and $ez.Done -eq 5) ($lb + ': kurtarma')
    foreach ($c in @($ee.items)) { Assert-Eq @($ez.Results | Where-Object { $_.Ok -eq $true -and (Get-Sha $_.Path) -eq [string]$c.sha }).Count 1 ($lb + ': ' + $c.name + ' birebir') }
}

# ---- tanınmayan biçimler, bozuk birimler: tüm alanda imza taraması ----
$names = @{ btrfs = 'Btrfs'; xfs = 'XFS'; apfs = 'APFS'; hfsplus = 'HFS+'; f2fs = 'F2FS'; lvm = 'LVM'; refs = 'ReFS' }
foreach ($k in @('btrfs', 'xfs', 'apfs', 'hfsplus', 'f2fs', 'lvm', 'refs')) {
    Reset-Mocks
    $sr = Job_RecoverScan @{ Source = (Img ('sniff_' + $k + '.img')); Mode = 'Quick' }
    Assert-True ($sr.Ok -eq $true) ($names[$k] + ': tarama yapılır')
    Assert-Eq $sr.Fs $names[$k] ($names[$k] + ': tanınır')
    Assert-True ($sr.Raw -eq $true -and $sr.Method -eq 'raw') ($names[$k] + ': ham mod')
    Assert-True ($sr.Note -match [regex]::Escape($names[$k])) ($names[$k] + ': açıklama biçimi söyler')
    Assert-Eq $sr.Items.Count 2 ($names[$k] + ': iki dosya')
    foreach ($c in @($exp.sniff.($k).items)) {
        $m = @($sr.Items | Where-Object { $_.Offset -eq [long]$c.offset })
        Assert-Eq $m.Count 1 ($names[$k] + ': ' + [string]$c.offset + ' bulundu')
        if ($m.Count -eq 1) { Assert-Eq $m[0].Length ([long]$c.size) ($names[$k] + ': uzunluk'); Assert-Eq $m[0].Chance 75 ($names[$k] + ': şans (silinmiş mi var mı bilinmez)') }
    }
    Assert-True (@($script:Logs | Where-Object { $_ -like 'WARN:*' + $names[$k] + '*' }).Count -ge 1) ($names[$k] + ': günlükte uyarı')
}
Reset-Mocks
$rw = Job_RecoverScan @{ Source = (Img 'raw.img'); Mode = 'Quick' }
Assert-True ($rw.Ok -eq $true -and $rw.Raw -eq $true -and $rw.Fs -eq 'Bilinmeyen' -and $rw.Items.Count -eq 3) 'biçimsiz imaj: üç dosya imzayla bulunur'
$rwz = Job_RecoverFiles @{ Source = (Img 'raw.img'); Dest = (Join-Path $tmp 'hedef-raw'); Items = @($rw.Items) }
foreach ($c in @($exp.rawimg.items)) { Assert-Eq @($rwz.Results | Where-Object { $_.Ok -eq $true -and (Get-Sha $_.Path) -eq [string]$c.sha }).Count 1 ('biçimsiz imaj: ' + [string]$c.offset + ' birebir') }
Assert-True (@($rwz.Results | Where-Object { $_.Path -like '*İmza taraması*' }).Count -eq 3) 'ham tarama sonuçları imza klasörüne gider'
$lk = Job_RecoverScan @{ Source = (Img 'luks.img'); Mode = 'Quick' }
Assert-True ($lk.Ok -ne $true -and $lk.Error -match 'LUKS' -and $lk.Error -match 'parola') 'LUKS: parolasız kurtarılamaz'
$nb = Job_RecoverScan @{ Source = (Img 'ntfs_bozuk.img'); Mode = 'Quick' }
Assert-True ($nb.Ok -eq $true -and $nb.Raw -eq $true -and $nb.Fs -eq 'NTFS') 'bozuk NTFS: ham taramaya düşer'
Assert-True ($nb.Note -match 'MFT konumu geçersiz') 'bozuk NTFS: neden söylenir'
foreach ($c in @($exp.ntfs.carve)) { Assert-Eq @($nb.Items | Where-Object { $_.Offset -eq [long]$c.offset -and $_.Length -eq [long]$c.size }).Count 1 ('bozuk NTFS: ' + $c.name + ' imzayla bulundu') }
$fbz = Job_RecoverScan @{ Source = (Img 'fat32_bozuk.img'); Mode = 'Quick' }
Assert-True ($fbz.Ok -eq $true -and $fbz.Raw -eq $true -and $fbz.Fs -eq 'FAT32' -and $fbz.Note -match 'önyükleme kaydı geçersiz') 'bozuk FAT32: ham taramaya düşer'
foreach ($o in @($exp.fat32d.orphans)) { Assert-Eq @($fbz.Items | Where-Object { $_.Offset -eq [long]$o.offset -and $_.Length -eq [long]$o.size }).Count 1 ('bozuk FAT32: ' + $o.name + ' imzayla bulundu') }

# ---- fiziksel disk ve sürücü adları ----
$dn = 0
foreach ($ok in @('PhysicalDrive0', 'physicaldrive12', '\\.\PhysicalDrive3', ' PhysicalDrive7 ')) { Assert-True ([Mm.RcEngine]::IsDiskSpec($ok)) ('disk adı: ' + $ok) }
foreach ($no in @('PhysicalDrive', 'PhysicalDriveX', 'PhysicalDrive12345', 'PhysicalDrive-1', 'Disk0', 'C:', '', 'E:\PhysicalDrive1')) { Assert-True (-not [Mm.RcEngine]::IsDiskSpec($no)) ('disk adı değil: ' + $no) }
Assert-True ([Mm.RcEngine]::DiskNumberOf('\\.\PhysicalDrive3', [ref]$dn) -and $dn -eq 3) 'disk numarası ayrıştırılır'
$sd = Resolve-RcSource 'PhysicalDrive2'
Assert-True ($sd.Ok -eq $true -and $sd.Kind -eq 'Disk' -and $sd.Source -eq 'PhysicalDrive2' -and $sd.DiskNumber -eq 2) 'kaynak: fiziksel disk'
$sd2 = Resolve-RcSource '\\.\PhysicalDrive11'
Assert-True ($sd2.Ok -eq $true -and $sd2.Kind -eq 'Disk' -and $sd2.DiskNumber -eq 11) 'kaynak: \\.\ ile fiziksel disk'
Assert-True ((Resolve-RcSource 'PhysicalDriveX').Ok -ne $true) 'kaynak: geçersiz disk adı imaj sayılır, bulunamaz'

# ---- güvenlik: hedef denetimleri ----
$src = Resolve-RcSource $ntfs
Assert-True ((Test-RcDestination $src '' 100) -match 'seçilmedi') 'hedef boş'
Assert-True ((Test-RcDestination $src 'goreli/klasor' 100) -match 'tam bir yol') 'göreli hedef reddedilir'
Assert-True ((Test-RcDestination $src (Join-Path $tmp 'tamam') 100) -eq '') 'uygun hedef'
Assert-True ((Test-RcDestination $src (Join-Path $tmp 'tamam') 1e18) -match 'yeterli boş yer yok') 'yer yetmiyor'
Assert-True ((Test-RcDestination $src '/proc/mm-deneme/klasor' 100) -match 'yazılamadı') 'yazılamayan hedef'
$fake = @{ Ok = $true; Kind = 'Drive'; Source = '/'; Letter = '/' }
Assert-True ((Test-RcDestination $fake (Join-Path $tmp 'ayni') 100) -match 'taranan .* sürücüsünde olamaz') 'taranan sürücüye yazma reddedilir'
$fake2 = @{ Ok = $true; Kind = 'Drive'; Source = 'Z:'; Letter = 'Z' }
Assert-True ((Test-RcDestination $fake2 (Join-Path $tmp 'baska') 100) -eq '') 'farklı sürücü kabul'
Reset-Mocks
$bad = Job_RecoverFiles @{ Source = $ntfs; Dest = '/proc/mm-deneme'; Items = $sel }
Assert-True ($bad.Ok -ne $true -and $bad.Error -match 'yazılamadı') 'yazılamayan hedefte işlem başlamaz'
Assert-True ($bad.Dir -eq '') 'klasör oluşturulmadı'
$none = Job_RecoverFiles @{ Source = $ntfs; Dest = (Join-Path $tmp 'bos'); Items = @() }
Assert-True ($none.Ok -ne $true -and $none.Error -match 'seçilmedi') 'seçim yok'
Assert-True (-not (Test-Path -LiteralPath (Join-Path $tmp 'bos'))) 'seçim yokken hedef oluşturulmaz'
$free1 = Join-Path $tmp 'ad.txt'
Set-Content -LiteralPath $free1 -Value 'x'
Assert-True ((Get-RcFreeName $free1) -ne $free1 -and (Get-RcFreeName $free1) -like '*ad (2).txt') 'dolu ad için yeni ad'
Assert-Eq (Get-RcFreeName (Join-Path $tmp 'yok-dosya.txt')) (Join-Path $tmp 'yok-dosya.txt') 'boş ad aynen kalır'

# ---- güvenlik: kötü niyetli ya da bayat öğeler ----
$evilDir = Join-Path $tmp 'kotu'
$e1 = New-Object Mm.RcItem
$e1.Kind = 'carve'; $e1.Offset = 600L * 4096; $e1.Length = 9000; $e1.Name = '..\..\evil.txt'; $e1.Ext = 'txt'
$e2 = New-Object Mm.RcItem
$e2.Kind = 'mft'; $e2.Rec = 48; $e2.Length = 364; $e2.Name = 'notlar.txt'; $e2.Path = '..\..\..\tmp\x'; $e2.Ext = 'txt'
$e3 = New-Object Mm.RcItem
$e3.Kind = 'mft'; $e3.Rec = 48; $e3.Length = 364; $e3.Name = 'baska.txt'
$e4 = New-Object Mm.RcItem
$e4.Kind = 'mft'; $e4.Rec = 43; $e4.Length = 380; $e4.Name = 'keep.txt'
$e5 = New-Object Mm.RcItem
$e5.Kind = 'mft'; $e5.Rec = 9999; $e5.Length = 10; $e5.Name = 'yok.txt'
Reset-Mocks
$ev = Job_RecoverFiles @{ Source = $ntfs; Dest = $evilDir; Items = @($e1, $e2, $e3, $e4, $e5); KeepPaths = $true }
Assert-Eq $ev.Done 2 'yalnızca geçerli iki öğe kaydedildi'
Assert-Eq $ev.Failed 3 'bayat ve geçersiz üç öğe reddedildi'
foreach ($row in @($ev.Results | Where-Object { $_.Ok -eq $true })) {
    Assert-True ([System.IO.Path]::GetFullPath($row.Path).StartsWith([System.IO.Path]::GetFullPath($ev.Dir))) ('kaçış yok: ' + $row.Path)
}
Assert-True (-not (Test-Path -LiteralPath (Join-Path $tmp 'evil.txt')) -and -not (Test-Path -LiteralPath '/tmp/x')) 'hedef dışına dosya yazılmadı'
$notes = @($ev.Results | Where-Object { $_.Ok -ne $true } | ForEach-Object { [string]$_.Note })
Assert-True (@($notes | Where-Object { $_ -match 'yeniden kullanılmış' }).Count -ge 2) 'kayıt yeniden kullanılmış uyarısı'
Assert-Eq @(Get-ChildItem -LiteralPath $ev.Dir -Recurse -File | Where-Object { $_.Length -eq 0 }).Count 0 'boş kalıntı dosya yok'

# ---- iptal: kopyalama sırasında ----
Reset-Mocks
$script:CancelAfter = 1
$cx = Job_RecoverFiles @{ Source = $ntfs; Dest = (Join-Path $tmp 'iptal'); Items = @($sel[0], $sel[1], $sel[2]) }
Assert-True ($cx.Canceled -eq $true) 'kopyalama iptali'
Assert-True ($cx.Ok -ne $true) 'iptalde başarılı sayılmaz'
Assert-Eq @(Get-ChildItem -LiteralPath $cx.Dir -Recurse -File | Where-Object { $_.Name -ne 'Kurtarma-Raporu.csv' }).Count 0 'iptalde yarım dosya kalmaz'
Reset-Mocks

# ---- kaynak imajlara dokunulmadı ----
foreach ($f in @(Get-ChildItem -LiteralPath $imgDir -Filter '*.img')) {
    Assert-Eq ((Get-Sha $f.FullName) + '|' + $f.LastWriteTimeUtc.Ticks) $before[$f.Name] ('imaj değişmedi: ' + $f.Name)
}

# ---- kaynak metni: yazma yok ----
$ext = Join-Path $script:TestDir 'Eklenti'
$text = [System.IO.File]::ReadAllText((Join-Path $ext 'Kurtarma.ps1'), [System.Text.Encoding]::UTF8)
$cs = $text.Substring($text.IndexOf("@'") + 2, $text.IndexOf("`n'@") - $text.IndexOf("@'") - 2)
Assert-True ($cs.Length -gt 40000) 'C# gövdesi alındı'
foreach ($pat in @('FileAccess\.Write', 'FileAccess\.ReadWrite', '0x40000000', 'GENERIC_WRITE', 'FileMode\.Create', 'FileMode\.Append', 'FileMode\.OpenOrCreate', 'FileMode\.Truncate', 'SetLength', 'File\.Delete', 'Directory\.Delete', 'File\.Move', 'WriteFile', 'FlushFileBuffers', 'LockFile', 'FSCTL', 'IOCTL_DISK_(SET|FORMAT|DELETE|CREATE|UPDATE|GROW|VERIFY)')) {
    Assert-True ($cs -notmatch $pat) ('C# kodunda yok: ' + $pat)
}
Assert-True ($cs -match '0x80000000u') 'ham erişim yalnızca okuma ister'
Assert-Eq ([regex]::Matches($cs, 'CreateFile\(').Count) 3 'ham açma çağrıları: bildirim + sürücü + fiziksel disk'
foreach ($m in [regex]::Matches($cs, 'CreateFile\([^;]*;')) { if ($m.Value -notmatch 'string name, uint access') { Assert-True ($m.Value -match '0x80000000u') ('her ham açma yalnızca okuma ister: ' + $m.Value.Substring(0, [math]::Min(60, $m.Value.Length))) } }
Assert-Eq ([regex]::Matches($cs, 'DeviceIoControl').Count) 2 'DeviceIoControl: bir bildirim ve bir çağrı'
Assert-True ($cs -match 'IoctlDiskGetLengthInfo = 0x0007405C') 'tek denetim kodu: disk uzunluğu sorgusu'
Assert-Eq ([regex]::Matches($cs, 'DeviceIoControl\(h, ').Count) 1 'DeviceIoControl yalnızca uzunluk sorgusunda çağrılır'
Assert-True ($cs -match 'FileAccess\.Read') 'imaj okuma modu'
Assert-True ($text -notmatch [string][char]0x2019) 'eklentide tipografik kesme işareti yok'
Assert-True (($text -replace '[\x00-\x7F]', '').Length -gt 0) 'eklenti UTF-8 Türkçe metin içerir'
$nonAsciiStrings = 0
foreach ($m in [regex]::Matches($cs, '"(?:\\.|[^"\\\r\n])*"')) { if ($m.Value -match '[^\x00-\x7F]') { $nonAsciiStrings++ } }
Assert-Eq $nonAsciiStrings 0 'C# dizgilerinde ASCII dışı karakter yok (kaçışlı)'
Assert-True ($text -notmatch 'Remove-Item|\[System\.IO\.File\]::Delete\(\$Src|Format-Volume|Clear-Disk|Remove-Partition|diskpart|\bformat\.com') 'yıkıcı komut yok'
Assert-True ($text -match 'Test-RcDestination') 'hedef denetimi var'

Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
Show-Result
