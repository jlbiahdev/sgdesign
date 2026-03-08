// ─────────────────────────────────────────────
// SIDE PANEL
// ─────────────────────────────────────────────
(function ($, STX, API, JobRegistry) {

  window.openSidePanel = function (title, html) {
    $('#sidePanelTitle').text(title);
    $('#sidePanelBody').html(html);
    $('#sidePanel').addClass('open');
  };

  window.closeSidePanel = function () {
    $('#sidePanel').removeClass('open');
    $('#btnAbout, #btnSettings').removeClass('active');
  };

  window.buildHelpContent = function () {
    return (
      '<div class="panel-section">' +
      '<h4>Jobs disponibles</h4>' +
      '<ul>' +
      '<li><strong>Omen Savings</strong> — Projection épargne (DET / STO / Pricer)</li>' +
      '<li><strong>NonLife</strong> — Risques non-vie (mortalité, morbidité, longévité…)</li>' +
      '<li><strong>RiskLife / RiskLifeKP</strong> — Risques vie Solvabilité II</li>' +
      '<li><strong>TdR</strong> — Taux de Rendement</li>' +
      '<li><strong>BRD</strong> — Best Estimate épargne longue durée</li>' +
      '<li><strong>UFX</strong> — Traitement de fichiers Universal Format Exchange</li>' +
      '<li><strong>Custom Input</strong> — Lancement avec un dossier d\'actions personnalisé</li>' +
      '<li><strong>Scénario Transformateur</strong> — Génération de scénarios économiques</li>' +
      '</ul>' +
      '<p style="margin-top:6px;font-size:.6rem;color:var(--text-faint)">Chaque onglet job dispose d\'un bouton <strong>?</strong> pour le guide détaillé.</p>' +
      '</div>' +
      '<div class="panel-section">' +
      '<h4>Navigation</h4>' +
      '<ul>' +
      '<li>Ouvrir un job : menu latéral gauche ou clic sur un type de job</li>' +
      '<li>Passer d\'un job à l\'autre : cliquer sur l\'onglet en haut</li>' +
      '<li>Fermer un job : croix de l\'onglet (l\'état du formulaire est conservé)</li>' +
      '<li>Rouvrir un job fermé : l\'état est restauré depuis le stockage local</li>' +
      '</ul>' +
      '</div>' +
      '<div class="panel-section">' +
      '<h4>Console</h4>' +
      '<ul>' +
      '<li>Affiche les soumissions, erreurs et événements en temps réel</li>' +
      '<li>Ouvrir / fermer : bouton <strong>Console</strong> en bas à gauche</li>' +
      '<li>L\'historique est conservé 48 h dans le stockage local</li>' +
      '<li>Maximum 200 entrées conservées (les plus anciennes sont purgées)</li>' +
      '</ul>' +
      '</div>' +
      '<div class="panel-section">' +
      '<h4>Configuration</h4>' +
      '<ul>' +
      '<li><strong>Thème</strong> Dark / Light : bouton ☽/☀ en haut à droite</li>' +
      '<li><strong>Mode API</strong> Fake : réponses simulées localement (fake_api.json)</li>' +
      '<li><strong>Mode API</strong> Real : requêtes envoyées au backend ASP.NET Core</li>' +
      '<li><strong>Base URL</strong> : adresse du serveur (ex. http://srv:5000)</li>' +
      '<li><strong>Racine réseau</strong> : préfixe UNC du serveur de fichiers (ex. \\\\\\\\srv)</li>' +
      '</ul>' +
      '</div>' +
      '<div class="panel-section">' +
      '<h4>À propos</h4>' +
      '<div class="pref-row"><span class="pref-key">Application</span><span class="pref-val">Styx Job Manager</span></div>' +
      '<div class="pref-row"><span class="pref-key">Version</span>    <span class="pref-val">2026.01.00</span></div>' +
      '<div class="pref-row"><span class="pref-key">Moteur</span>     <span class="pref-val">OMEN · SGA</span></div>' +
      '<div class="pref-row"><span class="pref-key">Équipe</span>     <span class="pref-val">ASSU · MCA</span></div>' +
      '<div class="pref-row"><span class="pref-key">Copyright</span>  <span class="pref-val">© Société Générale Assurances</span></div>' +
      '</div>'
    );
  };

  window.buildMonitoringHelp = function () {
    return (
      '<div class="panel-section">' +
      '<h4>États des jobs</h4>' +
      '<ul>' +
      '<li><span class="state-dot running"   style="display:inline-block;margin-right:6px"></span><strong>Running</strong> — calcul en cours sur la grille HPC</li>' +
      '<li><span class="state-dot pending"   style="display:inline-block;margin-right:6px"></span><strong>Queued</strong> — en attente d\'un slot de calcul</li>' +
      '<li><span class="state-dot done"      style="display:inline-block;margin-right:6px"></span><strong>Finished</strong> — terminé avec succès</li>' +
      '<li><span class="state-dot error"     style="display:inline-block;margin-right:6px"></span><strong>Failed</strong> — erreur pendant l\'exécution</li>' +
      '<li><span class="state-dot cancelled" style="display:inline-block;margin-right:6px"></span><strong>Canceled</strong> — annulé manuellement</li>' +
      '</ul>' +
      '</div>' +
      '<div class="panel-section">' +
      '<h4>Hiérarchie des jobs</h4>' +
      '<ul>' +
      '<li><strong>Parent job</strong> (ligne principale) — créé lors de la soumission depuis Styx ; porte le nom affiché dans la grille</li>' +
      '<li><strong>Job Groups</strong> (phases) — sous-étapes séquentielles du parent (ex. "Generate inputs", "Run det", "Reporting", "Copy &amp; Delete Temp"). Cliquer sur la ligne parent pour les afficher.</li>' +
      '<li><strong>Child jobs</strong> (batch) — instances parallèles d\'une phase ; chacun traite un sous-ensemble de scénarios ou de périodes</li>' +
      '<li><strong>Tasks</strong> — commandes Styx individuelles à l\'intérieur d\'un leaf job</li>' +
      '</ul>' +
      '</div>' +
      '<div class="panel-section">' +
      '<h4>Colonnes</h4>' +
      '<ul>' +
      '<li><strong>State</strong> — pastille colorée indiquant l\'état courant</li>' +
      '<li><strong>Id</strong> — identifiant unique du job dans la grille</li>' +
      '<li><strong>Name</strong> — nom du job (préfixe [Omen], [NL], [RL], [RLKP], [BRD], [TdR], [Ufx]…)</li>' +
      '<li><strong>Progress</strong> — pourcentage d\'avancement estimé (barre + valeur)</li>' +
      '<li><strong>GDC</strong> — Grid Cost : nombre de slots de calcul consommés</li>' +
      '<li><strong>Priority</strong> — Normal · BelowNormal · AboveNormal · High</li>' +
      '<li><strong>Account Name</strong> — utilisateur ayant soumis le job</li>' +
      '<li><strong>Created / Submitted / Last Update</strong> — horodatages du cycle de vie</li>' +
      '</ul>' +
      '</div>' +
      '<div class="panel-section">' +
      '<h4>Filtres</h4>' +
      '<ul>' +
      '<li><strong>Job Id</strong> — filtre par identifiant (partiel)</li>' +
      '<li><strong>Job Name</strong> — filtre par nom (partiel, insensible à la casse)</li>' +
      '<li><strong>Account Name</strong> — filtre par utilisateur</li>' +
      '<li><strong>Priority</strong> — filtre par niveau de priorité</li>' +
      '<li><strong>Full View</strong> — affiche également les jobs Finished et Canceled (masqués par défaut)</li>' +
      '<li><strong>Boutons d\'état</strong> — filtre multi-sélection ; plusieurs états peuvent être actifs simultanément</li>' +
      '</ul>' +
      '</div>' +
      '<div class="panel-section">' +
      '<h4>Menu contextuel (clic droit)</h4>' +
      '<ul>' +
      '<li><strong>Cancel</strong> — annule un job Running ou Queued</li>' +
      '<li><strong>Requeue</strong> — relance un job Failed ou Canceled</li>' +
      '<li><strong>Copier le Job Id</strong> — copie l\'identifiant dans le presse-papier</li>' +
      '</ul>' +
      '</div>'
    );
  };

  window.buildJobHelp = function (type) {
    var def = JobRegistry.get(type);
    if (!def || !def.help) {
      return '<div class="panel-section"><p>Aucune aide disponible pour ce type de job.</p></div>';
    }
    var rows = def.help.fields.map(function (e) {
      return '<li><strong>' + e[0] + '</strong> — ' + e[1] + '</li>';
    }).join('');
    return (
      '<div class="panel-section"><h4>' + def.help.synopsis + '</h4></div>' +
      '<div class="panel-section"><ul>' + rows + '</ul></div>'
    );
  };

  window.buildSettingsContent = function () {
    return (
      '<div class="panel-section">' +
      '<h4>Application</h4>' +
      '<div class="pref-row"><span class="pref-key">Version</span>       <span class="pref-val">2026.01.00</span></div>' +
      '<div class="pref-row"><span class="pref-key">Environnement</span> <span class="pref-val">Recette</span></div>' +
      '<div class="pref-row"><span class="pref-key">Serveur</span>       <span class="pref-val mono" style="font-size:.62rem">\\\\srv\\styx\\recette</span></div>' +
      '</div>' +
      '<div class="panel-section">' +
      '<h4>Préférences utilisateur</h4>' +
      '<div class="pref-row">' +
      '<span class="pref-key">Thème</span>' +
      '<div class="toggle-group">' +
      '<button class="btn-toggle" id="prefDark">Dark</button>' +
      '<button class="btn-toggle" id="prefLight">Light</button>' +
      '</div>' +
      '</div>' +
      '<div class="pref-row">' +
      '<span class="pref-key">Langue</span>' +
      '<select name="langue" style="width:80px"><option>FR</option><option>EN</option></select>' +
      '</div>' +
      '<div class="pref-row">' +
      '<span class="pref-key">Job Priority par défaut</span>' +
      '<select name="priority" style="width:110px"><option>Automatic</option><option>Normal</option><option>High</option></select>' +
      '</div>' +
      '</div>' +
      '<div class="panel-section">' +
      '<h4>Compte</h4>' +
      '<div class="pref-row"><span class="pref-key">Utilisateur</span> <span class="pref-val">John DOE</span></div>' +
      '<div class="pref-row"><span class="pref-key">Rôle</span>        <span class="pref-val">Actuaire</span></div>' +
      '<div class="pref-row"><span class="pref-key">Équipe</span>      <span class="pref-val">ASSU · MCA</span></div>' +
      '</div>' +
      '<div class="panel-section">' +
      '<h4>API</h4>' +
      '<div class="pref-row">' +
      '<span class="pref-key">Mode</span>' +
      '<div class="toggle-group">' +
      '<button class="btn-toggle" id="prefApiFake">Fake</button>' +
      '<button class="btn-toggle" id="prefApiReal">Real</button>' +
      '</div>' +
      '</div>' +
      '<div id="apiRealSettings" style="display:none">' +
      '<div class="pref-row">' +
      '<span class="pref-key">Base URL</span>' +
      '<input type="text" name="apiBaseUrl" style="width:140px;font-size:.6rem" placeholder="http://srv:5000">' +
      '</div>' +
      '<div class="pref-row">' +
      '<span class="pref-key">Racine réseau</span>' +
      '<input type="text" name="apiRoot" style="width:140px;font-size:.6rem" placeholder="\\\\\\\\srv">' +
      '</div>' +
      '</div>' +
      '</div>' +
      '<div class="panel-section">' +
      '<button class="btn-submit" style="width:100%" id="btnSaveSettings">Enregistrer</button>' +
      '</div>'
    );
  };

  $(function () {

    $('#closeSidePanel').on('click', closeSidePanel);

    // Fermer en cliquant en dehors
    $(document).on('click', function (e) {
      if ($('#sidePanel').hasClass('open') &&
        !$(e.target).closest('#sidePanel').length &&
        !$(e.target).closest('#btnAbout').length &&
        !$(e.target).closest('#btnSettings').length &&
        !$(e.target).closest('.adv-chk-label').length &&
        !$(e.target).closest('.btn-help-job').length &&
        !$(e.target).closest('.btn-help-monitoring').length) {
        closeSidePanel();
      }
    });

    // Help Center
    $('#btnAbout').on('click', function () {
      if ($('#sidePanel').hasClass('open') && $('#sidePanelTitle').text() === 'Help Center') {
        closeSidePanel();
      } else {
        $(this).addClass('active');
        openSidePanel('Help Center', buildHelpContent());
      }
    });

    // Aide Monitoring
    $(document).on('click', '.btn-help-monitoring', function () {
      var title = 'Monitoring — Guide';
      if ($('#sidePanel').hasClass('open') && $('#sidePanelTitle').text() === title) {
        closeSidePanel();
      } else {
        openSidePanel(title, buildMonitoringHelp());
      }
    });

    // Aide contextuelle par job
    $(document).on('click', '.btn-help-job', function () {
      var $view = $(this).closest('.job-view');
      var id = $view.attr('id').replace('view-', '');
      var type = (STX.get('job.' + id) || {}).type;
      var label = JobRegistry.getLabel(type) || 'Job';
      var title = label + ' — Guide';
      if ($('#sidePanel').hasClass('open') && $('#sidePanelTitle').text() === title) {
        closeSidePanel();
      } else {
        openSidePanel(title, buildJobHelp(type));
      }
    });

    // Settings
    $('#btnSettings').on('click', function () {
      if ($('#sidePanel').hasClass('open') && $('#sidePanelTitle').text() === 'Général') {
        closeSidePanel();
      } else {
        $(this).addClass('active');
        openSidePanel('Général', buildSettingsContent());
        var saved = STX.get('settings') || {};
        if (saved.langue)     $('#sidePanelBody [name="langue"]').val(saved.langue);
        if (saved.priority)   $('#sidePanelBody [name="priority"]').val(saved.priority);
        if (saved.apiBaseUrl) $('#sidePanelBody [name="apiBaseUrl"]').val(saved.apiBaseUrl);
        if (saved.apiRoot)    $('#sidePanelBody [name="apiRoot"]').val(saved.apiRoot);
        var t = $('html').attr('data-theme');
        $('#prefDark').toggleClass('active', t === 'dark');
        $('#prefLight').toggleClass('active', t !== 'dark');
        var apiMode = API.getMode();
        $('#prefApiFake').toggleClass('active', apiMode === 'fake');
        $('#prefApiReal').toggleClass('active', apiMode === 'real');
        $('#apiRealSettings').toggle(apiMode === 'real');
      }
    });

    // Save settings on any change in the panel
    $(document).on('change', '#sidePanelBody [name]', function () {
      if ($('#sidePanelTitle').text() === 'Général') {
        var data = {};
        $('#sidePanelBody [name]').each(function () { data[$(this).attr('name')] = $(this).val(); });
        STX.set('settings', data);
        if (data.apiBaseUrl !== undefined) API.setBaseUrl(data.apiBaseUrl);
      }
    });

    // Advanced Options – label click : ouvre/ferme le panel
    $(document).on('click', '.adv-chk-label', function (e) {
      if ($(e.target).is('.adv-chk')) return;
      e.preventDefault();
      if ($('#sidePanel').hasClass('open') && $('#sidePanelTitle').text() === 'Advanced Options') {
        closeSidePanel();
      } else {
        var $view = $(this).closest('.job-view');
        var viewId = $view.attr('id') || '';
        var type = viewId.replace(/^view-/, '').replace(/-\d+$/, '');
        var def = JobRegistry.get(type);
        var advHtml = def && typeof def.buildAdv === 'function' ? def.buildAdv() : '';
        if (!advHtml) return;
        openSidePanel('Advanced Options', advHtml);
        var stxKey = 'job.' + viewId.replace('view-', '');
        var saved = (STX.get(stxKey) || {}).adv;
        autoNameFields($('#sidePanelBody'));
        restoreView($('#sidePanelBody'), saved);
      }
    });

    // Live-save des Advanced Options
    var saveAdvOptions = debounce(function () {
      if ($('#sidePanelTitle').text() !== 'Advanced Options') return;
      var $active = $('.job-view.active');
      if (!$active.length) return;
      var stxKey = 'job.' + $active.attr('id').replace('view-', '');
      var cur = STX.get(stxKey) || {};
      cur.adv = serializeView($('#sidePanelBody'));
      STX.set(stxKey, cur);
    }, 400);

    $(document).on('input change', '#sidePanelBody input, #sidePanelBody select', function () {
      saveAdvOptions();
    });
    $(document).on('click', '#sidePanelBody .btn-toggle', function () {
      saveAdvOptions();
    });

  });

}(jQuery, window.STX, window.API, window.JobRegistry));
