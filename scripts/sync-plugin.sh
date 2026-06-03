#!/usr/bin/env bash
# Sync the canonical root skill into the Claude Code plugin subtree.
#
# The skill has two consumers:
#   1. `npx skills add amply-tools/sdk-skill` — reads the ROOT SKILL.md + references/.
#   2. The Claude Code plugin (catalog repo amply-tools/claude-plugins references this
#      repo's plugins/amply-integration/ via a git-subdir sparse clone).
#
# A sparse clone of plugins/amply-integration/ cannot follow symlinks into the repo
# root, so the plugin subtree must hold REAL COPIES of SKILL.md + references/.
# This script regenerates those copies from the canonical root. Run it before every
# release; `--check` fails (non-zero) if the copies have drifted, for use as a gate.
set -euo pipefail
cd "$(dirname "$0")/.."   # repo root (public/)

SRC_SKILL="SKILL.md"
SRC_REFS="references"
DST_DIR="plugins/amply-integration/skills/amply-integration"

check=0
[ "${1:-}" = "--check" ] && check=1

if [ "$check" = 1 ]; then
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/$DST_DIR"
  cp "$SRC_SKILL" "$tmp/$DST_DIR/SKILL.md"
  cp -R "$SRC_REFS" "$tmp/$DST_DIR/references"
  if diff -r "$tmp/$DST_DIR" "$DST_DIR" >/dev/null 2>&1; then
    echo "sync-plugin: OK — plugin copy matches canonical root."
    rm -rf "$tmp"; exit 0
  else
    echo "sync-plugin: DRIFT — plugin copy differs from root. Run scripts/sync-plugin.sh to fix." >&2
    diff -r "$tmp/$DST_DIR" "$DST_DIR" >&2 || true
    rm -rf "$tmp"; exit 1
  fi
fi

mkdir -p "$DST_DIR"
rm -f "$DST_DIR/SKILL.md"
rm -rf "$DST_DIR/references"
cp "$SRC_SKILL" "$DST_DIR/SKILL.md"
cp -R "$SRC_REFS" "$DST_DIR/references"
echo "sync-plugin: copied root SKILL.md + references/ → $DST_DIR"
