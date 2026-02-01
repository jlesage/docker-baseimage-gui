package main

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"os/exec"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/creack/pty"
	"github.com/gorilla/websocket"
	"github.com/julienschmidt/httprouter"

	"webservices/log"
)

const (
	minCols, minRows = 1, 1
	maxCols, maxRows = 1000, 500
)

func getTerminalLogPrefix(connId uint64) string {
	if connId == 0 {
		return "terminal: "
	} else {
		return fmt.Sprintf("terminal[conn id %d]:", connId)
	}
}

func parseResize(payload string) (int, int, error) {
	payload = strings.TrimSpace(payload)
	parts := strings.Split(payload, ",")
	if len(parts) != 2 {
		return 0, 0, fmt.Errorf("expected cols,rows")
	}

	colsStr := strings.TrimSpace(parts[0])
	rowsStr := strings.TrimSpace(parts[1])

	cols, err := strconv.Atoi(colsStr)
	if err != nil {
		return 0, 0, fmt.Errorf("invalid cols: %w", err)
	}
	rows, err := strconv.Atoi(rowsStr)
	if err != nil {
		return 0, 0, fmt.Errorf("invalid rows: %w", err)
	}

	if cols < minCols || cols > maxCols || rows < minRows || rows > maxRows {
		return 0, 0, fmt.Errorf("cols/rows out of bounds (%d-%d / %d-%d)", minCols, maxCols, minRows, maxRows)
	}

	return cols, rows, nil
}

func getTerminalWebSocketHandler(appCtx context.Context) httprouter.Handle {
	return func(w http.ResponseWriter, r *http.Request, ps httprouter.Params) {
		terminalWebSocketHandler(appCtx, w, r, ps)
	}
}

func terminalWebSocketHandler(appCtx context.Context, w http.ResponseWriter, r *http.Request, ps httprouter.Params) {
	// Setup the WebSocket connection.
	conn, connId, err := webSocketConnectionManager.SetupConnection(w, r, ps)
	if err != nil {
		log.Errorf("%s WebSocket connection setup failed: %v", getTerminalLogPrefix(connId), err)
		return
	}

	// Setup termination function for the WebSocket connection.
	var closeConnOnce sync.Once
	closeConn := func() {
		closeConnOnce.Do(func() {
			log.Debugf("%s closing WebSocket connection", getTerminalLogPrefix(connId))
			webSocketConnectionManager.TeardownConnection(conn)
		})
	}
	defer closeConn()

	log.Debugf("%s new WebSocket connection", getTerminalLogPrefix(connId))

	// Variable used to track PTY closure request.
	var ptyCloseRequested atomic.Bool
	ptyCloseRequested.Store(false)

	// Start a shell.
	cmd := exec.Command("/bin/sh")
	cmd.Dir = "/tmp"
	ptmx, err := pty.Start(cmd)
	if err != nil {
		log.Errorf("%s failed to start terminal: %v", getTerminalLogPrefix(connId), err)
		return
	}

	// Setup the termination function for the PTY.
	var closePtyOnce sync.Once
	closePty := func() {
		closePtyOnce.Do(func() {
			log.Debugf("%s closing terminal", getTerminalLogPrefix(connId))
			ptyCloseRequested.Store(true)
			cmd.Process.Kill()
			cmd.Process.Wait()
			ptmx.Close()
		})
	}
	defer closePty()

	// Setup channel used to indicate that one of the go routines
	// terminated.
	done := make(chan struct{})
	var signalDoneOnce sync.Once
	signalDone := func() {
		signalDoneOnce.Do(func() { close(done) })
	}

	// Wait group to wait for go routines to terminate.
	var wg sync.WaitGroup
	wg.Add(2)

	// Go routing used to read from PTY and write to the WebSocket.
	go func() {
		defer wg.Done()
		defer signalDone()

		buf := make([]byte, 1024)
		for {
			// Read data from PTY.
			n, err := ptmx.Read(buf)
			if err != nil {
				var errno syscall.Errno
				if errors.As(err, &errno) && errno == syscall.EIO {
					log.Debugf("%s shell exited", getTerminalLogPrefix(connId))
					if !ptyCloseRequested.Load() {
						conn.SetWriteDeadline(time.Now().Add(writeWait))
						err := conn.WriteMessage(websocket.CloseMessage, websocket.FormatCloseMessage(websocket.CloseNormalClosure, "Connection closing"))
						if err == nil {
							// Give some time to the peer to process the message.
							time.Sleep(time.Second * 2)
						} else {
							log.Errorf("%s failed to send close message: %v", getTerminalLogPrefix(connId), err)
						}
					}
				} else {
					log.Errorf("%s failed to read from terminal: %v", getTerminalLogPrefix(connId), err)
				}

				// Exit the go routine.
				return
			}

			// Forward data to WebSocket.
			conn.SetWriteDeadline(time.Now().Add(writeWait))
			if err := conn.WriteMessage(websocket.BinaryMessage, buf[:n]); err != nil {
				if isNormalWebSocketCloseError(err) {
					log.Debugf("%s WebSocket closed while writing: %v", getTerminalLogPrefix(connId), err)
				} else {
					log.Errorf("%s failed to write to WebSocket: %v", getTerminalLogPrefix(connId), err)
				}

				// Exit the go routine.
				return
			}
		}
	}()

	// Go routine used to read from the WebSocket and write to PTY.
	go func() {
		defer wg.Done()
		defer signalDone()

		for {
			// Read data from WebSocket.
			msgType, msg, err := conn.ReadMessage()
			if err != nil {
				if isNormalWebSocketCloseError(err) {
					log.Debugf("%s WebSocket closed while reading: %v", getTerminalLogPrefix(connId), err)
				} else {
					log.Errorf("%s failed to read from WebSocket: %v", getTerminalLogPrefix(connId), err)
				}
				return
			}

			// Forward data to PTY.
			if msgType == websocket.BinaryMessage {
				if _, err := ptmx.Write(msg); err != nil {
					log.Errorf("%s failed to write to terminal: %v", getTerminalLogPrefix(connId), err)
					return
				}
				continue
			}

			// Or handle text command.
			if msgType == websocket.TextMessage {
				// Handle resize message.
				// Expected format: "resize:cols,rows"
				if strings.HasPrefix(string(msg), "resize:") {
					cols, rows, err := parseResize(string(msg[len("resize:"):]))
					if err != nil {
						log.Errorf("%s invalid terminal resize command received: %v", getTerminalLogPrefix(connId), err)
						continue
					}

					err = pty.Setsize(ptmx, &pty.Winsize{
						Cols: uint16(cols),
						Rows: uint16(rows),
					})
					if err == nil {
						log.Debugf("%s terminal resized to %dx%d", getTerminalLogPrefix(connId), cols, rows)
					} else {
						log.Errorf("%s failed to resize terminal: %v", getTerminalLogPrefix(connId), err)
					}
				} else {
					log.Errorf("%s unknown terminal command received", getTerminalLogPrefix(connId))
				}
			}
		}
	}()

	// The main loop.
Loop:
	for {
		select {
		case <-appCtx.Done():
			// Context cancelled (graceful shutdown).
			log.Debugf("%s web services server shutting down, terminating terminal", getTerminalLogPrefix(connId))
			break Loop
		case <-done:
			// One of the go routines terminated.
			break Loop
		}
	}

	// Make sure the PTY and WebSocket connection are terminated. This will
	// also cause any go routines that are still running to terminate.
	closePty()
	closeConn()

	// Wait for go routines to terminate.
	wg.Wait()
}
