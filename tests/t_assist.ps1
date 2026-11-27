. "$PSScriptRoot/lib.ps1"
# Asistan ve kullanım kolaylığı (mods\152_assist_core.ps1, 153_ux_ui.ps1, patches\p66_kullanim.py):
# soru eşleştirme, cevap ve eylemler; sol çubuk alt sekme menüsü; kısa açıklamalar; arayüz bağlantıları.
Import-Fn 'ConvertTo-AsciiKey', 'Get-AskFoldMap', 'ConvertTo-AskKey', 'Test-AskCjk', 'Get-AskStems', 'Get-AskTokens', 'Get-AskScore', 'Get-AskMatches', 'Get-AskAnswer', 'Get-AskSamples', 'Get-AskTopic', 'Get-PageSubTabs', 'Test-DescLong', 'Add-DescTags', 'Get-TitleLevel'
Import-Fn 'Get-AskTopicData', 'Get-AskTopics'
Import-Var 'AskStop', 'CmdDefs', 'BoardActions', 'PageTitles', 'TlTabs', 'ApTabs', 'ClTabs', 'NwTabs', 'BkTabs', 'SlvTabs'
$script:AskTopics = $null
Assert-True (@(Get-AskTopics).Count -ge 24 -and $null -ne $script:AskTopics) 'konu tablosu ilk kullanımda yüklenir'
$src = [System.IO.File]::ReadAllText($script:TestPath)

# ======================= 1) sözcükler =======================
Assert-Eq ((Get-AskTokens 'Bilgisayarım çok YAVAŞ açılıyor!') -join ',') 'yavas,aciliyor' 'Türkçe harfler sadeleşir, bağlaçlar ve dolgu sözcükleri atılır'
Assert-Eq (Get-AskTokens '   ').Count 0 'boş soru'
Assert-Eq ((Get-AskTokens 'disk disk DİSK') -join ',') 'disk' 'yinelenen sözcük bir kez'
# çok dilli: her dilin harfleri korunur, aksanlar sadeleşir; dil dosyası gövde ve bağlaç verebilir
Import-Var 'AskStopMore'
Assert-Eq (ConvertTo-AskKey 'Problème für Straße İSTANBUL') 'probleme fur strasse istanbul' 'aksan sadeleşir, ß→ss, İ→i'
Assert-Eq ((Get-AskTokens 'Mon ordinateur est très lent') -join ',') 'mon,ordinateur,est,tres,lent' 'Fransızca sözcükler korunur'
Assert-Eq ((Get-AskTokens 'компьютер очень медленный') -join ',') 'компьютер,очень,медленный' 'Kiril harfleri korunur'
Assert-Eq ((Get-AskTokens '电脑很慢') -join ',') '电脑很慢' 'Çince metin tek sözcük olarak kalır'
Assert-True (Test-AskCjk '慢') 'CJK tanınır'
Assert-True (-not (Test-AskCjk 'slow')) 'Latin harf CJK değildir'
Assert-Eq (Get-AskScore @{ W = 'yavas' } @('电脑很慢')) 0 'Çince soru Türkçe gövdeyle eşleşmez'
function Tr($t) { if ($t -eq 'yavas kasiyor') { return '慢 卡顿' }; if ($t -eq $script:AskStopMore) { return 'the my is' }; return $t }
Assert-Eq (Get-AskScore @{ W = 'yavas kasiyor' } @('电脑很慢')) 3 'çeviri gövdesi (CJK) sözcüğün içinde geçince 3 puan'
Assert-Eq ((Get-AskStems @{ W = 'yavas kasiyor' }) -join ',') 'yavas,kasiyor,慢,卡顿' 'gövdeler: Türkçe + çeviri'
Assert-Eq ((Get-AskTokens 'my computer is slow') -join ',') 'computer,slow' 'dil dosyasındaki bağlaçlar da atılır'
function Tr($t) { return $t }

