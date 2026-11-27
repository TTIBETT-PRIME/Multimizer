# ==================================================================
#  KATALOG EKLERİ (9.0.0): yapay zekâ özellikleri için ilkeler ve isteğe bağlı Windows özellikleri
#  Hepsi ayrıntılı önizlenir, günlüğe yazılır ve Geçmiş sayfasından geri alınır. Güvenlik kapısına takılan hiçbir işlem yoktur.
# ==================================================================

# ============================ GİZLİLİK: yapay zekâ özellikleri ============================
Add-RegTweak -Id 'AiClickToDo' -Cat 'Gizlilik' -Level 3 -OS '11' -Title 'Click to Do (ekrandaki içeriğe yapay zekâ eylemleri) özelliğini kapat' `
    -Desc 'Win + tıklama ile açılan “Click to Do” ekrandaki metin ve görüntüyü çözümleyip yapay zekâ eylemleri önerir. İlkeyle kapatılınca ekran içeriği bu amaçla işlenmez; Win + Q ve Win + tıklama kısayolu da çalışmaz.' `
    -Reg @('HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsAI|DisableClickToDo|DWord|1', 'HKCU\Software\Microsoft\Windows\Shell\ClickToDo|DisableClickToDo|DWord|1')
Add-RegTweak -Id 'AiPaint' -Cat 'Gizlilik' -Level 3 -OS '11' -Title 'Paint’teki yapay zekâ özelliklerini kapat (Cocreator, Üretken Dolgu, Görüntü Oluşturucu)' `
    -Desc 'Paint’in görüntü üretme ve düzenleme için içeriği Microsoft’un yapay zekâ hizmetine göndermesini engeller. Paint’in diğer özellikleri değişmez.' `
    -Reg @('HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint|DisableCocreator|DWord|1', 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint|DisableGenerativeFill|DWord|1',
           'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint|DisableImageCreator|DWord|1')
Add-RegTweak -Id 'AiNotepad' -Cat 'Gizlilik' -Level 3 -OS '11' -Title 'Not Defteri’ndeki yapay zekâ özelliklerini kapat (Yeniden yaz, Özetle, Yaz)' `
    -Desc 'Not Defteri’nin yazdığınız metni yapay zekâ hizmetine göndererek yeniden yazma, özetleme ya da metin üretme özelliklerini ilkeyle kapatır. Not Defteri normal çalışmaya devam eder.' `
    -Reg @('HKLM\SOFTWARE\Policies\WindowsNotepad|DisableAIFeatures|DWord|1')

# ============================ WINDOWS ÖZELLİKLERİ: isteğe bağlı bileşenleri aç ============================
Add-RegTweak -Id 'FeatNetFx3' -Cat 'Ozellik' -Level 4 -Title '.NET Framework 3.5’i etkinleştir (eski programlar için)' `
    -Desc 'Eski programların ve oyunların istediği .NET Framework 2.0 – 3.5 çalışma zamanını açar. Gerekli dosyaları Windows Update’ten indirir, bu yüzden internet bağlantısı ister.' `
    -Ops @((FeatOp 'NetFx3' 'Enabled'))
Add-RegTweak -Id 'FeatDirectPlay' -Cat 'Ozellik' -Level 4 -Title 'DirectPlay’i etkinleştir (eski oyunlar için)' `
    -Desc 'Çok eski oyunların çok oyunculu ve ağ bileşeni olarak kullandığı DirectPlay’i açar. Yeni oyunlar buna ihtiyaç duymaz.' `
    -Ops @((FeatOp 'DirectPlay' 'Enabled'))
Add-RegTweak -Id 'FeatSandbox' -Cat 'Ozellik' -Level 4 -Title 'Windows Sandbox’ı etkinleştir (şüpheli dosyaları yalıtılmış ortamda aç)' -Reboot $true `
    -Desc 'Tek kullanımlık, yalıtılmış bir Windows ortamı açar; şüpheli bir programı kapatınca her şey silinir. Windows Pro/Enterprise sürümü, sanallaştırma desteği ve yaklaşık 4 GB bellek ister.' `
    -Ops @((FeatOp 'Containers-DisposableClientVM' 'Enabled'))
Add-RegTweak -Id 'FeatWsl' -Cat 'Ozellik' -Level 4 -Title 'Linux için Windows Alt Sistemi’ni (WSL) etkinleştir' -Reboot $true `
    -Desc 'Windows içinde Linux komut satırı ve geliştirme araçlarını çalıştırmak için gereken WSL ile sanal makine platformunu açar. Dağıtımı sonradan “wsl --install” ile seçersiniz.' `
    -Ops @((FeatOp 'Microsoft-Windows-Subsystem-Linux' 'Enabled'), (FeatOp 'VirtualMachinePlatform' 'Enabled'))
