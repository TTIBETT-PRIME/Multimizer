. "$PSScriptRoot/lib.ps1"
# Güvenlik duruşu (mods\129_posture.ps1): standart eşleme tablolarının bütünlüğü (başvuru biçimleri, katalog ve bulgu kimlikleriyle karşılaştırma),
# ayrıştırma ve biçimlendirme, bulgu/ayar eşleme, kapsam hesabı, Chk_Posture bulguları, rapor bölümü, sağlık taramasına bağlantı ve Uzman kipi satırı.
Import-Fn 'Get-JsonProp', 'Test-OsOk', 'Test-WhenOk', 'New-FixInfo', 'New-TweakFix', 'Add-Finding', 'New-Section',
    'ConvertTo-PostureMap', 'Get-PostureTweakMap', 'Get-PostureFindMap', 'Get-PostureThemeName', 'Format-PostureRefs', 'Get-PostureForFinding', 'Set-FindingStd',
    'Get-PostureCoverage', 'Get-PostureNameList', 'Get-PostureWeakTheme', 'Chk_Posture', 'Get-PostureReportSection',
    'Get-SlBr', 'Get-CatLabel', 'Render-SlScan', 'Update-PageMode_solve'
Import-Var 'PostureStds', 'PostureThemes', 'PostureTweakRows', 'PostureFindRows'
$script:PostureTweakMapCache = $null
$script:PostureFindMapCache = $null
. "$PSScriptRoot/uifake.ps1"

# ---- sahte ortam ----
$script:Findings = New-Object System.Collections.ArrayList
$script:AutoFixTweaks = @()
$script:FakeCat = @{}
$script:Pend = @{}
$script:Blocked = @()
$sync = @{ Profile = [pscustomobject]@{ WinMajor = '11'; IsLaptop = $false; DiskType = 'SSD' } }
function Get-CatalogItem([string]$Id) { if ($script:FakeCat.ContainsKey($Id)) { return $script:FakeCat[$Id] } return $null }
function Get-TweakPending($Item) { if ($script:Pend.ContainsKey([string]$Item.Id)) { return [int]$script:Pend[[string]$Item.Id] } return 0 }
function Test-TweakBlocked($Item) { return ($script:Blocked -contains [string]$Item.Id) }
function Add-Cat([string]$Id, [int]$Level, [string]$OS = 'All', [string]$When = '') {
    $script:FakeCat[$Id] = @{ Id = $Id; Title = ('Ayar ' + $Id); Level = $Level; OS = $OS; When = $When }
}
function Reset-Cat { $script:FakeCat = @{}; $script:Pend = @{}; $script:Blocked = @(); $script:Findings.Clear() }
function Find-F([string]$Id) { foreach ($f in $script:Findings) { if ($f.Id -eq $Id) { return $f } } return $null }

# =====================================================================
#  1) tablo bütünlüğü
# =====================================================================
$stdKeys = @($script:PostureStds | ForEach-Object { ([string]$_).Split('|')[0] })
$themeKeys = @($script:PostureThemes | ForEach-Object { ([string]$_).Split('|')[0] })
Assert-Eq ($stdKeys -join ',') 'CIS,NIST,ISO,BSI,NIS2,GDPR,KVKK' 'standart listesi ve sırası'
Assert-Eq ($themeKeys -join ',') 'acc,mal,net,cfg,log,upd,dat,prv' 'konu listesi ve sırası'
foreach ($s in $script:PostureStds) {
    $f = ([string]$s).Split('|')
    Assert-True ($f.Count -eq 3 -and $f[1] -ne '') ('standart satırı: üç alan ' + $f[0])
}
foreach ($t in $script:PostureThemes) {
    $f = ([string]$t).Split('|')
    Assert-True ($f.Count -eq 2 -and $f[1] -ne '') ('konu satırı: iki alan ' + $f[0])
}

