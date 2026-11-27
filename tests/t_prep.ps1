. "$PSScriptRoot/lib.ps1"
# Çözüm Merkezi "Hazırlık" sekmesi (mods\127_prep_core.ps1 ve 127_solve_prep.ps1): bileşen okuyucuları (sahte kayıt defteri ve dosyalarla), satır kuralları,
# winget sonuç kodları, izin listesi, kurulum ve WMI işleri (sahte winget ile), çizim ve onaylar. Gerçek kurulum yapılmaz.
Import-Fn 'Get-JsonProp', 'Format-PcGb',
    'Test-PrepPackage', 'Get-PrepWingetResult', 'Get-PrepNetName', 'Get-PrepVcRuntime', 'Get-PrepDotnetDesktop', 'Get-PrepDirectX', 'Get-PrepCsc', 'Get-PrepSysDrive',
    'Test-PrepWmi', 'Test-PrepWritable', 'Get-PrepProtect', 'Get-PrepState', 'Job_PrepCheck', 'New-PrepItem', 'New-PrepFix', 'Get-PrepVcItem', 'Get-PrepItems', 'Get-PrepSummary',
    'Get-PrepInstallList', 'Job_PrepInstall', 'Invoke-PrepWmiRepair', 'Job_PrepWmi',
    'Get-PrepBr', 'Get-PrepInstallModel', 'Load-SlPrep', 'Complete-SlPrep', 'Render-SlPrep', 'Invoke-PrepAction', 'Start-PrepInstall', 'Start-PrepFixAll',
    'Complete-PrepInstall', 'Start-PrepWmi', 'Complete-PrepWmi', 'Init-SlPrep', 'Update-PageMode_solve'
Import-Var 'MmExtNames', 'PrepPackages', 'H_PrAct'
$script:PrepState = $null; $script:PrepItems = @(); $script:PrepLoading = $false; $script:PrepPending = $null
$script:WhLog = New-Object System.Collections.ArrayList
function Write-WhLog([string]$Message, [string]$Level = 'INFO') { [void]$script:WhLog.Add($Level + '|' + $Message) }
. "$PSScriptRoot/uifake.ps1"
function Open-Page([string]$Key, [string]$Sub = '') { [void]$script:Opened.Add('page:' + $Key + '/' + $Sub) }
$script:PcRenders = 0
function Render-SlPc { $script:PcRenders++ }

# =====================================================================
#  1) izin listesi ve küçük yardımcılar
# =====================================================================
Assert-Eq $script:PrepPackages.Count 5 'izin listesi: beş paket'
foreach ($k in @($script:PrepPackages.Keys)) {
    Assert-True ([string]$k -match '^[A-Za-z0-9][A-Za-z0-9\.\-_\+]*$') ('izin listesi: kimlik biçimi geçerli ' + $k)
    Assert-True ([string]$script:PrepPackages[$k] -ne '') ('izin listesi: ad var ' + $k)
    Assert-Eq (Test-PrepPackage ([string]$k)) '' ('izin listesi: kurulabilir ' + $k)
}
Assert-True ($script:PrepPackages.ContainsKey('Microsoft.VCRedist.2015+.x64') -and $script:PrepPackages.ContainsKey('Microsoft.VCRedist.2015+.x86') -and $script:PrepPackages.ContainsKey('Microsoft.DirectX') -and $script:PrepPackages.ContainsKey('Microsoft.DotNet.DesktopRuntime.10')) 'izin listesi: beklenen Microsoft paketleri'
Assert-True (@($script:PrepPackages.Keys | Where-Object { [string]$_ -notmatch '^Microsoft\.' }).Count -eq 0) 'izin listesi: yalnızca Microsoft paketleri'
Assert-Eq (Test-PrepPackage 'microsoft.directx') '' 'paket denetimi: büyük/küçük harf önemsiz'
Assert-True ((Test-PrepPackage 'Vendor.Tool') -match 'izin listesinde değil') 'paket denetimi: listede olmayan kimlik reddedilir'
Assert-True ((Test-PrepPackage 'Microsoft.DirectX; calc') -match 'Geçersiz paket kimliği') 'paket denetimi: komut eklemeye çalışan kimlik reddedilir'
Assert-True ((Test-PrepPackage 'Microsoft.DirectX --source evil') -match 'Geçersiz') 'paket denetimi: boşluklu kimlik reddedilir'
Assert-True ((Test-PrepPackage '..\evil') -match 'Geçersiz') 'paket denetimi: yol benzeri kimlik reddedilir'
Assert-True ((Test-PrepPackage '') -match 'Geçersiz') 'paket denetimi: boş kimlik reddedilir'
Assert-True ((Test-PrepPackage '-v') -match 'Geçersiz') 'paket denetimi: tire ile başlayan (seçenek gibi) kimlik reddedilir'
Assert-Eq $script:MmExtNames.Count 8 'eklenti listesi: sekiz eklenti'
Assert-True (($script:MmExtNames -contains 'DiskSilme') -and ($script:MmExtNames -contains 'Kurtarma') -and ($script:MmExtNames -contains 'GuvenliSilme')) 'eklenti listesi: silme ve kurtarma eklentileri var'

# winget çıkış kodları
$w0 = Get-PrepWingetResult 0
Assert-True ($w0.Ok -eq $true -and $w0.Reboot -eq $false -and $w0.Already -eq $false -and $w0.Text -eq 'kuruldu') 'winget kodu: 0 kuruldu'
foreach ($c in @(-1978335189, -1978335135, -1978334963, -1978335153)) {
    $x = Get-PrepWingetResult $c
    Assert-True ($x.Ok -eq $true -and $x.Already -eq $true -and $x.Reboot -eq $false -and $x.Text -eq 'zaten kurulu') ('winget kodu: zaten kurulu ' + $c)
}
foreach ($c in @(3010, 1641, -1978334967)) {
    $x = Get-PrepWingetResult $c
    Assert-True ($x.Ok -eq $true -and $x.Reboot -eq $true -and $x.Text -match 'yeniden başlatma') ('winget kodu: kuruldu, yeniden başlatma ' + $c)
}
$x = Get-PrepWingetResult -1978334965
Assert-True ($x.Ok -eq $true -and $x.Reboot -eq $true) 'winget kodu: yeniden başlatma başlatıldı'
$x = Get-PrepWingetResult -1978334966
Assert-True ($x.Ok -eq $false -and $x.Reboot -eq $true -and $x.Text -match 'önce bilgisayarı') 'winget kodu: önce yeniden başlatma gerekir, başarı sayılmaz'
foreach ($c in @(-1978335212, -1978335209, -1978335179)) {
    $x = Get-PrepWingetResult $c
    Assert-True ($x.Ok -eq $false -and $x.Text -match 'bulunamadı') ('winget kodu: bulunamadı ' + $c)
}
$x = Get-PrepWingetResult -1978335216
Assert-True ($x.Ok -eq $false -and $x.Text -match 'uygun kurulum paketi yok') 'winget kodu: uygun paket yok'
$x = Get-PrepWingetResult -1978334957
Assert-True ($x.Ok -eq $false -and $x.Text -match 'desteklenmiyor') 'winget kodu: sistem desteklenmiyor'
$x = Get-PrepWingetResult -1978335215
Assert-True ($x.Ok -eq $false -and $x.Text -match 'özeti paketle uyuşmadı' -and $x.Text -match 'kurulmadı') 'winget kodu: özet uyuşmazlığı kurulmaz'
$x = Get-PrepWingetResult 12345
Assert-True ($x.Ok -eq $false -and $x.Text -eq 'winget çıkış kodu 12345') 'winget kodu: bilinmeyen kod'
$x = Get-PrepWingetResult -1
Assert-True ($x.Ok -eq $false -and $x.Text -eq 'winget çıkış kodu -1') 'winget kodu: -1 başarısız'

# .NET Framework sürüm adları
$netCases = @(@(0, ''), @(378388, ''), @(378389, '4.5'), @(378675, '4.5.1'), @(379893, '4.5.2'), @(393295, '4.6'), @(394254, '4.6.1'), @(394802, '4.6.2'), @(460798, '4.7'), @(461308, '4.7.1'), @(461808, '4.7.2'),
    @(528040, '4.8'), @(528372, '4.8'), @(533320, '4.8.1'), @(533325, '4.8.1'), @(999999, '4.8.1'))
foreach ($c in $netCases) { Assert-Eq (Get-PrepNetName ([int]$c[0])) ([string]$c[1]) ('.NET Framework adı: ' + [string]$c[0]) }

# =====================================================================
#  2) okuyucular: sahte kayıt defteri, dosya ve CIM ile
# =====================================================================
$script:Reg = @{}
function Get-RegValue([string]$Path, [string]$Name, $Default = $null) { $k = $Path + '|' + $Name; if ($script:Reg.ContainsKey($k)) { return $script:Reg[$k] }; return $Default }
$vcx64 = 'HKLM\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64'
$vcx86w = 'HKLM\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\x86'
$vcx86n = 'HKLM\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x86'
$vca64 = 'HKLM\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\ARM64'
$v0 = Get-PrepVcRuntime 'x64'
Assert-True ($v0.Installed -eq $false -and $v0.Arch -eq 'x64' -and $v0.Version -eq '') 'VC++: kayıt yoksa yüklü değil'
$script:Reg[$vcx64 + '|Installed'] = 1; $script:Reg[$vcx64 + '|Version'] = 'v14.44.35211.00'; $script:Reg[$vcx64 + '|Major'] = 14; $script:Reg[$vcx64 + '|Minor'] = 44; $script:Reg[$vcx64 + '|Bld'] = 35211
$v1 = Get-PrepVcRuntime 'x64'
Assert-True ($v1.Installed -eq $true -and $v1.Version -eq 'v14.44.35211.00' -and $v1.Major -eq 14 -and $v1.Minor -eq 44 -and $v1.Build -eq 35211) 'VC++: x64 sürümü okunur'
$script:Reg[$vcx64 + '|Installed'] = 0
Assert-True ((Get-PrepVcRuntime 'x64').Installed -eq $false) 'VC++: Installed=0 yüklü sayılmaz'
$script:Reg[$vcx86n + '|Installed'] = 1; $script:Reg[$vcx86n + '|Major'] = 14; $script:Reg[$vcx86n + '|Minor'] = 29
Assert-True ((Get-PrepVcRuntime 'x86').Installed -eq $true -and (Get-PrepVcRuntime 'x86').Minor -eq 29) 'VC++: x86 (32 bit Windows yolu)'
$script:Reg[$vcx86w + '|Installed'] = 1; $script:Reg[$vcx86w + '|Major'] = 14; $script:Reg[$vcx86w + '|Minor'] = 40
Assert-Eq (Get-PrepVcRuntime 'x86').Minor 40 'VC++: x86 için WOW6432Node yolu öncelikli'
$script:Reg[$vca64 + '|Installed'] = 1; $script:Reg[$vca64 + '|Major'] = 14; $script:Reg[$vca64 + '|Minor'] = 42
Assert-True ((Get-PrepVcRuntime 'arm64').Installed -eq $true -and (Get-PrepVcRuntime 'arm64').Minor -eq 42) 'VC++: ARM64'
Assert-True ((Get-PrepVcRuntime 'bilinmeyen').Installed -eq $false) 'VC++: bilinmeyen mimari'

