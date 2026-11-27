# 7.2.0: (1) koddan üretilen öğelerin fırça renkleri tema değişince güncellenir (eski renkte kalan günlük satırları olmaz),
#        (2) duyarlı yerleşim: dar / kısa pencerede ve yüksek yakınlaştırmada günlük, komut satırı, başlık çubuğu ve durum panosu.
# Linux'ta WPF yok: renk ve fırça türleri küçük sahte sınıflarla taklit edilir; gerçek işlevler AST ile derlenmiş betikten alınır.
. "$PSScriptRoot/lib.ps1"

Add-Type -ReferencedAssemblies @([psobject].Assembly.Location, 'System.Collections', 'System.Runtime', 'netstandard') -TypeDefinition @'
using System;
namespace System.Windows.Media {
    public struct Color : IEquatable<Color> {
        public byte A; public byte R; public byte G; public byte B;
        public Color(byte a, byte r, byte g, byte b) { A = a; R = r; G = g; B = b; }
        public bool Equals(Color o) { return A == o.A && R == o.R && G == o.G && B == o.B; }
        public override bool Equals(object o) { return (o is Color) && Equals((Color)o); }
        public override int GetHashCode() { return (A << 24) | (R << 16) | (G << 8) | B; }
        public override string ToString() { return "#" + A.ToString("X2") + R.ToString("X2") + G.ToString("X2") + B.ToString("X2"); }
        public static bool operator ==(Color a, Color b) { return a.Equals(b); }
        public static bool operator !=(Color a, Color b) { return !a.Equals(b); }
    }
    public class SolidColorBrush {
        public Color Color; public bool IsFrozen; public double Opacity = 1.0;
        public SolidColorBrush() { }
        public SolidColorBrush(Color c) { Color = c; }
        public SolidColorBrush Clone() { var b = new SolidColorBrush(Color); b.Opacity = Opacity; return b; }
    }
    public class LinearGradientBrush { public bool IsFrozen; }
}
'@

Import-Fn 'Get-Br', 'Sync-CodeBrushes', 'Get-CodeBrushProblems', 'Get-PageWidth', 'Get-PageHeight', 'Test-LogFits', 'Test-CmdFits', 'Test-PanelNarrow', 'Get-TitleLevel', 'Test-LogAutoOpen'
Import-Fn 'Get-LayoutDefaults', 'Get-RailWidth', 'New-SmokeStep', 'New-SmokeQueue', 'Get-SmokeActions', 'Add-SmokeLookParts', 'Add-SmokeBoardEditParts'
Import-Var 'RespMinPageW', 'RespMinPageH', 'RespWidePage', 'RespChromeH', 'RespPageMargin', 'SmokeThemes', 'SmokeLayouts', 'SmokeScopes', 'SmokeDesigns', 'SmokeGlassOps', 'SmokeGlassThemeOp', 'SmokePresets'

function New-Col([int]$A, [int]$R, [int]$G, [int]$B) { return [System.Windows.Media.Color]::new([byte]$A, [byte]$R, [byte]$G, [byte]$B) }

# ======================= 1) kod fırçaları: özel kopya + eşitleme =======================
$global:Res = @{}
$script:Win = New-Object psobject
Add-Member -InputObject $script:Win -MemberType ScriptMethod -Name FindResource -Value { param($k) if ($global:Res.ContainsKey($k)) { return $global:Res[$k] }; throw ('kaynak yok: ' + $k) }
Add-Member -InputObject $script:Win -MemberType ScriptMethod -Name TryFindResource -Value { param($k) if ($global:Res.ContainsKey($k)) { return $global:Res[$k] }; return $null }
$script:BrushCache = @{}
$ui = @{}

$neonText = New-Col 255 0xE2 0xE8 0xF8
$whiteText = New-Col 255 0x16 0x20 0x33
$res1 = [System.Windows.Media.SolidColorBrush]::new($neonText)
$res1.IsFrozen = $true       # stillerde StaticResource ile kullanılan fırçalar WPF'ce dondurulur
$global:Res['BrText'] = $res1

