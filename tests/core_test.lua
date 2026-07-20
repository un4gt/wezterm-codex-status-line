local core = require("codex_statusline_core")

local function assert_equal(actual, expected, label)
  if actual ~= expected then
    error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
  end
end

local function process(pid, ppid, executable, argv, children)
  return {
    pid = pid,
    ppid = ppid,
    executable = executable,
    argv = argv or { executable },
    children = children or {},
  }
end

local options = {
  names = { "codex", "codex.exe" },
  argv_markers = { "/@openai/codex/bin/codex.js" },
  terminal_names = { "wezterm-gui.exe" },
}

do
  local codex = process(20, 10, "C:\\tools\\codex.exe")
  local result = core.inspect_codex_process(codex, function()
    return nil
  end, options)
  assert_equal(result.state, true, "native process state")
  assert_equal(result.pid, 20, "native process pid")
  assert_equal(result.kind, "native", "native process kind")
end

do
  local wrapper = process(30, 10, "C:\\nodejs\\node.exe", {
    "node.exe",
    "C:\\node_global\\node_modules\\@openai\\codex\\bin\\codex.js",
  })
  local result = core.inspect_codex_process(wrapper, function()
    return nil
  end, options)
  assert_equal(result.state, true, "npm wrapper state")
  assert_equal(result.kind, "wrapper", "npm wrapper kind")
end

do
  local git = process(41, 40, "C:\\Program Files\\Git\\bin\\git.exe")
  local codex = process(40, 30, "C:\\tools\\codex.exe")
  local node = process(30, 10, "C:\\nodejs\\node.exe")
  local parents = { [40] = codex, [30] = node }
  local result = core.inspect_codex_process(git, function(pid)
    return parents[pid]
  end, options)
  assert_equal(result.state, true, "codex child command state")
  assert_equal(result.pid, 40, "codex child command pid")
end

do
  local shell_a = process(51, 1, "C:\\Program Files\\PowerShell\\7\\pwsh.exe")
  local codex_b = process(61, 60, "C:\\tools\\codex.exe")
  local shell_b = process(60, 1, "C:\\Program Files\\PowerShell\\7\\pwsh.exe", nil, { [61] = codex_b })
  local wezterm = process(1, 0, "C:\\tools\\wezterm-gui.exe", nil, { [51] = shell_a, [60] = shell_b })
  local result = core.inspect_codex_process(shell_a, function(pid)
    if pid == 1 then
      return wezterm
    end
    return nil
  end, options)
  assert_equal(result.state, false, "sibling codex must not leak across panes")
  assert_equal(result.reason, "terminal-boundary", "sibling boundary reason")
end

do
  local child = process(70, 69, "C:\\tools\\git.exe")
  local result = core.inspect_codex_process(child, function()
    return nil
  end, options)
  assert_equal(result.state, nil, "incomplete parent chain is unknown")
end

do
  local object = {
    type = "event_msg",
    payload = {
      type = "token_count",
      info = {
        total_token_usage = {
          input_tokens = 100000,
          cached_input_tokens = 80000,
          output_tokens = 5000,
          reasoning_output_tokens = 1500,
          total_tokens = 105000,
        },
        last_token_usage = {
          input_tokens = 159000,
          cached_input_tokens = 150000,
          output_tokens = 1735,
          reasoning_output_tokens = 700,
          total_tokens = 160735,
        },
        model_context_window = 353400,
      },
    },
  }
  local info = core.extract_token_usage_info(object)
  local usage = core.build_usage(info.total, info.last, info.model_context_window)
  assert_equal(usage.total, 25000, "blended total")
  assert_equal(usage.input, 20000, "non-cached input")
  assert_equal(usage.cached, 80000, "cached input")
  assert_equal(usage.output, 5000, "output")
  assert_equal(usage.context_tokens, 160735, "active context")
  assert_equal(usage.context_remaining_percent, 56, "context remaining")
  assert_equal(core.extract_token_usage_info({ payload = { usage = object.payload.info } }), nil, "strict event parsing")
end

do
  local mapping, err = core.validate_bridge_mapping({
    schema = 1,
    pane_id = "9",
    thread_id = "019f75fc-a8b9-7382-8b0c-9739278f57a4",
    rollout_path = "C:\\Users\\me\\.codex\\sessions\\rollout.jsonl",
    generation = "generation-1",
  }, 9)
  assert_equal(err, nil, "valid mapping error")
  assert_equal(mapping.thread_id, "019f75fc-a8b9-7382-8b0c-9739278f57a4", "valid mapping thread")
end

do
  local selected = core.select_recent_rollout({
    { _rollout_path = "today.jsonl", _activity_timestamp = "2026-07-19T00:00:00Z" },
    { _rollout_path = "older-resumed.jsonl", _activity_timestamp = "2026-07-19T00:10:00Z" },
  })
  assert_equal(selected._rollout_path, "older-resumed.jsonl", "cross-day active rollout")
end

do
  local offset, discard = core.tail_start(1000, 500, 100)
  assert_equal(offset, 500, "saved tail offset")
  assert_equal(discard, false, "saved offset must not discard a complete line")

  offset, discard = core.tail_start(1000, 0, 100)
  assert_equal(offset, 900, "initial tail seek")
  assert_equal(discard, true, "initial tail seek discards a partial line")
end

return true
