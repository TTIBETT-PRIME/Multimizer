# ==================================================================
#  KARARLILIK ÇÖZÜMLEYİCİ: mavi ekran kodları, uygulama çökmeleri ve açılış süresi
#  Yalnızca olay günlüklerini okur, hiçbir şeyi değiştirmez. Olay metinleri Windows diline bağlı olduğundan yalnızca olay kimlikleri ve veri
#  alanları kullanılır; Türkçe, İngilizce ya da başka dilli Windows’ta aynı sonucu verir. Her bulgu nedenini ve atılacak adımı söyler.
#  Yeniden başlatma isteyen bellek sınaması gibi adımlar yalnızca kullanıcı düğmeye basınca Windows’un kendi aracını açar.
# ==================================================================

# Hata denetimi (mavi ekran) kodları. Biçim: 'KOD|AD|TÜR'. KOD büyük harfli onaltılık, baştaki sıfırlar atılmış (0x0000000A -> A).
# TÜR: driver (sürücü), gpu (ekran kartı), memory (bellek), disk (disk ve dosya sistemi), hardware (işlemci, anakart, aşırı hız, güç),
#      system (Windows dosyaları), power (güç geçişi), manual (elle üretilmiş). Adlar Microsoft’un hata denetimi kodu başvurusundaki adlardır.
$script:BugcheckList = @(
    'A|IRQL_NOT_LESS_OR_EQUAL|driver',
    '1A|MEMORY_MANAGEMENT|memory',
    '1E|KMODE_EXCEPTION_NOT_HANDLED|driver',
    '23|FAT_FILE_SYSTEM|disk',
    '24|NTFS_FILE_SYSTEM|disk',
    '2E|DATA_BUS_ERROR|memory',
    '3B|SYSTEM_SERVICE_EXCEPTION|driver',
    '3F|NO_MORE_SYSTEM_PTES|driver',
    '4E|PFN_LIST_CORRUPT|memory',
    '50|PAGE_FAULT_IN_NONPAGED_AREA|memory',
    '51|REGISTRY_ERROR|disk',
    '77|KERNEL_STACK_INPAGE_ERROR|disk',
    '7A|KERNEL_DATA_INPAGE_ERROR|disk',
    '7B|INACCESSIBLE_BOOT_DEVICE|disk',
    '7E|SYSTEM_THREAD_EXCEPTION_NOT_HANDLED|driver',
    '7F|UNEXPECTED_KERNEL_MODE_TRAP|hardware',
    '8E|KERNEL_MODE_EXCEPTION_NOT_HANDLED|driver',
    '9C|MACHINE_CHECK_EXCEPTION|hardware',
    '9F|DRIVER_POWER_STATE_FAILURE|power',
    'A0|INTERNAL_POWER_ERROR|power',
    'BE|ATTEMPTED_WRITE_TO_READONLY_MEMORY|driver',
    'C2|BAD_POOL_CALLER|driver',
    'C4|DRIVER_VERIFIER_DETECTED_VIOLATION|driver',
    'C5|DRIVER_CORRUPTED_EXPOOL|driver',
    'CA|PNP_DETECTED_FATAL_ERROR|driver',
    'D1|DRIVER_IRQL_NOT_LESS_OR_EQUAL|driver',
    'D5|DRIVER_PAGE_FAULT_IN_FREED_SPECIAL_POOL|driver',
    'E2|MANUALLY_INITIATED_CRASH|manual',
    'EA|THREAD_STUCK_IN_DEVICE_DRIVER|gpu',
    'EF|CRITICAL_PROCESS_DIED|system',
    'F4|CRITICAL_OBJECT_TERMINATION|disk',
    'FC|ATTEMPTED_EXECUTE_OF_NOEXECUTE_MEMORY|driver',
    '101|CLOCK_WATCHDOG_TIMEOUT|hardware',
    '109|CRITICAL_STRUCTURE_CORRUPTION|hardware',
    '116|VIDEO_TDR_FAILURE|gpu',
    '117|VIDEO_TDR_TIMEOUT_DETECTED|gpu',
    '119|VIDEO_SCHEDULER_INTERNAL_ERROR|gpu',
    '124|WHEA_UNCORRECTABLE_ERROR|hardware',
    '133|DPC_WATCHDOG_VIOLATION|driver',
    '139|KERNEL_SECURITY_CHECK_FAILURE|driver',
    '13A|KERNEL_MODE_HEAP_CORRUPTION|driver',
    '141|VIDEO_ENGINE_TIMEOUT_DETECTED|gpu',
    '154|UNEXPECTED_STORE_EXCEPTION|disk',
    '1CA|SYNTHETIC_WATCHDOG_TIMEOUT|hardware',
    'C000021A|STATUS_SYSTEM_PROCESS_TERMINATED|system'
)
$script:BugcheckInfo = @{}
foreach ($bcLine in $script:BugcheckList) {
    $bcPart = ([string]$bcLine).Split('|')
    $script:BugcheckInfo[[string]$bcPart[0]] = @{ Key = [string]$bcPart[0]; Hex = ('0x' + ([string]$bcPart[0]).PadLeft(8, '0')); Name = [string]$bcPart[1]; Kind = [string]$bcPart[2] }
}

