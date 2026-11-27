# ==================================================================
#  ÇÖZÜM MERKEZİ: "Hazırlık" denetimi ve kurulumu (çekirdek)
#  Multimizer’ın ve kullandığı araçların ihtiyaç duyduğu bileşenleri okur (yalnızca okuma) ve eksik olanların kurulmasını sağlar.
#  Kurulum yalnızca kullanıcı onaylarsa, yalnızca aşağıdaki izin listesindeki Microsoft paketleri için ve winget’in kendi paket özeti
#  (SHA-256) doğrulamasıyla yapılır. Bu bölüm çekirdekte durur çünkü denetim ve kurulum arka plan çalışma alanında çalışır;
#  sekmenin çizimi 127_solve_prep.ps1 içindedir.
# ==================================================================

# Eklenti adları (açılış kendi kendini sınama ve Hazırlık sekmesi aynı listeyi kullanır)
$script:MmExtNames = @('Sifreleme', 'Bellek', 'GuvenliSilme', 'WifiAktar', 'DiskKoruma', 'Kurtarma', 'DiskSilme')

# Kurulabilecek paketler: winget kimliği -> görünen ad. Başka kimlik hiçbir koşulda kurulmaz.
$script:PrepPackages = @{
    'Microsoft.VCRedist.2015+.x64'      = 'Visual C++ 2015-2022 çalışma zamanı (x64)'
    'Microsoft.VCRedist.2015+.x86'      = 'Visual C++ 2015-2022 çalışma zamanı (x86)'
    'Microsoft.VCRedist.2015+.arm64'    = 'Visual C++ 2015-2022 çalışma zamanı (ARM64)'
    'Microsoft.DirectX'                 = 'DirectX eski çalışma zamanı (D3DX9, XAudio, XInput)'
    'Microsoft.DotNet.DesktopRuntime.10' = '.NET 10 Masaüstü Çalışma Zamanı'
}

# '' = bu paket kurulabilir, aksi hâlde nedeni
function Test-PrepPackage([string]$Id) {
    if ($Id -cnotmatch '^[A-Za-z0-9][A-Za-z0-9\.\-_\+]*$') { return ('Geçersiz paket kimliği: ' + $Id) }
    if (-not $script:PrepPackages.ContainsKey($Id)) { return ($Id + ' izin listesinde değil; kurulmadı.') }
    return ''
}

# winget çıkış kodu -> sonuç. Ok: paket artık kurulu; Reboot: yeniden başlatma gerekiyor; Text: kısa açıklama
function Get-PrepWingetResult([int]$Code) {
    $r = @{ Ok = $false; Reboot = $false; Already = $false; Text = '' }
    switch ($Code) {
        0 { $r.Ok = $true; $r.Text = 'kuruldu' }
        3010 { $r.Ok = $true; $r.Reboot = $true; $r.Text = 'kuruldu, yeniden başlatma gerekiyor' }
        1641 { $r.Ok = $true; $r.Reboot = $true; $r.Text = 'kuruldu, yeniden başlatma gerekiyor' }
        -1978335189 { $r.Ok = $true; $r.Already = $true; $r.Text = 'zaten kurulu' }
        -1978335135 { $r.Ok = $true; $r.Already = $true; $r.Text = 'zaten kurulu' }
        -1978334963 { $r.Ok = $true; $r.Already = $true; $r.Text = 'zaten kurulu' }
        -1978335153 { $r.Ok = $true; $r.Already = $true; $r.Text = 'zaten kurulu' }
        -1978334967 { $r.Ok = $true; $r.Reboot = $true; $r.Text = 'kuruldu, yeniden başlatma gerekiyor' }
        -1978334965 { $r.Ok = $true; $r.Reboot = $true; $r.Text = 'kuruldu, yeniden başlatılıyor' }
        -1978334966 { $r.Reboot = $true; $r.Text = 'önce bilgisayarı yeniden başlatın, sonra yeniden deneyin' }
        -1978335212 { $r.Text = 'winget deposunda bulunamadı' }
        -1978335209 { $r.Text = 'winget deposunda bulunamadı' }
        -1978335179 { $r.Text = 'winget deposunda bulunamadı' }
        -1978335216 { $r.Text = 'bu bilgisayara uygun kurulum paketi yok' }
        -1978334957 { $r.Text = 'bu sistem desteklenmiyor' }
        -1978335215 { $r.Text = 'indirilen dosyanın özeti paketle uyuşmadı; güvenliğiniz için kurulmadı' }
        default { $r.Text = 'winget çıkış kodu ' + [string]$Code }
    }
    return $r
}

# .NET Framework Release anahtarı -> sürüm adı ('' = 4.5’ten eski ya da bilinmiyor)
function Get-PrepNetName([int]$Release) {
    if ($Release -ge 533320) { return '4.8.1' }
    if ($Release -ge 528040) { return '4.8' }
    if ($Release -ge 461808) { return '4.7.2' }
    if ($Release -ge 461308) { return '4.7.1' }
    if ($Release -ge 460798) { return '4.7' }
    if ($Release -ge 394802) { return '4.6.2' }
    if ($Release -ge 394254) { return '4.6.1' }
    if ($Release -ge 393295) { return '4.6' }
    if ($Release -ge 379893) { return '4.5.2' }
    if ($Release -ge 378675) { return '4.5.1' }
    if ($Release -ge 378389) { return '4.5' }
    return ''
}

