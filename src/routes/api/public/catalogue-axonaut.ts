import { createFileRoute } from "@tanstack/react-router";

// Route NEUVE appelée par n8n (TC_20 v3 et TC_33), agent STOCK. Protégée par l'en-tête x-tc-secret.
export const Route = createFileRoute("/api/public/catalogue-axonaut")({
  server: {
    handlers: {
      POST: async ({ request }) => {
        const { traiterCatalogueAxonaut } = await import("@/lib/stock.server");
        return traiterCatalogueAxonaut(request);
      },
    },
  },
});
