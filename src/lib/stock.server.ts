// Stock Axonaut, côté serveur uniquement (agent STOCK, 2026-10-14, dérogation de G_R ; brèche TC-91).
// Routes NEUVES appelées par n8n, protégées par x-tc-secret comme les routes de liaison (D-22, D-28) :
//   POST /api/public/demandes-a-traiter-v2 : comme demandes-a-traiter, avec l'identifiant du produit Axonaut par ligne d'envoi (TC_00 v3).
//     ATTENTION : réserve dans la même table que le chemin actuel ; à n'appeler qu'après la bascule (TC_00 v3 publié).
//   POST /api/public/catalogue-axonaut : correspondance pièce du catalogue -> produit Axonaut (TC_20 v3, TC_33).
//   POST /api/public/stock-axonaut : écriture du stock lu dans Axonaut, corps { stocks: [ { axonaut_produit_id, stock } ] } (TC_33).
// Les routes existantes (liaison.server.ts) ne changent pas.
import { supabaseAdmin } from "@/integrations/supabase/client.server";
import type { Json } from "@/integrations/supabase/types";
import { refuserSansSecret } from "@/lib/liaison.server";

const json = (corps: unknown, status = 200) =>
  new Response(JSON.stringify(corps), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
  });

export async function traiterDemandesATraiterV2(request: Request): Promise<Response> {
  const refus = refuserSansSecret(request, process.env["TC_SECRET"]);
  if (refus) return refus;
  const { data, error } = await supabaseAdmin.rpc("reserver_demandes_v2", { p_limite: 10 });
  if (error) {
    console.error("[stock] reserver_demandes_v2", error.message);
    return json({ ok: false, erreur: "réservation impossible" }, 500);
  }
  return json(Array.isArray(data) ? data : []);
}

export async function traiterCatalogueAxonaut(request: Request): Promise<Response> {
  const refus = refuserSansSecret(request, process.env["TC_SECRET"]);
  if (refus) return refus;
  const { data, error } = await supabaseAdmin.rpc("catalogue_axonaut_liste");
  if (error) {
    console.error("[stock] catalogue_axonaut_liste", error.message);
    return json({ ok: false, erreur: "lecture impossible" }, 500);
  }
  return json({ ok: true, produits: Array.isArray(data) ? data : [] });
}

/** Lit { stocks: [...] } ; toute autre forme est refusée avant la base. */
export function lireStocks(texte: string): Json[] | null {
  try {
    const c = JSON.parse(texte) as unknown;
    if (!c || typeof c !== "object" || Array.isArray(c)) return null;
    const s = (c as { stocks?: unknown }).stocks;
    return Array.isArray(s) ? (s as Json[]) : null;
  } catch {
    return null;
  }
}

export async function traiterStockAxonaut(request: Request): Promise<Response> {
  const refus = refuserSansSecret(request, process.env["TC_SECRET"]);
  if (refus) return refus;
  const stocks = lireStocks(await request.text().catch(() => ""));
  if (!stocks)
    return json(
      { ok: false, erreur: "objet attendu : { stocks: [ { axonaut_produit_id, stock } ] }" },
      400,
    );
  const { data, error } = await supabaseAdmin.rpc("stock_axonaut_ecrire", { p: { stocks } });
  if (error) {
    console.error("[stock] stock_axonaut_ecrire", error.message);
    return json({ ok: false, erreur: "écriture impossible" }, 500);
  }
  return json(data ?? { ok: false, erreur: "vide" });
}
