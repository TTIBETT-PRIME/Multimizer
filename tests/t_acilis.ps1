. "$PSScriptRoot/lib.ps1"
# Pencere acmayan baslatma: Acilis.ps1 (acilis ekrani + denetci), uygulama tarafi (-Gizli) ve Baslat.bat ile uyumu.
# WinForms bu ortamda yoktur; cizim disindaki tum mantik (dil secimi, arguman tirnaklama, asama dosyasi, karar tablosu, denetci dongusu) sinanir.

$acPath = Join-Path $script:TestDir 'Acilis.ps1'
Assert-True (Test-Path -LiteralPath $acPath) 'Acilis.ps1 Multimizer.ps1 ile ayni klasorde'
$acBytes = [System.IO.File]::ReadAllBytes($acPath)
Assert-Eq @($acBytes | Where-Object { $_ -ge 128 }).Count 0 'Acilis.ps1 yalnizca ASCII (metinler \uXXXX olarak gomulu)'
$acText = [System.Text.Encoding]::ASCII.GetString($acBytes)
$tok = $null; $err = $null
$acAst = [System.Management.Automation.Language.Parser]::ParseFile($acPath, [ref]$tok, [ref]$err)
Assert-Eq @($err).Count 0 'Acilis.ps1 soz dizimi temiz'

# ---- betikten islevleri ve metin tablosunu yukle (ust duzey kod calistirilmaz)
$fnAsts = @($acAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))
function Import-AcFn([string]$Name) {
    $f = @($fnAsts | Where-Object { $_.Name -eq $Name }) | Select-Object -Last 1
    if ($null -eq $f) { throw ('islev yok: ' + $Name) }
    . ([scriptblock]::Create($f.Extent.Text))
    Set-Item -Path ('function:global:' + $Name) -Value (Get-Item ('function:' + $Name)).ScriptBlock
}
foreach ($n in @('Resolve-LaunchLang', 'Get-LaunchLang', 'Get-LT', 'ConvertTo-ArgLine', 'Read-LaunchStatus', 'Get-ProgressTarget', 'Get-StartDecision', 'Get-AppVersionText',
        'Test-ProcessAlive', 'Add-LaunchTrace', 'Remove-QuietFile', 'Write-LaunchResult', 'Test-IsAdmin', 'Step-Launch', 'Invoke-Denetci', 'Show-LaunchMessage', 'Test-GuiRunning', 'Send-ShowSignal')) { Import-AcFn $n }
foreach ($vn in @('LTKeys', 'LTData')) {
    $a = @($acAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq ('$script:' + $vn) }, $true))[0]
    Assert-True ($null -ne $a) ('tablo atamasi var: ' + $vn)
    . ([scriptblock]::Create($a.Extent.Text))
}

# ---- metin tablosu
$langs = @('tr', 'en', 'de', 'fr', 'es', 'it', 'pt', 'ru', 'ja', 'ko', 'zh', 'zh-hant', 'ar')
Assert-Eq (@($script:LTData.Keys | Sort-Object) -join ',') (($langs | Sort-Object) -join ',') 'tablodaki diller beklenen 13 dil'
foreach ($l in $langs) {
    $arr = @($script:LTData[$l])
    Assert-Eq $arr.Count $script:LTKeys.Count ("$l : her anahtar icin metin var")
    $bos = @($arr | Where-Object { [string]::IsNullOrWhiteSpace([string]$_) })
    Assert-Eq $bos.Count 0 ("$l : bos metin yok")
    $hi = [array]::IndexOf($script:LTKeys, 'hata')
    Assert-True (([regex]::Unescape([string]$arr[$hi])) -match '\{0\}') ("$l : hata iletisinde {0} yer tutucusu var")
}
$script:LaunchLang = 'tr'
$tr = Get-LT 'baslat'
Assert-Eq $tr ('Multimizer ba' + [char]0x015F + 'lat' + [char]0x0131 + 'l' + [char]0x0131 + 'yor' + [char]0x2026) 'Turkce metin dogru cozulur (\u escape)'
$script:LaunchLang = 'ja'
Assert-True ((Get-LT 'hazir') -eq ([string][char]0x6E96 + [char]0x5099 + [char]0x5B8C + [char]0x4E86) ) 'Japonca metin dogru'
$script:LaunchLang = 'ar'
Assert-True ((Get-LT 'hazir') -eq ([string][char]0x062C + [char]0x0627 + [char]0x0647 + [char]0x0632) ) 'Arapca metin dogru'
$script:LaunchLang = 'en'
Assert-Eq (Get-LT 'hazir') 'Ready' 'Ingilizce metin'
Assert-Eq (Get-LT 'olmayan-anahtar') 'olmayan-anahtar' 'bilinmeyen anahtar anahtarin kendisini dondurur'
$script:LaunchLang = 'xx'
Assert-Eq (Get-LT 'hazir') 'Ready' 'bilinmeyen dil Ingilizceye duser'
# kullanilan her Get-LT anahtari tabloda var
$used = New-Object System.Collections.ArrayList
foreach ($m in [regex]::Matches($acText, "Get-LT\s+'([a-z_]+)'")) { [void]$used.Add($m.Groups[1].Value) }
foreach ($m in [regex]::Matches($acText, "Get-LT\s+\(\[string\]\$st\.Key\)")) { }
Assert-True ($used.Count -ge 5) 'betik Get-LT ile metin okur'
foreach ($k in ($used | Sort-Object -Unique)) { Assert-True ($script:LTKeys -contains $k) ("kullanilan metin anahtari tabloda: $k") }
# acilis asamalari: uygulamanin asama anahtarlari tabloda
foreach ($k in @('arayuz', 'veri', 'cekirdek', 'ayarlar', 'calisma', 'sistem', 'pencere', 'hazir')) { Assert-True ($script:LTKeys -contains $k) ("asama metni var: $k") }

