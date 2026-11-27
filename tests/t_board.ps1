# 8.0.0: Düzen Motoru (döşeme panosu) — saf mantık: katalog, çarpışma, sıkıştırma, taşıma/boyutlandırma/ekleme/çıkarma,
# kayıtlı düzenin doğrulanması, JSON gidiş-dönüş, hazır düzenler, piksel hesapları ve rastgele (tohumlu) karşılaştırma testi.
. "$PSScriptRoot/lib.ps1"

Import-Fn 'ConvertTo-BoardInt', 'Get-BoardField', 'Resolve-BoardType', 'Get-BoardSpec', 'Get-BoardActionKey', 'Resolve-BoardArg', 'ConvertTo-BoardTileFit'
Import-Fn 'Find-BoardTile', 'Get-BoardNewId', 'New-BoardTile', 'Copy-BoardLayout', 'Test-BoardCollide', 'Test-BoardHit', 'Get-BoardOrder', 'Invoke-BoardCompact'
Import-Fn 'Move-BoardTile', 'Resize-BoardTile', 'Add-BoardTile', 'Remove-BoardTile', 'ConvertTo-BoardLayout', 'ConvertTo-BoardData', 'ConvertFrom-BoardSpecs'
Import-Fn 'Get-BoardPreset', 'Get-BoardProblems', 'Get-BoardCellW', 'Get-BoardRows', 'Get-BoardRect', 'Get-BoardCell', 'Get-BoardSpan'
Import-Var 'BoardCols', 'BoardMaxTiles', 'BoardMaxRows', 'BoardWidgets', 'BoardActions', 'BoardPresets', 'BoardPresetInfo'
Import-Fn 'Get-TileAccent', 'Get-TileSoft'
Import-Var 'BoardAccent', 'BoardActionAccent', 'BoardSoftOf', 'Themes'

$src = [System.IO.File]::ReadAllText($script:TestPath)

function New-L { return , (New-Object System.Collections.ArrayList) }
function Tile([string]$Id, [string]$Type, [int]$X, [int]$Y, [int]$W, [int]$H, [string]$Arg = '') { return @{ Id = $Id; Type = $Type; X = $X; Y = $Y; W = $W; H = $H; Arg = $Arg } }
function Pos($L, [string]$Id) { $t = Find-BoardTile $L $Id; return ('{0},{1},{2},{3}' -f $t.X, $t.Y, $t.W, $t.H) }

# ======================= 1) katalog ve eylemler =======================
Assert-Eq $script:BoardCols 12 'pano 12 sütunlu'
Assert-True ($script:BoardWidgets.Count -ge 15) 'katalogda parçalar var'
foreach ($k in @($script:BoardWidgets.Keys)) {
    $w = $script:BoardWidgets[$k]
    Assert-True ($w.MinW -le $w.W -and $w.W -le $w.MaxW) "$k varsayılan genişlik sınırlar içinde"
    Assert-True ($w.MinH -le $w.H -and $w.H -le $w.MaxH) "$k varsayılan yükseklik sınırlar içinde"
    Assert-True ($w.MinW -ge 1 -and $w.MinH -ge 1 -and $w.MaxW -le 12) "$k sınırlar makul"
    Assert-True ([string]$w.T -ne '' -and [string]$w.D -ne '') "$k adı ve açıklaması var"
    Assert-True ($src.Contains('x:Key="' + $w.Ico + '"')) "$k simgesi uygulamada tanımlı ($($w.Ico))"
}
foreach ($k in @($script:BoardActions.Keys)) {
    $a = $script:BoardActions[$k]
    Assert-True ([string]$a.T -ne '' -and [string]$a.D -ne '') "$k eylem adı ve açıklaması var"
    Assert-True ($src.Contains('x:Key="' + $a.Ico + '"')) "$k eylem simgesi tanımlı ($($a.Ico))"
    Assert-True ([string]$a.Page -ne '' -or [string]$a.Fn -ne '') "$k bir sayfaya ya da işleve bağlı"
    if ([string]$a.Page -ne '') { Assert-True ($src.Contains('$script:Page_' + $a.Page + ' = ')) "$k eylemi var olan sayfayı açıyor ($($a.Page))" }
    Assert-True (@('', 'health', 'maint', 'audit', 'report') -contains [string]$a.Fn) "$k işlev adı tanınıyor ($($a.Fn))"
}

