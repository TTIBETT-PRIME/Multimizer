# Tema uygulamasi: WPF kaynak sozlugune PSObject sarmalli firca yazilmamali (7.1.0'da uygulamanin acilmamasinin kok nedeni).
# Linux'ta WPF yok; ayni ad alanindaki kucuk sahte siniflarla Set-AppTheme / Set-BrushColor / Get-ThemeProblems gercek kodla calistirilir.
. "$PSScriptRoot/lib.ps1"

Add-Type -ReferencedAssemblies @([psobject].Assembly.Location, 'System.Collections', 'System.Runtime', 'netstandard') -TypeDefinition @'
using System;
using System.Collections;
using System.Collections.Generic;
namespace System.Windows.Media {
    public struct Color : IEquatable<Color> {
        public byte A, R, G, B;
        public bool Equals(Color o) { return A == o.A && R == o.R && G == o.G && B == o.B; }
        public override bool Equals(object o) { return o is Color && Equals((Color)o); }
        public override int GetHashCode() { return (A << 24) | (R << 16) | (G << 8) | B; }
        public override string ToString() { return string.Format("#{0:X2}{1:X2}{2:X2}{3:X2}", A, R, G, B); }
        public static bool operator ==(Color a, Color b) { return a.Equals(b); }
        public static bool operator !=(Color a, Color b) { return !a.Equals(b); }
    }
    public static class ColorConverter {
        public static object ConvertFromString(string s) {
            if (s == null || s.Length < 2 || s[0] != '#') throw new FormatException("gecersiz renk: " + s);
            string h = s.Substring(1);
            Color c = new Color();
            int i = 0;
            if (h.Length == 8) { c.A = Convert.ToByte(h.Substring(0, 2), 16); i = 2; }
            else if (h.Length == 6) { c.A = 255; }
            else throw new FormatException("gecersiz renk: " + s);
            c.R = Convert.ToByte(h.Substring(i, 2), 16);
            c.G = Convert.ToByte(h.Substring(i + 2, 2), 16);
            c.B = Convert.ToByte(h.Substring(i + 4, 2), 16);
            return c;
        }
    }
    public abstract class Freezable {
        private bool _frozen;
        public bool IsFrozen { get { return _frozen; } }
        public void Freeze() { _frozen = true; }
        protected void CheckWrite() { if (_frozen) throw new InvalidOperationException("Dondurulmus nesne degistirilemez"); }
    }
    public class Brush : Freezable { }
    public class SolidColorBrush : Brush {
        private Color _c;
        public SolidColorBrush() { }
        public SolidColorBrush(Color c) { _c = c; }
        public Color Color { get { return _c; } set { CheckWrite(); _c = value; } }
        public SolidColorBrush Clone() { return new SolidColorBrush(_c); }
    }
    public class GradientStop { public Color Color { get; set; } public double Offset { get; set; } }
    public class LinearGradientBrush : Brush {
        public List<GradientStop> GradientStops = new List<GradientStop>();
    }
}
namespace MmTest {
    // WPF ResourceDictionary gibi davranir: dizinleyiciyle yazilan degerin turu kaydedilir, Brush olmayan deger (PSObject dahil) kaydi tutulur.
    // Bilerek IDictionary DEGIL: PowerShell, sozluklerde $nesne.Ad atamasini alan yerine anahtar sayar ve sayaclari bozardi.
    public class FakeRes {
        private Dictionary<string, object> d = new Dictionary<string, object>();
        public int IndexerSets = 0;
        public List<string> BadTypes = new List<string>();
        public List<string> AddTypes = new List<string>();
        public string FailAddKey = "";
        private void Check(string key, object value) {
            string t = (value == null) ? "null" : value.GetType().FullName;
            if (!(value is System.Windows.Media.Brush)) BadTypes.Add(key + ":" + t);
        }
        public object this[string key] {
            get { object v; return d.TryGetValue(key, out v) ? v : null; }
            set { IndexerSets++; Check(key, value); d[key] = value; }
        }
        public bool Contains(string key) { return d.ContainsKey(key); }
        public void Remove(string key) { d.Remove(key); }
        public int Count { get { return d.Count; } }
        public void Add(string key, object value) {
            if (FailAddKey != "" && FailAddKey == key) throw new InvalidOperationException("kaynak eklenemedi: " + key);
            Check(key, value); AddTypes.Add(value.GetType().FullName); d.Add(key, value);
        }
    }
}
'@

Import-Fn 'Set-BrushColor', 'Get-ThemeProblems', 'Set-AppTheme', 'Get-Br', 'Sync-CodeBrushes', 'Get-CodeBrushProblems', 'Initialize-Appearance', 'Update-ReduceMotion', 'ConvertTo-ThemeKey', 'Get-RelLuminance', 'Get-ContrastRatio'
Import-Var 'Themes', 'ThemeGrads', 'ThemeInfo'
# Saydamlik bu pakette kapalidir (opaklik 1): tema renkleri aynen uygulanir. Saydamliga ozgu denetimler t_glass.ps1'dedir.
Import-Fn 'Get-GlassHex', 'Get-GlassAlphaFor'
Import-Var 'GlassShellKeys', 'GlassSurfaceKeys'
$script:GlassAlpha = 1.0
function global:Initialize-GlassState([string]$ThemeKey) { $script:GlassAlpha = 1.0 }
function global:Update-GlassTheme { }
$script:ThemeName = 'Neon'
$script:ThemeFail = 0
$script:BrushCache = @{}
$script:Logs = New-Object System.Collections.ArrayList
$script:CrashLogs = New-Object System.Collections.ArrayList
function global:Write-WhLog([string]$Message, [string]$Level = 'INFO') { [void]$script:Logs.Add($Level + ' ' + $Message) }
function global:Write-CrashLog([string]$Text) { [void]$script:CrashLogs.Add($Text) }
$script:SavedKeys = New-Object System.Collections.ArrayList
function global:Set-SettingsKeys($Keys) { foreach ($k in @($Keys.Keys)) { [void]$script:SavedKeys.Add($k + '=' + $Keys[$k]) } ; foreach ($k in @($Keys.Keys)) { $script:Settings[[string]$k] = $Keys[$k] } }
$sync = @{ Profile = @{ RamGB = 16 } }

