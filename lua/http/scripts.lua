--- Run # @script directives from a .http file.
--- Each script must `return` a table. Returned tables are merged into a
--- single vars table which is used for {{var}} substitution.
---
--- Scripts are executed synchronously via dofile(). This is intentional for
--- v1 — complex auth flows that need io.popen() will block briefly.

local log = require("http.log")

local M = {}

--- Run a list of script paths and collect their returned vars.
---@param script_paths string[]  paths (may be relative)
---@param base_dir string        directory of the .http file (for relative paths)
---@return table vars            merged variables from all scripts
M.run = function(script_paths, base_dir)
    local vars = {}

    for _, rel_path in ipairs(script_paths or {}) do
        -- Resolve relative to base_dir
        local abs_path
        if rel_path:sub(1, 1) == "/" then
            abs_path = rel_path
        else
            abs_path = base_dir .. "/" .. rel_path:gsub("^%./", "")
        end

        log.append("SCRIPT " .. abs_path)

        local ok, result = pcall(dofile, abs_path)
        if not ok then
            vim.notify("[http] Script error in " .. abs_path .. ": " .. tostring(result),
                vim.log.levels.ERROR)
        elseif type(result) == "table" then
            for k, v in pairs(result) do
                vars[k] = tostring(v)
            end
            log.append("SCRIPT OK — " .. vim.inspect(result):sub(1, 120))
        else
            vim.notify("[http] Script " .. abs_path .. " did not return a table (got "
                .. type(result) .. ")", vim.log.levels.WARN)
        end
    end

    return vars
end

return M
