# ==================================================================
#  ÇÖZÜM MERKEZİ: bulur ve düzeltir. Sekmeler, eylem dili, belirtiye göre sorun gidericiler ve onların işlemleri.
#  Her düzeltme önce önizlenir, onaydan sonra uygulanır, günlüğe yazılır; geri alınabilenler Geçmiş sayfasından geri alınır.
# ==================================================================
$script:SlvTabs = @('scan', 'disk', 'recover', 'erase', 'trouble', 'pc', 'prep')

# Başka bir yerden (bulgu, öneri) Çözüm Merkezi’nin bir sekmesine gitmek için eylem
function New-SolveAction([string]$Sub, [string]$Arg, [string]$Label) {
    return @{ Kind = 'Page'; Page = 'solve'; Sub = $Sub; Arg = $Arg; Label = $Label }
}

# ---------------- belirtiye göre sorun gidericiler ----------------
# K: anahtar; T: başlık; D: ne yaptığı ve yan etkisi; Steps: plan adımları (FuncOp adları); Reboot: yeniden başlatma gerekir mi; Guided: ilgili sayfaya yönlendirmeler
$script:SlvSymptoms = @(
    @{ K = 'net'; T = 'İnternete bağlanamıyorum ya da bağlantı çok yavaş'
       D = 'DNS önbelleğini temizler, IP adresini yeniler ve ağ yığınını (Winsock, TCP/IP) sıfırlar. Bağlantı birkaç saniye kesilir; yığın sıfırlaması için yeniden başlatmak gerekir.'
       Steps = @(@{ Id = 'sv-dns'; Title = 'DNS önbelleğini temizle'; Fn = 'FlushDns' }, @{ Id = 'sv-ip'; Title = 'IP adresini yenile'; Fn = 'RenewIp' }, @{ Id = 'sv-stack'; Title = 'Ağ yığınını sıfırla'; Fn = 'NetStackReset' })
       Reboot = $true; Guided = @(@{ Label = 'Ağ araçları'; Page = 'network'; Sub = '' }) },
    @{ K = 'time'; T = 'Saat yanlış ya da siteler “bağlantınız gizli değil” diyor'
       D = 'Windows Saat hizmetini başlatır ve saati zaman sunucusuyla eşitler. Yanlış saat, güvenli sitelerin sertifika hatası vermesinin sık nedenidir.'
       Steps = @(@{ Id = 'sv-time'; Title = 'Saati eşitle'; Fn = 'TimeSync' }); Reboot = $false; Guided = @() },
    @{ K = 'audio'; T = 'Ses gelmiyor ya da ses aygıtı görünmüyor'
       D = 'Windows Ses ve Ses Uç Noktası Oluşturucu hizmetlerini yeniden başlatır. Çalan sesler bir an kesilir.'
       Steps = @(@{ Id = 'sv-audio'; Title = 'Ses hizmetlerini yeniden başlat'; Fn = 'RestartAudio' }); Reboot = $false; Guided = @(@{ Label = 'Windows ses ayarları'; Page = ''; Url = 'ms-settings:sound' }) },
    @{ K = 'print'; T = 'Yazıcı kuyruğu takıldı, belge yazdırılmıyor'
       D = 'Yazdırma Biriktiricisi’ni durdurur, bekleyen (takılmış) yazdırma işlerini siler ve hizmeti yeniden başlatır. Kuyruktaki belgeler yazdırılmaz; yeniden göndermeniz gerekir.'
       Steps = @(@{ Id = 'sv-spool'; Title = 'Yazdırma kuyruğunu temizle'; Fn = 'ClearSpooler' }); Reboot = $false; Guided = @() },
    @{ K = 'wu'; T = 'Windows Update takıldı ya da hata veriyor'
       D = 'Güncelleme hizmetlerini durdurur, güncelleme önbelleğini (SoftwareDistribution, catroot2) yedek adıyla kenara alır ve hizmetleri yeniden başlatır. Windows önbelleği kendisi yeniden kurar; ilk denetim her zamankinden uzun sürebilir.'
       Steps = @(@{ Id = 'sv-wu'; Title = 'Windows Update bileşenlerini sıfırla'; Fn = 'ResetWuComponents' }); Reboot = $false; Guided = @(@{ Label = 'Güncellemeler sayfası'; Page = 'updates'; Sub = '' }) },
    @{ K = 'shell'; T = 'Görev çubuğu, Başlat menüsü ya da masaüstü donuyor; simgeler bozuk'
       D = 'Windows Gezgini’ni yeniden başlatır ve simge önbelleğini yeniden oluşturur. Masaüstü ve görev çubuğu bir an kaybolup geri gelir.'
       Steps = @(@{ Id = 'sv-icons'; Title = 'Simge önbelleğini yeniden oluştur'; Fn = 'RebuildIconCache' }); Reboot = $false; Guided = @() },
    @{ K = 'slow'; T = 'Bilgisayar yavaşladı'
       D = 'Geçici dosyaları, güncelleme önbelleğini ve hata raporlarını temizler; sürücüyü türüne göre iyileştirir (SSD için TRIM, HDD için birleştirme). Kişisel dosyalara dokunmaz.'
       Steps = @(@{ Id = 'sv-temp'; Title = 'Geçici dosyaları temizle'; Fn = 'CleanTemp' }, @{ Id = 'sv-wer'; Title = 'Hata raporlarını temizle'; Fn = 'CleanWer' }, @{ Id = 'sv-opt'; Title = 'Sürücüyü iyileştir'; Fn = 'OptimizeDrive' })
       Reboot = $false; Guided = @(@{ Label = 'Başlangıçta açılan programlar'; Page = 'startup'; Sub = '' }, @{ Label = 'Hızlandırma ayarları'; Page = 'optimize'; Sub = '' }) },
    @{ K = 'full'; T = 'Disk dolmak üzere'
       D = 'Güvenle silinebilen geçici dosyaları, Windows Update indirme önbelleğini ve çökme dökümlerini temizler. Kişisel dosyalara, indirilenlere ve Geri Dönüşüm Kutusu’na dokunmaz.'
       Steps = @(@{ Id = 'sv-temp2'; Title = 'Geçici dosyaları temizle'; Fn = 'CleanTemp' }, @{ Id = 'sv-wuc'; Title = 'Güncelleme önbelleğini temizle'; Fn = 'CleanUpdateCache' }, @{ Id = 'sv-dump'; Title = 'Çökme dökümlerini temizle'; Fn = 'CleanDumps' })
       Reboot = $false; Guided = @(@{ Label = 'En büyük dosyalar ve kopyalar'; Page = 'clean'; Sub = 'big' }) },
    @{ K = 'bsod'; T = 'Mavi ekran alıyorum ya da bilgisayar kendiliğinden yeniden başlıyor'
       D = 'Önce Windows’un kendi kayıtlarındaki hata kodlarına bakılır; nedene göre ne yapılacağı Sorunlar sekmesinde yazar. Sistem dosyalarını denetlemek için Araçlar > Onarım kullanılır.'
       Steps = @(); Reboot = $false; Guided = @(@{ Label = 'Bilgisayarı tara'; Page = 'solve'; Sub = 'scan' }, @{ Label = 'Sistem dosyası onarımı'; Page = 'tools'; Sub = '' }) }
)

