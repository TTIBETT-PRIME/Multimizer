# Katkı rehberi

Katkılar açıktır. Aşağıdaki kurallar uygulamanın güvenlik sözünü korumak içindir.

## Kesin kurallar

1. **Güvenlik katmanlarını kapatan değişiklik kabul edilmez:** Windows Defender, Güvenlik Duvarı, UAC, Microsoft Store ve Windows Update kapatılamaz. Kayıt defteri koruma listesi (`Test-RegWriteBlocked`) genişletilebilir, daraltılamaz.
2. **Saldırı tekniği yoktur:** ARP zehirleme, deauth, başkasının cihazına müdahale gibi şeyler eklenmez. Ağ taraması yalnızca özel adres aralıklarında ve kullanıcı başlatınca çalışır. “Engelle” yalnızca bu bilgisayarın yerel güvenlik duvarı kuralıdır.
3. **Her değişiklik önizlenir, günlüğe yazılır ve geri alınabilir.** Yeni bir ayar eklerken kayıt defteri / hizmet işlemini katalog yapısıyla (`RegOp`, `SvcOp`, ...) tanımlayın; doğrudan yazmayın. Yeniden başlatma isteyen düzeltmeler kendiliğinden uygulanmaz.
4. **İzleme yok.** Kendiliğinden internete bağlanan kod eklenmez. İnternet kullanan her özellik `$script:NetFeatures` tablosuna girer ve Ayarlar’dan kapatılabilir olmalıdır.
5. **Kendi şifreleme / tünel kodu yazılmaz.** VPN için resmî istemciler ve Windows’un yerleşik özellikleri (disk şifreleme için BitLocker); şifreleme için sınanmış motorlar (ör. restic) kullanılır. Parola günlüğe, dosyaya ya da komut satırına yazılmaz. (Silme motorunun AES-256-CTR akışı yalnızca rastgele veri üretir; kullanıcı verisini şifrelemez, buna dayanan yeni bir şifreleme özelliği eklenmez.)
6. **Varsayılan kapalı:** Riskli ya da yan etkisi olan özellikler Ayarlar > İsteğe bağlı özellikler altında kapalı gelir.
7. **Geri döndürülemeyen işlem kendiliğinden yapılmaz.** Üzerine yazarak silme, bölüm ve disk silme gibi işlemler yalnızca elle yazdırılan hedef adıyla başlar, hedef işlem anında yeniden doğrulanır, Windows’un çalıştığı disk reddedilir. Bu kapıları gevşeten değişiklik kabul edilmez; yeni bir kapı ekliyorsanız kapatması gereken durumları da test edin.
8. **Dışarıdan kurulan şey izin listesinden gelir.** Hazırlık ve Dış araçlar yalnızca sabit listedeki winget kimliklerini kurar; liste dışı kimlik hiçbir yoldan kurulamaz. Listeye eklemek kod değişikliğidir ve gerekçesi (lisans, bakım durumu, neden Multimizer’ın içine kopyalanmadığı) açıklamada yazılır.
9. **Standart iddiası yok.** CIS, NIST, ISO 27001, BSI, NIS2, GDPR ve KVKK eşlemesi bilgilendirmedir; belge, ekran ya da ileti “uyumludur”, “sertifikalıdır” gibi bir şey söylemez.

## Kod kuralları

