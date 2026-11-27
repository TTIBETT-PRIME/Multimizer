. "$PSScriptRoot/lib.ps1"
# Dil desteği (mods\140_i18n_core.ps1, 141_i18n_ui.ps1, patches\p52_i18n.py ve build.py dil sarma adımı):
# dil dosyası ayrıştırma, Tr (birebir, boşluk, şablon, çok satırlı, yedek dil), XAML ve günlük çevirisi, dil seçimi, Ayarlar kartı akışı,
# bağlantı noktaları (kaynak denetimi) ve gönderilen dil dosyalarının tutarlılığı.
Import-Fn 'Get-LangUnescaped', 'Add-LangTemplate', 'Read-LangPack', 'Read-LangHeader', 'Get-LangList', 'Find-LangForCulture', 'Get-SystemLangCode',
    'Resolve-LangCode', 'Import-LangPackFile', 'Set-LangActive', 'Initialize-Lang', 'Enable-LangTrack', 'Find-LangIn', 'Format-LangTemplate', 'Find-LangText', 'Find-LangTag', 'Find-LangJoined', 'Find-LangDirect', 'Find-LangFolded', 'Get-LangPunct', 'Convert-LangTrLower', 'Convert-LangTrUpperFirst', 'Convert-LangUpper',
    'Add-LangMiss', 'Tr', 'Format-Tr', 'ConvertTo-XamlAttr', 'Convert-XamlText', 'Convert-LogLineText', 'Save-LangMiss',
    'Get-LangChoiceName', 'Get-LangEntry', 'Initialize-StLang', 'Load-StLang', 'Update-StLangNote', 'Get-RestartArgs', 'Invoke-StLangApply', 'Complete-LangChange', 'Confirm-LangRestart', 'Test-LangLeak',
    'Set-ComboChoices', 'Select-ComboKey', 'Get-ComboKey', 'New-Choice', 'ConvertTo-TrUpper',
    'Get-LangPercentStyle', 'Convert-LangPercent', 'Format-Percent', 'Convert-LangBidi'
Import-Var 'LangPctRx', 'LangBidiRx'
Import-Fn 'Get-LangLeakPattern', 'Test-LangLeakText', 'Format-LangSnippet', 'Get-LangVisible', 'Get-LangClipVerdict'
. "$PSScriptRoot/uifake.ps1"
$src = [System.IO.File]::ReadAllText($script:TestPath)

# durum değişkenleri
$script:LangOn = $false; $script:LangCode = 'tr'; $script:LangTag = 'tr-TR'; $script:LangRtl = $false; $script:LangName = ''
$script:LangPrimary = $null; $script:LangFallback = $null; $script:LangList = $null; $script:LangTrack = $false; $script:LangMiss = $null; $script:LangSeen = $null; $script:LangPctStyle = 0; $script:LangOut = $null
$script:LangKeyLen = 5
$script:LangPrefixRx = New-Object System.Text.RegularExpressions.Regex(('^(\s*(?:>>>|' + [char]0x2192 + ')\s+)(.+)$'), [System.Text.RegularExpressions.RegexOptions]::Singleline)
$script:LangBracketRx = New-Object System.Text.RegularExpressions.Regex('^(.*?)\s{2}\[(.+)\]\s*$', [System.Text.RegularExpressions.RegexOptions]::Singleline)
$script:LangCountRx = New-Object System.Text.RegularExpressions.Regex('^(.+?) \(([^()]+)\)$', [System.Text.RegularExpressions.RegexOptions]::Singleline)
$script:LangUpperRx = New-Object System.Text.RegularExpressions.Regex('\p{Lu}{2}')
$script:LangLowerRx = New-Object System.Text.RegularExpressions.Regex('\p{Ll}')
$script:LangUpperCulture = $null
$script:LangFull = $true
$script:LangLetterRx = New-Object System.Text.RegularExpressions.Regex('\p{L}{2}')
$script:LangLogRx = New-Object System.Text.RegularExpressions.Regex('^(\d\d:\d\d:\d\d\s+\S+\s+)(.+)$', [System.Text.RegularExpressions.RegexOptions]::Singleline)
$script:LangXamlRx = New-Object System.Text.RegularExpressions.Regex('(\b(?:Text|Content|ToolTip|Header|Title|Watermark)=")([^"]*)(")')
$script:Settings = @{ Language = 'auto' }
$script:StLoading = $false
$Dil = ''
$env:MM_DIL = ''; $env:MM_DIL_IZLE = ''

# ---- geçici dil klasörleri (uygulama ve kullanıcı)
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('mm-dil-' + [guid]::NewGuid().ToString('N'))
$appDil = Join-Path $tmp 'app'; $usrDil = Join-Path $tmp 'usr'
[void](New-Item -ItemType Directory -Path $appDil -Force); [void](New-Item -ItemType Directory -Path $usrDil -Force)
function Get-LangFolders { return @($script:T_App, $script:T_Usr) }
$script:T_App = $appDil; $script:T_Usr = $usrDil
function Write-Pack([string]$Dir, [string]$Code, [string]$Body) { [System.IO.File]::WriteAllText((Join-Path $Dir ($Code + '.lang')), $Body, (New-Object System.Text.UTF8Encoding($false))) }

Write-Pack $appDil 'en' @"
#name: English
#native: English
#tag: en-US
#rtl: 0
#match: en
#coverage: 100
Kapat`tClose
Tamam`tOK
Hata: {0}`tError: {0}
Silindi: {0} dosya`t{0} files deleted
{0} dosya silindi, {1} atlandı`t{1} skipped, {0} deleted
Disk dolu`tDisk full
Tamam & Kapat`tOK & Close
Satır bir\nSatır iki`tLine one\nLine two
Ters {0} ve {1} sırası`tOrder {1} then {0}
Yol (C:) [x] {0}.`tPath (C:) [x] {0}.
{0}: {1}`tbad generic
{0}{1}`tbad adjacent
Ters\\Eğik\tSekme`tBack\\slash\ttab
Düzeltilebilir sorunlar`tFixable issues
Disk sağlıklı:`tDisk health:
Teslim İyileştirme önbelleği`tDelivery Optimization cache
Mağaza uygulamaları taranıyor`tScanning Store apps
Hazırlık denetleniyor`tChecking readiness
Hız için özellik kapatmaya gerek yok.`tNo need to turn features off for speed.
Bellek, işlemci ve disk yeterli; özellik kapatmaya gerek yok`tMemory, processor and disk are sufficient; no need to turn features off
Bu yüzden yalnızca gizlilik ve bakım ayarları önerilir.`tTherefore only privacy and maintenance settings are recommended.
Etkili olması için yeniden başlatma gerekir.`tA restart is required to take effect.
Bağlantı kesilir. Yeniden başlatın.`tThe connection drops. Restart.
Klasik`tClassic
Pencere düz renkli çizilir. Varsayılan.`tThe window is drawn in a solid color. Default.
Yedek ve kurtarma`tBackup and recovery
Hizmet Yöneticisi`tService Manager
Ana ekran`tHome
otomatik`tautomatic
Bellek 4 GB ya da daha az`tMemory 4 GB or less
Sistem diski mekanik (HDD)`tSystem disk is mechanical (HDD)
salt okunur`tread-only
Sıfırlama sonrası`tAfter reset
"@
Write-Pack $appDil 'de' @"
#name: German
#native: Deutsch
#tag: de-DE
#match: de
#coverage: 60
Kapat`tSchließen
Tamam`tOK
Silindi: {0} dosya`t{0} Dateien gelöscht
"@
Write-Pack $appDil 'ar' @"
#name: Arabic
#native: العربية
#tag: ar-SA
#rtl: 1
#match: ar
#coverage: 30
Kapat`tإغلاق
"@
Write-Pack $appDil 'zh' @"
#name: Chinese (Simplified)
#native: 简体中文
#tag: zh-CN
#match: zh,zh-cn,zh-sg,zh-hans
#coverage: 40
Kapat`t关闭
"@
Write-Pack $appDil 'zh-hant' @"
#name: Chinese (Traditional)
#native: 繁體中文
#tag: zh-TW
#match: zh-tw,zh-hk,zh-mo,zh-hant
#coverage: 40
Kapat`t關閉
"@
Write-Pack $appDil 'pt' "#name: Portuguese`n#native: Português`n#tag: pt-BR`n#match: pt`n#coverage: 50`nKapat`tFechar`n"
# bozuk dosya adları yok sayılır
Write-Pack $appDil 'Bozuk Ad' "#name: x`nKapat`tx`n"
Write-Pack $appDil 'tr' "#name: Turkish`nKapat`tTR`n"