# Sorun gidericinin plan adımları. Dönüş: @(@{ Id; Title; Ops; Reboot })
function Get-SlvTroubleSteps([string]$Key) {
    $out = New-Object System.Collections.ArrayList
    foreach ($s in $script:SlvSymptoms) {
        if ([string]$s.K -ne $Key) { continue }
        $n = @($s.Steps).Count
        $i = 0
        foreach ($st in @($s.Steps)) {
            $i++
            $rb = ($s.Reboot -eq $true -and $i -eq $n)
            [void]$out.Add(@{ Id = [string]$st.Id; Title = [string]$st.Title; Ops = @((FuncOp ([string]$st.Fn))); Reboot = $rb })
        }
    }
    return , $out.ToArray()
}

function Get-SlvSymptom([string]$Key) {
    foreach ($s in $script:SlvSymptoms) { if ([string]$s.K -eq $Key) { return $s } }
    return $null
}

# ---------------- sorun giderici işlemleri (önizleme destekli, FuncOp olarak kayıtlı) ----------------
function Stop-SlvService([string]$Name) {
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if ($null -eq $svc) { return $false }
    if ($svc.Status -ne 'Stopped') { Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue }
    for ($i = 0; $i -lt 20; $i++) {
        $svc.Refresh()
        if ($svc.Status -eq 'Stopped') { return $true }
        Start-Sleep -Milliseconds 500
    }
    return $false
}

