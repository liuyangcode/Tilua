--- Fixture controller exercising action annotations.
---
--- `auto_routes = true` discovers this file and honours the annotations below.
--- `plain` has no annotation and must keep the `GET /annotated/plain` default.

local controller = require("Tilua.controller")

local Annotated = controller.define()

--- No annotation: keeps the convention default.
function Annotated:plain()
    return "plain"
end

--- @route GET /ann/read/{id}
--- @route POST /ann/create
--- @middleware auth
function Annotated:multi(id)
    return "multi:" .. tostring(id)
end

--- @route PUT
--- @middleware rate_limit, { limit = 10 }
--- @middleware audit
function Annotated:limited()
    return "limited"
end

--- @route DELETE /ann/remove/{id}
--- @phases access = admin_guard
function Annotated:guarded(id)
    return "guarded:" .. tostring(id)
end

--- @middleware auth
--- @phases access = admin_guard
--- @route GET /ann/both
function Annotated:both()
    return "both"
end

--- @route get,post /ann/pair
function Annotated:pair()
    return "pair"
end

--- @route WRONG /ann/bad
function Annotated:badmethod()
    return "bad"
end

--- @route GET /ann/unknown
--- @nonsense whatever
function Annotated:typo()
    return "typo"
end

--- A `--[[ ]]` block comment is documentation, not an annotation, so this action
--- must keep the default GET /annotated/blockdoc.
--[[
--- @route POST /ann/should-not-apply
]]
function Annotated:blockdoc()
    return "blockdoc"
end

--- An annotation block separated from its action by a BLANK LINE does not apply
--- (the block must be contiguous).
--- @route POST /ann/separated

function Annotated:separated()
    return "separated"
end

--- Private actions are never registered, even when annotated.
--- @route GET /ann/private
function Annotated:_private()
    return "private"
end

return Annotated
