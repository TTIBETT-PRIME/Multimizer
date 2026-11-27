# -*- coding: utf-8 -*-
"""Kararlılık çözümleyici (mavi ekran, uygulama çökmesi, açılış süresi) ve katalog ekleri."""

SELF_ANCHOR = "    Add-SelfLine ''\n    $okN = $script:SelfTotal - $script:SelfFail\n"

SELFTEST = r"""    Test-Step ('Kararlılık çözümleyici: hata denetimi kodları, çökme ve açılış özetleri') {
        $need = @('ConvertTo-BugcheckKey', 'Get-BugcheckInfo', 'Get-BugcheckSummary', 'Get-BugcheckAdvice', 'Get-AppCrashSummary', 'Get-AppCrashAdvice', 'Get-BootSummary', 'Invoke-MemDiagAction', 'Chk_Crashes', 'Chk_AppCrashes', 'Chk_BootTime')
        $miss = @($need | Where-Object { $null -eq (Get-Command -Name $_ -CommandType Function -ErrorAction Ignore) })
        if ($miss.Count -gt 0) { return ('eksik: ' + ($miss -join ', ')) }
        if ((ConvertTo-BugcheckKey 'The bugcheck was: 0x0000009f (0x0000000000000003)') -ne '9F') { return 'hata denetimi kodu ayrıştırılamadı' }
        if ((ConvertTo-BugcheckKey 'kod yok') -ne '') { return 'kodsuz metin kod üretti' }
        $i = Get-BugcheckInfo '9F'
        if ([string]$i.Kind -ne 'power') { return 'DRIVER_POWER_STATE_FAILURE türü yanlış' }
        if ([string](Get-BugcheckInfo 'ZZZ').Kind -ne 'other') { return 'bilinmeyen kod other olmalı' }
        $ev = @(@{ Time = [datetime]'2026-01-02'; Key = '9F' }, @{ Time = [datetime]'2026-01-03'; Key = '9F' }, @{ Time = [datetime]'2026-01-04'; Key = 'E2' }, @{ Time = [datetime]'2026-01-05'; Key = '133' })
        $s = Get-BugcheckSummary $ev
        if ($s.Total -ne 3 -or $s.Manual -ne 1) { return 'özet toplamı yanlış (elle üretilenler sayılmamalı)' }
        if ([string]$s.Rows[0].Key -ne '9F') { return 'en sık kod başta değil' }
        if ([string](Get-BugcheckAdvice 'memory').Run -ne 'MemDiag') { return 'bellek önerisi sınama eylemi taşımıyor' }
        if (-not $script:ExtraActions.ContainsKey('MemDiag')) { return 'MemDiag eylemi kayıtlı değil' }
        $rows = @(@{ App = 'a.exe'; Kind = 'crash'; Module = 'vcruntime140.dll'; Code = 'c0000005'; Path = ''; Time = [datetime]'2026-01-02' }, @{ App = 'a.exe'; Kind = 'crash'; Module = 'vcruntime140.dll'; Code = 'c0000005'; Path = ''; Time = [datetime]'2026-01-03' })
        $as = Get-AppCrashSummary $rows
        if ($as.Total -ne 2 -or [int]$as.Rows[0].Crashes -ne 2) { return 'uygulama özeti yanlış' }
        if ([string](Get-AppCrashAdvice $as.Rows[0]).Kind -ne 'runtime') { return 'çalışma zamanı kitaplığı çökmesi tanınmadı' }
        $bs = Get-BootSummary @(@{ Time = [datetime]'2026-01-02'; BootMs = 50000; MainMs = 30000; PostMs = 20000 }) @()
        if ($bs.Count -ne 1 -or [int]$bs.MedianMain -ne 30000) { return 'açılış özeti yanlış' }
    }

"""


def apply(b):
    # eski, yalnızca sayan çökme denetimini kaldır
    b.sub_re(r"function Get-EventCountSafe\(\[hashtable\]\$Filter\) \{.*?(?=# -{10,} dosya dolasma)", '', 1, flags=__import__('re').S)
    b.add_core('114_stability.ps1', title='kararlilik cozumleyici: mavi ekran, uygulama cokmesi, acilis suresi')
    b.add_core('115_catalog9.ps1', title='katalog ekleri 9.0.0')
    b.rep("B = { Chk_Crashes } }\n",
          "B = { Chk_Crashes } },\n            @{ N = ('Uygulama çökmeleri'); B = { Chk_AppCrashes } }, @{ N = ('Açılış süresi'); B = { Chk_BootTime } }\n")
    b.before(SELF_ANCHOR, SELFTEST)
