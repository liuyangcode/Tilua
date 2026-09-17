--- Path manipulation and file queries.
--
-- This is modelled after Python's os.path library (10.1).
--
-- Dependencies: `Tilua.utils.util` only.  **LuaFileSystem is optional.**
--
-- The module used to `error()` at require time when `lfs` was missing, which
-- made the whole framework unloadable on a stock `openresty/openresty` image —
-- that image ships no `lfs.so`, despite LuaFileSystem being widely described as
-- "bundled with OpenResty".  `lfs` is now used when present and a pure
-- `io`/`os` implementation takes over otherwise.
--
-- What the fallback can and cannot do:
--   * file/directory existence, size  -- pure io, always available
--   * modification time               -- `os.time` from the open file handle
--     (the view cache's staleness check depends on this)
--   * atime / ctime / symlink status  -- best effort, may be nil/false
--   * directory iteration (`path.dir`) -- needs `lfs`; nil otherwise
-- @module Tilua.utils.path

-- imports and locals
local _G = _G
local sub = string.sub
local getenv = os.getenv
local tmpnam = os.tmpname
local package = package
local append, concat, remove = table.insert, table.concat, table.remove
local utils = require 'Tilua.utils.util'
local split = require 'Tilua.utils.strings'.split

local path = {}

----------------------------------------------------------------------
-- filesystem backend (lfs when available, pure io/os otherwise)
----------------------------------------------------------------------

local ok_lfs, lfs = _G.pcall(_G.require, 'lfs')
if not ok_lfs then
    lfs = nil
end

--- Is LuaFileSystem driving the queries?  Diagnostics-only.
path.has_lfs = lfs ~= nil

--- Modification time for `p`, or nil.
---
--- Pure Lua has no portable way to read a file's mtime (`os.time` only accepts a
--- date table), so this shells out to `stat(1)` and falls back to `date -r`
--- (BSD/macOS form).  Returns nil when neither works rather than inventing a
--- value — a fabricated mtime would make the view cache look permanently fresh.
local function pure_mtime(p)
    local quoted = "'" .. tostring(p):gsub("'", "'\\''") .. "'"

    -- GNU coreutils: -c '%Y' = mtime as epoch seconds
    local f = io.popen("stat -c %Y " .. quoted .. " 2>/dev/null")
    if f then
        local out = f:read("*l")
        f:close()
        local t = tonumber(out)
        if t then
            return t
        end
    end

    -- BSD/macOS: -f %m = mtime as epoch seconds
    f = io.popen("stat -f %m " .. quoted .. " 2>/dev/null")
    if f then
        local out = f:read("*l")
        f:close()
        local t = tonumber(out)
        if t then
            return t
        end
    end

    return nil
end

--- Is `p` a directory?  (`io.open` succeeds on directories on Linux, so this
--- cannot be inferred from a successful open.)
local function pure_isdir(p)
    local ok = os.execute("test -d '" .. tostring(p):gsub("'", "'\\''") .. "' 2>/dev/null")
    return ok == true or ok == 0
end

--- Attribute lookup returning `field` (or the whole table).
---
--- Mirrors `lfs.attributes(p, field)`: returns nil when the path does not exist.
local function attrib(p, field)
    if type(p) ~= "string" or p == "" then
        return nil
    end

    if lfs then
        return lfs.attributes(p, field)
    end

    -- A trailing separator confuses io.open; keep it for the directory probe.
    local trimmed = p:gsub("[/\\]+$", "")
    if trimmed == "" then
        trimmed = "/"
    end

    local attr

    if pure_isdir(trimmed) then
        attr = {
            mode = "directory",
            modification = pure_mtime(trimmed),
            access = nil,
            change = nil,
            size = nil,
        }
    else
        -- Not a directory: it exists only if it opens as a regular file.
        local file = io.open(trimmed, "rb")
        if not file then
            return nil
        end
        local size = file:seek("end")
        file:close()

        attr = {
            mode = "file",
            modification = pure_mtime(trimmed),
            access = nil,
            change = nil,
            size = size,
        }
    end

    if field then
        return attr[field]
    end
    return attr
end

path.attrib = attrib
path.link_attrib = lfs and lfs.symlinkattributes or nil

--- Lua iterator over the entries of a given directory.
-- Behaves like `lfs.dir`. Requires LuaFileSystem; nil otherwise.
path.dir = lfs and lfs.dir or nil

