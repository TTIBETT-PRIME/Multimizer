# ==================================================================
#  CANLI OZELLIK DENETIMI  (duman kapsami "ozellik")
#  Gercek Windows'ta, bu bilgisayarda: katalogdaki her ayari uygulamanin kendi motoruyla uygular, sistemden BAGIMSIZ bir okumayla
#  dogrular, geri alir ve eski halle karsilastirir. Bulunan her tutarsizlik "HATA" olarak raporlanir.
#  Iki kip (ortam degiskeni MM_OZELLIK_KIP):
#    oku (varsayilan) : hicbir sey yazmaz. Her ayarin olcumunu, onizlemesini ve yalnizca-okuma denetimlerini yapar.
#    tam              : yonetici olarak calisirken gercek tur (uygula -> dogrula -> geri al -> karsilastir). Her adimdan once eski durum
#                       diskte saklanir (%TEMP%\Multimizer-duman-geri); surec oluse bile bir sonraki acilista kendiliginden geri yuklenir.
#                       Yonetici degilse "oku" kipine iner.
#  Geri alinamayan islemler (temizlik, uygulama kaldirma, Windows bilesenini kaldirma) gercek veriye uygulanmaz: onizleme ve olcum yapilir,
#  silme / yazma mantigi gecici bir deneme alaninda (klasor ya da sanal disk) sinanir.
#  Sonuc: Multimizer-duman.txt ("canli ..." satirlari) ve Multimizer-duman-ozellik.tsv
# ==================================================================

$script:LiveRows = New-Object System.Collections.ArrayList
$script:LiveMode = ''
$script:LiveDowngraded = $false
$script:LiveState = @{}
$script:LiveTsv = ''
$script:LiveT0 = $null
$script:LiveApplicable = $null

function Get-LiveDir {
    $d = Join-Path ([System.IO.Path]::GetTempPath()) 'Multimizer-duman-geri'
    try { if (-not (Test-Path -LiteralPath $d)) { [void](New-Item -ItemType Directory -Path $d -Force) } } catch { }
    return $d
}

function Get-LiveMode {
    if ($script:LiveMode -ne '') { return $script:LiveMode }
    $m = ''
    try { $m = ([string]$env:MM_OZELLIK_KIP).Trim().ToLowerInvariant() } catch { $m = '' }
    if ($m -eq 'tam' -and -not [bool]$script:IsAdmin) { $m = 'oku'; $script:LiveDowngraded = $true }
    if ($m -ne 'tam') { $m = 'oku' }
    $script:LiveMode = $m
    return $m
}

function Format-LiveMs([double]$Ms) {
    if ($Ms -ge 60000) { return ([string][math]::Round($Ms / 60000, 1) + ' dk') }
    if ($Ms -ge 1000) { return ([string][math]::Round($Ms / 1000, 1) + ' sn') }
    return ([string][int]$Ms + ' ms')
}

