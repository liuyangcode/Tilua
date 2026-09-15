--- Tilua.logging.writer
--- Output backends: file / stderr / ngx / multi

local path_util = require("Tilua.utils.path")

local Writer = {}

local function ensure_dir(dir)
    if not dir or dir == "" then
        return
    end
    if path_util.isdir and path_util.isdir(dir) then
        return true
    end
    if path_util.mkdir then
        pcall(path_util.mkdir, dir)
        return true
    end
    pcall(function()
        os.execute("mkdir -p '" .. dir:gsub("'", "'\\''") .. "'")
    end)
    return true
end

local function today_name()
    return os.date("%Y_%m_%d")
end

--- File writer (buffered lines, flush on request end)
function Writer.file(config)
    config = config or {}
    local w = {
        type = "file",
        path = config.path or "log",
        buffer = {},
    }

    function w:write_line(line)
        self.buffer[#self.buffer + 1] = line
    end

    function w:flush()
        if #self.buffer == 0 then
            return
        end
        ensure_dir(self.path)
        local file_path = self.path .. "/" .. today_name() .. ".log"
        local f, err = io.open(file_path, "a+")
        if not f then
            if ngx then
                ngx.log(ngx.ERR, "log open failed: ", err, " ", file_path)
            end
            self.buffer = {}
            return
        end
        for i = 1, #self.buffer do
            f:write(self.buffer[i], "\n")
        end
        f:close()
        self.buffer = {}
    end

    function w:close()
        self:flush()
    end

    return w
end

--- Direct ngx.log (no buffer)
function Writer.ngx(config)
    local level_map = {
        EMERG = ngx and ngx.EMERG,
        ALERT = ngx and ngx.ALERT,
        CRIT = ngx and ngx.CRIT,
        ERR = ngx and ngx.ERR,
        ERROR = ngx and ngx.ERR,
        WARN = ngx and ngx.WARN,
        WARNING = ngx and ngx.WARN,
        NOTICE = ngx and ngx.NOTICE,
        INFO = ngx and ngx.INFO,
        DEBUG = ngx and ngx.DEBUG,
    }
    local w = { type = "ngx", buffer = {} }

    function w:write_line(line, level)
        if ngx and ngx.log then
            local lv = level_map[level] or level_map.INFO or ngx.INFO
            ngx.log(lv, line)
        else
            self.buffer[#self.buffer + 1] = line
        end
    end

    function w:flush() end
    function w:close() end

    return w
end

--- stderr (CLI / tests)
function Writer.stderr(config)
    local w = { type = "stderr", buffer = {} }
    function w:write_line(line)
        io.stderr:write(line, "\n")
    end
    function w:flush() end
    function w:close() end
    return w
end

--- Factory from config.type
function Writer.create(config)
    config = config or {}
    local t = string.lower(tostring(config.type or "file"))
    if t == "ngx" or t == "syslog" then
        return Writer.ngx(config)
    end
    if t == "stderr" or t == "console" then
        return Writer.stderr(config)
    end
    return Writer.file(config)
end

-- legacy adapter used by old Tilua.log.file
Writer.legacy_file = {
    init = function(config)
        ensure_dir(config and config.path)
    end,
    flush = function(log)
        local w = Writer.file(log.config)
        for _, v in ipairs(log.log_data or {}) do
            local line
            if v.level == "" or not v.level then
                line = v.msg
            else
                line = "[" .. v.level .. "]: " .. tostring(v.msg)
            end
            w:write_line(line)
        end
        w:flush()
    end,
}

return Writer
