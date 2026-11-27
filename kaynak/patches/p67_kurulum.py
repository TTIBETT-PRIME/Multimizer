# -*- coding: utf-8 -*-
"""Kurulum teklifi (10.1.0): uygulama kurulu degilken ilk acilista sorulur; "Kur" secilirse once eksik bilesenler kurulur, sonra uygulama."""


def apply(b):
    b.rep("    Initialize-GuardWatch\n    Initialize-FirstRun\n",
          "    Initialize-GuardWatch\n    try { Initialize-InstallOffer } catch { Write-CrashLog ('Kurulum teklifi: ' + $_.Exception.Message) }\n    Initialize-FirstRun\n",
          raw=True, name='p67 acilis')
    b.after("        FullDesc     = $false\n", "        InstallAsked = $false\n", raw=True)
    b.add_ui('154_setup_ui.ps1', "function Init-Page_backup {\n", title='kurulum teklifi: once bilesenler, sonra uygulama')
