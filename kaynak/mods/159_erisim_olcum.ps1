# ---------------- Duman testi: erişilebilirlik ölçümü (yalnızca okur) ----------------
# Her ekran görüntüsünde pencerede görünen denetim öğelerini (düğme, onay kutusu, seçenek düğmesi, seçim kutusu, metin kutusu,
# kaydırıcı) gezer ve iki şeyi ölçer:
#  1) Ekran okuyucunun okuyacağı ad (UI Automation Name) boş mu ya da yalnızca simge yazı tipi karakteri mi (Ekran Okuyucu bunu
#     "düğme" diye adsız okur). Ad, öğenin otomasyon eşinden (AutomationPeer) alınır; Windows'un ekran okuyucuya verdiği addır.
#  2) Dokunma hedefi: kısa kenarı 24 px'ten küçük mü (WCAG 2.2 AA alt sınırı) ya da 24-32 px arasında mı (Windows sık yerleşim
#     ölçüsü 32 px; dokunmatik ekran için önerilen yaklaşık 40 px). Ölçüler etkin pikseldir (96 DPI'a göre).
# Aynı sayfa ve sekme her temada yeniden ölçülmez (adlar temaya bağlı değil); yerleşimler ayrı ölçülür (boyutlar değişir).
# Başka bir denetimin parçası olan öğeler (kaydırma çubuğu okları, seçim kutusunun açma düğmesi gibi) sayılmaz.
# Hiçbir şeyi değiştirmez; özet duman sonucuna, ayrıntı %TEMP%\Multimizer-duman-erisim.txt dosyasına yazılır.
$script:SmokeA11y = $null
$script:SmokeA11yMax = 80
$script:SmokeA11yFails = 0

# Ad boş ya da yalnızca simge/noktalama mı (harf ya da rakam yoksa ekran okuyucu anlamlı bir şey okuyamaz)
function Test-A11yNameBad([string]$Name) {
    $t = ([string]$Name).Trim()
    if ($t.Length -eq 0) { return $true }
    foreach ($ch in $t.ToCharArray()) {
        $c = [int]$ch
        if ($c -ge 0xE000 -and $c -le 0xF8FF) { continue }
        if ([char]::IsLetterOrDigit($ch)) { return $false }
    }
    return $true
}

# Ekran görüntüsü adından tema önekini atar: "Neon-home" ve "Koyu-home" aynı görünümdür
function Get-A11yContextKey([string]$Shot) {
    $s = [string]$Shot
    $i = $s.IndexOf('-')
    if ($i -gt 0) {
        $first = $s.Substring(0, $i)
        foreach ($t in @($script:SmokeThemes)) { if ([string]$t -eq $first) { return $s.Substring($i + 1) } }
    }
    return $s
}

# Türlere göre sayım: anahtarın ilk sözcüğü tür adıdır ("Button Kok \"Uygula\"")
function Get-A11yKindCounts($Map) {
    $c = @{}
    foreach ($k in @($Map.Keys)) {
        $kind = ([string]$k).Split(' ')[0]
        if (-not $c.ContainsKey($kind)) { $c[$kind] = 0 }
        $c[$kind] = [int]$c[$kind] + 1
    }
    if ($c.Count -eq 0) { return '' }
    return (' (' + ((@($c.Keys | Sort-Object) | ForEach-Object { [string]$_ + ' ' + [string]$c[$_] }) -join ', ') + ')')
}

function Get-A11yKind($El) {
    if ($El -is [System.Windows.Controls.ComboBox]) { return 'ComboBox' }
    if ($El -is [System.Windows.Controls.Slider]) { return 'Slider' }
    if ($El -is [System.Windows.Controls.PasswordBox]) { return 'PasswordBox' }
    if ($El -is [System.Windows.Controls.Primitives.TextBoxBase]) { return 'TextBox' }
    if ($El -is [System.Windows.Controls.Primitives.ButtonBase]) { return [string]$El.GetType().Name }
    return ''
}