# CIS v8: denetim başına güvenlik önlemi sayısı (toplam 153)
$cisMax = @{ 1 = 5; 2 = 7; 3 = 14; 4 = 12; 5 = 6; 6 = 8; 7 = 7; 8 = 12; 9 = 7; 10 = 7; 11 = 5; 12 = 8; 13 = 11; 14 = 9; 15 = 7; 16 = 14; 17 = 9; 18 = 5 }
$isoMax = @{ 5 = 37; 6 = 8; 7 = 14; 8 = 34 }
$fmt = @{
    CIS  = '^\d{1,2}\.\d{1,2}$'
    NIST = '^(AC|AT|AU|CA|CM|CP|IA|IR|MA|MP|PE|PL|PM|PS|PT|RA|SA|SC|SI|SR)-\d{1,2}$'
    ISO  = '^A\.[5-8]\.\d{1,2}$'
    BSI  = '^(ISMS|ORP|CON|OPS|DER|APP|SYS|IND|NET|INF)\.\d+(\.\d+)*$'
    NIS2 = '^21\(2\)\([a-j]\)$'
    GDPR = '^\d{1,2}(\(\d\)\([a-f]\))?$'
    KVKK = '^\d{1,2}$'
}
function Test-RefRows([string]$What, $Map) {
    $dupGuard = @{}
    foreach ($key in @($Map.Order)) {
        $e = $Map.ById[$key]
        Assert-True (-not $dupGuard.ContainsKey($key)) ($What + ': yinelenen kimlik yok ' + $key)
        $dupGuard[$key] = $true
        Assert-True ($themeKeys -contains [string]$e.Theme) ($What + ': geçerli konu ' + $key)
        Assert-True ($e.Refs.Count -ge 1) ($What + ': en az bir standart ' + $key)
        foreach ($sk in @($e.Refs.Keys)) {
            Assert-True ($stdKeys -contains [string]$sk) ($What + ': bilinen standart ' + $key + '/' + $sk)
            $list = @($e.Refs[$sk])
            Assert-True ($list.Count -ge 1) ($What + ': başvuru var ' + $key + '/' + $sk)
            $seen = @{}
            foreach ($r in $list) {
                $rs = [string]$r
                Assert-True ($rs -cmatch $fmt[[string]$sk]) ($What + ': başvuru biçimi ' + $key + '/' + $sk + '=' + $rs)
                Assert-True (-not $seen.ContainsKey($rs)) ($What + ': başvuru yinelenmiyor ' + $key + '/' + $sk + '=' + $rs)
                $seen[$rs] = $true
                if ([string]$sk -eq 'CIS' -and $rs -match '^(\d+)\.(\d+)$') {
                    $ctl = [int]$Matches[1]; $sg = [int]$Matches[2]
                    Assert-True ($cisMax.ContainsKey($ctl) -and $sg -ge 1 -and $sg -le [int]$cisMax[$ctl]) ($What + ': CIS v8 önlemi var ' + $key + '=' + $rs)
                }
                if ([string]$sk -eq 'ISO' -and $rs -match '^A\.(\d)\.(\d+)$') {
                    $th = [int]$Matches[1]; $nn = [int]$Matches[2]
                    Assert-True ($isoMax.ContainsKey($th) -and $nn -ge 1 -and $nn -le [int]$isoMax[$th]) ($What + ': ISO 27001:2022 Ek A kontrolü var ' + $key + '=' + $rs)
                }
            }
        }
    }
}
$tmap = Get-PostureTweakMap
$fmap = Get-PostureFindMap
Assert-Eq (@($tmap.Order).Count) (@($script:PostureTweakRows).Count) 'ayar satırları: hepsi ayrıştı (yinelenen/bozuk satır yok)'
Assert-Eq (@($fmap.Order).Count) (@($script:PostureFindRows).Count) 'bulgu satırları: hepsi ayrıştı (yinelenen/bozuk satır yok)'
Assert-True (@($tmap.Order).Count -ge 45) 'ayar satırı sayısı beklenenden az değil'
Assert-True (@($fmap.Order).Count -ge 60) 'bulgu satırı sayısı beklenenden az değil'
Test-RefRows 'ayar' $tmap
Test-RefRows 'bulgu' $fmap
# gizlilik satırları yalnızca gizlilik standartlarını taşır; güvenlik satırları gizlilik standardı taşımaz (şifreleme/yedek satırları GDPR m.32 ve KVKK m.12 hariç)
foreach ($key in @($tmap.Order)) {
    $e = $tmap.ById[$key]
    if ($e.Theme -eq 'prv') {
        Assert-True ($e.Refs.ContainsKey('GDPR') -and $e.Refs.ContainsKey('KVKK') -and $e.Refs.ContainsKey('ISO')) ('gizlilik ayarı GDPR, KVKK ve ISO taşır ' + $key)
        Assert-True (-not $e.Refs.ContainsKey('CIS') -and -not $e.Refs.ContainsKey('NIS2')) ('gizlilik ayarı CIS/NIS2 taşımaz ' + $key)
    } else {
        Assert-True (-not $e.Refs.ContainsKey('GDPR') -and -not $e.Refs.ContainsKey('KVKK')) ('güvenlik ayarı GDPR/KVKK taşımaz ' + $key)
    }
}
foreach ($key in @('bl', 'bl-data', 'bl-key', 'backup')) {
    $e = $fmap.ById[$key]
    Assert-True ($e.Refs.ContainsKey('GDPR') -and (@($e.Refs['GDPR']) -contains '32') -and $e.Refs.ContainsKey('KVKK') -and (@($e.Refs['KVKK']) -contains '12')) ('veri koruma bulgusu GDPR m.32 ve KVKK m.12 taşır ' + $key)
}

