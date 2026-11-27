. "$PSScriptRoot/lib.ps1"
# Çözüm Merkezi "Bilgisayarım" sekmesi: toplama (sahte CIM ile), bölüm ve gözlem yorumlama, çizim, kopyalama.
Import-Fn 'Get-PcText', 'Get-PcMemTypeName', 'Format-PcGb', 'Format-PcSpan', 'Get-PcDiskKind', 'Get-PcCim', 'Get-PcInfo', 'Job_PcInfo', 'Get-PcMemSummary', 'Get-PcSecuritySummary',
    'Get-PcSections', 'New-PcAct', 'Get-PcNotes', 'Get-PcSummaryText', 'Load-SlPc', 'Complete-SlPc', 'Render-SlPc', 'Copy-SlPc', 'Init-SlPc', 'Update-PageMode_solve',
    'Invoke-PcAction', 'Start-PcJob', 'Start-PcJobNow', 'Start-PcUefi', 'Invoke-PcRescanAction', 'Invoke-PcMbr2gptAction', 'Job_Action', 'Invoke-ActionExtra'
function Write-WhLog([string]$Message, [string]$Level = 'INFO') { }
. "$PSScriptRoot/uifake.ps1"

# =====================================================================
#  1) küçük yardımcılar
# =====================================================================
Assert-Eq (Get-PcText "  LENOVO`t 82XV`r`n ") 'LENOVO 82XV' 'metin: denetim karakterleri ve boşluklar temizlenir'
Assert-Eq (Get-PcText $null) '' 'metin: boş değer'
Assert-Eq (Get-PcMemTypeName 26) 'DDR4' 'bellek türü: DDR4'
Assert-Eq (Get-PcMemTypeName 34) 'DDR5' 'bellek türü: DDR5'
Assert-Eq (Get-PcMemTypeName 24) 'DDR3' 'bellek türü: DDR3'
Assert-Eq (Get-PcMemTypeName 30) 'LPDDR4' 'bellek türü: LPDDR4'
Assert-Eq (Get-PcMemTypeName 0) '' 'bellek türü: bilinmeyen'
Assert-Eq (Format-PcGb 16) '16 GB' 'GB: tam sayı'
Assert-Eq (Format-PcGb 15.8) '15.8 GB' 'GB: ondalık'
Assert-Eq (Format-PcGb 7.96) '8 GB' 'GB: yuvarlanır'
Assert-Eq (Format-PcSpan 0.5) '30 dk' 'süre: dakika'
Assert-Eq (Format-PcSpan 5.4) '5 saat' 'süre: saat'
Assert-Eq (Format-PcSpan 100) '4 gün 4 saat' 'süre: gün'
Assert-Eq (Get-PcDiskKind 'SSD' 'NVMe') 'NVMe SSD' 'disk türü: NVMe'
Assert-Eq (Get-PcDiskKind 'SSD' 'SATA') 'SSD' 'disk türü: SSD'
Assert-Eq (Get-PcDiskKind 'HDD' 'SATA') 'HDD' 'disk türü: HDD'
Assert-Eq (Get-PcDiskKind 'Unspecified' 'USB') 'USB disk' 'disk türü: USB'
Assert-Eq (Get-PcDiskKind 'Unspecified' 'SD') 'Bellek kartı' 'disk türü: kart'
Assert-Eq (Get-PcDiskKind '' '') 'Disk' 'disk türü: bilinmiyor'

# =====================================================================
#  2) toplama: sahte CIM, kayıt defteri ve disk işlevleriyle
# =====================================================================
$script:Cim = @{}
$script:CimNs = New-Object System.Collections.ArrayList
function Get-CimInstance {
    [CmdletBinding()] param([string]$Namespace = 'root\cimv2', [string]$ClassName, [string]$Filter = '')
    [void]$script:CimNs.Add($Namespace + '|' + $ClassName)
    if (-not $script:Cim.ContainsKey($ClassName)) { throw ('sınıf yok: ' + $ClassName) }
    return $script:Cim[$ClassName]
}
$script:Reg = @{}
function Get-RegValue([string]$Path, [string]$Name, $Default = $null) { $k = $Path + '|' + $Name; if ($script:Reg.ContainsKey($k)) { return $script:Reg[$k] }; return $Default }
$script:PhysDisks = @()
function Get-SlvPhysDisks { return , $script:PhysDisks }
function Get-PhysicalDisk { [CmdletBinding()] param() return $script:PhysHealth }
$script:PhysHealth = @()
function Get-NetAdapter { [CmdletBinding()] param([switch]$Physical) return $script:Adapters }
$script:Adapters = @()

$script:Cim['Win32_ComputerSystem'] = @([pscustomobject]@{ Manufacturer = 'LENOVO '; Model = "82XV`t"; TotalPhysicalMemory = [double](15.8GB); PCSystemType = 2 })
$script:Cim['Win32_BIOS'] = @([pscustomobject]@{ Manufacturer = 'LENOVO'; SMBIOSBIOSVersion = 'N3CN45WW'; ReleaseDate = [datetime]'2023-06-08' })
$script:Cim['Win32_BaseBoard'] = @([pscustomobject]@{ Manufacturer = 'LENOVO'; Product = 'LNVNB161216' })
$script:Cim['Win32_OperatingSystem'] = @([pscustomobject]@{ Caption = 'Microsoft Windows 11 Home'; OSArchitecture = '64-bit'; BuildNumber = '22631'; InstallDate = [datetime]'2024-02-03'; LastBootUpTime = (Get-Date).AddHours(-100) })
$script:Cim['Win32_Processor'] = @([pscustomobject]@{ Name = '  AMD Ryzen 7 7840HS   with Radeon 780M '; NumberOfCores = 8; NumberOfLogicalProcessors = 16; MaxClockSpeed = 3800; L2CacheSize = 8192; L3CacheSize = 16384; VirtualizationFirmwareEnabled = $false })
$script:Cim['Win32_PhysicalMemory'] = @(
    [pscustomobject]@{ DeviceLocator = 'DIMM A'; BankLabel = 'BANK 0'; Capacity = [double](8GB); SMBIOSMemoryType = 26; Speed = 3200; ConfiguredClockSpeed = 2400; Manufacturer = 'Samsung'; PartNumber = 'M471A1K43DB1-CWE ' }
)
$script:Cim['Win32_PhysicalMemoryArray'] = @([pscustomobject]@{ MemoryDevices = 2; MaxCapacity = [double](33554432) })
$script:Cim['Win32_VideoController'] = @(
    [pscustomobject]@{ Name = 'AMD Radeon(TM) 780M'; DriverVersion = '31.0.21001.1'; DriverDate = [datetime]'2022-03-15'; CurrentHorizontalResolution = 2560; CurrentVerticalResolution = 1600; CurrentRefreshRate = 165 }
)
$script:Cim['Win32_Battery'] = @([pscustomobject]@{ EstimatedChargeRemaining = 63; BatteryStatus = 1 })
$script:Cim['BatteryStaticData'] = @([pscustomobject]@{ DesignedCapacity = 71000 })
$script:Cim['BatteryFullChargedCapacity'] = @([pscustomobject]@{ FullChargedCapacity = 42600 })
$script:Cim['Win32_PnPEntity'] = @([pscustomobject]@{ Name = "Bilinmeyen aygıt`r`n"; ConfigManagerErrorCode = 28 })
$script:Cim['Win32_Tpm'] = @([pscustomobject]@{ IsEnabled_InitialValue = $true; IsActivated_InitialValue = $true; SpecVersion = '2.0, 0, 1.59' })
$script:Reg['HKLM\SYSTEM\CurrentControlSet\Control|PEFirmwareType'] = 2
$script:Reg['HKLM\SYSTEM\CurrentControlSet\Control\SecureBoot\State|UEFISecureBootEnabled'] = 1
$script:Reg['HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion|DisplayVersion'] = '23H2'
$script:Reg['HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion|UBR'] = 4602
$script:PhysDisks = @(
    @{ Number = 0; Name = 'Samsung SSD 980 PRO 1TB'; Size = [double](1000204886016); Bus = 'NVMe'; Media = 'SSD'; Style = 'GPT'; IsSystem = $true; Letters = @('C:'); Parts = @() },
    @{ Number = 1; Name = 'SanDisk Ultra'; Size = [double](31914983424); Bus = 'USB'; Media = 'Unspecified'; Style = 'MBR'; IsSystem = $false; Letters = @('E:'); Parts = @() }
)
$script:PhysHealth = @([pscustomobject]@{ DeviceId = '0'; HealthStatus = 'Healthy' }, [pscustomobject]@{ DeviceId = '1'; HealthStatus = 'Warning' })
$script:Adapters = @(
    [pscustomobject]@{ InterfaceDescription = 'MediaTek Wi-Fi 6E MT7922'; PhysicalMediaType = 'Native 802.11'; LinkSpeed = '1.2 Gbps'; Status = 'Up' },
    [pscustomobject]@{ InterfaceDescription = 'Realtek PCIe GbE'; PhysicalMediaType = '802.3'; LinkSpeed = '0 bps'; Status = 'Disconnected' }
)
$env:SystemDrive = '/'