function Invoke-RenewIpOp {
    if ($script:Preview) { Add-Plan 'IP adresi bırakılıp yeniden alınacak (bağlantı birkaç saniye kesilir)'; return }
    & ipconfig.exe /release 2>&1 | Out-Null
    Start-Sleep -Seconds 2
    & ipconfig.exe /renew 2>&1 | Out-Null
    Add-Done 'IP adresi yenilendi'
}

function Invoke-NetStackResetOp {
    if ($script:Preview) { Add-Plan 'Winsock ve TCP/IP yığını sıfırlanacak (etkili olması için yeniden başlatma gerekir)'; return }
    & netsh.exe winsock reset 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw ('Winsock sıfırlanamadı (çıkış kodu ' + [string]$LASTEXITCODE + ')') }
    & netsh.exe int ip reset 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { Add-Skip 'TCP/IP sıfırlaması kısmen tamamlandı (bazı kayıt anahtarları Windows tarafından korunuyor)' }
    Add-Done 'Winsock ve TCP/IP yığını sıfırlandı; yeniden başlatınca etkili olur'
}

function Invoke-RestartAudioOp {
    if ($script:Preview) { Add-Plan 'Ses hizmetleri (AudioEndpointBuilder, Audiosrv) yeniden başlatılacak'; return }
    $names = @('AudioEndpointBuilder', 'Audiosrv')
    foreach ($n in $names) {
        $svc = Get-Service -Name $n -ErrorAction SilentlyContinue
        if ($null -eq $svc) { Add-Skip ('Hizmet yok: ' + $n); continue }
        Restart-Service -Name $n -Force -ErrorAction Stop
    }
    foreach ($n in $names) {
        $svc = Get-Service -Name $n -ErrorAction SilentlyContinue
        if ($null -ne $svc -and [string]$svc.Status -ne 'Running') { Start-Service -Name $n -ErrorAction Stop }
    }
    Add-Done 'Ses hizmetleri yeniden başlatıldı'
}

function Invoke-ClearSpoolerOp {
    $dir = Join-Path (Join-Path (Join-Path ([string]$env:WINDIR) 'System32') 'spool') 'PRINTERS'
    if ($script:Preview) { Add-Plan ('Yazdırma Biriktiricisi durdurulacak, ' + $dir + ' içindeki bekleyen işler silinecek, hizmet yeniden başlatılacak'); return }
    $stopped = Stop-SlvService 'Spooler'
    $n = 0
    if (Test-Path -LiteralPath $dir -PathType Container) {
        foreach ($f in @(Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue)) {
            try { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop; $n++ } catch { }
        }
    }
    Start-Service -Name 'Spooler' -ErrorAction SilentlyContinue
    if (-not $stopped) { Add-Skip 'Yazdırma Biriktiricisi tam durmadı; bekleyen işler silinemeyebilir' }
    Add-Done ('Yazdırma kuyruğu temizlendi (' + [string]$n + ' bekleyen iş silindi)')
}

