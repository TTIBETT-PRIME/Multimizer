# 7.2.0: görünüm (tema / yerleşim / yakınlaştırma), kaydırma + klavye + kısayollar, tepsi (simge durumu ve X) davranışı.
# Linux'ta WPF yok: ağaç, pencere ve denetim türleri küçük sahte sınıflarla taklit edilir; gerçek işlevler AST ile derlenmiş betikten alınır.
. "$PSScriptRoot/lib.ps1"

Add-Type -ReferencedAssemblies @([psobject].Assembly.Location, 'System.Collections', 'System.Runtime', 'netstandard') -TypeDefinition @'
using System;
namespace System.Windows {
    public class DependencyObject { }
    public class FrameworkElement : System.Windows.Media.Visual { public object Parent; public object TemplatedParent; }
    public enum WindowState { Normal, Minimized, Maximized }
    public struct Thickness {
        public double Left, Top, Right, Bottom;
        public Thickness(double u) { Left = u; Top = u; Right = u; Bottom = u; }
        public Thickness(double l, double t, double r, double b) { Left = l; Top = t; Right = r; Bottom = b; }
    }
    public static class SystemParameters { public static Thickness WindowResizeBorderThickness { get { return new Thickness(8, 8, 8, 8); } } }
    public static class LogicalTreeHelper { public static object GetParent(DependencyObject o) { return null; } }
}
namespace System.Windows.Media {
    public class Visual : System.Windows.DependencyObject { public object P; }
    public static class VisualTreeHelper { public static object GetParent(System.Windows.DependencyObject o) { var v = o as Visual; return v == null ? null : v.P; } }
}
namespace System.Windows.Media.Media3D { public class Visual3D : System.Windows.DependencyObject { } }
namespace System.Windows.Input { public enum Key { None = 0, Tab = 3, Prior = 19, Next = 20, End = 21, Home = 22 } }
namespace System.Windows.Controls.Primitives {
    public class TextBoxBase : System.Windows.FrameworkElement { }
    public class Selector : System.Windows.FrameworkElement { }
    public class ButtonBase : System.Windows.FrameworkElement { }
    public class Popup : System.Windows.FrameworkElement { }
}
namespace System.Windows.Controls {
    public enum ScrollBarVisibility { Disabled, Auto, Hidden, Visible }
    public class ScrollViewer : System.Windows.FrameworkElement {
        public ScrollBarVisibility VerticalScrollBarVisibility = ScrollBarVisibility.Auto;
        public double ScrollableHeight; public bool CanContentScroll; public double VerticalOffset; public double ViewportHeight;
    }
    public class TextBox : System.Windows.Controls.Primitives.TextBoxBase { }
    public class PasswordBox : System.Windows.FrameworkElement { }
    public class Slider : System.Windows.FrameworkElement { }
    public class ListBoxItem : System.Windows.FrameworkElement { }
    public class ComboBoxItem : System.Windows.FrameworkElement { }
    public class ComboBox : System.Windows.Controls.Primitives.Selector { }
    public class Button : System.Windows.Controls.Primitives.ButtonBase { }
    public class CheckBox : System.Windows.Controls.Primitives.ButtonBase { }
    public class Border : System.Windows.FrameworkElement { }
}
namespace System.Windows.Forms { public enum ToolTipIcon { None, Info, Warning, Error } }
'@

Import-Fn 'ConvertTo-ThemeKey', 'ConvertTo-ThemeChoice', 'Get-SystemThemeKey', 'ConvertTo-LayoutKey', 'ConvertTo-ZoomPct', 'Get-NearestZoomStep', 'Get-NextZoom', 'Get-LayoutDefaults', 'Get-RailWidth', 'Get-CardOpenCount', 'Get-LookPreset'
Import-Fn 'Format-Percent', 'Convert-LangPercent'
$script:LangPctStyle = 0
Import-Fn 'Get-WheelPixels', 'Get-FocusKind', 'Get-KeyName', 'Get-ScrollKeyAction', 'Get-HotKeyAction', 'Test-NavKeyName', 'Get-ParentObj', 'Test-IsDescendant', 'Find-ScrollerFrom'
Import-Fn 'Get-TrayOnClose', 'Get-TrayOnMinimize', 'Invoke-CloseRequest', 'Hide-ToTray', 'Restore-FromTray', 'Invoke-WindowStateChanged', 'Get-DefaultSettings'
Import-Fn 'Get-ComboOfPopupSource', 'New-Choice', 'Set-ComboChoices', 'Select-ComboKey', 'Get-ComboKey', 'Merge-HexOver', 'Get-ThemeSwatch', 'Get-MatchingLookPreset'
Import-Fn 'Initialize-StLookChoices', 'Load-StLook', 'Save-StLook', 'Sync-StPresetBox', 'Update-StAppearanceText'
Import-Fn 'Get-BoardField', 'ConvertTo-HomeKey', 'ConvertTo-DsValue', 'Test-DesignOverridden', 'ConvertTo-DesignKey', 'ConvertTo-GlassKey', 'ConvertTo-GlassOpacity', 'Get-PresetGlass', 'Get-DesignSpec'
Import-Var 'Themes', 'ThemeGrads', 'ThemeInfo', 'LayoutInfo', 'ZoomSteps', 'SmokeSafe', 'SmokeSafeSelect', 'LookPresetNames', 'HomeInfo', 'DsOptions', 'DsRadii', 'DesignInfo', 'GlassInfo', 'GlassSteps'

# ---------------- sahte ortam ----------------
$script:Log = New-Object System.Collections.ArrayList
function Write-CrashLog([string]$Text) { [void]$script:Log.Add($Text) }
$global:Calls = @{ Exit = 0; Hide = 0; Show = 0; Activate = 0; Focus = 0; Confirm = (New-Object System.Collections.ArrayList); Balloon = (New-Object System.Collections.ArrayList); Keys = (New-Object System.Collections.ArrayList) }
function Reset-Calls {
    $global:Calls.Exit = 0; $global:Calls.Hide = 0; $global:Calls.Show = 0; $global:Calls.Activate = 0; $global:Calls.Focus = 0
    $global:Calls.Confirm.Clear(); $global:Calls.Balloon.Clear(); $global:Calls.Keys.Clear(); $script:Log.Clear()
}
$script:FakeBusy = $false
function Test-AsyncBusy { return [bool]$script:FakeBusy }
function Exit-App { $global:Calls.Exit++ }
function Show-Confirm($Title, $Msg, $Btn, $Act, $Danger) { [void]$global:Calls.Confirm.Add(([string]$Title + '|' + [string]$Danger)) }
function Set-SettingsKeys($Keys) { foreach ($k in @($Keys.Keys)) { $script:Settings[[string]$k] = $Keys[$k]; [void]$global:Calls.Keys.Add([string]$k + '=' + [string]$Keys[$k]) } }

function New-FakeWin([string]$State) {
    $w = New-Object psobject -Property @{ WindowState = [System.Windows.WindowState]$State; ShowInTaskbar = $false; Topmost = $false }
    Add-Member -InputObject $w -MemberType ScriptMethod -Name Hide -Value { $global:Calls.Hide++ }
    Add-Member -InputObject $w -MemberType ScriptMethod -Name Show -Value { $global:Calls.Show++ }
    Add-Member -InputObject $w -MemberType ScriptMethod -Name Activate -Value { $global:Calls.Activate++; return $true }
    Add-Member -InputObject $w -MemberType ScriptMethod -Name Focus -Value { $global:Calls.Focus++; return $true }
    return $w
}
function New-FakeTray {
    $t = New-Object psobject
    Add-Member -InputObject $t -MemberType ScriptMethod -Name ShowBalloonTip -Value { param($ms, $title, $text, $icon) [void]$global:Calls.Balloon.Add([string]$text) }
    return $t
}

# ======================= 1) görünüm yardımcıları =======================
Assert-Eq (@($script:Themes.Keys | Sort-Object) -join ',') 'Acik,Akis,Cam,Hacker,Holo,Koyu,Kum,Neon,Uzay,Yuksek' 'on renk teması'
Assert-Eq (@($script:LayoutInfo.Keys) -join ',') 'Ayrintili,Kompakt,Sade,Hacker' 'dört yerleşim (ayrıntılı, kompakt, sade, hacker)'
Assert-Eq ($script:ZoomSteps -join ',') '80,90,100,110,120,130' 'yakınlaştırma basamakları'

# kanonik ad
Assert-Eq (ConvertTo-LayoutKey 'Kompakt') 'Kompakt' 'yerleşim adı korunur'
Assert-Eq (ConvertTo-LayoutKey 'kompakt') 'Kompakt' 'küçük harfli yerleşim adı kanonik olur'
Assert-Eq (ConvertTo-LayoutKey 'SADE') 'Sade' 'büyük harfli yerleşim adı kanonik olur'
Assert-Eq (ConvertTo-LayoutKey 'Bilinmeyen') 'Sade' 'bilinmeyen yerleşim sade (varsayılan) olur'
Assert-Eq (ConvertTo-LayoutKey '') 'Sade' 'boş yerleşim sade (varsayılan) olur'
Assert-Eq (ConvertTo-LayoutKey $null) 'Sade' 'null yerleşim sade (varsayılan) olur'
Assert-Eq (ConvertTo-ThemeKey 'KOYU') 'Koyu' 'büyük harfli tema adı kanonik olur'

