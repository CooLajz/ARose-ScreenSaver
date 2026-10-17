# Rekonstrukce ARose

## Podklady

- [ARoseBlitz1.1 na Aminetu](https://aminet.net/package/util/blank/ARoseBlitz1.1)
- [Archiv ARoseBlitz1.1.lha](https://aminet.net/util/blank/ARoseBlitz1.1.lha)
- [Dokumentace v archivu Garshneblanker varianty](https://aminet.net/package/util/blank/ARoseGarshn1_4)

Analyzován byl Amiga HUNK soubor `BB.ARose020881`, varianta pro 68020 a 68881. Archiv byl rozbalen systémovým `tar`, instrukce disassemblovány pomocí Capstone 5.0.9 v režimu M68K 020. Disassembler sloužil ke čtení instrukcí, kód Amigy nebyl spouštěn.

SHA-256 archivu:

```text
e8ee5fe14161930c08ff1470f7899a10bb68b3d4d200cc3f4fb1774ad803ba9f
```

SHA-256 modulu:

```text
def45dee11c1788b473aa1d2143106a798a58e4dce511e10ad041cd482963667
```

## Mapa kódu

Adresy jsou relativní vůči začátku CODE hunku, nikoli souboru. První CODE hunk začíná na souborovém offsetu `0x24`.

| Adresa | Význam |
| --- | --- |
| `0x038c–0x05e4` | Příprava barev, AGA duha o 6 × 16 odstínech a ECS alternativa |
| `0x0628–0x0664` | Střed obrazovky a počáteční cílový poloměr, čtvrtina menšího rozměru |
| `0x06a4–0x0724` | Výpočet 1 440 hodnot sinu a kosinu, násobek 4 096, zaokrouhlení k nule |
| `0x084e–0x08c8` | Inicializace 96 záznamů po 94 bytech, počáteční úhly po 15 krocích |
| `0x09a6–0x0e1a` | Jeden simulační krok |
| `0x0a06–0x0a26` | Mazání nejstarších bodů černou |
| `0x0a3a–0x0ab8` | Složení souřadnic a rotace |
| `0x0acc–0x0afe` | Volba a postupné cyklování barvy každého bodu |
| `0x0b68–0x0bc6` | Rotace celého obrazce a změna primárního úhlu |
| `0x0bda–0x0c78` | Změny frekvence a dvou poloměrů |
| `0x0c7c–0x0e0e` | Čítače a přechody řídicích tabulek |
| `0x0f4c–0x0f56` | Čekání na vertikální obnovu před krokem animace |

Relativní adresy DATA hunku: `0x013c` poloměr A (48 slov), `0x019c` poloměr B (102 slov), `0x0268` režim rotace (14 slov), `0x0284` frekvence (87 slov). Data jsou přepsána v `RoseTables.swift`.

## Souřadnice

Pro bod `i` je počáteční úhel `15i`, tedy rovnoměrné rozmístění 96 bodů do 1 440 dílků. Sekundární úhel se odvozuje od pevného počátečního úhlu a proměnlivého parametru `frequency / 200`.

S celočíselným dělením k nule se nejprve vypočítají:

```text
u = (radiusA × sinTable[angle] + radiusB × sinTable[secondary]) / 4096
v = (radiusA × cosTable[angle] + radiusB × cosTable[secondary]) / 4096
x = centerX + (v × cosTable[rotation] - u × sinTable[rotation]) / 4096
y = centerY - (v × sinTable[rotation] + u × cosTable[rotation]) / 4096
```

Při generování tabulky se úhel po každém přírůstku ukládá do `Float`, stejně jako původní `fmove.s`. Konstanta přírůstku je zachována bitově (`0x3f71df46a2529d39`). Hostitelské `sin`/`cos` ovšem nemusí mít bitově totožný výsledek jako 68881.

Stopa se nezeslabuje průhledností. Nejstarší souřadnice všech bodů se nejprve vymažou a nové se vykreslí. Tím zůstává zachováno i typické vymazávání překrývajících se stop.

## Vědomé odlišnosti a meze ověření

- Pevná logická plocha 800 × 600 místo volitelného obrazového režimu Amigy.
- PAL časování 50 Hz; původní rychlost na NTSC nebo grafické kartě mohla být jiná.
- macOS zvětšuje hotovou bodovou bitmapu bez vyhlazování a zachovává poměr stran.
- Bez ukládání rozpracovaného obrazce (`BB.ARose.act`) a cache trigonometrie (`BB.ARose.dat`). Každé nové vytvoření view začíná od začátku.
- Bez emulace původních chyb při ukládání historie bodů mimo obrazovku; současná implementace bezpečně ořezává zápisy.
- Port nepředstírá bitově přesnou emulaci 16bitového přetečení u libovolných vstupů; používá původní omezené řídicí tabulky a širší hostitelská celá čísla.
- Dosud neproběhlo automatické porovnání snímek po snímku s originálem na Amize nebo v emulátoru. Uživatel při vizuální kontrole uvedl, že náhled vypadá jako originál.

## Moderní varianta

Volitelná moderní podoba zachovává řídicí tabulky a 96 bodů, ale vyhodnocuje trigonometrické funkce v `Double` bez původní kvantizace souřadnic a sekundárního úhlu. Historii bodů vykresluje vektorově při každém překreslení v aktuálním měřítku displeje. Barva je spojitá funkce indexu bodu a času, nikoli původní indexovaná paleta. Stopy mají postupnou průhlednost a již se navzájem nemažou černým pixelem. Tyto odlišnosti jsou záměrné a aktivují se výhradně volbou Moderní.
