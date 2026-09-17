#!/bin/sh
# Smoke-test every example that has an .expect file.
#
#   sh tests/run_examples.sh
#
# Each example declares its own port in the first `# port: N` line of .expect.

REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$REPO"

fails=0

for dir in examples/*/; do
    example=${dir%/}
    [ -f "$example/.expect" ] || continue

    port=$(sed -n 's/^# *port: *\([0-9]\+\).*/\1/p' "$example/.expect" | head -1)
    [ -n "$port" ] || port=8080

    if sh tests/run_example.sh "$example" "$port"; then
        :
    else
        fails=$((fails + 1))
    fi
    echo ""
done

if [ "$fails" -eq 0 ]; then
    echo "all examples passed"
else
    echo "$fails example(s) failed"
fi

exit "$fails"
