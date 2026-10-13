-- Banc SQL du parcours devis (migration 0003), à jouer après banc_liaison.sql sur la même base locale.
-- Chaque étape est jouée sous le rôle réel ; toute assertion fausse arrête le banc (ON_ERROR_STOP).
\set ON_ERROR_STOP 1
\set QUIET 1
create function pg_temp.verifier(c boolean, m text) returns void language plpgsql as $$ begin if c is not true then raise exception 'ASSERTION : %', m; end if; end $$;
-- Vrai si l'instruction est refusée (droit ou RLS), faux si elle passe
create function pg_temp.refuse(sql text) returns boolean language plpgsql as $$
begin execute sql; return false;
exception when insufficient_privilege or check_violation or raise_exception then return true; end $$;
grant execute on function pg_temp.refuse(text), pg_temp.verifier(boolean, text) to anon, authenticated, service_role;

select id as fiche_id from public.fiches limit 1 \gset
select id as cab_id from public.pieces_catalogue where reference = 'CAB' \gset

-- 1. Le mécanicien crée un devis depuis la fiche et saisit les lignes conseillées.
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000e';
insert into public.devis(fiche_id, reference, axonaut_client_id, commentaire)
  values (:'fiche_id', 'BANC-DEVIS-1', '52135944', 'Cassette usée, à changer.');
select id as dv from public.devis where reference = 'BANC-DEVIS-1' \gset
insert into public.devis_lignes(devis_id, ordre, libelle, quantite, prix_unitaire_ht, taux_tva) values
  (:'dv', 1, 'Cassette 10 vitesses', 2, 12.50, 20), (:'dv', 2, 'Main d''oeuvre (heure)', 1, 50, 20);
insert into public.devis_lignes(devis_id, ordre, piece_id, libelle, quantite, prix_unitaire_ht)
  values (:'dv', 3, :'cab_id', 'Câble de frein', 1, 9.99);
select pg_temp.verifier(pg_temp.refuse($q$insert into public.devis(reference, statut) values ('BANC-X', 'envoye')$q$), 'insertion directe en envoye refusée');
select public.devis_controles(:'dv') as avis \gset
select pg_temp.verifier(:'avis'::jsonb @> '[{"niveau":"attention"}]' and :'avis'::jsonb::text like '%catalogue%', 'écart de prix au catalogue signalé');
select pg_temp.verifier(not (:'avis'::jsonb @> '[{"niveau":"erreur"}]'), 'aucune erreur sur un devis complet');
reset role;
delete from public.devis_lignes where devis_id = :'dv' and ordre = 3;
select pg_temp.verifier(public.devis_totaux(:'dv') = '{"total_ht": 75.00, "total_tva": 15.00, "total_ttc": 90.00}'::jsonb, 'totaux au centime');

-- 2. Devis vide : erreur aux contrôles, proposition refusée.
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000e';
insert into public.devis(reference) values ('BANC-VIDE');
select id as vide from public.devis where reference = 'BANC-VIDE' \gset
select pg_temp.verifier(public.devis_controles(:'vide')::text like '%aucune ligne%', 'devis vide : erreur aucune ligne');
select pg_temp.verifier(public.devis_controles(:'vide')::text like '%pas encore dans Axonaut%', 'devis sans client : erreur client');
select pg_temp.verifier(pg_temp.refuse(format('select public.devis_proposer(%L)', :'vide')), 'proposition d un devis vide refusée');

-- 3. Le mécanicien propose ; il ne peut pas relire lui-même.
select public.devis_proposer(:'dv');
select pg_temp.verifier(pg_temp.refuse(format('select public.devis_preparer_envoi(%L)', :'dv')), 'mécanicien : relecture refusée');
reset role;

-- 4. Anon : aucune lecture des tables, aucune fonction interne ; page publique vide avant l'envoi.
set role anon; reset request.jwt.claim.sub;
select pg_temp.verifier(pg_temp.refuse('select count(*) from public.devis'), 'anon : lecture de devis refusée');
select pg_temp.verifier(pg_temp.refuse('select count(*) from public.devis_lignes'), 'anon : lecture des lignes refusée');
select pg_temp.verifier(pg_temp.refuse(format('select public.devis_controles(%L)', :'dv')), 'anon : contrôles refusés');
select pg_temp.verifier(pg_temp.refuse($q$select public.devis_noter_envoi('{}'::jsonb)$q$), 'anon : noter_envoi refusé');
select pg_temp.verifier(pg_temp.refuse(format('select public.devis_totaux(%L)', :'dv')), 'anon : totaux refusés');
reset role;

