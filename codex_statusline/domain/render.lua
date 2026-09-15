local M = {}
local version = require("codex_statusline.version")
local common = require("codex_statusline.domain.common")
local session = require("codex_statusline.domain.session")
local pricing = require("codex_statusline.domain.pricing")
local BASELINE_TOKENS = session.BASELINE_TOKENS
local GOAL_STATUSES = session.GOAL_STATUSES
local trim = common.trim
local to_number = common.to_number
local normalized_event_type = session.normalized_event_type
local MODEL_ICONS = { astra = "✦", sol = "☀", terra = "⊕", luna = "☾" }

function M.model_text(model, display)
  if not model or (display ~= "icon_name" and display ~= "icon") then
    return model
  end
  for token in model:lower():gmatch("[a-z0-9]+") do
    local icon = MODEL_ICONS[token]
    if icon then
      return display == "icon" and icon or (icon .. " " .. model)
    end
  end
  return model
end

function M.render_layout_key(pane_id, cols, rows, font_size)
  return table.concat({
    tostring(pane_id or "?"),
    tostring(to_number(cols) or "?"),
    tostring(to_number(rows) or "?"),
    tostring(to_number(font_size) or "?"),
  }, "|")
end

local LEGACY_SEGMENT_ORDER = {
  "label",
  "model",
  "reasoning",
  "provider",
  "cwd",
  "git",
  "context",
  "used_tokens",
}

local DEFAULT_SEGMENT_ORDER = {
  "label",
  "model",
  "reasoning",
  "activity",
  "provider",
  "personality",
  "service_tier",
  "cwd",
  "project",
  "git",
  "permissions",
  "approval",
  "context",
  "context_used",
  "context_window",
  "used_tokens",
  "cache_rate",
  "cost",
  "input_tokens",
  "cached_tokens",
  "output_tokens",
  "reasoning_tokens",
  "thread_id",
  "task_progress",
  "codex_version",
  "icon",
}

local DROP_ORDER = {
  "provider",
  "personality",
  "service_tier",
  "codex_version",
  "thread_id",
  "approval",
  "permissions",
  "cached_tokens",
  "reasoning_tokens",
  "input_tokens",
  "output_tokens",
  "context_window",
  "context_used",
  "task_progress",
  "project",
  "cwd",
  "cache_rate",
  "cost",
  "used_tokens",
  "git",
  "reasoning",
  "model",
}

local function compact_trim(value)
  return value:gsub("(%..-)0+$", "%1"):gsub("%.$", "")
end

function M.compact_number(value)
  local number = to_number(value)
  if not number then
    return nil
  end
  local sign = number < 0 and "-" or ""
  local absolute = math.abs(number)
  if absolute < 1000 then
    return sign .. tostring(math.floor(absolute + 0.5))
  end

  local units = {
    { 1000000000000, "T" },
    { 1000000000, "B" },
    { 1000000, "M" },
    { 1000, "K" },
  }
  for _, unit in ipairs(units) do
    if absolute >= unit[1] then
      local scaled = absolute / unit[1]
      local formatted = nil
      if scaled < 10 then
        formatted = string.format("%.2f", scaled)
      elseif scaled < 100 then
        formatted = string.format("%.1f", scaled)
      else
        formatted = string.format("%.0f", scaled)
      end
      local rounded = tonumber(formatted) or scaled
      if rounded >= 1000 then
        for next_index, next_unit in ipairs(units) do
          if next_unit[1] > unit[1] and absolute >= next_unit[1] * 0.9995 then
            local next_scaled = absolute / next_unit[1]
            local next_formatted = next_scaled < 10 and string.format("%.2f", next_scaled)
              or (next_scaled < 100 and string.format("%.1f", next_scaled) or string.format("%.0f", next_scaled))
            return sign .. compact_trim(next_formatted) .. next_unit[2]
          end
        end
      end
      return sign .. compact_trim(formatted) .. unit[2]
    end
  end
  return sign .. tostring(math.floor(absolute + 0.5))
end

