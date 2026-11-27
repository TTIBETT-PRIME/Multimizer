# Multimizer dil katalogu cikarici: betigin sozdizimi agacindan (AST) kullaniciya gosterilebilecek metinleri bulur.
# Yalnizca okur. Windows PowerShell 5.1 ve PowerShell 7'de calisir.
#   Cikti (JSON dizisi): { i = metin kimligi; k = 'c' (sabit) | 't' (sablon, {0} {1} ... dinamik parca); x = baglam; l = satir; p = parametre }
param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Out)
$ErrorActionPreference = 'Stop'
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
if ($errors.Count -gt 0) { Write-Output ('ayristirma hatasi: ' + $errors.Count + ' ' + $errors[0].Message); exit 2 }

$flatCache = New-Object 'System.Collections.Generic.Dictionary[object,object]'
$none = New-Object psobject

# Dizgi ifadesini parcalara ayirir: duz metin parcasi (string) ya da dinamik parca ($null). Dizgi ifadesi degilse $null.
function Get-Flat($n) {
    if ($null -eq $n) { return $null }
    if ($flatCache.ContainsKey($n)) { $c = $flatCache[$n]; if ([object]::ReferenceEquals($c, $none)) { return $null } else { return $c } }
    $res = $null
    $tn = $n.GetType().Name
    if ($tn -eq 'StringConstantExpressionAst') {
        if ($n.StringConstantType -ne 'BareWord') { $res = New-Object 'System.Collections.Generic.List[object]'; [void]$res.Add([string]$n.Value) }
    }
    elseif ($tn -eq 'ConvertExpressionAst') {
        $ty = $n.Type.TypeName.Name
        if ($ty -eq 'char' -and $n.Child -is [System.Management.Automation.Language.ConstantExpressionAst] -and $n.Child.Value -is [int]) {
            $res = New-Object 'System.Collections.Generic.List[object]'; [void]$res.Add([string][char][int]$n.Child.Value)
        }
        elseif ($ty -eq 'string') {
            $res = New-Object 'System.Collections.Generic.List[object]'; [void]$res.Add($null)
        }
    }
    elseif ($tn -eq 'ParenExpressionAst') {
        $p = $n.Pipeline
        if ($p -is [System.Management.Automation.Language.PipelineAst] -and $p.PipelineElements.Count -eq 1 -and $p.PipelineElements[0] -is [System.Management.Automation.Language.CommandExpressionAst]) {
            $res = Get-Flat $p.PipelineElements[0].Expression
        }
    }
    elseif ($tn -eq 'BinaryExpressionAst') {
        if ($n.Operator -eq 'Plus') {
            $l = Get-Flat $n.Left
            $r = Get-Flat $n.Right
            $hasLit = $false
            if ($null -ne $l) { foreach ($x in $l) { if ($null -ne $x) { $hasLit = $true } } }
            if ($null -ne $r) { foreach ($x in $r) { if ($null -ne $x) { $hasLit = $true } } }
            if ($hasLit) {
                $res = New-Object 'System.Collections.Generic.List[object]'
                if ($null -ne $l) { foreach ($x in $l) { [void]$res.Add($x) } } else { [void]$res.Add($null) }
                if ($null -ne $r) { foreach ($x in $r) { [void]$res.Add($x) } } else { [void]$res.Add($null) }
            }
        }
    }
    elseif ($tn -eq 'ExpandableStringExpressionAst') {
        if ($n.StringConstantType -eq 'DoubleQuoted') {
            $res = New-Object 'System.Collections.Generic.List[object]'
            $base = $n.Extent.StartOffset + 1
            $txt = $n.Extent.Text
            $cur = 0
            $nested = @($n.NestedExpressions | Sort-Object { $_.Extent.StartOffset })
            foreach ($ne in $nested) {
                $s = $ne.Extent.StartOffset - $base
                if ($s -gt $cur) { [void]$res.Add(($txt.Substring(1 + $cur, $s - $cur)).Replace('`n', "`n").Replace('`t', "`t").Replace('`"', '"').Replace('""', '"').Replace('``', '`')) }
                [void]$res.Add($null)
                $cur = $ne.Extent.EndOffset - $base
            }
            $endLit = $txt.Length - 2 - $cur
            if ($endLit -gt 0) { [void]$res.Add(($txt.Substring(1 + $cur, $endLit)).Replace('`n', "`n").Replace('`t', "`t").Replace('`"', '"').Replace('""', '"').Replace('``', '`')) }
        }
    }
    if ($null -eq $res) { $flatCache[$n] = $none } else { $flatCache[$n] = $res }
    return $res
}

