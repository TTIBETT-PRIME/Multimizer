# -*- coding: utf-8 -*-
"""Dis araclar (saglayici katmani): Araclar sayfasina 'Dis araclar' sekmesi, cekirdek ve arayuz modulleri, Duman turu adimi, arama ve komut baglantilari."""


def apply(b):
    # ---- XAML: sekme dugmesi ve aciklama
    b.after('    <RadioButton x:Name="tl_Tab_sys" Content="Sistem" Tag="sys" GroupName="tl_tabs" Style="{DynamicResource Chip}"/>\n',
            '    <RadioButton x:Name="tl_Tab_ext" Content="Dış araçlar" Tag="ext" GroupName="tl_tabs" Style="{DynamicResource Chip}"/>\n',
            xaml=True)
    b.rep('gibi ek araçları kullanın.',
          'gibi ek araçları kullanın; disk sağlığı, kurtarma ve izleme gibi yerleşik dış araçları tek yerden kurun ve açın.',
          xaml=True, name='p46 araclar aciklamasi')

    # ---- sekme listesi, sekme gecisi ve yenile dugmesi
    b.rep("$script:TlTabs = @('win', 'procs', 'repair', 'files', 'sys')",
          "$script:TlTabs = @('win', 'procs', 'repair', 'files', 'sys', 'ext')", raw=True, name='p46 sekmeler')
    b.rep("        'sys' { Show-OnlyBar 'tl' @(); Render-TlSys }\n    }\n}",
          "        'sys' { Show-OnlyBar 'tl' @(); Render-TlSys }\n        'ext' { Show-OnlyBar 'tl' @('tl_Refresh'); Render-TlExt }\n    }\n}", raw=True, name='p46 Set-TlTab')
    b.rep("$ui.tl_Refresh.Add_Click({ Invoke-Safe { $script:TlProcs = $null; Render-TlProcs } 'Yenile' })",
          "$ui.tl_Refresh.Add_Click({ Invoke-Safe { Invoke-TlRefresh } 'Yenile' })", raw=True, name='p46 yenile')

    # ---- moduller: cekirdek (arka plan isleri) ve arayuz
    b.add_core('132_exttools_core.ps1', title='dis araclar: katalog, denetim ve kurulum isleri')
    b.add_ui('133_exttools_ui.ps1', "function Init-Page_backup {\n", title='dis araclar: Araclar sayfasi sekmesi')

    # ---- Duman turu: Dis araclar sekmesini acip yeniler (yalnizca okuma)
    b.rep("        @('tools', 'tl_Tab_procs', 'tl_Refresh'),\n",
          "        @('tools', 'tl_Tab_procs', 'tl_Refresh'),\n        @('tools', 'tl_Tab_ext', 'tl_Refresh'),\n", raw=True, name='p46 duman')

    # ---- iki sekmede ayni adli dugme (tl_Refresh) olabilir: ekran goruntusu adi sekmeyi de tasir, biri otekinin ustune yazilmaz
    b.rep("('eylem-' + $a[2])", "('eylem-' + $(if ($a[1] -ne '') { [string]$a[1] + '-' } else { '' }) + $a[2])", raw=True, name='p46 goruntu adi')

    # ---- arama sozcukleri ve komut hedefleri
    b.rep("tools = 'arac onarim islem'",
          "tools = 'arac onarim islem dis harici crystaldiskinfo testdisk photorec windirstat sysinternals hwinfo wireguard 7zip everything powertoys winget kur'",
          name='p46 arama: araclar')
    b.rep("diskler = 'solve:disk'\n", "diskler = 'solve:disk'; harici = 'tools:ext'; disaraclar = 'tools:ext'\n", name='p46 komut hedefleri')

    # ---- pano hizli eylemi
    b.rep("\n}\n\n# Hazir duzenler (tasarim basina;",
          "\n    extools  = @{ T = 'Dış araçlar'; D = 'Disk sağlığı, kurtarma ve izleme gibi yerleşik araçları kurar ve açar.'; Ico = 'IcoTools'; Page = 'tools'; Sub = 'ext'; Fn = '' }\n"
          "}\n\n# Hazir duzenler (tasarim basina;", name='p46 pano eylemi')
    b.rep("pcinfo = 'BrBlue'\n}", "pcinfo = 'BrBlue'; extools = 'BrAccent'\n}", name='p46 pano vurgu')
