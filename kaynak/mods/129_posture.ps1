# ==================================================================
#  GÜVENLİK DURUŞU
#  Sertleştirme ayarlarını ve güvenlik bulgularını uluslararası çerçevelerin ilgili başlıklarıyla eşler: CIS Controls v8, NIST SP 800-53 Rev. 5,
#  ISO/IEC 27001:2022 Ek A, BSI IT-Grundschutz, AB 2022/2555 (NIS2) m.21, AB 2016/679 (GDPR) ve 6698 sayılı KVKK.
#  Eşleme bilgilendirme amaçlıdır; sertifika, denetim sonucu ya da uygunluk beyanı değildir.
#  Yalnızca okur. Uygulanmamış ayarlar tek bir bulgu olarak sunulur; düzeltme, mevcut ayar altyapısıyla (önizleme, günlük, geri alma) yapılır.
#  Bu bölüm çekirdekte durur çünkü Chk_Posture sağlık işinin (arka plan çalışma alanı) içinde çalışır.
# ==================================================================

# Standart anahtarı | görünen ad | başlık öneki
$script:PostureStds = @(
    'CIS|CIS v8|',
    'NIST|NIST 800-53|',
    'ISO|ISO 27001|',
    'BSI|BSI|',
    'NIS2|NIS2|m.',
    'GDPR|GDPR|m.',
    'KVKK|KVKK|m.'
)

# Konu anahtarı | görünen ad
$script:PostureThemes = @(
    'acc|Kimlik ve hesaplar',
    'mal|Zararlı yazılımdan koruma',
    'net|Ağ ve uzaktan erişim',
    'cfg|Yapılandırma ve şifreleme',
    'log|Günlükleme ve izleme',
    'upd|Güncelleme ve destek',
    'dat|Veri koruma ve yedek',
    'prv|Gizlilik'
)

