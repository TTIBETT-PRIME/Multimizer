# -*- coding: utf-8 -*-
"""Ust cubuk (10.0.0): (1) sol ustteki Multimizer emblemi ana sayfa dugmesi olur (tiklaninca durum panosuna doner),
(2) KULLANICI | UZMAN kapsulunun yanina dil secici eklenir (kapsul + acilir liste; yerel dil adlari, kapsam yuzdesi, Otomatik),
(3) baslik cubugunun duyarli gizleme basamaklari yeni ogeyi hesaba katar, (4) duman testine 'ust' kapsami eklenir."""
from tr2ascii import convert


def apply(b):
    # ---- stiller: marka dugmesi (emblem) ve dil kapsulu dugmesi
    styles = r'''<Style x:Key="BtnBrand" TargetType="Button">
  <Setter Property="Foreground" Value="{DynamicResource BrText}"/>
  <Setter Property="Background" Value="Transparent"/>
  <Setter Property="BorderBrush" Value="Transparent"/>
  <Setter Property="BorderThickness" Value="1"/>
  <Setter Property="Padding" Value="8,4"/>
  <Setter Property="Margin" Value="-8,0,-2,0"/>
  <Setter Property="Cursor" Value="Hand"/>
  <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
  <Setter Property="Template">
    <Setter.Value>
      <ControlTemplate TargetType="Button">
        <Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="{DynamicResource RadBtn}" Padding="{TemplateBinding Padding}" SnapsToDevicePixels="True">
          <ContentPresenter HorizontalAlignment="Left" VerticalAlignment="Center"/>
        </Border>
        <ControlTemplate.Triggers>
          <Trigger Property="IsMouseOver" Value="True">
            <Setter TargetName="Bd" Property="Background" Value="{DynamicResource BrHover}"/>
          </Trigger>
          <Trigger Property="IsPressed" Value="True">
            <Setter TargetName="Bd" Property="Opacity" Value="0.75"/>
          </Trigger>
        </ControlTemplate.Triggers>
      </ControlTemplate>
    </Setter.Value>
  </Setter>
</Style>
<Style x:Key="BtnLangCap" TargetType="Button">
  <Setter Property="Foreground" Value="{DynamicResource BrText}"/>
  <Setter Property="Background" Value="Transparent"/>
  <Setter Property="BorderBrush" Value="Transparent"/>
  <Setter Property="BorderThickness" Value="1"/>
  <Setter Property="Padding" Value="11,6"/>
  <Setter Property="FontSize" Value="11.5"/>
  <Setter Property="FontWeight" Value="SemiBold"/>
  <Setter Property="Cursor" Value="Hand"/>
  <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
  <Setter Property="Template">
    <Setter.Value>
      <ControlTemplate TargetType="Button">
        <Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="{DynamicResource RadBtn}" Padding="{TemplateBinding Padding}" SnapsToDevicePixels="True">
          <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
        </Border>
        <ControlTemplate.Triggers>
          <Trigger Property="IsMouseOver" Value="True">
            <Setter TargetName="Bd" Property="Background" Value="{DynamicResource BrHover}"/>
          </Trigger>
          <Trigger Property="Tag" Value="open">
            <Setter TargetName="Bd" Property="Background" Value="{DynamicResource BrActiveBg}"/>
            <Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource BrAccentDim}"/>
            <Setter Property="Foreground" Value="{DynamicResource BrAccent}"/>
          </Trigger>
        </ControlTemplate.Triggers>
      </ControlTemplate>
    </Setter.Value>
  </Setter>
</Style>
'''
    b.before('<Style x:Key="BtnTitle" TargetType="Button">\n', styles, xaml=True)

    # ---- sol ust: emblem + yazi imi tek dugme (ana sayfa)
    old_brand = (
        '          <ContentControl Style="{DynamicResource Icon}" Tag="{DynamicResource IcoLogo}" Width="24" Height="24" Foreground="{DynamicResource BrAccent2}"/>\n'
        '          <TextBlock Text="MULTİMİZER" FontSize="15" FontWeight="Bold" Foreground="{DynamicResource BrText}" Margin="10,0,0,0" VerticalAlignment="Center"/>\n'
    )
    new_brand = (
        '          <Button x:Name="BtnHome" Style="{DynamicResource BtnBrand}" shell:WindowChrome.IsHitTestVisibleInChrome="True" ToolTip="Ana sayfa: durum panosuna dön">\n'
        '            <StackPanel Orientation="Horizontal">\n'
        '              <ContentControl Style="{DynamicResource Icon}" Tag="{DynamicResource IcoLogo}" Width="24" Height="24" Foreground="{DynamicResource BrAccent2}"/>\n'
        '              <TextBlock Text="MULTİMİZER" FontSize="15" FontWeight="Bold" Foreground="{DynamicResource BrText}" Margin="10,0,0,0" VerticalAlignment="Center"/>\n'
        '            </StackPanel>\n'
        '          </Button>\n'
    )
    b.rep(old_brand, new_brand, xaml=True, name='p63 emblem dugmesi')

    # ---- orta blok: KULLANICI | UZMAN kapsulunun yanina dil kapsulu ve acilir liste
    lang = r'''          <Border x:Name="LangCapsule" Margin="10,0,0,0" Background="{DynamicResource BrCard}" BorderBrush="{DynamicResource BrLine}" BorderThickness="1" CornerRadius="{DynamicResource RadBtn}" Padding="2">
            <Button x:Name="BtnLang" Style="{DynamicResource BtnLangCap}" ToolTip="Arayüz dili">
              <StackPanel Orientation="Horizontal">
                <ContentControl Style="{DynamicResource Icon}" Tag="{DynamicResource IcoGlobe}" Width="15" Height="15" Foreground="{DynamicResource BrAccent}"/>
                <TextBlock x:Name="TxtLangCode" Text="TR" Margin="7,0,0,0" VerticalAlignment="Center"/>
                <ContentControl Style="{DynamicResource Icon}" Tag="{DynamicResource IcoChevD}" Width="11" Height="11" Margin="6,1,0,0" Foreground="{DynamicResource BrDim}" VerticalAlignment="Center"/>
              </StackPanel>
            </Button>
          </Border>
          <Popup x:Name="LangPop" Placement="Bottom" StaysOpen="False" AllowsTransparency="True" PopupAnimation="Fade">
            <Border Background="{DynamicResource BrPanel2}" BorderBrush="{DynamicResource BrLine2}" BorderThickness="1" CornerRadius="12" Padding="6" Margin="10,4,10,14" MinWidth="272">
              <Border.Effect>
                <DropShadowEffect BlurRadius="16" ShadowDepth="3" Opacity="0.30" Color="#000000"/>
              </Border.Effect>
              <StackPanel>
                <TextBlock Text="ARAYÜZ DİLİ" FontSize="10.5" FontWeight="SemiBold" Foreground="{DynamicResource BrFaint}" Margin="10,6,0,4"/>
                <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" MaxHeight="430">
                  <StackPanel x:Name="LangItems" KeyboardNavigation.DirectionalNavigation="Cycle"/>
                </ScrollViewer>
                <Border BorderBrush="{DynamicResource BrLine}" BorderThickness="0,1,0,0" Margin="4,6,4,0" Padding="6,8,6,2">
                  <TextBlock Text="Dil değişince uygulama kendini yeniden başlatır." FontSize="11" Foreground="{DynamicResource BrDim}" TextWrapping="Wrap" MaxWidth="250"/>
                </Border>
              </StackPanel>
            </Border>
          </Popup>
'''
    b.rep('        </StackPanel>\n        <StackPanel x:Name="TitleRight"',
          lang + '        </StackPanel>\n        <StackPanel x:Name="TitleRight"', xaml=True, name='p63 dil kapsulu')

    # ---- baglama: kabukta ust cubuk olaylari; pencere etkinlikten cikinca dil listesi kapanir
    b.rep("    $ui.BtnCmdToggle.Add_Click({ Invoke-Safe { Switch-CmdPanel } 'Komut' })\n",
          "    $ui.BtnCmdToggle.Add_Click({ Invoke-Safe { Switch-CmdPanel } 'Komut' })\n"
          "    try { Initialize-HeaderBar } catch { Write-CrashLog ('Ust cubuk: ' + $_.Exception.Message) }\n", raw=True, name='p63 Initialize-Shell')
    b.rep("    $w.Add_Deactivated({ try { $ui.CmdPop.IsOpen = $false } catch { } })\n",
          "    $w.Add_Deactivated({ try { $ui.CmdPop.IsOpen = $false } catch { }; try { Close-LangMenu } catch { } })\n", raw=True, name='p63 Deactivated')

    # ---- duyarli baslik: dil kodu yazisi, sayfa adi kutusu daralirken (2. basamak) gizlenir; kazanc olculen genislige eklenir
    b.rep("    if ($null -ne $ui.TxtConnLbl) { Set-Visible $ui.TxtConnLbl $lab }\n}\n",
          "    if ($null -ne $ui.TxtConnLbl) { Set-Visible $ui.TxtConnLbl $lab }\n"
          "    if ($null -ne $ui.TxtLangCode) { Set-Visible $ui.TxtLangCode ($Level -lt 2) }\n}\n", raw=True, name='p63 Set-TitleLevel')
    b.rep("    $script:TitleNat = @{ L = $l; C = $c; R = $r; Tag = $tag; Pill = 40.0; Lab = $lab }\n",
          "    $gain = 40.0\n"
          "    try { if ($null -ne $ui.TxtLangCode) { $gain = $gain + [double]$ui.TxtLangCode.DesiredSize.Width + [double]$ui.TxtLangCode.Margin.Left } } catch { }\n"
          "    $script:TitleNat = @{ L = $l; C = $c; R = $r; Tag = $tag; Pill = $gain; Lab = $lab }\n", raw=True, name='p63 Measure-TitleNatural')

    # ---- duman testi: guvenli dugme, kapsam ve adimlar
    b.rep("    'sl_Scan', 'sl_DiskRefresh', 'sl_ErRefresh', 'sl_PcRefresh', 'sl_PrCheck', 'st_IntCheck'\n)",
          "    'sl_Scan', 'sl_DiskRefresh', 'sl_ErRefresh', 'sl_PcRefresh', 'sl_PrCheck', 'st_IntCheck', 'BtnHome'\n)", raw=True, name='p63 SmokeSafe')
    b.rep("Duman-Saydam.cmd, Duman-Dil.cmd). Kapsam", "Duman-Saydam.cmd, Duman-Dil.cmd, Duman-Ust.cmd). Kapsam", raw=True, name='p63 kapsam notu 1')
    b.rep(" | tasarim | saydam | dil\n# \"dil\" kapsami",
          " | tasarim | saydam | dil | ust\n# \"ust\" kapsami baslik cubugunu dener: ana sayfa emblemi baska sayfadan ana sayfaya doner, dil listesi acilir (dil secilmez), goruntusu alinip ceviri sizintisi taranir.\n# \"dil\" kapsami",
          raw=True, name='p63 kapsam notu 2')
    b.rep("'ornek', 'tepsi', 'boyut'", "'ornek', 'ust', 'tepsi', 'boyut'", raw=True, name='p63 tam kapsam')
    b.rep("    dil     = @('sayfa', 'sekme', 'tektema', 'dildenetim')\n",
          "    dil     = @('sayfa', 'sekme', 'tektema', 'dildenetim', 'ust')\n    ust     = @('ust')\n", raw=True, name='p63 dil/ust kapsami')

    steps = (
        "          if ($parts -contains 'ust') {\n"
        "            # ust cubuk: baska sayfadayken ana sayfa emblemine tiklanir; dil listesi acilir, goruntusu alinir ve kapanir (dil secilmez: secim uygulamayi yeniden baslatirdi)\n"
        "            $q.Enqueue((New-SmokeStep 'Page' 'settings' 700 'sayfa settings (ana sayfa emblemi için)'))\n"
        "            $q.Enqueue((New-SmokeStep 'Click' 'BtnHome' 700 'düğme: ana sayfa emblemi'))\n"
        "            $q.Enqueue((New-SmokeStep 'UstCheck' 'home' 100 'ana sayfa: emblem durum panosunu açtı mı'))\n"
        "            $q.Enqueue((New-SmokeStep 'Shot' 'ust-ana-sayfa' 200 'üst çubuk: pencere görüntüsü'))\n"
        "            $q.Enqueue((New-SmokeStep 'Screen' 'ust-ana-sayfa' 200 'üst çubuk: gerçek ekran görüntüsü'))\n"
        "            $q.Enqueue((New-SmokeStep 'LangPop' 'all' 300 'dil listesi: aç, görüntü al, çeviri tara, kapat'))\n"
        "            $q.Enqueue((New-SmokeStep 'UstCheck' 'lang' 100 'dil düğmesi: kod ve araç ipucu'))\n"
        "          }\n"
    )
    b.before("          if ($parts -contains 'tepsi') {\n", steps)

    cases = (
        "        'UstCheck' { Test-SmokeHeader $arg }\n"
        "        'LangPop' { Test-SmokeLangPop $arg }\n"
    )
    b.after("        'Resp' { Test-SmokeResp $arg }\n", cases, raw=True)

    # ---- moduller
    b.add_core('145_header_core.ps1', title='ust cubuk: dil dugmesi modeli')
    b.add_ui('146_header_ui.ps1', "function Init-Page_backup {\n", title='ust cubuk: ana sayfa emblemi ve dil secici')
