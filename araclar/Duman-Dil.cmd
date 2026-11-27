@echo off
setlocal EnableExtensions
title Multimizer dil denetimi
rem ---------------------------------------------------------------
rem  Dil denetimi: duman testinin "dil" kapsamini her dil icin ayri calistirir. Her sayfayi ve sekmeyi gezer, ekran goruntusu alir;
rem  cevirisi unutulmus metinleri (SIZINTI) ve ekrana sigmayan ya da kirpilan metinleri (KESIK) listeler.
rem  Varsayilan diller: tr (karsilastirma), en, de, zh, ja, ar. Baska dil icin dil kodlarini yazin:  Duman-Dil.cmd fr es
rem  "/sessiz" verilirse sonunda beklemez. Yonetici izni gerekmez; hicbir sistem ayarina dokunmaz.
rem  Her dil yaklasik 5-10 dakika surer; bitene kadar pencereye dokunmayin.
rem  Sonuc      : %TEMP%\Multimizer-dil-denetimi\<dil>\  (Multimizer-duman.txt, Multimizer-duman-dil.txt, Multimizer-dil-eksik.txt, ekran\*.png)
rem  Ozet       : %TEMP%\Multimizer-dil-denetimi\ozet.txt
rem  Cikis kodu : 0 = temiz, 2 = en az bir dilde hata var
rem  Bu dosya yalnizca ASCII karakter icerir ve satir sonlari CRLF olmalidir.
rem  Not: shift komutu betik adini da kaydirir; bu yuzden klasor yolu en basta MM_HERE degiskenine alinir.
rem ---------------------------------------------------------------
set "MM_HERE=%~dp0"
set "MM_QUIET="
set "MM_LANGS="
set "MM_ROOT=%TEMP%\Multimizer-dil-denetimi"
set "MM_BAD=0"

:arg
if "%~1"=="" goto :arg_bitti
if /i "%~1"=="/sessiz" set "MM_QUIET=1"& shift & goto :arg
echo %~1| findstr /r /i "^[a-z-][a-z-]*$" >nul
if errorlevel 1 goto :arg_atla
set "MM_LANGS=%MM_LANGS% %~1"
:arg_atla
shift
goto :arg

:arg_bitti
if "%MM_LANGS%"=="" set "MM_LANGS=tr en de zh ja ar"
if not exist "%MM_HERE%..\Multimizer.ps1" goto :betik_yok
if not exist "%MM_ROOT%" mkdir "%MM_ROOT%" >nul 2>&1
echo Multimizer dil denetimi > "%MM_ROOT%\ozet.txt"
echo.
echo  Dil denetimi basliyor (%MM_LANGS% ). Pencere kendi kendine gezecek; bitene kadar dokunmayin.
for %%L in (%MM_LANGS%) do call :bir %%L
echo.
echo  Tamamlandi. Ayrinti: %MM_ROOT%
echo.
if /i not "%MM_QUIET%"=="1" pause
exit /b %MM_BAD%

:bir
set "MM_DIL=%~1"
set "MM_DIL_IZLE=1"
set "MM_DUMAN_KAPSAM=dil"
set "MM_D=%MM_ROOT%\%~1"
del "%TEMP%\Multimizer-duman-dil.txt" >nul 2>&1
del "%TEMP%\Multimizer-dil-eksik.txt" >nul 2>&1
echo.
echo  [%~1] baslatiliyor...
call "%MM_HERE%Duman-Testi.cmd" /sessiz
set "MM_RC=%errorlevel%"
if exist "%MM_D%" rmdir /s /q "%MM_D%" >nul 2>&1
mkdir "%MM_D%" >nul 2>&1
copy /y "%TEMP%\Multimizer-duman.txt" "%MM_D%\" >nul 2>&1
copy /y "%TEMP%\Multimizer-duman-dil.txt" "%MM_D%\" >nul 2>&1
copy /y "%TEMP%\Multimizer-dil-eksik.txt" "%MM_D%\" >nul 2>&1
xcopy /e /i /y /q "%TEMP%\Multimizer-duman\ekran" "%MM_D%\ekran" >nul 2>&1
echo [%~1] cikis kodu %MM_RC% >> "%MM_ROOT%\ozet.txt"
if exist "%TEMP%\Multimizer-duman-dil.txt" findstr /b /c:"OZET" "%TEMP%\Multimizer-duman-dil.txt" >> "%MM_ROOT%\ozet.txt"
if exist "%TEMP%\Multimizer-duman-dil.txt" findstr /b /c:"OZET" "%TEMP%\Multimizer-duman-dil.txt"
if not "%MM_RC%"=="0" set "MM_BAD=2"
exit /b 0

:betik_yok
echo.
echo  HATA: Multimizer.ps1 bulunamadi. ZIP dosyasinin tamamini bir klasore cikartin.
echo.
if /i not "%MM_QUIET%"=="1" pause
exit /b 1
