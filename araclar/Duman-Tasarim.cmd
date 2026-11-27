@echo off
rem ---------------------------------------------------------------
rem  Duman testinin yalnizca tasarim bolumu: bes tasarimi, menu bicimlerini, ana ekran panosunu (duzenleme, parca ekleme/kaldirma), hazir gorunumleri ve her temada ana ekrani dener. Yaklasik 4 dakika surer.
rem  Sonuc ve cikis kodlari Duman-Testi.cmd ile aynidir (%TEMP%\Multimizer-duman.txt).
rem  Bu dosya yalnizca ASCII karakter icerir ve satir sonlari CRLF olmalidir.
rem ---------------------------------------------------------------
set "MM_DUMAN_KAPSAM=tasarim"
call "%~dp0Duman-Testi.cmd" %*
exit /b %errorlevel%
