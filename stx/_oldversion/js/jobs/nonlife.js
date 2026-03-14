(function ($, JobRegistry, API, STX) {

  function _build(id) {
    return buildOmenForm(id, {
      label: 'Non Life',
      code: 'N',
      extraRows:
        '<div class="fg-lbl">Period:</div>' +
        '<div class="fg-ctrl">' +
        '<div class="f-row" style="align-items:center;gap:8px">' +
        '<input type="number" name="period" style="width:80px" min="1" max="200">' +
        '<span class="months-lbl">Year(s)</span>' +
        '</div>' +
        '</div>',
    });
  }

  function _validate($v, name) {
    var errs = validateOmenBase($v, name);
    var period = parseInt($v.find('[name="period"]').val(), 10);
    if (!period || period <= 0)
      errs.push(name + ' : Period must be a positive number of years');
    return errs;
  }

  function _init($view) {
    var cached = STX.get('initCache.nonlife');
    var ready = (cached && (Date.now() - cached.ts) < 86400000)
      ? $.Deferred().resolve(cached.data).promise()
      : API.get('/api/JobManager/nonlife/init').then(function (init) {
          STX.set('initCache.nonlife', { data: init, ts: Date.now() });
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
    type:     'nonlife',
    label:    'Omen Non Life',
    tabIcon:  'omen',
    build:    _build,
    validate: _validate,
    init:     _init,
    buildAdv: null,
    help: {
      synopsis: 'Run OMEN pour les produits Non Life — dommages et prévoyance.',
      fields: [
        ['Environnement',        'Chemin réseau UNC vers le dossier use case Non Life. Browse disponible dès qu\'un chemin est saisi.'],
        ['Inputs',               'Sélectionnez le jeu de données d\'entrée depuis le sous-dossier input/.'],
        ['Version Omen',         'Version du moteur OMEN pour ce run Non Life.'],
        ['Périodes & itérations','Définissez la période de simulation (mois) et le nombre d\'itérations pour Deterministic et Stochastic.'],
        ['Job Omen Type',        'Type de run OMEN à exécuter.'],
      ],
    },
  });

}(jQuery, window.JobRegistry, window.API, window.STX));
