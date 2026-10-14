import { describe, expect, it } from "vitest";
import { journeeAffichee } from "@/lib/commandes-journee";

// Correctif L1 (agent V4, 2026-10-14) : la journée affichée de l'écran « À commander » ne change plus seule.
const J16 = "e81ea25a-ee49-4b60-8836-b0fc80018192";
const J13 = "2b83b5ef-041a-4c17-971f-8eece4fd4fdd";

describe("écran À commander : journée affichée", () => {
  it("défaut reproduit : la dernière pièce du 16/10 cochée, l'écran reste sur le 16/10", () => {
    // Premier affichage : rien de choisi, le 16/10 est la première journée qui a des pièces.
    const avant = [
      { evenement_id: J16, nb_a_commander: 1 },
      { evenement_id: J13, nb_a_commander: 1 },
    ];
    const premiere = journeeAffichee(avant, null);
    expect(premiere).toBe(J16);
    // Relecture après la coche : le 16/10 n'a plus rien à commander. Avant le correctif, l'écran passait au 13/10.
    const apres = [
      { evenement_id: J16, nb_a_commander: 0 },
      { evenement_id: J13, nb_a_commander: 1 },
    ];
    expect(journeeAffichee(apres, premiere)).toBe(J16);
  });

  it("nominal : le choix de l'utilisateur est gardé, même sur une journée sans pièce", () => {
    const liste = [
      { evenement_id: J16, nb_a_commander: 1 },
      { evenement_id: J13, nb_a_commander: 0 },
    ];
    expect(journeeAffichee(liste, J13)).toBe(J13);
  });

  it("vide : liste vide, aucune journée ; rien d'affiché, journée par défaut", () => {
    expect(journeeAffichee([], null)).toBeNull();
    expect(journeeAffichee([], J16)).toBeNull();
    expect(
      journeeAffichee(
        [
          { evenement_id: J16, nb_a_commander: 0 },
          { evenement_id: J13, nb_a_commander: 0 },
        ],
        null,
      ),
    ).toBe(J16);
  });

  it("erreur : journée affichée absente de la liste relue, retour au choix par défaut", () => {
    const liste = [
      { evenement_id: J16, nb_a_commander: 0 },
      { evenement_id: J13, nb_a_commander: 2 },
    ];
    expect(journeeAffichee(liste, "inconnue")).toBe(J13);
    expect(journeeAffichee(liste, "")).toBe(J13);
  });
});