# ======================= 2) eşleştirme =======================
function Top([string]$q) { $m = Get-AskMatches $q 1; if ($m.Count -eq 0) { return '' }; return [string]$m[0].Topic.K }
$cases = [ordered]@{
    'bilgisayarım çok yavaşladı' = 'slow'; 'pc kasıyor' = 'slow'; 'diskim doldu yer kalmadı' = 'disk'; 'gereksiz dosyaları temizle' = 'disk'
    'internet çok yavaş' = 'net'; 'wifi kopuyor' = 'net'; 'güçlü bir parola üret' = 'pw'; 'şifre oluştur' = 'pw'
    'dosyamı şifrelemek istiyorum' = 'crypt'; 'bitlocker nasıl açılır' = 'crypt'; 'windows veri gönderiyor mu' = 'priv'; 'telemetriyi kapat' = 'priv'
    'oyunda fps düşük' = 'game'; 'laptop çok ısınıyor' = 'heat'; 'fan sesi çok' = 'heat'; 'pil çabuk bitiyor' = 'power'
    'açılışta başlayan programlar' = 'boot'; 'gereksiz hizmetleri kapat' = 'svc'; 'sürücü güncelleme' = 'upd'
    'yaptığım ayarı geri almak istiyorum' = 'undo'; 'yedek almak' = 'backup'; 'sildiğim dosyayı kurtar' = 'recover'
    'bilgisayarı satacağım kalıcı sil' = 'wipe'; 'virüs var mı' = 'sec'; 'mavi ekran veriyor' = 'crash'
    'format attım yeni kurulum' = 'newpc'; 'açık kaynak program kur' = 'apps'; 'dosyaları toplu yeniden adlandır' = 'rename'
    'ağdaki cihazlar kimler' = 'lan'; 'işlemci ve ram özellikleri' = 'hw'; 'koyu tema' = 'look'; 'ayarları sıfırla' = 'reset'
}
foreach ($q in $cases.Keys) { Assert-Eq (Top $q) ([string]$cases[$q]) ("soru -> konu: $q") }
Assert-Eq (Top 'asdfgh qwerty') '' 'ilgisiz metin eşleşmez'
Assert-Eq (Top '') '' 'boş soru eşleşmez'
# kök eşleşmesi: en az dört harfli gövde, sözcüğün başında
Assert-Eq (Get-AskScore @{ W = 'yavas' } @('yavasliyor')) 2 'gövdeyle başlayan sözcük 2 puan'
Assert-Eq (Get-AskScore @{ W = 'yavas' } @('yavas')) 3 'tam eşleşme 3 puan'
Assert-Eq (Get-AskScore @{ W = 'ram' } @('ramazan')) 0 'üç harfli gövde yalnızca tam eşleşir'
Assert-Eq (Get-AskScore @{ W = 'disk' } @('dis')) 0 'sözcük gövdeden kısaysa eşleşmez'
$m2 = Get-AskMatches 'internet yavaş' 2
Assert-True ($m2.Count -eq 2 -and [string]$m2[0].Topic.K -eq 'net') 'iki konu eşleşirse puanı yüksek olan başta'

