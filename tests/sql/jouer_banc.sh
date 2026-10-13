#!/usr/bin/env bash
# Joue le banc SQL sur un PostgreSQL local : base jetable « banc », bouchon Supabase, migrations dans l'ordre, scénario.
# Usage : tests/sql/jouer_banc.sh <hôte ou dossier de socket> <port> <utilisateur>
set -euo pipefail
H="$1"; PORT="$2"; U="$3"; RACINE="$(cd "$(dirname "$0")/../.." && pwd)"
psql -h "$H" -p "$PORT" -U "$U" -d postgres -qc "drop database if exists banc" -c "create database banc"
for f in "$RACINE/tests/sql/bouchon_supabase.sql" "$RACINE"/drizzle/migrations/0*.sql; do
  psql -h "$H" -p "$PORT" -U "$U" -d banc -q -v ON_ERROR_STOP=1 -f "$f" >/dev/null
  echo "migration appliquée : $(basename "$f")"
done
psql -h "$H" -p "$PORT" -U "$U" -d banc -f "$RACINE/tests/sql/banc_liaison.sql"
# Parcours devis (migration 0003), sur la même base, après le banc de liaison
psql -h "$H" -p "$PORT" -U "$U" -d banc -f "$RACINE/tests/sql/banc_devis.sql"
