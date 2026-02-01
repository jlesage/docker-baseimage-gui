package main

import (
	"context"
	"fmt"
	"net/http"
	"sync"
	"time"

	"github.com/godbus/dbus/v5"
	"github.com/godbus/dbus/v5/introspect"
	"github.com/gorilla/websocket"
	"github.com/julienschmidt/httprouter"

	"webservices/log"
)

// Notifications implements the org.freedesktop.Notifications D-Bus interface.
// https://specifications.freedesktop.org/notification-spec/1.2/protocol.html
type Notifications struct {
	nextID uint32
}

// Message represents the structure of WebSocket messages sent to clients.
type NotificationMessage struct {
	Summary string `msgpack:"summary"`
	Body    string `msgpack:"body"`
}

// WebSocket clients
var clients = make(map[*websocket.Conn]chan NotificationMessage)
var clientsMutex sync.Mutex

func getNotificationLogPrefix(connId uint64) string {
	if connId == 0 {
		return "notification: "
	} else {
		return fmt.Sprintf("notification[conn id %d]:", connId)
	}
}

func notificationServiceInit(appCtx context.Context) error {
	// Connect to D-Bus.
	conn, err := dbus.SessionBus()
	if err != nil {
		return fmt.Errorf("%s: failed to connect to D-Bus: %w", getNotificationLogPrefix(0), err)
	}

	// Register org.freedesktop.Notifications.
	n := &Notifications{nextID: 0}
	err = conn.Export(n, "/org/freedesktop/Notifications", "org.freedesktop.Notifications")
	if err != nil {
		conn.Close()
		return fmt.Errorf("%s failed to export Notifications interface: %w", getNotificationLogPrefix(0), err)
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
		return fmt.Errorf("%s failed to request bus name: %w", getNotificationLogPrefix(0), err)
	}
	if reply != dbus.RequestNameReplyPrimaryOwner {
		conn.Close()
		return fmt.Errorf("%s could not become primary owner of org.freedesktop.Notifications", getNotificationLogPrefix(0))
	}

	// Serve the D-Bus requests.
	go serveNotifications(conn, appCtx)

	return nil
}

func serveNotifications(conn *dbus.Conn, appCtx context.Context) {
	defer conn.Close()
	select {
	case <-appCtx.Done():
		log.Debugf("%s web services server shutting down, terminating D-Bus connection", getNotificationLogPrefix(0))
		return
	}
}

func getNotificationWebsocketHandler(appCtx context.Context) httprouter.Handle {
	return func(w http.ResponseWriter, r *http.Request, ps httprouter.Params) {
		notificationWebsocketHandler(appCtx, w, r, ps)
	}
}

func notificationWebsocketHandler(appCtx context.Context, w http.ResponseWriter, r *http.Request, ps httprouter.Params) {
	// Register the WebSocket connection.
	conn, connId, err := webSocketConnectionManager.SetupConnection(w, r, nil)
	if err != nil {
		log.Errorf("%s WebSocket connection setup failed: %v", getNotificationLogPrefix(0), err)
		return
	}
	defer webSocketConnectionManager.TeardownConnection(conn)

	log.Debugf("%s new WebSocket connection established", getNotificationLogPrefix(uint64(connId)))

	// Setup ping mechanism to check connection with client.
	ticker := time.NewTicker(pingPeriod)
	conn.SetPongHandler(func(string) error {
		conn.SetReadDeadline(time.Now().Add(pongWait))
		return nil
	})

	// Create channel to receive notification messages.
	ch := make(chan NotificationMessage, 16)

	// Create channel for read on WebSocket. No message is expected to be
	// received, however this allows quick detection of disconnections.
	readCh := make(chan error)

	// Register client.
	clientsMutex.Lock()
	clients[conn] = ch
	clientsMutex.Unlock()

	defer func() {
		log.Debugf("%s closing WebSocket connection", getNotificationLogPrefix(uint64(connId)))
		clientsMutex.Lock()
		delete(clients, conn)
		clientsMutex.Unlock()
		conn.Close()
		ticker.Stop()
	}()

	// Go routine used to read on the WebSocket. It will send any
	// read error to the channel.
	go func() {
		for {
			_, _, err := conn.ReadMessage()
			if err != nil {
				readCh <- err
			}
		}
	}()

	for {
		select {
		// Handle notification messages.
		case message := <-ch:
			// Send notification message to this client.
			log.Debugf("%s forwarding desktop notification to client", getNotificationLogPrefix(uint64(connId)))
			conn.SetWriteDeadline(time.Now().Add(writeWait))
			if err := writeMessagePack(conn, message); err != nil {
				if !isNormalWebSocketCloseError(err) {
					log.Errorf("%s failed to write to WebSocket: %v", getNotificationLogPrefix(uint64(connId)), err)
				}
				return
			}
		// Handle WebSocket read errors.
		case err := <-readCh:
			if !isNormalWebSocketCloseError(err) {
				log.Errorf("%s failed to read from WebSocket: %v", getNotificationLogPrefix(uint64(connId)), err)
			}
			return
		// Handle ping timer.
		case <-ticker.C:
			// Send ping.
			conn.SetWriteDeadline(time.Now().Add(writeWait))
			if err := conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				if !isNormalWebSocketCloseError(err) {
					log.Errorf("%s failed to write ping to WebSocket: %v", getNotificationLogPrefix(uint64(connId)), err)
				}
				return
			}
		// Handle server shutdown.
		case <-appCtx.Done():
			log.Debugf("%s web services server shutting down, terminating desktop notifications", getNotificationLogPrefix(uint64(connId)))
			return
		}
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

	clientsMutex.Lock()
	defer clientsMutex.Unlock()

	// Send to WebSocket clients.
	log.Debugf("%s new desktop notification received, forwarding to %d client(s)", getNotificationLogPrefix(0), len(clients))
	for _, ch := range clients {
		// Send without blocking.
		select {
		case ch <- message:
		default:
		}
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
	return []string{"summary", "body", "actions"}, nil
}

// GetServerInformation handles the org.freedesktop.Notifications.GetServerInformation method.
func (n *Notifications) GetServerInformation() (name, vendor, version, specVersion string, err *dbus.Error) {
	// Return server metadata.
	return "WebServices", "jlesage", "1.0", "1.2", nil
}
