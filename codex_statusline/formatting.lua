local core = require("codex_statusline_core")
local util = require("codex_statusline.util")
local M = {}
function M.new(wezterm)
  local trim = util.trim
  local is_windows = util.is_windows
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
      if max_width < ell_w then
        return ""
      end
      if max_width == ell_w then
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

    local function split_right_segments(segments, cols)
      local left = {}
      local anchors = {}
      for _, segment in ipairs(segments or {}) do
        if segment.kind == "icon" or segment.kind == "version" then
          anchors[segment.kind] = segment
        else
          table.insert(left, segment)
        end
      end
      local right, width = {}, 0
      -- Reserve the installed version first, including when the icon is disabled.
      for _, kind in ipairs({ "version", "icon" }) do
        local segment = anchors[kind]
        if segment then
          local text = " " .. tostring(segment.text or "") .. " "
          local remaining = math.max(0, cols - width)
          if wezterm.column_width(text) > remaining then
            text = kind == "version" and truncate_to_width(tostring(segment.text or ""), remaining) or ""
          end
          if text ~= "" then
            table.insert(right, 1, { text = text, bg = segment.bg, fg = segment.fg })
            width = width + wezterm.column_width(text)
          end
        end
      end
      return left, right, width
    end

    local function append_right(items, right, gap, theme)
      if #right == 0 then return end
      if gap > 0 then
        table.insert(items, { Background = { Color = theme.bg } })
        table.insert(items, { Foreground = { Color = theme.fg } })
        table.insert(items, { Text = string.rep(" ", gap) })
      end
      for _, segment in ipairs(right) do
        table.insert(items, { Background = { Color = segment.bg } })
        table.insert(items, { Foreground = { Color = segment.fg } })
        table.insert(items, { Text = segment.text })
      end
    end

    local function build_powerline(segments, glyphs, cols, theme)
      local sep = glyphs.sep or ""
      local items = {}
      local used = 0
      local left, right, right_width = split_right_segments(segments, cols)
      local left_cols = math.max(0, cols - right_width)

      for idx, seg in ipairs(left) do
        local text = seg.text or ""
        local seg_width = wezterm.column_width(text) + 2
        local next_bg = nil
        if idx < #left then
          next_bg = left[idx + 1].bg
        end

        if used + seg_width > left_cols then
          local remaining = left_cols - used
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

        if next_bg and sep ~= "" and used < left_cols then
          local sep_w = wezterm.column_width(sep)
          if used + sep_w > left_cols then
            break
          end
          table.insert(items, { Background = { Color = seg.bg } })
          table.insert(items, { Foreground = { Color = next_bg } })
          table.insert(items, { Text = sep })
          used = used + sep_w
        end
      end

      append_right(items, right, math.max(0, left_cols - used), theme)

      local reset_item = format_reset_item()
      if reset_item then
        table.insert(items, reset_item)
      end
      return wezterm.format(items)
    end

    local function build_plain_line(segments, cols, theme)
      local left, right, right_width = split_right_segments(segments, cols)
      local parts = {}
      for _, segment in ipairs(left) do
        table.insert(parts, segment.text)
      end
      local left_cols = math.max(0, cols - right_width)
      local text = truncate_to_width(table.concat(parts, "  "), left_cols)
      local items = {
        { Background = { Color = theme.bg } },
        { Foreground = { Color = theme.fg } },
        { Text = text },
      }
      append_right(items, right, math.max(0, left_cols - wezterm.column_width(text)), theme)
      local reset_item = format_reset_item()
      if reset_item then
        table.insert(items, reset_item)
      end
      return wezterm.format(items)
    end

  return {
    format_reset_item = format_reset_item,
    format_int = format_int,
    substitute_home = substitute_home,
    truncate_to_width = truncate_to_width,
    shorten_path = shorten_path,
    segments_width = segments_width,
    build_powerline = build_powerline,
    build_plain_line = build_plain_line,
  }

end
return M
