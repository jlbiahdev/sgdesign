(function ($, JobRegistry, API, STX) {

  function _build(id) {
    return buildOmenForm(id, {
      label: 'Savings BRD',
      code: 'BRD',
      extraRows:
        '<div class="fg-lbl">Projection Duration:</div>' +
        '<div class="fg-ctrl">' +
        '<div class="f-row" style="align-items:center;gap:8px">' +
        '<input type="number" name="projectionDuration" style="width:80px" min="1">' +
        '<span class="months-lbl">Year(s)</span>' +
        '</div>' +
        '</div>' +
        '<div class="fg-lbl nb">Scenarios:</div>' +
        '<div class="fg-ctrl nb">' + rlScenarioBlock() + '</div>',
    });
  }

  function _validate($v, name) {
    var errs = validateOmenBase($v, name);
    var dur = parseInt($v.find('[name="projectionDuration"]').val(), 10);
    if (!dur || dur <= 0)
      errs.push(name + ' : Projection Duration must be a positive number of years');
    var hasScen = $v.find('.scen-table tbody input[type="checkbox"]:checked').length > 0;
    if (!hasScen)
      errs.push(name + ' : you have to select at least one scenario');
    return errs;
  }

  function _init($view) {
    var cached = STX.get('initCache.brd');
    var ready = (cached && (Date.now() - cached.ts) < 86400000)
      ? $.Deferred().resolve(cached.data).promise()
      : API.get('/api/JobManager/brd/init').then(function (init) {
          STX.set('initCache.brd', { data: init, ts: Date.now() });
          return init;
        });
    ready.then(function (init) {
      if (init.defaultName) $view.find('[name="jobName"]').val(init.defaultName);
      if (init.defaultProjectionDuration != null) $view.find('[name="projectionDuration"]').val(init.defaultProjectionDuration);
      if (init.models && init.models.length) {
        var $modelSel = $view.find('.ref-content [name="model"]');
        $modelSel.empty();
        init.models.forEach(function (m) { $modelSel.append('<option>' + m.model + '</option>'); });
        fillVersionSelect($view, init.models[0].versions);
      }
      saveJobView($view);
    });
  }

  function _buildAdv() {
    return (
      '<div class="adv-field">' +
      '<label class="adv-lbl">Job priority</label>' +
      '<select name="priority"><option>Automatic</option><option selected>Normal</option><option>High</option></select>' +
      '</div>'
    );
  }

  JobRegistry.register({
    type:     'brd',
    label:    'Omen Savings BRD',
    tabIcon:  'omen',
    build:    _build,
    validate: _validate,
    init:     _init,
    buildAdv: _buildAdv,
    help: {
      synopsis: 'Run OMEN Savings avec projection Brut de Rachat et Décès.',
      fields: [
        ['Environnement',        'Chemin réseau UNC vers le dossier use case Savings BRD.'],
        ['Inputs',               'Jeu de données d\'entrée depuis input/.'],
        ['Version Omen',         'Version du moteur OMEN.'],
        ['Durée de projection',  'Nombre d\'années de projection (entier positif).'],
        ['Scénarios',            'Sélectionnez les scénarios à inclure dans le run.'],
        ['Advanced Options',     'Priorité du job (Automatic / Normal / High).'],
      ],
    },
  });

}(jQuery, window.JobRegistry, window.API, window.STX));
