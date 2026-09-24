#!/bin/sh
# Privacy check (PLAN.md §3). Fails if app or library code uses an API that
# writes to disk, syncs data off the device, or leaves records in system
# logs, anywhere except the files allowed to.
#
# Runs as a build phase of the tvOS app and as a unit test (PrivacyTests).
#
# To allow a new use: think hard, then add the file to ALLOWED with a reason.
set -eu
cd "$(dirname "$0")/.."

# APIs that persist or leak data.
FORBIDDEN='UserDefaults|@AppStorage|@SceneStorage|NSUbiquitousKeyValueStore|CloudKit|FileManager|\.write\(to:|createFile|NSKeyedArchiver|import CoreData|import SwiftData|NSPersistentContainer|URLCache|urlCache|HTTPCookieStorage|httpCookieStorage|SecItem[A-Za-z]*\(|URLSession\.shared|URLSessionConfiguration|os_log|NSLog|Logger\(|import OSLog|import os$|AVAssetDownload|print\('

# file: reason
ALLOWED='
Sources/GregularTVCore/Privacy/SecureStore.swift
Sources/GregularTVCore/Privacy/AppPreferences.swift
Sources/GregularTVCore/Jellyfin/HTTPTransport.swift
'
#   SecureStore.swift:    Keychain; the only credential storage (server URL, token, user ID, device ID).
#   AppPreferences.swift: UserDefaults; last channel number and streaming quality only.
#   HTTPTransport.swift:  builds the one ephemeral URLSession, with cache and cookies switched off.

violations=$(grep -rnE "$FORBIDDEN" Sources App/GregularTV --include='*.swift' \
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
