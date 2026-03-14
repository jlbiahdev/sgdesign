// ─────────────────────────────────────────────
// API (fake via fake_api.json + real HTTP)
// ─────────────────────────────────────────────
window.API = (function ($, STX) {

  // ── Mode & config (persistés dans STX 'settings') ──
  var _mode    = (STX.get('settings') || {}).apiMode    || 'fake';
  var _baseUrl = (STX.get('settings') || {}).apiBaseUrl || '';

  // ══════════════════════════════════════════════
  // FAKE — lit fake_api.json
  // ══════════════════════════════════════════════
  var _db = null;
  var _fakeReady = $.getJSON('fake_api.json').then(function (data) { _db = data; });

  function _fakeResolve(method, path) {
    if (!_db) return undefined;
    var key = method + ' ' + path;
    if (key in _db) return _db[key];
    var noQ = path.split('?')[0];
    var base = method + ' ' + noQ;
    if (base in _db) return _db[base];
    var parent = method + ' ' + noQ.replace(/\/[^/]+$/, '');
    return parent in _db ? _db[parent] : undefined;
  }

  function _fakeCall(method, path) {
    return $.Deferred(function (dfd) {
      $.when(_fakeReady).then(function () {
        var resp = _fakeResolve(method, path);
        if (resp === undefined) {
          console.warn('[API:fake] No response for:', method, path);
          dfd.reject({ status: 404, message: 'Not found in fake_api.json: ' + method + ' ' + path });
          return;
        }
        setTimeout(function () { dfd.resolve($.extend(true, {}, resp)); }, 120);
      });
    }).promise();
  }

  var _tree = null;
  function _ensureTree() {
    if (!_tree && _db) _tree = (_db['GET /api/JobEnvironment/explore'] || {})._tree || {};
    return _tree || {};
  }

  function _fakeExploreDir(path, opts) {
    var isFolder  = !!(opts && opts.isFolder);
    var extension = (opts && opts.extension) ? String(opts.extension).replace(/^\./, '').toLowerCase() : null;
    return $.Deferred(function (dfd) {
      $.when(_fakeReady).always(function () {
        var node = _ensureTree()[path || ''] || { folders: [], files: [] };
        var files = node.files || [];
        if (isFolder) {
          files = [];
        } else if (extension) {
          files = files.filter(function (f) {
            return f.toLowerCase().slice(-(extension.length + 1)) === '.' + extension;
          });
        }
        dfd.resolve({ folders: node.folders || [], files: files, scenarios: node.scenarios || null });
      });
    }).promise();
  }

  // ══════════════════════════════════════════════
  // REAL — appels HTTP vers _baseUrl
  // ══════════════════════════════════════════════
  function _ajax(method, path, data) {
    var opts = {
      url: _baseUrl + path,
      method: method,
      contentType: 'application/json',
      headers: { Accept: 'application/json' },
    };
    if (data !== undefined) opts.data = JSON.stringify(data);
    return $.ajax(opts).then(null, function (xhr) {
      var msg = '';
      try { msg = xhr.responseJSON.message || xhr.statusText; } catch (e) { msg = xhr.statusText || String(xhr.status); }
      console.error('[API:real]', method, path, '→', xhr.status, msg);
      return $.Deferred().reject({ status: xhr.status, message: msg }).promise();
    });
  }

  function _realExploreDir(path, opts) {
    var params = { rootFolder: path || '' };
    if (opts && opts.isFolder)  params.isFolder  = true;
    if (opts && opts.extension) params.extension = opts.extension;
    return _ajax('GET', '/api/JobEnvironment/explore?' + $.param(params))
      .then(function (resp) {
        return { folders: resp.folders || [], files: resp.files || [], scenarios: resp.scenarios || null };
      });
  }

  // ══════════════════════════════════════════════
  // Interface publique
  // ══════════════════════════════════════════════
  return {
    get: function (path) {
      return _mode === 'real' ? _ajax('GET', path) : _fakeCall('GET', path);
    },
    post: function (path, data) {
      return _mode === 'real' ? _ajax('POST', path, data) : _fakeCall('POST', path);
    },
    exploreDir: function (path, opts) {
      return _mode === 'real' ? _realExploreDir(path, opts) : _fakeExploreDir(path, opts);
    },
    getRoot: function () {
      return _mode === 'real'
        ? ((STX.get('settings') || {}).apiRoot || '')
        : (_db ? ((_db['GET /api/JobEnvironment/explore'] || {})._root || '') : '');
    },
    getMode:    function ()    { return _mode; },
    setMode:    function (m)   { _mode = m; },
    getBaseUrl: function ()    { return _baseUrl; },
    setBaseUrl: function (url) { _baseUrl = url; },
  };
}(jQuery, window.STX));
