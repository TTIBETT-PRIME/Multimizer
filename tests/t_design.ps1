# 8.0.0: Tasarim motoru ve pano arayuzunun saf kismi + kaynak duzeyi baglanti denetimleri.
# WPF Linux'ta calismadigi icin cizim kodu burada calistirilmaz; cizimin dayandigi tablolar, hesaplar, XAML butunlugu ve
# ana betige baglanan kancalar denetlenir. Cizim kodunun kendisi duman testinde (tasarim x tema) gercek pencerede sinanir.
. "$PSScriptRoot/lib.ps1"

Import-Fn 'ConvertTo-DesignKey', 'Get-DesignSpec', 'Get-DesignHero', 'Get-NavGroups', 'Get-NavGroupOf', 'Get-NavMenuItems', 'ConvertTo-TrUpper', 'ConvertTo-AsciiKey'
Import-Fn 'Format-BoardNum', 'Get-SparkPoints', 'Get-HexCells', 'Get-HexPath', 'Get-RadarSlots', 'Get-CpuShortName', 'Get-BoardSearchResults', 'Get-BoardKind'
Import-Fn 'Get-LookPreset', 'Get-PresetGlass', 'Get-RailWidth', 'Get-BoardField', 'ConvertTo-HomeKey', 'ConvertTo-DsValue', 'Merge-DesignOverrides', 'Get-ActiveDesign', 'Test-DesignOverridden', 'Clear-DesignOverrides', 'Test-BoardHome'
Import-Var 'HomeInfo', 'DsOptions', 'DsTitles', 'DsRadii', 'BoardPresetInfo', 'DesignInfo', 'PageNames', 'PageSubs', 'PageIcons', 'PageTitles', 'BoardSearchWords', 'BoardWidgets', 'BoardActions', 'BoardPresets', 'CmdDefs', 'Themes', 'LayoutInfo', 'BoardAccent'
Import-Var 'BoardShellHead', 'BoardShellTail', 'Page_board', 'ExpertPages'

# Doseme icerikleri: $script:BoardXaml['tur'] = @'...'@ atamalari tek tek yuklenir
[void](Get-AstFunctions)
$script:BoardXaml = @{}
foreach ($a in @($script:Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text.StartsWith('$script:BoardXaml[') }, $true))) {
    . ([scriptblock]::Create($a.Extent.Text))
}

$src = [System.IO.File]::ReadAllText($script:TestPath)
function Get-FnText([string]$Name) {
    $f = @(Get-AstFunctions | Where-Object { ($_.Name -replace '^global:', '') -eq $Name }) | Select-Object -Last 1
    if ($null -eq $f) { return '' }
    return $f.Extent.Text
}
function Test-Key([string]$Key) { return $src.Contains('x:Key="' + $Key + '"') }

# ======================= 1) tasarim tablosu =======================
$keys = @($script:DesignInfo.Keys)
Assert-Eq $keys.Count 5 'bes tasarim var'
Assert-Eq ($keys -join ',') 'Klasik,Atolye,Sifir,Morpheus,Komuta' 'tasarim sirasi'
foreach ($k in $keys) {
    Assert-True ([string]$script:DesignInfo[$k].T -ne '' -and [string]$script:DesignInfo[$k].D -ne '') "$k adi ve aciklamasi var"
}
Assert-Eq (ConvertTo-DesignKey 'Morpheus') 'Morpheus' 'anahtar: gecerli korunur'
Assert-Eq (ConvertTo-DesignKey 'yok') 'Klasik' 'anahtar: bilinmeyen Klasik olur'
Assert-Eq (ConvertTo-DesignKey $null) 'Klasik' 'anahtar: null Klasik olur'
Assert-Eq (ConvertTo-DesignKey '') 'Klasik' 'anahtar: bos Klasik olur'

$navSet = @('Rail', 'Fly', 'Hidden', 'Compact')
$skinSet = @('Plain', 'Glass', 'Calm', 'Neon', 'Slate')
$graphSet = @('area', 'scope', 'none')
foreach ($k in $keys) {
    $s = Get-DesignSpec $k
    Assert-Eq $s.Key $k "$k ozelligi: anahtar"
    Assert-True ($navSet -contains [string]$s.Nav) "$k menu bicimi gecerli ($($s.Nav))"
    Assert-True ($skinSet -contains [string]$s.Skin) "$k parca gorunumu gecerli ($($s.Skin))"
    Assert-True ($graphSet -contains [string]$s.Graph) "$k grafik dili gecerli ($($s.Graph))"
    Assert-True ([double]$s.RadCard -ge 0 -and [double]$s.RadCard -le 30) "$k kart kosesi makul"
    Assert-True ([double]$s.RadBtn -ge 0 -and [double]$s.RadBtn -le 24) "$k dugme kosesi makul"
    Assert-True ([int]$s.Gap -ge 4 -and [int]$s.Gap -le 24) "$k aralik makul"
    Assert-True ([int]$s.CellH -ge 40 -and [int]$s.CellH -le 120) "$k hucre yuksekligi makul"
    Assert-True ($script:Themes.Contains([string]$s.Theme)) "$k onerilen tema tanimli ($($s.Theme))"
    Assert-True ($script:LayoutInfo.Contains([string]$s.Layout)) "$k onerilen yerlesim tanimli ($($s.Layout))"
    Assert-True ($script:BoardPresets.ContainsKey([string]$s.Preset)) "$k hazir pano duzeni tanimli ($($s.Preset))"
    $h = Get-DesignHero $k
    Assert-True ([string]$h.T -ne '' -and [string]$h.S -ne '') "$k karsilama metni var"
}
$kl = Get-DesignSpec 'Klasik'
Assert-True ($kl.Board -eq $true) 'Klasik: pano da kullanilabilir (ana ekran bicimini Ana ekran secimi belirler)'
Assert-Eq $kl.Preset 'Klasik' 'Klasik: kendi hazir duzeni bugunku durum panosunu taklit eder'
Assert-Eq $kl.Nav 'Rail' 'Klasik: simge menusu'
Assert-Eq "$($kl.RadCard),$($kl.RadBtn)" '8,6' 'Klasik: koseler eski degerlerle ayni'
Assert-Eq $kl.Skin 'Plain' 'Klasik: duz gorunum'
foreach ($k in @('Atolye', 'Sifir', 'Morpheus', 'Komuta')) { Assert-True ((Get-DesignSpec $k).Board -eq $true) "$k ana ekrani pano"; Assert-Eq (Get-DesignSpec $k).Preset $k "$k kendi hazir duzenini kullanir" }
Assert-Eq (Get-DesignSpec 'Atolye').Nav 'Fly' 'Atolye: acilir alt menulu simge menusu'
Assert-Eq (Get-DesignSpec 'Sifir').Nav 'Hidden' 'Sifir Noktasi: menu gizli'
Assert-Eq (Get-DesignSpec 'Sifir').Graph 'none' 'Sifir Noktasi: sayi ve grafik kalabaligi yok'
Assert-True ((Get-DesignSpec 'Morpheus').Mono -eq $true) 'Morpheus: tek aralikli yazi'
Assert-Eq (Get-DesignSpec 'Morpheus').Graph 'scope' 'Morpheus: dalga bicimli grafik'
Assert-Eq (Get-DesignSpec 'Komuta').Skin 'Slate' 'Komuta Merkezi: arduvaz gorunumu'
Assert-True ((Get-DesignSpec 'Sifir').RadCard -gt (Get-DesignSpec 'Morpheus').RadCard) 'Sifir Noktasi yuvarlak, Morpheus koseli'
Assert-Eq (Get-DesignSpec 'bilinmeyen').Key 'Klasik' 'ozellik: bilinmeyen anahtar Klasik'

