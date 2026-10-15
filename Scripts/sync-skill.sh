#!/usr/bin/env bash
# Copies the Lua API docs into the agent skill, Sources/Locky/Resources/skill/locky/references. docs/ is the one
# source: edit the docs, then run this. AgentSkillTests fails while a copy differs.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
for name in api create-widget plugins themes views widgets; do
  cp "$ROOT/docs/$name.md" "$ROOT/Sources/Locky/Resources/skill/locky/references/$name.md"
done
