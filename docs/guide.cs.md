# Uživatelský průvodce ARose

[English](guide.md) | **Česky** · [Zpět na hlavní stránku](../README.cs.md)

## Požadavky a stav vydání

Verze 1.0.3 je první veřejné vydání. Instalační soubory a aktualizační kanály jsou dostupné v GitHub Releases.

| Platforma | Požadavek | Stav ověření |
| --- | --- | --- |
| macOS | macOS 14+ pro aplikaci se systémovým spořičem; Apple Silicon nebo Intel | Ručně ověřováno na Macu M2. Další verze macOS a Intel zatím čekají na provozní ověření. |
| Windows | Windows 11 x64 | Prošly nativní CI, test instalátoru a závěrečný test správce projektu na Windows. |

Veřejné Mac balíčky mají podpis Developer ID a notarizaci od Applu. Windows soubory nejsou podepsané a systém může zobrazit upozornění na neznámého vydavatele. Samotné úspěšné sestavení nepotvrzuje vyzkoušení na všech systémech.

## Instalace

### Mac

1. Otevřete instalační DMG a přetáhněte ARose na Aplikace.
2. Spusťte nainstalovanou aplikaci jednou ze složky Aplikace.
3. V nabídce **ARose → Nastavení systémového spořiče…** vyberte ARose a otevřete **Volby…**.

Umístění spořičů v Nastavení systému se liší podle verze macOS; na novějších verzích je najdete v části Tapeta. Aplikace může po výměně nebo aktualizaci obnovit otevřené Nastavení systému, aby se načetl nový spořič. Aplikaci poté můžete zavřít.

Klasický `.saver` není součástí plánovaných veřejných souborů ke stažení. Pokud jej máte ze starších vývojových testů, jde o nezávislou instalaci; přetažení nové aplikace jej neodstraní.

### Windows

Spusťte instalační `Setup.exe`, potvrďte správce a dokončete průvodce. V nabídce Start najdete **ARose** s ovládacími prvky a **ARose Preview** s animací v okně. V systémovém nastavení spořičů zvolte ARose. Instalátor ani spořič nepřebírají správu hesla, zamykání nebo doby nečinnosti — tyto volby dál spravují Windows.

### Samostatný spořič pro Windows

Samostatný `ARose.scr` nevyžaduje aplikaci ani další frameworky. Uložte jej do trvalé složky, klikněte na něj pravým tlačítkem a zvolte **Nainstalovat** (případně nejprve **Zobrazit další možnosti**). Tím otevřete systémové nastavení spořičů, kde vyberete ARose.

Dokud je soubor vybraný jako spořič, nepřesouvejte jej. Novou verzi pak instalujete ruční výměnou souboru. Pro pohodlné aktualizace použijte plný instalátor.

## Kde měnit nastavení

**Aplikace a systémový spořič mají vlastní oddělené volby i uloženou pozici.**

- Pro systémový spořič použijte **Volby…** v macOS nebo **Nastavení** v systémovém dialogu Windows.
- V aplikaci macOS otevřete tlačítko **Nastavení…**. Ve Windows otevřete náhled a stiskněte **F1**.
- Změny potvrďte tlačítkem **Uložit**. **Zrušit** je zahodí.

## Co jednotlivé volby dělají

| Volba | Význam |
| --- | --- |
| Vzhled | **Originální Amiga** pro retro body a palety, **Moderní** pro jemné body a plynulou duhu. |
| Rychlost | Mění tempo proměn a pohybu. |
| Stopa | Určuje, jak dlouhá historie bodů zůstává viditelná. |
| Barvy | V Retro režimu vybírá černobílou, ECS nebo AGA paletu. Moderní režim používá plynulou RGB duhu. |
| Záře | V Moderním režimu nastavuje světlo kolem bodů od 0 do 100 %. Při nule zůstávají jemné body bez záře. |
| Zvětšovat retro obrazce podle rozlišení | Zvětší obrazce pro dnešní displeje, ale body ponechá ostré. Vypnutím získáte pevnou pixelovou velikost jako na Amize. Zvětšování podle rozlišení přinesl pozdější WinRose. |
| Pokračovat od posledního obrazce | Při dalším spuštění naváže přibližně na předchozí pozici. Ve výchozím stavu je vypnuté. |
| Zapomenout uložený obrazec | Po potvrzení tlačítkem Uložit smaže pozici v právě nastavované aplikaci či spořiči. Volbu pokračování nevypíná. |
| Debug: zobrazovat vytížení procesu | Volitelný technický údaj o CPU; pro běžné používání jej můžete ponechat vypnutý. |

Pokračování obnovuje obrazec, natočení a barevnou fázi, nikoli uložený obrázek. Stopa se po spuštění znovu dokreslí. Vypnutí pokračování pozici nemaže; k resetu použijte **Zapomenout uložený obrazec → Uložit**. Změna vzhledu může animaci restartovat.

## Aplikace pro hraní s obrazci

