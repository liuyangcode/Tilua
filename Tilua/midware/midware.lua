

local class = require('pl.class')

class.midware()

function midware:_init(app)
    self.app = app
end

function midware:hanlde(...)
    assert(false, 'midware is base class ,cannot be instanced')
end

function midware.derive()
    return class(midware)
end

return midware