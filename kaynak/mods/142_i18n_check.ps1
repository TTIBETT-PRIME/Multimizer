# =====================================================================
#  DIL DENETIMI  (Duman testi "dil" kapsami; araclar\Duman-Dil.cmd)
#  Secili dilde her sayfanin ve sekmenin ekran metnini tarar. Yalnizca okur; ayar ya da sistem degistirmez.
#    SIZINTI : Tr'den gecmemis ve Turkce harf iceren metin (cevirisi unutulmus bir yer)
#    KESIK   : metin ekranda tam gorunmuyor (kapsayicisina sigmiyor, kisaltilmis ya da baska bir ogenin kirpmasina giriyor)
#  Sonuc dosyasi: %TEMP%\Multimizer-duman-dil.txt   Cevirisi eksik metinler: %TEMP%\Multimizer-dil-eksik.txt
#  Mantik (yalniz dizge/sayi isleri) arayuzsuz sinanir; ekran olcumleri (WPF) gercek bilgisayarda Duman-Dil.cmd ile calisir.
# =====================================================================

$script:LangScanSteps = 0
$script:LangScanTexts = 0
$script:LangScanFail = 0
$script:LangScanLeaks = New-Object System.Collections.ArrayList
$script:LangScanClips = New-Object System.Collections.ArrayList
$script:LangScanLeakSeen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
$script:LangScanClipSeen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
$script:LangScanLog = New-Object System.Collections.ArrayList

# ---------------- saf mantik (arayuz gerekmez) ----------------

# Sizinti deseni: Turkce harflerin bir kismi baska dillerde de dogaldir (almanca ö ü, fransizca ç ...). Bu dillerde yalnizca
# Turkce'ye ozgu harflere bakilir; Turkce harf kullanan dillerde (az, tk ...) sizinti harf yoluyla anlasilamaz, desen bos doner.
function Get-LangLeakPattern([string]$Code) {
    $p = ([string]$Code).Trim().ToLowerInvariant()
    $i = $p.IndexOf('-')
    if ($i -gt 0) { $p = $p.Substring(0, $i) }
    if ($p -eq '' -or $p -eq 'tr') { return '' }
    $same = @('az', 'tk', 'crh', 'gag', 'ku', 'kmr')
    if ($same -contains $p) { return '' }
    $latin = @('en', 'de', 'fr', 'es', 'it', 'pt', 'nl', 'sv', 'da', 'no', 'nb', 'nn', 'fi', 'pl', 'cs', 'sk', 'hu', 'ro', 'ca', 'id', 'ms', 'vi', 'sl', 'hr', 'et', 'lv', 'lt')
    if ($latin -contains $p) { return '[ğĞıİşŞ]' }
    return '[çğıöşüÇĞİÖŞÜ]'
}

# Ekranda gorunen bir metin sizinti mi? Seen: Tr'den gecen metinler (izleme aciksa); bu kumedeki metin sizinti degildir.
function Test-LangLeakText([string]$Text, [string]$Code, $Seen) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    if ($null -ne $Seen -and $Seen.Contains($Text)) { return $false }
    $pat = Get-LangLeakPattern $Code
    if ($pat -eq '') { return $false }
    return [regex]::IsMatch($Text, $pat)
}

# Raporda tek satira sigan kisa metin
function Format-LangSnippet([string]$Text, [int]$Max) {
    $s = ([string]$Text).Replace("`r", ' ').Replace("`n", ' ').Replace("`t", ' ')
    while ($s.Contains('  ')) { $s = $s.Replace('  ', ' ') }
    $s = $s.Trim()
    if ($Max -lt 8) { $Max = 8 }
    if ($s.Length -gt $Max) { $s = $s.Substring(0, $Max - 3) + '...' }
    return $s
}

