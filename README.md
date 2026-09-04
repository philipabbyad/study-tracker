# study-tracker

A tiny interactive CLI for tracking daily progress against a plain-text
study schedule doc, instead of hand-editing checkbox markers or opening
the file just to see what's left.

## Usage

```
./study-log.sh /path/to/schedule.txt
```

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

### `--date`: backfill a specific day

`--date` overrides which day header `--log` treats as "today," so you
can log or backfill a day other than the real current date — useful for
testing, or catching up a day you forgot about days later:

```
./study-log.sh /path/to/schedule.txt --log --date "Mon 8/24"
```

**`--date` always requires `--log`** — it's a modifier on `--log`, not a
mode of its own. Running `--date` by itself (no `--log`) is an error;
there's no read-only snapshot for an arbitrary date, only for today.

`--date` also accepts just the month/day (`--date "8/24"`) — the script
looks up which weekday that is in the schedule's year and matches on
that. With `--date`, `--log` logs *only* that one header: no catch-up
scan for other overdue days, and no logging-ahead walk into upcoming days
afterward — it's a narrowly-scoped, single-day operation.
