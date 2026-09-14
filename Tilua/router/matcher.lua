local Matcher = {}

local ngx_re_match = ngx and ngx.re and ngx.re.match

local function match_pattern(pattern, path)
    if ngx_re_match then
        local matches, err = ngx_re_match(path, pattern, "jo")
        if matches then return matches end
        if err then return nil, err end
        return nil
    end
    return { string.match(path, pattern) }
end

function Matcher.match(route, method, path)
    if not route or not path then return nil end

    local pattern = route.compiled and route.compiled.pattern
    if not pattern then return nil end

    local matches = match_pattern(pattern, path)
    if not matches then return nil end

    if not route:allows(method) then
        return nil, "method_not_allowed"
    end

    local params = {}
    local names = route.params or {}
    for i, name in ipairs(names) do
        params[name] = matches[i]
    end

    return {
        route = route,
        params = params,
        method = string.upper(method or "GET"),
        path = path
    }
end

function Matcher.path(route, path)
    if not route or not route.compiled then return false end
    return match_pattern(route.compiled.pattern, path) ~= nil
end

return Matcher
