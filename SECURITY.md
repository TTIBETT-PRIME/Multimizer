# Güvenlik

## Güvenlik açığı bildirimi

Bir güvenlik açığı bulduysanız lütfen herkese açık bir sorun (issue) açmayın. GitHub’da bu deponun **Security > Report a vulnerability**
bölümünden özel olarak bildirin. Bildirimde sürümü, etkilenen işlevi ve yeniden üretme adımlarını yazın.

## Kapsam

Özellikle şunlar önemlidir:

- Windows Defender, Güvenlik Duvarı, UAC, Microsoft Store ya da Windows Update’i kapatabilen herhangi bir yol (koruma listesini aşma dahil).
- Kullanıcı onayı olmadan sistemde değişiklik yapan ya da geri alınamayan değişiklik üreten akışlar.
- Parolanın, BitLocker kurtarma anahtarının ya da VPN özel anahtarının günlüğe, dosyaya, komut satırına veya ağa sızması.
- Yetkisiz bir kullanıcının yönetici yetkisiyle çalışan kısımları tetiklemesi (ör. betik, `veri/` ya da `Eklenti/` klasörüne yazma izinleri; yan dosyalar yüklenmeden önce SHA-256 özetiyle doğrulanır, bu doğrulamayı aşan yollar önemlidir).
- Ağ özelliklerinin kullanıcının kendi ağı dışına çıkması ya da başka cihazlara müdahale etmesi.
- Silme koruma kurallarını aşıp Windows'un çalıştığı diske, çevrimdışı ya da salt okunur diske, depolama havuzu üyesine ya da kullanıcının onaylamadığı bir hedefe yazan yollar (`Test-WipeDiskAllowed`, `Test-WipePartAllowed`, `Test-SecureDeleteAllowed`, hedef adının elle yazdırılması ve işlem anında yeniden doğrulama).
- Kurtarma motorunun kaynağa yazması ya da kurtarılan veriyi var olan bir dosyanın üzerine yazması.
- Güncelleme denetiminin kullanıcı başlatmadan çalışması, HTTPS dışına inmesi, boyut sınırlarını aşması, özeti tutmayan dosyayı bırakması ya da indirilen dosyayı açıp çalıştırması.
- Hazırlık ve Dış araçlar'daki izin listelerinin dışında bir paketin kurulabilmesi.

## Tasarım ilkeleri

Uygulama telemetri göndermez, uzaktan kod indirip çalıştırmaz, kendi disk şifreleme ya da tünel kodu içermez
(disk şifreleme için Windows'un BitLocker'ı, şifreli yedek için restic, VPN için resmî WireGuard istemcisi / Windows IKEv2 kullanılır) ve yalnızca yönetici izniyle çalışır.
Silme motorunun AES-256-CTR akışı yalnızca rastgele veri üretir; kullanıcı verisini şifrelemez.
Ayrıntılar için [README.md](README.md), [MIMARI.md](MIMARI.md) ve [CONTRIBUTING.md](CONTRIBUTING.md).

## İndirdiğiniz paketi doğrulama

Sürümler GitHub Actions ile depodaki kaynak koddan üretilir; `Multimizer.ps1`, `Eklenti/` ve `veri/` dosyalarının kaynaktan yeniden üretilen kopyayla bayt bayt aynı olduğu her gönderimde (`ci.yml`) ve her sürümde (`release.yml`) denetlenir.

- **Özet:** sürüm sayfasındaki `SHA256SUMS.txt` ile karşılaştırın: `Get-FileHash .\Multimizer-<sürüm>.zip -Algorithm SHA256`
- **İmzalı kaynak kanıtı:** paket ve özet listesi için GitHub Artifact Attestations (Sigstore) kanıtı üretilir. GitHub CLI ile: `gh attestation verify Multimizer-<sürüm>.zip --repo TTIBETT-PRIME/Multimizer`. Doğrulama, paketin bu deponun hangi işlemesinden ve hangi iş akışıyla üretildiğini gösterir.
- Bu kanıt, Windows’un “bilinmeyen yayıncı” uyarısını kaldıran kod imzası (Authenticode) değildir; kod imzalama yol haritasındadır.
- Paketi yalnızca bu deponun sürüm sayfasından indirin.

## Bilinen güvenlik sınırları

- **Dosya özetleri (SHA-256) bütünlüğü gösterir, yayıncı kimliğini kanıtlamaz.** Yan dosyalar (`Eklenti/`, `veri/`) betikteki özetlerle doğrulanır; ancak betiği ve özetleri birlikte değiştirebilen biri bu denetimi aşar. Güncelleme denetiminin SHA-256 doğrulaması da aynı kapsamdadır. Kod imzalama sertifikası yol haritasındadır.
- **Silme ve kurtarma SSD ve flash belleklerde sınırlıdır.** Üzerine yazma denetleyicinin ayırdığı gizli hücrelere ulaşamaz; kesin çözüm baştan şifrelemektir. Silme yöntemleri hiçbir silme standardına uygunluk iddia etmez.
- **Güvenlik duruşu eşlemesi** (CIS, NIST, ISO 27001, BSI, NIS2, GDPR, KVKK) bilgilendirme amaçlıdır; sertifika ya da uygunluk beyanı değildir.
- Kurtarma ve silme motorlarının yazan yolları gerçek USB bellek ve fiziksel disklerde henüz sahada sınanmamıştır; bkz. [CHANGELOG.md](CHANGELOG.md).

## Desteklenen sürümler

Yalnızca en son sürüm düzeltme alır.
