import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";
import { dateHeure, euros, messageErreur, totaux } from "@/lib/format";
import { STATUT_DEVIS, envoyerDevis, lireAvis, relancerReport } from "@/lib/devis";
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
import { AvisDevis, LignesDevis } from "@/components/devis/LignesDevis";

/** Onglet « Devis » du bureau : relecture par l'atelier ou le dirigeant avant tout envoi (contrôle demandé par le client). */
export function DevisBureau() {
  const [ouvert, setOuvert] = useState<string | null>(null);
  return ouvert ? (
    <DetailDevis id={ouvert} onRetour={() => setOuvert(null)} />
  ) : (
    <ListeDevis onOuvrir={setOuvert} />
  );
}

const ORDRE = ["a_relire", "brouillon", "envoye", "accepte", "refuse"];

function ListeDevis({ onOuvrir }: { onOuvrir: (id: string) => void }) {
  const q = useQuery({
    queryKey: ["devis-liste"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("devis")
        .select(
          "id, reference, statut, updated_at, devis_lignes(quantite, prix_unitaire_ht, taux_tva)",
        )
        .order("updated_at", { ascending: false })
        .limit(100);
      if (error) throw error;
      return data;
    },
  });
  if (q.isLoading) return <p role="status">Chargement des devis.</p>;
  if (q.error)
    return (
      <p role="alert" className="font-bold text-rose-text">
        Devis illisibles. {messageErreur(q.error)}
      </p>
    );
  const liste = [...(q.data ?? [])].sort(
    (a, b) => ORDRE.indexOf(a.statut) - ORDRE.indexOf(b.statut),
  );
  if (!liste.length)
    return <p>Aucun devis pour l'instant. Les devis se préparent depuis la fiche du vélo.</p>;
  return (
    <ul className="space-y-2">
      {liste.map((d) => {
        const t = totaux(
          (d.devis_lignes ?? []) as {
            quantite: number;
            prix_unitaire_ht: number;
            taux_tva: number;
          }[],
        );
        return (
          <li key={d.id}>
            <button
              type="button"
              onClick={() => onOuvrir(d.id)}
              className="tap flex w-full items-center justify-between gap-3 rounded-xl bg-card p-4 text-left shadow-sm"
            >
              <span>
                <span className="block font-bold">{d.reference}</span>
                <span className="text-sm">{euros(t.ttc)} TTC</span>
              </span>
              <span
                className={
                  "rounded-full px-3 py-1 text-sm font-bold " +
                  (d.statut === "a_relire"
                    ? "bg-rose text-white"
                    : d.statut === "accepte"
                      ? "bg-primary text-primary-foreground"
                      : "bg-accent text-accent-foreground")
                }
              >
                {STATUT_DEVIS[d.statut] ?? d.statut}
              </span>
            </button>
          </li>
        );
      })}
    </ul>
  );
}

