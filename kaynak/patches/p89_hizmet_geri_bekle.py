# -*- coding: utf-8 -*-
"""p89: Hizmet geri almasi, durdurulmakta olan hizmetin durmasini bekler.

Gercek bilgisayarda (26.11.2026, b17 tam canli denetim) tur/Search HATA verdi: WSearch 'Running' iken Invoke-SvcOp
Stop-Service -NoWait ile durdurdu; geri alma hizmeti hemen Start-Service ile baslatmaya calisti, ama hizmet daha
'StopPending' idi ve Start-Service -ErrorAction SilentlyContinue ile sessizce basarisiz oldu (sonuc: 2/True/Stopped).
Cozum: geri alma, hizmet 'Stopped' olunca baslatir; en cok 30 sn bekler.
"""


def apply(b):
    b.rep("if ($it.WasRunning) { Start-Service -Name $it.Name -ErrorAction SilentlyContinue }",
          "if ($it.WasRunning) {\n"
          "                            for ($k = 0; $k -lt 60; $k++) {\n"
          "                                $sv = Get-Service -Name $it.Name -ErrorAction SilentlyContinue\n"
          "                                if ($null -eq $sv -or $sv.Status -eq 'Running') { break }\n"
          "                                if ($sv.Status -eq 'Stopped') { Start-Service -Name $it.Name -ErrorAction SilentlyContinue }\n"
          "                                Start-Sleep -Milliseconds 500\n"
          "                            }\n"
          "                            $sv = Get-Service -Name $it.Name -ErrorAction SilentlyContinue\n"
          "                            if ($null -ne $sv -and $sv.Status -ne 'Running') { throw ('Hizmet 30 sn i\u00e7inde ba\u015flat\u0131lamad\u0131: ' + $it.Name) }\n"
          "                        }",
          raw=False, name='hizmet geri alma: StopPending bitince baslat')
