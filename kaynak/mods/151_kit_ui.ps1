# ==================================================================
#  YARDIMCILAR (arayuz): Araclar > Yardimcilar sekmesi
#  Ana liste ve alt gorunumler ayni listede cizilir; her alt gorunumun basinda "Geri" satiri vardir.
#  Cekirdek islevler: 150_kit_core.ps1
# ==================================================================
$script:KitView = 'home'
$script:KitPw = @{ Len = 20; Upper = $true; Digit = $true; Symbol = $true; Value = '' }
$script:KitPwTimer = $null
$script:KitRen = @{ Dir = ''; Items = @(); Mode = ''; Arg = ''; Plan = $null }
$script:KitScore = $null
$script:KitNet = $null
$script:KitAlt = $null
$script:KitPending = $null

function Set-KitView([string]$View) {
    $script:KitView = $View
    if ($script:TlTab -eq 'kit') { Render-TlKit }
}

function Add-KitBack([string]$Title) {
    Add-TlAction ('‹ ' + $Title) 'Yardımcılar listesine dön.' 'BrDim' 'kit:home' 'Geri'
}

function Render-TlKit {
    $ui.tl_List.Children.Clear()
    switch ([string]$script:KitView) {
        'pw' { Render-KitPw }
        'ren' { Render-KitRename }
        'score' { Render-KitScore }
        'net' { Render-KitNet }
        'alt' { Render-KitAlt }
        'setup' { Render-KitSetup }
        default { Render-KitHome }
    }
}

function Render-KitHome {
    Add-HeadRow $ui.tl_List 'Bilgisayar'
    Add-TlAction 'Yeni bilgisayar / format sonrası adımları' 'Güncelleme, eksik bileşenler, önerilen ayarlar, temel programlar ve yedekleme: sırayla, her adım kendi sayfasına götürür.' 'BrAccent' 'kit:setup' 'Aç'
    Add-TlAction 'Karne: önce ve sonra' 'Her işlemden önce ve sonra çalışan hizmet, işlem, boş bellek ve boş disk alanı ölçülür. Kazancı rakamla görürsünüz; kayıt yalnızca bu bilgisayarda durur.' 'BrAccent' 'kit:score' 'Aç'
    Add-HeadRow $ui.tl_List 'Gizlilik'
    Add-TlAction 'Hangi program internete bağlanıyor?' 'Şu anda internet bağlantısı açık olan programları ve bağlandıkları adres sayısını listeler. İstemediğiniz programın internetini tek tıkla kesebilirsiniz (geri alınabilir).' 'BrAccent2' 'kit:net' 'Tara'
    Add-TlAction 'Açık kaynak alternatifleri' 'Kurulu programlarınıza bakar; veri toplayan ya da ücretli olanların açık kaynak karşılığını önerir. Hiçbir şey kendiliğinden kurulmaz ya da kaldırılmaz.' 'BrAccent2' 'kit:alt' 'Tara'
    Add-TlAction 'Firefox gizlilik ilkeleri' 'Telemetri, çalışmalar, sponsorlu kısayollar ve tanıtım iletileri Mozilla’nın belgelenmiş ilkeleriyle kapatılır. Yer imleri ve geçmiş değişmez; Geçmiş sayfasından geri alınır.' 'BrAccent2' 'kit:ffxPrev' 'Önizle' 'kit:ffx' 'Uygula'
    Add-HeadRow $ui.tl_List 'Günlük işler'
    Add-TlAction 'Parola üretici' 'Kriptografik rastgele sayı üretecinden güçlü parola üretir ve panoya kopyalar. Parola hiçbir yere kaydedilmez ve gönderilmez.' 'BrAccent' 'kit:pw' 'Aç'
    Add-TlAction 'Toplu yeniden adlandırma' 'Bir klasördeki dosyalara sıra numarası verir, metin değiştirir, tarih ekler. Önce önizleme gösterilir; Geçmiş sayfasından geri alınır.' 'BrAccent' 'kit:ren' 'Klasör seç'
    Add-HeadRow $ui.tl_List 'Destek'
    Add-TlAction 'Yardım paketi hazırla' 'Sorun bildirirken göndermek için: sürüm, sistem özeti ve son günlükler tek bir zip dosyasına konur. Kullanıcı adı, bilgisayar adı, IP ve MAC adresleri, e-posta adresleri silinir.' 'BrDim' 'kit:bundle' 'Hazırla'
    $ui.tl_Foot.Text = 'Bu sekmedeki araçlar internete veri göndermez. Sistemi değiştiren işlemler önce önizlenir ve geri alınabilir.'
}

# ---------------- parola uretici ----------------
function Get-KitPwDetail {
    $p = $script:KitPw
    $parts = New-Object System.Collections.ArrayList
    [void]$parts.Add((Tr 'küçük harf'))
    if ($p.Upper) { [void]$parts.Add((Tr 'büyük harf')) }
    if ($p.Digit) { [void]$parts.Add((Tr 'rakam')) }
    if ($p.Symbol) { [void]$parts.Add((Tr 'simge')) }
    $bits = Get-PasswordBits ([int]$p.Len) ([bool]$p.Upper) ([bool]$p.Digit) ([bool]$p.Symbol)
    return ((Format-Tr 'Uzunluk {0}' ([int]$p.Len)) + ' · ' + ($parts -join ', ') + ' · ' + (Format-Tr 'yaklaşık {0} bit' $bits) + ' (' + (Tr (Get-PasswordStrengthText $bits)) + '). ' + (Tr 'Karıştırılan karakterler (0 ve O, 1 ve l) kullanılmaz.'))
}

