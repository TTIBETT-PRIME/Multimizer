# ==================================================================
#  Multimizer eklentisi: disk koruma. BitLocker özelliğini açar, askıya alır, kilitler ve kaldırır.
#  Bu dosya Multimizer.ps1 tarafından gerektiğinde yüklenir; tek başına çalıştırılmaz. Yalnızca Çözüm Merkezi Diskler sekmesinde
#  ilgili düğmeye basılınca yüklenir. Özeti ana betikte yazılıdır; okuma ve planlama işlevleri de orada.
#  Ana betikten kullanılanlar: Get-SlvEnv, Get-SlvDisks, Test-BlEnablePlan, Test-BlKeyDir, Get-BlKeyFileName, Format-BlKeyFile,
#  Get-BlScopeText, Job_BitLockerKey, Write-WhLog.
#  Kurallar: önce plan, sonra anahtar; kurtarma anahtarı şifrelenen sürücü dışındaki bir klasöre yazılıp geri okunarak
#  doğrulanmadan hiçbir sürücü şifrelenmiş sayılmaz. Doğrulama başarısız olursa yapılan her şey geri alınır.
# ==================================================================

function global:Get-BlDriveName([string]$Drive) {
    $d = ([string]$Drive).Trim().ToUpperInvariant()
    if ($d -cmatch '^[A-Z]$') { $d = $d + ':' }
    if ($d -cmatch '^[A-Z]:$') { return $d }
    return ''
}

function global:New-BlResult([string]$Op, [string]$Drive) {
    return @{ Ok = $false; Op = $Op; Drive = $Drive; Message = ''; Error = ''; NeedsReboot = $false; KeyPath = '' }
}

# Klasörü gerekirse oluşturur, küçük bir deneme dosyası yazıp siler. Dönüş: '' = yazılabilir, aksi hâlde neden.
function global:Test-BlDirWritable([string]$Dir) {
    try {
        if (-not (Test-Path -LiteralPath $Dir -PathType Container)) { [void](New-Item -ItemType Directory -Path $Dir -Force -ErrorAction Stop) }
        $probe = Join-Path $Dir ('.mm-deneme-' + [System.Guid]::NewGuid().ToString('N') + '.tmp')
        [System.IO.File]::WriteAllText($probe, 'x')
        [System.IO.File]::Delete($probe)
        return ''
    } catch {
        return ('Klasöre yazılamadı: ' + $_.Exception.Message)
    }
}

# Var olan bir dosyanın üzerine yazmaz: ad doluysa " (2)", " (3)" ... ekler
function global:Get-BlFreeName([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $Path }
    $dir = Split-Path -Parent $Path
    $base = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    $ext = [System.IO.Path]::GetExtension($Path)
    for ($i = 2; $i -lt 1000; $i++) {
        $c = Join-Path $dir ($base + ' (' + [string]$i + ')' + $ext)
        if (-not (Test-Path -LiteralPath $c)) { return $c }
    }
    return (Join-Path $dir ($base + '-' + [System.Guid]::NewGuid().ToString('N').Substring(0, 8) + $ext))
}

# Sürücünün kurtarma anahtarlarını okur. Dönüş: dizi (öğe: @{ Id; Password }); anahtar yoksa boş dizi
function global:Get-BlKeysOf([string]$Drive) {
    $r = Job_BitLockerKey @{ Drive = $Drive }
    if ($null -ne $r -and $r.Ok -eq $true) { return , @($r.Keys) }
    return , @()
}

# Anahtarları dosyaya yazar, geri okuyup her anahtarın dosyada olduğunu doğrular. Dönüş: @{ Ok; Path; Error }
function global:Save-BlKeyFile([string]$Drive, [string]$Dir, $Keys) {
    $res = @{ Ok = $false; Path = ''; Error = '' }
    $list = @($Keys)
    if ($list.Count -eq 0) { $res.Error = 'Kurtarma anahtarı okunamadı.'; return $res }
    $path = ''
    try {
        $text = Format-BlKeyFile $Drive $list
        $path = Get-BlFreeName (Join-Path $Dir (Get-BlKeyFileName $Drive))
        $enc = New-Object System.Text.UTF8Encoding -ArgumentList $true
        [System.IO.File]::WriteAllText($path, $text, $enc)
        $back = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
        foreach ($k in $list) {
            if (-not $back.Contains([string]$k.Password) -or -not $back.Contains([string]$k.Id)) { throw 'Dosya yazıldı ama içeriği doğrulanamadı.' }
        }
        $res.Ok = $true
        $res.Path = $path
    } catch {
        $res.Error = $_.Exception.Message
        # yarım kalmış, güvenilmez bir anahtar dosyası bırakılmaz (bu dosyayı biz oluşturduk)
        if ($path -ne '') { try { if (Test-Path -LiteralPath $path) { [System.IO.File]::Delete($path) } } catch { } }
    }
    return $res
}

