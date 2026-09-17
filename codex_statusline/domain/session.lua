local M = {}
local BASELINE_TOKENS = 12000
local common = require("codex_statusline.domain.common")
local trim = common.trim
local to_number = common.to_number
function M.normalize_path(value, windows)
  local path = trim(value)
  if not path then
    return nil
  end

  local use_windows = windows
  if use_windows == nil then
    use_windows = package.config:sub(1, 1) == "\\"
  end
  if use_windows then
    path = path:gsub("/", "\\")
    -- WezTerm may expose a Windows file URL as /C:/path while Codex records C:\\path.
    path = path:gsub("^\\([A-Za-z]:\\)", "%1")
    path = path:lower()
  end
  path = path:gsub("[\\/]+$", "")
  return path ~= "" and path or nil
end

function M.extract_usage_struct(value)
  if type(value) ~= "table" then
    return nil
  end
  local usage = {
    input_tokens = to_number(value.input_tokens),
    cached_input_tokens = to_number(value.cached_input_tokens),
    output_tokens = to_number(value.output_tokens),
    reasoning_output_tokens = to_number(value.reasoning_output_tokens),
    total_tokens = to_number(value.total_tokens),
  }
  if
    usage.input_tokens == nil
    and usage.cached_input_tokens == nil
    and usage.output_tokens == nil
    and usage.reasoning_output_tokens == nil
    and usage.total_tokens == nil
  then
    return nil
  end
  return usage
end

function M.extract_token_usage_info(object)
  if type(object) ~= "table" then
    return nil
  end
  if object.type ~= "event_msg" or type(object.payload) ~= "table" or object.payload.type ~= "token_count" then
    return nil
  end
  if type(object.payload.info) ~= "table" then
    return nil
  end

  local info = object.payload.info
  local total = M.extract_usage_struct(info.total_token_usage)
  local last = M.extract_usage_struct(info.last_token_usage)
  if not total and not last then
    return nil
  end
  return {
    total = total,
    last = last,
    model_context_window = to_number(info.model_context_window),
  }
end

function M.context_remaining_percent(context_tokens, context_window)
  local used_total = to_number(context_tokens)
  local window = to_number(context_window)
  if not used_total or not window then
    return nil
  end
  if window <= BASELINE_TOKENS then
    return 0
  end

  local effective_window = window - BASELINE_TOKENS
  local used = math.max(used_total - BASELINE_TOKENS, 0)
  local remaining = math.max(effective_window - used, 0)
  local percent = (remaining / effective_window) * 100
  return math.max(0, math.min(100, math.floor(percent + 0.5)))
end

function M.build_usage(total_usage, last_usage, context_window)
  if type(total_usage) ~= "table" and type(last_usage) ~= "table" then
    return nil
  end

  local cumulative = total_usage or last_usage
  local input_raw = math.max(0, to_number(cumulative.input_tokens) or 0)
  local cached = math.max(0, to_number(cumulative.cached_input_tokens) or 0)
  local input = math.max(0, input_raw - cached)
  local output = math.max(0, to_number(cumulative.output_tokens) or 0)
  local reasoning = math.max(0, to_number(cumulative.reasoning_output_tokens) or 0)
  local context_tokens = type(last_usage) == "table" and to_number(last_usage.total_tokens) or nil
  local window = to_number(context_window)

  return {
    total = input + output,
    input = input,
    input_raw = input_raw,
    cached = cached,
    output = output,
    reasoning = reasoning,
    accumulated_total = to_number(cumulative.total_tokens),
    context_tokens = context_tokens,
    context_window = window,
    context_remaining_percent = M.context_remaining_percent(context_tokens, window),
  }
end

function M.merge_context_window(current, candidate)
  local next_value = to_number(candidate)
  if next_value and next_value > 0 then
    return next_value
  end
  return to_number(current)
end

function M.inactivity_grace_elapsed(started_at, now, grace_seconds)
  local started = to_number(started_at)
  local current = to_number(now)
  if not started or not current then
    return false
  end
  local grace = math.max(0, to_number(grace_seconds) or 0)
  return (current - started) >= grace
end

