# -*- coding: utf-8 -*-
"""p93: Duman olcum siniri 80'den 200'e cikinca gorunen kalan adsiz ve tekrarli adlar (G-05 koşusu, 27.11.2026).
  - Asistan giris kutusu (AskInput) adsizdi: A11yNameMap'e eklendi (161_erisim_adlar.ps1).
  - Secim kutusundaki (Show-Choice) dugmeler adsizdi (icerik StackPanel): ad = baslik, yardim metni = ayrinti (gorunen metin gibi Tr ile cevrilir).
  - Panodaki parca kaldir dugmesi her parcada ayni adi tasiyordu: "Parcayi kaldir: <parca basligi>".
Kalan: Diskler sekmesinde her surucu kartindaki ayni satir dugmeleri (Iyilestir, Tara) surucu harfi olmadan ayni ad.
"""


def apply(b):
    b.rep("        $b.Content = $sp\n        $b.Add_Click({ param($s, $e) Invoke-Safe { Complete-Choice ([string]$s.Tag) } ('Se' + [char]0x00E7 + 'im') })\n",
          "        $b.Content = $sp\n"
          "        [System.Windows.Automation.AutomationProperties]::SetName($b, (Tr ([string]$o.Title)))\n"
          "        [System.Windows.Automation.AutomationProperties]::SetHelpText($b, (Tr ([string]$o.Detail)))\n"
          "        $b.Add_Click({ param($s, $e) Invoke-Safe { Complete-Choice ([string]$s.Tag) } ('Se' + [char]0x00E7 + 'im') })\n",
          raw=True, name='erisim: secim kutusu dugmelerine ad')
    b.rep("    if ($type -eq 'radar' -or $type -eq 'hex') { $n.Sub.Text = '' }\n}\n",
          "    if ($type -eq 'radar' -or $type -eq 'hex') { $n.Sub.Text = '' }\n"
          "    if ($n.ContainsKey('Del')) {\n"
          "        [System.Windows.Automation.AutomationProperties]::SetName($n.Del, (Tr 'Parçayı kaldır') + ': ' + (Tr $title))\n"
          "    }\n}\n",
          name='erisim: parca kaldir dugmesi parca basligiyla')
