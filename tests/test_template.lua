if not ngx then
    _G.ngx = { now = os.time }
end

package.path = "./?.lua;./?/init.lua;" .. (package.path or "")

local template = require("Tilua.template")

local function assert_true(c, msg)
    if not c then error(msg or "assert failed", 2) end
end

-----------------------------------------------------------------------
-- fixture views
-----------------------------------------------------------------------

local root = os.tmpname() .. "_tilua_template_view"
os.execute("mkdir -p '" .. root .. "/partials'")

local function write(path, content)
    local f = assert(io.open(path, "w"))
    f:write(content)
    f:close()
end

write(root .. "/greeting.html", table.concat({
    "<h1>{{ title }}</h1>",
    "{# comment, must not render #}",
    "<p>Raw: {{{ raw_html }}}</p>",
    "{% for _, name in ipairs(names) do %}<li>{{ name }}</li>{% end %}",
    "{{{ include(\"partials/footer.html\", { year = 2026 }) }}}",
}, "\n"))

write(root .. "/partials/footer.html", "<footer>&copy; {{ year }} {{ title }}</footer>")

local engine = template.new({ root = root })

local ctx = {
    title    = "<Tilua> & Friends",
    raw_html = "<b>bold</b>",
    names    = { "Ada", "Grace" },
}

-----------------------------------------------------------------------
-- render()
-----------------------------------------------------------------------

local out = engine:render("greeting.html", ctx)
assert_true(out:find("&lt;Tilua&gt; &amp; Friends", 1, true), "expression output should be HTML-escaped")
assert_true(out:find("<b>bold</b>", 1, true), "{{{ }}} output should be raw/unescaped")
assert_true(out:find("<li>Ada</li>", 1, true) and out:find("<li>Grace</li>", 1, true), "{% for %} loop should run")
assert_true(not out:find("comment, must not render", 1, true), "{# #} comments must not appear in output")
assert_true(out:find("&copy; 2026 &lt;Tilua&gt; &amp; Friends", 1, true), "include() should render the partial with merged context")

-----------------------------------------------------------------------
-- compile_string()
-----------------------------------------------------------------------

local fn = engine:compile_string("{{ 1 + 1 }} and {{{ '<raw>' }}}")
assert_true(fn({}) == "2 and <raw>", "compile_string should compile and run inline template strings")

-----------------------------------------------------------------------
-- precompile() + process() on the resulting cache file
-----------------------------------------------------------------------

local cache_file = root .. "/../greeting.cache.html"
engine:precompile("greeting.html", cache_file)

local cf = assert(io.open(cache_file))
local cached_src = cf:read("*a")
cf:close()
assert_true(cached_src:find("_b[#_b + 1]", 1, true) ~= nil, "precompile() should write generated Lua source")

local via_cache = engine:process(cache_file, ctx)
assert_true(via_cache == out, "process() on a precompiled cache file should match render() on the source")

local via_source = engine:process("greeting.html", ctx)
assert_true(via_source == out, "process() on raw markup should also match render()")

os.execute("rm -rf '" .. root .. "' '" .. cache_file .. "'")

print("test_template: OK")