# yakınlaştırma sınırları
Assert-Eq (ConvertTo-ZoomPct 100) 100 '%100 korunur'
Assert-Eq (ConvertTo-ZoomPct 130) 130 '%130 korunur'
Assert-Eq (ConvertTo-ZoomPct 50) 70 '%70 altı %70 olur'
Assert-Eq (ConvertTo-ZoomPct 500) 150 '%150 üstü %150 olur'
Assert-Eq (ConvertTo-ZoomPct 'abc') 100 'sayı olmayan değer %100 olur'
Assert-Eq (ConvertTo-ZoomPct $null) 100 'boş değer %100 olur (%70 e düşmez)'
Assert-Eq (ConvertTo-ZoomPct '') 100 'boş metin %100 olur'
Assert-Eq (ConvertTo-ZoomPct 0) 100 'sıfır %100 olur'
Assert-Eq (ConvertTo-ZoomPct '110') 110 'metin olarak yazılmış sayı okunur'
foreach ($n in @(100, 80, 130)) { Assert-Eq (Get-NearestZoomStep $n) $n ('basamak ' + $n + ' kendisidir') }
Assert-Eq (Get-NearestZoomStep 70) 80 '%70 en yakın basamak %80'
Assert-Eq (Get-NearestZoomStep 150) 130 '%150 en yakın basamak %130'
Assert-Eq (Get-NearestZoomStep 124) 120 '%124 en yakın basamak %120'
Assert-Eq (Get-NearestZoomStep 126) 130 '%126 en yakın basamak %130'
Assert-Eq (Get-NextZoom 100 1) 110 'Ctrl+artı: %100 -> %110'
Assert-Eq (Get-NextZoom 100 -1) 90 'Ctrl+eksi: %100 -> %90'
Assert-Eq (Get-NextZoom 130 1) 130 'üst sınırda kalır'
Assert-Eq (Get-NextZoom 80 -1) 80 'alt sınırda kalır'
Assert-Eq (Get-NextZoom 105 1) 110 'ara değerden bir sonraki basamağa geçer'
$zz = 100; $path = New-Object System.Collections.ArrayList
foreach ($i in 1..8) { $zz = Get-NextZoom $zz 1; [void]$path.Add($zz) }
Assert-Eq ($path -join ',') '110,120,130,130,130,130,130,130' 'art arda yaklaştırma %130 da durur'
foreach ($i in 1..8) { $zz = Get-NextZoom $zz -1 }
Assert-Eq $zz 80 'art arda uzaklaştırma %80 de durur'

# yerleşim tabloları
$d = Get-LayoutDefaults 'Ayrintili'
Assert-Eq "$($d.Rail)|$($d.Groups)|$($d.Log)|$($d.Cmd)|$($d.Cards)|$($d.Mono)|$($d.Calm)|$($d.Sys)" 'Icon|False|330|True|False|False|False|True' 'ayrıntılı: bugünkü kalabalık düzen (simge menü, günlük, komut satırı)'
$d = Get-LayoutDefaults 'Kompakt'
Assert-Eq "$($d.Rail)|$($d.Groups)|$($d.Log)|$($d.Cmd)|$($d.Cards)|$($d.Mono)|$($d.Calm)" 'Compact|False|0|False|False|False|False' 'kompakt: dar simge menüsü, günlük ve komut satırı kapalı'
$d = Get-LayoutDefaults 'Sade'
Assert-Eq "$($d.Rail)|$($d.Groups)|$($d.Log)|$($d.Cmd)|$($d.Cards)|$($d.Mono)|$($d.Calm)|$($d.Sys)" 'Text|True|0|False|True|False|True|False' 'sade: açılır gruplar, açılır kartlar, sakin, günlük ve komut satırı kapalı'
$d = Get-LayoutDefaults 'Hacker'
Assert-Eq "$($d.Rail)|$($d.Groups)|$($d.Log)|$($d.Open)|$($d.Cmd)|$($d.CmdH)|$($d.Cards)|$($d.Mono)|$($d.Calm)" 'Text|False|360|360|True|200|False|True|False' 'hacker: yazılı menü, geniş günlük, hep açık yüksek komut satırı, tek aralıklı yazı'
$d = Get-LayoutDefaults 'Yok'
Assert-Eq "$($d.Rail)|$($d.Log)|$($d.Cmd)" 'Icon|330|True' 'bilinmeyen yerleşim ayrıntılı gibi davranır'
foreach ($l in $script:LayoutInfo.Keys) {
    $d = Get-LayoutDefaults $l
    Assert-True (@('Icon', 'Compact', 'Text') -contains [string]$d.Rail) ($l + ': geçerli menü biçimi')
    if ([bool]$d.Cmd -eq $false) { Assert-Eq $d.Log 0 ($l + ': komut satırı kapalıysa günlük de kapalı') }
    Assert-True ([double]$d.Open -ge 300) ($l + ': günlük açılınca en az 300 px')
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$script:LayoutInfo[$l].T) -and -not [string]::IsNullOrWhiteSpace([string]$script:LayoutInfo[$l].D)) ($l + ': ad ve açıklama dolu')
}
Assert-Eq (Get-RailWidth 'Compact') 54 'kompakt menü 54 px'
Assert-Eq (Get-RailWidth 'Text') 200 'yazılı menü 200 px'
Assert-Eq (Get-RailWidth 'Icon') 72 'simge menü 72 px'
Assert-Eq (Get-RailWidth 'Bilinmeyen') 72 'bilinmeyen menü biçimi 72 px'
Assert-Eq (Get-CardOpenCount 'panel') 2 'panelde ilk iki kart açık başlar'
Assert-Eq (Get-CardOpenCount 'settings') 2 'ayarlarda ilk iki kart açık başlar (görünüm kartı kaybolmaz)'
Assert-Eq (Get-CardOpenCount 'network') 1 'diğer sayfalarda ilk kart açık başlar'

# hazır görünümler
$pre = @{ Varsayilan = 'Acik|Sade'; KoyuNeon = 'Neon|Ayrintili'; KompaktKoyu = 'Koyu|Kompakt'; Hacker = 'Hacker|Hacker' }
foreach ($k in $pre.Keys) {
    $p = Get-LookPreset $k
    Assert-Eq ([string]$p.Theme + '|' + [string]$p.Layout) $pre[$k] ('hazır görünüm ' + $k)
    Assert-Eq $p.Zoom 100 ('hazır görünüm ' + $k + ': %100')
    Assert-True ($script:Themes.Contains([string]$p.Theme) -and $script:LayoutInfo.Contains([string]$p.Layout)) ($k + ': tema ve yerleşim tablolarda var')
}
$p = Get-LookPreset 'Yok'
Assert-Eq ([string]$p.Theme + '|' + [string]$p.Layout) 'Acik|Sade' 'bilinmeyen hazır görünüm varsayılandır (beyaz ve sade)'

# ======================= 2) kaydırma ve tuş tabloları =======================
Assert-Eq (Get-WheelPixels 120 3 600) 99 'bir tekerlek çentiği, 3 satır = 99 px'
Assert-Eq (Get-WheelPixels -120 3 600) -99 'aşağı çentik negatif'
Assert-Eq (Get-WheelPixels 240 3 600) 198 'iki çentik'
Assert-Eq (Get-WheelPixels 60 3 600) 49.5 'dokunmatik yüzeyin yarım çentiği orantılı'
Assert-Eq (Get-WheelPixels 120 0 500) 450 'Windows "bir ekran" ayarı: görünür yüksekliğin %90 ı'
Assert-Eq (Get-WheelPixels -120 5 600) -165 'satır sayısı Windows ayarını izler'

# Get-KeyName: PageDown = Next, PageUp = Prior
Assert-Eq (Get-KeyName ([System.Windows.Input.Key]::Next)) 'PageDown' 'Next -> PageDown'
Assert-Eq (Get-KeyName ([System.Windows.Input.Key]::Prior)) 'PageUp' 'Prior -> PageUp'
Assert-Eq (Get-KeyName ([System.Windows.Input.Key]::Home)) 'Home' 'Home aynen'
Assert-Eq (Get-KeyName ([System.Windows.Input.Key]::Tab)) 'Tab' 'Tab aynen'