function New-ThemeRes([string]$Theme) {
    $res = New-Object MmTest.FakeRes
    foreach ($k in @($script:Themes[$Theme].Keys)) {
        $col = [System.Windows.Media.Color][System.Windows.Media.ColorConverter]::ConvertFromString([string]$script:Themes[$Theme][$k])
        $res.Add($k, [System.Windows.Media.SolidColorBrush]::new($col))
    }
    $g = New-Object System.Windows.Media.LinearGradientBrush
    foreach ($h in @($script:ThemeGrads[$Theme])) {
        $gs = New-Object System.Windows.Media.GradientStop
        $gs.Color = [System.Windows.Media.Color][System.Windows.Media.ColorConverter]::ConvertFromString($h)
        $g.GradientStops.Add($gs)
    }
    $res.Add('BrBgGrad', $g)
    $res.IndexerSets = 0; $res.BadTypes.Clear(); $res.AddTypes.Clear()
    return , $res
}
# WPF penceresi gibi: Resources + FindResource / TryFindResource (kaynak sozlugunden okur)
function New-FakeWin($Resources) {
    $w = [pscustomobject]@{ Resources = $Resources }
    Add-Member -InputObject $w -MemberType ScriptMethod -Name TryFindResource -Value { param($k) return $this.Resources[[string]$k] }
    Add-Member -InputObject $w -MemberType ScriptMethod -Name FindResource -Value { param($k) $v = $this.Resources[[string]$k]; if ($null -eq $v) { throw ('kaynak yok: ' + $k) }; return $v }
    return $w
}
$ui = @{}
function Get-Hex($Res, [string]$Key) { return $Res[$Key].Color.ToString() }
function Norm([string]$Hex) { return ([System.Windows.Media.ColorConverter]::ConvertFromString($Hex)).ToString() }

# ---------------- 0) tablolar ----------------
$allThemes = @('Neon', 'Koyu', 'Acik', 'Kum', 'Yuksek', 'Hacker', 'Cam', 'Holo', 'Akis', 'Uzay')
$glassThemes = @('Cam', 'Holo', 'Akis', 'Uzay')
Assert-Eq ((@($script:Themes.Keys) | Sort-Object) -join ',') (($allThemes | Sort-Object) -join ',') 'on tema: Neon (Futuristik), Koyu, Acik (beyaz), Kum (sicak acik), Yuksek (yuksek karsitlik), Hacker + Cam (Buzlu Cam), Holo (Holografik), Akis (Renk Akisi), Uzay (Derin Uzay)'
Assert-True (-not $script:Themes.Contains('Sade')) 'eski Sade tema artik renk temasi degil (yerlesimdir)'
Assert-Eq (@($script:ThemeInfo.Keys) -join ',') ($allThemes -join ',') 'ThemeInfo tablosu temalarla ayni sirada'
foreach ($t in $allThemes) {
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$script:ThemeInfo[$t].T) -and -not [string]::IsNullOrWhiteSpace([string]$script:ThemeInfo[$t].D)) ($t + ': ad ve aciklama dolu')
}
$nk = @($script:Themes['Neon'].Keys).Count
Assert-Eq $nk 34 'Neon temasinda 34 renk anahtari (31 temel + 3 simge cipi zemini)'
foreach ($t in $allThemes) {
    Assert-Eq (@($script:Themes[$t].Keys) -join ',') (@($script:Themes['Neon'].Keys) -join ',') ($t + ' anahtarlari Neon ile ayni sirada ve ayni')
    Assert-Eq @($script:ThemeGrads[$t]).Count 3 ($t + ': arka plan gecisinin 3 rengi var')
    $badHex = @($script:Themes[$t].Keys | Where-Object { [string]$script:Themes[$t][$_] -notmatch '^#([0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$' })
    Assert-Eq ($badHex -join ',') '' ($t + ': tum renkler gecerli #RRGGBB / #AARRGGBB')
    $badGr = @($script:ThemeGrads[$t] | Where-Object { [string]$_ -notmatch '^#([0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$' })
    Assert-Eq $badGr.Count 0 ($t + ': gecis renkleri gecerli')
}

# bir rengi (#AARRGGBB) baska bir renk (#RRGGBB) uzerine birlestirir -> #RRGGBB (cam yuzeylerin etkin rengi)
function Get-CompositeHex([string]$Top, [string]$Under) {
    $t = $Top.TrimStart('#'); $u = $Under.TrimStart('#')
    $a = 1.0
    if ($t.Length -eq 8) { $a = [Convert]::ToInt32($t.Substring(0, 2), 16) / 255.0; $t = $t.Substring(2) }
    if ($u.Length -eq 8) { $u = $u.Substring(2) }
    $o = ''
    foreach ($i in 0, 2, 4) {
        $x = [Convert]::ToInt32($t.Substring($i, 2), 16); $y = [Convert]::ToInt32($u.Substring($i, 2), 16)
        $o += ([Convert]::ToInt32([math]::Round($a * $x + (1 - $a) * $y))).ToString('X2')
    }
    return ('#' + $o)
}

