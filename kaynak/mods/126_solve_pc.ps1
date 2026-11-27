# ==================================================================
#  ÇÖZÜM MERKEZİ: "Bilgisayarım" sekmesi
#  Bilgisayarı tanır: model, Windows, işlemci, bellek, ekran kartı, diskler, ağ, pil ve güvenlik donanımı. Bilgileri yalnızca okur, hiçbir ayarı değiştirmez; Gözlemler altındaki düğmeler (yeniden başlatma, UEFI ayarına yeniden başlatma, aygıtları yeniden tarama) yalnızca onayla çalışır.
#  Kullanıcı kipinde sade özet, Uzman kipinde ham ayrıntılar gösterilir. Altta "Gözlemler" bölümü bulunanlara göre ne yapılabileceğini söyler.
#  Toplama (Get-PcInfo) arka plan işinde çalışır; yorumlama işlevleri (Get-PcSections, Get-PcNotes) saf mantıktır ve ayrı sınanır.
# ==================================================================
$script:PcInfo = $null
$script:PcLoading = $false

# ---------------- yorumlama (saf mantık) ----------------
function Get-PcMemSummary($I) {
    $mods = @($I.Mem.Modules)
    $total = [double]$I.Mem.TotalGB
    if ($mods.Count -eq 0) { return (Format-PcGb $total) }
    $types = @($mods | ForEach-Object { [string]$_.Type } | Where-Object { $_ -ne '' } | Select-Object -Unique)
    $speed = 0
    foreach ($m in $mods) { $sp = [int]$m.Running; if ($sp -le 0) { $sp = [int]$m.Rated }; if ($sp -gt $speed) { $speed = $sp } }
    $parts = New-Object System.Collections.ArrayList
    [void]$parts.Add((Format-PcGb $total))
    if ($types.Count -gt 0) { [void]$parts.Add(($types -join '/')) }
    if ($speed -gt 0) { [void]$parts.Add([string]$speed + ' MHz') }
    $mc = [string]$mods.Count + ' modül'
    if ([int]$I.Mem.SlotCount -gt $mods.Count) { $mc += ' (' + [string]([int]$I.Mem.SlotCount - $mods.Count) + ' yuva boş)' }
    [void]$parts.Add($mc)
    return ($parts.ToArray() -join '  ·  ')
}

function Get-PcSecuritySummary($I) {
    $m = $I.Machine
    $p = New-Object System.Collections.ArrayList
    if ([string]$m.Firmware -ne '') { [void]$p.Add([string]$m.Firmware) }
    if ($null -ne $m.SecureBoot) { if ($m.SecureBoot -eq $true) { [void]$p.Add('Güvenli Önyükleme açık') } else { [void]$p.Add('Güvenli Önyükleme kapalı') } }
    if ($m.Tpm.Known -eq $true) {
        if ($m.Tpm.Present -eq $true) {
            $tv = ''
            if ([string]$m.Tpm.Version -ne '') { $tv = ' ' + [string]$m.Tpm.Version }
            if ($m.Tpm.Ready -eq $true) { [void]$p.Add('TPM' + $tv + ' hazır') } else { [void]$p.Add('TPM' + $tv + ' var, kapalı') }
        } else { [void]$p.Add('TPM yok') }
    } else { [void]$p.Add('TPM durumu okunamadı (yönetici gerekir)') }
    if ($p.Count -eq 0) { return 'Okunamadı' }
    return ($p.ToArray() -join '  ·  ')
}