$I = Get-PcInfo
Assert-True ($I.Ok -eq $true) 'toplama: tamam'
Assert-Eq $I.Machine.Maker 'LENOVO' 'toplama: üretici temizlenir'
Assert-Eq $I.Machine.Model '82XV' 'toplama: model temizlenir'
Assert-Eq $I.Machine.Kind 'Dizüstü' 'toplama: tür (PCSystemType 2)'
Assert-Eq $I.Machine.IsVm $false 'toplama: sanal makine değil'
Assert-Eq $I.Machine.Bios 'LENOVO N3CN45WW' 'toplama: BIOS'
Assert-Eq $I.Machine.BiosDate '08.06.2023' 'toplama: BIOS tarihi'
Assert-Eq $I.Machine.Board 'LENOVO LNVNB161216' 'toplama: anakart'
Assert-Eq $I.Machine.Firmware 'UEFI' 'toplama: UEFI'
Assert-Eq $I.Machine.SecureBoot $true 'toplama: Güvenli Önyükleme'
Assert-True ($I.Machine.Tpm.Known -eq $true -and $I.Machine.Tpm.Present -eq $true -and $I.Machine.Tpm.Ready -eq $true -and $I.Machine.Tpm.Version -eq '2.0') 'toplama: TPM 2.0 hazır'
Assert-True ($script:CimNs -contains 'root\cimv2\Security\MicrosoftTpm|Win32_Tpm') 'toplama: TPM sorgusu doğru ad alanında'
Assert-True ($script:CimNs -contains 'root\wmi|BatteryStaticData' -and $script:CimNs -contains 'root\wmi|BatteryFullChargedCapacity') 'toplama: pil sorguları root\wmi altında'
Assert-Eq $I.Os.Name 'Windows 11 Home' 'toplama: Windows adı (Microsoft öneki atılır)'
Assert-Eq $I.Os.Build 22631 'toplama: derleme'
Assert-Eq $I.Os.Version '23H2' 'toplama: sürüm'
Assert-Eq $I.Os.Ubr 4602 'toplama: UBR'
Assert-Eq $I.Os.Installed '03.02.2024' 'toplama: kurulum tarihi'
Assert-True ($I.Os.UptimeHours -gt 99 -and $I.Os.UptimeHours -lt 101) 'toplama: açık kalma süresi'
Assert-Eq $I.Cpu.Name 'AMD Ryzen 7 7840HS with Radeon 780M' 'toplama: işlemci adı toparlanır'
Assert-True ($I.Cpu.Cores -eq 8 -and $I.Cpu.Threads -eq 16 -and $I.Cpu.Mhz -eq 3800 -and $I.Cpu.L2KB -eq 8192 -and $I.Cpu.L3KB -eq 16384) 'toplama: işlemci sayıları'
Assert-Eq $I.Cpu.Virt $false 'toplama: sanallaştırma kapalı'
Assert-Eq $I.Mem.TotalGB 15.8 'toplama: toplam bellek'
Assert-Eq @($I.Mem.Modules).Count 1 'toplama: bir modül'
$m0 = @($I.Mem.Modules)[0]
Assert-True ($m0.CapGB -eq 8 -and $m0.Type -eq 'DDR4' -and $m0.Rated -eq 3200 -and $m0.Running -eq 2400 -and $m0.Part -eq 'M471A1K43DB1-CWE') 'toplama: modül ayrıntısı'
Assert-Eq $I.Mem.SlotCount 2 'toplama: yuva sayısı'
Assert-Eq $I.Mem.MaxGB 32 'toplama: en çok bellek (KB -> GB)'
Assert-Eq @($I.Gpu).Count 1 'toplama: ekran kartı'
Assert-True ($I.Gpu[0].DriverDate -eq '15.03.2022' -and $I.Gpu[0].Res -eq '2560x1600 @ 165 Hz') 'toplama: sürücü tarihi ve çözünürlük'
Assert-Eq @($I.Disks).Count 2 'toplama: iki disk'
Assert-True ($I.Disks[0].Kind -eq 'NVMe SSD' -and $I.Disks[0].SizeGB -eq 932 -and $I.Disks[0].IsSystem -eq $true -and $I.Disks[0].Health -eq 'Healthy') 'toplama: sistem diski'
Assert-True ($I.Disks[1].Kind -eq 'USB disk' -and $I.Disks[1].Health -eq 'Warning' -and $I.Disks[1].Letters[0] -eq 'E:') 'toplama: USB disk ve sağlık'
Assert-True ($I.SysDrive.SizeGB -gt 0) 'toplama: sistem sürücüsü boyutu'
Assert-Eq @($I.Net).Count 2 'toplama: iki bağdaştırıcı'
Assert-True ($I.Net[0].Kind -eq 'Wi-Fi' -and $I.Net[0].Up -eq $true -and $I.Net[1].Kind -eq 'Ethernet' -and $I.Net[1].Up -eq $false) 'toplama: ağ türleri'
Assert-True ($I.Battery.Percent -eq 63 -and $I.Battery.Charging -eq $false -and $I.Battery.WearPct -eq 40) 'toplama: pil aşınması %40'
Assert-True (@($I.Problems).Count -eq 1 -and $I.Problems[0].Code -eq 28 -and $I.Problems[0].Name -eq 'Bilinmeyen aygıt') 'toplama: sorunlu aygıt'

