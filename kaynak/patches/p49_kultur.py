# -*- coding: utf-8 -*-
"""Gerçek Windows'ta (Türkçe kültür, Windows PowerShell 5.1) bulunan hatalar.

Kök neden: .NET Framework düzenli ifadeleri büyük/küçük harf duyarsız eşleştirirken girdi karakterini geçerli kültüre göre
küçültür; Türkçe/Azerice kültürde "I" -> "ı" olduğundan [A-Za-z] gibi sınıflar büyük I'yı eşleştirmez ("Input", "INTEL",
"OFIS-PC" gibi bilgisayar adları, I: sürücüsü, INFO günlük düzeyi). Çözüm iki katmanlıdır:
  1) Set-MmCulture: her iş parçacığında sayı/tarih biçimi kullanıcının kültüründen kalır, büyük/küçük harf kuralı değişmez
     kültürden gelir (Türkçe/Azerice dışında hiçbir şey değişmez);
  2) doğrulayıcılar ve sistem klasörü korumaları ayrıca harf duyarlı (-cmatch) ya da küçültülmüş metinle çalışır.
Ayrıca: katalog sınamasının işlem türü listesi MoreOps kayıtlarını da kapsar; sınama iletileri bulunan değerleri yazar;
konsol çıktı kodlaması kullanıcının bölgesel kültürüne değil işletim sisteminin OEM kod sayfasına bakar."""

CULTURE_BLOCK = r"""# ------------------------------------------------------------------
#  Kültür koruması
#  Türkçe ve Azerice kültürde .NET Framework düzenli ifadeleri büyük I harfini [A-Za-z] ile eşleştirmez
#  ('Input' -match '^[A-Za-z]+$' ve 'INTEL' -match 'intel' yanlış çıkar; bilgisayar adındaki I silinir, I: sürücüsü reddedilir).
#  Sayı ve tarih biçimi kullanıcının kültüründen kalır; büyük/küçük harf kuralı değişmez kültürden alınır.
#  Her iş parçacığında (ana, arka plan) çağrılır; sorun yoksa hiçbir şeyi değiştirmez. Dönüş: değiştirdiyse $true.
# ------------------------------------------------------------------
function Set-MmCulture {
    param([switch]$Force)
    try {
        $cur = [System.Threading.Thread]::CurrentThread.CurrentCulture
        if (-not $Force) {
            $okLow = (([string]'I').ToLower($cur) -ceq 'i')
            $okUp = (([string]'i').ToUpper($cur) -ceq 'I')
            if ($okLow -and $okUp) { return $false }
        }
        $c = [System.Globalization.CultureInfo]::InvariantCulture.Clone()
        try { $c.NumberFormat = $cur.NumberFormat.Clone() } catch { }
        try { $c.DateTimeFormat = $cur.DateTimeFormat.Clone() } catch { }
        [System.Threading.Thread]::CurrentThread.CurrentCulture = $c
        try { [System.Globalization.CultureInfo]::DefaultThreadCurrentCulture = $c } catch { }
        return $true
    } catch { return $false }
}
# arka plan çalışma alanları işlevi bu metinden tanımlar (çekirdekten önce)
$script:CultureText = 'function Set-MmCulture {' + (Get-Command -Name Set-MmCulture -CommandType Function).Definition + '}'
[void](Set-MmCulture)

"""

