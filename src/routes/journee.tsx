import { createFileRoute, Link } from "@tanstack/react-router";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { toast } from "sonner";
import { Copy, Plus } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { requireRoles, useAuth } from "@/lib/auth";
import { PARTIE_LABEL, TYPE_VELO, dateLongue, messageErreur, todayISO } from "@/lib/format";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";

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
  component: Journee,
});

type Ev = {
  id: string;
  site: string;
  adresse: string;
  date_intervention: string;
  statut: string;
  code: string;
  entreprises: { nom: string; code: string } | null;
};

function journeeParDefaut(evs: Ev[]): string | null {
  if (evs.length === 0) return null;
  const auj = todayISO();
  const dujour = evs.find((e) => e.date_intervention === auj);
  if (dujour) return dujour.id;
  const futures = evs
    .filter((e) => e.date_intervention > auj)
    .sort((a, b) => a.date_intervention.localeCompare(b.date_intervention));
  if (futures[0]) return futures[0].id;
  return [...evs].sort((a, b) => b.date_intervention.localeCompare(a.date_intervention))[0]!.id;
}

function Journee() {
  const { data: auth } = useAuth();
  const dirigeant = !!auth?.roles.includes("dirigeant");
  const [choix, setChoix] = useState<string | null>(null);
  const [creation, setCreation] = useState(false);

  const evs = useQuery({
    queryKey: ["evenements"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("evenements")
        .select("id, site, adresse, date_intervention, statut, code, entreprises(nom, code)")
        .order("date_intervention");
      if (error) throw error;
      return data as unknown as Ev[];
    },
  });

  const liste = evs.data ?? [];
  const actif = choix ?? journeeParDefaut(liste);
  const ev = liste.find((e) => e.id === actif) ?? null;

  return (
    <div className="space-y-5">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h1 className="text-3xl font-bold text-primary">La journée</h1>
        {dirigeant && (
          <Button onClick={() => setCreation(true)}>
            <Plus aria-hidden /> Nouvelle journée
          </Button>
        )}
      </div>

      {evs.isLoading && <p role="status">Chargement des journées.</p>}
      {evs.error && (
        <p role="alert" className="font-bold text-rose-text">
          {messageErreur(evs.error)}
        </p>
      )}
      {!evs.isLoading && liste.length === 0 && (
        <p>Aucune journée prévue.{dirigeant ? " Créez la première." : ""}</p>
      )}

      {liste.length > 0 && (
        <div>
          <Label htmlFor="choix-journee">Journée</Label>
          <select
            id="choix-journee"
            className="mt-1 h-12 w-full rounded-lg border-2 border-input bg-card px-3 text-base"
            value={actif ?? ""}
            onChange={(e) => setChoix(e.target.value)}
          >
            {liste.map((e) => (
              <option key={e.id} value={e.id}>
                {dateLongue(e.date_intervention)}, {e.entreprises?.nom}, {e.site}
              </option>
            ))}
          </select>
        </div>
      )}

      {ev && <DetailJournee ev={ev} dirigeant={dirigeant} />}

      {dirigeant && (
        <NouvelleJournee
          ouvert={creation}
          onOpenChange={setCreation}
          onCree={(id) => setChoix(id)}
        />
      )}
    </div>
  );
}

function lienInscription(codeEntreprise: string, codeJournee?: string) {
  const base = `${window.location.origin}/inscription?c=${codeEntreprise}`;
  return codeJournee ? `${base}&e=${codeJournee}` : base;
}

function Liens({ ev }: { ev: Ev }) {
  if (!ev.entreprises) return null;
  const liens = [
    { titre: "Lien d'inscription de l'entreprise", url: lienInscription(ev.entreprises.code) },
    {
      titre: "Lien d'inscription de cette journée",
      url: lienInscription(ev.entreprises.code, ev.code),
    },
  ];
  return (
    <ul className="space-y-2">
      {liens.map((l) => (
        <li key={l.titre} className="rounded-lg border-2 p-3">
          <p className="font-bold">{l.titre}</p>
          <p className="break-all text-sm">{l.url}</p>
          <Button
            variant="outline"
            className="mt-2 w-full"
            onClick={async () => {
              try {
                await navigator.clipboard.writeText(l.url);
                toast.success("Lien copié.");
              } catch {
                toast.error("Copie impossible : sélectionnez le lien à la main.");
              }
            }}
          >
            <Copy aria-hidden /> Copier le lien
          </Button>
        </li>
      ))}
    </ul>
  );
}

