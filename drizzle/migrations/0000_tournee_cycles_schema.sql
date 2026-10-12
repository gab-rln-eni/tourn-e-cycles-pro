create type public.app_role as enum ('dirigeant','mecanicien','atelier');

create table public.acces (
  id uuid primary key default gen_random_uuid(),
  email text not null check (email = lower(email)),
  role public.app_role not null,
  expire_le timestamptz,
  revoque_le timestamptz,
  cree_par uuid,
  created_at timestamptz not null default now(),
  unique (email, role)
);
grant select on public.acces to authenticated;
grant all on public.acces to service_role;
alter table public.acces enable row level security;

create or replace function public.has_role(_user_id uuid, _role public.app_role)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from auth.users u
    join public.acces a on a.email = lower(u.email)
    where u.id = _user_id
      and u.email_confirmed_at is not null
      and a.role = _role
      and a.revoque_le is null
      and (a.expire_le is null or a.expire_le > now())
  )
$$;

create or replace function public.has_any_role(_roles public.app_role[])
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from unnest(_roles) r where public.has_role(auth.uid(), r))
$$;

create or replace function public.mes_roles()
returns public.app_role[] language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(r), '{}'::public.app_role[])
  from unnest(enum_range(null::public.app_role)) r
  where public.has_role(auth.uid(), r)
$$;

create policy acces_select on public.acces for select to authenticated
  using (public.has_role(auth.uid(), 'dirigeant'));

create or replace function public.code_court() returns text language sql volatile set search_path = public as $$
  select lower(substr(md5(gen_random_uuid()::text || clock_timestamp()::text), 1, 10))
$$;

create table public.entreprises (
  id uuid primary key default gen_random_uuid(),
  nom text not null check (char_length(nom) between 1 and 150),
  code text not null unique default public.code_court(),
  axonaut_client_id text,
  created_at timestamptz not null default now()
);
grant select, insert, update on public.entreprises to authenticated;
grant all on public.entreprises to service_role;
alter table public.entreprises enable row level security;
create policy ent_select on public.entreprises for select to authenticated
  using (public.has_any_role(array['dirigeant','mecanicien','atelier']::public.app_role[]));
create policy ent_insert on public.entreprises for insert to authenticated
  with check (public.has_role(auth.uid(), 'dirigeant'));
create policy ent_update on public.entreprises for update to authenticated
  using (public.has_role(auth.uid(), 'dirigeant'));

create table public.evenements (
  id uuid primary key default gen_random_uuid(),
  entreprise_id uuid not null references public.entreprises(id) on delete cascade,
  site text not null check (char_length(site) between 1 and 150),
  adresse text not null default '' check (char_length(adresse) <= 300),
  date_intervention date not null,
  places_max integer check (places_max is null or places_max > 0),
  statut text not null default 'ouvert' check (statut in ('ouvert','clos')),
  code text not null unique default public.code_court(),
  cree_par uuid default auth.uid(),
  created_at timestamptz not null default now()
);
grant select, insert, update on public.evenements to authenticated;
grant all on public.evenements to service_role;
alter table public.evenements enable row level security;
create policy ev_select on public.evenements for select to authenticated
  using (public.has_any_role(array['dirigeant','mecanicien','atelier']::public.app_role[]));
create policy ev_insert on public.evenements for insert to authenticated
  with check (public.has_role(auth.uid(), 'dirigeant'));
create policy ev_update on public.evenements for update to authenticated
  using (public.has_role(auth.uid(), 'dirigeant'));

create table public.inscriptions (
  id uuid primary key default gen_random_uuid(),
  evenement_id uuid not null references public.evenements(id) on delete cascade,
  nom text not null,
  prenom text not null,
  telephone text not null,
  email text not null,
  code_postal text not null,
  type_velo text not null check (type_velo in ('vae','musculaire')),
  velo_modele text,
  partie_signalee text not null check (partie_signalee in ('freins','roues','transmission','direction','cadre','autre','inconnu')),
  probleme_percu text,
  consentement_le timestamptz not null,
  axonaut_client_id text,
  created_at timestamptz not null default now()
);
grant select on public.inscriptions to authenticated;
grant all on public.inscriptions to service_role;
alter table public.inscriptions enable row level security;
create policy insc_select on public.inscriptions for select to authenticated
  using (public.has_any_role(array['dirigeant','mecanicien','atelier']::public.app_role[]));

