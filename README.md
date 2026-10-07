# Mise Nix Flake Plugin

Enable flake development environments, similar to `nix develop`, but in your own
shell.

Note: `shellHook` is not run unless the `shell_hook` option is enabled.

## Installation

To install the `nix` plugin, run:

```sh
$ mise plugins install nix
```

In `mise.toml`, enable the `nix` environment:

```toml
[env]
_.nix = true

[settings]
env_cache = true
```

This will automatically load the development environment from `flake.nix`,
equivalent to entering the shell via `nix develop`.

To install a specific [release](https://github.com/joshbode/mise-nix/releases):

```sh
$ mise plugins install nix https://github.com/joshbode/mise-nix#v0.1.0
```

## Configuration

The following options are supported:

| Option        | Type     | Default      | Description                        |
| ------------- | -------- | ------------ | ---------------------------------- |
| `flake_attr`  | `string` | `default`    | Flake attribute to use             |
| `flake_lock`  | `string` | `flake.lock` | Lock file to use                   |
| `profile_dir` | `string` | `.mise-nix`  | Directory for keeping profile link |
| `shell_hook`  | `bool`   | `false`      | Run `shellHook` (see below)        |
| `watch_files` | `array`  | `[]`         | Extra files to watch (see below)   |

For example, to use a specific lock-file, set the `flake_lock` option:

```toml
[env]
_.nix = { flake_lock = "some-flake.lock" }

[settings]
env_cache = true
```

### `shellHook`

Set `shell_hook = true` to run the flake's `shellHook` and use the resulting
environment, e.g. where the hook removes entries from `PATH` or unsets
variables:

```toml
[env]
_.nix = { shell_hook = true }
```

The hook is run non-interactively in a clean environment (only `HOME`, `USER`
and `LOGNAME` are passed through), with its output discarded. Only exported
variables are kept, so functions and aliases defined by the hook are not
available.

Entries the hook adds to `PATH` that are already on your `PATH` (e.g.
`/usr/bin`) are dropped, so they keep their usual position after the flake's
packages.

## Caching

The environment is cached in `profile_dir` (alongside the profile that keeps its
packages from being garbage-collected) and is rebuilt when the options change or
`flake.nix` or the lock file is modified. If the flake imports other files, add
them with `watch_files` (globs, relative to the flake):

```toml
[env]
_.nix = { watch_files = ["nix/*.nix"] }
```

The same files are reported to mise, so the `env_cache` setting can also avoid
running the plugin at all, although mise does not cache an environment that
includes redacted or encrypted values (e.g. from `sops`).

## Development

Tools and tasks are defined in `mise.toml`:

```sh
$ mise run fmt   # format Lua code
$ mise run lint  # check formatting and types
$ mise run test  # integration tests (requires nix)
```

The tests evaluate copies of the fixture flakes in `test/` with the plugin
installed into an isolated mise (separate data, config and state directories),
so they don't affect your own installation.

## Releasing

From an up-to-date, clean `main`:

```sh
$ mise run release 0.1.0
```

This sets the version in `metadata.lua`, then commits, tags (`v0.1.0`) and
pushes. The release workflow runs the tests, checks the tag matches
`metadata.lua` and publishes a GitHub release with generated notes.
