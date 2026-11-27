# -*- coding: utf-8 -*-
"""STANDARTLAR.md üreticisi.

Eşleme tabloları uygulamanın kendisindedir (mods/129_posture.ps1: PostureTweakRows, PostureFindRows,
PostureStds, PostureThemes). Bu betik o tablolardan, derlenmiş betikteki ayar adları ve düzeyleriyle
birlikte STANDARTLAR.md dosyasını üretir; belge ile kod birbirinden ayrışamaz.

Kullanım:
    python3 kaynak/tools/gen_standartlar.py            # STANDARTLAR.md dosyasını yazar
    python3 kaynak/tools/gen_standartlar.py --check    # dosya güncel değilse 1 ile çıkar (check.py bunu çağırır)
Derlenmiş betik (depoda Multimizer.ps1) önce üretilmiş olmalıdır.
"""
import io
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BUILD = os.path.dirname(HERE)
SCR = os.path.dirname(BUILD)
DEPO = os.path.basename(BUILD) == 'kaynak'  # depo yerleşimi: kaynak/ deponun içindedir
POSTURE = os.path.join(BUILD, 'mods', '129_posture.ps1')
BUILT = os.path.join(SCR, 'Multimizer.ps1') if DEPO else os.path.join(SCR, 'out', 'Multimizer.ps1')
OUT = os.path.join(SCR, 'STANDARTLAR.md') if DEPO else os.path.join(BUILD, 'docs8', 'STANDARTLAR.md')

# ---------------------------------------------------------------------------------------------
# Çerçeve bilgileri: anahtar -> (kısa ad, tam ad, başlık türü, kaynak adresi)
# ---------------------------------------------------------------------------------------------
FRAMEWORKS = {
    'CIS': ('CIS v8', 'CIS Critical Security Controls v8', 'Önlem (safeguard) numarası, ör. 4.8',
            'https://www.cisecurity.org/controls/v8'),
    'NIST': ('NIST 800-53', 'NIST SP 800-53 Rev. 5', 'Kontrol, ör. CM-7',
             'https://csrc.nist.gov/pubs/sp/800/53/r5/upd1/final'),
    'ISO': ('ISO 27001', 'ISO/IEC 27001:2022 Ek A', 'Kontrol, ör. A.8.9',
            'https://www.iso.org/standard/27001'),
    'BSI': ('BSI', 'BSI IT-Grundschutz-Kompendium (Edition 2023)', 'Modül, ör. SYS.2.2.3',
            'https://www.bsi.bund.de/DE/Themen/Unternehmen-und-Organisationen/Standards-und-Zertifizierung/IT-Grundschutz/IT-Grundschutz-Kompendium/it-grundschutz-kompendium_node.html'),
    'NIS2': ('NIS2', 'AB 2022/2555 (NIS2) Direktifi, m.21(2)', 'Bent, ör. m.21(2)(g)',
             'https://eur-lex.europa.eu/eli/dir/2022/2555/oj'),
    'GDPR': ('GDPR', 'AB 2016/679 (GDPR) Tüzüğü', 'Madde, ör. m.25',
             'https://eur-lex.europa.eu/eli/reg/2016/679/oj'),
    'KVKK': ('KVKK', '6698 sayılı Kişisel Verilerin Korunması Kanunu', 'Madde, ör. m.12',
             'https://www.mevzuat.gov.tr/mevzuat?MevzuatNo=6698&MevzuatTur=1&MevzuatTertip=5'),
}
PREFIX = {'NIS2': 'm.', 'GDPR': 'm.', 'KVKK': 'm.'}