# WCAG karsitlik: her temada yazi, vurgu ve durum renkleri zeminlerinde okunur olmali (esikler: ana yazi >= 7, soluk >= 4.5, silik >= 3, vurgu >= 4.5, ...)
$surf = @('BrBg', 'BrTitle', 'BrRail', 'BrPanel', 'BrPanel2', 'BrCard')
$rules = @(
    @('BrText', 7.0, ($surf + @('BrHover', 'BrActiveBg'))),
    @('BrDim', 4.5, ($surf + @('BrHover', 'BrActiveBg'))),
    @('BrFaint', 3.0, @('BrBg', 'BrTitle', 'BrPanel', 'BrPanel2', 'BrCard')),
    @('BrAccent', 4.5, ($surf + @('BrHover', 'BrActiveBg'))),
    @('BrAccent2', 3.0, @('BrBg', 'BrPanel', 'BrCard')),
    @('BrBlue', 4.0, @('BrPanel', 'BrCard')),
    @('BrGold', 4.5, @('BrTitle', 'BrPanel', 'BrCard', 'BrGoldBg')),
    @('BrGood', 4.5, @('BrPanel', 'BrCard', 'BrTitle')),
    @('BrWarn', 4.5, @('BrPanel', 'BrCard')),
    @('BrBad', 4.0, @('BrPanel', 'BrCard', 'BrDangerBg')),
    @('BrInfo', 4.0, @('BrPanel', 'BrCard')),
    @('BrLogGreen', 4.5, @('BrPanel', 'BrCard')),
    @('BrDangerFg', 4.5, @('BrDangerBg')),
    @('BrText', 3.0, @('BrAccentDim'))
)
foreach ($t in $allThemes) {
    $tb = $script:Themes[$t]
    $weak = New-Object System.Collections.ArrayList
    $nCheck = 0
    foreach ($r in $rules) {
        foreach ($sf in $r[2]) {
            $nCheck++
            $cr = Get-ContrastRatio ([string]$tb[$r[0]]) ([string]$tb[$sf])
            if ($cr -lt [double]$r[1]) { [void]$weak.Add($r[0] + ' / ' + $sf + ' = ' + [math]::Round($cr, 2)) }
        }
    }
    Assert-Eq ($weak -join '; ') '' ($t + ': yazi / zemin karsitligi yeterli (' + $nCheck + ' olcum)')
    Assert-True ((Get-ContrastRatio ([string]$tb['BrOnAccent']) ([string]$tb['BrAccent'])) -ge 4.5) ($t + ': vurgulu dugmede yazi okunur')
    # sayfa basliklari dogrudan arka plan gecisinin ustune yazilir: gecisin her durağinda ana yazi >= 7, soluk yazi >= 4.5
    foreach ($gc in @($script:ThemeGrads[$t])) {
        Assert-True ((Get-ContrastRatio ([string]$tb['BrText']) ([string]$gc)) -ge 7.0) ($t + ': ana yazi arka plan gecisinde okunur (' + $gc + ')')
        Assert-True ((Get-ContrastRatio ([string]$tb['BrDim']) ([string]$gc)) -ge 4.5) ($t + ': soluk yazi arka plan gecisinde okunur (' + $gc + ')')
    }
    # yari saydam yuzeyler (cam): her gecis durağinin ustunde birlestirilmis (etkin) renkle olcum
    foreach ($gc in @($script:ThemeGrads[$t])) {
        $eff = @{}
        foreach ($sn in @('BrTitle', 'BrRail', 'BrPanel')) { $eff[$sn] = Get-CompositeHex ([string]$tb[$sn]) ([string]$gc) }
        $eff['BrCard'] = Get-CompositeHex ([string]$tb['BrCard']) $eff['BrPanel']
        $weakE = New-Object System.Collections.ArrayList
        foreach ($er in @(@('BrText', 7.0), @('BrDim', 4.5), @('BrAccent', 4.5), @('BrGood', 4.5), @('BrWarn', 4.5), @('BrBad', 4.0), @('BrInfo', 4.0), @('BrLogGreen', 4.5), @('BrGold', 4.5), @('BrBlue', 4.0), @('BrFaint', 3.0), @('BrAccent2', 3.0))) {
            foreach ($sn in @('BrTitle', 'BrRail', 'BrPanel', 'BrCard')) {
                $cr2 = Get-ContrastRatio ([string]$tb[$er[0]]) ([string]$eff[$sn])
                if ($cr2 -lt [double]$er[1]) { [void]$weakE.Add($er[0] + ' / ' + $sn + ' = ' + [math]::Round($cr2, 2)) }
            }
        }
        Assert-Eq ($weakE -join '; ') '' ($t + ': yari saydam yuzeylerin etkin renginde yazi okunur (gecis ' + $gc + ')')
        foreach ($ln in @('BrLine', 'BrLine2')) { Assert-True ((Get-ContrastRatio ([string]$tb[$ln]) ([string]$eff['BrCard'])) -ge 1.15) ($t + ': ' + $ln + ' etkin kart renginden ayrilir (gecis ' + $gc + ')') }
    }
    Assert-True ((Get-ContrastRatio '#FFFFFF' ([string]$tb['BrAccentDim'])) -ge 3.0) ($t + ': acik anahtarin beyaz topuzu secilir')
    foreach ($ln in @('BrLine', 'BrLine2')) { Assert-True ((Get-ContrastRatio ([string]$tb[$ln]) ([string]$tb['BrCard'])) -ge 1.15) ($t + ': ' + $ln + ' karttan ayrilir') }
}
# temalarin kimligi: yanlis paletin yanlis ada konmasini engeller
foreach ($t in @('Acik', 'Kum', 'Cam')) {
    Assert-True ((Get-RelLuminance ([string]$script:Themes[$t]['BrBg'])) -gt 0.7) ($t + ': zemin acik renk')
    Assert-True ((Get-RelLuminance ([string]$script:Themes[$t]['BrText'])) -lt 0.1) ($t + ': yazi koyu renk')
    foreach ($gc in @($script:ThemeGrads[$t])) { Assert-True ((Get-RelLuminance ([string]$gc)) -gt 0.55) ($t + ': arka plan gecisi acik renk (' + $gc + ')') }
}
foreach ($t in @('Neon', 'Koyu', 'Yuksek', 'Hacker', 'Holo', 'Akis', 'Uzay')) {
    Assert-True ((Get-RelLuminance ([string]$script:Themes[$t]['BrBg'])) -lt 0.05) ($t + ': zemin koyu renk')
    Assert-True ((Get-RelLuminance ([string]$script:Themes[$t]['BrText'])) -gt 0.7) ($t + ': yazi acik renk')
}
# cam temalari: Card / Row / Rail / baslik yari saydam; acilir pencere, bildirim ve diyalog yuzeyi (BrPanel2), cizgiler, vurgu ve durum zeminleri opak
function Get-AlphaOf([string]$Hex) { $h = $Hex.TrimStart('#'); if ($h.Length -eq 8) { return [Convert]::ToInt32($h.Substring(0, 2), 16) } else { return 255 } }
foreach ($t in $glassThemes) {
    $tb = $script:Themes[$t]
    foreach ($sn in @('BrTitle', 'BrRail', 'BrPanel', 'BrCard')) {
        $al = Get-AlphaOf ([string]$tb[$sn])
        Assert-True ($al -ge 0x80 -and $al -le 0xE6) ($t + ': ' + $sn + ' yari saydam (cam), ama okunur kalacak kadar dolgun (alfa ' + $al + ')')
    }
    foreach ($sn in @('BrBg', 'BrPanel2', 'BrLine', 'BrLine2', 'BrHover', 'BrActiveBg', 'BrGoldBg', 'BrDangerBg', 'BrAccent', 'BrText', 'BrMapBg')) {
        Assert-Eq (Get-AlphaOf ([string]$tb[$sn])) 255 ($t + ': ' + $sn + ' opak')
    }
    $gs = @($script:ThemeGrads[$t])
    Assert-Eq (@($gs | Select-Object -Unique).Count) 3 ($t + ': arka plan gecisinin uc rengi birbirinden farkli (cam arkasinda gorunur)')
}
foreach ($t in @('Neon', 'Koyu', 'Acik', 'Kum', 'Yuksek', 'Hacker')) {
    foreach ($sn in @('BrTitle', 'BrRail', 'BrPanel', 'BrCard', 'BrPanel2')) { Assert-Eq (Get-AlphaOf ([string]$script:Themes[$t][$sn])) 255 ($t + ': ' + $sn + ' opak (cam teması değil)') }
}
# renkli simge cipleri: her tema uc *Soft anahtari tasir; opak, simge rengi cipte okunur (>= 3:1), kart rengiyle karismaz
foreach ($t in $allThemes) {
    $tb = $script:Themes[$t]
    $cardBase = [string]$tb['BrCard']
    if ((Get-AlphaOf $cardBase) -ne 255) { $cardBase = [string]$tb['BrPanel2'] }
    foreach ($pr in @(@('BrBlueSoft', 'BrBlue'), @('BrGoodSoft', 'BrGood'), @('BrAccent2Soft', 'BrAccent2'))) {
        Assert-Eq (Get-AlphaOf ([string]$tb[$pr[0]])) 255 ($t + ': ' + $pr[0] + ' opak')
        Assert-True ((Get-ContrastRatio ([string]$tb[$pr[1]]) ([string]$tb[$pr[0]])) -ge 3.0) ($t + ': ' + $pr[1] + ' simgesi ' + $pr[0] + ' cipinde secilir')
        Assert-True ((Get-ContrastRatio ([string]$tb[$pr[0]]) $cardBase) -ge 1.08) ($t + ': ' + $pr[0] + ' kart renginden ayirt edilir')
    }
    Assert-True ((Get-ContrastRatio ([string]$tb['BrAccent']) ([string]$tb['BrActiveBg'])) -ge 4.5) ($t + ': vurgu simgesi BrActiveBg cipinde okunur')
    Assert-True ((Get-ContrastRatio ([string]$tb['BrGold']) ([string]$tb['BrGoldBg'])) -ge 4.5) ($t + ': altin simge BrGoldBg cipinde okunur')
    Assert-True ((Get-ContrastRatio ([string]$tb['BrWarn']) ([string]$tb['BrGoldBg'])) -ge 3.0) ($t + ': uyari simgesi BrGoldBg cipinde okunur')
}
# yeni ve yenilenen paletlerin kimligi
$ac = [string]$script:Themes['Acik']['BrAccent']
Assert-True ([Convert]::ToInt32($ac.Substring(5, 2), 16) -gt [Convert]::ToInt32($ac.Substring(1, 2), 16) + 40 -and [Convert]::ToInt32($ac.Substring(5, 2), 16) -gt [Convert]::ToInt32($ac.Substring(3, 2), 16) + 30 -and (Get-RelLuminance $ac) -lt 0.06) 'Acik: vurgu koyu lacivert (mavi kirmizi ve yesili asar, renk koyu)'
$ac2 = [string]$script:Themes['Acik']['BrAccent2']
Assert-True ([Convert]::ToInt32($ac2.Substring(5, 2), 16) -gt [Convert]::ToInt32($ac2.Substring(3, 2), 16) + 100 -and [Convert]::ToInt32($ac2.Substring(1, 2), 16) -gt [Convert]::ToInt32($ac2.Substring(3, 2), 16) + 40) 'Acik: ikinci vurgu eflatun (mavi ve kirmizi yesili asar)'
$kA = [string]$script:Themes['Kum']['BrAccent']
Assert-True ([Convert]::ToInt32($kA.Substring(1, 2), 16) -gt [Convert]::ToInt32($kA.Substring(5, 2), 16) + 80) 'Kum: vurgu kiremit (sicak ton)'
$kB = [string]$script:Themes['Kum']['BrBg']
Assert-True ([Convert]::ToInt32($kB.Substring(1, 2), 16) -gt [Convert]::ToInt32($kB.Substring(5, 2), 16) + 6) 'Kum: zemin krem (kirmizi maviden yuksek)'
$kyA = [string]$script:Themes['Koyu']['BrAccent']
Assert-True ([Convert]::ToInt32($kyA.Substring(5, 2), 16) -gt [Convert]::ToInt32($kyA.Substring(1, 2), 16) + 60) 'Koyu: vurgu mavi'
# gunluk satirlari renkle ayirt edilir: PLAN (ikinci vurgu) hata (BrBad), basari / bilgi (BrGood, BrLogGreen) ve uyari (BrWarn) renginden en az 60 derece uzak
function Get-HexHue([string]$Hex) {
    $h = $Hex.TrimStart('#'); if ($h.Length -eq 8) { $h = $h.Substring(2) }
    $r = [Convert]::ToInt32($h.Substring(0, 2), 16) / 255.0; $g = [Convert]::ToInt32($h.Substring(2, 2), 16) / 255.0; $b = [Convert]::ToInt32($h.Substring(4, 2), 16) / 255.0
    $mx = [math]::Max($r, [math]::Max($g, $b)); $mn = [math]::Min($r, [math]::Min($g, $b)); $d = $mx - $mn
    if ($d -lt 0.0001) { return 0.0 }
    if ($mx -eq $r) { $x = (($g - $b) / $d) } elseif ($mx -eq $g) { $x = (($b - $r) / $d) + 2.0 } else { $x = (($r - $g) / $d) + 4.0 }
    $deg = 60.0 * $x
    while ($deg -lt 0) { $deg += 360.0 }
    while ($deg -ge 360) { $deg -= 360.0 }
    return $deg
}
function Get-HueGap([double]$A, [double]$B) { $x = [math]::Abs($A - $B); return [math]::Min($x, 360.0 - $x) }
Assert-True ((Get-HueGap (Get-HexHue '#FF0000') (Get-HexHue '#00FF00')) -eq 120) 'ton hesabi: kirmizi ile yesil 120 derece'
Assert-True ([math]::Abs((Get-HexHue '#0000FF') - 240) -lt 0.01) 'ton hesabi: mavi 240 derece'
foreach ($t in @('Neon', 'Koyu', 'Acik', 'Kum', 'Uzay')) {
    $tb = $script:Themes[$t]
    $h2 = Get-HexHue ([string]$tb['BrAccent2'])
    foreach ($k in @('BrBad', 'BrLogGreen', 'BrGood', 'BrWarn')) {
        Assert-True ((Get-HueGap $h2 (Get-HexHue ([string]$tb[$k]))) -ge 60) ($t + ': PLAN rengi (BrAccent2) ' + $k + ' renginden ayirt edilir')
    }
    Assert-True ((Get-HueGap $h2 (Get-HexHue ([string]$tb['BrAccent']))) -ge 35) ($t + ': iki vurgu birbirinden ayirt edilir')
}
# ADIM satiri (BrAccent) ve UYARI satiri (BrWarn) da hata satirindan (BrBad) ayirt edilir; hata her temada ilk bakista secilmeli
foreach ($t in @($script:Themes.Keys)) {
    $tb = $script:Themes[$t]
    $hb = Get-HexHue ([string]$tb['BrBad'])
    Assert-True ((Get-HueGap $hb (Get-HexHue ([string]$tb['BrAccent']))) -ge 30) ($t + ': ADIM rengi (BrAccent) hata renginden (BrBad) en az 30 derece uzak')
    Assert-True ((Get-HueGap $hb (Get-HexHue ([string]$tb['BrWarn']))) -ge 20) ($t + ': UYARI rengi (BrWarn) hata renginden (BrBad) en az 20 derece uzak')
}
# tema kimlikleri
$hoB = [string]$script:Themes['Holo']['BrAccent']
Assert-True ([Convert]::ToInt32($hoB.Substring(5, 2), 16) -gt [Convert]::ToInt32($hoB.Substring(1, 2), 16) + 100 -and [Convert]::ToInt32($hoB.Substring(3, 2), 16) -gt [Convert]::ToInt32($hoB.Substring(1, 2), 16) + 100) 'Holo: vurgu turkuaz (mavi ve yesil kirmiziyi asar)'
Assert-True ((Get-RelLuminance ([string]$script:Themes['Holo']['BrLine2'])) -gt 0.08) 'Holo: ikinci cizgi rengi parlak (parlayan cerceve)'
$uzA = [string]$script:Themes['Uzay']['BrAccent']
Assert-True ([Convert]::ToInt32($uzA.Substring(1, 2), 16) -gt [Convert]::ToInt32($uzA.Substring(3, 2), 16) + 80 -and [Convert]::ToInt32($uzA.Substring(1, 2), 16) -gt [Convert]::ToInt32($uzA.Substring(5, 2), 16) + 60) 'Uzay: vurgu kirmizi-gul tonlu'
$uzG = @($script:ThemeGrads['Uzay'])
Assert-True ((Get-RelLuminance $uzG[0]) -lt 0.01) 'Uzay: gecis cok koyu mor rengle baslar'
$akG = @($script:ThemeGrads['Akis'])
$akSpread = 0
foreach ($i in 0..1) { foreach ($j in ($i + 1)..2) { $ca = [Convert]::ToInt32($akG[$i].Substring(1, 2), 16) - [Convert]::ToInt32($akG[$j].Substring(1, 2), 16); $cb = [Convert]::ToInt32($akG[$i].Substring(3, 2), 16) - [Convert]::ToInt32($akG[$j].Substring(3, 2), 16); $cc = [Convert]::ToInt32($akG[$i].Substring(5, 2), 16) - [Convert]::ToInt32($akG[$j].Substring(5, 2), 16); $dist = [math]::Sqrt($ca * $ca + $cb * $cb + $cc * $cc); if ($akSpread -eq 0 -or $dist -lt $akSpread) { $akSpread = $dist } } }
Assert-True ($akSpread -gt 60) 'Akis: gecisin uc rengi birbirinden belirgin ayrilir (canli renk akisi)'
Assert-Eq ([string]$script:Themes['Yuksek']['BrBg']) '#000000' 'Yuksek: zemin saf siyah'
Assert-Eq ([string]$script:Themes['Yuksek']['BrText']) '#FFFFFF' 'Yuksek: yazi saf beyaz'
Assert-True ((Get-ContrastRatio ([string]$script:Themes['Yuksek']['BrText']) ([string]$script:Themes['Yuksek']['BrBg'])) -ge 21.0) 'Yuksek: ana yazi karsitligi 21:1'
$hk = [string]$script:Themes['Hacker']['BrAccent']
$hr = [Convert]::ToInt32($hk.Substring(1, 2), 16); $hg = [Convert]::ToInt32($hk.Substring(3, 2), 16); $hb = [Convert]::ToInt32($hk.Substring(5, 2), 16)
Assert-True ($hg -gt 200 -and $hr -lt 60 -and $hb -lt 120) 'Hacker: vurgu fosfor yesili'
$ht = [string]$script:Themes['Hacker']['BrText']
Assert-True ([Convert]::ToInt32($ht.Substring(3, 2), 16) -gt [Convert]::ToInt32($ht.Substring(1, 2), 16)) 'Hacker: yazi yesil tonlu'
# temalar birbirinden ayirt edilebilir: hicbir iki tema ayni palet degil
$sigs = @($allThemes | ForEach-Object { (@($script:Themes[$_].Values) -join '|') })
Assert-Eq (@($sigs | Select-Object -Unique).Count) 10 'on tema birbirinden farkli'
$gsigs = @($allThemes | ForEach-Object { (@($script:ThemeGrads[$_]) -join '|') })
Assert-Eq (@($gsigs | Select-Object -Unique).Count) 10 'on temanin arka plan gecisi birbirinden farkli'