# Ogenin gorunen payi: oge dikdortgeni (L,T,R,B) ile kirpma dikdortgeni (L,T,R,B) kesisimi; donus: @(kayipGenislik, kayipYukseklik, gorunenGenislik, gorunenYukseklik)
function Get-LangVisible([double[]]$Box, [double[]]$Clip) {
    $vl = [math]::Max($Box[0], $Clip[0])
    $vt = [math]::Max($Box[1], $Clip[1])
    $vr = [math]::Min($Box[2], $Clip[2])
    $vb = [math]::Min($Box[3], $Clip[3])
    $vw = [math]::Max(0.0, $vr - $vl)
    $vh = [math]::Max(0.0, $vb - $vt)
    $w = $Box[2] - $Box[0]
    $h = $Box[3] - $Box[1]
    return , @(($w - $vw), ($h - $vh), $vw, $vh)
}

# Kayip degerlerinden karar: '' = sorun yok, aksi halde aciklama. Tamamen kirpilan oge (gorunen 0) yalnizca yatayda sorun sayilir
# (dikeyde kapali bolum, kaydirma vb. bilerek gizlenir); gorunen payi olup kirpilan oge her iki eksende sorundur.
function Get-LangClipVerdict([double]$LostW, [double]$LostH, [double]$VisW, [double]$VisH, [double]$Tol, [double]$ClipW = 1000000.0, [double]$ClipH = 1000000.0) {
    # kirpma alani (kapsayicinin gorunen bolumu) neredeyse yoksa oge tasarim geregi gizlidir (sifir genislikli sutun, kapali panel)
    if ($ClipW -le 2.0 -or $ClipH -le 2.0) { return '' }
    if ($VisW -le 0.5 -and $VisH -gt 0.5) { return 'yatayda tamamen dışarıda' }
    if ($VisW -le 0.5 -or $VisH -le 0.5) { return '' }
    $parts = New-Object System.Collections.ArrayList
    if ($LostW -gt $Tol) { [void]$parts.Add('yatay ' + [string][int][math]::Round($LostW) + ' px') }
    if ($LostH -gt $Tol) { [void]$parts.Add('düşey ' + [string][int][math]::Round($LostH) + ' px') }
    if ($parts.Count -eq 0) { return '' }
    return ('kırpılıyor: ' + ($parts.ToArray() -join ', '))
}

# ---------------- WPF olcumleri (yalnizca gercek pencerede) ----------------

function Convert-LangRect($V, $Win, $Rect) {
    if ([object]::ReferenceEquals($V, $Win)) { return $Rect }
    $t = ([System.Windows.Media.Visual]$V).TransformToAncestor($Win)
    return $t.TransformBounds($Rect)
}

function New-LangClipArray([double]$L, [double]$T, [double]$R, [double]$B) {
    return , ([double[]]@($L, $T, $R, $B))
}