# "0x00000133 (0x0000000000000001, ...)" -> "133"; sayı bulunamazsa boş
function ConvertTo-BugcheckKey([string]$Text) {
    $m = [regex]::Match([string]$Text, '(?i)0x([0-9a-f]{1,8})')
    if (-not $m.Success) { return '' }
    $h = $m.Groups[1].Value.TrimStart('0').ToUpperInvariant()
    if ($h -eq '') { $h = '0' }
    return $h
}

# Bilinmeyen kod: Ad boş, Tür other
function Get-BugcheckInfo([string]$Key) {
    $k = ([string]$Key).Trim().ToUpperInvariant()
    if ($script:BugcheckInfo.ContainsKey($k)) { return $script:BugcheckInfo[$k] }
    $pad = $k
    if ($pad -eq '') { $pad = '0' }
    return @{ Key = $k; Hex = ('0x' + $pad.PadLeft(8, '0')); Name = ''; Kind = 'other' }
}

function Format-BugcheckLabel($Row) {
    if ([string]$Row.Name -ne '') { return ([string]$Row.Name + ' (' + [string]$Row.Hex + ')') }
    return ('kod ' + [string]$Row.Hex)
}

# Türe göre neden ve atılacak adım. Run: Job_Action anahtarı (boş olabilir); Page: yönlendirilecek sayfa
function Get-BugcheckAdvice([string]$Kind) {
    $a = @{ Kind = $Kind; Why = ''; Do = ''; Run = ''; Page = 'tools' }
    if ($Kind -eq 'driver') {
        $a.Why = 'Bir sürücü ya da hizmet çekirdek belleğine yanlış eriştiği için Windows kendini durdurdu. En sık nedenler: yeni kurulan ya da eski kalmış bir sürücü (ağ, ses, depolama, dokunmatik yüzey), sanal ağ bağdaştırıcıları ve bazı güvenlik yazılımları.'
        $a.Do = 'Hatalar bir kurulumdan sonra başladıysa o sürücüyü ya da programı kaldırın. Değilse Windows Update’teki “isteğe bağlı güncellemeleri” ve cihaz üreticisinin sitesindeki en son sürücüleri kurun. Ardından Araçlar > Onarım’da sistem dosyası denetimini çalıştırın.'
    } elseif ($Kind -eq 'gpu') {
        $a.Why = 'Ekran kartı sürücüsü ya da ekran kartı donanımı yanıt vermeyi bıraktı. Aşırı ısınma, kararsız aşırı hız (overclock), yetersiz güç ya da bozuk sürücü kurulumu bunun nedeni olabilir.'
        $a.Do = 'Ekran kartı sürücüsünü üreticisinden indirip “temiz kurulum” seçeneğiyle yeniden kurun. Aşırı hız ve özel fan ayarlarını varsayılana alın, kartın sıcaklığına ve güç kablolarına bakın. Oyun ya da yoğun iş sırasında oluyorsa kasa içi havalandırmayı denetleyin.'
    } elseif ($Kind -eq 'memory') {
        $a.Why = 'Bellek (RAM) hatası ya da belleği bozan bir sürücü. Bu kodlar en sık bozuk ya da gevşek takılmış bir bellek modülünden, hatalı bellek hızı (XMP/EXPO) ayarından çıkar.'
        $a.Do = 'Windows Bellek Tanılama’yı çalıştırın (bilgisayar yeniden başlar ve modülleri sınar). BIOS’ta XMP/EXPO ve aşırı hız ayarlarını kapatın. Birden çok modül varsa tek tek takarak hangisinin hatalı olduğunu bulun.'
        $a.Run = 'MemDiag'
    } elseif ($Kind -eq 'disk') {
        $a.Why = 'Disk, disk bağlantısı ya da dosya sistemi hatası. Bozulmaya başlayan bir SSD/HDD, gevşek ya da bozuk bir SATA/NVMe bağlantısı ya da dosya sistemi hataları bunu tetikler.'
        $a.Do = 'Önce önemli dosyalarınızın yedeğini alın. Çözüm Merkezi’nin Disk sekmesinden disk sağlığına (S.M.A.R.T.) bakın ve sürücüyü denetleyin. Bağlantı kablosunu ya da portu değiştirmeyi deneyin; sağlık uyarıyorsa diski değiştirin.'
        $a.Page = 'solve'
    } elseif ($Kind -eq 'hardware') {
        $a.Why = 'Donanım düzeyinde bir hata bildirildi (işlemci, bellek denetleyicisi, anakart ya da güç). Aşırı hız, düşük voltaj ayarı (undervolt), yetersiz soğutma ve zayıf güç kaynağı bunu tetikler.'
        $a.Do = 'BIOS/UEFI’de aşırı hız, undervolt ve XMP/EXPO ayarlarını varsayılana alın; BIOS ve yonga seti sürücülerini güncelleyin. Sıcaklıkları ve güç kaynağını denetleyin. Sorun sürerse donanımı servis sınasın.'
    } elseif ($Kind -eq 'system') {
        $a.Why = 'Windows’un kritik bir işlemi beklenmedik biçimde sonlandı. Sistem dosyalarının bozulması, disk hataları ya da bir sürücü bunun nedeni olabilir.'
        $a.Do = 'Araçlar > Onarım’da sistem dosyası denetimini (SFC) ve ardından DISM onarımını çalıştırın. Hatalar bir güncellemeden ya da sürücüden sonra başladıysa onu geri alın.'
    } elseif ($Kind -eq 'power') {
        $a.Why = 'Bir aygıt uyku, hazırda bekletme ya da güç tasarrufu geçişinde yanıt vermedi. Genellikle ağ, depolama ya da yonga seti sürücüsünün güç yönetimi hatasıdır.'
        $a.Do = 'Yonga seti, depolama ve ağ sürücülerini güncelleyin. Hızlandır sayfasındaki “Hızlı Başlatma’yı kapat” ayarını deneyin. Aygıt Yöneticisi’nde ağ bağdaştırıcısının “Gücü tasarruf etmek için bilgisayarın bu aygıtı kapatmasına izin ver” seçeneğini kaldırın.'
    } elseif ($Kind -eq 'manual') {
        $a.Why = 'Bu hata denetimi elle ya da bir hata ayıklama aracıyla bilerek oluşturulmuş.'
    } else {
        $a.Why = 'Bu kod için hazır bir açıklama yok. Mavi ekranların çoğu sürücü, bellek ya da disk kaynaklıdır.'
        $a.Do = 'Windows’u ve sürücüleri güncelleyin, Araçlar > Onarım’da sistem dosyası denetimini çalıştırın. Kodu Microsoft’un “Hata denetimi kodu başvurusu” sayfasında aratabilirsiniz.'
    }
    return $a
}

