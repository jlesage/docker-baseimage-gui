/*
 * Simple web authentication server.
 *
 * Inspired by https://redbyte.eu/en/blog/using-the-nginx-auth-request-module/
 */
package main

import (
	"flag"
	"errors"
	"net"
	"os"
	"os/signal"
	"syscall"
	"net/http"
	"net/url"
	"math/rand"
	"encoding/hex"
	"sync"
	"sync/atomic"
	"time"

	"golang.org/x/time/rate"

	"github.com/julienschmidt/httprouter"
	"github.com/tg123/go-htpasswd"
	"github.com/jasonlvhit/gocron"
	"github.com/gorilla/securecookie"

	"webauth/log"
)

type WebauthConfig struct {
	MaxTokens uint
	TokenValidityDuration time.Duration
	SecureCookieInstance *securecookie.SecureCookie
	TokenCookieName string
	LoginSuccessRedirectCookieName string
	LoginFailureRedirectCookieName string
	LoginResultCookieName string
	LogoutRedirectCookieName string
}

type WebauthStats struct {
	AuthSuccess atomic.Uint64
	AuthFailure atomic.Uint64
	LoginSuccess atomic.Uint64
	LoginFailure atomic.Uint64
	LoginBadRequest atomic.Uint64
	LoginInternalError atomic.Uint64
	LogoutSuccess atomic.Uint64
	LogoutBadRequest atomic.Uint64
	NotFound atomic.Uint64
	MethodNotAllowed atomic.Uint64
	TokenGenerated atomic.Uint64
}

const (
	MAX_USERNAME_LENGTH = 128
	MAX_PASSWORD_LENGTH = 128
)

var (
	gConfig WebauthConfig
	gStats WebauthStats
	gTokens = make(map[string]time.Time)
	gTokensMutex sync.Mutex
	gPasswordDb *htpasswd.File
	gLoginLimiter *rate.Limiter
)

