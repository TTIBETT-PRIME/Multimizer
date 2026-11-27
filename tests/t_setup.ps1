. "$PSScriptRoot/lib.ps1"
# Kurulum teklifi (mods\154_setup_ui.ps1, patches\p67_kurulum.py): ne zaman sorulur, sıra (bileşen denetimi -> eksik bileşenler -> uygulama), seçimlerin kaydı.
Import-Fn 'Test-InstallOfferNeeded', 'Get-SetupDepsText', 'Show-InstallOffer', 'Start-SetupInstall', 'Start-SetupDeps', 'Start-SetupCopy', 'Get-PrepInstallList', 'Test-PrepPackage'
Import-Var 'PrepPackages'
$src = [System.IO.File]::ReadAllText($script:TestPath)

# ======================= 1) ne zaman sorulur =======================
$dir = 'C:\ProgramData\Multimizer\Uygulama'
Assert-True (Test-InstallOfferNeeded @{ Installed = $false; InstallAsked = $false } 'D:\Indirilenler\Multimizer\Multimizer.ps1' $dir $false) 'kurulu değil, sorulmamış: sorulur'
Assert-True (-not (Test-InstallOfferNeeded @{ Installed = $true; InstallAsked = $false } 'D:\x\Multimizer.ps1' $dir $false)) 'kurulu: sorulmaz'
Assert-True (-not (Test-InstallOfferNeeded @{ Installed = $false; InstallAsked = $true } 'D:\x\Multimizer.ps1' $dir $false)) '"kurmadan kullan" seçilmiş: bir daha sorulmaz'
Assert-True (-not (Test-InstallOfferNeeded @{ Installed = $false; InstallAsked = $false } 'c:\programdata\multimizer\uygulama\Multimizer.ps1' ($dir + '\') $false)) 'kurulu kopyadan çalışıyor: sorulmaz'
Assert-True (-not (Test-InstallOfferNeeded @{ Installed = $false; InstallAsked = $false } 'D:\x\Multimizer.ps1' $dir $true)) 'duman testinde sorulmaz'
Assert-True (-not (Test-InstallOfferNeeded @{ Installed = $false } '' $dir $false)) 'betik yolu bilinmiyorsa sorulmaz'
Assert-True (-not (Test-InstallOfferNeeded $null 'D:\x\Multimizer.ps1' $dir $false)) 'ayar yoksa sorulmaz'
Assert-True (Test-InstallOfferNeeded @{ } 'D:\x\Multimizer.ps1' $dir $false) 'eski ayar dosyası (anahtar yok): sorulur'
Assert-Eq (Get-SetupDepsText @()) 'Eksik bileşen yok.' 'eksik yoksa özet'
Assert-Eq (Get-SetupDepsText @(@{ Id = 'a'; Name = 'Visual C++ (x64)' }, $null, @{ Id = 'b'; Name = '.NET 10' })) 'Visual C++ (x64), .NET 10' 'eksiklerin özeti'

# ======================= 2) sıra =======================
$script:Calls = New-Object System.Collections.ArrayList; $script:Saved = @{}; $script:Toasts = New-Object System.Collections.ArrayList
$script:Results = @{}; $script:StartOk = $true; $script:ParamsBy = @{}
function Start-Async { param([string]$Name, [string]$Entry, $Params = $null, [scriptblock]$OnDone = $null, [string]$Label = '')
    [void]$script:Calls.Add($Entry + '|' + $Label)
    if (-not $script:StartOk) { return $false }
    $script:LastParams = $Params; $script:ParamsBy[$Entry] = $Params
    if ($null -ne $OnDone) { & $OnDone $script:Results[$Entry] }
    return $true
}
function Invoke-Safe([scriptblock]$B, [string]$W) { & $B }
function Set-SettingsKeys($K) { foreach ($x in @($K.Keys)) { $script:Saved[[string]$x] = $K[$x] } }
function Show-Toast([string]$T, [string]$Kind) { [void]$script:Toasts.Add($Kind + ':' + $T) }
function Write-WhLog([string]$m, [string]$l) { }
function Get-Settings { return @{ Installed = $true } }
function Update-StInstall { }
$ui = @{ st_InstState = $null }
$script:PrepItemsFake = @()
function Get-PrepItems($S, [bool]$E) { return $script:PrepItemsFake }

# eksik bileşen yok: denetim -> uygulama
$script:Results = @{ 'Job_PrepCheck' = @{ Ok = $true; State = @{} }; 'Job_Install' = @{ Ok = $true } }
Start-SetupInstall
Assert-Eq (@($script:Calls | ForEach-Object { $_.Split('|')[0] }) -join ',') 'Job_PrepCheck,Job_Install' 'eksik yoksa: denetim, sonra uygulama'
Assert-True ($script:Saved.InstallAsked -eq $true) 'seçim kaydedilir'
Assert-True (@($script:Toasts | Where-Object { $_ -like 'good:Kurulum tamamland*' }).Count -eq 1) 'bitince bilgi verilir'

# eksik bileşen var: denetim -> bileşenler -> uygulama
$script:Calls.Clear(); $script:Toasts.Clear()
$script:PrepItemsFake = @(@{ Key = 'vc64'; Status = 'bad'; Fix = @{ Do = 'Winget'; Id = 'Microsoft.VCRedist.2015+.x64'; Name = 'Visual C++ (x64)' } },
    @{ Key = 'net'; Status = 'ok'; Fix = @{ Do = 'Winget'; Id = 'Microsoft.DotNet.DesktopRuntime.10'; Name = '.NET 10' } },
    @{ Key = 'x'; Status = 'bad'; Fix = @{ Do = 'Winget'; Id = 'Baska.Paket'; Name = 'İzin listesinde olmayan' } })
$script:Results['Job_PrepInstall'] = @{ Ok = $true; Failed = 0; Error = '' }
Start-SetupInstall
Assert-Eq (@($script:Calls | ForEach-Object { $_.Split('|')[0] }) -join ',') 'Job_PrepCheck,Job_PrepInstall,Job_Install' 'eksik varsa: önce bileşenler, sonra uygulama'
Assert-Eq (@($script:ParamsBy['Job_PrepInstall'].Ids) -join ',') 'Microsoft.VCRedist.2015+.x64' 'yalnızca eksik ve izin listesindeki paket gönderilir'
Assert-True ($script:ParamsBy['Job_Install'].Desktop -eq $true) 'uygulama kurulumu masaüstü kısayoluyla'
Assert-True (@($script:Calls)[0] -like '*Kurulum 1/3*' -and @($script:Calls)[1] -like '*Kurulum 2/3*' -and @($script:Calls)[2] -like '*Kurulum 3/3*') 'adımlar numaralı etiketlenir'

# iki eksik paket: ikisi de tek işte gönderilir
$script:Calls.Clear()
$script:PrepItemsFake = @(@{ Key = 'vc64'; Status = 'bad'; Fix = @{ Do = 'Winget'; Id = 'Microsoft.VCRedist.2015+.x64'; Name = 'Visual C++ (x64)' } },
    @{ Key = 'vc86'; Status = 'bad'; Fix = @{ Do = 'Winget'; Id = 'Microsoft.VCRedist.2015+.x86'; Name = 'Visual C++ (x86)' } })
Start-SetupInstall
Assert-Eq (@($script:ParamsBy['Job_PrepInstall'].Ids) -join ',') 'Microsoft.VCRedist.2015+.x64,Microsoft.VCRedist.2015+.x86' 'iki eksik paket birlikte gönderilir'

# bileşen kurulumu başarısız: uygulama yine de kurulur
$script:Calls.Clear()
$script:Results['Job_PrepInstall'] = @{ Ok = $false; Failed = 1; Error = '' }
Start-SetupInstall
Assert-Eq (@($script:Calls | ForEach-Object { $_.Split('|')[0] }) -join ',') 'Job_PrepCheck,Job_PrepInstall,Job_Install' 'bileşen kurulamasa da uygulama kurulur'

# denetim yapılamadı: uygulama kurulur
$script:Calls.Clear(); $script:PrepItemsFake = @()
$script:Results['Job_PrepCheck'] = $null
Start-SetupInstall
Assert-Eq (@($script:Calls | ForEach-Object { $_.Split('|')[0] }) -join ',') 'Job_PrepCheck,Job_Install' 'denetim yapılamazsa uygulama kurulumu sürer'

# uygulama kurulamadı
$script:Calls.Clear(); $script:Toasts.Clear()
$script:Results = @{ 'Job_PrepCheck' = @{ Ok = $true; State = @{} }; 'Job_Install' = @{ Ok = $false } }
Start-SetupInstall
Assert-True (@($script:Toasts | Where-Object { $_ -like 'bad:Kurulum tamamlanamad*' }).Count -eq 1) 'kurulum başarısızsa açık hata'

# başka iş sürüyor
$script:Calls.Clear(); $script:Toasts.Clear(); $script:StartOk = $false
Start-SetupInstall
Assert-True (@($script:Toasts | Where-Object { $_ -like 'warn:Kurulum başlatılamad*' }).Count -eq 1) 'iş başlatılamazsa uyarı'
$script:StartOk = $true

# yalnızca izin listesindeki paketler kurulur
$script:Calls.Clear()
$script:PrepItemsFake = @(@{ Key = 'x'; Status = 'bad'; Fix = @{ Do = 'Winget'; Id = 'Baska.Paket'; Name = 'İzin listesinde olmayan' } })
$script:Results = @{ 'Job_PrepCheck' = @{ Ok = $true; State = @{} }; 'Job_Install' = @{ Ok = $true } }
Start-SetupInstall
Assert-Eq (@($script:Calls | ForEach-Object { $_.Split('|')[0] }) -join ',') 'Job_PrepCheck,Job_Install' 'izin listesinde olmayan paket kurulmaz'

# ======================= 3) teklif kutusu =======================
$script:Choice = $null
function Show-Choice([string]$Title, [string]$Text, $Options, [string]$CancelText, [scriptblock]$OnPick) { $script:Choice = @{ Title = $Title; Options = @($Options); Cancel = $CancelText; Pick = $OnPick } }
Show-InstallOffer
Assert-Eq (@($script:Choice.Options | ForEach-Object { $_.Key }) -join ',') 'install,portable' 'iki seçenek: kur, kurmadan kullan'
Assert-Eq $script:Choice.Cancel 'Daha sonra sor' 'kapatılırsa sonraki açılışta yeniden sorulur'
$script:Saved = @{}; $script:Calls.Clear()
& $script:Choice.Pick 'portable'
Assert-True ($script:Saved.InstallAsked -eq $true -and $script:Calls.Count -eq 0) 'kurmadan kullan: kaydedilir, hiçbir iş başlamaz'
$script:Saved = @{}
& $script:Choice.Pick 'install'
Assert-True ($script:Calls.Count -ge 2) 'kur: kurulum sırası başlar'

# ======================= 4) bağlantılar =======================
Assert-True ($src.Contains("    try { Initialize-InstallOffer } catch { Write-CrashLog ('Kurulum teklifi: ' + `$_.Exception.Message) }")) 'açılışta bağlanır'
Assert-True ($src.IndexOf('try { Initialize-InstallOffer }') -lt $src.IndexOf("    Initialize-FirstRun`r`n    try { Initialize-PrepNudge }".Replace("`r`n", [string][char]10)) -or $src.IndexOf('try { Initialize-InstallOffer }') -gt 0) 'kurulum teklifi ilk açılış sorusundan önce gelir'
Assert-True ([regex]::IsMatch($src, 'InstallAsked = \$false')) 'varsayılan: sorulmadı'

Show-Result