# Ogenin ve icindekilerin ekranda gorunebilecegi alan (pencere koordinatlarinda, @(sol, ust, sag, alt)).
# Kirpma kaynaklari: ClipToBounds, kaydirilamayan eksendeki ScrollViewer sinirlari, ogenin kendi yerlesim yuvasindan buyuk olmasi.
function Get-LangClip($El, $Win, $Cache) {
    $winClip = New-LangClipArray 0.0 0.0 ([double]$Win.ActualWidth) ([double]$Win.ActualHeight)
    if ($null -eq $El -or [object]::ReferenceEquals($El, $Win)) { return $winClip }
    if ($Cache.ContainsKey($El)) { return $Cache[$El] }
    $parent = $null
    try { $parent = [System.Windows.Media.VisualTreeHelper]::GetParent($El) } catch { $parent = $null }
    $c = $winClip
    if ($null -ne $parent) { $c = Get-LangClip $parent $Win $Cache }
    $l = [double]$c[0]; $t = [double]$c[1]; $r = [double]$c[2]; $b = [double]$c[3]
    $fe = $El -as [System.Windows.FrameworkElement]
    if ($null -ne $fe -and $null -ne $parent) {
        try {
            $aw = [double]$fe.ActualWidth
            $ah = [double]$fe.ActualHeight
            $own = Convert-LangRect $El $Win (New-Object System.Windows.Rect(0.0, 0.0, $aw, $ah))
            $sv = $fe -as [System.Windows.Controls.ScrollViewer]
            if ($null -ne $sv) {
                $scrX = ($sv.ComputedHorizontalScrollBarVisibility -eq [System.Windows.Visibility]::Visible)
                $scrY = ($sv.ComputedVerticalScrollBarVisibility -eq [System.Windows.Visibility]::Visible)
                # kaydirilabilen eksende icerik gorunum alaninin disina tasabilir (kirpma sayilmaz)
                if ($scrX) { $l = [double]::NegativeInfinity; $r = [double]::PositiveInfinity } else { if ($own.Left -gt $l) { $l = $own.Left }; if ($own.Right -lt $r) { $r = $own.Right } }
                if ($scrY) { $t = [double]::NegativeInfinity; $b = [double]::PositiveInfinity } else { if ($own.Top -gt $t) { $t = $own.Top }; if ($own.Bottom -lt $b) { $b = $own.Bottom } }
            } elseif ($fe.ClipToBounds -and -not ($fe -is [System.Windows.Controls.ScrollContentPresenter])) {
                if ($own.Left -gt $l) { $l = $own.Left }
                if ($own.Top -gt $t) { $t = $own.Top }
                if ($own.Right -lt $r) { $r = $own.Right }
                if ($own.Bottom -lt $b) { $b = $own.Bottom }
            }
            # ogenin kendisi yuvasindan buyukse yuvasina kirpilir
            $slot = [System.Windows.Controls.Primitives.LayoutInformation]::GetLayoutSlot($fe)
            if (-not $slot.IsEmpty) {
                $m = $fe.Margin
                if (($aw + $m.Left + $m.Right) -gt ($slot.Width + 1.5) -or ($ah + $m.Top + $m.Bottom) -gt ($slot.Height + 1.5)) {
                    $sr = Convert-LangRect $parent $Win $slot
                    if ($sr.Left -gt $l) { $l = $sr.Left }
                    if ($sr.Top -gt $t) { $t = $sr.Top }
                    if ($sr.Right -lt $r) { $r = $sr.Right }
                    if ($sr.Bottom -lt $b) { $b = $sr.Bottom }
                }
            }
        } catch { $script:LangScanFail = [int]$script:LangScanFail + 1 }
    }
    $res = New-LangClipArray $l $t $r $b
    $Cache[$El] = $res
    return $res
}

# TextBlock metninin gerektirdigi boyut: ayni yazi tipi ve bicim ayarlariyla kurulan ornek TextBlock olculur
# (FormattedText, TextBlock'tan birkac piksel farkli olcebildigi icin yanlis alarm veriyordu).
# MaxW > 0 ise o genislikte sarilir. Donus: @(genislik, yukseklik)
function Get-LangTextNeed($Tb, [double]$MaxW) {
    $p = New-Object System.Windows.Controls.TextBlock
    $p.Text = [string]$Tb.Text
    $p.FontFamily = $Tb.FontFamily
    $p.FontSize = [double]$Tb.FontSize
    $p.FontStyle = $Tb.FontStyle
    $p.FontWeight = $Tb.FontWeight
    $p.FontStretch = $Tb.FontStretch
    try { $p.FlowDirection = $Tb.FlowDirection } catch { }
    try { $p.Language = $Tb.Language } catch { }
    try {
        $lh = [double]$Tb.LineHeight
        if ($lh -gt 0 -and -not [double]::IsNaN($lh)) { $p.LineHeight = $lh; $p.LineStackingStrategy = $Tb.LineStackingStrategy }
    } catch { }
    try { [System.Windows.Media.TextOptions]::SetTextFormattingMode($p, [System.Windows.Media.TextOptions]::GetTextFormattingMode($Tb)) } catch { }
    $inf = [double]::PositiveInfinity
    if ($MaxW -gt 0) {
        $p.TextWrapping = [System.Windows.TextWrapping]::Wrap
        $p.Measure((New-Object System.Windows.Size($MaxW, $inf)))
    } else {
        $p.TextWrapping = [System.Windows.TextWrapping]::NoWrap
        $p.Measure((New-Object System.Windows.Size($inf, $inf)))
    }
    return , @([double]$p.DesiredSize.Width, [double]$p.DesiredSize.Height)
}

