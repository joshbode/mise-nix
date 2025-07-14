local utils = require("utils")

---@type Strings
local strings = require("vfox.strings")

function PLUGIN:MisePath(ctx)
  local options = ctx.options
  if options == false then
    return {}
  elseif options == true then
    options = {}
  end

  local path = os.getenv("MISE_NIX_PATH")

  if path ~= nil then
    return strings.split(path, ":")
  end

  ---@cast options Options
  local result = utils.load_env(options)
  if result == nil then
    return {}
  end

  for key, info in pairs(result.env.variables) do
    if key == "PATH" then
      return strings.split(info.value, ":")
    end
  end

  return {}
end