# Şifrelemeyi geri alır (yalnızca bu işlemin başlattığı şifreleme için çağrılır; plan sürücünün şifresiz olduğunu doğrulamıştı)
function global:Undo-BlEnable([string]$Drive) {
    try {
        [void](Disable-BitLocker -MountPoint $Drive -ErrorAction Stop)
        return $true
    } catch {
        return $false
    }
}

# ---------------- şifrelemeyi başlat ----------------
# P: Drive, KeyDir (anahtar dosyasının klasörü), Full (isteğe bağlı: tüm sürücüyü şifrele)
function global:Invoke-BlEnable($P) {
    $drive = Get-BlDriveName ([string]$P.Drive)
    $r = New-BlResult 'Enable' $drive
    if ($drive -eq '') { $r.Error = 'Geçersiz sürücü.'; return $r }
    $sys = Get-SlvEnv
    $disks = Get-SlvDisks
    $vol = $null
    foreach ($d in @($disks)) { if ([string]$d.Drive -eq $drive) { $vol = $d } }
    if ($null -eq $vol) { $r.Error = $drive + ' sürücüsü bulunamadı.'; return $r }
    $plan = Test-BlEnablePlan $vol $sys
    if ($plan.Ok -ne $true) { $r.Error = [string]$plan.Why; return $r }
    if ([string]$plan.Method -eq 'DeviceEncryption') { $r.Error = 'Windows Home sürümünde cihaz şifrelemesi Ayarlar sayfasından açılır.'; return $r }
    $dir = ([string]$P.KeyDir).Trim()
    $bad = Test-BlKeyDir $dir $drive
    if ($bad -ne '') { $r.Error = $bad; return $r }
    $bad = Test-BlDirWritable $dir
    if ($bad -ne '') { $r.Error = $bad; return $r }

    $isOs = ($plan.IsOs -eq $true)
    $scope = [string]$plan.Scope
    if ($P.Full -eq $true) { $scope = 'Full' }
    $cmd = @{ MountPoint = $drive; EncryptionMethod = [string]$plan.Cipher; ErrorAction = 'Stop' }
    if ($scope -ne 'Full') { $cmd.UsedSpaceOnly = $true }
    if ($isOs) { $cmd.TpmProtector = $true } else { $cmd.RecoveryPasswordProtector = $true }

    Write-WhLog ($drive + ' için BitLocker etkinleştiriliyor (' + [string]$plan.Cipher + ', ' + (Get-BlScopeText $scope) + ').') 'INFO'
    try {
        [void](Enable-BitLocker @cmd)
    } catch {
        $r.Error = 'BitLocker etkinleştirilemedi: ' + $_.Exception.Message
        Write-WhLog $r.Error 'ERR'
        [void](Undo-BlEnable $drive)
        return $r
    }

    $fail = ''
    if ($isOs) {
        try { [void](Add-BitLockerKeyProtector -MountPoint $drive -RecoveryPasswordProtector -ErrorAction Stop) }
        catch { $fail = 'Kurtarma anahtarı oluşturulamadı: ' + $_.Exception.Message }
    }
    $save = $null
    if ($fail -eq '') {
        $keys = Get-BlKeysOf $drive
        if (@($keys).Count -eq 0) { $fail = 'Kurtarma anahtarı okunamadı.' }
        else {
            $save = Save-BlKeyFile $drive $dir $keys
            if ($save.Ok -ne $true) { $fail = 'Kurtarma anahtarı dosyası doğrulanamadı: ' + [string]$save.Error }
        }
    }
    if ($fail -ne '') {
        $undone = Undo-BlEnable $drive
        if ($undone) { $r.Error = $fail + ' Şifreleme geri alındı; sürücüde değişiklik kalmadı.' }
        else { $r.Error = $fail + ' Şifreleme geri alınamadı; Denetim Masası bölümündeki BitLocker Sürücü Şifrelemesi sayfasından durumu kontrol edin.' }
        Write-WhLog $r.Error 'ERR'
        return $r
    }

    $r.Ok = $true
    $r.KeyPath = [string]$save.Path
    $r.Message = $drive + ' için kurtarma anahtarı kaydedildi: ' + $r.KeyPath + '.'
    Write-WhLog ($drive + ' için kurtarma anahtarı dosyaya yazıldı ve doğrulandı (anahtar günlüğe yazılmaz): ' + $r.KeyPath) 'OK'
    if ($isOs) {
        $r.NeedsReboot = $true
        $r.Message += ' Şifreleme bilgisayarı yeniden başlatınca başlayacak.'
    } else {
        $r.Message += ' Şifreleme arka planda sürüyor.'
        if ([string]$vol.DriveType -ne 'Removable') {
            $au = Invoke-BlAutoUnlock $drive
            if ($au.Ok -eq $true) { $r.Message += ' Sürücü, oturum açınca kendiliğinden açılacak.' }
            else { $r.Message += ' Otomatik açma etkinleştirilemedi (' + [string]$au.Error + '); sürücü yeniden başlatınca kurtarma anahtarı isteyebilir.' }
        }
    }
    return $r
}

