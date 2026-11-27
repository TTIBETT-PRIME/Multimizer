. "$PSScriptRoot/lib.ps1"
# Üst çubuk (mods\145_header_core.ps1, 146_header_ui.ps1, patches\p63_ust_cubuk.py):
# sol üstteki Multimizer emblemi ana sayfa düğmesidir; KULLANICI | UZMAN kapsülünün yanında dil seçici vardır.
# Burada: XAML yapısı, dil düğmesinin gösterimi, açılır listenin modeli, dil değiştirme akışı (yeniden başlatma / yalnızca kayıt / meşgul),
# emblem tıklaması, olay bağlantıları ve dil dosyalarındaki yeni metinler sınanır. Gerçek çizim bilgisayarda Duman-Ust.cmd ile görülür.
Import-Fn 'Get-LangShortCode', 'Get-LangStoredKey', 'Add-LangNameOut', 'Get-LangMenuModel', 'Get-LangButtonInfo', 'Get-LangChangePlan',
    'Get-LangList', 'Read-LangHeader', 'Find-LangForCulture', 'Resolve-LangCode', 'Get-LangEntry', 'Format-Tr',
    'Get-LangShownName', 'Request-LangChange', 'Invoke-HomeClick', 'Update-LangButton', 'Update-LangMenu', 'Select-LangRow', 'Close-LangMenu',
    'Show-LangMenu', 'Set-LangPopFocus', 'Initialize-HeaderBar', 'Complete-LangChange', 'Confirm-LangRestart'
Import-Var 'SmokeSafe', 'SmokeScopes'
. "$PSScriptRoot/uifake.ps1"
$src = [System.IO.File]::ReadAllText($script:TestPath)
$mid = [string][char]0x00B7

# ======================= 1) XAML yapısı =======================
foreach ($n in @('BtnHome', 'LangCapsule', 'BtnLang', 'TxtLangCode', 'LangPop', 'LangItems')) {
    Assert-Eq ([regex]::Matches($src, ('x:Name="' + $n + '"')).Count) 1 ("XAML: $n bir kez tanımlı")
}
foreach ($k in @('BtnBrand', 'BtnLangCap')) {
    Assert-Eq ([regex]::Matches($src, ('<Style x:Key="' + $k + '" TargetType="Button">')).Count) 1 ("stil $k bir kez tanımlı")
}
$iLeft = $src.IndexOf('x:Name="TitleLeft"'); $iHome = $src.IndexOf('x:Name="BtnHome"'); $iTag = $src.IndexOf('x:Name="TxtTagline"')
$iCenter = $src.IndexOf('x:Name="TitleCenter"'); $iUser = $src.IndexOf('x:Name="SegUser"'); $iExp = $src.IndexOf('x:Name="SegExpert"')
$iCap = $src.IndexOf('x:Name="LangCapsule"'); $iPop = $src.IndexOf('x:Name="LangPop"'); $iRight = $src.IndexOf('x:Name="TitleRight"')
Assert-True ($iLeft -ge 0 -and $iHome -gt $iLeft -and $iHome -lt $iTag -and $iTag -lt $iCenter) 'emblem düğmesi sol başlık alanında, sloganın önünde'
Assert-True ($iCenter -lt $iUser -and $iUser -lt $iExp -and $iExp -lt $iCap -and $iCap -lt $iPop -and $iPop -lt $iRight) 'dil kapsülü KULLANICI | UZMAN kapsülünün hemen yanında, aynı orta alanda'
$mHome = [regex]::Match($src, '<Button x:Name="BtnHome"[^>]*>')
Assert-True $mHome.Success 'emblem düğmesi tanımı bulundu'
Assert-True ($mHome.Value.Contains('Style="{DynamicResource BtnBrand}"')) 'emblem düğmesi BtnBrand stilini kullanır'
Assert-True ($mHome.Value.Contains(' shell:WindowChrome.IsHitTestVisibleInChrome="True"')) 'emblem düğmesi başlık çubuğunda tıklanabilir (WindowChrome istisnası)'
Assert-True ($mHome.Value -match 'ToolTip="Ana sayfa: durum panosuna d[^"]+n"') 'emblem düğmesinin aracı ipucu var'
$homeBlock = $src.Substring($iHome, $src.IndexOf('</Button>', $iHome) - $iHome)
Assert-True ($homeBlock.Contains('IcoLogo') -and $homeBlock.Contains('Text="MULTIMIZER"') -and -not $homeBlock.Contains('MULT&#x0130;')) 'emblem düğmesi logoyu ve MULTIMIZER yazısını içerir'
$mLang = [regex]::Match($src, '<Button x:Name="BtnLang"[^>]*>')
Assert-True ($mLang.Success -and $mLang.Value.Contains('Style="{DynamicResource BtnLangCap}"') -and $mLang.Value -match 'ToolTip="Aray') 'dil düğmesi BtnLangCap stilinde ve aracı ipucu var'
$capBlock = $src.Substring($iCap, $iPop - $iCap)
Assert-True ($capBlock.Contains('IcoGlobe') -and $capBlock.Contains('IcoChevD') -and $capBlock.Contains('x:Name="TxtLangCode"')) 'dil düğmesi: küre simgesi, dil kodu ve ok'
Assert-True ($capBlock.Contains('CornerRadius="{DynamicResource RadBtn}"') -and $capBlock.Contains('Padding="2"')) 'dil kapsülü kip kapsülüyle aynı köşe ve iç boşlukta'
$popTag = [regex]::Match($src, '<Popup x:Name="LangPop"[^>]*>').Value
Assert-True ($popTag.Contains('StaysOpen="False"') -and $popTag.Contains('Placement="Bottom"') -and $popTag.Contains('AllowsTransparency="True"')) 'dil listesi: dışarı tıklanınca kapanır, düğmenin altında açılır'
Assert-True ($src.Contains('<StackPanel x:Name="LangItems" KeyboardNavigation.DirectionalNavigation="Cycle"/>')) 'dil listesi ok tuşlarıyla gezilebilir'
# başlıktaki her kaynak anahtarı tanımlı
$hdrXaml = $src.Substring($iLeft, $iRight - $iLeft)
$sA = $src.IndexOf('<Style x:Key="BtnBrand"'); $sB = $src.IndexOf('<Style x:Key="BtnLangCap"')
$stBrand = $src.Substring($sA, $src.IndexOf('</Style>', $sB) + 8 - $sA)
$miss = @()
foreach ($m in [regex]::Matches(($hdrXaml + $stBrand), '\{DynamicResource ([A-Za-z0-9_]+)\}')) {
    $key = $m.Groups[1].Value
    if (-not $src.Contains('x:Key="' + $key + '"') -and $miss -notcontains $key) { $miss += $key }
}
Assert-Eq ($miss -join ',') '' 'başlık ve düğme stilleri yalnızca tanımlı kaynakları kullanır'

