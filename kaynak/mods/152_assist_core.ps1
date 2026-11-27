# ==================================================================
#  ASISTAN (cekirdek): yazilan soruyu konuyla eslestirir, kisa bir aciklama ve tek tikla acilan eylemler dondurur.
#  Tamamen yereldir: cevaplar bu dosyadaki sabit konu tablosundan gelir, hicbir metin bilgisayardan cikmaz, yapay zeka servisi kullanilmaz.
#  Eylem etiketleri: nav:<sayfa> | sub:<sayfa>:<sekme> | act:<pano eylemi> | cmd:<komut satiri> | kit:<Yardimcilar gorunumu>
# ==================================================================

# W: aranacak govdeler (kucuk harf, Turkce harfler sadelestirilmis). 4 harf ve uzeri govde, sozcugun basinda da eslesir ("yavas" -> "yavasladi").
# Konu tablosu bir islev govdesindedir: PowerShell islev govdesini ilk cagrida derler. Boylece tablo acilista ve her arka plan
# calisma alaninda derlenmez (gercek bilgisayarda olculdu: pilde yaklasik 0,7 sn); yalnizca Asistan ilk kez kullanildiginda yuklenir.
function Get-AskTopicData {
    return @(
        @{ K = 'slow'; Q = 'Bilgisayarım yavaş'; W = 'yavas kasiyor kasma takiliyor agir hantal hizlan hizli performans donuyor dondu gecikiyor'
           T = 'Bilgisayar yavaş çalışıyor'
           A = 'Yavaşlığın en sık üç nedeni: açılışta başlayan çok sayıda program, dolmuş disk ve arka planda boşuna çalışan hizmetlerdir. Önce sağlık taramasını çalıştırın; sonuç hangi adımın işe yarayacağını gösterir. Uygulanan her değişiklik Geçmiş sayfasından geri alınır.'
           Do = @(@{ L = 'Sağlık taraması'; Tag = 'act:health' }, @{ L = 'Başlangıç programları'; Tag = 'sub:apps:startup' }, @{ L = 'Hızlı bakım'; Tag = 'act:maint' }, @{ L = 'Önerilen ayarlar'; Tag = 'nav:optimize' }) }
        @{ K = 'disk'; Q = 'Diskim doldu'; W = 'disk dolu doldu dolmus yer alan bosalt temizle temizlik depolama kapasite gereksiz cop'
           T = 'Diskte yer açmak'
           A = 'Temizlik taraması geçici dosyaları, güncelleme artıklarını ve tarayıcı önbelleklerini bulur; neyin silineceğini önce size gösterir. Asıl yeri çoğunlukla büyük ve yinelenen dosyalar tutar.'
           Do = @(@{ L = 'Temizlik taraması'; Tag = 'sub:clean:clean' }, @{ L = 'Büyük dosyalar'; Tag = 'sub:clean:big' }, @{ L = 'Kopya dosyalar'; Tag = 'sub:clean:dup' }) }
        @{ K = 'net'; Q = 'İnternetim yavaş'; W = 'internet baglanti wifi kablosuz kopuyor kopma ping gecikme dns modem indirme yukleme yavas'
           T = 'İnternet yavaş ya da kopuyor'
           A = 'Önce hız testiyle hattın gerçek hızını ölçün. Sayfalar geç açılıyor ama indirme hızlıysa sorun çoğunlukla DNS’tedir: DNS ölçümü en hızlı sunucuyu gösterir. Bağlantı hiç yoksa ağ onarımı bağdaştırıcıyı sıfırlar.'
           Do = @(@{ L = 'Hız testi'; Tag = 'sub:network:speed' }, @{ L = 'DNS hızını ölç'; Tag = 'sub:network:dns' }, @{ L = 'Ağ onarımı'; Tag = 'sub:network:fix' }) }
        @{ K = 'crypt'; Q = ''; W = 'sifrele sifreleme sifreli bitlocker kilitle veracrypt koru korumak'
           T = 'Dosya ve disk şifreleme'
           A = 'Sistem sürücüsü Windows’un kendi şifrelemesiyle (BitLocker; Home sürümünde “Cihaz şifrelemesi”) korunur. Tek tek dosyalar için uygulamanın AES-256 şifrelemesi, USB bellek ve ek sürücüler için açık kaynaklı VeraCrypt uygundur.'
           Do = @(@{ L = 'Disk şifreleme'; Tag = 'sub:backup:bl' }, @{ L = 'Dosya şifrele'; Tag = 'sub:tools:files' }) }
        @{ K = 'pw'; Q = 'Güçlü parola üret'; W = 'parola password sifre uret olustur guclu'
           T = 'Güçlü parola'
           A = 'Parola üretici, işletim sisteminin kriptografik üretecinden rastgele parola üretir ve panoya kopyalar; pano 60 saniye sonra temizlenir. Parola hiçbir yere kaydedilmez.'
           Do = @(@{ L = 'Parola üretici'; Tag = 'kit:pw' }) }
        @{ K = 'priv'; Q = 'Veri gönderimini kapat'; W = 'gizlilik telemetri izleme izleniyor reklam veri gonder gonderiyor takip casus mahremiyet'
           T = 'Gizlilik ve veri gönderimi'
           A = 'Windows’un tanılama verisi, reklam kimliği ve öneri ayarları tek adımda en aza indirilir (Home ve Pro’da telemetri tümüyle kapatılamaz; “Gerekli” düzeyine iner). Hangi programın internete bağlandığını görüp istemediğinizin çıkışını kesebilirsiniz.'
           Do = @(@{ L = 'İzlenmeyi kapat'; Tag = 'act:privacy' }, @{ L = 'İnternete bağlanan programlar'; Tag = 'kit:net' }, @{ L = 'Açık kaynak alternatifleri'; Tag = 'kit:alt' }) }
        @{ K = 'game'; Q = ''; W = 'oyun oyunda fps gaming takilma'
           T = 'Oyunlarda performans'
           A = 'Oyun kipi; oyun çubuğu kaydı, tam ekran iyileştirmeleri ve grafik tercihi gibi ayarları toplar, oyun sırasında işlemci, ekran kartı ve sıcaklığı gösterir. Dizüstünde fişe takılıyken güç kipini “En iyi performans” yapın.'
           Do = @(@{ L = 'Oyun kipi'; Tag = 'nav:gaming' }, @{ L = 'Güç kipi'; Tag = 'nav:power' }) }
        @{ K = 'heat'; Q = ''; W = 'sicaklik isiniyor isinma sicak fan gurultu ses termal derece'
           T = 'Isınma ve fan sesi'
           A = 'İşlemci ve ekran kartı sıcaklığı Durum Panosu’ndaki Sıcaklık kutusunda görünür. Değer yoksa bilgisayarınız Windows’a sıcaklık bildirmiyordur. Sürekli yüksek ısıda güç kipini Dengeli’ye alın ve hava girişlerinin açık olduğunu denetleyin.'
           Do = @(@{ L = 'Akıllı bakım'; Tag = 'nav:smart' }, @{ L = 'Güç'; Tag = 'nav:power' }) }
        @{ K = 'power'; Q = ''; W = 'pil batarya sarj guc plan plani kipi tasarruf'
           T = 'Güç ve pil'
           A = 'Güç sayfası etkin planı ve güç kipini gösterir. Modern Bekleme kullanan dizüstülerde Windows yalnızca Dengeli planını sunar; performans düzeyi güç kipiyle (En iyi performans, Dengeli, En iyi güç verimliliği) ayarlanır.'
           Do = @(@{ L = 'Güç'; Tag = 'nav:power' }) }
        @{ K = 'boot'; Q = ''; W = 'baslangic acilis acilista aciliyor baslayan boot'
           T = 'Açılış süresi'
           A = 'Açılışı en çok, Windows ile birlikte başlayan programlar uzatır. Listeden kullanmadıklarınızı kapatın; program silinmez, yalnızca kendiliğinden başlamaz.'
           Do = @(@{ L = 'Başlangıç programları'; Tag = 'sub:apps:startup' }, @{ L = 'Karne: açılış süreleri'; Tag = 'kit:score' }) }
        @{ K = 'svc'; Q = ''; W = 'hizmet hizmetler servis service gereksiz'
           T = 'Gereksiz hizmetler'
           A = 'Hizmetler sayfası her hizmetin ne işe yaradığını ve kapatmanın güvenli olup olmadığını açıklar; güvenlik ve güncelleme hizmetleri kilitlidir. Karne, kendi işleminde çalışan hizmetlerin ne kadar bellek tuttuğunu gösterir.'
           Do = @(@{ L = 'Hizmetler'; Tag = 'nav:services' }, @{ L = 'Karne'; Tag = 'kit:score' }) }
        @{ K = 'upd'; Q = ''; W = 'guncelle guncelleme guncel update surucu driver'
           T = 'Güncellemeler'
           A = 'Windows güncellemeleri, sürücüler ve kurulu programların yeni sürümleri tek sayfada denetlenir. Program güncellemeleri winget deposundan imza doğrulamasıyla kurulur.'
           Do = @(@{ L = 'Güncellemeler'; Tag = 'nav:updates' }) }
        @{ K = 'undo'; Q = 'Yaptığım değişikliği geri al'; W = 'geri eski bozuldu bozdu pisman iptal donmek'
           T = 'Değişikliği geri almak'
           A = 'Multimizer’ın yaptığı her değişiklik kayıt altındadır. Geçmiş sayfasında işlemi seçip “Geri al” demeniz yeterlidir. Hepsini birden geri almak için Ayarlar > Ayarları sıfırla bölümündeki “Her şey” kapsamını kullanın.'
           Do = @(@{ L = 'Geçmiş'; Tag = 'nav:history' }, @{ L = 'Ayarlar'; Tag = 'nav:settings' }) }
        @{ K = 'backup'; Q = ''; W = 'yedek yedekle yedekleme kopya sakla'
           T = 'Yedekleme'
           A = 'Belgelerinizi ikinci bir diske ya da harici diske düzenli olarak kopyalayabilirsiniz; ilk adım bir hedef seçmektir. Yedek, diskle aynı bilgisayarda değil, ayrı bir yerde durmalıdır.'
           Do = @(@{ L = 'Yedekleme'; Tag = 'nav:backup' }) }
        @{ K = 'recover'; Q = ''; W = 'silinen sildim silindi kurtar kurtarma kayboldu kayip recover'
           T = 'Silinen dosyayı kurtarmak'
           A = 'Önce Geri Dönüşüm Kutusu’na bakın. Orada yoksa dosya kurtarma, sürücüyü yalnızca okuyarak tarar. Önemli: dosyanın silindiği sürücüye yeni bir şey yazmayın; üzerine yazılan veri geri gelmez.'
           Do = @(@{ L = 'Geri Dönüşüm Kutusu'; Tag = 'sub:backup:recycle' }, @{ L = 'Dosya kurtar'; Tag = 'act:recover' }) }
        @{ K = 'wipe'; Q = ''; W = 'kalici imha satacagim satmadan devretmeden iz birakmadan'
           T = 'Kalıcı silme'
           A = 'Bilgisayarı ya da diski elden çıkarmadan önce dosyaların geri getirilemeyecek biçimde silinmesi gerekir. Bu işlem geri alınamaz; önce ne silineceğini gösteren önizlemeyi okuyun.'
           Do = @(@{ L = 'Kalıcı sil'; Tag = 'act:erase' }) }
        @{ K = 'sec'; Q = ''; W = 'virus zararli guvenlik guvenli hack saldiri korunma defender antivirus trojan'
           T = 'Güvenlik'
           A = 'Güvenlik denetimi Defender, güvenlik duvarı, güncelleme, açık bağlantı noktaları ve şüpheli zamanlanmış görevleri denetler. Multimizer virüsten koruma yazılımı değildir; Defender’ı kapatmaz, yerine geçmez.'
           Do = @(@{ L = 'Güvenlik denetimi'; Tag = 'act:audit' }) }
        @{ K = 'crash'; Q = ''; W = 'mavi ekran cokme cokuyor kapaniyor hata bsod kilitleniyor'
           T = 'Mavi ekran ve çökmeler'
           A = 'Çözüm Merkezi, Windows’un çökme ve açılış kayıtlarını okur; hangi sürücünün ya da programın soruna yol açtığını yazar. Sistem dosyaları bozuksa Onarım sekmesindeki SFC ve DISM taramaları bunları düzeltir.'
           Do = @(@{ L = 'Çözüm Merkezi'; Tag = 'nav:solve' }, @{ L = 'Onarım'; Tag = 'sub:tools:repair' }) }
        @{ K = 'newpc'; Q = 'Yeni bilgisayar kurdum'; W = 'yeni format formatladim kurulum kurdum sifirdan tasin tasinma'
           T = 'Yeni bilgisayar ya da format sonrası'
           A = 'Sırayla: güncellemeler, eksik bileşenler, önerilen ayarlar, temel programlar ve yedekleme. Adım listesi her birini kendi sayfasında açar. Eski bilgisayarınız varsa taşınma kitiyle ayarlarınızı getirebilirsiniz.'
           Do = @(@{ L = 'Adım listesi'; Tag = 'kit:setup' }, @{ L = 'Taşınma kiti'; Tag = 'sub:backup:kit' }) }
        @{ K = 'apps'; Q = ''; W = 'program programlar uygulama kur yukle kaldir acik kaynak alternatif ucretsiz'
           T = 'Program kurmak ve kaldırmak'
           A = 'Ücretsiz araçlar listesindeki programlar winget deposundan imza ve özet doğrulamasıyla kurulur; her birinin lisansı yazılıdır ve “yalnızca açık kaynak” süzgeci vardır. Kurulu programlarınızın açık kaynak karşılığını da görebilirsiniz.'
           Do = @(@{ L = 'Ücretsiz araçlar'; Tag = 'sub:apps:foss' }, @{ L = 'Kurulu programlar'; Tag = 'sub:apps:programs' }, @{ L = 'Açık kaynak alternatifleri'; Tag = 'kit:alt' }) }
        @{ K = 'rename'; Q = ''; W = 'adlandir adlandirma isim rename toplu'
           T = 'Toplu yeniden adlandırma'
           A = 'Bir klasördeki dosyalara sıra numarası verebilir, adlarındaki metni değiştirebilir ya da başlarına tarih ekleyebilirsiniz. Önce önizleme gösterilir; işlem Geçmiş sayfasından geri alınır.'
           Do = @(@{ L = 'Toplu yeniden adlandırma'; Tag = 'kit:ren' }) }
        @{ K = 'lan'; Q = ''; W = 'agdaki cihaz cihazlar komsu bagli kimler'
           T = 'Ağınızdaki cihazlar'
           A = 'Ağ taraması kablosuz ağınıza bağlı cihazları üreticisi ve türüyle listeler; tanımadığınız cihazı işaretleyebilirsiniz.'
           Do = @(@{ L = 'Ağdaki cihazlar'; Tag = 'sub:network:dev' }) }
        @{ K = 'hw'; Q = ''; W = 'donanim ozellik ozellikleri islemci bellek ram ekran karti model anakart'
           T = 'Bu bilgisayarın özellikleri'
           A = 'Donanım özeti, güvenlik duruşu ve bu bilgisayara uygun öneriler “Bu bilgisayar” sekmesindedir.'
           Do = @(@{ L = 'Bu bilgisayar'; Tag = 'act:pcinfo' }) }
        @{ K = 'look'; Q = ''; W = 'dil language tema gorunum renk koyu karanlik yazi boyut buyut'
           T = 'Görünüm ve dil'
           A = 'Tema, yazı boyutu ve yerleşim Ayarlar sayfasındadır. Arayüz dili üst çubuktaki dil düğmesinden değişir.'
           Do = @(@{ L = 'Ayarlar'; Tag = 'nav:settings' }) }
        @{ K = 'reset'; Q = ''; W = 'sifirla sifirlama varsayilan fabrika'
           T = 'Ayarları sıfırlamak'
           A = 'Üç kapsam vardır: yalnızca görünüm, tüm uygulama tercihleri ya da her şey (Multimizer’ın Windows’ta yaptığı değişiklikler de geri alınır). Önceki ayarlarınızın kopyası saklanır.'
           Do = @(@{ L = 'Ayarlar'; Tag = 'nav:settings' }) }
        @{ K = 'help'; Q = ''; W = 'destek bildir bildirmek yardim paketi rapor gonder'
           T = 'Sorun bildirmek'
           A = 'Yardım paketi sürüm, sistem özeti ve son günlükleri tek bir zip dosyasına koyar; kullanıcı adı, bilgisayar adı, IP ve e-posta adresleri silinir. Dosyayı kime göndereceğinize siz karar verirsiniz.'
           Do = @(@{ L = 'Yardımcılar'; Tag = 'kit:home' }) }
    )
}
$script:AskTopics = $null
function Get-AskTopics {
    if ($null -eq $script:AskTopics) { $script:AskTopics = @(Get-AskTopicData) }
    return $script:AskTopics
}

