#!/bin/sh
# Parse-check every Lua file in the project, including examples.
#
# Examples were previously skipped here, which let a syntax error in
# examples/api/Api/routes.lua reach a running nginx (it surfaced as a 404 on
# every route, because the failed require left the router with zero rules).
fail=0
count=0
for f in $(find Tilua tests examples -name '*.lua' 2>/dev/null | sort); do
    count=$((count + 1))
    if ! luajit -bl "$f" >/dev/null 2>/tmp/synerr; then
        echo "SYNTAX FAIL: $f"
        sed -n '1,3p' /tmp/synerr
        fail=1
    fi
done
if [ "$fail" -eq 0 ]; then
    echo "all $count Lua files parse OK"
fi
exit $fail