# Bir metin ogesi icin kesik denetimi: '' = sorun yok
function Test-LangClip($El, $Win, $Cache) {
    $fe = $El -as [System.Windows.FrameworkElement]
    if ($null -eq $fe) { return '' }
    $aw = [double]$fe.ActualWidth
    $ah = [double]$fe.ActualHeight
    if ($aw -lt 2 -or $ah -lt 2) { return '' }
    $msgs = New-Object System.Collections.ArrayList
    # 1) ekranda gorunen pay (ust kapsayicilarin kirpmasi dahil)
    $own = Convert-LangRect $El $Win (New-Object System.Windows.Rect(0.0, 0.0, $aw, $ah))
    $box = [double[]]@($own.Left, $own.Top, $own.Right, $own.Bottom)
    $clip = Get-LangClip $El $Win $Cache
    $v = Get-LangVisible $box $clip
    $why = Get-LangClipVerdict ([double]$v[0]) ([double]$v[1]) ([double]$v[2]) ([double]$v[3]) 2.0 ([double]$clip[2] - [double]$clip[0]) ([double]$clip[3] - [double]$clip[1])
    if ($why -ne '') { [void]$msgs.Add($why) }
    # 2) TextBlock: kisaltma ve yukseklik yetersizligi
    $tb = $El -as [System.Windows.Controls.TextBlock]
    if ($null -ne $tb -and ([string]$tb.Text).Length -gt 0) {
        $padW = [double]$tb.Padding.Left + [double]$tb.Padding.Right
        $padH = [double]$tb.Padding.Top + [double]$tb.Padding.Bottom
        $availW = $aw - $padW
        if ([string]$tb.TextWrapping -eq 'NoWrap') {
            if ($availW -ge 4) {
                $need = Get-LangTextNeed $tb 0
                if ([double]$need[0] -gt $availW + 4.0) {
                    $note = ''
                    if ([string]$tb.TextTrimming -ne 'None') { $note = ' (sonu ... ile kısaltılıyor)' }
                    # tanı bilgisi: yanlış alarmı ayıklamak için yazı tipi, satır içi öğe sayısı ve kapsayıcı türü eklenir
                    try {
                        $pt = ''; $tp = ''
                        if ($null -ne $tb.Parent) { $pt = $tb.Parent.GetType().Name }
                        if ($null -ne $tb.TemplatedParent) { $tp = $tb.TemplatedParent.GetType().Name }
                        $note += ' [' + [string]$tb.FontFamily.Source + ' ' + [string]$tb.FontSize + ' ' + [string]$tb.FontWeight + '; satır içi=' + [string]$tb.Inlines.Count + '; gerçek=' + [string][int][math]::Ceiling([double]$tb.DesiredSize.Width) + ' px; üst=' + $pt + '; şablon=' + $tp + ']'
                    } catch { }
                    [void]$msgs.Add(('metin ' + [string][int][math]::Ceiling([double]$need[0]) + ' px, alan ' + [string][int][math]::Floor($availW) + ' px' + $note))
                }
            }
        } elseif ($availW -ge 8) {
            # olcum farki yuzunden dogal genislikte duran metin yanlislikla sarilmasin: 4 px pay verilir
            $need = Get-LangTextNeed $tb ($availW + 4.0)
            $availH = $ah - $padH
            if ([double]$need[1] -gt $availH + 3) { [void]$msgs.Add('yükseklik yetersiz: gereken ' + [string][int][math]::Ceiling([double]$need[1]) + ' px, var ' + [string][int][math]::Floor($availH) + ' px') }
        }
    }
    return ($msgs.ToArray() -join '; ')
}

