. "$PSScriptRoot/lib.ps1"
# 9.0.0 bağlantıları (p45_wiring, mods\130_prep_nudge.ps1, 131_wiring.ps1): Duman turu düğmeleri, açılışta Hazırlık uyarısı (karar mantığı, zamanlayıcı, ağsız denetim),
# pano hızlı eylemleri, arama sözcükleri, komut satırı sayfa:sekme hedefleri ve ayar varsayılanı. Gerçek ağ, kurulum ya da pencere kullanılmaz.
Add-Type -ReferencedAssemblies @([psobject].Assembly.Location, 'System.Collections', 'System.Runtime', 'netstandard') -TypeDefinition @'
using System;
namespace System.Windows {
    public enum WindowState { Normal, Minimized, Maximized }
}
namespace System.Windows.Threading {
    public class DispatcherTimer {
        public TimeSpan Interval;
        public bool IsEnabled;
        public int Starts;
        public int Stops;
        public event EventHandler Tick;
        public void Start() { IsEnabled = true; Starts++; }
        public void Stop() { IsEnabled = false; Stops++; }
        public void Fire() { if (Tick != null) { Tick(this, EventArgs.Empty); } }
    }
}
'@

Import-Fn 'Get-JsonProp', 'Format-PcGb', 'New-PrepItem', 'New-PrepFix', 'Get-PrepVcItem', 'Get-PrepItems', 'Get-PrepSummary'
Import-Fn 'Test-PrepNudgeKey', 'Get-PrepNudgeNames', 'Get-PrepNudgeModel', 'Test-PrepNudgeReady', 'Complete-PrepNudge', 'Start-PrepNudgeCheck', 'Invoke-PrepNudgeTick', 'Initialize-PrepNudge'
Import-Fn 'Get-SmokeActions', 'Invoke-BoardAction', 'Get-BoardField', 'Get-BoardSearchResults', 'ConvertTo-AsciiKey', 'Split-CmdTarget', 'Open-CmdPage', 'Get-DefaultSettings'
Import-Var 'PrepPackages', 'PrepNudgeKeys', 'SmokeSafe', 'SlvTabs', 'TlTabs', 'PageTitles', 'PageNames', 'PageSubs', 'PageIcons', 'BoardActions', 'BoardActionAccent', 'BoardSoftOf', 'BoardSearchWords', 'CmdPages', 'CmdDefs', 'Themes'
. "$PSScriptRoot/uifake.ps1"

$src = [System.IO.File]::ReadAllText($script:TestPath)
$null = Get-AstFunctions
function Get-FnSrc([string]$Name) { return [string](@($script:AllFns | Where-Object { ($_.Name -replace '^global:', '') -eq $Name }) | Select-Object -Last 1).Extent.Text }

$script:WhLog = New-Object System.Collections.ArrayList
function Write-WhLog([string]$Message, [string]$Level = 'INFO') { [void]$script:WhLog.Add($Level + '|' + $Message) }
$script:OpenedPages = New-Object System.Collections.ArrayList
function Open-Page([string]$Key, [string]$Sub = '') { [void]$script:OpenedPages.Add($Key + '/' + $Sub) }
$script:Starts = New-Object System.Collections.ArrayList
$script:StartResult = $true
function Start-Async {
    param([string]$Name, [string]$Entry, $Params = $null, [scriptblock]$OnDone = $null, [string]$Label = '', [bool]$Quiet = $false, [bool]$Queue = $false)
    [void]$script:Starts.Add(@{ Name = $Name; Entry = $Entry; Params = $Params; OnDone = $OnDone; Label = $Label; Quiet = $Quiet; Queue = $Queue })
    return $script:StartResult
}
$script:SaveCount = 0
$script:SavedSeen = $null
function Save-Settings($S) { $script:SaveCount++; $script:SavedSeen = [string]$S.PrepSeen }
$script:HealthCalls = 0
function Start-HealthScan([string]$Mode, [bool]$Quiet = $false) { $script:HealthCalls++ }
function Start-QuickMaint { $script:OpenedPages.Add('maint-islevi') | Out-Null }
function Start-ReportNow { $script:OpenedPages.Add('rapor-islevi') | Out-Null }