# =====================================================================
#  1) kaçış dizileri ve dosya ayrıştırma
# =====================================================================
Assert-Eq (Get-LangUnescaped 'a\tb') ("a`tb") 'kaçış: sekme'
Assert-Eq (Get-LangUnescaped 'a\nb') ("a`nb") 'kaçış: satır sonu'
Assert-Eq (Get-LangUnescaped 'a\rb') ("a`rb") 'kaçış: satır başı'
Assert-Eq (Get-LangUnescaped 'a\\b') 'a\b' 'kaçış: ters eğik çizgi'
Assert-Eq (Get-LangUnescaped 'C:\yol') 'C:\yol' 'kaçış: tanınmayan dizi olduğu gibi kalır'
Assert-Eq (Get-LangUnescaped 'sonda\') 'sonda\' 'kaçış: sondaki tek ters eğik çizgi'
Assert-Eq (Get-LangUnescaped 'düz metin') 'düz metin' 'kaçış: kaçışsız metin'

$p = Read-LangPack ([System.IO.File]::ReadAllText((Join-Path $appDil 'en.lang'), [System.Text.Encoding]::UTF8)) 'en'
Assert-Eq $p.Meta['native'] 'English' 'paket: üst bilgi native'
Assert-Eq $p.Meta['coverage'] '100' 'paket: üst bilgi coverage'
Assert-Eq $p.Map['Kapat'] 'Close' 'paket: birebir kayıt'
Assert-Eq $p.Map["Satır bir`nSatır iki"] "Line one`nLine two" 'paket: kaçışlı çok satırlı kayıt'
Assert-Eq $p.Map["Ters\Eğik`tSekme"] "Back\slash`ttab" 'paket: kaçışlı kimlik ve çeviri'
Assert-True (-not $p.Map.ContainsKey('Hata: {0}')) 'paket: şablon birebir tabloya girmez'
Assert-True ($p.NTpl -ge 4) 'paket: şablonlar dizinlendi'
Assert-True ($p.Tpl.ContainsKey('{0}: {') -eq $false) 'paket: kötü şablon dizine girmez (anahtar)'
$allTpl = 0; foreach ($k in @($p.Tpl.Keys)) { $allTpl += $p.Tpl[$k].Count }
Assert-Eq $allTpl $p.NTpl 'paket: şablon sayacı dizinle tutarlı'
Assert-True (-not (@($p.Tpl.Values | ForEach-Object { $_ } | Where-Object { $_.Id -eq '{0}: {1}' }).Count -gt 0)) 'paket: yalnızca yer tutuculardan oluşan şablon reddedilir'
Assert-True (-not (@($p.Tpl.Values | ForEach-Object { $_ } | Where-Object { $_.Id -eq '{0}{1}' }).Count -gt 0)) 'paket: bitişik yer tutucular reddedilir'
$h = Read-LangHeader (Join-Path $appDil 'de.lang')
Assert-Eq $h['native'] 'Deutsch' 'üst bilgi okuyucu: native'
Assert-Eq $h['match'] 'de' 'üst bilgi okuyucu: match'
Assert-Eq (Read-LangHeader (Join-Path $appDil 'yok.lang')).Count 0 'üst bilgi okuyucu: olmayan dosya'

# CRLF dosya ve BOM
$crlf = "#native: Test`r`n#name: Test`r`nKapat`tX`r`nTamam`tY`r`n"
$pc = Read-LangPack $crlf 'xx'
Assert-Eq $pc.Map['Kapat'] 'X' 'paket: CRLF satır sonu'
Assert-Eq $pc.Map['Tamam'] 'Y' 'paket: CRLF ikinci satır'
$pe = Read-LangPack "Kapat`t`nTamam`tY`n`tYok`n#yorum`nSekmesiz satir`n" 'xx'
Assert-Eq $pe.N 1 'paket: boş çeviri, boş kimlik, yorum ve sekmesiz satır atlanır'

# =====================================================================
#  2) dil listesi, kültür eşleme, çözümleme
# =====================================================================
$list = @(Get-LangList $true)
Assert-Eq $list[0].Code 'tr' 'liste: Türkçe ilk sırada'
Assert-Eq $list[0].Native ('T' + [char]0x00FC + 'rk' + [char]0x00E7 + 'e') 'liste: Türkçe adı'
$codes = @($list | ForEach-Object { $_.Code })
Assert-True (($codes -contains 'en') -and ($codes -contains 'de') -and ($codes -contains 'ar') -and ($codes -contains 'zh') -and ($codes -contains 'zh-hant') -and ($codes -contains 'pt')) 'liste: dil dosyaları bulundu'
Assert-True (-not ($codes -contains 'bozuk ad') -and -not ($codes -contains 'Bozuk Ad')) 'liste: geçersiz dosya adı yok sayılır'
Assert-Eq @($codes | Where-Object { $_ -eq 'tr' }).Count 1 'liste: tr.lang dosyası Türkçe kaydı yerine geçmez'
Assert-Eq (@($list | Where-Object { $_.Code -eq 'ar' })[0].Rtl) $true 'liste: Arapça sağdan sola'
Assert-Eq (@($list | Where-Object { $_.Code -eq 'de' })[0].Rtl) $false 'liste: Almanca soldan sağa'
Assert-Eq (@($list | Where-Object { $_.Code -eq 'de' })[0].Coverage) 60 'liste: kapsam yüzdesi'
Assert-Eq (@($list | Where-Object { $_.Code -eq 'zh' })[0].Native) '简体中文' 'liste: yerel ad'
Assert-Eq (@($list | Where-Object { $_.Code -eq 'de' })[0].User) $false 'liste: uygulama dosyası kullanıcı dosyası değil'
$sorted = @($codes | Select-Object -Skip 1)
Assert-Eq ($sorted -join ',') (@($sorted | Sort-Object) -join ',') 'liste: Türkçeden sonra koda göre sıralı'

Assert-Eq (Find-LangForCulture 'de-DE') 'de' 'kültür: de-DE'
Assert-Eq (Find-LangForCulture 'de') 'de' 'kültür: de'
Assert-Eq (Find-LangForCulture 'DE-at') 'de' 'kültür: büyük/küçük harf önemsiz'
Assert-Eq (Find-LangForCulture 'en-GB') 'en' 'kültür: en-GB'
Assert-Eq (Find-LangForCulture 'zh-CN') 'zh' 'kültür: zh-CN basitleştirilmiş'
Assert-Eq (Find-LangForCulture 'zh-Hans-CN') 'zh' 'kültür: zh-Hans-CN'
Assert-Eq (Find-LangForCulture 'zh-TW') 'zh-hant' 'kültür: zh-TW geleneksel'
Assert-Eq (Find-LangForCulture 'zh-HK') 'zh-hant' 'kültür: zh-HK geleneksel'
Assert-Eq (Find-LangForCulture 'zh-Hant-TW') 'zh-hant' 'kültür: zh-Hant-TW (daha uzun önek kazanır)'
Assert-Eq (Find-LangForCulture 'ar-EG') 'ar' 'kültür: ar-EG'
Assert-Eq (Find-LangForCulture 'pt-BR') 'pt' 'kültür: pt-BR'
Assert-Eq (Find-LangForCulture 'tr-TR') 'tr' 'kültür: tr-TR kaynak dil'
Assert-Eq (Find-LangForCulture 'sv-SE') '' 'kültür: desteklenmeyen dil boş döner'
Assert-Eq (Find-LangForCulture '') '' 'kültür: boş ad'
Assert-Eq (Find-LangForCulture 'dex') '' 'kültür: önek sınırı (dex de değildir)'

Assert-Eq (Resolve-LangCode 'de') 'de' 'çözümleme: bilinen kod'
Assert-Eq (Resolve-LangCode ' DE ') 'de' 'çözümleme: boşluk ve büyük harf'
Assert-Eq (Resolve-LangCode 'tr') 'tr' 'çözümleme: Türkçe'
Assert-Eq (Resolve-LangCode 'de-AT') 'de' 'çözümleme: bölgeli kod'
Assert-Eq (Resolve-LangCode 'sv') 'en' 'çözümleme: bilinmeyen kod İngilizceye düşer'
Assert-Eq (Resolve-LangCode 'zh-tw') 'zh-hant' 'çözümleme: zh-tw'

# =====================================================================
#  3) Tr
# =====================================================================
Assert-Eq (Tr 'Kapat') 'Kapat' 'Tr: Türkçe seçiliyken metin aynen döner'
Assert-Eq (Tr 5) 5 'Tr: dize olmayan değer aynen döner'
Assert-True ($null -eq (Tr $null)) 'Tr: $null aynen döner'
Set-LangActive 'de'
Assert-True ($script:LangOn -eq $true -and $script:LangCode -eq 'de' -and $script:LangTag -eq 'de-DE' -and $script:LangRtl -eq $false) 'etkinleştirme: Almanca durumu'
Assert-True ($null -ne $script:LangFallback) 'etkinleştirme: İngilizce yedek yüklendi'
Assert-Eq (Tr 'Kapat') 'Schließen' 'Tr: birebir (Almanca)'
Assert-Eq (Tr '  Kapat ') '  Schließen ' 'Tr: baştaki ve sondaki boşluk korunur'
Assert-Eq (Tr "Kapat`r`n") "Schließen`r`n" 'Tr: sondaki satır sonu korunur'
Assert-Eq (Tr 'Silindi: 5 dosya') '5 Dateien gelöscht' 'Tr: şablon (Almanca)'
Assert-Eq (Tr 'Silindi:  dosya') ' Dateien gelöscht' 'Tr: şablon boş parça'
Assert-Eq (Tr 'Hata: Disk dolu') 'Error: Disk full' 'Tr: Almancada yok, İngilizce yedek şablon + yakalanan parça çevrilir'
Assert-Eq (Tr '12 dosya silindi, 3 atlandı') '3 skipped, 12 deleted' 'Tr: şablonda yer tutucu sırası değişir'
Assert-Eq (Tr 'Ters A ve B sırası') 'Order B then A' 'Tr: ters sıralı yer tutucular'
Assert-Eq (Tr 'Yol (C:) [x] D.') 'Path (C:) [x] D.' 'Tr: düzenli ifade özel karakterli şablon'
Assert-Eq (Tr 'Yol (C:) [x] D') 'Yol (C:) [x] D' 'Tr: şablonun sonu eşleşmezse metin aynen kalır'
Assert-Eq (Tr 'Tamam & Kapat') 'OK & Close' 'Tr: İngilizce yedek, birebir (&)'
Assert-Eq (Tr "Kapat`nTamam") "Schließen`nOK" 'Tr: çok satırlı metin satır satır çevrilir'
Assert-Eq (Tr "Kapat`r`nTamam") "Schließen`r`nOK" 'Tr: çok satırlı (CRLF)'
Assert-Eq (Tr "Kapat`nBilinmeyen satır") "Schließen`nBilinmeyen satır" 'Tr: çok satırlıda çevrilemeyen satır korunur'
Assert-Eq (Tr 'Kapat  ·  Tamam') 'Schließen  ·  OK' 'Tr: "parça  ·  parça" biçimli birleşik metinde her parça ayrı çevrilir'
Assert-Eq (Tr 'Kapat · Tamam') 'Schließen · OK' 'Tr: tek boşluklu orta nokta ayırıcısı da çözülür'
Assert-Eq (Tr 'Kapat  ·  Bilinmeyen parça') 'Schließen  ·  Bilinmeyen parça' 'Tr: birleşik metinde çevrilemeyen parça korunur'
Assert-Eq (Tr 'Bilinmeyen  ·  Bilinmeyen parça') 'Bilinmeyen  ·  Bilinmeyen parça' 'Tr: birleşik metinde hiçbir parça çevrilemezse metin aynen kalır'
Assert-Eq (Tr "Satır bir`nSatır iki") "Line one`nLine two" 'Tr: çok satırlı kimlik birebir kaydı (İngilizce yedek)'
Assert-Eq (Tr 'Bilinmeyen metin') 'Bilinmeyen metin' 'Tr: çevirisi olmayan metin aynen kalır'
Assert-Eq (Tr 'a') 'a' 'Tr: tek karakter'
Assert-Eq (Tr '') '' 'Tr: boş metin'
Assert-Eq (Tr 'x: y') 'x: y' 'Tr: genel şablonlar (yalnızca yer tutucu) hiçbir metni eşlemez'
Assert-Eq (Tr 'ab') 'ab' 'Tr: bitişik yer tutucu şablonu hiçbir metni eşlemez'
Assert-Eq (Format-Tr 'Silindi: {0} dosya' 7) '7 Dateien gelöscht' 'Format-Tr: yer tutucu doldurma'
Assert-Eq (Format-Tr 'Kapat') 'Schließen' 'Format-Tr: yer tutucusuz'

# ---- yapısal çözücüler (birleşik metinler): sayaç eki, "Etiket: değer", üç nokta, cümle birleşimi, günlük satırı, büyük harfli başlık
Set-LangActive 'en'
Assert-Eq (Tr 'Düzeltilebilir sorunlar (2)') 'Fixable issues (2)' 'çözücü: sayaç eki korunur, metin çevrilir'
Assert-Eq (Tr 'Düzeltilebilir sorunlar (12)') 'Fixable issues (12)' 'çözücü: iki basamaklı sayaç'
Assert-Eq (Tr 'Bilinmeyen başlık (2)') 'Bilinmeyen başlık (2)' 'çözücü: sayaçlı bilinmeyen metin aynen kalır'
Assert-Eq (Tr 'Mağaza uygulamaları taranıyor (salt okunur)') 'Scanning Store apps (read-only)' 'çözücü: parantez içi not da çevrilir'
Assert-Eq (Tr 'Disk sağlıklı: PSENN001TA87QC0') 'Disk health: PSENN001TA87QC0' 'çözücü: "Etiket: değer" etiketi çevrilir, değer korunur'
Assert-Eq (Tr 'Teslim İyileştirme önbelleği: 0 B') 'Delivery Optimization cache: 0 B' 'çözücü: iki noktasız kayıtlı etiket'
Assert-Eq (Tr 'Klasik: Pencere düz renkli çizilir. Varsayılan.') 'Classic: The window is drawn in a solid color. Default.' 'çözücü: "Ad: açıklama" iki yanı da çevrilir'
Assert-Eq (Tr 'Bilinmeyen: değer') 'Bilinmeyen: değer' 'çözücü: etiketi bilinmeyen metin aynen kalır'
Assert-Eq (Tr 'Mağaza uygulamaları taranıyor...') 'Scanning Store apps...' 'çözücü: sondaki üç nokta korunur'
Assert-Eq (Tr ('Hazırlık denetleniyor' + [char]0x2026)) ('Checking readiness' + [char]0x2026) 'çözücü: tek karakterli üç nokta da korunur'
Assert-Eq (Tr 'Bilinmeyen iş...') 'Bilinmeyen iş...' 'çözücü: üç noktalı bilinmeyen metin aynen kalır'
Assert-Eq (Tr 'Bellek, işlemci ve disk yeterli; özellik kapatmaya gerek yok. Bu yüzden yalnızca gizlilik ve bakım ayarları önerilir.') 'Memory, processor and disk are sufficient; no need to turn features off. Therefore only privacy and maintenance settings are recommended.' 'çözücü: cümleler ayrı ayrı çevrilir'
Assert-Eq (Tr 'Bilinmeyen cümle. Hız için özellik kapatmaya gerek yok.') 'Bilinmeyen cümle. No need to turn features off for speed.' 'çözücü: bilinmeyen cümle korunur, bilinen çevrilir'
Assert-Eq (Tr 'Bağlantı kesilir. Yeniden başlatın. Etkili olması için yeniden başlatma gerekir.') 'The connection drops. Restart. A restart is required to take effect.' 'çözücü: çok cümleli girdi (birden çok cümleli kayıt dahil)'
Assert-Eq (Tr 'Bellek 4 GB ya da daha az; Sistem diski mekanik (HDD)') 'Memory 4 GB or less; System disk is mechanical (HDD)' 'çözücü: noktalı virgülle ayrılmış parçalar'
Assert-Eq (Tr 'Bellek 4 GB ya da daha az; Sistem diski mekanik (HDD). Hız için özellik kapatmaya gerek yok.') 'Memory 4 GB or less; System disk is mechanical (HDD). No need to turn features off for speed.' 'çözücü: cümle ve noktalı virgül birlikte'
Assert-Eq (Tr '14:02:09  INFO  Hazırlık denetleniyor') '14:02:09  INFO  Checking readiness' 'çözücü: günlük satırında yalnızca ileti çevrilir'
Assert-Eq (Tr '14:02:09  STEP  >>> Hazırlık denetleniyor') '14:02:09  STEP  >>> Checking readiness' 'çözücü: günlük satırı ve ön ek birlikte'
Assert-Eq (Tr 'YEDEK VE KURTARMA') 'BACKUP AND RECOVERY' 'çözücü: büyük harfli başlık küçük harfli kayıttan çevrilir'
Assert-Eq (Tr 'ANA EKRAN') 'HOME' 'çözücü: büyük harfli başlık (tek kayıt)'
Assert-Eq (Tr 'BİLİNMEYEN BAŞLIK') 'BİLİNMEYEN BAŞLIK' 'çözücü: bilinmeyen büyük harfli başlık aynen kalır'
Assert-Eq (Tr 'OTOMATİK') 'AUTOMATIC' 'çözücü: Türkçe İ ile büyük harfli başlık (otomatik)'
Assert-Eq (Tr 'HİZMET YÖNETİCİSİ') 'SERVICE MANAGER' 'çözücü: büyük harfli başlık, kayıt baş harfleri büyük yazılmış'
Assert-Eq (Tr 'Hizmet yöneticisi') 'Service Manager' 'çözücü: yalnızca harf büyüklüğü farklı metin bulunur'
Assert-Eq (Tr 'Yedek Ve Kurtarma') 'Backup and recovery' 'çözücü: baş harfleri büyük yazılmış metin küçük harfli kayıttan bulunur'
Assert-Eq (Convert-LangTrLower 'IĞDIR İSTANBUL') ('ığd' + [char]0x0131 + 'r ist' + [char]0x0061 + 'nbul') 'çözücü: Türkçe küçük harf dönüşümü (I -> ı, İ -> i)'
Assert-Eq (Convert-LangTrUpperFirst 'istanbul') ([string][char]0x0130 + 'stanbul') 'çözücü: Türkçe baş harf dönüşümü (i -> İ)'
Assert-Eq (Convert-LangTrUpperFirst ([string][char]0x0131 + 'rmak')) 'Irmak' 'çözücü: Türkçe baş harf dönüşümü (ı -> I)'
Assert-Eq (Convert-LangUpper 'home') 'HOME' 'çözücü: İngilizce büyük harf'
Set-LangActive 'de'
Assert-Eq (Tr 'Düzeltilebilir sorunlar (2)') 'Fixable issues (2)' 'çözücü: Almancada yok, İngilizce yedekten sayaçlı metin'
Assert-Eq (Tr 'Klasik: Pencere düz renkli çizilir. Varsayılan.') 'Classic: The window is drawn in a solid color. Default.' 'çözücü: yedek dil + etiket'
Set-LangActive 'en'
# izleme açıkken Türkçe kalıntısı bırakan kısmi çeviri eksik sayılır; eksiksiz çeviri sayılmaz
Enable-LangTrack
$null = Tr 'Bilinmeyen uzun cümle başka yerde. Hız için özellik kapatmaya gerek yok.'
Assert-True ($script:LangMiss.ContainsKey('Bilinmeyen uzun cümle başka yerde. Hız için özellik kapatmaya gerek yok.')) 'çözücü: izlemede kalıntı bırakan kısmi çeviri eksik sayılır'
$null = Tr 'Bağlantı kesilir. Yeniden başlatın. Etkili olması için yeniden başlatma gerekir.'
Assert-True (-not $script:LangMiss.ContainsKey('Bağlantı kesilir. Yeniden başlatın. Etkili olması için yeniden başlatma gerekir.')) 'çözücü: eksiksiz çeviri eksik sayılmaz'
$script:LangTrack = $false; $script:LangMiss = $null; $script:LangSeen = $null; $script:LangOut = $null
Set-LangActive 'tr'

Set-LangActive 'en'
Assert-True ($null -eq $script:LangFallback) 'etkinleştirme: İngilizce seçiliyken yedek yok'
Assert-Eq (Tr 'Kapat') 'Close' 'Tr: birebir (İngilizce)'
Assert-Eq (Tr 'Silindi: 1 dosya') '1 files deleted' 'Tr: şablon (İngilizce)'

Set-LangActive 'ar'
Assert-True ($script:LangRtl -eq $true -and $script:LangTag -eq 'ar-SA' -and $script:LangName -eq 'العربية') 'etkinleştirme: Arapça sağdan sola ve etiket'
Assert-Eq (Tr 'Kapat') 'إغلاق' 'Tr: Arapça'
Assert-Eq (Tr 'Tamam') 'OK' 'Tr: Arapçada yok, İngilizce yedek'

# yüzde yazımı: Türkçede %40, çoğu dilde 40%, Almanca/Fransızca gibi dillerde 40 % (bölünmez boşluk)
$nb = [string][char]0x00A0
Assert-Eq (Get-LangPercentStyle 'tr') 0 'yüzde: Türkçe stili %40'
Assert-Eq (Get-LangPercentStyle 'en') 1 'yüzde: İngilizce 40%'
Assert-Eq (Get-LangPercentStyle 'zh-hant') 1 'yüzde: Geleneksel Çince 40%'
Assert-Eq (Get-LangPercentStyle 'pt-BR') 1 'yüzde: Portekizce 40%'
Assert-Eq (Get-LangPercentStyle 'de') 2 'yüzde: Almanca 40 %'
Assert-Eq (Get-LangPercentStyle 'FR-ca') 2 'yüzde: Fransızca 40 % (büyük harf ve bölge kodu)'
Assert-Eq (Get-LangPercentStyle 'ar') 1 'yüzde: Arapça 40%'
$script:LangPctStyle = 0
Assert-Eq (Convert-LangPercent 'CPU %40') 'CPU %40' 'yüzde: Türkçede değişmez'
Assert-Eq (Format-Percent 40) '%40' 'yüzde: Format-Percent Türkçede %40'
Set-LangActive 'en'
Assert-Eq $script:LangPctStyle 1 'yüzde: İngilizce etkinleştirmesi stili ayarlar'
Assert-Eq (Format-Percent 40) '40%' 'yüzde: Format-Percent İngilizcede 40%'
Assert-Eq (Convert-LangPercent 'CPU %40 · RAM %62,5') 'CPU 40% · RAM 62,5%' 'yüzde: cümle içinde ve ondalıklı'
Assert-Eq (Convert-LangPercent '(%5)') '(5%)' 'yüzde: parantez içi'
Assert-Eq (Convert-LangPercent '%TEMP%\x') '%TEMP%\x' 'yüzde: ortam değişkeni adı korunur'
Assert-Eq (Convert-LangPercent 'C:\a%20b') 'C:\a%20b' 'yüzde: yola gömülü %20 korunur'
Assert-Eq (Convert-LangPercent 'a/%20b') 'a/%20b' 'yüzde: bağlantıdaki %20 korunur'
Assert-Eq (Convert-LangPercent '%60''a kadar') '%60''a kadar' 'yüzde: Türkçe ek alan sözcük dokunulmaz'
Assert-Eq (Convert-LangPercent '100% hazır') '100% hazır' 'yüzde: zaten sonda olan yüzde dokunulmaz'
Assert-Eq (Tr 'Pil %20 altında') 'Pil 20% altında' 'yüzde: çevrilemeyen metinde de yazım düzeltilir'
Set-LangActive 'de'
Assert-Eq (Format-Percent 40) ('40' + $nb + '%') 'yüzde: Format-Percent Almancada bölünmez boşluklu'
Assert-Eq (Convert-LangPercent 'CPU %40') ('CPU 40' + $nb + '%') 'yüzde: Almanca cümle içi'
Set-LangActive 'tr'
Assert-Eq $script:LangPctStyle 0 'yüzde: Türkçeye dönünce stil sıfırlanır'

# sağdan sola dillerde Latin harf ve rakamlı çok sözcüklü metin soldan sağa işaretiyle sarılır
$lrm = [string][char]0x200E
Assert-Eq (Convert-LangBidi 'Windows 11 Home 26H2') ($lrm + 'Windows 11 Home 26H2' + $lrm) 'çift yön: Latin metin LRM ile sarılır'
Assert-Eq (Convert-LangBidi '15.5 / 30.8 GB') ($lrm + '15.5 / 30.8 GB' + $lrm) 'çift yön: sayı ve birim LRM ile sarılır'
Assert-Eq (Convert-LangBidi 'Waiting...') ($lrm + 'Waiting...' + $lrm) 'çift yön: sondaki noktalama için de sarılır'
Assert-Eq (Convert-LangBidi '38%') '38%' 'çift yön: tek sözcük sarılmaz'
Assert-Eq (Convert-LangBidi 'ab') 'ab' 'çift yön: çok kısa metin sarılmaz'
Assert-Eq (Convert-LangBidi '12 : 34') ($lrm + '12 : 34' + $lrm) 'çift yön: yalnızca rakam ve ayraçtan oluşan metin de sarılır (sıra ters dizilmesin)'
Assert-Eq (Convert-LangBidi ' - ') ' - ' 'çift yön: harf ve rakam yoksa sarılmaz'
Assert-Eq (Convert-LangBidi ('C: 151.4 ' + [char]0x062C + [char]0x064A + [char]0x062C + [char]0x0627)) ('C: 151.4 ' + [char]0x062C + [char]0x064A + [char]0x062C + [char]0x0627) 'çift yön: Arapça harf içeren metin sarılmaz'
Assert-Eq (Convert-LangBidi ($lrm + 'Windows 11')) ($lrm + 'Windows 11') 'çift yön: zaten işaretli metin sarılmaz'
Set-LangActive 'ar'
Assert-Eq (Tr 'Windows 11 Home 26H2') ($lrm + 'Windows 11 Home 26H2' + $lrm) 'çift yön: Arapçada Tr Latin metni sarar'
Assert-Eq (Tr 'Kapat') 'إغلاق' 'çift yön: Arapça çeviri sarılmaz'
Set-LangActive 'en'
Assert-Eq (Tr 'Windows 11 Home 26H2') 'Windows 11 Home 26H2' 'çift yön: soldan sağa dillerde sarılmaz'
Set-LangActive 'tr'

Set-LangActive 'zh-hant'
Assert-Eq (Tr 'Kapat') '關閉' 'Tr: Geleneksel Çince'
Assert-Eq $script:LangTag 'zh-TW' 'etkinleştirme: zh-hant dil etiketi'

Set-LangActive 'tr'
Assert-True ($script:LangOn -eq $false -and $script:LangCode -eq 'tr' -and $null -eq $script:LangPrimary) 'etkinleştirme: Türkçe çeviriyi kapatır'
Assert-Eq (Tr 'Kapat') 'Kapat' 'Tr: Türkçe etkinken değişmez'
Set-LangActive 'yok'
Assert-True ($script:LangOn -eq $false) 'etkinleştirme: olmayan dil Türkçe kalır'

# kullanıcı dosyası aynı kodlu uygulama dosyasının yerine geçer
Write-Pack $usrDil 'de' "#name: German (user)`n#native: Deutsch (Benutzer)`n#tag: de-DE`n#match: de`n#coverage: 5`nKapat`tZumachen`n"
$list = @(Get-LangList $true)
$de = @($list | Where-Object { $_.Code -eq 'de' })
Assert-Eq $de.Count 1 'kullanıcı dosyası: aynı kod tek kayıt'
Assert-Eq $de[0].Native 'Deutsch (Benutzer)' 'kullanıcı dosyası: uygulama dosyasının yerine geçer'
Assert-Eq $de[0].User $true 'kullanıcı dosyası: işaretlenir'
Set-LangActive 'de'
Assert-Eq (Tr 'Kapat') 'Zumachen' 'kullanıcı dosyası: çeviri kullanıcı dosyasından'
Assert-Eq (Tr 'Tamam') 'OK' 'kullanıcı dosyası: eksik metin İngilizce yedekten'
Remove-Item -LiteralPath (Join-Path $usrDil 'de.lang') -Force
$null = Get-LangList $true

# kullanıcı yeni bir dil ekler
Write-Pack $usrDil 'xx' "#name: Test Language`n#native: Testish`n#tag: en-US`n#match: xx`n#coverage: 1`nKapat`tTX`n"
$codes = @((Get-LangList $true) | ForEach-Object { $_.Code })
Assert-True ($codes -contains 'xx') 'kullanıcı dosyası: yeni dil listeye girer'
Assert-Eq (Find-LangForCulture 'xx-YY') 'xx' 'kullanıcı dosyası: yeni dil kültür eşlemesine girer'
Remove-Item -LiteralPath (Join-Path $usrDil 'xx.lang') -Force
$null = Get-LangList $true

# =====================================================================
#  4) Initialize-Lang: komut satırı > ortam > ayar
# =====================================================================
$script:Settings = @{ Language = 'de' }; $Dil = ''; $env:MM_DIL = ''
Initialize-Lang
Assert-Eq $script:LangCode 'de' 'açılış: ayardaki dil'
$env:MM_DIL = 'en'; Initialize-Lang
Assert-Eq $script:LangCode 'en' 'açılış: ortam değişkeni ayarın önüne geçer'
$Dil = 'ar'; Initialize-Lang
Assert-True ($script:LangCode -eq 'ar' -and $script:LangRtl -eq $true) 'açılış: -Dil ortam değişkeninin önüne geçer'
$Dil = ''; $env:MM_DIL = ''
$script:Settings = @{ Language = 'tr' }; Initialize-Lang
Assert-True ($script:LangOn -eq $false -and $script:LangCode -eq 'tr') 'açılış: tr çeviriyi kapatır'
$script:Settings = @{ Language = 'sv' }; Initialize-Lang
Assert-Eq $script:LangCode 'en' 'açılış: desteklenmeyen dil İngilizceye düşer'
$script:Settings = @{ }; Initialize-Lang
Assert-True ($null -ne $script:LangCode) 'açılış: ayarda Language yoksa hata vermez'
$script:Settings = @{ Language = 'de' }; $env:MM_DIL_IZLE = '1'; Initialize-Lang; $env:MM_DIL_IZLE = ''
Assert-True ($script:LangTrack -eq $true) 'açılış: MM_DIL_IZLE izlemeyi açar'
[void](Tr 'Hiç çevrilmemiş cümle'); [void](Tr 'Kapat'); [void](Tr 'Hiç çevrilmemiş cümle')
Assert-Eq $script:LangMiss['Hiç çevrilmemiş cümle'] 2 'izleme: eksik metin sayılır'
Assert-True (-not $script:LangMiss.ContainsKey('Kapat')) 'izleme: çevrilen metin eksik sayılmaz'
Assert-True ($script:LangSeen.Contains('Schließen') -and $script:LangSeen.Contains('Hiç çevrilmemiş cümle')) 'izleme: Tr çıktıları kaydedilir'
Assert-True (-not (Test-LangLeak 'Schließen')) 'sızıntı: Tr çıktısı sızıntı değil'
Assert-True (-not (Test-LangLeak 'Hiç çevrilmemiş cümle')) 'sızıntı: Tr''den geçen metin sızıntı değil (eksik olarak ayrıca sayılır)'
Assert-True (Test-LangLeak 'Tr''ye hiç uğramamış Türkçe cümle') 'sızıntı: Tr''ye uğramayan Türkçe metin sızıntıdır'
Assert-True (-not (Test-LangLeak 'Plain ASCII text')) 'sızıntı: Türkçe harf yoksa sızıntı değil'
# dil denetimi (Duman-Dil.cmd): dile duyarlı sızıntı deseni, rapor yardımcıları ve kesik kararı
Assert-Eq (Get-LangLeakPattern 'tr') '' 'dil denetimi: Türkçede sızıntı denetimi yapılmaz'
Assert-Eq (Get-LangLeakPattern 'az') '' 'dil denetimi: Türkçe harf kullanan dillerde harf yoluyla sızıntı anlaşılamaz'
Assert-True ([regex]::IsMatch('Çalışma', (Get-LangLeakPattern 'de'))) 'dil denetimi: Almancada Türkçeye özgü harf (ş) sızıntı sayılır'
Assert-True (-not [regex]::IsMatch('Größe schließen für', (Get-LangLeakPattern 'de'))) 'dil denetimi: Almanca ö ü ß sızıntı sayılmaz'
Assert-True (-not [regex]::IsMatch('Français garçon', (Get-LangLeakPattern 'fr'))) 'dil denetimi: Fransızca ç sızıntı sayılmaz'
Assert-True ([regex]::IsMatch('Öğe', (Get-LangLeakPattern 'zh-hant'))) 'dil denetimi: Çincede Türkçe harf sızıntı sayılır'
Assert-True ([regex]::IsMatch('Öğe', (Get-LangLeakPattern 'ar'))) 'dil denetimi: Arapçada Türkçe harf sızıntı sayılır'
$seenSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
[void]$seenSet.Add('Çalışma')
Assert-True (-not (Test-LangLeakText 'Çalışma' 'de' $seenSet)) 'dil denetimi: Tr çıktısı olan metin sızıntı değil'
Assert-True (Test-LangLeakText 'Çalışma sürüyor' 'de' $seenSet) 'dil denetimi: Tr''ye uğramayan Türkçe harfli metin sızıntıdır'
Assert-True (-not (Test-LangLeakText 'Größe' 'de' $seenSet)) 'dil denetimi: Almanca ö sızıntı değil'
Assert-True (-not (Test-LangLeakText '   ' 'de' $null)) 'dil denetimi: boş metin sızıntı değil'
Assert-True (-not (Test-LangLeakText 'Çalışma' 'tr' $null)) 'dil denetimi: Türkçe çalışırken sızıntı sayılmaz'
Assert-Eq (Format-LangSnippet "a`r`n  b`tc" 50) 'a b c' 'dil denetimi: rapor metni tek satıra indirilir'
Assert-Eq (Format-LangSnippet ('x' * 40) 20) (('x' * 17) + '...') 'dil denetimi: uzun metin kısaltılır'
$vis = Get-LangVisible ([double[]]@(10, 10, 110, 30)) ([double[]]@(0, 0, 60, 100))
Assert-Eq ([string]$vis[0] + ',' + [string]$vis[1] + ',' + [string]$vis[2] + ',' + [string]$vis[3]) '50,0,50,20' 'dil denetimi: görünen pay (yarısı yatayda kırpılmış)'
$vis2 = Get-LangVisible ([double[]]@(200, 10, 300, 30)) ([double[]]@(0, 0, 100, 100))
Assert-Eq ([string]$vis2[2]) '0' 'dil denetimi: tamamen dışarıdaki ögenin görünen genişliği 0'
$vis3 = Get-LangVisible ([double[]]@(10, 10, 60, 30)) ([double[]]@([double]::NegativeInfinity, [double]::NegativeInfinity, [double]::PositiveInfinity, [double]::PositiveInfinity))
Assert-Eq ([string]$vis3[0] + ',' + [string]$vis3[1]) '0,0' 'dil denetimi: sınırsız kırpma alanında kayıp yok'
Assert-Eq (Get-LangClipVerdict 0 0 100 20 2) '' 'dil denetimi: eksiksiz görünen metin sorun değil'
Assert-Eq (Get-LangClipVerdict 1.5 1.0 98 19 2) '' 'dil denetimi: 2 px altı fark yok sayılır'
Assert-True ((Get-LangClipVerdict 50 0 50 20 2) -like '*yatay 50 px*') 'dil denetimi: yatay kırpılma bildirilir'
Assert-True ((Get-LangClipVerdict 0 8 100 12 2) -like '*düşey 8 px*') 'dil denetimi: düşey kırpılma bildirilir'
Assert-True ((Get-LangClipVerdict 100 0 0 20 2) -like '*tamamen dışarıda*') 'dil denetimi: yatayda tamamen dışarıdaki metin bildirilir'
Assert-Eq (Get-LangClipVerdict 0 20 100 0 2) '' 'dil denetimi: dikeyde tamamen gizlenen (kapalı bölüm) sorun sayılmaz'
Assert-Eq (Get-LangClipVerdict 100 0 0 20 2 0 600) '' 'dil denetimi: sıfır genişlikli kapsayıcıdaki (tasarım gereği gizli) metin sorun sayılmaz'
Assert-Eq (Get-LangClipVerdict 100 0 0 20 2 300 600) 'yatayda tamamen dışarıda' 'dil denetimi: gerçek alanı olan kapsayıcının dışına taşan metin bildirilir'
$mp = Save-LangMiss
Assert-True (Test-Path -LiteralPath $mp) 'izleme: eksik listesi dosyaya yazılır'
$mt = [System.IO.File]::ReadAllText($mp, [System.Text.Encoding]::UTF8)
Assert-True ($mt -match "2`tHiç çevrilmemiş cümle") 'izleme: dosya sayı ve metin içerir'
Remove-Item -LiteralPath $mp -Force
$script:LangTrack = $false

# =====================================================================
#  5) XAML ve günlük satırı çevirisi
# =====================================================================
Set-LangActive 'en'
$x = '<StackPanel><Button x:Name="Kapat" Content="Kapat" ToolTip="Silindi: 5 dosya" Tag="Kapat"/><TextBlock Text="{Binding [Name]}"/><TextBlock Text="@@Text@@"/><TextBlock Text="Tamam &amp; Kapat"/><TextBlock PlaceholderText="Kapat"/><TextBlock Text="Satır bir&#10;Satır iki"/><TextBlock Text="Bilinmeyen"/></StackPanel>'
$y = Convert-XamlText $x
Assert-True ($y.Contains('Content="Close"')) 'XAML: Content çevrildi'
Assert-True ($y.Contains('ToolTip="5 files deleted"')) 'XAML: ToolTip şablonu çevrildi'
Assert-True ($y.Contains('x:Name="Kapat"') -and $y.Contains('Tag="Kapat"')) 'XAML: ad ve etiket değişmedi'
Assert-True ($y.Contains('Text="{Binding [Name]}"')) 'XAML: bağlama değişmedi'
Assert-True ($y.Contains('Text="@@Text@@"')) 'XAML: yer tutucu değişmedi'
Assert-True ($y.Contains('Text="OK &amp; Close"')) 'XAML: varlık kodlu metin çözülür, çevrilir, yeniden kodlanır'
Assert-True ($y.Contains('PlaceholderText="Kapat"')) 'XAML: PlaceholderText öznitelik adı eşleşmez'
Assert-True ($y.Contains('Text="Line one&#10;Line two"')) 'XAML: satır sonu varlığı çözülür, çok satırlı çevrilir, yeniden kodlanır'
Assert-True ($y.Contains('Text="Bilinmeyen"')) 'XAML: çevirisi olmayan metin değişmedi'
[xml]$parsed = '<r xmlns:x="u">' + $y + '</r>'
Assert-True ($null -ne $parsed) 'XAML: çevrilmiş belge geçerli XML'
Set-LangActive 'tr'
Assert-Eq (Convert-XamlText $x) $x 'XAML: Türkçede belge aynen döner'
Set-LangActive 'de'
Assert-Eq (Convert-LogLineText '12:00:01  OK  Kapat') '12:00:01  OK  Schließen' 'günlük: saat ve düzey korunur, ileti çevrilir'
Assert-Eq (Convert-LogLineText '12:00:01  WARN  Silindi: 3 dosya') '12:00:01  WARN  3 Dateien gelöscht' 'günlük: şablon iletisi'
Assert-Eq (Convert-LogLineText 'Kapat ve çık') 'Kapat ve çık' 'günlük: önek yoksa tüm satır denenir'
Assert-Eq (Convert-LogLineText '12:00:01  ERR  Bilinmeyen ileti') '12:00:01  ERR  Bilinmeyen ileti' 'günlük: çevirisi olmayan ileti aynen'
Set-LangActive 'tr'
Assert-Eq (Convert-LogLineText '12:00:01  OK  Kapat') '12:00:01  OK  Kapat' 'günlük: Türkçede satır aynen'
Assert-Eq (ConvertTo-XamlAttr "a&b<c`"d`ne") 'a&amp;b&lt;c&quot;d&#10;e' 'öznitelik kodlama'

# büyük harf
Set-LangActive 'tr'
Assert-Eq (ConvertTo-TrUpper 'ışık i') ('I' + [char]0x015E + 'IK ' + [char]0x0130) 'büyük harf: Türkçe i/ı kuralı'
Set-LangActive 'en'
Assert-Eq (ConvertTo-TrUpper 'Kapat') 'CLOSE' 'büyük harf: etkin dilde önce çevrilir, sonra büyütülür'
Assert-Eq (ConvertTo-TrUpper 'disk') 'DISK' 'büyük harf: İngilizcede noktalı İ oluşmaz'
Set-LangActive 'tr'

# =====================================================================
#  6) Ayarlar > Dil kartı akışı (sahte arayüz)
# =====================================================================
$script:FakeSys = 'tr'
function Get-SystemLangCode { return $script:FakeSys }
$ui = @{ st_LangSel = (New-FakeCombo); st_LangNote = (New-FakeCtl); st_LangApply = (New-FakeCtl); st_LangFolder = (New-FakeCtl) }
Set-LangActive 'tr'
$script:Settings = @{ Language = 'auto' }
Initialize-StLang
$items = @($ui.st_LangSel.Items)
Assert-Eq $items[0]['Key'] 'auto' 'Dil kartı: ilk öğe Otomatik'
Assert-Eq $items[1]['Key'] 'tr' 'Dil kartı: ikinci öğe Türkçe'
Assert-True (@($items | ForEach-Object { $_['Key'] }) -contains 'zh-hant') 'Dil kartı: tüm diller listede'
Assert-Eq $items[1]['Name'] ('T' + [char]0x00FC + 'rk' + [char]0x00E7 + 'e (Turkish)') 'Dil kartı: Türkçe adı'
$deItem = @($items | Where-Object { $_['Key'] -eq 'de' })[0]
Assert-Eq $deItem['Name'] 'Deutsch (German)  -  %60' 'Dil kartı: kapsamı eksik dilde yüzde gösterilir'
$enItem = @($items | Where-Object { $_['Key'] -eq 'en' })[0]
Assert-Eq $enItem['Name'] 'English' 'Dil kartı: kapsamı tam dilde yüzde gösterilmez'
Load-StLang
Assert-Eq (Get-ComboKey $ui.st_LangSel) 'auto' 'Dil kartı: kayıtlı "auto" seçili'
Assert-Eq $ui.st_LangApply.IsEnabled $false 'Dil kartı: değişiklik yokken Uygula kapalı'
Assert-True ($ui.st_LangNote.Text.Contains('Türkçedir')) 'Dil kartı: Türkçe notu'
$script:FakeSys = 'de'
Update-StLangNote
Assert-Eq $ui.st_LangApply.IsEnabled $true 'Dil kartı: Windows dili değiştiyse (auto) Uygula açılır'
$script:FakeSys = 'tr'
[void](Select-ComboKey $ui.st_LangSel 'de')
Update-StLangNote
Assert-Eq $ui.st_LangApply.IsEnabled $true 'Dil kartı: farklı dil seçilince Uygula açılır'
Assert-True ($ui.st_LangNote.Text.Contains('%60')) 'Dil kartı: kapsam yüzdesi notta'
Assert-True ($ui.st_LangNote.Text.Contains('İngilizce')) 'Dil kartı: eksik kapsam uyarısı'
[void](Select-ComboKey $ui.st_LangSel 'en')
Update-StLangNote
Assert-True ($ui.st_LangNote.Text.Contains('%100')) 'Dil kartı: tam kapsam notu'

# Uygula -> onay -> kayıt -> yeniden başlatma
$script:Saved = $null; $script:Restarted = 0; $script:Exited = 0
function Save-Settings($S) { $script:Saved = $S.Language }
function Restart-App { $script:Restarted++; return $true }
function Exit-App { $script:Exited++ }
Reset-Fake
[void](Select-ComboKey $ui.st_LangSel 'de')
Invoke-StLangApply
Assert-Eq $script:Confirms.Count 1 'Uygula: onay penceresi açılır'
Assert-Eq $script:Confirms[0].Title ('Dil de' + [char]0x011F + 'i' + [char]0x015F + 'ikli' + [char]0x011F + 'i') 'Uygula: onay başlığı'
Assert-True ($script:Confirms[0].Text.Contains('Deutsch')) 'Uygula: onay metni seçilen dilin yerel adını içerir'
Assert-Eq $script:Saved $null 'Uygula: onaydan önce kayıt yapılmaz'
& $script:Confirms[0].OnOk
Assert-Eq $script:Saved 'de' 'Uygula: onaydan sonra ayar kaydedilir'
Assert-Eq $script:Settings.Language 'de' 'Uygula: bellekteki ayar güncellenir'
Assert-True ($script:Restarted -eq 1 -and $script:Exited -eq 1) 'Uygula: yeniden başlatma ve çıkış'
Reset-Fake; $script:Restarted = 0; $script:Exited = 0
function Restart-App { $script:Restarted++; return $false }
[void](Select-ComboKey $ui.st_LangSel 'auto')
Invoke-StLangApply
& $script:Confirms[0].OnOk
Assert-Eq $script:Settings.Language 'auto' 'Uygula: "auto" kaydedilir'
Assert-True ($script:Exited -eq 0 -and $script:Toasts.Count -eq 1 -and $script:Toasts[0].K -eq 'warn') 'Uygula: yeniden başlatılamazsa çıkılmaz, uyarı gösterilir'

# yeniden başlatma komut satırı
$a = Get-RestartArgs 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' "C:\Users\O'Neil\Multimizer.ps1" 4242
Assert-True ($a.StartsWith('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -EncodedCommand ')) 'yeniden başlatma: gizli pencere ve kodlu komut'
$enc = $a.Substring($a.IndexOf('-EncodedCommand ') + 16)
$dec = [System.Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($enc))
Assert-True ($dec.Contains('Wait-Process -Id 4242')) 'yeniden başlatma: eski sürecin bitmesi beklenir'
Assert-True ($dec.Contains("O''Neil")) 'yeniden başlatma: tek tırnak ikilenir'
Assert-True ($dec.Contains('-STA') -and $dec.Contains('-File')) 'yeniden başlatma: STA ve -File'
$tk = $null; $te = $null
[void][System.Management.Automation.Language.Parser]::ParseInput($dec, [ref]$tk, [ref]$te)
Assert-Eq @($te).Count 0 'yeniden başlatma: üretilen komut sözdizimi geçerli'

# =====================================================================
#  7) bağlantı noktaları (derlenmiş kaynak)
# =====================================================================
Assert-True ($src.Contains("[string]`$Dil = ''")) 'kaynak: -Dil parametresi'
Assert-True ($src.Contains("[void]`$parts.Add('-Dil')")) 'kaynak: yeniden başlatma bloğu -Dil aktarır'
Assert-True ($src.Contains("Language     = 'auto'")) 'kaynak: Language varsayılanı auto'
$ix = $src.IndexOf("`$sync.Settings = `$script:Settings`r`ntry { Initialize-Lang } catch { }")
Assert-True ($ix -gt 0) 'kaynak: Initialize-Lang ayarlar yüklendikten hemen sonra çağrılır'
$cnt = [regex]::Matches($src, '(?<!\[void\])\[System\.Windows\.Markup\.XamlReader\]::Parse\(').Count
Assert-Eq $cnt 1 'kaynak: XamlReader.Parse yalnızca Read-LocalXaml içinde (sınama yerleri [void] ile)'
Assert-Eq ([regex]::Matches($src, 'Read-LocalXaml \(').Count) 21 'kaynak: 21 XAML okuma yeri Read-LocalXaml kullanır'
Assert-True ($src.Contains('function Add-LogLine([string]$Line) {' + "`r`n" + '    $Line = Convert-LogLineText $Line')) 'kaynak: günlük satırı çevrilir'
Assert-True ($src.Contains('Name = (Tr $Name)')) 'kaynak: liste öğesi adları çevrilir'
Assert-True ($src.Contains('$v = [string](Tr $v)')) 'kaynak: satır şablonu metinleri çevrilir'
Assert-True ($src.Contains('x:Name="st_LangSel"') -and $src.Contains('x:Name="st_LangApply"') -and $src.Contains('x:Name="st_LangFolder"') -and $src.Contains('x:Name="st_LangNote"')) 'kaynak: Ayarlar > Dil kartı'
Assert-True ($src.Contains("Initialize-StLang`r`n    Init-StLangEvents") -and $src.Contains("Load-StUpdate`r`n    Load-StLang")) 'kaynak: Dil kartı Ayarlar sayfasına bağlı'
$wrapped = [regex]::Matches($src, '\(Tr \$\(').Count
Assert-True ($wrapped -ge 300) ("kaynak: metin atamaları Tr ile sarılı ($wrapped)")
Assert-Eq ([regex]::Matches($src, '\$(r|res|out|pl|m|d|l)\.(Text|Content|Title|Header|ToolTip) = \(Tr ').Count) 0 'kaynak: veri nesnelerine yapılan atamalar sarılmaz'
Assert-True ($src.Contains('$tb.Text = $Line # Tr:yok')) 'kaynak: günlük satırı iki kez çevrilmez'
Assert-True ($src.Contains('$script:Tray.Text = $t # Tr:yok') -and $src.Contains('$t = Tr $t')) 'kaynak: tepsi ipucu önce çevrilir sonra 63 karaktere kısaltılır'
Assert-True ($src.Contains("`$d.Description = (Tr `$Desc)")) 'kaynak: klasör seçici açıklaması çevrilir'

# sarma adımı: her sarılı atamanın sağ tarafı geçerli ifade (sözdizimi denetimi tüm dosyada)
$tk = $null; $te = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($script:TestPath, [ref]$tk, [ref]$te)
Assert-Eq @($te).Count 0 'kaynak: sarılmış betik sözdizimi geçerli'
$bad = 0
foreach ($a in @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true))) {
    $lt = $a.Left
    if ($lt -isnot [System.Management.Automation.Language.MemberExpressionAst]) { continue }
    $mem = [string]$lt.Member.Extent.Text
    if (@('Text', 'Content', 'ToolTip', 'Header', 'Title') -cnotcontains $mem) { continue }
    $rt = $a.Right.Extent.Text
    if ($rt.StartsWith('(Tr $(') -and -not $rt.EndsWith('))')) { $bad++ }
}
Assert-Eq $bad 0 'kaynak: sarılı atamalar iki parantezle kapanır'

