-- 0010_v4.sql : chantier V4 (agent V4, nuit du 2026-10-14, dérogation de G_R).
-- Objets NEUFS seulement : aucune table, colonne, vue, fonction, contrainte ni règle d'accès existante n'est modifiée.
-- Aucune clé étrangère ni déclencheur ; RLS active sur les tables neuves ; REVOKE public, anon, authenticated puis droits nécessaires.
-- Rejouable (if not exists, create or replace, on conflict do nothing). Écart connu : hors journal Drizzle, comme 0003 à 0009.
--   v4_bascule : verrou d'affichage (une seule ligne, faite = faux) ; l'app masque ce qui ne marche qu'avec les workflows v4.
--                mise_en_service : heure d'application, seuil des lignes de devis prises par le rappel de 15 h (comme L1).
--   devis_pieces_retirees : case « retirée de la liste » d'une ligne de devis (aucune suppression, une ligne par ligne de devis).
--   commandes_devis_source : pièces des devis reliées au catalogue (jamais la main d'oeuvre ni une ligne libre), stock « À commander »
--     ou « Stock inconnu » (même calcul que stock_pieces), avec provenance et règle anti-doublon (colonne doublon) :
--       (a) la même pièce (piece_id) est déjà dans la liste L1 pour le même vélo (fiche terminée, pièce posée « à commander ») : 'fiche' ;
--       (b) la même pièce figure sur plusieurs devis de la même fiche : une seule ligne gardée (non retirée d'abord, puis accepté,
--           en attente, refusé, puis la plus récente) ; les autres : 'devis'.
--     LIMITES écrites (relecture CONS-120) : la même pièce deux fois sur un même devis donne une seule ligne (quantité de la ligne gardée) ;
--       une main d'oeuvre du catalogue sans ligne 'main_oeuvre' dans catalogue_axonaut serait prise pour une pièce (en base réelle,
--       MO-H a sa ligne) ; un devis sans fiche n'a pas de journée et n'entre pas dans la liste ; une ligne masquée par le doublon 'fiche'
--       n'est pas rappelée même si la pièce de la fiche est elle-même hors rappel (fiche terminée avant la mise en service de L1).
--   commandes_v4_journees, commandes_v4_journee : écran « À commander » (pièces des fiches L1 et pièces des devis), dirigeant et atelier.
--   devis_piece_retirer : case de retrait (dirigeant, atelier, mécanicien). devis_pieces_etat : état des lignes d'un devis pour la fiche.
--   rappel_commandes_reserver_v4 : rappel de 15 h du workflow TC_30 v2 ; même règle que rappel_commandes_reserver pour les pièces L1,
--     plus les pièces des devis non retirées, non refusées, sans doublon ; même réservation du jour (table rappels_commandes, partagée).
--   inscrire_v4 : ENVELOPPE de inscrire (refus d'une seconde inscription du même mail à la même journée), qui appelle inscrire elle-même.
--   facture_resume_v4 : résumé d'une facture « prête à valider » pour le mail au dirigeant (TC_14), par l'identifiant de la demande.

-- 1. Verrou d'affichage V4
create table if not exists public.v4_bascule (
  id boolean primary key default true check (id),
  faite boolean not null default false,
  mise_en_service timestamptz not null default now(),
  modifie_le timestamptz not null default now()
);
insert into public.v4_bascule (id) values (true) on conflict (id) do nothing;
alter table public.v4_bascule enable row level security;
revoke all on table public.v4_bascule from public, anon, authenticated;
grant all on table public.v4_bascule to service_role;

create or replace function public.v4_bascule_etat()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select b.faite from public.v4_bascule b where b.id), false)
$$;

-- 2. Case « retirée de la liste » d'une ligne de devis
create table if not exists public.devis_pieces_retirees (
  devis_ligne_id uuid primary key,
  retiree boolean not null default true,
  modifie_par uuid,
  modifie_le timestamptz not null default now()
);
alter table public.devis_pieces_retirees enable row level security;
revoke all on table public.devis_pieces_retirees from public, anon, authenticated;
grant all on table public.devis_pieces_retirees to service_role;