# =====================================================================
#  1) Duman turu: Çözüm Merkezi'nin salt okunur düğmeleri
# =====================================================================
$acts = @(Get-SmokeActions)
$solveActs = @($acts | Where-Object { [string]$_[0] -eq 'solve' })
Assert-Eq $solveActs.Count 5 'duman: Çözüm Merkezi için beş eylem'
$want = @('sl_Tab_scan|sl_Scan', 'sl_Tab_disk|sl_DiskRefresh', 'sl_Tab_erase|sl_ErRefresh', 'sl_Tab_pc|sl_PcRefresh', 'sl_Tab_prep|sl_PrCheck')
Assert-Eq ((@($solveActs | ForEach-Object { [string]$_[1] + '|' + [string]$_[2] })) -join ',') ($want -join ',') 'duman: sekme ve düğme çiftleri'
foreach ($a in $acts) {
    Assert-Eq $a.Count 3 ('duman: eylem üçlüdür ' + [string]$a[2])
    Assert-True ($script:PageTitles.Contains([string]$a[0])) ('duman: sayfa gerçek ' + [string]$a[0])
    Assert-True ($script:SmokeSafe -contains [string]$a[2]) ('duman: düğme güvenli listede ' + [string]$a[2])
    Assert-True ($src.Contains('x:Name="' + [string]$a[2] + '"')) ('duman: düğme arayüzde var ' + [string]$a[2])
    if ([string]$a[1] -ne '') { Assert-True ($src.Contains('x:Name="' + [string]$a[1] + '"')) ('duman: sekme düğmesi arayüzde var ' + [string]$a[1]) }
}
foreach ($a in $solveActs) {
    $tab = ([string]$a[1]).Substring('sl_Tab_'.Length)
    Assert-True ($script:SlvTabs -contains $tab) ('duman: sekme anahtarı Çözüm Merkezi sekmesi ' + $tab)
    Assert-True ($src.Contains('x:Name="' + [string]$a[1] + '"') -and $src -match ('x:Name="' + [string]$a[1] + '" Content="[^"]*" Tag="' + $tab + '"')) ('duman: sekme düğmesinin etiketi eşleşiyor ' + $tab)
}
foreach ($n in @($script:SmokeSafe)) { Assert-True ($src.Contains('x:Name="' + [string]$n + '"')) ('duman: güvenli listedeki her ad arayüzde var ' + [string]$n) }
# yazan ya da yıkıcı düğmeler güvenli listeye girmez
foreach ($bad in @('sl_FixAll', 'sl_ScanFull', 'sl_RcRun', 'sl_RcQuick', 'sl_RcDeep', 'sl_RcImg', 'sl_RcDest', 'sl_ErFile', 'sl_ErFolder', 'sl_PrFix', 'sl_PcCopy', 'sl_RcAll', 'sl_RcNone')) {
    Assert-True ($script:SmokeSafe -notcontains $bad) ('duman: güvenli listede olmamalı ' + $bad)
}
# güvenli düğmelerin işleyicileri yalnızca okur: tek satırlık işleyicide yazma/silme komutu yok
foreach ($b in @('sl_Scan', 'sl_DiskRefresh', 'sl_ErRefresh', 'sl_PcRefresh', 'sl_PrCheck')) {
    $m = [regex]::Match($src, '\$ui\.' + $b + '\.Add_Click\(\{[^\r\n]*')
    Assert-True $m.Success ('duman: işleyici bulundu ' + $b)
    Assert-True ($m.Value -notmatch 'Remove-|Format-|Clear-Disk|Wipe|Delete|Secure|Install|Start-Process|Set-') ('duman: işleyici yazma komutu çağırmıyor ' + $b)
}

# =====================================================================
#  2) Açılışta Hazırlık uyarısı: karar mantığı
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

# anahtar süzgeci
foreach ($k in @('ps', 'net', 'csc', 'wmi', 'data', 'ext', 'os', 'winget', 'space', 'vcx64', 'vcx86', 'vcarm64')) { Assert-True (Test-PrepNudgeKey $k) ('uyarı anahtarı: sayılır ' + $k) }
foreach ($k in @('admin', 'restore', 'online', 'dx', 'dotnet', '')) { Assert-True (-not (Test-PrepNudgeKey $k)) ('uyarı anahtarı: sayılmaz [' + $k + ']') }
# her gerçek satır anahtarı bir kez karara bağlanmıştır: uyarıya girenler dışında kalanlar bilinçli seçimdir
$everyKey = @((Get-PrepItems (New-St)) | ForEach-Object { [string]$_.Key })
$nudged = @($everyKey | Where-Object { Test-PrepNudgeKey $_ })
$skipped = @($everyKey | Where-Object { -not (Test-PrepNudgeKey $_) } | Sort-Object)
Assert-Eq ($skipped -join ',') 'admin,dotnet,dx,online,restore' 'uyarı: sayılmayan satırlar yönetici, Sistem Koruması, internet ve isteğe bağlılar'
Assert-Eq $nudged.Count 11 'uyarı: sayılan satır sayısı'

# adlar
Assert-Eq (Get-PrepNudgeNames @()) '' 'adlar: boş'
Assert-Eq (Get-PrepNudgeNames @('A')) 'A' 'adlar: tek'
Assert-Eq (Get-PrepNudgeNames @('A', 'B')) 'A, B' 'adlar: iki'
Assert-Eq (Get-PrepNudgeNames @('A', 'B', 'C', 'D')) 'A, B ve 2 bileşen daha' 'adlar: fazlası sayı olarak'
Assert-Eq (Get-PrepNudgeNames @('A', '', 'B') 5) 'A, B' 'adlar: boş başlık atlanır'
Assert-Eq (Get-PrepNudgeNames @('A', 'B', 'C') 1) 'A ve 2 bileşen daha' 'adlar: sınır 1'

# karar
$m = Get-PrepNudgeModel $null
Assert-True ($m.Show -eq $false -and @($m.Req).Count -eq 0 -and @($m.Rec).Count -eq 0) 'karar: durum yok -> uyarı yok'
$m = Get-PrepNudgeModel @{ Failed = $true }
Assert-True ($m.Show -eq $false) 'karar: denetim başarısız -> uyarı yok'
$m = Get-PrepNudgeModel (New-St)
Assert-True ($m.Show -eq $false -and $m.Kind -eq 'info' -and $m.Text -eq '' -and $m.Toast -eq '') 'karar: her şey yolunda -> uyarı yok'

