# -*- coding: utf-8 -*-
"""p82: Geri alinamayan kayitlar kaybolmaz.

Gercek bilgisayardaki tam denetimde (18.11.2026 19:55) Is Klasorleri kapatildi, "Geri al" ozelligi yeniden acamadi
(0x371B, Windows yeniden baslatma bekliyordu) ve ekranda "Bilgisayari yeniden baslatip tekrar deneyin" yazdi. Ama
Invoke-Undo hata olsa da yedek dosyasini her zaman ".geri-alindi" diye isaretliyordu; Gecmis sayfasi bu dosyalari gostermedigi
icin yeniden denenecek bir sey kalmiyordu. Artik:
  - hepsi geri alindiysa dosya eskisi gibi ".geri-alindi" olur;
  - bazi kayitlar hata verdiyse dosyada yalnizca geri alinamayanlar kalir (basari ile geri alinanlar ikinci kez
    uygulanmaz), oturum Gecmis'te gorunmeye devam eder ve uyari bunu soyler; "Tumunu geri al" da onlari yeniden dener;
  - eski (.json) bicimdeki yedekte hata olursa dosyaya dokunulmaz (tamami yeniden denenebilir)."""


def apply(b):
    b.before("function Invoke-Undo([string]$File) {\n", """# Geri alinamayan kayitlari yedekte birakir: oturum Gecmis sayfasinda kalir, yeniden baslatmadan sonra tekrar geri alinabilir.
# $Failed geri alma sirasindadir (dosyanin tersi); dosyaya ilk siralariyla yazilir.
function Save-UndoRemainder([string]$File, $Jr, $Failed) {
    $n = @($Failed).Count
    try {
        if ($File.EndsWith('.jsonl', [StringComparison]::OrdinalIgnoreCase)) {
            $keep = @($Failed)
            [array]::Reverse($keep)
            $sb = New-Object System.Text.StringBuilder
            if ($null -ne $Jr.Header) { [void]$sb.Append((ConvertTo-Json -InputObject $Jr.Header -Compress -Depth 5) + "`r`n") }
            foreach ($it in $keep) { [void]$sb.Append((ConvertTo-Json -InputObject $it -Compress -Depth 5) + "`r`n") }
            [System.IO.File]::WriteAllText($File, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
        }
    } catch { Write-LogFile ('Kalan geri alma kayitlari yazilamadi: ' + $_.Exception.Message) }
    Write-WhLog ([string]$n + ' kayıt geri alınamadı; bu yedek Geçmiş sayfasında kaldı. Bilgisayarı yeniden başlattıktan sonra yeniden geri alabilirsiniz.') 'WARN'
}

""")
    b.rep("""    Write-WhLog ('Yedek: ' + $created + ' (' + $items.Count + (' kay' + [char]0x0131 + 't)')) 'STEP'
    foreach ($it in $items) {
""", """    Write-WhLog ('Yedek: ' + $created + ' (' + $items.Count + (' kay' + [char]0x0131 + 't)')) 'STEP'
    $undoFail = New-Object System.Collections.ArrayList
    foreach ($it in $items) {
""", name='p82 geri al sayaci')
    b.rep("""        } catch { Add-Err ('Hata: ' + $_.Exception.Message) }
        Step-JobProgress
    }
    try { [void](Invoke-LiveRefresh $items) } catch { }
    try {
        $dn = [System.IO.Path]::ChangeExtension($File, '.geri-alindi' + [System.IO.Path]::GetExtension($File))
        Move-Item -LiteralPath $File -Destination $dn -Force -ErrorAction Stop
    } catch { }
}
""", """        } catch { Add-Err ('Hata: ' + $_.Exception.Message); [void]$undoFail.Add($it) }
        Step-JobProgress
    }
    try { [void](Invoke-LiveRefresh $items) } catch { }
    if ($undoFail.Count -gt 0) { Save-UndoRemainder $File $jr $undoFail.ToArray(); return }
    try {
        $dn = [System.IO.Path]::ChangeExtension($File, '.geri-alindi' + [System.IO.Path]::GetExtension($File))
        Move-Item -LiteralPath $File -Destination $dn -Force -ErrorAction Stop
    } catch { }
}
""", name='p82 kalan kayitlar')
