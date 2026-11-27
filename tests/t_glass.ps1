# 8.0.0: Saydamlik (Mica / Akrilik + yuzey opakligi): saf plan ve renk hesaplari, Windows cagrilarinin tampon duzeni,
# uygulama akisi (sistem cagrilari taklit edilerek), Ayarlar sayfasi baglantilari ve ana betige giren kancalar.
# Gercek DWM etkisi Linux'ta denenemez; o kisim duman testinde (saydamlik x tema) gercek pencerede sinanir.
. "$PSScriptRoot/lib.ps1"

Import-Fn 'ConvertTo-GlassKey', 'ConvertTo-GlassOpacity', 'Get-GlassPlan', 'Get-GlassAlphaFor', 'Get-GlassHex', 'Test-HexDark', 'Get-AccentColor'
Import-Fn 'Format-Percent', 'Convert-LangPercent'
$script:LangPctStyle = 0
Import-Fn 'Get-GlassThemeDark', 'Get-PresetGlass', 'Get-GlassBlockWhy', 'Initialize-GlassState', 'Disable-GlassState'
Import-Var 'GlassInfo', 'GlassSteps', 'GlassDefaultOp', 'GlassShellKeys', 'GlassSurfaceKeys', 'Themes', 'ThemeGrads', 'Page_settings'

$src = [System.IO.File]::ReadAllText($script:TestPath)
function Get-FnText([string]$Name) {
    $f = @(Get-AstFunctions | Where-Object { ($_.Name -replace '^global:', '') -eq $Name }) | Select-Object -Last 1
    if ($null -eq $f) { return '' }
    return $f.Extent.Text
}

# ======================= 1) tablolar =======================
$gk = @($script:GlassInfo.Keys)
Assert-Eq ($gk -join ',') 'Yok,Mica,Akrilik' 'efekt anahtarlari ve sirasi (efektsiz duz seffaflik yok: gercek pencerede denendi, Windows 11 de calismiyor)'
foreach ($k in $gk) { Assert-True ([string]$script:GlassInfo[$k].T -ne '' -and [string]$script:GlassInfo[$k].D -ne '') "$k adi ve aciklamasi var" }
Assert-Eq (@($script:GlassSteps) -join ',') '100,90,80,70,60,50' 'opaklik adimlari'
foreach ($k in @('Mica', 'Akrilik')) {
    $d = [int]$script:GlassDefaultOp[$k]
    Assert-True (@($script:GlassSteps) -contains $d -and $d -lt 100) "$k ilk acilista gorunur bir opaklik onerir ($d)"
}
Assert-True (-not $script:GlassDefaultOp.ContainsKey('Yok')) 'kapali efektin onerilen opakligi yok'
Assert-True (@($script:GlassShellKeys | Where-Object { @($script:GlassSurfaceKeys) -contains $_ }).Count -eq 0) 'kabuk ve yuzey fircalari karismaz'
foreach ($k in @($script:GlassShellKeys) + @($script:GlassSurfaceKeys)) {
    foreach ($tn in @($script:Themes.Keys)) { Assert-True ($script:Themes[$tn].Contains($k)) "tema $tn icinde $k var" }
}
foreach ($opaque in @('BrPanel2', 'BrOverlay', 'BrTipBg', 'BrText', 'BrAccent', 'BrLine')) {
    Assert-True (@($script:GlassShellKeys) -notcontains $opaque -and @($script:GlassSurfaceKeys) -notcontains $opaque) "$opaque saydamlastirilmaz"
}

# ======================= 2) anahtar ve opaklik =======================
Assert-Eq (ConvertTo-GlassKey 'Mica') 'Mica' 'anahtar: gecerli korunur'
Assert-Eq (ConvertTo-GlassKey 'mica') 'Mica' 'anahtar: harf buyuklugu onemsiz'
Assert-Eq (ConvertTo-GlassKey 'Seffaf') 'Yok' 'anahtar: kaldirilan Seffaf (eski ayar dosyasi) Yok olur'
Assert-Eq (ConvertTo-GlassKey 'bilinmeyen') 'Yok' 'anahtar: bilinmeyen Yok olur'
Assert-Eq (ConvertTo-GlassKey $null) 'Yok' 'anahtar: null Yok olur'
Assert-Eq (ConvertTo-GlassKey '') 'Yok' 'anahtar: bos Yok olur'
foreach ($s in @(100, 90, 80, 70, 60, 50)) { Assert-Eq (ConvertTo-GlassOpacity $s) $s "opaklik: adim $s korunur" }
Assert-Eq (ConvertTo-GlassOpacity '70') 70 'opaklik: metin sayi'
Assert-Eq (ConvertTo-GlassOpacity 85) 90 'opaklik: esitlikte ustteki adim'
Assert-Eq (ConvertTo-GlassOpacity 82) 80 'opaklik: en yakin adim'
Assert-Eq (ConvertTo-GlassOpacity 49) 50 'opaklik: alt sinir'
Assert-Eq (ConvertTo-GlassOpacity 10) 50 'opaklik: cok dusuk en dusuk adima'
Assert-Eq (ConvertTo-GlassOpacity 1000) 100 'opaklik: cok yuksek %100'
Assert-Eq (ConvertTo-GlassOpacity 0) 100 'opaklik: sifir %100'
Assert-Eq (ConvertTo-GlassOpacity -5) 100 'opaklik: eksi %100'
Assert-Eq (ConvertTo-GlassOpacity 'abc') 100 'opaklik: bozuk metin %100'
Assert-Eq (ConvertTo-GlassOpacity $null) 100 'opaklik: null %100'
Assert-Eq (ConvertTo-GlassOpacity '') 100 'opaklik: bos %100'

# ======================= 3) plan =======================
$p = Get-GlassPlan 'Yok' 26300 ''
Assert-Eq "$($p.Mode)|$($p.Api)" 'Yok|' 'plan: kapali'
foreach ($b in @(10240, 17134, 22000, 26300)) { Assert-Eq (Get-GlassPlan 'Yok' $b '').Mode 'Yok' "plan: kapali her surumde ($b)" }
foreach ($k in @('Mica', 'Akrilik')) {
    $p = Get-GlassPlan $k 26300 'Guvenli baslangic'
    Assert-Eq $p.Mode 'Yok' "plan: engel varsa $k uygulanmaz"
    Assert-Eq $p.Note 'Guvenli baslangic' "plan: engel nedeni notta ($k)"
    $p = Get-GlassPlan $k 17133 ''
    Assert-Eq $p.Mode 'Yok' "plan: eski surumde $k uygulanmaz"
    Assert-True ([string]$p.Note -ne '') "plan: eski surumde neden yazilir ($k)"
}
$p = Get-GlassPlan 'bilinmeyen' 26300 ''
Assert-Eq $p.Mode 'Yok' 'plan: bilinmeyen istek kapali'
$tbl = @(
    @('Mica', 17134, 'Akrilik', 'Accent', $true), @('Mica', 19045, 'Akrilik', 'Accent', $true), @('Mica', 21999, 'Akrilik', 'Accent', $true),
    @('Mica', 22000, 'Mica', 'MicaOld', $false), @('Mica', 22620, 'Mica', 'MicaOld', $false),
    @('Mica', 22621, 'Mica', 'Backdrop', $false), @('Mica', 26300, 'Mica', 'Backdrop', $false),
    @('Akrilik', 17134, 'Akrilik', 'Accent', $false), @('Akrilik', 19045, 'Akrilik', 'Accent', $false), @('Akrilik', 22000, 'Akrilik', 'Accent', $false),
    @('Akrilik', 22621, 'Akrilik', 'Backdrop', $false), @('Akrilik', 26300, 'Akrilik', 'Backdrop', $false),
    @('Seffaf', 17134, 'Yok', '', $false), @('Seffaf', 26300, 'Yok', '', $false)
)
foreach ($r in $tbl) {
    $p = Get-GlassPlan ([string]$r[0]) ([int]$r[1]) ''
    Assert-Eq "$($p.Mode)|$($p.Api)" "$($r[2])|$($r[3])" "plan: $($r[0]) surum $($r[1])"
    Assert-Eq ([string]$p.Note -ne '') ([bool]$r[4]) "plan: not $($r[0]) surum $($r[1])"
}