# odaktaki öğenin türü
Assert-Eq (Get-FocusKind $null) 'Neutral' 'odak yok: nötr'
Assert-Eq (Get-FocusKind (New-Object System.Windows.Controls.TextBox)) 'Text' 'yazı kutusu'
Assert-Eq (Get-FocusKind (New-Object System.Windows.Controls.PasswordBox)) 'Text' 'parola kutusu'
Assert-Eq (Get-FocusKind (New-Object System.Windows.Controls.ComboBox)) 'List' 'açılır kutu'
Assert-Eq (Get-FocusKind (New-Object System.Windows.Controls.Slider)) 'List' 'kaydırma çubuğu / ayar çubuğu'
Assert-Eq (Get-FocusKind (New-Object System.Windows.Controls.ListBoxItem)) 'List' 'liste öğesi'
Assert-Eq (Get-FocusKind (New-Object System.Windows.Controls.ComboBoxItem)) 'List' 'açılır kutu öğesi'
Assert-Eq (Get-FocusKind (New-Object System.Windows.Controls.Button)) 'Button' 'düğme'
Assert-Eq (Get-FocusKind (New-Object System.Windows.Controls.CheckBox)) 'Button' 'işaret kutusu / anahtar'
Assert-Eq (Get-FocusKind (New-Object System.Windows.Controls.Border)) 'Neutral' 'kenarlık: nötr'

# tuş -> kaydırma eylemi: (tuş, Ctrl, Alt, Shift, odak türü) -> eylem
$keyCases = @(
    @('PageDown', $false, $false, $false, 'Neutral', 'PageDown'),
    @('PageUp', $false, $false, $false, 'Neutral', 'PageUp'),
    @('PageDown', $false, $false, $false, 'Button', 'PageDown'),
    @('PageUp', $false, $false, $false, 'Button', 'PageUp'),
    @('PageDown', $false, $false, $false, 'Text', ''),
    @('PageDown', $false, $false, $false, 'List', ''),
    @('PageDown', $true, $false, $false, 'Neutral', ''),
    @('Home', $false, $false, $false, 'Neutral', 'Top'),
    @('End', $false, $false, $false, 'Neutral', 'Bottom'),
    @('Home', $false, $false, $false, 'Button', ''),
    @('Home', $true, $false, $false, 'Button', 'Top'),
    @('End', $true, $false, $false, 'Button', 'Bottom'),
    @('Home', $true, $false, $false, 'Text', ''),
    @('End', $true, $false, $false, 'List', ''),
    @('Space', $false, $false, $false, 'Neutral', 'PageDown'),
    @('Space', $false, $false, $true, 'Neutral', 'PageUp'),
    @('Space', $false, $false, $false, 'Button', ''),
    @('Down', $false, $false, $false, 'Neutral', 'LineDown'),
    @('Up', $false, $false, $false, 'Neutral', 'LineUp'),
    @('Down', $false, $false, $false, 'Button', ''),
    @('Up', $false, $false, $false, 'Text', ''),
    @('Down', $false, $false, $false, 'List', ''),
    @('PageDown', $false, $true, $false, 'Neutral', ''),
    @('Home', $false, $true, $false, 'Neutral', ''),
    @('A', $false, $false, $false, 'Neutral', ''),
    @('Tab', $false, $false, $false, 'Neutral', '')
)
foreach ($c in $keyCases) {
    $got = Get-ScrollKeyAction $c[0] $c[1] $c[2] $c[3] $c[4]
    Assert-Eq $got $c[5] ('tuş ' + $c[0] + ' ctrl=' + $c[1] + ' alt=' + $c[2] + ' shift=' + $c[3] + ' odak=' + $c[4])
}

# Ctrl kısayolları
$hot = @(
    @('Tab', $true, $false, $false, 'NextPage'), @('Tab', $true, $false, $true, 'PrevPage'), @('Tab', $false, $false, $false, ''),
    @('OemComma', $true, $false, $false, 'Settings'), @('Q', $true, $false, $false, 'Quit'), @('W', $true, $false, $false, 'HideToTray'),
    @('OemPlus', $true, $false, $false, 'ZoomIn'), @('Add', $true, $false, $false, 'ZoomIn'),
    @('OemMinus', $true, $false, $false, 'ZoomOut'), @('Subtract', $true, $false, $false, 'ZoomOut'),
    @('D0', $true, $false, $false, 'ZoomReset'), @('NumPad0', $true, $false, $false, 'ZoomReset'),
    @('Tab', $true, $true, $false, ''), @('Q', $false, $false, $false, ''), @('Q', $true, $true, $false, ''), @('A', $true, $false, $false, ''), @('C', $true, $false, $false, ''), @('V', $true, $false, $false, '')
)
foreach ($c in $hot) { Assert-Eq (Get-HotKeyAction $c[0] $c[1] $c[2] $c[3]) $c[4] ('kısayol ' + $c[0] + ' ctrl=' + $c[1] + ' alt=' + $c[2] + ' shift=' + $c[3]) }
foreach ($n in @('Tab', 'Left', 'Right', 'Up', 'Down', 'Space', 'Return', 'Enter')) { Assert-True (Test-NavKeyName $n) ('gezinme tuşu: ' + $n) }
foreach ($n in @('A', 'F5', 'PageDown', 'Home')) { Assert-True (-not (Test-NavKeyName $n)) ('gezinme tuşu değil: ' + $n) }

# ======================= 3) kaydırıcı zinciri (iç içe listeler sınırda sayfaya geçer) =======================
function New-Sv([double]$Off, [double]$Max, [bool]$Native, $Parent) {
    $sv = New-Object System.Windows.Controls.ScrollViewer
    $sv.VerticalOffset = $Off; $sv.ScrollableHeight = $Max; $sv.CanContentScroll = $Native; $sv.P = $Parent; $sv.ViewportHeight = 400
    return $sv
}
function New-Leaf($Parent) { $l = New-Object System.Windows.FrameworkElement; $l.P = $Parent; return $l }
$outer = New-Sv 100 500 $false $null
$inner = New-Sv 0 10 $true $outer
$leaf = New-Leaf $inner
Assert-Eq (Find-ScrollerFrom $leaf 1) 'native' 'liste ortada: tekerlek listeyi kaydırır (WPF e bırakılır)'
$inner.VerticalOffset = 5
Assert-Eq (Find-ScrollerFrom $leaf -1) 'native' 'liste ortada, yukarı: liste kaydırır'
$inner.VerticalOffset = 10
Assert-True ([object]::ReferenceEquals((Find-ScrollerFrom $leaf 1), $outer)) 'liste en altta, aşağı: tekerlek sayfaya geçer'
Assert-Eq (Find-ScrollerFrom $leaf -1) 'native' 'liste en altta, yukarı: hâlâ liste kaydırır'
$inner.VerticalOffset = 0
Assert-True ([object]::ReferenceEquals((Find-ScrollerFrom $leaf -1), $outer)) 'liste en üstte, yukarı: tekerlek sayfaya geçer'
$outer.VerticalOffset = 0
Assert-True ($null -eq (Find-ScrollerFrom $leaf -1)) 'liste ve sayfa en üstte, yukarı: kaydırılacak yer yok'
$outer.VerticalOffset = 500
$inner.VerticalOffset = 10
Assert-True ($null -eq (Find-ScrollerFrom $leaf 1)) 'liste ve sayfa en altta, aşağı: kaydırılacak yer yok'
$outer.VerticalOffset = 100
# piksel bazlı iç kaydırıcı
$inner.CanContentScroll = $false; $inner.ScrollableHeight = 300; $inner.VerticalOffset = 150
Assert-True ([object]::ReferenceEquals((Find-ScrollerFrom $leaf 1), $inner)) 'piksel bazlı iç kaydırıcı ortada: o kaydırılır'
$inner.VerticalOffset = 300
Assert-True ([object]::ReferenceEquals((Find-ScrollerFrom $leaf 1), $outer)) 'piksel bazlı iç kaydırıcı sonda: sayfaya geçer'
$inner.VerticalOffset = 0
Assert-True ([object]::ReferenceEquals((Find-ScrollerFrom $leaf -1), $outer)) 'piksel bazlı iç kaydırıcı başta, yukarı: sayfaya geçer'
$inner.VerticalOffset = 100
Assert-True ([object]::ReferenceEquals((Find-ScrollerFrom $leaf 0), $inner)) 'yön yoksa ilk kaydırılabilir olan'
# içeriği sığan ve kapalı kaydırıcılar atlanır
$inner.ScrollableHeight = 0
Assert-True ([object]::ReferenceEquals((Find-ScrollerFrom $leaf 1), $outer)) 'içeriği sığan kaydırıcı atlanır'
$inner.ScrollableHeight = 300; $inner.VerticalScrollBarVisibility = [System.Windows.Controls.ScrollBarVisibility]::Disabled
Assert-True ([object]::ReferenceEquals((Find-ScrollerFrom $leaf 1), $outer)) 'dikey kaydırması kapalı kaydırıcı atlanır'
$inner.VerticalScrollBarVisibility = [System.Windows.Controls.ScrollBarVisibility]::Auto
# ağaç yardımcıları
Assert-True (Test-IsDescendant $leaf $outer) 'yaprak dış kaydırıcının torunudur'
Assert-True (Test-IsDescendant $leaf $leaf) 'öğe kendisinin torunu sayılır'
Assert-True (-not (Test-IsDescendant $outer $leaf)) 'dış kaydırıcı yaprağın torunu değildir'
Assert-True (-not (Test-IsDescendant $leaf (New-Leaf $null))) 'ilgisiz öğe torun değildir'
Assert-True (-not (Test-IsDescendant $null $outer)) 'boş öğe torun değildir'
Assert-True ($null -eq (Get-ParentObj $null)) 'boş öğenin üstü yok'
Assert-True ([object]::ReferenceEquals((Get-ParentObj $leaf), $inner)) 'üst öğe görsel ağaçtan okunur'

