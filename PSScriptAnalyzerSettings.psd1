# PSScriptAnalyzer kural kumesi. kaynak/tools/kod_analizi.ps1 ve CI'deki kod-analizi isi kullanir.
# Uygulama Windows PowerShell 5.1 hedefler: sozdizimi uyumu 5.1'e gore denetlenir.
# Bilerek kullanilan kaliplar disarida birakilir:
#   bos catch bloklari (Windows yoklamalari sessiz hataya gore yazildi), Write-Host (konsol araclari),
#   betik kapsamli degiskenler, ShouldProcess (arayuz onizleme + geri alma kaydi + geri yukleme noktasi kullanir),
#   ad kurallari ve yorum yardimi. Geri kalan Error / Warning kurallari acik kalir.
# G-07 (27.11.2026) incelemesinden sonra disarida birakilanlar; her birinin bulgulari tek tek gozden gecirildi:
#   PSReviewUnusedParameter: 283 bulgunun hepsi olay isleyicisi ve geri cagri imzasi (param($s, $e), param($r), param($key, $ch))
#     ya da dize icinden tanimlanan islevlerde kullanilan parametre; imza cagiranin istedigi bicimde olmali.
#   PSAvoidUsingComputerNameHardcoded: tek bulgu Internet baglanti yoklamasi (Test-Connection 1.1.1.1, genel DNS); gizli ad yok.
#   PSAvoidUsingPlainTextForPassword: parola PBKDF2 icin bayta ya da restic'e ortam degiskeni olarak gider; SecureString yalnizca
#     ara donusum ekler, koruma saglamaz (Microsoft da yeni kod icin onermiyor).
#   PSUseLiteralInitializerForHashtable: bulgular bilerek karsilastirici (StringComparer) verilen tablolar; @{} buyuk/kucuk harf duyarsizdir.
#   PSUseSupportsShouldProcess: Show-Password'deki [bool]$Confirm "parolayi yeniden yaz" alanidir, -Confirm ortak parametresi degil;
#     ShouldProcess kurallari yukaridaki gerekceyle zaten disarida.
@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        'PSAvoidUsingEmptyCatchBlock',
        'PSAvoidUsingWriteHost',
        'PSAvoidGlobalVars',
        'PSUseShouldProcessForStateChangingFunctions',
        'PSShouldProcess',
        'PSUseSingularNouns',
        'PSUseApprovedVerbs',
        'PSUseBOMForUnicodeEncodedFile',
        'PSAvoidUsingPositionalParameters',
        'PSUseOutputTypeCorrectly',
        'PSProvideCommentHelp',
        'PSReviewUnusedParameter',
        'PSAvoidUsingComputerNameHardcoded',
        'PSAvoidUsingPlainTextForPassword',
        'PSUseLiteralInitializerForHashtable',
        'PSUseSupportsShouldProcess'
    )
    Rules        = @{
        PSUseCompatibleSyntax = @{
            Enable         = $true
            TargetVersions = @('5.1')
        }
    }
}
