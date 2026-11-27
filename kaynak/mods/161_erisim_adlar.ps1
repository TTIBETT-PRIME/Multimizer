# ---------------- Erişilebilirlik: ekran okuyucu adları ----------------
# Ekran Okuyucu bir denetimi UI Automation adıyla okur. WPF bu adı yalnızca içeriği düz yazı olan düğmelerde kendisi bulur;
# simge + yazıdan oluşan düğmeler, seçim ve metin kutuları adsız kalır ("düğme", "birleşik giriş kutusu" diye okunur).
# Bir denetim ilk kez boyut aldığında (SizeChanged sınıf işleyicisi; sonradan oluşan satırlar, açılan sekmeler dahil) adı boşsa:
#  - düğme ve onay/seçenek kutusu: içindeki ilk anlamlı yazıya (TextBlock.Text) bağlanır; yazı yoksa ipucuna (ToolTip)
#  - seçim kutusu, metin kutusu, parola kutusu, kaydırıcı: aynı satırdaki önceki etikete (LabeledBy) bağlanır; yoksa ipucuna
# Bağlama (Binding) kullanıldığı için dil değişince ad da değişir. Adı zaten verilmiş öğelere ve başka bir denetimin
# şablon parçalarına (kaydırma çubuğu okları gibi) dokunulmaz. İş, yerleşim bittikten sonra (Background önceliği) yapılır.
# Neden Loaded değil: WPF, Loaded olayını yalnızca kendisinde ya da stilinde Loaded işleyicisi olan öğelere yayınlar; sınıf
# işleyicisi bu yüzden çoğu düğmede hiç çağrılmaz (gerçek bilgisayarda 25.11.2026: yama öncesi ve sonrası 46 adsız denetim).
# SizeChanged ise her öğede yerleşim sırasında RaiseEvent ile tetiklenir; yalnızca ilk boyutta (önceki boyut 0) iş yapılır.
$script:A11yQueue = New-Object System.Collections.ArrayList
$script:A11yPending = $false
$script:A11yRegistered = $false
$script:A11yDone = 0
$script:A11yCalls = 0
$script:A11yErr = $false
# Yazısı ya da ipucu olmayan, adıyla tanınan denetimler (değer seçici okları, komut satırı). Satır başlığı varsa öne eklenir.
$script:A11yNameMap = @{
    Dn = 'Azalt'; Up = 'Artır'
    AcDn = 'Fişte: azalt'; AcUp = 'Fişte: artır'; DcDn = 'Pilde: azalt'; DcUp = 'Pilde: artır'
    CmdInput = 'Komut satırı'; AskInput = 'Asistan'
}
$script:A11yRowTitled = @('Dn', 'Up', 'AcDn', 'AcUp', 'DcDn', 'DcUp')

function Test-A11yTarget($El) {
    return (($El -is [System.Windows.Controls.Primitives.ButtonBase]) -or ($El -is [System.Windows.Controls.ComboBox]) -or
        ($El -is [System.Windows.Controls.Primitives.TextBoxBase]) -or ($El -is [System.Windows.Controls.PasswordBox]) -or
        ($El -is [System.Windows.Controls.Slider]))
}

# Yüklenen öğe: hızlı elemeden geçerse kuyruğa alınır (asıl iş boşta yapılır)
function Add-A11yCandidate($El) {
    if ($null -eq $El) { return }
    if (-not [string]::IsNullOrEmpty([System.Windows.Automation.AutomationProperties]::GetName($El))) { return }
    if ($null -ne [System.Windows.Automation.AutomationProperties]::GetLabeledBy($El)) { return }
    if ($El -is [System.Windows.Controls.ContentControl]) {
        $cn = $El.Content
        if ($cn -is [string] -and -not (Test-A11yNameBad ([string]$cn))) { return }
    }
    if ($El.TemplatedParent -is [System.Windows.Controls.Control]) { return }
    [void]$script:A11yQueue.Add($El)
    if (-not $script:A11yPending) {
        $script:A11yPending = $true
        [void]$El.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [Action]{ Invoke-A11yQueue })
    }
}

function Set-A11yNameBinding($El, $Source, [string]$Path) {
    $b = New-Object System.Windows.Data.Binding($Path)
    $b.Source = $Source
    $b.Mode = [System.Windows.Data.BindingMode]::OneWay
    [void][System.Windows.Data.BindingOperations]::SetBinding($El, [System.Windows.Automation.AutomationProperties]::NameProperty, $b)
}