# .NET Masaüstü Çalışma Zamanı (kayıt defteri sağlayıcısı sahte)
$script:ItemProps = @{}
function Get-ItemProperty { [CmdletBinding()] param([string]$LiteralPath)
    if ($script:ItemProps.ContainsKey($LiteralPath)) { return $script:ItemProps[$LiteralPath] }
    throw ('yol yok: ' + $LiteralPath)
}
$dn0 = Get-PrepDotnetDesktop
Assert-Eq $dn0.Count 0 '.NET masaüstü: kayıt yoksa boş'
$script:ItemProps['HKLM:\SOFTWARE\dotnet\Setup\InstalledVersions\x64\sharedfx\Microsoft.WindowsDesktop.App'] = [pscustomobject]@{ '8.0.11' = 1; '10.0.1' = 1; PSPath = 'x'; PSChildName = 'y' }
$script:ItemProps['HKLM:\SOFTWARE\WOW6432Node\dotnet\Setup\InstalledVersions\x86\sharedfx\Microsoft.WindowsDesktop.App'] = [pscustomobject]@{ '8.0.11' = 1; '9.0.2' = 1 }
$dn1 = Get-PrepDotnetDesktop
Assert-Eq ($dn1 -join ',') '8.0.11,10.0.1,9.0.2' '.NET masaüstü: sürümler birleştirilir, yinelenenler ve sağlayıcı alanları atlanır'

# DirectX ve derleyici dosyaları
$script:Files = @{}
function Test-Path { [CmdletBinding()] param([string]$LiteralPath, [string]$Path, [string]$PathType)
    $p = $LiteralPath; if ($p -eq '') { $p = $Path }
    if ($script:Files.ContainsKey($p)) { return $true }
    return $false
}
$env:SystemRoot = '/win'
$dxe = Get-PrepDirectX
Assert-True ($dxe.Native -eq $false -and $dxe.X86 -eq $false) 'DirectX: dosyalar yoksa ikisi de eksik'
$script:Files[(Join-Path '/win' 'System32\d3dx9_43.dll')] = 1
$dxe = Get-PrepDirectX
Assert-True ($dxe.Native -eq $true -and $dxe.X86 -eq $false) 'DirectX: yalnızca yerel kopya'
$script:Files[(Join-Path '/win' 'SysWOW64\d3dx9_43.dll')] = 1
$dxe = Get-PrepDirectX
Assert-True ($dxe.Native -eq $true -and $dxe.X86 -eq $true) 'DirectX: iki kopya'
$cs0 = Get-PrepCsc
Assert-True ($cs0.Found -eq $false -and $cs0.Path -eq '') 'derleyici: yoksa bulunamadı'
$script:Files[(Join-Path '/win' 'Microsoft.NET\Framework\v4.0.30319\csc.exe')] = 1
$cs1 = Get-PrepCsc
Assert-True ($cs1.Found -eq $true -and $cs1.Path -match 'Framework.v4.0.30319.csc.exe') 'derleyici: 32 bit yolu da kabul edilir'
$script:Files[(Join-Path '/win' 'Microsoft.NET\Framework64\v4.0.30319\csc.exe')] = 1
$cs2 = Get-PrepCsc
Assert-True ($cs2.Found -eq $true -and $cs2.Path -match 'Framework64') 'derleyici: 64 bit yolu öncelikli'
$env:SystemRoot = ''
Assert-True ((Get-PrepCsc).Found -eq $false -and (Get-PrepDirectX).Native -eq $false) 'dosya okuyucular: SystemRoot yoksa güvenle boş döner'
Remove-Item function:Test-Path
Remove-Item function:Get-ItemProperty

# sistem sürücüsü: Linux'ta DriveInfo('C:') açılamaz; işlev hata vermeden boş döner
$sd = Get-PrepSysDrive
Assert-True ($sd -is [hashtable] -and $sd.ContainsKey('FreeGB') -and $sd.ContainsKey('SizeGB') -and $sd.ContainsKey('Letter')) 'sistem sürücüsü: her durumda tam bir tablo döner'

# WMI
$script:CimMode = 'ok'
function Get-CimInstance { [CmdletBinding()] param([string]$Namespace = 'root\cimv2', [string]$ClassName)
    if ($script:CimMode -eq 'throw') { throw 'WMI hatası: 0x80041010 Geçersiz sınıf' }
    if ($script:CimMode -eq 'empty') { return @() }
    return @([pscustomobject]@{ Caption = 'Microsoft Windows 11' })
}
$wm = Test-PrepWmi
Assert-True ($wm.Ok -eq $true -and $wm.Error -eq '') 'WMI: sorgu çalışıyor'
$script:CimMode = 'throw'
$wm = Test-PrepWmi
Assert-True ($wm.Ok -eq $false -and $wm.Error -match '0x80041010') 'WMI: hata iletilir'
$script:CimMode = 'empty'
$wm = Test-PrepWmi
Assert-True ($wm.Ok -eq $false -and $wm.Error -match 'sonuç döndürmedi') 'WMI: boş sonuç başarısız sayılır'
$script:CimMode = 'ok'

# yazılabilir klasör
$tmpRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('mm-prep-' + [guid]::NewGuid().ToString('N'))
$wr = Test-PrepWritable $tmpRoot
Assert-True ($wr.Ok -eq $true -and (Test-Path -LiteralPath $tmpRoot -PathType Container)) 'yazma denemesi: olmayan klasör oluşturulur ve yazılır'
Assert-Eq @(Get-ChildItem -LiteralPath $tmpRoot).Count 0 'yazma denemesi: geçici dosya silinir'
$wr = Test-PrepWritable (Join-Path $tmpRoot 'ic/ice')
Assert-True ($wr.Ok -eq $true) 'yazma denemesi: iç içe klasör'
$fileAsDir = Join-Path $tmpRoot 'dosya.txt'
[System.IO.File]::WriteAllText($fileAsDir, 'x')
$wr = Test-PrepWritable $fileAsDir
Assert-True ($wr.Ok -eq $false -and [string]$wr.Error -ne '') 'yazma denemesi: klasör yerine dosya verilirse başarısız'
$wr = Test-PrepWritable ''
Assert-True ($wr.Ok -eq $false -and $wr.Error -match 'bilinmiyor') 'yazma denemesi: boş yol'
Remove-Item -LiteralPath $tmpRoot -Recurse -Force

# Sistem Koruması
$spp = 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SPP\Clients|{09F7EDC5-294E-4180-AF6A-FB0E6A0E9513}'
$pol = 'HKLM\SOFTWARE\Policies\Microsoft\Windows NT\SystemRestore|DisableSR'
$script:Reg = @{}
$pr = Get-PrepProtect 'C:'
Assert-True ($pr.Known -eq $true -and $pr.On -eq $false -and $pr.Policy -eq $false) 'koruma: kayıt yoksa kapalı'
$script:Reg[$spp] = @('1:\\?\Volume{aaaa}\:(C%3A)', '1:\\?\Volume{bbbb}\:(D%3A)')
$pr = Get-PrepProtect 'C:'
Assert-True ($pr.Known -eq $true -and $pr.On -eq $true) 'koruma: sistem sürücüsü listede'
$pr = Get-PrepProtect 'e:'
Assert-True ($pr.On -eq $false) 'koruma: listede olmayan sürücü'
$pr = Get-PrepProtect 'd:'
Assert-True ($pr.On -eq $true) 'koruma: harf büyük/küçük harf önemsiz'
$script:Reg[$pol] = 1
$pr = Get-PrepProtect 'C:'
Assert-True ($pr.Known -eq $true -and $pr.Policy -eq $true -and $pr.On -eq $false) 'koruma: ilkeyle kapatılmış'
$script:Reg = @{}

