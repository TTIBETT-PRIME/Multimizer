# Multimizer statik denetimi (AST). Kullanim: pwsh -File check.ps1 -Path out/Multimizer.ps1 [-MakeKnown]
param(
    [string]$Path,
    [string]$Known = (Join-Path $PSScriptRoot 'known_cmds.txt'),
    [switch]$MakeKnown
)
$ErrorActionPreference = 'Stop'
$issues = New-Object System.Collections.ArrayList
function Add-Issue([string]$Sec, [string]$Msg) { [void]$issues.Add(('[' + $Sec + '] ' + $Msg)) }

$dir = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($Path))
$files = New-Object System.Collections.ArrayList
[void]$files.Add([System.IO.Path]::GetFullPath($Path))
$ext = Join-Path $dir 'Eklenti'
if (Test-Path -LiteralPath $ext) { foreach ($x in @(Get-ChildItem -LiteralPath $ext -Filter '*.ps1' | Sort-Object Name)) { [void]$files.Add($x.FullName) } }

$asts = @{}
foreach ($f in $files) {
    $tk = $null; $er = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$tk, [ref]$er)
    $asts[$f] = $ast
    foreach ($e in @($er)) { Add-Issue 'parse' ([System.IO.Path]::GetFileName($f) + ':' + $e.Extent.StartLineNumber + ' ' + $e.Message) }
}
if ($issues.Count -gt 0) { $issues | ForEach-Object { $_ }; exit 1 }

# ---- islev tanimlari
$defined = @{}
$fnAsts = New-Object System.Collections.ArrayList
foreach ($f in $files) {
    foreach ($fn in @($asts[$f].FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))) {
        $nm = ($fn.Name -replace '^(global|script|local):', '')
        $defined[$nm.ToLowerInvariant()] = $true
        [void]$fnAsts.Add(@{ File = $f; Ast = $fn; Name = $nm })
    }
}

$mainAst = $asts[[System.IO.Path]::GetFullPath($Path)]

# ---- ps51: PowerShell 7'ye ozgu sozdizimi ve parametreler
$badParams = @('AsByteStream', 'AsHashtable', 'SkipHttpErrorCheck', 'Parallel', 'ThrottleLimit', 'NoEmphasis', 'EnumsAsStrings', 'Stable', 'SkipCertificateCheck', 'SkipHeaderValidation',
    'HttpVersion', 'AllowInsecureRedirect', 'Authentication', 'UseQuotes', 'QuoteFields', 'SkipEditionCheck', 'NoEnumerate', 'AsUTC', 'LeafBase', 'Extension', 'TcpPort', 'AdditionalChildPath', 'Top', 'Bottom')
$badParamCmd = @{ 'ForEach-Object' = @('Parallel', 'ThrottleLimit'); 'ConvertFrom-Json' = @('AsHashtable', 'Depth', 'NoEnumerate'); 'Get-Content' = @('AsByteStream'); 'Set-Content' = @('AsByteStream')
    'Invoke-WebRequest' = @('SkipHttpErrorCheck', 'SkipCertificateCheck', 'Authentication', 'AllowInsecureRedirect', 'HttpVersion'); 'Invoke-RestMethod' = @('SkipHttpErrorCheck', 'SkipCertificateCheck', 'Authentication', 'AllowInsecureRedirect', 'HttpVersion')
    'Sort-Object' = @('Stable', 'Top', 'Bottom'); 'Split-Path' = @('LeafBase', 'Extension'); 'Test-Connection' = @('TcpPort'); 'Get-Date' = @('AsUTC'); 'Join-Path' = @('AdditionalChildPath')
    'Select-String' = @('NoEmphasis', 'Raw'); 'ConvertTo-Json' = @('EnumsAsStrings'); 'Export-Csv' = @('UseQuotes', 'QuoteFields'); 'Import-Module' = @('SkipEditionCheck') }