# ======================= 3) konu tablosu tutarlı =======================
$keys = @($script:AskTopics | ForEach-Object { [string]$_.K })
Assert-Eq @($keys | Select-Object -Unique).Count $keys.Count 'konu anahtarları benzersiz'
Assert-True ($script:AskTopics.Count -ge 24) 'en az 24 konu'
$tabsOf = @{ tools = $script:TlTabs; apps = $script:ApTabs; clean = $script:ClTabs; network = $script:NwTabs; backup = $script:BkTabs; solve = $script:SlvTabs }
$kitViews = @('home', 'pw', 'ren', 'score', 'net', 'alt', 'setup')
foreach ($t in $script:AskTopics) {
    Assert-True ([string]$t.T -ne '' -and ([string]$t.A).Length -ge 60 -and ([string]$t.A).Length -le 420) ('başlık ve 60-420 karakterlik cevap: ' + [string]$t.K)
    Assert-True (([string]$t.W) -cmatch '^[a-z0-9 ]+$') ('gövdeler küçük harf ve sade: ' + [string]$t.K)
    Assert-True (@($t.Do).Count -ge 1 -and @($t.Do).Count -le 4) ('1-4 eylem: ' + [string]$t.K)
    foreach ($a in @($t.Do)) {
        $tag = [string]$a.Tag; $p = $tag.Split(':')
        $ok = $false
        switch ($p[0]) {
            'nav' { $ok = $script:PageTitles.Contains($p[1]) }
            'sub' { $ok = ($p.Count -eq 3 -and $script:PageTitles.Contains($p[1]) -and $tabsOf.ContainsKey($p[1]) -and (@($tabsOf[$p[1]]) -contains $p[2])) }
            'act' { $ok = $script:BoardActions.Contains($p[1]) }
            'kit' { $ok = ($kitViews -contains $p[1]) }
            'cmd' { $ok = $script:CmdDefs.Contains($p[1]) }
        }
        Assert-True $ok ('eylem geçerli bir hedefe gidiyor: ' + [string]$t.K + ' / ' + $tag)
        Assert-True ([string]$a.L -ne '') ('eylem etiketi dolu: ' + $tag)
    }
}
$smp = @(Get-AskSamples)
Assert-True ($smp.Count -ge 5 -and $smp.Count -le 8) 'örnek soru sayısı 5-8'
foreach ($q in $smp) { Assert-True ((Top $q) -ne '') ("örnek soru bir konuya gidiyor: $q") }
Assert-True ($null -ne (Get-AskTopic 'slow') -and $null -eq (Get-AskTopic 'yok')) 'konu anahtarla bulunur'

# ======================= 4) cevap =======================
$a = Get-AskAnswer 'bilgisayar yavaş' $script:CmdDefs @()
Assert-True ($a.Kind -eq 'topic' -and $a.Title -ne '' -and @($a.Actions).Count -ge 2) 'konu cevabı: başlık, metin, eylemler'
$a = Get-AskAnswer 'ping 8.8.8.8' $script:CmdDefs @()
Assert-True ($a.Kind -eq 'command' -and [string]$a.Actions[0].Tag -eq 'cmd:ping 8.8.8.8') 'komut adıyla başlayan girdi komut olarak önerilir'
$a = Get-AskAnswer 'durum' $script:CmdDefs @()
Assert-Eq $a.Kind 'command' 'tek sözcüklük komut'
$a = Get-AskAnswer 'yardım paketi nasıl hazırlanır' $script:CmdDefs @()
Assert-Eq $a.Kind 'topic' '"yardım" ile başlayan soru komut sayılmaz'
$a = Get-AskAnswer 'internet yavaş' $script:CmdDefs @()
Assert-True ($a.Kind -eq 'topic' -and [string]$a.Also -ne '' -and [string]$a.AlsoKey -eq 'slow') 'yakın ikinci konu “İlgili” olarak eklenir'
$a = Get-AskAnswer 'zzz qqq' $script:CmdDefs @(@{ Text = 'Araçlar'; Tag = 'nav:tools' }, $null, @{ Text = 'Geçmiş'; Tag = 'nav:history' })
Assert-True ($a.Kind -eq 'pages' -and @($a.Actions).Count -eq 2 -and [string]$a.Actions[0].Tag -eq 'nav:tools') 'konu yoksa sayfa araması sonuçları'
$a = Get-AskAnswer 'zzz qqq' $script:CmdDefs @()
Assert-True ($a.Kind -eq 'none' -and [string]$a.Text -ne '' -and @($a.Actions).Count -eq 0) 'hiçbir şey bulunamazsa nasıl sorulacağı anlatılır'
Assert-Eq (Get-AskAnswer '  ' $script:CmdDefs @()).Kind 'none' 'boş girdi'
Assert-Eq (Get-AskAnswer 'bilgisayar yavaş' $null @()).Kind 'topic' 'komut tablosu olmadan da çalışır'

