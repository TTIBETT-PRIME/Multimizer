# -*- coding: utf-8 -*-
"""p80: Windows bileseni (capability) durumu bayat okunmaz.

Gercek bilgisayardaki tam denetimde (18.11.2026 15:18-16:13) "XPS Goruntuleyici'yi kapat" ve "Adim Kaydedicisi'ni kaldir"
gercekten uygulandi, ama hemen ardindan dogrulama "tam uygulanamadi (1 deger hala farkli)" dedi; canli tur da XPS icin
HATA verdi. Neden: bilesen listesi oturum boyunca bir kez okunup saklaniyordu ($script:CapCache) ve isler ayni calisma
alaninda (runspace) calistigi icin degisiklikten sonra da eski liste kullaniliyordu. Uygulama acik kaldikca durum ekrani da
eski durumu gosterirdi. Artik:
  - bilesen listesi yalnizca toplu durum olcumu partisi icinde (Start-StateBatch) bir kez okunur; parti disinda ve gercek
    uygulamada her okuma tazedir (ozellik ve gorev okumalariyla ayni kural);
  - "kurulum yeniden baslatma bekliyor" (InstallPending) kurulu sayilir; "kaldirma yeniden baslatma bekliyor"
    (UninstallPending) kurulu sayilmaz. Boylece yeniden baslatma bekleyen degisiklik dogrulamada "uygulanmadi" gorunmez,
    geri alma da bekleyen kurulumu ikinci kez kurmaya calismaz;
  - liste okunamazsa uyari bir iste bir kez yazilir."""


def apply(b):
    b.rep("""$script:CapCache = $null
function Get-CapList {
    if ($null -eq $script:CapCache) {
        $script:CapCache = @()
        $script:CapReadFailed = $false
        try { $script:CapCache = @(Get-WindowsCapability -Online -ErrorAction Stop) } catch { $script:CapReadFailed = $true; Write-WhLog (('Bile' + [char]0x015F + 'en listesi okunamad' + [char]0x0131 + ': ') + $_.Exception.Message) 'WARN' }
    }
    return $script:CapCache
}
""", """$script:CapReadFailed = $false
$script:CapWarned = $false
# Bilesen kurulu mu? Yeniden baslatma bekleyen kurulum kurulu, bekleyen kaldirma kurulu degil sayilir.
function Test-CapOn([string]$State) { return (@('Installed', 'InstallPending') -contains $State) }
function Read-CapListFresh {
    $script:CapReadFailed = $false
    try { return , @(Get-WindowsCapability -Online -ErrorAction Stop) }
    catch {
        $script:CapReadFailed = $true
        if (-not $script:CapWarned) { $script:CapWarned = $true; Write-WhLog ('Bileşen listesi okunamadı: ' + $_.Exception.Message) 'WARN' }
        return , @()
    }
}
# Toplu durum olcumu partisinde liste bir kez okunur; parti disinda ve gercek uygulamada her okuma tazedir.
function Get-CapList {
    $b = $script:StateBatch
    if ($null -ne $b -and $script:Preview) {
        if ($null -eq $b.Caps) { $b.Caps = Read-CapListFresh; $b.CapsFailed = $script:CapReadFailed }
        $script:CapReadFailed = [bool]$b.CapsFailed
        return $b.Caps
    }
    return (Read-CapListFresh)
}
""", name='p80 bilesen listesi')
    b.rep("""        $isOn = ([string]$c.State -eq 'Installed')
        if ($isOn -ne $wantAbsent) { Add-Skip (('Windows bile' + [char]0x015F + 'eni zaten uygun: ') + [string]$c.Name); continue }
""", """        $isOn = Test-CapOn ([string]$c.State)
        if ($isOn -ne $wantAbsent) { Add-Skip (('Windows bile' + [char]0x015F + 'eni zaten uygun: ') + [string]$c.Name); continue }
""", name='p80 bekleyen durum')
    b.rep("""    if ($null -eq $script:StateBatch) { $script:StateBatch = @{ Depth = 0; Mp = $null; Tasks = $null; TasksOk = $false } }
""", """    if ($null -eq $script:StateBatch) { $script:StateBatch = @{ Depth = 0; Mp = $null; Tasks = $null; TasksOk = $false; Caps = $null; CapsFailed = $false } }
""", name='p80 parti')
    b.rep("""    $script:FreedBytes = 0.0; $script:Provisioned = $null
}
""", """    $script:FreedBytes = 0.0; $script:Provisioned = $null; $script:CapWarned = $false
}
""", name='p80 sayaclar')