# sanal makine ve eksik veri: bölümler boş kalır, hata fırlamaz
$script:Cim = @{}
$script:Cim['Win32_ComputerSystem'] = @([pscustomobject]@{ Manufacturer = 'QEMU'; Model = 'Standard PC (Q35 + ICH9, 2009)'; TotalPhysicalMemory = [double](4GB); PCSystemType = 1 })
$script:Reg = @{}
$script:PhysDisks = @()
$script:PhysHealth = @()
$script:Adapters = @()
$I2 = Get-PcInfo
Assert-True ($I2.Ok -eq $true -and $I2.Machine.IsVm -eq $true -and $I2.Machine.Kind -eq 'Sanal makine') 'eksik veri: sanal makine tanınır'
Assert-True (@($I2.Gpu).Count -eq 0 -and @($I2.Disks).Count -eq 0 -and @($I2.Net).Count -eq 0 -and $null -eq $I2.Battery) 'eksik veri: bölümler boş'
Assert-Eq $I2.Machine.Firmware '' 'eksik veri: yazılım türü bilinmiyor'
Assert-True ($null -eq $I2.Machine.SecureBoot -and $I2.Machine.Tpm.Known -eq $false) 'eksik veri: güvenlik donanımı bilinmiyor'
$j = Job_PcInfo @{}
Assert-True ($j.Ok -eq $true -and $null -ne $j.Info) 'iş: sonuç döner'

# =====================================================================
#  3) yorumlama
# =====================================================================
function New-Info {
    return @{ Ok = $true; At = '09.11.2026 10:00'; Admin = $true
        Machine = @{ Maker = 'ASUS'; Model = 'PRIME B550M-A'; Kind = 'Masaüstü'; IsVm = $false; Board = 'ASUSTeK PRIME B550M-A'; Bios = 'American Megatrends 3607'; BiosDate = '10.08.2023'; Firmware = 'UEFI'; SecureBoot = $true; Tpm = @{ Known = $true; Present = $true; Ready = $true; Version = '2.0' } }
        Os = @{ Name = 'Windows 11 Pro'; Version = '24H2'; Build = 26100; Ubr = 2033; Arch = '64-bit'; Installed = '01.03.2025'; Boot = '08.11.2026 09:00'; UptimeHours = [double]25 }
        Cpu = @{ Name = 'AMD Ryzen 5 5600'; Cores = 6; Threads = 12; Mhz = 4400; L2KB = 3072; L3KB = 32768; Virt = $true }
        Mem = @{ TotalGB = [double]32; SlotCount = 4; MaxGB = [double]128; Modules = @(
            @{ Slot = 'DIMM A2'; Bank = 'BANK 1'; CapGB = [double]16; Type = 'DDR4'; Rated = 3200; Running = 3200; Maker = 'Kingston'; Part = 'KF432C16BB/16' },
            @{ Slot = 'DIMM B2'; Bank = 'BANK 3'; CapGB = [double]16; Type = 'DDR4'; Rated = 3200; Running = 3200; Maker = 'Kingston'; Part = 'KF432C16BB/16' }) }
        Gpu = @(@{ Name = 'NVIDIA GeForce RTX 3060'; Driver = '32.0.15.6094'; DriverDate = (Get-Date).AddDays(-40).ToString('dd.MM.yyyy'); Res = '2560x1440 @ 144 Hz' })
        Disks = @(@{ Number = 0; Name = 'WD_BLACK SN770 1TB'; Kind = 'NVMe SSD'; Bus = 'NVMe'; SizeGB = [double]931; Style = 'GPT'; Letters = @('C:'); Health = 'Healthy'; IsSystem = $true })
        Net = @(@{ Name = 'Realtek 2.5GbE'; Kind = 'Ethernet'; Speed = '1 Gbps'; Up = $true })
        Battery = $null; Problems = @(); SysDrive = @{ Letter = 'C:'; FreeGB = [double]412; SizeGB = [double]931 } }
}
$desk = New-Info
$secN = @(Get-PcSections $desk $false)
$secE = @(Get-PcSections $desk $true)
Assert-Eq (@($secN | ForEach-Object { $_.Title }) -join '|') 'Bilgisayar ve Windows|İşlemci|Bellek|Ekran kartı|Depolama|Ağ' 'bölümler (kullanıcı kipi, pilsiz)'
Assert-Eq (@($secE | ForEach-Object { $_.Title }) -join '|') 'Bilgisayar ve Windows|İşlemci|Bellek|Ekran kartı|Depolama|Ağ' 'bölümler (uzman kipi)'
function Get-Kv($Sections, [string]$Title) { return @(@($Sections | Where-Object { $_.Title -eq $Title })[0].Rows) }
function Find-Kv($Rows, [string]$Key) { $x = @($Rows | Where-Object { $_.K -eq $Key }); if ($x.Count -eq 0) { return $null }; return [string]$x[0].V }
$pcN = Get-Kv $secN 'Bilgisayar ve Windows'
$pcE = Get-Kv $secE 'Bilgisayar ve Windows'
Assert-Eq (Find-Kv $pcN 'Bilgisayar') 'ASUS PRIME B550M-A' 'kullanıcı kipi: model'
Assert-Eq (Find-Kv $pcN 'Windows') 'Windows 11 Pro  ·  24H2  ·  derleme 26100.2033' 'kullanıcı kipi: Windows satırı'
Assert-Eq (Find-Kv $pcN 'Açık kalma süresi') '1 gün 1 saat' 'kullanıcı kipi: açık kalma süresi'
Assert-Eq (Find-Kv $pcN 'Güvenlik donanımı') 'UEFI  ·  Güvenli Önyükleme açık  ·  TPM 2.0 hazır' 'kullanıcı kipi: güvenlik donanımı'
Assert-True ($null -eq (Find-Kv $pcN 'Anakart') -and $null -eq (Find-Kv $pcN 'BIOS / UEFI sürümü')) 'kullanıcı kipi: anakart ve BIOS gizli'
Assert-Eq (Find-Kv $pcE 'Anakart') 'ASUSTeK PRIME B550M-A' 'uzman kipi: anakart'
Assert-Eq (Find-Kv $pcE 'BIOS / UEFI sürümü') 'American Megatrends 3607  ·  10.08.2023' 'uzman kipi: BIOS'
Assert-Eq (Find-Kv $pcE 'Mimari') '64-bit' 'uzman kipi: mimari'
$cpuN = Get-Kv $secN 'İşlemci'
$cpuE = Get-Kv $secE 'İşlemci'
Assert-Eq (Find-Kv $cpuN 'Çekirdek') '6 çekirdek, 12 iş parçacığı' 'kullanıcı kipi: çekirdek'
Assert-True ($null -eq (Find-Kv $cpuN 'En yüksek hız')) 'kullanıcı kipi: hız gizli'
Assert-Eq (Find-Kv $cpuE 'En yüksek hız') '4400 MHz' 'uzman kipi: hız'
Assert-Eq (Find-Kv $cpuE 'Önbellek') 'L2 3 MB  ·  L3 32 MB' 'uzman kipi: önbellek'
Assert-Eq (Find-Kv $cpuE 'Sanallaştırma') 'Açık' 'uzman kipi: sanallaştırma'
$memN = Get-Kv $secN 'Bellek'
$memE = Get-Kv $secE 'Bellek'
Assert-Eq (Find-Kv $memN 'Bellek') '32 GB  ·  DDR4  ·  3200 MHz  ·  2 modül (2 yuva boş)' 'kullanıcı kipi: bellek özeti'
Assert-Eq @($memN).Count 1 'kullanıcı kipi: modüller gizli'
Assert-Eq (Find-Kv $memE 'DIMM A2') '16 GB  ·  DDR4  ·  3200 MHz  ·  Kingston  ·  KF432C16BB/16' 'uzman kipi: modül satırı'
Assert-Eq (Find-Kv $memE 'Desteklenen en çok') '128 GB' 'uzman kipi: en çok bellek'
$gpuE = Get-Kv $secE 'Ekran kartı'
Assert-True ((Find-Kv $gpuE '   sürücü') -match '^32\.0\.15\.6094  ·  \d{2}\.\d{2}\.\d{4}$') 'uzman kipi: sürücü sürümü ve tarihi'
Assert-Eq (Find-Kv $gpuE '   ekran') '2560x1440 @ 144 Hz' 'uzman kipi: çözünürlük'
Assert-Eq @(Get-Kv $secN 'Ekran kartı').Count 1 'kullanıcı kipi: yalnızca kart adı'
$stN = Get-Kv $secN 'Depolama'
$stE = Get-Kv $secE 'Depolama'
Assert-Eq (Find-Kv $stN 'Disk 0 (Windows)') 'WD_BLACK SN770 1TB  ·  NVMe SSD  ·  931 GB' 'kullanıcı kipi: disk satırı'
Assert-Eq (Find-Kv $stE 'Disk 0 (Windows)') 'WD_BLACK SN770 1TB  ·  NVMe SSD  ·  931 GB  ·  GPT  ·  NVMe  ·  C:' 'uzman kipi: disk ayrıntısı'
Assert-Eq (Find-Kv $stN 'C: boş alan') '412 GB / 931 GB' 'boş alan satırı'
Assert-Eq (Find-Kv (Get-Kv $secN 'Ağ') 'Ethernet') 'Realtek 2.5GbE  ·  bağlı, 1 Gbps' 'ağ satırı'

