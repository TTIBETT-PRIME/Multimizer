# ==================================================================
#  KULLANIM KOLAYLIGI (arayuz): Asistan (ust cubuk, sohbet bicimli), sol cubukta uzerine gelince acilan menuler,
#  uzun aciklamalarin tek satira inmesi ve tamaminin ipucunda gosterilmesi.
#  Cekirdek (saf) islevler: 152_assist_core.ps1
# ==================================================================

# ---------------- kisa aciklamalar ----------------
# Uzun aciklama tek satira iner; tamami, satirin uzerinde bekleyince ipucunda gorunur (ipucu metne baglidir, metin degisirse guncellenir).
function Set-TextCompact($Tb, $TipOwner) {
    if ($null -eq $Tb -or $Tb -isnot [System.Windows.Controls.TextBlock]) { return $false }
    if (-not (Test-DescLong ([string]$Tb.Text))) { return $false }
    $Tb.TextWrapping = [System.Windows.TextWrapping]::NoWrap
    $Tb.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
    $tip = New-Object System.Windows.Controls.TextBlock
    $tip.TextWrapping = [System.Windows.TextWrapping]::Wrap
    $tip.MaxWidth = 340
    $b = New-Object System.Windows.Data.Binding -ArgumentList 'Text'
    $b.Source = $Tb
    [void]$tip.SetBinding([System.Windows.Controls.TextBlock]::TextProperty, $b)
    $own = $TipOwner
    if ($null -eq $own) { $own = $Tb }
    $own.ToolTip = $tip
    [System.Windows.Controls.ToolTipService]::SetInitialShowDelay($own, 450)
    [System.Windows.Controls.ToolTipService]::SetShowDuration($own, 30000)
    return $true
}

function Test-FullDesc { return ($script:Settings.FullDesc -eq $true) }

# Liste satiri: aciklama (Det) tek satir, tamami satirin ipucunda
function Set-DescCompact($El) {
    if ((Test-FullDesc) -or $null -eq $El -or $El -isnot [System.Windows.FrameworkElement]) { return }
    $det = $null
    try { $det = $El.FindName('Det') } catch { $det = $null }
    if ($null -eq $det) { return }
    [void](Set-TextCompact $det $El)
}

# Sayfa: Add-DescTags ile isaretlenmis aciklama paragraflari
function Set-PageDescCompact($Root) {
    if ((Test-FullDesc) -or $null -eq $Root) { return 0 }
    $n = 0
    $stack = New-Object System.Collections.Stack
    $stack.Push($Root)
    $guard = 0
    while ($stack.Count -gt 0 -and $guard -lt 20000) {
        $guard++
        $cur = $stack.Pop()
        if ($cur -is [System.Windows.Controls.TextBlock]) {
            if ([string]$cur.Tag -eq 'desc') { if (Set-TextCompact $cur $null) { $n++ } }
            continue
        }
        if ($cur -isnot [System.Windows.DependencyObject]) { continue }
        foreach ($ch in [System.Windows.LogicalTreeHelper]::GetChildren($cur)) { if ($ch -is [System.Windows.DependencyObject]) { $stack.Push($ch) } }
    }
    return $n
}

# ---------------- uzerine gelince acilan menu ----------------
$script:HoverPop = $null
$script:HoverTarget = $null
$script:HoverTimer = $null
$script:HoverWatch = $null
$script:HoverPending = $null
$script:HoverMiss = 0
$script:HoverPin = $false

$script:HoverPopXaml = @'
<Popup xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
       StaysOpen="True" AllowsTransparency="True" PopupAnimation="Fade" Placement="Right" HorizontalOffset="-6">
  <Border Background="{DynamicResource BrPanel2}" BorderBrush="{DynamicResource BrLine2}" BorderThickness="1" CornerRadius="12" Padding="6" Margin="8" MinWidth="210" MaxHeight="560">
    <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
      <StackPanel x:Name="Items"/>
    </ScrollViewer>
  </Border>
</Popup>
'@

$script:HoverItemXaml = @'
<Button xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Style="{DynamicResource BtnRow}" Tag="@@Tag@@" Padding="12,7">
  <TextBlock Text="@@Text@@" FontSize="12.5" Foreground="{DynamicResource BrText}"/>
</Button>
'@

function Close-HoverMenu {
    try { if ($null -ne $script:HoverWatch) { $script:HoverWatch.Stop() } } catch { }
    if ($null -ne $script:HoverPop) { $script:HoverPop.IsOpen = $false }
    $script:HoverTarget = $null
}

function Get-HoverPopup {
    if ($null -ne $script:HoverPop) { return $script:HoverPop }
    $pop = Read-LocalXaml ($script:HoverPopXaml)
    [void]$ui.BodyGrid.Children.Add($pop)
    $script:HoverPop = $pop
    return $pop
}

