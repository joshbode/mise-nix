# Mise Nix Flake Plugin

Enable flake development environments, equivalent to `nix develop`.

## Installation

To install the `nix` plugin, run:

```sh
$ mise plugins install nix
```

## Configuration

In `.mise.toml`, enable the `nix` environment:

```toml
[env]
_.nix = true
```

This will automatically load the development environment from `flake.nix`,
equivalent to entering the shell via `nix develop`.

To use a different lock-file, set the `flake_lock` option:

```toml
[env]
_.nix = { flake_lock = "some-flake.lock" }
```
