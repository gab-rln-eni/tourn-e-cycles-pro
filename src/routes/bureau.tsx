import { createFileRoute } from "@tanstack/react-router";
import { requireRoles } from "@/lib/auth";

export const Route = createFileRoute("/bureau")({
  ssr: false,
  beforeLoad: requireRoles(["dirigeant", "atelier"]),
  head: () => ({
    meta: [
      { title: "Bureau | Tournée Cycles" },
      { name: "description", content: "Factures et tableau de bord." },
      { property: "og:title", content: "Bureau | Tournée Cycles" },
      { property: "og:description", content: "Factures et tableau de bord." },
    ],
  }),
  component: () => <h1 className="text-3xl text-primary">Bureau</h1>,
});
