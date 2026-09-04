# study-tracker

A tiny interactive CLI for tracking daily progress against a plain-text
study schedule doc, instead of hand-editing checkbox markers or opening
the file just to see what's left.

## Usage

```
./study-log.sh /path/to/schedule.txt
```

Run `./study-log.sh --help` (or `-h`, with or without a file path) any
time for a quick in-terminal summary of the flags below.

See `example-schedule.txt` for a minimal example of the expected file
format (day headers, `[x]`/`[ ]` items, completion suffixes, and the
`Last updated:` line).

With no flags, it's read-only: a status snapshot printed to the terminal.
It never prompts and never writes to the file. It shows:

- **Progress** — `X of Y days completed (Z remaining)`, plus a pace label:
  `Behind by N day(s)` if any past day still has unfinished items
  (a partially-done overdue day counts the same as a fully untouched
  one — each is one day behind); otherwise `Ahead by N day(s)` if
  one or more *future* days are fully checked off, or just `Ahead` (no
  count) if a future day has some but not all items done; otherwise
  `On track`.
- **Overdue** (only if any past day still has unfinished `[ ]` items) — a
  count plus the full day (every item, done and open both — not just
  what's left) for just the single oldest overdue day, to avoid a wall
  of text if you've fallen far behind.
- **Today** — today's date header (matching `Weekday M/D`, e.g.
  `Mon 8/24`) with the full day's items (done and open both), or
  "already fully logged" if nothing's left, or "No entry for `<today>`"
  if the schedule has no header for today at all.
- **Next up** — the single nearest upcoming day that still has unfinished
  items, with its full item list (done and open both — handy when
  you've already knocked out a few of that day's items ahead of time),
  or "Nothing upcoming."

### `--date`: peek at a specific day or range

To check a day or span of days directly, without scrolling through the
Progress/Overdue/Today/Next-up snapshot, pass `--date`. It takes one of
three forms (plain `M/D`, no weekday prefix):

```
./study-log.sh /path/to/schedule.txt --date "9/8"          # just that day
./study-log.sh /path/to/schedule.txt --date "9/8" "9/12"   # that date range, inclusive
./study-log.sh /path/to/schedule.txt --date 7               # next 7 days, starting today
```

Each matching day header prints in full (done and open items both, same
as the other snapshot sections), in file order. There's no Progress/pace
line here — it's just a focused listing of the day(s) you asked for. If
nothing in the schedule falls in that date or range, it says so instead
of printing nothing. `--date` is snapshot-only: combining it with `--log`
is an error.

## Logging progress: `--log`

```
./study-log.sh /path/to/schedule.txt --log
```

`--log` is the interactive, write-enabled mode. It walks through each
unchecked `[ ]` item and prompts:

```
[y]es / [s]kip / [q]uit
```

writing back `[x] <item> — completed on-time` on yes. `[s]kip` leaves the
item open to ask again later. Already-marked items are shown as "(already
logged)" and never re-prompted, so it's safe to run more than once a day.

**Catch-up:** before asking about today, it also scans every earlier day
header for unfinished (`[ ]`) items and walks through those first, oldest
first, using the same prompt. Each overdue day is previewed with its full
item list (done and open both) before you're walked through it — items
completed here are written back as `[x] <item> — completed late`, since
they're being logged after the day they were due. `q`/`Q` at any point
(catch-up or today) stops the whole run immediately, including skipping
today's prompts.

If the schedule file has a header line starting with `Last updated:`, it's
automatically rewritten to today's actual date whenever a run saves any
changes — no manual upkeep needed to keep that line trustworthy.

**Logging ahead:** once today's entry has been handled — whether you
logged items, skipped them, or it was already fully checked off — the
script checks for unfinished (`[ ]`) items on any day *after* today. If
there are none, it ends quietly. If there are, it walks through them one
day at a time, oldest first, rather than dumping the whole list up front —
useful on a schedule with weeks or months of upcoming days. It shows the
next upcoming day's full item list (done and open both, so you can see
what you've already gotten ahead on) and prompts through the remaining
open items with the same `[y]es / [s]kip / [q]uit` prompt; once that day
is done, it asks
`Continue to <next day>? [y/n]` before showing the next day's items, so you
can stop at a clean day boundary once you've caught up to wherever you
actually left off reading. `q`/`Q` during an item still stops immediately,
same as elsewhere. Completions are written back as
`[x] <item> — completed early`, so you can tell at a glance (and later,
when judging how well you planned your pace) which items were done ahead
of schedule.
