# Tilua
a simple mvc lua web development kit based on [openresty](https://openresty.org/)
# Status
Pruduction not ready
# Dependencies
* [lua-resty-template](https://github.com/bungle/lua-resty-template)
* [lua-resty-redis](https://github.com/bungle/lua-resty-redis)
* [lua-resty-mysql](https://github.com/bungle/lua-resty-mysql)
* [Penlight - A Portable Lua Library](http://www.penlight.luaforge.net/)
# Demo
nginx/8001.conf
```nginx
lua_package_path '$prefix/../lua/?.lua;$prefix/../lualib/?.lua;;';
lua_shared_dict app_test_cache 10m;
server {
        listen 8001;
        location ~/.*\.(css|js|jpg|jpeg|png).*$ {
                root /var/web;
                add_header Access-Control-Allow-Origin *;
                keepalive_timeout  0;
                expires 7d;
        }
        location / {
                lua_code_cache off;
                content_by_lua_block {
                    require "Test.app"():run()
                }
        }
}
```
Test/app.lua
```lua
local app = require("Tilua.app").derive() 

function app:_init()
    self.module = 'Home'
    self.app_name = "Test"
    self.app_path = "/usr/local/openresty/lua/Test/"
    self.debug = true
    self:super(self)
end
return app
```
路由模式
Test/routes.lua
```lua
local route = require('Tilua.route')
local response = require('Tilua.response')
route.get('/', function()
    return response('hello world!')
end)
route.get('/user/welcome/{name}', function(request,name)
    return response('welcome '..name..'!')
end)
```

控制器模式
Test/Home/controller/index.lua
```lua
local index = require("Tilua.controller").derive()

function index:_init(...)
    self:super(...)
end

function index:index(request,name)
    return 'welcome,'..name
end
return index
```


## License and Copyright

MIT License

Copyright (c) 2020 liuyangcode

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
