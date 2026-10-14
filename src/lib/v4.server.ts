// Chantier V4, côté serveur uniquement (agent V4, nuit du 2026-10-14, dérogation de G_R).
// Routes NEUVES appelées par n8n, protégées par x-tc-secret comme les routes de liaison (D-22, D-28) :
//   POST /api/public/rappel-commandes-v4 : rappel de 15 h du workflow TC_30 v2 (pièces des fiches et des devis) ;
//     corps facultatif { essai: true } : pièces LOTS-TEST seulement, sans réserver le jour.
//   POST /api/public/facture-resume-v4 : résumé d'une facture « prête à valider » pour le mail au dirigeant (TC_14),
//     corps { demande_id } (demande de type controle).
//   POST /api/public/v4-verrou : verrou d'affichage V4 sans l'outil SQL (visa G_R, point 3) ; corps STRICT { faite: true | false }
//     (tout autre corps : 400) ; écrit UNIQUEMENT public.v4_bascule (table et colonnes en dur, ligne unique), puis renvoie la valeur relue.
//     Appelée seulement par les workflows figés TC_V4_Verrou_lever_v1 et TC_V4_Verrou_rabaisser_v1. Jamais stock_bascule.
// Les routes existantes ne changent pas.
import { supabaseAdmin } from "@/integrations/supabase/client.server";
import { lireEssai } from "@/lib/commandes.server";
import { refuserSansSecret } from "@/lib/liaison.server";

const json = (corps: unknown, status = 200) =>
  new Response(JSON.stringify(corps), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
  });

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

/** Lit { demande_id } ; null si le corps n'a pas cette forme. */
export function lireDemandeId(texte: string): string | null {
  try {
    const c = JSON.parse(texte) as unknown;
    if (!c || typeof c !== "object" || Array.isArray(c)) return null;
    const id = (c as { demande_id?: unknown }).demande_id;
    return typeof id === "string" && UUID.test(id) ? id : null;
  } catch {
    return null;
  }
}

export async function traiterRappelCommandesV4(request: Request): Promise<Response> {
  const refus = refuserSansSecret(request, process.env["TC_SECRET"]);
  if (refus) return refus;
  const essai = lireEssai(await request.text().catch(() => ""));
  const { data, error } = await supabaseAdmin.rpc("rappel_commandes_reserver_v4", {
    p_essai: essai,
  });
  if (error) {
    console.error("[v4] rappel_commandes_reserver_v4", error.message);
    return json({ ok: false, erreur: "lecture impossible" }, 500);
  }
  return json(data ?? { envoyer: false, raison: "vide" });
}

export async function traiterFactureResumeV4(request: Request): Promise<Response> {
  const refus = refuserSansSecret(request, process.env["TC_SECRET"]);
  if (refus) return refus;
  const id = lireDemandeId(await request.text().catch(() => ""));
  if (!id) return json({ ok: false, erreur: "objet attendu : { demande_id }" }, 400);
  const { data, error } = await supabaseAdmin.rpc("facture_resume_v4", { p_demande: id });
  if (error) {
    console.error("[v4] facture_resume_v4", error.message);
    return json({ ok: false, erreur: "lecture impossible" }, 500);
  }
  if (!data) return json({ ok: false, erreur: "demande introuvable ou d'un autre type" }, 404);
  return json({ ok: true, facture: data });
}

/** Lit le corps strict { faite: booléen } ; toute autre forme (clé en plus, valeur non booléenne) : null. */
export function lireVerrou(texte: string): boolean | null {
  try {
    const c = JSON.parse(texte) as unknown;
    if (!c || typeof c !== "object" || Array.isArray(c)) return null;
    const cles = Object.keys(c);
    if (cles.length !== 1 || cles[0] !== "faite") return null;
    const f = (c as { faite?: unknown }).faite;
    return typeof f === "boolean" ? f : null;
  } catch {
    return null;
  }
}

export async function traiterVerrouV4(request: Request): Promise<Response> {
  const refus = refuserSansSecret(request, process.env["TC_SECRET"]);
  if (refus) return refus;
  const faite = lireVerrou(await request.text().catch(() => ""));
  if (faite === null)
    return json({ ok: false, erreur: "objet attendu : { faite: true | false }" }, 400);
  const ecrit = await supabaseAdmin
    .from("v4_bascule")
    .update({ faite, modifie_le: new Date().toISOString() })
    .eq("id", true);
  if (ecrit.error) {
    console.error("[v4] verrou écriture", ecrit.error.message);
    return json({ ok: false, erreur: "écriture impossible" }, 500);
  }
  const relu = await supabaseAdmin
    .from("v4_bascule")
    .select("faite, modifie_le")
    .eq("id", true)
    .maybeSingle();
  if (relu.error || !relu.data) {
    console.error("[v4] verrou relecture", relu.error?.message ?? "ligne absente");
    return json({ ok: false, erreur: "relecture impossible" }, 500);
  }
  return json({
    ok: relu.data.faite === faite,
    faite: relu.data.faite,
    modifie_le: relu.data.modifie_le,
  });
}