# ======================= 2) sahte ortam =======================
$script:Settings = @{ Language = 'auto' }
$script:LangCode = 'tr'; $script:LangList = $null; $script:LangOut = $null
$script:T_Sys = 'tr'
function Get-SystemLangCode { return $script:T_Sys }
function Get-LangFolders { return @((Join-Path $script:TestDir 'veri/dil')) }
function Format-Percent($V) { return '%' + [string]$V }
$script:TrSeen = New-Object System.Collections.ArrayList
function global:Tr { param([string]$Text) [void]$script:TrSeen.Add($Text); return $Text }
$script:Saved = New-Object System.Collections.ArrayList
function Save-Settings($S) { [void]$script:Saved.Add([string]$S.Language) }
$script:Busy = $false
function Test-AsyncBusy { return $script:Busy }
$script:Restarted = 0; $script:Exited = 0
function Restart-App { $script:Restarted++; return $true }
function Exit-App { $script:Exited++ }
$script:NavClosed = 0
function Close-NavMenu { $script:NavClosed++ }
$script:ShownPages = New-Object System.Collections.ArrayList
$script:UiState = @{ Page = 'settings' }
function Show-Page([string]$Key) { [void]$script:ShownPages.Add($Key); $script:UiState.Page = $Key }
$script:ScrollTo = New-Object System.Collections.ArrayList
$script:ScrollerFake = [pscustomobject]@{}
Add-Member -InputObject $script:ScrollerFake -MemberType ScriptMethod -Name ScrollToVerticalOffset -Value { param($o) [void]$script:ScrollTo.Add([double]$o) } | Out-Null
$script:HasScroller = $true
function Get-PageScroller([int]$Dir) { if ($script:HasScroller) { return $script:ScrollerFake }; return $null }
$script:PageFocused = 0
function Focus-PageHost { $script:PageFocused++ }
function New-LangRow($M) {
    $r = New-FakeCtl
    # derleme adımı .Text atamalarını Tr ile sarar: aynı çağrılar burada taklit edilir (dinamik metinler çeviri denetiminde muaf olmalı)
    $r.Tag = [string]$M.Code; $r.Text = (Tr ([string]$M.Name)); $r.Kind = (Tr ([string]$M.Sub)); $r.IsChecked = [bool]$M.Checked
    if ([string]$M.Chip -ne '') { [void](Tr ([string]$M.Chip)) }
    Add-Member -InputObject $r -MemberType NoteProperty -Name Focused -Value 0
    Add-Member -InputObject $r -MemberType ScriptMethod -Name Focus -Value { $this.Focused++; return $true } | Out-Null
    return , $r
}
function New-HdrCtl {
    $c = New-FakeCtl
    Add-Member -InputObject $c -MemberType NoteProperty -Name ToolTip -Value ''
    Add-Member -InputObject $c -MemberType NoteProperty -Name IsOpen -Value $false
    Add-Member -InputObject $c -MemberType NoteProperty -Name PlacementTarget -Value $null
    Add-Member -InputObject $c -MemberType NoteProperty -Name Child -Value $null
    Add-Member -InputObject $c -MemberType NoteProperty -Name Ev -Value @{}
    Add-Member -InputObject $c -MemberType ScriptMethod -Name Add_Opened -Value { param($h) $this.Ev['Opened'] = $h } | Out-Null
    Add-Member -InputObject $c -MemberType ScriptMethod -Name Add_Closed -Value { param($h) $this.Ev['Closed'] = $h } | Out-Null
    Add-Member -InputObject $c -MemberType ScriptMethod -Name Add_PreviewKeyDown -Value { param($h) $this.Ev['Key'] = $h } | Out-Null
    return $c
}
function New-HdrUi {
    $u = @{ BtnHome = (New-HdrCtl); BtnLang = (New-HdrCtl); TxtLangCode = (New-HdrCtl); LangCapsule = (New-HdrCtl); LangPop = (New-HdrCtl); LangItems = (New-FakeCtl) }
    $u.LangPop.Child = New-HdrCtl
    return $u
}
$script:ui = New-HdrUi
$ui = $script:ui
$script:LangPopClosedAt = [datetime]::MinValue
$script:LangPopFocus = $null
function Reset-Hdr {
    Reset-Fake
    $script:Saved.Clear(); $script:Busy = $false; $script:Restarted = 0; $script:Exited = 0; $script:NavClosed = 0
    $script:ShownPages.Clear(); $script:ScrollTo.Clear(); $script:HasScroller = $true; $script:PageFocused = 0
    $script:UiState = @{ Page = 'settings' }; $script:LangPopClosedAt = [datetime]::MinValue; $script:LangPopFocus = $null
    $script:ui = New-HdrUi
}

