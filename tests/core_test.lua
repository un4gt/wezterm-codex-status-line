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

  assert_equal(core.merge_context_window(353400, nil), 353400, "missing window preserves known value")
  assert_equal(core.merge_context_window(353400, 272000), 272000, "new window replaces known value")
  assert_equal(core.merge_context_window(nil, "272000"), 272000, "string window is accepted")
end

do
  assert_equal(core.inactivity_grace_elapsed(100, 100, 2), false, "grace starts without expiring")
  assert_equal(core.inactivity_grace_elapsed(100, 101, 2), false, "grace retains transient inactivity")
  assert_equal(core.inactivity_grace_elapsed(100, 102, 2), true, "grace expires at threshold")
end

do
  local signal = core.parse_codex_terminal_title("codex | max | wezterm-codex-status-line")
  assert_equal(signal.reasoning, "max", "terminal title reasoning")
  assert_equal(signal.project, "wezterm-codex-status-line", "terminal title project")

  signal = core.parse_codex_terminal_title("[ ! ] Action Required | codex | HIGH | app")
  assert_equal(signal.reasoning, "high", "action title reasoning")
  assert_equal(core.parse_codex_terminal_title("pwsh.exe"), nil, "unrelated terminal title")
  assert_equal(core.parse_codex_terminal_title("codex | high"), nil, "incomplete terminal title")
end

do
  local state, override, source = core.update_title_bridge_state(nil, { reasoning = "max" }, true, true, 100)
  assert_equal(override, true, "managed title activates session")
  assert_equal(source, "terminal-title", "managed title source")
  assert_equal(state.reasoning, "max", "managed title stores reasoning")

  state, override, source = core.update_title_bridge_state(state, nil, true, true, 100)
  assert_equal(override, nil, "live Codex process survives transient title loss")
  assert_equal(source, nil, "transient title loss has no terminal override")
  assert_equal(state.ended, false, "transient title loss keeps title generation active")

  state, override = core.update_title_bridge_state(state, nil, true, false, nil)
  assert_equal(override, false, "confirmed process exit ends title session")
  assert_equal(state.ended, true, "confirmed process exit marks title generation ended")

  state, override = core.update_title_bridge_state(state, nil, false, true, 100)
  assert_equal(override, false, "stale process cannot reactivate ended title session")

  state, override, source = core.update_title_bridge_state(state, nil, true, true, 101)
  assert_equal(override, nil, "new process generation can activate before its title")
  assert_equal(source, "process-generation", "new process generation source")
  assert_equal(state.ended, false, "new process resets ended title generation")

  state, override = core.update_title_bridge_state(state, { reasoning = "low" }, true, true, 101)
  assert_equal(override, true, "new title starts new session")
  assert_equal(state.reasoning, "low", "new session reasoning")
end

do
  assert_equal(core.render_layout_key(7, 120, 1, 12), "7|120|1|12", "render layout key")
  assert_equal(
    core.render_layout_key(7, 120, 1, 13),
    "7|120|1|13",
    "font size invalidates render layout"
  )
end

do
  assert_equal(core.normalize_path("/E:/Src/App/", true), "e:\\src\\app", "wezterm Windows file URL")
  assert_equal(core.normalize_path("E:\\Src\\App", true), "e:\\src\\app", "native Windows path")
  assert_equal(core.normalize_path("/home/me/app/", false), "/home/me/app", "Unix path")
end

