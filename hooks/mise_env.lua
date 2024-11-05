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
  local hook_name = "_unload_mise_nix"

  local lines = {} ---@type string[]
  table.insert(lines, ('%s() {'):format(hook_name))
  table.insert(lines, ('  local PROJECT_ROOT=%q'):format(project_root))
  table.insert(lines, '  if [[ "${CWD#${PROJECT_ROOT}/}" != "${CWD}" ]]; then return; fi')
  table.insert(lines, ('  unset -f %s'):format(hook_name))
  for _, name in ipairs(variables) do
    table.insert(lines, ('  unset %q'):format(name))
  end
  for _, name in ipairs(functions) do
    table.insert(lines, ('  unset -f %q'):format(name))
  end
  if shell == "zsh" then
    table.insert(lines, ('  add-zsh-hook -d chpwd %s'):format(hook_name))
  elseif shell == "bash" then
    table.insert(lines, ('  PROMPT_COMMAND=${PROMPT_COMMAND%%;%s}'):format(hook_name))
  end
  table.insert(lines, '}')

  if shell == "zsh" then
    table.insert(lines, ('add-zsh-hook chpwd %s'):format(hook_name))
  elseif shell == "bash" then
    table.insert(lines,
      ('  if [[ "${PROMPT_COMMAND%%;%s}" == "${PROMPT_COMMAND}" ]]; then'):format(hook_name))
    table.insert(lines, ('    PROMPT_COMMAND="${PROMPT_COMMAND};%s"'):format(hook_name))
    table.insert(lines, '  fi')
  end

  return strings.join(lines, "\n")
end

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
  local variables = {} ---@type string[]
  local functions = {} ---@type string[]

  -- should shell-specific outputs be emitted?
  local shell = os.getenv("VIM") == nil

  for key, info in pairs(env.variables) do
    if VARS[key] == "ignore" then
      -- skip
    elseif info.type == "exported" then
      if key == "shellHook" then
        if shell then
          print(info.value)
        end
      else
        exports[#exports + 1] = { key = key, value = info.value }
      end
    elseif info.type == "var" then
      if shell then
        table.insert(variables, key)
        print(("%s=%q"):format(key, info.value))
      end
    elseif info.type == "array" then
      if shell then
        local value = {}
        for i, v in ipairs(info.value) do
          value[i] = ("%q"):format(v)
        end
        table.insert(variables, key)
        print(("%s=(%s)"):format(key, strings.join(value, " ")))
      end
    end
  end

  if shell then
    for key, value in pairs(env.bashFunctions) do
      table.insert(functions, key)
      print(("%s() {%s}"):format(key, value))
    end
    print(make_unload_hook(project_root, variables, functions))
  end

  return exports
end