# Bir sonuc satiri: Durum = OK | HATA | UYARI | ATLA | BILGI.  HATA hata sayilir (cikis kodu 2), UYARI uyari sayilir.
function Add-LiveRow([string]$Area, [string]$Id, [string]$Status, [string]$Detail, [double]$Ms = 0) {
    $d = $Detail
    if ($null -eq $d) { $d = '' }
    $d = ($d -replace "[\r\n\t]+", ' ').Trim()
    $r = [pscustomobject]@{ Alan = $Area; Kimlik = $Id; Durum = $Status; Ayrinti = $d; Ms = [int]$Ms }
    [void]$script:LiveRows.Add($r)
    $text = '      canlı ' + $Area + ' [' + $Status + '] ' + $Id
    if ($d -ne '') { $text += ' — ' + $d }
    if ($Ms -ge 1) { $text += ' (' + (Format-LiveMs $Ms) + ')' }
    if ($Status -eq 'HATA') { Add-SmokeError 'ozellik' ($Area + '/' + $Id + ': ' + $d) }
    elseif ($Status -eq 'UYARI') { Add-SmokeWarn ($Area + '/' + $Id + ': ' + $d) }
    else { Add-SmokeLine $text }
    try { [Console]::WriteLine('  ' + $Area + ' [' + $Status + '] ' + $Id + $(if ($d.Length -gt 110) { ' — ' + $d.Substring(0, 110) + '...' } elseif ($d -ne '') { ' — ' + $d } else { '' })) } catch { }
    try {
        if ($script:LiveTsv -eq '') { $script:LiveTsv = Join-Path ([System.IO.Path]::GetTempPath()) 'Multimizer-duman-ozellik.tsv'; [System.IO.File]::WriteAllText($script:LiveTsv, ("Alan`tKimlik`tDurum`tMs`tAyrinti`r`n"), (New-Object System.Text.UTF8Encoding($true))) }
        [System.IO.File]::AppendAllText($script:LiveTsv, ($Area + "`t" + $Id + "`t" + $Status + "`t" + [string][int]$Ms + "`t" + $d + "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
    } catch { }
}

function Get-LiveCount([string]$Status) { return @($script:LiveRows | Where-Object { $_.Durum -eq $Status }).Count }

# ---------------- gunluk kuyrugu: bir cagrinin yazdigi satirlari yakalar ----------------
function Get-LiveLogMark {
    try { return [int64](New-Object System.IO.FileInfo ([string]$sync.LogFile)).Length } catch { return [int64]0 }
}

function Get-LiveLogSince([int64]$Mark) {
    $out = @()
    try {
        $fs = [System.IO.File]::Open([string]$sync.LogFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            if ($fs.Length -gt $Mark) {
                [void]$fs.Seek($Mark, [System.IO.SeekOrigin]::Begin)
                $buf = New-Object byte[] ([int]($fs.Length - $Mark))
                [void]$fs.Read($buf, 0, $buf.Length)
                $out = @(([System.Text.Encoding]::UTF8.GetString($buf)) -split "`r?`n" | Where-Object { $_ -ne '' })
            }
        } finally { $fs.Close() }
    } catch { }
    return , $out
}

function Select-LiveLines($Lines, [string]$Level) {
    return , @(@($Lines) | Where-Object { $_ -match ('^\d\d:\d\d:\d\d\s+' + $Level + '\s') })
}

# Motorun is islevini (Job_Plan, Job_Undo ...) arayuz is parcaciginin yaptigi gibi cagirir; sayac durumunu korur
function Invoke-LiveJob([string]$Fn, $Arg) {
    $keepP = $script:Preview; $keepS = $script:Silent
    $out = $null; $err = ''
    try { $out = & $Fn $Arg } catch { $err = $_.Exception.Message }
    finally { $script:Preview = $keepP; $script:Silent = $keepS }
    if ($out -is [System.Array]) {
        $h = @($out | Where-Object { $_ -is [hashtable] })
        if ($h.Count -gt 0) { $out = $h[$h.Count - 1] }
    }
    return @{ Out = $out; Err = $err }
}

# ---------------- okuma bekcisi ----------------
# Okuma isleri (Get-LiveReadJobs) hicbir sey yazmamali. Bir is yanlislikla yazmaya kalkarsa (ornegin onizleme bayragi unutulursa) is suresince
# asagidaki komutlar YEREL kapsamda "bos" islevlerle gizlenir: islem YAPILMAZ, deneme kaydedilir ve HATA olarak bildirilir. Islevler yerel kapsamda
# tanimlandigi icin is bitince kendiliginden kalkar (istisna olsa bile asil komutlar eski haline doner). Merkezi giris noktasi Invoke-Op da
# onizleme degilse hicbir sey yapmaz; Func, Mp, Feature ... dahil her ayar turu buradan gecer.
# Sinir: bekci yalnizca bu is parcaciginda calisan komutlari yakalar; ayri bir calisma alani (runspace) acan kod bekcinin disinda kalir.
$script:LiveGuardNames = @(
    'Set-Service', 'Stop-Service', 'Start-Service', 'Restart-Service', 'Suspend-Service', 'Resume-Service', 'New-Service', 'Remove-Service',
    'Set-MpPreference', 'Add-MpPreference', 'Remove-MpPreference',
    'Disable-ScheduledTask', 'Enable-ScheduledTask', 'Unregister-ScheduledTask', 'Register-ScheduledTask', 'Set-ScheduledTask',
    'Set-NetFirewallRule', 'New-NetFirewallRule', 'Remove-NetFirewallRule', 'Enable-NetFirewallRule', 'Disable-NetFirewallRule', 'Set-NetFirewallProfile',
    'Stop-Process', 'Restart-Computer', 'Stop-Computer',
    'Set-DnsClientServerAddress', 'Set-DnsClientDohServerAddress', 'Add-DnsClientDohServerAddress', 'Remove-DnsClientDohServerAddress',
    'Enable-WindowsOptionalFeature', 'Disable-WindowsOptionalFeature', 'Add-WindowsCapability', 'Remove-WindowsCapability',
    'Invoke-DismExe', 'Set-WinFeatureState', 'Set-WinCapabilityState', 'Add-AppxPackage',
    'Set-NetIPInterface', 'Set-NetConnectionProfile', 'Remove-AppxPackage', 'Remove-AppxProvisionedPackage',
    'Checkpoint-Computer', 'Enable-ComputerRestore', 'Disable-ComputerRestore', 'Set-ExecutionPolicy', 'Clear-RecycleBin', 'Optimize-Volume',
    'Enable-BitLocker', 'Disable-BitLocker', 'New-LocalUser', 'Remove-LocalUser', 'Disable-LocalUser', 'Enable-LocalUser', 'Set-LocalUser',
    'Set-ItemProperty', 'New-ItemProperty', 'Remove-ItemProperty',
    'Set-RegData', 'Remove-RegData', 'Set-SvcStart', 'Set-HostsBlock', 'Disable-KillSwitchNow', 'Invoke-Undo', 'Invoke-RestorePoint'
)
$script:LiveBlocked = New-Object System.Collections.ArrayList

function Add-LiveBlocked([string]$Name, [string]$ArgText) {
    $t = ($Name + ' ' + $ArgText).Trim()
    if ($t.Length -gt 160) { $t = $t.Substring(0, 160) + '...' }
    [void]$script:LiveBlocked.Add($t)
}

# Onizleme bayragi acik mi (bekci altindaki Invoke-Op / Invoke-Plan gölgeleri bunu sorar; $script:Preview burada dogru betik kapsamindan okunur)
function Test-LivePreviewOn { return ($script:Preview -eq $true) }

# Bir okuma isini bekci altinda calistirir; Invoke-LiveJob gibi @{ Out; Err } doner. Engellenen denemeler $script:LiveBlocked icinde kalir.
# Invoke-Op ve Invoke-Plan yalnizca ONIZLEME acikken asil islevi calistirir (onizleme sistemde hicbir sey degistirmez); degilse engellenir.
function Invoke-LiveGuarded([string]$Fn, $Arg) {
    $script:LiveBlocked.Clear()
    $origOp = $null; $origPlan = $null
    try { if (Test-Path -LiteralPath 'function:Invoke-Op') { $origOp = (Get-Item -LiteralPath 'function:Invoke-Op').ScriptBlock } } catch { }
    try { if (Test-Path -LiteralPath 'function:Invoke-Plan') { $origPlan = (Get-Item -LiteralPath 'function:Invoke-Plan').ScriptBlock } } catch { }
    $defs = New-Object System.Text.StringBuilder
    foreach ($n in $script:LiveGuardNames) {
        if ($n -cnotmatch '^[A-Za-z0-9-]+$') { continue }
        [void]$defs.Append('function ' + $n + ' { Add-LiveBlocked ''' + $n + ''' (($args | ForEach-Object { [string]$_ }) -join '' '') }' + "`n")
    }
    [void]$defs.Append('function Invoke-Op($Op) { if ((Test-LivePreviewOn) -and $null -ne $OrigOp) { & $OrigOp $Op } else { Add-LiveBlocked ''Invoke-Op'' ([string]$Op.T + '' '' + [string]$Op.Name + '' '' + [string]$Op.Path) } }' + "`n")
    [void]$defs.Append('function Invoke-Plan($Steps, [bool]$RestorePoint) { if ((Test-LivePreviewOn) -and $null -ne $OrigPlan) { & $OrigPlan $Steps $RestorePoint } else { Add-LiveBlocked ''Invoke-Plan'' ([string]@($Steps).Count + '' adım'') } }' + "`n")
    $res = & {
        param($JobFn, $JobArg, $DefText, $OrigOp, $OrigPlan)
        . ([scriptblock]::Create($DefText))
        Invoke-LiveJob $JobFn $JobArg
    } $Fn $Arg $defs.ToString() $origOp $origPlan
    if ($res -is [System.Array]) {
        $h = @($res | Where-Object { $_ -is [hashtable] })
        if ($h.Count -gt 0) { $res = $h[$h.Count - 1] }
    }
    if ($res -isnot [hashtable]) { $res = @{ Out = $null; Err = 'bekçi sonucu alınamadı' } }
    return $res
}

# ---------------- sistemden bagimsiz okumalar ----------------
function Get-LiveRegRaw([string]$Path, [string]$Name) {
    $r = @{ KeyExists = $false; Exists = $false; Kind = ''; Data = $null; Err = '' }
    $rp = Resolve-RegPath $Path
    $i = $rp.IndexOf('\')
    $root = $rp; $sub = ''
    if ($i -ge 0) { $root = $rp.Substring(0, $i); $sub = $rp.Substring($i + 1) }
    $hive = $null
    switch ($root.ToUpperInvariant()) {
        'HKLM' { $hive = [Microsoft.Win32.RegistryHive]::LocalMachine }
        'HKCU' { $hive = [Microsoft.Win32.RegistryHive]::CurrentUser }
        'HKU'  { $hive = [Microsoft.Win32.RegistryHive]::Users }
        'HKCR' { $hive = [Microsoft.Win32.RegistryHive]::ClassesRoot }
    }
    if ($null -eq $hive) { $r.Err = 'bilinmeyen kök: ' + $root; return $r }
    $base = $null
    try {
        $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey($hive, [Microsoft.Win32.RegistryView]::Registry64)
        $key = $base.OpenSubKey($sub, $false)
        if ($null -ne $key) {
            $r.KeyExists = $true
            if (@($key.GetValueNames()) -contains $Name) {
                $r.Exists = $true
                $r.Kind = $key.GetValueKind($Name).ToString()
                $r.Data = $key.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            }
            $key.Close()
        }
    } catch { $r.Err = $_.Exception.Message } finally { if ($null -ne $base) { $base.Close() } }
    return $r
}

function ConvertTo-LiveUInt([object]$V) {
    $l = [int64]$V
    return [uint32]($l -band [int64]4294967295)
}

function Test-LiveDataEqual([string]$Kind, $X, $Y) {
    switch ($Kind) {
        'Binary' {
            $a = [byte[]]@($X); $b = [byte[]]@($Y)
            if ($a.Length -ne $b.Length) { return $false }
            for ($i = 0; $i -lt $a.Length; $i++) { if ($a[$i] -ne $b[$i]) { return $false } }
            return $true
        }
        'MultiString' { return ((@($X) -join [string][char]0) -ceq (@($Y) -join [string][char]0)) }
        'DWord'       { return ((ConvertTo-LiveUInt $X) -eq (ConvertTo-LiveUInt $Y)) }
        'QWord'       { return ([int64]$X -eq [int64]$Y) }
        default       { return ([string]$X -ceq [string]$Y) }
    }
}

function Test-LiveRawEqual($A, $B) {
    if ([bool]$A.Exists -ne [bool]$B.Exists) { return $false }
    if (-not [bool]$A.Exists) { return $true }
    if ([string]$A.Kind -ne [string]$B.Kind) { return $false }
    return (Test-LiveDataEqual ([string]$A.Kind) $A.Data $B.Data)
}

function Format-LiveRaw($R) {
    if ($null -eq $R -or -not [bool]$R.Exists) { return '(yok)' }
    $v = $R.Data
    if ($R.Kind -eq 'Binary') { $b = [byte[]]@($v); $s = (($b | Select-Object -First 12 | ForEach-Object { '{0:x2}' -f $_ }) -join ' '); if ($b.Length -gt 12) { $s += ' …' }; return ('bin[' + $b.Length + ']=' + $s) }
    if ($R.Kind -eq 'MultiString') { return ('[' + (@($v) -join '|') + ']') }
    return ([string]$R.Kind + ':' + [string]$v)
}

function Get-LiveSvcSnap([string]$Name) {
    $s = @{ K = 'Svc'; Name = $Name; Exists = $false; Start = -1; Delayed = $false; Status = '' }
    try {
        $tpl = $Name
        try { $tpl = Get-SvcTemplateName $Name } catch { }
        $key = 'HKLM\SYSTEM\CurrentControlSet\Services\' + $tpl
        $r = Get-LiveRegRaw $key 'Start'
        if ($r.Exists) { $s.Exists = $true; $s.Start = [int]$r.Data }
        $d = Get-LiveRegRaw $key 'DelayedAutostart'
        if ($d.Exists) { $s.Delayed = ([int]$d.Data -eq 1) }
        $sc = $null
        try { $sc = New-Object System.ServiceProcess.ServiceController($Name) } catch { }
        if ($null -ne $sc) {
            $st = $sc.Status.ToString()
            if ($st -eq 'StartPending' -or $st -eq 'ContinuePending') { $st = 'Running' }
            elseif ($st -eq 'StopPending' -or $st -eq 'PausePending') { $st = 'Stopped' }
            $s.Status = $st
        }
    } catch { }
    return $s
}

function Get-LiveTaskSnap([string]$Path, [string]$Name) {
    $s = @{ K = 'Task'; Path = $Path; Name = $Name; Exists = $false; Enabled = $false }
    try {
        $t = Get-ScheduledTask -TaskPath $Path -TaskName $Name -ErrorAction Stop
        if ($null -ne $t) { $s.Exists = $true; $s.Enabled = [bool]$t.Settings.Enabled }
    } catch { }
    return $s
}

function Get-LiveMpSnap([string]$Name) {
    $s = @{ K = 'Mp'; Name = $Name; Ok = $false; Value = '' }
    try {
        $v = (Get-MpPreference -ErrorAction Stop).$Name
        $s.Ok = $true
        $s.Value = (@($v) -join ',')
        if ($v -is [bool]) { $s.Value = ([string]$v).ToLowerInvariant() }
    } catch { }
    return $s
}

function Get-LiveFwSnap([string]$Group) {
    $s = @{ K = 'Fw'; Group = $Group; Rules = @{} }
    try {
        foreach ($r in @(Get-NetFirewallRule -Group $Group -ErrorAction Stop)) { $s.Rules[[string]$r.Name] = ([string]$r.Enabled -eq 'True') }
    } catch { }
    return $s
}

function Get-LiveEvtSnap([string]$Name) {
    $s = @{ K = 'EvtLog'; Name = $Name; Bytes = -1 }
    try {
        $cfg = New-Object System.Diagnostics.Eventing.Reader.EventLogConfiguration($Name)
        $s.Bytes = [int64]$cfg.MaximumSizeInBytes
        $cfg.Dispose()
    } catch { }
    return $s
}

function Get-LiveFeatSnap([string]$Name) {
    $s = @{ K = 'Feature'; Name = $Name; State = '' }
    try { $f = Get-WindowsOptionalFeature -Online -FeatureName $Name -ErrorAction Stop; if ($null -ne $f) { $s.State = [string]$f.State } }
    catch {
        # yonetici degil: Win32_OptionalFeature (1 acik, 2 kapali, 3 kaynak dosyalari kaldirilmis)
        try {
            $w = @(Get-CimInstance -ClassName Win32_OptionalFeature -Filter ("Name='" + ($Name -creplace "[^A-Za-z0-9\.\-_]", '') + "'") -ErrorAction Stop | Where-Object { $null -ne $_ })
            if ($w.Count -gt 0) {
                switch ([int]$w[0].InstallState) { 1 { $s.State = 'Enabled' } 2 { $s.State = 'Disabled' } 3 { $s.State = 'DisabledWithPayloadRemoved' } }
            }
        } catch { }
    }
    # yeniden baslatma bekleyen degisiklik etkin durum sayilir (uygulamanin olcumuyle ayni)
    if ($s.State -eq 'EnablePending') { $s.State = 'Enabled' } elseif ($s.State -eq 'DisablePending') { $s.State = 'Disabled' }
    return $s
}

function Get-LiveFuncSnap([string]$Name) {
    $s = @{ K = 'Func'; Name = $Name; Data = '' }
    switch ($Name) {
        'HibernateOff' {
            $r = Get-LiveRegRaw 'HKLM\SYSTEM\CurrentControlSet\Control\Power' 'HibernateEnabled'
            $s.Data = ('hib=' + $(if ($r.Exists) { [string]$r.Data } else { '?' }))
        }
        'GuestOff' {
            $u = $null
            try { $u = Get-LocalUser -ErrorAction Stop | Where-Object { $_.SID.Value -like '*-501' } | Select-Object -First 1 } catch { }
            $s.Data = $(if ($null -ne $u) { 'guest=' + [string]$u.Enabled + ';name=' + [string]$u.Name } else { 'guest=yok' })
        }
        'NetBiosOff' {
            $base = 'HKLM\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces'
            $parts = New-Object System.Collections.ArrayList
            foreach ($n in @((Get-RegSubKeyNames $base) | Where-Object { $_ -like 'Tcpip_*' } | Sort-Object)) {
                $r = Get-LiveRegRaw ($base + '\' + $n) 'NetbiosOptions'
                [void]$parts.Add($n + '=' + $(if ($r.Exists) { [string]$r.Data } else { '-' }))
            }
            $s.Data = ($parts -join ';')
        }
        'LockoutPolicy' {
            $v = $null
            try { $v = Get-SecPolValues } catch { }
            if ($null -ne $v) { $s.Data = ('thr=' + [string]$v['LockoutBadCount'] + ';dur=' + [string]$v['LockoutDuration'] + ';win=' + [string]$v['ResetLockoutCount']) }
        }
        'AuditLogon' {
            $txt = ''
            try { $txt = ((& auditpol.exe /get /category:* /r 2>&1) | Out-String) } catch { }
            $s.Data = $txt
        }
        { $_ -eq 'HostsBlock' -or $_ -eq 'HostsUnblock' } {
            $txt = ''
            try { $txt = [System.IO.File]::ReadAllText((Join-Path $env:WINDIR 'System32\drivers\etc\hosts')) } catch { $txt = '' }
            if ($txt.Length -gt 200000) { $txt = 'sha:' + (Get-ShortHash $txt) }
            $s.Name = 'Hosts'
            $s.Data = $txt
        }
        'PowerMode' {
            $ac = ''; $dc = ''; $cur = ''
            try { if (Initialize-SysNative) { $ac = [string][WH.Sys]::GetUserMode($false); $dc = [string][WH.Sys]::GetUserMode($true); $cur = [string][WH.Sys]::GetMode() } } catch { }
            $s.Data = ('ac=' + $ac + ';dc=' + $dc + ';cur=' + $cur)
        }
        'PowerPlan' {
            $act = ''; $all = ''
            try { $o = (& powercfg.exe /getactivescheme 2>&1 | Out-String); if ($o -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') { $act = $Matches[1].ToLowerInvariant() } } catch { }
            try { $o2 = (& powercfg.exe /list 2>&1 | Out-String); $all = ((([regex]::Matches($o2, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}') | ForEach-Object { $_.Value.ToLowerInvariant() }) | Sort-Object) -join ',') } catch { }
            # Modern Bekleme'de ayar guc kipiyle uygulanir: yururlukteki kip de karsilastirilir
            $kip = ''
            try { if (Initialize-SysNative) { $kip = [string][WH.Sys]::GetMode() } } catch { }
            $s.Data = ('aktif=' + $act + ';kip=' + $kip + ';planlar=' + $all)
        }
    }
    return $s
}

function Get-LiveSnap($C) {
    $items = New-Object System.Collections.ArrayList
    foreach ($op in @($C.Ops)) {
        $it = $null
        try {
            switch ([string]$op.T) {
                'Reg'     { $it = @{ K = 'Reg'; Path = (Resolve-RegPath ([string]$op.Path)); Name = [string]$op.Name; Raw = (Get-LiveRegRaw ([string]$op.Path) ([string]$op.Name)) } }
                'Svc'     { $it = Get-LiveSvcSnap ([string]$op.Name) }
                'Task'    { $it = Get-LiveTaskSnap ([string]$op.Path) ([string]$op.Name) }
                'Mp'      { $it = Get-LiveMpSnap ([string]$op.Name) }
                'Fw'      { $it = Get-LiveFwSnap ([string]$op.Group) }
                'EvtLog'  { $it = Get-LiveEvtSnap ([string]$op.Name) }
                'Feature' { $it = Get-LiveFeatSnap ([string]$op.Name) }
                'Cap'     { $it = @{ K = 'Cap'; Name = [string]$op.Match; Data = (Get-LiveCapState ([string]$op.Match)) } }
                'Func'    { $it = Get-LiveFuncSnap ([string]$op.Name) }
            }
        } catch { $it = @{ K = 'Hata'; Name = [string]$op.T; Err = $_.Exception.Message } }
        if ($null -eq $it) { $it = @{ K = 'Yok'; Name = [string]$op.T } }
        [void]$items.Add($it)
    }
    return , $items.ToArray()
}

function Compare-LiveItem($X, $Y) {
    switch ([string]$X.K) {
        'Reg' {
            if (-not (Test-LiveRawEqual $X.Raw $Y.Raw)) { return ($X.Path + '\' + $X.Name + ': ' + (Format-LiveRaw $X.Raw) + ' -> ' + (Format-LiveRaw $Y.Raw)) }
        }
        'Svc' {
            if ([int]$X.Start -ne [int]$Y.Start -or [bool]$X.Delayed -ne [bool]$Y.Delayed -or [string]$X.Status -ne [string]$Y.Status) {
                return ('hizmet ' + $X.Name + ': başlangıç ' + $X.Start + '/' + $X.Delayed + '/' + $X.Status + ' -> ' + $Y.Start + '/' + $Y.Delayed + '/' + $Y.Status)
            }
        }
        'Task' { if ([bool]$X.Exists -ne [bool]$Y.Exists -or [bool]$X.Enabled -ne [bool]$Y.Enabled) { return ('görev ' + $X.Path + $X.Name + ': ' + $X.Enabled + ' -> ' + $Y.Enabled) } }
        'Mp'   { if ([string]$X.Value -ne [string]$Y.Value) { return ('Defender ' + $X.Name + ': ' + $X.Value + ' -> ' + $Y.Value) } }
        'Fw' {
            foreach ($k in @($X.Rules.Keys)) { if ($Y.Rules.ContainsKey($k) -and [bool]$X.Rules[$k] -ne [bool]$Y.Rules[$k]) { return ('güvenlik duvarı kuralı ' + $k + ': ' + $X.Rules[$k] + ' -> ' + $Y.Rules[$k]) } }
        }
        'EvtLog'  { if ([int64]$X.Bytes -ne [int64]$Y.Bytes) { return ('olay günlüğü ' + $X.Name + ': ' + $X.Bytes + ' -> ' + $Y.Bytes) } }
        'Feature' { if ([string]$X.State -ne [string]$Y.State) { return ('özellik ' + $X.Name + ': ' + $X.State + ' -> ' + $Y.State) } }
        'Cap' { if ([string]$X.Data -ne 'okunamadi' -and [string]$Y.Data -ne 'okunamadi' -and [string]$X.Data -ne [string]$Y.Data) { return ('bileşen ' + $X.Name + ': ' + $X.Data + ' -> ' + $Y.Data) } }
        'Func' {
            if ([string]$X.Name -eq 'PowerMode') {
                # geri alma bos kullanici kipini Dengeli olarak yazar; karsilastirma yalnizca yururlukteki kipe bakar
                $cx = ''; $cy = ''
                if ([string]$X.Data -match 'cur=(.*)$') { $cx = $Matches[1] }
                if ([string]$Y.Data -match 'cur=(.*)$') { $cy = $Matches[1] }
                if ($cx -ne $cy) { return ('güç kipi: ' + $cx + ' -> ' + $cy) }
            } elseif ([string]$X.Data -ne [string]$Y.Data) { return ('işlev ' + $X.Name + ': ' + (Get-LiveShort ([string]$X.Data)) + ' -> ' + (Get-LiveShort ([string]$Y.Data))) }
        }
    }
    return ''
}

function Get-LiveShort([string]$S, [int]$Max = 90) {
    $t = ($S -replace '\s+', ' ').Trim()
    if ($t.Length -gt $Max) { return ($t.Substring(0, $Max) + '…') }
    return $t
}

function Compare-LiveSnap($A, $B) {
    $diff = New-Object System.Collections.ArrayList
    $a = @($A); $b = @($B)
    for ($i = 0; $i -lt $a.Count -and $i -lt $b.Count; $i++) {
        $d = Compare-LiveItem $a[$i] $b[$i]
        if ($d -ne '') { [void]$diff.Add($d) }
    }
    return , $diff.ToArray()
}

# ---------------- diske yazilan eski durum (surec oluse bile geri yuklenir) ----------------
# Ikili (REG_BINARY) veri kurtarma dosyasinda onaltilik metin olarak tutulur ('' = bos dizi)
function ConvertTo-LiveHex($Data) {
    if ($null -eq $Data) { return '' }
    $sb = New-Object System.Text.StringBuilder
    foreach ($x in [byte[]]@($Data)) { [void]$sb.Append($x.ToString('x2', [System.Globalization.CultureInfo]::InvariantCulture)) }
    return $sb.ToString()
}

function ConvertFrom-LiveHex([string]$Text) {
    if ($Text -cnotmatch '^(?:[0-9a-fA-F]{2})*$') { throw 'kurtarma dosyasındaki ikili veri okunamadı (onaltılık metin değil)' }
    $n = [int]($Text.Length / 2)
    $out = New-Object byte[] $n
    for ($i = 0; $i -lt $n; $i++) { $out[$i] = [Convert]::ToByte($Text.Substring(2 * $i, 2), 16) }
    return , $out
}

function ConvertTo-LiveSerial($Snap) {
    $out = New-Object System.Collections.ArrayList
    foreach ($it in @($Snap)) {
        if ([string]$it.K -eq 'Reg') {
            $r = $it.Raw
            $data = $null
            if ([bool]$r.Exists) {
                switch ([string]$r.Kind) {
                    'Binary'      { $data = ConvertTo-LiveHex $r.Data }
                    'MultiString' { $data = @($r.Data) }
                    'QWord'       { $data = [string][int64]$r.Data }
                    'DWord'       { $data = [string][int64]$r.Data }
                    default       { $data = [string]$r.Data }
                }
            }
            [void]$out.Add(@{ K = 'Reg'; Path = [string]$it.Path; Name = [string]$it.Name; KeyExists = [bool]$r.KeyExists; Exists = [bool]$r.Exists; Kind = [string]$r.Kind; Data = $data })
        } elseif ([string]$it.K -eq 'Fw') {
            $rules = @()
            foreach ($k in @($it.Rules.Keys)) { $rules += @{ Name = [string]$k; On = [bool]$it.Rules[$k] } }
            [void]$out.Add(@{ K = 'Fw'; Group = [string]$it.Group; Rules = $rules })
        } else {
            $h = @{}
            foreach ($k in @($it.Keys)) { $h[[string]$k] = $it[$k] }
            [void]$out.Add($h)
        }
    }
    return , $out.ToArray()
}

function Save-LiveInflight([string]$Id, $Snap) {
    try {
        $ser = ConvertTo-LiveSerial $Snap
        $o = @{ Id = $Id; Time = (Get-Date).ToString('s'); Items = $ser }
        $json = ConvertTo-Json -InputObject $o -Depth 8
        [System.IO.File]::WriteAllText((Join-Path (Get-LiveDir) 'ozellik-yarim.json'), $json, (New-Object System.Text.UTF8Encoding($false)))
    } catch { Add-LiveRow 'kurtarma' $Id 'UYARI' ('eski durum diske yazılamadı: ' + $_.Exception.Message) }
}

function Clear-LiveInflight {
    try { $f = Join-Path (Get-LiveDir) 'ozellik-yarim.json'; if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue } } catch { }
}

# Bir ogenin eski halini sisteme geri yazar (bagimsiz geri yukleme: motorun geri alma yoluna guvenmez)
function Restore-LiveItem($It) {
    $k = [string]$It.K
    if ($k -eq 'Reg') {
        $path = [string]$It.Path; $name = [string]$It.Name
        $exists = [bool]$It.Exists
        if ($exists) {
            $kind = [string]$It.Kind
            $val = $It.Data
            switch ($kind) {
                'Binary'      { $val = ConvertFrom-LiveHex ([string]$val) }
                'MultiString' { $val = [string[]]@($val) }
                'QWord'       { $val = [int64]$val }
                'DWord'       { $val = [int64]$val }
            }
            Set-RegData $path $name $kind $val
        } else {
            Remove-RegData $path $name (-not [bool]$It.KeyExists)
        }
        return
    }
    if ($k -eq 'Svc') {
        if ([int]$It.Start -gt 1) { Set-SvcStart ([string]$It.Name) ([int]$It.Start) ([bool]$It.Delayed) }
        if ([string]$It.Status -eq 'Running') {
            $sc = $null; try { $sc = New-Object System.ServiceProcess.ServiceController([string]$It.Name) } catch { }
            if ($null -ne $sc -and $sc.Status.ToString() -ne 'Running' -and [int]$It.Start -ne 4) { Start-Service -Name ([string]$It.Name) -ErrorAction SilentlyContinue }
        }
        return
    }
    if ($k -eq 'Task') {
        if (-not [bool]$It.Exists) { return }
        if ([bool]$It.Enabled) { Enable-ScheduledTask -TaskPath ([string]$It.Path) -TaskName ([string]$It.Name) -ErrorAction SilentlyContinue | Out-Null }
        else { Disable-ScheduledTask -TaskPath ([string]$It.Path) -TaskName ([string]$It.Name) -ErrorAction SilentlyContinue | Out-Null }
        return
    }
    if ($k -eq 'Mp') {
        if (-not [bool]$It.Ok) { return }
        $v = [string]$It.Value
        $splat = @{}
        if ($v -eq 'true') { $splat[[string]$It.Name] = $true }
        elseif ($v -eq 'false') { $splat[[string]$It.Name] = $false }
        elseif ($v -match '^-?\d+$') { $splat[[string]$It.Name] = [int]$v }
        else { $splat[[string]$It.Name] = $v }
        Set-MpPreference @splat -ErrorAction SilentlyContinue
        return
    }
    if ($k -eq 'Fw') {
        foreach ($r in @($It.Rules)) { Set-NetFirewallRule -Name ([string]$r.Name) -Enabled $(if ([bool]$r.On) { 'True' } else { 'False' }) -ErrorAction SilentlyContinue }
        return
    }
    if ($k -eq 'EvtLog') {
        if ([int64]$It.Bytes -gt 0) { & wevtutil.exe sl ([string]$It.Name) ('/ms:' + [int64]$It.Bytes) | Out-Null }
        return
    }
    if ($k -eq 'Func') { Restore-LiveFunc $It; return }
    if ($k -eq 'Cap') {
        if ([string]$It.Data -eq 'kurulu' -and (Get-LiveCapState ([string]$It.Name)) -ne 'kurulu') { [void](Set-WinCapabilityState ([string]$It.Name) $true) }
        return
    }
    if ($k -eq 'Feature') {
        $want = [string]$It.State
        if ($want -eq '') { return }
        $cur = [string](Get-LiveFeatSnap ([string]$It.Name)).State
        $wantOn = ($want -eq 'Enabled' -or $want -eq 'EnablePending')
        $curOn = ($cur -eq 'Enabled' -or $cur -eq 'EnablePending')
        if ($cur -ne '' -and $wantOn -ne $curOn) {
            # Windows yeniden baslatma beklerken kapatilmis ozelligi acmak cogu zaman ya hemen reddedilir ya da DISM asili kalir
            # (cihazda 15 dakika). Ozellik kurtarma listesine girer, yeniden baslatmadan sonraki tam denetimin basinda acilir.
            if ($wantOn) {
                $rn = [string](Get-CbsRebootPending)
                if ($rn -eq '' -and $script:DismNeedsReboot) { $rn = 'DISM' }
                if ($rn -ne '') { throw ('Windows bir bileşen değişikliği için yeniden başlatılmayı bekliyor (' + $rn + '); ' + [string]$It.Name + ' yeniden başlatmadan sonraki tam denetimin başında yeniden açılacak') }
            }
            [void](Set-WinFeatureState ([string]$It.Name) $wantOn)
        }
        return
    }
    if ($k -eq 'Appx') {
        if (-not (Restore-AppxItem @{ Name = [string]$It.Name; Locs = @($It.Locs) })) { throw ('uygulama paket klasöründen geri kaydedilemedi: ' + [string]$It.Name) }
        return
    }
}

function Restore-LiveFunc($It) {
    $d = [string]$It.Data
    switch ([string]$It.Name) {
        'Hosts' {
            if ($d -ne '' -and $d -notlike 'sha:*') { [System.IO.File]::WriteAllText((Join-Path $env:WINDIR 'System32\drivers\etc\hosts'), $d, (New-Object System.Text.UTF8Encoding($false))) }
        }
        'HibernateOff' {
            if ($d -eq 'hib=1') { & powercfg.exe /hibernate on | Out-Null } elseif ($d -eq 'hib=0') { & powercfg.exe /hibernate off | Out-Null }
        }
        'GuestOff' {
            if ($d -match '^guest=True;name=(.+)$') { Enable-LocalUser -Name $Matches[1] -ErrorAction SilentlyContinue }
        }
        'NetBiosOff' {
            $base = 'HKLM\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces'
            foreach ($p in @($d -split ';')) {
                if ($p -match '^(Tcpip_[^=]+)=(\d+)$') { Set-RegData ($base + '\' + $Matches[1]) 'NetbiosOptions' 'DWord' ([int]$Matches[2]) }
            }
        }
        'LockoutPolicy' {
            if ($d -match 'thr=(\d+);dur=(\d+);win=(\d+)') {
                if ([int]$Matches[1] -eq 0) { & net.exe accounts /lockoutthreshold:0 | Out-Null }
                else { & net.exe accounts /lockoutthreshold:$($Matches[1]) /lockoutduration:$($Matches[2]) /lockoutwindow:$($Matches[3]) | Out-Null }
            }
        }
        'PowerMode' {
            if ($d -match 'ac=([^;]*);dc=([^;]*);cur=(.*)$') {
                $pa = $Matches[1]; $pd = $Matches[2]; $pc = $Matches[3]
                if ($pa -eq '') { $pa = $pc }
                if ($pd -eq '') { $pd = $pa }
                if ($pa -ne '' -and (Initialize-SysNative)) { [void][WH.Sys]::SetMode($pa, $pd) }
            }
        }
        'PowerPlan' {
            $kip = ''
            if ($d -match ';kip=([^;]*);') { $kip = $Matches[1] }
            if ($kip -ne '') { try { if (Initialize-SysNative) { [void][WH.Sys]::SetMode($kip, $kip) } } catch { } }
            if ($d -match 'aktif=([0-9a-f-]{36});(?:kip=[^;]*;)?planlar=(.*)$') {
                $act = $Matches[1]; $keep = @($Matches[2] -split ',' | Where-Object { $_ -ne '' })
                & powercfg.exe /setactive $act | Out-Null
                $now = (& powercfg.exe /list 2>&1 | Out-String)
                foreach ($m in [regex]::Matches($now, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}')) {
                    $g = $m.Value.ToLowerInvariant()
                    if ($keep -notcontains $g -and $g -ne $act) { & powercfg.exe /delete $g | Out-Null }
                }
            }
        }
    }
}

function Restore-LiveSnap($Serial) {
    foreach ($it in @($Serial)) { try { Restore-LiveItem $it } catch { Add-LiveRow 'kurtarma' ([string]$it.K) 'HATA' ('geri yazılamadı: ' + $_.Exception.Message) } }
}

# Onceki (oluse ya da zaman asimina ugrayan) bir turdan kalan degisiklik varsa geri yukler
function Restore-LiveInflight {
    $f = Join-Path (Get-LiveDir) 'ozellik-yarim.json'
    if (-not (Test-Path -LiteralPath $f)) { return }
    try {
        $o = ConvertFrom-Json -InputObject ([System.IO.File]::ReadAllText($f))
        if ((Get-LiveMode) -ne 'tam') {
            Add-LiveRow 'kurtarma' ([string]$o.Id) 'UYARI' 'önceki turdan yarım kalan değişiklik var; "tam" kipte (yönetici) geri yüklenecek'
            return
        }
        Add-LiveRow 'kurtarma' ([string]$o.Id) 'BILGI' ('önceki turdan yarım kalan değişiklik geri yükleniyor (' + [string]$o.Time + ')')
        $items = @($o.Items)
        # Reg ogeleri ConvertFrom-Json ile PSCustomObject gelir; Restore-LiveItem alan adlariyla calisir
        $errs = New-Object System.Collections.ArrayList
        foreach ($it in $items) {
            if (Test-LiveDismItem $it) {
                if (Test-LiveItemCurrent $it) { continue }
                $blk = Get-LiveDismBlock
                if ($blk -ne '') { [void]$errs.Add([string]$it.Name + ': ' + $blk); [void]$script:LiveStopKinds.Add([string]$it.K); continue }
                if ($script:LiveRestoreFailed.Contains([string]$it.Name)) { [void]$errs.Add([string]$it.Name + ': bu denetimde zaten geri yüklenemedi'); continue }
            }
            Add-LiveCompTouched ([string]$it.K) ([string]$it.Name)
            try { Restore-LiveItem $it }
            catch {
                [void]$errs.Add($_.Exception.Message)
                if (Test-LiveDismItem $it) { [void]$script:LiveRestoreFailed.Add([string]$it.Name); [void]$script:LiveStopKinds.Add([string]$it.K) }
            }
        }
        Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue
        if ($errs.Count -gt 0) {
            # kaybolmasin: kalici kurtarma listesine tasinir, sonraki tam denetimde yeniden denenir
            Add-LiveUnrestored ([string]$o.Id) $items ($errs -join ' | ')
            Add-LiveRow 'kurtarma' ([string]$o.Id) 'HATA' ('yarım kalan değişiklik geri yüklenemedi (kurtarma listesine alındı): ' + (Get-LiveShort ($errs -join ' | ') 200))
        } else { Add-LiveRow 'kurtarma' ([string]$o.Id) 'OK' 'yarım kalan değişiklik geri yüklendi' }
    } catch { Add-LiveRow 'kurtarma' 'yarim' 'HATA' ('yarım kalan değişiklik geri yüklenemedi: ' + $_.Exception.Message) }
}

# ---------------- beklenen sonuc: ayarin tanimindaki degerler uygulandi mi ----------------
function Get-LiveExpectMismatch($C, $Snap, $Lines) {
    $bad = New-Object System.Collections.ArrayList
    $ops = @($C.Ops); $sn = @($Snap)
    $skipText = (@($Lines) | Where-Object { $_ -match '\sSKIP\s' }) -join "`n"
    for ($i = 0; $i -lt $ops.Count -and $i -lt $sn.Count; $i++) {
        $op = $ops[$i]; $s = $sn[$i]
        switch ([string]$op.T) {
            'Reg' {
                $label = Get-RegOpLabel $op
                if (Test-RegDenied $label) { continue }
                if ($op.Del -eq $true) {
                    if ([bool]$s.Raw.Exists) { [void]$bad.Add($label + ': silinmedi (' + (Format-LiveRaw $s.Raw) + ')') }
                    continue
                }
                $kind = [string]$op.Kind
                if ([string]::IsNullOrEmpty($kind)) { $kind = 'DWord' }
                if (-not [bool]$s.Raw.Exists) { [void]$bad.Add($label + ': değer yazılmadı'); continue }
                if ([string]$s.Raw.Kind -ne $kind) { [void]$bad.Add($label + ': tür ' + $s.Raw.Kind + ' (beklenen ' + $kind + ')'); continue }
                $want = $op.Value
                $ok = $false
                try { $ok = Test-LiveDataEqual $kind $want $s.Raw.Data } catch { $ok = $false }
                if (-not $ok) { [void]$bad.Add($label + ': ' + (Format-LiveRaw $s.Raw) + ' (beklenen ' + [string]$want + ')') }
            }
            'Svc' {
                if (-not [bool]$s.Exists) { continue }
                if ($skipText -match [regex]::Escape([string]$op.Name)) { continue }
                $target = 3
                try { $target = [int]$script:StartMap[[string]$op.Start] } catch { }
                if ([int]$s.Start -ne $target) { [void]$bad.Add('hizmet ' + $op.Name + ': başlangıç ' + $s.Start + ' (beklenen ' + $target + ')') }
            }
            'Task' {
                if (-not [bool]$s.Exists) { continue }
                $wantEnable = ([string]$op.Action -eq 'Enable')
                if ([bool]$s.Enabled -ne $wantEnable) { [void]$bad.Add('görev ' + $op.Path + $op.Name + ': ' + $(if ($s.Enabled) { 'açık' } else { 'kapalı' }) + ' (beklenen ' + $(if ($wantEnable) { 'açık' } else { 'kapalı' }) + ')') }
            }
        }
    }
    return , $bad.ToArray()
}

# ---------------- hangi ayar nasil denenir ----------------
# Donus: hkcu | hklm | hizmet | ozel | onizleme | uygunsuz
# Canlı uygulanıp günlükle geri alınabilen Func işlemleri
$script:LiveFuncLive = @('PowerPlan', 'HibernateOff', 'GuestOff', 'NetBiosOff', 'AuditLogon', 'LockoutPolicy', 'HostsBlock', 'HostsUnblock')
# Tek yönlü Func işlemleri: tam kipte canlı uygulanır ama geri alınamaz (silme/temizlik/önbellek); doğrulama ikinci önizlemeyle yapılır
$script:LiveOneWay = @('OptimizeDrive', 'FlushDns', 'CleanTemp', 'CleanThumbs', 'CleanPrefetch', 'CleanWer', 'CleanLogs', 'CleanDumps', 'CleanSetupLogs', 'CleanDelivery',
    'CleanUpdateCache', 'CleanShader', 'CleanAppCaches', 'CleanBrowsers', 'CleanRecent', 'CleanMgr', 'DismCleanup', 'EmptyRecycleBin')
# Tam kipte bile yalnızca önizlenenler: bilgisayarın kurtarılabilirliğini azaltan ya da kullanıcının gördüğü veriyi geri
# getirilemez biçimde silenler. Önbellek ve geçici dosya temizliği (kendiliğinden yeniden oluşur) canlı denenir.
$script:LiveKeepPreview = @('CleanRestorePoints', 'CleanMgr', 'CleanRecent')
$script:LiveKeepPreviewWhy = @{
    'CleanRestorePoints' = 'eski geri yükleme noktalarını siler; silinen noktaya dönülemez'
    'CleanMgr'           = 'önceki Windows kurulumunu (Windows.old) ve güncelleme yedeklerini siler; önceki sürüme dönüş kalkar'
    'CleanRecent'        = 'son kullanılan dosyalar listesini siler; kullanıcının geçmişi geri gelmez'
}

function Get-LiveKeepPreviewWhy($C) {
    $w = New-Object System.Collections.ArrayList
    foreach ($op in @($C.Ops)) {
        if ([string]$op.T -ne 'Func') { continue }
        $n = [string]$op.Name
        if ($script:LiveKeepPreviewWhy.ContainsKey($n)) { [void]$w.Add($n + ': ' + [string]$script:LiveKeepPreviewWhy[$n]) }
    }
    if ($w.Count -eq 0) { return '' }
    return ('tam kipte de yalnızca önizlendi (' + ($w.ToArray() -join '; ') + ')')
}

# Tek yönlü işlem bu bilgisayarda canlı denenebilir mi? Dönüş: '' (evet) ya da neden metni
function Get-LiveOneWayBlock([string]$Name) {
    if ($Name -eq 'EmptyRecycleBin') {
        $n = -1
        try { $n = [int](New-Object -ComObject Shell.Application).NameSpace(10).Items().Count } catch { }
        if ($n -ne 0) { return ('Geri Dönüşüm Kutusu dolu (' + $(if ($n -lt 0) { '?' } else { [string]$n }) + ' öğe): veri kaybı olmasın diye yalnızca önizlendi') }
    }
    return ''
}

function Get-LiveGroup($C) {
    $pr = $sync.Profile
    try { if (-not (Test-OsOk ([string]$C.OS) $pr)) { return 'uygunsuz' } } catch { }
    $types = @(@($C.Ops) | ForEach-Object { [string]$_.T } | Sort-Object -Unique)
    if ($types -contains 'Cap' -or $types -contains 'Appx' -or $types -contains 'Feature') { return 'bilesen' }
    $funcs = @(@($C.Ops) | Where-Object { [string]$_.T -eq 'Func' } | ForEach-Object { [string]$_.Name })
    foreach ($fn in $funcs) {
        if ($script:LiveKeepPreview -contains $fn) { return 'onizleme' }
        if ($script:LiveFuncLive -notcontains $fn -and $script:LiveOneWay -notcontains $fn) { return 'onizleme' }
    }
    if (@($funcs | Where-Object { $script:LiveOneWay -contains $_ }).Count -gt 0) { return 'tekyon' }
    if ([bool]$C.Irrev) { return 'onizleme' }
    if ($types.Count -eq 1 -and $types[0] -eq 'Reg') {
        $roots = @(@($C.Ops) | ForEach-Object { ([string]$_.Path).Split('\')[0].ToUpperInvariant() } | Sort-Object -Unique)
        if ($roots.Count -eq 1 -and ($roots[0] -eq 'HKCU' -or $roots[0] -eq 'HKU')) { return 'hkcu' }
        return 'hklm'
    }
    if (@($types | Where-Object { @('Svc', 'Task', 'Reg') -notcontains $_ }).Count -eq 0) { return 'hizmet' }
    return 'ozel'
}

function Get-LiveApplicable {
    if ($null -ne $script:LiveApplicable) { return $script:LiveApplicable }
    if ($null -eq $sync.Profile) { try { $pf = Get-SystemProfile; $sync.Profile = $pf } catch { } }
    $list = New-Object System.Collections.ArrayList
    foreach ($c in @($script:Catalog)) {
        $ok = $true
        try { $ok = [bool](Test-OsOk ([string]$c.OS) $sync.Profile) } catch { $ok = $true }
        if ($ok) { [void]$list.Add($c) }
    }
    $script:LiveApplicable = $list.ToArray()
    return $script:LiveApplicable
}

function Get-LiveJournalAfter([datetime]$Since) {
    $best = $null
    try {
        foreach ($f in @(Get-ChildItem -LiteralPath ([string]$sync.BackupDir) -Filter 'yedek-*.jsonl' -ErrorAction SilentlyContinue)) {
            if ($f.LastWriteTime -ge $Since.AddSeconds(-1)) { if ($null -eq $best -or $f.LastWriteTime -gt $best.LastWriteTime) { $best = $f } }
        }
    } catch { }
    if ($null -eq $best) { return '' }
    return [string]$best.FullName
}

function Wait-LiveSvc($Snap0, $C) {
    # hizmet durumu (calisiyor / durdu) gecikmeli degisir: eski haline donene kadar en cok 12 sn bekler (yalniz hizmet ogeleri yoklanir)
    $ops = @($C.Ops); $s0 = @($Snap0)
    for ($t = 0; $t -lt 12; $t++) {
        $same = $true
        for ($i = 0; $i -lt $ops.Count -and $i -lt $s0.Count; $i++) {
            if ([string]$ops[$i].T -ne 'Svc') { continue }
            if ((Compare-LiveItem $s0[$i] (Get-LiveSvcSnap ([string]$ops[$i].Name))) -ne '') { $same = $false; break }
        }
        if ($same) { break }
        Start-Sleep -Milliseconds 1000
    }
    return (Get-LiveSnap $C)
}

# ---------------- bir ayarin tam turu ----------------
function Invoke-LiveRoundTrip($C, [string]$Mode) {
    $id = [string]$C.Id
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $defects = New-Object System.Collections.ArrayList
    $notes = New-Object System.Collections.ArrayList
    $snap0 = Get-LiveSnap $C
    $p0 = Get-TweakPending $C
    $hasSvc = (@(@($C.Ops) | Where-Object { [string]$_.T -eq 'Svc' }).Count -gt 0)
    $oneWay = @(@($C.Ops) | Where-Object { [string]$_.T -eq 'Func' -and $script:LiveOneWay -contains [string]$_.Name } | ForEach-Object { [string]$_.Name })
    # olculebilirlik motorla ayni tanimdan gelir (Get-TweakPending -1 donuyorsa olculemez)
    $measurable = ($p0 -ge 0)
    $allMeas = (@(@($C.Ops) | Where-Object { -not (Test-LiveOpMeasurable $_) }).Count -eq 0)

    # 1) onizleme: hicbir sey yazmaz; olcumle tutarli mi
    $mk = Get-LiveLogMark
    $pv = Invoke-LiveJob 'Job_Plan' @{ Steps = (New-StepsFromIds @($id)); Preview = $true; RestorePoint = $false }
    $plan = Select-LiveLines (Get-LiveLogSince $mk) 'PLAN'
    if ($pv.Err -ne '') { [void]$defects.Add('önizleme çöktü: ' + $pv.Err) }
    else {
        $chg = [int]$pv.Out.Changes
        if ($allMeas -and $p0 -ge 0 -and $chg -ne $p0) { [void]$defects.Add('önizleme ' + $chg + ' değişiklik diyor, ölçüm ' + $p0 + ' bekleyen diyor') }
        $after = Get-LiveSnap $C
        $dd = Compare-LiveSnap $snap0 $after
        if ($dd.Count -gt 0) { [void]$defects.Add('önizleme sistemi değiştirdi: ' + ($dd -join '; ')) }
    }
    if ($Mode -ne 'tam') {
        $st = 'OK'; if ($defects.Count -gt 0) { $st = 'HATA' }
        $txt = 'önizleme ' + $(if ($pv.Err -eq '') { [string]$pv.Out.Changes + ' değişiklik, ' + [string]$pv.Out.Skipped + ' atlanan' } else { 'başarısız' }) + '; ölçüm=' + $p0
        if ($defects.Count -gt 0) { $txt += '; ' + ($defects -join ' | ') }
        Add-LiveRow 'tur' $id $st $txt $sw.ElapsedMilliseconds
        return
    }

    # 1b) tek yonlu islem bu bilgisayarda canli denenemiyorsa yalnizca onizleme (neden yazilir)
    foreach ($ow in $oneWay) {
        $why = Get-LiveOneWayBlock $ow
        if ($why -ne '') {
            $txt = 'önizleme ' + $(if ($pv.Err -eq '') { [string]$pv.Out.Changes + ' değişiklik' } else { 'başarısız' }) + '; ' + $why
            if ($defects.Count -gt 0) { Add-LiveRow 'tur' $id 'HATA' ($txt + '; ' + ($defects -join ' | ')) $sw.ElapsedMilliseconds } else { Add-LiveRow 'tur' $id 'BILGI' $txt $sw.ElapsedMilliseconds }
            return
        }
    }
    $plan0 = @($plan | ForEach-Object { ($_ -replace '^\d\d:\d\d:\d\d\s+PLAN\s+', '') })

    # 2) gercek tur: eski durum diske yazilir, sonra uygulanir
    Save-LiveInflight $id $snap0
    Add-LiveTouched $C
    $t0 = Get-Date
    $restoredBy = ''
    try {
        $mk1 = Get-LiveLogMark
        $r1 = Invoke-LiveJob 'Job_Plan' @{ Steps = (New-StepsFromIds @($id)); Preview = $false; RestorePoint = $false }
        $log1 = Get-LiveLogSince $mk1
        $errs1 = Select-LiveLines $log1 'ERR'
        if ($r1.Err -ne '') { [void]$defects.Add('uygulama çöktü: ' + $r1.Err) }
        elseif ([int]$r1.Out.Errors -gt 0) { [void]$defects.Add('uygulama ' + [string]$r1.Out.Errors + ' hata verdi: ' + (Get-LiveShort ($errs1 -join ' | ') 200)) }
        $changes = 0; $skipped = 0
        if ($r1.Err -eq '') { $changes = [int]$r1.Out.Changes; $skipped = [int]$r1.Out.Skipped }

        $snap1 = Get-LiveSnap $C
        $p1 = Get-TweakPending $C
        $mis = Get-LiveExpectMismatch $C $snap1 $log1
        if ($mis.Count -gt 0) {
            $denied = (Test-TweakBlocked $C)
            if ($denied) { [void]$notes.Add('Windows korumalı: ' + (Get-LiveShort ($mis -join '; ') 160)) }
            else { [void]$defects.Add('uygulanan değer okunamıyor: ' + (Get-LiveShort ($mis -join '; ') 240)) }
        }
        if ($measurable) {
            if ($p1 -gt 0) {
                $mk2 = Get-LiveLogMark
                $pv2 = Invoke-LiveJob 'Job_Plan' @{ Steps = (New-StepsFromIds @($id)); Preview = $true; RestorePoint = $false }
                $plan2 = Select-LiveLines (Get-LiveLogSince $mk2) 'PLAN'
                $txt = 'uygulamadan sonra ölçüm ' + $p1 + ' bekleyen diyor'
                if ($plan2.Count -gt 0) { $txt += ': ' + (Get-LiveShort (($plan2 | ForEach-Object { ($_ -replace '^\d\d:\d\d:\d\d\s+PLAN\s+', '') }) -join '; ') 220) }
                if (Test-TweakBlocked $C) { [void]$notes.Add($txt) } else { [void]$defects.Add($txt) }
            }
            elseif ($p1 -lt 0) { [void]$defects.Add('uygulamadan sonra ölçülemiyor') }
        }
        # uygulananlar listesi
        if ($measurable -and $p1 -eq 0 -and $changes -gt 0 -and $p0 -gt 0) {
            $ap = Get-AppliedIds
            if ($ap -notcontains $id) { [void]$defects.Add('ayar uygulandı ama “uygulanmış ayarlar” listesine yazılmadı') }
        }

        # 2b) tek yonlu islem: ikinci onizleme ile dogrulama (bekleyen is azalmali; silinen dosyalar geri gelmez)
        $oneTxt = ''
        if ($oneWay.Count -gt 0) {
            $mkw = Get-LiveLogMark
            $pvw = Invoke-LiveJob 'Job_Plan' @{ Steps = (New-StepsFromIds @($id)); Preview = $true; RestorePoint = $false }
            $planw = @((Select-LiveLines (Get-LiveLogSince $mkw) 'PLAN') | ForEach-Object { ($_ -replace '^\d\d:\d\d:\d\d\s+PLAN\s+', '') })
            $n0 = Get-LivePlanFiles $plan0
            $n2 = Get-LivePlanFiles $planw
            $done1 = @((Select-LiveLines $log1 'OK') | ForEach-Object { ($_ -replace '^\d\d:\d\d:\d\d\s+OK\s+', '') })
            $oneTxt = 'tek yönlü (' + ($oneWay -join ',') + '): önizleme ' + $(if ($n0 -ge 0) { [string]$n0 + ' dosya' } else { (Get-LiveShort ($plan0 -join '; ') 80) }) + ' → uygulandı: ' + (Get-LiveShort ($done1 -join '; ') 120)
            if ($pvw.Err -ne '') { [void]$defects.Add('uygulamadan sonraki önizleme çöktü: ' + $pvw.Err) }
            elseif ($n0 -ge 0 -and $n2 -ge 0) {
                $oneTxt += ' → kalan ' + [string]$n2 + ' dosya'
                if ($n0 -gt 5 -and $n2 -ge $n0) { [void]$defects.Add('uygulandı dendi ama ikinci önizleme aynı sayıda dosya görüyor (' + $n0 + '→' + $n2 + '); hiçbir şey silinmemiş olabilir') }
                elseif ($n2 -gt 0 -and $n0 -gt 0 -and $n2 -gt [math]::Max(3, [int]($n0 * 0.25))) { [void]$notes.Add('kalan ' + $n2 + '/' + $n0 + ' dosya (kullanımda ya da korumalı olabilir)') }
            }
            if ($done1.Count -eq 0 -and $r1.Err -eq '' -and [int]$r1.Out.Skipped -eq 0 -and [int]$r1.Out.Errors -eq 0) { [void]$defects.Add('uygulama ne yapıldı ne atlandı satırı yazdı') }
        }

        # 3) geri al
        $jf = Get-LiveJournalAfter $t0
        if ($changes -gt 0 -and $jf -eq '' -and $oneWay.Count -eq 0) { [void]$defects.Add('değişiklik yapıldı ama geri alma günlüğü yazılmadı') }
        if ($jf -ne '') {
            $mk3 = Get-LiveLogMark
            $r2 = Invoke-LiveJob 'Job_Undo' @{ File = $jf }
            $log3 = Get-LiveLogSince $mk3
            if ($r2.Err -ne '') { [void]$defects.Add('geri alma çöktü: ' + $r2.Err) }
            elseif ([int]$r2.Out.Errors -gt 0) { [void]$defects.Add('geri alma ' + [string]$r2.Out.Errors + ' hata verdi: ' + (Get-LiveShort ((Select-LiveLines $log3 'ERR') -join ' | ') 200)) }
        }
        $snap2 = $null
        if ($hasSvc) { $snap2 = Wait-LiveSvc $snap0 $C } else { $snap2 = Get-LiveSnap $C }
        $d2 = Compare-LiveSnap $snap0 $snap2
        if ($d2.Count -gt 0) {
            [void]$defects.Add('geri alma eski durumu döndürmedi: ' + (Get-LiveShort ($d2 -join '; ') 240))
            # bagimsiz geri yukleme: sistem yine de eski haline getirilir
            Restore-LiveSnap (ConvertTo-LiveSerial $snap0)
            $restoredBy = 'bağımsız geri yükleme yapıldı'
            $d3 = Compare-LiveSnap $snap0 (Get-LiveSnap $C)
            if ($d3.Count -gt 0) {
                [void]$defects.Add('bağımsız geri yükleme de eski haline getiremedi: ' + (Get-LiveShort ($d3 -join '; ') 200))
                # kalici kurtarma listesine yazilir (sonraki tam denetimin basinda yeniden denenir) ve bu turden canli deneme durdurulur
                Add-LiveUnrestored $id (ConvertTo-LiveSerial $snap0) ($d3 -join '; ')
                foreach ($it0 in @($snap0)) { if ($null -ne $it0) { [void]$script:LiveStopKinds.Add([string]$it0.K) } }
            }
        }
        $p2 = Get-TweakPending $C
        if ($measurable -and $p2 -ne $p0) { [void]$defects.Add('geri almadan sonra ölçüm ' + $p2 + ' (başlangıç ' + $p0 + ')') }
        if ($measurable -and $p0 -gt 0 -and $p2 -gt 0) {
            $ap2 = Get-AppliedIds
            if ($ap2 -contains $id) { [void]$defects.Add('geri alındı ama “uygulanmış ayarlar” listesinde kaldı') }
        }
        Clear-LiveInflight
        $st = 'OK'
        if ($defects.Count -gt 0) { $st = 'HATA' } elseif ($notes.Count -gt 0) { $st = 'UYARI' }
        $txt = 'değişiklik=' + $changes + ' atlanan=' + $skipped + ' ölçüm ' + $p0 + '→' + $p1 + '→' + $p2
        if ($oneTxt -ne '') { $txt += '; ' + $oneTxt }
        if ($notes.Count -gt 0) { $txt += '; ' + ($notes -join ' | ') }
        if ($defects.Count -gt 0) { $txt += '; ' + ($defects -join ' | ') }
        if ($restoredBy -ne '') { $txt += '; ' + $restoredBy }
        Add-LiveRow 'tur' $id $st $txt $sw.ElapsedMilliseconds
    } catch {
        # beklenmeyen hata: eski hale getirmeyi dene
        try { Restore-LiveSnap (ConvertTo-LiveSerial $snap0); Clear-LiveInflight } catch { }
        Add-LiveRow 'tur' $id 'HATA' ('tur çöktü: ' + $_.Exception.Message + ' (eski hale getirildi)') $sw.ElapsedMilliseconds
    }
}

# Islem motorun olcumune giriyor mu (Get-TweakPending ile ayni tanim)
function Test-LiveOpMeasurable($Op) {
    $t = [string]$Op.T
    if (@('Reg', 'Svc', 'Task', 'Mp', 'EvtLog', 'Cap', 'Feature', 'DxGlobal', 'NetLatency') -contains $t) { return $true }
    return ($t -eq 'Func' -and $script:FuncStateful -contains [string]$Op.Name)
}

# Bir geri yukleme basarisiz olunca o turden (Feature, Cap, ...) canli deneme durdurulur
$script:LiveStopKinds = New-Object System.Collections.ArrayList

# Kalici kurtarma listesi: denetim bir degisikligi geri alamadiysa sonraki tam denetimin basinda yeniden denenir
function Get-LiveUnrestoredFile { return (Join-Path (Get-LiveDir) 'ozellik-geri-yuklenemedi.json') }

# JSON dizisini duz liste olarak okur. Windows PowerShell 5.1'de ConvertFrom-Json diziyi tek nesne olarak dondurur;
# @() ile sarilinca ic ice dizi olur ve listeye geri yazilinca her calismada bir kat daha icine girer (cihazda goruldu:
# [[[{FeatWorkFolders}]],{FeatHyperV}]). Ic ice diziler acilir; boylece eski bicimde yazilmis dosya da onarilir.
function Add-LiveFlat($List, $X) {
    if ($null -eq $X) { return }
    if ($X -is [System.Array] -or $X -is [System.Collections.ArrayList]) { foreach ($y in $X) { Add-LiveFlat $List $y }; return }
    [void]$List.Add($X)
}

function ConvertFrom-LiveJsonList([string]$Text) {
    $out = New-Object System.Collections.ArrayList
    if ([string]::IsNullOrWhiteSpace($Text)) { return $out.ToArray() }
    Add-LiveFlat $out (ConvertFrom-Json -InputObject $Text)
    return $out.ToArray()
}

function Get-LiveUnrestored {
    $f = Get-LiveUnrestoredFile
    if (-not (Test-Path -LiteralPath $f)) { return @() }
    try { return (ConvertFrom-LiveJsonList ([System.IO.File]::ReadAllText($f))) } catch { return @() }
}

function Save-LiveUnrestoredList($List) {
    $f = Get-LiveUnrestoredFile
    $arr = @($List)
    if ($arr.Count -eq 0) { try { if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force -ErrorAction Stop } } catch { }; return }
    try { [System.IO.File]::WriteAllText($f, (ConvertTo-Json -InputObject $arr -Depth 8), (New-Object System.Text.UTF8Encoding($false))) } catch { }
}

function Add-LiveUnrestored([string]$Id, $Serial, [string]$Why) {
    $list = New-Object System.Collections.ArrayList
    foreach ($e in @(Get-LiveUnrestored)) { if ([string]$e.Id -ne $Id) { [void]$list.Add($e) } }
    $now = (Get-Date).ToString('s')
    [void]$list.Add(@{ Id = $Id; Time = $now; Why = $Why; Items = @($Serial); Build = (Get-LiveBuildTag); Tried = $now })
    Save-LiveUnrestoredList $list
    Add-LiveRisky $Serial $Why
}

# Windows derlemesi (derleme.UBR). İsteğe bağlı bileşenlerin içeriği Windows Update'te derlemeye göre yayımlanır.
function Get-LiveBuildTag {
    $b = 0
    try { $b = [int](Get-OsBuildNumber) } catch { $b = 0 }
    $u = 0
    try { $u = [int](Get-RegValue 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion' 'UBR' 0) } catch { $u = 0 }
    return ([string]$b + '.' + [string]$u)
}

# Bileşenin içeriği bu derleme için Windows Update'te yoksa (0x800F0950) aynı derlemede 3 gün dolmadan yeniden denenmez.
# Gerçek bilgisayarda (18.11.2026) Adım Kaydedicisi Windows önizleme derlemesinde geri kurulamadı; her tam denetimin başında
# yeniden denemek yalnızca süre harcayıp aynı hatayı yazıyordu. Derleme değişince ya da 3 gün geçince yeniden denenir.
function Test-LiveRetryDeferred($E, [string]$Build, [datetime]$Now) {
    try {
        if ([string]$E.Why -notmatch '0x800F0950') { return $false }
        if ([string]$E.Build -eq '' -or [string]$E.Build -ne $Build) { return $false }
        $t = [datetime]::MinValue
        if ($E.Tried -is [datetime]) { $t = [datetime]$E.Tried }
        elseif (-not [datetime]::TryParse([string]$E.Tried, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$t)) { return $false }
        $age = ($Now - $t).TotalHours
        return ($age -ge 0 -and $age -lt 72)
    } catch { return $false }
}

# Kalici risk gecmisi: bu bilgisayarda bir kez geri yuklenemeyen Windows ozelligi / bileseni canli turda bir daha DEGISTIRILMEZ
# (geri yuklense bile). Gercek bilgisayarda (17.11.2026) Sanal Makine Platformu kapatildiktan sonra dosyalari yerelde bulunamadi
# (0x800F0912) ve Windows Update'ten saatlerce indirilemedi. Liste elle silinmedikce kalir: ozellik-riskli.json
function Get-LiveRiskFile { return (Join-Path (Get-LiveDir) 'ozellik-riskli.json') }

function Get-LiveRiskyNames {
    $names = New-Object System.Collections.ArrayList
    $f = Get-LiveRiskFile
    try {
        if (Test-Path -LiteralPath $f) {
            foreach ($e in @(ConvertFrom-LiveJsonList ([System.IO.File]::ReadAllText($f)))) { $n = [string]$e.Name; if ($n -ne '' -and -not $names.Contains($n)) { [void]$names.Add($n) } }
        }
    } catch { }
    # gecis: risk listesinden once geri yuklenemeyen ya da yarim kalan ozellik/bilesenler de riskli sayilir
    foreach ($e in @(Get-LiveUnrestored)) { foreach ($it in @($e.Items)) { if (@('Feature', 'Cap') -contains [string]$it.K) { $n = [string]$it.Name; if ($n -ne '' -and -not $names.Contains($n)) { [void]$names.Add($n) } } } }
    try {
        $yf = Join-Path (Get-LiveDir) 'ozellik-yarim.json'
        if (Test-Path -LiteralPath $yf) {
            $y = ConvertFrom-Json -InputObject ([System.IO.File]::ReadAllText($yf))
            foreach ($it in @($y.Items)) { if (@('Feature', 'Cap') -contains [string]$it.K) { $n = [string]$it.Name; if ($n -ne '' -and -not $names.Contains($n)) { [void]$names.Add($n) } } }
        }
    } catch { }
    return $names.ToArray()
}

function Add-LiveRisky($Items, [string]$Why) {
    try {
        $f = Get-LiveRiskFile
        $cur = New-Object System.Collections.ArrayList
        if (Test-Path -LiteralPath $f) {
            foreach ($e in @(ConvertFrom-LiveJsonList ([System.IO.File]::ReadAllText($f)))) { if ($null -ne $e -and [string]$e.Name -ne '') { [void]$cur.Add(@{ K = [string]$e.K; Name = [string]$e.Name; Why = [string]$e.Why; Time = [string]$e.Time }) } }
        }
        $added = 0
        foreach ($it in @($Items)) {
            if ($null -eq $it -or @('Feature', 'Cap') -notcontains [string]$it.K) { continue }
            $n = [string]$it.Name
            if ($n -eq '' -or @($cur | Where-Object { $_.Name -eq $n }).Count -gt 0) { continue }
            [void]$cur.Add(@{ K = [string]$it.K; Name = $n; Why = (Get-LiveShort $Why 300); Time = (Get-Date).ToString('s') })
            $added++
        }
        if ($added -gt 0) { [System.IO.File]::WriteAllText($f, (ConvertTo-Json -InputObject @($cur.ToArray()) -Depth 4), (New-Object System.Text.UTF8Encoding($false))) }
    } catch { }
}

# Bu denetimde geri yuklemesi basarisiz olan ozellik/bilesen adlari (ayni ozellik ayni denetimde ikinci kez uzun sure denenmez)
$script:LiveRestoreFailed = New-Object System.Collections.ArrayList

# Denetimin canlı değiştirdiği ayarlar ve Windows özellik/bileşenleri. Son durum karşılaştırmasında başlangıçtan farklı
# kalan bir ayarın bütün işlemleri Windows özelliği/bileşeniyse ve denetim bunlardan hiçbirine dokunmadıysa değişiklik
# denetimden gelmemiştir (gerçek bilgisayar 24.11.2026: XPS Görüntüleyici denetim sırasında Windows tarafından kuruldu;
# denetim, yeniden başlatma beklendiği için bileşen turlarını hiç yapmamıştı ama "başlangıçtan farklı" HATA yazıldı).
$script:LiveTouchedIds = @{}
$script:LiveCompTouched = @{}

function Add-LiveCompTouched([string]$Kind, [string]$Name) {
    if ($null -eq $script:LiveCompTouched) { $script:LiveCompTouched = @{} }
    if (($Kind -eq 'Feature' -or $Kind -eq 'Cap') -and $Name -ne '') { $script:LiveCompTouched[$Kind + ':' + $Name] = $true }
}

function Get-LiveOpCompName($Op) {
    if ([string]$Op.T -eq 'Cap') { return [string]$Op.Match }
    return [string]$Op.Name
}

function Add-LiveTouched($C) {
    if ($null -eq $C) { return }
    if ($null -eq $script:LiveTouchedIds) { $script:LiveTouchedIds = @{} }
    $script:LiveTouchedIds[[string]$C.Id] = $true
    foreach ($op in @($C.Ops)) { Add-LiveCompTouched ([string]$op.T) (Get-LiveOpCompName $op) }
}

# $true: ayarın bütün işlemleri Windows özelliği/bileşeni ve bu denetim hiçbirini değiştirmedi
function Test-LiveMovedOutside($C) {
    if ($null -eq $C) { return $false }
    if ($null -ne $script:LiveTouchedIds -and $script:LiveTouchedIds.ContainsKey([string]$C.Id)) { return $false }
    $ops = @($C.Ops)
    if ($ops.Count -eq 0) { return $false }
    foreach ($op in $ops) {
        $t = [string]$op.T
        if ($t -ne 'Feature' -and $t -ne 'Cap') { return $false }
        if ($null -ne $script:LiveCompTouched -and $script:LiveCompTouched.ContainsKey($t + ':' + (Get-LiveOpCompName $op))) { return $false }
    }
    return $true
}

# Denetim sonunda: kurtarma listesindeki kayıt bu arada eski durumuna döndüyse (ör. Windows bileşeni kuruldu) listeden çıkar
function Remove-LiveUnrestoredDone {
    if ((Get-LiveMode) -ne 'tam') { return }
    $list = @(Get-LiveUnrestored)
    if ($list.Count -eq 0) { return }
    $left = New-Object System.Collections.ArrayList
    foreach ($e in $list) {
        $its = @($e.Items)
        $all = ($its.Count -gt 0)
        foreach ($it in $its) {
            $ok = $false
            try { $ok = [bool](Test-LiveItemCurrent $it) } catch { $ok = $false }
            if (-not $ok) { $all = $false; break }
        }
        if ($all) { Add-LiveRow 'kurtarma' ([string]$e.Id) 'OK' ('önceki denetimden kalan değişiklik denetim sırasında eski durumuna döndü (' + [string]$e.Time + '); listeden çıkarıldı') }
        else { [void]$left.Add($e) }
    }
    if ($left.Count -ne $list.Count) { Save-LiveUnrestoredList $left }
}

# Ogeyi geri yuklemek icin DISM gerekiyor mu (Windows ozelligi / bileseni)
function Test-LiveDismItem($It) { return (@('Feature', 'Cap') -contains [string]$It.K) }

# DISM gerektiren oge zaten eski (istenen) durumunda mi? Oyleyse geri yuklemeye gerek yoktur; yeniden baslatma beklense de
# listeden duser (cihazda: ozellikler elle geri acildiktan sonra kurtarma listesi yeniden baslatma beklendigi icin bosalmadi)
function Test-LiveItemCurrent($It) {
    try {
        switch ([string]$It.K) {
            'Feature' { return ([string](Get-LiveFeatSnap ([string]$It.Name)).State -eq [string]$It.State) }
            'Cap' { $cur = Get-LiveCapState ([string]$It.Name); return ($cur -ne 'okunamadi' -and $cur -eq [string]$It.Data) }
        }
    } catch { }
    return $false
}

# Denetimin basinda: tam kipte yeniden geri yuklemeyi dener; okuma kipinde yalnizca bildirir
function Restore-LiveUnrestored {
    $list = @(Get-LiveUnrestored)
    if ($list.Count -eq 0) { return }
    if ((Get-LiveMode) -ne 'tam') {
        foreach ($e in $list) { Add-LiveRow 'kurtarma' ([string]$e.Id) 'UYARI' ('önceki tam denetimden geri yüklenemeyen değişiklik (' + [string]$e.Time + '): ' + (Get-LiveShort ([string]$e.Why) 200) + '; tam kipte yeniden denenecek') }
        return
    }
    $build = Get-LiveBuildTag
    $now = Get-Date
    $left = New-Object System.Collections.ArrayList
    foreach ($e in $list) {
        if (Test-LiveRetryDeferred $e $build $now) {
            [void]$left.Add($e)
            $names = (@($e.Items) | ForEach-Object { [string]$_.Name }) -join ', '
            Add-LiveRow 'kurtarma' ([string]$e.Id) 'UYARI' ('önceki denetimden kalan bileşen bu Windows derlemesi (' + $build + ') için Windows Update’te bulunmuyor (0x800F0950); son deneme ' + [string]$e.Tried + '. Windows güncellenince ya da 3 gün sonra yeniden denenecek: ' + $names)
            continue
        }
        $errs = New-Object System.Collections.ArrayList
        $held = ''
        $already = 0
        foreach ($it in @($e.Items)) {
            if (Test-LiveDismItem $it) {
                if (Test-LiveItemCurrent $it) { $already++; continue }
                $blk = Get-LiveDismBlock
                if ($blk -ne '') { $held = $blk; [void]$script:LiveStopKinds.Add([string]$it.K); continue }
                if ($script:LiveRestoreFailed.Contains([string]$it.Name)) { [void]$errs.Add([string]$it.Name + ': bu denetimde zaten geri yüklenemedi'); continue }
            }
            Add-LiveCompTouched ([string]$it.K) ([string]$it.Name)
            try { Restore-LiveItem $it }
            catch {
                [void]$errs.Add($_.Exception.Message)
                if (Test-LiveDismItem $it) { [void]$script:LiveRestoreFailed.Add([string]$it.Name); [void]$script:LiveStopKinds.Add([string]$it.K) }
            }
        }
        if ($held -ne '' -and $errs.Count -eq 0) {
            [void]$left.Add($e)
            Add-LiveRow 'kurtarma' ([string]$e.Id) 'UYARI' ('önceki denetimden kalan Windows özelliği/bileşeni şimdi geri yüklenmedi: ' + $held + '; yeniden başlatıp tam denetimi tekrar çalıştırın')
        } elseif ($errs.Count -gt 0) {
            $why = Get-LiveShort ($errs -join ' | ') 300
            [void]$left.Add(@{ Id = [string]$e.Id; Time = $e.Time; Why = $why; Items = @($e.Items); Build = $build; Tried = $now.ToString('s') })
            # içerik bu derleme için yayımlanmamışsa (0x800F0950) bu bir ortam sınırıdır, uygulama hatası değil
            $lvl = 'HATA'
            if (@($errs | Where-Object { [string]$_ -notmatch '0x800F0950' }).Count -eq 0) { $lvl = 'UYARI' }
            Add-LiveRow 'kurtarma' ([string]$e.Id) $lvl ('önceki denetimden kalan değişiklik yine geri yüklenemedi: ' + (Get-LiveShort ($errs -join ' | ') 220))
        } elseif ($already -gt 0 -and $already -eq @($e.Items).Count) { Add-LiveRow 'kurtarma' ([string]$e.Id) 'OK' ('önceki denetimden kalan değişiklik zaten eski durumunda (' + [string]$e.Time + '); listeden çıkarıldı') }
        else { Add-LiveRow 'kurtarma' ([string]$e.Id) 'OK' ('önceki denetimden kalan değişiklik geri yüklendi (' + [string]$e.Time + ')') }
    }
    Save-LiveUnrestoredList $left
}

# DISM ile geri yukleme/tur su an baslatilabilir mi? '' = evet; aksi halde nedeni (yeniden baslatma bekleniyor, Windows Update
# kuruyor, bu oturumda DISM sure sinirini asti ya da bilesen hizmeti onceki isi hala surduruyor)
function Get-LiveDismBlock {
    if ($script:DismTimedOut) { return 'bu denetimde bir DISM işlemi süre sınırını aştı (bileşen hizmeti hâlâ çalışıyor olabilir)' }
    $b = Get-LiveServicingBlock
    if ($b -ne '') { return $b }
    $p = Wait-LiveCbsIdle 180
    if ($p -ne '') { return ('Windows bileşen hizmeti önceki bir işi sürdürüyor (' + $p + ')') }
    return ''
}

# PLAN satirlarindaki "N dosya" toplami; hic yoksa -1
function Get-LivePlanFiles($Lines) {
    $sum = 0; $any = $false
    foreach ($l in @($Lines)) {
        foreach ($m in [regex]::Matches([string]$l, '(\d+) dosya')) { $sum += [int]$m.Groups[1].Value; $any = $true }
    }
    if (-not $any) { return -1 }
    return $sum
}

function Test-LiveRoundTrips([string]$Group) {
    $mode = Get-LiveMode
    $list = New-Object System.Collections.ArrayList
    foreach ($c in @(Get-LiveApplicable)) {
        if ((Get-LiveGroup $c) -eq $Group) { [void]$list.Add($c) }
    }
    # yalnizca onizlenecek grup tam kipte de gercek uygulanmaz (cihazda 18.11.2026: bu satir yokken eski geri yukleme noktalari silindi)
    $runMode = $mode
    if ($Group -eq 'onizleme') { $runMode = 'oku' }
    $gtxt = [string]$list.Count + ' ayar; kip=' + $mode
    if ($runMode -ne $mode) { $gtxt += ' (bu grup her kipte yalnızca önizlenir)' }
    Add-LiveRow 'tur' ('grup:' + $Group) 'BILGI' $gtxt
    $n = 0
    foreach ($c in $list) {
        $n++
        if ($runMode -ne $mode) {
            $why = Get-LiveKeepPreviewWhy $c
            if ($why -ne '') { Add-LiveRow 'tur' ('neden:' + [string]$c.Id) 'BILGI' $why }
        }
        try { Invoke-LiveRoundTrip $c $runMode } catch { Add-LiveRow 'tur' ([string]$c.Id) 'HATA' ('tur çöktü: ' + $_.Exception.Message) }
        if (($n % 8) -eq 0) { try { Invoke-SmokeFlush } catch { } }
    }
}

# ---------------- ortam ve yetki ----------------
function Test-LiveEnv {
    $mode = Get-LiveMode
    $txt = 'kip=' + $mode + '; yönetici=' + [string][bool]$script:IsAdmin
    if ($script:LiveDowngraded) { $txt += ' (tam kip istendi ama yönetici değil: yalnızca okuma)' }
    Add-LiveRow 'ortam' 'kip' 'BILGI' $txt
    if ($null -eq $sync.Profile) { try { $pf = Get-SystemProfile; $sync.Profile = $pf } catch { } }
    $p = $sync.Profile
    if ($null -ne $p) {
        Add-LiveRow 'ortam' 'sistem' 'BILGI' ([string]$p.OsName + ' build ' + [string]$p.Build + '.' + [string]$p.UBR + '; ' + [string]$p.Model + '; ' + [string]$p.CpuName + '; ' + [string]$p.RamGB + ' GB; disk=' + [string]$p.DiskType + '; dizüstü=' + [string]$p.IsLaptop + '; yönetilen=' + [string]$p.IsManaged)
    } else { Add-LiveRow 'ortam' 'sistem' 'HATA' 'sistem profili okunamadı' }
    $cp = Get-LiveRegRaw 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'ConsentPromptBehaviorAdmin'
    $lua = Get-LiveRegRaw 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'EnableLUA'
    Add-LiveRow 'ortam' 'uac' 'BILGI' ('EnableLUA=' + $(if ($lua.Exists) { [string]$lua.Data } else { '?' }) + '; ConsentPromptBehaviorAdmin=' + $(if ($cp.Exists) { [string]$cp.Data } else { '?' }))
    # yeniden baslatma bekliyor mu: motor ile bagimsiz okuma ayni sonucu vermeli
    $eng = Get-PendingReboot
    $ind = New-Object System.Collections.ArrayList
    $cbs = Get-RegSubKeyNames 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing'
    if ($cbs -contains 'RebootPending') { [void]$ind.Add('CBS') }
    $wu = Get-RegSubKeyNames 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update'
    if ($wu -contains 'RebootRequired') { [void]$ind.Add('WU') }
    $pf = Get-LiveRegRaw 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager' 'PendingFileRenameOperations'
    $pfTxt = ''
    if ($pf.Exists) { $pfTxt = ' PendingFileRenameOperations=' + (Get-LiveShort ((@($pf.Data) -join '|') -replace [string][char]0, '') 160) }
    $engText = ($eng -join '|')
    $bad = New-Object System.Collections.ArrayList
    if (($wu -contains 'RebootRequired') -ne ($engText -match 'Windows Update')) { [void]$bad.Add('Windows Update') }
    if (($cbs -contains 'RebootPending') -ne ($engText -match 'Bile')) { [void]$bad.Add('Bileşen servisi') }
    if ($bad.Count -gt 0) { Add-LiveRow 'ortam' 'yeniden-baslatma' 'HATA' ('yeniden başlatma bekleme durumu uygulama ile kayıt defterinde uyuşmuyor (' + ($bad -join ', ') + '): uygulama [' + ($eng -join ', ') + '], kayıt defteri [' + ($ind -join ',') + ']') }
    else { Add-LiveRow 'ortam' 'yeniden-baslatma' 'OK' ('uygulama: [' + ($eng -join ', ') + ']; kayıt defteri: [' + ($ind -join ',') + ']' + $pfTxt) }
    # yarim kalan onceki tur ve onceki denetimden geri yuklenemeyenler
    Restore-LiveUnrestored
    Restore-LiveInflight
    $busy = Get-LiveServicingBlock
    if ($busy -ne '') { Add-LiveRow 'ortam' 'guncelleme' 'UYARI' ($busy + ': Windows özelliği / bileşeni turları bu durumda yapılmaz (yalnızca önizlenir)') }
    else { Add-LiveRow 'ortam' 'guncelleme' 'OK' 'Windows Update güncelleme kurmuyor; bileşen servisi yeniden başlatma beklemiyor' }
}

# Olculemeyen ayarlarin onem duzeyi. Kimlik bicimi: Id(Tur1+Tur2...). Yonetici degilken yalnizca yonetici isteyen okuyuculari
# (Windows bileseni / ozelligi, Defender) iceren ayarlar BILGI; digerleri ya da yonetici kipinde herhangi biri UYARI.
$script:LiveAdminOnlyOps = @('Cap', 'Feature', 'Mp')
function Get-LiveUnkLevel([string[]]$UnkIds, [bool]$Admin) {
    if ($Admin -or @($UnkIds).Count -eq 0) { return 'UYARI' }
    foreach ($u in @($UnkIds)) {
        $m = [regex]::Match([string]$u, '\(([^()]*)\)$')
        if (-not $m.Success) { return 'UYARI' }
        $kinds = @($m.Groups[1].Value -split '\+' | ForEach-Object { ($_ -split ':')[0] })
        if (@($kinds | Where-Object { $script:LiveAdminOnlyOps -contains $_ }).Count -eq 0) { return 'UYARI' }
    }
    return 'BILGI'
}

# ---------------- tum ayarlarin durum olcumu ----------------
function Test-LiveMeasure {
    $cat = @(Get-LiveApplicable)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $applied = 0; $pending = 0; $unk = 0; $blocked = 0; $oneWayN = 0
    $unkIds = New-Object System.Collections.ArrayList
    $slow = New-Object System.Collections.ArrayList
    # tek tek olcum PARTISIZ yapilir (her okuma taze); asagida arayuzun partili toplu olcumu bununla karsilastirilir
    foreach ($c in $cat) {
        $one = [System.Diagnostics.Stopwatch]::StartNew()
        $pv = -1
        try { $pv = Get-TweakPending $c } catch { Add-LiveRow 'olcum' ([string]$c.Id) 'HATA' ('ölçüm çöktü: ' + $_.Exception.Message); continue }
        $script:LiveState[[string]$c.Id] = $pv
        if ($pv -eq 0 -and (Test-TweakBlocked $c)) { $blocked++ }
        elseif ($pv -eq 0) { $applied++ }
        elseif ($pv -gt 0) { $pending++ }
        else {
            $fn = @(@($c.Ops) | Where-Object { [string]$_.T -eq 'Func' } | ForEach-Object { [string]$_.Name })
            $oneWayOnly = ($fn.Count -gt 0 -and $fn.Count -eq @($c.Ops).Count -and @($fn | Where-Object { $script:LiveOneWay -contains $_ -or $script:LiveKeepPreview -contains $_ -or $_ -eq 'TimeSync' }).Count -eq $fn.Count)
            if ($oneWayOnly) { $oneWayN++ }
            else { $unk++; [void]$unkIds.Add([string]$c.Id + '(' + ((@(@($c.Ops) | ForEach-Object { [string]$_.T + $(if ([string]$_.T -eq 'Func') { ':' + [string]$_.Name } else { '' }) } | Sort-Object -Unique)) -join '+') + ')') }
        }
        if ($one.ElapsedMilliseconds -gt 1500) { [void]$slow.Add([string]$c.Id + '=' + (Format-LiveMs $one.ElapsedMilliseconds)) }
    }
    Add-LiveRow 'olcum' 'ozet' 'BILGI' ([string]$cat.Count + ' ayar: uygulanmış ' + $applied + ', bekleyen ' + $pending + ', Windows korumalı ' + $blocked + ', tek yönlü (ölçülmez) ' + $oneWayN + ', ölçülemeyen ' + $unk) $sw.ElapsedMilliseconds
    if ($unk -gt 0) {
        # yonetici degilken DISM ile okunan bilesenler okunamaz; uygulama her zaman yonetici olarak acildigindan arayuzde okunur
        $lvl = Get-LiveUnkLevel @($unkIds) ([bool]$script:IsAdmin)
        $why = ' ayarın durumu ölçülemiyor (arayüzde durum etiketi gösterilmez): '
        if ($lvl -eq 'BILGI') { $why = ' ayarın durumu yönetici izni olmadan okunamıyor (Windows bileşenleri DISM ile okunur; uygulama her zaman yönetici olarak açıldığından arayüzde okunur): ' }
        Add-LiveRow 'olcum' 'olculemeyen' $lvl ($unk.ToString() + $why + ($unkIds -join ', '))
    }
    if ($slow.Count -gt 0) { Add-LiveRow 'olcum' 'yavas' 'BILGI' ('tek başına ölçülünce 1,5 saniyeden uzun sürenler (arayüz toplu ölçümde görev listesini bir kez okur): ' + ($slow -join ', ')) }
    # arayuzun kullandigi toplu olcum (Job_TweakStates, partili) tek tek (partisiz) olcumle ayni sonucu vermeli ve hizli olmali
    foreach ($page in @('opt', 'sec', 'org')) {
        $pw = [System.Diagnostics.Stopwatch]::StartNew()
        $r = Invoke-LiveJob 'Job_TweakStates' @{ Page = $page }
        $pms = $pw.ElapsedMilliseconds
        if ($r.Err -eq '' -and $pms -gt 20000) { Add-LiveRow 'olcum' ('hiz:' + $page) 'UYARI' ('arayüzün durum okuması ' + (Format-LiveMs $pms) + ' sürdü (20 sn üstü)') $pms }
        elseif ($r.Err -eq '') { Add-LiveRow 'olcum' ('hiz:' + $page) 'OK' ('arayüzün durum okuması ' + (Format-LiveMs $pms)) $pms }
        if ($r.Err -ne '') { Add-LiveRow 'olcum' ('sayfa:' + $page) 'HATA' ('Job_TweakStates çöktü: ' + $r.Err); continue }
        $st = $r.Out.States
        $bad = New-Object System.Collections.ArrayList
        foreach ($k in @($st.Keys)) {
            if ($script:LiveState.ContainsKey([string]$k)) {
                $mine = [int]$script:LiveState[[string]$k]
                $theirs = [int]$st[$k]
                if ($theirs -eq -3) { continue }
                if ($mine -ne $theirs) { [void]$bad.Add([string]$k + ' (tek tek ' + $mine + ', toplu ' + $theirs + ')') }
            }
        }
        if ($bad.Count -gt 0) { Add-LiveRow 'olcum' ('sayfa:' + $page) 'HATA' ('toplu ölçüm tutarsız: ' + ($bad -join '; ')) }
        else { Add-LiveRow 'olcum' ('sayfa:' + $page) 'OK' ([string]@($st.Keys).Count + ' ayar tutarlı; geri dönen ayar=' + [string]@($r.Out.Drift).Count) }
    }
}