function Invoke-ResetWuComponentsOp {
    $win = [string]$env:WINDIR
    $sd = Join-Path $win 'SoftwareDistribution'
    $cr = Join-Path (Join-Path $win 'System32') 'catroot2'
    if ($script:Preview) { Add-Plan 'Güncelleme hizmetleri durdurulacak; SoftwareDistribution ve catroot2 klasörleri “.bak” adıyla kenara alınacak; hizmetler yeniden başlatılacak'; return }
    $svcs = @('wuauserv', 'bits', 'cryptsvc', 'msiserver')
    foreach ($n in $svcs) { [void](Stop-SlvService $n) }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $moved = 0
    try {
        foreach ($d in @($sd, $cr)) {
            if (Test-Path -LiteralPath $d -PathType Container) {
                Rename-Item -LiteralPath $d -NewName ((Split-Path -Leaf $d) + '.bak-' + $stamp) -ErrorAction Stop
                $moved++
            }
        }
    } finally {
        foreach ($n in $svcs) { Start-Service -Name $n -ErrorAction SilentlyContinue }
    }
    Add-Done ('Windows Update bileşenleri sıfırlandı (' + [string]$moved + ' klasör yedeklendi; bir sorun kalmazsa “.bak” klasörlerini silebilirsiniz)')
}

function Get-IconCacheFiles {
    $la = [string]$env:LOCALAPPDATA
    $list = New-Object System.Collections.ArrayList
    $f1 = Join-Path $la 'IconCache.db'
    if (Test-Path -LiteralPath $f1 -PathType Leaf) { [void]$list.Add($f1) }
    $ex = Join-Path (Join-Path (Join-Path $la 'Microsoft') 'Windows') 'Explorer'
    if (Test-Path -LiteralPath $ex -PathType Container) {
        foreach ($f in @(Get-ChildItem -LiteralPath $ex -Filter 'iconcache_*.db' -File -ErrorAction SilentlyContinue)) { [void]$list.Add($f.FullName) }
    }
    return $list.ToArray()
}

function Invoke-RebuildIconCacheOp {
    if ($script:Preview) { Add-Plan 'Windows Gezgini yeniden başlatılacak ve simge önbelleği silinecek (Windows yeniden oluşturur)'; return }
    $removed = 0
    for ($try = 0; $try -lt 3; $try++) {
        Get-Process -Name explorer -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 800
        foreach ($f in @(Get-IconCacheFiles)) {
            try { Remove-Item -LiteralPath $f -Force -ErrorAction Stop; $removed++ } catch { }
        }
        if (@(Get-IconCacheFiles).Count -eq 0) { break }
    }
    $left = @(Get-IconCacheFiles).Count
    for ($w = 0; $w -lt 8; $w++) {
        if (@(Get-Process -Name explorer -ErrorAction SilentlyContinue).Count -gt 0) { break }
        Start-Sleep -Milliseconds 500
    }
    if (@(Get-Process -Name explorer -ErrorAction SilentlyContinue).Count -eq 0) { Start-Process -FilePath 'explorer.exe' | Out-Null }
    if ($left -gt 0) { Add-Skip ([string]$left + ' önbellek dosyası kullanımda olduğu için silinemedi; oturumu kapatıp açınca yenilenir') }
    Add-Done ('Simge önbelleği yenilendi (' + [string]$removed + ' dosya), Gezgin yeniden başlatıldı')
}

$script:FuncOps['RenewIp'] = 'Invoke-RenewIpOp'
$script:FuncOps['NetStackReset'] = 'Invoke-NetStackResetOp'
$script:FuncOps['RestartAudio'] = 'Invoke-RestartAudioOp'
$script:FuncOps['ClearSpooler'] = 'Invoke-ClearSpoolerOp'
$script:FuncOps['ResetWuComponents'] = 'Invoke-ResetWuComponentsOp'
$script:FuncOps['RebuildIconCache'] = 'Invoke-RebuildIconCacheOp'
