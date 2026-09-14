local Trie = {}
Trie.__index = Trie

function Trie.new()
    return setmetatable({ routes = {}, static = {} }, Trie)
end

function Trie:add(route)
    self.routes[#self.routes + 1] = route
    local path = route.path or "/"
    if not path:find("{", 1, true) and not path:find("*", 1, true) then
        self.static[path] = self.static[path] or {}
        self.static[path][#self.static[path] + 1] = route
    end
    return route
end

function Trie:find(path)
    local static = self.static[path]
    if static and #static > 0 then return static end
    return self.routes
end

function Trie:clear()
    self.routes = {}
    self.static = {}
end

return setmetatable(Trie, {
    __call = function() return Trie.new() end
})
