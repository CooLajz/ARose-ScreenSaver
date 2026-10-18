# ARose ScreenSaver

[English](README.md) | **Česky**

Nativní rekonstrukce modulu ARose pro BlitzBlank na Amize. Obsahuje aplikaci `ARose.app` s vloženým rozšířením spořiče `.appex` a samostatný klasický `.saver`. Všechny varianty sdílejí vykreslovací kód i rozhraní nastavení ve Swiftu a AppKitu. Windows port používá C++ a Direct2D. Projekt funguje bez emulátoru a bez síťové komunikace.

Aplikace a klasický `.saver` mají cíl sestavení macOS 13+, vložené rozšíření `.appex` macOS 14+. Rozšíření používá neveřejné rozhraní ScreenSaver. Výstupy jsou univerzální pro Apple Silicon i Intel; ruční ověření proběhlo na Macu M2. Intel ani všechny starší verze macOS zatím nebyly otestovány.

Projekt se připravuje k prvnímu veřejnému vydání. Windows x64 port má ověřené nativní sestavení a základní testy; úplné provozní ověření ještě zbývá. Obsahuje systémový `.scr`, vlastní nastavení a náhled. Pokyny uvádí [instalační příručka](Windows/INSTALL.txt). Nový kód používá licenci MIT v rozsahu popsaném v [licenčním upozornění](THIRD_PARTY_NOTICES.md); původní řídicí tabulky pod MIT nepřelicencováváme. Před zveřejněním je potřeba vyjasnit oprávnění k odvozeným částem.

Postup balení a podmínky veřejného vydání uvádí [průvodce vydáváním](docs/releases.md).

## Spuštění a instalace

