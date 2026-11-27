# -*- coding: utf-8 -*-
"""Ayarlari sifirla (10.0.0): Ayarlar > Sifirlama karti (gorunum anlik; tercihler yeniden baslatarak), kopya + geri alma, komut satiri gorevi AyarSifirla,
ve gorunum yeni varsayilana tasindiginda tek seferlik bilgi."""
from tr2ascii import convert


def apply(b):
    # ---- XAML: Ayarlar > Sifirlama karti (HAKKINDA kartinin onunda)
    card = (
        '  <Border Style="{DynamicResource Card}" Padding="16" Margin="0,0,0,10">\n'
        '    <StackPanel>\n'
        '      <TextBlock Text="SIFIRLAMA" Style="{DynamicResource TxtCardTitle}"/>\n'
        '      <TextBlock Text="Üç kapsam vardır: yalnızca görünüm, tüm uygulama tercihleri ya da her şey (Multimizer’ın Windows’ta yaptığı geri alınabilir değişiklikler dahil). İlk iki kapsamda Windows üzerinde yapılan değişiklikler, zamanlanmış görevler ve yedekleme ayarları değişmez." Style="{DynamicResource TxtDim}" TextWrapping="Wrap" Margin="0,6,0,0"/>\n'
        '      <Grid Margin="0,10,0,0">\n'
        '        <Grid.ColumnDefinitions>\n'
        '          <ColumnDefinition Width="170"/>\n'
        '          <ColumnDefinition Width="*"/>\n'
        '        </Grid.ColumnDefinitions>\n'
        '        <TextBlock Text="Kapsam" Style="{DynamicResource TxtBody}" VerticalAlignment="Center"/>\n'
        '        <ComboBox x:Name="st_ResetScope" Grid.Column="1" Style="{DynamicResource Combo}" ItemTemplate="{DynamicResource ComboText}"/>\n'
        '      </Grid>\n'
        '      <TextBlock x:Name="st_ResetNote" Text="" Style="{DynamicResource TxtDim}" TextWrapping="Wrap" Margin="0,6,0,0"/>\n'
        '      <WrapPanel Margin="0,8,0,0">\n'
        '        <Button x:Name="st_ResetRun" Content="Varsayılana sıfırla" Style="{DynamicResource BtnGhost}" Margin="0,0,8,6"/>\n'
        '        <Button x:Name="st_ResetUndo" Content="Son sıfırlamayı geri al" Style="{DynamicResource BtnGhost}" Margin="0,0,8,6" IsEnabled="False"/>\n'
        '        <Button x:Name="st_ResetFolder" Content="Ayar kopyaları klasörü" Style="{DynamicResource BtnGhost}" Margin="0,0,8,6"/>\n'
        '      </WrapPanel>\n'
        '      <TextBlock x:Name="st_ResetState" Text="" Style="{DynamicResource TxtDim}" TextWrapping="Wrap" Margin="0,2,0,0"/>\n'
        '    </StackPanel>\n'
        '  </Border>\n'
    )
    b.before('  <Border Style="{DynamicResource Card}" Padding="16">\n    <StackPanel>\n      <TextBlock Text="HAKKINDA" Style="{DynamicResource TxtCardTitle}"/>\n',
             card, xaml=True)

    # ---- Ayarlar sayfasi: yukleme ve baglama
    b.rep("    Load-StLang\n    $ui.st_UseCaseText.Text", "    Load-StLang\n    Load-StReset\n    $ui.st_UseCaseText.Text", raw=True, name='p62 Load-StExtra')
    b.rep("    Init-StUpdate\n    Initialize-StLang\n    Init-StLangEvents\n    Init-StExtra\n}\n",
          "    Init-StUpdate\n    Initialize-StLang\n    Init-StLangEvents\n    Initialize-StReset\n    Init-StReset\n    Init-StExtra\n}\n", raw=True, name='p62 Init-Page_settings')

    # ---- gorunum tasindiysa tek seferlik bilgi
    b.rep("    try { Initialize-PrepNudge } catch { Write-CrashLog ('PrepNudge: ' + $_.Exception.Message) }\n}\n",
          "    try { Initialize-PrepNudge } catch { Write-CrashLog ('PrepNudge: ' + $_.Exception.Message) }\n"
          "    try { Initialize-LookNotice } catch { Write-CrashLog ('LookNotice: ' + $_.Exception.Message) }\n}\n", raw=True, name='p62 Start-UiTimers')

    # ---- komut satiri: AyarSifirla
    b.rep("            'gorunumsifirla' { $code = Invoke-CliResetUi }\n",
          "            'ayarsifirla' { $code = Invoke-CliResetSettings }\n            'gorunumsifirla' { $code = Invoke-CliResetUi }\n", raw=True, name='p62 cli kolu')
    line = ("    Write-Raw '    AyarSifirla     -Deger Gorunum | Tercihler: görünümü ya da uygulama tercihlerini varsayılana döndürür (önceki ayarlar AyarYedekleri klasörüne kopyalanır; uygulama kapalıyken)'\n")
    b.before("    Write-Raw (('    GorunumSifirla  ", convert(line, 'yama'), raw=True)
    b.after("      Multimizer.ps1 -Cli -Gorev GorunumSifirla   gorunumu en guvenli bicime dondurur (tema Neon, yerlesim Ayrintili, yakinlastirma %100, mini izleyici kapali); uygulama acilmazsa\n",
            "      Multimizer.ps1 -Cli -Gorev AyarSifirla -Deger Gorunum|Tercihler   uygulama tercihlerini varsayilana dondurur (once AyarYedekleri klasorune kopyalar; uygulama kapaliyken)\n",
            raw=True)

    # ---- moduller
    b.add_core('143_settings_reset_core.ps1', title='ayarlari sifirla: cekirdek')
    b.add_ui('144_settings_reset_ui.ps1', "function Init-Page_backup {\n", title='ayarlari sifirla: Ayarlar karti ve gorunum bilgisi')
