/*
 * UI module for noVNC HTML5 VNC client.
 *
 * == Viewport Drag ==
 */

"use strict";

var ViewportDragModule = {
  enabled: false,
  prio: 5,
  conflicts: [],

  // ID of the element of the navbar that contains the module's button.
  navbarButtonContainer: '#navbarClippingViewportDragButton',
  // ID of the button that activate/deactivate the module.
  navbarButton: '#clippingViewportDragToggleButton',

  /****************************************************************************
   * Module callbacks
   ****************************************************************************/

  load: function() {
    // Nothing to do.
    // Initially viewport drag is not active.
    return false;
  },

  unload: function() {
    // Nothing to do.
  },

  activate: function() {
    UI.rfb.set_viewportDrag(true);
  },

  deactivate: function() {
    UI.rfb.set_viewportDrag(false);
  },
};

/* Add the module. */
(function() {
  ModuleMgr.modules['ViewportDrag'] = ViewportDragModule;
})();
