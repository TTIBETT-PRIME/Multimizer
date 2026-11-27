. "$PSScriptRoot/lib.ps1"
# Baslat.bat statik denetimi (cmd bu ortamda calistirilamaz; bu yuzden yapisal hatalari yakalayan denetimler yapilir)

$batPath = Join-Path $script:TestDir 'Baslat.bat'
Assert-True (Test-Path -LiteralPath $batPath) 'Baslat.bat Multimizer.ps1 ile ayni klasorde'
$bytes = [System.IO.File]::ReadAllBytes($batPath)
$text = [System.Text.Encoding]::ASCII.GetString($bytes)

# ---- bicim: yalnizca ASCII, yalnizca CRLF (LF ile biten satirlarda goto etiketleri bozulur)
$nonAscii = @($bytes | Where-Object { $_ -ge 128 }).Count
Assert-Eq $nonAscii 0 'bat dosyasi yalnizca ASCII'
$crlf = ([regex]::Matches($text, "`r`n")).Count
$lf = ([regex]::Matches($text, "`n")).Count
$cr = ([regex]::Matches($text, "`r")).Count
Assert-True ($crlf -gt 50) 'satirlar var'
Assert-Eq $lf $crlf 'bos LF yok (her LF bir CRLF icinde)'
Assert-Eq $cr $crlf 'bos CR yok'
Assert-True ($bytes.Length -lt 3 -or $bytes[0] -ne 0xEF) 'UTF-8 imzasi (BOM) yok'
$lines = @($text -split "`r`n")

# ---- etiketler ve goto hedefleri
$labels = New-Object System.Collections.ArrayList
foreach ($l in $lines) { if ($l -match '^:([A-Za-z0-9_]+)\s*$') { [void]$labels.Add($Matches[1].ToLowerInvariant()) } }
Assert-True ($labels.Count -ge 6) ('etiket sayisi yeterli: ' + $labels.Count)
$dup = @($labels | Group-Object | Where-Object { $_.Count -gt 1 })
Assert-Eq $dup.Count 0 'ayni etiket iki kez tanimlanmamis'
$prefixClash = New-Object System.Collections.ArrayList
foreach ($a in $labels) { foreach ($b in $labels) { if ($a -ne $b -and $b.StartsWith($a)) { [void]$prefixClash.Add($a + '<' + $b) } } }
Assert-Eq $prefixClash.Count 0 ('hicbir etiket baska bir etiketin oneki degil: ' + ($prefixClash -join ', '))
$gotos = New-Object System.Collections.ArrayList
foreach ($l in $lines) { foreach ($m in [regex]::Matches($l, '(?i)goto\s+:?([A-Za-z0-9_]+)')) { [void]$gotos.Add($m.Groups[1].Value.ToLowerInvariant()) } }
# alt yordamlar "call :etiket" ile cagrilir
foreach ($l in $lines) { foreach ($m in [regex]::Matches($l, '(?i)\bcall\s+:([A-Za-z0-9_]+)')) { [void]$gotos.Add($m.Groups[1].Value.ToLowerInvariant()) } }
Assert-True ($gotos.Count -ge 10) 'goto satirlari var'
$missing = @($gotos | Where-Object { $_ -ne 'eof' -and $labels -notcontains $_ })
Assert-Eq $missing.Count 0 ('her goto hedefi tanimli: ' + ($missing -join ', '))
$unused = @($labels | Where-Object { $gotos -notcontains $_ })
Assert-Eq $unused.Count 0 ('kullanilmayan etiket yok: ' + ($unused -join ', '))

