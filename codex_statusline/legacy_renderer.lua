local core = require("codex_statusline_core")
local util = require("codex_statusline.util")
local M = {}
function M.new(wezterm, opts, git, formatting)
  local trim = util.trim
  local git_branch_for_cwd = git.git_branch_for_cwd
  local format_reset_item = formatting.format_reset_item
  local format_int = formatting.format_int
  local substitute_home = formatting.substitute_home
  local truncate_to_width = formatting.truncate_to_width
  local shorten_path = formatting.shorten_path
  local segments_width = formatting.segments_width
  local build_powerline = formatting.build_powerline
  local build_plain_line = formatting.build_plain_line
    local function build_legacy_lines(opts, codex_info, pane_state, cols)
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
          text = core.model_text(model, opts.render.model_display),
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
      table.insert(segments, {
        kind = "icon",
        text = (type(opts.icon) == "table" and trim(opts.icon.text)) or "",
        bg = opts.theme.segments.icon.bg,
        fg = opts.theme.segments.icon.fg,
      })

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
        table.insert(items, { kind = "version", text = require("codex_statusline.version").text,
          bg = opts.theme.bg, fg = opts.theme.dim or opts.theme.fg })
        if opts.render.powerline then
          return build_powerline(items, glyphs, cols, opts.theme)
        end
        if opts.render.plain_fallback then
          return build_plain_line(items, cols, opts.theme)
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
          table.insert(fallback, segments[#segments])
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

  return {
    build_legacy_lines = build_legacy_lines,
  }

end
return M
