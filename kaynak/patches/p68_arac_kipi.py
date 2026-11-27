# -*- coding: utf-8 -*-
"""Araclar sayfasi kullanici kipinde (10.1.0): Yardimcilar, Dis araclar ve Onarim sekmeleri kullanici kipinde de gorunur.

Gercek bilgisayardaki kullanim denemesinde goruldu: parola uretici, toplu yeniden adlandirma, karne gibi gundelik araclar
yalnizca uzman kipinde gorunen Araclar sayfasinin icindeydi; kullanici kipindeki biri bunlara ancak aramayla ulasabiliyordu.
Sayfa artik iki kipte de sol cubukta durur; uzmanlik isteyen sekmeler (Windows araclari, Islemler, Dosya araclari, Sistem)
kullanici kipinde gizlenir (mods/151_kit_ui.ps1: Get-TlVisibleTabs, Update-PageMode_tools).
"""


def apply(b):
    b.rep("$script:ExpertPages = @('services', 'company', 'tools')", "$script:ExpertPages = @('services', 'company')", raw=True, name='p68 uzman sayfalari')
    b.rep("    $expertOnly = @('services', 'company', 'tools')\n", "    $expertOnly = @('services', 'company')\n", raw=True, name='p68 menu gruplari')
    b.rep("function Show-Page_tools {\n    $t = Get-TabKey 'tl' $script:TlTabs 'win'\n    Set-TlTab $t\n}\n",
          "function Show-Page_tools {\n"
          "    $exp = ($script:UiState.Mode -eq 'Expert')\n"
          "    $vis = @(Get-TlVisibleTabs $exp)\n"
          "    foreach ($k in @($script:TlTabs)) { $c = $ui['tl_Tab_' + [string]$k]; if ($null -ne $c) { Set-Visible $c ($vis -contains [string]$k) } }\n"
          "    $cur = Get-TabKey 'tl' $script:TlTabs 'win'\n"
          "    $t = Get-TlStartTab $exp $cur\n"
          "    if ($t -ne $cur -and (Select-TabChip 'tl' $t)) { return }\n"
          "    Set-TlTab $t\n"
          "}\n", raw=True, name='p68 sayfa acilisi')
    b.rep("function Select-Sub_tools([string]$Sub) {\n    if (-not (Select-TabChip 'tl' $Sub)) { Set-TlTab $Sub }\n}\n",
          "function Select-Sub_tools([string]$Sub) {\n"
          "    if (Test-TlNeedsExpert $Sub ($script:UiState.Mode -eq 'Expert')) { Set-UiMode 'Expert' $true }\n"
          "    if (-not (Select-TabChip 'tl' $Sub)) { Set-TlTab $Sub }\n"
          "}\n", raw=True, name='p68 alt sekme')
