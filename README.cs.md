# ARose ScreenSaver

[English](README.md) | **Česky**

Nativní rekonstrukce modulu ARose pro BlitzBlank na Amize. Obsahuje systémový spořič `.saver` a samostatný náhled. Oba používají stejný vykreslovací kód ve Swiftu a AppKitu. Windows port používá C++ a Direct2D. Projekt funguje bez emulátoru a bez síťové komunikace.

Cíl sestavení je macOS 13 a novější. Výstupy jsou univerzální pro Apple Silicon i Intel; ruční ověření proběhlo na Macu M2. Intel ani všechny starší verze macOS zatím nebyly otestovány.

Projekt se připravuje k prvnímu veřejnému vydání. První Windows x64 port je implementovaný; praktické ověření ve Windows ještě zbývá. Obsahuje systémový `.scr`, vlastní nastavení a náhled. Pokyny uvádí [instalační příručka](Windows/INSTALL.txt). Nový kód používá licenci MIT v rozsahu popsaném v [licenčním upozornění](THIRD_PARTY_NOTICES.md); původní řídicí tabulky pod MIT nepřelicencováváme. Před zveřejněním je potřeba vyjasnit oprávnění k odvozeným částem.

Postup balení a podmínky veřejného vydání uvádí [průvodce vydáváním](docs/releases.md).

## Spuštění a instalace

- Otevřete `dist/ARose Preview.app` pro samostatný náhled.
- Pro instalaci rozbalte `dist/ARose.saver.zip` například ve složce Stažené soubory, otevřete rozbalený `ARose.saver` ve Finderu a dokončete instalaci nabízenou macOS. Potom vyberte ARose v nastavení spořiče obrazovky.
- Pokud macOS instalaci dvojklikem nenabídne, zkopírujte `ARose.saver` do složky `~/Library/Screen Savers/` (případně ji vytvořte) a znovu otevřete nastavení spořičů.
- Nastavení nabízí dvě podoby: **Originální Amiga** a **Moderní**, pět rychlostí a šest délek stopy. Originální režim má černobílou, ECS nebo AGA paletu; moderní režim vždy používá plynulou RGB duhu. Změny se projeví při novém spuštění spořiče; náhled se po uložení restartuje okamžitě.

Pro přenos používejte ZIP archivy v `dist/`. Některé spravované složky Dokumentů dodatečně připojují metadata Finderu, která mohou zneplatnit podpis volně uloženého balíčku; ZIP tento problém při přenosu nemá. Test kontroluje podpis i načtení spořiče po rozbalení ZIPu mimo složku projektu.

Balíčky jsou podepsané lokálním ad-hoc podpisem. Nejde o notarizovanou distribuci pro jiné počítače. Instalátor ani tento projekt nemění dobu nečinnosti, zamykání nebo jiná systémová nastavení.

## Ovládání náhledu

Od verze 1.0.3 obsahují spořič i aplikace české a anglické rozhraní. Jazyk se vybírá podle preferovaných jazyků macOS; pokud žádný z nich není podporován, použije se angličtina. Přeložené jsou nastavení, menu, nápovědy, popisky pro zpřístupnění i potvrzovací hlášky. Po změně jazyka je nutné aplikaci nebo systémového hostitele znovu spustit.

| Klávesy | Akce |
| --- | --- |
| ⌘ , | Nastavení |
| ⌘ F | Celá obrazovka |
| ⌘ P | Pozastavit / pokračovat |
| ⌘ R | Spustit sekvenci od začátku |
| ⌘ N | Posunout animaci o 500 snímků (10 sekund) |
| ⌘ Q | Ukončit |

## Sestavení

Je potřeba Xcode s macOS SDK. Otevřete `ARose.xcodeproj`, případně použijte:

```sh
./script/build_and_run.sh          # sestavení a spuštění náhledu
./script/build_and_run.sh --build  # pouze vytvoření obou balíčků v dist/
./script/build_and_run.sh --verify # sestavení, spuštění a ověření procesu
./script/test.sh                  # testy po sestavení
```

Skript vytváří univerzální balíčky, odstraní nepřípustná metadata Finderu pouze z výstupů v `dist/` a podepíše je pro lokální použití. Log sestavení je v `.build/build.log`. Xcode schéma `ARose` sestaví oba cíle a spouští náhled.

## Dvě podoby

Výchozí nastavení pro nové uživatele je **Moderní**, **záře 80 %** a **Dlouhá stopa** (16 kroků), s normální rychlostí. Již uložené volby se při aktualizaci nemění.

**Originální Amiga** zachovává bodovou bitmapu 800 × 600, celočíselné souřadnice, původní palety i mazání stop.

