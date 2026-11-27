# ==================================================================
#  OEM KODLAMA VE KÜLTÜR SINAMASI (çekirdek)
#  Türkçe ve Azerice kültürde .NET Framework düzenli ifadeleri büyük “I” harfini [A-Za-z] ile eşleştirmez:
#  “Input” -match '^[A-Za-z]+$' ve “INTEL” -match 'intel' yanlış çıkar, bilgisayar adındaki I silinir, I: sürücüsü reddedilir.
#  Set-MmCulture (betiğin başında tanımlıdır) sayı ve tarih biçimini kullanıcının kültüründen alıp büyük/küçük harf
#  kuralını değişmez kültürden alır. Bu dosya: konsol programlarının çıktı kodlaması ve korumanın sınaması.
# ==================================================================

# Sistemin OEM kod sayfası (konsol programlarının çıktı kodlaması). Kullanıcının bölgesel kültürüne değil işletim sistemi ayarına bakar;
# kayıt defteri okunamazsa yüklü arayüz dilinin OEM sayfasına, o da olmazsa 437'ye düşer.
function Get-OemEncoding {
    if ($null -ne $script:OemEnc) { return $script:OemEnc }
    $cp = 0
    try {
        $v = (Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage' -Name 'OEMCP' -ErrorAction Stop).OEMCP
        [void][int]::TryParse([string]$v, [ref]$cp)
    } catch { $cp = 0 }
    if ($cp -le 0) { try { $cp = [int][System.Globalization.CultureInfo]::InstalledUICulture.TextInfo.OEMCodePage } catch { $cp = 0 } }
    $enc = $null
    if ($cp -gt 0) { try { $enc = [System.Text.Encoding]::GetEncoding($cp) } catch { $enc = $null } }
    if ($null -eq $enc) { try { $enc = [System.Text.Encoding]::GetEncoding(437) } catch { $enc = [System.Text.Encoding]::UTF8 } }
    $script:OemEnc = $enc
    return $enc
}

# Kültür sınaması: Türkçe “I/ı” yüzünden bozulabilecek eşleşmeleri dener. Dönüş: @{ Ok; Bad; Culture; Upper }
# Ana iş parçacığında da arka plan çalışma alanında da aynı sonuç beklenir (Set-MmCulture her ikisinde de çağrılır).
function Test-MmCultureProbe {
    param($P = $null)
    $bad = New-Object System.Collections.ArrayList
    try {
        if (-not ('Input' -match '^[A-Za-z]+$')) { [void]$bad.Add('[A-Za-z] ile büyük I') }
        if (-not ('INTEL' -match 'intel') -or -not ('intel' -match 'INTEL')) { [void]$bad.Add('INTEL / intel') }
        if (-not ('NVIDIA GeForce' -match '^nvidia ')) { [void]$bad.Add('NVIDIA / nvidia') }
        if (-not ('I:\Yedek' -match '^[A-Za-z]:\\')) { [void]$bad.Add('I: sürücü harfi') }
        if (-not ('INFO  basladi' -match '^[A-Z]+\s')) { [void]$bad.Add('günlük düzeyi INFO') }
        if (('OFIS-PC' -replace '[^A-Za-z0-9\-_]', '') -cne 'OFIS-PC') { [void]$bad.Add('bilgisayar adı temizleme') }
        if (-not [regex]::IsMatch('Info', '(?i)^[a-z]+$')) { [void]$bad.Add('(?i) ile [a-z]') }
        if ((([string]'I').ToLower() -cne 'i') -or (([string]'i').ToUpper() -cne 'I')) { [void]$bad.Add('ToLower / ToUpper') }
        # @{} tabloları: Windows PowerShell 5.1 anahtar karşılaştırıcısını süreç başında, kullanıcının kültürüyle bir kez kurar ve saklar;
        # iş parçacığı kültürü bunu değiştirmez (Türkçede @{ Info = 1 }['info'] boş döner). Bu yüzden anahtarlar ToLowerInvariant() ile
        # normalleştirilir (ToLower() ile aynı sonucu vermelidir) ve harf boyu değişebilen dış metinler açık karşılaştırıcılı tabloda tutulur.
        $h = @{}
        $h[([string]'INFO').ToLowerInvariant()] = 1
        $h[([string]'Input').ToLower()] = 2
        if ($h[([string]'Info').ToLowerInvariant()] -ne 1 -or -not $h.ContainsKey(([string]'INPUT').ToLowerInvariant())) { [void]$bad.Add('sözlük anahtarı normalleştirme') }
        $t = New-Object System.Collections.Hashtable ([System.StringComparer]::OrdinalIgnoreCase)
        $t['Info'] = 1
        if ($t['info'] -ne 1 -or -not $t.ContainsKey('INFO')) { [void]$bad.Add('açık karşılaştırıcılı tablo') }
    } catch { [void]$bad.Add('sınama hatası: ' + $_.Exception.Message) }
    $cn = ''
    try { $cn = [string][System.Threading.Thread]::CurrentThread.CurrentCulture.Name } catch { $cn = '' }
    return @{ Ok = ($bad.Count -eq 0); Bad = @($bad.ToArray()); Culture = $cn; Upper = ([string]'i').ToUpper() }
}
