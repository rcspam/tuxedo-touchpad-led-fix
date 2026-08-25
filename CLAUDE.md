# Working on this repo

One Python file does everything: `bin/tuxedo-touchpad`. Subcommands `daemon`,
`on`, `off`, `toggle`, `status`, `probe`, `check`. There is no package, no
dependency beyond PyGObject, and the daemon and the CLI share the same code so
device discovery is written once.

`on` and `off` refer to the **touchpad**, not the LED. The light is lit exactly
when the pad is off, they are the same pair of bits, and naming it the other
way round has already confused people once.

## Traps that cost real time. Do not rediscover them.

**The switch report ID is not what a naive descriptor parse returns.** On the
PH6PG01 pad the `REPORT_ID` item comes *after* the two switch usages, so a
parser that returns the ID current when it first sees `Surface Switch` yields
the previous group, which is Input Mode. Writing `0x00` there flips the pad
into mouse-emulation mode: the LED does not move and the events quietly
relocate to the other evdev node, which makes the whole thing look like it
worked backwards. Accumulate usages, take the report ID at the closing
`FEATURE` item. Never hard-code the number, it differs between revisions.

**Everything about this touchpad exists twice.** Two evdev nodes, `event4`
"… Mouse" and `event5` "… Touchpad", plus two KWin objects to match, all four
carrying `UNIW0001`. Reading the wrong node gives zero events and looks like a
dead device. Matching KWin objects on the vendor string alone picks the mouse,
so the D-Bus call succeeds and does nothing visible. Always require `Touchpad`
in the name as well.

**A GLib callback must never let an exception escape, whatever its type.** One
did, after a resume: KWin is away for a few seconds, `_find()` returned None,
the next poll called `get(None, …)` and raised `TypeError` rather than the
`GLib.Error` being caught. GLib removed the timeout source, and the daemon then
sat there doing nothing while systemd still reported it `active`. `sync()` now
swallows everything and always returns True. A service being active proves
nothing, which is why every transition is logged.

**A mirror that never looks at what it mirrors will drift.** `sync()` compared
KWin against its own memory of what it had last written, and nothing ever read
the firmware back. Anything else touching the same report, `--raw` and a resume
included, left the pad disabled with the daemon certain it had done its job:
LED lit, pointer dead, journal empty, README promising the opposite. The poll
now reads the report and rewrites only on a genuine difference. Do not delete
that read to save an ioctl. It costs 0.86 ms and it is the only thing making
the documented behaviour true.

**`write()` on a hidraw node is not the same as a feature report.** A plain
write sends an *output* report; the device accepts it without complaint and
ignores it. Only `ioctl(HIDIOCSFEATURE)` reaches the switch. That silent
success is a good way to waste an hour.

## Before committing

```
python3.11 -m py_compile bin/tuxedo-touchpad
python3.12 -m py_compile bin/tuxedo-touchpad
```

Both, every time. An f-string with a backslash inside the expression is a
SyntaxError before 3.12: the file failed to parse at all on Debian 12 and
Ubuntu 22.04, so the tool did not even start there. Nothing in CI catches this
yet.

Then exercise it for real, the daemon has to be restarted to pick up changes:

```
make install                  # this restarts the service, enable --now does not
tuxedo-touchpad off && sleep 2 && tuxedo-touchpad status
tuxedo-touchpad on  && sleep 2 && tuxedo-touchpad status
journalctl --user -u tuxedo-touchpad.service -n 20
```

`check` refuses to run while the daemon is up. Stop it first when testing that
path.

## Reports coming in from other hardware

The whole point of `check` is that this was only ever tested on one laptop.
When someone posts a block from it, add their machine to the table in the
README, whether the LED worked or not. A failure on a Stellaris is worth as
much as a success: it tells us the report values or the LED wiring differ.

If a report shows a different report ID, that is expected and already handled.
If it shows the write being accepted but no LED, that is new and interesting:
it would mean the LED has a second control path, probably EC-side. There is a
lead about that in `docs/FINDINGS.md`.

## Prose

README and FINDINGS are written to be read by a person who is annoyed and
looking for an answer, not by a documentation reader. Short paragraphs, no em
dashes, no bullet lists where a sentence does, and no closing every paragraph
on a clipped three-word beat. If a section reads like it was generated, rewrite
it.

Code comments explain *why*, especially where the code looks wrong: the
descriptor parser, the double device, the exception handling. Those are the
places someone will try to "simplify" and reintroduce a bug.