function DetailJournee({ ev, dirigeant }: { ev: Ev; dirigeant: boolean }) {
  const q = useQuery({
    queryKey: ["inscrits", ev.id],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("inscriptions")
        .select("id, nom, prenom, type_velo, partie_signalee, fiches(statut)")
        .eq("evenement_id", ev.id)
        .order("nom");
      if (error) throw error;
      return data as unknown as {
        id: string;
        nom: string;
        prenom: string;
        type_velo: string;
        partie_signalee: string;
        fiches: { statut: string } | { statut: string }[] | null;
      }[];
    },
  });
  const etatFiche = (f: { statut: string } | { statut: string }[] | null) => {
    const x = Array.isArray(f) ? f[0] : f;
    return x ? (x.statut === "terminee" ? "Terminée" : "En cours") : "À faire";
  };
  const inscrits = q.data ?? [];
  const terminees = inscrits.filter((i) => etatFiche(i.fiches) === "Terminée").length;

  return (
    <section aria-labelledby="titre-journee" className="space-y-4">
      <header className="rounded-xl bg-card p-4 shadow-sm">
        <h2 id="titre-journee" className="text-2xl font-bold text-primary">
          {ev.entreprises?.nom}, {ev.site}
        </h2>
        <p className="mt-1">{dateLongue(ev.date_intervention)}</p>
        {ev.adresse && <p className="text-sm">{ev.adresse}</p>}
        {ev.statut === "clos" && <p className="mt-1 font-bold">Inscriptions closes</p>}
        <dl className="mt-3 grid grid-cols-2 gap-2 text-center">
          <div className="rounded-lg bg-accent p-2">
            <dt className="text-sm">Inscrits</dt>
            <dd className="text-2xl font-bold">{inscrits.length}</dd>
          </div>
          <div className="rounded-lg bg-accent p-2">
            <dt className="text-sm">Fiches terminées</dt>
            <dd className="text-2xl font-bold">{terminees}</dd>
          </div>
        </dl>
      </header>

      {dirigeant && (
        <details className="rounded-xl bg-card shadow-sm">
          <summary className="tap cursor-pointer p-4 font-bold">
            Liens d'inscription à transmettre
          </summary>
          <div className="px-4 pb-4">
            <Liens ev={ev} />
          </div>
        </details>
      )}

      {q.isLoading && <p role="status">Chargement des inscrits.</p>}
      {q.error && (
        <p role="alert" className="font-bold text-rose-text">
          {messageErreur(q.error)}
        </p>
      )}
      {!q.isLoading && inscrits.length === 0 && <p>Aucun vélo inscrit pour cette journée.</p>}
      <ul className="space-y-3">
        {inscrits.map((i) => {
          const etat = etatFiche(i.fiches);
          return (
            <li key={i.id}>
              <Link
                to="/fiche/$inscriptionId"
                params={{ inscriptionId: i.id }}
                className="tap block rounded-xl bg-card p-4 shadow-sm outline-offset-2 hover:bg-accent"
              >
                <span className="flex items-center justify-between gap-2">
                  <span className="text-lg font-bold">
                    {i.prenom} {i.nom}
                  </span>
                  <span
                    className={
                      "rounded-full px-3 py-1 text-sm font-bold " +
                      (etat === "Terminée"
                        ? "bg-primary text-primary-foreground"
                        : etat === "En cours"
                          ? "bg-rose text-white"
                          : "bg-accent text-accent-foreground")
                    }
                  >
                    {etat}
                  </span>
                </span>
                <span className="mt-1 block">
                  {TYPE_VELO[i.type_velo] ?? i.type_velo},{" "}
                  {PARTIE_LABEL[i.partie_signalee] ?? i.partie_signalee}
                </span>
              </Link>
            </li>
          );
        })}
      </ul>
    </section>
  );
}

