---@class http.Config
local M = {
    winbar = {
        show              = true,
        sections          = { "response", "headers", "history", "debug" },
        default_section   = "response",
        show_keymap_hints = true,
        base_sections     = {
            response = { label = "Response", keymap = "R" },
            headers  = { label = "Headers",  keymap = "H" },
            history  = { label = "History",  keymap = "Y" },
            debug    = { label = "Debug",    keymap = "D" },
        },
    },
    windows = {
        size     = 0.40,
        position = "below",
    },
    preview = {
        max_width  = 0.8,
        max_height = 0.6,
    },
    history = {
        max_entries   = 100,
        max_body_bytes = 262144,  -- 256 KB
    },
    curl_path = "curl",
}

return M
