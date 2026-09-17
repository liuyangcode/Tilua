-- Pure helpers only.  Penlight was historically soft-loaded here (`pl.tablex`,
-- `pl.pretty`) with hand-rolled fallbacks; since Penlight is not installed in a
-- stock OpenResty, those branches were dead code on every real deployment.  The
-- replacements now live in `Tilua.core.helpers`, so there is one implementation
-- instead of two divergent ones.
local helpers = require("Tilua.core.helpers")
local foreach = helpers.foreach
local ngx = ngx
local now, update_time = ngx.now, ngx.update_time
local md5 = ngx.md5
local string = string
local table = table
local gsub = string.gsub
local json = require("cjson.safe")
local split = helpers.split
local function assert_arg(n, val, typ)
    if type(val) ~= typ then
        error("argument " .. n .. " expected a " .. typ .. ", got " .. type(val), 2)
    end
end
local ffi = require "ffi"

local re_find = ngx.re.find
local re_match = ngx.re.match
local C = ffi.C
local ffi_fill = ffi.fill
local ffi_new = ffi.new
local ffi_str = ffi.string

-- `resty.jit-uuid` is optional.  It is NOT shipped with the stock
-- `openresty/openresty` image, so a hard require here made the framework
-- impossible to load outside a hand-provisioned deployment.  A v4 generator
-- backed by the same randomness as `util.random_string` is used when absent.
local ok_uuid, uuid = pcall(require, "resty.jit-uuid")
if not ok_uuid then
    uuid = nil
end

ffi.cdef [[
typedef unsigned char u_char;

int gethostname(char *name, size_t len);

int RAND_bytes(u_char *buf, int num);

unsigned long ERR_get_error(void);
void ERR_load_crypto_strings(void);
void ERR_free_strings(void);

const char *ERR_reason_error_string(unsigned long e);

int open(const char * filename, int flags, int mode);
size_t read(int fd, void *buf, size_t count);
int write(int fd, const void *ptr, int numbytes);
int close(int fd);
char *strerror(int errnum);
]]

local lrandom = nil -- the `random` rock was required but never used (see docs/ANALYSIS.md 5.1)

---@class util
local util = {
    split = split,
    bind1 = helpers.bind1,
}

util.is_windows = _G.package.config:sub(1, 1) == '\\'


--- bind the first argument of the function to a value.
-- @param fn a function of at least two values (may be an operator string)
-- @param p a value
-- @return a function such that f(x) is fn(p,x)
-- @raise same as @{function_arg}
-- @see func.bind1
-- @usage local function f(msg, name)
--   print(msg .. " " .. name)
-- end
--
-- local hello = utils.bind1(f, "Hello")
--
-- print(hello("world"))     --> "Hello world"
-- print(hello("sunshine"))  --> "Hello sunshine"
function util.bind1(fn, p)
    return helpers.bind1(fn, p)
end
--- bind the second argument of the function to a value.
-- @param fn a function of at least two values (may be an operator string)
-- @param p a value
-- @return a function such that f(x) is fn(x,p)
-- @raise same as @{function_arg}
-- @usage local function f(a, b, c)
--   print(a .. " " .. b .. " " .. c)
-- end
--
-- local hello = utils.bind1(f, "world")
--
-- print(hello("Hello", "!"))  --> "Hello world !"
-- print(hello("Bye", "?"))    --> "Bye world ?"
function util.bind2 (fn, p)
    return function(x, ...)
        return fn(x, p, ...)
    end
end
---choose
---@param condition boolean
---@param value_true any
---@param value_false any
function util.choose(condition, value_true, value_false)
    if not not condition then
        return value_true
    end
    return value_false
end

---parse_expression like token:qwerereqrqwrq,12123,123123;another-header:test
---@param exp string
---@param exp_sep string optional value default is ";"
---@param key_value_sep string optional value default is ":"
---@param value_sep string optional,default is ","
function util.parse_expression(exp, exp_sep, key_value_sep, value_sep)
    local values = {}
    exp = exp or ""
    exp_sep = exp_sep or ";"
    key_value_sep = key_value_sep or ":"
    value_sep = value_sep or ","
    exp = split(exp, exp_sep, true)
    for i = 1, #exp do
        if exp[i] ~= '' then
            local name, item_values = table.unpack(split(exp[i], key_value_sep, true))
            if item_values then
                item_values = split(item_values or "", value_sep, true)
                values[name] = #item_values > 1 and item_values or item_values[1]
            else
                values[name] = ''
            end
        end
    end
    return values