# ======================= 2) küçük yardımcılar =======================
Assert-Eq (ConvertTo-BoardInt '5') 5 'tam sayı: metin'
Assert-Eq (ConvertTo-BoardInt 3.7) 3 'tam sayı: kesir aşağı yuvarlanır'
Assert-Eq (ConvertTo-BoardInt 'abc' 9) 9 'tam sayı: sayı olmayan varsayılan'
Assert-Eq (ConvertTo-BoardInt $null 7) 7 'tam sayı: null varsayılan'
Assert-Eq (ConvertTo-BoardInt 1e12 4) 4 'tam sayı: taşan değer varsayılan'
Assert-Eq (ConvertTo-BoardInt -2) -2 'tam sayı: eksi korunur'
Assert-Eq (Resolve-BoardType 'CPU') 'cpu' 'tür: büyük harf eşlenir'
Assert-Eq (Resolve-BoardType ' hero ') 'hero' 'tür: boşluk kırpılır'
Assert-Eq (Resolve-BoardType 'yok') '' 'tür: bilinmeyen boş'
Assert-Eq (Get-BoardActionKey 'SPEED') 'speed' 'eylem anahtarı küçük harfe'
Assert-Eq (Get-BoardActionKey 'yok') 'health' 'eylem: bilinmeyen varsayılana'
Assert-Eq (Resolve-BoardArg 'cpu' 'speed') '' 'eylem dışı türde bağımsız değişken boş'
Assert-Eq (Resolve-BoardArg 'action' 'zzz') 'health' 'action: varsayılan sağlık'
Assert-Eq (Resolve-BoardArg 'cta' '') 'maint' 'cta: varsayılan bakım'
$f = ConvertTo-BoardTileFit 'cpu' 99 99
Assert-Eq "$($f.W),$($f.H)" '6,4' 'sığdır: üst sınır'
$f = ConvertTo-BoardTileFit 'cpu' 0 0
Assert-Eq "$($f.W),$($f.H)" '2,2' 'sığdır: alt sınır'
$f = ConvertTo-BoardTileFit 'hero' $null $null
Assert-Eq "$($f.W),$($f.H)" '12,2' 'sığdır: boşsa varsayılan boyut'

# ======================= 3) döşeme oluşturma =======================
$t = New-BoardTile 't1' 'cpu' 11 -3 3 2
Assert-Eq "$($t.X),$($t.Y)" '9,0' 'yeni döşeme: sağ kenar ve eksi satır düzeltilir'
Assert-True ($null -eq (New-BoardTile 't1' 'yok' 0 0 3 2)) 'yeni döşeme: bilinmeyen tür null'
$t = New-BoardTile 't1' 'action' 0 0 4 3 'BOGUS'
Assert-Eq $t.Arg 'health' 'yeni döşeme: geçersiz eylem varsayılana'
$t = New-BoardTile 't1' 'CTA' 0 0 4 1
Assert-Eq "$($t.Type)|$($t.Arg)" 'cta|maint' 'yeni döşeme: tür normalleşir, cta varsayılanı'

# ======================= 4) çarpışma =======================
$a = Tile 'a' 'cpu' 0 0 3 2
Assert-True (-not (Test-BoardCollide $a (Tile 'b' 'ram' 3 0 3 2))) 'yan yana (kenar değen) çakışmaz'
Assert-True (-not (Test-BoardCollide $a (Tile 'b' 'ram' 0 2 3 2))) 'alt alta (kenar değen) çakışmaz'
Assert-True (Test-BoardCollide $a (Tile 'b' 'ram' 2 1 3 2)) 'köşe örtüşmesi çakışır'
Assert-True (Test-BoardCollide $a (Tile 'b' 'ram' 0 0 3 2)) 'aynı yer çakışır'
Assert-True (Test-BoardCollide (Tile 'o' 'hero' 0 0 12 2) (Tile 'i' 'cpu' 4 1 3 2)) 'büyük döşeme küçüğü kapsar'