# ======================= 5) alt sekmeler =======================
$x = '<RadioButton x:Name="tl_Tab_win" Content="Windows ara&#x00E7;lar&#x0131;" Tag="win"/><RadioButton x:Name="tl_Tab_kit" Content="Yard&#x0131;mc&#x0131;lar" Tag="kit"/><Button x:Name="tl_Refresh" Content="Yenile"/>'
$tabs = Get-PageSubTabs $x
Assert-True ($tabs.Count -eq 2 -and $tabs[0].Key -eq 'win' -and $tabs[1].Text -eq ('Yard' + [char]0x0131 + 'mc' + [char]0x0131 + 'lar')) 'sekme anahtarı ve çözülmüş başlık'
Assert-Eq (Get-PageSubTabs '').Count 0 'boş XAML'
Import-Var 'Page_tools', 'Page_settings'
$tt = Get-PageSubTabs ([string]$script:Page_tools)
Assert-Eq (@($tt | ForEach-Object { $_.Key }) -join ',') ($script:TlTabs -join ',') 'Araçlar sayfasının sekmeleri XAML içinden aynı sırayla okunur'
Assert-Eq (Get-PageSubTabs ([string]$script:Page_settings)).Count 0 'sekmesi olmayan sayfa'
# sol çubuk menüsü: sayfanın alt sekmeleri tek tek gelir (gerçek bilgisayarda 7 yerine 1 öğe okunuyordu)
Import-Fn 'Get-RailSubItems'
$script:PageSubCache = @{}
$ri = Get-RailSubItems 'tools'
Assert-Eq @($ri).Count @($script:TlTabs).Count 'sol çubuk: Araçlar için her alt sekme ayrı öğe'
Assert-Eq ([string]$ri[0].Tag) 'sub:tools:win' 'sol çubuk: öğe etiketi sayfa ve sekmeyi taşır'
Assert-Eq ([string]$ri[@($ri).Count - 1].Tag) 'sub:tools:kit' 'sol çubuk: son öğe Yardımcılar'
Assert-Eq @(Get-RailSubItems 'settings').Count 0 'sol çubuk: sekmesi olmayan sayfada menü öğesi yok'
Assert-True ($script:PageSubCache.ContainsKey('tools')) 'sol çubuk: sonuç önbelleğe alınır'

# ======================= 6) kısa açıklamalar =======================
Assert-True (-not (Test-DescLong 'Kısa durum bilgisi')) 'kısa metin olduğu gibi kalır'
Assert-True (Test-DescLong ('a' * 65)) '64 karakterden uzun metin tek satıra iner'
$px = '<StackPanel><TextBlock Text="a" Style="{DynamicResource TxtDim}" TextWrapping="Wrap"/><TextBlock x:Name="st_Note" Style="{DynamicResource TxtDim}" TextWrapping="Wrap"/><TextBlock Text="b" Style="{DynamicResource TxtBody}" TextWrapping="Wrap"/><TextBlock Text="c" Style="{DynamicResource TxtDim}"/><TextBlock Tag="x" Text="d" Style="{DynamicResource TxtDim}" TextWrapping="Wrap"/></StackPanel>'
$tagged = Add-DescTags $px
Assert-Eq ([regex]::Matches($tagged, 'Tag="desc"').Count) 1 'yalnızca adsız, TxtDim biçimli ve kaydırmalı paragraf işaretlenir'
Assert-True ($tagged.Contains('<TextBlock Tag="desc" Text="a"')) 'işaret doğru öğede'
Assert-True ($tagged.Contains('<TextBlock x:Name="st_Note" Style')) 'adlı (içeriği değişen) öğe işaretlenmez'
Assert-Eq (Add-DescTags $tagged) $tagged 'ikinci kez işaretlemek metni değiştirmez'
Assert-True ($src.Contains('    try { Set-DescCompact $el } catch { }')) 'liste satırlarında açıklama kısaltılır'
Assert-True ($src.Contains('    $xaml = Add-DescTags ([string]$xaml)')) 'sayfa açılırken paragraflar işaretlenir'
Assert-True ($src.Contains('    try { [void](Set-PageDescCompact $root) } catch { }')) 'sayfa açılırken paragraflar kısaltılır'
Assert-True ($src.Contains('x:Name="st_FullDesc"') -and $src.Contains('$s.FullDesc = ($ui.st_FullDesc.IsChecked -eq $true)') -and $src.Contains('$ui.st_FullDesc.IsChecked = ($script:Settings.FullDesc -eq $true)')) 'Ayarlar: açıklamaları tam göster'
Assert-True ([regex]::IsMatch($src, 'FullDesc\s+= \$false')) 'varsayılan: kısa açıklama'

