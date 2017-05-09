/*
 * UI module for noVNC HTML5 VNC client.
 *
 * == Hideable Navagation Bar ==
 */

"use strict";

var HideableNavbarModule = {
  enabled: true,
  prio: 5,
  conflicts: [],

  // ID of the element of the navbar that contains the module's button.
  navbarButtonContainer: '#navbarHideableNavbarButton',
  // ID of the button that activate/deactivate the module.
  navbarButton: '#hideableNavbarToggleButton',

  /****************************************************************************
   * Module callbacks
   ****************************************************************************/

  load: function() {
    // Nothing to do.
    // Set initial state according to saved value.
    return UI.getSetting('hideablenavbar', false);
  },

  unload: function() {
    // Nothing to do.
  },

  activate: function() {
    // Remove the top margin of the RFB screen.
    $('#rfbScreen').css('margin-top', '0px');
    // Add event handlers.
    $('.navbar-btn').on('click', this.handleNavbarButtonClick);
    // Update button active state.
    $('#hideableNavbarToggleButton').addClass('active');
    // Add callback on RFB state changes.
    UI.rfbUpdateStateCallbacks.add(this.handleRFBStateUpdate);
    // Make the show/hide navbar button draggable.
    $('#navbarVisibilityToggleButton').draggable({
      axis: 'x',
      containment: 'window',
      cancel:false,
      start: function(event, ui) { UI.rfbDisplayBlur(); },
      stop: function(event, ui) { UI.rfbDisplayFocus(); },
    });
    // Add the show/hide navbar button.
    $('#navbarVisibilityToggleButton').on('click', this.toggleVisibility);
    $('#navbarVisibilityToggleButton').removeClass('hide');
    // Save the state.
    UI.saveSetting('hideablenavbar', true);
    // Schedule navbar hide.
    HideableNavbarModule.scheduleHide(1000);
  },

  deactivate: function() {
    // Clear timer.
    clearTimeout(this.hideTimeout);
    // Restore the top margin of the RFB screen.
    $('#rfbScreen').css('margin-top', '51px');
    // Remove event handlers.
    $('.navbar-btn').off('click', this.handleNavbarButtonClick);
    // Update button active state.
    $('#hideableNavbarToggleButton').removeClass('active');
    // Remove callback on RFB state changes.
    UI.rfbUpdateStateCallbacks.remove(this.handleRFBStateUpdate);
    // Remove draggable functionality from the show/hide navbar button.
    $('#navbarVisibilityToggleButton').draggable('destroy');
    // Remove the show/hide navbar button.
    $('#navbarVisibilityToggleButton').off('click', this.toggleVisibility);
    $('#navbarVisibilityToggleButton').addClass('hide');
    // Save the state.
    UI.saveSetting('hideablenavbar', false);
  },

  /****************************************************************************
   * Module functions
   ****************************************************************************/

  handleRFBStateUpdate: function(rfb, state, oldstate, msg) {
    if (state === 'normal') {
      // Now that we are fully connected, hide the navbar.
      HideableNavbarModule.scheduleHide(1500);
    }
    else {
      // Make sure the navbar is shown.
      HideableNavbarModule.show();
    }
  },

  hide: function() {
    if (UI.rfb_state !== 'normal') return;
    if ($('.navbar').is(':visible')) {
      $('.navbar').slideUp(400);
      $('#navbarVisibilityToggleButton').animate({ 'top': '0px' }, 400, function() {
        $('#navbarVisibilityToggleButtonIcon').removeClass('fa-chevron-up');
        $('#navbarVisibilityToggleButtonIcon').addClass('fa-chevron-down');
      });
    }
  },

  show: function(event) {
    clearTimeout(HideableNavbarModule.hideTimeout);
    if (!$('.navbar').is(':visible')) {
      $('.navbar').slideDown(400);
      $('#navbarVisibilityToggleButton').animate({ "top": "50px" }, 400, function() {
        $('#navbarVisibilityToggleButtonIcon').removeClass('fa-chevron-down');
        $('#navbarVisibilityToggleButtonIcon').addClass('fa-chevron-up');
      });
    }
  },

  toggleVisibility: function(event) {
    if ($('.navbar').is(':visible')) {
      HideableNavbarModule.hide();
    } else {
      HideableNavbarModule.show();
    }
  },

  scheduleHide: function(timeout) {
    timeout = timeout || 350;
    clearTimeout(HideableNavbarModule.hide);
    HideableNavbarModule.hideTimeout =
        setTimeout(HideableNavbarModule.hide, timeout);
  },

  handleNavbarButtonClick: function(event) {
    if ($(this).attr('id') === 'hideableNavbarToggleButton') {
      // This handler is registered only when hideable navbar is enabled.  Thus,
      // clicking on the hideable navbar button means that we are disabling the
      // feature.
      return;
    }
    // When a button in the navbar is clicked, automatically hide the navbar.
    HideableNavbarModule.scheduleHide();
  },
};

/* Add the module. */
(function() {
  ModuleMgr.modules['HideableNavbar'] = HideableNavbarModule;
})();
