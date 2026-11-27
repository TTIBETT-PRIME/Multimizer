# ==================================================================
#  GERCEK MAKINE DUZELTMELERI (cekirdek)
#  Bu bolumdeki her islem sonucunu sistemden geri okuyarak dogrular; "yapildi" yalnizca dogrulama tutarsa yazilir.
#    - Guc kipi: Modern Bekleme (S0) kullanan bilgisayarlarda Windows yalnizca Dengeli planina izin verir;
#      performans duzeyi "guc kipi" (En iyi performans / Dengeli / En iyi guc verimliligi) ile ayarlanir.
#    - Ekran karti sicakligi: Gorev Yoneticisi'nin kullandigi surucu arayuzunden (D3DKMT) okunur.
#    - Gorsel efektler: kayit degerleri oturum kapatmadan uygulanir (SystemParametersInfo + ayar degisikligi yayini).
#    - Oturum: bilgisayar kapanirken sona eren oturum cokme sayilmaz; guvenli kip sorunsuz oturumlardan sonra kendiliginden kapanir.
#    - Yeniden baslatma: shutdown.exe cikis koduyla dogrulanir.
# ==================================================================

$script:SysNativeOk = $null
$script:SysNativeSrc = @'
using System;
using System.Runtime.InteropServices;
namespace WH {
  public static class Sys {
    [StructLayout(LayoutKind.Sequential)] struct LUID { public uint Low; public int High; }
    [StructLayout(LayoutKind.Sequential)] struct ADAPTERINFO { public uint hAdapter; public LUID AdapterLuid; public uint NumOfSources; public int bPrecise; }
    [StructLayout(LayoutKind.Sequential)] struct ENUM2 { public uint NumAdapters; public IntPtr pAdapters; }
    [StructLayout(LayoutKind.Sequential)] struct QAI { public uint hAdapter; public uint Type; public IntPtr pData; public uint Size; }
    [StructLayout(LayoutKind.Sequential)] struct CLOSEAD { public uint hAdapter; }
    [StructLayout(LayoutKind.Sequential, Pack = 8)] struct PERF { public uint PhysicalAdapterIndex; public ulong MemoryFrequency; public ulong MaxMemoryFrequency; public ulong MaxMemoryFrequencyOC; public ulong MemoryBandwidth; public ulong PCIEBandwidth; public uint FanRPM; public uint Power; public uint Temperature; public byte PowerStateOverride; }
    [StructLayout(LayoutKind.Sequential)] struct ANIMATIONINFO { public uint cbSize; public int iMinAnimate; }
    [DllImport("gdi32.dll")] static extern int D3DKMTEnumAdapters2(ref ENUM2 e);
    [DllImport("gdi32.dll")] static extern int D3DKMTQueryAdapterInfo(ref QAI q);
    [DllImport("gdi32.dll")] static extern int D3DKMTCloseAdapter(ref CLOSEAD c);
    [DllImport("powrprof.dll")] static extern uint PowerGetEffectiveOverlayScheme(out Guid g);
    [DllImport("powrprof.dll")] static extern uint PowerSetActiveOverlayScheme(Guid g);
    [DllImport("powrprof.dll", EntryPoint = "PowerSetUserConfiguredACPowerMode")] static extern uint SetAcMode(ref Guid g);
    [DllImport("powrprof.dll", EntryPoint = "PowerSetUserConfiguredDCPowerMode")] static extern uint SetDcMode(ref Guid g);
    [DllImport("powrprof.dll", EntryPoint = "PowerGetUserConfiguredACPowerMode")] static extern uint GetAcMode(out Guid g);
    [DllImport("powrprof.dll", EntryPoint = "PowerGetUserConfiguredDCPowerMode")] static extern uint GetDcMode(out Guid g);
    [DllImport("powrprof.dll")] static extern byte GetPwrCapabilities([Out] byte[] caps);
    [DllImport("user32.dll", SetLastError = true)] static extern bool SystemParametersInfo(uint action, uint param, IntPtr pv, uint flags);
    [DllImport("user32.dll", SetLastError = true, EntryPoint = "SystemParametersInfo")] static extern bool SystemParametersInfoAnim(uint action, uint param, ref ANIMATIONINFO pv, uint flags);
    [DllImport("user32.dll", SetLastError = true, EntryPoint = "SystemParametersInfo")] static extern bool SystemParametersInfoGet(uint action, uint param, ref int pv, uint flags);
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint msg, IntPtr wParam, string lParam, uint flags, uint timeout, out IntPtr result);

