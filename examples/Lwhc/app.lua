local app = require("Tilua.app").derive()

app.name = "Lwhc"
app.path = "/usr/local/openresty/lua/Lwhc/"
app.debug = false
app.status = 'dev'

function app:_init()
    self:super(self)
end

return app