function Render-KitPw {
    Add-KitBack 'Parola üretici'
    $p = $script:KitPw
    Add-TlAction 'Parola üret' (Get-KitPwDetail) 'BrAccent' 'kit:pwgen' 'Üret ve kopyala' 'kit:pwlen' (Format-Tr 'Uzunluk: {0}' ([int]$p.Len))
    $sy = 'Simge: kapalı'; if ($p.Symbol) { $sy = 'Simge: açık' }
    $dg = 'Rakam: kapalı'; if ($p.Digit) { $dg = 'Rakam: açık' }
    Add-TlAction 'Karakter türleri' 'Bazı siteler simge kabul etmez; o durumda simgeyi kapatıp uzunluğu artırın.' 'BrDim' 'kit:pwsym' $sy 'kit:pwdig' $dg
    if ([string]$p.Value -ne '') {
        Add-HeadRow $ui.tl_List 'Son üretilen'
        Add-KvRow $ui.tl_List 'Parola' ([string]$p.Value)
        Add-Note $ui.tl_List 'Parola panoya kopyalandı; pano 60 saniye sonra temizlenir. Bu ekrandan ayrıldığınızda parola bellekten silinir.'
    }
    $ui.tl_Foot.Text = 'Parolalar kaydedilmez. Saklamak için bir parola yöneticisi (KeePassXC, Bitwarden) kullanın.'
}

function Clear-KitPw {
    $script:KitPw.Value = ''
    try { if ($null -ne $script:KitPwTimer) { $script:KitPwTimer.Stop() } } catch { }
}

function Invoke-KitPwGen {
    $p = $script:KitPw
    $x = Import-MmExt 'Parola'
    if ($x.Ok -ne $true) { Show-Toast ([string]$x.Error) 'bad'; return }
    $v = New-RandomPassword ([int]$p.Len) (Get-PasswordSets ([bool]$p.Upper) ([bool]$p.Digit) ([bool]$p.Symbol))
    $script:KitPw.Value = $v
    if (Set-ClipText $v) { Show-Toast 'Parola üretildi ve panoya kopyalandı.' 'good' } else { Show-Toast 'Parola üretildi; panoya kopyalanamadı.' 'warn' }
    try {
        if ($null -eq $script:KitPwTimer) {
            $script:KitPwTimer = New-Object System.Windows.Threading.DispatcherTimer
            $script:KitPwTimer.Interval = [TimeSpan]::FromSeconds(60)
            $script:KitPwTimer.Add_Tick({
                try {
                    $script:KitPwTimer.Stop()
                    $cur = ''
                    try { $cur = [string][System.Windows.Clipboard]::GetText() } catch { $cur = '' }
                    if ([string]$script:KitPw.Value -ne '' -and $cur -ceq [string]$script:KitPw.Value) { try { [System.Windows.Clipboard]::Clear() } catch { } }
                } catch { Write-CrashLog ('KitPw: ' + $_.Exception.Message) }
            })
        }
        $script:KitPwTimer.Stop(); $script:KitPwTimer.Start()
    } catch { }
    Render-TlKit
}

# ---------------- toplu yeniden adlandirma ----------------
function Start-KitRenPick {
    $d = Select-Folder 'Dosyaları yeniden adlandırılacak klasörü seçin'
    if ($d -eq '') { return }
    $why = Test-RenameDirAllowed $d
    if ($why -ne '') { Show-Toast $why 'warn'; return }
    Start-KitRenScan $d
}

function Start-KitRenScan([string]$Dir) {
    [void](Start-Async 'RenScan' 'Job_RenameScan' @{ Dir = $Dir } {
        param($r)
        if ($null -eq $r -or $r.Ok -ne $true) {
            $m = 'Klasör okunamadı.'
            if ($null -ne $r -and [string]$r.Error -ne '') { $m = [string]$r.Error }
            Show-Toast $m 'warn'; return
        }
        $script:KitRen = @{ Dir = [string]$r.Dir; Items = @($r.Items); Mode = ''; Arg = ''; Plan = $null }
        Set-KitView 'ren'
    } 'Klasör okunuyor')
}

function Set-KitRenPlan([string]$Mode, [string]$Arg) {
    $names = @($script:KitRen.Items | ForEach-Object { [string]$_.Name })
    $pl = Get-RenamePlan $script:KitRen.Items $Mode $Arg $names
    if ([string]$pl.Error -ne '') { Show-Toast ([string]$pl.Error) 'warn'; return }
    $script:KitRen.Mode = $Mode; $script:KitRen.Arg = $Arg; $script:KitRen.Plan = $pl
    if ([int]$pl.Changes -eq 0) { Show-Toast 'Bu kuralla adı değişecek dosya yok.' 'info' }
    Render-TlKit
}