# ======================= 1b) ana ekran bicimi ve tasarim ayrintilari =======================
Assert-Eq (@($script:HomeInfo.Keys) -join ',') 'Pano,Klasik' 'ana ekran bicimleri: Pano ve Klasik'
foreach ($hk in @($script:HomeInfo.Keys)) { Assert-True ([string]$script:HomeInfo[$hk].T -ne '' -and [string]$script:HomeInfo[$hk].D -ne '') "ana ekran bicimi $hk adi ve aciklamasi var" }
Assert-Eq (ConvertTo-HomeKey 'Klasik') 'Klasik' 'ana ekran: Klasik korunur'
Assert-Eq (ConvertTo-HomeKey 'Pano') 'Pano' 'ana ekran: Pano korunur'
Assert-Eq (ConvertTo-HomeKey '') 'Pano' 'ana ekran: bos Pano olur'
Assert-Eq (ConvertTo-HomeKey $null) 'Pano' 'ana ekran: null Pano olur'
Assert-Eq (ConvertTo-HomeKey 'klasik') 'Klasik' 'ana ekran: harf boyutu onemsiz, kayitli anahtara cevrilir'
Assert-Eq (ConvertTo-HomeKey 'baska') 'Pano' 'ana ekran: bilinmeyen deger Pano olur'
Assert-Eq (@($script:DsOptions.Keys) -join ',') 'Nav,Radius,Font,Graph,Skin' 'tasarim ayrintilari: bes ozellik'
Assert-Eq (@($script:DsTitles.Keys) -join ',') (@($script:DsOptions.Keys) -join ',') 'tasarim ayrintilari: her ozelligin basligi var'
foreach ($pr in @($script:DsOptions.Keys)) {
    $opt = $script:DsOptions[$pr]
    Assert-Eq ([string]@($opt.Keys)[0]) 'Auto' "ayrinti $pr : ilk secenek 'Tasarima gore'"
    Assert-True ([string]$script:DsTitles[$pr] -ne '') "ayrinti $pr basligi var"
    foreach ($ok in @($opt.Keys)) { Assert-True ([string]$opt[$ok] -ne '') "ayrinti $pr secenegi $ok adli" }
    Assert-Eq (ConvertTo-DsValue ([string]$pr) 'Auto') 'Auto' "ayrinti $pr : Auto korunur"
    Assert-Eq (ConvertTo-DsValue ([string]$pr) 'zzz') 'Auto' "ayrinti $pr : bilinmeyen deger Auto olur"
    Assert-Eq (ConvertTo-DsValue ([string]$pr) $null) 'Auto' "ayrinti $pr : null Auto olur"
    Assert-Eq (ConvertTo-DsValue ([string]$pr) '') 'Auto' "ayrinti $pr : bos Auto olur"
}
Assert-Eq (ConvertTo-DsValue 'Yok' 'Rail') 'Auto' 'ayrinti: bilinmeyen ozellik Auto olur'
Assert-Eq (ConvertTo-DsValue 'Nav' 'compact') 'Compact' 'ayrinti: harf boyutu onemsiz, kayitli degere cevrilir'
Assert-Eq (ConvertTo-DsValue 'Graph' 'AREA') 'area' 'ayrinti: grafik anahtarlari kucuk harfli'
# her tasarimin kendi degeri, ilgili ayrinti listesinde bulunur (secilince degismeden kalabilmesi icin)
foreach ($k in $keys) {
    $s2 = Get-DesignSpec $k
    Assert-True (@($script:DsOptions.Nav.Keys) -contains [string]$s2.Nav) "$k menu bicimi ayrinti listesinde"
    Assert-True (@($script:DsOptions.Skin.Keys) -contains [string]$s2.Skin) "$k parca gorunumu ayrinti listesinde"
    Assert-True (@($script:DsOptions.Graph.Keys) -contains [string]$s2.Graph) "$k grafik dili ayrinti listesinde"
    Assert-True ($script:BoardPresetInfo.Contains([string]$s2.Preset)) "$k hazir pano duzeninin adi ve aciklamasi var"
}
foreach ($nv in $navSet) { Assert-True (@($script:DsOptions.Nav.Keys) -contains $nv) "menu bicimi secenegi var: $nv" }
foreach ($sv in $skinSet) { Assert-True (@($script:DsOptions.Skin.Keys) -contains $sv) "parca gorunumu secenegi var: $sv" }
foreach ($gv in $graphSet) { Assert-True (@($script:DsOptions.Graph.Keys) -contains $gv) "grafik secenegi var: $gv" }
Assert-Eq (@($script:DsOptions.Font.Keys) -join ',') 'Auto,Sans,Mono' 'yazi tipi secenekleri'
Assert-Eq ((@($script:DsOptions.Radius.Keys) | Where-Object { $_ -ne 'Auto' }) -join ',') (@($script:DsRadii.Keys | Sort-Object { $script:DsRadii[$_][0] }) -join ',') 'kose secenekleri ile kose tablosu ayni, kucukten buyuge'
foreach ($rk in @($script:DsRadii.Keys)) {
    $rv = $script:DsRadii[$rk]
    Assert-True ($rv.Count -eq 2 -and [int]$rv[0] -ge [int]$rv[1] -and [int]$rv[0] -le 30 -and [int]$rv[1] -ge 0) "kose degerleri makul ($rk)"
}

