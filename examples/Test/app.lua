
local app = require("Tilua.app").derive()

function app:_init()
    self.module = 'Home'
    self.app_name = "Test"
    self.app_path = "/usr/local/openresty/lua/Test/"
    self.debug = true
    self:super(self)
end
return app