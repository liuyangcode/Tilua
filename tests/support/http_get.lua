--- Minimal HTTP client for example smoke tests.
---
---   luajit tests/support/http_get.lua <port> <path> [--header "Name: value"]...
---   luajit tests/support/http_get.lua <port> <path> --headers-from FILE
---
--- `--headers-from` reads one "Name: value" per line; the shell runner uses it
--- because POSIX sh cannot pass an array of arguments.
---
--- Prints:
---   line 1: status code
---   line 2: body (newlines escaped, truncated)
---
--- Uses FFI sockets because the stock OpenResty image has neither curl nor
--- luasocket.  `tests/e2e/client.lua` is the fuller version used by the
--- framework's own e2e suite.

local port = tonumber(arg[1]) or 8080
local path = arg[2] or "/"

local headers = {}
do
    local i = 3
    while i <= #arg do
        if arg[i] == "--header" and arg[i + 1] then
            headers[#headers + 1] = arg[i + 1]
            i = i + 2
        elseif arg[i] == "--headers-from" and arg[i + 1] then
            local f = io.open(arg[i + 1], "r")
            if f then
                for line in f:lines() do
                    if line ~= "" then
                        headers[#headers + 1] = line
                    end
                end
                f:close()
            end
            i = i + 2
        else
            i = i + 1
        end
    end
end

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

local fd = C.socket(2, 1, 0) -- AF_INET, SOCK_STREAM
if fd < 0 then
    io.stderr:write("socket() failed\n")
    os.exit(1)
end

local addr = ffi.new("struct sockaddr_in")
addr.sin_family = 2
addr.sin_port = C.htons(port)
addr.sin_addr = C.inet_addr("127.0.0.1")

if C.connect(fd, addr, ffi.sizeof(addr)) ~= 0 then
    io.stderr:write("connect() failed on port " .. port .. "\n")
    os.exit(1)
end

local lines = { "GET " .. path .. " HTTP/1.0", "Host: localhost", "Connection: close" }
for _, h in ipairs(headers) do
    lines[#lines + 1] = h
end
local req = table.concat(lines, "\r\n") .. "\r\n\r\n"
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
local status = raw:match("^HTTP/%d%.%d (%d+)") or "000"
local body = raw:match("\r\n\r\n(.*)$") or ""

-- Keep output to two lines so the shell runner can parse it, but show enough
-- body to be useful.
body = body:gsub("\n", "\\n")
if #body > 220 then
    body = body:sub(1, 220) .. "..."
end

print(status)
print(body)
