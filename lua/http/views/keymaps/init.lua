local state = require("http.state")

local M = {}

local api = vim.api

local pane_keymaps = {
    response = {
        "## Response",
        "",
        "| Key    | Action                    |",
        "|--------|---------------------------|",
        "| `y`    | Yank response body        |",
        "| `e`    | Export response to file   |",
    },
    headers = {
        "## Headers",
        "",
        "| Key    | Action                    |",
        "|--------|---------------------------|",
        "| `y`    | Yank all headers          |",
    },
    history = {
        "## History",
        "",
        "| Key    | Action                           |",
        "|--------|----------------------------------|",
        "| `<CR>` | Reload cached response (or re-run)|",
        "| `r`    | Force re-run request             |",
        "| `o`    | Show request details             |",
        "| `n`    | Name / rename entry              |",
        "| `y`    | Yank as curl command             |",
    },
    debug = {},
}

local function open_help_float(section)
    local global_lines = {
        "# http.nvim Keymaps",
        "",
        "## Global",
        "",
        "| Key          | Action              |",
        "|--------------|---------------------|",
        "| `R/H/Y/D`    | Switch view         |",
        "| `]v` / `[v`  | Navigate views      |",
        "| `gr`         | Re-run last request |",
        "| `q`          | Close panel         |",
        "| `g?`         | This help           |",
        "",
    }

    local pane  = pane_keymaps[section] or {}
    local lines = vim.list_extend(vim.deepcopy(global_lines), vim.deepcopy(pane))

    if #pane > 0 then table.insert(lines, "") end

    vim.list_extend(lines, {
        "## Commands",
        "",
        "| Command                    | Description              |",
        "|----------------------------|--------------------------|",
        "| `:Http open/close/toggle`  | Panel control            |",
        "| `:Http run [file]`         | Run .http file           |",
        "| `:Http convert`            | curl ↔ .http conversion  |",
        "| `:Http view <name>`        | Switch view              |",
        "| `:Http navigate <n>[!]`    | Navigate views           |",
    })

    local max_w     = math.max(50, math.floor(vim.o.columns * 0.60))
    local content_w = 0
    for _, l in ipairs(lines) do content_w = math.max(content_w, #l) end
    local width  = math.min(max_w, content_w + 4)
    local height = math.min(math.floor(vim.o.lines * 0.80), #lines + 2)
    height = math.max(height, 5)

    local float_buf = api.nvim_create_buf(false, true)
    api.nvim_buf_set_lines(float_buf, 0, -1, false, lines)
    vim.bo[float_buf].modifiable = false
    vim.bo[float_buf].filetype   = "markdown"

    local title = " Keymaps [" .. section .. "] "
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
    vim.wo[win].wrap        = false
    vim.wo[win].cursorline  = true
    vim.wo[win].conceallevel = 2

    for _, key in ipairs({ "q", "<Esc>" }) do
        vim.keymap.set("n", key, function()
            pcall(api.nvim_win_close, win, true)
        end, { buffer = float_buf, nowait = true })
    end

    api.nvim_create_autocmd("WinClosed", {
        pattern  = tostring(win),
        once     = true,
        callback = function()
            pcall(api.nvim_buf_delete, float_buf, { force = true })
        end,
    })
end

local function set_keymaps_for_buf(buf)
    local function map(lhs, rhs, desc)
        vim.keymap.set("n", lhs, rhs, { buffer = buf, nowait = true, desc = desc })
    end

    map("]v", function()
        require("http").navigate({ count = 1, wrap = true })
    end, "Next http section")

    map("[v", function()
        require("http").navigate({ count = -1, wrap = true })
    end, "Previous http section")

    map("q", function()
        require("http").close()
    end, "Close http panel")

    map("gr", function()
        if state.last_request then
            require("http").run({ request = state.last_request })
        else
            vim.notify("[http] No previous request to re-run", vim.log.levels.WARN)
        end
    end, "Re-run last request")

    map("g?", function()
        open_help_float(state.current_section or "response")
    end, "Show http help")
end

M.set_keymaps = function()
    for _, buf in pairs(state.bufs) do
        set_keymaps_for_buf(buf)
    end
end

return M