# ======================= 5) sıkıştırma =======================
$L = New-L; [void]$L.Add((Tile 'a' 'cpu' 0 5 3 2))
Invoke-BoardCompact $L ''
Assert-Eq (Pos $L 'a') '0,0,3,2' 'tek döşeme en üste çıkar'

$L = New-L; [void]$L.Add((Tile 'a' 'cpu' 0 0 3 2)); [void]$L.Add((Tile 'b' 'ram' 0 0 3 2))
Invoke-BoardCompact $L ''
Assert-Eq (Pos $L 'a') '0,0,3,2' 'çakışmada önce gelen yerinde kalır'
Assert-Eq (Pos $L 'b') '0,2,3,2' 'çakışmada ikincisi altına itilir'

$L = New-L; [void]$L.Add((Tile 'a' 'cpu' 0 0 3 2)); [void]$L.Add((Tile 'b' 'ram' 0 0 3 2))
Invoke-BoardCompact $L 'b'
Assert-Eq (Pos $L 'b') '0,0,3,2' 'sabitlenen döşeme yerinde kalır'
Assert-Eq (Pos $L 'a') '0,2,3,2' 'sabitlenenle çakışan altına itilir'

$L = New-L; [void]$L.Add((Tile 'a' 'cpu' 0 0 3 2)); [void]$L.Add((Tile 'b' 'ram' 3 3 3 2)); [void]$L.Add((Tile 'c' 'net' 6 7 3 2))
Invoke-BoardCompact $L ''
Assert-Eq (Pos $L 'b') '3,0,3,2' 'yan sütundaki döşeme yukarı çıkar'
Assert-Eq (Pos $L 'c') '6,0,3,2' 'boşluk kalan döşeme yukarı çıkar'

# sabitlenen tek başına aşağıda kalabilir (sürüklerken); bırakınca tüm sıkıştırma yukarı çeker
$L = New-L; [void]$L.Add((Tile 'a' 'cpu' 0 0 3 2)); [void]$L.Add((Tile 'b' 'ram' 3 0 3 2))
[void](Move-BoardTile $L 'b' 3 6)
Assert-Eq (Pos $L 'b') '3,6,3,2' 'taşınan döşeme istenen yerde kalır (canlı önizleme)'
Invoke-BoardCompact $L ''
Assert-Eq (Pos $L 'b') '3,0,3,2' 'bırakınca boşluk kapanır'

# kararlılık: aynı konumdaki döşemelerde özgün sıra korunur ve ikinci çalıştırma değişiklik yapmaz
$L = New-L; [void]$L.Add((Tile 'a' 'cpu' 0 0 3 2)); [void]$L.Add((Tile 'b' 'ram' 3 0 3 2)); [void]$L.Add((Tile 'c' 'net' 6 4 3 2)); [void]$L.Add((Tile 'd' 'disk' 1 1 3 2))
Invoke-BoardCompact $L ''
$snap1 = (ConvertTo-Json -InputObject (ConvertTo-BoardData $L) -Compress -Depth 4)
Invoke-BoardCompact $L ''
$snap2 = (ConvertTo-Json -InputObject (ConvertTo-BoardData $L) -Compress -Depth 4)
Assert-Eq $snap2 $snap1 'sıkıştırma tekrarlanınca değişmez'
Assert-Eq @(Get-BoardProblems $L).Count 0 'sıkıştırılmış düzende sorun yok'

