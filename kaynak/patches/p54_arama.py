# -*- coding: utf-8 -*-
"""Arama kutusu (10.0.0): eski adlar ve cevrilmis metinler de bulunur.

Sayfa ve eylem adlari profesyonel adlarla degisti (ornek: "Bilgisayarim" -> "Bu bilgisayar"); eski ad arama anahtari olarak kalir.
Arayuz dili Turkce degilse cevrilmis ad ve aciklama da aranir (ornek: Ingilizce "firewall").
"""


def apply(b):
    # eylem: K = ek arama sozcukleri (arayuzde gorunmez)
    b.rep("pcinfo   = @{ T = 'Bu bilgisayar';", "pcinfo   = @{ K = 'bilgisayarim bilgisayar bilgisi donanim bilgisi'; T = 'Bu bilgisayar';", raw=True, name='p54 pcinfo anahtar')
    b.rep("        $hay = ((ConvertTo-AsciiKey ([string]$script:PageNames[$k])) + ' ' + [string]$k + ' ' + [string]$script:BoardSearchWords[$k]).Trim()\n",
          "        $hay = ((ConvertTo-AsciiKey ([string]$script:PageNames[$k])) + ' ' + [string]$k + ' ' + [string]$script:BoardSearchWords[$k]).Trim()\n"
          "        if ($script:LangOn -eq $true) { $hay = $hay + ' ' + (ConvertTo-AsciiKey (Tr ([string]$script:PageNames[$k]))) }\n", raw=True, name='p54 sayfa cevirisi')
    b.rep("        $hay = ((ConvertTo-AsciiKey ([string]$a.T)) + ' ' + (ConvertTo-AsciiKey ([string]$a.D)) + ' ' + [string]$k).Trim()\n",
          "        $hay = ((ConvertTo-AsciiKey ([string]$a.T)) + ' ' + (ConvertTo-AsciiKey ([string]$a.D)) + ' ' + [string]$k + ' ' + [string]$a.K).Trim()\n"
          "        if ($script:LangOn -eq $true) { $hay = $hay + ' ' + (ConvertTo-AsciiKey (Tr ([string]$a.T))) + ' ' + (ConvertTo-AsciiKey (Tr ([string]$a.D))) }\n", raw=True, name='p54 eylem cevirisi')
    # iki harfli (CJK vb.) sozcukler de icerirse eslesir
    b.rep("                elseif ($t.Length -ge 3 -and $w.Contains($t)) { $best = [math]::Max($best, 1) }\n",
          "                elseif (($t.Length -ge 3 -or ($t.Length -ge 2 -and $t -cmatch '[^\\x00-\\x7F]')) -and $w.Contains($t)) { $best = [math]::Max($best, 1) }\n", raw=True, name='p54 kisa sozcuk')
