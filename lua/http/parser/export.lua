--- Convert a request struct to a curl command string.

local M = {}

--- Wrap a string in single quotes, escaping any single quotes within.
---@param s string
---@return string
local function sq(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

--- Convert a request struct to a multiline curl command.
---@param request table  {method, url, headers, body}
---@return string
M.to_curl = function(request)
    local parts = { "curl -X " .. (request.method or "GET") .. " " .. sq(request.url or "") }

    for k, v in pairs(request.headers or {}) do
        table.insert(parts, "  -H " .. sq(k .. ": " .. v))
    end

    if request.body and request.body ~= "" then
        table.insert(parts, "  -d " .. sq(request.body))
    end

    return table.concat(parts, " \\\n")
end

return M
