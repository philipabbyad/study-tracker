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
[y]es on-time / [e]arly / [l]ate / [s]kip / [q]uit
```

writing back `[X]`, `[*X]`, or `[X*]` accordingly (matching the doc's
existing legend). Already-marked items are shown as "(already logged)"
and never re-prompted, so it's safe to run more than once a day.

**Catch-up:** before asking about today, it also scans every earlier day
header for unfinished (`[ ]`) items and walks through those first, oldest
first, using the same prompt. `q`/`Q` at any point (catch-up or today)
stops the whole run immediately, including skipping today's prompts.

To test, log a past/future day, or backfill a day you forgot, override
the date:

```
./study-log.sh /path/to/schedule.txt --date "Mon 8/24"
```
