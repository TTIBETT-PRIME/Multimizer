# Multimizer

Speeds up and repairs Windows without turning off its security.

Windows'u güvenliğini kapatmadan hızlandırır ve onarır.

Windows 10 ve 11 için tek dosyalık hızlandırma, bakım, güvenlik, ağ koruma, sorun giderme, veri kurtarma, kalıcı silme ve şirket yönetimi aracı.
PowerShell 5.1 + WPF · kurulum gerektirmez · telemetri yok · her değişiklik önce gösterilir, kaydedilir ve geri alınır.

> *English: Multimizer is a single-file Windows 10/11 optimization, maintenance, security and network-protection tool
> (Windows PowerShell 5.1 + WPF) that also finds and fixes problems, recovers deleted files and securely erases data.
> It previews, journals and can undo every change, never disables Defender, the firewall,
> UAC or Windows Update, and sends no telemetry. The interface comes in 12 languages (Turkish is the source language; coverage per
> language is listed under "Dil desteği" below; translations have not yet been reviewed by native speakers, and anything untranslated falls back to English).*

## Neden

Windows’u “hızlandırdığını” söyleyen araçların çoğu ya işe yaramayan ayarlar kurcalar ya da güvenliği kapatır.
Multimizer tersini yapar: bilgisayarın donanımına bakar ve **güçlü bir bilgisayarda gereksiz bir şeyi kapatmaz**;
zayıf bir bilgisayarda ise gerçekten fark yaratan ayarları önerir. Her ayarın ne yaptığı ve ne kaybettireceği yazılıdır.

## Sayfalar

| Sayfa | İçindekiler |
|---|---|
| **Durum Panosu** | Canlı işlemci / bellek / disk / ağ, sağlık puanı, hızlı işlemler, işlem günlüğü. İlk açılışta “Bu bilgisayarı nasıl kullanıyorsun?” sorusu (ev, oyuncu, gizlilik, bilgisayarcı, şirket). |
| **Çözüm Merkezi** | Bulur **ve düzeltir**. *Sorunlar* (sağlık taraması ve tek tıkla düzeltme), *Diskler* (BitLocker ile şifreleme, sağlık, onarım), *Silinen dosyalar* (sürücü, USB bellek, SD kart, disk imajı), *Kalıcı silme* (dosya, boş alan, bölüm, tüm disk), *Sorun gidericiler* (9 belirti), *Bu bilgisayar* (donanımı tanır; kullanıcı ve uzman görünümü), *Hazırlık* (gerekli bileşenleri denetler, eksikleri onayla kurar). Aşağıdaki bölüme bakın. |
| **Optimizasyon** | 190’dan fazla ayar: gizlilik ve telemetri, arayüz ve kişiselleştirme, sistem, Windows özellikleri ve bileşenleri, oyun, ağ, temizlik, Edge ve Office; uygulama izinleri (kamera, mikrofon, kişiler...). Donanıma göre otomatik öneri; Güvenli / Dengeli / Güçlü düzeyler; zevk ve kullanım tercihleri yalnızca elle seçilir. Windows’un geri çevirdiği ayarları yakalayan sapma denetimi ve isteğe bağlı ayar bekçisi. |
| **Hizmet Yöneticisi** | 100’den fazla hizmet için bilgi tabanı: ne işe yarar, kapatırsanız ne olur. Windows’un omurgası olan hizmetler kilitlidir. |
| **Uygulamalar** | Mağaza uygulamaları (gereksiz olanlar), başlangıç programları, yüklü programlar, ücretsiz ve açık kaynak araç cephaneliği (winget). |
| **Temizlik ve Disk** | Akıllı temizlik: geçici dosyalar, tarayıcı ve uygulama önbellekleri (Discord, Slack, Teams, VS Code, Steam, Epic, Adobe), gölgelendirici (shader) önbelleği, küçük resim önbelleği, kurulum günlükleri, Windows Update ve Teslim İyileştirme önbelleği; disk analizi (klasör boyut haritası), **en büyük 100 dosya**, **kopya dosya bulucu**; **Sıkıştır**: CompactOS ve klasör sıkıştırma (önerilen oyun / program klasörleri, tahmini ve gerçek kazanç, geri alınabilir). Silme hep onaylıdır. |
| **Güç** | Modern Bekleme (S0) kullanan dizüstülerde Windows yalnızca Dengeli planını sunduğundan performans düzeyi **güç kipiyle** seçilir (En iyi performans / Dengeli / En iyi güç verimliliği; hem fişte hem pilde uygulanır, yazıldıktan sonra Windows’tan geri okunarak doğrulanır, önceki değerler Geçmiş’e yazılır ve geri alınır); diğer bilgisayarlarda Dengeli / Güç tasarrufu / Yüksek / Nihai performans planları; geçmeden önce **neyin değişeceğini gösteren önizleme**; **özel plan oluşturucu** (işlemci en düşük / en yüksek durumu, turbo, soğutma, çekirdek park, ekran, uyku, hazırda bekletme, disk, USB, PCIe, kablosuz, kapak) ve hazır şablonlar (Oyun, Sessiz ve serin, Pil ömrü, Ofis); canlı güç durumu ve pil aşınması; pil ve enerji verimliliği raporu; uyku durumları. |
| **Oyun** | Canlı işlemci / bellek / ekran kartı / disk / sıcaklık göstergeleri; yüklü oyunlar (Steam, Epic, GOG, elle eklenenler) ve çalışan oyunun algılanması; oyun başına **güçlü GPU’da çalıştır** ve **tam ekran iyileştirmesini kapat**; tek tıkla **oyun kipi** (nihai performans planı, odak kipi, oyun önceliği) ve “Normale dön”; oyun ayarları (donanım hızlandırmalı GPU zamanlaması, Game Bar / DVR, Nagle, ağ kısıtlaması, pencereli oyun iyileştirmesi...). |
| **Akıllı bakım** | Yerel, kural tabanlı bakım (bulut yok, veri gitmez, hepsi kapalı gelir): **performans artırıcı** (yükü oluşturan arka plan işlemini bulur, isterseniz önceliğini düşürür), **ısı yönetimi** (aşırı ısınmada işlemciyi geçici sınırlar, soğuyunca geri alır), **bellek rahatlatma**, **gizlilik kalkanı**, **sıfır dokunuş** (bu bilgisayara uygun güvenli ayarlar tek tıkla), **akıllı temizlik**, **otomasyon kuralları** (pil, fiş, sıcaklık, bellek, işlemci, boş disk, oyun açılınca / kapanınca, gün ve saat → güç planı, temizlik, odak kipi, bildirim...), **donanım sağlığı ve ömrü** (disk aşınması / sıcaklığı, pil aşınması, açık kalma süresi), **mini izleyici** (her zaman üstte küçük pencere). |
| **Güvenlik** | Denetim, **sağlık raporu → “Düzelt” planı**, sertleştirme, **güvenlik duruşu** (ayarların ve bulguların CIS, NIST, ISO 27001, BSI, NIS2, GDPR ve KVKK başlıklarıyla eşlemesi; [STANDARTLAR.md](STANDARTLAR.md)), hızlı işlemler; Windows 10 destek takvimi ve Windows 11 uyumluluğu; disk sağlığı (SMART) ve pil; kamera / mikrofon / konum kullanım zaman çizelgesi. |
| **Güncellemeler** | Windows Update ara / kur; winget ile program güncelleme ve **sabitleme**; **Denetim**: 35 güne kadar duraklat, özellik güncellemelerini 365 güne kadar ertele, sürücüleri Windows Update’ten ayır; **kurulu güncellemeleri listele ve sorunluyu kaldır**. Windows Update kapatılmaz. |
| **Ağ Araçları** | Genel bakış; **cihaz keşfi** (kendi ağınızdaki tüm cihazlar, tür tahminiyle); **koruma** (ağ profili, ağ geçidi MAC sabitleme, Wi-Fi güvenliği, dinleyen bağlantı noktaları); **VPN ve gizlilik**; DNS karşılaştırma ve şifreli DNS; ping / yol izleme; hız testi; onarım. |
| **Yedek ve Kurtarma** | Klasör yedeği (kopya / tarihli) ve **şifreli, sürümlü yedek (restic)**; Geri Dönüşüm Kutusu, önceki sürümler, geri yükleme noktaları; **BitLocker durumu ve kurtarma anahtarı** (şifrelemeyi başlatmak ve silinen dosyaları geri getirmek için Çözüm Merkezi); taşınma / format öncesi kit. |
| **Şirket Yönetimi** | Envanter ve durum raporu (HTML), şirket ilkeleri, zamanlanmış görevler, ayar profilini dışa / içe aktarma ve dağıtma. |
| **Araçlar** | **Yardımcılar** (kullanıcı kipinde de görünür; internete veri göndermez): **parola üretici**, **toplu yeniden adlandırma** (önizleme, çakışma denetimi, Geçmiş’ten geri alma), **karne** (her işlemden önce ve sonra çalışan hizmet, işlem, boş bellek ve boş alan), **hangi program internete bağlanıyor** (tek tıkla çıkışı kes), açık kaynak **alternatif önerici**, Firefox gizlilik ilkeleri, yeni bilgisayar / format sonrası adım listesi, **yardım paketi** (kişisel veriden arındırılmış zip); Windows yönetim araçlarına kısayollar, işlem listesi, SFC / DISM / disk onarımı, dosya özeti ve dijital imza, güvenli silme; **Dış araçlar** (CrystalDiskInfo, TestDisk ve PhotoRec, WinDirStat, Sysinternals, HWiNFO, WireGuard, 7-Zip, Everything, PowerToys: winget ile onayla kurulur, kurulu olanlar tek tıkla açılır). |
| **Geçmiş ve Geri Al** | Uygulanan her değişiklik burada; tek tıkla geri alınır (ayrıca çift tıklanabilir `.geri.reg` dosyası). |
| **Ayarlar** | **Görünüm** (10 tema, 4 yerleşim, 5 tasarım ve tasarım ayrıntıları, ana ekran biçimi, saydamlık, 8 hazır görünüm, yakınlaştırma, kaydırma ve klavye seçenekleri, güvenli çizim, ayrıntılı hata günlüğü; seçimler açılır listelerle), **sıfırlama** (üç kapsam: yalnızca görünüm, tüm uygulama tercihleri ya da **her şey**; sonuncusu Multimizer’ın Windows’ta yaptığı geri alınabilir değişiklikleri de geri alır; önce ayar kopyası alınır), **tepsi davranışı**, animasyonları azaltma, kullanım türü, otomatik geri yükleme noktası, günlük saklama süresi, **internet istekleri anahtarları**, haftalık bakım, profil kaydet / yükle; **Uygulama** kartı (isteğe bağlı güncelleme denetimi ve dosya bütünlüğü denetimi). |

