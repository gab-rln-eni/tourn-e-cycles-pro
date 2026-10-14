-- 0011_v4_brouillons.sql : chantier V4 (agent V4, nuit du 2026-10-14), décision 4 de G_R (visa du 2026-10-14 vers 22:20).
-- Remplace TROIS fonctions NEUVES de 0010 (créées ce soir, même signature, mêmes droits : CREATE OR REPLACE conserve les droits) ;
-- aucun objet antérieur à 0010 n'est touché ; aucune suppression.
--   Devis en brouillon (statut brouillon ou a_relire) : état 'brouillon' (« brouillon, non envoyé » à l'écran, avec la date du devis),
--   d'après les lignes ACTUELLES du brouillon (une pièce enlevée disparaît de la liste) ; priorité anti-doublon : accepté, en attente
--   (envoyé), brouillon, refusé.
--   Rappel de 15 h : pièces des brouillons créés LE JOUR MÊME seulement (heure de Paris ; commande avant 16 h pour le lendemain,
--   transcription l. 657 à 663) ; brouillons plus anciens visibles à l'écran sans être rappelés ; envoyés et acceptés comme avant ;
--   refusés jamais.

create or replace function public.commandes_devis_source()
returns table (devis_ligne_id uuid, devis_id uuid, devis_reference text, devis_statut text, etat_devis text,
               fiche_id uuid, evenement_id uuid, date_intervention date, entreprise text, site text,
               fiche_reference text, client text, piece_id uuid, libelle text, reference text, quantite numeric,
               etat_stock text, retiree boolean, modifie_le timestamptz, lots_test boolean, cree_le timestamptz, doublon text)
language sql stable security definer set search_path = public as $$
  with lignes as (
    select dl.id as devis_ligne_id, d.id as devis_id, d.reference as devis_reference, d.statut as devis_statut,
           case d.statut when 'accepte' then 'accepte' when 'refuse' then 'refuse' when 'envoye' then 'en_attente' else 'brouillon' end as etat_devis,
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
             order by l.retiree, case l.etat_devis when 'accepte' then 0 when 'en_attente' then 1 when 'brouillon' then 2 else 3 end, l.cree_le desc, l.devis_ligne_id) as rang
    from lignes l where l.etat_stock in ('a_commander', 'inconnu')
  )
  select c.devis_ligne_id, c.devis_id, c.devis_reference, c.devis_statut, c.etat_devis, c.fiche_id, c.evenement_id,
         c.date_intervention, c.entreprise, c.site, c.fiche_reference, c.client, c.piece_id, c.libelle, c.reference, c.quantite,
         c.etat_stock, c.retiree, c.modifie_le, c.lots_test, c.cree_le,
         case when c.dans_l1 then 'fiche' when c.rang > 1 then 'devis' end as doublon
  from candidates c
$$;


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
               'modifie_le', d.modifie_le,
               'devis_date', (select dv.created_at from public.devis dv where dv.id = d.devis_id))
        from public.commandes_devis_source() d where d.evenement_id = p_evenement and d.doublon is null) u), '[]'::jsonb);
end $$;


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
      and (d.etat_devis <> 'brouillon'
           or exists (select 1 from public.devis dv where dv.id = d.devis_id and (dv.created_at at time zone 'Europe/Paris')::date = v_jour))
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
