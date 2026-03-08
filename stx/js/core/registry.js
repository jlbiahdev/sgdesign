// ─────────────────────────────────────────────
// JOB REGISTRY — OCP fix
// Each job file calls JobRegistry.register(descriptor) at load time.
// Adding a new job type = one new file, nothing else to modify.
// ─────────────────────────────────────────────
window.JobRegistry = (function () {
  var _jobs = {};
  return {
    // Register a job descriptor:
    // {
    //   type:     string,
    //   label:    string,
    //   tabIcon:  'omen' | 'ufx' | 'monitoring' | 'tool',
    //   build:    function(id) -> HTML string,
    //   validate: function($view, name) -> string[],
    //   init:     function($view) -> void   (optional),
    //   buildAdv: function() -> HTML string (optional),
    //   help:     { synopsis: string, fields: [[label, desc], ...] }
    // }
    register: function (def) {
      _jobs[def.type] = def;
    },
    get: function (type) {
      return _jobs[type] || null;
    },
    getAll: function () {
      return $.extend({}, _jobs);
    },
    getLabel: function (type) {
      return (_jobs[type] || {}).label || type;
    },
  };
})();
