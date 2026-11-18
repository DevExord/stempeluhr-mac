#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Builds a universal Stempeluhr.app and publishes it to a GitHub Release from
# this machine — no CI needed. Useful while the repo is private (GitHub's
# macOS-hosted runners are free only on public repos).
#
#   scripts/release.sh v1.0.1
#
# Needs: the Swift toolchain and an authenticated `gh` CLI.
set -euo pipefail
cd "$(dirname "$0")/.."

TAG="${1:?usage: scripts/release.sh <tag, e.g. v1.0.1>}"
ZIP="build/Stempeluhr-macOS.zip"

./scripts/build-app.sh release
( cd build && rm -f Stempeluhr-macOS.zip && \
  ditto -c -k --keepParent --sequesterRsrc Stempeluhr.app Stempeluhr-macOS.zip )

# Create and push the tag if it isn't on the remote yet.
if ! git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null 2>&1; then
  git rev-parse "$TAG" >/dev/null 2>&1 || git tag "$TAG"
  git push origin "$TAG"
fi

NOTES=$'## Stempeluhr for macOS\n\nDownload **Stempeluhr-macOS.zip**, unzip it, and move `Stempeluhr.app` to your Applications folder.\n\nThe app is **not Apple-notarized**, so the first launch needs one step: **right-click the app → Open → Open** (or run `xattr -dr com.apple.quarantine /Applications/Stempeluhr.app` once). Universal build — runs on Apple Silicon and Intel.'

if gh release view "$TAG" >/dev/null 2>&1; then
  gh release upload "$TAG" "$ZIP" --clobber
else
  gh release create "$TAG" "$ZIP" --title "Stempeluhr $TAG" --notes "$NOTES"
fi

echo "✓ Released $TAG"
