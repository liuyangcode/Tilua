--- Tilua.cli (interface stub)
--- Run application commands outside the HTTP cycle.
---
--- Enable: config.plugins = { "Tilua.cli" }
--- Entry (standalone):
---   local App = require("myapp")
---   require("Tilua.cli").run(App, arg)

local CLI = {
    name = "cli",
    priority = 90,
    _commands = {},
}

function CLI.new(app)
    return CLI
end

function CLI.register(app)
    -- register built-in commands
    CLI.command("routes", function(app)
        local router = app:make("router")
        local caches = router.get_route_caches and router.get_route_caches(app.name)
        if not caches then
            print("no routes")
            return
        end
        for _, r in ipairs(caches) do
            local methods = type(r.method) == "table" and table.concat(r.method, ",") or tostring(r.method)
            print(string.format("%-12s %-6s %s", methods, r.matcher or "", r.path or ""))
        end
    end, "List registered routes")

    CLI.command("version", function()
        local v = "unknown"
        local f = io.open("VERSION", "r")
        if f then
            v = f:read("*l") or v
            f:close()
        end
        print("Tilua " .. v)
    end, "Show version")

    CLI.command("doctor", CLI.doctor, "Check environment, config and dependencies")
    CLI.command("serve", CLI.serve, "Run a local OpenResty dev server")
    CLI.command("new", CLI.new_project, "Scaffold a new Tilua project")
end

