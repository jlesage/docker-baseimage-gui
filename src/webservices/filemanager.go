package main

import (
	"context"
	"fmt"
	"mime"
	"net/http"
	"os"
	"path/filepath"
	"slices"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/gorilla/websocket"
	"github.com/hashicorp/golang-lru/v2/expirable"
	"github.com/julienschmidt/httprouter"

	"webservices/log"
)

const (
	MAX_FILENAME_LENGTH            = 255
	MAX_PATH_LENGTH                = 4096
	MAX_FILE_UPLOAD_SIZE           = 4 * 1024 * 1024 * 1024
	MAX_UPLOAD_BLOCK_DATA_SIZE     = 5 * 1024 * 1024
	MAX_PENDING_UPLOADS            = 5
	PENDING_UPLOAD_VALIDITY_TIME   = time.Second * 10
	MAX_PENDING_DOWNLOADS          = 5
	PENDING_DOWNLOAD_VALIDITY_TIME = time.Second * 20
	FILE_DOWNLOAD_CHUNK_SIZE       = 1 * 1024 * 1024
)

// Paths allowed to be accessed.
var allowedPaths []string

// Paths not allowed to be accessed.
var deniedPaths []string

// Pending downloads.
var pendingDownloads *expirable.LRU[string, string] = expirable.NewLRU[string, string](MAX_PENDING_DOWNLOADS, nil, PENDING_DOWNLOAD_VALIDITY_TIME)

// Pending uploads.
var pendingUploads *expirable.LRU[string, *UploadFileContext] = expirable.NewLRU(MAX_PENDING_UPLOADS, evictPendingUpload, PENDING_UPLOAD_VALIDITY_TIME)

// Message represents the structure of WebSocket messages received from clients.
type Message struct {
	Type       string  `msgpack:"type"`
	Path       string  `msgpack:"path,omitempty"`
	OldPath    string  `msgpack:"oldPath,omitempty"`
	NewPath    string  `msgpack:"newPath,omitempty"`
	NewName    string  `msgpack:"newName,omitempty"`
	Size       *uint64 `msgpack:"size,omitempty"`
	ChunkIndex uint    `msgpack:"chunkIndex,omitempty"`
	Content    []byte  `msgpack:"content,omitempty"`
}

type FileInfo struct {
	Name  string `msgpack:"name"`
	Path  string `msgpack:"path"`
	IsDir bool   `msgpack:"isDir"`
}

type UploadFileContext struct {
	ConnId        uint64
	Path          string
	FileSize      uint64
	Fd            *os.File
	BytesReceived uint64
	mu            sync.Mutex
}

func (m *UploadFileContext) Cleanup(removeFile bool) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.Fd != nil {
		m.Fd.Close()
		m.Fd = nil
		if removeFile {
			os.Remove(m.Path)
		}
	}
}

func getFileManagerLogPrefix(connId uint64) string {
	if connId == 0 {
		return "file manager: "
	} else {
		return fmt.Sprintf("file manager[conn id %d]:", connId)
	}
}

func evictPendingUpload(path string, uploadFileContext *UploadFileContext) {
	uploadFileContext.Cleanup(true)
}

func downloadHandler(w http.ResponseWriter, r *http.Request, ps httprouter.Params) {
	// Extract UUID from the URL parameters
	fileUUID := ps.ByName("uuid")

	// Look up the file associated with the UUID.
	filePath, ok := pendingDownloads.Peek(fileUUID)
	if ok {
		pendingDownloads.Remove(fileUUID)
	} else {
		http.Error(w, "Not Found", http.StatusNotFound)
		return
	}

	// Open the file.
	file, err := os.Open(filePath)
	if err != nil {
		http.Error(w, "Error opening file", http.StatusInternalServerError)
		return
	}
	defer file.Close()

	// Get file information.
	fileStat, err := file.Stat()
	if err != nil {
		http.Error(w, "Error opening file", http.StatusInternalServerError)
		return
	}

	fileName := filepath.Base(filePath)

	// Determine the MIME type based on the file extension.
	mimeType := mime.TypeByExtension(filepath.Ext(fileName))
	if mimeType == "" {
		// MIME type not found, use a generic fallback.
		mimeType = "application/octet-stream"
	}

	// Set the Content-Type header.
	w.Header().Set("Content-Type", mimeType)

	// Set the Content-Disposition header to prompt download. FormatMediaType
	// properly quotes and encodes the filename (RFC 2183 / 2231).
	disposition := mime.FormatMediaType("attachment", map[string]string{
		"filename": fileName,
	})
	if disposition == "" {
		disposition = "attachment"
	}
	w.Header().Set("Content-Disposition", disposition)

	// Serve the file.
	http.ServeContent(w, r, fileName, fileStat.ModTime(), file)
}