# ======================= 4) renk =======================
$script:GlassAlpha = 1.0
Assert-Eq (Get-GlassHex 'BrBg' '#080B16') '#080B16' 'renk: opakken aynen'
Assert-Eq (Get-GlassHex 'BrPanel' '#0E1427') '#0E1427' 'renk: opakken aynen (yuzey)'
$script:GlassAlpha = 0.8
Assert-Eq (Get-GlassHex 'BrBg' '#080B16') '#CC080B16' 'renk: kabuk %80'
Assert-Eq (Get-GlassHex 'BrTitle' '#0A0F1F') '#CC0A0F1F' 'renk: baslik %80'
Assert-Eq (Get-GlassHex 'BrRail' '#0A0F1E') '#CC0A0F1E' 'renk: menu %80'
Assert-Eq (Get-GlassHex 'BrPanel2' '#131B35') '#131B35' 'renk: acilir menu fircasi opak kalir'
Assert-Eq (Get-GlassHex 'BrText' '#E2E8F8') '#E2E8F8' 'renk: yazi opak kalir'
Assert-Eq (Get-GlassHex 'BrOverlay' '#D0050810') '#D0050810' 'renk: kendi alfasi olan fircaya dokunulmaz'
Assert-Eq (Get-GlassHex 'BrBg' '#0a0b16') '#CC0A0B16' 'renk: kucuk harf buyuk harfe cevrilir'
Assert-Eq (Get-GlassHex 'BrBg' '#80102030') '#66102030' 'renk: var olan alfa ile carpilir'
Assert-Eq (Get-GlassHex 'BrBg' 'kirmizi') 'kirmizi' 'renk: bozuk metin aynen'
Assert-Eq (Get-GlassHex 'BrBg' '#12345') '#12345' 'renk: kisa metin aynen'
$script:GlassAlpha = 0.6
Assert-Eq (Get-GlassHex 'BrBg' '#FFFFFF') '#99FFFFFF' 'renk: kabuk %60'
Assert-Eq (Get-GlassHex 'BrCard' '#141C38') '#CC141C38' 'renk: kart yari yolda (%60 -> %80)'
Assert-Eq (Get-GlassHex 'BrPanel' '#0E1427') '#CC0E1427' 'renk: panel yari yolda (%60 -> %80)'
foreach ($a in @(1.0, 0.9, 0.8, 0.7, 0.6, 0.5)) {
    $script:GlassAlpha = $a
    foreach ($tn in @($script:Themes.Keys)) {
        foreach ($k in @($script:Themes[$tn].Keys)) {
            $h = [string]$script:Themes[$tn][$k]
            $g = Get-GlassHex ([string]$k) $h
            $isGlass = (@($script:GlassShellKeys) -contains $k) -or (@($script:GlassSurfaceKeys) -contains $k)
            if (-not $isGlass -or $a -ge 0.999) {
                Assert-Eq $g $h "renk: $tn/$k alfa $a dokunulmaz"
            } else {
                $rgb = $h.TrimStart('#'); if ($rgb.Length -eq 8) { $rgb = $rgb.Substring(2) }
                Assert-True ($g -cmatch '^#[0-9A-F]{8}$') "renk: $tn/$k alfa $a bicimi"
                if ($g -cmatch '^#[0-9A-F]{8}$') {
                    Assert-Eq $g.Substring(3) $rgb.ToUpperInvariant() "renk: $tn/$k alfa $a rengi degismez"
                    $av = [Convert]::ToInt32($g.Substring(1, 2), 16)
                    # temanin kendi alfasi (cam temalarinda var) saydamlik alfasiyla carpilir
                    $baseA = 1.0
                    if ($h.TrimStart('#').Length -eq 8) { $baseA = [Convert]::ToInt32($h.TrimStart('#').Substring(0, 2), 16) / 255.0 }
                    $wantA = [int][math]::Round(255.0 * $baseA * (Get-GlassAlphaFor ([string]$k) $a))
                    Assert-True ([math]::Abs($av - $wantA) -le 1) "renk: $tn/$k alfa $a carpim ($av beklenen $wantA)"
                    Assert-True ($av -ge 40 -and $av -le 255) "renk: $tn/$k alfa $a okunabilir alt sinir ustunde ($av)"
                }
            }
        }
    }
}
# kabuk, ayni alfada karttan daha saydamdir
foreach ($a in @(0.9, 0.8, 0.7, 0.6, 0.5)) {
    Assert-True ((Get-GlassAlphaFor 'BrBg' $a) -lt (Get-GlassAlphaFor 'BrCard' $a)) "kabuk karttan saydam ($a)"
    Assert-True ((Get-GlassAlphaFor 'BrCard' $a) -lt 1.0) "kart yine de yari saydam ($a)"
    Assert-Eq (Get-GlassAlphaFor 'BrPanel2' $a) 1 "acilir fircalar opak ($a)"
}
Assert-Eq (Get-GlassAlphaFor 'BrBg' 1.0) 1 'alfa 1 iken kabuk opak'
$script:GlassAlpha = 1.0

Assert-True (Test-HexDark '#080B16') 'koyu: neon zemin'
Assert-True (-not (Test-HexDark '#EEF1F7')) 'acik: acik zemin'
Assert-True (Test-HexDark '#000000') 'koyu: siyah'
Assert-True (-not (Test-HexDark '#FFFFFF')) 'acik: beyaz'
Assert-True (-not (Test-HexDark '#80FFFFFF')) 'acik: alfali beyaz'
Assert-True (Test-HexDark 'bozuk') 'bozuk renk koyu sayilir'
Assert-True (Get-GlassThemeDark 'Neon') 'tema koyu: Neon'
Assert-True (Get-GlassThemeDark 'Koyu') 'tema koyu: Koyu'
Assert-True (-not (Get-GlassThemeDark 'Acik')) 'tema acik: Acik'
Assert-True (Get-GlassThemeDark 'Hacker') 'tema koyu: Hacker'
Assert-True (Get-GlassThemeDark 'yok-boyle-tema') 'bilinmeyen tema koyu sayilir'

