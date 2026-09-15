local wezterm = require("wezterm")
local root = wezterm.config_dir .. "/.."
package.path = root .. "/?.lua;" .. package.path

local adapter = require("codex_statusline.wezterm_adapter").new(wezterm)
local options = require("codex_statusline.config").new(wezterm, adapter).resolve({
  debug = true, log = { enabled = false }, codex_config = { enabled = false },
  git = { enabled = false }, sessions = { enabled = false },
  bottom_pane = { layout_debounce_ms = 250, close_grace_seconds = 0 },
  render = { powerline = false }, icon = { text = ">_" },
})
local running, cycle, phase, started = true, 0, "starting", nil
local owner, right, tab, baseline, right_baseline, runtime, idle_args
local done, handling = false, false
local repair_at, preserved, preserved_id
local layout = require("codex_statusline.layout")
local tick
local function pump()
  if done then return end
  if runtime then tick(tab:window():gui_window()) end
  wezterm.time.call_after(0.1, pump)
end

local function finish(ok, message)
  if done then return end
  done = true
  wezterm.log_info("LIVE_TEST_RESULT " .. wezterm.json_encode({
    passed = ok, cycles = cycle, message = message, version = wezterm.version,
  }))
end

wezterm.on("gui-startup", function()
  wezterm.log_info("LIVE_TEST_STARTUP")
  local args = { "powershell.exe", "-NoLogo", "-NoProfile", "-Command", "while($true){Start-Sleep -Seconds 3600}" }
  if not wezterm.target_triple:find("windows", 1, true) then
    args = { "sh", "-lc", "while true; do sleep 3600; done" }
  end
  idle_args = args
  tab, owner = wezterm.mux.spawn_window({ args = args })
  right = owner:split({ direction = "Right", size = 0.5, args = args })
  baseline = owner:get_dimensions().viewport_rows
  right_baseline = right:get_dimensions().viewport_rows
  local process = { build_codex_cells = function(_, pane)
    local active = pane:pane_id() == owner:pane_id() and running
    return { lifecycle = active and "running" or "exited", active = active,
      tree_state = active, codex_pid = active and (1000 + cycle) or nil,
      process_kind = active and "native" or nil, cells = {} }
  end }
  local rollout = { retire_bridge_generation = function() end, clear_rollout_data = function() end }
  local renderer = require("codex_statusline.renderer").new(wezterm, options,
    require("codex_statusline.git").new(wezterm), adapter)
  runtime = require("codex_statusline.lifecycle").new(wezterm, options, process, rollout, renderer, adapter)
  phase, started = "warmup", adapter.now_ms()
  wezterm.time.call_after(0.1, pump)
end)

tick = function(window)
  if not runtime or done or handling then return end
  handling = true
  local ok, err = pcall(function()
    assert(adapter.now_ms() - started < 240000, "live test timed out in " .. phase)
    if phase == "warmup" then
      if adapter.now_ms() - started < 1500 then return end
      baseline = owner:get_dimensions().viewport_rows
      right_baseline = right:get_dimensions().viewport_rows
      phase = "creating"
    end
    runtime.handle_update(window)
    local state = wezterm.GLOBAL.codex_statusline_state
    local binding = state.bindings[tostring(owner:pane_id())]
    local status = binding and binding.status_id and wezterm.mux.get_pane(tonumber(binding.status_id))
    local snap = assert(adapter.snapshot(tab))
    assert(right:get_dimensions().viewport_rows == right_baseline, "neighbor rows changed")
    if phase == "creating" and status then
      assert(not state.close_requests[binding.status_id], "unexpected close while running")
      if not adapter.marker(status) then return end
      assert(status:get_lines_as_text():find("CODEX", 1, true), "status content is blank")
      assert(layout.aligned(snap.by_id[tostring(owner:pane_id())], snap.by_id[tostring(status:pane_id())]), "local alignment")
      assert(owner:get_dimensions().viewport_rows + status:get_dimensions().viewport_rows + 1 == baseline, "row accounting")
      assert(tab:active_pane():pane_id() == right:pane_id(), "focus moved from right terminal")
      running, phase = false, "closing"
    elseif phase == "closing" and not status then
      assert(owner:get_dimensions().viewport_rows == baseline, "rows leaked on close")
      cycle = cycle + 1
      wezterm.log_info("LIVE_TEST_CYCLE " .. tostring(cycle))
      running, phase = true, cycle < 50 and "creating" or "final-create"
    elseif phase == "final-create" and status then
      assert(not state.close_requests[binding.status_id], "unexpected close while running")
      if not adapter.marker(status) then return end
      owner:split({ direction = "Right", size = 0.5, args = idle_args })
      preserved = layout.signature(tab:panes_with_info())
      preserved_id = status:pane_id()
      repair_at, phase = adapter.now_ms() + 2000, "preserve-layout"
    elseif phase == "preserve-layout" and adapter.now_ms() >= repair_at then
      assert(status and status:pane_id() == preserved_id, "status replaced after user split")
      assert(layout.signature(tab:panes_with_info()) == preserved, "user layout changed")
      finish(true, "50 local create/close cycles, right-pane focus/rows, conservative repair")
    end
  end)
  handling = false
  if not ok then finish(false, tostring(err)) end
end
wezterm.on("update-status", tick)

return {
  automatically_reload_config = false,
  check_for_updates = false,
  status_update_interval = 100,
  initial_cols = 160, initial_rows = 40,
  enable_tab_bar = false,
  window_close_confirmation = "NeverPrompt",
  exit_behavior = "Close",
}
