PREFIX   ?= $(HOME)/.local
BUILDDIR ?= build
VALAC    ?= valac

SOURCES := $(wildcard src/*.vala)
PKGS    := --pkg glib-2.0 --pkg gio-2.0 --pkg gio-unix-2.0 --pkg x11 --pkg posix --pkg cairo --pkg gdk-pixbuf-2.0
VFLAGS  := --vapidir=vapi --pkg xextra $(PKGS) \
           -X -lX11 -X -lXrandr -X -lXinerama -X -lXdamage -X -lm -X -O2 -X -w --target-glib=2.80 \
           -X -DG_LOG_DOMAIN=\"Fenster\"

.PHONY: all clean install uninstall run-xephyr

all: $(BUILDDIR)/fenster

$(BUILDDIR)/fenster: $(SOURCES) vapi/xextra.vapi
	@mkdir -p $(BUILDDIR)
	$(VALAC) $(VFLAGS) $(SOURCES) -o $@

install: all
	install -Dm755 $(BUILDDIR)/fenster $(PREFIX)/bin/fenster

uninstall:
	rm -f $(PREFIX)/bin/fenster

run-xephyr: all
	./scripts/xephyr.sh

clean:
	rm -rf $(BUILDDIR)
