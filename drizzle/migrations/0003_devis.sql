-- 0003_devis.sql : parcours devis (agent DEVIS, nuit du 2026-10-14, dérogation de G_R).
-- Objets NEUFS seulement : aucune table, colonne, fonction, contrainte ou politique existante n'est modifiée.
-- Idempotent : tables et index IF NOT EXISTS, politiques et déclencheur créés seulement s'ils manquent,
-- fonctions neuves (préfixe devis_) recréées à l'identique en cas de nouvelle exécution.
-- Droits : la base accorde par défaut tous les droits à anon et authenticated sur toute table ou fonction neuve
-- (pg_default_acl relu le 2026-10-14) ; ils sont donc retirés explicitement, puis accordés au plus juste.
-- Écart connu : ce fichier n'est pas inscrit dans drizzle/migrations/meta/_journal.json (application par SQL direct).

-- 1. Tables
create table if not exists public.devis (
  id uuid primary key default gen_random_uuid(),
  fiche_id uuid references public.fiches(id) on delete cascade,
  reference text not null unique default ('DV-' || upper(substr(public.code_court(), 1, 8)))
    check (char_length(reference) between 3 and 40),
  statut text not null default 'brouillon'
    check (statut in ('brouillon', 'a_relire', 'envoye', 'accepte', 'refuse')),
  axonaut_client_id text check (axonaut_client_id is null or axonaut_client_id ~ '^[0-9]+$'),
  commentaire text check (commentaire is null or char_length(commentaire) <= 2000),
  jeton text unique check (jeton is null or jeton ~ '^[0-9a-f]{64}$'),
  axonaut_devis_id text,
  axonaut_numero text,
  axonaut_lien text,
  axonaut_decision_le timestamptz,
  derniere_erreur text,
  cree_par uuid,
  propose_le timestamptz,
  relu_par uuid,
  relu_le timestamptz,
  envoye_le timestamptz,
  decide_le timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.devis_lignes (
  id uuid primary key default gen_random_uuid(),
  devis_id uuid not null references public.devis(id) on delete cascade,
  ordre integer not null default 0,
  piece_id uuid references public.pieces_catalogue(id),
  libelle text not null check (char_length(libelle) between 1 and 200),
  quantite numeric(10,2) not null default 1 check (quantite > 0),
  prix_unitaire_ht numeric(10,2) not null default 0 check (prix_unitaire_ht >= 0),
  taux_tva numeric(5,2) not null default 20 check (taux_tva >= 0 and taux_tva <= 100),
  created_at timestamptz not null default now()
);

create index if not exists devis_fiche_id_idx on public.devis(fiche_id);
create index if not exists devis_lignes_devis_id_idx on public.devis_lignes(devis_id);

do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'devis_updated' and tgrelid = 'public.devis'::regclass) then
    create trigger devis_updated before update on public.devis
      for each row execute function public.touch_updated_at();
  end if;
end $$;

-- 2. Droits et RLS des tables (aucun droit d'anon)
revoke all on public.devis, public.devis_lignes from public, anon, authenticated;
grant select, insert, update on public.devis to authenticated;
grant select, insert, update, delete on public.devis_lignes to authenticated;
grant all on public.devis, public.devis_lignes to service_role;
alter table public.devis enable row level security;
alter table public.devis_lignes enable row level security;

do $$ begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'devis' and policyname = 'devis_select') then
    create policy devis_select on public.devis for select to authenticated
      using (public.has_any_role(array['dirigeant','mecanicien','atelier']::public.app_role[]));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'devis' and policyname = 'devis_insert') then
    create policy devis_insert on public.devis for insert to authenticated
      with check (public.has_any_role(array['dirigeant','mecanicien','atelier']::public.app_role[])
                  and statut = 'brouillon' and jeton is null and axonaut_devis_id is null);
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'devis' and policyname = 'devis_update') then
    create policy devis_update on public.devis for update to authenticated
      using (public.has_any_role(array['dirigeant','mecanicien','atelier']::public.app_role[])
             and statut in ('brouillon','a_relire'))
      with check (statut in ('brouillon','a_relire') and jeton is null and axonaut_devis_id is null);
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'devis_lignes' and policyname = 'dl_select') then
    create policy dl_select on public.devis_lignes for select to authenticated
      using (public.has_any_role(array['dirigeant','mecanicien','atelier']::public.app_role[]));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'devis_lignes' and policyname = 'dl_write') then
    create policy dl_write on public.devis_lignes for all to authenticated
      using (public.has_any_role(array['dirigeant','mecanicien','atelier']::public.app_role[])
             and exists (select 1 from public.devis d where d.id = devis_id and d.statut in ('brouillon','a_relire')))
      with check (public.has_any_role(array['dirigeant','mecanicien','atelier']::public.app_role[])
             and exists (select 1 from public.devis d where d.id = devis_id and d.statut in ('brouillon','a_relire')));
  end if;
