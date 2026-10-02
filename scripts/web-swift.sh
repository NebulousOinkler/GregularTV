#!/bin/zsh
# web-swift.sh ARGS… — runs `swift ARGS…` in Web/ with the swift.org
# toolchain (which has the WebAssembly SDK; Xcode's doesn't) and builds
# into Web/.build. Install both as in README, *The web version*.
set -eu
cd "$(dirname "$0")/../Web"
version=6.4.0
toolchain=${GREGULAR_SWIFT_TOOLCHAIN:-$HOME/Library/Developer/Toolchains/swift-$version-RELEASE.xctoolchain}
swift=$toolchain/usr/bin/swift
[ -x "$swift" ] || swift=$(command -v swift)   # CI: the toolchain is on the PATH
exec "$swift" "$@"
