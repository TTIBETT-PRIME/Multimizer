# ==================================================================
#  AYARLARI SIFIRLA (cekirdek): uygulama tercihlerini varsayilana dondurur
#  Beyaz liste: yalnizca asagidaki anahtarlar sifirlanir. Windows uzerinde yapilan degisiklikler, zamanlanmis gorevler, yedekleme ayarlari,
#  ag koruma durumu, uygulanan duzeltme kayitlari, guncelleme adresi ve kuruluma ait bilgi korunur (listede olmayan anahtara dokunulmaz;
#  yeni eklenen bir ayar, listeye yazilmadikca sifirlanmaz).
#  Her sifirlamadan once ayarlarin bir kopyasi ProgramData\Multimizer\AyarYedekleri klasorune yazilir (en yeni 10 kopya tutulur);
#  "Son sifirlamayi geri al" bu kopyayi geri yukler. Kopya yazilamazsa sifirlama yapilmaz.
#  Bu dosya arayuze dokunmaz; Ayarlar sayfasindaki kart ve komut satiri (-Gorev AyarSifirla) bu islevleri cagirir.
# ==================================================================

# Gorunum kapsami: tema, yerlesim, yakinlastirma, tasarim ve ayrintilari, ana ekran bicimi, saydamlik, hareket, kaydirma, odak halkasi, mini izleyici konumu
$script:ResetLookKeys = @('Theme', 'Layout', 'Zoom', 'Design', 'HomeMode', 'DsNav', 'DsRadius', 'DsFont', 'DsGraph', 'DsSkin', 'Backdrop', 'WinOpacity', 'ReduceMotion', 'SmoothScroll', 'ToTopButton', 'FullDesc', 'FocusRing', 'WidgetCorner', 'WidgetOpacity', 'WidgetX', 'WidgetY')
# Tercihler kapsami: gorunume ek olarak dil, kullanim kipi, bildirim, tepsi, izleme, gunluk, guvenli silme ve ana ekran pano duzeni
$script:ResetPrefKeys = @('Language', 'Mode', 'ExpertConfirm', 'RestorePoint', 'HideConsole', 'TrayMinimize', 'TrayOnMinimize', 'TrayHints', 'Notify', 'MonitorSec', 'MonGpu', 'KeepLogDays', 'WipePasses', 'DebugLog', 'Board', 'BoardCustom')

# Her sey kapsami: bu anahtarlar DISINDAKI tum ayarlar varsayilana doner (kurulum bilgisi ve gecis isaretleri korunur)
$script:ResetKeepKeys = @('Installed', 'LookVersion', 'LookNotice', 'FixLevel', 'PrepSeen', 'UpdateUrl', 'Org', 'Contact', 'ManagedOverride')

# 'Gorunum' | 'Tercihler' | 'Fabrika' | '' (tanimsiz). Komut satiri degeri de buradan gecer.
function ConvertTo-ResetScope([string]$Name) {
    $v = ([string]$Name).Trim().ToLowerInvariant()
    if ($v -eq '' -or $v -eq 'gorunum' -or $v -eq 'look') { return 'Gorunum' }
    if ($v -eq 'fabrika' -or $v -eq 'hersey' -or $v -eq 'factory') { return 'Fabrika' }
    if ($v -eq 'tercihler' -or $v -eq 'tumu' -or $v -eq 'hepsi' -or $v -eq 'all') { return 'Tercihler' }
    return ''
}

# Kapsamdaki anahtarlar (Gorunum ya da Tercihler = gorunum + tercihler)
function Get-ResetKeyList([string]$Scope) {
    $k = New-Object System.Collections.ArrayList
    if ($Scope -eq 'Fabrika') {
        foreach ($x in @((Get-DefaultSettings).Keys | Sort-Object)) { if ($script:ResetKeepKeys -notcontains [string]$x) { [void]$k.Add([string]$x) } }
        return $k.ToArray()
    }
    foreach ($x in $script:ResetLookKeys) { [void]$k.Add([string]$x) }
    if ($Scope -eq 'Tercihler') { foreach ($x in $script:ResetPrefKeys) { [void]$k.Add([string]$x) } }
    return $k.ToArray()
}

