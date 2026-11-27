. "$PSScriptRoot/lib.ps1"
# Kararlılık çözümleyici: mavi ekran kodları, uygulama çökmeleri, açılış süresi. Yalnızca saf mantık ve bulgu üretimi (olay günlüğü okunmaz).
Import-Fn 'ConvertTo-BugcheckKey', 'Get-BugcheckInfo', 'Format-BugcheckLabel', 'Get-BugcheckAdvice', 'New-BugcheckAction', 'ConvertTo-MsValue', 'Get-NumMedian', 'Get-CountTopKey',
    'Get-BugcheckSummary', 'Get-BugcheckDominantKind', 'Add-BugcheckFindings', 'Get-AppCrashSummary', 'Test-SystemAppRow', 'Get-AppCrashAdvice', 'Add-AppCrashFindings',
    'Get-BootSummary', 'Format-BootSeconds', 'Get-BootSlowKindText', 'Add-BootFindings', 'Add-Finding', 'Invoke-MemDiagAction'
Import-Var 'BugcheckList', 'RuntimeModuleRx', 'GpuModuleRx', 'SystemAppRx'
$script:BugcheckInfo = @{}
foreach ($bcLine in $script:BugcheckList) {
    $bcPart = ([string]$bcLine).Split('|')
    $script:BugcheckInfo[[string]$bcPart[0]] = @{ Key = [string]$bcPart[0]; Hex = ('0x' + ([string]$bcPart[0]).PadLeft(8, '0')); Name = [string]$bcPart[1]; Kind = [string]$bcPart[2] }
}
$script:Findings = New-Object System.Collections.ArrayList
$script:ExtraActions = @{}
function New-SolveAction([string]$Sub, [string]$Arg, [string]$Label) { return @{ Kind = 'Page'; Page = 'solve'; Sub = $Sub; Label = $Label } }
function Reset-F { $script:Findings.Clear() }

# ---- kod ayrıştırma
Assert-Eq (ConvertTo-BugcheckKey 'The bugcheck was: 0x0000009f (0x0000000000000003, 0xffff)') '9F' 'küçük harfli onaltılık, baştaki sıfırlar atılır'
Assert-Eq (ConvertTo-BugcheckKey '0x00000133') '133' '3 basamak'
Assert-Eq (ConvertTo-BugcheckKey '0xC000021A') 'C000021A' '8 basamaklı kod'
Assert-Eq (ConvertTo-BugcheckKey '0x00000000') '0' 'sıfır kodu'
Assert-Eq (ConvertTo-BugcheckKey 'kod yok') '' 'sayı olmayan metin'
Assert-Eq (ConvertTo-BugcheckKey '') '' 'boş metin'

# ---- tablo
$names = @{}
foreach ($l in $script:BugcheckList) {
    $p = ([string]$l).Split('|')
    Assert-True ($p.Count -eq 3) ("satır biçimi: $l")
    Assert-True ($p[0] -cmatch '^[0-9A-F]{1,8}$') ("kod büyük harfli onaltılık: $($p[0])")
    Assert-True (-not $names.ContainsKey($p[0])) ("yinelenen kod: $($p[0])")
    $names[$p[0]] = $true
    Assert-True (@('driver', 'gpu', 'memory', 'disk', 'hardware', 'system', 'power', 'manual') -contains $p[2]) ("tür geçerli: $l")
    Assert-True ($p[1] -cmatch '^[A-Z0-9_]+$') ("ad büyük harfli: $l")
}
Assert-True ($script:BugcheckList.Count -ge 40) 'tabloda yaygın kodların hepsi var'
foreach ($k in '3B', 'A', '1A', 'D1', '9F', 'EF', '124', '133', '139', '116', '154', '7B', '50', 'C2') { Assert-True ($script:BugcheckInfo.ContainsKey($k)) "yaygın kod tabloda: $k" }
Assert-Eq (Get-BugcheckInfo '124').Name 'WHEA_UNCORRECTABLE_ERROR' 'ad'
Assert-Eq (Get-BugcheckInfo '124').Hex '0x00000124' 'onaltılık gösterim 8 basamak'
Assert-Eq (Get-BugcheckInfo 'a').Key 'A' 'küçük harf büyütülür'
Assert-Eq (Get-BugcheckInfo 'FFFF').Kind 'other' 'bilinmeyen kod türü'
Assert-Eq (Get-BugcheckInfo 'FFFF').Name '' 'bilinmeyen kod adı boş'
Assert-Eq (Get-BugcheckInfo '').Hex '0x00000000' 'boş kod'
Assert-Eq (Format-BugcheckLabel (Get-BugcheckInfo '116')) 'VIDEO_TDR_FAILURE (0x00000116)' 'etiket adlı'
Assert-Eq (Format-BugcheckLabel (Get-BugcheckInfo 'FFFF')) 'kod 0x0000FFFF' 'etiket adsız'

