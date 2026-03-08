# DevOps Agent

Agent Claude réutilisable qui analyse n'importe quel projet et configure automatiquement l'environnement Docker.

## Installation globale (une seule fois)

```bash
cd devops-agent
npm install
npm link          # rend la commande disponible globalement
```

## Utilisation

```bash
export ANTHROPIC_API_KEY=sk-ant-...

# Dans le dossier du projet à configurer :
devops-agent

# Ou pointer vers un projet :
devops-agent --project /chemin/vers/mon-projet
```

## Ce que fait l'agent

1. Analyse les fichiers du projet (*.csproj, package.json, appsettings.json…)
2. Détecte les dépendances infra (PostgreSQL, Redis, MongoDB, RabbitMQ…)
3. Vérifie les outils installés (docker, dotnet, node)
4. Génère `docker-compose.yml` adapté
5. Génère `dev-start.sh`
6. Démarre PostgreSQL et applique les migrations si présentes
7. Affiche un résumé

## Outils autorisés (sécurité)

L'agent ne peut exécuter que : `docker`, `dotnet`, `npm`, `node`, `brew`