end $$;

-- 3. Fonctions neuves
-- Totaux arrondis au centime, même règle que la facture : HT, TVA, TTC = HT + TVA
create or replace function public.devis_totaux(p_devis uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'total_ht', coalesce(round(sum(l.quantite * l.prix_unitaire_ht), 2), 0),
    'total_tva', coalesce(round(sum(l.quantite * l.prix_unitaire_ht * l.taux_tva / 100), 2), 0),
    'total_ttc', coalesce(round(sum(l.quantite * l.prix_unitaire_ht), 2), 0) + coalesce(round(sum(l.quantite * l.prix_unitaire_ht * l.taux_tva / 100), 2), 0))
  from public.devis_lignes l where l.devis_id = p_devis
$$;

-- Lignes au format attendu par n8n et par la page du cycliste (nombres JSON, ordre de saisie)
create or replace function public.devis_lignes_json(p_devis uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('libelle', l.libelle, 'quantite', l.quantite,
           'prix_unitaire_ht', l.prix_unitaire_ht, 'taux_tva', l.taux_tva) order by l.ordre, l.created_at), '[]'::jsonb)
  from public.devis_lignes l where l.devis_id = p_devis
$$;

-- Client Axonaut du devis : celui saisi sur le devis, sinon celui de l'inscription de la fiche
create or replace function public.devis_client_axonaut(p_devis uuid)
returns text language sql stable security definer set search_path = public as $$
  select coalesce(nullif(d.axonaut_client_id, ''), nullif(i.axonaut_client_id, ''))
  from public.devis d
  left join public.fiches f on f.id = d.fiche_id
  left join public.inscriptions i on i.id = f.inscription_id
  where d.id = p_devis
$$;

