import * as Log from '../core/util/logging.js';

function escapeHtml(str) {
    if (str === null) return str;
    return str
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;');
}

function unescapeHtml(str) {
    if (str === null) return str;
    return str
        .replace(/&amp;/g, '&')
        .replace(/&lt;/g, '<')
        .replace(/&gt;/g, '>')
        .replace(/&quot;/g, '"')
        .replace(/&#39;/g, "'");
}

const fileReaderModule = (function() {
    return class FileReaderModule {
        constructor(f) {
            // Private variables.
            let blockSize = 512 * 1024;
            let file = null;
            let filePos = 0;
            let reader = null;
            let blob = null;
            let eventCallbacks = {
                'block': [],
                'error': [],
            };

            // Private methods.

            function init(f) {
                file = f;
                reader = new FileReader();

                // Register the function called when a block has been read from
                // disk.
                reader.onloadend = function(e) {
                    if (e.target.readyState == FileReader.DONE) {
                        let arrayBuffer = e.target.result;
                        filePos += arrayBuffer.byteLength;

                        // Invoke defined callbacks.
                        eventCallbacks['block'].forEach(function (func, index) {
                            func(arrayBuffer, filePos, file.size);
                        });
                    }
                };

                reader.onerror = function(e) {
                    // Delegate error handling to registered callbacks so the
                    // module using this FileReader can decide how to react.

                    // Invoke defined callbacks.
                    eventCallbacks['error'].forEach(function (func) {
                        func(e);
                    });
                };
            }

            // Public methods.

            this.addEventListener = function(e, f) {
                if (eventCallbacks[e] !== undefined) {
                    eventCallbacks[e].push(f);
                }
            };

            this.requestNextBlock = function() {
                if (reader && filePos < file.size) {
                    let first = filePos;
                    let last = first + blockSize
                    if (last > file.size) {
                        last = file.size;
                    }
                    blob = file.slice(first, last);
                    reader.readAsArrayBuffer(blob);
                }
            }

            this.stop = function() {
                if (reader) {
                    reader.onloadend = null;
                    reader = null;
                }
                file = null;
                blob = null;
            }

            // Do the initialization.
            init(f);

        }
    };
})();

// FileManager Module
const FileManager = (function() {
    let webSocket = null;
    let webSocketUrl = null;
    let webSocketConnected = false;
    let webSocketConnectTimer = null;
    let fileManagerOpened = false;
    let moduleEventCallbacks = {
        'close': [],
    };
    let currentPath = '/';
    let activeUpload = null;
    let activeDownload = null;
    let activePopover = null;
    let activePopoverTarget = null;

    function initialize(wsUrl) {
        webSocketUrl = wsUrl;
        connectWebSocket();

        // File manager dialog close button handling.
        document.querySelector('.fmgr-dialog-close-btn').addEventListener('click', () => {
            closeFileManager();
        });

        // Upload button click handling.
        document.querySelector('.fmgr-upload-btn').addEventListener('click', () => {
            discardActivePopover();
            document.querySelector('.fmgr-file-input').click();
        });
        document.querySelector('.fmgr-file-input').addEventListener('change', (e) => {
            uploadFiles(e.target.files);
        });

        // New folder button click handling.
        document.querySelector('.fmgr-new-folder-btn').addEventListener('click', (e) => {
            discardActivePopover();
            confirmCreateFolder(e.target, currentPath);
        });

        // Go up button click handling.
        document.querySelector('.fmgr-go-up-btn').addEventListener('click', () => {
            discardActivePopover();
            goUp();
        });

        // Upload cancel button click handling.
        document.querySelector('.fmgr-upload-cancel-btn').addEventListener('click', () => {
            terminateUpload(true);
        });

        // Refresh button click handling.
        document.querySelector('.fmgr-refresh-btn').addEventListener('click', () => {
            discardActivePopover();
            refresh();
        });

        // Add click effect on all buttons of the toolbar.
        const buttons = document.querySelectorAll('.fmgr-dialog .toolbar .btn');
        buttons.forEach(button => {
          button.addEventListener('mousedown', () => {
            // Add the clicked effect immediately.
            button.classList.add('btn-clicked');
          });
          // Remove the clicked effect once the click ends.
          button.addEventListener('mouseup', () => {
            setTimeout(() => {
              button.classList.remove('btn-clicked');
            }, 100);
          });
          // Remove the effect if the user cancels the click
          // (e.g., mouse leaves before releasing).
          button.addEventListener('mouseleave', () => {
            button.classList.remove('btn-clicked');
          });
        });

        // Handle form submission from popover. Event delegation must be used
        // because popover HTML is generated dynamically.
        document.body.addEventListener('submit', function (event) {
            if (event.target && event.target.closest('#popoverForm')) {
                event.preventDefault(); // Prevent form submission.

                if (!activePopover || !activePopoverTarget) return;

                const action = event.target.querySelector('#popoverActionInput').value;
                const userInputElem = event.target.querySelector('#popoverUserTextInput');
                const userInput = userInputElem ? userInputElem.value : null;
                const fileEntryElem = activePopoverTarget.closest('.fmgr-file-list-entry');

                discardActivePopover();
                handleConfirmAction(action, userInput, fileEntryElem);
            }
        });

        // Handle cancel button from popover. Event delegation must be used
        // because popover HTML is generated dynamically.
        document.body.addEventListener('click', function(event) {
            if (event.target && event.target.id === 'popoverCancelButton') {
                discardActivePopover();
            }
        });

        // Handle action buttons from file list. Event delegation must be used
        // because the file list HTML is generated dynamically.
        document.querySelector('.fmgr-dialog').addEventListener('click', function(event) {
            if (!event.target) return;
            const targetElem = event.target.closest('.fmgr-file-action');
            if (targetElem) {
                const action = targetElem.getAttribute('data-fmgr-file-action');
                const fileEntryElem = targetElem.closest('.fmgr-file-list-entry');
                discardActivePopover();
                handleFileActionClick(action, targetElem, fileEntryElem);
            }
        });
    }

    function connectWebSocket() {
        if (webSocket) return;

        Log.Info("Establishing WebSocket connection for file manager...");
        webSocket = new WebSocket(webSocketUrl);
        webSocket.binaryType = 'arraybuffer';

        webSocket.onmessage = (event) => {
            handleWebSocketMessage(event);
        };

        //webSocket.onerror = function(error) {
        //    Log.Error("WebSocket connection for file manager error:", error);
        //};

        webSocket.onopen = function(e) {
            Log.Info("WebSocket connection for file manager established");
            webSocketConnected = true;
            if (fileManagerOpened) {
                clearError();
                refresh();
            }
        };

        webSocket.onclose = function(event) {
            if (event.wasClean) {
                Log.Info(`WebSocket connection for file manager closed, code=${event.code} reason=${event.reason}`);
            } else {
                // e.g. server process killed or network down
                // event.code is usually 1006 in this case
                Log.Info('WebSocket connection for file manager died');
            }

            // Destroy the connection.
            webSocket = null;
            webSocketConnected = false;

            // Attempt to re-connect.
            if (fileManagerOpened) {
                Log.Info('WebSocket reconnection for file manager will be attempted');
                webSocketConnectTimer = setTimeout(connectWebSocket, 1000);
            }
        };
    }

    function openFileManager() {
        if (!fileManagerOpened) {
            fileManagerOpened = true;

            // Connect to WebSocket if needed.
            if (webSocketConnected) {
                clearError();
                refresh();
            } else {
                currentPath = '/';
                renderFileList(currentPath, null);
                showError("Not connected to web services server.");
                connectWebSocket();
            }

            // Show the file manager dialog.
            document.querySelector('.fmgr-dialog').classList.add('noVNC_open');

            return true;
        } else {
            return false;
        }
    }

    function closeFileManager() {
        if (fileManagerOpened) {
            fileManagerOpened = false;

            // Hide the file manager dialog.
            document.querySelector('.fmgr-dialog').classList.remove('noVNC_open');

            // Stop trying to connect to WebSocket.
            clearTimeout(webSocketConnectTimer);

            // Discard any active popover.
            discardActivePopover();

            // Invoke the close callbacks.
            moduleEventCallbacks['close'].forEach(function (func, index) {
                func();
            });
            return true;
        } else {
            return false;
        }
    }

    function handleWebSocketMessage(event) {
        const data = msgpack.decode(new Uint8Array(event.data));

        Log.Debug("Received message: " + JSON.stringify(data));

        switch (data.type) {
            case 'error':
                showError(data);
                switch (data.req.type) {
                    case 'upload':
                    case 'uploadBlock':
                        terminateUpload(false);
                        break;
                    case 'download':
                        terminateDownload();
                        break;
                }
                break;
            case 'success':
                clearError();
                switch (data.req.type) {
                    case 'listDir':
                        renderFileList(data.req.path, data.files);
                        break;
                    case 'upload':
                        startUpload();
                        break;
                    case 'uploadBlock':
                        advanceUpload();
                        break;
                    case 'download':
                        startDownload(data.uuid);
                        break;
                    case 'rename':
                    case 'delete':
                    case 'createFolder':
                    case 'cancelUpload':
                        refresh();
                        break;
                }
                break;
        }
    }

    function handleFileActionClick(action, targetElem, fileEntryElem) {
        if (!action || !targetElem || !fileEntryElem) return;

        const name = unescapeHtml(fileEntryElem.getAttribute('data-fmgr-file-name'));
        const path = unescapeHtml(fileEntryElem.getAttribute('data-fmgr-file-path'));

        if (!name || !path) return;

        switch (action) {
            case 'navigate':
                navigate(path);
                break;
            case 'download':
                downloadFile(name, path);
                break;
            case 'rename':
                const isDir = targetElem.getAttribute('data-fmgr-file-is-dir');
                confirmRename(targetElem, name, path, isDir === 'true');
                break;
            case 'delete':
                confirmDelete(targetElem, path);
                break;
        }
    }

    function showPopover(elem, title, content, placement) {
        discardActivePopover();

        activePopover = new bootstrap.Popover(elem, {
            title: title,
            content: content,
            html: true,
            sanitize: false, // Disable sanitization to allow HTML content
            trigger: 'click',
            placement: placement,
        });
        activePopoverTarget = elem;

        activePopover.show();
    }

    function discardActivePopover() {
        if (activePopover !== null) {
            activePopover.dispose();
            activePopover = null;
            activePopoverTarget = null;
        }
    }

    function showError(message) {
        if (typeof message === 'object') {
            let errMsg = message.error === undefined ? "unknown error" : message.error;

            if (message.req !== undefined) {
                switch (message.req.type) {
                    case 'listDir':
                        errMsg = `: ${errMsg}.`;
                        break;
                    case 'rename':
                        errMsg = `Rename operation failed: ${errMsg}.`;
                        break;
                    case 'delete':
                        errMsg = `Delete operation failed: ${errMsg}.`;
                        break;
                    case 'createFolder':
                        errMsg = `Create directory operation failed: ${errMsg}.`;
                        break;
                    case 'upload':
                    case 'uploadBlock':
                        errMsg = `Upload operation failed: ${errMsg}.`;
                        break;
                    case 'download':
                        errMsg = `Download operation failed: ${errMsg}.`;
                        break;
                    default:
                        errMsg = `Operation failed: ${errMsg}.`;
                        break;
                }
            }

            message = errMsg;
        }

        const alertHtml = `
                    <div class="alert alert-danger alert-dismissible fade show m-0" role="alert">
                        ${message}
                        <button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="Close"></button>
                    </div>
        `;

        // Replace the current alert. If we want to add/stack multiple alerts,
        // we would use the following call instead:
        //    document.querySelector('.fmgr-alert').insertAdjacentHTML('beforeend', alertHtml);
        document.querySelector('.fmgr-alert').innerHTML = alertHtml;
    }

    function clearError() {
        document.querySelector('.fmgr-alert').innerHTML = '';
    }

    function confirmRename(targetElem, name, path, isDir) {
        const escapedFileName = escapeHtml(name);
        const escapedFilePath = escapeHtml(path);
        const popoverTitle = `Rename ${isDir ? 'Directory' : 'File'}`;
        const popoverContent = `
            <form id="popoverForm">
                <div class="mb-3">
                    <label for="popoverUserTextInput" class="form-label">Rename ${isDir ? 'directory' : 'file'} to:</label>
                    <input type="text" class="form-control" id="popoverUserTextInput" value="${escapedFileName}" required>
                    <input type="hidden" id="popoverActionInput" value="rename"></input>
                </div>
                <div class="d-flex justify-content-end column-gap-2">
                  <button type="button" class="btn btn-secondary" id="popoverCancelButton">Cancel</button>
                  <button type="submit" class="btn btn-primary">Rename</button>
                </div>
             </form>
        `;
        showPopover(targetElem, popoverTitle, popoverContent, 'left');
    }

    function confirmDelete(targetElem, path) {
        const escapedFilePath = escapeHtml(path);
        const popoverTitle = 'Confirm Deletion';
        const popoverContent = `
            <form id="popoverForm">
                <div class="mb-3">
                    Are you sure you want to delete <strong>${escapedFilePath}</strong>?
                    <input type="hidden" id="popoverActionInput" value="delete"></input>
                </div>
                <div class="d-flex justify-content-end column-gap-2">
                     <button type="button" class="btn btn-secondary" id="popoverCancelButton">Cancel</button>
                     <button type="submit" class="btn btn-danger">Delete</button>
                </div>
            </form>
        `;
        showPopover(targetElem, popoverTitle, popoverContent, 'left');
    }

    function confirmCreateFolder(targetElem, path) {
        const escapedFilePath = escapeHtml(path);
        const popoverTitle = 'Create Directory';
        const popoverContent = `
            <form id="popoverForm">
                <div class="mb-3">
                    <label for="popoverUserTextInput" class="form-label">Directory name:</label>
                    <input type="text" class="form-control" id="popoverUserTextInput" value="" required>
                    <input type="hidden" id="popoverActionInput" value="create"></input>
                </div>
                <div class="d-flex justify-content-end column-gap-2">
                  <button type="button" class="btn btn-secondary" id="popoverCancelButton">Cancel</button>
                  <button type="submit" class="btn btn-primary">Create</button>
                </div>
             </form>
        `;
        showPopover(targetElem, popoverTitle, popoverContent, 'bottom');
    }

    function handleConfirmAction(action, userInput, fileEntryElem) {
        let name = null
        let path = null

        if (fileEntryElem) {
            name = unescapeHtml(fileEntryElem.getAttribute('data-fmgr-file-name'));
            path = unescapeHtml(fileEntryElem.getAttribute('data-fmgr-file-path'));
        }

        switch (action) {
            case('rename'):
                if (path && userInput) {
                    webSocket.send(msgpack.encode({
                        type: 'rename', 
                        path: path, 
                        newName: `${userInput}` 
                    }));
                }
                break;
            case('delete'):
                if (path) {
                    webSocket.send(msgpack.encode({
                        type: 'delete',
                        path: `${path}`
                    }));
                }
                break;
            case('create'):
                if (userInput) {
                    webSocket.send(msgpack.encode({ 
                        type: 'createFolder', 
                        path: `${currentPath}/${userInput}` 
                    }));
                }
                break;
        }
    }

    // Render file list
    function renderFileList(path, files) {
        const fileList = document.querySelector('.fmgr-file-list');
        if (files === null) {
            files = [];
        }
        fileList.innerHTML = files.map(file => {
            const escapedFilePath = escapeHtml(file.path);
            const escapedFileName = escapeHtml(file.name);
            return `
            <div class="fmgr-file-list-entry d-flex align-items-center border-bottom py-2"
                data-fmgr-file-is-dir="${file.isDir ? 'true' : 'false'}"
                data-fmgr-file-name="${escapedFileName}"
                data-fmgr-file-path="${escapedFilePath}">
                <!-- File/folder icon. -->
                <span style="display: inline-block; width: 2em; min-width: 2em; text-align: center;">
                    <i class="fas ${file.isDir ? 'fa-folder text-warning' : 'fa-file text-info'}" 
                       style="font-size: 1.2em;"></i>
                </span>
                <!-- File/folder name. -->
                <span class="${file.isDir ? 'fmgr-file-action' : ''} flex-grow-1 ms-2 text-truncate" 
                      style="max-width: 100%; cursor: ${file.isDir ? 'pointer' : 'auto'}; transition: color 0.2s;"
                      title="${escapedFilePath}"
                      onmouseover="this.style.color='grey';"
                      onmouseout="this.style.color='inherit';"
                      ${file.isDir ? 'data-fmgr-file-action="navigate"' : ''}
                      >
                    ${file.name}
                </span>
                <!-- Action buttons. -->
                <div class="ms-auto d-flex flex-nowrap">
                    <button class="fmgr-file-action btn btn-sm btn-info mx-1" 
                            title="Download"
                            data-fmgr-file-action="download"
                            ${file.isDir ? 'disabled' : ''}>
                        <i class="fas fa-download"></i>
                    </button>
                    <button class="fmgr-file-action btn btn-sm btn-warning mx-1" 
                            title="Rename"
                            data-fmgr-file-action="rename">
                        <i class="fas fa-edit"></i>
                    </button>
                    <button class="fmgr-file-action btn btn-sm btn-danger mx-1" 
                            title="Delete"
                            data-fmgr-file-action="delete">
                        <i class="fas fa-trash"></i>
                    </button>
                </div>
            </div>
        `;
        }).join('');

        // Update the current path.
        currentPath = path;
        document.querySelector('.fmgr-current-path').textContent = path;
        document.querySelector('.fmgr-current-path').title = path;

        // Update the state of the go up button.
        document.querySelector('.fmgr-go-up-btn').disabled = currentPath === '/';
    }

    function refresh() {
        navigate(currentPath);
    }

    function navigate(path) {
        webSocket.send(msgpack.encode({
            type: 'listDir',
            path: path,
        }));
    }

    function goUp() {
        if (currentPath !== '/') {
            let path;
            const parts = currentPath.split('/').filter(Boolean);
            parts.pop();
            path = '/' + parts.join('/');
            if (path === '') path = '/';
            navigate(path);
        }
    }

    function uploadFiles(files) {
        if (activeUpload) {
            Log.Error("Could not upload file: transfer in progress.");
            return;
        }

        activeUpload = {
            destDir: currentPath,
            files: files,
            totalFiles: files.length,
            filesProcessed: 0,
            fileReader: null,
            curFileProgress: {
                cur: 0,
                tot: 0,
            },

            // The "prepare" stage sends the upload command to the server. The
            // command includes information about the file to upload and its
            // destination.
            prepare: function() {
                if (this.filesProcessed < this.totalFiles) {
                    webSocket.send(msgpack.encode({
                        type: 'upload',
                        path: this.destDir + '/' + this.files[this.filesProcessed].name,
                        size: this.files[this.filesProcessed].size,
                    }));
                }
            },

            // The "start" stage creates the file reader and starts the read
            // process. This stage invoked when we get a success answer from
            // the upload command that we sent.
            start: function() {
                if (this.fileReader) return;

                // Special case for empty files: nothing to read.
                if (this.files[this.filesProcessed].size === 0) {
                    advanceUpload();
                    return;
                }

                this.fileReader = new fileReaderModule(this.files[this.filesProcessed]);

                // Function to call when a file read error occurs.
                this.fileReader.addEventListener('error', (e) => {
                    showError("Upload operation failed: file read error.");
                    terminateUpload(true);
                });

                // Function to call when a file block is read from the disk. The
                // block has now to be sent to the server.
                this.fileReader.addEventListener('block', (blob, cur, tot) => {
                    this.curFileProgress.cur = cur;
                    this.curFileProgress.tot = tot;

                    // Send the blob to server.
                    webSocket.send(msgpack.encode({
                        type: 'uploadBlock',
                        path: this.destDir + '/' + this.files[this.filesProcessed].name,
                        content: new Uint8Array(blob), // Convert to b64 ?
                    }));
                });

                // Start reading the file.
                this.fileReader.requestNextBlock();
            },

            // The "advance" stage updates the progress bar and request the
            // next block from the file. This stage is invoked we receive from
            // the server the request of the next block. This means that the
            // previous block was successfully sent.
            advance: function() {
                // Calculate progress, based on the current file progress and
                // the total number of files processed.
                const progress = Math.floor(
                    (this.filesProcessed + 1)
                    * Math.max(this.curFileProgress.cur, 1)
                    / Math.max(this.curFileProgress.tot, 1)
                    / this.totalFiles
                    * 100
                );

                const fileCompleted = (this.curFileProgress.cur === this.curFileProgress.tot);
                if (fileCompleted) {
                    this.filesProcessed++;
                    const allFilesCompleted = (this.filesProcessed === this.totalFiles);

                    // Prepare the next file.
                    if (!allFilesCompleted) {
                        this.fileReader = null;
                        this.prepare();
                    } else {
                        // All uploads completed.
                        return 100;
                    }
                } else {
                    // Request the next block.
                    this.fileReader.requestNextBlock();
                }
                return progress;
            },

            terminate: function(sendCancel) {
                // Destroy the file reader.
                if (this.fileReader) {
                    this.fileReader.stop();
                    this.fileReader = null;
                }

                // Send the cancel operation to the server.
                if (sendCancel) {
                    webSocket.send(msgpack.encode({
                        type: 'cancelUpload',
                        path: this.destDir + '/' + this.files[this.filesProcessed].name,
                    }));
                }
            },
        };

        // Disable the upload button.
        document.querySelector('.fmgr-upload-btn').disabled = true;

        // Show the progress bar.
        const progressBar = document.querySelector('.fmgr-progress-bar');
        progressBar.setAttribute('aria-valuenow', 0);
        progressBar.querySelector('.progress-bar').style.width = '0%';
        document.querySelector('.fmgr-upload-progress').classList.remove('d-none');

        // Begin the upload.
        activeUpload.prepare();
    }

    function startUpload() {
        if (activeUpload) {
            activeUpload.start();
        }
    }

    function advanceUpload() {
        if (activeUpload) {
            let progress = activeUpload.advance();

            // Update the progress bar.
            const progressBar = document.querySelector('.fmgr-progress-bar');
            progressBar.setAttribute('aria-valuenow', progress);
            progressBar.querySelector('.progress-bar').style.width = `${progress}%`;

            if (progress == 100) {
                refresh();
                terminateUpload(false);
            }
        }
    }

    function terminateUpload(fromUser) {
        if (activeUpload) {
            activeUpload.terminate(fromUser);
            activeUpload = null;

            document.querySelector('.fmgr-file-input').value = '';

            setTimeout(() => {
                // Hide progress bar.
                document.querySelector('.fmgr-upload-progress').classList.add('d-none');

                // Re-enable the upload button.
                document.querySelector('.fmgr-upload-btn').disabled = false;
            }, 800);
        }
    }

    function downloadFile(name, path) {
        if (activeDownload) return;

        activeDownload = {
            fileName: name,
        };

        webSocket.send(msgpack.encode({
            type: 'download',
            path: `${path}`,
        }));
    }

    function startDownload(fileUUID) {
        if (activeDownload) {
            const link = document.createElement('a');
            link.href = `./download/${fileUUID}`;
            link.download = activeDownload.fileName;
            document.body.appendChild(link); 
            link.click();
            document.body.removeChild(link);
            activeDownload = null;
        }
    }

    function terminateDownload() {
        if (activeDownload) {
            activeDownload = null;
        }
    }

    // Public API
    return {
        init: function(wsUrl) {
            initialize(wsUrl);
        },

        initLogging: function(level) {
            Log.initLogging(level);
        },

        open: function() {
            return openFileManager();
        },

        close: function() {
            return closeFileManager();
        },

        addEventListener: function(e, f) {
            if (moduleEventCallbacks[e] !== undefined) {
                moduleEventCallbacks[e].push(f);
            }
        },

    };
})();

export default FileManager;
