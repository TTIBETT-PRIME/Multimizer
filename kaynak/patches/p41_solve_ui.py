# -*- coding: utf-8 -*-
"""Cozum Merkezi sayfasi: XAML, gezinme, simge, arka plan isleri ve arayuz islevleri."""

PAGE_XAML = r'''$script:Page_solve = @'
<Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Margin="0,0,6,0">
  <Grid.RowDefinitions>
    <RowDefinition Height="Auto"/>
    <RowDefinition Height="Auto"/>
    <RowDefinition Height="Auto"/>
    <RowDefinition Height="Auto"/>
    <RowDefinition Height="*"/>
    <RowDefinition Height="Auto"/>
  </Grid.RowDefinitions>
  <StackPanel Grid.Row="0" Margin="0,0,0,10">
    <TextBlock x:Name="sl_Title" Text="Çözüm Merkezi" Style="{DynamicResource TxtH1}"/>
    <TextBlock x:Name="sl_Desc" Text="Sorunları bulur ve düzeltir: tarama, disk şifreleme ve sağlık, silinen dosya kurtarma, kalıcı silme, sorun gidericiler ve eksik bileşenler." Style="{DynamicResource TxtDim}" TextWrapping="Wrap"/>
  </StackPanel>
  <WrapPanel x:Name="sl_Tabs" Grid.Row="1" Margin="0,0,0,8">
    <RadioButton x:Name="sl_Tab_scan" Content="Sorunlar" Tag="scan" GroupName="sl_tabs" Style="{DynamicResource Chip}" IsChecked="True"/>
    <RadioButton x:Name="sl_Tab_disk" Content="Diskler" Tag="disk" GroupName="sl_tabs" Style="{DynamicResource Chip}"/>
    <RadioButton x:Name="sl_Tab_recover" Content="Silinen dosyalar" Tag="recover" GroupName="sl_tabs" Style="{DynamicResource Chip}"/>
    <RadioButton x:Name="sl_Tab_erase" Content="Kalıcı silme" Tag="erase" GroupName="sl_tabs" Style="{DynamicResource Chip}"/>
    <RadioButton x:Name="sl_Tab_trouble" Content="Sorun gidericiler" Tag="trouble" GroupName="sl_tabs" Style="{DynamicResource Chip}"/>
    <RadioButton x:Name="sl_Tab_pc" Content="Bilgisayarım" Tag="pc" GroupName="sl_tabs" Style="{DynamicResource Chip}"/>
    <RadioButton x:Name="sl_Tab_prep" Content="Hazırlık" Tag="prep" GroupName="sl_tabs" Style="{DynamicResource Chip}"/>
  </WrapPanel>
  <WrapPanel x:Name="sl_Bar" Grid.Row="2" Margin="0,0,0,4">
    <Button x:Name="sl_Scan" Content="Bilgisayarı tara" Style="{DynamicResource BtnPrimary}" Margin="0,0,8,6" />
    <Button x:Name="sl_ScanFull" Content="Tam denetim" Style="{DynamicResource BtnGhost}" Margin="0,0,8,6" />
    <Button x:Name="sl_FixAll" Content="Otomatik olanları düzelt" Style="{DynamicResource BtnGhost}" Margin="0,0,8,6" />
    <Button x:Name="sl_DiskRefresh" Content="Yenile" Style="{DynamicResource BtnGhost}" Margin="0,0,8,6" Visibility="Collapsed" />
    <ComboBox x:Name="sl_RcVol" Width="460" Margin="0,0,8,6" Visibility="Collapsed" Style="{DynamicResource Combo}" ItemTemplate="{DynamicResource ComboText}" ToolTip="Taranacak sürücü, USB bellek, fiziksel disk ya da disk imajı"/>
    <Button x:Name="sl_RcImg" Content="Disk imajı seç..." Style="{DynamicResource BtnGhost}" Margin="0,0,8,6" Visibility="Collapsed" ToolTip="Ham disk imajı (.img, .dd, .raw, .bin) açar; imaj yalnızca okunur"/>
    <Button x:Name="sl_RcQuick" Content="Hızlı tara" Style="{DynamicResource BtnPrimary}" Margin="0,0,8,6" Visibility="Collapsed" ToolTip="Silinmiş dosya kayıtlarını okur (NTFS, FAT, exFAT); ad, klasör ve tarih korunur. Kayıt tutmayan biçimlerde imza taraması yapar"/>
    <Button x:Name="sl_RcDeep" Content="Derin tara" Style="{DynamicResource BtnGhost}" Margin="0,0,8,6" Visibility="Collapsed" ToolTip="Boş alanı dosya imzalarına göre de tarar; adı bilinmeyen dosyalar da bulunur, uzun sürebilir"/>
    <ComboBox x:Name="sl_RcType" Width="200" Margin="0,0,8,6" Visibility="Collapsed" Style="{DynamicResource Combo}" ItemTemplate="{DynamicResource ComboText}" ToolTip="Bulunan dosyaları türüne göre süz"/>
    <Button x:Name="sl_RcDest" Content="Kurtarma klasörü seç..." Style="{DynamicResource BtnGhost}" Margin="0,0,8,6" Visibility="Collapsed" ToolTip="Kurtarılan dosyalar taranan sürücüden farklı bir sürücüye yazılır"/>
    <Button x:Name="sl_RcRun" Content="Seçilenleri kurtar" Style="{DynamicResource BtnPrimary}" Margin="0,0,8,6" Visibility="Collapsed" />
    <Button x:Name="sl_RcAll" Content="Hepsini seç" Style="{DynamicResource BtnMini}" Margin="0,0,8,6" Visibility="Collapsed" />
    <Button x:Name="sl_RcNone" Content="Seçimi temizle" Style="{DynamicResource BtnMini}" Margin="0,0,8,6" Visibility="Collapsed" />
    <Button x:Name="sl_ErFile" Content="Dosya seç ve kalıcı sil..." Style="{DynamicResource BtnPrimary}" Margin="0,0,8,6" Visibility="Collapsed" ToolTip="Seçtiğiniz dosyanın üzerine rastgele veri yazar ve siler; geri getirilemez"/>
    <Button x:Name="sl_ErFolder" Content="Klasör seç ve kalıcı sil..." Style="{DynamicResource BtnGhost}" Margin="0,0,8,6" Visibility="Collapsed" ToolTip="Klasörü ve içindeki her şeyi üzerine yazarak siler; geri getirilemez"/>
    <ComboBox x:Name="sl_ErMethod" Width="250" Margin="0,0,8,6" Visibility="Collapsed" Style="{DynamicResource Combo}" ItemTemplate="{DynamicResource ComboText}" ToolTip="Boş alan, ayrılmamış alan, bölüm ve disk silmede kullanılacak yazma yöntemi. Modern sürücülerde tek geçiş yeterlidir"/>
    <ComboBox x:Name="sl_ErVerify" Width="250" Margin="0,0,8,6" Visibility="Collapsed" Style="{DynamicResource Combo}" ItemTemplate="{DynamicResource ComboText}" ToolTip="Yazılanın aygıttan geri okunup karşılaştırılması"/>
    <ComboBox x:Name="sl_ErAfter" Width="270" Margin="0,0,8,6" Visibility="Collapsed" Style="{DynamicResource Combo}" ItemTemplate="{DynamicResource ComboText}" ToolTip="Bölüm ya da disk silindikten sonra yeni bir bölüm açılıp biçimlensin mi"/>
    <Button x:Name="sl_ErRefresh" Content="Yenile" Style="{DynamicResource BtnGhost}" Margin="0,0,8,6" Visibility="Collapsed" ToolTip="Takılı diskleri ve sürücüleri yeniden okur (yeni takılan bir USB bellek için)"/>
    <Button x:Name="sl_PcRefresh" Content="Yenile" Style="{DynamicResource BtnGhost}" Margin="0,0,8,6" Visibility="Collapsed" />
    <Button x:Name="sl_PcCopy" Content="Özeti kopyala" Style="{DynamicResource BtnGhost}" Margin="0,0,8,6" Visibility="Collapsed" />
    <Button x:Name="sl_PrCheck" Content="Denetle" Style="{DynamicResource BtnPrimary}" Margin="0,0,8,6" Visibility="Collapsed" />
    <Button x:Name="sl_PrFix" Content="Eksikleri gider" Style="{DynamicResource BtnGhost}" Margin="0,0,8,6" Visibility="Collapsed" />
  </WrapPanel>
  <DockPanel x:Name="sl_RcFindRow" Grid.Row="3" Margin="0,0,0,8" LastChildFill="True" Visibility="Collapsed">
    <TextBlock Text="Ara" DockPanel.Dock="Left" Style="{DynamicResource TxtDim}" VerticalAlignment="Center" Margin="0,0,8,0"/>
    <TextBox x:Name="sl_RcFind"/>
  </DockPanel>
  <Grid Grid.Row="4">
    <Border x:Name="sl_ListCard" Grid.Column="0" Style="{DynamicResource Card}" Padding="8">
      <ScrollViewer x:Name="sl_Scroll" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
        <StackPanel x:Name="sl_List"/>
      </ScrollViewer>
    </Border>
  </Grid>
  <DockPanel Grid.Row="5" Margin="0,8,0,0" LastChildFill="True">
    <TextBlock x:Name="sl_Foot" Text="" Style="{DynamicResource TxtDim}" VerticalAlignment="Center" TextWrapping="Wrap" Margin="2,0,10,6"/>
  </DockPanel>
</Grid>
'@

'''

