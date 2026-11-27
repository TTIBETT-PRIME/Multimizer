. "$PSScriptRoot/lib.ps1"
Import-Fn 'Get-NetOffList','Test-NetBlocked','Get-NetBlockText','Remove-OldLogs','Get-Win11Readiness','Chk_Win11','Get-OsSupportInfo','Add-Finding','Complete-Overlay','Close-Overlay','Get-DefaultSettings','Update-ReduceMotion','Test-Opt','Get-OptValue'
Import-Var 'NetFeatures','Themes'

# ---------------- internet istegi denetimi ----------------
$script:FakeSettings = @{ NetOff = @() }
function global:Get-Settings { return $script:FakeSettings }
Assert-True ($script:NetFeatures.Count -ge 6) 'internet ozellikleri listelendi'
Assert-True (-not (Test-NetBlocked 'Job_SpeedTest')) 'varsayilan: engel yok'
$script:FakeSettings = @{ NetOff = @('speed', 'winget') }
Assert-True (Test-NetBlocked 'Job_SpeedTest') 'hiz testi kapali'
Assert-True (Test-NetBlocked 'Job_WingetInstall') 'winget kurulum kapali'
Assert-True (Test-NetBlocked 'Job_WingetUpgrade') 'winget guncelleme kapali'
Assert-True (-not (Test-NetBlocked 'Job_WuSearch')) 'windows update acik'
Assert-True (-not (Test-NetBlocked 'Job_Plan')) 'ilgisiz is engellenmez'
Assert-True ((Get-NetBlockText 'Job_SpeedTest') -match 'kapal') 'engel metni'
Assert-True ((Get-NetBlockText 'Job_Bilinmeyen') -match 'Ayarlar') 'bilinmeyen is icin genel metin'
$script:FakeSettings = @{ NetOff = 'leak' }
Assert-True (Test-NetBlocked 'Job_LeakTest') 'tek elemanli (dizi olmayan) NetOff'
$script:FakeSettings = @{ }
Assert-True (-not (Test-NetBlocked 'Job_SpeedTest')) 'NetOff yoksa engel yok'

# her ozellik gercek bir is islevine bagli olmali
$t = $null; $e = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($env:MM_BUILD, [ref]$t, [ref]$e)
$fnNames = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Name })
foreach ($k in $script:NetFeatures.Keys) {
    foreach ($j in @($script:NetFeatures[$k].Jobs)) { Assert-True ($fnNames -contains $j) ('is islevi var: ' + $j) }
}
$src = Get-Content -LiteralPath $env:MM_BUILD -Raw
Assert-True ($src -match 'Test-NetBlocked \$Entry\) \{ Write-WhLog') 'arka plan sarmalayicisi ve komut satiri denetimi'

