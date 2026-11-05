TARGET = microphone
PKG_CONFIG ?= pkg-config

# These plugin archives are registered explicitly by microphone.c. pkg-config
# resolves their private target dependencies (GLib, Opus, Ogg, etc.) for static linking.
GST_PACKAGES = gstreamer-1.0 \
    gstcoreelements gstplayback \
    gsttypefindfunctions gstaudioconvert \
    gstaudioresample gstopus \
    gstogg gstmatroska

CPPFLAGS += -DMICROPHONE_STATIC_GSTREAMER $(shell $(PKG_CONFIG) --cflags $(GST_PACKAGES))
CFLAGS = -std=c11 -Wall -Wextra -Werror -Os -fomit-frame-pointer
LDFLAGS += -static -Wl,--gc-sections -Wl,--strip-all
LDLIBS = -Wl,--start-group $(shell $(PKG_CONFIG) --static --libs $(GST_PACKAGES)) -Wl,--end-group

NATIVE_TARGET = microphone-native
NATIVE_CFLAGS ?= -std=c11 -Wall -Wextra -Werror -O0 -g3
NATIVE_LDFLAGS ?=

all: $(TARGET)

$(TARGET): microphone.c Makefile
	$(CC) $(CPPFLAGS) $(CFLAGS) $(LDFLAGS) $< $(LDLIBS) -o $@

# Use distro headers and runtime plugins without the production static flags.
native: $(NATIVE_TARGET)

$(NATIVE_TARGET): microphone.c Makefile
	$(CC) $(NATIVE_CFLAGS) \
		$(shell $(PKG_CONFIG) --cflags gstreamer-1.0 glib-2.0) \
		$(NATIVE_LDFLAGS) $< $(shell $(PKG_CONFIG) --libs gstreamer-1.0) -o $@

clean:
	$(RM) $(TARGET) $(NATIVE_TARGET)

.PHONY: all native clean