# ---- 10.0.0: ortali on baslik, konsol genisligi, yuksek DPI duyarli acilis ekrani
foreach ($lb in @(':konsol_sutun', ':sutun_say', ':orta', ':onbaslik')) { Assert-True ($lines -contains $lb) ('alt yordam etiketi var: ' + $lb) }
$iCik = [array]::IndexOf($lines, ':cik')
foreach ($lb in @(':konsol_sutun', ':sutun_say', ':orta', ':onbaslik')) {
    $k = [array]::IndexOf($lines, $lb)
    Assert-True ($k -gt [array]::IndexOf($lines, ':izin_yok') -and $k -lt $iCik) ($lb + ' yalnizca "call" ile ulasilir: izin_yok bolumunden sonra, :cik oncesi')
}
$iOb = [array]::IndexOf($lines, ':onbaslik')
$ob = @($lines[$iOb..($iCik - 1)])
Assert-True (@($ob | Where-Object { $_ -eq 'exit /b 0' }).Count -ge 1) ':onbaslik exit /b ile doner (sonraki etikete akmaz)'
$obText = $ob -join "`n"
$callCount = 0
for ($i = 0; $i -lt $ob.Count; $i++) {
    if ($ob[$i] -match '^call :orta (\d+)$') {
        $callCount++
        $declared = [int]$Matches[1]
        $echo = ''
        for ($j = $i + 1; $j -lt [math]::Min($ob.Count, $i + 3); $j++) { if ($ob[$j] -match '^echo %MM_PAD%(.*)$') { $echo = $Matches[1]; break } }
        Assert-Eq $echo.Length $declared ('on baslik: "call :orta ' + $declared + '" bildirilen uzunluk metinle ayni (' + $echo + ')')
    }
}
Assert-Eq $callCount 3 'on baslikta uc satir ortalanir (ad, durum, uyari)'
Assert-True ($obText -match 'M U L T I M I Z E R' -and $obText -match 'Arac baslatiliyor' -and $obText -match 'Bu pencereyi kapatmayin') 'on baslik metinleri korunur'
$ik = [array]::IndexOf($lines, ':klasik')
$kl = ($lines[$ik..([array]::IndexOf($lines, ':calistir') - 1)]) -join "`n"
$uacLen = 0
if ($kl -match '(?m)^call :orta (\d+)\s*$') { $uacLen = [int]$Matches[1] }
$uacTxt = ''
if ($kl -match '(?m)^echo %MM_PAD%(Yonetici izni isteniyor[^\r\n]*)$') { $uacTxt = $Matches[1] }
Assert-True ($uacLen -gt 0 -and $uacTxt.Length -eq $uacLen) ('yonetici izni bildirimi ortalanir; bildirilen uzunluk metinle ayni (' + $uacLen + '/' + $uacTxt.Length + ')')
$iCs = [array]::IndexOf($lines, ':konsol_sutun')
$cs = ($lines[$iCs..([array]::IndexOf($lines, ':sutun_say') - 1)]) -join "`n"
Assert-True ($cs -match 'set "MM_COLS=80"') 'konsol genisligi okunamazsa 80 sutun varsayilir'
Assert-True ($cs -match 'mode con 2\^>nul \^\| findstr /r "\[0-9\]"') 'sutun sayisi mode con ciktisindan okunur (hata ciktisi gizli)'
Assert-True ($cs -match 'if %MM_COLS% LSS 40 set "MM_COLS=80"' -and $cs -match 'if %MM_COLS% GTR 400 set "MM_COLS=80"') 'makul olmayan genislik 80 sayilir'
$iOr = [array]::IndexOf($lines, ':orta')
$or = ($lines[$iOr..($iOb - 1)]) -join "`n"
Assert-True ($or -match 'set /a MM_N=\(MM_COLS-%~1\)/2') 'sol bosluk (sutun - metin) / 2'
Assert-True ($or -match 'if %MM_N% LSS 0 set "MM_N=0"' -and $or -match 'if %MM_N% GTR 120 set "MM_N=120"') 'bosluk 0 ile 120 arasinda sinirlanir'
Assert-True ($or -match 'call set "MM_PAD=%%MM_SP:~0,%MM_N%%%"') 'bosluk dizgisi alt dizgiyle uretilir (dongu yok, hizli)'
Assert-True ($or -match '(?m)^set "MM_SP=\s{10}"\s*$') 'bosluk kaynagi 10 bosluk, sonra buyutulur'
# yuksek DPI: yalnizca acilis ekranini baslatan satirin etrafinda ayarlanir ve hemen temizlenir
$iAb = [array]::IndexOf($lines, ':acilis_baslat')
$iAbe = [array]::IndexOf($lines, ':acilis_bekle')
$ab = @($lines[$iAb..($iAbe - 1)])
$iSet = -1; $iStart = -1; $iClr = -1
for ($i = 0; $i -lt $ab.Count; $i++) {
    if ($ab[$i] -eq 'set "__COMPAT_LAYER=HIGHDPIAWARE"') { $iSet = $i }
    if ($ab[$i] -match '^start "" /min "%MM_PSEXE%".*-File "%MM_ACILIS%"') { $iStart = $i }
    if ($ab[$i] -eq 'set "__COMPAT_LAYER="') { $iClr = $i }
}
Assert-True ($iSet -ge 0 -and $iStart -gt $iSet -and $iClr -gt $iStart) 'HIGHDPIAWARE yalnizca Acilis.ps1 baslatilirken ayarlanir ve hemen sonra temizlenir'
Assert-Eq ([regex]::Matches($text, '__COMPAT_LAYER')).Count 2 '__COMPAT_LAYER baska yerde kullanilmaz (uygulama ve alt surecler etkilenmez)'

