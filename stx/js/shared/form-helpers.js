// ─────────────────────────────────────────────
// FORM HELPERS — shared by all job files and main.js
// ─────────────────────────────────────────────
(function ($, STX, API) {

  // ── Utilities ───────────────────────────────

  window.debounce = function (fn, ms) {
    var t;
    return function () {
      var a = arguments, c = this;
      clearTimeout(t);
      t = setTimeout(function () { fn.apply(c, a); }, ms);
    };
  };

  // Attribue name="f0", "f1"... aux champs sans name (filet de sécurité)
  window.autoNameFields = function ($ctx) {
    var i = 0;
    $ctx.find('input:not([name]):not(.chk-all):not(.scen-table input), select:not([name]), textarea:not([name])').each(function () {
      $(this).attr('name', 'f' + (i++));
    });
  };

  window.PERIOD_MONTHS = { '1y': 12, '5y': 60, '30y': 360, '40y': 480 };

  // ── Serialize / Restore ─────────────────────

  window.serializeView = function ($ctx) {
    var data = {};

    $ctx.find('[name]').not('.scen-table [name]').each(function () {
      data[$(this).attr('name')] = this.type === 'checkbox' ? this.checked : $(this).val();
    });

    var groupInfo = {};
    $ctx.find('.btn-toggle[data-grp]').each(function () {
      var g = $(this).data('grp');
      if (!groupInfo[g]) groupInfo[g] = { count: 0, active: [] };
      var idx = groupInfo[g].count++;
      if ($(this).hasClass('active')) groupInfo[g].active.push(idx);
    });
    $.each(groupInfo, function (g, info) {
      if (info.count === 1) {
        data[g] = info.active.length > 0;
      } else {
        if (!data.__groups) data.__groups = {};
        data.__groups[g] = info.active;
      }
    });

    var $verRef = $ctx.find('.ver-tog.ver-ref');
    if ($verRef.length) {
      var isRef = $verRef.hasClass('active');
      data.refModelSelected = isRef;
      if (isRef) delete data.customVersion;
      else { delete data.model; delete data.version; }
    }

    $ctx.find('.period-line').each(function () {
      var name = $(this).find('[name$="Enabled"]').attr('name');
      if (!name) return;
      var prefix = name.replace('Enabled', '');
      data[prefix + 'Period'] = $(this).find('.period-btn.active').data('period') || '';
    });

    var $scenBody = $ctx.find('.scen-table tbody');
    if ($scenBody.length) {
      data.scenarios = [];
      $scenBody.find('tr').each(function () {
        if ($(this).find('input[type=checkbox]').prop('checked')) {
          data.scenarios.push($(this).find('td').eq(1).text().trim());
        }
      });
    }

    return data;
  };

  window.restoreView = function ($ctx, data) {
    if (!data) return;

    $ctx.find('[name]').not('.scen-table [name]').each(function () {
      var n = $(this).attr('name');
      if (!(n in data)) return;
      if (this.type === 'checkbox') $(this).prop('checked', !!data[n]);
      else $(this).val(data[n]);
    });

    if (data.__groups) {
      $.each(data.__groups, function (g, idxs) {
        var $btns = $ctx.find('.btn-toggle[data-grp="' + g + '"]');
        $btns.each(function (i) { $(this).toggleClass('active', idxs.indexOf(i) !== -1); });
      });
    }

    $ctx.find('.btn-toggle[data-grp]').each(function () {
      var g = $(this).data('grp');
      if ($ctx.find('.btn-toggle[data-grp="' + g + '"]').length === 1 && g in data) {
        $(this).toggleClass('active', !!data[g]);
      }
    });

    $ctx.find('.period-line').each(function () {
      var name = $(this).find('[name$="Enabled"]').attr('name');
      if (!name) return;
      var prefix = name.replace('Enabled', '');
      var key = prefix + 'Period';
      if (!(key in data)) return;
      $(this).find('.period-btn').removeClass('active');
      $(this).find('.period-btn[data-period="' + data[key] + '"]').addClass('active');
    });

    if (data.scenarios) {
      $ctx.find('.scen-table tbody tr').each(function () {
        var num = $(this).find('td').eq(1).text().trim();
        $(this).find('input[type=checkbox]').prop('checked', data.scenarios.indexOf(num) !== -1);
      });
    }
  };

  // ── Validation base ─────────────────────────

  window.validateOmenBase = function ($v, name) {
    var errs = [];

    var env = ($v.find('[name="environment"]').val() || '').trim();
    if (!env) errs.push(name + ' : you have to select at least one environment');

    var input = ($v.find('[name="inputs"]').val() || '').trim();
    if (!input) {
      errs.push(name + ' : you have to select at least one environment\'s Input');
    } else if (input.indexOf(' ') !== -1) {
      errs.push(name + ' : the input name must not contain a space');
    }

    var isRef = $v.find('.ver-ref').hasClass('active');
    var isCustom = $v.find('.ver-cus').hasClass('active');
    if (!isRef && !isCustom) {
      errs.push(name + ' : you have to choose a version');
    } else if (isRef && !($v.find('[name="version"]').val() || '').trim()) {
      errs.push(name + ' : you have to select a version');
    } else if (isCustom && !($v.find('[name="customVersion"]').val() || '').trim()) {
      errs.push(name + ' : you have to select a version');
    }

    return errs;
  };

  // ── Form builders ────────────────────────────

  window.periodLine = function (label, cls) {
    var p = cls.replace('chk-', '');
    return (
      '<div class="period-line">' +
      '<label>' +
      '<input type="checkbox" class="chk-period ' + cls + '" name="' + p + 'Enabled">' +
      (label ? ' ' + label : '') +
      '</label>' +
      '<div class="period-group disabled f-row">' +
      '<input type="text" class="range-inp" name="' + p + 'Range">' +
      '<button class="btn-toggle period-btn" data-period="1y">1 years</button>' +
      '<button class="btn-toggle period-btn" data-period="5y">5 years</button>' +
      '<button class="btn-toggle period-btn" data-period="30y">30 years</button>' +
      '<button class="btn-toggle period-btn" data-period="40y">40 years</button>' +
      '<button class="btn-toggle period-btn" data-period="custom">Custom</button>' +
      '<input type="number" class="months-inp" disabled name="' + p + 'Months">' +
      '<span class="months-lbl">month(s)</span>' +
      '</div>' +
      '</div>'
    );
  };

  window.scenariosBlock = function () {
    return (
      '<div class="f-row" style="margin-bottom:6px">' +
      '<label style="display:flex;align-items:center;gap:6px;font-family:\'DM Mono\';font-size:.65rem;color:var(--text-dim);cursor:pointer">' +
      '<input type="checkbox" class="chk-all"> All' +
      '</label>' +
      '</div>' +
      '<div class="scenarios-wrap">' +
      '<table class="scen-table">' +
      '<thead><tr><th>Select</th><th>Num</th><th>Name</th><th>File RN</th><th>File Det</th><th>File Sto</th></tr></thead>' +
      '<tbody></tbody>' +
      '</table>' +
      '</div>'
    );
  };

  window.rlScenarioBlock = function () {
    return (
      '<div class="f-row" style="margin-bottom:6px">' +
      '<label style="display:flex;align-items:center;gap:6px;font-family:\'DM Mono\';font-size:.65rem;color:var(--text-dim);cursor:pointer">' +
      '<input type="checkbox" class="chk-all"> All' +
      '</label>' +
      '</div>' +
      '<div class="scenarios-wrap">' +
      '<table class="scen-table">' +
      '<thead><tr><th>Select</th><th>Num</th><th>Name</th></tr></thead>' +
      '<tbody></tbody>' +
      '</table>' +
      '</div>'
    );
  };

  window.advCommon = function () {
    return (
      '<div class="adv-field">' +
      '<label class="adv-lbl">Job priority</label>' +
      '<select name="priority"><option>Automatic</option><option>Normal</option><option>High</option></select>' +
      '</div>' +
      '<div class="adv-field">' +
      '<label class="adv-lbl">Task type</label>' +
      '<select name="taskType"><option>alm</option><option>Standard</option><option>SCR</option></select>' +
      '</div>' +
      '<div class="adv-row">' +
      '<button class="btn-toggle" data-grp="doNotMakeAverage">Do not make the average</button>' +
      '</div>' +
      '<div class="adv-field">' +
      '<label class="adv-lbl">Delayed Execution</label>' +
      '<input type="date" name="delayedExec">' +
      '</div>'
    );
  };

  window.advSlidingRow = function () {
    return (
      '<div class="adv-row">' +
      '<button class="btn-toggle active" data-grp="sliding">Sliding</button>' +
      '<button class="btn-toggle"        data-grp="testSliding">Test Sliding</button>' +
      '</div>'
    );
  };

  window.buildOmenForm = function (id, cfg) {
    var ph = cfg.label.replace(/ /g, '_');
    return (
      '<div class="job-view" id="view-' + id + '">' +
      '<div class="form-header">' +
      '<div>' +
      '<div class="form-title">New Omen ' + cfg.label + ' Job</div>' +
      '<div class="form-title-sub">Type ' + cfg.code + ' · OMEN 2026.01.00</div>' +
      '</div>' +
      '<div class="form-actions-col">' +
      '<div class="form-actions-row">' +
      '<button class="btn-secondary btn-help-job" type="button" title="How to use">?</button>' +
      '<button class="btn-submit btn-submit-job">Submit</button>' +
      '</div>' +
      '<label class="adv-chk-label"><input type="checkbox" class="adv-chk" name="advOptions"> Advanced Options</label>' +
      '</div>' +
      '</div>' +
      '<div class="form-grid">' +
      '<div class="fg-lbl">Name:</div>' +
      '<div class="fg-ctrl"><input type="text" class="field-name" name="jobName" placeholder="XK_Omen_' + ph + '"></div>' +
      '<div class="fg-lbl">Environment:</div>' +
      '<div class="fg-ctrl">' +
      '<div class="f-row">' +
      '<input type="text" name="environment" style="flex:1;min-width:0" placeholder="\\\\srv\\MOTEUR\\recette\\usecases\\...">' +
      '<button class="btn-secondary btn-browse btn-browse-env" disabled style="opacity:.35;cursor:not-allowed">Browse</button>' +
      '<button class="btn-secondary btn-open-env">Open</button>' +
      '</div>' +
      '</div>' +
      '<div class="fg-lbl">Inputs:</div>' +
      '<div class="fg-ctrl">' +
      '<select name="inputs"><option value="">— Choose an input —</option></select>' +
      '</div>' +
      '<div class="fg-lbl">User Settings:</div>' +
      '<div class="fg-ctrl">' +
      '<div class="f-row">' +
      '<button class="btn-secondary btn-browse">Browse</button>' +
      '<button class="btn-secondary btn-last">Last</button>' +
      '</div>' +
      '</div>' +
      '<div class="fg-lbl">Version Omen:</div>' +
      '<div class="fg-ctrl">' +
      '<div class="f-row" style="margin-bottom:8px">' +
      '<div class="toggle-group">' +
      '<button class="btn-toggle ver-tog ver-ref active">Reference</button>' +
      '<button class="btn-toggle ver-tog ver-cus">Custom</button>' +
      '</div>' +
      '<button class="btn-secondary" data-ver-action="export">Export</button>' +
      '<button class="btn-secondary btn-browse" data-ver-action="browse" disabled style="opacity:.35;cursor:not-allowed">Browse</button>' +
      '<button class="btn-secondary">Model Info</button>' +
      '</div>' +
      '<div class="ref-content">' +
      '<select name="model" style="margin-bottom:6px"></select>' +
      '<select name="version"></select>' +
      '</div>' +
      '<div class="cus-content" style="display:none">' +
      '<input type="text" name="customVersion" placeholder="Chemin vers la version custom...">' +
      '</div>' +
      '</div>' +
      (cfg.extraRows || '') +
      '</div>' +
      '</div>'
    );
  };

  // ── Init helpers ─────────────────────────────

  window.applyPeriodLineDefaults = function ($view, prefix, enabled, months, range) {
    var $chk = $view.find('[name="' + prefix + 'Enabled"]');
    var $group = $chk.closest('.period-line').find('.period-group');
    $chk.prop('checked', !!enabled);
    $group.toggleClass('disabled', !enabled);
    if (months != null) {
      var matched = false;
      $group.find('.period-btn').each(function () {
        var match = PERIOD_MONTHS[$(this).data('period')] === months;
        $(this).toggleClass('active', match);
        if (match) matched = true;
      });
      if (!matched) $group.find('[data-period="custom"]').addClass('active');
      $group.find('.months-inp').val(months).prop('disabled', matched);
    }
    if (range != null) $group.find('.range-inp').val(range);
  };

  window.fillVersionSelect = function ($view, versions) {
    var $v = $view.find('.ref-content [name="version"]');
    $v.empty();
    (versions || []).forEach(function (v) { $v.append('<option>' + v + '</option>'); });
  };

  window.rebuildScenarios = function ($view, scenarios) {
    var $tbody = $view.find('.scen-table tbody');
    $tbody.empty();
    (scenarios || []).forEach(function (sc) {
      $tbody.append(
        '<tr>' +
        '<td><input type="checkbox"></td>' +
        '<td>' + sc.scenarioNum + '</td>' +
        '<td>' + (sc.calVif || '') + '</td>' +
        '<td>' + (sc.filename || '') + '</td>' +
        '<td>' + (sc.filenameDot || '') + '</td>' +
        '<td>' + (sc.filenameSp || '') + '</td>' +
        '</tr>'
      );
    });
    var $boxes = $tbody.find('input[type=checkbox]');
    $view.find('.chk-all').prop('checked', $boxes.length > 0 && $boxes.length === $boxes.filter(':checked').length);
  };

  window.rebuildRLScenarios = function ($view, scenarios) {
    var $tbody = $view.find('.scen-table tbody');
    $tbody.empty();
    (scenarios || []).forEach(function (sc) {
      $tbody.append(
        '<tr>' +
        '<td><input type="checkbox"></td>' +
        '<td>' + sc.scenarioNum + '</td>' +
        '<td>' + (sc.calVif || '') + '</td>' +
        '</tr>'
      );
    });
  };

  // ── Browse / Environment helpers ─────────────

  window.syncBrowseButtons = function ($view) {
    var hasEnv = ($view.find('[name="environment"]').val() || '').trim() !== '';
    $view.find('.btn-browse-env')
      .prop('disabled', !hasEnv)
      .css({ opacity: hasEnv ? '' : '.35', cursor: hasEnv ? '' : 'not-allowed' });
  };

  window.envToApiPath = function (val) {
    var norm = (val || '').replace(/\\/g, '/').replace(/\/+$/, '');
    var root = API.getRoot().replace(/\\/g, '/').replace(/\/+$/, '');
    if (root && norm.toLowerCase().indexOf(root.toLowerCase()) === 0) {
      return norm.slice(root.length).replace(/^\/+/, '');
    }
    return norm.replace(/^\/+|\/+$/g, '');
  };

  function _resetEnvData($view) {
    $view.find('[name="inputs"]').find('option:not(:first)').remove().end().val('');
    $view.find('.scen-table tbody').empty();
  }

  window._loadEnvData = function ($view) {
    var envPath = envToApiPath($view.find('[name="environment"]').val());
    if (!envPath) { _resetEnvData($view); return; }

    API.exploreDir(envPath + '/input').then(function (node) {
      var $sel = $view.find('[name="inputs"]');
      var cur = $sel.val();
      $sel.find('option:not(:first)').remove();
      (node.folders || []).forEach(function (s) { $sel.append('<option>' + s + '</option>'); });
      if (cur) $sel.val(cur);
    });

    if ($view.find('.scen-table').length) {
      var _id2 = $view.attr('id').replace('view-', '');
      var _type2 = (STX.get('job.' + _id2) || {}).type;
      var _isRL = (_type2 === 'risklife' || _type2 === 'risklifekp' || _type2 === 'brd');
      API.exploreDir(envPath + '/scenario').then(function (node) {
        if (!node.scenarios) return;
        if (_isRL) rebuildRLScenarios($view, node.scenarios);
        else       rebuildScenarios($view, node.scenarios);
      });
    }
  };

  // ── Live-save ────────────────────────────────

  window.saveJobView = debounce(function ($view) {
    var stxKey = 'job.' + $view.attr('id').replace('view-', '');
    var cur = STX.get(stxKey) || {};
    var meta = { type: cur.type, id: cur.id, label: cur.label, createdAt: cur.createdAt, adv: cur.adv };
    STX.set(stxKey, $.extend(meta, serializeView($view)));
  }, 400);

}(jQuery, window.STX, window.API));
