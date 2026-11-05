#!/usr/bin/env bash
# Runs the example project the way its README tells a customer to: `bundle exec rackup` in example-project/, a visit
# to / (the app logs three lines, the middlewares the request and the response) and one to /error (the app raises, the
# middlewares log the error and a 500 response), then Ctrl+C. The example sends what is still buffered when the
# server stops, so the server is stopped right after the second request. The server's output goes to out/example.log,
# and a failure ends with one ::error:: line.
# Env: BETTER_STACK_SOURCE_TOKEN, BETTER_STACK_INGESTING_HOST, and example-project/Gemfile's gems installed.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=$ROOT/out
LOG=$OUT/example.log
# rackup's default port. Rack 1 listens on 0.0.0.0, newer ones on localhost, so the requests go to localhost.
URL=http://localhost:9292
mkdir -p "$OUT"

# The server's output, then the error, if any.
SERVER=""
ERROR=""
fail() {
  ERROR=$1
  exit 1
}
finish() {
  [ -z "$SERVER" ] || kill -KILL "$SERVER" 2> /dev/null || true
  cat "$LOG"
  [ -z "$ERROR" ] || echo "::error::$ERROR"
}
trap finish EXIT

cd "$ROOT/example-project"
bundle exec rackup > "$LOG" 2>&1 &
SERVER=$!

# Ready once the port takes a connection. A request would be logged and stored as a row of its own.
for ((second = 0; ; second++)); do
  if (exec 3<> /dev/tcp/localhost/9292) 2> /dev/null; then break; fi
  kill -0 "$SERVER" 2> /dev/null || fail "The example project exited before it listened: $(tail -n 1 "$LOG")"
  [ "$second" -lt 60 ] || fail "The example project did not listen on $URL within 60 s"
  sleep 1
done

request() {
  local status
  status=$(curl -sS -m 30 -o "$OUT/response.txt" -w '%{http_code}' "$URL$1") || status=000
  echo "GET $1 answered HTTP $status"
  [ "$status" = "$2" ] || fail "GET $1 answered HTTP $status instead of $2: $(head -c 300 "$OUT/response.txt" 2> /dev/null)"
}
request / 200
request /error 500

# Ctrl+C. rackup traps SIGINT and shuts the server down, then Ruby runs the at_exit hooks.
kill -INT "$SERVER"
for ((second = 0; ; second++)); do
  kill -0 "$SERVER" 2> /dev/null || break
  [ "$second" -lt 30 ] || fail "The example project did not stop within 30 s of SIGINT"
  sleep 1
done
STATUS=0
wait "$SERVER" || STATUS=$?
[ "$STATUS" = 0 ] || fail "The example project exited with status $STATUS: $(tail -n 1 "$LOG")"

# logtail 0.1.21 and newer warn about a batch Better Stack rejected, older releases drop it silently.
if grep -q 'Better Stack rejected' "$LOG"; then
  fail "$(grep -m 1 'Better Stack rejected' "$LOG")"
fi
