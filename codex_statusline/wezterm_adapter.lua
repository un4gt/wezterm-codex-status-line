local util = require("codex_statusline.util")
local layout = require("codex_statusline.layout")
local M = {}
local MARKER = "codex_statusline_owner"

function M.new(wezterm)
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

    local function mux_pane_lookup(pane_id)
      local ok, pane_or_err = pcall(wezterm.mux.get_pane, tonumber(pane_id) or pane_id)
      if ok then
        if pane_or_err then
          return pane_or_err, "found"
        end
        return nil, "missing"
      end

      local message = tostring(pane_or_err)
      local lower = message:lower()
      if lower:find("not found", 1, true) or lower:find("no pane", 1, true) then
        return nil, "missing", message
      end
      return nil, "error", message
    end

  local function now_ms()
    if wezterm.time and wezterm.time.now then
      local ok, value = pcall(function() return tonumber(wezterm.time.now():format("%s%.3f")) end)
      if ok and value then return value * 1000 end
    end
    return os.time() * 1000
  end

  local function active_tab(window)
    local ok, tab = pcall(function() return window:active_tab() end)
    return ok and tab or nil
  end

  local function snapshot(tab)
    local ok, infos = pcall(tab.panes_with_info, tab)
    if not ok or type(infos) ~= "table" then return nil end
    local signature = layout.signature(infos)
    if not signature then return nil end
    local by_id, zoomed = {}, false
    for _, info in ipairs(infos) do
      by_id[tostring(info.pane:pane_id())] = info
      zoomed = zoomed or info.is_zoomed == true
    end
    return { tab = tab, id = tostring(tab:tab_id()), infos = infos,
      by_id = by_id, signature = signature, zoomed = zoomed }
  end

  local function window_tabs(window)
    local ok, tabs = pcall(function() return window:mux_window():tabs() end)
    if ok and type(tabs) == "table" then return tabs end
    local tab = active_tab(window)
    return tab and { tab } or {}
  end

  local function marker(pane)
    local ok, vars = pcall(pane.get_user_vars, pane)
    if not ok or type(vars) ~= "table" then return nil end
    local value = safe_json_parse(vars[MARKER])
    if type(value) ~= "table" or value.schema ~= 1
      or type(value.generation) ~= "string"
      or not tostring(value.owner_id):match("^%d+$")
      or tostring(value.status_id) ~= tostring(pane:pane_id())
      or tostring(value.owner_id) == tostring(value.status_id) then return nil end
    value.owner_id, value.status_id = tostring(value.owner_id), tostring(value.status_id)
    return value
  end

  local function mark(pane, owner_id, generation)
    local ok, err = pcall(function()
      local data = wezterm.json_encode({ schema = 1, owner_id = tostring(owner_id),
        status_id = tostring(pane:pane_id()), generation = generation })
      pane:inject_output("\x1b]1337;SetUserVar=" .. MARKER .. "="
        .. util.base64_encode(data) .. "\x07"
        .. "\x1b]2;codex-statusline\x07\x1b[?25l")
    end)
    return ok, err
  end

  local function legacy_placeholder(pane)
    local ok, info = pcall(pane.get_foreground_process_info, pane)
    if not ok or type(info) ~= "table" or type(info.argv) ~= "table" then return false end
    for _, arg in ipairs(info.argv) do
      if arg == "while($true){Start-Sleep -Seconds 3600}"
        or arg == "while true; do sleep 3600; done" then return true end
    end
    return false
  end

  local function create(window, tab, owner, rows, generation)
    local focused = tab:active_pane()
    local args = util.is_windows()
      and { "powershell", "-NoLogo", "-NoProfile", "-Command", "while($true){Start-Sleep -Seconds 3600}" }
      or { "sh", "-lc", "while true; do sleep 3600; done" }
    local ok, pane = pcall(owner.split, owner, {
      direction = "Bottom", top_level = false, size = rows, args = args,
      set_environment_variables = { CODEX_STATUSLINE_OWNER = tostring(owner:pane_id()),
        CODEX_STATUSLINE_GENERATION = generation },
    })
    if not ok or not pane then return nil, tostring(pane) end
    -- Restore only focus changed by our split; never undo a user's subsequent switch.
    pcall(function()
      local current_tab = active_tab(window)
      if current_tab and current_tab:tab_id() == tab:tab_id() then
        local current = tab:active_pane()
        if focused and current and current:pane_id() == pane:pane_id() then focused:activate() end
      end
    end)
    local marked, err = mark(pane, owner:pane_id(), generation)
    return pane, marked and nil or tostring(err), marked
  end

  local function close(pane_id)
    -- The GUI sets this to its own mux socket; never fall back to another GUI.
    if not util.trim(os.getenv("WEZTERM_UNIX_SOCKET")) then
      return false, "current GUI mux socket is unavailable"
    end
    local executable = util.is_windows() and "wezterm.exe" or "wezterm"
    if util.trim(wezterm.executable_dir) then
      executable = util.path_join({ wezterm.executable_dir, executable })
    end
    return pcall(wezterm.background_child_process,
      { executable, "cli", "--no-auto-start", "kill-pane", "--pane-id", tostring(pane_id) })
  end

  local function location(pane)
    local ok, tab_id, window_id = pcall(function()
      local tab = pane:tab()
      return tostring(tab:tab_id()), tostring(tab:window():window_id())
    end)
    if ok then return tab_id, window_id end
    return nil
  end

  return {
    now_ms = now_ms,
    active_tab = active_tab,
    snapshot = snapshot,
    window_tabs = window_tabs,
    marker = marker,
    mark = mark,
    legacy_placeholder = legacy_placeholder,
    create = create,
    close = close,
    location = location,
    safe_json_parse = safe_json_parse,
    pane_cwd_file_path = pane_cwd_file_path,
    pane_dimensions = pane_dimensions,
    mux_pane_lookup = mux_pane_lookup,
  }

end

return M
