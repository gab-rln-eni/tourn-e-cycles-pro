-- Banc SQL de la liaison (L-1 à L-3 et routes pour n8n), à jouer sur une base locale après bouchon_supabase.sql et les migrations.
-- Chaque étape est jouée sous le rôle réel (anon, authenticated, service_role) ; toute assertion fausse arrête le banc (ON_ERROR_STOP).
\set ON_ERROR_STOP 1
\set QUIET 1
create function pg_temp.verifier(c boolean, m text) returns void language plpgsql as $$ begin if c is not true then raise exception 'ASSERTION : %', m; end if; end $$;

-- Données : trois comptes confirmés et leurs accès, catalogue.
insert into auth.users values
  ('00000000-0000-0000-0000-00000000000d', 'dirigeant@example.com', now()),
  ('00000000-0000-0000-0000-00000000000e', 'meca@example.com', now()),
  ('00000000-0000-0000-0000-00000000000a', 'atelier@example.com', now());
insert into public.acces(email, role) values
  ('dirigeant@example.com', 'dirigeant'), ('meca@example.com', 'mecanicien'), ('atelier@example.com', 'atelier');
insert into public.pieces_catalogue(reference, libelle, prix_vente_ht) values
  ('CAB', 'Câble de frein inox 1,6 mm 1,80 m', 2.08), ('MO', 'Main d''oeuvre (heure)', 50.00);

-- 1. Le dirigeant crée une entreprise et une journée.
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000d';
insert into public.entreprises(nom) values ('Entreprise de banc');
insert into public.evenements(entreprise_id, site, date_intervention)
  select id, 'Site de banc', current_date from public.entreprises;
reset role;
select e.code as code_ent, ev.id as ev_id from public.entreprises e join public.evenements ev on ev.entreprise_id = e.id \gset

-- 2. Inscription publique (anon) : une demande 'client'.
set role anon; reset request.jwt.claim.sub;
select public.inscrire(jsonb_build_object('code_entreprise', :'code_ent', 'evenement_id', :'ev_id', 'nom', 'Banc', 'prenom', 'Alex',
  'telephone', '06 00 00 00 02', 'email', 'alex.banc@example.com', 'code_postal', '69007', 'type_velo', 'vae',
  'partie_signalee', 'freins', 'probleme_percu', 'Freins mous', 'consentement', true)) is not null as inscrit \gset
reset role;
select id as insc_id from public.inscriptions \gset
do $$ begin assert (select count(*) from public.demandes_automatisation where type = 'client' and statut = 'a_faire') = 1, 'demande client'; end $$;

-- 3. Le mécanicien remplit et termine la fiche : facture créée, demande 'commande', AUCUNE demande 'brouillon' (L-3), référence (L-2).
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000e';
insert into public.fiches(inscription_id) values (:'insc_id');
reset role;
select id as fiche_id from public.fiches \gset
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000e';
insert into public.fiche_points(fiche_id, groupe, point, etat, remarque) values (:'fiche_id', 'Frein avant', 'Patins ou plaquettes', 'a_changer', 'usés');
insert into public.pieces_posees(fiche_id, piece_id, libelle, quantite, prix_unitaire_ht, a_commander)
  select :'fiche_id', id, libelle, 1, prix_vente_ht, reference = 'CAB' from public.pieces_catalogue;
update public.fiches set commentaire = 'Réglage des freins.' where id = :'fiche_id';
select public.terminer_fiche(:'fiche_id') as fac_id \gset
reset role;
do $$ begin
  assert (select count(*) from public.demandes_automatisation where type = 'brouillon') = 0, 'L-3 : aucune demande brouillon';
  assert (select count(*) from public.demandes_automatisation where type = 'commande' and statut = 'a_faire') = 1, 'demande commande';
  assert (select count(*) from public.facture_lignes) = 2, 'lignes copiées';
  assert (select reference ~ '^TC-[0-9A-F]{8}$' from public.fiches), 'L-2 : référence TC- et 8 caractères';
  assert (select reference = 'TC-' || upper(substr(id::text, 1, 8)) from public.fiches), 'L-2 : référence stable';
end $$;

-- 4. L'atelier contrôle puis prépare : 'a_valider' et demande 'controle' (L-1) ; il ne peut pas valider.
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select public.controler_facture(:'fac_id');
select public.preparer_facture(:'fac_id');
\set ON_ERROR_STOP 0
select public.valider_facture(:'fac_id');
select public.preparer_facture(:'fac_id');
\set ON_ERROR_STOP 1
reset role;
do $$ begin
  assert (select statut from public.factures) = 'a_valider', 'L-1 : facture à valider';
  assert (select prete_par from public.factures) = '00000000-0000-0000-0000-00000000000a', 'L-1 : prete_par';
  assert (select count(*) from public.demandes_automatisation where type = 'controle') = 1, 'L-1 : une seule demande controle';