function New-BugcheckAction($Advice) {
    if ([string]$Advice.Run -eq 'MemDiag') { return @{ Kind = 'Run'; Key = 'MemDiag'; Label = 'Bellek sınamasını aç' } }
    if ([string]$Advice.Page -eq 'solve') { return (New-SolveAction 'disk' '' 'Diskleri aç') }
    return @{ Kind = 'Page'; Page = 'tools'; Label = 'Onarım' }
}

# Windows Bellek Tanılama’yı açar; sınama ve yeniden başlatma seçeneğini kullanıcı kendisi seçer
function Invoke-MemDiagAction($P) {
    $exe = Join-Path ([string]$env:WINDIR) 'System32\MdSched.exe'
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw 'Windows Bellek Tanılama bu Windows sürümünde bulunamadı.' }
    Start-Process -FilePath $exe | Out-Null
    Write-WhLog 'Windows Bellek Tanılama açıldı. Sınamayı başlatırsanız bilgisayar yeniden başlar; önce açık dosyalarınızı kaydedin.' 'INFO'
}
$script:ExtraActions['MemDiag'] = 'Invoke-MemDiagAction'

# Olay veri alanları: Ad -> değer (XML’den; dile bağlı değil)
function Get-EventDataMap($Ev) {
    $m = @{}
    try {
        $x = [xml]$Ev.ToXml()
        foreach ($d in @($x.Event.EventData.Data)) {
            if ($null -ne $d -and $null -ne $d.Name) { $m[[string]$d.Name] = [string]$d.'#text' }
        }
    } catch { }
    return $m
}

function ConvertTo-MsValue($Value) {
    $d = 0.0
    if ([double]::TryParse([string]$Value, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$d)) { return $d }
    return 0.0
}

function Get-NumMedian($Values) {
    $v = @(@($Values) | ForEach-Object { [double]$_ } | Sort-Object)
    if ($v.Count -eq 0) { return 0.0 }
    $mid = [int][math]::Floor($v.Count / 2)
    if (($v.Count % 2) -eq 1) { return [double]$v[$mid] }
    return (([double]$v[$mid - 1] + [double]$v[$mid]) / 2.0)
}

# Bir sayaç tablosunda (ad -> adet) en çok geçen ad; eşitlikte alfabetik ilk
function Get-CountTopKey($Counts) {
    $best = ''
    $bestN = 0
    foreach ($k in (@($Counts.Keys) | Sort-Object)) {
        if ([int]$Counts[$k] -gt $bestN) { $best = [string]$k; $bestN = [int]$Counts[$k] }
    }
    return $best
}