function Invoke-KitRenMode([string]$Mode) {
    if ($Mode -eq 'Number') {
        Show-Input 'Sıra numarası ver' 'Dosyalar “Ad 01, Ad 02, …” biçiminde adlandırılır (ada göre sırayla; uzantı korunur). Temel adı yazın:' 'Dosya' { param($v) Invoke-Safe { Set-KitRenPlan 'Number' ([string]$v) } 'Yeniden adlandırma' }
        return
    }
    if ($Mode -eq 'Replace') {
        Show-Input 'Metni değiştir' 'Biçim: eski=>yeni   (örnek: IMG_=>Tatil ). Metni silmek için sağ tarafı boş bırakın. Uzantı değişmez.' '' { param($v) Invoke-Safe { Set-KitRenPlan 'Replace' ([string]$v) } 'Yeniden adlandırma' }
        return
    }
    Set-KitRenPlan $Mode ''
}

function Render-KitRename {
    Add-KitBack 'Toplu yeniden adlandırma'
    $R = $script:KitRen
    if ([string]$R.Dir -eq '') {
        Add-TlAction 'Klasör seçin' 'Yalnızca seçtiğiniz klasördeki dosyalar ele alınır; alt klasörlere, gizli dosyalara ve sistem dosyalarına dokunulmaz.' 'BrAccent' 'kit:ren' 'Klasör seç'
        return
    }
    Add-KvRow $ui.tl_List 'Klasör' ([string]$R.Dir)
    Add-KvRow $ui.tl_List 'Dosya' ([string]@($R.Items).Count)
    Add-HeadRow $ui.tl_List 'Kural seçin'
    Add-TlAction 'Sıra numarası ver' 'Ad 01, Ad 02, … (fotoğraf ve belge dizileri için).' 'BrAccent' 'kit:renmode:Number' 'Seç'
    Add-TlAction 'Metni değiştir' 'Adın içindeki bir metni başka bir metinle değiştirir ya da siler.' 'BrAccent' 'kit:renmode:Replace' 'Seç'
    Add-TlAction 'Başına tarih ekle' 'Dosyanın son değişiklik tarihi adın başına yazılır: 2026-11-14 rapor.pdf' 'BrAccent' 'kit:renmode:DatePrefix' 'Seç'
    Add-TlAction 'Küçük harfe çevir / boşlukları tire yap' 'Web’e ya da başka sistemlere yüklenecek dosyalar için.' 'BrAccent' 'kit:renmode:Lower' 'Küçük harf' 'kit:renmode:Dash' 'Tire'
    $pl = $R.Plan
    if ($null -ne $pl -and [int]$pl.Changes -gt 0) {
        Add-HeadRow $ui.tl_List (Format-Tr 'Önizleme: {0} dosyanın adı değişecek' ([int]$pl.Changes))
        $k = 0
        foreach ($row in @($pl.Rows)) {
            $k++
            if ($k -gt 12) { break }
            $v = [string]$row.New
            if ([string]$row.Problem -ne '') { $v += '   ⚠ ' + (Tr ([string]$row.Problem)) }
            Add-KvRow $ui.tl_List ([string]$row.Old) $v
        }
        if ([int]$pl.Changes -gt 12) { Add-Note $ui.tl_List (Format-Tr '… ve {0} dosya daha.' ([int]$pl.Changes - 12)) }
        if ([int]$pl.Problems -gt 0) {
            Add-Note $ui.tl_List (Format-Tr '{0} dosyada ad çakışması ya da geçersiz ad var; bu kural uygulanamaz. Başka bir kural ya da temel ad seçin.' ([int]$pl.Problems)) 'bad'
        } else {
            Add-TlAction 'Uygula' 'Dosyalar yeniden adlandırılır. İşlem Geçmiş sayfasından tek tıkla geri alınır.' 'BrGood' 'kit:renapply' 'Yeniden adlandır'
        }
    }
    $ui.tl_Foot.Text = 'Dosya içerikleri değişmez; yalnızca adlar değişir.'
}

function Start-KitRenApply {
    $R = $script:KitRen
    $pl = $R.Plan
    if ($null -eq $pl -or [int]$pl.Changes -eq 0 -or [int]$pl.Problems -gt 0) { Show-Toast 'Uygulanacak bir önizleme yok.' 'info'; return }
    $pairs = @($pl.Rows | ForEach-Object { @{ Old = [string]$_.Old; New = [string]$_.New } })
    $script:PendingSteps = @(@{ Title = 'Toplu yeniden adlandırma'; Ops = @(@{ T = 'Rename'; Dir = [string]$R.Dir; Pairs = $pairs }) })
    Show-Confirm 'Toplu yeniden adlandırma' (Format-Tr '{0} dosyanın adı değişecek. İşlem Geçmiş sayfasından geri alınabilir.' $pairs.Count) 'Yeniden adlandır' {
        Start-PlanJob $script:PendingSteps 'Dosyalar yeniden adlandırılıyor' $false $false { Invoke-Safe { Start-KitRenScan ([string]$script:KitRen.Dir) } 'Yeniden adlandırma' }
    }
}