- Otevřete DMG ze složky `dist/releases/` a přetáhněte **ARose** na **Applications (Aplikace)**.
- Aplikaci `/Applications/ARose.app` jednou spusťte. V její nabídce otevřete **Nastavení systémového spořiče…** a v macOS vyberte ARose. Po výměně aplikace jednou spusťte nainstalovanou kopii. Automaticky obnoví hostitele spořiče a případné otevřené Nastavení systému.
- Rozšíření zůstává uvnitř aplikace; žádný `.saver` se nekopíruje do Knihovny. Aplikace nemusí při běhu systémového spořiče zůstat otevřená.
- Na macOS 13 nebo při požadavku na klasický formát rozbalte `dist/ARose.saver.zip` a otevřete `ARose.saver` ve Finderu. Oba formáty mají oddělená nastavení; není nutné instalovat oba.
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
./script/build_and_run.sh --build  # aplikace s rozšířením a samostatný .saver
./script/build_and_run.sh --verify # sestavení, spuštění a ověření procesu
./script/test.sh                  # testy po sestavení
./script/package_macos_installer.sh # DMG s přetažením do Aplikací
```

Skript vytváří univerzální balíčky, odstraní nepřípustná metadata Finderu pouze z výstupů v `dist/` a podepíše je pro lokální použití. Log sestavení je v `.build/build.log`. Xcode schéma `ARose` sestaví aplikaci, její rozšíření a klasický spořič a spouští náhled.

## Dvě podoby

Výchozí nastavení pro nové uživatele je **Moderní**, **záře 80 %** a **Dlouhá stopa** (16 kroků), s normální rychlostí. Již uložené volby se při aktualizaci nemění.

**Originální Amiga** zachovává celočíselné souřadnice, původní palety a mazání stop. Na macOS i Windows kreslí přímo do fyzického rozlišení displeje. Ve výchozím stavu zapnutá volba „Zvětšovat retro obrazce podle rozlišení“ zvětšuje obrazce stejným měřítkem jako Modern (kratší strana v pixelech dělená 640), body však zůstávají jednopixelové. Vypnutím zachováte pevnou pixelovou velikost jako na Amize; zvětšování podle rozlišení přinesl novější WinRose. Počáteční cílový poloměr simulace je 150 bez ohledu na displej. Změna rozlišení zachová figuru a vymaže stopu; každý monitor ve Windows má vlastní rastr.

**Moderní** používá stejnou sekvenci obrazců a 96 bodů, ale souřadnice počítá s desetinnou přesností. Body vykresluje jako jemné vyhlazené kruhy přímo do aktuálního rozlišení displeje včetně Retiny. Jejich velikost je omezená, takže se při zvětšení okna nemění v roztažené čtverce. Obrazce se rovnoměrně přizpůsobují kratší straně plochy, bez deformace na širokoúhlých nebo svislých monitorech. Plynulá RGB duha není omezená indexovanou paletou; starší body stopy postupně zeslabují. Maximální skutečně zobrazený počet odstínů závisí na displeji a jeho barevné hloubce.

**Záře (0–100 %)** v moderním režimu přidává měkké barevné světlo kolem bodů a světlejší ostré jádro. Nula zachovává dosavadní vzhled. Vyšší hodnoty zesilují i rozšiřují záři; překrývající se stopy se světelně sčítají. Záře nemění matematiku ani rychlost animace a v originálním režimu je vypnutá. Intenzita se uloží tlačítkem Uložit.

Při přepnutí podoby se animace spustí od začátku. Volba původní palety zůstává uložená i při používání moderní verze. Ostatní instance načtou novou konfiguraci při svém příštím vytvoření nebo opětovném spuštění animace.

## Potíže s tlačítkem Volby

Aplikace a systémový spořič mají samostatná nastavení i uložené figury na macOS i Windows. Nastavení aplikace slouží k nezávislému zkoušení obrazců; systémový spořič se nastavuje tlačítkem Volby v macOS nebo Nastavení ve Windows. Změny se mezi nimi nepřenášejí.

Klasický `.saver` může nadále trpět problémem se zobrazením voleb po zavření a znovuotevření celého výběru spořičů. Nové rozšíření `.appex` používá vlastní proces a systémový konfigurační řadič, takže tento způsob zobrazování přes `legacyScreenSaver` obchází. Na macOS 27.0.1 bylo ověřeno opakované zavření a otevření celého výběru, otevření voleb a Uložit/Zrušit bez restartu Nastavení systému. Zobrazuje se i vlastní dlaždice ARose.

Neveřejné rozhraní se může v budoucnu změnit. Provozní ověření macOS 14–26 a hardwaru Intel zatím chybí. Podrobnosti obsahuje [popis rozšíření a ověření](docs/macos-extension.md).

## Věrnost originálu

Základem je rozbor `BB.ARose020881`, interní verze **1.2 (05.04.95)** z archivu **ARoseBlitz1.1**. Přeneseny byly řídicí tabulky, 96 bodů, celočíselné výpočty, trigonometrické tabulky, rotace, barvy a kruhová historie stop. Režim AGA používá 96 odstínů duhy na původně 256barevné obrazovce; režim ECS používá 12 odstínů na 16barevné obrazovce.

Na macOS režim Originální Amiga kreslí přímo do fyzických pixelů aktuální plochy, včetně Retina displejů. Střed leží uprostřed plochy a počáteční cílový poloměr odpovídá čtvrtině kratšího rozměru. Další poloměry z původních tabulek zůstávají pevné: na větším displeji jsou obrazce relativně menší a body se nezvětšují. Změna velikosti zachová rozpracovanou figuru a vymaže její stopu. Simulace běží 50 kroků za sekundu, v návaznosti na PAL časování. Začíná malým obrazcem, který postupně roste a mění se.

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

Windows sestavíte a otestujete příkazem `./script/build_windows.ps1` (C++ Build Tools 2022, Windows SDK, CMake a Python 3). Moderní režim používá dávkové GPU vykreslování přes Direct3D 11, se záložním rendererem Direct2D. CPU overlay uvádí použitý renderer. [Měření Windows rendereru](docs/windows-performance.md) (anglicky) popisuje reprodukovatelné porovnání, CPU, snímkovou frekvenci a změřené obrazové odchylky. Zbývající provozní kontroly uvádějí [podklady pro pokračování na Windows](docs/windows-handoff.md).

## Pokračování od posledního obrazce

S vypnutou volbou začíná každé nové spuštění systémového spořiče od začátku,
i když macOS znovu použije stejný pohled. Opakovaný požadavek na spuštění již
běžící animace obrazec neresetuje. Náhledy označené systémem jako náhled si
ponechají rozpracovaný obrazec i při dočasném zastavení.

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

Na macOS 14 a novějším se moderní animace řídí obnovováním displeje, včetně
120 Hz. Polohy a barvy mezisnímků se interpolují mezi nezměněnými 50Hz kroky
simulace. Původní režim Amiga a starší macOS zachovávají PAL časování.
Skutečnou obnovovací frekvenci může systém omezit podle displeje a napájení.

## Instalace a aktualizace

Nástroje připravují instalační DMG pro macOS a instalátor pro Windows, vedle nich
samostatné `.saver.zip` / `.scr`. Doprovodné aplikace nabízejí ruční kontrolu a
volitelnou týdenní kontrolu (výchozí stav vypnuto). Po potvrzení se aktualizace
stáhne, ověří a nainstaluje přes Sparkle / WinSparkle. Samostatné spořiče
nevyžadují aktualizátor ani další runtime. Veřejné balíčky zatím nejsou vydané.
Podrobnosti jsou v [dokumentaci aktualizací](docs/updates.md).