# ======================= 4) tepsi ayarları =======================
$tray = @(
    @($true, $null, $true, $true), @($false, $null, $false, $false), @($null, $null, $false, $false),
    @($true, $false, $true, $false), @($false, $true, $false, $true), @($true, $true, $true, $true), @($null, $true, $false, $true), @($null, $false, $false, $false)
)
foreach ($r in $tray) {
    $script:Settings = @{ TrayMinimize = $r[0]; TrayOnMinimize = $r[1] }
    Assert-Eq (Get-TrayOnClose) $r[2] ('X tepsiye iner mi: TrayMinimize=' + $r[0] + ' TrayOnMinimize=' + $r[1])
    Assert-Eq (Get-TrayOnMinimize) $r[3] ('simge durumu tepsiye iner mi: TrayMinimize=' + $r[0] + ' TrayOnMinimize=' + $r[1])
}

# ======================= 5) X düğmesi / Alt+F4 (Invoke-CloseRequest) =======================
$script:LastShownState = 'Normal'; $script:TrayBusyHintAt = [datetime]::MinValue; $script:TrayHintShown = $false
# a) tepsi var, ayar açık: pencere gizlenir, uygulama kapanmaz
Reset-Calls; $script:Tray = New-FakeTray; $script:Win = New-FakeWin 'Normal'; $script:Settings = @{ TrayMinimize = $true; TrayHints = 9 }; $script:FakeBusy = $false; $script:TrayHintShown = $false
Invoke-CloseRequest
Assert-Eq $Calls.Hide 1 'X: tepsi açıkken pencere gizlenir'
Assert-Eq $Calls.Exit 0 'X: tepsi açıkken uygulama kapanmaz'
Assert-Eq $Calls.Confirm.Count 0 'X: tepsi açıkken onay kutusu çıkmaz'
# b) tepsi var, ayar kapalı, işlem yok: uygulama kapanır
Reset-Calls; $script:Settings = @{ TrayMinimize = $false }; $script:FakeBusy = $false
Invoke-CloseRequest
Assert-Eq $Calls.Exit 1 'X: tepsi kapalıyken uygulama kapanır'
Assert-Eq $Calls.Hide 0 'X: tepsi kapalıyken pencere gizlenmez'
# c) tepsi simgesi yok, ayar açık: gizlemek kullanıcıyı kilitler, uygulama kapanır
Reset-Calls; $script:Tray = $null; $script:Settings = @{ TrayMinimize = $true }; $script:FakeBusy = $false
Invoke-CloseRequest
Assert-Eq $Calls.Exit 1 'X: tepsi simgesi kurulmadıysa uygulama kapanır'
Assert-Eq $Calls.Hide 0 'X: tepsi simgesi yokken pencere gizlenmez'
# d) tepsi kapalı, işlem sürüyor: önce sorulur (tehlikeli işlem olarak)
Reset-Calls; $script:Tray = New-FakeTray; $script:Settings = @{ TrayMinimize = $false }; $script:FakeBusy = $true
Invoke-CloseRequest
Assert-Eq $Calls.Exit 0 'X: işlem sürerken doğrudan kapanmaz'
Assert-Eq $Calls.Confirm.Count 1 'X: işlem sürerken onay istenir'
Assert-True ($Calls.Confirm[0] -like '*|True') 'X: onay kutusu tehlike kipinde'
# e) tepsi açık, işlem sürüyor: pencere gizlenir, iş arka planda sürer, soru sorulmaz
Reset-Calls; $script:Settings = @{ TrayMinimize = $true; TrayHints = 9 }; $script:FakeBusy = $true; $script:TrayBusyHintAt = [datetime]::MinValue
Invoke-CloseRequest
Assert-Eq $Calls.Hide 1 'X: işlem sürerken de pencere tepsiye iner'
Assert-Eq $Calls.Exit 0 'X: işlem sürerken uygulama kapanmaz (iş arka planda sürer)'
Assert-Eq $Calls.Confirm.Count 0 'X: tepsiye inerken onay çıkmaz'
Assert-Eq $Calls.Balloon.Count 1 'X: işlem sürerken simge bildirimi gösterilir'
Assert-True ($Calls.Balloon[0] -like '*tamamlanacak*') 'X: bildirim işin arka planda biteceğini söyler'

# ======================= 6) Hide-ToTray: pencere durumu ve ipucu bildirimleri =======================
$script:FakeBusy = $false
Reset-Calls; $script:Tray = New-FakeTray; $script:Win = New-FakeWin 'Maximized'; $script:LastShownState = 'Normal'; $script:TrayHintShown = $false; $script:Settings = @{ TrayMinimize = $true; TrayHints = 0 }
Hide-ToTray
Assert-Eq $script:LastShownState 'Maximized' 'tepsiye inmeden önceki durum (büyütülmüş) saklanır'
Assert-Eq $Calls.Hide 1 'pencere gizlenir'
Assert-Eq $Calls.Balloon.Count 1 'ilk kez: nasıl geri açılacağı bildirilir'
Assert-True ($Calls.Balloon[0] -like '*Tamamen kapat*') 'bildirim "Tamamen kapat" yolunu söyler'
Assert-True ($Calls.Keys -contains 'TrayHints=1') 'ipucu sayacı kalıcı olarak artar'
Hide-ToTray
Assert-Eq $Calls.Balloon.Count 1 'aynı oturumda ikinci kez bildirim yok'
$script:TrayHintShown = $false; $script:Settings.TrayHints = 2; $Calls.Balloon.Clear()
Hide-ToTray
Assert-Eq $Calls.Balloon.Count 0 'ipucu iki kez gösterildiyse sonraki açılışlarda sessiz'
$script:Win = New-FakeWin 'Minimized'; $script:LastShownState = 'Maximized'
Hide-ToTray
Assert-Eq $script:LastShownState 'Maximized' 'simge durumundayken önceki durum ezilmez'
$script:Win = New-FakeWin 'Normal'; $script:LastShownState = 'Maximized'
Hide-ToTray
Assert-Eq $script:LastShownState 'Normal' 'normal pencere: durum normal olarak saklanır'
# işlem sürerken 2 dakikada bir bildirim
$script:FakeBusy = $true; $script:TrayHintShown = $true; $script:Settings.TrayHints = 2; $script:TrayBusyHintAt = [datetime]::MinValue; $Calls.Balloon.Clear()
Hide-ToTray
Assert-Eq $Calls.Balloon.Count 1 'işlem sürerken gizlenince bildirim gösterilir'
Hide-ToTray
Assert-Eq $Calls.Balloon.Count 1 'iki dakika dolmadan yeniden bildirim yok'
$script:TrayBusyHintAt = (Get-Date).AddMinutes(-3)
Hide-ToTray
Assert-Eq $Calls.Balloon.Count 2 'iki dakika sonra yeniden bildirim'
$script:FakeBusy = $false
# tepsi simgesi yoksa hiçbir şey yapmaz
Reset-Calls; $script:Tray = $null
Hide-ToTray
Assert-Eq $Calls.Hide 0 'tepsi simgesi yoksa pencere gizlenmez'

# ======================= 7) Restore-FromTray =======================
$script:Tray = New-FakeTray
Reset-Calls; $script:Win = New-FakeWin 'Minimized'; $script:LastShownState = 'Maximized'
Restore-FromTray
Assert-Eq $Calls.Show 1 'geri getirme: pencere gösterilir'
Assert-Eq ([string]$script:Win.WindowState) 'Maximized' 'geri getirme: önceki büyütülmüş boyuta dönülür'
Assert-Eq $script:Win.ShowInTaskbar $true 'geri getirme: görev çubuğu düğmesi geri gelir'
Assert-Eq $Calls.Activate 1 'geri getirme: pencere öne alınır'
Assert-Eq $Calls.Focus 1 'geri getirme: odak verilir'
Assert-Eq $script:Win.Topmost $false 'geri getirme: üstte sabit kalmaz'
Reset-Calls; $script:Win = New-FakeWin 'Minimized'; $script:LastShownState = 'Normal'
Restore-FromTray
Assert-Eq ([string]$script:Win.WindowState) 'Normal' 'geri getirme: normal boyuta dönülür'
Reset-Calls; $script:Win = New-FakeWin 'Normal'; $script:LastShownState = 'Maximized'
Restore-FromTray
Assert-Eq ([string]$script:Win.WindowState) 'Normal' 'geri getirme: gizlenmiş normal pencere boyutu değişmez'

