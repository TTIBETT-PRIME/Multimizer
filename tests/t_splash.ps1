. "$PSScriptRoot/lib.ps1"
# Konsol açılış ekranı: logo, gradyan, çizim mantığı (sahte konsolla), aşamalar, düz yedek kip ve açılış akışına bağlantılar

Import-Fn 'Get-SplashLead', 'Get-SplashIndent', 'Get-SplashLogo', 'Get-SplashRgb', 'Get-SplashEsc', 'Format-SplashFit', 'Get-SplashLines', 'Write-SplashFrame', 'Write-SplashPlainHeader', 'Write-SplashPlainStep', 'Start-Splash', 'Update-Splash', 'Set-SplashStep', 'Stop-Splash', 'Complete-Splash', 'Get-SplashSummary', 'Clear-SplashScreen'
Import-Var 'SplashPhases', 'SplashHeadText', 'SplashDoneText', 'SplashWarnText', 'SplashRst', 'SplashTagline'
$script:AppVersion = '8.0.0'

# ---- sahte konsol: yazılanlar, imleç satırı, boyut ve yetenekler
$script:Out = New-Object System.Text.StringBuilder
$script:CurTop = 0
$script:Moves = New-Object System.Collections.ArrayList
$script:CursorVis = $null
$script:ThrowOnMove = $false
$script:TestW = 100
$script:TestH = 30
$script:TestVt = $true
$script:TestRedirected = $false
$script:TestCursorFail = $false
$script:HostCap = $false
$script:HostOut = New-Object System.Collections.ArrayList
function global:Write-SplashRaw([string]$Text) { [void]$script:Out.Append($Text); $script:CurTop += ([regex]::Matches($Text, "`r`n")).Count }
function global:Get-SplashCursorTop { if ($script:TestCursorFail) { return -1 }; return $script:CurTop }
function global:Move-SplashCursor([int]$Row) { if ($script:ThrowOnMove) { throw 'imleç taşınamadı' }; [void]$script:Moves.Add($Row); $script:CurTop = $Row }
function global:Set-SplashCursorVisible([bool]$On) { $script:CursorVis = $On }
function global:Get-SplashConsoleSize { return @($script:TestW, $script:TestH) }
function global:Test-SplashRedirected { return $script:TestRedirected }
function global:Enable-SplashVt { return $script:TestVt }
function global:Write-Host {
    param([Parameter(Position = 0, ValueFromRemainingArguments = $true)]$Object, $ForegroundColor, $BackgroundColor, [switch]$NoNewline, $Separator)
    if ($script:HostCap) { [void]$script:HostOut.Add((@($Object) -join ' ')); return }
    Microsoft.PowerShell.Utility\Write-Host @PSBoundParameters
}
function Reset-Fake {
    [void]$script:Out.Clear()
    $script:CurTop = 0
    $script:Moves.Clear()
    $script:HostOut.Clear()
    $script:CursorVis = $null
    $script:ThrowOnMove = $false
    $script:TestW = 100
    $script:TestH = 30
    $script:TestVt = $true
    $script:TestRedirected = $false
    $script:TestCursorFail = $false
    $script:HostCap = $false
    $script:SplashOn = $false
    $script:SplashMode = 'off'
    $script:SplashFull = $false
    $script:SplashIdx = 0
    $script:SplashTop = -1
    $script:SplashWidth = 80
    $script:SplashClock = $null
    $script:SplashTimes = @{}
    Remove-Item Env:MM_PREBANNER -ErrorAction SilentlyContinue
}
function Strip([string]$s) { return [regex]::Replace($s, "\x1b\[[0-9;]*[A-Za-z]", '') }
# gorunur metnin sol boslugu
function LeadOf([string]$s) { return ($s.Length - $s.TrimStart().Length) }
# bir satir konsol genisliginde ortalanmis mi (sol bosluk ile sag bosluk en cok 1 farkli; son sutun bos kalir)
function IsCentered([string]$line, [int]$w) {
    $t = $line.Trim()
    if ($t.Length -eq 0) { return $true }
    $left = LeadOf $line
    $right = ($w - 1) - $left - $t.Length
    return ($right -ge 0 -and [math]::Abs($left - $right) -le 1)
}
$block = [string][char]0x2588
$shade = [string][char]0x2591

