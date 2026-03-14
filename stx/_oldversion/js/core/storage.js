// ─────────────────────────────────────────────
// STORAGE (STX namespace)
// ─────────────────────────────────────────────
window.STX = (function () {
  var NS = 'styx.';
  return {
    get: function (k) {
      try {
        return JSON.parse(localStorage.getItem(NS + k));
      } catch (e) {
        return null;
      }
    },
    set: function (k, v) {
      localStorage.setItem(NS + k, JSON.stringify(v));
    },
    merge: function (k, p) {
      this.set(k, $.extend(true, this.get(k) || {}, p));
    },
    del: function (k) {
      localStorage.removeItem(NS + k);
    },
  };
})();
