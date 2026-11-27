. "$PSScriptRoot/lib.ps1"
# Çözüm Merkezi "Kalıcı silme" sekmesi (mods\125_solve_erase.ps1): sürücü ve disk satırları, onay metinleri, işlem planları, sonuç gösterimi,
# elle yazdırılan onay ve iş başlatma. İşlerin kendisi t_wipe_jobs, t_wipe_raw ve t_secdel dosyalarında sınanır; burada sahte denetimler ve sahte Start-Async kullanılır.
Import-Fn 'Format-Size', 'Format-Duration', 'Get-JsonProp', 'Get-RcVolumeName', 'Get-RcDiskName', 'New-Choice', 'Set-ComboChoices', 'Select-ComboKey', 'Get-ComboKey',
    'Get-WipeMethodKey', 'Get-WipeModes', 'Get-WipeMethodName', 'Get-WipeMethodList', 'Get-WipeVerifyKey', 'Get-WipeVerifyList', 'Get-WipeVerifyName',
    'Get-WipeAfterKey', 'Get-WipeAfterList', 'Get-WipeAfterName', 'Format-WipeEta', 'Get-WipeRate', 'Get-WipeEstimate', 'ConvertTo-WipeFold', 'Test-WipeTyped',
    'Get-WipeReserve', 'Test-WipeDiskAllowed', 'Test-WipePartAllowed', 'Get-WipeExpect',
    'Get-ErOptions', 'Get-ErDriveModels', 'Get-ErFreeWork', 'Get-ErFreeConfirmText', 'Get-ErGapEstimate', 'Get-ErPartTypeName', 'Get-ErDiskModels', 'New-ErRawPlan',
    'Get-ErResultModel', 'Get-ErFreeResultModel', 'Get-ErTrimResultModel', 'Get-ErRawResultModel', 'Get-ErSecureResultModel', 'Show-SecureDeleteResult', 'Get-ErRecoverKey',
    'Invoke-ErAction', 'Add-ErRow', 'Render-SlErase', 'Show-TypedConfirm', 'Find-ErDisk', 'Start-ErFree', 'Start-ErTrim', 'Start-ErRaw', 'Invoke-ErRawJob',
    'Complete-ErResult', 'Complete-ErFree', 'Complete-ErTrim', 'Complete-ErRaw', 'Select-ErOption', 'Init-SlErase'
Import-Var 'ErPendDrive', 'ErLast', 'ErPend', 'ErOpts', 'ErLoading', 'ErTypedExpect', 'ErTypedAct', 'H_ErAct'
. "$PSScriptRoot/uifake.ps1"

$MiB = [double]1048576
$GB = [double]1073741824

$script:ExtProblem = ''
function Get-ExtProblem([string]$Name) { return $script:ExtProblem }
$script:ChipCalls = New-Object System.Collections.ArrayList
$script:ChipOk = $false
function Select-TabChip([string]$P, [string]$Key) { [void]$script:ChipCalls.Add($P + ':' + $Key); return $script:ChipOk }
function Set-SlTab([string]$Tab) { [void]$script:ChipCalls.Add('tab:' + $Tab) }
$script:RcSelKey = ''
$script:RcPartCache = @{}

# --- örnek veriler ---
function New-Phys([hashtable]$Over = @{}) {
    $m = @{ Number = 1; Name = 'Örnek Disk'; Size = [double](32 * $GB); UniqueId = 'UID1'; Serial = 'SN1'; Bus = 'USB'; Media = 'Unspecified'; Style = 'GPT'
        IsSystem = $false; IsBoot = $false; Offline = $false; ReadOnly = $false; Clustered = $false; Pool = $false; Sector = 512
        Letters = @('F:'); Roles = @()
        Parts = @(
            @{ Number = 1; Offset = [double]$MiB; Size = [double](10 * $GB); Letter = 'F:'; Type = 'Basic'; IsSystem = $false; IsBoot = $false; IsActive = $false; Fs = 'NTFS'; Label = 'Veri' },
            @{ Number = 2; Offset = [double](12 * $GB); Size = [double](8 * $GB); Letter = ''; Type = 'Recovery'; IsSystem = $false; IsBoot = $false; IsActive = $false; Fs = ''; Label = '' }) }
    foreach ($k in $Over.Keys) { $m[$k] = $Over[$k] }
    return $m
}
$dkSys = New-Phys @{ Number = 0; Name = 'Sistem SSD'; Size = [double](512 * $GB); Bus = 'NVMe'; Media = 'SSD'; IsSystem = $true; IsBoot = $true; Letters = @('C:')
    Parts = @(@{ Number = 1; Offset = [double]$MiB; Size = [double](100 * $MiB); Letter = ''; Type = 'System'; IsSystem = $true; IsBoot = $false; Fs = 'FAT32'; Label = '' },
        @{ Number = 2; Offset = [double](101 * $MiB); Size = [double](500 * $GB); Letter = 'C:'; Type = 'Basic'; IsSystem = $false; IsBoot = $true; Fs = 'NTFS'; Label = 'Windows' }) }
$dkUsb = New-Phys @{}
$dkBlank = New-Phys @{ Number = 2; Name = 'Boş Disk'; Size = [double](500 * $GB); Bus = 'SATA'; Media = 'HDD'; Style = 'RAW'; Letters = @(); Parts = @() }
$dkApp = New-Phys @{ Number = 3; Name = 'Uygulama Diski'; Roles = @('E: sürücüsü: Multimizer bu sürücüde çalışıyor'); Letters = @('E:') }
$dkZero = New-Phys @{ Number = 4; Name = 'Boyutsuz'; Size = [double]0; Parts = @() }
$dkSsd = New-Phys @{ Number = 5; Name = 'Harici SSD'; Size = [double](1024 * $GB); Bus = 'USB'; Media = 'SSD'; Letters = @(); Parts = @() }
$dkFull = New-Phys @{ Number = 6; Name = 'Dolu Disk'; Size = [double](64 * $MiB); Bus = 'SATA'; Media = 'HDD'; Letters = @()
    Parts = @(@{ Number = 1; Offset = [double]$MiB; Size = [double](8 * $MiB); Letter = ''; Type = 'Basic'; IsSystem = $false; IsBoot = $false; Fs = ''; Label = '' },
        @{ Number = 2; Offset = [double](20 * $MiB); Size = [double](10 * $MiB); Letter = ''; Type = 'Basic'; IsSystem = $false; IsBoot = $false; Fs = ''; Label = '' },
        @{ Number = 3; Offset = [double](50 * $MiB); Size = [double](8 * $MiB); Letter = ''; Type = 'Basic'; IsSystem = $false; IsBoot = $false; Fs = ''; Label = '' }) }
$dkTight = New-Phys @{ Number = 7; Name = 'Sıkışık Disk'; Size = [double](100 * $MiB); Letters = @()
    Parts = @(@{ Number = 1; Offset = [double]$MiB; Size = [double](98 * $MiB); Letter = ''; Type = 'Basic'; IsSystem = $false; IsBoot = $false; Fs = ''; Label = '' }) }

# =====================================================================
#  1) seçenekler
# =====================================================================
$script:ErOpts = @{ Method = 'random'; Verify = 'sample'; After = 'none' }
$o = Get-ErOptions
Assert-True ($o.Method -eq 'random' -and $o.Verify -eq 'sample' -and $o.After -eq 'none') 'seçenekler: varsayılanlar'
$script:ErOpts = @{ Method = 'DOD3'; Verify = 'full'; After = 'exfat' }
$o = Get-ErOptions
Assert-True ($o.Method -eq 'dod3' -and $o.Verify -eq 'full' -and $o.After -eq 'exfat') 'seçenekler: büyük harf önemsiz'
$script:ErOpts = @{ Method = 'xx'; Verify = ''; After = 'ext9' }
$o = Get-ErOptions
Assert-True ($o.Method -eq 'random' -and $o.Verify -eq 'sample' -and $o.After -eq 'none') 'seçenekler: geçersiz değerler varsayılana döner'
$script:ErOpts = @{ Method = 'random'; Verify = 'sample'; After = 'none' }