# Düğmenin içindeki ilk anlamlı yazı (yalnızca simge karakteri olan yazılar atlanır)
function Find-A11yInnerText($El) {
    $hidden = $null
    $stack = New-Object System.Collections.Stack
    $stack.Push($El)
    $n = 0
    while ($stack.Count -gt 0 -and $n -lt 80) {
        $o = $stack.Pop()
        $n++
        if ($o -is [System.Windows.Controls.TextBlock] -and $o -ne $El -and -not (Test-A11yNameBad ([string]$o.Text))) {
            if ($o.IsVisible) { return $o }
            if ($null -eq $hidden) { $hidden = $o }
        }
        $k = 0
        try { $k = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($o) } catch { $k = 0 }
        for ($i = $k - 1; $i -ge 0; $i--) { try { $stack.Push([System.Windows.Media.VisualTreeHelper]::GetChild($o, $i)) } catch { } }
    }
    return $hidden
}

# Panelin doğrudan çocuklarından ilk anlamlı yazı (satır başlığı: StackPanel içindeki başlık TextBlock'u)
function Get-A11yFirstText($El) {
    if ($El -is [System.Windows.Controls.TextBlock]) { if (-not (Test-A11yNameBad ([string]$El.Text))) { return $El }; return $null }
    if ($El -is [System.Windows.Controls.Panel]) {
        foreach ($c in @($El.Children)) { if ($c -is [System.Windows.Controls.TextBlock] -and -not (Test-A11yNameBad ([string]$c.Text))) { return $c } }
    }
    return $null
}

# İçeriği olmayan düğme (kart üstündeki tıklama alanı, satırdaki onay kutusu): kardeş öğelerdeki ilk anlamlı yazı
function Find-A11ySiblingText($El) {
    $p = [System.Windows.Media.VisualTreeHelper]::GetParent($El)
    if (-not ($p -is [System.Windows.Controls.Panel])) { return $null }
    foreach ($c in @($p.Children)) {
        if ($c -eq $El) { continue }
        $t = Find-A11yInnerText $c
        if ($null -ne $t) { return $t }
    }
    return $null
}

# Satır başlığı: üstteki Grid'in ilk sütunundaki başlık yazısı (değer seçici satırları)
function Get-A11yRowTitle($El) {
    $p = $El
    for ($i = 0; $i -lt 3 -and $null -ne $p; $i++) {
        $p = [System.Windows.Media.VisualTreeHelper]::GetParent($p)
        if ($p -is [System.Windows.Controls.Grid]) {
            foreach ($c in @($p.Children)) {
                if ([System.Windows.Controls.Grid]::GetColumn($c) -ne 0) { continue }
                $t = Get-A11yFirstText $c
                if ($null -ne $t) { return [string]$t.Text }
            }
            return ''
        }
    }
    return ''
}

# Giriş denetiminin etiketi: aynı panelde ondan önce gelen, anlamlı yazısı olan TextBlock (Grid'de aynı satır, soldaki sütun)
function Find-A11yLabel($El) {
    $p = [System.Windows.Media.VisualTreeHelper]::GetParent($El)
    $hop = 0
    while ($null -ne $p -and $hop -lt 3) {
        if ($p -is [System.Windows.Controls.Grid]) {
            $row = [System.Windows.Controls.Grid]::GetRow($El)
            $col = [System.Windows.Controls.Grid]::GetColumn($El)
            $best = $null
            $bestCol = -1
            foreach ($c in @($p.Children)) {
                if ($c -eq $El -or -not $c.IsVisible) { continue }
                $cc = [System.Windows.Controls.Grid]::GetColumn($c)
                if ([System.Windows.Controls.Grid]::GetRow($c) -ne $row -or $cc -ge $col -or $cc -le $bestCol) { continue }
                $t = Get-A11yFirstText $c
                if ($null -ne $t) { $best = $t; $bestCol = $cc }
            }
            return $best
        }
        if ($p -is [System.Windows.Controls.Panel]) {
            $prev = $null
            foreach ($c in @($p.Children)) {
                if ($c -eq $El) { break }
                if ($c.IsVisible) { $prev = $c }
            }
            if ($prev -is [System.Windows.Controls.TextBlock] -and -not (Test-A11yNameBad ([string]$prev.Text))) { return $prev }
            $vis = @(@($p.Children) | Where-Object { $_.IsVisible })
            if ($vis.Count -gt 1) { return $null }
        }
        $El = $p
        $p = [System.Windows.Media.VisualTreeHelper]::GetParent($p)
        $hop++
    }
    return $null
}

