#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../app"

# The repository keeps Flutter business logic lightweight. Generate platform shells
# on a development machine or in CI; Flutter preserves lib/, test/, and pubspec.yaml.
flutter create --platforms=android,windows,linux .