# =====================================================================
#  2) sürücü satırları ve metinleri
# =====================================================================
$disks = @(
    @{ Drive = 'C:'; Type = 'Fixed'; State = 'none'; Label = 'Windows'; Fs = 'NTFS'; Size = [double](255 * $GB); Free = [double](100 * $GB); Media = 'SSD'; Bus = 'NVMe'; DiskName = 'A' },
    @{ Drive = 'D:'; Type = 'Fixed'; State = 'locked'; Label = 'Veri'; Fs = 'NTFS'; Size = [double](1024 * $GB); Free = [double](500 * $GB); Media = 'HDD'; Bus = 'SATA'; DiskName = 'B' },
    @{ Drive = 'E:'; Type = 'Removable'; State = 'none'; Label = 'Bellek'; Fs = 'exFAT'; Size = [double](32 * $GB); Free = [double](10 * $GB); Media = 'Unspecified'; Bus = 'USB'; DiskName = 'C' },
    @{ Drive = 'F:'; Type = 'Fixed'; State = 'none'; Label = ''; Fs = ''; Size = [double]0; Free = [double]0; Media = ''; Bus = ''; DiskName = '' },
    @{ Drive = 'G:'; Type = 'Fixed'; State = 'none'; Label = 'Dolu'; Fs = 'NTFS'; Size = [double](1024 * $GB); Free = [double]$MiB; Media = 'HDD'; Bus = 'SATA'; DiskName = 'D' },
    @{ Drive = 'H:'; Type = 'Fixed'; State = 'none'; Label = 'Arşiv'; Fs = 'NTFS'; Size = [double](2048 * $GB); Free = [double](1024 * $GB); Media = 'HDD'; Bus = 'SATA'; DiskName = 'E' },
    @{ Drive = 'I:'; Type = 'Fixed'; State = 'none'; Label = 'Harici SSD'; Fs = 'NTFS'; Size = [double](512 * $GB); Free = [double](200 * $GB); Media = 'SSD'; Bus = 'USB'; DiskName = 'F' }
)
$mm = Get-ErDriveModels $disks 'C:'
Assert-Eq @($mm).Count 4 'sürücüler: kilitli, dosya sistemsiz ve dolu sürücüler listelenmez'
Assert-Eq (@($mm | ForEach-Object { $_.Drive }) -join ',') 'C:,E:,H:,I:' 'sürücüler: listelenen sürücüler'
Assert-True ($mm[0].IsOs -eq $true -and $mm[0].BrCol -eq 'BrWarn' -and $mm[0].Detail -match 'tam güvence vermez' -and $mm[0].Detail -match 'Windows sürücüsünde') 'sürücüler: C: SSD ve Windows uyarıları'
Assert-True ($mm[0].Trim -eq $true) 'sürücüler: SSD için TRIM düğmesi'
Assert-True ($mm[1].Detail -match 'yavaş olabilir' -and $mm[1].BrCol -eq 'BrInfo' -and $mm[1].Trim -eq $false) 'sürücüler: USB belleğin notu, TRIM yok'
Assert-True ($mm[2].BrCol -eq 'BrInfo' -and $mm[2].Detail -notmatch 'SSD' -and $mm[2].Detail -notmatch 'yavaş' -and $mm[2].Trim -eq $false) 'sürücüler: HDD satırı sade'
Assert-True ($mm[3].Detail -match 'yavaş olabilir' -and $mm[3].Detail -notmatch 'tam güvence' -and $mm[3].Trim -eq $false) 'sürücüler: harici USB SSD icin SSD notu ve TRIM yok'
Assert-True ($mm[0].Title -match '^C:  Windows') 'sürücüler: başlık sürücü adını taşır'
Assert-Eq $mm[2].Free ([double](1024 * $GB)) 'sürücüler: boş alan aktarılır'
$mEmpty = Get-ErDriveModels @() 'C:'
Assert-Eq $mEmpty.Count 0 'sürücüler: boş liste'
$mEmpty = Get-ErDriveModels $null 'C:'
Assert-Eq $mEmpty.Count 0 'sürücüler: null liste'

Assert-Eq (Get-ErFreeWork @{ Free = [double](100 * $GB); Size = [double](255 * $GB); IsOs = $true }) ([double](100 * $GB) - [math]::Floor(255 * $GB * 0.03)) 'iş miktarı: Windows sürücüsü payı'
Assert-Eq (Get-ErFreeWork @{ Free = [double](100 * $MiB); Size = [double](255 * $GB); IsOs = $false }) 0 'iş miktarı: pay boş alandan büyükse sıfır'

$cf1 = Get-ErFreeConfirmText @{ Drive = 'C:'; Free = [double](100 * $GB); Size = [double](255 * $GB); Media = 'SSD'; Bus = 'NVMe'; IsOs = $true }
Assert-True ($cf1 -match 'C: sürücüsünün boş alanı' -and $cf1 -match '%3' -and $cf1 -match 'SSD' -and $cf1 -match 'TRIM' -and $cf1 -match 'program kurmayın' -and $cf1 -match 'iptal edebilirsiniz') 'onay metni: Windows SSD'
Assert-True ($cf1 -match 'Yöntem: tek geçiş rastgele' -and $cf1 -match 'Tahmini süre: yaklaşık' -and $cf1 -match 'Doğrulama: işe başlarken') 'onay metni: varsayılan yöntem, süre ve doğrulama'
$cf2 = Get-ErFreeConfirmText @{ Drive = 'H:'; Free = [double](1024 * $GB); Size = [double](2048 * $GB); Media = 'HDD'; Bus = 'SATA'; IsOs = $false }
Assert-True ($cf2 -match '%1' -and $cf2 -notmatch 'SSD' -and $cf2 -notmatch 'program kurmayın' -and $cf2 -match 'dokunulmaz') 'onay metni: HDD'
$cf3 = Get-ErFreeConfirmText @{ Drive = 'H:'; Free = [double](1024 * $GB); Size = [double](2048 * $GB); Media = 'HDD'; Bus = 'SATA'; IsOs = $false } @{ Method = 'dod3'; Verify = 'none' }
Assert-True ($cf3 -match 'Yöntem: 3 geçiş' -and $cf3 -notmatch 'Doğrulama: işe başlarken') 'onay metni: üç geçiş ve doğrulamasız'
Assert-True ((Get-ErFreeConfirmText @{ Drive = 'H:'; Free = [double](1024 * $GB); Size = [double](2048 * $GB); Media = 'HDD'; Bus = 'SATA'; IsOs = $false } @{ Method = 'dod3'; Verify = 'sample' }) -match 'yaklaşık .* . ') 'onay metni: üç geçişte süre aralığı yazılır'

# =====================================================================
#  3) ayrılmamış alan tahmini ve bölüm türleri
# =====================================================================
$g = Get-ErGapEstimate $dkFull
Assert-True ($g.Bytes -eq [double](31 * $MiB) -and $g.Count -eq 2) 'boşluk tahmini: 64 MiB diskte iki boşluk (9–20, 30–50 MiB)'
$g = Get-ErGapEstimate $dkBlank
Assert-True ($g.Count -eq 1 -and $g.Bytes -eq [double](500 * $GB) - [double](2 * $MiB)) 'boşluk tahmini: bölümsüz diskte tamamı (uçlarda 1 MiB hariç)'
$g = Get-ErGapEstimate $dkTight
Assert-True ($g.Count -eq 0 -and $g.Bytes -eq 0) 'boşluk tahmini: 8 MiB altindaki kucuk bosluklar sayilmaz'
$g = Get-ErGapEstimate $dkUsb
Assert-True ($g.Count -eq 2 -and $g.Bytes -gt [double](13 * $GB)) 'boşluk tahmini: bölümler arası ve sondaki boşluk'
$g = Get-ErGapEstimate (New-Phys @{ Size = [double](10 * $MiB); Parts = @() })
Assert-True ($g.Count -eq 0 -and $g.Bytes -eq 0) 'boşluk tahmini: çok küçük disk'
# sırasız girdiler: [40,50) [1,21) [35,45) çakışır, null ve boyutsuz girdi atlanır; boşluklar 21-35 (14 MiB) ve 50-99 (49 MiB)
$gOver = Get-ErGapEstimate (New-Phys @{ Size = [double](100 * $MiB); Parts = @(
    @{ Number = 2; Offset = [double](40 * $MiB); Size = [double](10 * $MiB) }, @{ Number = 1; Offset = [double](1 * $MiB); Size = [double](20 * $MiB) }, @{ Number = 3; Offset = [double](35 * $MiB); Size = [double](10 * $MiB) }, $null, @{ Number = 4; Offset = [double](90 * $MiB); Size = [double]0 }) })
Assert-True ($gOver.Count -eq 2 -and $gOver.Bytes -eq [double](14 * $MiB + 49 * $MiB)) 'boşluk tahmini: sırasız, çakışan ve boş bölüm girdileri'
$gSmall = Get-ErGapEstimate (New-Phys @{ Size = [double](100 * $MiB); Parts = @(@{ Number = 1; Offset = [double](1 * $MiB); Size = [double](20 * $MiB) }, @{ Number = 2; Offset = [double](25 * $MiB); Size = [double](74 * $MiB) }) })
Assert-True ($gSmall.Count -eq 0 -and $gSmall.Bytes -eq 0) 'boşluk tahmini: 8 MiB altı aradaki boşluk sayılmaz'

Assert-Eq (Get-ErPartTypeName 'System') 'EFI sistem bölümü' 'bölüm türü: EFI'
Assert-Eq (Get-ErPartTypeName 'Recovery') 'Windows kurtarma bölümü' 'bölüm türü: kurtarma'
Assert-Eq (Get-ErPartTypeName 'Reserved') 'Microsoft ayrılmış bölüm' 'bölüm türü: ayrılmış'
Assert-Eq (Get-ErPartTypeName ' Basic ') 'veri bölümü' 'bölüm türü: veri'
Assert-Eq (Get-ErPartTypeName 'IFS') 'veri bölümü' 'bölüm türü: IFS'
Assert-Eq (Get-ErPartTypeName 'Logical') 'mantıksal bölüm' 'bölüm türü: mantıksal'
Assert-Eq (Get-ErPartTypeName 'Extended') 'genişletilmiş bölüm' 'bölüm türü: genişletilmiş'
Assert-Eq (Get-ErPartTypeName 'XBOX') 'oyun bölümü' 'bölüm türü: oyun'
Assert-Eq (Get-ErPartTypeName 'Bilinmeyen') '' 'bölüm türü: bilinmeyen'

