# -*- coding: utf-8 -*-
"""p81: "Kullanici klasorunden calisan hizmet" bulgusu gercek riski anlatir.

Gercek bilgisayardaki taramada bulgu, kullanicinin bilerek kurdugu bir aracin hizmeti icin cikti (DNSCrypt proxy,
AppData altinda). Eski metin yalnizca "taniyorsaniz zararsiz olabilir" anlamina geliyordu; asil risk, taninan program icin
de gecerli: kullanicinin yazabildigi klasordeki hizmet dosyasini, o hesapta calisan herhangi bir program degistirip sistem
yetkisiyle calistirabilir. Metin bunu soyler ve daha guvenli kurulumu onerir."""


def apply(b):
    b.rep("""(('Hizmetler normalde Program Files gibi korumal' + [char]0x0131 + ' klas' + [char]0x00F6 + 'rlerden ' + [char]0x00E7 + 'al' + [char]0x0131 + '' + [char]0x015F + '' + [char]0x0131 + 'r. Tan' + [char]0x0131 + 'mad' + [char]0x0131 + '' + [char]0x011F + '' + [char]0x0131 + 'n' + [char]0x0131 + 'z bir program ise zararl' + [char]0x0131 + ' olabilir: ') + $names)""",
          """('Hizmetler normalde Program Files gibi korumalı klasörlerden çalışır. Tanımadığınız bir program zararlı olabilir. Tanıdığınız bir program olsa bile, bu hesapta çalışan başka bir program hizmetin dosyasını değiştirip sistem yetkisiyle çalıştırabilir; mümkünse programı Program Files altına kurun: ' + $names)""",
          name='p81 hizmet yolu metni')