-- 3. Source des pièces des devis (fonction interne, aucun droit pour authenticated)
create or replace function public.commandes_devis_source()
returns table (devis_ligne_id uuid, devis_id uuid, devis_reference text, devis_statut text, etat_devis text,
               fiche_id uuid, evenement_id uuid, date_intervention date, entreprise text, site text,
               fiche_reference text, client text, piece_id uuid, libelle text, reference text, quantite numeric,
               etat_stock text, retiree boolean, modifie_le timestamptz, lots_test boolean, cree_le timestamptz, doublon text)
language sql stable security definer set search_path = public as $$
  with lignes as (
    select dl.id as devis_ligne_id, d.id as devis_id, d.reference as devis_reference, d.statut as devis_statut,
           case d.statut when 'accepte' then 'accepte' when 'refuse' then 'refuse' else 'en_attente' end as etat_devis,
           f.id as fiche_id, ev.id as evenement_id, ev.date_intervention, e.nom as entreprise, ev.site,
           f.reference as fiche_reference, i.prenom || ' ' || i.nom as client,
           dl.piece_id, dl.libelle, pc.reference, dl.quantite,
           case when ca.id is null or not ca.suivi_stock or sa.stock is null then 'inconnu'
                when sa.stock > 0 then 'en_stock' else 'a_commander' end as etat_stock,
           coalesce(r.retiree, false) as retiree, r.modifie_le,
           (i.nom ilike 'LOTS-TEST%' or i.prenom ilike 'LOTS-TEST%' or dl.libelle ilike '%LOTS-TEST%') as lots_test,
           dl.created_at as cree_le,
           exists (select 1 from public.pieces_posees pp join public.fiches f2 on f2.id = pp.fiche_id and f2.statut = 'terminee'
                   where pp.fiche_id = f.id and pp.piece_id = dl.piece_id and pp.a_commander) as dans_l1
    from public.devis_lignes dl
    join public.devis d on d.id = dl.devis_id
    join public.fiches f on f.id = d.fiche_id
    join public.inscriptions i on i.id = f.inscription_id
    join public.evenements ev on ev.id = i.evenement_id
    join public.entreprises e on e.id = ev.entreprise_id
    join public.pieces_catalogue pc on pc.id = dl.piece_id
    left join public.catalogue_axonaut ca on ca.piece_id = pc.id
    left join public.stock_axonaut sa on sa.axonaut_produit_id = ca.axonaut_produit_id
    left join public.devis_pieces_retirees r on r.devis_ligne_id = dl.id
    where dl.piece_id is not null
      and not exists (select 1 from public.catalogue_axonaut m where m.piece_id = dl.piece_id and m.role = 'main_oeuvre')
  ), candidates as (
    select l.*, row_number() over (partition by l.fiche_id, l.piece_id
             order by l.retiree, case l.etat_devis when 'accepte' then 0 when 'en_attente' then 1 else 2 end, l.cree_le desc, l.devis_ligne_id) as rang
    from lignes l where l.etat_stock in ('a_commander', 'inconnu')
  )
  select c.devis_ligne_id, c.devis_id, c.devis_reference, c.devis_statut, c.etat_devis, c.fiche_id, c.evenement_id,
         c.date_intervention, c.entreprise, c.site, c.fiche_reference, c.client, c.piece_id, c.libelle, c.reference, c.quantite,
         c.etat_stock, c.retiree, c.modifie_le, c.lots_test, c.cree_le,
         case when c.dans_l1 then 'fiche' when c.rang > 1 then 'devis' end as doublon
  from candidates c
$$;

-- 4. Écran « À commander » : journées (pièces des fiches L1 et des devis)
create or replace function public.commandes_v4_journees()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.has_any_role(array['dirigeant','atelier']::public.app_role[]) then raise exception 'Accès refusé.'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('evenement_id', x.evenement_id, 'date_intervention', x.date_intervention,
             'entreprise', x.entreprise, 'site', x.site, 'nb_pieces', x.nb, 'nb_a_commander', x.nb_a)
             order by x.date_intervention desc, x.entreprise, x.site)
    from (select u.evenement_id, u.date_intervention, u.entreprise, u.site, count(*) as nb, count(*) filter (where u.a_faire) as nb_a
          from (select s.evenement_id, s.date_intervention, s.entreprise, s.site, not s.commandee as a_faire
                  from public.commandes_pieces_source() s
                union all
                select d.evenement_id, d.date_intervention, d.entreprise, d.site, not d.retiree and d.etat_devis <> 'refuse'
                  from public.commandes_devis_source() d where d.doublon is null) u
          group by u.evenement_id, u.date_intervention, u.entreprise, u.site) x), '[]'::jsonb);
