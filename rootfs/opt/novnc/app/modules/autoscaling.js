/*
 * UI module for noVNC HTML5 VNC client.
 *
 * == Auto Scaling ==
 */

"use strict";

var AutoScalingModule = {
  enabled: true,
  prio: 5,
  conflicts: ['Clipping'],

  // ID of the element of the navbar that contains the module's button.
  navbarButtonContainer: '#navbarAutoScalingButton',
  // ID of the button that activate/deactivate the module.
  navbarButton: '#autoScalingToggleButton',

  /****************************************************************************
   * Module callbacks
   ****************************************************************************/

  load: function() {
    // Nothing to do.
    // Set initial state according to saved value.
    return UI.getSetting('autoscaling', true);
  },

  unload: function() {
    // Nothing to do.
  },

  activate: function() {
    // Add event handlers.
    $(window).on('resize', this.handleWindowResize);
    $(document).on('UIModule:HideableNavbar', this.handleNavbarChange);
    // Add RFB callback.
    UI.rfbFBUCompleteCallbacks.add(this.handleFBUComplete);
    // Apply autoscaling.
    this.updateDisplay(true);
    // Save the auto scaling state.
    UI.saveSetting("autoscaling", true);

    Util.Info("Auto scaling enabled");
  },

  deactivate: function() {
    // Remove event handlers.
    $(window).off('resize', this.handleWindowResize);
    $(document).off('UIModule:HideableNavbar', this.handleNavbarChange);
    // Remove RFB callback.
    UI.rfbFBUCompleteCallbacks.remove(this.handleFBUComplete);
    // Apply auto scaling.
    this.updateDisplay(false);
    // Save the auto scaling state.
    UI.saveSetting('autoscaling', false);

    Util.Info("Auto scaling disabled");
  },

  /****************************************************************************
   * Module functions
   ****************************************************************************/

  updateDisplay: function(autoScale) {
    if (!UI.rfb) return;
    if (!UI.rfb.get_display()) return;

    var scaleRatio;
    var display = UI.rfb.get_display();

    if (autoScale) {
      var screen = UI.screenSize();
      var downscaleOnly = true;
      scaleRatio = display.autoscale(screen.w, screen.h, downscaleOnly);
    }
    else {
      scaleRatio = 1.0;
      display.set_scale(scaleRatio);
    }

    UI.rfb.get_mouse().set_scale(scaleRatio);
    Util.Debug('Scaling by ' + UI.rfb.get_mouse().get_scale());
  },

  handleFBUComplete: function(rfb, fbu) {
    // This callback is invoked only when auto scaling is enabled.
    AutoScalingModule.updateDisplay.bind(AutoScalingModule)(true);
  },

  handleWindowResize: function() {
    // Resize events are handled only when auto scaling is enabled.
    AutoScalingModule.updateDisplay.bind(AutoScalingModule)(true);
  },

  handleNavbarChange: function(event, action) {
    if (action === 'activated' || action === 'deactivated') {
      AutoScalingModule.updateDisplay.bind(AutoScalingModule)(true);
    }
  },
};

/* Add the module. */
(function() {
  ModuleMgr.modules['AutoScaling'] = AutoScalingModule;
})();