# pil ve sorunlu aygıtlar
$lap = New-Info
$lap.Machine.Kind = 'Dizüstü'
$lap.Battery = @{ Percent = 63; Charging = $false; DesignMWh = 71000; FullMWh = 42600; WearPct = 40 }
$lap.Problems = @(@{ Name = 'Bilinmeyen aygıt'; Code = 28 }, @{ Name = 'PCI Aygıtı'; Code = 10 })
$secL = @(Get-PcSections $lap $true)
Assert-True (@($secL | Where-Object { $_.Title -eq 'Pil' }).Count -eq 1 -and @($secL | Where-Object { $_.Title -eq 'Sorunlu aygıtlar' }).Count -eq 1) 'pil ve sorunlu aygıt bölümleri (uzman)'
Assert-Eq (Find-Kv (Get-Kv $secL 'Pil') 'Pil sağlığı') '%40 aşınma  ·  tasarım 71000 mWh, şimdi 42600 mWh' 'uzman kipi: pil kapasiteleri'
Assert-Eq (Find-Kv (Get-Kv $secL 'Pil') 'Şarj') '%63  ·  pille çalışıyor' 'pil şarjı'
Assert-Eq (Find-Kv (Get-Kv $secL 'Sorunlu aygıtlar') 'Kod 28') 'Bilinmeyen aygıt' 'sorunlu aygıt satırı'
$secLN = @(Get-PcSections $lap $false)
Assert-Eq (Find-Kv (Get-Kv $secLN 'Pil') 'Pil sağlığı') '%40 aşınma' 'kullanıcı kipi: pil sade'
Assert-True (@($secLN | Where-Object { $_.Title -eq 'Sorunlu aygıtlar' }).Count -eq 0) 'kullanıcı kipi: sorunlu aygıt bölümü gizli (gözlemlerde sayılır)'

# TPM bilinmiyor ve yok
$unk = New-Info
$unk.Machine.Tpm = @{ Known = $false; Present = $false; Ready = $false; Version = '' }
$unk.Machine.SecureBoot = $null
$unk.Machine.Firmware = ''
Assert-Eq (Get-PcSecuritySummary $unk) 'TPM durumu okunamadı (yönetici gerekir)' 'güvenlik özeti: bilinmiyor'
$unk.Machine.Tpm = @{ Known = $true; Present = $false; Ready = $false; Version = '' }
$unk.Machine.SecureBoot = $false
$unk.Machine.Firmware = 'Eski BIOS'
Assert-Eq (Get-PcSecuritySummary $unk) 'Eski BIOS  ·  Güvenli Önyükleme kapalı  ·  TPM yok' 'güvenlik özeti: eski BIOS, TPM yok'

# ---- gözlemler ----
function Note-Titles($Notes) { return (@($Notes | ForEach-Object { [string]$_.Title }) -join '|') }
$nd = @(Get-PcNotes $desk $true)
Assert-Eq @($nd).Count 1 'sağlıklı masaüstü: tek gözlem'
Assert-True ($nd[0].Level -eq 'good' -and $nd[0].Title -eq 'Dikkat çeken bir şey yok') 'sağlıklı masaüstü: iyi haber'