# ------------------------------------------------------------------ 1) logo
$want = @(
    '███╗   ███╗██╗   ██╗██╗     ████████╗██╗███╗   ███╗██╗███████╗███████╗██████╗ ',
    '████╗ ████║██║   ██║██║     ╚══██╔══╝██║████╗ ████║██║╚══███╔╝██╔════╝██╔══██╗',
    '██╔████╔██║██║   ██║██║        ██║   ██║██╔████╔██║██║  ███╔╝ █████╗  ██████╔╝',
    '██║╚██╔╝██║██║   ██║██║        ██║   ██║██║╚██╔╝██║██║ ███╔╝  ██╔══╝  ██╔══██╗',
    '██║ ╚═╝ ██║╚██████╔╝███████╗   ██║   ██║██║ ╚═╝ ██║██║███████╗███████╗██║  ██║',
    '╚═╝     ╚═╝ ╚═════╝ ╚══════╝   ╚═╝   ╚═╝╚═╝     ╚═╝╚═╝╚══════╝╚══════╝╚═╝  ╚═╝'
)
$logo = @(Get-SplashLogo)
Assert-Eq $logo.Count 6 'logo 6 satır'
for ($i = 0; $i -lt 6; $i++) {
    Assert-Eq $logo[$i].Length 78 ('logo satırı ' + $i + ' tam 78 sütun (80 sütunluk konsola sığar)')
    Assert-Eq $logo[$i] $want[$i] ('logo satırı ' + $i + ' ASCII kodundan doğru çözülür')
}
$allowed = [string[]]@(' ', [string][char]0x2588, [string][char]0x2557, [string][char]0x2550, [string][char]0x2551, [string][char]0x255A, [string][char]0x255D, [string][char]0x2554)
$strange = @($logo | ForEach-Object { $_.ToCharArray() } | Where-Object { $allowed -notcontains [string]$_ })
Assert-Eq $strange.Count 0 'logoda yalnızca blok ve kutu çizim karakterleri var'

# ------------------------------------------------------------------ 2) gradyan ve renk dizisi
Assert-Eq ((Get-SplashRgb 0) -join ',') '0,229,255' 'gradyan başı camgöbeği'
Assert-Eq ((Get-SplashRgb 0.5) -join ',') '124,77,255' 'gradyan ortası mor'
Assert-Eq ((Get-SplashRgb 1) -join ',') '255,64,196' 'gradyan sonu pembe'
Assert-Eq ((Get-SplashRgb -3) -join ',') '0,229,255' 'gradyan 0 altında başa sabitlenir'
Assert-Eq ((Get-SplashRgb 7) -join ',') '255,64,196' 'gradyan 1 üstünde sona sabitlenir'
$prev = Get-SplashRgb 0
$mono = $true
for ($t = 0.05; $t -le 1.0001; $t += 0.05) {
    $c = Get-SplashRgb $t
    if ($c[0] -lt $prev[0] -or $c[1] -gt $prev[1] -or $c[2] -gt $prev[2]) { $mono = $false }
    $prev = $c
}
Assert-True $mono 'gradyan düzgün ilerler (kırmızı artar, yeşil ve mavi azalır)'
$esc = [string][char]27
Assert-Eq (Get-SplashEsc @(1, 2, 3)) ($esc + '[38;2;1;2;3m') '24 bit renk dizisi'
Assert-Eq (Get-SplashEsc @(1, 2, 3) 0.5) ($esc + '[38;2;1;1;2m') 'gölge: renk yarıya koyulaşır'
Assert-Eq $SplashRst ($esc + '[0m') 'renk sıfırlama dizisi'
Assert-Eq (Format-SplashFit 'abcdef' 6) 'abcdef' 'sığan metin değişmez'
Assert-Eq (Format-SplashFit 'abcdefg' 6) ('abcde' + [char]0x2026) 'sığmayan metin … ile kısalır'
Assert-Eq (Format-SplashFit 'abc' 0) '' 'genişlik 0: boş'
Assert-Eq (Format-SplashFit 'abc' 1) 'a' 'genişlik 1: ilk harf'

# ------------------------------------------------------------------ 3) aşama tablosu
Assert-Eq $SplashPhases.Count 9 '9 açılış aşaması'
Assert-Eq (($SplashPhases | ForEach-Object { $_.Key }) -join ',') 'konsol,arayuz,veri,cekirdek,ayarlar,calisma,sistem,pencere,hazir' 'aşama sırası betiğin gerçek akışıyla aynı'
Assert-Eq $SplashPhases[0].Pct 0 'ilk aşama %0'
Assert-Eq $SplashPhases[8].Pct 100 'son aşama %100'
$inc = $true
for ($i = 1; $i -lt $SplashPhases.Count; $i++) { if ([int]$SplashPhases[$i].Pct -le [int]$SplashPhases[$i - 1].Pct) { $inc = $false } }
Assert-True $inc 'yüzdeler kesin artan'
foreach ($ph in $SplashPhases) {
    Assert-True ([string]$ph.Mod -ne '' -and [string]$ph.Text -ne '') ('aşama ' + $ph.Key + ': modül adı ve metin dolu')
    Assert-True ([int]$ph.Pct -ge 0 -and [int]$ph.Pct -le 100) ('aşama ' + $ph.Key + ': yüzde 0-100')
}
Assert-Eq $SplashHeadText ('Araç başlatılıyor' + [char]0x2026) 'başlık metni'
Assert-Eq $SplashWarnText 'Bu pencereyi kapatmayın.' 'uyarı metni'

