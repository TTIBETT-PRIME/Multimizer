# ---------------- Çökme kaydı: yakalanmayan istisnalar ve konsol sinyalleri ----------------
# Arka plan iş parçacığında patlayan bir istisna ya da konsola gelen bir kapatma sinyali süreci sessizce öldürür; ne kullanıcı ne duman
# testi nedenini görür. Bu kanca üç kaynağı dosyaya yazar: AppDomain.UnhandledException, TaskScheduler.UnobservedTaskException ve
# SetConsoleCtrlHandler (Ctrl+C / Ctrl+Break / konsol penceresi kapatıldı / oturum kapanıyor / sistem kapanıyor).
# Ctrl+C ve Ctrl+Break yutulur (uygulamanın kendi kapanış akışı vardır); pencere/oturum kapanışı engellenemez, yalnızca kaydedilir.
$script:CrashHookOn = $false
function Initialize-CrashHooks([string]$Path) {
    if ($script:CrashHookOn) { return $true }
    try {
        if (-not ('WH.CrashLog' -as [type])) {
            $src = @'
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
namespace WH {
    public static class CrashLog {
        public delegate bool CtrlHandler(int ctrlType);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool SetConsoleCtrlHandler(CtrlHandler handler, bool add);
        static CtrlHandler _ctrl;
        static string _path;
        static readonly object _lock = new object();
        public static int LastCtrl = -1;
        public static int Count = 0;
        public static bool Install(string path) {
            _path = path;
            try { AppDomain.CurrentDomain.UnhandledException += OnUnhandled; } catch { }
            try { TaskScheduler.UnobservedTaskException += OnTask; } catch { }
            bool ok = false;
            try { _ctrl = new CtrlHandler(OnCtrl); ok = SetConsoleCtrlHandler(_ctrl, true); } catch { }
            return ok;
        }
        public static void SetPath(string path) { _path = path; }
        public static void Write(string text) {
            Count++;
            try { lock (_lock) { File.AppendAllText(_path, DateTime.Now.ToString("HH:mm:ss.fff") + "  " + text + "\r\n"); } } catch { }
        }
        static void OnUnhandled(object s, UnhandledExceptionEventArgs e) {
            object ex = e.ExceptionObject;
            Write("HATA  yakalanmayan istisna (" + (e.IsTerminating ? "surec kapaniyor" : "surec devam ediyor") + "): " + (ex == null ? "?" : ex.ToString()));
        }
        static void OnTask(object s, UnobservedTaskExceptionEventArgs e) {
            Write("UYARI  gozlenmeyen gorev hatasi: " + (e.Exception == null ? "?" : e.Exception.ToString()));
            try { e.SetObserved(); } catch { }
        }
        static bool OnCtrl(int t) {
            LastCtrl = t;
            string n = t == 0 ? "Ctrl+C (yutuldu)" : t == 1 ? "Ctrl+Break (yutuldu)" : t == 2 ? "konsol penceresi kapatildi" : t == 5 ? "oturum kapatiliyor" : t == 6 ? "sistem kapaniyor" : ("tur " + t);
            Write((t <= 1 ? "UYARI" : "HATA") + "  konsol denetim sinyali: " + n);
            return t <= 1;
        }
    }
}
'@
            Add-Type -TypeDefinition $src -ErrorAction Stop
        }
        $r = [WH.CrashLog]::Install($Path)
        $script:CrashHookOn = $true
        return [bool]$r
    } catch {
        try { Write-CrashLog ('Çökme kancası kurulamadı: ' + $_.Exception.Message) } catch { }
        return $false
    }
}

# Duman testi sürerken kullanıcının kapatma isteği (pencere X'i, tepsi > Çıkış) denetimi yarıda kesmesin: pencere gizlenir, istek kaydedilir.
# Durdurmak isteyen konsol penceresini kapatır (bu sinyal yukarıdaki kancayla günlüğe düşer). Testin kendi bitişi SmokeFinishing ile geçer.
$script:SmokeFinishing = $false
function Test-SmokeExitBlocked {
    if (-not $script:SmokeMode -or $script:SmokeFinishing) { return $false }
    try { Add-SmokeWarn 'çıkış isteği duman testi bitene dek yok sayıldı (durdurmak için konsol penceresini kapatın)' } catch { }
    try { Add-Trace 'duman: çıkış isteği yok sayıldı' } catch { }
    try { $script:Win.Hide() } catch { }
    return $true
}