$bad = New-Info
$bad.Os.Name = 'Windows 10 Home'; $bad.Os.Build = 19045; $bad.Os.UptimeHours = [double]400
$bad.Mem.TotalGB = [double]3.8; $bad.Mem.SlotCount = 2
$bad.Mem.Modules = @(@{ Slot = 'DIMM A'; Bank = ''; CapGB = [double]4; Type = 'DDR3'; Rated = 1600; Running = 1000; Maker = ''; Part = '' })
$bad.Machine.Tpm = @{ Known = $true; Present = $false; Ready = $false; Version = '' }
$bad.Machine.Firmware = 'Eski BIOS'; $bad.Machine.SecureBoot = $null
$bad.Cpu.Virt = $false
$bad.Disks = @(@{ Number = 0; Name = 'ST500LM030'; Kind = 'HDD'; Bus = 'SATA'; SizeGB = [double]465; Style = 'MBR'; Letters = @('C:'); Health = 'Warning'; IsSystem = $true })
$bad.SysDrive = @{ Letter = 'C:'; FreeGB = [double]9; SizeGB = [double]465 }
$bad.Gpu = @(@{ Name = 'Microsoft Basic Display Adapter'; Driver = '10.0.19041.1'; DriverDate = '21.06.2006'; Res = '' })
$bad.Battery = @{ Percent = 40; Charging = $true; DesignMWh = 40000; FullMWh = 18000; WearPct = 55 }
$bad.Problems = @(@{ Name = 'A'; Code = 10 }, @{ Name = 'B'; Code = 28 }, @{ Name = 'C'; Code = 43 }, @{ Name = 'D'; Code = 31 })
$nb = @(Get-PcNotes $bad $true)
$tb = Note-Titles $nb
foreach ($want in @('Windows 10 kullanıyorsunuz', 'Windows 11 için TPM 2.0 gerekir', 'Bellek çok az', 'Bellek üretici hızının altında çalışıyor', 'Sanallaştırma kapalı', 'Windows bir HDD üzerinde',
        'Disk 0 sağlık uyarısı veriyor', 'C: sürücüsünde boş alan az', 'Uzun süredir yeniden başlatılmadı', 'Windows eski BIOS kipinde kurulu', 'Ekran kartı sürücüsü kurulu değil', 'Pil yıpranmış', '4 aygıtta sorun var')) {
    Assert-True ($tb -match [regex]::Escape($want)) ('gözlem var: ' + $want)
}
Assert-True ($tb -notmatch 'Dikkat çeken') 'sorunluyken iyi haber yok'
Assert-True ($tb -match 'tek kanalda') 'tek modül ve boş yuva: tek kanal gözlemi de var'
$wlev = @($nb | Where-Object { $_.Title -eq 'Pil yıpranmış' })[0].Level
Assert-Eq $wlev 'warn' 'pil %55 aşınma: uyarı'
$bad.Battery.WearPct = 32
Assert-Eq (@(Get-PcNotes $bad $true | Where-Object { $_.Title -eq 'Pil yıpranmış' })[0].Level) 'info' 'pil %32 aşınma: bilgi'
$bad.Battery.WearPct = 10
Assert-True ((Note-Titles @(Get-PcNotes $bad $true)) -notmatch 'Pil yıpranmış') 'pil %10 aşınma: gözlem yok'

# kullanıcı kipinde uzmana özel gözlemler gelmez
$nbn = Note-Titles @(Get-PcNotes $bad $false)
Assert-True ($nbn -notmatch 'Sanallaştırma kapalı' -and $nbn -notmatch 'hızının altında') 'kullanıcı kipi: uzman gözlemleri yok'
Assert-True ($nbn -match 'Windows bir HDD' -and $nbn -match 'Bellek çok az') 'kullanıcı kipi: genel gözlemler var'

# tek kanal, sanal makinede söylenmez
$one = New-Info
$one.Mem.Modules = @(@{ Slot = 'DIMM A2'; Bank = ''; CapGB = [double]16; Type = 'DDR4'; Rated = 3200; Running = 3200; Maker = ''; Part = '' })
$one.Mem.SlotCount = 2
$one.Mem.TotalGB = [double]16
Assert-True ((Note-Titles @(Get-PcNotes $one $false)) -match 'tek kanalda') 'tek modül + boş yuva: tek kanal gözlemi'
$one.Machine.IsVm = $true
Assert-True ((Note-Titles @(Get-PcNotes $one $false)) -notmatch 'tek kanalda') 'sanal makinede tek kanal söylenmez'
# eski sürücü tarihi
$old = New-Info
$old.Gpu[0].DriverDate = '01.02.2021'
Assert-True ((Note-Titles @(Get-PcNotes $old $false)) -match 'Ekran kartı sürücüsü eski') 'iki yıldan eski ekran kartı sürücüsü'
$old.Gpu[0].Name = 'Parsec Virtual Display Adapter'
Assert-True ((Note-Titles @(Get-PcNotes $old $false)) -notmatch 'Ekran kartı sürücüsü eski') 'sanal ekran bağdaştırıcısı için sürücü uyarısı yok'
# Güvenli Önyükleme kapalı
$sbk = New-Info
$sbk.Machine.SecureBoot = $false
Assert-True ((Note-Titles @(Get-PcNotes $sbk $false)) -match 'Güvenli Önyükleme kapalı') 'Güvenli Önyükleme kapalı gözlemi'

# kopyalanan özet
$txt = Get-PcSummaryText $desk $false
Assert-True ($txt -match '^Multimizer - Bilgisayar özeti' -and $txt -match 'Bilgisayar ve Windows' -and $txt -match '  Bilgisayar: ASUS PRIME B550M-A' -and $txt -match 'Gözlemler' -and $txt -match '- Dikkat çeken bir şey yok') 'özet metni'
Assert-True ($txt -notmatch 'Anakart') 'özet metni (kullanıcı kipi) ayrıntı içermez'
Assert-True ((Get-PcSummaryText $desk $true) -match 'Anakart: ASUSTeK') 'özet metni (uzman kipi) ayrıntı içerir'

# =====================================================================
#  4) çizim ve akış
# =====================================================================
$ui = @{}
foreach ($n in @('sl_List', 'sl_Foot', 'sl_PcRefresh', 'sl_PcCopy')) { $ui[$n] = New-FakeCtl }
$script:UiState = @{ Page = 'solve'; Mode = 'Normal' }
$script:SlTab = 'pc'
$script:PcInfo = $null
$script:PcLoading = $false
$script:ClipText = $null
$script:ClipOk = $true
function Set-ClipText([string]$Text) { $script:ClipText = $Text; return $script:ClipOk }

Reset-Fake
Render-SlPc
Assert-True ($null -ne (Find-NoteLike $ui.sl_List 'okunuyor')) 'okunmadan önce bilgi notu'
Assert-Eq $script:Asyncs.Count 1 'okuma işi başladı'
Assert-Eq $script:Asyncs[0].Entry 'Job_PcInfo' 'iş adı'
Assert-True ($script:PcLoading -eq $true) 'yükleniyor işareti'
Render-SlPc
Assert-Eq $script:Asyncs.Count 1 'okuma sürerken ikinci iş başlamaz'
& $script:Asyncs[0].OnDone @{ Ok = $true; Info = $desk }
Assert-True ($script:PcLoading -eq $false) 'yükleniyor işareti kalktı'
Assert-True ($null -ne (Find-NoteLike $ui.sl_List 'Bilgisayarınızın ne olduğunu')) 'kullanıcı kipi açıklaması'
Assert-True ($null -ne (Find-NoteLike $ui.sl_List 'ASUS PRIME B550M-A')) 'model satırı çizildi'
Assert-True ($null -eq (Find-NoteLike $ui.sl_List 'Anakart')) 'kullanıcı kipinde anakart yok'
$heads = @($ui.sl_List.Children | Where-Object { $_.Head -eq $true } | ForEach-Object { $_.Text })
Assert-Eq ($heads -join '|') 'Bilgisayar ve Windows|İşlemci|Bellek|Ekran kartı|Depolama|Ağ|Gözlemler' 'başlıklar'
$rows = @(Get-RowsOf $ui.sl_List)
Assert-Eq $rows.Count 1 'gözlem satırı sayısı'
Assert-True ($rows[0].Vars.Title -eq 'Dikkat çeken bir şey yok' -and $rows[0].Vars.BrCol -eq 'BrGood') 'iyi haber satırı yeşil'
Assert-True ($ui.sl_Foot.Text -match '^Okundu: 09\.11\.2026 10:00$') 'alt metin: yönetici ise ek not yok'

