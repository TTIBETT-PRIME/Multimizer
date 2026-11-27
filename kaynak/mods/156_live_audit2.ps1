# ==================================================================
#  CANLI OZELLIK DENETIMI (2): etkiler, araclar, okuma isleri, saglik bulgulari
#  155_live_audit.ps1 ile birlikte calisir ("ozellik" duman kapsami). Kip kurallari orada anlatilir:
#  "oku" kipinde hicbir sey yazilmaz; "tam" kipte (yonetici) her degisiklik geri alinir ve eski halle karsilastirilir.
# ==================================================================

# ---------------- gorsel efektler: kayit defteri degil, CALISAN OTURUM ----------------
# Uygulamanin kendi bit listesi ($script:LiveMaskBits, 147) kullanilir; boylece uygulama neyi oturuma uyguluyorsa o denetlenir.
function Get-LiveSpiSet {
    $h = @{}
    foreach ($b in $script:LiveMaskBits) { $h[[string]$b] = [int][WH.Sys]::GetSpi([uint32](0x1000 + $b * 2)) }
    $h['drag'] = [int][WH.Sys]::GetSpi([uint32]0x26)
    $h['menudelay'] = [int][WH.Sys]::GetSpi([uint32]0x6A)
    return $h
}

function Format-LiveSpiSet($H) {
    return ((@($script:LiveMaskBits | ForEach-Object { 'b' + $_ + '=' + $H[[string]$_] }) + @('sürükle=' + $H['drag'], 'menü=' + $H['menudelay'])) -join ' ')
}

# Gorsel efektleri Windows varsayilanina ceker (yalnizca tam kip denetiminde, ayar zaten uygulanmissa; sonunda asil hale donulur)
function Set-LiveVisualDefaults {
    $desk = 'HKCU\Control Panel\Desktop'
    $adv = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    Set-RegData 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting' 'DWord' 0
    Set-RegData $desk 'UserPreferencesMask' 'Binary' ([byte[]]@(0x9E, 0x1E, 0x07, 0x80, 0x12, 0x00, 0x00, 0x00))
    Set-RegData $desk 'DragFullWindows' 'String' '1'
    Set-RegData $desk 'MenuShowDelay' 'String' '400'
    Set-RegData ($desk + '\WindowMetrics') 'MinAnimate' 'String' '1'
    Set-RegData $adv 'TaskbarAnimations' 'DWord' 1
    Set-RegData $adv 'ListviewAlphaSelect' 'DWord' 1
    Set-RegData $adv 'ListviewShadow' 'DWord' 1
    Set-RegData 'HKCU\Software\Microsoft\Windows\DWM' 'EnableAeroPeek' 'DWord' 1
}

function Wait-LiveSession {
    for ($i = 0; $i -lt 6; $i++) { try { Invoke-SmokeFlush } catch { }; Start-Sleep -Milliseconds 150 }
}

function Test-LiveVisual {
    $mode = Get-LiveMode
    $c = Get-CatalogItem 'VisualFx'
    if ($null -eq $c) { Add-LiveRow 'etki' 'gorsel' 'HATA' 'VisualFx ayarı katalogda yok'; return }
    if (-not (Initialize-SysNative)) { Add-LiveRow 'etki' 'gorsel' 'HATA' 'yerel işlevler (SystemParametersInfo) yüklenemedi'; return }
    $before = Get-LiveSpiSet
    # Windows oturum acarken maskeyi okuyup oturuma uygular: kayit defteri ile calisan oturum ayni olmali (eslemenin dogrulugu)
    $raw = Get-LiveRegRaw 'HKCU\Control Panel\Desktop' 'UserPreferencesMask'
    if ($raw.Exists -and $raw.Kind -eq 'Binary') {
        $mask = [byte[]]@($raw.Data)
        $diff = New-Object System.Collections.ArrayList
        foreach ($b in $script:LiveMaskBits) {
            $want = [bool](Get-MaskBit $mask $b)
            $have = ([int]$before[[string]$b] -ne 0)
            if ($want -ne $have) { [void]$diff.Add('bit ' + $b + ' (kayıt ' + $want + ', oturum ' + $have + ')') }
        }
        if ($diff.Count -gt 0) { Add-LiveRow 'etki' 'gorsel-oturum' 'UYARI' ('çalışan oturum kayıt defteriyle uyuşmuyor: ' + ($diff -join ', ') + ' (oturum açıldıktan sonra değiştirilmiş ya da bit eşlemesi yanlış olabilir)') }
        else { Add-LiveRow 'etki' 'gorsel-oturum' 'OK' ('çalışan oturum kayıt defteriyle uyumlu: ' + (Format-LiveSpiSet $before)) }
    } else { Add-LiveRow 'etki' 'gorsel-oturum' 'BILGI' 'UserPreferencesMask okunamadı' }

    $steps = New-StepsFromIds @('VisualFx')
    $pv = Invoke-LiveJob 'Job_Plan' @{ Steps = $steps; Preview = $true; RestorePoint = $false }
    if ($pv.Err -ne '') { Add-LiveRow 'etki' 'gorsel-onizleme' 'HATA' ('önizleme çöktü: ' + $pv.Err) }
    else {
        $now = Get-LiveSpiSet
        $moved = New-Object System.Collections.ArrayList
        foreach ($k in @($before.Keys)) { if ([int]$before[$k] -ne [int]$now[$k]) { [void]$moved.Add($k) } }
        if ($moved.Count -gt 0) { Add-LiveRow 'etki' 'gorsel-onizleme' 'HATA' ('önizleme çalışan oturumu değiştirdi: ' + ($moved -join ', ')) }
        else { Add-LiveRow 'etki' 'gorsel-onizleme' 'OK' ([string]$pv.Out.Changes + ' değişiklik önizlendi, oturum değişmedi') }
    }
    if ($mode -ne 'tam') { return }

    # gercek tur: uygula -> calisan oturumu oku -> geri al -> oturum eski haline donmeli
    $snap0 = Get-LiveSnap $c
    Save-LiveInflight 'VisualFx' $snap0
    $injected = $false
    if ((Get-TweakPending $c) -eq 0) {
        # ayar zaten uygulanmis: uygulamanin gercek etkisini gorebilmek icin once gecici olarak Windows varsayilanina cekilir
        Set-LiveVisualDefaults
        [void](Invoke-LiveRefresh @(@{ T = 'Reg'; Path = 'HKCU\Control Panel\Desktop'; Name = 'UserPreferencesMask' }))
        Wait-LiveSession
        $injected = $true
        Add-LiveRow 'etki' 'gorsel-hazirlik' 'BILGI' ('ayar zaten uygulanmıştı; etkisini ölçmek için geçici olarak Windows varsayılanına çekildi: ' + (Format-LiveSpiSet (Get-LiveSpiSet)))
    }
    $before = Get-LiveSpiSet
    $snapB = Get-LiveSnap $c
    $t0 = Get-Date
    try {
        $r1 = Invoke-LiveJob 'Job_Plan' @{ Steps = $steps; Preview = $false; RestorePoint = $false }
        if ($r1.Err -ne '') { Add-LiveRow 'etki' 'gorsel-uygula' 'HATA' ('uygulama çöktü: ' + $r1.Err) }
        Wait-LiveSession
        $after = Get-LiveSpiSet
        $declared = $null
        foreach ($op in @($c.Ops)) { if ([string]$op.Name -eq 'UserPreferencesMask') { $declared = [byte[]]@($op.Value) } }
        $bad = New-Object System.Collections.ArrayList
        if ($null -ne $declared) {
            foreach ($b in $script:LiveMaskBits) {
                $want = [bool](Get-MaskBit $declared $b)
                $have = ([int]$after[[string]$b] -ne 0)
                if ($want -ne $have) { [void]$bad.Add('bit ' + $b + ' (olması gereken ' + $want + ', oturumda ' + $have + ')') }
            }
        }
        if ([int]$after['drag'] -ne 0) { [void]$bad.Add('pencereyi sürüklerken içerik gösterme kapanmadı') }
        if ([int]$after['menudelay'] -ne 200) { [void]$bad.Add('menü gecikmesi ' + $after['menudelay'] + ' (olması gereken 200)') }
        if ($bad.Count -gt 0) { Add-LiveRow 'etki' 'gorsel-uygula' 'HATA' ('ayar kaydedildi ama çalışan oturuma yansımadı (kullanıcının şikâyeti): ' + ($bad -join '; ')) }
        else { Add-LiveRow 'etki' 'gorsel-uygula' 'OK' ('çalışan oturum anında değişti: ' + (Format-LiveSpiSet $after)) }
        $jf = Get-LiveJournalAfter $t0
        if ($jf -eq '') { Add-LiveRow 'etki' 'gorsel-geri' 'HATA' ('geri alma günlüğü yazılmadı (uygulama ' + $(if ($r1.Err -eq '') { [string]$r1.Out.Changes } else { '?' }) + ' değişiklik yaptı)') }
        else {
            $r2 = Invoke-LiveJob 'Job_Undo' @{ File = $jf }
            if ($r2.Err -ne '') { Add-LiveRow 'etki' 'gorsel-geri' 'HATA' ('geri alma çöktü: ' + $r2.Err) }
        }
        Wait-LiveSession
        $back = Get-LiveSpiSet
        $bad2 = New-Object System.Collections.ArrayList
        foreach ($k in @($before.Keys)) { if ([int]$before[$k] -ne [int]$back[$k]) { [void]$bad2.Add($k + ' (önce ' + $before[$k] + ', sonra ' + $back[$k] + ')') } }
        $d2 = Compare-LiveSnap $snapB (Get-LiveSnap $c)
        if ($bad2.Count -gt 0 -or $d2.Count -gt 0) {
            Add-LiveRow 'etki' 'gorsel-geri' 'HATA' ('geri alınınca eski hâle dönmedi: oturum [' + ($bad2 -join '; ') + '] kayıt [' + ($d2 -join '; ') + ']')
        } elseif ($jf -ne '') { Add-LiveRow 'etki' 'gorsel-geri' 'OK' 'geri alınınca çalışan oturum ve kayıt defteri eski haline döndü' }
        # son durum: denetimden onceki hal (hazirlik yapildiysa ayarin uygulanmis hali) geri yazilir ve oturuma uygulanir
        if ($injected -or $bad2.Count -gt 0 -or $d2.Count -gt 0) {
            Restore-LiveSnap (ConvertTo-LiveSerial $snap0)
            try { [void](Invoke-LiveRefresh @(@{ T = 'Reg'; Path = 'HKCU\Control Panel\Desktop'; Name = 'UserPreferencesMask' })) } catch { }
            Wait-LiveSession
            $dz = Compare-LiveSnap $snap0 (Get-LiveSnap $c)
            if ($dz.Count -gt 0) { Add-LiveRow 'etki' 'gorsel-son' 'HATA' ('denetim öncesi hale dönülemedi: ' + ($dz -join '; ')) }
            else { Add-LiveRow 'etki' 'gorsel-son' 'OK' 'denetim öncesi hale dönüldü' }
        }
        Clear-LiveInflight
    } catch {
        try { Restore-LiveSnap (ConvertTo-LiveSerial $snap0); [void](Invoke-LiveRefresh @(@{ T = 'Reg'; Path = 'HKCU\Control Panel\Desktop'; Name = 'UserPreferencesMask' })); Clear-LiveInflight } catch { }
        Add-LiveRow 'etki' 'gorsel' 'HATA' ('deneme çöktü: ' + $_.Exception.Message)
    }
}

