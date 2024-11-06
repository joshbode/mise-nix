local json = require("json")
local strings = require("vfox.strings") ---@class Strings

local utils = require("utils")

---@dictionary "ignore" | "keep"
local VARS = {
  -- exported
  HOME = "ignore",
  TEMP = "ignore",
  TERM = "ignore",
  TMP = "ignore",
  TMPDIR = "ignore",
  TZ = "ignore",
}

---Load environment from handle
---@param handle file*?
---@return DevEnv?
local function get_env(handle)
  if handle ~= nil then
    local status, data = pcall(json.decode, handle:read("*a"))
    handle:close()
    return status and data or nil
  else
    return nil
  end
end

function PLUGIN:MiseEnv(ctx)
  local options = ctx.options
  if options == false then
    return {}
  elseif options == true then
    options = {}
  end
  ---@cast options Options

  if options.flake_lock == nil then
    options.flake_lock = "flake.lock"
  end

  local project_root = utils.find_project_root("flake.nix")
  if project_root == nil then
    utils.log("Unable to find flake")
    return {}
  end

  local flake_file = ("%s/%s"):format(project_root, "flake.nix")
  local lock_file = ("%s/%s"):format(project_root, options.flake_lock)

  if not utils.exists(lock_file) then
    utils.log("Lock file does not exist: %s", lock_file)
    return {}
  end

  local hash = utils.get_hash(flake_file, lock_file)
  if hash == nil then
    utils.log("Unable to hash flake files")
    return {}
  end

  local temp_dir = string.gsub(os.getenv("TMPDIR") or "/tmp", "/+$", "")
  local filename = ("%s/mise-nix-%s"):format(temp_dir, hash)

  local tag = ("%s:%s"):format(project_root, hash)

  -- check if already loaded
  if os.getenv("MISE_NIX") == tag then
    return {}
  end

  ---@type DevEnv?
  local env = nil

  if utils.exists(filename) then
    -- load from cache
    env = get_env(io.open(filename))
  end

  if env == nil then
    -- generate from nix and cache result
    local command = ([[
      set -o pipefail
      nix print-dev-env \
        --json --quiet --option warn-dirty false \
        --reference-lock-file %q |
        tee %q
    ]]):format(lock_file, filename)
    env = get_env(io.popen(command))

    if env == nil then
      utils.log("Unable to load environment")
      return {}
    end
  end

  ---@type { key: string, value: string}[]
  local exports = {
    { key = "MISE_NIX", value = tag },
  }

  for key, info in pairs(env.variables) do
    if VARS[key] == "ignore" then
      -- skip
    elseif info.type == "exported" then
      exports[#exports + 1] = { key = key, value = info.value }
    end
  end

  return exports
end
