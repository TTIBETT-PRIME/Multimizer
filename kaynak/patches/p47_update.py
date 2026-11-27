# -*- coding: utf-8 -*-
"""Guncelleme denetimi (istege bagli, yalnizca kullanici baslatinca) ve dosya butunlugu denetimi:
ayar varsayilani, Ayarlar > Uygulama karti, cekirdek ve arayuz modulleri, Duman turu adimi."""


def apply(b):
    # ---- ayar varsayilani: bos adres = ozellik kullanilmaz
    b.rep("        PrepSeen     = ''\n    }\n}\n", "        PrepSeen     = ''\n        UpdateUrl    = ''\n    }\n}\n", raw=True, name='p47 UpdateUrl')

    # ---- XAML: Ayarlar > Uygulama kartina guncelleme denetimi ve dosya butunlugu bolumleri
    b.after('        <Button x:Name="st_OpenData" Content="Veri klasörünü aç" Style="{DynamicResource BtnGhost}" Margin="0,0,8,6"/>\n      </WrapPanel>\n',
            '      <Border Height="1" Background="{DynamicResource BrLine}" Margin="0,12,0,12"/>\n'
            '      <TextBlock Text="Güncelleme denetimi" Style="{DynamicResource TxtBody}" FontWeight="SemiBold"/>\n'
            '      <TextBlock Text="Uygulama kendiliğinden hiçbir adrese bağlanmaz. Aşağıya bir HTTPS adresi (GitHub deposunun adresi ya da kendi bildirim dosyanız) yazın; “Güncellemeleri denetle”ye bastığınızda yalnızca sürüm bilgisi okunur. İndirme ayrıca onayınızı ister ve SHA-256 özetiyle doğrulanır; hiçbir şey kendiliğinden kurulmaz." Style="{DynamicResource TxtDim}" TextWrapping="Wrap" Margin="0,4,0,0"/>\n'
            '      <TextBox x:Name="st_UpdUrl" MaxLength="600" Margin="0,8,0,0"/>\n'
            '      <WrapPanel Margin="0,8,0,0">\n'
            '        <Button x:Name="st_UpdCheck" Content="Güncellemeleri denetle" Style="{DynamicResource BtnGhost}" Margin="0,0,8,6"/>\n'
            '        <Button x:Name="st_UpdGet" Content="İndir" Style="{DynamicResource BtnPrimary}" Margin="0,0,8,6" Visibility="Collapsed"/>\n'
            '        <Button x:Name="st_UpdPage" Content="Sürüm sayfası" Style="{DynamicResource BtnGhost}" Margin="0,0,8,6" Visibility="Collapsed"/>\n'
            '        <Button x:Name="st_UpdFolder" Content="İndirilenler klasörü" Style="{DynamicResource BtnGhost}" Margin="0,0,8,6" Visibility="Collapsed"/>\n'
            '      </WrapPanel>\n'
            '      <TextBlock x:Name="st_UpdState" Text="" Style="{DynamicResource TxtDim}" TextWrapping="Wrap" Margin="0,2,0,0"/>\n'
            '      <Border Height="1" Background="{DynamicResource BrLine}" Margin="0,12,0,12"/>\n'
            '      <TextBlock Text="Dosya bütünlüğü" Style="{DynamicResource TxtBody}" FontWeight="SemiBold"/>\n'
            '      <TextBlock Text="Eklenti ve veri dosyalarının, bu sürümle birlikte derlenen SHA-256 özetleriyle tutup tutmadığına bakar. Yalnızca okur; hiçbir dosyayı değiştirmez." Style="{DynamicResource TxtDim}" TextWrapping="Wrap" Margin="0,4,0,0"/>\n'
            '      <Button x:Name="st_IntCheck" Content="Dosya bütünlüğünü denetle" Style="{DynamicResource BtnGhost}" HorizontalAlignment="Left" Margin="0,8,0,6"/>\n'
            '      <TextBlock x:Name="st_IntState" Text="" Style="{DynamicResource TxtDim}" TextWrapping="Wrap" Margin="0,2,0,0"/>\n',
            xaml=True)

    # ---- Ayarlar sayfasi: yukleme ve baglama
    b.rep("    Render-StNet\n    $ui.st_UseCaseText.Text", "    Render-StNet\n    Load-StUpdate\n    $ui.st_UseCaseText.Text", raw=True, name='p47 Load-StExtra')
    b.rep("    Init-StExtra\n}\n\nfunction Show-Page_settings {", "    Init-StUpdate\n    Init-StExtra\n}\n\nfunction Show-Page_settings {", raw=True, name='p47 Init-Page_settings')

    # ---- moduller: cekirdek (arka plan isleri) ve arayuz
    b.add_core('134_update_core.ps1', title='guncelleme denetimi ve dosya butunlugu: cekirdek')
    b.add_ui('135_update_ui.ps1', "function Init-Page_backup {\n", title='guncelleme denetimi: Ayarlar karti')

    # ---- Duman turu: dosya butunlugu denetimi (yalnizca okur); guncelleme denetimi ag kullandigi icin turda basilmaz
    b.rep("'sl_Scan', 'sl_DiskRefresh', 'sl_ErRefresh', 'sl_PcRefresh', 'sl_PrCheck'\n)",
          "'sl_Scan', 'sl_DiskRefresh', 'sl_ErRefresh', 'sl_PcRefresh', 'sl_PrCheck', 'st_IntCheck'\n)", raw=True, name='p47 duman guvenli dugme')
    b.rep("        @('solve', 'sl_Tab_pc', 'sl_PcRefresh'), @('solve', 'sl_Tab_prep', 'sl_PrCheck')\n    )",
          "        @('solve', 'sl_Tab_pc', 'sl_PcRefresh'), @('solve', 'sl_Tab_prep', 'sl_PrCheck'),\n        @('settings', '', 'st_IntCheck')\n    )", raw=True, name='p47 duman eylem')
