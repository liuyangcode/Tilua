local app = require("Tilua.app").define()

app.name = "Lwhc"
app.debug = false
app.status = 'dev'

function app:_init()
    self:super(self)
end

return app