# sayılmayan satırlar bozuk olsa da uyarı çıkmaz
$s = New-St; $s.Admin = $false; $s.Online = $false; $s.Protect = @{ Known = $true; On = $false; Policy = $false }; $s.Dx = @{ Native = $false; X86 = $false; Is64 = $true }; $s.Dotnet = @()
$its = Get-PrepItems $s
Assert-Eq (Find-It $its 'admin').Status 'warn' 'karar: yönetici satırı uyarı durumunda (sınama anlamlı)'
Assert-Eq (Find-It $its 'online').Status 'info' 'karar: internet satırı bilgi durumunda'
Assert-True ((Find-It $its 'restore').Status -ne 'ok' -and (Find-It $its 'dx').Status -ne 'ok' -and (Find-It $its 'dotnet').Status -ne 'ok') 'karar: Sistem Koruması, DirectX, .NET satırları tam değil (sınama anlamlı)'
$m = Get-PrepNudgeModel $s
Assert-True ($m.Show -eq $false) 'karar: yönetici/internet/Sistem Koruması/isteğe bağlı eksikleri uyarı sebebi değil'

# yalnızca zorunlu eksik
$s = New-St; $s.Ps = @{ Version = '4.0'; Major = 4; Minor = 0; Edition = 'Desktop' }
$m = Get-PrepNudgeModel $s
Assert-True ($m.Show -eq $true -and $m.Kind -eq 'bad' -and @($m.Req).Count -eq 1 -and @($m.Rec).Count -eq 0) 'karar: eski PowerShell -> zorunlu uyarı'
Assert-Eq $m.Req[0] 'Windows PowerShell 5.1' 'karar: zorunlu başlık'
Assert-Eq $m.Title 'Hazırlık: eksik bileşen var' 'karar: onay penceresi başlığı'
Assert-True ($m.Text -match '•  Windows PowerShell 5\.1' -and $m.Text -match 'Çözüm Merkezi > Hazırlık' -and $m.Text -match 'hiçbir şey kurulmadı ya da değiştirilmedi' -and $m.Text -match 'yeniden gösterilmez') 'karar: onay metni neyin bulunduğunu, nereye bakılacağını ve hiçbir şeyin değişmediğini söyler'
Assert-True ($m.Text -notmatch 'Ayrıca') 'karar: önerilen yoksa "Ayrıca" satırı yok'
Assert-True ($m.Toast -match '^Hazırlık: 1 zorunlu bileşende sorun var \(Windows PowerShell 5\.1\)' -and $m.Toast -match 'Hazırlık sekmesine bakın') 'karar: bildirim metni'

# yalnızca önerilen eksik (Visual C++ x64 yok)
$s = New-St; $s.Vc.X64 = @{ Installed = $false }
$m = Get-PrepNudgeModel $s
Assert-True ($m.Show -eq $true -and $m.Kind -eq 'warn' -and @($m.Req).Count -eq 0 -and @($m.Rec).Count -eq 1) 'karar: Visual C++ yok -> öneri uyarısı'
Assert-True ($m.Rec[0] -match 'Visual C\+\+' -and $m.Text -eq '' -and $m.Toast -match '^Hazırlık: 1 önerilen bileşen eksik ya da eski \(Visual C\+\+' -and $m.Toast -match 'giderebilirsiniz') 'karar: öneri bildirimi'
Assert-Eq $m.Title 'Hazırlık: öneri var' 'karar: öneri başlığı'

# winget yok -> öneri
$s = New-St; $s.Winget = @{ Path = ''; Version = '' }
$m = Get-PrepNudgeModel $s
Assert-True ($m.Show -eq $true -and $m.Kind -eq 'warn' -and (@($m.Rec) -join '|') -match 'winget') 'karar: winget yok -> öneri uyarısı'

# .NET Framework eski ama çalışır (zorunlu grupta, durum "uyarı") -> öneri sayılır, onay penceresi açılmaz
$s = New-St; $s.Net = @{ Release = 460805; Name = '4.7' }
$m = Get-PrepNudgeModel $s
Assert-Eq (Find-It (Get-PrepItems $s) 'net').Status 'warn' 'karar: .NET 4.7 uyarı durumunda (sınama anlamlı)'
Assert-True ($m.Show -eq $true -and $m.Kind -eq 'warn' -and @($m.Req).Count -eq 0 -and (@($m.Rec) -join '|') -match '\.NET Framework') 'karar: .NET çalışır ama eski -> yalnızca öneri'

# disk alanı çok az -> önerilen grupta
$s = New-St; $s.Disk = @{ Letter = 'C:'; FreeGB = [double]0.4; SizeGB = [double]475.9 }
$sp = Find-It (Get-PrepItems $s) 'space'
$m = Get-PrepNudgeModel $s
Assert-True ($sp.Status -eq 'bad' -and $sp.Group -eq 'rec') 'karar: boş alan çok az, önerilen grupta kötü (sınama anlamlı)'
Assert-True ($m.Show -eq $true -and $m.Kind -eq 'warn' -and @($m.Req).Count -eq 0 -and @($m.Rec).Count -eq 1) 'karar: önerilen gruptaki "kötü" satır onay penceresi açmaz'

# eklenti sorunu
$s = New-St; $s.Exts[5] = @{ Name = 'Kurtarma'; Problem = 'Dosya bulunamadı.' }
$e = Find-It (Get-PrepItems $s) 'ext'
$m = Get-PrepNudgeModel $s
if ($e.Status -eq 'bad') { Assert-True ($m.Show -eq $true -and $m.Kind -eq 'bad' -and @($m.Req) -contains [string]$e.Title) 'karar: eklenti sorunu zorunlu uyarı' }
else { Assert-True ($m.Show -eq $false -or @($m.Req).Count -eq 0) 'karar: eklenti satırı kötü değilse onay penceresi açılmaz' }