$script:AskStop = @('ve', 'ile', 'bir', 'bu', 'su', 'ne', 'nasil', 'neden', 'nicin', 'icin', 'mi', 'mu', 'cok', 'daha', 'en', 'ben', 'benim', 'bana', 'beni', 'var', 'yok', 'da', 'de', 'ki', 'ama', 'gibi', 'olan', 'olarak',
    'istiyorum', 'lazim', 'gerek', 'yapabilirim', 'yaparim', 'yapilir', 'edebilirim', 'bilgisayar', 'bilgisayarim', 'pc', 'windows', 'the', 'my', 'is', 'how', 'to')

# Her dilin kendi baglaclari: dil dosyasindaki ceviri bosluklu liste olarak gelir; ceviri yoksa yalnizca Turkce liste kullanilir
$script:AskStopMore = 've ile bir bu şu ne nasıl neden için çok daha'

# Saf: metni esleme bicimine getirir: kucuk harf, Latin aksanlari kaldirilmis (ş->s, é->e, ß->ss), Turkce i/I kurali.
# Tablo acik yazilidir: .NET'in Normalize islevi degismez kulturde (sinama ortami) aksan ayirmaz.
$script:AskFoldMap = $null
function Get-AskFoldMap {
    if ($null -ne $script:AskFoldMap) { return $script:AskFoldMap }
    $m = @{}
    $groups = @(
        @('a', 'àáâãäåāăą'), @('c', 'çćčĉċ'), @('d', 'ďđ'), @('e', 'èéêëēĕėęě'), @('g', 'ğĝġģ'), @('h', 'ĥħ'), @('i', 'ìíîïĩīĭįı'),
        @('j', 'ĵ'), @('k', 'ķ'), @('l', 'ĺļľŀł'), @('n', 'ñńņňŉ'), @('o', 'òóôõöøōŏő'), @('r', 'ŕŗř'), @('s', 'şśŝšș'), @('t', 'ţťŧț'),
        @('u', 'ùúûüũūŭůűų'), @('w', 'ŵ'), @('y', 'ýÿŷ'), @('z', 'źżž'), @('ss', 'ß'), @('ae', 'æ'), @('oe', 'œ'), @('е', 'ё'))
    foreach ($g in $groups) { foreach ($ch in ([string]$g[1]).ToCharArray()) { $m[[int]$ch] = [string]$g[0] } }
    $script:AskFoldMap = $m
    return $m
}
function ConvertTo-AskKey([string]$Text) {
    $t = ([string]$Text).Replace([string][char]0x0130, 'i').Replace([string][char]0x0131, 'i').ToLowerInvariant()
    $map = Get-AskFoldMap
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $t.ToCharArray()) {
        $code = [int]$ch
        if ($map.ContainsKey($code)) { [void]$sb.Append($map[$code]) }
        elseif ([System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne [System.Globalization.UnicodeCategory]::NonSpacingMark) { [void]$sb.Append($ch) }
    }
    return $sb.ToString()
}

