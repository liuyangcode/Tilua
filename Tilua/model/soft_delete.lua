--- Soft-delete helpers mixed into model instances
local soft = {}

--- Call once after model construct if soft_delete field configured
function soft.apply_defaults(model)
    -- soft_delete: false | true (use deleted_at) | "column_name"
    if model.soft_delete == true then
        model.soft_delete = "deleted_at"
    end
end

function soft.is_enabled(model)
    return type(model.soft_delete) == "string" and model.soft_delete ~= ""
end

function soft.column(model)
    return model.soft_delete
end

--- Inject "not deleted" condition unless with_trashed / only_trashed
function soft.apply_scope(model, options)
    if not soft.is_enabled(model) then
        return options
    end
    options = options or {}
    if options.with_trashed then
        return options
    end
    local col = soft.column(model)
    options.where = options.where or {}
    if type(options.where) == "table" then
        if options.only_trashed then
            options.where[col] = { "exp", "`" .. col .. "` IS NOT NULL" }
        elseif options.where[col] == nil then
            -- active rows only
            options.where[col] = { "exp", "`" .. col .. "` IS NULL" }
        end

    end
    return options
end

function soft.with_trashed(model)
    model.options.with_trashed = true
    return model
end

function soft.only_trashed(model)
    model.options.only_trashed = true
    return model
end

--- Soft delete: set timestamp
function soft.soft_delete(model, options)
    local col = soft.column(model)
    local now = ngx and ngx.localtime and ngx.localtime() or os.date("%Y-%m-%d %H:%M:%S")
    return model:data({ [col] = now }):save()
end

function soft.restore(model, options)
    local col = soft.column(model)
    model.options = model.options or {}
    model.options.with_trashed = true
    return model:data({ [col] = false }):save()
    -- use NULL via exp
end

function soft.restore_null(model)
    local col = soft.column(model)
    local pk = model:getPk()
    local id = model.data and model.data[pk]
    if not id and model.options and model.options.where then
        return model.db:update({ [col] = { "exp", "NULL" } }, model:_parseOptions())
    end
    if id then
        model.options.where = { [pk] = id }
    end
    model.options.with_trashed = true
    local options = model:_parseOptions()
    options.where = options.where or { [pk] = id }
    return model.db:update({ [col] = { "exp", "NULL" } }, options)
end

return soft
