# -*- coding: utf-8 -*-
"""p79: Magaza uygulamasi kaldirma basariliyken hata gostermez; Microsoft 365 Copilot adi; disk optimizasyonu disk turunu okur.

Gercek bilgisayardaki tam denetimde (18.11.2026) Microsoft.MicrosoftOfficeHub tum kullanicilardan kaldirildi ama islem
"Sistem belirtilen yolu bulamiyor" hatasiyla bitti ve "kaldirildi" satiri yazilmadi. Hata, yeni hesaplara otomatik kurulum
kaydinin (provisioned package) silinmesinden geliyordu: kaydin dosyalari zaten yoktu ve DISM, SilentlyContinue'ya ragmen
sonlandirici hata atti. Artik:
  - her paket ayri kaldirilir; kaldirma hata verse bile paket artik hicbir kullanicida kurulu degilse basarili sayilir,
    gercekten kalan paket varsa hangi paketin neden kalmadigi yazilir;
  - otomatik kurulum kaydi silinemezse uygulama kaldirma basarisiz sayilmaz: dosyalari zaten silinmisse bilgi,
    baska bir nedenle kalmissa uyari yazilir; oturumdaki kayit listesi tazelenir.
Microsoft.MicrosoftOfficeHub uygulamasinin adi guncellendi: Microsoft 2025'te "Office" uygulamasinin adini
"Microsoft 365 Copilot" yapti; liste artik Word, Excel ve PowerPoint'in kaldirilmadigini da soyler.
Disk optimizasyonu disk turunu hic atanmayan $sync.DiskType'tan okuyordu (her zaman "Unknown"); artik sistem profilinden
okur: SSD'de TRIM, HDD'de birlestirme acikca secilir, onizleme dogru disk turunu gosterir."""


def apply(b):
    b.before("function Invoke-AppxOp($Op) {\n", """# Paket hala bir kullanicida kurulu mu? Kaldirma hata verse de paket cogu zaman gitmistir. Okunamazsa "kurulu" sayilir.
function Test-AppxStillThere([string]$Name, [string]$Full) {
    $all = $null
    try { $all = @(Get-AppxPackage -AllUsers -Name $Name -ErrorAction Stop) } catch { $all = $null }
    if ($null -eq $all) {
        try { $all = @(Get-AppxPackage -Name $Name -ErrorAction Stop) } catch { return $true }
    }
    foreach ($x in $all) {
        if ([string]$x.PackageFullName -ne $Full) { continue }
        $pui = @($x.PackageUserInformation | Where-Object { $null -ne $_ })
        if ($pui.Count -eq 0) { return $true }
        foreach ($u in $pui) { if ([string]$u.InstallState -eq 'Installed') { return $true } }
    }
    return $false
}

# Hata "yol bulunamadi" (0x80070003) mi? DISM ve Appx hatalari ic ice gelebilir; dile bagli ileti yerine kod denetlenir.
function Test-PathNotFoundError($Ex) {
    $e = $Ex
    while ($null -ne $e) {
        if ([int]$e.HResult -eq -2147024893) { return $true }
        if ([string]$e.Message -match '0x80070003') { return $true }
        $e = $e.InnerException
    }
    return $false
}

""")
    b.rep("""    Add-Journal @{ T = 'Appx'; Name = $name; Locs = $locs; Full = $fulls }
    foreach ($p in $keepP) {
        try { Remove-AppxPackage -Package $p.PackageFullName -AllUsers -ErrorAction Stop }
        catch { Remove-AppxPackage -Package $p.PackageFullName -ErrorAction Stop }
    }
    foreach ($pp in $keepV) { Remove-AppxProvisionedPackage -Online -PackageName $pp.PackageName -ErrorAction SilentlyContinue | Out-Null }
    Add-Done (('Uygulama kald' + [char]0x0131 + 'r' + [char]0x0131 + 'ld' + [char]0x0131 + ': ') + $name)
}
""", """    Add-Journal @{ T = 'Appx'; Name = $name; Locs = $locs; Full = $fulls }
    $fail = New-Object System.Collections.ArrayList
    foreach ($p in $keepP) {
        $full = [string]$p.PackageFullName
        $err = ''
        try { Remove-AppxPackage -Package $full -AllUsers -ErrorAction Stop }
        catch {
            $err = $_.Exception.Message
            try { Remove-AppxPackage -Package $full -ErrorAction Stop; $err = '' } catch { $err = $_.Exception.Message }
        }
        if ($err -ne '' -and (Test-AppxStillThere ([string]$p.Name) $full)) { [void]$fail.Add($full + ': ' + $err) }
    }
    foreach ($pp in $keepV) {
        $pn = [string]$pp.PackageName
        try { Remove-AppxProvisionedPackage -Online -PackageName $pn -ErrorAction Stop | Out-Null }
        catch {
            if (Test-PathNotFoundError $_.Exception) { Write-WhLog ('Yeni hesaplara otomatik kurulum kaydının dosyaları zaten silinmiş; uygulama yeni hesaplara kurulmaz: ' + $pn) 'INFO' }
            else { Write-WhLog ('Uygulamanın yeni hesaplara otomatik kurulum kaydı kaldırılamadı (' + $pn + '): ' + $_.Exception.Message) 'WARN' }
        }
    }
    if ($keepV.Count -gt 0 -and $null -ne $script:Provisioned) {
        $gone = @($keepV | ForEach-Object { [string]$_.PackageName })
        $script:Provisioned = @($script:Provisioned | Where-Object { $gone -notcontains [string]$_.PackageName })
    }
    if ($fail.Count -gt 0) { throw ('Uygulama kaldırılamadı (' + $name + '): ' + ($fail.ToArray() -join '; ')) }
    Add-Done (('Uygulama kald' + [char]0x0131 + 'r' + [char]0x0131 + 'ld' + [char]0x0131 + ': ') + $name)
}
""", name='p79 appx kaldirma')
    b.rep("""    @{ P = 'Microsoft.MicrosoftOfficeHub';           R = $true;  C = $false; N = ('Microsoft 365 (Office) tan' + [char]0x0131 + 't' + [char]0x0131 + 'm uygulamas' + [char]0x0131) },
""", """    @{ P = 'Microsoft.MicrosoftOfficeHub';           R = $true;  C = $false; N = 'Microsoft 365 Copilot uygulaması (eski adı Office; Word, Excel ve PowerPoint kaldırılmaz)' },
""", name='p79 office hub adi')
    b.rep("""    $dt = 'Unknown'
    try { $dt = [string]$sync.DiskType } catch { }
""", """    $dt = ''
    try { $dt = [string]$sync.Profile.DiskType } catch { }
    if ([string]::IsNullOrEmpty($dt)) { try { $dt = [string]$sync.DiskType } catch { } }
""", name='p79 disk turu')
