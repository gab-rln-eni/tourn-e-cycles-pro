import { createFileRoute } from "@tanstack/react-router";
import { requireRoles } from "@/lib/auth";

export const Route = createFileRoute("/journee")({
  ssr: false,
  beforeLoad: requireRoles(["dirigeant", "mecanicien"]),
  head: () => ({
    meta: [
      { title: "La journée | Tournée Cycles" },
      { name: "description", content: "Vélos inscrits à la journée de maintenance." },
      { property: "og:title", content: "La journée | Tournée Cycles" },
      { property: "og:description", content: "Vélos inscrits à la journée de maintenance." },
    ],
  }),
  component: () => <h1 className="text-3xl text-primary">La journée</h1>,
});
