# -*- coding: utf-8 -*-
"""Gercek makinede gorulen hatalar (10.1.0):
 - yeniden baslatma: shutdown.exe bagimsiz degiskenleri bozuktu (aciklama tirnaksizdi), komut hic calismiyordu
 - bilgisayar kapanirken biten oturum cokme sayiliyor, uygulama kalici guvenli kipe dusuyor, GPU ve sicaklik izleme kapaniyordu
 - guvenli kipte sicaklik izleme acik kalir; ekran karti sicakligi eklendi (D3DKMT)
 - Modern Bekleme'de guc plani yerine guc kipi; sonuc dogrulanir
 - gorsel efektler oturum kapatmadan uygulanir
 - "yeniden baslatma bekleniyor": yalnizca acilista silinecek dosya kayitlari sayilmaz
 - "ayar geri alinmis": Windows'un surekli yeniden actigi zamanlanmis gorevler sapma sayilmaz
 - Defender dislama bulgusu: ogeler listelenir, dislamalar sayfasi acilir
"""


def apply(b):
    # ---- yeniden baslatma
    b.rep("            Start-Process -FilePath 'shutdown.exe' -ArgumentList '/r', '/t', '30', '/c', 'Multimizer: yeniden baslatma' -WindowStyle Hidden | Out-Null\n",
          "            [void](Start-SystemRestart $false 30)\n", raw=True, name='p64 reboot')
    b.rep("            Start-Process -FilePath 'shutdown.exe' -ArgumentList '/r', '/fw', '/t', '30', '/c', 'Multimizer: UEFI ayarlarina yeniden baslatma' -WindowStyle Hidden | Out-Null\n",
          "            [void](Start-SystemRestart $true 30)\n", raw=True, name='p64 reboot fw')

    # ---- oturum: bilgisayar kapanirken biten oturum cokme degildir
    b.before("    if ($prev -is [hashtable] -and [string]$prev.Durum -eq 'acik' -and -not (Test-SessionAlive $prev)) {\n        $script:PrevCrashed = $true\n",
             "    $script:PrevBySystem = $false\n"
             "    if ($prev -is [hashtable] -and [string]$prev.Durum -eq 'acik' -and -not (Test-SessionAlive $prev) -and (Test-SessionEndedBySystem)) { $script:PrevBySystem = $true; $prev = $null }\n",
             raw=True)
    b.rep("    $script:SafeMode = ($persist -or $script:PrevCrashed -or ($Guvenli -eq $true))\n    $sync.SafeMon = $script:SafeMode\n",
          "    $persist = Update-SafeModeState $persist\n"
          "    $script:SafeMode = ($persist -or $script:PrevCrashed -or ($Guvenli -eq $true))\n    $sync.SafeMon = $script:SafeMode\n"
          "    if ($script:PrevBySystem) { Add-Trace 'onceki oturum bilgisayar kapanirken sona erdi (cokme sayilmadi)' }\n",
          raw=True, name='p64 safe karar')
    b.rep("    if ($script:SessClosed) { return }\n    $script:SessClosed = $true\n    try { if ($null -ne $script:SessBeatTimer) { $script:SessBeatTimer.Stop() } } catch { }\n",
          "    if ($script:SessClosed) { return }\n    $script:SessClosed = $true\n    try { Step-CleanStreak } catch { }\n    try { if ($null -ne $script:SessBeatTimer) { $script:SessBeatTimer.Stop() } } catch { }\n",
          raw=True, name='p64 temiz oturum')
    b.rep("    $oldSafe = ($s.SafeRender -eq $true)\n    $s.SafeRender = $wantSafe\n",
          "    $oldSafe = ($s.SafeRender -eq $true)\n    $s.SafeRender = $wantSafe\n    if ($oldSafe -ne $wantSafe) { if ($wantSafe) { $s.SafeRenderWhy = 'user' } else { $s.SafeRenderWhy = '' }; $s.CleanStreak = 0 }\n",
          raw=True, name='p64 safe elle')
    b.after("        RegDenied    = @()\n", "        SafeRenderWhy = ''\n        CleanStreak  = 0\n        FixLevel     = 0\n", raw=True)

    # ---- izleme: sicaklik guvenli kipte de okunur; ekran karti sicakligi
    b.rep("        if (($tick % 5) -eq 3 -and $sync.SafeMon -ne $true) {\n", "        if (($tick % 5) -eq 3) {\n", raw=True, name='p64 isi safemon')
    b.rep("        if ($sync.SafeMon -eq $true) { $last.Temp = -1.0 }\n        $m.Temp = $last.Temp\n",
          "        $m.Temp = $last.Temp\n"
          "        if (($tick % 5) -eq 4 -and $sync.SafeMon -ne $true -and $sync.NoGpu -ne $true) { try { $last.GpuTemp = [double](Get-GpuTemp) } catch { $last.GpuTemp = -1.0 } }\n"
          "        if ($null -eq $last.GpuTemp) { $last.GpuTemp = -1.0 }\n"
          "        $m.GpuTemp = [double]$last.GpuTemp\n",
          raw=True, name='p64 gpu isi')

    # ---- arayuz: olculemeyen degerin nedeni soylenir
    b.rep("        $ui.pn_DGpu.Text = ([string][char]0x00F6 + 'l' + [char]0x00E7 + [char]0x00FC + 'lemedi')\n",
          "        $ui.pn_DGpu.Text = (Get-GpuOffText)\n", raw=True, name='p64 pn gpu')
    b.rep("$ui.gm_DGpu.Text = ('' + [char]0x00F6 + 'l' + [char]0x00E7 + '' + [char]0x00FC + 'lemedi') }\n",
          "$ui.gm_DGpu.Text = (Get-GpuOffText) }\n", raw=True, name='p64 gm gpu')
    b.rep("$val = '--'; $sub = ('' + [char]0x00F6 + 'l' + [char]0x00E7 + '' + [char]0x00FC + 'lemedi') }\n",
          "$val = '--'; $sub = (Get-GpuOffText) }\n", raw=True, name='p64 board gpu')
    b.rep("        $ui.gm_DTemp.Text = 'sistem'\n", "        $ui.gm_DTemp.Text = (Get-TempSubText $M 'sistem')\n", raw=True, name='p64 gm isi')
    b.rep("$sub = ('i' + [char]0x015F + 'lemci / sistem'); $max = 110.0 }",
          "$sub = (Get-TempSubText $M ('i' + [char]0x015F + 'lemci / sistem')); $max = 110.0 }", raw=True, name='p64 board isi')

    # ---- ilk olcum gelene kadar "sensor yok / olculemedi" yerine "olculuyor" (GPU 1. turda, sicaklik 3. turda okunur)
    b.rep("        $sync.Mon = $m\n", "        $sync.MonWarmGpu = ($tick -lt 1); $sync.MonWarmTemp = ($tick -lt 3)\n        $sync.Mon = $m\n", raw=True, name='p64 ilk olcum')
    b.rep("$ui.gm_VTemp.Text = '--'; $ui.gm_DTemp.Text = ('sens' + [char]0x00F6 + 'r yok') }",
          "$ui.gm_VTemp.Text = '--'; $ui.gm_DTemp.Text = (Get-TempOffText) }", raw=True, name='p64 gm isi yok')
    b.rep("else { $val = '--'; $sub = ('sens' + [char]0x00F6 + 'r yok') }",
          "else { $val = '--'; $sub = (Get-TempOffText) }", raw=True, name='p64 board isi yok')

    # ---- guc: Modern Bekleme'de guc kipi
    b.rep("function Invoke-PowerSetOp($Op) {\n    $key = [string]$Op.Key\n",
          "function Invoke-PowerSetOp($Op) {\n    $key = [string]$Op.Key\n    if (Test-PwUseMode $key) { Invoke-PowerModeOp $key; return }\n",
          raw=True, name='p64 guc kipi')
    b.rep("function Undo-ExtraItem($it) {\n    switch ([string]$it.T) {\n",
          "function Undo-ExtraItem($it) {\n    switch ([string]$it.T) {\n        'PowerMode' { Undo-PowerMode $it }\n",
          raw=True, name='p64 guc kipi geri')
    b.rep("Known = $known; Time = (Get-Date) }\n", "Known = $known; Time = (Get-Date); Mode = (Get-PwModeInfo) }\n", raw=True, name='p64 guc bilgi')
    b.rep("    $t = Format-PwLive $i.Live\n", "    Update-PwModeLine $i\n    $t = Format-PwLive $i.Live\n", raw=True, name='p64 guc satiri')

    # ---- gorsel efektler: oturum kapatmadan uygula
    b.rep("    } finally {\n        if (-not $script:Preview) { Close-Journal }\n    }\n}\n\n# ---------------- geri alma ----------------\n",
          "    } finally {\n        if (-not $script:Preview) { try { [void](Invoke-LiveRefresh @($script:JItems)) } catch { }; Close-Journal }\n    }\n}\n\n# ---------------- geri alma ----------------\n",
          raw=True, name='p64 canli uygula')
    b.rep("        } catch { Add-Err ('Hata: ' + $_.Exception.Message) }\n        Step-JobProgress\n    }\n    try {\n        $dn = [System.IO.Path]::ChangeExtension($File, '.geri-alindi'",
          "        } catch { Add-Err ('Hata: ' + $_.Exception.Message) }\n        Step-JobProgress\n    }\n    try { [void](Invoke-LiveRefresh $items) } catch { }\n    try {\n        $dn = [System.IO.Path]::ChangeExtension($File, '.geri-alindi'",
          raw=True, name='p64 canli geri al')

    # ---- yeniden baslatma bekleyen dosya islemleri
    b.rep("    if ($null -ne $pf -and @($pf).Count -gt 0) { [void]$r.Add(", "    if ($null -ne $pf -and (Test-PendingRenameReal $pf)) { [void]$r.Add(", raw=True, name='p64 pfro')

    # ---- sapma: zamanlanmis gorevler sayilmaz
    b.rep("function Get-TweakPending($Item) {\n    if ($null -eq $Item) { return -1 }\n    $ops = @($Item.Ops | Where-Object { @('Reg', 'Svc', 'Task') -contains [string]$_.T })\n",
          "function Get-TweakPending($Item, [bool]$NoTask = $false) {\n    if ($null -eq $Item) { return -1 }\n    $ops = @($Item.Ops | Where-Object { @('Reg', 'Svc', 'Task') -contains [string]$_.T })\n"
          "    if ($NoTask) { $ops = @($ops | Where-Object { [string]$_.T -ne 'Task' }) }\n",
          raw=True, name='p64 pending')
    b.rep("        if (-not (Test-OsOk ([string]$c.OS) $sync.Profile)) { continue }\n        if ((Get-TweakPending $c) -gt 0) { [void]$out.Add([string]$id) }\n",
          "        if (-not (Test-OsOk ([string]$c.OS) $sync.Profile)) { continue }\n        if ((Get-TweakPending $c $true) -gt 0) { [void]$out.Add([string]$id) }\n",
          raw=True, name='p64 drift')

    # ---- Defender dislamalari: ogeleri goster, sayfayi ac
    b.sub_re(r"        elseif \(\$cnt -gt 0\) \{ Add-Finding 'av-excl' 'sec' 'info' [^\n]*\n",
             "        elseif ($cnt -gt 0) { Add-Finding 'av-excl' 'sec' 'info' (Get-ExclTitle $cnt) (Get-ExclDetail $pref) (Get-ExclAction) }\n", raw=True)

    b.add_core('147_realfix_core.ps1', title='gercek makine duzeltmeleri: cekirdek')
    b.add_core('148_realfix_state.ps1', title='gercek makine duzeltmeleri: durum ve metinler')
