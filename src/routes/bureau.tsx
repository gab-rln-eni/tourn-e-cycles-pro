import { createFileRoute } from "@tanstack/react-router";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect, useState } from "react";
import { toast } from "sonner";
import { AlertTriangle, CheckCircle2, Plus, Trash2, XCircle } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { requireRoles, useAuth } from "@/lib/auth";
import {
  ETAT_LABEL,
  STATUT_FACTURE,
  dateHeure,
  dateLongue,
  euros,
  messageErreur,
  totaux,
} from "@/lib/format";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";

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
  component: Bureau,
});

type FactureListe = {
  id: string;
  statut: string;
  inscriptions: {
    nom: string;
    prenom: string;
    evenements: {
      id: string;
      site: string;
      date_intervention: string;
      entreprises: { nom: string } | null;
    } | null;
  } | null;
};

function Bureau() {
  const [ouverte, setOuverte] = useState<string | null>(null);
  return (
    <div className="space-y-4">
      <h1 className="text-3xl font-bold text-primary">Bureau</h1>
      <Tabs defaultValue="factures">
        <TabsList className="grid h-auto w-full grid-cols-2">
          <TabsTrigger value="factures" className="min-h-12 text-base font-bold">
            Factures
          </TabsTrigger>
          <TabsTrigger value="tableau" className="min-h-12 text-base font-bold">
            Tableau de bord
          </TabsTrigger>
        </TabsList>
        <TabsContent value="factures" className="mt-4">
          {ouverte ? (
            <DetailFacture id={ouverte} onRetour={() => setOuverte(null)} />
          ) : (
            <ListeFactures onOuvrir={setOuverte} />
          )}
        </TabsContent>
        <TabsContent value="tableau" className="mt-4">
          <TableauDeBord />
        </TabsContent>
      </Tabs>
    </div>
  );
}

function ListeFactures({ onOuvrir }: { onOuvrir: (id: string) => void }) {
  const q = useQuery({
    queryKey: ["factures"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("factures")
        .select(
          "id, statut, inscriptions(nom, prenom, evenements(id, site, date_intervention, entreprises(nom)))",
        )
        .order("created_at", { ascending: false });
      if (error) throw error;
      return data as unknown as FactureListe[];
    },
  });
  if (q.isLoading) return <p role="status">Chargement des factures.</p>;
  if (q.error)
    return (
      <p role="alert" className="font-bold text-rose-text">
        {messageErreur(q.error)}
      </p>
    );
  const factures = q.data ?? [];
  if (factures.length === 0)
    return (
      <p>Aucune facture pour le moment. Une facture est créée quand une fiche est terminée.</p>
    );

  const groupes = new Map<string, { titre: string; date: string; items: FactureListe[] }>();
  for (const f of factures) {
    const ev = f.inscriptions?.evenements;
    const k = ev?.id ?? "sans";
    if (!groupes.has(k))
      groupes.set(k, {
        titre: ev ? `${ev.entreprises?.nom ?? ""}, ${ev.site}` : "Sans journée",
        date: ev?.date_intervention ?? "",
        items: [],
      });
    groupes.get(k)!.items.push(f);
  }

  return (
    <div className="space-y-6">
      {[...groupes.values()]
        .sort((a, b) => b.date.localeCompare(a.date))
        .map((g) => (
          <section key={g.titre + g.date} aria-label={g.titre}>
            <h2 className="text-lg font-bold">{g.titre}</h2>
            <p className="text-sm">{dateLongue(g.date)}</p>
            <ul className="mt-2 space-y-2">
              {g.items.map((f) => (
                <li key={f.id}>
                  <button
                    type="button"
                    onClick={() => onOuvrir(f.id)}
                    className="tap flex w-full items-center justify-between gap-2 rounded-xl bg-card p-4 text-left shadow-sm"
                  >
                    <span className="font-bold">
                      {f.inscriptions?.prenom} {f.inscriptions?.nom}
                    </span>
                    <Statut statut={f.statut} />
                  </button>
                </li>
              ))}
            </ul>
          </section>
        ))}
    </div>
  );
}

