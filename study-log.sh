#!/usr/bin/env bash
set -euo pipefail

FILE="${1:?Usage: study-log.sh <path-to-schedule-file> [--date \"Mon 8/24\"|--early]}"

DATE_OVERRIDE=""
EARLY_MODE=0
if [[ "${2:-}" == "--date" ]]; then
  DATE_OVERRIDE="${3:?--date requires an argument like '8/24' or 'Mon 8/24'}"
elif [[ "${2:-}" == "--early" ]]; then
  EARLY_MODE=1
fi

YEAR=$(date +%Y)
DAY_HEADER_RE='^(Mon|Tue|Wed|Thu|Fri|Sat|Sun) ([0-9]{1,2})/([0-9]{1,2})'

if [[ -n "$DATE_OVERRIDE" ]]; then
  if [[ "$DATE_OVERRIDE" =~ ^([0-9]{1,2})/([0-9]{1,2})$ ]]; then
    WEEKDAY=$(date -d "$YEAR-${BASH_REMATCH[1]}-${BASH_REMATCH[2]}" +%a)
    TODAY_PATTERN="$WEEKDAY $DATE_OVERRIDE"
  else
    TODAY_PATTERN="$DATE_OVERRIDE"
  fi
else
  WEEKDAY=$(date +%a)
  MONTHDAY=$(date +%-m/%-d)
  TODAY_PATTERN="$WEEKDAY $MONTHDAY"
fi

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
  local mode=$2  # "late" for catch-up items, "ontime" for today's items, "early" for ahead-of-schedule items
  echo "== $(header_label "${LINES[$idx]}") =="
  local i=$((idx + 1))
  while [[ $i -lt ${#LINES[@]} && -n "${LINES[$i]}" ]]; do
    local line="${LINES[$i]}"
    if [[ "$line" == "[ ]"* ]]; then
      local desc="${line#\[ \] }"
      echo ""
      echo "$desc"
      read -rp "Completed? [y]es / [s]kip / [q]uit: " ans
      case "$ans" in
        y|Y)
          if [[ "$mode" == "late" ]]; then
            LINES[$i]="[x] $desc — late"
          elif [[ "$mode" == "early" ]]; then
            LINES[$i]="[x] $desc — early"
          else
            LINES[$i]="[x] $desc"
          fi
          changed=$((changed + 1))
          ;;
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

if [[ $EARLY_MODE -eq 1 ]]; then
  upcoming=()
  for idx in "${day_indices[@]}"; do
    epoch=$(header_epoch "${LINES[$idx]}")
    if [[ -n "$epoch" && "$epoch" -gt "$TODAY_EPOCH" ]] && day_has_unfinished "$idx"; then
      upcoming+=("$idx")
    fi
  done

  if [[ ${#upcoming[@]} -eq 0 ]]; then
    echo "No upcoming unfinished items to log early."
  else
    first=1
    for idx in "${upcoming[@]}"; do
      if [[ $first -eq 0 ]]; then
        read -rp "Continue to $(header_label "${LINES[$idx]}")? [y/n]: " cont
        if [[ "$cont" != "y" && "$cont" != "Y" ]]; then
          break
        fi
      fi
      first=0
      echo "  $(header_label "${LINES[$idx]}")"
      print_unfinished_items "$idx"
      echo ""
      log_day_block "$idx" "early"
      if [[ $QUIT -eq 1 ]]; then
        break
      fi
    done
  fi
else
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
      log_day_block "$idx" "late"
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

    log_day_block "$header_idx" "ontime"
  fi
fi

if [[ $changed -gt 0 ]]; then
  printf '%s\n' "${LINES[@]}" > "$FILE.tmp"
  mv "$FILE.tmp" "$FILE"
  echo "Saved $changed update(s) to $FILE"
else
  echo "No changes made."
fi
