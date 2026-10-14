import { createFileRoute } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import { useMemo, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { requireRoles } from "@/lib/auth";
import { messageErreur, quantiteFr } from "@/lib/format";
import { calculer, filtrer, type LigneStat } from "@/lib/stats";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

// Lot L2 : statistiques par entreprise cliente (vue stats_entreprises, security_invoker).
export const Route = createFileRoute("/statistiques")({
  ssr: false,
  beforeLoad: requireRoles(["dirigeant"]),
  head: () => ({
    meta: [
      { title: "Statistiques | Tournée Cycles" },
      {
        name: "description",
        content: "Vélos vus, défauts fréquents et pièces changées, par entreprise.",
      },
      { property: "og:title", content: "Statistiques | Tournée Cycles" },
      {
        property: "og:description",
        content: "Vélos vus, défauts fréquents et pièces changées, par entreprise.",
      },
    ],
  }),
  component: Statistiques,
});

const champ = "mt-1 h-12 w-full rounded-lg border-2 border-input bg-card px-3 text-base";

function Statistiques() {
  const lignes = useQuery({
    queryKey: ["statistiques"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("stats_entreprises")
        .select("entreprise_id, entreprise, site, date_intervention, genre, libelle, quantite");
      if (error) throw error;
      return (data ?? []) as unknown as LigneStat[];
    },
  });
  const toutes = useMemo(() => lignes.data ?? [], [lignes.data]);
  const entreprises = useMemo(
    () =>
      [...new Map(toutes.map((l) => [l.entreprise_id, l.entreprise])).entries()].sort((a, b) =>
        a[1].localeCompare(b[1], "fr"),
      ),
    [toutes],
  );
  const [choixEnt, setChoixEnt] = useState<string | null>(null);
  const entreprise = choixEnt ?? entreprises[0]?.[0] ?? null;
  const sites = useMemo(
    () =>
      [...new Set(toutes.filter((l) => l.entreprise_id === entreprise).map((l) => l.site))].sort(),
    [toutes, entreprise],
  );
  const [site, setSite] = useState<string | null>(null);
  const [du, setDu] = useState("");
  const [au, setAu] = useState("");
  const r = calculer(filtrer(toutes, { entreprise, site, du, au }));

  return (
    <div className="space-y-5">
      <h1 className="text-3xl font-bold text-primary">Statistiques</h1>
      {lignes.isLoading && <p role="status">Chargement.</p>}
      {lignes.error && (
        <p role="alert" className="font-bold text-rose-text">
          {messageErreur(lignes.error)}
        </p>
      )}
      {!lignes.isLoading && !lignes.error && toutes.length === 0 && (
        <p>Aucune fiche pour le moment.</p>
      )}
      {entreprises.length > 0 && (
        <div className="grid gap-3 sm:grid-cols-2">
          <div>
            <Label htmlFor="stat-entreprise">Entreprise</Label>
            <select
              id="stat-entreprise"
              className={champ}
              value={entreprise ?? ""}
              onChange={(e) => {
                setChoixEnt(e.target.value);
                setSite(null);
              }}
            >
              {entreprises.map(([id, nom]) => (
                <option key={id} value={id}>
                  {nom}
                </option>
              ))}
            </select>
          </div>
          <div>
            <Label htmlFor="stat-site">Site</Label>
            <select
              id="stat-site"
              className={champ}
              value={site ?? ""}
              onChange={(e) => setSite(e.target.value || null)}
            >
              <option value="">Tous les sites</option>
              {sites.map((s) => (
                <option key={s} value={s}>
                  {s}
                </option>
              ))}
            </select>
          </div>
          <div>
            <Label htmlFor="stat-du">Du</Label>
            <Input
              id="stat-du"
              type="date"
              className="mt-1 h-12"
              value={du}
              onChange={(e) => setDu(e.target.value)}
            />
          </div>
          <div>
            <Label htmlFor="stat-au">Au</Label>
            <Input
              id="stat-au"
              type="date"
              className="mt-1 h-12"
              value={au}
              onChange={(e) => setAu(e.target.value)}
            />
          </div>
        </div>
      )}
      {entreprises.length > 0 && (
        <>
          <section aria-labelledby="titre-velos" className="rounded-lg border-2 bg-card p-4">
            <h2 id="titre-velos" className="text-xl font-bold">
              Vélos vus : {r.velos}
            </h2>
            <p>
              Sur {r.journees} journée{r.journees > 1 ? "s" : ""}
              {r.parType.length > 0 &&
                ` : ${r.parType.map((t) => `${t.libelle} ${quantiteFr(t.total)}`).join(", ")}`}
              .
            </p>
          </section>
          <Liste
            id="titre-organes"
            titre="Organes en défaut les plus fréquents"
            vide="Aucun défaut relevé sur la période."
            lignes={r.organes.slice(0, 8)}
          />
          <Liste
            id="titre-pieces"
            titre="Pièces changées"
            vide="Aucune pièce changée sur la période."
            lignes={r.pieces}
          />
        </>
      )}
    </div>
  );
}

function Liste(props: {
  id: string;
  titre: string;
  vide: string;
  lignes: { libelle: string; total: number }[];
}) {
  return (
    <section aria-labelledby={props.id} className="rounded-lg border-2 bg-card p-4">
      <h2 id={props.id} className="text-xl font-bold">
        {props.titre}
      </h2>
      {props.lignes.length === 0 ? (
        <p>{props.vide}</p>
      ) : (
        <ul className="mt-2 divide-y">
          {props.lignes.map((l) => (
            <li key={l.libelle} className="flex justify-between gap-3 py-2">
              <span>{l.libelle}</span>
              <span className="font-bold">{quantiteFr(l.total)}</span>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