# Katalog ayarları: kimlik | konu | STANDART=başlık,başlık | ...
$script:PostureTweakRows = @(
    'Smb1|net|CIS=4.8|NIST=CM-7|ISO=A.8.9,A.8.20|BSI=SYS.2.2.3|NIS2=21(2)(g)',
    'AutoRun|mal|CIS=10.3|NIST=MP-7|ISO=A.7.10|BSI=SYS.2.2.3|NIS2=21(2)(g)',
    'NetStrongCrypto|cfg|CIS=3.10|NIST=SC-8,SC-13|ISO=A.8.24|BSI=CON.1|NIS2=21(2)(h)',
    'WDigest|acc|CIS=4.1|NIST=IA-5,CM-6|ISO=A.8.5,A.8.9|BSI=SYS.2.2.3|NIS2=21(2)(i)',
    'NoLmHash|acc|CIS=4.1|NIST=IA-5|ISO=A.5.17,A.8.5|BSI=SYS.2.2.3,ORP.4|NIS2=21(2)(i)',
    'AnonEnum|acc|CIS=3.3|NIST=AC-3,AC-14|ISO=A.5.15,A.8.3|BSI=SYS.2.2.3|NIS2=21(2)(i)',
    'GuestOff|acc|CIS=4.7|NIST=AC-2|ISO=A.5.16,A.5.18|BSI=ORP.4,SYS.2.2.3|NIS2=21(2)(i)',
    'RdpNla|net|CIS=4.1|NIST=AC-17,IA-2|ISO=A.8.5,A.8.20|BSI=OPS.1.2.5,SYS.2.2.3|NIS2=21(2)(i)',
    'RemoteAssist|net|CIS=4.8|NIST=AC-17,CM-7|ISO=A.6.7|BSI=OPS.1.2.5|NIS2=21(2)(g)',
    'RdpOff|net|CIS=4.8|NIST=AC-17,CM-7|ISO=A.6.7,A.8.20|BSI=OPS.1.2.5|NIS2=21(2)(g)',
    'Llmnr|net|CIS=4.8|NIST=CM-7,SC-7|ISO=A.8.9,A.8.20|BSI=SYS.2.2.3|NIS2=21(2)(g)',
    'NetBiosOff|net|CIS=4.8|NIST=CM-7,SC-7|ISO=A.8.9,A.8.20|BSI=SYS.2.2.3|NIS2=21(2)(g)',
    'Wpad|net|CIS=4.1|NIST=CM-7,SC-7|ISO=A.8.9,A.8.20|BSI=SYS.2.2.3|NIS2=21(2)(g)',
    'SmbSigning|net|CIS=3.10|NIST=SC-8|ISO=A.8.20,A.8.24|BSI=SYS.2.2.3|NIS2=21(2)(h)',
    'Ntlmv2|acc|CIS=4.1|NIST=IA-2,IA-5|ISO=A.8.5,A.8.24|BSI=SYS.2.2.3|NIS2=21(2)(i)',
    'LsaPpl|acc|CIS=4.1,10.5|NIST=SC-39,SI-16|ISO=A.8.7,A.8.9|BSI=SYS.2.2.3|NIS2=21(2)(g)',
    'Tls10|cfg|CIS=3.10|NIST=SC-8,SC-13|ISO=A.8.24|BSI=CON.1|NIS2=21(2)(h)',
    'Ps2Off|mal|CIS=4.8|NIST=CM-7|ISO=A.8.9|BSI=SYS.2.2.3|NIS2=21(2)(g)',
    'PsLogging|log|CIS=8.2,8.5|NIST=AU-2,AU-12|ISO=A.8.15|BSI=OPS.1.1.5|NIS2=21(2)(b)',
    'OfficeMacro|mal|CIS=2.7|NIST=SC-18|ISO=A.8.7|BSI=APP.1.1,OPS.1.1.4|NIS2=21(2)(g)',
    'LegacyFeat|cfg|CIS=4.8|NIST=CM-7|ISO=A.8.9|BSI=SYS.2.2.3|NIS2=21(2)(g)',
    'DefenderHarden|mal|CIS=10.1,10.5,10.7|NIST=SI-3,SI-16|ISO=A.8.7|BSI=OPS.1.1.4|NIS2=21(2)(g)',
    'WshOff|mal|CIS=2.7,4.8|NIST=CM-7,SC-18|ISO=A.8.7,A.8.9|BSI=OPS.1.1.4,SYS.2.2.3|NIS2=21(2)(g)',
    'IdleLock|cfg|CIS=4.3|NIST=AC-11|ISO=A.7.7|BSI=SYS.2.1,SYS.2.2.3|NIS2=21(2)(i)',
    'AuditLogon|log|CIS=8.2,8.5|NIST=AU-2,AU-12|ISO=A.8.15|BSI=OPS.1.1.5|NIS2=21(2)(b)',
    'Lockout|acc|CIS=4.10|NIST=AC-7|ISO=A.8.5|BSI=ORP.4,SYS.2.2.3|NIS2=21(2)(i)',
    'EvtSizes|log|CIS=8.3|NIST=AU-4|ISO=A.8.15|BSI=OPS.1.1.5|NIS2=21(2)(b)',
    'HideLastUser|acc|CIS=4.1|ISO=A.8.9|BSI=SYS.2.2.3|NIS2=21(2)(i)',
    'PwdNoReveal|acc|CIS=4.1|NIST=IA-6|ISO=A.8.5|BSI=SYS.2.2.3|NIS2=21(2)(i)',
    'NoLockCamera|cfg|CIS=4.1|ISO=A.7.7,A.8.9|BSI=SYS.2.2.3|NIS2=21(2)(g)',
    'MuUpdates|upd|CIS=7.3,7.4|NIST=SI-2|ISO=A.8.8|BSI=OPS.1.1.3|NIS2=21(2)(e)',
    'Insider|cfg|CIS=4.1|ISO=A.8.9|BSI=SYS.2.2.3|NIS2=21(2)(g)',
    'WifiSense|net|CIS=4.1|NIST=AC-18|ISO=A.8.20|BSI=SYS.2.2.3|NIS2=21(2)(g)',
    'Telemetry|prv|ISO=A.5.34|GDPR=5(1)(c),25|KVKK=4',
    'Ads|prv|ISO=A.5.34|GDPR=5(1)(c),25|KVKK=4',
    'Spotlight|prv|ISO=A.5.34|GDPR=5(1)(c),25|KVKK=4',
    'Activity|prv|ISO=A.5.34|GDPR=5(1)(c),25|KVKK=4',
    'WebSearch|prv|ISO=A.5.34|GDPR=5(1)(c),25|KVKK=4',
    'SearchCloud|prv|ISO=A.5.34|GDPR=5(1)(c),25|KVKK=4',
    'Wer|prv|ISO=A.5.34|GDPR=5(1)(c),25|KVKK=4',
    'AppCompatTelemetry|prv|ISO=A.5.34|GDPR=5(1)(c),25|KVKK=4',
    'InputPers|prv|ISO=A.5.34|GDPR=5(1)(c),25|KVKK=4',
    'ClipCloud|prv|ISO=A.5.34|GDPR=5(1)(c),25|KVKK=4',
    'Location|prv|ISO=A.5.34|GDPR=5(1)(c),25|KVKK=4',
    'EdgeNoise|prv|ISO=A.5.34|GDPR=5(1)(c),25|KVKK=4',
    'News|prv|ISO=A.5.34|GDPR=5(1)(c),25|KVKK=4',
    'Cortana|prv|ISO=A.5.34|GDPR=5(1)(c),25|KVKK=4',
    'Copilot|prv|ISO=A.5.34|GDPR=5(1)(c),25|KVKK=4'
)

