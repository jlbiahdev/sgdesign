// Mock Jira data generator
function mockJiras(sprint) {
  const statuses = ['todo','progress','review','done','done','progress'];
  const assignees = ['J. Dupont','M. Martin','S. Bernard','L. Thomas','A. Petit'];
  const titles = [
    'Fix login bug après MàJ SSO','Implémenter le dashboard utilisateur','Upgrade dépendance Log4j','Refactorer les endpoints API REST',
    'Ajouter la réinitialisation de mot de passe','Optimiser les requêtes base de données','Améliorer le layout mobile','Créer la suite de tests automatisés',
    'Mettre à jour la documentation technique','Intégrer la passerelle de paiement','Corriger le rapport mensuel STYX','Migration vers .NET 8',
    'Audit des droits d\'accès HPC','Archivage Q4 2024','Déploiement en recette'
  ];
  const prefix = sprint.toUpperCase().replace(/[^A-Z0-9]/g,'').substring(0,6) || 'ABC';
  const n = 8 + Math.floor(Math.random()*7);
  return Array.from({length:n},(_,i)=>({
    num: prefix+'-'+(1001+i),
    title: titles[i % titles.length],
    status: statuses[i % statuses.length],
    assignee: assignees[i % assignees.length]
  }));
}

const statusLabel = {todo:'À faire',progress:'En cours',review:'En revue',done:'Terminé'};
const statusClass = {todo:'s-todo',progress:'s-progress',review:'s-review',done:'s-done'};

function loadSprint() {
  const v = document.getElementById('sprintInput').value.trim();
  if (!v) { document.getElementById('sprintInput').focus(); return; }
  const jiras = mockJiras(v);
  document.getElementById('sprintNameLabel').textContent = 'Sprint : ' + v.toUpperCase();
  document.getElementById('sprintCountLabel').textContent = jiras.length + ' tickets chargés';
  document.getElementById('sprintMeta').classList.add('show');
  document.getElementById('tblSection').classList.add('show');
  document.getElementById('jiraBody').innerHTML = jiras.map(j=>`
    <tr>
      <td class="jira-num"><a class="jira-link" href="#" onclick="return false">${j.num}</a></td>
      <td class="title-cell">${j.title}</td>
      <td><span class="status-badge ${statusClass[j.status]}">${statusLabel[j.status]}</span></td>
      <td style="font-size:.73rem;color:var(--text-dim)">${j.assignee}</td>
    </tr>`).join('');
}

function clearSprint() {
  document.getElementById('sprintInput').value='';
  document.getElementById('sprintMeta').classList.remove('show');
  document.getElementById('tblSection').classList.remove('show');
  document.getElementById('jiraBody').innerHTML='<tr><td colspan="4"><div class="empty"><svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke-width="1.2" stroke-linecap="round"><path d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8z"/><polyline points="14 2 14 8 20 8"/></svg><div>Aucun sprint chargé</div></div></td></tr>';
}
