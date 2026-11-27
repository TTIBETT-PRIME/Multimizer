<#
    Acilis.ps1  -  Multimizer pencere acmayan baslatici (acilis ekrani + denetci)
    Baslat.bat arayuz kipinde bunu gizli bir PowerShell olarak calistirir; ayri bir konsol penceresi acik kalmaz.
    Iki rol (ayni dosya):
      Karsilama (varsayilan)   Acilis ekranini gosterir, Denetci'yi baslatir (gerekirse yonetici izni ister) ve uygulamanin
                               penceresi acilinca kapanir. Yonetici izni verilmezse nedenini bir ileti ile soyler.
      Denetci (-Rol Denetci)   Yonetici olarak calisir: uygulamayi gizli konsolla baslatir ve bitisini bekler. Pencere acildiktan sonra
                               negatif (Windows cokme) kodla biterse bir kez guvenli kipte yeniden baslatir; hic acilamadiysa
                               Tani.ps1 raporunu bir pencerede gosterir.
    Dosyalar (ProgramData\Multimizer):
      acilis-KOD.txt       uygulamanin yazdigi acilis asamasi  (yuzde|sonraki yuzde|anahtar|surec)
      oturum-acik-KOD.txt  uygulama penceresi acilinca uygulamanin yazdigi isaret dosyasi
      acilis-KOD.son       Denetci'nin sonucu  (cikis kodu|sonuc)
      Kayitlar\acilis-iz.txt   bu betigin kisa izi (en cok 64 KB)
    Kullanim:  powershell -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File Acilis.ps1 [-Kod 123456] [uygulama parametreleri]
    Kisayollar ve uygulamanin kendi yeniden baslatmasi da bu dosyayi acar. Sistem ayarlarina dokunmaz.
    Bu dosya yalnizca ASCII karakter icerir (metinler \uXXXX olarak gomulu); build/src/Acilis.tpl.ps1 + baslatma_dil.tsv dosyalarindan uretilir.
#>
param([string]$Kod = '', [string]$Rol = 'Karsilama', [string]$Klasor = '')
$ErrorActionPreference = 'SilentlyContinue'