# Ekranda ve kopyalanan özette gösterilen bölümler: @( @{ Title; Rows = @( @{ K; V } ) } )
function Get-PcSections($I, [bool]$Expert) {
    $out = New-Object System.Collections.ArrayList
    $m = $I.Machine
    $o = $I.Os

    $r = New-Object System.Collections.ArrayList
    $mdl = (([string]$m.Maker + ' ' + [string]$m.Model).Trim())
    if ($mdl -eq '') { $mdl = 'Okunamadı' }
    [void]$r.Add(@{ K = 'Bilgisayar'; V = $mdl })
    if ([string]$m.Kind -ne '') { [void]$r.Add(@{ K = 'Tür'; V = [string]$m.Kind }) }
    $wn = [string]$o.Name
    if ($wn -eq '') { $wn = 'Windows' }
    if ([string]$o.Version -ne '') { $wn += '  ·  ' + [string]$o.Version }
    if ([int]$o.Build -gt 0) {
        $bs = [string]$o.Build
        if ([int]$o.Ubr -gt 0) { $bs += '.' + [string]$o.Ubr }
        $wn += '  ·  derleme ' + $bs
    }
    [void]$r.Add(@{ K = 'Windows'; V = $wn })
    if ([string]$o.Installed -ne '') { [void]$r.Add(@{ K = 'Kurulum tarihi'; V = [string]$o.Installed }) }
    if ([double]$o.UptimeHours -gt 0) { [void]$r.Add(@{ K = 'Açık kalma süresi'; V = (Format-PcSpan ([double]$o.UptimeHours)) }) }
    [void]$r.Add(@{ K = 'Güvenlik donanımı'; V = (Get-PcSecuritySummary $I) })
    if ($Expert) {
        if ([string]$m.Board -ne '') { [void]$r.Add(@{ K = 'Anakart'; V = [string]$m.Board }) }
        if ([string]$m.Bios -ne '') {
            $bv = [string]$m.Bios
            if ([string]$m.BiosDate -ne '') { $bv += '  ·  ' + [string]$m.BiosDate }
            [void]$r.Add(@{ K = 'BIOS / UEFI sürümü'; V = $bv })
        }
        if ([string]$o.Arch -ne '') { [void]$r.Add(@{ K = 'Mimari'; V = [string]$o.Arch }) }
        if ([string]$o.Boot -ne '') { [void]$r.Add(@{ K = 'Son açılış'; V = [string]$o.Boot }) }
    }
    [void]$out.Add(@{ Title = 'Bilgisayar ve Windows'; Rows = $r.ToArray() })

    $c = $I.Cpu
    $r = New-Object System.Collections.ArrayList
    $cn = [string]$c.Name
    if ($cn -eq '') { $cn = 'Okunamadı' }
    [void]$r.Add(@{ K = 'İşlemci'; V = $cn })
    if ([int]$c.Cores -gt 0) { [void]$r.Add(@{ K = 'Çekirdek'; V = [string]$c.Cores + ' çekirdek, ' + [string]$c.Threads + ' iş parçacığı' }) }
    if ($Expert) {
        if ([int]$c.Mhz -gt 0) { [void]$r.Add(@{ K = 'En yüksek hız'; V = [string]$c.Mhz + ' MHz' }) }
        if ([int]$c.L2KB -gt 0 -or [int]$c.L3KB -gt 0) { [void]$r.Add(@{ K = 'Önbellek'; V = 'L2 ' + [string][math]::Round([double]$c.L2KB / 1024, 1) + ' MB  ·  L3 ' + [string][math]::Round([double]$c.L3KB / 1024, 1) + ' MB' }) }
        if ($null -ne $c.Virt) { if ($c.Virt -eq $true) { [void]$r.Add(@{ K = 'Sanallaştırma'; V = 'Açık' }) } else { [void]$r.Add(@{ K = 'Sanallaştırma'; V = 'Kapalı (BIOS ayarı)' }) } }
    }
    [void]$out.Add(@{ Title = 'İşlemci'; Rows = $r.ToArray() })

    $r = New-Object System.Collections.ArrayList
    [void]$r.Add(@{ K = 'Bellek'; V = (Get-PcMemSummary $I) })
    if ($Expert) {
        $k = 0
        foreach ($md in @($I.Mem.Modules)) {
            $k++
            $line = (Format-PcGb ([double]$md.CapGB))
            if ([string]$md.Type -ne '') { $line += '  ·  ' + [string]$md.Type }
            if ([int]$md.Running -gt 0 -and [int]$md.Rated -gt 0 -and [int]$md.Running -ne [int]$md.Rated) { $line += '  ·  ' + [string]$md.Running + ' MHz (üretici değeri ' + [string]$md.Rated + ' MHz)' }
            elseif ([int]$md.Rated -gt 0) { $line += '  ·  ' + [string]$md.Rated + ' MHz' }
            if ([string]$md.Maker -ne '') { $line += '  ·  ' + [string]$md.Maker }
            if ([string]$md.Part -ne '') { $line += '  ·  ' + [string]$md.Part }
            $slot = [string]$md.Slot
            if ($slot -eq '') { $slot = 'Modül ' + [string]$k }
            [void]$r.Add(@{ K = $slot; V = $line })
        }
        if ([double]$I.Mem.MaxGB -gt 0) { [void]$r.Add(@{ K = 'Desteklenen en çok'; V = (Format-PcGb ([double]$I.Mem.MaxGB)) }) }
    }
    [void]$out.Add(@{ Title = 'Bellek'; Rows = $r.ToArray() })

    $r = New-Object System.Collections.ArrayList
    if (@($I.Gpu).Count -eq 0) { [void]$r.Add(@{ K = 'Ekran kartı'; V = 'Okunamadı' }) }
    foreach ($g in @($I.Gpu)) {
        [void]$r.Add(@{ K = 'Ekran kartı'; V = [string]$g.Name })
        if ($Expert) {
            if ([string]$g.Driver -ne '') {
                $dv = [string]$g.Driver
                if ([string]$g.DriverDate -ne '') { $dv += '  ·  ' + [string]$g.DriverDate }
                [void]$r.Add(@{ K = '   sürücü'; V = $dv })
            }
            if ([string]$g.Res -ne '') { [void]$r.Add(@{ K = '   ekran'; V = [string]$g.Res }) }
        }
    }
    [void]$out.Add(@{ Title = 'Ekran kartı'; Rows = $r.ToArray() })

    $r = New-Object System.Collections.ArrayList
    if (@($I.Disks).Count -eq 0) { [void]$r.Add(@{ K = 'Diskler'; V = 'Okunamadı' }) }
    foreach ($d in @($I.Disks)) {
        $line = [string]$d.Name
        if ($line -eq '') { $line = 'Disk' }
        $line += '  ·  ' + [string]$d.Kind + '  ·  ' + (Format-PcGb ([double]$d.SizeGB))
        if ([string]$d.Health -ne '' -and [string]$d.Health -ne 'Healthy') { $line += '  ·  sağlık: ' + [string]$d.Health }
        if ($Expert) {
            if ([string]$d.Style -ne '' -and [string]$d.Style -ne 'RAW') { $line += '  ·  ' + [string]$d.Style }
            if ([string]$d.Bus -ne '') { $line += '  ·  ' + [string]$d.Bus }
            if (@($d.Letters).Count -gt 0) { $line += '  ·  ' + (@($d.Letters) -join ' ') }
        }
        $lbl = 'Disk ' + [string]$d.Number
        if ($d.IsSystem -eq $true) { $lbl += ' (Windows)' }
        [void]$r.Add(@{ K = $lbl; V = $line })
    }
    if ([double]$I.SysDrive.SizeGB -gt 0) { [void]$r.Add(@{ K = ([string]$I.SysDrive.Letter + ' boş alan'); V = ((Format-PcGb ([double]$I.SysDrive.FreeGB)) + ' / ' + (Format-PcGb ([double]$I.SysDrive.SizeGB))) }) }
    [void]$out.Add(@{ Title = 'Depolama'; Rows = $r.ToArray() })

    if (@($I.Net).Count -gt 0) {
        $r = New-Object System.Collections.ArrayList
        foreach ($n in @($I.Net)) {
            $line = [string]$n.Name
            if ($n.Up -eq $true) { if ([string]$n.Speed -ne '') { $line += '  ·  bağlı, ' + [string]$n.Speed } else { $line += '  ·  bağlı' } } else { $line += '  ·  bağlı değil' }
            [void]$r.Add(@{ K = [string]$n.Kind; V = $line })
        }
        [void]$out.Add(@{ Title = 'Ağ'; Rows = $r.ToArray() })
    }

    if ($null -ne $I.Battery) {
        $b = $I.Battery
        $r = New-Object System.Collections.ArrayList
        $pl = '%' + [string]$b.Percent
        if ($b.Charging -eq $true) { $pl += '  ·  şarj oluyor ya da fişte' } else { $pl += '  ·  pille çalışıyor' }
        [void]$r.Add(@{ K = 'Şarj'; V = $pl })
        if ([int]$b.WearPct -ge 0) {
            $wv = '%' + [string]$b.WearPct + ' aşınma'
            if ($Expert -and [int]$b.DesignMWh -gt 0) { $wv += '  ·  tasarım ' + [string]$b.DesignMWh + ' mWh, şimdi ' + [string]$b.FullMWh + ' mWh' }
            [void]$r.Add(@{ K = 'Pil sağlığı'; V = $wv })
        }
        [void]$out.Add(@{ Title = 'Pil'; Rows = $r.ToArray() })
    }

    if ($Expert -and @($I.Problems).Count -gt 0) {
        $r = New-Object System.Collections.ArrayList
        foreach ($p in @($I.Problems)) { [void]$r.Add(@{ K = ('Kod ' + [string]$p.Code); V = [string]$p.Name }) }
        [void]$out.Add(@{ Title = 'Sorunlu aygıtlar'; Rows = $r.ToArray() })
    }
    return $out.ToArray()
}