# Items: @(@{ Head }) ya da @(@{ Text; Tag }).  Fare hedefin ve menunun disina cikinca kendiliginden kapanir.
function Show-HoverMenu($Target, $Items) {
    $list = @($Items)
    if ($null -eq $Target -or $list.Count -eq 0) { return }
    $pop = Get-HoverPopup
    $pop.IsOpen = $false
    $stack = $pop.FindName('Items')
    $stack.Children.Clear()
    foreach ($it in $list) {
        if ($it.ContainsKey('Head')) {
            [void]$stack.Children.Add((Read-LocalXaml ((Expand-Template $script:NavHeadXaml @{ Text = [string]$it.Head }))))
            continue
        }
        $b = Read-LocalXaml ((Expand-Template $script:HoverItemXaml @{ Tag = [string]$it.Tag; Text = [string]$it.Text }))
        $b.Add_Click({ param($s, $e) Invoke-Safe { $t = [string]$s.Tag; Close-HoverMenu; Invoke-MenuTag $t } 'Menü' })
        [void]$stack.Children.Add($b)
    }
    $pop.PlacementTarget = $Target
    $script:HoverTarget = $Target
    $script:HoverMiss = 0
    $pop.IsOpen = $true
    if ($null -eq $script:HoverWatch) {
        $script:HoverWatch = New-Object System.Windows.Threading.DispatcherTimer
        $script:HoverWatch.Interval = [TimeSpan]::FromMilliseconds(220)
        $script:HoverWatch.Add_Tick({
            try {
                $over = $false
                try { if ($null -ne $script:HoverTarget -and $script:HoverTarget.IsMouseOver) { $over = $true } } catch { }
                try { if (-not $over -and $null -ne $script:HoverPop -and $null -ne $script:HoverPop.Child -and $script:HoverPop.Child.IsMouseOver) { $over = $true } } catch { }
                if ($script:HoverPin -eq $true) { return }
                if ($over) { $script:HoverMiss = 0 } else { $script:HoverMiss++ }
                if ($script:HoverMiss -ge 2 -or ($null -ne $script:Win -and -not $script:Win.IsActive)) { Close-HoverMenu }
            } catch { Close-HoverMenu }
        })
    }
    $script:HoverWatch.Stop(); $script:HoverWatch.Start()
}

# Bekleme suresi dolunca calisir: fare hala hedefin uzerindeyse menuyu acar
function Start-HoverDwell($Target, [scriptblock]$Action, [int]$Ms = 320) {
    $script:HoverPending = @{ Target = $Target; Action = $Action }
    if ($null -eq $script:HoverTimer) {
        $script:HoverTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:HoverTimer.Add_Tick({
            try {
                $script:HoverTimer.Stop()
                $p = $script:HoverPending
                $script:HoverPending = $null
                if ($null -eq $p -or $null -eq $p.Target -or -not $p.Target.IsMouseOver) { return }
                if ($null -ne $ui.Overlay -and $ui.Overlay.Visibility -eq $script:VisOn) { return }
                & $p.Action $p.Target
            } catch { Write-CrashLog ('Hover: ' + $_.Exception.Message) }
        })
    }
    $script:HoverTimer.Stop()
    $script:HoverTimer.Interval = [TimeSpan]::FromMilliseconds($Ms)
    $script:HoverTimer.Start()
}

# Sayfanin alt sekmeleri (sayfa XAML'inden; sayfa acilmamis olsa da okunur)
$script:PageSubCache = @{}
function Get-RailSubItems([string]$Page) {
    if ($script:PageSubCache.ContainsKey($Page)) { return $script:PageSubCache[$Page] }
    $items = New-Object System.Collections.ArrayList
    try {
        $xaml = [string](Get-Variable -Scope Script -Name ('Page_' + $Page) -ValueOnly -ErrorAction Stop)
        $tabs = Get-PageSubTabs $xaml
        foreach ($t in @($tabs)) { [void]$items.Add(@{ Text = [string]$t.Text; Tag = ('sub:' + $Page + ':' + [string]$t.Key) }) }
    } catch { }
    $arr = $items.ToArray()
    $script:PageSubCache[$Page] = $arr
    return $arr
}

# Kipe gore gorunen alt sekmeler: Araclar sayfasinda kullanici kipinde yalnizca gundelik sekmeler listelenir
function Get-RailSubItemsShown([string]$Page) {
    $all = Get-RailSubItems $Page
    if ($Page -ne 'tools' -or $script:UiState.Mode -eq 'Expert') { return @($all) }
    $vis = @(Get-TlVisibleTabs $false)
    return @(@($all) | Where-Object { $vis -contains ([string]$_.Tag).Substring(([string]$_.Tag).LastIndexOf(':') + 1) })
}

