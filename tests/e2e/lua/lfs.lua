--- Minimal LuaFileSystem stand-in for the end-to-end test only.
--- Tilua.utils.path hard-errors without it (see docs/ANALYSIS.md 5.3);
--- a real deployment must install LuaFileSystem.
local lfs = {}

local function q(path)
    return "'" .. tostring(path):gsub("'", "'\\''") .. "'"
end

--- Run a shell test, returning true when it succeeds.
local function shell_ok(cmd)
    local ok = os.execute(cmd)
    -- LuaJIT/Lua 5.1 return the raw exit status; 5.2+ return true/false.
    if ok == true then
        return true
    end
    if type(ok) == "number" then
        return ok == 0
    end
    return false
end

local function is_dir(path)
    if type(path) ~= "string" or path == "" then
        return false
    end
    -- trailing slash is meaningful to `test -d` only on some shells
    local p = path:gsub("/+$", "")
    if p == "" then
        p = "/"
    end
    return shell_ok("test -d " .. q(p))
end

local function is_file(path)
    if type(path) ~= "string" or path == "" then
        return false
    end
    return shell_ok("test -f " .. q(path))
end

--- mode: "file" | "directory" | nil
function lfs.attributes(path, what)
    if type(path) ~= "string" or path == "" then
        return nil
    end

    local attr
    if is_dir(path) then
        attr = { mode = "directory", size = 0 }
    elseif is_file(path) then
        attr = { mode = "file", size = 0 }
    else
        return nil
    end

    if what then
        return attr[what]
    end
    return attr
end

function lfs.currentdir()
    local f = io.popen("pwd")
    if not f then
        return "."
    end
    local d = f:read("*l") or "."
    f:close()
    return d
end

function lfs.mkdir(path)
    return shell_ok("mkdir -p " .. q(path))
end

function lfs.rmdir(path)
    shell_ok("rmdir " .. q(path) .. " 2>/dev/null")
    return true
end

function lfs.chdir()
    return true
end

--- Directory iterator, like the real lfs.dir (includes "." and "..").
function lfs.dir(path)
    local names = {}
    local f = io.popen("ls -a " .. q(path) .. " 2>/dev/null")
    if f then
        for line in f:lines() do
            names[#names + 1] = line
        end
        f:close()
    end
    local i = 0
    return function()
        i = i + 1
        return names[i]
    end
end

function lfs.symlinkattributes()
    return nil
end

function lfs.touch(path)
    shell_ok("touch " .. q(path))
    return true
end

return lfs
