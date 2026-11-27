# -*- coding: utf-8 -*-
"""Pencere acmayan baslatma (10.0.0).

Acilis.ps1 uygulamayi konsol penceresi GIZLI olarak baslatir ve kendi acilis ekranini (WinForms) gosterir. Uygulama tarafinda:
  -Gizli            konsola hicbir sey cizilmez; acilis asamasi, Acilis.ps1'in okudugu dosyaya yazilir
                    (ProgramData\\Multimizer\\acilis-<kod>.txt:  yuzde|sonraki asamanin yuzdesi|anahtar|surec numarasi)
  -Oturum <kod>     dosya adindaki kod (oturum-acik-<kod>.txt ile ayni)
Konsol gizli oldugu icin Hide-ConsoleWindow cagrilmaz (kucultme dali gizli konsolu gorunur yapardi).
Yeniden baslatma (dil degisikligi) ve kisayollar Acilis.ps1 uzerinden gider; boylece her acilista ayni acilis ekrani ve ayni denetim vardir.
"""


def apply(b):
    # ---- parametre ve yardim metni
    b.rep("    [string]$Dil = ''\n)\n", "    [string]$Dil = '',\n    [switch]$Gizli\n)\n", raw=True, name='p53 param')
    b.rep("      Multimizer.ps1 -OzTest                      kendi kendine sinama\n",
          "      Multimizer.ps1 -Gizli -Oturum KOD           konsol penceresi gizli baslatilir; acilis ilerlemesi dosyaya yazilir (Acilis.ps1 kullanir)\n"
          "      Multimizer.ps1 -OzTest                      kendi kendine sinama\n", raw=True, name='p53 yardim')
    b.rep("$script:StartedAt  = Get-Date\n", "$script:StartedAt  = Get-Date\n$script:GizliMode  = [bool]$Gizli\n", raw=True, name='p53 GizliMode')

    # ---- yeniden baslatma blogu: -Gizli aktarilir, pencere gizli acilir
    b.rep("    if ($Guvenli) { [void]$parts.Add('-Guvenli') }\n",
          "    if ($Guvenli) { [void]$parts.Add('-Guvenli') }\n    if ($Gizli) { [void]$parts.Add('-Gizli') }\n", raw=True, name='p53 yeniden baslatma')
    b.rep("    if ($Cli -or $Tepsi) { $winStyle = 'Hidden' }\n", "    if ($Cli -or $Tepsi -or $Gizli) { $winStyle = 'Hidden' }\n", raw=True, name='p53 pencere')

    # ---- acilis ilerlemesi dosyaya yazilir
    b.rep("# ---------------- acilis akisindan cagrilan islevler (hicbiri hata firlatmaz) ----------------\nfunction Start-Splash {\n    if ($script:SplashOn) { return }\n",
          "# Gizli baslatma: mevcut asamayi Acilis.ps1'in okudugu dosyaya yazar (yuzde|sonraki yuzde|anahtar|surec). Hata firlatmaz.\n"
          "function Write-SplashFile {\n"
          "    try {\n"
          "        if ([string]$script:SplashFile -eq '') { return }\n"
          "        $i = [int]$script:SplashIdx\n"
          "        $nx = $i + 1\n"
          "        if ($nx -ge $script:SplashPhases.Count) { $nx = $i }\n"
          "        $ph = $script:SplashPhases[$i]\n"
          "        $line = [string]$ph.Pct + '|' + [string]$script:SplashPhases[$nx].Pct + '|' + [string]$ph.Key + '|' + [string]$PID\n"
          "        [System.IO.File]::WriteAllText($script:SplashFile, $line, (New-Object System.Text.UTF8Encoding($false)))\n"
          "    } catch { }\n"
          "}\n\n"
          "# ---------------- acilis akisindan cagrilan islevler (hicbiri hata firlatmaz) ----------------\n"
          "$script:SplashFile = ''\n"
          "function Start-Splash {\n"
          "    if ($script:SplashOn) { return }\n"
          "    if ($Gizli) {\n"
          "        # konsol gizli: hicbir sey cizilmez; asama dosyaya yazilir (kod yoksa acilis ekrani yoktur)\n"
          "        try {\n"
          "            $script:SplashClock = [System.Diagnostics.Stopwatch]::StartNew()\n"
          "            $script:SplashTimes = @{}\n"
          "            $script:SplashIdx = 0\n"
          "            $script:SplashMode = 'off'\n"
          "            if ($Oturum -cmatch '^[A-Za-z0-9]{3,32}$') {\n"
          "                $sd = Join-Path $env:ProgramData 'Multimizer'\n"
          "                [void][System.IO.Directory]::CreateDirectory($sd)\n"
          "                $script:SplashFile = Join-Path $sd ('acilis-' + $Oturum + '.txt')\n"
          "                $script:SplashMode = 'dosya'\n"
          "                $script:SplashOn = $true\n"
          "                $script:SplashTimes['konsol'] = 0\n"
          "                Write-SplashFile\n"
          "            }\n"
          "        } catch {\n"
          "            $script:SplashOn = $false\n"
          "            $script:SplashMode = 'off'\n"
          "        }\n"
          "        return\n"
          "    }\n", raw=True, name='p53 Start-Splash')
    b.rep("function Update-Splash {\n    if (-not $script:SplashOn) { return }\n",
          "function Update-Splash {\n    if (-not $script:SplashOn) { return }\n    if ($script:SplashMode -eq 'dosya') { Write-SplashFile; return }\n", raw=True, name='p53 Update-Splash')

    # ---- gizli konsol yeniden gorunur yapilmaz
    b.rep("function Hide-ConsoleWindow {\n    try {\n", "function Hide-ConsoleWindow {\n    if ($Gizli) { return }\n    try {\n", raw=True, name='p53 Hide-ConsoleWindow')

    # ---- kurulum: Acilis.ps1 ve Tani.ps1 betigin yanina kopyalanir; kisayol Acilis.ps1'i acar
    b.rep("    Save-AppIcon (Join-Path $dir 'Multimizer.ico')\n    return $dst\n}\n",
          "    if ([System.IO.Path]::GetFullPath($srcDir) -ne [System.IO.Path]::GetFullPath($dir)) {\n"
          "        foreach ($side in @('Acilis.ps1', 'Tani.ps1')) {\n"
          "            $sp = Join-Path $srcDir $side\n"
          "            if (Test-Path -LiteralPath $sp) { try { Copy-Item -LiteralPath $sp -Destination (Join-Path $dir $side) -Force } catch { } }\n"
          "        }\n"
          "    }\n"
          "    Save-AppIcon (Join-Path $dir 'Multimizer.ico')\n    return $dst\n}\n", raw=True, name='p53 Install-AppFiles')
    b.rep("    $l.Arguments = ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File \"' + $ScriptPath + '\" ' + $Extra).Trim()\n",
          "    $launch = $ScriptPath\n"
          "    $ac = Join-Path (Split-Path -Parent $ScriptPath) 'Acilis.ps1'\n"
          "    if (Test-Path -LiteralPath $ac) { $launch = $ac }\n"
          "    $l.Arguments = ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File \"' + $launch + '\" ' + $Extra).Trim()\n", raw=True, name='p53 kisayol')
