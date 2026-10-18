# ARose ScreenSaver

[English](README.md) | **Česky**

**Kousek Amigy na dnešní obrazovce.** Barevné body, proměnlivé obrazce a pohyb, u kterého se snadno zapomene na čas. ARose přináší oblíbený spořič z Amigy na macOS a Windows — s úctou k originálu a s novou září pro dnešní displeje.

**ARose v pohybu**

https://github.com/user-attachments/assets/b8c67746-8197-4f5f-9714-1877c5d0dc92

## Příběh návratu

Na mé Amize 1200 kdysi běžel BlitzBlank a v něm modul ARose. Pár barevných bodů se otáčelo, zrcadlilo a skládalo do nádherných obrazců. Byl to jeden z těch drobných zážitků, které člověku zůstanou v paměti desítky let.

Když jsem po letech hledal něco podobného pro svůj Mac, dlouho jsem nic, co by vyvolalo stejný pocit, nenašel. A tak začal vznikat tento remake. Cílem bylo zachovat to, co dělalo ARose tak výjimečným: jeho obrazce, proměny, rotace a rytmus pohybu.

Podařilo se oslovit původní autory, **Wolfganga Breyhu a Michaela Matzla**. Návrat ARose podpořili a udělili souhlas s vydáním. Poskytli také původní zdrojové kódy pro kontrolu a zpřesnění chování. Díky tomu jsme mohli porovnat původní matematiku a opravit drobné rozdíly v rotacích.

Výsledkem je návrat známého zážitku ve dvou podobách: s původním bodovým vzhledem, nebo s jemnými body, plynulou duhou a nastavitelnou září. Dnes už pro mě ARose není jen spořič obrazovky. Je to uklidňující pauza u kávy a malý návrat do časů Amigy.

## Amiga, Retro a Moderní

V aplikaci najdete dva režimy. Retro se v nastavení jmenuje **Originální Amiga**; původní Amiga v tabulce znamená historický program, ze kterého remake vychází.

| | Původní ARose na Amize | Retro v tomto remaku | Moderní v tomto remaku |
| --- | --- | --- | --- |
| Obrazce a pohyb | Původní výpočty a sekvence | Důraz na věrnost původním výpočtům a sekvencím | Stejný základ obrazců a pohybu |
| Body | Ostré body v rozlišení Amigy | Ostré jednobodové vykreslení v pixelech displeje | Jemné vyhlazené body i na Retina displejích |
| Barvy | Palety podle možností Amigy | Černobílá, ECS a AGA paleta | Plynulá RGB duha |
| Velikost obrazců | Pevná pixelová velikost | Volitelné zvětšení podle rozlišení, zpočátku zapnuté | Automatické přizpůsobení velikosti plochy |
| Záře | Bez moderního glow efektu | Bez glow efektu | Nastavitelná záře 0–100 % |

**Moderní režim nemění základní sekvenci na jiný efekt.** Rozvíjí její vzhled pro současné monitory a plynulé zobrazení. Retro zachovává původní charakter kresby; nejde však o úplnou emulaci Amigy ani o záruku shody každého jednotlivého snímku.

## Stažení a instalace

**První veřejné vydání: 1.0.3.** Vyberte instalační balíček pro svůj systém:

- [Stáhnout pro macOS — DMG](https://github.com/CooLajz/ARose-ScreenSaver/releases/download/v1.0.3/ARose-ScreenSaver-v1.0.3-macOS-universal.dmg)
- [Stáhnout pro Windows — instalátor](https://github.com/CooLajz/ARose-ScreenSaver/releases/download/v1.0.3/ARose-ScreenSaver-v1.0.3-Windows-x64-Setup.exe)
- [Všechny soubory vydání](https://github.com/CooLajz/ARose-ScreenSaver/releases/latest)

### macOS — macOS 14 a novější

1. Stáhněte soubor **macOS `.dmg`** a otevřete jej.
2. Přetáhněte **ARose** na ikonu **Applications (Aplikace)**.
3. Spusťte ARose ze složky Aplikace. V nabídce **ARose → Nastavení systémového spořiče…** otevřete systémové nastavení a vyberte ARose.
4. Tlačítkem **Volby…** nastavte vzhled systémového spořiče.

Aplikace nemusí při běhu spořiče zůstat otevřená. Pro Mac je k dispozici jeden instalační DMG; samostatný klasický `.saver` zůstává pouze ve zdrojovém projektu. Balíček obsahuje verze pro Apple Silicon i Intel; rozsah dosavadního ověření uvádí [uživatelský průvodce](docs/guide.cs.md#požadavky-a-stav-vydání).

### Windows — Windows 11, 64bitová verze

1. Stáhněte **Windows instalátor `Setup.exe`** a spusťte jej.
2. Potvrďte požadavek správce a dokončete instalaci.
3. V nastavení spořiče obrazovky Windows vyberte **ARose**. Ovládací aplikaci najdete v nabídce Start.

Není potřeba samostatně instalovat .NET ani Visual C++ Redistributable. Pro zájemce je dostupný také [samostatný soubor `.scr`](docs/guide.cs.md#samostatný-spořič-pro-windows).

## Nastavte si vlastní atmosféru

Výchozí kombinace je **Moderní, záře 80 % a Dlouhá stopa**. Můžete si upravit rychlost, délku stopy a sílu záře nebo přepnout na Retro. Volba **Pokračovat od posledního obrazce** umožňuje navázat přibližně tam, kde poslední běh skončil.

Doprovodná aplikace slouží i k hraní s obrazci v okně nebo na celé obrazovce. **Má vlastní nastavení, oddělené od systémového spořiče.** Zkoušení v aplikaci proto nezmění váš spořič.

Aplikace nabízí ruční kontrolu aktualizací a volitelnou kontrolu jednou týdně, která je zpočátku vypnutá. Animace funguje bez internetu a bez účtu; připojení se používá ke kontrole a stažení aktualizací.

[Uživatelský průvodce: nastavení, ovládání, aktualizace a odinstalace →](docs/guide.cs.md)

## Poděkování a licence

Původní ARose pro Amigu vytvořili **Wolfgang Breyha a Michael Matzl v letech 1994–1995**. Děkujeme jim za krásný originál, podporu návratu a pomoc s jeho věrným zachováním. Původní dokumentace uvádí inspiraci modulem Rose z After Dark. [Původní ARose na Aminetu](https://aminet.net/package/util/blank/ARoseBlitz1.1).

Remake vzniká s jejich souhlasem a používá [licenci MIT](LICENSE). Původní zdrojové archivy poskytnuté autory ani původní spustitelné soubory zde nešíříme. Podrobnosti a licence použitých knihoven uvádí [licenční upozornění](THIRD_PARTY_NOTICES.md).

## Pro vývojáře

[Sestavení a struktura projektu](docs/development.cs.md) · [Technické poznámky k rekonstrukci](docs/reconstruction.md) · [Příprava vydání](docs/releases.md)
