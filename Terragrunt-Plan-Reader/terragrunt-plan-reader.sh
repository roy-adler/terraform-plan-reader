#!/usr/bin/env bash
set -euo pipefail

if [[ $# -gt 1 ]]; then
  echo "Usage: $0 [logfile]"
  exit 1
fi

current_group=""

process() {
  while IFS= read -r raw; do
    # ANSI-stripped copy ONLY for matching
    clean="$(sed -E 's/\x1b\[[0-9;]*m//g' <<<"$raw")"

    if [[ "$clean" =~ .*\[(.+?)\][[:space:]]+terraform: ]]; then
      unit="${BASH_REMATCH[1]}"

      # Open / switch group
      if [[ "$unit" != "$current_group" ]]; then
        [[ -n "$current_group" ]] && echo "##[endgroup]"
        echo "##[group]$unit"
        current_group="$unit"
      fi

      # 🔥 Remove EVERYTHING in brackets + terraform prefix
      echo "$raw" | sed -E 's/\[[^]]+\][[:space:]]+.*terraform:[[:space:]]?//'
    else
      # Also remove standalone [stack] if it appears without terraform:
      echo "$raw" | sed -E 's/\[[^]]+\][[:space:]]+//'
    fi
  done
}

if [[ $# -eq 1 ]]; then
  process < "$1"
else
  process
fi

[[ -n "$current_group" ]] && echo "##[endgroup]"