func main() {
	var err error

	// Handle program options.
	passwordFile := flag.String("password-db", "/config/webauth-htpasswd", "path to the password database")
	unixSocket := flag.String("unix-socket", "/tmp/webauth.sock", "path to the unix domain socket")
	flag.UintVar(&gConfig.MaxTokens, "max-tokens", 1024, "maximum number of handled tokens")
	tokenValidityTime := flag.Uint("token-validity-time", 24, "validity time (in hours) of a token")
	logLevel := flag.String("log-level", "error", "log level")
	flag.Parse()

	// Handle log level.
	if err := log.SetLevel(*logLevel); err != nil {
		log.Fatal("invalid log level")
	}

	// Handle the token validity time.
	gConfig.TokenValidityDuration = time.Hour * time.Duration(Min(8760, Max(1, *tokenValidityTime)))

	// Create a SecureCookie instance.
	gConfig.SecureCookieInstance = securecookie.New(
		securecookie.GenerateRandomKey(64),
		securecookie.GenerateRandomKey(32))
	gConfig.SecureCookieInstance.MaxAge(int(gConfig.TokenValidityDuration.Seconds()))

	// Set name of cookies.
	gConfig.TokenCookieName = "auth"
	gConfig.LoginSuccessRedirectCookieName = "login_success_url"
	gConfig.LoginFailureRedirectCookieName = "login_failure_url"
	gConfig.LoginResultCookieName = "login_result"
	gConfig.LogoutRedirectCookieName = "logout_redirect_url"

	// Load the password database.
	gPasswordDb, err = htpasswd.New(*passwordFile, htpasswd.DefaultSystems, nil)
	if err != nil {
		log.Fatal("could not open password database:", err)
	}

	// Setup SIGHUP signal handling to reload password database.
	sighupChannel := make(chan os.Signal, 1)
	signal.Notify(sighupChannel, syscall.SIGHUP)
	go func() {
		for {
			// Wait for the SIGUP signal.
			<-sighupChannel
			// Reload password database.
			log.Info("reloading password database")
			gPasswordDb.Reload(nil)
		}
	}()

	// Setup SIGUSR1 signal handling to dump statistics.
	sigusr1Channel := make(chan os.Signal, 1)
	signal.Notify(sigusr1Channel, syscall.SIGUSR1)
	go func() {
		for {
			// Wait for the SIGUSR1 signal.
			<-sigusr1Channel
			// Dump statistics.
			log.Println("statistics:")
			log.Println("  AuthSuccess:        ", gStats.AuthSuccess.Load())
			log.Println("  AuthFailure:        ", gStats.AuthFailure.Load())
			log.Println("  LoginSuccess:       ", gStats.LoginSuccess.Load())
			log.Println("  LoginFailure:       ", gStats.LoginFailure.Load())
			log.Println("  LoginBadRequest:    ", gStats.LoginBadRequest.Load())
			log.Println("  LoginInternalError: ", gStats.LoginInternalError.Load())
			log.Println("  LogoutSuccess:      ", gStats.LogoutSuccess.Load())
			log.Println("  LogoutBadRequest:   ", gStats.LogoutBadRequest.Load())
			log.Println("  NotFound:           ", gStats.NotFound.Load())
			log.Println("  MethodNotAllowed:   ", gStats.MethodNotAllowed.Load())
			log.Println("  TokenGenerated:     ", gStats.TokenGenerated.Load())
			gTokensMutex.Lock()
			log.Println("  TokenCount:         ", len(gTokens))
			gTokensMutex.Unlock()
		}
	}()

	// Create limiter for login attempts.
	gLoginLimiter = rate.NewLimiter(1, 5)

	// Start periodic job to cleanup tokens.
	go func() {
		gocron.Every(1).Hour().Do(CleanupTokens, false)
		<-gocron.Start()
	}()

	// Create HTTP router.
	router := httprouter.New()
	router.POST("/login", loginHandler)
	router.GET("/logout", logoutHandler)
	router.GET("/auth", authHandler)
	router.NotFound = notFoundHandler()
	router.MethodNotAllowed = methodNotAllowedHandler()

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
	log.Info("web authentication service ready")
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

func methodNotAllowedHandler() http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gStats.MethodNotAllowed.Add(1)
		http.Error(w,
			http.StatusText(http.StatusMethodNotAllowed),
			http.StatusMethodNotAllowed,
		)
	})
}

func notFoundHandler() http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gStats.NotFound.Add(1)
		http.NotFound(w, r)
	})
}

func authHandler(w http.ResponseWriter, r *http.Request, _ httprouter.Params) {
	tokenIsValid := false

	// Try to extract token from cookie.
	if cookie, err := r.Cookie(gConfig.TokenCookieName); err == nil {
		value := make(map[string]string)
		// Try to decode it.
		if err := gConfig.SecureCookieInstance.Decode(gConfig.TokenCookieName, cookie.Value, &value); err == nil {
			if token := value["token"]; ValidateToken(token) {
				tokenIsValid = true
			}
		}
	}

	// Handle the result.
	if tokenIsValid {
		// Token valid: return HTTP 200 status code.
		gStats.AuthSuccess.Add(1)
		w.WriteHeader(http.StatusOK)
	} else {
		// Token invalid: return HTTP 401 status code.
		gStats.AuthFailure.Add(1)
		http.Error(w, http.StatusText(http.StatusUnauthorized), http.StatusUnauthorized)
	}
}

