# -*- coding: utf-8 -*-
"""p92: Dokunma hedefleri: Ayarlar > Gorunum'de Otomatik / Normal / Buyuk (G-05).

Gercek bilgisayarda (25.11.2026) duman olcumu: 24 px alti 70 hedef (sekme ve secenek dugmeleri, onay kutulari; p88 ile 24'e cikarildi),
24-32 px arasi 183 hedef (hemen hepsi dugme). Bilgisayar dokunmatik ekranli; Microsoft dokunma icin yaklasik 40x40 px, sik yerlesimde
32x32 px oneriyor. Yeni ayar TouchTargets (Auto | Normal | Large; varsayilan Auto = dokunmatik ekran varsa Large):
  - kaynak sozlugunde TouchMin (sekme, onay kutusu, anahtar: Normal 24, Large 40; Kompakt yerlesimde 32) ve TouchBtnMin (dugmeler:
    Normal 0 yani degisiklik yok, Large 40 ya da 32); stiller DynamicResource ile okur, degisiklik aninda uygulanir;
  - Set-TouchTargets her yerlesim uygulamasinda (acilis dahil) ve ayar degisince cagrilir;
  - duman testi 'dokunma' kapsami (ve tam kapsamin bir bolumu): Buyuk kipte her sayfa ve alt sekme, Kompakt yerlesim; olcum ayri raporlanir
    (Buyuk kipte 24 px alti ve 32 px alti sifir olmali). Duman testi her zaman Normal kipte baslar ve kullanicinin ayarina doner.
"""


