# -*- coding: utf-8 -*-
"""Varsayilan gorunum (10.0.0): beyaz tema + sade yerlesim.

* Acik tema yeniden boyanir: beyaz yuzeyler, koyu lacivert (gece mavisi) dugme/vurgu rengi, eflatun ikinci vurgu.
* Yeni kurulumda tema Acik, yerlesim Sade olur. Eski surumden kalan kayitta (LookVersion yok) gorunum bir kez yeni varsayilana tasinir:
  tema, yerlesim, tasarim, saydamlik ve tasarim ayrintilari varsayilana doner; yakinlastirma, ana ekran bicimi, pano ve diger tercihler korunur.
  Tasimadan once ayarlarin kopyasi AyarYedekleri klasorune yazilir ("Son sifirlamayi geri al" eski gorunumu getirir); kopya yazilamazsa gorunume dokunulmaz.
  Gecis LookVersion ile yalnizca bir kez yapilir, LookNotice tek seferlik bilgi icindir.
* Hazir gorunumler: "Varsayilan (beyaz ve sade)" ve "Koyu neon" (eski varsayilan); "Sade acik" hazir gorunumu varsayilanla birlesti.
* Guvenli gorunum (hata firtinasi, guvenli baslangic, -Gorev GorunumSifirla) bilerek Neon + Ayrintili kalir: arayuzde gomulu en sinanmis yol.
  Bu yuzden yedege donus iletileri "varsayilan" yerine "guvenli" der.
"""


