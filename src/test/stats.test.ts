import { describe, expect, it } from "vitest";
import { calculer, filtrer, type LigneStat } from "@/lib/stats";

// Lot L2 : statistiques par entreprise (filtre par site et période, cumuls).
const L = (x: Partial<LigneStat>): LigneStat => ({
  entreprise_id: "e1",
  entreprise: "Ent",
  site: "A",
  date_intervention: "2026-10-13",
  genre: "velo",
  libelle: "Musculaire",
  quantite: 1,
  ...x,
});
const lignes = [
  L({}),
  L({ site: "B", date_intervention: "2026-10-20", libelle: "Électrique (VAE)" }),
  L({ genre: "organe", libelle: "Frein avant" }),
  L({ genre: "organe", libelle: "Frein avant", site: "B", date_intervention: "2026-10-20" }),
  L({ genre: "organe", libelle: "Cadre" }),
  L({ genre: "piece", libelle: "Câble", quantite: 0.5 }),
  L({ genre: "piece", libelle: "Câble", quantite: 1 }),
  L({ entreprise_id: "e2", entreprise: "Autre" }),
];

describe("statistiques par entreprise", () => {
  it("nominal : cumuls de l'entreprise, organes triés par fréquence", () => {
    const r = calculer(filtrer(lignes, { entreprise: "e1", site: null, du: "", au: "" }));
    expect(r.velos).toBe(2);
    expect(r.journees).toBe(2);
    expect(r.organes[0]).toEqual({ libelle: "Frein avant", total: 2 });
    expect(r.pieces).toEqual([{ libelle: "Câble", total: 1.5 }]);
  });
  it("filtre par site et par période (bornes incluses)", () => {
    expect(calculer(filtrer(lignes, { entreprise: "e1", site: "B", du: "", au: "" })).velos).toBe(
      1,
    );
    const p = calculer(
      filtrer(lignes, { entreprise: "e1", site: null, du: "2026-10-13", au: "2026-10-13" }),
    );
    expect(p.velos).toBe(1);
    expect(p.organes.map((o) => o.libelle)).toEqual(["Cadre", "Frein avant"]);
  });
  it("vide : aucune ligne, aucun cumul", () => {
    const r = calculer(filtrer([], { entreprise: "e1", site: null, du: "", au: "" }));
    expect(r).toEqual({ velos: 0, journees: 0, parType: [], organes: [], pieces: [] });
  });
  it("erreur de saisie : période inversée, aucune ligne", () => {
    expect(
      filtrer(lignes, { entreprise: "e1", site: null, du: "2026-10-30", au: "2026-10-01" }),
    ).toEqual([]);
  });
});
