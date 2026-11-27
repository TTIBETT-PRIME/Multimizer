<#
    Tani.ps1  -  Multimizer baslatma tanilamasi
    Baslat.bat, Multimizer acilmazsa bunu kendiliginden calistirir. Yalnizca OKUR; hicbir ayari ya da dosyayi degistirmez.
    Amac: "neden acilmadi?" sorusunu tahmin yerine kayda dayanarak yanitlamak (ozellikle Windows Defender engelinde
    Defender'in verdigi tehdit adini gostermek). Sonuc ekrana yazilir ve %TEMP%\Multimizer-Tani.txt dosyasina kaydedilir.
    Kullanim:  powershell -NoProfile -ExecutionPolicy Bypass -File Tani.ps1 [-ExitCode 1] [-Mod Gui|Komut|Elle] [-Gizli]
      -Gizli: konsol penceresi yok (Acilis.ps1 gizli baslatmada cagirir); rapor renkli, kopyalanabilir bir pencerede gosterilir.
              Pencere kurulamazsa rapor konsola yazilir.
      Gui   : arayuz acilmadi; her sey yazilir (varsayilan).
      Komut : -Cli / -OzTest calistirmasi bitti; yalnizca Defender engeli ya da dosya sorunu bulunursa yazilir.
      Elle  : Baslat.bat /tani ile elle calistirildi; her sey yazilir.
    Cikis kodu: 0 = bir sey yazilmadi, 10 = rapor yazildi.
    Uygulamanin cikis kodlari: 4 = ana pencere acilamadi, 5 = gorunum hatasi nedeniyle kendini kapatti (ikisinde de bir sonraki
    acilis guvenli gorunumle olur; elle sifirlama: Baslat.bat -Cli -Gorev GorunumSifirla).
    Negatif cikis kodu (ornek -1073740791 = 0xC0000409) Windows'un verdigi bir cokme kodudur: bolum 3b uygulamanin oturum izini
    (Kayitlar\oturum-iz.txt, oturum.json) okuyarak cokmenin pencere acildiktan sonra mi oldugunu ve son olaylari gosterir.
#>
param([int]$ExitCode = 0, [ValidateSet('Gui', 'Komut', 'Elle')][string]$Mod = 'Gui', [switch]$Sessiz, [switch]$Gizli)
$ErrorActionPreference = 'SilentlyContinue'
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ps1 = Join-Path $dir 'Multimizer.ps1'
$lines = New-Object System.Collections.ArrayList
$colors = New-Object System.Collections.ArrayList

# Satirlar once tampona yazilir; Komut kipinde bir sey bulunmazsa hic gosterilmez.
function Say([string]$Text, [string]$Color = 'Gray') {
    [void]$lines.Add($Text)
    [void]$colors.Add($Color)
}

function Test-IsAdmin {
    try { return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) } catch { return $false }
}

# Cikis kodunu (isaretli 32 bit) Windows durum koduna cevirir
function Get-StatusText([int]$Code) {
    $u = [uint32]([BitConverter]::ToUInt32([BitConverter]::GetBytes($Code), 0))
    $hex = '0x' + $u.ToString('X8')
    switch ($u) {
        3221225477 { return $hex + ' (STATUS_ACCESS_VIOLATION: gecersiz bellek erisimi)' }
        3221226505 { return $hex + ' (STATUS_STACK_BUFFER_OVERRUN: hizli sonlandirma; bozuk bellek ya da yigin tamponu algilandi)' }
        3221225725 { return $hex + ' (STATUS_STACK_OVERFLOW: yigin tasmasi)' }
        3762504530 { return $hex + ' (.NET: yakalanmamis istisna)' }
        2148734499 { return $hex + ' (.NET: FailFast)' }
        3221225786 { return $hex + ' (STATUS_CONTROL_C_EXIT: konsol penceresi kapatildi ya da Ctrl+C)' }
        default { return $hex }
    }
}