# Öğenin ekranda görünen yazısı (yoksa ipucu): ayrıntı listesinde hangi öğe olduğunu bulmak için
function Get-A11yLabel($El) {
    try {
        if ($El -is [System.Windows.Controls.ContentControl]) {
            $cn = $El.Content
            if ($cn -is [string] -and -not (Test-A11yNameBad ([string]$cn))) { return [string]$cn }
        }
        $stack = New-Object System.Collections.Stack
        $stack.Push($El)
        $n = 0
        while ($stack.Count -gt 0 -and $n -lt 60) {
            $o = $stack.Pop()
            $n++
            if ($o -is [System.Windows.Controls.TextBlock]) {
                $tx = [string]$o.Text
                if (-not (Test-A11yNameBad $tx)) { if ($tx.Length -gt 40) { $tx = $tx.Substring(0, 40) + '...' }; return $tx }
            }
            $k = 0
            try { $k = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($o) } catch { $k = 0 }
            for ($i = $k - 1; $i -ge 0; $i--) { try { $stack.Push([System.Windows.Media.VisualTreeHelper]::GetChild($o, $i)) } catch { } }
        }
    } catch { }
    try {
        $tt = $El.ToolTip
        if ($tt -is [string] -and [string]$tt -ne '') { $s = [string]$tt; if ($s.Length -gt 40) { $s = $s.Substring(0, 40) + '...' }; return ('ipucu: ' + $s) }
    } catch { }
    return ''
}

# Öğenin kendisinin ya da en yakın üst öğesinin adı (x:Name): ayrıntı listesinde yer bulmak için
function Get-A11yAnchor($El) {
    $cur = $El
    $n = 0
    while ($null -ne $cur -and $n -lt 40) {
        $nm = ''
        try { $nm = [string]$cur.Name } catch { $nm = '' }
        if ($nm -ne '') { return $nm }
        try { $cur = [System.Windows.Media.VisualTreeHelper]::GetParent($cur) } catch { $cur = $null }
        $n++
    }
    return '?'
}

function Add-SmokeA11yFail([string]$Msg) {
    $script:SmokeA11yFails = [int]$script:SmokeA11yFails + 1
    if ([int]$script:SmokeA11yFails -eq 1) { Add-SmokeLine ('erişilebilirlik ölçümü yapılamadı (bilgi): ' + $Msg) }
}

function Measure-SmokeA11y([string]$Shot) {
    if ($null -eq $script:SmokeA11y) {
        $script:SmokeA11y = @{ Runs = 0; Seen = @{}; NoName = @{}; Small24 = @{}; Small32 = @{}; Ctx = @{}; Kinds = @{}; Ms = 0 }
    }
    $A = $script:SmokeA11y
    $ctx = Get-A11yContextKey $Shot
    if ($A.Ctx.ContainsKey($ctx)) { return }
    if ([int]$A.Runs -ge [int]$script:SmokeA11yMax) { return }
    $root = $script:Win
    if ($null -eq $root) { return }
    $A.Ctx[$ctx] = $true
    $A.Runs = [int]$A.Runs + 1
    # bekleyen ekran okuyucu adları önce verilir (ölçüm, adların verilme anına bağlı kalmasın)
    try { if ($null -ne $script:A11yQueue -and $script:A11yQueue.Count -gt 0) { Invoke-A11yQueue } } catch { }
    $t0 = Get-Date
    $stack = New-Object System.Collections.Stack
    $stack.Push($root)
    $n = 0
    while ($stack.Count -gt 0 -and $n -lt 30000) {
        $o = $stack.Pop()
        $n++
        if ($o -is [System.Windows.UIElement]) { if (-not $o.IsVisible) { continue } }
        $kind = Get-A11yKind $o
        if ($kind -ne '') {
            $part = $false
            try { $part = ($o.TemplatedParent -is [System.Windows.Controls.Control]) } catch { $part = $false }
            $w = 0.0
            $h = 0.0
            try { $w = [double]$o.ActualWidth; $h = [double]$o.ActualHeight } catch { }
            if (-not $part -and $w -gt 0 -and $h -gt 0) {
                $key = $kind + ' ' + (Get-A11yAnchor $o) + ' "' + (Get-A11yLabel $o) + '"'
                if (-not $A.Seen.ContainsKey($key)) {
                    $A.Seen[$key] = $ctx
                    if (-not $A.Kinds.ContainsKey($kind)) { $A.Kinds[$kind] = 0 }
                    $A.Kinds[$kind] = [int]$A.Kinds[$kind] + 1
                }
                if (-not $A.NoName.ContainsKey($key)) {
                    $name = ''
                    try {
                        $peer = [System.Windows.Automation.Peers.UIElementAutomationPeer]::CreatePeerForElement($o)
                        if ($null -ne $peer) { $name = [string]$peer.GetName() }
                    } catch { $name = '' }
                    if (Test-A11yNameBad $name) { $A.NoName[$key] = $ctx }
                }
                $mn = [Math]::Min($w, $h)
                $sz = [string][int][Math]::Round($w) + 'x' + [string][int][Math]::Round($h)
                if ($mn -lt 24) { if (-not $A.Small24.ContainsKey($key)) { $A.Small24[$key] = $ctx + ' ' + $sz } }
                elseif ($mn -lt 32) { if (-not $A.Small32.ContainsKey($key)) { $A.Small32[$key] = $ctx + ' ' + $sz } }
            }
        }
        $k = 0
        try { $k = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($o) } catch { $k = 0 }
        for ($i = $k - 1; $i -ge 0; $i--) { try { $stack.Push([System.Windows.Media.VisualTreeHelper]::GetChild($o, $i)) } catch { } }
    }
    $A.Ms = [int]$A.Ms + [int]((Get-Date) - $t0).TotalMilliseconds
}

