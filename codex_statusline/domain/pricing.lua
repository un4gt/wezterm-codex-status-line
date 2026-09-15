local M = {}
local prices = require("codex_statusline.domain.prices")
local aliases = { astra = "gpt-6-astra", sol = "gpt-5.6-sol", terra = "gpt-5.6-terra", luna = "gpt-5.6-luna" }

local function finite(value)
  return type(value) == "number" and value == value and math.abs(value) ~= math.huge
end

function M.valid_model(model)
  return type(model) == "string" and #model >= 1 and #model <= 128
    and model:match("^[a-z0-9][a-z0-9._:/%-]*$") ~= nil
end

function M.valid_price(price)
  if type(price) ~= "table" then return false end
  for key in pairs(price) do
    if key ~= "input" and key ~= "cached_input" and key ~= "output" then return false end
  end
  for _, key in ipairs({ "input", "cached_input", "output" }) do
    if not finite(price[key]) or price[key] < 0 or price[key] > 1000000 then return false end
  end
  return true
end

function M.resolve(model, pricing)
  if type(model) ~= "string" then return nil end
  local full = model:match("^%s*(.-)%s*$"):lower()
  local bare = full:match("([^/]*)$")
  local base = bare:gsub("%-%d%d%d%d%-%d%d%-%d%d$", "")
  local candidates = { full, bare, base, aliases[base] or base }
  local custom = type(pricing) == "table" and pricing.models or {}
  for _, source in ipairs({ type(custom) == "table" and custom or {}, prices }) do
    for _, key in ipairs(candidates) do
      if M.valid_price(source[key]) then return source[key] end
    end
  end
  return nil
end

local function token_count(value)
  return finite(value) and math.max(0, value) or nil
end

function M.usage_counts(usage)
  local cached = token_count(usage.cached) or 0
  local input = token_count(usage.input_raw)
  if not input and token_count(usage.input) then input = token_count(usage.input) + cached end
  return { input = input, cached = input and math.min(cached, input) or cached, output = token_count(usage.output) }
end

function M.cache_rate(usage)
  local counts = M.usage_counts(usage)
  if not counts.input or counts.input == 0 then return nil end
  return math.floor(counts.cached / counts.input * 1000 + 0.5) / 10
end

function M.estimate(model, usage, pricing)
  local price = M.resolve(model, pricing)
  local counts = M.usage_counts(usage)
  if not price or counts.input == nil or counts.output == nil then return nil end
  local cost = ((counts.input - counts.cached) * price.input + counts.cached * price.cached_input
    + counts.output * price.output) / 1000000
  return finite(cost) and cost or nil
end

function M.cost_text(cost)
  if cost == nil then return "Cost —" end
  if cost > 0 and cost < 0.01 then return "Cost <$0.01" end
  return string.format("Cost ~$%.2f", math.floor(cost * 100 + 0.5 + 1e-9) / 100)
end

return M