# ------------------------------------------------------------------ 4) güncellenen satırlar (renkli kip)
Reset-Fake
$script:SplashMode = 'vt'
$script:SplashWidth = 100
$script:SplashIdx = 3
$ln = @(Get-SplashLines)
Assert-Eq $ln.Count 3 'üç güncellenen satır'
foreach ($l in $ln) { Assert-Eq (Strip $l).Length 99 'satır tam genişlik - 1 karakter (eski içerik kalmaz, sarmaz)' }
foreach ($ix in @(0, 3, 6, 8)) {
    foreach ($w in @(60, 80, 100, 120, 200)) {
        $script:SplashWidth = $w; $script:SplashIdx = $ix
        $script:SplashClock = [System.Diagnostics.Stopwatch]::StartNew()
        $cl = @(Get-SplashLines)
        for ($k = 0; $k -lt 3; $k++) {
            $vl = Strip $cl[$k]
            Assert-True (IsCentered $vl $w) ('genişlik ' + $w + ', aşama ' + $ix + ', satır ' + ($k + 1) + ': satır ortalanmış (sol ' + (LeadOf $vl) + ', metin ' + $vl.Trim().Length + ')')
        }
    }
}
$script:SplashWidth = 100; $script:SplashIdx = 3
$ln = @(Get-SplashLines)
$s1 = (Strip $ln[0]).Trim(); $s2 = Strip $ln[1]; $s3 = (Strip $ln[2]).Trim()
Assert-Eq $s1 $SplashHeadText 'başlık satırı'
$fill = ([regex]::Matches($s2, $block)).Count
$empty = ([regex]::Matches($s2, $shade)).Count
$p3 = [int]$SplashPhases[3].Pct
Assert-Eq $fill ([int][math]::Floor(44 * $p3 / 100.0 + 0.5)) ('çubuk: %' + $p3 + ' için 44 hücrenin yuvarlanmış payı dolu')
Assert-Eq ($fill + $empty) 44 'çubuk 44 hücre'
Assert-True ($s2.TrimEnd().EndsWith(' %' + $p3)) ('yüzde etiketi sağda: %' + $p3)
Assert-True ($s3.StartsWith('PID ' + $PID)) 'durum satırı PID ile başlar'
Assert-True ($s3.Contains('Modül: Çekirdek')) 'durum satırı modül adını yazar'
Assert-True ($s3.Contains('Adım 4/9')) 'durum satırı adım sayısını yazar'
Assert-True ($s3.EndsWith('Çekirdek işlevler yükleniyor')) 'durum satırı aşama metniyle biter'
# son aşama
$script:SplashIdx = 8
$script:SplashClock = [System.Diagnostics.Stopwatch]::StartNew()
$ln = @(Get-SplashLines)
Assert-Eq (Strip $ln[0]).Trim() $SplashDoneText 'tamamlanınca başlık "Hazır" olur'
$s2 = Strip $ln[1]
Assert-Eq (([regex]::Matches($s2, $block)).Count) 44 'tamamlanınca çubuk tam dolu'
Assert-Eq (([regex]::Matches($s2, $shade)).Count) 0 'tamamlanınca boş hücre yok'
Assert-True ($s2.TrimEnd().EndsWith('%100')) '%100'
$s3 = (Strip $ln[2]).Trim()
Assert-True ($s3.Contains('Adım 9/9') -and $s3.Contains('Pencere açıldı') -and $s3.Contains(' sn)')) 'tamamlanınca süre yazılır'
Assert-True ($ln[0].Contains($esc + '[38;2;80;250;160m')) 'tamamlanınca başlık yeşil'
# dar konsol: hiçbir satır genişliği aşmaz
foreach ($w in @(30, 40, 50, 60, 80, 120, 200)) {
    foreach ($ix in @(0, 3, 6, 8)) {
        $script:SplashWidth = $w
        $script:SplashIdx = $ix
        $ln = @(Get-SplashLines)
        $maxLen = (@($ln | ForEach-Object { (Strip $_).Length }) | Measure-Object -Maximum).Maximum
        Assert-True ($maxLen -le ($w - 1)) ('genişlik ' + $w + ', aşama ' + $ix + ': satırlar sütun sayısını aşmaz (' + $maxLen + ')')
    }
}

