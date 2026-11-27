# 8.0.0: Duman testinin yeni ölçümleri: renkli zemin + saydamlık görünürlüğü (piksel ortalaması) ve gerçek fare ile pano sürüklemesi.
# Windows'a özgü çağrılar (fare girdisi, pencere sorgusu, ekran yakalama) burada sahte işlevlerle değiştirilir; sınanan şey karar mantığı,
# kuyruk sırası ve hata/uyarı yollarıdır. Gerçek etki bilgisayarda Duman-Saydam.cmd ve Duman-Tasarim.cmd ile görülür.
. "$PSScriptRoot/lib.ps1"
Import-Fn 'New-SmokeStep', 'New-SmokeQueue', 'Get-SmokeActions', 'Add-SmokeLookParts', 'Add-SmokeBoardEditParts', 'Test-SmokeSysTransparency', 'Test-SmokeGlassVisible', 'Get-SmokeLeftMean', 'Get-SmokeDragPlan', 'Invoke-SmokeDrag',
    'Test-SmokeDragResult', 'Stop-SmokeLook', 'Remove-SmokeBackdrop'
Import-Fn 'Format-Percent', 'Convert-LangPercent'
$script:LangPctStyle = 0
Import-Fn 'Find-BoardTile', 'Resolve-BoardType', 'Get-BoardSpec', 'Test-BoardCollide', 'Get-BoardProblems', 'ConvertTo-BoardInt', 'Get-BoardField'
Import-Var 'BoardPresetInfo', 'BoardCols', 'BoardMaxTiles', 'BoardMaxRows', 'BoardWidgets', 'SmokeSafe', 'SmokeThemes', 'SmokeDesigns', 'SmokeGlassOps', 'SmokeGlassThemeOp', 'SmokeLimitSec', 'SmokeScopes', 'SmokePresets'
Import-Fn 'Test-SmokeHome', 'Test-SmokeOverride', 'Get-SmokeComboPairs', 'Test-SmokeCombos', 'Get-SmokeComboText', 'Test-SmokePreset'
Import-Fn 'New-Choice', 'Set-ComboChoices', 'Select-ComboKey', 'Get-ComboKey', 'Get-MatchingLookPreset', 'Get-LookPreset', 'Get-PresetGlass', 'Get-DesignSpec', 'ConvertTo-DesignKey', 'ConvertTo-HomeKey', 'ConvertTo-DsValue'
Import-Fn 'Test-DesignOverridden', 'Merge-DesignOverrides', 'Get-ActiveDesign', 'Test-BoardHome', 'ConvertTo-ThemeKey', 'ConvertTo-ThemeChoice', 'Get-SystemThemeKey', 'ConvertTo-LayoutKey', 'ConvertTo-ZoomPct', 'Get-NearestZoomStep', 'ConvertTo-GlassKey', 'ConvertTo-GlassOpacity'
Import-Fn 'Initialize-StLookChoices', 'Initialize-StDesignChoices', 'Initialize-StGlassChoices', 'Load-StLook', 'Load-StDesign', 'Load-StGlass', 'Sync-StPresetBox', 'Update-StAppearanceText', 'Update-StDesignText', 'Update-StGlassText', 'Merge-HexOver', 'Get-ThemeSwatch'
Import-Var 'Themes', 'ThemeGrads', 'ThemeInfo', 'LayoutInfo', 'ZoomSteps', 'DsOptions', 'DsRadii', 'HomeInfo', 'DesignInfo', 'LookPresetNames', 'GlassInfo', 'GlassSteps', 'SmokeSafeSelect', 'SmokeSafeCheck', 'SmokeOverrides'

if ($null -eq ('System.Windows.Point' -as [type])) {
    Add-Type -TypeDefinition 'namespace System.Windows { public struct Point { public double X; public double Y; public Point(double x, double y) { X = x; Y = y; } } }'
}

# ---------------- sahte ortam ----------------
$script:Lines = New-Object System.Collections.ArrayList
$script:Errs = New-Object System.Collections.ArrayList
$script:Warns = New-Object System.Collections.ArrayList
function Add-SmokeLine([string]$Text) { [void]$script:Lines.Add($Text) }
function Add-SmokeError([string]$Where, [string]$Msg) { [void]$script:Errs.Add($Where + ': ' + $Msg) }
function Add-SmokeWarn([string]$Text) { [void]$script:Warns.Add($Text) }
$script:Mouse = New-Object System.Collections.ArrayList
$script:MouseOk = $true
function Send-SmokeMouse([string]$What, [int]$X, [int]$Y, [bool]$Move) { [void]$script:Mouse.Add(($What + ':' + [string]$X + ',' + [string]$Y + ':' + [string]$Move)); return $script:MouseOk }
$script:WinHits = @{}
$script:WinDefault = $true
function Test-SmokeWindowAt([int]$X, [int]$Y) {
    $k = [string]$X + ',' + [string]$Y
    if ($script:WinHits.ContainsKey($k)) { return [bool]$script:WinHits[$k] }
    return $script:WinDefault
}
$script:Fronts = 0
function Set-SmokeFront { $script:Fronts++ }
$script:StopCalls = New-Object System.Collections.ArrayList
function Stop-BoardDrag([bool]$Commit) { [void]$script:StopCalls.Add([string]$Commit); $script:BoardDrag = $null }
function Reset-Fake {
    $script:Lines.Clear(); $script:Errs.Clear(); $script:Warns.Clear(); $script:Mouse.Clear(); $script:StopCalls.Clear()
    $script:MouseOk = $true; $script:WinHits = @{}; $script:WinDefault = $true; $script:Fronts = 0
    $script:SmokeDrag = $null; $script:SmokeMouseDown = $false; $script:BoardDrag = $null
}
function Has-Line([string]$Needle) { foreach ($l in $script:Lines) { if ($l.Contains($Needle)) { return $true } }; return $false }

# ======================= 1) görünürlük ölçümü =======================
# Windows'un kendi saydamlık anahtarı (kayıt Linux'ta yok: açık sayılır). Sınamak için aşağıda sahtesi kullanılır.
Assert-True (Test-SmokeSysTransparency) 'sistem saydamlığı okunamazsa açık sayılır (efekt beklenir)'
$realSysTr = (Get-Item function:Test-SmokeSysTransparency).ScriptBlock
$script:SysTr = $true
function Test-SmokeSysTransparency { return $script:SysTr }
# efekt bu oturumda uygulanıyor (Akrilik); aşağıda "uygulanmıyor" durumu ayrıca denenir
$script:GlassPlan = @{ Req = 'Akrilik'; Mode = 'Akrilik'; Api = 'Acrylic'; Note = '' }
$script:SmokeStats = @{
    'base' = @{ R = 20.0; G = 30.0; B = 40.0 }
    'on'   = @{ R = 80.0; G = 30.0; B = 70.0 }
    'same' = @{ R = 21.0; G = 31.0; B = 41.0 }
}
Reset-Fake
Test-SmokeGlassVisible 'on|base|8'
Assert-Eq $script:Errs.Count 0 'görünürlük: fark yeterliyse hata yok'
Assert-True (Has-Line 'fark 30') 'görünürlük: ortalama renk farkı (|60|+|0|+|30|)/3 = 30 yazılır'
Assert-True (Has-Line 'ortalama renk 80,30,70 (efekt kapalıyken 20,30,40)') 'görünürlük: iki ortalama renk de satırda'
Reset-Fake
Test-SmokeGlassVisible 'same|base|8'
Assert-Eq $script:Errs.Count 1 'görünürlük: fark yetersizse tek hata'
Assert-True ($script:Errs[0].StartsWith('saydamlık: efekt görünmüyor')) 'görünürlük: hata saydamlık başlığıyla'
Assert-True ($script:Errs[0].Contains('beklenen en az 8')) 'görünürlük: hata beklenen eşiği söyler'
Reset-Fake
$script:SysTr = $false
Test-SmokeGlassVisible 'same|base|8'
Assert-Eq ($script:Errs.Count.ToString() + '|' + $script:Warns.Count.ToString()) '0|1' 'görünürlük: Windows saydamlık efektleri kapalıysa hata değil uyarı'
Assert-True ($script:Warns[0].Contains('saydamlık efektleri kapalı')) 'görünürlük: uyarı nedenini söyler'
Reset-Fake
Test-SmokeGlassVisible 'on|base|8'
Assert-Eq ($script:Errs.Count.ToString() + '|' + $script:Warns.Count.ToString()) '0|0' 'görünürlük: sistem efekti kapalı olsa da fark yeterliyse uyarı yok'
$script:SysTr = $true
Reset-Fake
Test-SmokeGlassVisible 'same|base|0'
Assert-Eq $script:Errs.Count 0 'görünürlük: eşik 0 ise fark küçük olsa da yalnızca yazılır'
Assert-True (Has-Line 'fark 1') 'görünürlük: eşik 0 iken de fark satırı yazılır'
Reset-Fake
Test-SmokeGlassVisible 'yok|base|8'
Assert-Eq $script:Errs.Count 0 'görünürlük: ölçüm yoksa hata değil uyarı'
Assert-Eq $script:Warns.Count 1 'görünürlük: ölçüm yoksa bir uyarı'
Reset-Fake
Test-SmokeGlassVisible 'on|yok|8'
Assert-Eq ($script:Errs.Count.ToString() + '|' + $script:Warns.Count.ToString()) '0|1' 'görünürlük: kapalı görüntü yoksa da uyarı'
# Gerçek cihazda bulundu: ayar kopyasında kalıcı güvenli çizim varsa saydamlık hiç uygulanmaz; efekt görünmez ve bu beklenen durumdur
$script:GlassPlan = @{ Req = 'Akrilik'; Mode = 'Yok'; Api = ''; Note = 'Güvenli çizim kipinde saydamlık kapalıdır.' }
Reset-Fake
Test-SmokeGlassVisible 'same|base|8'
Assert-Eq ($script:Errs.Count.ToString() + '|' + $script:Warns.Count.ToString()) '0|0' 'görünürlük: efekt uygulanmıyorsa (güvenli çizim) hata da uyarı da yok'
Assert-True (Has-Line 'efekt bu oturumda uygulanmıyor (Güvenli çizim kipinde saydamlık kapalıdır.)') 'görünürlük: uygulanmama nedeni satıra yazılır'
Assert-True (Has-Line 'ortalama renk') 'görünürlük: uygulanmasa da ölçülen renkler satırda'
$script:GlassPlan = @{ Req = 'Akrilik'; Mode = 'Akrilik'; Api = 'Acrylic'; Note = '' }
Reset-Fake
Test-SmokeGlassVisible 'same|base|8'
Assert-Eq $script:Errs.Count 1 'görünürlük: efekt uygulanırken görünmüyorsa hâlâ hata'
# Gerçek cihazda bulundu: "Ayrıntılı" yerleşimde işlem günlüğü ve kartlar gövdeyi kaplar (Akrilik %70 için gövde farkı 2,4, %50 için 6,4);
# cam başlık ve durum çubuğu şeritlerinde belirgindir (6,4 ve 13,9). Büyük olan fark sayılır.
$script:SmokeStats = @{
    'base'  = @{ R = 23.0; G = 34.0; B = 51.0; BarR = 20.0; BarG = 30.0; BarB = 45.0 }
    'bar'   = @{ R = 24.0; G = 35.0; B = 52.0; BarR = 40.0; BarG = 46.0; BarB = 51.0 }
    'none'  = @{ R = 24.0; G = 35.0; B = 52.0; BarR = 21.0; BarG = 31.0; BarB = 46.0 }
    'nobar' = @{ R = 24.0; G = 35.0; B = 52.0 }
}
Reset-Fake
Test-SmokeGlassVisible 'bar|base|8'
Assert-Eq $script:Errs.Count 0 'görünürlük: gövde farkı küçük ama şerit farkı yeterliyse hata yok'
Assert-True (Has-Line 'fark 1, üst ve alt şerit farkı 14') 'görünürlük: gövde ve şerit farkı birlikte yazılır'
Reset-Fake
Test-SmokeGlassVisible 'none|base|8'
Assert-Eq $script:Errs.Count 1 'görünürlük: gövde ve şerit farkı da yetersizse hata'
Assert-True ($script:Errs[0].Contains('üst ve alt şerit farkı 1') -and $script:Errs[0].Contains('beklenen en az 8')) 'görünürlük: hata iki farkı da ve eşiği söyler'
Reset-Fake
Test-SmokeGlassVisible 'nobar|base|8'
Assert-Eq $script:Errs.Count 1 'görünürlük: şerit ölçümü yoksa yalnızca gövdeye bakılır'
Assert-True (-not $script:Errs[0].Contains('şerit')) 'görünürlük: şerit ölçümü yoksa hata metninde şerit geçmez'
Reset-Fake
Test-SmokeGlassVisible 'bar|nobar|8'
Assert-Eq $script:Errs.Count 1 'görünürlük: şerit ölçümü yalnızca bir yanda varsa yok sayılır'
Reset-Fake
Test-SmokeGlassVisible 'bar|base|0'
Assert-Eq $script:Errs.Count 0 'görünürlük: eşik 0 iken şerit farkı yalnızca yazılır'
Assert-True (Has-Line 'şerit farkı 14') 'görünürlük: eşik 0 iken de şerit farkı satırda'
$script:GlassPlan = @{ Req = 'Akrilik'; Mode = 'Yok'; Api = ''; Note = 'Güvenli çizim kipinde saydamlık kapalıdır.' }
Reset-Fake
Test-SmokeGlassVisible 'none|base|8'
Assert-Eq ($script:Errs.Count.ToString() + '|' + $script:Warns.Count.ToString()) '0|0' 'görünürlük: efekt uygulanmıyorsa şerit farkı olsa da hata yok'
$script:GlassPlan = @{ Req = 'Akrilik'; Mode = 'Akrilik'; Api = 'Acrylic'; Note = '' }
$script:SmokeStats = @{
    'base' = @{ R = 20.0; G = 30.0; B = 40.0 }
    'on'   = @{ R = 80.0; G = 30.0; B = 70.0 }
    'same' = @{ R = 21.0; G = 31.0; B = 41.0 }
}

