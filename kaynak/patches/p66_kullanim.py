# -*- coding: utf-8 -*-
"""Kullanim kolayligi (10.1.0):
 - Asistan: ust cubukta "Sor ya da ara" dugmesi (F1), pencere ici sohbet paneli; cevaplar yerel konu tablosundan
 - sol cubuk: kapali grup basliginin uzerinde beklenince grup acilir; sayfa dugmesinin uzerinde beklenince alt sekmeler menusu
 - uzun aciklamalar tek satir; tamami ipucunda (Ayarlar > "Aciklamalari tam goster" ile eski gorunum)
"""


def apply(b):
    # ---- ust cubuk: Asistan dugmesi (dil seciciden sonra)
    b.before('          <Popup x:Name="LangPop" Placement="Bottom"',
             '          <Border x:Name="AskCapsule" Margin="10,0,0,0" Background="{DynamicResource BrCard}" BorderBrush="{DynamicResource BrLine}" BorderThickness="1" CornerRadius="{DynamicResource RadBtn}" Padding="2">\n'
             '            <Button x:Name="BtnAsk" Style="{DynamicResource BtnLangCap}" ToolTip="Asistan: sorunuzu yaz&#x0131;n ya da bir i&#x015F;lem aray&#x0131;n (F1)">\n'
             '              <StackPanel Orientation="Horizontal">\n'
             '                <ContentControl Style="{DynamicResource Icon}" Tag="{DynamicResource IcoSearch}" Width="15" Height="15" Foreground="{DynamicResource BrAccent}"/>\n'
             '                <TextBlock x:Name="TxtAskHint" Text="Sor ya da ara" Margin="7,0,2,0" VerticalAlignment="Center" Foreground="{DynamicResource BrDim}"/>\n'
             '              </StackPanel>\n'
             '            </Button>\n'
             '          </Border>\n', raw=True)

    # ---- pencere ici Asistan paneli (onay kutusunun altinda kalir)
    b.before('      <Grid x:Name="Overlay" Grid.RowSpan="3" Visibility="Collapsed" Background="{DynamicResource BrOverlay}">',
             '      <Grid x:Name="AskOverlay" Grid.RowSpan="3" Visibility="Collapsed" Background="{DynamicResource BrOverlay}">\n'
             '        <Border x:Name="AskCard" Style="{DynamicResource Card}" Width="640" MaxHeight="600" HorizontalAlignment="Center" VerticalAlignment="Top" Margin="0,58,0,0" Padding="0" BorderBrush="{DynamicResource BrLine2}" Background="{DynamicResource BrPanel2}">\n'
             '          <Grid>\n'
             '            <Grid.RowDefinitions>\n'
             '              <RowDefinition Height="Auto"/>\n'
             '              <RowDefinition Height="*"/>\n'
             '              <RowDefinition Height="Auto"/>\n'
             '              <RowDefinition Height="Auto"/>\n'
             '            </Grid.RowDefinitions>\n'
             '            <Grid Grid.Row="0" Margin="18,14,12,4">\n'
             '              <StackPanel Orientation="Horizontal" VerticalAlignment="Center">\n'
             '                <ContentControl Style="{DynamicResource Icon}" Tag="{DynamicResource IcoSpark}" Width="17" Height="17" Foreground="{DynamicResource BrAccent}" VerticalAlignment="Center"/>\n'
             '                <TextBlock Text="Asistan" Style="{DynamicResource TxtH2}" Margin="9,0,0,0" VerticalAlignment="Center"/>\n'
             '                <TextBlock Text="yerel &#x00B7; veri g&#x00F6;ndermez" FontSize="11" Foreground="{DynamicResource BrFaint}" Margin="10,3,0,0" VerticalAlignment="Center"/>\n'
             '              </StackPanel>\n'
             '              <Button x:Name="AskClose" Style="{DynamicResource BtnMini}" Content="Kapat (Esc)" HorizontalAlignment="Right" VerticalAlignment="Center"/>\n'
             '            </Grid>\n'
             '            <ScrollViewer x:Name="AskScroll" Grid.Row="1" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Margin="0,4,4,0" MinHeight="150">\n'
             '              <StackPanel x:Name="AskChat" Margin="18,2,12,6"/>\n'
             '            </ScrollViewer>\n'
             '            <WrapPanel x:Name="AskChips" Grid.Row="2" Margin="18,6,16,0"/>\n'
             '            <Grid Grid.Row="3" Margin="18,6,16,16">\n'
             '              <Grid.ColumnDefinitions>\n'
             '                <ColumnDefinition Width="*"/>\n'
             '                <ColumnDefinition Width="Auto"/>\n'
             '              </Grid.ColumnDefinitions>\n'
             '              <TextBox x:Name="AskInput" Grid.Column="0" FontSize="13" Padding="10,7" MaxLength="200"/>\n'
             '              <Button x:Name="AskSend" Grid.Column="1" Style="{DynamicResource BtnPrimary}" Content="Sor" Margin="8,0,0,0" Padding="18,7"/>\n'
             '            </Grid>\n'
             '          </Grid>\n'
             '        </Border>\n'
             '      </Grid>\n', raw=True)

    # ---- kurulum: pencere hazirlanirken baglanir
    b.rep("    try { Initialize-HeaderBar } catch { Write-CrashLog ('Ust cubuk: ' + $_.Exception.Message) }\n",
          "    try { Initialize-HeaderBar } catch { Write-CrashLog ('Ust cubuk: ' + $_.Exception.Message) }\n"
          "    try { Initialize-UxExtras } catch { Write-CrashLog ('Kullanim: ' + $_.Exception.Message) }\n", raw=True, name='p66 kurulum')

    # ---- duyarli baslik: "Sor ya da ara" yazisi slogandan sonra ilk gizlenen ogedir
    b.rep("    if ($null -ne $ui.TxtLangCode) { Set-Visible $ui.TxtLangCode ($Level -lt 2) }\n}\n",
          "    if ($null -ne $ui.TxtLangCode) { Set-Visible $ui.TxtLangCode ($Level -lt 2) }\n"
          "    if ($null -ne $ui.TxtAskHint) { Set-Visible $ui.TxtAskHint ($Level -lt 1) }\n}\n", raw=True, name='p66 Set-TitleLevel')
    b.rep("    $script:TitleNat = @{ L = $l; C = $c; R = $r; Tag = $tag; Pill = $gain; Lab = $lab }\n",
          "    try { if ($null -ne $ui.TxtAskHint) { $tag = $tag + [double]$ui.TxtAskHint.DesiredSize.Width + [double]$ui.TxtAskHint.Margin.Left + [double]$ui.TxtAskHint.Margin.Right } } catch { }\n"
          "    $script:TitleNat = @{ L = $l; C = $c; R = $r; Tag = $tag; Pill = $gain; Lab = $lab }\n", raw=True, name='p66 Measure-TitleNatural')

    # ---- menu etiketi: alt sekmeye dogrudan gecis
    b.rep("    if ($kind -eq 'nav') { Show-Page $arg }\n",
          "    if ($kind -eq 'nav') { Show-Page $arg }\n"
          "    elseif ($kind -eq 'sub') { $sp = $arg.Split(':'); if ($sp.Count -ge 2) { Open-Page ([string]$sp[0]) ([string]$sp[1]) } else { Show-Page $arg } }\n",
          raw=True, name='p66 sub etiketi')
    b.rep("function Close-NavMenu {\n    if ($null -ne $script:NavPop) { $script:NavPop.IsOpen = $false }\n",
          "function Close-NavMenu {\n    if ($null -ne $script:NavPop) { $script:NavPop.IsOpen = $false }\n    try { Close-HoverMenu } catch { }\n",
          raw=True, name='p66 menuyu kapat')

    # ---- sol cubuk: grup basligi uzerinde bekleme; tiklama gecici acilisi kalici yapar
    b.rep("        $hdr.Add_MouseLeftButtonUp({ param($s, $e) Invoke-Safe { Switch-RailGroup ([string]$s.Tag) } ('Men' + [char]0x00FC + '') })\n",
          "        $hdr.Add_MouseLeftButtonUp({ param($s, $e) Invoke-Safe { Switch-RailGroup ([string]$s.Tag) } ('Men' + [char]0x00FC + '') })\n"
          "        $hdr.Add_MouseEnter($script:H_RailHdrEnter)\n", raw=True, name='p66 grup basligi')
    b.rep("        if ([string]$g.Key -eq $Key) { Set-GroupOpen $g (-not [bool]$g.Open) }\n    }\n    $script:RailH = 0\n",
          "        if ([string]$g.Key -eq $Key) { if ($g.Peek -eq $true -and [bool]$g.Open) { $g.Peek = $false } else { Set-GroupOpen $g (-not [bool]$g.Open) } }\n    }\n    $script:RailH = 0\n",
          raw=True, name='p66 grup tiklama')
    b.rep("        $b.Add_Click($script:H_FlyClick)\n", "        $b.Add_Click($script:H_FlyClick)\n        $b.Add_MouseEnter($script:H_FlyHover)\n", raw=True, name='p66 simge menusu')

    # ---- kisa aciklamalar
    b.rep("    $xaml = Expand-Template $tpl $Vars\n    return Read-LocalXaml ($xaml)\n}\n",
          "    $xaml = Expand-Template $tpl $Vars\n    $el = Read-LocalXaml ($xaml)\n    try { Set-DescCompact $el } catch { }\n    return $el\n}\n", raw=True, name='p66 satir aciklamasi')
    b.rep("    $xaml = Get-Variable -Scope Script -Name ('Page_' + $Key) -ValueOnly\n    $root = Read-LocalXaml ($xaml)\n",
          "    $xaml = Get-Variable -Scope Script -Name ('Page_' + $Key) -ValueOnly\n    $xaml = Add-DescTags ([string]$xaml)\n    $root = Read-LocalXaml ($xaml)\n", raw=True, name='p66 sayfa isaretleri')
    b.before("    if ($script:CardsOn -eq $true) {\n        try { Update-PageCards $root $true (Get-CardOpenCount $Key) }",
             "    try { [void](Set-PageDescCompact $root) } catch { }\n", raw=True)

    # ---- Ayarlar: aciklamalari tam goster
    b.after('      <CheckBox x:Name="st_ToTop" Content="A&#x015F;a&#x011F;&#x0131; inince ba&#x015F;a d&#x00F6;n d&#x00FC;&#x011F;mesini g&#x00F6;ster" Style="{DynamicResource Toggle}" Margin="0,8,0,0"/>\n',
            '      <CheckBox x:Name="st_FullDesc" Content="A&#x00E7;&#x0131;klamalar&#x0131; tam g&#x00F6;ster (kapal&#x0131;yken tek sat&#x0131;r g&#x00F6;r&#x00FC;n&#x00FC;r; tamam&#x0131; &#x00FC;zerine gelince okunur)" Style="{DynamicResource Toggle}" Margin="0,8,0,0" ToolTip="De&#x011F;i&#x015F;iklik, sayfalar yeniden a&#x00E7;&#x0131;ld&#x0131;&#x011F;&#x0131;nda (uygulama yeniden ba&#x015F;lat&#x0131;l&#x0131;nca) t&#x00FC;m&#x00FC;yle ge&#x00E7;erli olur."/>\n',
            raw=True)
    b.rep("    foreach ($n in @('st_ReduceMotion', 'st_Smooth', 'st_ToTop', 'st_FocusRing',", "    foreach ($n in @('st_ReduceMotion', 'st_Smooth', 'st_ToTop', 'st_FullDesc', 'st_FocusRing',", raw=True, name='p66 ayar listesi')
    b.rep("    $ui.st_ToTop.IsChecked = ($script:Settings.ToTopButton -ne $false)\n",
          "    $ui.st_ToTop.IsChecked = ($script:Settings.ToTopButton -ne $false)\n    $ui.st_FullDesc.IsChecked = ($script:Settings.FullDesc -eq $true)\n", raw=True, name='p66 ayar oku')
    b.rep("    $s.ToTopButton = ($ui.st_ToTop.IsChecked -eq $true)\n",
          "    $s.ToTopButton = ($ui.st_ToTop.IsChecked -eq $true)\n    $s.FullDesc = ($ui.st_FullDesc.IsChecked -eq $true)\n", raw=True, name='p66 ayar yaz')
    b.after("        FossOpenOnly = $false\n", "        FullDesc     = $false\n", raw=True)

    # ---- duman testi: "kullanim" kapsami
    b.rep(" | tasarim | saydam | dil | ust\n", " | tasarim | saydam | dil | ust | kullanim\n# \"kullanim\" kapsami Asistan'i, sol cubuk alt sekme menusunu, Yardimcilar sekmesini ve kisa aciklamalari dener; fareyi oynatmaz, panoya ve ayarlara dokunmaz.\n", raw=True, name='p66 kapsam notu')
    b.rep("'ornek', 'ust', 'tepsi', 'boyut'", "'ornek', 'ust', 'kullanim', 'tepsi', 'boyut'", raw=True, name='p66 tam kapsam')
    b.rep("    ust     = @('ust')\n", "    ust     = @('ust')\n    kullanim = @('kullanim')\n", raw=True, name='p66 kapsam')
    steps = (
        "          if ($parts -contains 'kullanim') {\n"
        "            $q.Enqueue((New-SmokeStep 'UxCheck' 'ask' 400 'Asistan: aç ve örnek soru sor'))\n"
        "            $q.Enqueue((New-SmokeStep 'Shot' 'kullanim-asistan' 300 'Asistan: pencere görüntüsü'))\n"
        "            $q.Enqueue((New-SmokeStep 'UxCheck' 'askclose' 200 'Asistan: kapat'))\n"
        "            $q.Enqueue((New-SmokeStep 'UxCheck' 'group' 200 'sol çubuk: grup geçici açılır ve kapanır'))\n"
        "            $q.Enqueue((New-SmokeStep 'UxCheck' 'hover' 300 'sol çubuk: alt sekme menüsü'))\n"
        "            $q.Enqueue((New-SmokeStep 'UxCheck' 'kit' 600 'Araçlar > Yardımcılar: liste, kısa açıklamalar, parola üreteci'))\n"
        "            $q.Enqueue((New-SmokeStep 'Shot' 'kullanim-yardimcilar' 300 'Yardımcılar: pencere görüntüsü'))\n"
        "            $q.Enqueue((New-SmokeStep 'UxCheck' 'desc' 500 'Ayarlar: kısa açıklamalar'))\n"
        "            $q.Enqueue((New-SmokeStep 'Shot' 'kullanim-ayarlar' 300 'Ayarlar: pencere görüntüsü'))\n"
        "            $q.Enqueue((New-SmokeStep 'UxCheck' 'drift' 300 'geri dönen ayarlar: eski ve yeni kural (yalnızca okuma)'))\n"
        "            $q.Enqueue((New-SmokeStep 'UxCheck' 'pano' 300 'ana ekran: ekran kartı ve sıcaklık kartları (ilk ölçüm beklenir)'))\n"
        "            $q.Enqueue((New-SmokeStep 'Shot' 'kullanim-pano' 300 'ana ekran: pencere görüntüsü'))\n"
        "            $q.Enqueue((New-SmokeStep 'Health' '' 1500 'sağlık taraması (yalnızca okur)'))\n"
        "            $q.Enqueue((New-SmokeStep 'Drain' '' 1500 'iş bitsin: sağlık taraması'))\n"
        "            $q.Enqueue((New-SmokeStep 'UxCheck' 'sorunlar' 300 'sorunlar: bulgular ve eylemleri (yalnızca okuma)'))\n"
        "            $q.Enqueue((New-SmokeStep 'UxCheck' 'kurulum' 400 'kurulum teklifi: kutu açılır, seçim yapılmadan kapatılır'))\n"
        "          }\n"
    )
    b.before("          if ($parts -contains 'tepsi') {\n", steps)
    b.after("        'UstCheck' { Test-SmokeHeader $arg }\n", "        'UxCheck' { Test-SmokeUx $arg }\n", raw=True)

    b.add_core('152_assist_core.ps1', title='asistan: cekirdek')
    b.add_ui('153_ux_ui.ps1', "function Init-Page_backup {\n", title='kullanim kolayligi: asistan, uzerine gelince acilan menuler, kisa aciklamalar')
