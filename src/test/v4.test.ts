import { describe, expect, it } from "vitest";
import { lireDemandeId } from "@/lib/v4.server";
import { ETAT_DEVIS_PIECE, lireEtatStock, lireEtatsLignesDevis } from "@/lib/commandes";

// Chantier V4 (agent V4, 2026-10-14) : corps de la route facture-resume-v4, état des lignes de devis dans la liste « À commander ».
const ID = "a2000000-0000-0000-0000-000000000001";

describe("route facture-resume-v4 : lecture du corps", () => {
  it("nominal : identifiant de demande valide", () => {
    expect(lireDemandeId(JSON.stringify({ demande_id: ID }))).toBe(ID);
  });
  it("vide : corps absent, objet vide ou tableau", () => {
    expect(lireDemandeId("")).toBeNull();
    expect(lireDemandeId("{}")).toBeNull();
    expect(lireDemandeId("[]")).toBeNull();
  });
  it("erreur : JSON illisible, identifiant non conforme", () => {
    expect(lireDemandeId("{demande")).toBeNull();
    expect(lireDemandeId(JSON.stringify({ demande_id: "1; drop table" }))).toBeNull();
    expect(lireDemandeId(JSON.stringify({ demande_id: 42 }))).toBeNull();
  });
});

describe("liste À commander : lignes de devis", () => {
  it("nominal : état, retrait et doublon lus", () => {
    const m = lireEtatsLignesDevis([
      { devis_ligne_id: "l1", retiree: true, doublon: null, etat_devis: "accepte" },
      { devis_ligne_id: "l2", retiree: false, doublon: "fiche", etat_devis: "en_attente" },
    ]);
    expect(m.get("l1")).toEqual({ retiree: true, doublon: null, etatDevis: "accepte" });
    expect(m.get("l2")?.doublon).toBe("fiche");
    expect(ETAT_DEVIS_PIECE["refuse"]).toBe("refusé");
  });
  it("vide : réponse absente ou vide", () => {
    expect(lireEtatsLignesDevis(null).size).toBe(0);
    expect(lireEtatsLignesDevis([]).size).toBe(0);
  });
  it("erreur : éléments mal formés ignorés, valeurs inattendues prudentes", () => {
    const m = lireEtatsLignesDevis([
      null,
      3,
      { retiree: true },
      { devis_ligne_id: "l3", doublon: "autre", retiree: "oui" },
    ]);
    expect(m.size).toBe(1);
    expect(m.get("l3")).toEqual({ retiree: false, doublon: null, etatDevis: "en_attente" });
    expect(lireEtatStock("en_stock")).toBe("en_stock");
    expect(lireEtatStock(null)).toBe("inconnu");
    expect(lireEtatStock("bizarre")).toBe("inconnu");
  });
});