create table public.fiches (
  id uuid primary key default gen_random_uuid(),
  inscription_id uuid not null unique references public.inscriptions(id) on delete cascade,
  mecanicien_id uuid default auth.uid(),
  statut text not null default 'en_cours' check (statut in ('en_cours','terminee')),
  commentaire text check (commentaire is null or char_length(commentaire) <= 2000),
  debut_le timestamptz not null default now(),
  termine_le timestamptz
);
grant select, insert, update on public.fiches to authenticated;
grant all on public.fiches to service_role;
alter table public.fiches enable row level security;
create policy fiche_select on public.fiches for select to authenticated
  using (public.has_any_role(array['dirigeant','mecanicien','atelier']::public.app_role[]));
create policy fiche_insert on public.fiches for insert to authenticated
  with check (public.has_any_role(array['dirigeant','mecanicien']::public.app_role[]) and statut = 'en_cours');
create policy fiche_update on public.fiches for update to authenticated
  using (public.has_any_role(array['dirigeant','mecanicien']::public.app_role[]) and statut = 'en_cours')
  with check (statut = 'en_cours');

create table public.fiche_points (
  id uuid primary key default gen_random_uuid(),
  fiche_id uuid not null references public.fiches(id) on delete cascade,
  groupe text not null,
  point text not null,
  etat text not null default 'bon' check (etat in ('bon','a_regler','a_reparer','a_changer')),
  constats text[] not null default '{}',
  remarque text check (remarque is null or char_length(remarque) <= 500),
  unique (fiche_id, groupe, point)
);
grant select, insert, update, delete on public.fiche_points to authenticated;
grant all on public.fiche_points to service_role;
alter table public.fiche_points enable row level security;
create policy fp_select on public.fiche_points for select to authenticated
  using (public.has_any_role(array['dirigeant','mecanicien','atelier']::public.app_role[]));
create policy fp_write on public.fiche_points for all to authenticated
  using (public.has_any_role(array['dirigeant','mecanicien']::public.app_role[])
    and exists (select 1 from public.fiches f where f.id = fiche_id and f.statut = 'en_cours'))
  with check (public.has_any_role(array['dirigeant','mecanicien']::public.app_role[])
    and exists (select 1 from public.fiches f where f.id = fiche_id and f.statut = 'en_cours'));

create table public.pieces_catalogue (
  id uuid primary key default gen_random_uuid(),
  reference text not null,
  libelle text not null,
  prix_vente_ht numeric(10,2) not null default 0,
  taux_tva numeric(5,2) not null default 20,
  axonaut_produit_id text,
  actif boolean not null default true
);
grant select on public.pieces_catalogue to authenticated;
grant all on public.pieces_catalogue to service_role;
alter table public.pieces_catalogue enable row level security;
create policy cat_select on public.pieces_catalogue for select to authenticated
  using (public.has_any_role(array['dirigeant','mecanicien','atelier']::public.app_role[]));

create table public.pieces_posees (
  id uuid primary key default gen_random_uuid(),
  fiche_id uuid not null references public.fiches(id) on delete cascade,
  piece_id uuid references public.pieces_catalogue(id),
  libelle text not null check (char_length(libelle) between 1 and 200),
  quantite numeric(10,2) not null default 1 check (quantite > 0),
  prix_unitaire_ht numeric(10,2) not null default 0 check (prix_unitaire_ht >= 0),
  a_commander boolean not null default false,
  created_at timestamptz not null default now()
);
grant select, insert, update, delete on public.pieces_posees to authenticated;
grant all on public.pieces_posees to service_role;
alter table public.pieces_posees enable row level security;
create policy pp_select on public.pieces_posees for select to authenticated
  using (public.has_any_role(array['dirigeant','mecanicien','atelier']::public.app_role[]));
create policy pp_write on public.pieces_posees for all to authenticated
  using (public.has_any_role(array['dirigeant','mecanicien']::public.app_role[])
    and exists (select 1 from public.fiches f where f.id = fiche_id and f.statut = 'en_cours'))
  with check (public.has_any_role(array['dirigeant','mecanicien']::public.app_role[])
    and exists (select 1 from public.fiches f where f.id = fiche_id and f.statut = 'en_cours'));