# ======================= 6) taşıma ve boyutlandırma =======================
$L = Get-BoardPreset 'Komuta'
Assert-True (Move-BoardTile $L 't1' 9 0) 'taşıma: var olan döşeme'
Assert-True (-not (Move-BoardTile $L 'yok' 0 0)) 'taşıma: olmayan kimlik false'
Assert-Eq (Pos $L 't1') '9,0,3,3' 'taşıma: konum uygulanır'
Assert-Eq @(Get-BoardProblems $L).Count 0 'taşıma sonrası çakışma yok'
[void](Move-BoardTile $L 't1' 50 -4)
Assert-Eq (Pos $L 't1') '9,0,3,3' 'taşıma: sınır dışı değer sınıra çekilir'

$L = Get-BoardPreset 'Morpheus'
Assert-True (Resize-BoardTile $L 't4' 12 5) 'boyutlandırma: uygulanır'
$p = Find-BoardTile $L 't4'
Assert-Eq "$($p.W),$($p.H)" '12,5' 'boyutlandırma: boyut'
Assert-Eq ([int]$p.X) 0 'boyutlandırma: sağa taşan döşeme geri çekilir'
Assert-Eq @(Get-BoardProblems $L).Count 0 'boyutlandırma sonrası çakışma yok'
[void](Resize-BoardTile $L 't4' 99 99)
$p = Find-BoardTile $L 't4'
Assert-Eq "$($p.W),$($p.H)" '12,6' 'boyutlandırma: üst sınıra çekilir'
[void](Resize-BoardTile $L 't4' 0 0)
$p = Find-BoardTile $L 't4'
Assert-Eq "$($p.W),$($p.H)" '3,2' 'boyutlandırma: alt sınıra çekilir'
$L = New-L; [void]$L.Add((Tile 'a' 'cpu' 9 0 3 2))
[void](Resize-BoardTile $L 'a' 6 2)
Assert-Eq (Pos $L 'a') '6,0,6,2' 'sağ kenara dayalı döşeme büyüyünce sola kayar'

# ======================= 7) ekleme ve çıkarma =======================
$L = New-L
$n = Add-BoardTile $L 'hero'
Assert-Eq "$($n.Id)|$($n.X),$($n.Y)" 't1|0,0' 'ekleme: boş panoda ilk yer'
Assert-True ($null -eq (Add-BoardTile $L 'hero')) 'ekleme: tek kopyalık parça ikinci kez eklenmez'
Assert-True ($null -eq (Add-BoardTile $L 'yok')) 'ekleme: bilinmeyen tür null'
$n = Add-BoardTile $L 'action' 'speed'
Assert-Eq "$($n.Id)|$($n.Y)|$($n.Arg)" 't2|2|speed' 'ekleme: başlığın altına, eylemle'
$n = Add-BoardTile $L 'action' 'network'
Assert-Eq "$($n.X),$($n.Y)" '4,2' 'ekleme: yan yana ilk boşluk'
Assert-Eq @(Get-BoardProblems $L).Count 0 'ekleme sonrası sorun yok'
Assert-True (Remove-BoardTile $L 't2') 'çıkarma: var olan'
Assert-True (-not (Remove-BoardTile $L 't2')) 'çıkarma: ikinci kez false'
Assert-Eq (Pos $L 't3') '4,2,4,3' 'çıkarma: kalan döşeme yatayda yerinde kalır (yalnızca dikey sıkıştırma)'
$L = New-L
for ($i = 0; $i -lt $script:BoardMaxTiles; $i++) { $r = Add-BoardTile $L 'cta'; if ($null -eq $r) { break } }
Assert-Eq $L.Count $script:BoardMaxTiles 'ekleme: üst sınıra kadar eklenir'
Assert-True ($null -eq (Add-BoardTile $L 'cta')) 'ekleme: sınır aşılınca null'
Assert-Eq @(Get-BoardProblems $L).Count 0 'dolu panoda sorun yok'
$ids = @($L | ForEach-Object { $_.Id } | Select-Object -Unique)
Assert-Eq $ids.Count $script:BoardMaxTiles 'kimlikler benzersiz'
$n = Add-BoardTile (New-L) 'sysinfo'
Assert-Eq "$($n.W),$($n.H)" '4,2' 'ekleme: varsayılan boyut'
$L = New-L; [void]$L.Add((Tile 't7' 'cpu' 0 0 3 2))
Assert-Eq (Get-BoardNewId $L) 't8' 'sıradaki kimlik'
Assert-Eq (Get-BoardNewId (New-L)) 't1' 'boş panoda ilk kimlik'