# ------------------------------------------------------------------ 5) tam çizim (renkli kip, geniş konsol)
Reset-Fake
Start-Splash
Assert-True ($script:SplashOn -eq $true -and $script:SplashMode -eq 'vt' -and $script:SplashFull -eq $true) 'geniş ve renkli konsolda tam ekran'
Assert-Eq $script:CursorVis $false 'çizim sırasında imleç gizlenir'
$text = $script:Out.ToString()
$lines = @($text -split "`r`n")
$vis = @($lines | ForEach-Object { Strip $_ })
for ($i = 0; $i -lt 6; $i++) {
    Assert-Eq $vis[1 + $i].Trim() $want[$i].Trim() ('çizilen logo satırı ' + $i)
    Assert-Eq (LeadOf $vis[1 + $i]) 10 ('logo satırı ' + $i + ': 100 sütunluk konsolda 10 sütun içeriden başlar (ortalı)')
}
$metaLine = @($vis | Where-Object { $_.Trim() -eq 'v8.0.0  ·  Creator: S. Tibet Tuncer' })
Assert-Eq $metaLine.Count 1 'sürüm ve yapımcı satırı'
Assert-True (IsCentered $metaLine[0] 100) 'sürüm ve yapımcı satırı ortalı'
$tagLine = @($vis | Where-Object { $_.Trim() -eq $SplashTagline })
Assert-Eq $tagLine.Count 1 'slogan satırı'
Assert-True (IsCentered $tagLine[0] 100) 'slogan satırı ortalı'
$warnLine = @($vis | Where-Object { $_.Trim() -eq ('[!] ' + $SplashWarnText) })
Assert-Eq $warnLine.Count 1 'kapatma uyarısı'
Assert-True (IsCentered $warnLine[0] 100) 'kapatma uyarısı ortalı'
Assert-Eq $vis[7].Length 0 'logo ile sürüm satırı arasında boş satır var'
Assert-Eq $script:CurTop 17 'çizim 17 satır tutar'
Assert-Eq $script:SplashTop 11 'güncellenen satırlar 12. satırdan başlar (imleç satırı - 6)'
Assert-Eq $vis[$script:SplashTop].Trim() $SplashHeadText 'güncellenen ilk satır başlıktır (konum hesabı doğru)'
Assert-True ($vis[$script:SplashTop + 1].Contains($shade)) 'ikinci güncellenen satır ilerleme çubuğudur'
Assert-True ($vis[$script:SplashTop + 2].Trim().StartsWith('PID')) 'üçüncü güncellenen satır durum satırıdır'
$maxLen = (@($vis | ForEach-Object { $_.Length }) | Measure-Object -Maximum).Maximum
Assert-True ($maxLen -le 99) 'hiçbir satır konsol genişliğini aşmaz'
Assert-True (-not $text.StartsWith($esc + '[2J')) 'Baslat.bat başlığı yokken ekran silinmez'
$sizeBefore = $script:Out.Length
Start-Splash
Assert-Eq $script:Out.Length $sizeBefore 'ikinci Start-Splash yeniden çizmez'

# aşama güncellemesi: yalnızca üç satır yeniden yazılır, imleç eski yerine döner
$parkRow = $script:CurTop
Set-SplashStep 'arayuz'
Assert-Eq ($script:Moves -join ',') '11,12,13,17' 'güncelleme: üç satıra git, sonra imleç alt satıra döner'
$added = $script:Out.ToString().Substring($sizeBefore)
Assert-True ((Strip $added).Contains('Arayüz bileşenleri yükleniyor') -and (Strip $added).Contains('Adım 2/9')) 'yeni aşama metni yazıldı'
Assert-True (-not $added.Contains([string][char]0x2557)) 'güncelleme logoyu yeniden çizmez'
Assert-Eq $script:CurTop $parkRow 'imleç park satırında kalır'
$n1 = $script:Moves.Count
Set-SplashStep 'konsol'
Set-SplashStep 'arayuz'
Set-SplashStep 'bilinmeyen'
Set-SplashStep ''
Assert-Eq $script:Moves.Count $n1 'geriye gidiş, aynı aşama ve bilinmeyen anahtar yok sayılır'
Set-SplashStep 'sistem'
Assert-Eq $script:SplashIdx 6 'aşama atlanabilir (ileri)'
Assert-True ((Strip $script:Out.ToString()).Contains('Sistem bilgisi toplanıyor')) 'sistem aşaması yazıldı'
$sum = Get-SplashSummary
Assert-True ($sum.StartsWith('konsol=0 arayuz=') -and $sum.Contains(' sistem=') -and -not $sum.Contains('veri=')) 'aşama süreleri yalnızca geçilenler için yazılır'
Complete-Splash
Assert-True ($script:SplashOn -eq $false -and $script:CursorVis -eq $true) 'tamamlanınca ekran kapanır, imleç görünür'
$all = $script:Out.ToString()
Assert-True ((Strip $all).Contains($SplashDoneText)) 'son durum yazıldı'
Assert-True ($all.EndsWith($SplashRst)) 'çıktı renk sıfırlamayla biter (konsol rengi bozulmaz)'
$size2 = $script:Out.Length
Set-SplashStep 'hazir'
Update-Splash
Stop-Splash 'not'
Assert-Eq $script:Out.Length $size2 'kapandıktan sonra hiçbir çağrı yazmaz'
Assert-True ((Get-SplashSummary).Contains(' hazir=')) 'özet "hazir" aşamasını içerir'

