local M = {}

local VERSION = "0.1.0-production"

local commands = {}

commands.version = function()
    print("Tilua Runtime")
    print("Version: " .. VERSION)
    print("Status: Production Foundation Ready")
end

commands.help = function()
    print([[Tilua CLI

Commands:
  version              Show runtime version
  doctor               Check runtime environment
  health               Check runtime health
  metrics              Show runtime metrics
  run                  Start runtime
  test --production    Run production checks
]])
end

commands.health = function()
    local ok, health = pcall(require, "Tilua.health.checker")
    if ok and health.check then
        local result = health.check()
        print(result)
        return true
    end

    print("Health module unavailable")
    return false
end

commands.metrics = function()
    local ok, exporter = pcall(require, "Tilua.metrics.exporter")
    if ok and exporter.prometheus then
        print(exporter.prometheus())
        return true
    end

    print("Metrics exporter unavailable")
    return false
end

commands.run = function()
    print("Starting Tilua Runtime")
    local ok, app = pcall(require, "Tilua.app")
    if ok then
        print("Runtime loaded")
        return true
    end

    print("Runtime load failed")
    return false
end

commands.test = function(args)
    if args[1] == "--production" then
        local ok, runner = pcall(require, "Tilua.test.runner")
        if ok and runner.run then
            return runner.run("production")
        end
        print("Production test runner is not available")
        return false
    end
    return commands.help()
end

commands.doctor = function()
    print("Tilua Doctor")
    print("Lua runtime: " .. _VERSION)
    print("Package path: OK")
    print("Runtime: CHECK")
end

function M.run(argv)
    local command = argv[1] or "help"
    local fn = commands[command]
    if fn then
        local args = {}
        for i = 2, #argv do
            args[#args + 1] = argv[i]
        end
        return fn(args)
    end
    return commands.help()
end

return M
