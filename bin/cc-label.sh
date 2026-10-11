#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=cc-lib.sh
source "$HERE/cc-lib.sh"
dir="$(ccm_expand "${1:?usage: cc-label.sh <configDir>}")"
ccm_accounts | awk -F'\t' -v d="$dir" '$2==d{print $1; f=1} END{if(!f) print "default"}' | head -1