- **Windows PowerShell 5.1** ile çalışmalıdır: `?:`, `??`, `&&`, `ForEach-Object -Parallel` gibi PowerShell 7 sözdizimi yok.
- **Derlenmiş dosyalar yalnızca ASCII içerir.** `Multimizer.ps1` ve `Eklenti/` ASCII’dir; Türkçe harfler dizelerde `[char]0x00E7` gibi, XAML’de `&#x00E7;` olarak yazılır. (Not Defteri / Windows PowerShell 5.1 BOM’suz dosyayı ANSI okur; ASCII dışı karakter bozulur.) Yalnızca düz tırnak kullanın. Bu dosyaları elle düzenlemeyin; kaynağı `kaynak/` altındadır (aşağıda “Derleme”). `kaynak/mods` altındaki UTF-8 modüllerde Türkçe harf serbesttir, derleme çevirir; yalnızca dizelerin içinde ters eğik tırnak (’ ‘) kullanmayın.
- Dizi dönen işlevlerde sonucu önce bir değişkene atayıp sonra dolaşın; `@($null).Count` değeri 1’dir, tek elemanlı dizi `ConvertFrom-Json` çıktısında açılır. Aynı adlı parametre ve yerel değişken (`$P` / `$p`) PowerShell’de aynı değişkendir.
- **Antivirüs yanlış pozitifine karşı ana betikte şunlar bulunmaz:** gömülü base64 / gzip veri, `key=clear`, AES şifreleme döngüsü, `EmptyWorkingSet` ve ayrıcalık ayarlama (P/Invoke), üzerine yazarak silme, `Invoke-Expression`, `DownloadString`. Bu işler `Eklenti/` altına, veri ise `veri/` altına düz metin olarak konur; özetleri `Multimizer.ps1` içindeki `$script:PackHash` kaydındadır. Eklenti işlevleri `function global:Ad` ile tanımlanır ve `$script:` değişkeni kullanmaz. `tests/t_pack.ps1` bunu denetler.
- `veri/` ya da `Eklenti/` içindeki bir dosyayı değiştirince `pwsh araclar/Ozet-Guncelle.ps1 -Yaz` ile özet kaydını yenileyin. Yeni bir eklenti işi için `$script:ExtOf` tablosuna iş adını yazın ve arayüzde `Get-ExtProblem` ile kullanıcıya anlaşılır bir ileti verin.
- Arka plan işleri `Job_Ad($P)` işlevleridir ve arayüze dokunmaz; sonuçlarını hashtable olarak döner. Arayüz kodu `Start-Async` ile çağırır. Her iş ayrı bir çalışma alanında çalışır ve yalnızca **çekirdek** metnini (ve eşlenmiş eklentiyi) alır: bir `Job_*` işlevi ve çağırdığı her işlev çekirdekte olmalıdır, arayüz bölümündeki bir işlevi çağıramaz (`kaynak/check.py` bunu yakalar). Yeni bir eklenti işlevi için `$script:ExtOf` eşlemesi de gerekir.
- **C# 5.** Windows PowerShell 5.1’in `Add-Type` derleyicisi C# 5’tir: `$"..."`, `?.`, `nameof`, ifade gövdeli üyeler, `out var`, desen eşleme, `string?` kullanmayın. Kurtarma ve silme motorları (`kaynak/src/*.cs`) bu kurala göre yazılmıştır ve `check.py` Roslyn ile C# 5 dil sürümünde ayrıştırarak denetler.
- İşlev döndüren ve denetleyen kodda **aynı ad iki yerde tanımlanmaz**: derleme sonrası denetim, tabanda olmayan bir işlev ya da betik değişkeninin birden fazla tanımlanmasını hata sayar (sonraki tanım öncekinin üstüne yazar).
- Dizi döndüren işlevi `$x = f` ile çağırın (virgüllü dönüş `, $arr` ile sarılır). Değişken ve hashtable anahtar adları büyük küçük harfe duyarsızdır: `$J` ile `$j` aynıdır. .NET düzenli ifadelerinde `$` sondaki satır sonundan önce de eşleşir (`\z` kullanın), `\d` Unicode rakamlarını da eşler.
- **Türkçe “I” kuralı.** Windows PowerShell 5.1’de Türkçe ve Azerice kültürde büyük `I`, harf boyuna duyarsız düzenli ifadelerde `ı` olur: `'Input' -match '^[A-Za-z]+$'` yanlış çıkar. Doğrulayıcıda (kimlik, sürücü harfi, ad, anahtar) harf boyuna duyarsız `-match` ile `[A-Za-z]`, `[a-z]` ya da `[\x20-\x7E]` gibi aralık sınıfı kullanmayın; `-cmatch` / `-cnotmatch` / `-creplace` yazın ya da metni `ToLowerInvariant()` ile küçültüp `-cmatch` ile eşleyin. Kültürlü `ToUpper()` / `ToLower()` yerine `ToUpperInvariant()` / `ToLowerInvariant()` kullanın. `t_culture.ps1` bu kalıpları tarar ve bulursa kırmızıya döner. Betiğin başındaki `Set-MmCulture` çağrısını taşımayın ya da kaldırmayın.
- **Tablo anahtarları.** Türkçe sistemde `@{}` ve `[ordered]@{}` tabloları anahtar harf boyunu Türkçe kurala göre karşılaştırır (`@{ Info = 1 }['info']` boş döner; iş parçacığı kültürü bunu değiştirmez). Anahtarı tabloya yazarken de okurken de `ToLowerInvariant()` ile normalleştirin; dış metinden gelen, harf boyu değişebilen anahtarlar için `New-Object System.Collections.Hashtable ([System.StringComparer]::OrdinalIgnoreCase)` kullanın.
- **Yeni ayar** eklemek için `Add-RegTweak` kullanın (`'YOL|AD|TÜR|DEĞER'` satırları ya da `-Ops @(...)`); kimlik benzersiz, düzey 1-4, açıklama ne kaybettireceğini de söylemeli. Zevk ve kullanım tercihi olan ayarlar düzey 4’tür (hiçbir hazır profilde seçilmez).
- **Yeni işlem türü** (`T = 'Ad'`) `$script:MoreOps['Ad']` ve geri alması `$script:MoreUndo['Ad']` ile, yeni temizlik işlevi `$script:FuncOps['Ad']` ile kaydedilir. İşlem önizlemede (`$script:Preview`) yalnızca `Add-Plan` yazar; uygulamadan önce `Add-Journal` ile eski durumu kaydeder.
- Hashtable’da `Values`, `Keys`, `Count` adlı anahtarları dizinle okuyun (`$h['Values']`); nokta ile okununca anahtar yoksa hashtable’ın kendi özelliği döner.
- Çalışan işlem yolu okumak (`Get-Process ... .Path`) pahalıdır; arayüz zamanlayıcısında değil, canlı izleyici iş parçacığında (`Job_Monitor`) yapılır.
- **Görünüm eksenleri birbirinden bağımsızdır:** tema (renkler), yerleşim (yoğunluk), tasarım (kabuğun yapısı), ana ekran biçimi (Pano | Klasik) ve saydamlık. Yeni bir tema `Themes` tablosuna 34 fırça anahtarıyla (ayrıca `ThemeGrads` üç durağı ve `ThemeInfo` açıklaması) eklenir; renk çiftleri `tests/t_theme.ps1` kurallarından geçmelidir (WCAG oranları, işlem günlüğü PLAN renginin hata / başarı / uyarıdan en az 60° ton farkı, simge çipi karşıtlığı). Parça ve eylem kartı renkleri tema anahtarlarından türer; yeni tema ek renk işi gerektirmez.
- **Açılır listeler** `New-Choice` ve `Set-ComboChoices` ile kurulur: öğeler hashtable’dir (`Key`, `Name`, `C1`..`C4`), şablonlar `{Binding [Name]}` ile bağlanır; renkler tema fırçalarından okunur. Testlerde `New-FakeCombo` kullanılır.
- **Yutulan hatalar:** ortamsal bir hatayı bilerek geçiştirmek için `catch { }` yeterlidir; ama beklenmeyen bir hata olasılığı varsa `Baslat.bat -DebugLog` ile çalıştırıp `Kayitlar\ayrinti-GÜN.txt` içindeki `[kod?]` işaretli kayıtlara (boş değere yöntem çağrısı, tanımsız komut, bağlanamayan parametre) bakın ve nedenini düzeltin. Duman testi bu özeti raporun sonuna yazar.
- Her kullanıcı metni Türkçedir. Metinler sade ve doğrudan olsun; teknik terimi ilk geçtiği yerde açıklayın.

