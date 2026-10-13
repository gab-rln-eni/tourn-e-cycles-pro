import { createFileRoute } from "@tanstack/react-router";

// Route appelée par n8n (TC_00) : écrit le résultat d'une demande. Protégée par l'en-tête x-tc-secret.
export const Route = createFileRoute("/api/public/demande-resultat")({
  server: {
    handlers: {
      POST: async ({ request }) => {
        const { traiterDemandeResultat } = await import("@/lib/liaison.server");
        return traiterDemandeResultat(request);
      },
    },
  },
});