# ======================= 8) kayıtlı düzenin doğrulanması =======================
$bad = @(
    @{ Id = 'a1'; Type = 'cpu'; X = 0; Y = 0; W = 3; H = 2 },
    @{ Id = 'a1'; Type = 'cpu'; X = 0; Y = 0; W = 3; H = 2 },
    @{ Id = 'zz'; Type = 'bilinmeyen'; X = 0; Y = 0; W = 3; H = 2 },
    $null,
    @{ Id = 'BAD ID'; Type = 'RAM'; X = '3'; Y = '0'; W = '3'; H = '2' },
    @{ Id = 'a1'; Type = 'action'; X = 99; Y = -5; W = 99; H = 0; Arg = 'speed' },
    @{ Id = 'a1'; Type = 'action'; X = 0; Y = 0; W = 4; H = 3; Arg = 'nope' }
)
$L = ConvertTo-BoardLayout $bad
Assert-Eq $L.Count 4 'doğrulama: bilinmeyen, yinelenen tek-kopya ve null atılır (cpu, ram, 2 eylem)'
Assert-Eq @(Get-BoardProblems $L).Count 0 'doğrulanan düzende sorun yok'
$ids = @($L | ForEach-Object { $_.Id } | Select-Object -Unique)
Assert-Eq $ids.Count 4 'doğrulama: kimlikler benzersiz yapılır'
foreach ($tt in $L) { Assert-True ([string]$tt.Id -cmatch '^[a-z][a-z0-9]{0,11}$') "kimlik biçimi: $($tt.Id)" }
$act = @($L | Where-Object { $_.Type -eq 'action' })
Assert-Eq $act.Count 2 'doğrulama: eylem kartı çoğaltılabilir'
Assert-True (@($act | Where-Object { $_.Arg -eq 'speed' }).Count -eq 1 -and @($act | Where-Object { $_.Arg -eq 'health' }).Count -eq 1) 'doğrulama: eylemler korunur, geçersiz olan varsayılana döner'
Assert-Eq (ConvertTo-BoardLayout $null).Count 0 'doğrulama: null veri boş düzen'
Assert-Eq (ConvertTo-BoardLayout @()).Count 0 'doğrulama: boş dizi boş düzen'
$many = @(); for ($i = 0; $i -lt 40; $i++) { $many += , @{ Id = ('x' + $i); Type = 'cta'; X = 0; Y = $i; W = 4; H = 1 } }
Assert-Eq (ConvertTo-BoardLayout $many).Count $script:BoardMaxTiles 'doğrulama: en çok 24 döşeme'
# PSCustomObject (JSON'dan gelen) kaydı da kabul edilir
$js = '[{"Id":"t1","Type":"cpu","X":0,"Y":0,"W":3,"H":2,"Arg":""},{"Id":"t2","Type":"action","X":3,"Y":0,"W":4,"H":3,"Arg":"clean"}]'
$L = ConvertTo-BoardLayout ($js | ConvertFrom-Json)
Assert-Eq $L.Count 2 'JSON: iki döşeme okunur'
Assert-Eq (Pos $L 't2') '3,0,4,3' 'JSON: konum okunur'
Assert-Eq (Find-BoardTile $L 't2').Arg 'clean' 'JSON: eylem okunur'

# gidiş-dönüş: kaydet → oku → aynı düzen
foreach ($name in @('Klasik', 'Atolye', 'Sifir', 'Morpheus', 'Komuta')) {
    $L = Get-BoardPreset $name
    $json = ConvertTo-Json -InputObject (ConvertTo-BoardData $L) -Compress -Depth 4
    $L2 = ConvertTo-BoardLayout ($json | ConvertFrom-Json)
    $json2 = ConvertTo-Json -InputObject (ConvertTo-BoardData $L2) -Compress -Depth 4
    Assert-Eq $json2 $json "gidiş-dönüş aynı kalır ($name)"
}