Komut satırı da vardır (`Ctrl+K` ile pencerede, ya da `-Cli` ile pencere açmadan).

## Çözüm Merkezi

Bilgi vermekle kalmaz, bulduğunu çözer. Her işlem önce **önizlenir**, **onayla** çalışır, günlüğe yazılır; geri alınabilenler Geçmiş sayfasından geri alınır. Hiçbir işlem Defender’ı, Güvenlik Duvarı’nı, UAC’yi, Microsoft Store’u ya da Windows Update’i kapatmaz.

| Sekme | Ne yapar |
|---|---|
| **Sorunlar** | Sağlık taramasının bulgularını toplar; düzeltilebilenlerin yanında *Düzelt* düğmesi vardır. Uzman kipinde her bulgunun altında ilgili standart başlıkları yazılır. |
| **Diskler** | Her sürücünün türünü, dosya sistemini, boş alanını ve BitLocker durumunu gösterir. Windows’un kendi **BitLocker**’ıyla şifreler (önce plan; kurtarma anahtarı şifrelenen sürücünün **dışına** yazılıp geri okunarak doğrulanır, doğrulanamazsa her şey geri alınır); anahtarı gösterir ve kaydeder, korumayı askıya alır, kilitler, şifreyi çözer. Dosya sistemi taraması ve onarımı, sürücü iyileştirme ve disk sağlığı uyarıları da buradadır. |
| **Silinen dosyalar** | Silinmiş dosyaları geri getirir: harf almış her sürücü (dahili disk, USB bellek, SD kart, harici disk), harfsiz bölümler, fiziksel disk ve ham disk imajları (`.img`, `.dd`, `.raw`, `.bin`). NTFS, FAT12/16/32 ve exFAT’ta dosya adı, klasörü ve tarihi korunarak; ext2/3/4’te ve tanınmayan ya da bozuk biçimlerde dosya imzalarına göre (JPEG, PNG, GIF, BMP, PDF, ZIP/DOCX/XLSX, eski Office, MP4, SQLite, 7z, WAV/AVI/WebP). Kaynağa **hiçbir şey yazılmaz**; bulunanlar **başka** bir sürücüye, yeni bir klasöre kaydedilir. |
| **Kalıcı silme** | Dosya ve klasörü, sürücünün boş alanını, diskin ayrılmamış alanını, tek bir bölümü ya da tüm diski geri getirilemeyecek biçimde siler. Yöntem (rastgele, sıfır, üç geçiş), doğrulama ve silme sonrası durum (boş bırak / NTFS / exFAT / FAT32) seçilir. Windows’un çalıştığı diske doğrudan yazılmaz; geri döndürülemeyen işlemlerde hedefin adı elle yazdırılır ve disk işlem anında yeniden doğrulanır. |
| **Sorun gidericiler** | Dokuz belirtiye göre adımlar: bağlantı, saat, ses, yazıcı kuyruğu, Windows Update, görev çubuğu ve simgeler, yavaşlama, dolu disk, mavi ekran. Ne yapacağını ve yan etkisini baştan söyler. |
| **Bu bilgisayar** | Model, Windows, işlemci, bellek modülleri, ekran kartı, diskler, ağ, pil, TPM ve Güvenli Önyükleme okunur; kullanıcı kipinde sade, Uzman kipinde ayrıntılı gösterilir. *Gözlemler* bulunanları yorumlar (tek kanal bellek, HDD üzerinde Windows, eski sürücü, yıpranmış pil...). Bilgiler yalnızca okunur; yeniden başlatma gibi düğmeler yalnızca onayla çalışır. |
| **Hazırlık** | PowerShell, .NET Framework, C# derleyicisi, Visual C++ çalışma zamanları, DirectX, winget, boş alan, WMI ve yan dosyaları denetler. Eksikler yalnızca onayla ve winget’in paket özeti doğrulamasıyla kurulur; kurulabilen paketler sabit bir izin listesidir. Her sürümün ilk açılışında bir kez sessiz bir denetim yapılır (ağa çıkılmaz, hiçbir şey kurulmaz). |

