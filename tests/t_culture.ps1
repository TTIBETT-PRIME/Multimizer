. "$PSScriptRoot/lib.ps1"
# Kültür koruması (Türkçe/Azerice "I/ı" sorunu) ve OEM kodlama: Set-MmCulture, Test-MmCultureProbe, Get-OemEncoding (mods\136_oem_kultur.ps1 ve p49_kultur.py).
# Linux'ta Türkçe kültür yoktur (değişmez küresel kip); bu yüzden korumanın kendisi -Force ile sınanır, Türkçe biçimler yazılabilir bir kültürle benzetilir.
# Asıl gerçek sınama Windows'ta "Multimizer.ps1 -OzTest" içindedir (Türkçe kültür koruması adımı).
Import-Fn 'Set-MmCulture', 'Get-OemEncoding', 'Test-MmCultureProbe'
Import-Var 'CultureText'
$src = [System.IO.File]::ReadAllText($script:TestPath)
$null = Get-AstFunctions

$origCulture = [System.Threading.Thread]::CurrentThread.CurrentCulture
$origDefault = [System.Globalization.CultureInfo]::DefaultThreadCurrentCulture
try {
    # =================================================================
    #  1) Sorun yoksa hiçbir şey değişmez
    # =================================================================
    $r = Set-MmCulture
    Assert-True ($r -eq $false) 'sorun yoksa Set-MmCulture $false döner'
    Assert-True ([object]::ReferenceEquals([System.Threading.Thread]::CurrentThread.CurrentCulture, $origCulture)) 'sorun yoksa kültür nesnesi aynı kalır'

    # =================================================================
    #  2) Zorla: Türkçe benzeri biçimli kültür -> biçim korunur, harf kuralı değişmez kültürden gelir
    # =================================================================
    $fake = [System.Globalization.CultureInfo]::InvariantCulture.Clone()
    $fake.NumberFormat.NumberDecimalSeparator = ','
    $fake.NumberFormat.NumberGroupSeparator = '.'
    $fake.DateTimeFormat.ShortDatePattern = 'dd.MM.yyyy'
    [System.Threading.Thread]::CurrentThread.CurrentCulture = $fake
    $r = Set-MmCulture -Force
    $now = [System.Threading.Thread]::CurrentThread.CurrentCulture
    Assert-True ($r -eq $true) '-Force kültürü değiştirir'
    Assert-True (-not [object]::ReferenceEquals($now, $fake)) 'yeni kültür nesnesi kuruldu'
    Assert-Eq $now.NumberFormat.NumberDecimalSeparator ',' 'ondalık ayırıcı kullanıcının kültüründen kalır'
    Assert-Eq $now.NumberFormat.NumberGroupSeparator '.' 'binlik ayırıcı kullanıcının kültüründen kalır'
    Assert-Eq $now.DateTimeFormat.ShortDatePattern 'dd.MM.yyyy' 'tarih deseni kullanıcının kültüründen kalır'
    Assert-Eq ('{0:N2}' -f 1234.5) '1.234,50' 'biçim işleci kullanıcının sayı biçimini kullanır'
    Assert-Eq ([string]'I').ToLower() 'i' 'ToLower: I -> i'
    Assert-Eq ([string]'i').ToUpper() 'I' 'ToUpper: i -> I'
    Assert-True (-not $now.IsReadOnly) 'oluşturulan kültür yazılabilir'
    Assert-True (-not [object]::ReferenceEquals($now.NumberFormat, $fake.NumberFormat)) 'sayı biçimi kopyalanır (aynı nesne değil)'
    Assert-True ($null -ne [System.Globalization.CultureInfo]::DefaultThreadCurrentCulture) 'yeni iş parçacıkları için varsayılan kültür kuruldu'
    $fake.NumberFormat.NumberDecimalSeparator = ';'
    Assert-Eq $now.NumberFormat.NumberDecimalSeparator ',' 'kaynak kültürde sonradan yapılan değişiklik kopyayı etkilemez'

    # =================================================================
    #  3) Sınama işlevi
    # =================================================================
    $m = Test-MmCultureProbe
    Assert-True ($m -is [hashtable]) 'sınama bir tablo döndürür'
    Assert-True ($m.Ok -eq $true) ('sınama temiz: ' + (@($m.Bad) -join '; '))
    Assert-Eq @($m.Bad).Count 0 'sorunlu eşleşme yok'
    Assert-Eq $m.Upper 'I' 'sınama: küçük i büyütülünce I'
    Assert-Eq $m.Culture '' 'koruma sonrası kültür adı boş (değişmez tabanlı)'

    # =================================================================
    #  4) Çalışma alanı metni: işlev tek başına yeniden tanımlanabilir (tüm gövde, param bloğu dahil)
    # =================================================================
    Assert-True ($script:CultureText.StartsWith('function Set-MmCulture {')) 'CultureText işlev başlığıyla başlar'
    Assert-True ($script:CultureText.EndsWith('}')) 'CultureText kapanışla biter'
    Assert-True ($script:CultureText -match 'param\(\[switch\]\$Force\)') 'CultureText param bloğunu içerir'
    $rs = [runspacefactory]::CreateRunspace()
    $rs.Open()
    try {
        $rs.SessionStateProxy.SetVariable('CultureText', $script:CultureText)
        $ps = [powershell]::Create()
        $ps.Runspace = $rs
        [void]$ps.AddScript('. ([scriptblock]::Create($CultureText)); $a = Set-MmCulture -Force; $b = Set-MmCulture; $a.ToString() + "|" + $b.ToString() + "|" + ([string]"I").ToLower()')
        $o = @($ps.Invoke())
        $err = @($ps.Streams.Error)
        $ps.Dispose()
        Assert-Eq $err.Count 0 ('çalışma alanında hata yok ' + ($err -join ';'))
        Assert-Eq ([string]$o[0]) 'True|False|i' 'çalışma alanında işlev tanımlanır; -Force kurar, ikinci çağrı değiştirmez'
    } finally { $rs.Dispose() }

    # 4b) Uygulamadaki yol: çalışma alanı kültürü kurar, AsyncWrapper "Test-MmCultureProbe" girişini çalıştırır, tablo döner
    Import-Var 'AsyncWrapper'
    $probeText = (@(Get-AstFunctions | Where-Object { $_.Name -eq 'Test-MmCultureProbe' }) | Select-Object -Last 1).Extent.Text
    $rs2 = [runspacefactory]::CreateRunspace()
    $rs2.ApartmentState = [System.Threading.ApartmentState]::STA
    $rs2.ThreadOptions = [System.Management.Automation.Runspaces.PSThreadOptions]::ReuseThread
    $rs2.Open()
    try {
        $rs2.SessionStateProxy.SetVariable('CultureText', $script:CultureText)
        $rs2.SessionStateProxy.SetVariable('ProbeText', $probeText)
        $rs2.SessionStateProxy.SetVariable('J', [hashtable]::Synchronized(@{ Done = 0; Total = 0; Label = ''; State = 'Running'; Error = $null; Cancel = $false }))
        $rs2.SessionStateProxy.SetVariable('P', @{})
        $rs2.SessionStateProxy.SetVariable('Entry', 'Test-MmCultureProbe')
        $p0 = [powershell]::Create()
        $p0.Runspace = $rs2
        [void]$p0.AddScript('$ErrorActionPreference = ''Continue''; . ([scriptblock]::Create($CultureText)); [void](Set-MmCulture); function Test-NetBlocked { $false }; function Get-ExtError { [string]::Empty }; function Write-WhLog { }; function Save-DebugErrors { 0 }; . ([scriptblock]::Create($ProbeText))')
        [void]$p0.Invoke()
        Assert-Eq @($p0.Streams.Error).Count 0 'çalışma alanı hazırlığında hata yok'
        $p0.Dispose()
        $p1 = [powershell]::Create()
        $p1.Runspace = $rs2
        [void]$p1.AddScript($script:AsyncWrapper)
        $o1 = @($p1.Invoke())
        $e1 = @($p1.Streams.Error)
        $p1.Dispose()
        $res = $null
        foreach ($x in $o1) { $bx = $x; if ($bx -is [psobject]) { $bx = $bx.psobject.BaseObject }; if ($bx -is [hashtable]) { $res = $bx } }
        Assert-Eq $e1.Count 0 ('AsyncWrapper hatasız çalışır ' + ($e1 -join ';'))
        Assert-True ($null -ne $res) 'AsyncWrapper sınama tablosunu döndürür'
        Assert-True ($null -ne $res -and $res.Ok -eq $true) ('çalışma alanında kültür sınaması temiz: ' + $(if ($null -ne $res) { (@($res.Bad) -join '; ') + ' ' + [string]$res.ExtError } else { '' }))
        Assert-True ($null -ne $res -and $res.ContainsKey('Culture') -and $res.ContainsKey('Upper')) 'sınama tablosu kültür adı ve büyütme sonucunu taşır'
    } finally { $rs2.Dispose() }

    # =================================================================
    #  5) OEM kodlama
    # =================================================================
    $script:OemEnc = $null
    $e1 = Get-OemEncoding
    Assert-True ($e1 -is [System.Text.Encoding]) 'Get-OemEncoding bir kodlama döndürür'
    $e2 = Get-OemEncoding
    Assert-True ([object]::ReferenceEquals($e1, $e2)) 'kodlama önbelleğe alınır'
    $script:OemEnc = $null
} finally {
    [System.Threading.Thread]::CurrentThread.CurrentCulture = $origCulture
    [System.Globalization.CultureInfo]::DefaultThreadCurrentCulture = $origDefault
}

