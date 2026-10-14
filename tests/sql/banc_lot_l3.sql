-- Banc du lot L3 (accès des prestataires, migration 0007), joué sur la base du banc après les bancs existants.
-- Comptes du banc de liaison : dirigeant ...0d, mécanicien ...0e, atelier ...0a.
\set ON_ERROR_STOP 1
\set QUIET 1
create function pg_temp.verifier(c boolean, m text) returns void language plpgsql as $$ begin if c is not true then raise exception 'ASSERTION : %', m; end if; end $$;
create function pg_temp.refuse(q text, attendu text) returns boolean language plpgsql as $$
begin execute q; return false; exception when others then
  if sqlerrm not like '%' || attendu || '%' then raise exception 'ASSERTION : message inattendu « % » pour %', sqlerrm, q; end if; return true; end $$;
grant execute on function pg_temp.verifier(boolean, text), pg_temp.refuse(text, text) to anon, authenticated, service_role;

-- 0. Structure : aucun déclencheur ni colonne neuve sur acces ; aucun rôle neuf ; droits
select pg_temp.verifier((select count(*) from pg_trigger where tgrelid = 'public.acces'::regclass and not tgisinternal) = 0, 'aucun déclencheur sur acces');
select pg_temp.verifier((select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'acces') = 7, 'colonnes de acces inchangées');
select pg_temp.verifier((select count(*) from pg_roles where rolname in ('anon','authenticated','service_role')) = 3, 'rôles du bouchon');
select pg_temp.verifier(not has_function_privilege('anon', 'public.acces_donner(text,public.app_role,timestamptz)', 'execute'), 'anon sans EXECUTE donner');
select pg_temp.verifier(not has_function_privilege('authenticated', 'public.acces_protege(text,public.app_role)', 'execute'), 'acces_protege interne');

-- Accès des correcteurs (comme en base réelle), expirant le 2026-10-26 22:59 UTC
insert into public.acces(email, role, expire_le) values
  ('gabriel.roulon+correcteur@gmail.com', 'dirigeant', '2026-10-26 22:59:00+00'),
  ('gabriel.roulon+correcteur.meca@gmail.com', 'mecanicien', '2026-10-26 22:59:00+00');
select id as id_dir from public.acces where email = 'dirigeant@example.com' \gset
select id as id_corr from public.acces where email = 'gabriel.roulon+correcteur.meca@gmail.com' \gset
select count(*) as nb_avant from public.acces \gset

-- 1. Refus : anon, mécanicien, atelier
set role anon; reset request.jwt.claim.sub;
select pg_temp.verifier(pg_temp.refuse('select public.acces_liste()', 'permission denied'), 'anon : liste refusée');
reset role;
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000e';
select pg_temp.verifier(pg_temp.refuse('select public.acces_liste()', 'Accès refusé'), 'mécanicien : liste refusée');
select pg_temp.verifier(pg_temp.refuse($q$select public.acces_donner('x@example.com', 'atelier', now() + interval '1 day')$q$, 'Accès refusé'), 'mécanicien : donner refusé');
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select pg_temp.verifier(pg_temp.refuse(format('select public.acces_retirer(%L)', :'id_corr'), 'Accès refusé'), 'atelier : retirer refusé');
reset role;

