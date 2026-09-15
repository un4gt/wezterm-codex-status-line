local M = {}
local KEY = "codex_statusline_state"

function M.load(wezterm)
  local state = wezterm.GLOBAL[KEY]
  -- Recent WezTerm versions return shared userdata, not ordinary Lua tables.
  -- Take a structured snapshot so nested arrays and state updates behave alike
  -- on both the shared-object API and older copy-on-read versions.
  if type(state) == "userdata" then
    state = wezterm.json_parse(wezterm.json_encode(state))
  end
  if type(state) ~= "table" then state = {} end
  if state.schema ~= 8 then
    local previous = state
    state = { schema = 8, bindings = {}, panes = previous.panes or {}, tabs = {},
      close_requests = {}, next_generation = 0 }
    for _, old in pairs(previous.tabs or {}) do
      local owner = old.main_pane_id and tostring(old.main_pane_id)
      local status = old.status_pane_id and tostring(old.status_pane_id)
      if owner and status and owner ~= status then
        state.bindings[owner] = { owner_id = owner, status_id = status, legacy = true }
      end
    end
    -- Preserve exact targets already sent to the asynchronous CLI.
    for id, at in pairs(previous.pane_close_requests or {}) do
      state.close_requests[tostring(id)] = { started_at = (tonumber(at) or 0) * 1000,
        last_request_at = (tonumber(at) or 0) * 1000, reason = "legacy-pending" }
    end
    wezterm.GLOBAL[KEY] = state
  end
  return state
end

function M.save(wezterm, state)
  wezterm.GLOBAL[KEY] = state
end

function M.generation(state, now)
  state.next_generation = state.next_generation + 1
  return string.format("%.0f:%d", now, state.next_generation)
end

function M.binding(state, owner)
  local key = tostring(owner)
  local binding = state.bindings[key]
  if not binding then
    binding = { owner_id = key }
    state.bindings[key] = binding
  end
  state.panes[key] = state.panes[key] or { offset = 0 }
  return binding, state.panes[key]
end

function M.forget_status(binding)
  binding.status_id = nil
  binding.status_generation = nil
  binding.legacy = nil
  binding.created_here = nil
  binding.render = nil
end

return M
