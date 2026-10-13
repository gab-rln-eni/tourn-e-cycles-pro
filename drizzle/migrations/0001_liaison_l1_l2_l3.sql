-- Décisions L-1, L-2 et L-3 (visa G_R du 2026-10-13).
-- L-3 : terminer_fiche ne crée plus de demande 'brouillon' (le brouillon de facture est tenu dans l'application).
-- L-2 : référence unique et stable de la fiche, calculée par la base : « TC- » suivi des 8 premiers caractères de son identifiant.
-- L-1 : « Prête à valider » passe par preparer_facture, qui crée la demande 'controle' (avis IA consultatif).
-- Retour arrière : voir le bloc commenté en fin de fichier.

alter table public.fiches
  add column if not exists reference text
  generated always as ('TC-' || upper(substr(id::text, 1, 8))) stored;

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
  end if;
  if exists (select 1 from public.pieces_posees where fiche_id = p_fiche and a_commander) then
    select evenement_id into v_ev from public.inscriptions where id = v_f.inscription_id;
    insert into public.demandes_automatisation(type, objet_id) values ('commande', v_ev);
  end if;
  return v_fac;
end $$;

create or replace function public.preparer_facture(p_facture uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_statut text;
begin
  if not public.has_any_role(array['dirigeant','atelier']::public.app_role[]) then raise exception 'Accès refusé.'; end if;
  select statut into v_statut from public.factures where id = p_facture for update;
  if not found then raise exception 'Facture introuvable.'; end if;
  if v_statut not in ('a_preparer','brouillon','echec') then
    raise exception 'La facture ne peut plus être préparée.'; end if;
  if not exists (select 1 from public.facture_lignes where facture_id = p_facture) then
    raise exception 'La facture ne contient aucune ligne.'; end if;
  update public.factures set statut = 'a_valider', prete_par = auth.uid(), prete_le = now() where id = p_facture;
  delete from public.avis_controle where facture_id = p_facture and source = 'ia';
  insert into public.demandes_automatisation(type, objet_id) values ('controle', p_facture);
end $$;

revoke execute on function public.preparer_facture(uuid) from public;
grant execute on function public.preparer_facture(uuid) to authenticated;

-- Retour arrière (à exécuter seulement sur visa) :
-- drop function if exists public.preparer_facture(uuid);
-- alter table public.fiches drop column if exists reference;
-- puis rejouer la définition de terminer_fiche de 0000_tournee_cycles_schema.sql (avec la demande 'brouillon').
