--- Parse a curl command string into a request struct.
--- Handles: -X, -H, -d/--data/--data-raw, -u (basic auth), --url,
---          positional URL, -G, line continuations \, single+double quotes.

local M = {}

--- Tokenize a shell-like string respecting quotes and backslash continuations.
---@param str string
---@return string[]
local function tokenize(str)
    -- Normalize line continuations (\ at end of line)
    local s = str:gsub("\\\n", " "):gsub("\\\r\n", " ")

    local tokens = {}
    local i = 1
    local n = #s

    while i <= n do
        -- Skip whitespace
        while i <= n and s:sub(i, i):match("%s") do i = i + 1 end
        if i > n then break end

        local c = s:sub(i, i)
        local token = ""

        if c == "'" then
            -- Single-quoted: no escaping
            i = i + 1
            local j = s:find("'", i, true)
            if j then
                token = s:sub(i, j - 1)
                i = j + 1
            else
                token = s:sub(i)
                i = n + 1
            end
        elseif c == '"' then
            -- Double-quoted: backslash escaping for \", \\, \n, \t
            i = i + 1
            while i <= n do
                local ch = s:sub(i, i)
                if ch == '"' then
                    i = i + 1
                    break
                elseif ch == '\\' and i < n then
                    local next = s:sub(i + 1, i + 1)
                    if next == '"' or next == '\\' then
                        token = token .. next
                    elseif next == 'n' then
                        token = token .. '\n'
                    elseif next == 't' then
                        token = token .. '\t'
                    else
                        token = token .. ch .. next
                    end
                    i = i + 2
                else
                    token = token .. ch
                    i = i + 1
                end
            end
        elseif c == '$' and i < n and s:sub(i + 1, i + 1) == "'" then
            -- $'...' ANSI-C quoting
            i = i + 2
            while i <= n do
                local ch = s:sub(i, i)
                if ch == "'" then
                    i = i + 1
                    break
                elseif ch == '\\' and i < n then
                    local next = s:sub(i + 1, i + 1)
                    if next == 'n' then token = token .. '\n'
                    elseif next == 't' then token = token .. '\t'
                    elseif next == 'r' then token = token .. '\r'
                    elseif next == "'" then token = token .. "'"
                    elseif next == '\\' then token = token .. '\\'
                    else token = token .. ch .. next end
                    i = i + 2
                else
                    token = token .. ch
                    i = i + 1
                end
            end
        else
            -- Unquoted: read until whitespace
            while i <= n and not s:sub(i, i):match("%s") do
                token = token .. s:sub(i, i)
                i = i + 1
            end
        end

        if token ~= "" or c == "'" or c == '"' then
            table.insert(tokens, token)
        end
    end

    return tokens
end

--- Base64 encode (pure Lua, for -u basic auth).
---@param str string
---@return string
local function base64(str)
    local b64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    local out  = {}
    local pad  = (3 - (#str % 3)) % 3

    -- Pad input to multiple of 3
    local s = str .. string.rep("\0", pad)

    for i = 1, #s, 3 do
        local b1, b2, b3 = s:byte(i, i + 2)
        local n = b1 * 65536 + b2 * 256 + b3
        table.insert(out, b64:sub(math.floor(n / 262144) % 64 + 1, math.floor(n / 262144) % 64 + 1))
        table.insert(out, b64:sub(math.floor(n /   4096) % 64 + 1, math.floor(n /   4096) % 64 + 1))
        table.insert(out, b64:sub(math.floor(n /     64) % 64 + 1, math.floor(n /     64) % 64 + 1))
        table.insert(out, b64:sub(              n        % 64 + 1,               n        % 64 + 1))
    end

    local result = table.concat(out)
    -- Replace trailing padding chars
    if pad == 2 then
        result = result:sub(1, -3) .. "=="
    elseif pad == 1 then
        result = result:sub(1, -2) .. "="
    end
    return result
end

--- Parse a curl command string into a request struct.
---@param curl_str string
---@return http.Request
M.parse = function(curl_str)
    local tokens = tokenize(curl_str)

    local method  = nil
    local url     = nil
    local headers = {}
    local body    = nil
    local is_get  = false   -- -G flag

    local i = 1
    -- Skip leading "curl" token
    if tokens[1] and tokens[1]:lower() == "curl" then i = 2 end

    while i <= #tokens do
        local t = tokens[i]

        if t == "-X" or t == "--request" then
            i = i + 1
            method = tokens[i]

        elseif t == "-H" or t == "--header" then
            i = i + 1
            local hdr = tokens[i]
            if hdr then
                local k, v = hdr:match("^([^:]+):%s*(.*)$")
                if k then headers[k] = v end
            end

        elseif t == "-d" or t == "--data" or t == "--data-raw" or t == "--data-ascii" then
            i = i + 1
            body = tokens[i]

        elseif t == "-u" or t == "--user" then
            i = i + 1
            local creds = tokens[i]
            if creds then
                headers["Authorization"] = "Basic " .. base64(creds)
            end

        elseif t == "--url" then
            i = i + 1
            url = tokens[i]

        elseif t == "-G" or t == "--get" then
            is_get = true

        elseif t == "-g" or t == "--globoff"
            or t == "-v" or t == "--verbose"
            or t == "-s" or t == "--silent"
            or t == "-S" or t == "--show-error"
            or t == "-i" or t == "--include"
            or t == "-I" or t == "--head"
            or t == "-L" or t == "--location"
            or t == "-k" or t == "--insecure"
            or t == "--compressed"
            or t == "-o" or t == "--output"
            or t == "--connect-timeout" or t == "--max-time"
        then
            -- Known flags to skip (some consume next token)
            if t == "-o" or t == "--output"
                or t == "--connect-timeout" or t == "--max-time"
            then
                i = i + 1  -- skip argument
            end

        elseif not t:match("^%-") then
            -- Positional argument — treat as URL if we don't have one
            if not url then
                url = t
            end
        end

        i = i + 1
    end

    -- Defaults
    if is_get then method = "GET" end
    if not method then
        method = (body and body ~= "") and "POST" or "GET"
    end

    return {
        method  = method,
        url     = url or "",
        headers = headers,
        body    = body or "",
        scripts = {},
    }
end

return M