function M.context_bar(percent, cells)
  local value = math.max(0, math.min(100, to_number(percent) or 0))
  local width = math.max(1, math.floor(to_number(cells) or 10))
  local filled = math.max(0, math.min(width, math.floor((value / 100) * width + 0.5)))
  return string.rep("█", filled) .. string.rep("░", width - filled)
end

function M.render_layout(columns)
  local cols = math.max(1, math.floor(to_number(columns) or 120))
  if cols < 60 then
    return "tiny"
  end
  if cols < 90 then
    return "narrow"
  end
  if cols < 120 then
    return "medium"
  end
  return "wide"
end

local function list_set(values)
  local result = {}
  for key, value in pairs(type(values) == "table" and values or {}) do
    if type(key) == "number" then
      result[tostring(value)] = true
    elseif value == true then
      result[tostring(key)] = true
    end
  end
  return result
end

local function text_width(value)
  local text = tostring(value or "")
  if type(utf8) == "table" and type(utf8.len) == "function" then
    local ok, length = pcall(utf8.len, text)
    if ok and length then
      return length
    end
  end
  return #text
end

local function plan_width(segments, powerline)
  local width = 0
  for index, segment in ipairs(segments) do
    width = width + text_width(segment.text) + (powerline and 2 or 0)
    if index < #segments then
      width = width + (powerline and 1 or 2)
    end
  end
  return width
end

local function theme_for(options, id)
  local theme = type(options.theme) == "table" and options.theme or {}
  local themes = type(theme.segments) == "table" and theme.segments or {}
  local aliases = {
    reasoning = "thinking",
    context = "tokens",
    context_used = "tokens",
    context_window = "tokens",
    used_tokens = "tokens",
    cache_rate = "tokens",
    cost = "tokens",
    input_tokens = "tokens",
    cached_tokens = "tokens",
    output_tokens = "tokens",
    reasoning_tokens = "tokens",
  }
  local value = themes[id] or themes[aliases[id]] or {}
  return value.bg or theme.bg or "#11151a", value.fg or theme.fg or "#d5dbe3"
end

local function ordered_ids(options)
  local render = type(options.render) == "table" and options.render or {}
  local configured = type(render.segment_order) == "table" and render.segment_order or DEFAULT_SEGMENT_ORDER
  local result = {}
  local seen = {}
  for _, id in ipairs(configured) do
    id = tostring(id)
    if not seen[id] then
      seen[id] = true
      table.insert(result, id)
    end
  end

  local legacy = #configured > 0
  local legacy_set = list_set(LEGACY_SEGMENT_ORDER)
  for _, id in ipairs(configured) do
    if not legacy_set[tostring(id)] then
      legacy = false
      break
    end
  end
  local appendable = legacy and { "activity", "icon" } or DEFAULT_SEGMENT_ORDER
  for _, id in ipairs(appendable) do
    if not seen[id] then
      seen[id] = true
      table.insert(result, id)
    end
  end

  local anchored = {}
  for _, id in ipairs(result) do
    if id ~= "icon" then
      table.insert(anchored, id)
    end
  end
  if seen.icon then
    table.insert(anchored, "icon")
  end
  return anchored
end

local DEFAULT_ACTIVITY_LABELS = {
  plan = "PLAN",
  review = "REVIEW",
  goal_active = "GOAL",
  goal_paused = "GOAL PAUSED",
  goal_blocked = "GOAL BLOCKED",
  goal_usage_limited = "GOAL LIMITED",
  goal_budget_limited = "GOAL BUDGET",
  goal_complete = "GOAL DONE",
}

local function activity_text(options, snapshot)
  local activity = type(snapshot.activity) == "table" and snapshot.activity or {}
  local configured = type(options.activity) == "table" and options.activity.labels or nil
  local labels = type(configured) == "table" and configured or DEFAULT_ACTIVITY_LABELS
  if activity.review == true then
    return labels.review or DEFAULT_ACTIVITY_LABELS.review
  end
  if normalized_event_type(activity.mode) == "plan" then
    return labels.plan or DEFAULT_ACTIVITY_LABELS.plan
  end
  local status = type(activity.goal) == "table" and normalized_event_type(activity.goal.status) or nil
  if status and GOAL_STATUSES[status] then
    local key = "goal_" .. status
    return labels[key] or DEFAULT_ACTIVITY_LABELS[key]
  end
  return nil
