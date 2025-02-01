TARGET = xdpyprobe

RM = rm -f

CPPFLAGS = -MMD
CFLAGS = -Wall -Werror -std=gnu11 -Os -fomit-frame-pointer
LDFLAGS = -fuse-ld=lld -static -Wl,--strip-all
LDLIBS = -lX11 -lxcb -lXau -lXdmcp

SOURCES = xdpyprobe.c
OBJECTS = $(patsubst %.c, %.o, $(SOURCES))
DEPENDS = $(OBJECTS:.o=.d)

$(TARGET): $(OBJECTS)
	$(CC) $(LDFLAGS) $(OBJECTS) $(LDLIBS) -o $@

clean:
	-$(RM) $(OBJECTS)
	-$(RM) $(TARGET)
	-$(RM) $(DEPENDS)

-include $(DEPENDS)
