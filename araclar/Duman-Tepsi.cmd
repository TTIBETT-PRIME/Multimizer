@echo off
rem ---------------------------------------------------------------
rem  Duman testinin yalnizca tepsi bolumu: simge durumuna kucultme, X dugmesi (islem surerken de), ikinci acilis sinyali ve geri getirme.
rem  Yaklasik 2 dakika surer. Sonuc ve cikis kodlari Duman-Testi.cmd ile aynidir (%TEMP%\Multimizer-duman.txt).
rem  Bu dosya yalnizca ASCII karakter icerir ve satir sonlari CRLF olmalidir.
rem ---------------------------------------------------------------
set "MM_DUMAN_KAPSAM=tepsi"
call "%~dp0Duman-Testi.cmd" %*
exit /b %errorlevel%
