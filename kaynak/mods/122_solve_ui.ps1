# ==================================================================
#  ÇÖZÜM MERKEZİ SAYFASI
#  Sekmeler: Sorunlar (tara ve düzelt) · Diskler (şifreleme, sağlık) · Kurtarma · Silme · Sorun gidericiler · Bilgisayarım · Hazırlık
#  Her işlem önce önizlenir, onayla çalışır, günlüğe yazılır. Hiçbir işlem Windows Update, Defender, Güvenlik Duvarı ya da UAC’yi kapatmaz.
# ==================================================================
$script:SlTab = 'scan'
$script:SlDisks = $null
$script:SlLoading = $false
$script:SlPendingSteps = @()
$script:SlPendingTitle = ''

function Get-SlBr([string]$Status) {
    if ($Status -eq 'bad') { return 'BrBad' }
    if ($Status -eq 'warn') { return 'BrWarn' }
    if ($Status -eq 'ok') { return 'BrGood' }
    return 'BrInfo'
}

function Get-SlBarFor([string]$Tab) {
    switch ($Tab) {
        'scan'    { return @('sl_Scan', 'sl_ScanFull', 'sl_FixAll') }
        'disk'    { return @('sl_DiskRefresh') }
        'recover' { return @('sl_RcVol', 'sl_RcImg', 'sl_RcQuick', 'sl_RcDeep', 'sl_RcType', 'sl_RcDest', 'sl_RcRun', 'sl_RcAll', 'sl_RcNone') }
        'erase'   { return @('sl_ErFile', 'sl_ErFolder', 'sl_ErMethod', 'sl_ErVerify', 'sl_ErAfter', 'sl_ErRefresh') }
        'trouble' { return @() }
        'pc'      { return @('sl_PcRefresh', 'sl_PcCopy') }
        'prep'    { return @('sl_PrCheck', 'sl_PrFix') }
    }
    return @()
}

function Set-SlTab([string]$Tab) {
    if ($script:SlvTabs -notcontains $Tab) { $Tab = 'scan' }
    $script:SlTab = $Tab
    Show-OnlyBar 'sl' (Get-SlBarFor $Tab)
    if ($Tab -eq 'recover') { $ui.sl_RcFindRow.Visibility = $script:VisOn } else { $ui.sl_RcFindRow.Visibility = $script:VisOff }
    $ui.sl_Foot.Text = ''
    switch ($Tab) {
        'scan'    { Render-SlScan }
        'disk'    { Render-SlDisk }
        'recover' { Render-SlRecover }
        'erase'   { Render-SlErase }
        'trouble' { Render-SlTrouble }
        'pc'      { Render-SlPc }
        'prep'    { Render-SlPrep }
    }
}

