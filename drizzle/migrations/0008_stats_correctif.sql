-- 0008_stats_correctif.sql : correctif de la vue NEUVE stats_entreprises (lot L2, créée le 2026-10-14 par 0006), après relecture indépendante.
-- 1. Organes en défaut comptés une fois par fiche et par groupe (et non par point de contrôle).
-- 2. Même règle LOTS-TEST que L1 : une fiche est d'essai si l'inscription OU l'une de ses pièces porte « LOTS-TEST » ; toute la fiche est exclue.
-- Ne touche que la vue créée aujourd'hui (mêmes colonnes) ; aucun objet existant avant le 2026-10-14 n'est modifié. Idempotent.

create or replace view public.stats_entreprises with (security_invoker = on) as
  with fiches_ok as (
    select f.id as fiche_id, e.id as entreprise_id, e.nom as entreprise, ev.site, ev.date_intervention, i.type_velo
    from public.fiches f
    join public.inscriptions i on i.id = f.inscription_id
    join public.evenements ev on ev.id = i.evenement_id
    join public.entreprises e on e.id = ev.entreprise_id
    where i.nom not ilike 'LOTS-TEST%' and i.prenom not ilike 'LOTS-TEST%'
      and not exists (select 1 from public.pieces_posees pp where pp.fiche_id = f.id and pp.libelle ilike '%LOTS-TEST%')
  )
  select x.entreprise_id, x.entreprise, x.site, x.date_intervention, 'velo'::text as genre,
         case x.type_velo when 'vae' then 'Électrique (VAE)' else 'Musculaire' end as libelle, 1::numeric as quantite
  from fiches_ok x
  union all
  select x.entreprise_id, x.entreprise, x.site, x.date_intervention, 'organe', g.groupe, 1::numeric
  from fiches_ok x
  join (select distinct fp.fiche_id, fp.groupe from public.fiche_points fp where fp.etat <> 'bon') g on g.fiche_id = x.fiche_id
  union all
  select x.entreprise_id, x.entreprise, x.site, x.date_intervention, 'piece', pp.libelle, pp.quantite
  from fiches_ok x
  join public.pieces_posees pp on pp.fiche_id = x.fiche_id;

alter view public.stats_entreprises set (security_invoker = on);
revoke all on public.stats_entreprises from public, anon, authenticated;
grant select on public.stats_entreprises to authenticated;
grant select on public.stats_entreprises to service_role;
