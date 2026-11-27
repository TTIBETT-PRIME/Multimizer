# ==================================================================
#  ÇÖZÜM MERKEZİ: "Bilgisayarım" bilgilerini toplama (arka plan işi)
#  Yalnızca okur. Bu bölüm çekirdekte durur çünkü Job_PcInfo arka plan çalışma alanında çalışır; sekmenin çizimi ve yorumlaması 126_solve_pc.ps1 içindedir.
# ==================================================================
function Get-PcText($V) {
    if ($null -eq $V) { return '' }
    $t = [regex]::Replace([string]$V, '[\u0000-\u001F\u007F]', ' ')
    return ([regex]::Replace($t, '\s+', ' ')).Trim()
}

# SMBIOS bellek türü kodu -> ad
function Get-PcMemTypeName([int]$Code) {
    switch ($Code) {
        18 { return 'DDR' }
        19 { return 'DDR2' }
        20 { return 'DDR2' }
        24 { return 'DDR3' }
        26 { return 'DDR4' }
        27 { return 'LPDDR' }
        28 { return 'LPDDR2' }
        29 { return 'LPDDR3' }
        30 { return 'LPDDR4' }
        34 { return 'DDR5' }
        35 { return 'LPDDR5' }
    }
    return ''
}

function Format-PcGb([double]$Gb) {
    $r = [math]::Round($Gb, 1)
    if ($r -eq [math]::Floor($r)) { return ([string][int]$r + ' GB') }
    return ($r.ToString('0.0', [System.Globalization.CultureInfo]::InvariantCulture) + ' GB')
}

function Format-PcSpan([double]$Hours) {
    if ($Hours -lt 1) { return ([string][int][math]::Floor($Hours * 60) + ' dk') }
    if ($Hours -lt 24) {
        $h = [int][math]::Floor($Hours)
        return ([string]$h + ' saat')
    }
    $d = [int][math]::Floor($Hours / 24)
    $h2 = [int][math]::Floor($Hours - $d * 24)
    return ([string]$d + ' gün ' + [string]$h2 + ' saat')
}

# Ortam ve veri yolu -> kısa tür adı
function Get-PcDiskKind([string]$Media, [string]$Bus) {
    if ($Bus -eq 'USB') { return 'USB disk' }
    if ($Bus -eq 'NVMe' -or $Bus -eq '17') { return 'NVMe SSD' }
    if ($Media -eq 'SSD' -or $Media -eq '4') { return 'SSD' }
    if ($Media -eq 'HDD' -or $Media -eq '3') { return 'HDD' }
    if ($Bus -eq 'SD' -or $Bus -eq 'MMC') { return 'Bellek kartı' }
    return 'Disk'
}

function Get-PcCim([string]$Class, [string]$Ns = 'root\cimv2', [string]$Filter = '') {
    try {
        if ($Filter -ne '') { return @(Get-CimInstance -Namespace $Ns -ClassName $Class -Filter $Filter -ErrorAction Stop) }
        return @(Get-CimInstance -Namespace $Ns -ClassName $Class -ErrorAction Stop)
    } catch { return @() }
}

