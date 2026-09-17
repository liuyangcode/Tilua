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

function CLI.command(name, handler, help)
    CLI._commands[name] = { handler = handler, help = help or "" }
end

function CLI.handle(app, args)
    args = args or {}
    local name = args[1] or "help"
    if name == "help" or name == "--help" then
        print("Tilua CLI commands:")
        for n, c in pairs(CLI._commands) do
            print(string.format("  %-16s %s", n, c.help))
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