## Derleme

`Multimizer.ps1`, `Eklenti/Kurtarma.ps1` ve `Eklenti/DiskSilme.ps1` kaynaktan üretilir; üretilmiş dosyayı elle değiştirmek bir sonraki derlemede kaybolur. Python 3.9+ gerekir.

```
python3 kaynak/build.py     # Multimizer.ps1 ve Eklenti/ dosyalarını yerinde yeniler (özet kaydı dahil)
python3 kaynak/check.py     # derleme sonrası denetimler (PowerShell 7 gerekir)
python3 kaynak/tools/gen_standartlar.py   # STANDARTLAR.md dosyasını yeniler
```

- Yeni kod için `kaynak/mods/` altına UTF-8 bir modül yazın ve `kaynak/patches/` altındaki bir yamayla çekirdeğe (`b.add_core`) ya da arayüze (`b.add_ui`) bağlayın; mevcut kodu değiştirmek için `b.rep` gibi yardımcılar beklediği metnin kaç kez geçtiğini denetler, tutmazsa derleme durur.
- Güvenlik ayarlarının ya da sağlık bulgularının standart eşlemesi (`Get-PostureCoverage` ve tablolar) değişince `gen_standartlar.py` ile STANDARTLAR.md yenilenir; yenilenmediyse `check.py` hata verir.
- `check.py` ayrıca belgelerin sürüm numarasını (CHANGELOG, OKUBENI, MIMARI) ve belgelerde adı geçen test takımlarının varlığını denetler.
- Açılış ekranı (`Acilis.ps1`) `kaynak/src/Acilis.tpl.ps1` ve `kaynak/src/baslatma_dil.tsv` (13 dilli başlatıcı metinleri) dosyalarından üretilir; üretilmiş dosyayı elle değiştirmeyin. Dosya yalnızca ASCII içerir, metinler `\uXXXX` olarak gömülür.
- Arayüz metni atamaları (`.Text`, `.Content`, `.ToolTip`, `.Header`, `.Title`) derleyici tarafından `Tr` ile sarılır; bir metnin çevrilmemesi gerekiyorsa satırın sonuna `# Tr:yok` yazın. Değişken parçalı iletiler için `Format-Tr 'Silindi: {0} dosya' $n` kullanın; cümleyi parçalara bölmeyin.
- Sürüm numarası `$script:AppVersion` içindedir (kaynakta `kaynak/mods/` altında); belgeler onunla aynı olmalıdır.
- CI, `kaynak/` ağacından yeniden ürettiği dosyaların depodakilerle **bayt bayt aynı** olduğunu denetler. Kaynağı değiştirip derlemeyi çalıştırmadan gönderirseniz CI kırmızı olur.