# ======================= 8) pencere durumu değişimi (simge durumuna küçültme) =======================
$script:ChromeFallback = $false
$ui = @{ Root = [pscustomobject]@{ Margin = $null } }
Reset-Calls; $script:Tray = New-FakeTray; $script:Win = New-FakeWin 'Maximized'; $script:LastShownState = 'Normal'; $script:Settings = @{ TrayMinimize = $true; TrayHints = 9 }
Invoke-WindowStateChanged
Assert-Eq $script:LastShownState 'Maximized' 'büyütülünce durum saklanır'
Assert-Eq $ui.Root.Margin.Left 8 'büyütülünce kenar boşluğu pencere çerçevesi kadar'
Assert-Eq $Calls.Hide 0 'büyütmek pencereyi gizlemez'
$script:ChromeFallback = $true; $ui.Root.Margin = $null
Invoke-WindowStateChanged
Assert-True ($null -eq $ui.Root.Margin) 'yedek pencere çerçevesinde kenar boşluğu verilmez'
$script:ChromeFallback = $false
$script:Win = New-FakeWin 'Normal'
Invoke-WindowStateChanged
Assert-Eq $script:LastShownState 'Normal' 'normale dönünce durum saklanır'
Assert-Eq $ui.Root.Margin.Left 0 'normalde kenar boşluğu sıfır'
# simge durumu: tepsi ayarı açık -> gizlenir
Reset-Calls; $script:LastShownState = 'Maximized'; $script:Win = New-FakeWin 'Minimized'; $script:Settings = @{ TrayMinimize = $true; TrayOnMinimize = $null; TrayHints = 9 }
Invoke-WindowStateChanged
Assert-Eq $Calls.Hide 1 'simge durumu: ayar açıkken pencere tepsiye iner'
Assert-Eq $script:LastShownState 'Maximized' 'simge durumu: önceki durum korunur (geri gelince büyütülmüş)'
# simge durumu: yalnızca küçültme ayarı kapalı
Reset-Calls; $script:Win = New-FakeWin 'Minimized'; $script:Settings = @{ TrayMinimize = $true; TrayOnMinimize = $false; TrayHints = 9 }
Invoke-WindowStateChanged
Assert-Eq $Calls.Hide 0 'simge durumu: küçültme ayarı kapalıysa görev çubuğunda kalır'
# simge durumu: X ayarı kapalı ama küçültme ayarı açık
Reset-Calls; $script:Win = New-FakeWin 'Minimized'; $script:Settings = @{ TrayMinimize = $false; TrayOnMinimize = $true; TrayHints = 9 }
Invoke-WindowStateChanged
Assert-Eq $Calls.Hide 1 'simge durumu: küçültme ayarı tek başına yeter'
# simge durumu: tepsi simgesi yok
Reset-Calls; $script:Tray = $null; $script:Win = New-FakeWin 'Minimized'; $script:Settings = @{ TrayMinimize = $true; TrayHints = 9 }
Invoke-WindowStateChanged
Assert-Eq $Calls.Hide 0 'simge durumu: tepsi simgesi yoksa görev çubuğunda kalır'
# geri getirme sürerken gelen "küçültüldü" olayı (Show çağrısı tetikleyebilir) pencereyi yeniden gizlemez
$script:Tray = New-FakeTray
Reset-Calls; $script:LastShownState = 'Normal'; $script:Settings = @{ TrayMinimize = $true; TrayOnMinimize = $true; TrayHints = 9 }
$script:Win = New-FakeWin 'Minimized'
Add-Member -InputObject $script:Win -MemberType ScriptMethod -Name Show -Force -Value { $global:Calls.Show++; Invoke-WindowStateChanged }
Restore-FromTray
Assert-Eq $Calls.Show 1 'geri getirme: pencere bir kez gösterilir'
Assert-Eq $Calls.Hide 0 'geri getirme sürerken gelen küçültüldü olayı pencereyi yeniden gizlemez'
Assert-Eq ([string]$script:Win.WindowState) 'Normal' 'geri getirme: olay gelse de pencere normal boyuta döner'
Assert-Eq $script:TrayRestoring $false 'geri getirme bitince korunma bayrağı kalkar'
# hata olsa bile bayrak kalkar
Reset-Calls
$script:Win = New-FakeWin 'Minimized'
Add-Member -InputObject $script:Win -MemberType ScriptMethod -Name Show -Force -Value { throw 'deneme hatası' }
Restore-FromTray
Assert-Eq $script:TrayRestoring $false 'geri getirme hata verse de korunma bayrağı kalkar'
Assert-True (@($script:Log | Where-Object { $_ -like 'Restore-FromTray:*deneme hatası*' }).Count -eq 1) 'geri getirme hatası günlüğe yazılır'
# bayrak kalktıktan sonra gerçek küçültme yine tepsiye indirir
Reset-Calls; $script:Win = New-FakeWin 'Minimized'
Invoke-WindowStateChanged
Assert-Eq $Calls.Hide 1 'geri getirmeden sonra kullanıcı küçültünce pencere yine tepsiye iner'

# ======================= 9) varsayılan ayarlar =======================
$ds = Get-DefaultSettings
Assert-Eq $ds.Theme 'Acik' 'varsayılan tema beyaz (Acik)'
Assert-Eq $ds.Layout 'Sade' 'varsayılan yerleşim sade'
Assert-Eq $ds.Zoom 100 'varsayılan yakınlaştırma %100'
Assert-Eq $ds.SmoothScroll $true 'yumuşak kaydırma varsayılan açık'
Assert-Eq $ds.ToTopButton $true 'başa dön düğmesi varsayılan açık'
Assert-Eq $ds.FocusRing $true 'odak çerçevesi varsayılan açık'
Assert-True ($ds.ContainsKey('TrayOnMinimize') -and $null -eq $ds.TrayOnMinimize) 'simge durumu ayarı boş: X ayarını izler'
Assert-Eq $ds.TrayHints 0 'tepsi ipucu sayacı sıfır'
Assert-Eq $ds.TrayMinimize $true 'tepsi varsayılan açık (X ve simge durumu arka plana iner)'

