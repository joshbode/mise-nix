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
  -- bash vars
  BASH = "ignore",
  HOSTTYPE = "ignore",
  IFS = "ignore",
  LINENO = "ignore",
  MACHTYPE = "ignore",
  OPTARG = "ignore",
  OPTERR = "ignore",
  OPTIND = "ignore",
  OSTYPE = "ignore",
  PS4 = "ignore",
  SHELL = "ignore",
}

---@param project_root string
---@param variables string[]
---@param functions string[]
---@return string
local function make_unload_hook(project_root, variables, functions)
  local shell = os.getenv("MISE_SHELL")

  local lines = {} ---@type string[]
  table.insert(lines, "_unload_mise_nix() {")
  table.insert(lines, ("  local PROJECT_ROOT=%q"):format(project_root))
  table.insert(lines, '  if [[ "${PWD#${PROJECT_ROOT}}" == "${PWD}" ]]; then')
  for _, name in ipairs(variables) do
    table.insert(lines, ("    unset %q"):format(name))
  end
  for _, name in ipairs(functions) do
    table.insert(lines, ("    unset -f %q"):format(name))
  end
  if shell == "zsh" then
    table.insert(lines, "    add-zsh-hook -D chpwd _unload_mise_nix")
  elseif shell == "bash" then
    table.insert(lines, "    PROMPT_COMMAND=${PROMPT_COMMAND%;_unload_mise_nix}")
  end
  table.insert(lines, "  fi")
  table.insert(lines, "}")
  if shell == "zsh" then
    table.insert(lines, "add-zsh-hook chpwd _unload_mise_nix")
  elseif shell == "bash" then
    table.insert(lines,
      '  if [[ "${PROMPT_COMMAND%;_unload_mise_nix}" == "${PROMPT_COMMAND}" ]]; then')
    table.insert(lines, '    PROMPT_COMMAND="${PROMPT_COMMAND};_unload_mise_nix"')
    table.insert(lines, '  fi')
  end
  return strings.join(lines, "\n")
end

function PLUGIN:MiseEnv(ctx)
  if ctx.options == false then
    return {}
  end

  ---@type Options
  local options = ctx.options == true and {} or ctx.options

  local project_root = utils.find_project_root("flake.nix")
  if project_root == nil then
    utils.log("Unable to find flake")
    return {}
  end

  local lock_file = options.flake_lock or ("%s/%s"):format(project_root, "flake.lock")
  local hash = utils.get_hash(
    ("%s/%s"):format(project_root, "flake.nix"),
    lock_file
  )
  if hash == nil then
    utils.log("Unable to hash flake")
    return {}
  end

  local temp_dir = string.gsub(os.getenv("TMPDIR") or "/tmp", "/+$", "")
  local filename = ("%s/mise-nix-%s"):format(temp_dir, hash)

  -- check if already loaded
  if os.getenv("MISE_NIX") == hash then
    return {}
  end

  local handle ---@type file*?
  if utils.exists(filename) then
    -- load from cache
    handle = io.open(filename)
  else
    -- generate from nix and cache result
    local command = [[
      set -o pipefail
      nix print-dev-env \
        --json --quiet --option warn-dirty false \
        --reference-lock-file %q |
        tee %q
    ]]
    handle = io.popen(command:format(lock_file, filename))
  end

  if handle == nil then
    utils.log("Unable to get environment")
    return {}
  end

  ---@class DevEnv
  ---@field variables
  ---| { string: { type: "exported" | "var" | "array", value: any } }
  ---@field bashFunctions { string: string}

  ---@type boolean, DevEnv
  local status, data = pcall(json.decode, handle:read("*a"))
  handle:close()

  if not status then
    utils.log("Unable to load environment")
    return {}
  end

  ---@type { key: string, value: string}[]
  local exports = {
    { key = "MISE_NIX", value = hash },
  }
  local variables = {} ---@type string[]
  local functions = {} ---@type string[]

  for key, info in pairs(data.variables) do
    if VARS[key] == "ignore" then
      -- skip
    elseif info.type == "exported" then
      if key == "shellHook" then
        print(info.value)
      else
        exports[#exports + 1] = { key = key, value = info.value }
      end
    elseif info.type == "var" then
      table.insert(variables, key)
      print(("%s=%q"):format(key, info.value))
    elseif info.type == "array" then
      local value = {}
      for i, v in ipairs(info.value) do
        value[i] = ("%q"):format(v)
      end
      table.insert(variables, key)
      print(("%s=(%s)"):format(key, strings.join(value, " ")))
    end
  end

  for key, value in pairs(data.bashFunctions) do
    table.insert(functions, key)
    print(("%s() {%s}"):format(key, value))
  end

  print(make_unload_hook(project_root, variables, functions))

  return exports
end
