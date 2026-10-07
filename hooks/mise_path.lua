local utils = require("utils")

---@type Strings
local strings = require("strings")

function PLUGIN.MisePath(_, ctx)
  local options = ctx.options
  if options == false then
    return {}
  elseif options == true then
    options = {}
  end

  -- the environment is cached by the env hook, which runs first
  ---@cast options Options
  local result = utils.load_env(options, ctx.config_root)
  if result == nil or result.variables.PATH == nil then
    return {}
  end

  return strings.split(result.variables.PATH, ":")
end