# ---------------- metin tablosu (uretilir) ----------------
$script:LTKeys = @('baslat', 'izin', 'arayuz', 'veri', 'cekirdek', 'ayarlar', 'calisma', 'sistem', 'pencere', 'hazir', 'izin_yok', 'hata', 'betik_yok', 'slogan')
$script:LTData = @{
    'tr' = @(
        'Multimizer ba\u015flat\u0131l\u0131yor\u2026',
        'Y\u00f6netici izni bekleniyor\u2026',
        'Aray\u00fcz bile\u015fenleri y\u00fckleniyor',
        'Veri klas\u00f6rleri ve g\u00fcnl\u00fck haz\u0131rlan\u0131yor',
        '\u00c7ekirdek i\u015flevler y\u00fckleniyor',
        'Ayarlar okunuyor',
        'Arka plan \u00e7al\u0131\u015fma alan\u0131 haz\u0131rlan\u0131yor',
        'Sistem bilgisi toplan\u0131yor',
        'Pencere olu\u015fturuluyor',
        'Haz\u0131r',
        'Y\u00f6netici izni verilmedi. Multimizer, sistem ayarlar\u0131n\u0131 y\u00f6netebilmek i\u00e7in bu izne ihtiya\u00e7 duyar. Yeniden ba\u015flat\u0131n ve izin penceresinde \u201cEvet\u201di se\u00e7in.',
        'Multimizer ba\u015flat\u0131lamad\u0131 (kod {0}).',
        'Multimizer.ps1 bulunamad\u0131. \u00d6nce ZIP dosyas\u0131n\u0131n tamam\u0131n\u0131 bir klas\u00f6re \u00e7\u0131kar\u0131n.',
        'Windows i\u00e7in optimizasyon, bak\u0131m ve g\u00fcvenlik'
    )
    'en' = @(
        'Starting Multimizer\u2026',
        'Waiting for administrator permission\u2026',
        'Loading interface components',
        'Preparing data folders and log',
        'Loading core functions',
        'Reading settings',
        'Preparing background workspace',
        'Collecting system information',
        'Creating the window',
        'Ready',
        'Administrator permission was not granted. Multimizer needs it to manage system settings. Start it again and choose \u201cYes\u201d in the permission dialog.',
        'Multimizer could not be started (code {0}).',
        'Multimizer.ps1 was not found. Extract the entire ZIP file to a folder first.',
        'Optimization, maintenance and security for Windows'
    )
    'de' = @(
        'Multimizer wird gestartet\u2026',
        'Warte auf Administratorberechtigung\u2026',
        'Oberfl\u00e4chenkomponenten werden geladen',
        'Datenordner und Protokoll werden vorbereitet',
        'Kernfunktionen werden geladen',
        'Einstellungen werden gelesen',
        'Hintergrund-Arbeitsbereich wird vorbereitet',
        'Systeminformationen werden erfasst',
        'Fenster wird erstellt',
        'Bereit',
        'Die Administratorberechtigung wurde nicht erteilt. Multimizer ben\u00f6tigt sie, um Systemeinstellungen zu verwalten. Starten Sie das Programm erneut und w\u00e4hlen Sie im Berechtigungsdialog \u201eJa\u201c.',
        'Multimizer konnte nicht gestartet werden (Code {0}).',
        'Multimizer.ps1 wurde nicht gefunden. Entpacken Sie zuerst die gesamte ZIP-Datei in einen Ordner.',
        'Optimierung, Wartung und Sicherheit f\u00fcr Windows'
    )
    'fr' = @(
        'D\u00e9marrage de Multimizer\u2026',
        'En attente de l\u2019autorisation administrateur\u2026',
        'Chargement des composants de l\u2019interface',
        'Pr\u00e9paration des dossiers de donn\u00e9es et du journal',
        'Chargement des fonctions principales',
        'Lecture des param\u00e8tres',
        'Pr\u00e9paration de l\u2019espace de travail en arri\u00e8re-plan',
        'Collecte des informations syst\u00e8me',
        'Cr\u00e9ation de la fen\u00eatre',
        'Pr\u00eat',
        'L\u2019autorisation administrateur n\u2019a pas \u00e9t\u00e9 accord\u00e9e. Multimizer en a besoin pour g\u00e9rer les param\u00e8tres syst\u00e8me. Relancez le programme et choisissez \u00ab Oui \u00bb dans la bo\u00eete de dialogue d\u2019autorisation.',
        'Multimizer n\u2019a pas pu d\u00e9marrer (code {0}).',
        'Multimizer.ps1 est introuvable. Extrayez d\u2019abord l\u2019int\u00e9gralit\u00e9 du fichier ZIP dans un dossier.',
        'Optimisation, maintenance et s\u00e9curit\u00e9 pour Windows'
    )
    'es' = @(
        'Iniciando Multimizer\u2026',
        'Esperando el permiso de administrador\u2026',
        'Cargando los componentes de la interfaz',
        'Preparando las carpetas de datos y el registro',
        'Cargando las funciones principales',
        'Leyendo la configuraci\u00f3n',
        'Preparando el espacio de trabajo en segundo plano',
        'Recopilando informaci\u00f3n del sistema',
        'Creando la ventana',
        'Listo',
        'No se concedi\u00f3 el permiso de administrador. Multimizer lo necesita para administrar la configuraci\u00f3n del sistema. Vuelva a iniciarlo y elija \u00abS\u00ed\u00bb en el cuadro de permiso.',
        'No se pudo iniciar Multimizer (c\u00f3digo {0}).',
        'No se encontr\u00f3 Multimizer.ps1. Primero extraiga todo el archivo ZIP en una carpeta.',
        'Optimizaci\u00f3n, mantenimiento y seguridad para Windows'
    )
    'it' = @(
        'Avvio di Multimizer\u2026',
        'In attesa dell\u2019autorizzazione di amministratore\u2026',
        'Caricamento dei componenti dell\u2019interfaccia',
        'Preparazione delle cartelle dati e del registro',
        'Caricamento delle funzioni principali',
        'Lettura delle impostazioni',
        'Preparazione dell\u2019area di lavoro in background',
        'Raccolta delle informazioni di sistema',
        'Creazione della finestra',
        'Pronto',
        'L\u2019autorizzazione di amministratore non \u00e8 stata concessa. Multimizer ne ha bisogno per gestire le impostazioni di sistema. Riavvialo e scegli \u00abS\u00ec\u00bb nella finestra di autorizzazione.',
        'Impossibile avviare Multimizer (codice {0}).',
        'Multimizer.ps1 non trovato. Estrai prima l\u2019intero file ZIP in una cartella.',
        'Ottimizzazione, manutenzione e sicurezza per Windows'
    )
    'pt' = @(
        'Iniciando o Multimizer\u2026',
        'Aguardando a permiss\u00e3o de administrador\u2026',
        'Carregando os componentes da interface',
        'Preparando as pastas de dados e o registro',
        'Carregando as fun\u00e7\u00f5es principais',
        'Lendo as configura\u00e7\u00f5es',
        'Preparando a \u00e1rea de trabalho em segundo plano',
        'Coletando informa\u00e7\u00f5es do sistema',
        'Criando a janela',
        'Pronto',
        'A permiss\u00e3o de administrador n\u00e3o foi concedida. O Multimizer precisa dela para gerenciar as configura\u00e7\u00f5es do sistema. Inicie novamente e escolha \u201cSim\u201d na caixa de di\u00e1logo de permiss\u00e3o.',
        'N\u00e3o foi poss\u00edvel iniciar o Multimizer (c\u00f3digo {0}).',
        'Multimizer.ps1 n\u00e3o foi encontrado. Primeiro extraia todo o arquivo ZIP para uma pasta.',
        'Otimiza\u00e7\u00e3o, manuten\u00e7\u00e3o e seguran\u00e7a para o Windows'
    )
    'ru' = @(
        '\u0417\u0430\u043f\u0443\u0441\u043a Multimizer\u2026',
        '\u041e\u0436\u0438\u0434\u0430\u043d\u0438\u0435 \u0440\u0430\u0437\u0440\u0435\u0448\u0435\u043d\u0438\u044f \u0430\u0434\u043c\u0438\u043d\u0438\u0441\u0442\u0440\u0430\u0442\u043e\u0440\u0430\u2026',
        '\u0417\u0430\u0433\u0440\u0443\u0437\u043a\u0430 \u043a\u043e\u043c\u043f\u043e\u043d\u0435\u043d\u0442\u043e\u0432 \u0438\u043d\u0442\u0435\u0440\u0444\u0435\u0439\u0441\u0430',
        '\u041f\u043e\u0434\u0433\u043e\u0442\u043e\u0432\u043a\u0430 \u043f\u0430\u043f\u043e\u043a \u0434\u0430\u043d\u043d\u044b\u0445 \u0438 \u0436\u0443\u0440\u043d\u0430\u043b\u0430',
        '\u0417\u0430\u0433\u0440\u0443\u0437\u043a\u0430 \u043e\u0441\u043d\u043e\u0432\u043d\u044b\u0445 \u0444\u0443\u043d\u043a\u0446\u0438\u0439',
        '\u0427\u0442\u0435\u043d\u0438\u0435 \u043d\u0430\u0441\u0442\u0440\u043e\u0435\u043a',
        '\u041f\u043e\u0434\u0433\u043e\u0442\u043e\u0432\u043a\u0430 \u0444\u043e\u043d\u043e\u0432\u043e\u0433\u043e \u0440\u0430\u0431\u043e\u0447\u0435\u0433\u043e \u043f\u0440\u043e\u0441\u0442\u0440\u0430\u043d\u0441\u0442\u0432\u0430',
        '\u0421\u0431\u043e\u0440 \u0441\u0432\u0435\u0434\u0435\u043d\u0438\u0439 \u043e \u0441\u0438\u0441\u0442\u0435\u043c\u0435',
        '\u0421\u043e\u0437\u0434\u0430\u043d\u0438\u0435 \u043e\u043a\u043d\u0430',
        '\u0413\u043e\u0442\u043e\u0432\u043e',
        '\u0420\u0430\u0437\u0440\u0435\u0448\u0435\u043d\u0438\u0435 \u0430\u0434\u043c\u0438\u043d\u0438\u0441\u0442\u0440\u0430\u0442\u043e\u0440\u0430 \u043d\u0435 \u043f\u0440\u0435\u0434\u043e\u0441\u0442\u0430\u0432\u043b\u0435\u043d\u043e. Multimizer \u0442\u0440\u0435\u0431\u0443\u0435\u0442\u0441\u044f \u043e\u043d\u043e \u0434\u043b\u044f \u0443\u043f\u0440\u0430\u0432\u043b\u0435\u043d\u0438\u044f \u043f\u0430\u0440\u0430\u043c\u0435\u0442\u0440\u0430\u043c\u0438 \u0441\u0438\u0441\u0442\u0435\u043c\u044b. \u0417\u0430\u043f\u0443\u0441\u0442\u0438\u0442\u0435 \u043f\u0440\u043e\u0433\u0440\u0430\u043c\u043c\u0443 \u0441\u043d\u043e\u0432\u0430 \u0438 \u0432\u044b\u0431\u0435\u0440\u0438\u0442\u0435 \u00ab\u0414\u0430\u00bb \u0432 \u043e\u043a\u043d\u0435 \u0437\u0430\u043f\u0440\u043e\u0441\u0430 \u0440\u0430\u0437\u0440\u0435\u0448\u0435\u043d\u0438\u044f.',
        '\u041d\u0435 \u0443\u0434\u0430\u043b\u043e\u0441\u044c \u0437\u0430\u043f\u0443\u0441\u0442\u0438\u0442\u044c Multimizer (\u043a\u043e\u0434 {0}).',
        '\u0424\u0430\u0439\u043b Multimizer.ps1 \u043d\u0435 \u043d\u0430\u0439\u0434\u0435\u043d. \u0421\u043d\u0430\u0447\u0430\u043b\u0430 \u0440\u0430\u0441\u043f\u0430\u043a\u0443\u0439\u0442\u0435 \u0432\u0435\u0441\u044c ZIP-\u0444\u0430\u0439\u043b \u0432 \u043f\u0430\u043f\u043a\u0443.',
        '\u041e\u043f\u0442\u0438\u043c\u0438\u0437\u0430\u0446\u0438\u044f, \u043e\u0431\u0441\u043b\u0443\u0436\u0438\u0432\u0430\u043d\u0438\u0435 \u0438 \u0431\u0435\u0437\u043e\u043f\u0430\u0441\u043d\u043e\u0441\u0442\u044c Windows'
    )
    'ja' = @(
        'Multimizer \u3092\u8d77\u52d5\u3057\u3066\u3044\u307e\u3059\u2026',
        '\u7ba1\u7406\u8005\u306e\u8a31\u53ef\u3092\u5f85\u3063\u3066\u3044\u307e\u3059\u2026',
        '\u30a4\u30f3\u30bf\u30fc\u30d5\u30a7\u30a4\u30b9\u306e\u30b3\u30f3\u30dd\u30fc\u30cd\u30f3\u30c8\u3092\u8aad\u307f\u8fbc\u3093\u3067\u3044\u307e\u3059',
        '\u30c7\u30fc\u30bf\u30d5\u30a9\u30eb\u30c0\u30fc\u3068\u30ed\u30b0\u3092\u6e96\u5099\u3057\u3066\u3044\u307e\u3059',
        '\u30b3\u30a2\u6a5f\u80fd\u3092\u8aad\u307f\u8fbc\u3093\u3067\u3044\u307e\u3059',
        '\u8a2d\u5b9a\u3092\u8aad\u307f\u53d6\u3063\u3066\u3044\u307e\u3059',
        '\u30d0\u30c3\u30af\u30b0\u30e9\u30a6\u30f3\u30c9\u4f5c\u696d\u9818\u57df\u3092\u6e96\u5099\u3057\u3066\u3044\u307e\u3059',
        '\u30b7\u30b9\u30c6\u30e0\u60c5\u5831\u3092\u53ce\u96c6\u3057\u3066\u3044\u307e\u3059',
        '\u30a6\u30a3\u30f3\u30c9\u30a6\u3092\u4f5c\u6210\u3057\u3066\u3044\u307e\u3059',
        '\u6e96\u5099\u5b8c\u4e86',
        '\u7ba1\u7406\u8005\u306e\u8a31\u53ef\u304c\u4e0e\u3048\u3089\u308c\u307e\u305b\u3093\u3067\u3057\u305f\u3002Multimizer \u306f\u30b7\u30b9\u30c6\u30e0\u8a2d\u5b9a\u3092\u7ba1\u7406\u3059\u308b\u305f\u3081\u306b\u3053\u306e\u8a31\u53ef\u3092\u5fc5\u8981\u3068\u3057\u307e\u3059\u3002\u3082\u3046\u4e00\u5ea6\u8d77\u52d5\u3057\u3001\u8a31\u53ef\u306e\u30c0\u30a4\u30a2\u30ed\u30b0\u3067\u300c\u306f\u3044\u300d\u3092\u9078\u629e\u3057\u3066\u304f\u3060\u3055\u3044\u3002',
        'Multimizer \u3092\u8d77\u52d5\u3067\u304d\u307e\u305b\u3093\u3067\u3057\u305f (\u30b3\u30fc\u30c9 {0})\u3002',
        'Multimizer.ps1 \u304c\u898b\u3064\u304b\u308a\u307e\u305b\u3093\u3002\u5148\u306b ZIP \u30d5\u30a1\u30a4\u30eb\u5168\u4f53\u3092\u30d5\u30a9\u30eb\u30c0\u30fc\u306b\u5c55\u958b\u3057\u3066\u304f\u3060\u3055\u3044\u3002',
        'Windows \u306e\u6700\u9069\u5316\u3001\u30e1\u30f3\u30c6\u30ca\u30f3\u30b9\u3001\u30bb\u30ad\u30e5\u30ea\u30c6\u30a3'
    )
    'ko' = @(
        'Multimizer\ub97c \uc2dc\uc791\ud558\ub294 \uc911\u2026',
        '\uad00\ub9ac\uc790 \uad8c\ud55c\uc744 \uae30\ub2e4\ub9ac\ub294 \uc911\u2026',
        '\uc778\ud130\ud398\uc774\uc2a4 \uad6c\uc131 \uc694\uc18c\ub97c \ubd88\ub7ec\uc624\ub294 \uc911',
        '\ub370\uc774\ud130 \ud3f4\ub354\uc640 \ub85c\uadf8\ub97c \uc900\ube44\ud558\ub294 \uc911',
        '\ud575\uc2ec \uae30\ub2a5\uc744 \ubd88\ub7ec\uc624\ub294 \uc911',
        '\uc124\uc815\uc744 \uc77d\ub294 \uc911',
        '\ubc31\uadf8\ub77c\uc6b4\ub4dc \uc791\uc5c5 \uacf5\uac04\uc744 \uc900\ube44\ud558\ub294 \uc911',
        '\uc2dc\uc2a4\ud15c \uc815\ubcf4\ub97c \uc218\uc9d1\ud558\ub294 \uc911',
        '\ucc3d\uc744 \ub9cc\ub4dc\ub294 \uc911',
        '\uc900\ube44 \uc644\ub8cc',
        '\uad00\ub9ac\uc790 \uad8c\ud55c\uc774 \ubd80\uc5ec\ub418\uc9c0 \uc54a\uc558\uc2b5\ub2c8\ub2e4. Multimizer\ub294 \uc2dc\uc2a4\ud15c \uc124\uc815\uc744 \uad00\ub9ac\ud558\uae30 \uc704\ud574 \uc774 \uad8c\ud55c\uc774 \ud544\uc694\ud569\ub2c8\ub2e4. \ub2e4\uc2dc \uc2e4\ud589\ud55c \ud6c4 \uad8c\ud55c \ub300\ud654 \uc0c1\uc790\uc5d0\uc11c \u201c\uc608\u201d\ub97c \uc120\ud0dd\ud558\uc138\uc694.',
        'Multimizer\ub97c \uc2dc\uc791\ud560 \uc218 \uc5c6\uc2b5\ub2c8\ub2e4(\ucf54\ub4dc {0}).',
        'Multimizer.ps1\uc744 \ucc3e\uc744 \uc218 \uc5c6\uc2b5\ub2c8\ub2e4. \uba3c\uc800 ZIP \ud30c\uc77c \uc804\uccb4\ub97c \ud3f4\ub354\uc5d0 \uc555\ucd95 \ud574\uc81c\ud558\uc138\uc694.',
        'Windows \ucd5c\uc801\ud654, \uc720\uc9c0 \uad00\ub9ac \ubc0f \ubcf4\uc548'
    )
    'zh' = @(
        '\u6b63\u5728\u542f\u52a8 Multimizer\u2026',
        '\u6b63\u5728\u7b49\u5f85\u7ba1\u7406\u5458\u6743\u9650\u2026',
        '\u6b63\u5728\u52a0\u8f7d\u754c\u9762\u7ec4\u4ef6',
        '\u6b63\u5728\u51c6\u5907\u6570\u636e\u6587\u4ef6\u5939\u548c\u65e5\u5fd7',
        '\u6b63\u5728\u52a0\u8f7d\u6838\u5fc3\u529f\u80fd',
        '\u6b63\u5728\u8bfb\u53d6\u8bbe\u7f6e',
        '\u6b63\u5728\u51c6\u5907\u540e\u53f0\u5de5\u4f5c\u533a',
        '\u6b63\u5728\u6536\u96c6\u7cfb\u7edf\u4fe1\u606f',
        '\u6b63\u5728\u521b\u5efa\u7a97\u53e3',
        '\u5c31\u7eea',
        '\u672a\u6388\u4e88\u7ba1\u7406\u5458\u6743\u9650\u3002Multimizer \u9700\u8981\u8be5\u6743\u9650\u6765\u7ba1\u7406\u7cfb\u7edf\u8bbe\u7f6e\u3002\u8bf7\u91cd\u65b0\u542f\u52a8\uff0c\u5e76\u5728\u6743\u9650\u5bf9\u8bdd\u6846\u4e2d\u9009\u62e9\u201c\u662f\u201d\u3002',
        '\u65e0\u6cd5\u542f\u52a8 Multimizer\uff08\u4ee3\u7801 {0}\uff09\u3002',
        '\u672a\u627e\u5230 Multimizer.ps1\u3002\u8bf7\u5148\u5c06\u6574\u4e2a ZIP \u6587\u4ef6\u89e3\u538b\u5230\u4e00\u4e2a\u6587\u4ef6\u5939\u3002',
        'Windows \u4f18\u5316\u3001\u7ef4\u62a4\u4e0e\u5b89\u5168'
    )
    'zh-hant' = @(
        '\u6b63\u5728\u555f\u52d5 Multimizer\u2026',
        '\u6b63\u5728\u7b49\u5f85\u7cfb\u7d71\u7ba1\u7406\u54e1\u6b0a\u9650\u2026',
        '\u6b63\u5728\u8f09\u5165\u4ecb\u9762\u5143\u4ef6',
        '\u6b63\u5728\u6e96\u5099\u8cc7\u6599\u593e\u8207\u8a18\u9304\u6a94',
        '\u6b63\u5728\u8f09\u5165\u6838\u5fc3\u529f\u80fd',
        '\u6b63\u5728\u8b80\u53d6\u8a2d\u5b9a',
        '\u6b63\u5728\u6e96\u5099\u80cc\u666f\u5de5\u4f5c\u5340',
        '\u6b63\u5728\u6536\u96c6\u7cfb\u7d71\u8cc7\u8a0a',
        '\u6b63\u5728\u5efa\u7acb\u8996\u7a97',
        '\u5c31\u7dd2',
        '\u672a\u6388\u4e88\u7cfb\u7d71\u7ba1\u7406\u54e1\u6b0a\u9650\u3002Multimizer \u9700\u8981\u6b64\u6b0a\u9650\u624d\u80fd\u7ba1\u7406\u7cfb\u7d71\u8a2d\u5b9a\u3002\u8acb\u91cd\u65b0\u555f\u52d5\uff0c\u4e26\u5728\u6b0a\u9650\u5c0d\u8a71\u65b9\u584a\u4e2d\u9078\u64c7\u300c\u662f\u300d\u3002',
        '\u7121\u6cd5\u555f\u52d5 Multimizer\uff08\u4ee3\u78bc {0}\uff09\u3002',
        '\u627e\u4e0d\u5230 Multimizer.ps1\u3002\u8acb\u5148\u5c07\u6574\u500b ZIP \u6a94\u6848\u89e3\u58d3\u7e2e\u5230\u8cc7\u6599\u593e\u3002',
        'Windows \u6700\u4f73\u5316\u3001\u7dad\u8b77\u8207\u5b89\u5168'
    )
    'ar' = @(
        '\u062c\u0627\u0631\u064d \u062a\u0634\u063a\u064a\u0644 Multimizer\u2026',
        '\u0641\u064a \u0627\u0646\u062a\u0638\u0627\u0631 \u0625\u0630\u0646 \u0627\u0644\u0645\u0633\u0624\u0648\u0644\u2026',
        '\u062c\u0627\u0631\u064d \u062a\u062d\u0645\u064a\u0644 \u0645\u0643\u0648\u0651\u0646\u0627\u062a \u0627\u0644\u0648\u0627\u062c\u0647\u0629',
        '\u062c\u0627\u0631\u064d \u062a\u062c\u0647\u064a\u0632 \u0645\u062c\u0644\u062f\u0627\u062a \u0627\u0644\u0628\u064a\u0627\u0646\u0627\u062a \u0648\u0627\u0644\u0633\u062c\u0644',
        '\u062c\u0627\u0631\u064d \u062a\u062d\u0645\u064a\u0644 \u0627\u0644\u0648\u0638\u0627\u0626\u0641 \u0627\u0644\u0623\u0633\u0627\u0633\u064a\u0629',
        '\u062c\u0627\u0631\u064d \u0642\u0631\u0627\u0621\u0629 \u0627\u0644\u0625\u0639\u062f\u0627\u062f\u0627\u062a',
        '\u062c\u0627\u0631\u064d \u062a\u062c\u0647\u064a\u0632 \u0645\u0633\u0627\u062d\u0629 \u0627\u0644\u0639\u0645\u0644 \u0641\u064a \u0627\u0644\u062e\u0644\u0641\u064a\u0629',
        '\u062c\u0627\u0631\u064d \u062c\u0645\u0639 \u0645\u0639\u0644\u0648\u0645\u0627\u062a \u0627\u0644\u0646\u0638\u0627\u0645',
        '\u062c\u0627\u0631\u064d \u0625\u0646\u0634\u0627\u0621 \u0627\u0644\u0646\u0627\u0641\u0630\u0629',
        '\u062c\u0627\u0647\u0632',
        '\u0644\u0645 \u064a\u062a\u0645 \u0645\u0646\u062d \u0625\u0630\u0646 \u0627\u0644\u0645\u0633\u0624\u0648\u0644. \u064a\u062d\u062a\u0627\u062c Multimizer \u0625\u0644\u0649 \u0647\u0630\u0627 \u0627\u0644\u0625\u0630\u0646 \u0644\u0625\u062f\u0627\u0631\u0629 \u0625\u0639\u062f\u0627\u062f\u0627\u062a \u0627\u0644\u0646\u0638\u0627\u0645. \u0623\u0639\u062f \u0627\u0644\u062a\u0634\u063a\u064a\u0644 \u0648\u0627\u062e\u062a\u0631 \u00ab\u0646\u0639\u0645\u00bb \u0641\u064a \u0645\u0631\u0628\u0639 \u062d\u0648\u0627\u0631 \u0627\u0644\u0625\u0630\u0646.',
        '\u062a\u0639\u0630\u0651\u0631 \u062a\u0634\u063a\u064a\u0644 Multimizer (\u0627\u0644\u0631\u0645\u0632 {0}).',
        '\u0644\u0645 \u064a\u062a\u0645 \u0627\u0644\u0639\u062b\u0648\u0631 \u0639\u0644\u0649 Multimizer.ps1. \u0627\u0633\u062a\u062e\u0631\u062c \u0645\u0644\u0641 ZIP \u0628\u0627\u0644\u0643\u0627\u0645\u0644 \u0625\u0644\u0649 \u0645\u062c\u0644\u062f \u0623\u0648\u0644\u0627\u064b.',
        '\u062a\u062d\u0633\u064a\u0646 Windows \u0648\u0635\u064a\u0627\u0646\u062a\u0647 \u0648\u062d\u0645\u0627\u064a\u062a\u0647'
    )
}

