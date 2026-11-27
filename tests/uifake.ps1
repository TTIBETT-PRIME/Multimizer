# Sahte arayüz denetimleri ve yardımcılar: WPF bulunmayan ortamda sayfa çizim işlevlerinin akışını sınamak için.
# Test dosyasında "." ile yüklenir; aynı adlı gerçek işlevlerin yerine bu sahteler kullanılır.
$script:VisOn = 'Visible'
$script:VisOff = 'Collapsed'
$script:Toasts = New-Object System.Collections.ArrayList
$script:Confirms = New-Object System.Collections.ArrayList
$script:Asyncs = New-Object System.Collections.ArrayList
$script:Opened = New-Object System.Collections.ArrayList
$script:Loads = 0
$script:PickFolder = ''
$script:PickFile = ''
$script:PickSave = ''
$script:PickAnswer = $true
$script:Crashes = New-Object System.Collections.ArrayList

function New-FakeCtl {
    $c = [pscustomobject]@{
        Children = (New-Object System.Collections.ArrayList); Items = (New-Object System.Collections.ArrayList); SelectedIndex = -1
        Text = ''; Content = ''; Visibility = 'Visible'; IsChecked = $false; Tag = $null; Kind = ''; Head = $false; Named = @{}; Vars = $null
        Handlers = (New-Object System.Collections.ArrayList); IsEnabled = $true; Foreground = ''; Password = ''
    }
    Add-Member -InputObject $c -MemberType ScriptProperty -Name SelectedItem -Value { if ($this.SelectedIndex -ge 0 -and $this.SelectedIndex -lt $this.Items.Count) { $this.Items[$this.SelectedIndex] } else { $null } } | Out-Null
    Add-Member -InputObject $c -MemberType ScriptMethod -Name FindName -Value { param($n) if ($this.Named.ContainsKey($n)) { return $this.Named[$n] }; return $null } | Out-Null
    foreach ($ev in @('Add_Click', 'Add_Checked', 'Add_Unchecked', 'Add_SelectionChanged', 'Add_TextChanged', 'Add_LostFocus')) {
        Add-Member -InputObject $c -MemberType ScriptMethod -Name $ev -Value { param($h) [void]$this.Handlers.Add($h) } | Out-Null
    }
    return $c
}

function New-ItemRow($V, $Data, [bool]$Check, [bool]$Checked) {
    $row = New-FakeCtl
    $row.Tag = $Data
    $row.Vars = $V
    $chk = New-FakeCtl
    $chk.IsChecked = $Checked
    if ($Check) { $chk.Visibility = $script:VisOn } else { $chk.Visibility = $script:VisOff }
    $a1 = New-FakeCtl
    $a2 = New-FakeCtl
    $a1.Content = [string]$V.Btn1
    $a2.Content = [string]$V.Btn2
    if ([string]$V.Btn1 -eq '') { $a1.Visibility = $script:VisOff } else { $a1.Tag = $Data }
    if ([string]$V.Btn2 -eq '') { $a2.Visibility = $script:VisOff } else { $a2.Tag = $Data }
    $row.Named = @{ Chk = $chk; Act = $a1; Act2 = $a2 }
    return $row
}

function Add-Note($Panel, [string]$Text, [string]$Kind = 'dim') {
    $n = New-FakeCtl
    $n.Text = $Text
    $n.Kind = $Kind
    [void]$Panel.Children.Add($n)
}

function Add-HeadRow($Panel, [string]$Text) {
    $n = New-FakeCtl
    $n.Text = $Text
    $n.Head = $true
    [void]$Panel.Children.Add($n)
}

function Add-KvRow($Panel, [string]$Key, [string]$Val) {
    $n = New-FakeCtl
    $n.Text = $Key + ': ' + $Val
    $n.Kind = 'kv'
    [void]$Panel.Children.Add($n)
}

function Set-ListNote($Panel, [string]$Text, [string]$Kind = 'dim') {
    $Panel.Children.Clear()
    Add-Note $Panel $Text $Kind
}