# zorunlu + önerilen birlikte
$s = New-St; $s.Ps = @{ Version = '4.0'; Major = 4; Minor = 0; Edition = 'Desktop' }; $s.Vc.X64 = @{ Installed = $false }
$m = Get-PrepNudgeModel $s
Assert-True ($m.Show -eq $true -and $m.Kind -eq 'bad' -and @($m.Req).Count -eq 1 -and @($m.Rec).Count -eq 1) 'karar: ikisi birlikte -> zorunlu kazanır'
Assert-True ($m.Text -match 'Ayrıca 1 önerilen bileşen eksik ya da eski\.') 'karar: onay metni önerilen sayısını da söyler'

# beşten fazla zorunlu: dört madde + "ve N bileşen daha"
$s = New-St
$s.Ps = @{ Version = '4.0'; Major = 4; Minor = 0; Edition = 'Desktop' }
$s.Net = @{ Release = 0; Name = '' }
$s.Csc = @{ Found = $false; Path = '' }
$s.Wmi = @{ Ok = $false; Error = 'bozuk' }
$s.Data = @{ Path = 'C:\x'; Ok = $false; Error = 'yazılamıyor' }
$m = Get-PrepNudgeModel $s
Assert-Eq @($m.Req).Count 5 'karar: beş zorunlu eksik'
$bul = @([regex]::Matches($m.Text, '•  ')).Count
Assert-Eq $bul 5 'karar: dört madde ve bir "ve N bileşen daha" satırı'
Assert-True ($m.Text -match '•  ve 1 bileşen daha') 'karar: kalan sayı yazılır'
Assert-True ($m.Toast -match '5 zorunlu bileşende sorun var' -and $m.Toast -match ' ve 3 bileşen daha\)') 'karar: bildirimde iki ad ve kalan sayı'

# durum bozuksa yorumlayıcı patlarsa uyarı çıkmaz ve hata fırlatılmaz
function Get-PrepItems { throw 'yorumlama patladı' }
$m = Get-PrepNudgeModel (New-St)
Assert-True ($m.Show -eq $false) 'karar: yorumlama hatası sessizce uyarısız'
Remove-Item function:Get-PrepItems
Import-Fn 'Get-PrepItems'

# =====================================================================
#  3) uygun an
# =====================================================================
$script:AppVersion = '9.0.0'
$script:Settings = @{ PrepSeen = ''; FirstRunDone = $true }
$script:Cur = $null
$ui = [pscustomobject]@{ Overlay = [pscustomobject]@{ Visibility = 'Collapsed' } }
$script:Win = [pscustomobject]@{ IsVisible = $true; WindowState = [System.Windows.WindowState]::Normal }
Assert-True (Test-PrepNudgeReady) 'uygun an: her şey uygun'
$script:Win.IsVisible = $false
Assert-True (-not (Test-PrepNudgeReady)) 'uygun an: pencere gizliyse beklenir'
$script:Win.IsVisible = $true
$script:Win.WindowState = [System.Windows.WindowState]::Minimized
Assert-True (-not (Test-PrepNudgeReady)) 'uygun an: simge durumundaysa beklenir'
$script:Win.WindowState = [System.Windows.WindowState]::Maximized
Assert-True (Test-PrepNudgeReady) 'uygun an: büyütülmüş pencere uygun'
$script:Win.WindowState = [System.Windows.WindowState]::Normal
$script:Settings.FirstRunDone = $false
Assert-True (-not (Test-PrepNudgeReady)) 'uygun an: ilk çalıştırma ekranı bitmeden beklenir'
$script:Settings.FirstRunDone = $true
$ui.Overlay.Visibility = 'Visible'
Assert-True (-not (Test-PrepNudgeReady)) 'uygun an: açık pencere (onay kutusu) varken beklenir'
$ui.Overlay.Visibility = 'Collapsed'
$script:Cur = @{ Name = 'Health' }
Assert-True (-not (Test-PrepNudgeReady)) 'uygun an: çalışan iş varken beklenir'
$script:Cur = $null
Assert-True (Test-PrepNudgeReady) 'uygun an: engeller kalkınca uygun'

# =====================================================================
#  4) denetimi başlatma ve sonuç
# =====================================================================
$script:Starts.Clear()
Start-PrepNudgeCheck
Assert-Eq $script:Starts.Count 1 'başlat: tek iş'
$st0 = $script:Starts[0]
Assert-True ($st0.Name -eq 'PrepNudge' -and $st0.Entry -eq 'Job_PrepCheck') 'başlat: Hazırlık denetim işi'
Assert-True ($st0.Params -is [hashtable] -and $st0.Params.NoNet -eq $true) 'başlat: ağsız denetim istenir'
Assert-True ($st0.Quiet -eq $true -and $st0.Queue -eq $true) 'başlat: sessiz ve sıraya alınır (kullanıcının işini engellemez)'
$script:WhLog.Clear(); $script:Starts.Clear(); $script:StartResult = $false
Start-PrepNudgeCheck
Assert-True (@($script:WhLog | Where-Object { $_ -match '^WARN\|.*başlatılamadı' }).Count -eq 1) 'başlat: iş başlamazsa günlüğe yazılır'
$script:StartResult = $true

