# ==================================================================
#  UST CUBUK (arayuz): ana sayfa emblemi ve dil secici
#  Sol ustteki Multimizer emblemi ana sayfa dugmesidir: baska sayfadayken durum panosunu acar, zaten oradaysa sayfayi en uste kaydirir.
#  KULLANICI | UZMAN kapsulunun yanindaki dil dugmesi acilir listeyi gosterir; secim yeniden baslatmayla uygulanir
#  (Windows dili zaten secilen dilse yalnizca ayar yazilir). Satirlar 145_header_core.ps1 modelinden kurulur.
# ==================================================================
$script:LangPopClosedAt = [datetime]::MinValue
$script:LangPopFocus = $null

$script:LangRowXaml = @'
<Button xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Style="{DynamicResource BtnRow}" Padding="8,6" Margin="0,1">
  <Grid MinWidth="248">
    <Grid.ColumnDefinitions>
      <ColumnDefinition Width="24"/>
      <ColumnDefinition Width="*"/>
      <ColumnDefinition Width="Auto"/>
    </Grid.ColumnDefinitions>
    <ContentControl x:Name="RowCheck" Style="{DynamicResource Icon}" Tag="{DynamicResource IcoCheck}" Width="14" Height="14" Foreground="{DynamicResource BrAccent}" HorizontalAlignment="Left" VerticalAlignment="Center" Visibility="Hidden"/>
    <StackPanel Grid.Column="1" VerticalAlignment="Center">
      <TextBlock x:Name="RowName" Text="" FontSize="13" FontWeight="SemiBold" Foreground="{DynamicResource BrText}" TextTrimming="CharacterEllipsis"/>
      <TextBlock x:Name="RowSub" Text="" FontSize="11" Foreground="{DynamicResource BrDim}" Margin="0,1,0,0" TextTrimming="CharacterEllipsis"/>
    </StackPanel>
    <Border x:Name="RowChip" Grid.Column="2" Margin="12,0,0,0" Padding="6,1" CornerRadius="4" BorderThickness="1" BorderBrush="{DynamicResource BrLine}" VerticalAlignment="Center">
      <TextBlock x:Name="RowChipText" Text="" FontSize="10.5" FontWeight="SemiBold" Foreground="{DynamicResource BrDim}"/>
    </Border>
  </Grid>
</Button>
'@

# Modelden bir liste satiri kurar (metinler kodla atanir: dil adlari ceviriden gecmez)
function New-LangRow($M) {
    $row = Read-LocalXaml ($script:LangRowXaml)
    $row.Tag = [string]$M.Code
    $row.FindName('RowName').Text = [string]$M.Name
    $row.FindName('RowSub').Text = [string]$M.Sub
    $chip = $row.FindName('RowChip')
    $chipText = $row.FindName('RowChipText')
    if ([string]$M.Chip -eq '') { $chip.Visibility = $script:VisOff } else { $chipText.Text = [string]$M.Chip }
    if ([bool]$M.Checked) {
        $row.SetResourceReference([System.Windows.Controls.Control]::BackgroundProperty, 'BrActiveBg')
        $row.FindName('RowCheck').Visibility = $script:VisOn
        $chip.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, 'BrAccentDim')
        $chipText.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'BrAccent')
    }
    $row.Add_Click($script:H_LangRow)
    return , $row
}

$script:H_LangRow = {
    param($s, $e)
    Invoke-Safe { Select-LangRow ([string]$s.Tag) } 'Dil'
}

function Select-LangRow([string]$Code) {
    Close-LangMenu
    [void](Request-LangChange $Code)
}

# Listeyi modelden yeniden kurar (her acilista; ayar ya da dil dosyalari degismis olabilir)
function Update-LangMenu {
    if ($null -eq $ui.LangItems) { return }
    $stack = $ui.LangItems
    $stack.Children.Clear()
    $script:LangPopFocus = $null
    foreach ($m in @(Get-LangMenuModel)) {
        $row = New-LangRow $m
        if ($null -eq $row) { continue }
        [void]$stack.Children.Add($row)
        if ([bool]$m.Checked -and $null -eq $script:LangPopFocus) { $script:LangPopFocus = $row }
    }
    if ($null -eq $script:LangPopFocus -and $stack.Children.Count -gt 0) { $script:LangPopFocus = $stack.Children[0] }
}

