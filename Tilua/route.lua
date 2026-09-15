--- Compatibility shim: Tilua.route → Tilua.http.router
--- Keeps old require("Tilua.route") working during migration.
return require("Tilua.http.router")
