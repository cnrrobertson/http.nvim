local state   = require("http.state")
local util    = require("http.util")
local views   = require("http.views")
local globals = require("http.globals")

local M = {}

---@param bufnr integer
M.show = function(bufnr)
    if not util.is_buf_valid(bufnr) or not util.is_win_valid(state.winnr) then return end

    local has_data = state.last_request ~= nil or state.response_headers ~= nil
    if views.cleanup_view(bufnr, not has_data, "  Run a request to see headers") then
        return
    end

    local req      = state.last_request or {}
    local req_hdrs = req.headers or {}
    local res_hdrs = state.response_headers or {}

    -- Compute key column width
    local key_w = 0
    for k, _ in pairs(req_hdrs) do key_w = math.max(key_w, #k) end
    for k, _ in pairs(res_hdrs) do key_w = math.max(key_w, #k) end
    key_w = math.min(key_w, 40)

    local lines      = {}
    local key_ranges = {}

    -- Request headers section
    table.insert(lines, "  Request Headers")
    table.insert(key_ranges, nil)  -- section label, not a key

    local req_keys = vim.tbl_keys(req_hdrs)
    table.sort(req_keys)
    for _, k in ipairs(req_keys) do
        local pad  = string.rep(" ", key_w - #k)
        local line = "  " .. k .. pad .. "  " .. tostring(req_hdrs[k])
        table.insert(key_ranges, { #lines, 2, 2 + #k })
        table.insert(lines, line)
    end
    if #req_keys == 0 then
        table.insert(lines, "  (none)")
        table.insert(key_ranges, nil)
    end

    table.insert(lines, "")
    table.insert(key_ranges, nil)

    -- Response headers section
    local status = state.response_status or 0
    table.insert(lines, "  Response Headers  (" .. tostring(status) .. ")")
    table.insert(key_ranges, nil)

    local res_keys = vim.tbl_keys(res_hdrs)
    table.sort(res_keys)
    for _, k in ipairs(res_keys) do
        local pad  = string.rep(" ", key_w - math.min(#k, key_w))
        local line = "  " .. k .. pad .. "  " .. tostring(res_hdrs[k])
        table.insert(key_ranges, { #lines, 2, 2 + #k })
        table.insert(lines, line)
    end
    if #res_keys == 0 then
        table.insert(lines, "  (none)")
        table.insert(key_ranges, nil)
    end

    util.set_lines(bufnr, 0, -1, false, lines)

    local ns = globals.NAMESPACE

    -- Highlight section labels
    vim.hl.range(bufnr, ns, "HttpHeader", { 0, 2 }, { 0, #lines[1] })
    -- Find the response headers section label line index
    local res_label_idx = #req_keys + (req_keys and 1 or 0) + 2  -- approx
    for li, l in ipairs(lines) do
        if l:match("^  Response Headers") then
            vim.hl.range(bufnr, ns, "HttpHeader", { li - 1, 2 }, { li - 1, #l })
            break
        end
    end

    -- Highlight key names
    for li, r in ipairs(key_ranges) do
        if r then
            vim.hl.range(bufnr, ns, "HttpStatKey", { li - 1, r[2] }, { li - 1, r[3] })
        end
    end

    -- Keymap: yank all headers
    vim.keymap.set("n", "y", function()
        local out = { "Request Headers:", "" }
        for _, k in ipairs(req_keys) do
            table.insert(out, k .. ": " .. tostring(req_hdrs[k]))
        end
        table.insert(out, "")
        table.insert(out, "Response Headers:")
        table.insert(out, "")
        for _, k in ipairs(res_keys) do
            table.insert(out, k .. ": " .. tostring(res_hdrs[k]))
        end
        vim.fn.setreg("+", table.concat(out, "\n"))
        vim.notify("[http] Headers yanked", vim.log.levels.INFO)
    end, { buffer = bufnr, nowait = true, desc = "Yank all headers" })
end

return M