# --- Merge-DesignOverrides (saf islev) ---
$base = Get-DesignSpec 'Morpheus'
$m0 = Merge-DesignOverrides $base @{}
foreach ($pk in @('Key', 'Preset', 'Nav', 'RadCard', 'RadBtn', 'Mono', 'Graph', 'Gap', 'CellH', 'Skin', 'Theme', 'Layout')) { Assert-Eq $m0[$pk] $base[$pk] "ayrinti yokken tasarim ozelligi aynen kalir: $pk" }
Assert-True ($m0.Board -eq $true) 'ayar yokken ana ekran Pano'
Assert-True ((Merge-DesignOverrides $base @{ HomeMode = 'Klasik' }).Board -eq $false) 'HomeMode Klasik: pano kapali'
Assert-True ((Merge-DesignOverrides $base @{ HomeMode = 'Pano' }).Board -eq $true) 'HomeMode Pano: pano acik'
Assert-True ((Merge-DesignOverrides $base @{ HomeMode = 'sacma' }).Board -eq $true) 'HomeMode bilinmiyorsa Pano'
Assert-Eq (Merge-DesignOverrides $base @{ DsNav = 'Hidden' }).Nav 'Hidden' 'DsNav uygulanir'
Assert-Eq (Merge-DesignOverrides $base @{ DsNav = 'Auto' }).Nav 'Compact' 'DsNav Auto: tasarimin degeri'
$mr = Merge-DesignOverrides $base @{ DsRadius = 'Pill' }
Assert-Eq "$($mr.RadCard),$($mr.RadBtn)" '24,16' 'DsRadius Pill: kart ve dugme koseleri'
$mr = Merge-DesignOverrides $base @{ DsRadius = 'Sharp' }
Assert-Eq "$($mr.RadCard),$($mr.RadBtn)" '2,2' 'DsRadius Sharp: kart ve dugme koseleri'
Assert-True ((Merge-DesignOverrides $base @{ DsFont = 'Sans' }).Mono -eq $false) 'DsFont Sans: tek aralikli yazi kapanir'
Assert-True ((Merge-DesignOverrides (Get-DesignSpec 'Atolye') @{ DsFont = 'Mono' }).Mono -eq $true) 'DsFont Mono: tek aralikli yazi acilir'
Assert-True ((Merge-DesignOverrides $base @{ DsFont = 'Auto' }).Mono -eq $true) 'DsFont Auto: tasarimin degeri'
Assert-Eq (Merge-DesignOverrides $base @{ DsGraph = 'none' }).Graph 'none' 'DsGraph uygulanir'
Assert-Eq (Merge-DesignOverrides $base @{ DsSkin = 'Glass' }).Skin 'Glass' 'DsSkin uygulanir'
$mx = Merge-DesignOverrides $base @{ DsNav = 'zzz'; DsRadius = 7; DsFont = $null; DsGraph = ''; DsSkin = 'yok' }
foreach ($pk in @('Nav', 'RadCard', 'RadBtn', 'Mono', 'Graph', 'Skin')) { Assert-Eq $mx[$pk] $base[$pk] "gecersiz ayrinti degeri yok sayilir: $pk" }
Assert-Eq $base.Nav 'Compact' 'Merge-DesignOverrides asil tasarim tablosunu degistirmez (Nav)'
Assert-Eq $base.Skin 'Neon' 'Merge-DesignOverrides asil tasarim tablosunu degistirmez (Skin)'
# nesne bicimli ayarlar (PSCustomObject) da okunur
$mo = Merge-DesignOverrides $base ([pscustomobject]@{ DsNav = 'Fly'; HomeMode = 'Klasik' })
Assert-True ($mo.Nav -eq 'Fly' -and $mo.Board -eq $false) 'ayarlar nesne olsa da okunur'
# birlesik secimler birbirini bozmaz
$mc = Merge-DesignOverrides $base @{ DsNav = 'Rail'; DsRadius = 'Round'; DsFont = 'Sans'; DsGraph = 'area'; DsSkin = 'Plain'; HomeMode = 'Klasik' }
Assert-True ($mc.Nav -eq 'Rail' -and $mc.RadCard -eq 18 -and $mc.RadBtn -eq 12 -and $mc.Mono -eq $false -and $mc.Graph -eq 'area' -and $mc.Skin -eq 'Plain' -and $mc.Board -eq $false) 'bes ayrinti ve ana ekran birlikte uygulanir'
Assert-Eq $mc.Preset 'Morpheus' 'ayrintilar secilse de hazir pano duzeni tasarimin kendisi kalir'
foreach ($k in $keys) {
    foreach ($hm in @('Pano', 'Klasik')) {
        $mm = Merge-DesignOverrides (Get-DesignSpec $k) @{ HomeMode = $hm }
        Assert-True ($mm.Board -eq ($hm -ne 'Klasik')) "$k x ana ekran $hm : Board dogru"
    }
}

# --- Test-DesignOverridden / Clear-DesignOverrides ---
Assert-True ((Test-DesignOverridden @{}) -eq $false) 'ayrinti yokken ozel secim yok'
Assert-True ((Test-DesignOverridden @{ DsNav = 'Auto'; DsRadius = 'Auto'; DsFont = 'Auto'; DsGraph = 'Auto'; DsSkin = 'Auto' }) -eq $false) 'hepsi Auto: ozel secim yok'
Assert-True ((Test-DesignOverridden @{ DsSkin = 'zzz' }) -eq $false) 'gecersiz deger Auto sayilir'
foreach ($pr in @($script:DsOptions.Keys)) {
    $non = [string](@($script:DsOptions[$pr].Keys) | Where-Object { $_ -ne 'Auto' } | Select-Object -First 1)
    Assert-True ((Test-DesignOverridden @{ ('Ds' + $pr) = $non }) -eq $true) "tek ayrinti degisince ozel secim var ($pr)"
}
$cl = @{ DsNav = 'Fly'; DsRadius = 'Pill'; DsFont = 'Mono'; DsGraph = 'none'; DsSkin = 'Glass'; Theme = 'Neon'; HomeMode = 'Klasik' }
Clear-DesignOverrides $cl
foreach ($pr in @($script:DsOptions.Keys)) { Assert-Eq $cl[('Ds' + $pr)] 'Auto' "Clear-DesignOverrides: Ds$pr Auto olur" }
Assert-Eq $cl.Theme 'Neon' 'Clear-DesignOverrides: tema degismez'
Assert-Eq $cl.HomeMode 'Klasik' 'Clear-DesignOverrides: ana ekran bicimi degismez'
Assert-True ((Test-DesignOverridden $cl) -eq $false) 'temizlenince ozel secim kalmaz'

