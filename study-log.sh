#!/usr/bin/env bash
set -euo pipefail

STUDY_TRACKER_CONFIG="${STUDY_TRACKER_CONFIG:-$HOME/.study-trackerrc}"
if [[ -f "$STUDY_TRACKER_CONFIG" ]]; then
  # shellcheck disable=SC1090
  source "$STUDY_TRACKER_CONFIG"
fi

print_help() {
  cat <<'EOF'
Usage: study-log.sh <path-to-schedule-file> [--log] [--date <date>|<date> <date>|<N>]

Modes:
  (no flags)            Read-only status snapshot: progress, pace
                        (Behind/Ahead/On track), overdue, today, and
                        next up.
  --log                 Interactive mode: catch up on overdue days, log
                        today, then offers to log ahead into upcoming
                        days.
  --date <M/D>          Snapshot a single day, e.g. --date "9/8".
  --date <M/D> <M/D>    Snapshot an inclusive date range,
                        e.g. --date "9/8" "9/12".
  --date <N>            Snapshot the next N days starting today,
                        e.g. --date 7.
                        (--date cannot be combined with --log.)

  -h, --help            Show this help and exit.

See README.md for full details.
EOF
}

for arg in "$@"; do
  if [[ "$arg" == "--help" || "$arg" == "-h" ]]; then
    print_help
    exit 0
  fi
done

FILE="${1:?Usage: study-log.sh <path-to-schedule-file> [--log] [--date <date>|<date> <date>|<N>]}"
shift

LOG_MODE=0
DATE_MODE=0
DATE_ARG1=""
DATE_ARG2=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --log) LOG_MODE=1; shift ;;
    --date)
      DATE_MODE=1
      DATE_ARG1="${2:?--date requires a date (e.g. 9/8), two dates for a range (e.g. 9/8 9/12), or a number of days (e.g. 7)}"
      if [[ "$DATE_ARG1" =~ ^[0-9]{1,2}/[0-9]{1,2}$ && -n "${3:-}" && "$3" =~ ^[0-9]{1,2}/[0-9]{1,2}$ ]]; then
        DATE_ARG2="$3"
        shift 3
      else
        shift 2
      fi
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ $DATE_MODE -eq 1 && $LOG_MODE -eq 1 ]]; then
  echo "--date cannot be combined with --log" >&2
  exit 1
fi

YEAR=$(date +%Y)
DAY_HEADER_RE='^(Mon|Tue|Wed|Thu|Fri|Sat|Sun) ([0-9]{1,2})/([0-9]{1,2})'

WEEKDAY=$(date +%a)
MONTHDAY=$(date +%-m/%-d)
TODAY_PATTERN="$WEEKDAY $MONTHDAY"

mapfile -t LINES < "$FILE"

changed=0
QUIT=0

header_epoch() {
  local line="$1"
  if [[ "$line" =~ $DAY_HEADER_RE ]]; then
    date -d "$YEAR-${BASH_REMATCH[2]}-${BASH_REMATCH[3]}" +%s
  fi
}

