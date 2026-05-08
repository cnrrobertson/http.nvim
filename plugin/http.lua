if vim.g.loaded_http_nvim then return end
vim.g.loaded_http_nvim = true

local api = vim.api

local subcommands = {
    open = {
        impl = function(_args, _opts)
            require("http").open()
        end,
    },
    close = {
        impl = function(_args, _opts)
            require("http").close()
        end,
    },
    toggle = {
        impl = function(_args, _opts)
            require("http").toggle()
        end,
    },
    run = {
        impl = function(args, opts)
            -- With a range (visual selection): treat selection as curl command
            if opts.range > 0 then
                local lines = api.nvim_buf_get_lines(0, opts.line1 - 1, opts.line2, false)
                local text  = table.concat(lines, "\n"):gsub("^%s+", "")
                if text:match("^curl") then
                    -- Parse curl and run directly
                    local request = require("http.parser.curl").parse(text)
                    require("http").run({ request = request })
                else
                    vim.notify("[http] Visual selection must be a curl command to run",
                        vim.log.levels.WARN)
                end
                return
            end

            -- Explicit file argument
            local file = args[1]
            if file and file ~= "" then
                require("http").run({ file = vim.fn.expand(file) })
                return
            end

            -- No argument: use current buffer if it's a .http file
            local buf_name = api.nvim_buf_get_name(0)
            if buf_name:match("%.http$") then
                require("http").run({ file = buf_name })
            else
                vim.notify("[http] Current buffer is not a .http file. "
                    .. "Use :Http run <file> or open a .http file.",
                    vim.log.levels.WARN)
            end
        end,
        range = true,
        complete = function(arg_lead)
            return vim.fn.getcompletion(arg_lead, "file")
        end,
    },
    view = {
        impl = function(args, _opts)
            local v = args[1]
            if not v or v == "" then
                vim.notify("[http] Usage: Http view <name>", vim.log.levels.WARN)
                return
            end
            require("http").show_view(v)
        end,
        complete = function(arg_lead)
            local sections = require("http.setup").config.winbar.sections
            return vim.iter(sections)
                :filter(function(s) return s:find(arg_lead, 1, true) == 1 end)
                :totable()
        end,
    },
    navigate = {
        impl = function(args, opts)
            local count = tonumber(args[1]) or 1
            require("http").navigate({ count = count, wrap = opts.bang })
        end,
        bang = true,
    },
    convert = {
        impl = function(args, opts)
            -- With a range: convert the selected lines
            if opts.range > 0 then
                local lines = api.nvim_buf_get_lines(0, opts.line1 - 1, opts.line2, false)
                local text  = table.concat(lines, "\n")
                require("http").convert(text)
                return
            end

            -- Optional inline curl string
            local curl_str = args[1] and table.concat(args, " ") or nil
            if curl_str and curl_str ~= "" then
                require("http").convert(curl_str)
            else
                -- Prompt for paste
                require("http").convert()
            end
        end,
        range = true,
    },
}

local function complete(arg_lead, cmdline, _cursor_pos)
    if cmdline:match("^Http%s+%S*$") then
        return vim.iter(vim.tbl_keys(subcommands))
            :filter(function(k) return k:find(arg_lead, 1, true) == 1 end)
            :totable()
    end
    local subcmd_key = cmdline:match("^Http%s+(%S+)%s+")
    if subcmd_key and subcommands[subcmd_key] and subcommands[subcmd_key].complete then
        return subcommands[subcmd_key].complete(arg_lead)
    end
    return {}
end

local function dispatch(opts)
    local fargs = opts.fargs
    local key   = fargs[1]
    local args  = vim.list_slice(fargs, 2, #fargs)
    local sub   = subcommands[key]
    if not sub then
        vim.notify("[http] Unknown subcommand: " .. tostring(key), vim.log.levels.ERROR)
        return
    end
    sub.impl(args, opts)
end

api.nvim_create_user_command("Http", dispatch, {
    nargs    = "*",
    range    = true,
    bang     = true,
    complete = complete,
    desc     = "http.nvim — HTTP client",
})
