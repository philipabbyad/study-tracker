# study-tracker

A tiny interactive CLI for logging daily progress against a plain-text
study schedule doc, instead of hand-editing checkbox markers.

## Usage

```
./study-log.sh /path/to/schedule.txt
```

It finds today's date header (matching `Weekday M/D`, e.g. `Mon 8/24`) in
the file, then walks through each unchecked `[ ]` item for that day and
prompts:

```
[y]es / [s]kip / [q]uit
```

writing back `[x] <item> — completed on-time` on yes. `[s]kip` leaves the
item open to ask again later. Already-marked items are shown as "(already
logged)" and never re-prompted, so it's safe to run more than once a day.

**Catch-up:** before asking about today, it also scans every earlier day
header for unfinished (`[ ]`) items and walks through those first, oldest
first, using the same prompt — items completed here are written back as
`[x] <item> — completed late`, since they're being logged after the day
they were due. `q`/`Q` at any point (catch-up or today) stops the whole run
immediately, including skipping today's prompts.

If the schedule file has a header line starting with `Last updated:`, it's
automatically rewritten to today's actual date whenever a run saves any
changes — no manual upkeep needed to keep that line trustworthy.

**Logging ahead:** once today's entry has been handled — whether you
logged items, skipped them, or it was already fully checked off — the
script checks for unfinished (`[ ]`) items on any day *after* today. If
there are none, it ends quietly. If there are, it walks through them one
day at a time, oldest first, rather than dumping the whole list up front —
useful on a schedule with weeks or months of upcoming days. It shows the
next upcoming day's items and prompts through them with the same
`[y]es / [s]kip / [q]uit` prompt; once that day is done, it asks
`Continue to <next day>? [y/n]` before showing the next day's items, so you
can stop at a clean day boundary once you've caught up to wherever you
actually left off reading. `q`/`Q` during an item still stops immediately,
same as elsewhere. Completions are written back as
`[x] <item> — completed early`, so you can tell at a glance (and later,
when judging how well you planned your pace) which items were done ahead
of schedule.

To test, log a past/future day, or backfill a day you forgot, override
the date:

```
./study-log.sh /path/to/schedule.txt --date "Mon 8/24"
```

`--date` also accepts just the month/day (`--date "8/24"`) — the script
looks up which weekday that is in the schedule's year and matches on that.
`--date` is a standalone mode: it only logs the given day and doesn't
trigger the logging-ahead walk afterward.
