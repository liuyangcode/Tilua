local Compiler = {}

local function escape(text)
    return (text:gsub("([%.%+%-%^%$%(%)%[%]])", "%%%1"))
end

local function split_path(path)
    local parts = {}
    path = path or "/"
    if path == "/" then return parts end
    for part in path:gmatch("[^/]+") do parts[#parts + 1] = part end
    return parts
end

local function compile_parameter(token, params)
    local name, pattern = token:match("^([^:]+):(.+)$")
    name = name or token
    params[#params + 1] = name
    return pattern and "(" .. pattern .. ")" or "([^/]+)"
end

function Compiler.path(path, options)
    options = options or {}
    path = path or "/"
    local matcher = options.matcher or "*"
    local result = {
        path = path,
        matcher = matcher,
        params = {},
        pattern = nil,
        exact = matcher == "="
    }

    if matcher == "~" then
        result.pattern = path
        return result
    end

    if matcher == "=" then
        local exact_path = escape(path):gsub("/$", "")
        result.pattern = (path == "/") and "^/$" or ("^" .. exact_path .. "/?$")
        return result
    end

    local parts = split_path(path)
    if #parts == 0 then
        result.pattern = "^/$"
        return result
    end

    local patterns = { "^" }
    for _, part in ipairs(parts) do
        patterns[#patterns + 1] = "/"
        if part == "*" then
            patterns[#patterns + 1] = "(.*)"
            result.params[#result.params + 1] = "wildcard"
        elseif part:sub(1, 1) == "{" and part:sub(-1) == "}" then
            patterns[#patterns + 1] = compile_parameter(part:sub(2, -2), result.params)
        else
            patterns[#patterns + 1] = escape(part)
        end
    end
    patterns[#patterns + 1] = "/?$"
    result.pattern = table.concat(patterns)
    return result
end

function Compiler.route(route)
    route.compiled = Compiler.path(route.path, { matcher = route.matcher })
    route.params = route.compiled.params
    return route
end

return Compiler
