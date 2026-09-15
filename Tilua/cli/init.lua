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
        local caches = app.route and app.route.get_route_caches and app.route.get_route_caches(app.name)
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