$b1 = Get-Br 'BrText'
Assert-True ($b1 -is [System.Windows.Media.SolidColorBrush]) 'Get-Br: SolidColorBrush döner'
Assert-True (-not [object]::ReferenceEquals($b1, $res1)) 'Get-Br: kaynaktaki dondurulmuş fırçayı değil, özel kopyayı verir'
Assert-True ($b1.IsFrozen -eq $false) 'Get-Br: özel kopya dondurulmamıştır (rengi yerinde değiştirilebilir)'
Assert-True ($b1.Color -eq $neonText) 'Get-Br: kopya kaynağın rengiyle başlar'
Assert-True ([object]::ReferenceEquals((Get-Br 'BrText'), $b1)) 'Get-Br: aynı anahtar her seferinde aynı nesneyi verir (öğeler birlikte güncellenir)'

# bir öğe (günlük satırı gibi) fırçayı tutuyor
$el = New-Object psobject -Property @{ Foreground = $b1 }
Assert-Eq (@(Get-CodeBrushProblems).Count) 0 'başlangıçta kod fırçası uyuşmazlığı yok'

# tema değişti: Set-BrushColor'un yedek yolu dondurulmuş fırçayı sözlükte yeni bir nesneyle değiştirir
$res2 = [System.Windows.Media.SolidColorBrush]::new($whiteText)
$global:Res['BrText'] = $res2
$p = @(Get-CodeBrushProblems)
Assert-Eq ($p -join ',') 'BrText' 'tema değişince eşitlemeden önce eski renkli fırça yakalanır (beyaz temada eski neon yazı bu hatadır)'
$n = Sync-CodeBrushes
Assert-Eq $n 1 'Sync-CodeBrushes: rengi değişen fırça sayısı'
Assert-True ($el.Foreground.Color -eq $whiteText) 'fırçayı tutan öğe yeni rengi alır (öğeye dokunulmadan)'
Assert-True ([object]::ReferenceEquals((Get-Br 'BrText'), $b1)) 'eşitlemeden sonra da aynı fırça nesnesi kullanılır'
Assert-Eq (@(Get-CodeBrushProblems).Count) 0 'eşitlemeden sonra uyuşmazlık kalmaz'
Assert-Eq (Sync-CodeBrushes) 0 'ikinci eşitleme hiçbir şeyi değiştirmez'

# yerinde değişen (dondurulmamış) kaynak fırça da izlenir
$res2.Color = $neonText
Assert-Eq (@(Get-CodeBrushProblems) -join ',') 'BrText' 'kaynak fırçanın rengi yerinde değişince de uyuşmazlık görülür'
[void](Sync-CodeBrushes)
Assert-True ($b1.Color -eq $neonText) 'yerinde değişen kaynak rengi de kopyaya geçer'

# alfa kanalı korunur
$global:Res['BrOverlay'] = [System.Windows.Media.SolidColorBrush]::new((New-Col 0xD0 0x05 0x08 0x10))
$ov = Get-Br 'BrOverlay'
Assert-Eq ([string]$ov.Color) '#D0050810' 'yarı saydam renk (alfa) korunur'

# SolidColorBrush olmayan kaynak olduğu gibi verilir ve eşitlemeyi bozmaz
$grad = [System.Windows.Media.LinearGradientBrush]::new()
$global:Res['BrGrad'] = $grad
Assert-True ([object]::ReferenceEquals((Get-Br 'BrGrad'), $grad)) 'SolidColorBrush olmayan kaynak aynen verilir'
Assert-Eq (Sync-CodeBrushes) 0 'SolidColorBrush olmayan önbellek girdisi eşitlemeyi bozmaz'

# günlük / komut satırı satırları önbellekteki fırçayı tutmalı
$okRow = New-Object psobject -Property @{ Foreground = (Get-Br 'BrText') }
$ui = @{
    LogStack = (New-Object psobject -Property @{ Children = @($okRow, $okRow) })
    CmdOut = (New-Object psobject -Property @{ Children = @($okRow) })
}
Assert-Eq (@(Get-CodeBrushProblems).Count) 0 'satırlar önbellekteki fırçayı tutuyorsa sorun yok'
$stray = New-Object psobject -Property @{ Foreground = $res1 }
$ui.LogStack.Children = @($okRow, $stray, $stray)
$p = @(Get-CodeBrushProblems)
Assert-Eq $p.Count 1 'önbellek dışı fırçalı günlük satırı yakalanır'
Assert-True ($p[0] -like 'LogStack*2*') 'sorun metni kaç satırın etkilendiğini söyler'

