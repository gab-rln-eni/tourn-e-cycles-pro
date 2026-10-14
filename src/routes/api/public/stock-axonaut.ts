import { createFileRoute } from "@tanstack/react-router";

// Route NEUVE appelée par n8n (TC_33), agent STOCK. Protégée par l'en-tête x-tc-secret.
export const Route = createFileRoute("/api/public/stock-axonaut")({
  server: {
    handlers: {
      POST: async ({ request }) => {
        const { traiterStockAxonaut } = await import("@/lib/stock.server");
        return traiterStockAxonaut(request);
      },
    },
  },
});