$script:H_RailPageEnter = {
    param($s, $e)
    try {
        $page = [string]$s.Tag
        if ($page -eq '') { return }
        Start-HoverDwell $s {
            param($t)
            $pg = [string]$t.Tag
            $items = @(Get-RailSubItemsShown $pg)
            if ($items.Count -lt 2) { Close-HoverMenu; return }
            Show-HoverMenu $t (@(@{ Head = (ConvertTo-TrUpper ([string]$script:PageNames[$pg])) }) + $items)
        } 380
    } catch { }
}

# Kapali grup basliginin uzerinde beklenince grup yerinde acilir; fare sol cubuktan cikinca (sayfasi acik degilse) yeniden kapanir
$script:H_RailHdrEnter = {
    param($s, $e)
    try {
        Start-HoverDwell $s {
            param($t)
            foreach ($g in @($script:RailGroups)) {
                if ([string]$g.Key -eq [string]$t.Tag -and -not [bool]$g.Open) {
                    Set-GroupOpen $g $true
                    $g.Peek = $true
                    $script:RailH = 0
                    try { Update-RailDensity } catch { }
                }
            }
        } 220
    } catch { }
}

$script:RailLeaveTimer = $null
function Close-RailPeek {
    $changed = $false
    foreach ($g in @($script:RailGroups)) {
        if ($g.Peek -eq $true) {
            $g.Peek = $false
            if ([bool]$g.Open -and -not ($g.Pages -contains [string]$script:UiState.Page)) { Set-GroupOpen $g $false; $changed = $true }
        }
    }
    if ($changed) { $script:RailH = 0; try { Update-RailDensity } catch { } }
}

$script:H_RailLeave = {
    param($s, $e)
    try {
        if ($null -eq $script:RailLeaveTimer) {
            $script:RailLeaveTimer = New-Object System.Windows.Threading.DispatcherTimer
            $script:RailLeaveTimer.Interval = [TimeSpan]::FromMilliseconds(650)
            $script:RailLeaveTimer.Add_Tick({
                try {
                    $script:RailLeaveTimer.Stop()
                    $over = $false
                    try { if ($ui.RailScroll.IsMouseOver) { $over = $true } } catch { }
                    try { if (-not $over -and $null -ne $script:HoverPop -and $script:HoverPop.IsOpen -and $script:HoverPop.Child.IsMouseOver) { $over = $true } } catch { }
                    if (-not $over) { Close-RailPeek }
                } catch { }
            })
        }
        $script:RailLeaveTimer.Stop(); $script:RailLeaveTimer.Start()
    } catch { }
}

# Kullanici basliga tiklarsa secim kalicidir (fare cikinca kapanmaz)
function Clear-RailPeek([string]$Key) {
    foreach ($g in @($script:RailGroups)) { if ([string]$g.Key -eq $Key) { $g.Peek = $false } }
}

$script:RailHoverOn = $false
function Initialize-RailHover {
    if ($script:RailHoverOn) { return }
    $script:RailHoverOn = $true
    foreach ($k in @($script:PageTitles.Keys)) {
        $rb = $ui['Rail_' + $k]
        if ($null -eq $rb) { continue }
        if ([string]$rb.Tag -eq '') { $rb.Tag = [string]$k }
        if ([string]$rb.Tag -ne [string]$k) { continue }
        if (@(Get-RailSubItems ([string]$k)).Count -lt 2) { continue }
        $rb.Add_MouseEnter($script:H_RailPageEnter)
        try { [System.Windows.Controls.ToolTipService]::SetIsEnabled($rb, $false) } catch { }
    }
    if ($null -ne $ui.RailScroll) { $ui.RailScroll.Add_MouseLeave($script:H_RailLeave) }
}

# Atolye tasarimindaki simge menusu: uzerine gelince grubun sayfalari
$script:H_FlyHover = {
    param($s, $e)
    try {
        Start-HoverDwell $s {
            param($t)
            $expert = ([string]$script:UiState.Mode -eq 'Expert')
            $items = New-Object System.Collections.ArrayList
            foreach ($it in @(Get-NavMenuItems ([string]$t.Tag) $expert)) { if (-not $it.ContainsKey('Head')) { [void]$items.Add(@{ Text = [string]$it.Text; Tag = [string]$it.Tag }) } }
            if ($items.Count -ge 2) { Show-HoverMenu $t $items.ToArray() }
        } 300
    } catch { }
}