# ---------------------------------------------------------------------------------------------
# Başlık adları (Türkçe kısa ad). Her kullanılan başlık için bir ad bulunmalıdır; üretici eksik ya da
# fazla ad bulursa durur, böylece tablo ile belge ayrışmaz.
# ---------------------------------------------------------------------------------------------
REF_TITLES = {
    'CIS': {
        '2.2': 'Desteklenen yazılımın kullanımı',
        '2.7': 'İzinli betik listesi',
        '3.3': 'Veri erişim denetim listeleri',
        '3.6': 'Kullanıcı cihazlarında veri şifreleme',
        '3.10': 'İletilen hassas verinin şifrelenmesi',
        '3.11': 'Bekleyen hassas verinin şifrelenmesi',
        '4.1': 'Güvenli yapılandırma süreci',
        '4.3': 'Otomatik oturum kilidi',
        '4.5': 'Uç cihazlarda güvenlik duvarı',
        '4.7': 'Varsayılan hesapların yönetimi',
        '4.8': 'Gereksiz hizmetlerin kaldırılması ya da kapatılması',
        '4.9': 'Güvenilir DNS sunucuları',
        '4.10': 'Taşınabilir cihazlarda otomatik kilitleme',
        '5.2': 'Benzersiz parola kullanımı',
        '5.4': 'Yönetici yetkilerini ayrı hesaplarla sınırlama',
        '7.3': 'İşletim sistemi yamalarının otomatik yönetimi',
        '7.4': 'Uygulama yamalarının otomatik yönetimi',
        '8.2': 'Denetim günlüklerinin toplanması',
        '8.3': 'Yeterli günlük depolama alanı',
        '8.5': 'Ayrıntılı denetim günlükleri',
        '8.11': 'Denetim günlüklerinin gözden geçirilmesi',
        '10.1': 'Zararlı yazılım korumasının kurulması',
        '10.2': 'Zararlı yazılım tanımlarının otomatik güncellenmesi',
        '10.3': 'Çıkarılabilir ortamda otomatik çalıştırmanın kapatılması',
        '10.5': 'İstismar karşıtı özelliklerin açılması',
        '10.7': 'Davranış tabanlı zararlı yazılım koruması',
        '11.1': 'Veri kurtarma süreci',
        '11.2': 'Otomatik yedekleme',
        '12.6': 'Güvenli ağ yönetimi ve iletişim protokolleri',
    },
    'NIST': {
        'AC-2': 'Hesap yönetimi',
        'AC-3': 'Erişim zorlaması',
        'AC-6': 'En az ayrıcalık',
        'AC-7': 'Başarısız oturum açma denemeleri',
        'AC-11': 'Cihaz kilidi',
        'AC-14': 'Kimlik doğrulamasız izinli eylemler',
        'AC-17': 'Uzaktan erişim',
        'AC-18': 'Kablosuz erişim',
        'AU-2': 'Olay günlüğü',
        'AU-4': 'Günlük depolama kapasitesi',
        'AU-6': 'Günlük kayıtlarının incelenmesi, çözümlenmesi ve raporlanması',
        'AU-12': 'Günlük kaydı üretimi',
        'CM-6': 'Yapılandırma ayarları',
        'CM-7': 'En az işlevsellik',
        'CP-9': 'Sistem yedeği',
        'CP-10': 'Sistem kurtarma ve yeniden kurma',
        'IA-2': 'Kimlik belirleme ve doğrulama (kurum kullanıcıları)',
        'IA-5': 'Kimlik doğrulayıcı yönetimi',
        'IA-6': 'Doğrulama geri bildirimi',
        'MP-7': 'Ortam kullanımı',
        'SA-22': 'Desteklenmeyen sistem bileşenleri',
        'SC-7': 'Sınır koruması',
        'SC-8': 'İletimde gizlilik ve bütünlük',
        'SC-12': 'Kriptografik anahtar oluşturma ve yönetimi',
        'SC-13': 'Kriptografik koruma',
        'SC-18': 'Taşınabilir kod',
        'SC-21': 'Güvenli ad çözümleme hizmeti',
        'SC-28': 'Bekleyen bilginin korunması',
        'SC-39': 'Süreç yalıtımı',
        'SI-2': 'Kusur giderme',
        'SI-3': 'Zararlı kod koruması',
        'SI-4': 'Sistem izleme',
        'SI-7': 'Yazılım, bellenim ve bilgi bütünlüğü',
        'SI-16': 'Bellek koruması',
    },
    'ISO': {
        'A.5.15': 'Erişim kontrolü',
        'A.5.16': 'Kimlik yönetimi',
        'A.5.17': 'Kimlik doğrulama bilgisi',
        'A.5.18': 'Erişim hakları',
        'A.5.34': 'Mahremiyet ve kişisel verilerin korunması',
        'A.6.7': 'Uzaktan çalışma',
        'A.7.7': 'Temiz masa ve temiz ekran',
        'A.7.10': 'Depolama ortamı',
        'A.8.1': 'Kullanıcı uç cihazları',
        'A.8.2': 'Ayrıcalıklı erişim hakları',
        'A.8.3': 'Bilgiye erişimin kısıtlanması',
        'A.8.5': 'Güvenli kimlik doğrulama',
        'A.8.7': 'Zararlı yazılımdan koruma',
        'A.8.8': 'Teknik açıklıkların yönetimi',
        'A.8.9': 'Yapılandırma yönetimi',
        'A.8.13': 'Bilgi yedekleme',
        'A.8.14': 'Bilgi işleme olanaklarında yedeklilik',
        'A.8.15': 'Günlükleme',
        'A.8.16': 'İzleme faaliyetleri',
        'A.8.19': 'Operasyonel sistemlere yazılım kurulumu',
        'A.8.20': 'Ağ güvenliği',
        'A.8.21': 'Ağ hizmetlerinin güvenliği',
        'A.8.23': 'Web filtreleme',
        'A.8.24': 'Kriptografi kullanımı',
    },
    'BSI': {
        'APP.1.1': 'Ofis ürünleri',
        'CON.1': 'Kriptografi kavramı (Kryptokonzept)',
        'CON.3': 'Veri yedekleme kavramı (Datensicherungskonzept)',
        'DER.1': 'Güvenlik olaylarının saptanması (Detektion von sicherheitsrelevanten Ereignissen)',
        'NET.2.1': 'WLAN işletimi (WLAN-Betrieb)',
        'NET.3.2': 'Güvenlik duvarı (Firewall)',
        'OPS.1.1.3': 'Yama ve değişiklik yönetimi (Patch- und Änderungsmanagement)',
        'OPS.1.1.4': 'Zararlı yazılımdan koruma (Schutz vor Schadprogrammen)',
        'OPS.1.1.5': 'Günlükleme (Protokollierung)',
        'OPS.1.2.5': 'Uzaktan bakım (Fernwartung)',
        'ORP.4': 'Kimlik ve yetki yönetimi (Identitäts- und Berechtigungsmanagement)',
        'SYS.2.1': 'Genel istemci (Allgemeiner Client)',
        'SYS.2.2.3': 'Windows istemcileri (Clients unter Windows)',
    },
    'NIS2': {
        '21(2)(b)': 'Olay yönetimi',
        '21(2)(c)': 'İş sürekliliği (yedek yönetimi, olağanüstü durum kurtarma) ve kriz yönetimi',
        '21(2)(e)': 'Ağ ve bilgi sistemlerinin edinilmesi, geliştirilmesi ve bakımında güvenlik (açık yönetimi dahil)',
        '21(2)(g)': 'Temel siber hijyen uygulamaları ve eğitim',
        '21(2)(h)': 'Kriptografi ve gerektiğinde şifreleme politikaları',
        '21(2)(i)': 'İnsan kaynakları güvenliği, erişim denetimi ve varlık yönetimi',
    },
    'GDPR': {
        '5(1)(c)': 'Veri minimizasyonu',
        '25': 'Tasarım ve varsayılan olarak veri koruma',
        '32': 'İşlemenin güvenliği',
    },
    'KVKK': {
        '4': 'Genel ilkeler (işlenen verinin amaçla bağlantılı, sınırlı ve ölçülü olması)',
        '12': 'Veri güvenliğine ilişkin yükümlülükler',
    },
}

