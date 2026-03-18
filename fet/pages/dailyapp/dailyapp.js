/* ═══════════════════════════════════════
   CONFIG — à adapter
═══════════════════════════════════════ */
const API_BASE   = 'http://localhost:5000';
const ACCOUNT_ID = 'user1';

/* ═══════════════════════════════════════
   CONSTANTES
═══════════════════════════════════════ */
const MONTHS_FR    = ['Janvier','Février','Mars','Avril','Mai','Juin','Juillet','Août','Septembre','Octobre','Novembre','Décembre'];
const MONTHS_SHORT = ['Jan','Fév','Mar','Avr','Mai','Jun','Jul','Aoû','Sep','Oct','Nov','Déc'];
const DAYS_FR      = ['Lu','Ma','Me','Je','Ve','Sa','Di'];

/* ═══════════════════════════════════════
   STATE
═══════════════════════════════════════ */
const state = {
  month: new Date().getMonth() + 1,
  year:  new Date().getFullYear(),
  tasks: [],
  ctxTask: null
};
// Cache de toutes les tâches vues (calendar + search)
const taskCache = {};

/* ═══════════════════════════════════════
   HELP
═══════════════════════════════════════ */
function openHelp() { $('#helpOverlay').addClass('open'); }
function closeHelp() { $('#helpOverlay').removeClass('open'); }

/* ═══════════════════════════════════════
   MODE SWITCH
═══════════════════════════════════════ */
function switchMode(mode) {
  if (mode === 'calendar') {
    $('#view-calendar').addClass('active');
    $('#view-search').removeClass('active');
    $('#tabCal').addClass('active');
    $('#tabSearch').removeClass('active');
  } else {
    $('#view-search').addClass('active');
    $('#view-calendar').removeClass('active');
    $('#tabSearch').addClass('active');
    $('#tabCal').removeClass('active');
    setTimeout(function() { $('#searchInput').focus(); }, 50);
  }
}

/* ═══════════════════════════════════════
   API
═══════════════════════════════════════ */
function apiGet(path, params) {
  return $.ajax({
    url: API_BASE + path,
    method: 'GET',
    data: $.extend({ accountId: ACCOUNT_ID }, params || {})
  });
}
function apiPost(path, body) {
  return $.ajax({
    url: API_BASE + path + '?accountId=' + encodeURIComponent(ACCOUNT_ID),
    method: 'POST', contentType: 'application/json', data: JSON.stringify(body)
  });
}
function apiPut(path, body) {
  return $.ajax({
    url: API_BASE + path + '?accountId=' + encodeURIComponent(ACCOUNT_ID),
    method: 'PUT', contentType: 'application/json', data: JSON.stringify(body)
  });
}
function apiDelete(path) {
  return $.ajax({
    url: API_BASE + path + '?accountId=' + encodeURIComponent(ACCOUNT_ID),
    method: 'DELETE'
  });
}

function loadMonth(month, year) {
  state.month = month;
  state.year  = year;
  apiGet('/api/dailyapp/month/' + month + '/year/' + year)
    .done(function(data) {
      state.tasks = Array.isArray(data) ? data : [];
      state.tasks.forEach(function(t) { taskCache[t.id] = t; });
      renderCalendar();
    })
    .fail(function() { state.tasks = []; renderCalendar(); });
}

/* ═══════════════════════════════════════
   CALENDAR HELPERS
═══════════════════════════════════════ */
function getDaysInMonth(m, y) { return new Date(y, m, 0).getDate(); }
// Offset lundi=0 … dimanche=6
function firstDayOffset(m, y) { return (new Date(y, m - 1, 1).getDay() + 6) % 7; }

/* ═══════════════════════════════════════
   RENDER CALENDAR
═══════════════════════════════════════ */
function renderCalendar() {
  var m = state.month, y = state.year;
  var now = new Date();
  var todayD = now.getDate(), todayM = now.getMonth() + 1, todayY = now.getFullYear();

  $('#calMonthLbl').text(MONTHS_FR[m - 1] + ' ' + y);

  var total  = getDaysInMonth(m, y);
  var offset = firstDayOffset(m, y);
  var html   = '';

  // En-têtes jours
  DAYS_FR.forEach(function(d) { html += '<div class="cal-dow">' + d + '</div>'; });

  // Cellules vides avant le 1er
  for (var i = 0; i < offset; i++) html += '<div class="cal-day empty"></div>';

  // Jours
  for (var d = 1; d <= total; d++) {
    var isToday = (d === todayD && m === todayM && y === todayY);
    var dayTasks = state.tasks.filter(function(t) { return t.day === d; });
    var chipsHtml = '';
    dayTasks.forEach(function(t) {
      chipsHtml += '<div class="task-chip ' + esc(t.status) + '" data-id="' + t.id + '">'
        + esc((t.subject || '').substring(0, 30))
        + '</div>';
    });
    html += '<div class="cal-day' + (isToday ? ' today' : '') + '" data-day="' + d + '">'
      + '<div class="day-num">' + d + '</div>'
      + '<div class="day-tasks">' + chipsHtml + '</div>'
      + '<button class="day-add-btn" data-day="' + d + '">+ Ajouter</button>'
      + '</div>';
  }

  // Compléter toujours à 42 cellules (6 lignes × 7) pour hauteur fixe
  var cellsUsed = offset + total;
  for (var i = cellsUsed; i < 42; i++) html += '<div class="cal-day empty"></div>';

  $('#calGrid').html(html);
  renderPeriodsBar();
}