# ======================= 3) dil kodunun kısa gösterimi, kayıtlı seçim =======================
$all = @(Get-LangList)
$packFiles = @(Get-ChildItem -LiteralPath (Join-Path $script:TestDir 'veri/dil') -Filter '*.lang' -File)
Assert-True ($packFiles.Count -ge 2) 'dil dosyaları yanında veri\dil klasöründe'
Assert-Eq $all.Count ($packFiles.Count + 1) 'dil listesi: Türkçe + her dil dosyası'
Assert-Eq (Get-LangShortCode 'tr') 'TR' 'kısa kod: tr -> TR'
Assert-Eq (Get-LangShortCode ' En ') 'EN' 'kısa kod: boşluk ve büyük harf önemsenmez'
Assert-Eq (Get-LangShortCode 'zh') 'ZH' 'kısa kod: zh -> ZH'
Assert-Eq (Get-LangShortCode 'zh-hant') 'ZH-TW' 'kısa kod: zh-hant -> ZH-TW (dil etiketinin bölgesi)'
Assert-Eq (Get-LangShortCode 'pt-xx') 'PT-XX' 'kısa kod: dil dosyası olmayan bölgeli kod olduğu gibi büyütülür'
Assert-Eq (Get-LangShortCode '') '--' 'kısa kod: boş kod için tire'
foreach ($c in @('de', 'fr', 'es', 'it', 'pt', 'ru', 'ko', 'ja', 'ar', 'en')) { Assert-Eq (Get-LangShortCode $c) $c.ToUpperInvariant() ("kısa kod: $c") }
$script:Settings = @{ Language = 'auto' }; Assert-Eq (Get-LangStoredKey) 'auto' 'kayıtlı seçim: auto'
$script:Settings = @{ Language = ' DE ' }; Assert-Eq (Get-LangStoredKey) 'de' 'kayıtlı seçim: boşluk ve büyük harf düzeltilir'
$script:Settings = @{ Language = '' }; Assert-Eq (Get-LangStoredKey) 'auto' 'kayıtlı seçim: boşsa auto'
$script:Settings = @{}; Assert-Eq (Get-LangStoredKey) 'auto' 'kayıtlı seçim: anahtar yoksa auto'
$script:Settings = $null; Assert-Eq (Get-LangStoredKey) 'auto' 'kayıtlı seçim: ayarlar yoksa auto'