create table public.factures (
  id uuid primary key default gen_random_uuid(),
  inscription_id uuid not null unique references public.inscriptions(id) on delete cascade,
  statut text not null default 'a_preparer' check (statut in ('a_preparer','brouillon','a_valider','validee','envoyee','echec')),
  axonaut_facture_id text,
  prete_par uuid,
  prete_le timestamptz,
  validee_par uuid,
  validee_le timestamptz,
  envoyee_le timestamptz,
  detail text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
grant select, update on public.factures to authenticated;
grant all on public.factures to service_role;
alter table public.factures enable row level security;
create policy fac_select on public.factures for select to authenticated
  using (public.has_any_role(array['dirigeant','atelier']::public.app_role[]));
create policy fac_update on public.factures for update to authenticated
  using (public.has_any_role(array['dirigeant','atelier']::public.app_role[]) and statut not in ('validee','envoyee'))
  with check (statut in ('a_preparer','brouillon','a_valider','echec'));

create or replace function public.touch_updated_at() returns trigger language plpgsql set search_path = public as $$
begin new.updated_at := now(); return new; end $$;
create trigger factures_updated before update on public.factures
  for each row execute function public.touch_updated_at();

create table public.facture_lignes (
  id uuid primary key default gen_random_uuid(),
  facture_id uuid not null references public.factures(id) on delete cascade,
  libelle text not null check (char_length(libelle) between 1 and 200),
  quantite numeric(10,2) not null default 1 check (quantite > 0),
  prix_unitaire_ht numeric(10,2) not null default 0 check (prix_unitaire_ht >= 0),
  taux_tva numeric(5,2) not null default 20,
  ordre integer not null default 0
);
grant select, insert, update, delete on public.facture_lignes to authenticated;
grant all on public.facture_lignes to service_role;
alter table public.facture_lignes enable row level security;
create policy fl_select on public.facture_lignes for select to authenticated
  using (public.has_any_role(array['dirigeant','atelier']::public.app_role[]));
create policy fl_write on public.facture_lignes for all to authenticated
  using (public.has_any_role(array['dirigeant','atelier']::public.app_role[])
    and exists (select 1 from public.factures f where f.id = facture_id and f.statut not in ('validee','envoyee')))
  with check (public.has_any_role(array['dirigeant','atelier']::public.app_role[])
    and exists (select 1 from public.factures f where f.id = facture_id and f.statut not in ('validee','envoyee')));

create table public.avis_controle (
  id uuid primary key default gen_random_uuid(),
  facture_id uuid not null references public.factures(id) on delete cascade,
  source text not null check (source in ('regles','ia')),
  niveau text not null check (niveau in ('ok','attention','erreur')),
  message text not null,
  created_at timestamptz not null default now()
);
grant select on public.avis_controle to authenticated;
grant all on public.avis_controle to service_role;
alter table public.avis_controle enable row level security;
create policy avis_select on public.avis_controle for select to authenticated
  using (public.has_any_role(array['dirigeant','atelier']::public.app_role[]));

create table public.demandes_automatisation (
  id uuid primary key default gen_random_uuid(),
  type text not null check (type in ('client','commande','brouillon','controle','envoi')),
  objet_id uuid not null,
  statut text not null default 'a_faire' check (statut in ('a_faire','en_cours','fait','echec')),
  tentatives integer not null default 0,
  derniere_erreur text,
  created_at timestamptz not null default now(),
  termine_le timestamptz
);
grant select on public.demandes_automatisation to authenticated;
grant all on public.demandes_automatisation to service_role;
alter table public.demandes_automatisation enable row level security;
create policy dem_select on public.demandes_automatisation for select to authenticated
  using (public.has_any_role(array['dirigeant','atelier']::public.app_role[]));

-- Fonctions métier
create or replace function public.evenements_ouverts(p_code_entreprise text)
returns jsonb language sql stable security definer set search_path = public as $$
  select case when e.id is null then null else jsonb_build_object(
    'entreprise', e.nom,
    'evenements', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', ev.id, 'site', ev.site, 'adresse', ev.adresse,
        'date_intervention', ev.date_intervention, 'code', ev.code,
        'complet', (ev.places_max is not null and (select count(*) from public.inscriptions i where i.evenement_id = ev.id) >= ev.places_max)
      ) order by ev.date_intervention)
      from public.evenements ev
      where ev.entreprise_id = e.id and ev.statut = 'ouvert' and ev.date_intervention >= current_date
    ), '[]'::jsonb)) end
  from (select 1) x left join public.entreprises e on e.code = p_code_entreprise
$$;