# ---------------- karne ----------------
function Start-KitScore {
    [void](Start-Async 'ScoreView' 'Job_ScoreView' @{} {
        param($r)
        if ($null -eq $r -or $r.Ok -ne $true) { Show-Toast 'Karne okunamadı.' 'warn'; return }
        $script:KitScore = $r
        Set-KitView 'score'
    } 'Karne hazırlanıyor')
}

function Render-KitScore {
    Add-KitBack 'Karne: önce ve sonra'
    $S = $script:KitScore
    if ($null -eq $S) { Add-Note $ui.tl_List 'Karne hazırlanıyor…'; return }
    $n = $S.Now
    Add-HeadRow $ui.tl_List 'Şu an'
    if ([int]$n.Svc -ge 0) { Add-KvRow $ui.tl_List 'Çalışan hizmet' ([string]$n.Svc) }
    if ([int]$n.Proc -ge 0) { Add-KvRow $ui.tl_List 'Çalışan işlem' ([string]$n.Proc) }
    if ([int]$n.FreeMb -ge 0) { Add-KvRow $ui.tl_List 'Boş bellek' ((Format-Size ([double]$n.FreeMb * 1MB))) }
    if ([double]$n.DiskFreeGb -ge 0) { Add-KvRow $ui.tl_List 'Sistem sürücüsünde boş alan' ([string]$n.DiskFreeGb + ' GB') }
    $boots = @($S.Boots)
    if ($boots.Count -gt 0) {
        $txt = @($boots | ForEach-Object { ([datetime]$_.Time).ToString('dd.MM') + ': ' + [string][int]([double]$_.BootMs / 1000) + ' sn' }) -join '  ·  '
        Add-KvRow $ui.tl_List 'Son açılış süreleri' $txt
    }
    $ent = @($S.Entries)
    $w = Get-ScoreSummary $ent 7 (Get-Date)
    $m = Get-ScoreSummary $ent 30 (Get-Date)
    Add-HeadRow $ui.tl_List 'Özet'
    Add-KvRow $ui.tl_List 'Son 7 gün' (Format-Tr '{0} işlem, {1} değişiklik · çalışan hizmet {2} · açılan alan {3} GB' ([int]$w.Count) ([int]$w.Changes) (Format-Signed $w.Svc) ([string]$w.DiskFreeGb))
    Add-KvRow $ui.tl_List 'Son 30 gün' (Format-Tr '{0} işlem, {1} değişiklik · çalışan hizmet {2} · açılan alan {3} GB' ([int]$m.Count) ([int]$m.Changes) (Format-Signed $m.Svc) ([string]$m.DiskFreeGb))
    $svc = @($S.Services)
    if ($svc.Count -gt 0) {
        Add-HeadRow $ui.tl_List 'En çok bellek tutan hizmetler (kendi işleminde çalışanlar)'
        foreach ($x in $svc) { Add-KvRow $ui.tl_List (Limit-Text ([string]$x.Display) 60) ((Format-Tr 'yaklaşık {0} MB' ([int]$x.Mb)) + '  ·  ' + [string]$x.Name) }
        Add-Note $ui.tl_List 'Bir hizmeti kapatmadan önce Hizmetler sayfasındaki açıklamasını okuyun; bellek tutması gereksiz olduğu anlamına gelmez.'
    }
    Add-HeadRow $ui.tl_List 'İşlem geçmişi (önce → sonra)'
    if ($ent.Count -eq 0) {
        Add-Note $ui.tl_List 'Henüz kayıt yok. İyileştir, Temizlik ya da Hizmetler sayfasından bir işlem uyguladığınızda önce ve sonra ölçümü burada görünür.'
    } else {
        $k = 0
        foreach ($e in $ent) {
            $k++
            if ($k -gt 15) { break }
            $when = ''
            try { $when = ([datetime]::Parse([string]$e.B.Time, [System.Globalization.CultureInfo]::InvariantCulture)).ToString('dd.MM HH:mm') } catch { }
            Add-KvRow $ui.tl_List ($when + '  ' + (Limit-Text ([string]$e.Label) 40)) (Format-ScoreLine $e.A $e.B)
        }
    }
    $ui.tl_Foot.Text = 'Ölçümler işlem anındaki anlık değerlerdir; açık programlara göre birkaç birim oynayabilir. Kayıt yalnızca bu bilgisayarda tutulur.'
}

# ---------------- internete baglanan programlar ----------------
function Start-KitNet {
    [void](Start-Async 'NetTalk' 'Job_NetTalkers' @{} {
        param($r)
        if ($null -eq $r -or $r.Ok -ne $true) { Show-Toast 'Bağlantılar okunamadı.' 'warn'; return }
        $script:KitNet = $r
        Set-KitView 'net'
    } 'Bağlantılar okunuyor')
}