$exp = [uint32](96 * 16777216 + 48 * 65536 + 32 * 256 + 16)
Assert-Eq (Get-AccentColor '#102030' 96) $exp 'vurgu rengi: ABGR sirasi'
Assert-Eq (Get-AccentColor '#102030' 0) ([uint32](48 * 65536 + 32 * 256 + 16)) 'vurgu rengi: alfa 0'
Assert-Eq (Get-AccentColor '#102030' 300) ([uint32](255 * 16777216 + 48 * 65536 + 32 * 256 + 16)) 'vurgu rengi: alfa en cok 255'
Assert-Eq (Get-AccentColor '#102030' -5) ([uint32](48 * 65536 + 32 * 256 + 16)) 'vurgu rengi: alfa en az 0'
Assert-Eq (Get-AccentColor '#FF102030' 96) $exp 'vurgu rengi: sekiz haneli rengin alfasi yok sayilir'
Assert-Eq (Get-AccentColor 'bozuk' 64) ([uint32](64 * 16777216)) 'vurgu rengi: bozuk renk siyah'
Assert-True ((Get-AccentColor '#FFFFFF' 255) -is [uint32]) 'vurgu rengi uint32 doner'

# ======================= 5) hazir gorunumler =======================
Assert-Eq "$((Get-PresetGlass 'Atolye').Backdrop)|$((Get-PresetGlass 'Atolye').Opacity)" 'Mica|80' 'hazir gorunum: Atolye Mica'
Assert-Eq "$((Get-PresetGlass 'Sifir').Backdrop)|$((Get-PresetGlass 'Sifir').Opacity)" 'Mica|90' 'hazir gorunum: Sifir Noktasi hafif Mica'
foreach ($k in @('Varsayilan', 'KoyuNeon', 'KompaktKoyu', 'Hacker', 'Morpheus', 'Komuta', 'yok')) {
    $g = Get-PresetGlass $k
    Assert-Eq "$($g.Backdrop)|$($g.Opacity)" 'Yok|100' "hazir gorunum: $k duz renkli"
}
foreach ($k in @('Atolye', 'Sifir', 'Varsayilan')) {
    $g = Get-PresetGlass $k
    Assert-True (@($script:GlassInfo.Keys) -contains [string]$g.Backdrop -and @($script:GlassSteps) -contains [int]$g.Opacity) "hazir gorunum degerleri gecerli ($k)"
}

# ======================= 6) engeller ve plan kurulumu =======================
$script:SafeBoot = $false; $script:SafeMode = $false; $script:ChromeFallback = $false
$sess = $env:SESSIONNAME; $env:SESSIONNAME = 'Console'
Assert-Eq (Get-GlassBlockWhy 'Neon') '' 'engel yok'
$script:SafeBoot = $true
Assert-True ((Get-GlassBlockWhy 'Neon') -like '*ba*lang*') 'engel: guvenli baslangic'
$script:SafeBoot = $false; $script:SafeMode = $true
Assert-True ((Get-GlassBlockWhy 'Neon') -like '*izim kipinde*') 'engel: guvenli cizim kipi'
$script:SafeMode = $false; $script:ChromeFallback = $true
Assert-True ((Get-GlassBlockWhy 'Neon') -like '*er*eve*') 'engel: sistem cercevesi'
$script:ChromeFallback = $false
Assert-True ((Get-GlassBlockWhy 'Yuksek') -like '*kar*tl*') 'engel: yuksek karsitlik temasi'
Assert-Eq (Get-GlassBlockWhy 'Hacker') '' 'engel yok: Hacker teması'
$env:SESSIONNAME = 'RDP-Tcp#3'
Assert-True ((Get-GlassBlockWhy 'Neon') -like '*Uzak*') 'engel: uzak masaustu'
$env:SESSIONNAME = $sess

function global:Get-OsBuildNumber { return [int]$script:FakeBuild }
$script:FakeBuild = 26300
$script:Settings = @{ Backdrop = 'Mica'; WinOpacity = 80 }
Initialize-GlassState 'Neon'
Assert-Eq "$($script:GlassPlan.Mode)|$($script:GlassPlan.Api)" 'Mica|Backdrop' 'kurulum: Mica plani'
Assert-Eq $script:GlassAlpha 0.8 'kurulum: alfa 0.8'
$script:Settings = @{ Backdrop = 'Akrilik'; WinOpacity = 60 }
Initialize-GlassState 'Koyu'
Assert-Eq "$($script:GlassPlan.Mode)|$($script:GlassAlpha)" 'Akrilik|0.6' 'kurulum: Akrilik %60'
$script:Settings = @{ Backdrop = 'Yok'; WinOpacity = 70 }
Initialize-GlassState 'Neon'
Assert-Eq "$($script:GlassPlan.Mode)|$($script:GlassAlpha)" 'Yok|1' 'kurulum: kapaliyken alfa 1'
$script:Settings = @{ Backdrop = 'Mica'; WinOpacity = 70 }
Initialize-GlassState 'Yuksek'
Assert-Eq "$($script:GlassPlan.Mode)|$($script:GlassAlpha)" 'Yok|1' 'kurulum: yuksek karsitlik temasinda kapali'
$script:SafeBoot = $true
Initialize-GlassState 'Neon'
Assert-Eq "$($script:GlassPlan.Mode)|$($script:GlassAlpha)" 'Yok|1' 'kurulum: guvenli baslangicta kapali'
$script:SafeBoot = $false
$script:FakeBuild = 15063
Initialize-GlassState 'Neon'
Assert-Eq "$($script:GlassPlan.Mode)|$($script:GlassAlpha)" 'Yok|1' 'kurulum: eski Windows surumunde kapali'
$script:FakeBuild = 26300
$script:Settings = @{}
Initialize-GlassState 'Neon'
Assert-Eq "$($script:GlassPlan.Mode)|$($script:GlassAlpha)" 'Yok|1' 'kurulum: ayar yoksa kapali'
$script:Settings = @{ Backdrop = 'Mica'; WinOpacity = 'bozuk' }
Initialize-GlassState 'Neon'
Assert-Eq "$($script:GlassPlan.Mode)|$($script:GlassAlpha)" 'Mica|1' 'kurulum: bozuk opaklik %100 (efekt var, yuzeyler opak)'

$script:Settings = @{ Backdrop = 'Mica'; WinOpacity = 70 }
$script:SettingsSaved = $null
function global:Set-SettingsKeys([hashtable]$Keys) { $script:SettingsSaved = $Keys; foreach ($k in $Keys.Keys) { $script:Settings[$k] = $Keys[$k] } }
Initialize-GlassState 'Neon'
Disable-GlassState
Assert-Eq "$($script:GlassPlan.Mode)|$($script:GlassAlpha)" 'Yok|1' 'kapatma: bellekteki durum'
Assert-Eq "$($script:Settings.Backdrop)|$($script:Settings.WinOpacity)" 'Yok|100' 'kapatma: ayar yazilir'

