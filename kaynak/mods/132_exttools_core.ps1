# ==================================================================
#  DIŞ ARAÇLAR (sağlayıcı katmanı): çekirdek
#  Sürekli geliştirilen, kendi alanında yerleşik araçlar Multimizer’ın içine kopyalanmaz. Araçlar > Dış araçlar sekmesinde bulunur,
#  yalnızca onayla ve Microsoft’un winget aracıyla (paket özeti winget tarafından doğrulanarak) kurulur; kurulu olanlar tek tıkla açılır.
#  Liste sabittir (izin listesi): listede olmayan kimlik hiçbir yolla kurulamaz. Hiçbir araç kendiliğinden kurulmaz ya da çalıştırılmaz.
#  Satır biçimi:  Kimlik | Ad | Grup | Yayıncı | Açıklama | Sayfa (https) | Çalıştırılabilir dosya yolları (; ile ayrılır)
#  Yollarda ortam değişkenleri ve {WG} (winget kökleri: %LOCALAPPDATA%\Microsoft\WinGet ve %ProgramFiles%\WinGet) kullanılabilir; * ve ? joker karakterdir.
# ==================================================================
$script:ExtToolGroups = @('disk|Disk ve veri', 'sistem|Sistem ve donanım', 'ag|Ağ ve güvenlik', 'verim|Verimlilik')

$script:ExtToolRows = @(
    'CrystalDewWorld.CrystalDiskInfo|CrystalDiskInfo|disk|Crystal Dew World|Disklerin sağlığını (S.M.A.R.T.), sıcaklığını ve çalışma süresini gösterir; bozulmaya başlayan diski önceden yakalamanıza yardımcı olur.|https://crystalmark.info/en/software/crystaldiskinfo/|%ProgramFiles%\CrystalDiskInfo\DiskInfo64.exe;%ProgramFiles%\CrystalDiskInfo\DiskInfo32.exe;%ProgramFiles(x86)%\CrystalDiskInfo\DiskInfo32.exe;%ProgramFiles(x86)%\CrystalDiskInfo\DiskInfo64.exe',
    'CGSecurity.TestDisk|TestDisk ve PhotoRec|disk|CGSecurity|Silinen bölümleri ve dosyaları kurtarmak için köklü, açık kaynaklı araç çifti. Multimizer’ın kendi kurtarma motorunun bulamadığı durumlarda ikinci seçenektir.|https://www.cgsecurity.org/wiki/TestDisk|{WG}\Links\qphotorec.exe;{WG}\Links\photorec.exe;{WG}\Links\testdisk.exe;{WG}\Packages\CGSecurity.TestDisk_*\*\qphotorec_win.exe;{WG}\Packages\CGSecurity.TestDisk_*\qphotorec_win.exe;{WG}\Packages\CGSecurity.TestDisk_*\*\photorec_win.exe;{WG}\Packages\CGSecurity.TestDisk_*\photorec_win.exe;{WG}\Packages\CGSecurity.TestDisk_*\*\testdisk_win.exe;{WG}\Packages\CGSecurity.TestDisk_*\testdisk_win.exe',
    'WinDirStat.WinDirStat|WinDirStat|disk|WinDirStat ekibi|Disk alanını klasör ve dosya türüne göre renkli bir haritada gösterir; yer kaplayan şeyleri bulmayı kolaylaştırır.|https://windirstat.net/|%ProgramFiles%\WinDirStat\WinDirStat.exe;%ProgramFiles(x86)%\WinDirStat\windirstat.exe',
    'Microsoft.Sysinternals.Suite|Sysinternals Suite|sistem|Microsoft (Sysinternals)|Microsoft’un sistem inceleme araçları: Process Explorer, Autoruns, TCPView ve daha fazlası. Uzman kullanım içindir.|https://learn.microsoft.com/sysinternals/|{WG}\Links\procexp64.exe;{WG}\Links\procexp.exe;{WG}\Links\autoruns64.exe;{WG}\Links\autoruns.exe;{WG}\Packages\Microsoft.Sysinternals.Suite_*\procexp64.exe;{WG}\Packages\Microsoft.Sysinternals.Suite_*\*\procexp64.exe',
    'REALiX.HWiNFO|HWiNFO|sistem|REALiX|İşlemci, bellek, ekran kartı, anakart ve sensörlerin ayrıntılı bilgisini; canlı sıcaklık ve voltaj izlemeyi sunar.|https://www.hwinfo.com/|%ProgramFiles%\HWiNFO64\HWiNFO64.exe;%ProgramFiles(x86)%\HWiNFO64\HWiNFO64.exe;%ProgramFiles%\HWiNFO32\HWiNFO32.exe',
    'WireGuard.WireGuard|WireGuard|ag|WireGuard LLC|WireGuard’ın resmî Windows istemcisi. VPN sağlayıcınızın verdiği yapılandırma dosyasıyla çalışır; Multimizer’ın VPN bölümü bunu tanır.|https://www.wireguard.com/install/|%ProgramFiles%\WireGuard\wireguard.exe',
    '7zip.7zip|7-Zip|verim|Igor Pavlov|Ücretsiz, açık kaynaklı arşiv aracı; zip, 7z, rar ve birçok biçimi açar ve oluşturur.|https://www.7-zip.org/|%ProgramFiles%\7-Zip\7zFM.exe;%ProgramFiles(x86)%\7-Zip\7zFM.exe',
    'voidtools.Everything|Everything|verim|voidtools|Dosya ve klasör adlarını anında arar; büyük disklerde bile sonuç yazarken görünür.|https://www.voidtools.com/|%ProgramFiles%\Everything\Everything.exe;%ProgramFiles(x86)%\Everything\Everything.exe;%LOCALAPPDATA%\Programs\Everything\Everything.exe',
    'Microsoft.PowerToys|PowerToys|verim|Microsoft|Windows için üretkenlik araçları: pencere düzenleyici, toplu yeniden adlandırma, renk seçici ve daha fazlası.|https://learn.microsoft.com/windows/powertoys/|%ProgramFiles%\PowerToys\PowerToys.exe;%LOCALAPPDATA%\PowerToys\PowerToys.exe;%LOCALAPPDATA%\Programs\PowerToys\PowerToys.exe'
)
$script:ExtToolCache = $null

