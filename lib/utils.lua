---@type Json
local json = require("json")

---@type Strings
local strings = require("strings")

---@type Cmd
local cmd = require("cmd")

---@type File
local file = require("file")

---@type Log
local log = require("log")

---Get current working directory
---@return string?
local function get_cwd()
  local ok, result = pcall(cmd.exec, "pwd")
  if ok and result then
    return strings.trim_space(result)
  end
  return nil
end

---Find project root
---@param filename string Project filename (e.g. flake.nix)
---@param cwd string? Initial directory to search
---@return string?
local function find_project_root(filename, cwd)
  if cwd == nil then
    cwd = get_cwd()
    if cwd == nil then
      return nil
    end
  end

  ---@cast cwd string

  if file.exists(file.join_path(cwd, filename)) then
    return cwd
  else
    if cwd == "/" then
      return nil
    end
    local parts = strings.split(cwd, "/") ---@type string[]
    table.remove(parts, #parts)
    local parent = strings.join(parts, "/") ---@type string
    if parent == "" then
      parent = "/"
    end
    return find_project_root(filename, parent)
  end
end

---Load environment from command output
---@param command string
---@return DevEnv?
local function get_env(command)
  local ok, result = pcall(cmd.exec, command)
  if ok and result then
    local status, data = pcall(json.decode, result)
    if status and type(data) == "table" then
      return data
    end
  end

  return nil
end

---Variables set by the shell or `nix print-dev-env` itself rather than the
---shellHook (the temporary build directory is removed once the hook has run)
local HOOK_IGNORE = {
  _ = true,
  OLDPWD = true,
  PWD = true,
  SHLVL = true,
  NIX_BUILD_TOP = true,
  TEMP = true,
  TEMPDIR = true,
  TMP = true,
}

---Run shellHook in a clean environment and capture the exported variables
---@param env DevEnv Environment without shellHook applied
---@param profile_dir string
---@param lock_file string
---@param attr string
---@return table<string, { type: "exported", value: string }>?
local function run_shell_hook(env, profile_dir, lock_file, attr)
  -- use the bash from the environment: the dev-env script needs bash 4+
  local shell = env.variables.SHELL and env.variables.SHELL.value or "bash"

  -- hook output is sent to stderr, and the result is NUL-delimited
  -- `name=value` pairs, since values may contain newlines (the absolute path
  -- avoids depending on the hook's PATH)
  local ok, result = pcall(
    cmd.exec,
    ([=[
    set -eu

    PROFILE_DIR=%q
    LOCK_FILE=%q
    ATTR=%q
    SHELL_PATH=%q

    SCRIPT="$(mktemp)"
    trap 'rm -f "${SCRIPT}"' EXIT

    nix print-dev-env ".#${ATTR}" \
      --quiet \
      --profile "${PROFILE_DIR}/profile" \
      --reference-lock-file "${LOCK_FILE}" \
      --option warn-dirty false \
      > "${SCRIPT}"

    env -i HOME="${HOME}" USER="${USER:-}" LOGNAME="${LOGNAME:-}" \
      "${SHELL_PATH}" --noprofile --norc -c '
        . "$1" >&2
        rm -rf "${NIX_BUILD_TOP}"
        exec /usr/bin/env -0
      ' bash "${SCRIPT}"
  ]=]):format(profile_dir, lock_file, attr, shell)
  )
  if not ok or result == nil then
    return nil
  end

  local variables = {}
  for item in result:gmatch("([^%z]*)%z") do
    local key, value = item:match("^([^=]+)=(.*)$")
    if key ~= nil and not HOOK_IGNORE[key] then
      variables[key] = { type = "exported", value = value }
    end
  end

  return variables
end

---Get environment info
---@param options Options
---@return {env: DevEnv, lock_file: string}?
local function load_env(options)
  if options.flake_attr == nil then
    options.flake_attr = "default"
  end
  if options.flake_lock == nil then
    options.flake_lock = "flake.lock"
  end
  if options.profile_dir == nil then
    options.profile_dir = ".mise-nix"
  end

  local project_root = find_project_root("flake.nix")
  if project_root == nil then
    log.error("Unable to find flake")
    return nil
  end

  local lock_file = file.join_path(project_root, options.flake_lock)
  local profile_dir = file.join_path(project_root, options.profile_dir)

  if not file.exists(lock_file) then
    log.error("Lock file does not exist:", lock_file)
    return nil
  end

  ---@type DevEnv?
  local env = get_env(([=[
    set -eu

    PROFILE_DIR=%q
    LOCK_FILE=%q
    ATTR=%q

    mkdir -p "${PROFILE_DIR}"
    echo "*" > "${PROFILE_DIR}/.gitignore"

    nix profile wipe-history \
      --quiet \
      --profile "${PROFILE_DIR}/profile"

    nix print-dev-env ".#${ATTR}" \
      --quiet \
      --profile "${PROFILE_DIR}/profile" \
      --reference-lock-file "${LOCK_FILE}" \
      --option warn-dirty false \
      --json
  ]=]):format(profile_dir, lock_file, options.flake_attr))

  if env == nil then
    log.error("Failed to load environment")
    return nil
  end

  if options.shell_hook and env.variables.shellHook ~= nil then
    local variables = run_shell_hook(env, profile_dir, lock_file, options.flake_attr)
    if variables == nil then
      log.error("Failed to run shellHook")
      return nil
    end
    env.variables = variables
  end

  return { env = env, lock_file = lock_file }
end

return {
  find_project_root = find_project_root,
  load_env = load_env,
}
