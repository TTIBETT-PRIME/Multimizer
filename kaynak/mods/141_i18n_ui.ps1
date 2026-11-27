# ==================================================================
#  DIL DESTEGI: Ayarlar karti, yeniden baslatma, kalite denetimi
# ==================================================================
# Dil secimi yeniden baslatmayla uygulanir: butun ekran metinleri acilista bir kez cevrilir (parcalar ve satirlar olusturulurken).
# Secilen dil Ayarlar'a "Language" olarak yazilir; "auto" Windows ekran dilini izler.

$script:LangPending = ''

function Get-LangChoiceName($L) {
    $n = [string]$L.Native
    $e = [string]$L.English
    $t = $n
    if ($n -cne $e) { $t = $n + ' (' + $e + ')' }
    $cov = 0
    try { $cov = [int]$L.Coverage } catch { $cov = 0 }
    if ([string]$L.Code -ne 'tr' -and $cov -gt 0 -and $cov -lt 100) { $t = $t + '  -  ' + (Format-Percent $cov) }
    # dil adlari ozel addir; kalite denetiminde eksik cevirisi sayilmaz
    if ($null -ne $script:LangOut) { [void]$script:LangOut.Add($t) }
    return $t
}

function Get-LangFolderUser {
    $pd = ''
    try { $pd = [Environment]::GetFolderPath('CommonApplicationData') } catch { $pd = '' }
    if ($pd -eq '') { return '' }
    return [System.IO.Path]::Combine($pd, 'Multimizer', 'dil')
}

function Get-LangEntry([string]$Code) {
    foreach ($l in @(Get-LangList)) { if ([string]$l.Code -eq $Code) { return $l } }
    return $null
}

# Ayarlar > Dil karti: acilir listeyi doldurur (Otomatik + Turkce + bulunan dil dosyalari)
function Initialize-StLang {
    if ($null -eq $ui.st_LangSel) { return }
    $ch = New-Object System.Collections.ArrayList
    [void]$ch.Add((New-Choice 'auto' 'Otomatik (Windows ekran dili)'))
    foreach ($l in @(Get-LangList $true)) { [void]$ch.Add((New-Choice ([string]$l.Code) (Get-LangChoiceName $l))) }
    Set-ComboChoices $ui.st_LangSel $ch.ToArray()
}

# Kayitli dil secimini listede gosterir (secim olayi kayit yapmaz)
function Load-StLang {
    if ($null -eq $ui.st_LangSel) { return }
    $want = 'auto'
    try { $v = [string]$script:Settings.Language; if ($v.Trim() -ne '') { $want = $v.Trim().ToLowerInvariant() } } catch { }
    if ($want -ne 'auto') { $want = Resolve-LangCode $want }
    if (-not (Select-ComboKey $ui.st_LangSel $want)) { [void](Select-ComboKey $ui.st_LangSel 'auto') }
    $script:LangPending = ''
    Update-StLangNote
}

# Secim, kayitli ayardan ya da calisan dilden farkliysa "Uygula" etkinlesir; kapsam yuzdesi ve uyari yazilir
function Update-StLangNote {
    if ($null -eq $ui.st_LangNote) { return }
    $key = Get-ComboKey $ui.st_LangSel
    if ($key -eq '') { $key = 'auto' }
    $stored = 'auto'
    try { $v = [string]$script:Settings.Language; if ($v.Trim() -ne '') { $stored = $v.Trim().ToLowerInvariant() } } catch { }
    $eff = $key
    if ($key -eq 'auto') { $eff = Get-SystemLangCode }
    $pending = (($key -ne $stored) -or ($eff -ne [string]$script:LangCode))
    $ui.st_LangApply.IsEnabled = $pending
    $cov = 100
    $e = Get-LangEntry $eff
    if ($null -ne $e) { $cov = [int]$e.Coverage }
    $msg = ''
    if ($eff -eq 'tr') {
        $msg = 'Uygulamanın kaynak dili Türkçedir; tüm metinler eksiksizdir.'
    } elseif ($cov -ge 100 -or $cov -le 0) {
        $msg = 'Çeviri kapsamı: %100. Değişiklik uygulamanın yeniden başlatılmasıyla geçerli olur.'
    } else {
        $msg = ('Çeviri kapsamı: %' + [string]$cov + '. Çevrilmemiş metinler İngilizce, o da yoksa Türkçe gösterilir. Değişiklik uygulamanın yeniden başlatılmasıyla geçerli olur.')
    }
    if ($null -ne $e -and [bool]$e.User) { $msg = $msg + ' ' + 'Bu dil dosyası kullanıcı klasöründen yüklendi.' }
    $ui.st_LangNote.Text = $msg
}