# ---- öneriler
foreach ($kind in 'driver', 'gpu', 'memory', 'disk', 'hardware', 'system', 'power', 'manual', 'other') {
    $a = Get-BugcheckAdvice $kind
    Assert-True ([string]$a.Why -ne '') "neden yazılı: $kind"
    if ($kind -ne 'manual') { Assert-True ([string]$a.Do -ne '') "yapılacak yazılı: $kind" }
    Assert-True ($a.Why -notmatch '\b(yapay zek|AI|GPT)\b') "açıklama kalıntısı yok: $kind"
}
Assert-Eq (Get-BugcheckAdvice 'memory').Run 'MemDiag' 'bellek: sınama eylemi'
Assert-Eq (Get-BugcheckAdvice 'disk').Page 'solve' 'disk: Çözüm Merkezi'
Assert-Eq (New-BugcheckAction (Get-BugcheckAdvice 'memory')).Key 'MemDiag' 'bellek eylemi Run'
Assert-Eq (New-BugcheckAction (Get-BugcheckAdvice 'disk')).Page 'solve' 'disk eylemi sayfa'
Assert-Eq (New-BugcheckAction (Get-BugcheckAdvice 'driver')).Page 'tools' 'sürücü eylemi araçlar'

# ---- özet
$e = @(
    @{ Time = [datetime]'2026-03-01 10:00'; Key = '9F' }, @{ Time = [datetime]'2026-03-05 10:00'; Key = '9F' }, @{ Time = [datetime]'2026-03-07 09:00'; Key = '133' },
    @{ Time = [datetime]'2026-03-08 09:00'; Key = 'E2' }, @{ Time = [datetime]'2026-03-09 09:00'; Key = '' }
)
$s = Get-BugcheckSummary $e
Assert-Eq $s.Total 3 'elle üretilen ve boş kod sayılmaz'
Assert-Eq $s.Manual 1 'elle üretilen ayrı sayılır'
Assert-Eq $s.Rows[0].Key '9F' 'en sık kod başta'
Assert-Eq $s.Rows[0].Count 2 'sayı'
Assert-Eq $s.Rows[1].Key '133' 'ikinci'
Assert-Eq $s.Last.ToString('yyyy-MM-dd') '2026-03-07' 'son hata elle üretileni içermez'
$s0 = Get-BugcheckSummary @()
Assert-Eq $s0.Total 0 'boş özet'
Assert-Eq (Get-BugcheckDominantKind $s) 'power' 'baskın tür'
Assert-Eq (Get-BugcheckDominantKind $s0) 'other' 'baskın tür boş'
$tie = Get-BugcheckSummary @(@{ Time = [datetime]'2026-03-01'; Key = 'FFFF' }, @{ Time = [datetime]'2026-03-02'; Key = 'FFFF' }, @{ Time = [datetime]'2026-03-03'; Key = '1A' })
Assert-Eq (Get-BugcheckDominantKind $tie) 'memory' 'bilinmeyen kod baskınsa bilinen ilk tür'