function Get-CheckedData($Panel) {
    $r = New-Object System.Collections.ArrayList
    foreach ($row in $Panel.Children) {
        $c = $row.FindName('Chk')
        if ($null -eq $c) { continue }
        if ($row.Visibility -ne $script:VisOn -or $c.Visibility -ne $script:VisOn) { continue }
        if ($c.IsChecked -eq $true) { [void]$r.Add($row.Tag) }
    }
    return , $r.ToArray()
}

function Set-RowChecks($Panel, [scriptblock]$Pred) {
    foreach ($row in $Panel.Children) {
        $c = $row.FindName('Chk')
        if ($null -eq $c -or $c.Visibility -ne $script:VisOn) { continue }
        $c.IsChecked = [bool](& $Pred $row.Tag)
    }
}

function Show-OnlyBar([string]$P, $ShowNames) { $script:BarShown = @($ShowNames) }
function Show-Toast([string]$Text, [string]$Kind = 'info') { [void]$script:Toasts.Add(@{ T = $Text; K = $Kind }) }
function Show-Confirm([string]$Title, [string]$Text, [string]$OkText, [scriptblock]$OnOk, [bool]$Danger = $false) {
    [void]$script:Confirms.Add(@{ Title = $Title; Text = $Text; Ok = $OkText; OnOk = $OnOk; Danger = $Danger })
}
$script:Overlays = New-Object System.Collections.ArrayList
function Show-Overlay([string]$Title, [string]$Text, [string]$OkText, [bool]$ShowCancel, [bool]$Danger, [bool]$WithInput, [string]$InputText, [scriptblock]$OnOk) {
    [void]$script:Overlays.Add(@{ Title = $Title; Text = $Text; Ok = $OkText; ShowCancel = $ShowCancel; Danger = $Danger; WithInput = $WithInput; InputText = $InputText; OnOk = $OnOk })
}
function Show-Message([string]$Title, [string]$Text) { [void]$script:Confirms.Add(@{ Title = $Title; Text = $Text; Ok = ''; OnOk = $null; Danger = $false; Message = $true }) }
function Start-Async {
    param([string]$Name, [string]$Entry, $Params = $null, [scriptblock]$OnDone = $null, [string]$Label = '', [bool]$Quiet = $false, [bool]$Queue = $false)
    [void]$script:Asyncs.Add(@{ Name = $Name; Entry = $Entry; Params = $Params; OnDone = $OnDone; Label = $Label })
    return $true
}
function Select-Folder([string]$Desc) { return $script:PickFolder }
function Select-OpenFile([string]$Filter) { return $script:PickFile }
function Select-SaveFile([string]$Filter, [string]$Name) { return $script:PickSave }
function Open-Path([string]$Path) { [void]$script:Opened.Add('path:' + $Path) }
function Open-Folder([string]$Path) { [void]$script:Opened.Add('folder:' + $Path) }
function Open-Url([string]$Url) { [void]$script:Opened.Add('url:' + $Url) }
function Invoke-Safe([scriptblock]$Body, [string]$Where = '') { & $Body }
function Load-SlDisk { $script:Loads++ }
function Write-CrashLog([string]$Message) { [void]$script:Crashes.Add($Message) }

function Reset-Fake {
    $script:Toasts.Clear(); $script:Confirms.Clear(); $script:Overlays.Clear(); $script:Asyncs.Clear(); $script:Opened.Clear(); $script:Crashes.Clear()
    $script:Loads = 0; $script:PickFolder = ''; $script:PickFile = ''; $script:PickSave = ''
}
function Get-LastToast { if ($script:Toasts.Count -eq 0) { return $null }; return $script:Toasts[$script:Toasts.Count - 1] }
function Get-NoteTexts($Panel) { foreach ($c in $Panel.Children) { [string]$c.Text } }
function Find-NoteLike($Panel, [string]$Pattern) {
    foreach ($c in $Panel.Children) { if ([string]$c.Text -match $Pattern) { return $c } }
    return $null
}
function Get-RowsOf($Panel) { foreach ($c in $Panel.Children) { if ($null -ne $c.Vars) { $c } } }