# ======================= 2) duyarlı yerleşim: saf hesaplar =======================
Assert-Eq $script:RespMinPageW 700 'günlük için en az sayfa genişliği 700 px'
Assert-Eq $script:RespMinPageH 450 'komut satırı için en az sayfa yüksekliği 450 px'
Assert-Eq $script:RespWidePage 940 'durum panosu iki sütun için en az 940 px ister (4 çember x 108 px)'
Assert-Eq (Get-PageWidth 1380 1.0 72 330) 960 'ayrıntılı, 1380 px, %100: sayfa 960 px'
Assert-Eq (Get-PageWidth 1060 1.0 72 330) 640 'ayrıntılı, 1060 px, %100: sayfa 640 px'
Assert-Eq (Get-PageWidth 1380 1.3 72 330) 642 'ayrıntılı, 1380 px, %130: sayfa 642 px'
Assert-Eq (Get-PageWidth 1380 1.0 200 360) 802 'hacker, 1380 px, %100: sayfa 802 px'
Assert-Eq (Get-PageWidth 1380 1.0 54 0) 1308 'kompakt (günlük kapalı): sayfa 1308 px'
Assert-Eq (Get-PageWidth 1380 0 72 330) 960 'sıfır yakınlaştırma %100 sayılır (sıfıra bölme yok)'
Assert-Eq (Get-PageHeight 840 1.0 176) 582 'ayrıntılı, 840 px: sayfa yüksekliği 582 px'
Assert-Eq (Get-PageHeight 660 1.0 176) 402 'ayrıntılı, 660 px: sayfa yüksekliği 402 px'
Assert-Eq (Get-PageHeight 840 1.3 176) 405 'ayrıntılı, 840 px, %130: sayfa yüksekliği 405 px'
Assert-Eq (Get-PageHeight 840 1.0 0) 758 'komut satırı kapalı: sayfa yüksekliği 758 px'

# günlük (açıkken sayfaya yer kalıyor mu)
Assert-True (Test-LogFits 1380 1.0 72 330) 'varsayılan pencerede günlük sığar'
Assert-True (-not (Test-LogFits 1060 1.0 72 330)) 'en küçük pencerede günlük sığmaz'
Assert-True (-not (Test-LogFits 1380 1.3 72 330)) '%130 yakınlaştırmada günlük sığmaz'
Assert-True (Test-LogFits 1380 1.2 72 330) '%120 yakınlaştırmada günlük hâlâ sığar (730 px)'
Assert-True (Test-LogFits 1380 1.0 200 360) 'hacker yerleşimi varsayılan pencerede sığar (802 px)'
Assert-True (-not (Test-LogFits 1380 1.1 200 360)) 'hacker yerleşimi %110 yakınlaştırmada sığmaz'
Assert-True (Test-LogFits 1920 1.3 72 330) 'tam ekranda %130 yakınlaştırmada da günlük sığar'
# komut satırı
Assert-True (Test-CmdFits 840 1.0 160) 'varsayılan pencerede komut satırı sığar'
Assert-True (-not (Test-CmdFits 660 1.0 160)) 'en küçük pencerede komut satırı sığmaz'
Assert-True (-not (Test-CmdFits 840 1.3 160)) '%130 yakınlaştırmada komut satırı sığmaz'
Assert-True (Test-CmdFits 840 1.2 160) '%120 yakınlaştırmada komut satırı sığar (454 px)'
Assert-True (Test-CmdFits 840 1.0 200) 'hacker (200 px komut satırı) varsayılan pencerede sığar'
Assert-True (-not (Test-CmdFits 840 1.2 200)) 'hacker %120 yakınlaştırmada komut satırı sığmaz'
# durum panosu
Assert-True (-not (Test-PanelNarrow 960)) '960 px: iki sütun'
Assert-True (-not (Test-PanelNarrow 940)) '940 px: iki sütun (sınır dahil)'
Assert-True (Test-PanelNarrow 939) '939 px: tek sütun'
Assert-True (Test-PanelNarrow 802) 'hacker varsayılan: tek sütun'
# iki sütunda sol sütun, dört çember (108 px) ve trafik sütunu için yeter mi: 940 - 6 - 10 - 316 = 608; 608 - 30 = 578; 578 / 5.35 = 108
$leftAt940 = $script:RespWidePage - 6 - 10 - 316
Assert-True ((($leftAt940 - 30) / 5.35) -ge 107.9) 'iki sütun eşiğinde her gösterge sütunu en az 108 px'
$singleAtMin = $script:RespMinPageW - 6 - 10
Assert-True ((($singleAtMin - 30) / 5.35) -ge 108) 'tek sütunda günlük eşiğinin altına inmeden çemberler sığar'

