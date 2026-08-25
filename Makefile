PREFIX  ?= $(HOME)/.local
BINDIR  := $(PREFIX)/bin
UNITDIR := $(HOME)/.config/systemd/user
UDEVDIR := /usr/lib/udev/rules.d

# Machine-wide install. The daemon still runs once per session, because it
# needs that session's bus to reach KWin, so this installs one copy of the
# binary and enables the user unit for every account instead of running
# anything as root.
SYSPREFIX  ?= /usr/local
SYSBINDIR  := $(SYSPREFIX)/bin
SYSUNITDIR := /etc/systemd/user

.PHONY: install install-system uninstall uninstall-system udev status

install:
	install -Dm755 bin/tuxedo-touchpad $(BINDIR)/tuxedo-touchpad
	install -Dm644 systemd/tuxedo-touchpad.service $(UNITDIR)/tuxedo-touchpad.service
	systemctl --user daemon-reload
	systemctl --user enable tuxedo-touchpad.service
	systemctl --user restart tuxedo-touchpad.service
	@echo
	@$(BINDIR)/tuxedo-touchpad status

# The shipped unit points at ~/.local/bin through %h, which means nothing for a
# unit in /etc, so the ExecStart line is rewritten on the way in.
install-system:
	sudo install -Dm755 bin/tuxedo-touchpad $(SYSBINDIR)/tuxedo-touchpad
	sed 's|^ExecStart=.*|ExecStart=$(SYSBINDIR)/tuxedo-touchpad daemon|' \
	    systemd/tuxedo-touchpad.service \
	  | sudo install -Dm644 /dev/stdin $(SYSUNITDIR)/tuxedo-touchpad.service
	sudo systemctl --global enable tuxedo-touchpad.service
	@echo
	@if [ -e $(UNITDIR)/tuxedo-touchpad.service ] || [ -e $(BINDIR)/tuxedo-touchpad ]; then \
	  echo 'Your own copy still shadows the system one: systemd prefers'; \
	  echo '$(UNITDIR), and $(BINDIR) comes first in PATH.'; \
	  echo "Run 'make uninstall' to drop it, then log out and back in."; \
	else \
	  echo 'Installed for every account. Each one picks it up at its next login.'; \
	fi

# Only needed if tuxedo-touchpad-switch is not installed; it ships the same rule.
udev:
	sudo install -Dm644 udev/99-tuxedo-touchpad-hidraw.rules $(UDEVDIR)/99-tuxedo-touchpad-hidraw.rules
	sudo udevadm control --reload && sudo udevadm trigger

uninstall:
	-systemctl --user disable --now tuxedo-touchpad.service
	rm -f $(UNITDIR)/tuxedo-touchpad.service $(BINDIR)/tuxedo-touchpad
	systemctl --user daemon-reload

uninstall-system:
	-sudo systemctl --global disable tuxedo-touchpad.service
	sudo rm -f $(SYSUNITDIR)/tuxedo-touchpad.service $(SYSBINDIR)/tuxedo-touchpad

status:
	systemctl --user status tuxedo-touchpad.service --no-pager
