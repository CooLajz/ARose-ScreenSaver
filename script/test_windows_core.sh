#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/parity .build/ModuleCache
python3 script/generate_windows_tables.py --check
clang++ -std=c++17 -O2 -Wall -Wextra -Werror -ffp-contract=off Tests/Parity/main.cpp -o .build/parity/cpp-engine
.build/parity/cpp-engine --self-test
clang++ -std=c++17 -O2 -Wall -Wextra -Werror -ffp-contract=off Tests/WindowsRendering/main.cpp -o .build/parity/windows-rendering
.build/parity/windows-rendering
.build/parity/cpp-engine > .build/parity/cpp.txt
xcrun swiftc -O -module-cache-path .build/ModuleCache Sources/Core/*.swift Tests/Parity/main.swift -o .build/parity/swift-engine
.build/parity/swift-engine > .build/parity/swift.txt
python3 script/check_engine_parity.py --actual .build/parity/cpp.txt --reference .build/parity/swift.txt
python3 script/check_engine_parity.py --actual .build/parity/cpp.txt

clang++ -std=c++17 -O2 -Wall -Wextra -Werror -ffp-contract=off Tests/FigureState/main.cpp -o .build/parity/windows-figure
.build/parity/windows-figure
xcrun swiftc -O -module-cache-path .build/ModuleCache Sources/Core/*.swift Tests/FigureState/main.swift -o .build/parity/swift-figure
.build/parity/swift-figure
