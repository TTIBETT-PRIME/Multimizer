# -*- coding: utf-8 -*-
"""p98: Ad yazimi (G-08 karari, 27.11.2026): tamami buyuk harfle yazildiginda "MULTIMIZER" (noktasiz I). Ust cubuktaki emblem
dugmesinin yazisi Turkce arayuzde "MULTİMİZER" gorunuyordu; acilis ekrani, konsol ve diger basliklar zaten "MULTIMIZER" yaziyordu.
"""


def apply(b):
    b.rep('<TextBlock Text="MULTİMİZER" FontSize="15"', '<TextBlock Text="MULTIMIZER" FontSize="15"', xaml=True,
          name='ust cubuk: ad yazimi MULTIMIZER')
