local fake = require("tests.fake_wezterm")
local function eq(a, b, label) assert(a == b, label .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end
local function contains(s, part, label) assert(tostring(s):find(part, 1, true), label) end

local encode = require("codex_statusline.util").base64_encode
for source, expected in pairs({ [""] = "", f = "Zg==", fo = "Zm8=", foo = "Zm9v",
  foob = "Zm9vYg==", fooba = "Zm9vYmE=", foobar = "Zm9vYmFy", ["\x00\xff\x10"] = "AP8Q" }) do
  eq(encode(source), expected, "RFC 4648 base64 vector")
end

local h = fake.new()
h:start()
h:settle()
local status = assert(h:status())
contains(status.last_output, "high", "initial title reasoning")
local line = status.last_output:match("\x1b%[2J(.-)\x1b%[K")
assert(line, "status frame contains one rendered line")
eq(h.wezterm.column_width(line), 120, "version anchors full width")
local version_text = require("codex_statusline.version").text
local suffix = "   " .. version_text .. " "
eq(line:sub(-#suffix), suffix, "project icon followed by installed plugin version")

-- /model can update the title before the rollout has any new records.
local pane_data = h.wezterm.GLOBAL.codex_statusline_state.panes[tostring(h.main.id)]
pane_data.turn_context = { model = "gpt-6-astra", effort = "max" }
pane_data.thread_settings = { model = "gpt-6-astra", reasoning_effort = "max" }
h.main.title = "codex | gpt-5.6-sol | high | app"
h:tick()
contains(status.last_output, "gpt-5.6-sol", "idle model switch overrides stale rollout settings")
assert(not status.last_output:find("gpt-6-astra", 1, true), "old model is no longer displayed")
contains(status.last_output, "high", "idle model switch carries its reasoning")
eq(pane_data.turn_context.model, "gpt-6-astra", "live title does not rewrite request history")
eq(pane_data.thread_settings.model, "gpt-6-astra", "model updates without a new rollout event")
h.main.title = "codex | gpt-6-astra | max | app"
h:tick()
contains(status.last_output, "gpt-6-astra", "second idle switch updates immediately")
h.main.title = "pwsh.exe"
h:tick()
contains(status.last_output, "gpt-6-astra", "missing title falls back to the rollout")
pane_data.turn_context, pane_data.thread_settings = nil, nil

h.main.title = "codex | max | app"
h:tick()
contains(status.last_output, "max", "live title reasoning")
local painted = status.inject_count
h.window.font_size = 13
h:tick()
eq(status.inject_count, painted + 1, "font changes repaint")
painted = status.inject_count
h:tick()
eq(status.inject_count, painted, "unchanged frame does not repaint")

h.main.title = "pwsh.exe"
h:settle()
eq(h:status(), status, "MCP title changes retain live owner")
eq(#h.close_commands, 0, "MCP title does not close status")
h.main.user_vars.codex_active = "false"
h:tick()
eq(h.close_commands[1][6], tostring(status.id), "explicit exit targets status")
h:complete_close()
h:tick()
eq(h:status(), nil, "completed close clears binding")
assert(h.panes[h.main.id], "owner survives")
h:assert_no_errors()

for _, powerline in ipairs({ false, true }) do
  for _, rows in ipairs({ 1, 2 }) do
    local versioned = fake.new({ render = { powerline = powerline, disabled_segments = { "icon" } },
      bottom_pane = { rows = rows } })
    local adapter = require("codex_statusline.wezterm_adapter").new(versioned.wezterm)
    local opts = require("codex_statusline.config").new(versioned.wezterm, adapter).resolve(versioned.options)
    local renderer = require("codex_statusline.renderer").new(versioned.wezterm, opts,
      { git_info_for_cwd = function() return {} end }, adapter)
    for _, cols in ipairs({ 1, 2, 8, 25, 50, 75, 120 }) do
      local first, second = renderer.build_lines(opts, { model = "gpt-5.6-codex" }, {}, cols)
      assert(versioned.wezterm.column_width(first) <= cols, "version never wraps narrow panes")
      if cols >= #version_text + 2 then
        eq(first:sub(-#version_text - 2), " " .. version_text .. " ", "version visible with icon disabled")
        eq(versioned.wezterm.column_width(first), cols, "version stays flush right")
      end
      if second then assert(not second:find(version_text, 1, true), "two rows show version only once") end
    end
  end
end

for _, delay in ipairs({ 0, 249, 5001, 250.5, "1000" }) do
  local invalid = fake.new({ bottom_pane = { layout_debounce_ms = delay } })
  eq(invalid.callbacks["update-status"], nil, "invalid debounce disables setup safely")
  contains(table.concat(invalid.logs, "\n"), "layout_debounce_ms", "invalid debounce diagnostic")
end
for _, delay in ipairs({ 250, 1000, 5000 }) do
  local valid = fake.new({ bottom_pane = { layout_debounce_ms = delay } })
  valid:start()
  valid:tick(0)
  valid:tick(delay / 1000)
  assert(valid:status(), "inclusive debounce bounds")
end

local missing = fake.new()
missing:start()
missing:settle()
local existing = missing:status()
local saved = package.loaded["codex_statusline.layout"]
package.loaded["codex_statusline.layout"] = nil
package.preload["codex_statusline.layout"] = function() error("simulated missing layout") end
-- Force a dependency read during setup, as happens after an incomplete installation.
local saved_adapter = package.loaded["codex_statusline.wezterm_adapter"]
package.loaded["codex_statusline.wezterm_adapter"] = nil
eq(pcall(require("codex_statusline").setup, {}), true, "missing dependency leaves config usable")
missing:tick()
eq(missing:status(), existing, "failed setup does not mutate user panes")
eq(#missing.close_commands, 0, "missing dependency does not close panes")
package.loaded["codex_statusline.layout"] = saved
package.loaded["codex_statusline.wezterm_adapter"] = saved_adapter
package.preload["codex_statusline.layout"] = nil

print("statusline lifecycle and rendering tests passed")

if type(io.stdout) == "userdata" then
  local registry = require("codex_statusline.state")
  local saved_state = { schema = 8, bindings = {}, panes = {}, tabs = {}, close_requests = {}, next_generation = 9 }
  local shared = {
    GLOBAL = { codex_statusline_state = io.stdout },
    json_encode = function(value) eq(value, io.stdout, "shared state encoded"); return "shared-state" end,
    json_parse = function(value) eq(value, "shared-state", "shared state decoded"); return saved_state end,
  }
  eq(registry.load(shared), saved_state, "shared GLOBAL is not reset")
  eq(registry.generation(saved_state, 1000), "1000:10", "shared generation preserved")
end
