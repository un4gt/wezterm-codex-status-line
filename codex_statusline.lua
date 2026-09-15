local wezterm = require("wezterm")
local M = {}
local registered = false
local runtime
local use_legacy_event = false

function M.setup(user_opts)
  local ok, err = pcall(function()
    local adapter = require("codex_statusline.wezterm_adapter").new(wezterm)
    local config = require("codex_statusline.config").new(wezterm, adapter)
    local opts = config.resolve(user_opts)
    local index = require("codex_statusline.session_index").new(wezterm, config, adapter)
    local process = require("codex_statusline.process").new(wezterm, config)
    local rollout = require("codex_statusline.rollout").new(wezterm, index, adapter)
    local git = require("codex_statusline.git").new(wezterm)
    local renderer = require("codex_statusline.renderer").new(wezterm, opts, git, adapter)
    runtime = require("codex_statusline.lifecycle").new(wezterm, opts, process, rollout, renderer, adapter)
    use_legacy_event = opts.compat.update_right_status == true
    if opts.log.enabled then
      wezterm.log_info("codex_statusline: " .. opts.log.marker
        .. " module_id=wezterm-codex-statusline/" .. require("codex_statusline.version").version .. " searchpath="
        .. tostring(require("codex_statusline.util").resolved_module_path())
        .. " wezterm=" .. tostring(wezterm.version))
    end
    if not registered then
      wezterm.on("update-status", function(window, pane) if runtime then runtime.handle_update(window, pane) end end)
      wezterm.on("update-right-status", function(window, pane)
        if runtime and use_legacy_event then runtime.handle_update(window, pane) end
      end)
      wezterm.on("window-resized", function(window) if runtime then runtime.invalidate(window) end end)
      wezterm.on("codex-statusline-show", function(window, pane) if runtime then runtime.show(window, pane) end end)
      registered = true
    end
  end)
  if not ok then
    runtime = nil
    if type(wezterm.log_error) == "function" then
      wezterm.log_error("codex_statusline: setup failed; status line disabled: " .. tostring(err))
    end
  end
  return M
end

return M