function Render-KitNet {
    Add-KitBack 'Hangi program internete bağlanıyor?'
    $S = $script:KitNet
    if ($null -eq $S) { Add-Note $ui.tl_List 'Bağlantılar okunuyor…'; return }
    $rows = @($S.Rows)
    Add-TlAction (Format-Tr '{0} programın internet bağlantısı açık' $rows.Count) (Format-Tr 'Okundu: {0}. Yerel ağ ve bilgisayarın kendi içindeki bağlantılar sayılmaz.' ([string]$S.At)) 'BrDim' 'kit:net' 'Yenile'
    $i = -1
    foreach ($r in $rows) {
        $i++
        $d = (Format-Tr '{0} bağlantı, {1} farklı adres' ([int]$r.Count) ([int]$r.Hosts)) + ' (' + [string]$r.Sample + ')'
        if ([string]$r.Ports -ne '') { $d += ' · ' + (Tr 'bağlantı noktası') + ' ' + [string]$r.Ports }
        if ([string]$r.Path -ne '') { $d += '  ·  ' + (Limit-Text ([string]$r.Path) 90) }
        if ($r.Blocked -eq $true) { Add-TlAction ([string]$r.Name) ($d + '  ·  ' + (Tr 'İnterneti kesildi (açık bağlantılar kapanana kadar listede kalabilir).')) 'BrWarn' ('kit:netopen:' + [string]$i) 'Engeli kaldır' }
        elseif ($r.CanBlock -eq $true) { Add-TlAction ([string]$r.Name) $d 'BrAccent2' ('kit:netblock:' + [string]$i) 'İnterneti kes' }
        else { Add-TlAction ([string]$r.Name) ($d + '  ·  ' + (Tr ([string]$r.Why))) 'BrDim' 'kit:none' '' }
    }
    $ui.tl_Foot.Text = 'Engel, Windows Güvenlik Duvarı’na giden yönde bir kural olarak eklenir; Ağ > Koruma sekmesinden ve Geçmiş sayfasından kaldırılabilir.'
}

function Start-KitNetRule([int]$Index, [bool]$On) {
    $rows = @($script:KitNet.Rows)
    if ($Index -lt 0 -or $Index -ge $rows.Count) { return }
    $r = $rows[$Index]
    $t = 'İnterneti kes: ' + [string]$r.Name
    if (-not $On) { $t = 'İnternet engelini kaldır: ' + [string]$r.Name }
    $script:PendingSteps = @(@{ Title = $t; Ops = @(@{ T = 'FwApp'; Program = [string]$r.Path; On = $On }) })
    if (-not $On) { Start-PlanJob $script:PendingSteps $t $false $false { Invoke-Safe { Start-KitNet } 'Bağlantılar' }; return }
    Show-Confirm 'İnterneti kes' (Format-Tr '{0} programının internete çıkışı Windows Güvenlik Duvarı kuralıyla engellenecek. Program çalışmaya devam eder ama internete bağlanamaz. İstediğiniz zaman kaldırabilirsiniz.' ([string]$r.Name)) 'İnterneti kes' {
        Start-PlanJob $script:PendingSteps ([string]$script:PendingSteps[0].Title) $false $false { Invoke-Safe { Start-KitNet } 'Bağlantılar' }
    } $true
}

# ---------------- acik kaynak alternatifleri ----------------
function Start-KitAlt {
    [void](Start-Async 'AltScan' 'Job_AltScan' @{} {
        param($r)
        if ($null -eq $r -or $r.Ok -ne $true) { Show-Toast 'Kurulu programlar okunamadı.' 'warn'; return }
        $script:KitAlt = $r
        Set-KitView 'alt'
    } 'Kurulu programlar okunuyor')
}

function Render-KitAlt {
    Add-KitBack 'Açık kaynak alternatifleri'
    $S = $script:KitAlt
    if ($null -eq $S) { Add-Note $ui.tl_List 'Kurulu programlar okunuyor…'; return }
    $rows = @($S.Rows)
    if ($rows.Count -eq 0) {
        Add-Note $ui.tl_List (Format-Tr '{0} kurulu program incelendi; açık kaynak karşılığı önerilecek bir program bulunmadı.' ([int]$S.Count))
    } else {
        Add-Note $ui.tl_List (Format-Tr '{0} kurulu program incelendi. Aşağıdakilerin açık kaynak karşılığı var. Kurulum winget deposundan, imza ve özet doğrulamasıyla yapılır; eski program kaldırılmaz, kararı siz verirsiniz.' ([int]$S.Count))
        $i = -1
        foreach ($r in $rows) {
            $i++
            $lic = Get-FossLicenseText ([string]$r.Id)
            Add-TlAction ((Limit-Text ([string]$r.Have) 50) + '  →  ' + [string]$r.Name) ((Tr ([string]$r.Why)) + '.  ' + (Tr $lic)) 'BrAccent2' ('kit:altinst:' + [string]$i) 'Kur'
        }
    }
    Add-TlAction 'Bütün açık kaynak araçlar' 'Uygulamalar > Ücretsiz araçlar listesinde lisans bilgisi ve “yalnızca açık kaynak” süzgeci bulunur.' 'BrDim' 'kit:altall' 'Listeyi aç'
    $ui.tl_Foot.Text = 'Öneriler bu uygulamanın içindeki sabit bir tablodan gelir; kurulu program listeniz hiçbir yere gönderilmez.'
}

