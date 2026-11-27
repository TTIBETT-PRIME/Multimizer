# kaynak/

`Multimizer.ps1` ile `Eklenti/Kurtarma.ps1` ve `Eklenti/DiskSilme.ps1` bu klasördeki kaynaktan **üretilir**. Üretilmiş dosyaları elle değiştirmeyin; bir sonraki derlemede kaybolurlar. Tasarımın gerekçesi için [MIMARI.md](../MIMARI.md) bölüm 9 ve 10, kurallar için [CONTRIBUTING.md](../CONTRIBUTING.md) “Derleme” bölümüne bakın.

```
python3 kaynak/build.py     # Multimizer.ps1 ve Eklenti/ dosyalarını yerinde yeniler (özet kaydı dahil)
python3 kaynak/check.py     # derleme sonrası denetimler; PowerShell 7 (pwsh) gerekir
python3 kaynak/tools/gen_standartlar.py   # STANDARTLAR.md dosyasını yeniler
```

Python 3.9 ya da üstü yeterlidir; ek paket gerekmez. Derleme belirlenimlidir: aynı kaynaktan her seferinde aynı bayt dizisi çıkar, CI bunu denetler.

| Yol | İçerik |
|---|---|
| `base.ps1` | Önceki yayının (8.0.0) betiği, yalnızca ASCII. Değişiklikler bunun üzerine yamalarla eklenir. |
| `mods/*.ps1` | Yeni modüller (UTF-8, Türkçe harfli). Derlemede ASCII’ye çevrilir. |
| `patches/pNN_*.py` | Tabandaki kodu değiştiren ve modülleri bağlayan yamalar; alfabetik sırayla uygulanır. |
| `src/` | `Kurtarma` ve `DiskSilme` eklentilerinin şablonları ve C# 5 motor kaynakları. |
| `tools/` | PowerShell AST denetimi (`check.ps1`), C# 5 dil denetimi (`csharp5.ps1`), STANDARTLAR.md üreticisi, bilinen komut listesi. |
| `build.py`, `check.py`, `tr2ascii.py` | Derleyici, derleme sonrası denetim, ASCII çevirici. |

Bir yama beklediği metni bulamazsa (ya da beklenenden fazla yerde bulursa) derleme durur; sessizce yanlış yere yazmaz.
