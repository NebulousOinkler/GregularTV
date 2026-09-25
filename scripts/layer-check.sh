#!/bin/sh
# Layer check. Keeps the three parts of the code separate, so the logic can
# be reused with another server or another kind of app (such as radio):
#
#   Sources/GregularCore       the logic. Imports Foundation only: no
#                              Jellyfin, no Apple TV frameworks, no UI.
#   Sources/GregularJellyfin   the Jellyfin connection. Imports Foundation,
#                              GregularCore and Security (the Keychain) only.
#   App/GregularTV             the tvOS app. Only the files in APP_JELLYFIN
#                              may import GregularJellyfin; everything else
#                              (the player, guide, Settings, remote) uses
#                              GregularCore's interfaces.
#
# Runs as a unit test (LayerTests). To allow a new import, think about which
# part the code belongs in first.
set -eu
cd "$(dirname "$0")/.."

APP_JELLYFIN='
App/GregularTV/AppModel.swift
App/GregularTV/DemoMode.swift
App/GregularTV/Login/LoginModel.swift
App/GregularTV/Login/LoginView.swift
'
#   AppModel.swift:   signs in and hands the client on as Core's interfaces.
#   DemoMode.swift:   a pretend sign-in for screenshots (Debug only).
#   Login/:           the Jellyfin sign-in screens (Quick Connect, password).

violations=$(
    grep -rn '^import ' Sources/GregularCore --include='*.swift' \
        | grep -vE ':import Foundation$' || true
    grep -rn '^import ' Sources/GregularJellyfin --include='*.swift' \
        | grep -vE ':import (Foundation|GregularCore|Security)$' || true
    grep -rn '^import GregularJellyfin' App/GregularTV --include='*.swift' \
        | while IFS= read -r line; do
            file=${line%%:*}
            echo "$APP_JELLYFIN" | grep -qxF "$file" || echo "$line"
          done
)

if [ -n "$violations" ]; then
    echo "error: Layer check failed. These imports cross between the logic, Jellyfin and the app (see Package.swift):" >&2
    echo "$violations" | sed 's/^/error: /' >&2
    exit 1
fi
echo "Layer check passed."
