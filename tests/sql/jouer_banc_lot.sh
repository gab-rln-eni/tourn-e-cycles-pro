#!/usr/bin/env bash
# Banc d'un lot (agent LOTS, 2026-10-14) : non-régression des fonctions existantes, puis assertions du lot.
# Passe A : bouchon, migrations 0000 à 0004, bancs existants (liaison et devis : inscrire, terminer_fiche, preparer_facture,
#           controler_facture, valider_facture, donnees_demande par reserver_demandes, fonctions devis_*), photo des tables existantes.
# Passe B : même chose avec la migration du lot appliquée DEUX fois (idempotence) avant les bancs existants.
# Les sorties A et B, normalisées (identifiants, heures, codes et jetons aléatoires), doivent être identiques ; sinon échec.
# Usage : tests/sql/jouer_banc_lot.sh <hôte ou dossier de socket> <port> <utilisateur> <migration du lot> <banc du lot> <dossier de sortie>
set -euo pipefail
H="$1"; PORT="$2"; U="$3"; LOT="$4"; BANC="$5"; SORTIE="$6"
RACINE="$(cd "$(dirname "$0")/../.." && pwd)"
mkdir -p "$SORTIE"
P() { psql -h "$H" -p "$PORT" -U "$U" "$@"; }

normaliser() {
  sed -E -e 's/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/<UUID>/g' \
         -e 's/TC-[0-9A-F]{8}/TC-<REF>/g' \
         -e 's/[0-9]{4}-[0-9]{2}-[0-9]{2}[ T][0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?([+-][0-9]{2}(:[0-9]{2})?)?/<HEURE>/g' \
         -e 's/\b[0-9a-f]{64}\b/<JETON>/g' -e 's/\b[0-9a-f]{10}\b/<CODE>/g' \
         -e 's#/home/[^ :]*/##g'
}

TABLES="acces entreprises evenements inscriptions fiches fiche_points pieces_catalogue pieces_posees factures facture_lignes avis_controle demandes_automatisation devis devis_lignes"

passe() { # $1 = A ou B
  P -d postgres -qc "drop database if exists banc_lot" -c "create database banc_lot"
  P -d banc_lot -q -v ON_ERROR_STOP=1 -f "$RACINE/tests/sql/bouchon_supabase.sql" >/dev/null
  for f in "$RACINE"/drizzle/migrations/000[0-4]_*.sql; do P -d banc_lot -q -v ON_ERROR_STOP=1 -f "$f" >/dev/null; done
  if [ "$1" = B ]; then
    P -d banc_lot -q -v ON_ERROR_STOP=1 -f "$LOT" >/dev/null
    P -d banc_lot -q -v ON_ERROR_STOP=1 -f "$LOT" >/dev/null   # idempotence
  fi
  {
    P -d banc_lot -f "$RACINE/tests/sql/banc_liaison.sql" 2>&1
    P -d banc_lot -f "$RACINE/tests/sql/banc_devis.sql" 2>&1
    for t in $TABLES; do
      echo "== table $t"
      P -d banc_lot -Atc "select count(*) from public.$t"
      P -d banc_lot -Atc "select t::text from public.$t t" | normaliser | sort
    done
  } | normaliser > "$SORTIE/rejeu_$1.txt"
}

passe A
passe B
if diff -u "$SORTIE/rejeu_A.txt" "$SORTIE/rejeu_B.txt" > "$SORTIE/rejeu_diff.txt"; then
  echo "NON-RÉGRESSION : sorties A et B identiques ($(wc -l < "$SORTIE/rejeu_A.txt") lignes)"
else
  echo "NON-RÉGRESSION : ÉCART, voir $SORTIE/rejeu_diff.txt"; exit 1
fi
grep -q "BANC DEVIS : TOUTES LES ASSERTIONS PASSENT" "$SORTIE/rejeu_B.txt" || { echo "banc devis non passé"; exit 1; }

# Empreinte des objets existants avant et après le lot (base de passe B, comparée à une base sans le lot)
EMP="$RACINE/tests/sql/empreinte_schema.sql"
P -d postgres -qc "drop database if exists banc_emp" -c "create database banc_emp"
P -d banc_emp -q -v ON_ERROR_STOP=1 -f "$RACINE/tests/sql/bouchon_supabase.sql" >/dev/null
for f in "$RACINE"/drizzle/migrations/000[0-4]_*.sql; do P -d banc_emp -q -v ON_ERROR_STOP=1 -f "$f" >/dev/null; done
P -d banc_emp -Atf "$EMP" > "$SORTIE/empreinte_avant.txt"
P -d banc_emp -q -v ON_ERROR_STOP=1 -f "$LOT" >/dev/null
P -d banc_emp -Atf "$EMP" > "$SORTIE/empreinte_apres.txt"
comm -23 <(sort "$SORTIE/empreinte_avant.txt") <(sort "$SORTIE/empreinte_apres.txt") > "$SORTIE/empreinte_disparus_ou_changes.txt"
comm -13 <(sort "$SORTIE/empreinte_avant.txt") <(sort "$SORTIE/empreinte_apres.txt") > "$SORTIE/empreinte_neufs.txt"
if [ -s "$SORTIE/empreinte_disparus_ou_changes.txt" ]; then echo "SCHÉMA : objet existant modifié"; cat "$SORTIE/empreinte_disparus_ou_changes.txt"; exit 1; fi
echo "SCHÉMA : objets existants identiques ($(wc -l < "$SORTIE/empreinte_avant.txt")), objets neufs : $(wc -l < "$SORTIE/empreinte_neufs.txt")"

# Banc propre au lot, sur la base de passe B
P -d banc_lot -v ON_ERROR_STOP=1 -f "$BANC" > "$SORTIE/banc_lot.txt" 2>&1 || { tail -20 "$SORTIE/banc_lot.txt"; echo "BANC DU LOT : ÉCHEC"; exit 1; }
tail -1 "$SORTIE/banc_lot.txt"
