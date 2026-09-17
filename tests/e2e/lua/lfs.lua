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

--- Real metadata via `stat(1)`.
---
--- The earlier version returned only `mode`/`size` and hard-coded the size to
--- 0, which made `path.getmtime` (i.e. `attributes(P, "modification")`) return
--- *nil for every path that exists*.  View rendering treats a nil mtime as
--- "template missing" (`view.lua:51`), so the e2e `/view` case reported a 500
--- that a real LuaFileSystem never would have produced.  A stub that is wrong
--- in the same direction as the code under test is worse than no stub, so read
--- the timestamps from the filesystem for real.
---
--- `stat -c` is the GNU coreutils form; the OpenResty (Debian) image has it.
local function stat_fields(path)
    if type(path) ~= "string" or path == "" then
        return nil
    end
    -- %F file type, %s size, %X atime, %Y mtime, %Z ctime
    local f = io.popen("stat -c '%F|%s|%X|%Y|%Z' " .. q(path) .. " 2>/dev/null")
    if not f then
        return nil
    end
    local line = f:read("*l")
    f:close()
    if not line or line == "" then
        return nil
    end
    local ftype, size, atime, mtime, ctime = line:match("^(.-)|(%d+)|(%d+)|(%d+)|(%d+)$")
    if not ftype then
        return nil
    end
    return ftype, tonumber(size), tonumber(atime), tonumber(mtime), tonumber(ctime)
end

--- mode: "file" | "directory" | "link" | "other" | nil
function lfs.attributes(path, what)
    local ftype, size, atime, mtime, ctime = stat_fields(path)
    if not ftype then
        return nil
    end

    local mode
    if ftype == "directory" then
        mode = "directory"
    elseif ftype == "regular file" or ftype == "regular empty file" then
        mode = "file"
    elseif ftype == "symbolic link" then
        mode = "link"
    else
        mode = "other"
    end

    local attr = {
        mode       = mode,
        size       = size,
        access     = atime,
        modification = mtime,
        change     = ctime,
        -- `lfs.attributes` normally also reports permissions/nlink/uid/gid;
        -- nothing in Tilua reads them, so they are omitted rather than faked.
    }

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