function Start-KitAltInstall([int]$Index) {
    $rows = @($script:KitAlt.Rows)
    if ($Index -lt 0 -or $Index -ge $rows.Count) { return }
    $script:KitPending = $rows[$Index]
    Show-Confirm 'Program kur' (Format-Tr '{0} winget deposundan kurulacak ({1}). Mevcut programınız kaldırılmaz.' ([string]$script:KitPending.Name) ([string]$script:KitPending.Id)) 'Kur' {
        $t = $script:KitPending
        [void](Start-Async 'Foss' 'Job_WingetInstall' @{ Id = [string]$t.Id } {
            param($r)
            if ($null -ne $r -and $r.Ok -eq $true) { Show-Toast 'Kurulum tamamlandı.' 'good'; Invoke-Safe { Start-KitAlt } 'Alternatifler' }
            else { Show-Toast 'Kurulum başarısız; ayrıntı günlükte.' 'bad' }
        } ('Kuruluyor: ' + [string]$t.Name) $false $true)
    }
}

# ---------------- yeni bilgisayar adimlari ----------------
function Render-KitSetup {
    Add-KitBack 'Yeni bilgisayar / format sonrası adımları'
    $st = @{ Applied = @($script:Settings.AppliedIds).Count; BackupDest = [string]$script:Settings.BackupDest; UseCase = [string]$script:Settings.UseCase; PrepSeen = [string]$script:Settings.PrepSeen; AppVersion = [string]$script:AppVersion }
    Add-Note $ui.tl_List 'Adımları sırayla izleyin. Her adım ilgili sayfayı açar; işlem orada önizlenir ve onayınızla uygulanır. Eski bilgisayarınızdan ayar taşıyacaksanız önce Yedekleme > Taşınma kiti sekmesinden içe aktarın.'
    foreach ($s in @(Get-SetupSteps $st)) {
        $br = 'BrAccent'; $ttl = [string]$s.Title
        if ($s.Done -eq $true) { $br = 'BrGood'; $ttl = $ttl + '  ✓' }
        Add-TlAction $ttl ([string]$s.Detail) $br ('kit:go:' + [string]$s.Page + ':' + [string]$s.Tab) ([string]$s.Btn)
    }
    Add-TlAction 'Taşınma kiti' 'Eski bilgisayardan dışa aktardığınız ayarları, program listesini ve sürücü yedeğini bu bilgisayara getirir.' 'BrDim' 'kit:go:backup:kit' 'Taşınma kiti'
    $ui.tl_Foot.Text = '✓ işareti, adımın bu bilgisayarda daha önce yapıldığını gösterir.'
}

# ---------------- Firefox ilkeleri ----------------
function Start-KitFirefox([bool]$Preview) {
    $steps = New-StepsFromIds $script:FirefoxTweakIds
    $steps = @($steps)
    if ($steps.Count -eq 0) { Show-Toast 'Firefox ilkeleri bulunamadı.' 'warn'; return }
    $script:PendingSteps = $steps
    if ($Preview) { Start-PlanJob $script:PendingSteps 'Önizleme: Firefox gizlilik ilkeleri' $true $false; return }
    $note = ''
    if (-not (Test-FirefoxInstalled)) { $note = ' ' + (Tr 'Firefox bu bilgisayarda kurulu görünmüyor; ilkeler şimdi yazılır ve Firefox kurulduğunda geçerli olur.') }
    Show-Confirm 'Firefox gizlilik ilkeleri' ((Tr 'Firefox’un telemetrisi, çalışmaları, sponsorlu içerikleri ve tanıtım iletileri ilkeyle kapatılacak. Firefox ayarlarında “kuruluşunuz tarafından yönetiliyor” yazısı görünür. Geçmiş sayfasından geri alabilirsiniz.') + $note) 'Uygula' {
        Start-PlanJob $script:PendingSteps 'Firefox gizlilik ilkeleri uygulanıyor' $false $false
    }
}

# ---------------- yardim paketi ----------------
function Start-KitBundle {
    $dest = [Environment]::GetFolderPath('Desktop')
    [void](Start-Async 'Bundle' 'Job_SupportBundle' @{ Dest = $dest } {
        param($r)
        if ($null -eq $r -or $r.Ok -ne $true) {
            $m = 'Yardım paketi hazırlanamadı.'
            if ($null -ne $r -and [string]$r.Error -ne '') { $m += ' ' + [string]$r.Error }
            Show-Toast $m 'bad'; return
        }
        Show-Toast (Format-Tr 'Yardım paketi masaüstüne yazıldı: {0}' ([System.IO.Path]::GetFileName([string]$r.Path))) 'good'
        try { Open-Folder ([System.IO.Path]::GetDirectoryName([string]$r.Path)) } catch { }
    } 'Yardım paketi hazırlanıyor')
}

