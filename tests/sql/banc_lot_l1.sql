-- Banc du lot L1 (pièces à commander, migration 0005), joué sur la base du banc après banc_liaison.sql et banc_devis.sql.
-- Données du banc de liaison : dirigeant ...0d, mécanicien ...0e, atelier ...0a ; une fiche terminée avec une pièce CAB à commander.
\set ON_ERROR_STOP 1
\set QUIET 1
create function pg_temp.verifier(c boolean, m text) returns void language plpgsql as $$ begin if c is not true then raise exception 'ASSERTION : %', m; end if; end $$;
create function pg_temp.refuse(q text, attendu text) returns boolean language plpgsql as $$
begin execute q; return false; exception when others then
  if sqlerrm not like '%' || attendu || '%' then raise exception 'ASSERTION : message inattendu « % » pour %', sqlerrm, q; end if; return true; end $$;
grant execute on function pg_temp.verifier(boolean, text), pg_temp.refuse(text, text) to anon, authenticated, service_role;

-- 0. Structure : aucune clé étrangère et aucun déclencheur sur les tables neuves ; RLS active ; anon sans droit
select pg_temp.verifier((select count(*) from pg_constraint where contype = 'f'
  and conrelid in ('public.commandes_pieces'::regclass, 'public.rappels_commandes'::regclass, 'public.lots_parametres'::regclass)) = 0, 'aucune clé étrangère');
select pg_temp.verifier((select count(*) from pg_trigger where not tgisinternal
  and tgrelid in ('public.commandes_pieces'::regclass, 'public.rappels_commandes'::regclass, 'public.lots_parametres'::regclass)) = 0, 'aucun déclencheur');
select pg_temp.verifier((select bool_and(relrowsecurity) from pg_class where oid in
  ('public.commandes_pieces'::regclass, 'public.rappels_commandes'::regclass, 'public.lots_parametres'::regclass)), 'RLS active');
select pg_temp.verifier(not has_table_privilege('anon', 'public.commandes_pieces', 'select,insert,update,delete'), 'anon sans droit sur commandes_pieces');
select pg_temp.verifier(not has_table_privilege('authenticated', 'public.commandes_pieces', 'select,insert,update,delete'), 'authenticated sans droit direct');
select pg_temp.verifier(not has_function_privilege('anon', 'public.commandes_pieces_marquer(uuid,boolean)', 'execute'), 'anon sans EXECUTE marquer');
select pg_temp.verifier(not has_function_privilege('authenticated', 'public.rappel_commandes_reserver(boolean)', 'execute'), 'authenticated sans EXECUTE rappel');
select pg_temp.verifier(not has_function_privilege('authenticated', 'public.commandes_pieces_source()', 'execute'), 'authenticated sans EXECUTE source');

select ev.id as ev_id from public.evenements ev order by created_at limit 1 \gset
select pp.id as pp_cab from public.pieces_posees pp where a_commander limit 1 \gset
select pp.id as pp_mo from public.pieces_posees pp where not a_commander limit 1 \gset

-- 1. Refus sans session (anon) et refus du mécanicien
set role anon; reset request.jwt.claim.sub;
select pg_temp.verifier(pg_temp.refuse('select public.commandes_pieces_journees()', 'permission denied'), 'anon : journees refusé');
select pg_temp.verifier(pg_temp.refuse('select * from public.commandes_pieces', 'permission denied'), 'anon : table refusée');
select pg_temp.verifier(pg_temp.refuse('select public.rappel_commandes_reserver(false)', 'permission denied'), 'anon : rappel refusé');
reset role;
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000e';
select pg_temp.verifier(pg_temp.refuse('select public.commandes_pieces_journees()', 'Accès refusé'), 'mécanicien : journees refusé');
select pg_temp.verifier(pg_temp.refuse(format('select public.commandes_pieces_marquer(%L, true)', :'pp_cab'), 'Accès refusé'), 'mécanicien : marquer refusé');
reset role;