# ======================= 2) sol bölgenin ortalama rengi =======================
function New-FakeBmp([int]$W, [int]$H, $Left, $Right) {
    $b = [pscustomobject]@{ Width = $W; Height = $H; L = $Left; R = $Right; Calls = 0 }
    $b | Add-Member -MemberType ScriptMethod -Name GetPixel -Value {
        param($x, $y)
        $this.Calls++
        if ($x -lt [int]($this.Width * 0.5)) { return [pscustomobject]@{ R = $this.L[0]; G = $this.L[1]; B = $this.L[2] } }
        return [pscustomobject]@{ R = $this.R[0]; G = $this.R[1]; B = $this.R[2] }
    }
    return $b
}
$bmp = New-FakeBmp 1380 840 @(10, 20, 30) @(250, 250, 250)
$m = Get-SmokeLeftMean $bmp
Assert-Eq ([string][int]$m.R + ',' + [string][int]$m.G + ',' + [string][int]$m.B) '10,20,30' 'sol bölge ortalaması: sağ yarı hesaba girmez'
Assert-True ($bmp.Calls -gt 1000 -and $bmp.Calls -lt 40000) ('sol bölge ortalaması: örnekleme makul (' + $bmp.Calls + ' piksel)')
$bmp2 = New-FakeBmp 1380 840 @(100, 100, 100) @(0, 0, 0)
$m2 = Get-SmokeLeftMean $bmp2
Assert-True ([math]::Abs($m2.R - 100.0) -lt 0.001 -and [math]::Abs($m2.B - 100.0) -lt 0.001) 'sol bölge ortalaması: düz renk aynen döner'
Assert-True ($null -eq (Get-SmokeLeftMean (New-FakeBmp 1 1 @(1, 1, 1) @(1, 1, 1)))) 'sol bölge ortalaması: örnek alınamayacak kadar küçük görüntüde $null'
# üst ve alt şerit (başlık ve durum çubuğu): gövdeden ayrı örneklenir; gerçek cihazda cam her yerleşimde en çok orada görünür
function New-FakeBmpBands([int]$W, [int]$H, $Body, $Band) {
    $b = [pscustomobject]@{ Width = $W; Height = $H; Body = $Body; Band = $Band; Calls = 0 }
    $b | Add-Member -MemberType ScriptMethod -Name GetPixel -Value {
        param($x, $y)
        $this.Calls++
        if ($y -lt [int]($this.Height * 0.08) -or $y -ge [int]($this.Height * 0.92)) { return [pscustomobject]@{ R = $this.Band[0]; G = $this.Band[1]; B = $this.Band[2] } }
        return [pscustomobject]@{ R = $this.Body[0]; G = $this.Body[1]; B = $this.Body[2] }
    }
    return $b
}
$bmp3 = New-FakeBmpBands 1380 840 @(10, 20, 30) @(200, 100, 50)
$m3 = Get-SmokeLeftMean $bmp3
Assert-Eq ([string][int]$m3.R + ',' + [string][int]$m3.G + ',' + [string][int]$m3.B) '10,20,30' 'şerit: gövde ortalaması şeritlerden etkilenmez'
Assert-Eq ([string][int]$m3.BarR + ',' + [string][int]$m3.BarG + ',' + [string][int]$m3.BarB) '200,100,50' 'şerit: üst ve alt şerit ortalaması ayrı döner'
Assert-True ($bmp3.Calls -gt 1000 -and $bmp3.Calls -lt 40000) ('şerit: örnekleme makul (' + $bmp3.Calls + ' piksel)')
$m4 = Get-SmokeLeftMean (New-FakeBmp 1380 840 @(10, 20, 30) @(250, 250, 250))
Assert-True ([math]::Abs($m4.BarR - 10.0) -lt 0.001 -and [math]::Abs($m4.BarB - 30.0) -lt 0.001) 'şerit: düz renkte şerit ortalaması da aynen döner (sağ yarı hesaba girmez)'
$m5 = Get-SmokeLeftMean (New-FakeBmp 100 6 @(5, 6, 7) @(5, 6, 7))
Assert-True ($null -ne $m5 -and $null -eq $m5.BarR) 'şerit: şerit örneği alınamayacak kadar kısa görüntüde yalnızca gövde döner'

# ======================= 3) sürükleme planı =======================
function New-FakeEl([double]$Ox, [double]$Oy, [double]$W, [double]$H) {
    $o = [pscustomobject]@{ ActualWidth = $W; ActualHeight = $H; Ox = $Ox; Oy = $Oy }
    $o | Add-Member -MemberType ScriptMethod -Name PointToScreen -Value { param($p) [pscustomobject]@{ X = $this.Ox + $p.X; Y = $this.Oy + $p.Y } }
    return $o
}
function New-FakeBoard {
    $script:BoardMetrics = @{ CellW = 80.0; CellH = 70.0; Gap = 10.0; W = 1070.0 }
    $script:BoardEdit = $true
    $script:BoardLayout = New-Object System.Collections.ArrayList
    $script:BoardViews = @{}
    $specs = @(@('a', 'hero', 0, 0, 12, 2), @('b', 'cpu', 0, 2, 3, 2), @('c', 'ram', 3, 2, 3, 2), @('d', 'net', 9, 2, 3, 2))
    foreach ($s in $specs) {
        [void]$script:BoardLayout.Add(@{ Id = $s[0]; Type = $s[1]; X = $s[2]; Y = $s[3]; W = $s[4]; H = $s[5]; Arg = '' })
        $ox = 100.0 + [double]$s[2] * 90.0
        $oy = 200.0 + [double]$s[3] * 80.0
        $w = [double]$s[4] * 80.0 + ([double]$s[4] - 1) * 10.0
        $h = [double]$s[5] * 70.0 + ([double]$s[5] - 1) * 10.0
        $script:BoardViews[[string]$s[0]] = @{ N = @{ Veil = (New-FakeEl $ox $oy $w $h); Grip = (New-FakeEl ($ox + $w - 26.0) ($oy + $h - 26.0) 26.0 26.0) } }
    }
}
New-FakeBoard
Reset-Fake
$p = Get-SmokeDragPlan 'move'
Assert-Eq $p.Id 'b' 'taşıma planı: tam genişlikteki hero atlanır, ilk uygun parça seçilir'
Assert-Eq ([string]($p.X1 - $p.X0) + ',' + [string]($p.Y1 - $p.Y0)) '90,80' 'taşıma planı: bir sütun sağa (80+10) ve bir satır aşağı (70+10)'
Assert-Eq ($p.TX.ToString() + ',' + $p.TY.ToString() + ',' + $p.TW.ToString() + ',' + $p.TH.ToString()) '0,2,3,2' 'taşıma planı: özgün konum ve boyut kaydedilir'
# parçanın ortası: cpu 3x2 -> genişlik 3*80+2*10 = 260, yükseklik 2*70+10 = 150; orta (130, 75); köken (100, 360)
Assert-Eq ($p.X0.ToString() + ',' + $p.Y0.ToString()) '230,435' 'taşıma planı: başlangıç parçanın ortasındadır'
# en sağdaki parça sola kaydırılır
Reset-Fake
$script:WinHits = @{}
New-FakeBoard
$script:BoardLayout.RemoveAt(2); $script:BoardLayout.RemoveAt(1)
$p = Get-SmokeDragPlan 'move'
Assert-Eq $p.Id 'd' 'taşıma planı: sağ kenardaki parça seçilir'
Assert-Eq ([string]($p.X1 - $p.X0)) '-90' 'taşıma planı: sağa yer yoksa bir sütun sola'
# boyutlandırma: hero genişlik sınırında (12) -> daralır; yükseklik 2 < 3 -> büyür
New-FakeBoard
$p = Get-SmokeDragPlan 'size'
Assert-Eq $p.Id 'a' 'boyut planı: ilk parça (hero) seçilir'
Assert-Eq ([string]($p.X1 - $p.X0) + ',' + [string]($p.Y1 - $p.Y0)) '-90,80' 'boyut planı: genişlik azalır (en çok 12), yükseklik artar (en çok 3)'
# Grip 26x26 parçanın sağ alt köşesinde; orta noktası köşeden 13 px içeride
$vHero = $script:BoardViews['a'].N.Grip
Assert-Eq ($p.X0.ToString() + ',' + $p.Y0.ToString()) ([string]([int]($vHero.Ox + 13)) + ',' + [string]([int]($vHero.Oy + 13))) 'boyut planı: başlangıç köşe tutamacının ortasındadır'
# boyutlandırma sınırları: tüm parçalar en büyük boyutta ve en küçük boyutta ise parça atlanır
New-FakeBoard
$script:BoardLayout.Clear()
[void]$script:BoardLayout.Add(@{ Id = 'z'; Type = 'search'; X = 0; Y = 0; W = 4; H = 1; Arg = '' })
$script:BoardViews = @{ z = @{ N = @{ Veil = (New-FakeEl 100 200 350 70); Grip = (New-FakeEl 424 244 26 26) } } }
$p = Get-SmokeDragPlan 'size'
Assert-Eq ([string]($p.X1 - $p.X0) + ',' + [string]($p.Y1 - $p.Y0)) '90,0' 'boyut planı: yüksekliği sabit (1/1) parçada yalnızca genişlik değişir'
$script:BoardLayout[0].W = 12
$p = Get-SmokeDragPlan 'size'
Assert-Eq ([string]($p.X1 - $p.X0) + ',' + [string]($p.Y1 - $p.Y0)) '-90,0' 'boyut planı: en büyük genişlikte daraltılır'
$script:BoardLayout[0].W = 4
$script:BoardWidgets['search'].MinW = 4
$script:BoardWidgets['search'].MaxW = 4
$p = Get-SmokeDragPlan 'size'
Assert-True ($null -eq $p) 'boyut planı: hiçbir yönde değişemeyen parça için plan yok'
$script:BoardWidgets['search'].MinW = 4
$script:BoardWidgets['search'].MaxW = 12
# pencere o noktada görünmüyorsa parça atlanır; hiçbiri uygun değilse $null
New-FakeBoard
Reset-Fake
$script:WinDefault = $false
Assert-True ($null -eq (Get-SmokeDragPlan 'move')) 'taşıma planı: pencere hiçbir yerde görünmüyorsa plan yok'
$script:WinDefault = $true
$first = Get-SmokeDragPlan 'move'
$script:WinHits[[string]$first.X1 + ',' + [string]$first.Y1] = $false
$second = Get-SmokeDragPlan 'move'
Assert-True ($null -ne $second -and $second.Id -ne $first.Id) 'taşıma planı: bitiş noktası başka pencerenin altındaysa sıradaki parçaya geçilir'
# düzenleme kipi kapalıysa ya da ölçüler yoksa plan yok
$script:BoardEdit = $false
Assert-True ($null -eq (Get-SmokeDragPlan 'move')) 'sürükleme planı: düzenleme kipi kapalıyken yok'
$script:BoardEdit = $true
$saveM = $script:BoardMetrics
$script:BoardMetrics = $null
Assert-True ($null -eq (Get-SmokeDragPlan 'size')) 'sürükleme planı: pano ölçüleri yokken yok'
$script:BoardMetrics = $saveM
# boyutu ölçülemeyen (gizli) öğe atlanır
$script:BoardViews['b'].N.Veil.ActualWidth = 0
$script:BoardViews['c'].N.Veil.ActualHeight = [double]::NaN
$p = Get-SmokeDragPlan 'move'
Assert-Eq $p.Id 'd' 'taşıma planı: boyutu 0 ya da NaN olan öğe atlanır'

