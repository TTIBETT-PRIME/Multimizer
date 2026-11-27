# -*- coding: utf-8 -*-
"""Gerçek cihazdaki duman testinin bulduğu tutarsızlıklar (test düzeneğinde; uygulama davranışı değişmez).

1) Yerleşim adımı: doğrudan "Layout" adımı Select-Layout'u çağırıp ayarı yalnızca bellekte değiştiriyordu. Gerçek akışlarda (Ayarlar
   listesi, hazır görünüm) seçim hemen ayar dosyasına yazılır. Her arka plan işi bitince ayarlar dosyadan yeniden okunduğu için
   (Complete-Async) yazılmamış yerleşim eski değere dönüyor, Ayarlar listesi uygulanan yerleşimden farklı bir değer gösteriyordu;
   aynı değer yeniden seçilince hiçbir şey olmuyor ve yerleşim denetimi dört hata veriyordu. Tasarım ve saydamlık adımları ayarı
   zaten yazıyordu; yerleşim adımı da artık yazar.
2) Güvenli çizim: duman testi gerçek ayar dosyasının kopyasıyla koşar. Kopyada önceki bir çökmeden kalan kalıcı "güvenli çizim"
   varsa saydamlık hiç uygulanmıyor, Mica / Akrilik ve ekran görüntüsü denetimleri bir şey ölçmüyordu (Akrilik görünürlüğü yanlış
   hata veriyordu). Test artık varsayılan olarak normal çizimle koşar; MM_DUMAN_GUVENLI=1 ile güvenli kipte denenir. Ayrıca istenen
   efekt uygulanmıyorsa (güvenli çizim, desteklemeyen yapı) görünürlük beklenmez. Yalnızca geçici kopya değişir.
3) Akrilik görünürlük ölçümü yerleşime bağlıydı: ölçüm yalnızca pencerenin sol gövdesini örnekliyordu. "Ayrıntılı" yerleşimde işlem günlüğü ve
   kartlar gövdeyi kapladığı için cam orada yarı yarıya silikleşiyor (%70 için fark 2,4, %50 için 6,4); "Kompakt" yerleşimde aynı ölçüm 5,3 ve 12
   veriyordu. Efekt ekranda görünüyordu, eşik yerleşime göre yanlış kalıyordu. Ölçüm artık başlık ve durum çubuğu şeritlerini de örnekler
   (cam her yerleşimde en çok orada görünür: 6,4 ve 13,9); büyük olan fark sayılır. Gerçek ekran görüntüleriyle aynı hesap yeniden yapılıp
   doğrulandı; efekt kapalıyken iki ölçüm de 1,1'in altında kalır.
4) %70 eşiği ilk ölçümde tek bir değerden (4,9) türetilmişti (eşik 3). Sonraki koşularda aynı efekt 3,9 ile 6,4 arasında ölçüldü; eşik, ölçülen en
   düşük değerin yaklaşık %65'i olacak biçimde 2,5'e indirildi (%50 için 8 aynı oranda kalır: en düşük ölçüm 12)."""

SAFE_COPY = """        if (Test-Path -LiteralPath $realSt) { Copy-Item -LiteralPath $realSt -Destination $script:SettingsFile -Force -ErrorAction SilentlyContinue }
        # Kopyada onceki bir cokmeden kalma kalici "guvenli cizim" olabilir; duman testi varsayilan olarak normal cizimle kosar
        # (guvenli kipte saydamlik hic uygulanmaz, Mica / Akrilik ve ekran goruntusu denetimleri bir sey olcmez). Yalnizca gecici kopya degisir.
        # MM_DUMAN_GUVENLI=1 verilirse ayni test guvenli kipte kosar.
        if (Test-Path -LiteralPath $script:SettingsFile) {
            $stText = [System.IO.File]::ReadAllText($script:SettingsFile)
            $stSafe = 'false'
            if ([string]$env:MM_DUMAN_GUVENLI -eq '1') { $stSafe = 'true'; $Guvenli = [switch]$true }
            $stText = [regex]::Replace($stText, '("SafeRender"\\s*:\\s*)(true|false)', ('${1}' + $stSafe))
            $stText = [regex]::Replace($stText, '("CrashStreak"\\s*:\\s*)\\d+', '${1}0')
            [System.IO.File]::WriteAllText($script:SettingsFile, $stText, (New-Object System.Text.UTF8Encoding($false)))
        }
"""

