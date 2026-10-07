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

---Bump when the cached format or the way the environment is built changes
local CACHE_VERSION = "1"

---Find project root
---@param filename string Project filename (e.g. flake.nix)
---@param dir string? Initial directory to search
---@return string?
local function find_project_root(filename, dir)
  if dir == nil or dir == "" then
    return nil
  end

  if file.exists(file.join_path(dir, filename)) then
    return dir
  end
  if dir == "/" then
    return nil
  end

  local parts = strings.split(dir, "/") ---@type string[]
  table.remove(parts, #parts)
  local parent = strings.join(parts, "/") ---@type string
  if parent == "" then
    parent = "/"
  end
  return find_project_root(filename, parent)
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

---Remove entries outside the Nix store that are already on the user's PATH
---(e.g. `/usr/bin` added by a hook): mise prepends these and treats them as its
---own, so they would shadow the user's ordering and be removed from the user's
---PATH when mise reverts its changes
---@param path string
---@return string
local function filter_path(path)
  local user_path = os.getenv("__MISE_ORIG_PATH") or os.getenv("PATH") or ""

  local existing = {}
  for _, entry in ipairs(strings.split(user_path, ":")) do
    existing[entry] = true
  end

  local result = {}
  for _, entry in ipairs(strings.split(path, ":")) do
    if entry ~= "" and (strings.has_prefix(entry, "/nix/store/") or not existing[entry]) then
      result[#result + 1] = entry
    end
  end

  return strings.join(result, ":")
end

---Build the environment with `nix print-dev-env`
---@param project_root string
---@param profile_dir string
---@param lock_file string
---@param attr string
---@return table<string, string>?
local function build_env(project_root, profile_dir, lock_file, attr)
  -- values are passed through the environment rather than interpolated into
  -- the command
  local ok, result = pcall(
    cmd.exec,
    [=[
    set -eu

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
  ]=],
    {
      cwd = project_root,
      env = { PROFILE_DIR = profile_dir, LOCK_FILE = lock_file, ATTR = attr },
    }
  )
  if not ok or result == nil then
    return nil
  end

  local status, data = pcall(json.decode, result)
  if not status or type(data) ~= "table" or type(data.variables) ~= "table" then
    return nil
  end

  ---@cast data DevEnv
  local variables = {}
  for key, info in pairs(data.variables) do
    if info.type == "exported" then
      variables[key] = info.value
    end
  end

  return variables
end

---Run shellHook in a clean environment and capture the exported variables
---@param project_root string
---@param profile_dir string
---@param lock_file string
---@param attr string
---@param shell string Shell from the environment without shellHook applied
---@return table<string, string>?
local function run_shell_hook(project_root, profile_dir, lock_file, attr, shell)
  -- hook output is sent to stderr, and the result is NUL-delimited
  -- `name=value` pairs, since values may contain newlines (the absolute path
  -- avoids depending on the hook's PATH)
  local ok, result = pcall(
    cmd.exec,
    [=[
    set -eu

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
  ]=],
    {
      cwd = project_root,
      env = {
        PROFILE_DIR = profile_dir,
        LOCK_FILE = lock_file,
        ATTR = attr,
        SHELL_PATH = shell,
      },
    }
  )
  if not ok or result == nil then
    return nil
  end

  local variables = {}
  for item in result:gmatch("([^%z]*)%z") do
    local key, value = item:match("^([^=]+)=(.*)$")
    if key ~= nil and not HOOK_IGNORE[key] then
      variables[key] = value
    end
  end

  return variables
end

---Expand watched files: the flake, lock file and any `watch_files` patterns
---@param project_root string
---@param lock_file string
---@param patterns string[]?
---@return string[]
local function get_watch_files(project_root, lock_file, patterns)
  local result = { file.join_path(project_root, "flake.nix"), lock_file }
  local seen = { [result[1]] = true, [lock_file] = true }

  for _, pattern in ipairs(patterns or {}) do
    if not strings.has_prefix(pattern, "/") then
      pattern = file.join_path(project_root, pattern)
    end
    for _, path in ipairs(file.glob(pattern)) do
      if not seen[path] then
        seen[path] = true
        result[#result + 1] = path
      end
    end
  end

  return result
end

---Compute the cache key from the options and the watched files' mtimes
---@param options Options
---@param watch_files string[]
---@return string
local function get_cache_key(options, watch_files)
  local parts = {
    CACHE_VERSION,
    options.flake_attr,
    options.flake_lock,
    tostring(options.shell_hook == true),
  }
  for _, path in ipairs(watch_files) do
    local stat = file.stat(path)
    parts[#parts + 1] = ("%s=%s"):format(path, stat and tostring(stat.modified) or "missing")
  end
  return strings.join(parts, "\n")
end

---Load cached environment if the key matches and the profile (which keeps the
---store paths from being garbage-collected) still exists
---@param cache_file string
---@param profile_dir string
---@param key string
---@return table<string, string>?
local function read_cache(cache_file, profile_dir, key)
  if not file.exists(cache_file) or not file.exists(file.join_path(profile_dir, "profile")) then
    return nil
  end

  local ok, data = pcall(function()
    return json.decode(file.read(cache_file))
  end)
  if ok and type(data) == "table" and data.key == key and type(data.variables) == "table" then
    return data.variables
  end

  return nil
end

---Write environment to cache (atomically, since hooks may run concurrently)
---@param cache_file string
---@param key string
---@param variables table<string, string>
local function write_cache(cache_file, key, variables)
  -- table address is unique enough for a temporary name per process
  local id = tostring({}):match("0x(%x+)") or tostring(os.time())
  local tmp_file = ("%s.%s.tmp"):format(cache_file, id)
  local handle = io.open(tmp_file, "w")
  if handle == nil then
    log.debug("Unable to write cache:", cache_file)
    return
  end
  handle:write(json.encode({ key = key, variables = variables }))
  handle:close()
  if not os.rename(tmp_file, cache_file) then
    os.remove(tmp_file)
  end
end

---Get environment info
---@param options Options
---@param config_root string? Root of the config file declaring the directive
---@return {variables: table<string, string>, watch_files: string[]}?
local function load_env(options, config_root)
  if options.flake_attr == nil then
    options.flake_attr = "default"
  end
  if options.flake_lock == nil then
    options.flake_lock = "flake.lock"
  end
  if options.profile_dir == nil then
    options.profile_dir = ".mise-nix"
  end

  -- prefer the config root, falling back to the current directory (e.g. for a
  -- directive in the global config)
  local project_root = find_project_root("flake.nix", config_root)
    or find_project_root("flake.nix", os.getenv("PWD"))
  if project_root == nil then
    log.error("Unable to find flake")
    return nil
  end

  local lock_file = file.join_path(project_root, options.flake_lock)
  local profile_dir = file.join_path(project_root, options.profile_dir)
  local cache_file = file.join_path(profile_dir, "env.json")

  if not file.exists(lock_file) then
    log.error("Lock file does not exist:", lock_file)
    return nil
  end

  local watch_files = get_watch_files(project_root, lock_file, options.watch_files)
  local key = get_cache_key(options, watch_files)

  local variables = read_cache(cache_file, profile_dir, key)

  if variables == nil then
    variables = build_env(project_root, profile_dir, lock_file, options.flake_attr)
    if variables == nil then
      log.error("Failed to load environment")
      return nil
    end

    if options.shell_hook and variables.shellHook ~= nil then
      -- use the bash from the environment: the dev-env script needs bash 4+
      variables = run_shell_hook(
        project_root,
        profile_dir,
        lock_file,
        options.flake_attr,
        variables.SHELL or "bash"
      )
      if variables == nil then
        log.error("Failed to run shellHook")
        return nil
      end
    end

    write_cache(cache_file, key, variables)
  end

  -- filtering depends on the user's PATH, so is not cached
  if options.shell_hook and variables.PATH ~= nil then
    variables.PATH = filter_path(variables.PATH)
  end

  return { variables = variables, watch_files = watch_files }
end

return {
  find_project_root = find_project_root,
  load_env = load_env,
}