**Moderní** používá stejnou sekvenci obrazců a 96 bodů, ale souřadnice počítá s desetinnou přesností. Body vykresluje jako jemné vyhlazené kruhy přímo do aktuálního rozlišení displeje včetně Retiny. Jejich velikost je omezená, takže se při zvětšení okna nemění v roztažené čtverce. Obrazce se rovnoměrně přizpůsobují kratší straně plochy, bez deformace na širokoúhlých nebo svislých monitorech. Plynulá RGB duha není omezená indexovanou paletou; starší body stopy postupně zeslabují. Maximální skutečně zobrazený počet odstínů závisí na displeji a jeho barevné hloubce.

**Záře (0–100 %)** v moderním režimu přidává měkké barevné světlo kolem bodů a světlejší ostré jádro. Nula zachovává dosavadní vzhled. Vyšší hodnoty zesilují i rozšiřují záři; překrývající se stopy se světelně sčítají. Záře nemění matematiku ani rychlost animace a v originálním režimu je vypnutá. Intenzita se uloží tlačítkem Uložit.

Při přepnutí podoby se animace spustí od začátku. Volba původní palety zůstává uložená i při používání moderní verze. Ostatní instance načtou novou konfiguraci při svém příštím vytvoření nebo opětovném spuštění animace.

## Potíže s tlačítkem Volby

**Od verze 1.0.2 lze systémový spořič nastavovat také z ARose Preview:**

1. V Nastavení systému → Tapeta → Spořič obrazovky vyberte ARose a ponechte otevřený animovaný náhled. Tlačítko Volby není potřeba.
2. Otevřete `ARose Preview.app` a zvolte Obrazec → Nastavení… (⌘ ,). Aplikace nejprve načte volby z běžícího systémového hostitele, pokud odpoví.
3. Upravte nastavení a stiskněte Uložit. Potvrzení „Nastavení převzal i systémový spořič“ znamená, že hostitel potvrdil převzetí hodnot a synchronizaci vlastních předvoleb.
4. Pokud hostitel neodpoví, aplikace oznámí, že změny jsou uložené pouze v náhledu. Spusťte systémový náhled a uložení zopakujte. Přenos se neodkládá do příštího spuštění spořiče.

