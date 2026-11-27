# -*- coding: utf-8 -*-
"""p90: Duman erisilebilirlik raporuna ekran okuyucu adlarinin dogrulugu (G-04).

b17'de adsiz denetim sayisi 46'dan 0'a indi (p86), ama verilen adlarin dogrulugu olculmuyordu. Rapor artik her gorunumde
gorunen denetimlerin "tur, capa, gorunen yazi -> verilen ad" listesini yazar (yalnizca okur; en cok 400 satir) ve iki riskli
durumu ayri bolumde one cikarir:
  - ad, gorunen yazi ya da ipucuyla ortusmuyor (baska ogenin yazisini alan onay kutusu gibi);
  - ayni gorunumde ayni turde ve ayni adi tasiyan birden cok denetim (ekran okuyucu bunlari ayirt edemez).
Adlarin kendisi olcume gore duzeltilecek; olcmeden duzeltme yok.
"""


def apply(b):
    b.before("function Get-A11yKind($El) {",
             "# Rapora yazilan gorunen yazi ve adlarda kisisel veri olmasin (IP, e-posta, kullanici klasoru yolu)\n"
             "function Protect-A11yText([string]$Text) {\n"
             "    $t = [string]$Text\n"
             "    $t = [regex]::Replace($t, '\\b\\d{1,3}(\\.\\d{1,3}){3}\\b', '<gizli>')\n"
             "    $t = [regex]::Replace($t, '[0-9A-Fa-f]{0,4}(:[0-9A-Fa-f]{0,4}){3,}', '<gizli>')\n"
             "    $t = [regex]::Replace($t, '[^\\s\"@]+@[^\\s\"@]+\\.[^\\s\"@]+', '<gizli>')\n"
             "    $t = [regex]::Replace($t, '(?i)\\\\Users\\\\[^\\\\\\s\"]+', '\\Users\\<gizli>')\n"
             "    return $t\n"
             "}\n\n"
             "# Ad, denetimin gorunen yazisi ya da ipucuyla ortusuyor mu? (biri digerini iceriyorsa ortusur; yazi yoksa sorun sayilmaz)\n"
             "function Test-A11yNameMismatch([string]$Label, [string]$Name) {\n"
             "    $l = ([string]$Label).Trim()\n"
             "    if ($l.StartsWith('ipucu: ')) { $l = $l.Substring(7) }\n"
             "    if ($l.EndsWith('...')) { $l = $l.Substring(0, $l.Length - 3) }\n"
             "    $l = $l.Trim()\n"
             "    if ($l -eq '' -or (Test-A11yNameBad $Name)) { return $false }\n"
             "    $n = ([string]$Name).Trim()\n"
             "    if ($n.StartsWith($l + ',', [System.StringComparison]::OrdinalIgnoreCase)) { return $false }\n"
             "    if ($n.Length -lt 3 -or $l.Length -lt 3) { return ($n -ne $l) }\n"
             "    if ($n.IndexOf($l, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { return $false }\n"
             "    if ($l.IndexOf($n, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { return $false }\n"
             "    return $true\n"
             "}\n\n")
    b.rep("Small32 = @{}; Ctx = @{}; Kinds = @{}; Ms = 0 }",
          "Small32 = @{}; Ctx = @{}; Kinds = @{}; Named = @{}; Mis = @{}; Dup = @{}; Ms = 0 }",
          name='erisim: olcum tablolari')
    b.rep("                $key = $kind + ' ' + (Get-A11yAnchor $o) + ' \"' + (Get-A11yLabel $o) + '\"'\n",
          "                $lab = Get-A11yLabel $o\n"
          "                $anc = Get-A11yAnchor $o\n"
          "                $key = $kind + ' ' + $anc + ' \"' + $lab + '\"'\n",
          name='erisim: gorunen yazi ayri degiskende')
    b.rep("                if (-not $A.NoName.ContainsKey($key)) {\n"
          "                    $name = ''\n"
          "                    try {\n"
          "                        $peer = [System.Windows.Automation.Peers.UIElementAutomationPeer]::CreatePeerForElement($o)\n"
          "                        if ($null -ne $peer) { $name = [string]$peer.GetName() }\n"
          "                    } catch { $name = '' }\n"
          "                    if (Test-A11yNameBad $name) { $A.NoName[$key] = $ctx }\n"
          "                }\n",
          "                $name = ''\n"
          "                try {\n"
          "                    $peer = [System.Windows.Automation.Peers.UIElementAutomationPeer]::CreatePeerForElement($o)\n"
          "                    if ($null -ne $peer) { $name = [string]$peer.GetName() }\n"
          "                } catch { $name = '' }\n"
          "                if (Test-A11yNameBad $name) {\n"
          "                    if (-not $A.NoName.ContainsKey($key)) { $A.NoName[$key] = $ctx }\n"
          "                } else {\n"
          "                    $nm1 = $name.Trim()\n"
          "                    if (-not $A.Named.ContainsKey($key)) {\n"
          "                        $A.Named[$key] = '-> \"' + $nm1 + '\" [' + $ctx + ']'\n"
          "                        if (Test-A11yNameMismatch $lab $nm1) { $A.Mis[$key] = '-> \"' + $nm1 + '\" [' + $ctx + ']' }\n"
          "                    }\n"
          "                    $dk = $ctx + ' ' + $kind + ' \"' + $nm1 + '\"'\n"
          "                    if (-not $A.Dup.ContainsKey($dk)) { $A.Dup[$dk] = @{ N = 0; Anchors = @{} } }\n"
          "                    $A.Dup[$dk].N = [int]$A.Dup[$dk].N + 1\n"
          "                    $A.Dup[$dk].Anchors[$anc] = $true\n"
          "                }\n",
          name='erisim: verilen adlari, tutarsizlari ve yinelenenleri topla')
    b.before("    if ($null -ne $script:A11yCalls) { Add-SmokeLine (",
             "    $dupShow = @{}\n"
             "    if ($null -ne $A.Dup) {\n"
             "        foreach ($dk in @($A.Dup.Keys)) {\n"
             "            $dv = $A.Dup[$dk]\n"
             "            if ([int]$dv.N -ge 2) { $dupShow[$dk] = [string]$dv.N + ' denetim, ' + [string]$dv.Anchors.Count + ' ayrı çapa: ' + ((@($dv.Anchors.Keys | Sort-Object | Select-Object -First 4)) -join ', ') }\n"
             "        }\n"
             "    }\n"
             "    if ($null -ne $A.Named) {\n"
             "        Add-SmokeLine ('  verilen ad listesi: ' + [string]$A.Named.Count + ' denetim; ad yazıyla örtüşmeyen: ' + [string]$A.Mis.Count + '; aynı görünümde aynı ad: ' + [string]$dupShow.Count)\n"
             "    }\n")
    b.rep("        @{ T = '24-32 PX ARASI'; M = $A.Small32 }\n    )",
          "        @{ T = '24-32 PX ARASI'; M = $A.Small32 },\n"
          "        @{ T = 'AD GÖRÜNEN YAZIYLA ÖRTÜŞMÜYOR (satır: tür çapa \"görünen yazı\" -> verilen ad)'; M = $A.Mis },\n"
          "        @{ T = 'AYNI GÖRÜNÜMDE AYNI TÜRDE AYNI AD (görünüm tür \"ad\")'; M = $dupShow },\n"
          "        @{ T = 'VERİLEN ADLAR (tür çapa \"görünen yazı\" -> verilen ad)'; M = $A.Named }\n"
          "    )",
          name='erisim: yeni rapor bolumleri')
    b.rep("        $m = $sec.M\n",
          "        $m = $sec.M\n"
          "        if ($null -eq $m) { $m = @{} }\n",
          name='erisim: eski olcum tablolarinda yeni bolum bos')
    b.rep("            [void]$sb.Append('  ' + [string]$k + '  |  ' + [string]$m[$k] + $nl)\n",
          "            [void]$sb.Append('  ' + (Protect-A11yText ([string]$k)) + '  |  ' + (Protect-A11yText ([string]$m[$k])) + $nl)\n",
          name='erisim: rapora yazilan satirlarda kisisel veri suzgeci')
