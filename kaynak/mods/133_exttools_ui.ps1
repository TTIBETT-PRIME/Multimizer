# ==================================================================
#  DIŞ ARAÇLAR (sağlayıcı katmanı): arayüz
#  Araçlar > Dış araçlar sekmesi. Liste, 132_exttools_core.ps1 içindeki sabit katalogdan gelir. Kurulu olanlar tek tıkla açılır;
#  eksik olanlar yalnızca onayla ve Microsoft’un winget aracıyla kurulur. “Sayfa” düğmesi aracın resmî sayfasını tarayıcıda açar.
#  Denetim yalnızca dosya var mı diye bakar; hiçbir araç kendiliğinden kurulmaz, güncellenmez ya da çalıştırılmaz.
# ==================================================================
$script:ExtToolState = $null
$script:ExtToolLoading = $false
$script:ExtToolPending = $null

# Grup listesi: @( @{ K; T } )
function Get-ExtToolGroups {
    $out = New-Object System.Collections.ArrayList
    foreach ($g in $script:ExtToolGroups) {
        $f = ([string]$g).Split('|')
        if ($f.Count -ge 2) { [void]$out.Add(@{ K = $f[0]; T = $f[1] }) }
    }
    return , $out.ToArray()
}

# Denetim sonucundan bir aracın durumu; kayıt yoksa kurulu değil sayılır
function Get-ExtToolStateFor($State, [string]$Id) {
    $items = $null
    try { $items = $State.Items } catch { $items = $null }
    foreach ($i in @($items)) {
        if ($null -ne $i -and [string]$i.Id -eq $Id) { return $i }
    }
    return @{ Id = $Id; Installed = $false; Path = '' }
}

# Saf mantık: bir araç satırının görünümü ve veri nesnesi
function Get-ExtToolRowModel($Tool, $St, [bool]$Expert = $false) {
    $installed = ($null -ne $St -and $St.Installed -eq $true)
    $path = ''
    if ($installed) { $path = [string]$St.Path }
    $det = [string]$Tool.Publisher + ' · ' + [string]$Tool.Desc
    if ($Expert) { $det += ' · winget: ' + [string]$Tool.Id }
    $m = @{ Title = [string]$Tool.Name; Detail = $det; Tag = 'Kurulu değil'; BrCol = 'BrFaint'; Btn1 = 'Kur'; Btn2 = 'Sayfa' }
    if ($installed) { $m.Tag = 'Kurulu'; $m.BrCol = 'BrGood'; $m.Btn1 = 'Aç' }
    $m.Data = @{ Id = [string]$Tool.Id; Name = [string]$Tool.Name; Home = [string]$Tool.Home; Path = $path; Installed = $installed }
    return $m
}

# Kurulum onay penceresinin metni
function Get-ExtToolConfirmText($Tool) {
    $b = [string][char]0x2022 + '  '
    $txt = '“' + [string]$Tool.Name + '” (' + [string]$Tool.Publisher + ') Microsoft’un winget aracıyla kurulacak.' + "`r`n`r`n"
    $txt += $b + 'Paket winget deposundan indirilir; paket özeti (SHA-256) winget tarafından doğrulanır, uyuşmazsa kurulmaz.' + "`r`n"
    $txt += $b + '“Kur”a basarak aracın lisans koşullarını kabul etmiş olursunuz. Koşulları önce “Sayfa” düğmesiyle yayıncının sayfasından okuyabilirsiniz.' + "`r`n"
    $txt += $b + 'İnternet bağlantısı gerekir. Windows, kurulum için yönetici onayı isteyebilir.' + "`r`n"
    $txt += $b + 'Araç Multimizer’ın parçası değildir; güncellemesini ve desteğini kendi yayıncısı sağlar. Ayarlarınıza ve kişisel dosyalarınıza dokunulmaz.'
    return $txt
}

# Kurulum işinin sonucu -> bildirim: @{ Text; Kind (good | warn | bad) }
function Get-ExtToolInstallModel($R) {
    if ($null -eq $R) { return @{ Text = 'Kurulum tamamlanamadı; günlüğe bakın.'; Kind = 'bad' } }
    $name = [string](Get-JsonProp $R 'Name')
    if ($name -eq '') { $name = [string](Get-JsonProp $R 'Id') }
    if ($name -eq '') { $name = 'Araç' }
    $text = [string](Get-JsonProp $R 'Text')
    if ((Get-JsonProp $R 'Ok') -ne $true) {
        if ($text -eq '') { $text = 'bilinmeyen hata' }
        return @{ Text = ($name + ' kurulamadı: ' + $text); Kind = 'bad' }
    }
    $kind = 'good'
    $t = $name + ' kuruldu.'
    if ((Get-JsonProp $R 'Already') -eq $true) { $t = $name + ' zaten kuruluymuş.' }
    if ([string](Get-JsonProp $R 'Path') -ne '') { $t += ' “Aç” ile başlatabilirsiniz.' }
    else { $t += ' Çalıştırılabilir dosya beklenen konumda bulunamadı; Başlat menüsünden açabilirsiniz.'; $kind = 'warn' }
    if ((Get-JsonProp $R 'Reboot') -eq $true) { $t += ' Etkili olması için bilgisayarı yeniden başlatın.'; $kind = 'warn' }
    return @{ Text = $t; Kind = $kind }
}

