# -*- coding: utf-8 -*-
"""p78: DISM bilesen deposu temizligi bekleyen yeniden baslatmada hata vermez; sure sinirli calisir.
Gercek bilgisayardaki tam denetimde (18.11.2026) Windows yeniden baslatma beklerken temizlik 0x800F0806 ile basarisiz oldu
ve yalnizca sayisal cikis kodu yazildi. Artik Windows Update kuruyorsa ya da bilesen servisi yeniden baslatma bekliyorsa
temizlik nedeniyle birlikte ertelenir (onizlemede de gorunur); dism.exe sure sinirli (60 dk) calisir, hata aciklamali yazilir.
Ayrica tasarim ayarlarini yukleme, Ayarlar sayfasi henuz kurulmamisken (onay kutusu yokken) hata vermez."""


def apply(b):
    b.rep("""function Invoke-DismCleanup {
    if ($script:Preview) { Add-Plan ('DISM bile' + [char]0x015F + 'en deposu temizli' + [char]0x011F + 'i yap' + [char]0x0131 + 'lacak'); return }
    Write-WhLog ('DISM ba' + [char]0x015F + 'lad' + [char]0x0131 + '; 10-40 dakika s' + [char]0x00FC + 'rebilir, l' + [char]0x00FC + 'tfen bekleyin...') 'INFO'
    $dism = Join-Path $env:WINDIR 'System32\\Dism.exe'
    $p = Start-Process -FilePath $dism -ArgumentList '/Online /Cleanup-Image /StartComponentCleanup' -Wait -PassThru -WindowStyle Hidden
    if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) { throw (('DISM ' + [char]0x00E7 + [char]0x0131 + 'k' + [char]0x0131 + [char]0x015F + ' kodu ') + $p.ExitCode) }
    Add-Done ('DISM temizli' + [char]0x011F + 'i tamamland' + [char]0x0131)
}
""", """function Invoke-DismCleanup {
    $busy = Get-ServicingBusy
    if ($busy -ne '') { Add-Skip ('DISM bileşen deposu temizliği ertelendi: ' + $busy); return }
    $pend = Get-CbsRebootPending
    if ($pend -ne '') { Add-Skip ('DISM bileşen deposu temizliği ertelendi: Windows bir bileşen değişikliği için yeniden başlatılmayı bekliyor (' + $pend + '); yeniden başlattıktan sonra tekrar deneyin'); return }
    if ($script:Preview) { Add-Plan 'DISM bileşen deposu temizliği yapılacak'; return }
    Assert-DismReady
    Write-WhLog 'DISM başladı; 10-40 dakika sürebilir, lütfen bekleyin...' 'INFO'
    $rc = Invoke-DismExe @('/Online', '/Cleanup-Image', '/StartComponentCleanup') 60
    if ($rc -ne 0 -and $rc -ne 3010) { throw ('DISM bileşen deposu temizliği tamamlanamadı: ' + (Get-DismCodeText $rc)) }
    Add-Done 'DISM temizliği tamamlandı'
}
""", name='p78 dism temizlik')
    b.rep("    if (Test-DesignOverridden $s) { $ui.st_DsAdv.IsChecked = $true }\n",
          "    if ($null -ne $ui.st_DsAdv -and (Test-DesignOverridden $s)) { $ui.st_DsAdv.IsChecked = $true }\n",
          name='p78 tasarim onay kutusu')