# ---------------- 1) eski yontemin tehlikesi (olumsuz sinama): dizinleyiciyle New-Object yazmak PSObject saklar ----------------
$old = New-Object MmTest.FakeRes
$old['BrBg'] = New-Object System.Windows.Media.SolidColorBrush -ArgumentList ([System.Windows.Media.Color][System.Windows.Media.ColorConverter]::ConvertFromString('#15181D'))
Assert-Eq $old.IndexerSets 1 'eski yontem: dizinleyici kullanildi'
Assert-True ($old.BadTypes.Count -eq 1 -and $old.BadTypes[0] -match 'PSObject') 'eski yontem: kaynaga PSObject sarmalli firca yazilir (cokme nedeni) - sinama tehlikeyi yakalayabiliyor'
$ok = New-Object MmTest.FakeRes
$ok['BrBg'] = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color][System.Windows.Media.ColorConverter]::ConvertFromString('#15181D'))
Assert-Eq $ok.BadTypes.Count 0 '::new ile yazilan firca sarmalsiz'
$ok.Add('BrBg2', (New-Object System.Windows.Media.SolidColorBrush))
Assert-Eq $ok.BadTypes.Count 0 'yontem argumani (Add) New-Object sonucunu da acar'

# ---------------- 2) Set-AppTheme: yerinde guncelleme ----------------
$script:Win = (New-FakeWin (New-ThemeRes 'Neon'))
$res = $script:Win.Resources
$before = @{}
foreach ($k in @($script:Themes['Neon'].Keys)) { $before[$k] = $res[$k] }
$gradBefore = $res['BrBgGrad']

