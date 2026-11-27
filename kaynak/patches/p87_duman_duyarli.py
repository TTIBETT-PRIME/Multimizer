# -*- coding: utf-8 -*-
"""p87: Duman testi, yakinlastirma %100'e donuste gunluk ve komut satirini yerlesimin varsayilanina gore bekler.

Gercek bilgisayarda (25.11.2026) arayuz duman testi Hacker yerlesimiyle basladi; bu yerlesimde gunluk ve komut satiri
varsayilan olarak kapali. Yakinlastirma bolumu %100'e donunce iki paneli kosulsuz "acik" bekledigi icin iki HATA yazildi
(panellerin kendiliginden kapanmadigi, kullanicinin yerlesim secimiyle kapali oldugu ayni satirda gorunuyordu). %80 adimi
gibi yerlesimin varsayilanina gore bekler ('def'): kendiliginden kapanan panel varsayilan aciksa yine acik olmak zorunda.
"""


def apply(b):
    b.rep("(New-SmokeStep 'Resp' 'log:on,cmd:on,title,panel' 300 ('duyarl' + [char]0x0131 + ': yak'",
          "(New-SmokeStep 'Resp' 'log:def,cmd:def,title,panel' 300 ('duyarl' + [char]0x0131 + ': yak'",
          raw=True, name='duman: %100 donusunde paneller yerlesim varsayilanina gore')
