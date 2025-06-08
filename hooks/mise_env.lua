local utils = require("utils")

---@dictionary "ignore" | "keep"
local VARS = {
  PATH = "ignore", -- handled in path hook
  HOME = "ignore",
  SHELL = "ignore",
  TERM = "ignore",
  TMPDIR = "ignore",
  TZ = "ignore",
}

function PLUGIN:MiseEnv(ctx)
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
  local exports = {
    { key = "MISE_NIX", value = result.tag },
  }

  for key, info in pairs(result.env.variables) do
    ---@diagnostic disable-next-line: unnecessary-if
    if VARS[key] == "ignore" then
      -- skip
    elseif info.type == "exported" then
      exports[#exports + 1] = { key = key, value = info.value }
    end
  end

  return exports
end
