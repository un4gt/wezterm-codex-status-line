local M = {}

local BASELINE_TOKENS = 12000

local function trim(value)
  if value == nil then
    return nil
  end
  local text = tostring(value):gsub("^%s+", ""):gsub("%s+$", "")
  if text == "" then
    return nil
  end
  return text
end

local function basename(path)
  local value = trim(path)
  if not value then
    return nil
  end
  return value:match("([^/\\]+)$") or value
end

local function lower_set(values)
  local out = {}
  for _, value in ipairs(values or {}) do
    local item = trim(value)
    if item then
      out[item:lower()] = true
    end
  end
  return out
end

local function argv_text(argv)
  if type(argv) ~= "table" then
    return ""
  end
  local parts = {}
  for _, value in pairs(argv) do
    if value ~= nil then
      table.insert(parts, tostring(value):gsub("\\", "/"):lower())
    end
  end
  return table.concat(parts, "\0")
end

local function process_match(node, options)
  if type(node) ~= "table" then
    return nil
  end

  local names = options._name_set or lower_set(options.names)
  local executable = basename(trim(node.executable) or trim(node.name))
  if executable and names[executable:lower()] then
    return {
      pid = tonumber(node.pid),
      kind = "native",
      executable = trim(node.executable) or trim(node.name),
    }
  end

  local command_line = argv_text(node.argv)
  for _, marker in ipairs(options.argv_markers or {}) do
    local normalized = tostring(marker):gsub("\\", "/"):lower()
    if normalized ~= "" and command_line:find(normalized, 1, true) then
      return {
        pid = tonumber(node.pid),
        kind = "wrapper",
        executable = trim(node.executable) or trim(node.name),
      }
    end
  end

  return nil
end

local function better_process_match(current, candidate)
  if not candidate then
    return current
  end
  if not current then
    return candidate
  end
  if current.kind ~= "native" and candidate.kind == "native" then
    return candidate
  end
  return current
end

local function scan_descendants(node, options, depth, seen)
  if type(node) ~= "table" or depth > (options.max_descendant_depth or 10) then
    return nil
  end
  if seen[node] then
    return nil
  end
  seen[node] = true

  local best = process_match(node, options)
  for _, child in pairs(type(node.children) == "table" and node.children or {}) do
    best = better_process_match(best, scan_descendants(child, options, depth + 1, seen))
  end
  return best
end

local function is_terminal_boundary(node, options)
  if type(node) ~= "table" then
    return false
  end
  local name = basename(trim(node.executable) or trim(node.name))
  return name ~= nil and options._terminal_set[name:lower()] == true
end

-- The initial LocalProcessInfo is scoped to one pane. Descendant scanning is safe
-- there, but ancestor descendants are siblings and may belong to other panes.
function M.inspect_codex_process(info, get_parent, process_options)
  if type(info) ~= "table" then
    return { state = nil, reason = "foreground-unavailable" }
  end

  local options = {}
  for key, value in pairs(process_options or {}) do
    options[key] = value
  end
  options._name_set = lower_set(options.names or { "codex", "codex.exe" })
  options._terminal_set = lower_set(options.terminal_names or {
    "wezterm",
    "wezterm.exe",
    "wezterm-gui",
    "wezterm-gui.exe",
    "wezterm-mux-server-impl",
    "wezterm-mux-server-impl.exe",
  })

  local foreground_pid = tonumber(info.pid)
  local matched = scan_descendants(info, options, 0, {})
  if matched then
    matched.state = true
    matched.foreground_pid = foreground_pid
    return matched
  end

  if type(get_parent) ~= "function" then
    return { state = nil, foreground_pid = foreground_pid, reason = "parent-api-unavailable" }
  end

  local seen_pids = {}
  local ppid = tonumber(info.ppid)
  local checked = 0
  local max_depth = options.max_ancestor_depth or 12
  while ppid and ppid > 0 and checked < max_depth and not seen_pids[ppid] do
    seen_pids[ppid] = true
    local parent = get_parent(ppid)
    if type(parent) ~= "table" then
      return {
        state = nil,
        foreground_pid = foreground_pid,
        reason = checked == 0 and "parent-unavailable" or "parent-chain-incomplete",
      }
    end
    checked = checked + 1

    local parent_match = process_match(parent, options)
    if parent_match then
      parent_match.state = true
      parent_match.foreground_pid = foreground_pid
      return parent_match
    end
    if is_terminal_boundary(parent, options) then
      return { state = false, foreground_pid = foreground_pid, reason = "terminal-boundary" }
    end

    ppid = tonumber(parent.ppid)
  end

  return { state = false, foreground_pid = foreground_pid, reason = "process-chain-exhausted" }
end

local function to_number(value)
  if type(value) == "number" then
    return value
  end
  if type(value) == "string" then
    return tonumber(value:gsub(",", ""))
  end
  return nil
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

function M.extract_turn_context(object)
  if type(object) == "table" and object.type == "turn_context" and type(object.payload) == "table" then
    return object.payload
  end
  return nil
end

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

return M
