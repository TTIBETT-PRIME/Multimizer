# -*- coding: utf-8 -*-
"""p88: Dokunma hedefi alt siniri (WCAG 2.2 AA, 2.5.8): sekme dugmeleri ve onay kutulari en az 24 px yuksekligindedir.

Gercek bilgisayarda (25.11.2026) duman testinin erisilebilirlik olcumu 70 ogenin kisa kenarini 24 px altinda buldu:
63 RadioButton (alt sekmeler ve secenek dugmeleri, 22 px; hepsi 'Chip' stilini kullanir, o da 'Seg'den turer) ve
7 CheckBox (varsayilan stil 18 px, 'Toggle' stili 19-20 px). Dort stilden uc tanesine MinHeight eklenir; Chip, Seg'den
turedigi icin yuksekligi oradan alir. Sablonlarin koku zaten ogeyi doldurur ve icerik dikey ortalanir; yalnizca
dugme 2 px (sekmeler), Toggle 4 px, onay kutusu 6 px'e kadar yukselir. RailItem (56 px) etkilenmez.
Etki, duman testindeki erisilebilirlik olcumuyle (p84) olculur: '24 px alti' sayisi 0 olmalidir.
"""


def apply(b):
    b.rep('<Style x:Key="Seg" TargetType="RadioButton">',
          '<Style x:Key="Seg" TargetType="RadioButton">\n  <Setter Property="MinHeight" Value="24"/>',
          raw=True, name='dokunma hedefi: Seg (ve ondan turetilen Chip) en az 24 px')
    b.rep('<Style TargetType="CheckBox">',
          '<Style TargetType="CheckBox">\n  <Setter Property="MinHeight" Value="24"/>',
          raw=True, name='dokunma hedefi: varsayilan onay kutusu en az 24 px')
    b.rep('<Style x:Key="Toggle" TargetType="CheckBox">',
          '<Style x:Key="Toggle" TargetType="CheckBox">\n  <Setter Property="MinHeight" Value="24"/>',
          raw=True, name='dokunma hedefi: Toggle en az 24 px')
