#!/bin/zsh
# test-app.sh unit|walkthrough [xcodebuild options…] — runs the app's tests in
# the simulator, under a hard time limit (scripts/bounded.sh).
#
#   scripts/test-app.sh unit          the GregularTV scheme's tests (GregularTVTests)
#   scripts/test-app.sh walkthrough   the UI walkthrough (start scripts/demo-server.py first)
#
# Extra options go to xcodebuild, such as
# -only-testing:GregularTVUITests/WalkthroughTests/test7MainPage.
# DESTINATION picks the simulator (default: the "GregularTV Tests" one).
#
# Diagnostics collection is off: after any failing test, xcodebuild otherwise
# runs `simctl diagnose` (a sysdiagnose of the simulator, allowed 600 s) and
# sits waiting on it long after the tests have finished.
set -u
here=${0:A:h}
kind=${1:-}
[ $# -gt 0 ] && shift
case $kind in
  unit) scheme=GregularTV; limit=400; only=(-only-testing:GregularTVTests) ;;
  walkthrough) scheme=GregularTVWalkthrough; limit=900; only=() ;;
  *) echo "usage: scripts/test-app.sh unit|walkthrough [xcodebuild options…]" >&2; exit 2 ;;
esac
# With -only-testing given, run just that.
for arg in "$@"; do [[ $arg == -only-testing:* ]] && only=(); done
exec "$here/bounded.sh" $limit xcodebuild test \
  -project "$here/../App/GregularTV.xcodeproj" -scheme $scheme \
  -destination "${DESTINATION:-platform=tvOS Simulator,name=GregularTV Tests}" \
  -collect-test-diagnostics never "${only[@]}" "$@"
