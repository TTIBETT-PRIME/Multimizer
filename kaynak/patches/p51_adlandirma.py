# -*- coding: utf-8 -*-
"""Arayüz adlarının profesyonel adlarla değiştirilmesi (yalnızca görünen metin; ayar anahtarları ve komut adları aynı kalır).

Temalar   : Fütüristik -> Koyu neon, Kum -> Krem, Hacker -> Terminal (yeşil), Buzlu Cam -> Buzlu cam (açık),
            Holografik -> Koyu cam, Renk Akışı -> Renk geçişi, Derin Uzay -> Koyu mor
Yerleşim  : Hacker -> Terminal
Tasarımlar: Atölye -> Kartlı, Sıfır Noktası -> Minimal, Morpheus Ağı -> Ağ konsolu, Komuta Merkezi -> Gösterge paneli
Sayfalar  : Hızlandır -> Optimizasyon
Düğmeler  : Ağdan at -> Ağdan çıkar, Taşınma kiti -> Taşıma paketi, Bilgisayarım -> Bu bilgisayar
Duman testi görünen adı -> Arayüz doğrulaması
"""

# (eski, yeni, beklenen adet) - eski ve yeni tırnaklı dizgi parçalarıdır; Türkçe harfler derleyicide [char] biçimine çevrilir
PLAIN = [
    # temalar
    ("T = 'Fütüristik'", "T = 'Koyu neon'", 1),
    ("T = 'Kum (sıcak açık)'", "T = 'Krem (sıcak açık)'", 1),
    ("Hacker = @{ T = 'Hacker';", "Hacker = @{ T = 'Terminal (yeşil)';", 1),
    ("T = 'Buzlu Cam'", "T = 'Buzlu cam (açık)'", 1),
    ("T = 'Holografik'", "T = 'Koyu cam'", 1),
    ("T = 'Renk Akışı'", "T = 'Renk geçişi'", 1),
    ("T = 'Derin Uzay'", "T = 'Koyu mor'", 1),
    # yerleşim
    ("Hacker    = @{ T = 'Hacker';", "Hacker    = @{ T = 'Terminal';", 1),
    # tasarımlar ve ana ekran biçimleri
    ("T = 'Atölye'", "T = 'Kartlı'", 2),
    ("T = 'Sıfır Noktası'", "T = 'Minimal'", 2),
    ("T = 'Morpheus Ağı'", "T = 'Ağ konsolu'", 2),
    ("T = 'Komuta Merkezi'", "T = 'Gösterge paneli'", 2),
    # hazır görünümler
    ("SadeAcik = 'Sade ve beyaz'", "SadeAcik = 'Sade açık'", 1),
    ("Hacker = 'Hacker'", "Hacker = 'Terminal'", 1),
    ("Atolye = 'Atölye'", "Atolye = 'Kartlı'", 1),
    ("Sifir = 'Sıfır Noktası'", "Sifir = 'Minimal'", 1),
    ("Morpheus = 'Morpheus Ağı'", "Morpheus = 'Ağ konsolu'", 1),
    ("Komuta = 'Komuta Merkezi'", "Komuta = 'Gösterge paneli'", 1),
    # başlık yazıları
    ("$d.Tagline = 'MORPHEUS // AĞ'", "$d.Tagline = 'AĞ KONSOLU'", 1),
    ("'root@multimizer:~# _'", "'multimizer@pc:~$ _'", 1),
    ("'root@*'", "'multimizer@*'", 2),
    # parça görünümü
    ("Slate = 'Kurşun (üst çizgili)'", "Slate = 'Antrasit (üst çizgili)'", 1),
    # sayfa adı
    ("optimize = 'Hızlandır'", "optimize = 'Optimizasyon'", 1),
    ("optimize = 'HIZLANDIR'", "optimize = 'OPTİMİZASYON'", 1),
    # komut takma adı ve arama anahtar sözcükleri (eski sözcük de geçerli kalır)
    ("hizlandir = 'optimize'; optimize = 'optimize';", "hizlandir = 'optimize'; optimizasyon = 'optimize'; optimize = 'optimize';", 1),
    ("optimize = 'hizlandir gizlilik telemetri performans ayar'", "optimize = 'optimizasyon hizlandir gizlilik telemetri performans ayar'", 1),
    # paket adı (dışa aktarılan profil)
    ("New-ProfileObject ('Kit ' + $env:COMPUTERNAME)", "New-ProfileObject ('Paket ' + $env:COMPUTERNAME)", 1),
]

