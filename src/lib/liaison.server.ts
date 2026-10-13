// Liaison avec n8n, côté serveur uniquement (Lovable/CONCEPTION_P1.md, section 2 ; D-22, D-28).
// Secret unique TC_SECRET dans les deux sens, en-tête x-tc-secret ; adresse de n8n : N8N_BASE_URL.
// Les valeurs sont saisies dans les secrets du projet (L-4) ; elles ne sont jamais écrites dans le code.
import { supabaseAdmin } from "@/integrations/supabase/client.server";
import type { Json } from "@/integrations/supabase/types";

const json = (corps: unknown, status = 200) =>
  new Response(JSON.stringify(corps), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
  });

/** Comparaison à durée constante (indépendante du point de divergence). */
export function egaliteConstante(a: string, b: string): boolean {
  const ea = new TextEncoder().encode(a);
  const eb = new TextEncoder().encode(b);
  let diff = ea.length ^ eb.length;
  const n = Math.max(ea.length, eb.length);
  for (let i = 0; i < n; i++) diff |= (ea[i] ?? 0) ^ (eb[i] ?? 0);
  return diff === 0;
}

/** Contrôle du secret d'en-tête ; renvoie une réponse d'erreur, ou null si la requête est autorisée. */
export function refuserSansSecret(request: Request, secret: string | undefined): Response | null {
  if (!secret) return json({ ok: false, erreur: "TC_SECRET non configuré" }, 503);
  const recu = request.headers.get("x-tc-secret") ?? "";
  if (!egaliteConstante(recu, secret)) return json({ ok: false, erreur: "secret invalide" }, 401);
  return null;
}

/** POST /api/public/demandes-a-traiter : réserve les demandes « a_faire » et renvoie [{ demande_id, type, donnees }]. */
export async function traiterDemandesATraiter(request: Request): Promise<Response> {
  const refus = refuserSansSecret(request, process.env["TC_SECRET"]);
  if (refus) return refus;
  const { data, error } = await supabaseAdmin.rpc("reserver_demandes", { p_limite: 10 });
  if (error) {
    console.error("[liaison] reserver_demandes", error.message);
    return json({ ok: false, erreur: "réservation impossible" }, 500);
  }
  return json(Array.isArray(data) ? data : []);
}

/** POST /api/public/demande-resultat : écrit { demande_id, ok, erreur, resultat } et renvoie { ok }. */
export async function traiterDemandeResultat(request: Request): Promise<Response> {
  const refus = refuserSansSecret(request, process.env["TC_SECRET"]);
  if (refus) return refus;
  let corps: unknown;
  try {
    corps = await request.json();
  } catch {
    return json({ ok: false, erreur: "corps JSON invalide" }, 400);
  }
  if (!corps || typeof corps !== "object" || Array.isArray(corps)) {
    return json({ ok: false, erreur: "objet attendu : { demande_id, ok, erreur, resultat }" }, 400);
  }
  const { data, error } = await supabaseAdmin.rpc("ecrire_resultat", { p: corps as Json });
  if (error) {
    console.error("[liaison] ecrire_resultat", error.message);
    return json({ ok: false, erreur: "écriture impossible" }, 500);
  }
  const r = (data ?? {}) as { ok?: boolean; erreur?: string; statut?: string };
  return json(r, r.ok ? 200 : 409);
}

/** Appel du webhook unique de n8n (P1-5 B) ; un échec est sans conséquence : le rattrapage de n8n reprend la demande. */
export async function appelerWebhook(): Promise<{ ok: boolean; raison?: string }> {
  const base = process.env["N8N_BASE_URL"];
  const secret = process.env["TC_SECRET"];
  if (!base || !secret) return { ok: false, raison: "non configuré" };
  try {
    const r = await fetch(`${base.replace(/\/+$/, "")}/webhook/tc-traiter`, {
      method: "POST",
      headers: { "ngrok-skip-browser-warning": "1", "x-tc-secret": secret },
      signal: AbortSignal.timeout(8000),
    });
    return r.ok ? { ok: true } : { ok: false, raison: `HTTP ${r.status}` };
  } catch (e) {
    return { ok: false, raison: e instanceof Error ? e.name : "erreur réseau" };
  }
}
