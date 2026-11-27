# -*- coding: utf-8 -*-
"""Canli denetimin gercek bilgisayarda bulduklari (10.1.0).

1) Yonetici olmayan oturumda (yalnizca -Duman denemesi boyle acilabilir; gercek uygulama her zaman yukseltilmis calisir) bir kayit degerinin
   yazilamamasi "Windows bu degeri korumaya almis" anlamina gelmez. Eskiden bu durum kalici "korumali" listesine (RegDenied) yaziliyor ve ayar
   listesinde "Windows engelliyor" gorunuyordu; ileti de "yonetici olsaniz da" diyordu. Artik yonetici degilse kalici kayit tutulmaz ve ileti
   "Yonetici izni gerekiyor" der.
2) Duman testinin gunluk okuyucusu "beklenen satir" kavramini taniyor: bilerek yapilan olumsuz denemeler (yanlis parola, kisa parola, bozuk dosya)
   uygulamanin gunlugune ERR yazar. Bunlar hata sayilmaz ama gercekten yazildiklari dogrulanir; yazilmadiysa olumsuz yol hic calismamis demektir.
"""


def apply(b):
    # ---- 1) yonetici olmayan oturumda kalici "korumali" kaydi tutma
    b.before("function Get-RegDeniedText([string]$Label) {\n",
             "# Bu surecin yonetici olup olmadigi. Gercek uygulama her zaman yukseltilmis calisir; yalnizca -Duman denemesi yonetici olmadan acilabilir.\n"
             "# Yonetici olmayan oturumda bir degerin yazilamamasi \"Windows korumali\" demek degildir; bu yuzden kalici korumali kaydi tutulmaz.\n"
             "function Test-ProcAdmin {\n"
             "    if ($null -eq $script:ProcAdminCache) {\n"
             "        $v = $false\n"
             "        try { $v = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) } catch { $v = $false }\n"
             "        $script:ProcAdminCache = [bool]$v\n"
             "    }\n"
             "    return [bool]$script:ProcAdminCache\n"
             "}\n"
             "\n"
             "function Get-RegNoAdminText([string]$Label) {\n"
             "    return ('Yönetici izni gerekiyor; yönetici olmayan oturumda değiştirilemedi: ' + $Label)\n"
             "}\n"
             "\n")

    b.rep("function Register-RegDenied([string]$Label) {\n    try {\n        if ($null -eq $sync.RegDenied) { return }\n",
          "function Register-RegDenied([string]$Label) {\n    try {\n        if ($null -eq $sync.RegDenied) { return }\n"
          "        if (-not (Test-ProcAdmin)) { return }\n", raw=True, name='p70 kayit korumasi')

    b.rep("            Remove-LastJournalItem\n            Register-RegDenied $label\n            Add-Skip (Get-RegDeniedText $label)\n            return\n        }\n        Clear-RegDenied $label\n        Add-Done ($label + ' silindi')\n",
          "            Remove-LastJournalItem\n            if (Test-ProcAdmin) { Register-RegDenied $label; Add-Skip (Get-RegDeniedText $label) } else { Add-Skip (Get-RegNoAdminText $label) }\n            return\n        }\n        Clear-RegDenied $label\n        Add-Done ($label + ' silindi')\n",
          raw=True, name='p70 silme yolu')
    b.rep("        Remove-LastJournalItem\n        Register-RegDenied $label\n        Add-Skip (Get-RegDeniedText $label)\n        return\n    }\n    Clear-RegDenied $label\n    Add-Done ('{0} = {1}' -f $label, $newText)\n",
          "        Remove-LastJournalItem\n        if (Test-ProcAdmin) { Register-RegDenied $label; Add-Skip (Get-RegDeniedText $label) } else { Add-Skip (Get-RegNoAdminText $label) }\n        return\n    }\n    Clear-RegDenied $label\n    Add-Done ('{0} = {1}' -f $label, $newText)\n",
          raw=True, name='p70 yazma yolu')

    # ---- 2) beklenen gunluk satirlari
    b.before("function Read-SmokeLogDelta {\n",
             "# Beklenen gunluk satirlari: bilerek yapilan olumsuz denemeler (yanlis parola, kisa parola, bozuk dosya ...) uygulamanin gunlugune ERR ya da WARN yazar.\n"
             "# Bunlar hata sayilmaz; ama gercekten yazildiklari dogrulanir (yazilmadiysa olumsuz yol hic calismamis demektir). Her beklenti en cok N satir tuketir.\n"
             "$script:SmokeExpect = New-Object System.Collections.ArrayList\n"
             "\n"
             "function Add-SmokeExpect([string]$Pattern, [int]$Count = 1, [string]$Why = '') {\n"
             "    [void]$script:SmokeExpect.Add(@{ Pat = $Pattern; N = [int]$Count; Seen = 0; Why = $Why })\n"
             "}\n"
             "\n"
             "function Test-SmokeExpected([string]$Text) {\n"
             "    foreach ($e in @($script:SmokeExpect)) {\n"
             "        if ([int]$e.Seen -lt [int]$e.N -and $Text -match [string]$e.Pat) { $e.Seen = [int]$e.Seen + 1; return $true }\n"
             "    }\n"
             "    return $false\n"
             "}\n"
             "\n"
             "function Get-SmokeExpectMissing {\n"
             "    $o = New-Object System.Collections.ArrayList\n"
             "    foreach ($e in @($script:SmokeExpect)) {\n"
             "        if ([int]$e.Seen -lt [int]$e.N) { [void]$o.Add([string]$e.Why + ' (beklenen ' + [string]$e.N + ', görülen ' + [string]$e.Seen + ')') }\n"
             "    }\n"
             "    return $o.ToArray()\n"
             "}\n"
             "\n")

    b.before("            switch ([string]$en.Lv) {\n",
             "            if (([string]$en.Lv -eq 'ERR' -or [string]$en.Lv -eq 'WARN') -and (Test-SmokeExpected $tx)) { Add-SmokeLine ('beklenen olumsuz deneme [günlük] ' + $tx); continue }\n")
