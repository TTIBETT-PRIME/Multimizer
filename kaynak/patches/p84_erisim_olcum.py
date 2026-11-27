# -*- coding: utf-8 -*-
"""p84: Duman testine erisilebilirlik olcumu (yalnizca okur).

Kodda 236 XAML dugmesi var; ekran okuyucu adi (AutomationProperties.Name) yalnizca 3 yerde acikca verilmis. Simge ve yazi
birlesik dugmelerde, secim ve metin kutularinda UI Automation adi bos kalabilir; Ekran Okuyucu bunlari adsiz okur.
Kullanicinin bilgisayari dokunmatik: Microsoft dokunma hedefi icin yaklasik 40x40, sik yerlesimde 32x32 etkin piksel oneriyor;
WCAG 2.2 AA en az 24x24 istiyor. Duman testi artik her ekran goruntusunde (ayni gorunumu her temada yeniden olcmeden)
gorunen denetim ogelerini olcer, ozeti sonuca ve ayrintiyi %TEMP%\\Multimizer-duman-erisim.txt dosyasina yazar.
Duzeltmeler bu olcume gore yapilacak (olcmeden duzeltme yok).
"""


def apply(b):
    b.add_ui('159_erisim_olcum.ps1', "function Complete-SmokeRun {\n", title='duman: erisilebilirlik olcumu (yalnizca okur)')
    b.rep("        $script:SmokeShots = $script:SmokeShots + 1\n    } catch { Add-SmokeError ('ekran g",
          "        $script:SmokeShots = $script:SmokeShots + 1\n"
          "        try { Measure-SmokeA11y $Name } catch { Add-SmokeA11yFail $_.Exception.Message }\n"
          "    } catch { Add-SmokeError ('ekran g",
          raw=True, name='duman: ekran goruntusunde erisilebilirlik olcumu')
    b.rep("    try { Write-SmokeLangReport } catch {",
          "    try { Write-SmokeA11yReport } catch { Add-SmokeA11yFail $_.Exception.Message }\n"
          "    try { Write-SmokeLangReport } catch {",
          raw=True, name='duman: erisilebilirlik ozeti')
