-- Liaison avec n8n (Lovable/CONCEPTION_P1.md, section 2 ; D-22, D-28, D-50 ; L-1, L-2).
-- Les deux routes de l'application appellent ces fonctions avec la clé de service ; aucun autre rôle ne peut les exécuter.
-- reserver_demandes : réserve atomiquement les demandes « a_faire » (passage à « en_cours », tentatives + 1) et fournit les données
--   selon le type ; une demande « en_cours » depuis plus de 15 min redevient « a_faire » (ou « echec » si elle a déjà eu 3 tentatives).
-- ecrire_resultat : écrit le résultat d'une demande ; le résultat est écrit même quand ok est faux (A2-11) ;
--   la demande passe à « fait », revient à « a_faire », ou passe à « echec » à 3 tentatives.
-- Retour arrière : voir le bloc commenté en fin de fichier.

alter table public.demandes_automatisation add column if not exists pris_le timestamptz;

create or replace function public.donnees_demande(p_type text, p_objet uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v jsonb;
begin
  if p_type = 'client' then
    select jsonb_build_object(
      'inscription', jsonb_build_object('prenom', i.prenom, 'nom', i.nom, 'email', i.email, 'telephone', i.telephone,
                                        'code_postal', i.code_postal, 'axonaut_client_id', coalesce(i.axonaut_client_id, '')),
      'entreprise', jsonb_build_object('nom', e.nom))
    into v
    from public.inscriptions i
    join public.evenements ev on ev.id = i.evenement_id
    join public.entreprises e on e.id = ev.entreprise_id
    where i.id = p_objet;

  elsif p_type = 'commande' then
    select jsonb_build_object(
      'journee', jsonb_build_object('entreprise', e.nom, 'site', ev.site, 'adresse', ev.adresse, 'date_intervention', ev.date_intervention),
      'pieces', coalesce((
        select jsonb_agg(jsonb_build_object('libelle', x.libelle, 'reference', x.reference, 'quantite', x.quantite) order by x.libelle)
        from (
          select pp.libelle, pc.reference, sum(pp.quantite) as quantite
          from public.pieces_posees pp
          join public.fiches f on f.id = pp.fiche_id
          join public.inscriptions i on i.id = f.inscription_id
          left join public.pieces_catalogue pc on pc.id = pp.piece_id
          where i.evenement_id = ev.id and pp.a_commander
          group by pp.libelle, pc.reference
        ) x), '[]'::jsonb))
    into v
    from public.evenements ev
    join public.entreprises e on e.id = ev.entreprise_id
    where ev.id = p_objet;

  elsif p_type = 'controle' then
    -- Aucune donnée personnelle : ni nom, ni email, ni téléphone.
    select jsonb_build_object(
      'lignes', coalesce((
        select jsonb_agg(jsonb_build_object('libelle', l.libelle, 'quantite', l.quantite, 'prix_unitaire_ht', l.prix_unitaire_ht,
                                            'taux_tva', l.taux_tva) order by l.ordre)
        from public.facture_lignes l where l.facture_id = fa.id), '[]'::jsonb),
      'points', coalesce((
        select jsonb_agg(jsonb_build_object('groupe', fp.groupe, 'point', fp.point, 'etat', fp.etat, 'constats', fp.constats,
                                            'remarque', fp.remarque) order by fp.groupe, fp.point)
        from public.fiche_points fp
        where fp.fiche_id = fi.id and (fp.etat <> 'bon' or cardinality(fp.constats) > 0 or fp.remarque is not null)), '[]'::jsonb),
      'partie_signalee', i.partie_signalee,
      'probleme_percu', i.probleme_percu,
      'commentaire', fi.commentaire)
    into v
    from public.factures fa
    join public.inscriptions i on i.id = fa.inscription_id
    left join public.fiches fi on fi.inscription_id = i.id
    where fa.id = p_objet;

  elsif p_type = 'envoi' then
    select jsonb_build_object(
      'reference_fiche', fi.reference,
      'axonaut_client_id', coalesce(i.axonaut_client_id, ''),
      'lignes', coalesce((
        select jsonb_agg(jsonb_build_object('libelle', l.libelle, 'quantite', l.quantite, 'prix_unitaire_ht', l.prix_unitaire_ht,
                                            'taux_tva', l.taux_tva) order by l.ordre)
        from public.facture_lignes l where l.facture_id = fa.id), '[]'::jsonb),
      'total_ht', t.ht,
      'total_tva', t.tva,
      'total_ttc', t.ht + t.tva,
      'recapitulatif', jsonb_build_object('client', i.prenom || ' ' || i.nom, 'entreprise', e.nom, 'site', ev.site,
                                          'date_intervention', ev.date_intervention, 'reference_fiche', fi.reference,
                                          'velo', case i.type_velo when 'vae' then 'Électrique (VAE)' else 'Musculaire' end
                                                  || coalesce(', ' || nullif(btrim(i.velo_modele), ''), '')))
    into v
    from public.factures fa
    join public.inscriptions i on i.id = fa.inscription_id
    join public.evenements ev on ev.id = i.evenement_id
    join public.entreprises e on e.id = ev.entreprise_id
    left join public.fiches fi on fi.inscription_id = i.id
    cross join lateral (
      select round(coalesce(sum(l.quantite * l.prix_unitaire_ht), 0), 2) as ht,
             round(coalesce(sum(l.quantite * l.prix_unitaire_ht * l.taux_tva / 100), 0), 2) as tva
      from public.facture_lignes l where l.facture_id = fa.id
    ) t
    where fa.id = p_objet and fa.statut = 'validee';
  end if;
  return v;
end $$;

create or replace function public.reserver_demandes(p_limite integer default 10)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_res jsonb := '[]'::jsonb; r record;
begin
  -- Demandes restées « en_cours » plus de 15 minutes : reprises, ou abandonnées après 3 tentatives.
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
      'demande_id', r.id, 'type', r.type, 'donnees', public.donnees_demande(r.type, r.objet_id)));
  end loop;
  return v_res;