# ======================= 10) derlenmiş betikte bağlantılar =======================
$src = [System.IO.File]::ReadAllText($env:MM_BUILD)
foreach ($cn in @('st_LookSel', 'st_ThemeSel', 'st_LayoutSel', 'st_ZoomSel')) {
    Assert-True ($src -match ('<ComboBox[^>]*x:Name="' + $cn + '"')) ('Ayarlar: acilir liste ' + $cn)
    Assert-True ($script:SmokeSafeSelect -contains $cn) ('duman testi güvenli liste kümesinde ' + $cn)
}
foreach ($old in @('st_Th_Neon', 'st_Th_Uzay', 'st_Ly_Sade', 'st_Zm_100', 'st_Pre_Hacker')) {
    Assert-True (-not $src.Contains('x:Name="' + $old + '"')) ('Ayarlar: eski yan yana seçenek kaldırıldı ' + $old)
    Assert-True ($script:SmokeSafe -notcontains $old) ('duman testi güvenli düğmelerinde eski seçenek yok ' + $old)
}
foreach ($n in @('st_Smooth', 'st_ToTop', 'st_FocusRing', 'st_TrayMin', 'st_ThDesc', 'st_LyDesc', 'TxtTagline', 'BodyGrid', 'ColLog', 'CmdPanel', 'TxtSys', 'RailHost', 'RailScroll', 'BtnPower', 'BtnClose', 'BtnLogToggle', 'PageHost')) {
    Assert-True ($src.Contains('x:Name="' + $n + '"')) ('arayüz öğesi: ' + $n)
}
# durum ve kapatma bağlantıları
Assert-True ($src -match '\$w\.Add_StateChanged\(\{\s+try \{ Invoke-WindowStateChanged \}') 'pencere durum değişimi Invoke-WindowStateChanged e bağlı'
Assert-True ($src -match '\$w\.Add_Closing\(\{[^}]*Invoke-CloseRequest' ) 'pencere kapatma isteği (Alt+F4) Invoke-CloseRequest e bağlı'
Assert-True ($src -match '\$ui\.BtnClose\.Add_Click\(\{ Invoke-Safe \{ Invoke-CloseRequest \}') 'X düğmesi Invoke-CloseRequest e bağlı'
Assert-True ($src -match '\$ui\.BtnPower\.Add_Click\(\{ Invoke-Safe \{ Request-FullExit \}') 'güç düğmesi tamamen kapatmayı ister'
Assert-True ($src -match "Add-TrayItem 'exit' 'Tamamen kapat'") 'tepsi menüsünde "Tamamen kapat" var'
Assert-True ($src -match 'try \{ Initialize-Layout \}' -and $src -match 'try \{ Initialize-Scrolling \}') 'açılışta yerleşim ve kaydırma kurulur'
Assert-True ($src -match 'Sync-RailGroups \$railKey; Sync-FlyRail \$Key; Close-NavMenu; Update-ToTop \$null') 'sayfa değişince menü grubu açılır ve başa dön düğmesi güncellenir'
Assert-True ($src -match 'Request-FullExit') 'tamamen çıkış isteği tanımlı'
# ana betikteki eski tepsi işlevleri kalmadı (tek tanım): modüldekiler geçerli
foreach ($fn in @('Invoke-CloseRequest', 'Hide-ToTray', 'Restore-FromTray', 'Invoke-WindowStateChanged', 'Get-TrayOnClose', 'Get-TrayOnMinimize')) {
    $cnt = @(Get-AstFunctions | Where-Object { $_.Name -eq $fn }).Count
    Assert-Eq $cnt 1 ($fn + ' tek kez tanımlı')
}
# ikinci açılış sinyali zamanlayıcısı: tek tanım, normal öncelik, kısa aralık, sayaçlar ve görünür hata günlüğü
$sst = @(Get-AstFunctions | Where-Object { $_.Name -eq 'Start-ShowSignalTimer' })
Assert-Eq $sst.Count 1 'Start-ShowSignalTimer tek kez tanımlı'
if ($sst.Count -eq 1) {
    $sstTxt = $sst[0].Extent.Text
    Assert-True ($sstTxt -match 'DispatcherPriority\]::Normal') 'sinyal zamanlayıcısı normal öncelikli (arka plan işlerinin arkasında kalmaz)'
    Assert-True ($sstTxt -match 'FromMilliseconds\(400\)') 'sinyal zamanlayıcısı 400 ms aralıklı'
    Assert-True ($sstTxt -match 'SigTicks' -and $sstTxt -match 'SigFired') 'sinyal zamanlayıcısı tik ve tetiklenme sayaçlarını tutar'
    Assert-True ($sstTxt -match 'Write-CrashLog' -and $sstTxt -notmatch 'catch \{ \}') 'sinyal zamanlayıcısı hatayı yutmaz, günlüğe yazar'
}
# sistem güvenlik kapısı: yeni modüller Defender / Güvenlik Duvarı / Windows Update / UAC ayarlarına dokunmaz
$modTxt = ((Get-AstFunctions | Where-Object { $_.Name -in @('Invoke-WheelRoute', 'Invoke-KeyRoute', 'Initialize-Scrolling', 'Set-AppLayout', 'Set-UiZoom', 'Hide-ToTray', 'Restore-FromTray', 'Invoke-CloseRequest', 'Initialize-Layout') } | ForEach-Object { $_.Extent.Text }) -join "`n")
Assert-True ($modTxt.Length -gt 2000) 'yeni modül işlevleri bulundu'
Assert-True ($modTxt -notmatch 'Set-MpPreference|netsh|HKLM|HKCU|Set-Service|Stop-Service|wuauserv|Disable-|reg add') 'görünüm, kaydırma ve tepsi kodu sistem ayarına dokunmaz'

function Get-FnText([string]$Name) {
    $f = @(Get-AstFunctions | Where-Object { ($_.Name -replace '^global:', '') -eq $Name }) | Select-Object -Last 1
    if ($null -eq $f) { return '' }
    return $f.Extent.Text
}

# ======================= 11) açılır liste yardımcıları =======================
$script:StLoading = $false
$c = New-FakeCombo
$ch = @((New-Choice 'a' 'Alfa'), (New-Choice 'b' 'Beta' @('#111111', '#222222')), (New-Choice 'c' 'Gama' @('#010203', $null, '#0A0B0C', '#0D0E0F', '#FFFFFF')))
Assert-Eq $ch[0].Key 'a' 'seçenek: anahtar'
Assert-Eq $ch[0].Name 'Alfa' 'seçenek: ad'
Assert-Eq "$($ch[0].C1)|$($ch[0].C4)" '#00000000|#00000000' 'seçenek: renk verilmezse saydam'
Assert-Eq "$($ch[1].C1)|$($ch[1].C2)|$($ch[1].C3)" '#111111|#222222|#00000000' 'seçenek: verilen renkler sırayla, kalanı saydam'
Assert-Eq "$($ch[2].C1)|$($ch[2].C2)|$($ch[2].C3)|$($ch[2].C4)" '#010203|#00000000|#0A0B0C|#0D0E0F' 'seçenek: boş renk atlanır, en çok dört renk'
Set-ComboChoices $c $ch
Assert-Eq $c.Items.Count 3 'liste: seçenekler eklendi'
Set-ComboChoices $c $ch
Assert-Eq $c.Items.Count 3 'liste: yeniden doldurmak çoğaltmaz'
Set-ComboChoices $c @()
Assert-Eq $c.Items.Count 0 'liste: boş doldurma temizler'
Set-ComboChoices $c $ch
Assert-Eq (Get-ComboKey $c) '' 'liste: seçim yokken anahtar boş'
Assert-True ((Select-ComboKey $c 'b') -eq $true) 'liste: var olan anahtar seçilir'
Assert-Eq (Get-ComboKey $c) 'b' 'liste: seçili anahtar okunur'
Assert-Eq $c.SelectedIndex 1 'liste: seçili sıra'
Assert-True ((Select-ComboKey $c 'yok') -eq $false) 'liste: olmayan anahtar bulunamadı döner'
Assert-Eq $c.SelectedIndex -1 'liste: olmayan anahtar seçimi kaldırır'
Assert-Eq (Get-ComboKey $c) '' 'liste: seçimsizken anahtar boş'
Assert-True ((Select-ComboKey $null 'a') -eq $false) 'liste: null liste hata vermez (seç)'
Assert-Eq (Get-ComboKey $null) '' 'liste: null liste hata vermez (oku)'
Set-ComboChoices $null $ch
Assert-True ($script:StLoading -eq $false) 'liste: işlemden sonra yükleme bayrağı kalkar'
$script:StLoading = $true
[void](Select-ComboKey $c 'a')
Assert-True ($script:StLoading -eq $true) 'liste: dışarıdan açık bayrak korunur'
$script:StLoading = $false

# açılır pencere koruması
$cb = New-Object System.Windows.Controls.ComboBox
$pop = New-Object System.Windows.Controls.Primitives.Popup
$pop.TemplatedParent = $cb
$root = New-Object System.Windows.Controls.Border; $root.Parent = $pop
$leaf = New-Object System.Windows.Controls.ComboBoxItem; $leaf.P = $root
Assert-True ([object]::ReferenceEquals((Get-ComboOfPopupSource $leaf), $cb)) 'açılır pencere: içindeki öğeden ComboBox bulunur'
Assert-True ([object]::ReferenceEquals((Get-ComboOfPopupSource $root), $cb)) 'açılır pencere: kök öğeden de bulunur'
$other = New-Object System.Windows.Controls.Border; $leaf2 = New-Object System.Windows.Controls.Border; $leaf2.P = $other
Assert-True ($null -eq (Get-ComboOfPopupSource $leaf2)) 'açılır pencere: sıradan öğe için boş döner'
$pop2 = New-Object System.Windows.Controls.Primitives.Popup; $pop2.TemplatedParent = (New-Object System.Windows.Controls.Button)
$r2 = New-Object System.Windows.Controls.Border; $r2.Parent = $pop2
Assert-True ($null -eq (Get-ComboOfPopupSource $r2)) 'açılır pencere: ComboBox olmayan pencere için boş döner'
Assert-True ($null -eq (Get-ComboOfPopupSource $null)) 'açılır pencere: null kaynak hata vermez'
$loopA = New-Object System.Windows.Controls.Border; $loopB = New-Object System.Windows.Controls.Border; $loopA.P = $loopB; $loopB.P = $loopA
Assert-True ($null -eq (Get-ComboOfPopupSource $loopA)) 'açılır pencere: döngülü ağaçta sonsuz döngüye girmez'
$wr = (@(Get-AstFunctions | Where-Object { $_.Name -eq 'Invoke-WheelRoute' })[0]).Extent.Text
Assert-True ($wr.Contains('Get-ComboOfPopupSource $src')) 'tekerlek yönlendirme: açılır liste koruması var'
Assert-True ($wr.IndexOf('Get-ComboOfPopupSource $src') -lt $wr.IndexOf('Get-PageScroller')) 'tekerlek yönlendirme: koruma sayfa kaydırıcısından önce'