# ---------------- ortak degerler ----------------
$script:Dir = $Klasor
if ($script:Dir -eq '') { try { $script:Dir = Split-Path -Parent $PSCommandPath } catch { } }
if ($script:Dir -eq '' -or $null -eq $script:Dir) { $script:Dir = (Get-Location).Path }
$script:AppPs1 = Join-Path $script:Dir 'Multimizer.ps1'
$script:TaniPs1 = Join-Path $script:Dir 'Tani.ps1'
$script:DataDir = Join-Path $env:ProgramData 'Multimizer'
$script:PsExe = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$script:Forward = @($args | ForEach-Object { [string]$_ })
if ($Kod -notmatch '^[A-Za-z0-9]{3,30}$') { $Kod = [string](Get-Random -Minimum 100000 -Maximum 999999999) }
$script:LaunchLang = 'en'

# ---------------- yardimci islevler ----------------
function Resolve-LaunchLang([string]$Code) {
    $c = ([string]$Code).Trim().ToLowerInvariant().Replace('_', '-')
    if ($c -eq '') { return 'en' }
    if ($c -match '^zh-(hant|tw|hk|mo)') { return 'zh-hant' }
    if ($c.StartsWith('zh')) { return 'zh' }
    $p = $c.Split('-')[0]
    if ($script:LTData.ContainsKey($p)) { return $p }
    return 'en'
}