Say ''
Say '=== MULTIMIZER BASLATMA TANILAMASI ===' 'Cyan'
Say ('Tarih          : ' + (Get-Date -Format 'dd.MM.yyyy HH:mm:ss'))
Say ('Cikis kodu     : ' + $ExitCode)
Say ('Klasor         : ' + $dir)
$os = Get-CimInstance -ClassName Win32_OperatingSystem
if ($null -ne $os) { Say ('Windows        : ' + [string]$os.Caption + ' (derleme ' + [string]$os.BuildNumber + ')') }
Say ('PowerShell     : ' + $PSVersionTable.PSVersion.ToString())
$isAdmin = Test-IsAdmin
if ($isAdmin) { Say 'Yonetici       : evet' } else { Say 'Yonetici       : HAYIR (Defender kayitlarini okumak icin Baslat.bat dosyasina sag tik > Yonetici olarak calistir)' 'Yellow' }
Say ''

# ---------------- 1) dosyalar ----------------
Say '1) Dosyalar' 'Cyan'
$problems = New-Object System.Collections.ArrayList
if (-not (Test-Path -LiteralPath $ps1)) {
    Say '   Multimizer.ps1 bulunamadi. ZIP dosyasinin tamamini bir klasore cikartin.' 'Red'
    [void]$problems.Add('betik yok')
} else {
    $fi = Get-Item -LiteralPath $ps1 -Force
    Say ('   Multimizer.ps1 : ' + [string]([math]::Round($fi.Length / 1MB, 2)) + ' MB')
    foreach ($sub in @('veri', 'Eklenti')) {
        $p = Join-Path $dir $sub
        if (Test-Path -LiteralPath $p -PathType Container) {
            Say ('   ' + $sub + '\ klasoru : ' + [string]@(Get-ChildItem -LiteralPath $p -File).Count + ' dosya')
        } else {
            Say ('   ' + $sub + '\ klasoru YOK (uygulama acilir ama ilgili ozellikler calismaz). ZIP dosyasinin tamamini cikartin.') 'Yellow'
        }
    }
    if ($dir -match 'OneDrive') { Say '   Not: klasor OneDrive icinde. Sorun surerse klasoru C:\Multimizer gibi yerel bir yere tasiyin.' 'Yellow' }
    $zone = $null
    try { $zone = Get-Content -LiteralPath $ps1 -Stream Zone.Identifier -ErrorAction Stop } catch { }
    if ($null -ne $zone) { Say '   Not: dosya internetten indirilmis olarak isaretli (Zone.Identifier). Guvendiginiz bir kaynaksa Ozellikler > Engellemeyi kaldir.' 'Yellow' }
    # soz dizimi: yalnizca okur (betigi calistirmaz)
    $tok = $null; $err = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($ps1, [ref]$tok, [ref]$err)
    if ($null -ne $err -and @($err).Count -gt 0) {
        Say ('   Soz dizimi hatasi: ' + [string]@($err).Count + ' (ilki: ' + [string]@($err)[0].Message + ' / satir ' + [string]@($err)[0].Extent.StartLineNumber + ')') 'Red'
        [void]$problems.Add('soz dizimi')
    } else { Say '   Soz dizimi: temiz' 'Green' }
}
Say ''

