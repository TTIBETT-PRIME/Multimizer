# ==================================================================
#  BAĞLANTILAR: komut satırı sayfa/sekme hedefleri
#  "ac <sözcük>" komutu bir sayfayı ya da "sayfa:sekme" biçimindeki bir sekmeyi açar (örnek: solve:prep = Çözüm Merkezi > Hazırlık).
# ==================================================================
function Split-CmdTarget([string]$Target) {
    $pg = $Target
    $sub = ''
    $ix = $Target.IndexOf(':')
    if ($ix -gt 0) {
        $pg = $Target.Substring(0, $ix)
        $sub = $Target.Substring($ix + 1)
    }
    return @{ Page = $pg; Sub = $sub }
}

function Open-CmdPage([string]$Target) {
    $t = Split-CmdTarget $Target
    Open-Page ([string]$t.Page) ([string]$t.Sub)
}