-- 2. L'atelier voit la journée et la pièce non commandée
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select pg_temp.verifier(jsonb_array_length(public.commandes_pieces_journees()) = 1, 'une journée');
select pg_temp.verifier((public.commandes_pieces_journees()->0->>'nb_a_commander')::int = 1, 'une pièce à commander');
select pg_temp.verifier((public.commandes_pieces_journee(:'ev_id')->0->>'commandee')::boolean = false, 'non commandée');
select pg_temp.verifier(pg_temp.refuse(format('select public.commandes_pieces_marquer(%L, true)', :'pp_mo'), 'non marquée à commander'), 'pièce non à commander refusée');
select pg_temp.verifier(pg_temp.refuse(format('select public.commandes_pieces_marquer(%L, true)', gen_random_uuid()), 'introuvable'), 'pièce inconnue refusée');
select pg_temp.verifier(pg_temp.refuse(format('select public.commandes_pieces_marquer(%L, null)', :'pp_cab'), 'Indiquez'), 'valeur nulle refusée');
reset role;

-- 3. Rappel (clé de service) : jour ouvré, une pièce, puis « déjà envoyé » ; jour non ouvré sinon
set role service_role;
select public.rappel_commandes_reserver(false) as r1 \gset
select public.rappel_commandes_reserver(false) as r2 \gset
reset role;
select pg_temp.verifier(case when extract(isodow from (now() at time zone 'Europe/Paris')) <= 5
  then (:'r1'::jsonb->>'envoyer')::boolean and (:'r1'::jsonb->>'nb_pieces')::int = 1 and :'r2'::jsonb->>'raison' = 'deja_envoye'
  else :'r1'::jsonb->>'raison' = 'jour_non_ouvre' end, 'rappel : un seul par jour');
select pg_temp.verifier((select count(*) from public.rappels_commandes) <= 1, 'au plus une ligne de rappel');

-- 4. L'atelier coche : la pièce sort du rappel ; le dirigeant décoche puis recoche
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select pg_temp.verifier((public.commandes_pieces_marquer(:'pp_cab', true)->>'ok')::boolean, 'atelier coche');
select pg_temp.verifier((public.commandes_pieces_journee(:'ev_id')->0->>'commandee')::boolean, 'commandée');
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000d';
select pg_temp.verifier((public.commandes_pieces_marquer(:'pp_cab', false)->>'commandee')::boolean = false, 'dirigeant décoche');
select pg_temp.verifier((public.commandes_pieces_marquer(:'pp_cab', true)->>'commandee')::boolean, 'dirigeant recoche');
reset role;
select pg_temp.verifier((select count(*) from public.commandes_pieces) = 1, 'une seule ligne par pièce');
delete from public.rappels_commandes;  -- base jetable du banc seulement
set role service_role;
select pg_temp.verifier(public.rappel_commandes_reserver(false)->>'raison' in ('rien_a_commander', 'jour_non_ouvre'), 'pièce commandée : rien à rappeler');
reset role;

-- 5. Exclusions : LOTS-TEST, journées du 15/10 et du 27/10, fiches terminées avant la mise en service ; fiche en cours non cochable
insert into public.evenements(id, entreprise_id, site, date_intervention)
  select x.id, e.id, x.site, x.d from public.entreprises e,
  (values ('10000000-0000-0000-0000-000000000016'::uuid, 'Site 16', date '2026-10-16'),
          ('10000000-0000-0000-0000-000000000015'::uuid, 'Site 15', date '2026-10-15'),
          ('10000000-0000-0000-0000-000000000027'::uuid, 'Site 27', date '2026-10-27'),
          ('10000000-0000-0000-0000-000000000099'::uuid, 'Site en cours', date '2026-10-16')) x(id, site, d) limit 4;
insert into public.inscriptions(id, evenement_id, nom, prenom, telephone, email, code_postal, type_velo, partie_signalee, consentement_le) values
  ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000016', 'LOTS-TEST', 'Essai', '0600000000', 'lots@example.com', '69007', 'vae', 'freins', now()),
  ('20000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000015', 'Quinze', 'Alex', '0600000000', 'q@example.com', '69007', 'vae', 'freins', now()),
  ('20000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000027', 'Vingtsept', 'Alex', '0600000000', 'v@example.com', '69007', 'vae', 'freins', now()),
  ('20000000-0000-0000-0000-000000000004', '10000000-0000-0000-0000-000000000016', 'Normal', 'Alex', '0600000000', 'n@example.com', '69007', 'vae', 'freins', now()),
  ('20000000-0000-0000-0000-000000000005', '10000000-0000-0000-0000-000000000099', 'Encours', 'Alex', '0600000000', 'e@example.com', '69007', 'vae', 'freins', now());