end

local function segment_text(id, options, snapshot, layout)
  if id == "label" then
    return snapshot.label or options.label or "CODEX"
  end
  if id == "model" then
    return M.model_text(snapshot.model, type(options.render) == "table" and options.render.model_display or nil)
  end
  if id == "reasoning" then
    return snapshot.reasoning
  end
  if id == "activity" then
    return activity_text(options, snapshot)
  end
  if id == "provider" then
    if layout == "wide" and snapshot.provider then
      return "p:" .. tostring(snapshot.provider)
    end
    return snapshot.provider
  end
  if id == "personality" then
    return snapshot.personality and ("persona:" .. tostring(snapshot.personality)) or nil
  end
  if id == "service_tier" then
    return snapshot.service_tier and ("tier:" .. tostring(snapshot.service_tier)) or nil
  end
  if id == "cwd" then
    return snapshot.cwd
  end
  if id == "project" then
    return snapshot.project
  end
  if id == "git" then
    return snapshot.git
  end
  if id == "permissions" then
    return snapshot.permissions
  end
  if id == "approval" then
    return snapshot.approval
  end
  if id == "thread_id" then
    local value = trim(snapshot.thread_id)
    return value and ("id:" .. value:sub(1, 8)) or nil
  end
  if id == "task_progress" and type(snapshot.task_progress) == "table" then
    local completed = to_number(snapshot.task_progress.completed)
    local total = to_number(snapshot.task_progress.total)
    if completed and total and total > 0 then
      return "Tasks " .. tostring(math.floor(completed)) .. "/" .. tostring(math.floor(total))
    end
    return nil
  end
  if id == "codex_version" then
    local version = trim(snapshot.codex_version)
    return version and ("v" .. version:gsub("^v", "")) or nil
  end
  if id == "icon" then
    return trim(type(options.icon) == "table" and options.icon.text or nil) or ""
  end

  local usage = type(snapshot.usage) == "table" and snapshot.usage or nil
  if id == "context" then
    if not usage then
      return snapshot.waiting
    end
    local percent = to_number(usage.context_remaining_percent)
    if percent ~= nil then
      percent = math.max(0, math.min(100, math.floor(percent + 0.5)))
      if layout == "wide" or layout == "medium" then
        local cells = layout == "wide" and 10 or 8
        return "Ctx " .. M.context_bar(percent, cells) .. " " .. tostring(percent) .. "% left"
      end
      if layout == "narrow" then
        return "Ctx " .. tostring(percent) .. "% left"
      end
      return "Ctx " .. tostring(percent) .. "%"
    end
    local current = M.compact_number(usage.context_tokens)
    return current and ("Ctx " .. current) or snapshot.waiting
  end
  if id == "used_tokens" and usage then
    local counts = pricing.usage_counts(usage)
    if counts.input == nil and counts.output == nil then return nil end
    return "↑" .. (M.compact_number(counts.input) or "—") .. " ↓" .. (M.compact_number(counts.output) or "—")
  end
  if id == "cache_rate" and usage then
    local rate = pricing.cache_rate(usage)
    return rate and ("Cache " .. compact_trim(string.format("%.1f", rate)) .. "%") or "Cache —"
  end
  if id == "cost" and usage then
    return pricing.cost_text(pricing.estimate(snapshot.model, usage, options.pricing))
  end
  if id == "context_used" and usage then
    local remaining = to_number(usage.context_remaining_percent)
    if remaining ~= nil then
      return "Ctx " .. tostring(math.max(0, math.min(100, 100 - math.floor(remaining + 0.5)))) .. "% used"
    end
  end
  if id == "context_window" and usage then
    local value = M.compact_number(usage.context_window)
    return value and (value .. " window") or nil
  end
  if id == "input_tokens" and usage then
    local value = M.compact_number(pricing.usage_counts(usage).input)
    return value and ("↑" .. value) or nil
  end
  if id == "cached_tokens" and usage then
    local value = M.compact_number(usage.cached)
    return value and value ~= "0" and (value .. " cached") or nil
  end
  if id == "output_tokens" and usage then
    local value = M.compact_number(usage.output)
    return value and ("↓" .. value) or nil
  end
  if id == "reasoning_tokens" and usage then
    local value = M.compact_number(usage.reasoning)
    return value and value ~= "0" and (value .. " reasoning") or nil
  end
  return nil
