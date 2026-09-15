--- Tilua.model.result
--- Lightweight row hydration helpers (no heavy ORM magic)

local Result = {}

local row_mt = {
    __index = function(self, key)
        return rawget(self, "_data")[key]
    end,
    __newindex = function(self, key, value)
        rawget(self, "_data")[key] = value
        rawset(self, "_dirty", true)
    end,
}

function Result.row(data, model)
    if type(data) ~= "table" then
        return data
    end
    local obj = {
        _data = data,
        _model = model,
        _dirty = false,
    }
    function obj:to_table()
        return self._data
    end
    function obj:get(key, default)
        local v = self._data[key]
        if v == nil then return default end
        return v
    end
    function obj:set(key, value)
        self._data[key] = value
        self._dirty = true
        return self
    end
    function obj:is_dirty()
        return self._dirty
    end
    --- Persist dirty fields via model:save if model available
    function obj:save()
        if not self._model or not self._dirty then
            return false
        end
        local pk = self._model:getPk()
        local id = self._data[pk]
        if not id then
            return self._model:data(self._data):add()
        end
        return self._model:data(self._data):where({ [pk] = id }):save()
    end
    return setmetatable(obj, row_mt)
end

function Result.hydrate(rows, model)
    if type(rows) ~= "table" then
        return rows
    end
    -- single assoc row (not array)
    if rows[1] == nil and next(rows) ~= nil then
        return Result.row(rows, model)
    end
    local list = {}
    for i, r in ipairs(rows) do
        list[i] = Result.row(r, model)
    end
    return list
end

function Result.pluck(rows, column, key_field)
    local out = {}
    if not rows then
        return out
    end
    for i, r in ipairs(rows) do
        local data = r._data or r
        if key_field then
            out[data[key_field]] = data[column]
        else
            out[#out + 1] = data[column]
        end
    end
    return out
end

return Result
