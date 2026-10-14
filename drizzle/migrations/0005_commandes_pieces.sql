-- 0005_commandes_pieces.sql : lot L1, pièces à commander (agent LOTS, 2026-10-14, visa G_R de l'après-midi).
-- Objets NEUFS seulement : aucune table, colonne, fonction, contrainte ni règle d'accès existante n'est modifiée.
-- Aucune clé étrangère vers une table existante (pieces_posees comprise) ; aucun déclencheur sur une table existante.
-- Accès : aucun droit direct sur les tables neuves pour anon et authenticated ; tout passe par des fonctions SECURITY DEFINER.
-- Idempotent. Écart connu : non inscrit dans drizzle/migrations/meta/_journal.json (application par SQL direct, comme 0003 et 0004).

-- 1. Paramètres du lot : heure de mise en service de L1 (posée une seule fois, à la première application)
create table if not exists public.lots_parametres (
  cle text primary key,
  valeur timestamptz not null
);
insert into public.lots_parametres(cle, valeur) values ('l1_mise_en_service', now()) on conflict (cle) do nothing;

-- 2. État « commandée » d'une pièce marquée à commander (une ligne par pièce posée, sans clé étrangère)
create table if not exists public.commandes_pieces (
  piece_posee_id uuid primary key,
  commandee boolean not null default false,
  modifie_par uuid,
  modifie_le timestamptz not null default now()
);

-- 3. Rappels envoyés : au plus un par jour (heure de Paris)
create table if not exists public.rappels_commandes (
  jour date primary key,
  nb_pieces integer not null check (nb_pieces > 0),
  cree_le timestamptz not null default now()
);

alter table public.lots_parametres enable row level security;
alter table public.commandes_pieces enable row level security;
alter table public.rappels_commandes enable row level security;
revoke all on public.lots_parametres, public.commandes_pieces, public.rappels_commandes from public, anon, authenticated;
grant all on public.lots_parametres, public.commandes_pieces, public.rappels_commandes to service_role;

-- 4. Pièces à commander d'une fiche terminée : vue interne commune (fonction, pas de vue exposée)
create or replace function public.commandes_pieces_source()
returns table (piece_posee_id uuid, evenement_id uuid, date_intervention date, entreprise text, site text,
               fiche_reference text, client text, libelle text, reference text, quantite numeric,
               termine_le timestamptz, commandee boolean, modifie_le timestamptz, lots_test boolean)
language sql stable security definer set search_path = public as $$
  select pp.id, ev.id, ev.date_intervention, e.nom, ev.site, f.reference, i.prenom || ' ' || i.nom,
         pp.libelle, pc.reference, pp.quantite, f.termine_le,
         coalesce(cp.commandee, false), cp.modifie_le,
         (i.nom ilike 'LOTS-TEST%' or i.prenom ilike 'LOTS-TEST%' or pp.libelle ilike '%LOTS-TEST%')
  from public.pieces_posees pp
  join public.fiches f on f.id = pp.fiche_id and f.statut = 'terminee'
  join public.inscriptions i on i.id = f.inscription_id
  join public.evenements ev on ev.id = i.evenement_id
  join public.entreprises e on e.id = ev.entreprise_id
  left join public.pieces_catalogue pc on pc.id = pp.piece_id
  left join public.commandes_pieces cp on cp.piece_posee_id = pp.id
  where pp.a_commander
$$;

-- 5. Écran « À commander » : journées qui ont des pièces à commander (dirigeant et atelier)
create or replace function public.commandes_pieces_journees()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.has_any_role(array['dirigeant','atelier']::public.app_role[]) then raise exception 'Accès refusé.'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('evenement_id', x.evenement_id, 'date_intervention', x.date_intervention,
             'entreprise', x.entreprise, 'site', x.site, 'nb_pieces', x.nb, 'nb_a_commander', x.nb_a)
             order by x.date_intervention desc, x.entreprise, x.site)
    from (select s.evenement_id, s.date_intervention, s.entreprise, s.site, count(*) as nb,
                 count(*) filter (where not s.commandee) as nb_a
          from public.commandes_pieces_source() s
          group by s.evenement_id, s.date_intervention, s.entreprise, s.site) x), '[]'::jsonb);
end $$;

