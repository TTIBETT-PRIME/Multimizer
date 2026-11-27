# -*- coding: utf-8 -*-
"""Kendi kendine sinama: eklenti listesi basligi ve kurtarma/silme motorlarinin derlenmesi, silme motoru ozdenetimi."""

SELF_ANCHOR = "    Add-SelfLine ''\n    $okN = $script:SelfTotal - $script:SelfFail\n"

# 8.0.0 tabanindaki baslik yalnizca ilk dort eklentiyi sayiyordu (ASCII, [char] dizileriyle yazilmis hâli)
OLD_TITLE = ("Test-Step ('Eklentiler y' + [char]0x00FC + 'klenir (' + [char]0x015F + 'ifreleme, bellek bo' + [char]0x015F + 'alt' + [char]0x0131 + 'c' + [char]0x0131 + "
             "', g' + [char]0x00FC + 'venli silme, Wi-Fi d' + [char]0x0131 + '' + [char]0x015F + 'a aktarma)') {")
NEW_TITLE = "Test-Step ('Eklentiler yüklenir (şifreleme, bellek boşaltıcı, güvenli silme, Wi-Fi dışa aktarma, disk koruma, kurtarma, disk silme)') {"

STEP = r"""    Test-Step ('Kurtarma ve silme motorları derlenir (C# 5); silme motoru geçici bir imajda kendini sınar, diske yazmaz') {
        $r = Import-MmExt 'Kurtarma'
        if ($r.Ok -ne $true) { return ('Kurtarma eklentisi: ' + [string]$r.Error) }
        $e = Initialize-MmRecover
        if ($e -ne '') { return ('Kurtarma motoru: ' + [string]$e) }
        $r = Import-MmExt 'DiskSilme'
        if ($r.Ok -ne $true) { return ('Disk silme eklentisi: ' + [string]$r.Error) }
        $e = Initialize-MmWipe
        if ($e -ne '') { return ('Silme motoru: ' + [string]$e) }
        $sc = Invoke-WipeSelfCheck
        foreach ($ln in @($sc.Lines)) { if ($ln.Ok -ne $true) { return ('Silme motoru özdenetimi: ' + [string]$ln.Text) } }
    } $true

"""

GATES = r"""    Test-Step ('Çözüm Merkezi, Hazırlık, Dış araçlar, Güncelleme denetimi ve Güvenlik duruşu: işlevler ve izin listeleri yerinde') {
        $need = @('Job_SlvDisks', 'Job_SlvDiskOp', 'Job_PcInfo', 'Job_PrepCheck', 'Job_PrepInstall', 'Job_ExtToolScan', 'Job_ExtToolInstall', 'Job_IntegrityCheck',
            'Chk_Posture', 'Chk_Crashes', 'Chk_AppCrashes', 'Chk_BootTime', 'Chk_DiskProtect', 'Chk_DiskErrors', 'Get-PostureCoverage', 'Test-BlEnablePlan',
            'Test-WipeDiskAllowed', 'Test-WipePartAllowed', 'Test-WipeIdentity', 'Test-WipeTyped', 'Test-SecureDeleteAllowed', 'Test-PrepPackage', 'Test-ExtToolId', 'Get-ExtToolCatalog', 'Test-UpdateUrl', 'Compare-AppVersion')
        $miss = @($need | Where-Object { $null -eq (Get-Command -Name $_ -CommandType Function -ErrorAction Ignore) })
        if ($miss.Count -gt 0) { return ('eksik: ' + ($miss -join ', ')) }
        if ((Test-PrepPackage 'Baska.Paket') -eq '') { return 'Hazırlık: izin listesi dışındaki paket kabul edildi' }
        foreach ($k in @($script:PrepPackages.Keys)) { if ((Test-PrepPackage ([string]$k)) -ne '') { return ('Hazırlık: izin listesindeki paket reddedildi: ' + [string]$k) } }
        if ((Test-ExtToolId 'Baska.Arac') -eq '') { return 'Dış araçlar: katalog dışındaki araç kabul edildi' }
        $cat = Get-ExtToolCatalog
        if (@($cat).Count -lt 1) { return 'Dış araçlar: katalog boş' }
        foreach ($t in @($cat)) { if ((Test-ExtToolId ([string]$t.Id)) -ne '') { return ('Dış araçlar: katalogdaki araç reddedildi: ' + [string]$t.Id) } }
        if ((Test-UpdateUrl 'http://example.com/a.json') -eq '') { return 'Güncelleme: şifresiz (http) adres kabul edildi' }
        if ((Test-UpdateUrl 'https://example.com/a.json') -ne '') { return 'Güncelleme: https adresi reddedildi' }
        if ((Compare-AppVersion '9.0.1' '9.0.0') -ne 1 -or (Compare-AppVersion '9.0.0' '9.0.0') -ne 0 -or $null -ne (Compare-AppVersion 'x' '9.0.0')) { return 'Güncelleme: sürüm karşılaştırması yanlış' }
        if ((Test-WipeDiskAllowed @{ IsSystem = $true; Roles = @(); Size = 1000000000 } 'Disk') -eq '') { return 'Silme: Windows’un çalıştığı diske doğrudan yazma izni verildi' }
        if ((Test-WipeDiskAllowed @{ Roles = @(); Size = 1000000000 } 'Disk') -ne '') { return 'Silme: sıradan bir veri diski reddedildi' }
        if (-not (Test-WipeTyped 'disk 3' 'Disk 3') -or (Test-WipeTyped 'disk 4' 'Disk 3')) { return 'Silme: elle yazılan onay metni yanlış karşılaştırılıyor' }
        if ((Test-SecureDeleteAllowed ([string]$env:SystemDrive + '\')) -eq '' -or (Test-SecureDeleteAllowed ([string]$env:WINDIR)) -eq '') { return 'Silme: sürücü kökü ya da Windows klasörü silinebilir sayıldı' }
    }

"""


def apply(b):
    b.rep(OLD_TITLE, '@@MM_TITLE@@', raw=True, name='p48 eski eklenti basligi')
    b.rep('@@MM_TITLE@@', NEW_TITLE, name='p48 yeni eklenti basligi')
    b.before(SELF_ANCHOR, STEP)
    b.before(SELF_ANCHOR, GATES)