# Gözlem düğmesi: @{ Label; Do; ... }. Do: Page (Sayfa, Sub) | Url (Url) | Tool (Path) | SlTab (Tab) | Reboot | Uefi | Job (Key, Confirm, Done)
function New-PcAct([string]$Label, [string]$Do, $Extra = $null) {
    $a = @{ Label = $Label; Do = $Do }
    if ($null -ne $Extra) { foreach ($k in @($Extra.Keys)) { $a[$k] = $Extra[$k] } }
    return $a
}

# Gözlemler: @( @{ Level = warn|info|good; Title; Text; A1; A2 } ). A1/A2 bulguyu düzelten ya da ilgili yere götüren düğmelerdir (yoksa $null).
# Uzman kipine özel olanlar yalnızca $Expert iken gelir.
function Get-PcNotes($I, [bool]$Expert) {
    $n = New-Object System.Collections.ArrayList
    $m = $I.Machine
    $o = $I.Os
    $isVm = ($m.IsVm -eq $true)
    $actUefi = New-PcAct 'UEFI ayarlarına git' 'Uefi'
    $actDev = New-PcAct 'Aygıt Yöneticisi' 'Tool' @{ Path = 'devmgmt.msc' }
    $actWu = New-PcAct 'Güncellemeleri ara' 'Page' @{ Page = 'wu'; Sub = '' }
    $actBackup = New-PcAct 'Yedekle' 'Page' @{ Page = 'backup'; Sub = '' }

    if ([int]$o.Build -gt 0 -and [int]$o.Build -lt 22000 -and ([string]$o.Name -match 'Windows 10')) {
        [void]$n.Add(@{ Level = 'warn'; Title = 'Windows 10 kullanıyorsunuz'; Text = 'Windows 10 için standart destek 14 Ekim 2025’te sona erdi. Güvenlik güncellemeleri almaya devam etmek için uygun bilgisayarda Windows 11’e geçmeniz önerilir.'
            A1 = (New-PcAct 'Windows Update’i aç' 'Url' @{ Url = 'ms-settings:windowsupdate' }); A2 = $null })
        if ($m.Tpm.Known -eq $true -and ($m.Tpm.Present -ne $true -or ([string]$m.Tpm.Version -ne '' -and [string]$m.Tpm.Version -ne '2.0'))) {
            [void]$n.Add(@{ Level = 'info'; Title = 'Windows 11 için TPM 2.0 gerekir'; Text = 'Bu bilgisayarda TPM 2.0 görünmüyor. BIOS ayarlarında “fTPM” ya da “PTT” seçeneği açılırsa Windows 11 gereksinimi karşılanabilir.'; A1 = $actUefi; A2 = $null })
        }
    }

    $tot = [double]$I.Mem.TotalGB
    $actStartup = New-PcAct 'Başlangıç programları' 'Page' @{ Page = 'startup'; Sub = '' }
    if ($tot -gt 0 -and $tot -lt 4) { [void]$n.Add(@{ Level = 'warn'; Title = 'Bellek çok az'; Text = (Format-PcGb $tot) + ' bellek Windows’un rahat çalışması için yetersiz. Bellek eklemek ya da arka plan programlarını azaltmak belirgin fark yaratır.'; A1 = $actStartup; A2 = $null }) }
    elseif ($tot -ge 4 -and $tot -lt 8) { [void]$n.Add(@{ Level = 'info'; Title = 'Bellek sınırda'; Text = (Format-PcGb $tot) + ' bellek günlük işler için yeterli, ama tarayıcı ve birkaç program birlikte açıldığında zorlanabilir. 8 GB ve üzeri önerilir.'; A1 = $actStartup; A2 = $null }) }
    $mods = @($I.Mem.Modules)
    if (-not $isVm -and $mods.Count -eq 1 -and [int]$I.Mem.SlotCount -ge 2) {
        [void]$n.Add(@{ Level = 'info'; Title = 'Bellek tek kanalda çalışıyor'; Text = 'Tek bellek modülü takılı, boş yuva var. Aynı özellikte ikinci bir modül çift kanal sağlar; bellek bant genişliği iki katına çıkar ve özellikle yerleşik ekran kartlarında oyun ve uygulama hızı artar. Bu bir donanım eklemesidir, yazılımla düzeltilemez.'; A1 = $null; A2 = $null })
    }
    if ($Expert) {
        foreach ($md in $mods) {
            if ([int]$md.Rated -gt 0 -and [int]$md.Running -gt 0 -and [int]$md.Running -lt [int]([double]$md.Rated * 0.9)) {
                [void]$n.Add(@{ Level = 'info'; Title = 'Bellek üretici hızının altında çalışıyor'; Text = 'Modüller ' + [string]$md.Rated + ' MHz için üretilmiş, ' + [string]$md.Running + ' MHz’de çalışıyor. BIOS’ta XMP (Intel) ya da EXPO/DOCP (AMD) profili açılırsa tam hıza çıkar; kararlılık için yalnızca profili seçin, elle voltaj değiştirmeyin.'; A1 = $actUefi; A2 = $null })
                break
            }
        }
        if ($null -ne $I.Cpu.Virt -and $I.Cpu.Virt -eq $false -and -not $isVm) {
            [void]$n.Add(@{ Level = 'info'; Title = 'Sanallaştırma kapalı'; Text = 'WSL2, Windows Alt Sistemi, Android uygulamaları ve sanal makineler için BIOS’ta “Intel VT-x” ya da “AMD-V / SVM” açılmalıdır.'; A1 = $actUefi; A2 = $null })
        }
    }

    foreach ($d in @($I.Disks)) {
        if ($d.IsSystem -eq $true -and [string]$d.Kind -eq 'HDD') {
            [void]$n.Add(@{ Level = 'warn'; Title = 'Windows bir HDD üzerinde'; Text = 'Windows klasik bir sabit diskten (HDD) çalışıyor. SSD’ye geçmek açılış, güncelleme ve program başlatma hızını en çok artıran tek değişikliktir. Taşımadan önce tam yedek alın.'; A1 = $actBackup; A2 = $null })
        }
        if ([string]$d.Health -ne '' -and [string]$d.Health -ne 'Healthy') {
            [void]$n.Add(@{ Level = 'warn'; Title = 'Disk ' + [string]$d.Number + ' sağlık uyarısı veriyor'; Text = (Get-PcText $d.Name) + ' için Windows “' + [string]$d.Health + '” bildiriyor. Önemli dosyalarınızı hemen yedekleyin ve diski değiştirmeyi düşünün.'
                A1 = $actBackup; A2 = (New-PcAct 'Diskleri incele' 'SlTab' @{ Tab = 'disk' }) })
        }
    }
    $sg = [double]$I.SysDrive.SizeGB
    if ($sg -gt 0) {
        $fg = [double]$I.SysDrive.FreeGB
        if ($fg -lt 15 -or ($fg * 100.0 / $sg) -lt 10) {
            [void]$n.Add(@{ Level = 'warn'; Title = [string]$I.SysDrive.Letter + ' sürücüsünde boş alan az'; Text = (Format-PcGb $fg) + ' boş kaldı. Windows güncellemeleri ve sanal bellek için yer gerekir; geçici dosyaları temizleyin ya da kullanmadığınız programları kaldırın.'
                A1 = (New-PcAct 'Temizlik' 'Page' @{ Page = 'clean'; Sub = '' }); A2 = $null })
        }
    }

    if ([double]$o.UptimeHours -ge 336) {
        [void]$n.Add(@{ Level = 'info'; Title = 'Uzun süredir yeniden başlatılmadı'; Text = (Format-PcSpan ([double]$o.UptimeHours)) + ' önce açılmış. Windows’un Hızlı Başlatma özelliği nedeniyle “Kapat” tam kapanma sayılmaz; güncellemelerin tamamlanması için “Yeniden başlat” kullanın.'
            A1 = (New-PcAct 'Yeniden başlat' 'Reboot'); A2 = $null })
    }

    if ($m.IsVm -ne $true -and [string]$m.Firmware -eq 'Eski BIOS') {
        [void]$n.Add(@{ Level = 'info'; Title = 'Windows eski BIOS kipinde kurulu'; Text = 'UEFI ve Güvenli Önyükleme kullanılmıyor. Windows 10 (sürüm 1703 ve sonrası) MBR2GPT aracıyla veri silmeden GPT/UEFI’ye geçirilebilir; önce tam yedek alın. Düğme yalnızca uygunluğu denetler, diskte hiçbir şey değiştirmez.'
            A1 = (New-PcAct 'Uygunluğu denetle' 'Job' @{ Key = 'PcMbr2gpt'; Confirm = ''; Done = 'Disk GPT’ye dönüştürmeye uygun görünüyor. Dönüştürmeden önce tam yedek alın.'; Fail = 'Disk GPT’ye dönüştürmeye uygun değil ya da denetim yapılamadı; ayrıntı günlükte.'; Busy = 'Disk uygunluğu denetleniyor' })
            A2 = $actBackup })
    } elseif ($null -ne $m.SecureBoot -and $m.SecureBoot -eq $false -and [string]$m.Firmware -eq 'UEFI' -and -not $isVm) {
        [void]$n.Add(@{ Level = 'info'; Title = 'Güvenli Önyükleme kapalı'; Text = 'Bilgisayar UEFI kipinde ama Güvenli Önyükleme kapalı. Windows 11 ve bazı programlar açık olmasını ister; BIOS ayarlarından açılabilir.'; A1 = $actUefi; A2 = $null })
    }

    foreach ($g in @($I.Gpu)) {
        $gn = [string]$g.Name
        if ($gn -match 'Microsoft Basic Display') {
            [void]$n.Add(@{ Level = 'warn'; Title = 'Ekran kartı sürücüsü kurulu değil'; Text = 'Windows temel görüntü sürücüsünü kullanıyor; 3D hızlandırma ve yüksek çözünürlük sınırlı olur. Windows Update çoğu kartın sürücüsünü bulur; bulamazsa üreticinin (Intel, AMD, NVIDIA) sürücüsünü kurun.'; A1 = $actWu; A2 = $actDev })
        } elseif ($gn -notmatch 'Remote|Virtual|Meta|Parsec') {
            $dt = [datetime]::MinValue
            $dm = [regex]::Match([string]$g.DriverDate, '^(\d{2})\.(\d{2})\.(\d{4})$')
            if ($dm.Success) { try { $dt = New-Object System.DateTime -ArgumentList ([int]$dm.Groups[3].Value), ([int]$dm.Groups[2].Value), ([int]$dm.Groups[1].Value) } catch { } }
            if ($dt -gt [datetime]::MinValue -and ((Get-Date) - $dt).TotalDays -gt 730) {
                [void]$n.Add(@{ Level = 'info'; Title = 'Ekran kartı sürücüsü eski'; Text = $gn + ' sürücüsü ' + [string]$g.DriverDate + ' tarihli. Yeni oyun ve programlarla uyum ve güvenlik düzeltmeleri için güncel sürücüyü kurun.'; A1 = $actWu; A2 = $actDev })
            }
        }
    }

    if ($null -ne $I.Battery -and [int]$I.Battery.WearPct -ge 30) {
        $lv = 'info'
        if ([int]$I.Battery.WearPct -ge 50) { $lv = 'warn' }
        [void]$n.Add(@{ Level = $lv; Title = 'Pil yıpranmış'; Text = 'Pilin tam şarj kapasitesi tasarım değerinin yaklaşık %' + [string](100 - [int]$I.Battery.WearPct) + ' düzeyine inmiş. Pilde çalışma süresi kısalır; değiştirme zamanı gelmiş olabilir. Ayrıntılı rapor pilin geçmişini gösterir.'
            A1 = (New-PcAct 'Pil raporu' 'Job' @{ Key = 'BatteryReport'; Confirm = ''; Done = 'Pil raporu hazırlandı ve açıldı.'; Fail = 'Pil raporu oluşturulamadı; ayrıntı günlükte.'; Busy = 'Pil raporu hazırlanıyor' }); A2 = $null })
    }

    $pc = @($I.Problems)
    if ($pc.Count -gt 0) {
        $names = @($pc | Select-Object -First 3 | ForEach-Object { [string]$_.Name }) -join ', '
        [void]$n.Add(@{ Level = 'warn'; Title = [string]$pc.Count + ' aygıtta sorun var'; Text = 'Aygıt Yöneticisi şu aygıtlar için hata bildiriyor: ' + $names + '. Donanım değişiklikleri yeniden taranınca eksik sürücüler çoğu zaman kendiliğinden kurulur; olmazsa üreticinin sürücüsünü kurmak gerekir.'
            A1 = (New-PcAct 'Aygıtları yeniden tara' 'Job' @{ Key = 'PcRescan'; Confirm = 'Windows donanım değişikliklerini yeniden tarar (pnputil /scan-devices). Sürücüsü eksik ya da hatalı aygıtlar için sürücü yeniden denenir; hiçbir ayar değişmez ve dosyalara dokunulmaz.'; Done = 'Aygıtlar yeniden tarandı. Durumu görmek için “Yenile”ye basın.'; Fail = 'Tarama yapılamadı (yönetici olarak çalıştırın); ayrıntı günlükte.'; Busy = 'Aygıtlar taranıyor' }); A2 = $actDev })
    }

    if ($n.Count -eq 0) { [void]$n.Add(@{ Level = 'good'; Title = 'Dikkat çeken bir şey yok'; Text = 'Donanım ve Windows tarafında düzeltilmesi gereken bir bulgu çıkmadı.'; A1 = $null; A2 = $null }) }
    return $n.ToArray()
}