-- 5. L'atelier relit : jeton créé, données d'envoi complètes.
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select public.devis_preparer_envoi(:'dv') as prep \gset
select (:'prep'::jsonb)->>'jeton' as jeton \gset
select pg_temp.verifier((:'prep'::jsonb)->>'ok' = 'true' and :'jeton' ~ '^[0-9a-f]{64}$', 'relecture : ok et jeton');
select pg_temp.verifier((:'prep'::jsonb)#>>'{donnees,axonaut_client_id}' = '52135944' and jsonb_array_length((:'prep'::jsonb)#>'{donnees,lignes}') = 2
  and ((:'prep'::jsonb)#>>'{donnees,total_ttc}')::numeric = 90, 'données d envoi');
select pg_temp.verifier(public.devis_preparer_envoi(:'dv')->>'jeton' = :'jeton', 'reprise : même jeton');
reset role;
set role anon;
select pg_temp.verifier(public.devis_public(:'jeton') is null, 'page publique vide tant que le devis n est pas envoyé');
reset role;

-- 6. Réponse de n8n (service_role) : devis envoyé ; plus aucune modification par l'app.
set role service_role;
select pg_temp.verifier(public.devis_noter_envoi(jsonb_build_object('devis_id', :'dv', 'ok', true, 'axonaut_devis_id', '999', 'numero', 'D-1', 'public_path', 'https://exemple'))->>'statut' = 'envoye', 'noter_envoi');
reset role;
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
update public.devis set commentaire = 'modifié' where id = :'dv';
reset role;
select pg_temp.verifier((select commentaire from public.devis where id = :'dv') = 'Cassette usée, à changer.', 'devis envoyé : non modifiable par l app');

-- 7. Le cycliste (anon) voit le devis, sans donnée personnelle, et l'accepte une seule fois.
set role anon;
select public.devis_public(:'jeton') as pub \gset
select pg_temp.verifier((:'pub'::jsonb)->>'reference' = 'BANC-DEVIS-1' and ((:'pub'::jsonb)->>'total_ttc')::numeric = 90, 'page publique : référence et total');
select pg_temp.verifier(:'pub' not like '%@%' and :'pub' not like '%Alex%' and :'pub' not like '%52135944%', 'page publique : aucune donnée personnelle ni identifiant client');
select pg_temp.verifier(public.devis_public(repeat('0', 64)) is null and public.devis_public('x') is null, 'jeton faux : rien');
select pg_temp.verifier(public.devis_repondre(repeat('0', 64), 'accepte')->>'ok' = 'false', 'jeton faux : refus');
select pg_temp.verifier(public.devis_repondre(:'jeton', 'peut-etre')->>'ok' = 'false', 'décision inconnue : refus');
select public.devis_repondre(:'jeton', 'accepte') as rep \gset
select pg_temp.verifier((:'rep'::jsonb)->>'ok' = 'true' and (:'rep'::jsonb)->>'axonaut_devis_id' = '999', 'acceptation');
select pg_temp.verifier(public.devis_repondre(:'jeton', 'refuse')->>'ok' = 'false', 'seconde décision contraire refusée');
select pg_temp.verifier(public.devis_repondre(:'jeton', 'accepte')->>'deja' = 'true', 'seconde décision identique : déjà');
reset role;
select pg_temp.verifier((select statut from public.devis where id = :'dv') = 'accepte', 'statut accepte');

-- 8. Compte confirmé sans accès : aucune ligne visible.
insert into auth.users values ('00000000-0000-0000-0000-0000000000ff', 'inconnu@example.com', now());
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000ff';
select pg_temp.verifier((select count(*) from public.devis) = 0, 'compte sans accès : aucune ligne');
reset role;

\echo 'BANC DEVIS : TOUTES LES ASSERTIONS PASSENT'
