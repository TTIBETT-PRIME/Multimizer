@echo off
rem ---------------------------------------------------------------
rem  Duman testinin yalnizca saydamlik bolumu: Mica, Akrilik ve Seffaf secenekleriyle opaklik adimlarini her temada dener; pencerenin ekrandaki gercek goruntusunu kaydeder. Yaklasik 3 dakika surer.
rem  Sonuc ve cikis kodlari Duman-Testi.cmd ile aynidir (%TEMP%\Multimizer-duman.txt).
rem  Bu dosya yalnizca ASCII karakter icerir ve satir sonlari CRLF olmalidir.
rem ---------------------------------------------------------------
set "MM_DUMAN_KAPSAM=saydam"
call "%~dp0Duman-Testi.cmd" %*
exit /b %errorlevel%