# ---------------- 2) guvenlik yazilimi ----------------
Say '2) Guvenlik yazilimi' 'Cyan'
$av = @(Get-CimInstance -Namespace 'root/SecurityCenter2' -ClassName AntivirusProduct | ForEach-Object { [string]$_.displayName })
if ($av.Count -gt 0) { Say ('   Kayitli antivirus : ' + ($av -join ', ')) }
$mp = Get-MpComputerStatus
if ($null -ne $mp) {
    Say ('   Defender gercek zamanli koruma : ' + [string]$mp.RealTimeProtectionEnabled + '   imza surumu: ' + [string]$mp.AntivirusSignatureVersion)
}
$found = New-Object System.Collections.ArrayList
$since = (Get-Date).AddHours(-6)
try {
    foreach ($d in @(Get-MpThreatDetection | Where-Object { $_.InitialDetectionTime -ge $since } | Sort-Object InitialDetectionTime -Descending | Select-Object -First 8)) {
        $name = ''
        try { $name = [string](Get-MpThreat -ThreatID $d.ThreatID).ThreatName } catch { }
        $res = (@($d.Resources) -join '; ')
        [void]$found.Add(@{ Time = $d.InitialDetectionTime; Name = $name; Res = $res })
    }
} catch { }
if ($found.Count -eq 0) {
    # Defender olay kaydi (yedek yol): 1116 = tehdit bulundu
    try {
        foreach ($e in @(Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-Windows Defender/Operational'; Id = 1116; StartTime = $since } -MaxEvents 8)) {
            $msg = [string]$e.Message
            $n = ''; $p = ''
            foreach ($l in ($msg -split "`r?`n")) {
                $t = $l.Trim()
                if ($t -match '^(Name|Ad)\s*:\s*(.+)$') { $n = $Matches[2] }
                if ($t -match '^(Path|Yol)\s*:\s*(.+)$') { $p = $Matches[2] }
            }
            [void]$found.Add(@{ Time = $e.TimeCreated; Name = $n; Res = $p })
        }
    } catch { }
}
$mine = @($found | Where-Object { ([string]$_.Res) -match 'Multimizer|amsi' })
if ($found.Count -eq 0) {
    Say '   Son 6 saatte Defender tehdit kaydi bulunamadi (ya da okunamadi).' 'Gray'
} else {
    Say ('   Son 6 saatteki Defender kayitlari: ' + [string]$found.Count) 'Yellow'
    foreach ($f in $found) { Say ('     ' + ([string]$f.Time) + '  ' + [string]$f.Name + '  ->  ' + [string]$f.Res) 'Yellow' }
}
Say ''

# ---------------- 3) uygulamanin kendi hata kaydi ----------------
Say '3) Uygulamanin hata kaydi' 'Cyan'
$recentErr = $false
$logDir = Join-Path (Join-Path $env:ProgramData 'Multimizer') 'Kayitlar'
$lastErr = $null
try { $lastErr = @(Get-ChildItem -LiteralPath $logDir -Filter 'hata-*.txt' -File | Sort-Object LastWriteTime -Descending | Select-Object -First 1)[0] } catch { }
if ($null -eq $lastErr) {
    Say '   Hata kaydi (hata-*.txt) yok: uygulama bir cokme ya da gorunum hatasi yazmamis.' 'Gray'
} else {
    Say ('   En son hata dosyasi : ' + [string]$lastErr.FullName + '  (' + [string][math]::Round($lastErr.Length / 1KB, 1) + ' KB, ' + $lastErr.LastWriteTime.ToString('dd.MM.yyyy HH:mm') + ')')
    $tail = @()
    try { $tail = @(Get-Content -LiteralPath $lastErr.FullName -Tail 6 -Encoding UTF8) } catch { }
    foreach ($tl in $tail) {
        $t2 = ([string]$tl).Trim()
        if ($t2.Length -gt 200) { $t2 = $t2.Substring(0, 200) + '...' }
        if ($t2.Length -gt 0) { Say ('     ' + $t2) 'Yellow' }
    }
    if ($lastErr.LastWriteTime -ge (Get-Date).AddHours(-6)) { $recentErr = $true }
}
Say ''

# ---------------- 3b) oturum izi ----------------
Say '3b) Oturum izi (uygulama calisirken kapandiysa)' 'Cyan'
$crashed = $false
$sessFile = Join-Path (Join-Path $env:ProgramData 'Multimizer') 'oturum.json'
$traceFile = Join-Path $logDir 'oturum-iz.txt'
$sess = $null
try { if (Test-Path -LiteralPath $sessFile) { $sess = Get-Content -LiteralPath $sessFile -Raw -Encoding UTF8 | ConvertFrom-Json } } catch { }
if ($null -eq $sess) {
    Say '   Oturum kaydi (oturum.json) yok: uygulama bu surumde henuz bir pencere acmamis.' 'Gray'
} else {
    Say ('   Son oturum         : durum=' + [string]$sess.Durum + '  PID=' + [string]$sess.Pid + '  surum=' + [string]$sess.Surum + '  guvenli kip=' + [string]$sess.Guvenli)
    if ([string]$sess.Durum -eq 'acik') {
        $alive = $null
        try { $alive = Get-Process -Id ([int]$sess.Pid) -ErrorAction Stop } catch { }
        if ($null -ne $alive -and [string]$alive.ProcessName -match 'powershell|pwsh') {
            Say '   Uygulama su anda calisiyor.' 'Green'
        } else {
            $crashed = $true
            Say '   Oturum "acik" kalmis ve sureci yok: uygulama pencere acildiktan sonra beklenmedik sekilde sona ermis.' 'Red'
        }
    } else {
        Say ('   Son oturum duzgun kapanmis (' + [string]$sess.Neden + ').') 'Green'
    }
}
$tf = $null
if ($crashed -and (Test-Path -LiteralPath $traceFile)) { $tf = $traceFile }
else {
    try {
        $cf = @(Get-ChildItem -LiteralPath $logDir -Filter 'oturum-iz-cokme-*.txt' -File | Sort-Object LastWriteTime -Descending | Select-Object -First 1)
        if ($cf.Count -gt 0) { $tf = [string]$cf[0].FullName }
    } catch { }
}
if ($null -ne $tf) {
    $tfWhen = ''
    $tfOld = $false
    try {
        $tfi = Get-Item -LiteralPath $tf -ErrorAction Stop
        $tfWhen = '  (' + $tfi.LastWriteTime.ToString('dd.MM.yyyy HH:mm') + ')'
        if (-not $crashed -and ((Get-Date) - $tfi.LastWriteTime).TotalHours -gt 6) { $tfOld = $true }
    } catch { }
    Say ('   Iz dosyasi         : ' + $tf + $tfWhen)
    if ($tfOld) { Say '   Not: bu iz eski bir beklenmedik kapanmaya aittir; son oturum duzgun kapandiysa simdiki bir sorun degildir.' 'Yellow' }
    $all = @()
    try { $all = @(Get-Content -LiteralPath $tf -Encoding UTF8) } catch { }
    $from = [math]::Max(0, $all.Count - 14)
    for ($i = $from; $i -lt $all.Count; $i++) {
        $t3 = ([string]$all[$i]).Trim()
        if ($t3.Length -gt 220) { $t3 = $t3.Substring(0, 220) + '...' }
        if ($t3.Length -gt 0) { Say ('     ' + $t3) 'Yellow' }
    }
    $beats = @($all | Where-Object { ([string]$_) -match 'bellek=\d+MB' })
    if ($beats.Count -ge 2) {
        $b1 = [string]$beats[0]; $b2 = [string]$beats[$beats.Count - 1]
        $m1 = [regex]::Match($b1, 'bellek=(\d+)MB'); $m2 = [regex]::Match($b2, 'bellek=(\d+)MB')
        $h1 = [regex]::Match($b1, 'tutama.=(\d+)'); $h2 = [regex]::Match($b2, 'tutama.=(\d+)')
        if ($m1.Success -and $m2.Success) { Say ('   Bellek (ilk -> son nabiz) : ' + $m1.Groups[1].Value + ' MB -> ' + $m2.Groups[1].Value + ' MB') }
        if ($h1.Success -and $h2.Success) { Say ('   Tutamac (ilk -> son nabiz): ' + $h1.Groups[1].Value + ' -> ' + $h2.Groups[1].Value) }
    }
}
$wer = $null
try { $wer = (Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting' -Name Disabled -ErrorAction Stop).Disabled } catch { }
if ($wer -eq 1) { Say '   Not: Windows hata raporlamasi (WER) bu bilgisayarda kapali; cokmeler Olay Goruntuleyicisi''ne yazilmaz. Multimizer bu yuzden kendi oturum izini tutar.' 'Yellow' }
Say ''

# ---------------- 4) sonuc ----------------
Say '4) Sonuc' 'Cyan'
$interesting = $false
if ($mine.Count -gt 0) {
    $interesting = $true
    $nm = [string]$mine[0].Name
    Say ('   Windows Defender betigi ZARARLI saydi ve engelledi: ' + $nm) 'Red'
    Say '   Bu, yonetici izniyle ilgili degil; Defender dosyanin icerigini yanlis tanimis olabilir (yanlis pozitif).' 'Red'
    Say ''
    Say '   Yapabilecekleriniz:' 'White'
    Say '   a) Windows Guvenligi > Virus ve tehdit korumasi > Koruma gecmisi: kaydi acin; tehdit adini ve ayrintiyi bana iletin.'
    Say '   b) Dosyaya guveniyorsaniz ayni ekranda Eylemler > "Cihazda izin ver".'
    Say '   c) Yanlis tespiti Microsoft''a bildirin: https://www.microsoft.com/wdsi/filesubmission (Multimizer.ps1 dosyasini yukleyin).'
    Say '   d) Gecici cozum: yalnizca bu klasoru dislamaya ekleyin (Ayarlar > Dislamalar > Klasor). Korumanin tamamini KAPATMAYIN.'
} elseif ($problems.Count -gt 0) {
    $interesting = $true
    Say ('   Sorun: ' + ($problems -join ', ') + '. Yukaridaki ayrintilara bakin.') 'Red'
} elseif ($crashed -or ($Mod -eq 'Gui' -and $ExitCode -lt 0 -and $ExitCode -ne -1073741510)) {
    $interesting = $true
    Say ('   Multimizer beklenmedik sekilde kapandi. Cikis kodu: ' + (Get-StatusText $ExitCode)) 'Red'
    if ($crashed) { Say '   Pencere acilmisti; bu nedenle dosya, izin ya da Defender sorunu degil, calisma sirasinda olusan bir cokmedir.' 'White' }
    else { Say '   Oturum kaydi pencerenin acildigini gostermiyor; cokme acilis sirasinda olmus olabilir.' 'White' }
    Say '   Bir sonraki acilis kendiliginden guvenli kipte olur (yazilimsal cizim; GPU ve sicaklik izleme kapali).' 'White'
    Say '   Iz dosyasi ve hata kaydi (yukarida) kok nedeni bulmak icin saklandi; bu raporu sohbete yapistirabilirsiniz.' 'White'
    Say '   Guvenli kipi elle ac / kapat:   Baslat.bat -Cli -Gorev GuvenliCizim -Deger Ac     (Kapat)' 'White'
} elseif ($Mod -eq 'Gui' -and $ExitCode -eq -1073741510) {
    $interesting = $true
    Say '   Konsol penceresi kapatildigi icin uygulama sonlandi (hata degil).' 'Gray'
} elseif ($ExitCode -eq 4 -or $ExitCode -eq 5) {
    $interesting = $true
    if ($ExitCode -eq 4) { Say '   Ana pencere acilamadi (cikis kodu 4). Ayrinti yukaridaki hata kaydinda.' 'Red' }
    else { Say '   Uygulama, gorunumle ilgili tekrarlayan bir hata nedeniyle kendini kapatti (cikis kodu 5).' 'Red' }
    Say '   Bir sonraki acilis varsayilan (Neon) gorunumle ve mini izleyici kapali olarak baslar.' 'White'
    Say '   Yine de acilmazsa gorunumu elle sifirlayin:   Baslat.bat -Cli -Gorev GorunumSifirla' 'White'
} elseif ($Mod -eq 'Komut') {
    Say '   Dosya ya da Defender kaynakli bir sorun bulunamadi.' 'Gray'
} elseif ($ExitCode -eq 0) {
    Say '   Belirgin bir sorun bulunamadi: dosyalar tam, soz dizimi temiz, Defender kaydi yok.' 'Green'
    if (-not $isAdmin) { Say '   (Yonetici olarak calistirilmadigi icin Defender kayitlari eksik okunmus olabilir.)' 'Yellow' }
} else {
    $cause = New-Object System.Collections.ArrayList
    if (-not $isAdmin) { [void]$cause.Add('yonetici izni verilmemis olabilir (UAC penceresi Hayir ile kapatilmis)') }
    $pol = @(Get-ExecutionPolicy -List | Where-Object { ($_.Scope -eq 'MachinePolicy' -or $_.Scope -eq 'UserPolicy') -and @('Restricted', 'AllSigned', 'RemoteSigned') -contains [string]$_.ExecutionPolicy })
    if ($pol.Count -gt 0) { [void]$cause.Add('betik calistirma ilkesi grup ilkesiyle ayarlanmis (' + (($pol | ForEach-Object { [string]$_.Scope + '=' + [string]$_.ExecutionPolicy }) -join ', ') + ')') }
    if ($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') { [void]$cause.Add('PowerShell Kisitli Dil Modu acik (AppLocker / WDAC)') }
    if ($cause.Count -gt 0) {
        Say '   Olasi nedenler:' 'Yellow'
        foreach ($c in $cause) { Say ('   - ' + $c) 'Yellow' }
    } else {
        Say '   Bu tanilamada belirgin bir neden bulunamadi. Baslat.bat penceresinde gorunen kirmizi hata metnini bana iletin.' 'Yellow'
    }
    if ($recentErr) { Say '   Son 6 saatte uygulamanin hata kaydi yazilmis (yukaridaki 3. bolum).' 'Yellow' }
    Say '   Gorunum kaynakli olabilir: Baslat.bat -Cli -Gorev GorunumSifirla  (tema Neon, mini izleyici kapali; sistem ayarlarina dokunmaz).' 'Yellow'
}
Say ''

# ---------------- cikti ----------------
if ($Mod -eq 'Komut' -and -not $interesting) { exit 0 }
$report = Join-Path $env:TEMP 'Multimizer-Tani.txt'
try { [System.IO.File]::WriteAllText($report, (($lines.ToArray()) -join "`r`n"), (New-Object System.Text.UTF8Encoding($true))) } catch { }
if (Test-Path -LiteralPath $report) {
    Say ('Rapor kaydedildi: ' + $report) 'Gray'
    try { Set-Clipboard -Value (($lines.ToArray()) -join "`r`n"); Say 'Rapor panoya kopyalandi; sohbete yapistirabilirsiniz.' 'Gray' } catch { }
}
# Uygulama konsol penceresini gizlemis ya da kucultmus olabilir: rapor gorunsun. Hizli duzenleme (uygulama sirasinda kapatilir)
# yeniden acilir; boylece rapordaki metin secilip kopyalanabilir.
function Show-ThisConsole {
    try {
        Add-Type -Namespace WH -Name TaniWin -ErrorAction Stop -MemberDefinition '[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow(); [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n); [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h); [DllImport("kernel32.dll")] public static extern IntPtr GetStdHandle(int n); [DllImport("kernel32.dll")] public static extern bool GetConsoleMode(IntPtr h, out uint m); [DllImport("kernel32.dll")] public static extern bool SetConsoleMode(IntPtr h, uint m);'
        $w = [WH.TaniWin]::GetConsoleWindow()
        if ($w -ne [IntPtr]::Zero) { [void][WH.TaniWin]::ShowWindow($w, 9); [void][WH.TaniWin]::SetForegroundWindow($w) }
        $h = [WH.TaniWin]::GetStdHandle(-10)
        $m = [uint32]0
        if ([WH.TaniWin]::GetConsoleMode($h, [ref]$m)) { [void][WH.TaniWin]::SetConsoleMode($h, [uint32]($m -bor 0xC0)) }
    } catch { }
}
# Gizli baslatma: rapor bir pencerede gosterilir (renkli, kopyalanabilir). Pencere kurulamazsa $false doner ve rapor konsola yazilir.
function Show-ReportWindow {
    try {
        Add-Type -AssemblyName System.Windows.Forms, System.Drawing -ErrorAction Stop
        [System.Windows.Forms.Application]::EnableVisualStyles()
        $trk = ($PSUICulture -like 'tr*')
        if ($trk) { $title = 'Multimizer baslatma tanilamasi'; $bCopy = 'Raporu kopyala'; $bOpen = 'Rapor dosyasini ac'; $bClose = 'Kapat'; $okMsg = 'Rapor panoya kopyalandi.' }
        else { $title = 'Multimizer startup diagnostics'; $bCopy = 'Copy report'; $bOpen = 'Open report file'; $bClose = 'Close'; $okMsg = 'Report copied to the clipboard.' }
        $map = @{ Cyan = '#22D3EE'; Red = '#F87171'; Yellow = '#FBBF24'; Green = '#4ADE80'; White = '#F8FAFC'; Gray = '#94A3B8' }
        $form = New-Object System.Windows.Forms.Form
        $form.Text = $title
        $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
        $form.ClientSize = New-Object System.Drawing.Size(920, 620)
        $form.MinimumSize = New-Object System.Drawing.Size(640, 400)
        $form.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#0F172A')
        $form.TopMost = $true
        $rtb = New-Object System.Windows.Forms.RichTextBox
        $rtb.Dock = [System.Windows.Forms.DockStyle]::Fill
        $rtb.ReadOnly = $true
        $rtb.BorderStyle = [System.Windows.Forms.BorderStyle]::None
        $rtb.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#0F172A')
        $rtb.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#CBD5E1')
        $rtb.Font = New-Object System.Drawing.Font('Consolas', 10)
        $rtb.WordWrap = $true
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $hex = [string]$map[[string]$colors[$i]]
            if ($hex -eq '') { $hex = '#CBD5E1' }
            $rtb.SelectionStart = $rtb.TextLength
            $rtb.SelectionColor = [System.Drawing.ColorTranslator]::FromHtml($hex)
            $rtb.AppendText([string]$lines[$i] + "`r`n")
        }
        $rtb.SelectionStart = 0
        $bar = New-Object System.Windows.Forms.FlowLayoutPanel
        $bar.Dock = [System.Windows.Forms.DockStyle]::Bottom
        $bar.Height = 52
        $bar.FlowDirection = [System.Windows.Forms.FlowDirection]::RightToLeft
        $bar.Padding = New-Object System.Windows.Forms.Padding(10, 10, 10, 6)
        $bar.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#111C33')
        $mk = {
            param([string]$Text)
            $b = New-Object System.Windows.Forms.Button
            $b.Text = $Text
            $b.AutoSize = $true
            $b.Padding = New-Object System.Windows.Forms.Padding(10, 3, 10, 3)
            $b.FlatStyle = [System.Windows.Forms.FlatStyle]::System
            return $b
        }
        $btnClose = & $mk $bClose
        $btnOpen = & $mk $bOpen
        $btnCopy = & $mk $bCopy
        $btnClose.Add_Click({ $form.Close() })
        $btnOpen.Add_Click({ try { Start-Process -FilePath 'notepad.exe' -ArgumentList ('"' + $report + '"') } catch { } })
        $btnCopy.Add_Click({ try { [System.Windows.Forms.Clipboard]::SetText(($lines.ToArray()) -join "`r`n"); $btnCopy.Text = $okMsg } catch { } })
        $bar.Controls.Add($btnClose)
        $bar.Controls.Add($btnOpen)
        $bar.Controls.Add($btnCopy)
        $form.Controls.Add($rtb)
        $form.Controls.Add($bar)
        $form.AcceptButton = $btnClose
        [void]$form.ShowDialog()
        return $true
    } catch { return $false }
}

if (-not $Sessiz) {
    $shown = $false
    if ($Gizli) { $shown = [bool](Show-ReportWindow) }
    if (-not $shown) {
        Show-ThisConsole
        for ($i = 0; $i -lt $lines.Count; $i++) { Write-Host ([string]$lines[$i]) -ForegroundColor ([string]$colors[$i]) }
    }
}
exit 10