end

local function remove_kind(segments, kind)
  local result = {}
  for _, segment in ipairs(segments) do
    if segment.kind ~= kind then
      table.insert(result, segment)
    end
  end
  return result
end

local function fit_segments(segments, columns, powerline)
  local result = segments
  for _, kind in ipairs(DROP_ORDER) do
    if plan_width(result, powerline) <= columns then
      break
    end
    result = remove_kind(result, kind)
  end
  return result
end

local function with_version(segments, options)
  local theme = type(options.theme) == "table" and options.theme or {}
  table.insert(segments, { kind = "version", text = version.text,
    bg = theme.bg or "#11151a", fg = theme.dim or theme.fg or "#82909f" })
  return segments
end

function M.build_render_plan(options, snapshot, columns)
  options = type(options) == "table" and options or {}
  snapshot = type(snapshot) == "table" and snapshot or {}
  local cols = math.max(1, math.floor(to_number(columns) or 120))
  local layout = M.render_layout(cols)
  local render = type(options.render) == "table" and options.render or {}
  local disabled = list_set(render.disabled_segments)
  local layout_hidden = {}
  if layout == "tiny" then
    layout_hidden = list_set({
      "reasoning", "provider", "personality", "service_tier", "cwd", "project", "git", "permissions",
      "approval", "context_used", "context_window", "used_tokens", "cache_rate", "cost", "input_tokens", "cached_tokens",
      "output_tokens", "reasoning_tokens", "thread_id", "task_progress", "codex_version",
    })
  elseif layout == "narrow" then
    layout_hidden = list_set({
      "provider", "personality", "service_tier", "project", "permissions", "approval", "context_used",
      "context_window", "input_tokens", "cached_tokens", "output_tokens", "reasoning_tokens", "thread_id",
      "task_progress", "codex_version", "cache_rate", "cost",
    })
  end

  local segments = {}
  for _, id in ipairs(ordered_ids(options)) do
    if not disabled[id] and not layout_hidden[id] then
      local text = segment_text(id, options, snapshot, layout)
      if text and tostring(text) ~= "" then
        local bg, fg = theme_for(options, id)
        table.insert(segments, { kind = id, text = tostring(text), bg = bg, fg = fg })
      end
    end
  end

  local powerline = render.powerline ~= false
  local rows = math.max(1, math.min(2, math.floor(to_number(options.bottom_pane and options.bottom_pane.rows) or 1)))
  if rows == 1 then
    return {
      layout = layout,
      columns = cols,
      lines = { fit_segments(with_version(segments, options), cols, powerline) },
    }
  end

  local metadata = {}
  local usage = {}
  for _, segment in ipairs(segments) do
    if list_set({
      "context", "context_used", "context_window", "used_tokens", "cache_rate", "cost", "input_tokens", "cached_tokens",
      "output_tokens", "reasoning_tokens",
    })[segment.kind] then
      table.insert(usage, segment)
    else
      table.insert(metadata, segment)
    end
  end
  metadata = fit_segments(with_version(metadata, options), cols, powerline)
  usage = fit_segments(usage, cols, powerline)
  return {
    layout = layout,
    columns = cols,
    lines = { metadata, usage },
  }
end

M.BASELINE_TOKENS = BASELINE_TOKENS
M.DEFAULT_SEGMENT_ORDER = DEFAULT_SEGMENT_ORDER
M.LEGACY_SEGMENT_ORDER = LEGACY_SEGMENT_ORDER

return M