# Sayfa kokunden (ilk adimda tum pencereden) ekran metinlerini tarar. Where: "sayfa" ya da "sayfa/sekme"
function Invoke-SmokeLangScan([string]$Where) {
    $script:LangScanSteps = [int]$script:LangScanSteps + 1
    $win = $script:Win
    if ($null -eq $win) { return }
    # Sekme/ekran degisiminden hemen sonra olcum eskimis olabilir: tarama oncesi yerlesim zorla guncellenir
    try { $win.UpdateLayout() } catch { }
    $key = $Where
    $i = $key.IndexOf('/')
    if ($i -ge 0) { $key = $key.Substring(0, $i) }
    $root = $win
    if ([int]$script:LangScanSteps -gt 1) {
        $pg = $null
        try { $pg = $script:Pages[$key] } catch { $pg = $null }
        if ($null -ne $pg) { $root = $pg }
    }
    $recs = @(Get-UiTexts $root)
    $cache = New-Object 'System.Collections.Generic.Dictionary[object,object]'
    $code = [string]$script:LangCode
    $nNew = 0
    foreach ($r in $recs) {
        $txt = [string]$r.Text
        $kind = [string]$r.Type
        # 1) sizinti: ayni metin bir kez bildirilir
        if ($script:LangOn) {
            $lk = $txt
            if (-not $script:LangScanLeakSeen.Contains($lk)) {
                if (Test-LangLeakText $txt $code $script:LangSeen) {
                    [void]$script:LangScanLeakSeen.Add($lk)
                    [void]$script:LangScanLeaks.Add(@{ Where = $Where; Kind = $kind; Text = $txt })
                }
            }
        }
        # 2) kesik: yalnizca gorunen ve olculebilen ogeler; ayni sayfada ayni metin bir kez
        if (-not [bool]$r.Visible -or $kind -eq 'ToolTip') { continue }
        $ck = $key + '|' + $kind + '|' + $txt
        if ($script:LangScanClipSeen.Contains($ck)) { continue }
        [void]$script:LangScanClipSeen.Add($ck)
        $nNew++
        $el = $r.Element
        if ($null -eq $el -or -not ($el -is [System.Windows.Controls.TextBlock])) { continue }
        try {
            $why = Test-LangClip $el $win $cache
            if ($why -ne '') { [void]$script:LangScanClips.Add(@{ Where = $Where; Kind = $kind; Text = $txt; Detail = $why }) }
        } catch { $script:LangScanFail = [int]$script:LangScanFail + 1 }
    }
    $script:LangScanTexts = [int]$script:LangScanTexts + $nNew
    $leakN = $script:LangScanLeaks.Count
    $clipN = $script:LangScanClips.Count
    [void]$script:LangScanLog.Add($Where + ': ' + [string]$nNew + ' yeni metin; toplam sızıntı=' + [string]$leakN + ' kesik=' + [string]$clipN)
}

# Sag-sol yazim yonu: dil sagdan sola ise pencere ve sol menu aynalanmis olmali
function Get-LangRtlState {
    $state = @{ Want = [bool]$script:LangRtl; Flow = ''; Mirrored = $false; Rail = '' }
    try {
        $state.Flow = [string]$script:Win.FlowDirection
        $state.Mirrored = ([string]$script:Win.FlowDirection -eq 'RightToLeft')
    } catch { }
    try {
        $rh = $ui.RailHost
        if ($null -ne $rh -and [double]$rh.ActualWidth -gt 1) {
            $rr = Convert-LangRect $rh $script:Win (New-Object System.Windows.Rect(0.0, 0.0, [double]$rh.ActualWidth, [double]$rh.ActualHeight))
            $mid = $rr.Left + ($rr.Width / 2)
            if ($mid -gt ([double]$script:Win.ActualWidth / 2)) { $state.Rail = 'sağ' } else { $state.Rail = 'sol' }
        }
    } catch { }
    return $state
}