# Baslat.bat başlığı varsa ekran önce silinir
Reset-Fake
$env:MM_PREBANNER = '1'
Start-Splash
Assert-True ($script:Out.ToString().StartsWith($esc + '[2J' + $esc + '[H')) 'ön başlık varsa ekran silinip başa gidilir'
Remove-Item Env:MM_PREBANNER -ErrorAction SilentlyContinue

# ------------------------------------------------------------------ 6) dar ya da alçak konsol: büyük logo yerine tek satır başlık
foreach ($sz in @(@(70, 30), @(120, 20), @(79, 40))) {
    Reset-Fake
    $script:TestW = $sz[0]
    $script:TestH = $sz[1]
    Start-Splash
    Assert-True ($script:SplashMode -eq 'vt' -and $script:SplashFull -eq $false) ('boyut ' + ($sz -join 'x') + ': kompakt başlık')
    $vis = @(($script:Out.ToString() -split "`r`n") | ForEach-Object { Strip $_ })
    $ttl = @($vis | Where-Object { $_.Trim() -eq 'MULTIMIZER' })
    Assert-True ($ttl.Count -eq 1 -and (IsCentered $ttl[0] $sz[0])) ('boyut ' + ($sz -join 'x') + ': tek satır başlık, ortalı')
    Assert-True (-not ($script:Out.ToString().Contains([string][char]0x2557))) ('boyut ' + ($sz -join 'x') + ': büyük logo çizilmez')
    $maxLen = (@($vis | ForEach-Object { $_.Length }) | Measure-Object -Maximum).Maximum
    Assert-True ($maxLen -le ($sz[0] - 1)) ('boyut ' + ($sz -join 'x') + ': satırlar sığar (' + $maxLen + ')')
    $dynRows = $script:CurTop - 6
    Assert-Eq $script:SplashTop $dynRows 'kompakt kipte de konum hesabı doğru'
    Assert-Eq $vis[$script:SplashTop].Trim() $SplashHeadText 'kompakt: ilk güncellenen satır başlıktır'
    Set-SplashStep 'veri'
    Stop-Splash
}

