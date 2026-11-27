@echo off
setlocal EnableExtensions
title Multimizer
rem ---------------------------------------------------------------
rem  Multimizer - baslatici
rem   1) Arayuz kipinde ayri konsol penceresi acmaz: Acilis.ps1 uygulamanin kendi acilis ekranini gosterir, yonetici izni ister
rem      ve Multimizer.ps1 dosyasini gizli konsolla calistirir. Bu pencere yalnizca simge durumunda ve birkac saniyeligine kalir.
rem   2) Komut satiri kiplerinde (-Cli, -OzTest, -Duman), /tani ve /gorunur ile konsol penceresi gorunur kalir (cikti okunabilsin).
rem   3) Acilamazsa nedenini Tani.ps1 ile bulup gosterir (Defender engeli dahil).
rem  Ek parametreler betige aktarilir, ornek:   Baslat.bat -OzTest
rem  Yalnizca tanilama calistirmak icin:         Baslat.bat /tani
rem  Konsol penceresini gorunur tutmak icin (sorun giderme): Baslat.bat /gorunur
rem  Kendi kendini sinama (pencere acar, gezer, rapor yazar): Baslat.bat -Duman
rem  Yutulan hatalar dahil ayrintili hata gunlugu (Kayitlar\ayrinti-GUN.txt): Baslat.bat -DebugLog
rem  Pencere acildiktan sonra uygulama coker (negatif cikis kodu) ise guvenli kipte (yazilimsal cizim) bir kez yeniden baslatilir.
rem  Bu dosya yalnizca ASCII karakter icerir ve satir sonlari CRLF olmalidir.
rem ---------------------------------------------------------------
set "MM_PS1=%~dp0Multimizer.ps1"
set "MM_TANI=%~dp0Tani.ps1"
set "MM_ACILIS=%~dp0Acilis.ps1"
set "MM_SELF=%~f0"
set "MM_PSEXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "MM_ARGS=%*"
set "MM_ELEV="
set "MM_INNER="
set "MM_KLASIK="
set "MM_HS="
set "MM_MOD=Gui"
set "MM_RC=0"
set "MM_RETRY=0"
set "MM_TOK="
set "MM_MARK="

if /i "%~1"=="/yukseltildi" set "MM_ELEV=1"
if defined MM_ELEV set "MM_ARGS=%MM_ARGS:/yukseltildi=%"
if /i "%~1"=="/mmic" set "MM_INNER=1"
if defined MM_INNER set "MM_ARGS=%MM_ARGS:/mmic=%"
if /i "%~1"=="/gorunur" set "MM_KLASIK=1"
if defined MM_KLASIK set "MM_ARGS=%MM_ARGS:/gorunur=%"

if not exist "%MM_PS1%" goto :betik_yok

rem --- arayuz kipi: pencere acmadan baslat. Acilis.ps1 acilis ekranini gosterir, yonetici iznini ister ve uygulamayi izler.
rem     Komut satiri kipleri, /tani, /gorunur, yukseltilmis yeniden acis ve Acilis.ps1 yoksa klasik (gorunur konsol) akis calisir.
if defined MM_ELEV goto :klasik
if defined MM_KLASIK goto :klasik
if not exist "%MM_ACILIS%" goto :klasik
echo %MM_ARGS% | findstr /i /c:"/tani" /c:"-Cli" /c:"-OzTest" /c:"-Duman" >nul
if not errorlevel 1 goto :klasik
if defined MM_INNER goto :acilis_baslat
rem  Kendini simge durumunda yeniden ac: siyah konsol penceresi gozden kaybolur (gorev cubugunda kisa sure bir dugme kalir)
start "" /min "%ComSpec%" /d /c ""%MM_SELF%" /mmic %MM_ARGS%"
set "MM_RC=0"
goto :cik

:acilis_baslat
set "MM_RUN=%RANDOM%%RANDOM%%RANDOM%"
set "MM_HS=%TEMP%\mm-basladi-%MM_RUN%.txt"
del "%MM_HS%" >nul 2>&1
rem  Acilis ekrani yuksek DPI duyarli acilir (olcekli ekranlarda keskin cizim); Acilis.ps1 bu ayari alt sureclere aktarmaz
set "__COMPAT_LAYER=HIGHDPIAWARE"
start "" /min "%MM_PSEXE%" -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%MM_ACILIS%" -Kod %MM_RUN% %MM_ARGS%
set "__COMPAT_LAYER="
set "MM_N=0"

