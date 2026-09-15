local M = {}

function M.signature(infos)
  local rows = {}
  for _, info in ipairs(infos) do
    if not info.pane or not info.pane.pane_id then return nil end
    local values = { tostring(info.pane:pane_id()) }
    for _, key in ipairs({ "left", "top", "width", "height" }) do
      if type(info[key]) ~= "number" then return nil end
      values[#values + 1] = tostring(info[key])
    end
    values[#values + 1] = tostring(info.is_zoomed == true)
    rows[#rows + 1] = table.concat(values, ":")
  end
  table.sort(rows)
  return table.concat(rows, "|")
end

function M.observe(state, signature, now, delay)
  if not signature then
    state.signature = nil
    return false
  end
  if state.signature ~= signature or now < (state.last_sample_at or now) then
    state.signature = signature
    state.changed_at = now
    state.samples = 0
    state.last_sample_at = nil
  end
  if state.last_sample_at ~= now then
    state.samples = (state.samples or 0) + 1
    state.last_sample_at = now
  end
  return state.samples >= 2 and now - state.changed_at >= delay
end

function M.aligned(owner, status)
  return owner and status and owner.left == status.left and owner.width == status.width
    and status.top == owner.top + owner.height + 1
end

function M.can_create(owner, rows)
  return owner and owner.width >= 1 and owner.height >= rows + 1 + 5
end

function M.can_repair(infos, owner_id, status_id)
  if #infos ~= 2 then return false end
  local ids = {}
  for _, info in ipairs(infos) do ids[tostring(info.pane:pane_id())] = true end
  return ids[tostring(owner_id)] == true and ids[tostring(status_id)] == true
end

return M