# Bulgu kimliği -> kısa ad (bulgunun asıl başlığı bilgisayarın durumuna göre değiştiği için sabit ad kullanılır)
FIND_NAMES = {
    'acc-admin': 'Yerleşik Yönetici hesabı',
    'acc-adm': 'Yönetici grubunun üye sayısı',
    'acc-guest': 'Konuk hesabı',
    'acc-nopw': 'Parola gerektirmeyen etkin hesap',
    'pw-len': 'Asgari parola uzunluğu ilkesi',
    'pw-lock': 'Hesap kilitleme ilkesi',
    'autologon': 'Kayıt defterinde açık yazılı otomatik oturum açma parolası',
    'uac': 'Kullanıcı Hesabı Denetimi (UAC)',
    'logon-fail': 'Başarısız oturum açma denemeleri',
    'audit': 'Oturum açma olaylarının denetim kaydı',
    'av-rt': 'Gerçek zamanlı virüs koruması',
    'av-sig': 'Virüs tanımlarının güncelliği',
    'av-scan': 'Son virüs taramasının tarihi',
    'av-3p': 'Üçüncü taraf antivirüs',
    'av-cloud': 'Bulut tabanlı koruma',
    'av-pua': 'İstenmeyen uygulama koruması',
    'av-cfa': 'Kontrollü klasör erişimi',
    'av-tamper': 'Kurcalama Koruması',
    'av-excl': 'Defender tarama dışlamaları',
    'smartscreen': 'SmartScreen',
    'autorun': 'Çıkarılabilir sürücülerde otomatik çalıştırma',
    'ps2': 'PowerShell 2.0 motoru',
    'start-sus': 'Şüpheli konumdan başlayan program',
    'task-sus': 'Gizlenmiş ya da internetten komut çalıştıran zamanlanmış görev',
    'task-tmp': 'Temp ya da Public klasöründen çalışan zamanlanmış görev',
    'svc-tamper': 'İmzası bozulmuş hizmet dosyası',
    'svc-unsigned': 'Dijital imzasız üçüncü taraf hizmet',
    'svc-unquoted': 'Tırnaksız hizmet yolu',
    'svc-userpath': 'Kullanıcı klasöründen çalışan hizmet',
    'fw': 'Güvenlik duvarı profilleri',
    'fw-public-share': 'Genel ağlarda ağ keşfi ve dosya paylaşımı',
    'smb1': 'SMB 1.0',
    'llmnr': 'LLMNR ad çözümlemesi',
    'netbios': 'NetBIOS (TCP/IP üzerinden)',
    'rdp': 'Uzak Masaüstü ve NLA',
    'remote-assist': 'Uzaktan Yardım (davet)',
    'remotereg': 'Uzak Kayıt Defteri hizmeti',
    'ports': 'Ağdan erişilebilen dinleyen bağlantı noktaları',
    'share': 'Ağ paylaşımları',
    'share-wide': 'Herkese tam yetkili paylaşım',
    'upnp': 'UPnP / SSDP hizmetleri',
    'proxy': 'Sistem proxy sunucusu',
    'pac': 'Otomatik proxy betiği (PAC)',
    'hosts': 'hosts dosyasının güvenlik sitelerini engellemesi',
    'dns-odd': 'Bilinmeyen DNS sunucusu',
    'wifi-open': 'Şifresiz Wi-Fi ağlarına kendiliğinden bağlanma',
    'wifi-weak': 'Eski Wi-Fi şifreleme kipi',
    'arp-gw': 'Ağ geçidi MAC adresinin değişmesi',
    'vpn-ks-orphan': 'Etkin VPN bağlantısı olmadan kill-switch kuralı',
    'vpn-ks-partial': 'Eksik kill-switch kuralları',
    'vpn-public-novpn': 'Genel ağda VPN kullanılmaması',
    'vpn-doh-off': 'Şifresiz DNS sorguları',
    'bl': 'BitLocker durumu',
    'bl-data': 'Şifrelenmemiş veri sürücüleri',
    'bl-key': 'BitLocker kurtarma anahtarı',
    'sboot': 'Güvenli Önyükleme (Secure Boot)',
    'tpm': 'TPM güvenlik çipi',
    'drift': 'Windows’un geri çevirdiği ayarlar',
    'w11': 'Windows 11 uyumluluğu',
    'os-eol': 'Windows sürümünün destek durumu',
    'wu-age': 'Son güvenlik güncellemesinin yaşı',
    'wu-svc-off': 'Windows Update hizmetinin durumu',
    'backup': 'Dosya yedeği',
    'rp': 'Sistem geri yükleme noktası',
    'disk-pred': 'Disk arıza öngörüsü (SMART)',
}