def apply(b):
    # ---- aciklama satiri
    b.rep("# Neon (Futuristik) varsayilandir (XAML'deki renkler). Koyu: daha az doygun. Acik: beyaz zemin. Yuksek: siyah zemin, beyaz yazi.\n",
          "# Acik (beyaz) varsayilan temadir. XAML'e Neon (koyu neon) renkleri gomulur; acilista Set-AppTheme paleti pencere kaynaklarina yerinde yazar. Koyu: daha az doygun. Yuksek: siyah zemin, beyaz yazi.\n",
          name='p61 tema aciklamasi')

    # ---- Acik palet: beyaz yuzeyler, koyu lacivert vurgu, eflatun ikinci vurgu
    b.rep("    # Acik (beyaz yuzeyler, kobalt mavisi ve eflatun vurgu)\n"
          "    Acik = [ordered]@{\n"
          "        BrBg = '#F2F5FC'; BrTitle = '#FFFFFF'; BrRail = '#F8FAFF'; BrPanel = '#FFFFFF'; BrPanel2 = '#FFFFFF'; BrCard = '#F4F7FE'\n"
          "        BrLine = '#DCE3F2'; BrLine2 = '#B7C4E2'; BrHover = '#E7EEFD'; BrActiveBg = '#DCE7FF'\n"
          "        BrText = '#101828'; BrDim = '#42506A'; BrFaint = '#65738E'\n"
          "        BrAccent = '#1D55E0'; BrAccentDim = '#5784F0'; BrAccent2 = '#7B3FE4'; BrBlue = '#0B7BB5'\n",
          "    # Acik (beyaz yuzeyler, koyu lacivert dugmeler ve eflatun ikinci vurgu; varsayilan tema)\n"
          "    Acik = [ordered]@{\n"
          "        BrBg = '#F6F7FB'; BrTitle = '#FFFFFF'; BrRail = '#FFFFFF'; BrPanel = '#FFFFFF'; BrPanel2 = '#FFFFFF'; BrCard = '#F8F9FC'\n"
          "        BrLine = '#E2E6F0'; BrLine2 = '#BAC3D9'; BrHover = '#EDF0F8'; BrActiveBg = '#E4E9F7'\n"
          "        BrText = '#101828'; BrDim = '#42506A'; BrFaint = '#65738E'\n"
          "        BrAccent = '#1B2A5C'; BrAccentDim = '#5B6A9C'; BrAccent2 = '#8B3FC8'; BrBlue = '#0B7BB5'\n",
          name='p61 acik palet 1')
    b.rep("BrDangerFg = '#9B1239'; BrMapBg = '#E9EFFC'; BrTipBg = '#F5FFFFFF'\n"
          "        BrBlueSoft = '#D3E6F4'; BrGoodSoft = '#D3E6E7'; BrAccent2Soft = '#E3DDFA'\n",
          "BrDangerFg = '#9B1239'; BrMapBg = '#EEF1F8'; BrTipBg = '#F5FFFFFF'\n"
          "        BrBlueSoft = '#D3E6F4'; BrGoodSoft = '#D3E6E7'; BrAccent2Soft = '#E9DFF6'\n",
          name='p61 acik palet 2')
    b.rep("    Acik   = @('#F8FAFF', '#EAF0FE', '#FDF1EC')\n",
          "    Acik   = @('#FBFCFE', '#F6F8FB', '#FBFCFE')\n", name='p61 acik gecis')
    b.rep("    Acik   = @{ T = 'Açık (beyaz)';     D = 'Beyaz yüzeyler, kobalt mavisi ve eflatun vurgu; hafif renkli zemin. Gün ışığında rahat okunur.' }\n",
          "    Acik   = @{ T = 'Beyaz';     D = 'Beyaz yüzeyler, koyu lacivert düğmeler ve eflatun ikinci vurgu; sade ve rahat okunur. Varsayılan tema.' }\n",
          name='p61 acik tema bilgisi')

    # ---- varsayilan ayarlar
    b.rep("        Theme        = 'Neon'\n", "        Theme        = 'Acik'\n", name='p61 varsayilan tema')
    b.rep("        Layout       = 'Ayrintili'\n", "        Layout       = 'Sade'\n", name='p61 varsayilan yerlesim')
    b.rep("        Language     = 'auto'\n    }\n}\n",
          "        Language     = 'auto'\n        LookVersion  = 10\n        LookNotice   = $false\n    }\n}\n", name='p61 gorunum surumu')

    # ---- eski surumden kalan kayitlarin gorunumu yeni varsayilana tasinir (bir kez; once ayarlarin kopyasi alinir)
    b.rep("            if ($obj -is [hashtable]) {\n"
          "                foreach ($k in @($obj.Keys)) { $s[$k] = $obj[$k] }\n"
          "            }\n",
          "            if ($obj -is [hashtable]) {\n"
          "                foreach ($k in @($obj.Keys)) { $s[$k] = $obj[$k] }\n"
          "                # 10.0.0: varsayilan gorunum beyaz ve sade oldu. Eski surumden kalan kaydin gorunumu (tema, yerlesim, tasarim, saydamlik) bir kez yeni varsayilana tasinir;\n"
          "                # tasimadan once ayarlarin kopyasi AyarYedekleri klasorune yazilir (Ayarlar > Sifirlama > Son sifirlamayi geri al eski gorunumu getirir). Kopya yazilamazsa\n"
          "                # gorunume dokunulmaz. Yakinlastirma, ana ekran bicimi, pano ve diger tercihler korunur. LookVersion gecisin bir kez yapilmasini saglar,\n"
          "                # LookNotice tek seferlik bilgi icindir. Gorunum anahtari hic olmayan (yeni) kayitta bilgi gosterilmez.\n"
          "                if (-not $obj.ContainsKey('LookVersion') -and ($obj.ContainsKey('Theme') -or $obj.ContainsKey('Layout'))) {\n"
          "                    $lookKeys = @('Theme', 'Layout', 'Design', 'Backdrop', 'WinOpacity', 'DsNav', 'DsRadius', 'DsFont', 'DsGraph', 'DsSkin')\n"
          "                    $dflt = Get-DefaultSettings\n"
          "                    $lookMoved = $false\n"
          "                    foreach ($lk in $lookKeys) {\n"
          "                        if ($obj.ContainsKey($lk) -and ([string]$obj[$lk]) -ne ([string]$dflt[$lk])) { $lookMoved = $true }\n"
          "                    }\n"
          "                    if ($lookMoved -and ([string](Save-SettingsBackup $obj 'gorunum')) -ne '') {\n"
          "                        foreach ($lk in $lookKeys) { $s[$lk] = $dflt[$lk] }\n"
          "                        $s.LookNotice = $true\n"
          "                    }\n"
          "                }\n"
          "            }\n",
          name='p61 gorunum gecisi')

    # ---- Windows yuksek karsitlik kipinde, tema secilmemisse (varsayilan tema duruyorsa) Yuksek karsitlik uygulanir
    b.rep("[System.Windows.SystemParameters]::HighContrast -and $t -eq 'Neon') { $t = 'Yuksek' } } catch { }",
          "[System.Windows.SystemParameters]::HighContrast -and $t -eq 'Acik') { $t = 'Yuksek' } } catch { }", name='p61 yuksek karsitlik')

    # ---- bilinmeyen tema / yerlesim adi varsayilana (beyaz, sade) doner
    b.rep("# Eski \"Sade\" tema Koyu'ya tasinir; bilinmeyen ad Neon olur\n"
          "function ConvertTo-ThemeKey([string]$Name) {\n"
          "    $t = [string]$Name\n"
          "    if ($t -eq 'Sade') { return 'Koyu' }\n"
          "    foreach ($k in @($script:Themes.Keys)) { if ([string]$k -eq $t) { return [string]$k } }\n"
          "    return 'Neon'\n"
          "}\n",
          "# Eski \"Sade\" tema Koyu'ya tasinir; bilinmeyen ad varsayilan tema (Acik) olur\n"
          "function ConvertTo-ThemeKey([string]$Name) {\n"
          "    $t = [string]$Name\n"
          "    if ($t -eq 'Sade') { return 'Koyu' }\n"
          "    foreach ($k in @($script:Themes.Keys)) { if ([string]$k -eq $t) { return [string]$k } }\n"
          "    return 'Acik'\n"
          "}\n", name='p61 tema anahtari')
    b.rep("    foreach ($k in @($script:LayoutInfo.Keys)) { if ([string]$k -eq $l) { return [string]$k } }\n    return 'Ayrintili'\n}\n",
          "    foreach ($k in @($script:LayoutInfo.Keys)) { if ([string]$k -eq $l) { return [string]$k } }\n    return 'Sade'\n}\n", name='p61 yerlesim anahtari')

    # ---- guvenli gorunum: aciklama (degerler degismez: Neon + Ayrintili en sinanmis yol)
    b.rep("# Hata firtinasinda, guvenli baslangicta ve \"gorunumu sifirla\" komutunda ayni degerler yazilir: varsayilan tema, yerlesim ve tasarim;\n"
          "# tasarim ayrintilari tasarimin kendi degerinde;",
          "# Hata firtinasinda, guvenli baslangicta ve \"GorunumSifirla\" komutunda ayni degerler yazilir: arayuzde gomulu en sinanmis tema (Neon), yerlesim (Ayrintili) ve tasarim;\n"
          "# tasarim ayrintilari tasarimin kendi degerinde;", name='p61 guvenli gorunum aciklamasi')

    # ---- hazir gorunumler
    b.rep("    Varsayilan = 'Varsayılan'; SadeAcik = 'Sade açık'; KompaktKoyu = 'Kompakt koyu'; Hacker = 'Terminal'\n",
          "    Varsayilan = 'Varsayılan (beyaz ve sade)'; KoyuNeon = 'Koyu neon'; KompaktKoyu = 'Kompakt koyu'; Hacker = 'Terminal'\n", name='p61 hazir gorunum adlari')
    b.rep("    $p = @{ Theme = 'Neon'; Layout = 'Ayrintili'; Zoom = 100; Design = 'Klasik'; Backdrop = 'Yok'; Opacity = 100; HomeMode = '' }\n"
          "    if ($Key -eq 'SadeAcik') { $p.Theme = 'Acik'; $p.Layout = 'Sade' }\n",
          "    $p = @{ Theme = 'Acik'; Layout = 'Sade'; Zoom = 100; Design = 'Klasik'; Backdrop = 'Yok'; Opacity = 100; HomeMode = '' }\n"
          "    if ($Key -eq 'KoyuNeon') { $p.Theme = 'Neon'; $p.Layout = 'Ayrintili' }\n", name='p61 hazir gorunum degerleri')
    b.rep("foreach ($pr in @(@('SadeAcik', 'Sade', 'Acik'), @('Hacker', 'Hacker', 'Hacker'), @('KompaktKoyu', 'Kompakt', 'Koyu'), @('Varsayilan', 'Ayrintili', 'Neon'))) {",
          "foreach ($pr in @(@('Varsayilan', 'Sade', 'Acik'), @('KoyuNeon', 'Ayrintili', 'Neon'), @('KompaktKoyu', 'Kompakt', 'Koyu'), @('Hacker', 'Hacker', 'Hacker'))) {",
          name='p61 duman hazir gorunumler')

    # ---- Klasik tasarimin onerdigi tema / yerlesim
    b.rep("            Skin = 'Plain'; Theme = 'Neon'; Layout = 'Ayrintili'; Tagline = '' }",
          "            Skin = 'Plain'; Theme = 'Acik'; Layout = 'Sade'; Tagline = '' }", name='p61 klasik tasarim')

    # ---- yedege donus iletileri: "varsayilan" yerine "guvenli" (donulen gorunum Neon + Ayrintili'dir)
    b.rep("Write-WhLog ('Tema (' + $t + ') tam uygulanamadığı için varsayılan görünüme dönüldü.') 'WARN'",
          "Write-WhLog ('Tema (' + $t + ') tam uygulanamadığı için güvenli görünüme dönüldü.') 'WARN'", name='p61 ileti tema gunluk')
    b.rep("Show-Toast 'Tema tam uygulanamadı; varsayılan görünüme dönüldü. Ayrıntı günlükte.' 'warn'",
          "Show-Toast 'Tema tam uygulanamadı; güvenli görünüme dönüldü. Ayrıntı günlükte.' 'warn'", name='p61 ileti tema')
    b.rep("Show-Toast 'Yerleşim tam uygulanamadı; varsayılan yerleşime dönüldü. Ayrıntı günlükte.' 'warn'",
          "Show-Toast 'Yerleşim tam uygulanamadı; güvenli yerleşime dönüldü. Ayrıntı günlükte.' 'warn'", name='p61 ileti yerlesim')
    b.rep("'m varsay' + [char]0x0131 + 'lana d' + [char]0x00F6 + 'nd' + [char]0x00FC + 'r' + [char]0x00FC + 'ld' + [char]0x00FC + ' (Neon tema, mini izleyici kapal'",
          "'m g' + [char]0x00FC + 'venli de' + [char]0x011F + 'erlere d' + [char]0x00F6 + 'nd' + [char]0x00FC + 'r' + [char]0x00FC + 'ld' + [char]0x00FC + ' (Neon tema, mini izleyici kapal'",
          raw=True, name='p61 ileti onceki acilis')
    b.rep("Write-CrashLog 'Güvenli başlangıç: önceki açılışlar tamamlanamadı; görünüm varsayılana döndürüldü.'",
          "Write-CrashLog 'Güvenli başlangıç: önceki açılışlar tamamlanamadı; görünüm güvenli değerlere döndürüldü.'", name='p61 ileti guvenli baslangic')
    b.rep("Write-WhLog ('G' + [char]0x00F6 + 'r' + [char]0x00FC + 'n' + [char]0x00FC + 'm varsay' + [char]0x0131 + 'lana d' + [char]0x00F6 + 'nd' + [char]0x00FC + 'r' + [char]0x00FC + 'ld' + [char]0x00FC + ' (tema: Neon, yerle'",
          "Write-WhLog ('G' + [char]0x00F6 + 'r' + [char]0x00FC + 'n' + [char]0x00FC + 'm g' + [char]0x00FC + 'venli de' + [char]0x011F + 'erlere d' + [char]0x00F6 + 'nd' + [char]0x00FC + 'r' + [char]0x00FC + 'ld' + [char]0x00FC + ' (tema: Neon, yerle'",
          raw=True, name='p61 ileti gorunum sifirla')
    b.rep("'m' + [char]0x00FC + ' varsay' + [char]0x0131 + 'lana d' + [char]0x00F6 + 'nd' + [char]0x00FC + 'r' + [char]0x00FC + 'r (tema Neon, yerle'",
          "'m' + [char]0x00FC + ' en g' + [char]0x00FC + 'venli bi' + [char]0x00E7 + 'ime d' + [char]0x00F6 + 'nd' + [char]0x00FC + 'r' + [char]0x00FC + 'r (tema Neon, yerle'",
          raw=True, name='p61 yardim gorunum sifirla')
    b.rep("      Multimizer.ps1 -Cli -Gorev GorunumSifirla   gorunumu varsayilana dondurur (tema Neon, yerlesim Ayrintili, yakinlastirma %100, mini izleyici kapali); uygulama acilmazsa",
          "      Multimizer.ps1 -Cli -Gorev GorunumSifirla   gorunumu en guvenli bicime dondurur (tema Neon, yerlesim Ayrintili, yakinlastirma %100, mini izleyici kapali); uygulama acilmazsa",
          name='p61 baslik gorunum sifirla')

    # ---- uygulama acilamazsa / hata firtinasinda iletiler: donulen gorunum "guvenli" gorunumdur (varsayilan artik beyaz ve sade)
    b.rep("'Yeniden açtığınızda varsayılan görünümle başlayacak.'", "'Yeniden açtığınızda güvenli görünümle başlayacak.'", name='p61 ileti firtina yeniden ac')
    b.rep("'Uygulamayı yeniden açtığınızda varsayılan görünümle başlayacak.'", "'Uygulamayı yeniden açtığınızda güvenli görünümle başlayacak.'", name='p61 ileti acilamadi yeniden ac')
    b.rep("' varsay' + [char]0x0131 + 'lan g' + [char]0x00F6 + 'r' + [char]0x00FC + 'n' + [char]0x00FC + 'mle olacak.')",
          "' g' + [char]0x00FC + 'venli g' + [char]0x00F6 + 'r' + [char]0x00FC + 'n' + [char]0x00FC + 'mle olacak.')", raw=True, name='p61 ileti hata dongusu')
    b.rep("uygulama kendini guvenle kapatir ve bir sonraki acilis varsayilan gorunumle olur.",
          "uygulama kendini guvenle kapatir ve bir sonraki acilis guvenli gorunumle (Neon, Ayrintili) olur.", name='p61 yorum firtina')
