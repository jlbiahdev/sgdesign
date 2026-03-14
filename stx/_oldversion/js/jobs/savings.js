(function ($, JobRegistry, API, STX) {

  function _build(id) {
    return buildOmenForm(id, {
      label: 'Savings',
      code: 'S',
      extraRows:
        '<div class="fg-lbl">Iteration Range / Period:</div>' +
        '<div class="fg-ctrl">' +
        periodLine('Deterministic', 'chk-det') +
        periodLine('Stochastic', 'chk-sto') +
        '</div>' +
        '<div class="fg-lbl">Guaranteed Floor:</div>' +
        '<div class="fg-ctrl"><input type="checkbox" name="guaranteedFloor"></div>' +
        '<div class="fg-lbl">Pricer derivatives:</div>' +
        '<div class="fg-ctrl">' + periodLine('', 'chk-pricer') + '</div>' +
        '<div class="fg-lbl">Job Omen Type:</div>' +
        '<div class="fg-ctrl"><select name="omenType"></select></div>' +
        '<div class="fg-lbl nb">Scenarios:</div>' +
        '<div class="fg-ctrl nb">' + scenariosBlock() + '</div>',
    });
  }

  function _validate($v, name) {
    var errs = validateOmenBase($v, name);
    var detOk = $v.find('[name="detEnabled"]').is(':checked');
    var stoOk = $v.find('[name="stoEnabled"]').is(':checked');
    if (!detOk && !stoOk)
      errs.push(name + ' : Iteration is mandatory, please select an iteration range');
    var hasScen = $v.find('.scen-table tbody input[type="checkbox"]:checked').length > 0;
    if (!hasScen)
      errs.push(name + ' : you have to select at least one scenario');
    return errs;
  }

  function _init($view) {
    var cached = STX.get('initCache.savings');
    var ready = (cached && (Date.now() - cached.ts) < 86400000)
      ? $.Deferred().resolve(cached.data).promise()
      : API.get('/api/JobManager/savings/init').then(function (init) {
          STX.set('initCache.savings', { data: init, ts: Date.now() });
          return init;
        });
    ready.then(function (init) {
      if (init.defaultName) $view.find('[name="jobName"]').val(init.defaultName);
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
      $view.find('[name="guaranteedFloor"]').prop('checked', !!init.defaultIsGuaranteedFloorChecked);
      applyPeriodLineDefaults($view, 'det',    init.detChecked,               init.defaultDetPeriodSim,    init.defaultDetIterations);
      applyPeriodLineDefaults($view, 'sto',    init.stoChecked,               init.defaultStoPeriodSim,    init.defaultStoIterations);
      applyPeriodLineDefaults($view, 'pricer', init.defaultIsTrdPricerEnabled, init.defaultPricerPeriodSim, init.defaultPricerIterations);
      saveJobView($view);
    });
  }

  function _buildAdv() {
    return (
      advSlidingRow() +
      '<div class="adv-row">' +
      '<button class="btn-toggle" data-grp="launchInputTaskOnly">Launch Input Task Only</button>' +
      '<button class="btn-toggle" data-grp="removeInputGeneration">Remove input generation</button>' +
      '</div>' +
      '<div class="adv-field">' +
      '<label class="adv-lbl">Number Of Iterations for Life SCRs</label>' +
      '<input type="number" name="iterationsLifeSCR" style="width:100px">' +
      '</div>' +
      advCommon()
    );
  }

  JobRegistry.register({
    type:     'savings',
    label:    'Omen Savings',
    tabIcon:  'omen',
    build:    _build,
    validate: _validate,
    init:     _init,
    buildAdv: _buildAdv,
    help: {
      synopsis: 'Run OMEN de type Épargne — déterministe, stochastique et pricer.',
      fields: [
        ['Environnement',        'Chemin réseau UNC vers le dossier use case OMEN (ex. \\\\srv\\MOTEUR\\recette\\usecases\\Cas01). Le bouton Browse s\'active dès qu\'un chemin est renseigné.'],
        ['Inputs',               'Choisissez le jeu de données d\'entrée dans la liste. Les inputs disponibles sont chargés depuis le sous-dossier input/ de l\'environnement.'],
        ['Version Omen',         'Sélectionnez la version du moteur OMEN à utiliser. Passez en mode Custom pour saisir un chemin de version spécifique.'],
        ['Périodes & itérations','Définissez les périodes (en mois) et le nombre d\'itérations pour les modes Deterministic, Stochastic et Pricer. Cochez la case pour activer chaque mode.'],
        ['Guaranteed Floor',     'Activez cette option pour forcer un plancher garanti sur les résultats.'],
        ['Job Omen Type',        'Sélectionnez le type de run OMEN (ex. Full, Sensitivity…).'],
        ['Advanced Options',     'Sliding, Test Sliding, Launch Input Task Only, Remove Input Generation, itérations SCR Life, priorité HPC, type de tâche (alm / Standard / SCR), exécution différée.'],
      ],
    },
  });

}(jQuery, window.JobRegistry, window.API, window.STX));
