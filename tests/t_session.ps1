. "$PSScriptRoot/lib.ps1"
# 7.2.1: oturum izi ve güvenli kip. Pencere açıldıktan sonra beklenmedik biçimde sona eren (0xC0000409 gibi) bir oturumun
# sonraki açılışta kanıtla anlaşılması: oturum.json (Durum), iz dosyası, çökme izinin saklanması, güvenli kip kararı.

Import-Fn 'Add-Trace', 'ConvertTo-RunToken', 'Test-SessionAlive', 'Get-SessionTail', 'Remove-OldCrashTraces', 'Start-SessionTrace',
    'Set-RenderMode', 'Set-SessionOpen', 'Write-SessionBeat', 'Stop-SessionTrace', 'Invoke-CliSafeRender', 'Initialize-SessionHooks',
    'Save-JsonFile', 'Read-JsonFile', 'ConvertTo-Hashtable', 'Load-StSafe', 'Save-StSafe', 'Set-DebugLogState', 'Initialize-DebugTables'
Import-Var 'TraceMax', 'TraceEnc'

$root = Join-Path ([System.IO.Path]::GetTempPath()) ('mm-sess-' + [guid]::NewGuid().ToString('N'))
$script:DataDir = Join-Path $root 'veri'
$script:LogDir = Join-Path $script:DataDir 'Kayitlar'
New-Item -ItemType Directory -Path $script:LogDir -Force | Out-Null
$script:AppVersion = '7.2.1'
$script:IsAdmin = $true
$script:SmokeMode = $false
$script:Quitting = $false
$script:UiState = @{ Page = 'panel' }
$script:Settings = @{ CrashStreak = 0; SafeRender = $false; MonGpu = $true }
$sync = [hashtable]::Synchronized(@{ MonBeat = $null; MonDiag = $null; DebugLog = $false })
$script:DebugLogArg = $false
$Oturum = ''
$Guvenli = $false
$Deger = ''

$script:CrashLines = New-Object System.Collections.ArrayList
function Write-CrashLog([string]$Text) { [void]$script:CrashLines.Add($Text) }
$script:Wh = New-Object System.Collections.ArrayList
function Write-WhLog { param([string]$Message, [string]$Level = 'INFO') [void]$script:Wh.Add($Level + '|' + $Message) }
$script:Toasts = New-Object System.Collections.ArrayList
function Show-Toast([string]$Text, [string]$Kind = 'info') { [void]$script:Toasts.Add($Text) }
function Set-SettingsKeys($Keys) { foreach ($k in @($Keys.Keys)) { $script:Settings[[string]$k] = $Keys[$k] } }

function Reset-Sess {
    $script:CrashLines.Clear(); $script:Wh.Clear(); $script:Toasts.Clear()
    Get-ChildItem -LiteralPath $script:DataDir -Recurse -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    $script:Settings = @{ CrashStreak = 0; SafeRender = $false; MonGpu = $true }
    $script:SafeRenderAuto = $false; $script:OpenMarker = ''; $script:SessBeatTimer = $null
    $script:TraceMax = 262144
    $sync.SafeMon = $null; $sync.NoGpu = $null
    $global:Guvenli = $false; $global:Oturum = ''
}
$sessFile = Join-Path $script:DataDir 'oturum.json'
$traceFile = Join-Path $script:LogDir 'oturum-iz.txt'

