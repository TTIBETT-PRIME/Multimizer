# ==================================================================
#  Multimizer eklentisi: Wi-Fi profillerini parolalarıyla dışa aktarma (taşınma kiti).
#  Parolalar DÜZ METİN yazılır; bu yüzden yalnızca taşınma kitinde “Wi-Fi” kutusunu siz işaretlerseniz çalışır.
#  Bu dosya Multimizer.ps1 tarafından gerektiğinde yüklenir; tek başına çalıştırılmaz. Özeti ana betikte yazılıdır.
# ==================================================================

# Dir: yazılacak klasör (var olmalı). Dönüş: netsh çıkış kodu
function global:Export-WifiProfilesWithKeys([string]$Dir) {
    return (Invoke-Native 'netsh.exe' @('wlan', 'export', 'profile', 'key=clear', ('folder=' + $Dir)))
}