$allNodes = $mainAst.FindAll({ param($n) $true }, $true)
foreach ($f in $files) {
    $nodes = $asts[$f].FindAll({ param($n) $true }, $true)
    $bn = [System.IO.Path]::GetFileName($f)
    foreach ($n in $nodes) {
        $tn = $n.GetType().Name
        if ($tn -eq 'TernaryExpressionAst' -or $tn -eq 'PipelineChainAst') { Add-Issue 'ps51' ($bn + ':' + $n.Extent.StartLineNumber + ' ' + $tn) }
        elseif ($tn -eq 'BinaryExpressionAst' -and [string]$n.Operator -in @('QuestionQuestion')) { Add-Issue 'ps51' ($bn + ':' + $n.Extent.StartLineNumber + ' ??') }
        elseif ($tn -eq 'AssignmentStatementAst' -and [string]$n.Operator -eq 'QuestionQuestionEquals') { Add-Issue 'ps51' ($bn + ':' + $n.Extent.StartLineNumber + ' ??=') }
        elseif (($tn -eq 'MemberExpressionAst' -or $tn -eq 'InvokeMemberExpressionAst' -or $tn -eq 'IndexExpressionAst') -and $n.PSObject.Properties['NullConditional'] -and $n.NullConditional -eq $true) {
            Add-Issue 'ps51' ($bn + ':' + $n.Extent.StartLineNumber + ' ?. / ?[]')
        }
        elseif ($tn -eq 'ScriptBlockAst' -and $n.PSObject.Properties['CleanBlock'] -and $null -ne $n.CleanBlock) { Add-Issue 'ps51' ($bn + ':' + $n.Extent.StartLineNumber + ' clean blogu') }
        elseif ($tn -eq 'CommandAst') {
            $cn = [string]$n.GetCommandName()
            if ($badParamCmd.ContainsKey($cn)) {
                foreach ($el in $n.CommandElements) {
                    if ($el -is [System.Management.Automation.Language.CommandParameterAst]) {
                        foreach ($bp in $badParamCmd[$cn]) { if ($el.ParameterName -eq $bp) { Add-Issue 'ps51' ($bn + ':' + $n.Extent.StartLineNumber + ' ' + $cn + ' -' + $el.ParameterName + ' (5.1 desteklemez)') } }
                    }
                }
            }
            if ($cn -eq 'Join-Path') {
                $pos = 0
                foreach ($el in $n.CommandElements | Select-Object -Skip 1) { if ($el -isnot [System.Management.Automation.Language.CommandParameterAst]) { $pos++ } }
                $named = @($n.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] }).Count
                if ($pos -gt 2 -and $named -eq 0) { Add-Issue 'ps51' ($bn + ':' + $n.Extent.StartLineNumber + ' Join-Path ikiden fazla konumsal bagimsiz degisken (5.1 desteklemez)') }
            }
        }
    }
}
# .NET Core'a ozgu cagrilar (Windows PowerShell 5.1 = .NET Framework 4.x)
$netCore = @('::ProcessId', '[Math]::Clamp', '::GetRelativePath', '::ToHexString', '::FromHexString', '::GetElapsedTime', '[Array]::Fill', '[IO.Path]::Join(', '[System.IO.Path]::Join(', '.TryAdd(', '.GetValueOrDefault(', '[System.Random]::Shared', '[Random]::Shared', 'RandomNumberGenerator]::GetBytes(', 'RandomNumberGenerator]::Fill(', '.StartsWith([char]', '.EndsWith([char]', '::IsOSPlatform', '[Environment]::CurrentManagedThreadId')
foreach ($f in $files) {
    $txt = [System.IO.File]::ReadAllText($f)
    $bn = [System.IO.Path]::GetFileName($f)
    foreach ($pat in $netCore) {
        $i = $txt.IndexOf($pat, [System.StringComparison]::Ordinal)
        if ($i -ge 0) { Add-Issue 'ps51' ($bn + ':' + ($txt.Substring(0, $i).Split("`n").Count) + ' .NET Framework 4.x\''te yok: ' + $pat) }
    }
}

# ---- shadow: otomatik degiskenlerin ustune yazma
$auto = @('input', 'args', 'matches', 'error', 'host', 'home', 'pid', 'pwd', 'foreach', 'switch', 'this', 'psitem', 'true', 'false', 'null', 'profile', 'psboundparameters', 'myinvocation', 'psscriptroot', 'pscommandpath', 'shellid', 'stacktrace', 'lastexitcode', 'pshome', 'executioncontext', 'psversiontable', 'psculture', 'psuiculture', 'psedition', 'nestedpromptlevel', 'consolefilename', 'psscriptroot')
foreach ($f in $files) {
    $bn = [System.IO.Path]::GetFileName($f)
    foreach ($n in $asts[$f].FindAll({ param($x) $x -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true)) {
        $l = $n.Left
        if ($l -is [System.Management.Automation.Language.ConvertExpressionAst]) { $l = $l.Child }
        if ($l -is [System.Management.Automation.Language.VariableExpressionAst]) {
            $vn = $l.VariablePath.UserPath.ToLowerInvariant()
            if ($vn -notmatch ':' -and $auto -contains $vn) { Add-Issue 'shadow' ($bn + ':' + $n.Extent.StartLineNumber + ' $' + $vn + ' otomatik degiskenin ustune yazilir') }
        }
    }
    foreach ($p in $asts[$f].FindAll({ param($x) $x -is [System.Management.Automation.Language.ParameterAst] }, $true)) {
        $vn = $p.Name.VariablePath.UserPath.ToLowerInvariant()
        if ($auto -contains $vn) { Add-Issue 'shadow' ($bn + ':' + $p.Extent.StartLineNumber + ' parametre $' + $vn + ' otomatik degiskenle cakisir') }
    }
}

# ---- sarmal donus: "return , $dizi" donduren islev @( ) icinde cagrilirsa dizi bir kat daha sarilir
$commaFns = @{}
foreach ($fa in $fnAsts) {
    foreach ($r in $fa.Ast.FindAll({ param($x) $x -is [System.Management.Automation.Language.ReturnStatementAst] }, $true)) {
        $pl = $r.Pipeline
        if ($null -ne $pl -and $pl -is [System.Management.Automation.Language.PipelineAst]) {
            $ex = $pl.PipelineElements[0]
            if ($ex -is [System.Management.Automation.Language.CommandExpressionAst]) {
                $xe = $ex.Expression
                if (($xe -is [System.Management.Automation.Language.UnaryExpressionAst] -and [string]$xe.TokenKind -eq 'Comma') -or ($xe -is [System.Management.Automation.Language.ArrayLiteralAst] -and @($xe.Elements).Count -eq 1)) {
                    $commaFns[$fa.Name.ToLowerInvariant()] = $true
                }
            }
        }
    }
}
foreach ($f in $files) {
    $bn = [System.IO.Path]::GetFileName($f)
    foreach ($n in $asts[$f].FindAll({ param($x) $x -is [System.Management.Automation.Language.ArrayExpressionAst] }, $true)) {
        $st = @($n.SubExpression.Statements)
        if ($st.Count -eq 1 -and $st[0] -is [System.Management.Automation.Language.PipelineAst] -and $st[0].PipelineElements.Count -eq 1 -and $st[0].PipelineElements[0] -is [System.Management.Automation.Language.CommandAst]) {
            $cn = [string]$st[0].PipelineElements[0].GetCommandName()
            if ($cn -ne '' -and $commaFns.ContainsKey($cn.ToLowerInvariant())) { Add-Issue 'sarmal-donus' ($bn + ':' + $n.Extent.StartLineNumber + ' @(' + $cn + ' ...) : islev "return , dizi" kullanir') }
        }
    }
}

# ---- komut-modu: "(Islev arg + 'metin')" komut kipinde okunur, "+" bir bagimsiz degisken olur ve cagri hata verir
foreach ($f in $files) {
    $bn = [System.IO.Path]::GetFileName($f)
    foreach ($c in $asts[$f].FindAll({ param($x) $x -is [System.Management.Automation.Language.CommandAst] }, $true)) {
        $els = @($c.CommandElements)
        for ($i = 1; $i -lt $els.Count; $i++) {
            $el = $els[$i]
            if ($el -is [System.Management.Automation.Language.StringConstantExpressionAst] -and [string]$el.StringConstantType -eq 'BareWord' -and [string]$el.Value -in @('+', '*', '/', '%')) {
                Add-Issue 'komut-modu' ($bn + ':' + $c.Extent.StartLineNumber + ' "' + [string]$els[0].Extent.Text + ' ... ' + [string]$el.Value + ' ..." komut kipinde okunur; islev cagrisini parantez icine alin')
                break
            }
        }
    }
}

# ---- parametre-ezme: islevin parametresi ayni adin farkli buyuk/kucuk harfli yazimiyla ($T ve $t) atanirsa parametre sessizce ezilir
foreach ($f in $files) {
    $bn = [System.IO.Path]::GetFileName($f)
    foreach ($sb in $asts[$f].FindAll({ param($x) $x -is [System.Management.Automation.Language.ScriptBlockAst] }, $true)) {
        $pars = @()
        if ($null -ne $sb.ParamBlock) { $pars = @($sb.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath }) }
        elseif ($null -ne $sb.Parent -and $sb.Parent -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $null -ne $sb.Parent.Parameters) { $pars = @($sb.Parent.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath }) }
        if ($pars.Count -eq 0) { continue }
        foreach ($a in $sb.FindAll({ param($x) $x -is [System.Management.Automation.Language.AssignmentStatementAst] }, $false)) {
            $l = $a.Left
            if ($l -is [System.Management.Automation.Language.ConvertExpressionAst]) { $l = $l.Child }
            if ($l -isnot [System.Management.Automation.Language.VariableExpressionAst]) { continue }
            $vn = $l.VariablePath.UserPath
            foreach ($pn in $pars) {
                if ($vn -cne $pn -and $vn.ToLowerInvariant() -eq $pn.ToLowerInvariant()) {
                    # yalnizca parametrenin kendi yazimi atamadan SONRA okunuyorsa (yani eski deger bekleniyorsa) hata sayilir
                    $endOff = $a.Extent.EndOffset
                    $later = @($sb.FindAll({ param($x) $x -is [System.Management.Automation.Language.VariableExpressionAst] -and $x.VariablePath.UserPath -ceq $pn -and $x.Extent.StartOffset -gt $endOff }, $true))
                    if ($later.Count -gt 0) { Add-Issue 'parametre-ezme' ($bn + ':' + $a.Extent.StartLineNumber + ' $' + $vn + ' atamasi $' + $pn + ' parametresini ezer; $' + $pn + ' sonra okunuyor (satir ' + $later[0].Extent.StartLineNumber + ')') }
                }
            }
        }
    }
}

# ---- cekirdek-kapsam: arka plan isleri yalnizca $CoreCode ve eklenti dosyalarini yukler; arayuz bolumundeki islevler orada yoktur.
#      Cekirdek ya da eklenti kodu arayuz islevini cagirirsa is calisirken "komut bulunamadi" hatasi verir; Start-Async girisleri de cekirdekte ya da eslenmis eklentide tanimli olmalidir.
$coreAssign = $null
foreach ($a in $mainAst.FindAll({ param($x) $x -is [System.Management.Automation.Language.AssignmentStatementAst] }, $false)) {
    if ($a.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and $a.Left.VariablePath.UserPath -ceq 'CoreCode') { $coreAssign = $a }
}
if ($null -eq $coreAssign) { Add-Issue 'cekirdek-kapsam' '$CoreCode atamasi bulunamadi' }
else {
    $c0 = $coreAssign.Extent.StartOffset
    $c1 = $coreAssign.Extent.EndOffset
    $coreFns = @{}
    $uiFns = @{}
    foreach ($fa in $fnAsts) {
        if ($fa.File -ne [System.IO.Path]::GetFullPath($Path)) { continue }
        $lc = $fa.Name.ToLowerInvariant()
        if ($fa.Ast.Extent.StartOffset -ge $c0 -and $fa.Ast.Extent.EndOffset -le $c1) { $coreFns[$lc] = $true } else { $uiFns[$lc] = $true }
    }
    $extFns = @{}
    foreach ($fa in $fnAsts) { if ($fa.File -ne [System.IO.Path]::GetFullPath($Path)) { $extFns[$fa.Name.ToLowerInvariant()] = [System.IO.Path]::GetFileNameWithoutExtension($fa.File) } }
    $uiOnly = @{}
    foreach ($k in $uiFns.Keys) { if (-not $coreFns.ContainsKey($k) -and -not $extFns.ContainsKey($k)) { $uiOnly[$k] = $true } }
    $seen = @{}
    foreach ($c in $mainAst.FindAll({ param($x) $x -is [System.Management.Automation.Language.CommandAst] -and $x.Extent.StartOffset -ge $c0 -and $x.Extent.EndOffset -le $c1 }, $true)) {
        $cn = [string]$c.GetCommandName()
        if ($cn -eq '') { continue }
        $lc = $cn.ToLowerInvariant()
        if ($uiOnly.ContainsKey($lc) -and -not $seen.ContainsKey($lc)) { $seen[$lc] = $true; Add-Issue 'cekirdek-kapsam' ('cekirdek kodu arayuz islevini cagiriyor: ' + $cn + ' (satir ' + $c.Extent.StartLineNumber + '); islev cekirdek modulune tasinmali') }
    }
    foreach ($f in $files) {
        if ($f -eq [System.IO.Path]::GetFullPath($Path)) { continue }
        $bn = [System.IO.Path]::GetFileName($f)
        foreach ($c in $asts[$f].FindAll({ param($x) $x -is [System.Management.Automation.Language.CommandAst] }, $true)) {
            $cn = [string]$c.GetCommandName()
            if ($cn -eq '') { continue }
            $lc = $cn.ToLowerInvariant()
            if ($uiOnly.ContainsKey($lc) -and -not $seen.ContainsKey($bn + $lc)) { $seen[$bn + $lc] = $true; Add-Issue 'cekirdek-kapsam' ($bn + ':' + $c.Extent.StartLineNumber + ' eklenti arayuz islevini cagiriyor: ' + $cn) }
        }
    }
    # eklenti -> is adi eslemesi
    $extOf = @{}
    foreach ($a in $mainAst.FindAll({ param($x) $x -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true)) {
        if ($a.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and $a.Left.VariablePath.UserPath -ceq 'script:ExtOf') {
            foreach ($h in $a.Right.FindAll({ param($x) $x -is [System.Management.Automation.Language.HashtableAst] }, $true)) {
                foreach ($kv in $h.KeyValuePairs) { $extOf[([string]$kv.Item1.Extent.Text).Trim("'").ToLowerInvariant()] = ([string]$kv.Item2.Extent.Text).Trim("'") }
            }
        }
    }
    foreach ($c in $mainAst.FindAll({ param($x) $x -is [System.Management.Automation.Language.CommandAst] -and [string]$x.GetCommandName() -eq 'Start-Async' }, $true)) {
        $els = @($c.CommandElements)
        $entry = ''
        $pos = 0
        for ($i = 1; $i -lt $els.Count; $i++) {
            if ($els[$i] -is [System.Management.Automation.Language.CommandParameterAst]) { continue }
            $pos++
            if ($pos -eq 2) { if ($els[$i] -is [System.Management.Automation.Language.StringConstantExpressionAst]) { $entry = [string]$els[$i].Value }; break }
        }
        if ($entry -eq '') { continue }
        $le = $entry.ToLowerInvariant()
        if ($coreFns.ContainsKey($le)) { continue }
        if ($extFns.ContainsKey($le)) {
            if (-not $extOf.ContainsKey($le) -or $extOf[$le] -cne $extFns[$le]) { Add-Issue 'cekirdek-kapsam' ('Start-Async girisi ' + $entry + ' (satir ' + $c.Extent.StartLineNumber + ') ' + $extFns[$le] + ' eklentisinde ama $script:ExtOf eslemesi yok ya da yanlis') }
            continue
        }
        Add-Issue 'cekirdek-kapsam' ('Start-Async girisi ' + $entry + ' (satir ' + $c.Extent.StartLineNumber + ') cekirdekte ya da eklentide tanimli degil; arka plan isinde bulunamaz')
    }
}

# ---- komutlar: tanimsiz komut adlari (bilinenler known_cmds.txt)
$knownSet = @{}
if (Test-Path -LiteralPath $Known) { foreach ($l in [System.IO.File]::ReadAllLines($Known)) { $t = $l.Trim(); if ($t -ne '' -and -not $t.StartsWith('#')) { $knownSet[$t.ToLowerInvariant()] = $true } } }
$unres = @{}
foreach ($f in $files) {
    $bn = [System.IO.Path]::GetFileName($f)
    foreach ($c in $asts[$f].FindAll({ param($x) $x -is [System.Management.Automation.Language.CommandAst] }, $true)) {
        $cn = [string]$c.GetCommandName()
        if ($cn -eq '') { continue }
        if ($cn -match '\\') { $cn = $cn.Substring($cn.LastIndexOf('\') + 1) }
        $lc = $cn.ToLowerInvariant()
        if ($defined.ContainsKey($lc)) { continue }
        if ($cn -match '^(\.|&|\\|[A-Za-z]:)' -or $cn -match '\.(exe|cmd|bat|com|msc|cpl)$') { $unres[$lc] = $bn + ':' + $c.Extent.StartLineNumber; continue }
        if ($null -ne (Get-Command -Name $cn -ErrorAction Ignore)) { continue }
        if (-not $unres.ContainsKey($lc)) { $unres[$lc] = $bn + ':' + $c.Extent.StartLineNumber }
    }
}
if ($MakeKnown) {
    $names = @($unres.Keys | Sort-Object)
    [System.IO.File]::WriteAllLines($Known, [string[]](@('# Windows ve dis komutlar: 8.0.0 yayinindan devralinan taban cizgisi') + $names))
    Write-Host ('known_cmds.txt yazildi: ' + $names.Count)
    exit 0
}
foreach ($k in @($unres.Keys | Sort-Object)) {
    if (-not $knownSet.ContainsKey($k)) { Add-Issue 'komutlar' ($unres[$k] + ' tanimsiz ya da bilinmeyen komut: ' + $k) }
}

if ($issues.Count -eq 0) { Write-Host 'powershell denetimleri: temiz' }
else { $issues | ForEach-Object { $_ }; Write-Host ('powershell denetimleri: ' + $issues.Count + ' sorun'); exit 1 }