try {
    # ======================= 1) küçük yardımcılar =======================
    Assert-Eq (ConvertTo-RunToken 'abc123XYZ') 'abc123XYZ' 'geçerli kod'
    Assert-Eq (ConvertTo-RunToken '123456789012345') '123456789012345' 'Baslat.bat rakam kodu'
    Assert-Eq (ConvertTo-RunToken '../x') '' 'yol işaretleri reddedilir'
    Assert-Eq (ConvertTo-RunToken 'ab') '' 'çok kısa kod reddedilir'
    Assert-Eq (ConvertTo-RunToken ('a' * 40)) '' 'çok uzun kod reddedilir'
    Assert-Eq (ConvertTo-RunToken '') '' 'boş kod'

    # ======================= 2) normal oturum =======================
    Reset-Sess
    $script:SessFile = ''; $script:TraceFile = ''
    Start-SessionTrace
    Assert-True (Test-Path -LiteralPath $sessFile) 'oturum.json yazıldı'
    $j = ConvertTo-Hashtable (Read-JsonFile $sessFile)
    Assert-Eq $j.Durum 'acik' 'oturum açık yazılır'
    Assert-Eq ([int]$j.Pid) $PID 'süreç numarası'
    Assert-Eq $j.Surum '7.2.1' 'sürüm'
    Assert-True (-not $script:PrevCrashed) 'ilk açılış: önceki çökme yok'
    Assert-True (-not $script:SafeMode) 'ilk açılış: güvenli kip kapalı'
    Assert-True ($sync.SafeMon -eq $false) 'izleyiciye güvenli kip bilgisi verilir'
    Assert-True ($sync.NoGpu -eq $false) 'GPU ayarı açık'
    Assert-True (Test-Path -LiteralPath $traceFile) 'iz dosyası oluştu'
    $tl = @(Get-Content -LiteralPath $traceFile -Encoding UTF8)
    Assert-True ($tl.Count -ge 1 -and $tl[0] -like '*oturum başladı: sürüm 7.2.1*') 'ilk iz satırı oturum başlangıcı'
    $bytes = [System.IO.File]::ReadAllBytes($traceFile)
    Assert-True ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) 'iz dosyası UTF-8 (BOM)'
    Add-Trace 'sayfa: optimize'
    $tl = @(Get-Content -LiteralPath $traceFile -Encoding UTF8)
    Assert-True ($tl[$tl.Count - 1] -like '*sayfa: optimize') 'iz satırı eklenir'
    Assert-True ($tl[$tl.Count - 1] -match '^\d\d:\d\d:\d\d\.\d\d\d  ') 'satır saat damgalıdır'
    $script:Settings.CrashStreak = 1
    Stop-SessionTrace 'normal'
    $j = ConvertTo-Hashtable (Read-JsonFile $sessFile)
    Assert-Eq $j.Durum 'kapali' 'düzgün kapanışta durum kapalı'
    Assert-Eq $j.Neden 'normal' 'kapanış nedeni'
    Assert-Eq $script:Settings.CrashStreak 0 'düzgün kapanış art arda çökme sayacını sıfırlar'
    Stop-SessionTrace 'tekrar'
    $j = ConvertTo-Hashtable (Read-JsonFile $sessFile)
    Assert-Eq $j.Neden 'normal' 'kapanış iki kez yazılmaz'
    $tl = @(Get-Content -LiteralPath $traceFile -Encoding UTF8)
    Assert-True ($tl[$tl.Count - 1] -like '*oturum kapandı: normal') 'iz dosyasında kapanış satırı'

    # kapalı kayıttan sonraki açılış çökme sayılmaz
    $script:SessClosed = $false
    Start-SessionTrace
    Assert-True (-not $script:PrevCrashed) 'düzgün kapanmış oturumdan sonra çökme sayılmaz'
    Assert-Eq @($script:CrashLines).Count 0 'hata kaydına bir şey yazılmaz'

    # ======================= 3) beklenmedik bitiş =======================
    Reset-Sess
    $script:SessClosed = $false
    $old = @{ Durum = 'acik'; Pid = 2147480000; Basladi = ([DateTime]::UtcNow.AddMinutes(-33).ToString('o')); Surum = '7.2.0'; Guvenli = $false; Yonetici = $true; Kod = 'abc123' }
    Save-JsonFile $old $sessFile 3
    $enc = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText($traceFile, ("01:10:00.000  oturum başladı`r`n01:17:59.123  sayfa: network`r`n01:18:03.456  nabız: bellek=410MB özel=380MB tutamaç=900 parçacık=40`r`n01:18:24.001  iş basladi: ag (Job_LanScan)`r`n"), $enc)
    (Get-Item -LiteralPath $traceFile).LastWriteTime = [DateTime]::new(2026, 10, 19, 1, 18, 24)
    Start-SessionTrace
    Assert-True $script:PrevCrashed 'açık kalmış ve süreci olmayan oturum beklenmedik bitiş sayılır'
    Assert-True $script:SafeMode 'beklenmedik bitişten sonra güvenli kip'
    Assert-True ($sync.SafeMon -eq $true) 'izleyiciye güvenli kip bildirilir'
    Assert-Eq $script:Settings.CrashStreak 1 'art arda çökme sayacı 1'
    Assert-True (-not $script:Settings.SafeRender) 'tek çökmede güvenli çizim kalıcı yapılmaz'
    Assert-Eq $script:PrevCrashFile 'oturum-iz-cokme-20261019-011824.txt' 'çökme izi son yazım saatiyle saklanır'
    Assert-True (Test-Path -LiteralPath (Join-Path $script:LogDir $script:PrevCrashFile)) 'saklanan iz dosyası var'
    $kept = @(Get-Content -LiteralPath (Join-Path $script:LogDir $script:PrevCrashFile) -Encoding UTF8)
    Assert-True (($kept -join '|') -like '*sayfa: network*' -and ($kept -join '|') -like '*Job_LanScan*') 'saklanan iz çökmeden önceki olayları içerir'
    Assert-Eq @($script:CrashLines).Count 1 'hata kaydına tek özet yazılır'
    $cl = [string]$script:CrashLines[0]
    Assert-True ($cl -like '*beklenmedik biçimde sona erdi*PID 2147480000*7.2.0*') 'özet: süreç ve sürüm'
    Assert-True ($cl -like '*Son izler:*Job_LanScan*') 'özet: son izler'
    Assert-True ($cl -like '*oturum-iz-cokme-20261019-011824.txt*') 'özet: saklanan dosya adı'
    $tl = @(Get-Content -LiteralPath $traceFile -Encoding UTF8)
    Assert-True ($tl[0] -like '*oturum başladı*' -and -not (($tl -join '|') -like '*Job_LanScan*')) 'yeni oturumun izi temiz başlar'
    Assert-True (($tl -join '|') -like '*önceki oturum beklenmedik bitmişti (art arda 1)*') 'yeni iz önceki çökmeyi not eder'

    # ikinci çökme: güvenli çizim kalıcı olur
    $script:SessClosed = $false
    $old.Basladi = ([DateTime]::UtcNow.AddMinutes(-3).ToString('o'))
    Save-JsonFile $old $sessFile 3
    Start-SessionTrace
    Assert-Eq $script:Settings.CrashStreak 2 'art arda ikinci çökme'
    Assert-True ($script:Settings.SafeRender -eq $true) 'üst üste iki çökmede güvenli çizim kalıcı olur'
    Assert-True $script:SafeRenderAuto 'kalıcı yapılma otomatik diye işaretlenir'
    # ayar kalıcıyken çökme olmasa da güvenli kip sürer
    $script:SessClosed = $false
    Stop-SessionTrace 'normal'
    $script:SessClosed = $false
    Start-SessionTrace
    Assert-True ((-not $script:PrevCrashed) -and $script:SafeMode) 'kalıcı güvenli çizim çökme olmadan da güvenli kip verir'

    # ======================= 4) süreci hâlâ çalışan oturum =======================
    Reset-Sess
    $script:SessClosed = $false
    $proc = Start-Process -FilePath 'sleep' -ArgumentList '30' -PassThru
    try {
        Start-Sleep -Milliseconds 400
        $liveRec = @{ Durum = 'acik'; Pid = $proc.Id; Basladi = $proc.StartTime.ToUniversalTime().ToString('o'); Surum = '7.2.1' }
        Assert-True (Test-SessionAlive $liveRec) 'çalışan süreç canlı sayılır'
        $stale = @{ Durum = 'acik'; Pid = $proc.Id; Basladi = $proc.StartTime.ToUniversalTime().AddHours(-2).ToString('o'); Surum = '7.2.1' }
        Assert-True (-not (Test-SessionAlive $stale)) 'süreç numarası yeniden kullanılmışsa (başlangıç saati farklı) canlı sayılmaz'
        Assert-True (-not (Test-SessionAlive @{ Pid = $PID; Basladi = ([DateTime]::UtcNow.ToString('o')) })) 'kendi süreci önceki oturum sayılmaz'
        Assert-True (-not (Test-SessionAlive @{ Pid = 0; Basladi = '' })) 'geçersiz kayıt'
        Save-JsonFile $liveRec $sessFile 3
        Start-SessionTrace
        Assert-True (-not $script:PrevCrashed) 'önceki oturum hâlâ çalışıyorsa çökme sayılmaz'
    } finally { try { $proc.Kill() } catch { } }

    # ======================= 5) -Guvenli anahtarı =======================
    Reset-Sess
    $script:SessClosed = $false
    $global:Guvenli = $true
    Start-SessionTrace
    Assert-True ($script:SafeMode -and -not $script:PrevCrashed) '-Guvenli çökme olmadan da güvenli kip verir'
    $global:Guvenli = $false
    # GPU ayarı kapalı
    Reset-Sess
    $script:SessClosed = $false
    $script:Settings.MonGpu = $false
    Start-SessionTrace
    Assert-True ($sync.NoGpu -eq $true) 'GPU izleme ayarı kapalıysa izleyiciye bildirilir'

    # ======================= 6) işaret dosyası ve nabız =======================
    Reset-Sess
    $script:SessClosed = $false
    $global:Oturum = 'abc123def'
    Start-SessionTrace
    Assert-Eq $script:RunToken 'abc123def' 'Baslat.bat kodu alınır'
    Set-SessionOpen
    $mk = Join-Path $script:DataDir 'oturum-acik-abc123def.txt'
    Assert-True (Test-Path -LiteralPath $mk) 'pencere açılınca işaret dosyası yazılır'
    $tl = @(Get-Content -LiteralPath $traceFile -Encoding UTF8)
    Assert-True (($tl -join '|') -like '*pencere açıldı*') 'iz: pencere açıldı'
    Assert-True (($tl -join '|') -match 'nabız: bellek=\d+MB özel=\d+MB tutamaç=\d+ parçacık=\d+ yönetilen=\d+MB izleme=-?\d+sn') 'iz: nabız satırı bellek / tutamaç / parçacık içerir'
    Stop-SessionTrace 'normal'
    Assert-True (-not (Test-Path -LiteralPath $mk)) 'düzgün kapanışta işaret dosyası silinir'
    # kod yoksa işaret dosyası yazılmaz; duman kipinde de yazılmaz
    Reset-Sess
    $script:SessClosed = $false
    Start-SessionTrace; Set-SessionOpen
    Assert-Eq @(Get-ChildItem -LiteralPath $script:DataDir -Filter 'oturum-acik-*' -File -ErrorAction SilentlyContinue).Count 0 'kod verilmediyse işaret dosyası yok'
    Reset-Sess
    $script:SessClosed = $false
    $global:Oturum = 'abc123def'; $script:SmokeMode = $true
    Start-SessionTrace; Set-SessionOpen
    Assert-Eq @(Get-ChildItem -LiteralPath $script:DataDir -Filter 'oturum-acik-*' -File -ErrorAction SilentlyContinue).Count 0 'duman kipinde işaret dosyası yazılmaz'
    $script:SmokeMode = $false
    # çökmeden sonra açılışta kullanıcıya bilgi verilir
    Reset-Sess
    $script:SessClosed = $false
    Save-JsonFile @{ Durum = 'acik'; Pid = 2147480000; Basladi = ([DateTime]::UtcNow.AddMinutes(-9).ToString('o')); Surum = '7.2.0' } $sessFile 3
    Start-SessionTrace
    Set-SessionOpen
    Assert-True ((($script:Wh -join '|') -like '*güvenli kipte*') -and $script:Toasts.Count -ge 1) 'çökmeden sonra açılışta günlük satırı ve bildirim'
    Stop-SessionTrace 'normal'

    # ======================= 7) iz dosyası sınırı ve eski çökme izleri =======================
    Reset-Sess
    $script:SessClosed = $false
    Start-SessionTrace
    $script:TraceMax = $script:TraceBytes + 400
    for ($i = 0; $i -lt 50; $i++) { Add-Trace ('dolgu satırı ' + $i + ' ' + ('x' * 30)) }
    $sizeNow = (Get-Item -LiteralPath $traceFile).Length
    for ($i = 0; $i -lt 20; $i++) { Add-Trace 'sınırdan sonra' }
    Assert-Eq (Get-Item -LiteralPath $traceFile).Length $sizeNow 'sınır dolunca dosya büyümez'
    $all = @(Get-Content -LiteralPath $traceFile -Encoding UTF8)
    Assert-Eq @($all | Where-Object { $_ -like '*sınırına ulaştı*' }).Count 1 'sınır uyarısı tek kez yazılır'
    $script:TraceMax = 262144
    Add-Trace ('u' * 900)
    Reset-Sess
    for ($i = 1; $i -le 8; $i++) {
        $f = Join-Path $script:LogDir ('oturum-iz-cokme-2026101' + $i + '-000000.txt')
        'x' | Set-Content -LiteralPath $f
        (Get-Item -LiteralPath $f).LastWriteTime = [DateTime]::new(2026, 10, 10 + $i, 0, 0, 0)
    }
    Remove-OldCrashTraces
    $left = @(Get-ChildItem -LiteralPath $script:LogDir -Filter 'oturum-iz-cokme-*.txt' -File)
    Assert-Eq $left.Count 5 'yalnızca en yeni 5 çökme izi tutulur'
    Assert-True (@($left | Where-Object { $_.Name -like '*20261011*' }).Count -eq 0) 'en eskiler silinir'
    Assert-Eq @(Get-SessionTail (Join-Path $script:LogDir 'yok.txt') 5).Count 0 'olmayan dosyanın sonu boş'

    # ======================= 8) iz yazımı hata vermez =======================
    $script:TraceFile = Join-Path $root 'olmayan-klasor/alt/iz.txt'
    Add-Trace 'yazılamaz'
    Assert-True $true 'yazılamayan iz dosyası hata fırlatmaz'
    $script:TraceFile = ''
    Add-Trace 'dosya yok'
    Assert-True $true 'iz dosyası yolu boşken hata fırlatmaz'

    # ======================= 9) komut satırı: GuvenliCizim =======================
    Reset-Sess
    $global:Deger = 'Durum'
    Assert-Eq (Invoke-CliSafeRender) 0 'Durum çıkış kodu'
    Assert-True (($script:Wh -join '|') -like '*Güvenli çizim: kapalı*') 'Durum: kapalı'
    $global:Deger = 'Ac'
    [void](Invoke-CliSafeRender)
    Assert-True ($script:Settings.SafeRender -eq $true) 'Ac: ayar açılır'
    $script:Settings.CrashStreak = 3
    $global:Deger = 'Kapat'
    [void](Invoke-CliSafeRender)
    Assert-True ($script:Settings.SafeRender -eq $false -and $script:Settings.CrashStreak -eq 0) 'Kapat: ayar kapanır, çökme sayacı sıfırlanır'
    $global:Deger = ''

    # ======================= 9b) Ayarlar > Görünüm > Kararlılık anahtarları =======================
    # Uygulama "güvenli çizim kalıcı yapıldı, Ayarlar > Görünüm bölümünden kapatabilirsiniz" der; anahtar gerçekten var ve çalışır.
    Reset-Sess
    $ui = @{ st_SafeRender = [pscustomobject]@{ IsChecked = $false }; st_MonGpu = [pscustomobject]@{ IsChecked = $false }; st_DebugLog = [pscustomobject]@{ IsChecked = $true } }
    $script:Settings = @{ CrashStreak = 0; SafeRender = $true }
    Load-StSafe
    Assert-True ($ui.st_SafeRender.IsChecked -eq $true) 'Ayarlar: güvenli çizim açıksa kutu işaretli'
    Assert-True ($ui.st_MonGpu.IsChecked -eq $true) 'Ayarlar: MonGpu kayıtta yoksa varsayılan açık'
    Assert-True ($ui.st_DebugLog.IsChecked -eq $false) 'Ayarlar: ayrıntılı hata günlüğü kayıtta yoksa kapalı'
    $script:Settings = @{ CrashStreak = 0; SafeRender = $false; MonGpu = $false }
    Load-StSafe
    Assert-True ($ui.st_SafeRender.IsChecked -eq $false -and $ui.st_MonGpu.IsChecked -eq $false) 'Ayarlar: kapalı değerler kutulara yansır'

    # güvenli çizim açılır: ayar yazılır, bildirim çıkar, çökme sayacına dokunulmaz
    Reset-Sess
    $script:Settings.CrashStreak = 1
    $ui.st_SafeRender.IsChecked = $true; $ui.st_MonGpu.IsChecked = $true
    Save-StSafe
    Assert-True ($script:Settings.SafeRender -eq $true -and $script:Settings.MonGpu -eq $true) 'Ayarlar: güvenli çizim açıldı'
    Assert-Eq $script:Settings.CrashStreak 1 'Ayarlar: açarken çökme sayacı korunur'
    Assert-Eq $script:Toasts.Count 1 'Ayarlar: açılınca tek bildirim'
    Assert-True ($script:Toasts[0] -like '*bir sonraki açılışta etkin*') 'Ayarlar: bildirim sonraki açılışı söyler'

    # başka bir ayara tıklamak (durum değişmedi) bildirim üretmez ve çökme sayacını bozmaz
    $script:Toasts.Clear()
    Save-StSafe
    Assert-Eq $script:Toasts.Count 0 'Ayarlar: durum değişmediyse bildirim yok'
    Assert-Eq $script:Settings.CrashStreak 1 'Ayarlar: değişmeyen kayıtta çökme sayacı korunur'

    # güvenli çizim kapatılır: sayaç sıfırlanır
    $script:Settings.CrashStreak = 2
    $ui.st_SafeRender.IsChecked = $false
    Save-StSafe
    Assert-True ($script:Settings.SafeRender -eq $false) 'Ayarlar: güvenli çizim kapandı'
    Assert-Eq $script:Settings.CrashStreak 0 'Ayarlar: elle kapatınca çökme sayacı sıfırlanır'
    Assert-True ($script:Toasts.Count -eq 1 -and $script:Toasts[0] -like '*ekran kartıyla çizilir*') 'Ayarlar: kapatınca bildirim'

    # ekran kartı izleme anında etkin olur (izleme iş parçacığı $sync.NoGpu okur)
    $ui.st_MonGpu.IsChecked = $false
    Save-StSafe
    Assert-True ($script:Settings.MonGpu -eq $false -and $sync.NoGpu -eq $true) 'Ayarlar: GPU izleme kapatılınca NoGpu anında açılır'
    $ui.st_MonGpu.IsChecked = $true
    Save-StSafe
    Assert-True ($script:Settings.MonGpu -eq $true -and $sync.NoGpu -eq $false) 'Ayarlar: GPU izleme açılınca NoGpu kapanır'

    # ayrıntılı hata günlüğü: anahtar ayarı yazar ve çalışma durumunu anında değiştirir; -DebugLog ile açılan oturumda anahtar kapansa da günlük açık kalır
    $script:Toasts.Clear()
    $ui.st_DebugLog.IsChecked = $true
    Save-StSafe
    Assert-True ($script:Settings.DebugLog -eq $true -and $sync.DebugLog -eq $true) 'Ayarlar: ayrıntılı hata günlüğü açılınca durum anında açılır'
    Assert-True ($script:Toasts.Count -eq 1 -and $script:Toasts[0] -like '*Ayrıntılı hata günlüğü açıldı*') 'Ayarlar: açılınca bildirim'
    $script:Toasts.Clear()
    Save-StSafe
    Assert-Eq $script:Toasts.Count 0 'Ayarlar: ayrıntılı hata günlüğü değişmediyse bildirim yok'
    $ui.st_DebugLog.IsChecked = $false
    Save-StSafe
    Assert-True ($script:Settings.DebugLog -eq $false -and $sync.DebugLog -eq $false) 'Ayarlar: ayrıntılı hata günlüğü kapanınca durum kapanır'
    $script:DebugLogArg = $true
    $ui.st_DebugLog.IsChecked = $true; Save-StSafe
    $ui.st_DebugLog.IsChecked = $false; Save-StSafe
    Assert-True ($script:Settings.DebugLog -eq $false -and $sync.DebugLog -eq $true) 'Ayarlar: -DebugLog ile açılan oturumda anahtar kapansa da günlük açık kalır'
    $script:DebugLogArg = $false
    Set-DebugLogState $false
    $script:Settings = @{ CrashStreak = 0; SafeRender = $false; MonGpu = $true; DebugLog = $true }
    Load-StSafe
    Assert-True ($ui.st_DebugLog.IsChecked -eq $true) 'Ayarlar: kayıtlı ayrıntılı hata günlüğü kutuya yansır'
    Remove-Variable ui

    # ======================= 10) derlenmiş betikte bağlantılar =======================
    $src = Get-Content -LiteralPath $env:MM_BUILD -Raw
    $gui = $src.Substring($src.IndexOf('function Invoke-GuiMode {'))
    $gui = $gui.Substring(0, $gui.IndexOf('# ------------------------------------------------------------------' + "`r`n" + '#  Baslangic'))
    Assert-True ($gui.IndexOf('Start-SessionTrace') -lt $gui.IndexOf('Invoke-BootGuard')) 'oturum izi önyükleme korumasından önce başlar'
    Assert-True ($gui.IndexOf('Set-RenderMode') -lt $gui.IndexOf('New-MainWindow')) 'çizim kipi ilk pencere oluşmadan ayarlanır'
    Assert-True ($gui.Contains('Initialize-SessionHooks')) 'pencere olayları iz bırakır'
    Assert-True ($gui.Contains('Set-SessionOpen')) 'pencere açılınca işaret dosyası yazılır'
    Assert-True ($gui.Contains("Stop-SessionTrace 'windows-oturumu-kapaniyor'")) 'Windows oturumu kapanırken çökme sayılmasın'
    Assert-True ($gui.IndexOf('Stop-AllWork') -lt $gui.IndexOf('Stop-SessionTrace $sessWhy')) 'düzgün kapanış kaydı iş parçacıkları durduktan sonra yazılır'
    Assert-True ($src -match '\[string\]\$Oturum = ''''' -and $src -match '\[switch\]\$Guvenli') 'betik -Oturum ve -Guvenli parametrelerini tanır'
    Assert-True ($src.Contains("if ($Guvenli) { [void]`$parts.Add('-Guvenli') }") -or $src.Contains("[void]`$parts.Add('-Guvenli')")) 'yeniden başlatma -Guvenli parametresini aktarır'
    Assert-True ($src.Contains("[void]`$parts.Add('-Deger')")) 'yeniden başlatma -Deger parametresini aktarır (eskiden kayboluyordu)'
    Assert-True ($src.Contains("'guvenlicizim' { `$code = Invoke-CliSafeRender }")) 'komut satırı: GuvenliCizim'
    Assert-True ($src.Contains('CrashStreak  = 0') -and $src.Contains('SafeRender   = $false') -and $src.Contains('MonGpu       = $true')) 'yeni ayar anahtarları varsayılanlarda'
    Assert-True ($src.Contains("Add-Trace ('sayfa: ' + `$Key)")) 'sayfa geçişleri iz bırakır'
    Assert-True ($src.Contains("Add-Trace ('is basladi: '") -and $src.Contains("Add-Trace ('is bitti: '")) 'işler iz bırakır'
    Assert-Eq ([regex]::Matches($src, '<CheckBox x:Name="st_SafeRender"')).Count 1 'Ayarlar sayfasında güvenli çizim anahtarı tek'
    Assert-Eq ([regex]::Matches($src, '<CheckBox x:Name="st_MonGpu"')).Count 1 'Ayarlar sayfasında GPU izleme anahtarı tek'
    Assert-True ($src -match "(?s)foreach \(\`$n in @\([^)]*'st_SafeRender', 'st_MonGpu'[^)]*\)\) \{\s*\`$ui\[\`$n\]\.Add_Click\(\`$script:H_StLookChanged\)") 'iki anahtar tıklama olayına bağlı (ortak Görünüm olay işleyicisi)'
    Assert-True ($src.Contains("`$script:StLookParts = @('Look', 'Design', 'Glass', 'Safe')") -and $src.Contains("`$fn = 'Load-St' + `$p") -and $src.Contains("`$fn = 'Save-St' + `$p")) 'güvenli çizim ve GPU izleme yükleme ve kaydetme zincirinde (Safe bölümü)'
    Assert-True ($src.Contains('function Load-StSafe') -and $src.Contains('function Save-StSafe')) 'Safe bölümünün yükle ve kaydet işlevleri var'
} finally {
    try { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue } catch { }
}
Show-Result