# =====================================================================
#  3) tam toplama (Get-PrepState) ve iş sarmalayıcısı
# =====================================================================
$script:Reg = @{}
$script:Reg['HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion|CurrentBuildNumber'] = '22631'
$script:Reg['HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion|DisplayVersion'] = '23H2'
$script:Reg['HKLM\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full|Release'] = 528040
$script:Reg[$vcx64 + '|Installed'] = 1; $script:Reg[$vcx64 + '|Major'] = 14; $script:Reg[$vcx64 + '|Minor'] = 38; $script:Reg[$vcx64 + '|Version'] = 'v14.38.33135.00'
$script:Reg[$spp] = @('1:\\?\Volume{aaaa}\:(C%3A)')
function Get-WingetPath { return $script:WgPath }
$script:WgPath = ''
$script:OnlineCalls = 0
function Find-ItOnline($Items) { foreach ($i in $Items) { if ([string]$i.Key -eq 'online') { return $i } }; return $null }
function Test-Online { $script:OnlineCalls++; return $script:OnlineNow }
$script:OnlineNow = $true
$script:ExtProblems = @{ Kurtarma = 'Dosya bulunamadı.' }
function Get-ExtProblem([string]$Name) { if ($script:ExtProblems.ContainsKey($Name)) { return [string]$script:ExtProblems[$Name] }; return '' }
function Get-PrepSysDrive { return @{ Letter = 'C:'; FreeGB = [double]40.5; SizeGB = [double]475.9 } }
$tmpData = Join-Path ([System.IO.Path]::GetTempPath()) ('mm-prep-data-' + [guid]::NewGuid().ToString('N'))
$sync = @{ DataDir = $tmpData }
$env:SystemDrive = 'C:'
$env:PROCESSOR_ARCHITECTURE = 'AMD64'
$env:PROCESSOR_ARCHITEW6432 = ''
$st = Get-PrepState
Assert-True ($st.Ok -eq $true -and [string]$st.At -match '^\d\d\.\d\d\.\d{4} \d\d:\d\d$') 'durum: temel alanlar'
Assert-True ($st.Ps.Major -ge 5 -and [string]$st.Ps.Version -ne '' -and [string]$st.Ps.Edition -ne '') 'durum: PowerShell sürümü bu oturumdan okunur'
Assert-True ($st.Os.Build -eq 22631 -and $st.Os.Name -eq 'Windows 11' -and $st.Os.Display -eq '23H2' -and $st.Os.Arm -eq $false) 'durum: Windows 11 derlemesi'
Assert-True ($st.Net.Release -eq 528040 -and $st.Net.Name -eq '4.8') 'durum: .NET Framework'
Assert-True ($st.Vc.X64.Installed -eq $true -and $st.Vc.X64.Minor -eq 38 -and $st.Vc.X86.Installed -eq $false -and $null -eq $st.Vc.Arm64) 'durum: VC++ x64 var, x86 yok, ARM64 sorulmaz'
Assert-True ($st.Winget.Path -eq '' -and $st.Winget.Version -eq '') 'durum: winget yok'
Assert-True ($st.Online -eq $true -and $st.Wmi.Ok -eq $true -and $st.Disk.Letter -eq 'C:') 'durum: bağlantı, WMI ve sürücü'
Assert-Eq $script:OnlineCalls 1 'durum: bağlantı bir kez sınanır'
$stn = Get-PrepState $true
Assert-True ($null -eq $stn.Online -and $script:OnlineCalls -eq 1) 'durum: ağsız denetimde internet sınanmaz, Online boş kalır'
Assert-True ($stn.Ok -eq $true -and $stn.Net.Name -eq '4.8' -and $stn.Wmi.Ok -eq $true -and $stn.Disk.Letter -eq 'C:' -and @($stn.Exts).Count -eq 8) 'durum: ağsız denetimde diğer okumalar aynı'
Assert-True ($null -eq (Find-ItOnline (Get-PrepItems $stn))) 'durum: ağsız denetimde internet satırı gösterilmez'
Assert-True ($st.Data.Ok -eq $true -and $st.Data.Path -eq $tmpData -and (Test-Path -LiteralPath $tmpData)) 'durum: veri klasörü yazılabilir'
Assert-Eq @($st.Exts).Count 8 'durum: sekiz eklenti denetlendi'
Assert-True (@($st.Exts | Where-Object { $_.Problem -ne '' }).Count -eq 1 -and (@($st.Exts | Where-Object { $_.Name -eq 'Kurtarma' })[0].Problem -match 'bulunamadı')) 'durum: eklenti sorunu taşınır'
Assert-True ($st.Protect.Known -eq $true -and $st.Protect.On -eq $true) 'durum: Sistem Koruması açık'
$env:PROCESSOR_ARCHITECTURE = 'ARM64'
$script:Reg[$vca64 + '|Installed'] = 1; $script:Reg[$vca64 + '|Major'] = 14; $script:Reg[$vca64 + '|Minor'] = 40
$st2 = Get-PrepState
Assert-True ($st2.Os.Arm -eq $true -and $st2.Vc.Arm64.Installed -eq $true) 'durum: ARM64 bilgisayarda ARM64 çalışma zamanı da okunur'
$env:PROCESSOR_ARCHITECTURE = 'AMD64'
$script:OnlineNow = $false
$script:Reg['HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion|CurrentBuildNumber'] = '19045'
$st3 = Get-PrepState
Assert-True ($st3.Online -eq $false -and $st3.Os.Name -eq 'Windows 10') 'durum: çevrimdışı ve Windows 10'
$script:OnlineNow = $true
# bölümlerden biri hata verirse diğerleri korunur
function Get-PrepCsc { throw 'csc okunamadı' }
$st4 = Get-PrepState
Assert-True ($st4.Ok -eq $true -and $st4.Csc.Found -eq $false -and $st4.Net.Name -eq '4.8') 'durum: bir okuma başarısız olsa da diğerleri korunur'
Remove-Item function:Get-PrepCsc
$script:PrepRes = Job_PrepCheck @{}
Assert-True ($script:PrepRes.Ok -eq $true -and $script:PrepRes.State.Net.Name -eq '4.8') 'denetim işi: durumu döndürür'
Assert-True ($script:WhLog.Count -ge 1 -and ($script:WhLog | Where-Object { $_ -match 'yalnızca okuma' }).Count -ge 1) 'denetim işi: günlüğe yazar'
$oc = $script:OnlineCalls
$script:WhLog.Clear()
$script:PrepRes = Job_PrepCheck @{ NoNet = $true }
Assert-True ($script:PrepRes.Ok -eq $true -and $null -eq $script:PrepRes.State.Online -and $script:OnlineCalls -eq $oc) 'denetim işi: ağsız seçenekte internet sınanmaz'
Assert-True (@($script:WhLog | Where-Object { $_ -match 'ağa çıkılmaz' }).Count -eq 1) 'denetim işi: ağsız denetim günlüğe yazılır'
$script:PrepRes = Job_PrepCheck $null
Assert-True ($script:PrepRes.Ok -eq $true -and $script:PrepRes.State.Online -eq $true -and $script:OnlineCalls -eq ($oc + 1)) 'denetim işi: parametre yoksa internet sınanır (önceki davranış)'
$script:PrepRes = Job_PrepCheck @{ NoNet = $false }
Assert-True ($script:PrepRes.State.Online -eq $true -and $script:OnlineCalls -eq ($oc + 2)) 'denetim işi: NoNet=false internet sınanır'
function Get-PrepState { throw 'toplama patladı' }
$script:PrepRes = Job_PrepCheck @{}
Assert-True ($script:PrepRes.Ok -eq $false -and $script:PrepRes.Error -match 'toplama patladı') 'denetim işi: hata durumunda Ok=false'
Remove-Item function:Get-PrepState
Remove-Item -LiteralPath $tmpData -Recurse -Force