:acilis_bekle
rem  Acilis.ps1 ilk satirlarinda el sikisma dosyasini yazar; gelirse bu pencere kapanir (en cok 45 sn beklenir)
if exist "%MM_HS%" goto :acilis_tamam
set /a MM_N+=1
if %MM_N% GEQ 45 goto :acilis_yok
ping -n 2 127.0.0.1 >nul 2>&1
goto :acilis_bekle

:acilis_tamam
del "%MM_HS%" >nul 2>&1
set "MM_RC=0"
goto :cik

:acilis_yok
rem  Gizli baslatma haber vermedi: ayni istek gorunur konsolla (klasik akis) yeniden denenir
start "" "%ComSpec%" /d /c ""%MM_SELF%" /gorunur %MM_ARGS%"
set "MM_RC=0"
goto :cik

:klasik
rem --- yonetici degilse: bu dosyayi yonetici olarak yeniden ac
fltmc >nul 2>&1
if not errorlevel 1 goto :calistir
if defined MM_ELEV goto :calistir
call :konsol_sutun
call :orta 55
echo.
echo %MM_PAD%Yonetici izni isteniyor. Acilan pencerede "Evet" deyin.
"%MM_PSEXE%" -NoProfile -ExecutionPolicy Bypass -Command "$q=[char]34; $a='/c ' + $q + $q + $env:MM_SELF + $q + ' /yukseltildi ' + $env:MM_ARGS + $q; try { Start-Process -FilePath $env:ComSpec -ArgumentList $a -Verb RunAs -ErrorAction Stop } catch { exit 3 }"
if errorlevel 1 goto :izin_yok
goto :cik

:calistir
echo %MM_ARGS% | findstr /i /c:"/tani" >nul
if not errorlevel 1 goto :tani_elle
echo %MM_ARGS% | findstr /i /c:"-Cli" /c:"-OzTest" /c:"-Duman" >nul
if not errorlevel 1 set "MM_MOD=Komut"
rem  Arayuz kipinde: PowerShell betigi okunurken (1-2 sn) bos ekran gorunmesin; Multimizer.ps1 kendi acilis ekranini cizerken bu basligi siler
if /i "%MM_MOD%"=="Gui" set "MM_PREBANNER=1"
if /i "%MM_MOD%"=="Gui" call :onbaslik

:baslat_yinele
rem  Arayuz kipinde her calistirmaya benzersiz bir kod verilir: uygulama pencereyi actiginda oturum-acik-KOD.txt yazar, duzgun kapanista siler.
rem  Cikista dosya duruyorsa pencere acilmis ve uygulama sonradan beklenmedik sekilde sonlanmistir (acilis sorunu degildir).
if /i "%MM_MOD%"=="Gui" set "MM_RUN=%RANDOM%%RANDOM%%RANDOM%"
if /i "%MM_MOD%"=="Gui" set "MM_TOK=-Oturum %MM_RUN%"
if /i "%MM_MOD%"=="Gui" set "MM_MARK=%ProgramData%\Multimizer\oturum-acik-%MM_RUN%.txt"
"%MM_PSEXE%" -NoProfile -ExecutionPolicy Bypass -STA -File "%MM_PS1%" %MM_ARGS% %MM_TOK%
set "MM_RC=%errorlevel%"
if "%MM_RC%"=="0" goto :cik
rem  Komut satiri kipinde 2 (kritik bulgu) ve 3 (baska gorev calisiyor) uygulamanin kendi sonuc kodlaridir
if /i "%MM_MOD%"=="Komut" if "%MM_RC%"=="2" goto :cik
if /i "%MM_MOD%"=="Komut" if "%MM_RC%"=="3" goto :cik
rem  Konsol penceresi kapatildi (0xC000013A): hata degil
if /i "%MM_MOD%"=="Gui" if "%MM_RC%"=="-1073741510" goto :cik
if /i "%MM_MOD%"=="Gui" if defined MM_MARK if exist "%MM_MARK%" goto :cokme
if /i not "%MM_MOD%"=="Komut" echo.
if /i not "%MM_MOD%"=="Komut" echo  Multimizer acilamadi ya da beklenmedik sekilde kapandi ^(cikis kodu %MM_RC%^). Neden araniyor...
goto :tani_ac