# Dil dugmesinin yazisi (calisan dilin kisa kodu) ve aracipucu
function Update-LangButton {
    if ($null -eq $ui.BtnLang -or $null -eq $ui.TxtLangCode) { return }
    $info = Get-LangButtonInfo
    $ui.TxtLangCode.Text = [string]$info.Code
    $ui.BtnLang.ToolTip = [string]$info.Tip
    try { [System.Windows.Automation.AutomationProperties]::SetName($ui.BtnLang, [string]$info.Tip) } catch { }
}

function Set-LangPopFocus {
    $el = $script:LangPopFocus
    if ($null -eq $el) { return }
    try { [void]$el.Focus() } catch { }
}

function Close-LangMenu {
    if ($null -ne $ui.LangPop -and $ui.LangPop.IsOpen) { $ui.LangPop.IsOpen = $false }
}

# Dugme: liste aciksa kapatir, kapaliysa acar
function Show-LangMenu {
    $pop = $ui.LangPop
    if ($null -eq $pop -or $null -eq $ui.LangCapsule) { return }
    if ($pop.IsOpen) { $pop.IsOpen = $false; return }
    # StaysOpen=False: dugmenin uzerine tiklamak acik listeyi once kapatir, ayni tiklama ardindan Click olarak gelir; liste hemen yeniden acilmasin
    if (([datetime]::UtcNow - $script:LangPopClosedAt).TotalMilliseconds -lt 300) { return }
    Update-LangMenu
    try { Close-NavMenu } catch { }
    $pop.PlacementTarget = $ui.LangCapsule
    $pop.IsOpen = $true
}

function Get-LangShownName([string]$Key) {
    if ($Key -eq 'auto') { return (Tr 'Otomatik') }
    foreach ($l in @(Get-LangList)) { if ([string]$l.Code -eq $Key) { return [string]$l.Native } }
    return $Key
}

# Dil secimini uygular. Donus: 'yok' | 'ayni' | 'kaydet' | 'mesgul' | 'yeniden' (onay penceresi acildi)
function Request-LangChange([string]$Key) {
    $plan = Get-LangChangePlan $Key
    $k = $Key.Trim().ToLowerInvariant()
    if ($plan -eq 'yok') { Show-Toast 'Bu dil kullanılamıyor.' 'warn'; return $plan }
    if ($plan -eq 'ayni') { return $plan }
    if ($plan -eq 'kaydet') {
        # arayuz dili degismiyor (ornek: Otomatik <-> Turkce, Windows dili zaten bu): yeniden baslatmaya gerek yok
        $script:Settings.Language = $k
        Save-Settings $script:Settings
        $msg = Format-Tr 'Dil tercihi kaydedildi: {0}' (Get-LangShownName $k)
        Add-LangNameOut $msg
        Show-Toast $msg 'good'
        try { Update-LangButton } catch { }
        return $plan
    }
    $busy = $false
    try { $busy = [bool](Test-AsyncBusy) } catch { $busy = $false }
    if ($busy) { Show-Toast 'Çalışan bir işlem var; bitince dili değiştirin.' 'warn'; return 'mesgul' }
    Confirm-LangRestart $k
    return $plan
}

# Emblem: baska sayfadaysa durum panosunu acar; zaten ana sayfadaysa en uste kaydirir
function Invoke-HomeClick {
    try { Close-NavMenu } catch { }
    try { Close-LangMenu } catch { }
    $cur = [string]$script:UiState.Page
    if ($cur -eq 'panel' -or $cur -eq 'board') {
        $sv = $null
        try { $sv = Get-PageScroller 0 } catch { $sv = $null }
        if ($null -ne $sv) { try { $sv.ScrollToVerticalOffset(0) } catch { } }
    } else {
        Show-Page 'panel'
    }
    try { Focus-PageHost } catch { }
}