end $$;

-- 5. Le dirigeant valide : demande 'envoi'.
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000d';
select public.valider_facture(:'fac_id');
reset role;

-- 6. Droits : ni anon ni authenticated n'exécutent les fonctions des routes.
set role authenticated;
\set ON_ERROR_STOP 0
select public.reserver_demandes(10);
select public.ecrire_resultat('{}'::jsonb);
\set ON_ERROR_STOP 1
reset role;
do $$ begin
  assert not has_function_privilege('authenticated', 'public.reserver_demandes(integer)', 'execute'), 'droits authenticated';
  assert not has_function_privilege('anon', 'public.ecrire_resultat(jsonb)', 'execute'), 'droits anon';
  assert has_function_privilege('service_role', 'public.reserver_demandes(integer)', 'execute'), 'droits service_role';
end $$;

-- 7. Réservation par la route (service_role) : 4 demandes, données conformes au contrat.
set role service_role;
select public.reserver_demandes(10) as lot \gset
reset role;
create temp table lot as select x as d from jsonb_array_elements(:'lot'::jsonb) x;
do $$ declare c jsonb; e jsonb; k jsonb; v jsonb; begin
  assert (select count(*) from lot) = 4, 'quatre demandes réservées';
  assert (select count(*) from public.demandes_automatisation where statut = 'en_cours' and tentatives = 1 and pris_le is not null) = 4, 'en_cours, tentatives 1';
  select d->'donnees' into c from lot where d->>'type' = 'client';
  assert c->'inscription'->>'email' = 'alex.banc@example.com' and c->'entreprise'->>'nom' = 'Entreprise de banc', 'données client';
  select d->'donnees' into k from lot where d->>'type' = 'commande';
  assert jsonb_array_length(k->'pieces') = 1 and k->'pieces'->0->>'reference' = 'CAB', 'données commande';
  select d->'donnees' into v from lot where d->>'type' = 'controle';
  assert jsonb_array_length(v->'lignes') = 2 and jsonb_array_length(v->'points') = 1 and v->>'probleme_percu' = 'Freins mous', 'données controle';
  assert position('example.com' in v::text) = 0 and position('Banc' in v::text) = 0, 'controle sans donnée personnelle';
  select d->'donnees' into e from lot where d->>'type' = 'envoi';
  assert e->>'reference_fiche' = (select reference from public.fiches), 'envoi : référence';
  assert (e->>'total_ht')::numeric = 52.08 and (e->>'total_tva')::numeric = 10.42 and (e->>'total_ttc')::numeric = 62.50, 'envoi : totaux';
  assert jsonb_array_length(e->'lignes') = 2, 'envoi : lignes';
  assert e->'recapitulatif'->>'velo' = 'Électrique (VAE)', 'envoi : velo sans modèle (velo_modele vide)';
end $$;

-- 8. Sortie vide : plus rien à réserver.
set role service_role;
select public.reserver_demandes(10) = '[]'::jsonb as vide \gset
reset role;
select pg_temp.verifier(:'vide'::boolean, 'sortie vide');

-- 9. Résultats nominaux : client (identifiant Axonaut), controle (avis IA).
select (select d->>'demande_id' from lot where d->>'type' = 'client') as dem_client,
       (select d->>'demande_id' from lot where d->>'type' = 'controle') as dem_controle,
       (select d->>'demande_id' from lot where d->>'type' = 'envoi') as dem_envoi,
       (select d->>'demande_id' from lot where d->>'type' = 'commande') as dem_commande \gset
set role service_role;
select public.ecrire_resultat(jsonb_build_object('demande_id', :'dem_client', 'ok', true, 'resultat', jsonb_build_object('axonaut_client_id', '52094138')));
select public.ecrire_resultat(jsonb_build_object('demande_id', :'dem_controle', 'ok', true,
  'resultat', jsonb_build_object('avis', jsonb_build_array(jsonb_build_object('niveau', 'attention', 'message', 'Patins à changer sans plaquettes facturées.')))));
reset role;
do $$ begin
  assert (select axonaut_client_id from public.inscriptions) = '52094138', 'client : identifiant écrit';
  assert (select count(*) from public.avis_controle where source = 'ia' and niveau = 'attention') = 1, 'controle : avis IA écrit';
  assert (select count(*) from public.demandes_automatisation where statut = 'fait') = 2, 'deux demandes faites';
end $$;

