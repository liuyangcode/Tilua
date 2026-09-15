--- Minimal resty.jit-uuid stand-in for the end-to-end test only.
--- The framework hard-requires this module (see docs/ANALYSIS.md 5.1/5.2);
--- a real deployment must install lua-resty-jit-uuid.
local counter = 0
local M = {}

function M.seed()
    return true
end

function M.flush()
    return true
end

function M.new()
    counter = counter + 1
    return string.format("00000000-0000-4000-8000-%012d", counter)
end

return setmetatable(M, {
    __call = function()
        return M.new()
    end,
})
