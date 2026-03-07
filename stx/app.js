$(function () {

  // ─────────────────────────────────────────────
  // THEME
  // ─────────────────────────────────────────────
  const THEME_KEY = 'styx-theme';

  function applyTheme(t) {
    $('html').attr('data-theme', t);
    localStorage.setItem(THEME_KEY, t);
    $('#lblDark').css('opacity', t === 'dark' ? 1 : .3);
    $('#lblLight').css('opacity', t === 'light' ? 1 : .3);
    $('#prefDark').toggleClass('active', t === 'dark');
    $('#prefLight').toggleClass('active', t === 'light');
  }

  $('#themeToggle').on('click', () =>
    applyTheme($('html').attr('data-theme') === 'dark' ? 'light' : 'dark'));
  // Delegated: prefDark/prefLight vivent dans le side panel (injecté dynamiquement)
  $(document).on('click', '#prefDark',  function () { applyTheme('dark'); });
  $(document).on('click', '#prefLight', function () { applyTheme('light'); });

  // ── API mode toggle (injecté dynamiquement dans le side panel Settings) ──
  function _applyApiMode(mode) {
    API.setMode(mode);
    STX.merge('settings', { apiMode: mode });
    $('#prefApiFake').toggleClass('active', mode === 'fake');
    $('#prefApiReal').toggleClass('active', mode === 'real');
    $('#apiRealSettings').toggle(mode === 'real');
  }
  $(document).on('click', '#prefApiFake', function () { _applyApiMode('fake'); });
  $(document).on('click', '#prefApiReal', function () { _applyApiMode('real'); });

  applyTheme(localStorage.getItem(THEME_KEY) || 'dark');

  // ─────────────────────────────────────────────
  // STORAGE (STX namespace)
  // ─────────────────────────────────────────────
  var STX = (function () {
    var NS = 'styx.';
    return {
      get: function (k) {
        try {
          return JSON.parse(localStorage.getItem(NS + k));
        } catch (e) {
          return null;
        }
      },
      set: function (k, v) {
        localStorage.setItem(NS + k, JSON.stringify(v));
      },
      merge: function (k, p) {
        this.set(k, $.extend(true, this.get(k) || {}, p));
      },
      del: function (k) {
        localStorage.removeItem(NS + k);
      },
    };
  })();

  // ─────────────────────────────────────────────
  // API (fake via fake_api.json)
  // ─────────────────────────────────────────────
  var API = (function () {

    // ── Mode & config (persistés dans STX 'settings') ──
    var _mode    = (STX.get('settings') || {}).apiMode    || 'fake';
    var _baseUrl = (STX.get('settings') || {}).apiBaseUrl || '';

    // ══════════════════════════════════════════════
    // FAKE — lit fake_api.json
    // ══════════════════════════════════════════════
    var _db = null;
    var _fakeReady = $.getJSON('fake_api.json').then(function (data) { _db = data; });

    function _fakeResolve(method, path) {
      if (!_db) return undefined;
      var key = method + ' ' + path;
      if (key in _db) return _db[key];
      var noQ = path.split('?')[0];
      var base = method + ' ' + noQ;
      if (base in _db) return _db[base];
      var parent = method + ' ' + noQ.replace(/\/[^/]+$/, '');
      return parent in _db ? _db[parent] : undefined;
    }

    function _fakeCall(method, path) {
      return $.Deferred(function (dfd) {
        $.when(_fakeReady).then(function () {
          var resp = _fakeResolve(method, path);
          if (resp === undefined) {
            console.warn('[API:fake] No response for:', method, path);
            dfd.reject({ status: 404, message: 'Not found in fake_api.json: ' + method + ' ' + path });
            return;
          }
          setTimeout(function () { dfd.resolve($.extend(true, {}, resp)); }, 120);
        });
      }).promise();
    }

    var _tree = null;
    function _ensureTree() {
      if (!_tree && _db) _tree = (_db['GET /api/JobEnvironment/explore'] || {})._tree || {};
      return _tree || {};
    }

    function _fakeExploreDir(path, opts) {
      var isFolder  = !!(opts && opts.isFolder);
      var extension = (opts && opts.extension) ? String(opts.extension).replace(/^\./, '').toLowerCase() : null;
      return $.Deferred(function (dfd) {
        $.when(_fakeReady).always(function () {
          var node = _ensureTree()[path || ''] || { folders: [], files: [] };
          var files = node.files || [];
          if (isFolder) {
            files = [];
          } else if (extension) {
            files = files.filter(function (f) {
              return f.toLowerCase().slice(-(extension.length + 1)) === '.' + extension;
            });
          }
          dfd.resolve({ folders: node.folders || [], files: files, scenarios: node.scenarios || null });
        });
      }).promise();
    }

    // ══════════════════════════════════════════════
    // REAL — appels HTTP vers _baseUrl
    // ══════════════════════════════════════════════
    function _ajax(method, path, data) {
      var opts = {
        url: _baseUrl + path,
        method: method,
        contentType: 'application/json',
        headers: { Accept: 'application/json' },
      };
      if (data !== undefined) opts.data = JSON.stringify(data);
      return $.ajax(opts).then(null, function (xhr) {
        var msg = '';
        try { msg = xhr.responseJSON.message || xhr.statusText; } catch (e) { msg = xhr.statusText || String(xhr.status); }
        console.error('[API:real]', method, path, '→', xhr.status, msg);
        return $.Deferred().reject({ status: xhr.status, message: msg }).promise();
      });
    }

    function _realExploreDir(path, opts) {
      var params = { path: path || '' };
      if (opts && opts.isFolder)  params.isFolder  = true;
      if (opts && opts.extension) params.extension = opts.extension;
      return _ajax('GET', '/api/JobEnvironment/explore?' + $.param(params))
        .then(function (resp) {
          return { folders: resp.folders || [], files: resp.files || [], scenarios: resp.scenarios || null };
        });
    }

    // ══════════════════════════════════════════════
    // Interface publique
    // ══════════════════════════════════════════════
    return {
      get: function (path) {
        return _mode === 'real' ? _ajax('GET', path) : _fakeCall('GET', path);
      },
      post: function (path, data) {
        return _mode === 'real' ? _ajax('POST', path, data) : _fakeCall('POST', path);
      },
      exploreDir: function (path, opts) {
        return _mode === 'real' ? _realExploreDir(path, opts) : _fakeExploreDir(path, opts);
      },
      getRoot: function () {
        return _mode === 'real'
          ? ((STX.get('settings') || {}).apiRoot || '')
          : (_db ? ((_db['GET /api/JobEnvironment/explore'] || {})._root || '') : '');
      },
      getMode:    function ()    { return _mode; },
      setMode:    function (m)   { _mode = m; },
      getBaseUrl: function ()    { return _baseUrl; },
      setBaseUrl: function (url) { _baseUrl = url; },
    };
  })();

  // ─────────────────────────────────────────────
  // FORM SERIALIZATION HELPERS
  // ─────────────────────────────────────────────
  function debounce(fn, ms) {
    var t;
    return function () {
      var a = arguments,
        c = this;
      clearTimeout(t);
      t = setTimeout(function () {
        fn.apply(c, a);
      }, ms);
    };
  }

  // Attribue name="f0", "f1"... aux champs sans name (filet de sécurité)
  // Exclut les helpers UI : chk-all et checkboxes de scénarios
  function autoNameFields($ctx) {
    var i = 0;
    $ctx.find('input:not([name]):not(.chk-all):not(.scen-table input), select:not([name]), textarea:not([name])').each(function () {
      $(this).attr('name', 'f' + (i++));
    });
  }

  var PERIOD_MONTHS = {
    '1y': 12,
    '5y': 60,
    '30y': 360,
    '40y': 480
  };

  function serializeView($ctx) {
    var data = {};

    // Champs nommés (inputs, selects) — sauf scénarios gérés à part
    $ctx.find('[name]').not('.scen-table [name]').each(function () {
      data[$(this).attr('name')] = this.type === 'checkbox' ? this.checked : $(this).val();
    });

    // btn-toggle groups (data-grp)
    // Groupe à 1 bouton → booléen ; groupe multi → tableau d'indices dans __groups
    var groupInfo = {};
    $ctx.find('.btn-toggle[data-grp]').each(function () {
      var g = $(this).data('grp');
      if (!groupInfo[g]) groupInfo[g] = {
        count: 0,
        active: []
      };
      var idx = groupInfo[g].count++; // position dans le groupe, pas dans le DOM parent
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

    // Version mode : Reference ou Custom
    var $verRef = $ctx.find('.ver-tog.ver-ref');
    if ($verRef.length) {
      var isRef = $verRef.hasClass('active');
      data.refModelSelected = isRef;
      // Effacer les champs de l'autre mode
      if (isRef) {
        delete data.customVersion;
      } else {
        delete data.model;
        delete data.version;
      }
    }

    // Period buttons : active data-period per period-line
    $ctx.find('.period-line').each(function () {
      var name = $(this).find('[name$="Enabled"]').attr('name');
      if (!name) return;
      var prefix = name.replace('Enabled', '');
      data[prefix + 'Period'] = $(this).find('.period-btn.active').data('period') || '';
    });

    // Scénarios : array des Num sélectionnés
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
  }

  function restoreView($ctx, data) {
    if (!data) return;

    // Champs nommés
    $ctx.find('[name]').not('.scen-table [name]').each(function () {
      var n = $(this).attr('name');
      if (!(n in data)) return;
      if (this.type === 'checkbox') $(this).prop('checked', !!data[n]);
      else $(this).val(data[n]);
    });

    // Groupes multi-boutons (arrays dans __groups)
    if (data.__groups) {
      $.each(data.__groups, function (g, idxs) {
        var $btns = $ctx.find('.btn-toggle[data-grp="' + g + '"]');
        $btns.each(function (i) {
          $(this).toggleClass('active', idxs.indexOf(i) !== -1);
        });
      });
    }

    // Groupes mono-bouton (booléens au top level)
    $ctx.find('.btn-toggle[data-grp]').each(function () {
      var g = $(this).data('grp');
      if ($ctx.find('.btn-toggle[data-grp="' + g + '"]').length === 1 && g in data) {
        $(this).toggleClass('active', !!data[g]);
      }
    });

    // Period buttons : restore active state
    $ctx.find('.period-line').each(function () {
      var name = $(this).find('[name$="Enabled"]').attr('name');
      if (!name) return;
      var prefix = name.replace('Enabled', '');
      var key = prefix + 'Period';
      if (!(key in data)) return;
      $(this).find('.period-btn').removeClass('active');
      $(this).find('.period-btn[data-period="' + data[key] + '"]').addClass('active');
    });

    // Scénarios
    if (data.scenarios) {
      $ctx.find('.scen-table tbody tr').each(function () {
        var num = $(this).find('td').eq(1).text().trim();
        $(this).find('input[type=checkbox]').prop('checked', data.scenarios.indexOf(num) !== -1);
      });
    }
  }

  // ─────────────────────────────────────────────
  // SIDEBAR COLLAPSE
  // ─────────────────────────────────────────────
  $('#btnCollapse').on('click', function () {
    const c = $('#appLayout').toggleClass('sidebar-collapsed').hasClass('sidebar-collapsed');
    $('#collapseIcon path').attr('d', c ? 'M4 2l4 4-4 4' : 'M8 2L4 6l4 4');
  });

  // ─────────────────────────────────────────────
  // CONSOLE
  // ─────────────────────────────────────────────
  function openConsole() {
    $('#appLayout').addClass('console-open');
    $('#btnConsole').addClass('active');
  }

  function closeConsole() {
    $('#appLayout').removeClass('console-open');
    $('#btnConsole').removeClass('active');
  }

  $('#btnConsole').on('click', () =>
    $('#appLayout').hasClass('console-open') ? closeConsole() : openConsole());
  $('#btnCloseConsole').on('click', closeConsole);

  function renderLog(ts, msg, type) {
    var cls = type === 'warn' ? 'warn' : type === 'error' ? 'error' : '';
    var $l = $('<div class="c-line ' + cls + '"><span class="ts">[' + ts + ']</span>' + msg + '</div>');
    $('#consoleBody').append($l);
    var b = $('#consoleBody')[0];
    b.scrollTop = b.scrollHeight;
  }

  function cLog(msg, type) {
    var ts = new Date().toLocaleTimeString('fr-FR');
    renderLog(ts, msg, type);
    var logs = STX.get('console') || [];
    logs.push({
      ts: ts,
      msg: msg,
      type: type || ''
    });
    if (logs.length > 200) logs.splice(0, logs.length - 200);
    STX.set('console', logs);
  }

  // Restore console au chargement
  (function () {
    var logs = STX.get('console') || [];
    logs.forEach(function (l) {
      renderLog(l.ts, l.msg, l.type);
    });
  }());

  // Migration au démarrage : nettoyer les clés stale dans toutes les entrées job
  // (f0/f1, versionRef, scenAll, scen1/2/3 issus d'anciennes versions du code)
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
        if (/^f\d+$/.test(k) || STALE.indexOf(k) !== -1) {
          delete entry[k];
          dirty = true;
        }
      });
      if (!entry.createdAt) {
        entry.createdAt = Date.now();
        dirty = true;
      }
      if (dirty) STX.set(stxKey, entry);
    }
  }());

  // ─────────────────────────────────────────────
  // SIDE PANEL (générique)
  // ─────────────────────────────────────────────
  function openSidePanel(title, html) {
    $('#sidePanelTitle').text(title);
    $('#sidePanelBody').html(html);
    $('#sidePanel').addClass('open');
  }

  function closeSidePanel() {
    $('#sidePanel').removeClass('open');
    $('#btnAbout, #btnSettings').removeClass('active');
  }

  $('#closeSidePanel').on('click', closeSidePanel);

  // Fermer en cliquant en dehors
  $(document).on('click', function (e) {
    if ($('#sidePanel').hasClass('open') &&
      !$(e.target).closest('#sidePanel').length &&
      !$(e.target).closest('#btnAbout').length &&
      !$(e.target).closest('#btnSettings').length &&
      !$(e.target).closest('.adv-chk-label').length &&
      !$(e.target).closest('.btn-help-job').length) {
      closeSidePanel();
    }
  });

  // Help Center
  function buildHelpContent() {
    return (
      '<div class="panel-section">' +
      '<h4>Soumettre un job</h4>' +
      '<ul>' +
      '<li>Soumettre un job Savings</li>' +
      '<li>Soumettre un job UFX</li>' +
      '<li>Configurer les scénarios</li>' +
      '<li>Options avancées</li>' +
      '</ul>' +
      '</div>' +
      '<div class="panel-section">' +
      '<h4>Monitoring</h4>' +
      '<ul>' +
      '<li>Comprendre les états de job</li>' +
      '<li>Filtrer les résultats</li>' +
      '<li>Progression en temps réel</li>' +
      '</ul>' +
      '</div>' +
      '<div class="panel-section">' +
      '<h4>Configuration</h4>' +
      '<ul>' +
      '<li>Paramètres utilisateur</li>' +
      '<li>Gestion des environnements</li>' +
      '<li>Thème Dark / Light</li>' +
      '</ul>' +
      '</div>' +
      '<div class="panel-section">' +
      '<h4>À propos</h4>' +
      '<ul>' +
      '<li>Version 2026.01.00</li>' +
      '<li>Moteur OMEN · SGA</li>' +
      '<li>© Société Générale Assurances</li>' +
      '</ul>' +
      '</div>'
    );
  }

  // ─── Aide contextuelle par type de job ───────
  var _JOB_HELP = {
    savings: {
      synopsis: 'Run OMEN de type Épargne — déterministe, stochastique et pricer.',
      fields: [
        ['Environnement', 'Chemin réseau UNC vers le dossier use case OMEN (ex. \\\\srv\\MOTEUR\\recette\\usecases\\Cas01). Le bouton Browse s\'active dès qu\'un chemin est renseigné.'],
        ['Inputs', 'Choisissez le jeu de données d\'entrée dans la liste. Les inputs disponibles sont chargés depuis le sous-dossier input/ de l\'environnement.'],
        ['Version Omen', 'Sélectionnez la version du moteur OMEN à utiliser. Passez en mode Custom pour saisir un chemin de version spécifique.'],
        ['Périodes & itérations', 'Définissez les périodes (en mois) et le nombre d\'itérations pour les modes Deterministic, Stochastic et Pricer. Cochez la case pour activer chaque mode.'],
        ['Guaranteed Floor', 'Activez cette option pour forcer un plancher garanti sur les résultats.'],
        ['Job Omen Type', 'Sélectionnez le type de run OMEN (ex. Full, Sensitivity…).'],
        ['Advanced Options', 'Sliding, Test Sliding, Launch Input Task Only, Remove Input Generation, itérations SCR Life, priorité HPC, type de tâche (alm / Standard / SCR), exécution différée.'],
      ],
    },
    nonlife: {
      synopsis: 'Run OMEN pour les produits Non Life — dommages et prévoyance.',
      fields: [
        ['Environnement', 'Chemin réseau UNC vers le dossier use case Non Life. Browse disponible dès qu\'un chemin est saisi.'],
        ['Inputs', 'Sélectionnez le jeu de données d\'entrée depuis le sous-dossier input/.'],
        ['Version Omen', 'Version du moteur OMEN pour ce run Non Life.'],
        ['Périodes & itérations', 'Définissez la période de simulation (mois) et le nombre d\'itérations pour Deterministic et Stochastic.'],
        ['Job Omen Type', 'Type de run OMEN à exécuter.'],
      ],
    },
    risklife: {
      synopsis: 'Run OMEN Risk Life avec projection stochastique sur scénarios.',
      fields: [
        ['Environnement', 'Chemin réseau UNC vers le dossier use case Risk Life.'],
        ['Inputs', 'Jeu de données d\'entrée chargé depuis input/.'],
        ['Version Omen', 'Version du moteur OMEN à utiliser.'],
        ['Durée de projection', 'Nombre de mois de projection.'],
        ['Itérations', 'Nombre d\'itérations stochastiques. Cochez Auto pour le calcul automatique.'],
        ['Scénarios', 'Sélectionnez un ou plusieurs scénarios à lancer. Au moins un scénario est requis.'],
        ['Advanced Options', 'Sliding, Test Sliding, priorité du job (Automatic / Normal / High).'],
      ],
    },
    risklifekp: {
      synopsis: 'Run OMEN Risk Life pour la Pologne (KP) — calcul de capital réglementaire.',
      fields: [
        ['Environnement', 'Chemin réseau UNC vers le dossier use case Risk Life KP.'],
        ['Inputs', 'Jeu de données d\'entrée chargé depuis input/.'],
        ['Version Omen', 'Version du moteur OMEN à utiliser.'],
        ['Période', 'Nombre de mois de la période de simulation.'],
        ['Itérations', 'Nombre d\'itérations. Cochez Auto pour le calcul automatique.'],
        ['Scénarios', 'Sélectionnez les scénarios à inclure dans le run.'],
        ['Advanced Options', 'Sliding, Test Sliding, priorité du job (Automatic / Normal / High).'],
      ],
    },
    tdr: {
      synopsis: 'Run OMEN pour le calcul du Taux de Rendement.',
      fields: [
        ['Environnement', 'Chemin réseau UNC vers le dossier use case TdR.'],
        ['Inputs', 'Jeu de données d\'entrée depuis input/.'],
        ['Version Omen', 'Version du moteur OMEN.'],
        ['Période', 'Durée de simulation en mois.'],
      ],
    },
    brd: {
      synopsis: 'Run OMEN Savings avec projection Brut de Rachat et Décès.',
      fields: [
        ['Environnement', 'Chemin réseau UNC vers le dossier use case Savings BRD.'],
        ['Inputs', 'Jeu de données d\'entrée depuis input/.'],
        ['Version Omen', 'Version du moteur OMEN.'],
        ['Durée de projection', 'Nombre d\'années de projection (entier positif).'],
        ['Scénarios', 'Sélectionnez les scénarios à inclure dans le run.'],
        ['Advanced Options', 'Priorité du job (Automatic / Normal / High).'],
      ],
    },
    ufx: {
      synopsis: 'Reporting réglementaire au format UFX — Universal Format Exchange.',
      fields: [
        ['Path', 'Chemin réseau UNC complet vers le fichier ou dossier UFX à traiter.'],
        ['Is Folder', 'Cochez cette option pour que le Browse ne liste que les dossiers (aucun fichier).'],
      ],
    },
    custominput: {
      synopsis: 'Applique des scripts d\'actions personnalisées sur un dossier d\'inputs.',
      fields: [
        ['Input to Custom', 'Chemin réseau UNC vers le dossier contenant les fichiers d\'entrée à transformer.'],
        ['Custom Actions', 'Chemin réseau UNC vers le dossier contenant les scripts d\'actions à appliquer aux inputs.'],
      ],
    },
    scenariotransformator: {
      synopsis: 'Transforme des scénarios économiques vers le format d\'un modèle cible.',
      fields: [
        ['Environnement', 'Chemin réseau UNC vers le dossier de données à transformer. Le bouton Browse s\'active dès qu\'un chemin est renseigné.'],
        ['Model Type', 'Version de modèle pour la transformation : 2017, 2018, 2020 ou 2020 V2.'],
        ['Période', 'Fréquence de la transformation : Mois (mensuelle) ou Année (annuelle).'],
        ['Nb itérations', 'Nombre d\'itérations de la transformation de scénarios.'],
        ['Coupons', 'Type de coupon à générer : ZC (zéro coupon) ou TC (taux constant).'],
        ['Split', 'Activez cette option pour découper la sortie en fichiers séparés par scénario.'],
      ],
    },
  };

  function buildJobHelp(type) {
    var info = _JOB_HELP[type];
    if (!info) return '<div class="panel-section"><p>Aucune aide disponible pour ce type de job.</p></div>';
    var rows = info.fields.map(function (e) {
      return '<li><strong>' + e[0] + '</strong> — ' + e[1] + '</li>';
    }).join('');
    return (
      '<div class="panel-section"><h4>' + info.synopsis + '</h4></div>' +
      '<div class="panel-section"><ul>' + rows + '</ul></div>'
    );
  }

  $(document).on('click', '.btn-help-job', function () {
    var $view = $(this).closest('.job-view');
    var id = $view.attr('id').replace('view-', '');
    var type = (STX.get('job.' + id) || {}).type;
    var label = JOB_LABELS[type] || 'Job';
    var title = label + ' — Guide';
    if ($('#sidePanel').hasClass('open') && $('#sidePanelTitle').text() === title) {
      closeSidePanel();
    } else {
      openSidePanel(title, buildJobHelp(type));
    }
  });

  $('#btnAbout').on('click', function () {
    if ($('#sidePanel').hasClass('open') && $('#sidePanelTitle').text() === 'Help Center') {
      closeSidePanel();
    } else {
      $(this).addClass('active');
      openSidePanel('Help Center', buildHelpContent());
    }
  });

  // Advanced Options – label click : ouvre/ferme le panel
  $(document).on('click', '.adv-chk-label', function (e) {
    if ($(e.target).is('.adv-chk')) return; // checkbox gère son propre état
    e.preventDefault(); // ne pas toggler le checkbox
    if ($('#sidePanel').hasClass('open') && $('#sidePanelTitle').text() === 'Advanced Options') {
      closeSidePanel();
    } else {
      var $view = $(this).closest('.job-view');
      var viewId = $view.attr('id') || '';
      var type = viewId.replace(/^view-/, '').replace(/-\d+$/, '');
      var builders = {
        savings:    buildAdvSavings,
        nonlife:    buildAdvNonLife,
        risklife:   buildAdvRiskLife,
        risklifekp: buildAdvRiskLifeKp,
        tdr: buildAdvTdr,
        brd: buildAdvBrd,
        'tool-compare': buildAdvTool,
        'tool-extract': buildAdvTool,
        'tool-report': buildAdvTool,
      };
      openSidePanel('Advanced Options', (builders[type] || buildAdvSavings)());
      var stxKey = 'job.' + viewId.replace('view-', '');
      var saved = (STX.get(stxKey) || {}).adv;
      autoNameFields($('#sidePanelBody'));
      restoreView($('#sidePanelBody'), saved);
    }
  });

  // Advanced Options – checkbox : active/désactive (état capturé par serializeView, pas d'action sur le panel)

  // Live-save des Advanced Options dans le sub-objet "adv" du job actif
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

  // ─────────────────────────────────────────────
  // MODALS
  // ─────────────────────────────────────────────
  function openModal(id) {
    $('#' + id).addClass('open');
  }

  function closeModal(id) {
    $('#' + id).removeClass('open');
  }

  $(document).on('click', '[data-close]', function () {
    closeModal($(this).data('close'));
  });
  $('.overlay').on('click', function (e) {
    if ($(e.target).hasClass('overlay')) closeModal($(this).attr('id'));
  });

  $('#btnSettings').on('click', function () {
    if ($('#sidePanel').hasClass('open') && $('#sidePanelTitle').text() === 'Général') {
      closeSidePanel();
    } else {
      $(this).addClass('active');
      openSidePanel('Général', buildSettingsContent());
      // Restore depuis storage
      var saved = STX.get('settings') || {};
      if (saved.langue)    $('#sidePanelBody [name="langue"]').val(saved.langue);
      if (saved.priority)  $('#sidePanelBody [name="priority"]').val(saved.priority);
      if (saved.apiBaseUrl) $('#sidePanelBody [name="apiBaseUrl"]').val(saved.apiBaseUrl);
      if (saved.apiRoot)   $('#sidePanelBody [name="apiRoot"]').val(saved.apiRoot);
      // Sync état des boutons thème
      var t = $('html').attr('data-theme');
      $('#prefDark').toggleClass('active', t === 'dark');
      $('#prefLight').toggleClass('active', t !== 'dark');
      // Sync état des boutons API
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
      $('#sidePanelBody [name]').each(function () {
        data[$(this).attr('name')] = $(this).val();
      });
      STX.set('settings', data);
      if (data.apiBaseUrl !== undefined) API.setBaseUrl(data.apiBaseUrl);
    }
  });

  function buildSettingsContent() {
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
      '<div class="pref-row"><span class="pref-key">Utilisateur</span> <span class="pref-val">Pablo RABADAN</span></div>' +
      '<div class="pref-row"><span class="pref-key">Rôle</span>        <span class="pref-val">Actuaire</span></div>' +
      '<div class="pref-row"><span class="pref-key">Équipe</span>      <span class="pref-val">ASSU · Production</span></div>' +
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
  }
  // ── Explorateur de fichiers ───────────────────
  var _browseTarget = null;       // input appelant
  var _browseCurrent = '';        // chemin API courant (chemin complet dans le fake tree)
  var _browseBase = '';           // chemin de départ (= chemin normalisé d'Environment, ou '')
  var _browseRoot = '';           // préfixe d'affichage (valeur brute du champ Environment)
  var _browseIsFolderOnly = false; // true → n'affiche que les dossiers (isFolder=true)

  // Chemin à afficher : _browseRoot + partie RELATIVE à _browseBase
  function _browseDisplay(apiPath) {
    var rel = apiPath;
    if (_browseBase && apiPath.indexOf(_browseBase) === 0) {
      rel = apiPath.slice(_browseBase.length).replace(/^\//, '');
    }
    if (_browseRoot) {
      var base = _browseRoot.replace(/[\\\/]+$/, '');
      return rel ? base + '\\' + rel.replace(/\//g, '\\') : base;
    }
    return rel ? rel.replace(/\//g, '\\') : '(root)';
  }

  function loadBrowseDir(apiPath) {
    _browseCurrent = apiPath || '';
    API.exploreDir(_browseCurrent, { isFolder: _browseIsFolderOnly }).then(function (node) {
      var html = '';
      // Afficher ".." uniquement si on est au-delà du dossier de départ
      if (_browseCurrent !== _browseBase) {
        html += '<div class="file-item file-up"><span>📁</span> ..</div>';
      }
      node.folders.forEach(function (f) {
        html += '<div class="file-item" data-folder="' + f + '"><span>📁</span> ' + f + '</div>';
      });
      node.files.forEach(function (f) {
        html += '<div class="file-item file-file" data-file="' + f + '"><span>📄</span> ' + f + '</div>';
      });
      if (!html) html = '<div style="color:var(--text-dim);font-size:.65rem;padding:8px 4px">Empty folder</div>';
      $('#fileList').html(html);
      $('#browsePath').val(_browseDisplay(_browseCurrent));
    });
  }

  $(document).on('click', '.btn-open-env', function () {
    var path = $(this).closest('.f-row').find('[name="environment"]').val().trim();
    if (!path) {
      openConsole();
      cLog('Open : aucun chemin Environment renseigné.', 'error');
      return;
    }
    // Convertit le chemin Windows en URI file://
    var uri;
    if (/^\\\\/.test(path)) {
      // UNC : \\server\share\... → file://server/share/...
      uri = 'file:' + path.replace(/\\/g, '/');
    } else {
      // Chemin local : C:\... → file:///C:/...
      uri = 'file:///' + path.replace(/\\/g, '/').replace(/^\/+/, '');
    }
    window.open(uri);
    cLog('Ouverture dans l\'explorateur : ' + path);
  });

  $(document).on('click', '.btn-browse', function () {
    var $btn = $(this);
    var startPath = '';
    _browseRoot = '';
    _browseBase = '';
    _browseIsFolderOnly = false;
    if ($btn.data('ver-action') === 'browse') {
      _browseTarget = $btn.closest('.fg-ctrl').find('[name="customVersion"]');
    } else {
      _browseTarget = $btn.closest('.f-row').find('input[type="text"]').first();
    }
    if ($btn.hasClass('btn-browse-env')) {
      _browseRoot = API.getRoot(); // \\srvrbxassufp01 — butée UNC, pas de ".." au-delà
      _browseBase = ''; // toujours depuis la racine
      _browseTarget = $btn.closest('.f-row').find('[name="environment"]');
      startPath = ''; // toujours depuis _root, peu importe la valeur saisie
    }
    if ($btn.hasClass('btn-browse-ufx')) {
      _browseRoot = API.getRoot();
      _browseIsFolderOnly = $btn.closest('.f-row').find('[name="isFolder"]').is(':checked');
    }
    if ($btn.hasClass('btn-browse-folder')) {
      _browseRoot = API.getRoot();
      _browseIsFolderOnly = true;
    }
    if (_browseTarget && !_browseTarget.length) _browseTarget = null;
    loadBrowseDir(startPath);
    openModal('mBrowse');
  });

  // Dossier → naviguer dedans
  $(document).on('click', '#fileList .file-item[data-folder]', function () {
    var sub = $(this).data('folder');
    loadBrowseDir(_browseCurrent ? _browseCurrent + '/' + sub : sub);
  });

  // ".." → remonter (jamais au-dessus de _browseBase)
  $(document).on('click', '#fileList .file-up', function () {
    var parts = _browseCurrent.split('/');
    parts.pop();
    loadBrowseDir(parts.join('/'));
  });

  // Fichier → sélectionner directement
  $(document).on('click', '#fileList .file-file', function () {
    var file = $(this).data('file');
    var apiPath = _browseCurrent ? _browseCurrent + '/' + file : file;
    $('#browsePath').val(_browseDisplay(apiPath));
  });

  $('#btnFileSelect').on('click', function () {
    var path = $('#browsePath').val();
    if (_browseTarget) {
      _browseTarget.val(path).trigger('input').trigger('change');
      _browseTarget = null;
    }
    cLog('Chemin sélectionné : ' + path);
    closeModal('mBrowse');
  });

  // ─────────────────────────────────────────────
  // ADV TOGGLE BUTTONS (single-select per group)
  // ─────────────────────────────────────────────
  $(document).on('click', '.btn-toggle[data-grp]', function () {
    const g = $(this).data('grp');
    $('[data-grp="' + g + '"]').not(this).removeClass('active');
    $(this).toggleClass('active');
  });

  // ─────────────────────────────────────────────
  // OMEN JOBS DROPDOWN
  // ─────────────────────────────────────────────
  $('#btnOmenJobs').on('click', function (e) {
    e.stopPropagation();
    $('#omenDropdown').toggleClass('open');
  });
  $(document).on('click', function () {
    $('#omenDropdown, #toolsDropdown').removeClass('open');
  });

  // Tools dropdown
  $('#btnTools').on('click', function (e) {
    e.stopPropagation();
    $('#toolsDropdown').toggleClass('open');
  });

  // ─────────────────────────────────────────────
  // TAB / JOB MANAGEMENT
  // ─────────────────────────────────────────────
  var jobIdx = 0;
  var _outputCache = [];

  var JOB_LABELS = {
    savings:    'Omen Savings',
    nonlife:    'Omen Non Life',
    risklife:   'Omen Risk Life',
    risklifekp: 'Omen Risk Life KP',
    tdr: 'Omen TdR',
    brd: 'Omen Savings BRD',
    ufx: 'UFX Job',
    monitoring: 'Monitoring',
    'tool-compare': 'Tool · Compare',
    'tool-extract': 'Tool · Extract',
    'tool-report': 'Tool · Report',
    'custominput': 'Custom Input',
    'scenariotransformator': 'Scenario Transformator',
  };

  function openJob(type) {
    // Monitoring is singleton
    if (type === 'monitoring') {
      if ($('#view-monitoring').length) {
        activateTab('monitoring');
        return;
      }
      $('#jobArea').append(buildMonitoring());
      $('#emptyState').hide();
      // Restore filtres monitoring
      var mf = (STX.get('monitoring') || {}).filters || {};
      if (mf.id) $('.mf-id').val(mf.id);
      if (mf.name) $('.mf-name').val(mf.name);
      if (mf.priority) $('.mf-priority').val(mf.priority);
      if (mf.account) $('.mf-account').val(mf.account);
      addTab('monitoring', 'Monitoring', 'monitoring');
      activateTab('monitoring');
      loadMonitoringJobs();
      return;
    }

    jobIdx++;
    var id = type + '-' + jobIdx;
    var stxKey = 'job.' + id;
    var label = JOB_LABELS[type] || type;
    var omenBuilders = {
      savings:    buildOmenSavings,
      nonlife:    buildOmenNonLife,
      risklife:   buildOmenRiskLife,
      risklifekp: buildOmenRiskLifeKp,
      tdr: buildOmenTdr,
      brd: buildOmenBrd,
    };
    var html;
    if (type === 'ufx') html = buildUfx(id);
    else if (type === 'custominput') html = buildCustomInput(id);
    else if (type === 'scenariotransformator') html = buildScenarioTransformator(id);
    else if (type.indexOf('tool-') === 0) html = buildTool(id, type);
    else html = (omenBuilders[type] || buildOmenSavings)(id);

    $('#jobArea').append(html);
    $('#emptyState').hide();

    var $view = $('#view-' + id);
    var meta = {
      type: type,
      id: id,
      label: label,
      createdAt: Date.now()
    };

    autoNameFields($view);
    syncBrowseButtons($view);
    STX.set(stxKey, meta);

    // Init API : peuple les selects depuis l'API
    if (type === 'savings')              initSavingsView($view);
    if (type === 'brd')                  initBrdView($view);
    if (type === 'tdr')                  initTdrView($view);
    if (type === 'nonlife')              initNonLifeView($view);
    if (type === 'risklife')             initRiskLifeView($view);
    if (type === 'risklifekp')           initRiskLifeKpView($view);
    if (type === 'scenariotransformator') initScenarioTransformatorView($view);

    addTab(id, label, type);
    activateTab(id);
    cLog('Job ouvert : ' + label);
  }

  function tabIcon(type) {
    if (type === 'ufx') {
      return '<svg class="ti-svg" viewBox="0 0 12 12" fill="none"><rect x="0" y="0" width="12" height="12" rx="1" fill="#217346"/><path d="M3 3L9 9M9 3L3 9" stroke="white" stroke-width="1.6" stroke-linecap="round"/></svg>';
    }
    if (type === 'monitoring') {
      return '<svg class="ti-svg" viewBox="0 0 12 12" fill="currentColor"><rect x="0"  y="7"  width="2.2" height="5"  rx=".4"/><rect x="3.3" y="5"  width="2.2" height="7"  rx=".4"/><rect x="6.6" y="2.5" width="2.2" height="9.5" rx=".4"/><rect x="9.8" y="0"  width="2.2" height="12" rx=".4"/></svg>';
    }
    if (type && type.indexOf('tool') === 0) {
      return '<svg class="ti-svg" viewBox="0 0 12 12" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"><path d="M9.5 2.5a2.2 2.2 0 00-3 3L2.7 9.3a.75.75 0 001.1 1l3.8-3.8a2.2 2.2 0 003-3L9.2 4.9 8 3.8l1.5-1.3z"/></svg>';
    }
    // Omen: top half red, bottom half black, white center bar
    return '<svg class="ti-svg" viewBox="0 0 12 12" fill="none"><rect x="0" y="0" width="12" height="6" fill="#dc2626"/><rect x="0" y="6" width="12" height="6" fill="#111"/><rect x="0" y="5.25" width="12" height="1.5" fill="white"/></svg>';
  }

  function addTab(id, label, type) {
    const $t = $(
      '<div class="sidebar-tab" data-job="' + id + '">' +
      '<span class="tab-icon">' + tabIcon(type || id) + '</span>' +
      '<span class="tab-label">' + label + '</span>' +
      '<button class="tab-close" tabindex="-1">×</button>' +
      '</div>'
    );
    $('#sidebarTabs').append($t);
  }

  function activateTab(id) {
    $('.sidebar-tab').removeClass('active');
    $('.sidebar-tab[data-job="' + id + '"]').addClass('active');
    $('.job-view').removeClass('active');
    $('#view-' + id).addClass('active');
  }

  // Click tab → activate
  $(document).on('click', '.sidebar-tab', function () {
    activateTab($(this).data('job'));
  });

  // Close tab — supprime l'entrée STX associée
  $(document).on('click', '.tab-close', function (e) {
    e.stopPropagation();
    var $tab = $(this).closest('.sidebar-tab');
    var id = $tab.data('job');
    STX.del('job.' + id);
    $tab.remove();
    $('#view-' + id).remove();
    var $rem = $('.sidebar-tab');
    if ($rem.length) activateTab($rem.last().data('job'));
    else $('#emptyState').show();
  });

  // Nav bindings
  $('#btnNewUfx').on('click', function () {
    openJob('ufx');
  });
  $('#btnMonitoring').on('click', function () {
    openJob('monitoring');
  });
  $(document).on('click', '.job-type-opt', function () {
    openJob($(this).data('type'));
    $('#omenDropdown, #toolsDropdown').removeClass('open');
  });

  // ─────────────────────────────────────────────
  // LIVE-SAVE DES JOB VIEWS
  // ─────────────────────────────────────────────
  var saveJobView = debounce(function ($view) {
    var stxKey = 'job.' + $view.attr('id').replace('view-', '');
    var cur = STX.get(stxKey) || {};
    // Préserver uniquement les métadonnées, remplacer entièrement les valeurs du form
    var meta = {
      type: cur.type,
      id: cur.id,
      label: cur.label,
      createdAt: cur.createdAt,
      adv: cur.adv
    };
    STX.set(stxKey, $.extend(meta, serializeView($view)));
  }, 400);

  $(document).on('input change', '.job-view input, .job-view select', function () {
    saveJobView($(this).closest('.job-view'));
  });
  // btn-toggle dans les job views (pas dans le side panel)
  $(document).on('click', '.job-view .btn-toggle', function () {
    var $v = $(this).closest('.job-view');
    if ($v.length) saveJobView($v);
  });

  // ─────────────────────────────────────────────
  // BOUTON "LAST" : restaure le dernier job soumis du même type
  // ─────────────────────────────────────────────
  $(document).on('click', '.btn-last', function () {
    var $view = $(this).closest('.job-view');
    var id = $view.attr('id').replace('view-', '');
    var type = (STX.get('job.' + id) || {}).type;
    if (!type) return;
    var last = STX.get('lastSubmit.' + type);
    if (!last) {
      openConsole();
      cLog('Aucun job ' + type + ' soumis récemment.', 'warn');
      return;
    }

    restoreView($view, last);
    syncBrowseButtons($view);

    // Period checkboxes: fire change so .period-group toggling disabled class
    $view.find('.chk-period').trigger('change');

    // Adv : écrire dans STX (pour saveJobView / future ouverture manuelle)
    if (last.adv) {
      var cur = STX.get('job.' + id) || {};
      STX.set('job.' + id, $.extend(cur, {
        adv: last.adv
      }));
    }
    // Ouvrir le panel directement depuis last.adv, sans passer par trigger/STX
    if ($view.find('.adv-chk').prop('checked')) {
      var advBuilders = {
        savings:    buildAdvSavings,
        nonlife:    buildAdvNonLife,
        risklife:   buildAdvRiskLife,
        risklifekp: buildAdvRiskLifeKp,
        tdr: buildAdvTdr,
        brd: buildAdvBrd,
        'tool-compare': buildAdvTool,
        'tool-extract': buildAdvTool,
        'tool-report': buildAdvTool,
      };
      openSidePanel('Advanced Options', (advBuilders[type] || buildAdvSavings)());
      if (last.adv) restoreView($('#sidePanelBody'), last.adv);
    }

    // Version : trigger change sur model → options version synchronisées depuis cache,
    // puis appliquer la version sauvegardée
    $view.find('.ref-content [name="model"]').trigger('change');
    if (last.version) $view.find('.ref-content [name="version"]').val(last.version);

    // Charger les options de l'env puis restaurer explicitement les selects dynamiques
    var envPath = envToApiPath($view.find('[name="environment"]').val());
    if (envPath) {
      API.exploreDir(envPath + '/input').then(function (node) {
        var $sel = $view.find('[name="inputs"]');
        $sel.find('option:not(:first)').remove();
        (node.folders || []).forEach(function (s) {
          $sel.append('<option>' + s + '</option>');
        });
        if (last.inputs) $sel.val(last.inputs);
      });
      var _isRLType = (type === 'risklife' || type === 'risklifekp' || type === 'brd');
      if ($view.find('.scen-table').length) {
        API.exploreDir(envPath + '/scenario').then(function (node) {
          if (node.scenarios) {
            if (_isRLType) rebuildRLScenarios($view, node.scenarios);
            else           rebuildScenarios($view, node.scenarios);
            // Réappliquer les sélections sauvegardées après le rebuild
            if (last.scenarios && last.scenarios.length) {
              $view.find('.scen-table tbody tr').each(function () {
                var num = $(this).find('td').eq(1).text().trim();
                $(this).find('input[type=checkbox]').prop('checked', last.scenarios.indexOf(num) !== -1);
              });
            }
          }
        });
      }
    }

    saveJobView($view);
    cLog('Valeurs du dernier job ' + type + ' restaurées.');
  });

  // ─────────────────────────────────────────────
  // PERIOD BUTTON GROUPS
  // ─────────────────────────────────────────────
  $(document).on('click', '.period-btn', function () {
    var $grp = $(this).closest('.period-group');
    var period = $(this).data('period');
    $grp.find('.period-btn').removeClass('active');
    $(this).addClass('active');
    var isCustom = period === 'custom';
    $grp.find('.months-inp').prop('disabled', !isCustom);
    if (!isCustom && PERIOD_MONTHS[period]) {
      $grp.find('.months-inp').val(PERIOD_MONTHS[period]);
    }
  });

  // ─────────────────────────────────────────────
  // VERSION OMEN — Reference / Custom toggle
  // ─────────────────────────────────────────────
  $(document).on('click', '.ver-tog', function () {
    $(this).closest('.toggle-group').find('.ver-tog').removeClass('active');
    $(this).addClass('active');
    const $ctrl = $(this).closest('.fg-ctrl');
    const isRef = $(this).hasClass('ver-ref');
    $ctrl.find('.ref-content').toggle(isRef);
    $ctrl.find('.cus-content').toggle(!isRef);
    // Export enabled on Reference, Browse enabled on Custom
    const $export = $ctrl.find('[data-ver-action="export"]');
    const $browse = $ctrl.find('[data-ver-action="browse"]');
    $export.prop('disabled', !isRef).css({
      opacity: isRef ? '' : '.35',
      cursor: isRef ? '' : 'not-allowed'
    });
    $browse.prop('disabled', isRef).css({
      opacity: isRef ? '.35' : '',
      cursor: isRef ? 'not-allowed' : ''
    });
  });

  // ─────────────────────────────────────────────
  // PERIOD CHECKBOX → enable / disable sa ligne
  // ─────────────────────────────────────────────
  $(document).on('change', '.chk-period', function () {
    const checked = $(this).is(':checked');
    const $grp = $(this).closest('.period-line').find('.period-group');
    $grp.toggleClass('disabled', !checked);
    if (checked) {
      // Sync état months-inp avec le bouton actif (data-period="custom" → activé)
      const isCustom = $grp.find('.period-btn.active').data('period') === 'custom';
      $grp.find('.months-inp').prop('disabled', !isCustom);
    } else {
      $grp.find('.months-inp').prop('disabled', true);
    }
  });

  // ─────────────────────────────────────────────
  // SCENARIOS "ALL" CHECKBOX — sync bidirectionnel
  // ─────────────────────────────────────────────
  $(document).on('change', '.chk-all', function () {
    var checked = $(this).is(':checked');
    $(this).closest('.job-view').find('.scen-table input[type=checkbox]').prop('checked', checked);
  });

  // Quand un scénario individuel change → sync le "all"
  $(document).on('change', '.scen-table input[type=checkbox]', function () {
    var $view = $(this).closest('.job-view');
    var $rows = $view.find('.scen-table input[type=checkbox]');
    var allChecked = $rows.length === $rows.filter(':checked').length;
    $view.find('.chk-all').prop('checked', allChecked);
  });

  // ─────────────────────────────────────────────
  // CONTRÔLES SAVINGS — réactivité des champs
  // ─────────────────────────────────────────────

  // Name → libellé du tab
  $(document).on('input', '.job-view [name="jobName"]', function () {
    var $view = $(this).closest('.job-view');
    var id = $view.attr('id').replace('view-', '');
    var name = $(this).val().trim();
    $('.sidebar-tab[data-job="' + id + '"] .tab-label')
      .text(name || (STX.get('job.' + id) || {}).label || id);
  });

  function syncBrowseButtons($view) {
    var hasEnv = ($view.find('[name="environment"]').val() || '').trim() !== '';
    $view.find('.btn-browse-env')
      .prop('disabled', !hasEnv)
      .css({
        opacity: hasEnv ? '' : '.35',
        cursor: hasEnv ? '' : 'not-allowed'
      });
  }

  // Normalise la valeur Environment : retire la racine POC → clé dans le _tree
  function envToApiPath(val) {
    var norm = (val || '').replace(/\\/g, '/').replace(/\/+$/, '');
    var root = API.getRoot().replace(/\\/g, '/').replace(/\/+$/, '');
    if (root && norm.toLowerCase().indexOf(root.toLowerCase()) === 0) {
      return norm.slice(root.length).replace(/^\/+/, '');
    }
    return norm.replace(/^\/+|\/+$/g, '');
  }

  // Environment → inputs + scénarios au blur
  function _resetEnvData($view) {
    $view.find('[name="inputs"]').find('option:not(:first)').remove().end().val('');
    $view.find('.scen-table tbody').empty();
  }

  function _loadEnvData($view) {
    var envPath = envToApiPath($view.find('[name="environment"]').val());
    if (!envPath) { _resetEnvData($view); return; }

    // Inputs : dossiers de <env>/input
    API.exploreDir(envPath + '/input').then(function (node) {
      var $sel = $view.find('[name="inputs"]');
      var cur = $sel.val();
      $sel.find('option:not(:first)').remove();
      (node.folders || []).forEach(function (s) {
        $sel.append('<option>' + s + '</option>');
      });
      if (cur) $sel.val(cur);
    });

    // Scénarios : depuis <env>/scenario
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
  }

  $(document).on('input', '.job-view [name="environment"]', function () {
    syncBrowseButtons($(this).closest('.job-view'));
  });
  $(document).on('blur', '.job-view [name="environment"]', function () {
    var $view = $(this).closest('.job-view');
    syncBrowseButtons($view);
    _loadEnvData($view);
  });

  // Version Omen : changement de modèle → reset le select version depuis le cache
  $(document).on('change', '.job-view .ref-content [name="model"]', function () {
    var $view = $(this).closest('.job-view');
    var id = $view.attr('id').replace('view-', '');
    var type = (STX.get('job.' + id) || {}).type;
    var cacheKey = 'initCache.' + type;
    var cached = STX.get(cacheKey);
    if (!cached) return;
    var modelName = $(this).val();
    var entry = null;
    (cached.data.models || []).forEach(function (m) {
      if (m.model === modelName) entry = m;
    });
    if (entry) fillVersionSelect($view, entry.versions);
  });

  // ─────────────────────────────────────────────
  // VALIDATION
  // ─────────────────────────────────────────────
  function validateOmenBase($v, name) {
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
  }

  function validateSavings($v, name) {
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

  function validateNonLife($v, name) {
    var errs = validateOmenBase($v, name);
    var period = parseInt($v.find('[name="period"]').val(), 10);
    if (!period || period <= 0)
      errs.push(name + ' : Period must be a positive number of years');
    return errs;
  }

  function validateRiskLife($v, name) {
    var errs = validateOmenBase($v, name);
    var isAuto = $v.find('[name="autoIterations"]').is(':checked');
    if (!isAuto) {
      var iter = ($v.find('[name="iterations"]').val() || '').trim();
      if (!iter)
        errs.push(name + ' : Iterations is required (e.g. 1-1)');
    }
    var period = parseInt($v.find('[name="period"]').val(), 10);
    if (!period || period <= 0)
      errs.push(name + ' : Period must be a positive number of months');
    var hasScen = $v.find('.scen-table tbody input[type="checkbox"]:checked').length > 0;
    if (!hasScen)
      errs.push(name + ' : you have to select at least one scenario');
    return errs;
  }

  function validateRiskLifeKp($v, name) {
    var errs = validateOmenBase($v, name);
    var period = parseInt($v.find('[name="period"]').val(), 10);
    if (!period || period <= 0)
      errs.push(name + ' : Period must be a positive number of months');
    var hasScen = $v.find('.scen-table tbody input[type="checkbox"]:checked').length > 0;
    if (!hasScen)
      errs.push(name + ' : you have to select at least one scenario');
    return errs;
  }

  function validateTdr($v, name) {
    var errs = validateOmenBase($v, name);
    var period = parseInt($v.find('[name="period"]').val(), 10);
    if (!period || period <= 0)
      errs.push(name + ' : Period must be a positive number of months');
    return errs;
  }

  function validateBrd($v, name) {
    var errs = validateOmenBase($v, name);
    var dur = parseInt($v.find('[name="projectionDuration"]').val(), 10);
    if (!dur || dur <= 0)
      errs.push(name + ' : Projection Duration must be a positive number of years');
    var hasScen = $v.find('.scen-table tbody input[type="checkbox"]:checked').length > 0;
    if (!hasScen)
      errs.push(name + ' : you have to select at least one scenario');
    return errs;
  }

  function validateCustomInput($v, name) {
    var errs = [];
    var actions = ($v.find('[name="actionsFolder"]').val() || '').trim();
    var inputs  = ($v.find('[name="inputsFolder"]').val() || '').trim();
    if (!actions) errs.push(name + ' : you must select an action folder');
    if (!inputs)  errs.push(name + ' : you must select an inputs folder');
    return errs;
  }

  function validateScenarioTransformator($v, name) {
    var errs = [];
    var env = ($v.find('[name="environment"]').val() || '').trim();
    if (!env) errs.push(name + ' : you must select an environment');
    return errs;
  }

  var _validators = {
    savings:              validateSavings,
    brd:                  validateBrd,
    tdr:                  validateTdr,
    nonlife:              validateNonLife,
    risklife:             validateRiskLife,
    risklifekp:           validateRiskLifeKp,
    custominput:          validateCustomInput,
    scenariotransformator: validateScenarioTransformator,
  };

  // ─────────────────────────────────────────────
  // CONTEXT MENU
  // ─────────────────────────────────────────────
  var _ctxClipboard = null; // { type, data }
  var _ctxMenu = null;

  function _isFormValid($view) {
    var id = $view.attr('id').replace('view-', '');
    var type = (STX.get('job.' + id) || {}).type;
    var validate = _validators[type];
    if (!validate) return false;
    var name = ($view.find('.field-name').val() || '').trim() || 'job';
    return validate($view, name).length === 0;
  }

  function _hideCtxMenu() {
    if (_ctxMenu) { _ctxMenu.remove(); _ctxMenu = null; }
  }

  var _CTX_ICONS = {
    'Refresh':            '<svg viewBox="0 0 14 14" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M12 7A5 5 0 1 1 9.5 2.8"/><polyline points="12 1 12 4.5 8.5 4.5"/></svg>',
    'Copy Settings':      '<svg viewBox="0 0 14 14" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><rect x="4.5" y="1" width="8" height="9" rx="1.2"/><rect x="1" y="4" width="8" height="9" rx="1.2"/></svg>',
    'Paste Settings':     '<svg viewBox="0 0 14 14" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><rect x="1" y="3" width="10" height="10" rx="1.2"/><path d="M4 3V2a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v1"/><line x1="4" y1="7" x2="8" y2="7"/><line x1="4" y1="9.5" x2="7" y2="9.5"/></svg>',
    'Copy to clipboard':  '<svg viewBox="0 0 14 14" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M9 1H3a1 1 0 0 0-1 1v9"/><rect x="4" y="3" width="8" height="10" rx="1.2"/></svg>',
    'Open folder':        '<svg viewBox="0 0 14 14" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M1 3.5A1 1 0 0 1 2 2.5h3l1.5 1.5H12a1 1 0 0 1 1 1V11a1 1 0 0 1-1 1H2a1 1 0 0 1-1-1V3.5z"/></svg>',
    'Cancel job':         '<svg viewBox="0 0 14 14" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><circle cx="7" cy="7" r="5.5"/><line x1="4.5" y1="4.5" x2="9.5" y2="9.5"/><line x1="9.5" y1="4.5" x2="4.5" y2="9.5"/></svg>',
    'Requeue job':        '<svg viewBox="0 0 14 14" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="1 4 1 1 4 1"/><path d="M1 1l3.5 3.5A5.5 5.5 0 1 1 2.5 9"/></svg>',
  };

  function _showCtxMenu(items, x, y) {
    _hideCtxMenu();
    var $m = $('<div class="ctx-menu"></div>');
    items.forEach(function (item) {
      var icon = _CTX_ICONS[item.label] || '';
      var $i = $('<div class="ctx-item"></div>').html(icon + '<span>' + item.label + '</span>');
      $i.on('click', function () { _hideCtxMenu(); item.action(); });
      $m.append($i);
    });
    $m.css({ left: x, top: y });
    $('body').append($m);
    _ctxMenu = $m;
  }

  $(document).on('contextmenu', '.job-view', function (e) {
    var $view = $(this);
    var id = $view.attr('id').replace('view-', '');
    var type = (STX.get('job.' + id) || {}).type;
    if (!type || !_validators[type]) return;

    var valid = _isFormValid($view);
    var hasClip = !!(_ctxClipboard && _ctxClipboard.type === type);

    // Blank + no matching clipboard → no menu
    if (!valid && !hasClip) return;

    e.preventDefault();

    var items = [];

    // Refresh — always present when menu is shown
    items.push({
      label: 'Refresh',
      action: function () {
        var env = $view.find('[name="environment"]').val();
        if (!env) return;
        API.get('/api/JobManager/refreshinputs?environment=' + encodeURIComponent(env))
          .then(function (data) {
            var $sel = $view.find('[name="inputs"]');
            var cur = $sel.val();
            $sel.find('option:not(:first)').remove();
            (data.inputs || []).forEach(function (s) {
              $sel.append('<option>' + s + '</option>');
            });
            if (cur) $sel.val(cur);
          });
      }
    });

    if (valid) {
      items.push({
        label: 'Copy Settings',
        action: function () {
          var data = STX.get('job.' + id);
          _ctxClipboard = { type: type, data: data };
          try { navigator.clipboard.writeText(JSON.stringify(data, null, 2)); } catch (ex) {}
        }
      });
    }

    if (hasClip) {
      items.push({
        label: 'Paste Settings',
        action: function () {
          var data = _ctxClipboard.data;
          restoreView($view, data);
          syncBrowseButtons($view);

          // Period checkboxes: fire change so .period-group toggling disabled class
          $view.find('.chk-period').trigger('change');

          // Advanced Options: save adv to STX + restore panel body (same as Last button)
          if (data.adv) {
            var cur = STX.get('job.' + id) || {};
            STX.set('job.' + id, $.extend(cur, { adv: data.adv }));
            restoreView($('#sidePanelBody'), data.adv);
          }

          // If Reference mode: trigger model change to reload correct versions, then re-apply version
          if (data.model) {
            $view.find('.ref-content [name="model"]').trigger('change');
            if (data.version) $view.find('.ref-content [name="version"]').val(data.version);
          }

          // Load env data with post-load restore of inputs value
          var envPath = envToApiPath($view.find('[name="environment"]').val());
          if (!envPath) { saveJobView($view); return; }

          API.exploreDir(envPath + '/input').then(function (node) {
            var $sel = $view.find('[name="inputs"]');
            $sel.find('option:not(:first)').remove();
            (node.folders || []).forEach(function (s) {
              $sel.append('<option>' + s + '</option>');
            });
            if (data.inputs) $sel.val(data.inputs);
            saveJobView($view);
          });

          // Reload scenarios then re-apply selections
          if ($view.find('.scen-table').length) {
            var _isRL = (type === 'risklife' || type === 'risklifekp' || type === 'brd');
            API.exploreDir(envPath + '/scenario').then(function (node) {
              if (!node.scenarios) return;
              if (_isRL) rebuildRLScenarios($view, node.scenarios);
              else rebuildScenarios($view, node.scenarios);
              if (data.scenarios) {
                $view.find('.scen-table tbody tr').each(function () {
                  var num = $(this).find('td').eq(1).text().trim();
                  $(this).find('input[type=checkbox]').prop('checked', data.scenarios.indexOf(num) !== -1);
                });
              }
            });
          }
        }
      });
    }

    _showCtxMenu(items, e.clientX, e.clientY);
  });

  $(document).on('click', function (e) {
    if (_ctxMenu && !$(e.target).closest('.ctx-menu').length) _hideCtxMenu();
  });

  $(document).on('keydown', function (e) {
    if (e.key === 'Escape') _hideCtxMenu();
  });

  // ─────────────────────────────────────────────
  // CONTEXT MENU — MONITORING ROWS
  // ─────────────────────────────────────────────

  function _monCtxJobItems($tr, jobId, state, env, jobData) {
    var items = [];

    // Copy to clipboard — copies the environment path
    items.push({
      label: 'Copy to clipboard',
      action: function () {
        try { navigator.clipboard.writeText(env); } catch (ex) {}
      }
    });

    // Copy Settings — only if job has settings payload
    if (jobData && jobData.settings) {
      items.push({
        label: 'Copy Settings',
        action: function () {
          _ctxClipboard = { type: jobData.settings.type, data: jobData.settings };
          try { navigator.clipboard.writeText(JSON.stringify(jobData.settings, null, 2)); } catch (ex) {}
        }
      });
    }

    // Open folder
    items.push({
      label: 'Open folder',
      action: function () {
        if (env) window.open('file:///' + env.replace(/\\/g, '/'));
      }
    });

    var isTerminal = (state === 'done' || state === 'cancelled' || state === 'error');

    // Cancel job — active states only
    if (!isTerminal) {
      items.push({
        label: 'Cancel job',
        action: function () {
          API.post('/api/JobGrid/cancel/' + jobId).then(function () {
            $tr.find('.state-dot').removeClass().addClass('state-dot cancelled');
            $tr.attr('data-state', 'cancelled');
            openConsole();
            cLog('Job ' + jobId + ' — annulation demandée.', 'warn');
          });
        }
      });
    }

    // Requeue job — terminal states only (Done / Cancelled / Error)
    if (isTerminal) {
      items.push({
        label: 'Requeue job',
        action: function () {
          API.post('/api/JobGrid/requeue/' + jobId).then(function () {
            $tr.find('.state-dot').removeClass().addClass('state-dot pending');
            $tr.attr('data-state', 'pending');
            openConsole();
            cLog('Job ' + jobId + ' — remis en file d\'attente.', 'warn');
          });
        }
      });
    }

    return items;
  }

  // parentJob + childJob : full menu
  $(document).on('contextmenu', '#monitorBody .job-row, #monitorBody .child-row', function (e) {
    e.preventDefault();
    e.stopPropagation();
    var $tr = $(this);
    var jobId  = $tr.data('job-id') || $tr.data('child-id');
    var state  = ($tr.attr('data-state') || '').toLowerCase();
    var env    = $tr.attr('data-env') || '';
    var jobData = _monJobMap[jobId] || _monChildMap[jobId];
    var items = _monCtxJobItems($tr, jobId, state, env, jobData);
    if (items.length) _showCtxMenu(items, e.clientX, e.clientY);
  });

  // group + task : Open folder uniquement
  $(document).on('contextmenu', '#monitorBody .group-row, #monitorBody .task-row', function (e) {
    e.preventDefault();
    e.stopPropagation();
    var env = $(this).attr('data-env') || '';
    _showCtxMenu([{
      label: 'Open folder',
      action: function () {
        if (env) window.open('file:///' + env.replace(/\\/g, '/'));
      }
    }], e.clientX, e.clientY);
  });

  // ─────────────────────────────────────────────
  // SUBMIT
  // ─────────────────────────────────────────────
  $(document).on('click', '.btn-submit-job', function () {
    const $v = $(this).closest('.job-view');
    const $name = $v.find('.field-name');
    const name = ($name.val() || '').trim();

    if ($name.length && !name) {
      $name.addClass('is-invalid').focus();
      openConsole();
      cLog('Validation : le champ Name est requis.', 'error');
      return;
    }
    if ($name.length) $name.removeClass('is-invalid');

    var _id = $v.attr('id').replace('view-', '');
    var _jobData = STX.get('job.' + _id) || {};
    var _type = _jobData.type;
    var _displayName = name || JOB_LABELS[_type] || 'job';

    // Validation par type
    var validate = _validators[_type];
    if (validate) {
      var errors = validate($v, _displayName);
      if (errors.length) {
        openConsole();
        errors.forEach(function (e) {
          cLog(e, 'error');
        });
        return;
      }
    }

    // Lire l'adv depuis le DOM si le panel est ouvert (évite le délai du debounce saveAdvOptions)
    var _adv = ($('#sidePanel').hasClass('open') && $('#sidePanelTitle').text() === 'Advanced Options') ?
      serializeView($('#sidePanelBody')) :
      _jobData.adv;
    // Si advOptions non coché → adv null
    if (!$v.find('.adv-chk').is(':checked')) _adv = null;

    if (_type) STX.set('lastSubmit.' + _type, $.extend({}, serializeView($v), {
      adv: _adv
    }));

    var jobPayload = STX.get('job.' + _id);
    console.log('[STYX] Job payload:', jobPayload);
    openConsole();
    cLog('Job soumis : ' + _displayName);
    cLog('Connexion à l\'environnement en cours…', 'warn');
    setTimeout(() => cLog('Job démarré — 0% complété'), 900);
    setTimeout(() => cLog('Progression : 25%'), 2200);
    setTimeout(() => cLog('Progression : 60%'), 4000);
    setTimeout(() => cLog('Progression : 100% — Job terminé avec succès.'), 6500);
  });

  // ─────────────────────────────────────────────
  // MONITORING — API
  // ─────────────────────────────────────────────
  function apiGetJobs() {
    return API.get('/api/JobGrid/jobs');
  }

  function apiGetJobChildren(jobId) {
    return API.get('/api/JobGrid/jobs/children?jobId=' + jobId);
  }

  function apiGetJobTasks(jobId) {
    return API.get('/api/JobGrid/jobs/' + jobId + '/tasks');
  }

  // ─────────────────────────────────────────────
  // MONITORING — Render helpers
  // ─────────────────────────────────────────────
  // Formate une date ISO 8601 → "MM-DD HH:mm" ou "HH:mm:ss" selon la longueur
  function fmtDate(iso) {
    if (!iso) return '';
    var d = new Date(iso);
    if (isNaN(d)) return iso; // fallback : afficher brut
    var mm = String(d.getMonth() + 1).padStart(2, '0');
    var dd = String(d.getDate()).padStart(2, '0');
    var hh = String(d.getHours()).padStart(2, '0');
    var min = String(d.getMinutes()).padStart(2, '0');
    var ss = String(d.getSeconds()).padStart(2, '0');
    // Si secondes non nulles (timestamp précis) → HH:mm:ss, sinon MM-DD HH:mm
    return d.getSeconds() ? hh + ':' + min + ':' + ss : mm + '-' + dd + ' ' + hh + ':' + min;
  }

  function stateClass(state) {
    var s = String(state).toLowerCase();
    if (s === 'done' || s === 'finished' || s === '2') return 'done';
    if (s === 'running' || s === '1') return 'running';
    if (s === 'error' || s === 'failed' || s === '3') return 'error';
    if (s === 'cancelled' || s === 'canceled' || s === '4') return 'cancelled';
    return 'pending'; // queued, submitted, pending
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
    var rows = children.map(function (c) {
      var env = (c.environment || envPath || '').replace(/"/g, '&quot;');
      _monChildMap[c.id] = c;
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
    var parentEnv = ((_monJobMap[jobId] || {}).environment || '');
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

  // ─────────────────────────────────────────────
  // MONITORING — Load & Filters
  // ─────────────────────────────────────────────
  var _monJobMap   = {}; // jobId   → job object  (parentJob / childJob)
  var _monChildMap = {}; // childId → child object

  function loadMonitoringJobs() {
    var $body = $('#monitorBody');
    $body.html('<tr><td colspan="10" style="text-align:center;padding:20px;color:var(--text-faint);font-family:\'DM Mono\';font-size:.65rem">Chargement…</td></tr>');
    apiGetJobs().then(function (resp) {
      if (!resp.jobs || !resp.jobs.length) {
        $body.html('<tr><td colspan="10" style="text-align:center;padding:20px;color:var(--text-faint);font-family:\'DM Mono\';font-size:.65rem">Aucun job.</td></tr>');
        return;
      }
      _monJobMap = {};
      resp.jobs.forEach(function (j) { _monJobMap[j.id] = j; });
      $body.html(resp.jobs.map(buildJobRow).join(''));
      applyMonitorFilters();
    });
  }

  function applyMonitorFilters() {
    var id = $('.mf-id').val().toLowerCase();
    var name = $('.mf-name').val().toLowerCase();
    var prio = $('.mf-priority').val().toLowerCase();
    var acc = $('.mf-account').val().toLowerCase();
    var fullView = $('.mf-fullview').is(':checked');
    var connectedUser = $('.user-name').text().trim();
    var activeStates = [];
    $('.mf-state-btn.active').each(function () { activeStates.push($(this).data('state')); });
    $('#monitorBody .job-row').each(function () {
      var $tr = $(this);
      var jid = String($tr.data('job-id'));
      var nameText = ($tr.attr('data-name') || '').toLowerCase();
      var accountText = ($tr.data('account') || '').toLowerCase();
      var prioText = ($tr.attr('data-priority') || '').toLowerCase();
      var rowState = $tr.attr('data-state') || '';
      var show = (fullView || accountText.indexOf(connectedUser.toLowerCase()) !== -1) &&
        (!id || jid.indexOf(id) !== -1) &&
        (!name || nameText.indexOf(name) !== -1) &&
        (!prio || prioText.indexOf(prio) !== -1) &&
        (!acc || accountText.indexOf(acc) !== -1) &&
        (!activeStates.length || activeStates.indexOf(rowState) !== -1);
      $tr.toggle(show);
      $('#job-expand-' + $tr.data('job-id')).toggle(show && $tr.hasClass('is-expanded'));
    });
    STX.merge('monitoring', {
      filters: {
        id: id,
        name: name,
        priority: prio,
        account: acc
      }
    });
  }

  $(document).on('input', '.mf-id, .mf-name, .mf-priority, .mf-account', applyMonitorFilters);
  $(document).on('change', '.mf-fullview', applyMonitorFilters);
  $(document).on('click', '.mf-state-btn', function () {
    $(this).toggleClass('active');
    applyMonitorFilters();
  });

  // ─────────────────────────────────────────────
  // MONITORING — Expand/collapse job row
  // ─────────────────────────────────────────────
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
      return;
    }

    // Fermer l'éventuel job déjà ouvert
    $('#monitorBody .job-row.is-expanded').each(function () {
      var $other = $(this);
      $other.removeClass('is-expanded');
      $other.find('> td .expand-icon').text('▶');
      $('#job-expand-' + $other.data('job-id')).hide();
    });

    $tr.addClass('is-expanded');
    $tr.find('> td .expand-icon').text('▼');
    $expandRow.show();

    if (!isExpanded && !$cnt.data('loaded')) {
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
          var env = (_monJobMap[jobId] || {}).environment || '';
          $cnt.html(buildTasksTable(resp.tasks, env) || '<div class="expand-empty">Aucune tâche disponible</div>');
        }).fail(function () {
          $cnt.html('<div class="expand-empty">Erreur de chargement</div>');
        });
      }
    }
  });

  // Expand/collapse group row → show children (Level 2 → Level 3)
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
  });

  // Expand/collapse child row → load tasks (Level 3 → Level 4)
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
    if (!expanded && !$cnt.data('loaded')) {
      $cnt.data('loaded', true);
      apiGetJobTasks(childId).then(function (resp) {
        var env = (_monChildMap[childId] || {}).environment || '';
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

  // ─────────────────────────────────────────────
  // FORM BUILDERS
  // ─────────────────────────────────────────────

  // ─────────────────────────────────────────────
  // ADVANCED OPTIONS BUILDERS (one per job type)
  // ─────────────────────────────────────────────

  // Options communes à tous les types
  function advCommon() {
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
  }

  // Sliding et Test Sliding : 2 checkboxes indépendants (data-grp distincts)
  function advSlidingRow() {
    return (
      '<div class="adv-row">' +
      '<button class="btn-toggle active" data-grp="sliding">Sliding</button>' +
      '<button class="btn-toggle"        data-grp="testSliding">Test Sliding</button>' +
      '</div>'
    );
  }

  function buildAdvSavings() {
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

  function buildAdvNonLife() {
    return '';
  }

  function buildAdvRiskLife() {
    return (
      advSlidingRow() +
      '<div class="adv-field">' +
      '<label class="adv-lbl">Job priority</label>' +
      '<select name="priority"><option>Automatic</option><option selected>Normal</option><option>High</option></select>' +
      '</div>'
    );
  }

  function buildAdvRiskLifeKp() {
    return (
      advSlidingRow() +
      '<div class="adv-field">' +
      '<label class="adv-lbl">Job priority</label>' +
      '<select name="priority"><option>Automatic</option><option selected>Normal</option><option>High</option></select>' +
      '</div>'
    );
  }

  function buildAdvTdr() {
    return '';
  }

  function buildAdvBrd() {
    return (
      '<div class="adv-field">' +
      '<label class="adv-lbl">Job priority</label>' +
      '<select name="priority"><option>Automatic</option><option selected>Normal</option><option>High</option></select>' +
      '</div>'
    );
  }

  // label: text affiché (ex: 'Deterministic', 'Stochastic', '' pour Pricer)
  // cls: classe CSS sur le checkbox pour identification (chk-det, chk-sto, chk-pricer)
  // cls ex: "chk-det" → préfixe "det" pour les noms de champs
  function periodLine(label, cls) {
    var p = cls.replace('chk-', ''); // "det" | "sto" | "pricer"
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
  }

  function scenariosBlock() {
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
  }

  function buildUfx(id) {
    return (
      '<div class="job-view" id="view-' + id + '">' +
      '<div class="form-header">' +
      '<div>' +
      '<div class="form-title">New UFX Job</div>' +
      '<div class="form-title-sub">Universal Format Exchange</div>' +
      '</div>' +
      '<div class="form-actions-col">' +
      '<div class="form-actions-row">' +
      '<button class="btn-secondary btn-help-job" type="button" title="How to use">?</button>' +
      '<button class="btn-submit btn-submit-job">Submit</button>' +
      '</div>' +
      '</div>' +
      '</div>' +
      '<div class="form-grid">' +
      '<div class="fg-lbl">Name:</div>' +
      '<div class="fg-ctrl"><input type="text" class="field-name" name="jobName" placeholder="Nom du job UFX"></div>' +
      '<div class="fg-lbl">Path:</div>' +
      '<div class="fg-ctrl">' +
      '<div class="f-row">' +
      '<input type="text" name="path" style="flex:1;min-width:0" placeholder="\\\\srv\\styx\\recette\\...">' +
      '<button class="btn-secondary btn-browse btn-browse-ufx" type="button">Browse</button>' +
      '<label style="display:flex;align-items:center;gap:6px;font-family:\'DM Mono\';font-size:.65rem;color:var(--text-dim);cursor:pointer;white-space:nowrap">' +
      '<input type="checkbox" name="isFolder"> Is Folder' +
      '</label>' +
      '</div>' +
      '</div>' +
      '</div>' +
      '</div>'
    );
  }

  function buildCustomInput(id) {
    return (
      '<div class="job-view" id="view-' + id + '">' +
      '<div class="form-header">' +
      '<div>' +
      '<div class="form-title">New Custom Input Job</div>' +
      '<div class="form-title-sub">Input to Custom transformation</div>' +
      '</div>' +
      '<div class="form-actions-col">' +
      '<div class="form-actions-row">' +
      '<button class="btn-secondary btn-help-job" type="button" title="How to use">?</button>' +
      '<button class="btn-submit btn-submit-job">Submit</button>' +
      '</div>' +
      '</div>' +
      '</div>' +
      '<div class="form-grid">' +
      '<div class="fg-lbl">Input to Custom:</div>' +
      '<div class="fg-ctrl">' +
      '<div class="f-row">' +
      '<input type="text" name="inputsFolder" style="flex:1;min-width:0" placeholder="\\\\srv\\styx\\...">' +
      '<button class="btn-secondary btn-browse btn-browse-folder" type="button">Browse</button>' +
      '</div>' +
      '</div>' +
      '<div class="fg-lbl">Custom Actions:</div>' +
      '<div class="fg-ctrl">' +
      '<div class="f-row">' +
      '<input type="text" name="actionsFolder" style="flex:1;min-width:0" placeholder="\\\\srv\\styx\\...">' +
      '<button class="btn-secondary btn-browse btn-browse-folder" type="button">Browse</button>' +
      '</div>' +
      '</div>' +
      '</div>' +
      '</div>'
    );
  }

  function buildScenarioTransformator(id) {
    var radStyle = 'display:flex;align-items:center;gap:6px;font-family:\'DM Mono\';font-size:.65rem;color:var(--text-dim);cursor:pointer;white-space:nowrap';
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
      '<label style="' + radStyle + '"><input type="checkbox" name="split"> Split</label>' +
      '</div>' +

      '</div>' +
      '</div>'
    );
  }

  // ── Builder commun à tous les jobs Omen ──────
  // cfg : { label, code, extraRows }  — inputs/versions/omenTypes viennent de l'API
  function buildOmenForm(id, cfg) {
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
  }

  // ── Init Savings depuis l'API ─────────────────
  // Applique les valeurs par défaut d'une period-line (det / sto / pricer)
  function applyPeriodLineDefaults($view, prefix, enabled, months, range) {
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
  }

  // Peuple select[name="version"] avec les versions d'un modèle
  function fillVersionSelect($view, versions) {
    var $v = $view.find('.ref-content [name="version"]');
    $v.empty();
    (versions || []).forEach(function (v) {
      $v.append('<option>' + v + '</option>');
    });
  }

  // Reconstruit le tbody des scénarios depuis un array ScenarioMoSesDto
  function rebuildScenarios($view, scenarios) {
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
  }

  // Retourne une promise qui résout avec les données init (cache 24h dans STX)
  function getSavingsInit() {
    var cached = STX.get('initCache.savings');
    if (cached && (Date.now() - cached.ts) < 86400000) {
      return $.Deferred().resolve(cached.data).promise();
    }
    return API.get('/api/JobManager/savings/init').then(function (init) {
      STX.set('initCache.savings', {
        data: init,
        ts: Date.now()
      });
      return init;
    });
  }

  // Appelé à l'ouverture d'un job Savings — init depuis l'API (ou cache)
  function initSavingsView($view) {
    getSavingsInit().then(function (init) {

      // Nom par défaut
      if (init.defaultName) $view.find('[name="jobName"]').val(init.defaultName);

      // Version Omen : select[name="model"] → noms des modèles
      //                select[name="version"] → versions du premier modèle
      if (init.models && init.models.length) {
        var $modelSel = $view.find('.ref-content [name="model"]');
        $modelSel.empty();
        init.models.forEach(function (m) {
          $modelSel.append('<option>' + m.model + '</option>');
        });
        fillVersionSelect($view, init.models[0].versions);
      }

      // Job Omen Types + valeur par défaut
      if (init.jobOmenTypes && init.jobOmenTypes.length) {
        var $omenSel = $view.find('[name="omenType"]');
        $omenSel.empty();
        init.jobOmenTypes.forEach(function (t) {
          $omenSel.append('<option>' + t + '</option>');
        });
        if (init.defaultJobType) $omenSel.val(init.defaultJobType);
      }

      // Guaranteed Floor
      $view.find('[name="guaranteedFloor"]').prop('checked', !!init.defaultIsGuaranteedFloorChecked);

      // Period lines
      applyPeriodLineDefaults($view, 'det', init.detChecked, init.defaultDetPeriodSim, init.defaultDetIterations);
      applyPeriodLineDefaults($view, 'sto', init.stoChecked, init.defaultStoPeriodSim, init.defaultStoIterations);
      applyPeriodLineDefaults($view, 'pricer', init.defaultIsTrdPricerEnabled, init.defaultPricerPeriodSim, init.defaultPricerIterations);

      // Persister l'état initialisé
      saveJobView($view);
    });
  }

  function getBrdInit() {
    var cached = STX.get('initCache.brd');
    if (cached && (Date.now() - cached.ts) < 86400000) {
      return $.Deferred().resolve(cached.data).promise();
    }
    return API.get('/api/JobManager/brd/init').then(function (init) {
      STX.set('initCache.brd', { data: init, ts: Date.now() });
      return init;
    });
  }

  function initBrdView($view) {
    getBrdInit().then(function (init) {
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

  function getNonLifeInit() {
    var cached = STX.get('initCache.nonlife');
    if (cached && (Date.now() - cached.ts) < 86400000) {
      return $.Deferred().resolve(cached.data).promise();
    }
    return API.get('/api/JobManager/nonlife/init').then(function (init) {
      STX.set('initCache.nonlife', { data: init, ts: Date.now() });
      return init;
    });
  }

  function initNonLifeView($view) {
    getNonLifeInit().then(function (init) {
      if (init.defaultName) $view.find('[name="jobName"]').val(init.defaultName);
      if (init.defaultPeriod != null) $view.find('[name="period"]').val(init.defaultPeriod);
      if (init.models && init.models.length) {
        var $modelSel = $view.find('.ref-content [name="model"]');
        $modelSel.empty();
        init.models.forEach(function (m) {
          $modelSel.append('<option>' + m.model + '</option>');
        });
        fillVersionSelect($view, init.models[0].versions);
      }
      saveJobView($view);
    });
  }

  function getTdrInit() {
    var cached = STX.get('initCache.tdr');
    if (cached && (Date.now() - cached.ts) < 86400000) {
      return $.Deferred().resolve(cached.data).promise();
    }
    return API.get('/api/JobManager/tdr/init').then(function (init) {
      STX.set('initCache.tdr', { data: init, ts: Date.now() });
      return init;
    });
  }

  function initTdrView($view) {
    getTdrInit().then(function (init) {
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

  function getRiskLifeInit() {
    var cached = STX.get('initCache.risklife');
    if (cached && (Date.now() - cached.ts) < 86400000) {
      return $.Deferred().resolve(cached.data).promise();
    }
    return API.get('/api/JobManager/risklife/init').then(function (init) {
      STX.set('initCache.risklife', { data: init, ts: Date.now() });
      return init;
    });
  }

  function rebuildRLScenarios($view, scenarios) {
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
  }

  function initRiskLifeView($view) {
    getRiskLifeInit().then(function (init) {
      if (init.defaultName) $view.find('[name="jobName"]').val(init.defaultName);
      if (init.defaultIterations) $view.find('[name="iterations"]').val(init.defaultIterations);
      if (init.defaultPeriod != null) $view.find('[name="period"]').val(init.defaultPeriod);
      var autoOn = !!init.defaultAutoIterations;
      $view.find('[name="autoIterations"]').prop('checked', autoOn);
      $view.find('[name="iterations"]').prop('disabled', autoOn);
      if (init.models && init.models.length) {
        var $modelSel = $view.find('.ref-content [name="model"]');
        $modelSel.empty();
        init.models.forEach(function (m) {
          $modelSel.append('<option>' + m.model + '</option>');
        });
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

  // S2 Select / S2 Deselect
  function getRiskLifeKpInit() {
    var cached = STX.get('initCache.risklifekp');
    if (cached && (Date.now() - cached.ts) < 86400000) {
      return $.Deferred().resolve(cached.data).promise();
    }
    return API.get('/api/JobManager/risklifekp/init').then(function (init) {
      STX.set('initCache.risklifekp', { data: init, ts: Date.now() });
      return init;
    });
  }

  function initRiskLifeKpView($view) {
    getRiskLifeKpInit().then(function (init) {
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

  function getScenarioTransformatorInit() {
    var cached = STX.get('initCache.scenariotransformator');
    if (cached && (Date.now() - cached.ts) < 86400000) {
      return $.Deferred().resolve(cached.data).promise();
    }
    return API.get('/api/JobManager/scenarioTransfo/init').then(function (init) {
      STX.set('initCache.scenariotransformator', { data: init, ts: Date.now() });
      return init;
    });
  }

  function initScenarioTransformatorView($view) {
    getScenarioTransformatorInit().then(function (init) {
      var radStyle = 'display:flex;align-items:center;gap:6px;font-family:\'DM Mono\';font-size:.65rem;color:var(--text-dim);cursor:pointer;white-space:nowrap';

      if (init.modelTypes && init.modelTypes.length) {
        var $mt = $view.find('[data-radio-group="modelType"]');
        $mt.empty();
        init.modelTypes.forEach(function (m) {
          var chk = m.value === init.defaultModelType ? ' checked' : '';
          $mt.append('<label style="' + radStyle + '"><input type="radio" name="modelType" value="' + m.value + '"' + chk + '> ' + m.label + '</label>');
        });
      }

      if (init.periodes && init.periodes.length) {
        var $p = $view.find('[data-radio-group="periode"]');
        $p.empty();
        init.periodes.forEach(function (p) {
          var chk = p.value === init.defaultPeriode ? ' checked' : '';
          $p.append('<label style="' + radStyle + '"><input type="radio" name="periode" value="' + p.value + '"' + chk + '> ' + p.label + '</label>');
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

  $(document).on('change', '[name="autoIterations"]', function () {
    $(this).closest('.job-view').find('[name="iterations"]').prop('disabled', $(this).is(':checked'));
  });

  $(document).on('click', '.rl-s2-select', function () {
    $(this).closest('.fg-ctrl').find('.scen-table tbody input[type=checkbox]').prop('checked', true);
  });
  $(document).on('click', '.rl-s2-deselect', function () {
    $(this).closest('.fg-ctrl').find('.scen-table tbody input[type=checkbox]').prop('checked', false);
  });

  function buildOmenSavings(id) {
    return buildOmenForm(id, {
      label: 'Savings',
      code: 'S',
      extraRows: '<div class="fg-lbl">Iteration Range / Period:</div>' +
        '<div class="fg-ctrl">' +
        periodLine('Deterministic', 'chk-det') +
        periodLine('Stochastic', 'chk-sto') +
        '</div>' +

        '<div class="fg-lbl">Guaranteed Floor:</div>' +
        '<div class="fg-ctrl">' +
        '<input type="checkbox" name="guaranteedFloor">' +
        '</div>' +

        '<div class="fg-lbl">Pricer derivatives:</div>' +
        '<div class="fg-ctrl">' +
        periodLine('', 'chk-pricer') +
        '</div>' +

        '<div class="fg-lbl">Job Omen Type:</div>' +
        '<div class="fg-ctrl">' +
        '<select name="omenType"></select>' +
        '</div>' +

        '<div class="fg-lbl nb">Scenarios:</div>' +
        '<div class="fg-ctrl nb">' + scenariosBlock() + '</div>',
    });
  }

  function buildOmenNonLife(id) {
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

  function rlScenarioBlock() {
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
  }

  function buildOmenRiskLife(id) {
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
        '<div class="fg-ctrl">' +
        '<select name="omenType"></select>' +
        '</div>' +

        '<div class="fg-lbl nb">Scenarios:</div>' +
        '<div class="fg-ctrl nb">' + rlScenarioBlock() + '</div>',
    });
  }

  function buildOmenRiskLifeKp(id) {
    return buildOmenForm(id, {
      label: 'Risk Life KP',
      code: 'KP',
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
        '<div class="fg-ctrl">' +
        '<select name="omenType"></select>' +
        '</div>' +

        '<div class="fg-lbl nb">Scenarios:</div>' +
        '<div class="fg-ctrl nb">' + rlScenarioBlock() + '</div>',
    });
  }

  function buildOmenTdr(id) {
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

  function buildOmenBrd(id) {
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

  // ── Tools ──────────────────────────────────────
  function buildTool(id, type) {
    var info = {
      'tool-compare': ['Compare Jobs', 'Comparaison de résultats OMEN'],
      'tool-extract': ['Data Extract', 'Extraction de données tabulaires'],
      'tool-report': ['Batch Report', 'Génération de rapports actuariels'],
    };
    var arr = info[type] || ['Tool', ''];
    var title = arr[0],
      sub = arr[1];
    return (
      '<div class="job-view" id="view-' + id + '">' +
      '<div class="form-header">' +
      '<div>' +
      '<div class="form-title">' + title + '</div>' +
      '<div class="form-title-sub">' + sub + '</div>' +
      '</div>' +
      '<div class="form-actions-col">' +
      '<div class="form-actions-row">' +
      '<button class="btn-submit btn-submit-job">Run</button>' +
      '<label class="adv-chk-label"><input type="checkbox" class="adv-chk" name="advOptions"> Advanced Options</label>' +
      '</div>' +
      '</div>' +
      '</div>' +
      '<div class="form-grid">' +
      '<div class="fg-lbl">Name:</div>' +
      '<div class="fg-ctrl"><input type="text" class="field-name" name="jobName" placeholder="' + title + ' job"></div>' +
      '<div class="fg-lbl">Source:</div>' +
      '<div class="fg-ctrl">' +
      '<div class="f-row">' +
      '<input type="text" name="source" style="flex:1;min-width:0" placeholder="\\\\srv\\styx\\recette\\...">' +
      '<button class="btn-secondary btn-browse">Browse</button>' +
      '</div>' +
      '</div>' +
      '<div class="fg-lbl">Output:</div>' +
      '<div class="fg-ctrl">' +
      '<div class="f-row">' +
      '<input type="text" name="output" style="flex:1;min-width:0" placeholder="\\\\srv\\styx\\recette\\output\\...">' +
      '<button class="btn-secondary btn-browse">Browse</button>' +
      '</div>' +
      '</div>' +
      '<div class="fg-lbl">Format:</div>' +
      '<div class="fg-ctrl">' +
      '<select name="format"><option>Excel</option><option>CSV</option><option>JSON</option></select>' +
      '</div>' +
      '</div>' +
      '</div>'
    );
  }

  function buildAdvTool() {
    return advCommon();
  }

  function buildMonitoring() {
    return (
      '<div class="job-view" id="view-monitoring">' +
      '<div class="monitor-filters">' +
      '<input type="text" class="mf-id f-input-sm"       placeholder="Job Id"       style="width:80px">' +
      '<input type="text" class="mf-name f-input-sm"     placeholder="Job Name"     style="width:180px">' +
      '<input type="text" class="mf-account f-input-sm"  placeholder="Account Name" style="width:140px">' +
      '<input type="text" class="mf-priority f-input-sm" placeholder="Priority"     style="width:100px">' +
      '<label><input type="checkbox" class="mf-fullview"> Full View</label>' +
      '<div class="mf-sep"></div>' +
      '<div class="mf-states">' +
        '<button class="mf-state-btn" data-state="running"  type="button"><span class="state-dot running"></span>Running</button>' +
        '<button class="mf-state-btn" data-state="pending"  type="button"><span class="state-dot pending"></span>Queued</button>' +
        '<button class="mf-state-btn" data-state="done"     type="button"><span class="state-dot done"></span>Finished</button>' +
        '<button class="mf-state-btn" data-state="error"    type="button"><span class="state-dot error"></span>Failed</button>' +
        '<button class="mf-state-btn" data-state="cancelled"type="button"><span class="state-dot cancelled"></span>Canceled</button>' +
      '</div>' +
      '</div>' +
      '<div class="monitor-wrap">' +
      '<table class="monitor-table">' +
      '<thead><tr>' +
      '<th>State</th><th>Id</th><th>Name</th><th>Progress</th><th>GDC</th>' +
      '<th>Priority</th><th>Account Name</th><th>Created</th><th>Submitted</th><th>Last Update</th>' +
      '</tr></thead>' +
      '<tbody id="monitorBody"></tbody>' +
      '</table>' +
      '</div>' +
      '</div>'
    );
  }

}); // end document.ready