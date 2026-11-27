# -*- coding: utf-8 -*-
"""Otomasyon kural ozeti (10.0.0): hazir kuralin bildirim metni dil paketinden okunur; kullanicinin kendi metni degismeden kalir."""


def apply(b):
    b.rep("    elseif ([string]$d.Kind -eq 'Notify' -and [string]$d.Arg -ne '') { $b += (': ' + [string]$d.Arg) }\n",
          "    elseif ([string]$d.Kind -eq 'Notify' -and [string]$d.Arg -ne '') { $b += (': ' + (Tr ([string]$d.Arg))) }\n",
          raw=True, name='p56 kural bildirim metni')
