. "$PSScriptRoot/lib.ps1"
# Yardımcılar (mods\150_kit_core.ps1, 151_kit_ui.ps1, patches\p65_yardimcilar.py): parola üretici, toplu yeniden adlandırma (gerçek geçici dosyalarla),
# karne, internete bağlanan programlar, lisans bilgisi ve alternatif önerici, Firefox ilkeleri, yardım paketi, yeni bilgisayar adımları, şifreleme yolu.
Import-Fn 'Get-PasswordSets', 'Get-PasswordBits', 'Get-PasswordStrengthText', 'Get-NextPwLength',
    'Get-SafeFileName', 'Split-FileName', 'Get-RenamePlan', 'Test-RenameDirAllowed', 'Job_RenameScan', 'Invoke-RenamePairs', 'Invoke-RenameOp', 'Undo-RenameItem',
    'Get-ScoreDelta', 'Format-Signed', 'Format-ScoreLine', 'Get-ScoreSummary', 'Add-ScoreEntry', 'Read-ScoreEntries', 'Get-ScoreFile', 'Start-ScoreMeasure', 'Complete-ScoreMeasure',
    'Test-PrivateAddress', 'Get-NetTalkers', 'Get-FossMeta', 'Get-FossLicenseText', 'Test-FossHidden', 'Get-AltSuggestions',
    'Protect-SupportText', 'Get-SupportSettings', 'Get-SetupSteps', 'Test-HomeEdition', 'Get-BlEnableRoute', 'ConvertTo-Hashtable', 'Get-CatalogItem'
Import-Var 'PwCharSets', 'PwLengths', 'RenameModes', 'RenameMax', 'FossMeta', 'AltRules', 'SupportDropKeys', 'ScoreKeep'
$src = [System.IO.File]::ReadAllText($script:TestPath)

# ======================= 1) parola üretici =======================
# Üreteç eklentidedir (kriptografik üreteç ana betikte bulunmaz); küme seçimi ve güç hesabı ana betiktedir.
Assert-True (-not $src.Contains('function New-RandomPassword')) 'üreteç ana betikte değil'
Assert-True ($src.Contains("Import-MmExt 'Parola'")) 'üretmeden önce eklenti yüklenir (özet denetimiyle)'
. (Join-Path (Join-Path $script:TestDir 'Eklenti') 'Parola.ps1')
$all = Get-PasswordSets $true $true $true
Assert-Eq $all.Count 4 'dört küme'
Assert-Eq (Get-PasswordSets $false $false $false).Count 1 'yalnızca küçük harf'
$amb = '0Oo1lI'
foreach ($k in @($script:PwCharSets.Keys)) { foreach ($c in $amb.ToCharArray()) { Assert-True (-not ([string]$script:PwCharSets[$k]).Contains([string]$c)) ("karışan karakter yok: $k / $c") } }
$seen = @{}
for ($i = 0; $i -lt 200; $i++) {
    $p = New-RandomPassword 20 $all
    if ($p.Length -ne 20) { Assert-True $false 'uzunluk 20' }
    if ($p -cnotmatch '[a-z]' -or $p -cnotmatch '[A-Z]' -or $p -cnotmatch '\d' -or $p -cnotmatch '[!#$%&*+\-=?@_]') { Assert-True $false ('her kümeden en az bir karakter: ' + $p) }
    $seen[$p] = $true
}
Assert-Eq $seen.Count 200 '200 parola birbirinden farklı'
$p = New-RandomPassword 16 (Get-PasswordSets $false $false $false)
Assert-True ($p -cmatch '^[a-z]{16}$') 'yalnızca küçük harf seçilirse başka karakter gelmez'
$p = New-RandomPassword 12 (Get-PasswordSets $true $true $false)
Assert-True ($p -cmatch '^[A-Za-z0-9]{12}$') 'simge kapalıyken simge yok'
Assert-Eq (New-RandomPassword 3 $all).Length 8 'en kısa uzunluk 8'
Assert-Eq (New-RandomPassword 500 $all).Length 64 'en uzun uzunluk 64'
$threw = $false
try { [void](New-RandomPassword 20 @()) } catch { $threw = $true }
Assert-True $threw 'küme yoksa hata'
$first = @{}
for ($i = 0; $i -lt 300; $i++) { $c = (New-RandomPassword 20 $all)[0]; if ($c -cmatch '[a-z]') { $first['l'] = 1 } elseif ($c -cmatch '[A-Z]') { $first['u'] = 1 } elseif ($c -match '\d') { $first['d'] = 1 } else { $first['s'] = 1 } }
Assert-Eq $first.Count 4 'zorunlu karakterler başta sabit kalmaz (karıştırılır)'
$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$hist = @(0, 0, 0, 0, 0, 0, 0)
for ($i = 0; $i -lt 7000; $i++) { $hist[(Get-SecureIndex $rng 7)]++ }
Assert-True ((@($hist | Where-Object { $_ -lt 800 -or $_ -gt 1200 })).Count -eq 0) 'rastgele dizin eşit dağılır (7 kova, 7000 çekiliş)'
Assert-Eq (Get-SecureIndex $rng 1) 0 'tek seçenekte dizin 0'
Assert-Eq (Get-PasswordBits 20 $true $true $true) 121 'entropi: 20 karakter, 68 simgelik havuz'
Assert-Eq (Get-PasswordBits 8 $false $false $false) 36 'entropi: 8 küçük harf'
Assert-Eq (Get-PasswordStrengthText 36) 'zayıf' 'güç: zayıf'
Assert-Eq (Get-PasswordStrengthText 79) 'iyi' 'güç: iyi'
Assert-Eq (Get-PasswordStrengthText 100) 'güçlü' 'güç: güçlü'
Assert-Eq (Get-PasswordStrengthText 121) 'çok güçlü' 'güç: çok güçlü'
Assert-Eq (Get-NextPwLength 20) 24 'sonraki uzunluk'
Assert-Eq (Get-NextPwLength 32) 12 'son uzunluktan sonra başa döner'

