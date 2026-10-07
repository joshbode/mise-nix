local utils = require("utils")

---@dictionary "ignore" | "keep"
local VARS = {
  HOME = "ignore",
  PATH = "ignore", -- handled in path hook
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
  local result = utils.load_env(options, ctx.config_root)
  if result == nil then
    return {}
  end

  ---@type { key: string, value: string}[]
  local env = {}

  for key, value in pairs(result.variables) do
    ---@diagnostic disable-next-line: unnecessary-if
    if VARS[key] ~= "ignore" then
      env[#env + 1] = { key = key, value = value }
    end
  end

  return {
    cacheable = true,
    watch_files = result.watch_files,
    env = env,
  }
end