date_str_epoch() {
  local mmdd="$1"
  if [[ "$mmdd" =~ ^([0-9]{1,2})/([0-9]{1,2})$ ]]; then
    date -d "$YEAR-${BASH_REMATCH[1]}-${BASH_REMATCH[2]}" +%s
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

html_escape() {
  local s="$1"
  s="${s//&/&amp;}"
  s="${s//</&lt;}"
  s="${s//>/&gt;}"
  printf '%s' "$s"
}

render_schedule_html() {
  cat <<HTML_HEAD
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<meta name="robots" content="noindex">
<title>Study Tracker - Philip Abbyad</title>
<style>
  :root {
    --color-bg: #0c0c0c;
    --color-text: #e8e8e8;
    --color-text-dim: #888888;
    --color-border: #2a2a2a;
    --color-accent: #5f9ea0;
    --color-open: #666666;
    --color-done: #7fbf7f;
    --color-ontime: #7fbf7f;
    --color-early: #5f9ea0;
    --color-late: #d9a441;
    --font-mono: ui-monospace, "Cascadia Code", "SF Mono", Consolas, monospace;
    --font-body: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
    --max-width: 40rem;
  }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: var(--font-body); background: var(--color-bg); color: var(--color-text); padding: 1.5rem; line-height: 1.6; }
  main { max-width: var(--max-width); margin: 0 auto; }
  h1 { font-family: var(--font-mono); font-size: 1.5rem; margin-bottom: 0.25rem; }
  p.meta { color: var(--color-text-dim); font-size: 0.9rem; margin-bottom: 2rem; }
  .day { margin-bottom: 1.75rem; }
  .day-header { font-family: var(--font-mono); text-transform: uppercase; letter-spacing: 0.08em; font-size: 0.85rem;
                color: var(--color-text-dim); border-bottom: 1px solid var(--color-border); padding-bottom: 0.35rem; margin-bottom: 0.5rem; }
  .item { font-family: var(--font-mono); font-size: 0.95rem; padding: 0.15rem 0; }
  .item-open   { color: var(--color-open); }
  .item-done   { color: var(--color-done); }
  .item-ontime { color: var(--color-ontime); }
  .item-early  { color: var(--color-early); }
  .item-late   { color: var(--color-late); }
  footer { margin-top: 2rem; color: var(--color-text-dim); font-size: 0.8rem; }
  a { color: var(--color-accent); }
</style>
</head>
<body>
<main>
  <h1>Study Tracker</h1>
  <p class="meta">Last updated: $(date '+%Y-%m-%d %H:%M %Z')</p>
HTML_HEAD

  local line day_open=0 state desc class
  for line in "${LINES[@]}"; do
    if [[ -z "$line" ]]; then
      [[ $day_open -eq 1 ]] && echo "  </div>"
      day_open=0
      continue
    fi
    if [[ "$line" =~ $DAY_HEADER_RE ]]; then
      [[ $day_open -eq 1 ]] && echo "  </div>"
      echo "  <div class=\"day\">"
      echo "    <div class=\"day-header\">$(html_escape "$line")</div>"
      day_open=1
      continue
    fi
    [[ $day_open -eq 1 ]] || continue
    if [[ "$line" =~ ^\[([\ xX])\][[:space:]](.*)$ ]]; then
      state="${BASH_REMATCH[1]}"
      desc="${BASH_REMATCH[2]}"
      if [[ "$state" == " " ]]; then
        class=item-open
      else
        case "$desc" in
          *"— completed on-time") class=item-ontime ;;
          *"— completed late") class=item-late ;;
          *"— completed early") class=item-early ;;
          *) class=item-done ;;
        esac
      fi
      echo "    <div class=\"item $class\">$(html_escape "$desc")</div>"
    else
      echo "    <div class=\"item\">$(html_escape "$line")</div>"
    fi
  done
  [[ $day_open -eq 1 ]] && echo "  </div>"

  cat <<'HTML_FOOT'
  <footer>Generated automatically by study-log.sh</footer>
</main>
</body>
</html>
HTML_FOOT
}

publish_to_site() {
  local site_dir="${STUDY_TRACKER_SITE_DIR:-$HOME/personal-website}"
  local page_dir="$site_dir/study-tracker"
  local page_file="$page_dir/index.html"

  if [[ ! -d "$site_dir/.git" ]]; then
    echo "Warning: site dir '$site_dir' is not a git repo; skipping site publish." >&2
    return 0
  fi

  if ! mkdir -p "$page_dir" 2>/dev/null; then
    echo "Warning: could not create '$page_dir'; skipping site publish." >&2
    return 0
  fi

  if ! render_schedule_html > "$page_file.tmp" 2>/dev/null; then
    echo "Warning: failed to render study-tracker page; skipping site publish." >&2
    rm -f "$page_file.tmp"
    return 0
  fi
  mv "$page_file.tmp" "$page_file"

  (
    cd "$site_dir" || exit 1
    git add study-tracker/index.html || exit 1
    if git diff --cached --quiet; then
      exit 0
    fi
    git commit -q -m "Update study tracker page" || exit 1
    git push -q || exit 1
  ) || echo "Warning: failed to publish study-tracker page (git add/commit/push error). Local schedule log was still saved successfully; will retry on next run." >&2

  return 0
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

    if [[ $QUIT -eq 0 ]]; then
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
    publish_to_site
  else
    echo "No changes made."
  fi
elif [[ $DATE_MODE -eq 1 ]]; then
  if [[ "$DATE_ARG1" =~ ^[0-9]+$ ]]; then
    range_start=$TODAY_EPOCH
    range_end=$((TODAY_EPOCH + (DATE_ARG1 - 1) * 86400))
    range_label="the next $DATE_ARG1 day(s)"
  else
    range_start=$(date_str_epoch "$DATE_ARG1")
    range_end=$(date_str_epoch "${DATE_ARG2:-$DATE_ARG1}")
    if [[ $range_start -gt $range_end ]]; then
      range_tmp=$range_start; range_start=$range_end; range_end=$range_tmp
    fi
    range_label="$DATE_ARG1${DATE_ARG2:+ – $DATE_ARG2}"
  fi

  found=0
  for idx in "${day_indices[@]}"; do
    epoch=$(header_epoch "${LINES[$idx]}")
    if [[ -n "$epoch" && "$epoch" -ge "$range_start" && "$epoch" -le "$range_end" ]]; then
      echo "$(header_label "${LINES[$idx]}")"
      print_day_items "$idx"
      echo ""
      found=1
    fi
  done
  if [[ $found -eq 0 ]]; then
    echo "No entries for $range_label."
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
