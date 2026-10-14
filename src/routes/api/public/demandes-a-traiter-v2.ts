import { createFileRoute } from "@tanstack/react-router";

// Route NEUVE appelée par n8n (TC_00 v3, après la bascule seulement), agent STOCK. Protégée par l'en-tête x-tc-secret.
export const Route = createFileRoute("/api/public/demandes-a-traiter-v2")({
  server: {
    handlers: {
      POST: async ({ request }) => {
        const { traiterDemandesATraiterV2 } = await import("@/lib/stock.server");
        return traiterDemandesATraiterV2(request);
      },
    },
  },
});