    // En sicak ekran karti (derece C); okunamazsa -1.
    public static double GpuTemp() {
      double best = -1.0;
      ENUM2 e = new ENUM2();
      if (D3DKMTEnumAdapters2(ref e) != 0 || e.NumAdapters == 0 || e.NumAdapters > 64) return best;
      int sz = Marshal.SizeOf(typeof(ADAPTERINFO));
      e.pAdapters = Marshal.AllocHGlobal(sz * (int)e.NumAdapters);
      try {
        if (D3DKMTEnumAdapters2(ref e) != 0) return best;
        int psz = Marshal.SizeOf(typeof(PERF));
        for (int i = 0; i < e.NumAdapters; i++) {
          ADAPTERINFO a = (ADAPTERINFO)Marshal.PtrToStructure(new IntPtr(e.pAdapters.ToInt64() + (long)i * sz), typeof(ADAPTERINFO));
          IntPtr p = Marshal.AllocHGlobal(psz);
          try {
            for (int k = 0; k < psz; k++) Marshal.WriteByte(p, k, 0);
            QAI q = new QAI(); q.hAdapter = a.hAdapter; q.Type = 62; q.pData = p; q.Size = (uint)psz;
            if (D3DKMTQueryAdapterInfo(ref q) == 0) {
              PERF pf = (PERF)Marshal.PtrToStructure(p, typeof(PERF));
              double c = pf.Temperature / 10.0;
              if (c > 5.0 && c < 150.0 && c > best) best = c;
            }
          } finally {
            Marshal.FreeHGlobal(p);
            CLOSEAD cl = new CLOSEAD(); cl.hAdapter = a.hAdapter; D3DKMTCloseAdapter(ref cl);
          }
        }
      } finally { Marshal.FreeHGlobal(e.pAdapters); }
      return best;
    }

    // Modern Bekleme (S0 dusuk guc bosta): SYSTEM_POWER_CAPABILITIES.AoAc
    public static bool ModernStandby() {
      try { byte[] b = new byte[128]; if (GetPwrCapabilities(b) == 0) return false; return b[20] != 0; } catch { return false; }
    }

    public static string GetMode() {
      try { Guid g; if (PowerGetEffectiveOverlayScheme(out g) == 0) return g.ToString(); } catch { }
      return "";
    }

    // Kullanicinin sectigi kip (fiste, pilde); okunamazsa bos
    public static string GetUserMode(bool dc) {
      try { Guid g; uint r = dc ? GetDcMode(out g) : GetAcMode(out g); if (r == 0) return g.ToString(); } catch { }
      return "";
    }

    // 0 = basarili. Once belgelenmis Windows 11 islevleri (fis ve pil ayri), olmazsa etkin kaynak icin eski islev.
    public static uint SetMode(string ac, string dc) {
      Guid a = new Guid(ac); Guid d = new Guid(dc);
      try {
        uint r1 = SetAcMode(ref a); uint r2 = SetDcMode(ref d);
        if (r1 == 0 && r2 == 0) return 0;
      } catch (EntryPointNotFoundException) { }
      catch (DllNotFoundException) { return 2; }
      try { return PowerSetActiveOverlayScheme(a); } catch { return 1; }
    }

    public static bool SetSpiBool(uint setAction, bool on) { return SystemParametersInfo(setAction, 0, on ? new IntPtr(1) : IntPtr.Zero, 2); }
    public static bool SetSpiUi(uint setAction, uint value) { return SystemParametersInfo(setAction, value, IntPtr.Zero, 2); }
    public static bool SetMinAnimate(bool on) { ANIMATIONINFO ai = new ANIMATIONINFO(); ai.cbSize = 8; ai.iMinAnimate = on ? 1 : 0; return SystemParametersInfoAnim(0x0049, 8, ref ai, 2); }
    public static int GetSpi(uint getAction) { int v = 0; SystemParametersInfoGet(getAction, 0, ref v, 0); return v; }
    public static void Broadcast(string area) { IntPtr r; SendMessageTimeout(new IntPtr(0xFFFF), 0x001A, IntPtr.Zero, area, 0x0002, 1000, out r); }
  }
}
'@

# Yerel islevler bir kez derlenir (uygulama alani genelinde; arka plan calisma alanlari da ayni turu gorur)
function Initialize-SysNative {
    if ($null -ne ('WH.Sys' -as [type])) { $script:SysNativeOk = $true; return $true }
    if ($script:SysNativeOk -eq $false) { return $false }
    try { Add-Type -TypeDefinition $script:SysNativeSrc -ErrorAction Stop; $script:SysNativeOk = $true }
    catch { $script:SysNativeOk = $false; try { Write-WhLog ('SysNative: ' + $_.Exception.Message) } catch { } }
    return [bool]$script:SysNativeOk
}