# =====================================================================
#  6) Yapı: koruma betiğin başında, her iş parçacığında ve çalışma alanı başlatılırken çağrılır
# =====================================================================
$iGuard = $src.IndexOf('function Set-MmCulture {')
$iAdmin = $src.IndexOf('$script:IsAdmin  =')
Assert-True ($iGuard -gt 0 -and $iAdmin -gt 0 -and $iGuard -lt $iAdmin) 'Set-MmCulture, yeniden başlatma korumasından önce tanımlı'
$iCall = $src.IndexOf('[void](Set-MmCulture)')
Assert-True ($iCall -gt $iGuard -and $iCall -lt $iAdmin) 'koruma betiğin başında çağrılıyor'
Assert-True ($src.Contains("`$script:AsyncWrapper = @'`r`ntry { [void](Set-MmCulture) } catch { }")) 'her arka plan işi kültür korumasıyla başlar'
Assert-True ($src.Contains("SetVariable('CultureText', `$script:CultureText)")) 'çalışma alanına işlev metni aktarılıyor'
Assert-True ($src.Contains('. ([scriptblock]::Create($CultureText)); [void](Set-MmCulture); . ([scriptblock]::Create($CoreText))')) 'çalışma alanı çekirdekten önce kültürü kurar'
Assert-True (-not $src.Contains('CurrentCulture.TextInfo.OEMCodePage')) 'OEM kod sayfası bölgesel kültürden okunmuyor'
Assert-Eq (([regex]::Matches($src, '\(Get-OemEncoding\)')).Count) 3 'üç konsol çıktısı yeri OEM kodlamasını işletim sisteminden alıyor'

