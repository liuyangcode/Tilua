--- Tilua.service – service manager (lazy load app services)
---
--- Usage:
---   local userSvc = ctx.service.User          -- require(app.service.User)
---   local userSvc = ctx.service:instance("User")
---
--- Application service modules should live at:
---   <app>/service/User.lua  → return a class defined from Tilua.service.base

local helpers = require("Tilua.core.helpers")
local bind1 = helpers.bind1
local lw_utils = require("Tilua.utils.util")
local base = require("Tilua.service.base")

---@class service_manager
local manager = {}

function manager:instance(name)
    if not name or name == "" then
        return nil
    end
    if self.services[name] then
        return self.services[name]
    end

    self.logger:debug("init service ", name)

    -- 1. application service: app.service.Name
    local mod
    local ok, m = pcall(function()
        return lw_utils.import(table.concat({ self.ctx.name, "service", name }, "."))
    end)
    if ok then
        mod = m
    end

    -- 2. framework built-in (optional)
    if not mod then
        ok, m = pcall(require, "Tilua.service." .. name)
        if ok and m and m ~= base then
            mod = m
        end
    end

    local svc
    if mod then
        -- class from base.define() or plain table with new/_construct
        if type(mod) == "table" and (mod._construct or mod.__call) then
            svc = mod(self.ctx, name)
        elseif type(mod) == "function" then
            svc = mod(self.ctx, name)
        elseif type(mod) == "table" then
            svc = setmetatable({ ctx = self.ctx, name = name }, { __index = mod })
            if type(mod._construct) == "function" then
                mod._construct(svc, self.ctx, name)
            end
        end
    end

    -- 3. fallback empty service bound to ctx
    if not svc then
        svc = base(self.ctx, name)
    end

    self.services[name] = svc
    return svc
end

--- Register an already-built service instance
function manager:register(name, svc)
    self.services[name] = svc
    return svc
end

local function new(_, ctx)
    return setmetatable({
        ctx = ctx,
        logger = ctx.logger,
        services = {},
    }, {
        __index = function(this, name)
            local rawp = rawget(manager, name)
            if type(rawp) == "function" then
                return bind1(rawp, this)
            elseif type(rawp) == "string" then
                return rawp
            else
                return manager.instance(this, name)
            end
        end,
    })
end

setmetatable(manager, { __call = new })

return manager
