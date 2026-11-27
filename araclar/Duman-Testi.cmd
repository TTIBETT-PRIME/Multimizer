@echo off
setlocal EnableExtensions
title Multimizer duman testi
rem ---------------------------------------------------------------
rem  Multimizer duman testi: arayuzu acar, her temada her sayfayi gezer, Ayarlar'daki tema dugmelerine gercekten tiklar,
rem  salt okunur tarama ve onizleme dugmelerine basar, ekran goruntusu alir ve sonucu yazar.
rem  Yonetici izni gerekmez; hicbir sistem ayarina dokunmaz; ayarlar ve gunlukler %TEMP%\Multimizer-duman\veri altinda calisir.
rem  Sonuc      : %TEMP%\Multimizer-duman.txt
rem  Goruntuler : %TEMP%\Multimizer-duman\ekran
rem  Cikis kodu : 0 = temiz, 2 = hata var, 3 = zaman asimi
rem  Yaklasik 10-15 dakika surer; bitene kadar pencereye dokunmayin. "/sessiz" verilirse sonunda beklemez.
rem  Bu dosya yalnizca ASCII karakter icerir ve satir sonlari CRLF olmalidir.
rem ---------------------------------------------------------------
set "MM_PS1=%~dp0..\Multimizer.ps1"
set "MM_OUT=%TEMP%\Multimizer-duman-sonuc.txt"
if not exist "%MM_PS1%" goto :betik_yok
del "%MM_OUT%" >nul 2>&1
echo.
echo  Duman testi basliyor. Pencere kendi kendine gezecek; bitene kadar dokunmayin.
echo  Durdurmak icin bu konsol penceresini kapatin (Ctrl+C ve uygulamanin X dugmesi yok sayilir).
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -STA -File "%MM_PS1%" -Duman
set "MM_RC=%errorlevel%"
echo cikis kodu: %MM_RC% > "%MM_OUT%"
echo.
if "%MM_RC%"=="0" goto :temiz
echo  SONUC: HATA VAR ^(cikis kodu %MM_RC%^)
goto :ayrinti

:temiz
echo  SONUC: TEMIZ

:ayrinti
echo  Ayrinti: %TEMP%\Multimizer-duman.txt
echo.
if /i not "%~1"=="/sessiz" pause
exit /b %MM_RC%

:betik_yok
echo.
echo  HATA: Multimizer.ps1 bulunamadi. ZIP dosyasinin tamamini bir klasore cikartin.
echo.
if /i not "%~1"=="/sessiz" pause
exit /b 1
