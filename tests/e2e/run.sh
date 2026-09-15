#!/bin/sh
# End-to-end lifecycle test under real nginx.
#   docker run --rm -v <repo>:/app -w /app openresty/openresty:1.21.4.1-buster \
#          sh tests/e2e/run.sh
mkdir -p /app/.e2e
mkdir -p /app/tests/fixtures/TestApp/cache/view /app/tests/fixtures/TestApp/cache/html
rm -f /app/.e2e/error.log /app/.e2e/access.log /app/.e2e/result.txt /app/logs/error.log

nginx -p /app -c tests/e2e/nginx.conf > /app/.e2e/nginx.out 2>&1 &
NGINX_PID=$!
sleep 2

{
  echo "########## HTTP RESULTS ##########"
  luajit /app/tests/e2e/client.lua
  echo "########## ACCESS LOG ##########"
  cat /app/.e2e/access.log 2>/dev/null
  echo "########## ERROR LOG (lua only) ##########"
  grep -a "\[lua\]\|\[error\]" /app/.e2e/error.log | tail -40
} > /app/.e2e/result.txt 2>&1

kill $NGINX_PID 2>/dev/null
exit 0
