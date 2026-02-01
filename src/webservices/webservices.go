package main

import (
	"context"
	"flag"
	"net"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/julienschmidt/httprouter"

	"webservices/log"
)

func main() {
	// Handle program options.
	unixSocket := flag.String("unix-socket", "/tmp/webservices.sock", "path to the unix domain socket")
	logLevel := flag.String("log-level", "error", "log level")
	enableFileManager := flag.Bool("enable-file-manager", false, "enable file manager service")
	flag.Func("allowed-path", "path allowed to be accessed by the file manager (can be used multiple times)", addAllowedPath)
	flag.Func("denied-path", "path not allowed to be accessed by the file manager (can be used multiple times)", addDeniedPath)
	enableNotification := flag.Bool("enable-notification", false, "enable desktop notification service")
	flag.Parse()

	// Handle log level.
	if err := log.SetLevel(*logLevel); err != nil {
		log.Fatal("invalid log level")
	}

	// Create context used to gracefully shutdown the server when
	// receiving termination signals.
	appCtx, stop := signal.NotifyContext(
		context.Background(),
		syscall.SIGINT,
		syscall.SIGTERM,
	)
	defer stop()

	// Create HTTP router.
	router := httprouter.New()
	if *enableFileManager {
		router.GET("/ws-filemanager", getFileManagerWebsocketHandler(appCtx))
		router.GET("/download/:uuid", downloadHandler)
	}
	if *enableNotification {
		if err := notificationServiceInit(appCtx); err != nil {
			log.Fatal("could not initialize notification service: ", err)
		}
		router.GET("/ws-notification", getNotificationWebsocketHandler(appCtx))
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
	go func() {
		if err := server.Serve(unixListener); err != nil && err != http.ErrServerClosed {
			log.Fatal("could not start web services server:", err)
		}
	}()

	// Wait for termination signal.
	<-appCtx.Done()
	log.Info("shutting down web services server...")

	// Gracefully shutdown the HTTP server.
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	if err := server.Shutdown(shutdownCtx); err != nil {
		log.Fatal("web services server forced to shutdown:", err)
	}

	// Wait for all active WebSocket connections to terminate. This is
	// necessary because the HTTP server doesn't track upgraded WebSocket
	// connections.
	webSocketConnectionManager.Wait()
	log.Println("web services server exiting")
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
