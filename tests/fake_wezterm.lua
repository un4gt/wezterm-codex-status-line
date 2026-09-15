local M = {}
local real_time = os.time
local real_getenv = os.getenv
local function check(value, message) assert(value, message) end

function M.new(options)
  options = options or {}
  local h = { now = 1000, panes = {}, tabs = {}, callbacks = {}, logs = {},
    close_commands = {}, splits = {}, next_id = 1, json = {}, encoded = {}, events = {} }
  local w = { GLOBAL = {}, mux = {}, procinfo = {}, url = {}, action = {}, time = {},
    home_dir = "C:/Users/test", executable_dir = "C:/WezTerm", version = "test" }
  h.wezterm = w
  h.socket = "isolated-test-socket"
  os.getenv = function(key)
    if key == "WEZTERM_UNIX_SOCKET" then return h.socket end
    return real_getenv(key)
  end
  function w.on(name, fn)
    h.callbacks[name] = fn
    h.events[name] = (h.events[name] or 0) + 1
  end
  function w.log_info(s) h.logs[#h.logs + 1] = s end
  function w.log_error(s) h.logs[#h.logs + 1] = "ERROR " .. s end
  function w.column_width(s) return #s end
  function w.format(items)
    local out = {}
    for _, item in ipairs(items) do if type(item) == "table" and item.Text then out[#out + 1] = item.Text end end
    return table.concat(out)
  end
  function w.json_encode(value)
    local key = "fixture-json-" .. tostring(#h.json + 1)
    h.json[#h.json + 1] = key
    h.json[key] = value
    h.encoded[require("codex_statusline.util").base64_encode(key)] = key
    return key
  end
  function w.json_parse(s) if h.json[s] then return h.json[s] end; error("unexpected JSON") end
  function w.time.now()
    return { format = function() return tostring(h.now) end }
  end
  function w.url.parse(s) return { file_path = s } end
  function w.mux.get_pane(id)
    if (h.lookup_errors or 0) > 0 then h.lookup_errors = h.lookup_errors - 1; error("temporary lookup failure") end
    if h.missing_raises and not h.panes[id] then error("pane not found") end
    return h.panes[id]
  end
  function w.procinfo.get_info_for_pid(id)
    if id == 900 then return { pid = 900, ppid = 0, executable = "wezterm-gui.exe", argv = {}, children = {} } end
  end
  function w.background_child_process(args)
    if h.fail_close then error("close unavailable") end
    h.close_commands[#h.close_commands + 1] = args
  end
  local window = { id = 7, font_size = 12 }
  h.window = window
  function window:window_id() return self.id end
  function window:active_tab() return h.active_tab end
  function window:mux_window() return self end
  function window:tabs() return h.tabs end
  function window:effective_config() return { font_size = self.font_size } end

  local function place(node, left, top, width, height, out, tab)
    if not node then return end
    if node.pane then
      local pane = node.pane
      pane.dimensions = { cols = width, viewport_rows = height }
      pane._tab = tab
      out[#out + 1] = { pane = pane, left = left, top = top, width = width, height = height,
        is_active = tab.focused == pane, is_zoomed = tab.zoomed and tab.focused == pane or false }
    elseif node.axis == "Right" then
      local first = math.floor((width - 1) * node.ratio)
      place(node.a, left, top, first, height, out, tab)
      place(node.b, left + first + 1, top, width - first - 1, height, out, tab)
    else
      local first = math.floor((height - 1) * node.ratio + 0.000001)
      place(node.a, left, top, width, first, out, tab)
      place(node.b, left, top + first + 1, width, height - first - 1, out, tab)
    end
  end
  local function replace(node, pane, replacement)
    if not node then return nil end
    if node.pane == pane then return replacement end
    if node.a then
      node.a = replace(node.a, pane, replacement)
      node.b = replace(node.b, pane, replacement)
      if not node.a then return node.b end
      if not node.b then return node.a end
    end
    return node
  end
  local function new_pane()
    local pane = { id = h.next_id, mode = "shell", pid = 100 + h.next_id,
      title = "pwsh.exe", user_vars = {}, inject_count = 0, cwd = "E:/src/app" }
    h.next_id = h.next_id + 1
    h.panes[pane.id] = pane
    function pane:pane_id() return self.id end
    function pane:get_title() return self.title end
    function pane:get_user_vars() return self.user_vars end
    function pane:get_domain_name() return "local" end
    function pane:get_current_working_dir() return { file_path = self.cwd } end
    function pane:get_dimensions() return self.dimensions end
    function pane:tab() return self._tab end
    function pane:activate() self._tab.focused = self; self.activated = true end
    function pane:get_foreground_process_name()
      return self.mode == "codex" and "codex.exe" or "pwsh.exe"
    end
    function pane:get_foreground_process_info()
      if self.mode == "unknown" then error("process unavailable") end
      if self.mode == "codex" then
        return { pid = self.pid, ppid = 10, executable = "codex.exe", argv = { "codex" }, children = {} }
      end
      return { pid = 10, ppid = 900, executable = "pwsh.exe", argv = self.args or { "pwsh" }, children = {} }
    end
    function pane:inject_output(output)
      if h.fail_inject then error("injection failed") end
      local key, value = output:match("SetUserVar=([^=]+)=([^\x07]+)")
      if key then self.user_vars[key] = assert(h.encoded[value], "encoded OSC value") else
        self.last_output = output
        self.inject_count = self.inject_count + 1
      end
    end
    function pane:split(args) return h:split(self, args) end
    return pane
  end
  function h:add_tab(pane)
    pane = pane or new_pane()
    local tab = { id = #self.tabs + 1, width = 120, height = 40, root = { pane = pane }, focused = pane }
    function tab:tab_id() return self.id end
    function tab:window() return window end
    function tab:active_pane() return self.focused end
    function tab:panes_with_info()
      if h.fail_snapshot then error("snapshot failed") end
      local out = {}
      place(self.root, 0, 0, self.width, self.height, out, self)
      return out
    end
    self.tabs[#self.tabs + 1] = tab
    self.active_tab = self.active_tab or tab
    tab:panes_with_info()
    return tab, pane
  end
  function h:split(owner, args)
    args = args or { direction = "Right", size = 0.5 }
    if self.fail_split then error("split failed") end
    local tab = owner:tab()
    tab:panes_with_info()
    local pane = new_pane()
    pane.args = args.args
    local axis = args.direction or "Right"
    local available = axis == "Right" and owner.dimensions.cols or owner.dimensions.viewport_rows
    local requested = args.size or 0.5
    local second = requested < 1 and math.floor((available - 1) * requested) or requested
    local node = { a = { pane = owner }, b = { pane = pane }, axis = axis,
      ratio = (available - 1 - second) / (available - 1) }
    tab.root = replace(tab.root, owner, node)
    tab.focused = pane
    tab:panes_with_info()
    self.splits[#self.splits + 1] = { owner = owner.id, args = args, status = pane.id }
    if self.on_split then self.on_split(pane) end
    return pane
  end
  function h:remove(pane)
    local tab = pane:tab()
    tab.root = replace(tab.root, pane, nil)
    self.panes[pane.id] = nil
    local infos = tab:panes_with_info()
    if tab.focused == pane then tab.focused = infos[1] and infos[1].pane end
  end
  function h:move(pane)
    self:remove(pane)
    self.panes[pane.id] = pane
    return self:add_tab(pane)
  end
  function h:start(pane, pid)
    pane = pane or self.main
    pane.mode, pane.pid, pane.title = "codex", pid or pane.pid + 1, "codex | high | app"
  end
  function h:shell(pane)
    pane = pane or self.main
    pane.mode, pane.title = "shell", "pwsh.exe"
  end
  function h:tick(seconds)
    self.now = self.now + (seconds or 0.5)
    os.time = function() return self.now end
    self.callbacks["update-status"](self.window, self.active_tab:active_pane())
    os.time = real_time
  end
  function h:settle()
    for _ = 1, 5 do self:tick() end
  end
  function h:binding(pane)
    local state = self.wezterm.GLOBAL.codex_statusline_state
    return state and state.bindings[tostring((pane or self.main).id)]
  end
  function h:status(pane)
    local b = self:binding(pane)
    return b and b.status_id and self.panes[tonumber(b.status_id)]
  end
  function h:complete_close(index)
    local command = self.close_commands[index or #self.close_commands]
    check(command and command[3] == "--no-auto-start" and command[4] == "kill-pane" and command[5] == "--pane-id", "exact close command")
    local pane = self.panes[tonumber(command[6])]
    if pane then
      check(pane.user_vars.codex_statusline_owner ~= nil or pane.args ~= nil, "never close an ordinary pane")
      self:remove(pane)
    end
  end
  function h:reload()
    package.loaded.codex_statusline = nil
    require("codex_statusline").setup(self.options)
  end
  function h:assert_no_errors()
    for _, line in ipairs(self.logs) do check(not line:find("ERROR", 1, true), line) end
  end
  h.tab, h.main = h:add_tab()
  h.options = require("codex_statusline.util").shallow_merge({
    debug = true, log = { enabled = false }, codex_config = { enabled = false },
    git = { enabled = false }, sessions = { enabled = false },
    bottom_pane = { close_grace_seconds = 0 }, render = { powerline = false },
  }, options)
  package.loaded.wezterm = nil
  package.loaded.codex_statusline = nil
  package.preload.wezterm = function() return w end
  require("codex_statusline").setup(h.options)
  return h
end

return M
