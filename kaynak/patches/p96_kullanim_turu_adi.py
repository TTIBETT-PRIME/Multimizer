# -*- coding: utf-8 -*-
"""p96: Ayarlar > Kullanim turu satirindaki "Degistir..." dugmesi ekran okuyucuya baglamsiz okunuyordu (G-04 masa basi gezinme,
27.11.2026: duman raporunda ad yalnizca "Degistir..."). Ad "Degistir..., Kullanim turu" olur; her iki parca katalogda var, Tr ile cevrilir.
"""


def apply(b):
    b.rep("    $ui.st_UseCaseText.Text = (Get-UseCaseTitle ([string]$script:Settings.UseCase))\n",
          "    $ui.st_UseCaseText.Text = (Get-UseCaseTitle ([string]$script:Settings.UseCase))\n"
          "    [System.Windows.Automation.AutomationProperties]::SetName($ui.st_UseCase, (Tr 'Değiştir...') + ', ' + (Tr 'Kullanım türü'))\n",
          name='erisim: Kullanim turu degistir dugmesi')