foreach ($tn in @($allThemes | Where-Object { $_ -ne 'Neon' })) {
    Set-AppTheme $tn
    Assert-Eq $script:ThemeFail 0 ($tn + ': basarisiz renk yok')
    Assert-Eq $script:ThemeName $tn ($tn + ': tema adi')
    Assert-Eq @(Get-ThemeProblems $tn).Count 0 ($tn + ': Get-ThemeProblems bos')
    Assert-Eq $res.IndexerSets 0 ($tn + ': kaynak sozlugune dizinleyiciyle hic yazilmadi')
    Assert-Eq $res.BadTypes.Count 0 ($tn + ': kaynaga Brush olmayan nesne yazilmadi')
    Assert-Eq $res.AddTypes.Count 0 ($tn + ': yeni nesne eklenmedi (yerinde guncelleme)')
    foreach ($k in @($script:Themes[$tn].Keys)) {
        Assert-Eq (Get-Hex $res $k) (Norm ([string]$script:Themes[$tn][$k])) ($tn + ' renk: ' + $k)
        Assert-True ([object]::ReferenceEquals($res[$k], $before[$k])) ($tn + ': ayni firca nesnesi korundu: ' + $k)
    }
    Assert-True ([object]::ReferenceEquals($res['BrBgGrad'], $gradBefore)) ($tn + ': gecis fircasi ayni nesne')
    for ($i = 0; $i -lt 3; $i++) { Assert-Eq $res['BrBgGrad'].GradientStops[$i].Color.ToString() (Norm ([string]$script:ThemeGrads[$tn][$i])) ($tn + ' gecis rengi ' + $i) }
}
Set-AppTheme 'Yuksek'
Assert-Eq (Get-Hex $res 'BrBg') (Norm '#000000') 'Yuksek: zemin siyah'
Assert-Eq (Get-Hex $res 'BrText') (Norm '#FFFFFF') 'Yuksek: yazi beyaz'
Set-AppTheme 'Acik'
Assert-Eq (Get-Hex $res 'BrCard') (Norm ([string]$script:Themes['Acik']['BrCard'])) 'Acik: kart rengi uygulandi'

