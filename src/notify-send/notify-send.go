//
// Tool used to send desktop notification via ubus.
//
package main

import (
	"fmt"
	"os"

	"github.com/godbus/dbus/v5"
)

func main() {
	if len(os.Args) != 3 {
		fmt.Fprintf(os.Stderr, "Usage: %s <title> <body>\n", os.Args[0])
		os.Exit(1)
	}

	// Connect to the session bus
	conn, err := dbus.SessionBus()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Connection Error: %v\n", err)
		os.Exit(1)
	}
	defer conn.Close()

	// Create notification object
	obj := conn.Object("org.freedesktop.Notifications", "/org/freedesktop/Notifications")

	// Prepare notification arguments
	appName := "notify-send"
	id := uint32(0) // 0 to let notification daemon assign an ID
	icon := ""
	title := os.Args[1]
	body := os.Args[2]
	actions := []string{}             // Empty actions array
	hints := map[string]interface{}{} // Empty hints dictionary
	timeout := int32(-1)              // Use default timeout

	// Call Notify method
	var replyID uint32
	err = obj.Call("org.freedesktop.Notifications.Notify", 0,
		appName, id, icon, title, body, actions, hints, timeout).Store(&replyID)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Call Error: %v\n", err)
		os.Exit(1)
	}
}