# günlük açılma kararı (işlem başlayınca)
$script:RespLogFits = $true
foreach ($l in @('Ayrintili', 'Hacker')) { $script:LayoutName = $l; Assert-True (Test-LogAutoOpen) ($l + ': yer varsa işlem başlayınca günlük açılır') }
foreach ($l in @('Kompakt', 'Sade')) { $script:LayoutName = $l; Assert-True (-not (Test-LogAutoOpen)) ($l + ': işlem başlayınca günlük kendiliğinden açılmaz') }
$script:RespLogFits = $false
foreach ($l in @('Ayrintili', 'Hacker', 'Kompakt', 'Sade')) { $script:LayoutName = $l; Assert-True (-not (Test-LogAutoOpen)) ($l + ': pencere darsa günlük açılmaz') }

# başlık çubuğu basamakları
$nat = @{ L = 450.0; C = 407.0; R = 480.0; Tag = 290.0; Pill = 40.0; Lab = 110.0 }
Assert-Eq (Get-TitleLevel 1380 $nat) 0 'geniş pencerede hiçbir şey gizlenmez'
Assert-Eq (Get-TitleLevel 1351 $nat) 0 'tam sığdığı genişlikte gizleme yok'
Assert-Eq (Get-TitleLevel 1350 $nat) 1 'bir piksel azalınca önce slogan gizlenir'
Assert-Eq (Get-TitleLevel 1060 $nat) 2 'en küçük pencerede sayfa adı kutusu da daralır'
Assert-Eq (Get-TitleLevel 1000 $nat) 3 'çok darsa etiketler de gizlenir'
$prev = 0; $mono = $true
foreach ($w in 1600..900) {
    if ($w % 10 -ne 0) { continue }
    $lv = Get-TitleLevel $w $nat
    if ($lv -lt $prev) { $mono = $false }
    $prev = $lv
}
Assert-True $mono 'pencere daraldıkça seviye azalmaz (titreşim yok)'
$fitsAll = $true
foreach ($w in 1000..1600) {
    $lv = Get-TitleLevel $w $nat
    $need = 450.0 + 407.0 + 480.0
    if ($lv -ge 1) { $need -= 290.0 }
    if ($lv -ge 2) { $need -= 40.0 }
    if ($lv -lt 3 -and $need -gt ($w - 14)) { $fitsAll = $false }
}
Assert-True $fitsAll 'seçilen seviyede başlık çubuğu sığar (3. seviye son çaredir)'
Assert-Eq (Get-TitleLevel 1380 (@{ L = 1.0; C = 1.0; R = 1.0; Tag = 0.0; Pill = 0.0; Lab = 0.0 })) 0 'küçük ölçüler hep seviye 0'

