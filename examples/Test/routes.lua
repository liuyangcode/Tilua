local route = require("Tilua.route")
local lw_util = require("Tilua.utils.util")
--route.prefix('/posts', {
--    'json', 'body_parser'
--})
--route.prefix('/routes', {
--    'json', 'body_parser'
--})
route {
    ['/'] = {
        ['*'] = '[web] /'
    }
}

--route {
--    ['/'] = '[mvc] /'
--}

--route.get('~/user/find/([^\\/]+)/{name}$', function(ctx, uid, name)
--    ctx.response.body = { uid, name }
--end, {'json'})


route.group(function()
    route.rest('^/(services|certificate|secrets|targets|routes|upstreams|baffle|midwares|users)', 'controller.$1')
    route ['~^/plugins/([\\w]+)'] = 'controller.plugins@$1'
end, 'json', 'body_parser')

--route {
--    ['=/test-validation'] = function(ctx)
--        ctx.response.body = string.format("%03d",2)
--    end
--}
--
--route.get('/user/login.html', function(ctx)
--    local request, response = ctx:unpack()
--    response:render('index/login.html')
--end)
--
--route.get('~/user/find/{uid}/{name}', function(ctx, uid, name)
--    ctx.response.body = { uid, name, ctx.midware.test.config }
--end, { { 'Test.midware.test', { a = 1, b = 1 } }, 'json', 'session' })

