// Parcours devis, côté serveur uniquement (nuit du 2026-10-14, dérogation de G_R).
// Les workflows du devis reçoivent les données DANS LE CORPS de leur webhook (aucune lecture de l'app par n8n) :
// POST {N8N_BASE_URL}/webhook/tc-devis-creer et /webhook/tc-devis-decision, en-tête x-tc-secret = TC_SECRET (jamais écrit dans le code).
import { createClient } from "@supabase/supabase-js";
import { supabaseAdmin } from "@/integrations/supabase/client.server";
import type { Database, Json } from "@/integrations/supabase/types";

export type Decision = "accepte" | "refuse";
export type ResultatN8n = {
  ok: boolean;
  erreur: string;
  resultat: Record<string, unknown>;
};

const JETON = /^[0-9a-f]{64}$/;
export const jetonValide = (j: unknown): j is string => typeof j === "string" && JETON.test(j);
export const decisionValide = (d: unknown): d is Decision => d === "accepte" || d === "refuse";

export type AvisBrut = { niveau: string; message: string };
/** Avis de contrôle reçus de la base, réduits à { niveau, message } (sérialisables). */
export function avisBruts(v: unknown): AvisBrut[] {
  if (!Array.isArray(v)) return [];
  return v
    .filter((a): a is Record<string, unknown> => !!a && typeof a === "object" && !Array.isArray(a))
    .map((a) => ({ niveau: String(a["niveau"] ?? ""), message: String(a["message"] ?? "") }));
}

/** Adresse de la page du cycliste ; base de l'app tirée de APP_BASE_URL, sinon de l'origine de la requête. */
export function lienReponse(base: string, jeton: string): string {
  return `${base.replace(/\/+$/, "")}/devis/${jeton}`;
}

/** Corps envoyé à tc-devis-creer : données préparées par devis_preparer_envoi, plus le lien de réponse. */
export function corpsCreation(
  donnees: Record<string, unknown>,
  lien: string,
): Record<string, unknown> {
  return { ...donnees, lien_reponse: lien };
}

/** Lecture tolérante de la réponse d'un workflow : toute forme inattendue devient un échec lisible, jamais une exception. */
export function lireReponseN8n(status: number, texte: string): ResultatN8n {
  let j: unknown = null;
  try {
    j = JSON.parse(texte);
  } catch {
    j = null;
  }
  if (!j || typeof j !== "object" || Array.isArray(j)) {
    return { ok: false, erreur: `réponse illisible de n8n (HTTP ${status})`, resultat: {} };
  }
  const o = j as { ok?: unknown; erreur?: unknown; resultat?: unknown };
  const resultat =
    o.resultat && typeof o.resultat === "object" && !Array.isArray(o.resultat)
      ? (o.resultat as Record<string, unknown>)
      : {};
  if (status < 200 || status >= 300) {
    return { ok: false, erreur: String(o.erreur || `n8n a répondu HTTP ${status}`), resultat };
  }
  return { ok: o.ok === true, erreur: String(o.erreur ?? ""), resultat };
}

/** Appel d'un webhook du devis ; délai de 30 s (Axonaut puis Gmail) ; aucune exception ne remonte. */
export async function appelerWorkflow(
  chemin: "tc-devis-creer" | "tc-devis-decision",
  corps: Record<string, unknown>,
): Promise<ResultatN8n> {
  const base = process.env["N8N_BASE_URL"];
  const secret = process.env["TC_SECRET"];
  if (!base || !secret) return { ok: false, erreur: "n8n non configuré", resultat: {} };
  try {
    const r = await fetch(`${base.replace(/\/+$/, "")}/webhook/${chemin}`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "ngrok-skip-browser-warning": "1",
        "x-tc-secret": secret,
      },
      body: JSON.stringify(corps),
      signal: AbortSignal.timeout(30000),
    });
    return lireReponseN8n(r.status, await r.text());
  } catch (e) {
    return {
      ok: false,
      erreur: e instanceof Error ? `n8n injoignable (${e.name})` : "n8n injoignable",
      resultat: {},
    };
  }
}