| Akce | macOS | Náhled Windows |
| --- | --- | --- |
| Nastavení | Tlačítko Nastavení… nebo ⌘ , | F1 |
| Celá obrazovka | ⌘ F | F |
| Pozastavit / pokračovat | ⌘ P | Mezerník |
| Začít znovu | ⌘ R | R |
| Posunout animaci dopředu | ⌘ N | — |
| Ukončit | ⌘ Q | Esc; z celé obrazovky nejprve vrátí okno |

### Experimentální živé pozadí na Macu (vývojová verze)

V nabídce **Obrazec → Živé pozadí (experimentální)** můžete vyzkoušet animaci na hlavním monitoru pod ikonami plochy. Okno a ikona v Docku zmizí; ovládání najdete pod ikonou ARose v horní liště. Nabídka nabízí nastavení, pozastavení, restart, **Zpět do okna** a ukončení. Pozadí používá nastavení doprovodné aplikace. Před zapnutím opusťte celou obrazovku a zavřete nastavení.

Volba **Spouštět po přihlášení** používá systémové přihlašovací položky macOS. Zapněte ji až u kopie ve složce Aplikace; případné schválení dokončete v Nastavení systému. Aplikace si pamatuje poslední režim a při dalším spuštění obnoví i živé pozadí. Autorun je zpočátku vypnutý a je nezávislý na týdenní kontrole aktualizací.

Pouze živé pozadí při pozastavení během dvou sekund plynule zabrzdí a při pokračování se během dvou sekund rozjede. Přechod platí i pro automatickou pauzu při fullscreenu, spořiči nebo zamčení. První spuštění z černé obrazovky začíná normální rychlostí. Běžné okno aplikace a systémový spořič zachovávají okamžitou pauzu a pokračování. Uspání může doběh přerušit; po probuzení se obnoví pozvolný rozjezd bez dohánění času stráveného ve spánku.

Volba **Pozastavit při aplikaci na celé obrazovce** je zpočátku zapnutá. Při fullscreenu zastaví vykreslování pozadí a po návratu automaticky pokračuje. Zachytí také přehrávače jako Infuse, které fullscreen stav nemusí systému oznámit: jednou za sekundu ověří, zda okno jiné aplikace překrývá celý monitor s pozadím. Ručně zapnutá pauza zůstává zachována. Detekce využívá stav pracovní plochy a rozměry oken, nikoli jejich obrazový obsah či titulky, a nevyžaduje oprávnění ke snímání obrazovky ani zpřístupnění.

Ukončením ARose se odkryje původní tapeta. Moderní animace na pozadí má limit 30 snímků/s; výpočty zachovávají původní časování. Při běhu systémového spořiče, zamčení Macu, uspání displeje nebo neaktivní uživatelské relaci se vykreslování automaticky pozastaví, i když je volba pro fullscreen vypnutá. Po návratu pokračuje; ruční pauza zůstává zachována. Spuštění spořiče se zjišťuje podle oznámení a skutečně zobrazeného okna, nikoli jen podle běžícího procesu. Jde o první prototyp bez výběru monitoru a bez zjišťování, zda je plocha zakrytá běžnými okny; Mission Control a Stage Manager vyžadují další provozní ověření.

## Aktualizace

V nainstalované aplikaci zvolte **Zkontrolovat aktualizace…**. Pokud je nová verze dostupná, aktualizační okno vás provede stažením a instalací. Windows mohou vyžádat potvrzení správce. Aktualizace aplikace na Macu obsahuje i systémový spořič.

Volbu **Automaticky kontrolovat jednou týdně** lze zapnout dobrovolně; zpočátku je vypnutá. Kontrola počítač neprobouzí a její provedení se může odložit, například když je zařízení zamknuté nebo spí. Animace nepotřebuje internet, nevyžaduje účet a neposílá telemetrii.

## Odinstalace

**Mac:** vypněte týdenní kontrolu, je-li zapnutá, vyberte jiný systémový spořič a přesuňte **ARose.app** z Aplikací do koše. Vložený spořič je součástí aplikace. Případný starý samostatný `.saver` se odstraňuje zvlášť ze složky `Library/Screen Savers`.

**Windows instalátor:** použijte odinstalaci aplikace ve Windows. Na sdíleném počítači by si i ostatní uživatelé měli nejprve vybrat jiný spořič.

**Samostatný Windows soubor:** vyberte jiný spořič nebo Žádný a potom smažte `ARose.scr`.

Uložené preference a obrazce zůstanou zachované pro případ nové instalace.

## Když něco nefunguje

- Po ruční výměně na Macu nejprve jednou spusťte novou aplikaci ze složky Aplikace.
- Změna v aplikaci se nepromítla do spořiče? Jejich nastavení jsou záměrně oddělená; otevřete systémové Volby.
- Kontrola aktualizací ve vývojovém sestavení může selhat, dokud není zveřejněný aktualizační kanál.
- Pro hlášení chyby použijte [GitHub Issues](https://github.com/CooLajz/ARose-ScreenSaver/issues). Uveďte systém a jeho verzi, verzi ARose, zvolený režim a postup, jak problém zopakovat. Snímek obrazovky pomůže; osobní údaje před odesláním zakryjte.
