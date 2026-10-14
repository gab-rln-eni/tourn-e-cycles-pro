import { createFileRoute } from "@tanstack/react-router";

// Route NEUVE (agent V4) : verrou d'affichage V4, écrit seulement par les workflows TC_V4_Verrou_lever_v1 et TC_V4_Verrou_rabaisser_v1.
// POST seulement, protégée par x-tc-secret ; corps strict { faite: true | false }.
export const Route = createFileRoute("/api/public/v4-verrou")({
  server: {
    handlers: {
      POST: async ({ request }) => {
        const { traiterVerrouV4 } = await import("@/lib/v4.server");
        return traiterVerrouV4(request);
      },
    },
  },
});
