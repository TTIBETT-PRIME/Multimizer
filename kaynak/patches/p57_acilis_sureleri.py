# -*- coding: utf-8 -*-
"""Acilis sureleri (10.0.0): surec baslangicindan betik baslangicina gecen sure, acilis asamalarinin baslangic sureleri ve
sistem profili adimlari pencere acildiginda oturum izine yazilir (gercek bilgisayarda acilisin nerede harcandigini gormek icin)."""


def apply(b):
    # --- sistem profili adim sureleri
    b.rep("function Get-SystemProfile {\n    $p = @{\n",
          "# Acilis olcumu: Get-SystemProfile adimlarinin baslangictan gecen sureleri (ms); yalnizca ilk cagri olculur\n"
          "$script:ProfSw = $null\n"
          "$script:ProfMs = @{}\n"
          "function Add-ProfMark([string]$Name) {\n"
          "    try {\n"
          "        if ($null -eq $script:ProfSw) { $script:ProfSw = [System.Diagnostics.Stopwatch]::StartNew() }\n"
          "        if (-not $script:ProfMs.ContainsKey($Name)) { $script:ProfMs[$Name] = [int]$script:ProfSw.ElapsedMilliseconds }\n"
          "    } catch { }\n"
          "}\n\n"
          "function Get-SystemProfile {\n    Add-ProfMark 'bas'\n    $p = @{\n",
          raw=True, name='p57 profil baslangic')
    b.rep("    $ed = $p.EditionId\n    if ($ed -match '^Core') { $ed = 'Home' }\n",
          "    Add-ProfMark 'kayit'\n    $ed = $p.EditionId\n    if ($ed -match '^Core') { $ed = 'Home' }\n",
          raw=True, name='p57 profil kayit')
    b.rep("    try {\n        $bat = @(Get-CimInstance -ClassName Win32_Battery -ErrorAction Stop)\n",
          "    Add-ProfMark 'cim'\n    try {\n        $bat = @(Get-CimInstance -ClassName Win32_Battery -ErrorAction Stop)\n",
          raw=True, name='p57 profil cim')
    b.rep("    # Azure AD / Intune (kayit defteri ile, hizli)\n",
          "    Add-ProfMark 'batarya'\n    # Azure AD / Intune (kayit defteri ile, hizli)\n",
          raw=True, name='p57 profil batarya')
    b.rep("    $p.SysDrive = $env:SystemDrive.TrimEnd(':')\n    try {\n        $vol = Get-Volume -DriveLetter $p.SysDrive -ErrorAction Stop\n",
          "    Add-ProfMark 'yonetim'\n    $p.SysDrive = $env:SystemDrive.TrimEnd(':')\n    try {\n        $vol = Get-Volume -DriveLetter $p.SysDrive -ErrorAction Stop\n",
          raw=True, name='p57 profil yonetim')
    b.rep("    try {\n        $part = Get-Partition -DriveLetter $p.SysDrive -ErrorAction Stop | Select-Object -First 1\n",
          "    Add-ProfMark 'hacim'\n    try {\n        $part = Get-Partition -DriveLetter $p.SysDrive -ErrorAction Stop | Select-Object -First 1\n",
          raw=True, name='p57 profil hacim')
    b.rep("            $p.DiskModel = [string]$pd.FriendlyName\n            $p.BusType = $bus\n        }\n    } catch { }\n\n    return $p\n}\n",
          "            $p.DiskModel = [string]$pd.FriendlyName\n            $p.BusType = $bus\n        }\n    } catch { }\n    Add-ProfMark 'disk'\n\n    return $p\n}\n",
          raw=True, name='p57 profil disk')

    # --- ozet metni (acilis asamalari + onyukleme + profil adimlari)
    b.rep("if (-not $Cli) { Start-Splash }\nSet-SplashStep 'arayuz'\n",
          "# Acilis sure ozeti (ms): onyukleme = surec baslangicindan betigin ilk satirina; sonra asama baslangiclari; sonra sistem profili adimlari\n"
          "function Get-StartupTimingText {\n"
          "    $parts = New-Object System.Collections.ArrayList\n"
          "    try {\n"
          "        $pr = [System.Diagnostics.Process]::GetCurrentProcess()\n"
          "        try { [void]$parts.Add('onyukleme=' + [string][int](($script:StartedAt) - $pr.StartTime).TotalMilliseconds) } finally { $pr.Dispose() }\n"
          "    } catch { }\n"
          "    try { $s = [string](Get-SplashSummary); if ($s -ne '') { [void]$parts.Add($s) } } catch { }\n"
          "    try { if ($null -ne $script:SplashClock) { [void]$parts.Add('toplam=' + [string][int]$script:SplashClock.ElapsedMilliseconds) } } catch { }\n"
          "    try {\n"
          "        $pk = New-Object System.Collections.ArrayList\n"
          "        foreach ($k in @('bas', 'kayit', 'cim', 'batarya', 'yonetim', 'hacim', 'disk')) { if ($script:ProfMs.ContainsKey($k)) { [void]$pk.Add($k + '=' + [string]$script:ProfMs[$k]) } }\n"
          "        if ($pk.Count -gt 0) { [void]$parts.Add('| profil: ' + ($pk.ToArray() -join ' ')) }\n"
          "    } catch { }\n"
          "    return ($parts.ToArray() -join ' ')\n"
          "}\n\n"
          "if (-not $Cli) { Start-Splash }\nSet-SplashStep 'arayuz'\n",
          raw=True, name='p57 ozet islevi')

    # --- pencere acilinca oturum izine yaz
    b.rep("    Add-Trace ('pencere a' + [char]0x00E7 + '' + [char]0x0131 + 'ld' + [char]0x0131 + '')\n    try {\n        $script:SessBeatTimer",
          "    Add-Trace ('pencere a' + [char]0x00E7 + '' + [char]0x0131 + 'ld' + [char]0x0131 + '')\n"
          "    try { Add-Trace (('a' + [char]0x00E7 + '' + [char]0x0131 + 'l' + [char]0x0131 + [char]0x015F + ' s' + [char]0x00FC + 'releri (ms): ') + (Get-StartupTimingText)) } catch { }\n"
          "    try {\n        $script:SessBeatTimer",
          raw=True, name='p57 iz satiri')
