# -*- coding: utf-8 -*-
"""p94: Arayuz metni taramasi (G-06). Katalogdaki 8.375 metinde unlem ve abarti soz eslesmeleri elle gozden gecirildi
(ayrinti: docs/metin-taramasi.md). Degisenler: "tek tikla" ve "aninda" gibi olculemeyen vaatler, "sorunsuz", uygulama
aciklamalarindaki "hizli" ve "guclu" ovgusu, kapanis iletisindeki ve EFS aciklamasindaki unlem. Windows'un resmi adlari,
derece etiketleri ve ozellik adlari (Akilli bakim, Hizli bakim, Guclu parola) degismez.
Parca dizgileri \'+ [char]0x.. +\' bicimiyle (raw=True) eslestirilir: yama motoru dizgi disindaki Turkce karakteri kabul etmez.
Metin degisince katalog kimligi degisir; 11 dildeki ceviriler ayni turn icinde yenilenir (multimizer-ceviri).
"""


def apply(b):
    b.rep("Ge' + [char]0x00E7 + 'mi' + [char]0x015F + ' sayfas' + [char]0x0131 + 'ndan tek t' + [char]0x0131 + 'kla geri alabilirsiniz",
          "Ge' + [char]0x00E7 + 'mi' + [char]0x015F + ' sayfas' + [char]0x0131 + 'ndan geri alabilirsiniz",
          count=1, raw=True, name='metin 01')
    b.rep("buradan tek t' + [char]0x0131 + 'kla d' + [char]0x00FC + 'zeltebilirsiniz",
          "buradan d' + [char]0x00FC + 'zeltebilirsiniz",
          count=1, raw=True, name='metin 02')
    b.rep("Ge' + [char]0x00E7 + 'mi' + [char]0x015F + ' sayfas' + [char]0x0131 + 'ndan tek t' + [char]0x0131 + 'kla silinir",
          "Ge' + [char]0x00E7 + 'mi' + [char]0x015F + ' sayfas' + [char]0x0131 + 'ndan silinir",
          count=1, raw=True, name='metin 03')
    b.rep("eksik olan tek t' + [char]0x0131 + 'kla kurulur",
          'eksik olan buradan kurulur',
          count=1, raw=True, name='metin 04')
    b.rep("i' + [char]0x00E7 + 'in tek t' + [char]0x0131 + 'kla s' + [char]0x0131 + 'k' + [char]0x0131 + ' koruma",
          "i' + [char]0x00E7 + 'in s' + [char]0x0131 + 'k' + [char]0x0131 + ' koruma",
          count=1, raw=True, name='metin 05')
    b.rep("Ge' + [char]0x00E7 + 'mi' + [char]0x015F + ' sayfas' + [char]0x0131 + 'ndan tek t' + [char]0x0131 + 'kla geri al' + [char]0x0131 + 'n' + [char]0x0131 + 'r",
          "Ge' + [char]0x00E7 + 'mi' + [char]0x015F + ' sayfas' + [char]0x0131 + 'ndan geri al' + [char]0x0131 + 'n' + [char]0x0131 + 'r",
          count=1, raw=True, name='metin 06')
    b.rep("internetini tek t' + [char]0x0131 + 'kla kesebilirsiniz",
          'internetini buradan kesebilirsiniz',
          count=1, raw=True, name='metin 07')
    b.rep("ve tek t' + [char]0x0131 + 'kla a' + [char]0x00E7 + '' + [char]0x0131 + 'lan i' + [char]0x015F + 'lemleri",
          "ve i' + [char]0x015F + 'lemleri",
          count=1, raw=True, name='metin 08')
    b.rep("her bilgisayarda sorunsuz ' + [char]0x00E7 + 'al' + [char]0x0131 + '' + [char]0x015F + 'mas' + [char]0x0131 + '",
          "her bilgisayarda d' + [char]0x00FC + 'zg' + [char]0x00FC + 'n ' + [char]0x00E7 + 'al' + [char]0x0131 + '' + [char]0x015F + 'mas' + [char]0x0131 + '",
          count=1, raw=True, name='metin 09')
    b.rep("adlar' + [char]0x0131 + 'n' + [char]0x0131 + ' an' + [char]0x0131 + 'nda arar",
          "adlar' + [char]0x0131 + 'n' + [char]0x0131 + ' arar",
          count=1, raw=True, name='metin 10')
    b.rep("dosyalar' + [char]0x0131 + ' an' + [char]0x0131 + 'nda bulan",
          "dosyalar' + [char]0x0131 + ' ad' + [char]0x0131 + 'yla bulan",
          count=1, raw=True, name='metin 11')
    b.rep("H' + [char]0x0131 + 'zl' + [char]0x0131 + ' ve gizlilik odakl' + [char]0x0131 + '",
          "Gizlilik odakl' + [char]0x0131 + '",
          count=1, raw=True, name='metin 12')
    b.rep("H' + [char]0x0131 + 'zl' + [char]0x0131 + ', a' + [char]0x00E7 + '' + [char]0x0131 + 'k kaynakl' + [char]0x0131 + '",
          "A' + [char]0x00E7 + '' + [char]0x0131 + 'k kaynakl' + [char]0x0131 + '",
          count=1, raw=True, name='metin 13')
    b.rep("PDF' + [char]0x2019 + 'leri ' + [char]0x00E7 + 'ok h' + [char]0x0131 + 'zl' + [char]0x0131 + ' a' + [char]0x00E7 + 'ar",
          "PDF' + [char]0x2019 + 'leri a' + [char]0x00E7 + 'ar",
          count=1, raw=True, name='metin 14')
    b.rep("Hafif ve h' + [char]0x0131 + 'zl' + [char]0x0131 + ' PDF",
          'Hafif PDF',
          count=1, raw=True, name='metin 15')
    b.rep("' + [char]0x00E7 + 'ok daha h' + [char]0x0131 + 'zl' + [char]0x0131 + ' a' + [char]0x00E7 + '' + [char]0x0131 + 'l' + [char]0x0131 + 'r",
          "daha h' + [char]0x0131 + 'zl' + [char]0x0131 + ' a' + [char]0x00E7 + '' + [char]0x0131 + 'l' + [char]0x0131 + 'r",
          count=1, raw=True, name='metin 16')
    b.rep("dosyalara eri' + [char]0x015F + 'ilemez!",
          "dosyalara eri' + [char]0x015F + 'ilemez.",
          count=1, raw=True, name='metin 17')
    b.rep('rler!   Multimizer',
          'rler.   Multimizer',
          count=2, raw=True, name='metin 18')
    b.rep("tüm değişiklikleri tek tıkla geri alabilirsiniz",
          "tüm değişiklikleri geri alabilirsiniz",
          xaml=True, name='metin 19')
    b.rep("D = ('Hafif ve g' + [char]0x00FC + [char]0x00E7 + 'l' + [char]0x00FC + ' metin/kod d' + [char]0x00FC + 'zenleyici.')",
          "D = ('Hafif metin/kod d' + [char]0x00FC + 'zenleyici.')",
          raw=True, name='metin 20')