# ---------------- eski gunluk temizligi ----------------
$dir = Join-Path ([System.IO.Path]::GetTempPath()) ('mm-log-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $dir | Out-Null
foreach ($n in @('eski.txt', 'yeni.txt', 'eski.json', 'cok-eski.txt')) { Set-Content -LiteralPath (Join-Path $dir $n) -Value 'x' }
(Get-Item (Join-Path $dir 'eski.txt')).LastWriteTime = (Get-Date).AddDays(-100)
(Get-Item (Join-Path $dir 'eski.json')).LastWriteTime = (Get-Date).AddDays(-100)
(Get-Item (Join-Path $dir 'cok-eski.txt')).LastWriteTime = (Get-Date).AddDays(-400)
(Get-Item (Join-Path $dir 'yeni.txt')).LastWriteTime = (Get-Date).AddDays(-3)
$n = Remove-OldLogs 60 $dir
Assert-Eq $n 2 'iki eski txt silindi'
Assert-True (Test-Path (Join-Path $dir 'yeni.txt')) 'yeni dosya kaldi'
Assert-True (Test-Path (Join-Path $dir 'eski.json')) 'txt olmayan dosyaya dokunulmaz'
Assert-True (-not (Test-Path (Join-Path $dir 'eski.txt'))) 'eski txt gitti'
# 7 gunden kisa sure verilse bile en az 7 gun korunur
(Get-Item (Join-Path $dir 'yeni.txt')).LastWriteTime = (Get-Date).AddDays(-3)
Assert-Eq (Remove-OldLogs 1 $dir) 0 'en az 7 gun korunur'
Assert-Eq (Remove-OldLogs 60 (Join-Path $dir 'yok')) 0 'olmayan klasor sorun cikarmaz'
Remove-Item -LiteralPath $dir -Recurse -Force

# ---------------- Windows surum destegi ----------------
function global:Get-Date { return [datetime]$script:FakeNow }
function New-Pr([bool]$W11, [string]$Ver, [string]$Ed, [bool]$Ltsc, [int]$Build) { return @{ IsWin11 = $W11; Version = $Ver; Edition = $Ed; IsLtsc = $Ltsc; Build = $Build } }
$script:FakeNow = '2026-10-12'
$r = Get-OsSupportInfo (New-Pr $false '22H2' 'Home' $false 19045)
Assert-Eq $r.Status 'warn' 'Win10, ESU son gunden bir gun once: uyari'
Assert-True ($r.Text -match '13\.10\.2026') 'ESU tarihi'
Assert-True ($r.Text -match '\(1 g.n\)') 'kalan gun: 1'
$script:FakeNow = '2026-10-13'
$r = Get-OsSupportInfo (New-Pr $false '22H2' 'Pro' $false 19045)
Assert-Eq $r.Status 'warn' 'Win10, ESU son gunu: uyari'
$script:FakeNow = '2026-10-14'
$r = Get-OsSupportInfo (New-Pr $false '22H2' 'Home' $false 19045)
Assert-Eq $r.Status 'bad' 'Win10, ESU bitti: kotu'
Assert-True ($r.Text -match '2028') 'kurumsal ESU notu'
$script:FakeNow = '2026-10-12'
$r = Get-OsSupportInfo (New-Pr $false '21H2' 'Enterprise' $true 19044)
Assert-Eq $r.Status 'warn' 'Win10 LTSC 2021: 180 gunden az kaldi'
Assert-True ($r.Text -match '12\.01\.2027') 'LTSC 2021 tarihi'
$r = Get-OsSupportInfo (New-Pr $false '1809' 'Enterprise' $true 17763)
Assert-True ($r.Text -match '09\.01\.2029') 'LTSC 2019 tarihi'
Assert-Eq $r.Status 'ok' 'Win10 LTSC 2019: destek surer'
$script:FakeNow = '2026-10-12'
$r = Get-OsSupportInfo (New-Pr $true '24H2' 'Home' $false 26100)
Assert-Eq $r.Status 'warn' 'Win11 24H2 Home: servis sonuna 1 gun'
Assert-True ($r.Text -match '13\.10\.2026') 'Win11 24H2 Home tarihi'
$r = Get-OsSupportInfo (New-Pr $true '24H2' 'Enterprise' $false 26100)
Assert-Eq $r.Status 'ok' 'Win11 24H2 Enterprise: 2027'
Assert-True ($r.Text -match '12\.10\.2027') 'Win11 24H2 Enterprise tarihi'
$r = Get-OsSupportInfo (New-Pr $true '25H2' 'Pro' $false 26200)
Assert-Eq $r.Status 'ok' 'Win11 25H2 Pro: destekli'
Assert-True ($r.Text -match '12\.10\.2027') 'Win11 25H2 Home/Pro tarihi 12.10.2027'
$script:FakeNow = '2026-10-14'
$r = Get-OsSupportInfo (New-Pr $true '24H2' 'Pro' $false 26100)
Assert-Eq $r.Status 'bad' 'Win11 24H2 Pro servis sonu gecti'
$r = Get-OsSupportInfo (New-Pr $true '24H2' 'Enterprise' $true 26100)
Assert-Eq $r.Status 'ok' 'Win11 LTSC 2024'
Assert-True ($r.Text -match '09\.10\.2029') 'Win11 LTSC tarihi'
Remove-Item function:global:Get-Date

# ---------------- Windows 11 uyumluluk ----------------
$rd = Get-Win11Readiness
Assert-Eq @($rd.Items).Count 5 'bes gereksinim satiri'
foreach ($it in @($rd.Items)) { Assert-True ($it.Text -ne '') ('satir metni var: ' + $it.N) }
$script:Findings = New-Object System.Collections.ArrayList
$sync = @{ Profile = @{ IsWin11 = $true } }
Chk_Win11
Assert-Eq $script:Findings.Count 0 'Win11 kullanicisina uyumluluk bulgusu eklenmez'
$sync = @{ Profile = @{ IsWin11 = $false } }
function global:Get-Win11Readiness { return @{ Items = @(@{ N = 'TPM 2.0'; Ok = $false; Text = 'yok' }, @{ N = 'Bellek'; Ok = $true; Text = '8 GB' }); Ready = $false; Unknown = $false } }
Chk_Win11
Assert-Eq $script:Findings.Count 1 'uyumsuz makinede bir bulgu'
Assert-Eq $script:Findings[0].Id 'w11' 'bulgu kimligi'
Assert-Eq $script:Findings[0].Status 'info' 'uyumsuzluk bilgi duzeyinde (kullanicinin kusuru degil)'
Assert-True ($script:Findings[0].Title -match 'TPM 2\.0') 'basliga uyumsuz oge yazilir'
Assert-True ($script:Findings[0].Detail -match 'UYGUN DE') 'ayrintida UYGUN DEGIL isareti'
$script:Findings.Clear()
function global:Get-Win11Readiness { return @{ Items = @(@{ N = 'TPM 2.0'; Ok = $true; Text = 'TPM 2.0' }, @{ N = 'Bellek'; Ok = $true; Text = '8 GB' }); Ready = $true; Unknown = $false } }
Chk_Win11
Assert-True ($script:Findings[0].Title -match 'kar') 'uyumlu makine'
Assert-Eq $script:Findings[0].Action.Kind 'Url' 'uyumluysa Windows Update sayfasi acilir'
$script:Findings.Clear()
function global:Get-Win11Readiness { return @{ Items = @(@{ N = 'TPM 2.0'; Ok = $null; Text = 'Okunamadi' }); Ready = $true; Unknown = $true } }
Chk_Win11
Assert-True ($script:Findings[0].Title -match 'belirlenemedi') 'okunamayan durum dürüstçe söylenir'

# ---------------- ayar varsayilanlari ----------------
$d = Get-DefaultSettings
foreach ($k in @('NetOff', 'LastGuard', 'KeepLogDays', 'Theme', 'ReduceMotion', 'OptRam', 'OptCrypto', 'OptScan', 'OptGuard', 'OptFocus', 'OptHostsMs', 'OptVt', 'WipePasses')) {
    Assert-True ($d.ContainsKey($k)) ('varsayilan ayar: ' + $k)
}
foreach ($k in @('OptRam', 'OptScan', 'OptGuard', 'OptFocus', 'OptHostsMs', 'OptVt')) { Assert-Eq $d[$k] $false ('isteğe bağlı kapalı gelir: ' + $k) }
Assert-Eq $d['OptCrypto'] $true 'dosya şifreleme açık gelir (10.1.0: şifreleme uygulama içinden erişilebilir olmalı; eklenti yine yalnızca kullanıldığında yüklenir)'
Assert-Eq $d.KeepLogDays 60 'gunluk saklama varsayilani'
Assert-Eq $d.Theme 'Acik' 'varsayilan tema (beyaz)'

# ---------------- temalar ----------------
function Get-Lum([string]$Hex) {
    $h = $Hex.TrimStart('#')
    if ($h.Length -eq 8) { $h = $h.Substring(2) }
    $c = @([Convert]::ToInt32($h.Substring(0, 2), 16), [Convert]::ToInt32($h.Substring(2, 2), 16), [Convert]::ToInt32($h.Substring(4, 2), 16))
    $o = @(0, 0, 0)
    for ($i = 0; $i -lt 3; $i++) { $v = $c[$i] / 255.0; if ($v -le 0.03928) { $o[$i] = $v / 12.92 } else { $o[$i] = [math]::Pow(($v + 0.055) / 1.055, 2.4) } }
    return 0.2126 * $o[0] + 0.7152 * $o[1] + 0.0722 * $o[2]
}
function Get-Contrast([string]$A, [string]$B) {
    $la = Get-Lum $A; $lb = Get-Lum $B
    if ($la -lt $lb) { $x = $la; $la = $lb; $lb = $x }
    return ($la + 0.05) / ($lb + 0.05)
}
# XAML'deki varsayilan renkler
$m = [regex]::Match($src, "(?s)\`$script:XamlRes = @'\r?\n(.*?)\r?\n'@")
Assert-True $m.Success 'XamlRes bulundu'
$xamlBrushes = @{}
foreach ($x in [regex]::Matches($m.Groups[1].Value, '<SolidColorBrush x:Key="(\w+)" Color="(#[0-9A-Fa-f]+)"/>')) { $xamlBrushes[$x.Groups[1].Value] = $x.Groups[2].Value.ToUpper() }
Assert-True ($xamlBrushes.Count -ge 30) 'XAML fircalari okundu'
foreach ($tn in @('Neon', 'Koyu', 'Acik', 'Yuksek', 'Hacker', 'Cam', 'Holo', 'Akis', 'Uzay')) {
    $tb = $script:Themes[$tn]
    $missing = @($xamlBrushes.Keys | Where-Object { -not $tb.Contains($_) })
    Assert-Eq ($missing -join ',') '' ('tema tam: ' + $tn)
    $extra = @($tb.Keys | Where-Object { -not $xamlBrushes.ContainsKey($_) })
    Assert-Eq ($extra -join ',') '' ('temada fazla anahtar yok: ' + $tn)
    foreach ($k in $tb.Keys) { Assert-True ([string]$tb[$k] -match '^#([0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$') ("renk bicimi $tn/$k") }
    Assert-True ((Get-Contrast $tb.BrText $tb.BrBg) -ge 7) ("yazi/zemin kontrasti AAA: $tn")
    Assert-True ((Get-Contrast $tb.BrText $tb.BrCard) -ge 7) ("yazi/kart kontrasti: $tn")
    Assert-True ((Get-Contrast $tb.BrDim $tb.BrPanel) -ge 4.5) ("soluk yazi/panel kontrasti AA: $tn")
    Assert-True ((Get-Contrast $tb.BrOnAccent $tb.BrAccent) -ge 4.5) ("vurgu uzerindeki yazi (AA): $tn")
    Assert-True ((Get-Contrast $tb.BrDangerFg $tb.BrDangerBg) -ge 4.5) ("tehlike dugmesi yazisi: $tn")
    foreach ($k in @('BrGood', 'BrWarn', 'BrBad', 'BrInfo', 'BrAccent')) { Assert-True ((Get-Contrast $tb[$k] $tb.BrPanel) -ge 4.5) ("durum rengi okunur: $tn/$k") }
}
foreach ($k in $script:Themes.Neon.Keys) { Assert-Eq ([string]$script:Themes.Neon[$k]).ToUpper() $xamlBrushes[$k] ("Neon = XAML varsayilani: $k") }
Assert-True ((Get-Contrast $script:Themes.Yuksek.BrLine2 $script:Themes.Yuksek.BrBg) -ge 15) 'yuksek kontrast: kenarlik belirgin'

# ---------------- animasyon kisma ----------------
$script:Settings = @{ ReduceMotion = $false; Theme = 'Neon' }
$sync = @{ Profile = @{ RamGB = 16 } }
Update-ReduceMotion
Assert-True ($script:ReduceMotion -ne $true) 'guclu bilgisayarda animasyon acik'
$script:Settings.Layout = 'Sade'
Update-ReduceMotion
Assert-True ($script:ReduceMotion -eq $true) 'Sade yerlesim animasyonu kapatir'
$script:Settings.Layout = 'Ayrintili'
Update-ReduceMotion
Assert-True ($script:ReduceMotion -ne $true) 'Ayrintili yerlesim animasyonu kapatmaz'
$script:Settings = @{ ReduceMotion = $false; Theme = 'Neon' }
$sync = @{ Profile = @{ RamGB = 3.5 } }
Update-ReduceMotion
Assert-True ($script:ReduceMotion -eq $true) '4 GB alti bellekte animasyon kisilir'
$sync = @{ Profile = @{ RamGB = 8 } }
$script:Settings.ReduceMotion = $true
Update-ReduceMotion
Assert-True ($script:ReduceMotion -eq $true) 'kullanici istedi'

# ---------------- parola kutusu mantigi ----------------
$script:VisOn = 'On'; $script:VisOff = 'Off'
$script:Got = $null
$ui = @{
    OvInput = [pscustomobject]@{ Visibility = 'Off'; Text = '' }
    OvPw1 = [pscustomobject]@{ Visibility = 'On'; Password = '' }
    OvPw2 = [pscustomobject]@{ Visibility = 'On'; Password = '' }
    OvErr = [pscustomobject]@{ Visibility = 'Off'; Text = '' }
    OvText = [pscustomobject]@{ Text = 'gizli anahtar metni' }
    Overlay = [pscustomobject]@{ Visibility = 'On' }
}
function global:Show-Crash($E, $W) { Write-Host ('CRASH ' + $W) }
$script:OvMode = 'password'; $script:OvPwConfirm = $true
$script:OvAction = { param($pw) $script:Got = $pw }
$ui.OvPw1.Password = 'kisa'; $ui.OvPw2.Password = 'kisa'
Complete-Overlay $true
Assert-True ($ui.Overlay.Visibility -eq 'On') 'kisa parola: kutu kapanmaz'
Assert-True ($ui.OvErr.Text -match '8 karakter') 'kisa parola: uyari'
Assert-True ($null -eq $script:Got) 'kisa parola: islem calismaz'
Assert-Eq $ui.OvErr.Visibility 'On' 'uyari gorunur'
$ui.OvPw1.Password = 'uzunparola1'; $ui.OvPw2.Password = 'baskaparola'
Complete-Overlay $true
Assert-True ($ui.OvErr.Text -match 'ayn') 'farkli parolalar: uyari'
Assert-True ($null -eq $script:Got) 'farkli parolalar: islem calismaz'
$ui.OvPw2.Password = 'uzunparola1'
Complete-Overlay $true
Assert-Eq $script:Got 'uzunparola1' 'dogru parola islemi calistirir'
Assert-Eq $ui.OvPw1.Password '' 'parola alani temizlendi (1)'
Assert-Eq $ui.OvPw2.Password '' 'parola alani temizlendi (2)'
Assert-Eq $script:OvMode 'confirm' 'kip sifirlandi'
Assert-Eq $ui.Overlay.Visibility 'Off' 'kutu kapandi'
Assert-Eq $ui.OvText.Text '' 'kutu kapaninca metin silinir (kurtarma anahtari gibi gizli metin kalmaz)'
# vazgec
$script:Got = $null; $script:OvMode = 'password'; $script:OvPwConfirm = $false
$script:OvAction = { param($pw) $script:Got = $pw }
$ui.OvPw1.Password = 'gizliparola'; $ui.Overlay.Visibility = 'On'
Complete-Overlay $false
Assert-True ($null -eq $script:Got) 'vazgecilince islem calismaz'
Assert-Eq $ui.OvPw1.Password '' 'vazgecilince parola temizlenir'
# tek alan (cozme)
$script:OvMode = 'password'; $script:OvPwConfirm = $false
$script:OvAction = { param($pw) $script:Got = $pw }
$ui.OvPw1.Password = '12345678'; $ui.OvPw2.Password = ''
Complete-Overlay $true
Assert-Eq $script:Got '12345678' 'cozme: ikinci alan beklenmez'
# normal onay kutusu etkilenmez
$script:Got = $null; $script:OvMode = 'confirm'
$script:OvAction = { param($t) $script:Got = 'ok' }
Complete-Overlay $true
Assert-Eq $script:Got 'ok' 'normal onay'

Show-Result
