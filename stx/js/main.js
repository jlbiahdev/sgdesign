// ─────────────────────────────────────────────
// MAIN — bootstrap & event wiring
// ─────────────────────────────────────────────
$(function () {

  // ── Startup: clean stale STX keys ──────────
  (function () {
    var STALE = ['versionRef', 'versionRefSub', 'versionCustom', 'scenAll', 'scen1', 'scen2', 'scen3', 'refVersionSelected'];
    for (var i = localStorage.length - 1; i >= 0; i--) {
      var lsKey = localStorage.key(i);
      if (!lsKey || lsKey.indexOf('styx.job.') !== 0) continue;
      var stxKey = lsKey.replace('styx.', '');
      var entry = STX.get(stxKey);
      if (!entry) continue;
      var dirty = false;
      Object.keys(entry).forEach(function (k) {
        if (/^f\d+$/.test(k) || STALE.indexOf(k) !== -1) { delete entry[k]; dirty = true; }
      });
      if (!entry.createdAt) { entry.createdAt = Date.now(); dirty = true; }
      if (dirty) STX.set(stxKey, entry);
    }
  }());

  // ── Job counter ─────────────────────────────
  var jobIdx = 0;

  // ── Session restore ──────────────────────────
  function restoreSession() {
    var session = STX.get('session') || {};
    var tabs = session.tabs || [];
    if (!tabs.length) return;

    tabs.forEach(function (tab) {
      var type = tab.type;
      var id   = tab.id;

      if (type === 'monitoring') {
        if ($('#view-monitoring').length) return;
        $('#jobArea').append(buildMonitoring());
        $('#emptyState').hide();
        var mf = (STX.get('monitoring') || {}).filters || {};
        if (mf.id)       $('.mf-id').val(mf.id);
        if (mf.name)     $('.mf-name').val(mf.name);
        if (mf.priority) $('.mf-priority').val(mf.priority);
        if (mf.account)  $('.mf-account').val(mf.account);
        addTab('monitoring', 'Monitoring', 'monitoring');
        return;
      }

      var def = JobRegistry.get(type);
      if (!def) return;
      var savedMeta = STX.get('job.' + id);
      if (!savedMeta) return;

      // Ensure jobIdx is above any restored id to prevent collisions
      var m = id.match(/-(\d+)$/);
      if (m) jobIdx = Math.max(jobIdx, parseInt(m[1], 10));

      $('#jobArea').append(def.build(id));
      $('#emptyState').hide();

      var $view = $('#view-' + id);
      autoNameFields($view);
      syncBrowseButtons($view);
      if (typeof def.init === 'function') def.init($view);

      // Restore form data after init (which may be async); delay gives cached init time to run
      var snap = $.extend({}, savedMeta);
      setTimeout(function () {
        if (!$('#view-' + id).length) return;
        restoreView($view, snap);
        syncBrowseButtons($view);
        $view.find('.chk-period').trigger('change');
        // Reload inputs + scenarios for environment-based jobs
        var envPath = envToApiPath($view.find('[name="environment"]').val());
        if (envPath) $view.find('[name="environment"]').trigger('blur');
      }, 350);

      addTab(id, tab.label, type);
    });

    // Activate last active tab (deferred so all tabs are in DOM first)
    var activeId = session.activeTab;
    if (activeId) {
      setTimeout(function () {
        activateTab(activeId);
        if (activeId === 'monitoring') loadMonitoringJobs();
      }, 0);
    } else if (tabs.length) {
      activateTab(tabs[tabs.length - 1].id);
      if (tabs[tabs.length - 1].type === 'monitoring') loadMonitoringJobs();
    }

    $('#emptyState').hide();
  }

  // ── openJob ─────────────────────────────────
  function openJob(type) {
    // Monitoring is singleton
    if (type === 'monitoring') {
      if ($('#view-monitoring').length) { activateTab('monitoring'); return; }
      $('#jobArea').append(buildMonitoring());
      $('#emptyState').hide();
      var mf = (STX.get('monitoring') || {}).filters || {};
      if (mf.id)       $('.mf-id').val(mf.id);
      if (mf.name)     $('.mf-name').val(mf.name);
      if (mf.priority) $('.mf-priority').val(mf.priority);
      if (mf.account)  $('.mf-account').val(mf.account);
      addTab('monitoring', 'Monitoring', 'monitoring');
      activateTab('monitoring');
      loadMonitoringJobs();
      return;
    }

    var def = JobRegistry.get(type);
    if (!def) { console.warn('[openJob] Unknown type:', type); return; }

    jobIdx++;
    var id     = type + '-' + jobIdx;
    var label  = def.label;

    $('#jobArea').append(def.build(id));
    $('#emptyState').hide();

    var $view = $('#view-' + id);
    var meta  = { type: type, id: id, label: label, createdAt: Date.now() };

    autoNameFields($view);
    syncBrowseButtons($view);
    STX.set('job.' + id, meta);

    if (typeof def.init === 'function') def.init($view);

    addTab(id, label, type);
    activateTab(id);
    cLog('Job ouvert : ' + label);
  }

  // ── Nav bindings ─────────────────────────────
  $('#btnCollapse').on('click', function () {
    var c = $('#appLayout').toggleClass('sidebar-collapsed').hasClass('sidebar-collapsed');
    $('#collapseIcon path').attr('d', c ? 'M4 2l4 4-4 4' : 'M8 2L4 6l4 4');
  });

  $('#btnNewUfx').on('click', function () { openJob('ufx'); });
  $('#btnMonitoring').on('click', function () { openJob('monitoring'); });

  $(document).on('click', '.job-type-opt', function () {
    openJob($(this).data('type'));
    $('#omenDropdown, #toolsDropdown').removeClass('open');
  });

  $('#btnOmenJobs').on('click', function (e) {
    e.stopPropagation();
    $('#omenDropdown').toggleClass('open');
  });
  $('#btnTools').on('click', function (e) {
    e.stopPropagation();
    $('#toolsDropdown').toggleClass('open');
  });
  $(document).on('click', function () {
    $('#omenDropdown, #toolsDropdown').removeClass('open');
  });

  // ── Live-save job views ──────────────────────
  $(document).on('input change', '.job-view input, .job-view select', function () {
    saveJobView($(this).closest('.job-view'));
  });
  $(document).on('click', '.job-view .btn-toggle', function () {
    var $v = $(this).closest('.job-view');
    if ($v.length) saveJobView($v);
  });

  // ── ADV toggle single-select per group ───────
  $(document).on('click', '.btn-toggle[data-grp]', function () {
    var g = $(this).data('grp');
    $('[data-grp="' + g + '"]').not(this).removeClass('active');
    $(this).toggleClass('active');
  });

  // ── LAST button ──────────────────────────────
  $(document).on('click', '.btn-last', function () {
    var $view = $(this).closest('.job-view');
    var id = $view.attr('id').replace('view-', '');
    var type = (STX.get('job.' + id) || {}).type;
    if (!type) return;
    var last = STX.get('lastSubmit.' + type);
    if (!last) { openConsole(); cLog('Aucun job ' + type + ' soumis récemment.', 'warn'); return; }

    restoreView($view, last);
    syncBrowseButtons($view);
    $view.find('.chk-period').trigger('change');

    if (last.adv) {
      var cur = STX.get('job.' + id) || {};
      STX.set('job.' + id, $.extend(cur, { adv: last.adv }));
    }

    if ($view.find('.adv-chk').prop('checked')) {
      var def = JobRegistry.get(type);
      var advHtml = def && typeof def.buildAdv === 'function' ? def.buildAdv() : '';
      if (advHtml) {
        openSidePanel('Advanced Options', advHtml);
        if (last.adv) restoreView($('#sidePanelBody'), last.adv);
      }
    }

    $view.find('.ref-content [name="model"]').trigger('change');
    if (last.version) $view.find('.ref-content [name="version"]').val(last.version);

    var envVal = ($view.find('[name="environment"]').val() || '').trim();
    if (envVal) {
      API.get('/api/JobManager/inputs?' + $.param({ source: envVal }))
        .then(function (resp) {
          var $sel = $view.find('[name="inputs"]');
          $sel.find('option:not(:first)').remove();
          (resp.folders || []).forEach(function (s) { $sel.append('<option>' + s + '</option>'); });
          if (last.inputs) $sel.val(last.inputs);
        });
      if ($view.find('.scen-table').length) {
        var _isRLType = (type === 'risklife' || type === 'risklifekp' || type === 'brd');
        var scenParams = { source: envVal, input: last.inputs || '' };
        if (last.omenType) scenParams.jobType = last.omenType;
        API.get('/api/JobManager/' + type + '/models/scenarios?' + $.param(scenParams))
          .then(function (response) {
            var scenarios = (response && response.scenarios) ? response.scenarios : [];
            if (!scenarios.length) return;
            if (_isRLType) rebuildRLScenarios($view, scenarios);
            else           rebuildScenarios($view, scenarios);
            if (last.scenarios && last.scenarios.length) {
              $view.find('.scen-table tbody tr').each(function () {
                var num = $(this).find('td').eq(1).text().trim();
                $(this).find('input[type=checkbox]').prop('checked', last.scenarios.indexOf(num) !== -1);
              });
            }
          });
      }
    }

    saveJobView($view);
    cLog('Valeurs du dernier job ' + type + ' restaurées.');
  });

  // ── Period buttons ───────────────────────────
  $(document).on('click', '.period-btn', function () {
    var $grp = $(this).closest('.period-group');
    var period = $(this).data('period');
    $grp.find('.period-btn').removeClass('active');
    $(this).addClass('active');
    var isCustom = period === 'custom';
    $grp.find('.months-inp').prop('disabled', !isCustom);
    if (!isCustom && PERIOD_MONTHS[period]) $grp.find('.months-inp').val(PERIOD_MONTHS[period]);
  });

  // ── Version toggle ───────────────────────────
  $(document).on('click', '.ver-tog', function () {
    $(this).closest('.toggle-group').find('.ver-tog').removeClass('active');
    $(this).addClass('active');
    var $ctrl = $(this).closest('.fg-ctrl');
    var isRef = $(this).hasClass('ver-ref');
    $ctrl.find('.ref-content').toggle(isRef);
    $ctrl.find('.cus-content').toggle(!isRef);
    var $export = $ctrl.find('[data-ver-action="export"]');
    var $browse = $ctrl.find('[data-ver-action="browse"]');
    $export.prop('disabled', !isRef).css({ opacity: isRef ? '' : '.35', cursor: isRef ? '' : 'not-allowed' });
    $browse.prop('disabled', isRef).css({ opacity: isRef ? '.35' : '', cursor: isRef ? 'not-allowed' : '' });
  });

  // ── Period checkbox ──────────────────────────
  $(document).on('change', '.chk-period', function () {
    var checked = $(this).is(':checked');
    var $grp = $(this).closest('.period-line').find('.period-group');
    $grp.toggleClass('disabled', !checked);
    if (checked) {
      var isCustom = $grp.find('.period-btn.active').data('period') === 'custom';
      $grp.find('.months-inp').prop('disabled', !isCustom);
    } else {
      $grp.find('.months-inp').prop('disabled', true);
    }
  });

  // ── Scenarios "All" checkbox ─────────────────
  $(document).on('change', '.chk-all', function () {
    $(this).closest('.job-view').find('.scen-table input[type=checkbox]').prop('checked', $(this).is(':checked'));
  });
  $(document).on('change', '.scen-table input[type=checkbox]', function () {
    var $view = $(this).closest('.job-view');
    var $rows = $view.find('.scen-table input[type=checkbox]');
    $view.find('.chk-all').prop('checked', $rows.length === $rows.filter(':checked').length);
  });

  // ── Job name → tab label ─────────────────────
  $(document).on('input', '.job-view [name="jobName"]', function () {
    var $view = $(this).closest('.job-view');
    var id = $view.attr('id').replace('view-', '');
    var name = $(this).val().trim();
    $('.sidebar-tab[data-job="' + id + '"] .tab-label')
      .text(name || (STX.get('job.' + id) || {}).label || id);
  });

  // ── Environment field ────────────────────────
  $(document).on('input', '.job-view [name="environment"]', function () {
    syncBrowseButtons($(this).closest('.job-view'));
  });
  $(document).on('change blur', '.job-view [name="environment"]', function () {
    var $view = $(this).closest('.job-view');
    syncBrowseButtons($view);
    _loadEnvData($view);
  });

  $(document).on('change blur', '.job-view [name="inputs"]', function () {
    _loadScenarios($(this).closest('.job-view'));
  });

  // ── Version model change → reload versions ───
  $(document).on('change', '.job-view .ref-content [name="model"]', function () {
    var $view = $(this).closest('.job-view');
    var id = $view.attr('id').replace('view-', '');
    var type = (STX.get('job.' + id) || {}).type;
    var cached = STX.get('initCache.' + type);
    if (!cached) return;
    var modelName = $(this).val();
    var entry = null;
    (cached.data.models || []).forEach(function (m) { if (m.model === modelName) entry = m; });
    if (entry) fillVersionSelect($view, entry.versions);
  });

  // ── autoIterations toggle ────────────────────
  $(document).on('change', '[name="autoIterations"]', function () {
    $(this).closest('.job-view').find('[name="iterations"]').prop('disabled', $(this).is(':checked'));
  });

  // ── RL S2 select/deselect ────────────────────
  $(document).on('click', '.rl-s2-select', function () {
    $(this).closest('.fg-ctrl').find('.scen-table tbody input[type=checkbox]').prop('checked', true);
  });
  $(document).on('click', '.rl-s2-deselect', function () {
    $(this).closest('.fg-ctrl').find('.scen-table tbody input[type=checkbox]').prop('checked', false);
  });

  // ── Submit ───────────────────────────────────
  $(document).on('click', '.btn-submit-job', function () {
    var $v = $(this).closest('.job-view');
    var $name = $v.find('.field-name');
    var name = ($name.val() || '').trim();

    if ($name.length && !name) {
      $name.addClass('is-invalid').focus();
      openConsole();
      cLog('Validation : le champ Name est requis.', 'error');
      return;
    }
    if ($name.length) $name.removeClass('is-invalid');

    var _id       = $v.attr('id').replace('view-', '');
    var _jobData  = STX.get('job.' + _id) || {};
    var _type     = _jobData.type;
    var _displayName = name || JobRegistry.getLabel(_type) || 'job';

    var def = JobRegistry.get(_type);
    if (def && def.validate) {
      var errors = def.validate($v, _displayName);
      if (errors.length) {
        openConsole();
        errors.forEach(function (e) { cLog(e, 'error'); });
        return;
      }
    }

    var _adv = ($('#sidePanel').hasClass('open') && $('#sidePanelTitle').text() === 'Advanced Options') ?
      serializeView($('#sidePanelBody')) : _jobData.adv;
    if (!$v.find('.adv-chk').is(':checked')) _adv = null;

    if (_type) STX.set('lastSubmit.' + _type, $.extend({}, serializeView($v), { adv: _adv }));

    var d = serializeView($v);
    var payload;

    if (_type === 'ufx') {
      payload = { jobName: d.jobName, path: d.path, isFolder: !!d.isFolder };

    } else if (_type === 'custominput') {
      payload = { inputsFolder: d.inputsFolder, actionsFolder: d.actionsFolder };

    } else if (_type === 'scenariotransformator') {
      payload = {
        environment: d.environment,
        modelType:   d.modelType,
        periode:     d.periode,
        iterations:  d.iterations,
        coupons:     d.coupons,
        split:       !!d.split,
      };

    } else {
      var isRef = $v.find('.ver-ref').hasClass('active');
      payload = {
        jobName:          d.jobName,
        environment:      d.environment,
        inputs:           d.inputs,
        refModelSelected: !!isRef,
        model:            d.model,
        version:          isRef ? d.version : d.customVersion,
        advOptions:       _adv,
      };
      if (_type === 'savings') {
        $.extend(payload, {
          detEnabled:      !!d.detEnabled,
          detRange:        d.detRange,
          detPeriod:       d.detPeriod,
          detMonths:       d.detMonths ? parseInt(d.detMonths, 10) : null,
          stoEnabled:      !!d.stoEnabled,
          stoRange:        d.stoRange,
          stoPeriod:       d.stoPeriod,
          stoMonths:       d.stoMonths ? parseInt(d.stoMonths, 10) : null,
          pricerEnabled:   !!d.pricerEnabled,
          pricerRange:     d.pricerRange,
          pricerPeriod:    d.pricerPeriod,
          pricerMonths:    d.pricerMonths ? parseInt(d.pricerMonths, 10) : null,
          guaranteedFloor: !!d.guaranteedFloor,
          omenType:        d.omenType,
          scenarios:       d.scenarios || [],
        });
      } else if (_type === 'nonlife' || _type === 'tdr') {
        payload.period = d.period ? parseInt(d.period, 10) : null;
      } else if (_type === 'risklife' || _type === 'risklifekp') {
        payload.period    = d.period ? parseInt(d.period, 10) : null;
        payload.scenarios = d.scenarios || [];
      } else if (_type === 'brd') {
        payload.projectionDuration = d.projectionDuration ? parseInt(d.projectionDuration, 10) : null;
        payload.scenarios          = d.scenarios || [];
      }
    }

    openConsole();
    cLog('Soumission du job ' + _displayName + '…');
    API.post('/api/JobManager/submit/' + _type, payload)
      .then(function (resp) {
        cLog('Job soumis — parentId: ' + (resp.parentId || '?') + ', ' + (resp.launchedJobCount || 0) + ' job(s) lancé(s).');
      }, function (err) {
        console.error('[STYX] Submit failed', err);
        cLog('Erreur lors de la soumission : ' + (err.message || 'erreur inconnue'), 'error');
      });
  });

  // ── Restore previous session ─────────────────
  restoreSession();

});
