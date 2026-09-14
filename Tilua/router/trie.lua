local Trie = {}
Trie.__index = Trie

function Trie.new()
    return setmetatable({ routes = {}, static = {}, dynamic = {} }, Trie)
end

function Trie:add(route)
    self.routes[#self.routes + 1] = route
    local path = route.path or "/"
    if not path:find("{", 1, true) and not path:find("*", 1, true) and route.matcher ~= "~" then
        self.static[path] = self.static[path] or {}
        self.static[path][#self.static[path] + 1] = route
    else
        self.dynamic[#self.dynamic + 1] = route
    end
    return route
end

function Trie:find(path)
    local candidates = {}
    local static = self.static[path]
    if static then
        for _, route in ipairs(static) do candidates[#candidates + 1] = route end
    end
    for _, route in ipairs(self.dynamic) do candidates[#candidates + 1] = route end
    return candidates
end

function Trie:clear()
    self.routes = {}
    self.static = {}
    self.dynamic = {}
end

return setmetatable(Trie, {
    __call = function() return Trie.new() end
})
