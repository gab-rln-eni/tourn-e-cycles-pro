-- 0006_stats_entreprises.sql : lot L2, statistiques par entreprise cliente (agent LOTS, 2026-10-14, visa G_R de l'après-midi).
-- Objet NEUF seulement : une vue, avec security_invoker = on (les règles d'accès des tables existantes s'appliquent à l'appelant).
-- Aucune table, colonne, fonction, contrainte ni règle d'accès existante n'est modifiée.
-- Droits : REVOKE explicite pour public et anon (la base réelle accorde par défaut tout à anon sur un objet neuf) ; SELECT pour authenticated.
-- Une ligne par fait : 'velo' (une fiche), 'organe' (un point de contrôle qui n'est pas « bon », par groupe de la fiche),
-- 'piece' (une pièce posée, avec sa quantité). Les données d'essai LOTS-TEST sont exclues.
-- Idempotent. Écart connu : non inscrit dans drizzle/migrations/meta/_journal.json (application par SQL direct).

create or replace view public.stats_entreprises with (security_invoker = on) as
  select e.id as entreprise_id, e.nom as entreprise, ev.site, ev.date_intervention,
         'velo'::text as genre,
         case i.type_velo when 'vae' then 'Électrique (VAE)' else 'Musculaire' end as libelle,
         1::numeric as quantite
  from public.fiches f
  join public.inscriptions i on i.id = f.inscription_id
  join public.evenements ev on ev.id = i.evenement_id
  join public.entreprises e on e.id = ev.entreprise_id
  where i.nom not ilike 'LOTS-TEST%' and i.prenom not ilike 'LOTS-TEST%'
  union all
  select e.id, e.nom, ev.site, ev.date_intervention, 'organe', fp.groupe, 1::numeric
  from public.fiche_points fp
  join public.fiches f on f.id = fp.fiche_id
  join public.inscriptions i on i.id = f.inscription_id
  join public.evenements ev on ev.id = i.evenement_id
  join public.entreprises e on e.id = ev.entreprise_id
  where fp.etat <> 'bon' and i.nom not ilike 'LOTS-TEST%' and i.prenom not ilike 'LOTS-TEST%'
  union all
  select e.id, e.nom, ev.site, ev.date_intervention, 'piece', pp.libelle, pp.quantite
  from public.pieces_posees pp
  join public.fiches f on f.id = pp.fiche_id
  join public.inscriptions i on i.id = f.inscription_id
  join public.evenements ev on ev.id = i.evenement_id
  join public.entreprises e on e.id = ev.entreprise_id
  where i.nom not ilike 'LOTS-TEST%' and i.prenom not ilike 'LOTS-TEST%' and pp.libelle not ilike '%LOTS-TEST%';

alter view public.stats_entreprises set (security_invoker = on);
revoke all on public.stats_entreprises from public, anon, authenticated;
grant select on public.stats_entreprises to authenticated;
grant select on public.stats_entreprises to service_role;

-- Retour arrière (seulement sur visa, sans suppression) : revoke select on public.stats_entreprises from authenticated;
