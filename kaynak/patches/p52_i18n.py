# -*- coding: utf-8 -*-
"""Dil destegi (10.0.0): komut satiri parametresi, ayar varsayilani, cekirdek ve arayuz modulleri, XAML ceviri kancasi,
gunluk satiri / secim listesi / satir sablonu / bildirim kancalari ve Ayarlar > Dil karti.

Metin atamalarinin (Text, Content, ToolTip, Header, Title) Tr ile sarilmasi build.py icindeki i18n_wrap adiminda yapilir
(yamalardan sonra, tum metin uzerinde); bu yama yalnizca ozel durumlari ve kancalari ekler.
"""
import re


def apply(b):
    # ---- komut satiri parametresi ve yardim metni
    b.rep("    [switch]$DebugLog\n)\n", "    [switch]$DebugLog,\n    [string]$Dil = ''\n)\n", raw=True, name='p52 param')
    b.rep("      Multimizer.ps1 -OzTest                      kendi kendine sinama\n",
          "      Multimizer.ps1 -Dil en|de|fr|es|it|pt|ru|ja|zh|ko|ar|...   arayuz dilini bu oturum icin secer (kalici secim: Ayarlar > Dil; varsayilan: Windows ekran dili)\n"
          "      Multimizer.ps1 -OzTest                      kendi kendine sinama\n", raw=True, name='p52 yardim')
    # yeniden baslatma blogu: -Dil de aktarilir
    b.rep("    if ($DebugLog) { [void]$parts.Add('-DebugLog') }\n",
          "    if ($DebugLog) { [void]$parts.Add('-DebugLog') }\n"
          "    if ($Dil -ne '') { [void]$parts.Add('-Dil'); [void]$parts.Add('\"' + $Dil + '\"') }\n", raw=True, name='p52 yeniden baslatma')

    # ---- ayar varsayilani: auto = Windows ekran dili
    b.rep("        UpdateUrl    = ''\n    }\n}\n", "        UpdateUrl    = ''\n        Language     = 'auto'\n    }\n}\n", raw=True, name='p52 Language')

    # ---- XAML okuyucu: metinler cevrilerek okunur ([void] ile yalnizca sinanan yerler dokunulmaz)
    pat = re.compile(r'(?<!\[void\])\[System\.Windows\.Markup\.XamlReader\]::Parse\(')
    n = len(pat.findall(b.t))
    if n != 12:
        raise SystemExit('p52 XamlReader beklenen 12, bulunan %d' % n)
    b.t = pat.sub(lambda m: 'Read-LocalXaml (', b.t)

    # ---- cekirdek modul (arka plan is parcaciklari da kullanir; Turkce disinda dil yalnizca arayuz iscisinde etkindir)
    b.add_core('140_i18n_core.ps1', title='dil destegi: cekirdek')

    # ---- acilista dil secimi
    b.rep("$script:Settings = Get-Settings\n$sync.Settings = $script:Settings\n",
          "$script:Settings = Get-Settings\n$sync.Settings = $script:Settings\ntry { Initialize-Lang } catch { }\n", raw=True, name='p52 Initialize-Lang')

    # ---- gunluk satiri: onek (saat, duzey) korunur, ileti cevrilir; satirdaki metin bir daha sarilmaz
    b.rep("function Add-LogLine([string]$Line) {\n    $key = 'BrLogGreen'\n",
          "function Add-LogLine([string]$Line) {\n    $Line = Convert-LogLineText $Line\n    $key = 'BrLogGreen'\n", raw=True, name='p52 Add-LogLine')
    b.rep("    $tb.Text = $Line\n    $tb.Style = $script:Win.FindResource('TxtMono')\n",
          "    $tb.Text = $Line # Tr:yok\n    $tb.Style = $script:Win.FindResource('TxtMono')\n", raw=True, name='p52 Add-LogLine metin')

    # ---- acilir liste ogeleri (baglama ile gosterilir, atama yok)
    b.rep("    $c = @{ Key = $Key; Name = $Name; C1 = '#00000000'; C2 = '#00000000'; C3 = '#00000000'; C4 = '#00000000' }\n",
          "    $c = @{ Key = $Key; Name = (Tr $Name); C1 = '#00000000'; C2 = '#00000000'; C3 = '#00000000'; C4 = '#00000000' }\n", raw=True, name='p52 New-Choice')

    # ---- satir sablonlari: @@Metin@@ yer tutucularina konan metinler cevrilir
    b.rep("            if ($v.StartsWith('{')) { $v = '{}' + $v }\n",
          "            $v = [string](Tr $v)\n            if ($v.StartsWith('{')) { $v = '{}' + $v }\n", raw=True, name='p52 Expand-Template')

    # ---- buyuk harfe cevirme: etkin dilde once cevrilir, sonra degismez kulturle buyutulur (Turkce I kurali yalnizca Turkcede)
    b.rep("function ConvertTo-TrUpper([string]$Text) {\n    return (",
          "function ConvertTo-TrUpper([string]$Text) {\n    if ($script:LangOn) { return ([string](Tr $Text)).ToUpperInvariant() }\n    return (", raw=True, name='p52 ConvertTo-TrUpper')

    # ---- tepsi simgesi ipucu: sinir 63 karakter; once cevrilir, sonra kisaltilir
    b.rep("        if ($t.Length -gt 63) { $t = $t.Substring(0, 63) }\n        $script:Tray.Text = $t\n",
          "        $t = Tr $t\n        if ($t.Length -gt 63) { $t = $t.Substring(0, 63) }\n        $script:Tray.Text = $t # Tr:yok\n", raw=True, name='p52 Update-TrayTip')
    # ---- balon bildirimleri
    b.rep("        $t = Limit-Text $Title 60\n        $x = Limit-Text $Text 240\n",
          "        $t = Limit-Text (Tr $Title) 60\n        $x = Limit-Text (Tr $Text) 240\n", raw=True, name='p52 Show-Notify')
    b.rep("$script:Tray.ShowBalloonTip(4000, 'Multimizer', $text, [System.Windows.Forms.ToolTipIcon]::Info)",
          "$script:Tray.ShowBalloonTip(4000, 'Multimizer', (Tr $text), [System.Windows.Forms.ToolTipIcon]::Info)", raw=True, name='p52 balon')
    # ---- klasor secici aciklamasi
    b.rep("    $d = New-Object System.Windows.Forms.FolderBrowserDialog\n    $d.Description = $Desc\n",
          "    $d = New-Object System.Windows.Forms.FolderBrowserDialog\n    $d.Description = (Tr $Desc)\n", raw=True, name='p52 Select-Folder')

    # ---- Duman turu: baslik yazisi etkin dilde karsilastirilir
    b.rep("[string]$ui.TxtTagline.Text -ne [string]$spec.Tagline)", "[string]$ui.TxtTagline.Text -ne [string](Tr $spec.Tagline))", raw=True, name='p52 duman baslik')

    # ---- XAML: Ayarlar > Dil karti (GENEL kartinin onunda)
    card = (
        '  <Border Style="{DynamicResource Card}" Padding="16" Margin="0,0,0,10">\n'
        '    <StackPanel>\n'
        '      <TextBlock Text="Dil / Language" Style="{DynamicResource TxtCardTitle}"/>\n'
        '      <TextBlock Text="Arayüz dilini seçin. Otomatik seçenek Windows ekran dilini izler; çevirisi olmayan metinler İngilizce, o da yoksa Türkçe görünür." Style="{DynamicResource TxtDim}" TextWrapping="Wrap" Margin="0,6,0,0"/>\n'
        '      <Grid Margin="0,10,0,0">\n'
        '        <Grid.ColumnDefinitions>\n'
        '          <ColumnDefinition Width="170"/>\n'
        '          <ColumnDefinition Width="*"/>\n'
        '        </Grid.ColumnDefinitions>\n'
        '        <TextBlock Text="Arayüz dili" Style="{DynamicResource TxtBody}" VerticalAlignment="Center"/>\n'
        '        <ComboBox x:Name="st_LangSel" Grid.Column="1" Style="{DynamicResource Combo}" ItemTemplate="{DynamicResource ComboText}"/>\n'
        '      </Grid>\n'
        '      <TextBlock x:Name="st_LangNote" Text="" Style="{DynamicResource TxtDim}" TextWrapping="Wrap" Margin="0,6,0,0"/>\n'
        '      <WrapPanel Margin="0,8,0,0">\n'
        '        <Button x:Name="st_LangApply" Content="Uygula ve yeniden başlat" Style="{DynamicResource BtnPrimary}" Margin="0,0,8,6" IsEnabled="False"/>\n'
        '        <Button x:Name="st_LangFolder" Content="Dil dosyaları klasörü" Style="{DynamicResource BtnGhost}" Margin="0,0,8,6"/>\n'
        '      </WrapPanel>\n'
        '    </StackPanel>\n'
        '  </Border>\n'
    )
    b.before('  <Border Style="{DynamicResource Card}" Padding="16" Margin="0,0,0,10">\n    <StackPanel>\n      <TextBlock Text="GENEL" Style="{DynamicResource TxtCardTitle}"/>\n',
             card, xaml=True)

    # ---- Ayarlar sayfasi: yukleme ve baglama
    b.rep("    Load-StUpdate\n    $ui.st_UseCaseText.Text", "    Load-StUpdate\n    Load-StLang\n    $ui.st_UseCaseText.Text", raw=True, name='p52 Load-StExtra')
    b.rep("    Init-StUpdate\n    Init-StExtra\n}\n", "    Init-StUpdate\n    Initialize-StLang\n    Init-StLangEvents\n    Init-StExtra\n}\n", raw=True, name='p52 Init-Page_settings')

    # ---- arayuz modulu
    b.add_ui('141_i18n_ui.ps1', "function Init-Page_backup {\n", title='dil destegi: Ayarlar karti ve kalite denetimi')
    b.add_ui('142_i18n_check.ps1', "function Init-Page_backup {\n", title='dil destegi: duman testi dil denetimi (Duman-Dil.cmd)')