# ---------------- Asistan ----------------
$script:AskUserXaml = @'
<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" HorizontalAlignment="Right" Background="{DynamicResource BrActiveBg}" CornerRadius="12,12,3,12" Padding="12,7" Margin="70,8,0,2">
  <TextBlock Text="@@Text@@" TextWrapping="Wrap" Foreground="{DynamicResource BrText}" FontSize="13"/>
</Border>
'@

$script:AskBotXaml = @'
<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" HorizontalAlignment="Left" Background="{DynamicResource BrCard}" BorderBrush="{DynamicResource BrLine}" BorderThickness="1" CornerRadius="12,12,12,3" Padding="14,10" Margin="0,4,46,6">
  <StackPanel>
    <TextBlock x:Name="Ttl" Text="@@Title@@" FontWeight="SemiBold" FontSize="13.5" Foreground="{DynamicResource BrText}" TextWrapping="Wrap"/>
    <TextBlock x:Name="Body" Text="@@Text@@" TextWrapping="Wrap" FontSize="12.5" Foreground="{DynamicResource BrDim}" Margin="0,4,0,0" LineHeight="19"/>
    <WrapPanel x:Name="Acts" Margin="0,9,0,0"/>
  </StackPanel>
</Border>
'@

$script:AskActXaml = @'
<Button xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Style="{DynamicResource BtnMini}" Content="@@Text@@" Tag="@@Tag@@" Margin="0,0,6,6" Padding="11,5"/>
'@

$script:AskChipXaml = @'
<Button xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Style="{DynamicResource BtnGhost}" Content="@@Text@@" Tag="@@Tag@@" Margin="0,0,6,6" Padding="10,4" FontSize="11.5"/>
'@

$script:AskReady = $false

function Add-AskUser([string]$Text) {
    $el = Read-LocalXaml ((Expand-Template $script:AskUserXaml @{ Text = $Text }))
    [void]$ui.AskChat.Children.Add($el)
}

# Answer: Get-AskAnswer sonucu
function Add-AskBot($Answer) {
    $el = Read-LocalXaml ((Expand-Template $script:AskBotXaml @{ Title = [string]$Answer.Title; Text = [string]$Answer.Text }))
    if ([string]$Answer.Title -eq '') { $el.FindName('Ttl').Visibility = $script:VisOff }
    $acts = $el.FindName('Acts')
    foreach ($a in @($Answer.Actions)) {
        if ($null -eq $a) { continue }
        $b = Read-LocalXaml ((Expand-Template $script:AskActXaml @{ Text = [string]$a.L; Tag = [string]$a.Tag }))
        $b.Add_Click({ param($s, $e) Invoke-Safe { Invoke-AskTag ([string]$s.Tag) } 'Asistan' })
        [void]$acts.Children.Add($b)
    }
    if ([string]$Answer.Also -ne '') {
        $b = Read-LocalXaml ((Expand-Template $script:AskChipXaml @{ Text = ((Tr 'İlgili') + ': ' + (Tr ([string]$Answer.Also))); Tag = ('topic:' + [string]$Answer.AlsoKey) }))
        $b.Add_Click({ param($s, $e) Invoke-Safe { Invoke-AskTag ([string]$s.Tag) } 'Asistan' })
        [void]$acts.Children.Add($b)
    }
    if ($acts.Children.Count -eq 0) { $acts.Visibility = $script:VisOff }
    [void]$ui.AskChat.Children.Add($el)
    while ($ui.AskChat.Children.Count -gt 40) { $ui.AskChat.Children.RemoveAt(0) }
    try { $ui.AskScroll.UpdateLayout(); $ui.AskScroll.ScrollToEnd() } catch { }
}

function Invoke-Ask([string]$Text) {
    $q = ([string]$Text).Trim()
    if ($q -eq '') { return }
    if ($q.Length -gt 200) { $q = $q.Substring(0, 200) }
    Add-AskUser $q
    $hits = @()
    try { $hits = @(Get-BoardSearchResults $q) } catch { $hits = @() }
    Add-AskBot (Get-AskAnswer $q $script:CmdDefs $hits)
    $ui.AskInput.Text = ''
    try { [void]$ui.AskInput.Focus() } catch { }
}

function Invoke-AskTag([string]$Tag) {
    $i = $Tag.IndexOf(':')
    if ($i -lt 0) { return }
    $kind = $Tag.Substring(0, $i)
    $arg = $Tag.Substring($i + 1)
    if ($kind -eq 'topic') {
        $t = Get-AskTopic $arg
        if ($null -ne $t) { Add-AskUser ([string]$t.T); Add-AskBot @{ Title = [string]$t.T; Text = [string]$t.A; Actions = @($t.Do); Also = '' } }
        return
    }
    Hide-Ask
    if ($kind -eq 'kit') {
        Open-Page 'tools' 'kit'
        Invoke-TlExtraAct ('kit:' + $arg)
        return
    }
    Invoke-MenuTag $Tag
}