end $$;

-- 5. Écran « À commander » : pièces d'une journée ; source 'fiche' (case « commandée ») ou 'devis' (case « retirée »)
create or replace function public.commandes_v4_journee(p_evenement uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.has_any_role(array['dirigeant','atelier']::public.app_role[]) then raise exception 'Accès refusé.'; end if;
  return coalesce((
    select jsonb_agg(u.o order by u.fait, u.libelle, u.fiche_reference)
    from (
      select s.commandee as fait, s.libelle, s.fiche_reference,
             jsonb_build_object('source', 'fiche', 'id', s.piece_posee_id, 'fiche_reference', s.fiche_reference, 'client', s.client,
               'libelle', s.libelle, 'reference', s.reference, 'quantite', s.quantite, 'commandee', s.commandee,
               'retiree', false, 'devis_reference', null, 'etat_devis', null, 'etat_stock', null, 'modifie_le', s.modifie_le) as o
        from public.commandes_pieces_source() s where s.evenement_id = p_evenement
      union all
      select (d.retiree or d.etat_devis = 'refuse'), d.libelle, d.fiche_reference,
             jsonb_build_object('source', 'devis', 'id', d.devis_ligne_id, 'fiche_reference', d.fiche_reference, 'client', d.client,
               'libelle', d.libelle, 'reference', d.reference, 'quantite', d.quantite, 'commandee', false,
               'retiree', d.retiree, 'devis_reference', d.devis_reference, 'etat_devis', d.etat_devis, 'etat_stock', d.etat_stock,
               'modifie_le', d.modifie_le)
        from public.commandes_devis_source() d where d.evenement_id = p_evenement and d.doublon is null) u), '[]'::jsonb);
end $$;

-- 6. Case « retirée de la liste » (dirigeant, atelier, mécanicien) : ligne de devis reliée au catalogue seulement
create or replace function public.devis_piece_retirer(p_ligne uuid, p_retiree boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not public.has_any_role(array['dirigeant','atelier','mecanicien']::public.app_role[]) then raise exception 'Accès refusé.'; end if;
  if p_retiree is null then raise exception 'Indiquez si la pièce est retirée de la liste.'; end if;
  if not exists (select 1 from public.devis_lignes dl where dl.id = p_ligne and dl.piece_id is not null) then
    raise exception 'Ligne introuvable ou non reliée au catalogue.';
  end if;
  insert into public.devis_pieces_retirees(devis_ligne_id, retiree, modifie_par, modifie_le)
    values (p_ligne, p_retiree, auth.uid(), now())
  on conflict (devis_ligne_id) do update
    set retiree = excluded.retiree, modifie_par = excluded.modifie_par, modifie_le = excluded.modifie_le;
  return jsonb_build_object('ok', true, 'devis_ligne_id', p_ligne, 'retiree', p_retiree);
end $$;

-- 7. État des lignes d'un devis pour l'écran de la fiche : lignes candidates seulement ; doublon 'fiche' ou 'devis' si masquée
create or replace function public.devis_pieces_etat(p_devis uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.has_any_role(array['dirigeant','atelier','mecanicien']::public.app_role[]) then raise exception 'Accès refusé.'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('devis_ligne_id', d.devis_ligne_id, 'retiree', d.retiree, 'doublon', d.doublon,
             'etat_devis', d.etat_devis))
    from public.commandes_devis_source() d where d.devis_id = p_devis), '[]'::jsonb);
end $$;