# ---------------- mavi ekran ----------------
# Dönüş: @(@{ Time; Key }) (yeni kayıtlar önde olmak zorunda değil). Sistem günlüğü, WER-SystemErrorReporting 1001
function Get-BugcheckEvents([int]$Days = 30) {
    $out = New-Object System.Collections.ArrayList
    $evs = @()
    try { $evs = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WER-SystemErrorReporting'; Id = 1001; StartTime = (Get-Date).AddDays(-$Days) } -MaxEvents 100 -ErrorAction Stop) } catch { $evs = @() }
    foreach ($e in $evs) {
        $txt = ''
        try { if ($e.Properties.Count -gt 0) { $txt = [string]$e.Properties[0].Value } } catch { $txt = '' }
        $k = ConvertTo-BugcheckKey $txt
        if ($k -eq '') { try { $k = ConvertTo-BugcheckKey ([string]$e.Message) } catch { $k = '' } }
        if ($k -eq '') { continue }
        [void]$out.Add(@{ Time = [datetime]$e.TimeCreated; Key = $k })
    }
    return , $out.ToArray()
}

# Mavi ekran olmadan gerçekleşen beklenmedik kapanmalar (Kernel-Power 41, BugcheckCode 0)
function Get-PowerLossCount([int]$Days = 30) {
    $n = 0
    $evs = @()
    try { $evs = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Power'; Id = 41; StartTime = (Get-Date).AddDays(-$Days) } -MaxEvents 100 -ErrorAction Stop) } catch { return 0 }
    foreach ($e in $evs) {
        $m = Get-EventDataMap $e
        $bc = 0.0
        if ($m.ContainsKey('BugcheckCode')) { $bc = ConvertTo-MsValue $m['BugcheckCode'] }
        if ($bc -eq 0) { $n++ }
    }
    return $n
}

# Kodlara göre özet: Total (elle üretilenler hariç), Manual, Last, Rows (en sık olan önde)
function Get-BugcheckSummary($Events) {
    $by = @{}
    $manual = 0
    $last = [datetime]'2000-01-01'
    foreach ($e in @($Events)) {
        $k = [string]$e.Key
        if ($k -eq '') { continue }
        $inf = Get-BugcheckInfo $k
        if ([string]$inf.Kind -eq 'manual') { $manual++; continue }
        if (-not $by.ContainsKey($k)) { $by[$k] = @{ Count = 0; Last = [datetime]'2000-01-01' } }
        $by[$k].Count = [int]$by[$k].Count + 1
        if ($e.Time -gt $by[$k].Last) { $by[$k].Last = $e.Time }
        if ($e.Time -gt $last) { $last = $e.Time }
    }
    $rows = New-Object System.Collections.ArrayList
    foreach ($k in $by.Keys) {
        $inf = Get-BugcheckInfo ([string]$k)
        [void]$rows.Add(@{ Key = [string]$k; Hex = [string]$inf.Hex; Name = [string]$inf.Name; Kind = [string]$inf.Kind; Count = [int]$by[$k].Count; Last = $by[$k].Last })
    }
    $sorted = @($rows | Sort-Object @{ Expression = { [int]$_.Count }; Descending = $true }, @{ Expression = { $_.Last }; Descending = $true }, @{ Expression = { [string]$_.Key } })
    $total = 0
    foreach ($r in $sorted) { $total += [int]$r.Count }
    return @{ Total = $total; Manual = $manual; Last = $last; Rows = $sorted }
}

# En sık görülen kodun türü; o bilinmiyorsa bilinen ilk tür
function Get-BugcheckDominantKind($Summary) {
    $rows = @($Summary.Rows)
    if ($rows.Count -eq 0) { return 'other' }
    if ([string]$rows[0].Kind -ne 'other') { return [string]$rows[0].Kind }
    foreach ($r in $rows) { if ([string]$r.Kind -ne 'other') { return [string]$r.Kind } }
    return 'other'
}

function Add-BugcheckFindings($Summary, [int]$Days, [int]$PowerLoss) {
    $d = [string]$Days
    $n = [int]$Summary.Total
    if ($n -eq 0) {
        Add-Finding 'bsod' 'maint' 'ok' ('Son ' + $d + ' günde mavi ekran hatası yok') ''
    } else {
        $rows = @($Summary.Rows)
        $kind = Get-BugcheckDominantKind $Summary
        $adv = Get-BugcheckAdvice $kind
        $parts = New-Object System.Collections.ArrayList
        [void]$parts.Add('Son hata: ' + $Summary.Last.ToString('dd.MM.yyyy HH:mm') + '.')
        if ($rows.Count -gt 1) {
            $oth = New-Object System.Collections.ArrayList
            foreach ($r in @($rows | Select-Object -Skip 1 -First 3)) { [void]$oth.Add((Format-BugcheckLabel $r) + ' ' + [string]$r.Count + ' kez') }
            [void]$parts.Add('Diğer kodlar: ' + ($oth.ToArray() -join ', ') + '.')
        }
        [void]$parts.Add([string]$adv.Why)
        if ([string]$adv.Do -ne '') { [void]$parts.Add([string]$adv.Do) }
        $status = 'info'
        $w = 0
        if ($n -ge 3) { $status = 'warn'; $w = 6 }
        $title = 'Son ' + $d + ' günde ' + [string]$n + ' mavi ekran hatası: ' + (Format-BugcheckLabel $rows[0])
        Add-Finding 'bsod' 'maint' $status $title ($parts.ToArray() -join ' ') (New-BugcheckAction $adv) $w
    }
    if ($PowerLoss -ge 3) {
        Add-Finding 'pwr41' 'maint' 'info' ('Son ' + $d + ' günde ' + [string]$PowerLoss + ' beklenmedik kapanma') 'Bunlar mavi ekran vermeden kapanmış: bilgisayar kendiliğinden kapandı ya da güç kesildi. Elektrik kesintisi, aşırı ısınma, gevşek güç bağlantısı ya da güç kaynağı sorunu olabilir; dizüstünde şarj kablosunu ve pili de deneyin.'
    }
}

function Chk_Crashes {
    $days = 30
    $ev = Get-BugcheckEvents $days
    $sum = Get-BugcheckSummary $ev
    $loss = Get-PowerLossCount $days
    Add-BugcheckFindings $sum $days $loss
}

# ---------------- uygulama çökmeleri ----------------
# Application Error (1000) ve Application Hang (1002). Dönüş: @(@{ Time; Kind (crash | hang); App; Module; Code; Path })
function Get-AppCrashEvents([int]$Days = 30) {
    $out = New-Object System.Collections.ArrayList
    $since = (Get-Date).AddDays(-$Days)
    $evs = @()
    try { $evs = @(Get-WinEvent -FilterHashtable @{ LogName = 'Application'; ProviderName = 'Application Error'; Id = 1000; StartTime = $since } -MaxEvents 400 -ErrorAction Stop) } catch { $evs = @() }
    foreach ($e in $evs) {
        $p = $null
        try { $p = $e.Properties } catch { $p = $null }
        if ($null -eq $p -or $p.Count -lt 7) { continue }
        $path = ''
        if ($p.Count -gt 10) { $path = [string]$p[10].Value }
        [void]$out.Add(@{ Time = [datetime]$e.TimeCreated; Kind = 'crash'; App = [string]$p[0].Value; Module = [string]$p[3].Value; Code = [string]$p[6].Value; Path = $path })
    }
    $hv = @()
    try { $hv = @(Get-WinEvent -FilterHashtable @{ LogName = 'Application'; ProviderName = 'Application Hang'; Id = 1002; StartTime = $since } -MaxEvents 200 -ErrorAction Stop) } catch { $hv = @() }
    foreach ($e in $hv) {
        $p = $null
        try { $p = $e.Properties } catch { $p = $null }
        if ($null -eq $p -or $p.Count -lt 1) { continue }
        $path = ''
        if ($p.Count -gt 5) { $path = [string]$p[5].Value }
        [void]$out.Add(@{ Time = [datetime]$e.TimeCreated; Kind = 'hang'; App = [string]$p[0].Value; Module = ''; Code = ''; Path = $path })
    }
    return , $out.ToArray()
}

# Programa göre özet: Total, Rows (en çok kayıt olan önde; her satır: App, Count, Crashes, Hangs, Last, Path, Module, Code)
function Get-AppCrashSummary($Events, [int]$Top = 5) {
    $by = @{}
    $total = 0
    foreach ($e in @($Events)) {
        $app = ([string]$e.App).Trim().ToLowerInvariant()
        if ($app -eq '') { continue }
        $total++
        if (-not $by.ContainsKey($app)) { $by[$app] = @{ Crashes = 0; Hangs = 0; Last = [datetime]'2000-01-01'; Mods = @{}; Codes = @{}; Path = '' } }
        $r = $by[$app]
        if ([string]$e.Kind -eq 'hang') { $r.Hangs = [int]$r.Hangs + 1 } else { $r.Crashes = [int]$r.Crashes + 1 }
        if ($e.Time -gt $r.Last) {
            $r.Last = $e.Time
            if ([string]$e.Path -ne '') { $r.Path = [string]$e.Path }
        }
        $m = ([string]$e.Module).Trim().ToLowerInvariant()
        if ($m -ne '') { if ($r.Mods.ContainsKey($m)) { $r.Mods[$m] = [int]$r.Mods[$m] + 1 } else { $r.Mods[$m] = 1 } }
        $c = ([string]$e.Code).Trim().ToLowerInvariant()
        if ($c -ne '') { if ($r.Codes.ContainsKey($c)) { $r.Codes[$c] = [int]$r.Codes[$c] + 1 } else { $r.Codes[$c] = 1 } }
    }
    $rows = New-Object System.Collections.ArrayList
    foreach ($k in $by.Keys) {
        $r = $by[$k]
        [void]$rows.Add(@{ App = [string]$k; Count = ([int]$r.Crashes + [int]$r.Hangs); Crashes = [int]$r.Crashes; Hangs = [int]$r.Hangs; Last = $r.Last; Path = [string]$r.Path
            Module = (Get-CountTopKey $r.Mods); Code = (Get-CountTopKey $r.Codes) })
    }
    $sorted = @($rows | Sort-Object @{ Expression = { [int]$_.Count }; Descending = $true }, @{ Expression = { $_.Last }; Descending = $true }, @{ Expression = { [string]$_.App } })
    return @{ Total = $total; Rows = @($sorted | Select-Object -First $Top) }
}

# Çalışma zamanı kitaplıkları (Visual C++, DirectX); yükleyici hataları: DLL bulunamadı / başlatılamadı / geçersiz görüntü
$script:RuntimeModuleRx = '^(vcruntime|msvcp|msvcr|vcomp|concrt|mfc[0-9]|d3dx9|d3dx10|d3dx11|d3dcompiler|xinput1|xaudio2|x3daudio|xapofx)'
$script:GpuModuleRx = '^(nvwgf2um|nvd3dum|nvoglv|nvlddmkm|nvcuda|nvapi|atidxx|atiumd|amdxx|amdvlk|atio6axx|igd[0-9a-z]*umd|ig9icd|igc64)'
$script:SystemAppRx = '^(explorer|dwm|svchost|sihost|searchhost|searchapp|startmenuexperiencehost|shellexperiencehost|runtimebroker|taskhostw|ctfmon|textinputhost|lockapp|winlogon|csrss|services|lsass|fontdrvhost|wudfhost|dllhost|conhost|audiodg|spoolsv|msedgewebview2)\.exe$'

function Test-SystemAppRow($Row) {
    $app = [string]$Row.App
    if ($app -match $script:SystemAppRx) { return $true }
    $win = ([string]$env:WINDIR).ToLowerInvariant()
    $pth = ([string]$Row.Path).ToLowerInvariant()
    if ($win -ne '' -and $pth.StartsWith($win + '\') -and -not $pth.StartsWith($win + '\temp\')) { return $true }
    return $false
}

# Bir program satırı için tür, neden, atılacak adım ve eylem
function Get-AppCrashAdvice($Row) {
    $a = @{ Kind = 'generic'; Why = ''; Do = ''; Action = $null }
    $mod = [string]$Row.Module
    $code = [string]$Row.Code
    $app = [string]$Row.App
    $loader = ($code -eq 'c0000135' -or $code -eq 'c0000142' -or $code -eq 'c000007b')
    if ($loader -or ($mod -ne '' -and $mod -match $script:RuntimeModuleRx)) {
        $a.Kind = 'runtime'
        $a.Why = 'Program, eksik ya da bozuk bir çalışma zamanı kitaplığı (Visual C++, DirectX ya da benzeri) yüzünden açılamıyor veya çöküyor.'
        $a.Do = 'Microsoft’un sayfasından Visual C++ Yeniden Dağıtılabilir paketini (x64 ve x86) kurun ya da onarın; eski oyunlar için DirectX Son Kullanıcı Çalışma Zamanı da gerekebilir. Olmazsa programı kaldırıp yeniden kurun.'
        $a.Action = @{ Kind = 'Url'; Url = 'https://learn.microsoft.com/cpp/windows/latest-supported-vc-redist'; Label = 'Visual C++ paketini aç' }
    } elseif ($mod -ne '' -and $mod -match $script:GpuModuleRx) {
        $a.Kind = 'gpu'
        $a.Why = 'Çökme noktası ekran kartı sürücüsünde görünüyor.'
        $a.Do = 'Ekran kartı sürücüsünü üreticisinden indirip “temiz kurulum” seçeneğiyle yeniden kurun; aşırı hız ve oyun içi bindirmeleri (overlay) kapatıp deneyin.'
    } elseif ($app -match '^(powershell|pwsh)\.exe$') {
        $a.Kind = 'powershell'
        $a.Why = 'Bir PowerShell oturumu çökmüş. Multimizer de Windows PowerShell üzerinde çalıştığı için çöken oturum bu uygulamaya ait olabilir.'
        $a.Do = 'Çökme Multimizer çalışırken oluyorsa Ayarlar > Görünüm > Kararlılık bölümünden “Güvenli çizim (yalnızca yazılımla çiz)” seçeneğini açın. Aynı yerdeki “Ayrıntılı hata günlüğü” seçeneği sorunun izini Kayıtlar klasörüne yazar.'
        $a.Action = @{ Kind = 'Page'; Page = 'settings'; Label = 'Ayarları aç' }
    } elseif (Test-SystemAppRow $Row) {
        $a.Kind = 'system'
        $a.Why = 'Bir Windows bileşeni çöküyor. Bozulmuş sistem dosyaları, yarım kalmış bir güncelleme ya da uyumsuz bir sürücü bunun nedeni olabilir.'
        $a.Do = 'Araçlar > Onarım’da sistem dosyası denetimini (SFC) ve DISM onarımını çalıştırın. Sorun bir güncellemeden ya da sürücüden sonra başladıysa onu geri alın.'
        $a.Action = @{ Kind = 'Page'; Page = 'tools'; Label = 'Onarım' }
    } elseif ($code -eq 'e0434352') {
        $a.Kind = 'dotnet'
        $a.Why = 'Program, .NET tarafında yakalanmamış bir hatayla kapandı.'
        $a.Do = 'Programı en son sürüme güncelleyin. Windows Update’in .NET Framework güncellemelerini kurduğunu denetleyin; sürerse programı kaldırıp yeniden kurun.'
    } elseif ([int]$Row.Hangs -gt [int]$Row.Crashes) {
        $a.Kind = 'hang'
        $a.Why = 'Program sık sık yanıt vermeyi bırakıyor. Yavaş disk, bellek yetersizliği ya da programın bir eklentisi sık nedenlerdir.'
        $a.Do = 'Programın eklentilerini kapatıp deneyin, boş bellek ve disk alanına bakın, programı güncelleyin. Başlangıç sayfasından arka planda gereksiz çalışan programları kapatmak da yardımcı olur.'
    } else {
        $a.Why = 'Program tekrar tekrar kapanıyor. Çoğunlukla programın kendi hatası ya da bir eklentisi sorumludur.'
        $a.Do = 'Programı en son sürüme güncelleyin, eklentilerini kapatın, olmazsa kaldırıp yeniden kurun. Sürerse üreticiye bildirin.'
    }
    return $a
}

function Add-AppCrashFindings($Sum, [int]$Days) {
    $d = [string]$Days
    $rows = @($Sum.Rows)
    if ([int]$Sum.Total -eq 0 -or $rows.Count -eq 0) {
        Add-Finding 'app-crash' 'maint' 'ok' ('Son ' + $d + ' günde uygulama çökmesi yok') ''
        return
    }
    $top = $rows[0]
    if ([int]$top.Count -lt 2) {
        Add-Finding 'app-crash' 'maint' 'ok' ('Son ' + $d + ' günde belirgin uygulama çökmesi yok') ('Tek tük kayıt var (' + [string]$Sum.Total + ' olay); yinelenen bir sorun görünmüyor.')
        return
    }
    $adv = Get-AppCrashAdvice $top
    $what = New-Object System.Collections.ArrayList
    if ([int]$top.Crashes -gt 0) { [void]$what.Add([string]$top.Crashes + ' kez çöktü') }
    if ([int]$top.Hangs -gt 0) { [void]$what.Add([string]$top.Hangs + ' kez yanıt vermedi') }
    $title = '“' + [string]$top.App + '” son ' + $d + ' günde ' + ($what.ToArray() -join ' ve ')
    $parts = New-Object System.Collections.ArrayList
    [void]$parts.Add('Son kayıt: ' + $top.Last.ToString('dd.MM.yyyy HH:mm') + '.')
    if ([string]$top.Module -ne '') {
        $pt = [string]$top.Module
        if ([string]$top.Code -ne '') { $pt += ' (' + [string]$top.Code + ')' }
        [void]$parts.Add('Çökme noktası: ' + $pt + '.')
    }
    if ($rows.Count -gt 1) {
        $oth = New-Object System.Collections.ArrayList
        foreach ($r in @($rows | Select-Object -Skip 1 -First 3)) { [void]$oth.Add([string]$r.App + ' (' + [string]$r.Count + ')') }
        [void]$parts.Add('Diğer: ' + ($oth.ToArray() -join ', ') + '.')
    }
    [void]$parts.Add([string]$adv.Why)
    [void]$parts.Add([string]$adv.Do)
    $status = 'info'
    $w = 0
    if ([int]$top.Count -ge 5) { $status = 'warn'; $w = 3 }
    Add-Finding 'app-crash' 'maint' $status $title ($parts.ToArray() -join ' ') $adv.Action $w
}

function Chk_AppCrashes {
    $days = 30
    $ev = Get-AppCrashEvents $days
    $sum = Get-AppCrashSummary $ev
    Add-AppCrashFindings $sum $days
}

# ---------------- açılış süresi ----------------
# Microsoft-Windows-Diagnostics-Performance/Operational: 100 açılış süresi; 101 uygulama, 102 sürücü, 103 hizmet, 109 aygıt açılışı yavaşlattı
# Dönüş: @{ Boots = @(@{ Time; BootMs; MainMs; PostMs }); Slow = @(@{ Time; Id; Name; Friendly; TotalMs; DegradeMs }) }
function Get-BootEvents([int]$Days = 14) {
    $log = 'Microsoft-Windows-Diagnostics-Performance/Operational'
    $boots = New-Object System.Collections.ArrayList
    $slow = New-Object System.Collections.ArrayList
    $evs = @()
    try { $evs = @(Get-WinEvent -FilterHashtable @{ LogName = $log; Id = 100 } -MaxEvents 15 -ErrorAction Stop) } catch { $evs = @() }
    foreach ($e in $evs) {
        $m = Get-EventDataMap $e
        $bt = 0.0; $mp = 0.0; $pb = 0.0
        if ($m.ContainsKey('BootTime')) { $bt = ConvertTo-MsValue $m['BootTime'] }
        if ($m.ContainsKey('MainPathBootTime')) { $mp = ConvertTo-MsValue $m['MainPathBootTime'] }
        if ($m.ContainsKey('BootPostBootTime')) { $pb = ConvertTo-MsValue $m['BootPostBootTime'] }
        if ($bt -le 0 -and $mp -le 0) { continue }
        [void]$boots.Add(@{ Time = [datetime]$e.TimeCreated; BootMs = $bt; MainMs = $mp; PostMs = $pb })
    }
    $sv = @()
    try { $sv = @(Get-WinEvent -FilterHashtable @{ LogName = $log; Id = @(101, 102, 103, 109); StartTime = (Get-Date).AddDays(-$Days) } -MaxEvents 200 -ErrorAction Stop) } catch { $sv = @() }
    foreach ($e in $sv) {
        $m = Get-EventDataMap $e
        $nm = ''
        if ($m.ContainsKey('Name')) { $nm = [string]$m['Name'] }
        if ($nm -eq '') { try { if ($e.Properties.Count -gt 0) { $nm = [string]$e.Properties[0].Value } } catch { $nm = '' } }
        $fr = ''
        if ($m.ContainsKey('FriendlyName')) { $fr = [string]$m['FriendlyName'] }
        $tt = 0.0; $dg = 0.0
        if ($m.ContainsKey('TotalTime')) { $tt = ConvertTo-MsValue $m['TotalTime'] }
        if ($m.ContainsKey('DegradationTime')) { $dg = ConvertTo-MsValue $m['DegradationTime'] }
        [void]$slow.Add(@{ Time = [datetime]$e.TimeCreated; Id = [int]$e.Id; Name = $nm; Friendly = $fr; TotalMs = $tt; DegradeMs = $dg })
    }
    return @{ Boots = $boots.ToArray(); Slow = $slow.ToArray() }
}

# Özet: Count (açılış sayısı, en çok 10), Last (son açılış), MedianMain (ms), Slow (en çok yavaşlatan 3: Name, Id, Count, Max)
function Get-BootSummary($Boots, $Slow) {
    $b = @(@($Boots) | Sort-Object { $_.Time } -Descending | Select-Object -First 10)
    $slowRows = New-Object System.Collections.ArrayList
    $by = @{}
    foreach ($s in @($Slow)) {
        $nm = ([string]$s.Name).Trim()
        if ($nm -eq '') { continue }
        $key = $nm.ToLowerInvariant()
        if (-not $by.ContainsKey($key)) { $by[$key] = @{ Name = $nm; Id = [int]$s.Id; Count = 0; Max = 0.0 } }
        $by[$key].Count = [int]$by[$key].Count + 1
        if ([double]$s.DegradeMs -gt [double]$by[$key].Max) { $by[$key].Max = [double]$s.DegradeMs }
    }
    foreach ($k in $by.Keys) {
        if ([double]$by[$k].Max -lt 3000) { continue }
        [void]$slowRows.Add(@{ Name = [string]$by[$k].Name; Id = [int]$by[$k].Id; Count = [int]$by[$k].Count; Max = [double]$by[$k].Max })
    }
    $slowSorted = @($slowRows | Sort-Object @{ Expression = { [double]$_.Max }; Descending = $true } | Select-Object -First 3)
    if ($b.Count -eq 0) { return @{ Count = 0; Last = $null; MedianMain = 0.0; Slow = $slowSorted } }
    $mains = @($b | ForEach-Object { [double]$_.MainMs })
    return @{ Count = $b.Count; Last = $b[0]; MedianMain = (Get-NumMedian $mains); Slow = $slowSorted }
}

function Format-BootSeconds([double]$Ms) {
    return ([string][int][math]::Round($Ms / 1000.0))
}

function Get-BootSlowKindText([int]$Id) {
    if ($Id -eq 101) { return 'uygulama' }
    if ($Id -eq 102) { return 'sürücü' }
    if ($Id -eq 103) { return 'hizmet' }
    if ($Id -eq 109) { return 'aygıt' }
    return 'bileşen'
}

function Add-BootFindings($Sum, [string]$DiskType) {
    if ([int]$Sum.Count -eq 0 -or $null -eq $Sum.Last) { return }
    $hdd = ($DiskType -eq 'HDD')
    $okMs = 45000.0
    $warnMs = 90000.0
    if ($hdd) { $okMs = 90000.0; $warnMs = 150000.0 }
    $med = [double]$Sum.MedianMain
    $last = $Sum.Last
    $title = 'Açılış süresi: masaüstü ' + (Format-BootSeconds ([double]$last.MainMs)) + ' sn'
    if ([int]$Sum.Count -ge 3) { $title += ' (son ' + [string]$Sum.Count + ' açılışın ortancası ' + (Format-BootSeconds $med) + ' sn)' }
    $parts = New-Object System.Collections.ArrayList
    [void]$parts.Add('Son açılış toplam ' + (Format-BootSeconds ([double]$last.BootMs)) + ' sn sürdü: masaüstü ' + (Format-BootSeconds ([double]$last.MainMs)) + ' sn, arka plandaki açılış işleri ' + (Format-BootSeconds ([double]$last.PostMs)) + ' sn.')
    $slow = @($Sum.Slow)
    $hasApp = $false; $hasSvc = $false; $hasDrv = $false
    if ($slow.Count -gt 0) {
        $items = New-Object System.Collections.ArrayList
        foreach ($s in $slow) {
            [void]$items.Add([string]$s.Name + ' (' + (Get-BootSlowKindText ([int]$s.Id)) + ', +' + (Format-BootSeconds ([double]$s.Max)) + ' sn)')
            if ([int]$s.Id -eq 101) { $hasApp = $true } elseif ([int]$s.Id -eq 103) { $hasSvc = $true } elseif ([int]$s.Id -eq 102) { $hasDrv = $true }
        }
        [void]$parts.Add('Windows’un son 14 günde açılışı en çok yavaşlattığını kaydettikleri: ' + ($items.ToArray() -join ', ') + '.')
    }
    $status = 'ok'
    if ($med -gt $warnMs) { $status = 'warn' } elseif ($med -gt $okMs) { $status = 'info' }
    $act = $null
    if ($status -ne 'ok') {
        if ($hasApp) { [void]$parts.Add('Başlangıç sayfasından gerekmeyen programları kapatmak açılışı kısaltır.'); $act = @{ Kind = 'Page'; Page = 'startup'; Label = 'Başlangıç sayfası' } }
        if ($hasSvc) { [void]$parts.Add('Hizmetler sayfasında ilgili hizmetin başlangıç türünü gözden geçirebilirsiniz.'); if ($null -eq $act) { $act = @{ Kind = 'Page'; Page = 'services'; Label = 'Hizmetler sayfası' } } }
        if ($hasDrv) { [void]$parts.Add('Yavaşlatan sürücü için üreticisinin güncel sürümünü kurun.') }
        if ($slow.Count -eq 0) { [void]$parts.Add('Bu süre çoğunlukla bellenimin (BIOS/UEFI) başlatma süresine ve yüklü sürücü ile hizmet sayısına bağlıdır; BIOS’ta “Hızlı Önyükleme” (Fast Boot) seçeneğini de denetleyin.') }
    }
    $w = 0
    if ($status -eq 'warn') { $w = 2 }
    Add-Finding 'boot-time' 'perf' $status $title ($parts.ToArray() -join ' ') $act $w
}

function Chk_BootTime {
    $ev = Get-BootEvents 14
    $sum = Get-BootSummary $ev.Boots $ev.Slow
    $dt = ''
    try { $dt = [string]$sync.Profile.DiskType } catch { $dt = '' }
    Add-BootFindings $sum $dt
}