## Test

```
MM_BUILD=./Multimizer.ps1 pwsh -NoProfile -File tests/t_files.ps1      # tek takım
for f in tests/t_*.ps1; do MM_BUILD=./Multimizer.ps1 pwsh -NoProfile -File "$f" || exit 1; done
```

- `tests/lib.ps1` derlenmiş dosyadan (ve `Eklenti/` içinden) işlevleri AST ile çıkarıp (`Import-Fn`, `Import-Var`) sahte bağımlılıklarla sınar; WPF gerekmez. `Assert-Eq` büyük küçük harfe duyarlıdır; PowerShell’in `-eq` ve `-match` işleçleri ise duyarsızdır.
- **Kurtarma ve silme testleri** sentetik imajlarla çalışır: `tests/gen_images.py` NTFS, FAT12/16/32 ve exFAT imajlarını (MBR ve GPT sarmalı dahil) kendisi üretir. Üçüncü taraf bir imajı depoya koymayın; yeni bir dosya sistemi durumu için üreticiye bir senaryo ekleyin. Silme motorunun yazan yolları yalnızca geçici imajda ve sahte depolama komutlarıyla sınanır, gerçek diske yazan test eklenmez.
- **Testin kendisini sınayın.** Yeni bir kapı ya da doğrulama yazdıysanız, kodu kasıtlı bozduğunuzda (kapıyı kaldırın, karşılaştırmayı tersine çevirin) testin kırmızıya döndüğünü bir kez görün; kırmızıya dönmüyorsa test hiçbir şey sınamıyordur.
- `t_wiring.ps1` ana ekran eylem kartlarının, komut hedeflerinin ve arama sözcüklerinin var olan sayfa ve sekmelere bağlandığını; `t_exttools.ps1` dış araç kataloğunu ve izin listesini; `t_update.ps1` güncelleme denetiminin tüm kapılarını; `t_selftest.ps1` kendi kendine sınama adımlarını sınar. Yeni bir sayfa ya da sekme ekliyorsanız bunlara satır ekleyin.
- Yeni bir çekirdek işlev ekliyorsanız, hem olumlu hem **reddedilmesi gereken** durumları (sistem yolu, geçersiz sürücü, sınır dışı gün sayısı ...) test edin.
- Arayüz değişikliğinde sayfa tanımındaki `x:Name` adlarının ve `$ui.Ad` kullanımlarının eşleştiğini kontrol eden testlere (`t_ui_files.ps1`) satır ekleyin.
- `t_i18n.ps1` dil altyapısını sınar: dil dosyalarının üst bilgisi ve biçimi, yer tutucu eşliği, yinelenen kimlik ve boş çeviri olmaması, çözümleme sırası (seçili dil → İngilizce → Türkçe), şablonlar, sağdan sola yazı, yüzde yazımı ve kapsam. `t_acilis.ps1` başlatıcı sözleşmesini sınar: `Baslat.bat` ile `Acilis.ps1` akışı, 13 dilli metin tablosu, aşama anahtarları ve Denetçi’nin yeniden başlatma kuralı.
- `t_culture.ps1` kültür korumasını (`Set-MmCulture`, `Get-OemEncoding`, çalışma alanı ve `AsyncWrapper` yolu) ve harf boyuna duyarsız işleçlerdeki `I` içeren aralık sınıflarını sınar. Linux’ta Türkçe kültür yoktur; korumanın kendisi `-Force` ve yazılabilir bir kültürle denenir, asıl sınama Windows’ta `Baslat.bat -OzTest` içindeki “Türkçe kültür koruması” adımıdır. Testler PowerShell 7 ile çalışır; `t_wipe_raw.ps1` gibi bazı dosyalar PowerShell 7 sözdizimi içerir ve Windows PowerShell 5.1 ile ayrıştırılamaz (CI’nin 5.1 işi yalnızca uygulama dosyalarını ayrıştırır).
- `Baslat.bat` ASCII ve CRLF olmak zorundadır (LF satır sonlarında `goto` etiketleri bozulur); `tests/t_bat.ps1` bunu ve etiketleri denetler.
- Windows’ta `Baslat.bat -OzTest` kendi kendine sınamayı çalıştırır; yeni bir güvenlik kuralı için `Test-Step` ekleyin.
- **Statik analiz.** Kural kümesi depo kökündeki `PSScriptAnalyzerSettings.psd1` dosyasındadır: sözdizimi Windows PowerShell 5.1’e göre denetlenir, bilerek kullanılan kalıplar (boş `catch`, `Write-Host`, ad kuralları) gerekçesiyle dışarıda bırakılmıştır. Yerelde `Install-Module PSScriptAnalyzer, InjectionHunter -Scope CurrentUser` kurup `pwsh -NoProfile -File kaynak/tools/kod_analizi.ps1` çalıştırın; InjectionHunter, Microsoft’un kod enjeksiyonu kurallarıdır. CI’deki `kod-analizi` işi aynı betiği çalıştırır, özeti iş sayfasına yazar ve bulguları GitHub’ın Code scanning sekmesine yükler. Error düzeyinde bir bulgu işi başarısız sayar; Warning’ler raporda kalır. Bir kuralı dışarıda bırakırsanız gerekçesini ayar dosyasına yazın.
- Gerçek pencerede `araclar\Duman-*.cmd` kapsamları (`MM_DUMAN_KAPSAM=tam|tepsi|gorunum|tasarim|saydam|dil`) çalışır; yeni bir tema, tasarım, hazır görünüm ya da saydamlık adımı ekliyorsanız ilgili `Smoke*` listesine de ekleyin. Duman testini her seferinde yalnızca bir kopya olarak başlatın (iki kopya aynı ayar dosyasını paylaşır). Test, gerçek ayar dosyasının geçici kopyasında koşar ve varsayılan olarak normal çizimle başlar (kopyadaki kalıcı güvenli çizim kapatılır; `MM_DUMAN_GUVENLI=1` güvenli kipte koşturur). Doğrudan uygulama yapan bir adım (`Select-Layout` gibi) gerçek akışlardaki gibi `Save-Settings` ile kaydetmelidir: her arka plan işi bitince ayarlar dosyadan yeniden okunur ve kaydedilmemiş değişiklik kaybolur.
- `t_debuglog.ps1` ayrıntılı hata günlüğünü sınar: kapalıyken işlem yapılmaması, kayıt alanları, yinelenenlerin birleştirilmesi, dakika ve boyut sınırları, program hatası işareti, iş çalışma alanı satır çevirisi, betikteki bağlantılar.
- `t_perf.ps1` güç planları (sahte `powercfg`), oyun algılama, sıkıştırma (sahte `compact`), akıllı temizlik, otomasyon kuralları ve genişletilmiş kataloğu sınar; yeni ayarların güvenlik kapısından geçtiğini ve Defender / UAC / SmartScreen / Windows Update / Mağaza’yı kapatmadığını da denetler.

