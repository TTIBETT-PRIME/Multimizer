. "$PSScriptRoot/lib.ps1"
# 7.2.1: canlı izleme (Job_Monitor) ve yardımcıları: devre kesici, ağ hızı, GPU yüzdesi, işlem listesi, canlılık denetimi.
# Amaç: 19 Ekim'deki ani kapanmanın en güçlü şüphelisi olan Get-Counter / PerformanceCounter kullanımını geri getirecek bir değişiklik olursa testin kırılması.

Import-Fn 'New-MonBreaker', 'Test-MonBreakerSkip', 'Set-MonBreakerResult', 'Invoke-MonStep', 'Get-NetByteTotals', 'Get-NetRate',
    'Get-GpuLoadFromRows', 'Get-MonGpuLoad', 'Get-MonMemory', 'New-MonCounter', 'New-MonCpuCounter', 'Read-MonCounter', 'Get-MonTop', 'Job_Monitor',
    'Test-MonitorAlive'
Import-Var 'MonCi'

# ======================= 1) devre kesici =======================
$b = New-MonBreaker 3 4
Assert-True (-not (Test-MonBreakerSkip $b)) 'yeni kesici atlamaz'
Set-MonBreakerResult $b $false; Set-MonBreakerResult $b $false
Assert-True (-not (Test-MonBreakerSkip $b)) 'iki hata: hâlâ denenir'
Set-MonBreakerResult $b $false
Assert-Eq $b.Skip 4 'üçüncü hata kesiciyi açar (4 deneme atlanır)'
Assert-Eq $b.Trips 1 'kesme sayısı'
for ($i = 0; $i -lt 4; $i++) { Assert-True (Test-MonBreakerSkip $b) ('atlanan deneme ' + ($i + 1)) }
Assert-True (-not (Test-MonBreakerSkip $b)) 'bekleme bitince yeniden denenir'
Set-MonBreakerResult $b $true
Assert-Eq $b.Fail 0 'başarı hata sayacını sıfırlar'
Assert-True ($b.Ever -eq $true) 'başarı kaydedilir'
# hiç başarmamış ölçüm 3 kesmeden sonra bırakılır; bir kez başarmış olan bırakılmaz
$d = New-MonBreaker 1 0
for ($i = 0; $i -lt 3; $i++) { Set-MonBreakerResult $d $false }
Assert-True ($d.Dead -eq $true) 'hiç başarmamış ölçüm bırakılır'
Assert-True (Test-MonBreakerSkip $d) 'bırakılan ölçüm bir daha denenmez'
$e = New-MonBreaker 1 0
Set-MonBreakerResult $e $true
for ($i = 0; $i -lt 6; $i++) { Set-MonBreakerResult $e $false }
Assert-True ($e.Dead -ne $true) 'bir kez çalışmış ölçüm bırakılmaz'

# ======================= 2) Invoke-MonStep =======================
$b = New-MonBreaker 2 2
$r = Invoke-MonStep $b { 42 }
Assert-True ($r.Ok -and $r.V -eq 42) 'başarılı ölçüm'
$r = Invoke-MonStep $b { 0.0 }
Assert-True ($r.Ok -and $r.V -eq 0) 'sıfır geçerli bir ölçümdür'
$r = Invoke-MonStep $b { throw 'bozuk' }
Assert-True ($null -ne $r -and -not $r.Ok) 'hata başarısız sayılır, fırlatılmaz'
$r = Invoke-MonStep $b { $null }
Assert-True ($null -ne $r -and -not $r.Ok) '$null başarısız sayılır'
Assert-Eq $b.Skip 2 'iki hata kesiciyi açar'
Assert-True ($null -eq (Invoke-MonStep $b { 1 })) 'kesici açıkken ölçüm yapılmaz ($null döner)'
$b2 = New-MonBreaker 3 3
$r = Invoke-MonStep $b2 { , @() }
Assert-True ($r.Ok -and $r.V -is [array] -and $r.V.Count -eq 0) 'boş dizi geçerli bir sonuçtur (oyun yok)'
$r = Invoke-MonStep $b2 { , @(@{ Name = 'a' }, @{ Name = 'b' }) }
Assert-Eq $r.V.Count 2 'dizi sonucu korunur'