Set-AppTheme 'Neon'
Assert-Eq $script:ThemeFail 0 'Neon (geri donus): basarisiz renk yok'
foreach ($k in @($script:Themes['Neon'].Keys)) { Assert-Eq (Get-Hex $res $k) (Norm ([string]$script:Themes['Neon'][$k])) ('Neon geri donus: ' + $k) }
for ($i = 0; $i -lt 3; $i++) { Assert-Eq $res['BrBgGrad'].GradientStops[$i].Color.ToString() (Norm ([string]$script:ThemeGrads['Neon'][$i])) ('Neon gecis rengi ' + $i) }

# tekrar tekrar gecis
foreach ($n in 1..12) { foreach ($t in @('Koyu', 'Acik', 'Yuksek', 'Hacker', 'Cam', 'Holo', 'Akis', 'Uzay', 'Neon')) { Set-AppTheme $t } }
Assert-Eq $script:ThemeFail 0 '108 art arda gecisten sonra hata yok'
Assert-Eq $res.IndexerSets 0 '108 gecis sonrasi dizinleyici hic kullanilmadi'
Assert-Eq $res.BadTypes.Count 0 '108 gecis sonrasi gecersiz tur yok'

# bilinmeyen tema adi -> Neon
Set-AppTheme 'YokBoyleTema'
Assert-Eq $script:ThemeName 'Neon' 'bilinmeyen tema adi Neon olur'
Assert-Eq $script:ThemeFail 0 'bilinmeyen tema adi: hata yok'
Set-AppTheme 'Sade'
Assert-Eq $script:ThemeName 'Neon' 'eski Sade adi dogrudan uygulanmaz (Initialize-Appearance Koyu a tasir)'

# ---------------- 3) yedek yol: dondurulmus ya da eksik firca ----------------
$script:Win = (New-FakeWin (New-ThemeRes 'Neon'))
$res = $script:Win.Resources
$res['BrCard'].Freeze()
$res.Remove('BrGold')
$res.IndexerSets = 0; $res.BadTypes.Clear(); $res.AddTypes.Clear()
$frozenOld = $res['BrCard']
Set-AppTheme 'Koyu'
Assert-Eq $script:ThemeFail 0 'dondurulmus + eksik firca: yine de tam oturdu'
Assert-Eq @(Get-ThemeProblems 'Koyu').Count 0 'dondurulmus + eksik firca: sorun yok'
Assert-Eq $res.IndexerSets 0 'yedek yol da dizinleyici kullanmaz'
Assert-Eq $res.BadTypes.Count 0 'yedek yolda Brush olmayan nesne yazilmadi'
Assert-Eq $res.AddTypes.Count 2 'yedek yol: iki firca yeniden eklendi'
Assert-True (@($res.AddTypes | Where-Object { $_ -ne 'System.Windows.Media.SolidColorBrush' }).Count -eq 0) 'eklenen nesneler ham SolidColorBrush'
Assert-True (-not [object]::ReferenceEquals($res['BrCard'], $frozenOld)) 'dondurulmus firca yenisiyle degisti'
Assert-Eq (Get-Hex $res 'BrGold') (Norm ([string]$script:Themes['Koyu']['BrGold'])) 'eksik firca eklendi ve renkli'

# ---------------- 4) basarisizlik bildirimi ----------------
$script:Win = (New-FakeWin (New-ThemeRes 'Neon'))
$res = $script:Win.Resources
$res['BrGold'].Freeze()
$res.FailAddKey = 'BrGold'
$script:Logs.Clear()
Set-AppTheme 'Koyu'
Assert-True ($script:ThemeFail -gt 0) 'eklenemeyen firca: ThemeFail > 0'
Assert-True (@($script:Logs | Where-Object { $_ -match '^WARN .*BrGold' }).Count -ge 1) 'eklenemeyen firca uyari olarak yazildi'
Assert-True (@(Get-ThemeProblems 'Koyu') -contains 'BrGold') 'Get-ThemeProblems sorunlu anahtari bildirir'

# ---------------- 5) Initialize-Appearance: kayitli tema, eski Sade tema ve sorunlu tema ----------------
# ConvertTo-ThemeKey
Assert-Eq (ConvertTo-ThemeKey 'Sade') 'Koyu' 'eski Sade tema Koyu ya tasinir'
Assert-Eq (ConvertTo-ThemeKey 'Hacker') 'Hacker' 'Hacker temasi korunur'
Assert-Eq (ConvertTo-ThemeKey 'Acik') 'Acik' 'Acik temasi korunur'
Assert-Eq (ConvertTo-ThemeKey 'Yuksek') 'Yuksek' 'Yuksek temasi korunur'
Assert-Eq (ConvertTo-ThemeKey 'koyu') 'Koyu' 'kucuk harfle yazilmis ad kanonik hale gelir'
foreach ($gt in @('Cam', 'Holo', 'Akis', 'Uzay')) { Assert-Eq (ConvertTo-ThemeKey $gt) $gt ($gt + ' temasi korunur'); Assert-Eq (ConvertTo-ThemeKey $gt.ToLower()) $gt ($gt + ': kucuk harfle yazilmis ad kanonik hale gelir') }
Assert-Eq (ConvertTo-ThemeKey 'Gecersiz') 'Acik' 'bilinmeyen ad varsayilan temaya (Acik) doner'
Assert-Eq (ConvertTo-ThemeKey '') 'Acik' 'bos ad varsayilan temaya (Acik) doner'
Assert-Eq (ConvertTo-ThemeKey $null) 'Acik' 'null ad varsayilan temaya (Acik) doner'

