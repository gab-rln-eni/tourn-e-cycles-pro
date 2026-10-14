-- Banc du chantier V4 (migration 0010), joué sur la base du banc après banc_liaison.sql, banc_devis.sql, les bancs L1 à L3 et STOCK.
-- Données propres au banc (identifiants fixes en ...v4) ; comptes du banc de liaison : dirigeant ...0d, mécanicien ...0e, atelier ...0a.
-- Couvre : structure et droits, liste « À commander » (pièces des devis, provenance, anti-doublon, case de retrait), rappel de 15 h v2
-- (mode essai sans réservation, mode normal, réservation partagée avec v1), inscription sans doublon (enveloppe), résumé de facture,
-- sorties vides (journée sans pièce, demande inconnue) et sorties en erreur (rôle refusé, ligne inconnue, valeur nulle).
\set ON_ERROR_STOP 1
\set QUIET 1
create function pg_temp.verifier(c boolean, m text) returns void language plpgsql as $$ begin if c is not true then raise exception 'ASSERTION : %', m; end if; end $$;
create function pg_temp.refuse(q text, attendu text) returns boolean language plpgsql as $$
begin execute q; return false; exception when others then
  if sqlerrm not like '%' || attendu || '%' then raise exception 'ASSERTION : message inattendu « % » pour %', sqlerrm, q; end if; return true; end $$;
grant execute on function pg_temp.verifier(boolean, text), pg_temp.refuse(text, text) to anon, authenticated, service_role;

-- 0. Structure et droits
select pg_temp.verifier((select count(*) from pg_constraint where contype = 'f'
  and conrelid in ('public.v4_bascule'::regclass, 'public.devis_pieces_retirees'::regclass)) = 0, 'aucune clé étrangère');
select pg_temp.verifier((select count(*) from pg_trigger where not tgisinternal
  and tgrelid in ('public.v4_bascule'::regclass, 'public.devis_pieces_retirees'::regclass)) = 0, 'aucun déclencheur');
select pg_temp.verifier((select bool_and(relrowsecurity) from pg_class where oid in
  ('public.v4_bascule'::regclass, 'public.devis_pieces_retirees'::regclass)), 'RLS active');
select pg_temp.verifier(not has_table_privilege(r, t, 'select,insert,update,delete'), format('%s sans droit sur %s', r, t))
  from unnest(array['anon','authenticated']) r, unnest(array['public.v4_bascule','public.devis_pieces_retirees']) t;
select pg_temp.verifier(not has_function_privilege('anon', f, 'execute'), format('anon sans EXECUTE %s', f))
  from unnest(array['public.v4_bascule_etat()','public.commandes_devis_source()','public.commandes_v4_journees()',
                     'public.commandes_v4_journee(uuid)','public.devis_piece_retirer(uuid,boolean)','public.devis_pieces_etat(uuid)',
                     'public.rappel_commandes_reserver_v4(boolean)','public.facture_resume_v4(uuid)']) f;
select pg_temp.verifier(not has_function_privilege('authenticated', f, 'execute'), format('authenticated sans EXECUTE %s', f))
  from unnest(array['public.commandes_devis_source()','public.rappel_commandes_reserver_v4(boolean)','public.facture_resume_v4(uuid)']) f;
select pg_temp.verifier(has_function_privilege(r, 'public.inscrire_v4(jsonb)', 'execute') = has_function_privilege(r, 'public.inscrire(jsonb)', 'execute'),
  format('inscrire_v4 : mêmes droits que inscrire pour %s', r)) from unnest(array['anon','authenticated']) r;
select pg_temp.verifier(has_function_privilege('anon', 'public.inscrire_v4(jsonb)', 'execute'), 'anon EXECUTE inscrire_v4');
select pg_temp.verifier(has_function_privilege('service_role', 'public.inscrire_v4(jsonb)', 'execute'), 'service_role EXECUTE inscrire_v4 (comme inscrire en base réelle)');
select pg_temp.verifier((select count(*) from public.v4_bascule) = 1 and not public.v4_bascule_etat(), 'verrou V4 fermé, une ligne');