# tam dizgi sabitleri: (eski, yeni) - kaç kez geçtiği ne olursa olsun hepsi değiştirilir (en az bir kez bulunmalı)
LITERALS = [
    ("Ağdan at", "Ağdan çıkar"),
    ("Ağdan atma adımları", "Ağdan çıkarma adımları"),
    ("Duman testi", "Arayüz doğrulaması"),
    ("Duman testi: ", "Arayüz doğrulaması: "),
    ("  Duman testi örnek satırı (", "  Arayüz doğrulaması örnek satırı ("),
    ("Duman testi: komut satırı örnek satırı", "Arayüz doğrulaması: komut satırı örnek satırı"),
    ("Duman testi: soluk örnek satır", "Arayüz doğrulaması: soluk örnek satır"),
    ("Taşınma kiti hazır", "Taşıma paketi hazır"),
    ("Taşınma kiti hazır.", "Taşıma paketi hazır."),
    ("Taşınma kiti hazır: ", "Taşıma paketi hazır: "),
    ("Taşınma kiti hazırlanıyor", "Taşıma paketi hazırlanıyor"),
    ("Taşınma kitini oluştur", "Taşıma paketini oluştur"),
    ("Kit hazırlanamadı; günlüğe bakın.", "Paket hazırlanamadı; günlüğe bakın."),
    ("Kit şu klasöre hazırlanacak:", "Paket şu klasöre hazırlanacak:"),
    ("Kiti harici diske ya da USB belleğe kaydedin; sıfırlayacağınız diske kaydederseniz o da silinir.",
     "Paketi harici diske ya da USB belleğe kaydedin; sıfırlayacağınız diske kaydederseniz o da silinir."),
    ("Kitin içinde ne olur", "Paketin içinde ne olur"),
    ("Kitin kaydedileceği klasörü seçin (tercihen harici disk ya da USB bellek)",
     "Paketin kaydedileceği klasörü seçin (tercihen harici disk ya da USB bellek)"),
    ("Son hazırlanan kit", "Son hazırlanan paket"),
    ("Kayıtlı kablosuz ağlar. Parolalar dosyaya açık yazılır; kiti güvendiğiniz bir yerde saklayın",
     "Kayıtlı kablosuz ağlar. Parolalar dosyaya açık yazılır; paketi güvendiğiniz bir yerde saklayın"),
    ("WiFi klasörü varsa içindeki parolalar düz metindir; kiti güvendiğiniz bir yerde saklayın, işiniz bitince silin.",
     "WiFi klasörü varsa içindeki parolalar düz metindir; paketi güvendiğiniz bir yerde saklayın, işiniz bitince silin."),
    ("Not: Bu kit kişisel dosyalarınızı içermez. Belgeler, Resimler gibi klasörler için Yedek sayfasındaki dosya yedeğini kullanın.",
     "Not: Bu paket kişisel dosyalarınızı içermez. Belgeler, Resimler gibi klasörler için Yedek sayfasındaki dosya yedeğini kullanın."),
    # Hızlandır -> Optimizasyon (sayfa adı ve gönderme metinleri)
    ("Hızlandır", "Optimizasyon"),
    ("Hızlandır sayfası", "Optimizasyon sayfası"),
    ("Hızlandırma ayarları", "Optimizasyon ayarları"),
    ("Hızlandırma, güvenlik ve ağ koruması", "Optimizasyon, güvenlik ve ağ koruması"),
    ("Bilgisayarınızı sade ve güvenli biçimde hızlandırın.", "Bilgisayarınızı sade ve güvenli biçimde optimize edin."),
    (". Hızlandırma ayarları bu bilgisayarda fark yaratır.", ". Optimizasyon ayarları bu bilgisayarda fark yaratır."),
    (" ayar eski haline dönmüş. Hızlandır sayfasında \"Geri dönenleri seç\" ile yeniden uygulayabilirsiniz.",
     " ayar eski haline dönmüş. Optimizasyon sayfasında \"Geri dönenleri seç\" ile yeniden uygulayabilirsiniz."),
    ("1. Bu bilgisayarda Hızlandır, Güvenlik, Şirket ilkeleri sayfalarında istediğiniz ayarları işaretleyin (Hizmetler ve Uygulamalar sayfasındaki işaretler de eklenir).",
     "1. Bu bilgisayarda Optimizasyon, Güvenlik, Şirket ilkeleri sayfalarında istediğiniz ayarları işaretleyin (Hizmetler ve Uygulamalar sayfasındaki işaretler de eklenir)."),
    ("Dışa aktarılacak seçim yok. Önce Hızlandır / Güvenlik / Şirket ilkeleri sayfalarında ayar işaretleyin.",
     "Dışa aktarılacak seçim yok. Önce Optimizasyon / Güvenlik / Şirket ilkeleri sayfalarında ayar işaretleyin."),
    ("Henüz kayıtlı değişiklik yok. Hızlandır, Hizmetler gibi sayfalardan uyguladığınız her şey burada görünür.",
     "Henüz kayıtlı değişiklik yok. Optimizasyon, Hizmetler gibi sayfalardan uyguladığınız her şey burada görünür."),
    ("Hızlandır sayfasında önerilen ayarlar işaretli geliyor; önizleyip uygulayabilirsiniz.",
     "Optimizasyon sayfasında önerilen ayarlar işaretli geliyor; önizleyip uygulayabilirsiniz."),
    ("Yonga seti, depolama ve ağ sürücülerini güncelleyin. Hızlandır sayfasındaki “Hızlı Başlatma’yı kapat” ayarını deneyin. Aygıt Yöneticisi’nde ağ bağdaştırıcısının “Gücü tasarruf etmek için bilgisayarın bu aygıtı kapatmasına izin ver” seçeneğini kaldırın.",
     "Yonga seti, depolama ve ağ sürücülerini güncelleyin. Optimizasyon sayfasındaki “Hızlı Başlatma’yı kapat” ayarını deneyin. Aygıt Yöneticisi’nde ağ bağdaştırıcısının “Gücü tasarruf etmek için bilgisayarın bu aygıtı kapatmasına izin ver” seçeneğini kaldırın."),
    ("Sayfa aç: \"ac guvenlik\" (panel, hizlandir, hizmetler, uygulamalar, temizlik, ...)",
     "Sayfa aç: \"ac guvenlik\" (panel, optimizasyon, hizmetler, uygulamalar, temizlik, ...)"),
    # taşıma paketi başlığı
    ("MULTIMIZER TAŞINMA / FORMAT KİTİ", "MULTIMIZER TAŞIMA / FORMAT PAKETİ"),
    # Terminal yerleşimi (iç ad Hacker kalır; kullanıcıya görünen hata ve günlük metinleri)
    ("Hacker başlık yazısı uygulanmadı: ", "Terminal başlık yazısı uygulanmadı: "),
    ("Hacker başlık yazısı geri alınmadı: ", "Terminal başlık yazısı geri alınmadı: "),
]

