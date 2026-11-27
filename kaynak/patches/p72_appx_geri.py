# -*- coding: utf-8 -*-
"""Magaza uygulamasi kaldirma: geri alma (10.1.0).

"Geri al" magaza uygulamalarini geri getiremiyordu ("Store'dan yeniden yukleyin" uyarisi). Paket dosyalari WindowsApps altinda
duruyorsa (paket yalnizca bu kullanici icin kaldirildiysa ya da baska kullanicida hala yukluyse) AppxManifest.xml ile yeniden
kaydedilir; yoksa eski uyari kalir. Kaldirma gunlugune paketin kurulu oldugu klasor ve tam adi yazilir.
"""


def apply(b):
    b.rep("    if ($script:Preview) { Add-Plan (('Kald' + [char]0x0131 + 'r' + [char]0x0131 + 'lacak uygulama: ') + $name); return }\n"
          "    Add-Journal @{ T = 'Appx'; Name = $name }\n",
          "    if ($script:Preview) { Add-Plan (('Kald' + [char]0x0131 + 'r' + [char]0x0131 + 'lacak uygulama: ') + $name); return }\n"
          "    $locs = @($keepP | ForEach-Object { [string]$_.InstallLocation } | Where-Object { $_ -ne '' } | Sort-Object -Unique)\n"
          "    $fulls = @($keepP | ForEach-Object { [string]$_.PackageFullName })\n"
          "    Add-Journal @{ T = 'Appx'; Name = $name; Locs = $locs; Full = $fulls }\n",
          raw=True, name='p72 appx journal')
    b.rep("                'Appx' {\n"
          "                    Write-WhLog ((\"Uygulama otomatik geri gelmez; Microsoft Store'dan yeniden y\" + [char]0x00FC + \"kleyebilirsiniz: \") + $it.Name) 'WARN'\n"
          "                }\n",
          "                'Appx' {\n"
          "                    if (-not (Restore-AppxItem $it)) { Write-WhLog ((\"Uygulama otomatik geri gelmez; Microsoft Store'dan yeniden y\" + [char]0x00FC + \"kleyebilirsiniz: \") + $it.Name) 'WARN' }\n"
          "                }\n",
          raw=True, name='p72 appx undo')
    # yonetici olmayan surecte DISM "yukseltme gerekiyor" diye SilentlyContinue'ya ragmen sonlandirici hata atar
    b.rep("    if ($null -eq $script:Provisioned) { $script:Provisioned = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue) }\n    $pkgs = @(Get-AppxSafe $name)\n",
          "    if ($null -eq $script:Provisioned) { try { $script:Provisioned = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop) } catch { $script:Provisioned = @() } }\n    $pkgs = @(Get-AppxSafe $name)\n",
          raw=True, name='p72 provisioned guard')
    b.before("function Invoke-AppxOp($Op) {\n",
             "# Kaldirilan magaza uygulamasini paket klasorundeki AppxManifest.xml ile yeniden kaydeder (dosyalar duruyorsa). Donus: en az biri geri geldiyse $true\n"
             "function Restore-AppxItem($It) {\n"
             "    $ok = $false\n"
             "    foreach ($loc in @($It.Locs)) {\n"
             "        $mf = Join-Path ([string]$loc) 'AppxManifest.xml'\n"
             "        if ([string]$loc -eq '' -or -not (Test-Path -LiteralPath $mf)) { continue }\n"
             "        try {\n"
             "            Add-AppxPackage -Register $mf -DisableDevelopmentMode -ErrorAction Stop\n"
             "            Add-Done (('Uygulama geri kaydedildi: ') + [string]$It.Name)\n"
             "            $ok = $true\n"
             "        } catch { Write-WhLog (('Uygulama geri kaydedilemedi (') + [string]$It.Name + '): ' + $_.Exception.Message) 'WARN' }\n"
             "    }\n"
             "    return $ok\n"
             "}\n\n", raw=True)