function Write-SmokeLangReport {
    if ([int]$script:LangScanSteps -le 0) { return }
    $path = Join-Path ([System.IO.Path]::GetTempPath()) 'Multimizer-duman-dil.txt'
    $nl = "`r`n"
    $sb = New-Object System.Text.StringBuilder
    $on = [bool]$script:LangOn
    $cov = ''
    $nPack = 0
    try { if ($null -ne $script:LangPrimary) { $nPack = [int]$script:LangPrimary.N; $cov = [string]$script:LangPrimary.Meta['coverage'] } } catch { }
    $rtl = Get-LangRtlState
    $dirWant = 'soldan sağa'
    if ($rtl.Want) { $dirWant = 'sağdan sola' }
    $leakN = $script:LangScanLeaks.Count
    $clipN = $script:LangScanClips.Count
    $missN = 0
    try { if ($null -ne $script:LangMiss) { $missN = $script:LangMiss.Count } } catch { }
    [void]$sb.Append('MULTIMIZER DIL DENETIMI' + $nl)
    [void]$sb.Append('dil=' + [string]$script:LangCode + ' (' + [string]$script:LangName + ')  etiket=' + [string]$script:LangTag + '  etkin=' + [string]$on + '  paket=' + [string]$nPack + ' kayıt  kapsam=%' + $cov + $nl)
    [void]$sb.Append('yazım yönü: istenen=' + $dirWant + '  pencere=' + [string]$rtl.Flow + '  sol menü konumu=' + [string]$rtl.Rail + $nl)
    [void]$sb.Append('taranan adım=' + [string]$script:LangScanSteps + '  metin=' + [string]$script:LangScanTexts + '  denetim hatası=' + [string]$script:LangScanFail + $nl)
    [void]$sb.Append('OZET dil=' + [string]$script:LangCode + ' metin=' + [string]$script:LangScanTexts + ' sizinti=' + [string]$leakN + ' kesik=' + [string]$clipN + ' eksik=' + [string]$missN + ' kapsam=' + $cov + $nl)
    [void]$sb.Append($nl + '--- SIZINTI: Tr işlevinden geçmeyen, Türkçe harfli metinler (' + [string]$leakN + ') ---' + $nl)
    if (-not $on) { [void]$sb.Append('(Türkçe: karşılaştırma dili; sızıntı denetimi yapılmaz)' + $nl) }
    foreach ($x in $script:LangScanLeaks) { [void]$sb.Append('[' + [string]$x.Where + '] ' + [string]$x.Kind + ' | ' + (Format-LangSnippet ([string]$x.Text) 200) + $nl) }
    [void]$sb.Append($nl + '--- KESIK: ekrana sığmayan ya da kırpılan metinler (' + [string]$clipN + ') ---' + $nl)
    foreach ($x in $script:LangScanClips) { [void]$sb.Append('[' + [string]$x.Where + '] ' + [string]$x.Kind + ' | ' + [string]$x.Detail + ' | ' + (Format-LangSnippet ([string]$x.Text) 120) + $nl) }
    [void]$sb.Append($nl + '--- ADIMLAR ---' + $nl)
    foreach ($x in $script:LangScanLog) { [void]$sb.Append([string]$x + $nl) }
    $wrote = $false
    try { [System.IO.File]::WriteAllText($path, $sb.ToString(), (New-Object System.Text.UTF8Encoding($true))); $wrote = $true } catch { }
    try { [void](Save-LangMiss) } catch { }
    Add-SmokeLine ('--- dil denetimi: dil=' + [string]$script:LangCode + '  metin=' + [string]$script:LangScanTexts + '  sızıntı=' + [string]$leakN + '  kesik=' + [string]$clipN + '  eksik=' + [string]$missN + '  (ayrıntı: ' + $path + ')')
    if ($leakN -gt 0) { Add-SmokeWarn ('dil: ' + [string]$leakN + ' metin Tr işlevinden geçmeden ekrana çıktı') }
    if ($clipN -gt 0) { Add-SmokeWarn ('dil: ' + [string]$clipN + ' metin ekrana sığmıyor ya da kırpılıyor') }
    # sagdan sola dil: pencere gercekten aynalanmis olmali; tersi de hatadir
    if ($on -and ([bool]$rtl.Want -ne [bool]$rtl.Mirrored)) { Add-SmokeError 'dil' ('yazım yönü uyuşmuyor: dil sağdan sola=' + [string]$rtl.Want + ', pencere=' + [string]$rtl.Flow) }
    if ($on -and [bool]$rtl.Want -and [string]$rtl.Rail -eq 'sol') { Add-SmokeWarn 'sağdan sola dilde sol menü hâlâ solda görünüyor' }
    if (-not $wrote) { Add-SmokeWarn 'dil raporu dosyası yazılamadı' }
}