--- Creates a directory.  Scoped to a single level like `lfs.mkdir`.
function path.mkdir(p)
    if lfs and lfs.mkdir then
        return lfs.mkdir(p)
    end
    local ok = os.execute("mkdir '" .. tostring(p):gsub("'", "'\\''") .. "' 2>/dev/null")
    return ok == true or ok == 0
end

--- Removes a directory.
function path.rmdir(p)
    if lfs and lfs.rmdir then
        return lfs.rmdir(p)
    end
    local ok = os.execute("rmdir '" .. tostring(p):gsub("'", "'\\''") .. "' 2>/dev/null")
    return ok == true or ok == 0
end

---- Get the working directory.
function path.currentdir()
    if lfs and lfs.currentdir then
        return lfs.currentdir()
    end
    local f = io.popen("pwd 2>/dev/null")
    if not f then
        return "."
    end
    local dir = f:read("*l")
    f:close()
    return dir or "."
end

--- Changes the working directory.
function path.chdir(p)
    if lfs and lfs.chdir then
        return lfs.chdir(p)
    end
    return false, "path.chdir requires LuaFileSystem"
end


--- is this a directory?
-- @string P A file path
function path.isdir(P)
    if P:match("\\$") then
        P = P:sub(1, -2)
    end
    return attrib(P, 'mode') == 'directory'
end

--- is this a file?.
-- @string P A file path
function path.isfile(P)
    return attrib(P, 'mode') == 'file'
end

-- is this a symbolic link?
-- @string P A file path
function path.islink(P)
    if path.link_attrib then
        return path.link_attrib(P, 'mode') == 'link'
    else
        return false
    end
end

--- return size of a file.
-- @string P A file path
function path.getsize(P)
    return attrib(P, 'size')
end

--- does a path exist?.
-- @string P A file path
-- @return the file path if it exists, nil otherwise
function path.exists(P)
    -- Explicitly return nil rather than the boolean from `a ~= nil and P`,
    -- which yielded `false` for a missing path despite the documented contract.
    if attrib(P, 'mode') == nil then
        return nil
    end
    return P
end

--- Return the time of last access as the number of seconds since the epoch.
-- @string P A file path
function path.getatime(P)
    return attrib(P, 'access')
end

--- Return the time of last modification
-- @string P A file path
function path.getmtime(P)
    return attrib(P, 'modification')
end

---Return the system's ctime.
-- @string P A file path
function path.getctime(P)
    return path.attrib(P, 'change')
end

local function at(s, i)
    return sub(s, i, i)
end

path.is_windows = utils.is_windows

local other_sep
-- !constant sep is the directory separator for this platform.
if path.is_windows then
    path.sep = '\\';
    other_sep = '/'
    path.dirsep = ';'
else
    path.sep = '/'
    path.dirsep = ':'
end
local sep = path.sep

--- are we running Windows?
-- @class field
-- @name path.is_windows

--- path separator for this platform.
-- @class field
-- @name path.sep

--- separator for PATH for this platform
-- @class field
-- @name path.dirsep

--- given a path, return the directory part and a file part.
-- if there's no directory part, the first value will be empty
-- @string P A file path
function path.splitpath(P)
    local i = #P
    local ch = at(P, i)
    while i > 0 and ch ~= sep and ch ~= other_sep do
        i = i - 1
        ch = at(P, i)
    end
    if i == 0 then
        return '', P
    else
        return sub(P, 1, i - 1), sub(P, i + 1)
    end
end

--- return an absolute path.
-- @string P A file path
-- @string[opt] pwd optional start path to use (default is current dir)
function path.abspath(P, pwd)
    local use_pwd = pwd ~= nil
    P = P:gsub('[\\/]$', '')
    pwd = pwd or path.currentdir()
    if not path.isabs(P) then
        P = path.join(pwd, P)
    elseif path.is_windows and not use_pwd and at(P, 2) ~= ':' and at(P, 2) ~= '\\' then
        P = pwd:sub(1, 2) .. P -- attach current drive to path like '\\fred.txt'
    end
    return path.normpath(P)
end

--- given a path, return the root part and the extension part.
-- if there's no extension part, the second value will be empty
-- @string P A file path
-- @treturn string root part
-- @treturn string extension part (maybe empty)
function path.splitext(P)
    local i = #P
    local ch = at(P, i)
    while i > 0 and ch ~= '.' do
        if ch == sep or ch == other_sep then
            return P, ''
        end
        i = i - 1
        ch = at(P, i)
    end
    if i == 0 then
        return P, ''
    else
        return sub(P, 1, i - 1), sub(P, i)
    end
end

--- return the directory part of a path
-- @string P A file path
function path.dirname(P)
    local p1 = path.splitpath(P)
    return p1
