# -*- coding: utf-8 -*-
"""p76: Windows isteğe bağlı özelliğinin durumu tek yardımcıdan okunur (Get-WinFeatureInfo, mods/158).
DISM yönetici ister; yönetici değilken ya da DISM okuyamazsa Win32_OptionalFeature (WMI) kullanılır.
Toplu okumada (StateBatch) tüm özellikler bir kez okunur; DISM bir kez başarısız olursa o partide yeniden denenmez."""


def apply(b):
    b.rep("    try { $f = Get-WindowsOptionalFeature -Online -FeatureName $name -ErrorAction Stop } catch { $readErr = $_.Exception.Message }\n",
          "    try { $f = Get-WinFeatureInfo $name } catch { $readErr = $_.Exception.Message }\n",
          name='p76 ozellik okuma')
    # Yeniden baslatma bekleyen degisiklik etkin durum sayilir: acilmasi bekleyen ozellik "acik", kapanmasi bekleyen "kapali".
    # Yoksa ayni ayar ikinci kez uygulanir ve durum etiketi yeniden baslatmaya dek "uygulanmamis" gorunur.
    b.rep("    $isOn = ([string]$f.State -eq 'Enabled')\n    $wantOn = ([string]$Op.State -eq 'Enabled')\n",
          "    $isOn = (@('Enabled', 'EnablePending') -contains [string]$f.State)\n    $wantOn = ([string]$Op.State -eq 'Enabled')\n",
          name='p76 bekleyen durum')
