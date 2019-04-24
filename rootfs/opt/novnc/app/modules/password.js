/*
 * UI module for noVNC HTML5 VNC client.
 *
 * == VNC Password ==
 */

"use strict";

var PasswordModule = {
  enabled: true,
  prio: 5,
  conflicts: [],

  passwordSent: false,

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
    // Initialize UI variables.
    this.passwordSent = false;
    // Add event handlers.
    $('#SubmitPasswordButton').on('click', this.passwordSet);
    $('#vnc_password').on('keypress', function(e) {
      var keycode = e.keyCode || e.which;
      if (keycode == 13) {
        PasswordModule.passwordSet();
      }
    });
    $('#passwordModal').on('hidden.bs.modal', this.handleModalClosed);
    // Register the RFB callback.
    UI.rfbPasswordRequiredCallbacks.add(this.passwordRequired);
  },

  deactivate: function() {
    // Remove event handlers.
    $('#SubmitPasswordButton').off('click', this.passwordSet);
    $('#passwordModal').off('hidden.bs.modal', this.handleModalClosed);
    // Unregister the RFB callback.
    UI.rfbPasswordRequiredCallbacks.remove(this.passwordRequired);
  },

  /****************************************************************************
   * Module functions
   ****************************************************************************/

  // Called by the RFB when a password is required.
  passwordRequired: function(rfb, msg) {
    PasswordModule.passwordSent = false;
    if (typeof msg === 'undefined') {
      msg = "Password is required";
    }
    $('#passwordModal').modal('show');
  },

  passwordSet: function(event) {
    PasswordModule.passwordSent = true;
    UI.rfb.sendPassword($('#vnc_password').val());
    $('#passwordModal').modal('hide');
  },

  handleModalClosed: function() {
    // If the modal has been closed but the password has not been sent, send an
    // empty password to re-trigger the passwordRequired() callback.  Make sure
    // to give up after some tries by sending an invalid passsword.
    if (!PasswordModule.passwordSent) {
      if (typeof PasswordModule.handleModalClosed.counter ==='undefined') {
        PasswordModule.handleModalClosed.counter = 0;
      }
      PasswordModule.handleModalClosed.counter++;
      if (PasswordModule.handleModalClosed.counter > 2) {
          UI.rfb.sendPassword('wefo859803sa26gycth2378K#*2#ry1209');
      }
      else {
          UI.rfb.sendPassword('');
      }
    }

    // Clear the password from the modal.
    $('#vnc_password').val('');
  },
};

/* Add the module. */
(function() {
  ModuleMgr.modules['Password'] = PasswordModule;
})();