# Dil sirasi uygulamadakiyle ayni: -Dil > MM_DIL > ayarlar.json (Language) > Windows ekran dili
function Get-LaunchLang([string[]]$Rest) {
    $code = ''
    for ($i = 0; $i -lt $Rest.Count - 1; $i++) {
        if ([string]$Rest[$i] -ieq '-Dil') { $code = [string]$Rest[$i + 1]; break }
    }
    if ($code -eq '') { $code = [string]$env:MM_DIL }
    if ($code -eq '' -or $code -ieq 'auto') {
        $code = ''
        try {
            $f = Join-Path $script:DataDir 'ayarlar.json'
            if (Test-Path -LiteralPath $f) {
                $j = Get-Content -LiteralPath $f -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($null -ne $j -and $null -ne $j.Language) { $code = [string]$j.Language }
            }
        } catch { }
    }
    if ($code -eq '' -or $code -ieq 'auto') {
        try { $code = [System.Globalization.CultureInfo]::CurrentUICulture.Name } catch { $code = 'en' }
    }
    return (Resolve-LaunchLang $code)
}

function Get-LT([string]$Key) {
    $i = [array]::IndexOf($script:LTKeys, $Key)
    if ($i -lt 0) { return $Key }
    $arr = $script:LTData[$script:LaunchLang]
    $s = ''
    if ($null -ne $arr -and $i -lt $arr.Count) { $s = [string]$arr[$i] }
    if ($s -eq '') { $s = [string]$script:LTData['en'][$i] }
    return [regex]::Unescape($s)
}

# Windows komut satiri kurallarina gore tirnaklar (bosluk, tirnak ya da bos oge)
function ConvertTo-ArgLine([string[]]$Items) {
    $out = New-Object System.Collections.ArrayList
    foreach ($x in $Items) {
        $s = [string]$x
        if ($s -eq '' -or $s -match '[\s"]') {
            $s = $s -replace '(\\*)"', '$1$1\"'
            $s = $s -replace '(\\+)$', '$1$1'
            $s = '"' + $s + '"'
        }
        [void]$out.Add($s)
    }
    return ($out.ToArray() -join ' ')
}

function Read-LaunchStatus([string]$Path) {
    try {
        if (-not (Test-Path -LiteralPath $Path)) { return $null }
        $t = ([System.IO.File]::ReadAllText($Path)).Trim()
        $p = $t.Split('|')
        if ($p.Count -lt 3) { return $null }
        $a = 0; $n = 0
        if (-not [int]::TryParse($p[0], [ref]$a)) { return $null }
        if (-not [int]::TryParse($p[1], [ref]$n)) { return $null }
        return @{ Pct = $a; Next = $n; Key = [string]$p[2] }
    } catch { return $null }
}

# Cubuk, asamanin yuzdesinden sonraki asamaya dogru yavasca ilerler (asla sonraki asamayi gecmez)
function Get-ProgressTarget([int]$Pct, [int]$Next, [double]$AgeSec) {
    if ($Next -le $Pct) { return [double]$Pct }
    return ([double]$Pct + ([double]($Next - $Pct)) * 0.92 * (1.0 - [math]::Exp(-$AgeSec / 5.0)))
}

# 'bitti': normal kapanis; 'yeniden': pencere acildiktan sonra Windows cokme kodu -> guvenli kipte bir kez daha; 'tani': raporu goster
function Get-StartDecision([int]$Rc, [bool]$Opened, [int]$Attempt) {
    if ($Rc -eq 0) { return 'bitti' }
    if ($Rc -eq -1073741510) { return 'bitti' }
    if ($Opened -and $Rc -lt 0 -and $Attempt -eq 0) { return 'yeniden' }
    return 'tani'
}

function Get-AppVersionText {
    try {
        $fs = New-Object System.IO.FileStream($script:AppPs1, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            $buf = New-Object byte[] 4096
            $n = $fs.Read($buf, 0, 4096)
            $txt = [System.Text.Encoding]::ASCII.GetString($buf, 0, $n)
        } finally { $fs.Dispose() }
        $m = [regex]::Match($txt, 'Surum\s*:\s*([0-9][0-9A-Za-z.\-]*)')
        if ($m.Success) { return $m.Groups[1].Value }
    } catch { }
    return ''
}

function Test-IsAdmin {
    try { return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) } catch { return $false }
}

function Test-ProcessAlive([int]$ProcId) {
    if ($ProcId -le 0) { return $false }
    try { [void][System.Diagnostics.Process]::GetProcessById($ProcId); return $true } catch [System.ArgumentException] { return $false } catch { return $true }
}

function Add-LaunchTrace([string]$Text) {
    try {
        $d = Join-Path $script:DataDir 'Kayitlar'
        [void][System.IO.Directory]::CreateDirectory($d)
        $f = Join-Path $d 'acilis-iz.txt'
        if ((Test-Path -LiteralPath $f) -and ((Get-Item -LiteralPath $f).Length -gt 65536)) { Remove-Item -LiteralPath $f -Force }
        $line = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') + ' [' + $Rol + ' ' + $PID + '] ' + $Text
        [System.IO.File]::AppendAllText($f, $line + "`r`n", (New-Object System.Text.UTF8Encoding($true)))
    } catch { }
}

function Show-LaunchMessage([string]$Text) {
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $opt = [System.Windows.Forms.MessageBoxOptions]0
        if ($script:LaunchLang -eq 'ar') { $opt = [System.Windows.Forms.MessageBoxOptions]0x180000 }
        [void][System.Windows.Forms.MessageBox]::Show($Text, 'Multimizer', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning, [System.Windows.Forms.MessageBoxDefaultButton]::Button1, $opt)
    } catch { Add-LaunchTrace ('ileti gosterilemedi: ' + $Text) }
}