end $$;

create or replace function public.ecrire_resultat(p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_d public.demandes_automatisation;
  v_ok boolean := coalesce(p->>'ok', '') = 'true';
  v_res jsonb := case when jsonb_typeof(p->'resultat') = 'object' then p->'resultat' else '{}'::jsonb end;
  v_err text := nullif(left(btrim(coalesce(p->>'erreur', '')), 500), '');
  v_envoyee timestamptz;
  v_statut text;
begin
  if coalesce(p->>'demande_id', '') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return jsonb_build_object('ok', false, 'erreur', 'demande_id invalide');
  end if;
  select * into v_d from public.demandes_automatisation where id = (p->>'demande_id')::uuid for update;
  if not found then return jsonb_build_object('ok', false, 'erreur', 'demande inconnue'); end if;
  if v_d.statut <> 'en_cours' then
    return jsonb_build_object('ok', false, 'erreur', 'demande non en cours (' || v_d.statut || ')');
  end if;

  -- Résultat écrit même quand ok est faux (A2-11).
  if v_d.type = 'client' and nullif(btrim(coalesce(v_res->>'axonaut_client_id', '')), '') is not null then
    update public.inscriptions set axonaut_client_id = left(btrim(v_res->>'axonaut_client_id'), 50) where id = v_d.objet_id;
  end if;
  if v_d.type = 'envoi' and nullif(btrim(coalesce(v_res->>'axonaut_facture_id', '')), '') is not null then
    update public.factures set axonaut_facture_id = left(btrim(v_res->>'axonaut_facture_id'), 50) where id = v_d.objet_id;
  end if;
  if v_d.type = 'controle' and jsonb_typeof(v_res->'avis') = 'array' then
    delete from public.avis_controle where facture_id = v_d.objet_id and source = 'ia';
    insert into public.avis_controle(facture_id, source, niveau, message)
      select v_d.objet_id, 'ia',
             case when a->>'niveau' in ('ok', 'attention', 'erreur') then a->>'niveau' else 'attention' end,
             left(coalesce(nullif(btrim(a->>'message'), ''), 'Avis IA sans texte.'), 1000)
      from jsonb_array_elements(v_res->'avis') a
      where jsonb_typeof(a) = 'object';
  end if;

  if v_ok then
    update public.demandes_automatisation set statut = 'fait', termine_le = now(), derniere_erreur = null where id = v_d.id;
    v_statut := 'fait';
    if v_d.type = 'envoi' then
      v_envoyee := case when coalesce(v_res->>'envoyee_le', '') ~ '^\d{4}-\d{2}-\d{2}' then (v_res->>'envoyee_le')::timestamptz else now() end;
      update public.factures set statut = 'envoyee', envoyee_le = v_envoyee where id = v_d.objet_id;
    end if;
  elsif v_d.tentatives >= 3 then
    update public.demandes_automatisation set statut = 'echec', termine_le = now(), derniere_erreur = v_err where id = v_d.id;
    v_statut := 'echec';
    if v_d.type = 'envoi' then
      update public.factures set statut = 'echec', detail = coalesce(v_err, 'Échec de l''envoi.') where id = v_d.objet_id;
    end if;
  else
    update public.demandes_automatisation set statut = 'a_faire', derniere_erreur = v_err where id = v_d.id;
    v_statut := 'a_faire';
  end if;
  return jsonb_build_object('ok', true, 'statut', v_statut);
end $$;

revoke execute on function public.donnees_demande(text, uuid) from public, anon, authenticated;
revoke execute on function public.reserver_demandes(integer) from public, anon, authenticated;
revoke execute on function public.ecrire_resultat(jsonb) from public, anon, authenticated;
grant execute on function public.donnees_demande(text, uuid) to service_role;
grant execute on function public.reserver_demandes(integer) to service_role;
grant execute on function public.ecrire_resultat(jsonb) to service_role;

-- Retour arrière (à exécuter seulement sur visa) :
-- drop function if exists public.ecrire_resultat(jsonb);
-- drop function if exists public.reserver_demandes(integer);
-- drop function if exists public.donnees_demande(text, uuid);
-- alter table public.demandes_automatisation drop column if exists pris_le;