function Statut({ statut }: { statut: string }) {
  const fort = ["validee", "envoyee"].includes(statut);
  const alerte = statut === "echec";
  return (
    <span
      className={
        "rounded-full px-3 py-1 text-sm font-bold " +
        (alerte
          ? "bg-rose text-white"
          : fort
            ? "bg-primary text-primary-foreground"
            : "bg-accent text-accent-foreground")
      }
    >
      {STATUT_FACTURE[statut] ?? statut}
    </span>
  );
}

type Ligne = {
  id: string;
  libelle: string;
  quantite: number;
  prix_unitaire_ht: number;
  taux_tva: number;
  ordre: number;
};

function DetailFacture({ id, onRetour }: { id: string; onRetour: () => void }) {
  const qc = useQueryClient();
  const { data: auth } = useAuth();
  const dirigeant = !!auth?.roles.includes("dirigeant");
  const [confirmer, setConfirmer] = useState(false);

  const q = useQuery({
    queryKey: ["facture", id],
    queryFn: async () => {
      const ctl = await supabase.rpc("controler_facture", { p_facture: id });
      const { data: f, error } = await supabase
        .from("factures")
        .select(
          "*, inscriptions(id, nom, prenom, email, telephone, evenements(site, date_intervention, entreprises(nom)))",
        )
        .eq("id", id)
        .single();
      if (error) throw error;
      const insc = f.inscriptions as unknown as {
        id: string;
        nom: string;
        prenom: string;
        email: string;
        telephone: string;
        evenements: {
          site: string;
          date_intervention: string;
          entreprises: { nom: string } | null;
        } | null;
      };
      const [lignes, avis, fiche] = await Promise.all([
        supabase.from("facture_lignes").select("*").eq("facture_id", id).order("ordre"),
        supabase.from("avis_controle").select("*").eq("facture_id", id).order("created_at"),
        supabase
          .from("fiches")
          .select("id, commentaire, fiche_points(groupe, point, etat, constats, remarque)")
          .eq("inscription_id", insc.id)
          .maybeSingle(),
      ]);
      if (lignes.error) throw lignes.error;
      return {
        f,
        insc,
        lignes: (lignes.data ?? []) as Ligne[],
        avis: avis.data ?? [],
        fiche: fiche.data as unknown as {
          commentaire: string | null;
          fiche_points: {
            groupe: string;
            point: string;
            etat: string;
            constats: string[];
            remarque: string | null;
          }[];
        } | null,
        erreurControle: ctl.error ? messageErreur(ctl.error) : null,
      };
    },
  });

  const recharger = () => {
    qc.invalidateQueries({ queryKey: ["facture", id] });
    qc.invalidateQueries({ queryKey: ["factures"] });
  };

  async function exec(p: PromiseLike<{ error: unknown }>) {
    const { error } = await p;
    if (error) toast.error(`Non enregistré : ${messageErreur(error)}`);
    recharger();
  }

  const valider = useMutation({
    mutationFn: async () => {
      const { error } = await supabase.rpc("valider_facture", { p_facture: id });
      if (error) throw error;
    },
    onSuccess: () => {
      toast.success("Facture validée. L'envoi est lancé.");
      setConfirmer(false);
      recharger();
    },
    onError: (e) => toast.error(messageErreur(e)),
  });

  if (q.isLoading) return <p role="status">Chargement de la facture.</p>;
  if (q.error || !q.data)
    return (
      <div>
        <p role="alert" className="font-bold text-rose-text">
          {messageErreur(q.error)}
        </p>
        <Button variant="outline" onClick={onRetour}>
          Retour aux factures
        </Button>
      </div>
    );

  const { f, insc, lignes, avis, fiche, erreurControle } = q.data;
  const modifiable = !["validee", "envoyee"].includes(f.statut);
  const t = totaux(lignes);
  const aVoir = (fiche?.fiche_points ?? []).filter(
    (p) => p.etat !== "bon" || (p.constats ?? []).length > 0,
  );
  const ev = insc.evenements;

  return (
    <div className="space-y-5">
      <Button variant="outline" onClick={onRetour}>
        Retour aux factures
      </Button>
      <header className="rounded-xl bg-card p-4 shadow-sm">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <h2 className="text-2xl font-bold text-primary">
            {insc.prenom} {insc.nom}
          </h2>
          <Statut statut={f.statut} />
        </div>
        <p className="mt-1">{insc.email}</p>
        {ev && (
          <p className="mt-1 text-sm">
            {ev.entreprises?.nom}, {ev.site}, {dateLongue(ev.date_intervention)}
          </p>
        )}
        {f.prete_le && <p className="mt-1 text-sm">Préparée le {dateHeure(f.prete_le)}</p>}
        {f.validee_le && <p className="mt-1 text-sm">Validée le {dateHeure(f.validee_le)}</p>}
        {f.envoyee_le && <p className="mt-1 text-sm">Envoyée le {dateHeure(f.envoyee_le)}</p>}
        {f.statut === "echec" && f.detail && (
          <p className="mt-1 font-bold text-rose-text">{f.detail}</p>
        )}
      </header>

      <section aria-labelledby="titre-avis" className="space-y-2">
        <h3 id="titre-avis" className="text-lg font-bold">
          Avis de contrôle
        </h3>
        {erreurControle && (
          <p role="alert" className="font-bold text-rose-text">
            Contrôle impossible : {erreurControle}
          </p>
        )}
        {avis.length === 0 && !erreurControle && <p>Aucun avis.</p>}
        <ul className="space-y-2">
          {avis.map((a) => (
            <li
              key={a.id}
              className={
                "flex items-start gap-3 rounded-lg border-l-8 bg-card p-3 " +
                (a.niveau === "erreur"
                  ? "border-rose"
                  : a.niveau === "attention"
                    ? "border-warning"
                    : "border-success")
              }
            >
              {a.niveau === "erreur" ? (
                <XCircle aria-hidden className="mt-0.5 shrink-0 text-rose-text" />
              ) : a.niveau === "attention" ? (
                <AlertTriangle aria-hidden className="mt-0.5 shrink-0" />
              ) : (
                <CheckCircle2 aria-hidden className="mt-0.5 shrink-0 text-primary-text" />
              )}
              <span>
                <strong>
                  {a.niveau === "erreur"
                    ? "Erreur"
                    : a.niveau === "attention"
                      ? "Attention"
                      : "Correct"}
                </strong>
                {a.source === "ia" ? " (avis IA, consultatif)" : ""} : {a.message}
              </span>
            </li>
          ))}
        </ul>
      </section>

      <section
        aria-labelledby="titre-lignes"
        className="space-y-3 rounded-xl bg-card p-4 shadow-sm"
      >
        <h3 id="titre-lignes" className="text-lg font-bold">
          Lignes de la facture
        </h3>
        {lignes.length === 0 && <p>Aucune ligne.</p>}
        <ul className="space-y-3">
          {lignes.map((l) => (
            <LigneEditable key={l.id} l={l} modifiable={modifiable} exec={exec} />
          ))}
        </ul>
        {modifiable && (
          <Button
            variant="outline"
            className="w-full"
            onClick={() =>
              exec(
                supabase.from("facture_lignes").insert({
                  facture_id: id,
                  libelle: "Nouvelle ligne",
                  quantite: 1,
                  prix_unitaire_ht: 0,
                  taux_tva: 20,
                  ordre: lignes.length + 1,
                }),
              )
            }
          >
            <Plus aria-hidden /> Ajouter une ligne
          </Button>
        )}
        <dl className="grid grid-cols-2 gap-1 border-t pt-3 text-lg">
          <dt>Total HT</dt>
          <dd className="text-right font-bold">{euros(t.ht)}</dd>
          <dt>TVA</dt>
          <dd className="text-right">{euros(t.tva)}</dd>
          <dt>Total TTC</dt>
          <dd className="text-right font-bold">{euros(t.ttc)}</dd>
        </dl>
      </section>

      <section aria-labelledby="titre-points" className="rounded-xl bg-card p-4 shadow-sm">
        <h3 id="titre-points" className="text-lg font-bold">
          Points de la fiche à voir
        </h3>
        {aVoir.length === 0 ? (
          <p>Tous les points sont « Bon ».</p>
        ) : (
          <ul className="mt-2 list-disc space-y-1 pl-5">
            {aVoir.map((p) => (
              <li key={p.groupe + p.point}>
                {p.groupe}, {p.point} :{" "}
                {(p.constats ?? []).length ? p.constats.join(", ") : ETAT_LABEL[p.etat]}
                {p.remarque ? ` (${p.remarque})` : ""}
              </li>
            ))}
          </ul>
        )}
        {fiche?.commentaire && (
          <p className="mt-2">
            <strong>Commentaire :</strong> {fiche.commentaire}
          </p>
        )}
      </section>

      {["a_preparer", "brouillon", "echec"].includes(f.statut) && (
        <Button
          size="lg"
          className="w-full"
          onClick={() =>
            exec(
              supabase
                .from("factures")
                .update({
                  statut: "a_valider",
                  prete_par: auth?.user?.id ?? null,
                  prete_le: new Date().toISOString(),
                })
                .eq("id", id),
            )
          }
        >
          Prête à valider
        </Button>
      )}

      {dirigeant && f.statut === "a_valider" && (
        <>
          <Button size="lg" className="w-full" onClick={() => setConfirmer(true)}>
            Valider et envoyer
          </Button>
          <AlertDialog open={confirmer} onOpenChange={setConfirmer}>
            <AlertDialogContent>
              <AlertDialogHeader>
                <AlertDialogTitle>Valider et envoyer la facture ?</AlertDialogTitle>
                <AlertDialogDescription>
                  Total TTC : {euros(t.ttc)}. Destinataire : {insc.prenom} {insc.nom} ({insc.email}
                  ). Démonstration : l'envoi part vers l'adresse du projet, jamais vers le client.
                </AlertDialogDescription>
              </AlertDialogHeader>
              <AlertDialogFooter>
                <AlertDialogCancel className="min-h-12">Annuler</AlertDialogCancel>
                <AlertDialogAction
                  className="min-h-12"
                  disabled={valider.isPending}
                  onClick={() => valider.mutate()}
                >
                  Valider et envoyer
                </AlertDialogAction>
              </AlertDialogFooter>
            </AlertDialogContent>
          </AlertDialog>
        </>
      )}
      {!dirigeant && f.statut === "a_valider" && (
        <p role="status">En attente de la validation du dirigeant.</p>
      )}
    </div>
  );
}

