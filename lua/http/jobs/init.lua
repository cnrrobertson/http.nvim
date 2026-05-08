local state = require("http.state")
local log   = require("http.log")

local M = {}

---@class http.JobOpts
---@field cmd string[]
---@field on_exit fun(code: integer, output: string)

---@param opts http.JobOpts
---@return integer? job_id
M.run_job = function(opts)
    -- Cancel any in-flight job
    if state.current_job and state.current_job > 0 then
        pcall(vim.fn.jobstop, state.current_job)
        state.current_job = nil
    end

    local stdout_lines = {}
    local stderr_lines = {}

    log.append("RUN " .. table.concat(opts.cmd, " "))

    local job_id = vim.fn.jobstart(opts.cmd, {
        stdout_buffered = true,
        stderr_buffered = true,
        on_stdout = function(_, data)
            if data then
                for _, line in ipairs(data) do
                    table.insert(stdout_lines, line)
                end
            end
        end,
        on_stderr = function(_, data)
            if data then
                for _, line in ipairs(data) do
                    if line ~= "" then
                        table.insert(stderr_lines, line)
                    end
                end
            end
        end,
        on_exit = function(_, code)
            state.current_job = nil
            -- Keep raw stdout (includes trailing empty string from jobstart)
            -- Strip only the final empty sentinel jobstart appends
            if #stdout_lines > 0 and stdout_lines[#stdout_lines] == "" then
                table.remove(stdout_lines)
            end
            local stdout = table.concat(stdout_lines, "\n")
            local stderr = table.concat(stderr_lines, "\n")
            vim.schedule(function()
                if code ~= 0 then
                    log.append("EXIT " .. code
                        .. " STDERR: " .. (stderr ~= "" and stderr or "(empty)")
                        .. (stdout ~= "" and (" STDOUT: " .. stdout) or ""))
                else
                    log.append("EXIT 0 (" .. #stdout .. " bytes)")
                end
                local err_out = stderr ~= "" and stderr or stdout
                opts.on_exit(code, code == 0 and stdout or err_out)
            end)
        end,
    })

    if job_id <= 0 then
        vim.notify("[http] Failed to start curl process", vim.log.levels.ERROR)
        return nil
    end

    state.current_job = job_id
    return job_id
end

return M