# ======================= 4) sürükleme adımları ve sonuç denetimi =======================
$script:Settings = @{ BoardCustom = $true }
function Run-Drag([string]$Mode) {
    foreach ($ph in @('down', '1', '2', '3', '4', '5', 'up', 'check')) { Invoke-SmokeDrag ($Mode + '|' + $ph) }
}
New-FakeBoard
Reset-Fake
Invoke-SmokeDrag 'move|down'
Assert-Eq $script:Mouse.Count 1 'sürükleme: basma adımında tek fare olayı'
Assert-True ($script:Mouse[0].StartsWith('down:230,435:True')) 'sürükleme: fare düğmesi parçanın ortasında basılır'
Assert-True ($script:SmokeMouseDown -eq $true -and $script:Fronts -eq 1) 'sürükleme: düğme basılı işaretlenir ve pencere öne alınır'
foreach ($i in 1..5) { Invoke-SmokeDrag ('move|' + $i) }
Assert-Eq $script:Mouse.Count 6 'sürükleme: beş ara adım beş hareket olayı'
Assert-Eq ($script:Mouse[1] + ' ' + $script:Mouse[5]) 'move:248,451:True move:320,515:True' 'sürükleme: hareket adımları başlangıçtan bitişe eşit aralıkla (ilk ve son)'
Invoke-SmokeDrag 'move|up'
Assert-Eq $script:Mouse[6] 'up:320,515:True' 'sürükleme: fare hedef noktada bırakılır'
Assert-True ($script:SmokeMouseDown -eq $false) 'sürükleme: bırakınca basılı işareti kalkar'
# taşıma sonucu: parça gerçekten kaydı
$t = Find-BoardTile $script:BoardLayout 'b'
$t.X = 1; $t.Y = 4
$script:Settings.BoardCustom = $true
Invoke-SmokeDrag 'move|check'
Assert-Eq $script:Errs.Count 0 'sürükleme sonucu: parça kaydıysa hata yok'
Assert-True (Has-Line 'sürükleme taşıma: cpu 0,2 -> 1,4') 'sürükleme sonucu: eski ve yeni konum yazılır'
Assert-True ($null -eq $script:SmokeDrag) 'sürükleme sonucu: plan temizlenir'
# parça yerinde kaldı
New-FakeBoard; Reset-Fake
Run-Drag 'move'
Assert-Eq $script:Errs.Count 1 'sürükleme sonucu: parça oynamadıysa hata'
Assert-True ($script:Errs[0].Contains('parça yerinden oynamadı')) 'sürükleme sonucu: hata metni'
Assert-Eq $script:Mouse.Count 7 'sürükleme: tam dizi yedi fare olayı (bas, beş hareket, bırak); kontrol adımı olay üretmez'
# düzen değişti ama özel düzen işareti kapalı
New-FakeBoard; Reset-Fake
$script:Settings.BoardCustom = $false
foreach ($ph in @('down', '1', '2', '3', '4', '5', 'up')) { Invoke-SmokeDrag ('move|' + $ph) }
$t = Find-BoardTile $script:BoardLayout 'b'; $t.X = 1; $t.Y = 4
Invoke-SmokeDrag 'move|check'
Assert-Eq $script:Errs.Count 1 'sürükleme sonucu: özel düzen işareti kapalıysa hata'
Assert-True ($script:Errs[0].Contains('özel düzen işareti kapalı')) 'sürükleme sonucu: işaret hatası'
$script:Settings.BoardCustom = $true
# sürükleme bitmedi
New-FakeBoard; Reset-Fake
foreach ($ph in @('down', '1', '2', '3', '4', '5', 'up')) { Invoke-SmokeDrag ('move|' + $ph) }
$t = Find-BoardTile $script:BoardLayout 'b'; $t.X = 1
$script:BoardDrag = @{ Id = 'b' }
Invoke-SmokeDrag 'move|check'
Assert-True ($script:Errs.Count -ge 1 -and $script:Errs[0].Contains('sürükleme bitmedi')) 'sürükleme sonucu: fare bırakıldı ama sürükleme sürüyorsa hata'
Assert-Eq ($script:StopCalls -join ',') 'False' 'sürükleme sonucu: takılı kalan sürükleme iptal edilir'
# düzen çakışması
New-FakeBoard; Reset-Fake
foreach ($ph in @('down', '1', '2', '3', '4', '5', 'up')) { Invoke-SmokeDrag ('move|' + $ph) }
$t = Find-BoardTile $script:BoardLayout 'b'; $t.X = 3; $t.Y = 2
Invoke-SmokeDrag 'move|check'
Assert-True (@($script:Errs | Where-Object { $_.Contains('düzen sorunları') -and $_.Contains('çakışma') }).Count -eq 1) 'sürükleme sonucu: çakışan düzen hata olarak bildirilir'
# boyutlandırma sonucu
New-FakeBoard; Reset-Fake
foreach ($ph in @('down', '1', '2', '3', '4', '5', 'up')) { Invoke-SmokeDrag ('size|' + $ph) }
$t = Find-BoardTile $script:BoardLayout 'a'; $t.W = 11
Invoke-SmokeDrag 'size|check'
Assert-Eq $script:Errs.Count 0 'boyut sonucu: boyut değiştiyse hata yok'
Assert-True (Has-Line 'sürükleme boyut: hero 12x2 -> 11x2') 'boyut sonucu: eski ve yeni boyut yazılır'
New-FakeBoard; Reset-Fake
Run-Drag 'size'
Assert-True ($script:Errs.Count -eq 1 -and $script:Errs[0].Contains('boyutu değişmedi')) 'boyut sonucu: boyut aynıysa hata'
# plan yoksa uyarı ve hiçbir fare olayı
New-FakeBoard; Reset-Fake
$script:WinDefault = $false
Run-Drag 'move'
Assert-Eq ($script:Warns.Count.ToString() + '|' + $script:Errs.Count.ToString() + '|' + $script:Mouse.Count.ToString()) '1|0|0' 'plan yoksa: tek uyarı, hata ve fare olayı yok'
Assert-True ($script:Warns[0].Contains('atlandı')) 'plan yoksa: uyarı adımın atlandığını söyler'
# fare girdisi gönderilemezse hata
New-FakeBoard; Reset-Fake
$script:MouseOk = $false
Invoke-SmokeDrag 'move|down'
Assert-True ($script:Errs.Count -eq 1 -and $script:Errs[0].Contains('fare girdisi gönderilemedi') -and $null -eq $script:SmokeDrag -and $script:SmokeMouseDown -ne $true) 'fare girdisi gönderilemezse hata verilir ve düğme basılı kalmaz'

# ======================= 5) temizlik =======================
New-FakeBoard; Reset-Fake
$script:SmokeMouseDown = $true
$bk = [pscustomobject]@{ Closed = 0 }
$bk | Add-Member -MemberType ScriptMethod -Name Close -Value { $this.Closed++ }
$script:SmokeBackdrop = $bk
$script:SmokeStatsOn = $true
Stop-SmokeLook
Assert-Eq $script:Mouse.Count 1 'temizlik: basılı kalmış fare düğmesi bırakılır'
Assert-True ($script:Mouse[0].StartsWith('up:0,0:False')) 'temizlik: bırakma imleci oynatmadan yapılır'
Assert-True ($script:SmokeMouseDown -eq $false) 'temizlik: basılı işareti kalkar'
Assert-True ($bk.Closed -eq 1 -and $null -eq $script:SmokeBackdrop -and $script:SmokeStatsOn -eq $false) 'temizlik: renkli zemin kapanır, ölçüm durur'
Reset-Fake
Stop-SmokeLook
Assert-Eq $script:Mouse.Count 0 'temizlik: düğme basılı değilse fare olayı gönderilmez'
Remove-SmokeBackdrop
Assert-True ($null -eq $script:SmokeBackdrop) 'temizlik: ikinci çağrı zararsız'

# ======================= 6) kuyruk sırası =======================
$sk = @('panel', 'optimize', 'settings')
$say = @((New-SmokeQueue 'Neon' $sk { param($k) @() } 'Ayrintili' 'saydam').ToArray())
$kinds = @($say | ForEach-Object { $_.Kind })
$onI = [array]::IndexOf($kinds, 'Backdrop')
$bd = @($say | Where-Object { $_.Kind -eq 'Backdrop' } | ForEach-Object { $_.Arg })
Assert-Eq ($bd -join ',') 'on,off' 'saydam kapsamı: renkli zemin bir kez açılır, bir kez kapanır'
$firstScreen = [array]::IndexOf($kinds, 'Screen')
Assert-True ($onI -ge 0 -and $onI -lt $firstScreen) 'saydam kapsamı: renkli zemin ilk gerçek görüntüden önce açılır'
$offI = $kinds.Count - 1 - [array]::IndexOf(@($kinds[($kinds.Count - 1)..0]), 'Backdrop')
$lastScreen = $kinds.Count - 1 - [array]::IndexOf(@($kinds[($kinds.Count - 1)..0]), 'Screen')
Assert-True ($offI -gt $lastScreen) 'saydam kapsamı: renkli zemin son gerçek görüntüden sonra kapanır'
Assert-Eq ($say[$offI + 1].Kind) 'Theme' 'saydam kapsamı: zemin kapanınca başlangıç temasına dönülür'
$screens = @($say | Where-Object { $_.Kind -eq 'Screen' } | ForEach-Object { $_.Arg })
$gv = @($say | Where-Object { $_.Kind -eq 'GlassVisible' })
$nOps = 0
foreach ($mm in @($script:SmokeGlassOps.Keys)) { $nOps += @($script:SmokeGlassOps[$mm]).Count }
Assert-Eq $gv.Count $nOps 'saydam kapsamı: her opaklık denemesi için bir görünürlük ölçümü'
foreach ($g in $gv) {
    $q = $g.Arg.Split('|')
    Assert-True ($screens -contains $q[0] -and $screens -contains $q[1]) ('görünürlük ' + $q[0] + ': ölçülen ve kapalıyken alınan görüntü kuyrukta var')
    Assert-True ([array]::IndexOf($screens, $q[1]) -lt [array]::IndexOf($screens, $q[0])) ('görünürlük ' + $q[0] + ': kapalı görüntü önce alınır')
    $gi = [array]::IndexOf(@($say | ForEach-Object { $_.Kind + ':' + $_.Arg }), ('GlassVisible:' + $g.Arg))
    Assert-Eq ($say[$gi - 1].Kind + ':' + $say[$gi - 1].Arg) ('Screen:' + $q[0]) ('görünürlük ' + $q[0] + ': ölçüm kendi görüntüsünün hemen ardından')
    $want = '0'
    if ($q[0] -like 'saydam-Akrilik-*') {
        $o = [int]($q[0] -replace '^saydam-Akrilik-', '')
        if ($o -le 50) { $want = '8' } elseif ($o -le 70) { $want = '2.5' }
    }
    Assert-Eq $q[2] $want ('görünürlük ' + $q[0] + ': eşik ' + $want)
}
Assert-Eq (@($gv | Where-Object { $_.Arg -eq 'saydam-Akrilik-70|saydam-Yok-Neon|2.5' }).Count) 1 'saydam kapsamı: Akrilik %70 için eşik 2,5 (cihazda ölçülen en düşük fark 3,9)'
Assert-Eq (@($gv | Where-Object { $_.Arg -eq 'saydam-Akrilik-50|saydam-Yok-Neon|8' }).Count) 1 'saydam kapsamı: Akrilik %50 için eşik 8 (cihazda ölçülen en düşük fark 12)'
Assert-Eq (@($gv | Where-Object { -not $_.Arg.EndsWith('|0') }).Count) 2 'saydam kapsamı: eşik yalnızca Akrilik %70 ve %50 için'
Assert-Eq ($say[$onI + 1].Kind + ':' + $say[$onI + 1].Arg) 'Screen:saydam-Yok-Neon' 'saydam kapsamı: efektsiz taban görüntü zemin açılır açılmaz alınır'
# tasarım kapsamı: sürükleme yalnızca düzenleme kipi açıkken
$tas = @((New-SmokeQueue 'Neon' $sk { param($k) @() } 'Ayrintili' 'tasarim').ToArray())
$nd = $script:SmokeDesigns.Count
$dr = @($tas | Where-Object { $_.Kind -eq 'Drag' } | ForEach-Object { $_.Arg })
Assert-Eq $dr.Count (16 * $nd) 'tasarım kapsamı: her tasarımda taşıma ve boyutlandırma için sekizer sürükleme adımı'
Assert-Eq ((@($dr | Select-Object -First 8)) -join ',') 'move|down,move|1,move|2,move|3,move|4,move|5,move|up,move|check' 'tasarım kapsamı: taşıma adımları sırayla bas, beş hareket, bırak, denetle'
Assert-Eq ((@($dr | Select-Object -Skip 8 -First 8)) -join ',') 'size|down,size|1,size|2,size|3,size|4,size|5,size|up,size|check' 'tasarım kapsamı: boyutlandırma adımları aynı sırada'
$edit = $false
$bad = 0
$shotOk = 0
for ($i = 0; $i -lt $tas.Count; $i++) {
    $st = $tas[$i]
    if ($st.Kind -eq 'Click' -and $st.Arg -eq 'st_BoardEdit') { $edit = $true }
    elseif ($st.Kind -eq 'Click' -and $st.Arg -eq 'bd_BtnEdit') { $edit = -not $edit }
    if ($st.Kind -eq 'Drag' -and -not $edit) { $bad++ }
    if ($st.Kind -eq 'Shot' -and $st.Arg -like 'tasarim-*-surukleme' -and $edit) { $shotOk++ }
}
Assert-Eq $bad 0 'tasarım kapsamı: sürükleme adımlarının hepsi düzenleme kipi açıkken'
Assert-Eq $shotOk $nd 'tasarım kapsamı: her tasarımda sürükleme sonrası görüntü, düzen hâlâ açıkken'
# her sürükleme dizisinin sonunda bir sonraki adım düzen sonucunu bekler
$ci = [array]::IndexOf(@($tas | ForEach-Object { $_.Kind + ':' + $_.Arg }), 'Drag:size|check')
Assert-Eq ($tas[$ci + 1].Kind + ':' + $tas[$ci + 1].Arg) ('Shot:tasarim-' + $script:SmokeDesigns[0] + '-surukleme') 'tasarım kapsamı: boyut denetiminden sonra görüntü'
Assert-Eq (@($tas | Where-Object { $_.Kind -eq 'Backdrop' -or $_.Kind -eq 'GlassVisible' }).Count) 0 'tasarım kapsamında renkli zemin ve görünürlük ölçümü yok'
# öteki kapsamlarda yeni adımlar yok
foreach ($sc in @('tepsi', 'gorunum')) {
    $q = @((New-SmokeQueue 'Neon' $sk { param($k) @() } 'Ayrintili' $sc).ToArray())
    Assert-Eq (@($q | Where-Object { $_.Kind -in @('Drag', 'Backdrop', 'GlassVisible') }).Count) 0 ($sc + ' kapsamı: sürükleme, renkli zemin ve görünürlük adımı yok')
}
# tam kuyruk ikisini de içerir
$tam = @((New-SmokeQueue 'Neon' $sk { param($k) @() } 'Ayrintili').ToArray())
Assert-Eq (@($tam | Where-Object { $_.Kind -eq 'Drag' }).Count) (16 * $nd) 'tam kuyruk: sürükleme adımları dahil'
Assert-Eq (@($tam | Where-Object { $_.Kind -eq 'Backdrop' }).Count) 2 'tam kuyruk: renkli zemin açma ve kapama dahil'
Assert-Eq (@($tam | Where-Object { $_.Kind -eq 'GlassVisible' }).Count) $nOps 'tam kuyruk: görünürlük ölçümleri dahil'
# adım sürelerinin toplamı zaman aşımının yarısını geçmez (tam kuyruk)
$w = 0.0
foreach ($st in $tam) { $w += [double]$st.Wait / 1000.0 }
Assert-True ($w -lt ([double]$script:SmokeLimitSec / 2.0)) ('tam kuyruk: adım beklemeleri toplamı zaman aşımının yarısından az (' + [string][int]$w + ' sn)')
# güvenli tıklama listesi
Assert-True ($script:SmokeSafe -contains 'bd_BtnEdit') 'düzenleme düğmesi duman testinin güvenli listesinde'
foreach ($b in @('st_DsReset', 'st_BoardEdit', 'st_BoardReset')) { Assert-True ($script:SmokeSafe -contains $b) "$b duman testinin güvenli listesinde (yalnızca görünümü değiştirir)" }
foreach ($b in @('st_Uygula', 'op_Apply', 'st_WipeAll')) { Assert-True ($script:SmokeSafe -notcontains $b) "$b güvenli listede değil" }

