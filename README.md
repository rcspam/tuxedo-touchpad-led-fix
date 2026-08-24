# tuxedo-touchpad-led-fix

Makes the touchpad disabled-LED work again on KDE Plasma Wayland, on TUXEDO
laptops with a Uniwill touchpad.

You double-tap the top-left corner, the touchpad goes off, you get the OSD, and
the little light stays dark. That's what this fixes.

## Tested on exactly one machine

- TUXEDO InfinityBook Pro Gen8 (MK2), board `PH6PG01_PH6PG71`
- Touchpad `UNIW0001:00 093A:0274`, I2C, driven by `hid-multitouch`
- TUXEDO OS, kernel 7.0.0-108029-tuxedo
- Plasma 6.6.5 on Wayland
- tuxedo-drivers 4.22.3, tuxedo-touchpad-switch 1.1.0

That's one laptop and one touchpad revision. A Pulse, a Stellaris, a Gen10 or a
non-TUXEDO Uniwill/TongFang machine may well behave differently, and I have no
way to check. The tool looks up the hidraw node and the switch report ID at
runtime instead of hard-coding them, so it has a decent chance of travelling —
but that's an argument, not evidence. Run `tuxedo-touchpad probe` first, and
tell me how it went either way.

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

The "fixed differently" part refers to the xkeyboard-config work that made the
toggle key behave on Wayland. That did get fixed. It just has nothing to do
with the LED.

Long version, with how each step was actually established:
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
```

`on` and `off` are about the touchpad, not the LED. The light is lit exactly
when the pad is off, they're the same pair of bits.

`on`/`off`/`toggle` go through KWin by default, so everything stays consistent
and you don't have to stop the daemon. Add `--raw` to write the HID report
directly — handy from a tty or when diagnosing, but then the daemon will pull
the firmware back in line within two seconds unless you stop it.

## Check your hardware first

Before anything else, see whether the LED responds at all:

```
python3 -c 'import fcntl,os;fcntl.ioctl(os.open("/dev/hidraw0",os.O_WRONLY),0xC0024806,bytearray([7,0x00]))'
```

Light comes on, pad goes dead. Same line with `0x03` puts it back. If that does
nothing, your report ID is probably not 7 — run `probe`, it finds it for you.

## Not covered

X11. The LED already works there, so the service refuses to start outside a
KDE Wayland session. I never worked out *why* it works on X11 with the KDE code
gone from the package; if you know, tell me.

GNOME, Budgie, tty. GNOME on X11 is still handled by the official package.
GNOME on Wayland is in the same hole KDE was, but I can't test it.

## Credits

Diagnosed and written with Claude (Anthropic), in about a quarter of an hour of
actual work: reading the HID report descriptor, tracing the corner tap through
libinput to KWin, digging up the commit that removed KDE support, and writing
the daemon.

`Xartos/tuxedo-touchpad-switch`, branch `add-touchpad-toggle-update`, got to a
standalone toggle binary two years earlier. Different approach, same problem.

The udev rule is TUXEDO's, from `tuxedo-touchpad-switch`.

## Licence

GPL-3.0-or-later. The udev rule is TUXEDO's, from `tuxedo-touchpad-switch`,
same licence.
