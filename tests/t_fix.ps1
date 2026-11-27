. "$PSScriptRoot/lib.ps1"
Import-Fn 'New-FixInfo','New-TweakFix','New-StepsFix','New-RunFix','Resolve-FindingFix','Get-FixList','Get-QuotedImagePath','Test-UserWritablePath','Test-WindowsOwnPath'
$script:AutoFixTweaks = @('Smb1', 'AutoRun', 'Llmnr')
$script:AutoFixRuns = @('DefUpdate', 'FwOn')
$env:WINDIR = 'C:\Windows'

# --- New-TweakFix modu
Assert-Eq (New-TweakFix @('Smb1') 'x').Mode 'Auto' 'Smb1 otomatik'
Assert-Eq (New-TweakFix @('Smb1','Telnet') 'x').Mode 'Click' 'karisik tweak Click'
Assert-Eq (New-RunFix 'FwOn' 'l').Mode 'Auto' 'FwOn otomatik'
Assert-Eq (New-RunFix 'Whatever' 'l').Mode 'Click' 'bilinmeyen eylem Click'

# --- Resolve-FindingFix
$f1 = @{ Id='a'; Status='bad'; Action=@{Kind='Tweak'; Id='Smb1'; Label='Kapat'}; Fix=$null }
Resolve-FindingFix $f1; Assert-Eq $f1.Fix.Kind 'Tweak' 'tweak eylemi -> Tweak fix'; Assert-Eq $f1.Fix.Ids[0] 'Smb1' 'id korunur'
$f2 = @{ Id='b'; Status='ok'; Action=@{Kind='Tweak'; Id='Smb1'}; Fix=$null }
Resolve-FindingFix $f2; Assert-True ($null -eq $f2.Fix) 'ok bulguya fix verilmez'
$f3 = @{ Id='c'; Status='warn'; Action=$null; Fix=$null }
Resolve-FindingFix $f3; Assert-Eq $f3.Fix.Mode 'Manual' 'eylemsiz warn -> Manual'
$f4 = @{ Id='d'; Status='info'; Action=$null; Fix=$null }
Resolve-FindingFix $f4; Assert-True ($null -eq $f4.Fix) 'eylemsiz info -> fix yok'
$f5 = @{ Id='e'; Status='warn'; Action=@{Kind='Page'; Page='services'; Label='S'}; Fix=$null }
Resolve-FindingFix $f5; Assert-Eq $f5.Fix.Mode 'Guided' 'sayfa -> Guided'
$f6 = @{ Id='f'; Status='warn'; Action=@{Kind='Run'; Key='Reboot'; Label='R'}; Fix=$null }
Resolve-FindingFix $f6; Assert-Eq $f6.Fix.Mode 'Guided' 'Reboot -> Guided (otomatik yeniden baslatma yok)'
$pre = New-RunFix 'WuSvcRestore' 'x' 'Auto'
$f7 = @{ Id='g'; Status='bad'; Action=$null; Fix=$pre }
Resolve-FindingFix $f7; Assert-True ([object]::ReferenceEquals($f7.Fix, $pre)) 'var olan fix ezilmez'

# --- Get-FixList tekillestirme
$fa = @{ Id='x1'; Title='T1'; Status='bad'; Cat='sec'; Fix=(New-TweakFix @('Smb1') 'a') }
$fb = @{ Id='x2'; Title='T2'; Status='bad'; Cat='sec'; Fix=(New-TweakFix @('Smb1') 'a') }
$fc = @{ Id='x3'; Title='T3'; Status='warn'; Cat='sec'; Fix=(New-FixInfo 'Guided' 'Page' 'p') }
$fd = @{ Id='x4'; Title='T4'; Status='warn'; Cat='sec'; Fix=(New-RunFix 'FwOn' 'l') }
$fe = @{ Id='x5'; Title='T5'; Status='warn'; Cat='sec'; Fix=$null }
$l = Get-FixList @($fa,$fb,$fc,$fd,$fe)
Assert-Eq $l.Count 2 'ayni tweak tek sayilir, Guided ve fix-siz elenir'
$l0 = Get-FixList @()
Assert-Eq $l0.Count 0 'bos liste'
$lone = Get-FixList @($fd)
Assert-Eq $lone.Count 1 'tek ogeli liste dizi kalir'
Assert-Eq $lone[0].Mode 'Auto' 'mod tasinir'

# --- Get-QuotedImagePath
function Test-Path { param($LiteralPath, $PathType) return ($LiteralPath -like '*Program Files*') }
Assert-Eq (Get-QuotedImagePath 'C:\Program Files\Vendor App\svc.exe -k run') '"C:\Program Files\Vendor App\svc.exe" -k run' 'tirnaksiz bosluklu yol tirnaklanir'
Assert-Eq (Get-QuotedImagePath '"C:\Program Files\X\a.exe" -x') '' 'zaten tirnakli'
Assert-Eq (Get-QuotedImagePath 'C:\Windows\system32\svchost.exe -k netsvcs') '' 'bosluksuz yol'
Assert-Eq (Get-QuotedImagePath 'C:\Temp\Foo Bar\a.exe') '' 'dosya yoksa dokunulmaz'

# --- yol siniflandirma
Assert-True (Test-UserWritablePath 'C:\Users\ali\AppData\Local\Temp\x.exe') 'AppData yazilabilir'
Assert-True (Test-UserWritablePath 'C:\Users\ali\Downloads\x.exe') 'Downloads yazilabilir'
Assert-True (-not (Test-UserWritablePath 'C:\Program Files\App\x.exe')) 'Program Files korunmali'
Assert-True (-not (Test-UserWritablePath '')) 'bos'
Assert-True (Test-WindowsOwnPath 'C:\Windows\System32\svchost.exe') 'Windows yolu'
Assert-True (-not (Test-WindowsOwnPath 'C:\WindowsApps2\x.exe')) 'benzer ad Windows degil'
Show-Result