# Bulgular: bulgu kimliği | konu | STANDART=başlık,başlık | ...
$script:PostureFindRows = @(
    'acc-admin|acc|CIS=5.4|NIST=AC-6|ISO=A.8.2|BSI=ORP.4|NIS2=21(2)(i)',
    'acc-adm|acc|CIS=5.4|NIST=AC-6|ISO=A.8.2|BSI=ORP.4|NIS2=21(2)(i)',
    'acc-guest|acc|CIS=4.7|NIST=AC-2|ISO=A.5.16|BSI=ORP.4|NIS2=21(2)(i)',
    'acc-nopw|acc|CIS=5.2|NIST=IA-5|ISO=A.5.17|BSI=ORP.4|NIS2=21(2)(i)',
    'pw-len|acc|CIS=5.2|NIST=IA-5|ISO=A.5.17|BSI=ORP.4|NIS2=21(2)(i)',
    'pw-lock|acc|CIS=4.10|NIST=AC-7|ISO=A.8.5|BSI=ORP.4|NIS2=21(2)(i)',
    'autologon|acc|CIS=5.2|NIST=IA-5|ISO=A.5.17|BSI=SYS.2.2.3|NIS2=21(2)(i)',
    'uac|acc|CIS=4.1|NIST=AC-6|ISO=A.8.2|BSI=SYS.2.2.3|NIS2=21(2)(i)',
    'logon-fail|log|CIS=8.11|NIST=AU-6,SI-4|ISO=A.8.15,A.8.16|BSI=OPS.1.1.5|NIS2=21(2)(b)',
    'audit|log|CIS=8.2,8.5|NIST=AU-2,AU-12|ISO=A.8.15|BSI=OPS.1.1.5|NIS2=21(2)(b)',
    'av-rt|mal|CIS=10.1|NIST=SI-3|ISO=A.8.7|BSI=OPS.1.1.4|NIS2=21(2)(g)',
    'av-sig|mal|CIS=10.2|NIST=SI-3|ISO=A.8.7|BSI=OPS.1.1.4|NIS2=21(2)(g)',
    'av-scan|mal|CIS=10.1|NIST=SI-3|ISO=A.8.7|BSI=OPS.1.1.4|NIS2=21(2)(g)',
    'av-3p|mal|CIS=10.1|NIST=SI-3|ISO=A.8.7|BSI=OPS.1.1.4|NIS2=21(2)(g)',
    'av-cloud|mal|CIS=10.7|NIST=SI-3|ISO=A.8.7|BSI=OPS.1.1.4|NIS2=21(2)(g)',
    'av-pua|mal|CIS=10.1|NIST=SI-3|ISO=A.8.7|BSI=OPS.1.1.4|NIS2=21(2)(g)',
    'av-cfa|mal|CIS=10.1,10.7|NIST=SI-3|ISO=A.8.7|BSI=OPS.1.1.4|NIS2=21(2)(g)',
    'av-tamper|mal|CIS=10.1|NIST=SI-3,SI-7|ISO=A.8.7|BSI=OPS.1.1.4|NIS2=21(2)(g)',
    'av-excl|mal|CIS=10.1|NIST=SI-3|ISO=A.8.7|BSI=OPS.1.1.4|NIS2=21(2)(g)',
    'smartscreen|mal|CIS=10.1|NIST=SI-3|ISO=A.8.7,A.8.23|BSI=OPS.1.1.4|NIS2=21(2)(g)',
    'autorun|mal|CIS=10.3|NIST=MP-7|ISO=A.7.10|BSI=SYS.2.2.3|NIS2=21(2)(g)',
    'ps2|mal|CIS=4.8|NIST=CM-7|ISO=A.8.9|BSI=SYS.2.2.3|NIS2=21(2)(g)',
    'start-sus|mal|CIS=10.7|NIST=SI-3,SI-4|ISO=A.8.7,A.8.16|BSI=OPS.1.1.4,DER.1|NIS2=21(2)(b)',
    'task-sus|mal|CIS=10.7|NIST=SI-3,SI-4|ISO=A.8.7,A.8.16|BSI=OPS.1.1.4,DER.1|NIS2=21(2)(b)',
    'task-tmp|mal|CIS=10.7|NIST=SI-3,SI-4|ISO=A.8.7,A.8.16|BSI=OPS.1.1.4,DER.1|NIS2=21(2)(b)',
    'svc-tamper|mal|NIST=SI-7|ISO=A.8.7|BSI=OPS.1.1.4|NIS2=21(2)(g)',
    'svc-unsigned|cfg|NIST=SI-7|ISO=A.8.19|BSI=SYS.2.2.3|NIS2=21(2)(g)',
    'svc-unquoted|cfg|CIS=4.1|NIST=CM-6|ISO=A.8.9|BSI=SYS.2.2.3|NIS2=21(2)(g)',
    'svc-userpath|cfg|CIS=4.1|NIST=CM-6,SI-7|ISO=A.8.9|BSI=SYS.2.2.3|NIS2=21(2)(g)',
    'fw|net|CIS=4.5|NIST=SC-7|ISO=A.8.20|BSI=NET.3.2,SYS.2.2.3|NIS2=21(2)(g)',
    'fw-public-share|net|CIS=4.5|NIST=SC-7,CM-7|ISO=A.8.20|BSI=NET.3.2|NIS2=21(2)(g)',
    'smb1|net|CIS=4.8|NIST=CM-7|ISO=A.8.9,A.8.20|BSI=SYS.2.2.3|NIS2=21(2)(g)',
    'llmnr|net|CIS=4.8|NIST=CM-7,SC-7|ISO=A.8.9,A.8.20|BSI=SYS.2.2.3|NIS2=21(2)(g)',
    'netbios|net|CIS=4.8|NIST=CM-7,SC-7|ISO=A.8.9,A.8.20|BSI=SYS.2.2.3|NIS2=21(2)(g)',
    'rdp|net|CIS=4.8|NIST=AC-17|ISO=A.6.7,A.8.20|BSI=OPS.1.2.5|NIS2=21(2)(g)',
    'remote-assist|net|CIS=4.8|NIST=AC-17,CM-7|ISO=A.6.7|BSI=OPS.1.2.5|NIS2=21(2)(g)',
    'remotereg|net|CIS=4.8|NIST=CM-7,AC-17|ISO=A.8.9,A.8.20|BSI=SYS.2.2.3|NIS2=21(2)(g)',
    'ports|net|CIS=4.8|NIST=CM-7,SC-7|ISO=A.8.20|BSI=NET.3.2|NIS2=21(2)(g)',
    'share|net|CIS=3.3|NIST=AC-3|ISO=A.5.15,A.8.3|BSI=SYS.2.2.3|NIS2=21(2)(i)',
    'share-wide|net|CIS=3.3|NIST=AC-3,AC-6|ISO=A.5.15,A.8.3|BSI=SYS.2.2.3|NIS2=21(2)(i)',
    'upnp|net|CIS=4.8|NIST=CM-7,SC-7|ISO=A.8.20|BSI=NET.3.2|NIS2=21(2)(g)',
    'proxy|net|CIS=4.1|NIST=SC-7|ISO=A.8.20|BSI=SYS.2.2.3|NIS2=21(2)(g)',
    'pac|net|CIS=4.1|NIST=SC-7|ISO=A.8.20|BSI=SYS.2.2.3|NIS2=21(2)(g)',
    'hosts|net|CIS=4.9|NIST=SC-21|ISO=A.8.20,A.8.23|BSI=SYS.2.2.3|NIS2=21(2)(g)',
    'dns-odd|net|CIS=4.9|NIST=SC-21|ISO=A.8.20,A.8.21|BSI=SYS.2.2.3|NIS2=21(2)(g)',
    'wifi-open|net|CIS=12.6|NIST=AC-18,SC-8|ISO=A.8.20,A.8.21|BSI=NET.2.1|NIS2=21(2)(g)',
    'wifi-weak|net|CIS=12.6|NIST=AC-18,SC-8|ISO=A.8.20,A.8.24|BSI=NET.2.1|NIS2=21(2)(h)',
    'arp-gw|net|NIST=SC-7,SI-4|ISO=A.8.16,A.8.20|NIS2=21(2)(b)',
    'vpn-ks-orphan|net|NIST=SC-7|ISO=A.8.20|NIS2=21(2)(g)',
    'vpn-ks-partial|net|NIST=SC-7|ISO=A.8.20|NIS2=21(2)(g)',
    'vpn-public-novpn|net|NIST=SC-8|ISO=A.6.7,A.8.20|NIS2=21(2)(g)',
    'vpn-doh-off|net|NIST=SC-8,SC-21|ISO=A.8.20,A.8.21|NIS2=21(2)(g)',
    'bl|cfg|CIS=3.6|NIST=SC-28|ISO=A.8.1,A.8.24|BSI=CON.1,SYS.2.2.3|NIS2=21(2)(h)|GDPR=32|KVKK=12',
    'bl-data|cfg|CIS=3.6,3.11|NIST=SC-28|ISO=A.8.24|BSI=CON.1|NIS2=21(2)(h)|GDPR=32|KVKK=12',
    'bl-key|cfg|CIS=3.6|NIST=SC-12,SC-28|ISO=A.8.24|BSI=CON.1|NIS2=21(2)(h)|GDPR=32|KVKK=12',
    'sboot|cfg|CIS=4.1|NIST=SI-7|ISO=A.8.9|BSI=SYS.2.2.3|NIS2=21(2)(g)',
    'tpm|cfg|CIS=4.1|NIST=SC-12|ISO=A.8.24|BSI=SYS.2.2.3|NIS2=21(2)(h)',
    'drift|cfg|CIS=4.1|NIST=CM-6|ISO=A.8.9|BSI=SYS.2.2.3|NIS2=21(2)(g)',
    'w11|upd|CIS=2.2|NIST=SA-22|ISO=A.8.8|BSI=OPS.1.1.3|NIS2=21(2)(e)',
    'os-eol|upd|CIS=2.2,7.3|NIST=SA-22,SI-2|ISO=A.8.8|BSI=OPS.1.1.3|NIS2=21(2)(e)',
    'wu-age|upd|CIS=7.3|NIST=SI-2|ISO=A.8.8|BSI=OPS.1.1.3|NIS2=21(2)(e)',
    'wu-svc-off|upd|CIS=7.3|NIST=SI-2|ISO=A.8.8|BSI=OPS.1.1.3|NIS2=21(2)(e)',
    'backup|dat|CIS=11.2|NIST=CP-9|ISO=A.8.13|BSI=CON.3|NIS2=21(2)(c)|GDPR=32|KVKK=12',
    'rp|dat|CIS=11.1|NIST=CP-9,CP-10|ISO=A.8.13|BSI=CON.3|NIS2=21(2)(c)',
    'disk-pred|dat|CIS=11.2|NIST=CP-9|ISO=A.8.13,A.8.14|BSI=CON.3|NIS2=21(2)(c)'
)