# Panoya kopyalanacak düz metin özeti
function Get-PcSummaryText($I, [bool]$Expert) {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('Multimizer - Bilgisayar özeti  (' + [string]$I.At + ')')
    foreach ($s in @(Get-PcSections $I $Expert)) {
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine([string]$s.Title)
        foreach ($r in @($s.Rows)) { [void]$sb.AppendLine('  ' + [string]$r.K + ': ' + [string]$r.V) }
    }
    $notes = @(Get-PcNotes $I $Expert)
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('Gözlemler')
    foreach ($t in $notes) { [void]$sb.AppendLine('  - ' + [string]$t.Title + ': ' + [string]$t.Text) }
    return $sb.ToString().TrimEnd()
}

function Set-ClipText([string]$Text) {
    try { [System.Windows.Clipboard]::SetText($Text); return $true } catch { return $false }
}

# ---------------- çizim ----------------
function Load-SlPc {
    if ($script:PcLoading -eq $true) { return }
    $script:PcLoading = $true
    $ok = Start-Async 'PcInfo' 'Job_PcInfo' @{} {
        param($r)
        Complete-SlPc $r
    } 'Bilgisayar okunuyor' $false $true
    if (-not $ok) { $script:PcLoading = $false }
}

function Complete-SlPc($R) {
    $script:PcLoading = $false
    if ($null -eq $R -or $R.Ok -ne $true) { $script:PcInfo = @{ Failed = $true } } else { $script:PcInfo = $R.Info }
    if ([string]$script:UiState.Page -eq 'solve' -and $script:SlTab -eq 'pc') { Render-SlPc }
}

