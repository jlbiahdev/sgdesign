// ─────────────────────────────────────────────
// CONTEXT MENU
// ─────────────────────────────────────────────
(function ($, STX, API, JobRegistry) {

  window._ctxClipboard = null; // { type, data }
  var _ctxMenu = null;

  var _CTX_ICONS = {
    'Refresh':           '<svg viewBox="0 0 14 14" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M12 7A5 5 0 1 1 9.5 2.8"/><polyline points="12 1 12 4.5 8.5 4.5"/></svg>',
    'Copy Settings':     '<svg viewBox="0 0 14 14" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><rect x="4.5" y="1" width="8" height="9" rx="1.2"/><rect x="1" y="4" width="8" height="9" rx="1.2"/></svg>',
    'Paste Settings':    '<svg viewBox="0 0 14 14" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><rect x="1" y="3" width="10" height="10" rx="1.2"/><path d="M4 3V2a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v1"/><line x1="4" y1="7" x2="8" y2="7"/><line x1="4" y1="9.5" x2="7" y2="9.5"/></svg>',
    'Copy to clipboard': '<svg viewBox="0 0 14 14" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M9 1H3a1 1 0 0 0-1 1v9"/><rect x="4" y="3" width="8" height="10" rx="1.2"/></svg>',
    'Open folder':       '<svg viewBox="0 0 14 14" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M1 3.5A1 1 0 0 1 2 2.5h3l1.5 1.5H12a1 1 0 0 1 1 1V11a1 1 0 0 1-1 1H2a1 1 0 0 1-1-1V3.5z"/></svg>',
    'Cancel job':        '<svg viewBox="0 0 14 14" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><circle cx="7" cy="7" r="5.5"/><line x1="4.5" y1="4.5" x2="9.5" y2="9.5"/><line x1="9.5" y1="4.5" x2="4.5" y2="9.5"/></svg>',
    'Requeue job':       '<svg viewBox="0 0 14 14" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="1 4 1 1 4 1"/><path d="M1 1l3.5 3.5A5.5 5.5 0 1 1 2.5 9"/></svg>',
  };

  window._hideCtxMenu = function () {
    if (_ctxMenu) { _ctxMenu.remove(); _ctxMenu = null; }
  };

  window._showCtxMenu = function (items, x, y) {
    _hideCtxMenu();
    var $m = $('<div class="ctx-menu"></div>');
    items.forEach(function (item) {
      var icon = _CTX_ICONS[item.label] || '';
      var $i = $('<div class="ctx-item"></div>').html(icon + '<span>' + item.label + '</span>');
      $i.on('click', function () { _hideCtxMenu(); item.action(); });
      $m.append($i);
    });
    $m.css({ left: x, top: y });
    $('body').append($m);
    _ctxMenu = $m;
  };

  window._monCtxJobItems = function ($tr, jobId, state, env, jobData) {
    var items = [];

    items.push({
      label: 'Copy to clipboard',
      action: function () {
        try { navigator.clipboard.writeText(env); } catch (ex) {}
      }
    });

    if (jobData && jobData.settings) {
      items.push({
        label: 'Copy Settings',
        action: function () {
          window._ctxClipboard = { type: jobData.settings.type, data: jobData.settings };
          try { navigator.clipboard.writeText(JSON.stringify(jobData.settings, null, 2)); } catch (ex) {}
        }
      });
    }

    items.push({
      label: 'Open folder',
      action: function () {
        if (env) window.open('file:///' + env.replace(/\\/g, '/'));
      }
    });

    var isTerminal = (state === 'done' || state === 'cancelled' || state === 'error');

    if (!isTerminal) {
      items.push({
        label: 'Cancel job',
        action: function () {
          API.post('/api/JobGrid/cancel/' + jobId).then(function () {
            $tr.find('.state-dot').removeClass().addClass('state-dot cancelled');
            $tr.attr('data-state', 'cancelled');
            openConsole();
            cLog('Job ' + jobId + ' — annulation demandée.', 'warn');
          });
        }
      });
    }

    if (isTerminal) {
      items.push({
        label: 'Requeue job',
        action: function () {
          API.post('/api/JobGrid/requeue/' + jobId).then(function () {
            $tr.find('.state-dot').removeClass().addClass('state-dot pending');
            $tr.attr('data-state', 'pending');
            openConsole();
            cLog('Job ' + jobId + ' — remis en file d\'attente.', 'warn');
          });
        }
      });
    }

    return items;
  };

  function _isFormValid($view) {
    var id = $view.attr('id').replace('view-', '');
    var type = (STX.get('job.' + id) || {}).type;
    var def = JobRegistry.get(type);
    if (!def || !def.validate) return false;
    var name = ($view.find('.field-name').val() || '').trim() || 'job';
    return def.validate($view, name).length === 0;
  }

  $(function () {

    $(document).on('contextmenu', '.job-view', function (e) {
      var $view = $(this);
      var id = $view.attr('id').replace('view-', '');
      var type = (STX.get('job.' + id) || {}).type;
      var def = JobRegistry.get(type);
      if (!type || !def || !def.validate) return;

      var valid = _isFormValid($view);
      var hasClip = !!(window._ctxClipboard && window._ctxClipboard.type === type);

      if (!valid && !hasClip) return;
      e.preventDefault();

      var items = [];

      items.push({
        label: 'Refresh',
        action: function () {
          var env = $view.find('[name="environment"]').val();
          if (!env) return;
          API.get('/api/JobManager/refreshinputs?environment=' + encodeURIComponent(env))
            .then(function (data) {
              var $sel = $view.find('[name="inputs"]');
              var cur = $sel.val();
              $sel.find('option:not(:first)').remove();
              (data.inputs || []).forEach(function (s) { $sel.append('<option>' + s + '</option>'); });
              if (cur) $sel.val(cur);
            });
        }
      });

      if (valid) {
        items.push({
          label: 'Copy Settings',
          action: function () {
            var data = STX.get('job.' + id);
            window._ctxClipboard = { type: type, data: data };
            try { navigator.clipboard.writeText(JSON.stringify(data, null, 2)); } catch (ex) {}
          }
        });
      }

      if (hasClip) {
        items.push({
          label: 'Paste Settings',
          action: function () {
            var data = window._ctxClipboard.data;
            restoreView($view, data);
            syncBrowseButtons($view);
            $view.find('.chk-period').trigger('change');

            if (data.adv) {
              var cur = STX.get('job.' + id) || {};
              STX.set('job.' + id, $.extend(cur, { adv: data.adv }));
              restoreView($('#sidePanelBody'), data.adv);
            }

            if (data.model) {
              $view.find('.ref-content [name="model"]').trigger('change');
              if (data.version) $view.find('.ref-content [name="version"]').val(data.version);
            }

            var envPath = envToApiPath($view.find('[name="environment"]').val());
            if (!envPath) { saveJobView($view); return; }

            API.exploreDir(envPath + '/input').then(function (node) {
              var $sel = $view.find('[name="inputs"]');
              $sel.find('option:not(:first)').remove();
              (node.folders || []).forEach(function (s) { $sel.append('<option>' + s + '</option>'); });
              if (data.inputs) $sel.val(data.inputs);
              saveJobView($view);
            });

            if ($view.find('.scen-table').length) {
              var _isRL = (type === 'risklife' || type === 'risklifekp' || type === 'brd');
              API.exploreDir(envPath + '/scenario').then(function (node) {
                if (!node.scenarios) return;
                if (_isRL) rebuildRLScenarios($view, node.scenarios);
                else rebuildScenarios($view, node.scenarios);
                if (data.scenarios) {
                  $view.find('.scen-table tbody tr').each(function () {
                    var num = $(this).find('td').eq(1).text().trim();
                    $(this).find('input[type=checkbox]').prop('checked', data.scenarios.indexOf(num) !== -1);
                  });
                }
              });
            }
          }
        });
      }

      _showCtxMenu(items, e.clientX, e.clientY);
    });

    // parentJob + childJob : full menu
    $(document).on('contextmenu', '#monitorBody .job-row, #monitorBody .child-row', function (e) {
      e.preventDefault();
      e.stopPropagation();
      var $tr = $(this);
      var jobId  = $tr.data('job-id') || $tr.data('child-id');
      var state  = ($tr.attr('data-state') || '').toLowerCase();
      var env    = $tr.attr('data-env') || '';
      var jobData = (window._monJobMap || {})[jobId] || (window._monChildMap || {})[jobId];
      var items = _monCtxJobItems($tr, jobId, state, env, jobData);
      if (items.length) _showCtxMenu(items, e.clientX, e.clientY);
    });

    // group + task : Open folder uniquement
    $(document).on('contextmenu', '#monitorBody .group-row, #monitorBody .task-row', function (e) {
      e.preventDefault();
      e.stopPropagation();
      var env = $(this).attr('data-env') || '';
      _showCtxMenu([{
        label: 'Open folder',
        action: function () {
          if (env) window.open('file:///' + env.replace(/\\/g, '/'));
        }
      }], e.clientX, e.clientY);
    });

    $(document).on('click', function (e) {
      if (_ctxMenu && !$(e.target).closest('.ctx-menu').length) _hideCtxMenu();
    });

    $(document).on('keydown', function (e) {
      if (e.key === 'Escape') _hideCtxMenu();
    });

  });

}(jQuery, window.STX, window.API, window.JobRegistry));