$script:PostureTweakMapCache = $null
$script:PostureFindMapCache = $null

# Satır listesini { ById; Order } yapısına çevirir. Bozuk satırlar atlanır; aynı kimlik ikinci kez eklenmez.
function ConvertTo-PostureMap($Rows) {
    $by = @{}
    $order = New-Object System.Collections.ArrayList
    foreach ($line in @($Rows)) {
        $p = ([string]$line).Split('|')
        if ($p.Count -lt 3) { continue }
        $key = $p[0].Trim()
        if ($key -eq '' -or $by.ContainsKey($key)) { continue }
        $refs = @{}
        for ($i = 2; $i -lt $p.Count; $i++) {
            $kv = $p[$i].Split('=')
            if ($kv.Count -ne 2) { continue }
            $list = @($kv[1].Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
            if ($list.Count -gt 0) { $refs[$kv[0].Trim()] = $list }
        }
        $by[$key] = @{ Key = $key; Theme = $p[1].Trim(); Refs = $refs }
        [void]$order.Add($key)
    }
    return @{ ById = $by; Order = $order.ToArray() }
}

function Get-PostureTweakMap {
    if ($null -eq $script:PostureTweakMapCache) { $script:PostureTweakMapCache = ConvertTo-PostureMap $script:PostureTweakRows }
    return $script:PostureTweakMapCache
}

function Get-PostureFindMap {
    if ($null -eq $script:PostureFindMapCache) { $script:PostureFindMapCache = ConvertTo-PostureMap $script:PostureFindRows }
    return $script:PostureFindMapCache
}

function Get-PostureThemeName([string]$Key) {
    foreach ($t in @($script:PostureThemes)) {
        $f = ([string]$t).Split('|')
        if ($f[0] -eq $Key) { return $f[1] }
    }
    return $Key
}

# Bir kaydın standart başvurularını tek satıra çevirir: "CIS v8 4.8  ·  NIST 800-53 CM-7  ·  NIS2 m.21(2)(g)"
function Format-PostureRefs($Entry) {
    if ($null -eq $Entry) { return '' }
    $parts = New-Object System.Collections.ArrayList
    foreach ($s in @($script:PostureStds)) {
        $f = ([string]$s).Split('|')
        if (-not $Entry.Refs.ContainsKey($f[0])) { continue }
        $list = @($Entry.Refs[$f[0]])
        if ($list.Count -eq 0) { continue }
        $pre = ''
        if ($f.Count -ge 3) { $pre = $f[2] }
        # Madde önekü ("m.") seçili dilde yazılır ("Art. 21(2)(g)"); Türkçede olduğu gibi kalır
        if ($pre -ne '' -and $script:LangOn) { $pre = ([string](Tr $pre)).TrimEnd() + ' ' }
        [void]$parts.Add($f[1] + ' ' + $pre + ($list -join ', '))
    }
    return ($parts.ToArray() -join '  ·  ')
}

# Bulguya karşılık gelen kayıt: önce bulgu kimliği, sonra bulgunun önerdiği tek katalog ayarı
function Get-PostureForFinding($F) {
    if ($null -eq $F) { return $null }
    $id = [string](Get-JsonProp $F 'Id')
    $fm = Get-PostureFindMap
    $key = $id
    if ($key.StartsWith('wifi-weak-', [System.StringComparison]::Ordinal)) { $key = 'wifi-weak' }
    if ($key -ne '' -and $fm.ById.ContainsKey($key)) { return $fm.ById[$key] }
    $tm = Get-PostureTweakMap
    $tid = ''
    $act = Get-JsonProp $F 'Action'
    if ($null -ne $act -and [string](Get-JsonProp $act 'Kind') -eq 'Tweak') { $tid = [string](Get-JsonProp $act 'Id') }
    if ($tid -eq '') {
        $fx = Get-JsonProp $F 'Fix'
        if ($null -ne $fx -and [string](Get-JsonProp $fx 'Kind') -eq 'Tweak') {
            $ids = @(Get-JsonProp $fx 'Ids')
            if ($ids.Count -eq 1) { $tid = [string]$ids[0] }
        }
    }
    if ($tid -eq '' -and $id.StartsWith('np-', [System.StringComparison]::Ordinal)) { $tid = $id.Substring(3) }
    if ($tid -ne '' -and $tm.ById.ContainsKey($tid)) { return $tm.ById[$tid] }
    return $null
}

# Bulgunun üzerine Std (başvuru satırı) ve Theme (konu anahtarı) yazar; eşleme yoksa dokunmaz.
function Set-FindingStd($F) {
    $e = Get-PostureForFinding $F
    if ($null -eq $e) { return }
    $txt = Format-PostureRefs $e
    if ($txt -eq '') { return }
    $F['Std'] = $txt
    $F['Theme'] = [string]$e.Theme
}

# Eşlenmiş katalog ayarlarının bu bilgisayardaki durumu (yalnızca okur).
#   Level 1-2 = temel kapsam, Level 3 = isteğe bağlı; Level 4 ayarlar kurum kararıdır, ölçülmez.
#   Skip: başka bir bulgunun zaten sunduğu ayar kimlikleri (Reported olarak işaretlenir).
function Get-PostureCoverage($Pr, $Skip = $null) {
    $tm = Get-PostureTweakMap
    $items = New-Object System.Collections.ArrayList
    foreach ($id in @($tm.Order)) {
        $e = $tm.ById[[string]$id]
        $c = Get-CatalogItem ([string]$id)
        if ($null -eq $c) { continue }
        if (-not (Test-OsOk ([string]$c.OS) $Pr)) { continue }
        if (-not (Test-WhenOk ([string]$c.When) $Pr)) { continue }
        $lv = [int]$c.Level
        if ($lv -lt 1 -or $lv -gt 3) { continue }
        $pend = [int](Get-TweakPending $c)
        if ($pend -lt 0) { continue }
        $st = 'ok'
        if ($pend -gt 0) { $st = 'pend' }
        if (Test-TweakBlocked $c) { $st = 'blocked' }
        $dup = $false
        if ($null -ne $Skip) { if ($Skip.ContainsKey([string]$id)) { $dup = $true } }
        [void]$items.Add(@{ Id = [string]$id; Title = [string]$c.Title; Theme = [string]$e.Theme; Level = $lv; Pending = $pend; Status = $st; Reported = $dup })
    }
    $all = $items.ToArray()
    $themes = New-Object System.Collections.ArrayList
    $base = 0
    $ok = 0
    foreach ($t in @($script:PostureThemes)) {
        $tf = ([string]$t).Split('|')
        $mine = @($all | Where-Object { $_.Theme -eq $tf[0] -and $_.Level -le 2 -and $_.Status -ne 'blocked' })
        $mok = @($mine | Where-Object { $_.Status -eq 'ok' }).Count
        [void]$themes.Add(@{ Key = $tf[0]; Name = $tf[1]; Base = [int]$mine.Count; Ok = [int]$mok; Pend = [int]($mine.Count - $mok) })
        if ($tf[0] -ne 'prv') { $base += $mine.Count; $ok += $mok }
    }
    $opt = @($all | Where-Object { $_.Theme -ne 'prv' -and $_.Level -eq 3 -and $_.Status -eq 'pend' }).Count
    $blk = @($all | Where-Object { $_.Status -eq 'blocked' }).Count
    $pct = -1
    if ($base -gt 0) { $pct = [int][math]::Floor(100.0 * $ok / $base + 0.5) }
    return @{ Items = $all; Themes = $themes.ToArray(); Base = [int]$base; Ok = [int]$ok; Pend = [int]($base - $ok); Opt = [int]$opt; Blocked = [int]$blk; Percent = [int]$pct }
}

# Başlık listesi: en çok 4 ayar adı + "ve N ayar daha"
function Get-PostureNameList($Items, [int]$Max = 4) {
    $arr = @($Items)
    $names = @($arr | Select-Object -First $Max | ForEach-Object { [string]$_.Title })
    $t = ($names -join '; ')
    if ($arr.Count -gt $Max) { $t += ' ve ' + [string]($arr.Count - $Max) + ' ayar daha' }
    return $t
}

# En zayıf konu: en az iki ayarı olan ve en düşük oranda uygulanmış konu (yoksa boş)
function Get-PostureWeakTheme($Cov) {
    $best = $null
    $bestRatio = 2.0
    foreach ($t in @($Cov.Themes)) {
        if ($t.Key -eq 'prv' -or $t.Base -lt 2 -or $t.Pend -lt 1) { continue }
        $r = [double]$t.Ok / [double]$t.Base
        if ($r -lt $bestRatio -or ($r -eq $bestRatio -and $t.Pend -gt $best.Pend)) { $best = $t; $bestRatio = $r }
    }
    return $best
}

# Sağlık taramasının "Güvenlik duruşu" denetimi. Başka bir bulgunun zaten sunduğu ayarlar yinelenmez.
function Chk_Posture {
    $pr = $sync.Profile
    $skip = @{}
    foreach ($f in @($script:Findings)) {
        $act = $f.Action
        if ($null -ne $act) { if ([string]$act.Kind -eq 'Tweak' -and [string]$act.Id -ne '') { $skip[[string]$act.Id] = $true } }
        $fx = $f.Fix
        if ($null -ne $fx) { if ([string]$fx.Kind -eq 'Tweak') { foreach ($i in @($fx.Ids)) { $skip[[string]$i] = $true } } }
    }
    $cov = Get-PostureCoverage $pr $skip
    if ($cov.Base -le 0) { return }
    $own = @($cov.Items | Where-Object { $_.Status -eq 'pend' -and $_.Reported -ne $true -and $_.Theme -ne 'prv' -and $_.Level -le 2 })
    $page = @{ Kind = 'Page'; Page = 'security'; Label = 'Güvenlik sayfası' }
    if ($cov.Pend -eq 0) {
        $dt = 'Denetlenen ' + [string]$cov.Base + ' ayarın hepsi uygulanmış (kapsam %100).'
        if ($cov.Opt -gt 0) { $dt += ' İsteğe bağlı ' + [string]$cov.Opt + ' ayar daha var; Güvenlik sayfasından seçebilirsiniz.' }
        if ($cov.Blocked -gt 0) { $dt += ' ' + [string]$cov.Blocked + ' ayarı Windows koruduğu için değiştirilemiyor; bunlar sayıya katılmadı.' }
        Add-Finding 'posture' 'sec' 'ok' 'Sertleştirme ayarları yerinde' $dt $null 0
    } elseif ($own.Count -gt 0) {
        $dt = 'Kapsam %' + [string]$cov.Percent + ' (' + [string]$cov.Ok + '/' + [string]$cov.Base + '). Eksik: ' + (Get-PostureNameList $own 3) + '.'
        $weak = Get-PostureWeakTheme $cov
        if ($null -ne $weak) { $dt += ' En zayıf konu: ' + [string]$weak.Name + ' (' + [string]$weak.Ok + '/' + [string]$weak.Base + ').' }
        $l1 = @($own | Where-Object { $_.Level -eq 1 })
        $fix = $null
        if ($l1.Count -gt 0) { $fix = New-TweakFix @($l1 | ForEach-Object { [string]$_.Id }) 'Güvenli düzeydeki ayarları uygula' 'Click' }
        $stt = 'info'
        $w = 2
        if ($own.Count -ge 5) { $stt = 'warn'; $w = 5 }
        Add-Finding 'posture' 'sec' $stt ('Sertleştirme ayarlarından ' + [string]$own.Count + ' tanesi uygulanmamış') $dt $page $w $fix
    }
    $prv = @($cov.Items | Where-Object { $_.Theme -eq 'prv' -and $_.Status -eq 'pend' -and $_.Reported -ne $true -and $_.Level -le 2 })
    if ($prv.Count -gt 0) {
        $pdt = 'Eksik: ' + (Get-PostureNameList $prv 3) + '. Uygulanınca Windows’un Microsoft’a ve reklam ağlarına gönderdiği veri azalır.'
        $pl1 = @($prv | Where-Object { $_.Level -eq 1 })
        $pfix = $null
        if ($pl1.Count -gt 0) { $pfix = New-TweakFix @($pl1 | ForEach-Object { [string]$_.Id }) 'Gizlilik varsayılanlarını uygula' 'Click' }
        Add-Finding 'posture-prv' 'sec' 'info' ('Veri paylaşımını azaltan ' + [string]$prv.Count + ' ayar uygulanmamış') $pdt @{ Kind = 'Page'; Page = 'optimize'; Label = 'Gizlilik ayarları' } 0 $pfix
    }
}

# Rapor bölümü: eşlenmiş ayarların durumu ve standart başvuruları
function Get-PostureReportSection {
    $cov = Get-PostureCoverage $sync.Profile $null
    if (@($cov.Items).Count -eq 0) { return $null }
    $tm = Get-PostureTweakMap
    $label = @{ ok = 'Uygulanmış'; pend = 'Uygulanmamış'; blocked = 'Windows engelliyor' }
    $rows = New-Object System.Collections.ArrayList
    foreach ($it in @($cov.Items)) {
        $e = $tm.ById[[string]$it.Id]
        [void]$rows.Add(@((Get-PostureThemeName ([string]$it.Theme)), [string]$it.Title, [string]$label[[string]$it.Status], (Format-PostureRefs $e)))
    }
    $summary = 'Kapsam: %' + [string]$cov.Percent + ' (' + [string]$cov.Ok + '/' + [string]$cov.Base + ' temel ayar uygulanmış; gizlilik ayarları ayrıca sayılır).'
    if ($cov.Percent -lt 0) { $summary = 'Bu bilgisayarda ölçülebilen temel ayar yok.' }
    [void]$rows.Add(@('Özet', $summary, '', ''))
    [void]$rows.Add(@('Not', 'Eşleme bilgilendirme amaçlıdır; sertifika, denetim sonucu ya da uygunluk beyanı değildir. Başlıklar: CIS Controls v8, NIST SP 800-53 Rev. 5, ISO/IEC 27001:2022 Ek A, BSI IT-Grundschutz Kompendium, AB 2022/2555 (NIS2) m.21, AB 2016/679 (GDPR), 6698 sayılı KVKK.', '', ''))
    return (New-Section 'Güvenlik duruşu ve standart eşlemesi' @('Konu', 'Ayar', 'Durum', 'İlgili başlıklar') $rows.ToArray())
}