# ---------------- ekran karti sicakligi ----------------
function Get-GpuTemp {
    if (-not (Initialize-SysNative)) { return -1.0 }
    try { $v = [double][WH.Sys]::GpuTemp(); if ($v -gt 0) { return [math]::Round($v, 0) } } catch { }
    return -1.0
}

# ---------------- guc kipi ----------------
$script:PwModes = [ordered]@{
    Perf     = @{ Guid = 'ded574b5-45a0-4f42-8737-46345c09c238'; Name = 'En iyi performans' }
    Balanced = @{ Guid = '00000000-0000-0000-0000-000000000000'; Name = 'Dengeli' }
    Saver    = @{ Guid = '961cc777-2547-4f9d-8174-7d86181b8a7a'; Name = 'En iyi güç verimliliği' }
}

function Test-PwModernStandby {
    if (-not (Initialize-SysNative)) { return $false }
    try { return [bool][WH.Sys]::ModernStandby() } catch { return $false }
}

# Plan anahtari -> guc kipi anahtari ('' = bu anahtar bir guc kipine karsilik gelmez)
function Get-PwModeKeyFor([string]$PlanKey) {
    switch ($PlanKey) {
        'High' { return 'Perf' } 'Ultimate' { return 'Perf' } 'Best' { return 'Perf' }
        'Balanced' { return 'Balanced' } 'Saver' { return 'Saver' }
    }
    return ''
}

function Get-PwModeKeyOfGuid([string]$Guid) {
    $g = $Guid.Trim().ToLowerInvariant()
    foreach ($k in $script:PwModes.Keys) { if ([string]$script:PwModes[$k].Guid -eq $g) { return [string]$k } }
    return ''
}

# Su an yururlukteki guc kipi: @{ Ok; Key; Name; Guid; Modern }
function Get-PwModeInfo {
    $r = @{ Ok = $false; Key = ''; Name = ''; Guid = ''; Modern = $false }
    if (-not (Initialize-SysNative)) { return $r }
    try {
        $r.Modern = [bool][WH.Sys]::ModernStandby()
        $g = [string][WH.Sys]::GetMode()
        if ($g -eq '') { return $r }
        $r.Guid = $g.ToLowerInvariant()
        $r.Key = Get-PwModeKeyOfGuid $r.Guid
        if ($r.Key -ne '') { $r.Name = [string]$script:PwModes[$r.Key].Name; $r.Ok = $true }
    } catch { }
    return $r
}

# Plan anahtari guc kipiyle mi uygulanmali?  Modern Bekleme'de Windows Dengeli disindaki yerlesik planlari sunmaz.
function Test-PwUseMode([string]$PlanKey) {
    if ((Get-PwModeKeyFor $PlanKey) -eq '') { return $false }
    return (Test-PwModernStandby)
}

# Op: @{ T = 'PowerSet'; Key } -> Modern Bekleme'de guc kipi olarak uygulanir. Sonuc geri okunarak dogrulanir.
function Invoke-PowerModeOp([string]$PlanKey) {
    $mk = Get-PwModeKeyFor $PlanKey
    $tg = $script:PwModes[$mk]
    $cur = Get-PwModeInfo
    $act = Get-PwActive
    $balGuid = [string]$script:PwKnown.Balanced.Guid
    $onBalanced = ([string]$act.Guid -eq $balGuid)
    if ($cur.Ok -and [string]$cur.Guid -eq [string]$tg.Guid -and $onBalanced) { Add-Skip ('Güç kipi zaten ' + [string]$tg.Name); return }
    if ($script:Preview) {
        $from = 'bilinmiyor'
        if ($cur.Ok) { $from = [string]$cur.Name }
        Add-Plan ('Güç kipi: ' + $from + ' → ' + [string]$tg.Name)
        Add-Plan '   (Bu bilgisayar Modern Bekleme kullanıyor: Windows yalnızca Dengeli planını sunar, performans düzeyi güç kipiyle ayarlanır.)'
        if (-not $onBalanced) { Add-Plan ('   Etkin plan Dengeli yapılacak (güç kipi yalnızca Dengeli planında geçerlidir): ' + [string]$act.Name) }
        return
    }
    if (-not $onBalanced) {
        Add-Journal @{ T = 'Power'; Guid = [string]$act.Guid }
        & powercfg.exe /setactive $balGuid | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Dengeli plan etkinleştirilemedi (powercfg /setactive).' }
    }
    $pa = [string][WH.Sys]::GetUserMode($false); $pd = [string][WH.Sys]::GetUserMode($true)
    if ($pa -eq '') { $pa = [string]$cur.Guid }
    if ($pd -eq '') { $pd = [string]$cur.Guid }
    Add-Journal @{ T = 'PowerMode'; Ac = $pa; Dc = $pd }
    $rc = [WH.Sys]::SetMode([string]$tg.Guid, [string]$tg.Guid)
    if ($rc -ne 0) { throw ('Windows güç kipini değiştirmedi (kod ' + [string]$rc + ').') }
    $now = Get-PwModeInfo
    if (-not $now.Ok -or [string]$now.Guid -ne [string]$tg.Guid) {
        $seen = 'okunamadı'
        if ($now.Ok) { $seen = [string]$now.Name }
        throw ('Güç kipi doğrulanamadı: istenen ' + [string]$tg.Name + ', yürürlükteki ' + $seen + '. Üreticinin güç yazılımı ya da bir kurum ilkesi kipi kilitliyor olabilir.')
    }
    Add-Done ('Güç kipi: ' + [string]$tg.Name + ' (doğrulandı)')
}

