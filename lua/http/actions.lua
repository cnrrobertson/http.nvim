local state   = require("http.state")
local setup   = require("http.setup")
local util    = require("http.util")
local globals = require("http.globals")
local winbar  = require("http.options.winbar")
local persist = require("http.persist")

local M = {}

local api = vim.api

M.toggle = function()
    if util.is_win_valid(state.winnr) then
        M.close()
    else
        M.open()
    end
end

M.close = function()
    local winnr  = state.winnr
    state.winnr  = nil

    if util.is_win_valid(winnr) then
        pcall(api.nvim_win_close, winnr, true)
    end

    if vim.tbl_isempty(state.tab_wins) then
        for _, bufnr in pairs(state.bufs) do
            if util.is_buf_valid(bufnr) then
                pcall(api.nvim_buf_delete, bufnr, { force = true })
            end
        end
        state.bufs = {}
    end
end

M.open = function()
    if util.is_win_valid(state.winnr) then
        local existing = state.winnr
        state.winnr    = nil
        pcall(api.nvim_win_close, existing, true)
    end

    local cfg        = setup.config.windows
    local pos        = cfg.position
    local is_vertical = pos == "above" or pos == "below"
    local size_      = cfg.size
    local size       = size_ < 1
        and math.floor((is_vertical and vim.go.lines or vim.go.columns) * size_)
        or math.floor(size_)

    local sections = setup.config.winbar.sections
    for _, section in ipairs(sections) do
        if not util.is_buf_valid(state.bufs[section]) then
            local bufnr = api.nvim_create_buf(false, false)
            assert(bufnr ~= 0, "[http] Failed to create buffer for " .. section)
            local name = globals.buf_name(section)
            for _, buf in ipairs(api.nvim_list_bufs()) do
                if buf ~= bufnr and api.nvim_buf_get_name(buf) == name then
                    pcall(api.nvim_buf_delete, buf, { force = true })
                end
            end
            api.nvim_buf_set_name(bufnr, name)
            require("http.views.options").set_buf_options(bufnr)
            state.bufs[section] = bufnr
        end
    end

    local initial_section = state.current_section or setup.config.winbar.default_section
    local initial_buf     = state.bufs[initial_section]

    local winnr = api.nvim_open_win(initial_buf, false, {
        split  = pos,
        win    = -1,
        height = is_vertical and size or nil,
        width  = not is_vertical and size or nil,
    })
    assert(winnr ~= 0, "[http] Failed to open window")
    state.winnr = winnr

    vim.w[winnr].http_win = true

    require("http.views.options").set_win_options()
    require("http.views.keymaps").set_keymaps()

    state.current_section = initial_section

    winbar.set_action_keymaps()
    winbar.show_content(state.current_section)

    local tabid = vim.api.nvim_get_current_tabpage()

    api.nvim_create_autocmd("WinClosed", {
        pattern  = tostring(winnr),
        once     = true,
        callback = function()
            if state.tab_wins[tabid] == winnr then
                state.tab_wins[tabid] = nil
            end
            if vim.tbl_isempty(state.tab_wins) then
                for _, bufnr in pairs(state.bufs) do
                    if util.is_buf_valid(bufnr) then
                        pcall(api.nvim_buf_delete, bufnr, { force = true })
                    end
                end
                state.bufs = {}
            end
        end,
    })
end