create or replace function public.inscrire(p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_ent public.entreprises;
  v_ev public.evenements;
  v_nb integer;
  v_id uuid;
  v_nom text := btrim(coalesce(p->>'nom',''));
  v_prenom text := btrim(coalesce(p->>'prenom',''));
  v_tel text := regexp_replace(coalesce(p->>'telephone',''), '[\s\.\-]', '', 'g');
  v_email text := lower(btrim(coalesce(p->>'email','')));
  v_cp text := btrim(coalesce(p->>'code_postal',''));
  v_type text := coalesce(p->>'type_velo','');
  v_partie text := coalesce(p->>'partie_signalee','');
  v_modele text := nullif(btrim(coalesce(p->>'velo_modele','')), '');
  v_pb text := nullif(btrim(coalesce(p->>'probleme_percu','')), '');
  v_evid text := coalesce(p->>'evenement_id','');
begin
  select * into v_ent from public.entreprises where code = coalesce(p->>'code_entreprise','');
  if not found then raise exception 'Utilisez le lien transmis par votre entreprise.'; end if;
  if v_evid !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    raise exception 'Choisissez votre journée.'; end if;
  select * into v_ev from public.evenements where id = v_evid::uuid and entreprise_id = v_ent.id for update;
  if not found then raise exception 'Choisissez votre journée.'; end if;
  if v_ev.statut <> 'ouvert' or v_ev.date_intervention < current_date then
    raise exception 'Les inscriptions pour cette journée sont closes.'; end if;
  select count(*) into v_nb from public.inscriptions where evenement_id = v_ev.id;
  if v_ev.places_max is not null and v_nb >= v_ev.places_max then
    raise exception 'Cette journée est complète.'; end if;
  if char_length(v_nom) < 1 or char_length(v_nom) > 100 then raise exception 'Indiquez votre nom (100 caractères au plus).'; end if;
  if char_length(v_prenom) < 1 or char_length(v_prenom) > 100 then raise exception 'Indiquez votre prénom (100 caractères au plus).'; end if;
  if v_tel !~ '^[0-9]{10}$' then raise exception 'Le téléphone doit comporter 10 chiffres.'; end if;
  if char_length(v_email) > 255 or v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'L''adresse email n''est pas valide.'; end if;
  if v_cp !~ '^[0-9]{5}$' then raise exception 'Le code postal doit comporter 5 chiffres.'; end if;
  if v_type not in ('vae','musculaire') then raise exception 'Choisissez le type de vélo.'; end if;
  if v_partie not in ('freins','roues','transmission','direction','cadre','autre','inconnu') then raise exception 'Choisissez la partie du vélo qui pose problème.'; end if;
  if v_modele is not null and char_length(v_modele) > 100 then raise exception 'Marque et modèle : 100 caractères au plus.'; end if;
  if v_pb is not null and char_length(v_pb) > 300 then raise exception 'Description : 300 caractères au plus.'; end if;
  if coalesce((p->>'consentement')::boolean, false) is not true then raise exception 'Vous devez cocher la case de consentement.'; end if;

  insert into public.inscriptions(evenement_id, nom, prenom, telephone, email, code_postal, type_velo, velo_modele, partie_signalee, probleme_percu, consentement_le)
  values (v_ev.id, v_nom, v_prenom, v_tel, v_email, v_cp, v_type, v_modele, v_partie, v_pb, now())
  returning id into v_id;
  insert into public.demandes_automatisation(type, objet_id) values ('client', v_id);
  return jsonb_build_object('entreprise', v_ent.nom, 'site', v_ev.site, 'adresse', v_ev.adresse, 'date_intervention', v_ev.date_intervention);
end $$;

create or replace function public.terminer_fiche(p_fiche uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_f public.fiches; v_fac uuid; v_ev uuid;
begin
  if not public.has_any_role(array['dirigeant','mecanicien']::public.app_role[]) then raise exception 'Accès refusé.'; end if;
  select * into v_f from public.fiches where id = p_fiche for update;
  if not found then raise exception 'Fiche introuvable.'; end if;
  if v_f.statut = 'terminee' then raise exception 'Cette fiche est déjà terminée.'; end if;
  update public.fiches set statut = 'terminee', termine_le = now() where id = p_fiche;
  insert into public.factures(inscription_id) values (v_f.inscription_id)
    on conflict (inscription_id) do nothing returning id into v_fac;
  if v_fac is not null then
    insert into public.facture_lignes(facture_id, libelle, quantite, prix_unitaire_ht, taux_tva, ordre)
    select v_fac, pp.libelle, pp.quantite, pp.prix_unitaire_ht, coalesce(pc.taux_tva, 20),
           row_number() over (order by pp.created_at)
    from public.pieces_posees pp left join public.pieces_catalogue pc on pc.id = pp.piece_id
    where pp.fiche_id = p_fiche;
    insert into public.demandes_automatisation(type, objet_id) values ('brouillon', v_fac);
  end if;
  if exists (select 1 from public.pieces_posees where fiche_id = p_fiche and a_commander) then
    select evenement_id into v_ev from public.inscriptions where id = v_f.inscription_id;
    insert into public.demandes_automatisation(type, objet_id) values ('commande', v_ev);
  end if;
  return v_fac;
end $$;

create or replace function public.controler_facture(p_facture uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_insc uuid; v_email text; v_fiche uuid; v_n integer := 0; r record;
begin
  if not public.has_any_role(array['dirigeant','atelier']::public.app_role[]) then raise exception 'Accès refusé.'; end if;
  select f.inscription_id, i.email into v_insc, v_email
    from public.factures f join public.inscriptions i on i.id = f.inscription_id where f.id = p_facture;
  if not found then raise exception 'Facture introuvable.'; end if;
  select id into v_fiche from public.fiches where inscription_id = v_insc;
  delete from public.avis_controle where facture_id = p_facture and source = 'regles';

  if not exists (select 1 from public.facture_lignes where facture_id = p_facture) then
    insert into public.avis_controle(facture_id, source, niveau, message)
      values (p_facture, 'regles', 'erreur', 'La facture ne contient aucune ligne.');
    v_n := v_n + 1;
  end if;

  for r in
    select l.libelle, l.prix_unitaire_ht, c.prix_vente_ht
    from public.facture_lignes l
    join public.pieces_catalogue c on lower(c.libelle) = lower(l.libelle)
    where l.facture_id = p_facture and c.prix_vente_ht > 0
      and abs(l.prix_unitaire_ht - c.prix_vente_ht) > 0.2 * c.prix_vente_ht
  loop
    insert into public.avis_controle(facture_id, source, niveau, message)
      values (p_facture, 'regles', 'attention',
        format('Le prix de « %s » (%s € HT) s''écarte de plus de 20 %% du prix catalogue (%s € HT).',
          r.libelle, replace(r.prix_unitaire_ht::text, '.', ','), replace(r.prix_vente_ht::text, '.', ',')));
    v_n := v_n + 1;
  end loop;

  if v_fiche is not null
     and exists (select 1 from public.fiche_points where fiche_id = v_fiche and etat = 'a_changer')
     and not exists (select 1 from public.pieces_posees where fiche_id = v_fiche) then
    insert into public.avis_controle(facture_id, source, niveau, message)
      values (p_facture, 'regles', 'attention', 'Un point est marqué « À changer » mais aucune pièce n''a été posée.');
    v_n := v_n + 1;
  end if;

  if v_email is null or btrim(v_email) = '' then
    insert into public.avis_controle(facture_id, source, niveau, message)
      values (p_facture, 'regles', 'erreur', 'L''email du client est absent.');
    v_n := v_n + 1;
  end if;

  if v_n = 0 then
    insert into public.avis_controle(facture_id, source, niveau, message)
      values (p_facture, 'regles', 'ok', 'Aucune anomalie détectée par les contrôles simples.');
  end if;
end $$;

create or replace function public.valider_facture(p_facture uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_statut text;
begin
  if not public.has_role(auth.uid(), 'dirigeant') then raise exception 'Seul le dirigeant peut valider une facture.'; end if;
  select statut into v_statut from public.factures where id = p_facture for update;
  if not found then raise exception 'Facture introuvable.'; end if;
  if v_statut <> 'a_valider' then raise exception 'La facture doit être « à valider » pour être validée.'; end if;
  update public.factures set statut = 'validee', validee_par = auth.uid(), validee_le = now() where id = p_facture;
  insert into public.demandes_automatisation(type, objet_id) values ('envoi', p_facture);
end $$;

create or replace function public.email_utilisateur(p_user uuid)
returns text language sql stable security definer set search_path = public as $$
  select case when public.has_any_role(array['dirigeant','mecanicien','atelier']::public.app_role[])
    then (select email from auth.users where id = p_user) end
$$;

revoke execute on function public.evenements_ouverts(text) from public;
revoke execute on function public.inscrire(jsonb) from public;
revoke execute on function public.terminer_fiche(uuid) from public;
revoke execute on function public.controler_facture(uuid) from public;
revoke execute on function public.valider_facture(uuid) from public;
revoke execute on function public.email_utilisateur(uuid) from public;
revoke execute on function public.mes_roles() from public;
grant execute on function public.evenements_ouverts(text) to anon, authenticated;
grant execute on function public.inscrire(jsonb) to anon, authenticated;
grant execute on function public.terminer_fiche(uuid) to authenticated;
grant execute on function public.controler_facture(uuid) to authenticated;
grant execute on function public.valider_facture(uuid) to authenticated;
grant execute on function public.email_utilisateur(uuid) to authenticated;
grant execute on function public.mes_roles() to authenticated;
grant execute on function public.has_role(uuid, public.app_role) to authenticated;
grant execute on function public.has_any_role(public.app_role[]) to authenticated;