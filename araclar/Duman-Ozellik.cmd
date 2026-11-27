@echo off
rem ---------------------------------------------------------------
rem  Multimizer TAM ozellik denetimi (yonetici izni ister). Her ozelligi bu bilgisayarda gercekten dener:
rem  ayari uygular, Windows'tan bagimsiz okuyarak dogrular, geri alir, eski halle karsilastirir; araclari gecici klasorde sinar.
rem  Her degisiklikten once eski durum %TEMP%\Multimizer-duman-geri altina yazilir; surec oluse bile bir sonraki acilista geri yuklenir.
rem  Temizlik islemleri (gecici dosya, onbellek, gunluk, DISM, Disk Temizleme) gercekten calisir ve ikinci onizlemeyle dogrulanir;
rem  Geri Donusum Kutusu yalnizca bossa bosaltilir, eski kurtarma noktalari hic silinmez. Windows bileseni (XPS Goruntuleyici,
rem  Adim Kaydedicisi gibi) kaldirma turu varsayilan olarak yalnizca onizlenir: kaldirilan bilesen yalnizca Windows Update'ten
rem  geri kurulur ve icerik her zaman bulunmaz (18.11.2026'da bu bilgisayarda 0x800F0950 ile geri kurulamadi). Bilerek
rem  denemek icin bu dosyayi "set MM_BILESEN_CANLI=1" yazilmis bir komut isteminden calistirin (internet gerekir).
rem  Butun Windows ozellikleri denetime girer: hafifler (Is Klasorleri, IPP, SMB1...) gercekten acilip/kapatilip geri alinir;
rem  agirlar (WSL, Sanal Makine Platformu, Hyper-V, .NET 3.5, DirectPlay) kapaliysa gercekten acilip yeniden kapatilir. ACIK bir
rem  agir ozellik varsayilan olarak KAPATILMAZ (durumu okunur ve onizlenir): geri acmak dosyalarini Windows Update'ten indirmeyi
rem  gerektirebilir; 17.11.2026'da bu bilgisayarda Sanal Makine Platformu boyle saatlerce geri acilamadi. Bilerek denemek icin
rem  bu dosyayi "set MM_OZELLIK_AGIR=1" yazilmis bir komut isteminden calistirin (secim yonetici penceresine aktarilir).
rem  Bir kez geri yuklenemeyen ozellik/bilesen
rem  ozellik-riskli.json listesine yazilir ve bir daha degistirilmez. Windows Update guncelleme kuruyorsa, Windows yeniden
rem  baslatma bekliyorsa ya da bilesen hizmeti onceki isi surduruyorsa ozellik/bilesen turu baslamaz (once yeniden baslatin);
rem  DISM en cok 15 dakika beklenir, asilirsa kalan turlar yapilmaz. Geri yuklenemeyen degisiklik kurtarma listesine yazilir
rem  (sonraki tam denetimin basinda yeniden denenir). Denetim bitince bilgisayari bir kez yeniden baslatin.
rem  Sira: ozelligi KAPATAN turlar once (bilesen hizmeti temizken), acanlar sonra, Windows bileseni de kaldiranlar en son.
rem  Denetim sirasinda Windows yeniden baslatma beklemeye baslarsa ozellik artik kapatilmaz (18.11.2026'da Is Klasorleri
rem  boyle kapatilip hemen geri acilamadi); kapali kalan ozellik yeniden baslatmadan sonraki denetimin basinda acilir.
rem  Onbellek ve gecici dosya temizlikleri canli calisir. Bilgisayarin kurtarilabilirligini ya da kullanicinin gordugu veriyi
rem  geri getirilemez bicimde silenler tam kipte de yalnizca onizlenir: eski geri yukleme noktalari, Windows.old (onceki
rem  surume donus), son kullanilan dosyalar listesi. Magaza uygulamasi kaldirma da onizlenir (kaldirilan uygulama yalnizca
rem  Microsoft Store'dan geri gelir); bilerek bir uygulamayla denemek icin "set MM_UYGULAMA_CANLI=<paket adi>".
rem  Ag kesme (kill-switch) gercek baglantiya uygulanmaz (onizleme ve gecici alan).
rem  Sonuc : %TEMP%\Multimizer-duman.txt  ve  %TEMP%\Multimizer-duman-ozellik.tsv
rem  Sure  : yaklasik 40-90 dakika (DISM bilesen deposu temizligi tek basina 10-40 dk surebilir). Bitene kadar bilgisayari kullanmayin
rem          (ekran, guc ve gorunum ayarlari kisa sure degisip geri doner). Durdurmak icin konsol penceresini kapatin.
rem  Bu dosya yalnizca ASCII karakter icerir ve satir sonlari CRLF olmalidir.
rem ---------------------------------------------------------------
net session >nul 2>&1
if not "%errorlevel%"=="0" goto :yonetici_iste
set "MM_DUMAN_KAPSAM=ozellik"
set "MM_OZELLIK_KIP=tam"
if /i not "%~1"=="/secim" goto :secim_yok
rem Yonetici penceresi kullanicinin komut istemindeki ortam degiskenlerini almaz. Istege bagli secimler (MM_OZELLIK_AGIR,
rem MM_UYGULAMA_CANLI, MM_BILESEN_CANLI) tek kullanimlik bir dosyayla aktarilir: dosyanin adi yukseltme aninda uretilen
rem jetonu tasir, yalnizca okunur (calistirilmaz), bilinen uc ad disindaki satirlar yok sayilir ve okununca silinir.
echo %~2| findstr /r "^[0-9][0-9]*$" >nul
if errorlevel 1 goto :secim_bitti
set "MM_SECIM=%TEMP%\Multimizer-duman-secim-%~2.txt"
if not exist "%MM_SECIM%" goto :secim_bitti
for /f "usebackq tokens=1,* delims==" %%A in ("%MM_SECIM%") do (
  if /i "%%A"=="MM_OZELLIK_AGIR" set "MM_OZELLIK_AGIR=%%B"
  if /i "%%A"=="MM_UYGULAMA_CANLI" set "MM_UYGULAMA_CANLI=%%B"
  if /i "%%A"=="MM_BILESEN_CANLI" set "MM_BILESEN_CANLI=%%B"
)
del "%MM_SECIM%" >nul 2>&1
:secim_bitti
call "%~dp0Duman-Testi.cmd"
exit /b %errorlevel%

:secim_yok
call "%~dp0Duman-Testi.cmd" %*
exit /b %errorlevel%

:yonetici_iste
echo.
echo  Yonetici izni isteniyor. Acilan pencerede "Evet" deyin.
set "MM_JETON=%RANDOM%%RANDOM%%RANDOM%"
set "MM_SECIM=%TEMP%\Multimizer-duman-secim-%MM_JETON%.txt"
type nul > "%MM_SECIM%"
if defined MM_OZELLIK_AGIR >> "%MM_SECIM%" echo MM_OZELLIK_AGIR=%MM_OZELLIK_AGIR%
if defined MM_UYGULAMA_CANLI >> "%MM_SECIM%" echo MM_UYGULAMA_CANLI=%MM_UYGULAMA_CANLI%
if defined MM_BILESEN_CANLI >> "%MM_SECIM%" echo MM_BILESEN_CANLI=%MM_BILESEN_CANLI%
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -ArgumentList '/secim','%MM_JETON%' -Verb RunAs"
if errorlevel 1 del "%MM_SECIM%" >nul 2>&1
exit /b 0
