#!/bin/sh
# Layer check. Keeps the four parts of the code separate, so the logic can
# be reused with another server, and the screens with another device or a
# web page (see Package.swift):
#
#   Sources/GregularCore       the logic. Imports Foundation only.
#   Sources/GregularJellyfin   the Jellyfin connection. Imports Foundation and
#                              GregularCore only, so it runs on any platform.
#   Sources/GregularKeychain   Apple only: the sign-in in the Keychain. Imports
#                              Foundation, Security and GregularJellyfin only.
#                              Only the Apple TV app uses it.
#   Sources/GregularScreens    what the screens do, without drawing them.
#                              Imports Foundation, Observation, GregularCore,
#                              and GregularJellyfin in SCREENS_JELLYFIN only.
#                              No SwiftUI, UIKit or AVFoundation.
#   App/GregularTV             Apple TV: views, AVFoundation, the remote.
#                              Never imports (or links) GregularJellyfin: it
#                              gets everything through GregularScreens (and
#                              its sign-in storage from GregularKeychain).
#   Web/Sources/GregularBrowser  the browser's side of GregularJellyfin and
#                              GregularCore: fetch(), the sign-in vault, local
#                              storage. Foundation, GregularCore,
#                              GregularJellyfin and JavaScriptKit only.
#   Web/Sources/GregularWeb    the web app: pages, <video>, the keyboard.
#                              Like the Apple TV app, never imports
#                              GregularJellyfin, and no SwiftUI or UIKit.
#   Tools/KeywordHash          a tool, not part of the app (keyword-hash).
#                              Foundation and GregularCore only.
#
# Imports hold file by file: Package.swift and the Xcode project turn on
# MemberImportVisibility, so a file can't use another module's extension
# members just because a different file in its module imports it.
#
# Also a contract no script can check: every string GregularScreens hands a
# front end is plain text. SwiftUI's Text shows it as such; a web front end
# must escape it (names come from the server, so they're untrusted).
#
# Runs as a unit test (LayerTests). To allow a new import, think about which
# part the code belongs in first.
set -eu
cd "$(dirname "$0")/.."

SCREENS_JELLYFIN='
Sources/GregularScreens/App/AppModel.swift
Sources/GregularScreens/App/LoginModel.swift
Sources/GregularScreens/App/DemoCredentials.swift
Sources/GregularScreens/App/ServerAccess.swift
'
#   AppModel.swift:         signs in and hands the client on as Core's interfaces,
#                           and names the server for text on screen (serverName).
#   LoginModel.swift:       the Jellyfin sign-in steps (Quick Connect, password).
#   DemoCredentials.swift:  a pretend sign-in for screenshots (Debug only).
#   ServerAccess.swift:     makes every server and client, with the platform's transport and formats.

violations=$(
    grep -rn '^import ' Sources/GregularCore --include='*.swift' \
        | grep -vE ':import Foundation$' || true
    grep -rn '^import ' Sources/GregularJellyfin --include='*.swift' \
        | grep -vE ':import (Foundation|GregularCore)$' || true
    grep -rn '^import ' Sources/GregularKeychain --include='*.swift' \
        | grep -vE ':import (Foundation|Security|GregularJellyfin)$' || true
    grep -rn '^import ' Sources/GregularScreens --include='*.swift' \
        | grep -vE ':import (Foundation|Observation|GregularCore|GregularJellyfin)$' || true
    grep -rn '^import GregularJellyfin' Sources/GregularScreens --include='*.swift' \
        | while IFS= read -r line; do
            file=${line%%:*}
            echo "$SCREENS_JELLYFIN" | grep -qxF "$file" || echo "$line"
          done
    grep -rn '^import GregularJellyfin' App/GregularTV --include='*.swift' || true
    grep -rn '^import ' Web/Sources/GregularBrowser --include='*.swift' \
        | grep -vE ':import (Foundation|GregularCore|GregularJellyfin|JavaScriptKit|JavaScriptEventLoop|JavaScriptFoundationCompat)$' || true
    grep -rn '^import ' Tools/KeywordHash --include='*.swift' \
        | grep -vE ':import (Foundation|GregularCore)$' || true
    grep -rn '^import ' Web/Sources/GregularWeb --include='*.swift' \
        | grep -vE ':import (Foundation|Observation|GregularCore|GregularScreens|GregularBrowser|JavaScriptKit|JavaScriptEventLoop)$' || true
    # Nor does the Xcode project link it into the app: it comes in only
    # through GregularScreens and GregularKeychain.
    grep -n 'GregularJellyfin' App/GregularTV.xcodeproj/project.pbxproj | sed 's|^|App/GregularTV.xcodeproj/project.pbxproj:|' || true
    # Nor does text on screen name the server outside those files: it says
    # `AppModel.serverName`. (Comments may.)
    grep -rn '"[^"]*Jellyfin' Sources/GregularScreens App/GregularTV Web/Sources/GregularWeb --include='*.swift' \
        | grep -vE '^[^:]+:[0-9]+:[[:space:]]*//' \
        | while IFS= read -r line; do
            file=${line%%:*}
            echo "$SCREENS_JELLYFIN" | grep -qxF "$file" || echo "$line"
          done
)

if [ -n "$violations" ]; then
    echo "error: Layer check failed. These imports (or names) cross between the parts of the code (see Package.swift):" >&2
    echo "$violations" | sed 's/^/error: /' >&2
    exit 1
fi
echo "Layer check passed."
