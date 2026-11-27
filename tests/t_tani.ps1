. "$PSScriptRoot/lib.ps1"
# Tani.ps1: dosya sorunlari, Defender kaydi (sahte Defender komutlariyla), kipler, cikis kodlari, salt-okunur olmasi

$taniSrc = Join-Path $script:TestDir 'Tani.ps1'
Assert-True (Test-Path -LiteralPath $taniSrc) 'Tani.ps1 Multimizer.ps1 ile ayni klasorde'
$taniText = [System.IO.File]::ReadAllText($taniSrc)
$pw = (Get-Process -Id $PID).Path

# ---- statik: ASCII ve salt-okunur
Assert-Eq @($taniText.ToCharArray() | Where-Object { [int]$_ -ge 128 }).Count 0 'Tani.ps1 yalnizca ASCII'
$writers = @('Set-ItemProperty', 'New-ItemProperty', 'Remove-Item', 'Remove-ItemProperty', 'Set-MpPreference', 'Add-MpPreference', 'Remove-MpPreference', 'Set-Service', 'Stop-Service', 'Start-Service', 'Set-NetFirewall', 'New-NetFirewall', 'Stop-Process', 'Add-Content', 'Out-File', 'New-Item', 'Copy-Item', 'Move-Item', 'Rename-Item', 'reg.exe', 'sc.exe', 'netsh')
$hit = @($writers | Where-Object { $taniText -match [regex]::Escape($_) })
Assert-Eq $hit.Count 0 ('Tani.ps1 sistemde degisiklik yapan komut icermez: ' + ($hit -join ', '))
Assert-True ($taniText -match 'Parser\]::ParseFile') 'soz dizimi dosya CALISTIRILMADAN okunarak denetlenir (AMSI tetiklenmez)'

$root = Join-Path ([System.IO.Path]::GetTempPath()) ('mm-tani-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root -Force | Out-Null
$oldTemp = $env:TEMP
try {
    $env:TEMP = $root
    function New-Case([string]$Name, [string]$Body, [switch]$NoPs1, [switch]$WithDirs) {
        $d = Join-Path $root $Name
        New-Item -ItemType Directory -Path $d -Force | Out-Null
        Copy-Item -LiteralPath $taniSrc -Destination (Join-Path $d 'Tani.ps1')
        if (-not $NoPs1) { [System.IO.File]::WriteAllText((Join-Path $d 'Multimizer.ps1'), $Body) }
        if ($WithDirs) {
            New-Item -ItemType Directory -Path (Join-Path $d 'veri') -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $d 'Eklenti') -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $d 'veri\x.txt'), 'x')
            [System.IO.File]::WriteAllText((Join-Path $d 'Eklenti\x.ps1'), 'x')
        }
        return $d
    }
    # Sahte Defender komutlariyla Tani.ps1'i calistiran sarmalayici
    function New-Wrapper([string]$Dir, [string]$Mock) {
        $w = Join-Path $Dir 'sar.ps1'
        $code = 'param([string]$Kod = ''0'', [string]$Kip = ''Gui'')' + "`r`n" + $Mock + "`r`n" + '& (Join-Path $PSScriptRoot ''Tani.ps1'') -ExitCode ([int]$Kod) -Mod $Kip' + "`r`n" + 'exit $LASTEXITCODE' + "`r`n"
        [System.IO.File]::WriteAllText($w, $code)
        return $w
    }
    function Run-Tani([string]$Dir, [string[]]$TArgs, [string]$Mock = '') {
        $w = New-Wrapper $Dir $Mock
        $o = @(& $pw -NoProfile -File $w ('-Kod:' + [string]$TArgs[1]) ('-Kip:' + [string]$TArgs[3]) 2>&1 | ForEach-Object { [string]$_ })
        return @{ Rc = $LASTEXITCODE; Out = ($o -join "`n") }
    }

    $mockHit = @'
