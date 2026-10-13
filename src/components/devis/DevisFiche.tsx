import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";
import { messageErreur } from "@/lib/format";
import { STATUT_DEVIS, lireAvis } from "@/lib/devis";
import { Button } from "@/components/ui/button";
import { AvisDevis, LignesDevis, type PieceCatalogue } from "@/components/devis/LignesDevis";

/**
 * Bloc « Devis : réparations conseillées » de la fiche de maintenance (mécanicien ou dirigeant).
 * Les lignes conseillées vivent dans devis_lignes, jamais dans pieces_posees : terminer la fiche ne les facture pas.
 */
export function DevisFiche({
  ficheId,
  catalogue,
}: {
  ficheId: string;
  catalogue: PieceCatalogue[];
}) {
  const qc = useQueryClient();
  const cle = ["devis-fiche", ficheId];
  const q = useQuery({
    queryKey: cle,
    queryFn: async () => {
      const { data: devis, error } = await supabase
        .from("devis")
        .select("*")
        .eq("fiche_id", ficheId)
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle();
      if (error) throw error;
      if (!devis) return { devis: null, lignes: [], avis: [], erreurAvis: null as string | null };
      const [l, a] = await Promise.all([
        supabase
          .from("devis_lignes")
          .select("*")
          .eq("devis_id", devis.id)
          .order("ordre")
          .order("created_at"),
        supabase.rpc("devis_controles", { p_devis: devis.id }),
      ]);
      if (l.error) throw l.error;
      return {
        devis,
        lignes: l.data,
        avis: lireAvis(a.data),
        erreurAvis: a.error ? a.error.message : null,
      };
    },
  });
  const recharger = () => qc.invalidateQueries({ queryKey: cle });

  const creer = useMutation({
    mutationFn: async () => {
      const { error } = await supabase.from("devis").insert({ fiche_id: ficheId });
      if (error) throw error;
    },
    onSuccess: recharger,
    onError: (e) => toast.error(messageErreur(e)),
  });
  const proposer = useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase.rpc("devis_proposer", { p_devis: id });
      if (error) throw error;
    },
    onSuccess: () => {
      toast.success("Devis proposé : l'atelier le relit avant de l'envoyer au client.");
      recharger();
    },
    onError: (e) => toast.error(messageErreur(e)),
  });

  return (
    <section aria-labelledby="titre-devis" className="space-y-3 rounded-xl bg-card p-4 shadow-sm">
      <h2 id="titre-devis" className="text-xl font-bold">
        Devis : réparations conseillées
      </h2>
      <p className="text-sm">
        Ce qui est conseillé mais pas réparé aujourd'hui. Rien n'est facturé sans l'accord du
        client.
      </p>
      {q.isLoading && <p role="status">Chargement du devis.</p>}
      {q.error && (
        <p role="alert" className="font-bold text-rose-text">
          Devis illisible. {messageErreur(q.error)}
        </p>
      )}
      {q.data && !q.data.devis && (
        <Button
          variant="outline"
          className="w-full"
          disabled={creer.isPending}
          onClick={() => creer.mutate()}
        >
          Préparer un devis
        </Button>
      )}
      {q.data?.devis && (
        <>
          <p className="font-bold" role="status">
            {q.data.devis.reference} : {STATUT_DEVIS[q.data.devis.statut] ?? q.data.devis.statut}
          </p>
          <LignesDevis
            devisId={q.data.devis.id}
            lignes={q.data.lignes}
            catalogue={catalogue}
            lectureSeule={q.data.devis.statut !== "brouillon"}
            onChange={recharger}
          />
          {q.data.devis.statut === "brouillon" && (
            <>
              <AvisDevis avis={q.data.avis} erreur={q.data.erreurAvis} />
              <Button
                size="lg"
                className="w-full"
                disabled={proposer.isPending || q.data.lignes.length === 0}
                onClick={() => proposer.mutate(q.data!.devis!.id)}
              >
                Proposer le devis à l'atelier
              </Button>
            </>
          )}
        </>
      )}
    </section>
  );
}