# Visual C++ 2015-2022 yeniden dağıtılabilir paketi (kayıt defterinden). Arch: x64 | x86 | arm64
function Get-PrepVcRuntime([string]$Arch) {
    $r = @{ Arch = $Arch; Installed = $false; Version = ''; Major = 0; Minor = 0; Build = 0 }
    $paths = @()
    if ($Arch -eq 'x64') { $paths = @('HKLM\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64') }
    elseif ($Arch -eq 'x86') { $paths = @('HKLM\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\x86', 'HKLM\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x86') }
    elseif ($Arch -eq 'arm64') { $paths = @('HKLM\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\ARM64') }
    foreach ($p in $paths) {
        $inst = Get-RegValue $p 'Installed' $null
        if ($null -ne $inst -and [int]$inst -eq 1) {
            $r.Installed = $true
            $r.Version = [string](Get-RegValue $p 'Version' '')
            $r.Major = [int](Get-RegValue $p 'Major' 0)
            $r.Minor = [int](Get-RegValue $p 'Minor' 0)
            $r.Build = [int](Get-RegValue $p 'Bld' 0)
            break
        }
    }
    return $r
}

# Kurulu .NET (Core) Masaüstü Çalışma Zamanı sürümleri (kayıt defterinden); dizi döner, "$x = Get-PrepDotnetDesktop" ile alın
function Get-PrepDotnetDesktop {
    $vers = New-Object System.Collections.ArrayList
    foreach ($key in @('HKLM:\SOFTWARE\dotnet\Setup\InstalledVersions\x64\sharedfx\Microsoft.WindowsDesktop.App', 'HKLM:\SOFTWARE\dotnet\Setup\InstalledVersions\arm64\sharedfx\Microsoft.WindowsDesktop.App', 'HKLM:\SOFTWARE\dotnet\Setup\InstalledVersions\x86\sharedfx\Microsoft.WindowsDesktop.App', 'HKLM:\SOFTWARE\WOW6432Node\dotnet\Setup\InstalledVersions\x86\sharedfx\Microsoft.WindowsDesktop.App')) {
        try {
            $p = Get-ItemProperty -LiteralPath $key -ErrorAction Stop
            foreach ($pr in $p.PSObject.Properties) {
                if ($pr.Name -match '^\d+\.\d+\.\d+' -and -not $vers.Contains([string]$pr.Name)) { [void]$vers.Add([string]$pr.Name) }
            }
        } catch { }
    }
    return , $vers.ToArray()
}

# Eski DirectX çalışma zamanı (D3DX9): x64 ve x86 kopyaları
function Get-PrepDirectX {
    $r = @{ Native = $false; X86 = $false; Is64 = [Environment]::Is64BitOperatingSystem }
    $w = [string]$env:SystemRoot
    if ($w -eq '') { return $r }
    $r.Native = [bool](Test-Path -LiteralPath (Join-Path $w 'System32\d3dx9_43.dll') -PathType Leaf)
    if ($r.Is64) { $r.X86 = [bool](Test-Path -LiteralPath (Join-Path $w 'SysWOW64\d3dx9_43.dll') -PathType Leaf) } else { $r.X86 = $r.Native }
    return $r
}

