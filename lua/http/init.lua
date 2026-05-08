local M = {}

---@param user_config? table
M.setup = function(user_config)
    require("http.setup").setup(user_config)
    require("http.highlight")
    require("http.autocmds")
end

M.open = function()
    require("http.actions").open()
end

M.close = function()
    require("http.actions").close()
end

M.toggle = function()
    require("http.actions").toggle()
end

--- Run an HTTP request.
--- opts.file    = "/path/to/request.http"
--- opts.request = { method, url, headers, body }
---@param opts table
M.run = function(opts)
    require("http.actions").run_request(opts)
end

---@param view string
M.show_view = function(view)
    require("http.actions").show_view(view)
end

---@param opts {count: integer, wrap: boolean}
M.navigate = function(opts)
    require("http.actions").navigate(opts)
end

--- Convert between curl and .http format.
--- source may be: nil (prompts), a curl string, or a request struct table.
---@param source? string|table
M.convert = function(source)
    require("http.actions").convert(source)
end

return M
