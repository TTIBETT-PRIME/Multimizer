# -*- coding: utf-8 -*-
"""Guvenlik durusu: standart eslemesi, Chk_Posture denetimi, bulgulara Std alani, rapor bolumu."""


def apply(b):
    b.add_core('129_posture.ps1', title='guvenlik durusu: standart eslemesi')
    # tam saglik taramasinin sonuna "Guvenlik durusu" denetimi
    b.rep("B = { Chk_BootTime } }\n",
          "B = { Chk_BootTime } },\n            @{ N = ('Güvenlik duruşu'); B = { Chk_Posture } }\n", name='p44 kontrol listesi')
    # duzeltmeler turetildikten sonra bulgulara standart basliklari yazilir
    b.rep("foreach ($fnd in $script:Findings) { try { Resolve-FindingFix $fnd } catch { } }\n",
          "foreach ($fnd in $script:Findings) { try { Resolve-FindingFix $fnd } catch { } }\n"
          "    foreach ($fnd in $script:Findings) { try { Set-FindingStd $fnd } catch { } }\n", name='p44 std dongusu')
    # rapora "Guvenlik durusu ve standart eslemesi" bolumu
    b.rep("    $inv = Get-Inventory\n    Set-JobProgress 1 3",
          "    $inv = Get-Inventory\n"
          "    try { $psec = Get-PostureReportSection; if ($null -ne $psec) { $inv = @($inv) + @($psec) } } catch { }\n"
          "    Set-JobProgress 1 3", name='p44 rapor')