# ======================= 6b) kuyruk yapısı: açılır listeler, ana ekran, ayrıntılar =======================
$dsg = @($script:SmokeDesigns)
Assert-Eq ($dsg -join ',') 'Klasik,Atolye,Sifir,Morpheus,Komuta' 'duman: tasarım sırası (Klasik dahil beş)'
Assert-Eq ($dsg -join ',') (@($script:DesignInfo.Keys) -join ',') 'duman tasarımları DesignInfo ile aynı'
Assert-Eq (@($script:SmokeThemes | Sort-Object) -join ',') (@($script:Themes.Keys | Sort-Object) -join ',') 'duman temaları Themes ile aynı'
$all = @($tam | ForEach-Object { $_.Kind + ':' + $_.Arg })
$tk = @($tas | ForEach-Object { $_.Kind + ':' + $_.Arg })
foreach ($d in $dsg) {
    Assert-True (@($tk | Where-Object { $_ -eq ('Select:st_DesignSel|' + $d) }).Count -ge 2) "tasarım kapsamı: $d listeden en az iki kez seçilir (tek tek ve tema dizisinde)"
    Assert-Eq (@($tk | Where-Object { $_ -eq ('DesignCheck:' + $d) }).Count -ge 1) $true "tasarım kapsamı: $d doğrulanır"
    Assert-Eq (@($tk | Where-Object { $_ -eq ('Shot:tasarim-' + $d + '-panel') }).Count) 1 "tasarım kapsamı: $d panel görüntüsü bir kez"
    Assert-Eq (@($tk | Where-Object { $_ -eq ('Shot:tasarim-' + $d + '-klasikpano') }).Count) 1 "tasarım kapsamı: $d klasik durum panosu görüntüsü bir kez"
    foreach ($t in $script:SmokeThemes) { Assert-Eq (@($tk | Where-Object { $_ -eq ('Shot:tasarim-' + $d + '-' + $t) }).Count) 1 "tasarım kapsamı: $d x $t görüntüsü" }
}
Assert-Eq (@($tk | Where-Object { $_ -eq 'Select:st_HomeSel|Klasik' }).Count) $nd 'ana ekran: her tasarımda klasik durum panosu listeden seçilir'
$hc = @($tas | Where-Object { $_.Kind -eq 'HomeCheck' } | ForEach-Object { $_.Arg })
Assert-Eq ($hc -join ',') ((1..$nd | ForEach-Object { 'Pano,Klasik,Pano' }) -join ',') 'ana ekran: her tasarımda pano, klasik, düzenle ile panoya dönüş sırası'
for ($i = 0; $i -lt $tk.Count; $i++) {
    if ($tk[$i] -eq 'Select:st_HomeSel|Klasik') {
        Assert-Eq $tk[$i + 1] 'HomeCheck:Klasik' 'ana ekran: klasik seçilince hemen doğrulanır'
        Assert-True (@($tk[($i + 2)..($i + 5)]) -contains 'BoardCheck:off') 'ana ekran: klasik durum panosu panel sayfasında denetlenir'
    }
    if ($tk[$i] -eq 'Click:st_BoardEdit') {
        Assert-Eq $tk[$i + 1] 'HomeCheck:Pano' 'ana ekranı düzenle: panoya geçtiği doğrulanır'
        Assert-Eq $tk[$i + 2] 'BoardCheck:edit' 'ana ekranı düzenle: düzenleme kipi açık'
    }
}
Assert-Eq (@($tk | Where-Object { $_ -eq 'Click:st_BoardEdit' }).Count) $nd 'ana ekranı düzenle düğmesi her tasarımda bir kez'
Assert-Eq (@($tk | Where-Object { $_ -eq 'Click:st_BoardReset' }).Count) $nd 'düzeni sıfırla düğmesi her tasarımda bir kez'
Assert-Eq (@($tk | Where-Object { $_ -eq 'BoardLayoutMenu:' }).Count) $nd 'hazır düzen menüsü her tasarımda bir kez'
Assert-Eq (@($tk | Where-Object { $_ -eq 'BoardPreset:Klasik' }).Count) $nd 'Klasik hazır düzeni her tasarımda bir kez uygulanır'
foreach ($bp in @('BoardPreset:Klasik')) { $pk = $bp.Split(':')[1]; Assert-True ($script:BoardPresetInfo.Contains($pk)) "hazır düzen adı pano tablosunda: $pk" }
# tasarım ayrıntıları
$ovs = @($script:SmokeOverrides)
foreach ($ov in $ovs) {
    $prop = [string]$ov[0]; $val = [string]$ov[1]
    Assert-True ($script:DsOptions.Contains($prop) -and $script:DsOptions[$prop].Contains($val) -and $val -ne 'Auto') "ayrıntı denemesi geçerli: $prop = $val"
    $si = [array]::IndexOf($tk, ('Select:st_Ds' + $prop + 'Sel|' + $val))
    Assert-True ($si -ge 0) "ayrıntı $prop = $val listeden seçilir"
    if ($si -ge 0) { Assert-Eq $tk[$si + 1] ('OverrideCheck:' + $prop + '|' + $val) "ayrıntı $prop = $val seçilince hemen doğrulanır" }
}
$ocs = @($tas | Where-Object { $_.Kind -eq 'OverrideCheck' } | ForEach-Object { $_.Arg })
Assert-Eq $ocs.Count ($ovs.Count + 5 + 2) 'ayrıntı doğrulamaları: denemeler + Morpheus tersi (5) + iki sıfırlama'
Assert-Eq (@($ocs | Where-Object { $_ -eq 'Reset' }).Count) 2 'ayrıntıları sıfırlama iki kez doğrulanır (düğme ve tasarım değişimi)'
foreach ($pr in @($script:DsOptions.Keys)) {
    foreach ($vk in @($script:DsOptions[$pr].Keys)) {
        if ($vk -eq 'Auto') { continue }
        Assert-True (@($ocs | Where-Object { $_ -eq ($pr + '|' + $vk) }).Count -ge 1) "her ayrıntı seçeneği denenir: $pr = $vk"
    }
}
Assert-True ($tk -contains 'Click:st_DsReset') 'ayrıntıları sıfırla düğmesi denenir'
Assert-True ($tk -contains 'Check:st_DsAdv|on' -and $tk -contains 'Check:st_DsAdv|off') 'ayrıntı paneli açılır ve kapanır'
# hazır görünümler
Assert-Eq ($script:SmokePresets -join ',') 'Atolye,Sifir,Morpheus,Komuta,Varsayilan' 'duman: hazır görünüm sırası'
foreach ($pr in $script:SmokePresets) {
    Assert-True ($script:LookPresetNames.Contains($pr)) "hazır görünüm tabloda: $pr"
    $si = [array]::IndexOf($tk, ('Select:st_LookSel|' + $pr))
    Assert-True ($si -ge 0) "hazır görünüm $pr listeden seçilir"
    if ($si -ge 0) { Assert-Eq $tk[$si + 1] ('PresetCheck:' + $pr) "hazır görünüm $pr seçilince hemen doğrulanır" }
}
# açık liste görüntüleri
foreach ($cn in @('st_LookSel', 'st_ThemeSel', 'st_DesignSel', 'st_HomeSel')) {
    $oi = [array]::IndexOf($tk, ('DropDown:' + $cn + '|open'))
    Assert-True ($oi -ge 1) "açılır liste $cn açılır"
    if ($oi -ge 1) {
        Assert-Eq $tk[$oi - 1] ('Reveal:' + $cn) "açılır liste $cn önce görünür yapılır"
        Assert-Eq $tk[$oi + 1] ('DropDownCheck:' + $cn) "açılır liste $cn açılınca doğrulanır"
        Assert-Eq $tk[$oi + 2] ('PopupWheel:' + $cn) "açılır liste $cn açıkken tekerlek sınanır (arkadaki sayfa kıpırdamaz)"
        Assert-Eq $tk[$oi + 3] ('Screen:liste-' + $cn) "açılır liste $cn açıkken gerçek görüntü alınır"
        Assert-Eq $tk[$oi + 4] ('DropDown:' + $cn + '|close') "açılır liste $cn kapatılır"
    }
}
Assert-Eq @(Get-AstFunctions | Where-Object { $_.Name -eq 'Test-SmokePopupWheel' }).Count 1 'duman: açık liste tekerlek denemesi tanımlı'
Assert-Eq @($say | Where-Object { $_.Kind -eq 'PopupWheel' -and $_.Arg -eq 'st_BackdropSel' }).Count 1 'saydamlık kapsamı: saydamlık listesi açıkken tekerlek denenir'
# kuyruk güvenliği ve geçerliliği: her kapsamda her adım bilinen bir türde, güvenli listelerde ve var olan seçeneklerle
$knownKinds = New-Object System.Collections.ArrayList
foreach ($fnn in @('Invoke-SmokeStep', 'Invoke-SmokeStepLook')) {
    $ft = (@(Get-AstFunctions | Where-Object { $_.Name -eq $fnn }) | Select-Object -Last 1).Extent.Text
    foreach ($m in [regex]::Matches($ft, "(?m)^\s{8}'([A-Za-z]+)'\s*\{")) { [void]$knownKinds.Add($m.Groups[1].Value) }
}
Assert-True ($knownKinds.Count -gt 30) ("adım türleri kaynaktan okundu (" + $knownKinds.Count + ")")
$optKeys = @{
    st_DesignSel = @($script:DesignInfo.Keys); st_HomeSel = @($script:HomeInfo.Keys); st_ThemeSel = @(@('Sistem') + @($script:Themes.Keys)); st_LayoutSel = @($script:LayoutInfo.Keys)
    st_ZoomSel = @($script:ZoomSteps | ForEach-Object { [string]$_ }); st_BackdropSel = @($script:GlassInfo.Keys); st_OpacitySel = @($script:GlassSteps | ForEach-Object { [string]$_ })
    st_LookSel = @($script:LookPresetNames.Keys)
}
foreach ($pr in @($script:DsOptions.Keys)) { $optKeys[('st_Ds' + $pr + 'Sel')] = @($script:DsOptions[$pr].Keys) }
$srcAll = [System.IO.File]::ReadAllText($script:TestPath)
foreach ($sc in @('tam', 'tepsi', 'gorunum', 'tasarim', 'saydam', 'dil', 'ust')) {
    $qq = @((New-SmokeQueue 'Neon' $sk { param($k) @() } 'Ayrintili' $sc).ToArray())
    $badKind = 0; $badClick = 0; $badSel = 0; $badOpt = 0; $badName = 0; $badChk = 0; $badArg = 0; $badWait = 0
    foreach ($st in $qq) {
        $kd = [string]$st.Kind; $ar = [string]$st.Arg
        if ($knownKinds -notcontains $kd) { $badKind++; Write-Host ("  bilinmeyen tur: " + $kd + " (" + $sc + ")") }
        if ([int]$st.Wait -lt 0 -or [int]$st.Wait -gt 5000) { $badWait++ }
        if ($kd -eq 'Click') {
            if ($script:SmokeSafe -notcontains $ar) { $badClick++; Write-Host ('  guvensiz dugme: ' + $ar) }
            if (-not $srcAll.Contains('x:Name="' + $ar + '"')) { $badName++; Write-Host ('  XAML adi yok: ' + $ar) }
        }
        if ($kd -eq 'Select') {
            $p2 = $ar.Split('|')
            if ($script:SmokeSafeSelect -notcontains $p2[0]) { $badSel++; Write-Host ('  guvensiz liste: ' + $p2[0]) }
            if (-not $srcAll.Contains('x:Name="' + $p2[0] + '"')) { $badName++; Write-Host ('  XAML adi yok: ' + $p2[0]) }
            if (-not $optKeys.ContainsKey($p2[0]) -or @($optKeys[$p2[0]]) -notcontains $p2[1]) { $badOpt++; Write-Host ('  secenek yok: ' + $ar) }
        }
        if ($kd -eq 'DropDown' -or $kd -eq 'Reveal' -or $kd -eq 'DropDownCheck' -or $kd -eq 'PopupWheel') {
            $nm = $ar.Split('|')[0]
            if ($script:SmokeSafeSelect -notcontains $nm -or -not $srcAll.Contains('x:Name="' + $nm + '"')) { $badName++; Write-Host ('  liste adi yok: ' + $nm) }
        }
        if ($kd -eq 'Check') {
            $p2 = $ar.Split('|')
            if ($script:SmokeSafeCheck -notcontains $p2[0] -or -not $srcAll.Contains('x:Name="' + $p2[0] + '"') -or @('on', 'off') -notcontains $p2[1]) { $badChk++ }
        }
        if ($kd -eq 'HomeCheck' -and @('Pano', 'Klasik') -notcontains $ar) { $badArg++ }
        if ($kd -eq 'BoardCheck' -and @('off', 'home', 'edit', 'added', 'removed', 'reset') -notcontains $ar) { $badArg++ }
        if ($kd -eq 'DesignCheck' -and -not $script:DesignInfo.Contains($ar)) { $badArg++ }
        if ($kd -eq 'PresetCheck' -and -not $script:LookPresetNames.Contains($ar)) { $badArg++ }
        if ($kd -eq 'OverrideCheck' -and $ar -ne 'Reset') {
            $p2 = $ar.Split('|')
            if (-not $script:DsOptions.Contains($p2[0]) -or -not $script:DsOptions[$p2[0]].Contains($p2[1])) { $badArg++ }
        }
        if ($kd -eq 'GlassCheck') {
            $p2 = $ar.Split('|')
            if (-not $script:GlassInfo.Contains($p2[0]) -or ($p2[1] -ne '*' -and @($script:GlassSteps) -notcontains [int]$p2[1])) { $badArg++ }
        }
        if ($kd -eq 'BoardPreset' -and -not $script:BoardPresetInfo.Contains($ar)) { $badArg++ }
    }
    Assert-Eq $badKind 0 "$sc kuyruğu: tüm adım türleri işleyicide tanımlı"
    Assert-Eq $badClick 0 "$sc kuyruğu: tüm tıklamalar güvenli düğme listesinde"
    Assert-Eq $badSel 0 "$sc kuyruğu: tüm liste seçimleri güvenli liste kümesinde"
    Assert-Eq $badOpt 0 "$sc kuyruğu: seçilen seçenekler gerçekten var"
    Assert-Eq $badName 0 "$sc kuyruğu: kullanılan denetim adları arayüzde tanımlı"
    Assert-Eq $badChk 0 "$sc kuyruğu: onay kutusu adımları güvenli ve geçerli"
    Assert-Eq $badArg 0 "$sc kuyruğu: doğrulama adımlarının bağımsız değişkenleri geçerli"
    Assert-Eq $badWait 0 "$sc kuyruğu: adım beklemeleri makul"
    $sw = 0.0
    foreach ($st in $qq) { $sw += [double]$st.Wait / 1000.0 }
    Write-Host ("  " + $sc + " kuyruğu: " + $qq.Count + " adım, beklemeler toplamı " + [string][int]$sw + " sn")
}

