local core = require("codex_statusline_core")
local util = require("codex_statusline.util")
local M = {}

function M.new(wezterm, index, adapter)
  local trim = util.trim
  local to_number = util.to_number
  local normalize_session_meta_payload = util.normalize_session_meta_payload
  local safe_json_parse = adapter.safe_json_parse
  local detect_rollout_for_pane = index.detect_rollout_for_pane
  local read_session_meta = index.read_session_meta
  local bridge_mapping_for_pane = index.bridge_mapping_for_pane
  local bridge_required = index.bridge_required
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
    if pane_state.usage then
      local history = pane_state.cost_history
      pane_state.usage.by_model = history and history.by_model or {}
      pane_state.usage.cost_complete = history ~= nil and history.complete
        and history.total ~= nil and history.caught_up == true
    end
  end

  local function read_complete_line(fh)
    local start = fh:seek()
    local line = fh:read("*L")
    if line and line:sub(-1) ~= "\n" then
      -- Retry a line that Codex is still writing on the next refresh.
      fh:seek("set", start)
      return nil
    end
    return line and line:gsub("\r?\n$", "") or nil
  end

  local function update_cost_history(opts, pane_state, fh, file_size)
    local history = pane_state.cost_history or core.new_cost_history()
    pane_state.cost_history = history
    fh:seek("set", history.offset)
    for _ = 1, opts.sessions.max_tail_lines do
      if fh:seek() >= pane_state.offset then break end
      local line = read_complete_line(fh)
      if not line then break end
      local object = safe_json_parse(line)
      if object then
        core.record_cost_usage(history, object)
      elseif not line:match("^%s*$") then
        history.complete = false
      end
    end
    history.offset = fh:seek()
    history.caught_up = history.offset == pane_state.offset and pane_state.offset >= file_size
  end

  local function clear_rollout_data(pane_state)
    if not pane_state then
      return
    end
    pane_state.rollout_path = nil
    pane_state.rollout_source = nil
    pane_state.bridge_mapping = nil
    pane_state.bridge_wait_reason = nil
    pane_state.bridge_fallback_reason = nil
    pane_state.bridge_fallback_candidates = nil
    pane_state._bridge_fallback_checked_at = nil
    pane_state.session_meta = nil
    pane_state.turn_context = nil
    pane_state.thread_settings = nil
    pane_state.activity = nil
    pane_state._logged_session_id = nil
    pane_state.token_usage_total = nil
    pane_state.token_usage_last = nil
    pane_state.model_context_window = nil
    pane_state.usage = nil
    pane_state.cost_history = nil
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
    pane_state.thread_settings = nil
    pane_state.activity = nil
    pane_state._logged_session_id = nil
    pane_state.token_usage_total = nil
    pane_state.token_usage_last = nil
    pane_state.model_context_window = to_number(pane_state.session_meta and pane_state.session_meta.context_window)
    pane_state.usage = nil
    pane_state.cost_history = nil
    pane_state.offset = 0
  end

  local function retire_bridge_generation(opts, pane, pane_state)
    if not opts.sessions or not opts.sessions.enabled then
      return
    end
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
                .. " fallback_reason="
                .. tostring(pane_state.bridge_fallback_reason)
                .. " fallback_candidates="
                .. tostring(pane_state.bridge_fallback_candidates)
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

    local fh, open_err = io.open(pane_state.rollout_path, "rb")
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
      if not read_complete_line(fh) then
        fh:close()
        return pane_state
      end
    end

    local max_lines = opts.sessions.max_tail_lines
    local count = 0
    while count < max_lines do
      local line = read_complete_line(fh)
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

        local thread_settings = core.extract_thread_settings(obj)
        if thread_settings then
          pane_state.thread_settings = thread_settings
        end
        pane_state.activity = core.merge_activity_state(pane_state.activity, obj)

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
    update_cost_history(opts, pane_state, fh, file_size)
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

  return {
    update_rollout_state = update_rollout_state,
    retire_bridge_generation = retire_bridge_generation,
    clear_rollout_data = clear_rollout_data,
  }

end

return M
