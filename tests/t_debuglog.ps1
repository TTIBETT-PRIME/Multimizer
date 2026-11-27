. "$PSScriptRoot/lib.ps1"
# 8.0.0: ayrıntılı hata günlüğü (-DebugLog, Ayarlar > Görünüm > Kararlılık). Yutulan (try / catch ile geçiştirilen) hatalar da $Error listesinde birikir;
# modül listeyi okuyup Kayıtlar\ayrinti-GÜN.txt dosyasına yazar. Sınanan: kapalıyken hiçbir şey yapmaması, kayıt alanları, yinelenenlerin birleştirilmesi,
# dakika ve boyut sınırları, kendi hatalarını yeniden işlememesi, özet / program hatası işareti, iş çalışma alanı satır çevirisi ve betikteki bağlantılar.

Import-Fn 'Test-DebugLogOn', 'Initialize-DebugTables', 'Set-DebugLogState', 'Get-DebugKey', 'Test-DebugCodeError', 'Get-DebugErrorInfo',
    'Add-DebugFileText', 'Write-DebugRecord', 'Save-DebugErrors', 'Get-DebugSummary', 'Get-DebugCounts'
Import-Var 'DbgLast', 'DbgMaxBytes', 'DbgRecMax', 'DbgPerMin', 'DbgCodeIds'