function renderPeriodsBar() {
  var html = '<div class="period-year">' + state.year + '</div>';
  MONTHS_SHORT.forEach(function(label, i) {
    var active = (i + 1) === state.month ? ' active' : '';
    html += '<button class="period-btn' + active + '" data-month="' + (i + 1) + '" data-year="' + state.year + '">' + label + '</button>';
  });
  $('#periodsBar').html(html);
}

/* ═══════════════════════════════════════
   RENDER SEARCH RESULTS
═══════════════════════════════════════ */
function renderSearchResults(data) {
  if (!data || !data.length) {
    $('#searchResults').html('<div class="search-empty">Aucun résultat.</div>');
    return;
  }
  var statusLabel = { todo:'À faire', doing:'En cours', done:'Terminé', notdone:'Non fait', canceled:'Annulé', holiday:'Congé' };
  var html = '';
  data.forEach(function(t) {
    taskCache[t.id] = t;
    var dateStr = pad(t.day) + '/' + pad(t.month) + '/' + t.year;
    var sl = statusLabel[t.status] || t.status || '';
    html += '<div class="result-card ' + esc(t.status) + '" data-id="' + t.id + '">'
      + '<span class="result-date">' + dateStr + '</span>'
      + '<span class="result-subject">' + esc(t.subject || '') + '</span>'
      + '<span class="result-status ' + esc(t.status) + '">' + sl + '</span>'
      + '</div>';
  });
  $('#searchResults').html(html);
}

/* ═══════════════════════════════════════
   MODAL
═══════════════════════════════════════ */
function openModal(task, prefillDay) {
  $('#fId').val(task ? task.id : '');
  $('#fSubject').val(task ? (task.subject || '') : '');
  $('#fComment').val(task ? (task.comment || '') : '');
  $('#fDay').val(task ? task.day : (prefillDay || ''));
  $('#fMonth').val(task ? task.month : state.month);
  $('#fYear').val(task ? task.year : state.year);
  $('input[name="fStatus"]').prop('checked', false);
  var status = task ? task.status : 'todo';
  $('input[name="fStatus"][value="' + status + '"]').prop('checked', true);
  $('#modalTitle').text(task ? 'Modifier la tâche' : 'Nouvelle tâche');
  $('#modalOverlay').addClass('open');
  setTimeout(function() { $('#fSubject').focus(); }, 60);
}

function closeModal() { $('#modalOverlay').removeClass('open'); }

function saveTask() {
  var id      = $('#fId').val();
  var subject = $.trim($('#fSubject').val());
  var comment = $.trim($('#fComment').val());
  var day     = parseInt($('#fDay').val(), 10);
  var month   = parseInt($('#fMonth').val(), 10);
  var year    = parseInt($('#fYear').val(), 10);
  var status  = $('input[name="fStatus"]:checked').val();

  if (!subject) { $('#fSubject').focus(); return; }
  if (!day || !month || !year || !status) return;

  var done = function() { closeModal(); loadMonth(state.month, state.year); };
  var fail = function(e) { console.error('API error', e); };

  if (id) {
    apiPut('/api/dailyapp/' + id, { id: parseInt(id, 10), accountId: ACCOUNT_ID, subject: subject, comment: comment, day: day, month: month, year: year, status: status })
      .done(done).fail(fail);
  } else {
    apiPost('/api/dailyapp', { subject: subject, comment: comment, day: day, month: month, year: year, status: status })
      .done(done).fail(fail);
  }
}

