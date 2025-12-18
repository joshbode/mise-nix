local json = require("json")

---@type Strings
local strings = require("strings")

if table.unpack == nil then
  table.unpack = unpack
end

---Log info to stderr
---@param message any
local function log(message, ...)
  if ... ~= nil then
    local args = { ... }
    for i, value in ipairs(args) do
      if type(value) == "table" then
        args[i] = json.encode(value)
      end
    end
    message = message:format(table.unpack(args))
  elseif type(message) ~= "string" then
    message = json.encode(message)
  end

  print(("printf 'mise-nix: %%s\n' %q >&2"):format(message))
end

---Check if file exists
---@param filename string Filename to check
---@return boolean
local function exists(filename)
  local handle = io.open(filename, "r")
  if handle ~= nil then
    handle:close()
    return true
  else
    return false
  end
end

---Get current working directory
---@return string?
local function get_cwd()
  local handle = io.popen("pwd")
  if handle ~= nil then
    local result = handle:read("*l")
    handle:close()
    return result
  else
    return nil
  end
end

---Find project root
---@param filename string Project filename (e.g. flake.nix)
---@param cwd string? Initial directory to search
---@return string?
local function find_project_root(filename, cwd, i)
  if i == nil then
    i = 10
  end
  if i == 0 then
    return nil
  end

  if cwd == nil then
    cwd = get_cwd()
    if cwd == nil then
      return nil
    end
  end

  ---@cast cwd string

  if exists(("%s/%s"):format(cwd, filename)) then
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
    return find_project_root(filename, parent, i - 1)
  end
end

---Get joint hash of files
---@param ... string File to hash
---@return string?
local function get_hash(...)
  if ... == nil then
    return nil
  end

  local files = { ... }
  local command = ("cat%s | openssl sha256"):format(string.rep(" %q", #files))
  local handle = io.popen(command:format(table.unpack(files)))
  if handle ~= nil then
    local result = handle:read("*l")
    local status, _, _ = handle:close()
    if status then
      local hash = string.gsub(result, "[^ ]+ ", "")
      return hash
    else
      return nil
    end
  else
    return nil
  end
end

---Load environment from handle
---@param handle file*?
---@return DevEnv?
local function get_env(handle)
  if handle ~= nil then
    local status, data = pcall(json.decode, handle:read("*a"))
    handle:close()
    if status and type(data) == "table" then
      return data
    end
  end

  return nil
end

---Get environment info
---@param options Options
---@return {tag: string, env: DevEnv}?
local function load_env(options)
  if options.flake_lock == nil then
    options.flake_lock = "flake.lock"
  end
  if options.profile_dir == nil then
    options.profile_dir = ".mise-nix"
  end

  local project_root = find_project_root("flake.nix")
  if project_root == nil then
    log("Unable to find flake")
    return nil
  end

  local flake_file = ("%s/%s"):format(project_root, "flake.nix")
  local lock_file = ("%s/%s"):format(project_root, options.flake_lock)
  local profile_dir = ("%s/%s"):format(project_root, options.profile_dir)

  if not exists(lock_file) then
    log("Lock file does not exist: %s", lock_file)
    return nil
  end

  local hash = get_hash(flake_file, lock_file)
  if hash == nil then
    log("Unable to hash flake files")
    return nil
  end

  local temp_dir = string.gsub(os.getenv("TMPDIR") or "/tmp", "/+$", "")
  local filename = ("%s/mise-nix-%s"):format(temp_dir, hash)
  local tag = ("%s:%s"):format(project_root, hash)

  ---@type DevEnv?
  local env = nil

  -- check if already loaded
  if os.getenv("MISE_NIX") == tag then
    return nil
  end

  if exists(filename) then
    -- load from cache
    env = get_env(io.open(filename))
  end

  if env == nil then
    -- generate from nix and cache result
    env = get_env(io.popen(([=[
      set -eu

      PROFILE_DIR=%q
      LOCK_FILE=%q

      mkdir -p "${PROFILE_DIR}"

      nix profile wipe-history \
        --quiet \
        --profile "${PROFILE_DIR}/profile"

      nix print-dev-env \
        --quiet \
        --profile "${PROFILE_DIR}/profile" \
        --reference-lock-file "${LOCK_FILE}" \
        --option warn-dirty false \
        --json
    ]=]):format(profile_dir, lock_file)))

    if env == nil then
      log("Failed to load environment")
      return nil
    end

    local file = io.open(filename, "w")
    if file ~= nil then
      file:write(json.encode(env))
      file:close()
    end
  end

  ---@cast env DevEnv
  return { tag = tag, env = env }
end

---@module 'utils'
return {
  exists = exists,
  find_project_root = find_project_root,
  get_cwd = get_cwd,
  get_hash = get_hash,
  load_env = load_env,
  log = log,
}
