PREFIX  ?= $(HOME)/.local
BINDIR  := $(PREFIX)/bin
UNITDIR := $(HOME)/.config/systemd/user
UDEVDIR := /usr/lib/udev/rules.d

.PHONY: install uninstall udev status

install:
	install -Dm755 bin/tuxedo-touchpad $(BINDIR)/tuxedo-touchpad
	install -Dm644 systemd/tuxedo-touchpad.service $(UNITDIR)/tuxedo-touchpad.service
	systemctl --user daemon-reload
	systemctl --user enable tuxedo-touchpad.service
	systemctl --user restart tuxedo-touchpad.service
	@echo
	@$(BINDIR)/tuxedo-touchpad status

# Only needed if tuxedo-touchpad-switch is not installed; it ships the same rule.
udev:
	sudo install -Dm644 udev/99-tuxedo-touchpad-hidraw.rules $(UDEVDIR)/99-tuxedo-touchpad-hidraw.rules
	sudo udevadm control --reload && sudo udevadm trigger

uninstall:
	-systemctl --user disable --now tuxedo-touchpad.service
	rm -f $(UNITDIR)/tuxedo-touchpad.service $(BINDIR)/tuxedo-touchpad
	systemctl --user daemon-reload

status:
	systemctl --user status tuxedo-touchpad.service --no-pager