# ------------------------------------------------------------------ 7) düz (renksiz) yedek kip
foreach ($case in @('renksiz', 'yonlendirilmis', 'imlec')) {
    Reset-Fake
    if ($case -eq 'renksiz') { $script:TestVt = $false }
    if ($case -eq 'yonlendirilmis') { $script:TestRedirected = $true }
    if ($case -eq 'imlec') { $script:TestCursorFail = $true }
    $script:HostCap = $true
    Start-Splash
    Set-SplashStep 'arayuz'
    Set-SplashStep 'ayarlar'
    Complete-Splash
    $script:HostCap = $false
    Assert-Eq $script:SplashMode 'plain' ($case + ': düz kip')
    Assert-Eq $script:Out.Length 0 ($case + ': ANSI dizisi yazılmaz')
    $h = @($script:HostOut)
    Assert-True (($h -join "`n").Contains('MULTIMIZER') -and ($h -join "`n").Contains('Creator: S. Tibet Tuncer') -and ($h -join "`n").Contains($SplashHeadText) -and ($h -join "`n").Contains($SplashWarnText)) ($case + ': başlık satırları yazıldı')
    $mm = @($h | Where-Object { $_.Trim() -eq 'MULTIMIZER' })
    Assert-Eq $mm.Count 1 ($case + ': düz kip başlık adı bir kez')
    if ($case -eq 'yonlendirilmis') { Assert-Eq $mm[0] '   MULTIMIZER' ($case + ': yönlendirilmiş çıktıda sabit girinti (günlük dosyası bozulmaz)') }
    else { Assert-Eq (LeadOf $mm[0]) 44 ($case + ': düz kipte de başlık ortalanır (100 sütun)') }
    Assert-True (@($h | Where-Object { $_.Trim() -eq $SplashTagline }).Count -eq 1) ($case + ': slogan satırı yazıldı')
    Assert-True (@($h | Where-Object { $_ -like ('*%' + [string]$SplashPhases[1].Pct + '*Arayüz - Arayüz bileşenleri yükleniyor') }).Count -eq 1) ($case + ': aşama satırı yüzde ve modülle yazıldı')
    Assert-True (@($h | Where-Object { $_ -like ('*%' + [string]$SplashPhases[4].Pct + '*Ayarlar - Ayarlar okunuyor') }).Count -eq 1) ($case + ': ikinci aşama satırı')
    Assert-True (@($h | Where-Object { $_ -like '*%100*Hazır - Pencere açıldı' }).Count -eq 1) ($case + ': tamamlandı satırı')
    # Stop-Splash notu (ikinci kopya, hata): düz kipte tek satır yazılır, ikinci çağrı bir şey yazmaz
    Reset-Fake
    $script:TestVt = ($case -ne 'renksiz')
    $script:TestRedirected = ($case -eq 'yonlendirilmis')
    $script:TestCursorFail = ($case -eq 'imlec')
    $script:HostCap = $true
    Start-Splash
    $before = $script:HostOut.Count
    Stop-Splash 'Not satırı'
    Stop-Splash 'Ikinci not'
    $script:HostCap = $false
    Assert-Eq ($script:HostOut.Count - $before) 2 ($case + ': Stop-Splash notu bir satır ve bir boş satır yazar; ikinci çağrı yazmaz')
    Assert-True (@($script:HostOut | Where-Object { $_ -like '*Not satırı' }).Count -eq 1) ($case + ': Stop-Splash notu')
}

# renkli kipte Stop-Splash notu: renk sıfırlanır, imleç görünür, not yazılır
Reset-Fake
Start-Splash
$script:HostCap = $true
Stop-Splash 'İkinci kopya notu'
$script:HostCap = $false
Assert-True ($script:Out.ToString().EndsWith($SplashRst) -and $script:CursorVis -eq $true) 'renkli kip: Stop-Splash rengi sıfırlar ve imleci görünür yapar'
Assert-True (@($script:HostOut | Where-Object { $_ -like '*İkinci kopya notu' }).Count -eq 1) 'renkli kip: Stop-Splash notu yazılır'

# ------------------------------------------------------------------ 8) çizim hatası açılışı bozmaz: düz kipe geçilir
Reset-Fake
Start-Splash
$script:ThrowOnMove = $true
$script:HostCap = $true
$thrown = $false
try { Set-SplashStep 'veri' } catch { $thrown = $true }
$script:HostCap = $false
Assert-True (-not $thrown) 'imleç taşınamazsa Set-SplashStep hata fırlatmaz'
Assert-Eq $script:SplashMode 'plain' 'imleç taşınamazsa düz kipe geçilir'
$script:HostCap = $true
Set-SplashStep 'cekirdek'
$script:HostCap = $false
Assert-True (@($script:HostOut | Where-Object { $_ -like '*Çekirdek - Çekirdek işlevler yükleniyor' }).Count -eq 1) 'düz kipe geçtikten sonra aşamalar satır satır yazılır'
Stop-Splash

# başlatılmamış ya da -Cli: hiçbir şey yazılmaz
Reset-Fake
Set-SplashStep 'veri'
Complete-Splash
Stop-Splash 'x'
Assert-Eq $script:Out.Length 0 'başlatılmadan çağrılan işlevler sessizdir'