# ---- bulgular
Reset-F
Add-BugcheckFindings $s0 30 0
Assert-Eq $script:Findings.Count 1 'temiz: tek bulgu'
Assert-Eq $script:Findings[0].Status 'ok' 'temiz: ok'
Reset-F
Add-BugcheckFindings $s 30 0
Assert-Eq $script:Findings.Count 1 '3 hata: tek bulgu'
Assert-Eq $script:Findings[0].Status 'warn' '3 hata: uyarı'
Assert-Eq $script:Findings[0].Weight 6 '3 hata: ağırlık'
Assert-True ($script:Findings[0].Title -like '*3 mavi ekran*DRIVER_POWER_STATE_FAILURE*') 'başlıkta sayı ve ad'
Assert-True ($script:Findings[0].Detail -like '*Diğer kodlar*DPC_WATCHDOG_VIOLATION*') 'ayrıntıda diğer kodlar'
Reset-F
Add-BugcheckFindings (Get-BugcheckSummary @(@{ Time = [datetime]'2026-03-01'; Key = '1A' })) 30 0
Assert-Eq $script:Findings[0].Status 'info' 'tek hata: bilgi'
Assert-Eq $script:Findings[0].Action.Key 'MemDiag' 'bellek hatasında sınama eylemi'
Reset-F
Add-BugcheckFindings $s0 30 4
Assert-Eq $script:Findings.Count 2 'beklenmedik kapanma: ek bulgu'
Assert-Eq $script:Findings[1].Id 'pwr41' 'kapanma bulgusu'
Reset-F
Add-BugcheckFindings $s0 30 2
Assert-Eq $script:Findings.Count 1 '2 kapanma bulgu üretmez'

# ---- yardımcılar
Assert-Eq (ConvertTo-MsValue '1234.5') 1234.5 'ms değeri'
Assert-Eq (ConvertTo-MsValue 'x') 0.0 'ms değeri geçersiz'
Assert-Eq (Get-NumMedian @(1, 3, 2)) 2 'ortanca tek'
Assert-Eq (Get-NumMedian @(1, 2, 3, 4)) 2.5 'ortanca çift'
Assert-Eq (Get-NumMedian @()) 0 'ortanca boş'
Assert-Eq (Get-CountTopKey @{ a = 1; b = 3; c = 3 }) 'b' 'eşitlikte alfabetik ilk'
Assert-Eq (Get-CountTopKey @{}) '' 'boş sayaç'

# ---- uygulama çökmeleri
function New-Ev([string]$App, [string]$Kind, [string]$Mod, [string]$Code, [string]$Day, [string]$Path = '') { return @{ Time = [datetime]$Day; Kind = $Kind; App = $App; Module = $Mod; Code = $Code; Path = $Path } }
$ev = @(
    (New-Ev 'Oyun.exe' 'crash' 'VCRUNTIME140.dll' 'c0000005' '2026-03-01 10:00' 'C:\Oyun\Oyun.exe'),
    (New-Ev 'oyun.exe' 'crash' 'vcruntime140.dll' 'c0000005' '2026-03-02 10:00' 'C:\Oyun\Oyun.exe'),
    (New-Ev 'oyun.exe' 'hang' '' '' '2026-03-03 10:00' 'C:\Oyun\Oyun.exe'),
    (New-Ev 'baska.exe' 'crash' 'x.dll' 'c0000374' '2026-03-04 10:00'),
    (New-Ev '' 'crash' 'y.dll' 'c1' '2026-03-05 10:00')
)
$as = Get-AppCrashSummary $ev
Assert-Eq $as.Total 4 'adı boş kayıt sayılmaz'
Assert-Eq $as.Rows[0].App 'oyun.exe' 'ad küçük harfe çevrilir, kayıtlar birleşir'
Assert-Eq $as.Rows[0].Count 3 'toplam'
Assert-Eq $as.Rows[0].Crashes 2 'çökme sayısı'
Assert-Eq $as.Rows[0].Hangs 1 'yanıt vermeme sayısı'
Assert-Eq $as.Rows[0].Module 'vcruntime140.dll' 'en sık modül'
Assert-Eq $as.Rows[0].Code 'c0000005' 'en sık kod'
Assert-Eq $as.Rows[0].Path 'C:\Oyun\Oyun.exe' 'yol'
Assert-Eq (Get-AppCrashSummary $ev 1).Rows.Count 1 'en çok N satır'
Assert-Eq (Get-AppCrashSummary @()).Total 0 'boş özet'