# ======================= 7) derlenmiş dosyada bağlantılar =======================
$text = [System.IO.File]::ReadAllText($script:TestPath)
$sf = @(Get-AstFunctions | Where-Object { $_.Name -eq 'Complete-SmokeRun' }) | Select-Object -Last 1
$ct = ''
if ($null -ne $sf) { $ct = [string]$sf.Extent.Text }
Assert-True ($ct.Contains('Stop-SmokeLook')) 'Complete-SmokeRun: bitişte fare düğmesi ve renkli zemin temizlenir'
Assert-True ($ct.IndexOf('Stop-SmokeLook') -lt $ct.IndexOf('Set-AppTheme')) 'Complete-SmokeRun: temizlik temayı geri yüklemeden önce'
$ssf = @(Get-AstFunctions | Where-Object { $_.Name -eq 'Save-SmokeScreen' }) | Select-Object -Last 1
$st2 = [string]$ssf.Extent.Text
Assert-True ($st2.Contains('Get-SmokeLeftMean $bmp') -and $st2.Contains("StartsWith('saydam-')") -and $st2.Contains('SmokeStatsOn')) 'Save-SmokeScreen: yalnızca renkli zemin açıkken ve saydam görüntülerde ortalama renk ölçülür'
$api = @(Get-AstFunctions | Where-Object { $_.Name -eq 'Get-SmokeInputApi' }) | Select-Object -Last 1
$at = [string]$api.Extent.Text
foreach ($fn in @('SetCursorPos', 'mouse_event', 'WindowFromPoint', 'GetAncestor')) { Assert-True ($at.Contains($fn)) ('fare girdisi türü ' + $fn + ' çağrısını tanımlar') }
Assert-Eq ([regex]::Matches($at, 'Add-Type')).Count 1 'fare girdisi türü tek Add-Type ile kurulur'
Assert-True ($at.Contains("-ErrorAction Stop") -and $at.Contains('catch { $script:SmokeInputApi = $null }')) 'fare girdisi türü kurulamazsa $null döner (adım hata verir, uygulama kapanmaz)'
$dragFns = @('Invoke-SmokeDrag', 'Get-SmokeDragPlan', 'Test-SmokeDragResult', 'Send-SmokeMouse', 'Test-SmokeWindowAt', 'Show-SmokeBackdrop')
foreach ($fn in $dragFns) { Assert-Eq @(Get-AstFunctions | Where-Object { $_.Name -eq $fn }).Count 1 ($fn + ' tek kez tanımlı') }
# fare girdisi yalnızca duman testi modülünde
$other = 0
foreach ($f in @(Get-AstFunctions)) {
    if ($f.Name -in @('Get-SmokeInputApi', 'Send-SmokeMouse', 'Test-SmokeWindowAt')) { continue }
    if ($f.Extent.Text -match 'mouse_event|SetCursorPos\s*\(') { $other++; Write-Host ('  baska islev: ' + $f.Name) }
}
Assert-Eq $other 0 'gerçek fare girdisi yalnızca duman testinin üç işlevinde'
$tt = $text
$rootCalls = ([regex]::Matches($tt, 'Send-SmokeMouse')).Count
Assert-True ($rootCalls -ge 5) 'Send-SmokeMouse duman testi kodunda kullanılıyor'
# Duman testi dışında bu işlevler çağrılmaz: normal açılış yolu Initialize-Smoke ile açılan kipte çalışır
$callers = @()
foreach ($f in @(Get-AstFunctions)) {
    if ($f.Extent.Text.Contains('Invoke-SmokeDrag') -and $f.Name -notin @('Invoke-SmokeDrag', 'Invoke-SmokeStepLook')) { $callers += $f.Name }
}
Assert-Eq ($callers -join ',') '' 'Invoke-SmokeDrag yalnızca duman adımı işleyicisinden çağrılır'

# ======================= 8) denetim işlevleri (sahte arayüzle) =======================
$script:StLoading = $false
$script:Win = [pscustomobject]@{}
Add-Member -InputObject $script:Win -MemberType ScriptMethod -Name UpdateLayout -Value { } | Out-Null
$script:CfgFake = @{}
function Get-Settings { return $script:CfgFake }
$script:DesignChecks = New-Object System.Collections.ArrayList
function Test-SmokeDesign([string]$Key) { [void]$script:DesignChecks.Add($Key) }
function Invoke-SmokeFlush { }
$script:ui = @{}
foreach ($n in @('st_LookSel', 'st_ThemeSel', 'st_LayoutSel', 'st_ZoomSel', 'st_DesignSel', 'st_HomeSel', 'st_BackdropSel', 'st_OpacitySel', 'st_DsNavSel', 'st_DsRadiusSel', 'st_DsFontSel', 'st_DsGraphSel', 'st_DsSkinSel')) { $script:ui[$n] = New-FakeCombo }
foreach ($n in @('st_ReduceMotion', 'st_Smooth', 'st_ToTop', 'st_FocusRing', 'st_DsAdv')) { $script:ui[$n] = [pscustomobject]@{ IsChecked = $false } }
foreach ($n in @('st_ThDesc', 'st_LyDesc', 'st_DsDesc', 'st_HomeDesc', 'st_BdDesc')) { $script:ui[$n] = [pscustomobject]@{ Text = '' } }
$ui = $script:ui
Initialize-StLookChoices; Initialize-StDesignChoices; Initialize-StGlassChoices
function Set-FakeState($St) { $script:Settings = $St; $script:CfgFake = $St.Clone(); Load-StLook; Load-StDesign; Load-StGlass }
function New-State([hashtable]$Over) {
    $h = @{ Theme = 'Koyu'; Layout = 'Kompakt'; Zoom = 110; Design = 'Morpheus'; HomeMode = 'Pano'; Backdrop = 'Yok'; WinOpacity = 100
            DsNav = 'Auto'; DsRadius = 'Auto'; DsFont = 'Auto'; DsGraph = 'Auto'; DsSkin = 'Auto'; ReduceMotion = $false; SmoothScroll = $true; ToTopButton = $true; FocusRing = $true }
    foreach ($k in @($Over.Keys)) { $h[$k] = $Over[$k] }
    return $h
}

$script:DesignKey = 'Morpheus'
Set-FakeState (New-State @{})
$prs = @(Get-SmokeComboPairs)
Assert-Eq $prs.Count 13 'liste çiftleri: on üç liste'
$map = @{}
foreach ($pp in $prs) { $map[[string]$pp[0]] = [string]$pp[1] }
Assert-Eq "$($map.st_ThemeSel)|$($map.st_LayoutSel)|$($map.st_ZoomSel)|$($map.st_DesignSel)|$($map.st_HomeSel)|$($map.st_BackdropSel)|$($map.st_OpacitySel)" 'Koyu|Kompakt|110|Morpheus|Pano|Yok|100' 'liste çiftleri: ayarlardan beklenen anahtarlar'
Assert-Eq "$($map.st_DsNavSel)|$($map.st_DsRadiusSel)|$($map.st_DsFontSel)|$($map.st_DsGraphSel)|$($map.st_DsSkinSel)" 'Auto|Auto|Auto|Auto|Auto' 'liste çiftleri: ayrıntılar tasarımın değerinde'
Assert-Eq $map.st_LookSel 'Ozel' 'liste çiftleri: hazır olmayan birleşim Özel'
Reset-Fake; Test-SmokeCombos
Assert-Eq $script:Errs.Count 0 'liste denetimi: tutarlı durumda hata yok'
Assert-True (Has-Line 'açılır listeler tutarlı') 'liste denetimi: özet satırı yazılır'
[void](Select-ComboKey $ui.st_ThemeSel 'Neon')
Reset-Fake; Test-SmokeCombos
Assert-Eq $script:Errs.Count 1 'liste denetimi: ayarla uyuşmayan seçim tek hata'
Assert-True ($script:Errs.Count -gt 0 -and $script:Errs[0] -like '*st_ThemeSel*Neon*') 'liste denetimi: hata listeyi ve seçili anahtarı söyler'
Set-FakeState (New-State @{})
$ui.st_DsNavSel.Items.Clear()
Reset-Fake; Test-SmokeCombos
Assert-True ($script:Errs.Count -ge 1 -and $script:Errs[0] -like '*st_DsNavSel*0 öğe*') 'liste denetimi: boş liste hata verir'
Initialize-StDesignChoices
Set-FakeState (New-State @{})
$keep = $script:ui['st_DsSkinSel']; $script:ui['st_DsSkinSel'] = $null
Reset-Fake; Test-SmokeCombos
Assert-True ($script:Errs.Count -ge 1 -and $script:Errs[0] -like '*açılır liste yok*st_DsSkinSel*') 'liste denetimi: olmayan liste hata verir'
$script:ui['st_DsSkinSel'] = $keep
Assert-True ($null -eq (Get-SmokeComboText ([pscustomobject]@{ IsVisible = $false }))) 'seçim kutusu yazısı: görünmeyen liste için boş döner (denetlenmez)'
Assert-Eq (Get-SmokeComboText ([pscustomobject]@{ IsVisible = $true; Template = $null })) '' 'seçim kutusu yazısı: şablon yoksa boş metin (hata yutulur)'