# Saf: metin Cince/Japonca/Korece harf iceriyor mu (bosluksuz yazilan diller: govde icerme ile eslenir)
function Test-AskCjk([string]$Text) {
    return [regex]::IsMatch([string]$Text, '[\u3040-\u30FF\u3400-\u4DBF\u4E00-\u9FFF\uAC00-\uD7AF]')
}

# Saf: soru metni -> anlamli sozcukler (kucuk harf, sadelestirilmis; baglaclar atilir). Her dilin harfleri korunur.
function Get-AskTokens([string]$Text) {
    $q = ConvertTo-AskKey ([string]$Text)
    $stop = New-Object System.Collections.ArrayList
    foreach ($w in @($script:AskStop)) { [void]$stop.Add($w) }
    foreach ($w in @((ConvertTo-AskKey (Tr $script:AskStopMore)) -split '\s+')) { if ($w -ne '' -and -not $stop.Contains($w)) { [void]$stop.Add($w) } }
    $out = New-Object System.Collections.ArrayList
    foreach ($w in @($q -csplit '[^\p{L}\p{N}]+')) {
        if ($w.Length -lt 2 -or $stop.Contains($w)) { continue }
        if (-not $out.Contains($w)) { [void]$out.Add($w) }
    }
    return , $out.ToArray()
}