# ---------------- dugme dagitici (H_TlFileAct'in tanimadigi anahtarlar buraya duser) ----------------
function Invoke-TlExtraAct([string]$Key) {
    if (-not $Key.StartsWith('kit:')) { return }
    $p = $Key.Split(':')
    switch ([string]$p[1]) {
        'home' { Clear-KitPw; Set-KitView 'home' }
        'setup' { Set-KitView 'setup' }
        'score' { Start-KitScore }
        'net' { Start-KitNet }
        'netblock' { Start-KitNetRule ([int]$p[2]) $true }
        'netopen' { Start-KitNetRule ([int]$p[2]) $false }
        'alt' { Start-KitAlt }
        'altinst' { Start-KitAltInstall ([int]$p[2]) }
        'altall' { Open-Page 'apps' 'foss' }
        'ffxPrev' { Start-KitFirefox $true }
        'ffx' { Start-KitFirefox $false }
        'pw' { Set-KitView 'pw' }
        'pwgen' { Invoke-KitPwGen }
        'pwlen' { $script:KitPw.Len = Get-NextPwLength ([int]$script:KitPw.Len); Render-TlKit }
        'pwsym' { $script:KitPw.Symbol = (-not [bool]$script:KitPw.Symbol); Render-TlKit }
        'pwdig' { $script:KitPw.Digit = (-not [bool]$script:KitPw.Digit); Render-TlKit }
        'ren' { Start-KitRenPick }
        'renmode' { Invoke-KitRenMode ([string]$p[2]) }
        'renapply' { Start-KitRenApply }
        'bundle' { Start-KitBundle }
        'go' { $sub = ''; if ($p.Count -gt 3) { $sub = [string]$p[3] }; Open-Page ([string]$p[2]) $sub }
    }
}

# ---------------- Ucretsiz araclar listesi: lisans eki ve "yalnizca acik kaynak" suzgeci ----------------
function Get-FossDetail($Tool) {
    $d = [string]$Tool.D
    $l = Get-FossLicenseText ([string]$Tool.Id)
    if ($l -ne '') { $d = (Tr $d) + '  ·  ' + (Tr $l) }
    return $d
}

function Add-FossFilterRow {
    $on = ($script:Settings.FossOpenOnly -eq $true)
    $btn = 'Yalnızca açık kaynak: kapalı'
    if ($on) { $btn = 'Yalnızca açık kaynak: açık' }
    $row = New-ItemRow @{ Title = 'Lisans süzgeci'; Detail = 'Açıkken kaynak kodu yayımlanmayan (kapalı kaynaklı) ücretsiz araçlar listede gösterilmez. Her aracın lisansı açıklamasının sonunda yazar.'; BrCol = 'BrDim'; Btn1 = $btn } @{ Id = ''; Name = ''; Search = 'lisans acik kaynak suzgec' } $false $false
    $row.FindName('Act').Add_Click({
        Invoke-Safe {
            Set-SettingsKeys @{ FossOpenOnly = (-not ($script:Settings.FossOpenOnly -eq $true)) }
            Render-ApFoss
        } 'Süzgeç'
    })
    [void]$ui.ap_List.Children.Add($row)
}

# ---------------- Yedekleme > BitLocker: sifrelemeyi acma ----------------
function Get-BlOnLabel { return 'Şifrelemeyi aç' }

$script:H_BkBlOn = {
    param($s, $e)
    Invoke-Safe { Start-BlEnable ([string]$s.Tag.Drive) } 'Şifreleme'
}

function Show-BlAlternatives {
    Show-Message 'Disk şifreleme' 'Bu sürücü Windows’un kendi şifrelemesiyle uygulama içinden şifrelenemiyor (Windows Home’da yalnızca sistem sürücüsü, “Cihaz şifrelemesi” ile şifrelenir). İki seçeneğiniz var: Araçlar > Dosya araçları > “Dosya şifrele (AES-256)” ile tek tek dosyaları parolayla şifreleyebilir ya da Araçlar > Dış araçlar sekmesinden açık kaynaklı VeraCrypt’i kurup bütün bir sürücüyü ya da USB belleği şifreleyebilirsiniz.'
}

