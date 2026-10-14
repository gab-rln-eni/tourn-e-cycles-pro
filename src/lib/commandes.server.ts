// Lot L1 : rappel des pièces à commander, côté serveur uniquement (agent LOTS, 2026-10-14).
// Route lue par le workflow n8n TC_30 ; protégée par x-tc-secret comme les routes de liaison (D-22, D-28).
import { supabaseAdmin } from "@/integrations/supabase/client.server";
import { refuserSansSecret } from "@/lib/liaison.server";

const json = (corps: unknown, status = 200) =>
  new Response(JSON.stringify(corps), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
  });

/** Lit le mode essai dans un corps JSON facultatif ; tout autre contenu vaut le mode normal. */
export function lireEssai(texte: string): boolean {
  if (!texte.trim()) return false;
  try {
    const corps = JSON.parse(texte) as unknown;
    return !!corps && typeof corps === "object" && (corps as { essai?: unknown }).essai === true;
  } catch {
    return false;
  }
}

/** POST /api/public/rappel-commandes : { envoyer, essai, raison, jour, nb_pieces, pieces }. */
export async function traiterRappelCommandes(request: Request): Promise<Response> {
  const refus = refuserSansSecret(request, process.env["TC_SECRET"]);
  if (refus) return refus;
  const essai = lireEssai(await request.text().catch(() => ""));
  const { data, error } = await supabaseAdmin.rpc("rappel_commandes_reserver", { p_essai: essai });
  if (error) {
    console.error("[commandes] rappel_commandes_reserver", error.message);
    return json({ ok: false, erreur: "lecture impossible" }, 500);
  }
  return json(data ?? { envoyer: false, raison: "vide" });
}