function Remove-QuietFile([string]$Path) {
    try { if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue } } catch { }
}

# ====================================================================
#  ROL: DENETCI (yonetici)
# ====================================================================
function Test-GuiRunning {
    try {
        $m = [System.Threading.Mutex]::OpenExisting('Global\Multimizer-Arayuz')
        $m.Dispose()
        return $true
    } catch { return $false }
}

function Send-ShowSignal {
    try {
        $ev = [System.Threading.EventWaitHandle]::OpenExisting('Global\Multimizer-Goster')
        [void]$ev.Set()
        $ev.Dispose()
    } catch { }
}

function Write-LaunchResult([string]$Path, [int]$Rc, [string]$Why) {
    try { [System.IO.File]::WriteAllText($Path, ([string]$Rc + '|' + $Why), (New-Object System.Text.UTF8Encoding($false))) } catch { }
}

function Invoke-Denetci {
    $son = Join-Path $script:DataDir ('acilis-' + $Kod + '.son')
    [void][System.IO.Directory]::CreateDirectory($script:DataDir)
    Remove-QuietFile $son
    $rc = 0
    $why = 'bitti'
    Add-LaunchTrace ('denetci basladi; yonetici=' + (Test-IsAdmin) + '; kod=' + $Kod)
    try {
        if (-not (Test-Path -LiteralPath $script:AppPs1)) {
            $rc = 1; $why = 'betik-yok'
            Write-LaunchResult $son $rc $why
            Show-LaunchMessage (Get-LT 'betik_yok')
            return $rc
        }
        if (Test-GuiRunning) {
            Send-ShowSignal
            $why = 'zaten-acik'
            Add-LaunchTrace 'uygulama zaten acik; mevcut pencere one getirildi'
            return 0
        }
        $attempt = 0
        while ($true) {
            $code = $Kod
            if ($attempt -gt 0) { $code = $Kod + 'g' }
            $mark = Join-Path $script:DataDir ('oturum-acik-' + $code + '.txt')
            Remove-QuietFile $mark
            $items = New-Object System.Collections.ArrayList
            foreach ($a in @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-WindowStyle', 'Hidden', '-File', $script:AppPs1, '-Gizli', '-Oturum', $code)) { [void]$items.Add($a) }
            foreach ($a in $script:Forward) { [void]$items.Add([string]$a) }
            if ($attempt -gt 0) { [void]$items.Add('-Guvenli') }
            $p = Start-Process -FilePath $script:PsExe -ArgumentList (ConvertTo-ArgLine ([string[]]$items.ToArray())) -WindowStyle Hidden -PassThru -ErrorAction Stop
            $null = $p.Handle
            Add-LaunchTrace ('uygulama baslatildi: surec=' + $p.Id + ' deneme=' + $attempt)
            $p.WaitForExit()
            $rc = -1
            if ($null -ne $p.ExitCode) { $rc = [int]$p.ExitCode }
            $opened = Test-Path -LiteralPath $mark
            $dec = Get-StartDecision $rc $opened $attempt
            Add-LaunchTrace ('uygulama bitti: cikis=' + $rc + ' pencere-acilmisti=' + $opened + ' karar=' + $dec)
            Remove-QuietFile $mark
            Remove-QuietFile (Join-Path $script:DataDir ('acilis-' + $code + '.txt'))
            if ($dec -eq 'bitti') { $why = 'bitti'; break }
            if ($dec -eq 'yeniden') { $attempt++; continue }
            $why = 'tani'
            Write-LaunchResult $son $rc $why
            if (Test-Path -LiteralPath $script:TaniPs1) {
                try { & $script:TaniPs1 -ExitCode $rc -Mod Gui -Gizli | Out-Null } catch { Add-LaunchTrace ('tani acilamadi: ' + $_.Exception.Message); Show-LaunchMessage ((Get-LT 'hata').Replace('{0}', [string]$rc)) }
            } else {
                Show-LaunchMessage ((Get-LT 'hata').Replace('{0}', [string]$rc))
            }
            break
        }
    } catch {
        $rc = 1; $why = 'denetci-hatasi'
        Add-LaunchTrace ('denetci hatasi: ' + $_.Exception.Message)
        Show-LaunchMessage ((Get-LT 'hata').Replace('{0}', [string]$_.Exception.Message))
    } finally {
        Write-LaunchResult $son $rc $why
        Remove-QuietFile (Join-Path $script:DataDir ('acilis-' + $Kod + '.txt'))
        Add-LaunchTrace ('denetci bitti: ' + $why + ' (' + $rc + ')')
    }
    return $rc
}

# ====================================================================
#  ROL: KARSILAMA (acilis ekrani)
# ====================================================================
$script:Phase = 'baslat'
$script:Text = ''
$script:Shown = 0.0
$script:Target = 0.0
$script:Stat = $null
$script:StatAt = 0
$script:DenPid = 0
$script:Async = $null
$script:DenStarted = $false
$script:Ps = $null
$script:Rs = $null
$script:Clock = $null
$script:KExit = 0
$script:Finished = $false
$script:VerText = ''
$script:Rtl = $false
$script:Slogan = ''
$script:Pal = $null
$script:Lay = $null
$script:Static = $null
$script:StaticFailed = $false
$script:Closing = $false
$script:NoFade = $false
$script:LastText = ''
$script:TextAt = 0
$script:PhaseKeys = @('arayuz', 'veri', 'cekirdek', 'ayarlar', 'calisma', 'sistem', 'pencere', 'hazir')

function Write-Handshake {
    try { [System.IO.File]::WriteAllText((Join-Path $env:TEMP ('mm-basladi-' + $Kod + '.txt')), [string]$PID) } catch { }
}

# Denetci'yi ayri bir calisma alaninda baslatir: yonetici izni penceresi acikken acilis ekrani donmaz
function Start-DenetciAsync {
    if ($script:DenStarted) { return }
    $script:DenStarted = $true
    $exe = $script:PsExe
    $items = New-Object System.Collections.ArrayList
    foreach ($a in @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-WindowStyle', 'Hidden', '-File', $PSCommandPath, '-Rol', 'Denetci', '-Kod', $Kod, '-Klasor', $script:Dir)) { [void]$items.Add($a) }
    foreach ($a in $script:Forward) { [void]$items.Add([string]$a) }
    $argLine = ConvertTo-ArgLine ([string[]]$items.ToArray())
    $elevate = -not (Test-IsAdmin)
    $script:Rs = [runspacefactory]::CreateRunspace()
    $script:Rs.Open()
    $script:Ps = [powershell]::Create()
    $script:Ps.Runspace = $script:Rs
    [void]$script:Ps.AddScript({
        param($exe, $argLine, $elevate)
        try {
            $sp = @{ FilePath = $exe; ArgumentList = $argLine; WindowStyle = 'Hidden'; PassThru = $true; ErrorAction = 'Stop' }
            if ($elevate) { $sp['Verb'] = 'RunAs' }
            $p = Start-Process @sp
            return ('OK:' + [string]$p.Id)
        } catch {
            $ne = 0
            $ex = $_.Exception
            while ($null -ne $ex) {
                if ($ex -is [System.ComponentModel.Win32Exception]) { $ne = [int]$ex.NativeErrorCode; break }
                $ex = $ex.InnerException
            }
            return ('ERR:' + [string]$ne + ':' + [string]$_.Exception.Message)
        }
    }).AddArgument($exe).AddArgument($argLine).AddArgument($elevate)
    if ($elevate) { $script:Phase = 'izin'; $script:Text = (Get-LT 'izin') }
    $script:Async = $script:Ps.BeginInvoke()
}

# Bir tur: dosyalari okur ve durumu gunceller. Donus: '' (devam) | 'acildi' | 'bitti' | 'izin' | 'olu' | 'sure'
function Step-Launch {
    if ($null -ne $script:Async -and $script:Async.IsCompleted -and $script:Phase -ne 'calisiyor' -and $script:DenPid -eq 0) {
        $r = ''
        try { $r = [string]@($script:Ps.EndInvoke($script:Async))[0] } catch { $r = 'ERR:0:' + $_.Exception.Message }
        if ($r -like 'OK:*') {
            $script:DenPid = [int]$r.Substring(3)
            $script:Phase = 'calisiyor'
            $script:Text = (Get-LT 'baslat')
            Add-LaunchTrace ('denetci surec=' + $script:DenPid)
        } else {
            Add-LaunchTrace ('denetci baslatilamadi: ' + $r)
            if ($r -like 'ERR:1223:*') { return 'izin' }
            $script:ErrText = $r
            return 'olu'
        }
    }
    if ($script:Phase -ne 'calisiyor') { return '' }
    $ms = [int]$script:Clock.ElapsedMilliseconds
    $st = Read-LaunchStatus (Join-Path $script:DataDir ('acilis-' + $Kod + '.txt'))
    if ($null -ne $st) {
        if ($null -eq $script:Stat -or [string]$script:Stat.Key -ne [string]$st.Key) { $script:StatAt = $ms }
        $script:Stat = $st
        if ([array]::IndexOf($script:PhaseKeys, [string]$st.Key) -ge 0) { $script:Text = (Get-LT ([string]$st.Key)) }
    }
    if (Test-Path -LiteralPath (Join-Path $script:DataDir ('oturum-acik-' + $Kod + '.txt'))) { return 'acildi' }
    if (Test-Path -LiteralPath (Join-Path $script:DataDir ('acilis-' + $Kod + '.son'))) { return 'bitti' }
    if ($ms -gt 4000 -and -not (Test-ProcessAlive $script:DenPid)) {
        Start-Sleep -Milliseconds 400
        if (Test-Path -LiteralPath (Join-Path $script:DataDir ('acilis-' + $Kod + '.son'))) { return 'bitti' }
        if (Test-Path -LiteralPath (Join-Path $script:DataDir ('oturum-acik-' + $Kod + '.txt'))) { return 'acildi' }
        $script:ErrText = ''
        return 'olu'
    }
    if ($ms -gt 300000) { return 'sure' }
    return ''
}

function Complete-Launch([string]$Why) {
    if ($script:Finished) { return }
    $script:Finished = $true
    Add-LaunchTrace ('karsilama bitti: ' + $Why)
    if ($Why -eq 'izin') { $script:KExit = 3 }
    if ($Why -eq 'olu') { $script:KExit = 1 }
}

function Show-LaunchFailure([string]$Why) {
    if ($Why -eq 'izin') { Show-LaunchMessage (Get-LT 'izin_yok'); return }
    if ($Why -eq 'olu') {
        $d = [string]$script:ErrText
        if ($d -eq '') { $d = 'denetci' }
        Show-LaunchMessage ((Get-LT 'hata').Replace('{0}', $d))
    }
}

# Pencere cizimi olmadan bekleme (-Tepsi ya da WinForms yuklenemezse)
function Invoke-QuietWait {
    if ($null -eq $script:Clock) { $script:Clock = [System.Diagnostics.Stopwatch]::StartNew() }
    Start-DenetciAsync
    while ($true) {
        $r = Step-Launch
        if ($r -ne '') { Complete-Launch $r; Show-LaunchFailure $r; break }
        Start-Sleep -Milliseconds 250
    }
}

# ---------------- gorunum: acik/koyu, renkler, yerlesim ----------------
# Acilis ekrani kayitli temaya gore acik ya da koyu cizilir: Acik, Kum ve Cam acik, digerleri koyu.
# Kayit yoksa ya da eski surumden kalmissa (LookVersion yok) uygulama beyaz temayla acilacagindan ekran da acik cizilir.
function Get-LaunchLight {
    $theme = ''
    $ver = $false
    try {
        $f = Join-Path $script:DataDir 'ayarlar.json'
        if (Test-Path -LiteralPath $f) {
            $j = Get-Content -LiteralPath $f -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($null -ne $j) {
                if ($null -ne $j.Theme) { $theme = [string]$j.Theme }
                if ($null -ne $j.LookVersion) { $ver = $true }
            }
        }
    } catch { }
    if ($theme -eq '' -or -not $ver) { return $true }
    return (@('Acik', 'Kum', 'Cam') -contains $theme)
}

# Renkler (R, G, B). Pencere cizimi disinda sinanabilir.
function Get-SplashPalette([bool]$Light) {
    if ($Light) {
        return @{
            Light = $true
            BgTop = @(251, 252, 254); BgBottom = @(238, 241, 248); Edge = @(214, 220, 232)
            AccentA = @(27, 42, 92); AccentB = @(139, 63, 200); Glow = @(27, 42, 92)
            Text = @(52, 64, 84); Tagline = @(91, 106, 156); Dim = @(90, 102, 132); Track = @(216, 222, 236)
        }
    }
    return @{
        Light = $false
        BgTop = @(9, 14, 28); BgBottom = @(20, 30, 58); Edge = @(38, 58, 90)
        AccentA = @(34, 211, 238); AccentB = @(167, 139, 250); Glow = @(34, 211, 238)
        Text = @(203, 213, 225); Tagline = @(148, 163, 184); Dim = @(122, 136, 160); Track = @(30, 41, 59)
    }
}

# Yerlesim: 96 dpi'da 600 x 340 piksel; her oge yatayda ortalanir. $Scale ekran olcegidir (1.0 = %100).
function Get-SplashLayout([double]$Scale) {
    if ($Scale -lt 1.0) { $Scale = 1.0 }
    if ($Scale -gt 4.0) { $Scale = 4.0 }
    $k = { param([double]$v) [int][math]::Round($v * $Scale) }
    $L = @{}
    $L.Scale = $Scale
    $L.W = & $k 600
    $L.H = & $k 340
    $L.TopBarH = & $k 3
    $L.MarkSize = & $k 60
    $L.MarkX = [int][math]::Floor(($L.W - $L.MarkSize) / 2.0)
    $L.MarkY = & $k 38
    $L.WordY = & $k 114
    $L.WordH = & $k 40
    $L.TagY = & $k 158
    $L.TagH = & $k 24
    $L.TextX = & $k 40
    $L.TextW = $L.W - 2 * $L.TextX
    $L.StatusY = & $k 214
    $L.StatusH = & $k 26
    $L.BarW = & $k 380
    $L.BarX = [int][math]::Floor(($L.W - $L.BarW) / 2.0)
    $L.BarH = [math]::Max(3, (& $k 4))
    $L.BarY = & $k 254
    $L.PctY = & $k 266
    $L.PctH = & $k 18
    $L.FootY = & $k 304
    $L.FootH = & $k 18
    return $L
}

function Get-SplashColor([int[]]$Rgb, [int]$Alpha = 255) {
    return [System.Drawing.Color]::FromArgb($Alpha, [int]$Rgb[0], [int]$Rgb[1], [int]$Rgb[2])
}

# Yuvarlak koseli dikdortgen yolu
function New-RoundPath([double]$X, [double]$Y, [double]$W, [double]$H, [double]$R) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = [single]($R * 2.0)
    $p.AddArc([single]$X, [single]$Y, $d, $d, [single]180, [single]90)
    $p.AddArc([single]($X + $W - $d), [single]$Y, $d, $d, [single]270, [single]90)
    $p.AddArc([single]($X + $W - $d), [single]($Y + $H - $d), $d, $d, [single]0, [single]90)
    $p.AddArc([single]$X, [single]($Y + $H - $d), $d, $d, [single]90, [single]90)
    $p.CloseFigure()
    return $p
}

# Yatay ve dikeyde ortalayan metin bicimi
function New-CenterFormat([bool]$Rtl) {
    $sf = New-Object System.Drawing.StringFormat
    $sf.Alignment = [System.Drawing.StringAlignment]::Center
    $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
    $sf.Trimming = [System.Drawing.StringTrimming]::EllipsisCharacter
    $sf.FormatFlags = [System.Drawing.StringFormatFlags]::NoWrap
    if ($Rtl) { $sf.FormatFlags = ($sf.FormatFlags -bor [System.Drawing.StringFormatFlags]::DirectionRightToLeft) }
    return $sf
}

function Set-SplashOpacity([double]$V) {
    if ($script:NoFade) { return }
    try { $script:Form.Opacity = [math]::Max(0.0, [math]::Min(1.0, $V)) } catch {
        $script:NoFade = $true
        try { $script:Form.Opacity = 1.0 } catch { }
    }
}

# Degismeyen katman (zemin, logo, ad, slogan, alt bilgi) bir kez cizilip saklanir; her karede yalnizca durum metni ve cubuk yeniden cizilir.
function New-SplashStatic {
    $L = $script:Lay
    $P = $script:Pal
    $S = [double]$L.Scale
    $bmp = New-Object System.Drawing.Bitmap([int]$L.W, [int]$L.H, [System.Drawing.Imaging.PixelFormat]::Format32bppPArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
        $colA = Get-SplashColor $P.AccentA
        $colB = Get-SplashColor $P.AccentB

        # zemin, ust vurgu seridi, ince kenar
        $full = New-Object System.Drawing.Rectangle(0, 0, [int]$L.W, [int]$L.H)
        $bg = New-Object System.Drawing.Drawing2D.LinearGradientBrush($full, (Get-SplashColor $P.BgTop), (Get-SplashColor $P.BgBottom), [single]90.0)
        $g.FillRectangle($bg, $full)
        $bg.Dispose()
        $topR = New-Object System.Drawing.Rectangle(0, 0, [int]$L.W, [int]$L.TopBarH)
        $tb = New-Object System.Drawing.Drawing2D.LinearGradientBrush($topR, $colA, $colB, [single]0.0)
        $g.FillRectangle($tb, $topR)
        $tb.Dispose()
        $edge = New-Object System.Drawing.Pen((Get-SplashColor $P.Edge), [single]1)
        $g.DrawRectangle($edge, 0, 0, [int]$L.W - 1, [int]$L.H - 1)
        $edge.Dispose()

        # logo: yumusak golge ya da isilti, gradyanli yuvarlak kare, ust yarida hafif parlaklik, beyaz M
        $ms = [double]$L.MarkSize
        $mx = [double]$L.MarkX
        $my = [double]$L.MarkY
        $mr = 16.0 * $S
        $dy = 0.0
        $ga = 7
        if ($P.Light) { $dy = 6.0 * $S; $ga = 5 }
        for ($i = 7; $i -ge 1; $i--) {
            $gr = [double]$i * 3.0 * $S
            $gp = New-RoundPath ($mx - $gr) ($my - $gr + $dy) ($ms + 2.0 * $gr) ($ms + 2.0 * $gr) ($mr + $gr)
            $gb = New-Object System.Drawing.SolidBrush((Get-SplashColor $P.Glow $ga))
            $g.FillPath($gb, $gp)
            $gb.Dispose()
            $gp.Dispose()
        }
        $mp = New-RoundPath $mx $my $ms $ms $mr
        $mrect = New-Object System.Drawing.RectangleF([single]$mx, [single]$my, [single]$ms, [single]$ms)
        $mb = New-Object System.Drawing.Drawing2D.LinearGradientBrush($mrect, $colA, $colB, [single]45.0)
        $g.FillPath($mb, $mp)
        $mb.Dispose()
        $hr = New-Object System.Drawing.RectangleF([single]$mx, [single]$my, [single]$ms, [single]($ms * 0.55))
        $hb = New-Object System.Drawing.Drawing2D.LinearGradientBrush($hr, [System.Drawing.Color]::FromArgb(70, 255, 255, 255), [System.Drawing.Color]::FromArgb(0, 255, 255, 255), [single]90.0)
        $g.SetClip($mp)
        $g.FillRectangle($hb, $hr)
        $g.ResetClip()
        $hb.Dispose()
        $mp.Dispose()
        $mpen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, [single](5.0 * $S))
        $mpen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
        $mpen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
        $mpen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
        $u = $ms / 60.0
        $pts = New-Object 'System.Drawing.PointF[]' 5
        $pts[0] = New-Object System.Drawing.PointF([single]($mx + 17.0 * $u), [single]($my + 43.0 * $u))
        $pts[1] = New-Object System.Drawing.PointF([single]($mx + 17.0 * $u), [single]($my + 17.0 * $u))
        $pts[2] = New-Object System.Drawing.PointF([single]($mx + 30.0 * $u), [single]($my + 33.0 * $u))
        $pts[3] = New-Object System.Drawing.PointF([single]($mx + 43.0 * $u), [single]($my + 17.0 * $u))
        $pts[4] = New-Object System.Drawing.PointF([single]($mx + 43.0 * $u), [single]($my + 43.0 * $u))
        $g.DrawLines($mpen, $pts)
        $mpen.Dispose()

        # ad: harfler arasi bosluklu, harf harf gradyanli, yatayda ortali
        $word = 'MULTIMIZER'
        $fmt = [System.Drawing.StringFormat]::GenericTypographic
        $sp = 7.0 * $S
        $widths = New-Object 'double[]' $word.Length
        $total = 0.0
        for ($i = 0; $i -lt $word.Length; $i++) {
            $widths[$i] = [double]($g.MeasureString([string]$word[$i], $script:FontMark, 1000, $fmt).Width)
            $total += $widths[$i]
        }
        $total += $sp * ($word.Length - 1)
        $x = ([double]$L.W - $total) / 2.0
        for ($i = 0; $i -lt $word.Length; $i++) {
            $t = [double]$i / [double]($word.Length - 1)
            $col = [System.Drawing.Color]::FromArgb(255, [int]($P.AccentA[0] + ($P.AccentB[0] - $P.AccentA[0]) * $t), [int]($P.AccentA[1] + ($P.AccentB[1] - $P.AccentA[1]) * $t), [int]($P.AccentA[2] + ($P.AccentB[2] - $P.AccentA[2]) * $t))
            $br = New-Object System.Drawing.SolidBrush($col)
            $g.DrawString([string]$word[$i], $script:FontMark, $br, [single]$x, [single]$L.WordY, $fmt)
            $br.Dispose()
            $x += $widths[$i] + $sp
        }

        # slogan ve alt bilgi (surum, yapimci)
        $sf = New-CenterFormat $script:Rtl
        $tbr = New-Object System.Drawing.SolidBrush((Get-SplashColor $P.Tagline))
        $tr = New-Object System.Drawing.RectangleF([single]$L.TextX, [single]$L.TagY, [single]$L.TextW, [single]$L.TagH)
        $g.DrawString([string]$script:Slogan, $script:FontTag, $tbr, $tr, $sf)
        $tbr.Dispose()
        $sf.Dispose()
        $foot = 'Creator: S. Tibet Tuncer'
        if ($script:VerText -ne '') { $foot = $script:VerText + '  ' + [char]0x00B7 + '  ' + $foot }
        $sf2 = New-CenterFormat $false
        $fbr = New-Object System.Drawing.SolidBrush((Get-SplashColor $P.Dim))
        $fr = New-Object System.Drawing.RectangleF([single]$L.TextX, [single]$L.FootY, [single]$L.TextW, [single]$L.FootH)
        $g.DrawString($foot, $script:FontFoot, $fbr, $fr, $sf2)
        $fbr.Dispose()
        $sf2.Dispose()
    } finally { $g.Dispose() }
    return $bmp
}