# ======================= 3) derlenmiş betikte bağlantılar =======================
$text = [System.IO.File]::ReadAllText($env:MM_BUILD)
$fns = @(Get-AstFunctions)
function Get-FnText([string]$Name) {
    $f = @($fns | Where-Object { $_.Name -eq $Name }) | Select-Object -Last 1
    if ($null -eq $f) { return '' }
    return [string]$f.Extent.Text
}
foreach ($nm in @('TitleLeft', 'TitleCenter', 'TitleRight', 'TitlePill', 'TxtTitleSep', 'TxtJobLbl', 'TxtConnLbl', 'TxtTagline')) {
    Assert-Eq ([regex]::Matches($text, 'x:Name="' + $nm + '"')).Count 1 ('ana pencere XAML: ' + $nm + ' adı bir kez tanımlı')
}
Assert-True ((Get-FnText 'Set-AppTheme') -match 'Sync-CodeBrushes') 'Set-AppTheme: kod fırçalarını eşitler'
Assert-True ((Get-FnText 'Set-BrushColor') -notmatch 'BrushCache') 'Set-BrushColor: koda özel fırça önbelleğine dokunmaz'
Assert-True ((Get-FnText 'Get-Br') -match 'Clone\(\)') 'Get-Br: kaynağın kopyasını verir'
Assert-Eq (@($fns | Where-Object { $_.Name -eq 'Get-Br' }).Count) 1 'Get-Br tek tanımlı'
Assert-True ($text -match '\$ui\.BtnLogToggle\.Add_Click\(\{ Invoke-Safe \{ Switch-LogPanel \}') 'günlük düğmesi Switch-LogPanel çağırır'
$busy = Get-FnText 'Set-BusyUi'
Assert-True ($busy -match 'Test-LogAutoOpen' -and $busy -notmatch 'ArgumentList 330') 'Set-BusyUi: günlük yalnızca izin varsa açılır'
Assert-True ((Get-FnText 'Switch-CmdPanel') -match '\$script:CmdAutoOff = \$false') 'Switch-CmdPanel: elle değişiklik kendiliğinden kapanma durumunu sıfırlar'
Assert-True ((Get-FnText 'Switch-LogPanel') -match '\$script:LogAutoOff = \$false') 'Switch-LogPanel: elle değişiklik kendiliğinden kapanma durumunu sıfırlar'
Assert-True ((Get-FnText 'Build-Page') -match "Set-PanelReflow \`$root") 'sayfa kurulunca durum panosu yerleşimi uygulanır'
Assert-True ($text -match 'try \{ Initialize-Responsive \} catch') 'açılışta Initialize-Responsive çağrılır'
Assert-True ((Get-FnText 'Initialize-Responsive') -match 'Add_SizeChanged') 'Initialize-Responsive: pencere boyutu değişimini dinler'
Assert-True ((Get-FnText 'Set-AppLayout') -match 'Reset-Responsive') 'Set-AppLayout: yerleşim değişince duyarlı durum sıfırlanır'
Assert-True ((Get-FnText 'Set-UiZoom') -match 'Update-Responsive') 'Set-UiZoom: yakınlaştırma değişince duyarlı yerleşim güncellenir'
$upd = Get-FnText 'Update-Responsive'
Assert-True ($upd -match 'Update-ResponsivePanels' -and $upd -match 'Update-TitleFit' -and $upd -match 'Update-PanelReflow') 'Update-Responsive: paneller, başlık, durum panosu'
Assert-True ($upd -match 'finally') 'Update-Responsive: yeniden girişi serbest bırakmak için finally kullanır'
# sürekli çalışan döngü yok: zamanlayıcı yalnızca bir kez tetiklenip durur
$tick = Get-FnText 'Initialize-Responsive'
Assert-True ($tick -match 'RespTimer\.Stop\(\)') 'duyarlı yerleşim zamanlayıcısı her tetiklenişte durur (sürekli döngü yok)'
# sol menü düğme yüksekliği menü alanının gerçek boyutuna bağlanır (yakınlaştırmada pencere boyutu değişmez, gövde ölçeklenir)
Assert-True ($tick -match "RailHost\.Add_SizeChanged\(\{[^}]*Update-RailDensity") 'Initialize-Responsive: menü alanı boyutu değişince düğme yükseklikleri yeniden hesaplanır'
# 940 / 700 / 450 sabitleri tek yerde
Assert-Eq ([regex]::Matches($text, '\$script:RespWidePage = ')).Count 1 'RespWidePage tek tanımlı'

# açma-kapama (Toggle) satırlarının uzun metni sağda kesilmez, alt satıra sarar (Ayarlar, hacker yerleşimi)
$ti = $text.IndexOf('<Style x:Key="Toggle" TargetType="CheckBox">')
Assert-True ($ti -gt 0) 'Toggle stili derlenmiş betikte bulunur'
$tseg = $text.Substring($ti, [Math]::Min(2800, $text.Length - $ti))
Assert-True ($tseg -match '(?s)<ContentPresenter Grid\.Column="1"[^>]*RecognizesAccessKey="True">\s*<ContentPresenter\.Resources>\s*<Style TargetType="TextBlock"><Setter Property="TextWrapping" Value="Wrap"/></Style>\s*</ContentPresenter\.Resources>\s*</ContentPresenter>') 'Toggle: içerik metni sarar'
Assert-Eq ([regex]::Matches($text, '<ContentPresenter\.Resources>')).Count 1 'ortük TextBlock sarma stili yalnızca Toggle şablonunda'

