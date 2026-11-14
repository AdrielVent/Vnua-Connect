#!/bin/zsh
# Usage: tests/live/run.sh [site-url]   (default: the live GitHub Pages site)
# Runs the full web end-to-end suite in WebKit against the LIVE Supabase project with throwaway accounts,
# then deletes everything it created. Screenshots go to $TMPDIR/vnua-shots.
set -e
SITE=${1:-https://adrielvent.github.io/Vnua-Connect/}
source "$(dirname "$0")/env.sh"
SHOTS=${TMPDIR:-/tmp}/vnua-shots; rm -rf "$SHOTS"; mkdir -p "$SHOTS"
cd tests/live && [ -d node_modules ] || npm install --silent
SHOTS=$SHOTS SITE=$SITE node web_e2e.mjs
SITE=$SITE node ptr_check.mjs
SITE=$SITE node fonts_hang.mjs
SITE=$SITE node layout_slot_check.mjs