# ---------------- Sorunlar: tara ve düzelt ----------------
function Render-SlScan {
    $ui.sl_List.Children.Clear()
    $h = $script:Health
    if ($null -eq $h) {
        Add-Note $ui.sl_List 'Henüz tarama yapılmadı. “Bilgisayarı tara” sistemi yalnızca okur, hiçbir şeyi değiştirmez; bulunan sorunların çoğunu buradan tek tıkla düzeltebilirsiniz.'
        return
    }
    $open = @($h.Findings | Where-Object { [string]$_.Status -ne 'ok' } | Sort-Object -Property @{ Expression = { [int]$_.Weight }; Descending = $true })
    if ($open.Count -eq 0) {
        Add-Note $ui.sl_List 'Taramada düzeltilecek ya da dikkat edilecek bir şey çıkmadı. Her şey yolunda görünüyor.' 'good'
        $ui.sl_Foot.Text = 'Sağlık puanı: ' + [string]$h.Score.All
        return
    }
    $fixable = New-Object System.Collections.ArrayList
    $rest = New-Object System.Collections.ArrayList
    foreach ($f in $open) {
        $m = ''
        if ($null -ne $f.Fix) { $m = [string]$f.Fix.Mode }
        if ($m -eq 'Auto' -or $m -eq 'Click') { [void]$fixable.Add($f) } else { [void]$rest.Add($f) }
    }
    $groups = @(@{ T = 'Düzeltilebilir sorunlar'; L = $fixable.ToArray() }, @{ T = 'Bilgi ve elle yapılacaklar'; L = $rest.ToArray() })
    $shown = 0
    foreach ($g in $groups) {
        if (@($g.L).Count -eq 0) { continue }
        Add-HeadRow $ui.sl_List ($g.T + ' (' + [string]@($g.L).Count + ')')
        foreach ($f in @($g.L)) {
            if ($shown -ge 80) { break }
            $shown++
            $fx = $null
            if ($null -ne $f.Fix -and ([string]$f.Fix.Mode -eq 'Auto' -or [string]$f.Fix.Mode -eq 'Click')) { $fx = $f.Fix }
            $ak = ''
            $albl = ''
            if ($null -ne $f.Action) { $ak = [string]$f.Action.Kind; if ($f.Action.ContainsKey('Label')) { $albl = [string]$f.Action.Label } }
            $b1 = ''
            $b2 = ''
            if ($null -ne $fx) {
                $b1 = 'Düzelt'
                if ($albl -ne '' -and $ak -ne 'Tweak' -and $ak -ne 'Run') { $b2 = $albl }
            } elseif ($albl -ne '') { $b1 = $albl }
            $det = [string]$f.Detail
            if ($det.Length -gt 300) { $det = $det.Substring(0, 297) + '...' }
            if ([string]$script:UiState.Mode -eq 'Expert') {
                $std = [string](Get-JsonProp $f 'Std')
                if ($std -ne '') { $det += "`r`nStandartlar: " + $std }
            }
            $data = @{ Id = [string]$f.Id; Title = [string]$f.Title; Fix = $fx; Mode = ''; Action = $f.Action }
            if ($null -ne $fx) { $data.Mode = [string]$fx.Mode }
            $row = New-ItemRow @{ Title = [string]$f.Title; Detail = $det; Tag = (Get-CatLabel ([string]$f.Cat)); BrCol = (Get-SlBr ([string]$f.Status)); Btn1 = $b1; Btn2 = $b2 } $data $false $false
            if ($b1 -ne '') { if ($null -ne $fx) { $row.FindName('Act').Add_Click($script:H_FixOne) } else { $row.FindName('Act').Add_Click($script:H_ScAct) } }
            if ($b2 -ne '') { $row.FindName('Act2').Add_Click($script:H_ScAct) }
            [void]$ui.sl_List.Children.Add($row)
        }
    }
    $ts = ''
    try { if ($script:HealthAt -gt [datetime]'2001-01-01') { $ts = '  ·  tarama: ' + $script:HealthAt.ToString('HH:mm') } } catch { }
    $ui.sl_Foot.Text = 'Sağlık puanı: ' + [string]$h.Score.All + $ts + '  ·  Düzeltmeler Geçmiş sayfasından geri alınabilir.'
}

# Sağlık taraması bitince Update-HealthUi çağırır
function Update-SolveFromHealth {
    if ([string]$script:UiState.Page -eq 'solve' -and $script:SlTab -eq 'scan') { Render-SlScan }
}

# ---------------- Diskler ----------------
function Load-SlDisk {
    if ($script:SlLoading -eq $true) { return }
    $script:SlLoading = $true
    $ok = Start-Async 'SlDisks' 'Job_SlvDisks' @{} {
        param($r)
        $script:SlLoading = $false
        if ($null -eq $r -or $r.Ok -ne $true) { $script:SlDisks = @{ Failed = $true } } else { $script:SlDisks = $r }
        if ([string]$script:UiState.Page -eq 'solve') {
            if ($script:SlTab -eq 'disk') { Render-SlDisk }
            elseif ($script:SlTab -eq 'recover') { Render-SlRecover }
            elseif ($script:SlTab -eq 'erase') { Render-SlErase }
        }
    } 'Diskler okunuyor' $false $true
    if (-not $ok) { $script:SlLoading = $false }
}

