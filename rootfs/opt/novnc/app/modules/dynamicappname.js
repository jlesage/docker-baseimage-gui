/*
 * UI module for noVNC HTML5 VNC client.
 *
 * == Dynamic Application Name ==
 */

"use strict";

var DynamicAppNameModule = {
  enabled: true,
  prio: 5,
  conflicts: [],

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
    // Register the RFB callback.
    UI.rfbDesktopNameCallbacks.add(this.appNameReceive);
  },

  deactivate: function() {
    // Unregister the RFB callback.
    UI.rfbDesktopNameCallbacks.remove(this.appNameReceive);
  },

  /****************************************************************************
   * Module functions
   ****************************************************************************/

  appNameReceive: function(rfb, name) {
    UI.appNameUpdate(name);
  },
};

/* Add the module. */
(function() {
  ModuleMgr.modules['DynamicAppName'] = DynamicAppNameModule;
})();