$env:WINDIR = 'C:\Windows'
Assert-True (Test-SystemAppRow @{ App = 'explorer.exe'; Path = '' }) 'explorer sistem uygulaması'
Assert-True (Test-SystemAppRow @{ App = 'x.exe'; Path = 'C:\Windows\System32\x.exe' }) 'Windows klasörü'
Assert-True (-not (Test-SystemAppRow @{ App = 'x.exe'; Path = 'C:\Windows\Temp\x.exe' })) 'Windows\Temp sistem sayılmaz'
Assert-True (-not (Test-SystemAppRow @{ App = 'oyun.exe'; Path = 'C:\Oyun\oyun.exe' })) 'kullanıcı uygulaması'

$adv = Get-AppCrashAdvice $as.Rows[0]
Assert-Eq $adv.Kind 'runtime' 'VC++ çalışma zamanı'
Assert-Eq $adv.Action.Kind 'Url' 'çalışma zamanı: bağlantı'
Assert-True ($adv.Action.Url -like 'https://learn.microsoft.com/*') 'Microsoft bağlantısı'
Assert-Eq (Get-AppCrashAdvice @{ App = 'a.exe'; Module = ''; Code = 'c0000135'; Path = ''; Crashes = 1; Hangs = 0 }).Kind 'runtime' 'DLL bulunamadı kodu'
Assert-Eq (Get-AppCrashAdvice @{ App = 'a.exe'; Module = 'nvwgf2umx.dll'; Code = 'c0000005'; Path = ''; Crashes = 1; Hangs = 0 }).Kind 'gpu' 'ekran kartı sürücüsü'
Assert-Eq (Get-AppCrashAdvice @{ App = 'powershell.exe'; Module = 'x'; Code = ''; Path = ''; Crashes = 1; Hangs = 0 }).Kind 'powershell' 'PowerShell'
Assert-Eq (Get-AppCrashAdvice @{ App = 'powershell.exe'; Module = ''; Code = ''; Path = ''; Crashes = 1; Hangs = 0 }).Action.Page 'settings' 'PowerShell: ayarlar'
Assert-Eq (Get-AppCrashAdvice @{ App = 'explorer.exe'; Module = 'ntdll.dll'; Code = 'c0000005'; Path = ''; Crashes = 3; Hangs = 0 }).Kind 'system' 'sistem uygulaması'
Assert-Eq (Get-AppCrashAdvice @{ App = 'a.exe'; Module = 'KERNELBASE.dll'; Code = 'e0434352'; Path = ''; Crashes = 3; Hangs = 0 }).Kind 'dotnet' '.NET hatası'
Assert-Eq (Get-AppCrashAdvice @{ App = 'a.exe'; Module = ''; Code = ''; Path = ''; Crashes = 1; Hangs = 4 }).Kind 'hang' 'yanıt vermeme'
Assert-Eq (Get-AppCrashAdvice @{ App = 'a.exe'; Module = 'b.dll'; Code = 'c0000005'; Path = ''; Crashes = 3; Hangs = 0 }).Kind 'generic' 'genel'

Reset-F
Add-AppCrashFindings (Get-AppCrashSummary @()) 30
Assert-Eq $script:Findings[0].Status 'ok' 'çökme yok: ok'
Reset-F
Add-AppCrashFindings (Get-AppCrashSummary @((New-Ev 'a.exe' 'crash' 'b.dll' 'c1' '2026-03-01'))) 30
Assert-Eq $script:Findings[0].Status 'ok' 'tek kayıt: ok'
Reset-F
Add-AppCrashFindings $as 30
Assert-Eq $script:Findings[0].Status 'info' '3 kayıt: bilgi'
Assert-True ($script:Findings[0].Title -like '*oyun.exe*2 kez çöktü ve 1 kez yanıt vermedi*') 'başlık'
Assert-True ($script:Findings[0].Detail -like '*Çökme noktası: vcruntime140.dll (c0000005)*') 'çökme noktası'
Assert-True ($script:Findings[0].Detail -like '*baska.exe (1)*') 'diğer uygulamalar'
$many = @(); for ($i = 0; $i -lt 6; $i++) { $many += , (New-Ev 'a.exe' 'crash' 'b.dll' 'c1' ('2026-03-0' + ($i + 1))) }
Reset-F
Add-AppCrashFindings (Get-AppCrashSummary $many) 30
Assert-Eq $script:Findings[0].Status 'warn' '5 ve üstü: uyarı'

