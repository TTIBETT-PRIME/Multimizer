# ==================================================================
#  UST CUBUK (cekirdek): dil dugmesinin gosterimi ve acilir listenin modeli
#  Saf mantik: ekrana dokunmaz; testlerde sahte ayarlarla denenir.
#  Dil secimi yeniden baslatmayla uygulanir (bkz. 141_i18n_ui.ps1); Windows dili zaten secilen dilse yeniden baslatma gerekmez.
# ==================================================================

# Dil kodunun dugmedeki kisa gosterimi: 'tr' -> 'TR'; bolge/yazi eki olan kodlar dil etiketinin bolgesini alir ('zh-hant' -> 'ZH-TW')
function Get-LangShortCode([string]$Code) {
    $c = $Code.Trim().ToLowerInvariant()
    if ($c -eq '') { return '--' }
    $i = $c.IndexOf('-')
    if ($i -lt 0) { return $c.ToUpperInvariant() }
    $base = $c.Substring(0, $i)
    $tag = ''
    foreach ($l in @(Get-LangList)) { if ([string]$l.Code -eq $c) { $tag = [string]$l.Tag } }
    $j = $tag.IndexOf('-')
    if ($j -gt 0 -and $j -lt ($tag.Length - 1)) { return ($base + '-' + $tag.Substring($j + 1)).ToUpperInvariant() }
    return $c.ToUpperInvariant()
}

# Kayitli dil secimi: 'auto' ya da kucuk harfli dil kodu
function Get-LangStoredKey {
    $k = 'auto'
    try { $v = [string]$script:Settings.Language; if ($v.Trim() -ne '') { $k = $v.Trim().ToLowerInvariant() } } catch { }
    return $k
}

# Dil adlari ozel addir: ceviri denetiminde (izleme acikken) eksik ceviri ya da sizinti sayilmaz
function Add-LangNameOut([string]$Text) {
    if ($null -ne $script:LangOut -and $Text.Length -gt 0) { [void]$script:LangOut.Add($Text) }
}

# Acilir liste satirlari: Otomatik + Turkce + bulunan dil dosyalari. Kayit: Code, Name (yerel ad), Sub (ikinci satir), Chip (kisa kod), Checked (kayitli secim)
# Donus acilir (virgulsuz); cagiran @(Get-LangMenuModel) yazar.
function Get-LangMenuModel {
    $stored = Get-LangStoredKey
    $mark = $stored
    if ($stored -ne 'auto') { $mark = Resolve-LangCode $stored }
    $list = @(Get-LangList)
    foreach ($l in $list) { Add-LangNameOut ([string]$l.Native) }
    $sys = Get-SystemLangCode
    $sysName = $sys
    foreach ($l in $list) { if ([string]$l.Code -eq $sys) { $sysName = [string]$l.Native } }
    $rows = New-Object System.Collections.ArrayList
    $subAuto = Format-Tr 'Windows ekran dili: {0}' $sysName
    Add-LangNameOut $subAuto
    [void]$rows.Add(@{ Code = 'auto'; Name = (Tr 'Otomatik'); Sub = $subAuto; Chip = ''; Checked = ($stored -eq 'auto') })
    foreach ($l in $list) {
        $code = [string]$l.Code
        $sub = [string]$l.English
        $cov = 0
        try { $cov = [int]$l.Coverage } catch { $cov = 0 }
        if ($code -ne 'tr' -and $cov -gt 0 -and $cov -lt 100) { $sub = $sub + '  ' + [char]0x00B7 + '  ' + (Format-Percent $cov) }
        $chip = Get-LangShortCode $code
        Add-LangNameOut $sub
        Add-LangNameOut $chip
        [void]$rows.Add(@{ Code = $code; Name = [string]$l.Native; Sub = $sub; Chip = $chip; Checked = (($stored -ne 'auto') -and ($mark -eq $code)) })
    }
    return $rows.ToArray()
}

# Dil dugmesinin yazisi ve aracipucu: calisan arayuz dilini gosterir (secim yeniden baslatmayla uygulanir)
function Get-LangButtonInfo {
    $run = [string]$script:LangCode
    if ($run -eq '') { $run = 'tr' }
    $name = $run
    foreach ($l in @(Get-LangList)) { if ([string]$l.Code -eq $run) { $name = [string]$l.Native } }
    Add-LangNameOut $name
    $code = Get-LangShortCode $run
    Add-LangNameOut $code
    $tip = ''
    if ((Get-LangStoredKey) -eq 'auto') { $tip = Format-Tr 'Arayüz dili: {0} (otomatik)' $name } else { $tip = Format-Tr 'Arayüz dili: {0}' $name }
    Add-LangNameOut $tip
    return @{ Code = $code; Name = $name; Tip = $tip }
}

# Bir dil secimi icin gereken islem: 'yok' (bilinmeyen dil) | 'ayni' (degisiklik yok) | 'kaydet' (arayuz dili degismiyor: yalnizca ayar yazilir) | 'yeniden' (yeniden baslatma gerekir)
function Get-LangChangePlan([string]$Key) {
    $k = $Key.Trim().ToLowerInvariant()
    if ($k -eq '') { return 'yok' }
    $eff = $k
    if ($k -eq 'auto') { $eff = Get-SystemLangCode } else {
        $known = $false
        foreach ($l in @(Get-LangList)) { if ([string]$l.Code -eq $k) { $known = $true } }
        if (-not $known) { return 'yok' }
    }
    $run = [string]$script:LangCode
    if ($run -eq '') { $run = 'tr' }
    if ($k -eq (Get-LangStoredKey) -and $eff -eq $run) { return 'ayni' }
    if ($eff -eq $run) { return 'kaydet' }
    return 'yeniden'
}
