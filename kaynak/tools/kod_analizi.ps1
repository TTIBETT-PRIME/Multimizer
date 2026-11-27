# Multimizer statik kod analizi: PSScriptAnalyzer (kural kumesi: depo kokundeki PSScriptAnalyzerSettings.psd1)
# ve InjectionHunter (Microsoft'tan Lee Holmes'un kod enjeksiyonu kurallari). Yalnizca okur, hicbir dosyayi degistirmez.
# Gerekli moduller (PowerShell Galerisi):  Install-Module PSScriptAnalyzer, InjectionHunter -Scope CurrentUser
# Kullanim:  pwsh -NoProfile -File kaynak/tools/kod_analizi.ps1 [-Kok .] [-Sarif psa.sarif] [-Ozet ozet.md]
# Cikis kodu: 0 = Error onemde bulgu yok, 1 = en az bir Error / ParseError bulgusu, 2 = modul ya da ayar dosyasi yok.
param([string]$Kok = '.', [string]$Sarif = '', [string]$Ozet = '')
$ErrorActionPreference = 'Stop'

function ConvertTo-SarifLevel([string]$Severity) {
    switch ($Severity) {
        'Error' { return 'error' }
        'ParseError' { return 'error' }
        'Warning' { return 'warning' }
        default { return 'note' }
    }
}

