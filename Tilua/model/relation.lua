--- Lightweight relation helpers for Tilua models
--- Usage in model subclass _construct or properties:
---   self.relations = {
---     profile = { type = "hasOne", model = "Profile", foreign_key = "user_id", local_key = "id" },
---     posts   = { type = "hasMany", model = "Post", foreign_key = "user_id" },
---     author  = { type = "belongsTo", model = "User", foreign_key = "user_id" },
---   }

local Relation = {}

local function resolve_model(ctx, name)
    if not ctx or not ctx.model then
        return nil
    end
    if type(name) == "table" then
        return name
    end
    -- manager __index instantiates
    return ctx.model[name]
end

local function local_key_of(def, parent)
    return def.local_key or parent:getPk() or "id"
end

local function foreign_key_of(def, parent)
    if def.foreign_key then
        return def.foreign_key
    end
    -- convention: parent_table_id
    local name = parent.name or "parent"
    return string.lower(name) .. "_id"
end

--- hasOne: related.foreign_key = parent.local_key (one row)
function Relation.hasOne(parent, related_name, foreign_key, local_key)
    local def = {
        type = "hasOne",
        model = related_name,
        foreign_key = foreign_key,
        local_key = local_key,
    }
    return Relation.query(parent, def)
end

--- hasMany
function Relation.hasMany(parent, related_name, foreign_key, local_key)
    local def = {
        type = "hasMany",
        model = related_name,
        foreign_key = foreign_key,
        local_key = local_key,
    }
    return Relation.query(parent, def)
end

--- belongsTo: parent.foreign_key = related.pk
function Relation.belongsTo(parent, related_name, foreign_key, owner_key)
    local def = {
        type = "belongsTo",
        model = related_name,
        foreign_key = foreign_key,
        local_key = owner_key or "id",
    }
    return Relation.query(parent, def)
end

--- Build a related model query constrained by parent data / where
function Relation.query(parent, def)
    local related = resolve_model(parent.ctx, def.model)
    if not related then
        error("relation model not found: " .. tostring(def.model))
    end

    local pk = local_key_of(def, parent)
    local fk = foreign_key_of(def, parent)
    local parent_val

    if def.type == "belongsTo" then
        -- value from parent row
        parent_val = (parent.data and parent.data[fk]) or nil
        if parent_val == nil and parent.options and type(parent.options.where) == "table" then
            parent_val = parent.options.where[fk]
        end
        if parent_val ~= nil then
            related:where({ [pk] = parent_val })
        end
    else
        parent_val = (parent.data and parent.data[pk]) or nil
        if parent_val == nil and parent.options and type(parent.options.where) == "table" then
            parent_val = parent.options.where[pk]
        end
        if parent_val ~= nil then
            related:where({ [fk] = parent_val })
        end
    end

    related._relation_def = def
    related._relation_parent = parent
    return related
end

--- Load named relation from self.relations config
function Relation.load(parent, name)
    local defs = parent.relations
    if not defs or not defs[name] then
        error("undefined relation: " .. tostring(name))
    end
    local def = defs[name]
    def.model = def.model or name
    return Relation.query(parent, def)
end

--- Eager-ish load: for a list of parent rows, batch load hasMany/hasOne
function Relation.eager(parent_model, name, rows)
    if not rows or #rows == 0 then
        return rows
    end
    local defs = parent_model.relations
    if not defs or not defs[name] then
        return rows
    end
    local def = defs[name]
    local related = resolve_model(parent_model.ctx, def.model or name)
    if not related then
        return rows
    end

    local pk = local_key_of(def, parent_model)
    local fk = foreign_key_of(def, parent_model)
    local ids = {}
    for _, r in ipairs(rows) do
        local data = r._data or r
        local id = data[pk]
        if id ~= nil then
            ids[#ids + 1] = id
        end
    end
    if #ids == 0 then
        return rows
    end

    local children = related:where({ [fk] = { "in", ids } }):select() or {}
    local grouped = {}
    for _, c in ipairs(children) do
        local cd = c._data or c
        local key = cd[fk]
        grouped[key] = grouped[key] or {}
        grouped[key][#grouped[key] + 1] = c
    end

    for _, r in ipairs(rows) do
        local data = r._data or r
        local key = data[pk]
        local set = grouped[key] or {}
        if def.type == "hasOne" or def.type == "belongsTo" then
            if r.set then
                r:set(name, set[1])
            else
                data[name] = set[1]
            end
        else
            if r.set then
                r:set(name, set)
            else
                data[name] = set
            end
        end
    end
    return rows
end

return Relation