# Saf: konunun govdeleri. Dil dosyasinda cevirisi varsa o dilin govdeleri, yoksa Turkce govdeler; ikisi de esleme bicimine getirilir.
function Get-AskStems($Topic) {
    $w = [string]$Topic.W
    $tr = [string](Tr $w)
    $all = $w
    if ($tr -ne '' -and $tr -ne $w) { $all = $w + ' ' + $tr }
    $out = New-Object System.Collections.ArrayList
    foreach ($s in @((ConvertTo-AskKey $all) -split '\s+')) { if ($s -ne '' -and -not $out.Contains($s)) { [void]$out.Add($s) } }
    return , $out.ToArray()
}

# Saf: konu puani. Tam esleme 3; sozcuk govdeyle basliyorsa (govde en az 4 harf) 2; Cince/Japonca/Korece govde sozcugun icinde geciyorsa 3.
function Get-AskScore($Topic, $Tokens) {
    $stems = Get-AskStems $Topic
    $stems = @($stems)
    $score = 0
    foreach ($t in @($Tokens)) {
        $best = 0
        foreach ($s in $stems) {
            if ($t -eq $s) { $best = 3; break }
            if ($s.Length -ge 4 -and $t.Length -gt $s.Length -and $t.StartsWith($s)) { if ($best -lt 2) { $best = 2 } }
            elseif ((Test-AskCjk $s) -and $t.Length -gt $s.Length -and $t.Contains($s)) { $best = 3; break }
        }
        $score += $best
    }
    return $score
}