:cokme
del "%MM_MARK%" >nul 2>&1
echo.
echo  Multimizer calisirken beklenmedik sekilde kapandi ^(cikis kodu %MM_RC%^).
echo  Pencere acilmisti; bu bir acilis sorunu degil, calisma sirasinda olusan bir cokmedir.
rem  Negatif kodlar Windows'un verdigi cokme kodlaridir; 1 gibi pozitif kodlar Gorev Yoneticisi ile sonlandirmadir (yeniden baslatilmaz).
if %MM_RC% GEQ 0 goto :tani_ac
if not "%MM_RETRY%"=="0" goto :ikinci_cokme
echo.
echo  Guvenli kipte ^(yazilimsal cizim, GPU ve sicaklik izleme kapali^) yeniden baslatiliyor.
choice /c AV /n /t 8 /d A /m "  Vazgecmek icin V, hemen baslatmak icin A tusuna basin (8 sn sonra kendiliginden baslar): "
if errorlevel 2 goto :tani_ac
set "MM_RETRY=1"
set "MM_ARGS=%MM_ARGS% -Guvenli"
goto :baslat_yinele

:ikinci_cokme
echo  Guvenli kipte de kapandi; yeniden denenmiyor. Neden araniyor...
goto :tani_ac

:tani_elle
set "MM_MOD=Elle"
set "MM_RC=0"

:tani_ac
if not exist "%MM_TANI%" goto :tani_yok
"%MM_PSEXE%" -NoProfile -ExecutionPolicy Bypass -File "%MM_TANI%" -ExitCode %MM_RC% -Mod %MM_MOD%
rem  Komut kipinde Tani.ps1 bir sey bulmazsa (cikis kodu 0) sessizce kapanir
if /i "%MM_MOD%"=="Komut" if not errorlevel 10 goto :cik
echo.
pause
goto :cik

:tani_yok
echo.
echo  Tani.ps1 bulunamadi. ZIP dosyasinin tamamini bir klasore cikartin.
echo.
pause
goto :cik

:betik_yok
echo.
echo  HATA: Multimizer.ps1 bulunamadi.
echo  ZIP dosyasini once bir klasore cikartin ve Baslat.bat dosyasini
echo  Multimizer.ps1 ile ayni klasorde calistirin.
echo.
pause
set "MM_RC=1"
goto :cik

:izin_yok
echo.
echo  Yonetici izni verilmedi ya da pencere kapatildi.
echo  Multimizer sistem ayarlarini yonetebilmek icin yonetici izni ister.
echo  Baslat.bat dosyasini yeniden acin ve izin penceresinde "Evet" deyin.
echo.
pause
set "MM_RC=1"
goto :cik

:konsol_sutun
rem  Konsolun sutun sayisi (MM_COLS). "mode con" ciktisinda etiketler dile gore degisir, sira degismez: rakamli ikinci satir sutun sayisidir. Okunamazsa 80.
set "MM_COLS=80"
set "MM_I=0"
for /f "tokens=2 delims=: " %%a in ('mode con 2^>nul ^| findstr /r "[0-9]"') do call :sutun_say %%a
set /a MM_COLS=MM_COLS+0
if %MM_COLS% LSS 40 set "MM_COLS=80"
if %MM_COLS% GTR 400 set "MM_COLS=80"
exit /b 0

:sutun_say
set /a MM_I+=1
if %MM_I%==2 set "MM_COLS=%~1"
exit /b 0

:orta
rem  %1 = metnin uzunlugu. MM_PAD = metni MM_COLS sutunluk konsolda ortalamak icin gereken sol bosluk (once :konsol_sutun cagrilmali)
set "MM_SP=          "
set "MM_SP=%MM_SP%%MM_SP%%MM_SP%%MM_SP%"
set "MM_SP=%MM_SP%%MM_SP%%MM_SP%"
set /a MM_N=(MM_COLS-%~1)/2
if %MM_N% LSS 0 set "MM_N=0"
if %MM_N% GTR 120 set "MM_N=120"
set "MM_PAD="
if %MM_N% GTR 0 call set "MM_PAD=%%MM_SP:~0,%MM_N%%%"
exit /b 0

:onbaslik
call :konsol_sutun
echo.
call :orta 19
echo %MM_PAD%M U L T I M I Z E R
call :orta 37
echo %MM_PAD%Arac baslatiliyor, lutfen bekleyin...
call :orta 28
echo %MM_PAD%[!] Bu pencereyi kapatmayin.
echo.
exit /b 0

:cik
endlocal & exit /b %MM_RC%
