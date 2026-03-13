// ─────────────────────────────────────────────
// FILE BROWSER
// ─────────────────────────────────────────────
(function ($, API) {

  var _browseTarget      = null;
  var _browseCurrent     = '';
  var _browseBase        = '';
  var _browseRoot        = '';
  var _browseIsFolderOnly = false;

  function _browseDisplay(apiPath) {
    var rel = apiPath;
    if (_browseBase && apiPath.indexOf(_browseBase) === 0) {
      rel = apiPath.slice(_browseBase.length).replace(/^\//, '');
    }
    if (_browseRoot) {
      var base = _browseRoot.replace(/[\\\/]+$/, '');
      return rel ? base + '\\' + rel.replace(/\//g, '\\') : base;
    }
    return rel ? rel.replace(/\//g, '\\') : '(root)';
  }

  window.loadBrowseDir = function (apiPath) {
    _browseCurrent = apiPath || '';
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
      $('#browsePath').val(_browseDisplay(_browseCurrent));
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
      _browseRoot = '';
      _browseBase = '';
      _browseIsFolderOnly = false;

      if ($btn.data('ver-action') === 'browse') {
        _browseTarget = $btn.closest('.fg-ctrl').find('[name="customVersion"]');
      } else {
        _browseTarget = $btn.closest('.f-row').find('input[type="text"]').first();
      }

      if ($btn.hasClass('btn-browse-env')) {
        _browseRoot = API.getRoot();
        _browseBase = '';
        _browseTarget = $btn.closest('.f-row').find('[name="environment"]');
        var envVal = (_browseTarget.val() || '').trim();
        startPath = envVal ? envToApiPath(envVal) : '';
      }
      if ($btn.hasClass('btn-browse-ufx')) {
        _browseRoot = API.getRoot();
        _browseIsFolderOnly = $btn.closest('.f-row').find('[name="isFolder"]').is(':checked');
      }
      if ($btn.hasClass('btn-browse-folder')) {
        _browseRoot = API.getRoot();
        _browseIsFolderOnly = true;
      }

      if (_browseTarget && !_browseTarget.length) _browseTarget = null;
      loadBrowseDir(startPath);
      openModal('mBrowse');
    });

    // Dossier → naviguer dedans
    $(document).on('click', '#fileList .file-item[data-folder]', function () {
      var sub = $(this).data('folder');
      loadBrowseDir(_browseCurrent ? _browseCurrent + '/' + sub : sub);
    });

    // ".." → remonter
    $(document).on('click', '#fileList .file-up', function () {
      var parts = _browseCurrent.split('/');
      parts.pop();
      loadBrowseDir(parts.join('/'));
    });

    // Fichier → sélectionner directement
    $(document).on('click', '#fileList .file-file', function () {
      var file = $(this).data('file');
      var apiPath = _browseCurrent ? _browseCurrent + '/' + file : file;
      $('#browsePath').val(_browseDisplay(apiPath));
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