# ---- gerçek katalog ve bulgu kimlikleriyle karşılaştırma (derlenmiş betiğin sözdizimi ağacı) ----
[void](Get-AstFunctions)
$twAst = @($script:Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Add-Tweak' }, $true))
$cat = @{}
foreach ($c in $twAst) {
    $tx = $c.Extent.Text
    if ($tx -match "Id = '([^']+)'") {
        $id = $Matches[1]
        $lv = 2; if ($tx -match 'Level = (\d)') { $lv = [int]$Matches[1] }
        $cg = ''; if ($tx -match "Cat = '([^']*)'") { $cg = $Matches[1] }
        $cat[$id] = @{ Level = $lv; Cat = $cg }
    }
}
Assert-True ($cat.Count -ge 90) ('katalog ayrıştı (' + $cat.Count + ' ayar)')
foreach ($key in @($tmap.Order)) {
    Assert-True ($cat.ContainsKey($key)) ('ayar satırı katalogda var ' + $key)
    if (-not $cat.ContainsKey($key)) { continue }
    Assert-True ($cat[$key].Level -ge 1 -and $cat[$key].Level -le 3) ('ayar satırı ölçülebilir düzeyde (1-3) ' + $key)
    $isPrv = ($tmap.ById[$key].Theme -eq 'prv')
    if ($isPrv) { Assert-Eq $cat[$key].Cat 'Gizlilik' ('gizlilik konusundaki ayar Gizlilik kategorisinde ' + $key) }
    # Gizlilik kategorisinde olup güvenlik konusuna eşlenen tek ayar: Insider (önizleme sürümlerine kayıt = güncelleme kanalı güvenliği, veri paylaşımı değil)
    if (-not $isPrv -and $cat[$key].Cat -eq 'Gizlilik') { Assert-Eq $key 'Insider' ('Gizlilik kategorisindeki ayar yalnızca Insider olabilir güvenlik konusunda ' + $key) }
}
foreach ($id in @($cat.Keys)) {
    $c = $cat[$id]
    if ($c.Cat -eq 'Guvenlik') { Assert-True ($tmap.ById.ContainsKey($id)) ('her Güvenlik ayarı eşlenmiş ' + $id) }
    if (($c.Cat -eq 'Sirket' -or $c.Cat -eq 'Guncelleme') -and $c.Level -le 3 -and $id -ne 'NoRebootLoggedOn') {
        Assert-True ($tmap.ById.ContainsKey($id)) ('Şirket/Güncelleme ayarı (düzey 1-3) eşlenmiş ' + $id)
    }
}
Assert-True (-not $tmap.ById.ContainsKey('NoRebootLoggedOn')) 'rahatlık ayarı (sürpriz yeniden başlatma yok) güvenlik eşlemesine girmez'
$srcText = [System.IO.File]::ReadAllText($script:TestPath)
$static = @{}
foreach ($m in [regex]::Matches($srcText, "Add-Finding\s+\(?'([a-z0-9\-]+)'\)?\s+'(sec|maint|perf)'")) { $static[$m.Groups[1].Value] = $m.Groups[2].Value }
Assert-True ($static.Count -ge 80) ('bulgu kimlikleri çıkarıldı (' + $static.Count + ')')
foreach ($key in @($fmap.Order)) {
    $known = ($static.ContainsKey($key) -or $key -eq 'wifi-weak')
    Assert-True $known ('bulgu satırı gerçek bir bulgu kimliği ' + $key)
}
$unmapped = @($static.Keys | Where-Object { $static[$_] -eq 'sec' -and -not $fmap.ById.ContainsKey($_) } | Sort-Object)
Assert-Eq ($unmapped -join ',') 'cam-live,posture,posture-prv' 'eşlenmemiş güvenlik bulguları yalnızca bilinen üçü'

# =====================================================================
#  2) ayrıştırma ve biçimlendirme
# =====================================================================
$m = ConvertTo-PostureMap @(' A | net | CIS=4.8 | NIST=CM-7, SC-7 ', 'B|acc|ISO=A.8.5|BOZUK|NIS2=', 'A|mal|CIS=1.1', 'kisa|net', '|net|CIS=1.1', 'C|cfg||CIS=3.6,,3.11')
Assert-Eq (@($m.Order) -join ',') 'A,B,C' 'ayrıştırma: sıra korunur, bozuk ve yinelenen satır atlanır'
Assert-Eq $m.ById['A'].Theme 'net' 'ayrıştırma: konu boşluktan arındırılır'
Assert-Eq (@($m.ById['A'].Refs['NIST']) -join '|') 'CM-7|SC-7' 'ayrıştırma: başvurular ayrılır ve kırpılır'
Assert-Eq (@($m.ById['A'].Refs['CIS']) -join '|') '4.8' 'ayrıştırma: ilk satır kazanır (yinelenen A atlandı)'
Assert-True ($m.ById['B'].Refs.ContainsKey('ISO') -and -not $m.ById['B'].Refs.ContainsKey('NIS2')) 'ayrıştırma: boş başvuru listesi ve bozuk alan yok sayılır'
Assert-Eq (@($m.ById['C'].Refs['CIS']) -join '|') '3.6|3.11' 'ayrıştırma: boş başvuru parçası atlanır'
$m0 = ConvertTo-PostureMap @()
Assert-True (@($m0.Order).Count -eq 0 -and $m0.ById.Count -eq 0) 'ayrıştırma: boş girdi'

Assert-Eq (Format-PostureRefs $null) '' 'biçim: null kayıt boş döner'
Assert-Eq (Format-PostureRefs @{ Refs = @{} }) '' 'biçim: başvurusu olmayan kayıt boş döner'
Assert-Eq (Format-PostureRefs $tmap.ById['Smb1']) 'CIS v8 4.8  ·  NIST 800-53 CM-7  ·  ISO 27001 A.8.9, A.8.20  ·  BSI SYS.2.2.3  ·  NIS2 m.21(2)(g)' 'biçim: Smb1 satırı'
Assert-Eq (Format-PostureRefs $tmap.ById['Telemetry']) 'ISO 27001 A.5.34  ·  GDPR m.5(1)(c), 25  ·  KVKK m.4' 'biçim: gizlilik satırı (önek yalnızca ilk başvuruda)'
Assert-Eq (Format-PostureRefs $fmap.ById['bl']) 'CIS v8 3.6  ·  NIST 800-53 SC-28  ·  ISO 27001 A.8.1, A.8.24  ·  BSI CON.1, SYS.2.2.3  ·  NIS2 m.21(2)(h)  ·  GDPR m.32  ·  KVKK m.12' 'biçim: şifreleme bulgusu tüm standartlarla'
$mixed = @{ Refs = @{ KVKK = @('12'); CIS = @('4.8'); XYZ = @('9') } }
Assert-Eq (Format-PostureRefs $mixed) 'CIS v8 4.8  ·  KVKK m.12' 'biçim: standart sırası sabit, bilinmeyen standart atlanır'
Assert-Eq (Get-PostureThemeName 'net') 'Ağ ve uzaktan erişim' 'konu adı'
Assert-Eq (Get-PostureThemeName 'prv') 'Gizlilik' 'konu adı: gizlilik'
Assert-Eq (Get-PostureThemeName 'zzz') 'zzz' 'konu adı: bilinmeyen anahtar aynen döner'

# =====================================================================
#  3) bulgu ve ayar eşleme
# =====================================================================
$e1 = Get-PostureForFinding @{ Id = 'smb1' }
Assert-Eq $e1.Key 'smb1' 'eşleme: bulgu kimliği doğrudan'
Assert-Eq $e1.Theme 'net' 'eşleme: bulgu konusu'
Assert-Eq (Get-PostureForFinding @{ Id = 'wifi-weak-12' }).Key 'wifi-weak' 'eşleme: wifi-weak-<dizin> öneki'
Assert-Eq (Get-PostureForFinding @{ Id = 'np-Wpad' }).Key 'Wpad' 'eşleme: np-<ayar> öneki katalog satırına gider'
Assert-Eq (Get-PostureForFinding @{ Id = 'x-1'; Action = @{ Kind = 'Tweak'; Id = 'GuestOff' } }).Key 'GuestOff' 'eşleme: eylem tek ayarsa onun satırı'
Assert-Eq (Get-PostureForFinding @{ Id = 'x-2'; Action = $null; Fix = @{ Kind = 'Tweak'; Ids = @('Lockout') } }).Key 'Lockout' 'eşleme: düzeltme tek ayarsa onun satırı'
Assert-True ($null -eq (Get-PostureForFinding @{ Id = 'x-3'; Fix = @{ Kind = 'Tweak'; Ids = @('Lockout', 'GuestOff') } })) 'eşleme: düzeltme birden çok ayarsa eşleme yok'
Assert-True ($null -eq (Get-PostureForFinding @{ Id = 'x-4'; Action = @{ Kind = 'Page'; Page = 'security' } })) 'eşleme: sayfa eylemi eşleme üretmez'
Assert-True ($null -eq (Get-PostureForFinding @{ Id = 'cam-live' })) 'eşleme: bilinçli olarak eşlenmeyen bulgu'
Assert-True ($null -eq (Get-PostureForFinding $null)) 'eşleme: null bulgu'
Assert-True ($null -eq (Get-PostureForFinding @{ Id = '' })) 'eşleme: kimliksiz bulgu'
Assert-Eq (Get-PostureForFinding ([pscustomobject]@{ Id = 'ps2' })).Key 'ps2' 'eşleme: nesne biçiminde bulgu da çözülür'
Assert-Eq (Get-PostureForFinding @{ Id = 'SMB1' }).Key 'smb1' 'eşleme: kimlik büyük/küçük harfe duyarsız'

$fa = @{ Id = 'llmnr'; Cat = 'sec'; Status = 'info'; Title = 'LLMNR'; Detail = ''; Action = $null; Weight = 0; Fix = $null }
Set-FindingStd $fa
Assert-Eq $fa.Std 'CIS v8 4.8  ·  NIST 800-53 CM-7, SC-7  ·  ISO 27001 A.8.9, A.8.20  ·  BSI SYS.2.2.3  ·  NIS2 m.21(2)(g)' 'Set-FindingStd: Std yazılır'
Assert-Eq $fa.Theme 'net' 'Set-FindingStd: konu yazılır'
$fb = @{ Id = 'cam-live'; Cat = 'sec'; Status = 'info'; Title = ''; Detail = '' }
Set-FindingStd $fb
Assert-True (-not $fb.ContainsKey('Std') -and -not $fb.ContainsKey('Theme')) 'Set-FindingStd: eşleme yoksa alan eklenmez'
Set-FindingStd $null
Assert-True $true 'Set-FindingStd: null bulgu hata vermez'

# =====================================================================
#  4) kapsam hesabı (sahte katalog)
# =====================================================================
Reset-Cat
Add-Cat 'Smb1' 1; Add-Cat 'AutoRun' 1; Add-Cat 'Llmnr' 2; Add-Cat 'NetBiosOff' 3; Add-Cat 'Lockout' 2; Add-Cat 'GuestOff' 1
Add-Cat 'Telemetry' 1; Add-Cat 'Ads' 1
Add-Cat 'RdpNla' 1 '10'            # bu bilgisayar Windows 11: atlanır
Add-Cat 'Wpad' 1 'All' 'Laptop'    # masaüstü: atlanır
Add-Cat 'RdpOff' 4                 # düzey 4: ölçülmez
Add-Cat 'LsaPpl' 1                 # ölçülemez (-1): atlanır
$script:Pend = @{ Smb1 = 0; AutoRun = 2; Llmnr = 1; NetBiosOff = 1; Lockout = 0; GuestOff = 0; Telemetry = 3; Ads = 0; RdpNla = 5; Wpad = 5; RdpOff = 5; LsaPpl = -1 }
$cv = Get-PostureCoverage $sync.Profile $null
$ids = @($cv.Items | ForEach-Object { $_.Id })
Assert-Eq ($ids -join ',') 'Smb1,AutoRun,GuestOff,Llmnr,NetBiosOff,Lockout,Telemetry,Ads' 'kapsam: ölçülen ayarlar tablo sırasında (OS, donanım, düzey 4 ve ölçülemeyenler dışarıda)'
$byId = @{}; foreach ($i in $cv.Items) { $byId[$i.Id] = $i }
Assert-Eq $byId['Smb1'].Status 'ok' 'kapsam: bekleyen 0 = uygulanmış'
Assert-Eq $byId['AutoRun'].Status 'pend' 'kapsam: bekleyen > 0 = uygulanmamış'
Assert-Eq $byId['AutoRun'].Pending 2 'kapsam: bekleyen değer sayısı korunur'
Assert-Eq $byId['AutoRun'].Level 1 'kapsam: düzey korunur'
Assert-Eq $byId['AutoRun'].Theme 'mal' 'kapsam: konu eşleme tablosundan gelir'
Assert-Eq $byId['AutoRun'].Title 'Ayar AutoRun' 'kapsam: başlık katalogdan gelir'
Assert-True ($byId['AutoRun'].Reported -eq $false) 'kapsam: Skip yokken Reported = false'
$th = @{}; foreach ($t in $cv.Themes) { $th[$t.Key] = $t }
Assert-Eq (@($cv.Themes | ForEach-Object { $_.Key }) -join ',') 'acc,mal,net,cfg,log,upd,dat,prv' 'kapsam: konular tablo sırasında'
Assert-True ($th['net'].Base -eq 2 -and $th['net'].Ok -eq 1 -and $th['net'].Pend -eq 1) 'kapsam: ağ konusu (düzey 3 temel sayılmaz)'
Assert-True ($th['mal'].Base -eq 1 -and $th['mal'].Ok -eq 0 -and $th['mal'].Pend -eq 1) 'kapsam: zararlı yazılım konusu'
Assert-True ($th['acc'].Base -eq 2 -and $th['acc'].Ok -eq 2 -and $th['acc'].Pend -eq 0) 'kapsam: hesap konusu'
Assert-True ($th['prv'].Base -eq 2 -and $th['prv'].Ok -eq 1 -and $th['prv'].Pend -eq 1) 'kapsam: gizlilik konusu ayrıca sayılır'
Assert-True ($th['cfg'].Base -eq 0 -and $th['log'].Base -eq 0) 'kapsam: ayarı olmayan konular sıfır'
Assert-Eq $cv.Base 5 'kapsam: temel toplam (gizlilik hariç)'
Assert-Eq $cv.Ok 3 'kapsam: uygulanmış toplam'
Assert-Eq $cv.Pend 2 'kapsam: uygulanmamış toplam'
Assert-Eq $cv.Percent 60 'kapsam: yüzde'
Assert-Eq $cv.Opt 1 'kapsam: isteğe bağlı (düzey 3) bekleyen sayısı'
Assert-Eq $cv.Blocked 0 'kapsam: engellenen yok'

# Windows'un koruduğu ayar kapsamdan düşer ve ayrıca sayılır
$script:Blocked = @('Llmnr')
$cvb = Get-PostureCoverage $sync.Profile $null
$bb = @{}; foreach ($i in $cvb.Items) { $bb[$i.Id] = $i }
Assert-Eq $bb['Llmnr'].Status 'blocked' 'engelli: durum blocked'
Assert-True ($cvb.Base -eq 4 -and $cvb.Ok -eq 3 -and $cvb.Pend -eq 1 -and $cvb.Blocked -eq 1) 'engelli: temelden düşer, ayrıca sayılır'
Assert-Eq $cvb.Percent 75 'engelli: yüzde yeniden hesaplanır'
$script:Blocked = @()
# engelli ve bekleyeni 0 olan ayar da engelli sayılır (Windows yazmayı reddetti; uygulanmış değildir)
$script:Blocked = @('Smb1')
$cvb2 = Get-PostureCoverage $sync.Profile $null
$bb2 = @{}; foreach ($i in $cvb2.Items) { $bb2[$i.Id] = $i }
Assert-Eq $bb2['Smb1'].Status 'blocked' 'engelli: bekleyeni 0 olsa da engelli'
Assert-Eq $cvb2.Ok 2 'engelli: uygulanmış sayılmaz'
$script:Blocked = @()

# başka bulgunun sunduğu ayarlar işaretlenir ama sayılmaya devam eder
$cvs = Get-PostureCoverage $sync.Profile @{ AutoRun = $true; Telemetry = $true }
$bs = @{}; foreach ($i in $cvs.Items) { $bs[$i.Id] = $i }
Assert-True ($bs['AutoRun'].Reported -eq $true -and $bs['Telemetry'].Reported -eq $true -and $bs['Llmnr'].Reported -eq $false) 'Skip: yalnızca verilen kimlikler Reported olur'
Assert-True ($cvs.Base -eq 5 -and $cvs.Ok -eq 3 -and $cvs.Percent -eq 60) 'Skip: toplamlar değişmez'
$cvs2 = Get-PostureCoverage $sync.Profile @{ autorun = $true }
$bs2 = @{}; foreach ($i in $cvs2.Items) { $bs2[$i.Id] = $i }
Assert-True ($bs2['AutoRun'].Reported -eq $true) 'Skip: kimlik büyük/küçük harfe duyarsız'

# ölçülebilir ayar yoksa
Reset-Cat
$cv0 = Get-PostureCoverage $sync.Profile $null
Assert-True (@($cv0.Items).Count -eq 0 -and $cv0.Base -eq 0 -and $cv0.Percent -eq -1) 'kapsam: katalog boşken yüzde -1'
# profil yokken (null) OS ve donanım koşulları geçerli sayılır
Add-Cat 'RdpNla' 1 '10'; Add-Cat 'Wpad' 1 'All' 'Laptop'
$cvn = Get-PostureCoverage $null $null
Assert-Eq (@($cvn.Items | ForEach-Object { $_.Id }) -join ',') 'RdpNla,Wpad' 'kapsam: profil yoksa koşullar geçerli'

# yüzde yuvarlama: 8 temel ayardan 1 uygulanmış = %12,5 -> %13
Reset-Cat
$sec8 = @('Smb1', 'AutoRun', 'Llmnr', 'NetBiosOff', 'Lockout', 'GuestOff', 'WDigest', 'NoLmHash')
foreach ($s in $sec8) { Add-Cat $s 1; $script:Pend[$s] = 1 }
$script:Pend['Smb1'] = 0
Assert-Eq (Get-PostureCoverage $sync.Profile $null).Percent 13 'yüzde: 12,5 yukarı yuvarlanır'
$script:Pend['AutoRun'] = 0
Assert-Eq (Get-PostureCoverage $sync.Profile $null).Percent 25 'yüzde: 2/8 = %25'
foreach ($s in $sec8) { $script:Pend[$s] = 0 }
Assert-Eq (Get-PostureCoverage $sync.Profile $null).Percent 100 'yüzde: hepsi uygulanmış = %100'

# ---- ad listesi ----
$mk = { param($n) @(1..$n | ForEach-Object { @{ Title = ('T' + $_) } }) }
Assert-Eq (Get-PostureNameList @() 4) '' 'ad listesi: boş'
Assert-Eq (Get-PostureNameList (& $mk 1) 4) 'T1' 'ad listesi: tek ad'
Assert-Eq (Get-PostureNameList @{ Title = 'Tek' } 4) 'Tek' 'ad listesi: dizi olmayan tek öğe'
Assert-Eq (Get-PostureNameList (& $mk 3) 4) 'T1; T2; T3' 'ad listesi: sınırın altında'
Assert-Eq (Get-PostureNameList (& $mk 4) 4) 'T1; T2; T3; T4' 'ad listesi: tam sınırda'
Assert-Eq (Get-PostureNameList (& $mk 7) 3) 'T1; T2; T3 ve 4 ayar daha' 'ad listesi: sınırın üstünde'

# ---- en zayıf konu ----
$tc = {
    param($key, $name, $b, $o)
    @{ Key = $key; Name = $name; Base = $b; Ok = $o; Pend = ($b - $o) }
}
$covW = @{ Themes = @((& $tc 'acc' 'Hesap' 4 4), (& $tc 'mal' 'Zararlı' 2 1), (& $tc 'net' 'Ağ' 4 1), (& $tc 'prv' 'Gizlilik' 5 0), (& $tc 'cfg' 'Yapı' 1 0)) }
$w = Get-PostureWeakTheme $covW
Assert-Eq $w.Key 'net' 'en zayıf konu: en düşük oran (gizlilik ve tek ayarlı konu sayılmaz)'
$covW2 = @{ Themes = @((& $tc 'acc' 'Hesap' 4 2), (& $tc 'net' 'Ağ' 6 3)) }
Assert-Eq (Get-PostureWeakTheme $covW2).Key 'net' 'en zayıf konu: oran eşitse daha çok eksik olan'
$covW3 = @{ Themes = @((& $tc 'acc' 'Hesap' 4 4), (& $tc 'net' 'Ağ' 3 3)) }
Assert-True ($null -eq (Get-PostureWeakTheme $covW3)) 'en zayıf konu: eksik yoksa boş'

# =====================================================================
#  5) Chk_Posture bulguları
# =====================================================================
function New-Scenario1 {
    Reset-Cat
    Add-Cat 'Smb1' 1; Add-Cat 'AutoRun' 1; Add-Cat 'Llmnr' 2; Add-Cat 'NetBiosOff' 3; Add-Cat 'Lockout' 2; Add-Cat 'GuestOff' 1
    Add-Cat 'Telemetry' 1; Add-Cat 'Ads' 1
    $script:Pend = @{ Smb1 = 0; AutoRun = 2; Llmnr = 1; NetBiosOff = 1; Lockout = 0; GuestOff = 0; Telemetry = 3; Ads = 0 }
}
New-Scenario1
Chk_Posture
$p = Find-F 'posture'
Assert-True ($null -ne $p) 'bulgu: posture üretildi'
Assert-Eq $p.Cat 'sec' 'bulgu: kategori güvenlik'
Assert-Eq $p.Status 'info' 'bulgu: 5 ayardan azı eksikse bilgi'
Assert-Eq $p.Weight 2 'bulgu: bilgi ağırlığı 2'
Assert-Eq $p.Title 'Sertleştirme ayarlarından 2 tanesi uygulanmamış' 'bulgu: başlık eksik sayısını söyler'
Assert-True ($p.Detail -match '^Kapsam %60 \(3/5\)\. Eksik: Ayar AutoRun; Ayar Llmnr\.') 'bulgu: ayrıntı kapsamı ve eksikleri söyler'
Assert-True ($p.Detail -match 'En zayıf konu: ') 'bulgu: ayrıntı en zayıf konuyu söyler'
Assert-True ($p.Detail.Length -lt 300) 'bulgu: ayrıntı çözüm sayfasının 300 karakter sınırına sığar'
Assert-True ($null -ne $p.Fix -and $p.Fix.Mode -eq 'Click' -and $p.Fix.Kind -eq 'Tweak') 'bulgu: düzeltme tıklamayla (toplu otomatik değil)'
Assert-Eq (@($p.Fix.Ids) -join ',') 'AutoRun' 'bulgu: düzeltme yalnızca güvenli (düzey 1) ayarları kapsar'
Assert-Eq $p.Fix.Label 'Güvenli düzeydeki ayarları uygula' 'bulgu: düzeltme etiketi'
Assert-True ($p.Action.Kind -eq 'Page' -and $p.Action.Page -eq 'security' -and $p.Action.Label -eq 'Güvenlik sayfası') 'bulgu: eylem Güvenlik sayfasını açar'
$pv = Find-F 'posture-prv'
Assert-True ($null -ne $pv) 'bulgu: posture-prv üretildi'
Assert-Eq $pv.Status 'info' 'gizlilik bulgusu: bilgi'
Assert-Eq $pv.Weight 0 'gizlilik bulgusu: puanı düşürmez'
Assert-Eq $pv.Title 'Veri paylaşımını azaltan 1 ayar uygulanmamış' 'gizlilik bulgusu: başlık'
Assert-True ($pv.Detail -match '^Eksik: Ayar Telemetry\.' -and $pv.Detail -match 'Uygulanınca') 'gizlilik bulgusu: ayrıntı'
Assert-True ($pv.Fix.Mode -eq 'Click' -and (@($pv.Fix.Ids) -join ',') -eq 'Telemetry' -and $pv.Fix.Label -eq 'Gizlilik varsayılanlarını uygula') 'gizlilik bulgusu: düzeltme'
Assert-True ($pv.Action.Kind -eq 'Page' -and $pv.Action.Page -eq 'optimize') 'gizlilik bulgusu: eylem Optimize sayfası'
Assert-Eq $script:Findings.Count 2 'iki bulgu üretildi'

# başka bir bulgu AutoRun'ı zaten sunuyorsa yinelenmez
New-Scenario1
Add-Finding 'autorun' 'sec' 'info' 'Otomatik çalıştırma' '' @{ Kind = 'Tweak'; Id = 'AutoRun'; Label = 'Kapat' }
Chk_Posture
$p = Find-F 'posture'
Assert-Eq $p.Title 'Sertleştirme ayarlarından 1 tanesi uygulanmamış' 'yineleme yok: eylemi ayar olan bulgu kapsanır'
Assert-True ($p.Detail -match '^Kapsam %60 \(3/5\)\. Eksik: Ayar Llmnr\.' -and $p.Detail -notmatch 'AutoRun') 'yineleme yok: ayrıntıda AutoRun geçmez, kapsam aynı kalır'
Assert-True ($null -eq $p.Fix) 'yineleme yok: kalan ayar düzey 2 ise tek tıklık düzeltme yok'
Assert-Eq $p.Action.Page 'security' 'yineleme yok: yine de Güvenlik sayfasına yönlendirir'
# Fix.Ids ile sunulan ayar da kapsanır (np-* biçimi)
New-Scenario1
Add-Finding 'np-AutoRun' 'sec' 'info' 'AutoRun' '' $null 2 (New-TweakFix @('AutoRun') 'Uygula')
Chk_Posture
Assert-Eq (Find-F 'posture').Title 'Sertleştirme ayarlarından 1 tanesi uygulanmamış' 'yineleme yok: düzeltmesi ayar olan bulgu kapsanır'
# bekleyenlerin hepsi başka bulgularda ise posture bulgusu hiç çıkmaz
New-Scenario1
Add-Finding 'autorun' 'sec' 'info' 'a' '' @{ Kind = 'Tweak'; Id = 'AutoRun'; Label = 'Kapat' }
Add-Finding 'llmnr' 'sec' 'info' 'b' '' @{ Kind = 'Tweak'; Id = 'Llmnr'; Label = 'Kapat' }
Chk_Posture
Assert-True ($null -eq (Find-F 'posture')) 'hepsi başka bulgularda: posture çıkmaz'
Assert-True ($null -ne (Find-F 'posture-prv')) 'hepsi başka bulgularda: gizlilik bulgusu bağımsızdır'

# her şey yerinde
New-Scenario1
foreach ($k in @($script:Pend.Keys)) { $script:Pend[$k] = 0 }
Chk_Posture
$p = Find-F 'posture'
Assert-True ($null -ne $p -and $p.Status -eq 'ok' -and $p.Weight -eq 0) 'her şey yerinde: ok bulgusu, puan etkisi yok'
Assert-Eq $p.Title 'Sertleştirme ayarları yerinde' 'her şey yerinde: başlık'
Assert-Eq $p.Detail 'Denetlenen 5 ayarın hepsi uygulanmış (kapsam %100).' 'her şey yerinde: ayrıntı'
Assert-True ($null -eq (Find-F 'posture-prv')) 'her şey yerinde: gizlilik bulgusu yok'
Assert-Eq $script:Findings.Count 1 'her şey yerinde: tek bulgu'
# her şey yerinde ama isteğe bağlı (düzey 3) ayar bekliyor
New-Scenario1
foreach ($k in @($script:Pend.Keys)) { $script:Pend[$k] = 0 }
$script:Pend['NetBiosOff'] = 1
Chk_Posture
$p = Find-F 'posture'
Assert-True ($p.Status -eq 'ok' -and $p.Detail -match 'İsteğe bağlı 1 ayar daha var') 'her şey yerinde: isteğe bağlı ayar notu'

# ölçülebilir ayar yok
Reset-Cat
Chk_Posture
Assert-Eq $script:Findings.Count 0 'ölçülebilir ayar yok: bulgu yok'
# yalnızca gizlilik ayarları ölçülebiliyorsa temel kapsam yok: yalnızca gizlilik bulgusu da çıkmaz
Reset-Cat
Add-Cat 'Telemetry' 1; $script:Pend['Telemetry'] = 1
Chk_Posture
Assert-Eq $script:Findings.Count 0 'yalnızca gizlilik ayarı ölçülüyorsa kapsam bulgusu çıkmaz'

# beş ve fazla eksik: uyarı, 5 puan; düzeltme yalnızca düzey 1
Reset-Cat
foreach ($key in @($tmap.Order)) {
    if ($tmap.ById[$key].Theme -eq 'prv') { continue }
    $lv = 1
    if ($key -in @('Llmnr', 'Lockout')) { $lv = 2 }
    if ($key -eq 'NetBiosOff') { $lv = 3 }
    Add-Cat $key $lv
    $script:Pend[$key] = 1
}
$nSec = $script:FakeCat.Count
Chk_Posture
$p = Find-F 'posture'
Assert-True ($p.Status -eq 'warn' -and $p.Weight -eq 5) 'çok eksik: uyarı, 5 puan'
$own = $nSec - 1
Assert-Eq $p.Title ('Sertleştirme ayarlarından ' + [string]($nSec - 1) + ' tanesi uygulanmamış') 'çok eksik: başlıkta sayı (düzey 3 hariç)'
Assert-True ($p.Detail -match 'Kapsam %0 \(0/' -and $p.Detail -match ' ve \d+ ayar daha') 'çok eksik: kapsam %0 ve "ve N ayar daha"'
$l1 = @($p.Fix.Ids)
Assert-True ($l1.Count -eq ($nSec - 3) -and ($l1 -notcontains 'Llmnr') -and ($l1 -notcontains 'Lockout') -and ($l1 -notcontains 'NetBiosOff')) 'çok eksik: düzeltme yalnızca düzey 1 ayarlar'
Assert-True ($p.Detail.Length -lt 300) 'çok eksik: ayrıntı 300 karakteri aşmaz'
# tam sınır: 4 eksik = bilgi, 5 eksik = uyarı
Reset-Cat
foreach ($s in @('Smb1', 'AutoRun', 'Llmnr', 'Lockout', 'GuestOff')) { Add-Cat $s 1; $script:Pend[$s] = 1 }
$script:Pend['GuestOff'] = 0
Chk_Posture
Assert-Eq (Find-F 'posture').Status 'info' 'sınır: 4 eksik bilgi'
$script:Findings.Clear(); $script:Pend['GuestOff'] = 1
Chk_Posture
Assert-Eq (Find-F 'posture').Status 'warn' 'sınır: 5 eksik uyarı'

# Windows'un koruduğu ayar eksik sayılmaz
New-Scenario1
$script:Blocked = @('AutoRun', 'Llmnr')
Chk_Posture
$p = Find-F 'posture'
Assert-True ($null -ne $p -and $p.Status -eq 'ok') 'engelli ayarlar eksik sayılmaz: kalan hepsi uygulanmışsa ok bulgusu'
Assert-True ($p.Detail -match '^Denetlenen 3 ayarın hepsi uygulanmış \(kapsam %100\)\.' -and $p.Detail -match '2 ayarı Windows koruduğu için değiştirilemiyor; bunlar sayıya katılmadı') 'engelli ayarlar: ayrıntı engelli sayısını söyler'
$script:Blocked = @()

# =====================================================================
#  6) rapor bölümü
# =====================================================================
New-Scenario1
$sec = Get-PostureReportSection
Assert-Eq $sec.Title 'Güvenlik duruşu ve standart eşlemesi' 'rapor: bölüm başlığı'
Assert-Eq ($sec.Headers -join '|') 'Konu|Ayar|Durum|İlgili başlıklar' 'rapor: sütunlar'
Assert-Eq @($sec.Rows).Count 10 'rapor: sekiz ayar + özet + not'
$r0 = @($sec.Rows)[0]
Assert-Eq (@($r0) -join '|') ('Ağ ve uzaktan erişim|Ayar Smb1|Uygulanmış|' + (Format-PostureRefs $tmap.ById['Smb1'])) 'rapor: ilk satır konu, ayar, durum, başvurular'
$r1 = @($sec.Rows)[1]
Assert-Eq $r1[2] 'Uygulanmamış' 'rapor: bekleyen ayar durumu'
$rs = @($sec.Rows)[8]
Assert-True ($rs[0] -eq 'Özet' -and $rs[1] -match 'Kapsam: %60 \(3/5') 'rapor: özet satırı'
$rn = @($sec.Rows)[9]
Assert-True ($rn[0] -eq 'Not' -and $rn[1] -match 'sertifika, denetim sonucu ya da uygunluk beyanı değildir' -and $rn[1] -match 'NIS2' -and $rn[1] -match 'KVKK') 'rapor: yasal not ve kaynak çerçeveler'
$script:Blocked = @('AutoRun')
$sec2 = Get-PostureReportSection
Assert-Eq (@($sec2.Rows)[1][2]) 'Windows engelliyor' 'rapor: engelli ayar durumu'
$script:Blocked = @()
Reset-Cat
Assert-True ($null -eq (Get-PostureReportSection)) 'rapor: ölçülebilir ayar yoksa bölüm yok'
# her satırda dört hücre
New-Scenario1
foreach ($row in @((Get-PostureReportSection).Rows)) { Assert-Eq @($row).Count 4 'rapor: satırda dört hücre' }

# =====================================================================
#  7) sağlık taramasına bağlantı (derlenmiş betiğin metni)
# =====================================================================
$fnAll = Get-AstFunctions
$hf = @($fnAll | Where-Object { $_.Name -eq 'Get-HealthFindings' }) | Select-Object -Last 1
$ht = $hf.Extent.Text
Assert-True ($ht -match 'B = \{ Chk_Posture \}') 'tarama: Chk_Posture tam taramanın listesinde'
$posFull = $ht.IndexOf('Chk_Posture')
Assert-True ($posFull -gt $ht.IndexOf('Chk_BootTime') -and $posFull -gt $ht.IndexOf('if ($Level -eq ' + "'Full'" + ')')) 'tarama: Chk_Posture tam taramanın sonunda'
Assert-True ($ht.IndexOf('Set-FindingStd') -gt $ht.IndexOf('Resolve-FindingFix')) 'tarama: standart başlıkları düzeltmeler türetildikten sonra yazılır'
$quickPart = $ht.Substring(0, $ht.IndexOf('if ($Level -eq ' + "'Full'" + ')'))
Assert-True ($quickPart -notmatch 'Chk_Posture') 'tarama: hızlı taramada Chk_Posture yok'
$jr = @($fnAll | Where-Object { $_.Name -eq 'Job_Report' }) | Select-Object -Last 1
Assert-True ($jr.Extent.Text -match 'Get-PostureReportSection') 'rapor işi: güvenlik duruşu bölümünü ekler'
# çekirdek: arka plan çalışma alanları da bu işlevleri bulur (çekirdek metninde tanımlı olmalı)
$coreStart = $srcText.IndexOf('$CoreCode = {')
$coreEnd = $srcText.IndexOf('$script:CoreText = $CoreCode.ToString()')
Assert-True ($coreStart -ge 0 -and $coreEnd -gt $coreStart) 'çekirdek sınırları bulundu'
$coreText = $srcText.Substring($coreStart, $coreEnd - $coreStart)
foreach ($fnName in @('Chk_Posture', 'Set-FindingStd', 'Get-PostureCoverage', 'Get-PostureReportSection', 'Get-PostureForFinding', 'Format-PostureRefs')) {
    Assert-True ($coreText -match ('function ' + [regex]::Escape($fnName) + '\b')) ('çekirdek: ' + $fnName + ' çekirdekte tanımlı')
}

# =====================================================================
#  8) Çözüm Merkezi > Sorunlar: Uzman kipinde standart satırı
# =====================================================================
$script:UiState = @{ Page = 'solve'; Mode = 'Expert' }
$script:SlTab = 'scan'
$script:H_FixOne = { }
$script:H_ScAct = { }
$ui = @{ sl_List = (New-FakeCtl); sl_Foot = (New-FakeCtl) }
function New-Fnd([string]$Id, [string]$Title, [string]$Detail, [string]$Std = '') {
    $f = @{ Id = $Id; Cat = 'sec'; Status = 'warn'; Title = $Title; Detail = $Detail; Action = $null; Weight = 5; Fix = $null }
    if ($Std -ne '') { $f.Std = $Std }
    return $f
}
function Get-Rows { return @($ui.sl_List.Children | Where-Object { $null -ne $_.Vars }) }
$stdLine = 'CIS v8 4.8  ·  NIST 800-53 CM-7'
$script:Health = @{ Score = @{ All = 80 }; Findings = @(
    (New-Fnd 'a1' 'Birinci' 'Ayrıntı bir.' $stdLine),
    (New-Fnd 'a2' 'İkinci' 'Ayrıntı iki.'),
    (New-Fnd 'a3' 'Üçüncü' ('x' * 400) $stdLine)
) }
Render-SlScan
$rows = Get-Rows
$d = @{}; foreach ($r in $rows) { $d[[string]$r.Vars.Title] = [string]$r.Vars.Detail }
Assert-Eq $rows.Count 3 'Uzman kipi: üç satır'
Assert-Eq $d['Birinci'] ("Ayrıntı bir.`r`nStandartlar: " + $stdLine) 'Uzman kipi: eşlenmiş bulguda Standartlar satırı eklenir'
Assert-Eq $d['İkinci'] 'Ayrıntı iki.' 'Uzman kipi: eşlemesi olmayan bulguda satır eklenmez'
Assert-True ($d['Üçüncü'].StartsWith(('x' * 297) + '...') -and $d['Üçüncü'].EndsWith("`r`nStandartlar: " + $stdLine)) 'Uzman kipi: uzun ayrıntı kısaltılır, standart satırı kesilmez'
# kullanıcı kipinde satır yok
$script:UiState.Mode = 'User'
$ui.sl_List.Children.Clear()
Render-SlScan
$d2 = @{}; foreach ($r in (Get-Rows)) { $d2[[string]$r.Vars.Title] = [string]$r.Vars.Detail }
Assert-Eq $d2['Birinci'] 'Ayrıntı bir.' 'Kullanıcı kipi: Standartlar satırı yok'
Assert-True (($d2.Values | Where-Object { $_ -match 'Standartlar' }).Count -eq 0) 'Kullanıcı kipi: hiçbir satırda yok'
# nesne biçimindeki bulgu da okunur
$script:UiState.Mode = 'Expert'
$ui.sl_List.Children.Clear()
$script:Health = @{ Score = @{ All = 80 }; Findings = @([pscustomobject]@{ Id = 'o1'; Cat = 'sec'; Status = 'warn'; Title = 'Nesne'; Detail = 'D'; Action = $null; Weight = 5; Fix = $null; Std = 'ISO 27001 A.8.9' }) }
Render-SlScan
Assert-Eq (@(Get-Rows)[0].Vars.Detail) "D`r`nStandartlar: ISO 27001 A.8.9" 'Uzman kipi: nesne biçimindeki bulgunun Std alanı da okunur'

# kip değişince açık "Sorunlar" sekmesi yeniden çizilir
function Render-SlScan { $script:ScanRenders++ }
function Render-SlPc { $script:PcRenders++ }
function Render-SlPrep { $script:PrepRenders++ }
$script:ScanRenders = 0; $script:PcRenders = 0; $script:PrepRenders = 0
$script:PcInfo = $null; $script:PrepState = $null
$script:Health = @{ Score = @{ All = 90 }; Findings = @() }
$script:SlTab = 'scan'; $script:UiState.Page = 'solve'
Update-PageMode_solve
Assert-Eq $script:ScanRenders 1 'kip değişimi: Sorunlar sekmesi yeniden çizilir'
$script:Health = $null
Update-PageMode_solve
Assert-Eq $script:ScanRenders 1 'kip değişimi: tarama yoksa çizilmez'
$script:Health = @{ Score = @{ All = 90 }; Findings = @() }
$script:UiState.Page = 'optimize'
Update-PageMode_solve
Assert-Eq $script:ScanRenders 1 'kip değişimi: başka sayfadayken çizilmez'
$script:UiState.Page = 'solve'; $script:SlTab = 'disk'
Update-PageMode_solve
Assert-Eq $script:ScanRenders 1 'kip değişimi: başka sekme açıkken Sorunlar çizilmez'
$script:SlTab = 'pc'; $script:PcInfo = @{ X = 1 }
Update-PageMode_solve
Assert-True ($script:PcRenders -eq 1 -and $script:ScanRenders -eq 1) 'kip değişimi: Bilgisayarım sekmesi eskisi gibi çizilir'
Remove-Item function:Render-SlScan, function:Render-SlPc, function:Render-SlPrep

Show-Result
