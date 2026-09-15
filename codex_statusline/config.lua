local core = require("codex_statusline_core")
local util = require("codex_statusline.util")
local M = {}

function M.new(wezterm, adapter)
  local trim = util.trim
  local path_join = util.path_join
  local read_file = util.read_file
  local shallow_merge = util.shallow_merge
  local resolved_module_path = util.resolved_module_path
  local safe_json_parse = adapter.safe_json_parse
  local CONFIG_CACHE = {
    at = 0,
    loaded = false,
    values = nil,
  }

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
      service_tier = trim(values.service_tier),
    }
    CONFIG_CACHE.at = now
    CONFIG_CACHE.loaded = true

    return CONFIG_CACHE.values
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
      resume_fallback_enabled = true,
      resume_fallback_max_age_seconds = 30,
      resume_fallback_clock_skew_seconds = 5,
      resume_fallback_scan_ttl_seconds = 2,
      cache_ttl_seconds = 5,
      full_scan_ttl_seconds = 300,
      tail_ttl_seconds = 1,
      open_fail_clear_seconds = 30,
      initial_seek_bytes = 131072,
      activity_seek_bytes = 65536,
      activity_max_seek_bytes = 8388608,
      max_meta_lines = 40,
      max_tail_lines = 200,
    },
    bottom_pane = {
      enabled = true,
      rows = 1,
      layout_debounce_ms = 1000,
      close_grace_seconds = 2,
      prevent_focus = true,
    },
    render = {
      powerline = true,
      plain_fallback = true,
      model_display = "name", -- "name" | "icon_name" | "icon"
      segment_order = {
        "label",
        "model",
        "reasoning",
        "activity",
        "provider",
        "personality",
        "service_tier",
        "cwd",
        "project",
        "git",
        "permissions",
        "approval",
        "context",
        "context_used",
        "context_window",
        "used_tokens",
        "cache_rate",
        "cost",
        "input_tokens",
        "cached_tokens",
        "output_tokens",
        "reasoning_tokens",
        "thread_id",
        "task_progress",
        "codex_version",
        "icon",
      },
      disabled_segments = {
        "personality",
        "service_tier",
        "project",
        "permissions",
        "approval",
        "context_used",
        "context_window",
        "input_tokens",
        "cached_tokens",
        "output_tokens",
        "reasoning_tokens",
        "thread_id",
        "task_progress",
        "codex_version",
      },
    },
    activity = {
      labels = {
        plan = "PLAN",
        review = "REVIEW",
        goal_active = "GOAL",
        goal_paused = "GOAL PAUSED",
        goal_blocked = "GOAL BLOCKED",
        goal_usage_limited = "GOAL LIMITED",
        goal_budget_limited = "GOAL BUDGET",
        goal_complete = "GOAL DONE",
      },
    },
    icon = {
      text = "",
    },
    pricing = { models = {} },
    theme = {
      bg = "#11151a",
      fg = "#d5dbe3",
      dim = "#82909f",
      segments = {
        label = { bg = "#1d4ed8", fg = "#ffffff" },
        model = { bg = "#11151a", fg = "#d5dbe3" },
        reasoning = { bg = "#11151a", fg = "#fbbf24" },
        activity = { bg = "#6d28d9", fg = "#ffffff" },
        provider = { bg = "#11151a", fg = "#aab2bf" },
        personality = { bg = "#11151a", fg = "#c4b5fd" },
        service_tier = { bg = "#11151a", fg = "#f0abfc" },
        cwd = { bg = "#11151a", fg = "#d5dbe3" },
        project = { bg = "#11151a", fg = "#93c5fd" },
        git = { bg = "#11151a", fg = "#4ade80" },
        permissions = { bg = "#11151a", fg = "#fca5a5" },
        approval = { bg = "#11151a", fg = "#fdba74" },
        context = { bg = "#11151a", fg = "#7dd3fc" },
        context_used = { bg = "#11151a", fg = "#67e8f9" },
        context_window = { bg = "#11151a", fg = "#a5b4fc" },
        used_tokens = { bg = "#11151a", fg = "#d5dbe3" },
        cache_rate = { bg = "#11151a", fg = "#67e8f9" },
        cost = { bg = "#11151a", fg = "#fbbf24" },
        input_tokens = { bg = "#11151a", fg = "#86efac" },
        cached_tokens = { bg = "#11151a", fg = "#94a3b8" },
        output_tokens = { bg = "#11151a", fg = "#fde68a" },
        reasoning_tokens = { bg = "#11151a", fg = "#f0abfc" },
        thread_id = { bg = "#11151a", fg = "#94a3b8" },
        task_progress = { bg = "#11151a", fg = "#5eead4" },
        codex_version = { bg = "#11151a", fg = "#aab2bf" },
        icon = { bg = "#11151a", fg = "#58d6c5" },
        -- Backward-compatible theme keys for existing setup() overrides.
        thinking = { bg = "#11151a", fg = "#fbbf24" },
        tokens = { bg = "#11151a", fg = "#d5dbe3" },
      },
      glyphs = {
        sep = "",
        branch = "",
        folder = "",
      },
    },
  }

  local function managed_config_path()
    local module_path = resolved_module_path()
    if not module_path then
      return nil
    end
    local directory = module_path:match("^(.*)[/\\][^/\\]+$")
    if not directory then
      return nil
    end
    return path_join({ directory, "codex_statusline_config.json" })
  end

  local function load_managed_config()
    if type(io) ~= "table" or type(io.open) ~= "function" then
      return nil
    end
    local path = managed_config_path()
    if not path then
      return nil
    end
    local handle = io.open(path, "r")
    if not handle then
      return nil
    end
    local content = handle:read("*a")
    handle:close()
    local value = safe_json_parse(content)
    if type(value) ~= "table" or tonumber(value.schema) ~= 1 or type(value.options) ~= "table" then
      wezterm.log_error("codex_statusline: ignoring invalid managed config " .. tostring(path))
      return nil
    end
    return value.options
  end

  local function resolve(user_opts)
    local opts = shallow_merge(DEFAULTS, load_managed_config())
    opts = shallow_merge(opts, user_opts)

    for _, name in ipairs({
      "log",
      "compat",
      "codex_config",
      "title_bridge",
      "git",
      "user_vars",
      "process_match",
      "sessions",
      "bottom_pane",
      "activity",
      "icon",
      "pricing",
      "render",
      "theme",
    }) do
      if type(opts[name]) ~= "table" then
        error("invalid option table: " .. name)
      end
    end
    if type(opts.theme.segments) ~= "table" or type(opts.theme.glyphs) ~= "table" then
      error("invalid theme configuration")
    end
    local model_display = opts.render.model_display
    if model_display ~= "name" and model_display ~= "icon_name" and model_display ~= "icon" then
      error("render.model_display must be name, icon_name, or icon")
    end
    local pricing = require("codex_statusline.domain.pricing")
    if type(opts.pricing.models) ~= "table" then error("pricing.models must be a table") end
    local price_count = 0
    for model, price in pairs(opts.pricing.models) do
      price_count = price_count + 1
      if not pricing.valid_model(model) or not pricing.valid_price(price) then
        error("invalid pricing.models entry: " .. tostring(model))
      end
    end
    if price_count > 64 then error("pricing.models supports at most 64 entries") end

    local delay = opts.bottom_pane.layout_debounce_ms
    if type(delay) ~= "number" or delay % 1 ~= 0 or delay < 250 or delay > 5000 then
      error("bottom_pane.layout_debounce_ms must be an integer between 250 and 5000")
    end
    if opts.bottom_pane.rows ~= 1 and opts.bottom_pane.rows ~= 2 then
      error("bottom_pane.rows must be 1 or 2")
    end
    return opts
  end

  return {
    resolve = resolve,
    load_codex_config = load_codex_config,
    codex_home_for_opts = codex_home_for_opts,
    bridge_root_for_opts = bridge_root_for_opts,
  }

end

return M
