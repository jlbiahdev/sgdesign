#!/usr/bin/env bash
# =============================================================
# dev-start.sh — Lance l'environnement de développement TaskFlow
# Usage : ./dev-start.sh
# =============================================================
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

step() { echo -e "\n${GREEN}▶ $1${NC}"; }
info() { echo -e "${YELLOW}  $1${NC}"; }

# 1. PostgreSQL
step "Démarrage PostgreSQL"
docker compose up -d postgres
info "Attente de la disponibilité de PostgreSQL..."
until docker compose exec -T postgres pg_isready -U postgres -d taskflow > /dev/null 2>&1; do
  sleep 1
done
echo "  PostgreSQL prêt ✓"

# 2. Runner.Client
step "Lancement de Runner.Client (background)"
cd Runner.Client
dotnet run &
DOTNET_PID=$!
cd ..
info "Runner démarré (PID $DOTNET_PID)"

# 3. Dashboard React
step "Installation des dépendances npm (si nécessaire)"
cd runner-dashboard
npm install --silent

step "Lancement du Dashboard React"
npm run dev &
REACT_PID=$!
cd ..
info "Dashboard disponible sur http://localhost:5173"

echo -e "\n${GREEN}======================================${NC}"
echo -e "${GREEN}  Environnement prêt !${NC}"
echo -e "${GREEN}  Dashboard : http://localhost:5173${NC}"
echo -e "${GREEN}  API       : http://localhost:5000${NC}"
echo -e "${GREEN}  DB        : localhost:5432/taskflow${NC}"
echo -e "${GREEN}======================================${NC}"
echo ""
echo "  Arrêter : Ctrl+C puis ./dev-stop.sh"

# Attendre Ctrl+C
trap "echo 'Arrêt…'; kill $DOTNET_PID $REACT_PID 2>/dev/null; docker compose stop; exit 0" INT
wait
