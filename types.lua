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
---@field profile_dir string? Optional profile directory to use

--- Nix plugin context
---@class Context
---@field options Options | boolean Plugin options

--- Mise plugin
---@class Plugin: PluginBase
---@field MisePath fun(self: Plugin, ctx: Context): string[] Update PATH
---@field MiseEnv fun(self: Plugin, ctx: Context): {key: string, value: string}[] Update environment

--- VFox built-in strings library
---@class Strings
---@field contains fun(x: string, substr: string): boolean
---@field has_prefix fun(x: string, prefix: string): boolean
---@field has_suffix fun(x: string, suffix: string): boolean
---@field join fun(x: string[], sep: string): string Join array of strings with delimiter
---@field split fun(x: string, sep: string): string[] Split string by delimiter into array of strings
---@field trim fun(x: string, suffix: string): string
---@field trim_space fun(x: string): string

--- Development environment
---@class DevEnv
---@field variables
---| { string: { type: "exported" | "var" | "array", value: any } }
---@field bashFunctions { string: string}
