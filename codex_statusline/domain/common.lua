local M = {}

local function trim(value)
  if value == nil then
    return nil
  end
  local text = tostring(value):gsub("^%s+", ""):gsub("%s+$", "")
  if text == "" then
    return nil
  end
  return text
end

local function to_number(value)
  if type(value) == "number" then
    return value
  end
  if type(value) == "string" then
    local normalized = value:gsub(",", "")
    return tonumber(normalized)
  end
  return nil
end

return {
  trim = trim,
  to_number = to_number,
}