# =====================================================================
#  4) disk ve bölüm satırları
# =====================================================================
$dm = Get-ErDiskModels @($dkSys, $dkUsb, $dkBlank, $dkApp, $dkZero, $null)
Assert-Eq @($dm).Count 4 'disk satırları: boyutsuz ve boş girdiler atlanır'
Assert-Eq (@($dm | ForEach-Object { $_.Number }) -join ',') '0,1,2,3' 'disk satırları: sıra'
$d0 = $dm[0]
Assert-True ($d0.Blocked -match 'Windows bu diskte çalışıyor' -and $d0.Btn1 -eq '' -and $d0.Btn2 -eq '' -and @($d0.Parts).Count -eq 0 -and $d0.BrCol -eq 'BrWarn' -and $d0.Detail -match 'yalnızca sürücülerin boş alanı') 'disk satırları: sistem diski kilitli, düğme yok'
$d1 = $dm[1]
Assert-True ($d1.Blocked -eq '' -and $d1.Btn1 -eq 'Ayrılmamış alanı sil' -and $d1.Btn2 -eq 'Diski tamamen sil' -and $d1.BrCol -eq 'BrInfo') 'disk satırları: USB disk düğmeleri'
Assert-True ($d1.Title -match '^Disk 1  Örnek Disk' -and $d1.Title -match 'USB') 'disk satırları: başlık'
Assert-True ($d1.Detail -match '^GPT' -and $d1.Detail -match '2 bölüm' -and $d1.Detail -match 'sürücüler: F:' -and $d1.Detail -match 'ayrılmamış alan: yaklaşık') 'disk satırları: ayrıntı'
Assert-Eq @($d1.Parts).Count 2 'disk satırları: iki bölüm'
Assert-True ($d1.Parts[0].Number -eq 1 -and $d1.Parts[0].Title -match '^Bölüm 1  ·  F:  Veri  ·  NTFS' -and $d1.Parts[0].Btn1 -eq 'Bölümü sil' -and $d1.Parts[0].Detail -eq 'Veri bölümü.') 'bölüm satırı: harfli bölüm'
Assert-True ($d1.Parts[1].Title -match 'sürücü harfi yok' -and $d1.Parts[1].Detail -eq 'Windows kurtarma bölümü.') 'bölüm satırı: harfsiz bölüm'
$d2 = $dm[2]
Assert-True ($d2.Btn1 -eq 'Ayrılmamış alanı sil' -and $d2.Detail -match 'bölüm tablosu yok' -and $d2.Detail -match 'bölüm yok' -and @($d2.Parts).Count -eq 0) 'disk satırları: bölümsüz disk'
Assert-True ($dm[3].Blocked -match 'Multimizer' -and $dm[3].Btn2 -eq '') 'disk satırları: Multimizer diski kilitli'
$dmSys = Get-ErDiskModels @((New-Phys @{ Parts = @(@{ Number = 1; Offset = [double]$MiB; Size = [double](100 * $MiB); Letter = ''; Type = 'System'; IsSystem = $true; IsBoot = $false; Fs = ''; Label = '' }, @{ Number = 2; Offset = [double](200 * $MiB); Size = [double](10 * $GB); Letter = 'F:'; Type = 'Basic'; IsSystem = $false; IsBoot = $false; Fs = 'NTFS'; Label = '' }) }))
Assert-True ($dmSys[0].Parts[0].Blocked -match 'Windows.a ait' -and $dmSys[0].Parts[0].Btn1 -eq '' -and $dmSys[0].Parts[0].BrCol -eq 'BrWarn') 'bölüm satırı: Windows bölümünde düğme yok'
Assert-True ($dmSys[0].Parts[1].Btn1 -eq 'Bölümü sil') 'bölüm satırı: diğer bölüm silinebilir'
$dmSort = Get-ErDiskModels @((New-Phys @{ Parts = @(@{ Number = 2; Offset = [double](12 * $GB); Size = [double](8 * $GB); Letter = ''; Type = 'Basic'; IsSystem = $false; IsBoot = $false; Fs = ''; Label = '' }, @{ Number = 1; Offset = [double]$MiB; Size = [double](10 * $GB); Letter = ''; Type = 'Basic'; IsSystem = $false; IsBoot = $false; Fs = ''; Label = '' }) }))
Assert-Eq (@($dmSort[0].Parts | ForEach-Object { $_.Number }) -join ',') '1,2' 'bölüm satırları: konuma göre sıralı'
$dmEmpty = Get-ErDiskModels @()
Assert-Eq $dmEmpty.Count 0 'disk satırları: boş liste'
$dmTight = Get-ErDiskModels @($dkTight)
Assert-True ($dmTight[0].Btn1 -eq '' -and $dmTight[0].Btn2 -eq 'Diski tamamen sil' -and $dmTight[0].Detail -notmatch 'ayrılmamış alan') 'disk satırları: boşluk yoksa ayrılmamış alan düğmesi yok'

# =====================================================================
#  5) işlem planı
# =====================================================================
$opt = @{ Method = 'random'; Verify = 'sample'; After = 'none' }
$pD = New-ErRawPlan 'Disk' $dkUsb 0 $opt
Assert-True ($pD.Ok -eq $true -and $pD.Expect -eq 'Disk 1' -and $pD.Title -eq 'Diski tamamen sil' -and $pD.OkText -eq 'Diski sil' -and $pD.Label -eq 'Disk 1 siliniyor') 'plan: tüm disk'
Assert-True ($pD.Params.Scope -eq 'Disk' -and $pD.Params.Disk -eq 1 -and $pD.Params.Part -eq 0 -and $pD.Params.Method -eq 'random' -and $pD.Params.Verify -eq 'sample' -and $pD.Params.After -eq 'none') 'plan: iş parametreleri'
Assert-True ($pD.Params.Expect.Size -eq $dkUsb.Size -and $pD.Params.Expect.Name -eq 'Örnek Disk' -and $pD.Params.Expect.UniqueId -eq 'UID1' -and $pD.Params.Expect.Serial -eq 'SN1') 'plan: onay anındaki kimlik'
Assert-True ($pD.Text -match 'tamamen silinecek' -and $pD.Text -match '\(F:\)' -and $pD.Text -match 'Geri getirilemez' -and $pD.Text -match 'Yöntem: tek geçiş rastgele; doğrulama: örnekler' -and $pD.Text -match 'Sonunda: boş' -and $pD.Text -match 'Tahmini süre' -and $pD.Text -match 'çıkarmayın') 'plan: tüm disk metni'
Assert-True ($pD.Text -match 'SSD ve USB' -and $pD.Text -match 'NIST SP 800-88') 'plan: USB belleğe SSD/USB notu'
Assert-Eq $pD.Bytes ([double](32 * $GB)) 'plan: bayt'
$pDx = New-ErRawPlan 'Disk' $dkBlank 0 @{ Method = 'dod3'; Verify = 'full'; After = 'ntfs' }
Assert-True ($pDx.Ok -eq $true -and $pDx.Params.After -eq 'ntfs' -and $pDx.Params.Method -eq 'dod3' -and $pDx.Text -match 'NTFS olarak biçimlenir' -and $pDx.Text -notmatch 'SSD ve USB') 'plan: HDD, 3 geçiş, NTFS sonrası; SSD/USB notu yok'
$pP = New-ErRawPlan 'Partition' $dkUsb 1 $opt
Assert-True ($pP.Ok -eq $true -and $pP.Expect -eq 'Disk 1 Bölüm 1' -and $pP.Title -eq 'Bölümü sil' -and $pP.Params.Part -eq 1 -and $pP.Label -eq 'Disk 1 bölüm 1 siliniyor') 'plan: bölüm'
Assert-True ($pP.Params.Expect.PartOffset -eq [double]$MiB -and $pP.Params.Expect.PartSize -eq [double](10 * $GB)) 'plan: bölümün konumu da kimliğe eklenir'
Assert-True ($pP.Text -match 'bölüm 1 \(F:\)' -and $pP.Text -match 'diğer bölümlerine dokunulmaz') 'plan: bölüm metni'
Assert-Eq $pP.Bytes ([double](10 * $GB)) 'plan: bölüm baytı'
$pU = New-ErRawPlan 'Unallocated' $dkFull 0 @{ Method = 'zero'; Verify = 'none'; After = 'ntfs' }
Assert-True ($pU.Ok -eq $true -and $pU.Expect -eq '' -and $pU.Title -eq 'Ayrılmamış alanı sil' -and $pU.OkText -eq 'Sil' -and $pU.Params.After -eq 'none') 'plan: ayrılmamış alan, bölümler varken yazdırma yok, sonra=boş zorunlu'
Assert-True ($pU.Bytes -eq [double](31 * $MiB) -and $pU.Text -match 'dokunulmaz' -and $pU.Text -match '1 MB korunur' -and $pU.Text -cnotmatch 'Sonunda:' -and $pU.Text -notmatch 'çıkarmayın') 'plan: ayrılmamış alan metni'
$pU2 = New-ErRawPlan 'Unallocated' $dkBlank 0 $opt
Assert-True ($pU2.Ok -eq $true -and $pU2.Expect -eq 'Disk 2' -and $pU2.Title -eq 'Diski ayrılmamış alan olarak sil' -and $pU2.Text -match 'Diskte hiç bölüm görünmüyor' -and $pU2.Text -match 'Silinen dosyalar sekmesinde') 'plan: hiç bölümü olmayan diskte ad yazdırılır ve uyarı eklenir'
$pU3 = New-ErRawPlan 'Unallocated' $dkTight 0 $opt
Assert-True ($pU3.Ok -eq $false -and $pU3.Why -match 'silinecek ayrılmamış alan yok') 'plan: boşluk yoksa reddedilir'
$pX = New-ErRawPlan 'Disk' $dkSys 0 $opt
Assert-True ($pX.Ok -eq $false -and $pX.Why -match 'Windows bu diskte') 'plan: sistem diski reddedilir'
$pX = New-ErRawPlan 'Unallocated' $dkApp 0 $opt
Assert-True ($pX.Ok -eq $false -and $pX.Why -match 'doğrudan yazılmaz') 'plan: korunan diskte ayrılmamış alan da reddedilir'
$pX = New-ErRawPlan 'Partition' $dkUsb 9 $opt
Assert-True ($pX.Ok -eq $false -and $pX.Why -match 'Bölüm bulunamadı') 'plan: olmayan bölüm'
$pX = New-ErRawPlan 'Partition' $dkSys 1 $opt
Assert-True ($pX.Ok -eq $false -and $pX.Why -match 'Windows bu diskte') 'plan: sistem diskinde hiçbir bölüm silinmez'
$dkEsp = New-Phys @{ Number = 9; Parts = @(@{ Number = 1; Offset = [double]$MiB; Size = [double](100 * $MiB); Letter = ''; Type = 'System'; IsSystem = $true; IsBoot = $false; Fs = ''; Label = '' }, @{ Number = 2; Offset = [double](200 * $MiB); Size = [double](10 * $GB); Letter = 'F:'; Type = 'Basic'; IsSystem = $false; IsBoot = $false; Fs = 'NTFS'; Label = '' }) }
$pX = New-ErRawPlan 'Partition' $dkEsp 1 $opt
Assert-True ($pX.Ok -eq $false -and $pX.Why -match 'Windows.a ait') 'plan: Windows bölümü reddedilir'
$pX = New-ErRawPlan 'Partition' $dkEsp 2 $opt
Assert-True ($pX.Ok -eq $true -and $pX.Params.Part -eq 2) 'plan: aynı diskteki veri bölümü silinebilir'
$pX = New-ErRawPlan 'Hepsi' $dkUsb 0 $opt
Assert-True ($pX.Ok -eq $false -and $pX.Why -match 'Bilinmeyen silme kapsamı') 'plan: bilinmeyen kapsam'
$pX = New-ErRawPlan 'Disk' $null 0 $opt
Assert-True ($pX.Ok -eq $false -and $pX.Why -match 'Disk bulunamadı') 'plan: disk yok'
$big = New-Phys @{ Number = 8; Name = 'Büyük'; Size = [double](100 * $GB); Letters = @(); Parts = @(@{ Number = 1; Offset = [double]$MiB; Size = [double](50 * $GB); Letter = ''; Type = 'Basic'; IsSystem = $false; IsBoot = $false; Fs = ''; Label = '' }) }
$pX = New-ErRawPlan 'Disk' $big 0 @{ Method = 'zero'; Verify = 'none'; After = 'fat32' }
Assert-True ($pX.Ok -eq $false -and $pX.Why -match 'FAT32 yalnızca 32 GB') 'plan: FAT32 32 GB üstü disk'
$pX = New-ErRawPlan 'Partition' $big 1 @{ Method = 'zero'; Verify = 'none'; After = 'fat32' }
Assert-True ($pX.Ok -eq $false -and $pX.Why -match 'FAT32') 'plan: FAT32 32 GB üstü bölüm'
$pX = New-ErRawPlan 'Unallocated' $big 0 @{ Method = 'zero'; Verify = 'none'; After = 'fat32' }
Assert-True ($pX.Ok -eq $true) 'plan: ayrılmamış alanda FAT32 seçeneği önemsiz'
$pSsd = New-ErRawPlan 'Disk' $dkSsd 0 $opt
Assert-True ($pSsd.Ok -eq $true -and $pSsd.Text -match 'NIST SP 800-88') 'plan: SSD notu'