function Write-SmokeA11yReport {
    $A = $script:SmokeA11y
    if ($null -eq $A -or [int]$A.Runs -le 0) { return }
    $kinds = (@($A.Kinds.Keys | Sort-Object) | ForEach-Object { [string]$_ + ' ' + [string]$A.Kinds[$_] }) -join ', '
    Add-SmokeLine ('--- erişilebilirlik (bilgi; hiçbir şey değiştirilmedi): ' + [string]$A.Runs + ' görünümde ' + [string]$A.Seen.Count + ' denetim öğesi (' + $kinds + '), ' + [string]$A.Ms + ' ms')
    Add-SmokeLine ('  ekran okuyucu adı boş ya da yalnızca simge: ' + [string]$A.NoName.Count + (Get-A11yKindCounts $A.NoName))
    Add-SmokeLine ('  dokunma hedefi 24 px altı: ' + [string]$A.Small24.Count + (Get-A11yKindCounts $A.Small24) + '; 24-32 px arası: ' + [string]$A.Small32.Count + (Get-A11yKindCounts $A.Small32))
    if ($null -ne $script:A11yCalls) { Add-SmokeLine ('  ekran okuyucu adı verilen: ' + [string][int]$script:A11yDone + ' denetim (incelenen ' + [string][int]$script:A11yCalls + ')') }
    if ([int]$script:SmokeA11yFails -gt 0) { Add-SmokeLine ('  ölçüm ' + [string]$script:SmokeA11yFails + ' görünümde yarıda kaldı; sayılar eksik olabilir') }
    $nl = "`r`n"
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('MULTIMIZER ERİŞİLEBİLİRLİK ÖLÇÜMÜ (yalnızca okuma; hiçbir ayar değiştirilmedi)' + $nl)
    [void]$sb.Append('tarih=' + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') + '  görünüm=' + [string]$A.Runs + '  öğe=' + [string]$A.Seen.Count + '  süre=' + [string]$A.Ms + ' ms' + $nl)
    [void]$sb.Append('Ölçüt: ekran okuyucunun okuyacağı ad (UI Automation Name) boş ya da yalnızca simge; dokunma hedefinin kısa kenarı 24 px (WCAG 2.2 AA) ve 32 px (Windows sık yerleşim) altında. Ölçüler etkin pikseldir.' + $nl)
    [void]$sb.Append('Satır biçimi: tür  çapa (öğenin ya da en yakın üst öğenin adı)  "görünen yazı ya da ipucu"  |  ilk görüldüğü görünüm [ölçü]' + $nl)
    $sections = @(
        @{ T = 'ADSIZ (ekran okuyucu adı boş ya da yalnızca simge)'; M = $A.NoName },
        @{ T = '24 PX ALTI'; M = $A.Small24 },
        @{ T = '24-32 PX ARASI'; M = $A.Small32 }
    )
    foreach ($sec in $sections) {
        $m = $sec.M
        [void]$sb.Append($nl + '[' + [string]$sec.T + '] ' + [string]$m.Count + $nl)
        $i = 0
        foreach ($k in @($m.Keys | Sort-Object)) {
            $i++
            if ($i -gt 400) { [void]$sb.Append('  ... (ilk 400 satır)' + $nl); break }
            [void]$sb.Append('  ' + [string]$k + '  |  ' + [string]$m[$k] + $nl)
        }
    }
    $path = Join-Path ([System.IO.Path]::GetTempPath()) 'Multimizer-duman-erisim.txt'
    try {
        [System.IO.File]::WriteAllText($path, $sb.ToString(), (New-Object System.Text.UTF8Encoding($true)))
        Add-SmokeLine ('  ayrıntı: ' + $path)
    } catch { Add-SmokeLine ('  ayrıntı dosyası yazılamadı: ' + $_.Exception.Message) }
}