end

--- return the file part of a path
-- @string P A file path
function path.basename(P)
    local _, p2 = path.splitpath(P)
    return p2
end

--- get the extension part of a path.
-- @string P A file path
function path.extension(P)
    local _, p2 = path.splitext(P)
    return p2
end

--- is this an absolute path?.
-- @string P A file path
function path.isabs(P)
    if path.is_windows then
        return at(P, 1) == '/' or at(P, 1) == '\\' or at(P, 2) == ':'
    else
        return at(P, 1) == '/'
    end
end

--- return the path resulting from combining the individual paths.
-- if the second (or later) path is absolute, we return the last absolute path (joined with any non-absolute paths following).
-- empty elements (except the last) will be ignored.
-- @string p1 A file path
-- @string p2 A file path
-- @string ... more file paths
function path.join(p1, p2, ...)
    if select('#', ...) > 0 then
        local p = path.join(p1, p2)
        local args = { ... }
        for i = 1, #args do
            p = path.join(p, args[i])
        end
        return p
    end
    if path.isabs(p2) then
        return p2
    end
    local endc = at(p1, #p1)
    if endc ~= path.sep and endc ~= other_sep and endc ~= "" then
        p1 = p1 .. path.sep
    end
    return p1 .. p2
end

--- normalize the case of a pathname. On Unix, this returns the path unchanged;
--  for Windows, it converts the path to lowercase, and it also converts forward slashes
-- to backward slashes.
-- @string P A file path
function path.normcase(P)
    if path.is_windows then
        return (P:lower():gsub('/', '\\'))
    else
        return P
    end
end

--- normalize a path name.
--  `A//B`, `A/./B`, and `A/foo/../B` all become `A/B`.
-- @string P a file path
function path.normpath(P)
    -- Split path into anchor and relative path.
    local anchor = ''
    if path.is_windows then
        if P:match '^\\\\' then
            -- UNC
            anchor = '\\\\'
            P = P:sub(3)
        elseif at(P, 1) == '/' or at(P, 1) == '\\' then
            anchor = '\\'
            P = P:sub(2)
        elseif at(P, 2) == ':' then
            anchor = P:sub(1, 2)
            P = P:sub(3)
            if at(P, 1) == '/' or at(P, 1) == '\\' then
                anchor = anchor .. '\\'
                P = P:sub(2)
            end
        end
        P = P:gsub('/', '\\')
    else
        -- According to POSIX, in path start '//' and '/' are distinct,
        -- but '///+' is equivalent to '/'.
        if P:match '^//' and at(P, 3) ~= '/' then
            anchor = '//'
            P = P:sub(3)
        elseif at(P, 1) == '/' then
            anchor = '/'
            P = P:match '^/*(.*)$'
        end
    end
    local parts = {}
    for part in P:gmatch('[^' .. sep .. ']+') do
        if part == '..' then
            if #parts ~= 0 and parts[#parts] ~= '..' then
                remove(parts)
            else
                append(parts, part)
            end
        elseif part ~= '.' then
            append(parts, part)
        end
    end
    P = anchor .. concat(parts, sep)
    if P == '' then
        P = '.'
    end
    return P
end

--- relative path from current directory or optional start point
-- @string P a path
-- @string[opt] start optional start point (default current directory)
function path.relpath (P, start)
    local split, min, append = split, math.min, table.insert
    P = path.abspath(P, start)
    start = start or path.currentdir()
    local compare
    if path.is_windows then
        P = P:gsub("/", "\\")
        start = start:gsub("/", "\\")
        compare = function(v)
            return v:lower()
        end
    else
        compare = function(v)
            return v
        end
    end
    local startl, Pl = split(start, sep), split(P, sep)
    local n = min(#startl, #Pl)
    if path.is_windows and n > 0 and at(Pl[1], 2) == ':' and Pl[1] ~= startl[1] then
        return P
    end
    local k = n + 1 -- default value if this loop doesn't bail out!
    for i = 1, n do
        if compare(startl[i]) ~= compare(Pl[i]) then
            k = i
            break
        end
    end
    local rell = {}
    for i = 1, #startl - k + 1 do
        rell[i] = '..'
    end
    if k <= #Pl then
        for i = k, #Pl do
            append(rell, Pl[i])
        end
    end
    return table.concat(rell, sep)
end


--- Replace a starting '~' with the user's home directory.
-- In windows, if HOME isn't set, then USERPROFILE is used in preference to
-- HOMEDRIVE HOMEPATH. This is guaranteed to be writeable on all versions of Windows.
-- @string P A file path
function path.expanduser(P)
    if at(P, 1) == '~' then
        local home = getenv('HOME')
        if not home then
            -- has to be Windows
            home = getenv 'USERPROFILE' or (getenv 'HOMEDRIVE' .. getenv 'HOMEPATH')
        end
        return home .. sub(P, 2)
    else
        return P
    end
end


---Return a suitable full path to a new temporary file name.
-- unlike os.tmpname(), it always gives you a writeable path (uses TEMP environment variable on Windows)
function path.tmpname ()
    local res = tmpnam()
    -- On Windows if Lua is compiled using MSVC14 os.tmpname
    -- already returns an absolute path within TEMP env variable directory,
    -- no need to prepend it.
    if path.is_windows and not res:find(':') then
        res = getenv('TEMP') .. res
    end
    return res
end

--- return the largest common prefix path of two paths.
-- @string path1 a file path
-- @string path2 a file path
function path.common_prefix (path1, path2)
    -- get them in order!
    if #path1 > #path2 then
        path2, path1 = path1, path2
    end
    local compare
    if path.is_windows then
        path1 = path1:gsub("/", "\\")
        path2 = path2:gsub("/", "\\")
        compare = function(v)
            return v:lower()
        end
    else
        compare = function(v)
            return v
        end
    end
    for i = 1, #path1 do
        if compare(at(path1, i)) ~= compare(at(path2, i)) then
            local cp = path1:sub(1, i - 1)
            if at(path1, i - 1) ~= sep then
                cp = path.dirname(cp)
            end
            return cp
        end
    end
    if at(path2, #path1 + 1) ~= sep then
        path1 = path.dirname(path1)
    end
    return path1
    --return ''
end

function path.get_module_path(...)
    local module = select(1, ...)
    if utils.is_array(module) then
        module = table.concat(module, '.')
    else
        module = table.concat({ ... }, '.')
    end
    local module_file, finded = path.package_path(module)
    if not module_file then
        return nil
    end
    return path.normpath(path.dirname(module_file))
end
--- Pure-Lua search of a package template list (`package.path` / `cpath`).
---
--- Exposed for tests: `path._searchpath_fallback` lets the suite verify this
--- implementation even on a LuaJIT that ships the C built-in.
---
--- Like the standard `package.searchpath`, the module name's dots are first
--- converted to the directory separator, so `Tilua.utils.util` is looked up as
--- `./Tilua/utils/util.lua`.  (Substituting the dotted name directly finds
--- nothing — that is exactly the bug this fallback had before it was tested.)
local function searchpath_fallback(name, template)
    if type(name) ~= "string" or type(template) ~= "string" then
        return nil, "bad argument to searchpath"
    end
    local file_name = name:gsub("%.", sep)
    local tried = {}
    for entry in template:gmatch("[^;]+") do
        local candidate = entry:gsub("%?", file_name)
        local f = io.open(candidate, "rb")
        if f then
            f:close()
            return candidate
        end
        tried[#tried + 1] = "\n\tno file '" .. candidate .. "'"
    end
    return nil, table.concat(tried)
end
path._searchpath_fallback = searchpath_fallback

--- Search a template list, preferring the runtime's optimized implementation.
---
--- `package.searchpath` is a Lua 5.2+ / LuaJIT feature that this project was
--- relying on implicitly.  It exists in OpenResty's LuaJIT but not in every
--- LuaJIT build, where a missing one made `App.path` — and therefore the whole
--- view engine — fail to resolve.
local function searchpath(name, template)
    if type(package.searchpath) == "function" then
        return package.searchpath(name, template)
    end
    return searchpath_fallback(name, template)
end
path._searchpath = searchpath

--- return the full path where a particular Lua module would be found.
-- Both package.path and package.cpath is searched, so the result may
-- either be a Lua file or a shared library.
-- @string mod name of the module
-- @return on success: path of module, lua or binary
-- @return on error: nil,error string
function path.package_path(mod)
    local errs = {}

    for _, candidate in ipairs({
        { mod, package.path,  true  },   -- Lua source
        { mod, package.cpath, false },   -- shared library
    }) do
        local name, template, is_lua = candidate[1], candidate[2], candidate[3]
        if template and template ~= "" then
            local res, serr = searchpath(name, template)
            if res then
                return res, is_lua
            end
            if serr then
                errs[#errs + 1] = serr
            end
        end
    end

    return nil, "cannot find module '" .. tostring(mod) .. "' on package.path/cpath"
        .. table.concat(errs)
end

---- finis -----
return path
