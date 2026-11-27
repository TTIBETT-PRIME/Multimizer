# Test yardimcisi: derlenmis dosyadan (ve yanindaki Eklenti\ dosyalarindan) adli islevleri AST ile cikarip bu oturuma yukler.
param()
$script:TestPath = $env:MM_BUILD
$script:TestDir = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($script:TestPath))
function Get-AstFunctions {
    if ($null -ne $script:AllFns) { return $script:AllFns }
    $list = New-Object System.Collections.ArrayList
    $files = New-Object System.Collections.ArrayList
    [void]$files.Add($script:TestPath)
    $extDir = Join-Path $script:TestDir 'Eklenti'
    if (Test-Path -LiteralPath $extDir) { foreach ($x in @(Get-ChildItem -LiteralPath $extDir -Filter '*.ps1')) { [void]$files.Add($x.FullName) } }
    foreach ($f in $files) {
        $t = $null; $e = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$t, [ref]$e)
        if ($f -eq $script:TestPath) { $script:Ast = $ast }
        foreach ($fn in @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))) { [void]$list.Add($fn) }
    }
    $script:AllFns = $list.ToArray()
    return $script:AllFns
}
function Import-Fn([string[]]$Names) {
    $all = Get-AstFunctions
    foreach ($n in $Names) {
        $f = @($all | Where-Object { ($_.Name -replace '^global:', '') -eq $n }) | Select-Object -Last 1
        if ($null -eq $f) { throw "islev bulunamadi: $n" }
        . ([scriptblock]::Create($f.Extent.Text))
        # dot-source ile islev yalnizca bu kapsamda tanimlanir; global'e tasi
        Set-Item -Path ('function:global:' + $n) -Value (Get-Item ('function:' + $n)).ScriptBlock
    }
}
# Bir eklenti dosyasındaki (Eklenti\<Ad>.ps1) tüm işlevleri yükler. Eklentiler yalnızca işlev tanımlar; çalıştırılacak üst düzey kod yoktur.
function Import-Ext([string]$Name) {
    $f = Join-Path (Join-Path $script:TestDir 'Eklenti') ($Name + '.ps1')
    if (-not (Test-Path -LiteralPath $f)) { throw "eklenti bulunamadi: $Name" }
    $t = $null; $e = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$t, [ref]$e)
    if (@($e).Count -gt 0) { throw ('eklenti ayrilamadi: ' + $e[0].Message) }
    $names = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false) | ForEach-Object { $_.Name -replace '^global:', '' })
    foreach ($n in $names) {
        $all = Get-AstFunctions
        $fn = @($all | Where-Object { ($_.Name -replace '^global:', '') -eq $n -and $_.Extent.File -eq $f }) | Select-Object -Last 1
        . ([scriptblock]::Create($fn.Extent.Text))
        Set-Item -Path ('function:global:' + $n) -Value (Get-Item ('function:' + $n)).ScriptBlock
    }
    return $names
}
# Dil sarmalayicisi: testlerde metni degistirmez (t_i18n gercek Tr islevini yukleyip bunun uzerine yazar)
if (-not (Get-Command Tr -ErrorAction SilentlyContinue)) { function global:Tr { param([string]$Text) return $Text } }
$script:Pass = 0; $script:Fail = 0
function Assert-Eq($Actual, $Expected, [string]$Msg) {
    if ("$Actual" -ceq "$Expected") { $script:Pass++ } else { $script:Fail++; Write-Host ("FAIL: $Msg  beklenen=[$Expected] bulunan=[$Actual]") -ForegroundColor Red }
}
function Assert-True($Cond, [string]$Msg) { if ($Cond) { $script:Pass++ } else { $script:Fail++; Write-Host ("FAIL: $Msg") -ForegroundColor Red } }
function Show-Result { Write-Host ("Sonuc: gecti=$($script:Pass) kaldi=$($script:Fail)"); if ($script:Fail -gt 0) { exit 1 } }

# Betik duzeyi $script:Ad = ... atamalarini ayni sekilde yukler
function Import-Var([string[]]$Names) {
    [void](Get-AstFunctions)
    $all = $script:Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true)
    foreach ($n in $Names) {
        $a = @($all | Where-Object { $_.Left.Extent.Text -eq ('$script:' + $n) }) | Select-Object -Last 1
        if ($null -eq $a) { throw "degisken bulunamadi: $n" }
        . ([scriptblock]::Create($a.Extent.Text))
    }
}

# Sahte ComboBox: Items (ArrayList), SelectedIndex, SelectedItem, IsEnabled, Tag. Arayuz kodundaki Set-ComboChoices / Select-ComboKey / Get-ComboKey bununla sinanir.
function New-FakeCombo {
    $c = [pscustomobject]@{ Items = (New-Object System.Collections.ArrayList); SelectedIndex = -1; IsEnabled = $true; Tag = $null; Text = '' }
    Add-Member -InputObject $c -MemberType ScriptProperty -Name SelectedItem -Value { if ($this.SelectedIndex -ge 0 -and $this.SelectedIndex -lt $this.Items.Count) { $this.Items[$this.SelectedIndex] } else { $null } } | Out-Null
    return $c
}