# ---- dil secimi
$cases = @{ 'tr-TR' = 'tr'; 'en-US' = 'en'; 'de-AT' = 'de'; 'fr-CA' = 'fr'; 'zh-CN' = 'zh'; 'zh-Hans-CN' = 'zh'; 'zh-SG' = 'zh'; 'zh-TW' = 'zh-hant'; 'zh-Hant-HK' = 'zh-hant'; 'zh-MO' = 'zh-hant'
    'pt-BR' = 'pt'; 'pt_PT' = 'pt'; 'ar-SA' = 'ar'; 'ja-JP' = 'ja'; 'ko-KR' = 'ko'; 'ru-RU' = 'ru'; 'xx-YY' = 'en'; '' = 'en'; 'nb-NO' = 'en'; 'ES' = 'es'; 'it' = 'it' }
foreach ($k in $cases.Keys) { Assert-Eq (Resolve-LaunchLang $k) $cases[$k] ("dil kodu: [$k]") }
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('mm-acilis-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
$script:DataDir = $tmp
$oldDil = $env:MM_DIL
try {
    $env:MM_DIL = ''
    Assert-Eq (Get-LaunchLang @('-Dil', 'de')) 'de' '-Dil parametresi onceliklidir'
    Assert-Eq (Get-LaunchLang @('-Guvenli', '-dil', 'ja', '-DebugLog')) 'ja' '-Dil arguman listesinin ortasinda da bulunur'
    $env:MM_DIL = 'fr'
    Assert-Eq (Get-LaunchLang @()) 'fr' 'MM_DIL ortam degiskeni'
    Assert-Eq (Get-LaunchLang @('-Dil', 'es')) 'es' '-Dil, MM_DIL degiskeninden onceliklidir'
    $env:MM_DIL = ''
    [System.IO.File]::WriteAllText((Join-Path $tmp 'ayarlar.json'), '{"Language":"ru","Theme":"neon"}')
    Assert-Eq (Get-LaunchLang @()) 'ru' 'ayarlar.json Language'
    [System.IO.File]::WriteAllText((Join-Path $tmp 'ayarlar.json'), '{"Language":"auto"}')
    $sys = Resolve-LaunchLang ([System.Globalization.CultureInfo]::CurrentUICulture.Name)
    Assert-Eq (Get-LaunchLang @()) $sys 'auto: Windows ekran dili'
    [System.IO.File]::WriteAllText((Join-Path $tmp 'ayarlar.json'), '{bozuk json')
    Assert-True ($langs -contains (Get-LaunchLang @())) 'bozuk ayar dosyasi: yine gecerli bir dil'
} finally { $env:MM_DIL = $oldDil }

# ---- arguman tirnaklama: Windows (CommandLineToArgvW / C calisma zamani) kurallariyla gidis-donus
function Split-WinArgs([string]$Line) {
    $res = New-Object System.Collections.ArrayList
    $sb = New-Object System.Text.StringBuilder
    $inQ = $false; $has = $false; $i = 0
    while ($i -lt $Line.Length) {
        $c = $Line[$i]
        if ($c -eq '\') {
            $n = 0
            while ($i -lt $Line.Length -and $Line[$i] -eq '\') { $n++; $i++ }
            if ($i -lt $Line.Length -and $Line[$i] -eq '"') {
                [void]$sb.Append('\', [int][math]::Floor($n / 2)); $has = $true
                if ($n % 2 -eq 1) { [void]$sb.Append('"'); $i++ }
            } else { [void]$sb.Append('\', $n); $has = $true }
            continue
        }
        if ($c -eq '"') { $inQ = -not $inQ; $has = $true; $i++; continue }
        if (($c -eq ' ' -or $c -eq "`t") -and -not $inQ) {
            if ($has) { [void]$res.Add($sb.ToString()); [void]$sb.Clear(); $has = $false }
            $i++; continue
        }
        [void]$sb.Append($c); $has = $true; $i++
    }
    if ($has) { [void]$res.Add($sb.ToString()) }
    return $res.ToArray()
}
$samples = @(
    @('-Guvenli'), @('-Dil', 'de'), @('C:\Program Files\Multimizer\Multimizer.ps1'), @('x"y'), @('C:\a b\'), @(''), @('a  b', 'c'), @('tek\cift\\'), @('"tam"'), @('-Deger', 'D:\Oyunlar\Oyun 1\')
)
foreach ($s in $samples) {
    $line = ConvertTo-ArgLine ([string[]]$s)
    $back = @(Split-WinArgs $line)
    Assert-Eq ($back -join '|') ($s -join '|') ('arguman gidis-donus: ' + ($s -join ' | '))
}
Assert-Eq (ConvertTo-ArgLine ([string[]]@('-NoProfile', '-File', 'C:\x y\a.ps1'))) '-NoProfile -File "C:\x y\a.ps1"' 'bosluklu yol tirnaklanir, digerleri tirnaksiz'

# ---- asama dosyasi
$sf = Join-Path $tmp 'acilis-1234.txt'
Assert-True ($null -eq (Read-LaunchStatus $sf)) 'dosya yok: bos'
[System.IO.File]::WriteAllText($sf, '36|75|sistem|4242')
$st = Read-LaunchStatus $sf
Assert-True ($null -ne $st -and $st.Pct -eq 36 -and $st.Next -eq 75 -and $st.Key -eq 'sistem') 'asama dosyasi okunur'
[System.IO.File]::WriteAllText($sf, 'bozuk')
Assert-True ($null -eq (Read-LaunchStatus $sf)) 'bozuk icerik: bos'
[System.IO.File]::WriteAllText($sf, 'x|75|sistem|1')
Assert-True ($null -eq (Read-LaunchStatus $sf)) 'sayisal olmayan yuzde: bos'

# ---- cubuk hedefi: tek yonlu, sonraki asamayi gecmez
$prev = -1.0; $ok = $true
foreach ($age in @(0, 1, 2, 5, 10, 30, 120, 600)) {
    $t = Get-ProgressTarget 36 75 $age
    if ($t -lt $prev -or $t -ge 75 -or $t -lt 36) { $ok = $false }
    $prev = $t
}
Assert-True $ok 'cubuk hedefi artar ve sonraki asamayi gecmez'
Assert-Eq (Get-ProgressTarget 100 100 50) 100 'son asama: 100'
Assert-Eq (Get-ProgressTarget 50 40 5) 50 'sonraki yuzde kucukse yerinde kalir'

# ---- karar tablosu
Assert-Eq (Get-StartDecision 0 $true 0) 'bitti' 'cikis 0: bitti'
Assert-Eq (Get-StartDecision 0 $false 0) 'bitti' 'cikis 0, pencere acilmamis (zaten acik kopya): bitti'
Assert-Eq (Get-StartDecision (-1073741510) $false 0) 'bitti' 'konsol kapatildi (0xC000013A): hata degil'
Assert-Eq (Get-StartDecision (-1073740791) $true 0) 'yeniden' 'pencere acildiktan sonra Windows cokme kodu: guvenli kipte bir kez daha'
Assert-Eq (Get-StartDecision (-1073740791) $true 1) 'tani' 'ikinci cokme: yeniden denenmez, rapor'
Assert-Eq (Get-StartDecision (-1073740791) $false 0) 'tani' 'pencere hic acilmadiysa: rapor (yeniden deneme degil)'
Assert-Eq (Get-StartDecision 1 $true 0) 'tani' 'pozitif kod (Gorev Yoneticisi ile sonlandirma): yeniden baslatilmaz'
Assert-Eq (Get-StartDecision 4 $false 0) 'tani' 'ana pencere acilamadi (4): rapor'
Assert-Eq (Get-StartDecision 5 $true 0) 'tani' 'gorunum hatasi (5): rapor'

# ---- surum metni
$vp = Join-Path $tmp 'Multimizer.ps1'
[System.IO.File]::WriteAllText($vp, "<#`r`n    Multimizer.ps1  -  deneme`r`n    Surum   : 10.2.3-beta`r`n#>`r`nWrite-Host 1`r`n")
$script:AppPs1 = $vp
Assert-Eq (Get-AppVersionText) '10.2.3-beta' 'surum metni betik basliginden okunur'
$script:AppPs1 = Join-Path $tmp 'yok.ps1'
Assert-Eq (Get-AppVersionText) '' 'dosya yoksa bos'

# ---- surec denetimi
Assert-True (Test-ProcessAlive $PID) 'kendi sureci canli'
Assert-True (-not (Test-ProcessAlive 2147480000)) 'olmayan surec canli degil'
Assert-True (-not (Test-ProcessAlive 0)) 'surec 0 canli sayilmaz'

# ---- Step-Launch (acilis ekrani durum makinesi)
function New-FakeAsync([string]$Result, [bool]$Done = $true) {
    $ps = [pscustomobject]@{ Result = $Result }
    Add-Member -InputObject $ps -MemberType ScriptMethod -Name EndInvoke -Value { param($a) return $this.Result }
    $as = [pscustomobject]@{ IsCompleted = $Done }
    return @{ Ps = $ps; Async = $as }
}
function Reset-Step([string]$Result, [int]$Ms = 100, [bool]$Done = $true) {
    $fa = New-FakeAsync $Result $Done
    $script:Ps = $fa.Ps; $script:Async = $fa.Async
    $script:DenPid = 0; $script:Phase = 'baslat'; $script:Stat = $null; $script:StatAt = 0; $script:Text = ''; $script:ErrText = ''
    $script:Clock = [pscustomobject]@{ ElapsedMilliseconds = $Ms }
    $script:PhaseKeys = @('arayuz', 'veri', 'cekirdek', 'ayarlar', 'calisma', 'sistem', 'pencere', 'hazir')
    $script:LaunchLang = 'en'
}
$Kod = '777000'
foreach ($f in @('acilis-777000.txt', 'oturum-acik-777000.txt', 'acilis-777000.son')) { Remove-Item -LiteralPath (Join-Path $tmp $f) -Force -ErrorAction SilentlyContinue }
Reset-Step 'ERR:1223:The operation was canceled by the user.'
Assert-Eq (Step-Launch) 'izin' 'UAC iptal (1223): izin'
Reset-Step 'ERR:5:Access denied'
Assert-Eq (Step-Launch) 'olu' 'baska baslatma hatasi: olu'
Assert-True ($script:ErrText -match 'Access denied') 'hata metni saklanir'
Reset-Step 'OK:2147480000' 100 $false
Assert-Eq (Step-Launch) '' 'islem henuz bitmedi: devam'
Reset-Step 'OK:2147480000' 100
Assert-Eq (Step-Launch) '' 'denetci baslatildi: devam'
Assert-Eq $script:Phase 'calisiyor' 'asama: calisiyor'
Assert-Eq $script:DenPid 2147480000 'denetci surec numarasi alinir'
[System.IO.File]::WriteAllText((Join-Path $tmp 'acilis-777000.txt'), '36|75|sistem|55')
Assert-Eq (Step-Launch) '' 'asama dosyasi: devam'
Assert-Eq $script:Stat.Key 'sistem' 'asama okundu'
Assert-Eq $script:Text 'Collecting system information' 'durum metni asamaya gore degisir'
[System.IO.File]::WriteAllText((Join-Path $tmp 'oturum-acik-777000.txt'), '55 x')
Assert-Eq (Step-Launch) 'acildi' 'isaret dosyasi: pencere acildi'
Remove-Item -LiteralPath (Join-Path $tmp 'oturum-acik-777000.txt') -Force
[System.IO.File]::WriteAllText((Join-Path $tmp 'acilis-777000.son'), '4|tani')
Assert-Eq (Step-Launch) 'bitti' 'sonuc dosyasi: bitti'
Remove-Item -LiteralPath (Join-Path $tmp 'acilis-777000.son') -Force
Reset-Step 'OK:2147480000' 6000
$null = Step-Launch
$script:Clock = [pscustomobject]@{ ElapsedMilliseconds = 6000 }
Assert-Eq (Step-Launch) 'olu' 'denetci sonuc yazmadan oldu: olu'
$script:Clock = [pscustomobject]@{ ElapsedMilliseconds = 400000 }
$script:DenPid = $PID
Assert-Eq (Step-Launch) 'sure' '5 dakikayi asan bekleme: sure'

# ---- Denetci dongusu (Start-Process sahte)
$script:Rol = 'Denetci'
$script:AppPs1 = Join-Path $tmp 'Multimizer.ps1'
$script:TaniPs1 = Join-Path $tmp 'Tani.ps1'
$script:PsExe = 'powershell.exe'
$script:Forward = @('-Dil', 'de')
$script:Calls = New-Object System.Collections.ArrayList
$script:Scenario = @()
$script:ScenarioIdx = 0
$script:Opened = @()
function global:Start-Process {
    param($FilePath, $ArgumentList, $WindowStyle, [switch]$PassThru, $ErrorAction, $Verb)
    $i = [int]$script:ScenarioIdx
    $script:ScenarioIdx = $i + 1
    [void]$script:Calls.Add([string]$ArgumentList)
    if ($i -lt $script:Opened.Count -and $script:Opened[$i]) {
        $code = [regex]::Match([string]$ArgumentList, '-Oturum (\S+)').Groups[1].Value
        [System.IO.File]::WriteAllText((Join-Path $script:DataDir ('oturum-acik-' + $code + '.txt')), 'x')
    }
    $p = [pscustomobject]@{ Id = 9000 + $i; Handle = 1; ExitCode = [int]$script:Scenario[$i] }
    Add-Member -InputObject $p -MemberType ScriptMethod -Name WaitForExit -Value { }
    return $p
}
function Reset-Den($Codes, $OpenedFlags) {
    $script:Calls.Clear()
    $script:Scenario = $Codes; $script:Opened = $OpenedFlags; $script:ScenarioIdx = 0
    foreach ($f in @('acilis-777000.txt', 'acilis-777000g.txt', 'oturum-acik-777000.txt', 'oturum-acik-777000g.txt', 'acilis-777000.son', 'tani-cagri.txt')) { Remove-Item -LiteralPath (Join-Path $tmp $f) -Force -ErrorAction SilentlyContinue }
}
[System.IO.File]::WriteAllText($script:TaniPs1, 'param([int]$ExitCode = 0, [string]$Mod = '''', [switch]$Gizli)' + "`r`n" + '[System.IO.File]::WriteAllText((Join-Path ' + "'" + $tmp + "'" + ' ''tani-cagri.txt''), ([string]$ExitCode + ''|'' + $Mod + ''|'' + [string]$Gizli))' + "`r`n")
function global:Test-GuiRunning { return [bool]$script:GuiRunning }
$script:GuiRunning = $false
function Get-DenSon { $f = Join-Path $tmp 'acilis-777000.son'; if (Test-Path -LiteralPath $f) { return [System.IO.File]::ReadAllText($f) } return '' }

# a) normal calisma ve cikis 0
Reset-Den @(0) @($true)
$rc = @(Invoke-Denetci)[-1]
Assert-Eq $rc 0 'denetci: normal kapanis 0 dondurur'
Assert-Eq $script:Calls.Count 1 'uygulama bir kez baslatilir'
Assert-True ($script:Calls[0] -match '-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File ') 'uygulama gizli pencereyle ve STA ile baslar'
Assert-True ($script:Calls[0] -match ' -Gizli -Oturum 777000') 'uygulamaya -Gizli ve -Oturum KOD verilir'
Assert-True ($script:Calls[0] -match ' -Dil de') 'kullanicinin parametreleri uygulamaya aktarilir'
Assert-True ($script:Calls[0] -notmatch '-Guvenli') 'ilk calistirma guvenli kipte degil'
Assert-True (-not (Test-Path -LiteralPath (Join-Path $tmp 'tani-cagri.txt'))) 'sorun yok: rapor gosterilmez'
Assert-True ((Get-DenSon) -match '^0\|bitti') 'sonuc dosyasi: 0|bitti'

# b) pencere acildiktan sonra cokme -> guvenli kipte bir kez yeniden, ikincisi temiz
Reset-Den @(-1073740791, 0) @($true, $true)
$rc = @(Invoke-Denetci)[-1]
Assert-Eq $rc 0 'denetci: cokme sonrasi guvenli kip basarili'
Assert-Eq $script:Calls.Count 2 'uygulama iki kez baslatilir'
Assert-True ($script:Calls[1] -match ' -Guvenli') 'ikinci calistirma -Guvenli ile'
Assert-True ($script:Calls[1] -match '-Oturum 777000g') 'ikinci calistirmanin kodu farkli (777000g)'
Assert-True (-not (Test-Path -LiteralPath (Join-Path $tmp 'tani-cagri.txt'))) 'basarili yeniden deneme: rapor gosterilmez'

# c) iki kez cokme -> rapor
Reset-Den @(-1073740791, -1073740791) @($true, $true)
$rc = @(Invoke-Denetci)[-1]
Assert-Eq $script:Calls.Count 2 'en cok iki baslatma'
Assert-True (Test-Path -LiteralPath (Join-Path $tmp 'tani-cagri.txt')) 'ikinci cokmede rapor penceresi acilir'
Assert-True ([System.IO.File]::ReadAllText((Join-Path $tmp 'tani-cagri.txt')) -eq '-1073740791|Gui|True') 'Tani.ps1 cikis kodu, Gui kipi ve -Gizli ile cagrilir'
Assert-Eq $rc (-1073740791) 'denetci uygulamanin cikis kodunu dondurur'
Assert-True ((Get-DenSon) -match '^-1073740791\|tani') 'sonuc dosyasi: tani'

# d) pencere hic acilmadi (kod 4) -> rapor, yeniden deneme yok
Reset-Den @(4) @($false)
$rc = @(Invoke-Denetci)[-1]
Assert-Eq $script:Calls.Count 1 'acilmayan uygulama yeniden baslatilmaz'
Assert-True ([System.IO.File]::ReadAllText((Join-Path $tmp 'tani-cagri.txt')) -eq '4|Gui|True') 'rapor, cikis kodu 4 ile'

# e) zaten calisan kopya: ikinci uygulama baslatilmaz
Reset-Den @(0) @($false)
$script:GuiRunning = $true
$rc = @(Invoke-Denetci)[-1]
$script:GuiRunning = $false
Assert-Eq $script:Calls.Count 0 'zaten acik: yeni uygulama baslatilmaz'
Assert-Eq $rc 0 'zaten acik: cikis 0'
Assert-True ((Get-DenSon) -match 'zaten-acik') 'sonuc: zaten-acik'

# f) kullanici onceki oturum isaretini birakmissa silinir (eski dosya pencere acildi sanilmaz)
Reset-Den @(0) @($false)
[System.IO.File]::WriteAllText((Join-Path $tmp 'oturum-acik-777000.txt'), 'eski')
$null = Invoke-Denetci
Assert-True (-not (Test-Path -LiteralPath (Join-Path $tmp 'oturum-acik-777000.txt'))) 'eski isaret dosyasi temizlenir'

# g) betik yok
Remove-Item -LiteralPath $script:AppPs1 -Force -ErrorAction SilentlyContinue
function global:Show-LaunchMessage { param([string]$Text) $script:LastMsg = $Text }
Reset-Den @(0) @($false)
$rc = @(Invoke-Denetci)[-1]
Assert-Eq $rc 1 'Multimizer.ps1 yoksa 1'
Assert-Eq $script:Calls.Count 0 'betik yoksa hicbir sey baslatilmaz'
Assert-True ($script:LastMsg -match 'Multimizer\.ps1') 'betik yoksa kullaniciya ileti'
Remove-Item Function:\Start-Process, Function:\Test-GuiRunning, Function:\Show-LaunchMessage -ErrorAction SilentlyContinue

# ---- eslesme: uygulama / Baslat.bat / Acilis.ps1 ayni dosya adlarini kullanir
$appText = [System.IO.File]::ReadAllText($script:TestPath)
$batText = [System.IO.File]::ReadAllText((Join-Path $script:TestDir 'Baslat.bat'))
Assert-True ($appText -match "\[switch\]\`$Gizli") 'uygulamada -Gizli parametresi var'
Assert-True ($appText -match "'acilis-' \+ \`$Oturum \+ '\.txt'") 'uygulama asama dosyasini acilis-KOD.txt adiyla yazar'
Assert-True ($acText -match "'acilis-' \+ \`$Kod \+ '\.txt'") 'Acilis.ps1 ayni dosyayi okur'
Assert-True ($appText -match "'oturum-acik-' \+ \`$script:RunToken \+ '\.txt'" -and $acText -match "'oturum-acik-' \+ \`$Kod \+ '\.txt'") 'pencere acildi isareti iki tarafta ayni'
Assert-True ($batText -match 'mm-basladi-%MM_RUN%\.txt' -and $acText -match "'mm-basladi-' \+ \`$Kod \+ '\.txt'") 'el sikisma dosyasi Baslat.bat ve Acilis.ps1 arasinda ayni'
Assert-True ($batText -match '-File "%MM_ACILIS%" -Kod %MM_RUN% %MM_ARGS%') 'Baslat.bat Acilis.ps1 dosyasini kodla ve kullanici parametreleriyle acar'
Assert-True ($batText -match '-WindowStyle Hidden -File "%MM_ACILIS%"') 'Acilis.ps1 gizli pencereyle acilir'

# ---- uygulama tarafi: asama dosyasi
Import-Fn 'Write-SplashFile', 'Start-Splash', 'Update-Splash', 'Set-SplashStep', 'Stop-Splash', 'Complete-Splash', 'Write-SplashRaw', 'Set-SplashCursorVisible'
Import-Var 'SplashPhases'
$oldPD = $env:ProgramData
$pd = Join-Path $tmp 'pd'
New-Item -ItemType Directory -Path $pd -Force | Out-Null
$env:ProgramData = $pd
$script:SplashOn = $false; $script:SplashMode = 'off'; $script:SplashIdx = 0; $script:SplashTimes = @{}; $script:SplashClock = $null
$Gizli = $true; $Oturum = 'abc123'
function global:Write-Host { }
Start-Splash
$sfile = Join-Path (Join-Path $pd 'Multimizer') 'acilis-abc123.txt'
Assert-Eq $script:SplashMode 'dosya' 'gizli kip: dosya kipi'
Assert-True $script:SplashOn 'gizli kip: acilis ekrani etkin'
Assert-True (Test-Path -LiteralPath $sfile) 'asama dosyasi ProgramData\Multimizer altinda'
$s0 = Read-LaunchStatus $sfile
Assert-True ($s0.Key -eq 'konsol' -and $s0.Pct -eq 0) 'ilk asama: konsol 0'
Set-SplashStep 'arayuz'
$s1 = Read-LaunchStatus $sfile
Assert-True ($s1.Key -eq 'arayuz' -and $s1.Pct -eq 4 -and $s1.Next -eq 5) 'arayuz asamasi: 4 -> 5'
Set-SplashStep 'sistem'
$s2 = Read-LaunchStatus $sfile
Assert-True ($s2.Key -eq 'sistem' -and $s2.Pct -eq 36 -and $s2.Next -eq 75) 'sistem asamasi: 36 -> 75'
Set-SplashStep 'veri'
Assert-Eq (Read-LaunchStatus $sfile).Key 'sistem' 'geriye gidis yok sayilir'
Complete-Splash
$s3 = Read-LaunchStatus $sfile
Assert-True ($s3.Key -eq 'hazir' -and $s3.Pct -eq 100) 'tamamlaninca hazir 100'
Assert-True ([System.IO.File]::ReadAllText($sfile) -match '\|\d+$') 'satirin sonunda surec numarasi var'
Assert-True (-not $script:SplashOn) 'Complete-Splash sonrasi acilis ekrani kapali'
# kod yok ya da gecersiz: dosya yazilmaz, konsola da cizilmez
Remove-Item -LiteralPath $sfile -Force
$script:SplashOn = $false; $script:SplashMode = 'off'; $script:SplashIdx = 0
$Oturum = ''
Start-Splash
Assert-True (-not $script:SplashOn -and $script:SplashMode -eq 'off') 'kod yoksa acilis ekrani yok'
Assert-True (-not (Test-Path -LiteralPath $sfile)) 'kod yoksa dosya yazilmaz'
$Oturum = '../zararli'
$script:SplashOn = $false
Start-Splash
Assert-True (-not $script:SplashOn) 'gecersiz kod (yol karakterleri) reddedilir'
Remove-Item Function:\Write-Host -ErrorAction SilentlyContinue
$Gizli = $false; $Oturum = ''
$env:ProgramData = $oldPD

# ---- uygulama tarafi: konsol gizleme, yeniden baslatma, kisayol, kurulum
$hide = $script:Ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Hide-ConsoleWindow' }, $true)
Assert-True ($hide.Body.Extent.Text -match '^\{\s*if \(\$Gizli\) \{ return \}') 'Hide-ConsoleWindow gizli kipta hemen doner (kucultme dali gizli konsolu gorunur yapardi)'
$sp = $appText.IndexOf('function New-AppShortcut')
$shortcut = $appText.Substring($sp, 1400)
Assert-True ($shortcut -match 'Acilis\.ps1') 'kisayol Acilis.ps1 dosyasini acar (varsa)'
$ia = $appText.IndexOf('function Install-AppFiles')
$inst = $appText.Substring($ia, 2200)
Assert-True ($inst -match "'Acilis\.ps1', 'Tani\.ps1'") 'kurulum Acilis.ps1 ve Tani.ps1 dosyalarini da kopyalar'
$rel = $appText.IndexOf('if ($Guvenli) { [void]$parts.Add(''-Guvenli'') }')
Assert-True ($rel -gt 0 -and $appText.Substring($rel, 200) -match '-Gizli') 'yeniden baslatma blogu -Gizli aktarir'
Assert-True ($appText -match 'if \(\$Cli -or \$Tepsi -or \$Gizli\) \{ \$winStyle = ''Hidden'' \}') 'gizli kipte yeniden baslatma da gizli pencereyle'

Import-Fn 'Get-RestartArgs'
$rd = Join-Path $tmp 'rs'
New-Item -ItemType Directory -Path $rd -Force | Out-Null
[System.IO.File]::WriteAllText((Join-Path $rd 'Multimizer.ps1'), 'x')
function Read-RestartCommand([string]$Args2) {
    $m = [regex]::Match($Args2, '-EncodedCommand (\S+)$')
    return [System.Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($m.Groups[1].Value))
}
$script:GizliMode = $false
$cmd = Read-RestartCommand (Get-RestartArgs 'C:\Windows\powershell.exe' (Join-Path $rd 'Multimizer.ps1') 4321)
Assert-True ($cmd -match 'Multimizer\.ps1' -and $cmd -notmatch 'Acilis\.ps1') 'normal kipta yeniden baslatma betigi dogrudan acar'
Assert-True ($cmd -match 'Wait-Process -Id 4321') 'eski surecin bitmesi beklenir'
$script:GizliMode = $true
$cmd = Read-RestartCommand (Get-RestartArgs 'C:\Windows\powershell.exe' (Join-Path $rd 'Multimizer.ps1') 4321)
Assert-True ($cmd -match 'Multimizer\.ps1' -and $cmd -notmatch 'Acilis\.ps1') 'gizli kip ama Acilis.ps1 yok: betik dogrudan acilir'
[System.IO.File]::WriteAllText((Join-Path $rd 'Acilis.ps1'), 'x')
$cmd = Read-RestartCommand (Get-RestartArgs 'C:\Windows\powershell.exe' (Join-Path $rd 'Multimizer.ps1') 4321)
Assert-True ($cmd -match 'Acilis\.ps1" -Kod \d{6,9}''') 'gizli kip: yeniden baslatma Acilis.ps1 uzerinden, yeni kodla'
$script:GizliMode = $false

# ---- acilis ekrani tasarimi: ortali yerlesim, acik/koyu renkler, yumusak belirme (cizim disindaki mantik)
foreach ($n in @('Get-LaunchLight', 'Get-SplashPalette', 'Get-SplashLayout')) { Import-AcFn $n }
foreach ($l in $langs) {
    $script:LaunchLang = $l
    $sl = Get-LT 'slogan'
    Assert-True ($sl.Length -ge 12 -and $sl.Length -le 72) ("$l : slogan uygun uzunlukta (" + $sl.Length + ')')
    Assert-True ($sl -notmatch '\{\d\}') ("$l : slogan yer tutucu icermez")
    Assert-True ($sl.Contains('Windows')) ("$l : slogan Windows adini icerir")
}
$script:LaunchLang = 'en'
Assert-Eq (Get-LT 'slogan') 'Optimization, maintenance and security for Windows' 'Ingilizce slogan'

# acik/koyu secimi: kayitli tema + gorunum surumu
$script:DataDir = $tmp
$sf = Join-Path $tmp 'ayarlar.json'
Remove-Item -LiteralPath $sf -Force -ErrorAction SilentlyContinue
Assert-True (Get-LaunchLight) 'ayar dosyasi yok: acik (varsayilan beyaz tema)'
$lightCases = @(
    @('{"Theme":"Neon"}', $true, 'eski kayit (surum yok), Neon: uygulama beyaza tasiyacagi icin acik'),
    @('{"Theme":"Holo","Layout":"Kompakt"}', $true, 'eski kayit, Holo: acik'),
    @('{"Theme":"Neon","LookVersion":10}', $false, 'surumlu kayit, Neon: koyu'),
    @('{"Theme":"Koyu","LookVersion":10}', $false, 'surumlu kayit, Koyu: koyu'),
    @('{"Theme":"Hacker","LookVersion":10}', $false, 'surumlu kayit, Hacker: koyu'),
    @('{"Theme":"Yuksek","LookVersion":10}', $false, 'surumlu kayit, Yuksek: koyu'),
    @('{"Theme":"Uzay","LookVersion":10}', $false, 'surumlu kayit, Uzay: koyu'),
    @('{"Theme":"Akis","LookVersion":10}', $false, 'surumlu kayit, Akis: koyu'),
    @('{"Theme":"Holo","LookVersion":10}', $false, 'surumlu kayit, Holo: koyu'),
    @('{"Theme":"Acik","LookVersion":10}', $true, 'surumlu kayit, Acik: acik'),
    @('{"Theme":"Kum","LookVersion":10}', $true, 'surumlu kayit, Kum: acik'),
    @('{"Theme":"Cam","LookVersion":10}', $true, 'surumlu kayit, Cam: acik'),
    @('{"Theme":"acik","LookVersion":10}', $true, 'tema adi buyuk/kucuk harfe bakmaz'),
    @('{"LookVersion":10}', $true, 'tema anahtari yok: varsayilan beyaz'),
    @('{"Language":"de"}', $true, 'gorunum anahtari yok: acik'),
    @('{bozuk json', $true, 'bozuk dosya: acik'),
    @('', $true, 'bos dosya: acik'),
    @('null', $true, 'null icerik: acik')
)
foreach ($c in $lightCases) {
    [System.IO.File]::WriteAllText($sf, [string]$c[0])
    Assert-Eq ([bool](Get-LaunchLight)) ([bool]$c[1]) ('acik/koyu: ' + $c[2])
}
Remove-Item -LiteralPath $sf -Force -ErrorAction SilentlyContinue

# renk uyumu (WCAG): okunacak metinler her iki zeminde yeterince belirgin
function Get-LumRgb([int[]]$c) {
    $v = New-Object 'double[]' 3
    for ($i = 0; $i -lt 3; $i++) { $x = [double]$c[$i] / 255.0; if ($x -le 0.03928) { $v[$i] = $x / 12.92 } else { $v[$i] = [math]::Pow(($x + 0.055) / 1.055, 2.4) } }
    return (0.2126 * $v[0] + 0.7152 * $v[1] + 0.0722 * $v[2])
}
function Get-ContrastRgb([int[]]$a, [int[]]$b) {
    $l1 = Get-LumRgb $a; $l2 = Get-LumRgb $b
    if ($l1 -lt $l2) { $t = $l1; $l1 = $l2; $l2 = $t }
    return (($l1 + 0.05) / ($l2 + 0.05))
}
foreach ($mode in @($true, $false)) {
    $pal = Get-SplashPalette $mode
    $nm = 'koyu'; if ($mode) { $nm = 'acik' }
    Assert-Eq ([bool]$pal.Light) $mode ($nm + ' palet: kip bayragi')
    foreach ($k in @('BgTop', 'BgBottom', 'Edge', 'AccentA', 'AccentB', 'Glow', 'Text', 'Tagline', 'Dim', 'Track')) {
        $ok = ($pal[$k].Count -eq 3)
        foreach ($x in @($pal[$k])) { if ([int]$x -lt 0 -or [int]$x -gt 255) { $ok = $false } }
        Assert-True $ok ($nm + ' palet: ' + $k + ' gecerli RGB')
    }
    foreach ($bgk in @('BgTop', 'BgBottom')) {
        Assert-True ((Get-ContrastRgb $pal.Text $pal[$bgk]) -ge 7.0) ($nm + ' palet: durum metni ' + $bgk + ' uzerinde AAA (>= 7:1): ' + [math]::Round((Get-ContrastRgb $pal.Text $pal[$bgk]), 1))
        Assert-True ((Get-ContrastRgb $pal.Tagline $pal[$bgk]) -ge 4.5) ($nm + ' palet: slogan ' + $bgk + ' uzerinde AA (>= 4.5:1): ' + [math]::Round((Get-ContrastRgb $pal.Tagline $pal[$bgk]), 1))
        Assert-True ((Get-ContrastRgb $pal.Dim $pal[$bgk]) -ge 4.5) ($nm + ' palet: alt bilgi ' + $bgk + ' uzerinde AA (>= 4.5:1): ' + [math]::Round((Get-ContrastRgb $pal.Dim $pal[$bgk]), 1))
        Assert-True ((Get-ContrastRgb $pal.AccentA $pal[$bgk]) -ge 4.5) ($nm + ' palet: ad (baslangic rengi) ' + $bgk + ' uzerinde okunur: ' + [math]::Round((Get-ContrastRgb $pal.AccentA $pal[$bgk]), 1))
        Assert-True ((Get-ContrastRgb $pal.AccentB $pal[$bgk]) -ge 4.5) ($nm + ' palet: ad (bitis rengi) ' + $bgk + ' uzerinde okunur: ' + [math]::Round((Get-ContrastRgb $pal.AccentB $pal[$bgk]), 1))
        Assert-True ((Get-ContrastRgb $pal.Track $pal[$bgk]) -ge 1.1) ($nm + ' palet: cubuk yolu zeminden ayirt edilir')
    }
}
$pl = Get-SplashPalette $true; $pd2 = Get-SplashPalette $false
Assert-True ((Get-LumRgb $pl.BgTop) -gt 0.8 -and (Get-LumRgb $pd2.BgTop) -lt 0.02) 'acik palet acik, koyu palet koyu zemin'
Assert-Eq ($pl.AccentA -join ',') '27,42,92' 'acik palet: ana vurgu uygulamanin lacivert rengi'

# yerlesim: her olcekte ogeler yatayda ortali, dikeyde sirali ve pencerenin icinde
foreach ($sc in @(1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0)) {
    $L = Get-SplashLayout $sc
    $tag = '%' + [int]($sc * 100) + ': '
    Assert-Eq ($L.W.ToString() + 'x' + $L.H) ([string][int][math]::Round(600 * $sc) + 'x' + [int][math]::Round(340 * $sc)) ($tag + 'pencere boyutu olcege gore')
    Assert-True ([math]::Abs(($L.MarkX * 2 + $L.MarkSize) - $L.W) -le 1) ($tag + 'logo yatayda ortali')
    Assert-True ([math]::Abs(($L.BarX * 2 + $L.BarW) - $L.W) -le 1) ($tag + 'ilerleme cubugu yatayda ortali')
    Assert-True ([math]::Abs(($L.TextX * 2 + $L.TextW) - $L.W) -le 1) ($tag + 'metin alani yatayda ortali')
    $order = @(
        @($L.TopBarH, $L.MarkY), @(($L.MarkY + $L.MarkSize), $L.WordY), @(($L.WordY + $L.WordH), $L.TagY), @(($L.TagY + $L.TagH), $L.StatusY),
        @(($L.StatusY + $L.StatusH), $L.BarY), @(($L.BarY + $L.BarH), $L.PctY), @(($L.PctY + $L.PctH), $L.FootY), @(($L.FootY + $L.FootH), $L.H)
    )
    $okOrd = $true
    foreach ($o in $order) { if ([int]$o[0] -gt [int]$o[1]) { $okOrd = $false } }
    Assert-True $okOrd ($tag + 'ogeler dikeyde ust uste binmeden sirali ve pencerenin icinde')
    Assert-True ($L.BarX -gt 0 -and $L.BarW -lt $L.W -and $L.BarH -ge 3) ($tag + 'cubuk pencerenin icinde')
}
$lo = Get-SplashLayout 0.5; $l1 = Get-SplashLayout 1.0
Assert-Eq $lo.W $l1.W '1.0 altindaki olcek 1.0 olarak ele alinir'
$hi = Get-SplashLayout 9.0; $l4 = Get-SplashLayout 4.0
Assert-Eq $hi.W $l4.W '4.0 ustundeki olcek 4.0 ile sinirlanir'
Assert-Eq (Get-SplashLayout 1.0).W 600 '%100 olcekte pencere 600 piksel genis'

# kaynak denetimleri: ana cizim kurulamazsa yedek gorunum, yumusak belirme/solma, DPI degiskeninin temizlenmesi, agir derleme yok
$drawFn = @($fnAsts | Where-Object { $_.Name -eq 'Draw-Splash' })[0].Extent.Text
Assert-True ($drawFn.Contains('New-SplashStatic') -and $drawFn.Contains('StaticFailed') -and $drawFn.Contains("'MULTIMIZER'")) 'Draw-Splash: sabit katman kurulamazsa yedek gorunum (ekran bos kalmaz)'
$invFn = @($fnAsts | Where-Object { $_.Name -eq 'Invoke-Splash' })[0].Extent.Text
Assert-True ($invFn.Contains('Opacity') -and $invFn.Contains('Closing') -and $invFn.Contains('NoFade')) 'Invoke-Splash: yumusak belirme ve solma; saydamlik desteklenmezse devre disi'
Assert-True ($invFn.Contains("Get-LT 'slogan'") -and $invFn.Contains('Get-LaunchLight') -and $invFn.Contains('DpiX')) 'Invoke-Splash: yerel slogan, kayitli tema ve ekran olcegi kullanilir'
$karFn = @($fnAsts | Where-Object { $_.Name -eq 'Invoke-Karsilama' })[0].Extent.Text
Assert-True ($karFn.Contains("SetEnvironmentVariable('__COMPAT_LAYER', `$null, 'Process')")) 'Invoke-Karsilama: DPI uyumluluk degiskeni alt sureclere aktarilmaz'
Assert-True ($acText -notmatch 'Add-Type\s+(-MemberDefinition|-TypeDefinition)') 'Acilis.ps1 C# derlemez (acilis ekrani hizli gelir)'
$stFn = @($fnAsts | Where-Object { $_.Name -eq 'New-SplashStatic' })[0].Extent.Text
Assert-True ($stFn.Contains('GenericTypographic') -and $stFn.Contains('MeasureString') -and $stFn.Contains('DrawLines')) 'New-SplashStatic: ad harf harf olculup ortalanir, logo harfi cizgilerle cizilir'
$tickText = $invFn.Substring($invFn.IndexOf('Add_Tick'))
Assert-True ($tickText.IndexOf('Opacity') -lt $tickText.IndexOf('Step-Launch')) 'zamanlayici: belirme adimi, asama dosyasi okunmadan once yapilir (okuma hatasi ekrani gorunmez birakamaz)'

try { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue } catch { }
Show-Result
