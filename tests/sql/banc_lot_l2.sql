-- Banc du lot L2 (statistiques par entreprise, migration 0006), joué sur la base du banc après les bancs existants.
\set ON_ERROR_STOP 1
\set QUIET 1
create function pg_temp.verifier(c boolean, m text) returns void language plpgsql as $$ begin if c is not true then raise exception 'ASSERTION : %', m; end if; end $$;
create function pg_temp.refuse(q text, attendu text) returns boolean language plpgsql as $$
begin execute q; return false; exception when others then
  if sqlerrm not like '%' || attendu || '%' then raise exception 'ASSERTION : message inattendu « % » pour %', sqlerrm, q; end if; return true; end $$;
grant execute on function pg_temp.verifier(boolean, text), pg_temp.refuse(text, text) to anon, authenticated, service_role;

-- 0. Structure : security_invoker, droits
select pg_temp.verifier((select 'security_invoker=on' = any(reloptions) from pg_class where oid = 'public.stats_entreprises'::regclass), 'security_invoker = on');
select pg_temp.verifier(not has_table_privilege('anon', 'public.stats_entreprises', 'select'), 'anon sans SELECT');
select pg_temp.verifier(not has_table_privilege('authenticated', 'public.stats_entreprises', 'insert,update,delete'), 'authenticated en lecture seule');

-- 1. Refus sans session : anon refusé ; compte connecté sans rôle : aucune ligne (règles d'accès des tables)
set role anon; reset request.jwt.claim.sub;
select pg_temp.verifier(pg_temp.refuse('select * from public.stats_entreprises', 'permission denied'), 'anon refusé');
reset role;
set role authenticated; reset request.jwt.claim.sub;
select pg_temp.verifier((select count(*) from public.stats_entreprises) = 0, 'sans rôle : aucune ligne');
reset role;

-- 2. Le dirigeant voit les faits : vélos = fiches, organes en défaut, pièces changées
select count(*) as nb_fiches from public.fiches f join public.inscriptions i on i.id = f.inscription_id where i.nom not ilike 'LOTS-TEST%' \gset
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000d';
select pg_temp.verifier((select count(*) from public.stats_entreprises where genre = 'velo') = :nb_fiches, 'un vélo par fiche');
select pg_temp.verifier((select count(*) from public.stats_entreprises where genre = 'organe' and libelle = 'Frein avant') >= 1, 'organe en défaut : Frein avant');
select pg_temp.verifier((select sum(quantite) from public.stats_entreprises where genre = 'piece' and libelle like 'Câble%') >= 1, 'pièce changée : câble');
select count(*) as avant_test from public.stats_entreprises \gset
reset role;

-- 3. Données LOTS-TEST exclues
insert into public.inscriptions(id, evenement_id, nom, prenom, telephone, email, code_postal, type_velo, partie_signalee, consentement_le)
  select '50000000-0000-0000-0000-000000000001', id, 'LOTS-TEST', 'Stat', '0600000000', 's@example.com', '69007', 'vae', 'freins', now() from public.evenements limit 1;
insert into public.fiches(id, inscription_id, statut) values ('50000000-0000-0000-0000-000000000002', '50000000-0000-0000-0000-000000000001', 'terminee');
insert into public.fiche_points(fiche_id, groupe, point, etat) values ('50000000-0000-0000-0000-000000000002', 'Cadre', 'Fissure', 'a_changer');
insert into public.pieces_posees(fiche_id, libelle, quantite) values ('50000000-0000-0000-0000-000000000002', 'Pneu', 1);
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000d';
select pg_temp.verifier((select count(*) from public.stats_entreprises) = :avant_test, 'LOTS-TEST exclu');
reset role;

-- 4. Le mécanicien et l'atelier lisent aussi (règles des tables : les trois rôles lisent fiches et points)
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select pg_temp.verifier((select count(*) from public.stats_entreprises) = :avant_test, 'atelier : même lecture');
reset role;

\echo BANC L2 : TOUTES LES ASSERTIONS PASSENT
