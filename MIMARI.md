# MULTIMIZER — Mimari Karar Kaydı

Bu belge, uygulamanın hangi teknolojiyle geliştirilmeye devam edeceğini, neden o seçildiğini, hangi seçeneklerin
neden bugün seçilmediğini ve ileride neyin ne zaman değişebileceğini açıklar. Karar gerekçeleriyle birlikte yazılıdır;
koşullar değişirse aynı ölçütlerle yeniden verilebilir.

## 1. Ölçütler

Multimizer'ın kullanıcıları ev kullanıcıları ve şirketlerdir. Seçim şu ölçütlere göre yapıldı (önem sırasıyla):

1. **Kurulum gerektirmeme.** Windows 10/11'de ek çalışma zamanı, SDK ya da yönetici kurulumu olmadan açılmalı.
2. **Denetlenebilirlik.** Sistem ayarlarını değiştiren bir araçta kaynak kodun okunabilir olması güven konusudur;
   şirket BT ekipleri çalıştırmadan önce kodu inceleyebilmeli.
3. **Antivirüs uyumu.** İmzasız, derlenmiş ve paketlenmiş yürütülebilir dosyalar sık sık yanlış alarm üretir.
4. **Geri alınabilirlik ve güvenlik.** Her değişiklik önizlenir, günlüğe yazılır, geri alınabilir.
5. **Görsel esneklik.** Temalar, yerleşimler, kullanıcının düzenleyebildiği pano, saydamlık.
6. **Bakım maliyeti.** Mevcut ve test edilmiş kodun (yaklaşık 41 bin satır, 44 test paketi) korunması.
7. **Performans ve kararlılık.** Açılış süresi, bellek, canlı izlemede takılma olmaması.

## 2. Seçenekler

| Seçenek | Kurulum | Denetlenebilirlik | Antivirüs | Görsel esneklik | Taşıma maliyeti | Karar |
|---|---|---|---|---|---|---|
| **Windows PowerShell 5.1 + WPF** (bugünkü) | Yok (Windows ile gelir) | Tam (düz metin) | İyi (imzasız exe yok) | Yüksek (WPF) | Yok | **Seçildi** |
| PowerShell 7 + WPF | PS 7 kurulumu gerekir | Tam | İyi | Yüksek | Küçük | Gereksiz bağımlılık |
| C# + WPF (.NET 8) | .NET çalışma zamanı ya da büyük tek dosya | Orta (derlenmiş) | Orta (imza gerekir) | Yüksek | Çok büyük (yeniden yazım) | Yol haritasında: yardımcı DLL |
| C# + WinUI 3 | Windows App SDK + paketleme | Orta | Orta | Çok yüksek | Çok büyük | Elendi |
| Electron | 100 MB üzeri çalışma zamanı | Orta | Zayıf | Çok yüksek | Çok büyük | Elendi |
| Tauri / WebView2 uygulaması | WebView2 + Rust araç zinciri | Orta | Orta | Çok yüksek | Çok büyük | Elendi |
| Python (Flet / Qt) | Python çalışma zamanı ya da PyInstaller | Orta | Zayıf (PyInstaller) | Yüksek | Çok büyük | Elendi |
| PowerShell + WebView2 (karma) | WebView2 DLL'leri dağıtılır | Tam | İyi | Çok yüksek | Büyük | Gerekirse, yalnızca ön yüz |

### Karar

**Çekirdek Windows PowerShell 5.1 + WPF olarak kalır.** Gerekçe:

- Hiçbir ölçütte açık bir kaybı yok; kurulum, denetlenebilirlik ve antivirüs uyumunda rakipsiz.
- İstenen her şey (kullanıcı düzenli pano, beş tasarım, saydamlık, canlı grafikler) WPF ve Windows'un kendi
  pencere bileşeni (DWM) ile yerel olarak yapılabiliyor; ek kütüphane gerekmiyor.
- Mevcut yatırımın tamamı korunuyor: güvenlik kapısı, geri alma günlüğü, ağ koruması, şirket yönetimi, testler.
- Elenen seçeneklerin getirdiği tek ek kazanç (daha hızlı çizim, daha çok görsel efekt) kurulum ve güven ölçütlerinden
  ödünle ödenirdi. Bu uygulamada kullanıcıların ilk sorusu "bu ne yükledi?" olur; cevabın "yalnızca bir betik" olması değerlidir.

Ek kütüphane gerekmedi. Kullanılan her şey Windows'un kendi bileşenleridir: WPF, DWM (Mica / Akrilik), CIM / WMI, WinRT yerine .NET çağrıları.

## 3. Tasarım motoru

Görünüm üç bağımsız eksendir ve birbirine karışmaz:

- **Renk teması** (Beyaz, Koyu neon, Yüksek karşıtlık, Buzlu cam, ...): yalnızca renkler. Varsayılan Beyaz’dır; ayar anahtarları eski adları taşır (`Acik`, `Neon`, `Hacker`, `Cam`, ...), görünen adlar ayrı tabloda durur, böylece kayıtlı ayarlar adlandırma değişince bozulmaz.
- **Yerleşim yoğunluğu** (Ayrıntılı, Kompakt, Sade, Terminal): boşluklar ve yazı boyutu. Varsayılan Sade’dir.
- **Tasarım** (Klasik, Kartlı, Minimal, Ağ konsolu, Gösterge paneli): kabuğun yapısı — kenar çubuğunun biçimi,
  ana ekranın düzeni, köşe yuvarlaklığı, grafiklerin dili, simge dili.

Ana ekran için **Düzen Motoru** (betikteki «Düzen motoru» bölümü) vardır: 12 sütunlu bir ızgarada döşemeler (tile). Her döşeme bir parçadır
(sağlık puanı, işlemci, bellek, ağ, eylem kartı, akan günlük, ağ radarı, disk bölgeleri, komut çubuğu, ...). Kullanıcı kilidi açar,
döşemeleri sürükler, köşeden boyutlandırır, ekler ya da çıkarır. Çarpışma kuralı react-grid-layout ile aynıdır:
taşınan yerinde kalır, çakışanlar altına itilir, boşluklar yukarı kapanır.

- Motor saf mantıktır (ekrana dokunmaz); bu yüzden Linux'ta bile test edilir (`tests/t_board.ps1`, rastgele işlem dizileri dahil).
- Kayıtlı düzen tasarımdan bağımsızdır: tasarım değiştirilince döşemelerin yeri korunur, yalnızca görünüm değişir.
  Kullanıcı düzene hiç dokunmadıysa tasarımın hazır düzeni uygulanır; dokunduysa kendi düzeni kalır.
- Eylem kartları uygulamanın mevcut işlevlerini çağırır; onay, önizleme ve geri alma kuralları olduğu gibi geçerlidir.
- **Ana ekran biçimi** (`HomeMode`: Pano | Klasik) tasarımdan bağımsızdır: her tasarımda panoya (Düzen Motoru) ya da klasik durum panosuna geçilebilir. Tasarımın beş özelliği (menü biçimi, köşeler, yazı tipi, grafik biçimi, parça görünümü) ayrı ayrı ezilebilir (`Ds*` ayarları; *Tasarıma göre* = tasarımın kendi değeri). Hazır görünümler tema, yerleşim, tasarım, saydamlık, yakınlaştırma ve ana ekran biçimini birlikte taşır.
- **Renkler tek tabloda** (`Themes`, `ThemeGrads`, `ThemeInfo`): bir tema 34 fırça anahtarıdır. Anlamsal renkler (parça ve eylem kartı vurguları) tema anahtarlarından türer; yumuşak yüzey renkleri (`Br*Soft`) vurgunun opak kart rengine karışımıdır. Böylece yeni bir tema ek renk işi gerektirmez; WCAG oranları ve günlük satırı renklerinin ayırt edilebilirliği testle denetlenir.
- **Açılır listeler** (`New-Choice`, `Set-ComboChoices`): öğeler hashtable’dir; kutu, ok, açılan pencere ve öğe şablonları tema fırçalarından okunur, tema değişince kendiliğinden güncellenir.