--- Parse `--flag value` / `--flag=value` / `--bool` out of an argument list.
--- Returns (flags, positionals) so commands can accept both styles.
local function parse_flags(args)
    local flags, rest = {}, {}
    local i = 1
    while i <= #(args or {}) do
        local a = args[i]
        local k, v = a:match("^%-%-([%w_%-]+)=(.*)$")
        if k then
            flags[k] = v
        elseif a:match("^%-%-[%w_%-]+$") then
            k = a:sub(3)
            local nxt = args[i + 1]
            if nxt and not nxt:match("^%-%-") then
                flags[k] = nxt
                i = i + 1
            else
                flags[k] = true
            end
        else
            rest[#rest + 1] = a
        end
        i = i + 1
    end
    return flags, rest
end

--- Best-effort write check: create the dir if missing, try to drop a temp
--- file in it, clean up either way.
local function check_writable(dir)
    if not dir or dir == "" then
        return true, "not configured"
    end
    os.execute("mkdir -p '" .. dir:gsub("'", "'\\''") .. "' 2>/dev/null")
    local probe = dir .. "/.tilua_doctor_" .. tostring(ngx and ngx.now and ngx.now() or os.time())
    local f = io.open(probe, "w")
    if not f then
        return false, "cannot write to " .. dir
    end
    f:close()
    os.remove(probe)
    return true
end

--- `tilua doctor` — surface environment/config problems *before* they show up
--- as a confusing runtime error (missing resty module, unwritable log dir,
--- wrong Lua interpreter, stale VERSION file, …).
function CLI.doctor(app)
    local checks, fail = {}, 0

    local function check(name, fn)
        local ok, detail = fn()
        checks[#checks + 1] = { name = name, ok = ok, detail = detail }
        if not ok then fail = fail + 1 end
    end

    local function check_module(mod, why)
        check(mod, function()
            if pcall(require, mod) then return true end
            return false, why or ("require(\"" .. mod .. "\") failed - is it installed?")
        end)
    end

    check("LuaJIT runtime", function()
        if jit then return true, jit.version end
        return false, "OpenResty requires LuaJIT; this looks like stock Lua"
    end)

    check("OpenResty (ngx) available", function()
        if ngx and ngx.config then
            return true, ngx.config.nginx_version and ("nginx " .. ngx.config.nginx_version) or "ok"
        end
        return false, "ngx not visible - run via the `resty` CLI or inside nginx for full checks"
    end)

    check_module("resty.jit-uuid", "needed by Tilua.utils.util")
    check_module("lfs", "needed by Tilua.utils.path (LuaFileSystem)")

    local ok_cfg, config = pcall(function() return app and app.config end)
    config = ok_cfg and config or nil

    if config then
        if config.data_cache_handler == "redis" then
            check_module("resty.redis", "config.data_cache_handler = \"redis\" but lua-resty-redis is missing")
        end
        if config.db_type == "mysql" then
            check_module("resty.mysql", "config.db_type = \"mysql\" but lua-resty-mysql is missing")
        end

        check("log directory writable", function()
            return check_writable(config.log and config.log.path)
        end)

        check("multipart tmpdir writable", function()
            return check_writable(config.multipart and config.multipart.tmpdir)
        end)
    else
        check("app config", function()
            return false, "could not resolve app.config - run doctor from your app entry point"
        end)
    end

    check("VERSION matches CHANGELOG", function()
        local vf = io.open("VERSION", "r")
        if not vf then return true, "no VERSION file, skipped" end
        local v = vf:read("*l"); vf:close()

        local cf = io.open("CHANGELOG.md", "r")
        if not cf then return true, "no CHANGELOG.md, skipped" end
        local top
        for line in cf:lines() do
            if line:match("^##%s*%[") then top = line; break end
        end
        cf:close()

        if v and top and top:find(v, 1, true) then return true end
        return false, string.format("VERSION=%s but CHANGELOG's latest entry is %s",
            v or "?", top or "?")
    end)

    print("Tilua doctor")
    print(string.rep("-", 46))
    for _, c in ipairs(checks) do
        print(string.format("[%s] %-28s %s", c.ok and "OK  " or "FAIL", c.name, c.detail or ""))
    end
    print(string.rep("-", 46))
    print(fail == 0 and "All checks passed." or (fail .. " check(s) failed."))

    return fail == 0 and 0 or 1
end

-----------------------------------------------------------------------
-- serve
-----------------------------------------------------------------------

local function shq(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function capture(cmd)
    local p = io.popen(cmd .. " 2>/dev/null")
    if not p then return nil end
    local out = p:read("*l")
    p:close()
    return out and out ~= "" and out or nil
end

--- Locate an OpenResty-flavoured nginx binary. A stock nginx without the
--- ngx_lua module cannot run Tilua, so prefer `openresty` and only fall back
--- to `nginx` if it reports an OpenResty build.
local function find_openresty()
    local bin = capture("command -v openresty")
    if bin then return bin end
    for _, guess in ipairs({
        "/usr/local/openresty/bin/openresty",
        "/opt/openresty/bin/openresty",
        "/usr/local/opt/openresty/bin/openresty",
    }) do
        local f = io.open(guess, "r")
        if f then f:close(); return guess end
    end
    local ngx_bin = capture("command -v nginx")
    if ngx_bin then
        local p = io.popen(shq(ngx_bin) .. " -v 2>&1")
        local banner = p and p:read("*a") or ""
        if p then p:close() end
        if banner:lower():find("openresty", 1, true) then
            return ngx_bin
        end
    end
    return nil
end

local function abspath(p)
    if p:sub(1, 1) == "/" then return p end
    local cwd = capture("pwd") or "."
    p = p:gsub("^%./", "")
    return (p == "." or p == "") and cwd or (cwd .. "/" .. p)
end

--- Guess the application module name: a directory under `root` containing
--- app.lua, ignoring the framework itself and dot-dirs.
local function detect_app_name(root)
    local p = io.popen("ls -1 " .. shq(root) .. " 2>/dev/null")
    if not p then return nil end
    local found
    for entry in p:lines() do
        if entry ~= "Tilua" and entry:sub(1, 1) ~= "." then
            local f = io.open(root .. "/" .. entry .. "/app.lua", "r")
            if f then
                f:close()
                if found then
                    p:close()
                    return nil, "multiple candidates (" .. found .. ", " .. entry .. ") - pass --app"
                end
                found = entry
            end
        end
    end
    p:close()
    if not found then
        return nil, "no <Name>/app.lua found under " .. root .. " - pass --app"
    end
    return found
end

--- Render a development nginx.conf. Deliberately dev-only: `daemon off` so
--- Ctrl-C works, single worker so print/log output is not interleaved, and
--- `lua_code_cache off` so edited Lua is picked up on the next request with
--- no reload. Phase hooks mirror the documented lifecycle
--- (init / init_worker / rewrite / access / content / log).
local function render_conf(o)
    return ([[
# Generated by `tilua serve` - DEVELOPMENT ONLY, do not deploy.
# Regenerated on every run; edit your app, not this file.
worker_processes 1;
daemon off;
error_log %s/error.log %s;
pid %s/nginx.pid;

events { worker_connections 256; }

http {
    access_log %s/access.log;
    client_body_temp_path %s/client_body;
    proxy_temp_path %s/proxy;
    fastcgi_temp_path %s/fastcgi;
    uwsgi_temp_path %s/uwsgi;
    scgi_temp_path %s/scgi;

    lua_package_path "%s/?.lua;%s/?/init.lua;;";
    # dev: pick up edited Lua without a reload
    lua_code_cache off;
    # `app_cache` is what `tilua new` scaffolds; `app_test_cache` is the
    # framework default for config.SHDICIT_NAME. Declare both so an app
    # using either value starts without editing this file.
    lua_shared_dict app_cache 10m;
    lua_shared_dict app_test_cache 10m;

    init_by_lua_block {
        require("%s.app"):init_by_lua()
    }

    init_worker_by_lua_block {
        require("%s.app"):init_worker_by_lua()
    }

    server {
        listen %s;
        server_name localhost;

        location ~* \.(css|js|jpg|jpeg|png|gif|ico|svg|woff2?)$ {
            root %s/public;
            expires -1;
        }

        location / {
            rewrite_by_lua_block { require("%s.app"):rewrite_by_lua() }
            access_by_lua_block  { require("%s.app"):access_by_lua()  }
            content_by_lua_block { require("%s.app"):content_by_lua() }
            log_by_lua_block     { require("%s.app"):log_by_lua()     }
        }
    }
}
]]):format(
        o.run_dir, o.log_level,
        o.run_dir,
        o.run_dir, o.run_dir, o.run_dir, o.run_dir, o.run_dir, o.run_dir,
        o.root, o.root,
        o.app_name,
        o.app_name,
        o.port,
        o.root,
        o.app_name, o.app_name, o.app_name, o.app_name
    )
end

--- `tilua serve` - boot a local OpenResty for development.
---
--- Generates a dev nginx.conf under <root>/.tilua/ and execs OpenResty in the
--- foreground. Nothing is installed and nothing outside .tilua/ is touched.
---
---   --port  N      listen port            (default 8001)
---   --app   Name   app module name        (default: autodetected)
---   --root  DIR    project root           (default: cwd)
---   --log   LEVEL  nginx error_log level  (default info)
---   --print-conf   write + print the conf, do not start anything
function CLI.serve(app, args)
    local flags = parse_flags(args)

    local root = abspath(flags.root or ".")
    local port = tonumber(flags.port) or 8001
    local log_level = flags.log or "info"

    local app_name = flags.app or (app and app.name)
    if not app_name then
        local detected, derr = detect_app_name(root)
        if not detected then
            print("tilua serve: " .. tostring(derr))
            return 1
        end
        app_name = detected
    end

    if not io.open(root .. "/" .. app_name .. "/app.lua", "r") then
        print(("tilua serve: %s/%s/app.lua not found (wrong --app or --root?)")
            :format(root, app_name))
        return 1
    end

    local run_dir = root .. "/.tilua"
    os.execute("mkdir -p " .. shq(run_dir) .. " " .. shq(run_dir .. "/logs"))

    local conf_path = run_dir .. "/dev.nginx.conf"
    local conf = render_conf({
        root = root, run_dir = run_dir, port = port,
        app_name = app_name, log_level = log_level,
    })

    local f, ferr = io.open(conf_path, "w")
    if not f then
        print("tilua serve: cannot write " .. conf_path .. " (" .. tostring(ferr) .. ")")
        return 1
    end
    f:write(conf)
    f:close()

    if flags["print-conf"] then
        print("# written to " .. conf_path .. "\n")
        print(conf)
        return 0
    end

    local bin = find_openresty()
    if not bin then
        print("tilua serve: no OpenResty binary found on PATH.")
        print("  Install OpenResty, or inspect the generated config with:")
        print("    tilua serve --print-conf")
        print("  Config was still written to: " .. conf_path)
        return 1
    end

    print(("Tilua dev server: http://localhost:%d  (app=%s)"):format(port, app_name))
    print("  config : " .. conf_path)
    print("  logs   : " .. run_dir .. "/error.log")
    print("  binary : " .. bin)
    print("  lua_code_cache is off - edited Lua is picked up on the next")
    print("  request; only nginx.conf changes need a restart.")
    print("  Ctrl-C to stop.\n")

    -- `-p root` so relative paths inside the app resolve against the project.
    local cmd = ("exec %s -p %s -c %s"):format(shq(bin), shq(root), shq(conf_path))
    local ok, how, code = os.execute(cmd)
    if ok == true or ok == 0 then return 0 end
    return tonumber(code) or 1
end

-----------------------------------------------------------------------
-- new (scaffold)
-----------------------------------------------------------------------

--- Write `content` to `path`, creating parent directories. Refuses to
--- clobber an existing file.
local function write_new(path, content)
    local dir = path:match("^(.*)/[^/]+$")
    if dir then
        os.execute("mkdir -p " .. shq(dir))
    end
    if io.open(path, "r") then
        return false, "exists"
    end
    local f, err = io.open(path, "w")
    if not f then
        return false, tostring(err)
    end
    f:write(content)
    f:close()
    return true
end

--- Scaffold file set. Each entry is {relative path, content}; `%s` slots are
--- filled with the application name.
---
--- The conventions encoded here are the *current* ones, verified against the
--- framework source rather than the older README examples:
---   * `Tilua.app.define()` (there is no `derive()`)
---   * `name` / `status` / `debug` are class fields, because the base
---     constructor reads them before an instance exists
---   * routes come from `Tilua.http.router`, responses from
---     `Tilua.http.response`
---   * MVC controllers live at `<App>/controller/<name>.lua`
---   * views live at `<App>/view/<name>.html`
local function scaffold_files(name)
    local files = {}
    local function add(p, c) files[#files + 1] = { p, c } end

    add(name .. "/app.lua", ([[
--- %s application entry point.

local App = require("Tilua.app").define()

--- These are class fields on purpose: Tilua's base constructor reads
--- `name` / `status` / `debug` while building the instance, so setting them
--- inside `_construct` would be too late.
---   name   must match the require path (this directory)
---   status selects config/<status>.lua
App.name   = "%s"
App.status = "dev"
App.debug  = true

--- Register application-owned services here. Runs after the framework's
--- own bindings, so you can override them.
function App:_construct(opts)
    -- self:singleton("clock", function(c) return { now = ngx.now } end)
    return self
end

return App
]]):format(name, name))

    add(name .. "/routes.lua", ([[
--- %s routes.
---
--- Handlers may return:
---   a response object   -> sent as-is
---   a string            -> sent as plain text
---   a table             -> encoded as JSON
---   (view_name, table)  -> renders view/<view_name>.html
local route    = require("Tilua.http.router")
local response = require("Tilua.http.response")

route.get("/", function()
    return "index", {
        app_name = "%s",
        message  = "Your Tilua app is running.",
    }
end)

route.get("/hello/{name}", function(ctx, name)
    return response("Hello, " .. tostring(name) .. "!")
end)

route.get("/api/ping", function()
    return { pong = true }
end)
]]):format(name, name))

    add(name .. "/config/dev.lua", [[
--- Development config. Merged over Tilua/config/default.lua.
--- Create config/prod.lua and set App.status = "prod" for production.
return {
    app_title = "Tilua app",

    -- stderr keeps `tilua serve` output in one place and needs no writable
    -- log directory to start.
    log = { type = "stderr", level = "DEBUG" },

    -- The framework default enables an HTML cache and a Redis-backed data
    -- cache. Both are off here so a fresh project runs with no external
    -- services; turn them on when you actually need them.
    html_cache = false,

    -- Must match a lua_shared_dict declared in nginx.conf.
    -- `tilua serve` declares this one for you.
    SHDICIT_NAME = "app_cache",

    route = {},

    -- Middleware run in the content phase unless listed under another phase.
    middleware_phases = {
        access  = {},
        content = { "body_parser" },
    },
}
]])

    add(name .. "/controller/index.lua", [[
--- Classic MVC controller, reachable at /index/<action>.
--- Resolution is <App>/controller/<controller>.lua, action = 2nd path segment
--- (defaults to "index"). Enable the "mvc" middleware in config to use these.
local controller = require("Tilua.controller")

local Index = controller.define()

function Index:index(request)
    return "hello from the index controller"
end

return Index
]])

    add(name .. "/view/index.html", [[
<!doctype html>
<html>
<head>
    <meta charset="utf-8">
    <title>{{ app_name }}</title>
</head>
<body>
    <h1>{{ app_name }}</h1>
    <p>{{ message }}</p>
    <p>Try <a href="/hello/world">/hello/world</a> or
       <a href="/api/ping">/api/ping</a>.</p>
</body>
</html>
]])

    add("public/.gitkeep", "")

    add(".gitignore", [[
# tilua serve scratch dir (generated nginx.conf, pid, logs)
.tilua/
]])

    add("README.md", ([[
# %s

A [Tilua](https://github.com/liuyangcode/Tilua) application.

## Run

```bash
tilua doctor   # check OpenResty and dependencies
tilua serve    # http://localhost:8001
```

`tilua serve` runs with `lua_code_cache off`, so edited Lua is picked up on
the next request. Only nginx.conf changes need a restart.

## Layout

```
%s/
  app.lua            application entry (name / status / debug, services)
  routes.lua         route definitions
  config/dev.lua     config for status = "dev"
  controller/        classic MVC controllers
  view/              templates rendered by Tilua.template
public/              static files
```
]]):format(name, name))

    return files
end

--- `tilua new <Name>` - generate a runnable project skeleton.
---
---   --dir DIR     where to create it (default: ./<Name>)
---   --force       write into a non-empty directory
function CLI.new_project(app, args)
    local flags, rest = parse_flags(args)
    local name = rest[1]

    if not name then
        print("usage: tilua new <Name> [--dir DIR] [--force]")
        return 1
    end
    if not name:match("^[%a_][%w_]*$") then
        print("tilua new: '" .. name .. "' is not a valid module name")
        print("  use letters, digits and underscores, starting with a letter")
        return 1
    end

    local dir = abspath(flags.dir or ("./" .. name))

    local probe = io.popen("ls -A " .. shq(dir) .. " 2>/dev/null")
    local nonempty = probe and probe:read("*l") ~= nil
    if probe then probe:close() end
    if nonempty and not flags.force then
        print("tilua new: " .. dir .. " is not empty (use --force to write into it)")
        return 1
    end

    os.execute("mkdir -p " .. shq(dir))

    local written, skipped = {}, {}
    for _, entry in ipairs(scaffold_files(name)) do
        local rel, content = entry[1], entry[2]
        local ok, why = write_new(dir .. "/" .. rel, content)
        if ok then
            written[#written + 1] = rel
        else
            skipped[#skipped + 1] = rel .. " (" .. why .. ")"
        end
    end

    print("Created " .. name .. " in " .. dir)
    for _, rel in ipairs(written) do
        print("  + " .. rel)
    end
    if #skipped > 0 then
        print("  skipped (already present):")
        for _, s in ipairs(skipped) do print("    - " .. s) end
    end
    print("\nNext:")
    print("  cd " .. dir)
    print("  tilua serve")

    return 0
end

function CLI.command(name, handler, help)
    CLI._commands[name] = { handler = handler, help = help or "" }
end

function CLI.handle(app, args)
    args = args or {}
    local name = args[1] or "help"
    if name == "help" or name == "--help" then
        print("Tilua CLI commands:")
        local names = {}
        for n in pairs(CLI._commands) do names[#names + 1] = n end
        table.sort(names)
        for _, n in ipairs(names) do
            print(string.format("  %-16s %s", n, CLI._commands[n].help))
        end
        return 0
    end
    local cmd = CLI._commands[name]
    if not cmd then
        print("unknown command: " .. tostring(name))
        return 1
    end
    local a = {}
    for i = 2, #args do
        a[#a + 1] = args[i]
    end
    return cmd.handler(app, a)
end

--- Standalone entry: boots app in CLI mode and runs command
function CLI.run(AppClass, args)
    args = args or arg or {}
    local app = AppClass()
    app._channel = "cli"
    app._cli = true
    app._cli_args = args
    if type(app.init_by_lua) == "function" then
        -- minimal boot without ngx phases when possible
        pcall(function()
            app:load_config()
            app:load_route()
        end)
    end
    local Plugin = require("Tilua.core.plugin")
    Plugin.register(CLI)
    CLI.register(app)
    Plugin.boot(app)
    return CLI.handle(app, args)
end

CLI.hooks = {
    on_boot = function(app)
        -- no-op
    end,
}

return CLI
