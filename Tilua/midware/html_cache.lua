local html_cache = require("Tilua.midware").derive()

function html_cache:_init(ctx, config)
    self:super(ctx)
    self.ctx = ctx
    self.config = config
end

function html_cache:handle(next,request,...)
    return next(request)
end

return html_cache