# =====================================================================
#  4) satır kuralları
# =====================================================================
function New-St {
    $ex = @()
    foreach ($n in @('Sifreleme', 'Bellek', 'GuvenliSilme', 'WifiAktar', 'DiskKoruma', 'Kurtarma', 'DiskSilme')) { $ex += @{ Name = $n; Problem = '' } }
    $vc = @{ Installed = $true; Version = 'v14.44.35211.00'; Major = 14; Minor = 44; Build = 35211 }
    $vc2 = @{ Installed = $true; Version = 'v14.44.35211.00'; Major = 14; Minor = 44; Build = 35211 }
    return @{ Ok = $true; At = '09.11.2026 12:00'; Admin = $true
        Ps = @{ Version = '5.1.26100.4768'; Major = 5; Minor = 1; Edition = 'Desktop' }
        Os = @{ Name = 'Windows 11'; Build = 26100; Display = '24H2'; Is64 = $true; Arm = $false }
        Net = @{ Release = 533320; Name = '4.8.1' }
        Csc = @{ Found = $true; Path = 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe' }
        Vc = @{ X64 = $vc; X86 = $vc2; Arm64 = $null }
        Dx = @{ Native = $true; X86 = $true; Is64 = $true }
        Dotnet = @('8.0.11', '10.0.1')
        Winget = @{ Path = 'C:\Users\x\AppData\Local\Microsoft\WindowsApps\winget.exe'; Version = 'v1.11.400' }
        Wmi = @{ Ok = $true; Error = '' }
        Disk = @{ Letter = 'C:'; FreeGB = [double]120.4; SizeGB = [double]475.9 }
        Online = $true
        Data = @{ Path = 'C:\ProgramData\Multimizer'; Ok = $true; Error = '' }
        Exts = $ex
        Protect = @{ Known = $true; On = $true; Policy = $false } }
}
function Find-It($Items, [string]$Key) { foreach ($i in $Items) { if ([string]$i.Key -eq $Key) { return $i } }; return $null }

$all = Get-PrepItems (New-St)
Assert-Eq $all.Count 16 'satırlar: her şey yolundayken 16 satır (7 zorunlu, 7 önerilen, 2 isteğe bağlı)'
Assert-Eq (@($all | Where-Object { $_.Group -eq 'req' }).Count) 7 'satırlar: zorunlu grup'
Assert-Eq (@($all | Where-Object { $_.Group -eq 'rec' }).Count) 7 'satırlar: önerilen grup'
Assert-Eq (@($all | Where-Object { $_.Group -eq 'opt' }).Count) 2 'satırlar: isteğe bağlı grup'
Assert-Eq (@($all | Where-Object { $_.Status -ne 'ok' }).Count) 0 'satırlar: hepsi uygun'
Assert-Eq (@($all | Where-Object { $null -ne $_.Fix }).Count) 0 'satırlar: uygun satırlarda düğme yok'
Assert-Eq (@($all | ForEach-Object { $_.Key } | Select-Object -Unique).Count) 16 'satırlar: anahtarlar benzersiz'
$sum = Get-PrepSummary $all
Assert-True ($sum.Level -eq 'good' -and $sum.Ok -eq 16 -and $sum.Bad -eq 0 -and $sum.Warn -eq 0 -and $sum.Info -eq 0 -and $sum.Total -eq 16 -and $sum.Text -match '^Her şey hazır: 16') 'özet: her şey hazır'
Assert-Eq (Get-PrepInstallList $all).Count 0 'kurulum listesi: eksik yoksa boş'

# PowerShell
$s = New-St; $s.Ps = @{ Version = '4.0'; Major = 4; Minor = 0; Edition = 'Desktop' }
$i = Find-It (Get-PrepItems $s) 'ps'
Assert-True ($i.Status -eq 'bad' -and $i.Detail -match 'Sürüm 4.0' -and $i.Detail -match '5.1') 'PowerShell: eski sürüm zorunlu eksik'
$s.Ps = @{ Version = '5.0'; Major = 5; Minor = 0; Edition = 'Desktop' }
Assert-Eq (Find-It (Get-PrepItems $s) 'ps').Status 'bad' 'PowerShell: 5.0 yetersiz'
$s.Ps = @{ Version = '7.5.4'; Major = 7; Minor = 5; Edition = 'Core' }
Assert-Eq (Find-It (Get-PrepItems $s) 'ps').Status 'ok' 'PowerShell: 7 ve üzeri uygun'
$s.Ps = @{ Version = ''; Major = 5; Minor = 1; Edition = 'Desktop' }
Assert-True ((Find-It (Get-PrepItems $s) 'ps').Detail -match 'Sürüm 5.1') 'PowerShell: sürüm metni yoksa sayılardan kurulur'

# .NET Framework
foreach ($c in @(@(0, 'bad'), @(378389, 'bad'), @(379893, 'warn'), @(461308, 'warn'), @(461808, 'ok'), @(528040, 'ok'))) {
    $s = New-St; $s.Net = @{ Release = $c[0]; Name = (Get-PrepNetName ([int]$c[0])) }
    $i = Find-It (Get-PrepItems $s) 'net'
    Assert-Eq $i.Status $c[1] ('.NET Framework satırı: ' + [string]$c[0])
    if ($c[1] -ne 'ok') { Assert-True ($i.Fix.Do -eq 'Url' -and $i.Fix.Url -eq 'ms-settings:windowsupdate') ('.NET Framework satırı: Windows Update düğmesi ' + [string]$c[0]) }
}
$s = New-St; $s.Net = @{ Release = 0; Name = '' }
Assert-True ((Find-It (Get-PrepItems $s) 'net').Detail -match 'Okunamadı') '.NET Framework: sürüm okunamadıysa belirtilir'

# derleyici
$s = New-St; $s.Csc = @{ Found = $false; Path = '' }
$i = Find-It (Get-PrepItems $s) 'csc'
Assert-True ($i.Status -eq 'bad' -and $i.Detail -match 'derlenemez' -and $i.Fix.Do -eq 'Url') 'C# derleyicisi: yoksa zorunlu eksik, onarım için Windows Update'

# WMI
$s = New-St; $s.Wmi = @{ Ok = $false; Error = ('x' * 400) }
$i = Find-It (Get-PrepItems $s) 'wmi'
Assert-True ($i.Status -eq 'bad' -and $i.Fix.Do -eq 'Wmi' -and $i.Fix.Label -eq 'Doğrula ve onar' -and $i.Detail.Length -lt 500 -and $i.Detail -match '\.\.\.') 'WMI satırı: bozuksa onarım düğmesi, uzun hata kısaltılır'

# Windows sürümü
foreach ($c in @(@(26100, 'ok'), @(19041, 'ok'), @(18363, 'warn'), @(10240, 'warn'), @(9600, 'bad'), @(0, 'info'))) {
    $s = New-St; $s.Os.Build = $c[0]; if ($c[0] -eq 0) { $s.Os.Name = '' ; $s.Os.Display = '' }
    $i = Find-It (Get-PrepItems $s) 'os'
    Assert-Eq $i.Status $c[1] ('Windows sürümü: derleme ' + [string]$c[0])
}
$s = New-St
Assert-True ((Find-It (Get-PrepItems $s) 'os').Detail -match '^Windows 11 24H2 \(derleme 26100\)') 'Windows sürümü: ad, sürüm ve derleme yazılır'

# eklentiler
$s = New-St; $s.Exts[5].Problem = 'Eklenti/Kurtarma.ps1 bulunamadı.'; $s.Exts[6].Problem = 'özet uyuşmuyor'
$i = Find-It (Get-PrepItems $s) 'ext'
Assert-True ($i.Status -eq 'bad' -and $i.Detail -match '^2 eklenti eksik ya da değişmiş: Kurtarma, DiskSilme' -and $i.Detail -match 'ZIP dosyasının tamamını') 'eklentiler: eksik olanlar adıyla listelenir'
$s = New-St; $s.Exts = @()
Assert-Eq (Find-It (Get-PrepItems $s) 'ext').Status 'info' 'eklentiler: denetlenemediyse bilgi'
Assert-True ((Find-It $all 'ext').Detail -match '^7 eklentinin hepsi') 'eklentiler: hepsi uygunsa sayı yazılır'

# veri klasörü
$s = New-St; $s.Data = @{ Path = 'C:\ProgramData\Multimizer'; Ok = $false; Error = 'Erişim engellendi' }
$i = Find-It (Get-PrepItems $s) 'data'
Assert-True ($i.Status -eq 'bad' -and $i.Detail -match 'Erişim engellendi' -and $i.Detail -match 'ProgramData') 'veri klasörü: yazılamıyorsa zorunlu eksik'

# yönetici
$s = New-St; $s.Admin = $false
$i = Find-It (Get-PrepItems $s) 'admin'
Assert-True ($i.Status -eq 'warn' -and $i.Detail -match 'Baslat.bat' -and $null -eq $i.Fix) 'yönetici: yoksa uyarı, düğme yok'

# boş alan
foreach ($c in @(@(1.5, 475, 'bad'), @(5, 475, 'warn'), @(9.9, 100, 'warn'), @(30, 500, 'warn'), @(40, 500, 'ok'), @(15, 100, 'ok'), @(200, 475, 'ok'))) {
    $s = New-St; $s.Disk = @{ Letter = 'C:'; FreeGB = [double]$c[0]; SizeGB = [double]$c[1] }
    $i = Find-It (Get-PrepItems $s) 'space'
    Assert-Eq $i.Status $c[2] ('boş alan: ' + [string]$c[0] + ' / ' + [string]$c[1] + ' GB')
    if ($c[2] -ne 'ok') { Assert-True ($i.Fix.Do -eq 'Page' -and $i.Fix.Page -eq 'clean') ('boş alan: Temizlik düğmesi ' + [string]$c[0]) }
}
$s = New-St; $s.Disk = @{ Letter = 'C:'; FreeGB = [double]0; SizeGB = [double]0 }
Assert-Eq (Find-It (Get-PrepItems $s) 'space').Status 'info' 'boş alan: okunamadıysa bilgi'
$s = New-St; $s.Disk = @{ Letter = 'C:'; FreeGB = [double]12.6; SizeGB = [double]100 }
Assert-True ((Find-It (Get-PrepItems $s) 'space').Detail -match '^C: sürücüsünde 12.6 GB boş \(%13\)') 'boş alan: metin ve yüzde'

# winget
$s = New-St; $s.Winget = @{ Path = ''; Version = '' }
$i = Find-It (Get-PrepItems $s) 'winget'
Assert-True ($i.Status -eq 'warn' -and $i.Fix.Do -eq 'Url' -and $i.Fix.Url -eq 'ms-windows-store://pdp/?ProductId=9NBLGGH4NNS1' -and $i.Detail -match 'Uygulama Yükleyicisi') 'winget: yoksa Store düğmesi'
Assert-True ((Find-It $all 'winget').Detail -match '\(v1.11.400\)') 'winget: sürüm yazılır'
$s = New-St; $s.Winget = @{ Path = 'C:\winget.exe'; Version = '' }
Assert-True ((Find-It (Get-PrepItems $s) 'winget').Detail -notmatch '\(\)') 'winget: sürüm okunamadıysa boş parantez yok'

# Visual C++
$s = New-St; $s.Vc.X64 = @{ Installed = $false; Version = ''; Major = 0; Minor = 0; Build = 0 }
$i = Find-It (Get-PrepItems $s) 'vcx64'
Assert-True ($i.Status -eq 'warn' -and $i.Fix.Do -eq 'Winget' -and $i.Fix.Id -eq 'Microsoft.VCRedist.2015+.x64' -and $i.Fix.Name -match 'x64' -and $i.Detail -match 'Yüklü değil') 'VC++ x64: yoksa kurulum düğmesi izin listesindeki kimlikle'
$s = New-St; $s.Vc.X64 = $null
Assert-Eq (Find-It (Get-PrepItems $s) 'vcx64').Status 'warn' 'VC++ x64: okunamadıysa yok sayılır'
$s = New-St; $s.Vc.X86 = @{ Installed = $true; Version = 'v14.28.29914.00'; Major = 14; Minor = 28; Build = 29914 }
$i = Find-It (Get-PrepItems $s) 'vcx86'
Assert-True ($i.Status -eq 'warn' -and $i.Detail -match 'Eski sürüm' -and $i.Detail -match '14.28' -and $i.Fix.Id -eq 'Microsoft.VCRedist.2015+.x86') 'VC++ x86: eski sürüm güncelleme önerir'
$s.Vc.X86 = @{ Installed = $true; Version = 'v14.30.30708.00'; Major = 14; Minor = 30; Build = 30708 }
Assert-Eq (Find-It (Get-PrepItems $s) 'vcx86').Status 'ok' 'VC++ x86: 14.30 uygun'
$s.Vc.X86 = @{ Installed = $true; Version = ''; Major = 14; Minor = 44; Build = 0 }
Assert-True ((Find-It (Get-PrepItems $s) 'vcx86').Detail -match '14.44') 'VC++: sürüm metni yoksa sayılardan kurulur'
$s = New-St; $s.Os.Is64 = $false
Assert-True ($null -eq (Find-It (Get-PrepItems $s) 'vcx86') -and $null -ne (Find-It (Get-PrepItems $s) 'vcx64')) 'VC++: 32 bit Windows için ayrı x86 satırı yok'
$s = New-St; $s.Os.Arm = $true; $s.Vc.Arm64 = @{ Installed = $false; Version = ''; Major = 0; Minor = 0; Build = 0 }
$i = Find-It (Get-PrepItems $s) 'vcarm64'
Assert-True ($i.Status -eq 'warn' -and $i.Fix.Id -eq 'Microsoft.VCRedist.2015+.arm64') 'VC++ ARM64: ARM bilgisayarda satır ve düğme'
Assert-True ($null -eq (Find-It $all 'vcarm64')) 'VC++ ARM64: ARM değilse satır yok'

# Sistem Koruması
$s = New-St; $s.Protect = @{ Known = $true; On = $false; Policy = $true }
$i = Find-It (Get-PrepItems $s) 'restore'
Assert-True ($i.Status -eq 'warn' -and $i.Detail -match 'ilke') 'Sistem Koruması: ilkeyle kapalı'
$s.Protect = @{ Known = $true; On = $false; Policy = $false }
$i = Find-It (Get-PrepItems $s) 'restore'
Assert-True ($i.Status -eq 'info' -and $i.Detail -match 'sizin için açar') 'Sistem Koruması: kapalıysa bilgi, Multimizer açar'
$s.Protect = @{ Known = $false; On = $false; Policy = $false }
Assert-True ((Find-It (Get-PrepItems $s) 'restore').Detail -match 'okunamadı') 'Sistem Koruması: okunamadı'

# bağlantı
$s = New-St; $s.Online = $false
$i = Find-It (Get-PrepItems $s) 'online'
Assert-True ($i.Status -eq 'info' -and $i.Detail -match 'bağlantısız çalışır') 'bağlantı: yoksa bilgi'
$s.Online = $null
Assert-True ($null -eq (Find-It (Get-PrepItems $s) 'online')) 'bağlantı: sorulmadıysa satır yok'

# DirectX ve .NET masaüstü
$s = New-St; $s.Dx = @{ Native = $true; X86 = $false; Is64 = $true }
$i = Find-It (Get-PrepItems $s) 'dx'
Assert-True ($i.Status -eq 'info' -and $i.Fix.Id -eq 'Microsoft.DirectX' -and $i.Detail -match 'Multimizer için gerekmez') 'DirectX: bir kopya eksikse isteğe bağlı kurulum'
$s.Dx = $null
Assert-True ($null -eq (Find-It (Get-PrepItems $s) 'dx')) 'DirectX: okunamadıysa satır yok'
$s = New-St; $s.Dotnet = @()
$i = Find-It (Get-PrepItems $s) 'dotnet'
Assert-True ($i.Status -eq 'info' -and $i.Fix.Id -eq 'Microsoft.DotNet.DesktopRuntime.10') '.NET masaüstü: yoksa isteğe bağlı kurulum'
$s.Dotnet = @('6.0.36', '7.0.20')
Assert-Eq (Find-It (Get-PrepItems $s) 'dotnet').Status 'info' '.NET masaüstü: 6 ve 7 yeterli sayılmaz'
$s.Dotnet = @('6.0.36', '8.0.1')
Assert-True ((Find-It (Get-PrepItems $s) 'dotnet').Status -eq 'ok' -and (Find-It (Get-PrepItems $s) 'dotnet').Detail -match '8.0.1') '.NET masaüstü: 8 ve üzeri yeterli'

# uzman kipi
$s = New-St
$ex = Get-PrepItems $s $true
Assert-True ((Find-It $ex 'net').Detail -match 'Release anahtarı: 533320' -and (Find-It $ex 'csc').Detail -match 'Yol: C:' -and (Find-It $ex 'winget').Detail -match 'winget.exe' -and (Find-It $ex 'vcx64').Detail -match 'Derleme: 35211' -and (Find-It $ex 'dotnet').Detail -match '8.0.11, 10.0.1' -and (Find-It $ex 'ps').Detail -match 'Tür: Desktop' -and (Find-It $ex 'data').Detail -match 'Yol: C:.ProgramData') 'uzman kipi: ham değerler eklenir'
Assert-True ((Find-It $all 'net').Detail -notmatch 'Release anahtarı') 'kullanıcı kipi: ham değer yok'
Assert-Eq $ex.Count 16 'uzman kipi: satır sayısı değişmez'

# özet ve kurulum listesi
$s = New-St; $s.Vc.X64 = $null; $s.Vc.X86 = @{ Installed = $false; Version = ''; Major = 0; Minor = 0; Build = 0 }; $s.Dx = @{ Native = $false; X86 = $false; Is64 = $true }; $s.Dotnet = @()
$items = Get-PrepItems $s
$sum = Get-PrepSummary $items
Assert-True ($sum.Level -eq 'warn' -and $sum.Warn -eq 2 -and $sum.Info -eq 2 -and $sum.Bad -eq 0 -and $sum.Text -match '2 önerilen') 'özet: önerilenler eksikse uyarı'
$lst = Get-PrepInstallList $items
Assert-Eq $lst.Count 4 'kurulum listesi: dört eksik paket'
Assert-Eq (($lst | ForEach-Object { $_.Id }) -join ',') 'Microsoft.VCRedist.2015+.x64,Microsoft.VCRedist.2015+.x86,Microsoft.DirectX,Microsoft.DotNet.DesktopRuntime.10' 'kurulum listesi: sıra ve kimlikler'
Assert-True (($lst | Where-Object { [string]$_.Name -eq '' }).Count -eq 0) 'kurulum listesi: adlar dolu'
$lst2 = Get-PrepInstallList $items @('dx', 'vcx64')
Assert-Eq (($lst2 | ForEach-Object { $_.Key }) -join ',') 'vcx64,dx' 'kurulum listesi: seçili anahtarlar, satır sırasıyla'
$lst3 = Get-PrepInstallList $items @('os')
Assert-Eq $lst3.Count 0 'kurulum listesi: düğmesi olmayan satırlar atlanır'
$dup = @( (New-PrepItem 'a' 'rec' 'warn' 'A' 'x' (New-PrepFix 'Winget' 'Kur' @{ Id = 'Microsoft.DirectX'; Name = 'DirectX' })), (New-PrepItem 'b' 'opt' 'info' 'B' 'y' (New-PrepFix 'Winget' 'Kur' @{ Id = 'microsoft.directx'; Name = 'DirectX' })) )
Assert-Eq (Get-PrepInstallList $dup).Count 1 'kurulum listesi: aynı kimlik bir kez'
$nonOk = @( (New-PrepItem 'u' 'req' 'warn' 'U' 'x' (New-PrepFix 'Url' 'Aç' @{ Url = 'ms-settings:windowsupdate' })) )
Assert-Eq (Get-PrepInstallList $nonOk).Count 0 'kurulum listesi: Url düğmeleri kurulum sayılmaz'
$okRow = @( (New-PrepItem 'o' 'rec' 'ok' 'O' 'x' (New-PrepFix 'Winget' 'Kur' @{ Id = 'Microsoft.DirectX'; Name = 'DirectX' })) )
Assert-Eq (Get-PrepInstallList $okRow).Count 0 'kurulum listesi: uygun satır atlanır'
# özet düzeyleri
$s = New-St; $s.Net = @{ Release = 0; Name = '' }; $s.Vc.X64 = $null
$sum = Get-PrepSummary (Get-PrepItems $s)
Assert-True ($sum.Level -eq 'bad' -and $sum.Bad -eq 1 -and $sum.Warn -eq 1 -and $sum.Text -match '^1 zorunlu ya da önemli eksik var, 1 öneri' -and $sum.Text -match 'kırmızı') 'özet: zorunlu eksik varsa kırmızı'
$s = New-St; $s.Dotnet = @()
$sum = Get-PrepSummary (Get-PrepItems $s)
Assert-True ($sum.Level -eq 'good' -and $sum.Info -eq 1 -and $sum.Text -match '1 isteğe bağlı') 'özet: yalnızca isteğe bağlı eksik'
$sum = Get-PrepSummary @()
Assert-True ($sum.Total -eq 0 -and $sum.Level -eq 'good') 'özet: satır yoksa'

# =====================================================================
#  5) kurulum işi (sahte winget ile)
# =====================================================================
$script:WgCalls = New-Object System.Collections.ArrayList
$script:WgCodes = @{}
$script:WgThrow = @{}
$script:WgPath = 'C:\winget.exe'
function Invoke-WingetRaw([string[]]$WgArgs) {
    [void]$script:WgCalls.Add($WgArgs -join ' ')
    $id = ''
    for ($k = 0; $k -lt $WgArgs.Count; $k++) { if ($WgArgs[$k] -eq '--id') { $id = $WgArgs[$k + 1] } }
    if ($script:WgThrow.ContainsKey($id)) { throw $script:WgThrow[$id] }
    $code = 0
    if ($script:WgCodes.ContainsKey($id)) { $code = $script:WgCodes[$id] }
    return @{ Lines = @('indiriliyor', 'kuruluyor'); Code = $code }
}
$script:WgLines = 0
function Write-WingetLines($Lines) { $script:WgLines += @($Lines).Count }
$script:Counters = @{ Reset = 0; Done = 0; Err = 0; Steps = 0 }
function Reset-Counters { $script:Counters.Reset++ }
function Add-Done([string]$Message) { $script:Counters.Done++ }
function Add-Err([string]$Message) { $script:Counters.Err++ }
function Set-JobProgress([int]$Done, [int]$Total, [string]$Label = '') { }
function Step-JobProgress([string]$Label = '') { $script:Counters.Steps++ }
$script:CancelAfter = -1
function Test-JobCancel { return ($script:CancelAfter -ge 0 -and $script:Counters.Steps -ge $script:CancelAfter) }
function Reset-WgTest { $script:WgCalls.Clear(); $script:WgCodes = @{}; $script:WgThrow = @{}; $script:WgLines = 0; $script:Counters = @{ Reset = 0; Done = 0; Err = 0; Steps = 0 }; $script:CancelAfter = -1; $script:WhLog.Clear() }

Reset-WgTest
$r = Job_PrepInstall @{ Ids = @('Microsoft.VCRedist.2015+.x64', 'Microsoft.DirectX') }
Assert-True ($r.Ok -eq $true -and $r.Done -eq 2 -and $r.Failed -eq 0 -and $r.Reboot -eq $false -and $r.Canceled -eq $false -and $r.Items.Count -eq 2) 'kurulum işi: iki paket kuruldu'
Assert-Eq $script:WgCalls.Count 2 'kurulum işi: paket başına bir winget çağrısı'
Assert-Eq $script:WgCalls[0] 'install --id Microsoft.VCRedist.2015+.x64 --exact --silent --accept-package-agreements --accept-source-agreements --disable-interactivity' 'kurulum işi: winget bağımsız değişkenleri (tam eşleşme, sessiz, etkileşimsiz)'
Assert-True ($r.Items[0].Ok -eq $true -and $r.Items[0].Code -eq 0 -and $r.Items[1].Id -eq 'Microsoft.DirectX') 'kurulum işi: paket sonuçları sırayla'
Assert-True ($script:Counters.Reset -eq 1 -and $script:Counters.Done -eq 2 -and $script:Counters.Steps -eq 2 -and $script:WgLines -eq 4) 'kurulum işi: sayaçlar, ilerleme ve winget çıktısı'

Reset-WgTest
$script:WgCodes['Microsoft.VCRedist.2015+.x64'] = -1978335189
$script:WgCodes['Microsoft.VCRedist.2015+.x86'] = 3010
$r = Job_PrepInstall @{ Ids = @('Microsoft.VCRedist.2015+.x64', 'Microsoft.VCRedist.2015+.x86') }
Assert-True ($r.Ok -eq $true -and $r.Done -eq 2 -and $r.Reboot -eq $true -and $r.Items[0].Text -eq 'zaten kurulu' -and $r.Items[1].Text -match 'yeniden başlatma') 'kurulum işi: zaten kurulu ve yeniden başlatma gerekli sayılır başarı'

Reset-WgTest
$script:WgCodes['Microsoft.DirectX'] = -1978335215
$r = Job_PrepInstall @{ Ids = @('Microsoft.VCRedist.2015+.x64', 'Microsoft.DirectX') }
Assert-True ($r.Ok -eq $false -and $r.Done -eq 1 -and $r.Failed -eq 1 -and $r.Items[1].Ok -eq $false -and $r.Items[1].Text -match 'özeti paketle uyuşmadı' -and $script:Counters.Err -eq 1) 'kurulum işi: özet uyuşmazlığı başarısızlık sayılır, diğer paket kurulur'
Assert-True ($r.Error -eq '') 'kurulum işi: kısmi başarıda genel hata metni boş'

Reset-WgTest
$script:WgCodes['Microsoft.DirectX'] = -1978335212
$r = Job_PrepInstall @{ Ids = @('Microsoft.DirectX') }
Assert-True ($r.Ok -eq $false -and $r.Done -eq 0 -and $r.Failed -eq 1 -and $r.Error -match 'bulunamadı') 'kurulum işi: hiç kurulmadıysa hata metni ilk nedenden gelir'

Reset-WgTest
$script:WgThrow['Microsoft.DirectX'] = 'winget çalıştırılamadı'
$r = Job_PrepInstall @{ Ids = @('Microsoft.DirectX') }
Assert-True ($r.Ok -eq $false -and $r.Failed -eq 1 -and $r.Items[0].Code -eq -1 -and $r.Items[0].Text -eq 'winget çıkış kodu -1' -and ($script:WhLog | Where-Object { $_ -match 'winget çalıştırılamadı' }).Count -eq 1) 'kurulum işi: winget özel durum verirse başarısız ve günlüğe yazılır'

Reset-WgTest
$r = Job_PrepInstall @{ Ids = @('Vendor.Tool', 'Microsoft.DirectX; calc', 'Microsoft.DirectX') }
Assert-True ($r.Ok -eq $false -and $r.Done -eq 1 -and $r.Failed -eq 2 -and $script:WgCalls.Count -eq 1 -and $script:WgCalls[0] -match '--id Microsoft.DirectX ') 'kurulum işi: izin listesinde olmayan kimlikler winget a hiç gönderilmez'
Assert-True ($r.Items[0].Text -match 'izin listesinde değil' -and $r.Items[1].Text -match 'Geçersiz paket kimliği') 'kurulum işi: reddetme nedenleri bildirilir'

Reset-WgTest
$r = Job_PrepInstall @{ Ids = @('Microsoft.DirectX', 'Microsoft.DirectX', '', 'Microsoft.DirectX') }
Assert-True ($r.Done -eq 1 -and $script:WgCalls.Count -eq 1) 'kurulum işi: yinelenen ve boş kimlikler atlanır'

Reset-WgTest
$r = Job_PrepInstall @{ Ids = @() }
Assert-True ($r.Ok -eq $false -and $r.Error -match 'seçilmedi' -and $script:WgCalls.Count -eq 0) 'kurulum işi: kimlik yoksa hiçbir şey yapılmaz'
$r = Job_PrepInstall @{ }
Assert-True ($r.Ok -eq $false -and $script:WgCalls.Count -eq 0) 'kurulum işi: kimlik anahtarı yoksa da güvenli'

Reset-WgTest
$script:WgPath = ''
$r = Job_PrepInstall @{ Ids = @('Microsoft.DirectX') }
Assert-True ($r.Ok -eq $false -and $r.Error -match 'winget bulunamadı' -and $r.Error -match 'App Installer' -and $script:WgCalls.Count -eq 0 -and ($script:WhLog | Where-Object { $_ -match '^ERR\|' }).Count -eq 1) 'kurulum işi: winget yoksa kurulum denenmez'
$script:WgPath = 'C:\winget.exe'

Reset-WgTest
$script:CancelAfter = 1
$r = Job_PrepInstall @{ Ids = @('Microsoft.VCRedist.2015+.x64', 'Microsoft.VCRedist.2015+.x86', 'Microsoft.DirectX') }
Assert-True ($r.Canceled -eq $true -and $r.Ok -eq $false -and $r.Done -eq 1 -and $script:WgCalls.Count -eq 1) 'kurulum işi: iptalde kalan paketler kurulmaz'

Reset-WgTest
$script:WgCodes['Microsoft.DirectX'] = -1978334966
$r = Job_PrepInstall @{ Ids = @('Microsoft.DirectX') }
Assert-True ($r.Ok -eq $false -and $r.Reboot -eq $true -and $r.Items[0].Text -match 'önce bilgisayarı') 'kurulum işi: önce yeniden başlatma gerekiyorsa bildirilir'

# WMI onarımı (sahte winmgmt.exe)
$script:WmiCalls = New-Object System.Collections.ArrayList
$script:WmiPlan = @{ Verify = @('WMI repository is consistent', 0); Salvage = @('WMI repository salvage ok', 0) }
function winmgmt.exe {
    [void]$script:WmiCalls.Add($args -join ' ')
    $p = $script:WmiPlan.Verify
    if (($args -join ' ') -match 'salvage') { $p = $script:WmiPlan.Salvage }
    $global:LASTEXITCODE = [int]$p[1]
    if ([string]$p[0] -ne '') { $p[0] }
}
$script:CimMode = 'ok'
$w = Invoke-PrepWmiRepair
Assert-True ($w.Ok -eq $true -and $w.Verified -eq $true -and $w.Salvaged -eq $false -and $w.Text -match 'tutarlı' -and $script:WmiCalls.Count -eq 1 -and $script:WmiCalls[0] -eq '/verifyrepository') 'WMI onarımı: tutarlıysa onarım çağrılmaz'
$script:WmiCalls.Clear()
$script:WmiPlan = @{ Verify = @('WMI repository is inconsistent', 0); Salvage = @('', 0) }
$w = Invoke-PrepWmiRepair
Assert-True ($w.Ok -eq $true -and $w.Salvaged -eq $true -and $script:WmiCalls.Count -eq 2 -and $script:WmiCalls[1] -eq '/salvagerepository' -and $w.Text -match 'onarıldı') 'WMI onarımı: tutarsızsa onarılır ve yeniden sınanır'
$script:WmiCalls.Clear()
$script:WmiPlan = @{ Verify = @('', 1); Salvage = @('', 0) }
$w = Invoke-PrepWmiRepair
Assert-True ($w.Salvaged -eq $true -and $w.Ok -eq $true) 'WMI onarımı: doğrulama sıfır olmayan kodla biterse de onarılır'
$script:WmiCalls.Clear()
$script:WmiPlan = @{ Verify = @('WMI deposu tutarlı değil', 0); Salvage = @('', 0) }
$w = Invoke-PrepWmiRepair
Assert-True ($w.Salvaged -eq $true) 'WMI onarımı: Türkçe iletiyle de tutarsızlık anlaşılır'
$script:WmiCalls.Clear()
$script:WmiPlan = @{ Verify = @('WMI repository is inconsistent', 0); Salvage = @('hata', 5) }
$w = Invoke-PrepWmiRepair
Assert-True ($w.Ok -eq $false -and $w.Salvaged -eq $true -and $w.Text -match 'onarılamadı' -and $w.Text -match '5') 'WMI onarımı: onarım başarısızsa kod bildirilir'
$script:WmiCalls.Clear()
$script:WmiPlan = @{ Verify = @('WMI repository is inconsistent', 0); Salvage = @('', 0) }
$script:CimMode = 'throw'
$w = Invoke-PrepWmiRepair
Assert-True ($w.Ok -eq $false -and $w.Text -match 'hâlâ başarısız' -and $w.Text -match '0x80041010') 'WMI onarımı: onarımdan sonra sorgu hâlâ bozuksa belirtilir'
$script:CimMode = 'ok'
$script:WhLog.Clear()
$script:WmiPlan = @{ Verify = @('WMI repository is consistent', 0); Salvage = @('', 0) }
$jr = Job_PrepWmi @{}
Assert-True ($jr.Ok -eq $true -and ($script:WhLog | Where-Object { $_ -match '^OK\|' }).Count -eq 1) 'WMI işi: başarı günlüğe OK olarak yazılır'
function Invoke-PrepWmiRepair { throw 'winmgmt yok' }
$jr = Job_PrepWmi @{}
Assert-True ($jr.Ok -eq $false -and $jr.Text -match 'winmgmt yok') 'WMI işi: özel durum sonuca çevrilir'
Remove-Item function:Invoke-PrepWmiRepair

# =====================================================================
#  6) arayüz: kurulum sonucu iletileri
# =====================================================================
$m = Get-PrepInstallModel $null
Assert-True ($m.Kind -eq 'bad' -and $m.Text -match 'günlüğe bakın') 'ileti: boş sonuç'
$m = Get-PrepInstallModel @{ Ok = $true; Done = 3; Failed = 0; Reboot = $false; Items = @() }
Assert-True ($m.Kind -eq 'good' -and $m.Text -eq '3 bileşen kuruldu.') 'ileti: başarı'
$m = Get-PrepInstallModel @{ Ok = $true; Done = 1; Failed = 0; Reboot = $true; Items = @() }
Assert-True ($m.Kind -eq 'warn' -and $m.Text -match 'yeniden başlatın') 'ileti: başarı, yeniden başlatma'
$m = Get-PrepInstallModel @{ Ok = $false; Canceled = $true; Done = 1; Failed = 0; Items = @() }
Assert-True ($m.Kind -eq 'warn' -and $m.Text -match 'iptal edildi' -and $m.Text -match '1 bileşen') 'ileti: iptal'
$m = Get-PrepInstallModel @{ Ok = $false; Done = 1; Failed = 1; Items = @(@{ Id = 'Microsoft.VCRedist.2015+.x64'; Ok = $true; Text = 'kuruldu' }, @{ Id = 'Microsoft.DirectX'; Ok = $false; Text = 'bulunamadı' }) }
Assert-True ($m.Kind -eq 'bad' -and $m.Text -match '^1 bileşen kuruldu, 1 kurulamadı\.' -and $m.Text -match 'DirectX eski çalışma zamanı.*: bulunamadı') 'ileti: kısmi başarısızlık, paket adıyla'
$m = Get-PrepInstallModel @{ Ok = $false; Done = 0; Failed = 3; Items = @(@{ Id = 'Microsoft.DirectX'; Ok = $false; Text = 'a' }, @{ Id = 'Microsoft.DotNet.DesktopRuntime.10'; Ok = $false; Text = 'b' }, @{ Id = 'Vendor.X'; Ok = $false; Text = 'c' }) }
Assert-True ($m.Kind -eq 'bad' -and $m.Text -match '\(\+1 bileşen daha\)' -and ($m.Text -match 'Vendor.X') -eq $false) 'ileti: yalnızca ilk iki başarısızlık yazılır'
$m = Get-PrepInstallModel @{ Ok = $false; Done = 0; Failed = 0; Error = 'winget bulunamadı.'; Items = @() }
Assert-Eq $m.Text 'winget bulunamadı.' 'ileti: genel hata metni'
$m = Get-PrepInstallModel @{ Ok = $false; Done = 0; Failed = 0; Items = @() }
Assert-True ($m.Text -match 'günlüğe bakın') 'ileti: nedensiz hata'
Assert-Eq (Get-PrepBr 'bad') 'BrBad' 'renk: bad'
Assert-Eq (Get-PrepBr 'warn') 'BrWarn' 'renk: warn'
Assert-Eq (Get-PrepBr 'ok') 'BrGood' 'renk: ok'
Assert-Eq (Get-PrepBr 'info') 'BrInfo' 'renk: info'

# =====================================================================
#  7) arayüz: çizim
# =====================================================================
$script:UiState = @{ Page = 'solve'; Mode = 'Kullanici' }
$script:SlTab = 'prep'
$apos = [string][char]0x2019
$ui = @{}
foreach ($n in @('sl_List', 'sl_Foot', 'sl_PrCheck', 'sl_PrFix')) { $ui[$n] = New-FakeCtl }
$script:PrepState = $null
Reset-Fake
Render-SlPrep
Assert-True ($null -ne (Find-NoteLike $ui.sl_List 'denetleniyor')) 'çizim: durum yokken denetleniyor notu'
Assert-True ($script:Asyncs.Count -eq 1 -and $script:Asyncs[0].Name -eq 'PrepCheck' -and $script:Asyncs[0].Entry -eq 'Job_PrepCheck' -and $script:PrepLoading -eq $true) 'çizim: denetim işi başlatılır'
Render-SlPrep
Assert-Eq $script:Asyncs.Count 1 'çizim: iş sürerken ikinci kez başlatılmaz'
$a = $script:Asyncs[0]
Reset-Fake
& $a.OnDone @{ Ok = $true; State = $st }
Assert-True ($script:PrepLoading -eq $false -and $null -ne $script:PrepState -and $script:PrepState.Failed -ne $true) 'tamamlanma: durum saklandı'
Assert-True ($ui.sl_List.Children.Count -gt 5) 'tamamlanma: sekme açıkken liste çizildi'

# başarısız denetim
Reset-Fake
$script:PrepState = $null
Render-SlPrep
$a = $script:Asyncs[0]
& $a.OnDone $null
Assert-True ($script:PrepState.Failed -eq $true -and $null -ne (Find-NoteLike $ui.sl_List 'Denetim yapılamadı')) 'tamamlanma: boş sonuç başarısızlık sayılır'
Reset-Fake
Render-SlPrep
Assert-True ($script:Asyncs.Count -eq 0 -and $null -ne (Find-NoteLike $ui.sl_List 'Denetim yapılamadı')) 'çizim: başarısız durumda yeniden otomatik denenmez'
$script:PrepLoading = $false
Reset-Fake
$script:PrepState = $null
Render-SlPrep
& $script:Asyncs[0].OnDone @{ Ok = $false; Error = 'x' }
Assert-True ($script:PrepState.Failed -eq $true) 'tamamlanma: Ok=false başarısızlık'

# eksiklerle çizim
$s = New-St
$s.Vc.X64 = $null
$s.Net = @{ Release = 379893; Name = '4.5.2' }
$s.Dx = @{ Native = $false; X86 = $false; Is64 = $true }
$s.Winget = @{ Path = ''; Version = '' }
$script:PrepState = $s
Reset-Fake
Render-SlPrep
$heads = @($ui.sl_List.Children | Where-Object { $_.Head -eq $true })
Assert-Eq $heads.Count 3 'çizim: üç grup başlığı'
Assert-Eq (($heads | ForEach-Object { $_.Text }) -join '|') 'Zorunlu bileşenler|Önerilen bileşenler|İsteğe bağlı bileşenler' 'çizim: başlıklar'
$rows = @(Get-RowsOf $ui.sl_List)
Assert-Eq $rows.Count 17 'çizim: durum satırı artı 16 denetim satırı'
$srow = $rows[0]
Assert-True ($srow.Vars.Title -eq 'Durum' -and $srow.Vars.Btn1 -eq 'Eksikleri gider' -and $srow.Tag.Do -eq 'FixAll' -and $srow.Vars.BrCol -eq 'BrWarn' -and $srow.Named.Act.Handlers.Count -eq 1) 'çizim: özet satırı, kurulacak eksik varken düğmeyle'
$rv = @($rows | Where-Object { $_.Tag.Key -eq 'vcx64' })[0]
Assert-True ($rv.Vars.Btn1 -eq 'Kur' -and $rv.Tag.Do -eq 'Winget' -and $rv.Tag.Id -eq 'Microsoft.VCRedist.2015+.x64' -and $rv.Tag.Name -match 'x64' -and $rv.Vars.BrCol -eq 'BrWarn' -and $rv.Named.Act.Handlers.Count -eq 1) 'çizim: VC++ satırında Kur düğmesi ve paket verisi'
$rn = @($rows | Where-Object { $_.Tag.Key -eq 'net' })[0]
Assert-True ($rn.Vars.Btn1 -eq ('Windows Update' + $apos + 'i aç') -and $rn.Tag.Do -eq 'Url' -and $rn.Tag.Url -eq 'ms-settings:windowsupdate') 'çizim: .NET Framework satırında Windows Update düğmesi'
$rw = @($rows | Where-Object { $_.Tag.Key -eq 'winget' })[0]
Assert-True ($rw.Vars.Btn1 -eq ('Store' + $apos + 'da aç') -and $rw.Tag.Do -eq 'Url') 'çizim: winget satırında Store düğmesi'
$rok = @($rows | Where-Object { $_.Tag.Key -eq 'ps' })[0]
Assert-True ($rok.Vars.Btn1 -eq '' -and $rok.Vars.BrCol -eq 'BrGood' -and $rok.Named.Act.Handlers.Count -eq 0) 'çizim: uygun satırda düğme yok'
$rd = @($rows | Where-Object { $_.Tag.Key -eq 'dx' })[0]
Assert-True ($rd.Vars.Btn1 -eq 'Kur' -and $rd.Vars.BrCol -eq 'BrInfo') 'çizim: isteğe bağlı satır bilgi renginde'
Assert-True ($ui.sl_Foot.Text -match '^Denetlendi: 09.11.2026 12:00' -and $script:PrepItems.Count -eq 16) 'çizim: alt metin ve satırlar saklanır'

# her şey hazırken
$script:PrepState = New-St
Reset-Fake
Render-SlPrep
$rows = @(Get-RowsOf $ui.sl_List)
Assert-True ($rows[0].Vars.Btn1 -eq '' -and $rows[0].Vars.BrCol -eq 'BrGood' -and $rows[0].Vars.Detail -match '^Her şey hazır') 'çizim: her şey hazırken özet yeşil, düğmesiz'
# zorunlu eksik
$s = New-St; $s.Csc = @{ Found = $false; Path = '' }
$script:PrepState = $s
Render-SlPrep
$rows = @(Get-RowsOf $ui.sl_List)
Assert-Eq $rows[0].Vars.BrCol 'BrBad' 'çizim: zorunlu eksikte özet kırmızı'
Assert-Eq $rows[0].Vars.Btn1 '' 'çizim: kurulacak paket yoksa özette düğme yok'

# =====================================================================
#  8) arayüz: eylemler ve onaylar
# =====================================================================
$s = New-St
$s.Vc.X64 = $null
$s.Vc.X86 = @{ Installed = $false; Version = ''; Major = 0; Minor = 0; Build = 0 }
$s.Dx = @{ Native = $false; X86 = $false; Is64 = $true }
$script:PrepState = $s
Render-SlPrep
$rows = @(Get-RowsOf $ui.sl_List)
$rv = @($rows | Where-Object { $_.Tag.Key -eq 'vcx64' })[0]
Reset-Fake
Invoke-PrepAction $rv.Tag
Assert-Eq $script:Confirms.Count 1 'tek kurulum: onay açıldı'
Assert-True ($script:Confirms[0].Title -eq 'Eksik bileşenleri kur' -and $script:Confirms[0].Ok -eq 'Kur' -and $script:Confirms[0].Text -match 'Visual C\+\+ 2015-2022 çalışma zamanı \(x64\)' -and $script:Confirms[0].Text -match 'SHA-256' -and $script:Confirms[0].Text -match 'yeniden başlatılmasını') 'tek kurulum: onay metni paketi, özet doğrulamasını ve yeniden başlatma olasılığını yazar'
Assert-True ($script:Confirms[0].Text -notmatch 'x86' -and $script:Confirms[0].Danger -eq $false) 'tek kurulum: yalnızca seçilen paket yazılır'
Assert-Eq $script:Asyncs.Count 0 'tek kurulum: onaydan önce iş başlamaz'
& $script:Confirms[0].OnOk
Assert-True ($script:Asyncs.Count -eq 1 -and $script:Asyncs[0].Name -eq 'PrepInstall' -and $script:Asyncs[0].Entry -eq 'Job_PrepInstall' -and @($script:Asyncs[0].Params.Ids).Count -eq 1 -and $script:Asyncs[0].Params.Ids[0] -eq 'Microsoft.VCRedist.2015+.x64' -and $script:Asyncs[0].Label -eq 'Bileşenler kuruluyor') 'tek kurulum: onaydan sonra iş yalnızca o kimlikle başlar'
# tamamlanınca durum sıfırlanır ve liste yenilenir (yeniden okuma)
$a = $script:Asyncs[0]
Reset-Fake
& $a.OnDone @{ Ok = $true; Done = 1; Failed = 0; Reboot = $false; Items = @() }
Assert-True ((Get-LastToast).K -eq 'good' -and (Get-LastToast).T -eq '1 bileşen kuruldu.') 'tek kurulum: bitiş bildirimi'
Assert-True ($null -eq $script:PrepState -or $script:Asyncs.Count -eq 1) 'tek kurulum: durum sıfırlanır, denetim yeniden başlar'
Assert-True ($script:Asyncs.Count -eq 1 -and $script:Asyncs[0].Entry -eq 'Job_PrepCheck') 'tek kurulum: sekme açıkken doğrulama için denetim yeniden çalışır'

# hepsini gider
$script:PrepLoading = $false
$script:PrepState = $s
Reset-Fake
Render-SlPrep
$rows = @(Get-RowsOf $ui.sl_List)
$all2 = $rows[0]
Assert-Eq $all2.Tag.Do 'FixAll' 'hepsini gider: özet satırının eylemi'
Reset-Fake
Invoke-PrepAction $all2.Tag
Assert-Eq $script:Confirms.Count 1 'hepsini gider: onay açıldı'
Assert-True ($script:Confirms[0].Text -match 'x64' -and $script:Confirms[0].Text -match 'x86' -and $script:Confirms[0].Text -match 'DirectX' -and $script:Confirms[0].Text -notmatch '.NET 10') 'hepsini gider: eksik paketlerin hepsi yazılır'
& $script:Confirms[0].OnOk
Assert-Eq (@($script:Asyncs[0].Params.Ids) -join ',') 'Microsoft.VCRedist.2015+.x64,Microsoft.VCRedist.2015+.x86,Microsoft.DirectX' 'hepsini gider: iş, listedeki tüm kimliklerle başlar'
# araç çubuğu düğmesi
$script:PrepLoading = $false
$script:PrepState = $s
Render-SlPrep
Init-SlPrep
Assert-True ($ui.sl_PrCheck.Handlers.Count -eq 1 -and $ui.sl_PrFix.Handlers.Count -eq 1) 'başlatma: düğmeler bağlandı'
Reset-Fake
& $ui.sl_PrFix.Handlers[0] $null $null
Assert-True ($script:Confirms.Count -eq 1 -and $script:Confirms[0].Title -eq 'Eksik bileşenleri kur') 'Eksikleri gider düğmesi onay açar'
# kurulacak bir şey yokken
$script:PrepState = New-St
Render-SlPrep
Reset-Fake
Start-PrepFixAll
Assert-True ($script:Confirms.Count -eq 0 -and (Get-LastToast).K -eq 'info' -and (Get-LastToast).T -match 'eksik bileşen yok') 'Eksikleri gider: eksik yoksa onay açılmaz'
# denetim sürerken
$script:PrepState = $null
Reset-Fake
Start-PrepFixAll
Assert-True ($script:Confirms.Count -eq 0 -and (Get-LastToast).K -eq 'warn') 'Eksikleri gider: denetim bitmeden çalışmaz'
$script:PrepState = @{ Failed = $true }
Reset-Fake
Start-PrepFixAll
Assert-True ($script:Confirms.Count -eq 0 -and (Get-LastToast).K -eq 'warn') 'Eksikleri gider: denetim başarısızsa çalışmaz'
# Denetle düğmesi
$script:PrepLoading = $false
$script:PrepState = New-St
Reset-Fake
& $ui.sl_PrCheck.Handlers[0] $null $null
Assert-True ($null -eq $script:PrepState -and $script:Asyncs.Count -eq 1 -and $script:Asyncs[0].Entry -eq 'Job_PrepCheck') 'Denetle düğmesi durumu sıfırlar ve yeniden okur'

# izin listesi dışı paket onay penceresine bile ulaşmaz
Reset-Fake
Invoke-PrepAction @{ Do = 'Winget'; Id = 'Evil.Package'; Name = 'Kötü' }
Assert-True ($script:Confirms.Count -eq 1 -and $script:Confirms[0].Message -eq $true -and $script:Confirms[0].Title -eq 'Bu bileşen kurulamaz' -and $script:Confirms[0].Text -match 'izin listesinde değil' -and $script:Asyncs.Count -eq 0) 'eylem: listede olmayan paket için onay yerine ileti çıkar'
Reset-Fake
Invoke-PrepAction @{ Do = 'Winget'; Id = 'Microsoft.DirectX --source x'; Name = 'x' }
Assert-True ($script:Confirms.Count -eq 1 -and $script:Confirms[0].Message -eq $true -and $script:Asyncs.Count -eq 0) 'eylem: bağımsız değişken sızdırmaya çalışan kimlik reddedilir'
Reset-Fake
Start-PrepInstall @()
Assert-True ((Get-LastToast).K -eq 'info' -and $script:Confirms.Count -eq 0) 'eylem: boş liste'
Start-PrepInstall $null
Assert-True ($script:Confirms.Count -eq 0) 'eylem: null liste'

# öteki eylemler
Reset-Fake
Invoke-PrepAction @{ Do = 'Url'; Url = 'ms-settings:windowsupdate' }
Assert-Eq (@($script:Opened) -join ',') 'url:ms-settings:windowsupdate' 'eylem: adres açılır'
Reset-Fake
Invoke-PrepAction @{ Do = 'Page'; Page = 'clean'; Sub = '' }
Assert-Eq (@($script:Opened) -join ',') 'page:clean/' 'eylem: sayfa açılır'
Reset-Fake
Invoke-PrepAction @{ Do = '' }
Invoke-PrepAction $null
Invoke-PrepAction @{ Do = 'Bilinmeyen' }
Assert-True ($script:Opened.Count -eq 0 -and $script:Confirms.Count -eq 0 -and $script:Asyncs.Count -eq 0) 'eylem: boş ve bilinmeyen eylem hiçbir şey yapmaz'

# WMI eylemi
Reset-Fake
Invoke-PrepAction @{ Do = 'Wmi' }
Assert-True ($script:Confirms.Count -eq 1 -and $script:Confirms[0].Title -eq 'WMI deposunu doğrula ve onar' -and $script:Confirms[0].Text -match 'salvagerepository' -and $script:Confirms[0].Text -match 'yeniden başlatma gerekmez') 'WMI eylemi: onay metni ne yapılacağını söyler'
Assert-Eq $script:Asyncs.Count 0 'WMI eylemi: onaydan önce iş yok'
& $script:Confirms[0].OnOk
Assert-True ($script:Asyncs.Count -eq 1 -and $script:Asyncs[0].Name -eq 'PrepWmi' -and $script:Asyncs[0].Entry -eq 'Job_PrepWmi') 'WMI eylemi: onaydan sonra iş başlar'
$a = $script:Asyncs[0]
$script:PrepState = New-St
$script:PrepLoading = $false
Reset-Fake
& $a.OnDone @{ Ok = $true; Text = 'WMI deposu onarıldı; sorgular çalışıyor.' }
Assert-True ((Get-LastToast).K -eq 'good' -and (Get-LastToast).T -match 'onarıldı' -and $script:Asyncs.Count -eq 1) 'WMI sonucu: başarı bildirimi, denetim yeniden başlar'
$script:PrepLoading = $false
Reset-Fake
Complete-PrepWmi @{ Ok = $false; Text = 'WMI deposu onarılamadı (winmgmt çıkış kodu 5).' }
Assert-True ((Get-LastToast).K -eq 'bad' -and (Get-LastToast).T -match 'çıkış kodu 5') 'WMI sonucu: hata bildirimi'
Complete-PrepWmi $null
Assert-True ((Get-LastToast).K -eq 'bad' -and (Get-LastToast).T -match 'günlüğe bakın') 'WMI sonucu: boş sonuç'
Complete-PrepWmi @{ Ok = $true }
Assert-True ((Get-LastToast).K -eq 'good' -and (Get-LastToast).T -eq 'WMI denetimi tamamlandı.') 'WMI sonucu: metinsiz başarı'

# başka sayfa ya da sekmedeyken liste çizilmez
$script:PrepLoading = $false
$script:UiState = @{ Page = 'tools'; Mode = 'Kullanici' }
$ui.sl_List.Children.Clear()
Reset-Fake
Complete-PrepInstall @{ Ok = $true; Done = 1; Failed = 0; Items = @() }
Assert-True ($ui.sl_List.Children.Count -eq 0 -and $script:Asyncs.Count -eq 0 -and $null -eq $script:PrepState) 'tamamlanma: başka sayfadayken çizilmez, durum yine de sıfırlanır'
$script:UiState = @{ Page = 'solve'; Mode = 'Kullanici' }
$script:SlTab = 'scan'
Complete-PrepInstall @{ Ok = $true; Done = 1; Failed = 0; Items = @() }
Assert-Eq $ui.sl_List.Children.Count 0 'tamamlanma: başka sekmedeyken çizilmez'
$script:SlTab = 'prep'

# kullanıcı / uzman kipi geçişi
$script:PrepState = New-St
Render-SlPrep
Assert-Eq (@(@(Get-RowsOf $ui.sl_List | ForEach-Object { $_.Vars.Detail }) -match 'Release anahtarı').Count) 0 'kip: kullanıcı kipinde ham değer yok'
$script:UiState = @{ Page = 'solve'; Mode = 'Expert' }
$script:PcRenders = 0
Update-PageMode_solve
Assert-True ((@(Get-RowsOf $ui.sl_List | ForEach-Object { $_.Vars.Detail }) -match 'Release anahtarı').Count -ge 1 -and $script:PcRenders -eq 0) 'kip: uzman kipine geçince Hazırlık yeniden çizilir'
$script:PrepState = $null
$ui.sl_List.Children.Clear()
Update-PageMode_solve
Assert-Eq $ui.sl_List.Children.Count 0 'kip: durum yokken çizim tetiklenmez'
$script:SlTab = 'pc'
$script:PcInfo = @{ Ok = $true }
Update-PageMode_solve
Assert-Eq $script:PcRenders 1 'kip: Bilgisayarım sekmesi eskisi gibi çizilir'
$script:SlTab = 'prep'
$script:UiState = @{ Page = 'tools'; Mode = 'Expert' }
$script:PcRenders = 0
Update-PageMode_solve
Assert-Eq $script:PcRenders 0 'kip: başka sayfadayken hiçbir şey çizilmez'

Show-Result
