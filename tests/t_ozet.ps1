. "$PSScriptRoot/lib.ps1"
# araclar\Ozet-Guncelle.ps1: yan dosya ozetlerini Multimizer.ps1 icindeki kayitla karsilastirir / yeniler

$tool = Join-Path $script:TestDir 'araclar/Ozet-Guncelle.ps1'
Assert-True (Test-Path -LiteralPath $tool) 'araclar/Ozet-Guncelle.ps1 var'
$pw = (Get-Process -Id $PID).Path
Assert-Eq @([System.IO.File]::ReadAllBytes($tool) | Where-Object { $_ -ge 128 }).Count 0 'arac yalnizca ASCII'

$root = Join-Path ([System.IO.Path]::GetTempPath()) ('mm-ozet-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root -Force | Out-Null
try {
    function New-Copy([string]$Name) {
        $d = Join-Path $root $Name
        New-Item -ItemType Directory -Path $d -Force | Out-Null
        Copy-Item -LiteralPath $script:TestPath -Destination (Join-Path $d 'Multimizer.ps1')
        foreach ($sub in 'veri', 'Eklenti') { Copy-Item -LiteralPath (Join-Path $script:TestDir $sub) -Destination $d -Recurse -Force }
        New-Item -ItemType Directory -Path (Join-Path $d 'araclar') -Force | Out-Null
        Copy-Item -LiteralPath $tool -Destination (Join-Path $d 'araclar/Ozet-Guncelle.ps1')
        return $d
    }
    function Run-Tool([string]$Dir, [string[]]$More = @()) {
        $o = @(& $pw -NoProfile -File (Join-Path $Dir 'araclar/Ozet-Guncelle.ps1') @More 2>&1 | ForEach-Object { [string]$_ })
        return @{ Rc = $LASTEXITCODE; Out = ($o -join "`n") }
    }
    function Get-RegHash([string]$MainPath) {
        $t = $null; $e = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($MainPath, [ref]$t, [ref]$e)
        $a = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$script:PackHash' }, $true)) | Select-Object -First 1
        $script:PackHash = $null
        . ([scriptblock]::Create($a.Extent.Text))
        return $script:PackHash
    }

    # 1) saglam paket: hepsi tutar
    $d = New-Copy 'saglam'
    $r = Run-Tool $d
    Assert-Eq $r.Rc 0 'saglam paket: cikis 0'
    Assert-True ($r.Out -match 'Tum ozetler tutuyor') 'saglam paket: mesaj'
    Assert-True ($r.Out -match 'tamam\s+Eklenti/Sifreleme\.ps1') 'dosyalar tek tek listelenir'

    # 2) degistirilmis eklenti: yalniz karsilastirma 1 dondurur ve dosyayi adiyla soyler; Multimizer.ps1 degismez
    $d = New-Copy 'degisti'
    $mainBefore = [System.IO.File]::ReadAllBytes((Join-Path $d 'Multimizer.ps1'))
    [System.IO.File]::AppendAllText((Join-Path $d 'Eklenti/Bellek.ps1'), "`n# degisiklik")
    $r = Run-Tool $d
    Assert-Eq $r.Rc 1 'degisen dosya: cikis 1'
    Assert-True ($r.Out -match 'DEGISMIS\s+Eklenti/Bellek\.ps1') 'degisen dosya adiyla bildirilir'
    $mainAfter = [System.IO.File]::ReadAllBytes((Join-Path $d 'Multimizer.ps1'))
    Assert-Eq $mainAfter.Length $mainBefore.Length '-Yaz olmadan Multimizer.ps1 degismez'

    # 3) -Yaz: kayit yenilenir, sonra her sey tutar; CRLF + ASCII korunur; betik hala ayristirilir
    $r = Run-Tool $d @('-Yaz')
    Assert-Eq $r.Rc 0 '-Yaz: cikis 0'
    Assert-True ($r.Out -match 'yenilendi') '-Yaz: yenilendi mesaji'
    $r = Run-Tool $d
    Assert-Eq $r.Rc 0 'yenilemeden sonra tum ozetler tutuyor'
    $txt = [System.IO.File]::ReadAllText((Join-Path $d 'Multimizer.ps1'), [System.Text.Encoding]::ASCII)
    $nl = ([regex]::Matches($txt, "`n")).Count
    $crlf = ([regex]::Matches($txt, "`r`n")).Count
    Assert-Eq $nl $crlf 'Multimizer.ps1 satir sonlari CRLF kaldi'
    Assert-Eq @([System.IO.File]::ReadAllBytes((Join-Path $d 'Multimizer.ps1')) | Where-Object { $_ -ge 128 }).Count 0 'Multimizer.ps1 ASCII kaldi'
    $t = $null; $e = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $d 'Multimizer.ps1'), [ref]$t, [ref]$e)
    Assert-Eq @($e).Count 0 'Multimizer.ps1 hala hatasiz ayristirilir'
    $orig = Get-RegHash $script:TestPath
    $new = Get-RegHash (Join-Path $d 'Multimizer.ps1')
    Assert-Eq $new.Count $orig.Count 'kayit sayisi ayni'
    Assert-True ($new['Eklenti/Bellek.ps1'] -ne $orig['Eklenti/Bellek.ps1']) 'degisen dosyanin ozeti yenilendi'
    Assert-Eq $new['Eklenti/Sifreleme.ps1'] $orig['Eklenti/Sifreleme.ps1'] 'degismeyen dosyanin ozeti ayni'
    # farki dosyadan baska yer degismedi: kayit blogu disinda ayni
    $strip = { param($s) [regex]::Replace($s, '(?ms)^\$script:PackHash = @\{.*?^\}', '') }
    $origTxt = [System.IO.File]::ReadAllText($script:TestPath, [System.Text.Encoding]::ASCII)
    Assert-Eq (& $strip $txt) (& $strip $origTxt) 'kayit blogu disinda Multimizer.ps1 ayni'

    # 4) yenilenen kayit, uygulamanin kendi dogrulamasiyla da uyusur
    Import-Fn 'Get-AppFolder', 'Get-TextSha256', 'Get-PackFileText'
    $script:PackHash = $new
    $sync = @{ ScriptPath = (Join-Path $d 'Multimizer.ps1') }
    $g = Get-PackFileText 'Eklenti/Bellek.ps1'
    Assert-True ($g.Ok -eq $true) ('uygulama dogrulamasi yenilenen ozeti kabul eder: ' + [string]$g.Error)

    # 5) yeni dosya ve silinen dosya
    $d2 = New-Copy 'yeni'
    [System.IO.File]::WriteAllText((Join-Path $d2 'Eklenti/Yeni.ps1'), "function global:Job_Yeni { }`n")
    Remove-Item -LiteralPath (Join-Path $d2 'veri/supheli-komutlar.txt') -Force
    $r = Run-Tool $d2
    Assert-Eq $r.Rc 1 'yeni + eksik dosya: cikis 1'
    Assert-True ($r.Out -match 'YENI\s+Eklenti/Yeni\.ps1') 'yeni dosya bildirilir'
    Assert-True ($r.Out -match 'YOK\s+veri/supheli-komutlar\.txt') 'eksik dosya bildirilir'
    $r = Run-Tool $d2 @('-Yaz')
    Assert-Eq $r.Rc 0 'yeni + eksik: -Yaz basarili'
    $n2 = Get-RegHash (Join-Path $d2 'Multimizer.ps1')
    Assert-True ($n2.ContainsKey('Eklenti/Yeni.ps1')) 'yeni dosya kayda girdi'
    Assert-True (-not $n2.ContainsKey('veri/supheli-komutlar.txt')) 'diskte olmayan kayittan cikti'

    # 6) CRLF / LF farki ozeti etkilemez
    $d3 = New-Copy 'satirsonu'
    $f = Join-Path $d3 'Eklenti/WifiAktar.ps1'
    $c = [System.IO.File]::ReadAllText($f).Replace("`r`n", "`n").Replace("`n", "`r`n")
    [System.IO.File]::WriteAllText($f, $c, (New-Object System.Text.UTF8Encoding($false)))
    $r = Run-Tool $d3
    Assert-Eq $r.Rc 0 'CRLF dosya: ozet ayni'
    $c2 = $c.Replace("`r`n", "`n")
    [System.IO.File]::WriteAllText($f, $c2, (New-Object System.Text.UTF8Encoding($false)))
    $r = Run-Tool $d3
    Assert-Eq $r.Rc 0 'LF dosya: ozet ayni'
    [System.IO.File]::WriteAllText($f, $c2, (New-Object System.Text.UTF8Encoding($true)))
    $r = Run-Tool $d3
    Assert-Eq $r.Rc 0 'UTF-8 imzali dosya: ozet ayni'

    # 7) betik yoksa hata
    $d4 = Join-Path $root 'bos'
    New-Item -ItemType Directory -Path (Join-Path $d4 'araclar') -Force | Out-Null
    Copy-Item -LiteralPath $tool -Destination (Join-Path $d4 'araclar/Ozet-Guncelle.ps1')
    $r = Run-Tool $d4
    Assert-Eq $r.Rc 2 'Multimizer.ps1 yoksa cikis 2'
} finally {
    try { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue } catch { }
}
Show-Result