# ======================= 12) renk örneği ve hazır görünümler =======================
Assert-Eq (Merge-HexOver '#FF0000' '#000000') '#FF0000' 'renk karışımı: opak üst renk aynen'
Assert-Eq (Merge-HexOver '#00FF0000' '#102030') '#102030' 'renk karışımı: tam saydam üst renk alttakini verir'
Assert-Eq (Merge-HexOver '#80FFFFFF' '#000000') '#808080' 'renk karışımı: yarı saydam beyaz siyah üstünde gri'
Assert-Eq (Merge-HexOver 'FFFFFF' '#000000') '#FFFFFF' 'renk karışımı: # işaretsiz yazım'
Assert-Eq (Merge-HexOver '#CC102030' '#FF405060') '#1A2A3A' 'renk karışımı: alt renk alfa taşısa da opak sayılır'
Assert-Eq (Merge-HexOver 'sacma' '#000000') '#sacma' 'renk karışımı: geçersiz renk bozulmadan döner'
foreach ($tk in @($script:Themes.Keys)) {
    $sw = @(Get-ThemeSwatch ([string]$tk))
    Assert-Eq $sw.Count 4 "renk örneği ${tk}: dört renk"
    foreach ($hx in $sw) { Assert-True ([string]$hx -match '^#[0-9A-F]{6}$') "renk örneği ${tk}: geçerli #RRGGBB ($hx)" }
    Assert-True ($sw[2] -ne $sw[0]) "renk örneği ${tk}: vurgu zeminden ayırt edilir"
}
Assert-Eq (@(Get-ThemeSwatch 'yok')[0]) (@(Get-ThemeSwatch 'Acik')[0]) 'renk örneği: bilinmeyen tema varsayılan tema (Acik) gibi'

# hazır görünümler ve eşleştirme
$presetKeys = @($script:LookPresetNames.Keys)
Assert-Eq ($presetKeys -join ',') 'Varsayilan,KoyuNeon,KompaktKoyu,Hacker,Atolye,Sifir,Morpheus,Komuta' 'hazır görünüm sırası'
foreach ($pk in $presetKeys) {
    $lp = Get-LookPreset $pk
    $st = @{ Theme = $lp.Theme; Layout = $lp.Layout; Zoom = $lp.Zoom; Design = $lp.Design; Backdrop = $lp.Backdrop; WinOpacity = $lp.Opacity; HomeMode = $(if ($lp.HomeMode -ne '') { $lp.HomeMode } else { 'Pano' }) }
    Assert-Eq (Get-MatchingLookPreset $st) $pk "eşleştirme: $pk ayarları kendisine döner"
}
foreach ($pk in @('Atolye', 'Sifir', 'Morpheus', 'Komuta')) {
    Assert-Eq (Get-LookPreset $pk).HomeMode 'Pano' "$pk hazır görünümü ana ekranı pano yapar"
    $lp = Get-LookPreset $pk
    $st = @{ Theme = $lp.Theme; Layout = $lp.Layout; Zoom = $lp.Zoom; Design = $lp.Design; Backdrop = $lp.Backdrop; WinOpacity = $lp.Opacity; HomeMode = 'Klasik' }
    Assert-Eq (Get-MatchingLookPreset $st) 'Ozel' "eşleştirme: $pk ama ana ekran klasik durum panosu => Özel"
}
foreach ($pk in @('Varsayilan', 'KoyuNeon', 'KompaktKoyu', 'Hacker')) {
    Assert-Eq (Get-LookPreset $pk).HomeMode '' "$pk hazır görünümü ana ekran biçimine dokunmaz"
    $lp = Get-LookPreset $pk
    foreach ($hm in @('Pano', 'Klasik')) {
        $st = @{ Theme = $lp.Theme; Layout = $lp.Layout; Zoom = $lp.Zoom; Design = $lp.Design; Backdrop = 'Yok'; WinOpacity = 100; HomeMode = $hm }
        Assert-Eq (Get-MatchingLookPreset $st) $pk "eşleştirme: $pk, ana ekran $hm olsa da"
    }
}
Assert-Eq (Get-MatchingLookPreset @{ Theme = 'Neon'; Layout = 'Ayrintili'; Zoom = 100; Design = 'Klasik'; Backdrop = 'Yok'; WinOpacity = 100; DsNav = 'Fly' }) 'Ozel' 'eşleştirme: tasarım ayrıntısı seçilmişse Özel'
Assert-Eq (Get-MatchingLookPreset @{ Theme = 'Uzay'; Layout = 'Sade'; Zoom = 100; Design = 'Klasik' }) 'Ozel' 'eşleştirme: hazır olmayan birleşim Özel'
Assert-Eq (Get-MatchingLookPreset @{ Theme = 'Neon'; Layout = 'Ayrintili'; Zoom = 120; Design = 'Klasik' }) 'Ozel' 'eşleştirme: yakınlaştırma farklıysa Özel'
Assert-Eq (Get-MatchingLookPreset @{}) 'Varsayilan' 'eşleştirme: boş ayarlar Varsayılan'
Assert-Eq (Get-MatchingLookPreset @{ Theme = 'Neon'; Layout = 'Ayrintili'; Zoom = 100; Design = 'Klasik'; Backdrop = 'Mica'; WinOpacity = 80 }) 'Ozel' 'eşleştirme: saydamlık açıksa Varsayılan değil'

# Ayarlar sayfası: Load / Save (sahte açılır listeler)
$script:ui = @{}
foreach ($n in @('st_LookSel', 'st_ThemeSel', 'st_LayoutSel', 'st_ZoomSel', 'st_DesignSel', 'st_HomeSel', 'st_BackdropSel', 'st_OpacitySel', 'st_DsNavSel', 'st_DsRadiusSel', 'st_DsFontSel', 'st_DsGraphSel', 'st_DsSkinSel')) { $script:ui[$n] = New-FakeCombo }
foreach ($n in @('st_ReduceMotion', 'st_Smooth', 'st_ToTop', 'st_FocusRing')) { $script:ui[$n] = [pscustomobject]@{ IsChecked = $false } }
foreach ($n in @('st_ThDesc', 'st_LyDesc')) { $script:ui[$n] = [pscustomobject]@{ Text = '' } }
$ui = $script:ui
Initialize-StLookChoices
Assert-Eq (@($ui.st_ThemeSel.Items | ForEach-Object { $_['Key'] }) -join ',') ((@('Sistem') + @($script:Themes.Keys)) -join ',') 'tema listesi: önce Sistem, sonra tüm temalar tablo sırasında'
Assert-True (@($ui.st_ThemeSel.Items | Where-Object { $_['C1'] -match '^#[0-9A-F]{6}$' -and $_['C3'] -match '^#[0-9A-F]{6}$' }).Count -eq ($script:Themes.Count + 1)) 'tema listesi: her seçeneğin (Sistem dahil) renk örneği var'
Assert-Eq (@($ui.st_LayoutSel.Items | ForEach-Object { $_['Key'] }) -join ',') (@($script:LayoutInfo.Keys) -join ',') 'yerleşim listesi: tüm yerleşimler'
Assert-Eq (@($ui.st_ZoomSel.Items | ForEach-Object { $_['Key'] }) -join ',') ($script:ZoomSteps -join ',') 'yakınlaştırma listesi: basamaklar'
Assert-Eq (@($ui.st_ZoomSel.Items | ForEach-Object { $_['Name'] }) -join ',') ((@($script:ZoomSteps) | ForEach-Object { '%' + $_ }) -join ',') 'yakınlaştırma listesi: yüzdeli adlar'
Assert-Eq (@($ui.st_LookSel.Items | ForEach-Object { $_['Key'] }) -join ',') ('Ozel,' + (@($script:LookPresetNames.Keys) -join ',')) 'hazır görünüm listesi: Özel + hazırlar'
$script:Settings = @{ Theme = 'Uzay'; Layout = 'Sade'; Zoom = 90; ReduceMotion = $true; SmoothScroll = $false; ToTopButton = $true; FocusRing = $false; Design = 'Klasik'; HomeMode = 'Pano' }
Load-StLook
Assert-Eq (Get-ComboKey $ui.st_ThemeSel) 'Uzay' 'yükle: tema seçili'
Assert-Eq (Get-ComboKey $ui.st_LayoutSel) 'Sade' 'yükle: yerleşim seçili'
Assert-Eq (Get-ComboKey $ui.st_ZoomSel) '90' 'yükle: yakınlaştırma seçili'
Assert-Eq (Get-ComboKey $ui.st_LookSel) 'Ozel' 'yükle: hazır olmayan birleşimde Özel seçili'
Assert-True ($ui.st_ReduceMotion.IsChecked -eq $true -and $ui.st_Smooth.IsChecked -eq $false -and $ui.st_ToTop.IsChecked -eq $true -and $ui.st_FocusRing.IsChecked -eq $false) 'yükle: açma-kapama seçenekleri'
Assert-True ($ui.st_ThDesc.Text -like '*Uzay*' -or $ui.st_ThDesc.Text -ne '') 'yükle: tema açıklaması yazıldı'
Assert-True ($ui.st_LyDesc.Text -ne '') 'yükle: yerleşim açıklaması yazıldı'
$script:Settings = @{ Theme = 'Acik'; Layout = 'Sade'; Zoom = 100; Design = 'Klasik'; Backdrop = 'Yok'; WinOpacity = 100 }
Load-StLook
Assert-Eq (Get-ComboKey $ui.st_LookSel) 'Varsayilan' 'yükle: varsayılan birleşimde (beyaz, sade) Varsayılan seçili'
$script:Settings = @{ Theme = 'Neon'; Layout = 'Ayrintili'; Zoom = 100; Design = 'Klasik'; Backdrop = 'Yok'; WinOpacity = 100 }
Load-StLook
Assert-Eq (Get-ComboKey $ui.st_LookSel) 'KoyuNeon' 'yükle: Neon ve ayrıntılı birleşimde Koyu neon seçili'
$script:Settings = @{ Theme = 'Neon'; Layout = 'Ayrintili'; Zoom = 123 }
Load-StLook
Assert-Eq (Get-ComboKey $ui.st_ZoomSel) '120' 'yükle: aradaki yakınlaştırma en yakın basamağa oturur'
# Save-StLook: değişen seçimler uygulanır, değişmeyenlere dokunulmaz
$script:Calls2 = New-Object System.Collections.ArrayList
function global:Select-Theme([string]$Name) { [void]$script:Calls2.Add('theme:' + $Name); $script:Settings.Theme = $Name; return $true }
function global:Select-Layout([string]$Name) { [void]$script:Calls2.Add('layout:' + $Name); $script:Settings.Layout = $Name; return $true }
function global:Set-UiZoom([int]$Pct, [bool]$Save = $true) { [void]$script:Calls2.Add('zoom:' + $Pct + ':' + $Save) }
$script:Settings = @{ Theme = 'Neon'; Layout = 'Ayrintili'; Zoom = 100; ReduceMotion = $false; SmoothScroll = $true; ToTopButton = $true; FocusRing = $true }
Load-StLook
Save-StLook
Assert-Eq $script:Calls2.Count 0 'kaydet: değişiklik yoksa hiçbir şey uygulanmaz'
[void](Select-ComboKey $ui.st_ThemeSel 'Acik'); [void](Select-ComboKey $ui.st_LayoutSel 'Hacker'); [void](Select-ComboKey $ui.st_ZoomSel '110')
$ui.st_ReduceMotion.IsChecked = $true; $ui.st_Smooth.IsChecked = $false
Save-StLook
Assert-Eq ($script:Calls2 -join ',') 'theme:Acik,layout:Hacker,zoom:110:False' 'kaydet: üç seçim sırayla uygulanır'
Assert-Eq "$($script:Settings.Theme)|$($script:Settings.Layout)|$($script:Settings.Zoom)" 'Acik|Hacker|110' 'kaydet: ayarlara yazıldı'
Assert-True ($script:Settings.ReduceMotion -eq $true -and $script:Settings.SmoothScroll -eq $false -and $script:Settings.ToTopButton -eq $true -and $script:Settings.FocusRing -eq $true) 'kaydet: açma-kapama seçenekleri yazıldı'
$script:Calls2.Clear()
$ui.st_ThemeSel.SelectedIndex = -1; $ui.st_LayoutSel.SelectedIndex = -1; $ui.st_ZoomSel.SelectedIndex = -1
Save-StLook
Assert-Eq $script:Calls2.Count 0 'kaydet: seçimsiz listeler hiçbir şey uygulamaz'
Assert-Eq "$($script:Settings.Theme)|$($script:Settings.Layout)|$($script:Settings.Zoom)" 'Acik|Hacker|110' 'kaydet: seçimsiz listeler ayarı bozmaz'
Remove-Item function:global:Select-Theme, function:global:Select-Layout, function:global:Set-UiZoom -ErrorAction SilentlyContinue

