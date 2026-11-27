# -*- coding: utf-8 -*-
"""Hazirlik sekmesi: cekirdek (denetim, kurulum), Microsoft Store baglantisi ve eklenti listesi."""


def apply(b):
    b.add_core('127_prep_core.ps1', title='cozum merkezi: hazirlik denetimi ve kurulumu')
    # Open-Url: Microsoft Store baglantilari cmd uzerinden degil dogrudan acilir
    b.rep("if ($Url -match '^(https?://|windowsdefender:|ms-settings:)') {",
          "if ($Url -match '^(https?://|windowsdefender:|ms-settings:|ms-windows-store:)') {", raw=True, name='p43 store url')