# ======================= 2) yeniden adlandırma planı =======================
Assert-Eq (Get-SafeFileName 'a<b>:c|d?.txt. ') 'abcd.txt' 'geçersiz karakterler ve sondaki nokta atılır'
$sp = Split-FileName 'rapor.son.pdf'
Assert-True ($sp.Stem -eq 'rapor.son' -and $sp.Ext -eq '.pdf') 'uzantı son noktadan ayrılır'
$sp = Split-FileName '.gitignore'
Assert-True ($sp.Stem -eq '.gitignore' -and $sp.Ext -eq '') 'noktayla başlayan ad uzantı sayılmaz'
$items = @(@{ Name = 'IMG_3.jpg'; Time = [datetime]'2026-05-03' }, @{ Name = 'IMG_1.jpg'; Time = [datetime]'2026-05-01' }, @{ Name = 'IMG_2.JPG'; Time = [datetime]'2026-05-02' })
$names = @($items | ForEach-Object { $_.Name })
$pl = Get-RenamePlan $items 'Number' 'Tatil' $names
Assert-Eq $pl.Changes 3 'numara: üç dosya değişir'
Assert-Eq (@($pl.Rows | ForEach-Object { $_.Old + '>' + $_.New }) -join ';') 'IMG_1.jpg>Tatil 01.jpg;IMG_2.JPG>Tatil 02.JPG;IMG_3.jpg>Tatil 03.jpg' 'numara: ada göre sıra, uzantı korunur'
Assert-Eq $pl.Problems 0 'numara: çakışma yok'
Assert-Eq (Get-RenamePlan $items 'Number' '' $names).Rows[0].New 'Dosya 01.jpg' 'numara: temel ad boşsa "Dosya"'
$pl = Get-RenamePlan $items 'Replace' 'img_=>Foto ' $names
Assert-Eq $pl.Rows[0].New 'Foto 1.jpg' 'değiştir: büyük/küçük harfe duyarsız'
$pl = Get-RenamePlan $items 'Replace' 'IMG_=>' $names
Assert-Eq $pl.Rows[2].New '3.jpg' 'değiştir: sağ taraf boşsa metin silinir'
Assert-True ((Get-RenamePlan $items 'Replace' 'yanlis' $names).Error -ne '') 'değiştir: biçim hatası bildirilir'
Assert-Eq (Get-RenamePlan @(@{ Name = 'a$1.txt'; Time = (Get-Date) }) 'Replace' 'a=>$0b' @('a$1.txt')).Rows[0].New '$0b$1.txt' 'değiştir: $ işaretleri düz metindir'
$pl = Get-RenamePlan $items 'DatePrefix' '' $names
Assert-Eq $pl.Rows[0].New '2026-05-01 IMG_1.jpg' 'tarih: başa eklenir'
Assert-Eq (Get-RenamePlan @(@{ Name = '2026-05-01 a.txt'; Time = [datetime]'2026-05-01' }) 'DatePrefix' '' @()).Changes 0 'tarih: zaten varsa yinelenmez'
$pl = Get-RenamePlan $items 'Lower' '' $names
Assert-True ($pl.Changes -eq 3 -and $pl.Rows[1].New -ceq 'img_2.jpg') 'küçük harf: yalnızca harf büyüklüğü de değişiklik sayılır'
Assert-Eq (Get-RenamePlan @(@{ Name = 'yaz  tatili_2026 son.docx'; Time = (Get-Date) }) 'Dash' '' @()).Rows[0].New 'yaz-tatili-2026-son.docx' 'tire: boşluk ve alt çizgi tek tire olur'
# sorunlar
$dup = @(@{ Name = 'a b.txt'; Time = (Get-Date) }, @{ Name = 'a_b.txt'; Time = (Get-Date) })
$pl = Get-RenamePlan $dup 'Dash' '' @('a b.txt', 'a_b.txt')
Assert-True ($pl.Problems -eq 2 -and $pl.Rows[0].Problem -like 'aynı ad*') 'aynı ada düşen dosyalar sorun olarak işaretlenir'
$pl = Get-RenamePlan @(@{ Name = 'A.TXT'; Time = (Get-Date) }) 'Replace' 'A=>b' @('A.TXT', 'b.txt')
Assert-True ($pl.Problems -eq 1 -and $pl.Rows[0].Problem -like 'klasörde bu adda*') 'klasörde kalan dosyayla çakışma işaretlenir'
$pl = Get-RenamePlan @(@{ Name = 'x.txt'; Time = (Get-Date) }, @{ Name = 'y.txt'; Time = (Get-Date) }) 'Number' 'x' @('x.txt', 'y.txt', 'x 01.txt')
Assert-Eq $pl.Problems 1 'var olan "x 01.txt" ile çakışma'
$pl = Get-RenamePlan @(@{ Name = 'abc.txt'; Time = (Get-Date) }) 'Replace' 'abc=>' @('abc.txt')
Assert-True ($pl.Rows[0].Problem -eq 'ad boş kalıyor') 'ad boş kalırsa sorun'
Assert-True ((Get-RenamePlan $items 'Yok' '' $names).Error -ne '') 'bilinmeyen tür reddedilir'
# ad değiş tokuşu çakışma sayılmaz (iki aşamalı uygulama bunu kaldırır)
$sw = @(@{ Name = 'a 1.txt'; Time = (Get-Date) }, @{ Name = 'a-1.txt.bak'; Time = (Get-Date) })
Assert-Eq (Get-RenamePlan @(@{ Name = 'b.txt'; Time = (Get-Date) }, @{ Name = 'a.txt'; Time = (Get-Date) }) 'Number' 'x' @('a.txt', 'b.txt')).Problems 0 'yeniden adlandırılan dosyaların eski adları engel değildir'