# ======================= 7) Windows cagrilarinin tampon duzeni (sistem cagrisi taklit edilir) =======================
Import-Fn 'Set-DwmInt', 'Set-DwmMargins', 'Set-WindowAccent', 'Invoke-GlassNative', 'Get-GlassApi'
$script:Native = New-Object System.Collections.ArrayList
function global:Invoke-GlassNative([string]$Name, [object[]]$CallArgs) {
    $rec = @{ Name = $Name; Hwnd = $CallArgs[0].ToInt64() }
    if ($Name -eq 'DwmSetWindowAttribute') {
        $rec.Attr = [int]$CallArgs[1]; $rec.Size = [int]$CallArgs[3]
        $rec.Value = [System.Runtime.InteropServices.Marshal]::ReadInt32([IntPtr]$CallArgs[2], 0)
    } elseif ($Name -eq 'DwmExtendFrameIntoClientArea') {
        $m = @(); foreach ($i in 0..3) { $m += [System.Runtime.InteropServices.Marshal]::ReadInt32([IntPtr]$CallArgs[1], 4 * $i) }
        $rec.Margins = ($m -join ',')
    } elseif ($Name -eq 'SetWindowCompositionAttribute') {
        $d = [IntPtr]$CallArgs[1]; $ps = [IntPtr]::Size
        $rec.Attribute = [System.Runtime.InteropServices.Marshal]::ReadInt32($d, 0)
        $acc = [System.Runtime.InteropServices.Marshal]::ReadIntPtr($d, $ps)
        $rec.Size = [System.Runtime.InteropServices.Marshal]::ReadInt32($d, 2 * $ps)
        $rec.State = [System.Runtime.InteropServices.Marshal]::ReadInt32($acc, 0)
        $rec.Flags = [System.Runtime.InteropServices.Marshal]::ReadInt32($acc, 4)
        $rec.Color = [uint32][BitConverter]::ToUInt32([BitConverter]::GetBytes([System.Runtime.InteropServices.Marshal]::ReadInt32($acc, 8)), 0)
        $rec.Anim = [System.Runtime.InteropServices.Marshal]::ReadInt32($acc, 12)
    }
    [void]$script:Native.Add($rec)
    return 0
}
$hw = [IntPtr]4321
$r = Set-DwmInt $hw 38 2
$n = $script:Native[0]
Assert-Eq "$($n.Name)|$($n.Hwnd)|$($n.Attr)|$($n.Value)|$($n.Size)" 'DwmSetWindowAttribute|4321|38|2|4' 'DWM niteligi: tanitici, nitelik, deger, boyut'
$r = Set-DwmInt $hw 20 1
Assert-Eq "$($script:Native[1].Attr)|$($script:Native[1].Value)" '20|1' 'DWM niteligi: koyu kip'
$r = Set-DwmMargins $hw (-1)
Assert-Eq "$($script:Native[2].Name)|$($script:Native[2].Margins)" 'DwmExtendFrameIntoClientArea|-1,-1,-1,-1' 'DWM kenar bosluklari: dort kenar -1'
$r = Set-DwmMargins $hw 0
Assert-Eq $script:Native[3].Margins '0,0,0,0' 'DWM kenar bosluklari: sifir'
$col = Get-AccentColor '#102030' 96
$r = Set-WindowAccent $hw 4 2 $col
$n = $script:Native[4]
Assert-Eq "$($n.Name)|$($n.Attribute)|$($n.Size)" 'SetWindowCompositionAttribute|19|16' 'vurgu tamponu: nitelik 19, boyut 16'
Assert-Eq "$($n.State)|$($n.Flags)|$($n.Anim)" '4|2|0' 'vurgu tamponu: durum, bayrak, animasyon'
Assert-Eq $n.Color $col 'vurgu tamponu: renk aynen'
$r = Set-WindowAccent $hw 0 0 ([uint32]0)
Assert-Eq "$($script:Native[5].State)|$($script:Native[5].Color)" '0|0' 'vurgu tamponu: kapatma (durum 0)'
Assert-Eq $script:Native.Count 6 'her islev tek sistem cagrisi yapar'

# gercek tanimlama yolu: dinamik tur ve uc sistem cagrisi (cagrilmaz)
Import-Fn 'Invoke-GlassNative'
function global:Write-WhLog([string]$Message, [string]$Level = 'INFO') { }
$script:GlassApi = $null
$api = Get-GlassApi
Assert-True ($null -ne $api) 'sistem cagrilari turu tanimlandi'
if ($null -ne $api) {
    $want = @{ DwmSetWindowAttribute = 4; DwmExtendFrameIntoClientArea = 2; SetWindowCompositionAttribute = 2 }
    foreach ($k in $want.Keys) {
        $mi = $api.GetMethod($k)
        Assert-True ($null -ne $mi) "$k tanimli"
        if ($null -ne $mi) {
            Assert-Eq @($mi.GetParameters()).Count $want[$k] "$k parametre sayisi"
            Assert-Eq $mi.ReturnType.Name 'Int32' "$k donus turu"
            Assert-True ($mi.IsStatic) "$k static"
        }
    }
    $ptypes = (@($api.GetMethod('DwmSetWindowAttribute').GetParameters() | ForEach-Object { $_.ParameterType.Name })) -join ','
    Assert-Eq $ptypes 'IntPtr,Int32,IntPtr,Int32' 'DwmSetWindowAttribute parametre turleri'
    Assert-True ((Get-GlassApi) -eq $api) 'tur bir kez tanimlanir (onbellek)'
    Assert-Eq (Invoke-GlassNative 'OlmayanYontem' @([IntPtr]::Zero)) -1 'olmayan yontem -1 doner'
    $threw = $false
    try { [void](Invoke-GlassNative 'DwmSetWindowAttribute' @([IntPtr]::Zero, 20, [IntPtr]::Zero, 4)) } catch { $threw = $true }
    Assert-True $threw 'kutuphane yoksa (Linux) yonetilen hata firlatilir, uygulama cokmez'
}

