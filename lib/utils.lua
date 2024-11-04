local strings = require("vfox.strings") ---@class Strings

---Log info to stdout
---@param x any
local function log(x, ...)
  print(("echo mise-nix: %q"):format(x:format(...)))
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
  local files = { ... }
  local command = ("cat %s | openssl sha256"):format(string.rep("%q", #files, " "))
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

---@module 'utils'
return {
  exists = exists,
  find_project_root = find_project_root,
  get_cwd = get_cwd,
  get_hash = get_hash,
  log = log,
}