function Hide-Ask {
    if ($null -ne $ui.AskOverlay) { Set-Visible $ui.AskOverlay $false }
}

function Show-Ask([string]$Text = '') {
    if ($null -eq $ui.AskOverlay) { return }
    Close-HoverMenu
    try { Close-NavMenu } catch { }
    if (-not $script:AskReady) {
        $script:AskReady = $true
        $ui.AskChips.Children.Clear()
        foreach ($s in @(Get-AskSamples)) {
            $b = Read-LocalXaml ((Expand-Template $script:AskChipXaml @{ Text = [string]$s; Tag = [string]$s }))
            $b.Add_Click({ param($s2, $e) Invoke-Safe { Invoke-Ask ([string]$s2.Content) } 'Asistan' })
            [void]$ui.AskChips.Children.Add($b)
        }
        Add-AskBot @{ Title = 'Merhaba'; Text = 'Ne yapmak istediğinizi ya da sorununuzu kendi sözcüklerinizle yazın; ilgili açıklamayı ve tek tıkla açılan işlemleri göstereyim. Sayfa ve işlem adlarını da arayabilirsiniz. Cevaplar bu bilgisayarda üretilir; yazdıklarınız hiçbir yere gönderilmez.'; Actions = @(); Also = '' }
    }
    Set-Visible $ui.AskOverlay $true
    $ui.AskInput.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Input, [Action]{ try { [void]$ui.AskInput.Focus() } catch { } }) | Out-Null
    if ($Text.Trim() -ne '') { Invoke-Ask $Text }
}

function Initialize-Ask {
    if ($null -eq $ui.AskOverlay -or $null -eq $ui.BtnAsk) { return }
    $ui.BtnAsk.Add_Click({ Invoke-Safe { Show-Ask '' } 'Asistan' })
    $ui.AskClose.Add_Click({ Invoke-Safe { Hide-Ask } 'Asistan' })
    $ui.AskSend.Add_Click({ Invoke-Safe { Invoke-Ask ([string]$ui.AskInput.Text) } 'Asistan' })
    $ui.AskInput.Add_PreviewKeyDown({
        param($s, $e)
        if ($e.Key -eq [System.Windows.Input.Key]::Enter) { $e.Handled = $true; Invoke-Safe { Invoke-Ask ([string]$ui.AskInput.Text) } 'Asistan' }
    })
    $ui.AskOverlay.Add_PreviewKeyDown({
        param($s, $e)
        if ($e.Key -eq [System.Windows.Input.Key]::Escape) { $e.Handled = $true; Hide-Ask }
    })
    # kartin disina (karartilmis alana) tiklaninca kapanir
    $ui.AskOverlay.Add_MouseLeftButtonDown({
        param($s, $e)
        try { if ([object]::ReferenceEquals($e.OriginalSource, $ui.AskOverlay)) { Hide-Ask } } catch { }
    })
    $script:Win.Add_PreviewKeyDown({
        param($s, $e)
        try {
            if ($e.Key -eq [System.Windows.Input.Key]::F1) {
                $e.Handled = $true
                if ($ui.AskOverlay.Visibility -eq $script:VisOn) { Hide-Ask } else { Show-Ask '' }
            }
        } catch { }
    })
}

# Pencere kurulurken bir kez cagrilir
function Initialize-UxExtras {
    try { Initialize-Ask } catch { Write-CrashLog ('Asistan: ' + $_.Exception.Message) }
    try { Initialize-RailHover } catch { Write-CrashLog ('Sol cubuk: ' + $_.Exception.Message) }
}

