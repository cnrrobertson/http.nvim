-- Persistence layer for cross-session request history and response bodies.
--
-- History:   vim.fn.stdpath("state")/http/history.json
-- Responses: vim.fn.stdpath("state")/http/responses/<id>.txt

local state = require("http.state")
local setup = require("http.setup")

local M = {}

local function state_dir()    return vim.fn.stdpath("state") .. "/http" end
local function response_dir() return state_dir() .. "/responses" end
local function history_path() return state_dir() .. "/history.json" end
local function response_path(id) return response_dir() .. "/" .. id .. ".txt" end

M.setup = function()
    vim.fn.mkdir(response_dir(), "p")

    local f = io.open(history_path(), "r")
    if not f then return end

    local raw = f:read("*a")
    f:close()

    if not raw or raw == "" then return end

    local ok, decoded = pcall(vim.fn.json_decode, raw)
    if ok and type(decoded) == "table" then
        state.history = decoded
    end
end

---@param body string
---@return string|nil response_id
M.save_response = function(body)
    if not body or body == "" then return nil end

    local max = setup.config.history.max_body_bytes or 262144
    if #body > max then return nil end

    local id = tostring(os.time()) .. "-" .. string.format("%06d", math.random(999999))

    local f, err = io.open(response_path(id), "w")
    if not f then
        vim.notify("[http] Failed to save response: " .. (err or "?"), vim.log.levels.WARN)
        return nil
    end
    f:write(body)
    f:close()
    return id
end

---@param id string
---@return string|nil body
M.load_response = function(id)
    if not id then return nil end
    local f = io.open(response_path(id), "r")
    if not f then return nil end
    local body = f:read("*a")
    f:close()
    return (body ~= "" and body or nil)
end

M.save_history = function()
    local max     = setup.config.history.max_entries
    local history = state.history

    if max > 0 then
        while #history > max do
            local evicted = table.remove(history, 1)
            if evicted.response_id then
                os.remove(response_path(evicted.response_id))
            end
        end
    end

    local ok, encoded = pcall(vim.fn.json_encode, history)
    if not ok or not encoded then return end

    local f, err = io.open(history_path(), "w")
    if not f then
        vim.notify("[http] Failed to save history: " .. (err or "?"), vim.log.levels.WARN)
        return
    end
    f:write(encoded)
    f:close()
end

return M