# ------------------------------------------------------------------ 9) açılış akışına bağlantılar (derlenmiş betik)
$src = [System.IO.File]::ReadAllText($env:MM_BUILD)
function Pos([string]$needle) { return $src.IndexOf($needle) }
$iGuard = Pos 'if (-not $Cli) { Initialize-ConsoleGuard }'
$iStart = Pos 'if (-not $Cli) { Start-Splash }'
$iWpf = Pos 'Add-Type -AssemblyName PresentationFramework, PresentationCore'
$iVeri = Pos "Set-SplashStep 'veri'"
$iCek = Pos "Set-SplashStep 'cekirdek'"
$iAyar = Pos "Set-SplashStep 'ayarlar'"
$iCal = Pos "Set-SplashStep 'calisma'"
$iSis = Pos "Set-SplashStep 'sistem'"
$iPen = Pos "Set-SplashStep 'pencere'"
$iDone = Pos 'try { Complete-Splash } catch { }'
Assert-True ($iGuard -gt 0 -and $iStart -gt $iGuard -and $iWpf -gt $iStart) 'sıra: konsol koruması, açılış ekranı, arayüz kitaplıkları'
Assert-True ($iVeri -gt $iWpf -and $iCek -gt $iVeri -and $iAyar -gt $iCek -and $iCal -gt $iAyar -and $iSis -gt $iCal) 'üst düzey aşama bildirimleri betiğin gerçek akış sırasındadır (veri, çekirdek, ayarlar, çalışma alanı, sistem)'
Assert-True ($iDone -gt $iPen) 'pencere aşaması Loaded olayındaki tamamlanmadan önce bildirilir'
Assert-Eq ([regex]::Matches($src, "Set-SplashStep '(\w+)'")).Count 8 'Set-SplashStep çağrıları: 7 aşama bildirimi + Complete-Splash içindeki "hazir"'
foreach ($m in [regex]::Matches($src, "Set-SplashStep '(\w+)'")) { Assert-True (@($SplashPhases | Where-Object { $_.Key -eq $m.Groups[1].Value }).Count -eq 1) ('aşama anahtarı tablodadır: ' + $m.Groups[1].Value) }
foreach ($ph in $SplashPhases) { if ($ph.Key -ne 'konsol') { Assert-True ($src.Contains("Set-SplashStep '" + $ph.Key + "'")) ('aşama bir yerde bildirilir: ' + $ph.Key) } }
Assert-True ((Pos "Set-SplashStep 'ayarlar'") -lt (Pos ('$script:Settings = Get-Settings' + "`r`n" + '$sync.Settings = $script:Settings'))) 'ayarlar aşaması Get-Settings çağrısından önce'
Assert-True ((Pos "Set-SplashStep 'sistem'") -lt (Pos '$sync.Profile = Get-SystemProfile')) 'sistem aşaması Get-SystemProfile çağrısından önce'
Assert-True ((Pos "Set-SplashStep 'calisma'") -lt (Pos 'try { Initialize-Work } catch { }')) 'çalışma alanı aşaması Initialize-Work çağrısından önce'
Assert-True ($iDone -lt (Pos '{ Hide-ConsoleWindow }')) 'son durum konsol gizlenmeden önce yazılır'
Assert-True ($src.Contains('# Sabit bant (konsolda gorunur)') -eq $false) 'eski düz bant kaldırıldı'
Assert-True ($src.Contains('Arac baslatiliyor... bu pencereyi kapatmayin') -eq $false) 'eski bant metni kalmadı'

$fns = @(Get-AstFunctions)
function Get-Fn([string]$n) { return @($fns | Where-Object { $_.Name -eq $n })[0] }
$guiMode = (Get-Fn 'Invoke-GuiMode').Extent.Text
Assert-True ($guiMode -notmatch 'Test-SingleInstance') 'Invoke-GuiMode artık ikinci kopya denetimi yapmaz (Baslangic bölümünde, ağır hazırlıklardan önce yapılır)'
Assert-True ($guiMode.Contains("Set-SplashStep 'pencere'")) 'Invoke-GuiMode pencere aşamasını bildirir'
$iSingle = Pos 'if (-not (Test-SingleInstance)) {'
Assert-True ($iSingle -gt $iCek -and $iSingle -lt $iAyar -and $iSingle -lt $iSis) 'ikinci kopya denetimi ayarlar, çalışma alanı ve sistem bilgisinden önce'
$blk = $src.Substring($iSingle - 80, 520)
Assert-True ($blk.Contains('-not $Cli -and -not $OzTest -and -not $Duman')) 'ikinci kopya denetimi yalnızca arayüz kipinde (komut satırı, -OzTest ve duman hariç)'
Assert-True ($blk.Contains('Stop-Splash') -and $blk.Contains('try { Restore-ConsoleGuard } catch { }') -and $blk.Contains('[Environment]::Exit(0)')) 'ikinci kopya: ekran kapanır, konsol kipi geri yüklenir, temiz çıkılır'
Assert-True ((Pos ('Stop-Splash' + "`r`n" + '    $nr = @(Invoke-SelfTest)')) -gt 0) '-OzTest sonuç satırlarından önce açılış ekranı kapanır'
$failFn = (Get-Fn 'Show-StartFailure').Extent.Text
Assert-True ($failFn.IndexOf('Stop-Splash') -gt 0 -and $failFn.IndexOf('Stop-Splash') -lt $failFn.IndexOf('MessageBox')) 'başlatma hatasında ileti kutusundan önce açılış ekranı kapanır'
$smoke = (Get-Fn 'Start-SmokeRun').Extent.Text
Assert-True ($smoke.Contains('Get-SplashSummary')) 'duman testi günlüğü açılış aşama sürelerini yazar'

