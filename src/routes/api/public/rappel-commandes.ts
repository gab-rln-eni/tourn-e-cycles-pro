import { createFileRoute } from "@tanstack/react-router";

// Route appelée par n8n (TC_30) : pièces à commander pour le rappel quotidien. Protégée par l'en-tête x-tc-secret.
export const Route = createFileRoute("/api/public/rappel-commandes")({
  server: {
    handlers: {
      POST: async ({ request }) => {
        const { traiterRappelCommandes } = await import("@/lib/commandes.server");
        return traiterRappelCommandes(request);
      },
    },
  },
});