function M.waiting_status(rollout_path, rollout_source, bridge_wait_reason)
  if trim(rollout_path) then
    return {
      kind = "token-data",
      long = "Token usage: waiting for first response",
      short = "tokens: waiting for response",
      minimal = "tokens: waiting",
    }
  end

  if trim(rollout_source) == "bridge-waiting" then
    local reason = trim(bridge_wait_reason)
    if reason == "mapping-unavailable" or reason == "bridge-root-unavailable" or reason == "pane-id-unavailable" then
      return {
        kind = "bridge",
        long = "Session: waiting for bridge",
        short = "bridge: waiting",
        minimal = "waiting",
      }
    end
  end

  return {
    kind = "rollout",
    long = "Session: waiting for rollout",
    short = "rollout: waiting",
    minimal = "waiting",
  }
end

function M.extract_turn_context(object)
  if type(object) == "table" and object.type == "turn_context" and type(object.payload) == "table" then
    return object.payload
  end
  return nil
end

-- Keep token counts per request model, so price overrides can be applied at
-- render time without repricing the entire thread as its currently selected model.
function M.new_cost_history()
  return { offset = 0, by_model = {}, complete = true }
end

local function cost_counts(usage)
  if type(usage) ~= "table" then return nil end
  local result = {}
  for _, key in ipairs({ "input_tokens", "cached_input_tokens", "output_tokens" }) do
    local value = to_number(usage[key])
    if not value or value < 0 or value ~= value or value == math.huge then return nil end
    result[key] = value
  end
  if result.cached_input_tokens > result.input_tokens then return nil end
  return result
end

function M.record_cost_usage(history, object)
  local context = M.extract_turn_context(object)
  if context then
    local collaboration = type(context.collaboration_mode) == "table" and context.collaboration_mode.settings or nil
    history.model = trim(context.model) or (type(collaboration) == "table" and trim(collaboration.model) or nil)
    return
  end

  -- Thread settings describe the selected model, which may change while a
  -- request is still finishing. Its usage belongs to that request's turn context.
  local info = M.extract_token_usage_info(object)
  if not info then return end
  local total = cost_counts(info.total)
  if not total then
    history.complete = false
    return
  end

  local previous = history.total
  history.total = total
  local delta, changed = {}, false
  for key, value in pairs(total) do
    delta[key] = value - (previous and previous[key] or 0)
    if delta[key] < 0 then
      -- A reset/correction cannot be assigned to a model reliably.
      history.complete = false
      return
    end
    changed = changed or delta[key] > 0
  end
  if not changed then return end -- Codex also emits repeated cumulative totals.

  local last = cost_counts(info.last)
  if not previous and not last then
    history.complete = false
    return
  end
  if last then
    for key, value in pairs(delta) do
      if value ~= last[key] then
        -- Includes resumed/forked logs whose first total contains missing history.
        history.complete = false
        return
      end
    end
  end
  if not history.model or delta.cached_input_tokens > delta.input_tokens then
    history.complete = false
    return
  end

  local counts = history.by_model[history.model] or { input_raw = 0, cached = 0, output = 0 }
  counts.input_raw = counts.input_raw + delta.input_tokens
  counts.cached = counts.cached + delta.cached_input_tokens
  counts.output = counts.output + delta.output_tokens
  history.by_model[history.model] = counts
end

local function normalized_event_type(value)
  local text = trim(value)
  if not text then
    return nil
  end
  text = text:gsub("(%l)(%u)", "%1_%2")
  text = text:gsub("[%s%-]+", "_")
  return text:lower()
end

local GOAL_STATUSES = {
  active = true,
  paused = true,
  blocked = true,
  usage_limited = true,
  budget_limited = true,
  complete = true,
}

local function copy_table(value)
  local result = {}
  for key, item in pairs(type(value) == "table" and value or {}) do
    result[key] = item
  end
  return result
end

-- Fold one persisted rollout item into a compact, renderer-facing activity
-- snapshot. The function returns a new table so callers can test transitions
-- without sharing mutable state.
function M.merge_activity_state(current, object)
  local state = copy_table(current)
  state.mode = normalized_event_type(state.mode) == "plan" and "plan" or "default"
  state.review = state.review == true
  if type(state.goal) == "table" then
    state.goal = copy_table(state.goal)
  end

  if type(object) ~= "table" then
    return state
  end

  if object.type == "turn_context" and type(object.payload) == "table" then
    local collaboration = object.payload.collaboration_mode
    local mode = type(collaboration) == "table" and collaboration.mode or collaboration
    mode = normalized_event_type(mode)
    if mode == "plan" or mode == "default" then
      state.mode = mode
    end
    return state
  end

  if object.type ~= "event_msg" or type(object.payload) ~= "table" then
    return state
  end

  local payload = object.payload
  local event_type = normalized_event_type(payload.type)
  local review_type = event_type
  if event_type == "item_completed" and type(payload.item) == "table" then
    review_type = normalized_event_type(payload.item.type)
  end

  if review_type == "entered_review_mode" then
    state.review = true
  elseif review_type == "exited_review_mode" then
    state.review = false
  end

  if event_type == "thread_goal_updated" and type(payload.goal) == "table" then
    local goal = payload.goal
    local status = normalized_event_type(goal.status)
    if GOAL_STATUSES[status] then
      state.goal = {
        status = status,
        token_budget = to_number(goal.token_budget or goal.tokenBudget),
        tokens_used = to_number(goal.tokens_used or goal.tokensUsed),
        time_used_seconds = to_number(goal.time_used_seconds or goal.timeUsedSeconds),
      }
    end
  end

  return state