# ---------------- duman testi: "kullanim" kapsami ----------------
# Fare hareket ettirilmez; menuler ve Asistan dogrudan islevleriyle acilir, goruntuleri alinir. Pano, ayar ve sistem degismez.
function Test-SmokeUx([string]$What) {
    if ($What -eq 'ask') {
        if ($null -eq $ui.BtnAsk -or $ui.BtnAsk.IsVisible -ne $true) { Add-SmokeError 'kullanim' 'Asistan düğmesi görünmüyor'; return }
        Show-Ask ''
        Invoke-SmokeFlush
        if ($ui.AskOverlay.Visibility -ne $script:VisOn) { Add-SmokeError 'kullanim' 'Asistan paneli açılmadı'; return }
        Invoke-Ask 'bilgisayarım çok yavaş'
        Invoke-SmokeFlush
        $n = $ui.AskChat.Children.Count
        if ($n -lt 3) { Add-SmokeError 'kullanim' ('Asistan sohbetinde ' + [string]$n + ' öğe var (karşılama, soru ve cevap bekleniyordu)') }
        $last = $ui.AskChat.Children[$n - 1]
        $acts = 0
        try { $acts = $last.FindName('Acts').Children.Count } catch { }
        if ($acts -lt 2) { Add-SmokeError 'kullanim' ('Asistan cevabında ' + [string]$acts + ' eylem düğmesi var, en az 2 bekleniyordu') }
        if ($ui.AskChips.Children.Count -lt 5) { Add-SmokeError 'kullanim' 'Asistan örnek soruları eksik' }
        Add-SmokeLine ('      kullanım: Asistan açıldı, cevapta ' + [string]$acts + ' eylem, ' + [string]$ui.AskChips.Children.Count + ' örnek soru')
        return
    }
    if ($What -eq 'askclose') {
        Hide-Ask
        Invoke-SmokeFlush
        if ($ui.AskOverlay.Visibility -eq $script:VisOn) { Add-SmokeError 'kullanim' 'Asistan paneli kapanmadı' }
        return
    }
    if ($What -eq 'hover') {
        $rb = $ui['Rail_tools']
        $items = @(Get-RailSubItemsShown 'tools')
        $want = @(Get-TlVisibleTabs ($script:UiState.Mode -eq 'Expert')).Count
        if ($items.Count -ne $want) { Add-SmokeError 'kullanim' ('Araçlar için ' + [string]$items.Count + ' alt sekme okundu, beklenen ' + [string]$want) }
        # Araclar dugmesi kapali bir grubun icindeyse grup denetim suresince acilir, sonunda eski haline doner
        $opened = $null
        if ($null -ne $rb -and $rb.IsVisible -ne $true) {
            foreach ($g in @($script:RailGroups)) {
                if (@($g.Pages) -contains 'tools' -and -not [bool]$g.Open) { Set-GroupOpen $g $true; $opened = $g; break }
            }
            for ($i = 0; $i -lt 6; $i++) { Invoke-SmokeFlush; Start-Sleep -Milliseconds 40 }
            try { $rb.BringIntoView() } catch { }
            Invoke-SmokeFlush
        }
        if ($null -eq $rb -or $rb.IsVisible -ne $true) {
            if ($null -ne $opened) { Set-GroupOpen $opened $false }
            Add-SmokeLine '      kullanım: Araçlar düğmesi bu kipte görünmüyor; alt sekme menüsü görüntüsü atlandı'
            return
        }
        $script:HoverPin = $true
        Show-HoverMenu $rb (@(@{ Head = 'ARAÇLAR' }) + $items)
        for ($i = 0; $i -lt 14; $i++) { Invoke-SmokeFlush; Start-Sleep -Milliseconds 50 }
        if ($null -eq $script:HoverPop -or -not $script:HoverPop.IsOpen) {
            Add-SmokeError 'kullanim' 'alt sekme menüsü açılmadı'; $script:HoverPin = $false
            if ($null -ne $opened) { Set-GroupOpen $opened $false }
            return
        }
        $cnt = $script:HoverPop.FindName('Items').Children.Count
        if ($cnt -ne ($items.Count + 1)) { Add-SmokeError 'kullanim' ('alt sekme menüsünde ' + [string]$cnt + ' satır var') }
        Save-SmokeScreen 'kullanim-alt-sekme-menusu'
        Add-SmokeLine ('      kullanım: alt sekme menüsü ' + [string]$cnt + ' satırla açıldı')
        $script:HoverPin = $false
        Close-HoverMenu
        if ($null -ne $opened) { Set-GroupOpen $opened $false; Invoke-SmokeFlush }
        return
    }
    if ($What -eq 'group') {
        if ($script:RailGroupsOn -ne $true -or $script:RailGroups.Count -eq 0) { Add-SmokeLine '      kullanım: sol çubuk grupları bu yerleşimde kapalı; grup denetimi atlandı'; return }
        $g = $null
        foreach ($x in @($script:RailGroups)) { if (-not [bool]$x.Open -and $x.Header.Visibility -eq $script:VisOn) { $g = $x; break } }
        if ($null -eq $g) { Add-SmokeLine '      kullanım: kapalı grup yok; grup denetimi atlandı'; return }
        Set-GroupOpen $g $true; $g.Peek = $true
        Invoke-SmokeFlush
        if (-not [bool]$g.Open) { Add-SmokeError 'kullanim' 'grup açılmadı' }
        Close-RailPeek
        Invoke-SmokeFlush
        if ([bool]$g.Open) { Add-SmokeError 'kullanim' 'geçici açılan grup, fare çıkınca kapanmadı' }
        else { Add-SmokeLine ('      kullanım: “' + [string]$g.Title + '” grubu geçici açılıp kapandı') }
        return
    }
    if ($What -eq 'kit') {
        Open-Page 'tools' 'kit'
        Invoke-SmokeFlush
        $n = $ui.tl_List.Children.Count
        if ($n -lt 10) { Add-SmokeError 'kullanim' ('Yardımcılar listesinde ' + [string]$n + ' öğe var'); return }
        $short = 0; $tips = 0
        foreach ($row in $ui.tl_List.Children) {
            if ($row -isnot [System.Windows.Controls.Border]) { continue }
            $det = $null
            try { $det = $row.FindName('Det') } catch { }
            if ($null -eq $det) { continue }
            if ($det.TextWrapping -eq [System.Windows.TextWrapping]::NoWrap) { $short++ }
            if ($null -ne $row.ToolTip) { $tips++ }
        }
        if ((Test-FullDesc) -eq $false -and ($short -lt 5 -or $tips -lt 5)) { Add-SmokeError 'kullanim' ('kısa açıklama: ' + [string]$short + ' satır tek satıra indi, ' + [string]$tips + ' satırda ipucu var') }
        Add-SmokeLine ('      kullanım: Yardımcılar ' + [string]$n + ' öğe; ' + [string]$short + ' açıklama tek satır, ' + [string]$tips + ' ipucu')
        # parola ureteci: eklenti yuklenir, parola uretilir (panoya yazilmaz)
        $x = Import-MmExt 'Parola'
        if ($x.Ok -ne $true) { Add-SmokeError 'kullanim' ('parola eklentisi yüklenemedi: ' + [string]$x.Error); return }
        $pw = New-RandomPassword 20 (Get-PasswordSets $true $true $true)
        if ($pw.Length -ne 20 -or $pw -cnotmatch '\d' -or $pw -cnotmatch '[!#$%&*+\-=?@_]') { Add-SmokeError 'kullanim' 'üretilen parola beklenen biçimde değil' }
        else { Add-SmokeLine '      kullanım: parola üreteci 20 karakterlik parola üretti (panoya yazılmadı)' }
        return
    }
    if ($What -eq 'pano') {
        # ana ekran: izleme dongusunun ilk tam turu beklenir (en cok 20 sn), sonra ekran karti ve sicaklik kartlarinin yazilari okunur
        Open-Page 'panel'
        for ($i = 0; $i -lt 100; $i++) {
            Invoke-SmokeFlush
            $d = $sync.MonDiag
            if ($null -ne $d -and [int]$d.Tick -ge 5) { break }
            Start-Sleep -Milliseconds 200
        }
        for ($i = 0; $i -lt 16; $i++) { Invoke-SmokeFlush; Start-Sleep -Milliseconds 150 }
        $parts = New-Object System.Collections.ArrayList
        foreach ($k in @($script:BoardViews.Keys)) {
            $v = $script:BoardViews[$k]
            $t = [string]$v.Type
            if ($t -ne 'gpu' -and $t -ne 'temp') { continue }
            try { [void]$parts.Add($t + '=' + [string]$v.N.Val.Text + ' [' + [string]$v.N.Sub.Text + ']') } catch { }
        }
        $m = $sync.Mon
        $line = '      kullanım: pano kartları: ' + ($parts -join '; ')
        if ($null -ne $m) { $line += ' | ölçüm: GPU=' + [string]$m.Gpu + ' sıcaklık=' + [string]$m.Temp + ' GPU sıcaklığı=' + [string]$m.GpuTemp }
        $line += ' | güvenli kip=' + [string]($sync.SafeMon -eq $true)
        Add-SmokeLine $line
        foreach ($x in $parts) { if ([string]$x -like '*ölçülüyor*') { Add-SmokeError 'kullanim' ('ilk ölçümden sonra kart hâlâ bekliyor: ' + [string]$x) } }
        return
    }
    if ($What -eq 'sorunlar') {
        # saglik taramasinin bulgulari: "sorun" sayilanlar ve her birinin tek tikla acilan eylemi var mi (yalnizca okuma)
        $h = $script:Health
        if ($null -eq $h -or $null -eq $h.Findings) { Add-SmokeLine '      kullanım: sağlık taraması sonucu yok; sorun listesi atlandı'; return }
        $n = 0; $noAct = 0
        foreach ($f in @($h.Findings)) {
            $st = [string]$f.Status
            if ($st -ne 'bad' -and $st -ne 'warn' -and [string]$f.Id -ne 'av-excl') { continue }
            $n++
            $act = 'eylem yok'
            if ($null -ne $f.Fix) { $act = 'Düzelt' }
            elseif ($null -ne $f.Action) { $act = [string]$f.Action.Kind + ':' + [string]$f.Action.Label }
            else { $noAct++ }
            Add-SmokeLine ('      kullanım: bulgu [' + $st + '] ' + [string]$f.Id + ' — ' + [string]$f.Title + ' → ' + $act)
        }
        $pend = '?'
        try { $p = Get-PendingReboot; $pend = (@($p) -join ', ') } catch { }
        Add-SmokeLine ('      kullanım: sorun sayılan bulgu ' + [string]$n + '; eylemsiz ' + [string]$noAct + '; yeniden başlatma nedeni: [' + $pend + ']; yönetici=' + [string]([bool]$script:IsAdmin))
        return
    }
    if ($What -eq 'kurulum') {
        # kurulum teklifi kutusu: acilir, goruntusu alinir, secim yapilmadan kapatilir (hicbir sey kurulmaz, ayar yazilmaz)
        try { Open-Page 'panel'; Invoke-SmokeFlush } catch { }
        Show-InstallOffer
        for ($i = 0; $i -lt 6; $i++) { Invoke-SmokeFlush; Start-Sleep -Milliseconds 60 }
        if ($ui.Overlay.Visibility -ne $script:VisOn) { Add-SmokeError 'kullanim' 'kurulum teklifi kutusu açılmadı'; return }
        Save-SmokeScreen 'kullanim-kurulum-teklifi'
        # kullanicinin "Daha sonra sor" dugmesine basmasiyla ayni yol: secim yapilmaz
        Complete-Overlay $false
        $script:ChoiceAction = $null
        Invoke-SmokeFlush
        if ($ui.Overlay.Visibility -eq $script:VisOn) { Add-SmokeError 'kullanim' 'kurulum teklifi kutusu kapanmadı' }
        $need = Test-InstallOfferNeeded $script:Settings ([string]$sync.ScriptPath) (Get-InstallDir) $false
        Add-SmokeLine ('      kullanım: kurulum teklifi kutusu açılıp kapandı; bu kopyada gerçek açılışta sorulur mu: ' + [string]$need + ' (kurulu=' + [string]($script:Settings.Installed -eq $true) + ')')
        return
    }
    if ($What -eq 'desc') {
        try { Open-Page 'settings'; Invoke-SmokeFlush } catch { }
        $root = Build-Page 'settings'
        $n = 0
        $stack = New-Object System.Collections.Stack
        $stack.Push($root)
        while ($stack.Count -gt 0) {
            $cur = $stack.Pop()
            if ($cur -is [System.Windows.Controls.TextBlock]) { if ([string]$cur.Tag -eq 'desc' -and $cur.TextWrapping -eq [System.Windows.TextWrapping]::NoWrap -and $null -ne $cur.ToolTip) { $n++ }; continue }
            if ($cur -isnot [System.Windows.DependencyObject]) { continue }
            foreach ($ch in [System.Windows.LogicalTreeHelper]::GetChildren($cur)) { if ($ch -is [System.Windows.DependencyObject]) { $stack.Push($ch) } }
        }
        if ((Test-FullDesc) -eq $false -and $n -lt 3) { Add-SmokeError 'kullanim' ('Ayarlar sayfasında yalnızca ' + [string]$n + ' açıklama tek satıra indi') }
        Add-SmokeLine ('      kullanım: Ayarlar sayfasında ' + [string]$n + ' açıklama tek satır ve ipuçlu')
        return
    }
    if ($What -eq 'drift') {
        # gercek ayar kaydiyla: hangi uygulanmis ayar "Windows tarafindan geri alinmis" gorunuyor (yalnizca okuma)
        $new = Get-DriftedIds
        $new = @($new)
        $applied = Get-AppliedIds
        $applied = @($applied)
        $old = New-Object System.Collections.ArrayList
        foreach ($id in $applied) {
            $c = Get-CatalogItem ([string]$id)
            if ($null -eq $c) { continue }
            try { if ((Get-TweakPending $c) -gt 0) { [void]$old.Add([string]$id) } } catch { }
        }
        Add-SmokeLine ('      kullanım: uygulanmış ayar ' + [string]$applied.Count + '; geri dönmüş görünen (yeni kural, görevler hariç): ' + [string]$new.Count + ' [' + ($new -join ', ') + ']')
        Add-SmokeLine ('      kullanım: eski kuralla (görevler dahil) geri dönmüş görünen: ' + [string]$old.Count + ' [' + ($old -join ', ') + ']')
        return
    }
    Add-SmokeError 'kullanim' ('bilinmeyen denetim: ' + $What)
}
