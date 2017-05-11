/*
 * UI module for noVNC HTML5 VNC client.
 *
 * == Clipping ==
 */

"use strict";

var ClippingModule = {
  enabled: true,
  prio: 4,
  conflicts: ['AutoScaling'],

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
    $(window).on('resize', this.updateDisplay);
    $(document).on('UIModule:HideableNavbar', this.handleUIModuleChange);
    // Add RFB callback.
    UI.rfbFBUCompleteCallbacks.add(this.updateDisplay);
    // Enable clipping.
    var display = UI.rfb.get_display();
    display.set_viewport(true);
    // Update display.
    this.updateDisplay();
  },

  deactivate: function() {
    // Remove event handlers.
    $(window).off('resize', this.updateDisplay);
    $(document).off('UIModule:HideableNavbar', this.handleUIModuleChange);
    // Remove RFB callback.
    UI.rfbFBUCompleteCallbacks.remove(this.updateDisplay);
    // Disable clipping.
    var display = UI.rfb.get_display();
    display.set_viewport(false);
    // Update display.
    this.updateDisplay();
  },

  /****************************************************************************
   * Module functions
   ****************************************************************************/

  updateDisplay: function() {
    var display = UI.rfb.get_display();
    var clip = display.get_viewport();

    if (clip) {
      var screen = UI.screenSize();

      // First, reset the viewport position that could have been changed by a
      // viewport drag.
      display.viewportChangePos(-display.get_maxWidth(), -display.get_maxHeight());

      display.set_maxWidth(screen.w);
      display.set_maxHeight(screen.h);

      // Keep display centered horizontally and on top.
      var vp_w = screen.w;
      var vp_h = screen.h;
      if (screen.w > display.get_width()) {
        vp_w = screen.w - (screen.w - display.get_width());
      }
      if (screen.h > display.get_height()) {
        vp_h = screen.h - (screen.h - display.get_height());
      }

      display.viewportChangeSize(vp_w, vp_h);
    }
    else {
      display.set_maxWidth(0);
      display.set_maxHeight(0);
      display.viewportChangeSize();
      display.viewportChangePos(0, 0); // Reset drag that could have been done.
    }

    // Enable viewport drag support if remote display is currently clipped.
    if (clip && display.clippingDisplay()) {
      ModuleMgr.load('ViewportDrag');
    }
    else {
      ModuleMgr.unload('ViewportDrag');
    }

    // Force frame buffer update.
    if (UI.rfb_state === 'normal') {
        UI.rfb.requestFrameBufferUpdate();
    }
  },

  handleUIModuleChange: function(event, action) {
    if (action === 'activated' || action === 'deactivated') {
      ClippingModule.updateDisplay.bind(ClippingModule)();
    }
  },
};

/* Add the module. */
(function() {
  ModuleMgr.modules['Clipping'] = ClippingModule;
})();
