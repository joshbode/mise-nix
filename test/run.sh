#! /usr/bin/env bash

# Integration tests: evaluate copies of the fixture flakes with the plugin
# installed into an isolated mise (requires mise, nix and jq)

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# isolate from the caller's mise configuration and shell activation
while IFS= read -r name; do
  unset "${name}"
done < <(compgen -e | grep -E '^_*MISE_' || true)

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
WORK="$(cd "${WORK}" && pwd -P)"

export MISE_DATA_DIR="${WORK}/data"
export MISE_STATE_DIR="${WORK}/state"
export MISE_CACHE_DIR="${WORK}/cache"
export MISE_CONFIG_DIR="${WORK}/config"
export MISE_GLOBAL_CONFIG_FILE="${MISE_CONFIG_DIR}/config.toml"
export MISE_TRUSTED_CONFIG_PATHS="${WORK}/fixtures"
export MISE_CEILING_PATHS="${WORK}"
# exercise the plugin's own cache rather than mise's
export MISE_ENV_CACHE=false

mkdir -p "${MISE_DATA_DIR}/plugins" "${MISE_CONFIG_DIR}" "${WORK}/fixtures"
touch "${MISE_GLOBAL_CONFIG_FILE}"
ln -s "${ROOT}" "${MISE_DATA_DIR}/plugins/nix"

for fixture in foo bar; do
  cp -R "${ROOT}/test/${fixture}" "${WORK}/fixtures/"
  rm -rf "${WORK}/fixtures/${fixture}/.mise-nix"
done

FAILURES=0
ENV_JSON=""
BUILDS=0

pass() {
  printf 'ok    %s\n' "$1"
}

fail() {
  printf 'FAIL  %s\n' "$1"
  if [[ -n "${2-}" ]]; then
    printf '      %s\n' "$2"
  fi
  FAILURES=$((FAILURES + 1))
}

# set file mtime explicitly: the cache compares mtimes with 1s resolution
set_mtime() {
  touch -t "$1" "$2"
}

# evaluate the environment in a directory, recording the number of builds
evaluate() {
  local stderr="${WORK}/stderr"
  if ! ENV_JSON="$(MISE_DEBUG=1 mise -C "$1" env --json 2> "${stderr}")"; then
    cat "${stderr}" >&2
    fail "mise env in $1"
    ENV_JSON="{}"
  fi
  if grep -q 'ERROR' "${stderr}"; then
    fail "errors in $1" "$(grep 'ERROR' "${stderr}" | head -3)"
  fi
  BUILDS="$(grep -c 'Building environment' "${stderr}" || true)"
}

# check that a jq filter is true for the evaluated environment
check() {
  if jq -e "$2" > /dev/null <<< "${ENV_JSON}"; then
    pass "$1"
  else
    fail "$1" "$2"
  fi
}

check_builds() {
  if [[ "${BUILDS}" -eq "$2" ]]; then
    pass "$1"
  else
    fail "$1" "expected $2 build(s), got ${BUILDS}"
  fi
}

# --- without shellHook -------------------------------------------------------

BAR="${WORK}/fixtures/bar"

evaluate "${BAR}"
check "bar: sets flake variables" '.BAR == "bar"'
check "bar: adds packages to PATH" '.PATH | split(":") | any(test("^/nix/store/[^/]+-yash-"))'
check "bar: does not export internal variables" 'has("MISE_NIX_PATH") or has("HOME") | not'
check_builds "bar: fresh evaluation builds once" 1

evaluate "${BAR}"
check "bar: cached environment" '.BAR == "bar"'
check_builds "bar: cached evaluation does not build" 0

mkdir -p "${BAR}/sub/dir"
evaluate "${BAR}/sub/dir"
check "bar: subdirectory finds flake" '.BAR == "bar"'
check_builds "bar: subdirectory uses cache" 0

set_mtime 202001010000 "${BAR}/flake.nix"
evaluate "${BAR}"
check_builds "bar: rebuilds when flake.nix changes" 1

set_mtime 202001010000 "${BAR}/flake.lock"
evaluate "${BAR}"
check_builds "bar: rebuilds when lock file changes" 1

rm "${BAR}/.mise-nix/profile"
evaluate "${BAR}"
if [[ -L "${BAR}/.mise-nix/profile" ]]; then
  pass "bar: profile is recreated"
else
  fail "bar: profile is recreated"
fi
check_builds "bar: rebuilds when profile is missing" 1

mkdir -p "${BAR}/nix"
touch "${BAR}/nix/shell.nix"
printf '[env]\n_.nix = { watch_files = ["nix/*.nix"] }\n' > "${BAR}/mise.toml"
evaluate "${BAR}"
check_builds "bar: rebuilds when options change" 1
evaluate "${BAR}"
check_builds "bar: watch_files cached" 0
set_mtime 202001010000 "${BAR}/nix/shell.nix"
evaluate "${BAR}"
check_builds "bar: rebuilds when watched file changes" 1

# --- with shellHook ----------------------------------------------------------

FOO="${WORK}/fixtures/foo"

evaluate "${FOO}"
check "foo: sets flake variables" '.FOO == "foo"'
check "foo: sets shellHook variables" '.FOO_HOOK == "foo-hook"'
check "foo: discards shellHook output" 'del(.shellHook) | [.[] | tostring | contains("should not be in the environment")] | any | not'
check "foo: drops shell variables" '[has("NIX_BUILD_TOP"), has("SHLVL"), has("TMP")] | any | not'
check "foo: adds packages to PATH" '.PATH | split(":") | any(test("^/nix/store/[^/]+-dash-"))'
check "foo: keeps user PATH entries after flake packages" '.PATH | split(":") | .[0] | startswith("/nix/store/")'
check_builds "foo: fresh evaluation builds once" 1

evaluate "${FOO}"
check "foo: cached shellHook variables" '.FOO_HOOK == "foo-hook"'
check_builds "foo: cached evaluation does not build" 0

# shellcheck disable=SC2016 # expanded by dash
if [[ "$(mise -C "${FOO}" exec -- dash -c 'printf %s "${FOO_HOOK}"' 2> /dev/null)" == "foo-hook" ]]; then
  pass "foo: exec runs flake packages with environment"
else
  fail "foo: exec runs flake packages with environment"
fi

echo
if [[ "${FAILURES}" -gt 0 ]]; then
  echo "${FAILURES} test(s) failed"
  exit 1
fi
echo "all tests passed"