# uzman kipine geçince açık sekme yeniden çizilir
$script:UiState.Mode = 'Expert'
Update-PageMode_solve
Assert-True ($null -ne (Find-NoteLike $ui.sl_List 'Anakart')) 'uzman kipinde anakart çizilir'
Assert-True ($null -ne (Find-NoteLike $ui.sl_List 'Uzman kipi: ham değerler')) 'uzman kipi açıklaması'
$script:SlTab = 'scan'
$ui.sl_List.Children.Clear()
Update-PageMode_solve
Assert-Eq $ui.sl_List.Children.Count 0 'başka sekmedeyken kip değişimi çizmez'
$script:SlTab = 'pc'
$script:UiState.Mode = 'Normal'

# yönetici değilken alt metin uyarır; sorunlu bilgisayarda gözlemler renklenir
$bad2 = New-Info
$bad2.Admin = $false
$bad2.Disks = @(@{ Number = 0; Name = 'ST500'; Kind = 'HDD'; Bus = 'SATA'; SizeGB = [double]465; Style = 'MBR'; Letters = @('C:'); Health = 'Healthy'; IsSystem = $true })
$script:PcInfo = $bad2
Render-SlPc
Assert-True ($ui.sl_Foot.Text -match 'yönetici olmadan') 'alt metin: yönetici değil'
$r2 = @(Get-RowsOf $ui.sl_List)
Assert-True ($r2.Count -ge 1 -and $r2[0].Vars.BrCol -eq 'BrWarn') 'uyarı gözlemi sarı'

# yenile düğmesi
Init-SlPc
Assert-Eq $ui.sl_PcRefresh.Handlers.Count 1 'yenile düğmesi bağlandı'
Assert-Eq $ui.sl_PcCopy.Handlers.Count 1 'kopyala düğmesi bağlandı'
Reset-Fake
$script:PcLoading = $false
& $ui.sl_PcRefresh.Handlers[0] $null $null
Assert-True ($null -eq $script:PcInfo -or $script:Asyncs.Count -eq 1) 'yenile bilgiyi sıfırlar ve yeniden okur'
Assert-Eq $script:Asyncs.Count 1 'yenile: yeni okuma işi'

# okuma başarısız
Reset-Fake
$script:PcInfo = $null
$script:PcLoading = $false
Render-SlPc
Assert-Eq $script:Asyncs.Count 1 'başarısızlık denemesi: okuma işi başladı'
& $script:Asyncs[0].OnDone @{ Ok = $false; Error = 'x' }
Assert-True ($script:PcInfo.Failed -eq $true) 'başarısız okuma kaydedildi'
Assert-True ($null -ne (Find-NoteLike $ui.sl_List 'okunamadı')) 'başarısız okuma uyarısı'
& $script:Asyncs[0].OnDone $null
Assert-True ($script:PcInfo.Failed -eq $true) 'boş sonuç da başarısız sayılır'

# kopyalama
Reset-Fake
$script:PcInfo = $desk
& $ui.sl_PcCopy.Handlers[0] $null $null
Assert-True ($script:ClipText -match 'Bilgisayar özeti' -and $script:ClipText -match 'Gözlemler') 'özet panoya yazıldı'
Assert-True ((Get-LastToast).K -eq 'good') 'kopyalama bildirimi'
$script:ClipOk = $false
Reset-Fake
Copy-SlPc
Assert-True ((Get-LastToast).K -eq 'warn') 'pano yazılamazsa uyarı'
$script:ClipOk = $true
$script:PcInfo = $null
Reset-Fake
Copy-SlPc
Assert-True ((Get-LastToast).T -match 'bekleyin') 'bilgi yokken kopyalanmaz'
$script:PcInfo = @{ Failed = $true }
Reset-Fake
Copy-SlPc
Assert-True ((Get-LastToast).K -eq 'warn') 'başarısız bilgiyle kopyalanmaz'

# =====================================================================
#  5) gözlem düğmeleri: eşleme, yönlendirme, onaylı işler
# =====================================================================
function Note-Of($Notes, [string]$Title) { return @($Notes | Where-Object { $_.Title -eq $Title })[0] }
function Act-Is($A, [string]$Do, [string]$Prop = '', [string]$Val = '') {
    if ($null -eq $A -or [string]$A.Do -ne $Do) { return $false }
    if ($Prop -eq '') { return $true }
    return ([string]$A[$Prop] -eq $Val)
}
Import-Var 'H_PcAct'
$bad.Battery.WearPct = 55
$nb = @(Get-PcNotes $bad $true)
Assert-True (Act-Is (Note-Of $nb 'Windows 10 kullanıyorsunuz').A1 'Url' 'Url' 'ms-settings:windowsupdate') 'düğme: Windows 10 -> Windows Update ayarı'
Assert-True (Act-Is (Note-Of $nb 'Windows 11 için TPM 2.0 gerekir').A1 'Uefi') 'düğme: TPM -> UEFI ayarı'
Assert-True (Act-Is (Note-Of $nb 'Bellek çok az').A1 'Page' 'Page' 'startup') 'düğme: bellek az -> Başlangıç programları'
Assert-True (Act-Is (Note-Of $nb 'Bellek üretici hızının altında çalışıyor').A1 'Uefi') 'düğme: XMP -> UEFI ayarı'
Assert-True (Act-Is (Note-Of $nb 'Sanallaştırma kapalı').A1 'Uefi') 'düğme: sanallaştırma -> UEFI ayarı'
Assert-True (Act-Is (Note-Of $nb 'Windows bir HDD üzerinde').A1 'Page' 'Page' 'backup') 'düğme: HDD -> Yedek'
$nDisk = Note-Of $nb 'Disk 0 sağlık uyarısı veriyor'
Assert-True ((Act-Is $nDisk.A1 'Page' 'Page' 'backup') -and (Act-Is $nDisk.A2 'SlTab' 'Tab' 'disk')) 'düğme: disk sağlığı -> Yedek ve Diskler sekmesi'
Assert-True (Act-Is (Note-Of $nb 'C: sürücüsünde boş alan az').A1 'Page' 'Page' 'clean') 'düğme: boş alan az -> Temizlik'
Assert-True (Act-Is (Note-Of $nb 'Uzun süredir yeniden başlatılmadı').A1 'Reboot') 'düğme: uzun açık kalma -> yeniden başlat'
$nBios = Note-Of $nb 'Windows eski BIOS kipinde kurulu'
Assert-True ((Act-Is $nBios.A1 'Job' 'Key' 'PcMbr2gpt') -and (Act-Is $nBios.A2 'Page' 'Page' 'backup')) 'düğme: eski BIOS -> MBR2GPT denetimi ve Yedek'
Assert-True ([string]$nBios.A1.Confirm -eq '') 'düğme: MBR2GPT denetimi salt okunur, onay istemez'
$nGpu = Note-Of $nb 'Ekran kartı sürücüsü kurulu değil'
Assert-True ((Act-Is $nGpu.A1 'Page' 'Page' 'wu') -and (Act-Is $nGpu.A2 'Tool' 'Path' 'devmgmt.msc')) 'düğme: sürücü yok -> Windows Update ve Aygıt Yöneticisi'
$nBat = Note-Of $nb 'Pil yıpranmış'
Assert-True ((Act-Is $nBat.A1 'Job' 'Key' 'BatteryReport') -and $null -eq $nBat.A2) 'düğme: pil -> rapor'
$nDev = Note-Of $nb '4 aygıtta sorun var'
Assert-True ((Act-Is $nDev.A1 'Job' 'Key' 'PcRescan') -and (Act-Is $nDev.A2 'Tool' 'Path' 'devmgmt.msc')) 'düğme: sorunlu aygıt -> yeniden tara ve Aygıt Yöneticisi'
Assert-True ([string]$nDev.A1.Confirm -match 'pnputil' -and [string]$nDev.A1.Done -ne '' -and [string]$nDev.A1.Fail -ne '' -and [string]$nDev.A1.Busy -ne '') 'düğme: aygıt tarama onay, bitiş ve hata metinleri'
$one.Machine.IsVm = $false
$nOne = Note-Of @(Get-PcNotes $one $false) 'Bellek tek kanalda çalışıyor'
Assert-True ($null -ne $nOne -and $null -eq $nOne.A1 -and $null -eq $nOne.A2) 'düğme: tek kanal donanım işidir, düğme yok'
Assert-True ($null -eq $nd[0].A1 -and $null -eq $nd[0].A2) 'düğme: iyi haberde düğme yok'
foreach ($tn in @($nb)) {
    foreach ($an in @('A1', 'A2')) {
        $a = $tn[$an]
        if ($null -ne $a) { Assert-True (([string]$a.Label).Length -ge 3 -and @('Page', 'Url', 'Tool', 'SlTab', 'Reboot', 'Uefi', 'Job') -contains [string]$a.Do) ('düğme geçerli: ' + $tn.Title + ' / ' + $an) }
    }
}
# Güvenli Önyükleme gözlemi UEFI ayarına götürür
Assert-True (Act-Is (Note-Of @(Get-PcNotes $sbk $false) 'Güvenli Önyükleme kapalı').A1 'Uefi') 'düğme: Güvenli Önyükleme -> UEFI ayarı'

