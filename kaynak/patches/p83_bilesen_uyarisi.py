# -*- coding: utf-8 -*-
"""p83: Windows bileseni kaldirma secildiginde ozet geri kurulumun Windows Update'e bagli oldugunu soyler.

Gercek bilgisayarda (18.11.2026 22:49) XPS Goruntuleyici ve Adim Kaydedicisi kaldirildi; "Geri al" onlari Windows
Update'ten yeniden kuramadi (0x800F0950: bu Windows onizleme surumu icin icerik bulunamadi). Onceki iki denetimde ayni
geri kurulum sorunsuzdu. Kaldirilan bilesenin dosyalari silinir; geri kurulum her zaman Windows Update'ten iner ve icerik
her zaman bulunmaz. Optimize sayfasindaki ozet artik secimde bilesen kaldirma varsa bunu acikca yazar."""


def apply(b):
    b.rep("""    $reboot = 0
    foreach ($id in $ids) {
        $c = Get-CatalogItem $id
        if ($null -eq $c) { continue }
        $cn = [string]$script:CatNames[[string]$c.Cat]
        if (-not $byCat.ContainsKey($cn)) { $byCat[$cn] = 0 }
        $byCat[$cn]++
        if ($c.Irrev -eq $true) { [void]$irrev.Add([string]$c.Title) }
        if ($c.Reboot -eq $true) { $reboot++ }
    }
""", """    $reboot = 0
    $capRm = 0
    foreach ($id in $ids) {
        $c = Get-CatalogItem $id
        if ($null -eq $c) { continue }
        $cn = [string]$script:CatNames[[string]$c.Cat]
        if (-not $byCat.ContainsKey($cn)) { $byCat[$cn] = 0 }
        $byCat[$cn]++
        if ($c.Irrev -eq $true) { [void]$irrev.Add([string]$c.Title) }
        if ($c.Reboot -eq $true) { $reboot++ }
        if (@(@($c.Ops) | Where-Object { [string]$_.T -eq 'Cap' -and [string]$_.State -ne 'Installed' }).Count -gt 0) { $capRm++ }
    }
""", name='p83 bilesen sayaci')
    b.rep("""        if ($reboot -gt 0) { $t += ("`r`nBaz$([char]0x0131) de$([char]0x011F)i$([char]0x015F)iklikler i$([char]0x00E7)in yeniden ba$([char]0x015F)latma gerekecek.") }
""", """        if ($reboot -gt 0) { $t += ("`r`nBaz$([char]0x0131) de$([char]0x011F)i$([char]0x015F)iklikler i$([char]0x00E7)in yeniden ba$([char]0x015F)latma gerekecek.") }
        if ($capRm -gt 0) { $t += ("`r`n" + [string]$capRm + ' Windows bileşeni kaldırılacak. Geri alırken dosyaları Windows Update’ten yeniden indirilir; internet gerekir ve Windows önizleme (Insider) sürümlerinde içerik her zaman bulunmayabilir.') }
""", name='p83 bilesen notu')