# dokunma hedefi alt sınırı (WCAG 2.2 AA, 2.5.8: kısa kenar en az 24 px). Gerçek bilgisayar ölçümü (25.11.2026): 70 öğe 24 px altındaydı;
# 63 RadioButton (sekme düğmeleri 22 px) ve 7 CheckBox (18-20 px). Sekme (Seg, Chip), onay kutusu ve Toggle stilleri en az 24 px ister.
function Get-StyleHead([string]$Text, [string]$OpenTag) {
    $i = $Text.IndexOf($OpenTag)
    if ($i -lt 0) { return $null }
    $j = $Text.IndexOf('<Setter Property="Template">', $i)
    if ($j -lt 0) { return $null }
    return $Text.Substring($i, $j - $i)
}
foreach ($st in @(
        @{ Tag = '<Style x:Key="Seg" TargetType="RadioButton">'; Ad = 'Seg (sekme) stili' },
        @{ Tag = '<Style TargetType="CheckBox">'; Ad = 'varsayılan onay kutusu stili' },
        @{ Tag = '<Style x:Key="Toggle" TargetType="CheckBox">'; Ad = 'Toggle stili' })) {
    $head = Get-StyleHead $text $st.Tag
    Assert-True ($null -ne $head) ($st.Ad + ' derlenmiş betikte bulunur')
    # 10.1.0 (G-05): alt sınır kaynaktan okunur (TouchMin: Normal 24, Büyük 40 / Kompakt 32); varsayılan kaynak değeri 24
    $mh = if ($null -ne $head) { [regex]::Match($head, '<Setter Property="MinHeight" Value="\{DynamicResource TouchMin\}"\s*/>') } else { $null }
    Assert-True ($null -ne $mh -and $mh.Success) ($st.Ad + ': en az TouchMin (Normal 24 px) yükseklik ister')
}
$ci = $text.IndexOf('<Style x:Key="Chip" TargetType="RadioButton" BasedOn="{StaticResource Seg}">')
Assert-True ($ci -gt 0) 'Chip stili bulunur ve Seg''den türer'
$chip = $text.Substring($ci, $text.IndexOf('</Style>', $ci) - $ci)
Assert-True ($chip -notmatch '<Setter Property="(MinHeight|Height)"') 'Chip: yükseklik Seg''den gelir, burada ezilmez'

