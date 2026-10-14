import { createFileRoute } from "@tanstack/react-router";

// Route NEUVE appelée par n8n (TC_30 v2), agent V4 : rappel des pièces à commander (fiches et devis). Protégée par x-tc-secret.
export const Route = createFileRoute("/api/public/rappel-commandes-v4")({
  server: {
    handlers: {
      POST: async ({ request }) => {
        const { traiterRappelCommandesV4 } = await import("@/lib/v4.server");
        return traiterRappelCommandesV4(request);
      },
    },
  },
});
