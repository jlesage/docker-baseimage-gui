/*
 * UI module for noVNC HTML5 VNC client.
 *
 * == Right click for touch interface ==
  */

"use strict";

var RightClickModule = {
  enabled: function() {return UI.isTouchDevice && !UI.rfb.get_view_only();},
  prio: 5,

  // Module variables.
  onMouseButtonCallback: null,
  onMouseMoveCallback: null,
  mouseLBD: false,
  mouseLBDTime: null,
  mouseLBDPos: {},
  mouseLBDHasMoved: false,

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
    this.onMouseButtonCallback = this.onMouseButton.bind(this);
    this.onMouseMoveCallback = this.onMouseMove.bind(this);
    // Add RFB callback.
    UI.rfbOnMouseButtonCallbacks.add(this.onMouseButtonCallback);
    UI.rfbOnMouseMoveCallbacks.add(this.onMouseMoveCallback);
  },

  deactivate: function() {
    // Remove RFB callback.
    UI.rfbOnMouseButtonCallbacks.remove(this.onMouseButtonCallback);
    UI.rfbOnMouseMoveCallbacks.remove(this.onMouseMoveCallback);
  },

  /****************************************************************************
   * Module functions
   ****************************************************************************/

  onMouseButton: function (rfb, x, y, down, bmask) {
    if (rfb.get_view_only()) return;

    this.mouseLBD = false;
    if (bmask === 0x1) { // Left button?
      if (down) {
        this.mouseLBD = true;
        this.mouseLBDTime = new Date().getTime();
        this.mouseLBDPos = {'x': x, 'y': y};
        this.mouseLBDHasMoved = false;
      } else {
        if (!this.mouseLBDHasMoved) {
          if (new Date().getTime() - this.mouseLBDTime > 500) {
            // Send right-click.
            RFB.messages.pointerEvent(rfb._sock,
                                      rfb.get_display().absX(x),
                                      rfb.get_display().absY(y),
                                      0x4);
          }
        }
      }
    }
  },

  onMouseMove: function (rfb, x, y) {
    if (rfb.get_view_only()) return;

    if (this.mouseLBD && !this.mouseLBDHasMoved) {
      var deltaX = this.mouseLBDPos.x - x;
      var deltaY = this.mouseLBDPos.y - y;
      var dragThreshold = 10 * (window.devicePixelRatio || 1);
      if (Math.abs(deltaX) > dragThreshold ||
          Math.abs(deltaY) > dragThreshold) {
        this.mouseLBDHasMoved = true;
      }
    }
  },
};

/* Add the module. */
(function() {
  ModuleMgr.modules['RightClick'] = RightClickModule;
})();