-- 10. Sorties en erreur : identifiant invalide, inconnu, demande non en cours.
set role service_role;
select public.ecrire_resultat('{"demande_id":"x","ok":true}'::jsonb)->>'ok' as e1,
       public.ecrire_resultat('{"demande_id":"11111111-1111-1111-1111-111111111111","ok":true}'::jsonb)->>'ok' as e2,
       public.ecrire_resultat(jsonb_build_object('demande_id', :'dem_client', 'ok', true))->>'ok' as e3 \gset
reset role;
select pg_temp.verifier(:'e1' = 'false' and :'e2' = 'false' and :'e3' = 'false', 'erreurs refusées sans écriture');

-- 11. Envoi en échec avec identifiant de facture (A2-11) : retour à 'a_faire', identifiant gardé, facture toujours validée.
set role service_role;
select public.ecrire_resultat(jsonb_build_object('demande_id', :'dem_envoi', 'ok', false, 'erreur', 'Gmail refuse',
  'resultat', jsonb_build_object('axonaut_facture_id', '999')));
reset role;
do $$ begin
  assert (select statut from public.demandes_automatisation where type = 'envoi') = 'a_faire', 'envoi : reprise';
  assert (select axonaut_facture_id from public.factures) = '999', 'A2-11 : identifiant écrit malgré ok faux';
  assert (select statut from public.factures) = 'validee', 'facture toujours validée';
end $$;

-- 12. Règle des 15 minutes : commande bloquée en cours, reprise ; puis abandon à 3 tentatives.
update public.demandes_automatisation set pris_le = now() - interval '20 minutes' where type = 'commande';
set role service_role;
select jsonb_array_length(public.reserver_demandes(10)) as n12 \gset
reset role;
select pg_temp.verifier(:'n12' = 2, 'commande et envoi reprises');
select pg_temp.verifier((select tentatives from public.demandes_automatisation where type = 'commande') = 2, 'commande : tentatives 2');
update public.demandes_automatisation set pris_le = now() - interval '20 minutes', tentatives = 3 where type = 'commande';
set role service_role;
select public.reserver_demandes(10);
reset role;
do $$ begin
  assert (select statut from public.demandes_automatisation where type = 'commande') = 'echec', 'commande : abandon à 3 tentatives';
end $$;

-- 13. Envoi : troisième échec, abandon et facture en échec.
set role service_role;
select public.ecrire_resultat(jsonb_build_object('demande_id', :'dem_envoi', 'ok', false, 'erreur', 'Gmail refuse'));
select public.reserver_demandes(10);
select public.ecrire_resultat(jsonb_build_object('demande_id', :'dem_envoi', 'ok', false, 'erreur', 'Gmail refuse encore'));
reset role;
do $$ begin
  assert (select tentatives from public.demandes_automatisation where type = 'envoi') = 3, 'envoi : 3 tentatives';
  assert (select statut from public.demandes_automatisation where type = 'envoi') = 'echec', 'envoi : abandon';
  assert (select statut from public.factures) = 'echec' and (select detail from public.factures) = 'Gmail refuse encore', 'facture en échec avec motif';
end $$;

-- 14. Envoi réussi après nouvelle préparation et validation : facture envoyée.
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select public.preparer_facture(:'fac_id');
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000d';
select public.valider_facture(:'fac_id');
reset role;
set role service_role;
select (select x->>'demande_id' from jsonb_array_elements(public.reserver_demandes(10)) x where x->>'type' = 'envoi') as dem_envoi2 \gset
select public.ecrire_resultat(jsonb_build_object('demande_id', :'dem_envoi2', 'ok', true,
  'resultat', jsonb_build_object('axonaut_facture_id', '999', 'envoyee_le', '2026-10-13T08:00:00Z')));
reset role;
do $$ begin
  assert (select statut from public.factures) = 'envoyee', 'facture envoyée';
  assert (select envoyee_le from public.factures) = '2026-10-13 08:00:00+00', 'date d''envoi reprise du résultat';
end $$;

-- 15. recapitulatif.velo avec modèle renseigné, puis modèle fait d'espaces (traité comme vide).
update public.factures set statut = 'validee'; -- les données 'envoi' ne sont fournies que pour une facture validée
update public.inscriptions set velo_modele = 'Decathlon Elops 120';
set role service_role;
select public.donnees_demande('envoi', :'fac_id')->'recapitulatif'->>'velo' as velo1 \gset
reset role;
update public.inscriptions set velo_modele = '   ';
set role service_role;
select public.donnees_demande('envoi', :'fac_id')->'recapitulatif'->>'velo' as velo2 \gset
reset role;
select pg_temp.verifier(:'velo1' = 'Électrique (VAE), Decathlon Elops 120', 'velo avec modèle');
select pg_temp.verifier(:'velo2' = 'Électrique (VAE)', 'velo modèle blanc');

\echo BANC LIAISON : TOUTES LES ASSERTIONS PASSENT
