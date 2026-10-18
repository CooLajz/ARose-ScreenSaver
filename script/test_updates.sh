#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
xcrun swiftc Sources/Updates/UpdatePolicy.swift Tests/Updates/main.swift -o .build/update-policy-tests
.build/update-policy-tests
c++ -std=c++17 Tests/Updates/main.cpp -o .build/update-policy-cpp-tests
.build/update-policy-cpp-tests
python3 -B -m unittest discover -s Tests/Updates -p 'test_*.py'
