// Stock d'une pièce au moment du devis (agent STOCK, 2026-10-14) : lu par la fonction stock_pieces (table stock_axonaut,
// alimentée par le workflow TC_33 depuis Axonaut). Toute réponse illisible ou absente vaut « inconnu », jamais une erreur bloquante.
export type EtatStock = "en_stock" | "a_commander" | "inconnu";

/** Réponse de stock_pieces -> état par identifiant de pièce. */
export function lireStockPieces(v: unknown): Map<string, EtatStock> {
  const m = new Map<string, EtatStock>();
  if (!Array.isArray(v)) return m;
  for (const e of v) {
    if (!e || typeof e !== "object") continue;
    const id = (e as { piece_id?: unknown }).piece_id;
    const etat = (e as { etat?: unknown }).etat;
    if (typeof id !== "string") continue;
    m.set(id, etat === "en_stock" || etat === "a_commander" ? etat : "inconnu");
  }
  return m;
}

/** État d'une pièce : inconnu si la pièce n'est pas dans la réponse. */
export const etatPiece = (m: Map<string, EtatStock>, pieceId: string): EtatStock =>
  m.get(pieceId) ?? "inconnu";

export const libelleStock: Record<EtatStock, string> = {
  en_stock: "En stock",
  a_commander: "À commander",
  inconnu: "Stock inconnu",
};
