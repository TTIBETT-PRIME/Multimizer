@echo off
rem ---------------------------------------------------------------
rem  Multimizer ozellik denetimi, YALNIZCA OKUMA: hicbir ayar yazilmaz. Her ayarin olcumu ve onizlemesi, araclarin gecici klasorde denemesi,
rem  salt-okunur arka plan islerinin calistirilmasi ve Windows ile karsilastirmalar yapilir. Yonetici izni gerekmez (gerekirse bazi okumalar atlanir).
rem  Sonuc : %TEMP%\Multimizer-duman.txt  ve  %TEMP%\Multimizer-duman-ozellik.tsv
rem  Bu dosya yalnizca ASCII karakter icerir ve satir sonlari CRLF olmalidir.
rem ---------------------------------------------------------------
set "MM_DUMAN_KAPSAM=ozellik"
set "MM_OZELLIK_KIP=oku"
call "%~dp0Duman-Testi.cmd" %*
exit /b %errorlevel%