# ---------------- guc kipi ve guc plani ----------------
function Test-LivePower {
    $mode = Get-LiveMode
    if (-not (Initialize-SysNative)) { Add-LiveRow 'etki' 'guc' 'HATA' 'yerel işlevler yüklenemedi'; return }
    $modern = Test-PwModernStandby
    $cur = Get-PwModeInfo
    $act = $null
    try { $act = Get-PwActive } catch { }
    Add-LiveRow 'etki' 'guc-durum' 'BILGI' ('Modern Bekleme=' + $modern + '; güç kipi=' + $(if ($cur.Ok) { [string]$cur.Name } else { 'okunamadı' }) + '; etkin plan=' + $(if ($null -ne $act) { [string]$act.Name } else { '?' }))
    $keys = @('High', 'Saver', 'Balanced')
    if ($mode -ne 'tam') {
        foreach ($k in $keys) {
            $r = Invoke-LiveJob 'Job_Plan' @{ Steps = (New-PowerSetSteps $k); Preview = $true; RestorePoint = $false }
            if ($r.Err -ne '') { Add-LiveRow 'etki' ('guc-onizleme-' + $k) 'HATA' ('önizleme çöktü: ' + $r.Err) }
            else { Add-LiveRow 'etki' ('guc-onizleme-' + $k) 'OK' ([string]$r.Out.Changes + ' değişiklik, ' + [string]$r.Out.Skipped + ' atlanan önizlendi') }
        }
        $now = Get-PwModeInfo
        if ($cur.Ok -and $now.Ok -and [string]$cur.Guid -ne [string]$now.Guid) { Add-LiveRow 'etki' 'guc-onizleme' 'HATA' 'önizleme güç kipini değiştirdi' }
        return
    }
    # gercek tur: her plan icin uygula -> sistemden oku -> geri al -> eski haline donmus mu
    $snapP = Get-LiveFuncSnap 'PowerPlan'
    $snapM = Get-LiveFuncSnap 'PowerMode'
    Save-LiveInflight 'PowerPlan' @($snapP, $snapM)
    try {
        foreach ($k in $keys) {
            $t0 = Get-Date
            $mk = Get-LiveLogMark
            $r1 = Invoke-LiveJob 'Job_Plan' @{ Steps = (New-PowerSetSteps $k); Preview = $false; RestorePoint = $false }
            $lines = Get-LiveLogSince $mk
            if ($r1.Err -ne '') { Add-LiveRow 'etki' ('guc-' + $k) 'HATA' ('uygulama çöktü: ' + $r1.Err); continue }
            $errs = Select-LiveLines $lines 'ERR'
            $nowMode = Get-PwModeInfo
            $nowAct = $null; try { $nowAct = Get-PwActive } catch { }
            $okNow = $false; $seen = ''
            if ($modern -and (Get-PwModeKeyFor $k) -ne '') {
                $okNow = ($nowMode.Ok -and [string]$nowMode.Key -eq (Get-PwModeKeyFor $k))
                $seen = 'kip=' + $(if ($nowMode.Ok) { [string]$nowMode.Name } else { 'okunamadı' })
            } else {
                $okNow = ($null -ne $nowAct -and [string]$nowAct.Guid -eq [string]$script:PwKnown[$k].Guid)
                $seen = 'plan=' + $(if ($null -ne $nowAct) { [string]$nowAct.Name } else { '?' })
            }
            if (-not $okNow) {
                $why = ''
                if ($errs.Count -gt 0) { $why = ' | ' + (Get-LiveShort (($errs | ForEach-Object { ($_ -replace '^\d\d:\d\d:\d\d\s+ERR\s+', '') }) -join ' | ') 220) }
                # uretici guc yazilimi ya da kurum ilkesi kipi kilitleyebilir: uygulama bunu acikca soylemeli, sessiz kalmamali
                $explains = ($errs.Count -gt 0 -and (($errs -join ' ') -match 'kilitl|doğrulanamadı|değiştirmedi'))
                if ($explains) { Add-LiveRow 'etki' ('guc-' + $k) 'UYARI' ('Windows kipi değiştirmedi, uygulama nedenini söylüyor; ' + $seen + $why) }
                else { Add-LiveRow 'etki' ('guc-' + $k) 'HATA' ('güç planı uygulandı denildi ama sistem değişmedi (' + $seen + ')' + $why) }
            } else { Add-LiveRow 'etki' ('guc-' + $k) 'OK' ('sistem gerçekten ' + $seen + ' oldu') }
            $jf = Get-LiveJournalAfter $t0
            if ($jf -ne '') {
                $r2 = Invoke-LiveJob 'Job_Undo' @{ File = $jf }
                if ($r2.Err -ne '') { Add-LiveRow 'etki' ('guc-geri-' + $k) 'HATA' ('geri alma çöktü: ' + $r2.Err) }
            }
        }
        $dP = Compare-LiveItem $snapP (Get-LiveFuncSnap 'PowerPlan')
        $dM = Compare-LiveItem $snapM (Get-LiveFuncSnap 'PowerMode')
        if ($dP -ne '' -or $dM -ne '') {
            Add-LiveRow 'etki' 'guc-geri' 'HATA' ('geri alınınca güç ayarı eski haline dönmedi: ' + $dP + ' ' + $dM)
            Restore-LiveFunc $snapP; Restore-LiveFunc $snapM
        } else { Add-LiveRow 'etki' 'guc-geri' 'OK' 'güç kipi ve etkin plan eski haline döndü' }
        Clear-LiveInflight
    } catch {
        try { Restore-LiveFunc $snapP; Restore-LiveFunc $snapM; Clear-LiveInflight } catch { }
        Add-LiveRow 'etki' 'guc' 'HATA' ('deneme çöktü: ' + $_.Exception.Message)
    }
}

# ---------------- "Windows geri aldi" yolu: sapma tespiti ve Duzelt dugmesi ----------------
function Test-LiveDrift {
    $mode = Get-LiveMode
    $d0 = Get-DriftedIds
    Add-LiveRow 'sapma' 'durum' 'BILGI' ('deneme veri klasöründe geri dönmüş görünen ayar: ' + $d0.Count + $(if ($d0.Count -gt 0) { ' [' + ($d0 -join ', ') + ']' } else { '' }))
    $id = 'Transparency'
    $c = Get-CatalogItem $id
    if ($null -eq $c) { Add-LiveRow 'sapma' $id 'ATLA' 'deneme ayarı katalogda yok'; return }
    if ($mode -ne 'tam') { Add-LiveRow 'sapma' 'duzelt' 'ATLA' '“Düzelt” akışı gerçek ayar yazar; yalnızca tam kipte (yönetici) denenir'; return }
    $snap0 = Get-LiveSnap $c
    $set0 = Get-AppliedIds
    Save-LiveInflight $id $snap0
    try {
        # 1) ayari uygula; "uygulananlar" listesine girmeli
        $r1 = Invoke-LiveJob 'Job_Plan' @{ Steps = (New-StepsFromIds @($id)); Preview = $false; RestorePoint = $false }
        if ($r1.Err -ne '') { Add-LiveRow 'sapma' 'uygula' 'HATA' ('uygulama çöktü: ' + $r1.Err); return }
        if ((Get-TweakPending $c) -ne 0) { Add-LiveRow 'sapma' 'uygula' 'HATA' 'ayar uygulanamadı, sapma denemesi yapılamıyor'; return }
        $apNow = Get-AppliedIds
        if ($apNow -notcontains $id) { Add-LiveRow 'sapma' 'kayit' 'HATA' 'ayar uygulandı ama uygulananlar listesine girmedi'; return }
        Add-LiveRow 'sapma' 'kayit' 'OK' 'uygulanan ayar “uygulananlar” listesine girdi'
        # 2) Windows geri aliyor: deger disaridan eski haline cevrilir
        $op = @($c.Ops)[0]
        $orig = $snap0[0].Raw
        # ayar denetimden once zaten uygulanmissa eski deger hedefle aynidir; Windows'un geri almasi hedeften farkli bir degerle taklit edilir
        $target = [int64]$op.Value
        $driftV = [int64]1
        if ($target -ne 0) { $driftV = [int64]0 }
        if ($orig.Exists -and [string]$orig.Kind -eq 'DWord' -and [int64]$orig.Data -ne $target) { $driftV = [int64]$orig.Data }
        Set-RegData ([string]$op.Path) ([string]$op.Name) 'DWord' $driftV
        $drNow = Get-DriftedIds
        if ($drNow -notcontains $id) { Add-LiveRow 'sapma' 'tespit' 'HATA' 'değer dışarıdan eski haline çevrildi ama “Windows geri aldı” tespiti ayarı bulamadı'; return }
        Add-LiveRow 'sapma' 'tespit' 'OK' 'dışarıdan geri alınan ayar “geri dönmüş” olarak bulundu'
        # 3) saglik bulgusu ve "Duzelt" eylemi
        $fix = $null
        try {
            $script:Findings = New-Object System.Collections.ArrayList
            Chk_Drift
            $h = @($script:Findings | Where-Object { [string]$_.Id -eq 'drift' })
            if ($h.Count -ge 1) { $fix = $h[0].Fix }
        } catch { Add-LiveRow 'sapma' 'bulgu' 'HATA' ('Chk_Drift çöktü: ' + $_.Exception.Message) }
        if ($null -eq $fix) { Add-LiveRow 'sapma' 'bulgu' 'HATA' 'geri dönen ayar için sağlık bulgusu ya da “Düzelt” eylemi üretilmedi'; return }
        Add-LiveRow 'sapma' 'bulgu' 'OK' ('bulgu ve eylem var: “' + [string]$fix.Label + '” (' + [string]$fix.Kind + ')')
        # 4) Duzelt'e basmak = Job_FixAll
        $fx = Invoke-LiveJob 'Job_FixAll' @{ Fixes = @($fix); Preview = $false; RestorePoint = $false }
        if ($fx.Err -ne '') { Add-LiveRow 'sapma' 'duzelt' 'HATA' ('düzeltme çöktü: ' + $fx.Err); return }
        $pend = Get-TweakPending $c
        $still = Get-DriftedIds
        if ($pend -ne 0 -or $still -contains $id) { Add-LiveRow 'sapma' 'duzelt' 'HATA' ('“Düzelt” ayarı düzeltmedi (kullanıcının şikâyeti): ölçüm=' + $pend + ' değişiklik=' + [string]$fx.Out.Changes + ' hata=' + [string]$fx.Out.Errors) }
        else { Add-LiveRow 'sapma' 'duzelt' 'OK' ('geri dönen ayar yeniden uygulandı ve doğrulandı (değişiklik=' + [string]$fx.Out.Changes + ')') }
    } catch {
        Add-LiveRow 'sapma' $id 'HATA' ('deneme çöktü: ' + $_.Exception.Message)
    } finally {
        try {
            Restore-LiveSnap (ConvertTo-LiveSerial $snap0)
            Save-AppliedIds $set0
            Clear-LiveInflight
        } catch { }
    }
}

# ---------------- araclar ----------------
function Get-LiveSandbox([string]$Name) {
    $d = Join-Path (Join-Path ([System.IO.Path]::GetTempPath()) 'Multimizer-duman-kum') $Name
    try { if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue } } catch { }
    [void](New-Item -ItemType Directory -Path $d -Force)
    return $d
}

function Test-LivePassword {
    $x = Import-MmExt 'Parola'
    if ($x.Ok -ne $true) { Add-LiveRow 'arac' 'parola' 'HATA' ('parola eklentisi yüklenemedi: ' + [string]$x.Error); return }
    $bad = New-Object System.Collections.ArrayList
    $combos = @(@($false, $false, $false), @($true, $false, $false), @($true, $true, $false), @($true, $true, $true), @($false, $false, $true))
    foreach ($cb in $combos) {
        $sets = Get-PasswordSets $cb[0] $cb[1] $cb[2]
        $pool = ($sets -join '')
        foreach ($len in @(8, 12, 20, 33, 64)) {
            for ($n = 0; $n -lt 40; $n++) {
                $pw = New-RandomPassword $len $sets
                if ($pw.Length -ne $len) { [void]$bad.Add('uzunluk ' + $pw.Length + ' (istenen ' + $len + ')'); continue }
                foreach ($ch in $pw.ToCharArray()) { if ($pool.IndexOf($ch) -lt 0) { [void]$bad.Add('havuz dışı karakter: ' + $ch); break } }
                foreach ($s in $sets) { $hit = $false; foreach ($ch in $pw.ToCharArray()) { if ($s.IndexOf($ch) -ge 0) { $hit = $true; break } }; if (-not $hit) { [void]$bad.Add('küme eksik (' + $s.Substring(0, 3) + '...)'); break } }
            }
        }
    }
    # tekrar ve dagilim
    $sets = Get-PasswordSets $true $true $true
    # PowerShell sozlukleri buyuk/kucuk harfi ayirmaz; karakter sayimi icin sirali (ordinal) karsilastirici gerekir
    $seen = New-Object System.Collections.Hashtable ([System.StringComparer]::Ordinal); $dup = 0
    $freq = New-Object System.Collections.Hashtable ([System.StringComparer]::Ordinal)
    $pool = ($sets -join '')
    foreach ($ch in $pool.ToCharArray()) { $freq[[string]$ch] = 0 }
    $total = 0
    for ($n = 0; $n -lt 400; $n++) {
        $pw = New-RandomPassword 24 $sets
        if ($seen.ContainsKey($pw)) { $dup++ } else { $seen[$pw] = $true }
        foreach ($ch in $pw.ToCharArray()) { $freq[[string]$ch] = [int]$freq[[string]$ch] + 1; $total++ }
    }
    if ($dup -gt 0) { [void]$bad.Add($dup + ' tekrar eden parola') }
    $exp = $total / [double]$pool.Length
    $worst = 0.0
    foreach ($k in @($freq.Keys)) { $dev = [math]::Abs([double]$freq[$k] - $exp) / $exp; if ($dev -gt $worst) { $worst = $dev } }
    if ($worst -gt 0.6) { [void]$bad.Add('karakter dağılımı dengesiz (en büyük sapma %' + [int]($worst * 100) + ')') }
    # uzunluk sinirlari
    if ((New-RandomPassword 3 (Get-PasswordSets $true $true $true)).Length -ne 8) { [void]$bad.Add('çok kısa istek 8 karaktere yükseltilmedi') }
    if ((New-RandomPassword 500 (Get-PasswordSets $true $true $true)).Length -ne 64) { [void]$bad.Add('çok uzun istek 64 karaktere indirilmedi') }
    $bits = Get-PasswordBits 20 $true $true $true
    if ($bits -lt 100 -or $bits -gt 140) { [void]$bad.Add('entropi hesabı beklenmedik: ' + $bits) }
    if ($bad.Count -gt 0) { Add-LiveRow 'arac' 'parola' 'HATA' ((@($bad | Select-Object -First 6)) -join '; ') }
    else { Add-LiveRow 'arac' 'parola' 'OK' ('5 küme birleşimi × 5 uzunluk × 40 parola doğru; 400 parolada tekrar yok, karakter dağılımı dengeli (en büyük sapma %' + [int]($worst * 100) + '); 20 karakter ≈ ' + $bits + ' bit') }
}