# Bir ayar degerinin karsilastirma imzasi (dizi ve tablo degerleri icin de calisir)
function Get-ValueSig($V) {
    try { return [string](ConvertTo-Json -InputObject $V -Compress -Depth 6) } catch { return [string]$V }
}

# Saf: ayar tablosunun sifirlanmis kopyasini ve degisen anahtarlarin listesini verir; dosyaya ve bellege dokunmaz.
# Donus: @{ Settings; Changed; Scope }
function Get-ResetResult($Current, [string]$Scope) {
    $def = Get-DefaultSettings
    $new = @{}
    foreach ($k in @($Current.Keys)) { $new[[string]$k] = $Current[$k] }
    $changed = New-Object System.Collections.ArrayList
    foreach ($k in @(Get-ResetKeyList $Scope)) {
        if (-not $def.ContainsKey($k)) { continue }
        $same = $false
        if ($new.ContainsKey($k)) { $same = ((Get-ValueSig $new[$k]) -ceq (Get-ValueSig $def[$k])) }
        if (-not $same) { [void]$changed.Add([string]$k) }
        $new[$k] = $def[$k]
    }
    # sifirlanmis gorunum yeni kayit sayilir: eski varsayilana tasima ve tek seferlik bilgi yeniden calismaz
    $new['LookVersion'] = 10
    $new['LookNotice'] = $false
    return @{ Settings = $new; Changed = $changed.ToArray(); Scope = $Scope }
}

function Get-SettingsBackupDir {
    $root = ''
    try { $root = [string]$sync.DataDir } catch { $root = '' }
    if ($root -eq '') { try { $root = [string]$script:DataDir } catch { $root = '' } }
    return (Join-Path $root 'AyarYedekleri')
}

# Ayarlarin bir kopyasini AyarYedekleri klasorune yazar; kopyanin yolunu verir (yazilamazsa bos). Etiket: gorunum | tercihler | geri-alma
function Save-SettingsBackup($S, [string]$Tag) {
    try {
        $dir = Get-SettingsBackupDir
        if (-not (Test-Path -LiteralPath $dir -PathType Container)) { [void](New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop) }
        $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
        # ayni saniyede yazilan kopyalar (etiketi ne olursa olsun) sira numarasi alir; boylece siralama her zaman olusturulma sirasini izler
        $n = 1
        foreach ($e in @(Get-SettingsBackupFiles)) { if ([string]$e.Key -ceq $stamp.Replace('-', '') -and [int]$e.Seq -ge $n) { $n = [int]$e.Seq + 1 } }
        $path = ''
        while ($true) {
            $sfx = ''
            if ($n -gt 1) { $sfx = '-' + [string]$n }
            $path = Join-Path $dir ('ayarlar-' + $stamp + '-' + $Tag + $sfx + '.json')
            if (-not (Test-Path -LiteralPath $path)) { break }
            $n++
        }
        Save-JsonFile $S $path 8
        if (-not (Test-Path -LiteralPath $path)) { return '' }
        $all = @(Get-SettingsBackupFiles)
        for ($i = 10; $i -lt $all.Count; $i++) { try { Remove-Item -LiteralPath $all[$i].Path -Force -ErrorAction Stop } catch { } }
        return $path
    } catch { return '' }
}