CULTURE_STEP = r"""    Test-Step ('Türkçe kültür koruması: büyük “I” ve küçük “ı” düzenli ifadeleri bozmaz (ana ve arka plan iş parçacığı)') {
        [void](Set-MmCulture)
        $m = Test-MmCultureProbe
        if ($m.Ok -ne $true) { return ('ana iş parçacığı: ' + (@($m.Bad) -join '; ') + ' [kültür: ' + [string]$m.Culture + ']') }
        Initialize-Work
        Wait-CoreRunspace $script:Work
        $rs = $script:Work.Rs
        $rs.SessionStateProxy.SetVariable('J', [hashtable]::Synchronized(@{ Done = 0; Total = 0; Label = ''; State = 'Running'; Error = $null; Cancel = $false }))
        $rs.SessionStateProxy.SetVariable('P', @{})
        $rs.SessionStateProxy.SetVariable('Entry', 'Test-MmCultureProbe')
        $ps = [powershell]::Create()
        $ps.Runspace = $rs
        [void]$ps.AddScript($script:AsyncWrapper)
        $o = @($ps.Invoke())
        $err = @($ps.Streams.Error)
        $ps.Dispose()
        $r = $null
        foreach ($x in $o) {
            $bx = $x
            if ($bx -is [psobject]) { $bx = $bx.psobject.BaseObject }
            if ($bx -is [hashtable]) { $r = $bx }
        }
        if ($null -eq $r) { return ('arka plan sınaması sonuç vermedi ' + ($err -join ';')) }
        if ($r.Ok -ne $true) { return ('arka plan iş parçacığı: ' + (@($r.Bad) -join '; ') + ' [kültür: ' + [string]$r.Culture + ']') }
    }

"""

SELF_ANCHOR = "    Add-SelfLine ''\n    $okN = $script:SelfTotal - $script:SelfFail\n"