# =====================================================================
#  7) Yapı: harf duyarsız (varsayılan) düzenli ifade işleçlerinde, büyük/küçük I içeren harf aralığı sınıfı kalmamış olmalı
#     (Türkçe kültürde .NET Framework büyük I'yı bu sınıflarla eşleştirmez). Çözüm: -cmatch / -cnotmatch / -creplace ya da küçültülmüş metin.
# =====================================================================
function Get-ClassTokens([string]$Body) {
    # sınıf gövdesini belirteçlere ayırır: @{ C = karakter kodu (-1: \d \s \w gibi kısaltma); Esc = kaçışlı mı }
    $t = New-Object System.Collections.ArrayList
    $i = 0
    while ($i -lt $Body.Length) {
        $ch = $Body[$i]
        if ($ch -eq '\' -and $i + 1 -lt $Body.Length) {
            $n = $Body[$i + 1]
            if ($n -ceq 'x' -and $i + 3 -lt $Body.Length) { [void]$t.Add(@{ C = [Convert]::ToInt32($Body.Substring($i + 2, 2), 16); Esc = $true }); $i += 4; continue }
            if ($n -ceq 'u' -and $i + 5 -lt $Body.Length) { [void]$t.Add(@{ C = [Convert]::ToInt32($Body.Substring($i + 2, 4), 16); Esc = $true }); $i += 6; continue }
            if ('dDsSwWpP'.Contains([string]$n)) { [void]$t.Add(@{ C = -1; Esc = $true }); $i += 2; continue }
            [void]$t.Add(@{ C = [int][char]$n; Esc = $true }); $i += 2; continue
        }
        [void]$t.Add(@{ C = [int][char]$ch; Esc = $false }); $i++
    }
    return $t.ToArray()
}
function Test-ClassHasI([string]$Pattern) {
    foreach ($cm in [regex]::Matches($Pattern, '\[\^?((?:\\.|[^\]\\])+)\]')) {
        $tok = @(Get-ClassTokens $cm.Groups[1].Value)
        $i = 0
        while ($i -lt $tok.Count) {
            if ($i + 2 -lt $tok.Count -and $tok[$i + 1].C -eq 45 -and -not $tok[$i + 1].Esc -and $tok[$i].C -ge 0 -and $tok[$i + 2].C -ge 0) {
                $lo = [int]$tok[$i].C; $hi = [int]$tok[$i + 2].C
                if (($lo -le 73 -and $hi -ge 73) -or ($lo -le 105 -and $hi -ge 105)) { return $true }
                $i += 3
                continue
            }
            if ($tok[$i].C -eq 73 -or $tok[$i].C -eq 105) { return $true }
            $i++
        }
    }
    return $false
}
function Find-CaseInsensitiveClasses($Ast, [string]$File) {
    $hits = New-Object System.Collections.ArrayList
    $bins = $Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.BinaryExpressionAst] }, $true)
    foreach ($b in $bins) {
        $kind = [string]$b.Operator
        if ($kind -notin @('Imatch', 'Inotmatch', 'Ireplace', 'Isplit')) { continue }
        # kültür sınaması bilerek bu kalıpları dener
        $p = $b.Parent
        $inProbe = $false
        while ($null -ne $p) { if ($p -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $p.Name -eq 'Test-MmCultureProbe') { $inProbe = $true }; $p = $p.Parent }
        if ($inProbe) { continue }
        $rhs = $b.Right
        if ($rhs -is [System.Management.Automation.Language.ArrayLiteralAst]) { $rhs = $rhs.Elements[0] }
        if ($rhs -isnot [System.Management.Automation.Language.StringConstantExpressionAst]) { continue }
        if (Test-ClassHasI ([string]$rhs.Value)) { [void]$hits.Add($File + ':' + $b.Extent.StartLineNumber + '  ' + $b.Extent.Text.Substring(0, [math]::Min(110, $b.Extent.Text.Length))) }
    }
    return $hits.ToArray()
}
$hits = @(Find-CaseInsensitiveClasses $script:Ast 'Multimizer.ps1')
foreach ($ef in @(Get-ChildItem -LiteralPath (Join-Path $script:TestDir 'Eklenti') -Filter '*.ps1')) {
    $t = $null; $e = $null
    $ea = [System.Management.Automation.Language.Parser]::ParseFile($ef.FullName, [ref]$t, [ref]$e)
    $hits += @(Find-CaseInsensitiveClasses $ea $ef.Name)
}
foreach ($h in $hits) { Write-Host ('  harf aralığı sınıfı: ' + $h) -ForegroundColor Yellow }
Assert-Eq @($hits).Count 0 'harf duyarsız işleçlerde I içeren harf aralığı sınıfı kalmadı'

