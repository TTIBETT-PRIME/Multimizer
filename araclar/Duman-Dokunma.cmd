@echo off
rem ---------------------------------------------------------------
rem  Duman testinin yalnizca dokunma hedefleri bolumu: Ayarlar > Gorunum > Dokunma hedefleri "Buyuk" iken her sayfayi ve alt sekmeyi
rem  gezer, Kompakt yerlesimi de dener; erisilebilirlik raporunda Buyuk kipte 24 px alti ve 32 px alti hedef sayisi ayri yazilir.
rem  Yaklasik 5 dakika surer. Sonuc ve cikis kodlari Duman-Testi.cmd ile aynidir (%TEMP%\Multimizer-duman.txt).
rem  Bu dosya yalnizca ASCII karakter icerir ve satir sonlari CRLF olmalidir.
rem ---------------------------------------------------------------
set "MM_DUMAN_KAPSAM=dokunma"
call "%~dp0Duman-Testi.cmd" %*
exit /b %errorlevel%
