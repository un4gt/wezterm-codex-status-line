local wezterm = require("wezterm")
local core = require("codex_statusline_core")

local M = {}

-- Bump this when you want to confirm which copy of the file is loaded.
local MODULE_ID = "wezterm-codex-statusline/2026-07-20"

local FORMAT_RESET_ITEM = nil

local function format_reset_item()
  if FORMAT_RESET_ITEM == false then
    return nil
  end
  if FORMAT_RESET_ITEM ~= nil then
    return FORMAT_RESET_ITEM
  end

  local candidates = {
    -- Prefer the string variant; it is documented and stable.
    -- (Some builds reject `{ ResetAttributes = true }` as an invalid FormatItem.)
    "ResetAttributes",
    { Attribute = { Reset = true } },
  }

  for _, candidate in ipairs(candidates) do
    local ok = pcall(wezterm.format, { candidate })
    if ok then
      FORMAT_RESET_ITEM = candidate
      return candidate
    end
  end

  FORMAT_RESET_ITEM = false
  return nil
end

local CONFIG_CACHE = {
  at = 0,
  loaded = false,
  values = nil,
}

local SESSION_INDEX_CACHE = {
  at = 0,
  last_full_scan_at = 0,
  root = nil,
  entries = nil,
  by_path = nil,
}

local GIT_BRANCH_CACHE = {}

local GLOBAL_KEY = "codex_statusline_state"
local STATE_SCHEMA = 4
local existing_state = wezterm.GLOBAL[GLOBAL_KEY]
if type(existing_state) ~= "table" then
  existing_state = { tabs = {}, panes = {} }
elseif existing_state.schema ~= STATE_SCHEMA then
  existing_state.tabs = type(existing_state.tabs) == "table" and existing_state.tabs or {}
  existing_state.panes = {}
end
existing_state.schema = STATE_SCHEMA
wezterm.GLOBAL[GLOBAL_KEY] = existing_state

local function id_key(id)
  if id == nil then
    return nil
  end
  return tostring(id)
end

local function module_source()
  if type(debug) ~= "table" or type(debug.getinfo) ~= "function" then
    return nil
  end
  local ok, info = pcall(debug.getinfo, 1, "S")
  if not ok or type(info) ~= "table" then
    return nil
  end
  local src = info.source
  if type(src) ~= "string" then
    return nil
  end
  if src:sub(1, 1) == "@" then
    src = src:sub(2)
  end
  return src
end

local function resolved_module_path()
  if type(package) ~= "table" or type(package.searchpath) ~= "function" or type(package.path) ~= "string" then
    return nil
  end
  local ok, path = pcall(package.searchpath, "codex_statusline", package.path)
  if ok and type(path) == "string" then
    return path
  end
  return nil
end

local function window_id_key(window)
  if not window then
    return nil
  end
  if window.window_id then
    local ok, val = pcall(window.window_id, window)
    if ok and val ~= nil then
      return tostring(val)
    end
  end
  if window.mux_window then
    local mw = window:mux_window()
    if mw and mw.window_id then
      local ok, val = pcall(mw.window_id, mw)
      if ok and val ~= nil then
        return tostring(val)
      end
    end
  end
  return nil
end

local function tab_state_key(window, tab_id)
  local wid = window_id_key(window)
  if wid then
    return wid .. ":" .. tostring(tab_id)
  end
  return tostring(tab_id)
end

local function trim(value)
  if value == nil then
    return nil
  end
  local str = tostring(value)
  str = str:gsub("^%s+", ""):gsub("%s+$", "")
  if str == "" then
    return nil
  end
  return str
end

local function first_user_var(user_vars, names)
  for _, name in ipairs(names) do
    local value = trim(user_vars[name])
    if value then
      return value
    end
  end
  return nil
end

local function parse_boolish(value)
  local v = trim(value)
  if not v then
    return nil
  end
  v = v:lower()
  if v == "1" or v == "true" or v == "yes" or v == "on" then
    return true
  end
  if v == "0" or v == "false" or v == "no" or v == "off" then
    return false
  end
  return true
end

local function shallow_merge(defaults, overrides)
  local out = {}
  for k, v in pairs(defaults) do
    out[k] = v
  end
  if overrides then
    for k, v in pairs(overrides) do
      if type(v) == "table" and type(out[k]) == "table" then
        out[k] = shallow_merge(out[k], v)
      else
        out[k] = v
      end
    end
  end
  return out
end

local function is_windows()
  return package.config:sub(1, 1) == "\\"
end

local function normalize_path(path)
  return core.normalize_path(path, is_windows())
end

local function path_join(parts)
  local sep = package.config:sub(1, 1)
  local cleaned = {}
  for _, part in ipairs(parts) do
    local p = trim(part)
    if p then
      table.insert(cleaned, p)
    end
  end
  return table.concat(cleaned, sep)
end

local function safe_json_parse(line)
  if not line then
    return nil
  end
  local ok, value = pcall(wezterm.json_parse, line)
  if not ok then
    return nil
  end
  return value
end

local function normalize_session_meta_payload(payload)
  if type(payload) ~= "table" then
    return nil
  end

  if type(payload.meta) == "table" then
    local meta = payload.meta
    if payload.git ~= nil and meta.git == nil then
      meta.git = payload.git
    end
    return meta
  end

  return payload
end

local function pane_cwd_file_path(pane)
  if not pane or not pane.get_current_working_dir then
    return nil
  end

  local ok, url = pcall(pane.get_current_working_dir, pane)
  if not ok or not url then
    return nil
  end

  if type(url) == "string" then
    local parsed = wezterm.url.parse(url)
    if parsed and parsed.file_path then
      return parsed.file_path
    end
    return nil
  end

  local ok_path, file_path = pcall(function()
    return url.file_path
  end)
  if ok_path and file_path then
    return file_path
  end

  local parsed = wezterm.url.parse(tostring(url))
  if parsed and parsed.file_path then
    return parsed.file_path
  end

  return nil
end

local function strip_toml_comment(line)
  local in_single = false
  local in_double = false

  local i = 1
  while i <= #line do
    local ch = line:sub(i, i)

    if ch == "'" and not in_double then
      in_single = not in_single
    elseif ch == '"' and not in_single then
      local backslashes = 0
      local j = i - 1
      while j >= 1 and line:sub(j, j) == "\\" do
        backslashes = backslashes + 1
        j = j - 1
      end
      if backslashes % 2 == 0 then
        in_double = not in_double
      end
    elseif ch == "#" and not in_single and not in_double then
      return line:sub(1, i - 1)
    end

    i = i + 1
  end

  return line
end

local function parse_toml_scalar(value)
  local v = trim(value)
  if not v then
    return nil
  end

  if v:sub(1, 1) == '"' and v:sub(-1) == '"' and #v >= 2 then
    local inner = v:sub(2, -2)
    inner = inner:gsub("\\\\", "\\"):gsub('\\"', '"')
    return inner
  end

  if v:sub(1, 1) == "'" and v:sub(-1) == "'" and #v >= 2 then
    return v:sub(2, -2)
  end

  return v
end

local function read_file(path)
  local fh = io.open(path, "r")
  if not fh then
    return nil
  end
  local ok, content = pcall(fh.read, fh, "*a")
  fh:close()
  if not ok then
    return nil
  end
  return content
end

local function default_codex_config_paths()
  local home = wezterm.home_dir or os.getenv("USERPROFILE") or os.getenv("HOME")
  if not home then
    return nil
  end
  local codex_dir = path_join({ home, ".codex" })
  return {
    path_join({ codex_dir, "config.toml" }),
  }
end

local function default_codex_home()
  local explicit = trim(os.getenv("CODEX_HOME"))
  if explicit then
    return explicit
  end
  local home = wezterm.home_dir or os.getenv("USERPROFILE") or os.getenv("HOME")
  if not home then
    return nil
  end
  return path_join({ home, ".codex" })
end

local function codex_home_for_opts(opts)
  return trim(opts and opts.codex_home) or default_codex_home()
end

local function bridge_root_for_opts(opts)
  local configured = opts and opts.sessions and trim(opts.sessions.bridge_dir) or nil
  if configured then
    return configured
  end
  local codex_home = codex_home_for_opts(opts)
  if not codex_home then
    return nil
  end
  return path_join({ codex_home, "wezterm-statusline" })
end

local function bridge_manifest_present(opts)
  local root = bridge_root_for_opts(opts)
  if not root then
    return false
  end
  local fh = io.open(path_join({ root, "bridge.json" }), "r")
  if not fh then
    return false
  end
  fh:close()
  return true
end

local function bridge_mapping_for_pane(opts, pane_id)
  local root = bridge_root_for_opts(opts)
  if not root then
    return nil, "bridge-root-unavailable"
  end
  local path = path_join({ root, "panes", tostring(pane_id) .. ".json" })
  local content = read_file(path)
  if not content then
    return nil, "mapping-unavailable"
  end
  local value = safe_json_parse(content)
  local mapping, err = core.validate_bridge_mapping(value, pane_id)
  if not mapping then
    return nil, err
  end
  mapping._mapping_path = path
  return mapping
end

local function bridge_required(opts)
  local mode = opts and opts.sessions and trim(opts.sessions.binding_mode) or "auto"
  mode = mode:lower()
  if mode == "hook" then
    return true
  end
  if mode == "heuristic" then
    return false
  end
  return bridge_manifest_present(opts)
end