**Sınırlar (dürüstçe).** SSD ve flash belleklerde denetleyici veriyi başka hücrelere taşıdığı ve TRIM silinen verinin çoğunu temizlediği için kurtarma da, üzerine yazarak silme de sınırlıdır; kesin çözüm sürücüyü baştan şifrelemektir. Üzerine yazılmış, sıkıştırılmış ya da şifreli dosyalar geri gelmez. Yedekler, gölge kopyalar ve dosya adı kayıtları (MFT, USN) silinmez. SSD’de üzerine yazma NIST SP 800-88 Rev.1 anlamında “Clear” düzeyindedir; hiçbir standart için belgelendirme iddiası yoktur. Ayrıntı: [CHANGELOG.md](CHANGELOG.md), “Bilinen sınırlar”.

## Görünüm, kaydırma ve tepsi

**Tema** (renkler), **yerleşim** (yoğunluk) ve **tasarım** (kabuğun yapısı) ayrı seçilir; istediğiniz birleşimi kurabilirsiniz (Ayarlar > Görünüm). Hiçbiri sistem ayarına dokunmaz, yalnızca pencerenin görünümünü değiştirir. Varsayılan görünüm **beyaz ve sadedir** (Beyaz tema, Sade yerleşim, Klasik tasarım); koyu ve renkli temalar bir tıkla seçilir. **Dokunma hedefleri** (Ayarlar > Görünüm) Otomatik, Normal ya da Büyük olur: Otomatik, bilgisayarda dokunmatik ekran varsa Büyük’tür; Büyük kipte düğme, sekme ve onay kutuları en az 40 piksel (Kompakt yerleşimde 32) olur, Normal kipte hiçbir ölçü değişmez.

| Tema | Nasıl |
|---|---|
| **Beyaz** (varsayılan) | Beyaz yüzeyler, koyu lacivert düğmeler ve eflatun ikinci vurgu; çok açık gri-mavi zemin. Sade, gün ışığında ve yazdırırken rahat okunur. |
| **Koyu neon** | Koyu zemin, neon turkuaz ve mor vurgular. |
| **Koyu** | Grafit zemin; mavi ve eflatun vurgular. Uzun süre bakmaya uygun. |
| **Krem (sıcak açık)** | Krem kâğıt zemin, kiremit ve erik moru vurgu; göz yormayan sıcak açık tema. |
| **Yüksek karşıtlık** | Siyah zemin, beyaz yazı ve belirgin çizgiler; görmesi zor olanlar için. |
| **Terminal (yeşil)** | Siyah zemin, fosfor yeşili terminal renkleri. |
| **Buzlu cam (açık)** | Açık, pastel zemin ve yarı saydam cam yüzeyler; mavi–eflatun geçiş. |
| **Koyu cam** | Koyu cam yüzeyler, parlayan mavi ve mor çerçeveler; turkuaz ve pembe vurgu. |
| **Renk geçişi** | Mavi, mor ve macenta renklerin aktığı zemin; koyu, yarı saydam kartlar. |
| **Koyu mor** | Çok koyu mor zemin, kızıl–mor tonlar ve gül rengi vurgu. |

| Yerleşim | Nasıl |
|---|---|
| **Ayrıntılı** | Önceki düzen: simge ve yazılı sol menü, işlem günlüğü ile komut satırı açık. Her şey bir arada. |
| **Kompakt** | Dar simge menüsü; günlük ve komut satırı kapalı, sayfaya en geniş alan. |
| **Sade** (varsayılan) | Az kalabalık: açılır menü grupları (Hız ve temizlik, Güvenlik ve ağ, Yönetim) ve başlığa tıklayınca açılıp kapanan kartlar; günlük, komut satırı ve animasyonlar kapalı. |
| **Terminal** | Terminal düzeni: yazılı menü, hep açık komut satırı ve günlük, tek aralıklı yazı. |

| Tasarım | Nasıl |
|---|---|
| **Klasik** (varsayılan) | Bugünkü görünüm: simgeli sol menü ve ayrıntılı durum panosu. |
| **Kartlı** | Büyük karşılama başlığı, yan yana cam kartlar ve tek dokunuşluk büyük düğme. Simge menüsü; bir simgeye tıklayınca alt menü açılır. |
| **Minimal** | Ortada komut çubuğu ve birkaç büyük eylem kartı. Menü gizlidir (sol üstteki düğmeyle açılır); sayı ve grafik kalabalığı yoktur. |
| **Ağ konsolu** | Siyah zemin, ince neon çizgiler, tek aralıklı yazı. Akan günlük, ağ radarı ve dalga biçimli grafikler. |
| **Gösterge paneli** | İnce, daraltılabilir sol menü ve istediğiniz gibi düzenlenen parçalardan oluşan ana ekran. |

Bir tasarımı seçmek yalnızca kabuğun yapısını (menünün biçimi, ana ekranın düzeni, köşe yuvarlaklığı, grafik dili) değiştirir; tema ve yerleşim olduğu gibi kalır.

Ayarlar > Görünüm’deki seçimler **açılır listelerdir**: tema (renk örnekleri ve kısa açıklamayla), yerleşim, tasarım, ana ekran biçimi, arka plan efekti, yüzey opaklığı, yakınlaştırma ve hazır görünüm. **Ana ekran biçimi** her tasarımda seçilebilir: *Pano* (taşıyıp boyutlandırabileceğiniz parçalar) ya da *Klasik durum panosu*. *Tasarım ayrıntıları* altında menü biçimi, köşeler, yazı tipi, grafik biçimi ve parça görünümü tek tek değiştirilir (*Tasarıma göre* seçeneği tasarımın kendi değerini kullanır). Pano parçaları ve eylem kartları konularına göre renklenir (mavi: işlemci ve radar, eflatun: bellek, altın: disk ve bakım, yeşil: sağlık ve ekran kartı, turuncu: sıcaklık); Koyu neon temada tek vurgu rengi kullanılır.

**Ana ekranı düzenleme.** Ana ekran biçimi *Pano* iken (Klasik dışındaki tasarımlarda varsayılan) ana ekran 12 sütunlu bir ızgaradır. *Düzeni aç* ile parçaları sürükleyip yeniden dizebilir, sağ alt köşeden boyutlandırabilir, ✕ ile kaldırabilir, *+ Parça ekle* ile yenisini ekleyebilirsiniz; *Düzeni kilitle* ile sabitlenir, *Varsayılan düzen* tasarımın hazır düzenine döner. 16 parça türü vardır: karşılama başlığı, komut çubuğu, sağlık puanı, işlemci, bellek, disk, ağ, ekran kartı, sıcaklık, eylem kartı, büyük düğme, en çok kaynak kullananlar, akan günlük, ağ radarı, disk bölgeleri ve sistem bilgisi. Eylem kartları uygulamanın var olan işlemlerini çağırır; onay, önizleme ve geri alma kuralları aynen geçerlidir. Ağ radarı yeni tarama başlatmaz, yalnızca son taramanın sonucunu gösterir. Düzeniniz tasarımdan bağımsız kaydedilir: tasarımı değiştirince parçalarınızın yeri korunur. Klasik tasarımda ana ekran Durum Panosu olarak kalır; Ayarlar’daki *Ana ekranı düzenle* düğmesi panoyu ayrı bir sayfa olarak açar.

