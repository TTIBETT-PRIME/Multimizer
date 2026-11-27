# Multimizer: arayuz metni atamalarini Tr ile sarmak icin duzenleme listesi uretir (yalnizca okur).
#   $x.Text = ifade   ->   $x.Text = (Tr $(ifade))
# Cikti: JSON dizisi { s = baslangic konumu; e = bitis konumu } (yalnizca atamanin sag tarafi)
param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Out)
$ErrorActionPreference = 'Stop'
$tokens = $null
$errors = $null
$tree = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
if ($errors.Count -gt 0) { Write-Output ('ayristirma hatasi: ' + $errors.Count + ' ' + $errors[0].Message); exit 2 }
$props = @('Text', 'Content', 'ToolTip', 'Header', 'Title', 'BalloonTipText', 'BalloonTipTitle', 'Description')
$assigns = $tree.FindAll({ param($x) $x -is [System.Management.Automation.Language.AssignmentStatementAst] -and $x.Operator -eq 'Equals' }, $true)
$list = New-Object System.Collections.Generic.List[object]
foreach ($a in $assigns) {
    $lt = $a.Left
    if ($lt -isnot [System.Management.Automation.Language.MemberExpressionAst]) { continue }
    if ($lt.Static) { continue }
    $mem = $lt.Member
    if ($mem -isnot [System.Management.Automation.Language.StringConstantExpressionAst]) { continue }
    if ($props -cnotcontains [string]$mem.Value) { continue }
    $r = $a.Right
    # sag taraf yalnizca $null, sayi ya da mantiksal sabit ise sarilmaz
    if ($r -is [System.Management.Automation.Language.CommandExpressionAst]) {
        $ex = $r.Expression
        if ($ex -is [System.Management.Automation.Language.ConstantExpressionAst] -and $ex -isnot [System.Management.Automation.Language.StringConstantExpressionAst]) { continue }
        if ($ex -is [System.Management.Automation.Language.VariableExpressionAst]) {
            $vn = [string]$ex.VariablePath.UserPath
            if ($vn -eq 'null' -or $vn -eq 'true' -or $vn -eq 'false') { continue }
        }
    }
    $list.Add([pscustomobject]@{ s = $r.Extent.StartOffset; e = $r.Extent.EndOffset; l = $a.Extent.StartLineNumber; t = $lt.Extent.Text; p = [string]$mem.Value }) | Out-Null
}
$list | ConvertTo-Json -Compress -Depth 3 | Set-Content -LiteralPath $Out -Encoding UTF8
Write-Output ('atama: ' + $list.Count)
