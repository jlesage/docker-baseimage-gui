/*
 * UI module for noVNC HTML5 VNC client.
 *
 * == Fullscreen ==
 */

"use strict";

var FullscreenModule = {
  enabled: function() {return !UI.isSafari;},
  prio: 5,
  conflicts: [],

  // ID of the element of the navbar that contains the module's button.
  navbarButtonContainer: '#navbarFullscreenButton',
  // ID of the button that activate/deactivate the module.
  navbarButton: '#fullscreenToggleButton',

  /****************************************************************************
   * Module callbacks
   ****************************************************************************/

  load: function() {
    // Nothing to do.
    // Initially fullscreen is not active.
    return false;
  },

  unload: function() {
    // Nothing to do.
  },

  activate: function() {
    if (document.documentElement.requestFullscreen) {
      document.documentElement.requestFullscreen();
    } else if (document.documentElement.mozRequestFullScreen) {
      document.documentElement.mozRequestFullScreen();
    } else if (document.documentElement.webkitRequestFullscreen) {
      document.documentElement.webkitRequestFullscreen(Element.ALLOW_KEYBOARD_INPUT);
    } else if (document.body.msRequestFullscreen) {
      document.body.msRequestFullscreen();
    }
  },

  deactivate: function() {
    if (document.fullscreenElement || // alternative standard method
        document.mozFullScreenElement || // currently working methods
        document.webkitFullscreenElement ||
        document.msFullscreenElement) {
      if (document.exitFullscreen) {
        document.exitFullscreen();
      } else if (document.mozCancelFullScreen) {
        document.mozCancelFullScreen();
      } else if (document.webkitExitFullscreen) {
        document.webkitExitFullscreen();
      } else if (document.msExitFullscreen) {
        document.msExitFullscreen();
      }
    }
  },
};

/* Add the module. */
(function() {
  ModuleMgr.modules['Fullscreen'] = FullscreenModule;
})();
