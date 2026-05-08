local state   = require("http.state")
local util    = require("http.util")
local views   = require("http.views")
local globals = require("http.globals")
local persist = require("http.persist")

local M = {}

local api = vim.api

local function fmt_ms(n)
    if not n then return "?" end
    n = tonumber(n)
    if not n then return "?" end
    if n >= 1000 then return string.format("%.1fs", n / 1000)
    else return string.format("%dms", n) end
end

local function find_original(ts)
    for i, e in ipairs(state.history) do
        if e.ts == ts then return i, e end
    end
end

---@param bufnr integer
M.show = function(bufnr)
    if not util.is_buf_valid(bufnr) or not util.is_win_valid(state.winnr) then return end

    if views.cleanup_view(bufnr, #state.history == 0, "  No request history") then
        return
    end

    -- Newest first
    local entries = vim.deepcopy(state.history)
    for i = 1, math.floor(#entries / 2) do
        entries[i], entries[#entries - i + 1] = entries[#entries - i + 1], entries[i]
    end

    local hint   = "  <CR> load · r re-run · o details · n rename · y curl"
    local lines  = { hint }
    local status_positions = {}

    for _, entry in ipairs(entries) do
        local time_str = os.date("%H:%M:%S", entry.ts)
        local status_icon, hl_group
        if entry.status == "ok" then
            status_icon = "✓"
            hl_group    = "HttpHistoryOk"
        elseif entry.status == "error" then
            status_icon = "✗"
            hl_group    = "HttpHistoryErr"
        else
            status_icon = "…"
            hl_group    = "HttpLoading"
        end

        local elapsed   = fmt_ms(entry.elapsed_ms)
        local http_code = entry.http_status and tostring(entry.http_status) or "---"
        local cache_dot = entry.response_id and "●" or " "

        local label
        if entry.name and entry.name ~= "" then
            label = "[" .. entry.name .. "]"
        else
            local method = entry.method or "?"
            local url    = entry.url or ""
            local preview = method .. " " .. url
            if #preview > 55 then preview = preview:sub(1, 52) .. "..." end
            label = preview
        end

        local line = string.format("[%s] %s %s  %s  %-5s  %s",
            time_str, status_icon, cache_dot, elapsed, http_code, label)

        table.insert(status_positions, { #lines, 11, 11 + #status_icon, hl_group })
        if entry.response_id then
            table.insert(status_positions, { #lines, 14, 17, "Comment" })
        end
        table.insert(lines, line)
    end

    util.set_lines(bufnr, 0, -1, false, lines)

    local ns = globals.NAMESPACE
    vim.hl.range(bufnr, ns, "HttpHint", { 0, 0 }, { 0, #hint })
    for _, pos in ipairs(status_positions) do
        vim.hl.range(bufnr, ns, pos[4], { pos[1], pos[2] }, { pos[1], pos[3] })
    end

    -- <CR>: load cached response if available, otherwise re-run
    vim.keymap.set("n", "<CR>", function()
        if not util.is_win_valid(state.winnr) then return end
        local entry = entries[api.nvim_win_get_cursor(state.winnr)[1] - 1]
        if not entry then return end

        if entry.response_id then
            local body = persist.load_response(entry.response_id)
            if body then
                state.response_data      = body
                state.response_headers   = entry.response_headers or {}
                state.response_status    = entry.http_status
                state.response_elapsed_ms = entry.elapsed_ms
                state.last_request       = { method = entry.method, url = entry.url,
                                              headers = entry.request_headers or {},
                                              body = entry.request_body or "" }
                require("http.views").switch_to_view("response")
                vim.notify(("[http] Loaded cached response (%d bytes)"):format(#body),
                    vim.log.levels.INFO)
                return
            end
            vim.notify("[http] Cache missing — re-running…", vim.log.levels.WARN)
        end

        require("http").run({ request = {
            method  = entry.method  or "GET",
            url     = entry.url     or "",
            headers = entry.request_headers or {},
            body    = entry.request_body or "",
            scripts = {},
        }})
    end, { buffer = bufnr, nowait = true, desc = "Load cached response or re-run" })

    -- r: always force re-run
    vim.keymap.set("n", "r", function()
        if not util.is_win_valid(state.winnr) then return end
        local entry = entries[api.nvim_win_get_cursor(state.winnr)[1] - 1]
        if not entry then return end
        require("http").run({ request = {
            method  = entry.method  or "GET",
            url     = entry.url     or "",
            headers = entry.request_headers or {},
            body    = entry.request_body or "",
            scripts = {},
        }})
    end, { buffer = bufnr, nowait = true, desc = "Force re-run request" })

    -- o: show request details in a float
    vim.keymap.set("n", "o", function()
        if not util.is_win_valid(state.winnr) then return end
        local entry = entries[api.nvim_win_get_cursor(state.winnr)[1] - 1]
        if not entry then return end

        local detail_lines = {
            (entry.method or "GET") .. " " .. (entry.url or ""),
            "",
        }
        for k, v in pairs(entry.request_headers or {}) do
            table.insert(detail_lines, k .. ": " .. v)
        end
        if entry.request_body and entry.request_body ~= "" then
            table.insert(detail_lines, "")
            vim.list_extend(detail_lines, vim.split(entry.request_body, "\n", { plain = true }))
        end

        local max_w = math.max(40, math.floor(vim.o.columns * 0.75))
        local content_w = 0
        for _, l in ipairs(detail_lines) do content_w = math.max(content_w, #l) end
        local width  = math.min(max_w, content_w + 4)
        local height = math.min(math.floor(vim.o.lines * 0.6), #detail_lines + 2)
        height = math.max(height, 3)

        local float_buf = api.nvim_create_buf(false, true)
        api.nvim_buf_set_lines(float_buf, 0, -1, false, detail_lines)
        vim.bo[float_buf].modifiable = false
        vim.bo[float_buf].filetype   = "http"

        local title = entry.name and (" " .. entry.name .. " ") or " Request "
        local win   = api.nvim_open_win(float_buf, true, {
            relative  = "editor",
            width     = width,
            height    = height,
            row       = math.floor((vim.o.lines - height) / 2),
            col       = math.floor((vim.o.columns - width) / 2),
            style     = "minimal",
            border    = "rounded",
            title     = title,
            title_pos = "center",
        })
        vim.wo[win].wrap = true

        for _, key in ipairs({ "q", "<Esc>" }) do
            vim.keymap.set("n", key, function()
                pcall(api.nvim_win_close, win, true)
            end, { buffer = float_buf, nowait = true })
        end
    end, { buffer = bufnr, nowait = true, desc = "Show request details" })

    -- n: rename entry
    vim.keymap.set("n", "n", function()
        if not util.is_win_valid(state.winnr) then return end
        local entry = entries[api.nvim_win_get_cursor(state.winnr)[1] - 1]
        if not entry then return end

        local _, orig = find_original(entry.ts)
        if not orig then return end

        vim.ui.input({
            prompt  = "Request name (empty to clear): ",
            default = orig.name or "",
        }, function(input)
            if input == nil then return end
            orig.name = (input ~= "" and input or nil)
            persist.save_history()
            M.show(bufnr)
        end)
    end, { buffer = bufnr, nowait = true, desc = "Name / rename entry" })

    -- y: yank as curl command
    vim.keymap.set("n", "y", function()
        if not util.is_win_valid(state.winnr) then return end
        local entry = entries[api.nvim_win_get_cursor(state.winnr)[1] - 1]
        if not entry then return end

        local curl_str = require("http.parser.export").to_curl({
            method  = entry.method  or "GET",
            url     = entry.url     or "",
            headers = entry.request_headers or {},
            body    = entry.request_body or "",
        })
        vim.fn.setreg("+", curl_str)
        vim.notify("[http] curl command yanked", vim.log.levels.INFO)
    end, { buffer = bufnr, nowait = true, desc = "Yank as curl" })
end

return M