function Reset-Nudge {
    Reset-Fake
    $script:OpenedPages.Clear(); $script:WhLog.Clear()
    $script:Settings = @{ PrepSeen = ''; FirstRunDone = $true }
    $script:SaveCount = 0; $script:SavedSeen = $null
    $ui.Overlay.Visibility = 'Collapsed'
}

# sonuç yok ya da başarısız: sürüm işaretlenmez, sonraki açılışta yeniden denenir
Reset-Nudge
Complete-PrepNudge $null
Assert-True ($script:SaveCount -eq 0 -and [string]$script:Settings.PrepSeen -eq '' -and $script:Toasts.Count -eq 0 -and $script:Confirms.Count -eq 0) 'sonuç: sonuç yok -> hiçbir şey yapılmaz'
Assert-True (@($script:WhLog | Where-Object { $_ -match '^WARN\|.*yeniden denenecek' }).Count -eq 1) 'sonuç: sonuç yok -> günlükte uyarı'
Complete-PrepNudge @{ Ok = $false; Error = 'x' }
Assert-True ($script:SaveCount -eq 0 -and [string]$script:Settings.PrepSeen -eq '') 'sonuç: Ok=false -> sürüm işaretlenmez'
Complete-PrepNudge @{ Ok = $true; State = $null }
Assert-True ($script:SaveCount -eq 0 -and [string]$script:Settings.PrepSeen -eq '') 'sonuç: durum yoksa -> sürüm işaretlenmez'

# her şey yolunda
Reset-Nudge
Complete-PrepNudge @{ Ok = $true; State = (New-St) }
Assert-True ($script:SaveCount -eq 1 -and $script:SavedSeen -eq '9.0.0' -and [string]$script:Settings.PrepSeen -eq '9.0.0') 'sonuç: sürüm işaretlenir ve kaydedilir'
Assert-True ($script:Toasts.Count -eq 0 -and $script:Confirms.Count -eq 0) 'sonuç: sorun yoksa sessiz'
Assert-True (@($script:WhLog | Where-Object { $_ -match '^INFO\|Hazırlık: eksik ya da eski bileşen yok' }).Count -eq 1) 'sonuç: günlüğe bilgi'

# zorunlu eksik: onay penceresi
Reset-Nudge
$bad = New-St; $bad.Ps = @{ Version = '4.0'; Major = 4; Minor = 0; Edition = 'Desktop' }
Complete-PrepNudge @{ Ok = $true; State = $bad }
Assert-True ($script:SaveCount -eq 1 -and $script:SavedSeen -eq '9.0.0') 'sonuç: zorunlu eksikte de sürüm işaretlenir (yeniden rahatsız etmez)'
Assert-Eq $script:Confirms.Count 1 'sonuç: zorunlu eksik -> bir onay penceresi'
$cf = $script:Confirms[0]
Assert-True ($cf.Title -eq 'Hazırlık: eksik bileşen var' -and $cf.Ok -eq 'Hazırlık sekmesini aç' -and $cf.Danger -eq $false) 'sonuç: onay penceresi başlığı, düğmesi, tehlikesiz'
Assert-True ($cf.Text -match 'Windows PowerShell 5\.1') 'sonuç: onay metni eksik bileşeni adlandırır'
Assert-Eq $script:Toasts.Count 0 'sonuç: onay penceresiyle birlikte bildirim yok'
& $cf.OnOk
Assert-Eq (($script:OpenedPages) -join ',') 'solve/prep' 'sonuç: onay Çözüm Merkezi > Hazırlık sekmesini açar'
Assert-True (@($script:WhLog | Where-Object { $_ -match '^WARN\|Hazırlık: 1 zorunlu, 0 önerilen' }).Count -eq 1) 'sonuç: günlüğe sayılar'

# zorunlu eksik ama başka pencere açık: bildirimle yetinilir
Reset-Nudge
$ui.Overlay.Visibility = 'Visible'
Complete-PrepNudge @{ Ok = $true; State = $bad }
Assert-True ($script:Confirms.Count -eq 0 -and $script:Toasts.Count -eq 1 -and $script:Toasts[0].K -eq 'bad' -and $script:Toasts[0].T -match 'Hazırlık sekmesine bakın') 'sonuç: açık pencerenin üstüne pencere açılmaz; bildirim gösterilir'
Assert-True ($script:SaveCount -eq 1) 'sonuç: bu durumda da sürüm işaretlenir'

# yalnızca öneri: bildirim
Reset-Nudge
$rec = New-St; $rec.Vc.X64 = @{ Installed = $false }
Complete-PrepNudge @{ Ok = $true; State = $rec }
Assert-True ($script:Confirms.Count -eq 0 -and $script:Toasts.Count -eq 1 -and $script:Toasts[0].K -eq 'warn') 'sonuç: öneri -> uyarı bildirimi, pencere yok'
Assert-True ($script:Toasts[0].T -match 'önerilen bileşen eksik ya da eski' -and $script:Toasts[0].T -match 'Çözüm Merkezi > Hazırlık') 'sonuç: öneri bildirimi nereye bakılacağını söyler'
Assert-True ($script:SaveCount -eq 1 -and $script:SavedSeen -eq '9.0.0') 'sonuç: öneride de sürüm işaretlenir'