# AyarYedekleri klasorundeki kopyalar, yeniden eskiye (damga, ayni saniyedeki kopyalarda sira numarasi): @{ Path; Name; Time; Scope; Key; Seq }
# Tanimsiz adli dosyalar listelenmez ve silinmez.
function Get-SettingsBackupFiles {
    $out = New-Object System.Collections.ArrayList
    try {
        $dir = Get-SettingsBackupDir
        if (Test-Path -LiteralPath $dir -PathType Container) {
            foreach ($f in @(Get-ChildItem -LiteralPath $dir -Filter 'ayarlar-*.json' -File -ErrorAction SilentlyContinue)) {
                $m = [regex]::Match($f.Name, '^ayarlar-(\d{8})-(\d{6})-(gorunum|tercihler|fabrika|geri-alma)(?:-(\d+))?\.json$')
                if (-not $m.Success) { continue }
                $seq = 1
                if ($m.Groups[4].Success) { $seq = [int]$m.Groups[4].Value }
                $t = [datetime]::MinValue
                if (-not [datetime]::TryParseExact(($m.Groups[1].Value + $m.Groups[2].Value), 'yyyyMMddHHmmss', [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$t)) { $t = $f.LastWriteTime }
                [void]$out.Add(@{ Path = $f.FullName; Name = $f.Name; Time = $t; Scope = [string]$m.Groups[3].Value; Key = ($m.Groups[1].Value + $m.Groups[2].Value); Seq = $seq })
            }
        }
    } catch { }
    $arr = @($out.ToArray() | Sort-Object -Property @{ Expression = { [string]$_.Key }; Descending = $true }, @{ Expression = { [int]$_.Seq }; Descending = $true })
    # duz dizi doner (cagiranlar @() ile sarar); 'return , $arr' kullanilsa @() icinde ic ice dizi olusurdu
    return $arr
}

# Geri alinabilir sifirlama kopyalari, yeniden eskiye: @{ Path; Name; Time; Scope }  (geri alma oncesi kopyalar listelenmez)
function Get-ResetBackups {
    $out = New-Object System.Collections.ArrayList
    foreach ($b in @(Get-SettingsBackupFiles)) {
        if ([string]$b.Scope -eq 'geri-alma') { continue }
        [void]$out.Add(@{ Path = [string]$b.Path; Name = [string]$b.Name; Time = $b.Time; Scope = [string]$b.Scope })
    }
    return $out.ToArray()
}

# Kopyayi okur; ayar dosyasi gibi gorunmuyorsa $null
function Read-SettingsBackup([string]$Path) {
    try {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
        $obj = ConvertTo-Hashtable (Read-JsonFile $Path)
        if ($obj -is [hashtable] -and ($obj.ContainsKey('Theme') -or $obj.ContainsKey('Layout') -or $obj.ContainsKey('Mode'))) { return $obj }
    } catch { }
    return $null
}

# Kopyayi ayar dosyasina geri yazar (once gecerli ayarlarin kopyasi 'geri-alma' etiketiyle saklanir). Arayuz belleginin yenilenmesi cagirana aittir.
function Restore-SettingsFromBackup([string]$Path, $Current) {
    $obj = Read-SettingsBackup $Path
    if ($null -eq $obj) { return $false }
    if ($null -ne $Current) { [void](Save-SettingsBackup $Current 'geri-alma') }
    # eski surumden alinmis kopyada LookVersion yoktur; yazilmazsa ilk acilista gorunum yeniden yeni varsayilana tasinirdi
    $obj['LookVersion'] = 10
    $obj['LookNotice'] = $false
    try { Save-JsonFile $obj $sync.SettingsFile 8 } catch { return $false }
    return (Test-Path -LiteralPath $sync.SettingsFile)
}

# Arayuz baska bir surecte aciksa $true (arayuz kapanirken kendi ayarlarini yazar; bu yuzden o sirada dosya degistirilmez)
function Test-GuiRunning {
    $m = $null
    $busy = $false
    try {
        $m = New-Object System.Threading.Mutex($false, 'Global\Multimizer-Arayuz')
        $got = $false
        try { $got = $m.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $got = $true }
        if ($got) { try { $m.ReleaseMutex() } catch { } } else { $busy = $true }
    } catch { $busy = $false }
    finally { try { if ($null -ne $m) { $m.Dispose() } } catch { } }
    return $busy
}

# Arayuz kapaliyken (komut satiri): kayitli ayarlari sifirlar. Donus: @{ Ok; Changed; Backup }
function Reset-SettingsFile([string]$Scope) {
    $cur = Get-Settings
    $tag = 'gorunum'
    if ($Scope -eq 'Tercihler') { $tag = 'tercihler' }
    if ($Scope -eq 'Fabrika') { $tag = 'fabrika' }
    $bk = Save-SettingsBackup $cur $tag
    if ($bk -eq '') { return @{ Ok = $false; Changed = @(); Backup = '' } }
    $r = Get-ResetResult $cur $Scope
    Save-Settings $r.Settings
    return @{ Ok = $true; Changed = @($r.Changed); Backup = $bk }
}

# -Gorev AyarSifirla -Deger Gorunum | Tercihler
function Invoke-CliResetSettings {
    $scope = ConvertTo-ResetScope ([string]$Deger)
    if ($scope -eq '') { Write-WhLog 'Kullanım: -Gorev AyarSifirla -Deger Gorunum | Tercihler' 'ERR'; return 1 }
    if (Test-GuiRunning) { Write-WhLog 'Uygulama açıkken ayarlar komut satırından sıfırlanamaz; önce uygulamayı kapatın.' 'ERR'; return 3 }
    $r = Reset-SettingsFile $scope
    if ($r.Ok -ne $true) { Write-WhLog 'Ayar kopyası yazılamadı; sıfırlama yapılmadı.' 'ERR'; return 1 }
    $n = @($r.Changed).Count
    if ($scope -eq 'Tercihler') { Write-WhLog (Format-Tr 'Uygulama tercihleri sıfırlandı ({0} ayar değişti).' $n) 'OK' }
    else { Write-WhLog (Format-Tr 'Görünüm ayarları sıfırlandı ({0} ayar değişti).' $n) 'OK' }
    Write-WhLog (Format-Tr 'Önceki ayarların kopyası: {0}' ([string]$r.Backup)) 'INFO'
    return 0
}

# ---------------- her sey: Windows'ta yapilan degisikliklerin tamami ----------------
# Geri alinabilir gunlukler, yeniden eskiye (geri alinmis olanlar listelenmez)
function Get-UndoableJournals([string]$Dir) {
    $out = New-Object System.Collections.ArrayList
    try {
        if ([string]$Dir -ne '' -and (Test-Path -LiteralPath $Dir -PathType Container)) {
            foreach ($f in @(Get-ChildItem -LiteralPath $Dir -Filter 'yedek-*.jsonl' -File -ErrorAction SilentlyContinue | Sort-Object Name -Descending)) {
                if ($f.Name -match '^yedek-\d{8}-\d{6}\.jsonl$') { [void]$out.Add($f.FullName) }
            }
        }
    } catch { }
    return $out.ToArray()
}

# Tum gunlukleri yeniden eskiye geri alir. Donus: @{ Files; Changes; Errors; Summary }
function Job_UndoAll($P) {
    Reset-Counters
    $script:Preview = $false
    $t0 = Get-Date
    $files = @(Get-UndoableJournals ([string]$sync.BackupDir))
    Write-WhLog ('Geri alınacak kayıt dosyası: ' + [string]$files.Count) 'STEP'
    foreach ($f in $files) {
        try { Invoke-Undo ([string]$f) } catch { Add-Err ('Hata: ' + $_.Exception.Message) }
    }
    try { Update-AppliedAfterUndo } catch { Write-LogFile ('Kayit guncellenemedi: ' + $_.Exception.Message) }
    $sum = Get-RunSummary 'Tümünü geri alma' $t0
    Write-WhLog $sum 'INFO'
    return @{ Files = $files.Count; Changes = $script:Changes; Errors = $script:Errors; Summary = $sum }
}