## 4. Saydamlık

Arka plan efektini Windows'un kendi pencere yöneticisi (DWM) çizer; Multimizer yalnızca kartları, menüyü ve başlığı
yarı saydam boyar. Seçenekler: efekt **Kapalı / Mica / Akrilik** ve yüzey opaklığı **%100 ... %50** (iki ayrı ayar).

| Sistem | Mica | Akrilik |
|---|---|---|
| Windows 11, derleme 22621 ve üzeri | DWM sistem arka planı | DWM sistem arka planı |
| Windows 11 ilk sürüm (22000 - 22620) | eski Mica anahtarı | pencere bileşimi (accent) |
| Windows 10 sürüm 1803 ve üzeri | Akrilik uygulanır | pencere bileşimi (accent) |
| Daha eski sürümler | kapalı | kapalı |

Üç sistem çağrısı (`DwmSetWindowAttribute`, `DwmExtendFrameIntoClientArea`, `SetWindowCompositionAttribute`) uygulamanın başka
yerlerinde kullanılan yöntemle (`Add-Type -MemberDefinition`, yalnızca `DllImport`) tek küçük türde tanımlanır; bellekte dinamik
derleme kurulmaz ve tür, saydamlık ilk kez gerektiğinde derlenir. Derlenemezse efekt kapanır.

- Yüzeyler yarı saydam çizilir; metin ve düğmelerin karşıtlığı korunur. Tema doğrulaması (WCAG oranları) aynı renk işlevinden beslenir,
  yani saydam renklerle de sınanır. Açılır pencere, bildirim, iletişim kutusu yüzeyleri ve çizgiler opak kalır.
- Güvenli başlangıçta, güvenli çizim kipinde, sistem çerçevesine dönüldüğünde, Windows yüksek karşıtlık kipinde, *Yüksek karşıtlık*
  temasında ve uzak masaüstü oturumunda saydamlık kapalı kalır.
- Bir adım başarısız olursa efekt kapatılır ve pencere düz renkle açılır; uygulama açılışı hiçbir zaman saydamlığa bağlı değildir.
- **Bilerek yok: efektsiz düz şeffaflık** (arkasındaki pencerelerin olduğu gibi göründüğü pencere). Gerçek bir Windows 11 bilgisayarında
  (derleme 26300) dört deneyle ölçüldü: pencere bileşiminin düz saydam kipi normal pencerede etki etmiyor; katmanlı pencere biçemi
  (`WS_EX_LAYERED`) çalışan bir WPF penceresine sonradan eklenemiyor; `AllowsTransparency` yalnızca pencere oluşturulurken seçilir
  (yeniden başlatma gerektirir) ve ClearType yazıyı bozar. Mica ve Akrilik ise hem normal pencerede çalışır hem anında değişir.
  Bu yüzden düz şeffaflık eklenmedi; "ayarla ama işe yaramasın" seçeneği sunmak yerine hiç sunulmadı.

## 5. Hata ayıklama günlüğü

Hata günlüğü iki katmandır. `hata-GÜN.txt` yakalanmamış ve arayüzün bildirdiği hataları yazar (aynı ileti 60 sn içinde bir kez, günde en çok ~1 MB).
**Ayrıntılı hata günlüğü** (`-DebugLog` ya da Ayarlar; varsayılan kapalı) ek olarak `try / catch` ile yakalanıp yutulan ve `-ErrorAction SilentlyContinue` ile
susturulan hataları da toplar. PowerShell bu hataları `$Error` listesinde biriktirir; modül listeyi düzenli aralıkla (arayüz zamanlayıcısında yaklaşık 1,5 sn,
her arka plan işinin sonunda, canlı izleme döngüsünde, kapanışta ve komut satırı çıkışında) okur ve yalnızca son okumadan sonraki kayıtları `ayrinti-GÜN.txt`
dosyasına yazar. Kapalıyken yalnızca bir mantıksal değer denetlenir; kod yolu değişmez.

- Satır: saat, kaynak (`ana`, `is`, `izleme`), hata türü ve dilden bağımsız kimliği (`FullyQualifiedErrorId`), ileti, betik satırı, işlev zinciri, hatalı satırın metni.
  Arka plan çalışma alanlarında çekirdek betiğe göre ölçülen satır numarası dosya satırına çevrilir.
- Sınırlar: aynı hata (yol, tırnaklı ad ve sayılar yok sayılarak) dakikada bir kez yazılır, ötekiler sayılır; dakikada en çok 200 satır; günde 2 MB.
- Özet: duman testi bu günlüğü kendiliğinden açar ve raporun sonuna en sık yutulan hataları yazar; program hatası olasılığı yüksek kimlikler
  (boş değere yöntem çağrısı, tanımsız komut ya da yöntem, bağlanamayan parametre) `[kod?]` ile işaretlenir. Özet sonucu etkilemez.
- Gizlilik: dosya yalnızca yerel `Kayitlar` klasörüne yazılır; hiçbir şey dışarı gönderilmez.

## 6. Yol haritası

1. **Şimdi (10.1.0):** Gerçek bilgisayarda sınanıp düzeltilen özellikler (güç kipi, canlı görsel ayarlar, sıcaklık ve ekran kartı okuma, yeniden başlatma, ayar sıfırlama kapsamları, BitLocker yolları), Yardımcılar araç takımı, sohbet biçimli Asistan, açılışta kurulum teklifi, GitHub sürüm hattı (`release.yml`); yanında önceki sürümden gelen çok dilli arayüz (12 dil dosyası, Türkçe kaynak dil; bölüm 18), pencere açmadan başlatma (bölüm 19) ve profesyonel adlandırma; yanında önceki sürümden gelen Çözüm Merkezi (bulduğunu düzelten sayfa), silinen dosya kurtarma ve kalıcı silme motorları, BitLocker ile disk şifreleme, dış araç sağlayıcı katmanı, güncelleme denetimi, güvenlik duruşu eşlemesi; yanında önceki sürümden gelen Düzen Motoru, beş tasarım ve saydamlık (Mica / Akrilik).
2. **Doğrulama borcu:** Kurtarma ve silme motorlarının gerçek USB bellek, SD kart ve harici disklerde; silme motorunun sanal sabit disk (VHD) üzerinde otomatik olarak sınanması. Dış araç kataloğundaki winget kimliklerinin gerçek bir depoda doğrulanması.
3. **Sonra:** Modüllerin isteğe bağlı yüklenmesi (açılış süresini kısaltmak için sayfa kodunun ilk kullanımda kurulması),
   dışarıdan modül (eklenti) uygulama arayüzü için sürümlü bir sözleşme.
4. **İleride, gerekirse:** Küçük, imzalı bir yardımcı DLL (yalnızca PowerShell'in yavaş kaldığı iç döngüler için: disk
   taraması, hex ızgarası çizimi). Betik DLL bulamazsa kendi yoluna döner; çekirdek yine betik olarak kalır.
