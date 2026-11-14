PREFIX ?= $(HOME)/.local
DESTDIR ?=

BINDIR = $(DESTDIR)$(PREFIX)/bin
LIBDIR = $(DESTDIR)$(PREFIX)/lib/ghpkg
SHAREDIR = $(DESTDIR)$(PREFIX)/share/ghpkg

SCRIPTS = bin/ghpkg lib/*.sh integrations/omarchy/*.hook test/stubs/* test/helpers.bash

.PHONY: test lint install install-dev uninstall

test:
	bats test

lint:
	shellcheck -x $(SCRIPTS)

# Copies ghpkg into PREFIX (~/.local by default; /usr for the pacman package).
install:
	install -Dm755 bin/ghpkg $(BINDIR)/ghpkg
	install -Dm644 -t $(LIBDIR) lib/*.sh
	install -Dm755 -t $(SHAREDIR)/integrations/omarchy integrations/omarchy/*.hook
	if [ -d skill ]; then cd skill && find ghpkg -type f -exec install -Dm644 {} $(SHAREDIR)/skill/{} \; ; fi
	install -Dm644 LICENSE $(DESTDIR)$(PREFIX)/share/licenses/ghpkg/LICENSE

# Links ~/.local/bin/ghpkg to this checkout, for working on ghpkg itself.
install-dev:
	mkdir -p $(BINDIR)
	ln -sfn $(CURDIR)/bin/ghpkg $(BINDIR)/ghpkg

uninstall:
	rm -f $(BINDIR)/ghpkg
	rm -rf $(LIBDIR) $(SHAREDIR) $(DESTDIR)$(PREFIX)/share/licenses/ghpkg
