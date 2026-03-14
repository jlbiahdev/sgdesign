// ─────────────────────────────────────────────
// FILE BROWSER
// ─────────────────────────────────────────────
(function ($, API) {

  var _browseTarget       = null;
  var _browseCurrent      = '';   // normalized path (forward slashes, no leading slash) sent to API
  var _browseBase         = '';   // normalized root — ".." is hidden when current === base
  var _browseRootDisplay  = '';   // original UNC prefix for display reconstruction
  var _browseIsFolderOnly = false;

  // Convert any path to forward slashes, strip leading/trailing slashes
  function _norm(p) {
    return (p || '').replace(/\\/g, '/').replace(/^\/+|\/+$/g, '');
  }

  // Rebuild a displayable path (UNC style) from a normalized api path
  function _display(apiPath) {
    if (_browseRootDisplay) {
      var normRoot = _norm(_browseRootDisplay);
      var rel = (normRoot && apiPath.indexOf(normRoot) === 0)
        ? apiPath.slice(normRoot.length).replace(/^\/+/, '')
        : apiPath;
      var base = _browseRootDisplay.replace(/[\\\/]+$/, '');
      return rel ? base + '\\' + rel.replace(/\//g, '\\') : base;
    }
    return apiPath ? apiPath.replace(/\//g, '\\') : '(root)';
  }

  window.loadBrowseDir = function (apiPath) {
    _browseCurrent = _norm(apiPath);
    API.exploreDir(_browseCurrent, { isFolder: _browseIsFolderOnly }).then(function (node) {
      var html = '';
      if (_browseCurrent !== _browseBase) {
        html += '<div class="file-item file-up"><span>📁</span> ..</div>';
      }
      node.folders.forEach(function (f) {
        html += '<div class="file-item" data-folder="' + f + '"><span>📁</span> ' + f + '</div>';
      });
      node.files.forEach(function (f) {
        html += '<div class="file-item file-file" data-file="' + f + '"><span>📄</span> ' + f + '</div>';
      });
      if (!html) html = '<div style="color:var(--text-dim);font-size:.65rem;padding:8px 4px">Empty folder</div>';
      $('#fileList').html(html);
      $('#browsePath').val(_display(_browseCurrent));
    });
  };

  $(function () {

    $(document).on('click', '.btn-open-env', function () {
      var path = $(this).closest('.f-row').find('[name="environment"]').val().trim();
      if (!path) {
        openConsole();
        cLog('Open : aucun chemin Environment renseigné.', 'error');
        return;
      }
      var uri;
      if (/^\\\\/.test(path)) {
        uri = 'file:' + path.replace(/\\/g, '/');
      } else {
        uri = 'file:///' + path.replace(/\\/g, '/').replace(/^\/+/, '');
      }
      window.open(uri);
      cLog('Ouverture dans l\'explorateur : ' + path);
    });

    $(document).on('click', '.btn-browse', function () {
      var $btn = $(this);
      var startPath = '';
      _browseRootDisplay  = '';
      _browseBase         = '';
      _browseIsFolderOnly = false;

      if ($btn.data('ver-action') === 'browse') {
        _browseTarget = $btn.closest('.fg-ctrl').find('[name="customVersion"]');
      } else {
        _browseTarget = $btn.closest('.f-row').find('input[type="text"]').first();
      }

      if ($btn.hasClass('btn-browse-env')) {
        _browseIsFolderOnly = true;
        _browseTarget = $btn.closest('.f-row').find('[name="environment"]');
        var envVal = (_browseTarget.val() || '').trim();
        startPath           = envVal;
        _browseRootDisplay  = envVal;
        _browseBase         = _norm(envVal);
      }
      if ($btn.hasClass('btn-browse-ufx')) {
        _browseRootDisplay  = API.getRoot();
        _browseBase         = _norm(API.getRoot());
        _browseIsFolderOnly = $btn.closest('.f-row').find('[name="isFolder"]').is(':checked');
      }
      if ($btn.hasClass('btn-browse-folder')) {
        _browseRootDisplay  = API.getRoot();
        _browseBase         = _norm(API.getRoot());
        _browseIsFolderOnly = true;
      }

      if (_browseTarget && !_browseTarget.length) _browseTarget = null;
      loadBrowseDir(startPath);
      openModal('mBrowse');
    });

    // Folder → navigate into it
    $(document).on('click', '#fileList .file-item[data-folder]', function () {
      var sub = $(this).data('folder');
      loadBrowseDir(_browseCurrent ? _browseCurrent + '/' + sub : sub);
    });

    // ".." → go up one level
    $(document).on('click', '#fileList .file-up', function () {
      var parts = _browseCurrent.split('/');
      parts.pop();
      loadBrowseDir(parts.join('/'));
    });

    // File → update path display only
    $(document).on('click', '#fileList .file-file', function () {
      var file = $(this).data('file');
      var apiPath = _browseCurrent ? _browseCurrent + '/' + file : file;
      $('#browsePath').val(_display(apiPath));
    });

    $('#btnFileSelect').on('click', function () {
      var path = $('#browsePath').val();
      if (_browseTarget) {
        _browseTarget.val(path).trigger('input').trigger('change');
        _browseTarget = null;
      }
      cLog('Chemin sélectionné : ' + path);
      closeModal('mBrowse');
    });

  });

}(jQuery, window.API));
