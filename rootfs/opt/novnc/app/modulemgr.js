/*
 * Module manager for noVNC HTML5 VNC client UI.
 *
 * Actions that can be done on modules:
 *
 *  - Load:       Setup UI elements (buttons), event handlers or any
 *                initialization needed by the module.
 *  - Unload:     Undo actions performed during the load phase.
 *  - Activate:   Turn on the functionality of the module.
 *  - Deactivate: Turn off the functionality of the module.
 *
 */

"use strict";

var ModuleMgr = {
  // List of modules to manage.
  modules: {},

  initialized: false,

  /*
   * Initialize list of modules.
   */
  init: function() {
    for (var module in this.modules) {
      var mod = this.modules[module];
      // Config.
      mod.enabled = (typeof mod.enabled === 'undefined') ? false : mod.enabled;
      if (typeof mod.prio === 'undefined') mod.prio = 5;
      if (typeof mod.conflicts === 'undefined') mod.conflicts = [];
      // Initial states.
      mod.loaded = false;
      mod.active = false;
      mod.wantActive = false;
    }
    this.initialized = true;
  },

  /*
   * Load all enabled modules.
   */
  start: function() {
    if (!this.initialized) {
      this.init();
    }

    for (var module in this.modules) {
      if (!this.isEnabled(module)) continue;
      this.load(module);
    }
  },

  /*
   * Determine if a module is enabled or not.
   */
  isEnabled: function(module) {
    var mod = this.modules[module];
    switch (typeof mod.enabled) {
      case 'boolean':
        return mod.enabled;
      case 'function':
        return mod.enabled();
      case 'undefined':
        return false;
      default:
        Util.Error("Module " + module + " has invalid type for property " +
                   "'enabled': " + typeof mod.enabled);
    }
  },

  /*
   * Load a specific module.
   */
  load: function(module) {
    var mod = this.modules[module];
    if (mod.loaded) return;

    Util.Info("Loading module " + module + "...");

    // Invoke the module's load callback.
    var activate = mod.load();
    mod.loaded = true;
    // Add module's button event handlers.
    if (typeof mod.navbarButton !== 'undefined') {
      $(mod.navbarButton).on('click', { module: module },
          this.toggleActivation);
    }
    // Make sure the module's button is not in activate state.
    if (typeof mod.navbarButton != 'undefined') {
      $(mod.navbarButton).removeClass('active');
    }
    // Show the module's button in navbar.
    if (typeof mod.navbarButtonContainer !== 'undefined') {
      $(mod.navbarButtonContainer).removeClass('hide');
    }
    // Send the load event.
    $(document).trigger("UIModule:" + module, [ 'loaded' ]);
    // Activate the module if needed.
    if (activate) {
      this.activate(module);
    }
    // Module loaded successfully.
    return true;
  },

  /*
   * Unload a specific module.
   */
  unload: function(module) {
    var mod = this.modules[module];
    if (!mod.loaded) return;

    // First, make sure the module is deactivated.
    this.deactivate(module);

    Util.Info("Unloading module " + module + "...");

    // Remove module's button event handlers.
    if (typeof mod.navbarButton != 'undefined') {
      $(mod.navbarButton).off('click', this.toggleActivation);
    }
    // Hide the module's button in navbar.
    if (typeof mod.navbarButtonContainer !== 'undefined') {
      $(mod.navbarButtonContainer).addClass('hide');
    }
    // Make sure the module's button is not in activate state.
    if (typeof mod.navbarButton != 'undefined') {
      $(mod.navbarButton).removeClass('active');
    }
    // Invoke the module's unload callback.
    mod.unload(module);
    mod.loaded = false;
    // Send the unload event.
    $(document).trigger("UIModule:" + module, [ 'unloaded' ]);
    // Schedule check in case a module can now be activated.
    this.scheduleCheck();
  },

  /*
   * Determine if a module is loaded or not.
   */
  isLoaded: function(module) {
    var mod = this.modules[module];
    if (typeof mod === 'undefined') return false;
    return mod.loaded;
  },

  /*
   * Activate a specific module.
   */
  activate: function(module) {
    var mod = this.modules[module];
    if (mod.active) return;

    mod.wantActive = true;
    if (this.handleConflicts(module)) {
      Util.Info("Activating module " + module + "...");
      // Invoke module's activation callback.
      mod.activate();
      mod.active = true;
      // Update the active state of the navbar button.
      if (typeof mod.navbarButton !== 'undefined') {
        $(mod.navbarButton).addClass('active');
      }
      // Send module activated event.
      $(document).trigger("UIModule:" + module, [ 'activated' ]);
      // Module has been activated successfully.
      return true;
    }
    // Module has not been activated.
    return false;
  },

  /*
   * Deactivate a specific module.
   */
  deactivate: function(module, wantActive) {
    var mod = this.modules[module];
    if (!mod.active) return;

    Util.Info("Deactivating module " + module + "...");
    mod.wantActive = wantActive ? true : false;
    // Update the active state of the navbar button.
    if (typeof mod.navbarButton !== 'undefined') {
      $(mod.navbarButton).removeClass('active');
    }
    // Invoke module's deactivation callback.
    mod.deactivate();
    mod.active = false;
    // Send module deactivated event.
    $(document).trigger("UIModule:" + module, [ 'deactivated' ]);
    // Schedule check in case a module can now be activated.
    this.scheduleCheck();
  },

  /*
   * Determine if a module is active or not.
   */
  isActive: function(module) {
    var mod = this.modules[module];
    if (typeof mod === 'undefined') return false;
    return mod.active;
  },

  /*
   * Determine if a module is wanted to be active.
   */
  isActiveWanted: function(module) {
    var mod = this.modules[module];
    return mod.wantActive;
  },

  /*
   * Handle module conflicts.
   *
   * Called when during activation of a module.  A conflict occurs when two
   * identified modules need to be active at the same time.  The resolution is
   * quite simple:  if the current module as higher priority, conflictual
   * modules are deactivated.  Else, the current module is not activated.
   */
  handleConflicts: function(module) {
    var mod = this.modules[module];
    var to_deactivate = [];
    var can_proceed = true;
    for (var index in mod.conflicts) {
      var c_module = mod.conflicts[index];
      if (this.isActive(c_module)) {
        var c_mod = this.modules[c_module];
        if (mod.prio > c_mod.prio) {
          to_deactivate.push(c_module);
        } else {
          Util.Info("Module '" + module +
              "' will not be activated because higher-priority module '" +
              c_module + "' is active.");
          can_proceed = false;
          break;
        }
      }
    }

    if (can_proceed) {
      for (var index in to_deactivate) {
        var c_module = to_deactivate[index];
        Util.Info("Deactivating module '" + c_module +
            "' because higher-priority module '" + module +
            "' is beging activated.");
        this.deactivate(c_module, true);
      }
    }

    return can_proceed;
  },

  /*
   * Schedule check for missing active module(s).  Scheduling is required to
   * debounce checks.
   */
  scheduleCheck: function() {
    clearTimeout(ModuleMgr.checkTimeout);
    ModuleMgr.checkTimeout = setTimeout(function() {
      Util.Debug("Checking for modules that should be activated...");
      for (var module in ModuleMgr.modules) {
        if (!ModuleMgr.isEnabled(module)) continue;
        if (ModuleMgr.isActive(module)) continue;
        if (!ModuleMgr.isActiveWanted(module)) continue;
        ModuleMgr.activate(module);
      }
    }, 0);
  },

  toggleActivation: function(event) {
    var module = event.data.module;
    var mod = ModuleMgr.modules[module];
    if (typeof mod.navbarButton !== 'undefined') {
      if ($(mod.navbarButton).hasClass('active')) {
        ModuleMgr.deactivate(module);
      }
      else {
        ModuleMgr.activate(module);
      }
    }
  },
};
