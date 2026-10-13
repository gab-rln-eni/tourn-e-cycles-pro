-- 0004_devis_correctifs.sql : correctifs du parcours devis après relecture indépendante (agent DEVIS, nuit du 2026-10-14).
-- Ne touche que des objets créés par 0003 ; aucun objet antérieur à la nuit n'est modifié.
-- Lecture prudente : aucune fonction déjà créée n'est remplacée (pas de CREATE OR REPLACE sur un nom existant) ;
-- les fonctions corrigées portent un nom neuf, créées seulement si elles manquent, et les anciennes perdent leurs droits d'exécution.
-- Idempotent. Écart connu : non inscrit dans drizzle/migrations/meta/_journal.json (application par SQL direct).

-- 1. Colonne neuve sur la table neuve devis : heure de la dernière demande d'envoi (protection contre le double envoi)
alter table public.devis add column if not exists envoi_demande_le timestamptz;

-- 2. Droits par colonne : l'app n'écrit directement que la fiche, la référence, le client Axonaut et le commentaire ;
--    statut, jeton, relecture et identifiants Axonaut ne s'écrivent que par les fonctions
revoke insert, update on public.devis from authenticated;
grant insert (fiche_id, reference, axonaut_client_id, commentaire) on public.devis to authenticated;
grant update (axonaut_client_id, commentaire) on public.devis to authenticated;

-- 3. Lignes figées dès que la relecture a posé le jeton
alter policy dl_write on public.devis_lignes
  using (public.has_any_role(array['dirigeant','mecanicien','atelier']::public.app_role[])
         and exists (select 1 from public.devis d where d.id = devis_id and d.statut in ('brouillon','a_relire') and d.jeton is null))
  with check (public.has_any_role(array['dirigeant','mecanicien','atelier']::public.app_role[])
         and exists (select 1 from public.devis d where d.id = devis_id and d.statut in ('brouillon','a_relire') and d.jeton is null));

-- 4. Relecture, version 2 : un seul envoi à la fois (2 minutes de garde), heure de la demande notée
do $do$ begin
  if to_regprocedure('public.devis_preparer_envoi2(uuid)') is null then
    execute $f$
create function public.devis_preparer_envoi2(p_devis uuid)
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
  if v_d.envoi_demande_le is not null and v_d.envoi_demande_le > now() - interval '2 minutes' then
    return jsonb_build_object('ok', false, 'avis', jsonb_build_array(jsonb_build_object('niveau', 'erreur',
      'message', 'Envoi déjà en cours. Patientez deux minutes avant de réessayer.')));
  end if;
  v_avis := public.devis_controles(p_devis);
  if exists (select 1 from jsonb_array_elements(v_avis) a where a->>'niveau' = 'erreur') then
    return jsonb_build_object('ok', false, 'avis', v_avis);
  end if;
  update public.devis
     set relu_par = auth.uid(), relu_le = now(), derniere_erreur = null, envoi_demande_le = now(),
         jeton = coalesce(jeton, replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', ''))
   where id = p_devis returning * into v_d;
  v_t := public.devis_totaux(p_devis);
  return jsonb_build_object('ok', true, 'avis', v_avis, 'jeton', v_d.jeton, 'donnees', jsonb_build_object(
    'devis_id', v_d.id, 'reference', v_d.reference, 'axonaut_client_id', public.devis_client_axonaut(p_devis),
    'commentaire', coalesce(v_d.commentaire, ''), 'lignes', public.devis_lignes_json(p_devis),
    'total_ht', v_t->'total_ht', 'total_tva', v_t->'total_tva', 'total_ttc', v_t->'total_ttc'));
end $$
    $f$;
  end if;

  -- 5. Reprendre en brouillon un devis dont l'envoi a échoué (jeton retiré, lignes de nouveau modifiables)
  if to_regprocedure('public.devis_reprendre(uuid)') is null then
    execute $f$
create function public.devis_reprendre(p_devis uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_d public.devis;
begin
  if not public.has_any_role(array['dirigeant','atelier']::public.app_role[]) then raise exception 'Accès refusé.'; end if;
  select * into v_d from public.devis where id = p_devis for update;
  if not found then raise exception 'Devis introuvable.'; end if;
  if v_d.statut <> 'a_relire' or v_d.axonaut_devis_id is not null then raise exception 'Seul un devis non envoyé peut être repris.'; end if;
  if v_d.envoi_demande_le is not null and v_d.envoi_demande_le > now() - interval '2 minutes' then
    raise exception 'Envoi en cours : patientez deux minutes.';
  end if;
  update public.devis set statut = 'brouillon', jeton = null, envoi_demande_le = null, relu_par = null, relu_le = null
   where id = p_devis;
end $$
    $f$;
  end if;

  -- 6. Décision du cycliste, version 2 : ne renvoie à l'appelant anonyme que ok, statut, deja et erreur
  if to_regprocedure('public.devis_repondre2(text,text)') is null then
    execute $f$
create function public.devis_repondre2(p_jeton text, p_decision text)
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
  return jsonb_build_object('ok', true, 'statut', p_decision, 'deja', false, 'erreur', '');
end $$
    $f$;
  end if;
end $do$;

-- 7. Droits : versions 2 ouvertes, versions 1 fermées (sauf service_role)
revoke all on function public.devis_preparer_envoi2(uuid), public.devis_reprendre(uuid), public.devis_repondre2(text, text)
  from public, anon, authenticated;
grant execute on function public.devis_preparer_envoi2(uuid), public.devis_reprendre(uuid) to authenticated;
grant execute on function public.devis_repondre2(text, text) to anon, authenticated;
grant execute on function public.devis_preparer_envoi2(uuid), public.devis_reprendre(uuid), public.devis_repondre2(text, text) to service_role;
revoke execute on function public.devis_preparer_envoi(uuid) from authenticated;
revoke execute on function public.devis_repondre(text, text) from anon, authenticated;
