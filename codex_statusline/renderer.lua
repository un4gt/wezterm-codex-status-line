local core = require("codex_statusline_core")
local util = require("codex_statusline.util")
local M = {}
function M.new(wezterm, opts, git, adapter)
  local trim = util.trim
  local is_windows = util.is_windows
  local pane_dimensions = adapter.pane_dimensions
  local git_info_for_cwd = git.git_info_for_cwd
  local formatting = require("codex_statusline.formatting").new(wezterm)
  local format_reset_item = formatting.format_reset_item
  local format_int = formatting.format_int
  local substitute_home = formatting.substitute_home
  local truncate_to_width = formatting.truncate_to_width
  local shorten_path = formatting.shorten_path
  local segments_width = formatting.segments_width
  local build_powerline = formatting.build_powerline
  local build_plain_line = formatting.build_plain_line
  local build_legacy_lines = require("codex_statusline.legacy_renderer").new(wezterm, opts, git, formatting).build_legacy_lines
  local function path_basename(path)
    local value = trim(path)
    return value and (value:match("[^/\\]+$") or value) or nil
  end

  local function scalar_text(value)
    if type(value) == "string" or type(value) == "number" then
      return trim(value)
    end
    return nil
  end

  local function first_scalar(...)
    for index = 1, select("#", ...) do
      local value = scalar_text(select(index, ...))
      if value then
        return value
      end
    end
    return nil
  end

  local function permission_text(settings, turn_context)
    local active = type(settings) == "table" and settings.active_permission_profile or nil
    active = type(active) == "table" and scalar_text(active.id) or scalar_text(active)
    local active_labels = {
      [":read-only"] = "Read Only",
      [":workspace"] = "Workspace",
      [":danger-full-access"] = "Full Access",
    }
    if active then
      return active_labels[active] or active
    end

    local profile = type(settings) == "table" and settings.permission_profile or nil
    profile = type(profile) == "table" and profile or (type(turn_context) == "table" and turn_context.permission_profile or nil)
    local profile_type = type(profile) == "table" and first_scalar(profile.type, profile.mode) or scalar_text(profile)
    if profile_type == "disabled" or profile_type == "danger-full-access" then
      return "Full Access"
    end
    if profile_type == "external" or profile_type == "external-sandbox" then
      return "External"
    end

    local sandbox = type(turn_context) == "table" and turn_context.sandbox_policy or nil
    local sandbox_type = type(sandbox) == "table" and first_scalar(sandbox.type, sandbox.mode) or scalar_text(sandbox)
    if sandbox_type == "read-only" then
      return "Read Only"
    end
    if sandbox_type == "workspace-write" then
      return "Workspace"
    end
    if sandbox_type == "danger-full-access" then
      return "Full Access"
    end
    if profile_type == "managed" then
      return "Custom permissions"
    end
    return nil
  end

  local function approval_text(settings, turn_context)
    local policy = first_scalar(
      type(settings) == "table" and settings.approval_policy or nil,
      type(turn_context) == "table" and turn_context.approval_policy or nil
    )
    if not policy then
      return nil
    end
    policy = policy:lower():gsub("_", "-")
    if policy == "on-request" then
      local reviewer = first_scalar(
        type(settings) == "table" and settings.approvals_reviewer or nil,
        type(turn_context) == "table" and turn_context.approvals_reviewer or nil
      )
      reviewer = reviewer and reviewer:lower():gsub("-", "_") or nil
      return reviewer == "auto_review" and "Approve for me" or "Ask"
    end
    local labels = {
      untrusted = "Untrusted",
      never = "Never",
      granular = "Granular",
    }
    return labels[policy] or policy
  end

    local function build_lines(opts, codex_info, pane_state, cols)
      codex_info = type(codex_info) == "table" and codex_info or {}
      local meta = pane_state and pane_state.session_meta or nil
      local turn_context = pane_state and pane_state.turn_context or nil
      local settings = pane_state and pane_state.thread_settings or nil
      local collaboration = turn_context and turn_context.collaboration_mode or nil
      local model = first_scalar(
        type(settings) == "table" and settings.model or nil,
        type(collaboration) == "table" and collaboration.settings and collaboration.settings.model or nil,
        turn_context and turn_context.model or nil
      )
      model = model or trim(codex_info.model)
      local reasoning = trim(codex_info.live_reasoning)
      reasoning = reasoning or first_scalar(
        type(settings) == "table" and settings.reasoning_effort or nil,
        type(collaboration) == "table" and collaboration.settings and collaboration.settings.reasoning_effort or nil,
        turn_context and turn_context.effort or nil,
        turn_context and turn_context.model_reasoning_effort or nil
      )
      reasoning = reasoning or trim(codex_info.thinking)
      local provider = first_scalar(
        type(settings) == "table" and settings.model_provider_id or nil,
        meta and meta.model_provider or nil
      )
      provider = provider or trim(codex_info.provider)
      local service_tier = first_scalar(
        type(settings) == "table" and settings.service_tier or nil,
        codex_info.service_tier
      )
      local personality = first_scalar(
        type(settings) == "table" and settings.personality or nil,
        turn_context and turn_context.personality or nil
      )
      if personality and personality:lower() == "none" then
        personality = nil
      end
      local cwd = first_scalar(
        type(settings) == "table" and settings.cwd or nil,
        turn_context and turn_context.cwd or nil,
        meta and meta.cwd or nil
      )
      cwd = cwd or (pane_state and trim(pane_state.pane_cwd) or nil)
      local metadata_git_branch = nil
      if meta and type(meta.git) == "table" then
        metadata_git_branch = trim(meta.git.branch)
      end
      local git_info = git_info_for_cwd(opts, cwd, metadata_git_branch)
      local git_branch = git_info.branch
      local project = path_basename(git_info.root)
      local layout = core.render_layout(cols)

      local function basename(path)
        local value = substitute_home(path) or ""
        local separator = is_windows() and "\\" or "/"
        return value:match("[^" .. separator .. "]+$") or value
      end

      local cwd_display = nil
      if cwd then
        local max_width = math.max(10, math.floor(cols * 0.28))
        if layout == "narrow" then
          cwd_display = truncate_to_width(basename(cwd), math.max(10, math.floor(cols * 0.22)))
        else
          cwd_display = shorten_path(cwd, max_width)
        end
      end

      local waiting = core.waiting_status(
        pane_state and pane_state.rollout_path or nil,
        pane_state and pane_state.rollout_source or nil,
        pane_state and pane_state.bridge_wait_reason or nil
      )
      local snapshot = {
        label = opts.label,
        model = model,
        reasoning = reasoning,
        activity = pane_state and pane_state.activity or nil,
        provider = provider,
        personality = personality,
        service_tier = service_tier,
        cwd = cwd_display,
        project = project,
        git = git_branch,
        permissions = permission_text(settings, turn_context),
        approval = approval_text(settings, turn_context),
        usage = pane_state and pane_state.usage or nil,
        thread_id = first_scalar(
          type(settings) == "table" and settings.thread_id or nil,
          meta and meta.id or nil,
          pane_state and pane_state.bridge_mapping and pane_state.bridge_mapping.thread_id or nil
        ),
        codex_version = meta and first_scalar(meta.cli_version) or nil,
        waiting = waiting.minimal,
      }
      local ok, plan = pcall(core.build_render_plan, opts, snapshot, cols)
      if not ok or type(plan) ~= "table" or type(plan.lines) ~= "table" then
        wezterm.log_error("codex_statusline: compact renderer failed; using compatibility renderer: " .. tostring(plan))
        return build_legacy_lines(opts, codex_info, pane_state, cols)
      end

      local glyphs = opts.theme.glyphs or {}
      local function render_segments(segments)
        if type(segments) ~= "table" or #segments == 0 then
          return ""
        end
        local decorated = {}
        for _, segment in ipairs(segments) do
          local copy = {
            kind = segment.kind,
            text = segment.text,
            bg = segment.bg,
            fg = segment.fg,
          }
          if opts.render.powerline and segment.kind == "git" and glyphs.branch then
            copy.text = glyphs.branch .. " " .. tostring(copy.text)
          elseif opts.render.powerline and segment.kind == "cwd" and glyphs.folder and layout ~= "narrow" then
            copy.text = glyphs.folder .. " " .. tostring(copy.text)
          end
          table.insert(decorated, copy)
        end
        if opts.render.powerline then
          return build_powerline(decorated, glyphs, cols, opts.theme)
        end
        if opts.render.plain_fallback then
          return build_plain_line(decorated, cols, opts.theme)
        end
        return ""
      end

      local line1 = render_segments(plan.lines[1])
      local line2 = plan.lines[2] and render_segments(plan.lines[2]) or nil
      if line2 == "" then
        line2 = nil
      end
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

  return {
    build_lines = build_lines,
    repaint_status_pane = repaint_status_pane,
  }

end
return M