function DetailDevis({ id, onRetour }: { id: string; onRetour: () => void }) {
  const qc = useQueryClient();
  const [confirmer, setConfirmer] = useState(false);
  const cle = ["devis-detail", id];
  const q = useQuery({
    queryKey: cle,
    queryFn: async () => {
      const [d, l, c, a] = await Promise.all([
        supabase.from("devis").select("*").eq("id", id).single(),
        supabase
          .from("devis_lignes")
          .select("*")
          .eq("devis_id", id)
          .order("ordre")
          .order("created_at"),
        supabase.from("pieces_catalogue").select("*").eq("actif", true).order("libelle"),
        supabase.rpc("devis_controles", { p_devis: id }),
      ]);
      if (d.error) throw d.error;
      if (l.error) throw l.error;
      if (c.error) throw c.error;
      return {
        devis: d.data,
        lignes: l.data,
        catalogue: c.data,
        avis: lireAvis(a.data),
        erreurAvis: a.error ? a.error.message : null,
      };
    },
  });
  const recharger = () => {
    qc.invalidateQueries({ queryKey: cle });
    qc.invalidateQueries({ queryKey: ["devis-liste"] });
  };
  const reprendre = useMutation({
    mutationFn: async () => {
      const { error } = await supabase.rpc("devis_reprendre", { p_devis: id });
      if (error) throw error;
    },
    onSuccess: () => {
      toast.success("Devis repris en brouillon : il peut être corrigé puis renvoyé.");
      recharger();
    },
    onError: (e) => toast.error(messageErreur(e)),
  });
  const report = useMutation({
    mutationFn: async () => {
      const r = await relancerReport(id);
      if (!r.ok) throw new Error(r.erreur || "Report impossible.");
    },
    onSuccess: () => {
      toast.success("Décision du client reportée dans Axonaut.");
      recharger();
    },
    onError: (e) => {
      toast.error(messageErreur(e));
      recharger();
    },
  });
  const envoi = useMutation({
    mutationFn: async () => {
      const r = await envoyerDevis(id);
      if (!r.ok) throw new Error(r.erreur || "Envoi impossible.");
      return r;
    },
    onSuccess: (r) => {
      toast.success(
        `Devis créé dans Axonaut${r.numero ? ` (${r.numero})` : ""} et envoyé au client.`,
      );
      if (r.erreur) toast.warning(r.erreur);
      recharger();
    },
    onError: (e) => {
      toast.error(messageErreur(e));
      recharger();
    },
  });

  if (q.isLoading) return <p role="status">Chargement du devis.</p>;
  if (q.error || !q.data)
    return (
      <p role="alert" className="font-bold text-rose-text">
        Devis introuvable. {messageErreur(q.error)}
      </p>
    );
  const { devis: d, lignes, catalogue, avis, erreurAvis } = q.data;
  const t = totaux(lignes);
  const bloque = avis.some((a) => a.niveau === "erreur");
  const lien = d.jeton
    ? `${typeof window !== "undefined" ? window.location.origin : ""}/devis/${d.jeton}`
    : null;

  return (
    <div className="space-y-5">
      <Button variant="outline" onClick={onRetour}>
        Retour aux devis
      </Button>
      <header className="rounded-xl bg-card p-4 shadow-sm">
        <h2 className="text-2xl font-bold text-primary">{d.reference}</h2>
        <p className="mt-1 font-bold">{STATUT_DEVIS[d.statut] ?? d.statut}</p>
        {d.propose_le && <p className="mt-1 text-sm">Proposé le {dateHeure(d.propose_le)}</p>}
        {d.envoye_le && <p className="mt-1 text-sm">Envoyé le {dateHeure(d.envoye_le)}</p>}
        {d.decide_le && (
          <p className="mt-1 text-sm">Réponse du client le {dateHeure(d.decide_le)}</p>
        )}
        {d.axonaut_numero && <p className="mt-1 text-sm">Devis Axonaut {d.axonaut_numero}</p>}
        {d.derniere_erreur && <p className="mt-1 font-bold text-rose-text">{d.derniere_erreur}</p>}
      </header>

      <section aria-label="Lignes du devis" className="rounded-xl bg-card p-4 shadow-sm">
        <LignesDevis
          devisId={d.id}
          lignes={lignes}
          catalogue={catalogue}
          lectureSeule={d.statut !== "a_relire" || !!d.jeton}
          onChange={recharger}
        />
      </section>

      {d.statut === "a_relire" && (
        <>
          <AvisDevis avis={avis} erreur={erreurAvis} />
          <Button
            size="lg"
            className="w-full"
            disabled={bloque || envoi.isPending}
            onClick={() => setConfirmer(true)}
          >
            {envoi.isPending ? "Envoi en cours" : "Valider et envoyer au client"}
          </Button>
        </>
      )}

      {d.statut === "a_relire" && !!d.jeton && !!d.derniere_erreur && (
        <Button
          variant="outline"
          className="w-full"
          disabled={reprendre.isPending}
          onClick={() => reprendre.mutate()}
        >
          Reprendre en brouillon pour corriger
        </Button>
      )}

      {(d.statut === "accepte" || d.statut === "refuse") && !d.axonaut_decision_le && (
        <section className="space-y-2 rounded-xl bg-card p-4 shadow-sm">
          <p className="font-bold text-rose-text">
            La réponse du client n'est pas encore reportée dans Axonaut.
          </p>
          <Button className="w-full" disabled={report.isPending} onClick={() => report.mutate()}>
            Reporter dans Axonaut
          </Button>
        </section>
      )}

      {lien && d.statut !== "a_relire" && (
        <section className="space-y-2 rounded-xl bg-card p-4 shadow-sm">
          <h3 className="text-lg font-bold">Réponse du client</h3>
          <p>
            Montrez cette page au client sur le téléphone ou la tablette, ou laissez-le répondre
            depuis le mail.
          </p>
          <a
            href={lien}
            target="_blank"
            rel="noreferrer"
            className="tap inline-flex font-bold text-primary-text underline"
          >
            Ouvrir la page « J'accepte ou je refuse »
          </a>
        </section>
      )}

      <AlertDialog open={confirmer} onOpenChange={setConfirmer}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Envoyer le devis au client ?</AlertDialogTitle>
            <AlertDialogDescription>
              Le devis {d.reference} ({euros(t.ttc)} TTC) sera créé dans Axonaut et envoyé par mail.
              Il ne pourra plus être modifié.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel className="min-h-12">Annuler</AlertDialogCancel>
            <AlertDialogAction
              className="min-h-12"
              onClick={() => {
                setConfirmer(false);
                envoi.mutate();
              }}
            >
              Envoyer
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}