function Render-SlDisk {
    $ui.sl_List.Children.Clear()
    $d = $script:SlDisks
    if ($null -eq $d) { Set-ListNote $ui.sl_List 'Diskler okunuyor...'; Load-SlDisk; return }
    if ($d.Failed -eq $true) {
        Add-Note $ui.sl_List 'Disk bilgisi okunamadı. Multimizer’ı yönetici olarak çalıştırdığınızdan emin olun, sonra “Yenile”ye basın.' 'warn'
        return
    }
    Add-Note $ui.sl_List 'Her sürücünün şifreleme durumu, dosya sistemi sağlığı ve Windows’un disk hata kayıtları burada. Şifreleme bilgisayarınız çalınırsa ya da kaybolursa dosyalarınızı korur; kurtarma anahtarı olmadan bir BIOS ya da donanım değişikliğinden sonra verilere erişilemeyebilir, bu yüzden anahtar bilgisayarın dışında saklanmalıdır.'
    if ($d.Sys.IsAdmin -ne $true) { Add-Note $ui.sl_List 'Multimizer yönetici olarak çalışmıyor; şifreleme durumu okunamayabilir ve işlemler yapılamaz.' 'warn' }
    $n = 0
    foreach ($disk in @($d.Disks)) {
        foreach ($r in @($disk.Rows)) {
            if ([string]$r.Kind -eq 'head') { Add-HeadRow $ui.sl_List ([string]$r.Title); continue }
            $n++
            $b1 = ''; $b2 = ''
            if ([string]$r.Do -ne '') { $b1 = [string]$r.Label }
            if ([string]$r.Do2 -ne '') { $b2 = [string]$r.Label2 }
            $data = @{ Do = [string]$r.Do; Drive = [string]$disk.Drive; Method = [string]$disk.Plan.Method; IsOs = ($disk.Plan.IsOs -eq $true); Type = [string]$disk.Type; Scope = [string]$disk.Plan.Scope; Cipher = [string]$disk.Plan.Cipher }
            $row = New-ItemRow @{ Title = [string]$r.Title; Detail = [string]$r.Detail; BrCol = [string]$r.Br; Btn1 = $b1; Btn2 = $b2 } $data $false $false
            if ($b1 -ne '') { $row.FindName('Act').Add_Click($script:H_SlAct) }
            if ($b2 -ne '') {
                $data2 = @{ Do = [string]$r.Do2; Drive = [string]$disk.Drive; Method = [string]$disk.Plan.Method; IsOs = ($disk.Plan.IsOs -eq $true); Type = [string]$disk.Type; Scope = [string]$disk.Plan.Scope; Cipher = [string]$disk.Plan.Cipher }
                $a2 = $row.FindName('Act2')
                $a2.Tag = $data2
                $a2.Add_Click($script:H_SlAct)
            }
            [void]$ui.sl_List.Children.Add($row)
        }
    }
    if ($n -eq 0) { Add-Note $ui.sl_List 'Sürücü bulunamadı.' 'warn' }
    $ui.sl_Foot.Text = 'Anahtarlar yalnızca siz istediğinizde okunur ve günlüğe yazılmaz. Windows Update, Defender ve Güvenlik Duvarı’na dokunulmaz.'
}

$script:H_SlAct = { param($s, $e) Invoke-Safe { Invoke-SlAction $s.Tag } 'Eylem' }

function Invoke-SlAction($T) {
    $drive = [string]$T.Drive
    switch ([string]$T.Do) {
        'BlKey'    { & $script:H_BkBlKey ([pscustomobject]@{ Tag = @{ Drive = $drive } }) $null }
        'BlSave'   { & $script:H_BkBlSave ([pscustomobject]@{ Tag = @{ Drive = $drive } }) $null }
        'BlAddKey' { & $script:H_BkBlAdd ([pscustomobject]@{ Tag = @{ Drive = $drive } }) $null }
        'BlEnable' { Start-SlBlEnable $T }
        'BlSuspend' { Start-SlBlSimple 'Suspend' $drive }
        'BlLock'    { Start-SlBlSimple 'Lock' $drive }
        'BlDisable' { Start-SlBlSimple 'Disable' $drive }
        'BlAutoUnlock' { Start-SlBlSimple 'AutoUnlock' $drive }
        'BlResume' {
            [void](Start-Async 'Action' 'Job_Action' @{ Key = 'BlResume'; Drive = $drive } {
                param($r)
                if ($null -ne $r -and $r.Ok -eq $true) { Show-Toast 'BitLocker koruması sürdürüldü.' 'good' } else { Show-Toast 'Koruma sürdürülemedi; günlüğe bakın.' 'bad' }
                $script:SlDisks = $null
                if ([string]$script:UiState.Page -eq 'solve' -and $script:SlTab -eq 'disk') { Render-SlDisk }
            } 'BitLocker koruması sürdürülüyor')
        }
        'DiskScan'     { Start-SlDiskJob 'scan' $drive }
        'DiskOptimize' { Start-SlDiskJob 'optimize' $drive }
        'DiskRepair'   { Start-SlDiskRepair $drive ($T.IsOs -eq $true) }
        'Backup'       { Open-Page 'backup' }
    }
}

