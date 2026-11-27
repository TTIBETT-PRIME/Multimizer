@echo off
rem ---------------------------------------------------------------
rem  Duman testinin yalnizca ust cubuk bolumu: ana sayfa dugmesine (amblem) ve dil dugmesine tiklar, dil listesini acip ekran goruntusu alir.
rem  Yaklasik 1 dakika surer. Sonuc ve cikis kodlari Duman-Testi.cmd ile aynidir (%TEMP%\Multimizer-duman.txt).
rem  Bu dosya yalnizca ASCII karakter icerir ve satir sonlari CRLF olmalidir.
rem ---------------------------------------------------------------
set "MM_DUMAN_KAPSAM=ust"
call "%~dp0Duman-Testi.cmd" %*
exit /b %errorlevel%
