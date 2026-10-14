import { createFileRoute } from "@tanstack/react-router";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";
import { requireRoles } from "@/lib/auth";
import { dateLongue, messageErreur } from "@/lib/format";
import { finDeJourneeParis, ROLE_ACCES, type Acces } from "@/lib/acces";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

// Lot L3 : accès des prestataires (voir, donner, retirer, redonner), réservé au dirigeant.
export const Route = createFileRoute("/acces")({
  ssr: false,
  beforeLoad: requireRoles(["dirigeant"]),
  head: () => ({
    meta: [
      { title: "Accès | Tournée Cycles" },
      { name: "description", content: "Accès des mécaniciens et de l'atelier." },
      { property: "og:title", content: "Accès | Tournée Cycles" },
      { property: "og:description", content: "Accès des mécaniciens et de l'atelier." },
    ],
  }),
  component: AccesPage,
});

const ETAT: Record<string, string> = { actif: "Actif", expire: "Expiré", retire: "Retiré" };
const champ = "mt-1 h-12 w-full rounded-lg border-2 border-input bg-card px-3 text-base";

function AccesPage() {
  const qc = useQueryClient();
  const liste = useQuery({
    queryKey: ["acces"],
    queryFn: async () => {
      const { data, error } = await supabase.rpc("acces_liste");
      if (error) throw error;
      return (data ?? []) as unknown as Acces[];
    },
  });
  const donner = useMutation({
    mutationFn: async (v: { email: string; role: "mecanicien" | "atelier"; date: string }) => {
      const { data, error } = await supabase.rpc("acces_donner", {
        p_email: v.email,
        p_role: v.role,
        p_expire_le: finDeJourneeParis(v.date),
      });
      if (error) throw error;
      return data as { action?: string };
    },
    onSuccess: (d) => {
      toast.success(
        d?.action === "redonne"
          ? "Accès redonné."
          : d?.action === "modifie"
            ? "Date d'expiration modifiée."
            : "Accès donné.",
      );
      qc.invalidateQueries({ queryKey: ["acces"] });
    },
    onError: (e) => toast.error(messageErreur(e)),
  });
  const retirer = useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase.rpc("acces_retirer", { p_id: id });
      if (error) throw error;
    },
    onSuccess: () => {
      toast.success("Accès retiré.");
      qc.invalidateQueries({ queryKey: ["acces"] });
    },
    onError: (e) => toast.error(messageErreur(e)),
  });

  const [email, setEmail] = useState("");
  const [role, setRole] = useState<"mecanicien" | "atelier">("mecanicien");
  const [date, setDate] = useState("");
  const [redonnerDate, setRedonnerDate] = useState<Record<string, string>>({});

  return (
    <div className="space-y-5">
      <h1 className="text-3xl font-bold text-primary">Accès</h1>
      <p>
        Accès des mécaniciens et de l'atelier. La personne se connecte avec cette adresse email.
      </p>

      <form
        className="space-y-3 rounded-lg border-2 bg-card p-4"
        onSubmit={(e) => {
          e.preventDefault();
          donner.mutate({ email, role, date });
        }}
      >
        <h2 className="text-xl font-bold">Donner un accès</h2>
        <div>
          <Label htmlFor="acces-email">Email</Label>
          <Input
            id="acces-email"
            type="email"
            className="mt-1 h-12"
            required
            value={email}
            onChange={(e) => setEmail(e.target.value)}
          />
        </div>
        <div className="grid gap-3 sm:grid-cols-2">
          <div>
            <Label htmlFor="acces-role">Rôle</Label>
            <select
              id="acces-role"
              className={champ}
              value={role}
              onChange={(e) => setRole(e.target.value as "mecanicien" | "atelier")}
            >
              <option value="mecanicien">{ROLE_ACCES["mecanicien"]}</option>
              <option value="atelier">{ROLE_ACCES["atelier"]}</option>
            </select>
          </div>
          <div>
            <Label htmlFor="acces-date">Accès jusqu'au (inclus)</Label>
            <Input
              id="acces-date"
              type="date"
              className="mt-1 h-12"
              required
              value={date}
              onChange={(e) => setDate(e.target.value)}
            />
          </div>
        </div>
        <Button type="submit" disabled={donner.isPending || !email || !date}>
          Donner l'accès
        </Button>
      </form>

      {liste.isLoading && <p role="status">Chargement des accès.</p>}
      {liste.error && (
        <p role="alert" className="font-bold text-rose-text">
          {messageErreur(liste.error)}
        </p>
      )}
      <ul className="space-y-3" aria-label="Accès">
        {(liste.data ?? []).map((a) => (
          <li key={a.id} className="rounded-lg border-2 bg-card p-3">
            <p className="break-all text-lg font-bold">{a.email}</p>
            <p>
              {ROLE_ACCES[a.role] ?? a.role} : {ETAT[a.etat] ?? a.etat}
              {a.expire_le ? `, jusqu'au ${dateLongue(a.expire_le)}` : ""}
            </p>
            {a.protege && a.etat === "actif" ? (
              <p className="text-sm font-bold">
                Accès protégé : ne peut être ni retiré ni raccourci.
              </p>
            ) : a.etat === "actif" ? (
              <Button
                variant="outline"
                className="mt-2"
                disabled={retirer.isPending}
                onClick={() => retirer.mutate(a.id)}
              >
                Retirer l'accès
              </Button>
            ) : a.role !== "dirigeant" ? (
              <div className="mt-2 flex flex-wrap items-end gap-2">
                <div>
                  <Label htmlFor={`redonner-${a.id}`}>Redonner jusqu'au</Label>
                  <Input
                    id={`redonner-${a.id}`}
                    type="date"
                    className="mt-1 h-12"
                    value={redonnerDate[a.id] ?? ""}
                    onChange={(e) => setRedonnerDate({ ...redonnerDate, [a.id]: e.target.value })}
                  />
                </div>
                <Button
                  disabled={donner.isPending || !redonnerDate[a.id]}
                  onClick={() =>
                    donner.mutate({
                      email: a.email,
                      role: a.role as "mecanicien" | "atelier",
                      date: redonnerDate[a.id]!,
                    })
                  }
                >
                  Redonner l'accès
                </Button>
              </div>
            ) : null}
          </li>
        ))}
      </ul>
    </div>
  );
}