do
  local waiting = core.waiting_status(nil, "bridge-waiting", "mapping-unavailable")
  assert_equal(waiting.kind, "bridge", "missing mapping wait kind")

  waiting = core.waiting_status(nil, "bridge-waiting", "mapping-generation-retired")
  assert_equal(waiting.kind, "rollout", "retired mapping wait kind")

  waiting = core.waiting_status("rollout.jsonl", "bridge", nil)
  assert_equal(waiting.kind, "token-data", "first response wait kind")
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
  local selected, reason, count = core.select_unique_active_rollout({
    {
      _rollout_path = "stale.jsonl",
      _cwd_norm = "e:\\src\\app",
      _activity_timestamp = "2026-07-23T10:00:00Z",
    },
    {
      _rollout_path = "resumed.jsonl",
      _cwd_norm = "e:\\src\\app",
      _activity_timestamp = "2026-07-23T10:10:05.123Z",
    },
    {
      _rollout_path = "other-cwd.jsonl",
      _cwd_norm = "e:\\src\\other",
      _activity_timestamp = "2026-07-23T10:10:06Z",
    },
  }, "e:\\src\\app", "2026-07-23T10:10:00")
  assert_equal(selected._rollout_path, "resumed.jsonl", "unique active resume rollout")
  assert_equal(reason, nil, "unique active resume reason")
  assert_equal(count, 1, "unique active resume count")

  selected, reason, count = core.select_unique_active_rollout({
    {
      _rollout_path = "resume-a.jsonl",
      _cwd_norm = "e:\\src\\app",
      _activity_timestamp = "2026-07-23T10:10:05Z",
    },
    {
      _rollout_path = "resume-b.jsonl",
      _cwd_norm = "e:\\src\\app",
      _activity_timestamp = "2026-07-23T10:10:06Z",
    },
  }, "e:\\src\\app", "2026-07-23T10:10:00")
  assert_equal(selected, nil, "ambiguous resume rollout rejected")
  assert_equal(reason, "ambiguous-active-rollouts", "ambiguous resume reason")
  assert_equal(count, 2, "ambiguous resume count")

  selected, reason = core.select_unique_active_rollout({
    {
      _rollout_path = "stale.jsonl",
      _cwd_norm = "e:\\src\\app",
      _activity_timestamp = "2026-07-23T10:00:00Z",
    },
  }, "e:\\src\\app", "2026-07-23T10:10:00")
  assert_equal(selected, nil, "stale resume rollout rejected")
  assert_equal(reason, "no-active-rollout", "stale resume reason")
end

do
  local offset, discard = core.tail_start(1000, 500, 100)
  assert_equal(offset, 500, "saved tail offset")
  assert_equal(discard, false, "saved offset must not discard a complete line")

  offset, discard = core.tail_start(1000, 0, 100)
  assert_equal(offset, 900, "initial tail seek")
  assert_equal(discard, true, "initial tail seek discards a partial line")
end