function Initialize-HeaderBar {
    if ($null -ne $ui.BtnHome) {
        $ui.BtnHome.Add_Click({ Invoke-Safe { Invoke-HomeClick } 'Ana sayfa' })
        try { [System.Windows.Automation.AutomationProperties]::SetName($ui.BtnHome, (Tr 'Ana sayfa')) } catch { }
    }
    if ($null -ne $ui.BtnLang) {
        $ui.BtnLang.Add_Click({ Invoke-Safe { Show-LangMenu } 'Dil' })
    }
    if ($null -ne $ui.LangPop) {
        $ui.LangPop.Add_Opened({ try { $ui.BtnLang.Tag = 'open'; Set-LangPopFocus } catch { } })
        $ui.LangPop.Add_Closed({ try { $script:LangPopClosedAt = [datetime]::UtcNow; $ui.BtnLang.Tag = '' } catch { } })
        if ($null -ne $ui.LangPop.Child) {
            $ui.LangPop.Child.Add_PreviewKeyDown({
                param($s, $e)
                if ($e.Key -eq [System.Windows.Input.Key]::Escape) {
                    try { Close-LangMenu; [void]$ui.BtnLang.Focus() } catch { }
                    $e.Handled = $true
                }
            })
        }
    }
    Update-LangButton
    try { Update-LangMenu } catch { Write-CrashLog ('Dil listesi: ' + $_.Exception.Message) }
}

# ---------------- duman testi: ust cubuk denetimleri ----------------
# Bir ogenin goruntusunu PNG olarak kaydeder (acilir listeler pencere agacinda olmadigi icin pencere goruntusunde yer almaz)
function Save-SmokeShotOf($El, [string]$Name) {
    try {
        $pw = [int][math]::Ceiling([double]$El.ActualWidth)
        $ph = [int][math]::Ceiling([double]$El.ActualHeight)
        if ($pw -lt 20 -or $ph -lt 20) { Add-SmokeError 'ust cubuk' ('görüntü alınamadı, öğe ölçülmemiş: ' + $Name); return }
        $bmp = New-Object System.Windows.Media.Imaging.RenderTargetBitmap($pw, $ph, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
        $bmp.Render($El)
        $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
        $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($bmp))
        $fs = [System.IO.File]::Create((Join-Path $script:SmokeDir ($Name + '.png')))
        try { $enc.Save($fs) } finally { $fs.Dispose() }
        $script:SmokeShots = $script:SmokeShots + 1
    } catch { Add-SmokeError 'ust cubuk' $_.Exception.Message }
}

function Test-SmokeHeader([string]$What) {
    if ($What -eq 'home') {
        $want = 'panel'
        try { if (Test-BoardHome) { $want = 'board' } } catch { }
        $cur = [string]$script:UiState.Page
        if ($cur -ne $want) { Add-SmokeError 'ust cubuk' ('ana sayfa emblemi durum panosunu açmadı: ' + $cur + ' (beklenen ' + $want + ')') }
        else { Add-SmokeLine '      üst çubuk: ana sayfa emblemi durum panosunu açtı' }
        if ($null -eq $ui.BtnHome -or [double]$ui.BtnHome.ActualWidth -lt 40 -or $ui.BtnHome.IsVisible -ne $true) { Add-SmokeError 'ust cubuk' 'ana sayfa düğmesi görünmüyor' }
        return
    }
    if ($What -eq 'lang') {
        $b = $ui.BtnLang
        if ($null -eq $b -or $b.IsVisible -ne $true -or [double]$b.ActualWidth -lt 30) { Add-SmokeError 'ust cubuk' 'dil düğmesi görünmüyor'; return }
        $code = [string]$ui.TxtLangCode.Text
        $want = Get-LangShortCode ([string]$script:LangCode)
        if ($code -ne $want) { Add-SmokeError 'ust cubuk' ('dil düğmesindeki kod ' + $code + ', beklenen ' + $want) }
        if ([string]$b.ToolTip -eq '') { Add-SmokeError 'ust cubuk' 'dil düğmesinin ipucu boş' }
        # kapsul, KULLANICI | UZMAN kapsuluyla ayni yukseklikte olmali (ayni satirda duzgun hizalanir)
        $mode = $ui.SegUser.Parent.Parent
        $hm = [double]$mode.ActualHeight
        $hl = [double]$ui.LangCapsule.ActualHeight
        if ([math]::Abs($hm - $hl) -gt 1.5) { Add-SmokeError 'ust cubuk' ('dil kapsülü ' + [string][int]$hl + ' px, kip kapsülü ' + [string][int]$hm + ' px: yükseklikler eşit değil') }
        Add-SmokeLine ('      üst çubuk: dil düğmesi ' + $code + ' (' + [string][int]$ui.LangCapsule.ActualWidth + ' x ' + [string][int]$hl + ' px, kip kapsülü ' + [string][int]$hm + ' px)')
        return
    }
    Add-SmokeError 'ust cubuk' ('bilinmeyen denetim: ' + $What)
}

