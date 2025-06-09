# Mise Nix Flake Plugin

Enable flake development environments, similar to `nix develop`, but in your own
shell.

Note: `shellHook` will not be loaded.

## Installation

To install the `nix` plugin, run:

```sh
$ mise plugins install https://github.com/joshbode/mise-nix
```

In `.mise.toml`, enable the `nix` environment:

```toml
[env]
_.nix = true
```

This will automatically load the development environment from `flake.nix`,
equivalent to entering the shell via `nix develop`.

## Configuration

The following options are supported:

| Option        | Type     | Default      | Description                        |
| ------------- | -------- | ------------ | ---------------------------------- |
| `flake_lock`  | `string` | `flake.lock` | Lock file to use                   |
| `profile_dir` | `string` | `.mise-nix`  | Directory for keeping profile link |

For example, to use a specific lock-file, set the `flake_lock` option:

```toml
[env]
_.nix = { flake_lock = "some-flake.lock" }
```