# ======================= 3) ağ hızı =======================
$p0 = @{ a = @(1000.0, 500.0); b = @(2000.0, 100.0) }
$c0 = @{ a = @(3000.0, 1500.0); b = @(2500.0, 100.0) }
$rt = Get-NetRate $p0 $c0 2.0
Assert-Eq $rt.Down 1250 'iki arayüzün indirme toplamı / süre'
Assert-Eq $rt.Up 500 'gönderme'
$rt = Get-NetRate @{ a = @(4294967000.0, 0.0) } @{ a = @(500.0, 0.0) } 1.0
Assert-Eq $rt.Down 796 '32 bit sayaç başa sarınca fark doğru hesaplanır'
$rt = Get-NetRate @{ a = @(1000.0, 1000.0) } @{ a = @(1000.0, 1000.0); yeni = @(99999999.0, 99999999.0) } 1.0
Assert-Eq $rt.Down 0 'yeni görünen arayüz sıçrama yapmaz'
$rt = Get-NetRate @{ a = @(1000.0, 1000.0); gone = @(5.0, 5.0) } @{ a = @(1100.0, 1000.0) } 1.0
Assert-Eq $rt.Down 100 'kaybolan arayüz yok sayılır'
$rt = Get-NetRate @{ a = @(10.0, 10.0) } @{ a = @(20000000000.0, 10.0) } 1.0
Assert-Eq $rt.Down 0 'makul olmayan (5 GB/sn üstü) değer atılır'
$rt = Get-NetRate @{ a = @(5000000000.0, 0.0) } @{ a = @(10.0, 0.0) } 1.0
Assert-Eq $rt.Down 0 'sayaç sıfırlanması (32 bit sınırının üstünden düşüş) sıçrama yapmaz'
$rt = Get-NetRate $null $c0 1.0
Assert-Eq $rt.Down 0 'önceki ölçüm yoksa sıfır'
$rt = Get-NetRate $p0 $c0 0.0
Assert-Eq $rt.Up 0 'süre sıfırsa sıfır'
$nt = Get-NetByteTotals
Assert-True ($nt -is [hashtable]) 'arayüz sayaçları tablo olarak döner (bu makinede hata vermez)'
foreach ($k in $nt.Keys) { Assert-True (@($nt[$k]).Count -eq 2) 'her arayüz için (alınan, gönderilen)' }

# ======================= 4) GPU yüzdesi =======================
function New-GpuRow([string]$Name, [double]$V) { [pscustomobject]@{ Name = $Name; UtilizationPercentage = $V } }
$rows = @(
    (New-GpuRow 'pid_100_luid_0x00000000_0x0000F1D1_phys_0_eng_0_engtype_3D' 30),
    (New-GpuRow 'pid_200_luid_0x00000000_0x0000F1D1_phys_0_eng_0_engtype_3D' 25),
    (New-GpuRow 'pid_200_luid_0x00000000_0x0000F1D1_phys_0_eng_1_engtype_3D' 10),
    (New-GpuRow 'pid_200_luid_0x00000000_0x0000F1D1_phys_0_eng_2_engtype_Copy' 90),
    (New-GpuRow 'pid_300_luid_0x00000000_0x0000F1D1_phys_0_eng_3_engtype_VideoDecode' 80)
)
Assert-Eq (Get-GpuLoadFromRows $rows) 55 'aynı motoru kullanan işlemler toplanır, en yüklü 3D motor alınır (Copy / Video sayılmaz)'
$rows2 = @(
    (New-GpuRow 'pid_1_luid_0x00000000_0x0000AAAA_phys_0_eng_0_engtype_3D' 40),
    (New-GpuRow 'pid_1_luid_0x00000000_0x0000BBBB_phys_0_eng_0_engtype_3D' 70)
)
Assert-Eq (Get-GpuLoadFromRows $rows2) 70 'iki ekran kartı: yükü yüksek olan'
$rows3 = @((New-GpuRow 'pid_1_luid_0x00000000_0x0000AAAA_phys_0_eng_0_engtype_3D' 80), (New-GpuRow 'pid_2_luid_0x00000000_0x0000AAAA_phys_0_eng_0_engtype_3D' 70))
Assert-Eq (Get-GpuLoadFromRows $rows3) 100 '100 üstü 100e kırpılır'
Assert-Eq (Get-GpuLoadFromRows @()) '-1' 'satır yoksa -1 (veri yok)'
Assert-Eq (Get-GpuLoadFromRows @((New-GpuRow 'baska_bicim' 50))) '-1' 'tanınmayan ad biçimi veri sayılmaz'
Assert-Eq (Get-GpuLoadFromRows @((New-GpuRow 'pid_1_luid_0x00000000_0x0000AAAA_phys_0_eng_2_engtype_Copy' 50))) '0' 'yalnızca 3D dışı motor varsa 0'

