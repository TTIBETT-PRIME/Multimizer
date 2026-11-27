@echo off
rem ---------------------------------------------------------------
rem  Duman testinin yalnizca gorunum bolumu: her temada her sayfayi acar, tema dugmelerine ve hazir gorunumlere tiklar, ekran goruntusu alir.
rem  Yaklasik 5 dakika surer. Sonuc ve cikis kodlari Duman-Testi.cmd ile aynidir (%TEMP%\Multimizer-duman.txt).
rem  Bu dosya yalnizca ASCII karakter icerir ve satir sonlari CRLF olmalidir.
rem ---------------------------------------------------------------
set "MM_DUMAN_KAPSAM=gorunum"
call "%~dp0Duman-Testi.cmd" %*
exit /b %errorlevel%
