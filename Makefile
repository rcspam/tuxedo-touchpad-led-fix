PREFIX  ?= $(HOME)/.local
BINDIR  := $(PREFIX)/bin
UNITDIR := $(HOME)/.config/systemd/user
UDEVDIR := /usr/lib/udev/rules.d

.PHONY: install uninstall udev status

install:
	install -Dm755 bin/tuxedo-touchpad-led $(BINDIR)/tuxedo-touchpad-led
	install -Dm644 systemd/kde-touchpad-led.service $(UNITDIR)/kde-touchpad-led.service
	systemctl --user daemon-reload
	systemctl --user enable --now kde-touchpad-led.service
	@echo
	@$(BINDIR)/tuxedo-touchpad-led status

# Only needed if tuxedo-touchpad-switch is not installed; it ships the same rule.
udev:
	sudo install -Dm644 udev/99-tuxedo-touchpad-hidraw.rules $(UDEVDIR)/99-tuxedo-touchpad-hidraw.rules
	sudo udevadm control --reload && sudo udevadm trigger

uninstall:
	-systemctl --user disable --now kde-touchpad-led.service
	rm -f $(UNITDIR)/kde-touchpad-led.service $(BINDIR)/tuxedo-touchpad-led
	systemctl --user daemon-reload

status:
	systemctl --user status kde-touchpad-led.service --no-pager
