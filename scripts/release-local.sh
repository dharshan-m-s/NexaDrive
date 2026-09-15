#!/usr/bin/env bash
set -euo pipefail

# Create/update a release tag and let GitHub Actions build all distributables.
# Usage: ./scripts/release-local.sh 0.2.0
VERSION="${1:?Usage: $0 <version> }"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

cd "$ROOT"
sed -i -E "s/^version: .*/version: ${VERSION}+${VERSION//./}/" app/pubspec.yaml

git add app/pubspec.yaml
git commit -m "release: v${VERSION}"
git tag -a "v${VERSION}" -m "NexaDrive v${VERSION}"
git push origin "HEAD" "v${VERSION}"