# ======================= 8) uygulama akisi (sistem cagrilari taklit edilir) =======================
Import-Fn 'Clear-GlassWindow', 'Update-GlassWindow', 'Update-GlassTheme', 'Update-Glass', 'Select-Glass', 'Update-StGlassText', 'Load-StGlass', 'Save-StGlass', 'Initialize-StGlassChoices'
Import-Fn 'New-Choice', 'Set-ComboChoices', 'Select-ComboKey', 'Get-ComboKey'
$script:CallLog = New-Object System.Collections.ArrayList
$script:TraceLog = New-Object System.Collections.ArrayList
$script:CrashLog = New-Object System.Collections.ArrayList
$script:FakeHwnd = 4321; $script:DwmFail = -1; $script:ChromeThrow = $false; $script:Toasts = New-Object System.Collections.ArrayList
function global:Get-GlassHwnd { return [IntPtr]$script:FakeHwnd }
function global:Set-GlassSurface([bool]$On) { [void]$script:CallLog.Add('surface:' + $On) }
function global:Set-GlassChrome([bool]$On) { if ($script:ChromeThrow) { throw 'cerceve hatasi' }; [void]$script:CallLog.Add('chrome:' + $On) }
function global:Set-DwmInt([IntPtr]$Hwnd, [int]$Attr, [int]$Value) { [void]$script:CallLog.Add('dwm:' + $Attr + '=' + $Value); if ($script:DwmFail -eq $Attr) { return -2147024809 }; return 0 }
function global:Set-DwmMargins([IntPtr]$Hwnd, [int]$M) { [void]$script:CallLog.Add('margins:' + $M); return 0 }
function global:Set-WindowAccent([IntPtr]$Hwnd, [int]$State, [int]$Flags, [uint32]$Color) { [void]$script:CallLog.Add('accent:' + $State + ':' + $Color); return 1 }
function global:Add-Trace([string]$Text) { [void]$script:TraceLog.Add($Text) }
function global:Write-CrashLog([string]$Text) { [void]$script:CrashLog.Add($Text) }
function global:Show-Toast([string]$Text, [string]$Kind = 'info') { [void]$script:Toasts.Add($Kind + ':' + $Text) }
function Take-Log { $x = ($script:CallLog -join ' '); $script:CallLog.Clear(); return $x }
function Set-Plan([string]$Backdrop, [int]$Build, [string]$Theme) {
    $script:Settings = @{ Backdrop = $Backdrop; WinOpacity = 80 }
    $script:FakeBuild = $Build
    $script:ThemeName = $Theme
    Initialize-GlassState $Theme
}
$script:GlassApplied = $null
$mid = ''
try { $mid = [string]@($script:ThemeGrads['Neon'])[1] } catch { $mid = '' }
if ($mid -eq '') { $mid = [string]$script:Themes['Neon'].BrBg }

Set-Plan 'Mica' 26300 'Neon'
Update-GlassWindow
Assert-Eq (Take-Log) 'surface:True chrome:True dwm:20=1 dwm:38=2 margins:-1' 'akis: Mica (Windows 11 22H2+)'
Assert-Eq "$($script:GlassApplied.Api)|$($script:GlassApplied.Mode)|$($script:GlassState.Ok)" 'Backdrop|Mica|True' 'akis: durum kaydi'
Update-GlassWindow
Assert-Eq (Take-Log) '' 'akis: degisiklik yoksa yeniden uygulanmaz'
Update-GlassTheme
Assert-Eq (Take-Log) '' 'akis: tema kancasi degisiklik yoksa sessiz'
$script:ThemeName = 'Acik'
Update-GlassTheme
Assert-Eq (Take-Log) 'dwm:38=1 margins:0 chrome:False surface:False surface:True chrome:True dwm:20=0 dwm:38=2 margins:-1' 'akis: acik temaya gecince once temizlenir, sonra acik malzeme istenir'
$script:ThemeName = 'Neon'
Update-GlassWindow; [void](Take-Log)

Set-Plan 'Akrilik' 26300 'Neon'
Update-GlassWindow
Assert-Eq (Take-Log) 'dwm:38=1 margins:0 chrome:False surface:False surface:True chrome:True dwm:20=1 dwm:38=3 margins:-1' 'akis: Mica -> Akrilik (Windows 11)'

Set-Plan 'Seffaf' 26300 'Neon'
Update-GlassWindow
Assert-Eq (Take-Log) 'dwm:38=1 margins:0 chrome:False surface:False' 'akis: kaldirilan Seffaf istegi efekti kapatir (eski ayar dosyasi)'

Set-Plan 'Akrilik' 19045 'Neon'
Update-GlassWindow
$c96 = Get-AccentColor $mid 96
Assert-Eq (Take-Log) "surface:True chrome:True dwm:20=1 accent:4:$c96 margins:-1" 'akis: Windows 10 Akrilik (durum 4)'

Set-Plan 'Mica' 22000 'Neon'
Update-GlassWindow
Assert-Eq (Take-Log) 'accent:0:0 margins:0 chrome:False surface:False surface:True chrome:True dwm:20=1 dwm:1029=1 margins:-1' 'akis: Windows 11 ilk surum Mica (1029)'
Set-Plan 'Yok' 22000 'Neon'
Update-GlassWindow
Assert-Eq (Take-Log) 'dwm:1029=0 margins:0 chrome:False surface:False' 'akis: kapatinca eski haline doner'
Assert-True ($null -eq $script:GlassApplied) 'akis: kapaliyken uygulanmis kayit yok'
Assert-Eq "$($script:GlassState.Ok)" 'True' 'akis: kapali durum basarili'
Update-GlassWindow
Assert-Eq (Take-Log) '' 'akis: kapaliyken bir sey yapilmaz'
Update-GlassTheme
Assert-Eq (Take-Log) '' 'akis: kapaliyken tema kancasi sessiz'
Set-Plan 'Mica' 26300 'Neon'
Update-GlassTheme
Assert-Eq (Take-Log) 'surface:True chrome:True dwm:20=1 dwm:38=2 margins:-1' 'akis: yuksek karsitliktan donuste tema kancasi efekti geri kurar'
Set-Plan 'Mica' 26300 'Yuksek'
Update-GlassTheme
Assert-Eq (Take-Log) 'dwm:38=1 margins:0 chrome:False surface:False' 'akis: yuksek karsitlik temasi efekti kapatir'
Set-Plan 'Yok' 26300 'Neon'; Update-GlassWindow; [void](Take-Log)

# hata yollari
$script:FakeHwnd = 0
Set-Plan 'Mica' 26300 'Neon'
Update-GlassWindow
Assert-Eq (Take-Log) '' 'akis: pencere tanitici yokken hicbir sey yapilmaz'
$script:FakeHwnd = 4321
$script:GlassFail = 0; $script:DwmFail = 38
Update-GlassWindow
Assert-Eq (Take-Log) 'surface:True chrome:True dwm:20=1 dwm:38=2 dwm:38=1 margins:0 chrome:False surface:False' 'akis: DWM hata kodu dondururse geri alinir'
Assert-Eq "$($script:GlassState.Ok)|$($script:GlassFail)" 'False|1' 'akis: hata durumu ve sayaci'
Assert-True ($null -eq $script:GlassApplied) 'akis: hatadan sonra uygulanmis kayit yok'
Assert-True ([string]$script:GlassState.Detail -like '*0x*') 'akis: hata ayrintisi sayisal kod icerir'
$script:DwmFail = -1; $script:ChromeThrow = $true
Update-GlassWindow
$lg = Take-Log
Assert-Eq "$($script:GlassState.Ok)|$($script:GlassFail)" 'False|2' 'akis: cerceve istisnasi yakalanir'
Assert-True ($script:CrashLog.Count -ge 1) 'akis: istisna cokme gunlugune yazilir'
Assert-Eq $lg 'surface:True dwm:38=1 margins:0 surface:False' 'akis: cerceve istisnasinda kalan temizlik adimlari yine de yapilir'
$script:ChromeThrow = $false
Set-Plan 'Yok' 26300 'Neon'; Update-GlassWindow; [void](Take-Log)