def apply(b):
    b.add_ui('162_dokunma.ps1', "function Initialize-Scrolling {\n", title='dokunma hedefleri: Otomatik / Normal / Buyuk')

    # ---- ayar varsayilani, sifirlama ----
    b.rep("        FocusRing    = $true\n", "        FocusRing    = $true\n        TouchTargets = 'Auto'\n", name='dokunma: ayar varsayilani')
    b.rep("'FocusRing', 'WidgetCorner'", "'FocusRing', 'TouchTargets', 'WidgetCorner'", count=2, name='dokunma: gorunum sifirlama anahtari')
    b.rep("    $st.FocusRing = $true\n", "    $st.FocusRing = $true\n    $st.TouchTargets = 'Auto'\n", name='dokunma: arayuz sifirlamada Otomatik')

    # ---- sol menu: Buyuk kipte dugme yuksekligi en az TouchMin (Sade yerlesimde 34-40 px idi); guvenli gorunum Normal kipte acilir ----
    b.rep("    if ($h -lt [int]$script:RailMin) { $h = [int]$script:RailMin }\n    return $h\n",
          "    if ($h -lt [int]$script:RailMin) { $h = [int]$script:RailMin }\n"
          "    if ($script:TouchMode -eq 'Large' -and $h -lt [int]$script:TouchMinNow) { $h = [int]$script:TouchMinNow }\n"
          "    return $h\n", name='dokunma: sol menu Buyuk kipte en az TouchMin')
    b.rep("        Backdrop = 'Yok'; WinOpacity = 100\n    }\n}\n",
          "        Backdrop = 'Yok'; WinOpacity = 100; TouchTargets = 'Normal'\n    }\n}\n", name='dokunma: guvenli gorunum Normal kipte acilir')

    # ---- varsayilan kaynaklar (Normal kip); Set-TouchTargets uygulama basinda ve ayar degisince uzerine yazar ----
    b.rep('        xmlns:shell="clr-namespace:System.Windows.Shell;assembly=PresentationFramework"\n        x:Name="Win"',
          '        xmlns:shell="clr-namespace:System.Windows.Shell;assembly=PresentationFramework"\n        xmlns:sys="clr-namespace:System;assembly=mscorlib"\n        x:Name="Win"',
          raw=True, name='dokunma: pencere kokunde System ad alani')
    b.rep('<CornerRadius x:Key="RadBtn">6</CornerRadius>\n',
          '<CornerRadius x:Key="RadBtn">6</CornerRadius>\n<sys:Double x:Key="TouchMin">24</sys:Double>\n<sys:Double x:Key="TouchBtnMin">0</sys:Double>\n',
          raw=True, name='dokunma: varsayilan kaynak degerleri (Normal)')

    # ---- stiller: alt sinir kaynak sozlugunden okunur ----
    b.rep('<Setter Property="MinHeight" Value="24"/>',
          '<Setter Property="MinHeight" Value="{DynamicResource TouchMin}"/>\n  <Setter Property="MinWidth" Value="{DynamicResource TouchMin}"/>',
          count=3, raw=True, name='dokunma: sekme, onay kutusu ve anahtar alt siniri kaynaktan (yukseklik ve genislik)')
    b.rep('<Style x:Key="BtnBase" TargetType="Button">\n',
          '<Style x:Key="BtnBase" TargetType="Button">\n  <Setter Property="MinHeight" Value="{DynamicResource TouchBtnMin}"/>\n  <Setter Property="MinWidth" Value="{DynamicResource TouchBtnMin}"/>\n',
          raw=True, name='dokunma: dugme alt siniri')
    b.rep('<Style x:Key="BtnIcon" TargetType="Button" BasedOn="{StaticResource BtnBase}">\n',
          '<Style x:Key="BtnIcon" TargetType="Button" BasedOn="{StaticResource BtnBase}">\n  <Setter Property="MinWidth" Value="{DynamicResource TouchBtnMin}"/>\n',
          raw=True, name='dokunma: simge dugmesi alt genisligi')
    b.rep('<Style x:Key="BtnTitle" TargetType="Button">\n',
          '<Style x:Key="BtnTitle" TargetType="Button">\n  <Setter Property="MinWidth" Value="{DynamicResource TouchBtnMin}"/>\n  <Setter Property="MinHeight" Value="{DynamicResource TouchBtnMin}"/>\n',
          raw=True, name='dokunma: baslik cubugu dugmeleri (sabit 38 px genislik)')
    b.rep('<Style x:Key="BtnBrand" TargetType="Button">\n',
          '<Style x:Key="BtnBrand" TargetType="Button">\n  <Setter Property="MinHeight" Value="{DynamicResource TouchBtnMin}"/>\n',
          raw=True, name='dokunma: marka (ana sayfa) dugmesi')
    b.rep('<Style x:Key="BtnLangCap" TargetType="Button">\n',
          '<Style x:Key="BtnLangCap" TargetType="Button">\n  <Setter Property="MinHeight" Value="{DynamicResource TouchBtnMin}"/>\n  <Setter Property="MinWidth" Value="{DynamicResource TouchBtnMin}"/>\n',
          raw=True, name='dokunma: ust cubuk dil ve asistan dugmesi alt siniri')

    # ---- uygulama: her yerlesim uygulamasinda (acilis dahil) ----
    b.before("    # Pencere dar ya da kisaysa gunluk ve komut satiri kendiliginden kapanir",
             "    try { Set-TouchTargets $Name } catch { Write-CrashLog ('Dokunma hedefleri: ' + $_.Exception.Message) }\n")

    # ---- Ayarlar > Gorunum ----
    b.after("Ctrl + 0 y&#x00FC;zde y&#x00FC;ze d&#x00F6;nd&#x00FC;r&#x00FC;r.\" Style=\"{DynamicResource TxtDim}\" TextWrapping=\"Wrap\" Margin=\"0,6,0,0\"/>\n",
            "      <Grid Margin=\"0,10,0,0\">\n"
            "        <Grid.ColumnDefinitions>\n"
            "          <ColumnDefinition Width=\"170\"/>\n"
            "          <ColumnDefinition Width=\"*\"/>\n"
            "        </Grid.ColumnDefinitions>\n"
            "        <TextBlock Text=\"Dokunma hedefleri\" Style=\"{DynamicResource TxtBody}\" VerticalAlignment=\"Center\"/>\n"
            "        <ComboBox x:Name=\"st_TouchSel\" Grid.Column=\"1\" Style=\"{DynamicResource Combo}\" ItemTemplate=\"{DynamicResource ComboText}\"/>\n"
            "      </Grid>\n"
            "      <TextBlock Text=\"Otomatik: dokunmatik ekran varsa Büyük. Büyük: düğmeler, sekmeler ve onay kutuları en az 40 piksel olur (Kompakt yerleşimde 32).\" Style=\"{DynamicResource TxtDim}\" TextWrapping=\"Wrap\" Margin=\"0,6,0,0\"/>\n",
            xaml=True)
    b.rep("    Set-ComboChoices $ui.st_ZoomSel $zm.ToArray()\n",
          "    Set-ComboChoices $ui.st_ZoomSel $zm.ToArray()\n"
          "    $tc = New-Object System.Collections.ArrayList\n"
          "    [void]$tc.Add((New-Choice 'Auto' 'Otomatik'))\n"
          "    [void]$tc.Add((New-Choice 'Normal' 'Normal'))\n"
          "    [void]$tc.Add((New-Choice 'Large' 'Büyük'))\n"
          "    Set-ComboChoices $ui.st_TouchSel $tc.ToArray()\n", name='dokunma: secenek listesi')
    b.rep("    [void](Select-ComboKey $ui.st_ZoomSel ([string]$z))\n",
          "    [void](Select-ComboKey $ui.st_ZoomSel ([string]$z))\n"
          "    [void](Select-ComboKey $ui.st_TouchSel (ConvertTo-TouchKey ([string]$script:Settings.TouchTargets)))\n", name='dokunma: kayitli secimi isaretle')
    b.rep("        $s.Zoom = [int]$z\n    }\n    $s.ReduceMotion = ($ui.st_ReduceMotion.IsChecked -eq $true)\n",
          "        $s.Zoom = [int]$z\n    }\n"
          "    $tk = Get-ComboKey $ui.st_TouchSel\n"
          "    if ($tk -ne '' -and (ConvertTo-TouchKey $tk) -ne (ConvertTo-TouchKey ([string]$s.TouchTargets))) {\n"
          "        $s.TouchTargets = ConvertTo-TouchKey $tk\n"
          "        Set-TouchTargets\n"
          "    }\n"
          "    $s.ReduceMotion = ($ui.st_ReduceMotion.IsChecked -eq $true)\n", name='dokunma: secimi uygula ve ayara yaz')
    b.rep("foreach ($n in @('st_ThemeSel', 'st_LayoutSel', 'st_ZoomSel', 'st_DesignSel',",
          "foreach ($n in @('st_ThemeSel', 'st_LayoutSel', 'st_ZoomSel', 'st_TouchSel', 'st_DesignSel',", name='dokunma: secim olayi')
    b.rep("'st_LookSel', 'st_ThemeSel', 'st_LayoutSel', 'st_ZoomSel',",
          "'st_LookSel', 'st_ThemeSel', 'st_LayoutSel', 'st_ZoomSel', 'st_TouchSel',", name='dokunma: duman testi bu listeyi secebilir')
    b.rep("    [void]$pairs.Add(@('st_ZoomSel', [string](Get-NearestZoomStep (ConvertTo-ZoomPct $s.Zoom))))\n",
          "    [void]$pairs.Add(@('st_ZoomSel', [string](Get-NearestZoomStep (ConvertTo-ZoomPct $s.Zoom))))\n"
          "    [void]$pairs.Add(@('st_TouchSel', (ConvertTo-TouchKey ([string]$s.TouchTargets))))\n", name='dokunma: duman liste esleme denetimi')

    # ---- duman testi: kapsam, kuyruk, adim ----
    b.rep("    tepsi   = @('tepsi', 'saglik')\n", "    tepsi   = @('tepsi', 'saglik')\n    dokunma = @('dokunma')\n", name='dokunma: kisa kapsam')
    b.rep("'yerlesim', 'hazir', 'esle', 'tasarim'", "'yerlesim', 'dokunma', 'hazir', 'esle', 'tasarim'", name='dokunma: tam kapsama eklendi')
    b.rep("[string]$StartHome = 'Pano|Auto|Auto|Auto|Auto|Auto') {",
          "[string]$StartHome = 'Pano|Auto|Auto|Auto|Auto|Auto', [string]$StartTouch = 'Normal') {", name='dokunma: kuyruk basligi')
    b.before("    $themes = @($Start)\n",
             "    # dokunma hedefleri her zaman Normal kipte baslar (Otomatik, dokunmatik ekranda Buyuk olurdu); sonda kullanicinin ayarina doner\n"
             "    if ($StartTouch -ne 'Normal') { $q.Enqueue((New-SmokeStep 'Touch' 'Normal' 600 'dokunma hedefleri: Normal (başlangıç)')) }\n")
    b.before("          if ($parts -contains 'hazir') {\n",
             "          if ($parts -contains 'dokunma') {\n"
             "            # dokunma hedefleri Buyuk: her sayfa ve alt sekme, sonra Kompakt yerlesim (32 px); olcum 'dokunma-' onekiyle ayri raporlanir\n"
             "            $q.Enqueue((New-SmokeStep 'Touch' 'Large' 900 'dokunma hedefleri: Büyük'))\n"
             "            foreach ($k in $Keys) {\n"
             "                $q.Enqueue((New-SmokeStep 'Page' $k 900 ('sayfa ' + $k + ' / dokunma')))\n"
             "                $q.Enqueue((New-SmokeStep 'Shot' ('dokunma-' + $k) 0 ('görüntü dokunma ' + $k)))\n"
             "                foreach ($tab in @(& $TabsOf $k)) {\n"
             "                    $q.Enqueue((New-SmokeStep 'Tab' $tab 500 ('sekme ' + $tab + ' / dokunma')))\n"
             "                    $q.Enqueue((New-SmokeStep 'Shot' ('dokunma-' + $k + '-' + $tab) 0 ('görüntü dokunma ' + $tab)))\n"
             "                }\n"
             "            }\n"
             "            $q.Enqueue((New-SmokeStep 'Layout' 'Kompakt' 800 'dokunma: Kompakt yerleşim'))\n"
             "            foreach ($pg in @('panel', 'optimize', 'network', 'settings')) {\n"
             "                $q.Enqueue((New-SmokeStep 'Page' $pg 800 ('sayfa ' + $pg + ' / dokunma Kompakt')))\n"
             "                $q.Enqueue((New-SmokeStep 'Shot' ('dokunma-Kompakt-' + $pg) 0 ('görüntü dokunma Kompakt ' + $pg)))\n"
             "            }\n"
             "            $q.Enqueue((New-SmokeStep 'Layout' $StartLayout 800 ('dokunma: yerleşim geri ' + $StartLayout)))\n"
             "            $q.Enqueue((New-SmokeStep 'Touch' 'Normal' 600 'dokunma hedefleri: Normal'))\n"
             "          }\n")
    b.before("    $q.Enqueue((New-SmokeStep 'Layout' $StartLayout 600 (",
             "    if ($StartTouch -ne 'Normal') { $q.Enqueue((New-SmokeStep 'Touch' $StartTouch 600 ('dokunma hedefleri geri: ' + $StartTouch))) }\n")
    b.rep("    $script:SmokeSteps = New-SmokeQueue $script:SmokeTheme $keys { param($k) Get-SmokeTabs $k } $script:SmokeLayout $scope $d0 $g0 $h0\n",
          "    $t0 = ConvertTo-TouchKey ([string]$script:Settings.TouchTargets)\n"
          "    Add-SmokeLine ('baslangic dokunma hedefleri=' + $t0 + '   dokunmatik ekran=' + [string](Test-TouchScreen))\n"
          "    $script:SmokeSteps = New-SmokeQueue $script:SmokeTheme $keys { param($k) Get-SmokeTabs $k } $script:SmokeLayout $scope $d0 $g0 $h0 $t0\n",
          name='dokunma: baslangic degeri kuyruga')
    b.before("        'Glass' {\n            $gp = $arg.Split('|')\n",
             "        'Touch' {\n"
             "            # kullanicinin ayari yerine gecici deneme degeri (duman testi kopya ayar klasorunde calisir); Set-TouchTargets kaynaklari gunceller\n"
             "            $script:Settings.TouchTargets = ConvertTo-TouchKey $arg\n"
             "            Set-TouchTargets\n"
             "            try { Save-Settings $script:Settings } catch { }\n"
             "        }\n")

    # tam kapsam artik Buyuk kip bolumunu da gezer (+6 dk); bilgisayar yogunken (Windows guncellemesi) onceki 3000 sn dar kaldi (27.11.2026: 3000 sn'de bitmedi)
    b.rep("$script:SmokeLimitSec = 3000\n", "$script:SmokeLimitSec = 4800\n", name='dokunma: duman zaman asimi 4800 sn')

    # ---- duman olcumu: Buyuk kip ayri sayilir ----
    b.rep("$script:SmokeA11yMax = 80\n", "$script:SmokeA11yMax = 200\n$script:SmokeA11yMaxLarge = 160\n", name='dokunma: olcum gorunum siniri (80 doluyordu); Buyuk kip ayri sayilir')
    b.rep("    if ([int]$A.Runs -ge [int]$script:SmokeA11yMax) { return }\n",
          "    if ($ctx.StartsWith('dokunma-')) {\n"
          "        if ([int]$A.LRuns -ge [int]$script:SmokeA11yMaxLarge) { $A.Capped = $true; return }\n"
          "    } elseif (([int]$A.Runs - [int]$A.LRuns) -ge [int]$script:SmokeA11yMax) { $A.Capped = $true; return }\n",
          name='dokunma: Normal ve Buyuk kip gorunum sinirlari ayri; dolarsa isaretlenir')
    b.rep("Named = @{}; Mis = @{}; Dup = @{}; Ms = 0 }",
          "Named = @{}; Mis = @{}; Dup = @{}; L24 = @{}; L32 = @{}; L40 = @{}; LRuns = 0; Capped = $false; Ms = 0 }", name='dokunma: Buyuk kip tablolari')
    b.rep("    $A.Runs = [int]$A.Runs + 1\n",
          "    $A.Runs = [int]$A.Runs + 1\n    if ($ctx.StartsWith('dokunma-')) { $A.LRuns = [int]$A.LRuns + 1 }\n", name='dokunma: Buyuk kip gorunum sayisi')
    b.rep("                if ($mn -lt 24) { if (-not $A.Small24.ContainsKey($key)) { $A.Small24[$key] = $ctx + ' ' + $sz } }\n"
          "                elseif ($mn -lt 32) { if (-not $A.Small32.ContainsKey($key)) { $A.Small32[$key] = $ctx + ' ' + $sz } }\n",
          "                if ($ctx.StartsWith('dokunma-')) {\n"
          "                    if ($mn -lt 24) { if (-not $A.L24.ContainsKey($key)) { $A.L24[$key] = $ctx + ' ' + $sz } }\n"
          "                    elseif ($mn -lt 32) { if (-not $A.L32.ContainsKey($key)) { $A.L32[$key] = $ctx + ' ' + $sz } }\n"
          "                    elseif ($mn -lt 40 -and $ctx.IndexOf('Kompakt') -lt 0 -and @('Button', 'CheckBox', 'RadioButton') -contains $kind) { if (-not $A.L40.ContainsKey($key)) { $A.L40[$key] = $ctx + ' ' + $sz } }\n"
          "                }\n"
          "                elseif ($mn -lt 24) { if (-not $A.Small24.ContainsKey($key)) { $A.Small24[$key] = $ctx + ' ' + $sz } }\n"
          "                elseif ($mn -lt 32) { if (-not $A.Small32.ContainsKey($key)) { $A.Small32[$key] = $ctx + ' ' + $sz } }\n",
          name='dokunma: Buyuk kipte olcum ayri tablolara')
    b.before("    if ($null -ne $script:A11yCalls) { Add-SmokeLine (",
             "    if ($A.Capped -eq $true) { Add-SmokeLine ('  UYARI: \u00f6l\u00e7\u00fcm g\u00f6r\u00fcn\u00fcm s\u0131n\u0131r\u0131 doldu; kalan g\u00f6r\u00fcn\u00fcmler \u00f6l\u00e7\u00fclmedi (Normal ' + [string]$script:SmokeA11yMax + ', B\u00fcy\u00fck ' + [string]$script:SmokeA11yMaxLarge + ')') }\n")
    b.before("    if ($null -ne $script:A11yCalls) { Add-SmokeLine (",
             "    if ([int]$A.LRuns -gt 0) {\n"
             "        Add-SmokeLine ('  dokunma hedefleri Büyük (' + [string]$A.LRuns + ' görünüm): 24 px altı: ' + [string]$A.L24.Count + '; 24-32 px arası: ' + [string]$A.L32.Count + '; 32-40 px arası (Kompakt dışı): ' + [string]$A.L40.Count)\n"
             "    }\n")
    b.rep("    )\n    foreach ($sec in $sections) {\n",
          "    )\n"
          "    if ([int]$A.LRuns -gt 0) {\n"
          "        $sections = @($sections) + @(\n"
          "            @{ T = 'DOKUNMA BÜYÜK: 24 PX ALTI'; M = $A.L24 },\n"
          "            @{ T = 'DOKUNMA BÜYÜK: 24-32 PX ARASI'; M = $A.L32 },\n"
          "            @{ T = 'DOKUNMA BÜYÜK: 32-40 PX ARASI (Kompakt dışı)'; M = $A.L40 }\n"
          "        )\n"
          "    }\n"
          "    foreach ($sec in $sections) {\n", name='dokunma: Buyuk kip rapor bolumleri')
