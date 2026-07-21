local callbacks = {}
local panes = {}
local next_pane_id = 2

local function assert_equal(actual, expected, label)
  if actual ~= expected then
    error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
  end
end

local function assert_contains(value, expected, label)
  if not tostring(value):find(expected, 1, true) then
    error(string.format("%s: expected %q in %q", label, expected, tostring(value)))
  end
end

local wezterm = {
  GLOBAL = {},
  action = {},
  mux = {},
  procinfo = {},
  url = {},
  version = "test",
  home_dir = "C:\\Users\\test",
}

function wezterm.on(name, callback)
  callbacks[name] = callback
end

function wezterm.format(items)
  local parts = {}
  for _, item in ipairs(items or {}) do
    if type(item) == "table" and item.Text then
      table.insert(parts, item.Text)
    end
  end
  return table.concat(parts)
end

function wezterm.column_width(value)
  return #tostring(value or "")
end

function wezterm.log_info() end
function wezterm.log_error() end

function wezterm.action.CloseCurrentPane()
  return { kind = "close" }
end

function wezterm.action.ActivatePaneDirection(direction)
  return { kind = "activate", direction = direction }
end

function wezterm.mux.get_pane(id)
  return panes[id]
end

function wezterm.url.parse(value)
  return { file_path = tostring(value):gsub("^file://", "") }
end

local main = {
  id = 1,
  title = "codex | high | app",
  dimensions = { cols = 120, viewport_rows = 30 },
}
panes[main.id] = main

function main:pane_id()
  return self.id
end

function main:get_title()
  return self.title
end

function main:get_dimensions()
  return self.dimensions
end

function main:get_user_vars()
  return {}
end

function main:get_foreground_process_name()
  return "C:\\tools\\codex.exe"
end

function main:get_foreground_process_info()
  return {
    pid = 100,
    ppid = 10,
    executable = "C:\\tools\\codex.exe",
    argv = { "C:\\tools\\codex.exe" },
    children = {},
  }
end

function main:get_current_working_dir()
  return { file_path = "E:\\src\\app" }
end

function main:activate()
  self.activated = true
end

local tab = { id = 99 }

function tab:tab_id()
  return self.id
end

function tab:active_pane()
  return main
end

function tab:panes_with_info()
  local infos = {
    { pane = main, top = 0, width = 120, height = 30, is_active = true },
  }
  for id, pane in pairs(panes) do
    if id ~= main.id then
      table.insert(infos, { pane = pane, top = 30, width = 120, height = 1, is_active = false })
    end
  end
  return infos
end

local window = {
  font_size = 12,
  fail_close = false,
}

function window:window_id()
  return 7
end

function window:active_tab()
  return tab
end

function window:effective_config()
  return { font_size = self.font_size }
end

function window:perform_action(action, pane)
  if action.kind == "close" then
    if self.fail_close then
      error("simulated close failure")
    end
    panes[pane:pane_id()] = nil
  end
end

local function new_status_pane()
  local pane = {
    id = next_pane_id,
    title = "",
    dimensions = { cols = 120, viewport_rows = 1 },
    inject_count = 0,
    last_output = nil,
  }
  next_pane_id = next_pane_id + 1

  function pane:pane_id()
    return self.id
  end

  function pane:get_title()
    return self.title
  end

  function pane:set_title(title)
    self.title = title
  end

  function pane:get_dimensions()
    return self.dimensions
  end

  function pane:inject_output(output)
    self.inject_count = self.inject_count + 1
    self.last_output = output
  end

  function pane:get_domain_name()
    return "local"
  end

  panes[pane.id] = pane
  return pane
end

function main:split()
  return new_status_pane()
end

package.preload.wezterm = function()
  return wezterm
end

require("codex_statusline").setup({
  log = { enabled = false },
  codex_config = { enabled = false },
  git = { enabled = false },
  sessions = { enabled = false },
  bottom_pane = {
    rows = 1,
    close_grace_seconds = 0,
  },
  render = { powerline = false },
})

local update = callbacks["update-status"]
assert_equal(type(update), "function", "update-status handler")

update(window, main)
local status = panes[2]
assert_equal(status ~= nil, true, "status pane created")
assert_contains(status.last_output, "r:high", "initial title reasoning")

main.title = "codex | max | app"
update(window, main)
assert_contains(status.last_output, "r:max", "live title reasoning")

local before_zoom = status.inject_count
window.font_size = 13
update(window, main)
assert_equal(status.inject_count, before_zoom + 1, "font size forces repaint")

status.dimensions.viewport_rows = 0
update(window, main)
assert_equal(panes[status.id], nil, "invalid status pane closed")
update(window, main)
status = panes[3]
assert_equal(status ~= nil, true, "status pane recreated")
assert_equal(status.dimensions.viewport_rows, 1, "recreated status pane rows")

main.title = "pwsh.exe"
window.fail_close = true
update(window, main)
assert_equal(panes[status.id] ~= nil, true, "failed close retains status pane")
local tab_state = wezterm.GLOBAL.codex_statusline_state.tabs["7:99"]
assert_equal(tab_state.status_pane_id, status.id, "failed close retains status pane id")

window.fail_close = false
update(window, main)
assert_equal(panes[status.id], nil, "status pane closes after retry")
assert_equal(tab_state.status_pane_id, nil, "status pane id clears after confirmed close")

print("statusline lifecycle tests passed")