function Start-BlEnable([string]$Drive) {
    $route = Get-BlEnableRoute $Drive ([string]$env:SystemDrive) (Test-HomeEdition)
    if ($route -eq 'Settings') {
        Open-Url 'ms-settings:deviceencryption'
        Show-Toast 'Windows Home’da sistem sürücüsü Ayarlar > Cihaz şifrelemesi sayfasından şifrelenir; sayfa açıldı. Seçenek görünmüyorsa bilgisayar bunu desteklemiyordur: dosyalarınız için Araçlar > Dosya araçları > Dosya şifrele bölümünü kullanın.' 'info'
        return
    }
    if ($route -eq 'Panel') {
        try { Start-Process -FilePath (Join-Path (Join-Path $env:WINDIR 'System32') 'control.exe') -ArgumentList '/name Microsoft.BitLockerDriveEncryption' -ErrorAction Stop | Out-Null; Show-Toast 'Ek sürücüler için parola seçimi gerekir; Windows’un BitLocker penceresi açıldı.' 'info' }
        catch { Show-BlAlternatives }
        return
    }
    if ($route -ne 'Enable') { Show-BlAlternatives; return }
    $script:PendingDrive = $Drive
    Show-Confirm 'BitLocker’ı aç' (Format-Tr '{0} sürücüsü BitLocker ile şifrelenecek (TPM ve 48 haneli kurtarma anahtarı). Windows önce bir donanım sınaması ister; şifreleme bilgisayarı yeniden başlattıktan sonra arka planda başlar ve çalışmanızı engellemez. İşlem bitince kurtarma anahtarını mutlaka bilgisayarın DIŞINDA bir yere kaydedin: anahtar olmadan, donanım değişikliğinden sonra dosyalarınıza erişemezsiniz.' $Drive) 'Şifrelemeyi aç' {
        [void](Start-Async 'BlOn' 'Job_BitLockerEnable' @{ Drive = $script:PendingDrive } {
            param($r)
            $script:BkBl = $null
            if ($script:BkTab -eq 'bl') { Render-BkBl }
            if ($null -eq $r -or $r.Ok -ne $true) {
                $m = 'BitLocker açılamadı.'
                if ($null -ne $r -and [string]$r.Error -ne '') { $m = [string]$r.Error }
                Show-Toast $m 'bad'; return
            }
            if ($r.Verified -eq $true) { Show-Toast 'BitLocker başlatıldı. Şimdi “Anahtarı göster” ya da “Dosyaya kaydet” ile kurtarma anahtarını bilgisayarın dışında bir yere kaydedin; ardından bilgisayarı yeniden başlatın.' 'good' }
            else { Show-Toast 'Windows komutu kabul etti ama kurtarma anahtarı doğrulanamadı; listeyi yenileyip durumu denetleyin.' 'warn' }
        } 'BitLocker açılıyor')
    } $true
}

# BitLocker bilgisi okunamadiginda (Windows Home): yine de yapilabilecekler
function Add-BlHomeRows {
    $row = New-ItemRow @{ Title = 'Cihaz şifrelemesi (Windows Ayarları)'; Detail = 'Windows Home’da sistem sürücüsü bu sayfadan şifrelenir. Seçenek yoksa bilgisayar desteklemiyordur.'; BrCol = 'BrAccent'; Btn1 = 'Ayarları aç' } @{ Drive = [string]$env:SystemDrive } $false $false
    $row.FindName('Act').Add_Click({ Invoke-Safe { Open-Url 'ms-settings:deviceencryption' } 'Şifreleme' })
    [void]$ui.bk_List.Children.Add($row)
    $row2 = New-ItemRow @{ Title = 'Dosya ve sürücü şifreleme seçenekleri'; Detail = 'Tek tek dosyalar için uygulamanın AES-256 şifrelemesi; bütün bir sürücü ya da USB bellek için açık kaynaklı VeraCrypt.'; BrCol = 'BrDim'; Btn1 = 'Dosya şifrele'; Btn2 = 'VeraCrypt' } @{ Drive = '' } $false $false
    $row2.FindName('Act').Add_Click({ Invoke-Safe { Open-Page 'tools' 'files' } 'Şifreleme' })
    $row2.FindName('Act2').Add_Click({ Invoke-Safe { Open-Page 'apps' 'foss' } 'Şifreleme' })
    [void]$ui.bk_List.Children.Add($row2)
}

# ==================================================================
#  ARACLAR SAYFASI KULLANICI KIPINDE: Yardimcilar, Dis araclar ve Onarim gundelik islerdir; kullanici kipinde de gorunur.
#  Uzmanlik isteyen sekmeler (Windows araclari, Islemler, Dosya araclari, Sistem) yalnizca uzman kipinde gorunur;
#  arama ya da Asistan boyle bir sekmeye gotururse uygulama sessizce uzman kipine gecer.
# ==================================================================
$script:TlUserTabs = @('kit', 'ext', 'repair')

# Saf: kipe gore gorunen sekmeler (XAML sirasiyla)
function Get-TlVisibleTabs([bool]$Expert) {
    if ($Expert) { return @($script:TlTabs) }
    return @($script:TlTabs | Where-Object { $script:TlUserTabs -contains [string]$_ })
}

# Saf: sayfa acilirken secilecek sekme. Kullanici kipinde gizli bir sekme seciliyse Yardimcilar'a doner.
function Get-TlStartTab([bool]$Expert, [string]$Current) {
    if ($Expert) { if (@($script:TlTabs) -contains $Current) { return $Current }; return 'win' }
    if (@($script:TlUserTabs) -contains $Current) { return $Current }
    return 'kit'
}

# Saf: bu sekme icin uzman kipine gecmek gerekir mi?
function Test-TlNeedsExpert([string]$Tab, [bool]$Expert) {
    if ($Expert) { return $false }
    return ((@($script:TlTabs) -contains $Tab) -and (@($script:TlUserTabs) -notcontains $Tab))
}

function Update-PageMode_tools {
    $exp = ($script:UiState.Mode -eq 'Expert')
    $vis = @(Get-TlVisibleTabs $exp)
    foreach ($t in @($script:TlTabs)) {
        $c = $ui['tl_Tab_' + [string]$t]
        if ($null -ne $c) { Set-Visible $c ($vis -contains [string]$t) }
    }
    if ($vis -notcontains [string]$script:TlTab) {
        if (-not (Select-TabChip 'tl' 'kit')) { Set-TlTab 'kit' }
    }
}