REPS = [
    # 1) yerleşim adımı ayarı dosyaya da yazar
    ("        }\n        'LayoutCheck' { Test-SmokeLayout $arg $true }\n",
     "            # Select-* yalnizca uygular; gercek akislarda secimi Ayarlar sayfasi kaydeder. Arka plan isi bitince ayarlar dosyadan yeniden\n"
     "            # okunur (Complete-Async): kaydedilmemis yerlesim eski degere donerdi. Duman testi gecici kopyada calisir.\n"
     "            try { Save-Settings $script:Settings } catch { }\n"
     "        }\n        'LayoutCheck' { Test-SmokeLayout $arg $true }\n", 1),

    # 2) duman testi varsayılan olarak normal çizimle koşar
    ("        if (Test-Path -LiteralPath $realSt) { Copy-Item -LiteralPath $realSt -Destination $script:SettingsFile -Force -ErrorAction SilentlyContinue }\n",
     SAFE_COPY, 1),

    # 3) istenen efekt bu oturumda uygulanmıyorsa görünürlük beklenmez; gövde farkı yerleşime bağlı olduğundan üst ve alt şerit de sayılır
    ("    if ($min -gt 0 -and $d -lt $min) {\n        if (Test-SmokeSysTransparency) {",
     "    # Govde farki yerlesime gore degisir: Ayrintili yerlesimde opak kartlar camin onunu kapatir. Ust ve alt serit olculduyse buyuk olan fark sayilir.\n"
     "    if ($null -ne $a.BarR -and $null -ne $b.BarR) {\n"
     "        $dBar = ([math]::Abs([double]$a.BarR - [double]$b.BarR) + [math]::Abs([double]$a.BarG - [double]$b.BarG) + [math]::Abs([double]$a.BarB - [double]$b.BarB)) / 3.0\n"
     "        $info = $info + ', üst ve alt şerit farkı ' + [string][math]::Round($dBar, 1)\n"
     "        if ($dBar -gt $d) { $d = $dBar }\n"
     "    }\n"
     "    if ($min -gt 0 -and $d -lt $min) {\n"
     "        if ([string]$script:GlassPlan.Mode -eq 'Yok') { Add-SmokeLine ('      görünürlük ' + [string]$p[0] + ': efekt bu oturumda uygulanmıyor (' + [string]$script:GlassPlan.Note + '), görünmesi beklenmez - ' + $info) }\n"
     "        elseif (Test-SmokeSysTransparency) {", 1),

    # 4) ust ve alt serit ortalamasi govdeyle birlikte saklanir
    ("    if ($n -lt 1) { return $null }\n    return @{ R = ($r / $n); G = ($g / $n); B = ($b / $n) }\n}\n",
     "    if ($n -lt 1) { return $null }\n"
     "    $res = @{ R = ($r / $n); G = ($g / $n); B = ($b / $n) }\n"
     "    # Ust ve alt serit (baslik ve durum cubugu): govdede opak kartlar camin onunu kapatabilir ve bu yerlesime gore degisir\n"
     "    # (Ayrintili yerlesimde govde farki yarisina iner). Seritlerde yuzey pencerenin kendisidir; cam her yerlesimde en belirgin burada gorunur.\n"
     "    # Statik icerik (yazi, simge) iki goruntude de ayni oldugundan farki etkilemez.\n"
     "    $sr = 0.0\n"
     "    $sg = 0.0\n"
     "    $sb = 0.0\n"
     "    $sn = 0\n"
     "    foreach ($band in @(@(0.012, 0.070), @(0.945, 0.985))) {\n"
     "        for ($y = [int]($h * [double]$band[0]); $y -lt [int]($h * [double]$band[1]); $y += 4) {\n"
     "            for ($x = $xa; $x -lt $xb; $x += 6) {\n"
     "                $c = $Bmp.GetPixel($x, $y)\n"
     "                $sr += [double]$c.R\n"
     "                $sg += [double]$c.G\n"
     "                $sb += [double]$c.B\n"
     "                $sn++\n"
     "            }\n"
     "        }\n"
     "    }\n"
     "    if ($sn -gt 0) { $res.BarR = ($sr / $sn); $res.BarG = ($sg / $sn); $res.BarB = ($sb / $sn) }\n"
     "    return $res\n"
     "}\n", 1),

    # 5) esik aciklamasi: iki olcumun gercek degerleri
    ("                # Gercek cihazda olculen ortalama renk farki: %90 -> 1,3  %70 -> 4,9  %50 -> 12,2; esikler bu degerlerin altinda kalir\n",
     "                # Gercek cihazda olculen ortalama renk farki; govde ve ust/alt serit olculur, buyugu sayilir.\n"
     "                # Kompakt yerlesim: %90 -> 0,6   %70 -> 3,9 ila 5,3   %50 -> 12 ila 15. Ayrintili yerlesimde govdeyi opak kartlar kapladigindan govde\n"
     "                # 0,3 / 2,4 / 6,4, ust ve alt serit 1,6 / 6,4 / 13,9 cikar. Efekt kapaliyken ayni olcum 1,1'in altinda kalir.\n"
     "                # Esikler, olculen en dusuk degerin yaklasik %65'i: %70 icin 2,5 ve %50 icin 8\n", 1),

    # 6) %70 esigi: ilk olcumde tek bir degerden (4,9) turetilmisti; farkli yerlesim ve kosularda en dusuk deger 3,9 cikti
    ("if ([int]$op -le 50) { $minDiff = 8 } elseif ([int]$op -le 70) { $minDiff = 3 }",
     "if ([int]$op -le 50) { $minDiff = 8 } elseif ([int]$op -le 70) { $minDiff = 2.5 }", 1),
]


def apply(b):
    for old, new, cnt in REPS:
        b.rep(old, new, count=cnt, name='p50 ' + old[:40].strip())