# 5a) eski 7.1 ayari: Theme = Sade -> Koyu + animasyonlar kapali, ayar bir kez duzeltilir
$script:Win = (New-FakeWin (New-ThemeRes 'Neon'))
$res = $script:Win.Resources
$script:SavedKeys.Clear(); $script:Logs.Clear()
$script:SafeBoot = $false
$script:Settings = @{ Theme = 'Sade'; ReduceMotion = $false }
Initialize-Appearance
Assert-Eq $script:ThemeName 'Koyu' 'eski Sade ayari: Koyu tema uygulandi'
Assert-Eq $script:ThemeFail 0 'eski Sade ayari: hata yok'
Assert-True (@($script:SavedKeys) -contains 'Theme=Koyu') 'eski Sade ayari: kayit Koyu olarak duzeltildi'
Assert-True (@($script:SavedKeys) -contains 'ReduceMotion=True') 'eski Sade ayari: animasyonlar kapali tutuldu'
Assert-True ($script:ReduceMotion -eq $true) 'eski Sade ayari: animasyonlar kisildi'
Assert-Eq (Get-Hex $res 'BrBg') (Norm ([string]$script:Themes['Koyu']['BrBg'])) 'eski Sade ayari: pencere Koyu renklerinde'
$script:SavedKeys.Clear()
Initialize-Appearance
Assert-Eq $script:SavedKeys.Count 0 'duzeltilmis ayar bir sonraki acilista yeniden yazilmaz'

# 5b) normal temalar: ayar yeniden yazilmaz
foreach ($tn in @($allThemes | Where-Object { $_ -ne 'Neon' })) {
    $script:Win = (New-FakeWin (New-ThemeRes 'Neon'))
    $res = $script:Win.Resources
    $script:SavedKeys.Clear(); $script:Logs.Clear()
    $script:Settings = @{ Theme = $tn; ReduceMotion = $false }
    Initialize-Appearance
    Assert-Eq $script:ThemeName $tn ('Initialize-Appearance: ' + $tn + ' uygulandi')
    Assert-Eq $script:ThemeFail 0 ('Initialize-Appearance ' + $tn + ': hata yok')
    Assert-Eq $script:SavedKeys.Count 0 ($tn + ': basarili temada ayar yeniden yazilmaz')
    Assert-True ($script:ReduceMotion -eq $false) ($tn + ': animasyonlar kisilmaz')
    Assert-Eq (Get-Hex $res 'BrBg') (Norm ([string]$script:Themes[$tn]['BrBg'])) ($tn + ': pencere renkleri tema renkleri')
}
# animasyonlar: Ayarlar'dan, Sade yerlesimden ya da dusuk bellekten kisilir
$script:Settings = @{ Theme = 'Neon'; ReduceMotion = $true }; Update-ReduceMotion
Assert-True ($script:ReduceMotion -eq $true) 'ReduceMotion ayari animasyonlari kisar'
$script:Settings = @{ Theme = 'Neon'; ReduceMotion = $false; Layout = 'Sade' }; Update-ReduceMotion
Assert-True ($script:ReduceMotion -eq $true) 'Sade yerlesim animasyonlari kisar'
$script:Settings = @{ Theme = 'Neon'; ReduceMotion = $false; Layout = 'Hacker' }; Update-ReduceMotion
Assert-True ($script:ReduceMotion -eq $false) 'Hacker yerlesim animasyonlari kismaz'
$sync.Profile.RamGB = 2
Update-ReduceMotion
Assert-True ($script:ReduceMotion -eq $true) '4 GB dan az bellekte animasyonlar kisilir'
$sync.Profile.RamGB = 16

# 5c) sorunlu tema -> Neon a donulur ve kayit duzelir
$script:Win = (New-FakeWin (New-ThemeRes 'Neon'))
$res = $script:Win.Resources
$res['BrGold'].Freeze(); $res.FailAddKey = 'BrGold'
$script:SavedKeys.Clear(); $script:Logs.Clear()
$script:Settings = @{ Theme = 'Yuksek'; ReduceMotion = $false }
Initialize-Appearance
Assert-Eq $script:ThemeName 'Neon' 'sorunlu tema: Neon a donuldu'
Assert-True (@($script:SavedKeys) -contains 'Theme=Neon') 'sorunlu tema: kayitli tema Neon yapildi'
Assert-True (@($script:Logs | Where-Object { $_ -match '^WARN ' }).Count -ge 1) 'sorunlu tema: uyari yazildi'
Assert-Eq (Get-Hex $res 'BrBg') (Norm ([string]$script:Themes['Neon']['BrBg'])) 'sorunlu tema: pencere Neon renklerinde'

# gecersiz kayitli ad varsayilan temaya (Acik) doner (guvenli baslangicta ayarlar zaten Neon'a cekilmistir)
$script:Win = (New-FakeWin (New-ThemeRes 'Neon'))
$script:SafeBoot = $true
$script:Settings = @{ Theme = 'Gecersiz'; ReduceMotion = $false }
Initialize-Appearance
Assert-Eq $script:ThemeName 'Acik' 'gecersiz kayitli tema adi: varsayilan tema (Acik)'
$script:SafeBoot = $false

