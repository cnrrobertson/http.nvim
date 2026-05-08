--- {{var}} substitution in request fields.

local M = {}

--- Replace all {{key}} occurrences in a string.
--- Unknown variables are left as-is.
---@param str string
---@param vars table<string,string>
---@return string
M.substitute = function(str, vars)
    if not str or not vars then return str end
    return (str:gsub("{{([^}]+)}}", function(key)
        local val = vars[vim.trim(key)]
        return val ~= nil and tostring(val) or ("{{" .. key .. "}}")
    end))
end

--- Apply substitution to all fields of a request struct.
--- Returns a new struct (does not mutate the original).
---@param request table
---@param vars table<string,string>
---@return table
M.apply = function(request, vars)
    if not vars or vim.tbl_isempty(vars) then return request end

    local subst = M.substitute
    local new_headers = {}
    for k, v in pairs(request.headers or {}) do
        new_headers[subst(k, vars)] = subst(v, vars)
    end

    return {
        method  = request.method,
        url     = subst(request.url, vars),
        headers = new_headers,
        body    = subst(request.body, vars),
        scripts = request.scripts,
    }
end

return M