$root = Join-Path ([System.IO.Path]::GetTempPath()) ('mm-dbg-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root -Force | Out-Null
$sync = [hashtable]::Synchronized(@{ LogDir = $root; DebugLog = $false; Version = '8.0.0'; CoreLineBase = 100 })
$dayFile = Join-Path $root ('ayrinti-' + (Get-Date -Format 'yyyyMMdd') + '.txt')

function Reset-Dbg {
    $sync.DbgStat = $null; $sync.DbgSeen = $null; $sync.DbgDay = ''; $sync.DbgBytes = 0; $sync.DbgFull = $false; $sync.DbgWin = 0; $sync.DbgWinN = 0
    $script:DbgLast = $null; $script:DbgMaxBytes = 2097152; $script:DbgRecMax = 200; $script:DbgPerMin = 200
    if (Test-Path -LiteralPath $dayFile) { Remove-Item -LiteralPath $dayFile -Force }
    $Error.Clear()
}
function Read-Dbg { if (Test-Path -LiteralPath $dayFile) { return [System.IO.File]::ReadAllText($dayFile) } else { return '' } }
function Count-Recs([string]$Text) { return ([regex]::Matches($Text, '(?m)^\d\d:\d\d:\d\d  \[')).Count }

# yutulan hata üreticileri (uygulamadaki kalıplar: try / catch { } ve -ErrorAction SilentlyContinue)
function Gen-NullCall { try { $x = $null; $x.Foo() } catch { } }
function Gen-NoCmd { try { Nope-Komut-Yok 1 } catch { } }
function Gen-NoPath([string]$P) { Get-Item -LiteralPath $P -ErrorAction SilentlyContinue | Out-Null }
function Gen-Throw([string]$Text) { try { throw $Text } catch { } }

try {
    # ======================= 1) kapalıyken hiçbir şey yapılmaz =======================
    Reset-Dbg
    Gen-NullCall; Gen-NoCmd
    Assert-True ($Error.Count -ge 2) 'yutulan hatalar $Error listesinde birikir (try / catch ve SilentlyContinue)'
    Assert-True (-not (Test-DebugLogOn)) 'varsayılan: kapalı'
    Assert-Eq (Save-DebugErrors 'ana') 0 'kapalıyken kayıt işlenmez'
    Assert-True (-not (Test-Path -LiteralPath $dayFile)) 'kapalıyken dosya oluşmaz'
    Assert-True ($null -eq $sync.DbgStat) 'kapalıyken özet tablosu oluşmaz'

    # ======================= 2) açma =======================
    Set-DebugLogState $true
    Assert-True (Test-DebugLogOn) 'açıldı'
    Assert-True ($null -ne $sync.DbgStat -and $null -ne $sync.DbgSeen) 'tablolar hazır'
    Assert-True ([int]$global:MaximumErrorCount -ge 1024) 'hata listesi sınırı yükseltildi'

    # ======================= 3) kayıt alanları =======================
    Reset-Dbg
    Gen-NullCall; Gen-NoCmd; Gen-NoPath (Join-Path $root 'yok-1'); Gen-Throw 'patladi'
    $n = Save-DebugErrors 'ana'
    Assert-Eq $n 4 'dört yutulan hata işlendi'
    $t = Read-Dbg
    $bytes = [System.IO.File]::ReadAllBytes($dayFile)
    Assert-True ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) 'dosya UTF-8 imzalı (BOM)'
    Assert-True ($t.StartsWith('# Multimizer 8.0.0')) 'dosya başlığı sürümü yazar'
    Assert-Eq (Count-Recs $t) 4 'dosyada dört kayıt'
    Assert-True ($t.Contains('InvokeMethodOnNull')) 'boş değere yöntem çağrısı kimliği yazıldı'
    Assert-True ($t.Contains('CommandNotFoundException')) 'tanımsız komut kimliği yazıldı'
    Assert-True ($t.Contains('PathNotFound')) 'bulunamayan yol kimliği yazıldı'
    Assert-True ($t.Contains('patladi')) 'iletisi yazıldı'
    Assert-True ($t.Contains('[ana]')) 'kaynak etiketi yazıldı'
    Assert-True ($t -match 'işlev: Gen-NullCall') 'işlev zinciri yazıldı'
    Assert-True ($t.Contains('$x.Foo()')) 'hatalı satırın metni yazıldı'
    Assert-True ($t -match '(?m)^\s+satır \d+') 'betik satırı yazıldı'
    # eskiden yeniye: ilk üretilen önce yazılır
    Assert-True ($t.IndexOf('InvokeMethodOnNull') -lt $t.IndexOf('CommandNotFoundException') -and $t.IndexOf('CommandNotFoundException') -lt $t.IndexOf('patladi')) 'kayıtlar eskiden yeniye'

    # ======================= 4) yeni kayıt yoksa yeniden yazılmaz =======================
    Assert-Eq (Save-DebugErrors 'ana') 0 'yeni hata yokken sıfır'
    Assert-Eq (Count-Recs (Read-Dbg)) 4 'dosya büyümedi'
    Gen-Throw 'ikinci-kusur'
    Assert-Eq (Save-DebugErrors 'ana') 1 'yalnızca yeni kayıt işlenir'
    Assert-Eq (Count-Recs (Read-Dbg)) 5 'dosyaya bir kayıt eklendi'

    # ======================= 5) yinelenenler birleşir =======================
    Reset-Dbg
    for ($i = 1; $i -le 5; $i++) { Gen-NoPath (Join-Path $root ('yok-' + $i)) }
    Assert-Eq (Save-DebugErrors 'ana') 5 'beş yinelenen işlendi'
    Assert-Eq (Count-Recs (Read-Dbg)) 1 'farklı dosya adlarıyla yinelenen hata tek satır'
    $sum = @(Get-DebugSummary 10)
    Assert-Eq $sum.Count 1 'özet tek tür'
    Assert-True ($sum[0] -match '^\s*5x ') 'özet sayacı 5'
    $c = Get-DebugCounts
    Assert-True ($c.Kinds -eq 1 -and $c.Total -eq 5 -and $c.Code -eq 0) 'özet sayıları: 1 tür, 5 kayıt, program hatası yok'
    Assert-Eq (Get-DebugKey 'K' 'I' 'Index 5 of 10' 3) (Get-DebugKey 'K' 'I' 'Index 7 of 12' 3) 'sayılar yok sayılır'
    Assert-Eq (Get-DebugKey 'K' 'I' "Yol 'C:\a\b.txt' yok" 3) (Get-DebugKey 'K' 'I' "Yol 'D:\x.txt' yok" 3) 'tırnaklı adlar yok sayılır'
    Assert-Eq (Get-DebugKey 'K' 'I' 'Erisim C:\Windows\x\y reddedildi' 3) (Get-DebugKey 'K' 'I' 'Erisim D:\baska\z reddedildi' 3) 'Windows yolları yok sayılır'
    Assert-True ((Get-DebugKey 'K' 'I' 'ileti' 3) -ne (Get-DebugKey 'K' 'I' 'ileti' 4)) 'farklı satır farklı anahtar'
    Assert-True ((Get-DebugKey 'K' 'I' 'ileti bir' 3) -ne (Get-DebugKey 'K' 'I' 'ileti iki' 3)) 'farklı ileti farklı anahtar'

    # bir dakika sonra aynı hata not düşülerek yeniden yazılır
    $key = @($sync.DbgSeen.Keys)[0]
    $sync.DbgSeen[$key].T = [DateTime]::UtcNow.AddSeconds(-61)
    $sync.DbgSeen[$key].N = 4
    Gen-NoPath (Join-Path $root 'yok-9')
    [void](Save-DebugErrors 'ana')
    $t = Read-Dbg
    Assert-Eq (Count-Recs $t) 2 'bir dakika sonra yeniden yazıldı'
    Assert-True ($t.Contains('(son dakikada 4 kez daha)')) 'bastırılan sayı yazıldı'

    # ======================= 6) dakika sınırı =======================
    Reset-Dbg
    $script:DbgPerMin = 3
    foreach ($w in @('alfa', 'beta', 'gama', 'delta', 'epsilon', 'zeta', 'eta', 'teta')) { Gen-Throw ('kusur-' + $w) }
    Assert-Eq (Save-DebugErrors 'ana') 8 'sekiz kayıt işlendi'
    Assert-Eq (Count-Recs (Read-Dbg)) 3 'dakikada en çok sınır kadar satır yazıldı'
    Assert-Eq (Get-DebugCounts).Kinds 8 'özet tablosu hepsini sayar'
    $script:DbgPerMin = 200

    # ======================= 7) boyut sınırı =======================
    Reset-Dbg
    $script:DbgMaxBytes = 700
    foreach ($w in @('bir', 'iki', 'uc', 'dort', 'bes', 'alti', 'yedi', 'sekiz', 'dokuz', 'on')) { Gen-Throw ('boyut-sinavi-' + $w + '-' + ('x' * 80)) }
    [void](Save-DebugErrors 'ana')
    $t = Read-Dbg
    $len = ([System.IO.File]::ReadAllBytes($dayFile)).Length
    Assert-True ($len -lt 1500) 'dosya sınır dolayında kesildi'
    Assert-Eq ([regex]::Matches($t, 'sınırına ulaştı')).Count 1 'sınır iletisi bir kez yazıldı'
    Assert-True (-not (Add-DebugFileText "ek satir`r`n")) 'sınır dolunca ek yazılmaz'
    $script:DbgMaxBytes = 2097152

    # ======================= 8) kendi hatalarını yeniden işlemez; Clear sonrası yeniler alınır =======================
    Reset-Dbg
    Gen-Throw 'tek'
    [void](Save-DebugErrors 'ana')
    Assert-Eq (Save-DebugErrors 'ana') 0 'ikinci tur boş'
    $Error.Clear()
    Gen-Throw 'temizlik-sonrasi'
    Assert-Eq (Save-DebugErrors 'ana') 1 'liste temizlendikten sonra yeni kayıt alınır'

    # ======================= 9) tek turda işlenen kayıt sayısı sınırlıdır =======================
    Reset-Dbg
    $script:DbgRecMax = 50
    for ($i = 0; $i -lt 80; $i++) { Gen-Throw ('toplu-' + [string][char](97 + ($i % 26)) + [string][char](97 + [int]($i / 26))) }
    Assert-Eq (Save-DebugErrors 'ana') 50 'tek turda en çok DbgRecMax kayıt işlenir'
    $script:DbgRecMax = 200

    # ======================= 10) alan çözümleme =======================
    Reset-Dbg
    Gen-NullCall
    $d = Get-DebugErrorInfo $Error[0] 'ana'
    Assert-Eq $d.Kind 'RuntimeException' 'tür'
    Assert-Eq $d.Id 'InvokeMethodOnNull' 'kimlik'
    Assert-Eq $d.Cat 'InvalidOperation' 'sınıf'
    Assert-True ($d.Line -gt 0) 'satır'
    Assert-True ($d.Text.Contains('Foo')) 'metin'
    Assert-Eq $d.Chain 'Gen-NullCall' 'işlev zinciri'
    $l1 = [int]$d.Line
    $d2 = Get-DebugErrorInfo $Error[0] 'is'
    Assert-Eq ([int]$d2.Line) ($l1 + 100) 'iş çalışma alanında satır çekirdek tabanıyla dosya satırına çevrilir'
    $d3 = Get-DebugErrorInfo $Error[0] 'izleme'
    Assert-Eq ([int]$d3.Line) ($l1 + 100) 'izleme çalışma alanında da aynı çeviri'
    $ex = New-Object System.IO.IOException('disk dolu')
    $d4 = Get-DebugErrorInfo $ex 'ana'
    Assert-True ($d4.Kind -eq 'IOException' -and $d4.Msg -eq 'disk dolu' -and $d4.Id -eq '' -and [int]$d4.Line -eq 0) 'çıplak Exception de çözülür'
    $d5 = Get-DebugErrorInfo $null 'ana'
    Assert-True ($d5.Kind -eq '' -and [int]$d5.Line -eq 0) 'boş kayıt çökertmez'
    $d6 = Get-DebugErrorInfo ('metin') 'ana'
    Assert-True ($d6.Kind -eq '') 'tanınmayan nesne çökertmez'
    $er = New-Object System.Management.Automation.ErrorRecord((New-Object System.InvalidOperationException('elle kuruldu')), 'ElleKimlik', 'InvalidOperation', $null)
    $d7 = Get-DebugErrorInfo $er 'ana'
    Assert-True ($d7.Id -eq 'ElleKimlik' -and $d7.Msg -eq 'elle kuruldu' -and [int]$d7.Line -eq 0) 'invocation bilgisi olmayan ErrorRecord'
    Reset-Dbg
    Gen-Throw "çok`r`nsatırlı   ileti"
    $d8 = Get-DebugErrorInfo $Error[0] 'ana'
    Assert-Eq $d8.Msg 'çok satırlı ileti' 'ileti tek satıra indirilir'

    # ======================= 11) program hatası işareti ve özet =======================
    foreach ($id in @('InvokeMethodOnNull', 'CommandNotFoundException', 'MethodNotFound', 'PropertyNotFoundStrict', 'NullArray', 'VariableIsUndefined', 'ParameterBindingValidationException', 'ParameterArgumentValidationErrorNullNotAllowed', 'ArgumentNullException')) {
        Assert-True (Test-DebugCodeError $id) ('program hatası kimliği: ' + $id)
    }
    foreach ($id in @('', 'PathNotFound,Microsoft.PowerShell.Commands.GetItemCommand', 'InvalidCastFromStringToInteger', 'UnauthorizedAccessError', 'OperationStopped')) {
        Assert-True (-not (Test-DebugCodeError $id)) ('beklenen (ortamsal) hata: ' + $id)
    }
    Reset-Dbg
    for ($i = 0; $i -lt 3; $i++) { Gen-NullCall }
    Gen-NoPath (Join-Path $root 'yok')
    Gen-Throw 'tekil'
    [void](Save-DebugErrors 'ana')
    $sum = @(Get-DebugSummary 10)
    Assert-Eq $sum.Count 3 'üç tür'
    Assert-True ($sum[0] -match '^\s*3x\s+\[kod\?\] RuntimeException / InvokeMethodOnNull' -and $sum[0].Contains('Gen-NullCall') -and $sum[0].Contains('$x.Foo()')) 'en sık olan başta, [kod?] işaretli, işlev ve satır metniyle'
    Assert-True (-not ($sum[1] -match '\[kod\?\]') -and -not ($sum[2] -match '\[kod\?\]')) 'ortamsal hatalar işaretsiz'
    Assert-Eq @(Get-DebugSummary 2).Count 2 'özet üst sınırı'
    $c = Get-DebugCounts
    Assert-True ($c.Kinds -eq 3 -and $c.Total -eq 5 -and $c.Code -eq 1) 'özet sayıları'
    Reset-Dbg
    Assert-Eq @(Get-DebugSummary 5).Count 0 'boş özet'
    $c0 = Get-DebugCounts
    Assert-True ($c0.Kinds -eq 0 -and $c0.Total -eq 0 -and $c0.Code -eq 0) 'boş özet sayıları'

    # ======================= 12) kaynak etiketi dosyaya yazılır; günlük klasörü yoksa çökmez =======================
    Reset-Dbg
    Gen-Throw 'iste'
    [void](Save-DebugErrors 'is')
    Assert-True ((Read-Dbg).Contains('[is]')) 'iş kaynağı etiketi'
    $keep = $sync.LogDir
    $sync.LogDir = Join-Path $root 'olmayan-klasor'
    Reset-Dbg
    $sync.LogDir = Join-Path $root 'olmayan-klasor'
    Gen-Throw 'klasor-yok'
    $threw = $false
    try { [void](Save-DebugErrors 'ana') } catch { $threw = $true }
    Assert-True (-not $threw) 'günlük klasörü yoksa çökmez'
    $sync.LogDir = ''
    Gen-Throw 'yol-bos'
    $threw = $false
    try { [void](Save-DebugErrors 'ana') } catch { $threw = $true }
    Assert-True (-not $threw) 'günlük yolu boşsa çökmez'
    $sync.LogDir = $keep

    # ======================= 13) kapatınca durur =======================
    Reset-Dbg
    Set-DebugLogState $false
    Gen-Throw 'kapaliyken'
    Assert-Eq (Save-DebugErrors 'ana') 0 'kapatılınca işlem yok'
    Assert-True (-not (Test-Path -LiteralPath $dayFile)) 'kapatılınca dosya yok'

    # ======================= 14) derlenmiş betikte bağlantılar =======================
    $src = Get-Content -LiteralPath $env:MM_BUILD -Raw
    [void](Get-AstFunctions)
    $pn = @($script:Ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
    Assert-True ($pn -contains 'DebugLog') '-DebugLog parametresi var'
    Assert-True ($script:Ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'DebugLog' } | ForEach-Object { $_.StaticType.Name -eq 'SwitchParameter' }) '-DebugLog anahtar türünde'
    Assert-True ($src.Contains("if (`$DebugLog) { [void]`$parts.Add('-DebugLog') }")) 'yeniden başlatma -DebugLog parametresini aktarır'
    Assert-True ($src -match '(?m)^\s+DebugLog\s+= \$false\s*$') 'ayar varsayılan olarak kapalı'
    Assert-True ($src.Contains('$sync.DebugLog  = [bool]$DebugLog') -and $src.Contains('$sync.LogDir    = $script:LogDir')) 'paylaşılan durum başlatılır'
    Assert-True ($src.Contains('$script:DebugLogArg = [bool]$DebugLog')) 'oturum parametresi saklanır'
    Assert-True ($src.Contains('Set-DebugLogState (($script:Settings.DebugLog -eq $true) -or $script:DebugLogArg)')) 'ayar yüklenince durum belirlenir'
    Assert-True ($src.Contains('$sync.CoreLineBase = [int]$CoreCode.Ast.Extent.StartLineNumber - 1')) 'çekirdek satır tabanı hesaplanır'
    $wrap = $src.Substring($src.IndexOf('$script:AsyncWrapper = @'), 1400)
    Assert-True ($wrap.Contains("finally {") -and $wrap.Contains("Save-DebugErrors 'is'")) 'her arka plan işi sonunda okunur'
    Assert-True ($src.Contains("if (`$sync.DebugLog -eq `$true) { [void](Save-DebugErrors 'ana') }")) 'arayüz zamanlayıcısı okur'
    $mon = $src.Substring($src.IndexOf('function Job_Monitor'))
    Assert-True ($mon.Contains("Save-DebugErrors 'izleme'")) 'canlı izleme döngüsü okur'
    $gui = $src.Substring($src.IndexOf('function Invoke-GuiMode {'))
    $gui = $gui.Substring(0, $gui.IndexOf('#  Baslangic'))
    Assert-True ($gui.IndexOf("Save-DebugErrors 'ana'") -gt $gui.IndexOf('# ---- kapanis ----')) 'kapanışta son okuma yapılır'
    Assert-True ($src.Contains("`$cr = @(Invoke-CliMode)`r`n    try { [void](Save-DebugErrors 'ana') } catch { }")) 'komut satırı çıkışında okunur'
    Assert-True ($src.Contains("`$nr = @(Invoke-SelfTest)`r`n    try { [void](Save-DebugErrors 'ana') } catch { }")) 'kendi kendine sınamada okunur'
    $smk = $src.Substring($src.IndexOf('function Initialize-Smoke {'), 400)
    Assert-True ($smk.Contains('Set-DebugLogState $true')) 'duman testi yutulan hataları toplar'
    $cs = $src.Substring($src.IndexOf('function Complete-SmokeRun {'), 3000)
    Assert-True ($cs.Contains('Get-DebugSummary 40') -and $cs.Contains('yutulan hatalar (bilgi)')) 'duman raporu yutulan hata özetini yazar'
    Assert-Eq ([regex]::Matches($src, '<CheckBox x:Name="st_DebugLog"')).Count 1 'Ayarlar sayfasında anahtar tek'
    Assert-True ($src -match "(?s)foreach \(\`$n in @\([^)]*'st_MonGpu', 'st_DebugLog'[^)]*\)\) \{\s*\`$ui\[\`$n\]\.Add_Click\(\`$script:H_StLookChanged\)") 'anahtar tıklanınca kaydedilir'
    Assert-True ($src.Contains('-DebugLog') -and $src.Contains('[-Sessiz] [-DebugLog]')) 'komut satırı yardımı -DebugLog der'
    $bat = Get-Content -LiteralPath (Join-Path $script:TestDir 'Baslat.bat') -Raw
    Assert-True ($bat.Contains('Baslat.bat -DebugLog')) 'Baslat.bat açıklaması -DebugLog der'
    Assert-True ($bat -notmatch '[^\x00-\x7F]') 'Baslat.bat ASCII kalır'
    # günlük temizliği ayrıntı dosyalarını da kapsar (Kayıtlar klasöründeki tüm .txt)
    $ro = $src.Substring($src.IndexOf('function Remove-OldLogs'), 600)
    Assert-True ($ro.Contains("-Filter '*.txt'")) 'eski günlük temizliği ayrinti-*.txt dosyalarını da süpürür'
}
finally {
    try { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue } catch { }
}
Show-Result