function Start-SlDiskJob([string]$Kind, [string]$Drive) {
    $lbl = $Drive + ' taranıyor (salt okunur)'
    if ($Kind -eq 'optimize') { $lbl = $Drive + ' iyileştiriliyor' }
    [void](Start-Async 'SlDiskOp' 'Job_SlvDiskOp' @{ Kind = $Kind; Drive = $Drive } {
        param($r)
        if ($null -ne $r -and $r.Ok -eq $true) { Show-Toast 'Disk işlemi tamamlandı; ayrıntı günlükte.' 'good' } else { Show-Toast 'Disk işlemi tamamlanamadı; günlüğe bakın.' 'bad' }
    } $lbl)
}

function Start-SlDiskRepair([string]$Drive, [bool]$IsOs) {
    $step = @{ Id = 'chkdsk-' + $Drive.TrimEnd(':'); Title = $Drive + ' sürücüsünü onar'; Ops = @(@{ T = 'ChkdskRepair'; Drive = $Drive }); Reboot = $IsOs }
    $script:SlPendingSteps = @($step)
    $script:SlPendingTitle = $Drive + ' sürücüsünü onar'
    $txt = $Drive + ' sürücüsündeki dosya sistemi hataları onarılır. Onarım sürücüyü kısa süre kullanılamaz yapabilir; çalışan programları kapatmanız önerilir.'
    if ($IsOs) { $txt += "`r`n`r`nSistem sürücüsü yeniden başlatmada onarılır." }
    Show-Confirm 'Sürücüyü onar' $txt 'Onar' { Start-PlanJob $script:SlPendingSteps $script:SlPendingTitle $false $false { $script:SlDisks = $null } }
}

function Start-SlBlSimple([string]$Op, [string]$Drive) {
    $msg = ''
    $ok = 'Hazır'
    if ($Op -eq 'Suspend') {
        $msg = $Drive + ' için BitLocker koruması bir sonraki yeniden başlatmaya kadar askıya alınır (BIOS ya da sürücü güncellemesi öncesi için). Bu sırada veriler anahtarsız okunabilir; yeniden başlatınca koruma kendiliğinden döner.'
        $ok = 'Askıya al'
    } elseif ($Op -eq 'Lock') {
        $msg = $Drive + ' sürücüsü kilitlenir. Açmak için parola ya da kurtarma anahtarı gerekir; anahtarın elinizde olduğundan emin olun.'
        $ok = 'Kilitle'
    } elseif ($Op -eq 'Disable') {
        $msg = $Drive + ' sürücüsünün şifrelemesi kaldırılır (şifre çözme). Bundan sonra bilgisayar kaybolur ya da çalınırsa dosyalara herkes erişebilir. İşlem arka planda sürer; süre sürücü boyutuna bağlıdır ve kapatırsanız kaldığı yerden devam eder.'
        $ok = 'Şifrelemeyi kaldır'
    } elseif ($Op -eq 'AutoUnlock') {
        $msg = $Drive + ' sürücüsü, sistem sürücüsü açılınca kendiliğinden açılacak. Sürücüyü başka bir bilgisayara taktığınızda yine kurtarma anahtarı gerekir.'
        $ok = 'Aç'
    }
    $script:SlBlPending = @{ Op = $Op; Drive = $Drive }
    Show-Confirm 'BitLocker' $msg $ok {
        [void](Start-Async 'BlOp' 'Job_BlOp' @{ Op = $script:SlBlPending.Op; Drive = $script:SlBlPending.Drive } {
            param($r)
            if ($null -ne $r -and $r.Ok -eq $true) { Show-Toast ([string]$r.Message) 'good' } else { $m = 'İşlem tamamlanamadı.'; if ($null -ne $r -and [string]$r.Error -ne '') { $m = [string]$r.Error }; Show-Toast $m 'bad' }
            $script:SlDisks = $null
            if ([string]$script:UiState.Page -eq 'solve' -and $script:SlTab -eq 'disk') { Render-SlDisk }
        } 'BitLocker işlemi')
    }
}

