// Liste « À commander », côté client (agent V4, 2026-10-14) : libellés et lecture prudente des réponses de la base.
import type { EtatStock } from "@/lib/stock";

/** État du devis d'où vient une pièce, en libellé. */
export const ETAT_DEVIS_PIECE: Record<string, string> = {
  brouillon: "brouillon, non envoyé",
  en_attente: "en attente",
  accepte: "accepté",
  refuse: "refusé",
};

/** État de stock venu de la base ; toute valeur inattendue vaut « inconnu ». */
export function lireEtatStock(v: unknown): EtatStock {
  return v === "en_stock" || v === "a_commander" ? v : "inconnu";
}

export type EtatLigneDevis = {
  retiree: boolean;
  doublon: "fiche" | "devis" | null;
  etatDevis: string;
};

/** Réponse de devis_pieces_etat -> état par ligne de devis ; une ligne absente n'est pas dans la liste. */
export function lireEtatsLignesDevis(v: unknown): Map<string, EtatLigneDevis> {
  const m = new Map<string, EtatLigneDevis>();
  if (!Array.isArray(v)) return m;
  for (const e of v) {
    if (!e || typeof e !== "object") continue;
    const o = e as {
      devis_ligne_id?: unknown;
      retiree?: unknown;
      doublon?: unknown;
      etat_devis?: unknown;
    };
    if (typeof o.devis_ligne_id !== "string") continue;
    m.set(o.devis_ligne_id, {
      retiree: o.retiree === true,
      doublon: o.doublon === "fiche" || o.doublon === "devis" ? o.doublon : null,
      etatDevis: typeof o.etat_devis === "string" ? o.etat_devis : "en_attente",
    });
  }
  return m;
}

/** Date d'un devis au format court (jj/mm/aaaa, heure de Paris) ; vide si illisible. */
export function dateDevis(v: unknown): string {
  if (typeof v !== "string" || !v) return "";
  const d = new Date(v);
  return Number.isNaN(d.getTime())
    ? ""
    : d.toLocaleDateString("fr-FR", { timeZone: "Europe/Paris" });
}
