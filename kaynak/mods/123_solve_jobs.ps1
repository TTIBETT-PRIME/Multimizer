# ==================================================================
#  ÇÖZÜM MERKEZİ ARKA PLAN İŞLERİ: diskleri okuma ve sürücü işlemleri
# ==================================================================

# Diskleri ve BitLocker durumlarını okur; arayüzün çizeceği satırları ve sürücü seçicilerin kullandığı özet bilgileri (etiket, dosya sistemi, boyut, ortam) da hazırlar (hiçbir şeyi değiştirmez)
function Job_SlvDisks($P) {
    try {
        $sysEnv = Get-SlvEnv
        $disks = Get-SlvDisks
        foreach ($d in @($disks)) { if ([string]$d.Drive -eq [string]$sysEnv.OsDrive) { $sysEnv.OsBlState = Get-BlState $d } }
        $out = New-Object System.Collections.ArrayList
        foreach ($d in @($disks)) {
            [void]$out.Add(@{ Drive = [string]$d.Drive; Type = [string]$d.DriveType; State = (Get-BlState $d); Plan = (Test-BlEnablePlan $d $sysEnv); Rows = (Get-SlvDiskRows $d $sysEnv)
                Label = [string]$d.Label; Fs = [string]$d.FileSystem; Size = [double]$d.Size; Free = [double]$d.Free; Media = [string]$d.Media; Bus = [string]$d.Bus; DiskName = [string]$d.DiskName })
        }
        $phys = @()
        try { $phys = Get-SlvPhysDisks } catch { Write-WhLog ('Fiziksel diskler okunamadı: ' + $_.Exception.Message) 'WARN' }
        return @{ Ok = $true; Sys = $sysEnv; Disks = $out.ToArray(); Phys = $phys }
    } catch {
        Write-WhLog ('Diskler okunamadı: ' + $_.Exception.Message) 'ERR'
        return @{ Ok = $false; Error = $_.Exception.Message }
    }
}

# Kind: scan (salt okunur tarama) | optimize (TRIM ya da birleştirme)
function Job_SlvDiskOp($P) {
    $kind = [string]$P.Kind
    try {
        if ($kind -ne 'scan' -and $kind -ne 'optimize') { throw ('Bilinmeyen disk işlemi: ' + $kind) }
        Invoke-SlvDriveAction $kind @{ Drive = [string]$P.Drive }
        return @{ Ok = $true; Kind = $kind }
    } catch {
        Write-WhLog ('Disk işlemi başarısız (' + $kind + '): ' + $_.Exception.Message) 'ERR'
        return @{ Ok = $false; Kind = $kind; Error = $_.Exception.Message }
    }
}
