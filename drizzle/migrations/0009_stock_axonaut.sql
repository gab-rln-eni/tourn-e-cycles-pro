-- Stock Axonaut (agent STOCK, 2026-10-14, dérogation de G_R ; D8 modifiée par G_R, D9 c ; brèche TC-91).
-- Objets NEUFS seulement ; aucune table, fonction, contrainte ou règle d'accès existante n'est modifiée.
--   catalogue_axonaut : correspondance pièce du catalogue -> produit Axonaut de référence (pieces_catalogue.axonaut_produit_id reste gelée et vide).
--   stock_axonaut : dernier stock lu dans Axonaut par le workflow TC_33.
--   axonaut_produit_ligne : règle de correspondance d'une ligne (libellé exact du catalogue, sinon produit générique).
--     LIMITE : facture_lignes n'a pas de piece_id ; une ligne de catalogue dont le libellé a été retouché tombe sur le générique.
--   donnees_demande_v2 : même contrat que donnees_demande, plus axonaut_produit_id dans chaque ligne de 'envoi' (les autres types sont inchangés).
--   reserver_demandes_v2 : copie de reserver_demandes qui lit donnees_demande_v2. ATTENTION : réserve dans la même table que le chemin
--     actuel ; jamais appelée en base réelle avant la bascule (premier appel réel : TC_00 v3 publié).
--   catalogue_axonaut_liste, stock_axonaut_ecrire : routes de n8n (service_role seulement).
--   stock_pieces : lecture du stock par l'écran du devis (SECURITY DEFINER, rôles de l'atelier).
-- Aucune clé étrangère ni déclencheur ; RLS active ; REVOKE public, anon, authenticated puis droits nécessaires seulement.
-- Rejouable (if not exists, create or replace). Retour arrière : bloc commenté en fin de fichier.

create table if not exists public.catalogue_axonaut (
  id uuid primary key default gen_random_uuid(),
  piece_id uuid unique,
  role text not null check (role in ('piece', 'main_oeuvre', 'generique')),
  reference text not null unique check (char_length(reference) between 1 and 60),
  libelle text not null check (char_length(libelle) between 1 and 200),
  axonaut_produit_id text not null unique check (axonaut_produit_id ~ '^[0-9]{1,18}$'),
  suivi_stock boolean not null,
  created_at timestamptz not null default now(),
  check ((role = 'generique') = (piece_id is null)),
  check (role = 'piece' or not suivi_stock)
);
create unique index if not exists catalogue_axonaut_un_generique on public.catalogue_axonaut (role) where role = 'generique';

create table if not exists public.stock_axonaut (
  axonaut_produit_id text primary key check (axonaut_produit_id ~ '^[0-9]{1,18}$'),
  stock numeric(12,3),
  lu_le timestamptz not null default now()
);

alter table public.catalogue_axonaut enable row level security;
alter table public.stock_axonaut enable row level security;
revoke all on table public.catalogue_axonaut, public.stock_axonaut from public, anon, authenticated;
grant all on table public.catalogue_axonaut, public.stock_axonaut to service_role;

-- Produit Axonaut d'une ligne : libellé exact d'une pièce du catalogue reliée, sinon produit générique, sinon null.
create or replace function public.axonaut_produit_ligne(p_libelle text)
returns text language sql stable security definer set search_path = public as $$
  select coalesce(
    (select ca.axonaut_produit_id from public.pieces_catalogue pc
       join public.catalogue_axonaut ca on ca.piece_id = pc.id
      where pc.libelle = p_libelle order by pc.actif desc, ca.created_at limit 1),
    (select ca.axonaut_produit_id from public.catalogue_axonaut ca where ca.role = 'generique' limit 1))
$$;

