TARGET = microphone
PKG_CONFIG ?= pkg-config
PACKAGES = glib-2.0 opus nestegg

CFLAGS = -std=c11 -Wall -Wextra -Werror -Os -fomit-frame-pointer -ffunction-sections -fdata-sections
LDFLAGS += -static -Wl,--gc-sections -Wl,--strip-all

NATIVE_TARGET = microphone-native
NATIVE_CFLAGS ?= -std=c11 -Wall -Wextra -Werror -O0 -g3
NATIVE_CPPFLAGS ?= $(shell $(PKG_CONFIG) --cflags $(PACKAGES))
NATIVE_LDFLAGS ?=
NATIVE_LDLIBS ?= $(shell $(PKG_CONFIG) --libs $(PACKAGES))

all: $(TARGET)

$(TARGET): microphone.c Makefile
	$(CC) $(CPPFLAGS) $(CFLAGS) $(shell $(PKG_CONFIG) --cflags $(PACKAGES)) \
		$(LDFLAGS) $< -Wl,--start-group \
		$(shell $(PKG_CONFIG) --static --libs $(PACKAGES)) -Wl,--end-group -o $@

native: $(NATIVE_TARGET)

# Use host headers and libraries without the production static-linking flags.
$(NATIVE_TARGET): microphone.c Makefile
	$(CC) $(CPPFLAGS) $(NATIVE_CPPFLAGS) $(NATIVE_CFLAGS) $(NATIVE_LDFLAGS) \
		$< $(NATIVE_LDLIBS) -o $@

clean:
	$(RM) $(TARGET) $(NATIVE_TARGET)

.PHONY: all native clean