# Bulgu dosyasinin depo kokune gore yolu (SARIF ileri egik cizgi ister)
function Get-RelUri([string]$File, [string]$Root) {
    if ([string]::IsNullOrEmpty($File)) { return 'bilinmiyor' }
    $r = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    $full = [System.IO.Path]::GetFullPath($File)
    foreach ($sep in @('\', '/')) {
        if ($full.StartsWith($r + $sep, [System.StringComparison]::OrdinalIgnoreCase)) { $full = $full.Substring($r.Length + 1); break }
    }
    return ($full -replace '\\', '/')
}

# PSScriptAnalyzer bulgularini SARIF 2.1.0 bicimine cevirir (GitHub Code scanning bu bicimi okur)
function ConvertTo-PsaSarif($Records, [string]$Root, [string]$Version) {
    $rules = [ordered]@{}
    $results = New-Object System.Collections.Generic.List[object]
    foreach ($rec in @($Records)) {
        if ($null -eq $rec) { continue }
        $id = [string]$rec.RuleName
        if (-not $rules.Contains($id)) { $rules[$id] = [ordered]@{ id = $id; name = $id; shortDescription = [ordered]@{ text = $id } } }
        $line = 1
        try { $line = [int]$rec.Line } catch { $line = 1 }
        if ($line -lt 1) { $line = 1 }
        $col = 1
        try { $col = [int]$rec.Column } catch { $col = 1 }
        if ($col -lt 1) { $col = 1 }
        $region = [ordered]@{ startLine = $line; startColumn = $col }
        $phys = [ordered]@{ artifactLocation = [ordered]@{ uri = (Get-RelUri ([string]$rec.ScriptPath) $Root) }; region = $region }
        $results.Add([ordered]@{ ruleId = $id; level = (ConvertTo-SarifLevel ([string]$rec.Severity)); message = [ordered]@{ text = [string]$rec.Message }; locations = @([ordered]@{ physicalLocation = $phys }) })
    }
    $driver = [ordered]@{ name = 'PSScriptAnalyzer'; version = $Version; informationUri = 'https://github.com/PowerShell/PSScriptAnalyzer'; rules = @($rules.Values) }
    return [ordered]@{ '$schema' = 'https://json.schemastore.org/sarif-2.1.0.json'; version = '2.1.0'; runs = @([ordered]@{ tool = [ordered]@{ driver = $driver }; results = $results.ToArray() }) }
}

# Ozet satirlari (Markdown): kural basina sayi ve onem sirasina gore ilk bulgular
function Get-PsaSummary($Records, [string]$Root, [string]$Head, [int]$Max = 60) {
    $out = New-Object System.Collections.Generic.List[string]
    $all = @($Records | Where-Object { $null -ne $_ })
    $out.Add('## Kod analizi')
    $out.Add('')
    $out.Add($Head + ', ' + [string]$all.Count + ' bulgu.')
    if ($all.Count -eq 0) { return $out.ToArray() }
    $out.Add('')
    $out.Add('| Kural | Onem | Sayi |')
    $out.Add('|---|---|---|')
    foreach ($g in @($all | Group-Object -Property RuleName | Sort-Object -Property Count -Descending)) {
        $out.Add('| ' + [string]$g.Name + ' | ' + [string]$g.Group[0].Severity + ' | ' + [string]$g.Count + ' |')
    }
    $out.Add('')
    $out.Add('Onem sirasina gore ilk ' + [string]([Math]::Min($Max, $all.Count)) + ' bulgu:')
    $out.Add('')
    $rank = @{ 'ParseError' = 0; 'Error' = 1; 'Warning' = 2; 'Information' = 3 }
    $sorted = @($all | Sort-Object -Property @{ Expression = { $k = [string]$_.Severity; if ($rank.ContainsKey($k)) { $rank[$k] } else { 9 } } }, @{ Expression = { [string]$_.ScriptPath } }, @{ Expression = { [int]$_.Line } })
    foreach ($r in @($sorted | Select-Object -First $Max)) {
        $msg = ([string]$r.Message) -replace '[\r\n]+', ' ' -replace '\|', '/'
        if ($msg.Length -gt 220) { $msg = $msg.Substring(0, 220) + '...' }
        $out.Add('- `' + (Get-RelUri ([string]$r.ScriptPath) $Root) + ':' + [string]$r.Line + '` ' + [string]$r.Severity + ' ' + [string]$r.RuleName + ': ' + $msg)
    }
    return $out.ToArray()
}

# Yalnizca islevler isteniyorsa (nokta ile yuklenince) burada dur
if ($MyInvocation.InvocationName -eq '.') { return }

$psa = @(Get-Module -ListAvailable -Name PSScriptAnalyzer | Sort-Object -Property Version -Descending)
if ($psa.Count -eq 0) { Write-Output 'PSScriptAnalyzer kurulu degil: Install-Module PSScriptAnalyzer -Scope CurrentUser'; exit 2 }
Import-Module $psa[0].Path
$kokTam = [System.IO.Path]::GetFullPath($Kok)
$ayar = Join-Path $kokTam 'PSScriptAnalyzerSettings.psd1'
if (-not (Test-Path -LiteralPath $ayar)) { Write-Output ('ayar dosyasi yok: ' + $ayar); exit 2 }
$hedef = @(@('Multimizer.ps1', 'Tani.ps1', 'Acilis.ps1', 'Eklenti', 'araclar') | ForEach-Object { Join-Path $kokTam $_ } | Where-Object { Test-Path -LiteralPath $_ })
$kayit = New-Object System.Collections.Generic.List[object]
$sw = [System.Diagnostics.Stopwatch]::StartNew()
foreach ($h in $hedef) {
    foreach ($r in @(Invoke-ScriptAnalyzer -Path $h -Recurse -Settings $ayar)) { $kayit.Add($r) }
}
$ih = @(Get-Module -ListAvailable -Name InjectionHunter | Sort-Object -Property Version -Descending)
$bas = 'PSScriptAnalyzer ' + [string]$psa[0].Version
if ($ih.Count -gt 0) {
    $bas = $bas + ' + InjectionHunter ' + [string]$ih[0].Version
    foreach ($h in $hedef) {
        foreach ($r in @(Invoke-ScriptAnalyzer -Path $h -Recurse -CustomRulePath $ih[0].Path)) { $kayit.Add($r) }
    }
} else {
    $bas = $bas + ' (InjectionHunter kurulu degil; enjeksiyon kurallari atlandi)'
}
$bas = $bas + ', ' + [string][int]$sw.Elapsed.TotalSeconds + ' sn'
$lines = @(Get-PsaSummary $kayit.ToArray() $kokTam $bas)
foreach ($l in $lines) { Write-Output $l }
if ($Ozet -ne '') { Add-Content -LiteralPath $Ozet -Value $lines -Encoding utf8 }
if ($Sarif -ne '') {
    $doc = ConvertTo-PsaSarif $kayit.ToArray() $kokTam ([string]$psa[0].Version)
    Set-Content -LiteralPath $Sarif -Value ($doc | ConvertTo-Json -Depth 32) -Encoding utf8
}
$hata = @($kayit | Where-Object { @('Error', 'ParseError') -contains [string]$_.Severity }).Count
if ($hata -gt 0) { exit 1 }
exit 0
