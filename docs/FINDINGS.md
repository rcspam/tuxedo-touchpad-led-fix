# How this was worked out

Notes from the evening I spent chasing the LED, kept because the traps cost me
real time and the next person shouldn't pay twice. Everything here was measured
on an InfinityBook Pro Gen8 (MK2), `PH6PG01_PH6PG71`, TUXEDO OS, kernel
7.0.0-108029-tuxedo, Plasma 6.6.5 Wayland, tuxedo-drivers 4.22.3,
tuxedo-touchpad-switch 1.1.0.

## The LED is not a kernel LED

```
$ ls /sys/class/leds/
input25::capslock  input3::capslock  phy0-led
input25::numlock   input3::numlock   white:kbd_backlight
input25::scrolllock  input3::scrolllock
```

Nothing for the touchpad. It's driven by the pad's own firmware through a HID
feature report, and the only way in is `HIDIOCSFEATURE` on `/dev/hidraw*`.
`write()` won't do: that sends an *output* report, which the device accepts
without complaint and ignores. That silent success is a good way to waste half
an hour.

## The report ID is not the one a naive parser gives you

Parsing the report descriptor for the Surface Switch / Button Switch usages
(digitizer page `0x0D`, usages `0x57` and `0x58`):

```
FEATURE report 6 : Input Mode
FEATURE report 7 : Surface Switch, Button Switch     <- the one that drives the LED
FEATURE report 8 : Latency Mode
```

On this descriptor the `REPORT_ID` item comes **after** the two usages. If you
return the report ID that's current when you first see the usage, you get 6,
which is Input Mode. Writing `0x00` there flips the pad into mouse-emulation
mode: the LED doesn't move, and the events quietly relocate to the other evdev
node, which makes the whole thing look like it worked backwards. Accumulate
usages and take the report ID at the closing `FEATURE` item instead.

Values on report 7: `0x03` surface and button on, `0x00` both off. `0x00`
lights the LED.

## Everything about this pad exists twice

Two evdev nodes and two KWin objects, all four carrying `UNIW0001`:

| | mouse | touchpad |
|---|---|---|
| evdev | `event4` "... Mouse", relative | `event5` "... Touchpad", absolute |
| KWin | `/org/kde/KWin/InputDevice/event4` | `.../event5` |

Reading `event4` while the pad is in multitouch mode gives you nothing and
looks like a dead device. Matching KWin objects on the vendor string alone
picks the mouse, so you end up disabling something harmless and concluding your
D-Bus call failed. Both mistakes happened here.

## The corner double-tap is a keyboard event

`libinput debug-events` during a tap:

```
event13  KEYBOARD_KEY  KEY_F21 (191) pressed
event13  KEYBOARD_KEY  KEY_F21 (191) released
```

`event13` is "TUXEDO Keyboard", the input node created by the tuxedo-drivers
platform module, not the touchpad. In their source the constant is literally
`UNIWILL_OSD_TOUCHPADWORKAROUND`, and there's an `msleep(50)` so userspace can
tell it apart from the surrounding firmware chatter.

From there: xkeyboard-config maps F21 to `XF86TouchpadToggle`, KDE's
`ToggleTouchpad` global shortcut fires, KWin flips `enabled` on its
InputDevice object. No device on the machine declares `KEY_TOUCHPAD_TOGGLE`, so
don't go looking for it.

Measured during two taps:

```
[14.4s] KWin enabled : true -> false
[18.1s] KWin enabled : false -> true
report 7 : never changed
```

The compositor knows. The firmware doesn't. That's the whole bug.

## Why the official package does nothing on KDE

```
$ /usr/bin/tuxedo-touchpad-switch
Your desktop environment is not supported.
```

It autostarts through `/etc/xdg/autostart`, so `systemctl --user status
tuxedo-touchpad-switch` finds no such unit and tells you nothing. The generated
unit is `app-tuxedo\x2dtouchpad\x2dswitch@autostart.service`, and it's been
exiting 0 within 13 ms at every login.

The check in 1.1.0:

```c
else if (strstr(xdg_current_desktop, "GNOME") &&
         strstr(xdg_session_type, "x11")) {
```

`setup-kde.cpp` existed from January 2021 and got an "Add Plasma 6 support"
commit in May 2024. It was deleted on 2025-08-27:

> Only run on GNOME X11 as KDE and GNOME Wayland are now fixed differently

That's release 1.1.0. Nothing has been pushed to the repo since.

And even before that, KDE only ever worked on X11: the old code hooked the
`kded_touchpad` module, which isn't loaded in a Wayland session.

```
$ busctl --user call org.kde.kded6 /kded org.kde.kded loadedModules | tr ' ' '\n' | grep -i touch
(nothing)
```

Which matches every report I could find. People on KDE X11 had a working LED,
people on KDE Wayland never did.

## No signal to hang off

KWin emits no `PropertiesChanged` for its InputDevice objects. Verified by
monitoring the session bus while toggling the property: the value changes, no
signal appears. `org.kde.osdService` has a `touchpadEnabledChanged` method, but
nothing calls it on a toggle either.

So the daemon watches `~/.config/kcminputrc`, which KWin rewrites within
milliseconds of a toggle, and keeps a two-second poll as a backstop.

## Ruled out

**Latency mode.** There's an LKML patch by Werner Sembach adding
`MT_QUIRK_KEEP_LATENCY_ON_CLOSE`, because high latency breaks the corner
reactivation gesture on Uniwill pads. Not the problem here: report 8 reads
`0x00`, normal latency, and the gesture does reach the compositor.

**The mainline `uniwill-laptop` driver.** It's present in this kernel and the
board is in its DMI aliases, but it only exposes `fn_lock`,
`super_key_enable`, `touchpad_toggle_enable` and the lightbar. No touchpad LED.
It isn't even loaded, since the tuxedo-drivers DKMS stack claims the hardware
first.

## Still open

Why the LED works on X11. `kded_touchpad` explains it up to August 2025, but
the KDE code is gone now, so in principle X11 should be dark too. Possibly my
X11 memory predates the update.

There's also a [report on
r/tuxedocomputers](https://www.reddit.com/r/tuxedocomputers/comments/1rtj3c9/numlockw_status_causes_touchpad_led_to_pulse/)
where polling numlock state over evdev makes the touchpad LED pulse, and the
numlockw author concluded it's an EC bug. If the LED is also wired into the EC
keyboard-LED path, that could be a second channel and could explain the X11
behaviour. Untested here.
