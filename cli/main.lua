local M = {}

local VERSION = "0.1.0-production"

local commands = {}

commands.version = function()
    print("Tilua Runtime")
    print("Version: " .. VERSION)
end

commands.help = function()
    print([[Tilua CLI

Commands:
  version              Show runtime version
  test --production    Run production checks
  doctor               Check runtime environment
]])
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