RAIL_XAML = r'''                <RadioButton x:Name="Rail_solve" Style="{DynamicResource RailItem}" Tag="solve" ToolTip="Çözüm Merkezi: sorunları bulur ve düzeltir; disk şifreleme, silinen dosya kurtarma, sorun gidericiler">
                  <StackPanel HorizontalAlignment="Center">
                    <ContentControl Style="{DynamicResource Icon}" Tag="{DynamicResource IcoSolve}"/>
                    <TextBlock Text="Çözüm" FontSize="9.5" HorizontalAlignment="Center" Margin="0,3,0,0"/>
                  </StackPanel>
                </RadioButton>
'''

ICON_XAML = '<StreamGeometry x:Key="IcoSolve">M2,12 A10,10 0 1 0 22,12 A10,10 0 1 0 2,12 Z M8,12 A4,4 0 1 0 16,12 A4,4 0 1 0 8,12 Z M4.93,4.93 L9.17,9.17 M14.83,14.83 L19.07,19.07 M19.07,4.93 L14.83,9.17 M9.17,14.83 L4.93,19.07</StreamGeometry>\n'


def apply(b):
    # simge
    b.before('<StreamGeometry x:Key="IcoSpark">', ICON_XAML, xaml=True)
    # sayfa XAML'i
    b.before("$script:Page_company = @'\n", PAGE_XAML, xaml=True)
    # sol dikey cubuk dugmesi
    b.before('                <RadioButton x:Name="Rail_backup" Style="{DynamicResource RailItem}"', RAIL_XAML, xaml=True)
    # sayfa basligi
    b.after("    backup   = 'YEDEK VE KURTARMA'\n", "    solve    = 'ÇÖZÜM MERKEZİ'\n")
    # gezinme gruplari
    b.rep("@{ K = 'ana'; T = 'ANA'; P = @('panel') }", "@{ K = 'ana'; T = 'ANA'; P = @('panel', 'solve') }")
    b.rep("@{ K = 'ana'; T = 'Ana ekran'; Ico = 'IcoHome'; P = @('panel') }", "@{ K = 'ana'; T = 'Ana ekran'; Ico = 'IcoHome'; P = @('panel', 'solve') }")
    # menu adlari, alt basliklar, simge ve arama sozcukleri
    b.rep("$script:PageNames = @{\n", "$script:PageNames = @{\n    solve = 'Çözüm Merkezi'\n")
    b.rep("$script:PageSubs = @{\n", "$script:PageSubs = @{\n    solve = 'Sorunları bulur ve düzeltir; disk, kurtarma, silme'\n")
    b.rep("$script:PageIcons = @{\n", "$script:PageIcons = @{\n    solve = 'IcoSolve'\n")
    b.rep("$script:BoardSearchWords = @{\n", "$script:BoardSearchWords = @{\n    solve = 'cozum coz sorun onar bitlocker sifrele sifreleme kurtar silinen disk hata sorun giderme hazirlik'\n")
    # komut sozcukleri
    b.rep("otomasyon = 'smart'; sikistir = 'compress'\n", "otomasyon = 'smart'; sikistir = 'compress'\n    cozum = 'solve'; coz = 'solve'; sorun = 'solve'; onar = 'solve'; solve = 'solve'; bitlocker = 'solve'; sifrele = 'solve'; kurtar = 'solve'\n")
    # saglik taramasi bitince sayfayi tazele
    b.rep("    $fn = 'Update-SecurityFromHealth'\n    if (Get-Command -Name $fn -CommandType Function -ErrorAction Ignore) { & $fn }\n}",
          "    $fn = 'Update-SecurityFromHealth'\n    if (Get-Command -Name $fn -CommandType Function -ErrorAction Ignore) { & $fn }\n    if (Get-Command -Name 'Update-SolveFromHealth' -CommandType Function -ErrorAction Ignore) { Update-SolveFromHealth }\n}")
    # saglik taramasi: tum suruculeri kapsayan sifreleme/saglik denetimi ve disk hata kayitlari
    b.rep("@{ N = ('Disk ' + [char]0x015F + 'ifreleme'); B = { Chk_BitLocker } }",
          "@{ N = ('Disk ' + [char]0x015F + 'ifreleme ve sa' + [char]0x011F + 'l' + [char]0x0131 + 'k'); B = { Chk_DiskProtect } }, @{ N = ('Disk hatalar' + [char]0x0131); B = { Chk_DiskErrors } }", raw=True)
    # eklenti kaydi: BitLocker islemleri DiskKoruma eklentisinden yuklenir
    b.rep("$script:ExtOf = @{ 'Job_Crypt' = 'Sifreleme'; 'Job_MemTrim' = 'Bellek'; 'Job_SecureDelete' = 'GuvenliSilme' }",
          "$script:ExtOf = @{ 'Job_Crypt' = 'Sifreleme'; 'Job_MemTrim' = 'Bellek'; 'Job_SecureDelete' = 'GuvenliSilme'; 'Job_BlOp' = 'DiskKoruma'; 'Job_RecoverScan' = 'Kurtarma'; 'Job_RecoverParts' = 'Kurtarma'; 'Job_RecoverFiles' = 'Kurtarma'; 'Job_WipeFree' = 'DiskSilme'; 'Job_WipeRaw' = 'DiskSilme'; 'Job_TrimVolume' = 'DiskSilme' }")
    b.rep("foreach ($n in @('Sifreleme', 'Bellek', 'GuvenliSilme', 'WifiAktar')) {",
          "foreach ($n in $script:MmExtNames) {")
    # cekirdek: arka plan isleri
    b.add_core('123_solve_jobs.ps1', title='cozum merkezi: arka plan isleri')
    b.add_core('126_pc_core.ps1', title='cozum merkezi: bilgisayar bilgisi toplama')
    # arayuz: islevler
    anchor = "function Init-Page_backup {\n"
    b.add_ui('122_solve_ui.ps1', anchor, title='cozum merkezi sayfasi')
    for fname, ttl in (('124_solve_recover.ps1', 'cozum merkezi: silinen dosyalar sekmesi'),
                       ('125_solve_erase.ps1', 'cozum merkezi: kalici silme sekmesi'),
                       ('126_solve_pc.ps1', 'cozum merkezi: bilgisayarim sekmesi'),
                       ('127_solve_prep.ps1', 'cozum merkezi: hazirlik sekmesi')):
        b.add_ui(fname, anchor, title=ttl)