# =====================================================================
#  8) gönderilen dil dosyaları
# =====================================================================
$shipDir = Join-Path (Split-Path -Parent $script:TestPath) 'veri\dil'
$shipFiles = @()
if (Test-Path -LiteralPath $shipDir) { $shipFiles = @(Get-ChildItem -LiteralPath $shipDir -Filter '*.lang' -File) }
Assert-True ($shipFiles.Count -ge 1) 'dil dosyaları: veri\dil altında en az İngilizce var'
$enFile = $shipFiles | Where-Object { $_.BaseName -eq 'en' }
Assert-True ($null -ne $enFile) 'dil dosyaları: en.lang var'
foreach ($f in $shipFiles) {
    $code = $f.BaseName
    $raw = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8)
    Assert-True ($code -cmatch '^[a-z]{2,3}(-[a-z0-9]{2,8})?$') "dil dosyası $code`: dosya adı geçerli kod"
    $pk = Read-LangPack $raw $code
    foreach ($k in @('name', 'native', 'tag', 'match', 'coverage')) { Assert-True ($pk.Meta.ContainsKey($k) -and [string]$pk.Meta[$k] -ne '') "dil dosyası $code`: üst bilgi $k" }
    Assert-True ([int]$pk.Meta['coverage'] -ge 0 -and [int]$pk.Meta['coverage'] -le 100) "dil dosyası $code`: kapsam 0-100"
    Assert-True ($pk.N -gt 0) "dil dosyası $code`: kayıt var"
    # yer tutucu eşliği: kimlikteki {n} kümesi çeviridekiyle aynı olmalı; yinelenen kimlik yok
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    $badPh = 0; $dup = 0; $empty = 0
    foreach ($ln0 in ($raw -split "`n")) {
        $ln = $ln0.TrimEnd("`r")
        if ($ln.Length -eq 0 -or $ln[0] -eq '#') { continue }
        $tab = $ln.IndexOf([char]9)
        if ($tab -lt 1) { continue }
        $id = Get-LangUnescaped $ln.Substring(0, $tab); $out = Get-LangUnescaped $ln.Substring($tab + 1)
        if (-not $seen.Add($id)) { $dup++ }
        if ($out.Trim().Length -eq 0) { $empty++ }
        $a1 = @([regex]::Matches($id, '\{\d+\}') | ForEach-Object { $_.Value } | Sort-Object -Unique) -join ','
        $a2 = @([regex]::Matches($out, '\{\d+\}') | ForEach-Object { $_.Value } | Sort-Object -Unique) -join ','
        # Kimliğin başındaki {0}, büyük Türkçe harf ya da tırnak gibi bir karakter ifadesinin kalıntısıdır;
        # çeviride bu yer tutucu bilerek yer almaz (çözümleme yine eşleşir).
        if ($a1 -ne $a2 -and $id -match '^\{0\}[^\s\{]' -and $out -notmatch '\{0\}') {
            $a1 = @([regex]::Matches($id, '\{\d+\}') | ForEach-Object { $_.Value } | Where-Object { $_ -ne '{0}' } | Sort-Object -Unique) -join ','
        }
        if ($a1 -ne $a2) { $badPh++ }
    }
    Assert-Eq $badPh 0 "dil dosyası $code`: yer tutucular kimlik ve çeviride aynı"
    Assert-Eq $dup 0 "dil dosyası $code`: yinelenen kimlik yok"
    Assert-Eq $empty 0 "dil dosyası $code`: boş çeviri yok"
}

Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
Show-Result
