# Dockerfile for the Hello example.
#
# Build from the REPOSITORY ROOT (see docker-compose.yml, which sets the
# context to ../..).  The framework and the example both have to live under the
# nginx prefix, and nginx.conf addresses them with paths relative to it.
#
#   docker build -f examples/hello/Dockerfile -t tilua-hello .
#   docker run --rm -p 8080:8080 tilua-hello
#
# No LuaFileSystem or lua-resty-jit-uuid needed: the framework ships pure-Lua
# fallbacks for both, so a stock openresty image is enough.

FROM openresty/openresty:1.21.4.1-buster

WORKDIR /app

# The framework.
COPY Tilua/ /app/Tilua/

# This example (its app directory must sit at /app/examples/hello/Hello).
COPY examples/hello/nginx.conf /app/examples/hello/nginx.conf
COPY examples/hello/Hello/     /app/examples/hello/Hello/

# nginx needs these to exist before it starts.
RUN mkdir -p /app/logs /app/examples/hello/logs

EXPOSE 8080

# `-p` is the prefix the relative paths in nginx.conf resolve against.
CMD ["nginx", "-p", "/app", "-c", "examples/hello/nginx.conf"]
