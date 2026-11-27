# -*- coding: utf-8 -*-
"""Durum olcumu kapsami (10.1.0).

Canli denetim 209 ayardan 49'unun durumunun olculemedigini gosterdi (arayuzde "uygulanmis/bekleyen" etiketi cikmiyordu):
Defender tercihleri (Mp), olay gunlugu boyutu (EvtLog), Windows bileseni (Cap) ve durumu okunabilen islevler (guc plani,
hazirda bekletme, konuk hesabi, NetBIOS, hesap kilitleme, denetim ilkesi). Bunlarin onizlemesi zaten mevcut durumu
karsilastiriyor; olcume dahil edilir. Tek yonlu islevler (temizlik, birlestirme, DNS onbellegi) dogal olarak olculemez.
- Toplu durum olcumu (durum etiketleri, geri donen ayarlar, denetim) bir "parti" icinde yapilir: Defender tercihleri ve
  zamanlanmis gorev listesi partide bir kez okunur (Telemetri olcumu 8-11 sn -> ~2 sn). Parti disinda ve gercek uygulamada
  her okuma tazedir (ilk surumdeki 3 sn'lik onbellek geri almadan hemen sonra eski degeri gosteriyordu).
- Denetim ilkesi (AuditLogon) artik mevcut durumu okur: dort alt kategori zaten acik ise "zaten uygun" der.
"""


