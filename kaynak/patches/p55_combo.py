# -*- coding: utf-8 -*-
"""Acilir listeler (10.0.0): ceviride uzayan secenek metni sabit genislikte kirpilmasin (Fit-ComboWidth, 141_i18n_ui.ps1)."""


def apply(b):
    b.rep("        $Combo.Items.Clear()\n        foreach ($c in @($Choices)) { [void]$Combo.Items.Add($c) }\n    } finally { $script:StLoading = $prev }\n",
          "        $Combo.Items.Clear()\n        foreach ($c in @($Choices)) { [void]$Combo.Items.Add($c) }\n        if ($script:LangOn) { Fit-ComboWidth $Combo }\n    } finally { $script:StLoading = $prev }\n",
          raw=True, name='p55 combo genisligi')
