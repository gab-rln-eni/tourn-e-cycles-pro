import { createServerFn } from "@tanstack/react-start";

// Fonction serveur : prévient n8n qu'une demande vient d'être créée (D-22, P1-5 B). Jamais d'appel depuis le navigateur vers n8n.
export const declencherTraitement = createServerFn({ method: "POST" }).handler(async () => {
  const { appelerWebhook } = await import("@/lib/liaison.server");
  return appelerWebhook();
});

/** À appeler après chaque action qui crée une demande ; n'interrompt jamais l'écran (le rattrapage de n8n reprend tout). */
export function prevenirN8n() {
  declencherTraitement().catch(() => undefined);
}
