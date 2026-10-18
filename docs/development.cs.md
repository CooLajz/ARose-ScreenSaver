# Vývoj ARose ScreenSaver

[English](development.md) | **Česky** · [Uživatelská dokumentace](../README.cs.md)

## Struktura projektu

| Cesta | Účel |
| --- | --- |
| `Sources/Core/` | Swift simulace, původní řídicí tabulky a matematika. |
| `Sources/ScreenSaver/` | Sdílený pohled pro Mac, nastavení, CPU diagnostika a Metal vykreslování. |
| `Sources/Extension/` | Adaptér vloženého rozšíření systémového spořiče. |
| `Sources/Preview/` | Vstupní bod doprovodné aplikace. |
| `Sources/Updates/` | Instalace, životní cyklus a aktualizace. |
| `Windows/` | C++ jádro, Win32 rozhraní, Direct3D 11 renderer, záložní Direct2D a instalátor. |
| `Tests/`, `script/` | Regresní testy, kontrola shody jader, sestavení a balení. |

Aplikace, rozšíření a klasický `.saver` na Macu sdílejí kreslení a konfigurační rozhraní. Každá varianta má vlastní preference a uložené obrazce. Rozšíření používá neveřejné rozhraní ScreenSaver; před úpravou životního cyklu prostudujte [adaptér a provozní ověření](macos-extension.md).

Klasický `.saver` zůstává sestavitelný pro vývoj, ale nepatří mezi plánované veřejné soubory ke stažení. Pro Mac se vydává aplikace v DMG, aktualizační ZIP a appcast. Windows nadále nabízí instalátor i samostatný `.scr`. Některé stávající balicí skripty ještě vytvářejí klasické Mac balíčky; výběr souborů pro vydání je před publikací potřeba sjednotit.

## Sestavení na macOS

Nainstalujte Xcode s macOS SDK a vyberte jeho nástroje příkazové řádky. Z kořene repozitáře spusťte:

```sh
./script/build_and_run.sh          # Sestavení a spuštění ARose
./script/build_and_run.sh --build  # Sestavení bez spuštění
./script/build_and_run.sh --verify # Sestavení, spuštění a kontrola procesu
./script/test.sh                   # Testy po sestavení
./script/test_windows_core.sh      # Porovnání Swift a C++ jádra
./script/package_macos_installer.sh # DMG a aktualizační archiv
```

Projekt `ARose.xcodeproj`, schéma `ARose`, sestaví aplikaci, vložené rozšíření i klasický spořič. Minimum sestavení aplikace a klasického spořiče je macOS 13; rozšíření vyžaduje macOS 14. Výstupy obsahují arm64 i x86_64. Minimum sestavení neznamená provozní ověření všech verzí macOS ani hardwaru Intel.

Log je v `.build/build.log`, čisté archivy v `dist/` a soubory pro vydání v `dist/releases/`. Balení odstraní problematická metadata Finderu ze sestavovaných výstupů a nyní používá místní ad-hoc podpis. Přenášejte vygenerované archivy; opětovné zabalení volných balíčků ve spravované složce Dokumentů může připojit metadata a zneplatnit podpis.

Rozložení DMG používá připnuté verze Python závislostí v `.build/dmg-tools`. Knihovny aktualizací se stahují s kontrolou připnutých hashů. Původní soukromě poskytnutý archiv zdrojáků Amigy musí zůstat mimo repozitář.

## Sestavení na Windows

Nainstalujte Visual Studio 2022 s nástroji C++ pro desktop, Windows SDK, CMake a Python 3. Z kořene projektu:

```powershell
./script/build_windows.ps1
./script/package_windows.ps1
```

První skript sestaví projekt, spustí CTest a ověří shodu jader. Balení navíc vyžaduje **Inno Setup 6.3+ na sestavovacím počítači**. Uživatelé tyto nástroje nepotřebují. MSVC runtime se linkuje staticky a aktualizační knihovna se dodává s aplikací.

Jednotlivé kroky lze spustit i ručně:

```powershell
python script/generate_windows_tables.py --check
cmake -S Windows -B build-windows -A x64
cmake --build build-windows --config Release
ctest --test-dir build-windows -C Release --output-on-failure
python script/check_engine_parity.py --executable build-windows/Release/arose-engine-tests.exe
```

Volitelné křížové sestavení z Macu nebo Linuxu používá `script/build_windows_cross.sh` a proměnnou `ZIG_BIN` s cestou k Zig 0.15.2. Vytvoří binární soubory, ale neprovede provozní testy Windows. Pomocný kompilátor prostředků na Macu vyžaduje macOS 15+.

## Zachování chování při úpravách

Simulace navazuje na původní časování 50 Hz. Moderní vykreslování může interpolovat mezi stavy pro plynulejší obnovování displeje; nesmí tím měnit sekvenci obrazců. Retro zachovává celočíselné zaokrouhlování, palety a mazání stop. Škálování mění zobrazení, nikoli tabulky simulace.

Matematické úpravy a změny neovlivňující kreslení udržujte na obou platformách shodné. Windows tabulky vznikají ze Swift dat skriptem `script/generate_windows_tables.py`; neupravujte je nezávisle. Zachovejte češtinu i angličtinu, soulad uživatelské dokumentace a oddělení předvoleb aplikace a spořiče.

Automatické kontroly pokrývají dlouhé simulace, shodu jader, uložené obrazce, kreslení, nastavení, lokalizaci, načtení skutečného balíčku i řadiče rozšíření. Nenahrazují ruční test celé obrazovky, více monitorů, vysoké obnovovací frekvence, instalace a životního cyklu systémového hostitele. Hardwarově závislou obrazovou odchylku je potřeba posoudit před úpravou kreslení kvůli testovací toleranci.

CPU diagnostika ukazuje „1 jádro“ se 100 % pro jedno logické jádro a „Všechna jádra“ po dělení počtem logických jader. První hodnota může překročit 100 %. Jde o CPU čas, nikoli výkonově vážené měření nebo GPU zátěž. Systémový hostitel může obsluhovat více pohledů.

## Podrobné podklady

- [Rekonstrukce a původ dat](reconstruction.md)
- [Rozšíření macOS a ověření životního cyklu](macos-extension.md)
- [Vykreslování a výkon na macOS](performance.md)
- [Vykreslování a výkon na Windows](windows-performance.md)
- [Podklady pro nativní ověření Windows](windows-handoff.md)
- [Architektura aktualizací a podpisy](updates.md)
- [Příprava vydání](releases.md)
- [Licence a rozsah souhlasu původních autorů](../THIRD_PARTY_NOTICES.md)

Veřejná distribuce vyžaduje finální podpisy, notarizaci macOS a provozní ověření. Podpis Apple Developer ID a podpis aktualizací Sparkle/WinSparkle slouží různým účelům. Soukromé klíče a přihlašovací údaje patří mimo repozitář. Sestavení nebo balení samo o sobě neopravňuje ke zveřejnění vydání.