function Undo-PowerMode($It) {
    if (-not (Initialize-SysNative)) { throw 'Güç kipi geri alınamadı (yerel işlev yüklenemedi).' }
    $a = [string]$It.Ac; $d = [string]$It.Dc
    if ($a -eq '') { $a = [string]$script:PwModes.Balanced.Guid }
    if ($d -eq '') { $d = $a }
    $rc = [WH.Sys]::SetMode($a, $d)
    if ($rc -ne 0) { throw ('Güç kipi geri alınamadı (kod ' + [string]$rc + ').') }
    Add-Done 'Güç kipi geri alındı'
}

# ---------------- gorsel efektlerin aninda uygulanmasi ----------------
# UserPreferencesMask bitleri: SPI_GET degeri = 0x1000 + bit * 2, SPI_SET = SPI_GET + 1
$script:LiveMaskBits = @(1, 2, 3, 9, 10, 11, 12, 13, 18, 33)
$script:LiveRegRx = '(?i)\\Control Panel\\Desktop|\\Explorer\\VisualEffects|\\Explorer\\Advanced|\\Themes\\Personalize|\\Windows\\DWM'

# Gunluk kayitlari arasinda gorsel ayar var mi?
function Test-LiveRefreshNeeded($Items) {
    foreach ($it in @($Items)) {
        if ($null -eq $it) { continue }
        if ([string]$it.T -eq 'Reg' -and [string]$it.Path -match $script:LiveRegRx) { return $true }
    }
    return $false
}

# Maske baytlarindan bit degeri
function Get-MaskBit([byte[]]$Mask, [int]$Bit) {
    $i = [int][math]::Floor($Bit / 8)
    if ($null -eq $Mask -or $i -ge $Mask.Length) { return $null }
    return (([int]$Mask[$i] -band (1 -shl ($Bit % 8))) -ne 0)
}

# Kayit defterindeki gorsel ayarlari calisan oturuma uygular. Donus: uygulanan ayar sayisi (-1: yerel islev yok)
function Invoke-LiveRefresh($Items) {
    if (-not (Test-LiveRefreshNeeded $Items)) { return 0 }
    if (-not (Initialize-SysNative)) { return -1 }
    $n = 0
    try {
        $desk = 'HKCU\Control Panel\Desktop'
        $raw = Get-RegValue $desk 'UserPreferencesMask' $null
        $mask = $null
        if ($null -ne $raw) { try { $mask = [byte[]]@($raw) } catch { $mask = $null } }
        if ($null -ne $mask -and $mask.Length -ge 4) {
            foreach ($b in $script:LiveMaskBits) {
                $v = Get-MaskBit $mask $b
                if ($null -eq $v) { continue }
                if ([WH.Sys]::SetSpiBool([uint32](0x1000 + $b * 2 + 1), [bool]$v)) { $n++ }
            }
        }
        $ma = [string](Get-RegValue ($desk + '\WindowMetrics') 'MinAnimate' '')
        if ($ma -ne '') { if ([WH.Sys]::SetMinAnimate(($ma -eq '1'))) { $n++ } }
        $df = [string](Get-RegValue $desk 'DragFullWindows' '')
        if ($df -ne '') { if ([WH.Sys]::SetSpiUi(0x0025, [uint32]([int]($df -eq '1')))) { $n++ } }
        $md = [string](Get-RegValue $desk 'MenuShowDelay' '')
        if ($md -match '^\d+$') { if ([WH.Sys]::SetSpiUi(0x006B, [uint32]$md)) { $n++ } }
        foreach ($area in @('WindowMetrics', 'ImmersiveColorSet', 'TraySettings', 'Environment')) { [WH.Sys]::Broadcast($area) }
    } catch { Write-WhLog ('Görsel ayarlar oturuma uygulanırken hata: ' + $_.Exception.Message) 'WARN'; return $n }
    if ($n -gt 0) { Write-WhLog 'Görsel ayarlar oturum kapatmadan uygulandı (bazı pencereler yeniden açılınca tam yansır).' 'INFO' }
    return $n
}