# --- Get-ActiveDesign / Test-BoardHome ---
$script:DesignKey = 'Komuta'
$script:Settings = @{ HomeMode = 'Pano'; DsSkin = 'Glass' }
$ad = Get-ActiveDesign
Assert-True ($ad.Key -eq 'Komuta' -and $ad.Preset -eq 'Komuta' -and $ad.Skin -eq 'Glass' -and $ad.Board -eq $true) 'Get-ActiveDesign: tasarim + ayrinti + ana ekran'
Assert-True ((Test-BoardHome) -eq $true) 'Test-BoardHome: Pano'
$script:Settings = @{ HomeMode = 'Klasik' }
Assert-True ((Test-BoardHome) -eq $false) 'Test-BoardHome: Klasik durum panosu'
foreach ($k in $keys) {
    $script:DesignKey = $k
    $script:Settings = @{ HomeMode = 'Pano' }
    Assert-True ((Test-BoardHome) -eq $true) "$k tasarimi + Pano: ana ekran pano"
    $script:Settings = @{ HomeMode = 'Klasik' }
    Assert-True ((Test-BoardHome) -eq $false) "$k tasarimi + Klasik: ana ekran klasik durum panosu"
}
$script:DesignKey = 'Klasik'
$script:Settings = $null

# ======================= 2) menu gruplari =======================
$ptKeys = @($script:PageTitles.Keys | ForEach-Object { [string]$_ })
Assert-True ($ptKeys.Count -ge 17) "sayfa basliklari okundu ($($ptKeys.Count))"
Assert-True ($ptKeys -contains 'board') "sayfa basliklarinda 'board' var"
$expertPages = @($script:ExpertPages | ForEach-Object { [string]$_ })
$all = New-Object System.Collections.ArrayList
foreach ($g in @(Get-NavGroups $true)) { foreach ($p in @($g.P)) { [void]$all.Add([string]$p) } }
foreach ($pk in $ptKeys) {
    if ($pk -eq 'board') { continue }
    $n = @($all | Where-Object { $_ -eq $pk }).Count
    Assert-Eq $n 1 "uzman menusunde '$pk' tam bir kez"
}
Assert-Eq $all.Count ($ptKeys.Count - 1) 'menude sayfa anahtarlarindan fazlasi yok'
$user = New-Object System.Collections.ArrayList
foreach ($g in @(Get-NavGroups $false)) { foreach ($p in @($g.P)) { [void]$user.Add([string]$p) } }
foreach ($p in $expertPages) { Assert-True ($user -notcontains $p) "kullanici menusunde uzman sayfasi yok ($p)" }
Assert-Eq $user.Count ($ptKeys.Count - 1 - $expertPages.Count) 'kullanici menusu sayisi'
Assert-Eq @(Get-NavGroups $false).Count 5 'kullanici menusunde bes grup: Araclar sayfasi kullanici kipinde de var (10.1.0)'
Assert-Eq (@(@(Get-NavGroups $false) | Where-Object { $_.K -eq 'kur' })[0].P -join ',') 'tools' 'kullanici kipinde sirket ve araclar grubunda yalnizca Araclar'
Assert-Eq @(Get-NavGroups $true).Count 5 'uzman menusunde bes grup'
foreach ($g in @(Get-NavGroups $true)) {
    Assert-True ([string]$g.T -ne '' -and (Test-Key ([string]$g.Ico))) "grup simgesi tanimli ($($g.K): $($g.Ico))"
}
foreach ($pk in $ptKeys) {
    if ($pk -eq 'board') { continue }
    Assert-True ([string]$script:PageNames[$pk] -ne '') "sayfa adi var ($pk)"
    Assert-True ([string]$script:PageSubs[$pk] -ne '') "sayfa alt basligi var ($pk)"
    Assert-True (Test-Key ([string]$script:PageIcons[$pk])) "sayfa simgesi tanimli (${pk}: $($script:PageIcons[$pk]))"
    Assert-True ($src.Contains('$script:Page_' + $pk + ' = ')) "sayfa XAML'i var ($pk)"
    Assert-True ([string](Get-NavGroupOf $pk $true) -ne '') "sayfa bir gruba ait ($pk)"
}
Assert-Eq (Get-NavGroupOf 'board' $true) 'ana' "'board' ana grupta"
Assert-Eq (Get-NavGroupOf 'panel' $true) 'ana' "'panel' ana grupta"
Assert-Eq (Get-NavGroupOf 'settings' $true) 'son' 'ayarlar son grupta'
Assert-Eq (Get-NavGroupOf 'company' $false) '' 'uzman sayfasi kullanici kipinde grupsuz'
Assert-Eq (Get-NavGroupOf 'tools' $false) 'kur' 'Araclar kullanici kipinde de grubunda'
Assert-Eq (Get-NavGroupOf 'yok' $true) '' 'bilinmeyen sayfa grupsuz'
$items = @(Get-NavMenuItems '' $true)
$heads = @($items | Where-Object { $_.ContainsKey('Head') })
Assert-Eq $heads.Count 5 'tam menude bes baslik'
Assert-True ($heads[0].Head -ceq (ConvertTo-TrUpper $heads[0].Head)) 'basliklar buyuk harf'
Assert-Eq $items.Count (5 + 17) 'tam menu: bes baslik + 17 sayfa'
$one = @(Get-NavMenuItems 'guv' $true)
Assert-Eq $one.Count 4 'tek grup: sayfa sayisi'
Assert-True (-not $one[0].ContainsKey('Head')) 'tek grupta baslik yok'
foreach ($it in $items) { if (-not $it.ContainsKey('Head')) { Assert-True (([string]$it.Tag).StartsWith('nav:') -and [string]$it.Text -ne '') "menu ogesi etiketi nav: ($($it.Text))" } }

