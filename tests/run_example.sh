#!/bin/sh
# Smoke-test an example project under real nginx.
#
#   sh tests/run_example.sh examples/hello 8080
#
# Boots the example's nginx.conf (with `-p` = repo root), requests the paths
# listed in <example>/.expect, prints status + body, then shuts nginx down.
#
# POSIX sh only -- dash has no arrays, and building the client argv as a string
# silently word-splits `--header "X-Api-Token: secret"` into two arguments,
# which looks exactly like a broken auth guard.
set -e

REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
EXAMPLE=${1:-examples/hello}
PORT=${2:-8080}
CONF="$EXAMPLE/nginx.conf"

cd "$REPO"
mkdir -p logs "$EXAMPLE/logs" .e2e
rm -f "$EXAMPLE/logs/error.log" "$EXAMPLE/logs/access.log"

echo "### $EXAMPLE (port $PORT)"
echo ""

echo "--- nginx -t ---"
nginx -p "$REPO" -c "$CONF" -t 2>&1
echo ""

nginx -p "$REPO" -c "$CONF" >/dev/null 2>&1 &
NGINX_JOB=$!
sleep 2

ARGS_FILE=$(mktemp)
cleanup() {
    kill "$NGINX_JOB" 2>/dev/null || true
    if [ -f "$EXAMPLE/logs/nginx.pid" ]; then
        kill "$(cat "$EXAMPLE/logs/nginx.pid")" 2>/dev/null || true
    fi
    rm -f "$ARGS_FILE"
}
trap cleanup EXIT INT TERM

fails=0

# check <path> <expected_status> [header:value ...]
check() {
    path=$1
    want=$2
    shift 2

    # One argument per line so values with spaces survive.
    : > "$ARGS_FILE"
    for h in "$@"; do
        printf '%s\n' "$h" >> "$ARGS_FILE"
    done

    out=$(HDR_FILE="$ARGS_FILE" luajit tests/support/http_get.lua "$PORT" "$path" --headers-from "$ARGS_FILE" 2>&1) || true
    status=$(printf '%s\n' "$out" | sed -n 1p)
    body=$(printf '%s\n' "$out" | sed -n 2p)

    printf '%-32s ' "$path"
    if [ "$status" = "$want" ]; then
        printf '%-3s OK   %s\n' "$status" "$body"
    else
        printf '%-3s FAIL (want %s)  %s\n' "${status:-none}" "$want" "$body"
        fails=$((fails + 1))
    fi
}

if [ -f "$EXAMPLE/.expect" ]; then
    # shellcheck disable=SC1090
    . "$EXAMPLE/.expect"
else
    echo "no $EXAMPLE/.expect file -- nothing to check"
fi

echo ""
if [ "$fails" -eq 0 ]; then
    echo "all checks passed"
else
    echo "$fails check(s) failed"
fi

echo ""
echo "--- lua errors from the error log (if any) ---"
grep -a "\[lua\]\|\[error\]" "$EXAMPLE/logs/error.log" 2>/dev/null | tail -20 || echo "(none)"

exit "$fails"