create or replace function public.donnees_demande_v2(p_type text, p_objet uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v jsonb;
begin
  v := public.donnees_demande(p_type, p_objet);
  if p_type = 'envoi' and v is not null and jsonb_typeof(v->'lignes') = 'array' then
    v := jsonb_set(v, '{lignes}', coalesce((
      select jsonb_agg(l.e || jsonb_build_object('axonaut_produit_id', coalesce(public.axonaut_produit_ligne(l.e->>'libelle'), ''))
                       order by l.n)
      from jsonb_array_elements(v->'lignes') with ordinality as l(e, n)), '[]'::jsonb));
  end if;
  return v;
end $$;

create or replace function public.reserver_demandes_v2(p_limite integer default 10)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_res jsonb := '[]'::jsonb; r record;
begin
  -- Copie de reserver_demandes (migration 0002), seule différence : donnees_demande_v2.
  update public.demandes_automatisation
    set statut = case when tentatives >= 3 then 'echec' else 'a_faire' end,
        derniere_erreur = case when tentatives >= 3 then 'Délai dépassé après 3 tentatives.' else derniere_erreur end,
        termine_le = case when tentatives >= 3 then now() else termine_le end
    where statut = 'en_cours' and pris_le < now() - interval '15 minutes';

  for r in
    with prises as (
      select d.id from public.demandes_automatisation d
      where d.statut = 'a_faire'
        and d.type in ('client', 'commande', 'controle', 'envoi')
        and (d.type <> 'envoi' or exists (select 1 from public.factures fa where fa.id = d.objet_id and fa.statut = 'validee'))
      order by d.created_at
      limit greatest(1, least(coalesce(p_limite, 10), 50))
      for update skip locked
    )
    update public.demandes_automatisation d
      set statut = 'en_cours', tentatives = d.tentatives + 1, pris_le = now()
      from prises where d.id = prises.id
      returning d.id, d.type, d.objet_id, d.created_at
  loop
    v_res := v_res || jsonb_build_array(jsonb_build_object(
      'demande_id', r.id, 'type', r.type, 'donnees', public.donnees_demande_v2(r.type, r.objet_id)));
  end loop;
  return v_res;
end $$;

-- Correspondance lue par n8n (TC_20 v3, TC_33) : une ligne par produit de référence, libellé courant du catalogue.
create or replace function public.catalogue_axonaut_liste()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'reference', ca.reference, 'libelle', coalesce(pc.libelle, ca.libelle), 'role', ca.role,
           'axonaut_produit_id', ca.axonaut_produit_id, 'suivi_stock', ca.suivi_stock) order by ca.role, ca.reference), '[]'::jsonb)
  from public.catalogue_axonaut ca left join public.pieces_catalogue pc on pc.id = ca.piece_id
$$;

-- Écriture du stock lu par TC_33 : { stocks: [ { axonaut_produit_id, stock } ] } ; seuls les produits suivis en stock sont écrits ;
-- stock null (lecture en échec) : la ligne est écrite avec stock null, l'écran affiche « inconnu ».
create or replace function public.stock_axonaut_ecrire(p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare n integer := 0; ignores integer := 0; e jsonb;
begin
  if jsonb_typeof(p->'stocks') <> 'array' then
    return jsonb_build_object('ok', false, 'erreur', 'stocks attendu (tableau)');
  end if;
  for e in select * from jsonb_array_elements(p->'stocks') loop
    if exists (select 1 from public.catalogue_axonaut ca where ca.axonaut_produit_id = e->>'axonaut_produit_id' and ca.suivi_stock)
       and (e->'stock' is null or jsonb_typeof(e->'stock') in ('number', 'null')) then
      insert into public.stock_axonaut (axonaut_produit_id, stock, lu_le)
      values (e->>'axonaut_produit_id', case when jsonb_typeof(e->'stock') = 'number' then (e->>'stock')::numeric end, now())
      on conflict (axonaut_produit_id) do update set stock = excluded.stock, lu_le = excluded.lu_le;
      n := n + 1;
    else
      ignores := ignores + 1;
    end if;
  end loop;
  return jsonb_build_object('ok', true, 'ecrits', n, 'ignores', ignores);
end $$;

-- Stock affiché à l'écran du devis : une ligne par pièce active ; etat 'en_stock' (stock > 0), 'a_commander' (stock <= 0),
-- 'inconnu' (pièce non reliée, sans suivi de stock, jamais lue, ou lecture en échec).
create or replace function public.stock_pieces()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.has_any_role(array['dirigeant','mecanicien','atelier']::public.app_role[]) then raise exception 'Accès refusé.'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('piece_id', pc.id,
             'etat', case when ca.id is null or not ca.suivi_stock or sa.stock is null then 'inconnu'
                          when sa.stock > 0 then 'en_stock' else 'a_commander' end,
             'lu_le', sa.lu_le) order by pc.libelle)
    from public.pieces_catalogue pc
    left join public.catalogue_axonaut ca on ca.piece_id = pc.id
    left join public.stock_axonaut sa on sa.axonaut_produit_id = ca.axonaut_produit_id
    where pc.actif), '[]'::jsonb);
end $$;

revoke all on function public.axonaut_produit_ligne(text), public.donnees_demande_v2(text, uuid), public.reserver_demandes_v2(integer),
  public.catalogue_axonaut_liste(), public.stock_axonaut_ecrire(jsonb), public.stock_pieces() from public, anon, authenticated;
grant execute on function public.axonaut_produit_ligne(text), public.donnees_demande_v2(text, uuid), public.reserver_demandes_v2(integer),
  public.catalogue_axonaut_liste(), public.stock_axonaut_ecrire(jsonb), public.stock_pieces() to service_role;
grant execute on function public.stock_pieces() to authenticated;

-- Retour arrière (objets neufs seulement ; jamais exécuté sans visa) :
-- drop function if exists public.stock_pieces();
-- drop function if exists public.stock_axonaut_ecrire(jsonb);
-- drop function if exists public.catalogue_axonaut_liste();
-- drop function if exists public.reserver_demandes_v2(integer);
-- drop function if exists public.donnees_demande_v2(text, uuid);
-- drop function if exists public.axonaut_produit_ligne(text);
-- drop table if exists public.stock_axonaut;
-- drop table if exists public.catalogue_axonaut;