# ======================= 3) Turkce buyuk harf =======================
Assert-Eq (ConvertTo-TrUpper ('i' + [char]0x015F + [char]0x0131 + 'k')) ('' + [char]0x0130 + [char]0x015E + 'IK') 'buyuk harf: i -> I-noktali, dotless i -> I'
Assert-Eq (ConvertTo-TrUpper ([string][char]0x0131 + [char]0x015F + [char]0x0131 + 'k')) ('I' + [char]0x015E + 'IK') 'buyuk harf: dotless i -> I'
Assert-Eq (ConvertTo-TrUpper 'abc') 'ABC' 'buyuk harf: ASCII'

# ======================= 4) cizgi grafik =======================
Assert-Eq (Get-SparkPoints @() 100 40 100 60) '' 'grafik: veri yoksa bos'
Assert-Eq (Get-SparkPoints @(5) 100 40 100 60) '' 'grafik: tek veriyle bos'
Assert-Eq (Get-SparkPoints @(1, 2) 1 40 100 60) '' 'grafik: genislik yoksa bos'
$p = (Get-SparkPoints @(0, 50, 100) 100 40 100 3) -split ' '
Assert-Eq $p.Count 3 'grafik: uc veri uc nokta'
Assert-Eq $p[0] '0,38.5' 'grafik: sifir deger altta'
Assert-Eq $p[2] '100,1.5' 'grafik: tam deger ustte'
Assert-Eq $p[1] '50,20' 'grafik: orta deger ortada'
$p2 = (Get-SparkPoints @(10, 20, 30) 90 30 100 10) -split ' '
Assert-Eq ($p2[-1] -split ',')[0] '90' 'grafik: en yeni deger sag uca yaslanir'
Assert-True ([double](($p2[0] -split ',')[0]) -gt 0) 'grafik: kisa gecmis sagda toplanir'
$pc = (Get-SparkPoints @(-10, 500) 100 40 100 2) -split ' '
Assert-Eq $pc[0] '0,38.5' 'grafik: eksi deger sifira kirpilir'
Assert-Eq $pc[1] '100,1.5' 'grafik: ust siniri asan kirpilir'
$long = @(1..80 | ForEach-Object { $_ % 100 })
$pl = (Get-SparkPoints $long 120 40 100 60) -split ' '
Assert-True ($pl.Count -le 80 -and $pl.Count -ge 2) 'grafik: uzun gecmiste sigmayan noktalar atlanir'
foreach ($pt in $pl) { $xy = $pt -split ','; Assert-True ([double]$xy[0] -ge 0 -and [double]$xy[0] -le 120 -and [double]$xy[1] -ge 0 -and [double]$xy[1] -le 40) 'grafik: nokta kutunun icinde' }
Assert-Eq (Format-BoardNum 1.5) '1.5' 'sayi bicimi: nokta ayraci'
Assert-Eq (Format-BoardNum 2) '2' 'sayi bicimi: tam sayi'
Assert-Eq (Format-BoardNum 0.123456) '0.12' 'sayi bicimi: iki basamak'

# ======================= 5) altigen izgara =======================
$cells = @(Get-HexCells 300 150 10)
Assert-True ($cells.Count -gt 40) "altigenler: yeterli hucre ($($cells.Count))"
$dx = [math]::Sqrt(3) * 10
foreach ($c in $cells) {
    Assert-True ($c.X - $dx / 2 -ge -0.01 -and $c.X + $dx / 2 -le 300.6) 'altigen: yatayda sigar'
    Assert-True ($c.Y - 10 -ge -0.01 -and $c.Y + 10 -le 150.6) 'altigen: dikeyde sigar'
}
$row0 = @($cells | Where-Object { [math]::Abs($_.Y - 10) -lt 0.01 })
$row1 = @($cells | Where-Object { [math]::Abs($_.Y - 25) -lt 0.01 })
Assert-True ($row0.Count -gt 0 -and $row1.Count -gt 0) 'altigen: ilk iki satir var'
Assert-True ([math]::Abs($row1[0].X - $row0[0].X - $dx / 2) -lt 0.01) 'altigen: tek satirlar yarim hucre kayik'
Assert-Eq @(Get-HexCells 10 10 10).Count 0 'altigen: kucuk alanda hucre yok'
Assert-Eq @(Get-HexCells 300 150 1).Count 0 'altigen: cok kucuk yaricap reddedilir'
$hp = Get-HexPath @($cells[0], $cells[1]) 10
Assert-Eq ([regex]::Matches($hp, 'M').Count) 2 'altigen yolu: iki hucre iki parca'
Assert-Eq ([regex]::Matches($hp, 'Z').Count) 2 'altigen yolu: parcalar kapali'
Assert-Eq ([regex]::Matches($hp, ' L').Count) 10 'altigen yolu: her parca bes cizgi'
Assert-True ($hp -notmatch '[A-Za-z]{2}') 'altigen yolu: yalnizca komut harfleri'
Assert-Eq (Get-HexPath @() 10) '' 'altigen yolu: bos girdi bos'

# ======================= 6) radar =======================
foreach ($n in @(0, 1, 5, 8, 9, 22, 46, 80)) {
    $sl = @(Get-RadarSlots $n 100 100 90)
    Assert-Eq $sl.Count $n "radar: $n cihaz $n yer"
    foreach ($q in $sl) {
        $d = [math]::Sqrt([math]::Pow($q.X - 100, 2) + [math]::Pow($q.Y - 100, 2))
        Assert-True ($d -le 90 * 0.92 + 0.01 -and $d -ge 90 * 0.42 - 0.01) "radar: yer halkalarin icinde ($n)"
    }
    $seen = @{}
    foreach ($q in $sl) { $seen[('{0:0.0},{1:0.0}' -f $q.X, $q.Y)] = $true }
    Assert-Eq $seen.Count $n "radar: yerler birbirinden farkli ($n)"
}

# ======================= 7) islemci adi ve arama =======================
Assert-Eq (Get-CpuShortName 'Intel(R) Core(TM) i7-9700K CPU @ 3.60GHz') 'Intel Core i7-9700K' 'islemci adi kisaltilir'
Assert-Eq (Get-CpuShortName 'AMD Ryzen 5 5600X 6-Core Processor') 'AMD Ryzen 5 5600X 6-Core' 'islemci adi: AMD'
Assert-Eq (Get-CpuShortName '') '' 'islemci adi: bos'

