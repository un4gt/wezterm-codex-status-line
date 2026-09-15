local util = require("codex_statusline.util")
local layout = require("codex_statusline.layout")
local registry = require("codex_statusline.state")
local M = {}

function M.new(wezterm, opts, process, rollout, renderer, adapter)
  local busy = false
  local invalidations, show_requests, created = {}, {}, {}
  local last_background = {}

  local function log(message, important)
    if important or opts.debug then
      local writer = important and wezterm.log_error or wezterm.log_info
      if writer then writer("codex_statusline: " .. message) end
    end
  end

  local function defer(binding, reason)
    if binding.deferred ~= reason then
      binding.deferred = reason
      if reason then log("layout deferred owner_id=" .. binding.owner_id .. " reason=" .. reason) end
    end
  end

  local function verify(binding, pane)
    local marker = adapter.marker(pane)
    return marker and marker.owner_id == binding.owner_id
      and marker.status_id == binding.status_id and marker.generation == binding.status_generation
  end

  local function request_close(state, binding, reason, now)
    local id = binding.status_id
    if not id or id == binding.owner_id then return false end
    local pending = state.close_requests[id]
    if pending then return true end
    local pane, result = adapter.mux_pane_lookup(id)
    if result == "missing" then
      registry.forget_status(binding)
      created[id] = nil
      return false
    end
    if result ~= "found" or not (created[id] == binding.status_generation or verify(binding, pane)) then
      defer(binding, "ownership-unconfirmed")
      return false
    end
    -- Record the target before starting an operation that can yield to another callback.
    pending = { owner_id = binding.owner_id, generation = binding.status_generation,
      started_at = now, reason = reason, window_id = binding.window_id, tab_id = binding.tab_id }
    state.close_requests[id] = pending
    local ok, err = adapter.close(id)
    if ok then pending.last_request_at = now else pending.error = tostring(err) end
    log("requesting exact status pane close id=" .. id .. " w=" .. tostring(binding.window_id)
      .. " tab_id=" .. tostring(binding.tab_id) .. " reason=" .. reason
      .. " owner_id=" .. binding.owner_id .. " generation=" .. tostring(binding.status_generation))
    return true
  end

  local function reap_closes(state, now)
    for id, pending in pairs(state.close_requests) do
      local _, result = adapter.mux_pane_lookup(id)
      if result == "missing" then
        local binding = pending.owner_id and state.bindings[pending.owner_id]
        if binding and binding.status_id == id then registry.forget_status(binding) end
        state.close_requests[id] = nil
        created[id] = nil
        log("status pane close completed id=" .. id .. " owner_id=" .. tostring(pending.owner_id))
        local tab = state.tabs[tostring(pending.window_id) .. ":" .. tostring(pending.tab_id)]
        if tab then tab.signature = nil end
      elseif now - pending.started_at >= 10000 then
        if not pending.timed_out then
          pending.timed_out = true
          log("status pane close timed out id=" .. id .. " owner_id=" .. tostring(pending.owner_id), true)
        end
      elseif result == "found" and now - (pending.last_request_at or 0) >= 2000 then
        -- Retry only the original, immutable pane ID.
        pending.last_request_at = now
        local binding = pending.owner_id and state.bindings[pending.owner_id]
        local pane = select(1, adapter.mux_pane_lookup(id))
        if binding and pane and binding.status_id == id
          and binding.status_generation == pending.generation
          and (created[id] == pending.generation or verify(binding, pane)) then
          local ok, err = adapter.close(id)
          if not ok then pending.error = tostring(err) end
        end
      end
    end
  end

  local function reconcile(state, snap, window_id, now)
    local statuses = {}
    for _, binding in pairs(state.bindings) do binding.duplicate = nil end
    for _, info in ipairs(snap.infos) do
      local id = tostring(info.pane:pane_id())
      local marker = adapter.marker(info.pane)
      if marker then
        statuses[id] = true
        local binding = state.bindings[marker.owner_id]
        if not binding then binding = registry.binding(state, marker.owner_id) end
        if not binding.status_id and not state.close_requests[id] then
          binding.status_id = id
          binding.status_generation = marker.generation
        elseif binding.status_id ~= id then
          binding.duplicate = true
          defer(binding, "duplicate-status")
        end
      elseif state.close_requests[id] then
        statuses[id] = true
      end
    end
    for owner, binding in pairs(state.bindings) do
      local info = binding.status_id and snap.by_id[binding.status_id]
      if info then
        statuses[binding.status_id] = true
        if binding.legacy then
          if snap.by_id[owner] and adapter.legacy_placeholder(info.pane) then
            local generation = registry.generation(state, now)
            if adapter.mark(info.pane, owner, generation) then
              binding.status_generation = generation
              binding.legacy = nil
            end
          else
            defer(binding, "legacy-ownership-unconfirmed")
          end
        end
        local pending = state.close_requests[binding.status_id]
        if pending and not pending.owner_id then pending.owner_id = owner end
      end
      if snap.by_id[owner] and not statuses[owner] then
        binding.tab_id, binding.window_id = snap.id, window_id
      end
    end
    return statuses
  end

  local function observe_process(state, binding, pane, now)
    local data = state.panes[binding.owner_id]
    data.pane_cwd = adapter.pane_cwd_file_path(pane)
    data.pane_cwd_norm = util.normalize_path(data.pane_cwd)
    local signal = process.build_codex_cells(opts, pane, data)
    local lifecycle = signal.lifecycle
    if lifecycle == "running" then
      local promoted = data.codex_process_kind == "wrapper" and signal.process_kind == "native"
      local changed = signal.codex_pid and data.codex_pid and signal.codex_pid ~= data.codex_pid and not promoted
      if not binding.running or changed then
        if changed then
          rollout.retire_bridge_generation(opts, pane, data)
          rollout.clear_rollout_data(data)
        end
        binding.run_generation = registry.generation(state, now)
        binding.suppressed = nil
        binding.failed_signature = nil
        data.codex_started_at = now / 1000
      end
      binding.running = true
      binding.inactive_since = nil
      data.codex_pid = signal.codex_pid or data.codex_pid
      data.codex_process_kind = signal.process_kind or data.codex_process_kind
      data._codex_active = true
      data.codex_cwd_norm = data.codex_cwd_norm or data.pane_cwd_norm
      binding.signal = signal
    elseif lifecycle == "exited" then
      binding.inactive_since = binding.inactive_since or now
      if now - binding.inactive_since >= opts.bottom_pane.close_grace_seconds * 1000 then
        if binding.running then
          rollout.retire_bridge_generation(opts, pane, data)
          rollout.clear_rollout_data(data)
        end
        binding.running = false
        binding.signal = nil
        data._codex_active = false
        data.codex_pid = nil
        data.codex_process_kind = nil
        data.codex_started_at = nil
      end
    else
      -- An unavailable snapshot is not evidence that the owner exited.
      binding.inactive_since = nil
    end
    binding.observation = lifecycle
    local signature = table.concat({ lifecycle, tostring(signal.codex_pid), tostring(signal.tree_reason),
      tostring(binding.running), tostring(binding.run_generation), tostring(binding.tab_id), tostring(binding.window_id) }, ":")
    if data.last_signal_log ~= signature then
      data.last_signal_log = signature
      log("update w=" .. tostring(binding.window_id) .. " tab_id=" .. tostring(binding.tab_id)
        .. " pane_id=" .. binding.owner_id .. " active=" .. tostring(binding.running == true)
        .. " tree=" .. tostring(signal.tree_state) .. " reason=" .. tostring(signal.tree_reason)
        .. " owner_id=" .. binding.owner_id .. " lifecycle=" .. lifecycle
        .. " generation=" .. tostring(binding.run_generation))
    end
    return signal
  end

  local function status_for(state, binding)
    if not binding.status_id then return nil, "absent" end
    if state.close_requests[binding.status_id] then return nil, "closing" end
    local pane, result = adapter.mux_pane_lookup(binding.status_id)
    if result == "missing" then
      registry.forget_status(binding)
      binding.suppressed = binding.running == true
      defer(binding, binding.suppressed and "user-hidden" or nil)
      return nil, "hidden"
    end
    if result == "error" then return nil, "unknown" end
    if not verify(binding, pane) then
      defer(binding, "ownership-unconfirmed")
      return nil, "unverified"
    end
    return pane, "found"
  end

  local function current_snapshot(window, snap)
    local active = adapter.active_tab(window)
    if not active or tostring(active:tab_id()) ~= snap.id then return nil end
    local fresh = adapter.snapshot(snap.tab)
    if not fresh or fresh.zoomed or fresh.signature ~= snap.signature then return nil end
    return fresh
  end

  local function tab_pending(state, snap, window_id)
    for _, pending in pairs(state.close_requests) do
      if pending.tab_id == snap.id and pending.window_id == window_id then return true end
    end
    return false
  end

  local function render(window, state, binding, status)
    local data = state.panes[binding.owner_id]
    if binding.observation == "running" and opts.sessions.enabled then
      rollout.update_rollout_state(opts, select(1, adapter.mux_pane_lookup(binding.owner_id)), data)
    end
    local dimensions = adapter.pane_dimensions(status)
    if not dimensions or (tonumber(dimensions.cols) or 0) < 1 then return end
    binding.render = binding.render or {}
    local first, second = renderer.build_lines(opts, binding.signal, data, dimensions.cols)
    renderer.repaint_status_pane(window, status, binding.render, first, second)
  end

  local function update_tab(window, state, snap, visible, now)
    local window_id = util.window_id_key(window)
    local tab_key = window_id .. ":" .. snap.id
    state.tabs[tab_key] = state.tabs[tab_key] or {}
    local tab_state = state.tabs[tab_key]
    local stable = layout.observe(tab_state, snap.signature, now, opts.bottom_pane.layout_debounce_ms)
    local statuses = reconcile(state, snap, window_id, now)
    local changed = tab_pending(state, snap, window_id)
    for _, info in ipairs(snap.infos) do
      local id = tostring(info.pane:pane_id())
      if not statuses[id] and (visible or state.bindings[id]) then
        local binding = registry.binding(state, id)
        binding.tab_id, binding.window_id = snap.id, window_id
        -- Check disappearance before observing a new process generation.
        local status, status_result = status_for(state, binding)
        observe_process(state, binding, info.pane, now)
        if binding.running == false and binding.observation == "exited" then
          if status and stable and not snap.zoomed and not changed then
            changed = request_close(state, binding, "inactive", now)
          end
        elseif visible then
          if status and not snap.zoomed then
            render(window, state, binding, status)
            local status_info = snap.by_id[binding.status_id]
            if not layout.aligned(info, status_info) then
              if binding.observation == "running" and not binding.duplicate
                and stable and not changed and layout.can_repair(snap.infos, id, binding.status_id)
                and current_snapshot(window, snap) then
                changed = request_close(state, binding, "recreate", now)
              else
                defer(binding, snap.zoomed and "zoomed" or "preserve-user-layout")
              end
            else
              if not binding.duplicate then defer(binding, nil) end
            end
          elseif status_result == "absent" or status_result == "hidden" then
            if not binding.suppressed and binding.observation == "running"
              and not snap.zoomed and stable and not changed
              and binding.failed_signature ~= snap.signature then
              if layout.can_create(info, opts.bottom_pane.rows) and current_snapshot(window, snap) then
                changed = true
                binding.status_generation = registry.generation(state, now)
                local pane, err, marked = adapter.create(window, snap.tab, info.pane,
                  opts.bottom_pane.rows, binding.status_generation)
                tab_state.signature = nil
                if pane then
                  binding.status_id = tostring(pane:pane_id())
                  created[binding.status_id] = binding.status_generation
                  binding.render = nil
                  log("created status pane id=" .. binding.status_id .. " w=" .. window_id
                    .. " tab_id=" .. snap.id .. " owner_id=" .. id
                    .. " generation=" .. binding.status_generation)
                  if marked then
                    created[binding.status_id] = nil
                    render(window, state, binding, pane)
                  else
                    binding.failed_signature = snap.signature
                    request_close(state, binding, "marker-failed", now)
                    log("cannot mark status pane owner_id=" .. id .. " error=" .. tostring(err), true)
                  end
                else
                  binding.failed_signature = snap.signature
                  defer(binding, "split-failed")
                  log("failed to split status pane owner_id=" .. id .. " error=" .. tostring(err), true)
                end
              else
                defer(binding, "insufficient-space-or-layout-changed")
              end
            end
          end
        end
        if binding.running == false and not binding.status_id and not binding.suppressed then
          state.bindings[id] = nil
        end
      end
    end
    if visible and opts.bottom_pane.prevent_focus then
      local focused = snap.tab:active_pane()
      if focused then
        local marker = adapter.marker(focused)
        local binding = marker and state.bindings[marker.owner_id]
        if binding and verify(binding, focused) and snap.by_id[binding.owner_id] then
          pcall(snap.by_id[binding.owner_id].pane.activate, snap.by_id[binding.owner_id].pane)
        end
      end
    end
  end

  local function cleanup_moved_or_missing(state, now)
    for owner in pairs(state.panes) do
      if not state.bindings[owner] then
        local _, result = adapter.mux_pane_lookup(owner)
        if result == "missing" then state.panes[owner] = nil end
      end
    end
    for owner, binding in pairs(state.bindings) do
      local pane, result = adapter.mux_pane_lookup(owner)
      if result == "missing" then
        if binding.status_id then request_close(state, binding, "owner-missing", now) end
        if not binding.status_id then
          state.bindings[owner], state.panes[owner] = nil, nil
        end
      elseif result == "found" and binding.status_id then
        local status = select(1, adapter.mux_pane_lookup(binding.status_id))
        if status then
          local owner_tab = adapter.location(pane)
          local status_tab, status_window = adapter.location(status)
          if owner_tab and status_tab and owner_tab ~= status_tab then
            binding.tab_id, binding.window_id = status_tab, status_window
            local snap = adapter.snapshot(status:tab())
            local key = tostring(status_window) .. ":" .. status_tab
            local tab_state = state.tabs[key] or {}
            state.tabs[key] = tab_state
            if layout.observe(tab_state, snap and snap.signature, now, opts.bottom_pane.layout_debounce_ms)
              and not snap.zoomed then request_close(state, binding, "owner-moved", now) end
          end
        end
      end
    end
  end

  local function handle_update(window)
    local wid = util.window_id_key(window)
    if not wid or busy or not opts.bottom_pane.enabled then return end
    busy = true
    local state
    local ok, err = pcall(function()
      state = registry.load(wezterm)
      local now = adapter.now_ms()
      for key, tab in pairs(state.tabs) do
        if invalidations[key:match("^(.-):")] then tab.signature = nil end
      end
      invalidations = {}
      for id in pairs(show_requests) do
        local binding = state.bindings[id]
        if binding then
          binding.suppressed, binding.failed_signature = nil, nil
          local pending = binding.status_id and state.close_requests[binding.status_id]
          if pending then pending.started_at, pending.timed_out = now, nil end
        end
      end
      show_requests = {}
      reap_closes(state, now)
      local active = adapter.active_tab(window)
      local active_id = active and tostring(active:tab_id())
      local background = not last_background[wid] or now - last_background[wid] >= 2000
      cleanup_moved_or_missing(state, now)
      for _, tab in ipairs(adapter.window_tabs(window)) do
        local visible = tostring(tab:tab_id()) == active_id
        if visible or background then
          local snap = adapter.snapshot(tab)
          if snap then
            update_tab(window, state, snap, visible, now)
          else
            local tab_state = state.tabs[wid .. ":" .. tostring(tab:tab_id())]
            if tab_state then tab_state.signature = nil end
          end
        end
      end
      if background then last_background[wid] = now end
    end)
    if state then
      local saved, save_err = pcall(registry.save, wezterm, state)
      if not saved then ok, err = false, save_err end
    end
    busy = false
    if not ok then log("update failed: " .. tostring(err), true) end
  end

  local function invalidate(window)
    invalidations[tostring(util.window_id_key(window))] = true
  end

  local function show(window, pane)
    local marker = adapter.marker(pane)
    local id = marker and marker.owner_id or tostring(pane:pane_id())
    show_requests[id] = true
    handle_update(window)
  end

  return { handle_update = handle_update, invalidate = invalidate, show = show }
end

return M