function LigneEditable({
  l,
  modifiable,
  exec,
}: {
  l: Ligne;
  modifiable: boolean;
  exec: (p: PromiseLike<{ error: unknown }>) => void;
}) {
  const [libelle, setLibelle] = useState(l.libelle);
  useEffect(() => setLibelle(l.libelle), [l.libelle]);
  const maj = (champ: Partial<Ligne>) =>
    exec(supabase.from("facture_lignes").update(champ).eq("id", l.id));
  return (
    <li className="space-y-2 rounded-lg border-2 p-3">
      <label className="block text-sm font-bold" htmlFor={`lib-${l.id}`}>
        Libellé
      </label>
      <Input
        id={`lib-${l.id}`}
        className="h-12"
        maxLength={200}
        disabled={!modifiable}
        value={libelle}
        onChange={(e) => setLibelle(e.target.value)}
        onBlur={() => libelle.trim() && libelle !== l.libelle && maj({ libelle: libelle.trim() })}
      />
      <div className="grid grid-cols-2 gap-2">
        <div>
          <label className="block text-sm font-bold" htmlFor={`qte-${l.id}`}>
            Quantité
          </label>
          <Input
            id={`qte-${l.id}`}
            type="number"
            inputMode="decimal"
            min="0.01"
            step="0.01"
            className="h-12"
            disabled={!modifiable}
            defaultValue={Number(l.quantite)}
            onBlur={(e) => {
              const v = Number(e.target.value);
              if (v > 0 && v !== Number(l.quantite)) maj({ quantite: v });
            }}
          />
        </div>
        <div>
          <label className="block text-sm font-bold" htmlFor={`pu-${l.id}`}>
            Prix unitaire HT
          </label>
          <Input
            id={`pu-${l.id}`}
            type="number"
            inputMode="decimal"
            min="0"
            step="0.01"
            className="h-12"
            disabled={!modifiable}
            defaultValue={Number(l.prix_unitaire_ht)}
            onBlur={(e) => {
              const v = Number(e.target.value);
              if (v >= 0 && v !== Number(l.prix_unitaire_ht)) maj({ prix_unitaire_ht: v });
            }}
          />
        </div>
      </div>
      <div className="flex items-center justify-between">
        <span>Montant HT : {euros(Number(l.quantite) * Number(l.prix_unitaire_ht))}</span>
        {modifiable && (
          <Button
            variant="ghost"
            aria-label={`Retirer la ligne ${l.libelle}`}
            onClick={() => exec(supabase.from("facture_lignes").delete().eq("id", l.id))}
          >
            <Trash2 aria-hidden /> Retirer
          </Button>
        )}
      </div>
    </li>
  );
}

