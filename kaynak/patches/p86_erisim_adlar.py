# -*- coding: utf-8 -*-
"""p86: Ekran okuyucu adlari (UI Automation Name / LabeledBy).

Kodda 236 XAML dugmesi var, ekran okuyucu adi (AutomationProperties.Name) yalnizca 3 yerde verilmisti. WPF adi yalnizca icerigi
duz yazi olan dugmelerde kendisi buluyor; simge + yazi dugmeleri, secim ve metin kutulari Ekran Okuyucu'da adsiz kaliyordu.
Denetim yuklenince (sinif isleyicisi; sonradan olusan satirlar ve acilir pencereler dahil) adi bossa dugme icindeki ilk anlamli
yaziya, giris denetimi ayni satirdaki etikete (LabeledBy), ikisi de yoksa ipucuna baglanir. Baglama oldugu icin dil degisince ad
da degisir. Is pencere cizildikten sonra bosta yapilir. Etki, duman testindeki erisilebilirlik olcumuyle (p84) olculur.
"""


def apply(b):
    b.add_ui('161_erisim_adlar.ps1', "function Initialize-Scrolling {\n", title='erisilebilirlik: ekran okuyucu adlari')
    b.rep("    try { Initialize-Scrolling } catch { Write-CrashLog ('Kaydirma: ' + $_.Exception.Message) }\n",
          "    try { Initialize-Scrolling } catch { Write-CrashLog ('Kaydirma: ' + $_.Exception.Message) }\n"
          "    try { Register-A11yNames } catch { Write-CrashLog ('Erişilebilirlik: ' + $_.Exception.Message) }\n",
          name='erisilebilirlik: adlar pencere acilmadan kurulur')
