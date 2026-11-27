. "$PSScriptRoot/lib.ps1"
# Disk silme eklentisi (Eklenti\DiskSilme.ps1): boş alan temizleme işi, kanarya doğrulaması, TRIM ve yardımcı işlevler.
# Gerçek diske dokunulmaz: geçici klasör, sahte birim ve geçici imaj dosyası kullanılır.
Import-Fn 'Format-Size', 'Format-Duration', 'Get-WipeMethodKey', 'Get-WipeModes', 'Get-WipeMethodName', 'Get-WipeReserve', 'Get-WipeProgressLabel', 'Format-WipeEta'
[void](Import-Ext 'DiskSilme')

$script:Logs = New-Object System.Collections.ArrayList
$script:Progress = New-Object System.Collections.ArrayList
$script:CancelAfter = -1
$script:CancelCalls = 0
function Write-WhLog([string]$Message, [string]$Level = 'INFO') { [void]$script:Logs.Add($Level + ': ' + $Message) }
function Set-JobProgress($Done, $Total, [string]$Label = '') { [void]$script:Progress.Add(@($Done, $Total, $Label)) }
function Test-JobCancel { $script:CancelCalls++; return ($script:CancelAfter -ge 0 -and $script:CancelCalls -gt $script:CancelAfter) }
function Log-Has([string]$Needle) { foreach ($l in $script:Logs) { if ($l.Contains($Needle)) { return $true } }; return $false }

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('mm-wipejobs-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
[void][System.IO.Directory]::CreateDirectory($tmp)
$MiB = 1048576

# =====================================================================
#  1) küçük yardımcılar
# =====================================================================
Assert-Eq (Initialize-MmWipe) '' 'motor derleniyor'
try { throw (New-Object System.InvalidOperationException -ArgumentList 'dış hata', (New-Object System.ArgumentException -ArgumentList 'iç hata')) } catch { $et = Get-WipeErrorText $_ }
Assert-Eq $et 'iç hata' 'hata metni: en içteki ileti'
try { throw 'düz hata' } catch { $et2 = Get-WipeErrorText $_ }
Assert-Eq $et2 'düz hata' 'hata metni: düz iletiler'

$ex = ConvertTo-WipeExtents @(@{ Start = 4096; Length = 8192; Tag = 'a'; StreamPos = 100 }, $null, @{ Start = [double]1048576; Length = [double]512 })
Assert-Eq $ex.Count 2 'aralıklar: boş öğe atlanır'
Assert-True ($ex[0].Start -eq 4096 -and $ex[0].Length -eq 8192 -and $ex[0].Tag -eq 'a' -and $ex[0].StreamPos -eq 100) 'aralıklar: alanlar aktarılır'
Assert-True ($ex[1].Start -eq 1048576 -and $ex[1].Length -eq 512) 'aralıklar: double değerler çevrilir'
Assert-Eq (ConvertTo-WipeExtents @()).Count 0 'aralıklar: boş giriş'

$script:Progress.Clear()
$cb = New-WipeCallback 'Disk 4 siliniyor' 1000 0
Assert-True ($cb.Invoke('Yazılıyor', 500, 1000) -eq $true) 'geri çağrı: iptal yokken devam'
$last = $script:Progress[$script:Progress.Count - 1]
Assert-True ($last[0] -eq 500 -and $last[1] -eq 1000 -and $last[2] -match 'Disk 4 siliniyor' -and $last[2] -match '%50') 'geri çağrı: binde 500 ve etiket'
$cb2 = New-WipeCallback 'Disk 4' 2000 1000
[void]$cb2.Invoke('Yazılıyor', 500, 2000)
Assert-Eq $script:Progress[$script:Progress.Count - 1][0] 750 'geri çağrı: taban eklenir'
$script:CancelAfter = 0; $script:CancelCalls = 0
Assert-True ($cb.Invoke('Yazılıyor', 600, 1000) -eq $false) 'geri çağrı: iptal edilince false döner'
$script:CancelAfter = -1; $script:CancelCalls = 0

# gerçek birim bilgisi (Linux’ta da çalışır)
$gv = Get-WipeVolume $tmp
Assert-True ($gv.Total -gt 0 -and $gv.Free -ge 0 -and $gv.Free -le $gv.Total) 'birim bilgisi okunur'
$gv0 = Get-WipeVolume (Join-Path $tmp 'yok/yok')
Assert-True ($gv0.Total -ge 0) 'birim bilgisi: olmayan yolda hata vermez'

# dosya konumu sorgusu Windows dışında boş döner
$probeFile = Join-Path $tmp 'sorgu.bin'
[System.IO.File]::WriteAllBytes($probeFile, (New-Object byte[] 65536))
$fe = Get-WipeFileExtents $probeFile
Assert-True ($fe.Cluster -eq 0 -and @($fe.Extents).Count -eq 0) 'konum sorgusu: Windows dışında boş'
Remove-Item -LiteralPath $probeFile -Force

# eski geçici klasörler
$lr = Join-Path $tmp 'lr'
[void][System.IO.Directory]::CreateDirectory($lr)
[void][System.IO.Directory]::CreateDirectory((Join-Path $lr '.mm-bosalan-eski'))
Set-Content -LiteralPath (Join-Path $lr '.mm-bosalan-eski/x.tmp') -Value 'x'
[void][System.IO.Directory]::CreateDirectory((Join-Path $lr 'veri'))
Set-Content -LiteralPath (Join-Path $lr 'veri/a.txt') -Value 'a'
[void][System.IO.Directory]::CreateDirectory((Join-Path $lr '.mm-baska'))
Assert-Eq (Remove-WipeLeftovers $lr) 1 'eski klasörler: yalnızca eşleşen kaldırılır'
Assert-True (-not (Test-Path -LiteralPath (Join-Path $lr '.mm-bosalan-eski'))) 'eski klasörler: geçici klasör silindi'
Assert-True ((Test-Path -LiteralPath (Join-Path $lr 'veri/a.txt')) -and (Test-Path -LiteralPath (Join-Path $lr '.mm-baska'))) 'eski klasörler: diğerleri korunur'
Assert-Eq (Remove-WipeLeftovers (Join-Path $tmp 'yok-klasor')) 0 'eski klasörler: olmayan klasörde hata yok'

# =====================================================================
#  2) TRIM durumu ve gönderimi (sahte fsutil ve Optimize-Volume)
# =====================================================================
$script:FsutilOut = @()
$script:FsutilThrow = $false
function fsutil.exe { if ($script:FsutilThrow) { throw 'fsutil yok' }; return $script:FsutilOut }
$script:OptCalls = New-Object System.Collections.ArrayList
$script:OptFail = ''
function Optimize-Volume { [CmdletBinding()] param([string]$DriveLetter, [switch]$ReTrim) [void]$script:OptCalls.Add($DriveLetter + ':' + [string]$ReTrim.IsPresent); if ($script:OptFail -ne '') { throw $script:OptFail } }

$script:FsutilOut = @('NTFS DisableDeleteNotify = 0  (Etkin)', 'ReFS DisableDeleteNotify = 0  (Etkin)')
Assert-Eq (Get-WipeTrimState) 'on' 'TRIM durumu: açık'
$script:FsutilOut = @('NTFS DisableDeleteNotify = 1', 'ReFS DisableDeleteNotify = 0')
Assert-Eq (Get-WipeTrimState) 'off' 'TRIM durumu: NTFS için kapalı'
$script:FsutilOut = @('DisableDeleteNotify = 0')
Assert-Eq (Get-WipeTrimState) 'on' 'TRIM durumu: dosya sistemi adı olmadan'
$script:FsutilOut = @('beklenmeyen çıktı')
Assert-Eq (Get-WipeTrimState) 'unknown' 'TRIM durumu: okunamadı'
$script:FsutilThrow = $true
Assert-Eq (Get-WipeTrimState) 'unknown' 'TRIM durumu: komut yoksa bilinmiyor'
$script:FsutilThrow = $false

$script:FsutilOut = @('NTFS DisableDeleteNotify = 0')
$t1 = Invoke-WipeTrim ' d:\ '
Assert-True ($t1.Ok -eq $true -and $t1.Error -eq '' -and $t1.Note -eq '') 'TRIM gönder: başarılı'
Assert-Eq $script:OptCalls[0] 'D:True' 'TRIM gönder: sürücü harfi ve ReTrim'
$script:FsutilOut = @('NTFS DisableDeleteNotify = 1')
$t2 = Invoke-WipeTrim 'E:'
Assert-True ($t2.Ok -eq $true -and $t2.Note -match 'TRIM\) kapalı') 'TRIM gönder: Windows bildirimleri kapalıysa not düşer'
$script:OptFail = 'Sürücü desteklemiyor'
$t3 = Invoke-WipeTrim 'F:'
Assert-True ($t3.Ok -eq $false -and $t3.Error -eq 'Sürücü desteklemiyor') 'TRIM gönder: hata iletilir'
$script:OptFail = ''

# =====================================================================
#  3) sahte birim (boş alan işi için)
# =====================================================================
$script:Cap = [double](20 * $MiB)
$script:FakeTotal = [double](100 * $MiB)
$script:Frozen = $false
$script:MaxFiles = 0
$script:Samples = @{}
$script:Kinds = New-Object System.Collections.ArrayList
$script:Gen = 0
$script:VolImg = Join-Path $tmp 'sahte-birim.img'
$script:CanaryMode = 'ok'
$script:NextOff = [long]0
$script:ClobberAt = [double]0
$script:Clobbered = $false
$script:ImgRead = 0

function Get-Kind([byte[]]$B) {
    $z = 0; $f = 0
    foreach ($x in $B) { if ($x -eq 0) { $z++ } elseif ($x -eq 255) { $f++ } }
    if ($z -eq $B.Length) { return 'zero' }
    if ($f -eq $B.Length) { return 'ff' }
    return 'rand'
}
function Get-WipeVolume([string]$Root) {
    $used = [double]0
    $n = 0
    foreach ($f in @(Get-ChildItem -LiteralPath $Root -Recurse -File -Force -ErrorAction SilentlyContinue)) {
        $used += $f.Length
        $n++
        $key = [string]$script:Gen + ':' + $f.Name
        if ($f.Name -like 'bos-*' -and $f.Length -ge 4096 -and -not $script:Samples.ContainsKey($key)) {
            try {
                $fs = [System.IO.File]::OpenRead($f.FullName)
                $b = New-Object byte[] 4096
                [void]$fs.Read($b, 0, 4096)
                $fs.Dispose()
                $k = Get-Kind $b
                $script:Samples[$key] = $k
                [void]$script:Kinds.Add($k)
            } catch { }
        }
    }
    if ($n -eq 0) { $script:Gen++ }
    if ($n -gt $script:MaxFiles) { $script:MaxFiles = $n }
    if ($script:Frozen) { $used = [double]0 }
    if ($script:ClobberAt -gt 0 -and $used -ge $script:ClobberAt -and -not $script:Clobbered -and $script:NextOff -gt 0) {
        $script:Clobbered = $true
        $fs2 = [System.IO.File]::Open($script:VolImg, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
        $junk = New-Object byte[] ([int]$script:NextOff)
        for ($i = 0; $i -lt $junk.Length; $i++) { $junk[$i] = 238 }
        $fs2.Write($junk, 0, $junk.Length)
        $fs2.Dispose()
    }
    return @{ Free = [double]($script:Cap - $used); Total = $script:FakeTotal }
}
# kanarya dosyasının "birimdeki konumu": içeriği sahte birim imajına kopyalanır (silinmiş ama silinmemiş veri gibi)
function Get-WipeFileExtents([string]$Path) {
    if ($script:CanaryMode -eq 'none') { return @{ Cluster = [long]0; Extents = @() } }
    $len = (Get-Item -LiteralPath $Path).Length
    $off = $script:NextOff
    $script:NextOff += [long]([math]::Ceiling($len / 4096.0) * 4096)
    if ($script:CanaryMode -ne 'trimmed') {
        $data = [System.IO.File]::ReadAllBytes($Path)
        $fs = [System.IO.File]::Open($script:VolImg, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
        [void]$fs.Seek($off, [System.IO.SeekOrigin]::Begin)
        $fs.Write($data, 0, $data.Length)
        $fs.Dispose()
    }
    return @{ Cluster = [long]4096; Extents = @(@{ Start = [long]$off; Length = [long]$len }) }
}
function Open-WipeRead([string]$Spec) { $script:ImgRead++; return [Mm.WipeTarget]::Open($script:VolImg, $false) }
$script:TrimCalls = New-Object System.Collections.ArrayList
$script:TrimOk = $true
function Invoke-WipeTrim([string]$Letter) { [void]$script:TrimCalls.Add($Letter); if ($script:TrimOk) { return @{ Ok = $true; Error = ''; Note = '' } }; return @{ Ok = $false; Error = 'TRIM reddedildi (sahte)'; Note = '' } }

function Reset-Wipe {
    $script:Logs.Clear(); $script:Progress.Clear(); $script:CancelAfter = -1; $script:CancelCalls = 0; $script:Frozen = $false; $script:MaxFiles = 0
    $script:Samples = @{}; $script:Kinds.Clear(); $script:Gen = 0; $script:CanaryMode = 'ok'; $script:NextOff = [long]0; $script:ClobberAt = [double]0; $script:Clobbered = $false
    $script:ImgRead = 0; $script:TrimCalls.Clear(); $script:TrimOk = $true
    [System.IO.File]::WriteAllBytes($script:VolImg, (New-Object byte[] (4 * $MiB)))
}
function New-Root { $r = Join-Path $tmp ('v' + [guid]::NewGuid().ToString('N').Substring(0, 6)); [void][System.IO.Directory]::CreateDirectory($r); return $r }
function Count-Files([string]$Root) { return @(Get-ChildItem -LiteralPath $Root -Recurse -Force -ErrorAction SilentlyContinue).Count }
function Kinds-Unique { return (@($script:Kinds | Select-Object -Unique) -join ',') }

# =====================================================================
#  4) boş alan işi: normal çalışma, dosya sınırı, iptal, hatalar
# =====================================================================
Reset-Wipe
$root = New-Root
Set-Content -LiteralPath (Join-Path $root 'onemli.txt') -Value 'dokunulmamali'
$script:Cap = [double](20 * $MiB) + 14
$r = Job_WipeFree @{ Root = $root; Reserve = [double](2 * $MiB); FileMax = [long](8 * $MiB); Canary = $false }
Assert-True ($r.Ok -eq $true) 'boş alan: başarılı'
Assert-Eq $r.Written ([double](18 * $MiB)) 'boş alan: yazılan miktar = boş alan - pay'
Assert-Eq $r.Reserve ([double](2 * $MiB)) 'boş alan: pay bildirilir'
Assert-True ($r.Canceled -eq $false -and $r.Error -eq '') 'boş alan: iptal ve hata yok'
Assert-True ($r.Method -eq 'random' -and $r.Passes -eq 1 -and $r.Kind -eq 'Free') 'boş alan: varsayılan yöntem tek geçiş rastgele'
Assert-True ($null -eq $r.Canary -and $null -eq $r.Verdict -and $null -eq $r.Trim) 'boş alan: kanarya ve TRIM istenmedi'
Assert-Eq (Get-Content -LiteralPath (Join-Path $root 'onemli.txt') -Raw).Trim() 'dokunulmamali' 'boş alan: var olan dosya değişmedi'
Assert-Eq (Count-Files $root) 1 'boş alan: geçici klasör ve dosyalar silindi'
Assert-True ($script:MaxFiles -ge 2) 'boş alan: geçici dosyalar oluştu'
Assert-Eq (Kinds-Unique) 'rand' 'boş alan: varsayılan yöntem rastgele veri yazar'
Assert-True ((Log-Has 'BOŞ ALAN TEMİZLEME') -and (Log-Has 'bitti')) 'boş alan: günlük yazıldı'
Assert-Eq $script:ImgRead 0 'boş alan: kanarya kapalıyken birim okunmaz'

Reset-Wipe
$root = New-Root
$script:Cap = [double](20 * $MiB)
$r = Job_WipeFree @{ Root = $root; Reserve = [double](2 * $MiB); FileMax = [long](5 * $MiB); Canary = $false }
Assert-True ($r.Ok -eq $true -and $r.Written -eq [double](18 * $MiB)) 'dosya sınırı: parçalı yazma tamam'
Assert-True ($script:MaxFiles -ge 4) 'dosya sınırı: birden çok geçici dosya kullanıldı'
Assert-True ($script:Samples.Count -ge 3) 'dosya sınırı: kapanan dosyalardan örnek alındı'
Assert-Eq (Count-Files $root) 0 'dosya sınırı: her şey temizlendi'

# yöntemler
Reset-Wipe
$root = New-Root
$script:Cap = [double](20 * $MiB)
$r = Job_WipeFree @{ Root = $root; Reserve = [double](2 * $MiB); Method = 'zero'; FileMax = [long](8 * $MiB); Canary = $false }
Assert-True ($r.Ok -eq $true -and $r.Method -eq 'zero' -and $r.Passes -eq 1) 'sıfır yöntemi: tek geçiş'
Assert-Eq (Kinds-Unique) 'zero' 'sıfır yöntemi: dosyalar sıfırla dolu'
Reset-Wipe
$root = New-Root
$script:Cap = [double](34 * $MiB)
$r = Job_WipeFree @{ Root = $root; Reserve = [double](2 * $MiB); Method = 'dod3'; FileMax = [long](8 * $MiB); Canary = $false }
Assert-True ($r.Ok -eq $true -and $r.Method -eq 'dod3' -and $r.Passes -eq 3) 'üç geçiş: yöntem ve geçiş sayısı'
Assert-Eq $r.Written ([double](3 * 32 * $MiB)) 'üç geçiş: yazılan miktar üç katı'
Assert-Eq (Kinds-Unique) 'zero,ff,rand' 'üç geçiş: sıfır, bir, rastgele sırasıyla'
Assert-Eq (Count-Files $root) 0 'üç geçiş: temizlendi'
$labels = ($script:Progress | ForEach-Object { [string]$_[2] }) -join '|'
Assert-True ($labels -match '1/3\. geçiş' -and $labels -match '3/3\. geçiş') 'üç geçiş: ilerleme etiketinde geçiş sayısı'
Assert-True ($script:Progress.Count -ge 3 -and $script:Progress[$script:Progress.Count - 1][0] -le 1000) 'üç geçiş: ilerleme binde 1000 değerini aşmaz'
Assert-True ((Log-Has '1. geçiş bitti') -and (Log-Has '3. geçiş bitti')) 'üç geçiş: her geçiş günlükte'
Reset-Wipe
$root = New-Root
$script:Cap = [double](20 * $MiB)
$r = Job_WipeFree @{ Root = $root; Reserve = [double](2 * $MiB); Method = 'random3'; FileMax = [long](8 * $MiB); Canary = $false }
Assert-True ($r.Ok -eq $true -and $r.Passes -eq 3 -and (Kinds-Unique) -eq 'rand') 'random3: üç geçiş rastgele'
Reset-Wipe
$root = New-Root
$script:Cap = [double](20 * $MiB)
$r = Job_WipeFree @{ Root = $root; Reserve = [double](2 * $MiB); Method = 'gutmann'; Canary = $false }
Assert-True ($r.Method -eq 'random' -and $r.Passes -eq 1) 'bilinmeyen yöntem varsayılana döner'

# iptal
Reset-Wipe
$root = New-Root
$script:Cap = [double](40 * $MiB)
$script:CancelAfter = 3
$r = Job_WipeFree @{ Root = $root; Reserve = [double](2 * $MiB); Canary = $false; Trim = $true; VolSpec = 'X:' }
Assert-True ($r.Canceled -eq $true -and $r.Ok -eq $false) 'iptal: bildirildi'
Assert-True ($r.Written -gt 0 -and $r.Written -lt [double](38 * $MiB)) 'iptal: kısmen yazıldı'
Assert-Eq (Count-Files $root) 0 'iptal: geçici dosyalar silindi'
Assert-True (Log-Has 'İptal edildi') 'iptal: günlüğe yazıldı'
Assert-Eq $script:TrimCalls.Count 0 'iptal: TRIM gönderilmez'

# yetersiz alan, azalmayan boş alan
Reset-Wipe
$root = New-Root
$script:Cap = [double](1 * $MiB)
$r = Job_WipeFree @{ Root = $root; Reserve = [double](2 * $MiB) }
Assert-True ($r.Ok -eq $false -and $r.Error -match 'yeterli boş alan yok') 'yetersiz alan: işlem başlamaz'
Assert-Eq (Count-Files $root) 0 'yetersiz alan: hiçbir şey oluşturulmadı'
Reset-Wipe
$root = New-Root
$script:Cap = [double](64 * $MiB)
$script:Frozen = $true
$r = Job_WipeFree @{ Root = $root; Reserve = [double](2 * $MiB); StallBytes = [double](8 * $MiB); Canary = $false; Trim = $true; VolSpec = 'X:' }
Assert-True ($r.Ok -eq $false -and $r.Error -match 'beklendiği gibi azalmıyor') 'azalmayan alan: durur'
Assert-True ($r.Written -ge [double](8 * $MiB) -and $r.Written -le [double](16 * $MiB)) 'azalmayan alan: sınırlı yazıldı'
Assert-Eq (Count-Files $root) 0 'azalmayan alan: geçici dosyalar silindi'
Assert-Eq $script:TrimCalls.Count 0 'azalmayan alan: TRIM gönderilmez'
$script:Frozen = $false

Reset-Wipe
$r = Job_WipeFree @{ Drive = 'zz' }
Assert-True ($r.Ok -eq $false -and $r.Error -match 'Geçerli bir sürücü') 'geçersiz sürücü'
$r = Job_WipeFree @{ Drive = '' }
Assert-True ($r.Ok -eq $false -and $r.Error -match 'Geçerli bir sürücü') 'boş sürücü'
$r = Job_WipeFree @{ Drive = 'Q:' }
Assert-True ($r.Ok -eq $false -and $r.Error -match 'bulunamadı') 'olmayan sürücü'
$r = Job_WipeFree @{ Root = (Join-Path $tmp 'yok-klasor') }
Assert-True ($r.Ok -eq $false -and $r.Error -match 'bulunamadı') 'olmayan klasör'

# eski geçici klasör varken de çalışır
Reset-Wipe
$root = New-Root
[void][System.IO.Directory]::CreateDirectory((Join-Path $root '.mm-bosalan-eski2'))
[void][System.IO.Directory]::CreateDirectory((Join-Path $root 'veri'))
Set-Content -LiteralPath (Join-Path $root 'veri/a.txt') -Value 'a'
$script:Cap = [double](8 * $MiB)
$r = Job_WipeFree @{ Root = $root; Reserve = [double](1 * $MiB); Canary = $false }
Assert-True ($r.Ok -eq $true) 'eski klasör varken de çalışır'
Assert-True (-not (Test-Path -LiteralPath (Join-Path $root '.mm-bosalan-eski2'))) 'çalışma başında eski klasör temizlenir'
Assert-True (Test-Path -LiteralPath (Join-Path $root 'veri/a.txt')) 'özgün dosyalar duruyor'

# =====================================================================
#  5) kanarya doğrulaması
# =====================================================================
# 5a) eski veri silinmiş ve temizlik onun üstüne yazmış: "doğrulandı"
Reset-Wipe
$root = New-Root
$script:Cap = [double](40 * $MiB)
$script:ClobberAt = [double](4 * $MiB)
$r = Job_WipeFree @{ Root = $root; Reserve = [double](2 * $MiB); VolSpec = 'X:' }
Assert-True ($r.Ok -eq $true) 'kanarya: iş başarılı'
Assert-True ($null -ne $r.Canary -and $r.Canary.Files -eq 6) 'kanarya: altı test dosyası'
Assert-True ($r.Canary.Pre.Checked -eq $true -and $r.Canary.Pre.Same -gt 0 -and $r.Canary.Pre.Same -eq $r.Canary.Pre.Units) 'kanarya: temizlikten önce silinmiş veri okunabiliyordu'
Assert-True ($r.Canary.Post.Checked -eq $true -and $r.Canary.Post.Same -eq 0 -and $r.Canary.Post.Changed -gt 0) 'kanarya: temizlikten sonra okunamıyor'
Assert-True ($r.Verdict.Level -eq 'ok' -and $r.Verdict.Text -match 'Doğrulandı') 'kanarya: karar “doğrulandı”'
Assert-Eq $script:ImgRead 2 'kanarya: birim iki kez okundu (önce, sonra)'
Assert-Eq (Count-Files $root) 0 'kanarya: kanarya dosyaları ve geçici klasör silindi'
Assert-True (Log-Has 'Kanarya: 6 test dosyası') 'kanarya: günlüğe yazıldı'
Assert-True (Log-Has 'Doğrulama: Doğrulandı') 'kanarya: sonuç günlükte'

# 5b) temizlik o konumlara ulaşmadı: uyarı (iş yine başarılı)
Reset-Wipe
$root = New-Root
$script:Cap = [double](40 * $MiB)
$r = Job_WipeFree @{ Root = $root; Reserve = [double](2 * $MiB); VolSpec = 'X:' }
Assert-True ($r.Ok -eq $true -and $r.Verdict.Level -eq 'warn' -and $r.Verdict.Text -match 'hâlâ okunabiliyor|sonra da okunabiliyor') 'kanarya: eski veri kalmışsa uyarı'
Assert-True ($r.Canary.Post.Same -eq $r.Canary.Pre.Same) 'kanarya: kalan birim sayısı doğru'
Assert-True (Log-Has 'WARN: Doğrulama') 'kanarya: uyarı seviyesiyle günlüğe yazıldı'

# 5c) veri temizlikten önce de okunamıyordu (TRIM benzeri): bilgi
Reset-Wipe
$root = New-Root
$script:Cap = [double](40 * $MiB)
$script:CanaryMode = 'trimmed'
$r = Job_WipeFree @{ Root = $root; Reserve = [double](2 * $MiB); VolSpec = 'X:' }
Assert-True ($r.Ok -eq $true -and $r.Verdict.Level -eq 'info' -and $r.Verdict.Text -match 'TRIM') 'kanarya: veri baştan okunamıyorsa bilgi'
Assert-True ($r.Canary.Pre.Same -eq 0 -and $r.Canary.Pre.Zeroed -gt 0) 'kanarya: ön okuma sıfır gördü'

# 5d) konumlar okunamadı: doğrulama yok
Reset-Wipe
$root = New-Root
$script:Cap = [double](40 * $MiB)
$script:CanaryMode = 'none'
$r = Job_WipeFree @{ Root = $root; Reserve = [double](2 * $MiB); VolSpec = 'X:' }
Assert-True ($r.Ok -eq $true -and $null -eq $r.Canary -and $null -eq $r.Verdict) 'kanarya: konum yoksa doğrulama yapılmaz'
Assert-True (Log-Has 'dosya konumları okunamadı') 'kanarya: neden günlükte'
Assert-Eq $script:ImgRead 0 'kanarya: konum yoksa birim okunmaz'

# 5e) küçük boş alanda ve kapalıyken kanarya çalışmaz
Reset-Wipe
$root = New-Root
$script:Cap = [double](10 * $MiB)
$r = Job_WipeFree @{ Root = $root; Reserve = [double](2 * $MiB); VolSpec = 'X:' }
Assert-True ($r.Ok -eq $true -and $null -eq $r.Canary) 'kanarya: 16 MB altındaki boş alanda yapılmaz'
Reset-Wipe
$root = New-Root
$script:Cap = [double](40 * $MiB)
$r = Job_WipeFree @{ Root = $root; Reserve = [double](2 * $MiB); VolSpec = 'X:'; Canary = $false }
Assert-True ($r.Ok -eq $true -and $null -eq $r.Canary -and $script:ImgRead -eq 0) 'kanarya: kapatılınca yapılmaz'
Reset-Wipe
$root = New-Root
$script:Cap = [double](40 * $MiB)
$r = Job_WipeFree @{ Root = $root; Reserve = [double](2 * $MiB) }
Assert-True ($r.Ok -eq $true -and $null -eq $r.Canary) 'kanarya: sürücü harfi bilinmiyorsa yapılmaz (klasör yolu)'

# 5f) iptalde kanarya sonucu hesaplanmaz
Reset-Wipe
$root = New-Root
$script:Cap = [double](40 * $MiB)
$script:CancelAfter = 4
$r = Job_WipeFree @{ Root = $root; Reserve = [double](2 * $MiB); VolSpec = 'X:' }
Assert-True ($r.Canceled -eq $true -and $null -eq $r.Verdict) 'kanarya: iptalde karar verilmez'
Assert-Eq $script:ImgRead 1 'kanarya: iptalde yalnızca ön okuma yapıldı'
Assert-Eq (Count-Files $root) 0 'kanarya: iptalde geçici dosyalar silindi'

# 5g) doğrudan işlevler
Reset-Wipe
$key = [Mm.WipeEngine]::NewKey()
$img = New-Object byte[] (4 * $MiB)
$wsx = [Mm.WipeStream]::new(0, $key, 7)
$chunk = New-Object byte[] 16384
$wsx.Fill($chunk, 0, 16384, 0)
[Array]::Copy($chunk, 0, $img, 8192, 16384)
$wsx.Dispose()
# ilk 8 KB özgün (random), sonraki 4 KB sıfır, son 4 KB başka veri
for ($i = 8192 + 8192; $i -lt 8192 + 12288; $i++) { $img[$i] = 0 }
for ($i = 8192 + 12288; $i -lt 8192 + 16384; $i++) { $img[$i] = 77 }
[System.IO.File]::WriteAllBytes($script:VolImg, $img)
$cn = @{ Key = $key; Items = @(@{ Pass = 7; Extents = @(@{ Start = [long]8192; Length = [long]16384; StreamPos = [long]0 }) }); Units = [long]4; Files = 1 }
$tc = Test-WipeCanary $cn 'X:'
Assert-True ($tc.Checked -eq $true -and $tc.Units -eq 4 -and $tc.Same -eq 2 -and $tc.Zeroed -eq 1 -and $tc.Changed -eq 1 -and $tc.Error -eq '') 'kanarya okuma: aynı, sıfırlanmış ve değişmiş birimler'
$tcEmpty = Test-WipeCanary $null 'X:'
Assert-True ($tcEmpty.Checked -eq $false -and $tcEmpty.Units -eq 0) 'kanarya okuma: kanarya yoksa kontrol yok'
$tcEmpty2 = Test-WipeCanary @{ Key = $key; Items = @() } 'X:'
Assert-True ($tcEmpty2.Checked -eq $false) 'kanarya okuma: öğe yoksa kontrol yok'
function Open-WipeRead([string]$Spec) { throw 'birim açılamadı (sahte)' }
$tcErr = Test-WipeCanary $cn 'X:'
Assert-True ($tcErr.Checked -eq $false -and $tcErr.Error -match 'birim açılamadı') 'kanarya okuma: açılamazsa hata metni'
function Open-WipeRead([string]$Spec) { $script:ImgRead++; return [Mm.WipeTarget]::Open($script:VolImg, $false) }

$vOk = Get-WipeCanaryVerdict @{ Checked = $true; Same = 10; Units = 10 } @{ Checked = $true; Same = 0; Units = 10 }
Assert-True ($vOk.Level -eq 'ok' -and $vOk.Text -match '10 / 10') 'karar: ok'
$vWarn = Get-WipeCanaryVerdict @{ Checked = $true; Same = 10; Units = 10 } @{ Checked = $true; Same = 3; Units = 10 }
Assert-True ($vWarn.Level -eq 'warn' -and $vWarn.Text -match '3 / 10') 'karar: eski veri kalmış'
$vInfo = Get-WipeCanaryVerdict @{ Checked = $true; Same = 0; Units = 10 } @{ Checked = $true; Same = 0; Units = 10 }
Assert-Eq $vInfo.Level 'info' 'karar: baştan okunamıyordu'
$vWarn2 = Get-WipeCanaryVerdict @{ Checked = $true; Same = 0; Units = 10 } @{ Checked = $true; Same = 4; Units = 10 }
Assert-True ($vWarn2.Level -eq 'warn' -and $vWarn2.Text -match '4 / 10') 'karar: ön okuma boşken sonra veri görünürse uyarı'
$vNone = Get-WipeCanaryVerdict @{ Checked = $true; Same = 1; Units = 1 } @{ Checked = $false; Same = 0; Units = 0 }
Assert-Eq $vNone.Level 'none' 'karar: son okuma yapılamadı'
$vNone2 = Get-WipeCanaryVerdict $null $null
Assert-Eq $vNone2.Level 'none' 'karar: hiç okuma yok'
$vPre = Get-WipeCanaryVerdict $null @{ Checked = $true; Same = 0; Units = 5 }
Assert-Eq $vPre.Level 'info' 'karar: ön okuma yoksa ve kalan yoksa bilgi'

# kanarya üretimi (sahte konum sorgusuyla)
Reset-Wipe
$cdir = New-Root
$nc = New-WipeCanary $cdir
Assert-True ($nc.Files -eq 6 -and @($nc.Items).Count -eq 6 -and $nc.Key.Length -eq 32) 'kanarya üretimi: altı dosya ve anahtar'
Assert-Eq $nc.Units ([long](6 * 64)) 'kanarya üretimi: toplam birim'
Assert-Eq (Count-Files $cdir) 0 'kanarya üretimi: dosyalar silindi'
Assert-True ($nc.Items[0].Pass -eq 1 -and $nc.Items[5].Pass -eq 6) 'kanarya üretimi: geçiş numaraları'
Assert-True ($nc.Items[0].Extents[0].StreamPos -eq 0 -and $nc.Items[0].Extents[0].Length -eq 262144) 'kanarya üretimi: konum ve akış başlangıcı'
$pre = Test-WipeCanary $nc 'X:'
Assert-True ($pre.Same -eq $pre.Units -and $pre.Units -eq $nc.Units) 'kanarya üretimi: yazılan veri akıştan yeniden üretilip doğrulanır'
$script:CanaryMode = 'none'
$ncNone = New-WipeCanary $cdir
Assert-True ($ncNone.Files -eq 6 -and @($ncNone.Items).Count -eq 0 -and $ncNone.Units -eq 0) 'kanarya üretimi: konum yoksa öğe yok'
$script:CanaryMode = 'ok'
$small = New-WipeCanary $cdir 2 8192
Assert-True ($small.Files -eq 2 -and @($small.Items).Count -eq 2 -and $small.Units -eq 4) 'kanarya üretimi: dosya sayısı ve boyutu ayarlanabilir'
Assert-Eq (Count-Files $cdir) 0 'kanarya üretimi: yine temiz'

# =====================================================================
#  6) boş alan işi: TRIM isteği
# =====================================================================
Reset-Wipe
$root = New-Root
$script:Cap = [double](20 * $MiB)
$r = Job_WipeFree @{ Root = $root; Reserve = [double](2 * $MiB); Canary = $false; Trim = $true; VolSpec = 'X:' }
Assert-True ($r.Ok -eq $true -and $null -ne $r.Trim -and $r.Trim.Ok -eq $true) 'TRIM isteği: gönderildi'
Assert-Eq ($script:TrimCalls -join ',') 'X:' 'TRIM isteği: birim belirteci'
Assert-True (Log-Has 'TRIM gönderildi') 'TRIM isteği: günlükte'
Reset-Wipe
$root = New-Root
$script:Cap = [double](20 * $MiB)
$script:TrimOk = $false
$r = Job_WipeFree @{ Root = $root; Reserve = [double](2 * $MiB); Canary = $false; Trim = $true; VolSpec = 'X:' }
Assert-True ($r.Ok -eq $true -and $r.Trim.Ok -eq $false -and $r.Trim.Error -match 'reddedildi') 'TRIM isteği: hata iş sonucunu bozmaz'
Assert-True (Log-Has 'WARN: TRIM gönderilemedi') 'TRIM isteği: hata uyarı olarak günlükte'
Reset-Wipe
$root = New-Root
$script:Cap = [double](20 * $MiB)
$r = Job_WipeFree @{ Root = $root; Reserve = [double](2 * $MiB); Canary = $false; Trim = $false; VolSpec = 'X:' }
Assert-True ($null -eq $r.Trim -and $script:TrimCalls.Count -eq 0) 'TRIM isteği: istenmediyse gönderilmez'
Reset-Wipe
$root = New-Root
$script:Cap = [double](20 * $MiB)
$r = Job_WipeFree @{ Root = $root; Reserve = [double](2 * $MiB); Canary = $false; Trim = $true }
Assert-True ($null -eq $r.Trim -and $script:TrimCalls.Count -eq 0) 'TRIM isteği: sürücü harfi yoksa gönderilmez'

# =====================================================================
#  7) TRIM işi
# =====================================================================
function Test-Path {
    [CmdletBinding()] param([string]$LiteralPath, [string]$PathType)
    if ($LiteralPath -eq 'T:\') { return $true }
    return (Microsoft.PowerShell.Management\Test-Path @PSBoundParameters)
}
Reset-Wipe
foreach ($bad in @('', 'zz', '12', 'C:\x')) {
    $tr = Job_TrimVolume @{ Drive = $bad }
    Assert-True ($tr.Ok -eq $false -and $tr.Error -match 'Geçerli bir sürücü') ("TRIM işi: geçersiz sürücü [$bad]")
}
$tr = Job_TrimVolume @{ Drive = 'Q:' }
Assert-True ($tr.Ok -eq $false -and $tr.Error -match 'bulunamadı') 'TRIM işi: olmayan sürücü'
$tr = Job_TrimVolume @{ Drive = 't' }
Assert-True ($tr.Ok -eq $true -and $tr.Drive -eq 'T:' -and $tr.Kind -eq 'Trim') 'TRIM işi: harf tek başına verilebilir'
Assert-Eq $script:TrimCalls[0] 'T:' 'TRIM işi: sürücü belirteci'
Assert-True (Log-Has 'TRIM gönderildi.') 'TRIM işi: günlük'
$script:TrimOk = $false
$tr = Job_TrimVolume @{ Drive = 'T:\' }
Assert-True ($tr.Ok -eq $false -and $tr.Error -match 'reddedildi' -and $tr.Drive -eq 'T:') 'TRIM işi: hata iletilir'
Assert-True (Log-Has 'ERR: TRIM gönderilemedi') 'TRIM işi: hata günlükte'
Remove-Item function:Test-Path

# =====================================================================
#  8) kendi kendine denetim
# =====================================================================
$leftBefore = @(Get-ChildItem -LiteralPath ([System.IO.Path]::GetTempPath()) -Filter 'mm-silme-deneme-*' -ErrorAction SilentlyContinue).Count
$sc = Invoke-WipeSelfCheck
Assert-True ($sc.Ok -eq $true) 'öz denetim: başarılı'
Assert-True (@($sc.Lines).Count -ge 3 -and @($sc.Lines | Where-Object { $_.Ok -ne $true }).Count -eq 0) 'öz denetim: tüm satırlar tamam'
Assert-True ((@($sc.Lines | ForEach-Object { $_.Text }) -join '|') -match 'yazma ve doğrulama') 'öz denetim: imaj üzerinde yazma ve doğrulama satırı'
$leftAfter = @(Get-ChildItem -LiteralPath ([System.IO.Path]::GetTempPath()) -Filter 'mm-silme-deneme-*' -ErrorAction SilentlyContinue).Count
Assert-Eq $leftAfter $leftBefore 'öz denetim: geçici imaj silindi'

Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
Show-Result
