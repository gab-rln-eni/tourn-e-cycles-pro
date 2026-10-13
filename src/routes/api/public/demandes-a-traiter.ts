import { createFileRoute } from "@tanstack/react-router";

// Route appelée par n8n (TC_00) : réserve les demandes à traiter. Protégée par l'en-tête x-tc-secret.
export const Route = createFileRoute("/api/public/demandes-a-traiter")({
  server: {
    handlers: {
      POST: async ({ request }) => {
        const { traiterDemandesATraiter } = await import("@/lib/liaison.server");
        return traiterDemandesATraiter(request);
      },
    },
  },
});
