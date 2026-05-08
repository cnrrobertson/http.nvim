local jobs  = require("http.jobs")
local setup = require("http.setup")

local M = {}

local SENTINEL = "__HTTP_STATUS_CODE__"

--- Parse the raw curl output (headers + body + sentinel) into components.
---@param raw string
---@return integer status, table headers, string body
local function parse_output(raw)
    -- Extract status code from sentinel at end: __HTTP_STATUS_CODE__NNN
    local status_str = raw:match(SENTINEL .. "(%d+)%s*$")
    local status = tonumber(status_str) or 0

    -- Strip sentinel line from end
    local content = raw:gsub("\n?" .. SENTINEL .. "%d+%s*$", "")

    -- Response headers come first (curl -D - writes them before body)
    -- Headers end at the first blank line after the status line
    -- There may be multiple header blocks (e.g. 301 redirect + 200)
    -- We want the LAST header block
    local headers = {}
    local body_start = 1

    -- Find all header blocks separated by blank lines
    -- A header block starts with HTTP/
    local last_header_end = nil
    local pos = 1
    while true do
        local http_start = content:find("^HTTP/", pos)
        if not http_start then
            -- Check if there's an HTTP/ anywhere after current pos
            local next_http = content:find("\nHTTP/", pos)
            if next_http then
                pos = next_http + 1
            else
                break
            end
        else
            -- Find end of this header block (double newline)
            local block_end = content:find("\r?\n\r?\n", http_start)
            if block_end then
                last_header_end = block_end
                pos = block_end + 2
            else
                break
            end
        end
    end

    if last_header_end then
        -- Parse headers from the last block
        local header_block = content:sub(1, last_header_end)
        -- Find the last HTTP/ line
        local last_http = 1
        local p = 1
        while true do
            local found = header_block:find("\nHTTP/", p)
            if found then
                last_http = found + 1
                p = found + 1
            else
                break
            end
        end
        -- Also check if block starts with HTTP/
        if header_block:sub(1, 5) == "HTTP/" and last_http == 1 then
            last_http = 1
        end

        local hblock = header_block:sub(last_http)
        for line in hblock:gmatch("[^\r\n]+") do
            if not line:match("^HTTP/") then
                local k, v = line:match("^([^:]+):%s*(.*)$")
                if k and v then
                    headers[k:lower()] = v
                end
            end
        end
        -- Body is everything after the blank line following last header block
        local body_pos = content:find("\r?\n\r?\n", last_header_end)
        if body_pos then
            body_start = body_pos + (content:sub(body_pos, body_pos + 1) == "\r\n" and 4 or 2)
        else
            body_start = last_header_end + 2
        end
    end

    local body = content:sub(body_start)
    return status, headers, body
end

--- Build curl argv from a request struct.
---@param request table  {method, url, headers, body}
---@return string[]
local function build_argv(request)
    local curl = setup.config.curl_path or "curl"
    local args = {
        curl,
        "--silent",
        "--show-error",
        "-D", "-",                    -- dump response headers to stdout
        "-w", "\n" .. SENTINEL .. "%{http_code}",  -- append status code
        "-X", request.method or "GET",
        request.url,
    }

    -- Headers
    for k, v in pairs(request.headers or {}) do
        table.insert(args, "-H")
        table.insert(args, k .. ": " .. v)
    end

    -- Body
    if request.body and request.body ~= "" then
        table.insert(args, "--data-raw")
        table.insert(args, request.body)
    end

    return args
end

--- Execute an HTTP request via curl.
---@param request table  {method, url, headers, body}
---@param on_done fun(code: integer, status: integer, headers: table, body: string)
M.run_request = function(request, on_done)
    local cmd = build_argv(request)
    local start_ts = vim.uv.now()

    jobs.run_job({
        cmd = cmd,
        on_exit = function(code, output)
            local elapsed = vim.uv.now() - start_ts
            if code ~= 0 then
                on_done(code, 0, {}, output, elapsed)
                return
            end
            local status, headers, body = parse_output(output)
            on_done(code, status, headers, body, elapsed)
        end,
    })
end

return M
