#!/bin/zsh
# bounded.sh SECONDS command… — runs the command; SIGALRM kills it after SECONDS,
# then any test helpers it left behind. No extra process holds the output open.
limit=$1; shift
perl -e 'alarm shift; exec @ARGV or die' "$limit" "$@"
code=$?
if [ $code -eq 142 ]; then
  echo "WATCHDOG: killed after ${limit}s"
  pkill -f swiftpm-testing-helper; pkill -f GregularPackageTests
  # A simulator diagnose an xcodebuild test run started (and was killed waiting on).
  pkill -f 'simctl diagnose.*xcresult'
fi
exit $code