-- 1. Données du banc : catalogue relié (À commander, en stock, inconnu, main d'oeuvre), journées du 16/10 et du 15/10
update public.v4_bascule set mise_en_service = now() - interval '1 minute';   -- base jetable du banc seulement
insert into public.pieces_catalogue(id, reference, libelle, prix_vente_ht) values
  ('a0000000-0000-0000-0000-0000000000a1', 'V4-ACMD', 'Gaine V4 a commander', 3),
  ('a0000000-0000-0000-0000-0000000000a2', 'V4-STK', 'Patin V4 en stock', 5),
  ('a0000000-0000-0000-0000-0000000000a3', 'V4-INC', 'Chambre V4 inconnue', 7),
  ('a0000000-0000-0000-0000-0000000000a4', 'V4-MO', 'Main V4 (heure)', 50);
insert into public.catalogue_axonaut(piece_id, role, reference, libelle, axonaut_produit_id, suivi_stock) values
  ('a0000000-0000-0000-0000-0000000000a1', 'piece', 'V4-ACMD', 'Gaine V4 a commander', '9900001', true),
  ('a0000000-0000-0000-0000-0000000000a2', 'piece', 'V4-STK', 'Patin V4 en stock', '9900002', true),
  ('a0000000-0000-0000-0000-0000000000a4', 'main_oeuvre', 'V4-MO', 'Main V4 (heure)', '9900004', false);
insert into public.stock_axonaut(axonaut_produit_id, stock) values ('9900001', 0), ('9900002', 3), ('9900004', null);

insert into public.evenements(id, entreprise_id, site, date_intervention, places_max)
  select x.id, e.id, x.site, x.d, x.pm from (select id from public.entreprises order by created_at limit 1) e,
  (values ('b0000000-0000-0000-0000-000000000016'::uuid, 'Site V4 16', date '2026-10-16', null::int),
          ('b0000000-0000-0000-0000-000000000015'::uuid, 'Site V4 15', date '2026-10-15', null),
          ('b0000000-0000-0000-0000-0000000000c1'::uuid, 'Site V4 complet', date '2099-12-31', 1),
          ('b0000000-0000-0000-0000-0000000000f1'::uuid, 'Site V4 futur', current_date + 30, null),
          ('b0000000-0000-0000-0000-0000000000f2'::uuid, 'Site V4 futur 2', current_date + 31, null)) x(id, site, d, pm);
insert into public.inscriptions(id, evenement_id, nom, prenom, telephone, email, code_postal, type_velo, partie_signalee, consentement_le) values
  ('c0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000016', 'Normal', 'Un', '0600000000', 'un@example.com', '69007', 'vae', 'freins', now()),
  ('c0000000-0000-0000-0000-000000000002', 'b0000000-0000-0000-0000-000000000016', 'Normal', 'Deux', '0600000000', 'deux@example.com', '69007', 'vae', 'freins', now()),
  ('c0000000-0000-0000-0000-000000000003', 'b0000000-0000-0000-0000-000000000016', 'Normal', 'Trois', '0600000000', 'trois@example.com', '69007', 'vae', 'freins', now()),
  ('c0000000-0000-0000-0000-000000000004', 'b0000000-0000-0000-0000-000000000016', 'LOTS-TEST', 'V4', '0600000000', 'lots@example.com', '69007', 'vae', 'freins', now()),
  ('c0000000-0000-0000-0000-000000000005', 'b0000000-0000-0000-0000-000000000015', 'Quinze', 'V4', '0600000000', 'q@example.com', '69007', 'vae', 'freins', now());
insert into public.fiches(id, inscription_id, statut, termine_le) values
  ('d0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001', 'en_cours', null),
  ('d0000000-0000-0000-0000-000000000002', 'c0000000-0000-0000-0000-000000000002', 'terminee', now()),
  ('d0000000-0000-0000-0000-000000000003', 'c0000000-0000-0000-0000-000000000003', 'en_cours', null),
  ('d0000000-0000-0000-0000-000000000004', 'c0000000-0000-0000-0000-000000000004', 'en_cours', null),
  ('d0000000-0000-0000-0000-000000000005', 'c0000000-0000-0000-0000-000000000005', 'en_cours', null);
-- Fiche 2 (terminée) : la Gaine est posée « à commander » (liste L1)
insert into public.pieces_posees(id, fiche_id, piece_id, libelle, quantite, a_commander) values
  ('e0000000-0000-0000-0000-000000000002', 'd0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-0000000000a1', 'Gaine V4 a commander', 1, true);
insert into public.devis(id, fiche_id, reference, statut) values
  ('f0000000-0000-0000-0000-000000000011', 'd0000000-0000-0000-0000-000000000001', 'DV-V4-11', 'envoye'),
  ('f0000000-0000-0000-0000-000000000012', 'd0000000-0000-0000-0000-000000000001', 'DV-V4-12', 'refuse'),
  ('f0000000-0000-0000-0000-000000000021', 'd0000000-0000-0000-0000-000000000002', 'DV-V4-21', 'accepte'),
  ('f0000000-0000-0000-0000-000000000031', 'd0000000-0000-0000-0000-000000000003', 'DV-V4-31', 'refuse'),
  ('f0000000-0000-0000-0000-000000000041', 'd0000000-0000-0000-0000-000000000004', 'DV-V4-41', 'brouillon'),
  ('f0000000-0000-0000-0000-000000000051', 'd0000000-0000-0000-0000-000000000005', 'DV-V4-51', 'accepte'),
  ('f0000000-0000-0000-0000-000000000099', null, 'DV-V4-99', 'brouillon');
insert into public.devis_lignes(id, devis_id, piece_id, libelle, quantite, prix_unitaire_ht) values
  -- devis 11 (en attente, fiche 1) : Gaine (à commander), Patin (en stock), Chambre (inconnu), Main d'oeuvre, ligne libre
  ('01000000-0000-0000-0000-000000000111', 'f0000000-0000-0000-0000-000000000011', 'a0000000-0000-0000-0000-0000000000a1', 'Gaine V4 a commander', 2, 3),
  ('01000000-0000-0000-0000-000000000112', 'f0000000-0000-0000-0000-000000000011', 'a0000000-0000-0000-0000-0000000000a2', 'Patin V4 en stock', 1, 5),
  ('01000000-0000-0000-0000-000000000113', 'f0000000-0000-0000-0000-000000000011', 'a0000000-0000-0000-0000-0000000000a3', 'Chambre V4 inconnue', 1, 7),
  ('01000000-0000-0000-0000-000000000114', 'f0000000-0000-0000-0000-000000000011', 'a0000000-0000-0000-0000-0000000000a4', 'Main V4 (heure)', 1, 50),
  ('01000000-0000-0000-0000-000000000115', 'f0000000-0000-0000-0000-000000000011', null, 'Réglage libre V4', 1, 10),
  -- devis 12 (refusé, même fiche 1) : la Gaine encore : doublon 'devis' (le devis en attente l'emporte)
  ('01000000-0000-0000-0000-000000000121', 'f0000000-0000-0000-0000-000000000012', 'a0000000-0000-0000-0000-0000000000a1', 'Gaine V4 a commander', 1, 3),
  -- devis 21 (accepté, fiche 2 terminée) : la Gaine, déjà dans la liste L1 pour ce vélo : doublon 'fiche'
  ('01000000-0000-0000-0000-000000000211', 'f0000000-0000-0000-0000-000000000021', 'a0000000-0000-0000-0000-0000000000a1', 'Gaine V4 a commander', 1, 3),
  -- devis 31 (refusé, fiche 3) : Chambre : affichée « refusé », jamais rappelée
  ('01000000-0000-0000-0000-000000000311', 'f0000000-0000-0000-0000-000000000031', 'a0000000-0000-0000-0000-0000000000a3', 'Chambre V4 inconnue', 1, 7),
  -- devis 41 (brouillon, LOTS-TEST) : Gaine : mode essai seulement
  ('01000000-0000-0000-0000-000000000411', 'f0000000-0000-0000-0000-000000000041', 'a0000000-0000-0000-0000-0000000000a1', 'Gaine V4 a commander', 1, 3),
  -- devis 51 (accepté, journée du 15/10) : Gaine : à l'écran, jamais rappelée
  ('01000000-0000-0000-0000-000000000511', 'f0000000-0000-0000-0000-000000000051', 'a0000000-0000-0000-0000-0000000000a1', 'Gaine V4 a commander', 1, 3),
  -- devis 99 sans fiche : jamais dans la liste (pas de journée)
  ('01000000-0000-0000-0000-000000000991', 'f0000000-0000-0000-0000-000000000099', 'a0000000-0000-0000-0000-0000000000a1', 'Gaine V4 a commander', 1, 3);

-- 2. Source : reliées au catalogue seulement, stock À commander ou inconnu, anti-doublon
select pg_temp.verifier((select count(*) from public.commandes_devis_source() where devis_reference like 'DV-V4-%') = 7, 'source : 7 lignes candidates');
select pg_temp.verifier(not exists (select 1 from public.commandes_devis_source() where devis_ligne_id in
  ('01000000-0000-0000-0000-000000000112', '01000000-0000-0000-0000-000000000114', '01000000-0000-0000-0000-000000000115',
   '01000000-0000-0000-0000-000000000991')), 'en stock, main d''oeuvre, ligne libre et devis sans fiche exclus');
select pg_temp.verifier((select doublon from public.commandes_devis_source() where devis_ligne_id = '01000000-0000-0000-0000-000000000121') = 'devis',
  'doublon devis : le devis refusé cède la place au devis en attente');
select pg_temp.verifier((select doublon from public.commandes_devis_source() where devis_ligne_id = '01000000-0000-0000-0000-000000000111') is null,
  'devis en attente gardé');
select pg_temp.verifier((select doublon from public.commandes_devis_source() where devis_ligne_id = '01000000-0000-0000-0000-000000000211') = 'fiche',
  'doublon fiche : pièce déjà dans la liste L1 pour le même vélo');
select pg_temp.verifier((select etat_stock from public.commandes_devis_source() where devis_ligne_id = '01000000-0000-0000-0000-000000000113') = 'inconnu',
  'pièce non reliée à Axonaut : stock inconnu');
select pg_temp.verifier((select etat_devis from public.commandes_devis_source() where devis_ligne_id = '01000000-0000-0000-0000-000000000411') = 'brouillon',
  'brouillon : état brouillon (0011)');

-- 3. Écran (atelier) : journée du 16/10, une ligne par pièce et par vélo ; refus pour anon et mécanicien
set role anon; reset request.jwt.claim.sub;
select pg_temp.verifier(pg_temp.refuse('select public.commandes_v4_journees()', 'permission denied'), 'anon : journees refusé');
select pg_temp.verifier(pg_temp.refuse('select public.rappel_commandes_reserver_v4(true)', 'permission denied'), 'anon : rappel refusé');
reset role;
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000e';
select pg_temp.verifier(pg_temp.refuse('select public.commandes_v4_journees()', 'Accès refusé'), 'mécanicien : journees refusé');
select pg_temp.verifier(pg_temp.refuse('select public.rappel_commandes_reserver_v4(true)', 'permission denied'), 'authenticated : rappel refusé');
reset role;
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select public.commandes_v4_journee('b0000000-0000-0000-0000-000000000016') as j16 \gset
select public.commandes_v4_journees() as js \gset
reset role;
select pg_temp.verifier(jsonb_array_length(:'j16'::jsonb) = 5, 'journée 16 : 5 lignes (L1 fiche 2, devis 11 x2, devis 31, devis 41)');
select pg_temp.verifier((select count(*) from jsonb_array_elements(:'j16'::jsonb) e where e->>'source' = 'fiche') = 1, 'une ligne L1');
select pg_temp.verifier((select count(*) from jsonb_array_elements(:'j16'::jsonb) e
  where e->>'libelle' = 'Gaine V4 a commander' and e->>'client' = 'Deux Normal') = 1, 'anti-doublon : une seule ligne Gaine pour la fiche 2');
select pg_temp.verifier((select count(*) from jsonb_array_elements(:'j16'::jsonb) e
  where e->>'libelle' = 'Gaine V4 a commander' and e->>'client' = 'Un Normal') = 1, 'anti-doublon : une seule ligne Gaine pour la fiche 1');
select pg_temp.verifier((select e->>'devis_reference' = 'DV-V4-11' and e->>'etat_devis' = 'en_attente' and (e->>'quantite')::numeric = 2
  from jsonb_array_elements(:'j16'::jsonb) e where e->>'id' = '01000000-0000-0000-0000-000000000111'), 'provenance : devis, numéro, état, quantité');
select pg_temp.verifier((select e->>'etat_devis' from jsonb_array_elements(:'j16'::jsonb) e where e->>'id' = '01000000-0000-0000-0000-000000000311') = 'refuse',
  'devis refusé : affiché avec son état');
select pg_temp.verifier((select (e->>'nb_a_commander')::int from jsonb_array_elements(:'js'::jsonb) e
  where e->>'evenement_id' = 'b0000000-0000-0000-0000-000000000016') = 4, 'journée 16 : 4 à commander (le refusé ne compte pas)');
select pg_temp.verifier((select count(*) from jsonb_array_elements(:'js'::jsonb) e where e->>'evenement_id' = 'b0000000-0000-0000-0000-000000000015') = 1,
  'journée du 15/10 : à l''écran');
-- Sortie vide : journée sans pièce
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select pg_temp.verifier(public.commandes_v4_journee('b0000000-0000-0000-0000-0000000000c1') = '[]'::jsonb, 'journée sans pièce : liste vide');
reset role;

-- 4. Rappel v2 : essai (LOTS-TEST, sans réservation), puis normal (hors LOTS-TEST, 15/10, 27/10, refusés, doublons)
set role service_role;
select public.rappel_commandes_reserver_v4(true) as essai \gset
reset role;
select pg_temp.verifier((select count(*) from jsonb_array_elements(:'essai'::jsonb->'pieces') e where e->>'source' = 'devis' and e->>'devis_reference' like 'DV-V4-%') = 1
  and (select e->>'devis_reference' from jsonb_array_elements(:'essai'::jsonb->'pieces') e where e->>'source' = 'devis' and e->>'devis_reference' like 'DV-V4-%') = 'DV-V4-41',
  'essai : la pièce de devis LOTS-TEST seulement');
select pg_temp.verifier(:'essai'::jsonb->>'essai' = 'true', 'essai signalé');
select count(*) as nb_rappels_avant from public.rappels_commandes \gset
set role service_role;
select public.rappel_commandes_reserver_v4(true) is not null as encore \gset
reset role;
select pg_temp.verifier((select count(*) from public.rappels_commandes) = :nb_rappels_avant, 'essai : aucun jour réservé');
delete from public.rappels_commandes;   -- base jetable du banc seulement
set role service_role;
select public.rappel_commandes_reserver_v4(false) as n1 \gset
select public.rappel_commandes_reserver(false) as v1_apres \gset
reset role;
select pg_temp.verifier(case when extract(isodow from (now() at time zone 'Europe/Paris')) <= 5 then
    (:'n1'::jsonb->>'envoyer')::boolean
    and (select count(*) from jsonb_array_elements(:'n1'::jsonb->'pieces') e where e->>'source' = 'devis' and e->>'devis_reference' like 'DV-V4-%') = 2
    and (select bool_and(e->>'devis_reference' = 'DV-V4-11') from jsonb_array_elements(:'n1'::jsonb->'pieces') e where e->>'source' = 'devis' and e->>'devis_reference' like 'DV-V4-%')
    and :'v1_apres'::jsonb->>'raison' in ('deja_envoye', 'rien_a_commander')
  else :'n1'::jsonb->>'raison' = 'jour_non_ouvre' end,
  'normal : seules les 2 pièces du devis 11 ; réservation partagée avec la v1');
delete from public.rappels_commandes;
set role service_role;
select public.rappel_commandes_reserver(false) as v1_dabord \gset
select public.rappel_commandes_reserver_v4(false) as v4_ensuite \gset
reset role;
select pg_temp.verifier(case when extract(isodow from (now() at time zone 'Europe/Paris')) <= 5 and (:'v1_dabord'::jsonb->>'envoyer')::boolean
  then :'v4_ensuite'::jsonb->>'raison' = 'deja_envoye' else true end, 'v1 puis v2 le même jour : pas de second rappel');
delete from public.rappels_commandes;

-- 5. Case de retrait : mécanicien retire, la ligne sort du rappel et du compte ; refus et erreurs
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000e';
select pg_temp.verifier((public.devis_piece_retirer('01000000-0000-0000-0000-000000000113', true)->>'retiree')::boolean, 'mécanicien retire');
select pg_temp.verifier(pg_temp.refuse($q$select public.devis_piece_retirer('01000000-0000-0000-0000-000000000115', true)$q$, 'non reliée'), 'ligne libre refusée');
select pg_temp.verifier(pg_temp.refuse(format('select public.devis_piece_retirer(%L, true)', gen_random_uuid()), 'introuvable'), 'ligne inconnue refusée');
select pg_temp.verifier(pg_temp.refuse($q$select public.devis_piece_retirer('01000000-0000-0000-0000-000000000113', null)$q$, 'Indiquez'), 'valeur nulle refusée');
select pg_temp.verifier((select (e->>'retiree')::boolean from jsonb_array_elements(public.devis_pieces_etat('f0000000-0000-0000-0000-000000000011')) e
  where e->>'devis_ligne_id' = '01000000-0000-0000-0000-000000000113'), 'état du devis : retirée');
select pg_temp.verifier(jsonb_array_length(public.devis_pieces_etat('f0000000-0000-0000-0000-000000000099')) = 0, 'devis sans fiche : état vide');
reset role;
set role anon; reset request.jwt.claim.sub;
select pg_temp.verifier(pg_temp.refuse($q$select public.devis_piece_retirer('01000000-0000-0000-0000-000000000113', false)$q$, 'permission denied'), 'anon : retrait refusé');
reset role;
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select pg_temp.verifier((select (e->>'nb_a_commander')::int from jsonb_array_elements(public.commandes_v4_journees()) e
  where e->>'evenement_id' = 'b0000000-0000-0000-0000-000000000016') = 3, 'après retrait : 3 à commander');
reset role;
set role service_role;
select public.rappel_commandes_reserver_v4(false) as n2 \gset
reset role;
select pg_temp.verifier(case when extract(isodow from (now() at time zone 'Europe/Paris')) <= 5 then
    (select count(*) from jsonb_array_elements(:'n2'::jsonb->'pieces') e where e->>'source' = 'devis' and e->>'devis_reference' like 'DV-V4-%') = 1
  else true end, 'après retrait : une seule pièce de devis rappelée');
delete from public.rappels_commandes;
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000d';
select pg_temp.verifier((public.devis_piece_retirer('01000000-0000-0000-0000-000000000113', false)->>'retiree')::boolean = false, 'dirigeant remet la pièce');
reset role;
select pg_temp.verifier((select count(*) from public.devis_pieces_retirees) = 1, 'une seule ligne de retrait, jamais supprimée');
insert into public.devis_pieces_retirees(devis_ligne_id, retiree) values ('01000000-0000-0000-0000-000000000111', true);
select pg_temp.verifier((select doublon from public.commandes_devis_source() where devis_ligne_id = '01000000-0000-0000-0000-000000000111') = 'devis'
  and (select doublon from public.commandes_devis_source() where devis_ligne_id = '01000000-0000-0000-0000-000000000121') is null,
  'ligne gardée retirée : l''autre devis reprend la place (ici refusé, affiché, non rappelé)');
update public.devis_pieces_retirees set retiree = false where devis_ligne_id = '01000000-0000-0000-0000-000000000111';
update public.v4_bascule set mise_en_service = now() + interval '1 hour';
set role service_role;
select pg_temp.verifier(case when extract(isodow from (now() at time zone 'Europe/Paris')) <= 5 then
    (select count(*) from jsonb_array_elements(public.rappel_commandes_reserver_v4(true)->'pieces') e where e->>'source' = 'devis' and e->>'devis_reference' like 'DV-V4-%') = 1
  else true end, 'essai : indépendant de la mise en service');
reset role;
delete from public.rappels_commandes;

-- 6. Inscription sans doublon : enveloppe de inscrire
select e.code as code_ent from public.entreprises e join public.evenements ev on ev.entreprise_id = e.id
  where ev.id = 'b0000000-0000-0000-0000-0000000000f1' \gset
insert into public.inscriptions(evenement_id, nom, prenom, telephone, email, code_postal, type_velo, partie_signalee, consentement_le)
  values ('b0000000-0000-0000-0000-0000000000f1', 'Deja', 'Present', '0600000000', 'Deja.Present@example.com', '69007', 'vae', 'freins', now());
select count(*) as nb_insc_avant from public.inscriptions \gset
select count(*) as nb_dem_avant from public.demandes_automatisation where type = 'client' \gset
set role anon; reset request.jwt.claim.sub;
select public.inscrire_v4(jsonb_build_object('code_entreprise', :'code_ent', 'evenement_id', 'b0000000-0000-0000-0000-0000000000f1',
  'nom', 'Doublon', 'prenom', 'Essai', 'telephone', '0600000009', 'email', 'Neuf.V4@Example.com', 'code_postal', '69007',
  'type_velo', 'vae', 'partie_signalee', 'freins', 'consentement', true))->>'site' as site1 \gset
select pg_temp.verifier(pg_temp.refuse(format($q$select public.inscrire_v4(jsonb_build_object('code_entreprise', %L, 'evenement_id',
  'b0000000-0000-0000-0000-0000000000f1', 'nom', 'Doublon', 'prenom', 'Essai', 'telephone', '0600000009', 'email', '  neuf.v4@example.COM ',
  'code_postal', '69007', 'type_velo', 'vae', 'partie_signalee', 'freins', 'consentement', true))$q$, :'code_ent'), 'déjà inscrit'),
  'second envoi du même mail (casse et espaces différents) refusé');
select pg_temp.verifier(pg_temp.refuse(format($q$select public.inscrire_v4(jsonb_build_object('code_entreprise', %L, 'evenement_id',
  'b0000000-0000-0000-0000-0000000000f1', 'nom', 'Deja', 'prenom', 'Present', 'telephone', '0600000000', 'email', 'deja.present@example.com',
  'code_postal', '69007', 'type_velo', 'vae', 'partie_signalee', 'freins', 'consentement', true))$q$, :'code_ent'), 'déjà inscrit'),
  'inscription déjà présente en base : refusée');
select public.inscrire_v4(jsonb_build_object('code_entreprise', :'code_ent', 'evenement_id', 'b0000000-0000-0000-0000-0000000000f2',
  'nom', 'Doublon', 'prenom', 'Essai', 'telephone', '0600000009', 'email', 'neuf.v4@example.com', 'code_postal', '69007',
  'type_velo', 'vae', 'partie_signalee', 'freins', 'consentement', true)) is not null as autre_journee \gset
select pg_temp.verifier(pg_temp.refuse(format($q$select public.inscrire_v4(jsonb_build_object('code_entreprise', %L, 'evenement_id',
  'pas-un-uuid', 'email', 'x@example.com'))$q$, :'code_ent'), 'Choisissez votre journée'), 'journée invalide : message de inscrire');
select pg_temp.verifier(pg_temp.refuse(format($q$select public.inscrire_v4(jsonb_build_object('code_entreprise', %L, 'evenement_id',
  'b0000000-0000-0000-0000-0000000000f1', 'nom', 'Sans', 'prenom', 'Tel', 'telephone', '12', 'email', 'autre.v4@example.com',
  'code_postal', '69007', 'type_velo', 'vae', 'partie_signalee', 'freins', 'consentement', true))$q$, :'code_ent'), '10 chiffres'),
  'contrôles de inscrire conservés');
reset role;
select pg_temp.verifier(:'site1' = 'Site V4 futur', 'première inscription acceptée (réponse de inscrire)');
select pg_temp.verifier((select count(*) from public.inscriptions) = :nb_insc_avant + 2, 'deux inscriptions créées (deux journées), aucune en double');
select pg_temp.verifier((select count(*) from public.demandes_automatisation where type = 'client') = :nb_dem_avant + 2, 'demande client créée par inscrire');
select pg_temp.verifier((select email from public.inscriptions where evenement_id = 'b0000000-0000-0000-0000-0000000000f1' and nom = 'Doublon') = 'neuf.v4@example.com',
  'email normalisé par inscrire');
-- Code d'entreprise étranger à la journée : aucun contrôle de doublon (pas de sondage), refus de inscrire
select pg_temp.verifier(pg_temp.refuse($q$select public.inscrire_v4(jsonb_build_object('code_entreprise', 'code-inconnu', 'evenement_id',
  'b0000000-0000-0000-0000-0000000000f1', 'email', 'deja.present@example.com'))$q$, 'Utilisez le lien'), 'code inconnu : message de inscrire, pas de doublon révélé');
-- Blocage des places : celui de inscrire
set role anon;
select public.inscrire_v4(jsonb_build_object('code_entreprise', :'code_ent', 'evenement_id', 'b0000000-0000-0000-0000-0000000000c1',
  'nom', 'Place', 'prenom', 'Une', 'telephone', '0600000001', 'email', 'p1@example.com', 'code_postal', '69007',
  'type_velo', 'vae', 'partie_signalee', 'freins', 'consentement', true)) is not null as p1 \gset
select pg_temp.verifier(pg_temp.refuse(format($q$select public.inscrire_v4(jsonb_build_object('code_entreprise', %L, 'evenement_id',
  'b0000000-0000-0000-0000-0000000000c1', 'nom', 'Place', 'prenom', 'Deux', 'telephone', '0600000002', 'email', 'p2@example.com',
  'code_postal', '69007', 'type_velo', 'vae', 'partie_signalee', 'freins', 'consentement', true))$q$, :'code_ent'), 'complète'),
  'journée complète : refus de inscrire');
reset role;

-- 6 bis. inscrire inchangée et appelée par l'enveloppe
select pg_temp.verifier((select prosrc like '%public.inscrire(p)%' from pg_proc where oid = 'public.inscrire_v4(jsonb)'::regprocedure), 'inscrire_v4 appelle inscrire');
select pg_temp.verifier((select prosrc not like '%inscrire_v4%' and prosrc like '%insert into public.inscriptions%' from pg_proc where oid = 'public.inscrire(jsonb)'::regprocedure), 'inscrire non remplacée');

-- 7. Résumé de facture pour TC_14 : demande 'controle' seulement ; sortie vide sinon
insert into public.factures(id, inscription_id, statut) values ('a1000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000002', 'a_valider')
  on conflict (inscription_id) do nothing;
select id as fac_v4 from public.factures where inscription_id = 'c0000000-0000-0000-0000-000000000002' \gset
delete from public.facture_lignes where facture_id = :'fac_v4';   -- base jetable du banc seulement
insert into public.facture_lignes(facture_id, libelle, quantite, prix_unitaire_ht, taux_tva, ordre) values
  (:'fac_v4', 'Gaine V4 a commander', 1, 2.08, 20, 1), (:'fac_v4', 'Main V4 (heure)', 1, 50, 20, 2);
insert into public.avis_controle(facture_id, source, niveau, message) values (:'fac_v4', 'regles', 'ok', 'Aucune anomalie.');
insert into public.demandes_automatisation(id, type, objet_id) values
  ('a2000000-0000-0000-0000-000000000001', 'controle', :'fac_v4'), ('a2000000-0000-0000-0000-000000000002', 'envoi', :'fac_v4');
set role service_role;
select public.facture_resume_v4('a2000000-0000-0000-0000-000000000001') as res \gset
select public.facture_resume_v4('a2000000-0000-0000-0000-000000000002') is null as vide_type \gset
select public.facture_resume_v4(gen_random_uuid()) is null as vide_inconnue \gset
reset role;
select pg_temp.verifier(:'res'::jsonb->>'facture_id' = :'fac_v4' and :'res'::jsonb->>'client' = 'Deux Normal'
  and (:'res'::jsonb->>'total_ht')::numeric = 52.08 and (:'res'::jsonb->>'total_ttc')::numeric = 62.50
  and jsonb_array_length(:'res'::jsonb->'avis_regles') = 1, 'résumé : client, totaux au centime, avis des règles');
select pg_temp.verifier(:'vide_type'::boolean and :'vide_inconnue'::boolean, 'résumé : vide hors demande controle');

-- 8. Verrou d'affichage lisible par l'app connectée seulement
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000e';
select pg_temp.verifier(public.v4_bascule_etat() = false, 'verrou lu : fermé');
reset role;


-- 9. Brouillons (0011, décision 4 de G_R) : écran avec l'état « brouillon » et la date du devis, d'après les lignes actuelles ;
--    rappel : brouillons créés le jour même seulement ; brouillons anciens visibles sans rappel ; a_relire = brouillon
insert into public.evenements(id, entreprise_id, site, date_intervention)
  select 'b0000000-0000-0000-0000-0000000000b1', id, 'Site V4 brouillons', current_date + 5 from public.entreprises order by created_at limit 1;
insert into public.inscriptions(id, evenement_id, nom, prenom, telephone, email, code_postal, type_velo, partie_signalee, consentement_le) values
  ('c0000000-0000-0000-0000-0000000000b1', 'b0000000-0000-0000-0000-0000000000b1', 'Brouillon', 'Jour', '0600000000', 'bj@example.com', '69007', 'vae', 'freins', now()),
  ('c0000000-0000-0000-0000-0000000000b2', 'b0000000-0000-0000-0000-0000000000b1', 'Brouillon', 'Ancien', '0600000000', 'ba@example.com', '69007', 'vae', 'freins', now()),
  ('c0000000-0000-0000-0000-0000000000b3', 'b0000000-0000-0000-0000-0000000000b1', 'Relire', 'Jour', '0600000000', 'rj@example.com', '69007', 'vae', 'freins', now());
insert into public.fiches(id, inscription_id, statut) values
  ('d0000000-0000-0000-0000-0000000000b1', 'c0000000-0000-0000-0000-0000000000b1', 'en_cours'),
  ('d0000000-0000-0000-0000-0000000000b2', 'c0000000-0000-0000-0000-0000000000b2', 'en_cours'),
  ('d0000000-0000-0000-0000-0000000000b3', 'c0000000-0000-0000-0000-0000000000b3', 'en_cours');
update public.v4_bascule set mise_en_service = now() - interval '3 days';   -- base jetable du banc seulement
insert into public.devis(id, fiche_id, reference, statut, created_at) values
  ('f0000000-0000-0000-0000-0000000000b1', 'd0000000-0000-0000-0000-0000000000b1', 'DV-V4B-JOUR', 'brouillon', now()),
  ('f0000000-0000-0000-0000-0000000000b2', 'd0000000-0000-0000-0000-0000000000b2', 'DV-V4B-ANCIEN', 'brouillon', now() - interval '2 days'),
  ('f0000000-0000-0000-0000-0000000000b3', 'd0000000-0000-0000-0000-0000000000b3', 'DV-V4B-RELIRE', 'a_relire', now());
insert into public.devis_lignes(id, devis_id, piece_id, libelle, quantite, prix_unitaire_ht) values
  ('01000000-0000-0000-0000-0000000000b1', 'f0000000-0000-0000-0000-0000000000b1', 'a0000000-0000-0000-0000-0000000000a1', 'Gaine V4 a commander', 1, 3),
  ('01000000-0000-0000-0000-0000000000b4', 'f0000000-0000-0000-0000-0000000000b1', 'a0000000-0000-0000-0000-0000000000a3', 'Chambre V4 inconnue', 1, 7),
  ('01000000-0000-0000-0000-0000000000b2', 'f0000000-0000-0000-0000-0000000000b2', 'a0000000-0000-0000-0000-0000000000a1', 'Gaine V4 a commander', 1, 3),
  ('01000000-0000-0000-0000-0000000000b3', 'f0000000-0000-0000-0000-0000000000b3', 'a0000000-0000-0000-0000-0000000000a3', 'Chambre V4 inconnue', 1, 7);
update public.devis_lignes set created_at = now() - interval '2 days' where id = '01000000-0000-0000-0000-0000000000b2';
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select public.commandes_v4_journee('b0000000-0000-0000-0000-0000000000b1') as jb \gset
reset role;
select pg_temp.verifier(jsonb_array_length(:'jb'::jsonb) = 4, 'brouillons : 4 lignes à l''écran (jour, ancien, à relire)');
select pg_temp.verifier((select bool_and(e->>'etat_devis' = 'brouillon' and e->>'devis_date' is not null) from jsonb_array_elements(:'jb'::jsonb) e),
  'brouillons : état brouillon et date du devis');
select pg_temp.verifier(exists (select 1 from jsonb_array_elements(:'jb'::jsonb) e where e->>'devis_reference' = 'DV-V4B-ANCIEN'), 'brouillon ancien : visible à l''écran');
set role service_role;
select public.rappel_commandes_reserver_v4(false) as rb \gset
reset role;
select pg_temp.verifier(case when extract(isodow from (now() at time zone 'Europe/Paris')) <= 5 then
    (select count(*) from jsonb_array_elements(:'rb'::jsonb->'pieces') e where e->>'devis_reference' like 'DV-V4B-%') = 3
    and not exists (select 1 from jsonb_array_elements(:'rb'::jsonb->'pieces') e where e->>'devis_reference' = 'DV-V4B-ANCIEN')
  else true end, 'rappel : brouillons du jour (2 lignes) et à relire du jour (1), jamais le brouillon ancien');
delete from public.rappels_commandes;
-- une pièce enlevée du brouillon disparaît de la liste (lignes actuelles)
delete from public.devis_lignes where id = '01000000-0000-0000-0000-0000000000b4';   -- geste permis à l'app sur un brouillon (base jetable)
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select pg_temp.verifier(jsonb_array_length(public.commandes_v4_journee('b0000000-0000-0000-0000-0000000000b1')) = 3, 'pièce enlevée du brouillon : sortie de la liste');
reset role;
-- le mécanicien retire une pièce de brouillon par la case : elle sort du rappel
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000e';
select pg_temp.verifier((public.devis_piece_retirer('01000000-0000-0000-0000-0000000000b1', true)->>'retiree')::boolean, 'mécanicien retire une pièce de brouillon');
reset role;
set role service_role;
select pg_temp.verifier(case when extract(isodow from (now() at time zone 'Europe/Paris')) <= 5 then
    not exists (select 1 from jsonb_array_elements(public.rappel_commandes_reserver_v4(false)->'pieces') e where e->>'devis_reference' = 'DV-V4B-JOUR')
  else true end, 'pièce retirée du brouillon : plus rappelée');
reset role;
delete from public.rappels_commandes;
-- priorité anti-doublon : un devis envoyé l'emporte sur un brouillon de la même fiche
insert into public.devis(id, fiche_id, reference, statut) values ('f0000000-0000-0000-0000-0000000000b9', 'd0000000-0000-0000-0000-0000000000b2', 'DV-V4B-ENVOYE', 'envoye');
insert into public.devis_lignes(id, devis_id, piece_id, libelle, quantite) values ('01000000-0000-0000-0000-0000000000b9', 'f0000000-0000-0000-0000-0000000000b9', 'a0000000-0000-0000-0000-0000000000a1', 'Gaine V4 a commander', 1);
select pg_temp.verifier((select doublon from public.commandes_devis_source() where devis_ligne_id = '01000000-0000-0000-0000-0000000000b2') = 'devis'
  and (select doublon from public.commandes_devis_source() where devis_ligne_id = '01000000-0000-0000-0000-0000000000b9') is null,
  'anti-doublon : le devis envoyé l''emporte sur le brouillon');

\echo BANC V4 : TOUTES LES ASSERTIONS PASSENT
