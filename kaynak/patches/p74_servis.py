# -*- coding: utf-8 -*-
"""Windows ozelligi / bileseni islemleri: asili kalmaz, Windows Update mesgulken baslamaz (10.1.0).

Gercek bilgisayardaki tam denetimde (17.11.2026) Windows Update bir guncelleme kurarken Enable-WindowsOptionalFeature
1,5 saat bekleyip 0x80240021 verdi; ozellik geri acilamadi ve islem bu surede kilitli kaldi.
- mods/158: dism.exe ayri surecte, sure sinirli (15 dk) calisir; once yalnizca yerel kaynak (/LimitAccess), gerekirse
  Windows Update kaynagi (o anda guncelleme kurulmuyorsa).
- Ozellik/bilesen degisikligi Windows Update guncelleme kurarken hic baslamaz (geri alinamayacak bir yarim is birakmamak icin).
- Geri alma da ayni yolla calisir; basarisizsa nedeni ve ne yapilacagi yazilir.
"""


def apply(b):
    cv = lambda s: b._prep(s, False, False)
    b.add_core('158_servis.ps1', title='servis: DISM sure siniri, Windows Update mesgul denetimi')

    # --- Windows ozelligi: uygula
    b.rep("    Add-Journal @{ T = 'Feature'; Name = $name; WasEnabled = $isOn }\n"
          "    if ($wantOn) { Enable-WindowsOptionalFeature -Online -FeatureName $name -NoRestart -All -ErrorAction Stop | Out-Null }\n"
          "    else { Disable-WindowsOptionalFeature -Online -FeatureName $name -NoRestart -ErrorAction Stop | Out-Null }\n",
          cv("    $busy = Get-ServicingBusy\n"
          "    if ($busy -ne '') {\n"
          "        Write-WhLog ($busy + '; Windows özelliği şimdi değiştirilmedi (' + $name + '). Güncelleme bitince tekrar uygulayın.') 'WARN'\n"
          "        Add-Skip ('Windows Update meşgul, ertelendi: ' + $name)\n"
          "        return\n"
          "    }\n"
          "    Add-Journal @{ T = 'Feature'; Name = $name; WasEnabled = $isOn }\n"
          "    [void](Set-WinFeatureState $name $wantOn)\n"),
          raw=True, name='p74 feature apply')
    # --- Windows ozelligi: geri al
    b.rep("                    if ($it.WasEnabled -eq $true) { Enable-WindowsOptionalFeature -Online -FeatureName $it.Name -NoRestart -All -ErrorAction Stop | Out-Null }\n"
          "                    else { Disable-WindowsOptionalFeature -Online -FeatureName $it.Name -NoRestart -ErrorAction Stop | Out-Null }\n",
          "                    [void](Set-WinFeatureState ([string]$it.Name) ($it.WasEnabled -eq $true))\n",
          raw=True, name='p74 feature undo')

    # --- Windows bileseni: uygula
    b.rep("        Add-Journal @{ T = 'Cap'; Name = [string]$c.Name; WasInstalled = $isOn }\n"
          "        if ($wantAbsent) { Remove-WindowsCapability -Online -Name ([string]$c.Name) -ErrorAction Stop | Out-Null }\n"
          "        else { Add-WindowsCapability -Online -Name ([string]$c.Name) -ErrorAction Stop | Out-Null }\n",
          cv("        $busy = Get-ServicingBusy\n"
          "        if ($busy -ne '') {\n"
          "            Write-WhLog ($busy + '; Windows bileşeni şimdi değiştirilmedi (' + [string]$c.Name + '). Güncelleme bitince tekrar uygulayın.') 'WARN'\n"
          "            Add-Skip ('Windows Update meşgul, ertelendi: ' + [string]$c.Name)\n"
          "            continue\n"
          "        }\n"
          "        Add-Journal @{ T = 'Cap'; Name = [string]$c.Name; WasInstalled = $isOn }\n"
          "        [void](Set-WinCapabilityState ([string]$c.Name) (-not $wantAbsent))\n"),
          raw=True, name='p74 cap apply')
    # --- Windows bileseni: geri al
    b.rep("    if ([bool]$It.WasInstalled) { Add-WindowsCapability -Online -Name ([string]$It.Name) -ErrorAction Stop | Out-Null; Add-Done",
          "    if ([bool]$It.WasInstalled) { [void](Set-WinCapabilityState ([string]$It.Name) $true); Add-Done",
          raw=True, name='p74 cap undo add')
    b.rep("    else { Remove-WindowsCapability -Online -Name ([string]$It.Name) -ErrorAction Stop | Out-Null; Add-Done",
          "    else { [void](Set-WinCapabilityState ([string]$It.Name) $false); Add-Done",
          raw=True, name='p74 cap undo remove')
