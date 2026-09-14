local class = require("Tilua.utils.class")
local Request = require("Tilua.request")
local Response = require("Tilua.response")

local Lifecycle = class.define()

function Lifecycle:_construct(app)
    self.app = app
    self.ctx_key = "tilua"
end

function Lifecycle:init()
    self.app:boot()
    return self
end

function Lifecycle:init_worker()
    self.app:init_worker()
    return self
end

function Lifecycle:create_context()
    local ctx = self:get_context()
    if ctx then
        return ctx
    end

    local request = Request.capture(self.app)
    local response = Response(self.app)
    ctx = self.app:new_context(request, response)

    ngx.ctx[self.ctx_key] = ctx
    return ctx
end

function Lifecycle:get_context()
    return ngx.ctx[self.ctx_key]
end

function Lifecycle:set_context(ctx)
    ngx.ctx[self.ctx_key] = ctx
    return ctx
end

function Lifecycle:rewrite()
    return self:create_context()
end

function Lifecycle:access()
    local ctx = self:create_context()
    return ctx
end

function Lifecycle:content()
    local ctx = self:create_context()

    local ok, err = xpcall(function()
        return self.app:handle(ctx)
    end, debug.traceback)

    if not ok then
        return self:handle_exception(ctx, err)
    end

    if ctx.response and ctx.response.send then
        return ctx.response:send()
    end

    return err
end

function Lifecycle:log()
    local ctx = self:get_context()
    if not ctx then
        return
    end

    local logger
    if self.app.container:has("logger") then
        logger = self.app.container:get("logger")
    end

    if logger and logger.request then
        logger:request(ctx)
    end
end

function Lifecycle:exit_worker()
    return self.app:shutdown()
end

function Lifecycle:handle_exception(ctx, err)
    local logger
    if self.app.container:has("logger") then
        logger = self.app.container:get("logger")
    end

    if logger and logger.error then
        logger:error(err)
    else
        ngx.log(ngx.ERR, "Tilua request error: ", tostring(err))
    end

    if ctx.response then
        if ctx.response.json then
            return ctx.response:json({
                error = "internal_server_error",
                message = self.app.env == "production" and "Internal Server Error" or tostring(err)
            }, 500):send()
        end
        ngx.status = 500
        ngx.say(self.app.env == "production" and "Internal Server Error" or tostring(err))
        return
    end

    return ngx.exit(500)
end

return Lifecycle