function Start-SlBlEnable($T) {
    $drive = [string]$T.Drive
    if ([string]$T.Method -eq 'DeviceEncryption') {
        Open-Url 'ms-settings:deviceencryption'
        Show-Toast 'Cihaz şifrelemesi sayfası açıldı; oradan açtığınızda kurtarma anahtarı Microsoft hesabınıza kaydedilir.' 'info'
        return
    }
    $dir = Select-Folder ('Kurtarma anahtarının kaydedileceği klasörü seçin (' + $drive + ' dışında: USB bellek ya da başka bir sürücü)')
    if ($dir -eq '') { return }
    $bad = Test-BlKeyDir $dir $drive
    if ($bad -ne '') { Show-Toast $bad 'warn'; return }
    $isOs = ($T.IsOs -eq $true)
    $cname = 'XTS-AES 256'
    if ([string]$T.Cipher -eq 'Aes256') { $cname = 'AES-256' }
    $txt = $drive + ' sürücüsü BitLocker ile şifrelenecek (' + $cname + ', ' + (Get-BlScopeText ([string]$T.Scope)) + ').' + "`r`n`r`n" + 'Önce 48 haneli kurtarma anahtarı oluşturulup şu klasöre kaydedilir ve dosya doğrulanır: ' + $dir + "`r`n`r`n" + 'Dosya doğrulanamazsa hiçbir şey şifrelenmez.'
    if ($isOs) { $txt += "`r`n`r`n" + 'Sistem diskinde şifreleme bilgisayarı yeniden başlatınca başlar; o zamana kadar hiçbir şey değişmez. Şifreleme sürerken bilgisayarı kullanabilirsiniz.' }
    else { $txt += "`r`n`r`n" + 'Şifreleme hemen başlar ve arka planda sürer; bilgisayarı kullanabilirsiniz.' }
    $script:SlBlPending = @{ Op = 'Enable'; Drive = $drive; KeyDir = $dir; IsOs = $isOs }
    Show-Confirm 'Şifrelemeyi başlat' $txt 'Başlat' {
        [void](Start-Async 'BlOp' 'Job_BlOp' @{ Op = 'Enable'; Drive = $script:SlBlPending.Drive; KeyDir = $script:SlBlPending.KeyDir } {
            param($r)
            $script:SlDisks = $null
            if ($null -ne $r -and $r.Ok -eq $true) {
                Show-Toast ([string]$r.Message) 'good'
                if ($r.NeedsReboot -eq $true) { Request-Reboot }
            } else {
                $m = 'Şifreleme başlatılamadı.'
                if ($null -ne $r -and [string]$r.Error -ne '') { $m = [string]$r.Error }
                Show-Toast $m 'bad'
            }
            if ([string]$script:UiState.Page -eq 'solve' -and $script:SlTab -eq 'disk') { Render-SlDisk }
        } 'BitLocker şifrelemesi hazırlanıyor')
    }
}

