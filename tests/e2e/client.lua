--- End-to-end client: raw FFI sockets (no curl / luasocket in the image).
--- Prints status + body for each case so the shell runner can dump it.
local ffi = require("ffi")
local C = ffi.C

ffi.cdef [[
typedef int socklen_t;
int socket(int domain, int type, int protocol);
int connect(int sockfd, const void *addr, socklen_t addrlen);
long send(int sockfd, const void *buf, unsigned long len, int flags);
long recv(int sockfd, void *buf, unsigned long len, int flags);
int close(int fd);
struct sockaddr_in {
    unsigned short sin_family;
    unsigned short sin_port;
    unsigned int   sin_addr;
    char           sin_zero[8];
};
unsigned short htons(unsigned short hostshort);
unsigned int inet_addr(const char *cp);
]]

local AF_INET, SOCK_STREAM = 2, 1

local function request(path, headers)
    local fd = C.socket(AF_INET, SOCK_STREAM, 0)
    if fd < 0 then return nil, "socket() failed" end

    local addr = ffi.new("struct sockaddr_in")
    addr.sin_family = AF_INET
    addr.sin_port = C.htons(8100)
    addr.sin_addr = C.inet_addr("127.0.0.1")

    if C.connect(fd, addr, ffi.sizeof(addr)) ~= 0 then
        C.close(fd)
        return nil, "connect() failed"
    end

    local req = { "GET ", path, " HTTP/1.0\r\nHost: localhost\r\nConnection: close\r\n" }
    for k, v in pairs(headers or {}) do
        req[#req + 1] = k .. ": " .. v .. "\r\n"
    end
    req[#req + 1] = "\r\n"
    req = table.concat(req)
    C.send(fd, req, #req, 0)

    local buf = ffi.new("char[?]", 65536)
    local parts = {}
    while true do
        local n = C.recv(fd, buf, 65536, 0)
        if n <= 0 then break end
        parts[#parts + 1] = ffi.string(buf, n)
    end
    C.close(fd)

    local raw = table.concat(parts)
    local status = raw:match("^HTTP/%d%.%d (%d+)") or "?"
    local body = raw:match("\r\n\r\n(.*)$") or ""
    local hdr = {}
    for k, v in raw:gmatch("([Xx]-[Dd]ebug-[%w%-]+):%s*([^\r\n]+)") do
        hdr[#hdr + 1] = k .. "=" .. v
    end
    return { status = status, body = body, debug = table.concat(hdr, " ") }
end

local cases = {
    { "/greeter",      nil, "JSON route (response:send)" },
    { "/text",         nil, "plain string return -> text body" },
    { "/text-literal", nil, "response() body shorthand" },
    { "/view",         nil, "view render -> Tilua.template" },
    { "/about",        nil, "route from the callback form" },
    { "/user/ada",     nil, "path parameter" },
    { "/num/42",       nil, "param validation (reg) ACCEPT" },
    { "/num/abc",      nil, "param validation (reg) REJECT" },
    { "/kind/ok",      nil, "param validation (eq) ACCEPT" },
    { "/kind/no",      nil, "param validation (eq) REJECT" },
    { "/pair/x",       nil, "same-shape params: winner captures its own name" },
    { "/left/1",       nil, "separate parents keep separate param names (x)" },
    { "/right/2",      nil, "separate parents keep separate param names (y)" },
    { "/view-assign",  nil, "view:assign + render without a context table" },
    { "/mvc/index",    nil, "full MVC: controller action -> assign -> display -> view" },
    { "/mvc/mounted",  nil, "MVC: mount_context fallback + display() context" },
    { "/mvc/bare",     nil, "MVC: display() with no context at all" },
    { "/mvc/json",     nil, "MVC: a controller action returning a table" },
    { "/admin",        nil, "access-phase DENY (no token)" },
    { "/admin",        { ["X-Admin-Token"] = "letmein" }, "access-phase ADMIT" },
    { "/healthz",      nil, "health endpoint short-circuit" },
    { "/nope",         nil, "404" },
    { "/boom",         nil, "500 from a throwing route" },
}

for _, c in ipairs(cases) do
    local res, err = request(c[1], c[2])
    print(string.format("### %s   [%s]", c[1], c[3]))
    if res then
        print("status: " .. res.status)
        if res.debug and res.debug ~= "" then
            print("debug:  " .. res.debug)
        end
        print("body: " .. res.body:gsub("\n", "\\n"))
    else
        print("ERROR: " .. tostring(err))
    end
    print("")
end
