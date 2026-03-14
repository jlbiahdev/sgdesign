// ─────────────────────────────────────────────
// API — appels HTTP vers le backend ASP.NET Core
// ─────────────────────────────────────────────
window.API = (function ($, STX) {

  var _baseUrl = (STX.get('settings') || {}).apiBaseUrl || '';

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
      console.error('[API]', method, path, '→', xhr.status, msg);
      return $.Deferred().reject({ status: xhr.status, message: msg }).promise();
    });
  }

  function _exploreDir(path, opts) {
    var params = { rootFolder: path || '' };
    if (opts && opts.isFolder)  params.isFolder  = true;
    if (opts && opts.extension) params.extension = opts.extension;
    return _ajax('GET', '/api/JobEnvironment/explore?' + $.param(params))
      .then(function (resp) {
        return { folders: resp.folders || [], files: resp.files || [], scenarios: resp.scenarios || null };
      });
  }

  return {
    get: function (path) {
      return _ajax('GET', path);
    },
    post: function (path, data) {
      return _ajax('POST', path, data);
    },
    exploreDir: function (path, opts) {
      return _exploreDir(path, opts);
    },
    getRoot: function () {
      return (STX.get('settings') || {}).apiRoot || '';
    },
    getBaseUrl: function ()    { return _baseUrl; },
    setBaseUrl: function (url) { _baseUrl = url; },
  };
}(jQuery, window.STX));
