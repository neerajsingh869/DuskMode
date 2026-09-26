#!/bin/bash
# Push main and tags to both GitHub copies of DuskMode, so they never drift.
#   neerajsingh869/DuskMode  canonical: releases and the install.sh URL live here
#   neerajtechwhiz/DuskMode  full mirror with its own GitHub Pages site
# Usage: scripts/publish.sh            (pass --force after a history rewrite)
# Needs both accounts logged in to gh; git auth for this repo goes through gh.
set -euo pipefail
cd "$(dirname "$0")/.."

ACTIVE="$(gh api user -q .login)"
trap 'gh auth switch -h github.com -u "$ACTIVE" >/dev/null 2>&1' EXIT

push() {  # account, remote, extra git-push args
  gh auth switch -h github.com -u "$1" >/dev/null
  echo "==> $1"
  git push "$2" main "${@:3}"
  git push "$2" --tags "${@:3}"
}

push neerajsingh869 origin "$@"
push neerajtechwhiz techwhiz "$@"
echo "✓ Both copies are up to date."