# ======================= 9) hazır düzenler =======================
Assert-Eq $script:BoardPresets.Count 5 'beş hazır düzen (Klasik, Atölye, Sıfır, Morpheus, Komuta)'
Assert-Eq (@($script:BoardPresetInfo.Keys | Sort-Object) -join ',') (@($script:BoardPresets.Keys | Sort-Object) -join ',') 'Hazır düzen menüsünün adları, düzen tablosuyla aynı anahtarlara sahip'
foreach ($name in @($script:BoardPresetInfo.Keys)) { Assert-True (([string]$script:BoardPresetInfo[$name].T -ne '') -and ([string]$script:BoardPresetInfo[$name].D -ne '')) "$name hazır düzeninin adı ve açıklaması var" }
foreach ($name in @($script:BoardPresets.Keys)) {
    $L = Get-BoardPreset $name
    Assert-True ($L.Count -ge 5) "$name düzeninde döşeme var"
    Assert-Eq $L.Count @($script:BoardPresets[$name]).Count "$name tanımının hepsi uygulanır (hiçbiri atılmadı)"
    Assert-Eq @(Get-BoardProblems $L).Count 0 "$name düzeninde sorun yok"
    Assert-True ((Get-BoardRows $L) -le 10) "$name düzeni 10 satırı aşmaz ($(Get-BoardRows $L))"
    $before = ConvertTo-Json -InputObject (ConvertTo-BoardData $L) -Compress -Depth 4
    Invoke-BoardCompact $L ''
    Assert-Eq (ConvertTo-Json -InputObject (ConvertTo-BoardData $L) -Compress -Depth 4) $before "$name düzeni zaten sıkışık"
    foreach ($tt in $L) {
        if ($tt.Type -eq 'action' -or $tt.Type -eq 'cta') { Assert-True ($script:BoardActions.Contains($tt.Arg)) "$name eylemi geçerli ($($tt.Arg))" }
    }
}
Assert-Eq (Get-BoardPreset 'olmayan').Count (Get-BoardPreset 'Klasik').Count 'bilinmeyen tasarım Klasik düzenine düşer'
Assert-Eq (Find-BoardTile (Get-BoardPreset 'Klasik') 't1').Type 'health' 'Klasik düzen sağlık puanıyla başlar'
$kt = @((Get-BoardPreset 'Klasik') | ForEach-Object { $_.Type })
foreach ($need in @('health', 'cpu', 'ram', 'gpu', 'disk', 'net', 'temp', 'action', 'top', 'sysinfo', 'log')) { Assert-True ($kt -contains $need) "Klasik düzen klasik panonun parçasını taşır: $need" }
Assert-True (@((Get-BoardPreset 'Klasik') | Where-Object { $_.Type -eq 'action' }).Count -ge 4) 'Klasik düzende hızlı eylem kartları var'
Assert-Eq (Find-BoardTile (Get-BoardPreset 'Sifir') 't1').Type 'search' 'Sıfır Noktası komut çubuğuyla başlar'
Assert-Eq (Find-BoardTile (Get-BoardPreset 'Atolye') 't1').Type 'hero' 'Atölye başlıkla başlar'