end

function M.extract_thread_settings(object)
  if type(object) ~= "table" or object.type ~= "event_msg" or type(object.payload) ~= "table" then
    return nil
  end
  local payload = object.payload
  local event_type = normalized_event_type(payload.type)
  if event_type == "session_configured" then
    return payload
  end
  if event_type == "thread_settings_applied" and type(payload.thread_settings) == "table" then
    return payload.thread_settings
  end
  return nil
end

M.normalized_event_type = normalized_event_type

local UUID_PATTERN = "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$"

function M.validate_bridge_mapping(value, pane_id)
  if type(value) ~= "table" then
    return nil, "mapping-not-object"
  end
  local schema = tonumber(value.schema)
  if schema ~= 1 then
    return nil, "unsupported-schema"
  end
  if tostring(value.pane_id or "") ~= tostring(pane_id or "") then
    return nil, "pane-mismatch"
  end

  local thread_id = trim(value.thread_id)
  if not thread_id or not thread_id:match(UUID_PATTERN) then
    return nil, "invalid-thread-id"
  end
  local generation = trim(value.generation)
  if not generation then
    return nil, "missing-generation"
  end

  return {
    schema = schema,
    pane_id = tostring(value.pane_id),
    thread_id = thread_id:lower(),
    session_id = trim(value.session_id),
    rollout_path = trim(value.rollout_path),
    cwd = trim(value.cwd),
    source = trim(value.source),
    generation = generation,
    written_at_unix_ms = to_number(value.written_at_unix_ms),
  }
end

function M.event_timestamp(object)
  if type(object) ~= "table" then
    return nil
  end
  return trim(object.timestamp)
end

function M.select_recent_rollout(entries)
  local candidates = {}
  for _, entry in ipairs(entries or {}) do
    table.insert(candidates, entry)
  end
  table.sort(candidates, function(a, b)
    local activity_a = trim(a._activity_timestamp) or trim(a.timestamp) or ""
    local activity_b = trim(b._activity_timestamp) or trim(b.timestamp) or ""
    if activity_a ~= activity_b then
      return activity_a > activity_b
    end
    return tostring(a._rollout_path or "") > tostring(b._rollout_path or "")
  end)
  return candidates[1]
end

function M.select_unique_active_rollout(entries, cwd_norm, cutoff_timestamp)
  local expected_cwd = trim(cwd_norm)
  local cutoff = trim(cutoff_timestamp)
  if not expected_cwd or not cutoff then
    return nil, "fallback-input-unavailable", 0
  end

  local candidates = {}
  for _, entry in ipairs(entries or {}) do
    local activity = trim(entry._activity_timestamp) or trim(entry.timestamp)
    if entry._cwd_norm == expected_cwd and activity and activity >= cutoff then
      table.insert(candidates, entry)
    end
  end

  if #candidates == 0 then
    return nil, "no-active-rollout", 0
  end
  if #candidates > 1 then
    return nil, "ambiguous-active-rollouts", #candidates
  end
  return candidates[1], nil, 1
end

function M.tail_start(file_size, saved_offset, initial_seek_bytes)
  local size = math.max(0, tonumber(file_size) or 0)
  local offset = math.max(0, tonumber(saved_offset) or 0)
  if offset > size then
    offset = 0
  end
  local seek_bytes = tonumber(initial_seek_bytes)
  if offset == 0 and seek_bytes and seek_bytes > 0 and size > seek_bytes then
    return math.max(0, size - seek_bytes), true
  end
  return offset, false
end

M.BASELINE_TOKENS = BASELINE_TOKENS
M.GOAL_STATUSES = GOAL_STATUSES
return M
