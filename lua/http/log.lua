local state = require("http.state")

local M = {}

M.append = function(msg)
    local ts = os.date("%H:%M:%S")
    table.insert(state.debug_log, "[" .. ts .. "] " .. msg)
end

return M
