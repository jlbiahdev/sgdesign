#!/usr/bin/env bash
echo "Arrêt de tous les services..."
docker compose stop
pkill -f "Runner.Client" 2>/dev/null || true
pkill -f "vite" 2>/dev/null || true
echo "Arrêté ✓"
