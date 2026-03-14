(function ($, JobRegistry, API, STX) {

  function _build(id) {
    return buildOmenForm(id, {
      label: 'TdR',
      code: 'T',
      extraRows:
        '<div class="fg-lbl">Period:</div>' +
        '<div class="fg-ctrl">' +
        '<div class="f-row" style="align-items:center;gap:8px">' +
        '<input type="number" name="period" style="width:80px" min="1">' +
        '<span class="months-lbl">Month(s)</span>' +
        '</div>' +
        '</div>',
    });
  }

  function _validate($v, name) {
    var errs = validateOmenBase($v, name);
    var period = parseInt($v.find('[name="period"]').val(), 10);
    if (!period || period <= 0)
      errs.push(name + ' : Period must be a positive number of months');
    return errs;
  }

  function _init($view) {
    var cached = STX.get('initCache.tdr');
    var ready = (cached && (Date.now() - cached.ts) < 86400000)
      ? $.Deferred().resolve(cached.data).promise()
      : API.get('/api/JobManager/tdr/init').then(function (init) {
          STX.set('initCache.tdr', { data: init, ts: Date.now() });
          return init;
        });
    ready.then(function (init) {
      if (init.defaultName) $view.find('[name="jobName"]').val(init.defaultName);
      if (init.defaultPeriod != null) $view.find('[name="period"]').val(init.defaultPeriod);
      if (init.models && init.models.length) {
        var $modelSel = $view.find('.ref-content [name="model"]');
        $modelSel.empty();
        init.models.forEach(function (m) { $modelSel.append('<option>' + m.model + '</option>'); });
        fillVersionSelect($view, init.models[0].versions);
      }
      saveJobView($view);
    });
  }

  JobRegistry.register({
    type:     'tdr',
    label:    'Omen TdR',
    tabIcon:  'omen',
    build:    _build,
    validate: _validate,
    init:     _init,
    buildAdv: null,
    help: {
      synopsis: 'Run OMEN pour le calcul du Taux de Rendement.',
      fields: [
        ['Environnement', 'Chemin réseau UNC vers le dossier use case TdR.'],
        ['Inputs',        'Jeu de données d\'entrée depuis input/.'],
        ['Version Omen',  'Version du moteur OMEN.'],
        ['Période',       'Durée de simulation en mois.'],
      ],
    },
  });

}(jQuery, window.JobRegistry, window.API, window.STX));