-- Contrôles simples (code classique, aucune IA) : [ { niveau 'ok'|'attention'|'erreur', message } ]
create or replace function public.devis_controles(p_devis uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_avis jsonb := '[]'::jsonb;
  v_nb integer;
  v_ttc numeric;
  r record;
begin
  if not public.has_any_role(array['dirigeant','mecanicien','atelier']::public.app_role[]) then
    raise exception 'Accès refusé.';
  end if;
  if not exists (select 1 from public.devis where id = p_devis) then raise exception 'Devis introuvable.'; end if;
  select count(*) into v_nb from public.devis_lignes where devis_id = p_devis;
  if v_nb = 0 then
    v_avis := v_avis || jsonb_build_array(jsonb_build_object('niveau', 'erreur', 'message', 'Le devis n''a aucune ligne.'));
  end if;
  if public.devis_client_axonaut(p_devis) is null then
    v_avis := v_avis || jsonb_build_array(jsonb_build_object('niveau', 'erreur', 'message', 'Le client n''est pas encore dans Axonaut.'));
  end if;
  for r in
    select l.libelle, l.prix_unitaire_ht, pc.prix_vente_ht
    from public.devis_lignes l left join public.pieces_catalogue pc on pc.id = l.piece_id
    where l.devis_id = p_devis order by l.ordre, l.created_at
  loop
    if r.prix_unitaire_ht = 0 then
      v_avis := v_avis || jsonb_build_array(jsonb_build_object('niveau', 'attention', 'message', 'Prix à zéro : ' || r.libelle));
    elsif r.prix_vente_ht is not null and r.prix_vente_ht > 0
          and abs(r.prix_unitaire_ht - r.prix_vente_ht) / r.prix_vente_ht > 0.20 then
      v_avis := v_avis || jsonb_build_array(jsonb_build_object('niveau', 'attention', 'message',
        'Prix éloigné du catalogue (' || r.prix_vente_ht || ' € HT) : ' || r.libelle));
    end if;
  end loop;
  v_ttc := (public.devis_totaux(p_devis)->>'total_ttc')::numeric;
  if v_nb > 0 and v_ttc = 0 then
    v_avis := v_avis || jsonb_build_array(jsonb_build_object('niveau', 'erreur', 'message', 'Le total du devis est nul.'));
  end if;
  if jsonb_array_length(v_avis) = 0 then
    v_avis := jsonb_build_array(jsonb_build_object('niveau', 'ok', 'message', 'Aucun point à signaler.'));
  end if;
  return v_avis;
end $$;

-- Proposer le devis à la relecture de l'atelier (mécanicien, atelier ou dirigeant)
create or replace function public.devis_proposer(p_devis uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_d public.devis;
begin
  if not public.has_any_role(array['dirigeant','mecanicien','atelier']::public.app_role[]) then raise exception 'Accès refusé.'; end if;
  select * into v_d from public.devis where id = p_devis for update;
  if not found then raise exception 'Devis introuvable.'; end if;
  if v_d.statut <> 'brouillon' then raise exception 'Seul un brouillon peut être proposé.'; end if;
  if not exists (select 1 from public.devis_lignes where devis_id = p_devis) then raise exception 'Le devis n''a aucune ligne.'; end if;
  update public.devis set statut = 'a_relire', propose_le = now() where id = p_devis;
end $$;

-- Relecture par l'atelier ou le dirigeant : contrôles sans erreur, jeton créé, données d'envoi pour n8n renvoyées.
-- Le statut reste 'a_relire' jusqu'à la réponse de n8n (devis_noter_envoi) ; une reprise renvoie le même jeton.
create or replace function public.devis_preparer_envoi(p_devis uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_d public.devis;
  v_avis jsonb;
  v_t jsonb;
begin
  if not public.has_any_role(array['dirigeant','atelier']::public.app_role[]) then raise exception 'Accès refusé.'; end if;
  select * into v_d from public.devis where id = p_devis for update;
  if not found then raise exception 'Devis introuvable.'; end if;
  if v_d.statut <> 'a_relire' then raise exception 'Le devis doit être à relire.'; end if;
  v_avis := public.devis_controles(p_devis);
  if exists (select 1 from jsonb_array_elements(v_avis) a where a->>'niveau' = 'erreur') then
    return jsonb_build_object('ok', false, 'avis', v_avis);
  end if;
  update public.devis
     set relu_par = auth.uid(), relu_le = now(), derniere_erreur = null,
         jeton = coalesce(jeton, replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', ''))
   where id = p_devis returning * into v_d;
  v_t := public.devis_totaux(p_devis);
  return jsonb_build_object('ok', true, 'avis', v_avis, 'jeton', v_d.jeton, 'donnees', jsonb_build_object(
    'devis_id', v_d.id, 'reference', v_d.reference, 'axonaut_client_id', public.devis_client_axonaut(p_devis),
    'commentaire', coalesce(v_d.commentaire, ''), 'lignes', public.devis_lignes_json(p_devis),
    'total_ht', v_t->'total_ht', 'total_tva', v_t->'total_tva', 'total_ttc', v_t->'total_ttc'));
end $$;

-- Réponse de n8n à la création du devis dans Axonaut (fonction serveur seulement, rôle service_role)
create or replace function public.devis_noter_envoi(p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_d public.devis;
begin
  select * into v_d from public.devis where id = (p->>'devis_id')::uuid for update;
  if not found then return jsonb_build_object('ok', false, 'erreur', 'devis introuvable'); end if;
  if coalesce((p->>'ok')::boolean, false) and coalesce(p->>'axonaut_devis_id', '') <> '' then
    if v_d.statut not in ('a_relire', 'envoye') then
      return jsonb_build_object('ok', false, 'erreur', 'statut ' || v_d.statut);
    end if;
    update public.devis set statut = 'envoye', envoye_le = coalesce(envoye_le, now()),
           axonaut_devis_id = p->>'axonaut_devis_id', axonaut_numero = nullif(p->>'numero', ''),
           axonaut_lien = nullif(p->>'public_path', ''), derniere_erreur = null
     where id = v_d.id;
    return jsonb_build_object('ok', true, 'statut', 'envoye');
  end if;
  update public.devis set derniere_erreur = left(coalesce(nullif(p->>'erreur', ''), 'échec sans message'), 500) where id = v_d.id;
  return jsonb_build_object('ok', true, 'statut', v_d.statut);
end $$;

-- Page du cycliste, par jeton : aucune donnée personnelle (ni nom, ni email, ni téléphone)
create or replace function public.devis_public(p_jeton text)
returns jsonb language sql stable security definer set search_path = public as $$
  select case when d.id is null then null else jsonb_build_object(
    'reference', d.reference, 'statut', d.statut, 'commentaire', coalesce(d.commentaire, ''),
    'envoye_le', d.envoye_le, 'decide_le', d.decide_le, 'lignes', public.devis_lignes_json(d.id))
    || public.devis_totaux(d.id) end
  from (select 1) x
  left join public.devis d on p_jeton ~ '^[0-9a-f]{64}$' and d.jeton = p_jeton and d.statut in ('envoye', 'accepte', 'refuse')
$$;

-- Décision du cycliste, par jeton : une seule fois, depuis l'état 'envoye'
create or replace function public.devis_repondre(p_jeton text, p_decision text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_d public.devis;
begin
  if p_decision not in ('accepte', 'refuse') then return jsonb_build_object('ok', false, 'erreur', 'décision inconnue'); end if;
  if coalesce(p_jeton, '') !~ '^[0-9a-f]{64}$' then return jsonb_build_object('ok', false, 'erreur', 'lien invalide'); end if;
  select * into v_d from public.devis where jeton = p_jeton for update;
  if not found then return jsonb_build_object('ok', false, 'erreur', 'lien invalide'); end if;
  if v_d.statut in ('accepte', 'refuse') then
    return jsonb_build_object('ok', v_d.statut = p_decision, 'statut', v_d.statut, 'deja', true,
      'erreur', case when v_d.statut = p_decision then '' else 'devis déjà ' || case v_d.statut when 'accepte' then 'accepté' else 'refusé' end end);
  end if;
  if v_d.statut <> 'envoye' then return jsonb_build_object('ok', false, 'erreur', 'devis non envoyé'); end if;
  update public.devis set statut = p_decision, decide_le = now() where id = v_d.id;
  return jsonb_build_object('ok', true, 'statut', p_decision, 'deja', false, 'devis_id', v_d.id,
    'reference', v_d.reference, 'axonaut_devis_id', v_d.axonaut_devis_id,
    'axonaut_client_id', public.devis_client_axonaut(v_d.id));
end $$;

-- Report de la décision dans Axonaut, réponse de n8n (fonction serveur seulement, rôle service_role)
create or replace function public.devis_noter_decision(p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id uuid := (p->>'devis_id')::uuid;
begin
  if not exists (select 1 from public.devis where id = v_id) then return jsonb_build_object('ok', false, 'erreur', 'devis introuvable'); end if;
  if coalesce((p->>'ok')::boolean, false) then
    update public.devis set axonaut_decision_le = now(), derniere_erreur = null where id = v_id;
  else
    update public.devis set derniere_erreur = left(coalesce(nullif(p->>'erreur', ''), 'échec sans message'), 500) where id = v_id;
  end if;
  return jsonb_build_object('ok', true);
end $$;

-- 4. Droits des fonctions neuves (aucune n'est ouverte à anon sauf les deux fonctions à jeton)
revoke all on function public.devis_totaux(uuid), public.devis_lignes_json(uuid), public.devis_client_axonaut(uuid),
  public.devis_controles(uuid), public.devis_proposer(uuid), public.devis_preparer_envoi(uuid),
  public.devis_noter_envoi(jsonb), public.devis_public(text), public.devis_repondre(text, text),
  public.devis_noter_decision(jsonb) from public, anon, authenticated;
grant execute on function public.devis_controles(uuid), public.devis_proposer(uuid), public.devis_preparer_envoi(uuid)
  to authenticated;
grant execute on function public.devis_public(text), public.devis_repondre(text, text) to anon, authenticated;
grant execute on function public.devis_totaux(uuid), public.devis_lignes_json(uuid), public.devis_client_axonaut(uuid),
  public.devis_controles(uuid), public.devis_proposer(uuid), public.devis_preparer_envoi(uuid),
  public.devis_noter_envoi(jsonb), public.devis_public(text), public.devis_repondre(text, text),
  public.devis_noter_decision(jsonb) to service_role;
