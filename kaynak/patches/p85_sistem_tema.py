# -*- coding: utf-8 -*-
"""p85: Tema listesine "Sistem ayarini kullan" secenegi.

Uygulamanin dili "Otomatik" ile Windows'u izliyordu, Windows yuksek karsitligi da algilaniyordu; ama renk temasi Windows'un
acik/koyu uygulama ayarini izlemiyordu (varsayilan Beyaz, Windows koyu kipte olsa bile). Yeni secenek ayarda 'Sistem' olarak
saklanir; etkin tema Windows'tan cozulur (yuksek karsitlik > Koyu > Acik) ve Windows'ta kip degisince 3 sn icinde uygulanir.
Ayarlar listesi, hazir gorunum eslestirmesi ve duman testi secimi 'Sistem' degerini korur; duman testi secenegi ayrica dogrular.
"""


def apply(b):
    b.add_ui('160_sistem_tema.ps1', "function ConvertTo-ThemeKey([string]$Name) {\n", title='tema: Sistem ayarini kullan')
    b.rep("function ConvertTo-ThemeKey([string]$Name) {\n    $t = [string]$Name\n    if ($t -eq 'Sade') { return 'Koyu' }\n",
          "function ConvertTo-ThemeKey([string]$Name) {\n    $t = [string]$Name\n    if ($t -eq 'Sade') { return 'Koyu' }\n"
          "    if ($t -eq 'Sistem') { return (Get-SystemThemeKey) }\n",
          raw=True, name='tema: Sistem anahtari cozulur')
    b.rep("function Select-Theme([string]$Name) {\n    $Name = ConvertTo-ThemeKey $Name\n",
          "function Select-Theme([string]$Name) {\n    $choice = ConvertTo-ThemeChoice $Name\n    $Name = ConvertTo-ThemeKey $choice\n",
          raw=True, name='tema: secim Sistem degerini korur')
    b.rep("    $script:Settings.Theme = $Name\n    $ok = $true\n    try { Set-AppTheme $Name;",
          "    $script:Settings.Theme = $choice\n    $ok = $true\n    try { Set-AppTheme $Name;",
          raw=True, name='tema: ayara Sistem yazilir')
    b.rep("    $th = New-Object System.Collections.ArrayList\n    foreach ($k in @($script:Themes.Keys)) { [void]$th.Add(",
          "    $th = New-Object System.Collections.ArrayList\n"
          "    [void]$th.Add((New-Choice 'Sistem' ([string]$script:SystemThemeInfo.T) (Get-ThemeSwatch (Get-SystemThemeKey))))\n"
          "    foreach ($k in @($script:Themes.Keys)) { [void]$th.Add(",
          raw=True, name='tema: listede Sistem secenegi')
    b.rep("        $ui.st_ThDesc.Text = ([string]$script:ThemeInfo[$t].T + ': ' + [string]$script:ThemeInfo[$t].D)\n",
          "        if ([string]$script:Settings.Theme -eq 'Sistem') { $ui.st_ThDesc.Text = (Tr $(([string]$script:SystemThemeInfo.T + ': ' + [string]$script:SystemThemeInfo.D))) + ' ' + (Format-Tr 'Şu an: {0}.' (Tr ([string]$script:ThemeInfo[$t].T))) }\n"
          "        else { $ui.st_ThDesc.Text = ([string]$script:ThemeInfo[$t].T + ': ' + [string]$script:ThemeInfo[$t].D) }\n",
          name='tema: Sistem aciklamasi ve etkin tema')
    b.rep("function Load-StLook {\n    $t = ConvertTo-ThemeKey ([string]$script:Settings.Theme)\n",
          "function Load-StLook {\n    $t = ConvertTo-ThemeChoice ([string]$script:Settings.Theme)\n",
          raw=True, name='tema: ayarlar listesi Sistem gosterir')
    b.rep("    if ($t -ne '' -and (ConvertTo-ThemeKey $t) -ne (ConvertTo-ThemeKey ([string]$s.Theme))) { [void](Select-Theme $t) }",
          "    if ($t -ne '' -and (ConvertTo-ThemeChoice $t) -ne (ConvertTo-ThemeChoice ([string]$s.Theme))) { [void](Select-Theme $t) }",
          raw=True, name='tema: Sistem secimi kaydedilir')
    b.rep("    [void]$pairs.Add(@('st_ThemeSel', (ConvertTo-ThemeKey ([string]$s.Theme))))",
          "    [void]$pairs.Add(@('st_ThemeSel', (ConvertTo-ThemeChoice ([string]$s.Theme))))",
          raw=True, name='duman: tema listesi Sistem bekler')
    b.rep("    $t = ConvertTo-ThemeKey ([string](Get-BoardField $St 'Theme'))",
          "    $t = ConvertTo-ThemeChoice ([string](Get-BoardField $St 'Theme'))",
          raw=True, name='gorunum: Sistem hazir gorunumle eslesmez')
    b.rep("        $script:SessBeatTimer.Start()\n    } catch { }\n",
          "        $script:SessBeatTimer.Start()\n    } catch { }\n    try { Start-SystemThemeWatch } catch { }\n",
          raw=True, name='tema: Windows kipini izleme baslar')
    b.rep("            foreach ($x in $order) {\n                $q.Enqueue((New-SmokeStep 'Select' ('st_ThemeSel|' + $x) 700",
          "            $q.Enqueue((New-SmokeStep 'Select' 'st_ThemeSel|Sistem' 700 'seç tema Sistem'))\n"
          "            $q.Enqueue((New-SmokeStep 'SystemThemeCheck' 'Sistem' 200 'tema doğrula Sistem'))\n"
          "            foreach ($x in $order) {\n                $q.Enqueue((New-SmokeStep 'Select' ('st_ThemeSel|' + $x) 700",
          name='duman: Sistem secenegi secilir ve dogrulanir')
    b.rep("        'ThemeCheck' {\n            $cfg = ''\n",
          "        'SystemThemeCheck' {\n"
          "            $cfg = ''\n"
          "            try { $cfg = [string](Get-Settings).Theme } catch { }\n"
          "            $want = Get-SystemThemeKey\n"
          "            if ([string]$script:Settings.Theme -ne 'Sistem') { Add-SmokeError 'tema' ('bellekteki ayar ' + [string]$script:Settings.Theme + ', beklenen Sistem') }\n"
          "            if ($cfg -ne 'Sistem') { Add-SmokeError 'tema' ('dosyadaki ayar ' + $cfg + ', beklenen Sistem') }\n"
          "            if ([string]$script:ThemeName -ne $want) { Add-SmokeError 'tema' ('Sistem seçiliyken etkin tema ' + [string]$script:ThemeName + ', Windows kipine göre beklenen ' + $want) }\n"
          "            elseif ([bool](Update-SystemTheme)) { Add-SmokeError 'tema' 'Windows kipi değişmediği hâlde tema yeniden uygulandı' }\n"
          "            if ((Get-ComboKey $ui.st_ThemeSel) -ne 'Sistem') { Add-SmokeError 'tema' ('listede seçili ' + (Get-ComboKey $ui.st_ThemeSel) + ', beklenen Sistem') }\n"
          "            if ([int]$script:ThemeFail -gt 0) { Add-SmokeError 'tema' ('uygulanamayan renk sayısı: ' + [string]$script:ThemeFail) }\n"
          "        }\n"
          "        'ThemeCheck' {\n            $cfg = ''\n",
          name='duman: Sistem tema denetimi')
