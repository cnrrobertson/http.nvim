local state = require("http.state")
local util  = require("http.util")
local views = require("http.views")

local M = {}

---@param bufnr integer
M.show = function(bufnr)
    if not util.is_buf_valid(bufnr) or not util.is_win_valid(state.winnr) then return end

    if views.cleanup_view(bufnr, #state.debug_log == 0, "  No debug output yet") then
        return
    end

    util.set_lines(bufnr, 0, -1, false, state.debug_log)
end

return M