# ---------------- 5d) koddan uretilen ogeler (gunluk satiri, surec satiri...) tema degisince yeni rengi almali ----------------
# Gercek hata: beyaz temada, tema degismeden once yazilmis gunluk satirlari eski (neon) renkte kaldi. Neden: stillerde kullanilan firca donmus olur;
# Set-BrushColor onu sozlukte yeni nesneyle degistirir, eski nesneyi tutan kod ogeleri guncellenmezdi.
foreach ($mode in @('yerinde', 'donmus')) {
    $script:Win = (New-FakeWin (New-ThemeRes 'Neon'))
    $res = $script:Win.Resources
    $script:BrushCache = @{}
    $ui = @{}
    $keys = @('BrText', 'BrDim', 'BrAccent', 'BrGood', 'BrWarn', 'BrBad', 'BrAccent2', 'BrFaint', 'BrLogGreen', 'BrPanel2')
    if ($mode -eq 'donmus') { foreach ($k in $keys) { $res[$k].Freeze() } }
    # "satirlar": her anahtar icin fircayi tutan ogeler
    $holders = @{}
    foreach ($k in $keys) { $holders[$k] = (New-Object psobject -Property @{ Foreground = (Get-Br $k) }) }
    Assert-Eq @(Get-CodeBrushProblems).Count 0 ($mode + ': baslangicta kod fircalari tema ile uyumlu')
    foreach ($tn in @('Acik', 'Yuksek', 'Hacker', 'Koyu', 'Cam', 'Holo', 'Akis', 'Uzay', 'Neon', 'Acik')) {
        Set-AppTheme $tn
        Assert-Eq $script:ThemeFail 0 ($mode + ' ' + $tn + ': tema tam oturdu')
        Assert-Eq @(Get-CodeBrushProblems).Count 0 ($mode + ' ' + $tn + ': kod firca sorunu yok')
        foreach ($k in $keys) {
            $want = Norm ([string]$script:Themes[$tn][$k])
            Assert-Eq $holders[$k].Foreground.Color.ToString() $want ($mode + ' ' + $tn + ': kodla olusturulan ogenin rengi ' + $k)
            Assert-True ([object]::ReferenceEquals($holders[$k].Foreground, (Get-Br $k))) ($mode + ' ' + $tn + ': ayni ozel firca kullanilir ' + $k)
        }
    }
    if ($mode -eq 'donmus') {
        Assert-True ($res.AddTypes.Count -ge $keys.Count) 'donmus kip: kaynak fircalari yeni nesneyle degistirildi (yedek yol calisti)'
        Assert-True (-not [object]::ReferenceEquals($res['BrText'], $holders['BrText'].Foreground)) 'donmus kip: ogenin fircasi kaynaktakinden bagimsiz ozel kopya'
    } else {
        Assert-Eq $res.AddTypes.Count 0 'yerinde kip: kaynak fircalari degistirilmedi'
    }
}
# eski davranisin olumsuz sinamasi: kaynaktaki firca nesnesini dogrudan tutan oge, donmus firca degisince eski renkte kalir
$script:Win = (New-FakeWin (New-ThemeRes 'Neon'))
$res = $script:Win.Resources
$res['BrLogGreen'].Freeze()
$oldHeld = $res['BrLogGreen']
Set-AppTheme 'Acik'
Assert-True ($oldHeld.Color.ToString() -eq (Norm ([string]$script:Themes['Neon']['BrLogGreen']))) 'eski yontem: kaynak fircasini dogrudan tutan oge eski renkte kalir (sinama hatayi yakalayabiliyor)'
Assert-True ((Get-Hex $res 'BrLogGreen') -eq (Norm ([string]$script:Themes['Acik']['BrLogGreen']))) 'eski yontem: kaynak sozlugu ise yeni renkte'

# ---------------- 6) kaynak kodu: dizinleyiciyle firca yazimi geri gelmesin ----------------
$src = Get-Content -LiteralPath $env:MM_BUILD -Raw
Assert-True ($src -notmatch '\$script:Win\.Resources\[\[string\]\$k\]\s*=') 'tema kodunda kaynak sozlugune dizinleyiciyle atama yok'
Assert-True ($src -notmatch '\$res\[\[string\]\$k\]\s*=\s*New-Object') 'tema kodunda dizinleyici + New-Object yok'
$ast = [System.Management.Automation.Language.Parser]::ParseFile($env:MM_BUILD, [ref]$null, [ref]$null)
$bad = New-Object System.Collections.ArrayList
foreach ($fnName in @('Set-AppTheme', 'Set-BrushColor', 'Get-ThemeProblems')) {
    $fn = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $fnName }, $true)) | Select-Object -Last 1
    Assert-True ($null -ne $fn) ($fnName + ' bulundu')
    foreach ($a in @($fn.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left -is [System.Management.Automation.Language.IndexExpressionAst] }, $true))) {
        [void]$bad.Add($fnName + ' ' + $a.Extent.StartLineNumber.ToString() + ': ' + $a.Extent.Text)
    }
}
Assert-Eq $bad.Count 0 ('tema islevlerinde dizinleyiciyle atama yok ' + ($bad -join ' | '))

# ---------------- Sistem ayarını kullan (p85): Windows'un açık/koyu uygulama ayarı izlenir ----------------
Import-Fn 'Get-SystemThemeKey', 'ConvertTo-ThemeChoice', 'Update-SystemTheme'
$global:AppsLight = 0
function Get-RegValue([string]$Path, [string]$Name, $Default) { if ($Name -eq 'AppsUseLightTheme') { if ($null -eq $global:AppsLight) { return $Default }; return $global:AppsLight }; return $Default }
$script:SafeBoot = $false
Assert-Eq (Get-SystemThemeKey) 'Koyu' 'sistem: Windows koyu kipte Koyu'
$global:AppsLight = 1
Assert-Eq (Get-SystemThemeKey) 'Acik' 'sistem: Windows açık kipte Acik'
$global:AppsLight = $null
Assert-Eq (Get-SystemThemeKey) 'Acik' 'sistem: ayar yoksa Acik'
$global:AppsLight = 0
Assert-Eq (ConvertTo-ThemeKey 'Sistem') 'Koyu' 'sistem: tema anahtarı Windows kipinden çözülür'
Assert-Eq (ConvertTo-ThemeChoice 'Sistem') 'Sistem' 'sistem: liste seçimi Sistem olarak kalır'
Assert-Eq (ConvertTo-ThemeChoice 'koyu') 'Koyu' 'sistem: diğer adlar tema anahtarına çevrilir'
Assert-Eq (ConvertTo-ThemeChoice '') 'Acik' 'sistem: boş ad varsayılan temaya döner'
$script:Win = (New-FakeWin (New-ThemeRes 'Neon'))
$script:SavedKeys.Clear(); $script:Logs.Clear()
$script:Settings = @{ Theme = 'Sistem'; ReduceMotion = $false }
Initialize-Appearance
Assert-Eq $script:ThemeName 'Koyu' 'sistem: açılışta Windows koyu kipte Koyu uygulanır'
Assert-Eq ([string]$script:Settings.Theme) 'Sistem' 'sistem: ayar Sistem olarak kalır'
Assert-Eq @($script:SavedKeys).Count 0 'sistem: açılışta ayar yeniden yazılmaz'
Assert-True (-not (Update-SystemTheme)) 'sistem: kip değişmediyse tema yeniden uygulanmaz'
$global:AppsLight = 1
Assert-True (Update-SystemTheme) 'sistem: Windows açık kipe geçince tema değişir'
Assert-Eq $script:ThemeName 'Acik' 'sistem: yeni etkin tema Acik'
Assert-Eq $script:ThemeFail 0 'sistem: kip değişiminde renk hatası yok'
Assert-True (-not (Update-SystemTheme)) 'sistem: ikinci denetimde yeniden uygulanmaz'
$script:Settings = @{ Theme = 'Neon' }
$global:AppsLight = 0
Assert-True (-not (Update-SystemTheme)) 'sistem: başka tema seçiliyken Windows kipi izlenmez'
Assert-Eq $script:ThemeName 'Acik' 'sistem: başka tema seçiliyken etkin tema değişmez'
Remove-Item function:Get-RegValue -ErrorAction SilentlyContinue

Show-Result
