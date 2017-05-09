/*
 * UI module for noVNC HTML5 VNC client.
 *
 * == Virtual Keyboard ==
 */

"use strict";

var VirtualKeyboardModule = {
  enabled: function() {return UI.isTouchDevice && !UI.rfb.get_view_only();},
  prio: 5,
  conflicts: [],

  // ID of the element of the navbar that contains the module's button.
  navbarButtonContainer: '#navbarVirtualKeyboardButton',
  // ID of the button that activate/deactivate the module.
  navbarButton: '#virtualKeyboardToggleButton',

  /****************************************************************************
   * Module callbacks
   ****************************************************************************/

  load: function() {
    // Nothing to do.
    // Initially virtual keyboard is not active.
    return false;
  },

  unload: function() {
    // Nothing to do.
  },

  activate: function() {
    // Add event handlers.
    //$('#virtualKeyboardInput').on('keydown', UI.handleKeyDown);
    //$('#virtualKeyboardInput').on('keypress', UI.handleKeyPress);
    $('#virtualKeyboardInput').on('focusout', this.handleFocusOut);
    // Set focus on textbox.
    $('#virtualKeyboardInput').focus();
    // Collapse the navbar.
    if ($('.navbar-toggle').is(':visible')) {
      $('.navbar-toggle').click();
    }
  },

  deactivate: function() {
    // Remove event handlers.
    //$('#virtualKeyboardInput').off('keydown', UI.handleKeyDown);
    //$('#virtualKeyboardInput').off('keypress', UI.handleKeyPress);
    $('#virtualKeyboardInput').off('focusout', this.handleFocusOut);
    // Remove focus from textbox.
    $('#virtualKeyboardInput').blur();
  },

  /****************************************************************************
   * Module functions
   ****************************************************************************/

  handleFocusOut: function() {
    // When the keyboard is enabled, clicking the keyboard button will generate
    // the 'focusout' event before the button's click handler.  So we cannot
    // deactivate the keyboard right now, because the button's click handler
    // will see the 'deactivated' state and will activate the keyboard again.
    setTimeout(function() {
      ModuleMgr.deactivate('VirtualKeyboard'); },
      100);
    },

   /*
   handleKeyDown: function(event) {
     // Here, a key code is received.  See
     // https://www.w3schools.com/jsref/event_key_keycode.asp
     var keyCode = event.which;

     // Stop propagating the event.
     event.preventDefault();
     return false;
   },

   handleKeyPress: function(event) {
     // Here, a character code is received.  See
     // https://www.w3schools.com/jsref/event_key_keycode.asp
     var uniCharCode = event.which;
     UI.rfb.sendKey(uniCharCode);
   },
   */
};

/* Add the module */
(function() {
  ModuleMgr.modules['VirtualKeyboard'] = VirtualKeyboardModule;
})();