-- 8. Rappel de 15 h du workflow TC_30 v2 (route de l'app, clé de service seulement).
--    Pièces L1 : même règle que rappel_commandes_reserver (0005). Pièces des devis : non retirées, devis non refusé, sans doublon,
--    hors LOTS-TEST, hors journées du 15/10 et du 27/10, lignes créées après la mise en service de V4.
--    Mode essai : pièces LOTS-TEST seulement (fiches et devis), sans réserver le jour.
--    Réservation du jour dans rappels_commandes : PARTAGÉE avec rappel_commandes_reserver (au plus un rappel par jour, v1 ou v2).
create or replace function public.rappel_commandes_reserver_v4(p_essai boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_jour date := (now() at time zone 'Europe/Paris')::date;
  v_mes timestamptz;
  v_mes4 timestamptz;
  v_essai boolean := coalesce(p_essai, false);
  v_pieces jsonb;
  v_nb integer;
begin
  select valeur into v_mes from public.lots_parametres where cle = 'l1_mise_en_service';
  select mise_en_service into v_mes4 from public.v4_bascule where id;
  with p as (
    select s.date_intervention, s.entreprise, s.site, s.fiche_reference, s.libelle, s.reference, s.quantite,
           'fiche'::text as source, null::text as devis_reference, null::text as etat_devis
    from public.commandes_pieces_source() s
    where not s.commandee
      and case when v_essai then s.lots_test
               else not s.lots_test and v_mes is not null and s.termine_le > v_mes
                    and s.date_intervention not in (date '2026-10-15', date '2026-10-27') end
    union all
    select d.date_intervention, d.entreprise, d.site, d.fiche_reference, d.libelle, d.reference, d.quantite,
           'devis', d.devis_reference, d.etat_devis
    from public.commandes_devis_source() d
    where d.doublon is null and not d.retiree and d.etat_devis <> 'refuse'
      and case when v_essai then d.lots_test
               else not d.lots_test and v_mes4 is not null and d.cree_le > v_mes4
                    and d.date_intervention not in (date '2026-10-15', date '2026-10-27') end
  )
  select count(*), coalesce(jsonb_agg(jsonb_build_object('date_intervention', p.date_intervention, 'entreprise', p.entreprise,
           'site', p.site, 'fiche_reference', p.fiche_reference, 'libelle', p.libelle, 'reference', p.reference,
           'quantite', p.quantite, 'source', p.source, 'devis_reference', p.devis_reference, 'etat_devis', p.etat_devis)
           order by p.date_intervention, p.entreprise, p.site, p.libelle, p.source), '[]'::jsonb)
    into v_nb, v_pieces from p;

  if v_essai then
    return jsonb_build_object('envoyer', v_nb > 0, 'essai', true, 'raison', case when v_nb > 0 then 'essai' else 'rien_a_commander' end,
                              'jour', v_jour, 'nb_pieces', v_nb, 'pieces', v_pieces);
  end if;
  if extract(isodow from v_jour) > 5 then
    return jsonb_build_object('envoyer', false, 'essai', false, 'raison', 'jour_non_ouvre', 'jour', v_jour, 'nb_pieces', v_nb, 'pieces', '[]'::jsonb);
  end if;
  if v_nb = 0 then
    return jsonb_build_object('envoyer', false, 'essai', false, 'raison', 'rien_a_commander', 'jour', v_jour, 'nb_pieces', 0, 'pieces', '[]'::jsonb);
  end if;
  insert into public.rappels_commandes(jour, nb_pieces) values (v_jour, v_nb) on conflict (jour) do nothing;
  if not found then
    return jsonb_build_object('envoyer', false, 'essai', false, 'raison', 'deja_envoye', 'jour', v_jour, 'nb_pieces', v_nb, 'pieces', '[]'::jsonb);
  end if;
  return jsonb_build_object('envoyer', true, 'essai', false, 'raison', 'a_envoyer', 'jour', v_jour, 'nb_pieces', v_nb, 'pieces', v_pieces);
end $$;

-- 9. Inscription sans doublon (TC-23) : ENVELOPPE de inscrire, qui reste la seule à créer l'inscription, la demande pour TC_00
--    et à bloquer les places. Le verrou de la journée (FOR UPDATE, repris par inscrire dans la même transaction) évite que deux
--    envois simultanés du même mail passent tous les deux. Un identifiant de journée invalide est laissé au contrôle de inscrire.
--    LIMITE : inscrire reste exécutable par anon (droit existant, non modifié) ; l'anti-doublon vaut pour l'app, qui appelle inscrire_v4.
create or replace function public.inscrire_v4(p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_email text := lower(btrim(coalesce(p->>'email','')));
  v_evid text := coalesce(p->>'evenement_id','');
begin
  -- Contrôle seulement pour une journée de l'entreprise du lien (évite de sonder une journée inconnue) ; sinon inscrire refuse elle-même.
  if v_evid ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' and v_email <> ''
     and exists (select 1 from public.evenements ev join public.entreprises e on e.id = ev.entreprise_id
                 where ev.id = v_evid::uuid and e.code = coalesce(p->>'code_entreprise','')) then
    perform 1 from public.evenements where id = v_evid::uuid for update;
    if exists (select 1 from public.inscriptions i where i.evenement_id = v_evid::uuid and lower(btrim(i.email)) = v_email) then
      raise exception 'Vous êtes déjà inscrit à cette journée avec cette adresse email. Une seule inscription par personne et par journée.';
    end if;
  end if;
  return public.inscrire(p);
end $$;

-- 10. Résumé d'une facture pour le mail au dirigeant (TC_14) : par la demande 'controle' ; montants arrondis au centime comme la facture
create or replace function public.facture_resume_v4(p_demande uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'facture_id', fa.id, 'statut', fa.statut,
    'client', i.prenom || ' ' || i.nom, 'entreprise', e.nom, 'site', ev.site, 'date_intervention', ev.date_intervention,
    'reference_fiche', f.reference,
    'total_ht', coalesce((select round(sum(l.quantite * l.prix_unitaire_ht), 2) from public.facture_lignes l where l.facture_id = fa.id), 0),
    'total_ttc', coalesce((select round(sum(l.quantite * l.prix_unitaire_ht), 2) + round(sum(l.quantite * l.prix_unitaire_ht * l.taux_tva / 100), 2)
                           from public.facture_lignes l where l.facture_id = fa.id), 0),
    'avis_regles', coalesce((select jsonb_agg(jsonb_build_object('niveau', a.niveau, 'message', a.message) order by a.created_at)
                             from public.avis_controle a where a.facture_id = fa.id and a.source = 'regles'), '[]'::jsonb))
  from public.demandes_automatisation d
  join public.factures fa on fa.id = d.objet_id
  join public.inscriptions i on i.id = fa.inscription_id
  join public.evenements ev on ev.id = i.evenement_id
  join public.entreprises e on e.id = ev.entreprise_id
  left join public.fiches f on f.inscription_id = i.id
  where d.id = p_demande and d.type = 'controle'
$$;

-- 11. Droits d'exécution : explicites (la base réelle accorde par défaut tout à anon sur un objet neuf)
revoke all on function public.v4_bascule_etat(), public.commandes_devis_source(), public.commandes_v4_journees(),
  public.commandes_v4_journee(uuid), public.devis_piece_retirer(uuid, boolean), public.devis_pieces_etat(uuid),
  public.rappel_commandes_reserver_v4(boolean), public.inscrire_v4(jsonb), public.facture_resume_v4(uuid)
  from public, anon, authenticated;
grant execute on function public.v4_bascule_etat(), public.commandes_v4_journees(), public.commandes_v4_journee(uuid),
  public.devis_piece_retirer(uuid, boolean), public.devis_pieces_etat(uuid) to authenticated;
grant execute on function public.inscrire_v4(jsonb) to anon, authenticated;   -- mêmes droits que inscrire (formulaire public)
grant execute on function public.v4_bascule_etat(), public.commandes_devis_source(), public.commandes_v4_journees(),
  public.commandes_v4_journee(uuid), public.devis_piece_retirer(uuid, boolean), public.devis_pieces_etat(uuid),
  public.rappel_commandes_reserver_v4(boolean), public.inscrire_v4(jsonb), public.facture_resume_v4(uuid) to service_role;

-- Retour arrière (objets neufs seulement ; jamais exécuté sans visa ; l'app revient à inscrire en republiant le commit précédent) :
-- revoke execute on function public.inscrire_v4(jsonb) from anon, authenticated;
-- drop function if exists public.facture_resume_v4(uuid), public.inscrire_v4(jsonb), public.rappel_commandes_reserver_v4(boolean),
--   public.devis_pieces_etat(uuid), public.devis_piece_retirer(uuid, boolean), public.commandes_v4_journee(uuid),
--   public.commandes_v4_journees(), public.commandes_devis_source(), public.v4_bascule_etat();
-- drop table if exists public.devis_pieces_retirees, public.v4_bascule;