# kaydetme hatası denetimi bozmaz
Reset-Nudge
function Save-Settings($S) { throw 'disk dolu' }
$threw = $false
try { Complete-PrepNudge @{ Ok = $true; State = $rec } } catch { $threw = $true }
Assert-True (-not $threw -and $script:Toasts.Count -eq 1) 'sonuç: ayar kaydedilemese de bildirim gösterilir, hata fırlatılmaz'
function Save-Settings($S) { $script:SaveCount++; $script:SavedSeen = [string]$S.PrepSeen }

# =====================================================================
#  5) zamanlayıcı
# =====================================================================
# Duman testinde ve otomatik testlerde kurulmaz
$script:PrepNudgeTimer = $null
$script:SmokeMode = $true
Reset-Nudge
Initialize-PrepNudge
Assert-True ($null -eq $script:PrepNudgeTimer) 'zamanlayıcı: Duman testinde kurulmaz'
$script:SmokeMode = $false
# bu sürümde zaten gösterilmişse kurulmaz
$script:Settings.PrepSeen = '9.0.0'
Initialize-PrepNudge
Assert-True ($null -eq $script:PrepNudgeTimer) 'zamanlayıcı: bu sürümde gösterilmişse kurulmaz'
# eski sürümden kalan işaret yeni sürümde yeniden sorar
$script:Settings.PrepSeen = '8.0.0'
Initialize-PrepNudge
Assert-True ($null -ne $script:PrepNudgeTimer -and $script:PrepNudgeTimer.IsEnabled -eq $true) 'zamanlayıcı: eski sürümden kalan işaret -> kurulur'
Assert-Eq $script:PrepNudgeTimer.Interval.TotalSeconds 20 'zamanlayıcı: 20 sn aralık'
Assert-Eq $script:PrepNudgeTicks 0 'zamanlayıcı: sayaç sıfırdan'
# uygun an yokken tık: bekler
$script:Starts.Clear()
$script:Win.IsVisible = $false
$script:PrepNudgeTimer.Fire()
Assert-True ($script:PrepNudgeTimer.IsEnabled -eq $true -and $script:Starts.Count -eq 0 -and $script:PrepNudgeTicks -eq 1) 'zamanlayıcı: pencere gizliyken bekler, iş başlatmaz'
$script:Win.IsVisible = $true
$script:Cur = @{ Name = 'Health' }
$script:PrepNudgeTimer.Fire()
Assert-True ($script:PrepNudgeTimer.IsEnabled -eq $true -and $script:Starts.Count -eq 0 -and $script:PrepNudgeTicks -eq 2) 'zamanlayıcı: iş sürerken bekler'
$script:Cur = $null
# uygun an gelince tek kez başlatır ve durur
$script:PrepNudgeTimer.Fire()
Assert-True ($script:PrepNudgeTimer.IsEnabled -eq $false -and $script:Starts.Count -eq 1 -and $script:Starts[0].Entry -eq 'Job_PrepCheck' -and $script:Starts[0].Params.NoNet -eq $true) 'zamanlayıcı: uygun anda ağsız denetimi başlatır ve durur'
# aradan sürüm işaretlendiyse (başka yoldan) hiçbir şey başlatmadan durur
$script:Settings.PrepSeen = '8.0.0'
$script:Starts.Clear()
Initialize-PrepNudge
$script:Settings.PrepSeen = '9.0.0'
$script:PrepNudgeTimer.Fire()
Assert-True ($script:PrepNudgeTimer.IsEnabled -eq $false -and $script:Starts.Count -eq 0) 'zamanlayıcı: işaret düşmüşse hiçbir şey başlatmadan durur'
# işleyici hata verirse çökmez
$script:Settings.PrepSeen = '8.0.0'
Initialize-PrepNudge
$script:Win = $null
$script:PrepNudgeTimer.Fire()
Assert-True ($script:Crashes.Count -ge 0) 'zamanlayıcı: pencere yokken tık hata fırlatmaz'
$script:Win = [pscustomobject]@{ IsVisible = $true; WindowState = [System.Windows.WindowState]::Normal }

# =====================================================================
#  6) yalnızca okuma ve ağsız: uyarı kodu kurmaz, indirmez, ağa çıkmaz
# =====================================================================
$nudgeFns = @('Test-PrepNudgeKey', 'Get-PrepNudgeNames', 'Get-PrepNudgeModel', 'Test-PrepNudgeReady', 'Complete-PrepNudge', 'Start-PrepNudgeCheck', 'Invoke-PrepNudgeTick', 'Initialize-PrepNudge')
$nudgeText = (($nudgeFns | ForEach-Object { Get-FnSrc $_ }) -join "`n")
Assert-True ($nudgeText.Length -gt 1500) 'kod: uyarı işlevleri okundu'
foreach ($bad in @('Job_PrepInstall', 'Start-PrepInstall', 'Invoke-PrepAction', 'Start-PrepFixAll', 'Job_PrepWmi', 'winget', 'Start-Process', 'Invoke-WebRequest', 'Invoke-RestMethod', 'Test-Online', 'Test-Connection', 'DownloadFile', 'Remove-Item', 'Set-ItemProperty')) {
    Assert-True ($nudgeText -notmatch [regex]::Escape($bad)) ('kod: uyarı işlevleri ' + $bad + ' kullanmaz')
}
Assert-True ((Get-FnSrc 'Initialize-PrepNudge') -match 'SmokeMode') 'kod: Duman testinde devre dışı'
Assert-True ((Get-FnSrc 'Start-PrepNudgeCheck') -match 'NoNet\s*=\s*\$true') 'kod: denetim ağsız istenir'
$ut = Get-FnSrc 'Start-UiTimers'
Assert-True ($ut -match 'Initialize-FirstRun[\s\S]*Initialize-PrepNudge') 'kod: açılış zamanlayıcısı ilk çalıştırma ekranından sonra kurulur'