$r = @(Get-BoardSearchResults 'guvenlik')
Assert-True ($r.Count -ge 1) 'arama: guvenlik sonuc verir'
Assert-Eq $r[0].Tag 'nav:security' "arama: 'guvenlik' guvenlik sayfasini basa koyar"
$guv = 'G' + [char]0x00FC + 'venlik'
Assert-Eq (@(Get-BoardSearchResults $guv)[0].Tag) 'nav:security' 'arama: Turkce harfli yazim'
Assert-Eq (@(Get-BoardSearchResults 'temizlik')[0].Tag) 'nav:clean' 'arama: temizlik'
Assert-True (@(Get-BoardSearchResults 'saglik' | Where-Object { $_.Tag -eq 'act:health' }).Count -eq 1) 'arama: saglik eylemi bulunur'
Assert-True (@(Get-BoardSearchResults 'yedek' | Where-Object { $_.Tag -eq 'nav:backup' }).Count -eq 1) 'arama: yedek sayfasi'
Assert-True (@(Get-BoardSearchResults 'vpn' | Where-Object { $_.Tag -eq 'nav:network' }).Count -eq 1) 'arama: anahtar sozcukle ag sayfasi (vpn)'
Assert-True (@(Get-BoardSearchResults 'tema' | Where-Object { $_.Tag -eq 'nav:settings' }).Count -eq 1) 'arama: tema -> ayarlar'
Assert-True (@(Get-BoardSearchResults 'saydamlik' | Where-Object { $_.Tag -eq 'nav:settings' }).Count -eq 1) 'arama: saydamlik -> ayarlar'
Assert-Eq @(Get-BoardSearchResults '').Count 0 'arama: bos sorgu bos'
Assert-Eq @(Get-BoardSearchResults '   ').Count 0 'arama: bosluk sorgusu bos'
Assert-Eq @(Get-BoardSearchResults 'zzzzqq').Count 0 'arama: anlamsiz sorgu bos'
Assert-True (@(Get-BoardSearchResults 'a').Count -le 7) 'arama: en cok yedi sonuc'
foreach ($q in @('ag', 'oyun', 'guc', 'rapor', 'bakim', 'hiz', 'guncelleme', 'sirket', 'arac', 'gecmis', 'disk', 'yedekle', 'ayar')) {
    Assert-True (@(Get-BoardSearchResults $q).Count -ge 1) "arama: '$q' bir sey bulur"
}
foreach ($qq in @('ag', 'guvenlik', 'temiz')) {
    foreach ($x in @(Get-BoardSearchResults $qq)) {
        Assert-True ([string]$x.Text -ne '' -and ([string]$x.Tag -match '^(nav|act|cmd):')) 'arama: sonuc bicimi'
        if (([string]$x.Tag).StartsWith('nav:') -or ([string]$x.Tag).StartsWith('act:')) { Assert-True (Test-Key ([string]$x.Ico)) "arama: sonuc simgesi tanimli ($($x.Ico))" }
    }
}
# komut: ilk sozcuk bilinen bir komutsa ve bagimsiz degiskeni varsa en ustte
$cmdKey = ''
foreach ($ck in @($script:CmdDefs.Keys)) { if ([string]$ck -match '^[a-z]+$' -and [string]$ck -ne 'ag') { $cmdKey = [string]$ck; break } }
Assert-True ($cmdKey -ne '') 'komut tablosunda en az bir komut var'
$cr = @(Get-BoardSearchResults ($cmdKey + ' deneme'))
Assert-True ($cr.Count -ge 1 -and $cr[0].Tag -eq ('cmd:' + $cmdKey + ' deneme')) 'arama: komut + arguman en ustte'

# ======================= 8) hazir gorunumler ve menu genisligi =======================
foreach ($pk in @('Varsayilan', 'KoyuNeon', 'KompaktKoyu', 'Hacker', 'Atolye', 'Sifir', 'Morpheus', 'Komuta')) {
    $lp = Get-LookPreset $pk
    Assert-True ($script:Themes.Contains([string]$lp.Theme)) "hazir gorunum ${pk}: tema tanimli"
    Assert-True ($script:LayoutInfo.Contains([string]$lp.Layout)) "hazir gorunum ${pk}: yerlesim tanimli"
    Assert-True ($script:DesignInfo.Contains([string]$lp.Design)) "hazir gorunum ${pk}: tasarim tanimli"
    Assert-True (@(80, 90, 100, 110, 120, 130) -contains [int]$lp.Zoom) "hazir gorunum ${pk}: yakinlastirma adimi"
}
foreach ($pk in @('Atolye', 'Sifir', 'Morpheus', 'Komuta')) { Assert-Eq (Get-LookPreset $pk).Design $pk "hazir gorunum $pk kendi tasarimini secer" }
foreach ($pk in @('Varsayilan', 'KoyuNeon', 'KompaktKoyu', 'Hacker')) { Assert-Eq (Get-LookPreset $pk).Design 'Klasik' "eski hazir gorunum $pk Klasik'e doner" }
Assert-Eq (Get-RailWidth 'None') 0 'menu genisligi: gizli'
Assert-Eq (Get-RailWidth 'Fly') 84 'menu genisligi: simge menusu'
Assert-Eq (Get-RailWidth 'Compact') 54 'menu genisligi: dar (eski deger)'
Assert-Eq (Get-RailWidth 'Text') 200 'menu genisligi: yazili (eski deger)'
Assert-Eq (Get-RailWidth 'Icon') 72 'menu genisligi: simge (eski deger)'

