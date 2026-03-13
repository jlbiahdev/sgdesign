// ─────────────────────────────────────────────
// MONITORING UI
// ─────────────────────────────────────────────
(function ($, STX, API) {

  window._monJobMap   = {}; // jobId   → job object
  window._monChildMap = {}; // childId → child object
  var _outputCache    = [];
  var _refreshTimer   = null;

  window.setMonitorRefreshInterval = function (ms) {
    if (_refreshTimer) { clearInterval(_refreshTimer); _refreshTimer = null; }
    if (ms > 0) {
      _refreshTimer = setInterval(function () {
        if ($('#view-monitoring').hasClass('active')) loadMonitoringJobs();
      }, ms);
    }
  };

  window.stopMonitorRefresh = function () {
    if (_refreshTimer) { clearInterval(_refreshTimer); _refreshTimer = null; }
    $('.mf-refresh').val('0');
  };

  // ── API ─────────────────────────────────────

  function apiGetJobs()            { return API.get('/api/JobGrid/jobs'); }
  function apiGetJobChildren(id)   { return API.get('/api/JobGrid/jobs/children?jobId=' + id); }
  function apiGetJobTasks(id)      { return API.get('/api/JobGrid/jobs/' + id + '/tasks'); }

  // ── Render helpers ───────────────────────────

  function fmtDate(iso) {
    if (!iso) return '';
    var d = new Date(iso);
    if (isNaN(d)) return iso;
    var mm  = String(d.getMonth() + 1).padStart(2, '0');
    var dd  = String(d.getDate()).padStart(2, '0');
    var hh  = String(d.getHours()).padStart(2, '0');
    var min = String(d.getMinutes()).padStart(2, '0');
    var ss  = String(d.getSeconds()).padStart(2, '0');
    return d.getSeconds() ? hh + ':' + min + ':' + ss : mm + '-' + dd + ' ' + hh + ':' + min;
  }

  function stateClass(state) {
    var s = String(state).toLowerCase();
    if (s === 'done' || s === 'finished' || s === '2') return 'done';
    if (s === 'running' || s === '1') return 'running';
    if (s === 'error' || s === 'failed' || s === '3') return 'error';
    if (s === 'cancelled' || s === 'canceled' || s === '4') return 'cancelled';
    return 'pending';
  }

  function progBar(pct) {
    return (
      '<div class="prog-wrap">' +
      '<div class="prog-bar" style="width:' + pct + '%"></div>' +
      '<span class="prog-pct">' + pct + '%</span>' +
      '</div>'
    );
  }

  function buildTasksTable(tasks, envPath) {
    if (!tasks || !tasks.length) return '';
    tasks = tasks.slice().sort(function (a, b) { return a.id - b.id; });
    var rows = tasks.map(function (t) {
      var taskEnv = (t.command || '').replace(/^(.*[\\\/])[^\\\/]*$/, '$1').replace(/[\\\/]$/, '') || envPath || '';
      taskEnv = taskEnv.replace(/"/g, '&quot;');
      var outputCell = '';
      if (t.output) {
        var oidx = _outputCache.push(t.output) - 1;
        outputCell = '<button class="btn-output-view" data-oidx="' + oidx + '" title="Voir l\'output">' +
          '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"><circle cx="6.5" cy="6.5" r="4.5"/><path d="M10.5 10.5L14 14"/></svg>' +
          '</button>';
      } else {
        outputCell = '<span class="output-empty">—</span>';
      }
      return (
        '<tr class="task-row" data-env="' + taskEnv + '">' +
        '<td><span class="state-dot ' + stateClass(t.state) + '"></span></td>' +
        '<td class="mono">' + t.id + '</td>' +
        '<td class="mono expand-cmd" title="' + (t.command || '').replace(/"/g, '&quot;') + '">' + (t.command || '') + '</td>' +
        '<td class="task-output-cell">' + outputCell + '</td>' +
        '<td class="mono">' + fmtDate(t.startTime) + '</td>' +
        '<td class="mono">' + fmtDate(t.endTime) + '</td>' +
        '</tr>'
      );
    }).join('');
    return (
      '<table class="expand-table">' +
      '<thead><tr><th>State</th><th>Id</th><th>Command</th><th>Output</th><th>Start time</th><th>End time</th></tr></thead>' +
      '<tbody>' + rows + '</tbody>' +
      '</table>'
    );
  }

  function buildChildrenTable(children, envPath) {
    if (!children || !children.length) return '';
    children = children.slice().sort(function (a, b) { return a.id - b.id; });
    var rows = children.map(function (c) {
      var env = (c.environment || envPath || '').replace(/"/g, '&quot;');
      window._monChildMap[c.id] = c;
      if (!c.environment && envPath) c.environment = envPath;
      return (
        '<tr class="child-row" data-child-id="' + c.id + '" data-state="' + stateClass(c.state) + '" data-env="' + env + '">' +
        '<td><span class="state-dot ' + stateClass(c.state) + '"></span></td>' +
        '<td class="mono">' + c.id + '</td>' +
        '<td class="mono"><span class="expand-icon">▶</span> ' + (c.name || '') + '</td>' +
        '<td>' + progBar(c.progress || 0) + '</td>' +
        '<td class="mono">' + (c.priority || '') + '</td>' +
        '<td class="mono">' + fmtDate(c.created) + '</td>' +
        '<td class="mono">' + fmtDate(c.submitted) + '</td>' +
        '</tr>' +
        '<tr class="child-expand-row" id="child-expand-' + c.id + '" style="display:none">' +
        '<td colspan="7"><div class="expand-lv4" id="child-expand-cnt-' + c.id + '"><span class="expand-loading">Chargement…</span></div></td>' +
        '</tr>'
      );
    }).join('');
    return (
      '<table class="expand-table">' +
      '<thead><tr><th>State</th><th>Id</th><th>Name</th><th>Progress</th><th>Priority</th><th>Created</th><th>Submitted</th></tr></thead>' +
      '<tbody>' + rows + '</tbody>' +
      '</table>'
    );
  }

  function buildGroupsTable(groups, jobId) {
    if (!groups || !groups.length) return '';
    groups = groups.slice().sort(function (a, b) { return a.id - b.id; });
    var parentEnv = ((window._monJobMap[jobId] || {}).environment || '');
    var rows = groups.map(function (g) {
      var expandId = 'grp-expand-' + jobId + '-' + g.id;
      var childHtml = buildChildrenTable(g.children, parentEnv);
      var env = (g.environment || parentEnv).replace(/"/g, '&quot;');
      return (
        '<tr class="group-row" data-group-id="' + g.id + '" data-job-id="' + jobId + '" data-env="' + env + '">' +
        '<td><span class="state-dot ' + stateClass(g.status) + '"></span></td>' +
        '<td class="mono">' + g.id + '</td>' +
        '<td class="mono"><span class="expand-icon">▶</span> ' + (g.name || '') + '</td>' +
        '<td>' + progBar(g.progress || 0) + '</td>' +
        '<td class="mono">' + fmtDate(g.updated) + '</td>' +
        '</tr>' +
        (childHtml ?
          '<tr class="group-expand-row" id="' + expandId + '" style="display:none">' +
          '<td colspan="5"><div class="expand-lv3">' + childHtml + '</div></td>' +
          '</tr>' :
          '')
      );
    }).join('');
    return (
      '<table class="expand-table">' +
      '<thead><tr><th>State</th><th>Id</th><th>Name</th><th>Progress</th><th>Last update</th></tr></thead>' +
      '<tbody>' + rows + '</tbody>' +
      '</table>'
    );
  }

  function buildJobRow(job) {
    return (
      '<tr class="job-row" data-job-id="' + job.id + '" data-has-children="' + (job.hasChildrens ? 1 : 0) + '" data-account="' + (job.userName || '').toLowerCase() + '" data-state="' + stateClass(job.state) + '" data-priority="' + (job.priority || '').toLowerCase() + '" data-name="' + (job.name || '').toLowerCase().replace(/"/g, '&quot;') + '" data-env="' + (job.environment || '').replace(/"/g, '&quot;') + '">' +
      '<td><span class="state-dot ' + stateClass(job.state) + '"></span></td>' +
      '<td class="mono">' + job.id + '</td>' +
      '<td class="mono"><span class="expand-icon">▶</span> ' + (job.name || '') + '</td>' +
      '<td>' + progBar(job.progress || 0) + '</td>' +
      '<td class="mono">' + (job.gridCost || '') + '</td>' +
      '<td class="mono">' + (job.priority || '') + '</td>' +
      '<td class="mono">' + (job.userName || '') + '</td>' +
      '<td class="mono">' + fmtDate(job.createTime) + '</td>' +
      '<td class="mono">' + fmtDate(job.submitTime) + '</td>' +
      '<td class="mono">' + fmtDate(job.changeTime) + '</td>' +
      '</tr>' +
      '<tr class="job-expand-row" id="job-expand-' + job.id + '" style="display:none">' +
      '<td colspan="10"><div class="expand-lv2" id="job-expand-cnt-' + job.id + '"><span class="expand-loading">Chargement…</span></div></td>' +
      '</tr>'
    );
  }

  // ── Expand state persistence ─────────────────

  var _isRestoring = false;

  function _saveExpandState() {
    if (_isRestoring) return;
    var state = { jobId: null, groups: [], children: [] };
    var $expJob = $('#monitorBody .job-row.is-expanded');
    if ($expJob.length) {
      state.jobId = +$expJob.data('job-id');
      $('#monitorBody .group-row.is-expanded').each(function () {
        state.groups.push(+$(this).data('group-id'));
      });
      $('#monitorBody .child-row.is-expanded').each(function () {
        state.children.push(+$(this).data('child-id'));
      });
    }
    STX.merge('monitoring', { expand: state });
  }

  function _restoreExpandState() {
    var expand = (STX.get('monitoring') || {}).expand;
    if (!expand || !expand.jobId) return;
    var $jobRow = $('#monitorBody .job-row[data-job-id="' + expand.jobId + '"]');
    if (!$jobRow.length || !$jobRow.is(':visible')) return;

    _isRestoring = true;
    $jobRow.trigger('click');

    var groups   = expand.groups   || [];
    var children = expand.children || [];

    setTimeout(function () {
      groups.forEach(function (gid) {
        var $r = $('#monitorBody .group-row[data-group-id="' + gid + '"]');
        if ($r.length) $r.trigger('click');
      });
      if (!children.length) { _isRestoring = false; return; }
      setTimeout(function () {
        children.forEach(function (cid) {
          var $r = $('#monitorBody .child-row[data-child-id="' + cid + '"]');
          if ($r.length) $r.trigger('click');
        });
        _isRestoring = false;
      }, 500);
      if (!groups.length) _isRestoring = false;
    }, 500);
  }

  // ── Load & Filters ───────────────────────────

  window.loadMonitoringJobs = function () {
    var $body = $('#monitorBody');
    $body.html('<tr><td colspan="10" style="text-align:center;padding:20px;color:var(--text-faint);font-family:\'DM Mono\';font-size:.65rem">Chargement…</td></tr>');
    apiGetJobs().then(function (resp) {
      if (!resp.jobs || !resp.jobs.length) {
        $body.html('<tr><td colspan="10" style="text-align:center;padding:20px;color:var(--text-faint);font-family:\'DM Mono\';font-size:.65rem">Aucun job.</td></tr>');
        return;
      }
      window._monJobMap = {};
      resp.jobs.forEach(function (j) { window._monJobMap[j.id] = j; });
      resp.jobs.sort(function (a, b) { return b.id - a.id; });
      $body.html(resp.jobs.map(buildJobRow).join(''));
      applyMonitorFilters();
      _restoreExpandState();
    });
  };

  window.applyMonitorFilters = function () {
    var id       = $('.mf-id').val().toLowerCase();
    var name     = $('.mf-name').val().toLowerCase();
    var prio     = $('.mf-priority').val().toLowerCase();
    var acc      = $('.mf-account').val().toLowerCase();
    var fullView = $('.mf-fullview').is(':checked');
    var connectedUser = $('.user-name').text().trim();
    var activeStates = [];
    $('.mf-state-btn.active').each(function () { activeStates.push($(this).data('state')); });

    $('#monitorBody .job-row').each(function () {
      var $tr       = $(this);
      var jid       = String($tr.data('job-id'));
      var nameText  = ($tr.attr('data-name') || '').toLowerCase();
      var accountText = ($tr.data('account') || '').toLowerCase();
      var prioText  = ($tr.attr('data-priority') || '').toLowerCase();
      var rowState  = $tr.attr('data-state') || '';
      var show = (fullView || accountText.indexOf(connectedUser.toLowerCase()) !== -1) &&
        (!id   || jid.indexOf(id) !== -1) &&
        (!name || nameText.indexOf(name) !== -1) &&
        (!prio || prioText.indexOf(prio) !== -1) &&
        (!acc  || accountText.indexOf(acc) !== -1) &&
        (!activeStates.length || activeStates.indexOf(rowState) !== -1);
      $tr.toggle(show);
      $('#job-expand-' + $tr.data('job-id')).toggle(show && $tr.hasClass('is-expanded'));
    });

    if (!STX.get('monitoring.meta')) {
      STX.set('monitoring.meta', { savedAt: Date.now() });
    }
    STX.merge('monitoring', { filters: { id: id, name: name, priority: prio, account: acc } });
  };

  var MS_48H = 48 * 60 * 60 * 1000;

  $(function () {
    // Clear monitoring storage si plus vieux que 48h
    var meta = STX.get('monitoring.meta') || {};
    if (!meta.savedAt || (Date.now() - meta.savedAt) > MS_48H) {
      STX.del('monitoring');
      STX.del('monitoring.meta');
    }

    $(document).on('change', '.mf-refresh', function () {
      setMonitorRefreshInterval(+$(this).val());
    });

    $(document).on('input', '.mf-id, .mf-name, .mf-priority, .mf-account', applyMonitorFilters);
    $(document).on('change', '.mf-fullview', applyMonitorFilters);
    $(document).on('click', '.mf-state-btn', function () {
      $(this).toggleClass('active');
      applyMonitorFilters();
    });

    // Expand/collapse job row
    $(document).on('click', '#monitorBody .job-row', function (e) {
      e.stopPropagation();
      _hideCtxMenu();
      var $tr = $(this);
      var jobId = $tr.data('job-id');
      var hasChildren = +$tr.data('has-children') === 1;
      var $expandRow = $('#job-expand-' + jobId);
      var $cnt = $('#job-expand-cnt-' + jobId);
      var isExpanded = $tr.hasClass('is-expanded');

      if (isExpanded) {
        $tr.removeClass('is-expanded');
        $tr.find('> td .expand-icon').text('▶');
        $expandRow.hide();
        _saveExpandState();
        return;
      }

      $('#monitorBody .job-row.is-expanded').each(function () {
        var $other = $(this);
        $other.removeClass('is-expanded');
        $other.find('> td .expand-icon').text('▶');
        $('#job-expand-' + $other.data('job-id')).hide();
      });

      $tr.addClass('is-expanded');
      $tr.find('> td .expand-icon').text('▼');
      $expandRow.show();
      _saveExpandState();

      if (!$cnt.data('loaded')) {
        $cnt.data('loaded', true);
        if (hasChildren) {
          apiGetJobChildren(jobId).then(function (resp) {
            $cnt.html(
              buildGroupsTable(resp.jobGroups, jobId) ||
              '<div class="expand-empty">Aucun groupe disponible</div>'
            );
          }).fail(function () {
            $cnt.html('<div class="expand-empty">Erreur de chargement</div>');
          });
        } else {
          apiGetJobTasks(jobId).then(function (resp) {
            var env = (window._monJobMap[jobId] || {}).environment || '';
            $cnt.html(buildTasksTable(resp.tasks, env) || '<div class="expand-empty">Aucune tâche disponible</div>');
          }).fail(function () {
            $cnt.html('<div class="expand-empty">Erreur de chargement</div>');
          });
        }
      }
    });

    // Expand/collapse group row
    $(document).on('click', '#monitorBody .group-row', function (e) {
      e.stopPropagation();
      var $tr = $(this);
      var groupId = $tr.data('group-id');
      var jobId = $tr.data('job-id');
      var $expRow = $('#grp-expand-' + jobId + '-' + groupId);
      var expanded = $tr.hasClass('is-expanded');
      $tr.toggleClass('is-expanded', !expanded);
      $tr.find('.expand-icon').text(expanded ? '▶' : '▼');
      $expRow.toggle(!expanded);
      _saveExpandState();
    });

    // Expand/collapse child row → load tasks
    $(document).on('click', '#monitorBody .child-row', function (e) {
      e.stopPropagation();
      var $tr = $(this);
      var childId = $tr.data('child-id');
      var $expRow = $('#child-expand-' + childId);
      var $cnt = $('#child-expand-cnt-' + childId);
      var expanded = $tr.hasClass('is-expanded');
      $tr.toggleClass('is-expanded', !expanded);
      $tr.find('.expand-icon').text(expanded ? '▶' : '▼');
      $expRow.toggle(!expanded);
      _saveExpandState();
      if (!expanded && !$cnt.data('loaded')) {
        $cnt.data('loaded', true);
        apiGetJobTasks(childId).then(function (resp) {
          var env = (window._monChildMap[childId] || {}).environment || '';
          $cnt.html(buildTasksTable(resp.tasks, env) || '<div class="expand-empty">Aucune tâche disponible</div>');
        }).fail(function () {
          $cnt.html('<div class="expand-empty">Erreur de chargement</div>');
        });
      }
    });

    // Task output viewer
    $(document).on('click', '.btn-output-view', function (e) {
      e.stopPropagation();
      var output = _outputCache[+$(this).data('oidx')] || '';
      $('#taskOutputPre').text(output);
      openModal('mTaskOutput');
    });

  });

}(jQuery, window.STX, window.API));