# ---------------------------------------------------------------------------------------------
# Okuma
# ---------------------------------------------------------------------------------------------
def fail(msg):
    sys.stderr.write('gen_standartlar: ' + msg + '\n')
    raise SystemExit(2)


def read(path):
    if not os.path.exists(path):
        fail('dosya yok: ' + path)
    with io.open(path, encoding='utf-8') as f:
        return f.read()


def ps_array(src, name):
    m = re.search(r'\$script:' + name + r' = @\((.*?)\n\)\n', src, re.S)
    if not m:
        fail(name + ' tablosu bulunamadi')
    return re.findall(r"'([^']*)'", m.group(1))


def parse_entries(rows):
    out = []
    for r in rows:
        f = r.split('|')
        refs = {}
        for part in f[2:]:
            k, v = part.split('=', 1)
            refs[k] = [x for x in v.split(',') if x]
        out.append({'id': f[0], 'theme': f[1], 'refs': refs})
    return out


# Derlenmiş betikteki ASCII ifadeleri (tırnaklı dizgeler ve [char]0xNNNN) çözer
_TOK = re.compile(r"\s*(?:\[string\])?(?:'((?:[^']|'')*)'|\"([^\"$`]*)\"|\[char\]0x([0-9A-Fa-f]{2,4})|(\+)|(\()|(\)))")