# ---------------- çizim ----------------
function Load-TlExt {
    if ($script:ExtToolLoading -eq $true) { return }
    $script:ExtToolLoading = $true
    $ok = Start-Async 'ExtScan' 'Job_ExtToolScan' @{} {
        param($r)
        Complete-TlExt $r
    } 'Dış araçlar denetleniyor' $true $true
    if (-not $ok) { $script:ExtToolLoading = $false }
}

function Complete-TlExt($R) {
    $script:ExtToolLoading = $false
    if ($null -eq $R -or $R.Ok -ne $true) { $script:ExtToolState = @{ Failed = $true } } else { $script:ExtToolState = $R }
    if ([string]$script:UiState.Page -eq 'tools' -and $script:TlTab -eq 'ext') { Render-TlExt }
}

$script:H_TlExtAct = { param($s, $e) Invoke-Safe { Invoke-TlExtAction $s.Tag } 'Dış araç' }
$script:H_TlExtPage = { param($s, $e) Invoke-Safe { Open-Url ([string]$s.Tag.Home) } 'Sayfa' }

function Render-TlExt {
    $ui.tl_List.Children.Clear()
    $S = $script:ExtToolState
    if ($null -eq $S) {
        Add-Note $ui.tl_List 'Dış araçlar denetleniyor...'
        Load-TlExt
        return
    }
    if ($S.Failed -eq $true) {
        Add-Note $ui.tl_List 'Denetim yapılamadı. “Yenile”ye basarak yeniden deneyin; sorun sürerse günlüğe bakın.' 'warn'
        return
    }
    $expert = ([string]$script:UiState.Mode -eq 'Expert')
    Add-Note $ui.tl_List 'Bunlar kendi alanında yerleşik, sürekli geliştirilen araçlardır; Multimizer onları kopyalamaz, yalnızca kurulu olup olmadığına bakar. Eksik olan, yalnızca onayınızla ve Microsoft’un winget aracıyla (paket özeti doğrulanarak) kurulur.'
    $cat = Get-ExtToolCatalog
    foreach ($g in (Get-ExtToolGroups)) {
        $tools = @($cat | Where-Object { [string]$_.Group -eq [string]$g.K })
        if ($tools.Count -eq 0) { continue }
        Add-HeadRow $ui.tl_List ([string]$g.T)
        foreach ($t in $tools) {
            $m = Get-ExtToolRowModel $t (Get-ExtToolStateFor $S ([string]$t.Id)) $expert
            $row = New-ItemRow @{ Title = $m.Title; Detail = $m.Detail; Tag = $m.Tag; BrCol = $m.BrCol; Btn1 = $m.Btn1; Btn2 = $m.Btn2 } $m.Data $false $false
            $row.FindName('Act').Add_Click($script:H_TlExtAct)
            $row.FindName('Act2').Add_Click($script:H_TlExtPage)
            [void]$ui.tl_List.Children.Add($row)
        }
    }
    $ui.tl_Foot.Text = 'Denetlendi: ' + [string]$S.At + '  ·  Kurulumdan sonra “Yenile”ye basarak sonucu doğrulayın.'
}

# ---------------- işlemler ----------------
function Invoke-TlExtAction($T) {
    if ($null -eq $T) { return }
    if ($T.Installed -eq $true) { Open-ExtTool $T; return }
    Start-ExtToolInstall $T
}

# Kurulu aracı açar; dosya denetimden sonra silinmişse listeyi yeniler
function Open-ExtTool($T) {
    $p = [string]$T.Path
    if ($p -eq '' -or -not (Test-Path -LiteralPath $p -PathType Leaf)) {
        Show-Toast ([string]$T.Name + ' bulunamadı; liste yenileniyor.') 'warn'
        $script:ExtToolState = $null
        Render-TlExt
        return
    }
    Write-WhLog ('Dış araç açılıyor: ' + [string]$T.Name) 'INFO'
    Open-Path $p
}

# T: satırın veri nesnesi. Onaylanmadan hiçbir şey indirilmez ya da kurulmaz.
function Start-ExtToolInstall($T) {
    $why = Test-ExtToolId ([string]$T.Id)
    if ($why -ne '') { Show-Message 'Bu araç kurulamaz' $why; return }
    $tool = Get-ExtTool ([string]$T.Id)
    $script:ExtToolPending = $tool
    Show-Confirm 'Dış aracı kur' (Get-ExtToolConfirmText $tool) 'Kur' {
        $t = $script:ExtToolPending
        if ($null -eq $t) { return }
        [void](Start-Async 'ExtInstall' 'Job_ExtToolInstall' @{ Id = [string]$t.Id } {
            param($r)
            Complete-ExtToolInstall $r
        } ([string]$t.Name + ' kuruluyor'))
    }
}

function Complete-ExtToolInstall($R) {
    $script:ExtToolPending = $null
    $script:ExtToolState = $null
    $m = Get-ExtToolInstallModel $R
    Show-Toast ([string]$m.Text) ([string]$m.Kind)
    if ([string]$script:UiState.Page -eq 'tools' -and $script:TlTab -eq 'ext') { Render-TlExt }
}

# “Yenile” düğmesi: açık sekmeye göre
function Invoke-TlRefresh {
    if ($script:TlTab -eq 'ext') { $script:ExtToolState = $null; Render-TlExt; return }
    $script:TlProcs = $null
    Render-TlProcs
}
