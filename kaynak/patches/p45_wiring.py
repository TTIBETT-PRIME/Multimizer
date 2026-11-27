# -*- coding: utf-8 -*-
"""Baglama: Duman turu dugmeleri, arama sozcukleri, pano hizli eylemleri, komut hedefleri ve acilista Hazirlik uyarisi."""


def apply(b):
    # ---- Duman turu: Cozum Merkezi'nin salt okunur dugmeleri (tarama, yenileme, denetleme)
    b.rep("'st_BoardEdit', 'st_BoardReset'\n)",
          "'st_BoardEdit', 'st_BoardReset',\n    'sl_Scan', 'sl_DiskRefresh', 'sl_ErRefresh', 'sl_PcRefresh', 'sl_PrCheck'\n)", name='p45 smoke guvenli dugmeler')
    b.rep("        @('updates', 'up_Tab_wu', 'up_Check')\n",
          "        @('updates', 'up_Tab_wu', 'up_Check'),\n"
          "        @('solve', 'sl_Tab_scan', 'sl_Scan'), @('solve', 'sl_Tab_disk', 'sl_DiskRefresh'), @('solve', 'sl_Tab_erase', 'sl_ErRefresh'),\n"
          "        @('solve', 'sl_Tab_pc', 'sl_PcRefresh'), @('solve', 'sl_Tab_prep', 'sl_PrCheck')\n", name='p45 smoke eylemleri')

    # ---- arama sozcukleri (ASCII, kucuk harf)
    b.rep("    solve = 'cozum coz sorun onar bitlocker sifrele sifreleme kurtar silinen disk hata sorun giderme hazirlik'\n",
          "    solve = 'cozum coz sorun onar bitlocker sifrele sifreleme kurtar silinen dosya geri getir disk usb hata giderme hazirlik bilesen eksik gereksinim bagimlilik bilgisayarim donanim model islemci bellek ekran karti tpm kalici silme imha standart uyum cis nist iso bsi nis2 kvkk gdpr durus'\n",
          name='p45 arama: cozum')
    b.rep("security = 'guvenlik defender virus saldiri denetim'",
          "security = 'guvenlik defender virus saldiri denetim standart uyum cis nist iso bsi nis2 kvkk gdpr durus'", name='p45 arama: guvenlik')

    # ---- ayar varsayilani: Hazirlik uyarisinin son gosterildigi surum
    b.rep("        WinOpacity   = 100\n    }\n}\n", "        WinOpacity   = 100\n        PrepSeen     = ''\n    }\n}\n", name='p45 PrepSeen')

    # ---- pano hizli eylemleri: Cozum Merkezi ve sekmeleri
    b.rep("\n}\n\n# Hazir duzenler (tasarim basina;",
          "\n    solve    = @{ T = 'Çözüm Merkezi'; D = 'Sorunları bulur ve düzeltir; disk, kurtarma, silme.'; Ico = 'IcoSolve'; Page = 'solve'; Sub = 'scan'; Fn = '' }\n"
          "    recover  = @{ T = 'Dosya kurtar'; D = 'Silinen dosyaları sürücü, USB bellek ya da disk imajından geri getirir.'; Ico = 'IcoRestore'; Page = 'solve'; Sub = 'recover'; Fn = '' }\n"
          "    erase    = @{ T = 'Kalıcı sil'; D = 'Dosya, klasör, boş alan ya da diski geri getirilemeyecek biçimde siler.'; Ico = 'IcoTrash'; Page = 'solve'; Sub = 'erase'; Fn = '' }\n"
          "    pcinfo   = @{ T = 'Bilgisayarım'; D = 'Donanımı ve Windows sürümünü tanır; kullanıcı ve uzman görünümü.'; Ico = 'IcoMonitor'; Page = 'solve'; Sub = 'pc'; Fn = '' }\n"
          "    prep     = @{ T = 'Hazırlık'; D = 'Gerekli bileşenleri denetler; eksikleri onayınızla giderir.'; Ico = 'IcoCheck'; Page = 'solve'; Sub = 'prep'; Fn = '' }\n"
          "}\n\n# Hazir duzenler (tasarim basina;", name='p45 pano eylemleri')
    b.rep("    gaming = 'BrAccent2'; smart = 'BrAccent2'; company = 'BrAccent2'\n}",
          "    gaming = 'BrAccent2'; smart = 'BrAccent2'; company = 'BrAccent2'\n    solve = 'BrGood'; prep = 'BrGood'; recover = 'BrGold'; erase = 'BrWarn'; pcinfo = 'BrBlue'\n}", name='p45 pano vurgu')
    b.rep("    if ([string]$a.Page -ne '') { Open-Page ([string]$a.Page) }\n}",
          "    if ([string]$a.Page -ne '') { Open-Page ([string]$a.Page) ([string](Get-BoardField $a 'Sub')) }\n}", name='p45 pano eylem sekmesi')

    # ---- komut satiri: "ac hazirlik" gibi sekme hedefleri
    b.add_ui('131_wiring.ps1', "function Init-Page_backup {\n", title='baglantilar: komut hedefleri')
    b.rep("    cozum = 'solve'; coz = 'solve'; sorun = 'solve'; onar = 'solve'; solve = 'solve'; bitlocker = 'solve'; sifrele = 'solve'; kurtar = 'solve'\n",
          "    cozum = 'solve'; coz = 'solve'; sorun = 'solve'; onar = 'solve'; solve = 'solve'; bitlocker = 'solve'; sifrele = 'solve'; kurtar = 'solve'\n"
          "    hazirlik = 'solve:prep'; bilgisayarim = 'solve:pc'; donanim = 'solve:pc'; silinen = 'solve:recover'; silme = 'solve:erase'; diskler = 'solve:disk'\n", name='p45 komut hedefleri')
    b.rep("Open-Page ([string]$script:CmdPages[$a0]); Out-Cmd", "Open-CmdPage ([string]$script:CmdPages[$a0]); Out-Cmd", raw=True, name='p45 ac komutu')

    # ---- acilista Hazirlik uyarisi
    b.add_ui('130_prep_nudge.ps1', "function Init-Page_backup {\n", title='acilista hazirlik uyarisi')
    b.rep("    Initialize-GuardWatch\n    Initialize-FirstRun\n}",
          "    Initialize-GuardWatch\n    Initialize-FirstRun\n    try { Initialize-PrepNudge } catch { Write-CrashLog ('PrepNudge: ' + $_.Exception.Message) }\n}", name='p45 acilis zamanlayicisi')