function TableauDeBord() {
  const q = useQuery({
    queryKey: ["tableau"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("evenements")
        .select(
          "id, site, date_intervention, entreprises(nom), inscriptions(id, fiches(statut), factures(statut, facture_lignes(quantite, prix_unitaire_ht, taux_tva)))",
        )
        .order("date_intervention", { ascending: false });
      if (error) throw error;
      return data as unknown as {
        id: string;
        site: string;
        date_intervention: string;
        entreprises: { nom: string } | null;
        inscriptions: {
          id: string;
          fiches: { statut: string } | { statut: string }[] | null;
          factures:
            | {
                statut: string;
                facture_lignes: { quantite: number; prix_unitaire_ht: number; taux_tva: number }[];
              }
            | {
                statut: string;
                facture_lignes: { quantite: number; prix_unitaire_ht: number; taux_tva: number }[];
              }[]
            | null;
        }[];
      }[];
    },
  });
  if (q.isLoading) return <p role="status">Chargement du tableau de bord.</p>;
  if (q.error)
    return (
      <p role="alert" className="font-bold text-rose-text">
        {messageErreur(q.error)}
      </p>
    );
  const lignes = q.data ?? [];
  if (lignes.length === 0) return <p>Aucune journée pour le moment.</p>;
  const un = <T,>(x: T | T[] | null): T | null => (Array.isArray(x) ? (x[0] ?? null) : x);

  return (
    <div className="overflow-x-auto rounded-xl bg-card shadow-sm">
      <table className="w-full text-left">
        <caption className="sr-only">Tableau de bord par entreprise, site et date</caption>
        <thead>
          <tr className="border-b">
            <th scope="col" className="p-3">
              Journée
            </th>
            <th scope="col" className="p-3 text-right">
              Inscrits
            </th>
            <th scope="col" className="p-3 text-right">
              Fiches terminées
            </th>
            <th scope="col" className="p-3 text-right">
              Factures validées
            </th>
            <th scope="col" className="p-3 text-right">
              Factures envoyées
            </th>
            <th scope="col" className="p-3 text-right">
              Total HT
            </th>
          </tr>
        </thead>
        <tbody>
          {lignes.map((e) => {
            let fiches = 0;
            let validees = 0;
            let envoyees = 0;
            let ht = 0;
            for (const i of e.inscriptions) {
              if (un(i.fiches)?.statut === "terminee") fiches++;
              const fac = un(i.factures);
              if (fac) {
                if (fac.statut === "validee" || fac.statut === "envoyee") validees++;
                if (fac.statut === "envoyee") envoyees++;
                ht += totaux(fac.facture_lignes ?? []).ht;
              }
            }
            return (
              <tr key={e.id} className="border-b last:border-0">
                <th scope="row" className="p-3 font-normal">
                  <strong>{e.entreprises?.nom}</strong>
                  <br />
                  {e.site}, {dateLongue(e.date_intervention)}
                </th>
                <td className="p-3 text-right">{e.inscriptions.length}</td>
                <td className="p-3 text-right">{fiches}</td>
                <td className="p-3 text-right">{validees}</td>
                <td className="p-3 text-right">{envoyees}</td>
                <td className="p-3 text-right">{euros(ht)}</td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}