# tarayıcının kendisi: bilinen sorunlu / sorunsuz örnekler
Assert-True (Test-ClassHasI '^[A-Za-z0-9]+$') 'tarayıcı: [A-Za-z0-9] I içerir'
Assert-True (Test-ClassHasI '^[a-z]+$') 'tarayıcı: [a-z] i içerir'
Assert-True (Test-ClassHasI '^[A-Z]:$') 'tarayıcı: [A-Z] I içerir'
Assert-True (-not (Test-ClassHasI '^[0-9a-fA-F]{8}$')) 'tarayıcı: onaltılık sınıf I içermez'
Assert-True (-not (Test-ClassHasI '^[A-H]+\d$')) 'tarayıcı: [A-H] I içermez'
Assert-True (-not (Test-ClassHasI '^\w+$')) 'tarayıcı: \w sınıfı aralık değildir'
Assert-True (Test-ClassHasI '[^A-Za-z0-9\-_]') 'tarayıcı: olumsuz sınıf da sayılır'
Assert-True (Test-ClassHasI '[_i]') 'tarayıcı: tek harf i'
Assert-True (-not (Test-ClassHasI '[\w-]')) 'tarayıcı: kaçışlı tire'
Assert-True (Test-ClassHasI '^[\x20-\x7E]+$') 'tarayıcı: yazdırılabilir ASCII aralığı I içerir'
Assert-True (-not (Test-ClassHasI '[\x00-\x1F\x7F]')) 'tarayıcı: denetim karakterleri I içermez'
Assert-True (-not (Test-ClassHasI '[\s\x00-\x1f]')) 'tarayıcı: \s ile denetim karakterleri'

