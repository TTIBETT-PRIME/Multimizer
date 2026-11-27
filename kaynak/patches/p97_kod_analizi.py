# -*- coding: utf-8 -*-
"""p97: G-07 kod analizi (PSScriptAnalyzer 1.25.0 + InjectionHunter 1.0.0, 27.11.2026, yerelde ve CI'da ayni paket).
- PSAvoidUsingComputerNameHardcoded (tek Error) yanlis alarm: Test-Connection hedefi 1.1.1.1 genel DNS, gizli bilgi degil;
  kural PSScriptAnalyzerSettings.psd1'de gerekceli disarida.
- PSUseDeclaredVarsMoreThanAssignments (22): hepsi eski duzenlemelerden kalmis olu atama, davranis hatasi degil.
  Cagri iceren atamalar [void](...) olur (yan etki ve cikti yutma korunur), saf atamalar silinir.
- PSPossibleIncorrectComparisonWithNull (2): $null sola alinir.
- Kultur sinamasindaki (136_oem_kultur.ps1) ornek bilgisayar adi gelistiricinin gercek makine adiydi; modulde dogrudan
  notr bir adla degistirildi ("I" harfi korunur), yama bu adi tasimaz.
"""


def apply(b):
    b.rep("    $curKey = ''\n",
          "",
          raw=True, name='Write-UndoRegFile: kullanilmayan $curKey')
    b.rep("        $p = Start-Process -FilePath (Join-Path $env:WINDIR 'System32\\cleanmgr.exe') -ArgumentList '/sagerun:99' -Wait -PassThru -WindowStyle Hidden\n",
          "        [void](Start-Process -FilePath (Join-Path $env:WINDIR 'System32\\cleanmgr.exe') -ArgumentList '/sagerun:99' -Wait -PassThru -WindowStyle Hidden)\n",
          raw=True, name='cleanmgr: -PassThru ciktisi')
    b.rep("    $freeGB = [math]::Round([double]$os.FreePhysicalMemory / 1MB, 1)\n",
          "",
          raw=True, name='Chk_Memory: kullanilmayan $freeGB')
    b.rep("            $r = Invoke-WingetRaw @('export', '-o', $wj, '--accept-source-agreements', '--disable-interactivity')\n",
          "            [void](Invoke-WingetRaw @('export', '-o', $wj, '--accept-source-agreements', '--disable-interactivity'))\n",
          raw=True, name='winget export ciktisi')
    b.rep("    $o = & netsh.exe wlan set profileparameter ('name=' + [string]$It.Name) ('connectionmode=' + [string]$It.Prev) 2>&1\n",
          "    [void](& netsh.exe wlan set profileparameter ('name=' + [string]$It.Name) ('connectionmode=' + [string]$It.Prev) 2>&1)\n",
          raw=True, name='netsh wlan profileparameter ciktisi')
    b.rep("        $o = & netsh.exe wlan export profile ('folder=' + $dir) 2>&1\n",
          "        [void](& netsh.exe wlan export profile ('folder=' + $dir) 2>&1)\n",
          raw=True, name='netsh wlan export ciktisi')
    b.rep("        $title = ''\n",
          "",
          raw=True, name='Job_LanScan: kullanilmayan $title')
    b.rep("        $q = Start-Process -FilePath $exe -ArgumentList ('/uninstalltunnelservice ' + $Name) -Wait -PassThru -WindowStyle Hidden\n",
          "        [void](Start-Process -FilePath $exe -ArgumentList ('/uninstalltunnelservice ' + $Name) -Wait -PassThru -WindowStyle Hidden)\n",
          raw=True, name='wireguard uninstalltunnelservice (1)')
    b.rep("    $p = Start-Process -FilePath $exe -ArgumentList ('/uninstalltunnelservice ' + $Name) -Wait -PassThru -WindowStyle Hidden\n",
          "    [void](Start-Process -FilePath $exe -ArgumentList ('/uninstalltunnelservice ' + $Name) -Wait -PassThru -WindowStyle Hidden)\n",
          raw=True, name='wireguard uninstalltunnelservice (2)')
    b.rep("            $o = & netsh.exe advfirewall set ($pn.ToLowerInvariant() + 'profile') firewallpolicy ('blockinbound,' + $pol) 2>&1\n",
          "            [void](& netsh.exe advfirewall set ($pn.ToLowerInvariant() + 'profile') firewallpolicy ('blockinbound,' + $pol) 2>&1)\n",
          raw=True, name='netsh advfirewall ciktisi')
    b.rep("    $proc.StartInfo = $psi\n"
          "    $lines = New-Object System.Collections.ArrayList\n"
          "    $errs = New-Object System.Collections.ArrayList\n",
          "    $proc.StartInfo = $psi\n"
          "    $lines = New-Object System.Collections.ArrayList\n",
          raw=True, name='Invoke-Restic: kullanilmayan $errs')
    b.rep("function Update-SvSelCount {\n"
          "    $n = (Get-CheckedData $ui.sv_List).Count\n"
          "    $q = Get-FilterText $ui.sv_Filter\n",
          "function Update-SvSelCount {\n"
          "    $n = (Get-CheckedData $ui.sv_List).Count\n",
          raw=True, name='Update-SvSelCount: kullanilmayan $q')
    b.rep("        $pct = [int][math]::Round(100.0 * $b / $max)\n",
          "",
          raw=True, name='Render-ClDisk: kullanilmayan $pct')
    b.rep("            $idx = $ui.bd_Canvas.Children.IndexOf($v.Root)\n",
          "",
          raw=True, name='Stop-BoardDrag: kullanilmayan $idx')
    b.rep("                $pv2 = Invoke-LiveJob 'Job_Plan' @{ Steps = (New-StepsFromIds @($id)); Preview = $true; RestorePoint = $false }\n",
          "                [void](Invoke-LiveJob 'Job_Plan' @{ Steps = (New-StepsFromIds @($id)); Preview = $true; RestorePoint = $false })\n",
          raw=True, name='canli: $pv2')
    b.rep("function Test-LiveJobs([string]$Group) {\n"
          "    $mode = Get-LiveMode\n",
          "function Test-LiveJobs([string]$Group) {\n"
          "    [void](Get-LiveMode)\n",
          raw=True, name='Test-LiveJobs: Get-LiveMode (onbellek yan etkisi korunur)')
    b.rep("        $mk = Get-LiveLogMark\n"
          "        $pv = Invoke-LiveJob 'Job_Plan' @{ Steps = (New-StepsFromIds @($id)); Preview = $true; RestorePoint = $false }\n"
          "        $lines = Get-LiveLogSince $mk\n",
          "        $mk = Get-LiveLogMark\n"
          "        $pv = Invoke-LiveJob 'Job_Plan' @{ Steps = (New-StepsFromIds @($id)); Preview = $true; RestorePoint = $false }\n"
          "        [void](Get-LiveLogSince $mk)\n",
          raw=True, name='Test-LiveComponents: $lines')
    b.rep("    $mkA = Get-LiveLogMark\n",
          "",
          raw=True, name='Test-LiveComponents: kullanilmayan $mkA')
    b.rep("        $note = ''\n"
          "        if ($jf -eq '') { [void]$defects.Add(('geri alma g' + [char]0x00FC + 'nl' + [char]0x00FC + '' + [char]0x011F + '' + [char]0x00FC + ' yaz' + [char]0x0131 + 'lmad' + [char]0x0131 + '')) }\n"
          "        else {\n"
          "            $mk2 = Get-LiveLogMark\n"
          "            $r2 = Invoke-LiveJob 'Job_Undo' @{ File = $jf }\n"
          "            $log2 = Get-LiveLogSince $mk2\n",
          "        $note = ''\n"
          "        if ($jf -eq '') { [void]$defects.Add(('geri alma g' + [char]0x00FC + 'nl' + [char]0x00FC + '' + [char]0x011F + '' + [char]0x00FC + ' yaz' + [char]0x0131 + 'lmad' + [char]0x0131 + '')) }\n"
          "        else {\n"
          "            $mk2 = Get-LiveLogMark\n"
          "            $r2 = Invoke-LiveJob 'Job_Undo' @{ File = $jf }\n"
          "            [void](Get-LiveLogSince $mk2)\n",
          raw=True, name='Invoke-LiveAppxTrip: $log2')
    b.rep("    $script:PendingProfile = $file\n"
          "    $notes = New-Object System.Collections.ArrayList\n"
          "    $steps = Get-ProfileSteps $prof $notes\n",
          "    $script:PendingProfile = $file\n"
          "    $notes = New-Object System.Collections.ArrayList\n"
          "    [void](Get-ProfileSteps $prof $notes)\n",
          raw=True, name='Start-CoImport: Get-ProfileSteps yalnizca $notes icin')
    b.rep("        $reg = [string]$s.Tag.Reg\n",
          "",
          raw=True, name='H_HiShow: kullanilmayan $reg')
    b.rep("        if ($script:BoardDrag -ne $null -and [string]$script:BoardDrag.Id -eq [string]$t.Id) { continue }\n",
          "        if ($null -ne $script:BoardDrag -and [string]$script:BoardDrag.Id -eq [string]$t.Id) { continue }\n",
          raw=True, name='BoardDrag: $null solda')
    b.rep("            if ([math]::Abs($w - $script:BoardLastGeo - 4.0) -gt 3.0 -and $script:BoardDrag -eq $null) { Update-BoardGeometry $false }\n",
          "            if ([math]::Abs($w - $script:BoardLastGeo - 4.0) -gt 3.0 -and $null -eq $script:BoardDrag) { Update-BoardGeometry $false }\n",
          raw=True, name='BoardDrag: $null solda (2)')
