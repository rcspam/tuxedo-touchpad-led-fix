# tuxedo-touchpad-led-fix

[My hardware](#the-machine-i-have) ·
[Other machines — run `check`](#every-other-machine) ·
[Why it's broken](#why-its-broken) ·
[What this does](#what-this-does) ·
[Install](#install) ·
[Use](#use) ·
[Not covered](#not-covered) ·
[Credits](#credits)

Makes the touchpad disabled-LED work again on KDE Plasma Wayland, on TUXEDO
laptops with a Uniwill touchpad.

You double-tap the top-left corner, the touchpad goes off, you get the OSD, and
the little light stays dark. That's what this fixes.

## The machine I have

Everything here was measured and tested on one laptop:

- TUXEDO InfinityBook Pro Gen8 (MK2), board `PH6PG01_PH6PG71`
- Touchpad `UNIW0001:00 093A:0274`, I2C, driven by `hid-multitouch`
- HID switch report **7**
- TUXEDO OS, kernel 7.0.0-108029-tuxedo
- Plasma 6.6.5 on Wayland
- tuxedo-drivers 4.22.3, tuxedo-touchpad-switch 1.1.0

One laptop, one touchpad revision. That's the whole of my evidence.

## Every other machine

I have no idea what a Pulse, a Stellaris, a Gen10 or a non-TUXEDO
Uniwill/TongFang pad does. Two things vary between models: the hidraw node and
the **report ID** — mine is 7, yours may not be. The `0x00` / `0x03` values come
from the Microsoft precision-touchpad spec, so those should hold everywhere.

Rather than have people guess, there's a `check` command that works both of
them out on its own. No install, one file:

```
curl -O https://raw.githubusercontent.com/rcspam/tuxedo-touchpad-led-fix/master/bin/tuxedo-touchpad
python3 tuxedo-touchpad check
```

It scans every hidraw node for a Surface/Button Switch report, finds the report
ID, disables the pad for five seconds so you can watch the corner, puts it
back, then prints this:

```
machine   : TUXEDO InfinityBook Pro Gen8 (MK2), board PH6PG01_PH6PG71
kernel    : 7.0.0-108029-tuxedo
session   : wayland / KDE
touchpad  : UNIW0001:00 (i2c-UNIW0001:00)
report ID : 7
write     : 0x00 -> read back 0x00
result    : LED works
```

Open an issue and paste that in, whatever it says. A "LED did NOT light" on a
Stellaris is worth as much to me as a success — right now that list above has
exactly one machine in it.

### Is it safe to run on a machine I can't fix remotely?

That was the main thing on my mind writing it, since I can't test on your
hardware. What it does:

- reads the current value of the report **before** touching anything, and
  restores that exact value rather than assuming a default
- refuses to write to a report it cannot read back first
- checks the write actually took effect; if the device reports something else,
  it stops there instead of waiting five seconds
- restores in a `finally`, so Ctrl-C mid-test brings the pad back — tested by
  sending SIGINT during the window
- refuses to run at all if the daemon is up, since that would undo the test
- never guesses between several candidate devices, it asks

Needs write access to `/dev/hidraw*` — see `make udev` below if you don't have
`tuxedo-touchpad-switch` installed. It does **not** need PyGObject or a Plasma
session; only the daemon does. Runs on Python 3.11 and 3.12, both checked.

Worst case, if something goes really wrong: `python3 tuxedo-touchpad on --raw`
turns the pad back on, and a reboot resets the firmware anyway.

## Why it's broken

The LED belongs to the touchpad firmware. There's nothing for it in
`/sys/class/leds`, and the kernel has no say. The only way to light it is a HID
feature report, the Microsoft Surface Switch / Button Switch one.

The corner tap isn't a touchpad gesture either. The EC sees it, tuxedo-drivers
turns it into `KEY_F21`, xkeyboard-config maps that to `XF86TouchpadToggle`,
KDE's global shortcut catches it, and KWin disables the pad at the libinput
level. Nobody tells the firmware, so the light never comes on.

TUXEDO ship `tuxedo-touchpad-switch` to bridge exactly that gap. It used to
handle KDE. On 2025-08-27 the KDE code was deleted with the commit message
"Only run on GNOME X11 as KDE and GNOME Wayland are now fixed differently", and
the repo hasn't been touched since. The check in 1.1.0 is now `GNOME && x11`,
so on KDE it prints `Your desktop environment is not supported.` and exits in
about 13 ms, every login.

That "fixed differently" refers to the xkeyboard-config work that made the
toggle key behave on Wayland. That did get fixed. It just has nothing to do
with the LED.

Long version, with how each step was established and what I ruled out:
[docs/FINDINGS.md](docs/FINDINGS.md).

## What this does

A small daemon reads KWin's own view of the touchpad over D-Bus and writes it
into the firmware. That's it. The LED then follows the corner tap, the Fn key
and the System Settings toggle, because all three end up in the same place.

It mirrors state rather than remembering it, so it can't drift out of sync: it
resyncs at startup and every couple of seconds. Kill it and the touchpad comes
back on.

## Install

Needs Python 3, PyGObject (`python3-gi`), and a Plasma Wayland session.

```
make install
```

Installs to `~/.local/bin`, enables a systemd user service, prints the state.
No root, no system files.

If you don't have `tuxedo-touchpad-switch` installed, you also need the udev
rule so your user can write to the hidraw node:

```
make udev
```

Remove everything with `make uninstall`.

## Use

```
tuxedo-touchpad status         # touchpad, LED, KWin, service
tuxedo-touchpad off            # disable the touchpad, light comes on
tuxedo-touchpad on             # enable it again, light goes out
tuxedo-touchpad toggle
tuxedo-touchpad probe          # watch the reports while you tap the corner
tuxedo-touchpad check          # the compatibility test described above
```

`on` and `off` are about the touchpad, not the LED. The light is lit exactly
when the pad is off, they're the same pair of bits.

`on`/`off`/`toggle` go through KWin by default, so everything stays consistent
and you don't have to stop the daemon. Add `--raw` to write the HID report
directly — handy from a tty or when diagnosing, but then the daemon will pull
the firmware back in line within two seconds unless you stop it.

## Not covered

X11. The LED already works there, so the service refuses to start outside a
KDE Wayland session. I never worked out *why* it works on X11 with the KDE code
gone from the package; if you know, tell me.

GNOME, Budgie, tty. GNOME on X11 is still handled by the official package.
GNOME on Wayland is in the same hole KDE was, but I can't test it.

## Credits

Diagnosed and written with Claude (Anthropic), in about an hour of
actual work: reading the HID report descriptor, tracing the corner tap through
libinput to KWin, digging up the commit that removed KDE support, and writing
the daemon.

`Xartos/tuxedo-touchpad-switch`, branch `add-touchpad-toggle-update`, got to a
standalone toggle binary two years earlier. Different approach, same problem.

## Licence

GPL-3.0-or-later. The udev rule is TUXEDO's, from `tuxedo-touchpad-switch`,
same licence.