do
  assert_equal(core.compact_number(999), "999", "compact integer")
  assert_equal(core.compact_number(999950), "1M", "compact unit promotion")
  assert_equal(core.compact_number(4203817), "4.2M", "compact millions")
  assert_equal(core.context_bar(72, 10), "███████░░░", "context meter")

  local plan = core.build_render_plan({
    label = "CODEX",
    bottom_pane = { rows = 1 },
    render = {
      powerline = false,
      segment_order = { "label", "model", "reasoning", "provider", "cwd", "git", "context", "used_tokens" },
      disabled_segments = {},
    },
    theme = { bg = "#111111", fg = "#eeeeee", segments = {} },
  }, {
    model = "gpt-5.6-codex",
    reasoning = "high",
    provider = "openai",
    cwd = "~/src/app",
    git = "main",
    usage = { input_raw = 10000000, cached = 6000000, output = 203817, total = 4203817, context_remaining_percent = 72 },
  }, 140)
  assert_equal(plan.layout, "wide", "wide render plan")
  assert_equal(plan.lines[1][7].text, "Ctx ███████░░░ 72% left", "context segment")
  assert_equal(plan.lines[1][8].text, "↑10M ↓204K", "input and output segment")

  local tiny = core.build_render_plan({
    label = "CODEX",
    bottom_pane = { rows = 1 },
    render = { powerline = false },
    theme = { bg = "#111111", fg = "#eeeeee", segments = {} },
  }, {
    model = "gpt-5.6-codex",
    reasoning = "high",
    provider = "openai",
    cwd = "app",
    git = "main",
    usage = { total = 4203817, context_remaining_percent = 72 },
  }, 50)
  assert_equal(#tiny.lines[1], 5, "tiny segment count")
  assert_equal(tiny.lines[1][3].kind, "context", "tiny context priority")
  assert_equal(tiny.lines[1][4].kind, "icon", "tiny icon remains rightmost")
  assert_equal(tiny.lines[1][4].text, "", "tiny icon uses project terminal mark")

  local reordered = core.build_render_plan({
    label = "CODEX",
    bottom_pane = { rows = 1 },
    render = { powerline = false, segment_order = { "icon", "label", "model" } },
    theme = { bg = "#111111", fg = "#eeeeee", segments = {} },
  }, { model = "gpt-5.6-codex" }, 140)
  assert_equal(reordered.lines[1][#reordered.lines[1] - 1].kind, "icon", "configured icon precedes version")
  assert_equal(reordered.lines[1][#reordered.lines[1]].kind, "version", "version remains rightmost")
end

do
  local pricing = require("codex_statusline.domain.pricing")
  local usage = { input_raw = 1000000, cached = 800000, output = 100000, reasoning = 50000 }
  for _, case in ipairs({
    { "gpt-6-astra", "Cost ~$7.80" }, { "gpt-5.6-sol", "Cost ~$3.12" },
    { "gpt-5.6-terra", "Cost ~$1.76" }, { "gpt-5.6-luna", "Cost ~$0.18" },
    { "openai/GPT-5.6-SOL-2026-09-01", "Cost ~$3.12" }, { "gpt-5.6-sol-pro", "Cost —" },
  }) do
    for _, rows in ipairs({ 1, 2 }) do
      local plan = core.build_render_plan({ bottom_pane = { rows = rows } }, { model = case[1], usage = usage }, 180)
      local texts = {}
      for _, segment in ipairs(plan.lines[rows]) do texts[segment.kind] = segment.text end
      assert_equal(texts.used_tokens, "↑1M ↓100K", "raw input and output " .. case[1])
      assert_equal(texts.cache_rate, "Cache 80%", "cache ratio " .. case[1])
      assert_equal(texts.cost, case[2], "estimated cost " .. case[1])
    end
  end
  local custom = { models = { ["gpt-5.6-sol"] = { input = 3, cached_input = 1, output = 5 } } }
  assert_equal(pricing.cost_text(pricing.estimate("Sol", usage, custom)), "Cost ~$1.90", "custom price overrides alias")
  custom.models["gpt-5.6-sol"] = { input = 0, cached_input = 0, output = 0 }
  assert_equal(pricing.cost_text(pricing.estimate("Sol", usage, custom)), "Cost ~$0.00", "zero custom price")
  assert_equal(pricing.cache_rate({ input_raw = 0, cached = 0 }), nil, "zero input has unknown ratio")
  assert_equal(pricing.cache_rate({ input_raw = 3000, cached = 1000 }), 33.3, "fractional cache ratio")
  assert_equal(pricing.cache_rate({ input_raw = 100, cached = 200 }), 100, "cache ratio cannot exceed 100")
  assert_equal(pricing.estimate("Sol", { output = 100000 }), nil, "missing input cannot estimate cost")
  assert_equal(pricing.cost_text(pricing.estimate("Sol", { input_raw = 1000, cached = 800, output = 100 })),
    "Cost <$0.01", "small cost stays visible")
  assert_equal(pricing.cost_text(pricing.estimate("Sol", { input = 200000, cached = 800000, output = 100000 })),
    "Cost ~$3.12", "legacy net input reconstructs raw input")
  assert_equal(pricing.valid_price({ input = -1, cached_input = 0, output = 1 }), false, "negative prices rejected")
  assert_equal(pricing.valid_price({ input = 1, output = 1 }), false, "incomplete prices rejected")
end

do
  local options = { bottom_pane = { rows = 1 }, render = { powerline = true } }
  local examples = {
    { "gpt-6-astra", "✦" }, { "gpt-5.6-sol", "☀" },
    { "openai/gpt-5.6-terra", "⊕" }, { "GPT-5.6-LUNA", "☾" },
    { "Astra", "✦" }, { "Sol", "☀" }, { "Terra", "⊕" }, { "Luna", "☾" },
    { "gpt-5.6-codex" }, { "solar" }, { "terramodel" }, { "lunatic" }, { "toString" }, { "" }, {},
  }
  for _, display in ipairs({ false, "name", "icon_name", "icon" }) do
    options.render.model_display = display or nil
    for _, example in ipairs(examples) do
      local model, icon = example[1], example[2]
      local expected = model ~= "" and model or nil
      if icon and (display == "icon" or display == "icon_name") then
        expected = display == "icon" and icon or (icon .. " " .. model)
      end
      for _, columns in ipairs({ 50, 140 }) do
        local plan = core.build_render_plan(options, { model = model }, columns)
        local actual = nil
        for _, line in ipairs(plan.lines) do
          for _, segment in ipairs(line) do
            if segment.kind == "model" then actual = segment.text end
          end
        end
        assert_equal(actual, expected, "model display " .. tostring(model) .. " " .. tostring(display) .. " " .. columns)
      end
    end
  end
  options.render.disabled_segments = { "model" }
  local plan = core.build_render_plan(options, { model = "gpt-6-astra" }, 140)
  for _, segment in ipairs(plan.lines[1]) do
    assert_equal(segment.kind == "model", false, "model icon respects disabled segment")
  end
end

do
  local activity = core.merge_activity_state(nil, {
    type = "turn_context",
    payload = { collaboration_mode = { mode = "plan" } },
  })
  assert_equal(activity.mode, "plan", "plan mode enters from turn context")

  activity = core.merge_activity_state(activity, {
    type = "event_msg",
    payload = {
      type = "thread_goal_updated",
      goal = {
        status = "usageLimited",
        tokenBudget = 10000,
        tokensUsed = 2400,
        timeUsedSeconds = 15,
      },
    },
  })
  assert_equal(activity.goal.status, "usage_limited", "goal status normalizes camel case")
  assert_equal(activity.goal.token_budget, 10000, "goal budget normalizes camel case")

  activity = core.merge_activity_state(activity, {
    type = "event_msg",
    payload = { type = "entered_review_mode" },
  })
  assert_equal(activity.review, true, "legacy review event enters")

  activity = core.merge_activity_state(activity, {
    type = "event_msg",
    payload = { type = "exited_review_mode" },
  })
  assert_equal(activity.review, false, "legacy review event exits")

  activity = core.merge_activity_state(activity, {
    type = "event_msg",
    payload = { type = "item_completed", item = { type = "entered_review_mode" } },
  })
  assert_equal(activity.review, true, "paginated review item enters")

  activity = core.merge_activity_state(activity, {
    type = "event_msg",
    payload = { type = "item_completed", item = { type = "exited_review_mode" } },
  })
  assert_equal(activity.review, false, "paginated review item exits")

  activity = core.merge_activity_state(activity, {
    type = "turn_context",
    payload = { collaboration_mode = { mode = "default" } },
  })
  assert_equal(activity.mode, "default", "default mode exits plan")
end

do
  local disabled = {
    "label", "model", "reasoning", "provider", "personality", "service_tier", "cwd", "project", "git",
    "permissions", "approval", "context", "context_used", "context_window", "used_tokens", "input_tokens",
    "cached_tokens", "output_tokens", "reasoning_tokens", "thread_id", "task_progress", "codex_version",
  }
  local options = {
    bottom_pane = { rows = 1 },
    render = {
      powerline = false,
      segment_order = core.DEFAULT_SEGMENT_ORDER,
      disabled_segments = disabled,
    },
    theme = { bg = "#111111", fg = "#eeeeee", segments = {} },
  }
  local labels = {
    active = "GOAL",
    paused = "GOAL PAUSED",
    blocked = "GOAL BLOCKED",
    usage_limited = "GOAL LIMITED",
    budget_limited = "GOAL BUDGET",
    complete = "GOAL DONE",
  }

  for status, expected in pairs(labels) do
    local plan = core.build_render_plan(options, {
      activity = { mode = "default", review = false, goal = { status = status } },
    }, 120)
    assert_equal(plan.lines[1][1].text, expected, "goal label " .. status)
    assert_equal(plan.lines[1][2].kind, "icon", "goal icon remains rightmost " .. status)
  end

  local plan = core.build_render_plan(options, {
    activity = { mode = "plan", review = false, goal = { status = "blocked" } },
  }, 120)
  assert_equal(plan.lines[1][1].text, "PLAN", "plan takes priority over goal")

  plan = core.build_render_plan(options, {
    activity = { mode = "plan", review = true, goal = { status = "blocked" } },
  }, 120)
  assert_equal(plan.lines[1][1].text, "REVIEW", "review takes priority over plan and goal")
  assert_equal(plan.lines[1][2].kind, "icon", "wide icon remains rightmost")
end

do
  local settings = core.extract_thread_settings({
    type = "event_msg",
    payload = { type = "thread_settings_applied", thread_settings = { model = "gpt-test" } },
  })
  assert_equal(settings.model, "gpt-test", "thread settings extraction")
end

do
  local pricing = require("codex_statusline.domain.pricing")
  local function context(history, model)
    core.record_cost_usage(history, { type = "turn_context", payload = { model = model } })
  end
  local function counts(input, cached, output)
    return { input_tokens = input, cached_input_tokens = cached, output_tokens = output }
  end
  local function usage(history, total, last)
    core.record_cost_usage(history, { type = "event_msg", payload = {
      type = "token_count", info = { total_token_usage = total, last_token_usage = last },
    } })
  end
  local function cost(history, model, overrides)
    return pricing.cost_text(pricing.estimate(model, {
      by_model = history.by_model, cost_complete = history.complete,
    }, overrides))
  end
  local history = core.new_cost_history()
  local first = counts(1000000, 800000, 100000)
  local second = counts(2000000, 1600000, 200000)
  context(history, "gpt-5.6-sol")
  usage(history, first, first)
  assert_equal(cost(history, "gpt-5.6-sol"), "Cost ~$3.12", "first model cost")
  -- Changing the selected model while a request finishes must not reattribute it.
  core.record_cost_usage(history, { type = "event_msg", payload = {
    type = "thread_settings_applied", thread_settings = { model = "gpt-6-astra" },
  } })
  usage(history, second, first)
  assert_equal(cost(history, "gpt-6-astra"), "Cost ~$6.24", "in-flight request uses its turn model")
  context(history, "gpt-6-astra")
  usage(history, second, first)
  assert_equal(history.by_model["gpt-6-astra"], nil, "repeated totals add no usage after switch")
  assert_equal(cost(history, "unknown"), "Cost ~$6.24", "selected model never reprices past usage")
  usage(history, counts(3000000, 2400000, 300000), first)
  assert_equal(cost(history, "gpt-6-astra"), "Cost ~$14.04", "different model costs accumulate")
  context(history, "gpt-5.6-sol")
  usage(history, counts(4000000, 3200000, 400000), first)
  assert_equal(cost(history, "gpt-5.6-sol"), "Cost ~$17.16", "switching back retains both models")
  assert_equal(cost(history, "gpt-5.6-sol", { models = {
    ["gpt-5.6-sol"] = { input = 0, cached_input = 0, output = 0 },
  } }), "Cost ~$7.80", "custom price changes only its model subtotal")

  local unknown = core.new_cost_history()
  usage(unknown, first, first)
  context(unknown, "gpt-5.6-sol")
  usage(unknown, second, first)
  assert_equal(cost(unknown, "gpt-5.6-sol"), "Cost —", "missing historical model is not guessed")

  local inherited = core.new_cost_history()
  context(inherited, "gpt-5.6-sol")
  usage(inherited, second, first)
  assert_equal(cost(inherited, "gpt-5.6-sol"), "Cost —", "unrecorded prefix is not billed at first visible model")

  local reset = core.new_cost_history()
  context(reset, "gpt-5.6-sol")
  usage(reset, first, first)
  usage(reset, counts(100, 0, 10), counts(100, 0, 10))
  assert_equal(cost(reset, "gpt-5.6-sol"), "Cost —", "counter reset never subtracts past cost")

  local missing = core.new_cost_history()
  context(missing, "gpt-5.6-sol")
  usage(missing, nil, first)
  assert_equal(cost(missing, "gpt-5.6-sol"), "Cost —", "last usage alone cannot deduplicate requests")

  local no_price = core.new_cost_history()
  context(no_price, "custom-model")
  usage(no_price, first, first)
  context(no_price, "gpt-5.6-sol")
  usage(no_price, second, first)
  assert_equal(cost(no_price, "gpt-5.6-sol"), "Cost —", "unknown historical price hides incomplete total")
  assert_equal(cost(no_price, "gpt-5.6-sol", { models = {
    ["custom-model"] = { input = 4, cached_input = 0.4, output = 20 },
  } }), "Cost ~$6.24", "adding a missing price resolves historical cost")

  local collaboration = core.new_cost_history()
  core.record_cost_usage(collaboration, { type = "turn_context", payload = {
    collaboration_mode = { settings = { model = "gpt-5.6-sol" } },
  } })
  usage(collaboration, first, first)
  assert_equal(cost(collaboration, "gpt-6-astra"), "Cost ~$3.12", "collaboration model fallback")
  core.record_cost_usage(collaboration, { type = "turn_context", payload = {
    model = "gpt-6-astra", collaboration_mode = { settings = { model = "gpt-5.6-sol" } },
  } })
  usage(collaboration, second, first)
  assert_equal(cost(collaboration, "gpt-5.6-sol"), "Cost ~$10.92", "actual request model precedes selection")
end

return true
