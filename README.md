# Mise Nix Plugin

Enable flake development environment, equivalent to `nix develop`:

```toml
[env]
_.nix = true
```

To use a different lock-file, set the `flake_lock` option:
```toml
[env]
_.nix = { flake_lock = "some-flake.lock" }
```