# ======================= 9) doseme XAML'i =======================
$kinds = @('metric', 'health', 'actionV', 'actionH', 'cta', 'hero', 'search', 'list', 'radar', 'hex')
$need = @{
    metric = @('Gr', 'Gd', 'Ar', 'Ln', 'Ico', 'Ttl', 'Val', 'Sub')
    health = @('Ico', 'Ttl', 'Rg', 'Val', 'Sub', 'Act')
    actionV = @('Hit', 'Plate', 'Ico', 'Ttl', 'Sub')
    actionH = @('Hit', 'Plate', 'Ico', 'Ttl', 'Sub')
    cta = @('Hit', 'Ico', 'Ttl')
    hero = @('Ttl', 'Sub')
    search = @('Ico', 'Inp', 'Ph')
    list = @('Ico', 'Ttl', 'Lst')
    radar = @('Cv', 'Ico', 'Ttl', 'Sub')
    hex = @('Cv', 'HOn', 'HOff', 'Ico', 'Ttl', 'Sub')
}
$shellNames = @('Root', 'Inner', 'Gloss', 'Bar', 'Veil', 'Dash', 'Del', 'Grip')
Assert-Eq $script:BoardXaml.Count $kinds.Count 'doseme icerik turu sayisi'
foreach ($k in $kinds) {
    Assert-True ($script:BoardXaml.ContainsKey($k)) "doseme icerigi tanimli: $k"
    $x = $script:BoardShellHead + "`n" + [string]$script:BoardXaml[$k] + "`n" + $script:BoardShellTail
    $doc = $null
    try { $doc = [xml]$x } catch { Assert-True $false "doseme XAML'i bozuk: $k ($($_.Exception.Message))" }
    if ($null -eq $doc) { continue }
    $names = @([regex]::Matches($x, 'x:Name="([A-Za-z0-9_]+)"') | ForEach-Object { $_.Groups[1].Value })
    $dups = @($names | Group-Object | Where-Object { $_.Count -gt 1 })
    Assert-Eq $dups.Count 0 "doseme ${k}: adlar benzersiz"
    foreach ($nm in ($need[$k] + $shellNames)) { Assert-True ($names -contains $nm) "doseme ${k}: '$nm' adi var" }
    Assert-True ($x -notmatch 'x:Name="Veil"[^>]*Visibility="Visible"') "doseme ${k}: duzenleme ortusu basta kapali"
    foreach ($m in [regex]::Matches($x, '\{DynamicResource ([A-Za-z0-9_]+)\}')) {
        $rk = $m.Groups[1].Value
        Assert-True (Test-Key $rk) "doseme ${k}: kaynak '$rk' tanimli"
    }
}
$pg = $null
try { $pg = [xml]$script:Page_board } catch { Assert-True $false "pano sayfasi XAML'i bozuk: $($_.Exception.Message)" }
Assert-True ($null -ne $pg) 'pano sayfasi gecerli XML'
foreach ($nm in @('bd_Bar', 'bd_Title', 'bd_Hint', 'bd_BtnAdd', 'bd_BtnReset', 'bd_BtnEdit', 'bd_Scroll', 'bd_Canvas')) {
    Assert-True ($script:Page_board.Contains('x:Name="' + $nm + '"')) "pano sayfasinda '$nm' var"
}
foreach ($m in [regex]::Matches($script:Page_board, '\{DynamicResource ([A-Za-z0-9_]+)\}')) {
    Assert-True (Test-Key $m.Groups[1].Value) "pano sayfasi: kaynak '$($m.Groups[1].Value)' tanimli"
}
# parca rengi kaynaklari gercek
foreach ($k in @($script:BoardAccent.Keys)) { Assert-True (Test-Key ([string]$script:BoardAccent[$k])) "parca rengi tanimli ($k)" }
# her parca turunun bir icerigi, her parcanin simgesi var
foreach ($k in @($script:BoardWidgets.Keys)) {
    $w = $script:BoardWidgets[$k]
    $kind = Get-BoardKind @{ Type = [string]$k; H = [int]$w.H }
    Assert-True ($script:BoardXaml.ContainsKey($kind)) "her parca turunun bir XAML'i var ($k -> $kind)"
    Assert-True (Test-Key ([string]$w.Ico)) "parca simgesi tanimli ($k : $($w.Ico))"
}
Assert-Eq (Get-BoardKind @{ Type = 'action'; H = 2 }) 'actionH' 'eylem karti alcakken yatay gorunum'
Assert-Eq (Get-BoardKind @{ Type = 'action'; H = 3 }) 'actionV' 'eylem karti yukseken dikey gorunum'
# eylem kartlarinin hedefleri gercek
foreach ($k in @($script:BoardActions.Keys)) {
    $a = $script:BoardActions[$k]
    Assert-True (Test-Key ([string]$a.Ico)) "eylem simgesi tanimli ($k)"
    if ([string]$a.Page -ne '') { Assert-True ($script:PageTitles.Contains([string]$a.Page)) "eylem sayfasi gercek ($k -> $($a.Page))" }
    else { Assert-True (@('health', 'maint', 'audit', 'report') -contains [string]$a.Fn) "eylem islevi taniniyor ($k -> $($a.Fn))" }
}