# ---- yönlendirme ----
$script:PgCalls = New-Object System.Collections.ArrayList
$script:TabSel = $false
$script:TabSet = New-Object System.Collections.ArrayList
$script:RebootAsked = 0
function Open-Page([string]$Key, [string]$Sub = '') { [void]$script:PgCalls.Add($Key + '|' + $Sub) }
function Select-TabChip([string]$P, [string]$Key) { return $script:TabSel }
function Set-SlTab([string]$Tab) { [void]$script:TabSet.Add($Tab) }
function Request-Reboot { $script:RebootAsked++ }
Reset-Fake
Invoke-PcAction $null
Invoke-PcAction @{ Do = 'Page'; Page = 'clean'; Sub = '' }
Invoke-PcAction @{ Do = 'Url'; Url = 'ms-settings:windowsupdate' }
Invoke-PcAction @{ Do = 'Tool'; Path = 'devmgmt.msc' }
Assert-Eq ($script:PgCalls -join ',') 'clean|' 'yönlendirme: sayfa açılır'
Assert-Eq ($script:Opened -join ',') 'url:ms-settings:windowsupdate,path:devmgmt.msc' 'yönlendirme: ayar bağlantısı ve araç açılır'
$script:TabSel = $true
Invoke-PcAction @{ Do = 'SlTab'; Tab = 'disk' }
Assert-Eq $script:TabSet.Count 0 'yönlendirme: sekme değişince çizimi seçim olayı yapar'
$script:TabSel = $false
Invoke-PcAction @{ Do = 'SlTab'; Tab = 'disk' }
Assert-Eq ($script:TabSet -join ',') 'disk' 'yönlendirme: sekme zaten seçiliyse yeniden çizilir'
Invoke-PcAction @{ Do = 'Reboot' }
Assert-Eq $script:RebootAsked 1 'yönlendirme: yeniden başlatma isteği'
Invoke-PcAction @{ Do = 'Bilinmeyen' }
Assert-Eq $script:Confirms.Count 0 'yönlendirme: bilinmeyen eylem sessizce yok sayılır'

# ---- onaylı iş ----
Reset-Fake
Invoke-PcAction $nDev.A1
Assert-Eq $script:Confirms.Count 1 'iş: onay penceresi açıldı'
Assert-Eq $script:Asyncs.Count 0 'iş: onaydan önce başlamaz'
Assert-True ($script:Confirms[0].Title -eq 'Aygıtları yeniden tara' -and $script:Confirms[0].Ok -eq 'Çalıştır' -and $script:Confirms[0].Text -match 'hiçbir ayar değişmez') 'iş: onay metni ne olacağını söyler'
& $script:Confirms[0].OnOk
Assert-Eq $script:Asyncs.Count 1 'iş: onaydan sonra başladı'
Assert-True ($script:Asyncs[0].Entry -eq 'Job_Action' -and $script:Asyncs[0].Params.Key -eq 'PcRescan' -and $script:Asyncs[0].Label -eq 'Aygıtlar taranıyor') 'iş: Job_Action / PcRescan'
& $script:Asyncs[0].OnDone @{ Ok = $true }
Assert-True ((Get-LastToast).K -eq 'good' -and (Get-LastToast).T -match 'yeniden tarandı') 'iş: başarı bildirimi'
& $script:Asyncs[0].OnDone @{ Ok = $false }
Assert-True ((Get-LastToast).K -eq 'bad' -and (Get-LastToast).T -match 'yönetici') 'iş: hata bildirimi'
& $script:Asyncs[0].OnDone $null
Assert-True ((Get-LastToast).K -eq 'bad') 'iş: boş sonuç hata sayılır'
# onaysız (salt okunur / rapor) işler doğrudan başlar
Reset-Fake
Invoke-PcAction $nBat.A1
Assert-Eq $script:Confirms.Count 0 'iş: pil raporu onay istemez'
Assert-True ($script:Asyncs.Count -eq 1 -and $script:Asyncs[0].Params.Key -eq 'BatteryReport') 'iş: pil raporu başladı'
Reset-Fake
Invoke-PcAction $nBios.A1
Assert-True ($script:Confirms.Count -eq 0 -and $script:Asyncs.Count -eq 1 -and $script:Asyncs[0].Params.Key -eq 'PcMbr2gpt') 'iş: MBR2GPT denetimi doğrudan başladı'
& $script:Asyncs[0].OnDone @{ Ok = $true }
Assert-True ((Get-LastToast).K -eq 'good' -and (Get-LastToast).T -match 'tam yedek') 'iş: MBR2GPT başarı metni yedek hatırlatır'