# Yeniden baslatma yardimcisinin komut satiri: gizli bir PowerShell, bu surecin bitmesini bekler (tek-kopya kilidi birakilsin), sonra betigi yeniden acar.
# Yonetici hakki korunur: yukseltilmis surecin actigi surec de yukseltilmis acilir.
function Get-RestartArgs([string]$PsPath, [string]$ScriptPath, [int]$WaitPid) {
    $q = [string][char]39
    # Gizli baslatmada yeniden acilis de Acilis.ps1 uzerinden gider (ayni acilis ekrani ve ayni denetim); dosya yoksa betik dogrudan acilir
    $target = $ScriptPath
    $extra = ''
    if ($script:GizliMode -eq $true) {
        $ac = Join-Path (Split-Path -Parent $ScriptPath) 'Acilis.ps1'
        if (Test-Path -LiteralPath $ac) { $target = $ac; $extra = ' -Kod ' + [string](Get-Random -Minimum 100000 -Maximum 999999999) }
    }
    $inner = 'try { Wait-Process -Id ' + [string]$WaitPid + ' -Timeout 30 -ErrorAction Stop } catch { }; Start-Sleep -Milliseconds 700; Start-Process -FilePath ' + $q + $PsPath.Replace($q, $q + $q) + $q + ' -ArgumentList ' + $q + '-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "' + $target.Replace($q, $q + $q) + '"' + $extra + $q + ' -WindowStyle Hidden'
    $enc = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($inner))
    return ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -EncodedCommand ' + $enc)
}

function Restart-App {
    $ps = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $scr = [string]$sync.ScriptPath
    if (-not (Test-Path -LiteralPath $ps) -or [string]::IsNullOrEmpty($scr)) { return $false }
    $mine = [System.Diagnostics.Process]::GetCurrentProcess().Id
    try {
        Start-Process -FilePath $ps -ArgumentList (Get-RestartArgs $ps $scr $mine) -WindowStyle Hidden -ErrorAction Stop | Out-Null
    } catch { return $false }
    return $true
}

# Onaydan sonra: dil secimi ayara yazilir ve uygulama yeniden baslatilir (Ayarlar karti ve baslik cubugundaki dil dugmesi ortak kullanir)
function Complete-LangChange([string]$Key) {
    if ($Key -eq '') { return }
    $script:Settings.Language = $Key
    Save-Settings $script:Settings
    if (Restart-App) { Exit-App } else { Show-Toast 'Uygulama yeniden başlatılamadı; kapatıp elle açın. Dil ayarı kaydedildi.' 'warn' }
}

# Yeniden baslatma onayi: Tamam denirse Complete-LangChange calisir
function Confirm-LangRestart([string]$Key) {
    $script:LangPending = $Key
    $shown = $Key
    if ($Key -eq 'auto') { $shown = 'Otomatik' } else {
        $e = Get-LangEntry $Key
        if ($null -ne $e) { $shown = [string]$e.Native }
    }
    Show-Confirm 'Dil değişikliği' ('Arayüz dili şu olarak değiştirilecek: ' + $shown + '. Uygulama kapanıp yeniden açılır; çalışan işlem varsa önce bitmesini bekleyin.') 'Yeniden başlat' {
        Invoke-Safe { Complete-LangChange ([string]$script:LangPending) } 'Dil'
    }
}

function Invoke-StLangApply {
    $key = Get-ComboKey $ui.st_LangSel
    if ($key -eq '') { return }
    Confirm-LangRestart $key
}

function Init-StLangEvents {
    if ($null -eq $ui.st_LangSel) { return }
    $ui.st_LangSel.Add_SelectionChanged({
        if ($script:StLoading) { return }
        Invoke-Safe { Update-StLangNote } 'Dil'
    })
    $ui.st_LangApply.Add_Click({ Invoke-Safe { Invoke-StLangApply } 'Dil' })
    $ui.st_LangFolder.Add_Click({
        Invoke-Safe {
            $d = Get-LangFolderUser
            if ($d -eq '') { return }
            if (-not (Test-Path -LiteralPath $d -PathType Container)) { [void](New-Item -ItemType Directory -Path $d -Force) }
            Open-Folder $d
        } 'Dil'
    })
}