# ======================= 4) duman testi kuyruğunda yeni adımlar =======================
$kindsHandled = (Get-FnText 'Invoke-SmokeStep') + (Get-FnText 'Invoke-SmokeStepLook')
# Gerçek cihazda bulundu: doğrudan yerleşim adımı ayarı dosyaya da yazar. Her arka plan işi bitince ayarlar dosyadan yeniden okunur;
# yazılmamış yerleşim eski değere dönerdi ve Ayarlar listesi uygulanan yerleşimden farklı bir değer gösterirdi.
$layoutCase = [regex]::Match((Get-FnText 'Invoke-SmokeStep'), "(?s)'Layout' \{.*?\r?\n        \}")
Assert-True ($layoutCase.Success -and $layoutCase.Value.Contains('Select-Layout $arg') -and $layoutCase.Value.Contains('Save-Settings $script:Settings')) "duman testi: 'Layout' adımı seçimi ayar dosyasına da yazar"
Assert-True ((Get-FnText 'Complete-Async').Contains('$script:Settings = Get-Settings')) 'Complete-Async: iş bitince ayarlar dosyadan okunur (yazılmamış bellek değişikliği kaybolur)'
foreach ($startLayout in @('Ayrintili', 'Sade')) {
    $q = New-SmokeQueue 'Neon' @('panel', 'optimize', 'settings') { param($k) @() } $startLayout
    $steps = @($q.ToArray())
    $tag = 'başlangıç yerleşimi ' + $startLayout
    $kinds = @($steps | ForEach-Object { $_.Kind })
    foreach ($k in @($kinds | Select-Object -Unique)) {
        Assert-True ($kindsHandled -match ("'" + $k + "'")) ($tag + ': adım türü ' + $k + ' için işleyici var')
    }
    Assert-Eq (@($steps | Where-Object { $_.Kind -eq 'BrushSeed' }).Count) 1 ($tag + ': örnek günlük satırları bir kez eklenir')
    $bi = [array]::IndexOf($kinds, 'BrushSeed')
    $ti = [array]::IndexOf($kinds, 'Templates')
    Assert-True ($bi -ge 0 -and $bi -lt $ti) ($tag + ': örnek satırlar tema değişimlerinden önce eklenir')
    $firstTheme = [array]::IndexOf($kinds, 'Theme')
    Assert-True ($bi -lt $firstTheme) ($tag + ': örnek satırlar ilk tema değişiminden önce')
    $resp = @($steps | Where-Object { $_.Kind -eq 'Resp' })
    Assert-True ($resp.Count -ge 11) ($tag + ': duyarlı yerleşim denetimleri var (' + [string]$resp.Count + ')')
    foreach ($r in $resp) {
        foreach ($tok in @(([string]$r.Arg) -split ',')) {
            Assert-True ($tok -match '^(log:(on|off|def)|cmd:(on|off|def)|title|panel|panelfit)$') ($tag + ': geçerli koşul "' + $tok + '"')
        }
    }
    Assert-Eq (@($steps | Where-Object { $_.Kind -eq 'BusyLog' }).Count) 4 ($tag + ': dört yerleşimde işlem başlayınca günlük denenir')
    $busyIdx = @(0..($kinds.Count - 1) | Where-Object { $kinds[$_] -eq 'BusyLog' })
    foreach ($bx in $busyIdx) { Assert-Eq $kinds[$bx - 1] 'Drain' ($tag + ': işlem denemesinden önce boşta beklenir') }
    # küçük pencere: günlük + komut satırı kapanır, elle açılanlar kalır, varsayılan boyutta düzen geri gelir
    $seq = @($steps | Where-Object { $_.Kind -in @('Size', 'Resp') -or ($_.Kind -eq 'Click' -and $_.Arg -like 'Btn*' -and $_.Arg -ne 'BtnHome') } | ForEach-Object { if ($_.Kind -eq 'Resp') { 'Resp[' + $_.Arg + ']' } else { $_.Kind + ':' + $_.Arg } })
    $joined = $seq -join ' | '
    $want = 'Resp[log:on,cmd:on,title,panel] | Size:1060x660 | Resp[log:off,cmd:off,title,panel,panelfit] | Click:BtnLogToggle | Click:BtnCmdToggle | Resp[log:on,cmd:on,panel] | Size:1380x840 | Resp[log:on,cmd:on,title,panel]'
    Assert-True ($joined.StartsWith($want)) ($tag + ': küçük pencere dizisi (kapanır, elle açılır, geri döner)')
    $clicks = @($steps | Where-Object { $_.Kind -eq 'Click' })
    Assert-Eq (@($clicks | Where-Object { $_.Arg -like 'Btn*' -and $_.Arg -ne 'BtnHome' }).Count) 2 ($tag + ': yerleşim denemesinde yalnızca iki başlık düğmesine tıklanır (günlük, komut satırı)')
    Assert-Eq (@($clicks | Where-Object { $_.Arg -eq 'BtnHome' }).Count) 1 ($tag + ': ana sayfa emblemine bir kez tıklanır (yerleşim denemesinden ayrı, ust kapsamı)')
    # yakınlaştırma: %130'da kapanır, %80'de ve %100'de açık
    $zr = @($steps | Where-Object { $_.Kind -eq 'Resp' -and $_.Label -like '*yakınlaştırma*' } | ForEach-Object { $_.Arg })
    Assert-Eq $zr.Count 3 ($tag + ': üç yakınlaştırma için duyarlı denetim')
    Assert-Eq $zr[0] 'log:off,cmd:off,title,panel,panelfit' ($tag + ': %130 yakınlaştırmada günlük ve komut satırı kapanır')
    Assert-Eq $zr[1] 'log:def,cmd:def,title,panel' ($tag + ': %80 yakınlaştırmada varsayılan düzen')
    # Gerçek cihazda bulundu (25.11.2026): Hacker yerleşimiyle biten adımlardan sonra %100'de koşulsuz "açık" beklemek iki yanlış HATA yazdı.
    Assert-Eq $zr[2] 'log:def,cmd:def,title,panel' ($tag + ': %100 yakınlaştırmada günlük ve komut satırı yerleşimin varsayılanına döner')
    # yakınlaştırma sonrası sol menü: %130'da uyarı (yer yetmeyebilir), %80'de ve %100'e dönünce sığmalı
    $zrail = @($steps | Where-Object { $_.Kind -eq 'Rail' -and $_.Label -like '*yakınlaştırma*' } | ForEach-Object { $_.Arg })
    Assert-Eq ($zrail -join ',') 'warn,fit,fit' ($tag + ': yakınlaştırma sonrası sol menü denetimleri (%130 uyarı, %80 ve %100 sığmalı)')
}

Show-Result