insert into public.fiches(id, inscription_id, statut, termine_le) values
  ('30000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'terminee', now()),
  ('30000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000002', 'terminee', now()),
  ('30000000-0000-0000-0000-000000000003', '20000000-0000-0000-0000-000000000003', 'terminee', now()),
  ('30000000-0000-0000-0000-000000000004', '20000000-0000-0000-0000-000000000004', 'terminee', now()),
  ('30000000-0000-0000-0000-000000000005', '20000000-0000-0000-0000-000000000005', 'en_cours', null);
insert into public.pieces_posees(id, fiche_id, libelle, quantite, a_commander) values
  ('40000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', 'Pneu LOTS-TEST', 1, true),
  ('40000000-0000-0000-0000-000000000002', '30000000-0000-0000-0000-000000000002', 'Pneu du 15', 1, true),
  ('40000000-0000-0000-0000-000000000003', '30000000-0000-0000-0000-000000000003', 'Pneu du 27', 1, true),
  ('40000000-0000-0000-0000-000000000004', '30000000-0000-0000-0000-000000000004', 'Pneu normal', 2, true),
  ('40000000-0000-0000-0000-000000000005', '30000000-0000-0000-0000-000000000005', 'Pneu en cours', 1, true);
set role service_role;
select public.rappel_commandes_reserver(true) as essai \gset
select public.rappel_commandes_reserver(false) as normal \gset
reset role;
select pg_temp.verifier((:'essai'::jsonb->>'nb_pieces')::int = 1 and :'essai'::jsonb->'pieces'->0->>'libelle' = 'Pneu LOTS-TEST', 'essai : LOTS-TEST seulement');
select pg_temp.verifier(case when extract(isodow from (now() at time zone 'Europe/Paris')) <= 5
  then (:'normal'::jsonb->>'nb_pieces')::int = 1 and :'normal'::jsonb->'pieces'->0->>'libelle' = 'Pneu normal'
       and (:'normal'::jsonb->'pieces'->0->>'quantite')::numeric = 2
  else :'normal'::jsonb->>'raison' = 'jour_non_ouvre' end, 'normal : hors LOTS-TEST, 15/10, 27/10, fiche en cours');
select pg_temp.verifier((select count(*) from public.rappels_commandes) <= 1, 'essai ne réserve pas le jour');
delete from public.rappels_commandes;
update public.lots_parametres set valeur = now() + interval '1 hour' where cle = 'l1_mise_en_service';
set role service_role;
select pg_temp.verifier(public.rappel_commandes_reserver(false)->>'raison' in ('rien_a_commander', 'jour_non_ouvre'), 'fiches antérieures à la mise en service ignorées');
reset role;
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select pg_temp.verifier(pg_temp.refuse($q$select public.commandes_pieces_marquer('40000000-0000-0000-0000-000000000005', true)$q$, 'fiche non terminée'), 'fiche en cours : refus');
select pg_temp.verifier((public.commandes_pieces_marquer('40000000-0000-0000-0000-000000000001', true)->>'ok')::boolean, 'LOTS-TEST cochée');
reset role;
set role service_role;
select pg_temp.verifier(public.rappel_commandes_reserver(true)->>'raison' = 'rien_a_commander', 'essai vide une fois LOTS-TEST cochée');
reset role;

-- 6. Suppression d'une pièce dans une fiche en cours toujours possible (aucune clé étrangère ne la bloque)
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000e';
delete from public.pieces_posees where id = '40000000-0000-0000-0000-000000000005';
reset role;
select pg_temp.verifier(not exists (select 1 from public.pieces_posees where id = '40000000-0000-0000-0000-000000000005'), 'suppression en fiche en cours');

\echo BANC L1 : TOUTES LES ASSERTIONS PASSENT
