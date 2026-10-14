-- Banc du lot STOCK (migration 0009), joué sur la base du banc après banc_liaison.sql, banc_devis.sql et les bancs L1 à L3.
-- Données du banc de liaison : dirigeant ...0d, mécanicien ...0e, atelier ...0a ; catalogue CAB et MO ; une facture validée (Câble, Main d'oeuvre).
\set ON_ERROR_STOP 1
\set QUIET 1
create function pg_temp.verifier(c boolean, m text) returns void language plpgsql as $$ begin if c is not true then raise exception 'ASSERTION : %', m; end if; end $$;
create function pg_temp.refuse(q text, attendu text) returns boolean language plpgsql as $$
begin execute q; return false; exception when others then
  if sqlerrm not like '%' || attendu || '%' then raise exception 'ASSERTION : message inattendu « % » pour %', sqlerrm, q; end if; return true; end $$;
-- Retire axonaut_produit_id des lignes (comparaison au contrat de donnees_demande)
create function pg_temp.sans_id(v jsonb) returns jsonb language sql as $$
  select case when v ? 'lignes' then jsonb_set(v, '{lignes}', coalesce((select jsonb_agg(e - 'axonaut_produit_id' order by n)
    from jsonb_array_elements(v->'lignes') with ordinality x(e, n)), '[]'::jsonb)) else v end $$;
grant execute on function pg_temp.verifier(boolean, text), pg_temp.refuse(text, text), pg_temp.sans_id(jsonb) to anon, authenticated, service_role;

-- 0. Structure : aucune clé étrangère, aucun déclencheur, RLS active, aucun droit direct pour anon et authenticated
select pg_temp.verifier((select count(*) from pg_constraint where contype = 'f'
  and conrelid in ('public.catalogue_axonaut'::regclass, 'public.stock_axonaut'::regclass)) = 0, 'aucune clé étrangère');
select pg_temp.verifier((select count(*) from pg_trigger where not tgisinternal
  and tgrelid in ('public.catalogue_axonaut'::regclass, 'public.stock_axonaut'::regclass)) = 0, 'aucun déclencheur');
select pg_temp.verifier((select bool_and(relrowsecurity) from pg_class where oid in
  ('public.catalogue_axonaut'::regclass, 'public.stock_axonaut'::regclass)), 'RLS active');
select pg_temp.verifier(not has_table_privilege(r, t, 'select,insert,update,delete'), format('%s sans droit sur %s', r, t))
  from unnest(array['anon','authenticated']) r, unnest(array['public.catalogue_axonaut','public.stock_axonaut']) t;
select pg_temp.verifier(not has_function_privilege(r, f, 'execute'), format('%s sans EXECUTE %s', r, f))
  from unnest(array['anon','authenticated']) r,
       unnest(array['public.axonaut_produit_ligne(text)','public.donnees_demande_v2(text,uuid)','public.reserver_demandes_v2(integer)',
                     'public.catalogue_axonaut_liste()','public.stock_axonaut_ecrire(jsonb)']) f;
select pg_temp.verifier(not has_function_privilege('anon', 'public.stock_pieces()', 'execute'), 'anon sans EXECUTE stock_pieces');
select pg_temp.verifier(has_function_privilege('authenticated', 'public.stock_pieces()', 'execute'), 'authenticated EXECUTE stock_pieces');

select fa.id as fa_validee from public.factures fa where fa.statut = 'validee' limit 1 \gset
select pc.id as pc_cab from public.pieces_catalogue pc where reference = 'CAB' \gset
select pc.id as pc_mo from public.pieces_catalogue pc where reference = 'MO' \gset

-- 1. Sans correspondance : même contrat, identifiant vide dans chaque ligne d'envoi
set role service_role;
select pg_temp.verifier(pg_temp.sans_id(public.donnees_demande_v2('envoi', :'fa_validee')) = public.donnees_demande('envoi', :'fa_validee'), 'envoi : même contrat sans correspondance');
select pg_temp.verifier((select bool_and(e->>'axonaut_produit_id' = '') from jsonb_array_elements(public.donnees_demande_v2('envoi', :'fa_validee')->'lignes') e), 'envoi : identifiant vide');
select pg_temp.verifier(public.catalogue_axonaut_liste() = '[]'::jsonb, 'liste vide');

-- 2. Correspondance : contraintes
insert into public.catalogue_axonaut (piece_id, role, reference, libelle, axonaut_produit_id, suivi_stock) values
  (:'pc_cab', 'piece', 'CAB', 'Câble de frein inox 1,6 mm 1,80 m', '1001', true),
  (:'pc_mo', 'main_oeuvre', 'MO', 'Main d''oeuvre (heure)', '1002', false),
  (null, 'generique', 'LIBRE', 'Ligne libre (produit générique)', '1003', false);
select pg_temp.verifier(pg_temp.refuse($q$insert into public.catalogue_axonaut (piece_id, role, reference, libelle, axonaut_produit_id, suivi_stock)
  values (null, 'generique', 'LIBRE2', 'x', '1004', false)$q$, 'duplicate key'), 'un seul générique');
select pg_temp.verifier(pg_temp.refuse($q$insert into public.catalogue_axonaut (piece_id, role, reference, libelle, axonaut_produit_id, suivi_stock)
  values (gen_random_uuid(), 'main_oeuvre', 'MO2', 'x', '1005', true)$q$, 'check constraint'), 'main d''oeuvre sans stock');
select pg_temp.verifier(pg_temp.refuse($q$insert into public.catalogue_axonaut (piece_id, role, reference, libelle, axonaut_produit_id, suivi_stock)
  values (gen_random_uuid(), 'piece', 'X', 'x', 'abc', true)$q$, 'check constraint'), 'identifiant numérique');

-- 3. Avec correspondance : identifiants par ligne, reste du contrat identique ; ligne libre vers le générique
select pg_temp.verifier(pg_temp.sans_id(public.donnees_demande_v2('envoi', :'fa_validee')) = public.donnees_demande('envoi', :'fa_validee'), 'envoi : même contrat avec correspondance');
select pg_temp.verifier((select string_agg(e->>'axonaut_produit_id', ',' order by n) from jsonb_array_elements(public.donnees_demande_v2('envoi', :'fa_validee')->'lignes') with ordinality x(e, n)) = '1001,1002', 'envoi : identifiants dans l''ordre des lignes');
select pg_temp.verifier(public.axonaut_produit_ligne('Pneu LOTS-TEST') = '1003', 'ligne libre : générique');
select pg_temp.verifier(public.axonaut_produit_ligne('Câble de frein inox 1,6 mm 1,80 m ') = '1003', 'libellé retouché : générique (limite écrite)');
select pg_temp.verifier(public.donnees_demande_v2(t, o) is not distinct from public.donnees_demande(t, o), 'type ' || t || ' inchangé')
  from (select d.type t, d.objet_id o from public.demandes_automatisation d where d.type <> 'envoi') x;
select pg_temp.verifier(public.donnees_demande_v2('envoi', gen_random_uuid()) is null, 'envoi inconnu : null');
select pg_temp.verifier(jsonb_array_length(public.catalogue_axonaut_liste()) = 3, 'liste : 3 produits');
reset role;

-- 4. reserver_demandes_v2 : mêmes demandes réservées, mêmes effets sur la table, mêmes données hors identifiant produit
--    (chaque appel dans une transaction annulée ; demandes « a_faire » neuves : un envoi et un client)
select i.id as ins from public.inscriptions i order by created_at limit 1 \gset
insert into public.demandes_automatisation (type, objet_id) values ('envoi', :'fa_validee'), ('client', :'ins');
begin;
set local role service_role;
select public.reserver_demandes(10)::text as r1 \gset
select md5(string_agg(d.id || d.statut || d.tentatives || (d.pris_le is not null), ',' order by d.id)) as e1 from public.demandes_automatisation d \gset
rollback;
begin;
set local role service_role;
select public.reserver_demandes_v2(10)::text as r2 \gset
select md5(string_agg(d.id || d.statut || d.tentatives || (d.pris_le is not null), ',' order by d.id)) as e2 from public.demandes_automatisation d \gset
rollback;
select pg_temp.verifier(jsonb_array_length(:'r1'::jsonb) = 2 and jsonb_array_length(:'r2'::jsonb) = 2, 'deux demandes réservées par chacune');
select pg_temp.verifier(:'e1' = :'e2', 'mêmes effets sur demandes_automatisation');
select pg_temp.verifier((select jsonb_agg(jsonb_set(e, '{donnees}', pg_temp.sans_id(e->'donnees')) order by e->>'demande_id') from jsonb_array_elements(:'r2'::jsonb) e)
                      = (select jsonb_agg(e order by e->>'demande_id') from jsonb_array_elements(:'r1'::jsonb) e), 'mêmes données hors identifiant produit');
select pg_temp.verifier((select bool_and(l->>'axonaut_produit_id' <> '') from jsonb_array_elements(:'r2'::jsonb) e, jsonb_array_elements(e->'donnees'->'lignes') l
                         where e->>'type' = 'envoi'), 'v2 : identifiants présents dans l''envoi');
select pg_temp.verifier((select count(*) from public.demandes_automatisation where statut = 'a_faire') = 2, 'annulation : demandes toujours à faire');
-- remise en état : les deux demandes neuves passent en échec pour ne pas gêner la suite du banc (aucune suppression)
update public.demandes_automatisation set statut = 'echec', derniere_erreur = 'banc stock' where statut = 'a_faire';

-- 5. Écriture du stock (TC_33) et lecture par l'écran
set role service_role;
select pg_temp.verifier((public.stock_axonaut_ecrire('{"stocks": 3}'::jsonb)->>'ok')::boolean = false, 'corps invalide refusé');
select pg_temp.verifier(public.stock_axonaut_ecrire('{"stocks": [{"axonaut_produit_id": "1001", "stock": 3}, {"axonaut_produit_id": "1002", "stock": 9},
  {"axonaut_produit_id": "9999", "stock": 1}, {"axonaut_produit_id": "1001", "stock": "x"}]}'::jsonb) = '{"ok": true, "ecrits": 1, "ignores": 3}'::jsonb, 'seul le produit suivi est écrit');
select pg_temp.verifier(public.stock_axonaut_ecrire('{"stocks": []}'::jsonb) = '{"ok": true, "ecrits": 0, "ignores": 0}'::jsonb, 'liste vide : rien écrit');
reset role;
set role anon; reset request.jwt.claim.sub;
select pg_temp.verifier(pg_temp.refuse('select public.stock_pieces()', 'permission denied'), 'anon : stock refusé');
select pg_temp.verifier(pg_temp.refuse('select * from public.stock_axonaut', 'permission denied'), 'anon : table refusée');
reset role;
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000ff';
select pg_temp.verifier(pg_temp.refuse('select public.stock_pieces()', 'Accès refusé'), 'sans rôle : refusé');
select pg_temp.verifier(pg_temp.refuse('select public.reserver_demandes_v2(1)', 'permission denied'), 'authenticated : réservation refusée');
select pg_temp.verifier(pg_temp.refuse('select public.catalogue_axonaut_liste()', 'permission denied'), 'authenticated : liste refusée');
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000e';
select pg_temp.verifier((select e->>'etat' from jsonb_array_elements(public.stock_pieces()) e where e->>'piece_id' = :'pc_cab') = 'en_stock', 'mécanicien : câble en stock');
select pg_temp.verifier((select e->>'etat' from jsonb_array_elements(public.stock_pieces()) e where e->>'piece_id' = :'pc_mo') = 'inconnu', 'main d''oeuvre : inconnu');
reset role;
set role service_role;
select public.stock_axonaut_ecrire('{"stocks": [{"axonaut_produit_id": "1001", "stock": 0}]}'::jsonb) \gset x_
reset role;
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select pg_temp.verifier((select e->>'etat' from jsonb_array_elements(public.stock_pieces()) e where e->>'piece_id' = :'pc_cab') = 'a_commander', 'atelier : câble à commander');
reset role;
set role service_role;
select public.stock_axonaut_ecrire('{"stocks": [{"axonaut_produit_id": "1001", "stock": null}]}'::jsonb) \gset x_
reset role;
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000d';
select pg_temp.verifier((select e->>'etat' from jsonb_array_elements(public.stock_pieces()) e where e->>'piece_id' = :'pc_cab') = 'inconnu', 'lecture en échec : inconnu');
reset role;

select 'BANC STOCK : TOUTES LES ASSERTIONS PASSENT';
