--- Production overrides for `App.status = "prod"`.
---
--- Switch by setting `App.status = "prod"` in Api/app.lua (or from an env var).
--- Only the differences from dev live here.

return {
    -- Verbose error messages and per-request debug logging are off.
    -- `debug = false` also makes template lookups cache aggressively, so a
    -- production worker never re-reads a view file.
    log = { level = "WARN" },

    -- Read the token from the environment rather than the source tree.
    api_token = os.getenv("API_TOKEN") or "change-me",

    -- A real deployment would turn these on:
    -- html_cache = true,
    -- data_cache_handler = "redis",
}