# Update-Glass ve Select-Glass
$script:ThemeApplied = New-Object System.Collections.ArrayList
$script:ThemeFail = 0
function global:Set-AppTheme([string]$Name) { [void]$script:ThemeApplied.Add($Name); Initialize-GlassState $Name; $script:ThemeName = $Name; Update-GlassTheme }
$script:ui = @{}
$script:ui['st_BackdropSel'] = New-FakeCombo
$script:ui['st_OpacitySel'] = New-FakeCombo
$script:ui['st_BdDesc'] = [pscustomobject]@{ Text = '' }
$ui = $script:ui
$script:StLoading = $false
Initialize-StGlassChoices
Assert-Eq $ui.st_BackdropSel.Items.Count $script:GlassInfo.Count 'liste: efekt sayisi kadar secenek'
Assert-Eq ((@($ui.st_BackdropSel.Items) | ForEach-Object { $_['Key'] }) -join ',') (@($script:GlassInfo.Keys) -join ',') 'liste: efekt anahtarlari ve sirasi'
Assert-Eq ((@($ui.st_BackdropSel.Items) | ForEach-Object { $_['Name'] }) -join '|') ((@($script:GlassInfo.Keys) | ForEach-Object { [string]$script:GlassInfo[$_].T }) -join '|') 'liste: efekt adlari'
Assert-Eq ((@($ui.st_OpacitySel.Items) | ForEach-Object { $_['Key'] }) -join ',') (@($script:GlassSteps) -join ',') 'liste: opaklik adimlari'
Assert-Eq ((@($ui.st_OpacitySel.Items) | ForEach-Object { $_['Name'] }) -join ',') ((@($script:GlassSteps) | ForEach-Object { '%' + $_ }) -join ',') 'liste: opaklik adlari yuzdeli'
Initialize-StGlassChoices
Assert-Eq $ui.st_BackdropSel.Items.Count $script:GlassInfo.Count 'liste: yeniden doldurmak ogeleri cogaltmaz'
$script:ThemeName = 'Neon'; $script:FakeBuild = 26300; $script:GlassApplied = $null
$script:Settings = @{ Backdrop = 'Yok'; WinOpacity = 100 }
$ok = Select-Glass 'Mica' 80
Assert-Eq $ok $true 'secim: Mica uygulandi'
Assert-Eq "$($script:Settings.Backdrop)|$($script:Settings.WinOpacity)" 'Mica|80' 'secim: ayar yazildi'
Assert-Eq "$($script:ThemeApplied[$script:ThemeApplied.Count - 1])" 'Neon' 'secim: fircalar tema yeniden uygulanarak boyanir'
Assert-Eq $script:GlassAlpha 0.8 'secim: yuzey alfasi 0.8'
Assert-Eq (Take-Log) 'surface:True chrome:True dwm:20=1 dwm:38=2 margins:-1' 'secim: pencereye uygulandi'
Assert-True ($ui.st_BdDesc.Text -like '*Mica*') 'secim: aciklama metni guncellendi'
$ok = Select-Glass 'Mica' 60
Assert-Eq "$ok|$($script:GlassAlpha)" 'True|0.6' 'secim: yalniz opaklik degisince alfa degisir'
Assert-Eq (Take-Log) '' 'secim: yalniz opaklik degisince pencereye yeniden dokunulmaz'
$ok = Select-Glass 'Yok' 60
Assert-Eq "$ok|$($script:GlassAlpha)" 'True|1' 'secim: kapatma'
Assert-Eq (Take-Log) 'dwm:38=1 margins:0 chrome:False surface:False' 'secim: kapatinca pencere eski haline doner'
Assert-Eq $script:Settings.WinOpacity 60 'secim: kapatinca opaklik hatirlanir'
# basarisiz uygulama: ayar kapatilir, secici Kapali olur, uyari gosterilir
$script:DwmFail = 38; $script:Toasts.Clear()
$ok = Select-Glass 'Akrilik' 70
Assert-Eq $ok $false 'secim: uygulanamazsa $false'
Assert-Eq "$($script:Settings.Backdrop)|$($script:Settings.WinOpacity)" 'Yok|100' 'secim: uygulanamazsa ayar kapatilir'
Assert-Eq (Get-ComboKey $ui.st_BackdropSel) 'Yok' 'secim: uygulanamazsa Kapali secenegi secilir'
Assert-Eq (Get-ComboKey $ui.st_OpacitySel) '100' 'secim: uygulanamazsa opaklik %100 olur'
Assert-True ($script:Toasts.Count -eq 1 -and $script:Toasts[0] -like 'warn:*') 'secim: uygulanamazsa tek uyari'
Assert-Eq $script:GlassAlpha 1 'secim: uygulanamazsa yuzeyler opak'
$script:DwmFail = -1; [void](Take-Log)
# tema boyama hatasi saydamligi kapatir
$script:ThemeFail = 3
$ok = Select-Glass 'Mica' 80
Assert-Eq $ok $false 'secim: tema renkleri oturmazsa saydamlik kapatilir'
$script:ThemeFail = 0; [void](Take-Log)