# Katalog: @( @{ Id; Name; Group; Publisher; Desc; Home; Exe } )
function Get-ExtToolCatalog {
    if ($null -ne $script:ExtToolCache) { return , $script:ExtToolCache }
    $out = New-Object System.Collections.ArrayList
    foreach ($r in $script:ExtToolRows) {
        $f = ([string]$r).Split('|')
        if ($f.Count -lt 7) { continue }
        [void]$out.Add(@{ Id = $f[0].Trim(); Name = $f[1].Trim(); Group = $f[2].Trim(); Publisher = $f[3].Trim(); Desc = $f[4].Trim(); Home = $f[5].Trim(); Exe = $f[6].Trim() })
    }
    $script:ExtToolCache = $out.ToArray()
    return , $script:ExtToolCache
}

# Kimliğe göre katalog satırı (büyük/küçük harf önemsiz); yoksa $null
function Get-ExtTool([string]$Id) {
    $cat = Get-ExtToolCatalog
    foreach ($t in $cat) { if ([string]$t.Id -eq $Id) { return $t } }
    return $null
}

# Kurulabilir mi? '' = evet; aksi halde nedeni
function Test-ExtToolId([string]$Id) {
    if ($Id -cnotmatch '^[A-Za-z0-9][A-Za-z0-9\.\-_\+]*\z') { return ('Geçersiz paket kimliği: ' + $Id) }
    if ($null -eq (Get-ExtTool $Id)) { return ($Id + ' izin listesinde değil; kurulmadı.') }
    return ''
}

# Yol kalıplarını açar: ortam değişkenleri genişletilir, {WG} iki winget köküne çevrilir, açılamayan değişkenli yollar atlanır
function Expand-ExtToolPaths([string]$Patterns) {
    $out = New-Object System.Collections.ArrayList
    foreach ($p in @($Patterns -split ';')) {
        $q = $p.Trim()
        if ($q -eq '') { continue }
        $variants = @($q)
        if ($q.Contains('{WG}')) { $variants = @($q.Replace('{WG}', '%LOCALAPPDATA%\Microsoft\WinGet'), $q.Replace('{WG}', '%ProgramFiles%\WinGet')) }
        foreach ($v in $variants) {
            $e = [Environment]::ExpandEnvironmentVariables($v)
            if ($e.Contains('%')) { continue }
            [void]$out.Add($e)
        }
    }
    return , $out.ToArray()
}

