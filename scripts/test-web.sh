#!/bin/zsh
# test-web.sh browser|unit|walkthrough [debug|release] — the web version's
# tests, under a hard time limit (scripts/bounded.sh).
#
#   scripts/test-web.sh browser       the browser layer's own tests (Web/Tests),
#                                     in Node
#
#   scripts/test-web.sh unit          the package's own tests (GregularCore,
#                                     GregularJellyfin, GregularScreens), built
#                                     for WebAssembly and run in WasmKit: the
#                                     same code, as a browser runs it (32-bit)
#   scripts/test-web.sh walkthrough   a build of the web version (debug unless
#                                     told), driven
#                                     in Chromium, WebKit and Firefox by
#                                     Playwright (Web/walkthrough), against the demo
#                                     server, which it starts and stops
#
# Needs the swift.org toolchain and WebAssembly SDK, and for the walkthrough
# `npm install` and `npx playwright install` in Web/, and the demo video
# (`swift scripts/make-demo-video.swift`) (README, *The web version*).
set -eu
here=${0:A:h}
kind=${1:-}
sdk=${GREGULAR_WASM_SDK:-swift-6.4.0-RELEASE_wasm}
case $kind in
  browser)
    cd "$here/../Web"
    exec "$here/bounded.sh" 1200 "$here/web-swift.sh" package --swift-sdk "$sdk" --disable-sandbox js test ;;
  unit)
    build=$here/../.build/wasm
    # An 8 MB stack, as the web app has (Web/Package.swift).
    "$here/bounded.sh" 1800 "$here/web-swift.sh" build --package-path "$here/.." --build-tests --swift-sdk "$sdk" --scratch-path "$build" \
        -Xlinker -z -Xlinker stack-size=8388608
    products=$(ls -d "$build"/out/Products/*-webassembly-wasm32 2>/dev/null || echo "$build/debug")
    wasmkit=${GREGULAR_SWIFT_TOOLCHAIN:-$HOME/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain}/usr/bin/wasmkit
    [ -x "$wasmkit" ] || wasmkit=$(command -v wasmkit)
    # WasmKit interprets, many times slower than a browser: these tests wait
    # fractions of a second for a fade or a channel change, which it can't
    # keep up with. They run natively in `swift test` and the app's tests.
    slow='theSoundFadesOutWithThePictureAtTheEndOfTheLastClip|aClipEndingEarlyDoesntCloseTheCurtainOverTheCard'
    slow+='|thePictureFadesOutWhileChangingChannelAndBackOnceItPlays|surfingBackToTheSameChannelBringsThePictureBack'
    failed=0
    for suite in Core Jellyfin Screens; do
      echo "== Gregular${suite}Tests (WebAssembly)"
      "$here/bounded.sh" 3000 "$wasmkit" run --dir "$here/.." "$products/Gregular${suite}Tests-test-runner.wasm" \
        --testing-library swift-testing --skip "$slow" || failed=1
    done
    exit $failed ;;
  walkthrough)
    "$here/build-web.sh" "${2:-debug}"
    cd "$here/../Web"
    exec "$here/bounded.sh" 900 npx playwright test ;;
  *) echo "usage: scripts/test-web.sh browser|unit|walkthrough [debug|release]" >&2; exit 2 ;;
esac
