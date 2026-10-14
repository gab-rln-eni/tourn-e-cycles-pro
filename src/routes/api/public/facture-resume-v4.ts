import { createFileRoute } from "@tanstack/react-router";

// Route NEUVE appelée par n8n (TC_14), agent V4 : résumé d'une facture prête à valider. Protégée par x-tc-secret.
export const Route = createFileRoute("/api/public/facture-resume-v4")({
  server: {
    handlers: {
      POST: async ({ request }) => {
        const { traiterFactureResumeV4 } = await import("@/lib/v4.server");
        return traiterFactureResumeV4(request);
      },
    },
  },
});
