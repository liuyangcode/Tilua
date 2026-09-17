--- bin/tilua.lua
--- Lua entry point for the Tilua CLI. Invoked by ./bin/tilua.
---
--- Kept separate from the shell wrapper because `luajit -e` does not accept
--- trailing `-- args` the way a script file does: with `-e` the arguments land
--- in `arg` at offset 0 with a `--` entry at index -1, which is awkward and
--- fragile.  A real script file gets a clean 1-based `arg` table.

local ROOT   = os.getenv("TILUA_ROOT")
local LUALIB = os.getenv("TILUA_LUALIB") or "/usr/local/openresty/lualib"

if not ROOT or ROOT == "" then
    io.stderr:write("tilua: TILUA_ROOT is not set (see bin/tilua)\n")
    os.exit(1)
end

package.path = ROOT .. "/?.lua;" .. ROOT .. "/?/init.lua;"
    .. LUALIB .. "/?.lua;" .. LUALIB .. "/?/init.lua;" .. package.path
package.cpath = LUALIB .. "/?.so;" .. package.cpath

--- Minimal `ngx` for CLI use.
---
--- Tilua touches `ngx` while modules are being required, so a bare LuaJIT cannot
--- load the framework at all.  CLI commands never enter an HTTP phase, so only
--- require-time table access and a couple of helpers are needed.
--- (`resty` would provide this, but the stock openresty/openresty image does not
--- ship the `resty` CLI.)
local function install_ngx_shim()
    if rawget(_G, "ngx") then
        return
    end
    _G.ngx = {
        now = os.time,
        time = os.time,
        update_time = function() end,
        log = function() end,
        print = function(...) io.write(...) end,
        say = function(...) io.write(table.concat({ ... }, "\t"), "\n") end,
        -- subsystem = nil marks "not running inside nginx" for the CLI channel
        config = { subsystem = nil },
        re = {
            match = function() return nil end,
            find = function() return nil end,
            gsub = function(s) return s end,
            sub = function(s) return s end,
            escape = function(s) return s end,
        },
        var = {},
        ctx = {},
        header = {},
        shared = {},
        worker = { pid = function() return 0 end },
        req = {},
        resp = {},
        timer = {},
    }
end

install_ngx_shim()

local ok, CLI = pcall(require, "Tilua.cli")
if not ok then
    io.stderr:write("tilua: cannot load Tilua.cli from " .. ROOT .. "\n")
    io.stderr:write("       " .. tostring(CLI) .. "\n")
    os.exit(1)
end

local App = require("Tilua.app")

-- `arg[0]` is the script path; commands start at index 1.
local args = {}
for i = 1, #arg do
    args[i] = arg[i]
end

-- Run from the user's cwd (not the framework root) so `doctor`, `new` and
-- `serve --root .` resolve against the project the user is standing in.
local rc = CLI.run(App, args)
os.exit(tonumber(rc) or 0)