# Saf: en iyi konular (puani 2 ve uzeri), puana gore; esit puanda tablo sirasi
function Get-AskMatches([string]$Text, [int]$Max = 2) {
    $tok = Get-AskTokens $Text
    $hits = New-Object System.Collections.ArrayList
    if ($tok.Count -eq 0) { return , $hits.ToArray() }
    $i = 0
    foreach ($tp in @(Get-AskTopics)) {
        $s = Get-AskScore $tp $tok
        if ($s -ge 2) { [void]$hits.Add(@{ Topic = $tp; Score = $s; Order = $i }) }
        $i++
    }
    $sorted = @($hits.ToArray() | Sort-Object @{ Expression = { [int]$_.Score }; Descending = $true }, @{ Expression = { [int]$_.Order } })
    return , @($sorted | Select-Object -First $Max)
}

# Saf: soruya cevap.  Commands: komut adi -> aciklama (komut satirinin tablosu)   PageHits: sayfa/eylem aramasinin sonuclari (@{ Text; Tag })
#   Donus: @{ Kind = 'topic' | 'command' | 'pages' | 'none'; Title; Text; Actions = @(@{ L; Tag }); Also = '' }
function Get-AskAnswer([string]$Text, $Commands = $null, $PageHits = @()) {
    $q = ([string]$Text).Trim()
    $res = @{ Kind = 'none'; Title = ''; Text = ''; Actions = @(); Also = '' }
    if ($q -eq '') { return $res }
    $first = ''
    $parts = @((ConvertTo-AskKey $q) -split '\s+' | Where-Object { $_ -ne '' })
    if ($parts.Count -gt 0) { $first = [string]$parts[0] }
    if ($null -ne $Commands -and $first -ne '' -and $first -ne 'yardim' -and $Commands.Contains($first) -and $parts.Count -le 3) {
        $res.Kind = 'command'; $res.Title = 'Komut: ' + $first
        $res.Text = [string]$Commands[$first]
        $res.Actions = @(@{ L = 'Komutu çalıştır'; Tag = ('cmd:' + $q) })
        return $res
    }
    $m = Get-AskMatches $q 2
    if ($m.Count -gt 0) {
        $t = $m[0].Topic
        $res.Kind = 'topic'; $res.Title = [string]$t.T; $res.Text = [string]$t.A; $res.Actions = @($t.Do)
        if ($m.Count -gt 1 -and [int]$m[1].Score -ge 3) { $res.Also = [string]$m[1].Topic.T; $res.AlsoKey = [string]$m[1].Topic.K }
        return $res
    }
    $ph = @(@($PageHits) | Where-Object { $null -ne $_ } | Select-Object -First 4)
    if ($ph.Count -gt 0) {
        $res.Kind = 'pages'; $res.Title = 'Bununla ilgili sayfalar'
        $res.Text = 'Tam bir cevabım yok ama aradığınız bu sayfalardan birinde olabilir.'
        $res.Actions = @($ph | ForEach-Object { @{ L = [string]$_.Text; Tag = [string]$_.Tag } })
        return $res
    }
    $res.Title = 'Bunu bulamadım'
    $res.Text = 'Soruyu birkaç sözcükle, ne olduğunu ya da ne yapmak istediğinizi yazarak deneyin: “bilgisayar yavaş”, “disk doldu”, “internet kopuyor”, “silinen dosya”, “parola üret”.'
    return $res
}

