# ==================================================================
#  Multimizer eklentisi: dosya şifreleme (AES-256). İsteğe bağlı özelliktir; Ayarlar > İsteğe bağlı özellikler'den açılır.
#  Bu dosya Multimizer.ps1 tarafından gerektiğinde yüklenir; tek başına çalıştırılmaz. Özeti ana betikte yazılıdır.
# ==================================================================
# ---------------- AES-256 dosya şifreleme ----------------
# Biçim (.mmz):  'MMZ1' | yineleme sayısı (4 bayt, büyük uçlu) | tuz 16 | IV 16 | AES-256-CBC şifreli veri | HMAC-SHA256 (32)
# Anahtarlar PBKDF2-HMAC-SHA256 ile paroladan türetilir (32 bayt şifreleme + 32 bayt doğrulama). Önce doğrulanır, sonra çözülür.
$global:MmCryptIter = 200000
$global:MmCryptExt = '.mmz'

function global:Get-Pbkdf2Sha256([string]$Password, [byte[]]$Salt, [int]$Iter, [int]$Len) {
    $pw = [System.Text.Encoding]::UTF8.GetBytes($Password)
    $kdf = $null
    try {
        $kdf = New-Object System.Security.Cryptography.Rfc2898DeriveBytes -ArgumentList $pw, $Salt, $Iter, ([System.Security.Cryptography.HashAlgorithmName]::SHA256)
        return , $kdf.GetBytes($Len)
    } catch { } finally { if ($null -ne $kdf) { try { $kdf.Dispose() } catch { } } }
    # .NET Framework 4.7.2 öncesinde SHA-256'lı PBKDF2 hazır değil: aynı sonucu veren küçük bir yardımcı derlenir
    if (-not ('MmKdf' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Security.Cryptography;
public static class MmKdf {
    public static byte[] Derive(byte[] password, byte[] salt, int iterations, int length) {
        byte[] result = new byte[length];
        using (HMACSHA256 h = new HMACSHA256(password)) {
            int blocks = (length + 31) / 32;
            for (int i = 1; i <= blocks; i++) {
                byte[] si = new byte[salt.Length + 4];
                Buffer.BlockCopy(salt, 0, si, 0, salt.Length);
                si[salt.Length] = (byte)(i >> 24); si[salt.Length + 1] = (byte)(i >> 16); si[salt.Length + 2] = (byte)(i >> 8); si[salt.Length + 3] = (byte)i;
                byte[] u = h.ComputeHash(si);
                byte[] t = (byte[])u.Clone();
                for (int j = 1; j < iterations; j++) {
                    u = h.ComputeHash(u);
                    for (int k = 0; k < 32; k++) { t[k] ^= u[k]; }
                }
                int off = (i - 1) * 32;
                Buffer.BlockCopy(t, 0, result, off, Math.Min(32, length - off));
            }
        }
        return result;
    }
}
'@
    }
    return , ([MmKdf]::Derive($pw, $Salt, $Iter, $Len))
}

function global:Test-BytesEqual([byte[]]$A, [byte[]]$B) {
    if ($null -eq $A -or $null -eq $B -or $A.Length -ne $B.Length) { return $false }
    $d = 0
    for ($i = 0; $i -lt $A.Length; $i++) { $d = $d -bor ($A[$i] -bxor $B[$i]) }
    return ($d -eq 0)
}

function global:Protect-FileAes([string]$Path, [string]$OutPath, [string]$Password) {
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $salt = New-Object byte[] 16
    $iv = New-Object byte[] 16
    $rng.GetBytes($salt); $rng.GetBytes($iv); $rng.Dispose()
    $keys = Get-Pbkdf2Sha256 $Password $salt $global:MmCryptIter 64
    $ek = New-Object byte[] 32; $mk = New-Object byte[] 32
    [System.Array]::Copy($keys, 0, $ek, 0, 32); [System.Array]::Copy($keys, 32, $mk, 0, 32)
    $tmp = $OutPath + '.yaziliyor'
    $aes = [System.Security.Cryptography.Aes]::Create()
    $hmac = New-Object System.Security.Cryptography.HMACSHA256
    $inFs = $null; $outFs = $null
    try {
        $aes.KeySize = 256
        $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
        $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
        $aes.Key = $ek; $aes.IV = $iv
        $hmac.Key = $mk
        $inFs = New-Object System.IO.FileStream -ArgumentList $Path, ([System.IO.FileMode]::Open), ([System.IO.FileAccess]::Read), ([System.IO.FileShare]::Read)
        $outFs = New-Object System.IO.FileStream -ArgumentList $tmp, ([System.IO.FileMode]::Create), ([System.IO.FileAccess]::Write), ([System.IO.FileShare]::None)
        # Yazılan her bayt (başlık dahil) HMAC'ten geçer
        $hs = New-Object System.Security.Cryptography.CryptoStream -ArgumentList $outFs, $hmac, ([System.Security.Cryptography.CryptoStreamMode]::Write)
        $hdr = New-Object byte[] 8
        $hdr[0] = 0x4D; $hdr[1] = 0x4D; $hdr[2] = 0x5A; $hdr[3] = 0x31
        $it = [int]$global:MmCryptIter
        $hdr[4] = [byte](($it -shr 24) -band 0xFF); $hdr[5] = [byte](($it -shr 16) -band 0xFF); $hdr[6] = [byte](($it -shr 8) -band 0xFF); $hdr[7] = [byte]($it -band 0xFF)
        $hs.Write($hdr, 0, 8); $hs.Write($salt, 0, 16); $hs.Write($iv, 0, 16)
        $enc = $aes.CreateEncryptor()
        $cs = New-Object System.Security.Cryptography.CryptoStream -ArgumentList $hs, $enc, ([System.Security.Cryptography.CryptoStreamMode]::Write)
        $buf = New-Object byte[] 1048576
        while ($true) {
            $n = $inFs.Read($buf, 0, $buf.Length)
            if ($n -le 0) { break }
            $cs.Write($buf, 0, $n)
        }
        $cs.FlushFinalBlock()
        # İç içe CryptoStream'de dış akışın son bloğu kendiliğinden yazılır; yalnızca yazılmadıysa elle yazılır (iki kez çağrılırsa hata verir)
        if (-not $hs.HasFlushedFinalBlock) { $hs.FlushFinalBlock() }
        $tag = $hmac.Hash
        $outFs.Write($tag, 0, $tag.Length)
        $outFs.Flush()
    } finally {
        if ($null -ne $inFs) { $inFs.Dispose() }
        if ($null -ne $outFs) { $outFs.Dispose() }
        $aes.Dispose(); $hmac.Dispose()
    }
    if (Test-Path -LiteralPath $OutPath) { Remove-Item -LiteralPath $OutPath -Force }
    [System.IO.File]::Move($tmp, $OutPath)
}

function global:Unprotect-FileAes([string]$Path, [string]$OutPath, [string]$Password) {
    $inFs = New-Object System.IO.FileStream -ArgumentList $Path, ([System.IO.FileMode]::Open), ([System.IO.FileAccess]::Read), ([System.IO.FileShare]::Read)
    $tmp = $OutPath + '.yaziliyor'
    $outFs = $null
    $aes = [System.Security.Cryptography.Aes]::Create()
    $hmac = New-Object System.Security.Cryptography.HMACSHA256
    $ok = $false
    try {
        $total = [long]$inFs.Length
        if ($total -lt 88) { throw 'Bu bir Multimizer şifreli dosyası değil (çok kısa).' }
        $hdr = New-Object byte[] 40
        $r = 0
        while ($r -lt 40) { $k = $inFs.Read($hdr, $r, 40 - $r); if ($k -le 0) { break }; $r += $k }
        if ($r -ne 40 -or $hdr[0] -ne 0x4D -or $hdr[1] -ne 0x4D -or $hdr[2] -ne 0x5A -or $hdr[3] -ne 0x31) { throw 'Bu bir Multimizer şifreli dosyası değil.' }
        $it = ([int]$hdr[4] -shl 24) -bor ([int]$hdr[5] -shl 16) -bor ([int]$hdr[6] -shl 8) -bor [int]$hdr[7]
        if ($it -lt 10000 -or $it -gt 5000000) { throw 'Dosya başlığı bozuk.' }
        $ctLen = $total - 40 - 32
        if (($ctLen % 16) -ne 0) { throw 'Dosya bozuk ya da eksik.' }
        $salt = New-Object byte[] 16; $iv = New-Object byte[] 16
        [System.Array]::Copy($hdr, 8, $salt, 0, 16); [System.Array]::Copy($hdr, 24, $iv, 0, 16)
        $keys = Get-Pbkdf2Sha256 $Password $salt $it 64
        $ek = New-Object byte[] 32; $mk = New-Object byte[] 32
        [System.Array]::Copy($keys, 0, $ek, 0, 32); [System.Array]::Copy($keys, 32, $mk, 0, 32)
        # 1. geçiş: bütünlük ve parola doğrulaması (çözmeden önce)
        $hmac.Key = $mk
        [void]$hmac.TransformBlock($hdr, 0, 40, $null, 0)
        $buf = New-Object byte[] 1048576
        $left = $ctLen
        while ($left -gt 0) {
            $want = [int][math]::Min([long]$buf.Length, $left)
            $n = $inFs.Read($buf, 0, $want)
            if ($n -le 0) { throw 'Dosya okunamadı.' }
            [void]$hmac.TransformBlock($buf, 0, $n, $null, 0)
            $left -= $n
        }
        [void]$hmac.TransformFinalBlock($buf, 0, 0)
        $tag = New-Object byte[] 32
        $r = 0
        while ($r -lt 32) { $k = $inFs.Read($tag, $r, 32 - $r); if ($k -le 0) { break }; $r += $k }
        if (-not (Test-BytesEqual $tag $hmac.Hash)) { throw 'Parola yanlış ya da dosya değiştirilmiş.' }
        # 2. geçiş: çöz
        $aes.KeySize = 256
        $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
        $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
        $aes.Key = $ek; $aes.IV = $iv
        [void]$inFs.Seek(40, [System.IO.SeekOrigin]::Begin)
        $outFs = New-Object System.IO.FileStream -ArgumentList $tmp, ([System.IO.FileMode]::Create), ([System.IO.FileAccess]::Write), ([System.IO.FileShare]::None)
        $dec = $aes.CreateDecryptor()
        $cs = New-Object System.Security.Cryptography.CryptoStream -ArgumentList $outFs, $dec, ([System.Security.Cryptography.CryptoStreamMode]::Write)
        $left = $ctLen
        while ($left -gt 0) {
            $want = [int][math]::Min([long]$buf.Length, $left)
            $n = $inFs.Read($buf, 0, $want)
            if ($n -le 0) { throw 'Dosya okunamadı.' }
            $cs.Write($buf, 0, $n)
            $left -= $n
        }
        $cs.FlushFinalBlock()
        $outFs.Flush()
        $ok = $true
    } finally {
        $inFs.Dispose()
        if ($null -ne $outFs) { $outFs.Dispose() }
        $aes.Dispose(); $hmac.Dispose()
        if (-not $ok -and (Test-Path -LiteralPath $tmp)) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }
    if (Test-Path -LiteralPath $OutPath) { Remove-Item -LiteralPath $OutPath -Force }
    [System.IO.File]::Move($tmp, $OutPath)
}

function global:Get-FreeFileName([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $Path }
    $dir = [System.IO.Path]::GetDirectoryName($Path)
    $base = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    $ext = [System.IO.Path]::GetExtension($Path)
    for ($i = 2; $i -lt 1000; $i++) {
        $c = Join-Path $dir ($base + ' (' + [string]$i + ')' + $ext)
        if (-not (Test-Path -LiteralPath $c)) { return $c }
    }
    return (Join-Path $dir ($base + '-' + [System.Guid]::NewGuid().ToString('N') + $ext))
}

# P: Mode ('Enc' | 'Dec'), Paths, Password.  Özgün dosyalara dokunulmaz; sonuç yanlarına yazılır.
function global:Job_Crypt($P) {
    $mode = [string]$P.Mode
    $pw = [string]$P.Password
    $paths = @($P.Paths | ForEach-Object { [string]$_ } | Where-Object { $_ -ne '' })
    if ($pw.Length -lt 8) { Write-WhLog 'Parola en az 8 karakter olmalı.' 'ERR'; return @{ Ok = $false; Done = 0; Failed = $paths.Count; Outputs = @() } }
    $done = 0; $failed = 0
    $outs = New-Object System.Collections.ArrayList
    Set-JobProgress 0 $paths.Count $(if ($mode -eq 'Enc') { 'Şifreleniyor' } else { 'Çözülüyor' })
    foreach ($p in $paths) {
        if (Test-JobCancel) { break }
        try {
            if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { throw 'Dosya bulunamadı.' }
            if ($mode -eq 'Enc') {
                $out = Get-FreeFileName ($p + $global:MmCryptExt)
                Protect-FileAes $p $out $pw
                Write-WhLog ('Şifrelendi: ' + $out) 'OK'
            } else {
                $name = $p
                if ($p.EndsWith($global:MmCryptExt, [StringComparison]::OrdinalIgnoreCase)) { $name = $p.Substring(0, $p.Length - $global:MmCryptExt.Length) } else { $name = $p + '.cozuldu' }
                $out = Get-FreeFileName $name
                Unprotect-FileAes $p $out $pw
                Write-WhLog ('Çözüldü: ' + $out) 'OK'
            }
            [void]$outs.Add($out)
            $done++
        } catch {
            $failed++
            Write-WhLog ((Split-Path -Leaf $p) + ': ' + $_.Exception.Message) 'ERR'
        }
        Step-JobProgress
    }
    return @{ Ok = ($failed -eq 0 -and $done -gt 0); Done = $done; Failed = $failed; Outputs = $outs.ToArray(); Mode = $mode }
}
