# tuxedo-touchpad-led-fix

[My hardware](#the-machine-i-have) ·
[Why it's broken](#why-its-broken) ·
[What this does](#what-this-does) ·
[Install](#install) ·
[Other machines: run `check`](#every-other-machine) ·
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

So one laptop and one touchpad revision, which is not much to go on.

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
toggle key behave on Wayland, which did get fixed. It has no bearing on the
LED though, since nothing in xkeyboard-config talks to the touchpad firmware.

Long version, with how each step was established and what I ruled out:
[docs/FINDINGS.md](docs/FINDINGS.md).

## What this does

A small daemon reads KWin's own view of the touchpad over D-Bus and writes it
into the firmware. The LED then follows the corner tap, the Fn key and the
System Settings toggle, since all three end up in the same place.

It mirrors state rather than remembering it, so it can't drift out of sync: it
resyncs at startup and every couple of seconds. Kill it and the touchpad comes
back on.

## Install

Needs Python 3, PyGObject (`python3-gi`), and a Plasma Wayland session.

```
make install
```

Installs to `~/.local/bin`, enables a systemd user service and prints the
resulting state. Nothing goes outside your home directory and it never asks
for root.

If you don't have `tuxedo-touchpad-switch` installed, you also need the udev
rule so your user can write to the hidraw node:

```
make udev
```

Remove everything with `make uninstall`.

### For everyone on the machine

If several people log into the same laptop, install it once for all of them:

```
make install-system
```

The binary goes to `/usr/local/bin`, the unit to `/etc/systemd/user`, and
`systemctl --global enable` turns it on for every account, including ones
created later. Each account still gets its own daemon at login, because
reaching KWin means being on that session's bus. Nothing runs as root, and a
root service would not work anyway for the same reason.

This asks for sudo, and it takes effect at the next login rather than
immediately. If you had already run `make install`, remove your personal copy
with `make uninstall` first: systemd prefers a unit in `~/.config/systemd/user`
over the one in `/etc`, and `~/.local/bin` comes before `/usr/local/bin` in
PATH, so the old copy would quietly win. `make uninstall-system` undoes it.

One thing to know before you do this. The firmware is a single piece of
hardware and sessions are not. If someone stays logged in while another person
uses the machine, both daemons follow their own KWin and write the same report,
so the one in the background can switch off a touchpad the person in front is
using. Logging out properly is fine, the service stops with the graphical
session and puts the pad back on. It is fast user switching that bites, and the
official package has the same problem for the same reason: it autostarts once
per session too.

## Every other machine

I have no idea what a Pulse, a Stellaris, a Gen10 or a non-TUXEDO
Uniwill/TongFang pad does. Two things vary between models: the hidraw node and
the **report ID**. Mine is 7, yours may not be. The `0x00` / `0x03` values come
from the Microsoft precision-touchpad spec, so those should hold everywhere.

So instead of making people guess, `check` works both of them out by itself.
One file, nothing to install:

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
Stellaris tells me as much as a success. Right now that list above has
exactly one machine in it.

### Is it safe to run on a machine I can't fix remotely?

That was the thing I worried about most, since I can't test on your hardware
and a dead touchpad is a miserable thing to debug with only a keyboard.

Before it writes anything it reads the report back, and it refuses to touch a
report it couldn't read. Whatever value was there gets saved and put back at
the end, rather than assuming yours started at the same 0x03 mine did. The
restore sits in a `finally`, so an interrupted test still gives you your
touchpad back. I checked that by sending SIGINT halfway through the window.

After writing it reads again to confirm the device actually accepted it, and
gives up early if it didn't. If several devices look like candidates it asks
you which one instead of picking. And it won't start at all while the daemon
is running, because the daemon would quietly undo the test two seconds in.

Needs write access to `/dev/hidraw*`. See `make udev` above if you don't have
`tuxedo-touchpad-switch` installed. It does **not** need PyGObject or a Plasma
session; only the daemon does. Runs on Python 3.11 and 3.12, both checked.

Worst case, if something goes really wrong: `python3 tuxedo-touchpad on --raw`
turns the pad back on, and a reboot resets the firmware anyway.

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

`status` prints what the firmware says, what KWin says, and whether the service
is up. When those first two disagree it says so on a line of its own instead of
leaving you to compare them, which is the quickest way to tell a real fault from
a pad you switched off yourself and forgot about.

`on`/`off`/`toggle` go through KWin by default, so everything stays consistent
and you don't have to stop the daemon. Add `--raw` to write the HID report
directly. Handy from a tty or when diagnosing, but then the daemon will pull
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
standalone toggle binary two years before I did, going about it differently.

## Licence

GPL-3.0-or-later. The udev rule is TUXEDO's, from `tuxedo-touchpad-switch`,
same licence.
