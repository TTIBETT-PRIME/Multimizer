# -*- coding: utf-8 -*-
"""Kalici silme: cekirdek (yontemler, korumalar), guvenli silme korumalari ve gecis sayisi."""


def apply(b):
    # eski Test-SecureDeleteAllowed (base) kaldirilir; yenisi 128_wipe_core.ps1 icindedir
    start = 'function Test-SecureDeleteAllowed([string]$Path) {\n'
    end = '# Remove-FileSecure ve Job_SecureDelete (uzerine yazarak silme) Eklenti\\GuvenliSilme.ps1 dosyasindadir; ilk kullanimda yuklenir.\n'
    if b.t.count(start) != 1 or b.t.count(end) != 1:
        raise SystemExit('p42: Test-SecureDeleteAllowed bulunamadi')
    i = b.t.index(start)
    j = b.t.index(end)
    if j < i:
        raise SystemExit('p42: sira bozuk')
    b.t = b.t[:i] + '# Test-SecureDeleteAllowed: 128_wipe_core.ps1 icindedir.\n' + b.t[j:]
    b.add_core('128_wipe_core.ps1', title='kalici silme cekirdegi')

    # Start-TlWipe: gecis sayisi ise gonderilir, sinirlar metne eklenir, sonuc ortak islevle gosterilir
    b.rep("    if ($passes -lt 1) { $passes = 1 }\n    $what = 'Bu dosya'",
          "    if ($passes -lt 1) { $passes = 1 }\n    $script:PendingWipePasses = $passes\n    $what = 'Bu dosya'", raw=True, name='p42 passes')
    b.rep("[void](Start-Async 'Wipe' 'Job_SecureDelete' @{ Paths = $script:PendingWipe } {",
          "[void](Start-Async 'Wipe' 'Job_SecureDelete' @{ Paths = $script:PendingWipe; Passes = $script:PendingWipePasses } {", raw=True, name='p42 job')
    b.before("    if ([string]$sync.Profile.DiskType -eq 'SSD') { $txt += ",
             "    $txt += \"`r`n`r`nKısayollar izlenmez (yalnızca kısayolun kendisi kaldırılır) ve bulutta duran dosyalar atlanır. Yedekler, gölge kopyalar ve dosya adı kayıtları silinmez; bunlar için Çözüm Merkezi > Kalıcı silme sekmesindeki boş alan temizliğini de kullanın.\"\n")
    old = ("            if ($r.Ok -eq $true) { Show-Toast ([string]$r.Files + (' dosya g' + [char]0x00FC + 'venli silindi (') + (Format-Size ([double]$r.Bytes)) + ').') 'good' }\n"
           "            else { Show-Toast ([string]$r.Files + ' dosya silindi, ' + [string]$r.Failed + (' ' + [char]0x00F6 + '' + [char]0x011F + 'e silinemedi; g' + [char]0x00FC + 'nl' + [char]0x00FC + '' + [char]0x011F + 'e bak' + [char]0x0131 + 'n.')) 'warn' }\n")
    if b.t.count(old) != 1:
        raise SystemExit('p42: Start-TlWipe sonuc satirlari bulunamadi')
    b.t = b.t.replace(old, "            Show-SecureDeleteResult $r\n")
