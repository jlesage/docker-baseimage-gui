package main

import (
	"errors"
	"fmt"
	"net"
	"net/http"
	"sync"
	"sync/atomic"
	"time"

	"github.com/gorilla/websocket"
	"github.com/julienschmidt/httprouter"
	"github.com/vmihailenco/msgpack/v5"
)

// WebSocketConnectionManager keeps track of active WebSocket connections.
type WebSocketConnectionManager struct {
	connections       map[*websocket.Conn]bool
	activeConnections sync.WaitGroup
	nextConnectionId  uint64
	mu                sync.RWMutex
}

const (
	// Time allowed to write a message to the peer.
	writeWait = 10 * time.Second

	// Time allowed to read the next pong message from the peer.
	pongWait = 60 * time.Second

	// Send pings to peer with this period. Must be less than pongWait.
	pingPeriod = (pongWait * 9) / 10

	// The maximum number of active WebSocket connections allowed.
	maxActiveWebSocketConnections = 128
)

var (
	upgrader = websocket.Upgrader{
		ReadBufferSize:  1024,
		WriteBufferSize: 1024,
		CheckOrigin:     func(r *http.Request) bool { return true }, // Allow all origins.
	}

	webSocketConnectionManager = WebSocketConnectionManager{
		connections:      make(map[*websocket.Conn]bool),
		nextConnectionId: 0,
	}
)

func isNormalWebSocketCloseError(err error) bool {
	if errors.Is(err, net.ErrClosed) {
		return true
	} else if websocket.IsCloseError(err, websocket.CloseNormalClosure, websocket.CloseGoingAway, websocket.CloseNoStatusReceived) {
		return true
	} else {
		return false
	}
}

func (m *WebSocketConnectionManager) SetupConnection(w http.ResponseWriter, r *http.Request, _ httprouter.Params) (*websocket.Conn, uint64, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	// Make sure we didn't exceed the maximum number of active connections.
	if len(m.connections) >= maxActiveWebSocketConnections {
		return nil, 0, fmt.Errorf("maximum number of active WebSocket connections reached")
	}

	// Upgrade HTTP connection to WebSocket.
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		return nil, 0, fmt.Errorf("upgrade failed: %w", err)
	}

	// Register the connection.
	m.connections[conn] = true
	m.activeConnections.Add(1)

	// Return the WebSocket connection and a unique connection ID.
	return conn, atomic.AddUint64(&m.nextConnectionId, 1), nil
}

func (m *WebSocketConnectionManager) TeardownConnection(conn *websocket.Conn) {
	m.mu.Lock()
	defer m.mu.Unlock()

	if _, ok := m.connections[conn]; ok {
		delete(m.connections, conn)
		m.activeConnections.Done()
		conn.Close()
	}
}

func (m *WebSocketConnectionManager) Count() int {
	m.mu.RLock()
	count := len(m.connections)
	m.mu.RUnlock()
	return count
}

func (m *WebSocketConnectionManager) Wait() {
	m.activeConnections.Wait()
}

func writeMessagePack(conn *websocket.Conn, data interface{}) error {
	// Encode the data.
	encodedData, err := msgpack.Marshal(data)
	if err != nil {
		return err
	}

	// Send the data.
	return conn.WriteMessage(websocket.BinaryMessage, encodedData)
}

func readMessagePack(conn *websocket.Conn, data interface{}) error {
	// Receive data from WebSocket.
	_, msgData, err := conn.ReadMessage()
	if err != nil {
		return err
	}

	// Decode the MessagePack data.
	return msgpack.Unmarshal(msgData, data)
}
