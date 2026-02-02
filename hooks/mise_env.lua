local utils = require("utils")

---@dictionary "ignore" | "keep"
local VARS = {
  HOME = "ignore",
  SHELL = "ignore",
  TERM = "ignore",
  TMPDIR = "ignore",
  TZ = "ignore",
}

function PLUGIN.MiseEnv(_, ctx)
  local options = ctx.options
  if options == false then
    return {}
  elseif options == true then
    options = {}
  end

  ---@cast options Options
  local result = utils.load_env(options)
  if result == nil then
    return {}
  end

  ---@type { key: string, value: string}[]
  local env = {}

  for key, info in pairs(result.env.variables) do
    ---@diagnostic disable-next-line: unnecessary-if
    if VARS[key] == "ignore" then
      -- skip
    elseif key == "PATH" then
      -- cache for path handler
      env[#env + 1] = { key = "MISE_NIX_PATH", value = info.value }
    elseif info.type == "exported" then
      env[#env + 1] = { key = key, value = info.value }
    end
  end

  return {
    cacheable = true,
    watch_files = { result.lock_file },
    env = env,
  }
end
