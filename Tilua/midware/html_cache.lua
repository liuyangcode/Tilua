local html_cache = require("Tilua.midware").derive()

function html_cache:_init(ctx, config)
    self:super(ctx)
    self.ctx = ctx
    self.config = config
end

function html_cache:handle(next,request,...)
    ngx.say(self.ctx.mvc_router.controller_name)
    return next(request)
end

return html_cache