# ---------------- Sorun gidericiler ----------------
function Render-SlTrouble {
    $ui.sl_List.Children.Clear()
    Add-Note $ui.sl_List 'Belirtiyi bulun; Multimizer ilgili hizmetleri ve önbellekleri onarır. Her işlem önce önizlenir, onayınızla çalışır ve Geçmiş sayfasına yazılır. Kişisel dosyalara dokunulmaz.'
    foreach ($s in @($script:SlvSymptoms)) {
        $hasSteps = (@($s.Steps).Count -gt 0)
        $det = [string]$s.D
        if ($s.Reboot -eq $true) { $det += ' Etkili olması için yeniden başlatma gerekir.' }
        $b1 = 'Bilgisayarı tara'; $b2 = ''
        if ($hasSteps) { $b1 = 'Önizle'; $b2 = 'Düzelt' }
        $row = New-ItemRow @{ Title = [string]$s.T; Detail = $det; BrCol = 'BrInfo'; Btn1 = $b1; Btn2 = $b2 } @{ Do = 'TrPreview'; Key = [string]$s.K } $false $false
        $a1 = $row.FindName('Act')
        if (-not $hasSteps) { $a1.Tag = @{ Do = 'TrScan'; Key = [string]$s.K } }
        $a1.Add_Click($script:H_SlAct2)
        if ($hasSteps) {
            $a2 = $row.FindName('Act2')
            $a2.Tag = @{ Do = 'TrRun'; Key = [string]$s.K }
            $a2.Add_Click($script:H_SlAct2)
        }
        [void]$ui.sl_List.Children.Add($row)
        foreach ($g in @($s.Guided)) {
            $data = @{ Do = 'Go'; Page = [string]$g.Page; Sub = [string]$g.Sub; Url = [string]$g.Url }
            $gr = New-ItemRow @{ Title = ('      →  ' + [string]$g.Label); Detail = ''; BrCol = 'BrFaint'; Btn1 = 'Aç' } $data $false $false
            $gr.FindName('Act').Add_Click($script:H_SlAct2)
            [void]$ui.sl_List.Children.Add($gr)
        }
    }
    $ui.sl_Foot.Text = 'Düzelt’e basınca önce neler yapılacağı yazılır; siz onaylamadan hiçbir şey çalışmaz.'
}

$script:H_SlAct2 = { param($s, $e) Invoke-Safe { Invoke-SlAction2 $s.Tag } 'Eylem' }

function Invoke-SlAction2($T) {
    switch ([string]$T.Do) {
        'TrPreview' { Start-SlTrouble ([string]$T.Key) $true }
        'TrRun'     { Start-SlTrouble ([string]$T.Key) $false }
        'TrScan'    { if (-not (Select-TabChip 'sl' 'scan')) { Set-SlTab 'scan' }; Start-HealthScan 'Quick' $false }
        'Go' {
            if ([string]$T.Url -ne '') { Open-Url ([string]$T.Url) }
            elseif ([string]$T.Page -ne '') { Open-Page ([string]$T.Page) ([string]$T.Sub) }
        }
    }
}

function Start-SlTrouble([string]$Key, [bool]$Preview) {
    $s = Get-SlvSymptom $Key
    if ($null -eq $s) { return }
    $steps = Get-SlvTroubleSteps $Key
    if (@($steps).Count -eq 0) { return }
    $title = [string]$s.T
    if ($Preview) { Start-PlanJob $steps $title $true $false; return }
    $script:SlPendingSteps = @($steps)
    $script:SlPendingTitle = $title
    $lines = @($steps | ForEach-Object { '•  ' + [string]$_.Title })
    $txt = [string]$s.D + "`r`n`r`n" + 'Yapılacaklar:' + "`r`n" + ($lines -join "`r`n")
    Show-Confirm 'Sorunu gider' $txt 'Çalıştır' { Start-PlanJob $script:SlPendingSteps $script:SlPendingTitle $false $false }
}

# ---------------- sayfa kurulumu ----------------
function Init-Page_solve {
    Register-Tabs 'sl' $script:SlvTabs { param($s, $e) Invoke-Safe { Set-SlTab ([string]$s.Tag) } 'Sekme' }
    $ui.sl_Scan.Add_Click({ Invoke-Safe { Start-HealthScan 'Quick' $false } 'Tara' })
    $ui.sl_ScanFull.Add_Click({ Invoke-Safe { Start-HealthScan 'Full' $false } 'Tam denetim' })
    $ui.sl_FixAll.Add_Click({ Invoke-Safe { Start-FixAll } 'Düzelt' })
    $ui.sl_DiskRefresh.Add_Click({ Invoke-Safe { $script:SlDisks = $null; Render-SlDisk } 'Yenile' })
    Init-SlRecover
    Init-SlErase
    Init-SlPc
    Init-SlPrep
}

function Select-Sub_solve([string]$Sub) {
    if (-not (Select-TabChip 'sl' $Sub)) { Set-SlTab $Sub }
}

function Show-Page_solve {
    $t = Get-TabKey 'sl' $script:SlvTabs 'scan'
    Set-SlTab $t
}
