<#
    Ozet-Guncelle.ps1  -  gelistiriciler icin
    veri\ ve Eklenti\ klasorlerindeki dosyalarin SHA-256 ozetlerini Multimizer.ps1 icindeki kayitla karsilastirir.
    Multimizer.ps1 bu dosyalari yuklemeden once ozetlerini dogrular; bir dosyayi degistirdiyseniz kaydi yenilemeniz gerekir.

    Kullanim (Multimizer.ps1 ile ayni klasorden ya da araclar\ klasorunden):
      powershell -NoProfile -File araclar\Ozet-Guncelle.ps1           yalnizca karsilastirir
      powershell -NoProfile -File araclar\Ozet-Guncelle.ps1 -Yaz      Multimizer.ps1 icindeki kaydi yeniler

    Cikis kodu: 0 = tum ozetler tutuyor (ya da -Yaz ile yenilendi), 1 = uyusmazlik var, 2 = hata.
    Yeni bir eklenti dosyasi eklediyseniz ayrica $script:ExtOf tablosuna hangi is isminin hangi eklentiyi yukledigini yazin.
#>
param([switch]$Yaz, [string]$Klasor = '')
$ErrorActionPreference = 'Stop'

if ($Klasor -eq '') {
    $here = Split-Path -Parent $MyInvocation.MyCommand.Path
    if (Test-Path -LiteralPath (Join-Path $here 'Multimizer.ps1')) { $Klasor = $here } else { $Klasor = Split-Path -Parent $here }
}
$main = Join-Path $Klasor 'Multimizer.ps1'
if (-not (Test-Path -LiteralPath $main)) { Write-Host ('Multimizer.ps1 bulunamadi: ' + $main); exit 2 }

# Multimizer.ps1 icindeki Get-PackFileText ile ayni kural: UTF-8 (imza yok sayilir), satir sonlari LF'ye cevrilir
function Get-FileSha([string]$Path) {
    $txt = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8).Replace("`r`n", "`n")
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $b = $null
    try { $b = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($txt)) } finally { $sha.Dispose() }
    return (([System.BitConverter]::ToString($b)) -replace '-', '').ToLowerInvariant()
}

# Derleme sirasindaki kuralla ayni: veri\ ve Eklenti\ altindaki (alt klasorler dahil) .ps1 .txt .json .csv .lang dosyalari
$disk = @{}
$baseFull = [System.IO.Path]::GetFullPath($Klasor).TrimEnd([char]92, [char]47)
foreach ($sub in @('veri', 'Eklenti')) {
    $d = Join-Path $Klasor $sub
    if (-not (Test-Path -LiteralPath $d -PathType Container)) { continue }
    foreach ($f in @(Get-ChildItem -LiteralPath $d -File -Recurse)) {
        $ext = $f.Extension.ToLowerInvariant()
        if (@('.ps1', '.txt', '.json', '.csv', '.lang') -notcontains $ext) { continue }
        $rel = $f.FullName.Substring($baseFull.Length).TrimStart([char]92, [char]47).Replace([string][char]92, '/')
        $disk[$rel] = Get-FileSha $f.FullName
    }
}

$src = [System.IO.File]::ReadAllText($main, [System.Text.Encoding]::ASCII)
$rx = [regex]::new('(?ms)^\$script:PackHash = @\{\r?\n(?<body>.*?)^\}', 'None')
$m = $rx.Match($src)
if (-not $m.Success) { Write-Host 'Multimizer.ps1 icinde $script:PackHash kaydi bulunamadi.'; exit 2 }
$reg = @{}
foreach ($ln in ($m.Groups['body'].Value -split "\r?\n")) {
    $lm = [regex]::Match($ln, "^\s*'(?<k>[^']+)'\s*=\s*'(?<v>[0-9a-f]{64})'\s*$")
    if ($lm.Success) { $reg[$lm.Groups['k'].Value] = $lm.Groups['v'].Value }
}

$keys = New-Object System.Collections.ArrayList
foreach ($k in $disk.Keys) { [void]$keys.Add([string]$k) }
foreach ($k in $reg.Keys) { if (-not $disk.ContainsKey($k)) { [void]$keys.Add([string]$k) } }
$sorted = [string[]]$keys.ToArray()
[Array]::Sort($sorted, [StringComparer]::Ordinal)

$bad = 0
foreach ($k in $sorted) {
    if (-not $disk.ContainsKey($k)) { Write-Host ('  YOK       ' + $k + '  (kayitta var, diskte yok)'); $bad++ }
    elseif (-not $reg.ContainsKey($k)) { Write-Host ('  YENI      ' + $k + '  (kayitta yok)'); $bad++ }
    elseif ($reg[$k] -ne $disk[$k]) { Write-Host ('  DEGISMIS  ' + $k); $bad++ }
    else { Write-Host ('  tamam     ' + $k) }
}

if ($bad -eq 0) { Write-Host 'Tum ozetler tutuyor.'; exit 0 }
if (-not $Yaz) { Write-Host ([string]$bad + ' uyusmazlik var. Kaydi yenilemek icin -Yaz ile calistirin.'); exit 1 }

# Kaydi diskteki dosyalara gore yeniden yaz (diskte olmayanlar kayittan cikar)
$nl = "`n"
if ($m.Value.Contains("`r`n")) { $nl = "`r`n" }
$body = New-Object System.Text.StringBuilder
foreach ($k in $sorted) {
    if ($disk.ContainsKey($k)) { [void]$body.Append("    '" + $k + "' = '" + $disk[$k] + "'" + $nl) }
}
$newBlock = '$script:PackHash = @{' + $nl + $body.ToString() + '}'
$out = $src.Substring(0, $m.Index) + $newBlock + $src.Substring($m.Index + $m.Length)
[System.IO.File]::WriteAllText($main, $out, (New-Object System.Text.ASCIIEncoding))
Write-Host ('Multimizer.ps1 icindeki ozet kaydi yenilendi (' + [string]$disk.Count + ' dosya).')
exit 0