function Test-LiveRename {
    $dir = Get-LiveSandbox 'adlandir'
    $names = @('IMG_0001.jpg', 'IMG_0002.jpg', 'Tatil Raporu.docx', 'ÇOK  boşluk__ve_çizgi.txt', 'UPPER.TXT', 'a.txt', 'b.txt', 'noext')
    foreach ($n in $names) { [System.IO.File]::WriteAllText((Join-Path $dir $n), $n, [System.Text.Encoding]::UTF8) }
    (Get-Item -LiteralPath (Join-Path $dir 'a.txt')).LastWriteTime = [datetime]'2024-03-05 10:00'
    $bad = New-Object System.Collections.ArrayList
    $why = Test-RenameDirAllowed $dir
    if ($why -ne '') { Add-LiveRow 'arac' 'adlandir' 'HATA' ('geçici klasör reddedildi: ' + $why); return }
    $scan = Invoke-LiveJob 'Job_RenameScan' @{ Dir = $dir }
    if ($scan.Err -ne '' -or $scan.Out.Ok -ne $true) { Add-LiveRow 'arac' 'adlandir' 'HATA' ('klasör taraması başarısız: ' + $scan.Err + ' ' + [string]$scan.Out.Error); return }
    $items = @($scan.Out.Items)
    if ($items.Count -ne $names.Count) { [void]$bad.Add('tarama ' + $items.Count + ' dosya buldu, ' + $names.Count + ' bekleniyordu') }
    $existing = @(Get-ChildItem -LiteralPath $dir -File | ForEach-Object { $_.Name })
    # kuralli onizlemeler
    $p1 = Get-RenamePlan $items 'Number' 'Tatil' $existing
    if ($p1.Changes -ne $names.Count -or $p1.Problems -ne 0) { [void]$bad.Add('numaralandırma: ' + $p1.Changes + ' değişiklik, ' + $p1.Problems + ' sorun') }
    $p2 = Get-RenamePlan $items 'Replace' 'IMG_=>Foto ' $existing
    $row = @($p2.Rows | Where-Object { $_.Old -eq 'IMG_0001.jpg' })
    if ($row.Count -ne 1 -or $row[0].New -ne 'Foto 0001.jpg') { [void]$bad.Add('değiştir: ' + $(if ($row.Count -eq 1) { $row[0].New } else { 'satır yok' })) }
    $p3 = Get-RenamePlan $items 'Lower' '' $existing
    $row = @($p3.Rows | Where-Object { $_.Old -eq 'UPPER.TXT' })
    if ($row.Count -ne 1 -or $row[0].New -ne 'upper.txt') { [void]$bad.Add('küçük harf: ' + $(if ($row.Count -eq 1) { $row[0].New } else { 'satır yok' })) }
    $p4 = Get-RenamePlan $items 'Dash' '' $existing
    $row = @($p4.Rows | Where-Object { $_.Old -eq 'Tatil Raporu.docx' })
    if ($row.Count -ne 1 -or $row[0].New -ne 'Tatil-Raporu.docx') { [void]$bad.Add('tire: ' + $(if ($row.Count -eq 1) { $row[0].New } else { 'satır yok' })) }
    $p5 = Get-RenamePlan $items 'DatePrefix' '' $existing
    $row = @($p5.Rows | Where-Object { $_.Old -eq 'a.txt' })
    if ($row.Count -ne 1 -or $row[0].New -ne '2024-03-05 a.txt') { [void]$bad.Add('tarih öneki: ' + $(if ($row.Count -eq 1) { $row[0].New } else { 'satır yok' })) }
    # cakisma: a.txt ve b.txt ayni adi alirsa sorun isaretlenmeli
    $p6 = Get-RenamePlan @(@{ Name = 'a.txt'; Time = (Get-Date) }, @{ Name = 'b.txt'; Time = (Get-Date) }) 'Replace' 'a=>x' @('a.txt', 'b.txt', 'x.txt')
    if ($p6.Problems -lt 1) { [void]$bad.Add('klasörde var olan adla çakışma sorun sayılmadı') }
    # gercek uygulama + geri alma (gecici klasorde, motorun kendi yolu)
    $before = (@(Get-ChildItem -LiteralPath $dir -File | ForEach-Object { $_.Name } | Sort-Object)) -join '|'
    $pairs = @($p1.Rows | ForEach-Object { @{ Old = [string]$_.Old; New = [string]$_.New } })
    $t0 = Get-Date
    $r1 = Invoke-LiveJob 'Job_Plan' @{ Steps = @(@{ Id = 'LiveRename'; Title = 'adlandırma denemesi'; Ops = @(@{ T = 'Rename'; Dir = $dir; Pairs = $pairs }); Reboot = $false }); Preview = $false; RestorePoint = $false }
    if ($r1.Err -ne '' -or [int]$r1.Out.Errors -gt 0) { [void]$bad.Add('uygulama hata verdi: ' + $r1.Err) }
    $mid = @(Get-ChildItem -LiteralPath $dir -File | ForEach-Object { $_.Name })
    foreach ($row in $p1.Rows) { if ($mid -cnotcontains [string]$row.New) { [void]$bad.Add('yeni ad diskte yok: ' + $row.New) } ; if ($mid -ccontains [string]$row.Old -and [string]$row.Old -cne [string]$row.New) { [void]$bad.Add('eski ad hâlâ duruyor: ' + $row.Old) } }
    # icerik kaybolmadi mi
    foreach ($row in $p1.Rows) { $f = Join-Path $dir ([string]$row.New); if (Test-Path -LiteralPath $f) { $txt = [System.IO.File]::ReadAllText($f, [System.Text.Encoding]::UTF8); if ($txt -cne [string]$row.Old) { [void]$bad.Add('içerik değişti: ' + $row.New) } } }
    $jf = Get-LiveJournalAfter $t0
    if ($jf -eq '') { [void]$bad.Add('geri alma günlüğü yazılmadı') }
    else {
        $r2 = Invoke-LiveJob 'Job_Undo' @{ File = $jf }
        if ($r2.Err -ne '' -or [int]$r2.Out.Errors -gt 0) { [void]$bad.Add('geri alma hata verdi: ' + $r2.Err) }
        $after = (@(Get-ChildItem -LiteralPath $dir -File | ForEach-Object { $_.Name } | Sort-Object)) -join '|'
        if ($after -cne $before) { [void]$bad.Add('geri alma eski adları döndürmedi') }
    }
    # ters yonlu takas (a<->b): iki asamali yeniden adlandirma cakismamali
    $swap = @(@{ Old = 'a.txt'; New = 'b.txt' }, @{ Old = 'b.txt'; New = 'a.txt' })
    $done = @(Invoke-RenamePairs $dir $swap)
    if ($done.Count -ne 2) { [void]$bad.Add('takas ' + $done.Count + ' dosyada yapıldı') }
    else {
        $ta = [System.IO.File]::ReadAllText((Join-Path $dir 'a.txt')); $tb = [System.IO.File]::ReadAllText((Join-Path $dir 'b.txt'))
        if ($ta -cne 'b.txt' -or $tb -cne 'a.txt') { [void]$bad.Add('takas içerikleri yer değiştirmedi') }
    }
    # sistem klasoru reddedilir mi
    if ([string]$env:WINDIR -ne '' -and (Test-RenameDirAllowed $env:WINDIR) -eq '') { [void]$bad.Add('Windows klasöründe adlandırmaya izin verildi') }
    if ([string]$env:SystemDrive -ne '' -and (Test-RenameDirAllowed ($env:SystemDrive + '\')) -eq '') { [void]$bad.Add('sürücü kökünde adlandırmaya izin verildi') }
    try { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue } catch { }
    if ($bad.Count -gt 0) { Add-LiveRow 'arac' 'adlandir' 'HATA' ((@($bad | Select-Object -First 6)) -join '; ') }
    else { Add-LiveRow 'arac' 'adlandir' 'OK' 'tarama, 5 kural, çakışma denetimi, uygulama, geri alma, takas ve sistem klasörü reddi doğru'  }
}

function Test-LiveCrypt {
    $x = Import-MmExt 'Sifreleme'
    if ($x.Ok -ne $true) { Add-LiveRow 'arac' 'sifreleme' 'HATA' ('şifreleme eklentisi yüklenemedi: ' + [string]$x.Error); return }
    $dir = Get-LiveSandbox 'sifre'
    $bad = New-Object System.Collections.ArrayList
    $src = Join-Path $dir 'gizli belge.txt'
    $rnd = New-Object byte[] 3000017
    (New-Object System.Random 7).NextBytes($rnd)
    [System.IO.File]::WriteAllBytes($src, $rnd)
    $hash0 = (Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash
    $pw = 'Deneme-Parolasi-2026!'
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $e = Invoke-LiveJob 'Job_Crypt' @{ Mode = 'Enc'; Paths = @($src); Password = $pw }
    $encMs = $sw.ElapsedMilliseconds
    if ($e.Err -ne '' -or $e.Out.Ok -ne $true) { [void]$bad.Add('şifreleme başarısız: ' + $e.Err); }
    else {
        $enc = [string]@($e.Out.Outputs)[0]
        if (-not (Test-Path -LiteralPath $enc)) { [void]$bad.Add('şifreli dosya yok') }
        else {
            $encHash = (Get-FileHash -LiteralPath $enc -Algorithm SHA256).Hash
            if ($encHash -eq $hash0) { [void]$bad.Add('şifreli dosya açık dosyayla aynı') }
            $bytes = [System.IO.File]::ReadAllBytes($enc)
            if ($bytes.Length -lt $rnd.Length) { [void]$bad.Add('şifreli dosya beklenenden küçük') }
            # dogru parola
            Remove-Item -LiteralPath $src -Force
            $sw.Restart()
            $d = Invoke-LiveJob 'Job_Crypt' @{ Mode = 'Dec'; Paths = @($enc); Password = $pw }
            $decMs = $sw.ElapsedMilliseconds
            if ($d.Err -ne '' -or $d.Out.Ok -ne $true) { [void]$bad.Add('doğru parolayla çözülemedi: ' + $d.Err) }
            else {
                $dec = [string]@($d.Out.Outputs)[0]
                if ((Get-FileHash -LiteralPath $dec -Algorithm SHA256).Hash -ne $hash0) { [void]$bad.Add('çözülen dosya özgün dosyayla aynı değil') }
            }
            # yanlis parola (uygulama bu reddi gunluge ERR olarak yazar: beklenen satir)
            Add-SmokeExpect ': Parola yanlış ya da dosya değiştirilmiş' 1 'yanlış parola reddi günlüğe yazılmadı'
            $w = Invoke-LiveJob 'Job_Crypt' @{ Mode = 'Dec'; Paths = @($enc); Password = 'Yanlis-Parola-1234' }
            if ($w.Err -eq '' -and $w.Out.Ok -eq $true) { [void]$bad.Add('yanlış parolayla çözüldü') }
            # bozulmus dosya
            Add-SmokeExpect 'bozuk\.mmz: Parola yanlış ya da dosya değiştirilmiş' 1 'bozulmuş dosya reddi günlüğe yazılmadı'
            $bytes[$bytes.Length - 40] = [byte](($bytes[$bytes.Length - 40] + 1) -band 255)
            $tam = Join-Path $dir 'bozuk.mmz'
            [System.IO.File]::WriteAllBytes($tam, $bytes)
            $t = Invoke-LiveJob 'Job_Crypt' @{ Mode = 'Dec'; Paths = @($tam); Password = $pw }
            if ($t.Err -eq '' -and $t.Out.Ok -eq $true) { [void]$bad.Add('bozulmuş dosya fark edilmedi') }
            # kisa parola reddedilir
            Add-SmokeExpect 'Parola en az 8 karakter olmalı' 1 'kısa parola reddi günlüğe yazılmadı'
            $s = Invoke-LiveJob 'Job_Crypt' @{ Mode = 'Enc'; Paths = @($dec); Password = 'kisa' }
            if ($s.Err -eq '' -and $s.Out.Ok -eq $true) { [void]$bad.Add('8 karakterden kısa parola kabul edildi') }
            if ($encMs -gt 20000 -or $decMs -gt 20000) { [void]$bad.Add('3 MB için ' + (Format-LiveMs $encMs) + ' / ' + (Format-LiveMs $decMs) + ' sürdü (çok yavaş)') }
        }
    }
    try { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue } catch { }
    if ($bad.Count -gt 0) { Add-LiveRow 'arac' 'sifreleme' 'HATA' ((@($bad | Select-Object -First 6)) -join '; ') }
    else { Add-LiveRow 'arac' 'sifreleme' 'OK' ('3 MB şifrelendi (' + (Format-LiveMs $encMs) + '), doğru parolayla aynen çözüldü (' + (Format-LiveMs $decMs) + '); yanlış parola, bozulmuş dosya ve kısa parola reddedildi') }
}

function Test-LiveSecureDelete {
    $x = Import-MmExt 'GuvenliSilme'
    if ($x.Ok -ne $true) { Add-LiveRow 'arac' 'guvenli-silme' 'HATA' ('güvenli silme eklentisi yüklenemedi: ' + [string]$x.Error); return }
    $dir = Get-LiveSandbox 'silme'
    $bad = New-Object System.Collections.ArrayList
    $f1 = Join-Path $dir 'bir.bin'; $f2 = Join-Path $dir 'salt okunur.txt'; $sub = Join-Path $dir 'alt klasor'
    [void](New-Item -ItemType Directory -Path $sub -Force)
    $f3 = Join-Path $sub 'ic.dat'
    [System.IO.File]::WriteAllBytes($f1, (New-Object byte[] 100000))
    [System.IO.File]::WriteAllText($f2, 'salt okunur')
    (Get-Item -LiteralPath $f2).IsReadOnly = $true
    [System.IO.File]::WriteAllText($f3, 'iç dosya')
    # alternatif veri akisi
    try { Set-Content -LiteralPath $f1 -Stream 'gizli' -Value 'ads içerik' -ErrorAction Stop } catch { }
    $r = Invoke-LiveJob 'Job_SecureDelete' @{ Paths = @($f1, $f2, $sub); Passes = 1 }
    if ($r.Err -ne '') { [void]$bad.Add('silme çöktü: ' + $r.Err) }
    else {
        if ($r.Out.Files -lt 3) { [void]$bad.Add('yalnızca ' + $r.Out.Files + ' dosya silindi (3 bekleniyordu)') }
        if ($r.Out.Failed -gt 0) { [void]$bad.Add($r.Out.Failed + ' dosya silinemedi') }
    }
    foreach ($p in @($f1, $f2, $f3, $sub)) { if (Test-Path -LiteralPath $p) { [void]$bad.Add('hâlâ duruyor: ' + (Split-Path -Leaf $p)) } }
    # korumali yollar reddedilmeli. Silme isine ASLA verilmez: yalnizca silme yapmayan koruma sorgusu cagrilir
    $guard = New-Object System.Collections.ArrayList
    foreach ($v in @($env:WINDIR, $env:ProgramFiles, $env:ProgramData, $env:USERPROFILE, $(if ([string]$env:SystemDrive -ne '') { $env:SystemDrive + '\' } else { '' }), $(if ([string]$env:WINDIR -ne '') { Join-Path $env:WINDIR 'System32' } else { '' }))) {
        if ([string]$v -eq '') { continue }
        [void]$guard.Add([string]$v)
        if ((Test-SecureDeleteAllowed ([string]$v)) -eq '') { [void]$bad.Add('korumasız yol: ' + [string]$v) }
    }
    try { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue } catch { }
    if ($bad.Count -gt 0) { Add-LiveRow 'arac' 'guvenli-silme' 'HATA' ((@($bad | Select-Object -First 6)) -join '; ') }
    else { Add-LiveRow 'arac' 'guvenli-silme' 'OK' ('dosya, salt okunur dosya, alt akışlı dosya ve klasör silindi; ' + [string]$guard.Count + ' korumalı yol (Windows, Program Files, sürücü kökü...) reddedildi') }
}

function Test-LiveMemory {
    $x = Import-MmExt 'Bellek'
    if ($x.Ok -ne $true) { Add-LiveRow 'arac' 'bellek' 'HATA' ('bellek eklentisi yüklenemedi: ' + [string]$x.Error); return }
    $r = Invoke-LiveJob 'Job_MemTrim' @{ Standby = $false }
    if ($r.Err -ne '') { Add-LiveRow 'arac' 'bellek' 'HATA' ('bellek boşaltma çöktü: ' + $r.Err); return }
    if ($r.Out.Ok -ne $true) { Add-LiveRow 'arac' 'bellek' 'HATA' 'bellek boşaltma başarısız döndü'; return }
    $m = 'işlem=' + [string]$r.Out.Count + '; boş bellek ' + [int]$r.Out.Before + ' → ' + [int]$r.Out.After + ' MB'
    if ([int]$r.Out.Count -lt 5) { Add-LiveRow 'arac' 'bellek' 'UYARI' ('çalışma kümesi boşaltılan işlem sayısı çok az: ' + $m) }
    else { Add-LiveRow 'arac' 'bellek' 'OK' $m }
}

function Test-LiveTools {
    Test-LivePassword
    Test-LiveRename
    Test-LiveCrypt
    Test-LiveSecureDelete
    Test-LiveMemory
}

# ---------------- okuma amacli arka plan isleri: gercek bilgisayarda calisiyor mu ----------------
function Get-LiveResultSummary($Out) {
    if ($null -eq $Out) { return 'sonuç boş' }
    if ($Out -is [hashtable]) {
        $parts = New-Object System.Collections.ArrayList
        foreach ($k in @($Out.Keys | Sort-Object)) {
            $v = $Out[$k]
            if ($v -is [System.Array] -or $v -is [System.Collections.ArrayList]) { [void]$parts.Add([string]$k + '=' + @($v).Count) }
            elseif ($v -is [hashtable]) { [void]$parts.Add([string]$k + '={' + @($v.Keys).Count + '}') }
            elseif ($v -is [bool]) { [void]$parts.Add([string]$k + '=' + $v) }
            elseif ($v -is [string] -and $v.Length -le 24) { [void]$parts.Add([string]$k + '=' + $v) }
            elseif ($v -is [ValueType]) { [void]$parts.Add([string]$k + '=' + [string]$v) }
        }
        return ((@($parts | Select-Object -First 8)) -join ' ')
    }
    if ($Out -is [System.Array]) { return ('dizi ' + @($Out).Count) }
    return ([string]$Out.GetType().Name)
}

function Get-LiveReadJobs {
    $kum = Get-LiveSandbox 'is'
    [System.IO.File]::WriteAllText((Join-Path $kum 'ornek.txt'), 'ornek')
    [System.IO.File]::WriteAllText((Join-Path $kum 'ornek2.txt'), 'ornek')
    $ownIp = ''
    try { $ownIp = [string](@(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop | Where-Object { $_.IPAddress -match '^(10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.)' } | Select-Object -First 1 -ExpandProperty IPAddress)[0]) } catch { }
    $list = New-Object System.Collections.ArrayList
    $add = { param($fn, $arg, $grp, $slow) [void]$list.Add(@{ Fn = $fn; Arg = $arg; Group = $grp; Slow = [bool]$slow }) }
    # sistem
    foreach ($f in @('Job_PcInfo', 'Job_PowerInfo', 'Job_PowerStates', 'Job_PowerPreview', 'Job_Inventory', 'Job_Procs', 'Job_Services', 'Job_TaskInfo', 'Job_Startup', 'Job_Programs', 'Job_Apps', 'Job_ScoreView', 'Job_PrivacyStatus', 'Job_PrivacyUse', 'Job_Lifespan', 'Job_FocusState', 'Job_PathInfo', 'Job_IntegrityCheck')) { & $add $f @{} 'sistem' $false }
    & $add 'Job_Adaptive' @{ Preview = $true; RestorePoint = $false; Services = $true } 'sistem' $false
    & $add 'Job_SmartZero' @{ Preview = $true; RestorePoint = $false } 'sistem' $false
    & $add 'Job_TweakStateIds' @{ Ids = @('VisualFx', 'Transparency', 'Telemetry') } 'sistem' $false
    # depolama
    foreach ($f in @('Job_CleanScan', 'Job_RecycleList', 'Job_SlvDisks', 'Job_ShadowList', 'Job_BitLockerInfo', 'Job_AltScan')) { & $add $f @{} 'depolama' $false }
    & $add 'Job_DiskUsage' @{ Path = $kum } 'depolama' $false
    & $add 'Job_LargeFiles' @{ Path = $kum; Top = 10; MinMB = 0.000001 } 'depolama' $false
    & $add 'Job_Duplicates' @{ Path = $kum; MinMB = 0.000001 } 'depolama' $false
    & $add 'Job_FileInfo' @{ Path = (Join-Path $kum 'ornek.txt') } 'depolama' $false
    & $add 'Job_CompressEstimate' @{ Path = $kum } 'depolama' $false
    & $add 'Job_CompressScan' @{ MinMB = 250 } 'depolama' $true
    & $add 'Job_FindPhotoRec' @{} 'depolama' $false
    # guncellemeler
    foreach ($f in @('Job_InstalledUpdates', 'Job_WuHistory', 'Job_WingetPinList')) { & $add $f @{} 'guncelleme' $false }
    & $add 'Job_WuSearch' @{} 'guncelleme' $true
    & $add 'Job_WingetCheck' @{} 'guncelleme' $true
    # ag
    foreach ($f in @('Job_VpnStatus', 'Job_KsContext', 'Job_NetTalkers', 'Job_NetProtect', 'Job_FwBlocks', 'Job_ArpCheck', 'Job_Neighbors')) { & $add $f @{} 'ag' $false }
    & $add 'Job_Ping' @{ Host = '127.0.0.1'; Trace = $false } 'ag' $false
    & $add 'Job_Net' @{} 'ag' $true
    & $add 'Job_LanSweep' @{} 'ag' $true
    if ($ownIp -ne '') { & $add 'Job_PortCheck' @{ Host = $ownIp } 'ag' $true }
    & $add 'Job_LeakTest' @{} 'ag' $true
    & $add 'Job_DnsBench' @{} 'ag' $true
    # oyun
    & $add 'Job_GameScan' @{ Custom = @() } 'oyun' $true
    & $add 'Job_ExtToolScan' @{} 'oyun' $false
    & $add 'Job_PrepCheck' @{ NoNet = $true } 'oyun' $false
    # saglik ve raporlar (tam tarama ayrica "bulgu" bolumunde)
    & $add 'Job_Report' @{} 'saglik' $true
    & $add 'Job_SupportBundle' @{ Dest = $kum } 'saglik' $true
    return $list.ToArray()
}

# Sonucu "Ok = $false" donmesi hata sayilmayan isler: bu bilgisayarda o durum normal (ornegin etkin VPN yokken kill-switch baglami bos doner)
$script:LiveOkFalseInfo = @('Job_KsContext')

function Get-LiveWhy($Out) {
    $why = ''
    if ($Out -is [hashtable]) {
        foreach ($k in @('Error', 'Msg', 'Message', 'Reason', 'Why')) { if ($Out.ContainsKey($k) -and [string]$Out[$k] -ne '') { $why = [string]$Out[$k]; break } }
        if ($why -eq '' -and $Out.ContainsKey('Errors') -and [int]$Out.Errors -gt 0) { $why = [string][int]$Out.Errors + ' adım hata verdi' }
        if ($why -eq '' -and $Out.ContainsKey('Summary') -and [string]$Out.Summary -ne '') { $why = [string]$Out.Summary }
    }
    return $why
}

function Test-LiveJobs([string]$Group) {
    $mode = Get-LiveMode
    $all = @(Get-LiveReadJobs | Where-Object { $_.Group -eq $Group })
    foreach ($j in $all) {
        $fn = [string]$j.Fn
        if ($null -eq (Get-Command $fn -ErrorAction SilentlyContinue)) { Add-LiveRow 'is' $fn 'ATLA' 'bu sürümde işlev yok'; continue }
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $mk = Get-LiveLogMark
        $r = Invoke-LiveGuarded $fn $j.Arg
        $blocked = @($script:LiveBlocked.ToArray())
        $lines = Get-LiveLogSince $mk
        $ms = $sw.ElapsedMilliseconds
        $errs = Select-LiveLines $lines 'ERR'
        $errText = ''
        if ($errs.Count -gt 0) { $errText = Get-LiveShort (($errs | ForEach-Object { ($_ -replace '^\d\d:\d\d:\d\d\s+ERR\s+', '') }) -join ' | ') 220 }
        if ($blocked.Count -gt 0) {
            Add-LiveRow 'is' $fn 'HATA' ('okuma işi sistemi değiştirmeye kalkıştı (bekçi engelledi, hiçbir şey yazılmadı): ' + (Get-LiveShort ($blocked -join ' | ') 260)) $ms
            continue
        }
        if ($r.Err -ne '') { Add-LiveRow 'is' $fn 'HATA' ('iş çöktü: ' + (Get-LiveShort $r.Err 220)) $ms; continue }
        $out = $r.Out
        $sum = Get-LiveResultSummary $out
        if ($null -eq $out) { Add-LiveRow 'is' $fn 'UYARI' 'iş sonuç döndürmedi' $ms; continue }
        $okFalse = ($out -is [hashtable] -and $out.ContainsKey('Ok') -and $out.Ok -eq $false)
        if ($okFalse) {
            $why = Get-LiveWhy $out
            if ($errText -ne '') { $why = ($why + ' [günlük: ' + $errText + ']').Trim() }
            if ($script:LiveOkFalseInfo -contains $fn) { Add-LiveRow 'is' $fn 'BILGI' ('bu bilgisayarda boş döndü: ' + (Get-LiveShort $why 200)) $ms; continue }
            Add-LiveRow 'is' $fn 'UYARI' ('iş başarısız döndü: ' + (Get-LiveShort $why 260)) $ms; continue
        }
        if ($errs.Count -gt 0) { Add-LiveRow 'is' $fn 'UYARI' ('iş sonuç verdi ama günlüğe hata yazdı: ' + $errText + ' [' + $sum + ']') $ms; continue }
        $note = ''
        if ($ms -gt 30000 -and -not [bool]$j.Slow) { $note = ' (yavaş: ' + (Format-LiveMs $ms) + ')' }
        Add-LiveRow 'is' $fn 'OK' ($sum + $note) $ms
        try { Invoke-SmokeFlush } catch { }
    }
}

# ---------------- algilayicilar ve izleme: uygulamanin gosterdigi, Windows'un gercek degeriyle ayni mi ----------------
function Test-LiveSensors {
    try { Open-Page 'panel' } catch { }
    # izleme dongusunun ilk turlari beklenir (en cok 25 sn)
    for ($i = 0; $i -lt 100; $i++) {
        try { Invoke-SmokeFlush } catch { }
        $d = $sync.MonDiag
        if ($null -ne $d -and [int]$d.Tick -ge 6) { break }
        Start-Sleep -Milliseconds 250
    }
    $m = $sync.Mon
    if ($null -eq $m -or @($m.Keys).Count -eq 0) { Add-LiveRow 'sensor' 'izleme' 'HATA' 'izleme döngüsü hiç ölçüm üretmedi'; return }
    $age = 999
    try { $age = ([DateTime]::UtcNow - [DateTime]$sync.MonBeat).TotalSeconds } catch { }
    if ($age -gt 15) { Add-LiveRow 'sensor' 'izleme' 'HATA' ('izleme döngüsü ' + [int]$age + ' sn önce durmuş') } else { Add-LiveRow 'sensor' 'izleme' 'OK' ('izleme canlı, son ölçüm ' + [int]$age + ' sn önce; tur=' + [string]$sync.MonDiag.Tick) }
    # bellek: uygulama ile Windows
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $totalGB = [double]$os.TotalVisibleMemorySize / 1MB
        $usedPct = 100.0 * (1.0 - [double]$os.FreePhysicalMemory / [double]$os.TotalVisibleMemorySize)
        $dt = [math]::Abs([double]$m.RamTotalGB - $totalGB)
        $dp = [math]::Abs([double]$m.Ram - $usedPct)
        if ($dt -gt 0.6) { Add-LiveRow 'sensor' 'bellek' 'HATA' ('toplam bellek uygulamada ' + [math]::Round([double]$m.RamTotalGB, 1) + ' GB, Windows tarafında ' + [math]::Round($totalGB, 1) + ' GB') }
        elseif ($dp -gt 12) { Add-LiveRow 'sensor' 'bellek' 'HATA' ('bellek doluluğu uygulamada %' + [int]$m.Ram + ', Windows tarafında %' + [int]$usedPct) }
        else { Add-LiveRow 'sensor' 'bellek' 'OK' ('uygulama %' + [int]$m.Ram + ' / ' + [math]::Round([double]$m.RamTotalGB, 1) + ' GB, Windows %' + [int]$usedPct + ' / ' + [math]::Round($totalGB, 1) + ' GB') }
    } catch { Add-LiveRow 'sensor' 'bellek' 'UYARI' ('Windows bellek değeri okunamadı: ' + $_.Exception.Message) }
    # islemci yuku: uygulamanin okudugu sayacla AYNI olcumu (Processor Information \ % Processor Utility) bagimsiz bir sayac nesnesiyle yeniden oku
    try {
        $pc = $null
        $cname = '% Processor Utility'
        try { $pc = New-Object System.Diagnostics.PerformanceCounter('Processor Information', '% Processor Utility', '_Total', $true) } catch { $pc = $null }
        if ($null -eq $pc) { try { $cname = '% Processor Time'; $pc = New-Object System.Diagnostics.PerformanceCounter('Processor', '% Processor Time', '_Total', $true) } catch { $pc = $null } }
        if ($null -ne $pc) {
            try {
                [void]$pc.NextValue()
                Start-Sleep -Milliseconds 1200
                $refCpu = [math]::Min(100.0, [double]$pc.NextValue())
                $appCpu = 0.0
                try { $appCpu = [double]$m.Cpu } catch { }
                $cpuTxt = 'uygulama %' + [int]$appCpu + ', bağımsız okuma (' + $cname + ') %' + [int]$refCpu
                if ([math]::Abs($appCpu - $refCpu) -gt 35) { Add-LiveRow 'sensor' 'islemci' 'UYARI' ('işlemci yükü iki okumada çok farklı: ' + $cpuTxt) }
                else { Add-LiveRow 'sensor' 'islemci' 'OK' $cpuTxt }
            } finally { $pc.Dispose() }
        } else { Add-LiveRow 'sensor' 'islemci' 'BILGI' ('bağımsız işlemci sayacı açılamadı; uygulama %' + [int]$m.Cpu) }
    } catch { Add-LiveRow 'sensor' 'islemci' 'BILGI' ('işlemci karşılaştırması yapılamadı: ' + $_.Exception.Message) }
    # ekran karti
    $gpuLoad = [double]$m.Gpu
    $gpuT = -1.0
    try { $gpuT = [double](Get-GpuTemp) } catch { }
    $appGpuT = -1.0
    try { if ($null -ne $m.GpuTemp) { $appGpuT = [double]$m.GpuTemp } } catch { }
    if ($gpuT -gt 0 -and $appGpuT -le 0) { Add-LiveRow 'sensor' 'ekran-karti-sicaklik' 'HATA' ('Windows ekran kartı sıcaklığı veriyor (' + [string]$gpuT + ' °C) ama izleme döngüsü bunu panoya taşımıyor') }
    Add-LiveRow 'sensor' 'ekran-karti' $(if ($gpuT -gt 0) { 'OK' } else { 'UYARI' }) ('yük=' + $(if ($gpuLoad -ge 0) { '%' + [int]$gpuLoad } else { 'ölçülemedi' }) + '; sıcaklık=' + $(if ($gpuT -gt 0) { [string]$gpuT + ' °C' } else { 'ölçülemedi (sürücü bu değeri vermiyor olabilir)' }))
    # islemci sicakligi: iki yol
    $tAcpi = -1.0; $tPerf = -1.0
    try { foreach ($z in @(Get-CimInstance -Namespace 'root/wmi' -ClassName 'MSAcpi_ThermalZoneTemperature' -OperationTimeoutSec 5 -ErrorAction Stop)) { $c = ([double]$z.CurrentTemperature / 10.0) - 273.15; if ($c -gt $tAcpi) { $tAcpi = $c } } } catch { }
    try { foreach ($z in @(Get-CimInstance -ClassName 'Win32_PerfFormattedData_Counters_ThermalZoneInformation' -OperationTimeoutSec 5 -ErrorAction Stop)) { $c = [double]$z.Temperature - 273.15; if ($c -gt $tPerf) { $tPerf = $c } } } catch { }
    $appT = [double]$m.Temp
    $txt = 'uygulama=' + $(if ($appT -gt 0) { [string]$appT + ' °C' } else { 'yok' }) + '; ACPI=' + $(if ($tAcpi -gt 0) { [string][math]::Round($tAcpi, 1) } else { 'yok' }) + '; sayaç=' + $(if ($tPerf -gt 0) { [string][math]::Round($tPerf, 1) } else { 'yok' })
    if (($tAcpi -gt 0 -or $tPerf -gt 0) -and $appT -le 0) { Add-LiveRow 'sensor' 'islemci-sicakligi' 'HATA' ('Windows sıcaklık veriyor ama uygulama “ölçülemedi” diyor: ' + $txt) }
    elseif ($appT -gt 0) { Add-LiveRow 'sensor' 'islemci-sicakligi' 'OK' $txt }
    else { Add-LiveRow 'sensor' 'islemci-sicakligi' 'BILGI' ('bu bilgisayarda Windows hiçbir yoldan sıcaklık vermiyor: ' + $txt) }
    # kartlarin yazisi: "olculuyor" ya da "sensor yok" nedenli mi
    try {
        foreach ($k in @($script:BoardViews.Keys)) {
            $v = $script:BoardViews[$k]
            $t = [string]$v.Type
            if ($t -ne 'gpu' -and $t -ne 'temp') { continue }
            $val = ''; $sub = ''
            try { $val = [string]$v.N.Val.Text; $sub = [string]$v.N.Sub.Text } catch { }
            if ($val -match 'ölçülüyor') { Add-LiveRow 'sensor' ('kart-' + $t) 'HATA' ('ilk ölçümlerden sonra kart hâlâ “ölçülüyor” yazıyor: ' + $val + ' [' + $sub + ']') }
            else { Add-LiveRow 'sensor' ('kart-' + $t) 'BILGI' ($val + ' [' + $sub + ']') }
        }
    } catch { }
}

# ---------------- saglik taramasi bulgulari: Windows'un kendi okumasiyla ayni mi ----------------
function Get-LiveFinding($Findings, [string]$Id) {
    foreach ($f in @($Findings)) { if ([string]$f.Id -eq $Id) { return $f } }
    return $null
}

function Test-LiveFindings {
    $r = Invoke-LiveJob 'Job_Health' @{ Level = 'Full' }
    if ($r.Err -ne '' -or $null -eq $r.Out) { Add-LiveRow 'bulgu' 'tarama' 'HATA' ('sağlık taraması çöktü: ' + $r.Err); return }
    $f = @($r.Out.Findings)
    $by = @{}
    foreach ($x in $f) { $by[[string]$x.Status] = [int]$by[[string]$x.Status] + 1 }
    Add-LiveRow 'bulgu' 'tarama' 'BILGI' ([string]$f.Count + ' bulgu: ' + (($by.Keys | Sort-Object | ForEach-Object { $_ + '=' + $by[$_] }) -join ' ') + '; puan ' + [string]$r.Out.Score.All)
    $nonOk = @($f | Where-Object { @('bad', 'warn') -contains [string]$_.Status })
    if ($nonOk.Count -gt 0) {
        $nonTxt = (@($nonOk | ForEach-Object { '[' + [string]$_.Status + '] ' + [string]$_.Id + ': ' + (Get-LiveShort ([string]$_.Title) 70) })) -join ' | '
        Add-LiveRow 'bulgu' 'sorunlu' 'BILGI' (Get-LiveShort $nonTxt 900)
    }
    # kopya kimlik ve bos metin
    $ids = @{}; $dups = New-Object System.Collections.ArrayList; $empty = New-Object System.Collections.ArrayList
    foreach ($x in $f) {
        $k = [string]$x.Id
        if ($ids.ContainsKey($k)) { [void]$dups.Add($k) } else { $ids[$k] = $true }
        if ([string]$x.Title -eq '') { [void]$empty.Add($k) }
    }
    if ($dups.Count -gt 0) { Add-LiveRow 'bulgu' 'kopya' 'HATA' ('aynı kimlikle birden çok bulgu: ' + ($dups -join ', ')) }
    if ($empty.Count -gt 0) { Add-LiveRow 'bulgu' 'bos-baslik' 'HATA' ('başlıksız bulgu: ' + ($empty -join ', ')) }
    # "sorun" olan her bulgunun bir eylemi (Fix ya da Action) var mi
    $noAct = New-Object System.Collections.ArrayList
    foreach ($x in $f) { if (@('bad', 'warn') -contains [string]$x.Status -and $null -eq $x.Fix -and $null -eq $x.Action) { [void]$noAct.Add([string]$x.Id) } }
    if ($noAct.Count -gt 0) { Add-LiveRow 'bulgu' 'eylemsiz' 'BILGI' ('eylemi olmayan sorun bulguları (yalnızca bilgi): ' + ($noAct -join ', ')) }
    # --- bagimsiz capraz denetim: uygulamanin yargisi (ok / info / warn / bad) Windows'un kendi okumasiyla ayni mi
    #     Her satir: Id = bulgu kimligi, Expect = kabul edilen durumlar ('yok' = bulgu hic uretilmemeli), Note = Windows'un verdigi deger
    $checks = New-Object System.Collections.ArrayList
    # guvenlik duvari
    try {
        $fp = @(Get-NetFirewallProfile -ErrorAction Stop)
        $allOn = (@($fp | Where-Object { [string]$_.Enabled -ne 'True' }).Count -eq 0)
        [void]$checks.Add(@{ Id = 'fw'; Expect = @($(if ($allOn) { 'ok' } else { 'bad' })); Note = 'profiller: ' + (($fp | ForEach-Object { [string]$_.Name + '=' + [string]$_.Enabled }) -join ' ') })
    } catch { }
    # Defender gercek zamanli koruma (ucuncu taraf antivirus varsa Defender pasif olabilir)
    try {
        $mp = Get-MpComputerStatus -ErrorAction Stop
        $third = @()
        try { $third = @(Get-CimInstance -Namespace 'root/SecurityCenter2' -ClassName AntivirusProduct -ErrorAction Stop | Where-Object { [string]$_.displayName -notmatch 'Windows Defender|Microsoft Defender' }) } catch { }
        if ([bool]$mp.RealTimeProtectionEnabled) { [void]$checks.Add(@{ Id = 'av-rt'; Expect = @('ok'); Note = 'RealTimeProtectionEnabled=True' }) }
        elseif ($third.Count -gt 0) { [void]$checks.Add(@{ Id = 'av-3p'; Expect = @('ok'); Note = 'Defender pasif, üçüncü taraf antivirüs: ' + [string]$third[0].displayName }) }
        else { [void]$checks.Add(@{ Id = 'av-rt'; Expect = @('bad'); Note = 'RealTimeProtectionEnabled=False, başka antivirüs yok' }) }
        [void]$checks.Add(@{ Id = 'av-tamper'; Expect = @($(if ([bool]$mp.IsTamperProtected) { 'ok' } else { 'warn' })); Note = 'IsTamperProtected=' + [string]$mp.IsTamperProtected })
    } catch { }
    # UAC
    $lua = Get-LiveRegRaw 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'EnableLUA'
    $cpa = Get-LiveRegRaw 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'ConsentPromptBehaviorAdmin'
    $luaV = 1; if ($lua.Exists) { $luaV = [int]$lua.Data }
    $cpaV = 5; if ($cpa.Exists) { $cpaV = [int]$cpa.Data }
    [void]$checks.Add(@{ Id = 'uac'; Expect = @($(if ($luaV -eq 0) { 'bad' } elseif ($cpaV -eq 0) { 'warn' } else { 'ok' })); Note = 'EnableLUA=' + $luaV + ' ConsentPromptBehaviorAdmin=' + $cpaV })
    # Uzak Masaustu: kapaliysa bulgu uretilmez, aciksa "info" ya da (NLA kapaliysa) "bad"
    $rdp = Get-LiveRegRaw 'HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server' 'fDenyTSConnections'
    $rdpV = 1; if ($rdp.Exists) { $rdpV = [int]$rdp.Data }
    $nlaR = Get-LiveRegRaw 'HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' 'UserAuthentication'
    $nlaV = 1; if ($nlaR.Exists) { $nlaV = [int]$nlaR.Data }
    [void]$checks.Add(@{ Id = 'rdp'; Expect = @($(if ($rdpV -ne 0) { 'yok' } elseif ($nlaV -eq 0) { 'bad' } else { 'info' })); Note = 'fDenyTSConnections=' + $rdpV + ' UserAuthentication=' + $nlaV })
    # TPM ve guvenli onyukleme (Get-Tpm yonetici ister; okunamazsa karsilastirma yapilmaz)
    try { $tp = Get-Tpm -ErrorAction Stop; [void]$checks.Add(@{ Id = 'tpm'; Expect = @($(if ([bool]$tp.TpmPresent) { 'ok' } else { 'info' })); Note = 'TpmPresent=' + [string]$tp.TpmPresent + ' Ready=' + [string]$tp.TpmReady }) } catch { }
    try { $sb = [bool](Confirm-SecureBootUEFI -ErrorAction Stop); [void]$checks.Add(@{ Id = 'sboot'; Expect = @($(if ($sb) { 'ok' } else { 'warn' })); Note = 'SecureBoot=' + [string]$sb }) } catch { }
    # geri yukleme noktasi
    try { $rp = @(Get-ComputerRestorePoint -ErrorAction Stop); [void]$checks.Add(@{ Id = 'rp'; Expect = @($(if ($rp.Count -gt 0) { 'ok' } else { 'info' })); Note = 'geri yükleme noktası=' + [string]$rp.Count }) } catch { [void]$checks.Add(@{ Id = 'rp'; Expect = @('info'); Note = 'Sistem Geri Yükleme kapalı ya da okunamıyor' }) }
    # SMB 1.0
    try { $smb = Get-SmbServerConfiguration -ErrorAction Stop; [void]$checks.Add(@{ Id = 'smb1'; Expect = @($(if ([bool]$smb.EnableSMB1Protocol) { 'bad' } else { 'yok' })); Note = 'EnableSMB1Protocol=' + [string]$smb.EnableSMB1Protocol }) } catch { }
    foreach ($ck in $checks) {
        $x = Get-LiveFinding $f ([string]$ck.Id)
        $exp = @($ck.Expect)
        if ($null -eq $x) {
            if ($exp -contains 'yok') { Add-LiveRow 'bulgu' ([string]$ck.Id) 'OK' ('bulgu yok, Windows: ' + $ck.Note) }
            else { Add-LiveRow 'bulgu' ([string]$ck.Id) 'HATA' ('bulgu üretilmedi ama Windows ' + $ck.Note + ' (beklenen durum: ' + ($exp -join '/') + ')') }
            continue
        }
        $got = [string]$x.Status
        if ($exp -contains $got) { Add-LiveRow 'bulgu' ([string]$ck.Id) 'OK' ('uygulama “' + $got + '”, Windows: ' + $ck.Note) }
        else { Add-LiveRow 'bulgu' ([string]$ck.Id) 'HATA' ('uygulamanın yargısı Windows ile çelişiyor: uygulama “' + $got + '” diyor, beklenen ' + ($exp -join '/') + '; Windows: ' + $ck.Note + ' | ' + (Get-LiveShort ([string]$x.Title) 100)) }
    }
}


# ---------------- son: baslangic durumuna donuldu mu, sayilar ----------------
# ---------------- Windows bileşenleri (Cap) ve Mağaza uygulamaları (Appx) ----------------
# oku: her bileşen ayarı önizlenir, motorun kararı (kaldırılacak / zaten yok / korumalı) bağımsız okumayla karşılaştırılır; uygulama listesi okunur.
# tam: her mekanizmadan bir temsilci gerçekten kaldırılıp uygulamanın kendi "geri al" akışıyla geri getirilir
#      (bileşen: Add-WindowsCapability internet ister; uygulama: paket klasöründeki AppxManifest.xml ile yeniden kayıt).
#      Diğer bileşenler aynı motordan geçer; onlar önizleme + bağımsız durum okumasıyla doğrulanır.
$script:LiveCapPrefer = @('App.StepsRecorder', 'MathRecognizer', 'XPS.Viewer', 'Print.Fax.Scan', 'Microsoft.Windows.WordPad', 'Microsoft.Windows.PowerShell.ISE', 'Media.WindowsMediaPlayer', 'Browser.InternetExplorer')

function Get-LiveCapState([string]$Match) {
    try {
        $all = @(Get-WindowsCapability -Online -ErrorAction Stop | Where-Object { ([string]$_.Name) -like ($Match + '*') })
        if ($all.Count -eq 0) { return 'yok' }
        if (@($all | Where-Object { @('Installed', 'InstallPending') -contains [string]$_.State }).Count -gt 0) { return 'kurulu' }
        return 'kaldirilmis'
    } catch { return 'okunamadi' }
}

function Get-LiveAppxState([string]$Pattern) {
    try {
        $p = @()
        if ($script:IsAdmin) { try { $p = @(Get-AppxPackage -AllUsers -Name $Pattern -ErrorAction Stop) } catch { $p = @() } }
        if ($p.Count -eq 0) { $p = @(Get-AppxPackage -Name $Pattern -ErrorAction Stop) }
        if ($p.Count -eq 0) { return 'yok' }
        return 'kurulu'
    } catch { return 'okunamadi' }
}

function Test-LiveComponents {
    $mode = Get-LiveMode
    $list = @(Get-LiveApplicable | Where-Object { (Get-LiveGroup $_) -eq 'bilesen' })
    Add-LiveRow 'bilesen' 'grup' 'BILGI' ([string]$list.Count + ' bileşen ayarı; kip=' + $mode)
    $capPick = $null
    $unread = 0
    foreach ($c in $list) {
        $id = [string]$c.Id
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $defects = New-Object System.Collections.ArrayList
        $states = New-Object System.Collections.ArrayList
        $mk = Get-LiveLogMark
        $pv = Invoke-LiveJob 'Job_Plan' @{ Steps = (New-StepsFromIds @($id)); Preview = $true; RestorePoint = $false }
        $lines = Get-LiveLogSince $mk
        if ($pv.Err -ne '') { Add-LiveRow 'bilesen' $id 'HATA' ('önizleme çöktü: ' + $pv.Err) $sw.ElapsedMilliseconds; continue }
        $chg = [int]$pv.Out.Changes
        $pureFeat = (@(@($c.Ops) | Where-Object { [string]$_.T -ne 'Feature' }).Count -eq 0)
        $featNeed = 0
        foreach ($op in @($c.Ops)) {
            if ([string]$op.T -eq 'Feature') {
                $fs = [string](Get-LiveFeatSnap ([string]$op.Name)).State
                if ($fs -eq '') { $fs = 'yok/okunamadı' }
                [void]$states.Add([string]$op.Name + '=' + $fs)
                if ($fs -eq 'yok/okunamadı') { continue }
                $wantOn = ([string]$op.State -eq 'Enabled')
                $isOn = ($fs -eq 'Enabled')
                if ($wantOn -ne $isOn) { $featNeed++ }
                continue
            }
            if ([string]$op.T -ne 'Cap') { continue }
            $m = [string]$op.Match
            $st = Get-LiveCapState $m
            [void]$states.Add($m + '=' + $st)
            if ($st -eq 'okunamadi') { $unread++; continue }
            $wantAbsent = ([string]$op.State -ne 'Installed')
            if ($st -eq 'kurulu' -and $wantAbsent -and $chg -eq 0) { [void]$defects.Add('bileşen kurulu ama önizleme kaldırma planlamadı: ' + $m) }
            if ($st -ne 'kurulu' -and $wantAbsent -and $chg -gt 0) { [void]$defects.Add('bileşen zaten yok ama önizleme kaldıracağım diyor: ' + $m) }
            if ($null -eq $capPick -and $st -eq 'kurulu' -and $wantAbsent -and $script:LiveCapPrefer -contains $m -and @($c.Ops).Count -eq 1) { $capPick = $c }
        }
        # yalnizca Windows ozelligi iceren ayarda motorun karari bagimsiz okumayla ayni olmali
        if ($pureFeat -and $featNeed -ne $chg) { [void]$defects.Add('önizleme ' + $chg + ' değişiklik diyor, bağımsız okuma ' + $featNeed + ' özelliğin farklı olduğunu gösteriyor') }
        $txt = 'önizleme ' + $chg + ' değişiklik, ' + [string]$pv.Out.Skipped + ' atlanan; durum: ' + ($states -join ', ')
        if ($defects.Count -gt 0) { Add-LiveRow 'bilesen' $id 'HATA' ($txt + '; ' + ($defects -join ' | ')) $sw.ElapsedMilliseconds }
        else { Add-LiveRow 'bilesen' $id 'OK' $txt $sw.ElapsedMilliseconds }
    }
    if ($unread -gt 0) { Add-LiveRow 'bilesen' 'durum-okuma' 'BILGI' ([string]$unread + ' bileşenin durumu bağımsız okunamadı (DISM yönetici ister); tam kipte okunur') }

    # Magaza uygulamalari: kaldirilabilir liste
    $mkA = Get-LiveLogMark
    $ra = Invoke-LiveJob 'Job_Apps' @{}
    $appPick = ''
    if ($ra.Err -ne '') { Add-LiveRow 'bilesen' 'uygulama-liste' 'HATA' ('liste çöktü: ' + $ra.Err) }
    else {
        $rows = @($ra.Out.Rows)
        $bad = 0
        foreach ($r in $rows) {
            $st = Get-LiveAppxState ([string]$r.Pattern)
            if ($st -eq 'yok') { $bad++ }
            if ($appPick -eq '' -and $st -eq 'kurulu' -and [bool]$r.R) { $appPick = [string]$r.Pattern }
        }
        if ($bad -gt 0) { Add-LiveRow 'bilesen' 'uygulama-liste' $(if ($script:IsAdmin) { 'HATA' } else { 'UYARI' }) ([string]$rows.Count + ' uygulama listelendi; ' + $bad + ' tanesi bağımsız okumada yüklü görünmüyor' + $(if ($script:IsAdmin) { '' } else { ' (yönetici olmayan okuma yalnızca bu kullanıcıyı görür)' })) }
        else { Add-LiveRow 'bilesen' 'uygulama-liste' 'OK' ([string]$rows.Count + ' kaldırılabilir uygulama; hepsi bağımsız okumada da yüklü') }
        if ($appPick -ne '') {
            $mkP = Get-LiveLogMark
            $steps = @(@{ Id = 'Apps'; Title = 'Denetim: uygulama'; Ops = @(@{ T = 'Appx'; Name = $appPick }); Reboot = $false })
            $pvA = Invoke-LiveJob 'Job_Plan' @{ Steps = $steps; Preview = $true; RestorePoint = $false }
            $planA = @((Select-LiveLines (Get-LiveLogSince $mkP) 'PLAN') | ForEach-Object { ($_ -replace '^\d\d:\d\d:\d\d\s+PLAN\s+', '') })
            $errA = @((Select-LiveLines (Get-LiveLogSince $mkP) 'ERR') | ForEach-Object { ($_ -replace '^\d\d:\d\d:\d\d\s+ERR\s+', '') })
            if ($pvA.Err -ne '') { Add-LiveRow 'bilesen' 'uygulama-onizleme' 'HATA' ('önizleme çöktü: ' + $pvA.Err) }
            elseif ([int]$pvA.Out.Errors -gt 0) { Add-LiveRow 'bilesen' 'uygulama-onizleme' 'HATA' ($appPick + ': önizleme hata verdi: ' + (Get-LiveShort ($errA -join ' | ') 160)) }
            elseif ([int]$pvA.Out.Changes -lt 1) { Add-LiveRow 'bilesen' 'uygulama-onizleme' 'HATA' ($appPick + ' yüklü ama önizleme kaldırma planlamadı') }
            else { Add-LiveRow 'bilesen' 'uygulama-onizleme' 'OK' ($appPick + ': ' + (Get-LiveShort ($planA -join '; ') 120)) }
        } else { Add-LiveRow 'bilesen' 'uygulama-onizleme' 'BILGI' 'önerilen kaldırılabilir uygulama kalmamış; önizleme denenmedi' }
    }

    if ($mode -ne 'tam') {
        Add-LiveRow 'bilesen' 'canli' 'ATLA' 'bileşen ve uygulama kaldırma gerçek sistemi değiştirir; temsilci tur yalnızca tam kipte (yönetici) yapılır'
        return
    }

    # tam: Windows ozellikleri. Hepsi gercekten uygulanip geri alinir: once hafifler, sonra yeniden baslatma bekletebilen ya da
    # indirme gerektiren agirlar (WSL, Hyper-V, sanal makine platformu, .NET 3.5, DirectPlay; bu surumde olmayanlar atlanir).
    # Baslangic engeli (Windows Update kuruyor / bilesen servisi zaten yeniden baslatma bekliyor) bolum basinda bir kez okunur:
    # turlarin kendi biraktigi bekleyen islem sonraki turlari (bilesen turu dahil) engellemez.
    $script:LiveSvcBlock0 = Get-LiveServicingBlock
    Test-LiveFeatureTrips $list

    # tam: temsilci bilesen
    $busyC = [string]$script:LiveSvcBlock0
    if ($busyC -eq '') { $busyC = Get-ServicingBusy }
    if ($busyC -eq '' -and $script:DismTimedOut) { $busyC = 'bu denetimde bir DISM işlemi süre sınırını aştı' }
    $capName = ''
    if ($null -ne $capPick) { $capName = [string]@($capPick.Ops)[0].Match }
    if ($null -eq $capPick) { Add-LiveRow 'bilesen' 'bilesen-tur' 'BILGI' ('kurulu ve denenebilir bileşen yok (tercih listesi: ' + ($script:LiveCapPrefer -join ', ') + ')') }
    elseif ($busyC -ne '') { Add-LiveRow 'bilesen' 'bilesen-tur' 'BILGI' ($busyC + '; bileşen turu yapılmadı') }
    elseif ($script:LiveStopKinds -contains 'Cap') { Add-LiveRow 'bilesen' 'bilesen-tur' 'BILGI' 'önceki bir bileşen geri kurulamadı ya da DISM süre sınırını aştı; güvenlik için tur yapılmadı' }
    elseif (@(Get-LiveRiskyNames) -contains $capName) { Add-LiveRow 'bilesen' 'bilesen-tur' 'BILGI' ('bu bilgisayarda daha önce geri kurulamadı: ' + $capName + '; canlı turda değiştirilmez') }
    elseif (-not (Test-LiveCapLive)) { Add-LiveRow 'bilesen' 'bilesen-tur' 'BILGI' ('temsilci bileşen ' + $capName + ' canlı kaldırılmadı: ' + $script:LiveCapWhy + '. Kaldırma planı önizlendi; bilerek denemek için MM_BILESEN_CANLI=1') }
    else {
        $cbc = Wait-LiveCbsIdle 180
        if ($cbc -ne '') { Add-LiveRow 'bilesen' 'bilesen-tur' 'BILGI' ('Windows bileşen hizmeti önceki işi sürdürüyor (' + $cbc + '); bileşen turu yapılmadı') }
        else { Invoke-LiveCapTrip $capPick }
    }
    # Magaza uygulamasi kaldirma geri alinamaz: motor uygulamayi tum kullanicilardan ve Windows goruntusunden siler, dosyalar gider,
    # yalnizca Microsoft Store'dan geri gelir (cihazda 18.11.2026: Microsoft 365 Copilot boyle kaldirildi). Bu yuzden temsilci
    # uygulama yalnizca onizlenir; kullanici bilerek bir paket adi verirse (MM_UYGULAMA_CANLI) yalnizca o uygulama canli denenir.
    $appOpt = [string]$env:MM_UYGULAMA_CANLI
    if ($appOpt -ne '') {
        if ($appOpt -cnotmatch '^[A-Za-z0-9\.\-_]{3,120}$') { Add-LiveRow 'bilesen' 'uygulama-tur' 'HATA' ('MM_UYGULAMA_CANLI geçersiz paket adı: ' + $appOpt) }
        elseif ((Get-LiveAppxState $appOpt) -ne 'kurulu') { Add-LiveRow 'bilesen' 'uygulama-tur' 'BILGI' ('MM_UYGULAMA_CANLI=' + $appOpt + ': bu uygulama yüklü değil; tur yapılmadı') }
        else { Invoke-LiveAppxTrip $appOpt }
    }
    elseif ($appPick -eq '') { Add-LiveRow 'bilesen' 'uygulama-tur' 'BILGI' 'denenecek yüklü uygulama yok' }
    else { Add-LiveRow 'bilesen' 'uygulama-tur' 'BILGI' ('temsilci uygulama ' + $appPick + ' canlı kaldırılmadı: kaldırma uygulamayı tüm kullanıcılardan ve Windows görüntüsünden siler, yalnızca Microsoft Store’dan geri gelir. Kaldırma planı önizlendi; bilerek denemek için MM_UYGULAMA_CANLI=<paket adı>') }
}

# Hafif Windows ozellikleri (yerel kaynakla saniyeler icinde acilip kapanir): canli turda once bunlar denenir.
# Agir olanlar (WSL, Sanal Makine Platformu, Hyper-V, .NET 3.5, DirectPlay...) de tam kipte canli denenir ama en sona birakilir:
# yeniden baslatma bekletebilir ya da Windows Update'ten indirme gerektirebilir; biri geri yuklenemezse kalan ozellik turlari durur.
$script:LiveSvcBlock0 = $null
$script:LiveFeatLight = @('Printing-Foundation-InternetPrinting-Client', 'WorkFolders-Client', 'SMB1Protocol', 'SMB1Protocol-Client', 'SMB1Protocol-Server',
    'SMB1Protocol-Deprecation', 'MicrosoftWindowsPowerShellV2', 'MicrosoftWindowsPowerShellV2Root', 'Printing-XPSServices-Features', 'TelnetClient', 'TFTP',
    'Printing-Foundation-LPDPrintService', 'Printing-Foundation-LPRPortMonitor', 'MSRDC-Infrastructure', 'Internet-Explorer-Optional-amd64')

# Ozellik turlarinin sirasi (kararli; katalog sirasi korunur):
#  1) ozelligi KAPATAN turlar: geri almak ozelligi yeniden acmayi gerektirir; bilesen hizmeti temizken yapilir,
#  2) ozelligi ACAN turlar,
#  3) Windows bilesenini (FOD) de kaldiran turlar: kaldirma yeniden baslatma bekletir, geri kurulum Windows Update'ten iner.
# Her grupta hafifler once, agirlar sonra. Cihazda (18.11.2026) XPS turu bekleyen islem biraktiktan sonra Is Klasorleri
# kapatildi ve hemen yeniden acilamadi (0x371B); onceki denetimde ayni sira tesadufen sorunsuz gecmisti.
function Get-LiveFeatureOrder($List) {
    $items = @(@($List) | Where-Object { @(@($_.Ops) | Where-Object { [string]$_.T -eq 'Feature' }).Count -gt 0 })
    $groups = @()
    for ($i = 0; $i -lt 6; $i++) { $groups += , (New-Object System.Collections.ArrayList) }
    foreach ($c in $items) {
        $fops = @(@($c.Ops) | Where-Object { [string]$_.T -eq 'Feature' })
        $names = @($fops | ForEach-Object { [string]$_.Name })
        $heavy = (@($names | Where-Object { $script:LiveFeatLight -notcontains $_ }).Count -gt 0)
        $hasCap = (@(@($c.Ops) | Where-Object { [string]$_.T -eq 'Cap' }).Count -gt 0)
        $offs = (@($fops | Where-Object { [string]$_.State -ne 'Enabled' }).Count -gt 0)
        $g = 1
        if ($hasCap) { $g = 2 } elseif ($offs) { $g = 0 }
        $k = 2 * $g
        if ($heavy) { $k++ }
        [void]$groups[$k].Add($c)
    }
    $out = New-Object System.Collections.ArrayList
    foreach ($gl in $groups) { foreach ($x in $gl) { [void]$out.Add($x) } }
    return $out.ToArray()
}

# Ogenin canli turda kaldiracagi, su an kurulu Windows bilesenleri (FOD). Kaldirilan bilesen yalnizca Windows Update'ten geri
# kurulur ve icerik her zaman bulunmaz: cihazda 18.11.2026 22:49'da XPS Goruntuleyici ve Adim Kaydedicisi 0x800F0950 ile geri
# kurulamadi (once iki denetimde sorunsuz geri gelmislerdi). Bu yuzden bilesen kaldirma varsayilan olarak yalnizca onizlenir.
function Get-LiveCapRemovals($C) {
    $names = New-Object System.Collections.ArrayList
    foreach ($op in @($C.Ops)) {
        if ([string]$op.T -ne 'Cap' -or [string]$op.State -eq 'Installed') { continue }
        $m = [string]$op.Match
        if ((Get-LiveCapState $m) -eq 'kurulu') { [void]$names.Add($m) }
    }
    return $names.ToArray()
}
function Test-LiveCapLive { return ([string]$env:MM_BILESEN_CANLI -eq '1') }
$script:LiveCapWhy = 'kaldırılan bileşen yalnızca Windows Update’ten geri kurulabilir ve içerik her zaman bulunmaz (bu bilgisayarda 18.11.2026’da 0x800F0950 ile geri kurulamadı)'

# Bu denetimde Windows bir bilesen degisikligi icin yeniden baslatma bekliyor mu? (CBS anahtari ya da DISM'in
# "once yeniden baslatin" kodu). '' = beklemiyor.
function Get-LiveRebootNeed {
    $p = [string](Get-CbsRebootPending)
    if ($p -ne '') { return $p }
    if ($script:DismNeedsReboot) { return 'DISM' }
    return ''
}

# Windows bileşeni / özelliği turu şimdi yapılabilir mi? Windows Update kurulum yapıyorsa ya da bileşen servisi yeniden başlatma
# bekliyorsa DISM işlemi uzun sürebilir, reddedilebilir (0x800F082F) ya da yarım kalabilir: tur yapılmaz, yalnızca önizlenir.
function Get-LiveServicingBlock {
    $busy = Get-ServicingBusy
    if ($busy -ne '') { return $busy }
    try {
        $cbs = Get-RegSubKeyNames 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing'
        foreach ($k in @('RebootPending', 'RebootInProgress', 'PackagesPending')) {
            if ($cbs -contains $k) { return ('Windows bir bileşen değişikliği için yeniden başlatılmayı bekliyor (' + $k + '; yeniden başlatıp tam denetimi tekrarlayın)') }
        }
    } catch { }
    return ''
}

# Bilesen hizmeti surecleri: dism/DismHost calisiyorsa yeni DISM istegi siraya girer ve uzun sure bekler (cihazda 20 dakika goruldu).
# TiWorker (Windows Modules Installer Worker) DISM bittikten sonra bir sure daha calisabilir: beklenir ama tek basina engel sayilmaz.
$script:LiveCbsHard = @('dism', 'DismHost')
$script:LiveCbsSoft = @('TiWorker')

function Get-LiveProcNames([string[]]$Names) {
    $found = New-Object System.Collections.ArrayList
    foreach ($n in @($Names)) { try { if (@(Get-Process -Name $n -ErrorAction SilentlyContinue).Count -gt 0) { [void]$found.Add($n) } } catch { } }
    return ($found.ToArray() -join ', ')
}

# En cok $MaxSec saniye bilesen hizmetinin bosalmasini bekler. Donus: hala calisan dism/DismHost ('' = DISM baslatilabilir)
function Wait-LiveCbsIdle([int]$MaxSec = 180) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($true) {
        $hard = Get-LiveProcNames $script:LiveCbsHard
        $soft = Get-LiveProcNames $script:LiveCbsSoft
        if ($hard -eq '' -and $soft -eq '') { return '' }
        if ($sw.Elapsed.TotalSeconds -ge $MaxSec) { return $hard }
        Start-Sleep -Seconds 5
    }
}

# Ozellik turu bu ozelligi gercekten degistirecek mi: istenen durum ile simdiki durum farkli mi ('' = okunamadi / yok: degistirmez)
function Get-LiveFeatChange($Op) {
    $cur = [string](Get-LiveFeatSnap ([string]$Op.Name)).State
    if ($cur -eq '') { return '' }
    $curOn = (@('Enabled', 'EnablePending') -contains $cur)
    $wantOn = ([string]$Op.State -eq 'Enabled')
    if ($curOn -eq $wantOn) { return '' }
    if ($wantOn) { return 'ac' }
    return 'kapat'
}

function Test-LiveFeatureTrips($List) {
    $items = @(Get-LiveFeatureOrder $List)
    if ($items.Count -eq 0) { return }
    # Bolum basinda Windows Update kuruyorsa ya da bilesen servisi zaten yeniden baslatma bekliyorsa baslangic durumu belirsizdir:
    # hicbir ozellik turu yapilmaz (yalnizca onizlenir). Turlarin kendi biraktigi bekleyen islem yalnizca ozelligi KAPATAN
    # turlari durdurur (asagida 3); acan turlar ve bilesen turlari bekleyen islemle de geri alinabiliyor.
    $block = $script:LiveSvcBlock0
    if ($null -eq $block) { $block = Get-LiveServicingBlock }
    $block = [string]$block
    $risky = @(Get-LiveRiskyNames)
    $heavyOk = ([string]$env:MM_OZELLIK_AGIR -eq '1')
    foreach ($c in $items) {
        $id = [string]$c.Id
        $fops = @(@($c.Ops) | Where-Object { [string]$_.T -eq 'Feature' })
        $names = @($fops | ForEach-Object { [string]$_.Name })
        $heavy = @($names | Where-Object { $script:LiveFeatLight -notcontains $_ })
        if ($block -ne '') { Add-LiveRow 'bilesen' ('tur:' + $id) 'BILGI' ($block + '; tur yapılmadı (geri alınamayacak yarım iş bırakmamak için)'); Invoke-LiveRoundTrip $c 'oku'; continue }
        if ($script:LiveStopKinds -contains 'Feature') { Add-LiveRow 'bilesen' ('tur:' + $id) 'BILGI' 'önceki bir Windows özelliği geri yüklenemedi ya da DISM süre sınırını aştı; güvenlik için bu tur yalnızca önizlendi'; Invoke-LiveRoundTrip $c 'oku'; continue }
        $busy = Get-ServicingBusy
        if ($busy -ne '') { Add-LiveRow 'bilesen' ('tur:' + $id) 'BILGI' ($busy + '; tur yapılmadı (geri alınamayacak yarım iş bırakmamak için)'); Invoke-LiveRoundTrip $c 'oku'; continue }
        # bu turun degistirecegi ozellikler (simdiki durum istenenden farkliysa)
        $chg = @{}
        foreach ($op in $fops) { $w = Get-LiveFeatChange $op; if ($w -ne '') { $chg[[string]$op.Name] = $w } }
        # 1) bu bilgisayarda daha once geri yuklenemeyen ozellik: bir daha degistirilmez (yalnizca okunur ve onizlenir)
        $rk = @($chg.Keys | Where-Object { $risky -contains $_ } | Sort-Object)
        if ($rk.Count -gt 0) {
            Add-LiveRow 'bilesen' ('tur:' + $id) 'BILGI' ('bu bilgisayarda daha önce geri yüklenemedi: ' + ($rk -join ', ') + '; canlı turda değiştirilmez, yalnızca okundu ve önizlendi (liste: ozellik-riskli.json)')
            Invoke-LiveRoundTrip $c 'oku'; continue
        }
        # 2) agir ozelligi KAPATMAK: geri acmak dosyalarini Windows Update'ten indirmeyi gerektirebilir (cihazda saatlerce acilamadi)
        $hk = @($chg.Keys | Where-Object { $chg[$_] -eq 'kapat' -and $script:LiveFeatLight -notcontains $_ } | Sort-Object)
        if ($hk.Count -gt 0 -and -not $heavyOk) {
            Add-LiveRow 'bilesen' ('tur:' + $id) 'BILGI' ('ağır Windows özelliği açık: ' + ($hk -join ', ') + '; kapatıp geri açmak dosyalarını Windows Update’ten indirmeyi gerektirebilir (bu bilgisayarda Sanal Makine Platformu böyle geri açılamadı). Canlı kapatılmadı; durum okundu ve önizlendi. Bilerek denemek için: MM_OZELLIK_AGIR=1')
            Invoke-LiveRoundTrip $c 'oku'; continue
        }
        # 3a) Windows bilesenini de kaldiran oge: geri kurulum Windows Update'e bagli, varsayilan olarak yalnizca onizlenir
        $capRm = @(Get-LiveCapRemovals $c)
        if ($capRm.Count -gt 0 -and -not (Test-LiveCapLive)) {
            Add-LiveRow 'bilesen' ('tur:' + $id) 'BILGI' ('Windows bileşeni kaldırma canlı denenmedi (' + ($capRm -join ', ') + '): ' + $script:LiveCapWhy + '. Durum okundu ve önizlendi; bilerek denemek için MM_BILESEN_CANLI=1')
            Invoke-LiveRoundTrip $c 'oku'; continue
        }
        # 3) ozelligi KAPATAN tur, bu denetimde Windows yeniden baslatma beklerken yapilmaz: kapatilan ozelligi hemen geri acmak
        #    bu durumda basarisiz olabiliyor (cihazda Is Klasorleri 0x371B ile acilamadi) ve ozellik kapali kalir.
        $offk = @($chg.Keys | Where-Object { $chg[$_] -eq 'kapat' } | Sort-Object)
        if ($offk.Count -gt 0) {
            $rn = Get-LiveRebootNeed
            if ($rn -ne '') {
                Add-LiveRow 'bilesen' ('tur:' + $id) 'BILGI' ('Windows bu denetimdeki önceki bir bileşen değişikliği için yeniden başlatma bekliyor (' + $rn + '); kapatılan özelliği hemen geri açmak bu durumda başarısız olabiliyor (bu bilgisayarda İş Klasörleri böyle açılamadı). ' + ($offk -join ', ') + ' canlı kapatılmadı; durum okundu ve önizlendi, yeniden başlatmadan sonraki denetimde canlı denenir.')
                Invoke-LiveRoundTrip $c 'oku'; continue
            }
        }
        # 4) bilesen hizmeti bos mu (onceki turun DISM'i ya da Windows bakim isi suruyorsa yeni istek asili kalir)
        $cb = Wait-LiveCbsIdle 180
        if ($cb -ne '') {
            [void]$script:LiveStopKinds.Add('Feature'); [void]$script:LiveStopKinds.Add('Cap')
            Add-LiveRow 'bilesen' ('tur:' + $id) 'BILGI' ('Windows bileşen hizmeti önceki işi sürdürüyor (' + $cb + '); kalan özellik ve bileşen turları yapılmadı, yalnızca önizlendi')
            Invoke-LiveRoundTrip $c 'oku'; continue
        }
        if ($heavy.Count -gt 0) { Add-LiveRow 'bilesen' ('agir:' + $id) 'BILGI' ('ağır Windows özelliği (' + ($heavy -join ', ') + '): canlı deneniyor; yeniden başlatma bekletebilir ya da Windows Update indirmesi gerektirebilir') }
        # uygula -> dogrula -> geri al -> karsilastir (genel tur; satir 'tur' alaninda yazilir)
        Invoke-LiveRoundTrip $c 'tam'
        # DISM bu turda sure sinirini astiysa bilesen hizmeti arka planda calisiyor olabilir: kalan DISM turlari yapilmaz
        if ($script:DismTimedOut -and -not ($script:LiveStopKinds -contains 'Feature')) {
            [void]$script:LiveStopKinds.Add('Feature'); [void]$script:LiveStopKinds.Add('Cap')
            Add-LiveRow 'bilesen' ('dism:' + $id) 'UYARI' 'DISM süre sınırını aştı; kalan özellik ve bileşen turları yapılmadı. Bilgisayarı yeniden başlatıp tam denetimi tekrarlayın.'
        }
    }
}

function Invoke-LiveCapTrip($C) {
    $id = [string]$C.Id
    $m = [string]@($C.Ops)[0].Match
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $defects = New-Object System.Collections.ArrayList
    Save-LiveInflight $id @(@{ K = 'Cap'; Name = $m; Data = 'kurulu' })
    Add-LiveCompTouched 'Cap' $m
    $t0 = Get-Date
    try {
        $mk1 = Get-LiveLogMark
        $r1 = Invoke-LiveJob 'Job_Plan' @{ Steps = (New-StepsFromIds @($id)); Preview = $false; RestorePoint = $false }
        $log1 = Get-LiveLogSince $mk1
        if ($r1.Err -ne '') { [void]$defects.Add('kaldırma çöktü: ' + $r1.Err) }
        elseif ([int]$r1.Out.Errors -gt 0) { [void]$defects.Add('kaldırma ' + [string]$r1.Out.Errors + ' hata verdi: ' + (Get-LiveShort ((Select-LiveLines $log1 'ERR') -join ' | ') 200)) }
        $st1 = Get-LiveCapState $m
        if ($defects.Count -eq 0 -and $st1 -eq 'kurulu') { [void]$defects.Add('kaldırıldı dendi ama DISM hâlâ kurulu görüyor') }
        $jf = Get-LiveJournalAfter $t0
        $st2 = ''
        $capWhy = ''
        if ($jf -eq '') { [void]$defects.Add('geri alma günlüğü yazılmadı') }
        else {
            $mk2 = Get-LiveLogMark
            $r2 = Invoke-LiveJob 'Job_Undo' @{ File = $jf }
            $log2 = Get-LiveLogSince $mk2
            if ($r2.Err -ne '') { [void]$defects.Add('geri alma çöktü: ' + $r2.Err) }
            elseif ([int]$r2.Out.Errors -gt 0) { [void]$defects.Add('geri alma ' + [string]$r2.Out.Errors + ' hata verdi: ' + (Get-LiveShort ((Select-LiveLines $log2 'ERR') -join ' | ') 200)) }
            $st2 = Get-LiveCapState $m
            if ($st2 -ne 'kurulu') {
                [void]$defects.Add('geri alma bileşeni geri kuramadı (internet / Windows Update erişimi gerekir); elle: Add-WindowsCapability -Online -Name ' + $m)
                try { [void](Set-WinCapabilityState $m $true); $st2 = Get-LiveCapState $m } catch { $capWhy = [string]$_.Exception.Message }
            }
        }
        if ($st2 -eq 'kurulu') { Clear-LiveInflight }
        else {
            # geri kurulamadi: kalici kurtarma listesine alinir (sonraki tam denetimde yeniden denenir), bilesen turlari durur
            Add-LiveUnrestored $id @(@{ K = 'Cap'; Name = $m; Data = 'kurulu' }) ('bileşen geri kurulamadı: ' + $m + $(if ($capWhy -ne '') { ' (' + (Get-LiveShort $capWhy 200) + ')' } else { '' }))
            [void]$script:LiveStopKinds.Add('Cap')
            Clear-LiveInflight
        }
        $st = 'OK'; if ($defects.Count -gt 0) { $st = 'HATA' }
        Add-LiveRow 'bilesen' ('tur:' + $id) $st ('temsilci bileşen ' + $m + ': kaldırma → ' + $st1 + ' → geri al → ' + $st2 + $(if ($defects.Count -gt 0) { '; ' + ($defects -join ' | ') } else { '' })) $sw.ElapsedMilliseconds
    } catch {
        try { [void](Set-WinCapabilityState $m $true); Clear-LiveInflight } catch { }
        Add-LiveRow 'bilesen' ('tur:' + $id) 'HATA' ('tur çöktü: ' + $_.Exception.Message) $sw.ElapsedMilliseconds
    }
}

function Invoke-LiveAppxTrip([string]$Pattern) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $defects = New-Object System.Collections.ArrayList
    $locs = @()
    try { $locs = @(Get-AppxSafe $Pattern | ForEach-Object { [string]$_.InstallLocation } | Where-Object { $_ -ne '' } | Sort-Object -Unique) } catch { }
    Save-LiveInflight ('appx:' + $Pattern) @(@{ K = 'Appx'; Name = $Pattern; Locs = $locs })
    $t0 = Get-Date
    try {
        $steps = @(@{ Id = 'Apps'; Title = 'Denetim: uygulama'; Ops = @(@{ T = 'Appx'; Name = $Pattern }); Reboot = $false })
        $mk1 = Get-LiveLogMark
        $r1 = Invoke-LiveJob 'Job_Plan' @{ Steps = $steps; Preview = $false; RestorePoint = $false }
        $log1 = Get-LiveLogSince $mk1
        if ($r1.Err -ne '') { [void]$defects.Add('kaldırma çöktü: ' + $r1.Err) }
        elseif ([int]$r1.Out.Errors -gt 0) { [void]$defects.Add('kaldırma ' + [string]$r1.Out.Errors + ' hata verdi: ' + (Get-LiveShort ((Select-LiveLines $log1 'ERR') -join ' | ') 200)) }
        $st1 = Get-LiveAppxState $Pattern
        if ($defects.Count -eq 0 -and $st1 -eq 'kurulu') { [void]$defects.Add('kaldırıldı dendi ama paket hâlâ yüklü görünüyor') }
        $jf = Get-LiveJournalAfter $t0
        $st2 = ''
        $note = ''
        if ($jf -eq '') { [void]$defects.Add('geri alma günlüğü yazılmadı') }
        else {
            $mk2 = Get-LiveLogMark
            $r2 = Invoke-LiveJob 'Job_Undo' @{ File = $jf }
            $log2 = Get-LiveLogSince $mk2
            if ($r2.Err -ne '') { [void]$defects.Add('geri alma çöktü: ' + $r2.Err) }
            $st2 = Get-LiveAppxState $Pattern
            if ($st2 -ne 'kurulu') {
                $note = 'uygulama paket klasöründen geri kaydedilemedi (dosyalar silinmiş); Microsoft Store''dan yeniden yüklenebilir: ' + $Pattern
            }
        }
        Clear-LiveInflight
        $st = 'OK'
        if ($defects.Count -gt 0) { $st = 'HATA' } elseif ($note -ne '') { $st = 'UYARI' }
        $txt = 'temsilci uygulama ' + $Pattern + ': kaldırma → ' + $st1 + ' → geri al → ' + $st2
        if ($note -ne '') { $txt += '; ' + $note }
        if ($defects.Count -gt 0) { $txt += '; ' + ($defects -join ' | ') }
        Add-LiveRow 'bilesen' 'uygulama-tur' $st $txt $sw.ElapsedMilliseconds
    } catch {
        try { Restore-LiveInflight } catch { }
        Add-LiveRow 'bilesen' 'uygulama-tur' 'HATA' ('tur çöktü: ' + $_.Exception.Message) $sw.ElapsedMilliseconds
    }
}

function Complete-LiveAudit {
    $mode = Get-LiveMode
    # bilerek yapilan olumsuz denemelerin gunluk satirlari gercekten yazildi mi (once gunluk son kez taranir)
    try { Invoke-SmokeFlush } catch { }
    try { [void](Read-SmokeLogDelta) } catch { }
    $missingLog = @(Get-SmokeExpectMissing)
    if ($missingLog.Count -gt 0) { Add-LiveRow 'ozet' 'beklenen-gunluk' 'HATA' ('olumsuz denemelerin günlük satırı yazılmadı: ' + ($missingLog -join '; ')) }
    # sistem denetimin basindaki haline donmus olmali: tum ayarlarin olcumu yeniden alinip basla karsilastirilir
    $moved = New-Object System.Collections.ArrayList
    $outside = New-Object System.Collections.ArrayList
    $n = 0
    foreach ($c in @(Get-LiveApplicable)) {
        $id = [string]$c.Id
        if (-not $script:LiveState.ContainsKey($id)) { continue }
        $n++
        $now = -1
        try { $now = Get-TweakPending $c } catch { }
        if ([int]$now -ne [int]$script:LiveState[$id]) {
            $mv = $id + ' (' + $script:LiveState[$id] + '→' + $now + ')'
            if (Test-LiveMovedOutside $c) { [void]$outside.Add($mv) } else { [void]$moved.Add($mv) }
        }
    }
    if ($outside.Count -gt 0) { Add-LiveRow 'ozet' 'dis-degisiklik' 'UYARI' ('denetimin değiştirmediği Windows özellik/bileşenleri denetim sırasında başka bir yoldan değişti (Windows Update, Windows ya da kullanıcı): ' + ($outside -join ', ')) }
    # kurtarma listesindeki kayıt denetim sırasında eski durumuna döndüyse listeden çıkar, sonra kalanları yaz
    try { Remove-LiveUnrestoredDone } catch { }
    # denetimin geri yukleyemedigi degisiklikler (kalici kurtarma listesi) ozet olarak yazilir
    $unr = @(Get-LiveUnrestored)
    if ($unr.Count -gt 0) { Add-LiveRow 'ozet' 'kurtarma-listesi' 'HATA' ([string]$unr.Count + ' değişiklik geri yüklenemedi ve kurtarma listesinde bekliyor (bir sonraki tam denetimde yeniden denenir): ' + (($unr | ForEach-Object { [string]$_.Id + ': ' + (Get-LiveShort ([string]$_.Why) 120) }) -join ' | ')) }
    if ($n -eq 0) { Add-LiveRow 'ozet' 'son-durum' 'BILGI' 'başlangıç ölçümü alınmadığı için son durum karşılaştırılamadı' }
    elseif ($moved.Count -gt 0) { Add-LiveRow 'ozet' 'son-durum' 'HATA' ('denetim sonunda başlangıçtan farklı kalan ayarlar: ' + ($moved -join ', ')) }
    else { Add-LiveRow 'ozet' 'son-durum' 'OK' ([string]($n - $outside.Count) + ' ayarın durumu denetim başlangıcıyla aynı') }
    # yarim kalan geri yukleme dosyasi
    $f = Join-Path (Get-LiveDir) 'ozellik-yarim.json'
    if (Test-Path -LiteralPath $f) { Add-LiveRow 'ozet' 'yarim' 'UYARI' 'diskte yarım kalan geri yükleme dosyası duruyor (bir sonraki tam denetimde otomatik geri yüklenir)' }
    # sayilar
    $ok = Get-LiveCount 'OK'; $err = Get-LiveCount 'HATA'; $warn = Get-LiveCount 'UYARI'; $skip = Get-LiveCount 'ATLA'; $info = Get-LiveCount 'BILGI'
    $sec = 0
    try { if ($null -ne $script:LiveT0) { $sec = [int]((Get-Date) - $script:LiveT0).TotalSeconds } } catch { }
    $byArea = @{}
    foreach ($r in @($script:LiveRows)) { if ($r.Durum -eq 'HATA') { $byArea[[string]$r.Alan] = [int]$byArea[[string]$r.Alan] + 1 } }
    $areaTxt = ''
    if ($byArea.Count -gt 0) { $areaTxt = ' (' + ((@($byArea.Keys | Sort-Object) | ForEach-Object { $_ + '=' + $byArea[$_] }) -join ', ') + ')' }
    Add-SmokeLine ('canlı özet: kip=' + $mode + '; ' + $ok + ' tamam, ' + $err + ' hata' + $areaTxt + ', ' + $warn + ' uyarı, ' + $skip + ' atlandı, ' + $info + ' bilgi; süre ' + (Format-LiveMs ($sec * 1000)))
    try { Add-SmokeLine ('canlı özet: ayrıntılı tablo ' + [string]$script:LiveTsv) } catch { }
    try { [Console]::WriteLine('  ozet: ' + $ok + ' tamam, ' + $err + ' hata, ' + $warn + ' uyari, ' + $skip + ' atlandi') } catch { }
}

# ---------------- duman adimi: "LiveCheck" ----------------
# Arg: ortam | olcum | tur:<grup> | etki | sapma | arac | is:<grup> | sensor | bulgu | ozet
function Test-SmokeLive([string]$Arg) {
    $parts = $Arg.Split(':')
    $kind = $parts[0]
    $sub = ''
    if ($parts.Count -gt 1) { $sub = $parts[1] }
    if ($null -eq $script:LiveT0) { $script:LiveT0 = Get-Date }
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Add-SmokeLine ('    canlı bölüm: ' + $Arg + ' başladı')
    try {
        switch ($kind) {
            'ortam'  { Test-LiveEnv }
            'olcum'  { Test-LiveMeasure }
            'tur'    { Test-LiveRoundTrips $sub }
            'etki'   { Test-LiveVisual; Test-LivePower }
            'sapma'  { Test-LiveDrift }
            'arac'   { Test-LiveTools }
            'is'     { Test-LiveJobs $sub }
            'bilesen' { Test-LiveComponents }
            'sensor' { Test-LiveSensors }
            'bulgu'  { Test-LiveFindings }
            'ozet'   { Complete-LiveAudit }
            default  { Add-LiveRow 'ozellik' $Arg 'HATA' 'bilinmeyen denetim bölümü' }
        }
    } catch {
        Add-LiveRow $kind $sub 'HATA' ('bölüm çöktü: ' + $_.Exception.Message + ' (satır ' + [string]$_.InvocationInfo.ScriptLineNumber + ')')
        if ((Get-LiveMode) -eq 'tam') { try { Restore-LiveInflight } catch { } }
    }
    Add-SmokeLine ('    canlı bölüm: ' + $Arg + ' bitti (' + (Format-LiveMs $sw.ElapsedMilliseconds) + ')')
    try { Invoke-SmokeFlush } catch { }
}
