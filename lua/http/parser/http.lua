--- Parse a .http file into a request struct.
---
--- Format:
---   # @script ./auth.lua      (optional, one or more, anywhere before body)
---   METHOD URL                (required; URL alone implies GET)
---   Header-Name: value        (optional)
---   ...
---                             (blank line separates headers from body)
---   body content here         (optional)

local M = {}

---@class http.Request
---@field method  string
---@field url     string
---@field headers table<string,string>
---@field body    string
---@field scripts string[]   paths from # @script directives

--- Parse a .http file from a list of lines.
---@param lines string[]
---@return http.Request
M.parse_lines = function(lines)
    local scripts = {}
    local method  = nil
    local url     = nil
    local headers = {}
    local body_lines = {}

    local STATE_PREAMBLE = 1   -- before method line
    local STATE_HEADERS  = 2   -- after method, reading headers
    local STATE_BODY     = 3   -- after blank line

    local st = STATE_PREAMBLE

    for _, raw_line in ipairs(lines) do
        local line = raw_line:gsub("\r$", "")  -- strip CR

        if st == STATE_PREAMBLE then
            -- Collect # @script directives
            local script_path = line:match("^#%s*@script%s+(.+)$")
            if script_path then
                table.insert(scripts, vim.trim(script_path))
            elseif line:match("^%s*#") or line:match("^%s*$") then
                -- other comments or blank lines — skip
            else
                -- First non-comment, non-blank line is the method/URL line
                local m, u = line:match("^(%u+)%s+(.+)$")
                if m and u then
                    method = m
                    url    = vim.trim(u)
                else
                    -- URL only → GET
                    method = "GET"
                    url    = vim.trim(line)
                end
                st = STATE_HEADERS
            end

        elseif st == STATE_HEADERS then
            if line:match("^%s*$") then
                st = STATE_BODY
            else
                -- Collect # @script directives even in header section (before blank line)
                local script_path = line:match("^#%s*@script%s+(.+)$")
                if script_path then
                    table.insert(scripts, vim.trim(script_path))
                else
                    local k, v = line:match("^([^:]+):%s*(.*)$")
                    if k and v then
                        headers[k] = v
                    end
                end
            end

        elseif st == STATE_BODY then
            table.insert(body_lines, line)
        end
    end

    -- Trim trailing blank lines from body
    while #body_lines > 0 and body_lines[#body_lines]:match("^%s*$") do
        table.remove(body_lines)
    end

    return {
        method  = method or "GET",
        url     = url or "",
        headers = headers,
        body    = table.concat(body_lines, "\n"),
        scripts = scripts,
    }
end

--- Parse a .http file from disk.
---@param path string
---@return http.Request?, string? err
M.parse_file = function(path)
    local f, err = io.open(path, "r")
    if not f then
        return nil, "Cannot open file: " .. (err or path)
    end
    local content = f:read("*a")
    f:close()

    local lines = vim.split(content, "\n", { plain = true })
    return M.parse_lines(lines), nil
end

--- Serialize a request struct back to .http format.
---@param request http.Request
---@return string
M.to_string = function(request)
    local parts = {}

    for _, s in ipairs(request.scripts or {}) do
        table.insert(parts, "# @script " .. s)
    end
    if #(request.scripts or {}) > 0 then
        table.insert(parts, "")
    end

    table.insert(parts, (request.method or "GET") .. " " .. (request.url or ""))

    for k, v in pairs(request.headers or {}) do
        table.insert(parts, k .. ": " .. v)
    end

    if request.body and request.body ~= "" then
        table.insert(parts, "")
        table.insert(parts, request.body)
    end

    return table.concat(parts, "\n")
end

return M