---@param opts {count: integer, wrap: boolean}
M.navigate = function(opts)
    local sections = setup.config.winbar.sections
    local current  = state.current_section
    local idx      = 1
    for i, v in ipairs(sections) do
        if v == current then idx = i; break end
    end

    local new_idx = idx + (opts.count or 1)
    if opts.wrap then
        new_idx = ((new_idx - 1) % #sections) + 1
    else
        new_idx = math.max(1, math.min(#sections, new_idx))
    end

    require("http.views").switch_to_view(sections[new_idx])
end

---@param view string
M.show_view = function(view)
    if not util.is_win_valid(state.winnr) then M.open() end
    require("http.views").switch_to_view(view)
end

--- Core request runner.
--- opts.file    = path to a .http file (scripts will be run)
--- opts.request = already-parsed request struct (no scripts)
---@param opts table
M.run_request = function(opts)
    if not opts then
        vim.notify("[http] run_request: no options provided", vim.log.levels.WARN)
        return
    end

    local request
    local file_path = opts.file

    if file_path then
        -- Parse the .http file
        local parsed, err = require("http.parser.http").parse_file(file_path)
        if not parsed then
            vim.notify("[http] " .. (err or "Failed to parse file"), vim.log.levels.ERROR)
            return
        end
        request = parsed

        -- Run pre-request scripts and substitute vars
        if #request.scripts > 0 then
            local base_dir = vim.fn.fnamemodify(file_path, ":h")
            local vars     = require("http.scripts").run(request.scripts, base_dir)
            request        = require("http.vars").apply(request, vars)
        end
    elseif opts.request then
        request = opts.request
    else
        vim.notify("[http] run_request: provide 'file' or 'request'", vim.log.levels.WARN)
        return
    end

    if not request.url or request.url == "" then
        vim.notify("[http] No URL in request", vim.log.levels.WARN)
        return
    end

    state.last_request = request

    -- Open panel if not already open
    if not util.is_win_valid(state.winnr) then M.open() end

    -- Show loading state
    state.current_section = "response"
    winbar.refresh_winbar("response")
    local response_buf = state.bufs["response"]
    api.nvim_buf_clear_namespace(response_buf, globals.NAMESPACE, 0, -1)
    util.set_lines(response_buf, 0, -1, false, { "  Running…  " .. (request.method or "GET") .. " " .. request.url })
    if util.is_win_valid(state.winnr) then
        local cur_buf = api.nvim_win_get_buf(state.winnr)
        if cur_buf ~= response_buf then
            vim.wo[state.winnr][0].winfixbuf = false
            api.nvim_win_set_buf(state.winnr, response_buf)
            vim.wo[state.winnr][0].winfixbuf = true
        end
    end

    -- Record pending history entry
    local history_entry = {
        method          = request.method,
        url             = request.url,
        request_headers = request.headers,
        request_body    = request.body,
        status          = "running",
        ts              = os.time(),
        elapsed_ms      = nil,
        http_status     = nil,
    }
    table.insert(state.history, history_entry)

    require("http.jobs.curl").run_request(request, function(code, http_status, headers, body, elapsed)
        history_entry.elapsed_ms      = elapsed
        history_entry.response_headers = headers

        if code ~= 0 then
            history_entry.status     = "error"
            history_entry.http_status = http_status

            state.response_data      = body
            state.response_headers   = headers
            state.response_status    = http_status
            state.response_elapsed_ms = elapsed

            require("http.views").switch_to_view("response")
            winbar.refresh_winbar("response")
            vim.notify("[http] Request failed (exit " .. code .. "): " .. (body:sub(1, 120) or ""), vim.log.levels.ERROR)
            return
        end

        history_entry.status      = "ok"
        history_entry.http_status = http_status

        state.response_data       = body
        state.response_headers    = headers
        state.response_status     = http_status
        state.response_elapsed_ms = elapsed

        -- Persist response body
        local response_id = persist.save_response(body)
        if response_id then
            history_entry.response_id = response_id
        end
        persist.save_history()

        require("http.views").switch_to_view(state.current_section or "response")
    end)
end

--- Show a float with the curl representation of a request struct or .http content.
---@param source table|string  request struct, curl string, or nil (prompts for paste)
M.convert = function(source)
    local request

    if type(source) == "table" then
        -- Already a request struct: show as curl
        local curl_str = require("http.parser.export").to_curl(source)
        M._show_convert_float(curl_str, "curl")
        return
    end

    local input_str = type(source) == "string" and source or nil

    if not input_str then
        -- Prompt user to paste a curl command
        vim.ui.input({ prompt = "Paste curl command: " }, function(s)
            if not s or s == "" then return end
            M.convert(s)
        end)
        return
    end

    -- Try parsing as curl command
    if input_str:match("^%s*curl%s") or input_str:match("^%s*curl$") then
        request = require("http.parser.curl").parse(input_str)
        local http_str = require("http.parser.http").to_string(request)
        M._show_convert_float(http_str, ".http")
    else
        -- Try parsing as .http content
        local lines = vim.split(input_str, "\n", { plain = true })
        request = require("http.parser.http").parse_lines(lines)
        local curl_str = require("http.parser.export").to_curl(request)
        M._show_convert_float(curl_str, "curl")
    end
end

--- Open a floating window showing converted content.
---@param content string
---@param label string
M._show_convert_float = function(content, label)
    local lines  = vim.split(content, "\n", { plain = true })
    local max_w  = math.max(50, math.floor(vim.o.columns * 0.75))
    local cont_w = 0
    for _, l in ipairs(lines) do cont_w = math.max(cont_w, #l) end
    local width  = math.min(max_w, cont_w + 4)
    local height = math.min(math.floor(vim.o.lines * 0.6), #lines + 2)
    height = math.max(height, 3)

    local float_buf = api.nvim_create_buf(false, true)
    api.nvim_buf_set_lines(float_buf, 0, -1, false, lines)
    vim.bo[float_buf].modifiable = false
    vim.bo[float_buf].filetype   = label == ".http" and "http" or "sh"

    local win = api.nvim_open_win(float_buf, true, {
        relative  = "editor",
        width     = width,
        height    = height,
        row       = math.floor((vim.o.lines - height) / 2),
        col       = math.floor((vim.o.columns - width) / 2),
        style     = "minimal",
        border    = "rounded",
        title     = " " .. label .. " ",
        title_pos = "center",
    })
    vim.wo[win].wrap = true

    -- y: yank content
    vim.keymap.set("n", "y", function()
        vim.fn.setreg("+", content)
        vim.notify("[http] " .. label .. " content yanked", vim.log.levels.INFO)
    end, { buffer = float_buf, nowait = true })

    for _, key in ipairs({ "q", "<Esc>" }) do
        vim.keymap.set("n", key, function()
            pcall(api.nvim_win_close, win, true)
        end, { buffer = float_buf, nowait = true })
    end
end

return M
