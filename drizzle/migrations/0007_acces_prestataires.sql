-- 0007_acces_prestataires.sql : lot L3, écran des accès des prestataires (agent LOTS, 2026-10-14, visa G_R de l'après-midi).
-- Fonctions NEUVES seulement, SECURITY DEFINER, réservées au dirigeant. Aucun déclencheur, aucune colonne, aucun rôle neuf ;
-- la table acces et ses règles d'accès ne sont pas modifiées.
-- Règles : rôles donnés : mecanicien ou atelier seulement, jamais dirigeant ; date d'expiration obligatoire et future ;
-- retirer = revoque_le à now(), jamais de DELETE ; redonner = réactiver la ligne existante (UNIQUE (email, role)), jamais un second INSERT ;
-- interdits : retirer ou raccourcir un accès dirigeant, et les deux accès des correcteurs jusqu'au 26/10 inclus (comparaison en lower(email)).
-- Idempotent. Écart connu : non inscrit dans drizzle/migrations/meta/_journal.json (application par SQL direct).

-- Accès protégé : tout accès dirigeant ; les deux accès des correcteurs jusqu'au 26/10 inclus, heure de Paris
create or replace function public.acces_protege(p_email text, p_role public.app_role)
returns boolean language sql stable security definer set search_path = public as $$
  select p_role = 'dirigeant'
      or (lower(btrim(coalesce(p_email, ''))) in ('gabriel.roulon+correcteur@gmail.com', 'gabriel.roulon+correcteur.meca@gmail.com')
          and (now() at time zone 'Europe/Paris')::date <= date '2026-10-26')
$$;

-- Liste des accès (dirigeant)
create or replace function public.acces_liste()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.has_role(auth.uid(), 'dirigeant') then raise exception 'Accès refusé.'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', a.id, 'email', a.email, 'role', a.role, 'expire_le', a.expire_le,
             'revoque_le', a.revoque_le, 'created_at', a.created_at,
             'etat', case when a.revoque_le is not null then 'retire'
                          when a.expire_le is not null and a.expire_le <= now() then 'expire' else 'actif' end,
             'protege', public.acces_protege(a.email, a.role))
             order by (a.role = 'dirigeant') desc, a.email, a.role)
    from public.acces a), '[]'::jsonb);
end $$;

-- Donner un accès, ou redonner un accès retiré ou expiré (même ligne), ou changer sa date d'expiration
create or replace function public.acces_donner(p_email text, p_role public.app_role, p_expire_le timestamptz)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_email text := lower(btrim(coalesce(p_email, '')));
  v_a public.acces;
begin
  if not public.has_role(auth.uid(), 'dirigeant') then raise exception 'Accès refusé.'; end if;
  if p_role is null or p_role not in ('mecanicien', 'atelier') then raise exception 'Rôle possible : mécanicien ou atelier.'; end if;
  if char_length(v_email) > 255 or v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'L''adresse email n''est pas valide.'; end if;
  if p_expire_le is null or p_expire_le <= now() then raise exception 'Indiquez une date d''expiration à venir.'; end if;
  if p_expire_le > now() + interval '1 year' then raise exception 'Expiration : un an au plus.'; end if;
  select * into v_a from public.acces where email = v_email and role = p_role for update;
  if not found then
    insert into public.acces(email, role, expire_le, cree_par) values (v_email, p_role, p_expire_le, auth.uid())
      returning * into v_a;
    return jsonb_build_object('ok', true, 'action', 'donne', 'id', v_a.id);
  end if;
  if public.acces_protege(v_a.email, v_a.role)
     and (v_a.revoque_le is not null or v_a.expire_le is null or p_expire_le < v_a.expire_le) then
    raise exception 'Cet accès est protégé : il ne peut être ni retiré ni raccourci.';
  end if;
  update public.acces set revoque_le = null, expire_le = p_expire_le where id = v_a.id;
  return jsonb_build_object('ok', true, 'action', case when v_a.revoque_le is not null then 'redonne' else 'modifie' end, 'id', v_a.id);
end $$;

-- Retirer un accès : revoque_le = now(), jamais de suppression
create or replace function public.acces_retirer(p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_a public.acces;
begin
  if not public.has_role(auth.uid(), 'dirigeant') then raise exception 'Accès refusé.'; end if;
  select * into v_a from public.acces where id = p_id for update;
  if not found then raise exception 'Accès introuvable.'; end if;
  if public.acces_protege(v_a.email, v_a.role) then raise exception 'Cet accès est protégé : il ne peut être ni retiré ni raccourci.'; end if;
  if v_a.revoque_le is not null then return jsonb_build_object('ok', true, 'action', 'deja_retire', 'id', v_a.id); end if;
  update public.acces set revoque_le = now() where id = v_a.id;
  return jsonb_build_object('ok', true, 'action', 'retire', 'id', v_a.id);
end $$;

-- Droits d'exécution explicites (la base réelle accorde par défaut tout à anon sur un objet neuf)
revoke execute on function public.acces_protege(text, public.app_role) from public, anon, authenticated;
revoke execute on function public.acces_liste() from public, anon, authenticated;
revoke execute on function public.acces_donner(text, public.app_role, timestamptz) from public, anon, authenticated;
revoke execute on function public.acces_retirer(uuid) from public, anon, authenticated;
grant execute on function public.acces_liste() to authenticated;
grant execute on function public.acces_donner(text, public.app_role, timestamptz) to authenticated;
grant execute on function public.acces_retirer(uuid) to authenticated;

-- Retour arrière (seulement sur visa, sans suppression) : revoke execute des trois fonctions pour authenticated.
