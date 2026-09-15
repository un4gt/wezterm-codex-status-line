local M = {}
local common = require("codex_statusline.domain.common")
local trim = common.trim
local to_number = common.to_number
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

local function split_title_parts(value)
  local text = trim(value)
  if not text then
    return {}
  end

  local parts = {}
  local offset = 1
  while true do
    local first, last = text:find("%s+|%s+", offset)
    if not first then
      table.insert(parts, trim(text:sub(offset)))
      break
    end
    table.insert(parts, trim(text:sub(offset, first - 1)))
    offset = last + 1
  end
  return parts
end

function M.parse_codex_terminal_title(value, app_name)
  local expected_app = (trim(app_name) or "codex"):lower()
  local parts = split_title_parts(value)
  for index, part in ipairs(parts) do
    if part and part:lower() == expected_app then
      local reasoning = trim(parts[index + 1])
      local project = trim(parts[index + 2])
      if reasoning and project and not reasoning:find("[%c]") then
        return {
          app_name = part,
          reasoning = reasoning:lower(),
          project = project,
          part_index = index,
        }
      end
    end
  end
  return nil
end

-- A managed title corroborates process lifecycle state and carries live
-- reasoning. A missing title alone is not an exit signal because child tools
-- may temporarily replace it.
function M.update_title_bridge_state(current, signal, title_read_ok, process_state, process_id)
  local state = type(current) == "table" and current or {}
  local pid = to_number(process_id)
  if type(signal) == "table" then
    state.seen = true
    state.ended = false
    state.reasoning = trim(signal.reasoning)
    state.process_id = pid or state.process_id
    return state, true, "terminal-title"
  end

  if state.ended then
    if process_state == true and pid and (not state.process_id or pid ~= state.process_id) then
      state.seen = false
      state.ended = false
      state.reasoning = nil
      state.process_id = pid
      return state, nil, "process-generation"
    end
    if process_state == false then
      state.seen = false
      state.ended = false
      state.reasoning = nil
      state.process_id = nil
    end
    return state, false, "terminal-title-ended"
  end

  if title_read_ok and state.seen and process_state == false then
    state.ended = true
    state.reasoning = nil
    state.process_id = state.process_id or pid
    return state, false, "terminal-title-ended"
  end

  return state, nil, nil
end

return M