# ======================= 4) açılır liste modeli =======================
$script:Settings = @{ Language = 'auto' }; $script:T_Sys = 'de'
$script:LangOut = New-Object 'System.Collections.Generic.HashSet[string]'
$m = @(Get-LangMenuModel)
Assert-Eq $m.Count ($all.Count + 1) 'liste modeli: Otomatik + her dil'
Assert-Eq $m[0].Code 'auto' 'liste modeli: ilk satır Otomatik'
Assert-Eq $m[0].Name 'Otomatik' 'liste modeli: Otomatik satırının adı'
Assert-Eq $m[0].Sub 'Windows ekran dili: Deutsch' 'liste modeli: Otomatik satırı Windows dilini yerel adıyla gösterir'
Assert-Eq $m[0].Chip '' 'liste modeli: Otomatik satırında kod rozeti yok'
Assert-Eq (@($m | Where-Object { $_.Checked }).Count) 1 'liste modeli: tek satır işaretli (auto)'
Assert-True ([bool]$m[0].Checked) 'liste modeli: auto kayıtlıyken Otomatik işaretli'
$trRow = @($m | Where-Object { $_.Code -eq 'tr' })[0]
Assert-Eq $trRow.Name ('T' + [char]0x00FC + 'rk' + [char]0x00E7 + 'e') 'liste modeli: Türkçe yerel adıyla'
Assert-Eq $trRow.Sub 'Turkish' 'liste modeli: Türkçe satırında kapsam yüzdesi yok'
Assert-Eq $trRow.Chip 'TR' 'liste modeli: Türkçe rozeti'
$enRow = @($m | Where-Object { $_.Code -eq 'en' })[0]
Assert-Eq $enRow.Sub 'English' 'liste modeli: tam kapsamlı dilde yüzde gösterilmez'
$deRow = @($m | Where-Object { $_.Code -eq 'de' })[0]
$deE = Get-LangEntry 'de'
Assert-True ([int]$deE.Coverage -gt 0 -and [int]$deE.Coverage -le 100) 'Almanca: kapsam başlıkta yazılı'
Assert-Eq $deRow.Name 'Deutsch' 'liste modeli: Almanca yerel adıyla'
if ([int]$deE.Coverage -ge 100) { Assert-Eq $deRow.Sub 'German' 'liste modeli: tam kapsamlı Almanca satırında yüzde gösterilmez' }
# kısmi kapsamlı dil (çeviriler tamamlandıkça değişir): kapsamı 100'ün altındaki ilk dil dosyası
$pE = @($all | Where-Object { [string]$_.Code -ne 'tr' -and [int]$_.Coverage -gt 0 -and [int]$_.Coverage -lt 100 } | Select-Object -First 1)
$pSub = ''
if ($pE.Count -gt 0) {
    $pRow = @($m | Where-Object { $_.Code -eq [string]$pE[0].Code })[0]
    $pSub = [string]$pE[0].English + '  ' + $mid + '  %' + [string]$pE[0].Coverage
    Assert-Eq $pRow.Sub $pSub ('liste modeli: kısmi kapsamlı dilde İngilizce ad ve yüzde (' + [string]$pE[0].Code + ')')
}
Assert-Eq $deRow.Chip 'DE' 'liste modeli: Almanca rozeti'
Assert-Eq (@($m | Where-Object { $_.Code -eq 'zh-hant' })[0].Chip) 'ZH-TW' 'liste modeli: Geleneksel Çince rozeti ZH-TW'
Assert-True ($script:LangOut.Contains('Deutsch') -and $script:LangOut.Contains('Windows ekran dili: Deutsch')) 'liste modeli: dil adları çeviri denetiminde özel ad sayılır'
$codes = @($m | ForEach-Object { $_.Code })
Assert-Eq (@($codes | Select-Object -Unique).Count) $codes.Count 'liste modeli: her kod bir kez'
foreach ($want in @('auto', 'tr', 'de', 'zh-hant', 'ZH-HANT', 'xx')) {
    $script:Settings = @{ Language = $want }
    $mm = @(Get-LangMenuModel)
    $chk = @($mm | Where-Object { $_.Checked })
    Assert-Eq $chk.Count 1 ("liste modeli: kayıtlı '$want' iken tam bir satır işaretli")
    if ($want -ne 'xx') { Assert-Eq $chk[0].Code $want.ToLowerInvariant() ("liste modeli: kayıtlı '$want' işaretli") }
}
$script:Settings = @{ Language = 'auto' }
$script:LangOut = $null
Add-LangNameOut 'abc'
Assert-True $true 'dil adı kaydı: izleme kapalıyken hata vermez'

# ======================= 5) düğmenin yazısı ve ipucu =======================
$script:T_Sys = 'tr'; $script:LangCode = 'tr'; $script:Settings = @{ Language = 'auto' }
$i = Get-LangButtonInfo
Assert-Eq $i.Code 'TR' 'düğme: çalışan dil Türkçe -> TR'
Assert-Eq $i.Name ('T' + [char]0x00FC + 'rk' + [char]0x00E7 + 'e') 'düğme: yerel dil adı'
Assert-Eq $i.Tip ('Aray' + [char]0x00FC + 'z dili: T' + [char]0x00FC + 'rk' + [char]0x00E7 + 'e (otomatik)') 'düğme: otomatik seçimde ipucu "(otomatik)" der'
$script:Settings = @{ Language = 'tr' }
Assert-Eq (Get-LangButtonInfo).Tip ('Aray' + [char]0x00FC + 'z dili: T' + [char]0x00FC + 'rk' + [char]0x00E7 + 'e') 'düğme: elle seçimde ipucunda "(otomatik)" yok'
$script:LangCode = 'zh-hant'; $script:Settings = @{ Language = 'zh-hant' }
$i = Get-LangButtonInfo
Assert-Eq $i.Code 'ZH-TW' 'düğme: Geleneksel Çince -> ZH-TW'
Assert-Eq $i.Name ((Get-LangEntry 'zh-hant').Native) 'düğme: Geleneksel Çince yerel adı'
$script:LangCode = ''
Assert-Eq (Get-LangButtonInfo).Code 'TR' 'düğme: dil kodu boşsa Türkçe'
$script:LangCode = 'xx'
$i = Get-LangButtonInfo
Assert-True ($i.Code -eq 'XX' -and $i.Name -eq 'xx') 'düğme: bilinmeyen kodda kodun kendisi gösterilir'
$script:LangCode = 'tr'

# ======================= 6) dil değişikliği planı =======================
$script:Settings = @{ Language = 'auto' }; $script:T_Sys = 'tr'; $script:LangCode = 'tr'
Assert-Eq (Get-LangChangePlan 'auto') 'ayni' 'plan: auto zaten seçili'
Assert-Eq (Get-LangChangePlan 'tr') 'kaydet' 'plan: Windows dili Türkçe iken auto -> tr yalnızca kayıt'
Assert-Eq (Get-LangChangePlan 'en') 'yeniden' 'plan: başka dil yeniden başlatma ister'
Assert-Eq (Get-LangChangePlan ' EN ') 'yeniden' 'plan: boşluk ve büyük harf önemsenmez'
Assert-Eq (Get-LangChangePlan 'xx') 'yok' 'plan: bilinmeyen dil'
Assert-Eq (Get-LangChangePlan '') 'yok' 'plan: boş seçim'
$script:Settings = @{ Language = 'tr' }
Assert-Eq (Get-LangChangePlan 'tr') 'ayni' 'plan: tr zaten seçili'
Assert-Eq (Get-LangChangePlan 'auto') 'kaydet' 'plan: tr -> auto (Windows dili Türkçe) yalnızca kayıt'
$script:T_Sys = 'de'
Assert-Eq (Get-LangChangePlan 'auto') 'yeniden' 'plan: tr -> auto (Windows dili Almanca) yeniden başlatma ister'
$script:T_Sys = 'en'; $script:LangCode = 'en'; $script:Settings = @{ Language = 'en' }
Assert-Eq (Get-LangChangePlan 'en') 'ayni' 'plan: çalışan dil ve seçim aynı'
Assert-Eq (Get-LangChangePlan 'auto') 'kaydet' 'plan: en -> auto (Windows dili İngilizce) yalnızca kayıt'
Assert-Eq (Get-LangChangePlan 'tr') 'yeniden' 'plan: en -> tr yeniden başlatma ister'

