#!/bin/zsh
# build-web.sh [release|debug] — builds the web version into Web/dist,
# ready to serve as static files (WEB_PLAN.md):
#
#   Web/dist/index.html, app.css, js/, vendor/   Web/public, as they are
#   Web/dist/app/                                 GregularWeb, compiled to WebAssembly
#   Web/dist/editor.html, editor.css, editor.js   the channel editor: the same
#                                                 files the Apple TV serves to phones
#                                                 (Sources/GregularScreens/Editing/Page)
#
# Needs the swift.org toolchain and its WebAssembly SDK (README, *The web
# version*). Debug builds have demo mode (?demoServer=…) and Debug options.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
configuration=${1:-release}
sdk=${GREGULAR_WASM_SDK:-swift-6.4.0-RELEASE_wasm}
dist=$root/Web/dist
page=$root/Sources/GregularScreens/Editing/Page

"$root/scripts/web-swift.sh" package --swift-sdk "$sdk" \
    --allow-writing-to-directory "$root/Web/.build/app" \
    js -c "$configuration" --product GregularWeb --output "$root/Web/.build/app"

rm -rf "$dist"
cp -R "$root/Web/public" "$dist"
cp -R "$root/Web/.build/app" "$dist/app"
cp "$page/editor.css" "$page/editor.js" "$dist/"
{
    cat <<'HEAD'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="referrer" content="no-referrer">
<title>Gregular TV channels</title>
<link rel="stylesheet" href="editor.css">
</head>
<body>
HEAD
    cat "$page/editor-body.html"
    print '<script src="editor.js"></script>\n</body>\n</html>'
} > "$dist/editor.html"
# The packaging step's own notes, and its Node.js and threads versions,
# aren't part of the site. Its WASI shim comes from this site (vendor/),
# never a CDN.
rm -f "$dist/app/package.json" "$dist/app/"*.d.ts "$dist/app/platforms/"*.d.ts \
    "$dist/app/platforms/node.js" "$dist/app/platforms/browser.worker.js"
perl -pi -e "s#'\@bjorn3/browser_wasi_shim'#'../../vendor/browser_wasi_shim/index.js'#" "$dist/app/platforms/browser.js"
if grep -rqE "(from|import)[[:space:]]*\(?[[:space:]]*['\"](https?:|//|@)" "$dist/app"; then
    echo "error: the packaged app still loads something from outside the site." >&2
    exit 1
fi
# Cloudflare serves no file over 25 MiB, and the app is larger, so it's
# split into parts that js/main.js joins as they download (Cloudflare still
# compresses each). The parts are named for the build, so a page loading
# during a deploy can't mix two versions; app/wasm.json lists them.
python3 - "$dist/app" <<'SPLIT'
import hashlib, json, os, sys
app = sys.argv[1]
whole = os.path.join(app, "GregularWeb.wasm")
data = open(whole, "rb").read()
build = hashlib.sha256(data).hexdigest()[:16]
part_size = 20 * 1024 * 1024
parts = []
for start in range(0, len(data), part_size):
    name = f"GregularWeb.{build}.{start // part_size}.wasm"
    with open(os.path.join(app, name), "wb") as part:
        part.write(data[start:start + part_size])
    parts.append(name)
os.remove(whole)
with open(os.path.join(app, "wasm.json"), "w") as manifest:
    json.dump({"parts": parts, "size": len(data)}, manifest)
SPLIT
too_large=$(find "$dist" -type f -size +25M)
if [ -n "$too_large" ]; then
    echo "error: Cloudflare won't serve a file over 25 MiB: $too_large" >&2
    exit 1
fi
echo "Built the web version ($configuration) into Web/dist: $(du -sh "$dist" | cut -f1), the app in $(ls "$dist/app/"*.wasm | wc -l | tr -d ' ') parts."