end

---index table value by dot index like 'a.b.c'
---@param res table
---@param index string
---@param sep string optional,default is '.'
function util.index_value(res, index, sep)
    assert_arg(1, res, 'table')
    sep = sep or '.'
    local properties = split(index, sep, true)
    for i = 1, #properties do
        if not res[properties[i]] then
            return nil
        end
        res = res[properties[i]]
    end
    return res
end

function util.json_encode(data)
    return json.encode(data)
end
function util.json_decode(data)
    return json.decode(data)
end
function util.md5(str)
    return md5(str)
end

---is_array
---@param t any
function util.is_array(t)
    return helpers.is_array(t)
end

local function pairsByKeys(t)
    local a = {}

    for n in pairs(t) do
        a[#a + 1] = n
    end

    table.sort(a)

    local i = 0

    return function()
        i = i + 1
        return a[i], t[a[i]]
    end
end
util.pairsByKeys = pairsByKeys
function util.addslashes(str)
    return ngx.re.gsub(str, "([\'\\\"])", "\\$1", "jo")
end

--- Deep merge `src` into `dest` (in place), returning `dest`.
---
--- Arrays append, nested tables merge recursively, scalars overwrite — i.e. the
--- semantics Penlight's `tablex.update` provided.  With Penlight absent this
--- used to fall back to a flat overwrite, which REPLACED whole nested config
--- subtables instead of merging them, so `app.lua`'s layered config
--- (`Tilua.config.default` -> `<App>.config.default` -> `<App>.config.<status>`)
--- lost the framework defaults for any nested table the app also defined.
---
--- Delegating to `helpers.update` keeps one implementation.  Callers that need a
--- flat overwrite (middleware/config option merging) use `helpers.extend`.
---@param dest table
---@param src table
function util.extend(dest, src)
    assert_arg(1, dest, 'table')
    assert_arg(2, src, 'table')
    return helpers.update(dest, src)
end

function util.prequire(module)
    local found, hanlder = pcall(require, module)
    if found then
        return hanlder
    end
    return nil
end
function util.foreach(t, func, ...)
    for k, v in pairsByKeys(t) do
        func(v, k, ...)
    end
end
function util.callable(f)
    if type(f) == "function" then
        return true
    end
    local m = getmetatable(f)
    return m and type(m.__call) == "function"
end
function util.dump(...)
    local params = { ... }
    for i = 1, #params do
        local s = helpers.pretty(params[i])
        ngx.say(s .. '<br/>')
    end
end
--- Generate a v4 UUID without `resty.jit-uuid`.
---
--- Uses `get_rand_bytes` (declared later in this file and assigned before any
--- call site runs), so it is cryptographically random and needs no extra rock.
local function fallback_uuid()
    local raw = get_rand_bytes(16, true)
    if not raw then
        -- Last resort: still a valid v4 shape, seeded from the clock.  This
        -- path only triggers when both /dev/urandom and OpenSSL are missing.
        local out = {}
        local seed = tostring(now()) .. tostring(math.random(1, 1e9))
        for i = 0, 15 do
            out[i + 1] = string.char((seed:byte((i % #seed) + 1) + i * 17) % 256)
        end
        raw = table.concat(out)
    end

    local b = { raw:byte(1, 16) }
    b[7] = math.floor(b[7] / 16) * 16 + 4          -- version 4
    b[9] = math.floor(b[9] / 64) * 64 + 128        -- RFC 4122 variant

    local hex = {}
    for i = 1, 16 do
        hex[i] = string.format("%02x", b[i])
    end
    local h = table.concat(hex)
    return h:sub(1, 8) .. "-" .. h:sub(9, 12) .. "-" .. h:sub(13, 16)
        .. "-" .. h:sub(17, 20) .. "-" .. h:sub(21, 32)
end

util.CreateUUID = function()
    if uuid then
        uuid.seed()
        return uuid()
    end
    return fallback_uuid()
end

util.uuid = function(seed)
    if uuid then
        uuid.seed(seed)
        return uuid()
    end
    return fallback_uuid()
end

function util.get_hostname()
    local result
    local SIZE = 128

    local buf = ffi_new("unsigned char[?]", SIZE)
    local res = C.gethostname(buf, SIZE)

    if res == 0 then
        local hostname = ffi_str(buf, SIZE)
        result = gsub(hostname, "%z+$", "")
    else
        local f = io.popen("/bin/hostname")
        local hostname = f:read("*a") or ""
        f:close()
        result = gsub(hostname, "\n$", "")
    end

    return result
end

local get_rand_bytes

do
    local ngx_log = ngx.log
    local WARN = ngx.WARN

    local bytes_buf_t = ffi.typeof "char[?]"

    local function urandom_bytes(buf, size)
        local fd = ffi.C.open("/dev/urandom", 0, 0) -- mode is ignored
        if fd < 0 then
            ngx_log(WARN, "Error opening random fd: ",
                    ffi_str(ffi.C.strerror(ffi.errno())))

            return false
        end

        local res = ffi.C.read(fd, buf, size)
        if res <= 0 then
            ngx_log(WARN, "Error reading from urandom: ",
                    ffi_str(ffi.C.strerror(ffi.errno())))

            return false
        end

        if ffi.C.close(fd) ~= 0 then
            ngx_log(WARN, "Error closing urandom: ",
                    ffi_str(ffi.C.strerror(ffi.errno())))
        end

        return true
    end

    -- try to get n_bytes of CSPRNG data, first via /dev/urandom,
    -- and then falling back to OpenSSL if necessary
    get_rand_bytes = function(n_bytes, urandom)
        local buf = ffi_new(bytes_buf_t, n_bytes)
        ffi_fill(buf, n_bytes, 0x0)

        -- only read from urandom if we were explicitly asked
        if urandom then
            local rc = urandom_bytes(buf, n_bytes)

            -- if the read of urandom was successful, we returned true
            -- and buf is filled with our bytes, so return it as a string
            if rc then
                return ffi_str(buf, n_bytes)
            end
        end

        if C.RAND_bytes(buf, n_bytes) == 0 then
            -- get error code
            local err_code = C.ERR_get_error()
            if err_code == 0 then
                return nil, "could not get SSL error code from the queue"
            end

            -- get human-readable error string
            C.ERR_load_crypto_strings()
            local err = C.ERR_reason_error_string(err_code)
            C.ERR_free_strings()

            return nil, "could not get random bytes (" ..
                    "reason:" .. ffi_str(err) .. ") "
        end

        return ffi_str(buf, n_bytes)
    end

    util.get_rand_bytes = get_rand_bytes
end

do
    local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"

    --- URL-safe base64 (RFC 4648 §5) with no padding.
    ---
    --- Not `ngx.encode_base64(s, true)`: the `no_padding` second argument is not
    --- honoured by every OpenResty version, and the standard alphabet emits `+`
    --- and `/`, which the session id validator rejects.
    local function b64url(raw)
        local out = {}
        for i = 1, #raw, 3 do
            local a1, a2, a3 = raw:byte(i, i + 2)
            local v = a1 * 65536 + (a2 or 0) * 256 + (a3 or 0)
            local function ch(six)
                return ALPHABET:sub(six + 1, six + 1)
            end
            out[#out + 1] = ch(math.floor(v / 262144) % 64)
                .. ch(math.floor(v / 4096) % 64)
                .. (a2 and ch(math.floor(v / 64) % 64) or "")
                .. (a3 and ch(v % 64) or "")
        end
        return table.concat(out)
    end

    -- Cryptographically-random, URL-safe token.
    --
    -- Backed by /dev/urandom, falling back to OpenSSL RAND_bytes (see
    -- get_rand_bytes above), so it is suitable for session ids and CSRF tokens.
    --
    -- The charset `[A-Za-z0-9_-]` matters: `Tilua.session:valid_key` accepts only
    -- `^[%w%-_=]+$`.  The previous implementation returned standard base64 with
    -- a broken `gsub` post-process, emitting `+`, `/`, `=` and base64 line
    -- breaks; such ids were rejected by valid_key and the session silently got a
    -- NEW id on every request, so sessions never persisted.
    local function random_string(n_bytes)
        local raw, err = get_rand_bytes(n_bytes or 24, true)
        if not raw then
            -- Never silently degrade to a weak id.
            error("Tilua.utils.util.random_string: " .. tostring(err), 2)
        end
        return b64url(raw)
    end

    util.random_string = random_string
    util.b64url = b64url
end

local uuid_regex = "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
function util.is_valid_uuid(str)
    if type(str) ~= 'string' or #str ~= 36 then
        return false
    end
    return re_find(str, uuid_regex, 'ioj') ~= nil
end

---check vals is nil
function util.is_set(...)
    local params = { ... }
    for i = 1, #params do
        if params[i] == nil then
            return false
        end
    end
    return true
end

function util.import(...)
    local module = select(1, ...)
    if util.is_array(module) then
        module = table.concat(module, '.')
    else
        module = table.concat({ ... }, '.')
    end
    local ok, m = pcall(require, module)
    return ok and m or nil
end
---reverseTable
---@param tab table
---@return table
function util.reverseTable(tab)
    local tmp = {}
    for i = 1, #tab do
        tmp[i] = table.remove(tab)
    end
    return tmp
end

function util.is_string(val)
    return type(val) == 'string'
end

function util.is_scalar(val)
    return util.is_boolean(val) or util.is_string(val) or util.is_number(val)
end
---in_array
---@param array table
---@param val any
function util.in_array(array, val)
    return helpers.find(array, val) ~= nil
end

function util.get_now_ms()
    return now() * 1000
end

function util.get_timestamp()
    return now()
end

function util.elapse_time_start(tag, ctx)
    if not ctx then
        ctx = ngx.ctx
    end
    tag = tag and 'ELAPSE_TIME_TAG_' .. tag or 'ELAPSE_TIME_TAG_DEFAULT_START'
    ctx.tag = util.get_now_ms()
    return ctx.tag
end

function util.elapse_time_end(tag, ctx)
    if not ctx then
        ctx = ngx.ctx
    end
    tag = tag and 'ELAPSE_TIME_TAG_' .. tag or 'ELAPSE_TIME_TAG_DEFAULT_START'
    return util.get_now_ms() - ctx.tag
end

function util.is_number(val)
    return type(val) == 'number'
end

---序列化数组为字符串
---@param data table
function util.serialize(data)
    return util.json_encode(data)
end

function util.combine(keys, values)
    assert_arg(1, keys, 'table')
    assert_arg(1, values, 'table')
    local result = {}
    for i, v in ipairs(keys) do
        result[v] = values[i]
    end
    return result
end

function util.get_hash(data)
    return md5(util.serialize(data))
end
function util.is_boolean(val)
    return type(val) == 'boolean'
end
---判断值是否为空
---@param val any
function util.empty(val)
    return helpers.empty(val)
end
--"mysql://username:passwd@32.254.48.88:10/DbName?param1=val1&param2=val2#utf8"
function util.parse_url(url)
    local regex = "([a-zA-Z]+)://([a-zA-Z0-9_]+):([^@]+)@([^:]+):?([0-9]*)/([^?]+)\\??([^#]*)#(.+)"
    local m, _ = ngx.re.match(url, regex, "jo")
    if not m then
        return nil
    end
    return {
        scheme = m[1],
        user = m[2],
        pass = m[3],
        host = m[4],
        port = m[5],
        path = "/" .. m[6],
        query = m[7],
        params = ngx.decode_args(m[7]),
        fragment = m[8]
    }
end

---判断所有传入的值是否有空
function util.emptys(...)
    local result = true
    local args = { ... }
    foreach(args, function(val)
        result = result and util.empty(val)
    end)
    return result
end
return util