# Aracın çalıştırılabilir dosyası kuruluysa yolu, değilse ''. Yalnızca dosya var mı diye bakar; hiçbir şey çalıştırmaz.
function Find-ExtToolExe($Tool) {
    $paths = Expand-ExtToolPaths ([string]$Tool.Exe)
    $sep = [System.IO.Path]::DirectorySeparatorChar
    foreach ($p0 in $paths) {
        $p = $p0.Replace('\', [string]$sep)
        try {
            $wi = $p.IndexOfAny([char[]]@('*', '?'))
            if ($wi -ge 0) {
                # joker karakterden önceki sabit bölüm (kullanıcı klasörü gibi) olduğu gibi eşleşsin: [ ] gibi karakterler kaçırılır
                $si = $p.LastIndexOf($sep, $wi)
                $q = $p
                if ($si -ge 0) { $q = [System.Management.Automation.WildcardPattern]::Escape($p.Substring(0, $si + 1)) + $p.Substring($si + 1) }
                $f = Get-ChildItem -Path $q -File -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($null -ne $f) { return [string]$f.FullName }
            } elseif (Test-Path -LiteralPath $p -PathType Leaf) { return $p }
        } catch { }
    }
    return ''
}

# Katalogdaki her araç için kurulu mu ve nerede: @( @{ Id; Installed; Path } )
function Get-ExtToolStates {
    $cat = Get-ExtToolCatalog
    $out = New-Object System.Collections.ArrayList
    foreach ($t in $cat) {
        $path = ''
        try { $path = Find-ExtToolExe $t } catch { $path = '' }
        [void]$out.Add(@{ Id = [string]$t.Id; Installed = ($path -ne ''); Path = [string]$path })
    }
    return , $out.ToArray()
}

# Denetim işi: yalnızca dosya var mı diye bakar
function Job_ExtToolScan($P) {
    try {
        Write-WhLog ('Dış araçlar denetleniyor (yalnızca okuma)...') 'INFO'
        $items = Get-ExtToolStates
        $n = 0
        foreach ($i in $items) { if ($i.Installed -eq $true) { $n++ } }
        Write-WhLog ('Kurulu dış araç: ' + [string]$n + ' / ' + [string]@($items).Count) 'INFO'
        return @{ Ok = $true; Items = $items; At = (Get-Date).ToString('dd.MM.yyyy HH:mm') }
    } catch {
        Write-WhLog ('Dış araçlar denetlenemedi: ' + $_.Exception.Message) 'ERR'
        return @{ Ok = $false; Error = $_.Exception.Message }
    }
}

# Kurulum işi: P.Id yalnızca izin listesindeki bir kimlik olabilir. Dönüş: @{ Ok; Id; Name; Text; Reboot; Already; Code; Path }
function Job_ExtToolInstall($P) {
    $id = ''
    try { $id = [string]$P.Id } catch { $id = '' }
    $out = @{ Ok = $false; Id = $id; Name = ''; Text = ''; Reboot = $false; Already = $false; Code = 0; Path = '' }
    $why = Test-ExtToolId $id
    if ($why -ne '') { $out.Text = $why; Write-WhLog $why 'ERR'; return $out }
    $tool = Get-ExtTool $id
    $id = [string]$tool.Id
    $out.Id = $id
    $out.Name = [string]$tool.Name
    if ((Get-WingetPath) -eq '') {
        $out.Text = ('winget bulunamadı. Microsoft Store’dan “Uygulama Yükleyicisi”ni (App Installer) yükleyin.')
        Write-WhLog $out.Text 'ERR'
        return $out
    }
    Set-JobProgress 0 1 ($out.Name + ' kuruluyor')
    Write-WhLog ('=== Kuruluyor: ' + $out.Name + ' (' + $id + '; winget deposu, paket özeti winget tarafından doğrulanır)') 'STEP'
    $code = -1
    try {
        $r = Invoke-WingetRaw @('install', '--id', $id, '--exact', '--silent', '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity')
        Write-WingetLines $r.Lines
        $code = [int]$r.Code
    } catch { Write-WhLog ($id + ': ' + $_.Exception.Message) 'ERR' }
    $res = Get-PrepWingetResult $code
    $out.Code = $code
    $out.Ok = ($res.Ok -eq $true)
    $out.Reboot = ($res.Reboot -eq $true)
    $out.Already = ($res.Already -eq $true)
    $out.Text = [string]$res.Text
    if ($out.Ok) {
        try { $out.Path = Find-ExtToolExe $tool } catch { $out.Path = '' }
        Write-WhLog ($out.Name + ': ' + $out.Text) 'OK'
    } else {
        Write-WhLog ($out.Name + ': ' + $out.Text) 'ERR'
    }
    Set-JobProgress 1 1
    return $out
}
