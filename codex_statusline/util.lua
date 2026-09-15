local core = require("codex_statusline_core")

local function base64_encode(value)
  local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  local out = {}
  for index = 1, #value, 3 do
    local a, b, c = value:byte(index, index + 2)
    local n = a * 65536 + (b or 0) * 256 + (c or 0)
    local function digit(shift)
      local offset = math.floor(n / shift) % 64 + 1
      return alphabet:sub(offset, offset)
    end
    out[#out + 1] = digit(262144) .. digit(4096)
      .. (b and digit(64) or "=") .. (c and digit(1) or "=")
  end
  return table.concat(out)
end

local function id_key(id)
  if id == nil then
    return nil
  end
  return tostring(id)
end

local function resolved_module_path()
  if type(package) ~= "table" or type(package.searchpath) ~= "function" or type(package.path) ~= "string" then
    return nil
  end
  local ok, path = pcall(package.searchpath, "codex_statusline", package.path)
  if ok and type(path) == "string" then
    return path
  end
  return nil
end

local function window_id_key(window)
  if not window then
    return nil
  end
  if window.window_id then
    local ok, val = pcall(window.window_id, window)
    if ok and val ~= nil then
      return tostring(val)
    end
  end
  if window.mux_window then
    local mw = window:mux_window()
    if mw and mw.window_id then
      local ok, val = pcall(mw.window_id, mw)
      if ok and val ~= nil then
        return tostring(val)
      end
    end
  end
  return nil
end

local function tab_state_key(window, tab_id)
  local wid = window_id_key(window)
  if wid then
    return wid .. ":" .. tostring(tab_id)
  end
  return tostring(tab_id)
end

local function trim(value)
  if value == nil then
    return nil
  end
  local str = tostring(value)
  str = str:gsub("^%s+", ""):gsub("%s+$", "")
  if str == "" then
    return nil
  end
  return str
end

local function first_user_var(user_vars, names)
  for _, name in ipairs(names) do
    local value = trim(user_vars[name])
    if value then
      return value
    end
  end
  return nil
end

local function parse_boolish(value)
  local v = trim(value)
  if not v then
    return nil
  end
  v = v:lower()
  if v == "1" or v == "true" or v == "yes" or v == "on" then
    return true
  end
  if v == "0" or v == "false" or v == "no" or v == "off" then
    return false
  end
  return true
end

local function is_sequence(value)
  if type(value) ~= "table" then
    return false
  end
  local count = 0
  for key in pairs(value) do
    if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
      return false
    end
    count = count + 1
  end
  return count > 0 and count == #value
end

local function clone_table(value)
  if type(value) ~= "table" then
    return value
  end
  local result = {}
  for key, item in pairs(value) do
    result[key] = clone_table(item)
  end
  return result
end

local function shallow_merge(defaults, overrides)
  if type(defaults) ~= "table" then
    return clone_table(overrides ~= nil and overrides or defaults)
  end
  if type(overrides) == "table" and (is_sequence(defaults) or is_sequence(overrides)) then
    return clone_table(overrides)
  end

  local out = clone_table(defaults)
  if type(overrides) == "table" then
    for key, value in pairs(overrides) do
      if type(value) == "table" and type(out[key]) == "table" then
        out[key] = shallow_merge(out[key], value)
      else
        out[key] = clone_table(value)
      end
    end
  end
  return out
end

local function is_windows()
  return package.config:sub(1, 1) == "\\"
end

local function normalize_path(path)
  return core.normalize_path(path, is_windows())
end

local function path_join(parts)
  local sep = package.config:sub(1, 1)
  local cleaned = {}
  for _, part in ipairs(parts) do
    local p = trim(part)
    if p then
      table.insert(cleaned, p)
    end
  end
  return table.concat(cleaned, sep)
end

local function normalize_session_meta_payload(payload)
  if type(payload) ~= "table" then
    return nil
  end

  if type(payload.meta) == "table" then
    local meta = payload.meta
    if payload.git ~= nil and meta.git == nil then
      meta.git = payload.git
    end
    return meta
  end

  return payload
end

local function read_file(path)
  local fh = io.open(path, "r")
  if not fh then
    return nil
  end
  local ok, content = pcall(fh.read, fh, "*a")
  fh:close()
  if not ok then
    return nil
  end
  return content
end

local function path_is_within(path, root)
  local child = normalize_path(path)
  local parent = normalize_path(root)
  if not child or not parent then
    return false
  end
  if child == parent then
    return true
  end
  local sep = is_windows() and "\\" or "/"
  return child:sub(1, #parent + 1) == parent .. sep
end

local function to_number(value)
  if value == nil then
    return nil
  end
  if type(value) == "number" then
    return value
  end
  if type(value) == "string" then
    local stripped = value:gsub(",", "")
    return tonumber(stripped)
  end
  return nil
end

return {
  base64_encode = base64_encode,
  id_key = id_key,
  resolved_module_path = resolved_module_path,
  window_id_key = window_id_key,
  tab_state_key = tab_state_key,
  trim = trim,
  first_user_var = first_user_var,
  parse_boolish = parse_boolish,
  clone_table = clone_table,
  shallow_merge = shallow_merge,
  is_windows = is_windows,
  normalize_path = normalize_path,
  path_join = path_join,
  normalize_session_meta_payload = normalize_session_meta_payload,
  read_file = read_file,
  path_is_within = path_is_within,
  to_number = to_number,
}
