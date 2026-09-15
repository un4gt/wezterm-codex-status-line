-- Compatibility exports for consumers of the original pure core module.
local M = {}
for _, name in ipairs({ "process", "session", "render" }) do
  for key, value in pairs(require("codex_statusline.domain." .. name)) do
    M[key] = value
  end
end
return M
