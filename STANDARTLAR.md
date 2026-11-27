<!-- Bu dosya kaynak/tools/gen_standartlar.py ile, uygulamadaki eşleme tablolarından (mods/129_posture.ps1) üretilir. Elle düzenlemeyin. -->

# Standartlar eşlemesi

Multimizer’ın sertleştirme ayarları ve güvenlik bulguları, aşağıdaki çerçevelerin ilgili başlıklarıyla eşlenir.
Bu belge eşlemenin tamamını listeler; uygulamadaki gösterim de aynı tablolardan gelir.

> **Bu eşleme bilgilendirme amaçlıdır.** Sertifika, denetim sonucu ya da uygunluk beyanı değildir.
> Bir ayarın bir başlığa bağlanması, o başlığın karşılandığı anlamına gelmez: başlıkların çoğu politika, süreç, eğitim ve kanıt ister.
> Multimizer yalnızca bu bilgisayarın yapılandırmasına bakar; kurumun yönetim sistemini değerlendirmez.

## Çerçeveler

| Kısaltma | Çerçeve | Başlık biçimi | Kaynak |
|---|---|---|---|
| CIS v8 | CIS Critical Security Controls v8 | Önlem (safeguard) numarası, ör. 4.8 | [cisecurity.org](https://www.cisecurity.org/controls/v8) |
| NIST 800-53 | NIST SP 800-53 Rev. 5 | Kontrol, ör. CM-7 | [csrc.nist.gov](https://csrc.nist.gov/pubs/sp/800/53/r5/upd1/final) |
| ISO 27001 | ISO/IEC 27001:2022 Ek A | Kontrol, ör. A.8.9 | [iso.org](https://www.iso.org/standard/27001) |
| BSI | BSI IT-Grundschutz-Kompendium (Edition 2023) | Modül, ör. SYS.2.2.3 | [bsi.bund.de](https://www.bsi.bund.de/DE/Themen/Unternehmen-und-Organisationen/Standards-und-Zertifizierung/IT-Grundschutz/IT-Grundschutz-Kompendium/it-grundschutz-kompendium_node.html) |
| NIS2 | AB 2022/2555 (NIS2) Direktifi, m.21(2) | Bent, ör. m.21(2)(g) | [eur-lex.europa.eu](https://eur-lex.europa.eu/eli/dir/2022/2555/oj) |
| GDPR | AB 2016/679 (GDPR) Tüzüğü | Madde, ör. m.25 | [eur-lex.europa.eu](https://eur-lex.europa.eu/eli/reg/2016/679/oj) |
| KVKK | 6698 sayılı Kişisel Verilerin Korunması Kanunu | Madde, ör. m.12 | [mevzuat.gov.tr](https://www.mevzuat.gov.tr/mevzuat?MevzuatNo=6698&MevzuatTur=1&MevzuatTertip=5) |

## Uygulamada nerede görünür

- **Çözüm Merkezi > Sorunlar** (uzman kipi): her bulgunun altında “Standartlar: …” satırı olarak ilgili başlıklar yazılır.
- **Sağlık taraması**: “Güvenlik duruşu” denetimi, uygulanmamış sertleştirme ayarlarını tek bir bulguda toplar (kapsam yüzdesi, eksik ayarlar, en zayıf konu). Başka bir bulgunun zaten sunduğu ayarlar yinelenmez. Düzeltme, her zamanki yolla yapılır: önizleme, günlük, geri alma.
- **Envanter ve durum raporu** (Şirket Yönetimi ve `-Cli -Gorev Rapor`): “Güvenlik duruşu ve standart eşlemesi” bölümü, her ayarın durumunu ve başlıklarını listeler.

### Kapsam yüzdesi nasıl hesaplanır

- Yalnızca bu bilgisayarda uygulanabilen ayarlar sayılır (Windows sürümü ve donanım koşulu uymayanlar dışarıda kalır).
- Düzey 1 (Güvenli) ve düzey 2 (Dengeli) ayarlar **temel kapsamı** oluşturur. Düzey 3 (Güçlü) ayarlar isteğe bağlıdır; yüzdeye girmez, yalnızca “isteğe bağlı N ayar daha var” diye anılır. Düzey 4 (zevk ve kullanım tercihi) ayarlar bu belgede yoktur ve ölçülmez.
- Windows’un kendisinin koruduğu, değiştirilemeyen ayarlar yüzdeye katılmaz; ayrıca belirtilir.
- Gizlilik konusu ayrı sayılır: yüzde yalnızca diğer yedi konudan hesaplanır.

## Sayılar

48 ayar ve 65 bulgu eşlenmiştir.

| Çerçeve | Kullanılan başlık | Eşlenen ayar | Eşlenen bulgu |
|---|---:|---:|---:|
| CIS v8 | 29 | 33 | 58 |
| NIST 800-53 | 34 | 30 | 65 |
| ISO 27001 | 24 | 48 | 65 |
| BSI | 13 | 33 | 60 |
| NIS2 | 6 | 33 | 65 |
| GDPR | 3 | 15 | 4 |
| KVKK | 2 | 15 | 4 |

| Konu | Ayar | Bulgu |
|---|---:|---:|
| Kimlik ve hesaplar | 9 | 8 |
| Zararlı yazılımdan koruma | 5 | 16 |
| Ağ ve uzaktan erişim | 9 | 23 |
| Yapılandırma ve şifreleme | 6 | 9 |
| Günlükleme ve izleme | 3 | 2 |
| Güncelleme ve destek | 1 | 4 |
| Veri koruma ve yedek | 0 | 3 |
| Gizlilik | 15 | 0 |

## Konulara göre eşleme

“Ayar” satırları Hızlandır ve Güvenlik sayfalarındaki sertleştirme ayarlarıdır; adın yanında düzeyi yazılıdır (1 Güvenli, 2 Dengeli, 3 Güçlü). “Bulgu” satırları sağlık taramasının kontrol ettiği durumlardır. Bir hücrede “·”, o çerçevede ilgili başlık eşlenmediği anlamına gelir.

### Kimlik ve hesaplar

| Tür | Ad | CIS v8 | NIST 800-53 | ISO 27001 | BSI | NIS2 |
|---|---|---|---|---|---|---|
| Ayar | Parolaların bellekte düz metin tutulmasını engelle (WDigest) (düzey 1) | 4.1 | IA-5, CM-6 | A.8.5, A.8.9 | SYS.2.2.3 | m.21(2)(i) |
| Ayar | Zayıf LM parola özetlerini saklama (düzey 1) | 4.1 | IA-5 | A.5.17, A.8.5 | SYS.2.2.3, ORP.4 | m.21(2)(i) |
| Ayar | Anonim kullanıcı/paylaşım listelemesini kapat (düzey 1) | 3.3 | AC-3, AC-14 | A.5.15, A.8.3 | SYS.2.2.3 | m.21(2)(i) |
| Ayar | Konuk hesabını kapat (düzey 1) | 4.7 | AC-2 | A.5.16, A.5.18 | ORP.4, SYS.2.2.3 | m.21(2)(i) |
| Ayar | Yalnızca NTLMv2 kullan (eski NTLMv1 ve LM reddedilir) (düzey 3) | 4.1 | IA-2, IA-5 | A.8.5, A.8.24 | SYS.2.2.3 | m.21(2)(i) |
| Ayar | LSA korumasını (RunAsPPL) aç (düzey 3) | 4.1, 10.5 | SC-39, SI-16 | A.8.7, A.8.9 | SYS.2.2.3 | m.21(2)(g) |
| Ayar | Hesap kilitleme: 10 hatalı parola denemesinde 15 dakika kilitle (düzey 2) | 4.10 | AC-7 | A.8.5 | ORP.4, SYS.2.2.3 | m.21(2)(i) |
| Ayar | Oturum açma ekranında son kullanıcı adını gösterme (düzey 3) | 4.1 | · | A.8.9 | SYS.2.2.3 | m.21(2)(i) |
| Ayar | Parola alanlarındaki “göster” (göz) düğmesini kaldır (düzey 2) | 4.1 | IA-6 | A.8.5 | SYS.2.2.3 | m.21(2)(i) |
| Bulgu | Yerleşik Yönetici hesabı | 5.4 | AC-6 | A.8.2 | ORP.4 | m.21(2)(i) |
| Bulgu | Yönetici grubunun üye sayısı | 5.4 | AC-6 | A.8.2 | ORP.4 | m.21(2)(i) |
| Bulgu | Konuk hesabı | 4.7 | AC-2 | A.5.16 | ORP.4 | m.21(2)(i) |
| Bulgu | Parola gerektirmeyen etkin hesap | 5.2 | IA-5 | A.5.17 | ORP.4 | m.21(2)(i) |
| Bulgu | Asgari parola uzunluğu ilkesi | 5.2 | IA-5 | A.5.17 | ORP.4 | m.21(2)(i) |
| Bulgu | Hesap kilitleme ilkesi | 4.10 | AC-7 | A.8.5 | ORP.4 | m.21(2)(i) |
| Bulgu | Kayıt defterinde açık yazılı otomatik oturum açma parolası | 5.2 | IA-5 | A.5.17 | SYS.2.2.3 | m.21(2)(i) |
| Bulgu | Kullanıcı Hesabı Denetimi (UAC) | 4.1 | AC-6 | A.8.2 | SYS.2.2.3 | m.21(2)(i) |

### Zararlı yazılımdan koruma

| Tür | Ad | CIS v8 | NIST 800-53 | ISO 27001 | BSI | NIS2 |
|---|---|---|---|---|---|---|
| Ayar | Takılan USB/diskler için otomatik çalıştırmayı kapat (düzey 1) | 10.3 | MP-7 | A.7.10 | SYS.2.2.3 | m.21(2)(g) |
| Ayar | PowerShell 2.0 eski motorunu kaldır (düzey 2) | 4.8 | CM-7 | A.8.9 | SYS.2.2.3 | m.21(2)(g) |
| Ayar | İnternetten gelen Office dosyalarında makroları engelle (düzey 2) | 2.7 | SC-18 | A.8.7 | APP.1.1, OPS.1.1.4 | m.21(2)(g) |
| Ayar | Defender: istenmeyen uygulama (PUA) ve ağ korumasını aç (düzey 1) | 10.1, 10.5, 10.7 | SI-3, SI-16 | A.8.7 | OPS.1.1.4 | m.21(2)(g) |
| Ayar | Windows Betik Sunucusu’nu (.vbs/.js) kapat (düzey 3) | 2.7, 4.8 | CM-7, SC-18 | A.8.7, A.8.9 | OPS.1.1.4, SYS.2.2.3 | m.21(2)(g) |
| Bulgu | Gerçek zamanlı virüs koruması | 10.1 | SI-3 | A.8.7 | OPS.1.1.4 | m.21(2)(g) |
| Bulgu | Virüs tanımlarının güncelliği | 10.2 | SI-3 | A.8.7 | OPS.1.1.4 | m.21(2)(g) |
| Bulgu | Son virüs taramasının tarihi | 10.1 | SI-3 | A.8.7 | OPS.1.1.4 | m.21(2)(g) |
| Bulgu | Üçüncü taraf antivirüs | 10.1 | SI-3 | A.8.7 | OPS.1.1.4 | m.21(2)(g) |
| Bulgu | Bulut tabanlı koruma | 10.7 | SI-3 | A.8.7 | OPS.1.1.4 | m.21(2)(g) |
| Bulgu | İstenmeyen uygulama koruması | 10.1 | SI-3 | A.8.7 | OPS.1.1.4 | m.21(2)(g) |
| Bulgu | Kontrollü klasör erişimi | 10.1, 10.7 | SI-3 | A.8.7 | OPS.1.1.4 | m.21(2)(g) |
| Bulgu | Kurcalama Koruması | 10.1 | SI-3, SI-7 | A.8.7 | OPS.1.1.4 | m.21(2)(g) |
| Bulgu | Defender tarama dışlamaları | 10.1 | SI-3 | A.8.7 | OPS.1.1.4 | m.21(2)(g) |
| Bulgu | SmartScreen | 10.1 | SI-3 | A.8.7, A.8.23 | OPS.1.1.4 | m.21(2)(g) |
| Bulgu | Çıkarılabilir sürücülerde otomatik çalıştırma | 10.3 | MP-7 | A.7.10 | SYS.2.2.3 | m.21(2)(g) |
| Bulgu | PowerShell 2.0 motoru | 4.8 | CM-7 | A.8.9 | SYS.2.2.3 | m.21(2)(g) |
| Bulgu | Şüpheli konumdan başlayan program | 10.7 | SI-3, SI-4 | A.8.7, A.8.16 | OPS.1.1.4, DER.1 | m.21(2)(b) |
| Bulgu | Gizlenmiş ya da internetten komut çalıştıran zamanlanmış görev | 10.7 | SI-3, SI-4 | A.8.7, A.8.16 | OPS.1.1.4, DER.1 | m.21(2)(b) |
| Bulgu | Temp ya da Public klasöründen çalışan zamanlanmış görev | 10.7 | SI-3, SI-4 | A.8.7, A.8.16 | OPS.1.1.4, DER.1 | m.21(2)(b) |
| Bulgu | İmzası bozulmuş hizmet dosyası | · | SI-7 | A.8.7 | OPS.1.1.4 | m.21(2)(g) |

### Ağ ve uzaktan erişim

| Tür | Ad | CIS v8 | NIST 800-53 | ISO 27001 | BSI | NIS2 |
|---|---|---|---|---|---|---|
| Ayar | SMB 1.0 (eski dosya paylaşım protokolü) kapat (düzey 1) | 4.8 | CM-7 | A.8.9, A.8.20 | SYS.2.2.3 | m.21(2)(g) |
| Ayar | Uzak Masaüstü bağlantılarında ağ düzeyinde kimlik doğrulamayı (NLA) zorunlu kıl (düzey 1) | 4.1 | AC-17, IA-2 | A.8.5, A.8.20 | OPS.1.2.5, SYS.2.2.3 | m.21(2)(i) |
| Ayar | Uzaktan Yardım (davetle bağlanma) özelliğini kapat (düzey 2) | 4.8 | AC-17, CM-7 | A.6.7 | OPS.1.2.5 | m.21(2)(g) |
| Ayar | Uzak Masaüstü (RDP) bağlantılarını tamamen kapat (düzey 2) | 4.8 | AC-17, CM-7 | A.6.7, A.8.20 | OPS.1.2.5 | m.21(2)(g) |
| Ayar | LLMNR ad çözümlemesini kapat (düzey 2) | 4.8 | CM-7, SC-7 | A.8.9, A.8.20 | SYS.2.2.3 | m.21(2)(g) |
| Ayar | NetBIOS over TCP/IP kapat (düzey 3) | 4.8 | CM-7, SC-7 | A.8.9, A.8.20 | SYS.2.2.3 | m.21(2)(g) |
| Ayar | WPAD (otomatik vekil sunucu bulma) kapat (düzey 3) | 4.1 | CM-7, SC-7 | A.8.9, A.8.20 | SYS.2.2.3 | m.21(2)(g) |
| Ayar | SMB imzalamayı zorunlu kıl (düzey 3) | 3.10 | SC-8 | A.8.20, A.8.24 | SYS.2.2.3 | m.21(2)(h) |
| Ayar | Açık Wi-Fi ağlarına ve önerilen noktalara otomatik bağlanmayı engelle (düzey 2) | 4.1 | AC-18 | A.8.20 | SYS.2.2.3 | m.21(2)(g) |
| Bulgu | Güvenlik duvarı profilleri | 4.5 | SC-7 | A.8.20 | NET.3.2, SYS.2.2.3 | m.21(2)(g) |
| Bulgu | Genel ağlarda ağ keşfi ve dosya paylaşımı | 4.5 | SC-7, CM-7 | A.8.20 | NET.3.2 | m.21(2)(g) |
| Bulgu | SMB 1.0 | 4.8 | CM-7 | A.8.9, A.8.20 | SYS.2.2.3 | m.21(2)(g) |
| Bulgu | LLMNR ad çözümlemesi | 4.8 | CM-7, SC-7 | A.8.9, A.8.20 | SYS.2.2.3 | m.21(2)(g) |
| Bulgu | NetBIOS (TCP/IP üzerinden) | 4.8 | CM-7, SC-7 | A.8.9, A.8.20 | SYS.2.2.3 | m.21(2)(g) |
| Bulgu | Uzak Masaüstü ve NLA | 4.8 | AC-17 | A.6.7, A.8.20 | OPS.1.2.5 | m.21(2)(g) |
| Bulgu | Uzaktan Yardım (davet) | 4.8 | AC-17, CM-7 | A.6.7 | OPS.1.2.5 | m.21(2)(g) |
| Bulgu | Uzak Kayıt Defteri hizmeti | 4.8 | CM-7, AC-17 | A.8.9, A.8.20 | SYS.2.2.3 | m.21(2)(g) |
| Bulgu | Ağdan erişilebilen dinleyen bağlantı noktaları | 4.8 | CM-7, SC-7 | A.8.20 | NET.3.2 | m.21(2)(g) |
| Bulgu | Ağ paylaşımları | 3.3 | AC-3 | A.5.15, A.8.3 | SYS.2.2.3 | m.21(2)(i) |
| Bulgu | Herkese tam yetkili paylaşım | 3.3 | AC-3, AC-6 | A.5.15, A.8.3 | SYS.2.2.3 | m.21(2)(i) |
| Bulgu | UPnP / SSDP hizmetleri | 4.8 | CM-7, SC-7 | A.8.20 | NET.3.2 | m.21(2)(g) |
| Bulgu | Sistem proxy sunucusu | 4.1 | SC-7 | A.8.20 | SYS.2.2.3 | m.21(2)(g) |
| Bulgu | Otomatik proxy betiği (PAC) | 4.1 | SC-7 | A.8.20 | SYS.2.2.3 | m.21(2)(g) |
| Bulgu | hosts dosyasının güvenlik sitelerini engellemesi | 4.9 | SC-21 | A.8.20, A.8.23 | SYS.2.2.3 | m.21(2)(g) |
| Bulgu | Bilinmeyen DNS sunucusu | 4.9 | SC-21 | A.8.20, A.8.21 | SYS.2.2.3 | m.21(2)(g) |
| Bulgu | Şifresiz Wi-Fi ağlarına kendiliğinden bağlanma | 12.6 | AC-18, SC-8 | A.8.20, A.8.21 | NET.2.1 | m.21(2)(g) |
| Bulgu | Eski Wi-Fi şifreleme kipi | 12.6 | AC-18, SC-8 | A.8.20, A.8.24 | NET.2.1 | m.21(2)(h) |
| Bulgu | Ağ geçidi MAC adresinin değişmesi | · | SC-7, SI-4 | A.8.16, A.8.20 | · | m.21(2)(b) |
| Bulgu | Etkin VPN bağlantısı olmadan kill-switch kuralı | · | SC-7 | A.8.20 | · | m.21(2)(g) |
| Bulgu | Eksik kill-switch kuralları | · | SC-7 | A.8.20 | · | m.21(2)(g) |
| Bulgu | Genel ağda VPN kullanılmaması | · | SC-8 | A.6.7, A.8.20 | · | m.21(2)(g) |
| Bulgu | Şifresiz DNS sorguları | · | SC-8, SC-21 | A.8.20, A.8.21 | · | m.21(2)(g) |

### Yapılandırma ve şifreleme

| Tür | Ad | CIS v8 | NIST 800-53 | ISO 27001 | BSI | NIS2 | GDPR | KVKK |
|---|---|---|---|---|---|---|---|---|
| Ayar | .NET uygulamalarında güçlü şifreleme (TLS 1.2+) kullan (düzey 1) | 3.10 | SC-8, SC-13 | A.8.24 | CON.1 | m.21(2)(h) | · | · |
| Ayar | Eski TLS 1.0 ve 1.1 sürümlerini kapat (düzey 3) | 3.10 | SC-8, SC-13 | A.8.24 | CON.1 | m.21(2)(h) | · | · |
| Ayar | Telnet istemcisi ve TFTP özelliklerini kapat (düzey 2) | 4.8 | CM-7 | A.8.9 | SYS.2.2.3 | m.21(2)(g) | · | · |
| Ayar | Hareketsizlikte oturumu kilitle (15 dakika) (düzey 2) | 4.3 | AC-11 | A.7.7 | SYS.2.1, SYS.2.2.3 | m.21(2)(i) | · | · |
| Ayar | Kilit ekranında kamera ve bildirim içeriğini kapat (düzey 3) | 4.1 | · | A.7.7, A.8.9 | SYS.2.2.3 | m.21(2)(g) | · | · |
| Ayar | Windows Insider / deneme sürümü kayıtlarını engelle (düzey 2) | 4.1 | · | A.8.9 | SYS.2.2.3 | m.21(2)(g) | · | · |
| Bulgu | Dijital imzasız üçüncü taraf hizmet | · | SI-7 | A.8.19 | SYS.2.2.3 | m.21(2)(g) | · | · |
| Bulgu | Tırnaksız hizmet yolu | 4.1 | CM-6 | A.8.9 | SYS.2.2.3 | m.21(2)(g) | · | · |
| Bulgu | Kullanıcı klasöründen çalışan hizmet | 4.1 | CM-6, SI-7 | A.8.9 | SYS.2.2.3 | m.21(2)(g) | · | · |
| Bulgu | BitLocker durumu | 3.6 | SC-28 | A.8.1, A.8.24 | CON.1, SYS.2.2.3 | m.21(2)(h) | m.32 | m.12 |
| Bulgu | Şifrelenmemiş veri sürücüleri | 3.6, 3.11 | SC-28 | A.8.24 | CON.1 | m.21(2)(h) | m.32 | m.12 |
| Bulgu | BitLocker kurtarma anahtarı | 3.6 | SC-12, SC-28 | A.8.24 | CON.1 | m.21(2)(h) | m.32 | m.12 |
| Bulgu | Güvenli Önyükleme (Secure Boot) | 4.1 | SI-7 | A.8.9 | SYS.2.2.3 | m.21(2)(g) | · | · |
| Bulgu | TPM güvenlik çipi | 4.1 | SC-12 | A.8.24 | SYS.2.2.3 | m.21(2)(h) | · | · |
| Bulgu | Windows’un geri çevirdiği ayarlar | 4.1 | CM-6 | A.8.9 | SYS.2.2.3 | m.21(2)(g) | · | · |

### Günlükleme ve izleme

| Tür | Ad | CIS v8 | NIST 800-53 | ISO 27001 | BSI | NIS2 |
|---|---|---|---|---|---|---|
| Ayar | PowerShell betik bloğu günlüğünü aç (düzey 2) | 8.2, 8.5 | AU-2, AU-12 | A.8.15 | OPS.1.1.5 | m.21(2)(b) |
| Ayar | Oturum açma başarı/başarısızlıklarını denetle (düzey 2) | 8.2, 8.5 | AU-2, AU-12 | A.8.15 | OPS.1.1.5 | m.21(2)(b) |
| Ayar | Olay günlüklerini büyüt (Güvenlik 128 MB, Sistem/Uygulama 64 MB) (düzey 2) | 8.3 | AU-4 | A.8.15 | OPS.1.1.5 | m.21(2)(b) |
| Bulgu | Başarısız oturum açma denemeleri | 8.11 | AU-6, SI-4 | A.8.15, A.8.16 | OPS.1.1.5 | m.21(2)(b) |
| Bulgu | Oturum açma olaylarının denetim kaydı | 8.2, 8.5 | AU-2, AU-12 | A.8.15 | OPS.1.1.5 | m.21(2)(b) |

### Güncelleme ve destek

| Tür | Ad | CIS v8 | NIST 800-53 | ISO 27001 | BSI | NIS2 |
|---|---|---|---|---|---|---|
| Ayar | Office gibi diğer Microsoft ürünlerinin güncellemelerini de al (düzey 2) | 7.3, 7.4 | SI-2 | A.8.8 | OPS.1.1.3 | m.21(2)(e) |
| Bulgu | Windows 11 uyumluluğu | 2.2 | SA-22 | A.8.8 | OPS.1.1.3 | m.21(2)(e) |
| Bulgu | Windows sürümünün destek durumu | 2.2, 7.3 | SA-22, SI-2 | A.8.8 | OPS.1.1.3 | m.21(2)(e) |
| Bulgu | Son güvenlik güncellemesinin yaşı | 7.3 | SI-2 | A.8.8 | OPS.1.1.3 | m.21(2)(e) |
| Bulgu | Windows Update hizmetinin durumu | 7.3 | SI-2 | A.8.8 | OPS.1.1.3 | m.21(2)(e) |

### Veri koruma ve yedek

| Tür | Ad | CIS v8 | NIST 800-53 | ISO 27001 | BSI | NIS2 | GDPR | KVKK |
|---|---|---|---|---|---|---|---|---|
| Bulgu | Dosya yedeği | 11.2 | CP-9 | A.8.13 | CON.3 | m.21(2)(c) | m.32 | m.12 |
| Bulgu | Sistem geri yükleme noktası | 11.1 | CP-9, CP-10 | A.8.13 | CON.3 | m.21(2)(c) | · | · |
| Bulgu | Disk arıza öngörüsü (SMART) | 11.2 | CP-9 | A.8.13, A.8.14 | CON.3 | m.21(2)(c) | · | · |

### Gizlilik

| Tür | Ad | ISO 27001 | GDPR | KVKK |
|---|---|---|---|---|
| Ayar | Telemetriyi ve tanılama verisi gönderimini en aza indir (düzey 1) | A.5.34 | m.5(1)(c), m.25 | m.4 |
| Ayar | Reklam kimliği, öneriler ve sessiz uygulama yüklemelerini kapat (düzey 1) | A.5.34 | m.5(1)(c), m.25 | m.4 |
| Ayar | Windows Spotlight ve üçüncü taraf önerilerini kapat (düzey 2) | A.5.34 | m.5(1)(c), m.25 | m.4 |
| Ayar | Etkinlik geçmişini kapat (düzey 1) | A.5.34 | m.5(1)(c), m.25 | m.4 |
| Ayar | Başlat aramasında Bing/web sonuçlarını kapat (düzey 1) | A.5.34 | m.5(1)(c), m.25 | m.4 |
| Ayar | Aramada bulut (Microsoft hesabı / iş hesabı) içeriğini kapat (düzey 2) | A.5.34 | m.5(1)(c), m.25 | m.4 |
| Ayar | Windows Hata Raporlama'yı kapat (düzey 2) | A.5.34 | m.5(1)(c), m.25 | m.4 |
| Ayar | Uygulama uyumluluk envanteri ve Adım Kaydedici toplamasını kapat (düzey 2) | A.5.34 | m.5(1)(c), m.25 | m.4 |
| Ayar | Yazma/el yazısı/konuşma kişiselleştirmesini kapat (düzey 2) | A.5.34 | m.5(1)(c), m.25 | m.4 |
| Ayar | Pano geçmişinin buluta eşitlenmesini kapat (düzey 2) | A.5.34 | m.5(1)(c), m.25 | m.4 |
| Ayar | Konum hizmetlerini tamamen kapat (düzey 3) | A.5.34 | m.5(1)(c), m.25 | m.4 |
| Ayar | Edge: teşhis verisi, öneriler, kenar çubuğu ve alışveriş yardımcısını kapat (düzey 2) | A.5.34 | m.5(1)(c), m.25 | m.4 |
| Ayar | Görev çubuğundaki Haberler ve İlgi Alanları'nı kapat (düzey 1) | A.5.34 | m.5(1)(c), m.25 | m.4 |
| Ayar | Cortana'yı kapat (düzey 1) | A.5.34 | m.5(1)(c), m.25 | m.4 |
| Ayar | Copilot ve Recall (yapay zeka) özelliklerini kapat (düzey 1) | A.5.34 | m.5(1)(c), m.25 | m.4 |

## Başlıktan ayara

Her çerçeve için, kullanılan başlıkların hangi ayar ve bulgularla ilişkilendirildiği. Başlık adları kısa Türkçe özetlerdir; bağlayıcı metin çerçevenin kendi yayınıdır.

<details>
<summary><b>CIS Critical Security Controls v8</b> — 29 başlık</summary>

- **2.2** Desteklenen yazılımın kullanımı — Bulgular: Windows 11 uyumluluğu; Windows sürümünün destek durumu
- **2.7** İzinli betik listesi — Ayarlar: İnternetten gelen Office dosyalarında makroları engelle; Windows Betik Sunucusu’nu (.vbs/.js) kapat
- **3.3** Veri erişim denetim listeleri — Ayarlar: Anonim kullanıcı/paylaşım listelemesini kapat · Bulgular: Ağ paylaşımları; Herkese tam yetkili paylaşım
- **3.6** Kullanıcı cihazlarında veri şifreleme — Bulgular: BitLocker durumu; Şifrelenmemiş veri sürücüleri; BitLocker kurtarma anahtarı
- **3.10** İletilen hassas verinin şifrelenmesi — Ayarlar: .NET uygulamalarında güçlü şifreleme (TLS 1.2+) kullan; SMB imzalamayı zorunlu kıl; Eski TLS 1.0 ve 1.1 sürümlerini kapat
- **3.11** Bekleyen hassas verinin şifrelenmesi — Bulgular: Şifrelenmemiş veri sürücüleri
- **4.1** Güvenli yapılandırma süreci — Ayarlar: Parolaların bellekte düz metin tutulmasını engelle (WDigest); Zayıf LM parola özetlerini saklama; Uzak Masaüstü bağlantılarında ağ düzeyinde kimlik doğrulamayı (NLA) zorunlu kıl; WPAD (otomatik vekil sunucu bulma) kapat; Yalnızca NTLMv2 kullan (eski NTLMv1 ve LM reddedilir); LSA korumasını (RunAsPPL) aç; Oturum açma ekranında son kullanıcı adını gösterme; Parola alanlarındaki “göster” (göz) düğmesini kaldır; Kilit ekranında kamera ve bildirim içeriğini kapat; Windows Insider / deneme sürümü kayıtlarını engelle; Açık Wi-Fi ağlarına ve önerilen noktalara otomatik bağlanmayı engelle · Bulgular: Kullanıcı Hesabı Denetimi (UAC); Tırnaksız hizmet yolu; Kullanıcı klasöründen çalışan hizmet; Sistem proxy sunucusu; Otomatik proxy betiği (PAC); Güvenli Önyükleme (Secure Boot); TPM güvenlik çipi; Windows’un geri çevirdiği ayarlar
- **4.3** Otomatik oturum kilidi — Ayarlar: Hareketsizlikte oturumu kilitle (15 dakika)
- **4.5** Uç cihazlarda güvenlik duvarı — Bulgular: Güvenlik duvarı profilleri; Genel ağlarda ağ keşfi ve dosya paylaşımı
- **4.7** Varsayılan hesapların yönetimi — Ayarlar: Konuk hesabını kapat · Bulgular: Konuk hesabı
- **4.8** Gereksiz hizmetlerin kaldırılması ya da kapatılması — Ayarlar: SMB 1.0 (eski dosya paylaşım protokolü) kapat; Uzaktan Yardım (davetle bağlanma) özelliğini kapat; Uzak Masaüstü (RDP) bağlantılarını tamamen kapat; LLMNR ad çözümlemesini kapat; NetBIOS over TCP/IP kapat; PowerShell 2.0 eski motorunu kaldır; Telnet istemcisi ve TFTP özelliklerini kapat; Windows Betik Sunucusu’nu (.vbs/.js) kapat · Bulgular: PowerShell 2.0 motoru; SMB 1.0; LLMNR ad çözümlemesi; NetBIOS (TCP/IP üzerinden); Uzak Masaüstü ve NLA; Uzaktan Yardım (davet); Uzak Kayıt Defteri hizmeti; Ağdan erişilebilen dinleyen bağlantı noktaları; UPnP / SSDP hizmetleri
- **4.9** Güvenilir DNS sunucuları — Bulgular: hosts dosyasının güvenlik sitelerini engellemesi; Bilinmeyen DNS sunucusu
- **4.10** Taşınabilir cihazlarda otomatik kilitleme — Ayarlar: Hesap kilitleme: 10 hatalı parola denemesinde 15 dakika kilitle · Bulgular: Hesap kilitleme ilkesi
- **5.2** Benzersiz parola kullanımı — Bulgular: Parola gerektirmeyen etkin hesap; Asgari parola uzunluğu ilkesi; Kayıt defterinde açık yazılı otomatik oturum açma parolası
- **5.4** Yönetici yetkilerini ayrı hesaplarla sınırlama — Bulgular: Yerleşik Yönetici hesabı; Yönetici grubunun üye sayısı
- **7.3** İşletim sistemi yamalarının otomatik yönetimi — Ayarlar: Office gibi diğer Microsoft ürünlerinin güncellemelerini de al · Bulgular: Windows sürümünün destek durumu; Son güvenlik güncellemesinin yaşı; Windows Update hizmetinin durumu
- **7.4** Uygulama yamalarının otomatik yönetimi — Ayarlar: Office gibi diğer Microsoft ürünlerinin güncellemelerini de al
- **8.2** Denetim günlüklerinin toplanması — Ayarlar: PowerShell betik bloğu günlüğünü aç; Oturum açma başarı/başarısızlıklarını denetle · Bulgular: Oturum açma olaylarının denetim kaydı
- **8.3** Yeterli günlük depolama alanı — Ayarlar: Olay günlüklerini büyüt (Güvenlik 128 MB, Sistem/Uygulama 64 MB)
- **8.5** Ayrıntılı denetim günlükleri — Ayarlar: PowerShell betik bloğu günlüğünü aç; Oturum açma başarı/başarısızlıklarını denetle · Bulgular: Oturum açma olaylarının denetim kaydı
- **8.11** Denetim günlüklerinin gözden geçirilmesi — Bulgular: Başarısız oturum açma denemeleri
- **10.1** Zararlı yazılım korumasının kurulması — Ayarlar: Defender: istenmeyen uygulama (PUA) ve ağ korumasını aç · Bulgular: Gerçek zamanlı virüs koruması; Son virüs taramasının tarihi; Üçüncü taraf antivirüs; İstenmeyen uygulama koruması; Kontrollü klasör erişimi; Kurcalama Koruması; Defender tarama dışlamaları; SmartScreen
- **10.2** Zararlı yazılım tanımlarının otomatik güncellenmesi — Bulgular: Virüs tanımlarının güncelliği
- **10.3** Çıkarılabilir ortamda otomatik çalıştırmanın kapatılması — Ayarlar: Takılan USB/diskler için otomatik çalıştırmayı kapat · Bulgular: Çıkarılabilir sürücülerde otomatik çalıştırma
- **10.5** İstismar karşıtı özelliklerin açılması — Ayarlar: LSA korumasını (RunAsPPL) aç; Defender: istenmeyen uygulama (PUA) ve ağ korumasını aç
- **10.7** Davranış tabanlı zararlı yazılım koruması — Ayarlar: Defender: istenmeyen uygulama (PUA) ve ağ korumasını aç · Bulgular: Bulut tabanlı koruma; Kontrollü klasör erişimi; Şüpheli konumdan başlayan program; Gizlenmiş ya da internetten komut çalıştıran zamanlanmış görev; Temp ya da Public klasöründen çalışan zamanlanmış görev
- **11.1** Veri kurtarma süreci — Bulgular: Sistem geri yükleme noktası
- **11.2** Otomatik yedekleme — Bulgular: Dosya yedeği; Disk arıza öngörüsü (SMART)
- **12.6** Güvenli ağ yönetimi ve iletişim protokolleri — Bulgular: Şifresiz Wi-Fi ağlarına kendiliğinden bağlanma; Eski Wi-Fi şifreleme kipi

</details>

<details>
<summary><b>NIST SP 800-53 Rev. 5</b> — 34 başlık</summary>

- **AC-2** Hesap yönetimi — Ayarlar: Konuk hesabını kapat · Bulgular: Konuk hesabı
- **AC-3** Erişim zorlaması — Ayarlar: Anonim kullanıcı/paylaşım listelemesini kapat · Bulgular: Ağ paylaşımları; Herkese tam yetkili paylaşım
- **AC-6** En az ayrıcalık — Bulgular: Yerleşik Yönetici hesabı; Yönetici grubunun üye sayısı; Kullanıcı Hesabı Denetimi (UAC); Herkese tam yetkili paylaşım
- **AC-7** Başarısız oturum açma denemeleri — Ayarlar: Hesap kilitleme: 10 hatalı parola denemesinde 15 dakika kilitle · Bulgular: Hesap kilitleme ilkesi
- **AC-11** Cihaz kilidi — Ayarlar: Hareketsizlikte oturumu kilitle (15 dakika)
- **AC-14** Kimlik doğrulamasız izinli eylemler — Ayarlar: Anonim kullanıcı/paylaşım listelemesini kapat
- **AC-17** Uzaktan erişim — Ayarlar: Uzak Masaüstü bağlantılarında ağ düzeyinde kimlik doğrulamayı (NLA) zorunlu kıl; Uzaktan Yardım (davetle bağlanma) özelliğini kapat; Uzak Masaüstü (RDP) bağlantılarını tamamen kapat · Bulgular: Uzak Masaüstü ve NLA; Uzaktan Yardım (davet); Uzak Kayıt Defteri hizmeti
- **AC-18** Kablosuz erişim — Ayarlar: Açık Wi-Fi ağlarına ve önerilen noktalara otomatik bağlanmayı engelle · Bulgular: Şifresiz Wi-Fi ağlarına kendiliğinden bağlanma; Eski Wi-Fi şifreleme kipi
- **AU-2** Olay günlüğü — Ayarlar: PowerShell betik bloğu günlüğünü aç; Oturum açma başarı/başarısızlıklarını denetle · Bulgular: Oturum açma olaylarının denetim kaydı
- **AU-4** Günlük depolama kapasitesi — Ayarlar: Olay günlüklerini büyüt (Güvenlik 128 MB, Sistem/Uygulama 64 MB)
- **AU-6** Günlük kayıtlarının incelenmesi, çözümlenmesi ve raporlanması — Bulgular: Başarısız oturum açma denemeleri
- **AU-12** Günlük kaydı üretimi — Ayarlar: PowerShell betik bloğu günlüğünü aç; Oturum açma başarı/başarısızlıklarını denetle · Bulgular: Oturum açma olaylarının denetim kaydı
- **CM-6** Yapılandırma ayarları — Ayarlar: Parolaların bellekte düz metin tutulmasını engelle (WDigest) · Bulgular: Tırnaksız hizmet yolu; Kullanıcı klasöründen çalışan hizmet; Windows’un geri çevirdiği ayarlar
- **CM-7** En az işlevsellik — Ayarlar: SMB 1.0 (eski dosya paylaşım protokolü) kapat; Uzaktan Yardım (davetle bağlanma) özelliğini kapat; Uzak Masaüstü (RDP) bağlantılarını tamamen kapat; LLMNR ad çözümlemesini kapat; NetBIOS over TCP/IP kapat; WPAD (otomatik vekil sunucu bulma) kapat; PowerShell 2.0 eski motorunu kaldır; Telnet istemcisi ve TFTP özelliklerini kapat; Windows Betik Sunucusu’nu (.vbs/.js) kapat · Bulgular: PowerShell 2.0 motoru; Genel ağlarda ağ keşfi ve dosya paylaşımı; SMB 1.0; LLMNR ad çözümlemesi; NetBIOS (TCP/IP üzerinden); Uzaktan Yardım (davet); Uzak Kayıt Defteri hizmeti; Ağdan erişilebilen dinleyen bağlantı noktaları; UPnP / SSDP hizmetleri
- **CP-9** Sistem yedeği — Bulgular: Dosya yedeği; Sistem geri yükleme noktası; Disk arıza öngörüsü (SMART)
- **CP-10** Sistem kurtarma ve yeniden kurma — Bulgular: Sistem geri yükleme noktası
- **IA-2** Kimlik belirleme ve doğrulama (kurum kullanıcıları) — Ayarlar: Uzak Masaüstü bağlantılarında ağ düzeyinde kimlik doğrulamayı (NLA) zorunlu kıl; Yalnızca NTLMv2 kullan (eski NTLMv1 ve LM reddedilir)
- **IA-5** Kimlik doğrulayıcı yönetimi — Ayarlar: Parolaların bellekte düz metin tutulmasını engelle (WDigest); Zayıf LM parola özetlerini saklama; Yalnızca NTLMv2 kullan (eski NTLMv1 ve LM reddedilir) · Bulgular: Parola gerektirmeyen etkin hesap; Asgari parola uzunluğu ilkesi; Kayıt defterinde açık yazılı otomatik oturum açma parolası
- **IA-6** Doğrulama geri bildirimi — Ayarlar: Parola alanlarındaki “göster” (göz) düğmesini kaldır
- **MP-7** Ortam kullanımı — Ayarlar: Takılan USB/diskler için otomatik çalıştırmayı kapat · Bulgular: Çıkarılabilir sürücülerde otomatik çalıştırma
- **SA-22** Desteklenmeyen sistem bileşenleri — Bulgular: Windows 11 uyumluluğu; Windows sürümünün destek durumu
- **SC-7** Sınır koruması — Ayarlar: LLMNR ad çözümlemesini kapat; NetBIOS over TCP/IP kapat; WPAD (otomatik vekil sunucu bulma) kapat · Bulgular: Güvenlik duvarı profilleri; Genel ağlarda ağ keşfi ve dosya paylaşımı; LLMNR ad çözümlemesi; NetBIOS (TCP/IP üzerinden); Ağdan erişilebilen dinleyen bağlantı noktaları; UPnP / SSDP hizmetleri; Sistem proxy sunucusu; Otomatik proxy betiği (PAC); Ağ geçidi MAC adresinin değişmesi; Etkin VPN bağlantısı olmadan kill-switch kuralı; Eksik kill-switch kuralları
- **SC-8** İletimde gizlilik ve bütünlük — Ayarlar: .NET uygulamalarında güçlü şifreleme (TLS 1.2+) kullan; SMB imzalamayı zorunlu kıl; Eski TLS 1.0 ve 1.1 sürümlerini kapat · Bulgular: Şifresiz Wi-Fi ağlarına kendiliğinden bağlanma; Eski Wi-Fi şifreleme kipi; Genel ağda VPN kullanılmaması; Şifresiz DNS sorguları
- **SC-12** Kriptografik anahtar oluşturma ve yönetimi — Bulgular: BitLocker kurtarma anahtarı; TPM güvenlik çipi
- **SC-13** Kriptografik koruma — Ayarlar: .NET uygulamalarında güçlü şifreleme (TLS 1.2+) kullan; Eski TLS 1.0 ve 1.1 sürümlerini kapat
- **SC-18** Taşınabilir kod — Ayarlar: İnternetten gelen Office dosyalarında makroları engelle; Windows Betik Sunucusu’nu (.vbs/.js) kapat
- **SC-21** Güvenli ad çözümleme hizmeti — Bulgular: hosts dosyasının güvenlik sitelerini engellemesi; Bilinmeyen DNS sunucusu; Şifresiz DNS sorguları
- **SC-28** Bekleyen bilginin korunması — Bulgular: BitLocker durumu; Şifrelenmemiş veri sürücüleri; BitLocker kurtarma anahtarı
- **SC-39** Süreç yalıtımı — Ayarlar: LSA korumasını (RunAsPPL) aç
- **SI-2** Kusur giderme — Ayarlar: Office gibi diğer Microsoft ürünlerinin güncellemelerini de al · Bulgular: Windows sürümünün destek durumu; Son güvenlik güncellemesinin yaşı; Windows Update hizmetinin durumu
- **SI-3** Zararlı kod koruması — Ayarlar: Defender: istenmeyen uygulama (PUA) ve ağ korumasını aç · Bulgular: Gerçek zamanlı virüs koruması; Virüs tanımlarının güncelliği; Son virüs taramasının tarihi; Üçüncü taraf antivirüs; Bulut tabanlı koruma; İstenmeyen uygulama koruması; Kontrollü klasör erişimi; Kurcalama Koruması; Defender tarama dışlamaları; SmartScreen; Şüpheli konumdan başlayan program; Gizlenmiş ya da internetten komut çalıştıran zamanlanmış görev; Temp ya da Public klasöründen çalışan zamanlanmış görev
- **SI-4** Sistem izleme — Bulgular: Başarısız oturum açma denemeleri; Şüpheli konumdan başlayan program; Gizlenmiş ya da internetten komut çalıştıran zamanlanmış görev; Temp ya da Public klasöründen çalışan zamanlanmış görev; Ağ geçidi MAC adresinin değişmesi
- **SI-7** Yazılım, bellenim ve bilgi bütünlüğü — Bulgular: Kurcalama Koruması; İmzası bozulmuş hizmet dosyası; Dijital imzasız üçüncü taraf hizmet; Kullanıcı klasöründen çalışan hizmet; Güvenli Önyükleme (Secure Boot)
- **SI-16** Bellek koruması — Ayarlar: LSA korumasını (RunAsPPL) aç; Defender: istenmeyen uygulama (PUA) ve ağ korumasını aç

</details>

<details>
<summary><b>ISO/IEC 27001:2022 Ek A</b> — 24 başlık</summary>

- **A.5.15** Erişim kontrolü — Ayarlar: Anonim kullanıcı/paylaşım listelemesini kapat · Bulgular: Ağ paylaşımları; Herkese tam yetkili paylaşım
- **A.5.16** Kimlik yönetimi — Ayarlar: Konuk hesabını kapat · Bulgular: Konuk hesabı
- **A.5.17** Kimlik doğrulama bilgisi — Ayarlar: Zayıf LM parola özetlerini saklama · Bulgular: Parola gerektirmeyen etkin hesap; Asgari parola uzunluğu ilkesi; Kayıt defterinde açık yazılı otomatik oturum açma parolası
- **A.5.18** Erişim hakları — Ayarlar: Konuk hesabını kapat
- **A.5.34** Mahremiyet ve kişisel verilerin korunması — Ayarlar: Telemetriyi ve tanılama verisi gönderimini en aza indir; Reklam kimliği, öneriler ve sessiz uygulama yüklemelerini kapat; Windows Spotlight ve üçüncü taraf önerilerini kapat; Etkinlik geçmişini kapat; Başlat aramasında Bing/web sonuçlarını kapat; Aramada bulut (Microsoft hesabı / iş hesabı) içeriğini kapat; Windows Hata Raporlama'yı kapat; Uygulama uyumluluk envanteri ve Adım Kaydedici toplamasını kapat; Yazma/el yazısı/konuşma kişiselleştirmesini kapat; Pano geçmişinin buluta eşitlenmesini kapat; Konum hizmetlerini tamamen kapat; Edge: teşhis verisi, öneriler, kenar çubuğu ve alışveriş yardımcısını kapat; Görev çubuğundaki Haberler ve İlgi Alanları'nı kapat; Cortana'yı kapat; Copilot ve Recall (yapay zeka) özelliklerini kapat
- **A.6.7** Uzaktan çalışma — Ayarlar: Uzaktan Yardım (davetle bağlanma) özelliğini kapat; Uzak Masaüstü (RDP) bağlantılarını tamamen kapat · Bulgular: Uzak Masaüstü ve NLA; Uzaktan Yardım (davet); Genel ağda VPN kullanılmaması
- **A.7.7** Temiz masa ve temiz ekran — Ayarlar: Hareketsizlikte oturumu kilitle (15 dakika); Kilit ekranında kamera ve bildirim içeriğini kapat
- **A.7.10** Depolama ortamı — Ayarlar: Takılan USB/diskler için otomatik çalıştırmayı kapat · Bulgular: Çıkarılabilir sürücülerde otomatik çalıştırma
- **A.8.1** Kullanıcı uç cihazları — Bulgular: BitLocker durumu
- **A.8.2** Ayrıcalıklı erişim hakları — Bulgular: Yerleşik Yönetici hesabı; Yönetici grubunun üye sayısı; Kullanıcı Hesabı Denetimi (UAC)
- **A.8.3** Bilgiye erişimin kısıtlanması — Ayarlar: Anonim kullanıcı/paylaşım listelemesini kapat · Bulgular: Ağ paylaşımları; Herkese tam yetkili paylaşım
- **A.8.5** Güvenli kimlik doğrulama — Ayarlar: Parolaların bellekte düz metin tutulmasını engelle (WDigest); Zayıf LM parola özetlerini saklama; Uzak Masaüstü bağlantılarında ağ düzeyinde kimlik doğrulamayı (NLA) zorunlu kıl; Yalnızca NTLMv2 kullan (eski NTLMv1 ve LM reddedilir); Hesap kilitleme: 10 hatalı parola denemesinde 15 dakika kilitle; Parola alanlarındaki “göster” (göz) düğmesini kaldır · Bulgular: Hesap kilitleme ilkesi
- **A.8.7** Zararlı yazılımdan koruma — Ayarlar: LSA korumasını (RunAsPPL) aç; İnternetten gelen Office dosyalarında makroları engelle; Defender: istenmeyen uygulama (PUA) ve ağ korumasını aç; Windows Betik Sunucusu’nu (.vbs/.js) kapat · Bulgular: Gerçek zamanlı virüs koruması; Virüs tanımlarının güncelliği; Son virüs taramasının tarihi; Üçüncü taraf antivirüs; Bulut tabanlı koruma; İstenmeyen uygulama koruması; Kontrollü klasör erişimi; Kurcalama Koruması; Defender tarama dışlamaları; SmartScreen; Şüpheli konumdan başlayan program; Gizlenmiş ya da internetten komut çalıştıran zamanlanmış görev; Temp ya da Public klasöründen çalışan zamanlanmış görev; İmzası bozulmuş hizmet dosyası
- **A.8.8** Teknik açıklıkların yönetimi — Ayarlar: Office gibi diğer Microsoft ürünlerinin güncellemelerini de al · Bulgular: Windows 11 uyumluluğu; Windows sürümünün destek durumu; Son güvenlik güncellemesinin yaşı; Windows Update hizmetinin durumu
- **A.8.9** Yapılandırma yönetimi — Ayarlar: SMB 1.0 (eski dosya paylaşım protokolü) kapat; Parolaların bellekte düz metin tutulmasını engelle (WDigest); LLMNR ad çözümlemesini kapat; NetBIOS over TCP/IP kapat; WPAD (otomatik vekil sunucu bulma) kapat; LSA korumasını (RunAsPPL) aç; PowerShell 2.0 eski motorunu kaldır; Telnet istemcisi ve TFTP özelliklerini kapat; Windows Betik Sunucusu’nu (.vbs/.js) kapat; Oturum açma ekranında son kullanıcı adını gösterme; Kilit ekranında kamera ve bildirim içeriğini kapat; Windows Insider / deneme sürümü kayıtlarını engelle · Bulgular: PowerShell 2.0 motoru; Tırnaksız hizmet yolu; Kullanıcı klasöründen çalışan hizmet; SMB 1.0; LLMNR ad çözümlemesi; NetBIOS (TCP/IP üzerinden); Uzak Kayıt Defteri hizmeti; Güvenli Önyükleme (Secure Boot); Windows’un geri çevirdiği ayarlar
- **A.8.13** Bilgi yedekleme — Bulgular: Dosya yedeği; Sistem geri yükleme noktası; Disk arıza öngörüsü (SMART)
- **A.8.14** Bilgi işleme olanaklarında yedeklilik — Bulgular: Disk arıza öngörüsü (SMART)
- **A.8.15** Günlükleme — Ayarlar: PowerShell betik bloğu günlüğünü aç; Oturum açma başarı/başarısızlıklarını denetle; Olay günlüklerini büyüt (Güvenlik 128 MB, Sistem/Uygulama 64 MB) · Bulgular: Başarısız oturum açma denemeleri; Oturum açma olaylarının denetim kaydı
- **A.8.16** İzleme faaliyetleri — Bulgular: Başarısız oturum açma denemeleri; Şüpheli konumdan başlayan program; Gizlenmiş ya da internetten komut çalıştıran zamanlanmış görev; Temp ya da Public klasöründen çalışan zamanlanmış görev; Ağ geçidi MAC adresinin değişmesi
- **A.8.19** Operasyonel sistemlere yazılım kurulumu — Bulgular: Dijital imzasız üçüncü taraf hizmet
- **A.8.20** Ağ güvenliği — Ayarlar: SMB 1.0 (eski dosya paylaşım protokolü) kapat; Uzak Masaüstü bağlantılarında ağ düzeyinde kimlik doğrulamayı (NLA) zorunlu kıl; Uzak Masaüstü (RDP) bağlantılarını tamamen kapat; LLMNR ad çözümlemesini kapat; NetBIOS over TCP/IP kapat; WPAD (otomatik vekil sunucu bulma) kapat; SMB imzalamayı zorunlu kıl; Açık Wi-Fi ağlarına ve önerilen noktalara otomatik bağlanmayı engelle · Bulgular: Güvenlik duvarı profilleri; Genel ağlarda ağ keşfi ve dosya paylaşımı; SMB 1.0; LLMNR ad çözümlemesi; NetBIOS (TCP/IP üzerinden); Uzak Masaüstü ve NLA; Uzak Kayıt Defteri hizmeti; Ağdan erişilebilen dinleyen bağlantı noktaları; UPnP / SSDP hizmetleri; Sistem proxy sunucusu; Otomatik proxy betiği (PAC); hosts dosyasının güvenlik sitelerini engellemesi; Bilinmeyen DNS sunucusu; Şifresiz Wi-Fi ağlarına kendiliğinden bağlanma; Eski Wi-Fi şifreleme kipi; Ağ geçidi MAC adresinin değişmesi; Etkin VPN bağlantısı olmadan kill-switch kuralı; Eksik kill-switch kuralları; Genel ağda VPN kullanılmaması; Şifresiz DNS sorguları
- **A.8.21** Ağ hizmetlerinin güvenliği — Bulgular: Bilinmeyen DNS sunucusu; Şifresiz Wi-Fi ağlarına kendiliğinden bağlanma; Şifresiz DNS sorguları
- **A.8.23** Web filtreleme — Bulgular: SmartScreen; hosts dosyasının güvenlik sitelerini engellemesi
- **A.8.24** Kriptografi kullanımı — Ayarlar: .NET uygulamalarında güçlü şifreleme (TLS 1.2+) kullan; SMB imzalamayı zorunlu kıl; Yalnızca NTLMv2 kullan (eski NTLMv1 ve LM reddedilir); Eski TLS 1.0 ve 1.1 sürümlerini kapat · Bulgular: Eski Wi-Fi şifreleme kipi; BitLocker durumu; Şifrelenmemiş veri sürücüleri; BitLocker kurtarma anahtarı; TPM güvenlik çipi

</details>

<details>
<summary><b>BSI IT-Grundschutz-Kompendium (Edition 2023)</b> — 13 başlık</summary>

- **APP.1.1** Ofis ürünleri — Ayarlar: İnternetten gelen Office dosyalarında makroları engelle
- **CON.1** Kriptografi kavramı (Kryptokonzept) — Ayarlar: .NET uygulamalarında güçlü şifreleme (TLS 1.2+) kullan; Eski TLS 1.0 ve 1.1 sürümlerini kapat · Bulgular: BitLocker durumu; Şifrelenmemiş veri sürücüleri; BitLocker kurtarma anahtarı
- **CON.3** Veri yedekleme kavramı (Datensicherungskonzept) — Bulgular: Dosya yedeği; Sistem geri yükleme noktası; Disk arıza öngörüsü (SMART)
- **DER.1** Güvenlik olaylarının saptanması (Detektion von sicherheitsrelevanten Ereignissen) — Bulgular: Şüpheli konumdan başlayan program; Gizlenmiş ya da internetten komut çalıştıran zamanlanmış görev; Temp ya da Public klasöründen çalışan zamanlanmış görev
- **NET.2.1** WLAN işletimi (WLAN-Betrieb) — Bulgular: Şifresiz Wi-Fi ağlarına kendiliğinden bağlanma; Eski Wi-Fi şifreleme kipi
- **NET.3.2** Güvenlik duvarı (Firewall) — Bulgular: Güvenlik duvarı profilleri; Genel ağlarda ağ keşfi ve dosya paylaşımı; Ağdan erişilebilen dinleyen bağlantı noktaları; UPnP / SSDP hizmetleri
- **OPS.1.1.3** Yama ve değişiklik yönetimi (Patch- und Änderungsmanagement) — Ayarlar: Office gibi diğer Microsoft ürünlerinin güncellemelerini de al · Bulgular: Windows 11 uyumluluğu; Windows sürümünün destek durumu; Son güvenlik güncellemesinin yaşı; Windows Update hizmetinin durumu
- **OPS.1.1.4** Zararlı yazılımdan koruma (Schutz vor Schadprogrammen) — Ayarlar: İnternetten gelen Office dosyalarında makroları engelle; Defender: istenmeyen uygulama (PUA) ve ağ korumasını aç; Windows Betik Sunucusu’nu (.vbs/.js) kapat · Bulgular: Gerçek zamanlı virüs koruması; Virüs tanımlarının güncelliği; Son virüs taramasının tarihi; Üçüncü taraf antivirüs; Bulut tabanlı koruma; İstenmeyen uygulama koruması; Kontrollü klasör erişimi; Kurcalama Koruması; Defender tarama dışlamaları; SmartScreen; Şüpheli konumdan başlayan program; Gizlenmiş ya da internetten komut çalıştıran zamanlanmış görev; Temp ya da Public klasöründen çalışan zamanlanmış görev; İmzası bozulmuş hizmet dosyası
- **OPS.1.1.5** Günlükleme (Protokollierung) — Ayarlar: PowerShell betik bloğu günlüğünü aç; Oturum açma başarı/başarısızlıklarını denetle; Olay günlüklerini büyüt (Güvenlik 128 MB, Sistem/Uygulama 64 MB) · Bulgular: Başarısız oturum açma denemeleri; Oturum açma olaylarının denetim kaydı
- **OPS.1.2.5** Uzaktan bakım (Fernwartung) — Ayarlar: Uzak Masaüstü bağlantılarında ağ düzeyinde kimlik doğrulamayı (NLA) zorunlu kıl; Uzaktan Yardım (davetle bağlanma) özelliğini kapat; Uzak Masaüstü (RDP) bağlantılarını tamamen kapat · Bulgular: Uzak Masaüstü ve NLA; Uzaktan Yardım (davet)
- **ORP.4** Kimlik ve yetki yönetimi (Identitäts- und Berechtigungsmanagement) — Ayarlar: Zayıf LM parola özetlerini saklama; Konuk hesabını kapat; Hesap kilitleme: 10 hatalı parola denemesinde 15 dakika kilitle · Bulgular: Yerleşik Yönetici hesabı; Yönetici grubunun üye sayısı; Konuk hesabı; Parola gerektirmeyen etkin hesap; Asgari parola uzunluğu ilkesi; Hesap kilitleme ilkesi
- **SYS.2.1** Genel istemci (Allgemeiner Client) — Ayarlar: Hareketsizlikte oturumu kilitle (15 dakika)
- **SYS.2.2.3** Windows istemcileri (Clients unter Windows) — Ayarlar: SMB 1.0 (eski dosya paylaşım protokolü) kapat; Takılan USB/diskler için otomatik çalıştırmayı kapat; Parolaların bellekte düz metin tutulmasını engelle (WDigest); Zayıf LM parola özetlerini saklama; Anonim kullanıcı/paylaşım listelemesini kapat; Konuk hesabını kapat; Uzak Masaüstü bağlantılarında ağ düzeyinde kimlik doğrulamayı (NLA) zorunlu kıl; LLMNR ad çözümlemesini kapat; NetBIOS over TCP/IP kapat; WPAD (otomatik vekil sunucu bulma) kapat; SMB imzalamayı zorunlu kıl; Yalnızca NTLMv2 kullan (eski NTLMv1 ve LM reddedilir); LSA korumasını (RunAsPPL) aç; PowerShell 2.0 eski motorunu kaldır; Telnet istemcisi ve TFTP özelliklerini kapat; Windows Betik Sunucusu’nu (.vbs/.js) kapat; Hareketsizlikte oturumu kilitle (15 dakika); Hesap kilitleme: 10 hatalı parola denemesinde 15 dakika kilitle; Oturum açma ekranında son kullanıcı adını gösterme; Parola alanlarındaki “göster” (göz) düğmesini kaldır; Kilit ekranında kamera ve bildirim içeriğini kapat; Windows Insider / deneme sürümü kayıtlarını engelle; Açık Wi-Fi ağlarına ve önerilen noktalara otomatik bağlanmayı engelle · Bulgular: Kayıt defterinde açık yazılı otomatik oturum açma parolası; Kullanıcı Hesabı Denetimi (UAC); Çıkarılabilir sürücülerde otomatik çalıştırma; PowerShell 2.0 motoru; Dijital imzasız üçüncü taraf hizmet; Tırnaksız hizmet yolu; Kullanıcı klasöründen çalışan hizmet; Güvenlik duvarı profilleri; SMB 1.0; LLMNR ad çözümlemesi; NetBIOS (TCP/IP üzerinden); Uzak Kayıt Defteri hizmeti; Ağ paylaşımları; Herkese tam yetkili paylaşım; Sistem proxy sunucusu; Otomatik proxy betiği (PAC); hosts dosyasının güvenlik sitelerini engellemesi; Bilinmeyen DNS sunucusu; BitLocker durumu; Güvenli Önyükleme (Secure Boot); TPM güvenlik çipi; Windows’un geri çevirdiği ayarlar

</details>

<details>
<summary><b>AB 2022/2555 (NIS2) Direktifi, m.21(2)</b> — 6 başlık</summary>

- **m.21(2)(b)** Olay yönetimi — Ayarlar: PowerShell betik bloğu günlüğünü aç; Oturum açma başarı/başarısızlıklarını denetle; Olay günlüklerini büyüt (Güvenlik 128 MB, Sistem/Uygulama 64 MB) · Bulgular: Başarısız oturum açma denemeleri; Oturum açma olaylarının denetim kaydı; Şüpheli konumdan başlayan program; Gizlenmiş ya da internetten komut çalıştıran zamanlanmış görev; Temp ya da Public klasöründen çalışan zamanlanmış görev; Ağ geçidi MAC adresinin değişmesi
- **m.21(2)(c)** İş sürekliliği (yedek yönetimi, olağanüstü durum kurtarma) ve kriz yönetimi — Bulgular: Dosya yedeği; Sistem geri yükleme noktası; Disk arıza öngörüsü (SMART)
- **m.21(2)(e)** Ağ ve bilgi sistemlerinin edinilmesi, geliştirilmesi ve bakımında güvenlik (açık yönetimi dahil) — Ayarlar: Office gibi diğer Microsoft ürünlerinin güncellemelerini de al · Bulgular: Windows 11 uyumluluğu; Windows sürümünün destek durumu; Son güvenlik güncellemesinin yaşı; Windows Update hizmetinin durumu
- **m.21(2)(g)** Temel siber hijyen uygulamaları ve eğitim — Ayarlar: SMB 1.0 (eski dosya paylaşım protokolü) kapat; Takılan USB/diskler için otomatik çalıştırmayı kapat; Uzaktan Yardım (davetle bağlanma) özelliğini kapat; Uzak Masaüstü (RDP) bağlantılarını tamamen kapat; LLMNR ad çözümlemesini kapat; NetBIOS over TCP/IP kapat; WPAD (otomatik vekil sunucu bulma) kapat; LSA korumasını (RunAsPPL) aç; PowerShell 2.0 eski motorunu kaldır; İnternetten gelen Office dosyalarında makroları engelle; Telnet istemcisi ve TFTP özelliklerini kapat; Defender: istenmeyen uygulama (PUA) ve ağ korumasını aç; Windows Betik Sunucusu’nu (.vbs/.js) kapat; Kilit ekranında kamera ve bildirim içeriğini kapat; Windows Insider / deneme sürümü kayıtlarını engelle; Açık Wi-Fi ağlarına ve önerilen noktalara otomatik bağlanmayı engelle · Bulgular: Gerçek zamanlı virüs koruması; Virüs tanımlarının güncelliği; Son virüs taramasının tarihi; Üçüncü taraf antivirüs; Bulut tabanlı koruma; İstenmeyen uygulama koruması; Kontrollü klasör erişimi; Kurcalama Koruması; Defender tarama dışlamaları; SmartScreen; Çıkarılabilir sürücülerde otomatik çalıştırma; PowerShell 2.0 motoru; İmzası bozulmuş hizmet dosyası; Dijital imzasız üçüncü taraf hizmet; Tırnaksız hizmet yolu; Kullanıcı klasöründen çalışan hizmet; Güvenlik duvarı profilleri; Genel ağlarda ağ keşfi ve dosya paylaşımı; SMB 1.0; LLMNR ad çözümlemesi; NetBIOS (TCP/IP üzerinden); Uzak Masaüstü ve NLA; Uzaktan Yardım (davet); Uzak Kayıt Defteri hizmeti; Ağdan erişilebilen dinleyen bağlantı noktaları; UPnP / SSDP hizmetleri; Sistem proxy sunucusu; Otomatik proxy betiği (PAC); hosts dosyasının güvenlik sitelerini engellemesi; Bilinmeyen DNS sunucusu; Şifresiz Wi-Fi ağlarına kendiliğinden bağlanma; Etkin VPN bağlantısı olmadan kill-switch kuralı; Eksik kill-switch kuralları; Genel ağda VPN kullanılmaması; Şifresiz DNS sorguları; Güvenli Önyükleme (Secure Boot); Windows’un geri çevirdiği ayarlar
- **m.21(2)(h)** Kriptografi ve gerektiğinde şifreleme politikaları — Ayarlar: .NET uygulamalarında güçlü şifreleme (TLS 1.2+) kullan; SMB imzalamayı zorunlu kıl; Eski TLS 1.0 ve 1.1 sürümlerini kapat · Bulgular: Eski Wi-Fi şifreleme kipi; BitLocker durumu; Şifrelenmemiş veri sürücüleri; BitLocker kurtarma anahtarı; TPM güvenlik çipi
- **m.21(2)(i)** İnsan kaynakları güvenliği, erişim denetimi ve varlık yönetimi — Ayarlar: Parolaların bellekte düz metin tutulmasını engelle (WDigest); Zayıf LM parola özetlerini saklama; Anonim kullanıcı/paylaşım listelemesini kapat; Konuk hesabını kapat; Uzak Masaüstü bağlantılarında ağ düzeyinde kimlik doğrulamayı (NLA) zorunlu kıl; Yalnızca NTLMv2 kullan (eski NTLMv1 ve LM reddedilir); Hareketsizlikte oturumu kilitle (15 dakika); Hesap kilitleme: 10 hatalı parola denemesinde 15 dakika kilitle; Oturum açma ekranında son kullanıcı adını gösterme; Parola alanlarındaki “göster” (göz) düğmesini kaldır · Bulgular: Yerleşik Yönetici hesabı; Yönetici grubunun üye sayısı; Konuk hesabı; Parola gerektirmeyen etkin hesap; Asgari parola uzunluğu ilkesi; Hesap kilitleme ilkesi; Kayıt defterinde açık yazılı otomatik oturum açma parolası; Kullanıcı Hesabı Denetimi (UAC); Ağ paylaşımları; Herkese tam yetkili paylaşım

</details>

<details>
<summary><b>AB 2016/679 (GDPR) Tüzüğü</b> — 3 başlık</summary>

- **m.5(1)(c)** Veri minimizasyonu — Ayarlar: Telemetriyi ve tanılama verisi gönderimini en aza indir; Reklam kimliği, öneriler ve sessiz uygulama yüklemelerini kapat; Windows Spotlight ve üçüncü taraf önerilerini kapat; Etkinlik geçmişini kapat; Başlat aramasında Bing/web sonuçlarını kapat; Aramada bulut (Microsoft hesabı / iş hesabı) içeriğini kapat; Windows Hata Raporlama'yı kapat; Uygulama uyumluluk envanteri ve Adım Kaydedici toplamasını kapat; Yazma/el yazısı/konuşma kişiselleştirmesini kapat; Pano geçmişinin buluta eşitlenmesini kapat; Konum hizmetlerini tamamen kapat; Edge: teşhis verisi, öneriler, kenar çubuğu ve alışveriş yardımcısını kapat; Görev çubuğundaki Haberler ve İlgi Alanları'nı kapat; Cortana'yı kapat; Copilot ve Recall (yapay zeka) özelliklerini kapat
- **m.25** Tasarım ve varsayılan olarak veri koruma — Ayarlar: Telemetriyi ve tanılama verisi gönderimini en aza indir; Reklam kimliği, öneriler ve sessiz uygulama yüklemelerini kapat; Windows Spotlight ve üçüncü taraf önerilerini kapat; Etkinlik geçmişini kapat; Başlat aramasında Bing/web sonuçlarını kapat; Aramada bulut (Microsoft hesabı / iş hesabı) içeriğini kapat; Windows Hata Raporlama'yı kapat; Uygulama uyumluluk envanteri ve Adım Kaydedici toplamasını kapat; Yazma/el yazısı/konuşma kişiselleştirmesini kapat; Pano geçmişinin buluta eşitlenmesini kapat; Konum hizmetlerini tamamen kapat; Edge: teşhis verisi, öneriler, kenar çubuğu ve alışveriş yardımcısını kapat; Görev çubuğundaki Haberler ve İlgi Alanları'nı kapat; Cortana'yı kapat; Copilot ve Recall (yapay zeka) özelliklerini kapat
- **m.32** İşlemenin güvenliği — Bulgular: BitLocker durumu; Şifrelenmemiş veri sürücüleri; BitLocker kurtarma anahtarı; Dosya yedeği

</details>

<details>
<summary><b>6698 sayılı Kişisel Verilerin Korunması Kanunu</b> — 2 başlık</summary>

- **m.4** Genel ilkeler (işlenen verinin amaçla bağlantılı, sınırlı ve ölçülü olması) — Ayarlar: Telemetriyi ve tanılama verisi gönderimini en aza indir; Reklam kimliği, öneriler ve sessiz uygulama yüklemelerini kapat; Windows Spotlight ve üçüncü taraf önerilerini kapat; Etkinlik geçmişini kapat; Başlat aramasında Bing/web sonuçlarını kapat; Aramada bulut (Microsoft hesabı / iş hesabı) içeriğini kapat; Windows Hata Raporlama'yı kapat; Uygulama uyumluluk envanteri ve Adım Kaydedici toplamasını kapat; Yazma/el yazısı/konuşma kişiselleştirmesini kapat; Pano geçmişinin buluta eşitlenmesini kapat; Konum hizmetlerini tamamen kapat; Edge: teşhis verisi, öneriler, kenar çubuğu ve alışveriş yardımcısını kapat; Görev çubuğundaki Haberler ve İlgi Alanları'nı kapat; Cortana'yı kapat; Copilot ve Recall (yapay zeka) özelliklerini kapat
- **m.12** Veri güvenliğine ilişkin yükümlülükler — Bulgular: BitLocker durumu; Şifrelenmemiş veri sürücüleri; BitLocker kurtarma anahtarı; Dosya yedeği

</details>

## Sınırlar

- Eşleme **ayar düzeyindedir**. Kurumun politikaları, eğitimi, olay yönetimi süreci, tedarik zinciri ya da fiziksel güvenliği bu belgenin ve uygulamanın kapsamı dışındadır.
- Bir başlığın yanında ayar görünmesi, o başlığın karşılandığını göstermez; yalnızca ayarın o önleme katkı verdiğini söyler. Tersine, bir başlığın yanında ayar bulunmaması da başlığın gereksiz olduğu anlamına gelmez.
- NIS2 yalnızca kapsamdaki “temel” ve “önemli” kuruluşlar için bağlayıcıdır; KVKK ve GDPR kişisel veri işleyenleri ilgilendirir. Bu başlıklar, kuruluşunuzun kapsamda olup olmadığını belirlemez.
- Başlık numaraları belirtilen sürümlere göredir (CIS v8, NIST 800-53 Rev. 5, ISO/IEC 27001:2022, BSI Edition 2023). Çerçeveler güncellenirse tablolar `kaynak/mods/129_posture.ps1` içinde güncellenir ve bu belge yeniden üretilir.
- Uygulama bu eşleme nedeniyle hiçbir ayarı kendiliğinden uygulamaz. Her düzeltme önizlenir, günlüğe yazılır ve geri alınabilir.

## Yeniden üretme

```
python3 kaynak/tools/gen_standartlar.py          # bu dosyayı yazar
python3 kaynak/tools/gen_standartlar.py --check  # dosya güncel mi?
```

Yeni bir ayar ya da bulgu eşlerken önce `PostureTweakRows` / `PostureFindRows` tablosuna satır ekleyin; ardından bu betikteki `REF_TITLES` ve `FIND_NAMES` sözlüklerini tamamlayın. Eksik ya da artık bir ad varsa betik durur.
