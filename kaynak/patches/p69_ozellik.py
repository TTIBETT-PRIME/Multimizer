# -*- coding: utf-8 -*-
"""Canli ozellik denetimi (10.1.0): duman testinin "ozellik" kapsami.

Kullanici istegi: "butonlar var ama gercekte islevsiz" sikayetinin sistematik olarak bulunmasi. Bu kapsam, katalogdaki her ayari uygulamanin
kendi motoruyla uygular, sistemden BAGIMSIZ bir okumayla dogrular (kayit defteri, hizmet, gorev, calisan oturum), geri alir ve eski halle karsilastirir.
Gorsel efektler ve guc kipi calisan oturumda okunur; "Windows geri aldi" -> "Duzelt" akisi uctan uca denenir; parola uretici, toplu adlandirma,
dosya sifreleme, guvenli silme ve bellek bosaltma gecici bir deneme klasorunde gercek dosyalarla sinanir; salt-okunur arka plan isleri tek tek calistirilir;
sicaklik/ekran karti okumalari Windows'un kendi degeriyle, saglik bulgulari Windows'un kendi okumasiyla karsilastirilir.

Iki kip (MM_OZELLIK_KIP): oku (varsayilan, hicbir sey yazmaz) | tam (yonetici; her degisiklik geri alinir, eski durum once diske yazilir).
"tam" kapsamina dahil degildir; Duman-Ozellik.cmd (yonetici ister) ve Duman-OzellikOku.cmd ile baslatilir. Mantik mods/155 ve mods/156 dosyalarindadir.
"""


def apply(b):
    b.rep(" | ust | kullanim\n# \"kullanim\" kapsami",
          " | ust | kullanim | ozellik\n"
          "# \"ozellik\" kapsami her ozelligi gercek Windows'ta dener (mods/155_live_audit.ps1, 156): Duman-Ozellik.cmd (yonetici) ya da Duman-OzellikOku.cmd (yalnizca okuma).\n"
          "# \"kullanim\" kapsami", raw=True, name='p69 kapsam yorumu')
    b.rep("    kullanim = @('kullanim')\n", "    kullanim = @('kullanim')\n    ozellik = @('ozellik')\n", raw=True, name='p69 kapsam')

    steps = (
        "          if ($parts -contains 'ozellik') {\n"
        "            foreach ($lv in @('ortam', 'olcum', 'etki', 'sapma', 'tur:hkcu', 'tur:hklm', 'tur:hizmet', 'tur:ozel', 'tur:tekyon', 'tur:onizleme', 'bilesen', 'arac', 'is:sistem', 'is:depolama', 'is:guncelleme', 'is:ag', 'is:oyun', 'is:saglik', 'sensor', 'bulgu', 'ozet')) {\n"
        "              $q.Enqueue((New-SmokeStep 'LiveCheck' $lv 300 ('canl' + [char]0x0131 + ' denetim: ' + $lv)))\n"
        "            }\n"
        "          }\n"
    )
    b.before("          if ($parts -contains 'tepsi') {\n", steps)
    b.after("        'UxCheck' { Test-SmokeUx $arg }\n", "        'LiveCheck' { Test-SmokeLive $arg }\n", raw=True)

    # bu kapsam yuzlerce ayari sirayla gecer; bekci suresi uzatilir (diger kapsamlar 3000 sn)
    b.rep("        [void]$wd.AddArgument([int]$script:SmokeLimitSec)\n",
          "        if ((Get-SmokeScope) -eq 'ozellik') { $script:SmokeLimitSec = 10800 }\n"
          "        [void]$wd.AddArgument([int]$script:SmokeLimitSec)\n", raw=True, name='p69 bekci suresi')

    b.add_ui('155_live_audit.ps1', "function Init-Page_backup {\n", title='canli ozellik denetimi: cekirdek (olcum, tur, geri yukleme)')
    b.add_ui('156_live_audit2.ps1', "function Init-Page_backup {\n", title='canli ozellik denetimi: etkiler, araclar, isler, bulgular')
