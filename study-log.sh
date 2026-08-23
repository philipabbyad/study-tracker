#!/usr/bin/env bash
set -euo pipefail

FILE="${1:?Usage: study-log.sh <path-to-schedule-file> [--date \"Mon 8/24\"]}"

DATE_OVERRIDE=""
if [[ "${2:-}" == "--date" ]]; then
  DATE_OVERRIDE="${3:?--date requires an argument like 'Mon 8/24'}"
fi

if [[ -n "$DATE_OVERRIDE" ]]; then
  TODAY_PATTERN="$DATE_OVERRIDE"
else
  WEEKDAY=$(date +%a)
  MONTHDAY=$(date +%-m/%-d)
  TODAY_PATTERN="$WEEKDAY $MONTHDAY"
fi

mapfile -t LINES < "$FILE"

header_idx=-1
for i in "${!LINES[@]}"; do
  if [[ "${LINES[$i]}" == "$TODAY_PATTERN"* ]]; then
    header_idx=$i
    break
  fi
done

if [[ $header_idx -eq -1 ]]; then
  echo "No entry found for '$TODAY_PATTERN' in $FILE."
  exit 1
fi

echo "== ${LINES[$header_idx]} =="

changed=0
i=$((header_idx + 1))
while [[ $i -lt ${#LINES[@]} && -n "${LINES[$i]}" ]]; do
  line="${LINES[$i]}"
  if [[ "$line" == "[ ]"* ]]; then
    desc="${line#\[ \] }"
    echo ""
    echo "$desc"
    read -rp "Completed? [y]es on-time / [e]arly / [l]ate / [s]kip / [q]uit: " ans
    case "$ans" in
      y|Y) LINES[$i]="[X] $desc"; changed=$((changed + 1)) ;;
      e|E) LINES[$i]="[*X] $desc"; changed=$((changed + 1)) ;;
      l|L) LINES[$i]="[X*] $desc"; changed=$((changed + 1)) ;;
      q|Q) break ;;
      *) ;;
    esac
  else
    echo "  (already logged) $line"
  fi
  i=$((i + 1))
done

if [[ $changed -gt 0 ]]; then
  printf '%s\n' "${LINES[@]}" > "$FILE.tmp"
  mv "$FILE.tmp" "$FILE"
  echo ""
  echo "Saved $changed update(s) to $FILE"
else
  echo ""
  echo "No changes made."
fi
