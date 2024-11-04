---@meta

--- VFox plugin
---@class PluginBase
---@field name string Plugin name
---@field version string Plugin version
---@field description string Plugin description
---@field homepage string Plugin homepage
---@field license string Plugin license, please choose a correct license according to your needs.
---@field minRuntimeVersion string? Minimum compatible vfox version.
---@field manifestUrl string? If configured, vfox will check for updates to the plugin at this address, otherwise it will check for updates at the global registry.
---@field notes table? Some things that require the user's attention

--- Nix plugin options
---@class Options
---@field flake_lock string? Optional lock file to use

--- Nix plugin context
---@class Context
---@field options Options | boolean Plugin options

--- Mise plugin
---@class Plugin: PluginBase
---@field MisePath fun(self: Plugin, ctx: Context): string[] Update PATH
---@field MiseEnv fun(self: Plugin, ctx: Context): {key: string, value: string}[] Update environment

--- VFox built-in strings library
---@class Strings
---@field split fun(x: string, delim: string): string[] Split string by delimiter into array of strings
---@field join fun(x: string[], delim: string): string Join array of strings with delimiter

--- Development environment
---@class DevEnv
---@field variables
---| { string: { type: "exported" | "var" | "array", value: any } }
---@field bashFunctions { string: string}