# ana ekran biçimi denetimi
Set-FakeState (New-State @{ HomeMode = 'Pano' })
Reset-Fake; Test-SmokeHome 'Pano'
Assert-Eq $script:Errs.Count 0 'ana ekran denetimi: Pano doğru durumda hata yok'
Reset-Fake; Test-SmokeHome 'Klasik'
Assert-True ($script:Errs.Count -ge 3) ('ana ekran denetimi: beklenenle uyuşmayan durumda hatalar (' + $script:Errs.Count + ')')
Assert-True (@($script:Errs | Where-Object { $_ -like 'ana ekran:*' }).Count -eq $script:Errs.Count) 'ana ekran denetimi: hatalar ana ekran başlığıyla'
Set-FakeState (New-State @{ HomeMode = 'Klasik' })
Reset-Fake; Test-SmokeHome 'Klasik'
Assert-Eq $script:Errs.Count 0 'ana ekran denetimi: Klasik doğru durumda hata yok'
Reset-Fake; Test-SmokeHome 'Pano'
Assert-True ($script:Errs.Count -ge 3) 'ana ekran denetimi: Klasik durumda Pano beklenirse hata'
$script:CfgFake = (New-State @{ HomeMode = 'Pano' })
Reset-Fake; Test-SmokeHome 'Klasik'
Assert-Eq $script:Errs.Count 1 'ana ekran denetimi: yalnızca dosya uyuşmuyorsa tek hata'
Assert-True ($script:Errs.Count -gt 0 -and $script:Errs[0] -like '*dosyadaki*') 'ana ekran denetimi: hata dosyayı söyler'

# tasarım ayrıntısı denetimi
$cases = @(
    @{ D = 'Klasik'; P = 'Nav'; V = 'Fly' }, @{ D = 'Klasik'; P = 'Nav'; V = 'Hidden' }, @{ D = 'Klasik'; P = 'Radius'; V = 'Pill' }, @{ D = 'Klasik'; P = 'Radius'; V = 'Sharp' },
    @{ D = 'Klasik'; P = 'Radius'; V = 'Soft' }, @{ D = 'Klasik'; P = 'Radius'; V = 'Round' }, @{ D = 'Klasik'; P = 'Font'; V = 'Mono' }, @{ D = 'Morpheus'; P = 'Font'; V = 'Sans' },
    @{ D = 'Klasik'; P = 'Graph'; V = 'scope' }, @{ D = 'Morpheus'; P = 'Graph'; V = 'area' }, @{ D = 'Klasik'; P = 'Skin'; V = 'Glass' }, @{ D = 'Morpheus'; P = 'Skin'; V = 'Plain' }
)
foreach ($cs in $cases) {
    $script:DesignKey = $cs.D
    $ov = @{ Design = $cs.D }
    $ov[('Ds' + $cs.P)] = $cs.V
    Set-FakeState (New-State $ov)
    $script:DesignChecks.Clear()
    Reset-Fake; Test-SmokeOverride ($cs.P + '|' + $cs.V)
    Assert-Eq $script:Errs.Count 0 ("ayrıntı denetimi: " + $cs.D + ' ' + $cs.P + ' = ' + $cs.V + ' doğru durumda hata yok')
    Assert-Eq ($script:DesignChecks -join ',') $cs.D ("ayrıntı denetimi: " + $cs.D + ' ' + $cs.P + ' sonrası tasarım denetimi de çalışır')
    # liste başka bir değer gösterirse yakalanır
    $other = [string](@($script:DsOptions[$cs.P].Keys) | Where-Object { $_ -ne $cs.V -and $_ -ne 'Auto' } | Select-Object -First 1)
    [void](Select-ComboKey $ui[('st_Ds' + $cs.P + 'Sel')] $other)
    Reset-Fake; Test-SmokeOverride ($cs.P + '|' + $cs.V)
    Assert-True ($script:Errs.Count -ge 1) ("ayrıntı denetimi: " + $cs.P + ' listesi başka değer gösterirse hata')
}
# ayrıntı seçilmişken hazır görünüm listesi Özel göstermezse hata
$script:DesignKey = 'Klasik'
Set-FakeState (New-State @{ Design = 'Klasik'; Theme = 'Neon'; Layout = 'Ayrintili'; Zoom = 100; DsNav = 'Fly' })
[void](Select-ComboKey $ui.st_LookSel 'Varsayilan')
Reset-Fake; Test-SmokeOverride 'Nav|Fly'
Assert-True ($script:Errs.Count -eq 1 -and $script:Errs[0] -like '*Özel*') 'ayrıntı denetimi: hazır görünüm listesi Özel göstermeli'
# etkin tasarım ayrıntıyı yansıtmıyorsa (bellek başka) hata
Set-FakeState (New-State @{ Design = 'Klasik'; DsNav = 'Rail' })
Reset-Fake; Test-SmokeOverride 'Nav|Fly'
Assert-True ($script:Errs.Count -ge 2) 'ayrıntı denetimi: bellek, liste ve etkin tasarım uyuşmazlığı birlikte yakalanır'
# sıfırlama denetimi
Set-FakeState (New-State @{ Design = 'Klasik' })
Reset-Fake; Test-SmokeOverride 'Reset'
Assert-Eq $script:Errs.Count 0 'sıfırlama denetimi: hepsi Auto iken hata yok'
Set-FakeState (New-State @{ Design = 'Klasik'; DsNav = 'Fly'; DsSkin = 'Glass' })
Reset-Fake; Test-SmokeOverride 'Reset'
Assert-True ($script:Errs.Count -ge 4) ('sıfırlama denetimi: ayrıntı kalmışsa hatalar (' + $script:Errs.Count + ')')
Assert-True (@($script:Errs | Where-Object { $_ -like '*hâlâ ayrıntı seçilmiş*' }).Count -eq 1) 'sıfırlama denetimi: genel uyarı bir kez'
$script:DesignKey = 'Klasik'

# ---------------- erişilebilirlik ölçümü (p84): saf işlevler ve rapor ----------------
Import-Fn 'ConvertTo-TouchKey', 'Get-TouchMode', 'Get-TouchMin', 'Protect-A11yText', 'Test-A11yNameMismatch', 'Test-A11yNameBad', 'Get-A11yContextKey', 'Get-A11yKindCounts', 'Add-SmokeA11yFail', 'Write-SmokeA11yReport'
Assert-True (Test-A11yNameBad '') 'erişim: boş ad kötü'
Assert-True (Test-A11yNameBad '   ') 'erişim: yalnızca boşluk kötü'
Assert-True (Test-A11yNameBad ([string][char]0xE713)) 'erişim: yalnızca simge karakteri kötü'
Assert-True (Test-A11yNameBad ([string][char]0x00D7)) 'erişim: yalnızca çarpı işareti kötü'
Assert-True (Test-A11yNameBad '...') 'erişim: yalnızca noktalama kötü'
Assert-True (-not (Test-A11yNameBad ([string][char]0xE713 + ' Ayarlar'))) 'erişim: simge + yazı iyi'
Assert-True (-not (Test-A11yNameBad 'Uygula')) 'erişim: düz yazı iyi'
Assert-True (-not (Test-A11yNameBad '5')) 'erişim: rakam iyi'
Assert-Eq (Get-A11yContextKey 'Neon-home') 'home' 'erişim: tema öneki atılır'
Assert-Eq (Get-A11yContextKey 'Koyu-settings-st_General') 'settings-st_General' 'erişim: sekme görünümü tema öneksiz'
Assert-Eq (Get-A11yContextKey 'yerlesim-Kompakt-panel') 'yerlesim-Kompakt-panel' 'erişim: yerleşim görünümü ayrı kalır'
Assert-Eq (Get-A11yContextKey 'kullanim-asistan') 'kullanim-asistan' 'erişim: tema olmayan önek kalır'
Assert-Eq (Get-A11yKindCounts @{ 'Button a "x"' = 1; 'Button b "y"' = 1; 'ComboBox c ""' = 1 }) ' (Button 2, ComboBox 1)' 'erişim: türlere göre sayım'
Assert-Eq (Get-A11yKindCounts @{}) '' 'erişim: boş sayım'
$script:Lines.Clear()
$script:SmokeA11y = $null
Write-SmokeA11yReport
Assert-Eq $script:Lines.Count 0 'erişim: ölçüm yoksa rapor yazılmaz'
$script:SmokeA11yFails = 0
$script:SmokeA11y = @{ Runs = 2; Seen = @{ 'Button Kok "Uygula"' = 'home'; 'CheckBox Kart "Aç"' = 'home'; 'ComboBox st_LookSel ""' = 'settings' }
    NoName = @{ 'ComboBox st_LookSel ""' = 'settings' }; Small24 = @{ 'CheckBox Kart "Aç"' = 'home 18x18' }; Small32 = @{}; Ctx = @{}; Kinds = @{ Button = 1; CheckBox = 1; ComboBox = 1 }; Ms = 12 }
$ap = Join-Path ([System.IO.Path]::GetTempPath()) 'Multimizer-duman-erisim.txt'
Remove-Item -LiteralPath $ap -Force -ErrorAction SilentlyContinue
Write-SmokeA11yReport
Assert-True ($script:Lines.Count -ge 4) ('erişim: özet satırları (' + $script:Lines.Count + ')')
Assert-True ([string]$script:Lines[0] -like '*2 görünümde 3 denetim öğesi (Button 1, CheckBox 1, ComboBox 1)*') ('erişim: özet: ' + [string]$script:Lines[0])
Assert-True ([string]$script:Lines[1] -like '*yalnızca simge: 1 (ComboBox 1)') ('erişim: adsız: ' + [string]$script:Lines[1])
Assert-True ([string]$script:Lines[2] -like '*24 px altı: 1 (CheckBox 1); 24-32 px arası: 0') ('erişim: küçük: ' + [string]$script:Lines[2])
Assert-True (Test-Path -LiteralPath $ap) 'erişim: ayrıntı dosyası yazıldı'
$at = [System.IO.File]::ReadAllText($ap)
Assert-True ($at.Contains('] 1') -and $at.Contains('[ADSIZ') -and $at.Contains('ComboBox st_LookSel ""  |  settings')) 'erişim: ayrıntıda adsız öğe ve görünümü'
Assert-True ($at.Contains('[24 PX ALTI] 1') -and $at.Contains('CheckBox Kart "Aç"  |  home 18x18')) 'erişim: ayrıntıda küçük öğe ve ölçüsü'
Remove-Item -LiteralPath $ap -Force -ErrorAction SilentlyContinue
$script:Lines.Clear()
Add-SmokeA11yFail 'deneme'
Add-SmokeA11yFail 'deneme 2'
Assert-Eq $script:Lines.Count 1 'erişim: ölçüm hatası bir kez yazılır'
Assert-Eq ([int]$script:SmokeA11yFails) 2 'erişim: ölçüm hataları sayılır'
$script:SmokeA11y = $null
$script:SmokeA11yFails = 0

function Get-A11yFnText([string]$Name) {
    $f = @(Get-AstFunctions | Where-Object { ($_.Name -replace '^global:', '') -eq $Name }) | Select-Object -Last 1
    if ($null -eq $f) { return '' }
    return [string]$f.Extent.Text
}
# ---------------- G-04: verilen ekran okuyucu adlarının doğruluğu (p90) ----------------
Assert-True (-not (Test-A11yNameMismatch 'Uygula' 'Uygula')) 'ad doğruluğu: aynı yazı örtüşür'
Assert-True (-not (Test-A11yNameMismatch 'uygula' 'UYGULA')) 'ad doğruluğu: büyük küçük harf önemsiz'
Assert-True (-not (Test-A11yNameMismatch 'Ayarlar' ([string][char]0xE713 + ' Ayarlar'))) 'ad doğruluğu: ad yazıyı içerir'
Assert-True (-not (Test-A11yNameMismatch 'Pil ve güç ayarlarını aç ve kapat, ...' 'Pil ve güç')) 'ad doğruluğu: yazı adı içerir'
Assert-True (-not (Test-A11yNameMismatch 'ipucu: Yenile' 'Yenile')) 'ad doğruluğu: ipucu öneki atılır'
Assert-True (-not (Test-A11yNameMismatch 'Uzun bir açıklama metni burada...' 'Uzun bir açıklama metni burada ve devamı')) 'ad doğruluğu: kısaltma noktaları atılır'
Assert-True (-not (Test-A11yNameMismatch 'Aç' 'Aç, CompactOS')) 'ad doğruluğu: "düğme, satır başlığı" biçimi yazıyla tutarlı sayılır (gerçek ölçüm 26.11.2026)'
Assert-True (-not (Test-A11yNameMismatch '' 'Herhangi')) 'ad doğruluğu: görünen yazı yoksa sorun sayılmaz'
Assert-True (-not (Test-A11yNameMismatch 'Uygula' '')) 'ad doğruluğu: ad boşsa ayrı sayılır (adsız bölümü)'
Assert-True (Test-A11yNameMismatch 'Gece ışığı' 'Otomatik başlat') 'ad doğruluğu: başka öğenin yazısını alan ad yakalanır'
Assert-True (Test-A11yNameMismatch 'Aç' 'Kapat') 'ad doğruluğu: kısa yazı tam eşleşme ister'
Assert-True (-not (Test-A11yNameMismatch 'Aç' 'Aç')) 'ad doğruluğu: kısa yazı eşitse tutarlı'
Assert-True (Test-A11yNameMismatch 'Uygula' 'Ok') 'ad doğruluğu: kısa ad her yazıyı içerir sayılmaz'
$ipRaw = '192.168.1.20'
$ipv6 = 'fe80::1a2b:3c4d:5e6f:7a8b'
$mail = 'ad.soyad@example.com'
$yol = 'C:\Users\Ayse\Belgeler'
$kor = Protect-A11yText ('Wi-Fi ' + $ipRaw + ' ' + $ipv6 + ' ' + $mail + ' ' + $yol)
Assert-True (-not $kor.Contains($ipRaw) -and -not $kor.Contains('fe80') -and -not $kor.Contains('@') -and -not $kor.Contains('Ayse')) ('kişisel veri süzgeci: IP, IPv6, e-posta, kullanıcı adı gizlenir: ' + $kor)
Assert-Eq (Protect-A11yText 'Uygula 24 px 12:30') 'Uygula 24 px 12:30' 'kişisel veri süzgeci: sıradan yazıya dokunmaz'
$script:Lines.Clear()
$script:SmokeA11y = @{ Runs = 2; Seen = @{ 'CheckBox Kart "Gece ışığı"' = 'home'; 'Button Kok "Uygula"' = 'home' }
    NoName = @{}; Small24 = @{}; Small32 = @{}; Ctx = @{}; Kinds = @{ Button = 1; CheckBox = 1 }; Ms = 5
    Named = @{ 'CheckBox Kart "Gece ışığı"' = '-> "Otomatik başlat" [home]'; 'Button Kok "Uygula"' = '-> "Uygula" [home]'; 'Button Ag "Bağlan 10.20.30.40"' = '-> "Bağlan 10.20.30.40" [home]' }
    Mis = @{ 'CheckBox Kart "Gece ışığı"' = '-> "Otomatik başlat" [home]' }
    Dup = @{ 'home Button "Kaldır"' = @{ N = 3; Anchors = @{ RowA = $true; RowB = $true } }; 'home Button "Uygula"' = @{ N = 1; Anchors = @{ Kok = $true } } } }