**Saydamlık** (Ayarlar > Görünüm). Arka plan efekti **Kapalı** (varsayılan), **Mica** ya da **Akrilik**; *yüzey opaklığı* %100 ile %50 arasındadır. Efekti Windows çizer; Multimizer yalnızca kartları, menüyü ve başlığı yarı saydam boyar (açılır pencere, bildirim, iletişim kutuları ve çizgiler opak kalır). Efekt ilk kez seçilince önerilen opaklık gelir (Mica %80, Akrilik %70); %100’de efekt görünmez. Mica Windows 11’e özgüdür, Windows 10’da Akrilik uygulanır. Akrilik, Mica’dan daha çok ekran kartı kullanır; zayıf donanımda Mica ya da Kapalı önerilir. Güvenli başlangıçta, güvenli çizim kipinde, Windows yüksek karşıtlık kipinde, *Yüksek karşıtlık* temasında ve uzak masaüstü oturumunda saydamlık kapalı kalır. Efektsiz düz şeffaflık bilerek yoktur; nedeni [MIMARI.md](MIMARI.md) 4. bölümdedir.

**Kararlılık.** Pencere açıldıktan sonra uygulama beklenmedik biçimde kapanırsa (negatif çıkış kodu) `Baslat.bat` bunu algılar ve bir kez **güvenli kipte** (yalnızca yazılımla çizim, ekran kartı ve sıcaklık izleme kapalı) yeniden açar; 8 saniye içinde vazgeçilebilir. Hangi adımda kapandığı `C:\ProgramData\Multimizer\Kayitlar` altındaki `oturum-iz.txt` ve saklanan `oturum-iz-cokme-*.txt` dosyalarında yazılıdır. Art arda iki kez olursa güvenli çizim kalıcı olur; Ayarlar > Görünüm > *Kararlılık* bölümünden kapatılır (ayrıca `Multimizer.ps1 -Cli -Gorev GuvenliCizim -Deger Kapat`). Aynı bölümde ekran kartı yükü izleme de kapatılabilir.

**Ayrıntılı hata günlüğü.** Sorun ararken Ayarlar > Görünüm > *Kararlılık* altındaki *Ayrıntılı hata günlüğü* anahtarı ya da `Baslat.bat -DebugLog` kullanılır: uygulamanın sessizce geçiştirdiği hatalar da `Kayitlar\ayrinti-GÜN.txt` dosyasına yazılır (saat, kaynak, hata türü ve kimliği, ileti, betik satırı, işlev zinciri, hatalı satır). Aynı hata dakikada bir kez yazılır, dosya günde 2 MB’ta kesilir; varsayılan kapalıdır ve hiçbir veri dışarı gönderilmez.

Tek tıkla **hazır görünümler**: *Varsayılan (beyaz ve sade)*, *Koyu neon*, *Kompakt koyu*, *Terminal* ve her tasarım için birer tane (*Kartlı*, *Minimal*, *Ağ konsolu*, *Gösterge paneli*; tasarım, tema, yerleşim ve saydamlık birlikte gelir). Yakınlaştırma %80 ile %130 arasındadır.
Tüm temaların renk çiftleri WCAG karşıtlık oranlarına göre sınanır (ana metin 7:1, soluk metin ve vurgu 4,5:1); geçişli ve yarı saydam temalarda ölçüm geçişin her durağında yapılır. İşlem günlüğü satırlarının renkleri (PLAN, hata, başarı, uyarı) her temada en az 60° ton farkıyla ayrılır.
Görünüm yüzünden uygulama açılmazsa (art arda çökme ya da hata fırtınası) bir sonraki açılış **güvenli görünümle** başlar: Koyu neon tema, Ayrıntılı yerleşim, Klasik tasarım, %100 yakınlaştırma, saydamlık kapalı. Aynısını elle uygulamak için `Multimizer.ps1 -Cli -Gorev GorunumSifirla`; beyaz ve sade varsayılana dönmek için aşağıdaki sıfırlama kullanılır.

**Ayarları sıfırlama** (Ayarlar > Sıfırlama). İki kapsam vardır: *Görünüm* (tema, yerleşim, tasarım ve ayrıntıları, ana ekran biçimi, saydamlık, yakınlaştırma, hareket, kaydırma, odak halkası, mini izleyici konumu) ve *Tüm uygulama tercihleri* (görünüme ek olarak dil, kullanım türü, bildirim ve tepsi davranışı, izleme, günlük saklama, güvenli silme geçiş sayısı, ana ekran pano düzeni). *Varsayılana sıfırla* önce ayarların kopyasını `C:\ProgramData\Multimizer\AyarYedekleri` klasörüne yazar (en yeni 10 kopya tutulur; kopya yazılamazsa sıfırlama yapılmaz), sonra yalnızca bu listedeki anahtarları döndürür. Windows üzerinde yapılan değişikliklere, zamanlanmış görevlere, yedekleme ayarlarına, ağ koruması durumuna, geri alma kayıtlarına ve güncelleme adresine dokunulmaz. Görünüm sıfırlaması pencerede anında uygulanır; tercihlerin sıfırlanması uygulamayı yeniden başlatır. *Son sıfırlamayı geri al* kopyayı geri yükler (geri alma da kopyalanır, yani o da geri alınabilir). Komut satırından, uygulama kapalıyken: `Multimizer.ps1 -Cli -Gorev AyarSifirla -Deger Gorunum` ya da `-Deger Tercihler`.

**Eski sürümden geçiş.** Önceki sürümde görünümü varsayılandan farklı olan bir ayar dosyası, ilk açılışta bir kez yeni varsayılana taşınır; önceki ayarlar `AyarYedekleri` klasörüne kopyalanır, küçük bir bildirim bunu söyler ve *Son sıfırlamayı geri al* eski görünümü getirir. Yakınlaştırma, ana ekran biçimi, pano ve diğer tercihler korunur; kopya yazılamazsa görünüme dokunulmaz.

**Sağdaki kaydırma çubuğuna gerek yoktur.** Fare tekerleği, dokunmatik yüzey (iki parmak) ve dokunmatik ekranda parmakla sürükleme sayfanın her yerinde çalışır; iç içe listeler sınıra gelince kaydırma sayfaya geçer.
Yumuşak kaydırma, **Başa dön** düğmesi ve klavye odak çerçevesi Ayarlar’dan kapatılabilir.

