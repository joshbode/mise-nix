#!/usr/bin/env bash
#
# Release a new version: set the version in metadata.lua, then commit, tag and
# push. The release workflow runs the tests and publishes the GitHub release.
#
# usage: release.sh <version>

set -euo pipefail

die() {
  echo "error: $*" >&2
  exit 1
}

VERSION="${1:?usage: release.sh <version>}"
VERSION="${VERSION#v}"
TAG="v${VERSION}"

[[ "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "invalid version: ${VERSION}"

cd "$(dirname "${BASH_SOURCE[0]}")/.."

[[ "$(git branch --show-current)" == "main" ]] || die "not on main"
if ! git diff --quiet || ! git diff --cached --quiet; then
  die "working tree has changes"
fi

git fetch --quiet --tags origin
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || die "main is not up to date with origin/main"
if git rev-parse --quiet --verify "refs/tags/${TAG}" >/dev/null; then
  die "tag already exists: ${TAG}"
fi

CURRENT="$(sed -n 's/^  version = "\(.*\)",$/\1/p' metadata.lua)"
[[ -n "${CURRENT}" ]] || die "unable to find version in metadata.lua"
[[ "${CURRENT}" != "${VERSION}" ]] || die "version is already ${VERSION}"

perl -pi -e "s/^  version = \"\Q${CURRENT}\E\",\$/  version = \"${VERSION}\",/" metadata.lua

git commit --quiet --message "Release ${TAG}" metadata.lua
git tag --annotate "${TAG}" --message "${TAG}"
git push --atomic origin main "${TAG}"

echo "Pushed ${TAG}: the release workflow will publish it"
