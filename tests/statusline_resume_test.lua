local callbacks = {}
local panes = {}
local mapping_available = false
local now = 1000
local marker_values = {}
local last_log_error = nil
local rollout_path = "tests/fixtures/resume-home/sessions/2026/07/23/rollout-resume.jsonl"
local rollout_json = table.concat({
  '{"timestamp":"2026-07-23T10:00:00Z","type":"session_meta","payload":{"id":"019f8f00-0000-7000-8000-000000000001","cwd":"E:\\\\src\\\\app","model_provider":"openai"}}',
  '{"timestamp":"2026-07-23T10:10:05.123Z","type":"event_msg","payload":{"type":"token_count"}}',
  "",
}, "\n")
local mapping_json = '{"schema":1,"pane_id":"1","thread_id":"019f8f00-0000-7000-8000-000000000001"}'

local function assert_equal(actual, expected, label)
  if actual ~= expected then
    error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
  end
end

local function memory_file(content)
  local handle = { content = content, position = 1 }

  function handle:seek(whence, offset)
    local delta = tonumber(offset) or 0
    if whence == "end" then
      self.position = #self.content + 1 + delta
    elseif whence == "set" then
      self.position = 1 + delta
    elseif whence == "cur" then
      self.position = self.position + delta
    end
    self.position = math.max(1, math.min(#self.content + 1, self.position))
    return self.position - 1
  end

  function handle:read(format)
    if self.position > #self.content then
      return nil
    end
    if format == "*a" then
      local value = self.content:sub(self.position)
      self.position = #self.content + 1
      return value
    end
    if format == "*l" or format == "*L" then
      local newline = self.content:find("\n", self.position, true)
      local value = nil
      if newline then
        value = self.content:sub(self.position, format == "*L" and newline or newline - 1)
        self.position = newline + 1
      else
        value = self.content:sub(self.position)
        self.position = #self.content + 1
      end
      return value:gsub("\r$", "")
    end
    error("unsupported memory read: " .. tostring(format))
  end

  function handle:lines()
    return function()
      return self:read("*l")
    end
  end

  function handle:close() end
  return handle
end

io.open = function(path)
  local normalized = tostring(path):gsub("\\", "/")
  if normalized:match("/wezterm%-statusline/panes/1%.json$") and not mapping_available then
    return nil
  end
  if normalized:match("/wezterm%-statusline/panes/1%.json$") then
    return memory_file(mapping_json)
  end
  if normalized:match("/wezterm%-statusline/bridge%.json$") then
    return memory_file('{"schema":4}')
  end
  if normalized:match("/sessions/2026/07/23/rollout%-resume%.jsonl$") then
    return memory_file(rollout_json)
  end
  return nil
end

local real_date = os.date
os.time = function()
  return now
end
os.date = function(format, value)
  if format == "*t" or format == "!*t" then
    return { year = 2026, month = 7, day = 23 }
  end
  if format == "!%Y-%m-%dT%H:%M:%S" then
    return "2026-07-23T10:10:00"
  end
  return real_date(format, value)
end

local wezterm = {
  GLOBAL = {},
  action = {},
  mux = {},
  procinfo = {},
  url = {},
  version = "test",
  home_dir = "tests/fixtures",
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
function wezterm.log_error(message)
  last_log_error = tostring(message)
end

function wezterm.read_dir(path)
  local normalized = tostring(path):gsub("\\", "/"):gsub("/+$", "")
  if normalized:match("/sessions$") then
    return { "2026" }
  end
  if normalized:match("/sessions/2026$") then
    return { "07" }
  end
  if normalized:match("/sessions/2026/07$") then
    return { "23" }
  end
  if normalized:match("/sessions/2026/07/23$") then
    return { "rollout-resume.jsonl" }
  end
  return {}
end

function wezterm.json_parse(text)
  if marker_values[text] then return marker_values[text] end
  if text:find('"pane_id"', 1, true) then
    return {
      schema = 1,
      pane_id = "1",
      thread_id = "019f8f00-0000-7000-8000-000000000001",
      session_id = "019f8f00-0000-7000-8000-000000000001",
      rollout_path = rollout_path,
      cwd = "E:\\src\\app",
      source = "resume",
      generation = "resume-generation",
      written_at_unix_ms = 1784791805000,
    }
  end
  if text:find('"type":"session_meta"', 1, true) then
    return {
      timestamp = "2026-07-23T10:00:00Z",
      type = "session_meta",
      payload = {
        id = "019f8f00-0000-7000-8000-000000000001",
        cwd = "E:\\src\\app",
        model_provider = "openai",
      },
    }
  end
  if text:find('"type":"token_count"', 1, true) then
    local usage = {
      input_tokens = 4200,
      cached_input_tokens = 1200,
      output_tokens = 300,
      reasoning_output_tokens = 100,
      total_tokens = 4500,
    }
    return {
      timestamp = "2026-07-23T10:10:05.123Z",
      type = "event_msg",
      payload = {
        type = "token_count",
        info = {
          total_token_usage = usage,
          last_token_usage = usage,
          model_context_window = 10000,
        },
      },
    }
  end
  error("unexpected JSON fixture")
end

function wezterm.json_encode(value)
  marker_values.marker = value
  return "marker"
end

function wezterm.action.ActivatePaneDirection(direction)
  return { direction = direction }
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
panes[1] = main

function main:pane_id() return self.id end
function main:get_title() return self.title end
function main:get_dimensions() return self.dimensions end
function main:get_user_vars() return {} end
function main:get_foreground_process_name() return "C:\\tools\\codex.exe" end
function main:get_foreground_process_info()
  return {
    pid = 100,
    ppid = 10,
    executable = "C:\\tools\\codex.exe",
    argv = { "C:\\tools\\codex.exe", "resume" },
    children = {},
  }
end
function main:get_current_working_dir() return { file_path = "E:\\src\\app" } end
function main:activate() end

local function new_status_pane()
  local pane = { id = 2, dimensions = { cols = 120, viewport_rows = 1 } }
  function pane:pane_id() return self.id end
  function pane:get_dimensions() return self.dimensions end
  function pane:inject_output(output)
    self.last_output = output
    if output:find("SetUserVar=", 1, true) then self.marker = "marker" end
  end
  function pane:get_user_vars() return { codex_statusline_owner = self.marker } end
  function pane:get_domain_name() return "local" end
  function pane:set_title() end
  panes[2] = pane
  return pane
end

function main:split() return new_status_pane() end

local tab = {}
function tab:tab_id() return 9 end
function tab:active_pane() return main end
function tab:panes_with_info()
  local result = { { pane = main, left = 0, top = 0, width = 120, height = 30, is_active = true } }
  if panes[2] then
    table.insert(result, { pane = panes[2], left = 0, top = 31, width = 120, height = 1, is_active = false })
  end
  return result
end

local window = {}
function window:window_id() return 7 end
function window:active_tab() return tab end
function window:effective_config() return { font_size = 12 } end
function window:perform_action() end

package.preload.wezterm = function() return wezterm end

require("codex_statusline").setup({
  log = { enabled = false },
  codex_home = "tests/fixtures/resume-home",
  codex_config = { enabled = false },
  git = { enabled = false },
  bottom_pane = { rows = 1, close_grace_seconds = 0 },
  render = { powerline = false },
})

local update = callbacks["update-status"]
assert_equal(type(update), "function", "update handler; log=" .. tostring(last_log_error))
update(window, main)
now = now + 1
update(window, main)

local pane_state = wezterm.GLOBAL.codex_statusline_state.panes["1"]
assert_equal(pane_state.rollout_source, "bridge-activity", "resume activity fallback")
assert_equal(pane_state.rollout_path:gsub("\\", "/"), rollout_path, "resume rollout path")
assert_equal(pane_state.usage.total, 3300, "resume token usage")

mapping_available = true
update(window, main)
assert_equal(pane_state.rollout_source, "bridge", "mapping replaces activity fallback")
assert_equal(pane_state.bridge_mapping.generation, "resume-generation", "exact mapping generation")

do
  local pricing = require("codex_statusline.domain.pricing")
  local serial = 0
  local function item(value)
    serial = serial + 1
    local key = "cost-history-item-" .. serial
    marker_values[key] = value
    return key .. "\n"
  end
  local function context(model)
    return item({ type = "turn_context", payload = { model = model } })
  end
  local function usage(total_units, last_units)
    local function counts(units)
      return { input_tokens = units * 1000000, cached_input_tokens = units * 800000,
        output_tokens = units * 100000, total_tokens = units * 1100000 }
    end
    return item({ type = "event_msg", payload = { type = "token_count", info = {
      total_token_usage = counts(total_units), last_token_usage = counts(last_units),
    } } })
  end
  local module = require("codex_statusline.rollout").new(wezterm, {
    detect_rollout_for_pane = function() return rollout_path, "bridge" end,
    read_session_meta = function() return {} end,
    bridge_required = function() return false end,
  }, { safe_json_parse = function(line)
    local ok, result = pcall(wezterm.json_parse, line)
    return ok and result or nil
  end })
  local opts = { sessions = { enabled = true, tail_ttl_seconds = 0, max_tail_lines = 2,
    initial_seek_bytes = 50, max_meta_lines = 5 } }
  local state = {}
  rollout_json = context("gpt-5.6-sol") .. usage(1, 1)
    .. context("gpt-6-astra") .. usage(1, 1) .. usage(2, 1)
  local function refresh() module.update_rollout_state(opts, main, state) end
  local function cost(model) return pricing.cost_text(pricing.estimate(model, state.usage)) end
  refresh()
  assert_equal(state.usage.input_raw, 2000000, "tail immediately shows current token totals")
  assert_equal(cost("gpt-6-astra"), "Cost —", "partial history does not expose a partial cost")
  local reads = 1
  while not state.usage.cost_complete and reads < 10 do refresh(); reads = reads + 1 end
  assert_equal(state.usage.cost_complete, true, "history catches up in bounded batches")
  assert_equal(reads, 3, "historical scan obeys per-refresh line limit")
  assert_equal(cost("gpt-6-astra"), "Cost ~$10.92", "resume rebuilds models before initial tail")
  refresh()
  assert_equal(cost("gpt-5.6-sol"), "Cost ~$10.92", "idle refresh does not double count")

  rollout_json = rollout_json .. context("gpt-5.6-sol") .. usage(3, 1)
  refresh()
  assert_equal(cost("gpt-5.6-sol"), "Cost ~$14.04", "new usage extends the restored history")

  -- Split a newly appended record across refreshes, as a concurrent writer can.
  local appended = usage(4, 1)
  local prefix = appended:sub(1, 10)
  rollout_json = rollout_json .. prefix
  local previous_offset = state.offset
  refresh()
  assert_equal(state.offset, previous_offset, "partial line remains unread")
  assert_equal(state.usage.input_raw, 3000000, "partial line cannot change token totals")
  assert_equal(cost("gpt-5.6-sol"), "Cost —", "partial history is marked pending")
  rollout_json = rollout_json .. appended:sub(#prefix + 1)
  refresh()
  assert_equal(cost("gpt-5.6-sol"), "Cost ~$17.16", "completed line is read exactly once")

  -- Upgrading the plugin preserves pane offsets but has no prior cost history.
  state.cost_history = nil
  refresh()
  assert_equal(cost("gpt-5.6-sol"), "Cost —", "upgrade rebuilds rather than guessing from current totals")
  for _ = 1, 10 do if state.usage.cost_complete then break end; refresh() end
  assert_equal(cost("gpt-5.6-sol"), "Cost ~$17.16", "upgrade reconstructs cost at an existing offset")

  rollout_json = context("gpt-6-astra") .. usage(1, 1)
  refresh()
  assert_equal(cost("gpt-6-astra"), "Cost ~$7.80", "truncated file rebuilds without old buckets")
  assert_equal(state.usage.by_model["gpt-5.6-sol"], nil, "truncation removes the old model history")
  module.clear_rollout_data(state)
  assert_equal(state.cost_history, nil, "leaving a thread clears its cost history")

  rollout_json = usage(1, 1)
  refresh()
  assert_equal(cost("gpt-6-astra"), "Cost —", "current selection does not fill in a missing historical model")
end

print("statusline resume tests passed")