| Tuş | Ne yapar |
|---|---|
| `PageUp` / `PageDown` | Bir ekran yukarı / aşağı |
| `Home` / `End` | Sayfanın başına / sonuna (sayfaya bir kez tıkladıktan sonra) |
| `Boşluk`, `↑` `↓` | Aşağı / satır satır (yazı kutusunda değilken) |
| `Ctrl+Home` | Başa dön |
| `Ctrl+Tab`, `Ctrl+Shift+Tab` | Sonraki / önceki sayfa |
| `Ctrl+,` | Ayarlar |
| `Ctrl+K` | Komut satırı |
| `F5` | Sayfayı yenile |
| `Ctrl` + tekerlek, `Ctrl` + `+` / `-`, `Ctrl+0` | Yakınlaştır / uzaklaştır / yüzde yüz |
| `Ctrl+W` | Tepsiye indir |
| `Ctrl+Q` | Tamamen kapat |

**Üst çubuk.** Sol üstteki **Multimizer emblemi ana sayfa düğmesidir**: başka bir sayfadayken durum panosunu (ana ekranı) açar, zaten ana ekrandaysa sayfayı en üste kaydırır. Ortada, *Kullanıcı | Uzman* düğmesinin yanında **dil düğmesi** durur (küre simgesi ve çalışan dilin kısa kodu, örn. `TR`); tıklayınca dil listesi açılır: her satırda dilin kendi adı, altında İngilizce adı ve (çevirisi tam olmayan dillerde) kapsam yüzdesi, sağda kısa kodu yazar; seçili dil işaretlidir, `Esc` listeyi kapatır. Pencere daraldıkça önce slogan gizlenir, sonra sayfa adı kutusu daralır ve dil düğmesi yalnızca simgeye iner, en sonda durum etiketleri gizlenir; emblem ve dil düğmesi her genişlikte çalışır.

**Asistan.** Üst çubuktaki **Sor ya da ara** düğmesi (`F1`) sohbet biçimli Asistan’ı açar: ne yapmak istediğinizi ya da sorununuzu kendi sözcüklerinizle yazarsınız (“bilgisayar yavaş”, “disk doldu”, “parola üret”); ilgili açıklamayı ve tek tıkla açılan işlemleri gösterir, sayfa ve komut adlarını da arar. Cevaplar bu bilgisayarda üretilir, yazdıklarınız hiçbir yere gönderilmez; anahtar sözcükler seçili dilin dil dosyasından gelir. Alttaki yardım terminali (`Ctrl+K`) olduğu gibi durur.

**Kısa açıklamalar ve sol çubuk.** Satırlardaki uzun açıklamalar tek satırda kesilir, tamamı üzerine gelince ipucunda okunur (Ayarlar > Görünüm > *Açıklamaları tam göster* eski davranışı geri getirir). Sol çubukta kapalı bir grubun başlığı üzerinde kısa süre durunca grup açılır; bir sayfa düğmesi üzerinde durunca o sayfanın alt sekmeleri yanında bir menü olarak açılır.

**Kurulum teklifi.** Uygulama kurulu olmayan bir kopyadan açılınca sorar: *Kur (önerilir)* önce eksik bileşenleri (Visual C++, .NET, DirectX) denetleyip winget’ten kurar, sonra uygulamayı kalıcı klasöre kopyalar; *Kurmadan kullan* seçilirse bir daha sorulmaz, *Daha sonra sor* ve pencereyi kapatmak sonraki açılışta yeniden sorar. Aynı işlem her zaman Ayarlar > Kur ile yapılabilir.

**Tepsi.** Pencereyi simge durumuna küçültünce ya da kapat (X) düğmesine / `Alt+F4`’e basınca uygulama sağ alttaki bildirim alanına iner ve arka planda çalışmaya devam eder
(süren işlem, zamanlanmış bakım, otomasyon kuralları, mini izleyici). Simgeye çift tıklamak pencereyi geri getirir. **Tamamen kapatmak** için sağ üstteki güç düğmesi, `Ctrl+Q` ya da tepsi menüsündeki *Tamamen kapat* kullanılır.
İki davranış Ayarlar’dan ayrı ayrı kapatılabilir; kapalıyken küçültme görev çubuğuna iner, X uygulamayı kapatır (işlem sürüyorsa önce sorar).

## Dil desteği

Arayüz on iki dilde sunulabilir. Kaynak dil Türkçedir; çeviriler `veri/dil/<kod>.lang` dosyalarından okunur.

| Dil | Kod | Kapsam |
|---|---|---|
| Türkçe | `tr` | Kaynak dil (%100) |
| English | `en` | %100 |
| Deutsch | `de` | %100 |
| 简体中文 | `zh` | %100 |
| 繁體中文 | `zh-hant` | %100 |
| 日本語 | `ja` | %100 |
| العربية (sağdan sola) | `ar` | %100 |
| Français | `fr` | %99 |
| Español | `es` | %99 |
| Italiano | `it` | %99 |
| Português | `pt` | %99 |
| Русский | `ru` | %99 |
| 한국어 | `ko` | %99 |

Çevirisi olmayan metin önce İngilizce, o da yoksa Türkçe gösterilir; hiçbir ekran boş kalmaz. Çeviriler henüz ana dili konuşanlarca gözden geçirilmedi. Yüzdeler dil dosyalarının `#coverage` değerinden alınmıştır; bu sürümle gelen yeni arayüz metinleri (Yardımcılar, Asistan, kurulum teklifi, sıfırlama kapsamları, güç kipi, BitLocker iletileri) bütün dillerde çevrilidir, kalan açık eski sayfa metinlerinde ve uzun açıklamalardadır.
Dil, üst çubuktaki **dil düğmesinden** (aşağıda “Üst çubuk”) ya da **Ayarlar > Dil / Language** kartından seçilir (*Otomatik* Windows ekran dilini izler) ve uygulama yeniden başlatılınca geçerli olur.
Seçim arayüz dilini değiştirmiyorsa (örneğin Windows dili zaten seçilen dilse) yeniden başlatma istenmez; tercih yalnızca kaydedilir.
Sıra: `-Dil <kod>` (örn. `Baslat.bat -Dil de`) > ortam değişkeni `MM_DIL` > Ayarlar > Windows ekran dili.
Açılış ekranı (slogan dahil) 13 dilde yazılıdır ve uygulama açılmadan önce de seçilen dili kullanır.

**Kendi dilinizi ekleyin ya da düzeltin.** `%ProgramData%\Multimizer\dil\<kod>.lang` dosyası, aynı kodlu uygulama dosyasının yerine geçer.
Biçim: UTF-8; üst bilgi satırları `#name: …`, `#native: …`, `#tag: …`, `#rtl: 0|1`, `#match: …`, `#coverage: …`; sonra her satır `Türkçe metin<SEKME>çeviri`.
Değişken parçalar `{0}`, `{1}` yer tutucularıyla yazılır (çeviri sırasını değiştirebilir). `\t`, `\n`, `\\` kaçışları kullanılır.
Çevirisi unutulmuş metinleri bulmak için `MM_DIL_IZLE=1` ile açın; istenen ama çevirisi olmayan metinler `%TEMP%\Multimizer-dil-eksik.txt` dosyasına yazılır.
Her dilde tüm sayfaları gezip çevirisi unutulan ve ekrana sığmayan metinleri listelemek için `araclar\Duman-Dil.cmd` kullanılır.

## Çalıştırma