function Invoke-Splash {
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()
    $script:Clock = [System.Diagnostics.Stopwatch]::StartNew()
    $script:Text = (Get-LT 'baslat')
    $script:Slogan = (Get-LT 'slogan')
    $script:VerText = ''
    $v = Get-AppVersionText
    if ($v -ne '') { $script:VerText = 'v' + $v }
    $script:Rtl = ($script:LaunchLang -eq 'ar')
    $script:Pal = Get-SplashPalette (Get-LaunchLight)
    $scale = 1.0
    try {
        $gs = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero)
        $scale = [double]$gs.DpiX / 96.0
        $gs.Dispose()
    } catch { }
    $script:Lay = Get-SplashLayout $scale
    $pt = [System.Drawing.GraphicsUnit]::Point
    $reg = [System.Drawing.FontStyle]::Regular
    $script:FontMark = New-Object System.Drawing.Font('Segoe UI Semibold', 24, $reg, $pt)
    $script:FontTag = New-Object System.Drawing.Font('Segoe UI', 10, $reg, $pt)
    $script:FontTxt = New-Object System.Drawing.Font('Segoe UI', 11.5, $reg, $pt)
    $script:FontSmall = New-Object System.Drawing.Font('Segoe UI', 9, $reg, $pt)
    $script:FontFoot = New-Object System.Drawing.Font('Segoe UI', 8.5, $reg, $pt)

    $form = New-Object System.Windows.Forms.Form
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $form.ClientSize = New-Object System.Drawing.Size([int]$script:Lay.W, [int]$script:Lay.H)
    $form.BackColor = (Get-SplashColor $script:Pal.BgTop)
    $form.TopMost = $true
    $form.ShowInTaskbar = $false
    $form.Text = 'Multimizer'
    $form.Cursor = [System.Windows.Forms.Cursors]::AppStarting
    try {
        $pi = [System.Windows.Forms.Control].GetProperty('DoubleBuffered', [System.Reflection.BindingFlags]'Instance,NonPublic')
        $pi.SetValue($form, $true, $null)
    } catch { }
    $script:Form = $form
    # yumusak belirme: pencere saydam baslar, her turda biraz acilir (desteklenmezse hemen tam gorunur)
    try { $form.Opacity = 0.0 } catch { $script:NoFade = $true }

    $form.Add_Paint({
        param($s, $e)
        try { Draw-Splash $e.Graphics } catch { }
    })
    $form.Add_Shown({
        try { Start-DenetciAsync } catch { Add-LaunchTrace ('denetci baslatma hatasi: ' + $_.Exception.Message); $script:ErrText = [string]$_.Exception.Message; Complete-Launch 'olu'; $script:Form.Close() }
    })
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 40
    $script:Tick = 0
    $timer.Add_Tick({
        try {
            $script:Tick = [int]$script:Tick + 1
            # belirme / solma
            try {
                if ($script:Closing) {
                    $o = 1.0
                    try { $o = [double]$script:Form.Opacity } catch { }
                    if ($script:NoFade -or $o -le 0.3) { $script:Timer.Stop(); $script:Form.Close(); return }
                    Set-SplashOpacity ($o - 0.25)
                    return
                }
                if (-not $script:NoFade -and [double]$script:Form.Opacity -lt 1.0) { Set-SplashOpacity ([double]$script:Form.Opacity + 0.14) }
            } catch { $script:NoFade = $true }
            # asama dosyasi ve bitis kosullari 200 ms'de bir denetlenir
            if (($script:Tick % 5) -eq 0 -and -not $script:Finished) {
                $r = Step-Launch
                if ($r -ne '') {
                    Complete-Launch $r
                    $script:Closing = $true
                    return
                }
            }
            # cubuk hedefi
            if ($null -ne $script:Stat) {
                $age = ([double]($script:Clock.ElapsedMilliseconds - $script:StatAt)) / 1000.0
                $script:Target = Get-ProgressTarget ([int]$script:Stat.Pct) ([int]$script:Stat.Next) $age
                $script:Shown = $script:Shown + ($script:Target - $script:Shown) * 0.15
            }
            $script:Form.Invalidate()
        } catch { }
    })
    $script:Timer = $timer
    $timer.Start()
    [void][System.Windows.Forms.Application]::Run($form)
    try { $timer.Stop(); $timer.Dispose(); $form.Dispose() } catch { }
    try { if ($null -ne $script:Static) { $script:Static.Dispose(); $script:Static = $null } } catch { }
    if (-not $script:Finished) { Complete-Launch 'kapatildi' }
}