# ======================= 10) piksel hesapları =======================
$cw = Get-BoardCellW 1200 10
Assert-True ([math]::Abs($cw - 90.8333) -lt 0.01) "hücre genişliği ($cw)"
Assert-True ((Get-BoardCellW 50 10) -ge 20) 'çok dar alanda hücre alt sınırı'
foreach ($spanW in 1..12) {
    $tt = Tile 'p' 'cta' 0 0 $spanW 1
    $r = Get-BoardRect $tt $cw 70 10
    Assert-Eq (Get-BoardSpan $r.W $cw 10) $spanW "piksel→hücre genişliği ($spanW)"
}
foreach ($x in 0..11) {
    $tt = Tile 'p' 'cta' $x 3 1 1
    $r = Get-BoardRect $tt $cw 70 10
    $c = Get-BoardCell $r.X $r.Y $cw 70 10
    Assert-Eq "$($c.X),$($c.Y)" "$x,3" "piksel→hücre konumu ($x)"
}
$c = Get-BoardCell -20 -5 $cw 70 10
Assert-Eq "$($c.X),$($c.Y)" '0,0' 'eksi piksel 0. hücreye çekilir'
$r = Get-BoardRect (Tile 'p' 'cta' 2 1 3 2) 90 70 10
Assert-Eq "$($r.X),$($r.Y),$($r.W),$($r.H)" '200,80,290,150' 'dikdörtgen hesabı'

# ======================= 11) rastgele işlem dizisi (tohumlu) =======================
$rng = New-Object System.Random 20261019
$fuzzFail = 0
foreach ($name in @('Atolye', 'Sifir', 'Morpheus', 'Komuta')) {
    $L = Get-BoardPreset $name
    for ($step = 0; $step -lt 250; $step++) {
        $op = $rng.Next(0, 5)
        $types = @($script:BoardWidgets.Keys)
        if ($L.Count -eq 0) { $op = 3 }
        switch ($op) {
            0 { $tt = $L[$rng.Next(0, $L.Count)]; [void](Move-BoardTile $L $tt.Id $rng.Next(-3, 16) $rng.Next(-3, 14)) }
            1 { $tt = $L[$rng.Next(0, $L.Count)]; [void](Resize-BoardTile $L $tt.Id $rng.Next(-1, 15) $rng.Next(-1, 9)) }
            2 { $tt = $L[$rng.Next(0, $L.Count)]; [void](Remove-BoardTile $L $tt.Id) }
            3 { [void](Add-BoardTile $L $types[$rng.Next(0, $types.Count)]) }
            4 { Invoke-BoardCompact $L '' }
        }
        $pr = @(Get-BoardProblems $L)
        if ($pr.Count -gt 0) { $fuzzFail++; Write-Host ("rastgele $name adım $step işlem $op : " + ($pr -join '; ')) -ForegroundColor Red; break }
    }
    $snapA = ConvertTo-Json -InputObject (ConvertTo-BoardData $L) -Compress -Depth 4
    $L2 = ConvertTo-BoardLayout ($snapA | ConvertFrom-Json)
    Assert-Eq (ConvertTo-Json -InputObject (ConvertTo-BoardData $L2) -Compress -Depth 4) $snapA "rastgele işlemlerden sonra kayıt gidiş-dönüş ($name)"
}
Assert-Eq $fuzzFail 0 'rastgele işlem dizilerinde hiçbir adımda çakışma ya da sınır ihlali olmaz'

# taşıma isteği sınır içindeyse taşınan tam istenen yerde durur (yalnızca diğerleri uyum sağlar)
$L = Get-BoardPreset 'Komuta'
$ok = $true
for ($i = 0; $i -lt 60; $i++) {
    $tt = $L[$rng.Next(0, $L.Count)]
    $nx = $rng.Next(0, 13 - [int]$tt.W)
    $ny = $rng.Next(0, 9)
    [void](Move-BoardTile $L $tt.Id $nx $ny)
    $q = Find-BoardTile $L $tt.Id
    if ([int]$q.X -ne $nx -or [int]$q.Y -ne $ny) { $ok = $false }
    Invoke-BoardCompact $L ''
}
Assert-True $ok 'taşınan döşeme istenen hücrede durur'

