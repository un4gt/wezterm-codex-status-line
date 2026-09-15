local core = require("codex_statusline_core")
local util = require("codex_statusline.util")
local M = {}

function M.new(wezterm, config, adapter)
  local trim = util.trim
  local path_join = util.path_join
  local read_file = util.read_file
  local normalize_path = util.normalize_path
  local is_windows = util.is_windows
  local normalize_session_meta_payload = util.normalize_session_meta_payload
  local path_is_within = util.path_is_within
  local safe_json_parse = adapter.safe_json_parse
  local pane_cwd_file_path = adapter.pane_cwd_file_path
  local codex_home_for_opts = config.codex_home_for_opts
  local bridge_root_for_opts = config.bridge_root_for_opts
  local SESSION_INDEX_CACHE = {
    at = 0,
    last_full_scan_at = 0,
    root = nil,
    entries = nil,
    by_path = nil,
  }

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

  local function read_rollout_activity_timestamp(path, seek_bytes, max_seek_bytes)
    local fh = io.open(path, "r")
    if not fh then
      return nil
    end

    local file_size = fh:seek("end") or 0
    local window = math.max(1024, tonumber(seek_bytes) or 65536)
    local max_window = math.max(window, tonumber(max_seek_bytes) or (8 * 1024 * 1024))
    local latest = nil

    while true do
      local start = math.max(0, file_size - window)
      fh:seek("set", start)
      if start > 0 then
        fh:read("*l")
      end

      for line in fh:lines() do
        local timestamp = line:match('^%s*{"timestamp"%s*:%s*"([^"]+)"')
        if not timestamp then
          timestamp = core.event_timestamp(safe_json_parse(line))
        end
        if timestamp and (not latest or timestamp > latest) then
          latest = timestamp
        end
      end

      if latest or start == 0 or window >= max_window then
        break
      end
      window = math.min(max_window, window * 2)
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

  local BRIDGE_ACTIVITY_FALLBACK_REASONS = {
    ["mapping-unavailable"] = true,
    ["mapping-generation-retired"] = true,
    ["mapping-cwd-mismatch"] = true,
    ["mapping-rollout-unavailable"] = true,
  }

  local function pane_rollout_cwd(pane, pane_state)
    if pane_state and trim(pane_state.codex_cwd_norm) then
      return pane_state.codex_cwd_norm
    end
    return normalize_path(pane_cwd_file_path(pane))
  end

  local function rollout_entries_with_activity(opts, entries, pane_cwd)
    local matches = {}
    for _, meta in ipairs(entries or {}) do
      if meta._cwd_norm and meta._cwd_norm == pane_cwd then
        meta._activity_timestamp = read_rollout_activity_timestamp(
          meta._rollout_path,
          opts.sessions.activity_seek_bytes,
          opts.sessions.activity_max_seek_bytes
        ) or trim(meta.timestamp) or ""
        table.insert(matches, meta)
      end
    end
    return matches
  end

  local function detect_bridge_activity_fallback(opts, pane, pane_state, bridge_reason, force)
    if opts.sessions.resume_fallback_enabled == false then
      return nil, "fallback-disabled"
    end
    if not BRIDGE_ACTIVITY_FALLBACK_REASONS[bridge_reason] then
      return nil, "unsafe-bridge-failure"
    end
    if
      not force
      and pane_state
      and pane_state.rollout_source == "bridge-activity"
      and trim(pane_state.rollout_path)
    then
      return pane_state.rollout_path, nil, pane_state.session_meta
    end

    local now = os.time()
    local scan_ttl = math.max(0, tonumber(opts.sessions.resume_fallback_scan_ttl_seconds) or 2)
    if
      not force
      and pane_state
      and pane_state._bridge_fallback_checked_at
      and (now - pane_state._bridge_fallback_checked_at) < scan_ttl
    then
      return nil, pane_state.bridge_fallback_reason or "fallback-scan-cached"
    end
    if pane_state then
      pane_state._bridge_fallback_checked_at = now
    end

    local codex_home = codex_home_for_opts(opts)
    local pane_cwd = pane_rollout_cwd(pane, pane_state)
    if not codex_home or not pane_cwd then
      return nil, "fallback-input-unavailable"
    end

    local sessions_root = path_join({ codex_home, "sessions" })
    local entries = build_session_index(opts, sessions_root)
    local matches = rollout_entries_with_activity(opts, entries, pane_cwd)
    local max_age = math.max(1, tonumber(opts.sessions.resume_fallback_max_age_seconds) or 30)
    local clock_skew = math.max(0, tonumber(opts.sessions.resume_fallback_clock_skew_seconds) or 5)
    local cutoff_unix = now - max_age
    if pane_state and tonumber(pane_state.codex_started_at) then
      cutoff_unix = math.max(cutoff_unix, pane_state.codex_started_at - clock_skew)
    end
    local cutoff = os.date("!%Y-%m-%dT%H:%M:%S", cutoff_unix)
    local selected, reason, count = core.select_unique_active_rollout(matches, pane_cwd, cutoff)
    if pane_state then
      pane_state.bridge_fallback_reason = reason
      pane_state.bridge_fallback_candidates = count
    end
    if not selected then
      return nil, reason
    end
    return selected._rollout_path, nil, selected
  end

  local function detect_rollout_for_pane(opts, pane, pane_state, force)
    local binding_mode = trim(opts.sessions.binding_mode) or "auto"
    binding_mode = binding_mode:lower()
    if binding_mode ~= "heuristic" then
      local bridge_path, bridge_source, mapping, meta = detect_bridge_rollout(opts, pane, pane_state)
      if bridge_path then
        if pane_state then
          pane_state.bridge_wait_reason = nil
          pane_state.bridge_fallback_reason = nil
          pane_state.bridge_fallback_candidates = nil
          pane_state._bridge_fallback_checked_at = nil
        end
        return bridge_path, bridge_source, mapping, meta
      end
      if pane_state then
        pane_state.bridge_wait_reason = bridge_source
      end
      if bridge_required(opts) then
        if binding_mode == "auto" then
          local fallback_path, fallback_reason, fallback_meta = detect_bridge_activity_fallback(
            opts,
            pane,
            pane_state,
            bridge_source,
            force
          )
          if fallback_path then
            return fallback_path, "bridge-activity", nil, fallback_meta
          end
          if pane_state then
            pane_state.bridge_fallback_reason = fallback_reason
          end
        end
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

    local pane_cwd = pane_rollout_cwd(pane, pane_state)

    if pane_cwd then
      local matches = rollout_entries_with_activity(opts, entries, pane_cwd)

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

  return {
    detect_rollout_for_pane = detect_rollout_for_pane,
    read_session_meta = read_session_meta,
    bridge_mapping_for_pane = bridge_mapping_for_pane,
    bridge_required = bridge_required,
  }

end

return M
