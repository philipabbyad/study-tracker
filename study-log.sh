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

YEAR=$(date +%Y)
DAY_HEADER_RE='^(Mon|Tue|Wed|Thu|Fri|Sat|Sun) ([0-9]{1,2})/([0-9]{1,2})'

mapfile -t LINES < "$FILE"

changed=0
QUIT=0

header_epoch() {
  local line="$1"
  if [[ "$line" =~ $DAY_HEADER_RE ]]; then
    date -d "$YEAR-${BASH_REMATCH[2]}-${BASH_REMATCH[3]}" +%s
  fi
}

header_label() {
  local line="$1"
  if [[ "$line" =~ $DAY_HEADER_RE ]]; then
    echo "${BASH_REMATCH[0]}"
  else
    echo "$line"
  fi
}

day_has_unfinished() {
  local idx=$1
  local i=$((idx + 1))
  while [[ $i -lt ${#LINES[@]} && -n "${LINES[$i]}" ]]; do
    if [[ "${LINES[$i]}" == "[ ]"* ]]; then
      return 0
    fi
    i=$((i + 1))
  done
  return 1
}

print_unfinished_items() {
  local idx=$1
  local i=$((idx + 1))
  while [[ $i -lt ${#LINES[@]} && -n "${LINES[$i]}" ]]; do
    if [[ "${LINES[$i]}" == "[ ]"* ]]; then
      echo "    - ${LINES[$i]#\[ \] }"
    fi
    i=$((i + 1))
  done
}

log_day_block() {
  local idx=$1
  echo "== $(header_label "${LINES[$idx]}") =="
  local i=$((idx + 1))
  while [[ $i -lt ${#LINES[@]} && -n "${LINES[$i]}" ]]; do
    local line="${LINES[$i]}"
    if [[ "$line" == "[ ]"* ]]; then
      local desc="${line#\[ \] }"
      echo ""
      echo "$desc"
      read -rp "Completed? [y]es on-time / [e]arly / [l]ate / [s]kip / [q]uit: " ans
      case "$ans" in
        y|Y) LINES[$i]="[X] $desc"; changed=$((changed + 1)) ;;
        e|E) LINES[$i]="[*X] $desc"; changed=$((changed + 1)) ;;
        l|L) LINES[$i]="[X*] $desc"; changed=$((changed + 1)) ;;
        q|Q) QUIT=1; break ;;
        *) ;;
      esac
    else
      echo "  (already logged) $line"
    fi
    i=$((i + 1))
  done
  echo ""
}

TODAY_EPOCH=$(header_epoch "$TODAY_PATTERN")

day_indices=()
for i in "${!LINES[@]}"; do
  if [[ "${LINES[$i]}" =~ $DAY_HEADER_RE ]]; then
    day_indices+=("$i")
  fi
done

missing=()
for idx in "${day_indices[@]}"; do
  epoch=$(header_epoch "${LINES[$idx]}")
  if [[ -n "$epoch" && "$epoch" -lt "$TODAY_EPOCH" ]] && day_has_unfinished "$idx"; then
    missing+=("$idx")
  fi
done

if [[ ${#missing[@]} -gt 0 ]]; then
  echo "You have ${#missing[@]} day(s) with unfinished items:"
  for idx in "${missing[@]}"; do
    echo "  $(header_label "${LINES[$idx]}")"
    print_unfinished_items "$idx"
  done
  echo ""
  for idx in "${missing[@]}"; do
    log_day_block "$idx"
    if [[ $QUIT -eq 1 ]]; then
      break
    fi
  done
fi

if [[ $QUIT -eq 0 ]]; then
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

  log_day_block "$header_idx"
fi

if [[ $changed -gt 0 ]]; then
  printf '%s\n' "${LINES[@]}" > "$FILE.tmp"
  mv "$FILE.tmp" "$FILE"
  echo "Saved $changed update(s) to $FILE"
else
  echo "No changes made."
fi