# =====================================================================
#  8) Sözlük anahtarları. Windows PowerShell 5.1, @{} tablolarının anahtar karşılaştırıcısını süreç başında (kullanıcının kültürüyle)
#     bir kez kurar ve saklar; iş parçacığı kültürü bunu değiştirmez (cihazda görüldü: Türkçede @{ Info = 1 }['info'] boş döner).
#     Kural: anahtarlar ToLowerInvariant() ile normalleştirilir; kültürlü ToLower()/ToUpper() yalnızca kültür sınamasında kasıtlı kullanılır.
# =====================================================================
$spanStart = $src.IndexOf('function Test-MmCultureProbe {')
$spanEnd = -1
if ($spanStart -ge 0) { $spanEnd = $src.IndexOf("`n}", $spanStart) }
Assert-True ($spanStart -gt 0 -and $spanEnd -gt $spanStart) 'kültür sınaması işlevi bulundu'
$cultured = New-Object System.Collections.ArrayList
foreach ($mm in [regex]::Matches($src, '\.To(Upper|Lower)\(\)')) {
    if (-not ($mm.Index -gt $spanStart -and $mm.Index -lt $spanEnd)) {
        [void]$cultured.Add('satır ' + (($src.Substring(0, $mm.Index) -split "`n").Count))
    }
}
foreach ($c in $cultured) { Write-Host ('  kültürlü ToUpper/ToLower: ' + $c) -ForegroundColor Yellow }
Assert-Eq $cultured.Count 0 'kültürlü ToUpper()/ToLower() yalnızca kültür sınamasında kullanılıyor'
$probeText = ''
if ($spanStart -ge 0 -and $spanEnd -gt $spanStart) { $probeText = $src.Substring($spanStart, $spanEnd - $spanStart) }
Assert-True ($probeText.Contains('OrdinalIgnoreCase')) 'sınama açık karşılaştırıcılı tabloyu dener'
Assert-True ($probeText.Contains('ToLowerInvariant()')) 'sınama anahtar normalleştirmeyi dener'
Assert-True (-not $probeText.Contains('$h[''info'']')) 'sınama @{} tablosunda farklı harf boyuyla aramaya dayanmıyor'
# açık karşılaştırıcılı tablo her kültürde harf boyundan bağımsız çalışır
$tbl = New-Object System.Collections.Hashtable ([System.StringComparer]::OrdinalIgnoreCase)
$tbl['Info'] = 1
Assert-True ($tbl['info'] -eq 1 -and $tbl.ContainsKey('INFO')) 'OrdinalIgnoreCase tablosu harf boyundan bağımsız'
Show-Result
