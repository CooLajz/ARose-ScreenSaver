#!/bin/bash
# Local signing verification only; does not upload or alter a public feed.
set -euo pipefail
cd "$(dirname "$0")/.."
STAGING="$(mktemp -d /private/tmp/arose-signature-test.XXXXXX)"
trap 'rm -rf "$STAGING"' EXIT
printf 'ARose signed update fixture\n' > "$STAGING/update.zip"
SIGNER="$(python3 script/prepare_signing_tools.py)"
xcrun swiftc -module-cache-path .build/ModuleCache script/verify_update.swift -o "$STAGING/verify_update"
PUBLIC_KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' Resources/Preview-Info.plist)"
SIGNATURE="$("$SIGNER" --account cz.coolajz.ARose -p "$STAGING/update.zip")"
"$STAGING/verify_update" "$STAGING/update.zip" "$SIGNATURE" "$PUBLIC_KEY"
printf 'tampered\n' >> "$STAGING/update.zip"
if "$STAGING/verify_update" "$STAGING/update.zip" "$SIGNATURE" "$PUBLIC_KEY" > "$STAGING/rejected.log" 2>&1; then
    echo 'ERROR: tampered payload accepted' >&2; exit 1
fi
echo 'PASS: genuine payload accepted; modified payload rejected'