# ---- açılış süresi
$boots = @(
    @{ Time = [datetime]'2026-03-01'; BootMs = 80000; MainMs = 40000; PostMs = 40000 },
    @{ Time = [datetime]'2026-03-02'; BootMs = 100000; MainMs = 60000; PostMs = 40000 },
    @{ Time = [datetime]'2026-03-03'; BootMs = 120000; MainMs = 100000; PostMs = 20000 }
)
$slow = @(
    @{ Time = [datetime]'2026-03-02'; Id = 101; Name = 'Slow.exe'; Friendly = ''; TotalMs = 20000; DegradeMs = 15000 },
    @{ Time = [datetime]'2026-03-03'; Id = 101; Name = 'slow.exe'; Friendly = ''; TotalMs = 22000; DegradeMs = 18000 },
    @{ Time = [datetime]'2026-03-03'; Id = 103; Name = 'Hizmet'; Friendly = ''; TotalMs = 5000; DegradeMs = 2000 },
    @{ Time = [datetime]'2026-03-03'; Id = 102; Name = 'surucu.sys'; Friendly = ''; TotalMs = 9000; DegradeMs = 4000 }
)
$bs = Get-BootSummary $boots $slow
Assert-Eq $bs.Count 3 'açılış sayısı'
Assert-Eq $bs.Last.MainMs 100000 'son açılış en yeni olandır'
Assert-Eq $bs.MedianMain 60000 'ortanca'
Assert-Eq @($bs.Slow).Count 2 '3 sn altı yavaşlatıcı sayılmaz'
Assert-Eq $bs.Slow[0].Name 'Slow.exe' 'en çok yavaşlatan başta'
Assert-Eq $bs.Slow[0].Count 2 'ad büyük-küçük harfe bakmadan birleşir'
Assert-Eq (Get-BootSummary @() @()).Count 0 'boş açılış özeti'
Assert-Eq (Format-BootSeconds 45500) '46' 'saniye yuvarlama'
Assert-Eq (Get-BootSlowKindText 102) 'sürücü' 'tür adı'

Reset-F
Add-BootFindings (Get-BootSummary @() @()) 'SSD'
Assert-Eq $script:Findings.Count 0 'açılış verisi yoksa bulgu yok'
Reset-F
Add-BootFindings $bs 'SSD'
Assert-Eq $script:Findings[0].Status 'info' 'SSD: 60 sn ortanca bilgi'
Assert-Eq $script:Findings[0].Id 'boot-time' 'bulgu kimliği'
Assert-True ($script:Findings[0].Detail -like '*Slow.exe (uygulama, +18 sn)*') 'yavaşlatan uygulama yazılı'
Assert-Eq $script:Findings[0].Action.Page 'startup' 'uygulama yavaşlatıyorsa Başlangıç sayfası'
Reset-F
Add-BootFindings $bs 'HDD'
Assert-Eq $script:Findings[0].Status 'ok' 'HDD: 60 sn ortanca normal'
Assert-True ($null -eq $script:Findings[0].Action) 'normal açılışta eylem yok'
Reset-F
Add-BootFindings (Get-BootSummary @(@{ Time = [datetime]'2026-03-01'; BootMs = 200000; MainMs = 170000; PostMs = 30000 }) @()) 'SSD'
Assert-Eq $script:Findings[0].Status 'warn' 'çok yavaş açılış: uyarı'
Assert-Eq $script:Findings[0].Weight 2 'ağırlık'
Assert-True ($script:Findings[0].Detail -like '*Fast Boot*') 'yavaşlatıcı yoksa BIOS ipucu'

Show-Result