function Get-MpComputerStatus { [pscustomobject]@{ RealTimeProtectionEnabled = $true; AntivirusSignatureVersion = '1.2.3.4' } }
function Get-MpThreatDetection { [pscustomobject]@{ InitialDetectionTime = (Get-Date); ThreatID = 77; Resources = @('amsi: \Device\HarddiskVolume3\Windows\System32\WindowsPowerShell\v1.0\powershell.exe') } }
function Get-MpThreat { param($ThreatID) [pscustomobject]@{ ThreatName = 'Trojan:PowerShell/Deneme.A' } }
'@
    $mockOther = @'
function Get-MpComputerStatus { [pscustomobject]@{ RealTimeProtectionEnabled = $true; AntivirusSignatureVersion = '1.2.3.4' } }
function Get-MpThreatDetection { [pscustomobject]@{ InitialDetectionTime = (Get-Date); ThreatID = 78; Resources = @('file: C:\Indirilenler\baska.exe') } }
function Get-MpThreat { param($ThreatID) [pscustomobject]@{ ThreatName = 'Win32/Baska.B' } }
'@
    $mockNone = @'
function Get-MpComputerStatus { [pscustomobject]@{ RealTimeProtectionEnabled = $true; AntivirusSignatureVersion = '1.2.3.4' } }
function Get-MpThreatDetection { }
function Get-MpThreat { param($ThreatID) }
'@

    # 1) Defender betigi engelledi: tehdit adi gosterilir (her uc kipte de)
    $d1 = New-Case 'defender' 'Write-Host 1' -WithDirs
    foreach ($mode in @('Gui', 'Komut', 'Elle')) {
        $r = Run-Tani $d1 @('-ExitCode', '1', '-Mod', $mode) $mockHit
        Assert-Eq $r.Rc 10 ("Defender kaydi ($mode): cikis kodu 10")
        Assert-True ($r.Out -match 'Trojan:PowerShell/Deneme\.A') ("tehdit adi gosterilir ($mode)")
        Assert-True ($r.Out -match 'ZARARLI saydi') ("engel acikca soylenir ($mode)")
        Assert-True ($r.Out -match 'yonetici izniyle ilgili degil') ("yonetici izniyle ilgisi olmadigi soylenir ($mode)")
    }
    $r = Run-Tani $d1 @('-ExitCode', '1', '-Mod', 'Gui') $mockHit
    Assert-True ($r.Out -match 'Cihazda izin ver') 'cozum: Cihazda izin ver'
    Assert-True ($r.Out -match 'wdsi/filesubmission') 'cozum: Microsoft yanlis pozitif bildirimi'
    Assert-True ($r.Out -match 'KAPATMAYIN') 'korumanin tamamini kapatmayi onermez'
    Assert-True ($r.Out -notmatch '(?i)Set-MpPreference|DisableRealtimeMonitoring') 'Defender kapatma komutu onermez'
    $rep = Join-Path $root 'Multimizer-Tani.txt'
    Assert-True (Test-Path -LiteralPath $rep) 'rapor dosyasi yazildi'
    $rb = [System.IO.File]::ReadAllBytes($rep)
    Assert-True ($rb.Length -gt 100 -and $rb[0] -eq 0xEF -and $rb[1] -eq 0xBB -and $rb[2] -eq 0xBF) 'rapor UTF-8 imzali (Notepad dogru acar)'
    Assert-True ([System.Text.Encoding]::UTF8.GetString($rb) -match 'Trojan:PowerShell/Deneme\.A') 'raporda tehdit adi var'

    # 2) Defender baska bir seyi yakaladi: Komut kipinde sessiz, Gui kipinde liste ama "betigi engelledi" denmez
    $r = Run-Tani $d1 @('-ExitCode', '1', '-Mod', 'Komut') $mockOther
    Assert-Eq $r.Rc 0 'baska dosya tespiti: Komut kipi sessiz (cikis 0)'
    Assert-Eq $r.Out '' 'baska dosya tespiti: Komut kipi hicbir sey yazmaz'
    $r = Run-Tani $d1 @('-ExitCode', '1', '-Mod', 'Gui') $mockOther
    Assert-Eq $r.Rc 10 'Gui kipi her zaman rapor yazar'
    Assert-True ($r.Out -match 'Win32/Baska\.B') 'baska kayit listelenir'
    Assert-True ($r.Out -notmatch 'ZARARLI saydi') 'baska dosya icin "Multimizer engellendi" denmez'

    # 3) Defender kaydi yok
    $r = Run-Tani $d1 @('-ExitCode', '0', '-Mod', 'Elle') $mockNone
    Assert-Eq $r.Rc 10 'Elle kipi rapor yazar'
    Assert-True ($r.Out -match 'Belirgin bir sorun bulunamad') 'sorun yoksa bunu soyler'
    Assert-True ($r.Out -match 'Soz dizimi: temiz') 'soz dizimi temiz'
    Assert-True ($r.Out -match 'veri\\ klasoru : 1 dosya') 'veri klasoru sayilir'
    Assert-True ($r.Out -match 'Eklenti\\ klasoru : 1 dosya') 'Eklenti klasoru sayilir'
    $r = Run-Tani $d1 @('-ExitCode', '0', '-Mod', 'Komut') $mockNone
    Assert-Eq $r.Rc 0 'Komut kipi, sorun yok: cikis 0'
    Assert-Eq $r.Out '' 'Komut kipi, sorun yok: sessiz'

    # 4) Betik yok / soz dizimi hatasi / klasorler eksik
    $d2 = New-Case 'yok' '' -NoPs1
    $r = Run-Tani $d2 @('-ExitCode', '1', '-Mod', 'Gui') $mockNone
    Assert-True ($r.Out -match 'Multimizer\.ps1 bulunamadi') 'betik yoksa soyler'
    Assert-True ($r.Out -match 'Sorun: betik yok') 'sonuc: betik yok'
    $d3 = New-Case 'bozuk' ('function x { if (' + "`r`n")
    $r = Run-Tani $d3 @('-ExitCode', '1', '-Mod', 'Komut') $mockNone
    Assert-Eq $r.Rc 10 'soz dizimi hatasi: Komut kipinde de rapor yazilir'
    Assert-True ($r.Out -match 'Soz dizimi hatasi') 'soz dizimi hatasi bildirilir'
    $d4 = New-Case 'eksik' 'Write-Host 1'
    $r = Run-Tani $d4 @('-ExitCode', '1', '-Mod', 'Gui') $mockNone
    Assert-True ($r.Out -match 'veri\\ klasoru YOK') 'veri klasoru yoksa uyarir'
    Assert-True ($r.Out -match 'Eklenti\\ klasoru YOK') 'Eklenti klasoru yoksa uyarir'

    # 5) Tani.ps1 hicbir dosyayi degistirmedi: yalnizca rapor eklendi
    $before = @(Get-ChildItem -LiteralPath $d4 -Recurse -File | ForEach-Object { $_.Name + ':' + $_.Length } | Sort-Object)
    $null = Run-Tani $d4 @('-ExitCode', '1', '-Mod', 'Gui') $mockNone
    $after = @(Get-ChildItem -LiteralPath $d4 -Recurse -File | ForEach-Object { $_.Name + ':' + $_.Length } | Sort-Object)
    Assert-Eq ($after -join '|') ($before -join '|') 'Tani.ps1 calistirma klasorundeki dosyalari degistirmez'
    $bp = [System.IO.File]::ReadAllText((Join-Path $d4 'Multimizer.ps1'))
    Assert-Eq $bp 'Write-Host 1' 'Multimizer.ps1 icerigi degismedi'

    # 6) gecersiz kip reddedilir (dogrudan calistirma)
    $null = @(& $pw -NoProfile -File (Join-Path $d1 'Tani.ps1') -ExitCode 1 -Mod Bilinmeyen 2>&1)
    Assert-True ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 10) 'gecersiz -Mod reddedilir'
    # 7) 7.2.1: pencere acildiktan sonra cokme: cikis kodu cozulur, oturum izi okunur
    $pd = Join-Path $root 'pd'
    $mmd = Join-Path $pd 'Multimizer'
    $logd = Join-Path $mmd 'Kayitlar'
    New-Item -ItemType Directory -Path $logd -Force | Out-Null
    $oldPd = $env:ProgramData; $env:ProgramData = $pd
    [System.IO.File]::WriteAllText((Join-Path $mmd 'oturum.json'), '{"Durum":"acik","Pid":2147480000,"Basladi":"2026-10-19T22:45:21.0000000Z","Surum":"7.2.1","Guvenli":false}')
    $enc = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText((Join-Path $logd 'oturum-iz.txt'), ("01:10:00.000  oturum ba" + [char]0x015F + "lad" + [char]0x0131 + "`r`n01:10:30.000  nab" + [char]0x0131 + "z: bellek=100MB " + [char]0x00F6 + "zel=90MB tutama" + [char]0x00E7 + "=500 par" + [char]0x00E7 + "acik=30`r`n01:17:59.123  sayfa: network`r`n01:18:03.000  nab" + [char]0x0131 + "z: bellek=410MB " + [char]0x00F6 + "zel=380MB tutama" + [char]0x00E7 + "=2400 par" + [char]0x00E7 + "acik=44`r`n01:18:24.001  is basladi: ag (Job_LanScan)`r`n"), $enc)
    $d5 = New-Case 'cokme' 'Write-Host 1' -WithDirs
    $r = Run-Tani $d5 @('-ExitCode', '-1073740791', '-Mod', 'Gui') $mockNone
    Assert-Eq $r.Rc 10 'cokme: rapor yazilir'
    Assert-True ($r.Out -match '0xC0000409') 'cikis kodu 0xC0000409 olarak cozulur'
    Assert-True ($r.Out -match 'STATUS_STACK_BUFFER_OVERRUN') 'durum adi yazilir'
    Assert-True ($r.Out -match 'Oturum "acik" kalmis') 'oturum acik kalmis ve sureci yok'
    Assert-True ($r.Out -match 'pencere acildiktan sonra') 'cokme pencere acildiktan sonra'
    Assert-True ($r.Out -match 'sayfa: network' -and $r.Out -match 'Job_LanScan') 'iz dosyasinin son satirlari gosterilir'
    Assert-True ($r.Out -match 'Bellek \(ilk -> son nabiz\) : 100 MB -> 410 MB') 'bellek egilimi'
    Assert-True ($r.Out -match 'Tutamac \(ilk -> son nabiz\): 500 -> 2400') 'tutamac egilimi'
    Assert-True ($r.Out -match 'beklenmedik sekilde kapandi') 'sonuc: beklenmedik kapanis'
    Assert-True ($r.Out -match 'acilis sorunu degil|dosya, izin ya da Defender sorunu degil') 'acilis / Defender sorunu olmadigi soylenir'
    Assert-True ($r.Out -match 'GuvenliCizim') 'guvenli kip komutu anilir'
    Assert-True ($r.Out -notmatch 'Olasi nedenler') 'cokme icin acilis nedenleri listelenmez'
    # konsol penceresi kapatildi (0xC000013A): hata degil
    $r = Run-Tani $d5 @('-ExitCode', '-1073741510', '-Mod', 'Gui') $mockNone
    Assert-True ($r.Out -match '0xC000013A') 'konsol kapatma kodu cozulur'
    # oturum duzgun kapanmis ve cikis kodu 0
    [System.IO.File]::WriteAllText((Join-Path $mmd 'oturum.json'), '{"Durum":"kapali","Pid":2147480000,"Neden":"normal","Surum":"7.2.1","Guvenli":false}')
    $r = Run-Tani $d5 @('-ExitCode', '0', '-Mod', 'Elle') $mockNone
    Assert-True ($r.Out -match 'Son oturum duzgun kapanmis \(normal\)') 'duzgun kapanmis oturum belirtilir'
    Assert-True ($r.Out -notmatch 'beklenmedik sekilde kapandi') 'duzgun oturumda cokme denmez'
    # oturum kaydi hic yoksa
    Remove-Item -LiteralPath (Join-Path $mmd 'oturum.json') -Force
    $r = Run-Tani $d5 @('-ExitCode', '0', '-Mod', 'Elle') $mockNone
    Assert-True ($r.Out -match 'Oturum kaydi \(oturum\.json\) yok') 'oturum kaydi yoksa soyler'
    $env:ProgramData = $oldPd

} finally {
    $env:TEMP = $oldTemp
    try { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue } catch { }
}
Show-Result