# Ayarlar sayfasi: Load / Save (acilir listeler)
$script:Settings = @{ Backdrop = 'Akrilik'; WinOpacity = 70 }
Initialize-GlassState 'Neon'
Load-StGlass
Assert-Eq (Get-ComboKey $ui.st_BackdropSel) 'Akrilik' 'yukle: kayitli efekt secili'
Assert-Eq (Get-ComboKey $ui.st_OpacitySel) '70' 'yukle: kayitli opaklik secili'
Assert-True ($ui.st_OpacitySel.IsEnabled -eq $true) 'yukle: efekt varken opaklik listesi acik'
$script:Settings = @{ Backdrop = 'Yok'; WinOpacity = 80 }
Initialize-GlassState 'Neon'
Load-StGlass
Assert-True ($ui.st_OpacitySel.IsEnabled -eq $false) 'yukle: efekt yokken opaklik listesi kapali'
Assert-Eq (Get-ComboKey $ui.st_BackdropSel) 'Yok' 'yukle: Kapali secili'
Assert-Eq (Get-ComboKey $ui.st_OpacitySel) '80' 'yukle: kapaliyken de hatirlanan opaklik gorunur'
$script:Settings = @{ Backdrop = 'Seffaf'; WinOpacity = 'x' }
Initialize-GlassState 'Neon'
Load-StGlass
Assert-Eq "$(Get-ComboKey $ui.st_BackdropSel)|$(Get-ComboKey $ui.st_OpacitySel)" 'Yok|100' 'yukle: eski ya da bozuk ayar kapali ve %100 olarak okunur'
# kullanici Mica'yi secer (opaklik %100 iken ilk acilista onerilen opaklik gelir)
$script:Settings = @{ Backdrop = 'Yok'; WinOpacity = 100 }
Initialize-GlassState 'Neon'
Load-StGlass
[void](Select-ComboKey $ui.st_BackdropSel 'Mica')
Save-StGlass
Assert-Eq "$($script:Settings.Backdrop)|$($script:Settings.WinOpacity)" ("Mica|" + $script:GlassDefaultOp['Mica']) 'kaydet: ilk acilista onerilen opaklik'
Assert-Eq (Get-ComboKey $ui.st_OpacitySel) ([string]$script:GlassDefaultOp['Mica']) 'kaydet: onerilen opaklik listede gorunur'
Assert-True ($ui.st_OpacitySel.IsEnabled -eq $true) 'kaydet: efekt acilinca opaklik listesi acilir'
[void](Select-ComboKey $ui.st_OpacitySel '60')
Save-StGlass
Assert-Eq "$($script:Settings.Backdrop)|$($script:Settings.WinOpacity)" 'Mica|60' 'kaydet: opaklik degisti'
[void](Select-ComboKey $ui.st_BackdropSel 'Yok')
Save-StGlass
Assert-Eq "$($script:Settings.Backdrop)|$($script:Settings.WinOpacity)" 'Yok|60' 'kaydet: kapatinca opaklik hatirlanir'
Assert-True ($ui.st_OpacitySel.IsEnabled -eq $false) 'kaydet: kapatinca opaklik listesi kapanir'
[void](Select-ComboKey $ui.st_BackdropSel 'Akrilik')
Save-StGlass
Assert-Eq "$($script:Settings.Backdrop)|$($script:Settings.WinOpacity)" 'Akrilik|60' 'kaydet: yeniden acilinca hatirlanan opaklik gelir'
$n0 = $script:ThemeApplied.Count
Save-StGlass
Assert-Eq $script:ThemeApplied.Count $n0 'kaydet: degisiklik yoksa hicbir sey uygulanmaz'
# liste bos ya da secimsizken ayar bozulmaz
$ui.st_BackdropSel.SelectedIndex = -1; $ui.st_OpacitySel.SelectedIndex = -1
Save-StGlass
Assert-Eq "$($script:Settings.Backdrop)|$($script:Settings.WinOpacity)" 'Akrilik|60' 'kaydet: secimsiz listeler ayari bozmaz'
Update-StGlassText
Assert-True ($ui.st_BdDesc.Text -like '*Akrilik*' -and $ui.st_BdDesc.Text -like '*%60*') 'aciklama: etkin efekt ve opaklik'
$script:Settings = @{ Backdrop = 'Mica'; WinOpacity = 80 }; $script:FakeBuild = 19045
Initialize-GlassState 'Neon'; Update-StGlassText
Assert-True ($ui.st_BdDesc.Text -like '*Akrilik uygulandi*' -or $ui.st_BdDesc.Text -like '*Akrilik uyguland*') 'aciklama: Mica yoksa Windows 10 notu'
# Ayarlar sayfasi henuz kurulmamissa (ilk gezinti oncesi) aciklama kutusu yoktur: hata uretmeden donmeli
$keep = $script:ui['st_BdDesc']; $script:ui.Remove('st_BdDesc')
$Error.Clear()
Update-StGlassText
Assert-Eq $Error.Count 0 'aciklama: kutu yokken (sayfa kurulmadan) hata uretilmez'
$script:ui['st_BdDesc'] = $keep

# ======================= 9) Ayarlar sayfasi XAML =======================
$xp = $script:Page_settings
Assert-True ($xp -match '<ComboBox[^>]*x:Name="st_BackdropSel"') 'XAML: efekt listesi (st_BackdropSel) acilir liste'
Assert-True ($xp -match '<ComboBox[^>]*x:Name="st_OpacitySel"') 'XAML: opaklik listesi (st_OpacitySel) acilir liste'
Assert-True ($xp.Contains('x:Name="st_BdDesc"')) 'XAML: aciklama metni'
foreach ($old in @('st_Bd_Yok', 'st_Bd_Mica', 'st_Bd_Akrilik', 'st_Op_100', 'st_Op_50')) { Assert-True (-not $xp.Contains('x:Name="' + $old + '"')) "XAML: eski yan yana secenek kalmadi ($old)" }
$pDs = $xp.IndexOf('x:Name="st_DesignSel"'); $pBd = $xp.IndexOf('x:Name="st_BackdropSel"'); $pZm = $xp.IndexOf('x:Name="st_ZoomSel"')
Assert-True ($pDs -gt 0 -and $pBd -gt $pDs -and $pZm -gt $pBd) 'XAML: saydamlik satiri tasarim ile yakinlastirma arasinda'
$names = [regex]::Matches($xp, 'x:Name="([^"]+)"') | ForEach-Object { $_.Groups[1].Value }
$dups = @($names | Group-Object | Where-Object { $_.Count -gt 1 })
Assert-Eq $dups.Count 0 'XAML: tekrar eden ad yok'
$okXml = $true
try { $dummy = [xml]$xp } catch { $okXml = $false }
Assert-True $okXml 'XAML: ayarlar sayfasi bicimli'