function Set-A11yName($El) {
    if (-not [string]::IsNullOrEmpty([System.Windows.Automation.AutomationProperties]::GetName($El))) { return $false }
    $nm = [string]$El.Name
    if ($nm -ne '' -and $script:A11yNameMap.ContainsKey($nm)) {
        $txt = Tr ([string]$script:A11yNameMap[$nm])
        if ($script:A11yRowTitled -contains $nm) { $rt = Get-A11yRowTitle $El; if ($rt -ne '') { $txt = $rt + ', ' + $txt } }
        [System.Windows.Automation.AutomationProperties]::SetName($El, $txt)
        return $true
    }
    if ($El -is [System.Windows.Controls.Primitives.ButtonBase]) {
        $tb = Find-A11yInnerText $El
        if ($null -ne $tb) { Set-A11yNameBinding $El $tb 'Text'; return $true }
    } else {
        if ($null -ne [System.Windows.Automation.AutomationProperties]::GetLabeledBy($El)) { return $false }
        $lb = Find-A11yLabel $El
        if ($null -ne $lb) { [System.Windows.Automation.AutomationProperties]::SetLabeledBy($El, $lb); return $true }
    }
    if ($El.ToolTip -is [string] -and -not (Test-A11yNameBad ([string]$El.ToolTip))) { Set-A11yNameBinding $El $El 'ToolTip'; return $true }
    if ($El -is [System.Windows.Controls.Primitives.ButtonBase] -and ($null -eq $El.Content -or [string]$El.Content -eq '')) {
        $st = Find-A11ySiblingText $El
        if ($null -ne $st) { Set-A11yNameBinding $El $st 'Text'; return $true }
    }
    return $false
}

function Invoke-A11yQueue {
    $script:A11yPending = $false
    $items = $script:A11yQueue.ToArray()
    $script:A11yQueue.Clear()
    foreach ($el in $items) {
        try { if ($el.IsLoaded -and (Set-A11yName $el)) { $script:A11yDone = [int]$script:A11yDone + 1 } }
        catch {
            if (-not $script:A11yErr) { $script:A11yErr = $true; Write-CrashLog ('Erişilebilirlik adı verilemedi: ' + $_.Exception.Message) }
        }
    }
}

# Uygulama başlarken bir kez: denetim türleri için ilk boyut (SizeChanged) ve Loaded sınıf işleyicileri
function Register-A11yNames {
    if ($script:A11yRegistered) { return }
    $script:A11yRegistered = $true
    $h = [System.Windows.RoutedEventHandler]{
        param($s, $e)
        try {
            # yeniden boyutlanma (pencere büyütme, yakınlaştırma) işsizdir; yalnızca ilk boyut ve gizliyken açılma
            if ($e -is [System.Windows.SizeChangedEventArgs]) { $p = $e.PreviousSize; if ($p.Width -gt 0 -and $p.Height -gt 0) { return } }
            $script:A11yCalls = [int]$script:A11yCalls + 1
            if (Test-A11yTarget $s) { Add-A11yCandidate $s }
        }
        catch {
            if (-not $script:A11yErr) { $script:A11yErr = $true; Write-CrashLog ('Erişilebilirlik adı verilemedi: ' + $_.Exception.Message) }
        }
    }
    foreach ($t in @([System.Windows.Controls.Primitives.ButtonBase], [System.Windows.Controls.ComboBox], [System.Windows.Controls.Primitives.TextBoxBase],
            [System.Windows.Controls.PasswordBox], [System.Windows.Controls.Slider])) {
        [System.Windows.EventManager]::RegisterClassHandler($t, [System.Windows.FrameworkElement]::SizeChangedEvent, $h)
        [System.Windows.EventManager]::RegisterClassHandler($t, [System.Windows.FrameworkElement]::LoadedEvent, $h)
    }
}
