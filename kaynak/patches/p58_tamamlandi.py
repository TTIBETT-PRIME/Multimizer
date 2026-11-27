# -*- coding: utf-8 -*-
"""Tamamlanan islemlerin ileti dili (10.0.0): konusma dilindeki "bitti" yerine "tamamlandi" (yalnizca gorunen metin)."""


def apply(b):
    pairs = [
        ("[char]0x0131 + 'm bitti: ')", "[char]0x0131 + 'm tamamland' + [char]0x0131 + ': ')", 1, 'onarim gunluk'),
        ("[char]0x0131 + 'm bitti')", "[char]0x0131 + 'm tamamland' + [char]0x0131 + '')", 1, 'onarim bildirim basligi'),
        ("'kleme hatayla bitti (kod '", "'kleme hatayla sonu' + [char]0x00E7 + 'land' + [char]0x0131 + ' (kod '", 1, 'geri yukleme'),
        ("'nizleme bitti: '", "'nizleme tamamland' + [char]0x0131 + ': '", 2, 'onizleme'),
        ("'Yedekleme bitti: '", "'Yedekleme tamamland' + [char]0x0131 + ': '", 1, 'yedekleme'),
        ("'s taramas' + [char]0x0131 + ' bitti.'", "'s taramas' + [char]0x0131 + ' tamamland' + [char]0x0131 + '.'", 1, 'hizli tarama'),
        ("'ifreli yedek bitti: '", "'ifreli yedek tamamland' + [char]0x0131 + ': '", 1, 'sifreli yedek'),
        ("' bitti; sonu'", "' tamamland' + [char]0x0131 + '; sonu'", 1, 'onarim adimlari'),
        ("'rev bitti, '", "'rev tamamland' + [char]0x0131 + ', '", 1, 'gorev'),
    ]
    for old, new, cnt, name in pairs:
        b.rep(old, new, count=cnt, raw=True, name='p58 ' + name)
    b.rep("bak&#x0131;m bitti, sistem", "bak&#x0131;m tamamland&#x0131;, sistem", raw=True, name='p58 bildirim secenegi')