# (eski, yeni, adet): taban metin (8.0.0) ve önceki yamalar
REPS = [
    # ---- sağlamlaştırma: harf duyarlı (-cmatch) doğrulayıcılar
    ("$ln -match '^\\s*([A-Za-z]+)\\s*=\\s*(.+?)\\s*$'", "$ln -cmatch '^\\s*([A-Za-z]+)\\s*=\\s*(.+?)\\s*$'", 1),
    ("$id -notmatch '^[A-Za-z0-9][A-Za-z0-9\\.\\-_\\+]*$'", "$id -cnotmatch '^[A-Za-z0-9][A-Za-z0-9\\.\\-_\\+]*$'", 3),
    ("if ($t -match '^[A-Za-z]:\\\\?$' -or $t -match '(?i)\\\\temp\\\\?$|\\\\users\\\\[^\\\\]+\\\\?$|\\\\downloads\\\\?$')",
     "if ($t -cmatch '^[A-Za-z]:\\\\?$' -or $t.ToLowerInvariant() -cmatch '\\\\temp\\\\?$|\\\\users\\\\[^\\\\]+\\\\?$|\\\\downloads\\\\?$')", 1),
    ("$isMs = ($path -match '(?i)\\\\windows\\\\|\\\\windows defender\\\\|\\\\microsoft\\\\|\\\\windowsapps\\\\|svchost\\.exe|^\"?[a-z]:\\\\windows')",
     "$isMs = ($path.ToLowerInvariant() -cmatch '\\\\windows\\\\|\\\\windows defender\\\\|\\\\microsoft\\\\|\\\\windowsapps\\\\|svchost\\.exe|^\"?[a-z]:\\\\windows')", 1),
    ("if ($d -match '(?i)^[a-z]:\\\\(windows|program files|program files \\(x86\\))\\\\')",
     "if ($d.ToLowerInvariant() -cmatch '^[a-z]:\\\\(windows|program files|program files \\(x86\\))\\\\')", 1),
    ("$h -notmatch '^[A-Za-z0-9][A-Za-z0-9\\.\\-:]{0,200}$'", "$h -cnotmatch '^[A-Za-z0-9][A-Za-z0-9\\.\\-:]{0,200}$'", 1),
    ("$n -notmatch '^[A-Za-z0-9_\\.\\-]{1,80}$'", "$n -cnotmatch '^[A-Za-z0-9_\\.\\-]{1,80}$'", 1),
    ("$name -notmatch '^[A-Za-z0-9_.\\-]{1,80}$'", "$name -cnotmatch '^[A-Za-z0-9_.\\-]{1,80}$'", 1),
    ("$id -notmatch '^[A-Za-z0-9_]{2,40}$'", "$id -cnotmatch '^[A-Za-z0-9_]{2,40}$'", 1),
    ("    return ($Path -match '(?i)\\\\(AppData|Temp|Downloads|Users\\\\Public|Windows\\\\Temp)\\\\' -or $Path -match '(?i)^[a-z]:\\\\(Users\\\\[^\\\\]+\\\\)?(Desktop|Documents)\\\\')",
     "    $lp = $Path.ToLowerInvariant()\n"
     "    return ($lp -cmatch '\\\\(appdata|temp|downloads|users\\\\public|windows\\\\temp)\\\\' -or $lp -cmatch '^[a-z]:\\\\(users\\\\[^\\\\]+\\\\)?(desktop|documents)\\\\')", 1),
    ("$exe -notmatch '^[a-zA-Z]:\\\\'", "$exe -cnotmatch '^[a-zA-Z]:\\\\'", 1),
    ("$exe -match '^[a-zA-Z]:\\\\' -and", "$exe -cmatch '^[a-zA-Z]:\\\\' -and", 1),
    ("$K -notmatch '^[A-Za-z0-9+/]{43}=$'", "$K -cnotmatch '^[A-Za-z0-9+/]{43}=$'", 1),
    ("[string]$h['loc'] -match '^[A-Za-z]{2}$'", "[string]$h['loc'] -cmatch '^[A-Za-z]{2}$'", 1),
    ("[string]$h['colo'] -match '^[A-Za-z]{3,4}$'", "[string]$h['colo'] -cmatch '^[A-Za-z]{3,4}$'", 1),
    ("$drive -match '^[A-Z]$'", "$drive -cmatch '^[A-Z]$'", 2),
    ("$drive -notmatch '^[A-Z]:$'", "$drive -cnotmatch '^[A-Z]:$'", 2),
    ("$v -match '^[A-Za-z]:/'", "$v -cmatch '^[A-Za-z]:/'", 1),
    ("$Exe -notmatch '^[A-Za-z]:\\\\[^\"<>|*?\\r\\n]+\\.exe$'", "$Exe -cnotmatch '^[A-Za-z]:\\\\[^\"<>|*?\\r\\n]+\\.[Ee][Xx][Ee]$'", 1),
    ("$match -notmatch '^[A-Za-z0-9\\.\\-_~]{3,80}$'", "$match -cnotmatch '^[A-Za-z0-9\\.\\-_~]{3,80}$'", 1),
    ("$Path -notmatch '^[A-Za-z]:\\\\')", "$Path -cnotmatch '^[A-Za-z]:\\\\')", 1),
    ("    $deny = '(?i)^[A-Za-z]:\\\\(Windows|\\$Recycle\\.Bin|System Volume Information|Recovery|Boot|EFI|PerfLogs)(\\\\|$)|\\\\WinSxS(\\\\|$)|\\\\WindowsApps(\\\\|$)|\\\\Windows Defender|\\\\Microsoft\\\\Windows Defender|\\\\AppData\\\\Local\\\\Packages(\\\\|$)|\\\\OneDrive|\\\\Multimizer(\\\\|$)'\n"
     "    if ($p -match $deny)",
     "    $deny = '^[a-z]:\\\\(windows|\\$recycle\\.bin|system volume information|recovery|boot|efi|perflogs)(\\\\|$)|\\\\winsxs(\\\\|$)|\\\\windowsapps(\\\\|$)|\\\\windows defender|\\\\microsoft\\\\windows defender|\\\\appdata\\\\local\\\\packages(\\\\|$)|\\\\onedrive|\\\\multimizer(\\\\|$)'\n"
     "    if ($p.ToLowerInvariant() -cmatch $deny)", 1),
    ("if ($p -match '(?i)^[A-Za-z]:\\\\Users\\\\[^\\\\]+$')", "if ($p.ToLowerInvariant() -cmatch '^[a-z]:\\\\users\\\\[^\\\\]+$')", 1),
    ("if ($p -match '(?i)^[A-Za-z]:\\\\(Program Files|Program Files \\(x86\\)|ProgramData|Users)$')",
     "if ($p.ToLowerInvariant() -cmatch '^[a-z]:\\\\(program files|program files \\(x86\\)|programdata|users)$')", 1),
    ("$m = $m -replace '[A-Za-z]:\\\\[^\\s,;]*', '<yol>'", "$m = $m -creplace '[A-Za-z]:\\\\[^\\s,;]*', '<yol>'", 1),
    ("$Line -match '^\\d{2}:\\d{2}:\\d{2}\\s+([A-Z]+)\\s'", "$Line -cmatch '^\\d{2}:\\d{2}:\\d{2}\\s+([A-Z]+)\\s'", 1),
    ("$Text -notmatch '^[A-Za-z0-9]{3,32}$'", "$Text -cnotmatch '^[A-Za-z0-9]{3,32}$'", 1),

    ("$nm -match '^[\\x20-\\x7E]+$'", "$nm -cmatch '^[\\x20-\\x7E]+$'", 2),

    # ---- konsol çıktı kodlaması: işletim sisteminin OEM kod sayfası
    ("[System.Text.Encoding]::GetEncoding([System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage)", "(Get-OemEncoding)", 3),

    # ---- kültür koruması: betiğin başı, arka plan çalışma alanları
    ("$script:AppName    = 'Multimizer'\n", CULTURE_BLOCK + "$script:AppName    = 'Multimizer'\n", 1),
    ("    $rs.SessionStateProxy.SetVariable('CoreText', $script:CoreText)\n",
     "    $rs.SessionStateProxy.SetVariable('CoreText', $script:CoreText)\n    $rs.SessionStateProxy.SetVariable('CultureText', $script:CultureText)\n", 1),
    ("[void]$ps.AddScript('$ErrorActionPreference = ''Continue''; $ProgressPreference = ''SilentlyContinue''; . ([scriptblock]::Create($CoreText))')",
     "[void]$ps.AddScript('$ErrorActionPreference = ''Continue''; $ProgressPreference = ''SilentlyContinue''; . ([scriptblock]::Create($CultureText)); [void](Set-MmCulture); . ([scriptblock]::Create($CoreText))')", 1),
    ("$script:AsyncWrapper = @'\ntry {\n    if (Test-NetBlocked $Entry)", "$script:AsyncWrapper = @'\ntry { [void](Set-MmCulture) } catch { }\ntry {\n    if (Test-NetBlocked $Entry)", 1),

    # ---- kendi kendine sınama: katalog işlem türleri, şablon sayımı iletileri, harf duyarlı eşleşmeler
    ("$types = @('Reg', 'Svc', 'Task', 'Appx', 'Mp', 'Dns', 'Feature', 'Func', 'Fw', 'EvtLog')\n",
     "$types = @('Reg', 'Svc', 'Task', 'Appx', 'Mp', 'Dns', 'Feature', 'Func', 'Fw', 'EvtLog') + @($script:MoreOps.Keys | ForEach-Object { [string]$_ })\n", 1),
    ("$_.Name -match '^Page_[a-z]+$'", "$_.Name -cmatch '^Page_[a-z]+$'", 1),
    ("$_.Name -match '^Row_[A-Za-z]+$' })\n"
     "        if ($vars.Count -lt 6) { return (([string][char]0x015F + 'ablon say' + [char]0x0131 + 's' + [char]0x0131 + ': ') + $vars.Count) }",
     "$_.Name -cmatch '^Row_[A-Za-z]+$' })\n"
     "        if ($vars.Count -lt 6) { return (([string][char]0x015F + 'ablon say' + [char]0x0131 + 's' + [char]0x0131 + ': ') + $vars.Count + ' (' + (($vars | ForEach-Object { [string]$_.Name }) -join ', ') + ')') }", 1),
    ("$n -notmatch '^[A-Za-z0-9_=+.\\-]{1,32}$'", "$n -cnotmatch '^[A-Za-z0-9_=+.\\-]{1,32}$'", 1),
]


def apply(b):
    b.add_core('136_oem_kultur.ps1', title='oem kodlama ve kultur sinamasi')
    for old, new, cnt in REPS:
        b.rep(old, new, count=cnt, raw=("@'" in old), name='p49 ' + old[:40])
    b.before(SELF_ANCHOR, CULTURE_STEP)
