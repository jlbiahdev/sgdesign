function handleCsvDrop(e) {
  e.preventDefault();
  const zone = document.getElementById('csvDropZone');
  zone.classList.remove('over');
  const f = e.dataTransfer.files[0];
  if (f && f.name.endsWith('.csv')) handleCsvFile(f);
}
function handleCsvFile(f) {
  if (!f) return;
  const zone = document.getElementById('csvDropZone');
  zone.classList.add('has-file');
  document.getElementById('csvLabel').textContent = '✓ ' + f.name;
}

const cmds = [
  {cmd:'robocopy "\\\\srvrbxassufp01\\hpc\\01_EPARGNE\\2023" "\\\\srvrbxassufp01cold\\Archives3\\01_EPARGNE\\2023" /mir /LOG:\\\\srvrbxassufp01\\hpc\\00_MOTEUR\\Archives\\2023\\cpy_archives_01_epargne_2023.log'},
  {cmd:'robocopy "\\\\srvrbxassufp01\\hpc\\02_PREVOYANCE_DOMMAGE\\01_S2\\2023" "\\\\srvrbxassufp01cold\\Archives3\\02_PREVOYANCE_DOMMAGE\\01_S2" /mir /LOG:\\\\srvrbxassufp01\\hpc\\00_MOTEUR\\Archives\\2023\\cpy_archives_02_prevoyance_s2_2023.log'},
  {cmd:'robocopy "\\\\srvrbxassufp01\\hpc\\02_PREVOYANCE_DOMMAGE\\02_IFRS17\\2023" "\\\\srvrbxassufp01cold\\Archives3\\02_PREVOYANCE_DOMMAGE\\02_IFRS17" /mir /LOG:\\\\srvrbxassufp01\\hpc\\00_MOTEUR\\Archives\\2023\\cpy_archives_02_prevoyance_ifrs17_2023.log'},
  {cmd:'robocopy "\\\\srvrbxassufp01\\hpc\\02_PREVOYANCE_DOMMAGE\\03_BFP mvx pdts\\2023" "\\\\srvrbxassufp01cold\\Archives3\\02_PREVOYANCE_DOMMAGE\\03_BFP" /mir /LOG:\\\\srvrbxassufp01\\hpc\\00_MOTEUR\\Archives\\2023\\cpy_archives_02_prevoyance_bfp_2023.log'},
  {cmd:'robocopy "\\\\srvrbxassufp01\\hpc\\02_PREVOYANCE_DOMMAGE\\04_PHASE_RISQUE\\2023" "\\\\srvrbxassufp01cold\\Archives3\\02_PREVOYANCE_DOMMAGE\\04_PHASE_RISQUE" /mir /LOG:\\\\srvrbxassufp01\\hpc\\00_MOTEUR\\Archives\\2023\\cpy_archives_02_prevoyance_phase_risque_2023.log'},
  {cmd:'robocopy "\\\\srvrbxassufp03\\hpc\\04_PRR\\2023" "\\\\srvrbxassufp01cold\\Archives3\\04_PRR\\2023" /mir /LOG:\\\\srvrbxassufp03\\hpc\\00_MOTEUR\\Archives\\2023\\cpy_archives_04_prr_2023.log'},
  {cmd:'robocopy "\\\\srvrbxassufp01\\hpc\\05_MODELE\\2023" "\\\\srvrbxassufp01cold\\Archives3\\05_MODELE\\2023" /mir /LOG:\\\\srvrbxassufp01\\hpc\\00_MOTEUR\\Archives\\2023\\cpy_archives_05_modele_2023.log'},
];
function renderTable(data){
  const tb=document.getElementById('tbody');
  document.getElementById('cnt').textContent=data.length;
  tb.innerHTML=data.map(r=>`<tr><td class="cmd-cell">${r.cmd}</td><td class="act">
    <button class="dl-btn"><svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M21 15v4a2 2 0 01-2 2H5a2 2 0 01-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>CMD</button>
    <button class="dl-btn"><svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><polyline points="16 18 22 12 16 6"/><polyline points="8 6 2 12 8 18"/></svg>XML</button>
  </td></tr>`).join('');
}
renderTable(cmds);

var btnHelp   = document.getElementById('btnHelp');
var helpPopup = document.getElementById('helpPopup');
var closeHelp = document.getElementById('closeHelp');
btnHelp.addEventListener('click', function(e) {
  e.stopPropagation();
  if (helpPopup.classList.contains('open')) { helpPopup.classList.remove('open'); return; }
  var rect = btnHelp.getBoundingClientRect();
  var left = rect.right - 320;
  if (left < 8) left = 8;
  helpPopup.style.top   = (rect.bottom + 8) + 'px';
  helpPopup.style.left  = left + 'px';
  helpPopup.style.right = 'auto';
  helpPopup.classList.add('open');
});
closeHelp.addEventListener('click', function(e) {
  e.stopPropagation();
  helpPopup.classList.remove('open');
});
document.addEventListener('click', function() { helpPopup.classList.remove('open'); });
helpPopup.addEventListener('click', function(e) { e.stopPropagation(); });