# ======================= 5) bellek =======================
$script:MonCi = $null
function global:Get-CimInstance { param($ClassName, $Namespace, $OperationTimeoutSec, $ErrorAction)
    if ($ClassName -eq 'Win32_OperatingSystem') { return [pscustomobject]@{ TotalVisibleMemorySize = 16777216; FreePhysicalMemory = 4194304; LastBootUpTime = (Get-Date).AddHours(-5) } }
    throw 'yok'
}
$mem = Get-MonMemory
Assert-True ($null -ne $mem -and $mem.Pct -ge 0 -and $mem.Pct -le 100 -and $mem.TotalGB -gt 0) 'bellek ölçümü (ComputerInfo ya da CIM)'
Remove-Item function:\global:Get-CimInstance -ErrorAction SilentlyContinue

# ======================= 6) işlem listesi =======================
$t1 = Get-MonTop @{} 4
Assert-True ($t1.Cur -is [hashtable] -and $t1.Cur.Count -gt 0) 'ilk turda işlem tablosu kurulur'
Assert-Eq @($t1.Top).Count 0 'ilk turda fark olmadığı için liste boş'
$sum = 0.0; for ($i = 0; $i -lt 200000; $i++) { $sum += [math]::Sqrt($i) }
$t2 = Get-MonTop $t1.Cur 4
Assert-True (@($t2.Top).Count -ge 1 -and @($t2.Top).Count -le 5) 'ikinci turda en çok 5 işlem'
$first = @($t2.Top)[0]
Assert-True ($first -is [hashtable] -and $first.ContainsKey('Name') -and $first.ContainsKey('Cpu') -and $first.ContainsKey('Mem') -and $first.ContainsKey('Pid') -and $first.ContainsKey('Win')) 'işlem kaydı alanları'
Assert-True (-not $first.ContainsKey('P')) 'sonuçta Process nesnesi taşınmaz (iş parçacıkları arası)'
Assert-True ($first.Win -is [bool]) 'Win alanı mantıksal'
$sorted = $true; $prev = 1e9; foreach ($x in @($t2.Top)) { if ([double]$x.Cpu -gt $prev) { $sorted = $false }; $prev = [double]$x.Cpu }
Assert-True $sorted 'CPU kullanımına göre azalan sıra'