def apply(b):
    # 1) olcum filtresi
    b.rep("    $ops = @($Item.Ops | Where-Object { @('Reg', 'Svc', 'Task') -contains [string]$_.T })\n    if ($NoTask) {",
          "    $ops = @($Item.Ops | Where-Object { (@('Reg', 'Svc', 'Task', 'Mp', 'EvtLog', 'Cap', 'Feature', 'DxGlobal', 'NetLatency') -contains [string]$_.T) -or ([string]$_.T -eq 'Func' -and $script:FuncStateful -contains [string]$_.Name) })\n"
          "    if ($NoTask) {", raw=True, name='p73 olcum filtresi')
    # okunamayan durum (DISM / Defender yetki hatasi) "uygulanmis" sayilmasin: -1
    b.rep("        foreach ($op in $ops) { try { Invoke-Op $op } catch { } }\n        $n = [int]$script:Changes\n",
          "        $script:OpUnreadable = $false\n"
          "        foreach ($op in $ops) { try { Invoke-Op $op } catch { } }\n"
          "        $n = [int]$script:Changes\n"
          "        if ($script:OpUnreadable) { $n = -1 }\n", raw=True, name='p73 unreadable')
    b.rep("    try { $f = Get-WindowsOptionalFeature -Online -FeatureName $name -ErrorAction Stop } catch { }\n    if ($null -eq $f) { Add-Skip (('Windows ' + [char]0x00F6 + 'zelli' + [char]0x011F + 'i bu s' + [char]0x00FC + 'r' + [char]0x00FC + 'mde yok: ') + $name); return }\n",
          "    $readErr = ''\n"
          "    try { $f = Get-WindowsOptionalFeature -Online -FeatureName $name -ErrorAction Stop } catch { $readErr = $_.Exception.Message }\n"
          "    if ($null -eq $f -and $readErr -ne '') { $script:OpUnreadable = $true; Add-Skip (('Windows ' + [char]0x00F6 + 'zelli' + [char]0x011F + 'i okunamad' + [char]0x0131 + ' (') + $name + '): ' + $readErr); return }\n"
          "    if ($null -eq $f) { Add-Skip (('Windows ' + [char]0x00F6 + 'zelli' + [char]0x011F + 'i bu s' + [char]0x00FC + 'r' + [char]0x00FC + 'mde yok: ') + $name); return }\n",
          raw=True, name='p73 feature unreadable')
    b.rep("        $script:CapCache = @()\n        try { $script:CapCache = @(Get-WindowsCapability -Online -ErrorAction Stop) } catch { Write-WhLog",
          "        $script:CapCache = @()\n        $script:CapReadFailed = $false\n        try { $script:CapCache = @(Get-WindowsCapability -Online -ErrorAction Stop) } catch { $script:CapReadFailed = $true; Write-WhLog",
          raw=True, name='p73 cap unreadable')
    b.rep("    $all = Get-CapList\n    $found = @($all | Where-Object { ([string]$_.Name) -like ($match + '*') })\n",
          "    $all = Get-CapList\n"
          "    if ($script:CapReadFailed) { $script:OpUnreadable = $true; Add-Skip (('Windows bile' + [char]0x015F + 'en listesi okunamad' + [char]0x0131 + ' (y' + [char]0x00F6 + 'netici gerekir): ') + $match); return }\n"
          "    $found = @($all | Where-Object { ([string]$_.Name) -like ($match + '*') })\n",
          raw=True, name='p73 cap op unreadable')
    b.before("function Get-TweakPending($Item, [bool]$NoTask = $false) {\n",
             "# Durumu okunabilen (onizlemesi mevcut durumu karsilastiran) islevler; digerleri tek yonludur ve olculemez\n"
             "$script:FuncStateful = @('PowerPlan', 'HibernateOff', 'GuestOff', 'NetBiosOff', 'LockoutPolicy', 'AuditLogon')\n\n", raw=True)

    # 2) toplu olcum partisi: Defender tercihleri ve gorev listesi bir kez okunur (yalnizca onizlemede)
    b.rep("    try { $cur = (Get-MpPreference -ErrorAction Stop).$name } catch {",
          "    try { $cur = (Get-MpPrefCached).$name } catch { $script:OpUnreadable = $true;", raw=True, name='p73 mp cache use')
    b.rep("    $t = Get-ScheduledTask -TaskPath $Op.Path -TaskName $Op.Name -ErrorAction SilentlyContinue\n    if ($null -eq $t) { Add-Skip",
          "    $t = Get-TaskCached ([string]$Op.Path) ([string]$Op.Name)\n    if ($null -eq $t) { Add-Skip", raw=True, name='p73 task cache use')
    b.before("function Invoke-MpOp($Op) {\n",
             "# Toplu durum olcumu partisi: icindeki onizlemelerde pahali okumalar (Defender tercihleri, gorev listesi) bir kez yapilir.\n"
             "# Parti disinda ve gercek uygulamada her okuma tazedir. Ic ice cagrilabilir (derinlik sayaci).\n"
             "$script:StateBatch = $null\n"
             "function Start-StateBatch {\n"
             "    if ($null -eq $script:StateBatch) { $script:StateBatch = @{ Depth = 0; Mp = $null; Tasks = $null; TasksOk = $false } }\n"
             "    $script:StateBatch.Depth = [int]$script:StateBatch.Depth + 1\n"
             "}\n"
             "function Stop-StateBatch {\n"
             "    if ($null -eq $script:StateBatch) { return }\n"
             "    $script:StateBatch.Depth = [int]$script:StateBatch.Depth - 1\n"
             "    if ([int]$script:StateBatch.Depth -le 0) { $script:StateBatch = $null }\n"
             "}\n"
             "function Get-MpPrefCached {\n"
             "    $b = $script:StateBatch\n"
             "    if ($null -ne $b -and $script:Preview) {\n"
             "        if ($null -eq $b.Mp) { $b.Mp = Get-MpPreference -ErrorAction Stop }\n"
             "        return $b.Mp\n"
             "    }\n"
             "    return (Get-MpPreference -ErrorAction Stop)\n"
             "}\n"
             "function Get-TaskCached([string]$Path, [string]$Name) {\n"
             "    $b = $script:StateBatch\n"
             "    if ($null -ne $b -and $script:Preview) {\n"
             "        if ($null -eq $b.Tasks) {\n"
             "            $h = @{}\n"
             "            try { foreach ($t in @(Get-ScheduledTask -ErrorAction Stop)) { $h[([string]$t.TaskPath + [string]$t.TaskName).ToLowerInvariant()] = $t }; $b.TasksOk = $true } catch { $b.TasksOk = $false }\n"
             "            $b.Tasks = $h\n"
             "        }\n"
             "        $k = ($Path + $Name).ToLowerInvariant()\n"
             "        if ($b.Tasks.ContainsKey($k)) { return $b.Tasks[$k] }\n"
             "        # tam liste yonetici olarak okunduysa listede olmayan gorev yoktur; degilse tek tek sorulur\n"
             "        if ([bool]$b.TasksOk -and [bool]$script:IsAdmin) { return $null }\n"
             "    }\n"
             "    return (Get-ScheduledTask -TaskPath $Path -TaskName $Name -ErrorAction SilentlyContinue)\n"
             "}\n\n", raw=True)
    # partiyi baslatan toplu olcumler
    b.rep("function Get-DriftedIds {\n    $out = New-Object System.Collections.ArrayList\n    foreach ($id in (Get-AppliedIds)) {\n",
          "function Get-DriftedIds {\n    $out = New-Object System.Collections.ArrayList\n    Start-StateBatch\n    try {\n    foreach ($id in (Get-AppliedIds)) {\n",
          raw=True, name='p73 batch drift a')
    b.rep("        if ((Get-TweakPending $c $true) -gt 0) { [void]$out.Add([string]$id) }\n    }\n    return , $out.ToArray()\n}\n",
          "        if ((Get-TweakPending $c $true) -gt 0) { [void]$out.Add([string]$id) }\n    }\n    } finally { Stop-StateBatch }\n    return , $out.ToArray()\n}\n",
          raw=True, name='p73 batch drift b')
    b.rep("    Set-JobProgress 0 $items.Count ('Ayarlar' + [char]0x0131 + 'n durumu okunuyor')\n    foreach ($c in $items) {\n        if (Test-JobCancel) { break }\n        $pv = Get-TweakPending $c\n        if ($pv -eq 0 -and (Test-TweakBlocked $c)) { $pv = -3 }\n        $states[[string]$c.Id] = $pv\n        Step-JobProgress\n    }\n    $drift = Get-DriftedIds\n",
          "    Set-JobProgress 0 $items.Count ('Ayarlar' + [char]0x0131 + 'n durumu okunuyor')\n    Start-StateBatch\n    try {\n    foreach ($c in $items) {\n        if (Test-JobCancel) { break }\n        $pv = Get-TweakPending $c\n        if ($pv -eq 0 -and (Test-TweakBlocked $c)) { $pv = -3 }\n        $states[[string]$c.Id] = $pv\n        Step-JobProgress\n    }\n    $drift = Get-DriftedIds\n    } finally { Stop-StateBatch }\n",
          raw=True, name='p73 batch states')
    b.rep("function Job_TweakStateIds($P) {\n    $states = @{}\n    foreach ($id in @($P.Ids)) {\n",
          "function Job_TweakStateIds($P) {\n    $states = @{}\n    Start-StateBatch\n    try {\n    foreach ($id in @($P.Ids)) {\n",
          raw=True, name='p73 batch ids a')
    b.rep("            $states[[string]$id] = $pv\n        }\n    }\n    return @{ States = $states }\n}\n",
          "            $states[[string]$id] = $pv\n        }\n    }\n    } finally { Stop-StateBatch }\n    return @{ States = $states }\n}\n",
          raw=True, name='p73 batch ids b')

    # 3) denetim ilkesi: mevcut durum
    b.rep("function Invoke-AuditLogon {\n    if ($script:Preview) {",
          "function Invoke-AuditLogon {\n"
          "    if (Test-AuditLogonOn) { Add-Skip ('Denetim ilkesi zaten etkin (oturum, hesap kilitleme, hesap y' + [char]0x00F6 + 'netimi, ilke de' + [char]0x011F + 'i' + [char]0x015F + 'ikli' + [char]0x011F + 'i)'); return }\n"
          "    if ($script:Preview) {", raw=True, name='p73 audit state')
    b.before("# Denetim ilkesi: auditpol /backup ile tam geri alma\nfunction Invoke-AuditLogon {\n",
             "$script:AuditLogonSubs = @('{0CCE9215-69AE-11D9-BED3-505054503030}', '{0CCE9217-69AE-11D9-BED3-505054503030}', '{0CCE9235-69AE-11D9-BED3-505054503030}', '{0CCE9236-69AE-11D9-BED3-505054503030}')\n"
             "# Dort alt kategori de basari+hata ile aciksa $true; okunamazsa $false (uygulama yoluna duser, orada gercek hata gorunur)\n"
             "function Test-AuditLogonOn {\n"
             "    foreach ($g in $script:AuditLogonSubs) {\n"
             "        $txt = ''\n"
             "        try { $txt = ((& auditpol.exe /get /subcategory:$g /r 2>$null) | Out-String) } catch { return $false }\n"
             "        if ($LASTEXITCODE -ne 0 -or $txt -eq '') { return $false }\n"
             "        $row = @($txt -split \"`r?`n\" | Where-Object { $_ -match ',' } | Select-Object -Skip 1 | Select-Object -First 1)\n"
             "        if ($row.Count -eq 0) { return $false }\n"
             "        $cells = [string]$row[0] -split ','\n"
             "        $set = ''\n"
             "        if ($cells.Count -ge 5) { $set = [string]$cells[4] } else { $set = [string]$cells[$cells.Count - 1] }\n"
             "        # 'Inclusion Setting' sutunu: 'Success and Failure' / 'Basari ve Hata' (dil bagimsiz esleme)\n"
             "        if ($set -notmatch '(?i)success.*failure|failure.*success|ba.ar.*hata|hata.*ba.ar') { return $false }\n"
             "    }\n"
             "    return $true\n"
             "}\n\n", raw=True)