# ======================= 10) ana betige baglantilar =======================
foreach ($key in @('RadCard', 'RadBtn', 'BtnRow', 'BtnChoice', 'BtnTile', 'BtnFly', 'IcoMenu')) { Assert-True (Test-Key $key) "kaynak tanimli: $key" }
foreach ($nm in @('BtnMenu', 'FlyRail', 'RailBottom')) { Assert-True ($src.Contains('x:Name="' + $nm + '"')) "ana pencerede '$nm' var" }
Assert-True ($src.Contains('CornerRadius="{DynamicResource RadCard}"')) 'kartlar kosesini kaynaktan okur'
Assert-True ($src.Contains('Value="{DynamicResource RadCard}"')) 'Card stili kosesini kaynaktan okur'
Assert-True ($src.Contains('Value="{DynamicResource RadBtn}"')) 'Row stili kosesini kaynaktan okur'
$sp = Get-FnText 'Show-Page'
Assert-True ($sp.Contains("if (Test-BoardHome) { `$Key = 'board' }")) "Show-Page: 'panel' ana ekran panoysa panoya yonlenir"
Assert-True ($sp.Contains("Rail_' + `$railKey")) "Show-Page: pano 'panel' dugmesini isaretler"
Assert-True ($sp.Contains('Sync-FlyRail')) 'Show-Page: simge menusu vurgusu eslenir'
Assert-True ($sp.Contains('Close-NavMenu')) 'Show-Page: acik alt menu kapanir'
Assert-True ((Get-FnText 'Step-Page').Contains("'board'")) "Ctrl+Tab: 'board' sayfasi 'panel' sirasinda"
Assert-True ((Get-FnText 'Update-MonitorUi').Contains('Invoke-BoardTick')) 'izleme turu panoya da ulasir'
Assert-True ((Get-FnText 'Add-LogLine').Contains('Push-BoardLog')) 'gunluk satirlari panodaki akan gunluge de duser'
Assert-True ((Get-FnText 'Update-HealthUi').Contains('Update-BoardHealth')) 'saglik sonucu panodaki halkaya ulasir'
Assert-True ((Get-FnText 'Set-AppLayout').Contains('Apply-DesignShell')) 'yerlesim degisince tasarim kabugu yeniden uygulanir'
Assert-True ((Get-FnText 'Init-StExtra').Contains('Initialize-StDesignChoices')) 'ayar sayfasi tasarim listelerini doldurur'
foreach ($cn in @('st_DesignSel', 'st_HomeSel', 'st_DsNavSel', 'st_DsRadiusSel', 'st_DsFontSel', 'st_DsGraphSel', 'st_DsSkinSel')) { Assert-True ((Get-FnText 'Init-StExtra').Contains("'" + $cn + "'")) "ayar sayfasi $cn secimini kaydeder" }
foreach ($cn in @('st_DsAdv', 'st_DsAdvPanel', 'st_DsReset', 'st_BoardEdit', 'st_BoardReset')) { Assert-True ((Get-FnText 'Init-StExtra').Contains($cn)) "ayar sayfasi $cn denetimini baglar" }
Assert-True ((Get-FnText 'Init-StExtra').Contains('Open-BoardEditor')) 'Duzeni ac dugmesi duzenleyiciyi acar'
Assert-True ((Get-FnText 'Init-StExtra').Contains('Reset-DesignOverrides')) 'Ayrintilari sifirla dugmesi baglanti'
Assert-True ((Get-FnText 'Load-StExtra').Contains('Load-St')) 'ayar sayfasi kayitli secimleri parca parca isaretler'
Assert-True ((Get-FnText 'Save-StExtra').Contains("'Save-St'")) 'ayar sayfasi secimleri parca parca kaydeder'
Assert-True ((Get-FnText 'Sync-StLookControls').Contains('Load-StDesign')) 'gorunum listeleri senkronlanirken tasarim listeleri de yenilenir'
Assert-True ((Get-FnText 'Save-StDesign').Contains('Select-HomeMode')) 'ana ekran bicimi secimi uygulanir'
Assert-True ((Get-FnText 'Save-StDesign').Contains('Select-DesignOverride')) 'tasarim ayrintisi secimi uygulanir'
Assert-True ((Get-FnText 'Select-Design').Contains('Clear-DesignOverrides')) 'tasarim secilince ayrintilar tasarimin kendi degerine doner'
Assert-True ((Get-FnText 'Apply-LookPreset').Contains('Select-Design')) 'hazir gorunum tasarimi da uygular'
$gi = $src.IndexOf('Initialize-Layout } catch')
$di = $src.IndexOf('Initialize-Design } catch')
Assert-True ($gi -gt 0 -and $di -gt $gi) 'acilista tasarim yerlesimden sonra uygulanir'
$ds = Get-FnText 'Get-DefaultSettings'
foreach ($stg in @('Design', 'Board', 'BoardCustom')) { Assert-True ($ds -match "\b$stg\s+=") "varsayilan ayarda '$stg' var" }
Assert-True ((Get-FnText 'Get-Settings').Contains("'Board'")) 'Board ayari dizi olarak normallestirilir'
foreach ($fn in @('Initialize-Design', 'Select-Design', 'Set-AppDesign', 'Apply-DesignShell', 'Update-BoardSkin', 'Add-BoardWidget', 'Invoke-BoardAction', 'Set-BoardEdit', 'Reset-BoardLayout', 'Init-Page_board', 'Show-Page_board', 'Update-BoardLive', 'Invoke-BoardTick', 'Push-BoardLog', 'Update-BoardHealth', 'Sync-FlyRail', 'Close-NavMenu', 'Invoke-MenuButton', 'Test-BoardHome', 'Load-StDesign', 'Save-StDesign', 'Build-FlyRail', 'Show-ItemMenu', 'Invoke-MenuTag')) {
    Assert-True ((Get-FnText $fn) -ne '') "islev var: $fn"
}
# eylem kartlarinin cagirdigi islevler gercekten var
foreach ($fn in @('Start-HealthScan', 'Start-QuickMaint', 'Start-ReportNow', 'Open-Page', 'Switch-CmdPanel', 'Invoke-CmdLine', 'Initialize-LanSnap')) { Assert-True ((Get-FnText $fn) -ne '') "pano islevinin cagirdigi islev var: $fn" }
# menu etiketleri: her etiket turunun karsiligi Invoke-MenuTag icinde
$tagFn = Get-FnText 'Invoke-MenuTag'
foreach ($kind in @('nav', 'act', 'cmd', 'add', 'addact', 'addcta', 'layout')) { Assert-True ($tagFn.Contains("'" + $kind + "'")) "menu etiketi isleniyor: $kind" }
# ayar sayfasindaki yeni denetimler (acilir listeler)
foreach ($nm in @('st_LookSel', 'st_ThemeSel', 'st_LayoutSel', 'st_ZoomSel', 'st_DesignSel', 'st_HomeSel', 'st_BackdropSel', 'st_OpacitySel', 'st_DsNavSel', 'st_DsRadiusSel', 'st_DsFontSel', 'st_DsGraphSel', 'st_DsSkinSel')) {
    Assert-True ($src -match ('<ComboBox[^>]*x:Name="' + $nm + '"')) "ayarlarda '$nm' acilir liste olarak var"
}
foreach ($nm in @('st_ThDesc', 'st_DsDesc', 'st_LyDesc', 'st_HomeDesc', 'st_BdDesc', 'st_DsAdv', 'st_DsAdvPanel', 'st_DsReset', 'st_BoardEdit', 'st_BoardReset')) {
    Assert-True ($src.Contains('x:Name="' + $nm + '"')) "ayarlarda '$nm' var"
}
# eski yan yana dugmeler kalmadi
foreach ($old in @('st_Ds_Klasik', 'st_Ds_Atolye', 'st_Pre_Atolye', 'st_Th_Neon', 'st_Ly_Sade', 'st_Zm_100', 'st_Bd_Yok', 'st_Op_100')) { Assert-True (-not $src.Contains('x:Name="' + $old + '"')) "eski yan yana secenek kaldirildi ($old)" }
Assert-True ($src.Contains('$script:SmokeSafeSelect')) 'duman testinin guvenli liste kumesi var'
foreach ($nm in @('st_DesignSel', 'st_HomeSel', 'st_DsNavSel', 'st_DsRadiusSel', 'st_DsFontSel', 'st_DsGraphSel', 'st_DsSkinSel')) { Assert-True ($src.Contains("'" + $nm + "'")) "duman testinin guvenli listelerinde $nm" }

Show-Result
