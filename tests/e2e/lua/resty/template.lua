--- Minimal lua-resty-template stand-in for the end-to-end test only.
--- Tilua's view layer depends on it; a real deployment must install
--- lua-resty-template.  This stub only needs to satisfy the API the framework
--- touches during boot, and to make `render` obviously identifiable in bodies.
local caching_enabled = false

local tpl = {}

function tpl.new()
    return tpl
end

function tpl.caching(flag)
    if flag ~= nil then
        caching_enabled = flag and true or false
    end
    return caching_enabled
end

function tpl.precompile()
    return true
end

function tpl.compile()
    return function()
        return ""
    end
end

function tpl.compile_string(str)
    return function()
        return str or ""
    end
end

function tpl.process(view)
    return "<!-- stub template: " .. tostring(view) .. " -->"
end

function tpl.render(view)
    return "<!-- stub template: " .. tostring(view) .. " -->"
end

return tpl
