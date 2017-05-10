/*
 * UI module for noVNC HTML5 VNC client.
 *
 * == Clipboard ==
 */

"use strict";

var ClipboardModule = {
  enabled: true,
  prio: 5,
  conflicts: [],

  // ID of the element of the navbar that contains the module's button.
  navbarButtonContainer: '#navbarClipboardButton',

  clipboardContent: '',

  /****************************************************************************
   * Module callbacks
   ****************************************************************************/

  load: function() {
    // Nothing to do.
    // Always activate the module.
    return true;
  },

  unload: function() {
    // Nothing to do.
  },

  activate: function() {
    // Add event handlers.
    $('#clipboardModal').on('shown.bs.modal', this.handleModalOpened);
    $('#clipboardModal').on('hidden.bs.modal', this.handleModalClosed);
    $('#ClearClipboardButton').on('click', this.contentClear);
    $('#SubmitClipboardButton').on('click', this.contentSend);
    // Register the RFB callback.
    UI.rfb.set_onClipboard(this.contentReceive);
  },

  deactivate: function() {
    // Remove event handlers.
    $('#clipboardModal').off('shown.bs.modal', this.handleModalOpened);
    $('#clipboardModal').off('hidden.bs.modal', this.handleModalClosed);
    $('#ClearClipboardButton').off('click', this.contentClear);
    $('#SubmitClipboardButton').off('click', this.contentSend);
    // Unregister the RFB callback.
    UI.rfb.set_onClipboard(function(){});
  },

  /****************************************************************************
   * Module functions
   ****************************************************************************/

  // Called by the RFB when something is copied to the clipboard.
  contentReceive: function(rfb, text) {
    Util.Debug(">> UI.contentReceive: " + text.substr(0,40) + "...");
    ClipboardModule.clipboardContent = text;
    $('#clipboard_content').val(text);
    Util.Debug("<< UI.contentReceive");
  },

  // Send clipboard content to the RFB.
  contentSend: function(event) {
    var text = ClipboardModule.clipboardContent = $('#clipboard_content').val();
    if(text === '') {
      // It's not possible to clear the clipboard of the remote side.  Send
      // a single space to at least have synchronized clipboard.
      text = ' ';
    }
    Util.Debug(">> UI.contentSend: " + text.substr(0,40) + "...");
    UI.rfb.clipboardPasteFrom(text);
    Util.Debug("<< UI.contentSend");
    $('#clipboardModal').modal('hide');
  },

  contentClear: function(event) {
    $('#clipboard_content').val("");
    $('#clipboard_content').focus();
  },

  handleModalOpened: function() {
    $('#clipboard_content').focus();
    UI.rfbDisplayBlur();
  },

  handleModalClosed: function() {
    UI.rfbDisplayFocus();
    $('#clipboard_content').val(ClipboardModule.clipboardContent);
  },
};

/* Add the module. */
(function() {
  ModuleMgr.modules['Clipboard'] = ClipboardModule;
})();