def _eval(s, i):
    def atom(i):
        m = _TOK.match(s, i)
        if not m:
            return None
        if m.group(1) is not None:
            return (m.group(1).replace("''", "'"), m.end())
        if m.group(2) is not None:
            return (m.group(2), m.end())
        if m.group(3) is not None:
            return (chr(int(m.group(3), 16)), m.end())
        if m.group(5):
            r = expr(m.end())
            if not r:
                return None
            m2 = _TOK.match(s, r[1])
            if not m2 or not m2.group(6):
                return None
            return (r[0], m2.end())
        return None

    def expr(i):
        a = atom(i)
        if not a:
            return None
        out, i = a
        while True:
            m = _TOK.match(s, i)
            if m and m.group(4):
                b = atom(m.end())
                if not b:
                    return (out, i)
                out += b[0]
                i = b[1]
            else:
                return (out, i)
    return expr(i)


def tweak_info(built, tid):
    """(başlık, düzey) çifti; bulunamazsa None."""
    cands = [m.start() for m in re.finditer(r"Id = '" + re.escape(tid) + r"'", built)]
    cands += [m.start() for m in re.finditer(r"Add-RegTweak -Id '" + re.escape(tid) + r"'", built)]
    for st in cands:
        seg = built[st:st + 3500]
        t = re.search(r"(?:Title =|-Title) ", seg)
        if not t:
            continue
        r = _eval(seg, t.end())
        if not r:
            continue
        head = seg[:t.start()]
        lv = re.search(r"(?:Level =|-Level) ([0-9])", head)
        if not lv:
            lv = re.search(r"(?:Level =|-Level) ([0-9])", seg[:t.start() + 4000])
        return (r[0], int(lv.group(1)) if lv else 0)
    return None


def natkey(ref):
    return [int(x) if x.isdigit() else x for x in re.split(r'(\d+)', ref)]


def esc(s):
    return s.replace('|', '\\|')


def label(std, ref):
    return PREFIX.get(std, '') + ref