/** Client sans session (rôle anon) : seules les deux fonctions à jeton lui sont ouvertes. */
function clientAnonyme() {
  const url = process.env["SUPABASE_URL"];
  const cle = process.env["SUPABASE_PUBLISHABLE_KEY"];
  if (!url || !cle) throw new Error("Supabase non configuré");
  return createClient<Database>(url, cle, {
    auth: { storage: undefined, persistSession: false, autoRefreshToken: false },
  });
}

/** Relecture par l'atelier : préparation (droits vérifiés par la base sous l'identité de l'utilisateur), appel de n8n, report du résultat. */
export async function envoyerDevis(
  supabaseUtilisateur: ReturnType<typeof createClient<Database>>,
  devisId: string,
  baseApp: string,
): Promise<{ ok: boolean; erreur: string; avis?: AvisBrut[]; lien?: string; numero?: string }> {
  const { data, error } = await supabaseUtilisateur.rpc("devis_preparer_envoi", {
    p_devis: devisId,
  });
  if (error) return { ok: false, erreur: error.message };
  const prep = (data ?? {}) as {
    ok?: boolean;
    avis?: unknown;
    jeton?: string;
    donnees?: Record<string, unknown>;
  };
  if (!prep.ok || !prep.donnees || !jetonValide(prep.jeton)) {
    return {
      ok: false,
      erreur: "Le devis comporte une erreur à corriger.",
      avis: avisBruts(prep.avis),
    };
  }
  const lien = lienReponse(baseApp, prep.jeton);
  const rep = await appelerWorkflow("tc-devis-creer", corpsCreation(prep.donnees, lien));
  const r = rep.resultat;
  const note = await supabaseAdmin.rpc("devis_noter_envoi", {
    p: {
      devis_id: devisId,
      ok: rep.ok,
      erreur: rep.erreur,
      axonaut_devis_id: String(r["axonaut_devis_id"] ?? ""),
      numero: String(r["numero"] ?? ""),
      public_path: String(r["public_path"] ?? ""),
    } as Json,
  });
  if (note.error) console.error("[devis] devis_noter_envoi", note.error.message);
  if (!rep.ok) return { ok: false, erreur: rep.erreur || "Création du devis impossible." };
  return { ok: true, erreur: rep.erreur, lien, numero: String(r["numero"] ?? "") };
}

/** Page du cycliste : lecture par jeton, sans session. */
export async function lireDevisPublic(jeton: string): Promise<Json | null> {
  if (!jetonValide(jeton)) return null;
  const { data, error } = await clientAnonyme().rpc("devis_public", { p_jeton: jeton });
  if (error) throw new Error("Devis illisible.");
  return data ?? null;
}

/** Décision du cycliste : enregistrée en base (une seule fois), puis reportée dans Axonaut par n8n ; un échec du report ne défait pas la décision. */
export async function repondreDevis(
  jeton: string,
  decision: Decision,
): Promise<{ ok: boolean; statut?: string | undefined; erreur: string; report?: boolean }> {
  if (!jetonValide(jeton) || !decisionValide(decision))
    return { ok: false, erreur: "Lien ou réponse invalide." };
  const { data, error } = await clientAnonyme().rpc("devis_repondre", {
    p_jeton: jeton,
    p_decision: decision,
  });
  if (error) return { ok: false, erreur: "Réponse non enregistrée. Réessayez." };
  const r = (data ?? {}) as {
    ok?: boolean;
    statut?: string;
    deja?: boolean;
    erreur?: string;
    devis_id?: string;
    reference?: string;
    axonaut_devis_id?: string;
    axonaut_client_id?: string;
  };
  if (!r.ok) return { ok: false, statut: r.statut, erreur: r.erreur || "Réponse refusée." };
  if (r.deja) return { ok: true, statut: r.statut, erreur: "" };
  const rep = await appelerWorkflow("tc-devis-decision", {
    devis_id: r.devis_id,
    reference: r.reference,
    axonaut_devis_id: r.axonaut_devis_id ?? "",
    axonaut_client_id: r.axonaut_client_id ?? "",
    decision,
  });
  const note = await supabaseAdmin.rpc("devis_noter_decision", {
    p: { devis_id: r.devis_id, ok: rep.ok, erreur: rep.erreur } as Json,
  });
  if (note.error) console.error("[devis] devis_noter_decision", note.error.message);
  return { ok: true, statut: r.statut, erreur: "", report: rep.ok };
}