5. **Koşula bağlı:** Kod imzalama sertifikası (şirket dağıtımında SmartScreen / AppLocker uyumu), ön yüzün WebView2'ye taşınması
   (yalnızca WPF'nin sınırlarına gerçekten dayanılırsa).

## 7. Riskler ve geri dönüş

| Risk | Önlem |
|---|---|
| Saydamlık bazı ekran kartı sürücülerinde kararsız | Varsayılan kapalı; güvenli kipte ve güvenli başlangıçta kapalı; açılış üst üste başarısız olursa görünüm (saydamlık dahil) varsayılana döner; Ayarlar'dan tek dokunuşla kapatılır |
| Sürükle-bırak PowerShell'de yavaşlayabilir | Canlı önizleme yalnızca taşınan döşemeyi çizer; bırakınca tek seferde yerleşir; hareket azaltma ayarına saygı gösterir |
| Kayıtlı düzen bozulur | Doğrulama her açılışta çalışır; geçersiz kayıt sessizce tasarımın hazır düzenine döner |
| Yeni tasarımların bakım yükü | Tasarım = renk anahtarları + kabuk ayarları + hazır düzen; ortak kod tek yerde |
| Silme motoru yanlış diske yazar | Windows'un, Multimizer'ın ve geçici dosyaların bulunduğu diske doğrudan yazılmaz; çevrimdışı, salt okunur, havuz üyesi ve kümelenmiş diskler reddedilir; disk onay anındaki boyut, ad ve seri numarasıyla işlem anında yeniden doğrulanır; geri döndürülemeyen işlemde hedefin adı elle yazdırılır |
| Kurtarma, kurtarılan veriyi kaynağın üzerine yazar | Kurtarma motoru kaynağı yalnızca okur; hedef taranandan farklı bir sürücüdür, her seferinde yeni klasör açılır, var olan dosyanın üzerine yazılmaz, yer yoksa işlem başlamaz |
| BitLocker açıldıktan sonra anahtar kaybolur | Kurtarma anahtarı şifrelenen sürücünün dışına yazılıp geri okunarak doğrulanır; doğrulanamazsa yapılan her şey geri alınır |
| winget kimlikleri ya da paketleri değişir | Kurulabilen paketler sabit bir izin listesidir; kimlik bulunamazsa kurulum denenmez, durum açıkça söylenir; hiçbir şey kendiliğinden kurulmaz |
| Güncelleme denetimi kötüye kullanılır | Yalnızca kullanıcı başlatınca çalışır; yalnızca HTTPS; bildirim ve indirme boyutu sınırlı; SHA-256 tutmazsa dosya silinir; indirilen dosya açılmaz ve çalıştırılmaz |

## 8. Dış inceleme önerilerinin değerlendirmesi

Bağımsız bir kod incelemesinin önerileri tek tek denetlendi:

| Öneri | Sonuç |
|---|---|
| Tek dosyayı `.psm1` modüllerine ve JSON'a bölmek | **Dağıtımda yapılmadı.** Betik bölümlere ayrılmıştır (çekirdek, arayüz, işler) ve testler işlevleri AST ile tek tek yükler. Çalışma zamanında modül yüklemek, ZIP'ten tek dosya çalıştırma hatalarını ve antivirüs yanlış pozitiflerini artırır; tek ASCII betik + `Eklenti\` + `veri\` düzeni korunur. İsteğe bağlı sayfa yükleme (açılış süresi) ve ayar kataloğunun JSON'a taşınması yol haritasındadır. |
| Yerel dile bağlı komut çıktısını ayrıştırmak yerine CIM / .NET | **Denetlendi.** Sistem bilgisi CIM / .NET ile okunur; yerel araçların çıktısı yalnızca dilden bağımsız belirteçlerle okunur (GUID, onaltılık değer, IP / MAC, rakam, sütun konumu: `powercfg`, `arp`, `fsutil`, `winget`). Tek istisna `compact.exe /compactos:query`: metin yerelleştirilmiştir; belirsizse “bilinmiyor” sayılır ve işlem tekrarlanabilir olduğu için güvenle sürer. |
| Boş `catch { }` blokları yerine yapılandırılmış hata günlüğü, `-DebugLog` | **Yapıldı.** Bkz. bölüm 5. |
| Konsol uyumluluğu (VT100, conhost ve Windows Terminal) | **Denetlendi.** Açılış ekranı sanal uç birimi çalışma anında dener (Windows 10 sürüm 1703 ve üzeri, 24 bit renk); eski konsolda, yönlendirilmiş çıktıda ve dar konsolda sade metne geçer; açılış ekranı hiçbir koşulda uygulamanın açılmasını engellemez. |

Bu kararın ölçütleri ve gerekçeleri ilk bölümlerdedir; bir seçenek bu ölçütlerde kazanmaya başlarsa karar yeniden açılır.

## 9. Kaynak ağacı ve üretim hattı

`Multimizer.ps1` ile `Eklenti/Kurtarma.ps1` ve `Eklenti/DiskSilme.ps1` **üretilmiş dosyalardır**; kaynakları `kaynak/` altındadır.

| Yol | İçerik |
|---|---|
| `kaynak/base.ps1` | Önceki yayının betiği, yalnızca ASCII. Gerçek bilgisayarlarda sınanmış kodu olduğu gibi korur; değişiklikler yamalarla eklenir. |
| `kaynak/mods/*.ps1` | Yeni modüller (UTF-8, Türkçe harfli, düz PowerShell). Derlemede ASCII'ye çevrilir: dizelerdeki harfler `[char]0x...`, XAML'de `&#x...;` olur. |
| `kaynak/patches/pNN_*.py` | Tabandaki mevcut kodu değiştiren ve modülleri yerine bağlayan yamalar (`apply(b)`). Alfabetik sırayla uygulanır; her yama beklediği metnin tam kaç kez geçtiğini denetler, tutmazsa derleme durur. |
| `kaynak/src/` | `Kurtarma` ve `DiskSilme` eklentilerinin şablonları ve C# 5 motor kaynakları; `Acilis.tpl.ps1` + `baslatma_dil.tsv` (açılış ekranının şablonu ve 13 dilli metin tablosu; `Acilis.ps1` bunlardan üretilir, metinler ASCII’ye `\uXXXX` olarak gömülür). |
| `kaynak/tools/` | `i18n_wrap.ps1` (arayüz metni atamalarının konumlarını sözdizimi ağacından bulur), `i18n_extract.ps1`, `check.ps1` (PowerShell AST denetimi), `csharp5.ps1` (Roslyn ile C# 5 dil denetimi), `gen_standartlar.py` (STANDARTLAR.md üreticisi), `known_cmds.txt`. |
| `kaynak/build.py`, `check.py` | Derleyici ve derleme sonrası denetim. |

Derleme sırası: taban okunur → yamalar uygulanır (modüller çekirdeğe ya da arayüze eklenir) → eklentiler şablon + C# kaynağından üretilir → `Eklenti/` ve `veri/` dosyalarının SHA-256 özetleri betikteki `$script:PackHash` tablosuna yazılır → çıktının ASCII olduğu doğrulanır → CRLF ile yazılır. Derleme **belirlenimlidir**: aynı kaynaktan her seferinde aynı bayt dizisi çıkar; CI, yeniden üretilen dosyaların depodakilerle aynı olduğunu denetler. `python3 kaynak/build.py` dosyaları yerinde yeniler; `python3 kaynak/check.py` derleme sonrası denetimleri çalıştırır (PowerShell 7 gerekir).

## 10. Çekirdek, arayüz ve eklenti ayrımı

Betik üç bölümdür: **çekirdek** (`$CoreCode`: arka plan işleri ve onların çağırdığı her şey), **arayüz** (WPF pencereleri, sayfalar, olay işleyicileri) ve **eklentiler** (`Eklenti/`, yalnızca kullanılınca yüklenir).

- Arka plan işleri ayrı çalışma alanlarında (runspace) çalışır ve yalnızca çekirdek metnini ile ilgili eklentiyi alır. Bir `Job_*` işlevi ya da çağırdığı bir işlev arayüz bölümündeyse iş çalışırken "komut bulunamadı" hatası verir. `kaynak/tools/check.ps1` içindeki *çekirdek-kapsam* denetimi bunu çağrı grafiğiyle yakalar; `Start-Async` girişlerinin çekirdekte ya da eşlenmiş bir eklentide tanımlı olmasını da arar.
- Eklentiyi `Import-MmExt` yükler: dosyanın düz metnini okur, `$script:PackHash` içindeki SHA-256 özetiyle karşılaştırır, tutmuyorsa **yüklemez**; tutuyorsa betiğin kapsamına alır. Eklenti işlevleri `function global:Ad` ile tanımlanır ve `$script:` değişkeni kullanmaz. Amaç: antivirüs yanlış pozitifine yol açabilecek kodu (üzerine yazarak silme, bellek boşaltma, şifreleme döngüsü) ana betikten ayırmak ve yalnızca gerektiğinde yüklemek.
- Windows PowerShell 5.1'in `Add-Type` derleyicisi **C# 5**'tir. C# 6 ve sonrası özellikler (`$"..."`, `?.`, `nameof`, ifade gövdeli üyeler, `out var`, desen eşleme) orada derlenmez; `check.py` hem düzenli ifadelerle hem Roslyn'in C# 5 dil sürümüyle bütün C# gövdelerini denetler.
- Betik ve eklentiler yalnızca ASCII içerir (Not Defteri ve Windows PowerShell 5.1 BOM'suz dosyayı ANSI okur, ASCII dışı karakter bozulur); Türkçe metinler derlemede çevrilir.

## 11. Çözüm Merkezi

Sayfa anahtarı `solve`; yedi sekme: *Sorunlar*, *Diskler*, *Silinen dosyalar*, *Kalıcı silme*, *Sorun gidericiler*, *Bu bilgisayar*, *Hazırlık*. İlke: **bul, önizle, onayla, uygula, günlüğe yaz, geri alınabiliyorsa geri al.** Her sekmenin okuma işi ve (varsa) yazma işi ayrı `Job_*` işlevleridir; arayüz yalnızca çağırır ve sonucu gösterir.

- *Sorunlar* sağlık taramasının (`Chk_*`) bulgularını toplar; düzeltilebilen bulgu mevcut düzeltme planı mekanizmasına bağlanır, yani yeni bir yazma yolu açılmaz.
- *Diskler* BitLocker için Windows'un kendi yönetim komutlarını kullanır (Multimizer'da kendi disk şifreleme kodu yoktur). Her işlem önce bir plandır (`Test-BlEnablePlan`); anahtarın yazılıp geri okunması planın parçasıdır.
- *Bu bilgisayar* ve *Hazırlık* yalnızca okur; Hazırlık'taki kurulum adımı sabit bir izin listesiyle sınırlıdır (bölüm 13) ve her sürümün ilk açılışında bir kez, ağa çıkmadan ve hiçbir şey kurmadan çalışan sessiz bir denetim yapar.
- Kendi kendine sınama (`Baslat.bat -OzTest`) bu sayfanın izin listelerini ve kapılarını gerçekten sınar: izin listesi dışı paket, http adresi, sistem diski ve sürücü kökü reddediliyor mu.

## 12. Kurtarma ve silme motorları

İkisi de C# 5 ile yazılmış, eklenti olarak yüklenen motorlardır (`Kurtarma`, `DiskSilme`); Windows'ta `Add-Type` ile bu bilgisayarda derlenir, derlenemezse özellik kullanılamaz ve açıkça söylenir.

**Kurtarma (`RcEngine`)** kaynağa hiçbir şey yazmaz: ham aygıt ya da imaj dosyası salt okunur açılır. Bölüm tablosunu (MBR, genişletilmiş bölümler, GPT) okur, her bölümün dosya sistemini imzadan tanır ve dosya sistemine göre iş görür: NTFS'te silinmiş dosya kayıtlarını, FAT12/16/32 ve exFAT'ta silinmiş dizin girdilerini (uzun adlar ve exFAT sağlama toplamı doğrulanarak), ext2/3/4'te boş blokları, tanınmayan ya da bozuk alanlarda dosya imzalarını tarar. Bulunanlar taranandan farklı bir sürücüye, yeni bir klasöre kaydedilir.

**Silme (`WipeEngine`)** yazan tek yoldur ve bu yüzden ayrı bir koruma katmanı vardır: hedef doğrulama (`Test-WipeDiskAllowed`, `Test-WipePartAllowed`, `Test-WipeIdentity`), elle yazdırılan onay (`Test-WipeTyped`) ve dosya düzeyinde ayrı bir kapı (`Test-SecureDeleteAllowed`). Rastgele veri, anahtardan yeniden üretilebilen bir AES-256-CTR akışıdır; bu yalnızca doğrulamada aynı akışı yeniden üretmek içindir, kullanıcı verisi şifrelenmez. Boş alan temizliğinde kanarya dosyalarıyla silmenin gerçekten işlediği ölçülür. `Invoke-WipeSelfCheck` motoru geçici bir imajda uçtan uca sınar; bu, `Baslat.bat -OzTest` adımlarından biridir ve diske yazmaz.

**Testler.** İki motor da Linux'ta, `tests/gen_images.py` ile **kendi ürettiğimiz** sentetik NTFS, FAT12/16/32 ve exFAT imajlarıyla (MBR ve GPT sarmalı dahil) ve sahte Windows depolama komutlarıyla sınanır. Üçüncü taraf imajı kullanılmaz ve pakete konmaz. Gerçek USB bellek, SD kart ve fiziksel disklerde yazma yolunun sınanması yol haritasındadır (bölüm 6).

**Dürüst sınırlar.** SSD ve flash belleklerde denetleyici veriyi başka hücrelere taşıdığı ve TRIM silinen verinin çoğunu temizlediği için kurtarma da, üzerine yazarak silme de sınırlıdır; kesin çözüm baştan şifrelemedir. Silme yöntemleri hiçbir silme standardına uygunluk iddia etmez.

## 13. Sağlayıcı katmanı: dış araçlar ve Hazırlık

Kendi alanında yerleşik ve sürekli geliştirilen bir aracı yeniden yazmak ya da pakete kopyalamak yerine **onu kurar ve açar**: böylece güvenlik düzeltmeleri aracın geliştiricisinden gelir, Multimizer'ın boyutu ve denetim yüzeyi büyümez.

- `Get-ExtToolCatalog` sabit bir listedir (CrystalDiskInfo, TestDisk ve PhotoRec, WinDirStat, Sysinternals Suite, HWiNFO, WireGuard, 7-Zip, Everything, PowerToys). `Test-ExtToolId` listede olmayan kimliği reddeder; listeye araç eklemek kod değişikliğidir, ayar değildir.
- Kurulum yalnızca kullanıcı onayıyla ve winget aracılığıyla yapılır; paketin SHA-256 doğrulamasını winget yapar. Hiçbir araç kendiliğinden kurulmaz, güncellenmez ya da çalıştırılmaz.
- Hazırlık sekmesinin kurabildiği şeyler de sabit bir izin listesidir (`$script:PrepPackages`; `Test-PrepPackage`): Visual C++ 2015-2022 çalışma zamanları (x64, x86, ARM64), DirectX eski çalışma zamanı ve .NET Masaüstü Çalışma Zamanı. Başka hiçbir kimlik hiçbir yoldan kurulamaz.
- `Baslat.bat` bilerek değişmedi: başlatıcı hiçbir şey kurmaz; kurulum, uygulamanın içinde, açıkça ve onayla yapılır.

## 14. Güncelleme denetimi ve dosya bütünlüğü

Güncelleme denetimi yalnızca kullanıcı **Güncellemeleri denetle** düğmesine bastığında çalışır ve `$script:NetFeatures` tablosundaki "güncelleme denetimi" anahtarıyla kapatılabilir. Okunan şey bir bildirim dosyasıdır (sürüm, adres, SHA-256); kullanıcıya ait hiçbir veri gönderilmez.

- Yalnızca HTTPS; her yönlendirme adımı ayrıca denetlenir (en çok 5, elle izlenir); bildirim en çok 256 KB; indirme en çok 300 MB, hem `Content-Length` ile baştan hem akış sırasında sınırlanır.
- İndirme ayrıca onay penceresinden geçer. Özet tutmazsa dosya silinir. İndirilen dosya **açılmaz ve çalıştırılmaz**; kullanıcı klasörü açar, kurulumu kendisi yapar.
- SHA-256 dosyanın yolda değişmediğini ve bozulmadığını gösterir, **yayıncının kimliğini kanıtlamaz**: yayıncı hesabı ele geçirilirse bildirim ve dosya birlikte değişebilir. Bu yüzden güncelleme kendiliğinden uygulanmaz. Yayıncı kimliği için kod imzalama sertifikası yol haritasındadır (bölüm 6).
- *Dosya bütünlüğünü denetle* yan dosyaları (`Eklenti/`, `veri/`) derleme sırasında yazılan özetlerle karşılaştırır; yalnızca okur.

## 15. Güvenlik duruşu ve standart eşlemesi

48 sertleştirme ayarı ve 65 sağlık bulgusu, CIS Critical Security Controls v8, NIST SP 800-53 Rev. 5, ISO/IEC 27001:2022 Ek A, BSI IT-Grundschutz, AB 2022/2555 (NIS2) m.21(2), AB 2016/679 (GDPR) ve 6698 sayılı KVKK'nın ilgili başlıklarıyla eşlenmiştir. Eşleme koddaki tablolardadır ve [STANDARTLAR.md](STANDARTLAR.md) bunlardan `kaynak/tools/gen_standartlar.py` ile **üretilir**; üretilen belge güncel değilse `check.py` derlemeyi durdurur, yani belge ile kod birbirinden ayrışamaz.

Eşleme **bilgilendirme amaçlıdır**: sertifika, denetim sonucu ya da uygunluk beyanı değildir ve bir başlığa bağlanmış olmak o başlığın karşılandığı anlamına gelmez. Sağlık taramasındaki *Güvenlik duruşu* bulgusu uygulanmamış ayarları tek yerde toplar; kapsam yüzdesi yalnızca bu bilgisayarda uygulanabilen düzey 1-2 ayarlarından hesaplanır, gizlilik konusu yüzdeye girmez.

## 16. Test stratejisi

55 takım, işlevleri derlenmiş dosyadan AST ile tek tek çıkarıp sahte bağımlılıklarla sınar (WPF gerekmez); bu yüzden Linux'ta PowerShell 7 ile de çalışır. Üç ilke:

1. **Hem olumlu hem reddedilmesi gereken durumlar sınanır.** Yeni bir kapı (sistem yolu, geçersiz sürücü, izin listesi dışı kimlik, http adresi) eklenince, kapının gerçekten kapattığını gösteren bir olumsuz test de eklenir.
2. **Kurulum kodu da sınanır.** `Baslat.bat -OzTest` Windows'ta bu bilgisayarın derleyicisiyle motorları derler, silme motorunu geçici imajda sınar ve izin listelerinin kapılarını yoklar; yalnızca sahte ortamda yeşil görünen bir şeyin gerçekte de çalıştığı böyle görülür.
3. **Gerçek bilgisayarda sınama, sahte ortamın göremediğini bulur.** İlk gerçek Türkçe Windows 11 çalışmasında Linux’ta yeşil olan 47 adımın dördü kırmızıydı; üçünün nedeni Türkçe kültürdeki “I” harfiydi (bölüm 17). Bu yüzden kendi kendine sınama kültür korumasını da dener.
4. **Testlerin kendisi sınanır.** Güncelleme denetimi, dış araçlar ve bağlantılar için kasıtlı bozma denemeleri yapıldı (72 bozma, 72'si testlerce yakalandı; ilk turda kaçan üç bozma için test eklendi). Bir test, kodu bozunca kırmızıya dönmüyorsa hiçbir şey sınamıyordur.

Arayüzün gerçek pencerede sınanması için `araclar/Duman-*.cmd` kullanılır; ayrıntı [README.md](README.md) ve [CONTRIBUTING.md](CONTRIBUTING.md) içindedir.

## 17. Kültür koruması (Türkçe “I”)

**Sorun.** Windows PowerShell 5.1 (.NET Framework), `-match`, `-replace`, `(?i)` ve `[regex]::IsMatch` ile yapılan harf boyuna duyarsız eşleşmelerde metni kullanıcının kültürüne göre küçültür. Türkçe ve Azerice kültürde `I`, `ı` olur; oysa `[A-Za-z]` ve `[\x20-\x7E]` gibi sınıflar değişmez kültürle kurulur. Sonuç: `'Input' -match '^[A-Za-z]+$'` yanlış çıkar, `'INTEL' -match 'intel'` yanlış çıkar, bilgisayar adındaki `I` harfi silinir, `I:` sürücüsü reddedilir, base64 anahtarındaki `I` geçersiz sayılır. PowerShell 7 ve Linux’ta (değişmez küresel kip) bu hiçbir testte görünmez; sorun gerçek bir Türkçe Windows 11 bilgisayarında kendi kendine sınamayla bulundu.

**Çözüm iki katmanlıdır.**

1. `Set-MmCulture`, betiğin ilk işidir (yeniden başlatma mantığından önce) ve her arka plan çalışma alanının ile `AsyncWrapper`’ın başında yeniden çağrılır. Değişmez kültürün bir kopyasını kurar; sayı ve tarih biçimini kullanıcının kültüründen alır (ondalık ayırıcı, tarih deseni değişmez), harf boyu kuralını değişmez kültürden alır ve `DefaultThreadCurrentCulture` ile sonradan açılan iş parçacıklarına da yayar. Sorun yoksa hiçbir şey yapmaz.
2. Doğrulayıcılar ve sistem klasörü korumaları kültüre bağlı kalmasın diye `-cmatch`, `-cnotmatch`, `-creplace` ya da `ToLowerInvariant()` kullanır. `tests/t_culture.ps1` derlenmiş betikteki bütün harf boyuna duyarsız işleçleri AST ile tarar, `I` içeren aralık sınıfı (`[A-Za-z]`, `[a-z]`, `[\x20-\x7E]`) ve kültürlü `ToUpper()` / `ToLower()` bırakılmadığını denetler.

**Sınırlar.**

- PowerShell düzenli ifade nesnelerini süreç genelinde önbelleğe alır; bir örüntü ilk kez Türkçe kültürle kullanılmışsa o süreçte öyle kalır. Koruma bu yüzden betiğin ilk işidir.
- `@{}` ve `[ordered]@{}` tablolarının anahtar karşılaştırıcısını PowerShell, süreç başında kullanıcının kültürüyle bir kez kurup saklar; iş parçacığı kültürü bunu değiştirmez (cihazda görüldü: Türkçede `@{ Info = 1 }['info']` boş döner). Çözüm kodda uygulanır: anahtarlar tabloya yazılırken ve okunurken `ToLowerInvariant()` ile normalleştirilir; dış metinden gelen, harf boyu değişebilen anahtarlar için `New-Object System.Collections.Hashtable ([System.StringComparer]::OrdinalIgnoreCase)` kullanılır. PowerShell’in iç alanlarını yansımayla değiştirmek bilerek yapılmadı: kırılgandır ve antivirüs sezgilerinin tanıdığı bir kalıptır.
- Konsol programlarının (`robocopy`, `sfc`, `dism` ...) çıktı kodlaması `Get-OemEncoding` ile işletim sisteminin OEM kod sayfasından (`OEMCP` kaydı) okunur; kullanıcının bölgesel kültürü bunun için ölçü değildir.

**Gerçek sınama.** `Multimizer.ps1 -OzTest` içindeki “Türkçe kültür koruması” adımı, bu eşleşmeleri ana iş parçacığında ve arka plan çalışma alanında dener.

## 18. Dil desteği

**Karar.** Kaynak dil Türkçedir ve **Türkçe metnin kendisi kimliktir** (gettext tarzı). Ayrı bir anahtar kataloğu tutulmaz; böylece kaynak metin ile katalog birbirinden ayrışamaz, Türkçe için dil dosyası gerekmez ve yeni bir metin yazan kişi çeviri anahtarı uydurmaz. Bedeli: Türkçe bir cümleyi düzeltmek, o cümlenin çevirilerini de yeniden eşlemeyi gerektirir (dil dosyasındaki kimlik değişir). Bu bedel kabul edildi, çünkü tersi (anahtar katalogu) 6.900 metinde sürekli bakım ve “anahtar var, metin yok” hatalarına yol açar.

**Dil dosyası.** `veri/dil/<kod>.lang`, UTF-8, düz metin: `#name`, `#native`, `#tag`, `#rtl`, `#match`, `#coverage` üst bilgisi, sonra `Türkçe metin<SEKME>çeviri` satırları. Kimlikteki `{0}`, `{1}` dinamik parçayı gösterir (“Silindi: {0} dosya”); çeviri bunların sırasını değiştirebilir, sayıları aynı olmak zorundadır (`t_i18n` denetler). `\t`, `\n`, `\\` kaçışları vardır. Uygulamayla gelen dosyaların SHA-256 özetleri diğer yan dosyalar gibi `$script:PackHash` içinde kayıtlıdır; dosya bütünlüğü denetimi (Ayarlar > Uygulama) bunları doğrular. Dil dosyaları çalışma anında yalnızca metin olarak okunur, hiçbir şey çalıştırmaz; bu yüzden kullanıcının `%ProgramData%\Multimizer\dil` klasörüne koyduğu aynı kodlu dosya, özet aranmadan uygulamanınkinin yerine geçer.

**Çözümleme.** `Tr` işlevi sırayla arar: birebir eşleşme → baştaki/sondaki boşluk ve işaretler atılmış hâli → şablon (`{n}`) → büyük/küçük harf ve ek farkları gevşetilmiş hâli → cümleyi parçalara bölüp (ayırıcı, parantezli sayı, köşeli ek) parça parça çevirme. Seçili dilde bulunamazsa İngilizce paket, o da yoksa metin olduğu gibi (Türkçe) döner. Bu zincir kasıtlıdır: eksik çeviri hata değil, daha az çevrilmiş bir ekrandır. Sonuçlar bellekte önbelleğe alınır (izleme kapalıyken).

**Neyin çevrildiği.** Derleyici (`build.py`, `i18n_wrap`) arayüz metni atamalarını (`.Text`, `.Content`, `.ToolTip`, `.Header`, `.Title`, bildirim başlıkları) sözdizimi ağacından bulup `(Tr $(ifade))` ile sarar; veri nesnelerine yapılan atamalar ve satırında `# Tr:yok` yazanlar sarılmaz. XAML içindeki metinler pencere kurulurken `Convert-XamlText` ile çevrilir. İşlem günlüğü satırları (`Convert-LogLineText`) saat ve etiket korunarak çevrilir. Sarma sonucu kaynak değişmedikçe `wrapmap.json` önbelleğinde durur (PowerShell yalnızca kaynak değişince gerekir).

**Dile özgü işler.** Arapça için pencere `FlowDirection` ayarı, hizalamalar ve çift yönlü metin (`Convert-LangBidi`) ele alınır. Yüzde işareti üç yazımdan biriyle gösterilir (`%40`, `40%`, `40 %`; `Get-LangPercentStyle`). Büyük harfle yazılmış başlıklar, çevirisi küçük harfle bulunduğunda dilin kültürüyle büyütülür (`Convert-LangUpper`); bölüm 17’deki kültür koruması bundan bağımsız ve ayrıdır.

**Seçim ve değiştirme.** Sıra: `-Dil` > `MM_DIL` > `Ayarlar.Language` > Windows ekran dili (`Auto`). Dil çalışırken değiştirilmez: Ayarlar onay sorar, ayarı yazar ve uygulamayı yeniden başlatır. Böylece açık pencerelerde yarım çevrilmiş metin kalmaz ve `Tr` çağrılarının önbelleği tutarlı kalır.

**Kapsam ve dürüstlük.** Dil dosyasındaki `#coverage` değeri, çevrilmiş kimliklerin toplam kimlik sayısına oranıdır; Ayarlar kartı bunu olduğu gibi gösterir. Değer yükseltilirken çeviriyle birlikte güncellenmelidir. Kalite denetimi için iki araç vardır: `MM_DIL_IZLE=1` (istenen ama çevirisi olmayan metinleri `%TEMP%\Multimizer-dil-eksik.txt` dosyasına yazar) ve `araclar/Duman-Dil.cmd` (her dilde tüm sayfaları gezer; ekran görüntüsü, SIZINTI ve KESIK listesi üretir).

**Sınırlar.** Çeviriler ana dili konuşanlarca gözden geçirilmedi. Uzun açıklamalar ve belge şablonları büyük ölçüde yalnızca İngilizce çevrilidir. Çalışma zamanı çevirisi yalnızca görünen metni kapsar: ayar anahtarları, komut adları, günlük dosyası adları ve `Baslat.bat` iletileri çevrilmez (Baslat.bat’ın klasik akıştaki iletileri ASCII Türkçedir; açılış ekranı ise 13 dildedir).

## 19. Pencere açmadan başlatma ve açılış

**Sorun.** `Baslat.bat` çift tıklanınca siyah bir konsol penceresi açılıyor ve uygulama penceresi gelene kadar (10–30 sn) ekranda kalıyordu; konsolu kapatan kişi uygulamayı da kapatıyordu.

**Karar.** Arayüz kipinde `Baslat.bat` kendini simge durumunda yeniden açar (`/mmic`) ve gizli bir PowerShell’de `Acilis.ps1` çalıştırır. Aynı dosya iki roldedir:

- **Karşılama:** WinForms ile kenarlıksız bir açılış ekranı çizer (renk geçişli MULTIMIZER yazısı, durum metni, ilerleme çubuğu); metin 13 dildedir ve dil `-Dil` / `MM_DIL` / kayıtlı ayardan, o yoksa Windows ekran dilinden bulunur. İlerlemeyi uygulamanın yazdığı `acilis-KOD.txt` dosyasından (`yüzde|sonraki yüzde|anahtar|süreç`) okur; uygulama penceresi açılınca `oturum-acik-KOD.txt` işaretiyle kapanır. Yönetici izni gerekiyorsa Denetçi’yi `RunAs` ile başlatır.
- **Denetçi** (`-Rol Denetci`): yönetici olarak uygulamayı gizli konsolla çalıştırır ve bitişini bekler. Pencere açıldıktan sonra negatif (Windows çökme) koduyla biterse **bir kez** güvenli kipte (yazılımla çizim) yeniden başlatır; hiç açılamadıysa `Tani.ps1` raporunu bir pencerede gösterir.

Komut satırı kipleri (`-Cli`, `-OzTest`, `-Duman`), `/tani`, `/gorunur`, yükseltilmiş yeniden açış ve `Acilis.ps1`’in yokluğu klasik akışı (görünür konsol, uygulamanın kendi konsol açılış ekranı) seçer; çıktı okunabilsin diye.

**Uygulama tarafı.** Konsol açılış ekranı (`Start-Splash`, `Set-SplashStep`) yüzde tablosuyla (`$script:SplashPhases`) ilerler; `Gizli` kipte konsola yazmaz, yalnızca `acilis-KOD.txt` dosyasını günceller. Başlatıcının ve uygulamanın aşamaları aynı anahtarları kullanır: `baslat, izin, arayuz, veri, cekirdek, ayarlar, calisma, sistem, pencere, hazir`.

**Ölçüm.** Pencere açılınca oturum izine “açılış süreleri (ms)” satırı yazılır: `onyukleme` (süreç başlangıcından betiğin ilk satırına: çalışma zamanı ve AMSI), her aşamanın başlangıcı, `toplam` ve sistem profili adımları. Gerçek bir Windows 11 bilgisayarında harcanan zamanın büyük kısmı betiğin ayrıştırılması (~1 sn), çekirdek işlevlerin yüklenmesi (~3 sn), sistem profili (disk sorguları dahil) ve pencerenin kurulmasıdır (~2 sn). Disk türü ve modeli (Storage modülü) profilin geri kalanıyla **paralel** çalışma alanında bulunur; sistem diskinin boş/toplam alanı `DriveInfo` ile okunur.

**Sınırlar.** Yönetici onayı (UAC) otomatik sınanamaz. “Pencere açıldı” işareti, uygulama penceresinin yüklenmesinden sonra yazılır; arayüzün ilk çiziminden önce çöken bir kurulum açılış ekranını çökme koduyla birlikte bırakmaz, Denetçi tanılamaya geçer.

**Açılış ekranının görünümü.** Pencere 600×340 mantıksal pikseldir (ölçek ekranın DPI’sından hesaplanır, 1–4 arası) ve ekranın ortasında açılır; marka işareti, MULTIMIZER yazısı, slogan, durum metni, ilerleme çubuğu ve yüzde yatayda ortalanır ve tek bir ızgaraya göre yerleşir (`Get-SplashLayout`, saf işlev). Renkler kayıtlı temadan seçilir (`Get-LaunchLight`): Beyaz, Krem ve Buzlu cam için açık, diğerleri için koyu palet; ayar dosyası yoksa ya da eski sürümden kalmışsa uygulama beyaz temayla açılacağından ekran açık çizilir. İki palet de metin–zemin karşıtlığı için sınanır (`Get-SplashPalette`; ana metin 7:1, soluk metin 4,5:1). Pencere kenarlıksızdır, saydamlığı kademeli artar ve kapanırken azalır (`Set-SplashOpacity`). Çizim GDI+ ile yapılır; herhangi bir çizim adımı hata verirse yalnızca düz “MULTIMIZER” yazısı kalır ve açılış sürer. Açılış ekranı yüksek DPI’lı ekranda bulanık büyütülmesin diye `Baslat.bat` açılış sürecini `__COMPAT_LAYER=HIGHDPIAWARE` ile başlatır (ortam değişkeni yalnızca bu başlatma için kurulur ve hemen kaldırılır). Slogan 13 dilde `baslatma_dil.tsv` tablosundadır.

**Konsol akışı.** `Baslat.bat` konsolun sütun sayısını `mode con` çıktısından okur (okunamazsa 80 varsayılır; 40–400 aralığına kırpılır) ve ön başlığı ile yönetici izni notunu bu genişliğe göre ortalar. Uygulamanın konsol açılış ekranı (`Start-Splash`) aynı kuralı kendi içinde uygular (`Get-SplashLead`, `Get-SplashIndent`: görünen genişliğe göre `⌊(genişlik − 1 − görünen)/2⌋` boşluk). Çıktı yönlendirilmişse (dosyaya ya da başka bir programa) ortalama kapalıdır, böylece çıktı baştaki boşluklarla şişmez.

## 20. Ayarları sıfırlama ve varsayılan görünüm

**Sorun.** Kullanıcı görünümü ya da tercihleri toplu olarak ilk haline döndürebilmeli; yeni varsayılan (beyaz ve sade) eski kayıtlı ayarları sessizce ezmemeli; sıfırlama Windows üzerindeki gerçek değişikliklere dokunmamalı.

**Karar.** Sıfırlama bir **beyaz liste**dir: `ResetLookKeys` (20 anahtar) ve `ResetPrefKeys` (16 anahtar). Listede olmayan hiçbir ayara dokunulmaz; yeni eklenen bir ayar listeye yazılmadıkça sıfırlanmaz. Bu, “her şeyi sil” yerine “bilinen tercihleri döndür” yaklaşımıdır: uygulanan düzeltme kayıtları, zamanlanmış görevler, yedekleme kaynakları, ağ koruması durumu, bilinen cihazlar ve güncelleme adresi böylece korunur.

- **Saf çekirdek.** `Get-ResetResult` mevcut ayar tablosunu alır; sıfırlanmış kopyayı ve değişen anahtarların listesini döndürür, dosyaya ve belleğe dokunmaz. Testler bu işlevi doğrudan sınar.
- **Önce kopya.** `Save-SettingsBackup` her sıfırlamadan önce ayarları `AyarYedekleri\ayarlar-yyyyMMdd-HHmmss-<gorunum|tercihler|geri-alma>[-N].json` olarak yazar; en yeni 10 kopya tutulur, klasördeki yabancı dosyalara dokunulmaz. Kopya yazılamazsa sıfırlama **yapılmaz**. Geri alma da kendi öncesini kopyalar (`geri-alma`), böylece geri alma geri alınabilir.
- **Görünüm anında, tercihler yeniden başlatarak.** Görünüm sıfırlaması çalışan pencereye uygulanır; dil, kullanım türü ve tepsi gibi tercihler başlangıçta okunduğundan uygulama onay alındıktan sonra yeniden başlatılır.
- **Komut satırı.** `-Cli -Gorev AyarSifirla -Deger Gorunum|Tercihler`; çıkış kodları `0` tamam, `1` hata, `3` arayüz açık (kapsam her iki ayar yazıcısının çakışmaması için arayüz mutex’i `Global\Multimizer-Arayuz` tutulurken reddedilir). `GorunumSifirla` farklı bir araçtır: çökme sonrası kurtarma için görünümü **güvenli** değerlere (Koyu neon, Ayrıntılı, Klasik, %100, saydamlık kapalı) döndürür.
- **Varsayılan taşıma.** Ayar dosyasında `LookVersion` yoksa ve görünüm anahtarlarından biri yeni varsayılandan farklıysa, önce `gorunum` kopyası alınır, sonra yalnızca görünüm anahtarları (tema, yerleşim, tasarım, saydamlık ve tasarım ayrıntıları) yeni varsayılana çekilir ve `LookNotice` ile tek seferlik bildirim planlanır. `LookVersion` taşımanın bir kez yapılmasını sağlar; sıfırlama da onu yazar, böylece taşıma yeniden çalışmaz. Yeni kurulumda (görünüm anahtarı hiç yok) bildirim gösterilmez.

**Sınır.** Sıfırlama Windows’a yapılmış değişiklikleri geri almaz; onlar için Geçmiş sayfası ve geri alma kayıtları vardır. Sıfırlama kartı bunu açıkça söyler.

## 21. Üst çubuk: ana sayfa emblemi ve dil seçici

**Sorun.** Dil yalnızca Ayarlar’daki karttan seçilebiliyordu; sol üstteki marka işareti ise süstü. Kullanıcı dili hızla değiştirebilmeli ve her sayfadan tek tıkla ana ekrana dönebilmeli. Bunun için başlık çubuğunun dar pencere yerleşimi bozulmamalı, dil değişimi de açık pencerelerde yarım çevrilmiş metin bırakmamalıdır (bölüm 18).

**Karar.** Başlık çubuğuna iki öğe eklendi; ikisi de pencere kromunun içinde tıklanabilir (`IsHitTestVisibleInChrome`).

- **Ana sayfa emblemi** (`BtnHome`). Emblem ve MULTIMIZER yazısı tek, saydam bir düğmedir (üzerine gelince yumuşak zemin alır). `Invoke-HomeClick`: açık menüleri kapatır; başka bir sayfadaysa `Show-Page 'panel'` çağırır (ana ekran biçimi *Pano* ise `Show-Page` zaten panoya yönlendirir), zaten ana ekrandaysa sayfayı en üste kaydırır.
- **Dil kapsülü** (`LangCapsule`: `BtnLang` + `LangPop`). KULLANICI | UZMAN kapsülüyle aynı yüzey, kenarlık ve yükseklikte durur (gerçek bilgisayarda ikisi de 35 px); küre simgesi, çalışan dilin kısa kodu (`TR`, `ZH-TW`) ve açılır ok içerir. Tıklayınca liste açılır: *Otomatik* (Windows ekran dili), Türkçe ve bulunan her dil dosyası; her satırda dilin kendi adı, altında İngilizce adı ve (çevirisi tam olmayan dillerde) kapsam yüzdesi, sağda kısa kodu vardır, kayıtlı seçim işaretlidir. Liste `StaysOpen=False` açılır: `Esc`, pencerenin etkinliği yitirmesi ya da düğmeye yeniden tıklamak kapatır (kapanan listeyi aynı tıklamanın yeniden açmaması için 300 ms koruma vardır).

**Model ile çizim ayrıdır.** `145_header_core.ps1` saf mantıktır, ekrana dokunmaz ve sahte ayarlarla sınanır: `Get-LangShortCode` (düğmedeki kod), `Get-LangMenuModel` (liste satırları), `Get-LangButtonInfo` (düğme yazısı ve ipucu), `Get-LangChangePlan` (seçimin sonucu). `146_header_ui.ps1` yalnızca modeli çizer ve olayları bağlar; liste her açılışta modelden yeniden kurulur, böylece ayar ya da dil dosyası değişmişse güncel görünür.

**Dil değişim planı.** `Get-LangChangePlan` dört sonuçtan birini verir: `yok` (bilinmeyen dil; uyarı bildirimi), `ayni` (kayıtlı seçim zaten bu; hiçbir şey yapılmaz), `kaydet` (çalışan arayüz dili değişmiyor, örneğin Windows dili Türkçeyken *Otomatik* ↔ Türkçe; yalnızca ayar yazılır ve bildirim gösterilir, yeniden başlatma istenmez) ve `yeniden` (arayüz dili değişecek; Ayarlar > Dil kartıyla aynı onay ve yeniden başlatma akışı, `Confirm-LangRestart`). Süren bir işlem varsa (`Test-AsyncBusy`) değişiklik başlatılmaz; kullanıcıdan işlemin bitmesini beklemesi istenir. Dil çalışırken değiştirilmediği için açık pencerelerde yarım çevrilmiş metin kalmaz.

**Dar pencere.** Başlık çubuğunun sadeleşme basamakları (`Get-TitleLevel`): 0 her şey görünür, 1 slogan gizlenir, 2 sayfa adı kutusu daralır ve dil kodu yazısı kalkar (düğme küre ve oka iner), 3 durum etiketleri de gizlenir. Dil kapsülünün genişliği basamak hesabına katılır; emblem ve dil düğmesi hiçbir basamakta gizlenmez. Varsayılan 1380 × 840 pencerede (ve gerçek bilgisayarda %125 ölçekte) slogan dahil her şey görünür.

**Çeviri denetimi.** Dil adları, kısa kodlar ve onlardan kurulan metinler özel addır: `Add-LangNameOut`, bunları izleme açıkken eksik çeviri ve sızıntı sayımından çıkarır (yoksa her dilde `TR` ya da `Deutsch` sızıntı görünürdü). Yeni metinler (“Ana sayfa: durum panosuna dön”, “Arayüz dili: {0}”, “Dil tercihi kaydedildi: {0}” ve benzerleri) on iki dil dosyasına eklendi.

**Sınama.** `tests/t_header.ps1` kısa kod üretimini, satır modelini (sıra, işaret, kapsam yazısı, çeviri), değişim planının her kolunu, düğme yazısı ve ipucunu, yeniden başlatma akışını, ana sayfa tıklamasını (başka sayfalardan, ana ekranda en üste kaydırma, açık listeyi kapatma, hata dayanıklılığı), XAML yapısını (öğelerin sırası, pencere kromu istisnası, kapsülün köşe ve iç boşluğu, kaynak anahtarlarının tanımlı olması), olay bağlantılarını ve duman testi adımlarının bağlanmasını sınar (200 denetim). Gerçek pencerede `araclar/Duman-Ust.cmd` (`MM_DUMAN_KAPSAM=ust`, yaklaşık 1 dakika): emblemin başka sayfadan ana ekrana döndüğünü, dil listesinin açılıp kapandığını (satır sayısı, tek işaretli satır, çeviri sızıntısı taraması), dil kapsülünün kip kapsülüyle aynı yükseklikte olduğunu denetler; uygulamanın kendi çizdiği ve gerçek ekran görüntüsünü alır. Açılır liste pencere ağacında olmadığı için yalnızca gerçek ekran görüntüsünde görünür; görüntü, açılış animasyonu bitsin diye arayüz kısa aralıklarla boşaltıldıktan sonra alınır (animasyon saati arayüz iş parçacığıyla ilerler, uyku sırasında kare üretilmez).

**Sınır.** Duman testi dil seçmez (seçim uygulamayı yeniden başlatırdı); seçimin akışı birim testlerinde sahte onay penceresiyle sınanır. Gerçek görsel sınama Windows 11’de, %125 ölçekte, tek ekranda yapıldı; Windows 10 ve diğer ölçeklerde ayrıca denenmedi.
