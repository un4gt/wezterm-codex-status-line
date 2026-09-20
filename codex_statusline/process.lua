local core = require("codex_statusline_core")
local util = require("codex_statusline.util")
local M = {}

function M.new(wezterm, config)
  local trim = util.trim
  local first_user_var = util.first_user_var
  local parse_boolish = util.parse_boolish
  local load_codex_config = config.load_codex_config
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
      local ok, vars = pcall(pane.get_user_vars, pane)
      if ok and type(vars) == "table" then user_vars = vars end
    end

    local active_var = parse_boolish(first_user_var(user_vars, opts.user_vars.active))

    local fg_process = foreground_process_path(pane)
    local fg_base = process_basename(fg_process)
    local tree_result = codex_process_tree_result(pane, pane_state, opts)
    -- Do not use `and/or` here: an explicit false means the process walk
    -- reached the terminal boundary and is materially different from unknown.
    local tree_state = tree_result and tree_result.state
    local process_is_codex = tree_state == true and tree_result.pid == tree_result.foreground_pid
    local title_signal, title_read_ok, terminal_title = codex_terminal_title_signal(opts, pane)

    local model = first_user_var(user_vars, opts.user_vars.model)
    local thinking = first_user_var(user_vars, opts.user_vars.thinking)
    local provider = first_user_var(user_vars, opts.user_vars.provider)
    local service_tier = nil

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
      return { active = false, lifecycle = "exited", tree_state = false, tree_reason = "explicit-inactive" }
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
        tree_state,
        tree_result and tree_result.pid or nil
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
      elseif tree_state == false then
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
        service_tier = cfg.service_tier
      end
    end

    local lifecycle = "unknown"
    if process_seen or title_signal then
      lifecycle = "running"
    elseif tree_state == false then
      lifecycle = "exited"
    end
    return {
      active = active,
      lifecycle = lifecycle,
      model = model,
      thinking = thinking,
      live_model = title_signal and title_signal.model or nil,
      live_reasoning = title_signal and title_signal.reasoning or nil,
      provider = provider,
      service_tier = service_tier,
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

  return {
    build_codex_cells = build_codex_cells,
  }

end

return M
