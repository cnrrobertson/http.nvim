local state   = require("http.state")
local util    = require("http.util")
local views   = require("http.views")
local globals = require("http.globals")

local M = {}

local MAX_DEPTH = 8

--- Recursively unwrap string values that contain JSON objects/arrays.
--- Also expands \n and \t escape sequences in string values.
---@param val any
---@param depth integer
---@return any
local function unwrap(val, depth)
    if depth > MAX_DEPTH then return val end

    if type(val) == "string" then
        -- Expand escape sequences
        local expanded = val:gsub("\\n", "\n"):gsub("\\t", "\t")

        -- Attempt to parse as JSON if it looks like an object or array
        local trimmed = vim.trim(expanded)
        if trimmed:sub(1, 1) == "{" or trimmed:sub(1, 1) == "[" then
            local ok, decoded = pcall(vim.fn.json_decode, trimmed)
            if ok and decoded ~= nil and type(decoded) ~= "string" then
                return unwrap(decoded, depth + 1)
            end
        end

        return expanded

    elseif type(val) == "table" then
        local result = {}
        for k, v in pairs(val) do
            result[k] = unwrap(v, depth + 1)
        end
        return result
    end

    return val
end

--- Pretty-print a value recursively, returning an array of lines.
---@param body string  raw response body
---@return string pretty, boolean ok
local function format_body(body)
    local ok, decoded = pcall(vim.fn.json_decode, body)
    if not ok or decoded == nil then return body, false end

    local unwrapped = unwrap(decoded, 0)

    -- Re-encode with indentation
    local ok2, pretty = pcall(function()
        return vim.json and vim.json.encode and vim.json.encode(unwrapped, { indent = "  " })
    end)
    if ok2 and pretty then return pretty, true end

    local ok3, encoded = pcall(vim.fn.json_encode, unwrapped)
    if ok3 then return encoded, true end

    return body, false
end

---@param bufnr integer
M.show = function(bufnr)
    if not util.is_buf_valid(bufnr) or not util.is_win_valid(state.winnr) then return end

    if views.cleanup_view(bufnr, not state.response_data, "  Run a request to see the response") then
        return
    end

    local req     = state.last_request or {}
    local status  = state.response_status or 0
    local elapsed = state.response_elapsed_ms
    local body    = state.response_data or ""

    local elapsed_str = elapsed and string.format("%.0fms", elapsed) or "?"
    local hint = string.format("  %d  %s %s  (%s)",
        status, req.method or "?", req.url or "?", elapsed_str)

    local display_body, is_formatted = format_body(body)

    local body_lines = vim.split(display_body, "\n", { plain = true })
    local lines = { hint, "" }
    vim.list_extend(lines, body_lines)

    vim.bo[bufnr].modifiable = true
    vim.bo[bufnr].filetype   = is_formatted and "json" or "text"
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.bo[bufnr].modifiable = false

    -- Highlight status code
    local ns = globals.NAMESPACE
    local hl = (status >= 200 and status < 300) and "HttpStatusOk"
            or (status >= 300 and status < 400) and "HttpStatusWarn"
            or "HttpStatusErr"
    local status_str = tostring(status)
    vim.hl.range(bufnr, ns, hl, { 0, 2 }, { 0, 2 + #status_str })
    vim.hl.range(bufnr, ns, "HttpHint", { 0, 2 + #status_str }, { 0, #hint })

    -- Keymap: yank formatted body
    vim.keymap.set("n", "y", function()
        vim.fn.setreg("+", display_body)
        vim.notify("[http] Formatted body yanked", vim.log.levels.INFO)
    end, { buffer = bufnr, nowait = true, desc = "Yank formatted body" })

    -- Keymap: export to file
    vim.keymap.set("n", "e", function()
        local ext = is_formatted and ".json" or ".txt"
        local default = vim.fn.expand("~/Downloads/http-response-formatted" .. ext)
        vim.ui.input({ prompt = "Export to: ", default = default }, function(path)
            if not path or path == "" then return end
            path = vim.fn.expand(path)
            local f, err = io.open(path, "w")
            if not f then
                vim.notify("[http] Export failed: " .. (err or "?"), vim.log.levels.ERROR)
                return
            end
            f:write(display_body)
            f:close()
            vim.notify("[http] Exported to " .. path, vim.log.levels.INFO)
        end)
    end, { buffer = bufnr, nowait = true, desc = "Export formatted response to file" })
end

return M
