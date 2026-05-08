local defaults = require("http.config")

local M = {}

---@type http.Config
M.config = vim.deepcopy(defaults)

---@param user_config? table
M.setup = function(user_config)
    M.config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), user_config or {})
    require("http.persist").setup()
end

return M
