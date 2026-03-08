(function ($, JobRegistry, API, STX) {

  var _radStyle = 'display:flex;align-items:center;gap:6px;font-family:\'DM Mono\';font-size:.65rem;color:var(--text-dim);cursor:pointer;white-space:nowrap';

  function _build(id) {
    return (
      '<div class="job-view" id="view-' + id + '">' +
      '<div class="form-header">' +
      '<div>' +
      '<div class="form-title">Scenario Transformator</div>' +
      '<div class="form-title-sub">Transformation de scénarios</div>' +
      '</div>' +
      '<div class="form-actions-col">' +
      '<div class="form-actions-row">' +
      '<button class="btn-secondary btn-help-job" type="button" title="How to use">?</button>' +
      '<button class="btn-submit btn-submit-job">Transform</button>' +
      '</div>' +
      '</div>' +
      '</div>' +
      '<div class="form-grid">' +
      '<div class="fg-lbl">Environment:</div>' +
      '<div class="fg-ctrl">' +
      '<div class="f-row">' +
      '<input type="text" name="environment" style="flex:1;min-width:0" placeholder="\\\\srv\\styx\\...">' +
      '<button class="btn-secondary btn-browse btn-browse-env" disabled style="opacity:.35;cursor:not-allowed">Browse</button>' +
      '</div>' +
      '</div>' +
      '<div class="fg-lbl">Model Type:</div>' +
      '<div class="fg-ctrl">' +
      '<div class="f-row" style="gap:14px;flex-wrap:wrap" data-radio-group="modelType"></div>' +
      '</div>' +
      '<div class="fg-lbl">Période:</div>' +
      '<div class="fg-ctrl">' +
      '<div class="f-row" style="gap:14px" data-radio-group="periode"></div>' +
      '</div>' +
      '<div class="fg-lbl">Nb itérations:</div>' +
      '<div class="fg-ctrl"><select name="iterations"></select></div>' +
      '<div class="fg-lbl">Coupons:</div>' +
      '<div class="fg-ctrl"><select name="coupons"></select></div>' +
      '<div class="fg-lbl">Split:</div>' +
      '<div class="fg-ctrl">' +
      '<label style="' + _radStyle + '"><input type="checkbox" name="split"> Split</label>' +
      '</div>' +
      '</div>' +
      '</div>'
    );
  }

  function _validate($v, name) {
    var errs = [];
    var env = ($v.find('[name="environment"]').val() || '').trim();
    if (!env) errs.push(name + ' : you must select an environment');
    return errs;
  }

  function _init($view) {
    var cached = STX.get('initCache.scenariotransformator');
    var ready = (cached && (Date.now() - cached.ts) < 86400000)
      ? $.Deferred().resolve(cached.data).promise()
      : API.get('/api/JobManager/scenarioTransfo/init').then(function (init) {
          STX.set('initCache.scenariotransformator', { data: init, ts: Date.now() });
          return init;
        });
    ready.then(function (init) {
      if (init.modelTypes && init.modelTypes.length) {
        var $mt = $view.find('[data-radio-group="modelType"]');
        $mt.empty();
        init.modelTypes.forEach(function (m) {
          var chk = m.value === init.defaultModelType ? ' checked' : '';
          $mt.append('<label style="' + _radStyle + '"><input type="radio" name="modelType" value="' + m.value + '"' + chk + '> ' + m.label + '</label>');
        });
      }
      if (init.periodes && init.periodes.length) {
        var $p = $view.find('[data-radio-group="periode"]');
        $p.empty();
        init.periodes.forEach(function (p) {
          var chk = p.value === init.defaultPeriode ? ' checked' : '';
          $p.append('<label style="' + _radStyle + '"><input type="radio" name="periode" value="' + p.value + '"' + chk + '> ' + p.label + '</label>');
        });
      }
      if (init.iterations && init.iterations.length) {
        var $iter = $view.find('[name="iterations"]');
        $iter.empty();
        init.iterations.forEach(function (v) {
          var sel = v === init.defaultIterations ? ' selected' : '';
          $iter.append('<option value="' + v + '"' + sel + '>' + v + '</option>');
        });
      }
      if (init.coupons && init.coupons.length) {
        var $coup = $view.find('[name="coupons"]');
        $coup.empty();
        init.coupons.forEach(function (c) {
          var sel = c === init.defaultCoupon ? ' selected' : '';
          $coup.append('<option value="' + c + '"' + sel + '>' + c + '</option>');
        });
      }
      saveJobView($view);
    });
  }

  JobRegistry.register({
    type:     'scenariotransformator',
    label:    'Scenario Transformator',
    tabIcon:  'tool',
    build:    _build,
    validate: _validate,
    init:     _init,
    buildAdv: null,
    help: {
      synopsis: 'Transforme des scénarios économiques vers le format d\'un modèle cible.',
      fields: [
        ['Environnement', 'Chemin réseau UNC vers le dossier de données à transformer. Le bouton Browse s\'active dès qu\'un chemin est renseigné.'],
        ['Model Type',    'Version de modèle pour la transformation : 2017, 2018, 2020 ou 2020 V2.'],
        ['Période',       'Fréquence de la transformation : Mois (mensuelle) ou Année (annuelle).'],
        ['Nb itérations', 'Nombre d\'itérations de la transformation de scénarios.'],
        ['Coupons',       'Type de coupon à générer : ZC (zéro coupon) ou TC (taux constant).'],
        ['Split',         'Activez cette option pour découper la sortie en fichiers séparés par scénario.'],
      ],
    },
  });

}(jQuery, window.JobRegistry, window.API, window.STX));
