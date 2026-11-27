# -*- coding: utf-8 -*-
"""Yardimcilar (10.1.0): Araclar > Yardimcilar sekmesi (parola uretici, toplu yeniden adlandirma, karne, internete baglanan programlar,
acik kaynak alternatifleri, Firefox ilkeleri, yeni bilgisayar adimlari, yardim paketi); Ucretsiz araclar listesinde lisans bilgisi ve suzgec;
plan motorunda once/sonra olcumu; BitLocker sekmesinde "Sifrelemeyi ac"; dosya sifreleme varsayilan olarak acik.
"""


def apply(b):
    # taban araç listesi FossToolsBase olur; FossTools tek yerde (150_kit_core) birleşik tanımlanır
    b.rep("$script:FossTools = @(\n", "$script:FossToolsBase = @(\n", raw=True, name='p65 foss taban')
    # ---- Araclar sayfasi: yeni sekme
    b.after('    <RadioButton x:Name="tl_Tab_ext" Content="D&#x0131;&#x015F; ara&#x00E7;lar" Tag="ext" GroupName="tl_tabs" Style="{DynamicResource Chip}"/>\n',
            '    <RadioButton x:Name="tl_Tab_kit" Content="Yard&#x0131;mc&#x0131;lar" Tag="kit" GroupName="tl_tabs" Style="{DynamicResource Chip}"/>\n', raw=True)
    b.rep("$script:TlTabs = @('win', 'procs', 'repair', 'files', 'sys', 'ext')\n",
          "$script:TlTabs = @('win', 'procs', 'repair', 'files', 'sys', 'ext', 'kit')\n", raw=True, name='p65 sekme listesi')
    b.rep("        'ext' { Show-OnlyBar 'tl' @('tl_Refresh'); Render-TlExt }\n",
          "        'ext' { Show-OnlyBar 'tl' @('tl_Refresh'); Render-TlExt }\n        'kit' { Show-OnlyBar 'tl' @(); Render-TlKit }\n", raw=True, name='p65 sekme')
    b.rep("        switch ([string]$s.Tag.Key) {\n            'hash' { Start-TlFileInfo }\n",
          "        switch ([string]$s.Tag.Key) {\n            'hash' { Start-TlFileInfo }\n            default { Invoke-TlExtraAct ([string]$s.Tag.Key) }\n",
          raw=True, name='p65 dugme dagitici')

    # ---- plan motoru: once / sonra olcumu
    b.rep("    try {\n        if ($doRp) { [void](Invoke-RestorePoint); Step-JobProgress }\n",
          "    Start-ScoreMeasure\n    try {\n        if ($doRp) { [void](Invoke-RestorePoint); Step-JobProgress }\n", raw=True, name='p65 karne basla')
    b.rep("        if (-not $script:Preview) { try { [void](Invoke-LiveRefresh @($script:JItems)) } catch { }; Close-Journal }\n",
          "        if (-not $script:Preview) { try { [void](Invoke-LiveRefresh @($script:JItems)) } catch { }; Close-Journal }\n"
          "        try { if ($steps.Count -gt 0) { Complete-ScoreMeasure ([string]$steps[0].Title) } } catch { }\n",
          raw=True, name='p65 karne bitir')

    # ---- Ucretsiz araclar: lisans eki ve suzgec
    b.rep("    $last = ''\n    foreach ($t in $script:FossTools) {\n        if ([string]$t.Cat -ne $last) { Add-HeadRow $ui.ap_List ([string]$t.Cat); $last = [string]$t.Cat }\n",
          "    $last = ''\n    Add-FossFilterRow\n    $openOnly = ($script:Settings.FossOpenOnly -eq $true)\n    foreach ($t in $script:FossTools) {\n"
          "        if (Test-FossHidden $t $openOnly) { continue }\n"
          "        if ([string]$t.Cat -ne $last) { Add-HeadRow $ui.ap_List ([string]$t.Cat); $last = [string]$t.Cat }\n",
          raw=True, name='p65 foss suzgec')
    b.rep("        $row = New-ItemRow @{ Title = [string]$t.N; Detail = [string]$t.D; Tag = [string]$t.Id; BrCol = 'BrAccent2' } $d $true $false\n",
          "        $row = New-ItemRow @{ Title = [string]$t.N; Detail = (Get-FossDetail $t); Tag = [string]$t.Id; BrCol = 'BrAccent2' } $d $true $false\n",
          raw=True, name='p65 foss lisans')
    b.after("        FixLevel     = 0\n", "        FossOpenOnly = $false\n", raw=True)

    # ---- dosya sifreleme varsayilan olarak acik
    b.rep("        OptCrypto    = $false\n", "        OptCrypto    = $true\n", raw=True, name='p65 sifreleme acik')

    # ---- BitLocker sekmesi: sifrelemeyi ac
    b.before("        $d = @{ Drive = [string]$r.Drive }\n        $row = New-ItemRow @{ Title = ([string]$r.Drive + (' s' + [char]0x00FC + 'r' + [char]0x00FC + 'c' + [char]0x00FC + 's' + [char]0x00FC + ''));",
             "        if ($r.Encrypted -ne $true) { $b1 = (Get-BlOnLabel) }\n", raw=True)
    b.rep("        elseif ($b1 -eq 'Anahtar ekle') { $row.FindName('Act').Add_Click($script:H_BkBlAdd) }\n",
          "        elseif ($b1 -eq 'Anahtar ekle') { $row.FindName('Act').Add_Click($script:H_BkBlAdd) }\n"
          "        elseif ($b1 -ne '') { $row.FindName('Act').Add_Click($script:H_BkBlOn) }\n",
          raw=True, name='p65 bl dugme')
    b.before("        $ui.bk_Foot.Text = ''\n        return\n    }\n    foreach ($r in $arr) {\n        $br = 'BrWarn'\n",
             "        Add-BlHomeRows\n", raw=True)

    # ---- parola ureteci eklentisi (kriptografik uretec ana betikte bulunmaz)
    b.rep("$script:MmExtNames = @('Sifreleme', 'Bellek', 'GuvenliSilme', 'WifiAktar', 'DiskKoruma', 'Kurtarma', 'DiskSilme')\n",
          "$script:MmExtNames = @('Sifreleme', 'Bellek', 'GuvenliSilme', 'WifiAktar', 'DiskKoruma', 'Kurtarma', 'DiskSilme', 'Parola')\n", raw=True, name='p65 eklenti listesi')
    b.after("#    Eklenti\\WifiAktar.ps1       Wi-Fi profillerini parolalariyla disa aktarma (tasinma kitinde acik secim)\n",
            "#    Eklenti\\Parola.ps1          parola uretici (Araclar > Yardimcilar)\n", raw=True)

    b.add_core('150_kit_core.ps1', title='yardimcilar: cekirdek')
    b.add_ui('151_kit_ui.ps1', "function Init-Page_backup {\n", title='yardimcilar: arayuz')