local function path_is_within(path, root)
  local child = normalize_path(path)
  local parent = normalize_path(root)
  if not child or not parent then
    return false
  end
  if child == parent then
    return true
  end
  local sep = is_windows() and "\\" or "/"
  return child:sub(1, #parent + 1) == parent .. sep
end

local function load_codex_config(opts)
  if not opts.codex_config.enabled then
    return nil
  end

  local now = os.time()
  if CONFIG_CACHE.loaded and (now - CONFIG_CACHE.at) < opts.codex_config.cache_ttl_seconds then
    return CONFIG_CACHE.values
  end

  local paths = {}
  if trim(opts.codex_config.path) then
    table.insert(paths, opts.codex_config.path)
  else
    local defaults = default_codex_config_paths()
    if defaults then
      for _, p in ipairs(defaults) do
        table.insert(paths, p)
      end
    end
  end
  if #paths == 0 then
    CONFIG_CACHE.values = nil
    CONFIG_CACHE.at = now
    CONFIG_CACHE.loaded = true
    return nil
  end

  local text = nil
  for _, p in ipairs(paths) do
    text = read_file(p)
    if text then
      break
    end
  end
  if not text then
    CONFIG_CACHE.values = nil
    CONFIG_CACHE.at = now
    CONFIG_CACHE.loaded = true
    return nil
  end

  local values = {}
  for line in text:gmatch("[^\r\n]+") do
    local raw = trim(line)
    if raw and raw:sub(1, 1) ~= "#" then
      if raw:sub(1, 1) == "[" then
        break
      end
      local eq = raw:find("=", 1, true)
      if eq then
        local key = trim(raw:sub(1, eq - 1))
        local rhs = strip_toml_comment(raw:sub(eq + 1))
        local val = parse_toml_scalar(rhs)
        if key and val then
          values[key] = val
        end
      end
    end
  end

  CONFIG_CACHE.values = {
    model = trim(values.model),
    thinking = trim(values.model_reasoning_effort or values.reasoning_effort),
    provider = trim(values.model_provider or values.provider),
  }
  CONFIG_CACHE.at = now
  CONFIG_CACHE.loaded = true

  return CONFIG_CACHE.values
end

local function list_rollout_files(root, today_only)
  local sessions_root = trim(root)
  if not sessions_root then
    return {}
  end

  local function read_dir(path)
    local ok, items = pcall(wezterm.read_dir, path)
    if not ok or not items then
      return {}
    end
    return items
  end

  local function join_if_needed(parent, child)
    if not child then
      return nil
    end
    if child:find("[/\\\\]") then
      return child
    end
    return path_join({ parent, child })
  end

  local function collect_from_day(day_path)
    local out = {}
    for _, entry in ipairs(read_dir(day_path)) do
      local p = join_if_needed(day_path, entry)
      if p and p:lower():match("rollout.*%.jsonl$") then
        table.insert(out, p)
      end
    end
    return out
  end

  local function candidates_for_today()
    local now_local = os.date("*t")
    local now_utc = os.date("!*t")

    local function to_candidates(t)
      local y4 = string.format("%04d", t.year or 0)
      local y2 = y4:sub(-2)
      local m2 = string.format("%02d", t.month or 0)
      local d2 = string.format("%02d", t.day or 0)
      local m1 = tostring(tonumber(m2) or m2)
      local d1 = tostring(tonumber(d2) or d2)
      return {
        path_join({ sessions_root, y4, m2, d2 }),
        path_join({ sessions_root, y2, m2, d2 }),
        path_join({ sessions_root, y4, m1, d1 }),
        path_join({ sessions_root, y2, m1, d1 }),
      }
    end

    local out = {}
    for _, p in ipairs(to_candidates(now_local)) do
      table.insert(out, p)
    end
    for _, p in ipairs(to_candidates(now_utc)) do
      table.insert(out, p)
    end

    local uniq = {}
    local dedup = {}
    for _, p in ipairs(out) do
      local k = normalize_path(p) or p
      if k and not uniq[k] then
        uniq[k] = true
        table.insert(dedup, p)
      end
    end
    return dedup
  end

  if today_only then
    local recent = {}
    local seen = {}
    for _, day_path in ipairs(candidates_for_today()) do
      for _, file in ipairs(collect_from_day(day_path)) do
        local key = normalize_path(file) or file
        if not seen[key] then
          seen[key] = true
          table.insert(recent, file)
        end
      end
    end
    table.sort(recent)
    return recent
  end

  local out = {}
  for _, year_dir in ipairs(read_dir(sessions_root)) do
    local year_path = join_if_needed(sessions_root, year_dir)
    if year_path then
      for _, month_dir in ipairs(read_dir(year_path)) do
        local month_path = join_if_needed(year_path, month_dir)
        if month_path then
          for _, day_dir in ipairs(read_dir(month_path)) do
            local day_path = join_if_needed(month_path, day_dir)
            if day_path then
              local files = collect_from_day(day_path)
              for _, f in ipairs(files) do
                table.insert(out, f)
              end
            end
          end
        end
      end
    end
  end

  table.sort(out)
  return out
end

local function read_session_meta(path, max_lines)
  local fh = io.open(path, "r")
  if not fh then
    return nil
  end

  local limit = max_lines or 40
  local meta = nil
  for _ = 1, limit do
    local line = fh:read("*l")
    if not line then
      break
    end
    local obj = safe_json_parse(line)
    if obj and obj.type == "session_meta" and type(obj.payload) == "table" then
      meta = normalize_session_meta_payload(obj.payload)
      break
    end
  end

  fh:close()
  return meta
end

local function read_rollout_activity_timestamp(path, seek_bytes)
  local fh = io.open(path, "r")
  if not fh then
    return nil
  end

  local file_size = fh:seek("end") or 0
  local start = math.max(0, file_size - (seek_bytes or 65536))
  fh:seek("set", start)
  if start > 0 then
    fh:read("*l")
  end

  local latest = nil
  for line in fh:lines() do
    local obj = safe_json_parse(line)
    local timestamp = core.event_timestamp(obj)
    if timestamp and (not latest or timestamp > latest) then
      latest = timestamp
    end
  end
  fh:close()
  return latest
end

local function build_session_index(opts, sessions_root)
  local now = os.time()
  if SESSION_INDEX_CACHE.entries and SESSION_INDEX_CACHE.root == sessions_root then
    if (now - SESSION_INDEX_CACHE.at) < opts.sessions.cache_ttl_seconds then
      return SESSION_INDEX_CACHE.entries
    end
  end

  local same_root = SESSION_INDEX_CACHE.root == sessions_root
  local full_scan_ttl = opts.sessions.full_scan_ttl_seconds or 300
  local full_scan = (not same_root)
    or type(SESSION_INDEX_CACHE.entries) ~= "table"
    or (now - (SESSION_INDEX_CACHE.last_full_scan_at or 0)) >= full_scan_ttl

  local entries = {}
  local by_path = {}
  if not full_scan and type(SESSION_INDEX_CACHE.entries) == "table" then
    for _, meta in ipairs(SESSION_INDEX_CACHE.entries) do
      table.insert(entries, meta)
      by_path[normalize_path(meta._rollout_path) or meta._rollout_path] = meta
    end
  end

  for _, path in ipairs(list_rollout_files(sessions_root, not full_scan)) do
    local key = normalize_path(path) or path
    if not by_path[key] then
      local meta = read_session_meta(path, opts.sessions.max_meta_lines)
      if meta then
        meta._rollout_path = path
        meta._cwd_norm = normalize_path(meta.cwd)
        table.insert(entries, meta)
        by_path[key] = meta
      end
    end
  end

  table.sort(entries, function(a, b)
    local at = trim(a.timestamp) or ""
    local bt = trim(b.timestamp) or ""
    if at ~= bt then
      return at > bt
    end
    return tostring(a._rollout_path) > tostring(b._rollout_path)
  end)

  if opts.debug then
    local head = entries[1]
    local sig = table.concat({
      tostring(#entries),
      tostring(head and head.timestamp),
      tostring(head and head.cwd),
    }, "|")
    if sig ~= SESSION_INDEX_CACHE._last_debug_sig then
      SESSION_INDEX_CACHE._last_debug_sig = sig
      wezterm.log_info(
        "codex_statusline: session index"
          .. " root="
          .. tostring(sessions_root)
          .. " count="
          .. tostring(#entries)
          .. " latest_ts="
          .. tostring(head and head.timestamp)
          .. " latest_cwd="
          .. tostring(head and head.cwd)
      )
    end
  end

  SESSION_INDEX_CACHE.entries = entries
  SESSION_INDEX_CACHE.by_path = by_path
  SESSION_INDEX_CACHE.at = now
  SESSION_INDEX_CACHE.root = sessions_root
  if full_scan then
    SESSION_INDEX_CACHE.last_full_scan_at = now
  end

  return entries
end

local function detect_bridge_rollout(opts, pane, pane_state)
  local pane_id = pane and pane.pane_id and pane:pane_id() or nil
  if pane_id == nil then
    return nil, "pane-id-unavailable"
  end

  local mapping, mapping_err = bridge_mapping_for_pane(opts, pane_id)
  if not mapping then
    return nil, mapping_err
  end
  if pane_state and pane_state.retired_bridge_generation == mapping.generation then
    return nil, "mapping-generation-retired", mapping
  end

  local mapping_cwd = normalize_path(mapping.cwd)
  local pane_cwd = pane_state and (pane_state.codex_cwd_norm or pane_state.pane_cwd_norm) or nil
  if mapping_cwd and pane_cwd and mapping_cwd ~= pane_cwd then
    return nil, "mapping-cwd-mismatch", mapping
  end

  local codex_home = codex_home_for_opts(opts)
  if mapping.rollout_path then
    if not codex_home or not path_is_within(mapping.rollout_path, codex_home) then
      return nil, "mapping-path-outside-codex-home", mapping
    end
    local meta = read_session_meta(mapping.rollout_path, opts.sessions.max_meta_lines)
    local meta_id = meta and trim(meta.id or meta.session_id) or nil
    if not meta_id or meta_id:lower() ~= mapping.thread_id then
      return nil, "mapping-thread-mismatch", mapping
    end
    return mapping.rollout_path, "bridge", mapping, meta
  end

  if not codex_home then
    return nil, "codex-home-unavailable", mapping
  end
  local sessions_root = path_join({ codex_home, "sessions" })
  for _, meta in ipairs(build_session_index(opts, sessions_root)) do
    local meta_id = trim(meta.id or meta.session_id)
    if meta_id and meta_id:lower() == mapping.thread_id then
      return meta._rollout_path, "bridge", mapping, meta
    end
  end
  return nil, "mapping-rollout-unavailable", mapping
end

local function detect_rollout_for_pane(opts, pane, pane_state, force)
  local binding_mode = trim(opts.sessions.binding_mode) or "auto"
  if binding_mode:lower() ~= "heuristic" then
    local bridge_path, bridge_source, mapping, meta = detect_bridge_rollout(opts, pane, pane_state)
    if bridge_path then
      return bridge_path, bridge_source, mapping, meta
    end
    if pane_state then
      pane_state.bridge_wait_reason = bridge_source
    end
    if bridge_required(opts) then
      return nil, "bridge-waiting", mapping
    end
  end

  if (not force) and pane_state and trim(pane_state.rollout_path) then
    return pane_state.rollout_path, pane_state.rollout_source
  end

  local codex_home = codex_home_for_opts(opts)
  if not codex_home then
    return nil
  end
  local sessions_root = path_join({ codex_home, "sessions" })

  local entries = build_session_index(opts, sessions_root)
  if #entries == 0 then
    return nil
  end

  local pane_cwd = nil
  if pane_state and trim(pane_state.codex_cwd_norm) then
    pane_cwd = pane_state.codex_cwd_norm
  else
    pane_cwd = normalize_path(pane_cwd_file_path(pane))
  end

  if pane_cwd then
    local matches = {}
    for _, meta in ipairs(entries) do
      if meta._cwd_norm and meta._cwd_norm == pane_cwd then
        meta._activity_timestamp = read_rollout_activity_timestamp(
          meta._rollout_path,
          opts.sessions.activity_seek_bytes
        ) or trim(meta.timestamp) or ""
        table.insert(matches, meta)
      end
    end

    if #matches > 0 then
      local selected = core.select_recent_rollout(matches)
      return selected and selected._rollout_path or nil, "cwd"
    end

    if opts.debug and pane_state then
      local now = os.time()
      local last = pane_state._last_rollout_miss_log_at or 0
      if (now - last) >= 3 then
        pane_state._last_rollout_miss_log_at = now
        local examples = {}
        for i = 1, math.min(3, #entries) do
          local e = entries[i]
          table.insert(examples, tostring(e and e.cwd))
        end
        wezterm.log_info(
          "codex_statusline: no rollout match for pane cwd"
            .. " pane_cwd="
            .. tostring(pane_cwd)
            .. " sessions="
            .. tostring(#entries)
            .. " latest_cwds=["
            .. table.concat(examples, ", ")
            .. "]"
        )
      end
    end

    -- If we can determine the pane cwd, do not fall back to "latest" since that
    -- can mis-associate sessions when multiple Codex tabs are open.
    return nil
  end

  if opts.sessions.allow_fallback_latest then
    return entries[1]._rollout_path, "fallback"
  end

  return nil
end

local function to_number(value)
  if value == nil then
    return nil
  end
  if type(value) == "number" then
    return value
  end
  if type(value) == "string" then
    local stripped = value:gsub(",", "")
    return tonumber(stripped)
  end
  return nil
end

local function extract_token_usage_info(obj)
  return core.extract_token_usage_info(obj)
end

local function update_flat_usage(pane_state)
  if type(pane_state) ~= "table" then
    return
  end

  pane_state.usage = core.build_usage(
    pane_state.token_usage_total,
    pane_state.token_usage_last,
    pane_state.model_context_window
  )
end

local function clear_rollout_data(pane_state)
  if not pane_state then
    return
  end
  pane_state.rollout_path = nil
  pane_state.rollout_source = nil
  pane_state.bridge_mapping = nil
  pane_state.session_meta = nil
  pane_state.turn_context = nil
  pane_state._logged_session_id = nil
  pane_state.token_usage_total = nil
  pane_state.token_usage_last = nil
  pane_state.model_context_window = nil
  pane_state.usage = nil
  pane_state.offset = 0
  pane_state.last_read_at = nil
  pane_state.open_fail_first_at = nil
  pane_state.open_fail_count = 0
end

local function clear_parsed_rollout_data(opts, pane_state)
  pane_state.session_meta = pane_state.rollout_path
      and read_session_meta(pane_state.rollout_path, opts.sessions.max_meta_lines)
    or nil
  pane_state.turn_context = nil
  pane_state._logged_session_id = nil
  pane_state.token_usage_total = nil
  pane_state.token_usage_last = nil
  pane_state.model_context_window = to_number(pane_state.session_meta and pane_state.session_meta.context_window)
  pane_state.usage = nil
  pane_state.offset = 0
end

local function retire_bridge_generation(opts, pane, pane_state)
  if not pane_state then
    return
  end
  local mapping = pane_state.bridge_mapping
  if not mapping and pane and pane.pane_id then
    mapping = bridge_mapping_for_pane(opts, pane:pane_id())
  end
  if mapping and mapping.generation then
    pane_state.retired_bridge_generation = mapping.generation
  end
end

local function assign_rollout(opts, pane_state, path, source, mapping, meta)
  local changed = pane_state.rollout_path ~= path or pane_state.rollout_source ~= source
  if changed then
    clear_rollout_data(pane_state)
  end
  pane_state.rollout_path = path
  pane_state.rollout_source = source
  pane_state.bridge_mapping = mapping

  local resolved_meta = meta
  if not resolved_meta and (changed or not pane_state.session_meta) and path then
    resolved_meta = read_session_meta(path, opts.sessions.max_meta_lines)
  end
  if resolved_meta then
    pane_state.session_meta = resolved_meta
    pane_state.model_context_window = core.merge_context_window(
      pane_state.model_context_window,
      resolved_meta.context_window
    )
  end
  return changed
end

local function update_rollout_state(opts, pane, pane_state)
  if not pane_state then
    return nil
  end

  local now_for_detection = os.time()
  local refresh_bridge = pane_state.rollout_source == "bridge"
    and (
      not pane_state.last_bridge_check_at
      or (now_for_detection - pane_state.last_bridge_check_at) >= 1
    )
  if not pane_state.rollout_path or pane_state.rollout_source ~= "bridge" or refresh_bridge then
    if refresh_bridge then
      pane_state.last_bridge_check_at = now_for_detection
    end
    local detected_path, source, mapping, meta = detect_rollout_for_pane(opts, pane, pane_state, false)
    if detected_path then
      local changed = assign_rollout(opts, pane_state, detected_path, source, mapping, meta)
      if opts.debug and changed then
        wezterm.log_info(
          "codex_statusline: detected rollout_path=" .. tostring(pane_state.rollout_path) .. " source=" .. tostring(source)
        )
      end
    elseif source == "bridge-waiting" and bridge_required(opts) then
      if pane_state.rollout_path and pane_state.rollout_source ~= "bridge" then
        clear_rollout_data(pane_state)
      end
      if not pane_state.rollout_path then
        pane_state.rollout_source = "bridge-waiting"
      end
      if opts.debug then
        local now = os.time()
        local last = pane_state._last_bridge_wait_log_at or 0
        if (now - last) >= 3 then
          pane_state._last_bridge_wait_log_at = now
          wezterm.log_info(
            "codex_statusline: waiting for SessionStart bridge mapping reason="
              .. tostring(pane_state.bridge_wait_reason)
          )
        end
      end
    end
    if opts.debug and pane_state.rollout_path and pane_state._logged_rollout_path ~= pane_state.rollout_path then
      pane_state._logged_rollout_path = pane_state.rollout_path
      wezterm.log_info(
        "codex_statusline: using rollout_path="
          .. tostring(pane_state.rollout_path)
          .. " source="
          .. tostring(pane_state.rollout_source)
      )
    end
    if pane_state.rollout_path and not pane_state.session_meta then
      pane_state.session_meta = read_session_meta(pane_state.rollout_path, opts.sessions.max_meta_lines)
      if
        opts.debug
        and pane_state.session_meta
        and pane_state.session_meta.id
        and pane_state._logged_session_id ~= tostring(pane_state.session_meta.id)
      then
        pane_state._logged_session_id = tostring(pane_state.session_meta.id)
        wezterm.log_info(
          "codex_statusline: session id="
            .. tostring(pane_state.session_meta.id)
            .. " (resume: codex resume "
            .. tostring(pane_state.session_meta.id)
            .. ")"
        )
      end
    end
  end

  if not pane_state.rollout_path then
    return pane_state
  end

  local now = os.time()
  if pane_state.last_read_at and (now - pane_state.last_read_at) < opts.sessions.tail_ttl_seconds then
    return pane_state
  end
  pane_state.last_read_at = now

  local fh, open_err = io.open(pane_state.rollout_path, "r")
  if not fh then
    local now2 = os.time()
    pane_state.open_fail_first_at = pane_state.open_fail_first_at or now2
    pane_state.open_fail_count = (pane_state.open_fail_count or 0) + 1
    if opts.debug then
      local last = pane_state._last_open_fail_log_at or 0
      if (now2 - last) >= 3 then
        pane_state._last_open_fail_log_at = now2
        wezterm.log_error(
          "codex_statusline: failed to open rollout jsonl"
            .. " path="
            .. tostring(pane_state.rollout_path)
            .. " count="
            .. tostring(pane_state.open_fail_count)
            .. " err="
            .. tostring(open_err)
        )
      end
    end

    local clear_after = opts.sessions.open_fail_clear_seconds or 30
    if clear_after > 0 and (now2 - (pane_state.open_fail_first_at or now2)) >= clear_after then
      if opts.debug then
        wezterm.log_info(
          "codex_statusline: giving up on rollout path; will re-detect"
            .. " path="
            .. tostring(pane_state.rollout_path)
            .. " seconds="
            .. tostring(clear_after)
        )
      end
      clear_rollout_data(pane_state)
    end
    return pane_state
  end
  pane_state.open_fail_first_at = nil
  pane_state.open_fail_count = 0

  local file_size = fh:seek("end") or 0
  if pane_state.offset and pane_state.offset > file_size then
    clear_parsed_rollout_data(opts, pane_state)
  end
  local offset, discard_partial_line = core.tail_start(
    file_size,
    pane_state.offset,
    opts.sessions.initial_seek_bytes
  )
  fh:seek("set", offset)
  if discard_partial_line then
    -- Drop the partial line if we started in the middle of the file.
    fh:read("*l")
  end

  local max_lines = opts.sessions.max_tail_lines
  local count = 0
  while count < max_lines do
    local line = fh:read("*l")
    if not line then
      break
    end
    count = count + 1

    local obj = safe_json_parse(line)
    if obj then
      if (not pane_state.session_meta) and obj.type == "session_meta" and type(obj.payload) == "table" then
        pane_state.session_meta = normalize_session_meta_payload(obj.payload)
        pane_state.model_context_window = pane_state.model_context_window
          or to_number(pane_state.session_meta and pane_state.session_meta.context_window)
      end

      local turn_context = core.extract_turn_context(obj)
      if turn_context then
        pane_state.turn_context = turn_context
      end

      local usage_info = extract_token_usage_info(obj)
      if usage_info then
        if usage_info.total then
          pane_state.token_usage_total = usage_info.total
        end
        if usage_info.last then
          pane_state.token_usage_last = usage_info.last
        end
        pane_state.model_context_window = core.merge_context_window(
          pane_state.model_context_window,
          usage_info.model_context_window
        )
        if opts.debug and usage_info.total then
          wezterm.log_info(
            "codex_statusline: token_count updated total_tokens=" .. tostring(usage_info.total.total_tokens)
          )
        end
      end
    end
  end

  pane_state.offset = fh:seek()
  fh:close()

  update_flat_usage(pane_state)
  if opts.debug and pane_state.usage then
    local u = pane_state.usage
    local sig = table.concat({
      tostring(u.total),
      tostring(u.input),
      tostring(u.cached),
      tostring(u.output),
      tostring(u.reasoning),
      tostring(u.context_tokens),
      tostring(u.context_window),
      tostring(u.context_remaining_percent),
    }, "|")
    if sig ~= pane_state._last_usage_sig then
      pane_state._last_usage_sig = sig
      wezterm.log_info(
        "codex_statusline: usage"
          .. " total="
          .. tostring(u.total)
          .. " input="
          .. tostring(u.input)
          .. " cached="
          .. tostring(u.cached)
          .. " output="
          .. tostring(u.output)
          .. " reasoning="
          .. tostring(u.reasoning)
          .. " context="
          .. tostring(u.context_tokens)
          .. "/"
          .. tostring(u.context_window)
          .. " remaining="
          .. tostring(u.context_remaining_percent)
      )
    end
  end
  return pane_state
end

local DEFAULTS = {
  debug = false,
  label = "CODEX",
  log = {
    enabled = true,
    marker = "CODEX_STATUSLINE_LOADED",
  },
  compat = {
    -- Older WezTerm builds used `update-right-status` instead of `update-status`.
    -- Enable if you don't see `update-status` events firing.
    update_right_status = false,
  },
  codex_config = {
    enabled = true,
    path = nil,
    cache_ttl_seconds = 5,
  },
  title_bridge = {
    enabled = true,
    app_name = "codex",
  },
  git = {
    enabled = true,
    cache_ttl_seconds = 5,
  },
  codex_home = nil, -- defaults to $CODEX_HOME or ~/.codex
  user_vars = {
    model = { "codex_model", "CODEX_MODEL" },
    thinking = { "codex_thinking", "CODEX_THINKING", "codex_reasoning", "CODEX_REASONING" },
    provider = { "codex_provider", "CODEX_PROVIDER", "codex_model_provider", "CODEX_MODEL_PROVIDER" },
    active = { "codex_active", "CODEX_ACTIVE" },
  },
  process_match = {
    enabled = true,
    names = { "codex", "codex.exe" },
    argv_markers = { "/@openai/codex/bin/codex.js" },
    terminal_names = {
      "wezterm",
      "wezterm.exe",
      "wezterm-gui",
      "wezterm-gui.exe",
      "wezterm-mux-server-impl",
      "wezterm-mux-server-impl.exe",
    },
    -- Keep the status visible briefly only when process inspection is unavailable.
    grace_seconds = 5,
    tree_cache_ttl_seconds = 1,
  },
  sessions = {
    enabled = true,
    binding_mode = "auto", -- "auto" | "hook" | "heuristic"
    bridge_dir = nil, -- defaults to $CODEX_HOME/wezterm-statusline
    allow_fallback_latest = false,
    cache_ttl_seconds = 5,
    full_scan_ttl_seconds = 300,
    tail_ttl_seconds = 1,
    open_fail_clear_seconds = 30,
    initial_seek_bytes = 131072,
    activity_seek_bytes = 65536,
    max_meta_lines = 40,
    max_tail_lines = 200,
  },
  bottom_pane = {
    enabled = true,
    rows = 1,
    close_grace_seconds = 2,
    prevent_focus = true,
  },
  render = {
    powerline = true,
    plain_fallback = true,
  },
  theme = {
    bg = "#1a1b26",
    fg = "#c0caf5",
    dim = "#565f89",
    segments = {
      label = { bg = "#7aa2f7", fg = "#1a1b26" },
      model = { bg = "#9ece6a", fg = "#1a1b26" },
      thinking = { bg = "#e0af68", fg = "#1a1b26" },
      provider = { bg = "#bb9af7", fg = "#1a1b26" },
      cwd = { bg = "#414868", fg = "#c0caf5" },
      git = { bg = "#73daca", fg = "#1a1b26" },
      tokens = { bg = "#24283b", fg = "#c0caf5" },
    },
    glyphs = {
      sep = "",
      branch = "",
      folder = "",
    },
  },
}

local function git_branch_for_cwd(opts, cwd, fallback)
  local fallback_branch = trim(fallback)
  if not opts.git or not opts.git.enabled or not wezterm.run_child_process then
    return fallback_branch
  end

  local normalized_cwd = normalize_path(cwd)
  if not normalized_cwd then
    return fallback_branch
  end

  local ttl = tonumber(opts.git.cache_ttl_seconds) or 5
  ttl = math.max(0, ttl)
  local now = os.time()
  local cached = GIT_BRANCH_CACHE[normalized_cwd]
  if cached and (now - cached.at) < ttl then
    if cached.resolved then
      return cached.branch
    end
    return fallback_branch
  end

  local ok, success, stdout = pcall(wezterm.run_child_process, {
    "git",
    "-C",
    normalized_cwd,
    "branch",
    "--show-current",
  })
  local resolved = ok and success == true
  local branch = resolved and trim(stdout) or nil
  GIT_BRANCH_CACHE[normalized_cwd] = {
    at = now,
    resolved = resolved,
    branch = branch,
  }
  if resolved then
    return branch
  end
  return fallback_branch
end

local function foreground_process_path(pane)
  if not pane or not pane.get_foreground_process_name then
    return nil
  end
  local ok, value = pcall(pane.get_foreground_process_name, pane)
  if not ok then
    return nil
  end
  return trim(value)
end

local function process_basename(process)
  local p = trim(process)
  if not p then
    return nil
  end
  local last = p:match("([^/\\\\]+)$")
  return last or p
end

local function codex_process_tree_result(pane, pane_state, opts)
  if not pane_state or not opts or not opts.process_match or not opts.process_match.enabled then
    return { state = nil, reason = "process-matching-disabled" }
  end

  local ttl = opts.process_match.tree_cache_ttl_seconds
  if type(ttl) ~= "number" or ttl <= 0 then
    ttl = 1
  end

  local now = os.time()
  if pane_state._tree_checked_at and (now - pane_state._tree_checked_at) < ttl then
    return pane_state._tree_result or { state = pane_state._tree_state }
  end
  pane_state._tree_checked_at = now
  pane_state._tree_state = nil
  pane_state._tree_result = nil

  if not pane or not pane.get_foreground_process_info then
    return { state = nil, reason = "foreground-api-unavailable" }
  end

  local ok_info, info = pcall(pane.get_foreground_process_info, pane)
  if not ok_info or type(info) ~= "table" then
    return { state = nil, reason = "foreground-unavailable" }
  end

  local get_parent = nil
  if wezterm.procinfo and wezterm.procinfo.get_info_for_pid then
    get_parent = function(pid)
      local ok_parent, parent = pcall(wezterm.procinfo.get_info_for_pid, pid)
      if ok_parent then
        return parent
      end
      return nil
    end
  end

  local result = core.inspect_codex_process(info, get_parent, opts.process_match)
  pane_state._tree_result = result
  pane_state._tree_state = result.state
  return result
end

local function codex_terminal_title_signal(opts, pane)
  if not opts.title_bridge or not opts.title_bridge.enabled or not pane or not pane.get_title then
    return nil, false, nil
  end

  local ok, title = pcall(pane.get_title, pane)
  if not ok then
    return nil, false, nil
  end
  return core.parse_codex_terminal_title(title, opts.title_bridge.app_name), true, title
end

local function build_codex_cells(opts, pane, pane_state)
  local user_vars = {}
  if pane.get_user_vars then
    user_vars = pane:get_user_vars() or {}
  end

  local active_var = parse_boolish(first_user_var(user_vars, opts.user_vars.active))

  local fg_process = foreground_process_path(pane)
  local fg_base = process_basename(fg_process)
  local tree_result = codex_process_tree_result(pane, pane_state, opts)
  local tree_state = tree_result and tree_result.state or nil
  local process_is_codex = tree_state == true and tree_result.pid == tree_result.foreground_pid
  local title_signal, title_read_ok, terminal_title = codex_terminal_title_signal(opts, pane)

  local model = first_user_var(user_vars, opts.user_vars.model)
  local thinking = first_user_var(user_vars, opts.user_vars.thinking)
  local provider = first_user_var(user_vars, opts.user_vars.provider)

  local now = os.time()
  if pane_state then
    pane_state.fg_process = fg_base or fg_process
  end

  if active_var == false then
    if pane_state then
      pane_state.last_codex_seen_at = nil
      pane_state.codex_confirmed = false
      pane_state.shell_since = nil
      pane_state.codex_cwd_norm = nil
      pane_state.title_bridge = nil
    end
    return { active = false }
  end

  local process_seen = tree_state == true or active_var == true
  if process_seen and pane_state then
    pane_state.last_codex_seen_at = now
  end

  local recently_seen = false
  if pane_state and pane_state.last_codex_seen_at and opts.process_match.grace_seconds then
    recently_seen = (now - pane_state.last_codex_seen_at) <= opts.process_match.grace_seconds
  end

  local active = false
  local allow_recent = (tree_state == nil) and recently_seen
  if tree_state == true or active_var == true or allow_recent then
    active = true
  end

  local title_bridge_source = nil
  if pane_state then
    local title_override = nil
    pane_state.title_bridge, title_override, title_bridge_source = core.update_title_bridge_state(
      pane_state.title_bridge,
      title_signal,
      title_read_ok,
      tree_state
    )
    if title_override ~= nil then
      active = title_override
    end
  elseif title_signal then
    active = true
    title_bridge_source = "terminal-title"
  end

  if pane_state then
    if active then
      if process_seen or title_signal then
        pane_state.last_codex_seen_at = now
      end
      pane_state.codex_confirmed = true
      pane_state.shell_since = nil
    else
      pane_state.codex_confirmed = false
      pane_state.last_codex_seen_at = nil
      pane_state.shell_since = nil
      pane_state.codex_cwd_norm = nil
    end
  end

  if opts.codex_config.enabled and active then
    local cfg = load_codex_config(opts)
    if cfg then
      model = model or cfg.model
      thinking = thinking or cfg.thinking
      provider = provider or cfg.provider
    end
  end

  return {
    active = active,
    model = model,
    thinking = thinking,
    live_reasoning = title_signal and title_signal.reasoning or nil,
    provider = provider,
    process_is_codex = process_is_codex,
    tree_state = tree_state,
    tree_reason = tree_result and tree_result.reason or nil,
    codex_pid = tree_result and tree_result.pid or nil,
    process_kind = tree_result and tree_result.kind or nil,
    foreground_pid = tree_result and tree_result.foreground_pid or nil,
    title_bridge_source = title_bridge_source,
    terminal_title = terminal_title,
  }
end

function M.setup(user_opts)
  local opts = shallow_merge(DEFAULTS, user_opts)

  if opts.log and opts.log.enabled then
    local marker = opts.log.marker or "CODEX_STATUSLINE_LOADED"
    wezterm.log_info(
      "codex_statusline: "
        .. tostring(marker)
        .. " module_id="
        .. tostring(MODULE_ID)
        .. " source="
        .. tostring(module_source())
        .. " searchpath="
        .. tostring(resolved_module_path())
        .. " wezterm="
        .. tostring(wezterm.version)
    )
  end

  local state = wezterm.GLOBAL[GLOBAL_KEY]
  if type(state) ~= "table" then
    state = { schema = STATE_SCHEMA, tabs = {}, panes = {} }
    wezterm.GLOBAL[GLOBAL_KEY] = state
  end
  if type(state.tabs) ~= "table" then
    state.tabs = {}
  end
  if type(state.panes) ~= "table" then
    state.panes = {}
  end

  local function reset_status_render_state(tab_state)
    tab_state.last_render_frame = nil
    tab_state.last_render_layout = nil
    tab_state.last_render_ok = false
    tab_state._warned_inject_output = nil
    tab_state._warned_inject_error = nil
    tab_state._rendered_once = nil
  end

  local function clear_status_pane_reference(tab_state)
    tab_state.status_pane_id = nil
    tab_state.status_rows = nil
    tab_state.status_close_requested = nil
    tab_state.status_close_reason = nil
    reset_status_render_state(tab_state)
  end

  local function pane_dimensions(pane)
    if not pane or not pane.get_dimensions then
      return nil
    end
    local ok, dims = pcall(pane.get_dimensions, pane)
    if not ok or type(dims) ~= "table" then
      return nil
    end
    return dims
  end

  local close_status_pane

  local function ensure_status_pane(window, pane, tab_id, tab_state)
    if not opts.bottom_pane.enabled then
      return nil
    end

    local desired_rows = math.max(1, opts.bottom_pane.rows or 1)

    if tab_state and tab_state.status_pane_id then
      local ok_existing, existing = pcall(wezterm.mux.get_pane, tab_state.status_pane_id)
      if not ok_existing then
        if opts.debug then
          wezterm.log_info(
            "codex_statusline: unable to verify status pane id=" .. tostring(tab_state.status_pane_id)
          )
        end
        return nil
      end

      if not existing then
        clear_status_pane_reference(tab_state)
      else
        if tab_state.status_close_requested then
          close_status_pane(window, tab_id, tab_state, tab_state.status_close_reason)
          return nil
        end

        local dims = pane_dimensions(existing)
        local existing_rows = dims and tonumber(dims.viewport_rows or dims.rows) or nil
        if existing_rows == desired_rows then
          tab_state.status_rows = desired_rows
          return existing
        end

        if opts.debug then
          wezterm.log_info(
            "codex_statusline: recreating status pane for row change"
              .. " pane_id="
              .. tostring(tab_state.status_pane_id)
              .. " rows="
              .. tostring(existing_rows)
              .. "->"
              .. tostring(desired_rows)
          )
        end
        close_status_pane(window, tab_id, tab_state, "recreate")
        return nil
      end
    end

    local args = nil
    if is_windows() then
      args = {
        "powershell",
        "-NoLogo",
        "-NoProfile",
        "-Command",
        "while($true){Start-Sleep -Seconds 3600}",
      }
    else
      args = { "sh", "-lc", "while true; do sleep 3600; done" }
    end

    local ok_split, status_pane_or_err = pcall(pane.split, pane, {
      direction = "Bottom",
      top_level = true,
      size = desired_rows,
      args = args,
    })
    local status_pane = ok_split and status_pane_or_err or nil
    if not status_pane then
      wezterm.log_error("codex_statusline: failed to split bottom pane for status: " .. tostring(status_pane_or_err))
      return nil
    end

    if opts.debug then
      local status_dims = pane_dimensions(status_pane)
      local main_dims = pane_dimensions(pane)
      local status_rows = status_dims and (status_dims.viewport_rows or status_dims.rows) or "?"
      local main_rows = main_dims and (main_dims.viewport_rows or main_dims.rows) or "?"
      local wid = window_id_key(window) or "?"
      local tkey = tab_state_key(window, tab_id)
      wezterm.log_info(
        "codex_statusline: created status pane id="
          .. tostring(status_pane:pane_id())
          .. " w="
          .. tostring(wid)
          .. " tab_id="
          .. tostring(tab_id)
          .. " key="
          .. tostring(tkey)
          .. " size="
          .. tostring(desired_rows)
          .. " rows(status/main)="
          .. tostring(status_rows)
          .. "/"
          .. tostring(main_rows)
      )
    end

    if status_pane.set_title then
      pcall(status_pane.set_title, status_pane, "codex-statusline")
    end

    local tab_key = tab_state_key(window, tab_id)
    state.tabs[tab_key] = state.tabs[tab_key] or {}
    state.tabs[tab_key].status_pane_id = status_pane:pane_id()
    state.tabs[tab_key].status_rows = desired_rows
    state.tabs[tab_key].main_pane_id = pane:pane_id()
    state.tabs[tab_key].status_close_requested = nil
    state.tabs[tab_key].status_close_reason = nil
    reset_status_render_state(state.tabs[tab_key])

    -- Keep focus in the main pane (WezTerm tends to focus the newly split pane).
    if opts.bottom_pane.prevent_focus then
      if pane.activate then
        pcall(pane.activate, pane)
      elseif window and window.perform_action then
        pcall(window.perform_action, window, wezterm.action.ActivatePaneDirection("Up"), status_pane)
      end
    end

    return status_pane
  end

  close_status_pane = function(window, tab_id, tab_state, reason)
    if not tab_state or not tab_state.status_pane_id then
      return true
    end

    local status_pane_id = tab_state.status_pane_id
    local ok_pane, status_pane = pcall(wezterm.mux.get_pane, status_pane_id)
    if not ok_pane then
      return false
    end
    if not status_pane then
      clear_status_pane_reference(tab_state)
      return true
    end

    tab_state.status_close_requested = true
    tab_state.status_close_reason = reason or tab_state.status_close_reason or "inactive"
    if window and window.perform_action then
      if opts.debug then
        wezterm.log_info(
          "codex_statusline: closing status pane id="
            .. tostring(status_pane_id)
            .. " w="
            .. tostring(window_id_key(window) or "?")
            .. " tab_id="
            .. tostring(tab_id)
            .. " reason="
            .. tostring(tab_state.status_close_reason)
        )
      end
      local ok_close, err = pcall(
        window.perform_action,
        window,
        wezterm.action.CloseCurrentPane({ confirm = false }),
        status_pane
      )
      if not ok_close then
        if opts.debug then
          wezterm.log_info("codex_statusline: status pane close failed: " .. tostring(err))
        end
        return false
      end
    else
      return false
    end

    local ok_after, remaining = pcall(wezterm.mux.get_pane, status_pane_id)
    if ok_after and not remaining then
      clear_status_pane_reference(tab_state)
      return true
    end
    return false
  end

  local function format_int(n)
    if n == nil then
      return nil
    end
    local s = tostring(math.floor(n))
    local sign = ""
    if s:sub(1, 1) == "-" then
      sign = "-"
      s = s:sub(2)
    end
    local rev = s:reverse()
    local grouped = rev:gsub("(%d%d%d)", "%1,"):reverse()
    grouped = grouped:gsub("^,", "")
    return sign .. grouped
  end

  local function substitute_home(path)
    local p = trim(path)
    if not p then
      return nil
    end
    local home = wezterm.home_dir or os.getenv("USERPROFILE") or os.getenv("HOME")
    if not home then
      return p
    end
    if is_windows() then
      local p_low = p:lower()
      local home_low = home:lower()
      if p_low:sub(1, #home_low) == home_low then
        return "~" .. p:sub(#home + 1)
      end
      return p
    end
    if p:sub(1, #home) == home then
      return "~" .. p:sub(#home + 1)
    end
    return p
  end

  local function truncate_to_width(text, max_width)
    local s = tostring(text or "")
    if max_width <= 0 then
      return ""
    end
    if wezterm.column_width(s) <= max_width then
      return s
    end
    local ell = "…"
    local ell_w = wezterm.column_width(ell)
    if max_width <= ell_w then
      return ell
    end
    local target = max_width - ell_w
    local out = ""
    local used = 0
    for _, codepoint in utf8.codes(s) do
      local ch = utf8.char(codepoint)
      local w = wezterm.column_width(ch)
      if used + w > target then
        break
      end
      out = out .. ch
      used = used + w
    end
    return out .. ell
  end

  local function shorten_path(path, max_width)
    local p = substitute_home(path) or ""
    if wezterm.column_width(p) <= max_width then
      return p
    end
    local sep = is_windows() and "\\" or "/"
    local parts = {}
    for part in p:gmatch("[^" .. sep .. "]+") do
      table.insert(parts, part)
    end
    local last = parts[#parts] or p
    local prev = parts[#parts - 1]
    local candidate = (prev and ("…" .. sep .. prev .. sep .. last)) or ("…" .. sep .. last)
    if wezterm.column_width(candidate) <= max_width then
      return candidate
    end
    return truncate_to_width(last, max_width)
  end

  local function segments_width(segments, glyphs, powerline)
    local width = 0
    local sep_width = powerline and wezterm.column_width(glyphs.sep or "") or 2
    for idx, seg in ipairs(segments) do
      width = width + wezterm.column_width(seg.text or "") + (powerline and 2 or 0)
      if idx < #segments then
        width = width + sep_width
      end
    end
    return width
  end

  local function build_powerline(segments, glyphs, cols)
    local sep = glyphs.sep or ""
    local items = {}
    local used = 0

    for idx, seg in ipairs(segments) do
      local text = seg.text or ""
      local seg_width = wezterm.column_width(text) + 2
      local next_bg = nil
      if idx < #segments then
        next_bg = segments[idx + 1].bg
      end

      if used + seg_width > cols then
        local remaining = cols - used
        if remaining <= 0 then
          break
        end
        local clipped = truncate_to_width(text, math.max(0, remaining - 2))
        text = clipped
        seg_width = wezterm.column_width(text) + 2
      end

      if seg_width <= 2 then
        break
      end

      table.insert(items, { Background = { Color = seg.bg } })
      table.insert(items, { Foreground = { Color = seg.fg } })
      table.insert(items, { Text = " " .. text .. " " })
      used = used + seg_width

      if next_bg and sep ~= "" and used < cols then
        local sep_w = wezterm.column_width(sep)
        if used + sep_w > cols then
          break
        end
        table.insert(items, { Background = { Color = seg.bg } })
        table.insert(items, { Foreground = { Color = next_bg } })
        table.insert(items, { Text = sep })
        used = used + sep_w
      end
    end

    local reset_item = format_reset_item()
    if reset_item then
      table.insert(items, reset_item)
    end
    return wezterm.format(items)
  end

  local function build_plain_line(parts, cols, theme)
    local text = table.concat(parts, "  ")
    text = truncate_to_width(text, cols)
    local items = {
      { Background = { Color = theme.bg } },
      { Foreground = { Color = theme.fg } },
      { Text = text },
    }
    local reset_item = format_reset_item()
    if reset_item then
      table.insert(items, reset_item)
    end
    return wezterm.format(items)
  end

  local function build_lines(opts, codex_info, pane_state, cols)
    local meta = pane_state and pane_state.session_meta or nil
    local turn_context = pane_state and pane_state.turn_context or nil
    local model = turn_context and trim(turn_context.model) or nil
    model = model or trim(codex_info.model)
    local thinking = trim(codex_info.live_reasoning)
    thinking = thinking or (turn_context and trim(turn_context.effort or turn_context.model_reasoning_effort) or nil)
    thinking = thinking or trim(codex_info.thinking)
    local provider = meta and trim(meta.model_provider) or nil
    provider = provider or trim(codex_info.provider)
    local cwd = meta and trim(meta.cwd) or nil
    cwd = cwd or (pane_state and trim(pane_state.pane_cwd) or nil)
    local metadata_git_branch = nil
    if meta and type(meta.git) == "table" then
      metadata_git_branch = trim(meta.git.branch)
    end
    local git_branch = git_branch_for_cwd(opts, cwd, metadata_git_branch)

    local layout = "wide"
    if cols < 60 then
      layout = "tiny"
    elseif cols < 90 then
      layout = "narrow"
    elseif cols < 120 then
      layout = "medium"
    end

    local function basename(path)
      local p = substitute_home(path) or ""
      local sep = is_windows() and "\\" or "/"
      local last = p:match("[^" .. sep .. "]+$")
      return last or p
    end

    local glyphs = opts.theme.glyphs or {}
    local segments = {}
    table.insert(segments, {
      kind = "label",
      text = opts.label,
      bg = opts.theme.segments.label.bg,
      fg = opts.theme.segments.label.fg,
    })
    if model then
      table.insert(segments, {
        kind = "model",
        text = model,
        bg = opts.theme.segments.model.bg,
        fg = opts.theme.segments.model.fg,
      })
    end
    if thinking then
      table.insert(segments, {
        kind = "thinking",
        text = "r:" .. thinking,
        bg = opts.theme.segments.thinking.bg,
        fg = opts.theme.segments.thinking.fg,
      })
    end
    if provider and layout ~= "tiny" then
      local label = (layout == "wide") and "p:" or ""
      table.insert(segments, {
        kind = "provider",
        text = label .. provider,
        bg = opts.theme.segments.provider.bg,
        fg = opts.theme.segments.provider.fg,
      })
    end
    if cwd and layout ~= "tiny" then
      local max_width = math.max(10, math.floor(cols * 0.35))
      if layout == "medium" then
        max_width = math.max(10, math.floor(cols * 0.28))
      elseif layout == "narrow" then
        max_width = math.max(10, math.floor(cols * 0.22))
      end

      local display = nil
      if layout == "narrow" then
        display = truncate_to_width(basename(cwd), max_width)
      else
        display = shorten_path(cwd, max_width)
      end

      local folder_prefix = ""
      if opts.render.powerline and glyphs.folder and layout ~= "narrow" then
        folder_prefix = glyphs.folder .. " "
      elseif layout ~= "narrow" then
        folder_prefix = "cwd:"
      end
      table.insert(segments, {
        kind = "cwd",
        text = folder_prefix .. display,
        bg = opts.theme.segments.cwd.bg,
        fg = opts.theme.segments.cwd.fg,
      })
    end
    if git_branch and layout ~= "tiny" then
      local branch_prefix = ""
      if opts.render.powerline and glyphs.branch then
        branch_prefix = glyphs.branch .. " "
      else
        branch_prefix = "git:"
      end
      table.insert(segments, {
        kind = "git",
        text = branch_prefix .. git_branch,
        bg = opts.theme.segments.git.bg,
        fg = opts.theme.segments.git.fg,
      })
    end

    local usage = pane_state and pane_state.usage or nil
    local usage_candidates = {}
    local long_usage_text = nil
    if usage then
      local cached_val = usage.cached
      local reasoning_val = usage.reasoning

      local total = format_int(usage.total)
      local input = format_int(usage.input)
      local cached = (cached_val and cached_val > 0) and format_int(cached_val) or nil
      local output = format_int(usage.output)
      local reasoning = (reasoning_val and reasoning_val > 0) and format_int(reasoning_val) or nil
      local context_tokens = format_int(usage.context_tokens)
      local context_window = format_int(usage.context_window)
      local context_remaining = usage.context_remaining_percent

      local function build_usage_text(style, drop_cached, drop_reasoning, compact_context)
        local parts = {}
        if style == "long" then
          table.insert(parts, "Token usage:")
          if total then
            table.insert(parts, "total=" .. total)
          end
          if input then
            local input_part = "input=" .. input
            if cached and (not drop_cached) then
              input_part = input_part .. " (+ " .. cached .. " cached)"
            end
            table.insert(parts, input_part)
          elseif cached and (not drop_cached) then
            table.insert(parts, "cached=" .. cached)
          end
          if output then
            local output_part = "output=" .. output
            if reasoning and (not drop_reasoning) then
              output_part = output_part .. " (reasoning " .. reasoning .. ")"
            end
            table.insert(parts, output_part)
          elseif reasoning and (not drop_reasoning) then
            table.insert(parts, "reasoning=" .. reasoning)
          end
          if context_tokens or context_remaining ~= nil then
            if compact_context and context_remaining ~= nil then
              table.insert(parts, "context=" .. tostring(context_remaining) .. "% left")
            else
              local context_part = "context=" .. tostring(context_tokens or "?")
              if context_window then
                context_part = context_part .. "/" .. context_window
              end
              if context_remaining ~= nil then
                context_part = context_part .. " (" .. tostring(context_remaining) .. "% left)"
              end
              table.insert(parts, context_part)
            end
          end
        else
          table.insert(parts, "Tok:")
          if total then
            table.insert(parts, "t=" .. total)
          end
          if input then
            table.insert(parts, "in=" .. input)
          end
          if cached and not drop_cached then
            table.insert(parts, "+c=" .. cached)
          end
          if output then
            table.insert(parts, "out=" .. output)
          end
          if reasoning and not drop_reasoning then
            table.insert(parts, "r=" .. reasoning)
          end
          if context_tokens or context_remaining ~= nil then
            if compact_context and context_remaining ~= nil then
              table.insert(parts, "ctx=" .. tostring(context_remaining) .. "%")
            else
              local context_part = "ctx=" .. tostring(context_tokens or "?")
              if context_window then
                context_part = context_part .. "/" .. context_window
              end
              if context_remaining ~= nil then
                context_part = context_part .. " left=" .. tostring(context_remaining) .. "%"
              end
              table.insert(parts, context_part)
            end
          end
        end
        return table.concat(parts, " ")
      end

      long_usage_text = build_usage_text("long", false, false, false)
      table.insert(usage_candidates, build_usage_text("short", false, false, false))
      table.insert(usage_candidates, build_usage_text("short", false, false, true))
      table.insert(usage_candidates, build_usage_text("short", false, true, true))
      table.insert(usage_candidates, build_usage_text("short", true, true, true))

      local minimal = {}
      if context_remaining ~= nil then
        table.insert(minimal, "ctx=" .. tostring(context_remaining) .. "%")
      elseif context_tokens then
        table.insert(minimal, "ctx=" .. context_tokens)
      end
      if total then
        table.insert(minimal, "t=" .. total)
      end
      table.insert(usage_candidates, table.concat(minimal, " "))
    else
      local waiting = core.waiting_status(
        pane_state and pane_state.rollout_path or nil,
        pane_state and pane_state.rollout_source or nil,
        pane_state and pane_state.bridge_wait_reason or nil
      )
      long_usage_text = waiting.long
      usage_candidates = { waiting.short, waiting.minimal }
    end

    local function render_segments(items)
      if opts.render.powerline then
        return build_powerline(items, glyphs, cols)
      end
      if opts.render.plain_fallback then
        local parts = {}
        for _, seg in ipairs(items) do
          table.insert(parts, seg.text)
        end
        return build_plain_line(parts, cols, opts.theme)
      end
      return ""
    end

    if math.max(1, opts.bottom_pane.rows or 1) == 1 then
      local drop_sets = {
        {},
        { git = true },
        { git = true, cwd = true },
        { git = true, cwd = true, provider = true },
      }
      local best = nil

      for removed, drop_set in ipairs(drop_sets) do
        local metadata = {}
        for _, seg in ipairs(segments) do
          if not drop_set[seg.kind] then
            table.insert(metadata, seg)
          end
        end
        for candidate_index, text in ipairs(usage_candidates) do
          if text ~= "" then
            local combined = {}
            for _, seg in ipairs(metadata) do
              table.insert(combined, seg)
            end
            table.insert(combined, {
              kind = "tokens",
              text = text,
              bg = opts.theme.segments.tokens.bg,
              fg = usage and opts.theme.segments.tokens.fg or opts.theme.dim,
            })
            if segments_width(combined, glyphs, opts.render.powerline) <= cols then
              if not best or candidate_index < best.candidate_index then
                best = {
                  candidate_index = candidate_index,
                  removed = removed,
                  segments = combined,
                }
              end
              break
            end
          end
        end
      end

      if not best then
        local fallback = { segments[1] }
        table.insert(fallback, {
          kind = "tokens",
          text = usage_candidates[#usage_candidates] or "",
          bg = opts.theme.segments.tokens.bg,
          fg = usage and opts.theme.segments.tokens.fg or opts.theme.dim,
        })
        best = { segments = fallback }
      end
      return render_segments(best.segments), nil
    end

    local line1 = render_segments(segments)
    local text = long_usage_text
    if wezterm.column_width(text) > cols then
      for _, candidate in ipairs(usage_candidates) do
        text = candidate
        if wezterm.column_width(text) <= cols then
          break
        end
      end
    end
    text = truncate_to_width(text, cols)

    local line2 = wezterm.format({
      { Background = { Color = opts.theme.segments.tokens.bg } },
      { Foreground = { Color = usage and opts.theme.segments.tokens.fg or opts.theme.dim } },
      { Text = text },
      format_reset_item() or { Text = "" },
    })
    return line1, line2
  end

  local function repaint_status_pane(window, status_pane, tab_state, line1, line2)
    local dims = pane_dimensions(status_pane)
    local cols = dims and tonumber(dims.cols) or nil
    local rows = dims and tonumber(dims.viewport_rows or dims.rows) or nil
    if not cols or cols < 1 or not rows or rows < 1 then
      return false
    end

    local font_size = nil
    if window and window.effective_config then
      local ok_config, config = pcall(window.effective_config, window)
      if ok_config and type(config) == "table" then
        font_size = config.font_size
      end
    end

    local payload = nil
    if line2 == nil then
      payload = line1 .. "\x1b[K"
    elseif rows < 2 then
      payload = line2 .. "\x1b[K"
    else
      local start_row = math.max(1, rows - 1)
      payload = string.format("\x1b[%d;1H", start_row) .. line1 .. "\x1b[K\r\n" .. line2 .. "\x1b[K"
    end
    local frame = "\x1b[?25l\x1b[H\x1b[2J" .. payload
    local layout_key = core.render_layout_key(status_pane:pane_id(), cols, rows, font_size)

    if
      tab_state.last_render_ok
      and tab_state.last_render_frame == frame
      and tab_state.last_render_layout == layout_key
    then
      return true
    end

    if not status_pane.inject_output then
      if not tab_state._warned_inject_output then
        tab_state._warned_inject_output = true
        local domain = nil
        if status_pane.get_domain_name then
          local ok_dn, dn = pcall(status_pane.get_domain_name, status_pane)
          domain = ok_dn and dn or nil
        end
        wezterm.log_error(
          "codex_statusline: pane:inject_output is not available; cannot render bottom status pane"
            .. " pane_id="
            .. tostring(status_pane:pane_id())
            .. " domain="
            .. tostring(domain)
        )
      end
      return false
    end

    local ok, err = pcall(status_pane.inject_output, status_pane, frame)
    if ok then
      tab_state.last_render_frame = frame
      tab_state.last_render_layout = layout_key
      tab_state.last_render_ok = true
      if opts.debug and not tab_state._rendered_once then
        tab_state._rendered_once = true
        wezterm.log_info(
          "codex_statusline: rendered status pane"
            .. " pane_id="
            .. tostring(status_pane:pane_id())
            .. " cols="
            .. tostring(cols)
            .. " rows="
            .. tostring(rows)
        )
      end
      return true
    end

    tab_state.last_render_ok = false
    if not tab_state._warned_inject_error then
      tab_state._warned_inject_error = true
      wezterm.log_error(
        "codex_statusline: failed to inject output"
          .. " pane_id="
          .. tostring(status_pane:pane_id())
          .. " cols="
          .. tostring(cols)
          .. " rows="
          .. tostring(rows)
          .. " err="
          .. tostring(err)
      )
    end
    return false
  end

  local function handle_update(window, active_pane)
    if not opts.bottom_pane.enabled then
      return
    end

    local tab = nil
    if window.active_tab then
      tab = window:active_tab()
    end
    if (not tab) and window.mux_window then
      local mw = window:mux_window()
      if mw and mw.active_tab then
        tab = mw:active_tab()
      end
    end
    if not tab then
      return
    end
    local tab_id = tab:tab_id()
    local tab_key = tab_state_key(window, tab_id)
    state.tabs[tab_key] = state.tabs[tab_key] or {}
    local tab_state = state.tabs[tab_key]

    if tab_state.status_pane_id then
      local ok_known, known = pcall(wezterm.mux.get_pane, tab_state.status_pane_id)
      if ok_known and not known then
        clear_status_pane_reference(tab_state)
      end
    end

    -- If we lost state (or have duplicates), reconcile by scanning panes for a
    -- pane titled "codex-statusline". Keep only the bottom-most one.
    if tab.panes_with_info then
      local ok_pi, panes_info = pcall(tab.panes_with_info, tab)
      if ok_pi and type(panes_info) == "table" then
        local status_infos = {}
        local max_top = 0
        for _, info in ipairs(panes_info) do
          if info then
            max_top = math.max(max_top, tonumber(info.top) or 0)
            local p = info.pane
            if p and p.pane_id then
              local pid = p:pane_id()
              local is_status = (tab_state.status_pane_id and pid == tab_state.status_pane_id) or false
              if (not is_status) and p.get_title then
                local ok_title, title = pcall(p.get_title, p)
                if ok_title and title == "codex-statusline" then
                  is_status = true
                end
              end
              if is_status then
                table.insert(status_infos, info)
              end
            end
          end
        end

        if #status_infos > 0 then
          table.sort(status_infos, function(a, b)
            return (tonumber(a.top) or 0) > (tonumber(b.top) or 0)
          end)
          local keep = status_infos[1]
          local keep_id = keep and keep.pane and keep.pane.pane_id and keep.pane:pane_id() or nil
          if keep_id then
            if tab_state.status_pane_id ~= keep_id then
              reset_status_render_state(tab_state)
            end
            tab_state.status_pane_id = keep_id
            if (tonumber(keep.top) or 0) ~= max_top then
              -- Status pane drifted away from the bottom; close it so we can
              -- recreate it as a top_level Bottom split.
              if opts.debug then
                wezterm.log_info(
                  "codex_statusline: status pane not at bottom; closing pane_id="
                    .. tostring(keep_id)
                    .. " top="
                    .. tostring(keep.top)
                    .. " max_top="
                    .. tostring(max_top)
                )
              end
              close_status_pane(window, tab_id, tab_state, "recreate")
            else
              -- Close any extra status panes.
              for i = 2, #status_infos do
                local extra = status_infos[i]
                if extra and extra.pane and window and window.perform_action then
                  if opts.debug and extra.pane.pane_id then
                    wezterm.log_info(
                      "codex_statusline: closing extra status pane"
                        .. " pane_id="
                        .. tostring(extra.pane:pane_id())
                        .. " top="
                        .. tostring(extra.top)
                    )
                  end
                  pcall(window.perform_action, window, wezterm.action.CloseCurrentPane({ confirm = false }), extra.pane)
                end
              end
            end
          end
        end
      end
    end

    -- Prefer mux tab active pane; it avoids special overlay panes that can
    -- appear as the active gui pane and don't have foreground process info.
    if tab.active_pane then
      local ok_ap, ap = pcall(tab.active_pane, tab)
      if ok_ap and ap then
        active_pane = ap
      end
    elseif tab.panes_with_info then
      local ok_pi, panes_info = pcall(tab.panes_with_info, tab)
      if ok_pi and type(panes_info) == "table" then
        for _, info in ipairs(panes_info) do
          if info and info.is_active and info.pane then
            active_pane = info.pane
            break
          end
        end
      end
    end
    if not active_pane then
      return
    end

    local target_pane = active_pane
    if tab_state.status_pane_id and active_pane:pane_id() == tab_state.status_pane_id then
      if opts.bottom_pane.prevent_focus and window and window.perform_action then
        -- If the user clicked the status pane, immediately return focus to the
        -- main pane so the Codex prompt remains usable.
        pcall(window.perform_action, window, wezterm.action.ActivatePaneDirection("Up"), active_pane)
      end

      local main = nil
      if tab_state.main_pane_id then
        local ok_main, p = pcall(wezterm.mux.get_pane, tab_state.main_pane_id)
        main = ok_main and p or nil
      end
      if (not main) and tab.panes_with_info then
        local ok_pi, panes_info = pcall(tab.panes_with_info, tab)
        if ok_pi and type(panes_info) == "table" then
          local best = nil
          local best_area = -1
          for _, info in ipairs(panes_info) do
            if info and info.pane and info.pane.pane_id then
              local pid = info.pane:pane_id()
              if pid ~= tab_state.status_pane_id then
                local area = (info.width or 0) * (info.height or 0)
                if area > best_area then
                  best_area = area
                  best = info.pane
                end
              end
            end
          end
          main = best
        end
      end
      if main then
        target_pane = main
        if opts.bottom_pane.prevent_focus then
          if main.activate then
            pcall(main.activate, main)
          elseif window and window.perform_action then
            pcall(window.perform_action, window, wezterm.action.ActivatePaneDirection("Up"), active_pane)
          end
        end
      end
    end

    local pane_id = target_pane:pane_id()
    local pane_key = id_key(pane_id)
    state.panes[pane_key] = state.panes[pane_key] or { offset = 0 }
    local pane_state = state.panes[pane_key]
    pane_state.pane_cwd = pane_cwd_file_path(target_pane)
    pane_state.pane_cwd_norm = normalize_path(pane_state.pane_cwd)

    local codex_info = build_codex_cells(opts, target_pane, pane_state)
    if codex_info and codex_info.active and pane_state and pane_state.pane_cwd_norm and not pane_state.codex_cwd_norm then
      pane_state.codex_cwd_norm = pane_state.pane_cwd_norm
      if opts.debug then
        wezterm.log_info("codex_statusline: locked codex cwd=" .. tostring(pane_state.codex_cwd_norm))
      end
    end

    if opts.debug then
      local pname = nil
      if target_pane.get_foreground_process_name then
        local ok_pname, val = pcall(target_pane.get_foreground_process_name, target_pane)
        pname = ok_pname and val or nil
      end
      local sig = table.concat({
        tostring(window_id_key(window) or "?"),
        tostring(tab_id),
        tostring(target_pane:pane_id()),
        tostring(pname),
        tostring(codex_info and codex_info.active),
        tostring(codex_info and codex_info.tree_state),
        tostring(codex_info and codex_info.codex_pid),
        tostring(codex_info and codex_info.process_kind),
        tostring(codex_info and codex_info.tree_reason),
        tostring(codex_info and codex_info.title_bridge_source),
        tostring(codex_info and codex_info.live_reasoning),
        tostring(pane_state and pane_state.codex_confirmed),
        tostring(pane_state and pane_state.pane_cwd),
      }, "|")
      if sig ~= tab_state._last_update_sig then
        tab_state._last_update_sig = sig
        wezterm.log_info(
          "codex_statusline: update"
            .. " w="
            .. tostring(window_id_key(window) or "?")
            .. " tab_id="
            .. tostring(tab_id)
            .. " pane_id="
            .. tostring(target_pane:pane_id())
            .. " fg="
            .. tostring(pname)
            .. " active="
            .. tostring(codex_info and codex_info.active)
            .. " tree="
            .. tostring(codex_info and codex_info.tree_state)
            .. " codex_pid="
            .. tostring(codex_info and codex_info.codex_pid)
            .. " kind="
            .. tostring(codex_info and codex_info.process_kind)
            .. " reason="
            .. tostring(codex_info and codex_info.tree_reason)
            .. " title_bridge="
            .. tostring(codex_info and codex_info.title_bridge_source)
            .. " live_reasoning="
            .. tostring(codex_info and codex_info.live_reasoning)
            .. " confirmed="
            .. tostring(pane_state and pane_state.codex_confirmed)
            .. " cwd="
            .. tostring(pane_state and pane_state.pane_cwd)
        )
      end
    end

    local now = os.time()
    if not codex_info or not codex_info.active then
      tab_state.inactive_since = tab_state.inactive_since or now
      if core.inactivity_grace_elapsed(
        tab_state.inactive_since,
        now,
        opts.bottom_pane.close_grace_seconds
      ) then
        if pane_state._codex_active or pane_state.rollout_path or not pane_state._inactive_mapping_checked then
          retire_bridge_generation(opts, target_pane, pane_state)
          clear_rollout_data(pane_state)
          pane_state._inactive_mapping_checked = true
        end
        pane_state._codex_active = false
        pane_state.codex_pid = nil
        pane_state.codex_process_kind = nil
        if tab_state.status_pane_id then
          close_status_pane(window, tab_id, tab_state, "inactive")
        end
      end
      return
    end
    tab_state.inactive_since = nil
    pane_state._inactive_mapping_checked = false
    if tab_state.status_close_reason == "inactive" then
      tab_state.status_close_requested = nil
      tab_state.status_close_reason = nil
    end

    local detected_codex_pid = codex_info.codex_pid
    local wrapper_promotion = pane_state.codex_process_kind == "wrapper" and codex_info.process_kind == "native"
    if
      detected_codex_pid
      and pane_state.codex_pid
      and detected_codex_pid ~= pane_state.codex_pid
      and not wrapper_promotion
    then
      retire_bridge_generation(opts, target_pane, pane_state)
      clear_rollout_data(pane_state)
    end
    pane_state.codex_pid = detected_codex_pid or pane_state.codex_pid
    pane_state.codex_process_kind = codex_info.process_kind or pane_state.codex_process_kind
    pane_state._codex_active = true

    tab_state.main_pane_id = target_pane:pane_id()

    local status_pane = ensure_status_pane(window, target_pane, tab_id, tab_state)
    if not status_pane then
      return
    end

    if opts.sessions.enabled then
      pane_state = update_rollout_state(opts, target_pane, pane_state)
      state.panes[pane_key] = pane_state
    end

    local dims = pane_dimensions(status_pane)
    local cols = dims and tonumber(dims.cols) or nil
    local rows = dims and tonumber(dims.viewport_rows or dims.rows) or nil
    local desired_rows = math.max(1, opts.bottom_pane.rows or 1)
    if not cols or cols < 1 or rows ~= desired_rows then
      close_status_pane(window, tab_id, tab_state, "recreate")
      return
    end

    local line1, line2 = build_lines(opts, codex_info, pane_state, cols)
    repaint_status_pane(window, status_pane, tab_state, line1, line2)
  end

  -- Prefer update-status, but also hook update-right-status for older builds.
  wezterm.on("update-status", handle_update)
  if opts.compat.update_right_status then
    wezterm.on("update-right-status", handle_update)
  end
end

return M
