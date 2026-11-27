# -*- coding: utf-8 -*-
"""Cokme kaydi ve duman dayanikliligi (10.1.0).

Gercek bilgisayardaki ozellik denetimi iki kez ayni yerde (ag isleri) cikis kodu -1073741510 (STATUS_CONTROL_C_EXIT) ile sessizce bitti;
oturum izinde kullanicinin pencereyi kapattigi ve tepsiden cikis istedigi gorundu, konsol sinyali ise hicbir yere yazilmiyordu.
1) mods/157: AppDomain.UnhandledException, TaskScheduler.UnobservedTaskException ve SetConsoleCtrlHandler kancalari dosyaya yazar;
   Ctrl+C / Ctrl+Break yutulur (uygulamanin kendi kapanis akisi var). Duman testinde duman gunlugune, gercek uygulamada hata-GUNTARIH.txt'ye.
2) Duman testi surerken X / tepsi > Cikis istegi yok sayilir (pencere gizlenir, UYARI yazilir); test kendi bitisinde cikar.
3) Yerel ag taramasi: bekleyen ping nesneleri kapatilmis tutamacla serbest birakilmaz (tamamlananlar hemen, kalanlar kisa bekleyisle).
4) Duman-Testi.cmd: durdurma yolu yazilir.
"""


def apply(b):
    b.add_ui('157_cokme_kaydi.ps1', "function Init-Page_backup {\n", title='cokme kaydi: yakalanmayan istisna ve konsol sinyali kancalari, duman cikis korumasi')

    # 1) duman: kanca duman gunlugune yazar
    b.after("    $script:SmokeLog = Join-Path $tmp 'Multimizer-duman.txt'\n",
            "    try { [void](Initialize-CrashHooks $script:SmokeLog) } catch { }\n", raw=True)
    # 1b) gercek uygulama: gunun hata dosyasina
    b.rep("if ($Duman) { Initialize-Smoke }\ntry {\n    $gr = @(Invoke-GuiMode)\n",
          "if ($Duman) { Initialize-Smoke }\n"
          "else { try { [void](Initialize-CrashHooks (Join-Path $script:LogDir ('hata-' + (Get-Date -Format 'yyyyMMdd') + '.txt'))) } catch { } }\n"
          "try {\n    $gr = @(Invoke-GuiMode)\n", raw=True, name='p71 kanca gui')

    # 2) duman surerken cikis istegi
    b.rep("function Exit-App {\n    $script:Quitting = $true\n",
          "function Exit-App {\n    if (Test-SmokeExitBlocked) { return }\n    $script:Quitting = $true\n", raw=True, name='p71 exit-app')
    b.rep("    if ($script:SmokeExit -eq 0) { Add-SmokeLine 'SONUC TEMIZ' } else { Add-SmokeLine 'SONUC HATALI' }\n    Exit-App\n}\n",
          "    if ($script:SmokeExit -eq 0) { Add-SmokeLine 'SONUC TEMIZ' } else { Add-SmokeLine 'SONUC HATALI' }\n    $script:SmokeFinishing = $true\n    Exit-App\n}\n",
          raw=True, name='p71 smoke finishing')

    # 3) ag taramasi: suren ping nesneleri
    b.rep("        try { [void][System.Threading.Tasks.Task]::WaitAll([System.Threading.Tasks.Task[]]$tasks.ToArray(), 6000) } catch { }\n"
          "        foreach ($pg in $pings) { try { $pg.Dispose() } catch { } }\n",
          "        try { [void][System.Threading.Tasks.Task]::WaitAll([System.Threading.Tasks.Task[]]$tasks.ToArray(), 6000) } catch { }\n"
          "        # suren ping nesnesi serbest birakilmaz (bekleyen ICMP geri cagrisi kapatilmis tutamaca yazabilir): tamamlananlar hemen, kalanlar kisa bekleyisten sonra\n"
          "        $late = New-Object System.Collections.ArrayList\n"
          "        for ($pi = 0; $pi -lt $pings.Count; $pi++) {\n"
          "            $done = $true\n"
          "            try { if ($pi -lt $tasks.Count) { $done = [bool]$tasks[$pi].IsCompleted } } catch { }\n"
          "            if ($done) { try { $pings[$pi].Dispose() } catch { } } else { [void]$late.Add($pings[$pi]) }\n"
          "        }\n"
          "        if ($late.Count -gt 0) { Start-Sleep -Milliseconds 1500; foreach ($pg in $late) { try { $pg.Dispose() } catch { } } }\n",
          raw=True, name='p71 lansweep dispose')
