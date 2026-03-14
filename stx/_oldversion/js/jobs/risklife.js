(function ($, JobRegistry, API, STX) {

  function _build(id) {
    return buildOmenForm(id, {
      label: 'Risk Life',
      code: 'RL',
      extraRows:
        '<div class="fg-lbl">Iterations:</div>' +
        '<div class="fg-ctrl">' +
        '<div class="f-row" style="align-items:center;gap:8px">' +
        '<input type="text" name="iterations" style="width:70px" placeholder="1-1">' +
        '<label style="display:flex;align-items:center;gap:6px;font-family:\'DM Mono\';font-size:.65rem;color:var(--text-dim);cursor:pointer">' +
        '<input type="checkbox" name="autoIterations"> Auto' +
        '</label>' +
        '</div>' +
        '</div>' +
        '<div class="fg-lbl">Period:</div>' +
        '<div class="fg-ctrl">' +
        '<div class="f-row" style="align-items:center;gap:8px">' +
        '<input type="number" name="period" style="width:80px" min="1">' +
        '<span class="months-lbl">Month(s)</span>' +
        '</div>' +
        '</div>' +
        '<div class="fg-lbl">Job Omen Type:</div>' +
        '<div class="fg-ctrl"><select name="omenType"></select></div>' +
        '<div class="fg-lbl nb">Scenarios:</div>' +
        '<div class="fg-ctrl nb">' + rlScenarioBlock() + '</div>',
    });
  }

  function _validate($v, name) {
    var errs = validateOmenBase($v, name);
    var isAuto = $v.find('[name="autoIterations"]').is(':checked');
    if (!isAuto) {
      var iter = ($v.find('[name="iterations"]').val() || '').trim();
      if (!iter) errs.push(name + ' : Iterations is required (e.g. 1-1)');
    }
    var period = parseInt($v.find('[name="period"]').val(), 10);
    if (!period || period <= 0)
      errs.push(name + ' : Period must be a positive number of months');
    var hasScen = $v.find('.scen-table tbody input[type="checkbox"]:checked').length > 0;
    if (!hasScen)
      errs.push(name + ' : you have to select at least one scenario');
    return errs;
  }

  function _init($view) {
    var cached = STX.get('initCache.risklife');
    var ready = (cached && (Date.now() - cached.ts) < 86400000)
      ? $.Deferred().resolve(cached.data).promise()
      : API.get('/api/JobManager/risklife/init').then(function (init) {
          STX.set('initCache.risklife', { data: init, ts: Date.now() });
          return init;
        });
    ready.then(function (init) {
      if (init.defaultName) $view.find('[name="jobName"]').val(init.defaultName);
      if (init.defaultIterations) $view.find('[name="iterations"]').val(init.defaultIterations);
      if (init.defaultPeriod != null) $view.find('[name="period"]').val(init.defaultPeriod);
      var autoOn = !!init.defaultAutoIterations;
      $view.find('[name="autoIterations"]').prop('checked', autoOn);
      $view.find('[name="iterations"]').prop('disabled', autoOn);
      if (init.models && init.models.length) {
        var $modelSel = $view.find('.ref-content [name="model"]');
        $modelSel.empty();
        init.models.forEach(function (m) { $modelSel.append('<option>' + m.model + '</option>'); });
        fillVersionSelect($view, init.models[0].versions);
      }
      if (init.jobOmenTypes && init.jobOmenTypes.length) {
        var $omenSel = $view.find('[name="omenType"]');
        $omenSel.empty();
        init.jobOmenTypes.forEach(function (t) { $omenSel.append('<option>' + t + '</option>'); });
        if (init.defaultJobType) $omenSel.val(init.defaultJobType);
      }
      saveJobView($view);
    });
  }

  function _buildAdv() {
    return (
      advSlidingRow() +
      '<div class="adv-field">' +
      '<label class="adv-lbl">Job priority</label>' +
      '<select name="priority"><option>Automatic</option><option selected>Normal</option><option>High</option></select>' +
      '</div>'
    );
  }

  JobRegistry.register({
    type:     'risklife',
    label:    'Omen Risk Life',
    tabIcon:  'omen',
    build:    _build,
    validate: _validate,
    init:     _init,
    buildAdv: _buildAdv,
    help: {
      synopsis: 'Run OMEN Risk Life avec projection stochastique sur scénarios.',
      fields: [
        ['Environnement',    'Chemin réseau UNC vers le dossier use case Risk Life.'],
        ['Inputs',           'Jeu de données d\'entrée chargé depuis input/.'],
        ['Version Omen',     'Version du moteur OMEN à utiliser.'],
        ['Durée de projection', 'Nombre de mois de projection.'],
        ['Itérations',       'Nombre d\'itérations stochastiques. Cochez Auto pour le calcul automatique.'],
        ['Scénarios',        'Sélectionnez un ou plusieurs scénarios à lancer. Au moins un scénario est requis.'],
        ['Advanced Options', 'Sliding, Test Sliding, priorité du job (Automatic / Normal / High).'],
      ],
    },
  });

}(jQuery, window.JobRegistry, window.API, window.STX));