# Her karede: sabit katman + durum metni (yeni metin yumusakca belirir) + ortali ilerleme cubugu (parlama ile) + yuzde
function Draw-Splash($g) {
    $L = $script:Lay
    $P = $script:Pal
    $S = [double]$L.Scale
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    if ($null -eq $script:Static -and -not $script:StaticFailed) {
        try { $script:Static = New-SplashStatic } catch { $script:StaticFailed = $true; Add-LaunchTrace ('acilis ekrani cizimi: ' + $_.Exception.Message) }
    }
    if ($null -ne $script:Static) {
        $g.DrawImageUnscaled($script:Static, 0, 0)
    } else {
        # yedek gorunum: duz zemin ve ad (ana cizim kurulamazsa ekran bos kalmaz)
        $g.Clear((Get-SplashColor $P.BgTop))
        $sfb = New-CenterFormat $false
        $bb = New-Object System.Drawing.SolidBrush((Get-SplashColor $P.AccentA))
        $rb = New-Object System.Drawing.RectangleF([single]0, [single]$L.WordY, [single]$L.W, [single]$L.WordH)
        $g.DrawString('MULTIMIZER', $script:FontMark, $bb, $rb, $sfb)
        $bb.Dispose()
        $sfb.Dispose()
    }

    # durum metni
    try {
        $now = [int]$script:Clock.ElapsedMilliseconds
        if ([string]$script:LastText -ne [string]$script:Text) { $script:LastText = [string]$script:Text; $script:TextAt = $now }
        $a = [int][math]::Min(255.0, 255.0 * ([double]($now - [int]$script:TextAt) / 220.0))
        if ($a -lt 0) { $a = 0 }
        $tbr = New-Object System.Drawing.SolidBrush((Get-SplashColor $P.Text $a))
        $sf = New-CenterFormat $script:Rtl
        $tr = New-Object System.Drawing.RectangleF([single]$L.TextX, [single]$L.StatusY, [single]$L.TextW, [single]$L.StatusH)
        $g.DrawString([string]$script:Text, $script:FontTxt, $tbr, $tr, $sf)
        $tbr.Dispose()
        $sf.Dispose()
    } catch { }

    # ilerleme cubugu (ortali, yuvarlak uclu)
    try {
        $bx = [int]$L.BarX
        $by = [int]$L.BarY
        $bw = [int]$L.BarW
        $bh = [int]$L.BarH
        $cy = [single]($by + $bh / 2.0)
        $tp = New-Object System.Drawing.Pen((Get-SplashColor $P.Track), [single]$bh)
        $tp.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
        $tp.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
        $g.DrawLine($tp, [single]($bx + $bh / 2.0), $cy, [single]($bx + $bw - $bh / 2.0), $cy)
        $tp.Dispose()
        $colA = Get-SplashColor $P.AccentA
        $colB = Get-SplashColor $P.AccentB
        if ($null -eq $script:Stat) {
            # asama bilgisi yok: gidip gelen belirsiz parca
            $seg = [int](110.0 * $S)
            $span = $bw - $seg
            $ph = ([int]([double]$script:Tick * 7.0 * $S)) % (2 * $span)
            if ($ph -gt $span) { $ph = 2 * $span - $ph }
            $sp = New-RoundPath ($bx + $ph) $by $seg $bh ($bh / 2.0)
            $sr = New-Object System.Drawing.RectangleF([single]($bx + $ph), [single]$by, [single]$seg, [single]$bh)
            $sbr = New-Object System.Drawing.Drawing2D.LinearGradientBrush($sr, $colA, $colB, [single]0.0)
            $g.FillPath($sbr, $sp)
            $sbr.Dispose()
            $sp.Dispose()
        } else {
            $fw = [int]([math]::Max([double]$bh, [math]::Min(100.0, [double]$script:Shown) / 100.0 * $bw))
            $fx = $bx
            if ($script:Rtl) { $fx = $bx + $bw - $fw }
            $fp = New-RoundPath $fx $by $fw $bh ($bh / 2.0)
            $fr = New-Object System.Drawing.RectangleF([single]$fx, [single]$by, [single]$fw, [single]$bh)
            $fbr = New-Object System.Drawing.Drawing2D.LinearGradientBrush($fr, $colA, $colB, [single]0.0)
            $g.FillPath($fbr, $fp)
            $fbr.Dispose()
            # parlama: dolu kisim uzerinde kayan ince isik
            $hw = [double](90.0 * $S)
            $cyc = 1800
            $pos = [double]([int]$script:Clock.ElapsedMilliseconds % $cyc) / [double]$cyc
            $hx = $fx - $hw + ($fw + $hw) * $pos
            if ($script:Rtl) { $hx = $fx + $fw - ($fw + $hw) * $pos }
            $hr = New-Object System.Drawing.RectangleF([single]$hx, [single]$by, [single]$hw, [single]$bh)
            $hbr = New-Object System.Drawing.Drawing2D.LinearGradientBrush($hr, [System.Drawing.Color]::FromArgb(0, 255, 255, 255), [System.Drawing.Color]::FromArgb(0, 255, 255, 255), [single]0.0)
            $cb = New-Object System.Drawing.Drawing2D.ColorBlend(3)
            $cb.Colors = [System.Drawing.Color[]]@([System.Drawing.Color]::FromArgb(0, 255, 255, 255), [System.Drawing.Color]::FromArgb(120, 255, 255, 255), [System.Drawing.Color]::FromArgb(0, 255, 255, 255))
            $cb.Positions = [single[]]@(0.0, 0.5, 1.0)
            $hbr.InterpolationColors = $cb
            $g.SetClip($fp)
            $g.FillRectangle($hbr, $hr)
            $g.ResetClip()
            $hbr.Dispose()
            $fp.Dispose()
            # yuzde (cubugun altinda ortali)
            $pc = [int][math]::Round([math]::Min(100.0, [math]::Max(0.0, [double]$script:Shown)))
            $pbr = New-Object System.Drawing.SolidBrush((Get-SplashColor $P.Dim))
            $pf = New-CenterFormat $false
            $prc = New-Object System.Drawing.RectangleF([single]$L.TextX, [single]$L.PctY, [single]$L.TextW, [single]$L.PctH)
            $g.DrawString([string]$pc + '%', $script:FontSmall, $pbr, $prc, $pf)
            $pbr.Dispose()
            $pf.Dispose()
        }
    } catch { }
}