# ======================= 7) Request-LangChange akışları =======================
Reset-Hdr; $script:LangCode = 'tr'; $script:T_Sys = 'tr'; $script:Settings = @{ Language = 'auto' }
Assert-Eq (Request-LangChange 'xx') 'yok' 'istek: bilinmeyen dil'
Assert-True ($script:Toasts.Count -eq 1 -and $script:Toasts[0].K -eq 'warn' -and $script:Toasts[0].T -eq ('Bu dil kullan' + [char]0x0131 + 'lam' + [char]0x0131 + 'yor.')) 'istek: bilinmeyen dilde uyarı'
Assert-True ($script:Saved.Count -eq 0 -and $script:Confirms.Count -eq 0) 'istek: bilinmeyen dil kayıt ve onay açmaz'
Reset-Hdr; $script:LangCode = 'tr'
Assert-Eq (Request-LangChange 'auto') 'ayni' 'istek: aynı seçim'
Assert-True ($script:Saved.Count -eq 0 -and $script:Confirms.Count -eq 0 -and $script:Toasts.Count -eq 0) 'istek: aynı seçimde hiçbir şey yapılmaz'
Reset-Hdr; $script:LangCode = 'tr'; $script:Settings = @{ Language = 'auto' }; $script:T_Sys = 'tr'
Assert-Eq (Request-LangChange 'tr') 'kaydet' 'istek: arayüz dili değişmiyorsa yalnızca kayıt'
Assert-Eq $script:Settings.Language 'tr' 'istek: ayar belleğe yazıldı'
Assert-Eq ($script:Saved -join ',') 'tr' 'istek: ayar dosyaya bir kez yazıldı'
Assert-True ($script:Confirms.Count -eq 0 -and $script:Restarted -eq 0) 'istek: yeniden başlatma onayı çıkmaz'
Assert-True ($script:Toasts.Count -eq 1 -and $script:Toasts[0].K -eq 'good' -and $script:Toasts[0].T.StartsWith('Dil tercihi kaydedildi: ')) 'istek: kayıt bildirimi'
Assert-Eq $ui.TxtLangCode.Text 'TR' 'istek: kayıttan sonra düğme yenilenir (kod)'
Assert-True ([string]$ui.BtnLang.ToolTip -notmatch 'otomatik') 'istek: kayıttan sonra düğme ipucu elle seçimi gösterir'
Reset-Hdr; $script:LangCode = 'tr'; $script:Settings = @{ Language = 'tr' }; $script:T_Sys = 'tr'
Assert-Eq (Request-LangChange 'auto') 'kaydet' 'istek: tr -> auto yalnızca kayıt'
Assert-True ($script:Saved[0] -eq 'auto' -and $script:Toasts[0].T -eq 'Dil tercihi kaydedildi: Otomatik') 'istek: Otomatik kaydı bildirimi'
Reset-Hdr; $script:LangCode = 'tr'; $script:Settings = @{ Language = 'auto' }; $script:T_Sys = 'tr'; $script:Busy = $true
Assert-Eq (Request-LangChange 'en') 'mesgul' 'istek: işlem sürerken yeniden başlatma yapılmaz'
Assert-True ($script:Toasts.Count -eq 1 -and $script:Toasts[0].K -eq 'warn' -and $script:Toasts[0].T.Contains('bitince dili de')) 'istek: meşgulken uyarı'
Assert-True ($script:Confirms.Count -eq 0 -and $script:Saved.Count -eq 0 -and $script:Settings.Language -eq 'auto') 'istek: meşgulken onay ve kayıt yok'
Assert-Eq (Request-LangChange 'tr') 'kaydet' 'istek: işlem sürerken bile yalnızca kayıt serbest (uygulama kapanmaz)'
Reset-Hdr; $script:LangCode = 'tr'; $script:Settings = @{ Language = 'auto' }; $script:T_Sys = 'tr'
Assert-Eq (Request-LangChange ' DE ') 'yeniden' 'istek: başka dil onay ister'
Assert-Eq $script:Confirms.Count 1 'istek: tek onay penceresi'
Assert-Eq $script:Confirms[0].Title ('Dil de' + [char]0x011F + 'i' + [char]0x015F + 'ikli' + [char]0x011F + 'i') 'istek: onay başlığı'
Assert-Eq $script:Confirms[0].Ok ('Yeniden ba' + [char]0x015F + 'lat') 'istek: onay düğmesi'
Assert-True ($script:Confirms[0].Text.Contains('Deutsch')) 'istek: onay metni seçilen dilin yerel adını içerir'
Assert-True ($script:Saved.Count -eq 0 -and $script:Settings.Language -eq 'auto' -and $script:Restarted -eq 0) 'istek: onaydan önce hiçbir şey değişmez'
& $script:Confirms[0].OnOk
Assert-Eq $script:Settings.Language 'de' 'istek: onaydan sonra ayar yazılır'
Assert-Eq ($script:Saved -join ',') 'de' 'istek: onaydan sonra dosyaya kaydedilir'
Assert-True ($script:Restarted -eq 1 -and $script:Exited -eq 1) 'istek: onaydan sonra yeniden başlatılır ve çıkılır'
Reset-Hdr; $script:LangCode = 'tr'; $script:Settings = @{ Language = 'tr' }; $script:T_Sys = 'de'
Assert-Eq (Request-LangChange 'auto') 'yeniden' 'istek: Windows dili farklıyken Otomatik yeniden başlatma ister'
Assert-True ($script:Confirms[0].Text.Contains('Otomatik')) 'istek: onay metni Otomatik der'
& $script:Confirms[0].OnOk
Assert-Eq $script:Settings.Language 'auto' 'istek: auto kaydedilir'

