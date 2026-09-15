--- Session middleware (optimized)
--- - Caches save_handler module (no require every request for path string)
--- - Only sets cookie when there is something to send
--- - pcall around start/close so session failures don't take down the request

local session = require("Tilua.session")
local helpers = require("Tilua.core.helpers")

local session_start = {}

local handler_cache = {}

local function resolve_save_handler(path_or_mod, ctx)
    if type(path_or_mod) == "table" and path_or_mod.new then
        return path_or_mod.new(ctx)
    end
    local path = path_or_mod
    if type(path) ~= "string" then
        path = "Tilua.session.session_redis_hanler"
    end
    local mod = handler_cache[path]
    if not mod then
        local ok, m = pcall(require, path)
        if not ok or not m then
            error("Cannot find session save handler: " .. tostring(path) .. " err=" .. tostring(m))
        end
        handler_cache[path] = m
        mod = m
    end
    return mod.new(ctx)
end

function session_start:handle(next_fn, ...)
    local request, response = self.ctx:unpack()

    local save_handler = resolve_save_handler(self.config.save_handler, self.ctx)
    local cfg = helpers.extend({}, self.config)
    cfg.save_handler = save_handler

    local sess = session(cfg, self.ctx)
    local ok, err = pcall(sess.start, sess, request)
    if not ok then
        if self.ctx.logger then
            self.ctx.logger:error("session start failed: ", tostring(err))
        end
        -- continue without session rather than 500
        return next_fn(...)
    end

    self.ctx.session = sess
    response = next_fn(...)

    local cookie = sess:cookie_to_send()
    if cookie and cookie ~= "" and type(response.set_cookie) == "function" then
        -- response:set_cookie accepts raw Set-Cookie string when name-only form used
        pcall(response.set_cookie, response, cookie)
    end

    pcall(sess.close, sess)
    return response
end

local function new(self, ctx, config)
    local default_config = {
        use_strict_mode = true,
        use_cookies = true,
        gc_maxlifetime = 3600,
        gc_divisor = 100,
        name = "ACCESSTOKEN",
        -- prefer canonical path; legacy typo path still works
        save_handler = "Tilua.session.redis",
        serialize_handler = nil,
        use_only_cookies = true,
        referer_check = "",
        lazy_write = 1,
        gc_probability = 1,
        cookie_path = "/",
        cookie_domain = "",
        cookie_expires = 0,
        cookie_http_only = true,
        cookie_secure = false,
        cookie_same_site = "Lax",
    }

    local merged = helpers.extend({}, default_config)
    if config then
        helpers.extend(merged, config)
    end

    return setmetatable({
        ctx = ctx,
        config = merged,
    }, { __index = self })
end

setmetatable(session_start, { __call = new })

return session_start
