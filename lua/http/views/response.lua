local state   = require("http.state")
local util    = require("http.util")
local views   = require("http.views")
local globals = require("http.globals")

local M = {}

local api = vim.api

--- Pretty-print JSON body using pure Lua round-trip.
---@param body string
---@return string pretty, boolean ok
local function pretty_json(body)
    local ok, decoded = pcall(vim.fn.json_decode, body)
    if not ok or decoded == nil then return body, false end
    -- vim.fn.json_encode produces compact JSON; use vim.json if available (Neovim 0.10+)
    local ok2, pretty = pcall(function()
        return vim.json and vim.json.encode and vim.json.encode(decoded, { indent = 2 })
    end)
    if ok2 and pretty then return pretty, true end
    -- Fallback: re-encode with compact then manual indent via jq if available
    -- Otherwise return compact re-encode (still valid JSON)
    local ok3, encoded = pcall(vim.fn.json_encode, decoded)
    if ok3 then return encoded, true end
    return body, false
end

--- Determine display filetype from Content-Type header value.
---@param ct string?
---@return string filetype, boolean is_json
local function content_type_ft(ct)
    if not ct then return "text", false end
    ct = ct:lower()
    if ct:find("json") then return "json", true end
    if ct:find("xml")  then return "xml",  false end
    if ct:find("html") then return "html", false end
    return "text", false
end

--- Pick highlight group for HTTP status code.
---@param status integer
---@return string
local function status_hl(status)
    if status >= 200 and status < 300 then return "HttpStatusOk"
    elseif status >= 300 and status < 400 then return "HttpStatusWarn"
    else return "HttpStatusErr"
    end
end

---@param bufnr integer
M.show = function(bufnr)
    if not util.is_buf_valid(bufnr) or not util.is_win_valid(state.winnr) then return end

    if views.cleanup_view(bufnr, not state.response_data, "  Run a request to see the response") then
        return
    end

    local req    = state.last_request or {}
    local status = state.response_status or 0
    local elapsed = state.response_elapsed_ms
    local body   = state.response_data or ""
    local ct     = (state.response_headers or {})["content-type"] or ""

    -- Hint line
    local elapsed_str = elapsed and string.format("%.0fms", elapsed) or "?"
    local hint = string.format("  %d  %s %s  (%s)",
        status, req.method or "?", req.url or "?", elapsed_str)

    local ft, is_json = content_type_ft(ct)

    -- Pretty-print body
    local display_body = body
    if is_json then
        local pretty, ok = pretty_json(body)
        if ok then display_body = pretty end
    end

    local body_lines = vim.split(display_body, "\n", { plain = true })
    local lines = { hint, "" }
    vim.list_extend(lines, body_lines)

    -- Temporarily allow filetype change
    vim.bo[bufnr].modifiable = true
    vim.bo[bufnr].filetype   = ft
    api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.bo[bufnr].modifiable = false

    -- Highlight status code in hint line
    local ns = globals.NAMESPACE
    local hl = status_hl(status)
    -- Status code starts at col 2 (after "  ")
    local status_str = tostring(status)
    vim.hl.range(bufnr, ns, hl, { 0, 2 }, { 0, 2 + #status_str })

    -- Dim the rest of the hint line
    vim.hl.range(bufnr, ns, "HttpHint",
        { 0, 2 + #status_str },
        { 0, #hint })

    -- Keymap: yank body
    vim.keymap.set("n", "y", function()
        vim.fn.setreg("+", body)
        vim.notify("[http] Response body yanked", vim.log.levels.INFO)
    end, { buffer = bufnr, nowait = true, desc = "Yank response body" })

    -- Keymap: export body to file
    vim.keymap.set("n", "e", function()
        local ext = ft == "json" and ".json" or ft == "xml" and ".xml" or ".txt"
        local default = vim.fn.expand("~/Downloads/http-response" .. ext)
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
    end, { buffer = bufnr, nowait = true, desc = "Export response to file" })
end

return M