func loginHandler(w http.ResponseWriter, r *http.Request, _ httprouter.Params) {
	// Rate limit login attempts.
	if gLoginLimiter.Allow() == false {
		log.Debug("rate limiting login attempts")
		http.Error(w,
			http.StatusText(http.StatusTooManyRequests),
			http.StatusTooManyRequests,
		)
		return
	}

	username := r.PostFormValue("username")
	password := r.PostFormValue("password")
	successRawUrl := ""
	failureRawUrl := ""

	// Make sure all form fields are present and valid.
	if username == "" || password == "" {
		http.Error(w, http.StatusText(http.StatusBadRequest), http.StatusBadRequest)
		log.Debug("invalid login request: username or password missing")
		gStats.LoginBadRequest.Add(1)
		return
	} else if len(username) > MAX_USERNAME_LENGTH || len(password) > MAX_PASSWORD_LENGTH {
		http.Error(w, http.StatusText(http.StatusBadRequest), http.StatusBadRequest)
		log.Debug("invalid login request: username or password too long")
		gStats.LoginBadRequest.Add(1)
		return
	}

	// Fetch redirect URLs via cookies.
	if cookie, err := r.Cookie(gConfig.LoginSuccessRedirectCookieName); err == nil {
		successRawUrl = cookie.Value
	} else {
		http.Error(w, http.StatusText(http.StatusBadRequest), http.StatusBadRequest)
		log.Debug("invalid login request: login success url cookie:", err)
		gStats.LoginBadRequest.Add(1)
		return
	}
	if cookie, err := r.Cookie(gConfig.LoginFailureRedirectCookieName); err == nil {
		failureRawUrl = cookie.Value
	} else {
		http.Error(w, http.StatusText(http.StatusBadRequest), http.StatusBadRequest)
		log.Debug("invalid login request: login failure url cookie:", err)
		gStats.LoginBadRequest.Add(1)
		return
	}

	// Validate redirect URLs.
	if _, err := url.Parse(successRawUrl); err != nil {
		http.Error(w, http.StatusText(http.StatusBadRequest), http.StatusBadRequest)
		log.Debug("invalid login request: invalid login success url:", err)
		gStats.LoginBadRequest.Add(1)
		return
	}
	if _, err := url.Parse(failureRawUrl); err != nil {
		http.Error(w, http.StatusText(http.StatusBadRequest), http.StatusBadRequest)
		log.Debug("invalid login request: invalid login failure url:", err)
		gStats.LoginBadRequest.Add(1)
		return
	}

	// Validate provided credentials.
	validCredentials := gPasswordDb.Match(username, password)

	// Handle the result.
	if validCredentials {
		// Credentials are valid.

		// Generate a token.
		token, err := GenerateToken(16)
		if err != nil {
			// Failed to generate the token.
			log.Error("could not generate token:", err)
			http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)
			gStats.LoginInternalError.Add(1)
			return
		}

		// Save the token.
		if err := SaveToken(token, gConfig.TokenValidityDuration); err != nil {
			// Failed to save the token.
			log.Error("could not save token:", err)
			http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)
			gStats.LoginInternalError.Add(1)
			return
		}

		// Create cookie containing the token.
		value := map[string]string{
			"token": token,
		}
		encoded, err := gConfig.SecureCookieInstance.Encode(gConfig.TokenCookieName, value)
		if err != nil {
			// Failed to create token.
			log.Error("could not encode cookie:", err)
			http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)
			gStats.LoginInternalError.Add(1)
			return
		}

		// Add cookie to the response.
		cookie := &http.Cookie{
			Name:    gConfig.TokenCookieName,
			Value:   encoded,
			MaxAge:  int(gConfig.TokenValidityDuration.Seconds()),
			Path:    "/",
			Secure: true,
			HttpOnly: true,
		}
		http.SetCookie(w, cookie)

		// Remove cookies containing redirect URLs.
		http.SetCookie(w, &http.Cookie{
			Name:    gConfig.LoginSuccessRedirectCookieName,
			Value:   "deleted",
			Expires: time.Now().Add(time.Hour * -24),
			Path:    "/",
		})
		http.SetCookie(w, &http.Cookie{
			Name:    gConfig.LoginFailureRedirectCookieName,
			Value:   "deleted",
			Expires: time.Now().Add(time.Hour * -24),
			Path:    "/",
		})

		// Respond with the redirect.
		gStats.LoginSuccess.Add(1)
		http.Redirect(w, r, successRawUrl, http.StatusFound)
	} else {
		// Invalid credentials.
		log.Debug("invalid credentials have been provided")

		// Add cookie indicating the login result.
		http.SetCookie(w, &http.Cookie{
			Name:    gConfig.LoginResultCookieName,
			Value:   "INVALID_CREDENTIALS",
		})

		// Respond with the redirect.
		gStats.LoginFailure.Add(1)
		http.Redirect(w, r, failureRawUrl, http.StatusFound)
	}
}