Přenos probíhá lokálními systémovými oznámeními, bez sítě a bez přímého přepisování souborů předvoleb jiného procesu. Přijímá pouze osm ověřených voleb ARose. Lokálně byl ověřen přenos změny záře, potvrzení od obou běžících hostitelů a zachování hodnoty v novém hostiteli po restartu. Toto řešení obchází problém se systémovým dialogem; neopravuje chybu macOS v tlačítku Volby. Stejné omezení popisuje také [autor Afterglow](https://morphing.cloud/afterglow/help/#known-issues).

Při lokálním ověření na macOS 27.0.1 byl zachycen přerušovaný pád systémového procesu `legacyScreenSaver`: při požadavku `presentConfiguration` přistoupil k první položce prázdného pole `viewControllers`, ještě před předáním požadavku konfiguračnímu oknu modulu. Náhled proto může zmizet nebo se po obnovení hostitele znovu rozběhnout. Pokud Volby nereagují, zavřete výběr spořičů tlačítkem Hotovo, ukončete Nastavení systému a znovu je otevřete. Tento postup není zárukou odstranění systémové chyby.

Verze 1.0.1 uchovává konfigurační okno pro opakované použití, podporuje zavření i mimo připojený panel a zaznamenává požadavek na otevření, uložení a zrušení do systémového logu pod subsystémem `cz.coolajz.ARose`, kategorií `Configuration`. Po aktualizaci byla přímo v Nastavení systému ověřena tři otevření, zrušení a uložení. Dlouhodobé odstranění přerušované chyby hostitele tím není potvrzeno.

Při opakovaném ověření 17. října 2026 se chyba projevila po zavření a znovuotevření celého výběru spořičů. ARose obdržel druhý požadavek a vrátil nový obsah o velikosti 460 × 450, dialog se však neobjevil. Explicitní velikost řadiče ani alternativní ukončení modální relace nepomohly a tyto pokusné změny byly vráceny. Vestavěný spořič Zpráva stejným postupem prošel; tím není určeno, zda zbývající problém leží v integraci ARose, nebo v hostiteli starších spořičů. Automatický test životního cyklu dialogu toto zobrazení mezi procesy neověřuje.

Balíček obsahuje náhledy `thumbnail.png` a `thumbnail@2x.png`; Xcode je ponechává ve formátu PNG. Na lokálním macOS 27.0.1 však systémový seznam i po obnovení služby stále zobrazuje výchozí dlaždici. Tato kosmetická chyba zůstává nevyřešená; animovaný náhled funguje.

## Věrnost originálu

Základem je rozbor `BB.ARose020881`, interní verze **1.2 (05.04.95)** z archivu **ARoseBlitz1.1**. Přeneseny byly řídicí tabulky, 96 bodů, celočíselné výpočty, trigonometrické tabulky, rotace, barvy a kruhová historie stop. Režim AGA používá 96 odstínů duhy na původně 256barevné obrazovce; režim ECS používá 12 odstínů na 16barevné obrazovce.

V režimu Originální Amiga se kreslí na logickou plochu 800 × 600. Obraz se zvětšuje bez vyhlazování, se zachovaným poměrem stran. Na širokoúhlých monitorech zůstávají černé okraje. Simulace běží 50 kroků za sekundu, v návaznosti na PAL časování. Začíná malým obrazcem, který postupně roste a mění se.

Nejde o úplnou emulaci Amigy. Zatím není implementováno původní ukládání rozpracovaného obrazce mezi spuštěními. Přesná shoda jednotlivých snímků s emulovanou nebo fyzickou Amigou nebyla měřena. Podrobnosti a adresy rozebraných rutin jsou v [poznámkách k rekonstrukci](docs/reconstruction.md).

Původní ARose: **Wolfgang Breyha a Michael Matzl, 1994–1995**. Dokumentace uvádí inspiraci modulem Rose z After Dark. Původní binární soubory nejsou součástí projektu.

## Ověření

- Sestavení a kontrola podpisů obou univerzálních balíčků.
- Test 600 000 simulačních snímků ve třech paletách, krajních délek stopy a základního celočíselného výpočtu.
- Dynamické načtení skutečného `.saver` přes `NSBundle`, inicializace náhledu i plné velikosti, vykreslení, konfigurační okno a restart animace.
- Ruční vizuální kontrola běžící aplikace a nastavení.

Testy vytvoří PNG snímky v `.build/test-images/`. Automatické testy používají testovacího hostitele; lokálně byla navíc ověřena instalace, animovaný náhled a konfigurační dialog v Nastavení systému. Omezení systémového hostitele jsou popsána výše.

## Debug CPU

V nastavení zapněte **Debug: zobrazovat vytížení procesu**. Vpravo dole se jednou
za sekundu aktualizuje vytížení CPU procesu spořiče. Výchozí stav je vypnuto.
Vedle sebe se zobrazují dvě hodnoty: **1 jádro** má 100 % pro jedno logické
jádro a může překročit 100 %; **Všechna jádra** má 100 % pro všechna logická
jádra dohromady. Například 300 % a 75 % označuje na čtyřech jádrech stejnou
zátěž procesu. Jde o podíl CPU
času, nikoli výkonově vážené měření; výkonná a úsporná jádra se počítají stejně.
Nejde o celkové vytížení počítače ani GPU. Na macOS údaj zahrnuje celý proces
hostitele, případně více jeho náhledů. Před prvním měřením se zobrazí pomlčka.
Při aktualizaci použijte nový spořič i novou aplikaci náhledu a znovu otevřete
Nastavení systému, aby všechny části používaly nové schéma předvoleb.

Moderní režim na podporovaných Macích vykresluje záři i ostré body přes Metal, také při vypnuté záři. Malá předpočítaná textura zachovává vyhlazování jemných bodů z Core Graphics. Při nedostupnosti Metalu se použije CPU. Obrazové rozdíly a omezení měření jsou popsány v [poznámkách k výkonu](docs/performance.md).

Optimalizace přípravy Windows rendereru a zbývající kontroly přímo na Windows jsou uvedeny v [podkladech pro pokračování na Windows](docs/windows-handoff.md) (anglicky). Nejde zatím o změřené zrychlení ve Windows.

## Pokračování od posledního obrazce

Volba **Pokračovat od posledního obrazce** obnoví při příštím spuštění tvar,
natočení i barevnou fázi, také po restartu počítače. Ve výchozím nastavení je
vypnutá a funguje v obou podobách. Stav se ukládá při běžném ukončení. macOS navíc ukládá první snímek a pak každou
sekundu, protože systémový hostitel nemusí zavolat ukončení; Windows ukládá
každých 30 sekund. Při nuceném ukončení se může poslední interval ztratit.
Stopa se během prvních 0,4 sekundy dokreslí, neukládá se jako obrázek.
Náhled označený systémem jako náhled uloženou pozici nemění. Některé verze macOS
ale spouštějí i dlaždici v Nastavení systému jako plnohodnotný spořič; tehdy
sdílí jeho uloženou pozici. Samostatná náhledová aplikace
pro macOS a okno Windows `/w` mají vlastní oddělenou pozici. Vypnutím volby se
uložený stav přestane používat, ale nesmaže se. Neplatné nebo nepodporované
uložené stavy se ignorují. Žádná data se neposílají po síti.

Pro návrat na začátek stiskněte **Zapomenout uložený obrazec** a poté **Uložit**.
Smaže se pozice spořiče i samostatného náhledu; volba pokračování zůstane beze změny.
Tlačítko **Zrušit** zachová původní pozici.