# ======================= 10) ana betige giren kancalar =======================
$t = Get-FnText 'Set-AppTheme'
Assert-True ($t.Contains('Get-GlassHex ([string]$k) ([string]$tbl[$k])')) 'Set-AppTheme: fircalar Get-GlassHex ile boyanir'
Assert-True ($t.Contains("Get-GlassHex 'BrBg' ([string]`$cols[`$i])")) 'Set-AppTheme: arka plan gecisi kabuk alfasiyla'
Assert-True ($t.IndexOf('Initialize-GlassState $Name') -gt 0 -and $t.IndexOf('Initialize-GlassState $Name') -lt $t.IndexOf('foreach ($k in @($tbl.Keys))')) 'Set-AppTheme: plan, renkler boyanmadan once kurulur'
Assert-True ($t.IndexOf('Update-GlassTheme') -gt $t.IndexOf('$script:ThemeFail = $fail')) 'Set-AppTheme: efekt tema oturduktan sonra uydurulur'
$t = Get-FnText 'Get-ThemeProblems'
Assert-True ($t.Contains('Get-GlassHex ([string]$k) ([string]$tbl[$k])')) 'Get-ThemeProblems: ayni renk islevini kullanir (dogrulama saydam renklerle tutarli)'
$t = Get-FnText 'Initialize-Appearance'
Assert-True ($t.Contains('Initialize-GlassState $t')) 'Initialize-Appearance: plan kurulur'
Assert-True ($t.Contains("if (`$t -ne 'Neon' -or `$script:GlassAlpha -lt 0.999)")) 'Initialize-Appearance: saydamlik varken Neon da boyanir'
Assert-True ($t.Contains('Disable-GlassState') -and $t.IndexOf('Disable-GlassState') -lt $t.IndexOf("Set-AppTheme 'Neon'")) 'Initialize-Appearance: tema oturmazsa once saydamlik kapatilir'
$t = Get-FnText 'Invoke-GuiMode'
$iA = $t.IndexOf('Initialize-Appearance'); $iD = $t.IndexOf('Initialize-Design'); $iG = $t.IndexOf('Initialize-Glass')
Assert-True ($iA -gt 0 -and $iD -gt $iA -and $iG -gt $iD) 'Invoke-GuiMode: sira gorunum, tasarim, saydamlik'
$t = Get-FnText 'Get-DefaultSettings'
Assert-True ($t -match "Backdrop\s*=\s*'Yok'" -and $t -match 'WinOpacity\s*=\s*100') 'varsayilan ayarlar: saydamlik kapali, opaklik 100'
$t = Get-FnText 'Get-SafeLookKeys'
Assert-True ($t.Contains("Design = 'Klasik'") -and $t.Contains("Backdrop = 'Yok'") -and $t.Contains('WinOpacity = 100') -and $t.Contains("HomeMode = 'Klasik'")) 'Get-SafeLookKeys: tasarim, ana ekran ve saydamlik varsayilana doner'
foreach ($fn in @('Invoke-BootGuard', 'Stop-ErrorStorm', 'Reset-UiSettings')) { Assert-True ((Get-FnText $fn).Contains('Get-SafeLookKeys')) "${fn}: guvenli gorunum anahtarlarini kullanir" }
$t = Get-FnText 'Init-StExtra'
Assert-True ($t.Contains("'st_BackdropSel'") -and $t.Contains("'st_OpacitySel'")) 'Init-StExtra: saydamlik listeleri baglanir'
Assert-True ($t.Contains('Initialize-StGlassChoices')) 'Init-StExtra: saydamlik listeleri doldurulur'
Import-Var 'StLookParts'
Assert-True (@($script:StLookParts) -contains 'Glass') 'Ayarlar parcalarinda saydamlik var (Load-StGlass / Save-StGlass cagrilir)'
Assert-True ((Get-FnText 'Load-StExtra').Contains("'Load-St' + `$p") -and (Get-FnText 'Save-StExtra').Contains("'Save-St' + `$p")) 'Load-StExtra / Save-StExtra parcalari adlariyla cagirir'
Assert-True ((Get-FnText 'Sync-StLookControls').Contains('Load-StGlass')) 'Sync-StLookControls: saydamlik listeleri de yenilenir'
$t = Get-FnText 'Get-LookPreset'
Assert-True ($t.Contains('Get-PresetGlass $Key')) 'Get-LookPreset: hazir gorunum saydamligi da icerir'
$t = Get-FnText 'Apply-LookPreset'
Assert-True ($t.Contains('Select-Glass') -and $t.IndexOf('Select-Design') -lt $t.IndexOf('Select-Glass')) 'Apply-LookPreset: hazir gorunum saydamligi tasarimdan sonra uygular'
Import-Var 'SmokeSafeSelect'
foreach ($nm in @('st_BackdropSel', 'st_OpacitySel')) { Assert-True (@($script:SmokeSafeSelect) -contains $nm) "duman testi guvenli liste: $nm" }

# ======================= 11) Windows cagrilari: kaynak duzeyi denetimler =======================
$api = Get-FnText 'Get-GlassApi'
Assert-True ($api.Contains('Add-Type -Namespace WH -Name GlassWin') -and $api.Contains('-MemberDefinition') -and $api.Contains('[DllImport(')) 'sistem cagrilari tek Add-Type -MemberDefinition ile (uygulamanin diger yerleriyle ayni yontem) tanimlanir'
Assert-True ((-not $api.Contains('DefinePInvokeMethod')) -and (-not $api.Contains('DefineDynamicAssembly')) -and (-not $api.Contains('AssemblyName'))) 'bellekte dinamik derleme kurulmaz'
Assert-True ($api.Contains('DwmSetWindowAttribute') -and $api.Contains('DwmExtendFrameIntoClientArea') -and $api.Contains('SetWindowCompositionAttribute')) 'uc sistem cagrisi tanimli'
Assert-True ($api.Contains('"dwmapi.dll"') -and $api.Contains('"user32.dll"')) 'sistem kutuphaneleri'
Assert-True ($api.Contains("if (`$null -eq ('WH.GlassWin' -as [type]))") -and $api.Contains("`$script:GlassApi = ('WH.GlassWin' -as [type])")) 'tur zaten varsa yeniden derlenmez'
Assert-True ($api.Contains('-ErrorAction Stop')) 'derleme hatasi yakalanir (efekt kapanir)'
$all = ''
foreach ($fn in @('Get-GlassApi', 'Set-DwmInt', 'Set-DwmMargins', 'Set-WindowAccent', 'Set-GlassChrome', 'Set-GlassSurface', 'Clear-GlassWindow', 'Update-GlassWindow')) { $all += (Get-FnText $fn) }
Assert-True (-not $all.Contains('AllowsTransparency')) 'pencere katmanli (AllowsTransparency) yapilmaz: DWM arka plani calissin'
Assert-Eq ([regex]::Matches($all, 'Add-Type')).Count 1 'saydamlik kodunda tek Add-Type var (sistem cagrilari turu)'
$t = Get-FnText 'Update-GlassWindow'
Assert-True ($t.IndexOf("if (`$mode -eq 'Yok')") -gt 0 -and $t.IndexOf("if (`$mode -eq 'Yok')") -lt $t.IndexOf('Set-GlassSurface $true')) 'Update-GlassWindow: kapaliyken sistem cagrisina girmeden doner'
Assert-True ($t.IndexOf('Set-GlassSurface $true') -lt $t.IndexOf('Set-GlassChrome $true') -and $t.IndexOf('Set-GlassChrome $true') -lt $t.IndexOf('Set-DwmInt $hwnd 20')) 'Update-GlassWindow: once zemin, sonra cerceve, sonra efekt'
Assert-True ($t.Contains('try {') -and $t.Contains('catch') -and $t.Contains('Clear-GlassWindow $hwnd')) 'Update-GlassWindow: hata olursa temizler'
$t = Get-FnText 'Set-WindowAccent'
Assert-True ($t.Contains('AllocHGlobal') -and $t.Contains('FreeHGlobal') -and $t.Contains('finally')) 'Set-WindowAccent: bellek serbest birakilir'
Assert-True ($t.Contains('WriteInt32($data, 0, 19)') -and $t.Contains('WriteIntPtr($data, $ps, $acc)') -and $t.Contains('WriteInt32($data, 2 * $ps, 16)')) 'Set-WindowAccent: WINDOWCOMPOSITIONATTRIBDATA duzeni (32/64 bit)'
$t = Get-FnText 'Clear-GlassWindow'
Assert-True ($t.Contains('Set-DwmMargins $Hwnd 0') -and $t.Contains('Set-GlassChrome $false') -and $t.Contains('Set-GlassSurface $false')) 'Clear-GlassWindow: kenar, cerceve ve zemin geri alinir'
$t = Get-FnText 'Set-GlassSurface'
Assert-True ($t.Contains('BackgroundColor') -and $t.Contains('GlassPrevBg') -and $t.Contains("SetResourceReference([System.Windows.Window]::BackgroundProperty, 'BrBg')")) 'Set-GlassSurface: zemin rengi hatirlanir ve kaynak baglantisi geri verilir'
$t = Get-FnText 'Set-GlassChrome'
Assert-True ($t.Contains('GlassFrameThickness') -and $t.Contains('-1.0')) 'Set-GlassChrome: cam cerceve tum alana (-1)'

Show-Result
