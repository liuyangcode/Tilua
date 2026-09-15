--- Tilua.openapi (interface stub)
--- Collects route metadata for OpenAPI 3 document generation.
--- Enable: config.plugins = { "Tilua.openapi" }

local OpenAPI = {
    name = "openapi",
    priority = 80,
    _paths = {},
}

function OpenAPI.new(app)
    return OpenAPI
end

function OpenAPI.register(app)
    -- optional route annotation helper on router (resolve through the container)
    local route = app:make("router")
    if route and not route.openapi then
        route.openapi = function(meta)
            -- meta: { path, method, summary, tags, requestBody, responses }
            OpenAPI.document(meta)
            return route
        end
    end
end

function OpenAPI.document(meta)
    if type(meta) ~= "table" or not meta.path then
        return
    end
    local path = meta.path
    OpenAPI._paths[path] = OpenAPI._paths[path] or {}
    local method = string.lower(meta.method or "get")
    OpenAPI._paths[path][method] = {
        summary = meta.summary or "",
        tags = meta.tags or {},
        requestBody = meta.requestBody,
        responses = meta.responses or {
            ["200"] = { description = "OK" },
        },
        operationId = meta.operationId,
    }
end

function OpenAPI.spec(info)
    return {
        openapi = "3.0.3",
        info = info or {
            title = "Tilua API",
            version = "1.0.0",
        },
        paths = OpenAPI._paths,
    }
end

--- Emit JSON spec (call from a controller or health-like route)
function OpenAPI.to_json(info)
    local ok, cjson = pcall(require, "cjson.safe")
    if not ok then
        ok, cjson = pcall(require, "cjson")
    end
    if ok and cjson then
        return cjson.encode(OpenAPI.spec(info))
    end
    return nil, "cjson required"
end

OpenAPI.hooks = {
    on_route_loaded = function(app, router)
        -- future: auto-scan rule_caches for annotations
    end,
    on_boot = function(app)
        if app.logger and app.logger.debug then
            app.logger:debug("OpenAPI plugin ready; use route.openapi{...} or OpenAPI.document")
        end
    end,
}

return OpenAPI