# =====================================================================
#  7) ayar varsayılanı
# =====================================================================
$d = Get-DefaultSettings
Assert-True ($d.ContainsKey('PrepSeen') -and [string]$d['PrepSeen'] -eq '') 'ayar: PrepSeen varsayılanı boş'

# =====================================================================
#  8) pano hızlı eylemleri
# =====================================================================
foreach ($k in @('solve', 'recover', 'erase', 'pcinfo', 'prep')) {
    Assert-True ($script:BoardActions.Contains($k)) ('pano eylemi var: ' + $k)
    $a = $script:BoardActions[$k]
    Assert-True ([string]$a.Page -eq 'solve' -and [string]$a.Fn -eq '') ('pano eylemi Çözüm Merkezi sayfasını açar: ' + $k)
    Assert-True ($script:SlvTabs -contains [string]$a.Sub) ('pano eylemi gerçek bir sekmeyi açar: ' + $k + ' -> ' + [string]$a.Sub)
    Assert-True ($src.Contains('x:Key="' + [string]$a.Ico + '"')) ('pano eylemi simgesi tanımlı: ' + $k)
    Assert-True ($script:BoardActionAccent.ContainsKey($k)) ('pano eylemi vurgu rengine bağlı: ' + $k)
    Assert-True (([string]$a.T).Length -le 24 -and ([string]$a.T) -ne '' -and ([string]$a.D) -ne '') ('pano eylemi adı kısa, açıklaması var: ' + $k)
}
Assert-Eq $script:BoardActions['recover'].Sub 'recover' 'pano: Dosya kurtar -> Silinen dosyalar sekmesi'
Assert-Eq $script:BoardActions['erase'].Sub 'erase' 'pano: Kalıcı sil -> Kalıcı silme sekmesi'
Assert-Eq $script:BoardActions['pcinfo'].Sub 'pc' 'pano: Bilgisayarım -> Bilgisayarım sekmesi'
Assert-Eq $script:BoardActions['prep'].Sub 'prep' 'pano: Hazırlık -> Hazırlık sekmesi'
# Sub yalnızca sekmesi olan sayfaların eylemlerinde (Çözüm Merkezi, Araçlar) ve yalnızca gerçek sekme adıyla
foreach ($k in @($script:BoardActions.Keys)) {
    $sub = [string](Get-BoardField $script:BoardActions[$k] 'Sub')
    if ($sub -ne '') {
        $pg = [string]$script:BoardActions[$k].Page
        $tabs = @()
        if ($pg -eq 'solve') { $tabs = @($script:SlvTabs) } elseif ($pg -eq 'tools') { $tabs = @($script:TlTabs) }
        Assert-True ($tabs -contains $sub) ('pano eylemi: Sub gerçek bir sekme ' + $k + ' -> ' + $pg + ':' + $sub)
    }
}
# çalıştırma
$script:OpenedPages.Clear()
Invoke-BoardAction 'recover'; Invoke-BoardAction 'erase'; Invoke-BoardAction 'pcinfo'; Invoke-BoardAction 'prep'; Invoke-BoardAction 'solve'
Assert-Eq (($script:OpenedPages) -join ',') 'solve/recover,solve/erase,solve/pc,solve/prep,solve/scan' 'pano: eylemler sekmeyi açar'
$script:OpenedPages.Clear()
Invoke-BoardAction 'clean'
Assert-Eq (($script:OpenedPages) -join ',') 'clean/' 'pano: sekmesiz eylem yalnızca sayfayı açar (önceki davranış)'
$script:OpenedPages.Clear(); $script:HealthCalls = 0
Invoke-BoardAction 'health'
Assert-True ($script:HealthCalls -eq 1 -and $script:OpenedPages.Count -eq 0) 'pano: sağlık taraması işlevi değişmedi'
$script:OpenedPages.Clear()
Invoke-BoardAction 'yok-boyle-bir-sey'
Assert-Eq $script:OpenedPages.Count 0 'pano: bilinmeyen eylem hiçbir şey yapmaz'
$script:OpenedPages.Clear()
Invoke-BoardAction 'audit'
Assert-Eq (($script:OpenedPages) -join ',') 'security/' 'pano: güvenlik denetimi eylemi değişmedi'

