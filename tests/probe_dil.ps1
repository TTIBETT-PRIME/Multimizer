. "$PSScriptRoot/lib.ps1"
# Dil kapsami sondasi (test degil): MM_PROBE_DIL dili icin MM_PROBE_IN dosyasindaki her satiri Tr'den gecirir.
# Cikti: <durum>\t<metin>\t<ceviri>   durum: C = cevrildi, U = degismedi
Import-Fn 'Get-LangUnescaped', 'Add-LangTemplate', 'Read-LangPack', 'Read-LangHeader', 'Get-LangList', 'Find-LangForCulture', 'Get-SystemLangCode',
    'Resolve-LangCode', 'Import-LangPackFile', 'Set-LangActive', 'Initialize-Lang', 'Enable-LangTrack', 'Find-LangIn', 'Format-LangTemplate', 'Find-LangText', 'Find-LangTag', 'Find-LangJoined', 'Find-LangDirect', 'Get-LangPunct', 'Convert-LangTrLower', 'Convert-LangTrUpperFirst', 'Convert-LangUpper',
    'Add-LangMiss', 'Tr', 'Format-Tr', 'Get-LangPercentStyle', 'Convert-LangPercent', 'Format-Percent', 'Convert-LangBidi'
Import-Var 'LangPctRx', 'LangBidiRx'
$script:LangOn = $false; $script:LangCode = 'tr'; $script:LangTag = 'tr-TR'; $script:LangRtl = $false; $script:LangName = ''
$script:LangPrimary = $null; $script:LangFallback = $null; $script:LangList = $null; $script:LangTrack = $false; $script:LangMiss = $null; $script:LangSeen = $null; $script:LangPctStyle = 0; $script:LangOut = $null
$script:LangKeyLen = 5
$script:LangPrefixRx = New-Object System.Text.RegularExpressions.Regex(('^(\s*(?:>>>|' + [char]0x2192 + ')\s+)(.+)$'), [System.Text.RegularExpressions.RegexOptions]::Singleline)
$script:LangBracketRx = New-Object System.Text.RegularExpressions.Regex('^(.*?)\s{2}\[(.+)\]\s*$', [System.Text.RegularExpressions.RegexOptions]::Singleline)
$script:LangCountRx = New-Object System.Text.RegularExpressions.Regex('^(.+?) \(([^()]+)\)$', [System.Text.RegularExpressions.RegexOptions]::Singleline)
$script:LangUpperRx = New-Object System.Text.RegularExpressions.Regex('\p{Lu}{2}')
$script:LangLowerRx = New-Object System.Text.RegularExpressions.Regex('\p{Ll}')
$script:LangUpperCulture = $null
$script:LangFull = $true
$script:LangLetterRx = New-Object System.Text.RegularExpressions.Regex('\p{L}{2}')
$script:LangLogRx = New-Object System.Text.RegularExpressions.Regex('^(\d\d:\d\d:\d\d\s+\S+\s+)(.+)$', [System.Text.RegularExpressions.RegexOptions]::Singleline)
$script:Settings = @{ Language = 'auto' }
$script:StLoading = $false
$Dil = ''
$env:MM_DIL = ''; $env:MM_DIL_IZLE = ''
$script:T_App = (Join-Path (Split-Path $script:TestDir -Parent) 'build/static/veri/dil')
if ($env:MM_PROBE_APP) { $script:T_App = $env:MM_PROBE_APP }
$script:T_Usr = (Join-Path ([System.IO.Path]::GetTempPath()) 'mm-probe-yok')
function Get-LangFolders { return @($script:T_App, $script:T_Usr) }
$code = $env:MM_PROBE_DIL; if (-not $code) { $code = 'en' }
Set-LangActive $code
$lines = [System.IO.File]::ReadAllLines($env:MM_PROBE_IN, [System.Text.Encoding]::UTF8)
$sb = New-Object System.Text.StringBuilder
foreach ($l in $lines) {
    if ($l.Length -eq 0) { continue }
    $r = Tr $l
    $st = 'C'; if ($r -ceq $l) { $st = 'U' }
    [void]$sb.Append($st + "`t" + $l.Replace("`n", '\n') + "`t" + $r.Replace("`n", '\n') + "`n")
}
[System.IO.File]::WriteAllText($env:MM_PROBE_OUT, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
Write-Host ('sonda: ' + $lines.Count + ' satir')
