# ==================================================================
#  Multimizer eklentisi: bellek boşaltıcı. İsteğe bağlı özelliktir; Ayarlar > İsteğe bağlı özellikler'den açılır.
#  Bu dosya Multimizer.ps1 tarafından gerektiğinde yüklenir; tek başına çalıştırılmaz. Özeti ana betikte yazılıdır.
# ==================================================================
# ---------------- bellek boşaltıcı ----------------
function global:Initialize-MemNative {
    if ('MmMem' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
public static class MmMem {
    [DllImport("psapi.dll", SetLastError = true)] static extern bool EmptyWorkingSet(IntPtr hProcess);
    [DllImport("ntdll.dll")] static extern int NtSetSystemInformation(int infoClass, ref int info, int length);
    [DllImport("advapi32.dll", SetLastError = true)] static extern bool OpenProcessToken(IntPtr h, uint access, out IntPtr token);
    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)] static extern bool LookupPrivilegeValue(string system, string name, out long luid);
    [StructLayout(LayoutKind.Sequential, Pack = 1)] struct TokPriv { public int Count; public long Luid; public int Attr; }
    [DllImport("advapi32.dll", SetLastError = true)] static extern bool AdjustTokenPrivileges(IntPtr token, bool disableAll, ref TokPriv newState, int len, IntPtr prev, IntPtr retLen);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    static bool EnablePrivilege(string name) {
        IntPtr tok;
        if (!OpenProcessToken(Process.GetCurrentProcess().Handle, 0x28, out tok)) { return false; }
        try {
            TokPriv tp = new TokPriv();
            tp.Count = 1; tp.Attr = 2;
            if (!LookupPrivilegeValue(null, name, out tp.Luid)) { return false; }
            return AdjustTokenPrivileges(tok, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
        } finally { CloseHandle(tok); }
    }
    public static int TrimAll() {
        int n = 0;
        foreach (Process p in Process.GetProcesses()) {
            try { if (EmptyWorkingSet(p.Handle)) { n++; } } catch { } finally { p.Dispose(); }
        }
        return n;
    }
    public static int PurgeStandby() {
        EnablePrivilege("SeProfileSingleProcessPrivilege");
        int cmd = 4;
        return NtSetSystemInformation(80, ref cmd, 4);
    }
}
'@
}

function global:Get-FreeMemMb {
    try { return [double](Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop).FreePhysicalMemory / 1024.0 } catch { return 0.0 }
}

# P: Standby (bool) bekleme önbelleğini de boşalt
function global:Job_MemTrim($P) {
    try { Initialize-MemNative } catch { Write-WhLog ('Bellek yardımcısı hazırlanamadı: ' + $_.Exception.Message) 'ERR'; return @{ Ok = $false } }
    $before = Get-FreeMemMb
    $n = 0
    try { $n = [MmMem]::TrimAll() } catch { Write-WhLog ('Çalışma kümeleri boşaltılamadı: ' + $_.Exception.Message) 'WARN' }
    if ($P.Standby -eq $true) {
        try {
            $rc = [MmMem]::PurgeStandby()
            if ($rc -ne 0) { Write-WhLog ('Bekleme önbelleği boşaltılamadı (kod ' + [string]$rc + ').') 'WARN' }
        } catch { Write-WhLog ('Bekleme önbelleği boşaltılamadı: ' + $_.Exception.Message) 'WARN' }
    }
    Start-Sleep -Milliseconds 400
    $after = Get-FreeMemMb
    $gain = [math]::Max(0.0, $after - $before)
    Write-WhLog ('Bellek boşaltıldı: ' + [string]$n + ' işlem, boş bellek ' + [string][int]$before + ' MB -> ' + [string][int]$after + ' MB') 'OK'
    return @{ Ok = $true; Count = $n; Before = $before; After = $after; Gain = $gain }
}