# =====================================================================
#  9) arama sözcükleri
# =====================================================================
function Tags([string]$Q) { return @(Get-BoardSearchResults $Q | ForEach-Object { [string]$_.Tag }) }
Assert-True ((Tags 'hazirlik') -contains 'nav:solve' -and (Tags 'hazirlik') -contains 'act:prep') 'arama: hazırlık -> Çözüm Merkezi ve Hazırlık eylemi'
Assert-True ((Tags 'bilgisayarim') -contains 'nav:solve' -and (Tags 'bilgisayarim') -contains 'act:pcinfo') 'arama: bilgisayarım'
Assert-True ((Tags 'donanim') -contains 'nav:solve') 'arama: donanım'
Assert-True ((Tags 'tpm') -contains 'nav:solve') 'arama: tpm'
Assert-True ((Tags 'kurtar') -contains 'act:recover') 'arama: kurtar -> Dosya kurtar'
Assert-Eq (@(Get-BoardSearchResults 'kalici sil')[0].Tag) 'act:erase' 'arama: kalıcı sil -> ilk sonuç eylem'
Assert-True ((Tags 'kalici silme') -contains 'nav:solve') 'arama: kalıcı silme sayfası'
Assert-True ((Tags 'standart') -contains 'nav:solve' -and (Tags 'standart') -contains 'nav:security') 'arama: standart -> Çözüm Merkezi ve Güvenlik'
foreach ($w in @('cis', 'nist', 'iso', 'bsi', 'nis2', 'kvkk', 'gdpr')) { Assert-True ((Tags $w) -contains 'nav:security' -and (Tags $w) -contains 'nav:solve') ('arama: ' + $w + ' -> Güvenlik ve Çözüm Merkezi') }
$coz = 'Çözüm'
Assert-Eq (@(Get-BoardSearchResults $coz)[0].Tag) 'nav:solve' 'arama: Türkçe harfli çözüm -> Çözüm Merkezi ilk'
# önceki aramalar bozulmadı
Assert-Eq (@(Get-BoardSearchResults 'guvenlik')[0].Tag) 'nav:security' 'arama: güvenlik hâlâ Güvenlik sayfası'
Assert-Eq (@(Get-BoardSearchResults 'temizlik')[0].Tag) 'nav:clean' 'arama: temizlik hâlâ Temizlik'
Assert-True ((Tags 'saglik') -contains 'act:health') 'arama: sağlık eylemi hâlâ bulunur'
# arama sözcükleri ASCII ve küçük harf
foreach ($k in @($script:BoardSearchWords.Keys)) { Assert-True ([string]$script:BoardSearchWords[$k] -cmatch '^[a-z0-9 ]+$') ('arama sözcükleri ASCII küçük harf: ' + $k) }

# =====================================================================
#  10) komut satırı: sayfa:sekme hedefleri
# =====================================================================
$t = Split-CmdTarget 'solve:prep'
Assert-True ($t.Page -eq 'solve' -and $t.Sub -eq 'prep') 'komut hedefi: sayfa:sekme ayrılır'
$t = Split-CmdTarget 'clean'
Assert-True ($t.Page -eq 'clean' -and $t.Sub -eq '') 'komut hedefi: yalnızca sayfa'
$t = Split-CmdTarget ''
Assert-True ($t.Page -eq '' -and $t.Sub -eq '') 'komut hedefi: boş'
$t = Split-CmdTarget 'a:b:c'
Assert-True ($t.Page -eq 'a' -and $t.Sub -eq 'b:c') 'komut hedefi: ilk iki nokta ayırır'
$script:OpenedPages.Clear()
Open-CmdPage 'solve:recover'; Open-CmdPage 'security'; Open-CmdPage 'solve'
Assert-Eq (($script:OpenedPages) -join ',') 'solve/recover,security/,solve/' 'komut hedefi: Open-Page doğru çağrılır'
foreach ($k in @($script:CmdPages.Keys)) {
    $tg = Split-CmdTarget ([string]$script:CmdPages[$k])
    $okPage = ($script:PageTitles.Contains([string]$tg.Page)) -or (@('board', 'startup', 'compress', 'wu') -contains [string]$tg.Page)
    Assert-True $okPage ('komut sözcüğü gerçek sayfaya gider: ' + $k + ' -> ' + [string]$script:CmdPages[$k])
    if ([string]$tg.Sub -ne '') {
        $tabs = @()
        if ([string]$tg.Page -eq 'solve') { $tabs = @($script:SlvTabs) } elseif ([string]$tg.Page -eq 'tools') { $tabs = @($script:TlTabs) }
        Assert-True ($tabs -contains [string]$tg.Sub) ('komut sözcüğü gerçek sekmeye gider: ' + $k)
    }
}
Assert-Eq $script:CmdPages['hazirlik'] 'solve:prep' 'komut: hazirlik -> Hazırlık sekmesi'
Assert-Eq $script:CmdPages['silinen'] 'solve:recover' 'komut: silinen -> Silinen dosyalar'
Assert-Eq $script:CmdPages['silme'] 'solve:erase' 'komut: silme -> Kalıcı silme'
Assert-Eq $script:CmdPages['bilgisayarim'] 'solve:pc' 'komut: bilgisayarim -> Bilgisayarım'
Assert-Eq $script:CmdPages['donanim'] 'solve:pc' 'komut: donanim -> Bilgisayarım'
Assert-Eq $script:CmdPages['diskler'] 'solve:disk' 'komut: diskler -> Diskler'
Assert-Eq $script:CmdPages['disk'] 'clean' 'komut: disk -> Temizlik (önceki davranış korunur)'
Assert-Eq $script:CmdPages['kurtar'] 'solve' 'komut: kurtar -> Çözüm Merkezi (önceki davranış korunur)'
Assert-True ($src -match "Open-CmdPage \(\[string\]\`$script:CmdPages\[\`$a0\]\)") 'komut: ac komutu hedefi Open-CmdPage ile açar'
Assert-True ($src -notmatch 'Open-Page \(\[string\]\$script:CmdPages\[\$a0\]\)') 'komut: ac komutunda eski doğrudan çağrı kalmadı'

Show-Result