# ---------------------------------------------------------------------------------------------
# Üretim
# ---------------------------------------------------------------------------------------------
def build_text():
    post = read(POSTURE)
    built = read(BUILT)

    stds = [r.split('|') for r in ps_array(post, 'PostureStds')]
    std_keys = [s[0] for s in stds]
    if sorted(std_keys) != sorted(FRAMEWORKS):
        fail('PostureStds ile FRAMEWORKS ayni degil: %s / %s' % (std_keys, sorted(FRAMEWORKS)))
    disp = {s[0]: s[1] for s in stds}
    themes = [r.split('|') for r in ps_array(post, 'PostureThemes')]
    tweaks = parse_entries(ps_array(post, 'PostureTweakRows'))
    finds = parse_entries(ps_array(post, 'PostureFindRows'))

    # bulgu adları eksiksiz ve fazlasız olmalı
    fid = [e['id'] for e in finds]
    if set(fid) != set(FIND_NAMES):
        fail('FIND_NAMES ile PostureFindRows ayni degil. Eksik: %s Fazla: %s' % (sorted(set(fid) - set(FIND_NAMES)), sorted(set(FIND_NAMES) - set(fid))))

    # başlık adları eksiksiz ve fazlasız olmalı
    used = {k: set() for k in FRAMEWORKS}
    for e in tweaks + finds:
        for k, v in e['refs'].items():
            if k not in used:
                fail('bilinmeyen standart anahtari: ' + k)
            used[k].update(v)
    for k in FRAMEWORKS:
        miss = sorted(used[k] - set(REF_TITLES[k]))
        extra = sorted(set(REF_TITLES[k]) - used[k])
        if miss or extra:
            fail('REF_TITLES[%s] ile tablo ayni degil. Eksik: %s Fazla: %s' % (k, miss, extra))

    # ayar adları ve düzeyleri derlenmiş betikten
    tinfo = {}
    for e in tweaks:
        r = tweak_info(built, e['id'])
        if r is None:
            fail('katalogda ayar bulunamadi: ' + e['id'])
        if r[1] < 1 or r[1] > 3:
            fail('ayar duzeyi 1-3 disinda: %s = %s' % (e['id'], r[1]))
        tinfo[e['id']] = r

    L = []
    w = L.append
    w('<!-- Bu dosya kaynak/tools/gen_standartlar.py ile, uygulamadaki eşleme tablolarından (mods/129_posture.ps1) üretilir. Elle düzenlemeyin. -->')
    w('')
    w('# Standartlar eşlemesi')
    w('')
    w('Multimizer’ın sertleştirme ayarları ve güvenlik bulguları, aşağıdaki çerçevelerin ilgili başlıklarıyla eşlenir.')
    w('Bu belge eşlemenin tamamını listeler; uygulamadaki gösterim de aynı tablolardan gelir.')
    w('')
    w('> **Bu eşleme bilgilendirme amaçlıdır.** Sertifika, denetim sonucu ya da uygunluk beyanı değildir.')
    w('> Bir ayarın bir başlığa bağlanması, o başlığın karşılandığı anlamına gelmez: başlıkların çoğu politika, süreç, eğitim ve kanıt ister.')
    w('> Multimizer yalnızca bu bilgisayarın yapılandırmasına bakar; kurumun yönetim sistemini değerlendirmez.')
    w('')

    # ---- çerçeveler
    w('## Çerçeveler')
    w('')
    w('| Kısaltma | Çerçeve | Başlık biçimi | Kaynak |')
    w('|---|---|---|---|')
    for k in std_keys:
        short, full, kind, url = FRAMEWORKS[k]
        w('| %s | %s | %s | [%s](%s) |' % (disp[k], full, kind, re.sub(r'^https://(www\.)?', '', url).split('/')[0], url))
    w('')

    # ---- uygulamada nerede
    w('## Uygulamada nerede görünür')
    w('')
    w('- **Çözüm Merkezi > Sorunlar** (uzman kipi): her bulgunun altında “Standartlar: …” satırı olarak ilgili başlıklar yazılır.')
    w('- **Sağlık taraması**: “Güvenlik duruşu” denetimi, uygulanmamış sertleştirme ayarlarını tek bir bulguda toplar (kapsam yüzdesi, eksik ayarlar, en zayıf konu). Başka bir bulgunun zaten sunduğu ayarlar yinelenmez. Düzeltme, her zamanki yolla yapılır: önizleme, günlük, geri alma.')
    w('- **Envanter ve durum raporu** (Şirket Yönetimi ve `-Cli -Gorev Rapor`): “Güvenlik duruşu ve standart eşlemesi” bölümü, her ayarın durumunu ve başlıklarını listeler.')
    w('')
    w('### Kapsam yüzdesi nasıl hesaplanır')
    w('')
    w('- Yalnızca bu bilgisayarda uygulanabilen ayarlar sayılır (Windows sürümü ve donanım koşulu uymayanlar dışarıda kalır).')
    w('- Düzey 1 (Güvenli) ve düzey 2 (Dengeli) ayarlar **temel kapsamı** oluşturur. Düzey 3 (Güçlü) ayarlar isteğe bağlıdır; yüzdeye girmez, yalnızca “isteğe bağlı N ayar daha var” diye anılır. Düzey 4 (zevk ve kullanım tercihi) ayarlar bu belgede yoktur ve ölçülmez.')
    w('- Windows’un kendisinin koruduğu, değiştirilemeyen ayarlar yüzdeye katılmaz; ayrıca belirtilir.')
    w('- Gizlilik konusu ayrı sayılır: yüzde yalnızca diğer yedi konudan hesaplanır.')
    w('')

    # ---- sayılar
    w('## Sayılar')
    w('')
    w('%d ayar ve %d bulgu eşlenmiştir.' % (len(tweaks), len(finds)))
    w('')
    w('| Çerçeve | Kullanılan başlık | Eşlenen ayar | Eşlenen bulgu |')
    w('|---|---:|---:|---:|')
    for k in std_keys:
        nt = sum(1 for e in tweaks if k in e['refs'])
        nf = sum(1 for e in finds if k in e['refs'])
        w('| %s | %d | %d | %d |' % (disp[k], len(used[k]), nt, nf))
    w('')
    w('| Konu | Ayar | Bulgu |')
    w('|---|---:|---:|')
    for t in themes:
        nt = sum(1 for e in tweaks if e['theme'] == t[0])
        nf = sum(1 for e in finds if e['theme'] == t[0])
        w('| %s | %d | %d |' % (t[1], nt, nf))
    w('')

    # ---- konulara göre tablolar
    w('## Konulara göre eşleme')
    w('')
    w('“Ayar” satırları Hızlandır ve Güvenlik sayfalarındaki sertleştirme ayarlarıdır; adın yanında düzeyi yazılıdır (1 Güvenli, 2 Dengeli, 3 Güçlü). “Bulgu” satırları sağlık taramasının kontrol ettiği durumlardır. Bir hücrede “·”, o çerçevede ilgili başlık eşlenmediği anlamına gelir.')
    w('')
    for t in themes:
        mine_t = [e for e in tweaks if e['theme'] == t[0]]
        mine_f = [e for e in finds if e['theme'] == t[0]]
        if not mine_t and not mine_f:
            continue
        cols = [k for k in std_keys if any(k in e['refs'] for e in mine_t + mine_f)]
        w('### %s' % t[1])
        w('')
        w('| Tür | Ad | ' + ' | '.join(disp[k] for k in cols) + ' |')
        w('|---|---|' + '|'.join('---' for _ in cols) + '|')
        for e in mine_t:
            title, lv = tinfo[e['id']]
            cells = [', '.join(label(k, x) if k in ('NIS2', 'GDPR', 'KVKK') else x for x in e['refs'].get(k, [])) or '·' for k in cols]
            w('| Ayar | %s (düzey %d) | %s |' % (esc(title), lv, ' | '.join(cells)))
        for e in mine_f:
            cells = [', '.join(label(k, x) if k in ('NIS2', 'GDPR', 'KVKK') else x for x in e['refs'].get(k, [])) or '·' for k in cols]
            w('| Bulgu | %s | %s |' % (esc(FIND_NAMES[e['id']]), ' | '.join(cells)))
        w('')

    # ---- başlıktan ayara
    w('## Başlıktan ayara')
    w('')
    w('Her çerçeve için, kullanılan başlıkların hangi ayar ve bulgularla ilişkilendirildiği. Başlık adları kısa Türkçe özetlerdir; bağlayıcı metin çerçevenin kendi yayınıdır.')
    w('')
    for k in std_keys:
        short, full, kind, url = FRAMEWORKS[k]
        refs = sorted(used[k], key=natkey)
        w('<details>')
        w('<summary><b>%s</b> — %d başlık</summary>' % (full, len(refs)))
        w('')
        for ref in refs:
            ts = [tinfo[e['id']][0] for e in tweaks if ref in e['refs'].get(k, [])]
            fs = [FIND_NAMES[e['id']] for e in finds if ref in e['refs'].get(k, [])]
            parts = []
            if ts:
                parts.append('Ayarlar: ' + '; '.join(ts))
            if fs:
                parts.append('Bulgular: ' + '; '.join(fs))
            w('- **%s** %s — %s' % (label(k, ref), REF_TITLES[k][ref], ' · '.join(parts)))
        w('')
        w('</details>')
        w('')

    # ---- sınırlar
    w('## Sınırlar')
    w('')
    w('- Eşleme **ayar düzeyindedir**. Kurumun politikaları, eğitimi, olay yönetimi süreci, tedarik zinciri ya da fiziksel güvenliği bu belgenin ve uygulamanın kapsamı dışındadır.')
    w('- Bir başlığın yanında ayar görünmesi, o başlığın karşılandığını göstermez; yalnızca ayarın o önleme katkı verdiğini söyler. Tersine, bir başlığın yanında ayar bulunmaması da başlığın gereksiz olduğu anlamına gelmez.')
    w('- NIS2 yalnızca kapsamdaki “temel” ve “önemli” kuruluşlar için bağlayıcıdır; KVKK ve GDPR kişisel veri işleyenleri ilgilendirir. Bu başlıklar, kuruluşunuzun kapsamda olup olmadığını belirlemez.')
    w('- Başlık numaraları belirtilen sürümlere göredir (CIS v8, NIST 800-53 Rev. 5, ISO/IEC 27001:2022, BSI Edition 2023). Çerçeveler güncellenirse tablolar `kaynak/mods/129_posture.ps1` içinde güncellenir ve bu belge yeniden üretilir.')
    w('- Uygulama bu eşleme nedeniyle hiçbir ayarı kendiliğinden uygulamaz. Her düzeltme önizlenir, günlüğe yazılır ve geri alınabilir.')
    w('')
    w('## Yeniden üretme')
    w('')
    w('```')
    w('python3 kaynak/tools/gen_standartlar.py          # bu dosyayı yazar')
    w('python3 kaynak/tools/gen_standartlar.py --check  # dosya güncel mi?')
    w('```')
    w('')
    w('Yeni bir ayar ya da bulgu eşlerken önce `PostureTweakRows` / `PostureFindRows` tablosuna satır ekleyin; ardından bu betikteki `REF_TITLES` ve `FIND_NAMES` sözlüklerini tamamlayın. Eksik ya da artık bir ad varsa betik durur.')
    w('')
    return '\n'.join(L)


def main(argv):
    text = build_text()
    if '--check' in argv:
        cur = None
        if os.path.exists(OUT):
            with io.open(OUT, encoding='utf-8', newline='') as f:
                cur = f.read()
        if cur != text:
            sys.stderr.write('STANDARTLAR.md güncel değil: python3 kaynak/tools/gen_standartlar.py ile yeniden üretin.\n')
            return 1
        print('STANDARTLAR.md güncel (%d satır)' % (text.count('\n') + 1))
        return 0
    with io.open(OUT, 'w', encoding='utf-8', newline='') as f:
        f.write(text)
    print('yazıldı: %s (%d satır, %d bayt)' % (OUT, text.count('\n') + 1, len(text.encode('utf-8'))))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