# ======================= 3) klasör koruması =======================
$env:WINDIR = 'C:\Windows'; $env:ProgramFiles = 'C:\Program Files'; $env:ProgramData = 'C:\ProgramData'
Assert-True ((Test-RenameDirAllowed 'C:\Windows\System32') -ne '') 'Windows klasörü reddedilir'
Assert-True ((Test-RenameDirAllowed 'c:\program files\Uygulama') -ne '') 'Program Files reddedilir'
Assert-True ((Test-RenameDirAllowed 'D:\') -ne '') 'sürücü kökü reddedilir'
Assert-True ((Test-RenameDirAllowed '') -ne '') 'boş yol reddedilir'
Assert-Eq (Test-RenameDirAllowed 'D:\Fotolar\2026') '' 'kullanıcı klasörü kabul edilir'
Assert-Eq (Test-RenameDirAllowed 'C:\WindowsEski') '' 'adı benzeyen klasör engellenmez'

# ======================= 4) gerçek dosyalarla uygula ve geri al =======================
$script:Log = New-Object System.Collections.ArrayList; $script:Jr = New-Object System.Collections.ArrayList; $script:Errs = 0
function Add-Skip([string]$m) { [void]$script:Log.Add('SKIP ' + $m) }
function Add-Plan([string]$m) { [void]$script:Log.Add('PLAN ' + $m) }
function Add-Done([string]$m) { [void]$script:Log.Add('OK ' + $m) }
function Add-Err([string]$m) { $script:Errs++; [void]$script:Log.Add('ERR ' + $m) }
function Add-Journal($i) { [void]$script:Jr.Add($i) }
function Write-WhLog([string]$m, [string]$l) { [void]$script:Log.Add($l + ' ' + $m) }
$td = Join-Path ([System.IO.Path]::GetTempPath()) ('mm-ren-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $td -Force)
foreach ($n in @('b.txt', 'a.txt', 'c.txt')) { [System.IO.File]::WriteAllText((Join-Path $td $n), ('icerik ' + $n)) }
[void](New-Item -ItemType Directory -Path (Join-Path $td 'alt') -Force)
$sc = Job_RenameScan @{ Dir = $td }
Assert-True ($sc.Ok -and @($sc.Items).Count -eq 3) 'tarama: üç dosya (alt klasör sayılmaz)'
# değiş tokuş: a->b, b->c, c->a (zincir; tek aşamada çakışırdı)
$pairs = @(@{ Old = 'a.txt'; New = 'b.txt' }, @{ Old = 'b.txt'; New = 'c.txt' }, @{ Old = 'c.txt'; New = 'a.txt' })
$script:Preview = $true
Invoke-RenameOp @{ T = 'Rename'; Dir = $td; Pairs = $pairs }
Assert-True (@($script:Log | Where-Object { $_ -like 'PLAN a.txt*b.txt' }).Count -eq 1) 'önizleme: eski → yeni satırı'
Assert-Eq ([System.IO.File]::ReadAllText((Join-Path $td 'a.txt'))) 'icerik a.txt' 'önizleme dosyaya dokunmaz'
Assert-Eq $script:Jr.Count 0 'önizleme günlüğe yazmaz'
$script:Preview = $false; $script:Log.Clear()
Invoke-RenameOp @{ T = 'Rename'; Dir = $td; Pairs = $pairs }
Assert-Eq ([System.IO.File]::ReadAllText((Join-Path $td 'b.txt'))) 'icerik a.txt' 'uygula: a.txt -> b.txt'
Assert-Eq ([System.IO.File]::ReadAllText((Join-Path $td 'c.txt'))) 'icerik b.txt' 'uygula: b.txt -> c.txt'
Assert-Eq ([System.IO.File]::ReadAllText((Join-Path $td 'a.txt'))) 'icerik c.txt' 'uygula: c.txt -> a.txt (zincir çakışmadan)'
Assert-Eq @(Get-ChildItem -LiteralPath $td -File).Count 3 'geçici ad kalmadı, dosya kaybı yok'
Assert-True ($script:Jr.Count -eq 1 -and [string]$script:Jr[0].T -eq 'Rename' -and @($script:Jr[0].Pairs).Count -eq 3) 'günlük: tek kayıt, üç çift'
Undo-RenameItem $script:Jr[0]
foreach ($n in @('a.txt', 'b.txt', 'c.txt')) { Assert-Eq ([System.IO.File]::ReadAllText((Join-Path $td $n))) ('icerik ' + $n) ("geri al: $n eski içeriğinde") }
# hedef kilitliyse (var olan klasör adı): o dosya eski adında kalır, diğerleri sürer
$script:Jr.Clear(); $script:Errs = 0
Invoke-RenameOp @{ T = 'Rename'; Dir = $td; Pairs = @(@{ Old = 'a.txt'; New = 'alt' }, @{ Old = 'b.txt'; New = 'bb.txt' }) }
Assert-True ((Test-Path -LiteralPath (Join-Path $td 'a.txt')) -and (Test-Path -LiteralPath (Join-Path $td 'bb.txt'))) 'başarısız dosya eski adına döner, diğeri değişir'
Assert-Eq $script:Errs 1 'başarısız dosya hata olarak sayılır'
Assert-Eq @($script:Jr[0].Pairs).Count 1 'günlüğe yalnızca başarılı çift yazılır'
# kaynak yoksa: hiçbir dosya değişmez
$threw = ''
try { Invoke-RenameOp @{ T = 'Rename'; Dir = $td; Pairs = @(@{ Old = 'c.txt'; New = 'cc.txt' }, @{ Old = 'yok.txt'; New = 'z.txt' }) } } catch { $threw = $_.Exception.Message }
Assert-True ($threw -like 'Yeniden adlandırma başlatılamadı*' -and (Test-Path -LiteralPath (Join-Path $td 'c.txt'))) 'ilk aşama başarısızsa her şey eski adında kalır'
$threw = ''
try { Invoke-RenameOp @{ T = 'Rename'; Dir = 'C:\Windows\System32'; Pairs = $pairs } } catch { $threw = $_.Exception.Message }
Assert-True ($threw -ne '') 'sistem klasöründe işlem reddedilir'
Remove-Item -LiteralPath $td -Recurse -Force -ErrorAction SilentlyContinue
Assert-True ($src.Contains("`$script:MoreOps['Rename'] = 'Invoke-RenameOp'") -and $src.Contains("`$script:MoreUndo['Rename'] = 'Undo-RenameItem'")) 'işlem ve geri alma plan motoruna kayıtlı'

# ======================= 5) karne =======================
$a = @{ Time = '2026-11-14T10:00:00'; Svc = 142; Proc = 201; FreeMb = 6100; DiskFreeGb = 120.0 }
$b = @{ Time = '2026-11-14T10:01:00'; Svc = 139; Proc = 196; FreeMb = 6400; DiskFreeGb = 122.0 }
$d = Get-ScoreDelta $a $b
Assert-True ($d.Svc -eq -3 -and $d.Proc -eq -5 -and $d.FreeMb -eq 300 -and $d.DiskFreeGb -eq 2.0) 'fark hesaplanır'
Assert-Eq (Format-Signed -3) ([string][char]0x2212 + '3') 'eksi işareti'
Assert-Eq (Format-Signed 2.5 ' GB') '+2,5 GB' 'artı ve ondalık virgül'
Assert-Eq (Format-Signed 0) '0' 'sıfır'
$line = Format-ScoreLine $a $b
Assert-True ($line.StartsWith('çalışan hizmet 142 ' + [char]0x2192 + ' 139 (' + [char]0x2212 + '3)') -and $line.Contains('boş bellek 6100 ' + [char]0x2192 + ' 6400 MB (+300)')) 'karne satırı'
$a2 = @{ Time = 'x'; Svc = -1; Proc = 10; FreeMb = -1; DiskFreeGb = -1 }
Assert-Eq (Format-ScoreLine $a2 @{ Time = 'y'; Svc = 5; Proc = 12; FreeMb = 100; DiskFreeGb = 3 }) ('işlem 10 ' + [char]0x2192 + ' 12 (+2)') 'ölçülemeyen değer satıra girmez'
$script:DataDir = Join-Path ([System.IO.Path]::GetTempPath()) ('mm-karne-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $script:DataDir -Force)
$script:ScoreKeep = 5
for ($i = 1; $i -le 7; $i++) { [void](Add-ScoreEntry ('işlem ' + $i) $a $b $i) }
$en = Read-ScoreEntries 60
Assert-Eq $en.Count 5 'en fazla ScoreKeep kayıt tutulur'
Assert-Eq ([string]$en[0].Label) 'işlem 7' 'en yeni kayıt başta'
Assert-Eq ([int]$en[4].Changes) 3 'en eski kayıt atılır'
Assert-Eq (Read-ScoreEntries 2).Count 2 'istenen kadar kayıt döner'
[System.IO.File]::AppendAllText((Get-ScoreFile), "bozuk satir`n")
Assert-Eq (Read-ScoreEntries 60).Count 5 'bozuk satır atlanır'
$sum = Get-ScoreSummary @(@{ Changes = 4; A = $a; B = $b }, @{ Changes = 1; A = $a; B = @{ Time = '2026-10-01T10:00:00'; Svc = 142; Proc = 1; FreeMb = 1; DiskFreeGb = 125.0 } }) 7 ([datetime]'2026-11-15')
Assert-True ($sum.Count -eq 1 -and $sum.Changes -eq 4 -and $sum.Svc -eq -3 -and $sum.DiskFreeGb -eq 2.0) 'özet: yalnızca son 7 gün'
# ölçüm kancası: değişiklik yoksa kayıt yok
function Get-ScoreSnapshot { return @{ Time = (Get-Date).ToString('s'); Svc = 100; Proc = 50; FreeMb = 1000; DiskFreeGb = 10.0 } }
Remove-Item -LiteralPath (Get-ScoreFile) -Force
$script:Preview = $false; $script:Changes = 0
Start-ScoreMeasure; Complete-ScoreMeasure 'boş plan'
Assert-True (-not (Test-Path -LiteralPath (Get-ScoreFile))) 'değişiklik yoksa karne kaydı yazılmaz'
$script:Changes = 3
Start-ScoreMeasure; Complete-ScoreMeasure 'gizlilik ayarları'
Assert-Eq (Read-ScoreEntries 10).Count 1 'değişiklik varsa kayıt yazılır'
$script:Preview = $true
Start-ScoreMeasure; Complete-ScoreMeasure 'önizleme'
Assert-Eq (Read-ScoreEntries 10).Count 1 'önizlemede ölçüm yapılmaz'
Remove-Item -LiteralPath $script:DataDir -Recurse -Force -ErrorAction SilentlyContinue
Assert-True ($src.Contains("    Start-ScoreMeasure`n") -or $src.Contains("    Start-ScoreMeasure`r`n")) 'Invoke-Plan ölçümü başlatır'
Assert-True ($src.Contains('Complete-ScoreMeasure ([string]$steps[0].Title)')) 'Invoke-Plan ölçümü tamamlar'

# ======================= 6) internete bağlanan programlar =======================
foreach ($ip in @('127.0.0.1', '::1', '10.1.2.3', '192.168.1.5', '172.16.0.9', '172.31.255.1', '169.254.3.3', 'fe80::1', 'fd00::5', '100.64.0.1', '0.0.0.0')) { Assert-True (Test-PrivateAddress $ip) ("yerel adres: $ip") }
foreach ($ip in @('8.8.8.8', '172.32.0.1', '172.15.0.1', '100.128.0.1', '2a00:1450::200e', '193.140.1.1')) { Assert-True (-not (Test-PrivateAddress $ip)) ("genel adres: $ip") }
$conns = @(@{ Pid = 10; Remote = '8.8.8.8'; Port = 443 }, @{ Pid = 10; Remote = '8.8.4.4'; Port = 443 }, @{ Pid = 11; Remote = '1.1.1.1'; Port = 80 }, @{ Pid = 12; Remote = '192.168.1.1'; Port = 445 },
    @{ Pid = 13; Remote = '9.9.9.9'; Port = 443 }, @{ Pid = 14; Remote = '8.8.8.8'; Port = 443 }, @{ Pid = 99; Remote = '4.4.4.4'; Port = 53 })
$procs = @{ '10' = @{ Name = 'brave'; Path = 'C:\P\brave.exe' }; '11' = @{ Name = 'app'; Path = 'C:\P\app.exe' }; '12' = @{ Name = 'lan'; Path = 'C:\P\lan.exe' }; '13' = @{ Name = 'brave'; Path = 'C:\P\BRAVE.EXE' }; '14' = @{ Name = 'svchost'; Path = '' } }
$tk = @(Get-NetTalkers $conns $procs)
Assert-Eq $tk.Count 4 'yalnızca internete bağlananlar; aynı program tek satır'
Assert-True ($tk[0].Name -eq 'brave' -and $tk[0].Count -eq 3 -and $tk[0].Hosts -eq 3) 'aynı yolun işlemleri birleşir, en çok bağlanan başta'
Assert-True (@($tk | Where-Object { $_.Name -eq 'lan' }).Count -eq 0) 'yalnızca yerel ağa bağlanan program listelenmez'
Assert-True (@($tk | Where-Object { $_.Name -eq 'PID 99' }).Count -eq 1) 'işlem bilgisi yoksa PID ile gösterilir'
Assert-True (@($tk | Where-Object { $_.Name -eq 'svchost' -and $_.Path -eq '' }).Count -eq 1) 'yolu okunamayan işlem adıyla gruplanır'
Assert-Eq @(Get-NetTalkers @() @{}).Count 0 'bağlantı yoksa boş liste'

# ======================= 7) lisans ve alternatifler =======================
Assert-Eq (Get-FossLicenseText '7zip.7zip') 'Açık kaynak (LGPL-2.1)' 'lisans metni: açık kaynak'
Assert-True ((Get-FossLicenseText 'voidtools.Everything').StartsWith('Kapalı kaynak')) 'lisans metni: kapalı kaynak'
Assert-Eq (Get-FossLicenseText 'Bilinmeyen.Arac') '' 'bilinmeyen araçta ek yok'
Assert-True (Test-FossHidden @{ Id = 'Microsoft.Sysinternals.Autoruns' } $true) 'süzgeç açık: kapalı kaynaklı araç gizlenir'
Assert-True (-not (Test-FossHidden @{ Id = 'Microsoft.Sysinternals.Autoruns' } $false)) 'süzgeç kapalı: gizlenmez'
Assert-True (-not (Test-FossHidden @{ Id = 'Rufus.Rufus' } $true)) 'süzgeç açık: açık kaynak görünür'
Assert-True (-not (Test-FossHidden @{ Id = 'Bilinmeyen.Arac' } $true)) 'lisansı bilinmeyen araç gizlenmez'
foreach ($r in $script:AltRules) {
    Assert-True ($script:FossMeta.ContainsKey([string]$r.Id) -and $script:FossMeta[[string]$r.Id].Open -eq $true) ('alternatif açık kaynak ve lisansı kayıtlı: ' + [string]$r.Id)
    Assert-True ([string]$r.Id -cmatch '^[A-Za-z0-9][A-Za-z0-9\.\-_\+]*$') ('alternatif kimliği winget biçiminde: ' + [string]$r.Id)
}
$sg = @(Get-AltSuggestions @('WinRAR 7.01 (64-bit)', 'Google Chrome', 'Adobe Acrobat Reader DC', 'Notepad++ (64-bit x64)', 'WinZip 28'))
Assert-Eq (@($sg | ForEach-Object { $_.Id }) -join ',') '7zip.7zip,SumatraPDF.SumatraPDF,Mozilla.Firefox' 'öneriler: aynı karşılık bir kez önerilir'
Assert-True ($sg[0].Have -like 'WinRAR*') 'öneri, kurulu programın adını taşır'
Assert-Eq @(Get-AltSuggestions @('WinRAR 7.01', '7-Zip 26.06 (x64)')).Count 0 'karşılığı zaten kuruluysa önerilmez'
Assert-Eq @(Get-AltSuggestions @('Google Chrome', 'Mozilla Firefox (x64 tr)')).Count 0 'Firefox kuruluysa tarayıcı önerilmez'
Assert-Eq @(Get-AltSuggestions @('Notepad++', 'VLC media player')).Count 0 'eşleşme yoksa öneri yok'
Assert-Eq @(Get-AltSuggestions @()).Count 0 'liste boşsa öneri yok'
# Ücretsiz araçlar listesi: yeni araçlar eklendi, kategoriler bir arada
Import-Var 'FossToolsBase', 'FossToolsMore'
Import-Fn 'Get-FossToolsMerged'
$baseCount = @($script:FossToolsBase).Count
Import-Var 'FossTools'
Assert-Eq @($script:FossTools).Count ($baseCount + 5) 'beş yeni araç eklendi'
Assert-Eq @(Get-FossToolsMerged $script:FossTools $script:FossToolsMore).Count ($baseCount + 5) 'aynı kimlik ikinci kez eklenmez'
$ids = @($script:FossTools | ForEach-Object { [string]$_.Id })
foreach ($x in @('SumatraPDF.SumatraPDF', 'GIMP.GIMP', 'ShareX.ShareX', 'qBittorrent.qBittorrent', 'HandBrake.HandBrake')) { Assert-True ($ids -contains $x) ("araç listesinde: $x") }
Assert-Eq @($ids | Select-Object -Unique).Count $ids.Count 'araç kimlikleri benzersiz'
$run = New-Object System.Collections.ArrayList; $lastCat = $null
foreach ($t in $script:FossTools) { if ([string]$t.Cat -ne $lastCat) { [void]$run.Add([string]$t.Cat); $lastCat = [string]$t.Cat } }
Assert-Eq @($run | Select-Object -Unique).Count $run.Count 'her kategori listede tek blok (başlık yinelenmez)'
foreach ($t in $script:FossTools) { Assert-True ($script:FossMeta.ContainsKey([string]$t.Id)) ('lisans bilgisi var: ' + [string]$t.Id) }

# ======================= 8) Firefox ilkeleri =======================
foreach ($id in @('PrivFirefoxTele', 'PrivFirefoxSponsor')) {
    Assert-True ([regex]::IsMatch($src, "Add-RegTweak -Id '$id' -Cat 'Gizlilik' -Level 2")) ("katalogda: $id")
}
Assert-True ($src.Contains("'|DisableTelemetry|DWord|1'") -and $src.Contains("'|DisableFirefoxStudies|DWord|1'") -and $src.Contains("'\FirefoxHome|SponsoredTopSites|DWord|0'")) 'Mozilla''nın belgelenmiş ilke adları'
Assert-True ($src.Contains("`$ffx = 'HKLM\SOFTWARE\Policies\Mozilla\Firefox'")) 'ilke anahtarı'

# ======================= 9) yardım paketi =======================
$t = Protect-SupportText 'C:\Users\stibe\AppData\x.log stibe@ornek.com 192.168.1.10 AA:BB:CC:DD:EE:FF LAPTOP-AB12 sürüm 10.0.0 saat 14:58:53' 'stibe' 'LAPTOP-AB12'
Assert-True ($t.Contains('C:\Users\<kullanıcı>\AppData')) 'kullanıcı klasörü gizlenir'
Assert-True (-not $t.Contains('stibe')) 'kullanıcı adı kalmaz'
Assert-True ($t.Contains('<e-posta>') -and $t.Contains('<ip>') -and $t.Contains('<mac>') -and $t.Contains('<bilgisayar>')) 'e-posta, IP, MAC ve bilgisayar adı gizlenir'
Assert-True ($t.Contains('sürüm 10.0.0') -and $t.Contains('14:58:53')) 'sürüm numarası ve saat bozulmaz'
Assert-Eq (Protect-SupportText 'kısa ad ab içinde' 'ab' '') 'kısa ad ab içinde' 'üç harften kısa kullanıcı adı sözcük içinde aranmaz'
Assert-Eq (Protect-SupportText '' 'x' 'y') '' 'boş metin'
$ss = Get-SupportSettings @{ Theme = 'Acik'; Contact = 'ali@x.com'; BackupDest = 'E:\Yedek'; GwBaseline = @{ a = 1 }; AppliedIds = @('Ads') }
Assert-True ($ss.ContainsKey('Theme') -and $ss.ContainsKey('AppliedIds')) 'pakette sorun gidermeye yarayan ayarlar kalır'
foreach ($k in @('Contact', 'BackupDest', 'GwBaseline')) { Assert-True (-not $ss.ContainsKey($k)) ("pakete girmez: $k") }

# ======================= 10) yeni bilgisayar adımları =======================
$st = @(Get-SetupSteps @{ Applied = 0; BackupDest = ''; PrepSeen = ''; AppVersion = '10.1.0' })
Assert-Eq $st.Count 6 'altı adım'
Assert-Eq (@($st | ForEach-Object { $_.Page }) -join ',') 'updates,solve,optimize,apps,backup,board' 'adımların sayfaları'
Assert-Eq @($st | Where-Object { $_.Done }).Count 0 'yeni bilgisayarda tamamlanan adım yok'
$st = @(Get-SetupSteps @{ Applied = 12; BackupDest = 'E:\Yedek'; PrepSeen = '10.1.0'; AppVersion = '10.1.0' })
Assert-Eq (@($st | Where-Object { $_.Done } | ForEach-Object { $_.Key }) -join ',') 'prep,tune,backup' 'yapılan adımlar işaretlenir'
foreach ($s in $st) { Assert-True ([string]$s.Title -ne '' -and [string]$s.Detail -ne '' -and [string]$s.Btn -ne '') ('adım metinleri dolu: ' + [string]$s.Key) }
foreach ($pg in @($st | ForEach-Object { $_.Page } | Select-Object -Unique)) { Assert-True ($src.Contains('function Show-Page_' + $pg)) ("sayfa var: $pg") }

# ======================= 11) şifreleme yolu =======================
Assert-True (Test-HomeEdition 'Core') 'Home sürümü'
Assert-True (Test-HomeEdition 'CoreSingleLanguage') 'Home tek dil sürümü'
Assert-True (-not (Test-HomeEdition 'Professional')) 'Pro sürümü Home değildir'
Assert-Eq (Get-BlEnableRoute 'C:' 'C:' $true) 'Settings' 'Home, sistem sürücüsü: Cihaz şifrelemesi'
Assert-Eq (Get-BlEnableRoute 'D:' 'C:' $true) 'None' 'Home, ek sürücü: Windows ile şifrelenemez'
Assert-Eq (Get-BlEnableRoute 'c:\' 'C:' $false) 'Enable' 'Pro, sistem sürücüsü: uygulama içinden'
Assert-Eq (Get-BlEnableRoute 'E:' 'C:' $false) 'Panel' 'Pro, ek sürücü: Windows BitLocker penceresi'
Assert-Eq (Get-BlEnableRoute 'C:\Windows' 'C:' $false) 'None' 'sürücü harfi olmayan yol reddedilir'
Assert-True ($src.Contains('if ($r.Encrypted -ne $true) { $b1 = (Get-BlOnLabel) }')) 'şifresiz sürücüde "Şifrelemeyi aç" düğmesi'
Assert-True ($src.Contains("-UsedSpaceOnly -RecoveryPassword")) 'BitLocker kurtarma parolasıyla açılır'
Assert-True ($src.Contains('(\d{6}-){7}\d{6}') -and $src.Contains('<kurtarma parolas')) 'kurtarma parolası günlüğe yazılmaz'
Assert-True ([regex]::IsMatch($src, 'OptCrypto\s+= \$true')) 'dosya şifreleme varsayılan olarak açık'

# ======================= 12) arayüz bağlantıları =======================
Assert-True ($src.Contains('x:Name="tl_Tab_kit"')) 'Yardımcılar sekmesi XAML''de'
Assert-True ($src.Contains("'kit' { Show-OnlyBar 'tl' @(); Render-TlKit }")) 'sekme çizimi bağlı'
Assert-True ($src.Contains('default { Invoke-TlExtraAct ([string]$s.Tag.Key) }')) 'düğme dağıtıcı bağlı'
foreach ($k in [regex]::Matches($src, "'(kit:[A-Za-z]+)(?::[^']*)?'") | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique) {
    $key = $k.Split(':')[1]
    if ($key -eq 'none') { continue }
    Assert-True ([regex]::IsMatch($src, "(?m)^\s+'" + [regex]::Escape($key) + "' \{")) ("düğme anahtarı dağıtıcıda karşılanıyor: $k")
}
foreach ($f in @('Render-TlKit', 'Render-KitHome', 'Render-KitPw', 'Render-KitRename', 'Render-KitScore', 'Render-KitNet', 'Render-KitAlt', 'Render-KitSetup', 'Invoke-TlExtraAct', 'Add-FossFilterRow', 'Get-FossDetail', 'Start-BlEnable', 'Add-BlHomeRows')) {
    Assert-True ([regex]::IsMatch($src, '(?m)^function ' + [regex]::Escape($f) + '\b')) ("işlev tanımlı: $f")
}

# ======================= dizi dönüşü: "return , $dizi" ile dönen işlevler tek tek gezilir (gerçek bilgisayarda yakalanan hata sınıfı) =======================
Import-Fn 'Test-FirefoxInstalled', 'Job_AltScan'
function Get-RegSubKeyNames([string]$k) { return , @() }
Assert-True (-not (Test-FirefoxInstalled)) 'Firefox kayıt anahtarı boşsa kurulu sayılmaz'
function Get-RegSubKeyNames([string]$k) { if ($k -like 'HKCU*') { return , @('128.0 (x64 tr)') }; return , @() }
Assert-True (Test-FirefoxInstalled) 'alt anahtar varsa Firefox kurulu sayılır'
function Get-InstalledPrograms { return , @(@{ Name = 'WinRAR 7.01 (64-bit)' }, @{ Name = 'Adobe Acrobat Reader DC' }, @{ Name = 'Paint.NET' }) }
$ar = Job_AltScan @{}
Assert-Eq $ar.Count 3 'kurulu program adları tek tek okunur (birleşik tek metin değil)'
Assert-True (@($ar.Rows | Where-Object { $_.Have -eq 'WinRAR 7.01 (64-bit)' }).Count -eq 1) 'alternatif önerisi eşleşen programın kendi adını taşır'
Assert-True ([regex]::IsMatch($src, '\$steps = New-StepsFromIds \$script:FirefoxTweakIds\r?\n\s+\$steps = @\(\$steps\)')) 'Firefox ilkeleri: adım listesi iç içe diziye dönüşmez'

# ======================= Araçlar sayfası kullanıcı kipinde =======================
Import-Fn 'Get-TlVisibleTabs', 'Get-TlStartTab', 'Test-TlNeedsExpert'
Import-Var 'TlTabs', 'TlUserTabs', 'ExpertPages'
Assert-Eq (@(Get-TlVisibleTabs $true) -join ',') ($script:TlTabs -join ',') 'uzman kipinde bütün sekmeler görünür'
Assert-Eq (@(Get-TlVisibleTabs $false) -join ',') 'repair,ext,kit' 'kullanıcı kipinde yalnızca gündelik sekmeler (sayfadaki sırayla)'
Assert-Eq (Get-TlStartTab $false 'win') 'kit' 'kullanıcı kipinde gizli sekme seçiliyse Yardımcılar açılır'
Assert-Eq (Get-TlStartTab $false 'ext') 'ext' 'kullanıcı kipinde görünen sekme korunur'
Assert-Eq (Get-TlStartTab $true 'procs') 'procs' 'uzman kipinde seçili sekme korunur'
Assert-Eq (Get-TlStartTab $true 'yok') 'win' 'uzman kipinde bilinmeyen sekme ilk sekmeye döner'
Assert-True (Test-TlNeedsExpert 'procs' $false) 'kullanıcı kipinde uzman sekmesi istenirse kip değişir'
Assert-True (-not (Test-TlNeedsExpert 'kit' $false)) 'Yardımcılar için kip değişmez'
Assert-True (-not (Test-TlNeedsExpert 'procs' $true)) 'uzman kipindeyken kip değişmez'
Assert-True (-not (Test-TlNeedsExpert 'yok' $false)) 'bilinmeyen sekme kip değiştirmez'
Assert-True (@($script:ExpertPages) -notcontains 'tools') 'Araçlar sayfası kullanıcı kipinde de sol çubukta durur'
Assert-True (@($script:ExpertPages) -contains 'services' -and @($script:ExpertPages) -contains 'company') 'Hizmetler ve Şirket yalnızca uzman kipinde'
Assert-True ([regex]::IsMatch($src, '(?m)^function Update-PageMode_tools\b')) 'kip değişince Araçlar sekmeleri güncellenir'
Assert-True ($src.Contains("    if (Test-TlNeedsExpert `$Sub (`$script:UiState.Mode -eq 'Expert')) { Set-UiMode 'Expert' `$true }")) 'gizli sekmeye gidilirse sessizce uzman kipine geçilir'

Show-Result