func getFileManagerWebsocketHandler(appCtx context.Context) httprouter.Handle {
	return func(w http.ResponseWriter, r *http.Request, ps httprouter.Params) {
		fileManagerWebsocketHandler(appCtx, w, r, ps)
	}
}

func fileManagerWebsocketHandler(appCtx context.Context, w http.ResponseWriter, r *http.Request, ps httprouter.Params) {
	// Register the WebSocket connection.
	conn, connId, err := webSocketConnectionManager.SetupConnection(w, r, ps)
	if err != nil {
		log.Errorf("%s WebSocket connection setup failed: %v", getFileManagerLogPrefix(0), err)
		return
	}

	// Setup termination function for the WebSocket connection.
	var closeConnOnce sync.Once
	closeConn := func() {
		closeConnOnce.Do(func() {
			log.Debugf("%s closing WebSocket connection", getFileManagerLogPrefix(uint64(connId)))
			webSocketConnectionManager.TeardownConnection(conn)
		})
	}
	defer closeConn()

	log.Debugf("%s new WebSocket connection established", getFileManagerLogPrefix(uint64(connId)))

	// Handle server shutdown.
	go func() {
		<-appCtx.Done()
		log.Debugf("%s web services server shutting down, terminating file manager", getFileManagerLogPrefix(uint64(connId)))
		closeConn()
	}()

	for {
		var msg Message
		err := readMessagePack(conn, &msg)
		if err != nil {
			if !isNormalWebSocketCloseError(err) {
				log.Errorf("%s failed to read from WebSocket: %v", getFileManagerLogPrefix(uint64(connId)), err)
			}
			break
		}

		switch msg.Type {
		case "listDir":
			if len(msg.Path) == 0 {
				sendError(conn, "path missing", msg)
				continue
			} else if len(msg.Path) > MAX_PATH_LENGTH {
				sendError(conn, "path too long", msg)
				continue
			}

			files, err := listDir(msg.Path)
			if pathErr, ok := err.(*os.PathError); ok {
				sendError(conn, pathErr.Err.Error(), msg)
				continue
			} else if err != nil {
				sendError(conn, err.Error(), msg)
				continue
			}

			// Remove all paths that are not allowed.
			numFiles := len(files)
			files = slices.DeleteFunc(files, func(f FileInfo) bool {
				// Check denied paths.
				for _, deniedPath := range deniedPaths {
					// If the denied path is a subpath of the
					// current file, remove it.
					ok, err := hasSubpath(f.Path, deniedPath)
					if err == nil && ok {
						return true
					}
				}

				// Check allowed paths.
				for _, allowedPath := range allowedPaths {
					// If the allowed path is a subpath of the
					// current file, keep it.
					ok, err := hasSubpath(f.Path, allowedPath)
					if err == nil && ok {
						return false
					}

					// If the current file is a directory and is
					// a subpath of an allowed path, keep it. We
					// must be able to "reach" an allowed path.
					if f.IsDir {
						ok, err := hasSubpath(allowedPath, f.Path)
						if err == nil && ok {
							return false
						}
					}
				}
				return true
			})

			// If we removed all files, a non-allowed path
			// was accessed.
			if numFiles > 0 && len(files) == 0 {
				sendError(conn, "no such file or directory", msg)
				continue
			}

			writeMessagePack(conn, struct {
				Type    string     `msgpack:"type"`
				Files   []FileInfo `msgpack:"files"`
				Request Message    `msgpack:"req"` // The original message from client.
			}{Type: "success", Files: files, Request: msg})

		case "rename":
			if len(msg.Path) == 0 {
				sendError(conn, "path missing", msg)
				continue
			} else if len(msg.Path) > MAX_PATH_LENGTH {
				sendError(conn, "path too long", msg)
				continue
			} else if len(msg.NewName) == 0 {
				sendError(conn, "new name missing", msg)
				continue
			} else if len(msg.NewName) > MAX_FILENAME_LENGTH {
				sendError(conn, "new name too long", msg)
				continue
			} else if !isValidFileName(msg.NewName) {
				sendError(conn, "invalid new name", msg)
				continue
			}

			// Build the destination path. NewName is validated as a single
			// path component so it cannot escape the source directory.
			newPath := filepath.Join(filepath.Dir(msg.Path), msg.NewName)
			if len(newPath) > MAX_PATH_LENGTH {
				sendError(conn, "path too long", msg)
				continue
			} else if !isPathAllowed(msg.Path) {
				sendError(conn, "no such file or directory", msg)
				continue
			} else if !isPathAllowed(newPath) {
				sendError(conn, "no such file or directory", msg)
				continue
			}

			err := os.Rename(msg.Path, newPath)
			if linkErr, ok := err.(*os.LinkError); ok {
				sendError(conn, linkErr.Err.Error(), msg)
				continue
			} else if err != nil {
				sendError(conn, err.Error(), msg)
				continue
			}
			sendSuccess(conn, msg)

		case "delete":
			if len(msg.Path) == 0 {
				sendError(conn, "path missing", msg)
				continue
			} else if len(msg.Path) > MAX_PATH_LENGTH {
				sendError(conn, "path too long", msg)
				continue
			} else if !isPathAllowed(msg.Path) {
				sendError(conn, "no such file or directory", msg)
				continue
			}

			info, err := os.Stat(msg.Path)
			if pathErr, ok := err.(*os.PathError); ok {
				sendError(conn, pathErr.Err.Error(), msg)
				continue
			} else if err != nil {
				sendError(conn, err.Error(), msg)
				continue
			}
			if info.IsDir() {
				err = os.RemoveAll(msg.Path)
			} else {
				err = os.Remove(msg.Path)
			}
			if pathErr, ok := err.(*os.PathError); ok {
				sendError(conn, pathErr.Err.Error(), msg)
				continue
			} else if err != nil {
				sendError(conn, err.Error(), msg)
				continue
			}
			sendSuccess(conn, msg)

		case "createFolder":
			if len(msg.Path) == 0 {
				sendError(conn, "path missing", msg)
				continue
			} else if len(msg.Path) > MAX_PATH_LENGTH {
				sendError(conn, "path too long", msg)
				continue
			} else if !isPathAllowed(msg.Path) {
				if filepath.Dir(msg.Path) == "/" {
					sendError(conn, "permission denied", msg)
				} else {
					sendError(conn, "no such file or directory", msg)
				}
				continue
			}

			err := os.Mkdir(msg.Path, 0755)
			if pathErr, ok := err.(*os.PathError); ok {
				sendError(conn, pathErr.Err.Error(), msg)
				continue
			} else if err != nil {
				sendError(conn, err.Error(), msg)
				continue
			}
			sendSuccess(conn, msg)

		case "upload":
			if len(msg.Path) == 0 {
				sendError(conn, "path missing", msg)
				continue
			} else if len(msg.Path) > MAX_PATH_LENGTH {
				sendError(conn, "path too long", msg)
				continue
			} else if msg.Size == nil {
				sendError(conn, "size missing", msg)
				continue
			} else if *msg.Size > MAX_FILE_UPLOAD_SIZE {
				sendError(conn, "size too big", msg)
				continue
			} else if !isPathAllowed(msg.Path) {
				sendError(conn, "no such file or directory", msg)
				continue
			} else if pendingUploads.Len() >= MAX_PENDING_UPLOADS {
				sendError(conn, "too much transfers in progress", msg)
				continue
			} else if _, ok := pendingUploads.Peek(msg.Path); ok {
				sendError(conn, "upload in progress", msg)
				continue
			}

			// Make sure the file doesn't exist.
			_, err := os.Stat(msg.Path)
			if err == nil {
				sendError(conn, "file already exists", msg)
				continue
			}

			// Create the file.
			file, err := os.Create(msg.Path)
			if err != nil {
				sendError(conn, err.Error(), msg)
				continue
			}

			// If the file size is zero, we are done.
			if *msg.Size == 0 {
				file.Close()
				sendSuccess(conn, msg)
				continue
			}

			// Create the upload context.
			uploadFileContext := &UploadFileContext{
				ConnId:        connId,
				Path:          msg.Path,
				FileSize:      *msg.Size,
				Fd:            file,
				BytesReceived: 0,
			}

			// Add it to our table.
			pendingUploads.Add(msg.Path, uploadFileContext)

			sendSuccess(conn, msg)

		case "cancelUpload":
			if len(msg.Path) == 0 {
				sendError(conn, "path missing", msg)
				continue
			} else if len(msg.Path) > MAX_PATH_LENGTH {
				sendError(conn, "path too long", msg)
				continue
			}

			uploadFileContext, ok := pendingUploads.Get(msg.Path)
			if !ok || uploadFileContext.ConnId != connId {
				// Same error whether missing or owned by another connection.
				sendError(conn, "transfer not found", msg)
				continue
			}

			//uploadFileContext.Cleanup(true)
			pendingUploads.Remove(msg.Path)
			sendSuccess(conn, msg)

		case "uploadBlock":
			if len(msg.Path) == 0 {
				sendError(conn, "path missing", msg)
				continue
			} else if len(msg.Path) > MAX_PATH_LENGTH {
				sendError(conn, "path too long", msg)
				continue
			} else if len(msg.Content) == 0 {
				sendError(conn, "data missing", msg)
				continue
			} else if len(msg.Content) > MAX_UPLOAD_BLOCK_DATA_SIZE {
				sendError(conn, "data too big", msg)
				continue
			}

			uploadFileContext, ok := pendingUploads.Get(msg.Path)
			if !ok || uploadFileContext.ConnId != connId {
				// Same error whether missing or owned by another connection.
				sendError(conn, "transfer not found", msg)
				continue
			}

			// Get only updates LRU recency, not the absolute TTL. Re-Add the
			// same entry so ExpiresAt is renewed while the transfer is active;
			// abandoned uploads still expire after PENDING_UPLOAD_VALIDITY_TIME
			// of inactivity.
			pendingUploads.Add(msg.Path, uploadFileContext)

			if uploadFileContext.BytesReceived+uint64(len(msg.Content)) > uploadFileContext.FileSize {
				//uploadFileContext.Cleanup(true)
				pendingUploads.Remove(msg.Path)
				sendError(conn, "too much data received", msg)
				continue
			}

			// Write data to file.
			_, err := uploadFileContext.Fd.Write(msg.Content)
			if err != nil {
				//uploadFileContext.Cleanup(true)
				pendingUploads.Remove(msg.Path)
				sendError(conn, err.Error(), msg)
				continue
			}
			uploadFileContext.BytesReceived += uint64(len(msg.Content))

			// Check if upload is terminated.
			if uploadFileContext.BytesReceived == uploadFileContext.FileSize {
				uploadFileContext.Cleanup(false)
				pendingUploads.Remove(msg.Path)
			}
			sendSuccess(conn, msg)

		case "download":
			if len(msg.Path) == 0 {
				sendError(conn, "path missing", msg)
				continue
			} else if len(msg.Path) > MAX_PATH_LENGTH {
				sendError(conn, "path too long", msg)
				continue
			} else if !isPathAllowed(msg.Path) {
				sendError(conn, "no such file or directory", msg)
				continue
			}

			// Get file information.
			info, err := os.Stat(msg.Path)
			if pathErr, ok := err.(*os.PathError); ok {
				sendError(conn, pathErr.Err.Error(), msg)
				continue
			} else if err != nil {
				sendError(conn, err.Error(), msg)
				continue
			}

			// Make sure it is a file and not a directory.
			if info.IsDir() {
				sendError(conn, "path is a directory", msg)
				continue
			}

			absPath, err := filepath.Abs(msg.Path)
			if err != nil {
				sendError(conn, err.Error(), msg)
				continue
			}

			if ok := pendingDownloads.Contains(absPath); ok {
				sendError(conn, "download in progress", msg)
				continue
			}

			// Add the file to the pending downloads cache.
			fileUUID := uuid.New().String()
			pendingDownloads.Add(fileUUID, absPath)

			// Send to WebSocket.
			writeMessagePack(conn, struct {
				Type    string  `msgpack:"type"`
				UUID    string  `msgpack:"uuid"`
				Request Message `msgpack:"req"` // The original message from client.
			}{Type: "success", UUID: fileUUID, Request: msg})

		default:
			sendError(conn, "unknown message type", msg)
		}
	}

	// Clear all pending uploads of this client.
	defer func() {
		keys := pendingUploads.Keys()
		for _, key := range keys {
			uploadFileContext, ok := pendingUploads.Peek(key)
			if ok && uploadFileContext.ConnId == connId {
				pendingUploads.Remove(key)
			}
		}
	}()
}