# ======================= 8) liste: kurma, açma/kapama, odak =======================
Reset-Hdr; $script:LangCode = 'tr'; $script:Settings = @{ Language = 'de' }; $script:T_Sys = 'tr'
Update-LangMenu
Assert-Eq $ui.LangItems.Children.Count ($all.Count + 1) 'liste: Otomatik + her dil satırı kuruldu'
Assert-Eq $script:LangPopFocus.Tag 'de' 'liste: odak işaretli (kayıtlı) satırda'
Assert-Eq ($ui.LangItems.Children | Where-Object { $_.IsChecked } | ForEach-Object { $_.Tag }) 'de' 'liste: yalnızca kayıtlı satır işaretli'
Update-LangMenu
Assert-Eq $ui.LangItems.Children.Count ($all.Count + 1) 'liste: yeniden kurulunca satırlar çoğalmaz'
Reset-Hdr; $script:LangCode = 'tr'; $script:Settings = @{ Language = 'auto' }
Show-LangMenu
Assert-True ([bool]$ui.LangPop.IsOpen) 'liste: düğme listeyi açar'
Assert-True ($ui.LangPop.PlacementTarget -eq $ui.LangCapsule) 'liste: kapsülün altında açılır'
Assert-Eq $script:NavClosed 1 'liste: açılırken sol menü kapanır'
Assert-Eq $ui.LangItems.Children.Count ($all.Count + 1) 'liste: açılırken satırlar kurulur'
Show-LangMenu
Assert-True (-not [bool]$ui.LangPop.IsOpen) 'liste: açıkken düğme listeyi kapatır'
$script:LangPopClosedAt = [datetime]::UtcNow
Show-LangMenu
Assert-True (-not [bool]$ui.LangPop.IsOpen) 'liste: kapandıktan hemen sonraki tıklama yeniden açmaz (StaysOpen=False çift tıklaması)'
$script:LangPopClosedAt = [datetime]::UtcNow.AddSeconds(-2)
Show-LangMenu
Assert-True ([bool]$ui.LangPop.IsOpen) 'liste: bekleme süresi geçince yeniden açılır'
Select-LangRow 'tr'
Assert-True (-not [bool]$ui.LangPop.IsOpen) 'liste: satır seçilince liste kapanır'
Assert-Eq $script:Settings.Language 'tr' 'liste: satır seçimi dil isteğini işler'
Set-LangPopFocus
$script:LangPopFocus = New-LangRow @{ Code = 'x'; Name = 'x'; Sub = ''; Chip = ''; Checked = $false }
Set-LangPopFocus
Assert-Eq $script:LangPopFocus.Focused 1 'liste: açılınca odak seçili satıra verilir'
$ui.LangPop.IsOpen = $false
Close-LangMenu
Assert-True $true 'liste: kapalıyken kapatmak hata vermez'
$ui2 = $script:ui; $script:ui = @{}; $ui = $script:ui
Close-LangMenu; Update-LangMenu; Update-LangButton; Show-LangMenu
Assert-True $true 'liste: denetimler yokken işlevler sessizce döner'
$script:ui = $ui2; $ui = $script:ui