# C# derleyicisi (Add-Type buna dayanır; kurtarma ve silme motorları derlenir)
function Get-PrepCsc {
    $r = @{ Found = $false; Path = '' }
    $w = [string]$env:SystemRoot
    if ($w -eq '') { return $r }
    foreach ($c in @((Join-Path $w 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'), (Join-Path $w 'Microsoft.NET\Framework\v4.0.30319\csc.exe'))) {
        if (Test-Path -LiteralPath $c -PathType Leaf) { $r.Found = $true; $r.Path = $c; break }
    }
    return $r
}

function Get-PrepSysDrive {
    $r = @{ Letter = ''; FreeGB = [double]0; SizeGB = [double]0 }
    try {
        $sd = [string]$env:SystemDrive
        if ($sd -eq '') { $sd = 'C:' }
        $di = New-Object System.IO.DriveInfo($sd)
        $r.Letter = $sd
        $r.FreeGB = [math]::Round([double]$di.AvailableFreeSpace / 1GB, 1)
        $r.SizeGB = [math]::Round([double]$di.TotalSize / 1GB, 1)
    } catch { }
    return $r
}

function Test-PrepWmi {
    try {
        $o = @(Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop)
        if ($o.Count -gt 0) { return @{ Ok = $true; Error = '' } }
        return @{ Ok = $false; Error = 'Sorgu sonuç döndürmedi.' }
    } catch { return @{ Ok = $false; Error = [string]$_.Exception.Message } }
}

# Klasöre yazılabiliyor mu? Denemek için kendi küçük geçici dosyasını yazıp siler.
function Test-PrepWritable([string]$Dir) {
    if ([string]::IsNullOrEmpty($Dir)) { return @{ Ok = $false; Error = 'Klasör bilinmiyor.' } }
    try {
        if (-not (Test-Path -LiteralPath $Dir)) { New-Item -ItemType Directory -Path $Dir -Force -ErrorAction Stop | Out-Null }
        $f = Join-Path $Dir ('yazma-denemesi-' + [guid]::NewGuid().ToString('N') + '.tmp')
        [System.IO.File]::WriteAllText($f, 'x')
        Remove-Item -LiteralPath $f -Force -ErrorAction Stop
        return @{ Ok = $true; Error = '' }
    } catch { return @{ Ok = $false; Error = [string]$_.Exception.Message } }
}

# Sistem Koruması (geri yükleme noktaları) sistem sürücüsünde açık mı? Known = $false: okunamadı.
function Get-PrepProtect([string]$Drive) {
    $r = @{ Known = $false; On = $false; Policy = $false }
    try {
        $dis = Get-RegValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows NT\SystemRestore' 'DisableSR' $null
        if ($null -ne $dis -and [int]$dis -eq 1) { $r.Known = $true; $r.Policy = $true; return $r }
        $v = Get-RegValue 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SPP\Clients' '{09F7EDC5-294E-4180-AF6A-FB0E6A0E9513}' $null
        $r.Known = $true
        if ($null -ne $v -and $Drive -cmatch '^([A-Za-z]):') {
            $tag = '(' + $Matches[1].ToUpperInvariant() + '%3A)'
            foreach ($x in @($v)) { if (([string]$x).ToUpperInvariant().Contains($tag)) { $r.On = $true } }
        }
    } catch { $r.Known = $false }
    return $r
}

# Bilgisayarı okur (yalnızca okuma). Her bölüm ayrı korunur; bir okuma başarısız olursa o bölüm boş kalır.
# NoNet: internet bağlantısı sınanmaz (ağa hiç çıkılmaz); Online boş kalır ve bağlantı satırı gösterilmez.
function Get-PrepState([bool]$NoNet = $false) {
    $admin = $false
    try { $admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) } catch { }
    $S = @{ Ok = $true; At = (Get-Date).ToString('dd.MM.yyyy HH:mm'); Admin = $admin
        Ps = @{ Version = ''; Major = 0; Minor = 0; Edition = '' }
        Os = @{ Name = ''; Build = 0; Display = ''; Is64 = [Environment]::Is64BitOperatingSystem; Arm = $false }
        Net = @{ Release = 0; Name = '' }
        Csc = @{ Found = $false; Path = '' }
        Vc = @{ X64 = $null; X86 = $null; Arm64 = $null }
        Dx = $null; Dotnet = @()
        Winget = @{ Path = ''; Version = '' }
        Wmi = @{ Ok = $true; Error = '' }
        Disk = @{ Letter = ''; FreeGB = [double]0; SizeGB = [double]0 }
        Online = $null
        Data = @{ Path = ''; Ok = $true; Error = '' }
        Exts = @()
        Protect = @{ Known = $false; On = $false; Policy = $false } }

    try {
        $pv = $PSVersionTable.PSVersion
        $S.Ps.Version = [string]$pv
        $S.Ps.Major = [int]$pv.Major
        $S.Ps.Minor = [int]$pv.Minor
        $S.Ps.Edition = [string]$PSVersionTable.PSEdition
    } catch { }
    try {
        $k = 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
        $S.Os.Build = [int](Get-RegValue $k 'CurrentBuildNumber' 0)
        $S.Os.Display = [string](Get-RegValue $k 'DisplayVersion' '')
        if ($S.Os.Build -ge 22000) { $S.Os.Name = 'Windows 11' } elseif ($S.Os.Build -gt 0) { $S.Os.Name = 'Windows 10' }
        $arch = [string]$env:PROCESSOR_ARCHITEW6432
        if ($arch -eq '') { $arch = [string]$env:PROCESSOR_ARCHITECTURE }
        $S.Os.Arm = ($arch -match '^ARM')
    } catch { }
    try {
        $S.Net.Release = [int](Get-RegValue 'HKLM\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' 'Release' 0)
        $S.Net.Name = Get-PrepNetName $S.Net.Release
    } catch { }
    try { $S.Csc = Get-PrepCsc } catch { }
    try {
        $S.Vc.X64 = Get-PrepVcRuntime 'x64'
        $S.Vc.X86 = Get-PrepVcRuntime 'x86'
        if ($S.Os.Arm) { $S.Vc.Arm64 = Get-PrepVcRuntime 'arm64' }
    } catch { }
    try { $S.Dx = Get-PrepDirectX } catch { }
    try { $S.Dotnet = Get-PrepDotnetDesktop } catch { }
    try {
        $wg = Get-WingetPath
        $S.Winget.Path = [string]$wg
        if ($wg -ne '') {
            $o = @(& $wg '--version' 2>&1 | ForEach-Object { [string]$_ })
            if ($o.Count -gt 0) { $S.Winget.Version = ([string]$o[0]).Trim() }
        }
    } catch { }
    try { $S.Wmi = Test-PrepWmi } catch { }
    try { $S.Disk = Get-PrepSysDrive } catch { }
    if (-not $NoNet) { try { $S.Online = [bool](Test-Online) } catch { } }
    try {
        $dd = ''
        try { $dd = [string]$sync.DataDir } catch { }
        $S.Data.Path = $dd
        $w = Test-PrepWritable $dd
        $S.Data.Ok = [bool]$w.Ok
        $S.Data.Error = [string]$w.Error
    } catch { }
    try {
        $ex = New-Object System.Collections.ArrayList
        foreach ($n in @($script:MmExtNames)) { [void]$ex.Add(@{ Name = [string]$n; Problem = [string](Get-ExtProblem ([string]$n)) }) }
        $S.Exts = $ex.ToArray()
    } catch { }
    try { $S.Protect = Get-PrepProtect ([string]$S.Disk.Letter) } catch { }
    return $S
}

function Job_PrepCheck($P) {
    try {
        $nn = $false
        try { if ($null -ne $P -and $P.ContainsKey('NoNet')) { $nn = ($P['NoNet'] -eq $true) } } catch { }
        if ($nn) { Write-WhLog 'Hazırlık denetimi yapılıyor (yalnızca okuma; ağa çıkılmaz)...' 'INFO' }
        else { Write-WhLog 'Hazırlık denetimi yapılıyor (yalnızca okuma)...' 'INFO' }
        return @{ Ok = $true; State = (Get-PrepState $nn) }
    } catch {
        Write-WhLog ('Hazırlık denetimi yapılamadı: ' + $_.Exception.Message) 'ERR'
        return @{ Ok = $false; Error = $_.Exception.Message }
    }
}

# ---------------- yorumlama (saf mantık) ----------------
function New-PrepItem([string]$Key, [string]$Group, [string]$Status, [string]$Title, [string]$Detail, $Fix = $null) {
    return @{ Key = $Key; Group = $Group; Status = $Status; Title = $Title; Detail = $Detail; Fix = $Fix }
}

function New-PrepFix([string]$Do, [string]$Label, $Extra = $null) {
    $f = @{ Do = $Do; Label = $Label }
    if ($null -ne $Extra) { foreach ($k in @($Extra.Keys)) { $f[$k] = $Extra[$k] } }
    return $f
}

# Visual C++ satırı: yüklü değil ya da eski ise kurulum düğmesi
function Get-PrepVcItem($Vc, [string]$Arch, [string]$Id, [string]$Label) {
    $title = 'Visual C++ çalışma zamanı (' + $Label + ')'
    $fix = New-PrepFix 'Winget' 'Kur' @{ Id = $Id; Name = [string]$script:PrepPackages[$Id] }
    if ($null -eq $Vc -or $Vc.Installed -ne $true) {
        return (New-PrepItem ('vc' + $Arch) 'rec' 'warn' $title 'Yüklü değil. Birçok program ve Multimizer’ın kurduğu bazı araçlar bu paketi ister; yoksa “VCRUNTIME140.dll bulunamadı” gibi hatalar çıkar.' $fix)
    }
    $ver = [string]$Vc.Version
    if ($ver -eq '') { $ver = [string]$Vc.Major + '.' + [string]$Vc.Minor }
    if ([int]$Vc.Major -eq 14 -and [int]$Vc.Minor -lt 30) {
        return (New-PrepItem ('vc' + $Arch) 'rec' 'warn' $title ('Eski sürüm kurulu (' + $ver + '). Yeni programlar 2019 sonrası sürümü ister; güncelleyin.') $fix)
    }
    return (New-PrepItem ('vc' + $Arch) 'rec' 'ok' $title ('Kurulu (' + $ver + ').'))
}

# Tarama sonucundan satırlar: @( @{ Key; Group (req | rec | opt); Status (ok | info | warn | bad); Title; Detail; Fix } ).
# Fix: $null ya da @{ Do = Winget | Url | Page | Wmi; Label; ... }
function Get-PrepItems($S, [bool]$Expert = $false) {
    $n = New-Object System.Collections.ArrayList
    $os64 = ($S.Os.Is64 -eq $true)

    # ---- zorunlu
    $psv = [string]$S.Ps.Version
    if ($psv -eq '') { $psv = [string]$S.Ps.Major + '.' + [string]$S.Ps.Minor }
    if ([int]$S.Ps.Major -gt 5 -or ([int]$S.Ps.Major -eq 5 -and [int]$S.Ps.Minor -ge 1)) {
        [void]$n.Add((New-PrepItem 'ps' 'req' 'ok' 'Windows PowerShell 5.1' ('Sürüm ' + $psv + '. Multimizer bu sürümle çalışır.')))
    } else {
        [void]$n.Add((New-PrepItem 'ps' 'req' 'bad' 'Windows PowerShell 5.1' ('Sürüm ' + $psv + ' bulundu; Multimizer Windows PowerShell 5.1 ister. Windows 10 ve 11’de yerleşiktir; eski sistemde “Windows Management Framework 5.1” kurulmalıdır.')))
    }

    $rel = [int]$S.Net.Release
    $nn = [string]$S.Net.Name
    $wu = New-PrepFix 'Url' 'Windows Update’i aç' @{ Url = 'ms-settings:windowsupdate' }
    if ($rel -ge 461808) {
        [void]$n.Add((New-PrepItem 'net' 'req' 'ok' '.NET Framework' ('Sürüm ' + $nn + ' kurulu. Arayüz (WPF) ve motorların derlenmesi için gerekli sürüm var.')))
    } elseif ($rel -ge 379893) {
        [void]$n.Add((New-PrepItem 'net' 'req' 'warn' '.NET Framework' ('Sürüm ' + $nn + ' kurulu; 4.7.2 ve üzeri önerilir. Windows Update ile güncellenir.') $wu))
    } else {
        $cur = 'Okunamadı'
        if ($nn -ne '') { $cur = $nn }
        [void]$n.Add((New-PrepItem 'net' 'req' 'bad' '.NET Framework' ('Gerekli sürüm bulunamadı (şu an: ' + $cur + '). En az 4.5.2, önerilen 4.7.2 ve üzeri. Windows Update ile kurulur.') $wu))
    }

    if ($S.Csc.Found -eq $true) {
        [void]$n.Add((New-PrepItem 'csc' 'req' 'ok' 'C# derleyicisi' 'Bulundu. Silinen dosya kurtarma ve kalıcı silme motorları ilk kullanımda bununla derlenir.'))
    } else {
        [void]$n.Add((New-PrepItem 'csc' 'req' 'bad' 'C# derleyicisi' 'csc.exe bulunamadı; kurtarma ve kalıcı silme motorları derlenemez. .NET Framework onarımı için Windows Update’i çalıştırın.' $wu))
    }

    if ($S.Wmi.Ok -eq $true) {
        [void]$n.Add((New-PrepItem 'wmi' 'req' 'ok' 'WMI (CIM) sorguları' 'Çalışıyor. Bilgisayar tanıma ve birçok denetim buna dayanır.'))
    } else {
        $we = [string]$S.Wmi.Error
        if ($we.Length -gt 160) { $we = $we.Substring(0, 157) + '...' }
        [void]$n.Add((New-PrepItem 'wmi' 'req' 'bad' 'WMI (CIM) sorguları' ('Sorgu başarısız: ' + $we + ' WMI deposu bozulmuş olabilir; birçok denetim çalışmaz. Doğrulama ve onarım Microsoft’un kendi winmgmt aracıyla yapılır.') (New-PrepFix 'Wmi' 'Doğrula ve onar')))
    }

    $bld = [int]$S.Os.Build
    $osn = [string]$S.Os.Name
    if ($osn -eq '') { $osn = 'Windows' }
    $osd = $osn
    if ([string]$S.Os.Display -ne '') { $osd += ' ' + [string]$S.Os.Display }
    if ($bld -gt 0) { $osd += ' (derleme ' + [string]$bld + ')' }
    if ($bld -ge 19041) {
        [void]$n.Add((New-PrepItem 'os' 'req' 'ok' 'Windows sürümü' ($osd + '. Desteklenen bir sürüm.')))
    } elseif ($bld -ge 10240) {
        [void]$n.Add((New-PrepItem 'os' 'req' 'warn' 'Windows sürümü' ($osd + '. Eski sürüm; bazı özellikler çalışmayabilir. Windows Update ile güncelleyin.') $wu))
    } elseif ($bld -gt 0) {
        [void]$n.Add((New-PrepItem 'os' 'req' 'bad' 'Windows sürümü' ($osd + '. Multimizer Windows 10 ve 11 içindir.')))
    } else {
        [void]$n.Add((New-PrepItem 'os' 'req' 'info' 'Windows sürümü' 'Okunamadı.'))
    }

    $bad = @($S.Exts | Where-Object { [string]$_.Problem -ne '' })
    if (@($S.Exts).Count -eq 0) {
        [void]$n.Add((New-PrepItem 'ext' 'req' 'info' 'Multimizer eklentileri' 'Denetlenemedi.'))
    } elseif ($bad.Count -eq 0) {
        [void]$n.Add((New-PrepItem 'ext' 'req' 'ok' 'Multimizer eklentileri' ([string]@($S.Exts).Count + ' eklentinin hepsi yerinde ve özetleri doğru (kurtarma, silme, şifreleme, bellek, Wi-Fi ve disk koruma).')))
    } else {
        $names = (@($bad | ForEach-Object { [string]$_.Name }) -join ', ')
        [void]$n.Add((New-PrepItem 'ext' 'req' 'bad' 'Multimizer eklentileri' ([string]$bad.Count + ' eklenti eksik ya da değişmiş: ' + $names + '. ZIP dosyasının tamamını yeni bir klasöre çıkarıp Baslat.bat’ı oradan çalıştırın. ' + [string]$bad[0].Problem)))
    }

    if ($S.Data.Ok -eq $true) {
        [void]$n.Add((New-PrepItem 'data' 'req' 'ok' 'Veri klasörü' ('Yazılabiliyor (' + [string]$S.Data.Path + '). Ayarlar, günlükler ve yedekler burada tutulur.')))
    } else {
        [void]$n.Add((New-PrepItem 'data' 'req' 'bad' 'Veri klasörü' ('Yazılamıyor (' + [string]$S.Data.Path + '): ' + [string]$S.Data.Error + ' Ayarlar ve günlükler kaydedilemez.')))
    }

    # ---- önerilen
    if ($S.Admin -eq $true) {
        [void]$n.Add((New-PrepItem 'admin' 'rec' 'ok' 'Yönetici hakları' 'Var. Disk, güvenlik ve sistem işlemleri yapılabilir.'))
    } else {
        [void]$n.Add((New-PrepItem 'admin' 'rec' 'warn' 'Yönetici hakları' 'Yok. Disk, güvenlik ve sistem işlemleri için gerekir; Multimizer’ı Baslat.bat ile açın, izin penceresinde “Evet” deyin.'))
    }

    $fg = [double]$S.Disk.FreeGB
    $sg = [double]$S.Disk.SizeGB
    $dl = [string]$S.Disk.Letter
    if ($sg -gt 0) {
        $pc = [int][math]::Round($fg * 100.0 / $sg)
        $txt = $dl + ' sürücüsünde ' + (Format-PcGb $fg) + ' boş (%' + [string]$pc + ').'
        $clean = New-PrepFix 'Page' 'Temizlik' @{ Page = 'clean'; Sub = '' }
        if ($fg -lt 2) { [void]$n.Add((New-PrepItem 'space' 'rec' 'bad' 'Sistem sürücüsünde boş alan' ($txt + ' Windows güncellemeleri ve geri yükleme noktaları için yer yok; önce yer açın.') $clean)) }
        elseif ($fg -lt 10 -or $pc -lt 8) { [void]$n.Add((New-PrepItem 'space' 'rec' 'warn' 'Sistem sürücüsünde boş alan' ($txt + ' Güncellemeler, sanal bellek ve geri yükleme noktaları için en az 10 GB önerilir.') $clean)) }
        else { [void]$n.Add((New-PrepItem 'space' 'rec' 'ok' 'Sistem sürücüsünde boş alan' $txt)) }
    } else {
        [void]$n.Add((New-PrepItem 'space' 'rec' 'info' 'Sistem sürücüsünde boş alan' 'Okunamadı.'))
    }

    if ([string]$S.Winget.Path -ne '') {
        $wv = ''
        if ([string]$S.Winget.Version -ne '') { $wv = ' (' + [string]$S.Winget.Version + ')' }
        [void]$n.Add((New-PrepItem 'winget' 'rec' 'ok' 'winget (Uygulama Yükleyicisi)' ('Kurulu' + $wv + '. Eksik bileşenler ve araçlar Microsoft’un bu aracıyla, paket özeti doğrulanarak kurulur.')))
    } else {
        [void]$n.Add((New-PrepItem 'winget' 'rec' 'warn' 'winget (Uygulama Yükleyicisi)' 'Bulunamadı. Bileşen ve araç kurulumları buna dayanır. Microsoft Store’daki “Uygulama Yükleyicisi”ni (App Installer) yükleyin, sonra Denetle’ye basın.' (New-PrepFix 'Url' 'Store’da aç' @{ Url = 'ms-windows-store://pdp/?ProductId=9NBLGGH4NNS1' })))
    }

    [void]$n.Add((Get-PrepVcItem $S.Vc.X64 'x64' 'Microsoft.VCRedist.2015+.x64' 'x64'))
    if ($os64) { [void]$n.Add((Get-PrepVcItem $S.Vc.X86 'x86' 'Microsoft.VCRedist.2015+.x86' 'x86')) }
    if ($S.Os.Arm -eq $true -and $null -ne $S.Vc.Arm64) { [void]$n.Add((Get-PrepVcItem $S.Vc.Arm64 'arm64' 'Microsoft.VCRedist.2015+.arm64' 'ARM64')) }

    $pt = $S.Protect
    if ($pt.Policy -eq $true) {
        [void]$n.Add((New-PrepItem 'restore' 'rec' 'warn' 'Sistem Koruması (geri yükleme noktaları)' 'Bir ilke tarafından kapatılmış. Multimizer değişikliklerden önce geri yükleme noktası alamaz; işlemler yine de önizlenir ve geçmişten geri alınabilir.'))
    } elseif ($pt.Known -eq $true -and $pt.On -eq $true) {
        [void]$n.Add((New-PrepItem 'restore' 'rec' 'ok' 'Sistem Koruması (geri yükleme noktaları)' ($dl + ' sürücüsünde açık. Büyük değişikliklerden önce geri yükleme noktası alınır.')))
    } elseif ($pt.Known -eq $true) {
        [void]$n.Add((New-PrepItem 'restore' 'rec' 'info' 'Sistem Koruması (geri yükleme noktaları)' 'Kapalı görünüyor. Multimizer, geri yükleme noktası alması gerektiğinde bunu sizin için açar; Ayarlar’dan geri yükleme noktasını kapatmadığınız sürece ek bir şey yapmanız gerekmez.'))
    } else {
        [void]$n.Add((New-PrepItem 'restore' 'rec' 'info' 'Sistem Koruması (geri yükleme noktaları)' 'Durumu okunamadı.'))
    }

    if ($S.Online -eq $true) {
        [void]$n.Add((New-PrepItem 'online' 'rec' 'ok' 'İnternet bağlantısı' 'Var. Bileşen indirme ve güncelleme denetimi yapılabilir.'))
    } elseif ($S.Online -eq $false) {
        [void]$n.Add((New-PrepItem 'online' 'rec' 'info' 'İnternet bağlantısı' 'Yok ya da engelli görünüyor. Bileşen kurulumları ve güncelleme denetimi için gerekir; Multimizer’ın diğer özellikleri bağlantısız çalışır.'))
    }

    # ---- isteğe bağlı
    $dx = $S.Dx
    $dxFix = New-PrepFix 'Winget' 'Kur' @{ Id = 'Microsoft.DirectX'; Name = [string]$script:PrepPackages['Microsoft.DirectX'] }
    if ($null -ne $dx) {
        if ($dx.Native -eq $true -and $dx.X86 -eq $true) {
            [void]$n.Add((New-PrepItem 'dx' 'opt' 'ok' 'DirectX eski çalışma zamanı' 'D3DX9 dosyaları kurulu. Eski oyun ve programlar için yeterli.'))
        } else {
            [void]$n.Add((New-PrepItem 'dx' 'opt' 'info' 'DirectX eski çalışma zamanı' 'D3DX9 dosyaları yok. Yalnızca eski oyunlar ve eski programlar “d3dx9_43.dll bulunamadı” hatası verirse gerekir; Multimizer için gerekmez.' $dxFix))
        }
    }

    $dv = @($S.Dotnet)
    $hi = ''
    foreach ($v in $dv) {
        $mj = 0
        if (([string]$v) -match '^(\d+)\.') { $mj = [int]$Matches[1] }
        if ($mj -ge 8) { $hi = [string]$v }
    }
    if ($hi -ne '') {
        [void]$n.Add((New-PrepItem 'dotnet' 'opt' 'ok' '.NET Masaüstü Çalışma Zamanı' ('Kurulu (' + $hi + '). Yeni .NET ile yazılmış programlar çalışır.')))
    } else {
        [void]$n.Add((New-PrepItem 'dotnet' 'opt' 'info' '.NET Masaüstü Çalışma Zamanı' 'Yüklü değil. Yeni .NET ile yazılmış bazı programlar (ör. donanım izleme araçları) bunu ister; Multimizer için gerekmez.' (New-PrepFix 'Winget' 'Kur' @{ Id = 'Microsoft.DotNet.DesktopRuntime.10'; Name = [string]$script:PrepPackages['Microsoft.DotNet.DesktopRuntime.10'] })))
    }

    # Uzman kipi: ham değerler
    if ($Expert) {
        $ex = @{}
        $ex['ps'] = 'Tür: ' + [string]$S.Ps.Edition + '.'
        if ($rel -gt 0) { $ex['net'] = 'Release anahtarı: ' + [string]$rel + '.' }
        if ($S.Csc.Found -eq $true) { $ex['csc'] = 'Yol: ' + [string]$S.Csc.Path }
        if ([string]$S.Winget.Path -ne '') { $ex['winget'] = 'Yol: ' + [string]$S.Winget.Path }
        if ($null -ne $S.Vc.X64 -and $S.Vc.X64.Installed -eq $true) { $ex['vcx64'] = 'Derleme: ' + [string]$S.Vc.X64.Build + '.' }
        if ($dv.Count -gt 0) { $ex['dotnet'] = 'Bulunan sürümler: ' + ($dv -join ', ') + '.' }
        if ([string]$S.Data.Path -ne '') { $ex['data'] = 'Yol: ' + [string]$S.Data.Path }
        foreach ($it in $n) {
            if ($ex.ContainsKey([string]$it.Key)) { $it.Detail = [string]$it.Detail + '  ' + [string]$ex[[string]$it.Key] }
        }
    }
    return , $n.ToArray()
}

# Özet: @{ Bad; Warn; Info; Ok; Total; Level (good | warn | bad); Text }
function Get-PrepSummary($Items) {
    $b = 0; $w = 0; $i = 0; $o = 0
    foreach ($x in @($Items)) {
        switch ([string]$x.Status) { 'bad' { $b++ } 'warn' { $w++ } 'info' { $i++ } default { $o++ } }
    }
    $total = $b + $w + $i + $o
    $lvl = 'good'
    $txt = 'Her şey hazır: ' + [string]$total + ' denetimin hepsi uygun.'
    if ($b -gt 0) { $lvl = 'bad'; $txt = [string]$b + ' zorunlu ya da önemli eksik var' ; if ($w -gt 0) { $txt += ', ' + [string]$w + ' öneri' }; $txt += '. Önce kırmızı satırlara bakın.' }
    elseif ($w -gt 0) { $lvl = 'warn'; $txt = 'Multimizer çalışır; ' + [string]$w + ' önerilen bileşen eksik ya da eski.' }
    elseif ($i -gt 0) { $txt = 'Her şey hazır; ' + [string]$i + ' isteğe bağlı bileşen kurulabilir.' }
    return @{ Bad = $b; Warn = $w; Info = $i; Ok = $o; Total = $total; Level = $lvl; Text = $txt }
}

# “Eksikleri gider” için kurulacak paketler: @( @{ Key; Id; Name } ). Keys boşsa tüm uygun satırlar; ok olanlar ve tekrarlayan kimlikler atlanır.
function Get-PrepInstallList($Items, $Keys = $null) {
    $out = New-Object System.Collections.ArrayList
    $seen = @{}
    $want = @()
    if ($null -ne $Keys) { $want = @($Keys | ForEach-Object { [string]$_ }) }
    foreach ($x in @($Items)) {
        if ($null -eq $x.Fix -or [string]$x.Fix.Do -ne 'Winget') { continue }
        if ([string]$x.Status -eq 'ok') { continue }
        if ($want.Count -gt 0 -and $want -notcontains [string]$x.Key) { continue }
        $id = [string]$x.Fix.Id
        if ($seen.ContainsKey($id.ToLowerInvariant())) { continue }
        $seen[$id.ToLowerInvariant()] = $true
        [void]$out.Add(@{ Key = [string]$x.Key; Id = $id; Name = [string]$x.Fix.Name })
    }
    return , $out.ToArray()
}

# ---------------- kurulum ve onarım (onaylı) ----------------
# P: Ids (izin listesindeki winget kimlikleri). Kurulumlar sırayla yapılır; her paketin sonucu ayrı bildirilir.
function Job_PrepInstall($P) {
    $ids = New-Object System.Collections.ArrayList
    foreach ($x in @($P.Ids)) { $s = [string]$x; if ($s -ne '' -and -not $ids.Contains($s)) { [void]$ids.Add($s) } }
    $out = @{ Ok = $false; Items = @(); Reboot = $false; Done = 0; Failed = 0; Canceled = $false; Error = '' }
    if ($ids.Count -eq 0) { $out.Error = 'Kurulacak bileşen seçilmedi.'; return $out }
    if ((Get-WingetPath) -eq '') {
        $out.Error = 'winget bulunamadı. Microsoft Store’dan “Uygulama Yükleyicisi”ni (App Installer) yükleyin.'
        Write-WhLog $out.Error 'ERR'
        return $out
    }
    Reset-Counters
    Set-JobProgress 0 $ids.Count 'Bileşenler kuruluyor'
    $items = New-Object System.Collections.ArrayList
    foreach ($id in $ids) {
        if (Test-JobCancel) { $out.Canceled = $true; Write-WhLog 'İptal edildi.' 'WARN'; break }
        $chk = Test-PrepPackage $id
        if ($chk -ne '') {
            Add-Err $chk
            [void]$items.Add(@{ Id = $id; Ok = $false; Code = 0; Text = $chk })
            $out.Failed++
            Step-JobProgress
            continue
        }
        Write-WhLog ('=== Kuruluyor: ' + $id + ' (winget deposu; paket özeti winget tarafından doğrulanır)') 'STEP'
        $code = -1
        try {
            $r = Invoke-WingetRaw @('install', '--id', $id, '--exact', '--silent', '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity')
            Write-WingetLines $r.Lines
            $code = [int]$r.Code
        } catch { Write-WhLog ($id + ': ' + $_.Exception.Message) 'ERR' }
        $res = Get-PrepWingetResult $code
        if ($res.Ok -eq $true) { Add-Done ($id + ': ' + $res.Text); $out.Done++ } else { Add-Err ($id + ': ' + $res.Text); $out.Failed++ }
        if ($res.Reboot -eq $true) { $out.Reboot = $true }
        [void]$items.Add(@{ Id = $id; Ok = ($res.Ok -eq $true); Code = $code; Text = [string]$res.Text })
        Step-JobProgress
    }
    $out.Items = $items.ToArray()
    $out.Ok = ($out.Failed -eq 0 -and $out.Canceled -ne $true -and $out.Done -gt 0)
    if ($out.Failed -gt 0 -and $out.Done -eq 0 -and [string]$out.Error -eq '') { $out.Error = [string]$items[0].Text }
    Write-WhLog ('Kurulan bileşen: ' + [string]$out.Done + ' / ' + [string]$ids.Count) 'INFO'
    return $out
}

# WMI deposunu doğrular; tutarsızsa Microsoft’un winmgmt aracıyla onarır (kayıtlı veriyi korur). Dönüş: @{ Ok; Verified; Salvaged; Text }
function Invoke-PrepWmiRepair {
    $r = @{ Ok = $false; Verified = $false; Salvaged = $false; Text = '' }
    $o = @(& winmgmt.exe /verifyrepository 2>&1 | ForEach-Object { [string]$_ })
    $code = [int]$LASTEXITCODE
    $txt = ($o -join ' ').Trim()
    if ($txt -ne '') { Write-WhLog ('winmgmt /verifyrepository: ' + $txt) 'INFO' }
    $incons = ($txt -match '(?i)inconsistent|not consistent|tutars[ıi]z|tutarl[ıi]\s+de[ğg]il')
    if ($code -eq 0 -and -not $incons) { $r.Ok = $true; $r.Verified = $true; $r.Text = 'WMI deposu tutarlı; onarım gerekmedi.'; return $r }
    Write-WhLog 'WMI deposu tutarsız görünüyor; winmgmt /salvagerepository çalıştırılıyor...' 'WARN'
    $o2 = @(& winmgmt.exe /salvagerepository 2>&1 | ForEach-Object { [string]$_ })
    $c2 = [int]$LASTEXITCODE
    $t2 = ($o2 -join ' ').Trim()
    if ($t2 -ne '') { Write-WhLog ('winmgmt /salvagerepository: ' + $t2) 'INFO' }
    $r.Salvaged = $true
    if ($c2 -ne 0) { $r.Text = 'WMI deposu onarılamadı (winmgmt çıkış kodu ' + [string]$c2 + ').'; return $r }
    $v = Test-PrepWmi
    if ($v.Ok -eq $true) { $r.Ok = $true; $r.Verified = $true; $r.Text = 'WMI deposu onarıldı; sorgular çalışıyor.' } else { $r.Text = 'WMI deposu onarıldı ama sorgu hâlâ başarısız: ' + [string]$v.Error }
    return $r
}

function Job_PrepWmi($P) {
    try {
        $r = Invoke-PrepWmiRepair
        if ($r.Ok -eq $true) { Write-WhLog $r.Text 'OK' } else { Write-WhLog $r.Text 'ERR' }
        return $r
    } catch {
        Write-WhLog ('WMI denetimi yapılamadı: ' + $_.Exception.Message) 'ERR'
        return @{ Ok = $false; Verified = $false; Salvaged = $false; Text = [string]$_.Exception.Message }
    }
}
