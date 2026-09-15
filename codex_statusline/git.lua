local core = require("codex_statusline_core")
local util = require("codex_statusline.util")
local M = {}

function M.new(wezterm)
  local trim = util.trim
  local normalize_path = util.normalize_path
  local GIT_INFO_CACHE = {}
  local function git_info_for_cwd(opts, cwd, fallback)
    local fallback_branch = trim(fallback)
    local fallback_info = { branch = fallback_branch, root = nil }
    if not opts.git or not opts.git.enabled or not wezterm.run_child_process then
      return fallback_info
    end

    local normalized_cwd = normalize_path(cwd)
    if not normalized_cwd then
      return fallback_info
    end

    local ttl = tonumber(opts.git.cache_ttl_seconds) or 5
    ttl = math.max(0, ttl)
    local now = os.time()
    local cached = GIT_INFO_CACHE[normalized_cwd]
    if cached and (now - cached.at) < ttl then
      if cached.resolved then
        return { branch = cached.branch, root = cached.root }
      end
      return fallback_info
    end

    local ok, success, stdout = pcall(wezterm.run_child_process, {
      "git",
      "-C",
      normalized_cwd,
      "rev-parse",
      "--show-toplevel",
      "--abbrev-ref",
      "HEAD",
    })
    local resolved = ok and success == true
    local root = nil
    local branch = nil
    if resolved then
      root, branch = tostring(stdout or ""):match("^([^\r\n]+)[\r\n]+([^\r\n]+)")
      root = trim(root)
      branch = trim(branch)
    end
    GIT_INFO_CACHE[normalized_cwd] = {
      at = now,
      resolved = resolved,
      branch = branch,
      root = root,
    }
    if resolved then
      return { branch = branch, root = root }
    end
    return fallback_info
  end

  local function git_branch_for_cwd(opts, cwd, fallback)
    return git_info_for_cwd(opts, cwd, fallback).branch
  end

  return {
    git_info_for_cwd = git_info_for_cwd,
    git_branch_for_cwd = git_branch_for_cwd,
  }

end

return M