// isValidFileName reports whether name is a single path component suitable
// for rename (no separators, ".", or "..").
func isValidFileName(name string) bool {
	if name == "" || name == "." || name == ".." {
		return false
	}
	// Reject separators and null bytes that could form another path.
	if strings.ContainsAny(name, `/\`+string(filepath.Separator)+"\x00") {
		return false
	}
	// filepath.Base collapses directory components; mismatch means a path.
	if filepath.Base(name) != name {
		return false
	}
	return true
}

func addAllowedPath(path string) error {
	allowedPaths = append(allowedPaths, path)
	return nil
}

func addDeniedPath(path string) error {
	deniedPaths = append(deniedPaths, path)
	return nil
}

func isPathAllowed(path string) bool {
	// Check denied paths.
	for _, deniedPath := range deniedPaths {
		ok, err := hasSubpath(path, deniedPath)
		if err == nil && ok {
			return false
		}
	}

	// Check allowed paths.
	if len(allowedPaths) == 0 {
		return true
	} else {
		for _, allowedPath := range allowedPaths {
			ok, err := hasSubpath(path, allowedPath)
			if err == nil && ok {
				return true
			}
		}
		return false
	}
}

// resolvePath returns an absolute path with symlinks evaluated. If the final
// component does not exist yet (create/upload), existing parent components are
// still resolved so a symlink parent cannot smuggle a path outside the
// allowlist.
func resolvePath(path string) (string, error) {
	absPath, err := filepath.Abs(path)
	if err != nil {
		return "", err
	}

	resolved, err := filepath.EvalSymlinks(absPath)
	if err == nil {
		return resolved, nil
	}

	// Walk up until an existing prefix can be resolved, then rejoin the
	// missing trailing components.
	var missing []string
	current := absPath
	for {
		if current == filepath.Dir(current) {
			return "", err
		}
		missing = append(missing, filepath.Base(current))
		current = filepath.Dir(current)

		resolved, err = filepath.EvalSymlinks(current)
		if err == nil {
			for i := len(missing) - 1; i >= 0; i-- {
				resolved = filepath.Join(resolved, missing[i])
			}
			return resolved, nil
		}
	}
}

func hasSubpath(path string, basePath string) (bool, error) {
	// Resolve absolute paths and symlinks so allow/deny checks cannot be
	// bypassed via a symlink under an allowed path.
	absPath, err := resolvePath(path)
	if err != nil {
		return false, err
	}

	absBasePath, err := resolvePath(basePath)
	if err != nil {
		return false, err
	}

	if absPath == absBasePath {
		return true, nil
	} else if absBasePath == string(filepath.Separator) {
		// Root is a parent of every absolute path.
		return true, nil
	} else if strings.HasPrefix(absPath, absBasePath) {
		// Base path should be followed by a separator, otherwise
		// it's not a subpath.
		if absPath[len(absBasePath)] == filepath.Separator {
			// It's a subpath.
			return true, nil
		}
	}

	// No match found.
	return false, nil
}

func sortFilesAscend(files []os.DirEntry) {
	sort.Slice(files, func(i, j int) bool {
		// If both are directories or both are files, compare by name.
		if files[i].IsDir() == files[j].IsDir() {
			return files[i].Name() < files[j].Name()
		}
		// Directories should come first, regardless of the name.
		return files[i].IsDir()
	})
}

func listDir(path string) ([]FileInfo, error) {
	dir, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer dir.Close()

	entries, err := dir.ReadDir(-1)
	if err != nil {
		return nil, err
	}

	sortFilesAscend(entries)

	var files []FileInfo
	for _, entry := range entries {
		files = append(files, FileInfo{
			Name:  entry.Name(),
			Path:  filepath.Join(path, entry.Name()),
			IsDir: entry.IsDir(),
		})
	}
	return files, nil
}

func sendError(conn *websocket.Conn, errMsg string, req Message) {
	data := struct {
		Type    string  `msgpack:"type"`
		Error   string  `msgpack:"error"`
		Request Message `msgpack:"req"` // The original message from client.
	}{Type: "error", Error: errMsg, Request: req}

	// Content can be huge, so make sure we don't send it back
	// to the client.
	data.Request.Content = nil

	// Send the data.
	writeMessagePack(conn, data)
}

func sendSuccess(conn *websocket.Conn, req Message) {
	data := struct {
		Type    string  `msgpack:"type"`
		Request Message `msgpack:"req"` // The original message from client.
	}{Type: "success", Request: req}

	// Content can be huge, so make sure we don't send it back
	// to the client.
	data.Request.Content = nil

	// Send the data.
	writeMessagePack(conn, data)
}