func logoutHandler(w http.ResponseWriter, r *http.Request, _ httprouter.Params) {
	token := ""

	// Try to extract token from cookie.
	if cookie, err := r.Cookie(gConfig.TokenCookieName); err == nil {
		value := make(map[string]string)
		// Try to decode it.
		if err := gConfig.SecureCookieInstance.Decode(gConfig.TokenCookieName, cookie.Value, &value); err == nil {
			token = value["token"]
		}
	}

	// Remove the token.
	if token != "" {
		RemoveToken(token)
	} else {
		log.Error("no token provided for logout request")
	}

	// Fetch redirect URL via cookie.
	redirectRawUrl := ""
	if cookie, err := r.Cookie(gConfig.LogoutRedirectCookieName); err == nil {
		redirectRawUrl = cookie.Value
	} else {
		http.Error(w, http.StatusText(http.StatusBadRequest), http.StatusBadRequest)
		log.Debug("invalid logout request: logout redirect url cookie:", err)
		gStats.LogoutBadRequest.Add(1)
		return
	}

	// Validate redirect URL.
	if _, err := url.Parse(redirectRawUrl); err != nil {
		http.Error(w, http.StatusText(http.StatusBadRequest), http.StatusBadRequest)
		log.Debug("invalid logout request: invalid logout redirect url:", err)
		gStats.LogoutBadRequest.Add(1)
		return
	}

	// Remove cookie containing the token.
	http.SetCookie(w, &http.Cookie{
		Name:    gConfig.TokenCookieName,
		Value:   "deleted",
		Expires: time.Now().Add(time.Hour * -24),
		Path:    "/",
	})

	// Respond with a redirect to the login page.
	gStats.LogoutSuccess.Add(1)
	http.Redirect(w, r, redirectRawUrl, http.StatusFound)
}

func GenerateToken(length int) (string, error) {
	b := make([]byte, length)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	gStats.TokenGenerated.Add(1)
	return hex.EncodeToString(b), nil
}

func SaveToken(token string, validityDuration time.Duration) error {
	gTokensMutex.Lock()
	defer gTokensMutex.Unlock()

	// Check if we reached the maximum number of tokens.  If yes,
	// perform an immediate cleanup and check again.
	if uint(len(gTokens)) == gConfig.MaxTokens {
		CleanupTokens(true)
		if uint(len(gTokens)) == gConfig.MaxTokens {
			return errors.New("maximum number of tokens reached")
		}
	}

	// Add the token and its expiration.
	gTokens[token] = time.Now().Add(validityDuration)
	return nil
}

func ValidateToken(token string) bool {
	gTokensMutex.Lock()
	defer gTokensMutex.Unlock()

	if token != "" {
		expiration, found := gTokens[token]
		if found && time.Now().Before(expiration) {
			// Token is valid.
			return true
		}
	}

	return false
}

func RemoveToken(token string) {
	gTokensMutex.Lock()
	defer gTokensMutex.Unlock()

	if token != "" {
		_, found := gTokens[token]
		if found {
			delete(gTokens, token)
		}
	}
}

func CleanupTokens(mutextLocked bool) {
	if !mutextLocked {
		gTokensMutex.Lock()
		defer gTokensMutex.Unlock()
	}

	log.Info("cleaning tokens...")
	for token, expiration := range gTokens {
		if time.Now().After(expiration) {
			log.Info("removing expired token", token)
			delete(gTokens, token)
		}
	}
	log.Info("tokens cleanup terminated")
}

func Min(x, y uint) uint {
	if x < y {
		return x
	}
	return y
}

func Max(x, y uint) uint {
	if x > y {
		return x
	}
	return y
}