# Saf: bos ekranda gosterilecek ornek sorular
function Get-AskSamples {
    return @(@(Get-AskTopics) | Where-Object { [string]$_.Q -ne '' } | ForEach-Object { [string]$_.Q })
}

function Get-AskTopic([string]$Key) {
    foreach ($t in @(Get-AskTopics)) { if ([string]$t.K -eq $Key) { return $t } }
    return $null
}

# Saf: sol cubuk icin sayfanin alt sekmeleri. Xaml: sayfanin XAML metni. Donus: @(@{ Key; Text })
function Get-PageSubTabs([string]$Xaml) {
    $out = New-Object System.Collections.ArrayList
    if ([string]$Xaml -eq '') { return , $out.ToArray() }
    foreach ($m in [regex]::Matches($Xaml, 'x:Name="[a-z]+_Tab_([A-Za-z0-9]+)" Content="([^"]*)"')) {
        [void]$out.Add(@{ Key = $m.Groups[1].Value; Text = [System.Net.WebUtility]::HtmlDecode($m.Groups[2].Value) })
    }
    return , $out.ToArray()
}

# Saf: aciklama metni tek satira indirilecek kadar uzun mu?
function Test-DescLong([string]$Text, [int]$Limit = 64) {
    return (([string]$Text).Trim().Length -gt $Limit)
}

# Saf: sayfa XAML'inde aciklama paragraflarini isaretler (TxtDim bicimli, satir kaydirmali, adsiz TextBlock -> Tag="desc")
function Add-DescTags([string]$Xaml) {
    return [regex]::Replace([string]$Xaml, '<TextBlock (?![^>]*\bTag=)(?![^>]*x:Name=)(?=[^>]*Style="\{DynamicResource TxtDim\}")(?=[^>]*TextWrapping="Wrap")', '<TextBlock Tag="desc" ')
}