1. Depoyu indirin ve **tamamını** bir klasöre çıkarın (`Baslat.bat`, `Multimizer.ps1`, `Tani.ps1`, `veri/` ve `Eklenti/` yan yana kalmalı).
2. `Baslat.bat` dosyasına çift tıklayın; yönetici izni istenir. Ayrı bir konsol penceresi açık kalmaz: pencere gelene kadar uygulamanın kendi **açılış ekranı** görünür: ortalanmış marka yazısı, slogan ve ilerleme çubuğu (13 dilde; kayıtlı temaya göre açık ya da koyu çizilir, yüksek DPI’lı ekranda keskindir) ve pencere açılınca yavaşça kapanır.
   Açılamazsa nedenini kendisi arar ve yazar (`Tani.ps1`); elle çalıştırmak için `Baslat.bat /tani`. Konsolu görünür tutmak için `Baslat.bat /gorunur`: renk geçişli MULTIMIZER yazısı, yüzdeli ilerleme çubuğu ve “PID · Modül · Adım” satırı konsol genişliğine göre ortalanarak gösterilir;
   eski ya da renk desteği olmayan konsolda sade metne geçer. Komut satırı kipleri (`-Cli`, `-OzTest`, `-Duman`) konsolu zaten görünür tutar. Multimizer zaten açıksa (tepsideyse de) ikinci açılış hemen çıkar ve mevcut pencereyi öne getirir.
3. İlk kez çalıştırıyorsanız önce kendi kendine sınamayı çalıştırın: `Baslat.bat -OzTest`
   (sistemde kalıcı değişiklik yapmaz; sonuç `C:\ProgramData\Multimizer\ozsinama.txt` dosyasına yazılır).

Gereksinim: Windows 10 veya 11 ve Windows ile birlikte gelen Windows PowerShell 5.1.
“Kısıtlı Dil Modu” (WDAC / AppLocker) açık bilgisayarlarda çalışmaz.

### Dosya düzeni

| Dosya / klasör | Ne işe yarar |
|---|---|
| `Baslat.bat` | Başlatıcı: yönetici izni ister, betiği doğru ayarlarla açar, açılmazsa tanılama çalıştırır. |
| `Multimizer.ps1` | Uygulamanın kendisi (yalnızca ASCII). |
| `Acilis.ps1` | Pencere açmayan başlatıcının açılış ekranı ve denetçisi: ilerlemeyi gösterir, yönetici izni ister, uygulamayı gizli konsolla çalıştırır, çökerse güvenli kipte yeniden açar. |
| `Tani.ps1` | Açılış tanılaması. Yalnızca okur; Defender engelinde tehdit adını gösterir. |
| `veri/` | Düz metin veri: üretici tablosu (`oui.txt`), şüpheli komut kuralları, dil dosyaları (`veri/dil/*.lang`). |
| `Eklenti/` | İsteğe bağlı özellikler, yalnızca kullanılınca yüklenir: `Kurtarma` (silinen dosya kurtarma motoru), `DiskSilme` (boş alan, bölüm ve disk silme), `GuvenliSilme` (dosya ve klasör silme), `DiskKoruma` (BitLocker işlemleri), `Sifreleme` (dosya şifreleme), `Parola` (kriptografik parola üretimi), `Bellek` (bellek boşaltıcı), `WifiAktar` (Wi-Fi parola dışa aktarma). |
| `araclar/Duman-Testi.cmd` | Arayüz duman testi: pencereyi açar, her temada ve yerleşimde sayfaları gezer, düğmelere tıklar, tepsiyi dener. Yönetici gerekmez, sistem ayarına dokunmaz (aşağıya bakın). |
| `araclar/Duman-Tepsi.cmd` | Duman testinin yalnızca tepsi bölümü (simge durumuna küçültme, X, ikinci açılış sinyali, geri getirme); yaklaşık 1 dakika. |
| `araclar/Duman-Gorunum.cmd` | Duman testinin yalnızca görünüm bölümü (her temada her sayfa, tema ve hazır görünüm düğmeleri, ekran görüntüleri); yaklaşık 9 dakika. |
| `araclar/Duman-Dokunma.cmd` | Duman testinin yalnızca dokunma hedefleri bölümü (Ayarlar > Görünüm > Dokunma hedefleri “Büyük” iken her sayfa ve alt sekme, Kompakt yerleşim; erişilebilirlik raporunda Büyük kipte 24 px altı ve 32 px altı hedef sayısı ayrı yazılır); yaklaşık 5 dakika. |
| `araclar/Duman-Tasarim.cmd` | Duman testinin yalnızca tasarım bölümü (her tasarım × tema, ana ekran düzenleme, parça ekleme ve kaldırma, hazır görünümler, ekran görüntüleri); yaklaşık 8 dakika. |
| `araclar/Duman-Saydam.cmd` | Duman testinin yalnızca saydamlık bölümü (Mica ve Akrilik, her opaklık adımı, saydamlıkla tema değişimi; pencerenin gerçek ekran görüntüleriyle); yaklaşık 2 dakika. |
| `araclar/Duman-Ust.cmd` | Duman testinin yalnızca üst çubuk bölümü (ana sayfa emblemi başka sayfadan ana ekrana döner mi, dil listesi açılıp çeviri taramasından geçiyor mu, dil düğmesi kip düğmesiyle aynı yükseklikte mi; pencere ve gerçek ekran görüntüleriyle); yaklaşık 1 dakika. |
| `araclar/Duman-Kullanim.cmd` | Duman testinin yalnızca kullanım bölümü (Asistan, alt sekme menüsü, Yardımcılar ve parola üreteci, kısa açıklamalar, geri dönen ayar kuralı, pano kartlarının ilk ölçümü, sağlık bulguları, kurulum teklifi kutusu; pencere ve gerçek ekran görüntüleriyle). Yönetici gerekmez. |
| `araclar/Duman-Ozellik.cmd` | **Özellik denetimi (gerçek ayarlar).** Kendini yönetici olarak yeniden açar (UAC onayı sorar) ve her ayarı gerçek Windows’ta sınar: ayarı uygular, Windows’un kayıt defteri, hizmet, zamanlanmış görev, Defender, güvenlik duvarı ve oturum düzeyinde gerçekten değiştiğini bağımsız okuyucularla doğrular, geri alır ve ilk duruma döndüğünü doğrular. Ayrıca görsel efektleri ve güç kipini (oturumda yürürlüğe girdi mi), “Windows geri aldı” + Düzelt akışını, parola üreticiyi, toplu yeniden adlandırmayı, dosya şifrelemeyi ve güvenli silmeyi (geçici klasörde gerçek dosyalarla), tüm okuma işlerini, sensörleri ve sağlık bulgularını (Windows ile çapraz kontrol) sınar. Çalışırken her değişikliğin öncesi bir kurtarma dosyasına yazılır; bilgisayar kapanırsa bir sonraki açılışta ilk duruma döndürülür. Temizlik işlemleri (geçici dosya, önbellek, günlük, DISM, Disk Temizleme) gerçekten çalışır ve ikinci önizlemeyle doğrulanır (Geri Dönüşüm Kutusu yalnızca boşsa boşaltılır, eski kurtarma noktaları silinmez); Windows bileşeni ve Mağaza uygulaması kaldırma için her mekanizmadan bir temsilci gerçekten kaldırılıp “geri al” ile geri getirilir (bileşen için internet gerekir). Yalnızca ağ kesme (kill-switch) ve disk silme gerçek hedefe uygulanmaz (önizleme ve geçici alan). Denetim sürerken pencere X’i ve tepsiden çıkış yok sayılır, Ctrl+C yutulur; durdurmak için konsol penceresi kapatılır. Çökme ve konsol sinyalleri `%TEMP%\Multimizer-duman.txt` dosyasına yazılır. Sonuçlar `%TEMP%\Multimizer-duman.txt` ve `%TEMP%\Multimizer-duman-ozellik.tsv` dosyalarına yazılır; yaklaşık 40–90 dakika (DISM tek başına 10–40 dk sürebilir). |
| `araclar/Duman-OzellikOku.cmd` | Özellik denetiminin yalnızca okuma kipi: yönetici gerekmez, sisteme hiçbir şey yazmaz; ölçümleri, okuma işlerini, araçları (geçici klasörde), sensörleri ve sağlık bulgularını sınar. |
| `araclar/Duman-Dil.cmd` | Dil denetimi: seçilen her dilde (varsayılan tr, en, de, zh, ja, ar) tüm sayfaları gezer, ekran görüntüsü alır, çevirisi unutulan ve ekrana sığmayan metinleri listeler; her dil yaklaşık 5–10 dakika. |
| `araclar/Ozet-Guncelle.ps1` | Geliştiriciler için: `veri/` ve `Eklenti/` özetlerini yeniler. |
| `STANDARTLAR.md` | Güvenlik ayarları ve bulgularının CIS, NIST, ISO 27001, BSI, NIS2, GDPR ve KVKK başlıklarıyla eşlemesinin tamamı (uygulamadaki tablolardan üretilir). |
| `tests/` | Birim testleri (55 takım) ve kurtarma testleri için sentetik imaj üreticisi (`gen_images.py`). |
| `kaynak/` | Geliştiriciler için: `Multimizer.ps1` ve `Eklenti/` dosyalarını üreten kaynak ağacı ve derleyici (aşağıda “Geliştirme ve test”). |