# ---------------- kalite denetimi: ekrandaki metinleri toplar ----------------
# Gorsel ve mantiksal agacta dolasip her metin ogesini (TextBlock, dugme, aracipucu) listeler.
# Donus (acilir, @() ile alinir): { Type; Text; Visible } kayitlari. Yalnizca okur.
function Get-UiTexts($Root) {
    $res = New-Object System.Collections.ArrayList
    if ($null -eq $Root) { return $res.ToArray() }
    $seen = New-Object 'System.Collections.Generic.HashSet[object]'
    $stack = New-Object System.Collections.Stack
    $stack.Push($Root)
    while ($stack.Count -gt 0) {
        $o = $stack.Pop()
        if ($null -eq $o) { continue }
        if (-not $seen.Add($o)) { continue }
        $txt = $null
        $kind = ''
        if ($o -is [System.Windows.Controls.TextBlock]) { $txt = [string]$o.Text; $kind = 'TextBlock' }
        elseif ($o -is [System.Windows.Controls.ContentControl]) {
            if ($o.Content -is [string]) { $txt = [string]$o.Content; $kind = $o.GetType().Name }
        }
        if ($null -ne $txt -and $txt.Trim().Length -gt 0) {
            $vis = $false
            try { if ($o -is [System.Windows.UIElement]) { $vis = [bool]$o.IsVisible } } catch { $vis = $false }
            [void]$res.Add(@{ Type = $kind; Text = $txt; Visible = $vis; Element = $o })
        }
        if ($o -is [System.Windows.Controls.ItemsControl]) {
            # acilir liste ve liste ogeleri: duz metin ya da Name alanli secenek tablosu (en cok 200 oge)
            $cnt = 0
            try {
                foreach ($it in $o.Items) {
                    $cnt++
                    if ($cnt -gt 200) { break }
                    $itxt = $null
                    if ($it -is [string]) { $itxt = [string]$it }
                    elseif ($it -is [System.Collections.IDictionary] -and $it.Contains('Name')) { $itxt = [string]$it['Name'] }
                    if ($null -ne $itxt -and $itxt.Trim().Length -gt 0) { [void]$res.Add(@{ Type = 'Item'; Text = $itxt; Visible = $false; Element = $o }) }
                }
            } catch { }
        }
        if ($o -is [System.Windows.FrameworkElement]) {
            $tt = $null
            try { $tt = $o.ToolTip } catch { $tt = $null }
            if ($tt -is [string] -and $tt.Trim().Length -gt 0) { [void]$res.Add(@{ Type = 'ToolTip'; Text = [string]$tt; Visible = $false; Element = $o }) }
        }
        if ($o -is [System.Windows.Media.Visual]) {
            $n = 0
            try { $n = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($o) } catch { $n = 0 }
            for ($i = 0; $i -lt $n; $i++) { try { $stack.Push([System.Windows.Media.VisualTreeHelper]::GetChild($o, $i)) } catch { } }
        }
        if ($o -is [System.Windows.DependencyObject]) {
            try { foreach ($c in [System.Windows.LogicalTreeHelper]::GetChildren($o)) { if ($c -is [System.Windows.DependencyObject]) { $stack.Push($c) } } } catch { }
        }
    }
    return $res.ToArray()
}

# Ekrandaki bir metin Tr'den gecmediyse ve Turkce harf iceriyorsa "sizinti" sayilir (cevrilmesi unutulmus bir yer)
function Test-LangLeak([string]$Text) {
    if (-not $script:LangOn -or $null -eq $script:LangSeen) { return $false }
    if ($script:LangSeen.Contains($Text)) { return $false }
    return [regex]::IsMatch($Text, '[çğıöşüÇĞİÖŞÜ]')
}

# Sabit genislikli acilir listede secili metin ceviride uzarsa kirpilmasin: genislik en uzun secenege gore buyutulur
function Fit-ComboWidth($Combo) {
    if ($null -eq $Combo -or -not $script:LangOn) { return }
    try {
        $w0 = [double]$Combo.Width
        if ([double]::IsNaN($w0) -or $w0 -le 0) { return }
        $need = 0.0
        $inf = [double]::PositiveInfinity
        foreach ($it in @($Combo.Items)) {
            $t = ''
            if ($it -is [System.Collections.IDictionary]) { if ($it.Contains('Name')) { $t = [string]$it['Name'] } } else { $t = [string]$it }
            if ($t.Length -eq 0) { continue }
            $p = New-Object System.Windows.Controls.TextBlock
            $p.Text = $t   # Tr:yok
            $p.FontFamily = $Combo.FontFamily
            $p.FontSize = [double]$Combo.FontSize
            $p.FontWeight = $Combo.FontWeight
            $p.Measure((New-Object System.Windows.Size($inf, $inf)))
            if ([double]$p.DesiredSize.Width -gt $need) { $need = [double]$p.DesiredSize.Width }
        }
        $want = [math]::Ceiling($need + 56.0)
        if ($want -gt $w0) { $Combo.Width = [math]::Min($want, 440.0) }
    } catch { }
}
