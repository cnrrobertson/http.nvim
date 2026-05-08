return {
    buf_name  = function(section) return "http://" .. section end,
    NAMESPACE = vim.api.nvim_create_namespace("http"),
    HL_PREFIX = "Http",
}