# ---- parantezli blok yok: yolda ")" olan klasorlerde (Program Files (x86) gibi) blok icindeki %~dp0 acilimi bozulurdu
$blocks = @($lines | Where-Object { $_ -match '\(\s*$' -and $_ -notmatch '^\s*rem\b' })
Assert-Eq $blocks.Count 0 'parantezli blok kullanilmamis'

# ---- icerik
Assert-Eq $lines[0] '@echo off' 'ilk satir @echo off'
Assert-True ($text -match '(?m)^setlocal EnableExtensions') 'setlocal EnableExtensions'
Assert-True ($text -match '(?i)-NoProfile -ExecutionPolicy Bypass -STA -File "%MM_PS1%" %MM_ARGS%') 'betik dogru parametrelerle calisir'
Assert-True ($text -match '(?i)fltmc') 'yonetici denetimi (fltmc; Server hizmeti kapaliyken de calisir)'
Assert-True ($text -notmatch '(?im)^\s*net session') 'net session kullanilmaz (Server hizmeti kapaliysa yanlis sonuc verir)'
Assert-True ($text -match '/yukseltildi') 'yukseltme korumasi (sonsuz dongu onleme)'
Assert-True ($text -match '(?i)-Verb RunAs') 'yonetici olarak yeniden aciliyor'
Assert-True ($text -match '(?i)-File "%MM_TANI%" -ExitCode %MM_RC% -Mod %MM_MOD%') 'tanilama cikis koduyla cagrilir'
Assert-True ($text -match '(?m)^endlocal & exit /b %MM_RC%\s*$') 'cikis kodu korunur'
# Eski hata: her hatada "yonetici izni verilmedi" yazmak. Bu metin yalnizca UAC reddedildiginde gosterilen bolumde olabilir.
$ix = [array]::IndexOf($lines, ':calistir')
$iy = [array]::IndexOf($lines, ':betik_yok')
Assert-True ($ix -gt 0 -and $iy -gt $ix) 'calistir bolumu bulundu'
$run = ($lines[$ix..($iy - 1)]) -join "`n"
Assert-True ($run -notmatch '(?i)izni verilmedi|yonetici izni') 'betik hatasi "yonetici izni" diye yorumlanmaz'
$ip = [array]::IndexOf($lines, ':izin_yok')
$izin = ($lines[$ip..($lines.Count - 1)]) -join "`n"
Assert-True ($izin -match '(?i)izni verilmedi') 'izin metni yalnizca UAC reddi bolumunde'

# ---- yukseltme komutu: -Command metni PowerShell tarafindan dogru okunuyor ve beklenen arguman dizgisini uretiyor
$m = [regex]::Match($text, '(?m)^"%MM_PSEXE%" -NoProfile -ExecutionPolicy Bypass -Command "(?<cmd>[^"]+)"\s*$')
Assert-True $m.Success 'yukseltme -Command metni bulundu'
$cmd = $m.Groups['cmd'].Value
$tok = $null; $err = $null
[void][System.Management.Automation.Language.Parser]::ParseInput($cmd, [ref]$tok, [ref]$err)
Assert-Eq @($err).Count 0 'yukseltme komutu soz dizimi temiz'
Assert-True ($cmd -notmatch '"') '-Command metninde cift tirnak yok (cmd ile PowerShell tirnak catismasi olmaz)'
Assert-True ($cmd -notmatch '%') '-Command metninde yuzde isareti yok'

