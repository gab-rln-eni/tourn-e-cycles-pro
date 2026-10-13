import { createFileRoute } from "@tanstack/react-router";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { Check, X } from "lucide-react";
import { lireDevisPublicServeur, repondreDevisServeur } from "@/lib/devis";
import { dateHeure, euros, messageErreur } from "@/lib/format";
import { Button } from "@/components/ui/button";
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

// Page du cycliste : le devis montré sur le téléphone ou la tablette de l'atelier, ou ouvert depuis le mail.
// Aucun compte, aucune donnée personnelle : le lien porte un jeton aléatoire de 64 caractères.
export const Route = createFileRoute("/devis/$jeton")({
  ssr: false,
  head: () => ({
    meta: [
      { title: "Votre devis | Tournée Cycles" },
      { name: "description", content: "Devis des réparations conseillées par Tournée Cycles." },
      { name: "robots", content: "noindex" },
    ],
  }),
  component: PageDevis,
});

function PageDevis() {
  const { jeton } = Route.useParams();
  const qc = useQueryClient();
  const [demande, setDemande] = useState<"accepte" | "refuse" | null>(null);
  const q = useQuery({
    queryKey: ["devis-public", jeton],
    queryFn: async () => (await lireDevisPublicServeur({ data: { jeton } })).devis,
  });
  const m = useMutation({
    mutationFn: async (decision: "accepte" | "refuse") => {
      const r = await repondreDevisServeur({ data: { jeton, decision } });
      if (!r.ok) throw new Error(r.erreur || "Réponse non enregistrée.");
      return r;
    },
    onSettled: () => qc.invalidateQueries({ queryKey: ["devis-public", jeton] }),
  });

  if (q.isLoading) return <p role="status">Chargement du devis.</p>;
  if (q.error)
    return (
      <p role="alert" className="font-bold text-rose-text">
        Le devis ne peut pas être affiché. {messageErreur(q.error)}
      </p>
    );
  const d = q.data;
  if (!d)
    return (
      <div className="rounded-xl bg-card p-4 shadow-sm">
        <h1 className="text-2xl font-bold text-primary">Devis introuvable</h1>
        <p className="mt-2">
          Ce lien n'est pas valable. Demandez un nouveau lien à Tournée Cycles.
        </p>
      </div>
    );

  const repondu = d.statut === "accepte" || d.statut === "refuse";
  return (
    <div className="space-y-5">
      <header className="rounded-xl bg-card p-4 shadow-sm">
        <h1 className="text-2xl font-bold text-primary">Votre devis {d.reference}</h1>
        <p className="mt-1">Réparations conseillées lors du passage de Tournée Cycles.</p>
        {d.envoye_le && <p className="mt-1 text-sm">Proposé le {dateHeure(d.envoye_le)}</p>}
      </header>

      <section aria-labelledby="titre-lignes" className="rounded-xl bg-card p-4 shadow-sm">
        <h2 id="titre-lignes" className="text-xl font-bold">
          Ce que nous vous conseillons
        </h2>
        <ul className="mt-3 space-y-2">
          {d.lignes.map((l, i) => (
            <li key={i} className="flex items-start justify-between gap-3 border-b pb-2">
              <span>
                {l.libelle}
                {Number(l.quantite) !== 1 && (
                  <span className="text-sm">
                    {" "}
                    (quantité {String(l.quantite).replace(".", ",")})
                  </span>
                )}
              </span>
              <span className="whitespace-nowrap font-bold">
                {euros(Number(l.quantite) * Number(l.prix_unitaire_ht))} HT
              </span>
            </li>
          ))}
        </ul>
        <dl className="mt-3 space-y-1">
          <div className="flex justify-between">
            <dt>Total HT</dt>
            <dd>{euros(Number(d.total_ht))}</dd>
          </div>
          <div className="flex justify-between">
            <dt>TVA</dt>
            <dd>{euros(Number(d.total_tva))}</dd>
          </div>
          <div className="flex justify-between text-xl font-bold">
            <dt>Total TTC</dt>
            <dd>{euros(Number(d.total_ttc))}</dd>
          </div>
        </dl>
        {d.commentaire && <p className="mt-3 rounded-lg bg-accent p-3">{d.commentaire}</p>}
      </section>

      {repondu ? (
        <p role="status" className="rounded-xl bg-card p-4 text-lg font-bold shadow-sm">
          {d.statut === "accepte"
            ? "Merci, vous avez accepté ce devis. Tournée Cycles revient vers vous pour la réparation."
            : "Vous avez refusé ce devis. Merci pour votre réponse."}
          {d.decide_le && (
            <span className="block text-sm font-normal">Réponse du {dateHeure(d.decide_le)}</span>
          )}
        </p>
      ) : (
        <div className="grid gap-3 sm:grid-cols-2">
          <Button
            size="lg"
            className="min-h-14 text-lg"
            onClick={() => setDemande("accepte")}
            disabled={m.isPending}
          >
            <Check aria-hidden /> J'accepte
          </Button>
          <Button
            size="lg"
            variant="outline"
            className="min-h-14 text-lg"
            onClick={() => setDemande("refuse")}
            disabled={m.isPending}
          >
            <X aria-hidden /> Je refuse
          </Button>
        </div>
      )}
      {m.error && (
        <p role="alert" className="font-bold text-rose-text">
          {messageErreur(m.error)}
        </p>
      )}

      <AlertDialog open={demande !== null} onOpenChange={(o) => !o && setDemande(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>
              {demande === "accepte" ? "Accepter le devis ?" : "Refuser le devis ?"}
            </AlertDialogTitle>
            <AlertDialogDescription>
              {demande === "accepte"
                ? `Vous acceptez le devis ${d.reference} pour ${euros(Number(d.total_ttc))} TTC.`
                : `Vous refusez le devis ${d.reference}.`}{" "}
              Votre réponse ne pourra plus être modifiée.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel className="min-h-12">Revenir</AlertDialogCancel>
            <AlertDialogAction
              className="min-h-12"
              disabled={m.isPending}
              onClick={() => {
                if (demande) m.mutate(demande);
                setDemande(null);
              }}
            >
              {demande === "accepte" ? "Oui, j'accepte" : "Oui, je refuse"}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}