# =====================================================================
#  6) sonuç modelleri
# =====================================================================
$m1 = Get-ErResultModel @{ Ok = $true; Drive = 'H:\'; Written = [double](5 * $GB); Canceled = $false; Error = '' }
Assert-True ($m1.BrCol -eq 'BrGood' -and $m1.Title -eq 'H:\ boş alanı temizlendi' -and $m1.Detail -match 'üzerine yazıldı' -and $m1.Toast -match 'temizlendi') 'boş alan sonucu: başarılı'
$m1b = Get-ErResultModel @{ Ok = $true; Kind = 'Free'; Drive = 'H:\'; Written = [double](5 * $GB); Method = 'dod3'; Verdict = @{ Level = 'ok'; Text = 'Doğrulandı: 384 / 384.' }; Trim = @{ Ok = $true; Error = '' } }
Assert-True ($m1b.BrCol -eq 'BrGood' -and $m1b.Detail -match '3 geçiş' -and $m1b.Detail -match 'Doğrulandı: 384' -and $m1b.Detail -match 'TRIM') 'boş alan sonucu: yöntem, kanarya ve TRIM'
$m1c = Get-ErResultModel @{ Ok = $true; Kind = 'Free'; Drive = 'H:\'; Written = [double]$GB; Verdict = @{ Level = 'warn'; Text = 'Eski veri kalmış.' }; Trim = @{ Ok = $false; Error = 'TRIM reddedildi' } }
Assert-True ($m1c.BrCol -eq 'BrWarn' -and $m1c.Detail -match 'Eski veri kalmış' -and $m1c.Detail -match 'TRIM gönderilemedi: TRIM reddedildi') 'boş alan sonucu: kanarya uyarısı ve TRIM hatası'
$m2 = Get-ErResultModel @{ Ok = $false; Drive = 'H:\'; Written = [double]$GB; Canceled = $true; Error = '' }
Assert-True ($m2.BrCol -eq 'BrWarn' -and $m2.Title -match 'iptal' -and $m2.Detail -match 'geçici dosyalar silindi') 'boş alan sonucu: iptal'
$m3 = Get-ErResultModel @{ Ok = $false; Drive = 'H:\'; Written = [double]0; Canceled = $false; Error = 'Sürücüde temizlenecek yeterli boş alan yok.' }
Assert-True ($m3.BrCol -eq 'BrBad' -and $m3.Detail -match 'yeterli boş alan' -and $m3.Title -match 'temizlenemedi') 'boş alan sonucu: hata'
$m4 = Get-ErResultModel @{ Ok = $false; Drive = 'H:\'; Written = [double]0; Canceled = $false; Error = '' }
Assert-True ($m4.Detail -match 'günlük') 'boş alan sonucu: nedensiz hata'

$t1 = Get-ErResultModel @{ Kind = 'Trim'; Ok = $true; Drive = 'C:'; Note = 'Windows bildirimleri kapalı.' }
Assert-True ($t1.BrCol -eq 'BrGood' -and $t1.Title -eq 'C: için TRIM gönderildi' -and $t1.Detail -match 'arka planda' -and $t1.Detail -match 'bildirimleri kapalı') 'TRIM sonucu: başarılı'
$t2 = Get-ErResultModel @{ Kind = 'Trim'; Ok = $false; Drive = 'C:'; Error = 'Sürücü desteklemiyor' }
Assert-True ($t2.BrCol -eq 'BrBad' -and $t2.Title -match 'gönderilemedi' -and $t2.Detail -eq 'Sürücü desteklemiyor') 'TRIM sonucu: hata'
$t3 = Get-ErResultModel @{ Kind = 'Trim'; Ok = $false; Drive = 'C:' }
Assert-True ($t3.Detail -match 'günlük') 'TRIM sonucu: nedensiz hata'

$rN = Get-ErResultModel @{ Kind = 'Raw'; Ok = $true; Nothing = $true; Scope = 'Unallocated'; Disk = 3; Notes = @('Ayrılmamış alan bulunamadı; yapılacak bir şey yok.') }
Assert-True ($rN.BrCol -eq 'BrInfo' -and $rN.Title -eq 'Disk 3 ayrılmamış alanı: yapılacak bir şey yok' -and $rN.Detail -match 'bulunamadı') 'ham silme sonucu: yapılacak bir şey yok'
$rO = Get-ErResultModel @{ Kind = 'Raw'; Ok = $true; Scope = 'Disk'; Disk = 2; Name = 'Boş Disk'; Written = [double]$GB; Method = 'random'; VerifyKind = 'full'; Verified = [double]$GB; AfterDone = 'NTFS olarak biçimlenir'; Letter = 'G:'; Seconds = [double]12; Notes = @() }
Assert-True ($rO.BrCol -eq 'BrGood' -and $rO.Title -eq 'Disk 2  Boş Disk silindi' -and $rO.Detail -match 'tek geçiş rastgele' -and $rO.Detail -match 'aygıttan geri okundu, fark yok' -and $rO.Detail -match 'Yeni sürücü: G:' -and $rO.Detail -match 'NTFS olarak biçimlenir' -and $rO.Detail -match 'Süre') 'ham silme sonucu: disk, başarılı'
$rP = Get-ErResultModel @{ Kind = 'Raw'; Ok = $true; Scope = 'Partition'; Disk = 1; Part = 2; Written = [double]$MiB; Method = 'zero'; VerifyKind = ''; Notes = @('Yeni bölüm açılamadı: x.') }
Assert-True ($rP.BrCol -eq 'BrWarn' -and $rP.Title -eq 'Disk 1 bölüm 2 silindi' -and $rP.Detail -match 'Doğrulama yapılmadı' -and $rP.Detail -match 'Yeni bölüm açılamadı') 'ham silme sonucu: bölüm, nota göre uyarı'
$rI = Get-ErResultModel @{ Kind = 'Raw'; Ok = $true; Scope = 'Disk'; Disk = -1; Written = [double]$MiB }
Assert-True ($rI.Title -match '^Disk imajı') 'ham silme sonucu: imaj'
$rC = Get-ErResultModel @{ Kind = 'Raw'; Ok = $false; Canceled = $true; Started = $true; Scope = 'Disk'; Disk = 2; Written = [double]$MiB }
Assert-True ($rC.BrCol -eq 'BrWarn' -and $rC.Title -match 'silme iptal edildi' -and $rC.Detail -match 'yarım silinmiş') 'ham silme sonucu: bölümler kaldırıldıktan sonra iptal'
$rC2 = Get-ErResultModel @{ Kind = 'Raw'; Ok = $false; Canceled = $true; Started = $false; Scope = 'Unallocated'; Disk = 2; Written = [double]$MiB }
Assert-True ($rC2.Detail -notmatch 'yarım silinmiş') 'ham silme sonucu: başlamadan iptal'
$rE = Get-ErResultModel @{ Kind = 'Raw'; Ok = $false; Started = $true; Scope = 'Partition'; Disk = 2; Part = 1; Error = 'Doğrulama başarısız: 4 birim.' }
Assert-True ($rE.BrCol -eq 'BrBad' -and $rE.Title -eq 'Disk 2 bölüm 1 silinemedi' -and $rE.Detail -match 'Doğrulama başarısız' -and $rE.Detail -match 'yeniden başlatın') 'ham silme sonucu: hata ve başlamış işlem'
$rE2 = Get-ErResultModel @{ Kind = 'Raw'; Ok = $false; Scope = 'Disk'; Disk = 2; Error = '' }
Assert-True ($rE2.Detail -match 'günlük' -and $rE2.Detail -notmatch 'yeniden başlatın') 'ham silme sonucu: nedensiz hata'

# dosya ve klasör silme sonucu
$s0 = Get-ErSecureResultModel @{ Files = 0; Failed = 0; Skipped = 0 }
Assert-True ($s0.Kind -eq 'info' -and $s0.Text -eq 'Silinecek dosya bulunamadı.') 'dosya silme sonucu: boş'
$s1 = Get-ErSecureResultModel @{ Files = 3; Failed = 0; Skipped = 0; Bytes = [double]3MB; Passes = 3; Warnings = @() }
Assert-True ($s1.Kind -eq 'good' -and $s1.Text -match '^3 dosya kalıcı silindi' -and $s1.Text -match '3 geçiş') 'dosya silme sonucu: başarılı, geçiş sayısı'
$s2 = Get-ErSecureResultModel @{ Files = 2; Failed = 1; Skipped = 2; Bytes = [double]1; Passes = 1; Warnings = @('2 dosya, x') }
Assert-True ($s2.Kind -eq 'warn' -and $s2.Text -match '2 öğe atlandı' -and $s2.Text -match '1 öğe silinemedi' -and $s2.Text -notmatch 'geçiş' -and @($s2.Warnings).Count -eq 1) 'dosya silme sonucu: atlanan ve başarısız'
Reset-Fake
Show-SecureDeleteResult @{ Files = 1; Failed = 0; Skipped = 0; Bytes = [double]10; Passes = 1; Warnings = @() }
Assert-True ((Get-LastToast).K -eq 'good' -and $script:Confirms.Count -eq 0) 'dosya silme bildirimi: uyarı yoksa pencere yok'
Show-SecureDeleteResult @{ Files = 1; Failed = 0; Skipped = 0; Bytes = [double]10; Passes = 1; Warnings = @('1 dosya, NTFS sıkıştırması açık dosya: x') }
Assert-True ($script:Confirms.Count -eq 1 -and $script:Confirms[0].Message -eq $true -and $script:Confirms[0].Text -match 'NTFS sıkıştırması' -and $script:Confirms[0].Text -match 'Boş alanı temizle') 'dosya silme bildirimi: uyarı varsa ileti penceresi'

# kurtarma anahtarı
Assert-Eq (Get-ErRecoverKey @{ Kind = 'Raw'; Disk = 4; Written = [double]1 }) 'PD:4:all' 'kurtarma anahtarı: ham silme tüm disk'
Assert-Eq (Get-ErRecoverKey @{ Kind = 'Raw'; Disk = 4; Written = [double]0 }) '' 'kurtarma anahtarı: yazılmadıysa yok'
Assert-Eq (Get-ErRecoverKey @{ Kind = 'Raw'; Disk = -1; Written = [double]1 }) '' 'kurtarma anahtarı: imaj için yok'
Assert-Eq (Get-ErRecoverKey @{ Kind = 'Trim'; Drive = 'E:'; Written = [double]1 }) '' 'kurtarma anahtarı: TRIM için yok'
Assert-Eq (Get-ErRecoverKey @{ Kind = 'Free'; Drive = 'e:\'; Written = [double]1 }) 'E:' 'kurtarma anahtarı: boş alan için sürücü'
Assert-Eq (Get-ErRecoverKey @{ Drive = 'E:\'; Written = [double]1 }) 'E:' 'kurtarma anahtarı: tür yoksa boş alan sayılır'
Assert-Eq (Get-ErRecoverKey @{ Drive = '\\sunucu\paylasim'; Written = [double]1 }) '' 'kurtarma anahtarı: sürücü harfi yoksa yok'
Assert-Eq (Get-ErRecoverKey $null) '' 'kurtarma anahtarı: sonuç yoksa yok'

# =====================================================================
#  7) sekme çizimi
# =====================================================================
$script:UiState = @{ Page = 'solve' }
$script:SlTab = 'erase'
$ui = @{}
foreach ($n in @('sl_List', 'sl_Foot', 'sl_ErFile', 'sl_ErFolder', 'sl_ErRefresh', 'sl_ErMethod', 'sl_ErVerify', 'sl_ErAfter')) { $ui[$n] = New-FakeCtl }
$script:SlDisks = $null
$script:ErLast = $null
$script:IsAdmin = $false
Reset-Fake

Render-SlErase
Assert-Eq $script:Loads 1 'çizim: sürücüler yoksa okuma istenir'
Assert-True ($null -ne (Find-NoteLike $ui.sl_List 'okunuyor')) 'çizim: okunuyor notu'
Assert-True ($null -ne (Find-NoteLike $ui.sl_List 'yazılana kadar boş alanda')) 'çizim: boş alan açıklaması'
Assert-True (@($ui.sl_List.Children | Where-Object { $_.Head -eq $true }).Count -eq 2) 'çizim: okuma sürerken iki başlık'

$script:SlDisks = @{ Failed = $true }
Render-SlErase
Assert-True ($null -ne (Find-NoteLike $ui.sl_List 'okunamadı')) 'çizim: sürücü listesi okunamazsa not'

$script:SlDisks = @{ Ok = $true; Sys = @{ OsDrive = 'C:' }; Disks = @($disks[1]); Phys = @() }
Render-SlErase
Assert-True ($null -ne (Find-NoteLike $ui.sl_List 'Temizlenebilecek sürücü bulunamadı')) 'çizim: temizlenecek sürücü yoksa not'
Assert-True ($null -ne (Find-NoteLike $ui.sl_List 'Silinebilecek disk bulunamadı')) 'çizim: silinecek disk yoksa not'

$script:SlDisks = @{ Ok = $true; Sys = @{ OsDrive = 'C:' }; Disks = $disks; Phys = @($dkSys, $dkUsb, $dkBlank, $dkApp, $dkFull) }
Render-SlErase
$rows = @(Get-RowsOf $ui.sl_List)
$driveRows = @($rows | Where-Object { $_.Tag.Do -eq 'ErFree' })
Assert-Eq $driveRows.Count 4 'çizim: dört sürücü satırı'
Assert-True ($driveRows[0].Vars.Btn1 -eq 'Boş alanı temizle' -and $driveRows[0].Vars.Btn2 -eq 'TRIM gönder' -and $driveRows[0].Tag.Drive -eq 'C:' -and $driveRows[0].Tag.IsOs -eq $true -and $driveRows[0].Tag.Trim -eq $true) 'çizim: SSD satırında TRIM düğmesi ve satır verisi'
Assert-True ($driveRows[1].Vars.Btn2 -eq '' -and $driveRows[1].Named.Act2.Handlers.Count -eq 0) 'çizim: USB satırında ikinci düğme yok'
Assert-Eq $driveRows[0].Named.Act.Handlers.Count 1 'çizim: birinci düğme bağlandı'
Assert-Eq $driveRows[0].Named.Act2.Handlers.Count 1 'çizim: TRIM düğmesi bağlandı'
Assert-True ($driveRows[0].Named.Act2.Tag.Do -eq 'ErTrim' -and $driveRows[0].Named.Act2.Tag.Drive -eq 'C:') 'çizim: TRIM düğmesinin verisi'
$diskRows = @($rows | Where-Object { $_.Tag.Do -eq 'ErGap' })
Assert-Eq $diskRows.Count 5 'çizim: beş disk satırı'
$partRows = @($rows | Where-Object { $_.Tag.Do -eq 'ErPart' })
Assert-Eq $partRows.Count 5 'çizim: beş bölüm satırı (kilitli disklerde bölüm gösterilmez)'
Assert-True ($diskRows[0].Vars.Btn1 -eq '' -and $diskRows[0].Vars.Btn2 -eq '' -and $diskRows[0].Named.Act.Handlers.Count -eq 0) 'çizim: sistem diskinde düğme yok'
Assert-True ($diskRows[1].Vars.Btn1 -eq 'Ayrılmamış alanı sil' -and $diskRows[1].Vars.Btn2 -eq 'Diski tamamen sil' -and $diskRows[1].Tag.Disk -eq 1) 'çizim: USB disk satırı'
Assert-True ($diskRows[1].Named.Act2.Tag.Do -eq 'ErDisk' -and $diskRows[1].Named.Act2.Tag.Disk -eq 1 -and $diskRows[1].Named.Act2.Handlers.Count -eq 1) 'çizim: disk silme düğmesinin verisi'
Assert-True ($partRows[0].Tag.Disk -eq 1 -and $partRows[0].Tag.Part -eq 1 -and $partRows[0].Vars.Btn1 -eq 'Bölümü sil' -and $partRows[0].Vars.Title -match '^      Bölüm 1') 'çizim: bölüm satırı girintili ve verili'
Assert-True ($null -ne (Find-NoteLike $ui.sl_List 'yönetici olarak çalışmıyor')) 'çizim: yönetici değilse uyarı'
Assert-True ($ui.sl_Foot.Text -match 'geri alınamaz') 'çizim: alt metin'
Assert-True ($null -ne (Find-NoteLike $ui.sl_List 'belgelendirme iddiası yoktur') -and $null -ne (Find-NoteLike $ui.sl_List 'Kurtarma motoruyla dene')) 'çizim: bilgi notları'
$script:IsAdmin = $true
Render-SlErase
Assert-True ($null -eq (Find-NoteLike $ui.sl_List 'yönetici olarak çalışmıyor')) 'çizim: yöneticiyken uyarı yok'
$script:IsAdmin = $false

# sonuç satırı en üstte
$script:ErLast = @{ Kind = 'Raw'; Ok = $true; Scope = 'Disk'; Disk = 2; Name = 'Boş Disk'; Written = [double]$GB; Method = 'random'; Notes = @() }
Render-SlErase
$first = $ui.sl_List.Children[0]
Assert-True ($first.Vars.Title -eq 'Disk 2  Boş Disk silindi' -and $first.Vars.Btn1 -eq 'Kurtarma motoruyla dene' -and $first.Tag.Do -eq 'ErRecover' -and $first.Tag.Key -eq 'PD:2:all') 'çizim: sonuç satırı en üstte, kurtarma düğmesiyle'
$script:ErLast = @{ Kind = 'Trim'; Ok = $true; Drive = 'C:' }
Render-SlErase
$first = $ui.sl_List.Children[0]
Assert-True ($first.Vars.Btn1 -eq '' -and $first.Vars.Title -match 'TRIM gönderildi') 'çizim: TRIM sonucunda kurtarma düğmesi yok'
$script:ErLast = $null

# =====================================================================
#  8) işlemler: boş alan, TRIM
# =====================================================================
$script:SlDisks = @{ Ok = $true; Sys = @{ OsDrive = 'C:' }; Disks = $disks; Phys = @($dkSys, $dkUsb, $dkBlank, $dkApp, $dkFull) }
Render-SlErase
$rows = @(Get-RowsOf $ui.sl_List)
$driveRows = @($rows | Where-Object { $_.Tag.Do -eq 'ErFree' })
Reset-Fake
Invoke-ErAction $driveRows[2].Tag
Assert-Eq $script:Confirms.Count 1 'boş alan: onay açıldı'
Assert-True ($script:Confirms[0].Title -eq 'Boş alanı temizle' -and $script:Confirms[0].Ok -eq 'Temizle' -and $script:Confirms[0].Text -match 'H: sürücüsünün') 'boş alan: onay içeriği'
Assert-Eq $script:Asyncs.Count 0 'boş alan: onaydan önce iş başlamaz'
& $script:Confirms[0].OnOk
Assert-Eq $script:Asyncs.Count 1 'boş alan: onaydan sonra iş başladı'
$a = $script:Asyncs[0]
Assert-True ($a.Name -eq 'WipeFree' -and $a.Entry -eq 'Job_WipeFree' -and $a.Params.Drive -eq 'H:' -and $a.Params.Method -eq 'random' -and $a.Params.Canary -eq $true -and $a.Params.Trim -eq $false -and $a.Label -match 'H: boş alanı temizleniyor') 'boş alan: iş parametreleri'
# seçenekler işe taşınır
$script:ErOpts = @{ Method = 'dod3'; Verify = 'none'; After = 'ntfs' }
Reset-Fake
Invoke-ErAction $driveRows[0].Tag
Assert-True ($script:Confirms[0].Text -match 'Yöntem: 3 geçiş' -and $script:Confirms[0].Text -notmatch 'Doğrulama: işe başlarken') 'boş alan: onay metni seçili yöntemi gösterir'
& $script:Confirms[0].OnOk
$a = $script:Asyncs[0]
Assert-True ($a.Params.Drive -eq 'C:' -and $a.Params.Method -eq 'dod3' -and $a.Params.Canary -eq $false -and $a.Params.Trim -eq $true) 'boş alan: yöntem, kanarya kapalı ve SSD için TRIM işe taşınır'
$script:ErOpts = @{ Method = 'random'; Verify = 'sample'; After = 'none' }
# tamamlanınca
Reset-Fake
$script:ErPendDrive = 'H:'
$a.OnDone.GetType() | Out-Null
& $a.OnDone @{ Ok = $true; Kind = 'Free'; Drive = 'H:\'; Written = [double](5 * $GB); Canceled = $false; Error = '' }
Assert-True ((Get-LastToast).K -eq 'good' -and (Get-LastToast).T -match 'temizlendi') 'boş alan: bitiş bildirimi iş sonucundan gelir'
# eklenti sorunluysa onay açılmaz
Reset-Fake
$script:ExtProblem = 'Eklenti bozuk.'
Invoke-ErAction $driveRows[0].Tag
Assert-True ($script:Confirms.Count -eq 1 -and $script:Confirms[0].Message -eq $true -and $script:Confirms[0].Text -eq 'Eklenti bozuk.' -and $script:Confirms[0].Title -eq 'Boş alan temizleme kullanılamıyor') 'boş alan: eklenti sorunu gösterilir, onay açılmaz'
Assert-Eq $script:Asyncs.Count 0 'boş alan: eklenti sorunluysa iş yok'
Reset-Fake
Invoke-ErAction $driveRows[0].Named.Act2.Tag
Assert-True ($script:Confirms.Count -eq 1 -and $script:Confirms[0].Message -eq $true -and $script:Confirms[0].Title -eq 'TRIM kullanılamıyor') 'TRIM: eklenti sorunu gösterilir'
Reset-Fake
Invoke-ErAction @{ Do = 'ErDisk'; Disk = 1 }
Assert-True ($script:Confirms.Count -eq 1 -and $script:Confirms[0].Message -eq $true -and $script:Confirms[0].Title -eq 'Disk silme kullanılamıyor' -and $script:Overlays.Count -eq 0) 'disk silme: eklenti sorunu gösterilir, onay açılmaz'
$script:ExtProblem = ''

# TRIM
Reset-Fake
Invoke-ErAction $driveRows[0].Named.Act2.Tag
Assert-True ($script:Confirms.Count -eq 1 -and $script:Confirms[0].Title -eq 'TRIM gönder' -and $script:Confirms[0].Ok -eq 'Gönder' -and $script:Confirms[0].Text -match 'C: sürücüsü' -and $script:Confirms[0].Text -match 'Hiçbir dosyaya dokunulmaz') 'TRIM: onay'
& $script:Confirms[0].OnOk
$a = $script:Asyncs[0]
Assert-True ($a.Name -eq 'WipeTrim' -and $a.Entry -eq 'Job_TrimVolume' -and $a.Params.Drive -eq 'C:' -and $a.Label -match 'C: için TRIM') 'TRIM: iş parametreleri'
Reset-Fake
$script:ErPendDrive = 'C:'
& $a.OnDone @{ Ok = $true; Kind = 'Trim'; Drive = 'C:'; Note = '' }
Assert-True ((Get-LastToast).K -eq 'good' -and (Get-LastToast).T -match 'TRIM gönderildi') 'TRIM: bitiş bildirimi'

# =====================================================================
#  9) işlemler: ayrılmamış alan, bölüm, disk
# =====================================================================
$script:IsAdmin = $false
Reset-Fake
Invoke-ErAction @{ Do = 'ErDisk'; Disk = 1 }
Assert-True ($script:Confirms.Count -eq 1 -and $script:Confirms[0].Message -eq $true -and $script:Confirms[0].Title -eq 'Yönetici izni gerekli' -and $script:Overlays.Count -eq 0 -and $script:Asyncs.Count -eq 0) 'disk: yönetici değilse hiçbir şey açılmaz'
Invoke-ErAction @{ Do = 'ErPart'; Disk = 1; Part = 1 }
Invoke-ErAction @{ Do = 'ErGap'; Disk = 1 }
Assert-True ($script:Confirms.Count -eq 3 -and $script:Overlays.Count -eq 0 -and $script:Asyncs.Count -eq 0) 'bölüm ve ayrılmamış alan: yönetici değilse hiçbir şey açılmaz'
$script:IsAdmin = $true
# iş bitince bilgiler sıfırlanır; yeniden okunmuş gibi doldur
$script:SlDisks = @{ Ok = $true; Sys = @{ OsDrive = 'C:' }; Disks = $disks; Phys = @($dkSys, $dkUsb, $dkBlank, $dkApp, $dkFull) }

# tüm disk: elle yazdırılan onay
Reset-Fake
Invoke-ErAction @{ Do = 'ErDisk'; Disk = 1 }
Assert-Eq $script:Overlays.Count 1 'disk: yazdırmalı onay penceresi açıldı'
Assert-Eq $script:Confirms.Count 0 'disk: düz onay açılmadı'
$ov = $script:Overlays[0]
Assert-True ($ov.Title -eq 'Diski tamamen sil' -and $ov.Ok -eq 'Diski sil' -and $ov.WithInput -eq $true -and $ov.Danger -eq $true -and $ov.ShowCancel -eq $true) 'disk: pencere biçimi (tehlikeli, kutulu)'
Assert-True ($ov.Text -match 'tamamen silinecek' -and $ov.Text -match 'Onaylamak için kutuya şunu yazın:  Disk 1$') 'disk: pencere metni beklenen yazıyı gösterir'
Assert-Eq $script:Asyncs.Count 0 'disk: onaydan önce iş başlamaz'
& $ov.OnOk 'disk 2'
Assert-True ($script:Asyncs.Count -eq 0 -and (Get-LastToast).K -eq 'warn' -and (Get-LastToast).T -match 'eşleşmedi') 'disk: yanlış yazı kabul edilmez, hiçbir şey silinmez'
& $ov.OnOk ''
Assert-Eq $script:Asyncs.Count 0 'disk: boş yazı kabul edilmez'
& $ov.OnOk '  DİSK   1 '
Assert-Eq $script:Asyncs.Count 1 'disk: doğru yazıyla iş başladı (büyük harf ve boşluk önemsiz)'
$a = $script:Asyncs[0]
Assert-True ($a.Name -eq 'WipeRaw' -and $a.Entry -eq 'Job_WipeRaw' -and $a.Params.Scope -eq 'Disk' -and $a.Params.Disk -eq 1 -and $a.Params.Expect.Serial -eq 'SN1' -and $a.Label -eq 'Disk 1 siliniyor') 'disk: iş parametreleri'
& $ov.OnOk 'disk 1'
Assert-Eq $script:Asyncs.Count 1 'disk: aynı pencereden ikinci kez iş başlatılamaz'

# bölüm
Reset-Fake
Invoke-ErAction @{ Do = 'ErPart'; Disk = 1; Part = 1 }
$ov = $script:Overlays[0]
Assert-True ($ov.Title -eq 'Bölümü sil' -and $ov.Text -match 'Disk 1 Bölüm 1$') 'bölüm: yazdırma metni'
& $ov.OnOk 'disk 1'
Assert-Eq $script:Asyncs.Count 0 'bölüm: yalnızca disk adı yetmez'
& $ov.OnOk 'disk 1 bolum 1'
Assert-True ($script:Asyncs.Count -eq 1 -and $script:Asyncs[0].Params.Scope -eq 'Partition' -and $script:Asyncs[0].Params.Part -eq 1 -and $script:Asyncs[0].Params.Expect.PartSize -eq [double](10 * $GB)) 'bölüm: Türkçe harfsiz yazımla iş başladı'

# ayrılmamış alan: bölümler varken düz onay
Reset-Fake
Invoke-ErAction @{ Do = 'ErGap'; Disk = 1 }
Assert-True ($script:Overlays.Count -eq 0 -and $script:Confirms.Count -eq 1 -and $script:Confirms[0].Title -eq 'Ayrılmamış alanı sil' -and $script:Confirms[0].Ok -eq 'Sil' -and $script:Confirms[0].Danger -eq $true) 'ayrılmamış alan: düz onay, tehlike işaretli'
Assert-Eq $script:Asyncs.Count 0 'ayrılmamış alan: onaydan önce iş yok'
& $script:Confirms[0].OnOk
Assert-True ($script:Asyncs.Count -eq 1 -and $script:Asyncs[0].Params.Scope -eq 'Unallocated' -and $script:Asyncs[0].Params.After -eq 'none' -and $script:Asyncs[0].Label -eq 'Disk 1 ayrılmamış alan siliniyor') 'ayrılmamış alan: iş parametreleri'
# bölümü hiç olmayan diskte ad yazdırılır
Reset-Fake
Invoke-ErAction @{ Do = 'ErGap'; Disk = 2 }
Assert-True ($script:Confirms.Count -eq 0 -and $script:Overlays.Count -eq 1 -and $script:Overlays[0].Title -eq 'Diski ayrılmamış alan olarak sil' -and $script:Overlays[0].Text -match 'Disk 2$') 'ayrılmamış alan: bölümsüz diskte ad yazdırılır'
& $script:Overlays[0].OnOk 'disk 2'
Assert-True ($script:Asyncs.Count -eq 1 -and $script:Asyncs[0].Params.Scope -eq 'Unallocated' -and $script:Asyncs[0].Params.Disk -eq 2) 'ayrılmamış alan: doğru yazıyla iş başladı'

# seçenekler plana taşınır
$script:ErOpts = @{ Method = 'zero'; Verify = 'full'; After = 'exfat' }
Reset-Fake
Invoke-ErAction @{ Do = 'ErDisk'; Disk = 2 }
& $script:Overlays[0].OnOk 'disk 2'
Assert-True ($script:Asyncs[0].Params.Method -eq 'zero' -and $script:Asyncs[0].Params.Verify -eq 'full' -and $script:Asyncs[0].Params.After -eq 'exfat') 'disk: seçili yöntem, doğrulama ve sonra seçeneği işe taşınır'
$script:ErOpts = @{ Method = 'random'; Verify = 'sample'; After = 'none' }

# reddedilenler
foreach ($case in @(@('Do', 'ErDisk', 0, 'Windows bu diskte'), @('Do', 'ErGap', 0, 'Windows bu diskte'), @('Do', 'ErDisk', 3, 'doğrudan yazılmaz'), @('Do', 'ErDisk', 77, 'Disk bulunamadı'), @('Do', 'ErPart', 0, 'Windows bu diskte'))) {
    Reset-Fake
    Invoke-ErAction @{ Do = $case[1]; Disk = $case[2]; Part = 1 }
    Assert-True ($script:Confirms.Count -eq 1 -and $script:Confirms[0].Message -eq $true -and $script:Confirms[0].Title -eq 'Bu işlem yapılamaz' -and $script:Confirms[0].Text -match $case[3] -and $script:Overlays.Count -eq 0 -and $script:Asyncs.Count -eq 0) ('reddedilen işlem: ' + $case[1] + ' disk ' + $case[2])
}
Reset-Fake
$saveDisks = $script:SlDisks
$script:SlDisks = $null
Invoke-ErAction @{ Do = 'ErDisk'; Disk = 1 }
Assert-True ($script:Confirms.Count -eq 1 -and $script:Confirms[0].Text -match 'Disk bulunamadı') 'disk listesi yoksa işlem yapılmaz'
$script:SlDisks = @{ Failed = $true }
Reset-Fake
Invoke-ErAction @{ Do = 'ErDisk'; Disk = 1 }
Assert-True ($script:Confirms.Count -eq 1 -and $script:Confirms[0].Text -match 'Disk bulunamadı') 'disk listesi okunamamışsa işlem yapılmaz'
$script:SlDisks = $saveDisks
Assert-Eq (Find-ErDisk 1).Number 1 'disk bulma: var olan disk'
Assert-Eq (Find-ErDisk 123) $null 'disk bulma: olmayan disk'
Reset-Fake
Invoke-ErAction @{ Do = 'Bilinmeyen' }
Assert-True ($script:Confirms.Count -eq 0 -and $script:Overlays.Count -eq 0 -and $script:Asyncs.Count -eq 0) 'bilinmeyen eylem hiçbir şey yapmaz'

# kurtarma motoruyla dene
Reset-Fake
$script:ChipCalls.Clear(); $script:ChipOk = $false; $script:RcSelKey = ''
Invoke-ErAction @{ Do = 'ErRecover'; Key = 'PD:2:all' }
Assert-True ($script:RcSelKey -eq 'PD:2:all' -and (@($script:ChipCalls) -join ',') -eq 'sl:recover,tab:recover') 'kurtarma: kaynak seçilir ve sekme değişir'
$script:ChipCalls.Clear(); $script:ChipOk = $true
Invoke-ErAction @{ Do = 'ErRecover'; Key = 'E:' }
Assert-True ($script:RcSelKey -eq 'E:' -and (@($script:ChipCalls) -join ',') -eq 'sl:recover') 'kurtarma: sekme çipi varsa yalnızca çip seçilir'
$script:ChipCalls.Clear(); $script:RcSelKey = 'x'
Invoke-ErAction @{ Do = 'ErRecover'; Key = '' }
Assert-True ($script:ChipCalls.Count -eq 0 -and $script:RcSelKey -eq 'x') 'kurtarma: anahtar yoksa hiçbir şey yapılmaz'

# =====================================================================
#  10) sonuçların işlenmesi
# =====================================================================
Reset-Fake
$script:SlDisks = @{ Ok = $true; Sys = @{ OsDrive = 'C:' }; Disks = $disks; Phys = @($dkUsb) }
$script:RcPartCache = @{ 'PhysicalDrive1' = 'a'; 'PhysicalDrive2' = 'b'; 'E:' = 'c' }
$script:ErPendDrive = 'H:'
$script:ErPend = $null
$script:UiState = @{ Page = 'solve' }
$script:SlTab = 'erase'
Complete-ErFree @{ Ok = $true; Drive = 'H:\'; Written = [double](5 * $GB); Canceled = $false; Error = '' }
Assert-True ((Get-LastToast).K -eq 'good' -and (Get-LastToast).T -match 'temizlendi') 'sonuç: başarı bildirimi'
Assert-Eq $script:Loads 1 'sonuç: sürücü bilgisi yenilenmek üzere sıfırlandı, yeniden okuma istendi'
Assert-True ($script:RcPartCache.ContainsKey('E:') -and -not $script:RcPartCache.ContainsKey('PhysicalDrive1') -and -not $script:RcPartCache.ContainsKey('PhysicalDrive2')) 'sonuç: kurtarma sekmesinin disk önbelleği temizlendi, diğerleri korundu'
$first = $ui.sl_List.Children[0]
Assert-True ($first.Vars.Title -match 'H:\\ boş alanı temizlendi' -and $first.Vars.BrCol -eq 'BrGood' -and $first.Vars.Btn1 -eq 'Kurtarma motoruyla dene' -and $first.Tag.Key -eq 'H:') 'sonuç: sonuç satırı en üstte'
Complete-ErFree @{ Ok = $false; Drive = 'H:\'; Written = [double]$GB; Canceled = $true; Error = '' }
Assert-Eq (Get-LastToast).K 'warn' 'sonuç: iptal bildirimi'
Complete-ErFree @{ Ok = $false; Drive = 'H:\'; Written = [double]0; Canceled = $false; Error = 'Sürücü bilgisi okunamadı.' }
Assert-Eq (Get-LastToast).K 'bad' 'sonuç: hata bildirimi'
Complete-ErFree $null
Assert-True ((Get-LastToast).K -eq 'bad' -and $script:ErLast.Error -match 'günlüğe bakın') 'sonuç: boş sonuç hata sayılır'
Complete-ErFree @{ Ok = $false; ExtError = 'Eklenti değiştirilmiş.'; Drive = ''; Written = 0; Canceled = $false; Error = '' }
Assert-True ((Get-LastToast).K -eq 'bad' -and (Get-LastToast).T -match 'Eklenti değiştirilmiş') 'sonuç: eklenti hatası iletilir'
Complete-ErTrim @{ Ok = $true; Kind = 'Trim'; Drive = 'C:' }
Assert-True ((Get-LastToast).K -eq 'good' -and (Get-LastToast).T -match 'TRIM gönderildi') 'sonuç: TRIM bildirimi'
Complete-ErTrim $null
Assert-True ((Get-LastToast).K -eq 'bad' -and $script:ErLast.Kind -eq 'Trim') 'sonuç: boş TRIM sonucu hata sayılır'
$script:ErPend = @{ Kind = 'Raw'; Scope = 'Disk'; Disk = 2 }
Complete-ErRaw @{ Ok = $true; Kind = 'Raw'; Scope = 'Disk'; Disk = 2; Name = 'Boş Disk'; Written = [double]$GB; Method = 'random'; Notes = @() }
Assert-True ((Get-LastToast).K -eq 'good' -and (Get-LastToast).T -match 'Disk 2  Boş Disk silindi') 'sonuç: ham silme başarı bildirimi'
Complete-ErRaw @{ Ok = $true; Nothing = $true; Kind = 'Raw'; Scope = 'Unallocated'; Disk = 2; Notes = @('Ayrılmamış alan bulunamadı; yapılacak bir şey yok.') }
Assert-Eq (Get-LastToast).K 'info' 'sonuç: yapılacak bir şey yok bilgi olarak bildirilir'
Complete-ErRaw @{ Ok = $false; Canceled = $true; Started = $true; Kind = 'Raw'; Scope = 'Partition'; Disk = 2; Part = 1; Written = [double]$MiB }
Assert-Eq (Get-LastToast).K 'warn' 'sonuç: ham silme iptali'
Complete-ErRaw $null
Assert-True ((Get-LastToast).K -eq 'bad' -and $script:ErLast.Kind -eq 'Raw' -and $script:ErLast.Scope -eq 'Disk' -and $script:ErLast.Disk -eq 2) 'sonuç: boş ham sonuç, bekleyen işin bilgisiyle hata sayılır'
Complete-ErRaw @{ Ok = $false; ExtError = 'DiskSilme eklentisi değiştirilmiş.' }
Assert-True ((Get-LastToast).K -eq 'bad' -and (Get-LastToast).T -match 'DiskSilme eklentisi değiştirilmiş') 'sonuç: ham silmede eklenti hatası'
# başka sayfadayken çizilmez
$script:UiState = @{ Page = 'tools' }
$ui.sl_List.Children.Clear()
Complete-ErFree @{ Ok = $true; Drive = 'H:\'; Written = [double]$GB; Canceled = $false; Error = '' }
Assert-Eq $ui.sl_List.Children.Count 0 'sonuç: başka sayfadayken liste yeniden çizilmez'
Assert-True ($null -eq $script:SlDisks) 'sonuç: yine de sürücü bilgisi sıfırlandı'
$script:UiState = @{ Page = 'solve' }
$script:SlTab = 'scan'
Complete-ErFree @{ Ok = $true; Drive = 'H:\'; Written = [double]$GB; Canceled = $false; Error = '' }
Assert-Eq $ui.sl_List.Children.Count 0 'sonuç: başka sekmedeyken liste yeniden çizilmez'
$script:SlTab = 'erase'

# =====================================================================
#  11) başlatma ve seçenek kutuları
# =====================================================================
Init-SlErase
Assert-True ($ui.sl_ErFile.Handlers.Count -eq 1 -and $ui.sl_ErFolder.Handlers.Count -eq 1 -and $ui.sl_ErRefresh.Handlers.Count -eq 1) 'başlatma: düğmeler bağlandı'
Assert-Eq $ui.sl_ErMethod.Items.Count 4 'başlatma: dört yöntem'
Assert-Eq $ui.sl_ErVerify.Items.Count 3 'başlatma: üç doğrulama seçeneği'
Assert-Eq $ui.sl_ErAfter.Items.Count 4 'başlatma: dort sonra secenegi'
Assert-True ((Get-ComboKey $ui.sl_ErMethod) -eq 'random' -and (Get-ComboKey $ui.sl_ErVerify) -eq 'sample' -and (Get-ComboKey $ui.sl_ErAfter) -eq 'none') 'başlatma: varsayılanlar seçili'
Assert-True ($script:ErLoading -eq $false) 'başlatma: yükleme bayrağı kapandı'
[void](Select-ComboKey $ui.sl_ErMethod 'dod3')
& $ui.sl_ErMethod.Handlers[0] $null $null
Assert-Eq $script:ErOpts.Method 'dod3' 'seçenek: yöntem değişince saklanır'
[void](Select-ComboKey $ui.sl_ErVerify 'none')
& $ui.sl_ErVerify.Handlers[0] $null $null
Assert-Eq $script:ErOpts.Verify 'none' 'seçenek: doğrulama değişince saklanır'
[void](Select-ComboKey $ui.sl_ErAfter 'fat32')
& $ui.sl_ErAfter.Handlers[0] $null $null
Assert-Eq $script:ErOpts.After 'fat32' 'secenek: sonra degisince saklanir'
$script:ErLoading = $true
[void](Select-ComboKey $ui.sl_ErMethod 'zero')
Select-ErOption 'Method'
Assert-Eq $script:ErOpts.Method 'dod3' 'seçenek: yükleme sırasında değişiklik yok sayılır'
$script:ErLoading = $false
$ui.sl_ErMethod.SelectedIndex = -1
Select-ErOption 'Method'
Assert-Eq $script:ErOpts.Method 'dod3' 'seçenek: seçim yoksa değişmez'
$script:ErOpts = @{ Method = 'random'; Verify = 'sample'; After = 'none' }
# yenile düğmesi
Reset-Fake
$script:SlDisks = @{ Ok = $true; Sys = @{ OsDrive = 'C:' }; Disks = $disks; Phys = @() }
& $ui.sl_ErRefresh.Handlers[0] $null $null
Assert-True ($null -eq $script:SlDisks -and $script:Loads -eq 1) 'yenile: bilgiler sıfırlanır ve yeniden okunur'
# yeniden başlatma: kaydedilmiş seçenekler korunur
$script:ErOpts = @{ Method = 'random3'; Verify = 'full'; After = 'ntfs' }
Init-SlErase
Assert-True ((Get-ComboKey $ui.sl_ErMethod) -eq 'random3' -and (Get-ComboKey $ui.sl_ErVerify) -eq 'full' -and (Get-ComboKey $ui.sl_ErAfter) -eq 'ntfs') 'başlatma: kayıtlı seçenekler seçili gelir'

Show-Result
