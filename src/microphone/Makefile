TARGET = microphone

RM = rm -f

NESTEGG_SRC ?= /tmp/nestegg/src/nestegg.c
NESTEGG_INC ?= /tmp/nestegg/include

CPPFLAGS = -I$(NESTEGG_INC)
CXXFLAGS = -std=c++17 -Wall -Wextra -Werror -Os -fomit-frame-pointer -ffunction-sections -fdata-sections
NESTEGG_CFLAGS = -std=c11 -Os -fomit-frame-pointer -ffunction-sections -fdata-sections -DNDEBUG
LDFLAGS = -pthread -Wl,--as-needed -static -Wl,--gc-sections -Wl,--strip-all
LDLIBS = -lopus -lm

OBJECTS = microphone.o nestegg.o

$(TARGET): $(OBJECTS)
	$(CXX) $(LDFLAGS) $(OBJECTS) $(LDLIBS) -o $@

microphone.o: microphone.cpp
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -c microphone.cpp -o $@

nestegg.o: $(NESTEGG_SRC)
	$(CC) $(NESTEGG_CFLAGS) -I$(NESTEGG_INC) -c $(NESTEGG_SRC) -o $@

clean:
	-$(RM) $(OBJECTS) $(TARGET)

.PHONY: clean