/* ═══════════════════════════════════════
   CONTEXT MENU
═══════════════════════════════════════ */
function showCtxMenu(taskId, x, y) {
  var task = taskCache[taskId];
  if (!task) return;
  state.ctxTask = task;
  var $m = $('#ctxMenu');
  $m.addClass('open');
  var mw = $m.outerWidth(), mh = $m.outerHeight();
  var vw = window.innerWidth, vh = window.innerHeight;
  $m.css({
    left: Math.min(x, vw - mw - 8),
    top:  (y + mh > vh) ? y - mh - 4 : y
  });
}
function closeCtxMenu() { $('#ctxMenu').removeClass('open'); }

/* ═══════════════════════════════════════
   UTILS
═══════════════════════════════════════ */
function esc(s) {
  return String(s || '').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}
function pad(n) { return String(n).padStart(2, '0'); }

/* ═══════════════════════════════════════
   EVENTS
═══════════════════════════════════════ */
$(function() {

  // Help popup
  $('#helpCloseBtn').on('click', closeHelp);
  $('#helpOverlay').on('click', function(e) { if ($(e.target).is('#helpOverlay')) closeHelp(); });

  // Nav calendrier
  $('#btnPrev').on('click', function() {
    var m = state.month - 1, y = state.year;
    if (m < 1) { m = 12; y--; }
    loadMonth(m, y);
  });
  $('#btnNext').on('click', function() {
    var m = state.month + 1, y = state.year;
    if (m > 12) { m = 1; y++; }
    loadMonth(m, y);
  });
  $('#btnToday').on('click', function() {
    var n = new Date();
    loadMonth(n.getMonth() + 1, n.getFullYear());
  });

  // Periods bar
  $(document).on('click', '.period-btn', function() {
    loadMonth(parseInt($(this).data('month'), 10), parseInt($(this).data('year'), 10));
  });

  // Bouton ajouter par jour
  $(document).on('click', '.day-add-btn', function(e) {
    e.stopPropagation();
    openModal(null, parseInt($(this).data('day'), 10));
  });

  // Click sur chip → context menu
  $(document).on('contextmenu', '.task-chip', function(e) {
    e.preventDefault();
    showCtxMenu(parseInt($(this).data('id'), 10), e.clientX, e.clientY);
  });
  // Clic gauche sur chip → modifier directement
  $(document).on('click', '.task-chip', function(e) {
    e.stopPropagation();
    var task = taskCache[parseInt($(this).data('id'), 10)];
    if (task) openModal(task, null);
  });

  // Click sur résultat recherche → context menu
  $(document).on('contextmenu', '.result-card', function(e) {
    e.preventDefault();
    showCtxMenu(parseInt($(this).data('id'), 10), e.clientX, e.clientY);
  });
  $(document).on('click', '.result-card', function(e) {
    e.stopPropagation();
    var task = taskCache[parseInt($(this).data('id'), 10)];
    if (task) openModal(task, null);
  });

  // Recherche
  $('#btnSearch').on('click', function() {
    var kw = $.trim($('#searchInput').val());
    if (!kw) return;
    apiGet('/api/dailyapp/search', { keywords: kw })
      .done(renderSearchResults)
      .fail(function() { $('#searchResults').html('<div class="search-empty">Erreur lors de la recherche.</div>'); });
  });
  $('#searchInput').on('keydown', function(e) {
    if (e.key === 'Enter') $('#btnSearch').click();
  });

  // Modal
  $('#modalCloseBtn, #modalCancelBtn').on('click', closeModal);
  $('#modalOverlay').on('click', function(e) { if ($(e.target).is('#modalOverlay')) closeModal(); });
  $('#btnSave').on('click', saveTask);

  // Context menu actions
  $('#ctxEdit').on('click', function() {
    if (!state.ctxTask) return;
    closeCtxMenu();
    openModal(state.ctxTask, null);
  });
  $('#ctxDuplicate').on('click', function() {
    if (!state.ctxTask) return;
    var t = state.ctxTask;
    closeCtxMenu();
    openModal(null, t.day);
    $('#fSubject').val(t.subject || '');
    $('#fComment').val(t.comment || '');
    $('input[name="fStatus"]').prop('checked', false);
    $('input[name="fStatus"][value="' + (t.status || 'todo') + '"]').prop('checked', true);
  });
  $('#ctxDelete').on('click', function() {
    if (!state.ctxTask) return;
    var id = state.ctxTask.id;
    closeCtxMenu();
    if (!confirm('Supprimer cette tâche ?')) return;
    apiDelete('/api/dailyapp/' + id)
      .done(function() { loadMonth(state.month, state.year); })
      .fail(function(e) { console.error('Delete failed', e); });
  });

  // Fermer ctx menu au clic extérieur
  $(document).on('click', function(e) {
    if (!$(e.target).closest('#ctxMenu').length) closeCtxMenu();
  });

  // Init
  loadMonth(state.month, state.year);
});