function Invoke-Karsilama {
    # Baslat.bat acilis ekraninin keskin cizilmesi icin bu sureci yuksek DPI duyarli baslatir; denetci ve uygulama bu ayari miras almasin
    try { [Environment]::SetEnvironmentVariable('__COMPAT_LAYER', $null, 'Process') } catch { }
    Write-Handshake
    Add-LaunchTrace ('karsilama basladi; yonetici=' + (Test-IsAdmin) + '; kod=' + $Kod + '; dil=' + $script:LaunchLang)
    if (-not (Test-Path -LiteralPath $script:AppPs1)) {
        Show-LaunchMessage (Get-LT 'betik_yok')
        return 1
    }
    $quiet = $false
    foreach ($a in $script:Forward) { if ([string]$a -ieq '-Tepsi') { $quiet = $true } }
    $shownOk = $false
    if (-not $quiet) {
        try { Invoke-Splash; $shownOk = $true } catch { Add-LaunchTrace ('acilis ekrani hatasi: ' + $_.Exception.Message) }
    }
    if (-not $shownOk -and -not $script:Finished) { Invoke-QuietWait }
    $why = 'bitti'
    if ($script:KExit -eq 3) { $why = 'izin' } elseif ($script:KExit -eq 1) { $why = 'olu' }
    if ($why -ne 'bitti' -and $shownOk) { Show-LaunchFailure $why }
    try { if ($null -ne $script:Ps) { $script:Ps.Dispose() }; if ($null -ne $script:Rs) { $script:Rs.Dispose() } } catch { }
    Remove-QuietFile (Join-Path $env:TEMP ('mm-basladi-' + $Kod + '.txt'))
    return $script:KExit
}

# ---------------- giris ----------------
$script:LaunchLang = Get-LaunchLang $script:Forward
if ($Rol -ieq 'Denetci') {
    $res = @(Invoke-Denetci)
    exit ([int]$res[$res.Count - 1])
}
$res = @(Invoke-Karsilama)
exit ([int]$res[$res.Count - 1])