-- 6. Écran « À commander » : pièces d'une journée (dirigeant et atelier)
create or replace function public.commandes_pieces_journee(p_evenement uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.has_any_role(array['dirigeant','atelier']::public.app_role[]) then raise exception 'Accès refusé.'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('piece_posee_id', s.piece_posee_id, 'fiche_reference', s.fiche_reference,
             'client', s.client, 'libelle', s.libelle, 'reference', s.reference, 'quantite', s.quantite,
             'commandee', s.commandee, 'modifie_le', s.modifie_le)
             order by s.commandee, s.libelle, s.fiche_reference)
    from public.commandes_pieces_source() s where s.evenement_id = p_evenement), '[]'::jsonb);
end $$;

-- 7. Cocher ou décocher « commandée » (dirigeant et atelier ; pièce marquée à commander d'une fiche terminée seulement)
create or replace function public.commandes_pieces_marquer(p_piece uuid, p_commandee boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not public.has_any_role(array['dirigeant','atelier']::public.app_role[]) then raise exception 'Accès refusé.'; end if;
  if p_commandee is null then raise exception 'Indiquez si la pièce est commandée.'; end if;
  if not exists (select 1 from public.pieces_posees pp join public.fiches f on f.id = pp.fiche_id
                 where pp.id = p_piece and pp.a_commander and f.statut = 'terminee') then
    raise exception 'Pièce introuvable, non marquée à commander ou fiche non terminée.';
  end if;
  insert into public.commandes_pieces(piece_posee_id, commandee, modifie_par, modifie_le)
    values (p_piece, p_commandee, auth.uid(), now())
  on conflict (piece_posee_id) do update
    set commandee = excluded.commandee, modifie_par = excluded.modifie_par, modifie_le = excluded.modifie_le;
  return jsonb_build_object('ok', true, 'piece_posee_id', p_piece, 'commandee', p_commandee);
end $$;

-- 8. Rappel quotidien (route de l'app pour n8n, clé de service seulement).
--    Mode normal : pièces non commandées de fiches terminées APRÈS la mise en service de L1, hors LOTS-TEST,
--    hors journées du 15/10 et du 27/10 ; jour ouvré seulement ; réserve le jour (au plus un rappel par jour).
--    Mode essai : pièces LOTS-TEST seulement, sans réserver le jour (pour exercer le mail sans toucher aux vraies données).
create or replace function public.rappel_commandes_reserver(p_essai boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_jour date := (now() at time zone 'Europe/Paris')::date;
  v_mes timestamptz;
  v_pieces jsonb;
  v_nb integer;
begin
  select valeur into v_mes from public.lots_parametres where cle = 'l1_mise_en_service';
  select count(*), coalesce(jsonb_agg(jsonb_build_object('date_intervention', s.date_intervention, 'entreprise', s.entreprise,
           'site', s.site, 'fiche_reference', s.fiche_reference, 'libelle', s.libelle, 'reference', s.reference,
           'quantite', s.quantite) order by s.date_intervention, s.entreprise, s.site, s.libelle), '[]'::jsonb)
    into v_nb, v_pieces
  from public.commandes_pieces_source() s
  where not s.commandee
    and case when coalesce(p_essai, false) then s.lots_test
             else not s.lots_test and v_mes is not null and s.termine_le > v_mes
                  and s.date_intervention not in (date '2026-10-15', date '2026-10-27') end;

  if coalesce(p_essai, false) then
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

-- 9. Droits d'exécution : explicites (la base réelle accorde par défaut tout à anon sur un objet neuf)
revoke execute on function public.commandes_pieces_source() from public, anon, authenticated;
revoke execute on function public.commandes_pieces_journees() from public, anon, authenticated;
revoke execute on function public.commandes_pieces_journee(uuid) from public, anon, authenticated;
revoke execute on function public.commandes_pieces_marquer(uuid, boolean) from public, anon, authenticated;
revoke execute on function public.rappel_commandes_reserver(boolean) from public, anon, authenticated;
grant execute on function public.commandes_pieces_journees() to authenticated;
grant execute on function public.commandes_pieces_journee(uuid) to authenticated;
grant execute on function public.commandes_pieces_marquer(uuid, boolean) to authenticated;
grant execute on function public.commandes_pieces_source() to service_role;
grant execute on function public.rappel_commandes_reserver(boolean) to service_role;

-- Retour arrière (seulement sur visa, sans suppression) : neutraliser par REVOKE EXECUTE des quatre fonctions
-- pour authenticated et service_role ; les tables neuves restent, sans droit pour anon et authenticated.
