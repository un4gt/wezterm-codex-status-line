local ok, err = pcall(require, "tests.core_test")
if not ok then
  error(err)
end

require("codex_statusline").setup({
  log = { enabled = false },
  bottom_pane = { rows = 1 },
})

return {}
