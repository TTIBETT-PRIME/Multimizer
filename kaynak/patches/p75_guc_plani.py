# -*- coding: utf-8 -*-
"""Yuksek Performans guc plani ayari gercekten devreye girer (10.1.0).

Gercek bilgisayardaki tam denetim (HP OmniBook, Modern Bekleme) gosterdi: "Yuksek Performans guc planini etkinlestir"
ayari powercfg ile gizli plani etkinlestiriyor ya da kopyaliyordu, ama Windows Modern Bekleme'de Dengeli disindaki plani
devreye almiyordu; uygulamanin kendi dogrulamasi "1 deger hala farkli" diyordu ve olcum hep "bekliyor" kaliyordu.
Kullanicinin "performans moduna aliyorum ama girmiyor" sikayetinin ikinci yolu buydu.
- Ayar artik Guc sayfasindaki ile ayni yolu kullanir (Invoke-PowerSetOp 'High'): Modern Bekleme'de guc kipi
  "En iyi performans" yapilir ve geri okunarak dogrulanir; klasik bilgisayarda Yuksek Performans plani etkinlestirilir,
  yoksa Windows'un kendi kimligiyle olusturulur (kopya birikmez).
- Uygulamanin olusturdugu plan geri alinca silinir (geride iz kalmaz).
"""


def apply(b):
    b.sub_re(r"function Invoke-PowerPlan \{\n.*?\n\}\n\nfunction Invoke-HibernateOff \{\n",
             "function Invoke-PowerPlan {\n"
             "    # Guc sayfasindaki ile ayni yol: Modern Bekleme'de guc kipi (En iyi performans), klasik bilgisayarda Yuksek Performans plani\n"
             "    Invoke-PowerSetOp @{ T = 'PowerSet'; Key = 'High' }\n"
             "}\n\nfunction Invoke-HibernateOff {\n",
             flags=__import__('re').S, raw=True)

    # uygulamanin olusturdugu plan gunluge yazilir; geri alinca silinir
    b.rep("    if ($null -eq $tg) { $tg = New-PwBuiltin $key }\n",
          "    $created = ''\n"
          "    if ($null -eq $tg) { $tg = New-PwBuiltin $key; if ($null -ne $tg) { $created = [string]$tg.Guid } }\n",
          raw=True, name='p75 created')
    b.rep("    Add-Journal @{ T = 'Power'; Guid = [string]$act.Guid }\n    & powercfg.exe /setactive ([string]$tg.Guid) | Out-Null\n",
          "    Add-Journal @{ T = 'Power'; Guid = [string]$act.Guid; Created = $created }\n    & powercfg.exe /setactive ([string]$tg.Guid) | Out-Null\n",
          raw=True, name='p75 journal created')
    b.rep("                'Power' {\n                    if ($it.Guid) { & powercfg.exe /setactive $it.Guid | Out-Null }\n",
          "                'Power' {\n                    if ($it.Guid) { & powercfg.exe /setactive $it.Guid | Out-Null }\n"
          "                    # uygulamanin olusturdugu plan (etkin degilse) silinir\n"
          "                    $cr = [string]$it.Created\n"
          "                    if ($cr -match ('^' + $script:GuidRx + '$') -and $cr -ne [string]$it.Guid) { try { & powercfg.exe /delete $cr 2>&1 | Out-Null } catch { } }\n",
          raw=True, name='p75 undo delete')