function Render-SlPc {
    $ui.sl_List.Children.Clear()
    $I = $script:PcInfo
    if ($null -eq $I) {
        Add-Note $ui.sl_List 'Bilgisayar okunuyor...'
        Load-SlPc
        return
    }
    if ($I.Failed -eq $true) {
        Add-Note $ui.sl_List 'Bilgisayar bilgisi okunamadı. “Yenile”ye basarak yeniden deneyin; sorun sürerse günlüğe bakın.' 'warn'
        return
    }
    $expert = ([string]$script:UiState.Mode -eq 'Expert')
    if ($expert) { Add-Note $ui.sl_List 'Uzman kipi: ham değerler, bellek modülleri, sürücü sürümleri ve sorunlu aygıt kodları da gösteriliyor.' }
    else { Add-Note $ui.sl_List 'Bilgisayarınızın ne olduğunu ve neye ihtiyacı olabileceğini sade anlatır. Bellek modülleri, sürücü sürümleri ve BIOS ayrıntıları için sağ üstten Uzman kipine geçin. Bilgiler yalnızca okunur, hiçbir ayar değişmez; Gözlemler altındaki düğmeler (yeniden başlatma, UEFI ayarına yeniden başlatma, aygıtları yeniden tarama) yalnızca onayınızla çalışır.' }
    foreach ($s in @(Get-PcSections $I $expert)) {
        Add-HeadRow $ui.sl_List ([string]$s.Title)
        foreach ($r in @($s.Rows)) { Add-KvRow $ui.sl_List ([string]$r.K) ([string]$r.V) }
    }
    Add-HeadRow $ui.sl_List 'Gözlemler'
    foreach ($t in @(Get-PcNotes $I $expert)) {
        $br = 'BrInfo'
        if ([string]$t.Level -eq 'warn') { $br = 'BrWarn' } elseif ([string]$t.Level -eq 'good') { $br = 'BrGood' }
        $b1 = ''; $b2 = ''
        if ($null -ne $t.A1) { $b1 = [string]$t.A1.Label }
        if ($null -ne $t.A2) { $b2 = [string]$t.A2.Label }
        $d1 = @{ Do = '' }
        if ($null -ne $t.A1) { $d1 = $t.A1 }
        $row = New-ItemRow @{ Title = [string]$t.Title; Detail = [string]$t.Text; BrCol = $br; Btn1 = $b1; Btn2 = $b2 } $d1 $false $false
        if ($b1 -ne '') { $row.FindName('Act').Add_Click($script:H_PcAct) }
        if ($b2 -ne '') {
            $a2 = $row.FindName('Act2')
            $a2.Tag = $t.A2
            $a2.Add_Click($script:H_PcAct)
        }
        [void]$ui.sl_List.Children.Add($row)
    }
    $adm = ''
    if ($I.Admin -ne $true) { $adm = '  ·  yönetici olmadan TPM gibi bazı bilgiler okunamayabilir' }
    $ui.sl_Foot.Text = 'Okundu: ' + [string]$I.At + $adm
}

