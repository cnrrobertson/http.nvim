local api    = vim.api
local prefix = require("http.globals").HL_PREFIX

local function hl(name, link)
    api.nvim_set_hl(0, prefix .. name, { default = true, link = link })
end

local function define()
    hl("Tab",         "TabLine")
    hl("TabSelected", "TabLineSel")
    hl("TabFill",     "TabLineFill")
    hl("Header",      "Title")
    hl("StatKey",     "Identifier")
    hl("HistoryOk",   "DiagnosticOk")
    hl("HistoryErr",  "DiagnosticError")
    hl("Loading",     "Comment")
    hl("MissingData", "DiagnosticVirtualTextWarn")
    hl("Hint",        "Comment")
    hl("StatusOk",    "DiagnosticOk")
    hl("StatusWarn",  "DiagnosticWarn")
    hl("StatusErr",   "DiagnosticError")
end

define()

api.nvim_create_autocmd("ColorScheme", {
    group    = api.nvim_create_augroup("http_hl", { clear = true }),
    callback = define,
})
