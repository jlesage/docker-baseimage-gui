package main

import (
	"reflect"
	"testing"

	"github.com/godbus/dbus/v5"
	"github.com/vmihailenco/msgpack/v5"
)

func TestNotifyForwardsFullPayload(t *testing.T) {
	ch := make(chan NotificationMessage, 1)
	clientsMutex.Lock()
	clients[nil] = ch
	clientsMutex.Unlock()
	t.Cleanup(func() {
		clientsMutex.Lock()
		delete(clients, nil)
		clientsMutex.Unlock()
	})

	pixels := []byte{0x11, 0x22, 0x33, 0xff}
	hints := map[string]dbus.Variant{
		"desktop-entry": dbus.MakeVariant("firefox"),
		"image-data":    dbus.MakeVariant(pixels),
	}
	n := &Notifications{}
	id, dbusErr := n.Notify(
		"Firefox",
		0,
		"firefox",
		"Example title",
		"Example body",
		[]string{"default", "Activate"},
		hints,
		5000,
	)
	if dbusErr != nil {
		t.Fatalf("Notify returned a D-Bus error: %v", dbusErr)
	}

	message := <-ch
	want := NotificationMessage{
		ID:            1,
		AppName:       "Firefox",
		AppIcon:       "firefox",
		Summary:       "Example title",
		Body:          "Example body",
		Actions:       []string{"default", "Activate"},
		Hints:         map[string]any{"desktop-entry": "firefox", "image-data": pixels},
		ExpireTimeout: 5000,
	}
	if id != want.ID {
		t.Fatalf("Notify returned ID %d, want %d", id, want.ID)
	}
	if !reflect.DeepEqual(message, want) {
		t.Fatalf("forwarded message = %#v, want %#v", message, want)
	}

	encoded, err := msgpack.Marshal(message)
	if err != nil {
		t.Fatalf("marshal notification: %v", err)
	}
	var decoded NotificationMessage
	if err := msgpack.Unmarshal(encoded, &decoded); err != nil {
		t.Fatalf("unmarshal notification: %v", err)
	}
	if !reflect.DeepEqual(decoded, want) {
		t.Fatalf("decoded message = %#v, want %#v", decoded, want)
	}
}