## Çeviri katkısı

Çeviriler `veri/dil/<kod>.lang` dosyalarındadır (UTF-8, düz metin; biçim README’deki “Dil desteği” bölümünde). Kaynak dil Türkçedir ve Türkçe metin kimliktir.

- **Çeviriyi düzeltmek:** satırın sağ tarafını (sekmeden sonrasını) değiştirin; sol taraftaki kimliği değiştirmeyin. Kimlik, uygulamadaki Türkçe metinle birebir aynı olmak zorundadır.
- **Yeni dil:** `veri/dil/<kod>.lang` oluşturun (`#name`, `#native`, `#tag`, `#rtl`, `#match`, `#coverage` üst bilgisi; kod küçük harfli `xx` ya da `xx-yyyy`). Sonra `python3 kaynak/build.py` ile özet kaydını yenileyin ve `tests/t_i18n.ps1` çalıştırın. Sağdan sola diller için `#rtl: 1` yazın.
- **Yer tutucular:** kimlikte geçen `{0}`, `{1}` ... çeviride de aynı kümede bulunmalıdır; sırası değişebilir. Kaçışlar: `\t` sekme, `\n` satır sonu, `\\` ters bölü.
- **Eksikleri bulmak:** uygulamayı `MM_DIL_IZLE=1` ile açıp sayfaları gezin; istenen ama çevirisi olmayan metinler `%TEMP%\Multimizer-dil-eksik.txt` dosyasına yazılır. `araclar\Duman-Dil.cmd` bunu her sayfa ve dil için kendisi yapar, ekran görüntüsü alır ve ekrana sığmayan metinleri (KESIK) de listeler.
- **Kapsam dürüst yazılır:** çeviri ekledikçe `#coverage` değerini (çevrilmiş kimliklerin yüzdesi) güncelleyin; Ayarlar’daki dil kartı bu değeri olduğu gibi gösterir. Makine çevirisi ya da gözden geçirilmemiş metni “tam” diye işaretlemeyin.
- Terimler tutarlı olmalı: aynı Türkçe terim aynı dilde hep aynı karşılıkla çevrilir (örn. “önizleme” → *preview* / *Vorschau* / *预览* / *プレビュー* / *معاينة*).