# Save-StDesign: tasarım değişince eski ayrıntı seçimleri geri yazılmaz; yalnızca ayrıntı ya da ana ekran biçimi değişince o uygulanır
Import-Fn 'Save-StDesign', 'Load-StDesign', 'Update-StDesignText', 'Initialize-StDesignChoices', 'Clear-DesignOverrides'
$script:ui['st_DsAdv'] = [pscustomobject]@{ IsChecked = $false }
foreach ($n in @('st_DsDesc', 'st_HomeDesc')) { $script:ui[$n] = [pscustomobject]@{ Text = '' } }
Initialize-StDesignChoices
$script:Calls3 = New-Object System.Collections.ArrayList
function global:Select-Design([string]$Name) { [void]$script:Calls3.Add('design:' + $Name); $script:Settings.Design = $Name; Clear-DesignOverrides $script:Settings; return $true }
function global:Select-HomeMode([string]$Name) { [void]$script:Calls3.Add('home:' + $Name); $script:Settings.HomeMode = $Name; return $true }
function global:Select-DesignOverride([string]$Prop, [string]$Value) { [void]$script:Calls3.Add('ds:' + $Prop + '=' + $Value); $script:Settings[('Ds' + $Prop)] = $Value; return $true }
$script:Settings = @{ Design = 'Morpheus'; HomeMode = 'Pano'; DsNav = 'Rail'; DsRadius = 'Round'; DsFont = 'Sans'; DsGraph = 'area'; DsSkin = 'Plain' }
Load-StDesign
Assert-Eq "$(Get-ComboKey $ui.st_DesignSel)|$(Get-ComboKey $ui.st_DsNavSel)|$(Get-ComboKey $ui.st_DsRadiusSel)|$(Get-ComboKey $ui.st_DsFontSel)|$(Get-ComboKey $ui.st_DsGraphSel)|$(Get-ComboKey $ui.st_DsSkinSel)" 'Morpheus|Rail|Round|Sans|area|Plain' 'tasarım listeleri: yükleme (ayrıntılar seçili)'
Assert-True ($ui.st_DsAdv.IsChecked -eq $true) 'tasarım ayrıntıları paneli: ayrıntı seçiliyse açılır'
Save-StDesign
Assert-Eq $script:Calls3.Count 0 'tasarım kaydet: değişiklik yoksa hiçbir şey uygulanmaz'
[void](Select-ComboKey $ui.st_DesignSel 'Komuta')
Save-StDesign
Assert-Eq ($script:Calls3 -join ',') 'design:Komuta' 'tasarım kaydet: tasarım değişince yalnızca tasarım uygulanır (eski ayrıntılar geri yazılmaz)'
foreach ($p in @($script:DsOptions.Keys)) {
    Assert-Eq $script:Settings[('Ds' + [string]$p)] 'Auto' "tasarım kaydet: tasarım değişince Ds$p sıfırlı kalır"
    Assert-Eq (Get-ComboKey $ui[('st_Ds' + [string]$p + 'Sel')]) 'Auto' "tasarım kaydet: Ds$p listesi 'Tasarıma göre' gösterir"
}
Assert-Eq (Get-ComboKey $ui.st_DesignSel) 'Komuta' 'tasarım kaydet: tasarım listesi yeni seçimi gösterir'
$script:Calls3.Clear()
[void](Select-ComboKey $ui.st_DsFontSel 'Mono')
Save-StDesign
Assert-Eq ($script:Calls3 -join ',') 'ds:Font=Mono' 'tasarım kaydet: yalnızca değişen ayrıntı uygulanır'
Assert-Eq (Get-ComboKey $ui.st_DsFontSel) 'Mono' 'tasarım kaydet: ayrıntı listesi seçimi korur'
$script:Calls3.Clear()
[void](Select-ComboKey $ui.st_HomeSel 'Klasik')
Save-StDesign
Assert-Eq ($script:Calls3 -join ',') 'home:Klasik' 'tasarım kaydet: ana ekran biçimi değişince yalnızca o uygulanır'
Assert-Eq $script:Settings.DsFont 'Mono' 'tasarım kaydet: ana ekran biçimi ayrıntılara dokunmaz'
Remove-Item function:global:Select-Design, function:global:Select-HomeMode, function:global:Select-DesignOverride -ErrorAction SilentlyContinue

# ======================= 13) kaynak düzeyi bağlantılar =======================
$ap = Get-FnText 'Apply-LookPreset'
foreach ($call in @('Select-Theme', 'Select-Layout', 'Select-Design', 'Select-HomeMode', 'Select-Glass', 'Set-UiZoom', 'Sync-StLookControls')) { Assert-True ($ap.Contains($call)) "Apply-LookPreset: $call çağrılır" }
Assert-True ($ap.IndexOf('Select-Design') -lt $ap.IndexOf('Select-HomeMode')) 'Apply-LookPreset: ana ekran biçimi tasarımdan sonra (tasarım seçimi ayrıntıları sıfırlar)'
Assert-True ((Get-FnText 'Sync-StLookControls').Contains('Load-StDesign')) 'Sync-StLookControls: tasarım listeleri de yenilenir'
Assert-True ($src.Contains('ComboToggle') -and $src.Contains('x:Key="ComboText"') -and $src.Contains('x:Key="ComboTheme"')) 'açılır liste şablonları ve stilleri var'

Show-Result
