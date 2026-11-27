@echo off
rem ---------------------------------------------------------------
rem  Duman testinin yalnizca kullanim kolayligi bolumu: Asistan, sol cubuk alt sekme menusu, Yardimcilar sekmesi, kisa aciklamalar.
rem  Yaklasik 1 dakika surer. Fareyi oynatmaz, panoya ve ayarlara dokunmaz. Sonuc ve cikis kodlari Duman-Testi.cmd ile aynidir.
rem  Bu dosya yalnizca ASCII karakter icerir ve satir sonlari CRLF olmalidir.
rem ---------------------------------------------------------------
set "MM_DUMAN_KAPSAM=kullanim"
call "%~dp0Duman-Testi.cmd" %*
exit /b %errorlevel%