# XAML öznitelikleri: (eski, yeni)
XAML = [
    ('Text="Hızlandır"', 'Text="Optimizasyon"'),
    ('Content="Taşınma kiti"', 'Content="Taşıma paketi"'),
    ('Content="Kiti oluştur..."', 'Content="Paketi oluştur..."'),
    ('Content="Bilgisayarım"', 'Content="Bu bilgisayar"'),
    ('Content="Ağdan at"', 'Content="Ağdan çıkar"'),
    ('Text="HIZLANDIRMA · GÜVENLİK · AĞ KORUMA"', 'Text="OPTİMİZASYON · GÜVENLİK · AĞ KORUMA"'),
    ('ToolTip="Hızlandır: gizlilik, performans, görünüm ve oyun ayarları"', 'ToolTip="Optimizasyon: gizlilik, performans, görünüm ve oyun ayarları"'),
]

# sayfa adı tablosu ve gösterge kartı (tek tırnaklı parantezli biçim)
PAGE_NAMES = [
    ("pcinfo   = @{ T = 'Bilgisayarım';", "pcinfo   = @{ T = 'Bu bilgisayar';", 1),
]


def _count(b, s):
    return b.t.count(s)


def apply(b):
    for old, new, cnt in PLAIN:
        b.rep(old, new, count=cnt, name='p51 ' + old[:40])
    from tr2ascii import convert, xaml as xaml_escape
    for old, new in LITERALS:
        o = convert("'" + old + "'", 'yama')
        n = convert("'" + new + "'", 'yama')
        # kaynakta ardisik Turkce harfler bazen "+ '' +" ile ayrilmis, bazen birlesik yazilmis; iki bicim de denenir
        found = 0
        for oo, nn in ((o, n), (o.replace(" + '' + ", ' + '), n.replace(" + '' + ", ' + '))):
            c = b.t.count(oo)
            if c > 0:
                b.t = b.t.replace(oo, nn)
                found += c
        if found < 1:
            raise SystemExit('p51 literal bulunamadi: ' + old[:70])
    for old, new in XAML:
        o = xaml_escape(old)
        n = xaml_escape(new)
        c = b.t.count(o)
        if c < 1:
            raise SystemExit('p51 xaml bulunamadi: ' + old)
        b.t = b.t.replace(o, n)
    for old, new, cnt in PAGE_NAMES:
        b.rep(old, new, count=cnt, name='p51 sayfa')