Write-SmokeA11yReport
Assert-True (Has-Line 'verilen ad listesi: 3 denetim; ad yazıyla örtüşmeyen: 1; aynı görünümde aynı ad: 1') ('ad doğruluğu: özet satırı: ' + (@($script:Lines) -join ' / '))
$at = [System.IO.File]::ReadAllText($ap)
Assert-True ($at.Contains('[AD GÖRÜNEN YAZIYLA ÖRTÜŞMÜYOR') -and $at.Contains('CheckBox Kart "Gece ışığı"  |  -> "Otomatik başlat" [home]')) 'ad doğruluğu: ayrıntıda örtüşmeyen ad'
Assert-True ($at.Contains('home Button "Kaldır"  |  3 denetim, 2 ayrı çapa: RowA, RowB')) 'ad doğruluğu: ayrıntıda yinelenen ad'
Assert-True (-not $at.Contains('home Button "Uygula"  |  1 denetim')) 'ad doğruluğu: tek örnek yinelenen sayılmaz'
Assert-True (-not $at.Contains('10.20.30.40') -and $at.Contains('Bağlan <gizli>')) 'kişisel veri süzgeci: rapor dosyasında IP yok'
Assert-True ($at.Contains('[VERİLEN ADLAR') -and $at.Contains('Button Kok "Uygula"  |  -> "Uygula" [home]')) 'ad doğruluğu: ayrıntıda verilen adlar listesi'
Remove-Item -LiteralPath $ap -Force -ErrorAction SilentlyContinue
$mf = Get-A11yFnText 'Measure-SmokeA11y'
Assert-True ($mf.Contains('Test-A11yNameMismatch') -and $mf.Contains('A.Dup[$dk]') -and $mf.Contains('A.Named[$key]')) 'ad doğruluğu: ölçüm adları, tutarsızlığı ve yinelenenleri toplar'
$script:Lines.Clear()
$script:SmokeA11y = $null

# ---------------- G-04: yinelenen adlar baglamla ayirt edilir (p91) ----------------
# Gerçek bilgisayarda bulundu (26.11.2026, duman ölçümü): 303 denetimde 40 ad aynı görünümde tekrar ediyordu (satır düğmeleri
# "Önizle"/"Düzelt"/"Aç", aynı başlıklı satır onay kutuları, kenar çubuğu "Temizlik" ile ilk sekme "Temizlik", iki "Durdur").
$ctxFn = Get-A11yFnText 'Set-A11yContextName'
Assert-True ($ctxFn.Contains("'BtnCancel'") -and $ctxFn.Contains("'sekme'") -and $ctxFn.Contains("'Ttl'") -and $ctxFn.Contains("'Det'")) 'erişim yinelenen: iş durdurma, sekme, satır başlığı ve ayrıntısı kuralları'
Assert-True ($ctxFn.Contains("'{0}, {1}'")) 'erişim yinelenen: satır düğmesi ve onay kutusu adı "yazı, satır başlığı" biçimli'
Assert-True ((Get-A11yFnText 'Test-A11yContextTarget').Contains("'Act2'") -and (Get-A11yFnText 'Test-A11yContextTarget').Contains('_Tab_') -and (Get-A11yFnText 'Test-A11yContextTarget').Contains("'Chk'")) 'erişim yinelenen: bağlam hedefleri Act, Act2, sekme ve Chk'
Assert-True ((Get-A11yFnText 'Find-A11yRowText').Contains('$hits.Count -eq 1') -and (Get-A11yFnText 'Find-A11yRowText').Contains('$hits.Count -gt 1')) 'erişim yinelenen: satır yazısı yalnızca tek eşleşmede alınır'
Assert-True ((Get-A11yFnText 'Test-A11yContextTarget').Contains("'Fx'") -and (Get-A11yFnText 'Test-A11yContextTarget').Contains('-cmatch')) 'erişim yinelenen: Düzelt (Fx) bağlam hedefi; sekme adı büyük/küçük harf duyarlı eşleşir (Türkçe I tuzağı)'
Assert-True ((Get-A11yFnText 'Find-A11yRowText').Contains('if ($stack.Count -gt 0) { return $null }')) 'erişim yinelenen: tarama sınıra takılırsa satır yazısı belirsiz sayılır'
Assert-True ($ctxFn.Contains('Test-A11yNameBad ([string]$El.Content)') -and $ctxFn.Contains('IsNullOrEmpty([string]$tt.Text)')) 'erişim yinelenen: boş ya da yalnızca simge içerik ve boş başlık ad olarak kullanılmaz'
# ---------------- G-05 koşusu: ölçüm sınırı genişleyince çıkan adsız ve tekrarlı adlar (p93, gerçek bilgisayar 27.11.2026) ----------------
$scf = Get-A11yFnText 'Show-Choice'
Assert-True ($scf.Contains('AutomationProperties]::SetName($b, (Tr ([string]$o.Title)))') -and $scf.Contains('AutomationProperties]::SetHelpText($b, (Tr ([string]$o.Detail)))')) 'erişim p93: seçim kutusu düğmeleri başlık ve ayrıntıyı çevrilmiş ad ve yardım metni olarak alır'
$ittf = Get-A11yFnText 'Initialize-TileTexts'
Assert-True ($ittf.Contains("ContainsKey('Del')") -and $ittf.Contains('AutomationProperties]::SetName($n.Del,') -and $ittf.Contains('$title')) 'erişim p93: parçayı kaldır düğmesinin adı parça başlığını içerir'
Import-Var 'A11yNameMap'
Assert-True ($script:A11yNameMap.ContainsKey('AskInput')) 'erişim p93: Asistan giriş kutusunun adı eşlemede'
# G-11 (p95): Diskler sekmesinde her sürücü kartındaki aynı satır düğmeleri sürücü harfiyle ayrılır (gerçek bilgisayar 27.11.2026: 3 sürücüde 3 aynı ad)
$rsd = Get-A11yFnText 'Render-SlDisk'
Assert-True ($rsd.Contains('SetName($row.FindName(''Act''), (Tr $b1)') -and $rsd.Contains('SetName($a2, (Tr $b2)') -and ([regex]::Matches($rsd, [regex]::Escape('[string]$disk.Drive)'))).Count -ge 2) 'erişim p95: disk satırı düğmelerinin adı sürücü harfini içerir'
# G-04 masa başı gezinme (p96): "Değiştir..." düğmesi bağlamsız okunuyordu
Assert-True ((Get-A11yFnText 'Load-StExtra').Contains('SetName($ui.st_UseCase, (Tr')) 'erişim p96: Kullanım türü Değiştir düğmesinin adı bağlamlı'
$qf = Get-A11yFnText 'Invoke-A11yQueue'
Assert-True ($qf.Contains('ElapsedMilliseconds -gt 40') -and $qf.Contains('$All') -and $qf.Contains('BeginInvoke')) 'erişim yinelenen: kuyruk işi 40 ms bütçeli, kalanı sonraki Background turuna bırakır'
Assert-True ((Get-A11yFnText 'Measure-SmokeA11y').Contains('Invoke-A11yQueue $true')) 'erişim ölçümü: ölçümden önce kuyruk tamamen boşaltılır'
Assert-True ($srcAll.Contains('<TextBlock x:Name="Ttl" Text="@@Title@@" Style="{DynamicResource TxtBody}" FontWeight="SemiBold" TextWrapping="Wrap"/>')) 'erişim yinelenen: bulgu satırı şablonunda başlık adlı'
$tc = Get-A11yFnText 'Get-A11yTitleCount'
Assert-True ($tc.Contains('A11yTitleCache') -and $tc.Contains('Children.Count') -and $tc.Contains("'Ttl'")) 'erişim yinelenen: aynı başlıklı satır sayısı panel başına önbellekli sayılır'
Assert-True ($ctxFn.Contains('Get-A11yTitleCount') -and $ctxFn.Contains("'{0}, {1}, {2}'")) 'erişim yinelenen: başlığı tekrar eden satırlarda düğme adına ayrıntı da eklenir (gerçek ölçüm: iki "Python Launcher" satırı)'
Assert-True ((Get-A11yFnText 'Invoke-A11yQueue').Contains('A11yTitleCache.Clear()')) 'erişim yinelenen: kuyruk bitince başlık önbelleği silinir (satırlar yenilenebilir)'
Assert-True ((Get-A11yFnText 'Add-A11yCandidate').Contains('Test-A11yContextTarget')) 'erişim yinelenen: düz yazılı satır düğmeleri de kuyruğa alınır'
Assert-True ((Get-A11yFnText 'Set-A11yName').Contains('Set-A11yContextName')) 'erişim yinelenen: ad verirken önce bağlam adı denenir'
Assert-True ((Get-A11yFnText 'Set-A11yJoinBinding').Contains('MultiBinding') -and (Get-A11yFnText 'Set-A11yJoinBinding').Contains('StringFormat')) 'erişim yinelenen: iki kaynaklı bağlama dil değişince güncellenir'

