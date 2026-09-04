#!/usr/bin/env bash
set -euo pipefail

FILE="${1:?Usage: study-log.sh <path-to-schedule-file> [--log [--date \"Mon 8/24\"]]}"
shift

LOG_MODE=0
DATE_OVERRIDE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --log) LOG_MODE=1; shift ;;
    --date) DATE_OVERRIDE="${2:?--date requires an argument like '8/24' or 'Mon 8/24'}"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ -n "$DATE_OVERRIDE" && $LOG_MODE -eq 0 ]]; then
  echo "--date requires --log" >&2
  exit 1
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

day_has_completed() {
  local idx=$1
  local i=$((idx + 1))
  while [[ $i -lt ${#LINES[@]} && -n "${LINES[$i]}" ]]; do
    if [[ "${LINES[$i]}" == "[x]"* ]]; then
      return 0
    fi
    i=$((i + 1))
  done
  return 1
}

print_day_items() {
  local idx=$1
  local i=$((idx + 1))
  while [[ $i -lt ${#LINES[@]} && -n "${LINES[$i]}" ]]; do
    echo "    ${LINES[$i]}"
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
            LINES[$i]="[x] $desc — completed late"
          elif [[ "$mode" == "early" ]]; then
            LINES[$i]="[x] $desc — completed early"
          else
            LINES[$i]="[x] $desc — completed on-time"
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

build_upcoming() {
  upcoming=()
  for idx in "${day_indices[@]}"; do
    epoch=$(header_epoch "${LINES[$idx]}")
    if [[ -n "$epoch" && "$epoch" -gt "$TODAY_EPOCH" ]] && day_has_unfinished "$idx"; then
      upcoming+=("$idx")
    fi
  done
}

walk_upcoming() {
  local first=1
  for idx in "${upcoming[@]}"; do
    if [[ $first -eq 0 ]]; then
      read -rp "Continue to $(header_label "${LINES[$idx]}")? [y/n]: " cont
      if [[ "$cont" != "y" && "$cont" != "Y" ]]; then
        break
      fi
    fi
    first=0
    echo "  $(header_label "${LINES[$idx]}")"
    print_day_items "$idx"
    echo ""
    log_day_block "$idx" "early"
    if [[ $QUIT -eq 1 ]]; then
      break
    fi
  done
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

if [[ $LOG_MODE -eq 1 ]]; then
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "You have ${#missing[@]} day(s) with unfinished items:"
    for idx in "${missing[@]}"; do
      echo "  $(header_label "${LINES[$idx]}")"
      print_day_items "$idx"
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

    if day_has_unfinished "$header_idx"; then
      log_day_block "$header_idx" "ontime"
    else
      echo "$(header_label "${LINES[$header_idx]}") — already fully logged."
    fi

    if [[ $QUIT -eq 0 && -z "$DATE_OVERRIDE" ]]; then
      build_upcoming
      if [[ ${#upcoming[@]} -gt 0 ]]; then
        walk_upcoming
      fi
    fi
  fi

  if [[ $changed -gt 0 ]]; then
    for i in "${!LINES[@]}"; do
      if [[ "${LINES[$i]}" == "Last updated:"* ]]; then
        LINES[$i]="Last updated: $(date +%-m/%-d/%Y)"
        break
      fi
    done
    printf '%s\n' "${LINES[@]}" > "$FILE.tmp"
    mv "$FILE.tmp" "$FILE"
    echo "Saved $changed update(s) to $FILE"
  else
    echo "No changes made."
  fi
else
  completed=0
  for idx in "${day_indices[@]}"; do
    if ! day_has_unfinished "$idx"; then
      completed=$((completed + 1))
    fi
  done
  total=${#day_indices[@]}

  ahead_days=0
  ahead_partial=0
  for idx in "${day_indices[@]}"; do
    epoch=$(header_epoch "${LINES[$idx]}")
    if [[ -n "$epoch" && "$epoch" -gt "$TODAY_EPOCH" ]]; then
      if day_has_completed "$idx" && ! day_has_unfinished "$idx"; then
        ahead_days=$((ahead_days + 1))
      elif day_has_completed "$idx"; then
        ahead_partial=1
      fi
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    pace="Behind by ${#missing[@]} day(s)"
  elif [[ $ahead_days -gt 0 ]]; then
    pace="Ahead by $ahead_days day(s)"
  elif [[ $ahead_partial -eq 1 ]]; then
    pace="Ahead"
  else
    pace="On track"
  fi

  echo "Progress: $completed of $total days completed ($((total - completed)) remaining) — $pace"
  echo ""

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Overdue (${#missing[@]} day(s)), oldest:"
    echo "  $(header_label "${LINES[${missing[0]}]}")"
    print_day_items "${missing[0]}"
    echo ""
  fi

  header_idx=-1
  for i in "${!LINES[@]}"; do
    if [[ "${LINES[$i]}" == "$TODAY_PATTERN"* ]]; then
      header_idx=$i
      break
    fi
  done

  echo "Today:"
  if [[ $header_idx -eq -1 ]]; then
    echo "  No entry for '$TODAY_PATTERN' in $FILE."
  elif day_has_unfinished "$header_idx"; then
    echo "  $(header_label "${LINES[$header_idx]}")"
    print_day_items "$header_idx"
  else
    echo "  $(header_label "${LINES[$header_idx]}") — already fully logged."
  fi
  echo ""

  build_upcoming
  echo "Next up:"
  if [[ ${#upcoming[@]} -gt 0 ]]; then
    echo "  $(header_label "${LINES[${upcoming[0]}]}")"
    print_day_items "${upcoming[0]}"
  else
    echo "  Nothing upcoming."
  fi
fi
