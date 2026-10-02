#!/bin/sh
# Privacy check (PLAN.md §3). Fails if app or library code uses an API that
# writes to disk, syncs data off the device, or leaves records in system
# logs, anywhere except the files allowed to.
#
# Runs as a build phase of the tvOS app and as a unit test (PrivacyTests).
# Also checks the web version (Web/): its Swift, and its own JavaScript.
#
# To allow a new use: think hard, then add the file to ALLOWED with a reason.
set -eu
cd "$(dirname "$0")/.."

# APIs that persist or leak data.
FORBIDDEN='UserDefaults|@AppStorage|@SceneStorage|NSUbiquitousKeyValueStore|CloudKit|FileManager|\.write\(to:|createFile|NSKeyedArchiver|import CoreData|import SwiftData|NSPersistentContainer|URLCache|urlCache|HTTPCookieStorage|httpCookieStorage|SecItem[A-Za-z]*\(|URLSession\.shared|URLSessionConfiguration|os_log|NSLog|Logger\(|import OSLog|import os$|AVAssetDownload|print\('

# The browser's equivalents, in the web version's Swift and JavaScript (its
# own code; Web/public/vendor holds unchanged libraries).
WEB_FORBIDDEN='localStorage|sessionStorage|indexedDB|document\.cookie|sendBeacon|serviceWorker|caches\.open|console\.(log|info|debug)'

# file: reason
ALLOWED='
Sources/GregularKeychain/KeychainStore.swift
Sources/GregularCore/Preferences/AppPreferences.swift
Sources/GregularJellyfin/HTTPTransport.swift
Web/Sources/GregularBrowser/BrowserPreferences.swift
Web/public/js/vault.js
'
#   KeychainStore.swift:  Keychain; the only credential storage on Apple platforms (server URL, token,
#                         user ID, device ID).
#   AppPreferences.swift: UserDefaults; client settings only (last channel, quality, schedule code,
#                         switches) and custom channels as the channel codes the viewer made.
#   HTTPTransport.swift:  builds the one ephemeral URLSession, with cache and cookies switched off.
#   BrowserPreferences.swift: local storage; the same client settings as AppPreferences, in a browser.
#   vault.js:             IndexedDB; the browser's sign-ins, encrypted (the Keychain's job on Apple TV).

violations=$({ grep -rnE "$FORBIDDEN" Sources App/GregularTV Web/Sources --include='*.swift'
               grep -rnE "$WEB_FORBIDDEN" Web/Sources Web/public/js --include='*.swift' --include='*.js'; } \
    | grep -vE '^[^:]+:[0-9]+:[[:space:]]*//' \
    | while IFS= read -r line; do
        file=${line%%:*}
        echo "$ALLOWED" | grep -qxF "$file" || echo "$line"
      done)

if [ -n "$violations" ]; then
    echo "error: Privacy check failed. These lines use APIs that persist or leak data (see PLAN.md §3):" >&2
    echo "$violations" | sed 's/^/error: /' >&2
    exit 1
fi
echo "Privacy check passed."