$script:H_PcAct = { param($s, $e) Invoke-Safe { Invoke-PcAction $s.Tag } 'Eylem' }
$script:PcPendingJob = $null

# Gözlem düğmeleri: ya ilgili sayfaya götürür ya da (onayla) bir işlem çalıştırır
function Invoke-PcAction($T) {
    if ($null -eq $T) { return }
    switch ([string]$T.Do) {
        'Page'   { Open-Page ([string]$T.Page) ([string]$T.Sub) }
        'Url'    { Open-Url ([string]$T.Url) }
        'Tool'   { Open-Path ([string]$T.Path) }
        'SlTab'  { if (-not (Select-TabChip 'sl' ([string]$T.Tab))) { Set-SlTab ([string]$T.Tab) } }
        'Reboot' { Request-Reboot }
        'Uefi'   { Start-PcUefi }
        'Job'    { Start-PcJob $T }
    }
}

function Start-PcJob($T) {
    $script:PcPendingJob = $T
    if ([string]$T.Confirm -ne '') {
        Show-Confirm ([string]$T.Label) ([string]$T.Confirm) 'Çalıştır' { Start-PcJobNow }
        return
    }
    Start-PcJobNow
}

function Start-PcJobNow {
    $T = $script:PcPendingJob
    if ($null -eq $T) { return }
    [void](Start-Async 'Action' 'Job_Action' @{ Key = [string]$T.Key } {
        param($r)
        $j = $script:PcPendingJob
        if ($null -ne $r -and $r.Ok -eq $true) { Show-Toast ([string]$j.Done) 'good' } else { Show-Toast ([string]$j.Fail) 'bad' }
    } ([string]$T.Busy))
}