# ======================= 7) Job_Monitor döngüsü (birkaç tur, sahte uyku) =======================
$script:Sleeps = 0
function global:Start-Sleep { param([int]$Milliseconds, [int]$Seconds)
    $script:Sleeps++
    if ($script:Sleeps -ge 22) { $global:sync.Stop = $true }
}
$global:sync = [hashtable]::Synchronized(@{ Stop = $false; Mon = @{}; MonInterval = 1; GameDirs = @(@{ Name = 'Oyun'; Dir = '/oyun' }); SafeMon = $false; NoGpu = $false })
function global:Get-CimInstance { param($ClassName, $Namespace, $OperationTimeoutSec, $ErrorAction)
    if ($ClassName -eq 'Win32_OperatingSystem') { return [pscustomobject]@{ TotalVisibleMemorySize = 16777216; FreePhysicalMemory = 8388608; LastBootUpTime = (Get-Date).AddHours(-3) } }
    if ($ClassName -eq 'Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine') {
        return @([pscustomobject]@{ Name = 'pid_1_luid_0x00000000_0x0000AAAA_phys_0_eng_0_engtype_3D'; UtilizationPercentage = 42 })
    }
    throw 'yok'
}
function global:Get-ThermalTemp { return 61.5 }
function global:Get-GmRunning { param($Games) return @(@{ Name = 'Oyun'; Pid = 7; Proc = 'oyun.exe' }) }
$res = Job_Monitor @{ Interval = 1 }
Assert-True ($res.Stopped -eq $true) 'döngü Stop ile sonlanır'
$mon = $global:sync.Mon
foreach ($k in @('Boot', 'Cpu', 'Disk', 'Ram', 'RamUsedGB', 'RamTotalGB', 'NetDown', 'NetUp', 'Gpu', 'Temp', 'Games', 'Top', 'Time')) {
    Assert-True ($mon.ContainsKey($k)) ('izleme alanı var: ' + $k)
}
Assert-Eq $mon.Ram 50 'bellek yüzdesi (16 GB, 8 GB boş)'
Assert-Eq $mon.Gpu 42 'GPU yüzdesi CIM satırından'
Assert-Eq $mon.Temp 61.5 'sıcaklık'
Assert-Eq @($mon.Games).Count 1 'çalışan oyun'
Assert-True ($null -ne $global:sync.MonBeat -and (([DateTime]::UtcNow - [DateTime]$global:sync.MonBeat).TotalSeconds -lt 30)) 'nabız her turda güncellenir'
Assert-True ([int]$global:sync.MonDiag.Tick -ge 3) 'tur sayacı ilerler'
# güvenli kipte GPU sorgulanmaz; sıcaklık (salt okunur sayaç) okunmaya devam eder
$script:Sleeps = 0
$global:sync.Stop = $false; $global:sync.SafeMon = $true; $global:sync.Mon = @{}
$script:GpuCalls = 0; $script:TempCalls = 0
function global:Get-CimInstance { param($ClassName, $Namespace, $OperationTimeoutSec, $ErrorAction)
    if ($ClassName -eq 'Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine') { $script:GpuCalls++ }
    if ($ClassName -eq 'Win32_OperatingSystem') { return [pscustomobject]@{ TotalVisibleMemorySize = 16777216; FreePhysicalMemory = 8388608; LastBootUpTime = (Get-Date) } }
    throw 'yok'
}
function global:Get-ThermalTemp { $script:TempCalls++; return 70.0 }
[void](Job_Monitor @{ Interval = 1 })
Assert-Eq $script:GpuCalls 0 'güvenli kipte GPU sorgulanmaz'
Assert-True ($script:TempCalls -ge 1) 'güvenli kipte sıcaklık okunmaya devam eder'
Assert-Eq ([double]$global:sync.Mon.GpuTemp) (-1.0) 'güvenli kipte ekran kartı sıcaklığı okunmaz (-1)'
Assert-Eq $global:sync.Mon.Gpu '-1' 'güvenli kipte GPU -1'
# GPU ayarı kapalıyken de sorgulanmaz
$script:Sleeps = 0; $global:sync.Stop = $false; $global:sync.SafeMon = $false; $global:sync.NoGpu = $true
[void](Job_Monitor @{ Interval = 1 })
Assert-Eq $script:GpuCalls 0 'GPU izleme ayarı kapalıyken sorgulanmaz'
# bozuk ölçümler döngüyü durdurmaz
$script:Sleeps = 0; $global:sync.Stop = $false; $global:sync.NoGpu = $false; $global:sync.Mon = @{}
function global:Get-CimInstance { throw 'WMI yok' }
function global:Get-ThermalTemp { throw 'sensor yok' }
function global:Get-GmRunning { param($Games) throw 'liste yok' }
$res = Job_Monitor @{ Interval = 1 }
Assert-True ($res.Stopped -eq $true -and $global:sync.Mon.ContainsKey('Cpu')) 'tüm ölçümler hata verse de döngü çalışır ve sonuç yazar'
Remove-Item function:\global:Start-Sleep, function:\global:Get-CimInstance, function:\global:Get-ThermalTemp, function:\global:Get-GmRunning -ErrorAction SilentlyContinue