function Test-SmokeLangPop([string]$What) {
    $pop = $ui.LangPop
    if ($null -eq $pop -or $null -eq $ui.BtnLang -or $null -eq $ui.LangItems) { Add-SmokeError 'ust cubuk' 'dil listesi ya da düğmesi yok'; return }
    Show-LangMenu
    if (-not $pop.IsOpen) { Add-SmokeError 'ust cubuk' 'dil listesi açılmadı'; return }
    try { [void]$script:Win.Dispatcher.Invoke([System.Action]{ }, [System.Windows.Threading.DispatcherPriority]::Render) } catch { }
    $c = $pop.Child
    try { $c.UpdateLayout() } catch { }
    $need = @(Get-LangList).Count + 1
    $got = $ui.LangItems.Children.Count
    if ($got -ne $need) { Add-SmokeError 'ust cubuk' ('dil listesinde ' + [string]$got + ' satır var, beklenen ' + [string]$need) }
    $marked = 0
    foreach ($r in $ui.LangItems.Children) { if ($r.FindName('RowCheck').Visibility -eq $script:VisOn) { $marked++ } }
    if ($marked -ne 1) { Add-SmokeError 'ust cubuk' ('dil listesinde ' + [string]$marked + ' satır işaretli, beklenen 1') }
    if ([string]$ui.BtnLang.Tag -ne 'open') { Add-SmokeError 'ust cubuk' 'liste açıkken dil düğmesi etkin görünümde değil' }
    if ([double]$c.ActualWidth -lt 50) {
        # acilir pencerenin yerlesimi henuz olusmadiysa elle olculur
        try {
            $c.Measure((New-Object System.Windows.Size([double]::PositiveInfinity, [double]::PositiveInfinity)))
            $c.Arrange((New-Object System.Windows.Rect(0.0, 0.0, [double]$c.DesiredSize.Width, [double]$c.DesiredSize.Height)))
        } catch { }
    }
    Save-SmokeShotOf $c ('ust-dil-listesi-' + [string]$script:LangCode)
    # gercek ekran goruntusu: acik liste pencerenin ustunde nasil duruyor (acilir pencere RenderTargetBitmap goruntusune girmez).
    # Acilir pencere once yuklenir, sonra Fade animasyonuyla belirir: yerlesim ve cizim bitsin, masaustu bileseni kareyi sunsun, sonra goruntu alinir.
    # (animasyon saati arayuz is parcacigiyla ilerler: uyku sirasinda kare uretilmez, bu yuzden kisa uykularla art arda bosaltilir)
    for ($i = 0; $i -lt 16; $i++) { Invoke-SmokeFlush; Start-Sleep -Milliseconds 50 }
    Start-Sleep -Milliseconds 120
    if (-not $pop.IsOpen) { Add-SmokeLine '      üst çubuk: liste ekran görüntüsünden önce kapandı (pencere etkinliğini yitirdi)' }
    Save-SmokeScreen ('ust-dil-listesi-' + [string]$script:LangCode)
    # ceviri sizintisi: listedeki her metin
    if ($script:LangOn -and $null -ne $script:LangScanLeaks) {
        $code = [string]$script:LangCode
        foreach ($r in @(Get-UiTexts $c)) {
            $txt = [string]$r.Text
            if ($script:LangScanLeakSeen.Contains($txt)) { continue }
            if (Test-LangLeakText $txt $code $script:LangSeen) {
                [void]$script:LangScanLeakSeen.Add($txt)
                [void]$script:LangScanLeaks.Add(@{ Where = 'üst çubuk / dil listesi'; Kind = [string]$r.Type; Text = $txt })
            }
        }
    }
    Add-SmokeLine ('      üst çubuk: dil listesi açıldı (' + [string]$got + ' satır, ' + [string][int]$c.ActualWidth + ' x ' + [string][int]$c.ActualHeight + ' px), kapatılıyor')
    Close-LangMenu
    if ($pop.IsOpen) { Add-SmokeError 'ust cubuk' 'dil listesi kapanmadı' }
}