# Bilgisayarı doğrudan UEFI (BIOS) ayar ekranına yeniden başlatır; yalnızca UEFI kipinde çalışır
function Start-PcUefi {
    $fw = ''
    if ($null -ne $script:PcInfo -and $script:PcInfo.Failed -ne $true) { $fw = [string]$script:PcInfo.Machine.Firmware }
    if ($fw -eq 'Eski BIOS') {
        Show-Toast 'Bu bilgisayar eski BIOS kipinde. BIOS ayarına açılışta üreticinin tuşuyla (genellikle Del, F2 ya da F10) girilir.' 'info'
        return
    }
    Show-Confirm 'UEFI ayarlarına yeniden başlat' ('Bilgisayar 30 saniye sonra yeniden başlatılır ve doğrudan UEFI (BIOS) ayar ekranı açılır. Açık işlerinizi kaydedin.' + "`r`n`r`n" + 'Bu ekranda yaptığınız değişikliklerin sorumluluğu size aittir; emin değilseniz hiçbir şeyi değiştirmeden çıkın. Komut satırına “iptal” yazarak yeniden başlatmayı durdurabilirsiniz.') 'Yeniden başlat' {
        try {
            Start-Process -FilePath 'shutdown.exe' -ArgumentList '/r', '/fw', '/t', '30', '/c', 'Multimizer: UEFI ayarlarina yeniden baslatma' -WindowStyle Hidden | Out-Null
            Show-Toast 'Bilgisayar 30 saniye sonra UEFI ayarlarına yeniden başlatılacak.' 'warn'
        } catch { Show-Toast 'Yeniden başlatılamadı.' 'bad' }
    } $true
}

