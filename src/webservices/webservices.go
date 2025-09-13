package main

import (
	"flag"
	"net"
	"net/http"
	"os"

	"github.com/gorilla/websocket"
	"github.com/julienschmidt/httprouter"

	"webservices/log"
)

var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	CheckOrigin:     func(r *http.Request) bool { return true }, // Allow all origins.
}

func main() {
	// Handle program options.
	unixSocket := flag.String("unix-socket", "/tmp/webservices.sock", "path to the unix domain socket")
	logLevel := flag.String("log-level", "error", "log level")
	enableFileManager := flag.Bool("enable-file-manager", false, "enable file manager service")
	flag.Func("allowed-path", "path allowed to be accessed by the file manager (can be used multiple times)", addAllowedPath)
	flag.Func("denied-path", "path not allowed to be accessed by the file manager (can be used multiple times)", addDeniedPath)
	flag.Parse()

	// Handle log level.
	if err := log.SetLevel(*logLevel); err != nil {
		log.Fatal("invalid log level")
	}

	// Create HTTP router.
	router := httprouter.New()
	if *enableFileManager {
		router.GET("/ws-filemanager", fileManagerWebsocketHandler)
		router.GET("/download/:uuid", downloadHandler)
	}
	//router.NotFound = notFoundHandler()
	//router.MethodNotAllowed = methodNotAllowedHandler()

	// Create listener on Unix socket.
	os.Remove(*unixSocket)
	unixListener, err := net.Listen("unix", *unixSocket)
	if err != nil {
		log.Fatal("could not create unix socket listener:", err)
	}

	// Create the HTTP server.
	server := http.Server{
		Handler: httpHandler(router),
	}

	// Start the HTTP server.
	log.Info("web services server ready")
	server.Serve(unixListener)
}

func httpHandler(handler http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		visitor := ""
		if visitor = r.Header.Get("X-Forwarded-For"); visitor == "" {
			if visitor = r.Header.Get("X-Real-IP"); visitor == "" {
				visitor = r.RemoteAddr
			}
		}
		log.Debugf("%s %s %s", visitor, r.Method, r.URL)

		handler.ServeHTTP(w, r)
	})
}
