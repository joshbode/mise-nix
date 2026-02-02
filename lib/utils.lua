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

  return { env = env, lock_file = lock_file }
end

return {
  find_project_root = find_project_root,
  load_env = load_env,
}
