---@class http.State
---@field bufs table<string, integer>
---@field winnr? integer           virtual field — resolves to tab_wins[current_tabpage]
---@field tab_wins table<integer, integer>
---@field current_section? string
---@field cur_pos table<string, integer[]>
---@field current_job? integer
---@field last_request? table      parsed request struct from last run
---@field response_data? string    raw response body
---@field response_headers? table  response headers k/v
---@field response_status? integer HTTP status code
---@field response_elapsed_ms? integer
---@field history table
---@field debug_log string[]

local _tab_wins = {}

local M = {
    bufs               = {},
    tab_wins           = _tab_wins,
    cur_pos            = {},
    last_request       = nil,
    response_data      = nil,
    response_headers   = nil,
    response_status    = nil,
    response_elapsed_ms = nil,
    history            = {},
    debug_log          = {},
}

setmetatable(M, {
    __index = function(_, k)
        if k == "winnr" then
            return _tab_wins[vim.api.nvim_get_current_tabpage()]
        end
    end,
    __newindex = function(t, k, v)
        if k == "winnr" then
            _tab_wins[vim.api.nvim_get_current_tabpage()] = v
        else
            rawset(t, k, v)
        end
    end,
})

return M