# ---------------- yeniden baslatma bekleyen dosya islemleri ----------------
# PendingFileRenameOperations ciftlerden olusur (kaynak, hedef). Hedefi bos olan cift "acilista sil" demektir;
# uygulamalarin geride biraktigi bu tur kayitlar yeniden baslatma gerektirmez. Yalnizca dosya degistiren ciftler sayilir.
function Test-PendingRenameReal($Value) {
    $a = @($Value)
    if ($a.Count -eq 0) { return $false }
    for ($i = 0; $i -lt $a.Count; $i += 2) {
        $src = [string]$a[$i]
        $dst = ''
        if (($i + 1) -lt $a.Count) { $dst = [string]$a[$i + 1] }
        if ($src.Trim() -eq '') { continue }
        if ($dst.Trim() -ne '') { return $true }
    }
    return $false
}

# ---------------- oturum: bilgisayar kapanirken sona erme ----------------
function Get-SystemBootTime {
    try { return [DateTime](Get-CimInstance -ClassName Win32_OperatingSystem -OperationTimeoutSec 5 -ErrorAction Stop).LastBootUpTime } catch { }
    try { return (Get-Date).AddSeconds(-1.0 * [System.Diagnostics.Stopwatch]::GetTimestamp() / [System.Diagnostics.Stopwatch]::Frequency) } catch { }
    return [DateTime]::MinValue
}

# Onceki oturumun son izi bilgisayarin son acilisindan onceyse oturum, Windows kapanirken sona ermistir (cokme degildir).
function Test-EndedBySystem([DateTime]$LastTrace, [DateTime]$Boot) {
    if ($Boot -eq [DateTime]::MinValue -or $LastTrace -eq [DateTime]::MinValue) { return $false }
    return ($LastTrace -lt $Boot)
}

function Test-SessionEndedBySystem {
    try {
        if ([string]$script:TraceFile -eq '' -or -not (Test-Path -LiteralPath $script:TraceFile)) { return $false }
        $last = (Get-Item -LiteralPath $script:TraceFile).LastWriteTime
        return (Test-EndedBySystem $last (Get-SystemBootTime))
    } catch { return $false }
}

# Guvenli kipten kendiliginden cikis karari.
#   Why: 'user' (kullanici Ayarlar'dan acti) | 'auto' | '' (eski surumden kalan; otomatik sayilir)
#   Donus: $true = guvenli cizim kapatilmali
function Test-SafeModeRelease([bool]$SafeRender, [string]$Why, [int]$CleanStreak, [bool]$PrevCrashed, [int]$FixLevel) {
    if (-not $SafeRender -or $PrevCrashed) { return $false }
    if ($Why -eq 'user') { return $false }
    if ($FixLevel -lt 1) { return $true }
    return ($CleanStreak -ge 3)
}

# ---------------- yeniden baslatma ----------------
# shutdown.exe bagimsiz degiskenleri tek satirda ve aciklamasi tirnak icinde verilir; cikis kodu 0 degilse basarisizdir.
function Get-RestartArgLine([bool]$Firmware, [int]$Seconds) {
    $a = '/r'
    if ($Firmware) { $a += ' /fw' }
    return ($a + ' /t ' + [string]$Seconds + ' /c "Multimizer: yeniden baslatma"')
}

function Start-SystemRestart([bool]$Firmware = $false, [int]$Seconds = 30) {
    $exe = Join-Path (Join-Path $env:WINDIR 'System32') 'shutdown.exe'
    $p = Start-Process -FilePath $exe -ArgumentList (Get-RestartArgLine $Firmware $Seconds) -WindowStyle Hidden -Wait -PassThru -ErrorAction Stop
    $code = [int]$p.ExitCode
    if ($code -ne 0) { throw ('shutdown.exe çıkış kodu ' + [string]$code) }
    return $true
}