# ======================= 7) arayüz bağlantıları =======================
foreach ($n in @('AskCapsule', 'BtnAsk', 'TxtAskHint', 'AskOverlay', 'AskCard', 'AskScroll', 'AskChat', 'AskChips', 'AskInput', 'AskSend', 'AskClose')) {
    Assert-Eq ([regex]::Matches($src, 'x:Name="' + $n + '"').Count) 1 ("XAML öğesi bir kez tanımlı: $n")
}
Assert-True ($src.IndexOf('x:Name="AskOverlay"') -lt $src.IndexOf('x:Name="Overlay"')) 'Asistan paneli onay kutusunun altında kalır'
Assert-True ($src.Contains("    try { Initialize-UxExtras } catch { Write-CrashLog ('Kullanim: ' + `$_.Exception.Message) }")) 'pencere kurulurken bağlanır'
Assert-True ($src.Contains('if ($null -ne $ui.TxtAskHint) { Set-Visible $ui.TxtAskHint ($Level -lt 1) }')) 'dar pencerede “Sor ya da ara” yazısı gizlenir'
Assert-True ($src.Contains("elseif (`$kind -eq 'sub') { `$sp = `$arg.Split(':')")) 'menü etiketi alt sekmeye gider'
Assert-True ($src.Contains('        $hdr.Add_MouseEnter($script:H_RailHdrEnter)')) 'grup başlığı üzerine gelince açılır'
Assert-True ($src.Contains('if ($g.Peek -eq $true -and [bool]$g.Open) { $g.Peek = $false }')) 'geçici açılan gruba tıklamak onu kalıcı yapar'
Assert-True ($src.Contains('        $b.Add_MouseEnter($script:H_FlyHover)')) 'simge menüsü üzerine gelince açılır'
Assert-True ($src.Contains('[System.Windows.Input.Key]::F1')) 'F1 Asistan penceresini açar'
foreach ($f in @('Show-Ask', 'Hide-Ask', 'Invoke-Ask', 'Invoke-AskTag', 'Add-AskBot', 'Add-AskUser', 'Initialize-Ask', 'Initialize-RailHover', 'Initialize-UxExtras', 'Show-HoverMenu', 'Close-HoverMenu', 'Start-HoverDwell',
        'Get-RailSubItems', 'Close-RailPeek', 'Set-TextCompact', 'Set-DescCompact', 'Set-PageDescCompact')) {
    Assert-True ([regex]::IsMatch($src, '(?m)^function ' + [regex]::Escape($f) + '\b')) ("işlev tanımlı: $f")
}
# başlık basamağı: Asistan yazısının genişliği slogan kazancına eklenir (hesap işlevi aynı)
Assert-Eq (Get-TitleLevel 1400 @{ L = 400; C = 600; R = 300; Tag = 200; Pill = 60; Lab = 80 }) 0 'geniş pencere: hepsi görünür'
Assert-Eq (Get-TitleLevel 1200 @{ L = 400; C = 600; R = 300; Tag = 200; Pill = 60; Lab = 80 }) 1 'dar pencere: slogan ve Asistan yazısı gizlenir'

Show-Result
