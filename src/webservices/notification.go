package main

import (
	"fmt"
	"net/http"

	"github.com/godbus/dbus/v5"
	"github.com/godbus/dbus/v5/introspect"
	"github.com/gorilla/websocket"
	"github.com/julienschmidt/httprouter"

	"webservices/log"
)

// Notifications implements the org.freedesktop.Notifications D-Bus interface.
// https://specifications.freedesktop.org/notification-spec/1.2/protocol.html
type Notifications struct {
	broadcast chan NotificationMessage
	nextID    uint32
}

// Message represents the structure of WebSocket messages sent to clients.
type NotificationMessage struct {
	Summary string `msgpack:"summary"`
	Body    string `msgpack:"body"`
}

// WebSocket clients
var clients = make(map[*websocket.Conn]bool)
var broadcast = make(chan NotificationMessage)

func notificationServiceInit() error {
	// Connect to D-Bus.
	conn, err := dbus.SessionBus()
	if err != nil {
		return fmt.Errorf("failed to connect to D-Bus: %w", err)
	}

	// Register org.freedesktop.Notifications.
	n := &Notifications{broadcast: broadcast, nextID: 0}
	err = conn.Export(n, "/org/freedesktop/Notifications", "org.freedesktop.Notifications")
	if err != nil {
		conn.Close()
		return fmt.Errorf("failed to export Notifications interface: %w", err)
	}

	// Export introspection data.
	const introspectXML = `
	<node>
		<interface name="org.freedesktop.Notifications">
			<method name="Notify">
				<arg type="s" name="app_name" direction="in"/>
				<arg type="u" name="replaces_id" direction="in"/>
				<arg type="s" name="app_icon" direction="in"/>
				<arg type="s" name="summary" direction="in"/>
				<arg type="s" name="body" direction="in"/>
				<arg type="as" name="actions" direction="in"/>
				<arg type="a{sv}" name="hints" direction="in"/>
				<arg type="i" name="expire_timeout" direction="in"/>
				<arg type="u" name="id" direction="out"/>
			</method>
			<method name="CloseNotification">
				<arg type="u" name="id" direction="in"/>
			</method>
			<method name="GetCapabilities">
				<arg type="as" name="capabilities" direction="out"/>
			</method>
			<method name="GetServerInformation">
				<arg type="s" name="name" direction="out"/>
				<arg type="s" name="vendor" direction="out"/>
				<arg type="s" name="version" direction="out"/>
				<arg type="s" name="spec_version" direction="out"/>
			</method>
			<signal name="NotificationClosed">
				<arg type="u" name="id"/>
				<arg type="u" name="reason"/>
			</signal>
			<signal name="ActionInvoked">
				<arg type="u" name="id"/>
				<arg type="s" name="action_key"/>
			</signal>
		</interface>
	</node>`
	conn.Export(introspect.Introspectable(introspectXML), "/org/freedesktop/Notifications", "org.freedesktop.DBus.Introspectable")

	// Request the bus name.
	reply, err := conn.RequestName("org.freedesktop.Notifications", dbus.NameFlagReplaceExisting|dbus.NameFlagDoNotQueue)
	if err != nil {
		conn.Close()
		return fmt.Errorf("failed to request bus name: %w", err)
	}
	if reply != dbus.RequestNameReplyPrimaryOwner {
		conn.Close()
		return fmt.Errorf("could not become primary owner of org.freedesktop.Notifications")
	}

	// Serve the D-Bus requests.
	go serveNotifications(conn)

	return nil
}

func serveNotifications(conn *dbus.Conn) {
	defer conn.Close()
	select {}
}

func notificationWebsocketHandler(w http.ResponseWriter, r *http.Request, _ httprouter.Params) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Error("WebSocket upgrade failed: ", err)
		return
	}
	defer conn.Close()

	log.Debug("new WebSocket connection established")

	// Register client.
	clients[conn] = true
	defer func() {
		delete(clients, conn)
		conn.Close()
	}()

	// Handle notification messages.
	for message := range broadcast {
		// Send notification message to this client.
		writeMessagePack(conn, message)
	}
}

// Notify handles the org.freedesktop.Notifications.Notify method.
func (n *Notifications) Notify(appName string, replacesID uint32, appIcon, summary, body string, actions []string, hints map[string]dbus.Variant, expireTimeout int32) (uint32, *dbus.Error) {
	// Create notification message.
	message := NotificationMessage{
		Summary: summary,
		Body:    body,
	}

	// Assign a new ID if replacesID is 0.
	id := replacesID
	if id == 0 {
		n.nextID++
		id = n.nextID
	}

	// Send to WebSocket clients.
	if len(clients) > 0 {
		n.broadcast <- message
	}

	return id, nil
}

// CloseNotification handles the org.freedesktop.Notifications.CloseNotification method.
func (n *Notifications) CloseNotification(id uint32) *dbus.Error {
	// Not implemented for simplicity; could emit NotificationClosed signal.
	return nil
}

// GetCapabilities handles the org.freedesktop.Notifications.GetCapabilities method.
func (n *Notifications) GetCapabilities() ([]string, *dbus.Error) {
	// Return supported capabilities.
	return []string{"body", "summary"}, nil
}

// GetServerInformation handles the org.freedesktop.Notifications.GetServerInformation method.
func (n *Notifications) GetServerInformation() (name, vendor, version, specVersion string, err *dbus.Error) {
	// Return server metadata.
	return "WebServices", "jlesage", "1.0", "1.2", nil
}