`veri/` ve `Eklenti/` içindeki her dosyanın SHA-256 özeti `Multimizer.ps1` içinde kayıtlıdır; değişmiş ya da eksik dosya yüklenmez.
Eksik olursa uygulama yine açılır, yalnızca ilgili özellik çalışmaz.

### Antivirüs uyarısı verirse

Büyük ve imzasız bir betik olduğu için bazı güvenlik yazılımları Multimizer’ı yanlışlıkla zararlı sayabilir
(“Bu betik zararlı içerik içeriyor ve antivirüs yazılımınız tarafından engellendi”). Bu, yönetici izniyle ilgili değildir.
`Baslat.bat` bu durumda `Tani.ps1` ile Defender’ın verdiği tehdit adını gösterir. Güvenlik yazılımını kapatmayın; bunun yerine
Koruma geçmişinden **Cihazda izin ver** deyin, tespiti [Microsoft’a bildirin](https://www.microsoft.com/wdsi/filesubmission)
ya da yalnızca bu klasörü dışlamaya ekleyin. Tehdit adını bir sorun (issue) olarak paylaşırsanız ilgili kalıp araştırılır.

## Tasarım ilkeleri

- **Önce göster.** *Önizle* hiçbir şeyi değiştirmeden tüm değişiklikleri listeler.
- **Geri alınabilir.** Her değişiklik uygulanmadan önce yedek günlüğüne yazılır. Yeniden başlatma isteyen düzeltmeler kendiliğinden uygulanmaz.
- **Dokunulmaz alan.** Windows Defender, Güvenlik Duvarı, UAC, Microsoft Store ve Windows Update **kapatılmaz**; kayıt defteri yazma katmanı bu yollara yazmayı reddeder.
- **İzleme yok.** Hiçbir veri dışarı gönderilmez. İnternet yalnızca siz başlatınca kullanılır (winget, Windows Update, hız testi, DNS testi, sızıntı testi, güncelleme denetimi) ve **Ayarlar > İnternet istekleri** bölümünden tek tek kapatılabilir.
- **Uzaktan kod yok.** Çalışan her şey bu klasördeki düz metin dosyalarında okunabilir (`Multimizer.ps1`, `Eklenti/`); indirilen paketlerin doğrulamasını winget yapar. Güncelleme denetimi yalnızca sürüm numarasını, adresi ve SHA-256 özetini okur; indirilen dosya açılmaz ve çalıştırılmaz.
- **Geri döndürülemez işlemler ayrıdır.** Üzerine yazarak silme, bölüm ve disk silme yalnızca elle yazdırılan hedef adıyla başlar; Windows’un çalıştığı disk, çevrimdışı, salt okunur, havuz üyesi ve kümelenmiş diskler reddedilir.
- **Standart iddiası yok.** Güvenlik ayarlarının uluslararası çerçevelerle eşlemesi bilgilendirme amaçlıdır; sertifika, denetim sonucu ya da uygunluk beyanı değildir ([STANDARTLAR.md](STANDARTLAR.md)).
- **Donanıma uyum.** Güçlü bir bilgisayarda performans özelliklerine dokunulmaz; zayıf bir bilgisayarda hızlandıran ayarlar öne çıkar.
- **Varsayılan kapalı özellikler.** Bellek boşaltıcı, dosya şifreleme (AES-256, .NET’in yerleşik AES’i ile; disk şifreleme ise Windows’un BitLocker’ıdır), ayrıntılı ağ taraması (portlar), ayar bekçisi, odak / oyun kipi, genişletilmiş hosts listesi, VirusTotal araması, akıllı bakım ve otomasyon, mini izleyici Ayarlar’dan isteğe bağlı açılır.
- **Bilerek olmayanlar.** Defender, Kurcalama Koruması, SmartScreen, UAC, Sistem Koruması ve Windows Update’i kapatan; Microsoft Store’u, medya kodeklerini ya da Windows çekirdek paketlerini kaldıran; etkinleştirme filigranını gizleyen anahtarlar yoktur. Bunlar bilgisayarı korumasız bırakır ya da bozar; benzer araçlarda bulunsalar da Multimizer’a eklenmez.

## Ağ özellikleri ve sınırları

- **Tarama yalnızca kendi ağınızda ve sizin başlattığınızda** yapılır; özel adres aralıkları dışına çıkmaz.
- **Cihaz engelleme** bu bilgisayarın Windows Güvenlik Duvarı’nda yerel kural olarak uygulanır (o cihazla bu bilgisayar arasındaki trafik kesilir).
  Başka bir cihazı ağdan **atmak** yönlendirici yönetimi gerektirir; uygulama bunun için adım adım rehber verir. ARP zehirleme, deauth gibi saldırı yöntemleri **yoktur**.
- **VPN:** Multimizer bir VPN sağlayıcısı değildir ve kendi tünel / şifreleme kodu yoktur. Üç yol sunar:
  kendi WireGuard yapılandırmanızı doğrulayıp resmî WireGuard istemcisiyle kullanma, Windows’un yerleşik IKEv2 profili, şifreli DNS (DoH).
  **Kill-switch** yerel güvenlik duvarı kurallarıdır; her zaman kapatılabilir ve `-Cli -Gorev KorumaAc` komutuyla acil durumda kaldırılır.

## İsteğe bağlı dış araçlar

Hiçbiri pakete dahil değildir; gerektiğinde winget ile, onayınızla kurulur. Sürekli geliştirilen araçlar kendi geliştiricilerinde kalır; Multimizer onları kopyalamaz, yalnızca kurar ve açar.

| Araç | Ne için | Lisans |
|---|---|---|
| [restic](https://restic.net) | Şifreli ve sürümlü dosya yedeği | BSD-2 |
| [TestDisk / PhotoRec](https://www.cgsecurity.org) | Silinmiş dosya kurtarma (Çözüm Merkezi’nin kendi kurtarma motoruna ek olarak) | GPL-2.0+ |
| [WireGuard](https://www.wireguard.com) | VPN tüneli | GPL-2.0 |
| [CrystalDiskInfo](https://crystalmark.info/en/software/crystaldiskinfo/) | Disk sağlığı (S.M.A.R.T.) | MIT |
| [WinDirStat](https://windirstat.net) | Disk kullanım haritası | GPL-2.0+ |
| [Sysinternals Suite](https://learn.microsoft.com/sysinternals/) | Süreç, otomatik başlatma ve sistem izleme araçları | Microsoft |
| [HWiNFO](https://www.hwinfo.com) | Ayrıntılı donanım bilgisi ve sensörler | Ücretsiz, kapalı kaynak |
| [7-Zip](https://www.7-zip.org) | Arşiv aracı | LGPL ve unRAR kısıtı |
| [Everything](https://www.voidtools.com) | Anında dosya arama | MIT |
| [PowerToys](https://learn.microsoft.com/windows/powertoys/) | Microsoft’un Windows yardımcı araçları | MIT |

Katalog sabit bir izin listesidir (`Araçlar > Dış araçlar`); listede olmayan bir kimlik hiçbir yolla kurulamaz.

## Komut satırı (şirketler, GPO, Intune, zamanlanmış görev)

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File Multimizer.ps1 -Cli -Gorev Bakim -Sessiz
```

Görevler: `Bakim`, `Rapor`, `Yedekle`, `Durum`, `Duzelt`, `Guncelle`, `Profil -Profil C:\yol\profil.json`, `AgBul`, `KorumaAc`,
`GucPlani -Deger Dengeli|Tasarruf|Yuksek|Nihai`, `AkilliBakim` (sıfır dokunuş), `AkilliTemizlik`, `Sikistir -Deger "D:\Oyunlar\X"` ya da `-Deger CompactOS`, `GorunumSifirla` (görünümü güvenli biçime döndürür: Koyu neon tema, Ayrıntılı yerleşim, %100; pencere açılmasa da çalışır), `AyarSifirla -Deger Gorunum|Tercihler` (görünümü ya da tüm uygulama tercihlerini varsayılana döndürür; önce `AyarYedekleri` klasörüne kopyalar, uygulama açıkken `3` döner).
Her görevle `-DebugLog` verilebilir: yutulan hatalar da `Kayitlar\ayrinti-GÜN.txt` dosyasına yazılır.
Çıkış kodları: `0` tamam, `1` hata, `2` kritik bulgu var (Durum), `3` başka görev çalışıyor.
Şifreli (restic) yedek parola gerektirdiği için zamanlanmış çalışmada atlanır; elle başlatılır.

## Geliştirme ve test

`Multimizer.ps1` yalnızca ASCII karakter içerir (Türkçe harfler çalışma anında üretilir); böylece Not Defteri’yle kaydedilse bile bozulmaz.
`Multimizer.ps1` ve `Eklenti/` içindeki `Kurtarma.ps1` ile `DiskSilme.ps1` **üretilmiş dosyalardır**; kaynakları `kaynak/` altındadır ve oradan yeniden üretilir (`python3 kaynak/build.py`). Ayrıntı için [CONTRIBUTING.md](CONTRIBUTING.md) ve [MIMARI.md](MIMARI.md). Testler Linux’ta PowerShell 7 ile de çalışır:

```
MM_BUILD=./Multimizer.ps1 pwsh -NoProfile -File tests/t_files.ps1
```

`tests/` içindeki her `t_*.ps1` dosyası ayrı bir takımdır (55 takım, 23.177 denetim); CI hepsini çalıştırır, betikleri Windows PowerShell 5.1 ile de ayrıştırır ve `kaynak/` ağacından yeniden üretilen `Multimizer.ps1` dosyasının depodakiyle aynı olduğunu denetler.
`veri/` ya da `Eklenti/` içindeki bir dosyayı değiştirirseniz özet kaydını yenileyin: `pwsh araclar/Ozet-Guncelle.ps1 -Yaz`.
Arayüz (WPF) Windows’ta iki yolla sınanır: `Baslat.bat -OzTest` (kendi kendine sınama) ve `araclar\Duman-Testi.cmd` (duman testi: gerçek pencerede her temayı ve yerleşimi gezer, tema / yerleşim / hazır görünüm düğmelerine tıklar, kaydırmayı, kısayolları ve tepsiyi dener, ekran görüntüsü alır; yaklaşık 25 dakika sürer, sonuç `%TEMP%\Multimizer-duman.txt`). Kısa kapsamlar: `Duman-Tepsi.cmd` (~1 dakika) ve `Duman-Gorunum.cmd` (~9 dakika), `Duman-Tasarim.cmd` (~8 dakika), `Duman-Saydam.cmd` (~2 dakika) ve `Duman-Ust.cmd` (üst çubuk: ana sayfa emblemi ve dil listesi; ~1 dakika); aynı kapsam `MM_DUMAN_KAPSAM=tam|tepsi|gorunum|tasarim|saydam|dil|ust` ortam değişkeniyle de seçilir. Sonuç dosyasına konsol açılış ekranının kipi ve aşama süreleri de yazılır. Duman testi gerçek ayar dosyanızın geçici bir kopyasıyla çalışır ve normal çizimle başlar (kopyada önceki bir çökmeden kalma kalıcı güvenli çizim varsa kapatılır; gerçek ayar dosyasına dokunulmaz). Güvenli kipte denemek için `MM_DUMAN_GUVENLI=1` verin.

## Yol haritası

- Almanca, Çince, Japonca, Arapça çevirilerinin tamamlanması ve diğer dillerin kapsamının artırılması; çevirilerin ana dili konuşanlarca gözden geçirilmesi
- Kod imzalama ve kurulum paketi
- Ayar kataloğunun JSON dosyasına taşınması (eklenti klasörü)
- Üç farklı bilgisayarda (eski HDD’li, dizüstü, oyun PC’si) saha sınaması; özellikle kurtarma ve silme motorlarının gerçek USB bellek, SD kart ve harici disklerde sınanması
- Sanal sabit disk (VHD) üzerinde, yedekli ortamda silme motorunun uçtan uca sınaması

## Sorumluluk

Bu araç sistem ayarlarını değiştirir. Her değişiklik geri alınabilir olacak şekilde tasarlanmıştır, ancak kullanım sizin sorumluluğunuzdadır;
önemli verilerinizin yedeğini alın. Lisans etkinleştirme / kırma aracı değildir ve içermez.

## Lisans

[MIT](LICENSE)

---
ᏖᵀᎥᴮᏋᵀᏖ · S. Tibet Tuncer
