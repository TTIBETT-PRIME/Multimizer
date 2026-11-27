# C# 5 uyum denetimi: .cs dosyalarını ve .ps1 içindeki Add-Type gövdelerini Roslyn ile C# 5 dil sürümünde ayrıştırır.
# Windows PowerShell 5.1 içindeki derleyici C# 5'tir; C# 6+ özelliği kullanan kod orada derlenmez.
# Yalnızca pwsh 7 ile çalışır (Roslyn orada hazırdır). Çıktı: "[cs5] dosya:satır: ileti" satırları; sorun yoksa "cs5 temiz".
# Files: dosya yolları, '|' ile ayrılmış tek metin (pwsh -File ile dizi geçirilemediği için)
param([Parameter(Mandatory = $true)][string]$Files)
$ErrorActionPreference = 'Stop'
try { [void][Microsoft.CodeAnalysis.CSharp.LanguageVersion] } catch {
    foreach ($n in @('Microsoft.CodeAnalysis.dll', 'Microsoft.CodeAnalysis.CSharp.dll')) {
        $p = Join-Path $PSHOME $n
        if (Test-Path -LiteralPath $p) { try { Add-Type -Path $p } catch { } }
    }
}
$parse = [Microsoft.CodeAnalysis.CSharp.CSharpParseOptions]::new([Microsoft.CodeAnalysis.CSharp.LanguageVersion]::CSharp5)
$refs = New-Object System.Collections.Generic.List[Microsoft.CodeAnalysis.MetadataReference]
foreach ($p in ([string][AppContext]::GetData('TRUSTED_PLATFORM_ASSEMBLIES')).Split([System.IO.Path]::PathSeparator)) {
    $leaf = [System.IO.Path]::GetFileName($p)
    if ($leaf -match '^(System\.Private\.CoreLib|System\.Runtime|System\.Collections|System\.Linq|System\.Console|System\.Runtime\.InteropServices|System\.Diagnostics\.Process|System\.Text\.Encoding\.Extensions|System\.Memory|System\.ComponentModel\.Primitives|Microsoft\.Win32\.Primitives|System\.Threading|System\.Net\.Primitives|System\.Net\.Sockets|System\.Net\.NetworkInformation|System\.IO\.FileSystem|System\.Security\.Cryptography.*|System\.Collections\.Concurrent|netstandard)\.dll$') {
        $refs.Add([Microsoft.CodeAnalysis.MetadataReference]::CreateFromFile($p))
    }
}
$bad = 0
$blocks = 0
foreach ($f in ($Files.Split('|') | Where-Object { $_ -ne '' })) {
    if (-not (Test-Path -LiteralPath $f)) { Write-Output ('[cs5] ' + $f + ': dosya yok'); $bad++; continue }
    $text = [System.IO.File]::ReadAllText($f)
    $list = New-Object System.Collections.Generic.List[object]
    if ($f -match '\.cs$') {
        $list.Add(@{ Text = $text; Line = 1 })
    } else {
        foreach ($m in [regex]::Matches($text, "(?s)@(['""])\r?\n(.*?)\r?\n\1@")) {
            $body = $m.Groups[2].Value
            if ($body -notmatch '(?m)\busing\s+System|\bnamespace\s+\w|\bpublic\s+(?:static\s+|sealed\s+)?class\b|\[DllImport') { continue }
            $line = 1 + ($text.Substring(0, $m.Groups[2].Index) -split "`n").Count - 1
            $list.Add(@{ Text = $body; Line = $line })
        }
    }
    foreach ($b in $list) {
        $blocks++
        $tree = [Microsoft.CodeAnalysis.CSharp.CSharpSyntaxTree]::ParseText([string]$b.Text, $parse)
        $comp = [Microsoft.CodeAnalysis.CSharp.CSharpCompilation]::Create('mmcheck', [Microsoft.CodeAnalysis.SyntaxTree[]]@($tree), $refs.ToArray(), $null)
        foreach ($d in $comp.GetDiagnostics()) {
            $msg = $d.GetMessage()
            $isSyntax = ($d.Id -match '^CS1\d\d\d$' -and $d.Severity -eq 'Error') -and $d.Location.IsInSource
            $isFeature = ($msg -match 'is not available in C#|language version')
            if (-not ($isFeature -or $isSyntax)) { continue }
            $ln = $d.Location.GetLineSpan().StartLinePosition.Line + [int]$b.Line
            Write-Output ('[cs5] ' + [System.IO.Path]::GetFileName($f) + ':' + [string]$ln + ': ' + $d.Id + ' ' + $msg)
            $bad++
        }
    }
}
if ($bad -eq 0) { Write-Output ('cs5 temiz (' + [string]$blocks + ' blok)') }