-- 2. Le dirigeant : liste, donner, retirer, redonner (même ligne)
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000d';
select pg_temp.verifier(jsonb_array_length(public.acces_liste()) = :nb_avant, 'liste complète');
select pg_temp.verifier(public.acces_liste()->0->>'role' = 'dirigeant' and (public.acces_liste()->0->>'protege')::boolean, 'dirigeant en tête, protégé');
select (public.acces_donner('  Presta@Example.com ', 'mecanicien', now() + interval '10 days')->>'id') as id_presta \gset
select pg_temp.verifier((select email from public.acces where id = :'id_presta') = 'presta@example.com', 'email en minuscules');
select pg_temp.verifier(public.acces_retirer(:'id_presta')->>'action' = 'retire', 'retiré');
select pg_temp.verifier(public.acces_retirer(:'id_presta')->>'action' = 'deja_retire', 'retrait idempotent');
reset role;
select pg_temp.verifier((select revoque_le is not null from public.acces where id = :'id_presta'), 'revoque_le posé');
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000d';
select pg_temp.verifier(public.acces_donner('presta@example.com', 'mecanicien', now() + interval '20 days')->>'action' = 'redonne', 'redonné');
reset role;
select pg_temp.verifier((select count(*) from public.acces where email = 'presta@example.com') = 1, 'redonner : aucun second INSERT');
select pg_temp.verifier((select revoque_le is null and expire_le > now() + interval '19 days' from public.acces where id = :'id_presta'), 'réactivé avec nouvelle expiration');

-- 3. Interdits : rôle dirigeant, date passée ou absente, email invalide, accès protégés
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000d';
select pg_temp.verifier(pg_temp.refuse($q$select public.acces_donner('x@example.com', 'dirigeant', now() + interval '1 day')$q$, 'Rôle possible'), 'jamais le rôle dirigeant');
select pg_temp.verifier(pg_temp.refuse($q$select public.acces_donner('x@example.com', 'atelier', now() - interval '1 day')$q$, 'date d''expiration'), 'date passée refusée');
select pg_temp.verifier(pg_temp.refuse($q$select public.acces_donner('x@example.com', 'atelier', null)$q$, 'date d''expiration'), 'date absente refusée');
select pg_temp.verifier(pg_temp.refuse($q$select public.acces_donner('pas-un-email', 'atelier', now() + interval '1 day')$q$, 'email'), 'email invalide');
select pg_temp.verifier(pg_temp.refuse(format('select public.acces_retirer(%L)', :'id_dir'), 'protégé'), 'dirigeant : retrait refusé');
select pg_temp.verifier(pg_temp.refuse(format('select public.acces_retirer(%L)', :'id_corr'), 'protégé'), 'correcteur : retrait refusé');
select pg_temp.verifier(pg_temp.refuse($q$select public.acces_donner('GABRIEL.ROULON+CORRECTEUR.MECA@gmail.com', 'mecanicien', '2026-10-20 10:00+00')$q$, 'protégé'), 'correcteur : raccourcir refusé (lower)');
select pg_temp.verifier(public.acces_donner('gabriel.roulon+correcteur.meca@gmail.com', 'mecanicien', '2026-10-26 22:59:00+00')->>'action' = 'modifie', 'correcteur : même date acceptée');
reset role;
select pg_temp.verifier((select revoque_le is null and expire_le = '2026-10-26 22:59:00+00' from public.acces where id = :'id_corr'), 'correcteur intact');
select pg_temp.verifier((select count(*) from public.acces where role = 'dirigeant' and revoque_le is not null) = 0, 'aucun dirigeant retiré');

-- 3 bis. Accès protégé retiré (hors écran, par exemple avant L3) : il peut être redonné, sans raccourcir
update public.acces set revoque_le = now() where id = :'id_corr';
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000d';
select pg_temp.verifier(pg_temp.refuse($q$select public.acces_donner('gabriel.roulon+correcteur.meca@gmail.com', 'mecanicien', '2026-10-20 10:00+00')$q$, 'protégé'), 'correcteur retiré : raccourcir refusé');
select pg_temp.verifier(public.acces_donner('gabriel.roulon+correcteur.meca@gmail.com', 'mecanicien', '2026-10-26 22:59:00+00')->>'action' = 'redonne', 'correcteur retiré : redonné');
reset role;
select pg_temp.verifier((select revoque_le is null from public.acces where id = :'id_corr'), 'correcteur réactivé');

-- 4. Aucune suppression : nombre de lignes = avant + 1 (presta)
select pg_temp.verifier((select count(*) from public.acces) = :nb_avant + 1, 'aucune suppression, un seul ajout');

\echo BANC L3 : TOUTES LES ASSERTIONS PASSENT