# ---------------- G-05: dokunma hedefleri (p92) ----------------
Import-Var 'SmokeSafeSelect', 'SmokeA11yMax', 'SmokeA11yMaxLarge', 'TouchKeys'
# Gerçek bilgisayarda (25.11.2026) duman ölçümü: 24 px altında 70, 24-32 px arasında 183 hedef; bilgisayar dokunmatik ekranlı.
Assert-Eq (ConvertTo-TouchKey 'Large') 'Large' 'dokunma: Large geçerli'
Assert-Eq (ConvertTo-TouchKey 'Normal') 'Normal' 'dokunma: Normal geçerli'
Assert-Eq (ConvertTo-TouchKey 'Auto') 'Auto' 'dokunma: Auto geçerli'
Assert-Eq (ConvertTo-TouchKey 'large') 'Auto' 'dokunma: büyük/küçük harf duyarlı (geçersiz → Otomatik)'
Assert-Eq (ConvertTo-TouchKey $null) 'Auto' 'dokunma: boş ayar Otomatik'
Assert-Eq (ConvertTo-TouchKey 'Buyuk') 'Auto' 'dokunma: bilinmeyen değer Otomatik'
Assert-Eq (Get-TouchMode 'Auto' $true) 'Large' 'dokunma: Otomatik + dokunmatik ekran = Büyük'
Assert-Eq (Get-TouchMode 'Auto' $false) 'Normal' 'dokunma: Otomatik + dokunmatik ekran yok = Normal (görünüm değişmez)'
Assert-Eq (Get-TouchMode 'Normal' $true) 'Normal' 'dokunma: Normal seçiliyse dokunmatik ekran olsa da Normal'
Assert-Eq (Get-TouchMode 'Large' $false) 'Large' 'dokunma: Büyük seçiliyse dokunmatik ekran olmasa da Büyük'
Assert-Eq (Get-TouchMin 'Normal' 'Ayrintili') 24.0 'dokunma: Normal alt sınır 24 px (p88)'
Assert-Eq (Get-TouchMin 'Normal' 'Kompakt') 24.0 'dokunma: Normal kipte Kompakt yerleşim değişmez'
Assert-Eq (Get-TouchMin 'Large' 'Ayrintili') 40.0 'dokunma: Büyük 40 px'
Assert-Eq (Get-TouchMin 'Large' 'Sade') 40.0 'dokunma: Büyük Sade yerleşimde 40 px'
Assert-Eq (Get-TouchMin 'Large' 'Kompakt') 32.0 'dokunma: Büyük Kompakt yerleşimde 32 px'
$srcT = [System.IO.File]::ReadAllText($script:TestPath)
Assert-True ($srcT.Contains("        TouchTargets = 'Auto'")) 'dokunma: ayar varsayılanı Otomatik'
Assert-True (([regex]::Matches($srcT, 'MinHeight" Value="\{DynamicResource TouchMin\}"')).Count -eq 3) 'dokunma: sekme, onay kutusu ve anahtar alt sınırı kaynaktan (3 stil)'
Assert-True (-not $srcT.Contains('<Setter Property="MinHeight" Value="24"/>')) 'dokunma: sabit 24 px alt sınır kalmadı'
Assert-True ($srcT -match '<Style x:Key="BtnBase" TargetType="Button">\r?\n  <Setter Property="MinHeight" Value="\{DynamicResource TouchBtnMin\}"/>') 'dokunma: düğme alt sınırı BtnBase üzerinden (türeyen tüm düğmeler)'
Assert-True ($srcT.Contains('<Setter Property="MinWidth" Value="{DynamicResource TouchBtnMin}"/>')) 'dokunma: simge düğmesi alt genişliği'
Assert-True (([regex]::Matches($srcT, 'MinWidth" Value="\{DynamicResource TouchMin\}"')).Count -eq 3) 'dokunma: sekme, onay kutusu ve anahtar alt genişliği (dar satır onay kutusu, kısa sekme)'
Assert-True ($srcT -match '<Style x:Key="BtnTitle" TargetType="Button">\r?\n  <Setter Property="MinWidth" Value="\{DynamicResource TouchBtnMin\}"/>') 'dokunma: başlık çubuğu düğmeleri (sabit 38 px genişlik)'
Assert-True ($srcT -match '<Style x:Key="BtnBrand" TargetType="Button">\r?\n  <Setter Property="MinHeight" Value="\{DynamicResource TouchBtnMin\}"/>') 'dokunma: marka düğmesi'
Assert-True ($srcT -match '<Style x:Key="BtnBase" TargetType="Button">\r?\n  <Setter Property="MinHeight" Value="\{DynamicResource TouchBtnMin\}"/>\r?\n  <Setter Property="MinWidth" Value="\{DynamicResource TouchBtnMin\}"/>') 'dokunma: düğme alt genişliği (dar değer seçici okları)'
Assert-True ($srcT -match '<Style x:Key="BtnLangCap" TargetType="Button">\r?\n  <Setter Property="MinHeight" Value="\{DynamicResource TouchBtnMin\}"/>\r?\n  <Setter Property="MinWidth" Value="\{DynamicResource TouchBtnMin\}"/>') 'dokunma: üst çubuk dil ve asistan düğmesi'
Assert-True ($srcT.Contains('<sys:Double x:Key="TouchMin">24</sys:Double>') -and $srcT.Contains('<sys:Double x:Key="TouchBtnMin">0</sys:Double>') -and $srcT.Contains('xmlns:sys="clr-namespace:System;assembly=mscorlib"')) 'dokunma: varsayılan kaynaklar Normal kipte (TouchMin 24, TouchBtnMin 0)'
Assert-True ($srcT.Contains('x:Name="st_TouchSel"')) 'dokunma: Ayarlar > Görünüm seçim kutusu'
Assert-True ((Get-A11yFnText 'Set-AppLayout').Contains('Set-TouchTargets $Name')) 'dokunma: her yerleşim uygulamasında (açılış dahil) hedefler yeniden hesaplanır'
$stt = Get-A11yFnText 'Set-TouchTargets'
Assert-True ($stt.Contains("'TouchMin'") -and $stt.Contains("'TouchBtnMin'") -and $stt.Contains('Resources')) 'dokunma: iki kaynak değeri pencere kaynaklarına yazılır'
Assert-True ((Get-A11yFnText 'Save-StLook').Contains('Set-TouchTargets') -and (Get-A11yFnText 'Load-StLook').Contains('st_TouchSel')) 'dokunma: seçim uygulanır ve kayıtlı değer işaretlenir'
Assert-True ($script:SmokeSafeSelect -contains 'st_TouchSel') 'dokunma: duman testi bu listeyi seçebilir'
$tpair = @(Get-SmokeComboPairs | Where-Object { $_[0] -eq 'st_TouchSel' })
Assert-Eq $tpair.Count 1 'dokunma: duman liste eşleme denetimi dokunma kutusunu kapsar'
# duman kuyruğu
Assert-True ($script:SmokeScopes.ContainsKey('dokunma')) 'dokunma: kısa duman kapsamı tanımlı'
Assert-True ($script:SmokeScopes['tam'] -contains 'dokunma') 'dokunma: tam duman kapsamı Büyük kipi de gezer'
$dkq = @((New-SmokeQueue 'Neon' $sk { param($k) @('tabA', 'tabB') } 'Sade' 'dokunma').ToArray())
$dkK = @($dkq | ForEach-Object { $_.Kind + ':' + $_.Arg })
Assert-Eq ([array]::IndexOf($dkK, 'Touch:Large')) 1 'dokunma kuyruğu: ilk sayfadan sonra Büyük kip (başlangıç Normal olduğundan ayrı Normal adımı yok)'
Assert-True ($dkK -contains 'Touch:Normal') 'dokunma kuyruğu: sonda Normal kipe dönülür'
Assert-Eq (@($dkq | Where-Object { $_.Kind -eq 'Touch' }).Count) 2 'dokunma kuyruğu: Normal başlangıçta yalnızca iki Touch adımı'
$dkShots = @($dkq | Where-Object { $_.Kind -eq 'Shot' } | ForEach-Object { [string]$_.Arg })
Assert-True (@($dkShots | Where-Object { -not $_.StartsWith('dokunma-') }).Count -eq 0) 'dokunma kuyruğu: bütün görüntü adları dokunma- önekli (ölçüm Büyük kipi ayrı sayar)'
Assert-True (($dkShots -contains 'dokunma-panel') -and ($dkShots -contains 'dokunma-optimize-tabB') -and ($dkShots -contains 'dokunma-Kompakt-settings')) 'dokunma kuyruğu: sayfalar, alt sekmeler ve Kompakt yerleşim görüntülenir'
Assert-Eq (@($dkShots | Group-Object | Where-Object { $_.Count -gt 1 }).Count) 0 'dokunma kuyruğu: görüntü adları benzersiz'
$dkL = @($dkq | Where-Object { $_.Kind -eq 'Layout' } | ForEach-Object { [string]$_.Arg })
Assert-True ($dkL[0] -eq 'Kompakt' -and $dkL[1] -eq 'Sade' -and $dkL[$dkL.Count - 1] -eq 'Sade') ('dokunma kuyruğu: Kompakt denenir, hemen yerleşim geri verilir, sonda başlangıç yerleşimi: ' + ($dkL -join ','))
$dkq2 = @((New-SmokeQueue 'Neon' $sk { param($k) @() } 'Sade' 'dokunma' 'Klasik' 'Yok|100' 'Pano|Auto|Auto|Auto|Auto|Auto' 'Auto').ToArray())
$dkK2 = @($dkq2 | Where-Object { $_.Kind -eq 'Touch' } | ForEach-Object { $_.Arg })
Assert-Eq ($dkK2 -join ',') 'Normal,Large,Normal,Auto' 'dokunma kuyruğu: Otomatik başlangıçta Normal denenir, sonda kullanıcının Otomatik ayarı geri verilir'
$dkq3 = @((New-SmokeQueue 'Neon' $sk { param($k) @() } 'Sade' 'gorunum').ToArray())
Assert-Eq (@($dkq3 | Where-Object { $_.Kind -eq 'Touch' }).Count) 0 'dokunma kuyruğu: gorunum kapsamı dokunma adımı içermez'
# rapor: Büyük kip ayrı sayılır
$script:Lines.Clear()
$script:SmokeA11y = @{ Runs = 3; Seen = @{ 'Button A "x"' = 'home' }; NoName = @{}; Small24 = @{}; Small32 = @{ 'Button A "x"' = 'home 100x30' }; Ctx = @{}; Kinds = @{ Button = 1 }; Ms = 2
    Named = @{}; Mis = @{}; Dup = @{}; L24 = @{}; L32 = @{ 'Button B "y"' = 'dokunma-home 90x31' }; L40 = @{ 'Button C "z"' = 'dokunma-home 80x38' }; LRuns = 2 }
Write-SmokeA11yReport
Assert-True (Has-Line 'dokunma hedefleri Büyük (2 görünüm): 24 px altı: 0; 24-32 px arası: 1; 32-40 px arası (Kompakt dışı): 1') ('dokunma raporu: özet satırı: ' + (@($script:Lines) -join ' / '))
$dt = [System.IO.File]::ReadAllText($ap)
Assert-True ($dt.Contains('[DOKUNMA BÜYÜK: 24-32 PX ARASI] 1') -and $dt.Contains('Button B "y"  |  dokunma-home 90x31')) 'dokunma raporu: ayrıntı dosyasında Büyük kip bölümleri'
Remove-Item -LiteralPath $ap -Force -ErrorAction SilentlyContinue
$script:Lines.Clear()
$script:SmokeA11y = $null
$mfn = Get-A11yFnText 'Measure-SmokeA11y'
Assert-True ($mfn.Contains("StartsWith('dokunma-')") -and $mfn.Contains('$A.L24[$key]') -and $mfn.Contains('$A.L40[$key]') -and $mfn.Contains("@('Button', 'CheckBox', 'RadioButton') -contains $kind")) 'dokunma ölçümü: Büyük kip görünümleri ayrı tablolara yazılır (Normal sayılar değişmez)'
Import-Var 'SmokeLimitSec'
Assert-True ([int]$script:SmokeLimitSec -ge 4800) ('dokunma: duman zaman aşımı tam kapsamı (Büyük kip dahil) kapsar: ' + [string]$script:SmokeLimitSec + ' sn')
Assert-True ([int]$script:SmokeA11yMax -ge 200 -and [int]$script:SmokeA11yMaxLarge -ge 120) ('dokunma ölçümü: Normal ve Büyük kip görünüm sınırları ayrı (' + [string]$script:SmokeA11yMax + ' / ' + [string]$script:SmokeA11yMaxLarge + ')')
Assert-True ($mfn.Contains('A11yMaxLarge') -and $mfn.Contains('$A.Capped = $true')) 'dokunma ölçümü: sınır dolarsa işaretlenir'
$script:Lines.Clear()
$script:SmokeA11y = @{ Runs = 1; Seen = @{ 'Button A "x"' = 'home' }; NoName = @{}; Small24 = @{}; Small32 = @{}; Ctx = @{}; Kinds = @{ Button = 1 }; Ms = 2; Capped = $true }
Write-SmokeA11yReport
Assert-True (Has-Line 'ölçüm görünüm sınırı doldu') 'dokunma raporu: sınır dolduysa uyarı satırı'
Remove-Item -LiteralPath $ap -Force -ErrorAction SilentlyContinue
$script:Lines.Clear()
$script:SmokeA11y = $null
$rh = Get-A11yFnText 'Get-RailHeight'
Assert-True ($rh.Contains("TouchMode -eq 'Large'") -and $rh.Contains('TouchMinNow')) 'dokunma: sol menü düğmeleri Büyük kipte en az TouchMin (Sade yerleşimde 34-40 px idi)'
Assert-True ((Get-A11yFnText 'Get-SafeLookKeys').Contains("TouchTargets = 'Normal'")) 'dokunma: güvenli görünüm Normal kipte açılır (Büyük kip taşma yaparsa)'
Assert-True ((Get-A11yFnText 'Set-TouchTargets').Contains('Update-RailDensity')) 'dokunma: kip değişince sol menü yüksekliği yeniden hesaplanır'

# Gerçek bilgisayarda bulundu (25.11.2026): Loaded sınıf işleyicisi çoğu düğmede hiç çağrılmadı (WPF, Loaded olayını yalnızca
# Loaded işleyicisi olan öğelere yayınlar); ad verme yaması öncesi ve sonrası ölçüm aynı kaldı (46 adsız denetim).
$reg = Get-A11yFnText 'Register-A11yNames'
Assert-True ($reg.Contains('FrameworkElement]::SizeChangedEvent')) 'erişim adları: ilk boyut (SizeChanged) sınıf işleyicisi kaydedilir'
Assert-True ($reg.Contains('PreviousSize') -and $reg.Contains('-gt 0 -and')) 'erişim adları: yeniden boyutlanmada iş yapılmaz (yalnızca ilk boyut)'
Assert-True ((Get-A11yFnText 'Add-A11yCandidate').Contains('DispatcherPriority]::Background')) 'erişim adları: kuyruk Background önceliğinde işlenir (ApplicationIdle beklemez)'
Assert-True ((Get-A11yFnText 'Measure-SmokeA11y').Contains('Invoke-A11yQueue')) 'erişim ölçümü: bekleyen adlar ölçümden önce verilir'
$script:Lines.Clear()
$script:A11yCalls = 10
$script:A11yDone = 7
$script:SmokeA11y = @{ Runs = 1; Seen = @{ 'Button Kok "Uygula"' = 'home' }; NoName = @{}; Small24 = @{}; Small32 = @{}; Ctx = @{}; Kinds = @{ Button = 1 }; Ms = 3 }
Write-SmokeA11yReport
Assert-True (Has-Line 'ekran okuyucu adı verilen: 7 denetim (incelenen 10)') 'erişim: verilen ad sayısı raporda'
Remove-Item -LiteralPath $ap -Force -ErrorAction SilentlyContinue
$script:Lines.Clear()
Remove-Variable -Name A11yCalls, A11yDone -Scope Script -ErrorAction SilentlyContinue
$script:SmokeA11y = @{ Runs = 1; Seen = @{ 'Button Kok "Uygula"' = 'home' }; NoName = @{}; Small24 = @{}; Small32 = @{}; Ctx = @{}; Kinds = @{ Button = 1 }; Ms = 3 }
Write-SmokeA11yReport
Assert-True (-not (Has-Line 'ekran okuyucu adı verilen')) 'erişim: ad verme yüklenmemişse satır yazılmaz'
Remove-Item -LiteralPath $ap -Force -ErrorAction SilentlyContinue
$script:Lines.Clear()
$script:SmokeA11y = $null

Show-Result