# açılış ekranı yalnızca konsola yazar: sistem, dosya ya da kayıt defteri işlemi yok
foreach ($fnName in @('Get-SplashLogo', 'Get-SplashRgb', 'Get-SplashEsc', 'Format-SplashFit', 'Get-SplashLines', 'Write-SplashFrame', 'Write-SplashPlainHeader', 'Write-SplashPlainStep', 'Start-Splash', 'Update-Splash', 'Set-SplashStep', 'Stop-Splash', 'Complete-Splash', 'Get-SplashSummary', 'Enable-SplashVt', 'Clear-SplashScreen', 'Write-SplashRaw', 'Move-SplashCursor')) {
    $f = Get-Fn $fnName
    Assert-True ($null -ne $f) ('işlev tanımlı: ' + $fnName)
    if ($null -ne $f) {
        $cmds = @($f.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true) | ForEach-Object { $_.GetCommandName() })
        $bad = @($cmds | Where-Object { $_ -match '^(Set-ItemProperty|New-ItemProperty|Remove-Item|New-Item|Out-File|Set-Content|Add-Content|Start-Process|Invoke-WebRequest|Invoke-RestMethod|Stop-Process|Set-Service|netsh|reg|sc)(\.exe)?$' })
        Assert-Eq ($bad -join ',') '' ($fnName + ': sistem, dosya ya da ağ işlemi yok')
    }
}
# tek tanım ve doğru yer: komut satırı kipinde hiç çizilmez
foreach ($fnName in @('Start-Splash', 'Stop-Splash', 'Set-SplashStep', 'Complete-Splash', 'Update-Splash')) { Assert-Eq (@($fns | Where-Object { $_.Name -eq $fnName }).Count) 1 ($fnName + ' tek kez tanımlı') }
Assert-True ($src.Contains('if (-not $Cli) { Start-Splash }')) 'komut satırı kipinde açılış ekranı çizilmez'

# ------------------------------------------------------------------ 10) çıkışta konsol eski haline döner
$rc = (Get-Fn 'Restore-ConsoleGuard').Extent.Text
Assert-True ($rc.Contains('ConModeOut0') -and $rc.Contains('ConHandleOut') -and $rc.Contains('CursorVisible = $true')) 'çıkışta çıktı kipi geri yüklenir ve imleç görünür olur'
$ev = (Get-Fn 'Enable-SplashVt').Extent.Text
Assert-True ($ev.Contains('15063') -and $ev.Contains('GetStdHandle(-11)') -and $ev.Contains('$script:ConModeOut0 = $m')) 'sanal uç birim yalnızca Windows 10 1703 ve sonrasında açılır; eski kip saklanır'

# ------------------------------------------------------------------ 11) Baslat.bat ön başlığı
$bat = [System.IO.File]::ReadAllText((Join-Path $script:TestDir 'Baslat.bat'))
$batLines = @($bat -split "`r`n")
$pre = @($batLines | Where-Object { $_ -match '^if /i "%MM_MOD%"=="Gui" ' })
Assert-True ($pre.Count -ge 2) 'Baslat.bat: arayüz kipinde ön başlık satırları var'
Assert-True (@($pre | Where-Object { $_ -match 'set "MM_PREBANNER=1"' }).Count -eq 1) 'Baslat.bat: ekranın silinmesi için MM_PREBANNER bildirilir'
Assert-True (@($pre | Where-Object { $_ -match 'call :onbaslik' }).Count -eq 1) 'Baslat.bat: ön başlık alt yordamı yalnızca arayüz kipinde çağrılır'
$iOb = [array]::IndexOf($batLines, ':onbaslik')
$obTxt = ($batLines[$iOb..($batLines.Count - 1)]) -join "`n"
Assert-True ($obTxt -match 'M U L T I M I Z E R' -and $obTxt -match 'Bu pencereyi kapatmayin') 'Baslat.bat: ön başlık adı ve kapatma uyarısını yazar'
$iPre = $bat.IndexOf('MM_PREBANNER=1')
$iRun = $bat.IndexOf('-STA -File "%MM_PS1%"')
Assert-True ($iPre -gt 0 -and $iRun -gt $iPre) 'Baslat.bat: ön başlık PowerShell başlamadan önce yazılır'
Assert-True ($iPre -gt $bat.IndexOf('set "MM_MOD=Komut"')) 'Baslat.bat: ön başlık, kip belirlendikten sonra (komut satırı kipinde yazılmaz)'

Show-Result