# Aygıt yöneticisinin "donanım değişikliklerini tara" işlemi (Job_Action anahtarı: PcRescan)
function Invoke-PcRescanAction($P) {
    Write-WhLog 'Donanım değişiklikleri taranıyor (pnputil /scan-devices)...' 'INFO'
    $o = & pnputil.exe /scan-devices 2>&1
    if ($LASTEXITCODE -ne 0) { throw ('pnputil çıkış kodu ' + [string]$LASTEXITCODE + ': ' + (($o | Out-String).Trim())) }
    Write-WhLog 'Aygıtlar yeniden tarandı.' 'OK'
}
$script:ExtraActions['PcRescan'] = 'Invoke-PcRescanAction'

# MBR2GPT dönüştürme uygunluğunu yalnızca denetler (diskte hiçbir şey değişmez)
function Invoke-PcMbr2gptAction($P) {
    Write-WhLog 'Disk GPT dönüştürme uygunluğu denetleniyor (mbr2gpt /validate; salt okunur)...' 'INFO'
    $o = & mbr2gpt.exe /validate /allowFullOS 2>&1
    $txt = (($o | Out-String).Trim())
    if ($txt -ne '') { Write-WhLog $txt 'INFO' }
    if ($LASTEXITCODE -ne 0) { throw ('mbr2gpt çıkış kodu ' + [string]$LASTEXITCODE) }
    Write-WhLog 'Disk GPT dönüştürmeye uygun.' 'OK'
}
$script:ExtraActions['PcMbr2gpt'] = 'Invoke-PcMbr2gptAction'

function Copy-SlPc {
    $I = $script:PcInfo
    if ($null -eq $I -or $I.Failed -eq $true) { Show-Toast 'Önce bilgisayar bilgisinin okunmasını bekleyin.' 'warn'; return }
    $expert = ([string]$script:UiState.Mode -eq 'Expert')
    if (Set-ClipText (Get-PcSummaryText $I $expert)) { Show-Toast 'Bilgisayar özeti panoya kopyalandı.' 'good' } else { Show-Toast 'Kopyalanamadı.' 'warn' }
}

function Init-SlPc {
    $ui.sl_PcRefresh.Add_Click({ Invoke-Safe { $script:PcInfo = $null; Render-SlPc } 'Yenile' })
    $ui.sl_PcCopy.Add_Click({ Invoke-Safe { Copy-SlPc } 'Kopyala' })
}

# Kullanıcı / Uzman kipi değişince açık sekmeyi yeniden çizer
function Update-PageMode_solve {
    if ([string]$script:UiState.Page -ne 'solve') { return }
    if ($script:SlTab -eq 'pc' -and $null -ne $script:PcInfo) { Render-SlPc }
    elseif ($script:SlTab -eq 'prep' -and $null -ne $script:PrepState) { Render-SlPrep }
    elseif ($script:SlTab -eq 'scan' -and $null -ne $script:Health) { Render-SlScan }
}