# ======================= 9) emblem tıklaması =======================
Reset-Hdr
$script:UiState = @{ Page = 'settings' }
Invoke-HomeClick
Assert-Eq ($script:ShownPages -join ',') 'panel' 'emblem: başka sayfadayken durum panosu açılır'
Assert-True ($script:ScrollTo.Count -eq 0 -and $script:PageFocused -eq 1 -and $script:NavClosed -eq 1) 'emblem: menü kapanır, odak sayfaya döner, kaydırma yapılmaz'
foreach ($pg in @('optimize', 'network', 'backup', 'apps')) {
    Reset-Hdr; $script:UiState = @{ Page = $pg }
    Invoke-HomeClick
    Assert-Eq ($script:ShownPages -join ',') 'panel' "emblem: $pg sayfasından durum panosuna gider"
}
foreach ($pg in @('panel', 'board')) {
    Reset-Hdr; $script:UiState = @{ Page = $pg }
    Invoke-HomeClick
    Assert-Eq $script:ShownPages.Count 0 "emblem: zaten $pg sayfasındayken sayfa değişmez"
    Assert-Eq ($script:ScrollTo -join ',') '0' "emblem: $pg sayfasında en üste kaydırır"
}
Reset-Hdr; $script:UiState = @{ Page = 'panel' }; $script:HasScroller = $false
Invoke-HomeClick
Assert-True ($script:ShownPages.Count -eq 0 -and $script:PageFocused -eq 1) 'emblem: kaydırıcı yoksa hata vermez'
Reset-Hdr; $ui.LangPop.IsOpen = $true; $script:UiState = @{ Page = 'settings' }
Invoke-HomeClick
Assert-True (-not [bool]$ui.LangPop.IsOpen) 'emblem: açık dil listesini kapatır'
function Close-NavMenu { throw 'menu hatasi' }
Reset-Hdr; $script:UiState = @{ Page = 'settings' }
Invoke-HomeClick
Assert-Eq ($script:ShownPages -join ',') 'panel' 'emblem: menü kapatılamasa da ana sayfa açılır'
function Close-NavMenu { $script:NavClosed++ }

# ======================= 10) olay bağlantıları =======================
Reset-Hdr; $script:LangCode = 'tr'; $script:Settings = @{ Language = 'auto' }
Initialize-HeaderBar
Assert-Eq $ui.BtnHome.Handlers.Count 1 'bağlantı: emblem tıklaması bağlı'
Assert-Eq $ui.BtnLang.Handlers.Count 1 'bağlantı: dil düğmesi tıklaması bağlı'
Assert-True ($ui.LangPop.Ev.ContainsKey('Opened') -and $ui.LangPop.Ev.ContainsKey('Closed') -and $ui.LangPop.Child.Ev.ContainsKey('Key')) 'bağlantı: liste açılma, kapanma ve tuş olayları bağlı'
Assert-Eq $ui.TxtLangCode.Text 'TR' 'bağlantı: başlangıçta dil kodu yazılır'
Assert-True ([string]$ui.BtnLang.ToolTip -ne '') 'bağlantı: başlangıçta ipucu yazılır'
Assert-Eq $ui.LangItems.Children.Count ($all.Count + 1) 'bağlantı: liste açılışta önceden kurulur'
& $ui.BtnHome.Handlers[0]
Assert-Eq ($script:ShownPages -join ',') 'panel' 'bağlantı: emblem tıklaması ana sayfaya götürür'
& $ui.BtnLang.Handlers[0]
Assert-True ([bool]$ui.LangPop.IsOpen) 'bağlantı: dil düğmesi listeyi açar'
& $ui.LangPop.Ev['Opened']
Assert-Eq $ui.BtnLang.Tag 'open' 'bağlantı: liste açılınca düğme etkin görünümde'
$ui.LangPop.IsOpen = $false
& $ui.LangPop.Ev['Closed']
Assert-Eq $ui.BtnLang.Tag '' 'bağlantı: liste kapanınca düğme normal görünümde'
Assert-True (([datetime]::UtcNow - $script:LangPopClosedAt).TotalSeconds -lt 5) 'bağlantı: kapanma anı kaydedilir (çift tıklama koruması)'
$script:ui = @{}; $ui = $script:ui
Initialize-HeaderBar
Assert-True $true 'bağlantı: denetimler yokken Initialize-HeaderBar hata vermez'

# ======================= 11) kaynak bağlantıları =======================
function Get-FnText([string]$Name) { return [string](@(Get-AstFunctions | Where-Object { $_.Name -eq $Name }) | Select-Object -Last 1).Extent.Text }
$shell = Get-FnText 'Initialize-Shell'
Assert-True ($shell.Contains('Initialize-HeaderBar')) 'kabuk: Initialize-HeaderBar çağrılır'
Assert-True ($shell.IndexOf('BtnCmdToggle.Add_Click') -lt $shell.IndexOf('Initialize-HeaderBar')) 'kabuk: başlık çubuğu, komut düğmesinden sonra bağlanır'
Assert-True ($shell.Contains('Write-CrashLog') -and $shell.Contains('Close-LangMenu')) 'kabuk: başlık hatası günlüğe yazılır; pencere pasifleşince dil listesi kapanır'
$lvl = Get-FnText 'Set-TitleLevel'
Assert-True ($lvl.Contains('TxtLangCode') -and $lvl.Contains('$Level -lt 2')) 'başlık düzeyi: dar pencerede dil kodu yazısı gizlenir (simge kalır)'
Assert-True ((Get-FnText 'Measure-TitleNatural').Contains('TxtLangCode')) 'başlık ölçümü: dil kodunun genişliği hesaba katılır'
Assert-True ($script:SmokeSafe -contains 'BtnHome') 'duman testi: emblem düğmesine tıklayabilir'
Assert-True ($script:SmokeSafe -notcontains 'BtnLang') 'duman testi: dil düğmesine tıklamaz (liste kodla açılır, dil seçilmez)'
Assert-True ($script:SmokeScopes.ContainsKey('ust') -and (@($script:SmokeScopes['ust']) -join ',') -eq 'ust') 'duman testi: yalnızca üst çubuğu deneyen "ust" kapsamı var'
Assert-True ((@($script:SmokeScopes['tam']) -contains 'ust') -and (@($script:SmokeScopes['dil']) -contains 'ust')) 'duman testi: tam ve dil kapsamları üst çubuğu da dener'
Assert-True ((@($script:SmokeScopes['gorunum']) -notcontains 'ust')) 'duman testi: görünüm kapsamı değişmedi'
foreach ($fn in @('Test-SmokeHeader', 'Test-SmokeLangPop', 'Save-SmokeShotOf', 'Invoke-HomeClick', 'Request-LangChange', 'Initialize-HeaderBar')) {
    Assert-Eq @(Get-AstFunctions | Where-Object { $_.Name -eq $fn }).Count 1 ("$fn tek kez tanımlı")
}
$sl = Get-FnText 'Invoke-SmokeStep'
Assert-True ($sl.Contains("'UstCheck' { Test-SmokeHeader") -and $sl.Contains("'LangPop' { Test-SmokeLangPop")) 'duman testi: ust çubuk adımları işleyicide'
$tl = Get-FnText 'Test-SmokeLangPop'
Assert-True ($tl.Contains('Show-LangMenu') -and -not $tl.Contains('Request-LangChange') -and -not $tl.Contains('Select-LangRow')) 'duman testi: dil listesini açar ama dil seçmez'
Assert-True ((Get-FnText 'Initialize-HeaderBar').Contains('Key]::Escape')) 'bağlantı: Esc tuşu dil listesini kapatır'
Assert-True ((Get-FnText 'Invoke-StLangApply').Contains('Confirm-LangRestart')) 'Ayarlar > Dil kartı ve başlık düğmesi aynı yeniden başlatma akışını kullanır'