## Araç kataloğu katkısı

Ücretsiz araçlar listesi (`$script:FossTools`, `$script:FossToolsMore`), lisans tablosu (`$script:FossMeta`) ve açık kaynak alternatif kuralları (`$script:AltRules`) `kaynak/mods/150_kit_core.ps1` içindedir.

- **Yeni araç:** winget kimliğini, görünen adı, kategoriyi ve tek cümlelik açıklamayı ekleyin; aynı kimlik için `FossMeta` satırı (kaynak kodu açık mı, lisansın kısa adı) zorunludur. Lisansı winget bildiriminden ya da projenin deposundan alın, tahmin etmeyin.
- **Kimliği doğrulayın:** `winget show --id <Kimlik> --exact --source winget` çıkış kodu 0 olmalıdır. Sürüm 10.1.0’daki bütün kimlikler bu komutla doğrulanmıştır.
- **Alternatif kuralı:** `Rx` kurulu programın görünen adını eşler (dar tutun; yanlış eşleşme yanlış öneri demektir), `Id` önerilen aracın winget kimliğidir ve `FossMeta` içinde açık kaynak olarak kayıtlı olmalıdır, `Why` tek cümlelik somut gerekçedir. Karşılaştırmalı reklam dili kullanmayın.
- Kaynak kodu yayımlanmayan araçlar listede kalabilir ama `Open = $false` ile işaretlenir; “yalnızca açık kaynak” süzgeci bunları gizler.
- `tests/t_kit.ps1` her aracın lisans kaydını, kimlik biçimini ve kuralların açık kaynak hedefe gittiğini denetler.

## Sürüm çıkarma

1. `kaynak/build.py` içindeki `VERSION` ile `kaynak/patches/p00_version.py` içindeki sürümü yükseltin, `CHANGELOG.md` başına sürüm bölümünü yazın.
2. `python3 kaynak/build.py`, testler ve `python3 kaynak/check.py` temiz olmalı; üretilen `Multimizer.ps1`, `Eklenti/` ve `veri/` dosyalarını işleyin.
3. `git tag v<sürüm>` ve `git push --tags`. `.github/workflows/release.yml` yeniden üretimi doğrular, paketi ve `SHA256SUMS.txt` dosyasını üretir, ikisi için imzalı kaynak kanıtı oluşturur ve sürümü yayımlar.
4. Sürüm sayfasındaki doğrulama komutunu kendiniz bir kez çalıştırın (`gh attestation verify ...`). Bu iş akışı ilk etiketle birlikte ilk kez çalışacaktır; ilk çalışmada çıktısını satır satır inceleyin.

## Hata bildirimi

Windows sürümü (`winver`), Multimizer sürümü ve `C:\ProgramData\Multimizer\Kayitlar` içindeki ilgili `hata-*.txt` dosyasının içeriğini ekleyin. Kişisel bilgi (kullanıcı adı, Wi-Fi adı, MAC adresi) varsa silin.