# ======================= 8) canlılık denetimi =======================
$script:Restarts = 0; $script:Warn = New-Object System.Collections.ArrayList
function global:Start-Monitor { $script:Restarts++ }
function global:Write-WhLog { param([string]$Message, [string]$Level = 'INFO') [void]$script:Warn.Add($Message) }
function global:Add-Trace { param([string]$Text) }
class FakeAr { [bool]$IsCompleted }
class FakeRun { [object]BeginStop($a, $b) { return $null } }
class FakeRs { [object]CloseAsync() { return $null } }
function New-FakeWork([bool]$Done) { $ar = New-Object FakeAr; $ar.IsCompleted = $Done; return @{ RunAr = $ar; Run = (New-Object FakeRun); Rs = (New-Object FakeRs) } }
$global:sync.Stop = $false
$script:Quitting = $false; $script:MonStarter = $false; $script:MonGaveUp = $false; $script:MonSeenAt = $null
$script:MonRestarts = New-Object System.Collections.ArrayList
$script:MonWork = New-FakeWork $false
$global:sync.MonBeat = [DateTime]::UtcNow
Test-MonitorAlive
Assert-Eq $script:Restarts 0 'taze nabız: yeniden başlatılmaz'
$global:sync.MonBeat = [DateTime]::UtcNow.AddSeconds(-90)
Test-MonitorAlive
Assert-Eq $script:Restarts 1 '60 sn nabız yok: yeniden başlatılır'
Assert-True ($null -eq $script:MonWork) 'eski iş bırakılır'
$script:MonWork = New-FakeWork $true
Test-MonitorAlive
Assert-Eq $script:Restarts 2 'iş sonlanmış: yeniden başlatılır'
$script:MonWork = New-FakeWork $true
Test-MonitorAlive
Assert-Eq $script:Restarts 3 'üçüncü yeniden başlatma'
$script:MonWork = New-FakeWork $true
Test-MonitorAlive
Assert-Eq $script:Restarts 3 '10 dakikada 3 kezden sonra vazgeçilir'
Assert-True ($script:MonGaveUp -eq $true) 'vazgeçildiği kaydedilir'
$script:MonGaveUp = $false; $script:MonRestarts = New-Object System.Collections.ArrayList
$script:MonStarter = $true; $script:MonWork = New-FakeWork $true
Test-MonitorAlive
Assert-Eq $script:Restarts 3 'izleme henüz başlatılmadıysa (runspace hazırlanıyor) denetlenmez'
$script:MonStarter = $false; $script:Quitting = $true
Test-MonitorAlive
Assert-Eq $script:Restarts 3 'uygulama kapanırken yeniden başlatılmaz'
Remove-Item function:\global:Start-Monitor, function:\global:Write-WhLog, function:\global:Add-Trace -ErrorAction SilentlyContinue

# ======================= 9) derlenmiş betikte bağlantı denetimleri =======================
$src = Get-Content -LiteralPath $env:MM_BUILD -Raw
$jm = $src.Substring($src.IndexOf('function Job_Monitor($P) {'))
$jm = $jm.Substring(0, $jm.IndexOf('#  ISLER (E)'))
$mods = $src.Substring($src.IndexOf('function New-MonBreaker'))
$mods = $mods.Substring(0, $mods.IndexOf('#  ISLER (E)'))
Assert-True ($mods -notmatch 'Get-Counter') 'izleme: Get-Counter (PDH) kullanılmaz'
Assert-True ($mods -notmatch 'PerformanceCounterCategory') 'izleme: PerformanceCounterCategory taraması yok'
Assert-True ($mods -notmatch "'Network Interface'") 'izleme: ağ için PerformanceCounter yok (yönetilen NetworkInterface kullanılır)'
Assert-True ($mods.Contains('$p.Dispose()')) 'izleme: Process nesneleri Dispose edilir'
Assert-True ($jm.Contains('$sync.MonBeat = [DateTime]::UtcNow')) 'izleme: nabız yazılır'
Assert-True ($jm.Contains('$sync.SafeMon') -and $jm.Contains('$sync.NoGpu')) 'izleme: güvenli kip ve GPU ayarı okunur'
Assert-True ($mods.Contains('-OperationTimeoutSec 6')) 'izleme: CIM sorgularında zaman aşımı var'
Assert-True ($src.Contains('try { Test-MonitorAlive } catch { }')) 'izleme zamanlayıcısı canlılık denetimini çağırır'
Assert-True (([regex]::Matches($src, 'function Job_Monitor')).Count -eq 1) 'tek Job_Monitor tanımı'

Show-Result
