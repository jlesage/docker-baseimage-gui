TARGET = pulseaudio

RM = rm -f

CFLAGS = -std=gnu11 -Os -fomit-frame-pointer -ffunction-sections -fdata-sections
CFLAGS += -Ibuild -Ibuild/src -Isrc
CFLAGS += -DHAVE_CONFIG_H -D_GNU_SOURCE -D__INCLUDED_FROM_PULSE_AUDIO -D__PA_STATIC_MODULE

# For module-native-protocol-unix module.
CFLAGS += -DUSE_PROTOCOL_NATIVE -DUSE_UNIX_SOCKETS

LDFLAGS = -static -Wl,--strip-all -Wl,--gc-sections
LDLIBS = -lsndfile -lcap

SOURCES = \
	src/daemon/caps.c \
	src/daemon/cmdline.c \
	src/daemon/cpulimit.c \
	src/daemon/daemon-conf.c \
	src/daemon/dumpmodules.c \
	src/daemon/main.c \
	src/pulsecore/asyncmsgq.c \
	src/pulsecore/asyncq.c \
	src/pulsecore/aupdate.c \
	src/pulsecore/auth-cookie.c \
	src/pulsecore/authkey.c \
	src/pulsecore/bitset.c \
	src/pulsecore/card.c \
	src/pulsecore/cli-command.c \
	src/pulsecore/cli-text.c \
	src/pulsecore/client.c \
	src/pulsecore/core.c \
	src/pulsecore/core-error.c \
	src/pulsecore/core-format.c \
	src/pulsecore/conf-parser.c \
	src/pulsecore/core-scache.c \
	src/pulsecore/core-subscribe.c \
	src/pulsecore/core-rtclock.c \
	src/pulsecore/core-util.c \
	src/pulsecore/cpu.c \
	src/pulsecore/cpu-arm.c \
	src/pulsecore/cpu-orc.c \
	src/pulsecore/cpu-x86.c \
	src/pulsecore/device-port.c \
	src/pulsecore/dynarray.c \
	src/pulsecore/fdsem.c \
	src/pulsecore/flist.c \
	src/pulsecore/g711.c \
	src/pulsecore/hashmap.c \
	src/pulsecore/hook-list.c \
	src/pulsecore/i18n.c \
	src/pulsecore/idxset.c \
	src/pulsecore/iochannel.c \
	src/pulsecore/ipacl.c \
	src/pulsecore/json.c \
	src/pulsecore/lock-autospawn.c \
	src/pulsecore/log.c \
	src/pulsecore/ltdl-helper.c \
	src/pulsecore/ltdl-static.c \
	src/pulsecore/mcalign.c \
	src/pulsecore/memblock.c \
	src/pulsecore/memblockq.c \
	src/pulsecore/memchunk.c \
	src/pulsecore/memtrap.c \
	src/pulsecore/message-handler.c \
	src/pulsecore/mix.c \
	src/pulsecore/modargs.c \
	src/pulsecore/modinfo.c \
	src/pulsecore/module.c \
	src/pulsecore/msgobject.c \
	src/pulsecore/mutex-posix.c \
	src/pulsecore/namereg.c \
	src/pulsecore/native-common.c \
	src/pulsecore/object.c \
	src/pulsecore/once.c \
	src/pulsecore/packet.c \
	src/pulsecore/pdispatch.c \
	src/pulsecore/pid.c \
	src/pulsecore/play-memblockq.c \
	src/pulsecore/play-memchunk.c \
	src/pulsecore/pstream.c \
	src/pulsecore/pstream-util.c \
	src/pulsecore/protocol-esound.c \
	src/pulsecore/protocol-native.c \
	src/pulsecore/queue.c \
	src/pulsecore/random.c \
	src/pulsecore/ratelimit.c \
	src/pulsecore/remap.c \
	src/pulsecore/remap_mmx.c \
	src/pulsecore/remap_sse.c \
	src/pulsecore/resampler.c \
	src/pulsecore/resampler/ffmpeg.c \
	src/pulsecore/resampler/peaks.c \
	src/pulsecore/resampler/trivial.c \
	src/pulsecore/rtpoll.c \
	src/pulsecore/sample-util.c \
	src/pulsecore/semaphore-posix.c \
	src/pulsecore/sconv.c \
	src/pulsecore/sconv-s16be.c \
	src/pulsecore/sconv-s16le.c \
	src/pulsecore/sconv_sse.c \
	src/pulsecore/shared.c \
	src/pulsecore/shm.c \
	src/pulsecore/sink.c \
	src/pulsecore/sink-input.c \
	src/pulsecore/sioman.c \
	src/pulsecore/socket-server.c \
	src/pulsecore/sndfile-util.c \
	src/pulsecore/socket-util.c \
	src/pulsecore/sound-file.c \
	src/pulsecore/sound-file-stream.c \
	src/pulsecore/source.c \
	src/pulsecore/source-output.c \
	src/pulsecore/srbchannel.c \
	src/pulsecore/stream-util.c \
	src/pulsecore/strbuf.c \
	src/pulsecore/strlist.c \
	src/pulsecore/svolume_c.c \
	src/pulsecore/svolume_arm.c \
	src/pulsecore/svolume_mmx.c \
	src/pulsecore/svolume_sse.c \
	src/pulsecore/tagstruct.c \
	src/pulsecore/thread-mq.c \
	src/pulsecore/thread-posix.c \
	src/pulsecore/tokenizer.c \
	src/pulsecore/usergroup.c \
	src/pulsecore/ffmpeg/resample2.c \
	src/pulsecore/filter/biquad.c \
	src/pulsecore/filter/crossover.c \
	src/pulsecore/filter/lfe-filter.c \
	src/pulse/channelmap.c \
	src/pulse/client-conf.c \
	src/pulse/error.c \
	src/pulse/format.c \
	src/pulse/mainloop.c \
	src/pulse/mainloop-api.c \
	src/pulse/mainloop-signal.c \
	src/pulse/proplist.c \
	src/pulse/rtclock.c \
	src/pulse/sample.c \
	src/pulse/timeval.c \
	src/pulse/utf8.c \
	src/pulse/util.c \
	src/pulse/volume.c \
	src/pulse/xmalloc.c \

# PulseAudio modules.
SOURCES += \
	src/modules/module-null-sink.c \
	src/modules/module-protocol-stub.c \

OBJECTS = $(patsubst %.c, %.o, $(SOURCES))
DEPENDS = $(OBJECTS:.o=.d)

$(TARGET): $(OBJECTS)
	$(CC) $(LDFLAGS) $(OBJECTS) $(LDLIBS) -o $@

clean:
	-$(RM) $(OBJECTS)
	-$(RM) $(TARGET)
	-$(RM) $(DEPENDS)

-include $(DEPENDS)