# ---------------- döşeme simge renkleri: anlamına göre, her temada karşılığı olan fırça anahtarlarıyla ----------------
$neonKeys = @($script:Themes['Neon'].Keys)
foreach ($ak in @($script:BoardActions.Keys)) {
    Assert-True ($script:BoardActionAccent.ContainsKey([string]$ak)) ("eylem '$ak' bir vurgu rengine bağlı (sessizce varsayılana düşmez)")
}
foreach ($ak in @($script:BoardActionAccent.Keys)) { Assert-True ($script:BoardActions.Contains([string]$ak)) ("vurgu tablosunda olmayan eylem yok: $ak") }
foreach ($tk in @($script:BoardAccent.Keys)) { Assert-True ($script:BoardWidgets.Contains([string]$tk)) ("vurgu tablosundaki döşeme türü katalogda var: $tk") }
$accs = @(@($script:BoardAccent.Values) + @($script:BoardActionAccent.Values) | Select-Object -Unique)
foreach ($a in $accs) {
    Assert-True ($neonKeys -contains [string]$a) ("vurgu fırçası tema paletinde var: $a")
    Assert-True ($script:BoardSoftOf.ContainsKey([string]$a)) ("vurgunun yumuşak çip karşılığı tanımlı: $a")
    Assert-True ($neonKeys -contains [string]$script:BoardSoftOf[[string]$a]) ("çip fırçası tema paletinde var: " + [string]$script:BoardSoftOf[[string]$a])
}
Assert-True ($accs.Count -ge 5) 'ana ekran en az beş farklı vurgu rengi kullanır (renkli, tek tonlu değil)'
Assert-Eq (Get-TileAccent 'action' 'health' 'Glass') 'BrGood' 'sağlık taraması kartı yeşil'
Assert-Eq (Get-TileAccent 'action' 'network' 'Calm') 'BrBlue' 'ağ koruması kartı mavi'
Assert-Eq (Get-TileAccent 'action' 'maint' 'Plain') 'BrGold' 'bakım kartı altın'
Assert-Eq (Get-TileAccent 'action' 'speed' 'Slate') 'BrAccent' 'hızlandır kartı tema vurgusu'
Assert-Eq (Get-TileAccent 'action' 'gaming' 'Glass') 'BrAccent2' 'oyun kipi kartı ikinci vurgu'
Assert-Eq (Get-TileAccent 'cpu' '' 'Glass') 'BrBlue' 'işlemci döşemesi mavi'
Assert-Eq (Get-TileAccent 'cta' 'maint' 'Glass') 'BrAccent' 'büyük düğme tema vurgusunda kalır'
Assert-Eq (Get-TileAccent 'action' 'bilinmeyen' 'Glass') 'BrAccent' 'bilinmeyen eylem tema vurgusuna düşer'
Assert-Eq (Get-TileAccent 'hero' '' 'Glass') 'BrAccent' 'karşılama başlığı tema vurgusunda'
foreach ($tt in @('action', 'cpu', 'health', 'ram')) { Assert-Eq (Get-TileAccent $tt 'health' 'Neon') 'BrAccent' "Neon kaplaması tek renk kullanır ($tt)" }
Assert-Eq (Get-TileSoft 'BrBlue') 'BrBlueSoft' 'mavi simgenin çipi BrBlueSoft'
Assert-Eq (Get-TileSoft 'BrGood') 'BrGoodSoft' 'yeşil simgenin çipi BrGoodSoft'
Assert-Eq (Get-TileSoft 'BrAccent2') 'BrAccent2Soft' 'ikinci vurgunun çipi BrAccent2Soft'
Assert-Eq (Get-TileSoft 'BrAccent') 'BrActiveBg' 'tema vurgusunun çipi BrActiveBg'
Assert-Eq (Get-TileSoft 'BrGold') 'BrGoldBg' 'altının çipi BrGoldBg'
Assert-Eq (Get-TileSoft 'BrYok') 'BrActiveBg' 'bilinmeyen vurgu BrActiveBg çipine düşer'
Assert-True ($src.Contains('Arg = [string]$Tile.Arg;')) 'döşeme görünümü eylem anahtarını taşır (kaplama rengi buradan seçilir)'
Assert-True ($src.Contains('(Get-TileSoft $acc)') -and $src.Contains('Get-TileAccent $type ([string]$V.Arg) $skin')) 'kaplama simge ve çip rengini ortak işlevlerden alır'

Show-Result
