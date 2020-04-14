local app = require("Tilua.app").derive()

function app:_init()
    self:super(self)
    self.app_name = "Test"
    self.app_path = "/usr/local/openresty/lua/Test/"
    self.debug = true
    self.status = 'dev'
end
return app