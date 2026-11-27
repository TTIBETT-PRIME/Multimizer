# -*- coding: utf-8 -*-
"""p95: Diskler sekmesinde her surucu kartindaki ayni satir dugmeleri (Iyilestir, Tara) ekran okuyucuya ayni adla okunuyordu (G-11).
Gercek bilgisayar (27.11.2026, duman olcum siniri 200 gorunum): dokunma-solve-sl_Tab_disk gorunumunde 3 surucude 3 ayni ad.
Cozum: satir dugmesinin adi "<dugme>, <satir basligi>, <surucu>" olur (Tr ile cevrilir); surucu harfi kartin kendisindendir.
"""


def apply(b):
    b.rep("            if ($b1 -ne '') { $row.FindName('Act').Add_Click($script:H_SlAct) }\n",
          "            if ($b1 -ne '') {\n"
          "                $row.FindName('Act').Add_Click($script:H_SlAct)\n"
          "                [System.Windows.Automation.AutomationProperties]::SetName($row.FindName('Act'), (Tr $b1) + ', ' + (Tr ([string]$r.Title)) + ', ' + [string]$disk.Drive)\n"
          "            }\n",
          name='disk: Act dugmesi surucu harfiyle')
    b.rep("                $a2.Tag = $data2\n",
          "                $a2.Tag = $data2\n"
          "                [System.Windows.Automation.AutomationProperties]::SetName($a2, (Tr $b2) + ', ' + (Tr ([string]$r.Title)) + ', ' + [string]$disk.Drive)\n",
          name='disk: Act2 dugmesi surucu harfiyle')