# ---------------- otomatik açma (yalnızca bu bilgisayarda, sistem sürücüsü açılınca) ----------------
function global:Invoke-BlAutoUnlock([string]$Drive) {
    $r = @{ Ok = $false; Error = '' }
    $sys = Get-SlvEnv
    $disks = Get-SlvDisks
    $osVol = $null
    foreach ($d in @($disks)) { if ([string]$d.Drive -eq ([string]$sys.OsDrive).ToUpperInvariant()) { $osVol = $d } }
    $osState = 'unknown'
    if ($null -ne $osVol) { $osState = Get-BlState $osVol }
    if ($osState -ne 'encrypted' -and $osState -ne 'working') { $r.Error = 'sistem sürücüsü şifreli değil'; return $r }
    try {
        [void](Enable-BitLockerAutoUnlock -MountPoint $Drive -ErrorAction Stop)
        $r.Ok = $true
    } catch {
        $r.Error = $_.Exception.Message
    }
    return $r
}

# ---------------- diğer işlemler ----------------
function global:Invoke-BlSimple([string]$Op, [string]$Drive) {
    $r = New-BlResult $Op $Drive
    if ($Drive -eq '') { $r.Error = 'Geçersiz sürücü.'; return $r }
    $sys = Get-SlvEnv
    if ($sys.IsAdmin -ne $true) { $r.Error = 'Bu işlem için Multimizer uygulamasını yönetici olarak çalıştırın.'; return $r }
    $isOs = ($Drive -eq ([string]$sys.OsDrive).ToUpperInvariant())
    try {
        switch ($Op) {
            'Suspend' {
                [void](Suspend-BitLocker -MountPoint $Drive -RebootCount 1 -ErrorAction Stop)
                $r.Message = $Drive + ' için BitLocker koruması bir sonraki yeniden başlatmaya kadar askıya alındı.'
            }
            'Lock' {
                if ($isOs) { $r.Error = 'Windows kurulu olan sürücü kilitlenemez.'; return $r }
                [void](Lock-BitLocker -MountPoint $Drive -ErrorAction Stop)
                $r.Message = $Drive + ' sürücüsü kilitlendi. Açmak için parola ya da kurtarma anahtarı gerekir.'
            }
            'Disable' {
                [void](Disable-BitLocker -MountPoint $Drive -ErrorAction Stop)
                $r.Message = $Drive + ' için şifre çözme başladı; arka planda sürer, bilgisayarı kapatırsanız kaldığı yerden devam eder.'
            }
            'AutoUnlock' {
                if ($isOs) { $r.Error = 'Otomatik açma yalnızca veri sürücüleri içindir.'; return $r }
                $au = Invoke-BlAutoUnlock $Drive
                if ($au.Ok -ne $true) { $r.Error = 'Otomatik açma etkinleştirilemedi: ' + [string]$au.Error; return $r }
                $r.Message = $Drive + ' sürücüsü, oturum açınca kendiliğinden açılacak.'
            }
            default { $r.Error = 'Bilinmeyen BitLocker işlemi: ' + $Op; return $r }
        }
    } catch {
        $m = [string]$_.Exception.Message
        if ($Op -eq 'Lock') { $m += ' Sürücüde açık dosya varsa programları kapatıp yeniden deneyin.' }
        $r.Error = 'BitLocker işlemi başarısız (' + $Op + '): ' + $m
        Write-WhLog $r.Error 'ERR'
        return $r
    }
    $r.Ok = $true
    Write-WhLog $r.Message 'OK'
    return $r
}

# P: Op (Enable | Suspend | Lock | Disable | AutoUnlock), Drive, KeyDir (yalnızca Enable)
function global:Job_BlOp($P) {
    $op = [string]$P.Op
    $drive = Get-BlDriveName ([string]$P.Drive)
    try {
        if ($op -eq 'Enable') { return (Invoke-BlEnable $P) }
        return (Invoke-BlSimple $op $drive)
    } catch {
        Write-WhLog ('BitLocker işlemi başarısız: ' + $_.Exception.Message) 'ERR'
        $r = New-BlResult $op $drive
        $r.Error = $_.Exception.Message
        return $r
    }
}
