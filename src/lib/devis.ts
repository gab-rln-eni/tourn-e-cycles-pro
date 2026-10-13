import { createServerFn } from "@tanstack/react-start";
import { getRequest } from "@tanstack/react-start/server";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
import { supabase } from "@/integrations/supabase/client";

// Fonctions serveur du parcours devis : le navigateur n'appelle jamais n8n ni Axonaut, et ne connaît pas le secret.

const texte = (v: unknown, max = 100) => (typeof v === "string" ? v.slice(0, max) : "");

/** Relecture par l'atelier : création du devis dans Axonaut et mail, par n8n (droits vérifiés en base). */
export const envoyerDevisServeur = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((d: unknown) => ({ devisId: texte((d as { devisId?: unknown })?.devisId, 36) }))
  .handler(async ({ data, context }) => {
    const { envoyerDevis } = await import("@/lib/devis.server");
    const req = getRequest();
    const base = process.env["APP_BASE_URL"] || (req ? new URL(req.url).origin : "");
    return envoyerDevis(context.supabase, data.devisId, base);
  });

/** Lecture publique du devis par son jeton (page du cycliste, sans compte). */
export const lireDevisPublicServeur = createServerFn({ method: "POST" })
  .inputValidator((d: unknown) => ({ jeton: texte((d as { jeton?: unknown })?.jeton, 64) }))
  .handler(async ({ data }) => {
    const { lireDevisPublic } = await import("@/lib/devis.server");
    return { devis: (await lireDevisPublic(data.jeton)) as unknown as DevisPublic | null };
  });

/** Décision du cycliste : « J'accepte » ou « Je refuse ». */
export const repondreDevisServeur = createServerFn({ method: "POST" })
  .inputValidator((d: unknown) => ({
    jeton: texte((d as { jeton?: unknown })?.jeton, 64),
    decision: texte((d as { decision?: unknown })?.decision, 10),
  }))
  .handler(async ({ data }) => {
    const { repondreDevis, decisionValide } = await import("@/lib/devis.server");
    if (!decisionValide(data.decision)) return { ok: false, erreur: "Réponse invalide." };
    return repondreDevis(data.jeton, data.decision);
  });

/** Rattrapage : reporter dans Axonaut une décision du client restée non reportée. */
export const relancerReportServeur = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((d: unknown) => ({ devisId: texte((d as { devisId?: unknown })?.devisId, 36) }))
  .handler(async ({ data, context }) => {
    const { relancerReport } = await import("@/lib/devis.server");
    return relancerReport(context.supabase, data.devisId);
  });

/** En-tête de session pour les fonctions serveur protégées (la base vérifie le rôle). */
async function enteteSession(): Promise<Record<string, string> | null> {
  const { data } = await supabase.auth.getSession();
  const jeton = data.session?.access_token;
  return jeton ? { Authorization: `Bearer ${jeton}` } : null;
}

export async function relancerReport(devisId: string) {
  const headers = await enteteSession();
  if (!headers) return { ok: false, erreur: "Session expirée : reconnectez-vous." };
  return relancerReportServeur({ data: { devisId }, headers });
}

/** Appel côté écran de la relecture : transmet le jeton de session pour que la base vérifie le rôle. */
export async function envoyerDevis(devisId: string) {
  const { data } = await supabase.auth.getSession();
  const jeton = data.session?.access_token;
  if (!jeton) return { ok: false, erreur: "Session expirée : reconnectez-vous." };
  return envoyerDevisServeur({ data: { devisId }, headers: { Authorization: `Bearer ${jeton}` } });
}

export type DevisLigne = {
  libelle: string;
  quantite: number;
  prix_unitaire_ht: number;
  taux_tva: number;
};
export type DevisPublic = {
  reference: string;
  statut: string;
  commentaire: string;
  envoye_le: string | null;
  decide_le: string | null;
  lignes: DevisLigne[];
  total_ht: number;
  total_tva: number;
  total_ttc: number;
};

export const STATUT_DEVIS: Record<string, string> = {
  brouillon: "Brouillon",
  a_relire: "À relire",
  envoye: "Envoyé au client",
  accepte: "Accepté",
  refuse: "Refusé",
};

export type Avis = { niveau: "ok" | "attention" | "erreur"; message: string };

/** Lecture tolérante des avis de contrôle renvoyés par la base. */
export function lireAvis(v: unknown): Avis[] {
  if (!Array.isArray(v)) return [];
  return v
    .filter(
      (a): a is { niveau: string; message: string } =>
        !!a && typeof a === "object" && "niveau" in a && "message" in a,
    )
    .map((a) => ({
      niveau: a.niveau === "erreur" || a.niveau === "attention" ? a.niveau : "ok",
      message: String(a.message),
    }));
}
