// Écran « À commander » : choix de la journée affichée (correctif L1, agent V4, 2026-10-14, visa G_R).
// Défaut corrigé : sans choix de l'utilisateur, la journée affichée était recalculée à chaque relecture de la liste
// (première journée qui a encore des pièces) ; cocher la dernière pièce d'une journée faisait donc passer l'écran
// sur une autre journée. Désormais la journée affichée, choisie ou par défaut, reste affichée jusqu'à un nouveau
// choix de l'utilisateur ou un rechargement de la page ; une journée vidée reste affichée (« tout est commandé »).

export type JourneeChoix = { evenement_id: string; nb_a_commander: number };

/**
 * Journée à afficher.
 * @param liste journées de l'écran, dans l'ordre de la base
 * @param affichee journée déjà affichée (choix de l'utilisateur, ou journée retenue par défaut au premier affichage)
 * @returns la journée déjà affichée si elle est toujours dans la liste ; sinon la première journée qui a des pièces
 *          à commander, à défaut la première de la liste ; null si la liste est vide.
 */
export function journeeAffichee(
  liste: readonly JourneeChoix[],
  affichee: string | null,
): string | null {
  if (affichee && liste.some((j) => j.evenement_id === affichee)) return affichee;
  const parDefaut = liste.find((j) => j.nb_a_commander > 0) ?? liste[0];
  return parDefaut?.evenement_id ?? null;
}