function Get-Ctx($n) {
    $a = $n
    for ($i = 0; $i -lt 10 -and $null -ne $a; $i++) {
        $par = $a.Parent
        if ($null -eq $par) { break }
        if ($par -is [System.Management.Automation.Language.CommandAst]) {
            $prev = $null
            $els = $par.CommandElements
            for ($k = 0; $k -lt $els.Count; $k++) { if ([object]::ReferenceEquals($els[$k], $a)) { if ($k -gt 0) { $prev = $els[$k - 1] }; break } }
            $pn = ''
            if ($prev -is [System.Management.Automation.Language.CommandParameterAst]) { $pn = [string]$prev.ParameterName }
            return @(('cmd:' + [string]$par.GetCommandName()), $pn)
        }
        if ($par -is [System.Management.Automation.Language.AssignmentStatementAst]) {
            $lt = $par.Left
            if ($lt -is [System.Management.Automation.Language.MemberExpressionAst]) { return @(('assign:' + [string]$lt.Member.Value), '') }
            return @('assign:var', '')
        }
        if ($par -is [System.Management.Automation.Language.HashtableAst]) {
            foreach ($kv in $par.KeyValuePairs) {
                if ($kv.Item2.Extent.StartOffset -le $a.Extent.StartOffset -and $kv.Item2.Extent.EndOffset -ge $a.Extent.EndOffset) {
                    $kf = Get-Flat $kv.Item1
                    $kname = $kv.Item1.Extent.Text
                    if ($null -ne $kf -and $kf.Count -eq 1 -and $null -ne $kf[0]) { $kname = [string]$kf[0] }
                    return @(('hash:' + $kname), '')
                }
            }
            return @('hash:?', '')
        }
        if ($par -is [System.Management.Automation.Language.ArrayLiteralAst] -or $par -is [System.Management.Automation.Language.ArrayExpressionAst] -or $par -is [System.Management.Automation.Language.ParenExpressionAst] -or $par -is [System.Management.Automation.Language.BinaryExpressionAst] -or $par -is [System.Management.Automation.Language.CommandExpressionAst] -or $par -is [System.Management.Automation.Language.PipelineAst] -or $par -is [System.Management.Automation.Language.StatementBlockAst] -or $par -is [System.Management.Automation.Language.SubExpressionAst]) { $a = $par; continue }
        if ($par -is [System.Management.Automation.Language.InvokeMemberExpressionAst]) {
            return @(('call:' + $par.Member.Extent.Text), '')
        }
        if ($par -is [System.Management.Automation.Language.ReturnStatementAst]) { return @('return', '') }
        $a = $par
    }
    return @('', '')
}

$cand = $ast.FindAll({ param($x)
        $x -is [System.Management.Automation.Language.StringConstantExpressionAst] -or
        $x -is [System.Management.Automation.Language.BinaryExpressionAst] -or
        $x -is [System.Management.Automation.Language.ParenExpressionAst] -or
        $x -is [System.Management.Automation.Language.ExpandableStringExpressionAst] -or
        $x -is [System.Management.Automation.Language.ConvertExpressionAst] }, $true)

$rows = New-Object System.Collections.Generic.List[object]
foreach ($n in $cand) {
    $f = Get-Flat $n
    if ($null -eq $f) { continue }
    $hasLit = $false
    foreach ($x in $f) { if ($null -ne $x -and $x.Length -gt 0) { $hasLit = $true } }
    if (-not $hasLit) { continue }
    # en buyuk dizgi ifadesi: ust dugum de ayni zincirin parcasi ise atla
    $par = $n.Parent
    if ($null -ne $par) {
        $pt = $par.GetType().Name
        if ($pt -eq 'BinaryExpressionAst' -or $pt -eq 'ParenExpressionAst') {
            $pf = Get-Flat $par
            if ($null -ne $pf) { continue }
        }
    }
    $sb = New-Object System.Text.StringBuilder
    $k = 0
    $nDyn = 0
    foreach ($x in $f) {
        if ($null -eq $x) { [void]$sb.Append('{' + $k + '}'); $k++; $nDyn++ } else { [void]$sb.Append($x) }
    }
    $id = $sb.ToString()
    if ($id.Length -lt 2) { continue }
    if ($id.TrimStart().StartsWith('<')) { $kind = 'x' } elseif ($nDyn -gt 0) { $kind = 't' } else { $kind = 'c' }
    $cx = Get-Ctx $n
    $rows.Add([pscustomobject]@{ i = $id; k = $kind; x = $cx[0]; p = $cx[1]; l = $n.Extent.StartLineNumber }) | Out-Null
}
# -f bicim dizgileri: sablon dogrudan sol taraftir
foreach ($n in $ast.FindAll({ param($x) $x -is [System.Management.Automation.Language.BinaryExpressionAst] -and $x.Operator -eq 'Format' }, $true)) {
    $lf = Get-Flat $n.Left
    if ($null -eq $lf -or $lf.Count -ne 1 -or $null -eq $lf[0]) { continue }
    $t = [regex]::Replace([string]$lf[0], '\{(\d+)(?:,-?\d+)?(?::[^}]*)?\}', '{$1}')
    $cx = Get-Ctx $n
    $rows.Add([pscustomobject]@{ i = $t; k = 't'; x = $cx[0]; p = 'fmt'; l = $n.Extent.StartLineNumber }) | Out-Null
}
$rows | ConvertTo-Json -Compress -Depth 3 | Set-Content -LiteralPath $Out -Encoding UTF8
Write-Output ('kayit: ' + $rows.Count)
