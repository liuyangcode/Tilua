local route = require("Tilua.route")
local lw_util = require("Tilua.util")
--route.prefix('/posts', {
--    'json', 'body_parser'
--})
--route.prefix('/routes', {
--    'json', 'body_parser'
--})
route {
    ['/'] = {
        ['*'] = '[mvc] /'
    }
}

--route {
--    ['/'] = '[mvc] /'
--}

route.get('~/user/find/([^\\/]+)/{name}$', function(ctx, uid, name)
    ctx.response.body = { uid, name }
end, {'json'})


route.group(function()
    route.rest('^/(services|secrets|targets|routes|upstreams|baffle|midwares|users)', 'controller.$1')
    route {
        ["=/routes/addPlugin"] = {
            get = 'controller.routes@add_plugin',
            post = 'controller.routes@do_add_plugin'
        }
    }
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

