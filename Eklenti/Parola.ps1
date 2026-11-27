# ==================================================================
#  Multimizer eklentisi: parola üretici (Araçlar > Yardımcılar).
#  Rastgele sayılar işletim sisteminin kriptografik üretecinden alınır. Parola hiçbir yere kaydedilmez ve gönderilmez.
#  Bu dosya Multimizer.ps1 tarafından gerektiğinde yüklenir; tek başına çalıştırılmaz. Özeti ana betikte yazılıdır.
# ==================================================================

# Kriptografik rastgele dizin, 0..Max-1 (eşit olasılık: sınır dışı baytlar atılır)
function global:Get-SecureIndex($Rng, [int]$Max) {
    if ($Max -le 1) { return 0 }
    $limit = 256 - (256 % $Max)
    $b = New-Object byte[] 1
    while ($true) {
        $Rng.GetBytes($b)
        if ([int]$b[0] -lt $limit) { return ([int]$b[0] % $Max) }
    }
}

# Sets: karakter kümeleri. Her kümeden en az bir karakter bulunur; sıra karıştırılır. Uzunluk 8..64.
function global:New-RandomPassword([int]$Length, [string[]]$Sets) {
    $sets = @($Sets | Where-Object { [string]$_ -ne '' })
    if ($sets.Count -eq 0) { throw 'Karakter kümesi yok.' }
    if ($Length -lt 8) { $Length = 8 }
    if ($Length -gt 64) { $Length = 64 }
    $pool = ($sets -join '')
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $ch = New-Object char[] $Length
        for ($i = 0; $i -lt $Length; $i++) {
            if ($i -lt $sets.Count) { $s = [string]$sets[$i]; $ch[$i] = $s[(Get-SecureIndex $rng $s.Length)] }
            else { $ch[$i] = $pool[(Get-SecureIndex $rng $pool.Length)] }
        }
        # Fisher-Yates: zorunlu karakterler başta kalmasın
        for ($i = $Length - 1; $i -gt 0; $i--) {
            $j = Get-SecureIndex $rng ($i + 1)
            $t = $ch[$i]; $ch[$i] = $ch[$j]; $ch[$j] = $t
        }
        return (-join $ch)
    } finally { try { $rng.Dispose() } catch { } }
}
