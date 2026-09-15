# Tilua Deployment Guide

## Requirements

- OpenResty
- LuaJIT
- Tilua runtime dependencies

## Production Layout

```
Tilua/
├── lua/
├── nginx/
├── cli/
├── tests/
└── docs/
```

## Nginx Configuration

```nginx
lua_package_path '$prefix/../lua/?.lua;$prefix/../lualib/?.lua;;';
lua_shared_dict app_cache 10m;

server {
    listen 8001;

    location / {
        content_by_lua_block {
            require "app"():run()
        }
    }
}
```

## Start

```bash
nginx -t
nginx -s reload
```

## Verification

```bash
tilua doctor
tilua test --production
tilua health
```
