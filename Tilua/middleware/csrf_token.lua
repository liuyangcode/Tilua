--- CSRF middleware (v0.2.5)
--- - Issues token in session + optional double-submit cookie (SameSite)
--- - Validates on unsafe methods (POST/PUT/PATCH/DELETE)
--- - Accepts body field, header, or cookie

local lw_util = require("Tilua.utils.util")
local helpers = require("Tilua.core.helpers")
local errors = require("Tilua.core.errors")
local base = require("Tilua.middleware.base")

local csrf_token = (type(base.define) == "function" and base.define()) or base
csrf_token.alias = "csrf"

local UNSAFE = {
    POST = true,
    PUT = true,
    PATCH = true,
    DELETE = true,
}

local DEFAULTS = {
    field_name = "csrftoken",
    header_name = "x-csrf-token", -- also accepts csrftoken
    cookie_name = "XSRF-TOKEN",
    session_key = "csrf_token",
    cookie_path = "/",
    cookie_secure = false,
    cookie_samesite = "Lax",
    cookie_httponly = false, -- readable by JS for SPA double-submit
    enable_cookie = true,
    auto_check = true,
}

local function merge_config(cfg)
    local c = helpers.extend({}, DEFAULTS)
    if cfg then
        helpers.extend(c, cfg)
    end
    return c
end

local function new_token()
    if lw_util.uuid then
        return lw_util.uuid()
    end
    if lw_util.random_string then
        return lw_util.random_string()
    end
    return ngx.md5(tostring(ngx.now()) .. tostring(math.random(1, 1e9)))
end

function csrf_token:_construct(ctx, config)
    self.ctx = ctx
    self.config = merge_config(config)
end

function csrf_token:ensure_token()
    local sess = self.ctx.session
    if not sess then
        return nil
    end
    local key = self.config.session_key
    local token = sess:get(key)
    if not token or token == "" then
        token = new_token()
        sess:set(key, token)
    end
    return token
end

--- HTML hidden input
function csrf_token:token()
    local token = self:ensure_token()
    local field = self.config.field_name
    return '<input type="hidden" name="' .. field .. '" value="' .. tostring(token or "") .. '"/>'
end

function csrf_token:meta_tag()
    local token = self:ensure_token()
    return '<meta name="csrf-token" content="' .. tostring(token or "") .. '"/>'
end

function csrf_token:issue_cookie(response, token)
    if not self.config.enable_cookie or not response or not token then
        return
    end
    response:set_cookie({
        name = self.config.cookie_name,
        value = token,
        path = self.config.cookie_path or "/",
        httponly = self.config.cookie_httponly and true or false,
        secure = self.config.cookie_secure,
        samesite = self.config.cookie_samesite or "Lax",
        raw = true,
    })
end

function csrf_token:read_request_token(request)
    local field = self.config.field_name
    local body = request.body or request._body or {}
    local token = body[field]
    if not token and request.header then
        token = request.header[self.config.header_name]
            or request.header["X-CSRF-TOKEN"]
            or request.header["x-csrf-token"]
            or request.header.csrftoken
            or request.header["X-XSRF-TOKEN"]
    end
    if not token and request.cookie and self.config.enable_cookie then
        token = request.cookie[self.config.cookie_name]
    end
    return token
end

function csrf_token:check()
    local request = self.ctx.request
    if not request then
        request = select(1, self.ctx:unpack())
    end
    local sess = self.ctx.session
    if not sess then
        return false
    end
    local expected = sess:get(self.config.session_key)
    local provided = self:read_request_token(request)
    if not expected or not provided or provided ~= expected then
        return false
    end
    return true
end

--- Rotate token after successful check (optional one-time use)
function csrf_token:rotate()
    local sess = self.ctx.session
    if not sess then
        return nil
    end
    local token = new_token()
    sess:set(self.config.session_key, token)
    return token
end

function csrf_token:handle(next_fn, ...)
    local cfg = self.config
    local request, response = self.ctx:unpack()

    -- expose helpers to views
    if self.ctx.view and self.ctx.view.mount_context then
        self.ctx.view:mount_context("__CSRF__", function()
            return self:token()
        end)
        self.ctx.view:mount_context("__CSRF_META__", function()
            return self:meta_tag()
        end)
    end

    local token = self:ensure_token()
    if token then
        self:issue_cookie(response, token)
    end

    if cfg.auto_check then
        local method = string.upper(tostring(request.method or ngx.var.request_method or "GET"))
        if UNSAFE[method] then
            if not self:check() then
                local err = errors.forbidden("CSRF token mismatch", "csrf_failed")
                local as_json = self.ctx.config and self.ctx.config.enable_json_errors
                return errors.apply(response, err, as_json)
            end
            -- rotate after successful unsafe request
            local new_t = self:rotate()
            if new_t then
                self:issue_cookie(response, new_t)
            end
        end
    end

    return next_fn(...)
end

return csrf_token