function NouvelleJournee({
  ouvert,
  onOpenChange,
  onCree,
}: {
  ouvert: boolean;
  onOpenChange: (o: boolean) => void;
  onCree: (id: string) => void;
}) {
  const qc = useQueryClient();
  const [entrepriseId, setEntrepriseId] = useState("nouvelle");
  const [nom, setNom] = useState("");
  const [site, setSite] = useState("");
  const [adresse, setAdresse] = useState("");
  const [date, setDate] = useState(todayISO());
  const [places, setPlaces] = useState("");
  const [erreur, setErreur] = useState("");
  const [enCours, setEnCours] = useState(false);
  const [creee, setCreee] = useState<Ev | null>(null);

  const ents = useQuery({
    queryKey: ["entreprises"],
    enabled: ouvert,
    queryFn: async () => {
      const { data, error } = await supabase.from("entreprises").select("id, nom").order("nom");
      if (error) throw error;
      return data;
    },
  });

  function fermer(o: boolean) {
    if (!o) {
      setCreee(null);
      setErreur("");
      setNom("");
      setSite("");
      setAdresse("");
      setPlaces("");
    }
    onOpenChange(o);
  }

  async function creer(e: React.FormEvent) {
    e.preventDefault();
    setErreur("");
    setEnCours(true);
    try {
      let entId = entrepriseId;
      if (entId === "nouvelle") {
        if (!nom.trim()) throw new Error("Indiquez le nom de l'entreprise.");
        const { data, error } = await supabase
          .from("entreprises")
          .insert({ nom: nom.trim() })
          .select("id")
          .single();
        if (error) throw error;
        entId = data.id;
      }
      if (!site.trim()) throw new Error("Indiquez le site.");
      const p = places.trim() ? Number(places) : null;
      if (p !== null && (!Number.isInteger(p) || p <= 0))
        throw new Error("Le nombre de places doit être un entier positif.");
      const { data, error } = await supabase
        .from("evenements")
        .insert({
          entreprise_id: entId,
          site: site.trim(),
          adresse: adresse.trim(),
          date_intervention: date,
          places_max: p,
        })
        .select("id, site, adresse, date_intervention, statut, code, entreprises(nom, code)")
        .single();
      if (error) throw error;
      const ev = data as unknown as Ev;
      setCreee(ev);
      await qc.invalidateQueries({ queryKey: ["evenements"] });
      await qc.invalidateQueries({ queryKey: ["entreprises"] });
      onCree(ev.id);
    } catch (err) {
      setErreur(messageErreur(err));
    } finally {
      setEnCours(false);
    }
  }

  return (
    <Dialog open={ouvert} onOpenChange={fermer}>
      <DialogContent className="max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{creee ? "Journée créée" : "Nouvelle journée"}</DialogTitle>
          <DialogDescription>
            {creee
              ? "Transmettez un de ces liens au responsable vélo de l'entreprise."
              : "Entreprise, site, adresse et date."}
          </DialogDescription>
        </DialogHeader>
        {creee ? (
          <div className="space-y-3">
            <Liens ev={creee} />
            <Button className="w-full" onClick={() => fermer(false)}>
              Fermer
            </Button>
          </div>
        ) : (
          <form onSubmit={creer} className="space-y-4">
            <div>
              <Label htmlFor="nj-ent">Entreprise</Label>
              <select
                id="nj-ent"
                className="mt-1 h-12 w-full rounded-lg border-2 border-input bg-card px-3 text-base"
                value={entrepriseId}
                onChange={(e) => setEntrepriseId(e.target.value)}
              >
                <option value="nouvelle">Nouvelle entreprise</option>
                {(ents.data ?? []).map((e) => (
                  <option key={e.id} value={e.id}>
                    {e.nom}
                  </option>
                ))}
              </select>
            </div>
            {entrepriseId === "nouvelle" && (
              <div>
                <Label htmlFor="nj-nom">Nom de l'entreprise (obligatoire)</Label>
                <Input
                  id="nj-nom"
                  className="h-12"
                  maxLength={150}
                  value={nom}
                  onChange={(e) => setNom(e.target.value)}
                />
              </div>
            )}
            <div>
              <Label htmlFor="nj-site">Site (obligatoire)</Label>
              <Input
                id="nj-site"
                className="h-12"
                maxLength={150}
                value={site}
                onChange={(e) => setSite(e.target.value)}
              />
            </div>
            <div>
              <Label htmlFor="nj-adr">Adresse</Label>
              <Input
                id="nj-adr"
                className="h-12"
                maxLength={300}
                value={adresse}
                onChange={(e) => setAdresse(e.target.value)}
              />
            </div>
            <div>
              <Label htmlFor="nj-date">Date (obligatoire)</Label>
              <Input
                id="nj-date"
                type="date"
                required
                className="h-12"
                value={date}
                onChange={(e) => setDate(e.target.value)}
              />
            </div>
            <div>
              <Label htmlFor="nj-places">Nombre de places (facultatif)</Label>
              <Input
                id="nj-places"
                type="number"
                inputMode="numeric"
                min="1"
                className="h-12"
                value={places}
                onChange={(e) => setPlaces(e.target.value)}
              />
            </div>
            {erreur && (
              <p role="alert" className="font-bold text-rose-text">
                {erreur}
              </p>
            )}
            <Button type="submit" className="w-full" disabled={enCours}>
              Créer la journée
            </Button>
          </form>
        )}
      </DialogContent>
    </Dialog>
  );
}