# Bilgisayarı okur (yalnızca okuma). Her bölüm ayrı korunur; bir sorgu başarısız olursa o bölüm boş kalır.
function Get-PcInfo {
    $admin = $false
    try { $admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) } catch { }
    $I = @{ Ok = $true; At = (Get-Date).ToString('dd.MM.yyyy HH:mm'); Admin = $admin
        Machine = @{ Maker = ''; Model = ''; Kind = ''; IsVm = $false; Board = ''; Bios = ''; BiosDate = ''; Firmware = ''; SecureBoot = $null; Tpm = @{ Known = $false; Present = $false; Ready = $false; Version = '' } }
        Os = @{ Name = ''; Version = ''; Build = 0; Ubr = 0; Arch = ''; Installed = ''; Boot = ''; UptimeHours = [double]0 }
        Cpu = @{ Name = ''; Cores = 0; Threads = 0; Mhz = 0; L2KB = 0; L3KB = 0; Virt = $null }
        Mem = @{ TotalGB = [double]0; SlotCount = 0; MaxGB = [double]0; Modules = @() }
        Gpu = @(); Disks = @(); Net = @(); Battery = $null; Problems = @(); SysDrive = @{ Letter = ''; FreeGB = [double]0; SizeGB = [double]0 } }

    # bilgisayar, BIOS, anakart
    try {
        $cs = @(Get-PcCim 'Win32_ComputerSystem') | Select-Object -First 1
        if ($null -ne $cs) {
            $I.Machine.Maker = Get-PcText $cs.Manufacturer
            $I.Machine.Model = Get-PcText $cs.Model
            $I.Mem.TotalGB = [math]::Round([double]$cs.TotalPhysicalMemory / 1GB, 1)
            $I.Machine.IsVm = ((Get-PcText ($cs.Manufacturer + ' ' + $cs.Model)) -match 'Virtual|VMware|VirtualBox|KVM|QEMU|Parallels|Hyper-V')
            $pt = 0
            try { $pt = [int]$cs.PCSystemType } catch { }
            if ($pt -eq 1) { $I.Machine.Kind = 'Masaüstü' } elseif ($pt -eq 2) { $I.Machine.Kind = 'Dizüstü' } elseif ($pt -eq 3) { $I.Machine.Kind = 'İş istasyonu' }
        }
    } catch { }
    try {
        $bios = @(Get-PcCim 'Win32_BIOS') | Select-Object -First 1
        if ($null -ne $bios) {
            $I.Machine.Bios = Get-PcText ($bios.Manufacturer + ' ' + $bios.SMBIOSBIOSVersion)
            try { if ($null -ne $bios.ReleaseDate) { $I.Machine.BiosDate = ([datetime]$bios.ReleaseDate).ToString('dd.MM.yyyy') } } catch { }
        }
        $bb = @(Get-PcCim 'Win32_BaseBoard') | Select-Object -First 1
        if ($null -ne $bb) { $I.Machine.Board = Get-PcText ($bb.Manufacturer + ' ' + $bb.Product) }
    } catch { }
    try {
        $fw = Get-RegValue 'HKLM\SYSTEM\CurrentControlSet\Control' 'PEFirmwareType' $null
        if ($null -ne $fw) { if ([int]$fw -eq 2) { $I.Machine.Firmware = 'UEFI' } elseif ([int]$fw -eq 1) { $I.Machine.Firmware = 'Eski BIOS' } }
        $sb = Get-RegValue 'HKLM\SYSTEM\CurrentControlSet\Control\SecureBoot\State' 'UEFISecureBootEnabled' $null
        if ($null -ne $sb) { $I.Machine.SecureBoot = ([int]$sb -eq 1) }
    } catch { }
    try {
        $tp = @(Get-PcCim 'Win32_Tpm' 'root\cimv2\Security\MicrosoftTpm') | Select-Object -First 1
        if ($null -ne $tp) {
            $I.Machine.Tpm.Known = $true
            $I.Machine.Tpm.Present = $true
            $I.Machine.Tpm.Ready = ($tp.IsEnabled_InitialValue -eq $true -and $tp.IsActivated_InitialValue -eq $true)
            $I.Machine.Tpm.Version = (Get-PcText $tp.SpecVersion).Split(',')[0].Trim()
        } elseif ($admin) {
            $I.Machine.Tpm.Known = $true
        }
    } catch { }

    # Windows
    try {
        $os = @(Get-PcCim 'Win32_OperatingSystem') | Select-Object -First 1
        if ($null -ne $os) {
            $I.Os.Name = (Get-PcText $os.Caption) -replace '^Microsoft\s+', ''
            $I.Os.Arch = Get-PcText $os.OSArchitecture
            $b = 0
            [void][int]::TryParse([string]$os.BuildNumber, [ref]$b)
            $I.Os.Build = $b
            try { $I.Os.Installed = ([datetime]$os.InstallDate).ToString('dd.MM.yyyy') } catch { }
            try {
                $boot = [datetime]$os.LastBootUpTime
                $I.Os.Boot = $boot.ToString('dd.MM.yyyy HH:mm')
                $I.Os.UptimeHours = [math]::Round(((Get-Date) - $boot).TotalHours, 1)
            } catch { }
        }
        $I.Os.Version = [string](Get-RegValue 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion' 'DisplayVersion' '')
        $I.Os.Ubr = [int](Get-RegValue 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion' 'UBR' 0)
    } catch { }

    # işlemci
    try {
        $cp = @(Get-PcCim 'Win32_Processor')
        if ($cp.Count -gt 0) {
            $I.Cpu.Name = Get-PcText $cp[0].Name
            foreach ($c in $cp) { $I.Cpu.Cores += [int]$c.NumberOfCores; $I.Cpu.Threads += [int]$c.NumberOfLogicalProcessors }
            $I.Cpu.Mhz = [int]$cp[0].MaxClockSpeed
            $I.Cpu.L2KB = [int]$cp[0].L2CacheSize
            $I.Cpu.L3KB = [int]$cp[0].L3CacheSize
            if ($null -ne $cp[0].VirtualizationFirmwareEnabled) { $I.Cpu.Virt = ($cp[0].VirtualizationFirmwareEnabled -eq $true) }
        }
    } catch { }

    # bellek modülleri
    try {
        $mods = New-Object System.Collections.ArrayList
        foreach ($m in @(Get-PcCim 'Win32_PhysicalMemory')) {
            $tn = ''
            try { $tn = Get-PcMemTypeName ([int]$m.SMBIOSMemoryType) } catch { }
            [void]$mods.Add(@{ Slot = (Get-PcText $m.DeviceLocator); Bank = (Get-PcText $m.BankLabel); CapGB = [math]::Round([double]$m.Capacity / 1GB, 1); Type = $tn
                Rated = [int]$m.Speed; Running = [int]$m.ConfiguredClockSpeed; Maker = (Get-PcText $m.Manufacturer); Part = (Get-PcText $m.PartNumber) })
        }
        $I.Mem.Modules = $mods.ToArray()
        $arr = @(Get-PcCim 'Win32_PhysicalMemoryArray')
        foreach ($a in $arr) {
            $I.Mem.SlotCount += [int]$a.MemoryDevices
            $I.Mem.MaxGB += [math]::Round([double]$a.MaxCapacity / 1MB, 0)
        }
    } catch { }

    # ekran kartları
    try {
        $gl = New-Object System.Collections.ArrayList
        foreach ($g in @(Get-PcCim 'Win32_VideoController')) {
            $dd = ''
            try { if ($null -ne $g.DriverDate) { $dd = ([datetime]$g.DriverDate).ToString('dd.MM.yyyy') } } catch { }
            $res = ''
            if ([int]$g.CurrentHorizontalResolution -gt 0) { $res = [string][int]$g.CurrentHorizontalResolution + 'x' + [string][int]$g.CurrentVerticalResolution + ' @ ' + [string][int]$g.CurrentRefreshRate + ' Hz' }
            [void]$gl.Add(@{ Name = (Get-PcText $g.Name); Driver = (Get-PcText $g.DriverVersion); DriverDate = $dd; Res = $res })
        }
        $I.Gpu = $gl.ToArray()
    } catch { }

    # diskler
    try {
        $health = @{}
        try { foreach ($pd in @(Get-PhysicalDisk -ErrorAction Stop)) { $health[[string]$pd.DeviceId] = [string]$pd.HealthStatus } } catch { }
        $dl = New-Object System.Collections.ArrayList
        $phys = Get-SlvPhysDisks
        foreach ($d in @($phys)) {
            $h = ''
            if ($health.ContainsKey([string]$d.Number)) { $h = [string]$health[[string]$d.Number] }
            [void]$dl.Add(@{ Number = [int]$d.Number; Name = (Get-PcText $d.Name); Kind = (Get-PcDiskKind ([string]$d.Media) ([string]$d.Bus)); Bus = [string]$d.Bus
                SizeGB = [math]::Round([double]$d.Size / 1GB, 0); Style = [string]$d.Style; Letters = @($d.Letters); Health = $h; IsSystem = ($d.IsSystem -eq $true) })
        }
        $I.Disks = $dl.ToArray()
    } catch { }
    try {
        $sd = [string]$env:SystemDrive
        if ($sd -ne '') {
            $di = New-Object System.IO.DriveInfo -ArgumentList $sd
            $I.SysDrive.Letter = $sd
            $I.SysDrive.FreeGB = [math]::Round([double]$di.AvailableFreeSpace / 1GB, 1)
            $I.SysDrive.SizeGB = [math]::Round([double]$di.TotalSize / 1GB, 1)
        }
    } catch { }

    # ağ bağdaştırıcıları (yalnızca fiziksel)
    try {
        $nl = New-Object System.Collections.ArrayList
        foreach ($a in @(Get-NetAdapter -Physical -ErrorAction Stop)) {
            $mt = [string]$a.PhysicalMediaType
            $kind = 'Ağ'
            if ($mt -match '802\.11') { $kind = 'Wi-Fi' } elseif ($mt -match '802\.3') { $kind = 'Ethernet' } elseif ($mt -match 'Bluetooth') { $kind = 'Bluetooth' }
            [void]$nl.Add(@{ Name = (Get-PcText $a.InterfaceDescription); Kind = $kind; Speed = (Get-PcText $a.LinkSpeed); Up = ([string]$a.Status -eq 'Up') })
        }
        $I.Net = $nl.ToArray()
    } catch { }

    # pil
    try {
        $batt = @(Get-PcCim 'Win32_Battery') | Select-Object -First 1
        if ($null -ne $batt) {
            $bi = @{ Percent = [int]$batt.EstimatedChargeRemaining; Charging = ([int]$batt.BatteryStatus -ne 1); DesignMWh = 0; FullMWh = 0; WearPct = -1 }
            try {
                $ds = @(Get-PcCim 'BatteryStaticData' 'root\wmi') | Select-Object -First 1
                $fc = @(Get-PcCim 'BatteryFullChargedCapacity' 'root\wmi') | Select-Object -First 1
                if ($null -ne $ds) { $bi.DesignMWh = [int]$ds.DesignedCapacity }
                if ($null -ne $fc) { $bi.FullMWh = [int]$fc.FullChargedCapacity }
                if ($bi.DesignMWh -gt 0 -and $bi.FullMWh -gt 0) { $bi.WearPct = [int][math]::Max(0, [math]::Round(100 - ($bi.FullMWh * 100.0 / $bi.DesignMWh), 0)) }
            } catch { }
            $I.Battery = $bi
            if ($I.Machine.Kind -eq '') { $I.Machine.Kind = 'Dizüstü' }
        }
    } catch { }
    if ($I.Machine.IsVm) { $I.Machine.Kind = 'Sanal makine' }

    # sorunlu aygıtlar (devre dışı bırakılmış olanlar sayılmaz)
    try {
        $pl = New-Object System.Collections.ArrayList
        foreach ($p in @(Get-PcCim 'Win32_PnPEntity' 'root\cimv2' 'ConfigManagerErrorCode <> 0 AND ConfigManagerErrorCode <> 22')) {
            if ($pl.Count -ge 12) { break }
            [void]$pl.Add(@{ Name = (Get-PcText $p.Name); Code = [int]$p.ConfigManagerErrorCode })
        }
        $I.Problems = $pl.ToArray()
    } catch { }
    return $I
}

function Job_PcInfo($P) {
    try {
        Write-WhLog 'Bilgisayar bilgileri okunuyor (yalnızca okuma)...' 'INFO'
        $info = Get-PcInfo
        return @{ Ok = $true; Info = $info }
    } catch {
        Write-WhLog ('Bilgisayar bilgileri okunamadı: ' + $_.Exception.Message) 'ERR'
        return @{ Ok = $false; Error = $_.Exception.Message }
    }
}