# ---- UEFI ayarına yeniden başlatma ----
$script:ProcCalls = New-Object System.Collections.ArrayList
function Start-SystemRestart([bool]$Firmware = $false, [int]$Seconds = 30) { [void]$script:ProcCalls.Add('yeniden-baslat fw=' + [string]$Firmware + ' sn=' + [string]$Seconds); return $true }
$script:PcInfo = $desk
Reset-Fake
Start-PcUefi
Assert-Eq $script:Confirms.Count 1 'UEFI: UEFI kipinde onay istenir'
Assert-True ($script:Confirms[0].Text -match '30 saniye' -and $script:Confirms[0].Text -match 'iptal' -and $script:Confirms[0].Danger -eq $true) 'UEFI: onay süreyi ve iptali söyler'
Assert-Eq $script:ProcCalls.Count 0 'UEFI: onaydan önce komut çalışmaz'
& $script:Confirms[0].OnOk
Assert-Eq ($script:ProcCalls -join ';') 'yeniden-baslat fw=True sn=30' 'UEFI: yalnızca doğrulamalı yeniden başlatma (/r /fw /t 30)'
Assert-True ((Get-LastToast).K -eq 'warn') 'UEFI: yeniden başlatma bildirimi'
$legacy = New-Info
$legacy.Machine.Firmware = 'Eski BIOS'
$script:PcInfo = $legacy
Reset-Fake
$script:ProcCalls.Clear()
Start-PcUefi
Assert-True ($script:Confirms.Count -eq 0 -and $script:ProcCalls.Count -eq 0) 'UEFI: eski BIOS kipinde yeniden başlatılmaz'
Assert-True ((Get-LastToast).T -match 'Del' -and (Get-LastToast).T -match 'F2') 'UEFI: eski BIOS için tuş bilgisi verilir'
function Start-SystemRestart([bool]$Firmware = $false, [int]$Seconds = 30) { throw 'shutdown.exe çıkış kodu 1' }
$script:PcInfo = $desk
Reset-Fake
Start-PcUefi
& $script:Confirms[0].OnOk
Assert-True ((Get-LastToast).K -eq 'bad') 'UEFI: komut başarısızsa hata bildirimi'

# ---- iş işlevleri (sahte pnputil / mbr2gpt) ----
$script:Native = New-Object System.Collections.ArrayList
$script:NativeRc = 0
function pnputil.exe { [void]$script:Native.Add('pnputil ' + ($args -join ' ')); $global:LASTEXITCODE = $script:NativeRc; return 'Aygit taramasi baslatildi.' }
function mbr2gpt.exe { [void]$script:Native.Add('mbr2gpt ' + ($args -join ' ')); $global:LASTEXITCODE = $script:NativeRc; return 'MBR2GPT: Dogrulama tamam' }
Invoke-PcRescanAction @{}
Assert-Eq $script:Native[0] 'pnputil /scan-devices' 'aygıt tarama: yalnızca /scan-devices'
$script:NativeRc = 5
$e1 = ''; try { Invoke-PcRescanAction @{} } catch { $e1 = $_.Exception.Message }
Assert-True ($e1 -match 'çıkış kodu 5') 'aygıt tarama: hata kodu fırlatılır'
$script:NativeRc = 0
$script:Native.Clear()
Invoke-PcMbr2gptAction @{}
Assert-Eq $script:Native[0] 'mbr2gpt /validate /allowFullOS' 'MBR2GPT: yalnızca /validate (diske yazmaz)'
Assert-True (-not ($script:Native -join ' ' -match '/convert')) 'MBR2GPT: /convert hiç çağrılmaz'
$script:NativeRc = 2
$e2 = ''; try { Invoke-PcMbr2gptAction @{} } catch { $e2 = $_.Exception.Message }
Assert-True ($e2 -match 'çıkış kodu 2') 'MBR2GPT: uygun değilse hata'

# Job_Action kayıtlı eylemleri bulur
$script:ExtraActions = @{}
Import-Var "ExtraActions['PcRescan']", "ExtraActions['PcMbr2gpt']"
Assert-Eq $script:ExtraActions['PcRescan'] 'Invoke-PcRescanAction' 'kayıt: PcRescan'
Assert-Eq $script:ExtraActions['PcMbr2gpt'] 'Invoke-PcMbr2gptAction' 'kayıt: PcMbr2gpt'
$script:NativeRc = 0
$script:Native.Clear()
$jr = Job_Action @{ Key = 'PcRescan' }
Assert-True ($jr.Ok -eq $true -and $script:Native[0] -eq 'pnputil /scan-devices') 'Job_Action: PcRescan çalışır'
$script:NativeRc = 3
$jr2 = Job_Action @{ Key = 'PcMbr2gpt' }
Assert-True ($jr2.Ok -eq $false) 'Job_Action: hata Ok=false döner'

# ---- çizimde düğmeler ----
$script:PcInfo = $bad
$script:UiState.Mode = 'Expert'
Reset-Fake
Render-SlPc
$rowsB = @(Get-RowsOf $ui.sl_List)
Assert-True ($rowsB.Count -ge 10) 'çizim: sorunlu bilgisayarda çok sayıda gözlem satırı'
$rwDisk = @($rowsB | Where-Object { $_.Vars.Title -eq 'Disk 0 sağlık uyarısı veriyor' })[0]
Assert-True ($rwDisk.Vars.Btn1 -eq 'Yedekle' -and $rwDisk.Vars.Btn2 -eq 'Diskleri incele') 'çizim: iki düğmeli satır'
Assert-True ($rwDisk.Named.Act.Handlers.Count -eq 1 -and $rwDisk.Named.Act2.Handlers.Count -eq 1) 'çizim: düğmelere tıklama işleyicisi bağlandı'
Assert-True ($rwDisk.Named.Act.Tag.Page -eq 'backup' -and $rwDisk.Named.Act2.Tag.Tab -eq 'disk') 'çizim: her düğme kendi eylemini taşır'
$script:PgCalls.Clear()
& $rwDisk.Named.Act.Handlers[0] $rwDisk.Named.Act $null
Assert-Eq ($script:PgCalls -join ',') 'backup|' 'çizim: birinci düğme sayfayı açar'
$script:TabSet.Clear(); $script:TabSel = $false
& $rwDisk.Named.Act2.Handlers[0] $rwDisk.Named.Act2 $null
Assert-Eq ($script:TabSet -join ',') 'disk' 'çizim: ikinci düğme Diskler sekmesine geçer'
$rwOk = @($rowsB | Where-Object { $_.Vars.Title -eq 'Bellek tek kanalda çalışıyor' })[0]
Assert-True ($rwOk.Vars.Btn1 -eq '' -and $rwOk.Vars.Btn2 -eq '' -and $rwOk.Named.Act.Handlers.Count -eq 0) 'çizim: düğmesiz gözlemde işleyici yok'
$script:UiState.Mode = 'Normal'
$script:PcInfo = $null

Show-Result