# ======================= 12) çevrilecek metinler =======================
Reset-Hdr; $script:TrSeen.Clear(); $script:LangCode = 'tr'
$script:LangOut = New-Object 'System.Collections.Generic.HashSet[string]'
$script:Settings = @{ Language = 'auto' }; $script:T_Sys = 'de'
Update-LangMenu; Update-LangButton; [void](Get-LangButtonInfo)
$script:Settings = @{ Language = 'tr' }; [void](Get-LangButtonInfo)
$script:Busy = $true; [void](Request-LangChange 'en'); $script:Busy = $false
[void](Request-LangChange 'xx')
$script:LangCode = 'tr'; $script:Settings = @{ Language = 'tr' }; $script:T_Sys = 'tr'; [void](Request-LangChange 'auto')
$srcTexts = New-Object System.Collections.ArrayList
foreach ($s in $script:TrSeen) { [void]$srcTexts.Add([string]$s) }
foreach ($t in $script:Toasts) { [void]$srcTexts.Add([string]$t.T) }
$newKeys = @('Ana sayfa: durum panosuna dön', 'Ana sayfa', 'Arayüz dili', 'Arayüz dili: {0}', 'Arayüz dili: {0} (otomatik)', 'Otomatik', 'Windows ekran dili: {0}',
    'Dil değişince uygulama kendini yeniden başlatır.', 'Dil tercihi kaydedildi: {0}', 'Çalışan bir işlem var; bitince dili değiştirin.', 'Bu dil kullanılamıyor.')
foreach ($f in $packFiles) {
    $code = $f.BaseName
    $keys = @{}
    foreach ($ln in [System.IO.File]::ReadAllLines($f.FullName, [System.Text.Encoding]::UTF8)) {
        if ($ln.Length -eq 0 -or $ln[0] -eq '#') { continue }
        $tab = $ln.IndexOf("`t")
        if ($tab -lt 1) { continue }
        $keys[$ln.Substring(0, $tab)] = $ln.Substring($tab + 1)
    }
    $lack = @($newKeys | Where-Object { -not $keys.ContainsKey($_) -or [string]$keys[$_] -eq '' })
    Assert-Eq ($lack -join ' | ') '' "dil dosyası ${code}: üst çubuk metinleri çevrili"
    if ($code -eq 'en') {
        # kaynakta Tr/Format-Tr/Show-Toast ile verilen her sabit metin İngilizce dosyada birebir ya da şablonla bulunur
        $rx = @($keys.Keys | Where-Object { $_.Contains('{0}') } | ForEach-Object { New-Object System.Text.RegularExpressions.Regex(('^' + [regex]::Escape($_).Replace('\{0}', '.+') + '$')) })
        $uncovered = @()
        foreach ($s in $srcTexts) {
            $ok = $keys.ContainsKey($s)
            if (-not $ok) { foreach ($r in $rx) { if ($r.IsMatch($s)) { $ok = $true; break } } }
            if (-not $ok -and $script:LangOut.Contains($s)) { $ok = $true }
            if (-not $ok -and $uncovered -notcontains $s) { $uncovered += $s }
        }
        Assert-Eq ($uncovered -join ' | ') '' 'İngilizce dosya: başlık çubuğunun kodla verdiği her metin çevrili'
    }
}
Assert-True ($srcTexts.Count -ge 40) ('çeviri taraması: başlık çubuğunun metinleri toplandı (' + $srcTexts.Count + ')')
Assert-True ($script:LangOut.Contains('TR') -and $script:LangOut.Contains('ZH-TW') -and $script:LangOut.Contains('German') -and ($pSub -eq '' -or $script:LangOut.Contains($pSub))) 'çeviri taraması: dil kodları ve dil satırlarının ikinci satırı özel ad sayılır (eksik çeviri raporuna girmez)'
$script:LangOut = $null

Show-Result
