# -*- coding: utf-8 -*-
"""Adlandirma (10.0.0): ana sayfa hizli eylem kartinin gayriresmi adi 'Copu temizle' -> 'Disk temizligi'."""


def apply(b):
    b.rep("clean    = @{ T = ('' + [char]0x00C7 + '' + [char]0x00F6 + 'p' + [char]0x00FC + ' temizle');",
          "clean    = @{ T = ('Disk temizli' + [char]0x011F + 'i');",
          raw=True, name='p60 temizlik karti adi')