$pw = (Get-Process -Id $PID).Path
$stub = 'function Start-Process { param($FilePath, $ArgumentList, $Verb, $ErrorAction) [Console]::Out.WriteLine(''FILE='' + $FilePath); [Console]::Out.WriteLine(''ARGS='' + $ArgumentList); [Console]::Out.WriteLine(''VERB='' + $Verb) }; $env:ComSpec = ''cmd.exe''; '
$env:MM_SELF = 'C:\Users\Kullanici\Masa ustu (x86)\Multimizer\Baslat.bat'
$env:MM_ARGS = '-Cli -Gorev Durum'
$out = @(& $pw -NoProfile -Command ($stub + $cmd))
$rc = $LASTEXITCODE
Assert-Eq $rc 0 'yukseltme komutu hatasiz biter'
Assert-True ($out -contains 'FILE=cmd.exe') 'cmd.exe baslatilir'
Assert-True ($out -contains 'VERB=RunAs') 'RunAs ile baslatilir'
Assert-True ($out -contains 'ARGS=/c ""C:\Users\Kullanici\Masa ustu (x86)\Multimizer\Baslat.bat" /yukseltildi -Cli -Gorev Durum"') 'cmd /c arguman dizgisi: dis tirnaklar cmd kuralina uygun, bosluk ve parantezli yol korunur'
$env:MM_ARGS = ''
$out = @(& $pw -NoProfile -Command ($stub + $cmd))
Assert-True ($out -contains 'ARGS=/c ""C:\Users\Kullanici\Masa ustu (x86)\Multimizer\Baslat.bat" /yukseltildi "') 'parametresiz cagri da dogru'
# UAC reddedilirse (Start-Process hata verir) cikis kodu 3 olmali; bat bunu "izin verilmedi" diye gosterir
$stubFail = 'function Start-Process { param($FilePath, $ArgumentList, $Verb, $ErrorAction) throw ''The operation was canceled by the user.'' }; $env:ComSpec = ''cmd.exe''; '
$out = @(& $pw -NoProfile -Command ($stubFail + $cmd))
Assert-Eq $LASTEXITCODE 3 'UAC reddi: cikis kodu 3'
Remove-Item Env:MM_SELF, Env:MM_ARGS -ErrorAction SilentlyContinue

# ---- 7.2.1: pencere acildiktan sonra cokme (negatif cikis kodu) -> acilis sorunu gibi gosterilmez, guvenli kipte bir kez yeniden denenir
Assert-True ($text -match '(?m)^:baslat_yinele\s*$') 'yeniden deneme etiketi var'
Assert-True ($text -match '(?i)set "MM_RUN=%RANDOM%%RANDOM%%RANDOM%"') 'her calistirmaya benzersiz kod verilir'
Assert-True ($text -match '(?i)if /i "%MM_MOD%"=="Gui" set "MM_TOK=-Oturum %MM_RUN%"') 'kod yalnizca arayuz kipinde betige gecer'
Assert-True ($text -match '(?i)-File "%MM_PS1%" %MM_ARGS% %MM_TOK%') 'betik kodla calistirilir'
Assert-True ($text -match '(?i)set "MM_MARK=%ProgramData%\\Multimizer\\oturum-acik-%MM_RUN%\.txt"') 'isaret dosyasi yolu uygulamanin yazdigiyla ayni'
Assert-True ($text -match '(?i)if defined MM_MARK if exist "%MM_MARK%" goto :cokme') 'isaret dosyasi varsa cokme bolumune gidilir'
$ic = [array]::IndexOf($lines, ':cokme')
$ie = [array]::IndexOf($lines, ':ikinci_cokme')
Assert-True ($ic -gt 0 -and $ie -gt $ic) 'cokme bolumu bulundu'
$ck = ($lines[$ic..($ie - 1)]) -join "`n"
Assert-True ($ck -match '(?i)del "%MM_MARK%"') 'isaret dosyasi silinir'
Assert-True ($ck -match '(?i)if %MM_RC% GEQ 0 goto :tani_ac') 'yalnizca negatif (Windows cokme) kodlarinda yeniden baslatilir; Gorev Yoneticisi ile sonlandirmada baslatilmaz'
Assert-True ($ck -match '(?i)choice /c AV /n /t 8 /d A') 'vazgecme firsati: 8 sn sonra kendiliginden devam'
Assert-True ($ck -match '(?i)set "MM_ARGS=%MM_ARGS% -Guvenli"') 'yeniden baslatma -Guvenli ile'
Assert-True ($ck -match '(?i)set "MM_RETRY=1"') 'yeniden deneme bir kez ile sinirli'
Assert-True ($ck -match '(?i)if not "%MM_RETRY%"=="0" goto :ikinci_cokme') 'ikinci cokmede yeniden denenmez'
Assert-True ($text -match '(?i)if /i "%MM_MOD%"=="Gui" if "%MM_RC%"=="-1073741510" goto :cik') 'konsol penceresi kapatilinca (0xC000013A) hata gosterilmez'
$ir = [array]::IndexOf($lines, ':baslat_yinele')
Assert-True ($ir -gt $ix -and $ir -lt $ic) 'yeniden deneme noktasi calistir bolumunun icinde'
Assert-True ($text -match '(?i)^set "MM_RETRY=0"' -or $text -match '(?im)^set "MM_RETRY=0"') 'yeniden deneme sayaci baslangicta sifir'

Show-Result
