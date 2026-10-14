import { createFileRoute } from "@tanstack/react-router";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";
import { requireRoles } from "@/lib/auth";
import { dateHeure, dateLongue, messageErreur, quantiteFr } from "@/lib/format";
import { Label } from "@/components/ui/label";
import { ETAT_DEVIS_PIECE, dateDevis, lireEtatStock } from "@/lib/commandes";
import { libelleStock } from "@/lib/stock";

// Lot L1 : pièces marquées « à commander » sur les fiches terminées, par journée, avec la case « commandée ».
// V4 (agent V4, 2026-10-14) : s'y ajoutent les pièces des devis reliées au catalogue (stock « À commander » ou « Stock inconnu »),
// avec leur provenance et la case « retirée de la liste » ; une seule ligne par pièce et par vélo (règle de commandes_devis_source).
// L'écran ne dépend pas des workflows v4 ; seule la mention du rappel de 15 h attend la bascule (verrou v4_bascule).
export const Route = createFileRoute("/commandes")({
  ssr: false,
  beforeLoad: requireRoles(["dirigeant", "atelier"]),
  head: () => ({
    meta: [
      { title: "À commander | Tournée Cycles" },
      { name: "description", content: "Pièces à commander, par journée." },
      { property: "og:title", content: "À commander | Tournée Cycles" },
      { property: "og:description", content: "Pièces à commander, par journée." },
    ],
  }),
  component: Commandes,
});

type Journee = {
  evenement_id: string;
  date_intervention: string;
  entreprise: string;
  site: string;
  nb_pieces: number;
  nb_a_commander: number;
};

type Piece = {
  source: "fiche" | "devis";
  id: string;
  fiche_reference: string | null;
  client: string;
  libelle: string;
  reference: string | null;
  quantite: number;
  commandee: boolean;
  retiree: boolean;
  devis_reference: string | null;
  etat_devis: string | null;
  etat_stock: string | null;
  modifie_le: string | null;
  devis_date?: string | null;
};

function Commandes() {
  const [choix, setChoix] = useState<string | null>(null);
  const journees = useQuery({
    queryKey: ["commandes", "journees"],
    queryFn: async () => {
      const { data, error } = await supabase.rpc("commandes_v4_journees");
      if (error) throw error;
      return (data ?? []) as unknown as Journee[];
    },
  });
  // Verrou d'affichage V4 : fermé (ou illisible) = la mention du rappel des pièces de devis reste masquée.
  const v4 = useQuery({
    queryKey: ["v4_bascule"],
    queryFn: async () => {
      const { data, error } = await supabase.rpc("v4_bascule_etat");
      if (error) return false;
      return data === true;
    },
  });
  const liste = journees.data ?? [];
  const parDefaut = liste.find((j) => j.nb_a_commander > 0) ?? liste[0];
  const actif = choix ?? parDefaut?.evenement_id ?? null;

  return (
    <div className="space-y-5">
      <h1 className="text-3xl font-bold text-primary">À commander</h1>
      <p>
        Pièces notées « à commander » sur les fiches terminées, et pièces des devis qui ne sont pas
        en stock. Cochez une pièce de fiche quand elle est commandée ; retirez une pièce de devis de
        la liste si elle n'est plus à commander.
      </p>
      {v4.data === true && (
        <p className="text-sm">Le rappel de 15 h reprend aussi les pièces des devis non refusés.</p>
      )}
      {journees.isLoading && <p role="status">Chargement.</p>}
      {journees.error && (
        <p role="alert" className="font-bold text-rose-text">
          {messageErreur(journees.error)}
        </p>
      )}
      {!journees.isLoading && !journees.error && liste.length === 0 && (
        <p>Aucune pièce à commander pour le moment.</p>
      )}
      {liste.length > 0 && (
        <div>
          <Label htmlFor="choix-journee-commandes">Journée</Label>
          <select
            id="choix-journee-commandes"
            className="mt-1 h-12 w-full rounded-lg border-2 border-input bg-card px-3 text-base"
            value={actif ?? ""}
            onChange={(e) => setChoix(e.target.value)}
          >
            {liste.map((j) => (
              <option key={j.evenement_id} value={j.evenement_id}>
                {dateLongue(j.date_intervention)}, {j.entreprise}, {j.site} :{" "}
                {j.nb_a_commander === 0 ? "tout est commandé" : `${j.nb_a_commander} à commander`}
              </option>
            ))}
          </select>
        </div>
      )}
      {actif && <PiecesJournee evenementId={actif} />}
    </div>
  );
}

function PiecesJournee({ evenementId }: { evenementId: string }) {
  const qc = useQueryClient();
  const pieces = useQuery({
    queryKey: ["commandes", "journee", evenementId],
    queryFn: async () => {
      const { data, error } = await supabase.rpc("commandes_v4_journee", {
        p_evenement: evenementId,
      });
      if (error) throw error;
      return (data ?? []) as unknown as Piece[];
    },
  });
  const marquer = useMutation({
    mutationFn: async (v: { id: string; commandee: boolean }) => {
      const { error } = await supabase.rpc("commandes_pieces_marquer", {
        p_piece: v.id,
        p_commandee: v.commandee,
      });
      if (error) throw error;
    },
    onSuccess: (_d, v) => {
      toast.success(v.commandee ? "Pièce notée commandée." : "Pièce de nouveau à commander.");
      qc.invalidateQueries({ queryKey: ["commandes"] });
    },
    onError: (e) => toast.error(messageErreur(e)),
  });
  const retirer = useMutation({
    mutationFn: async (v: { id: string; retiree: boolean }) => {
      const { error } = await supabase.rpc("devis_piece_retirer", {
        p_ligne: v.id,
        p_retiree: v.retiree,
      });
      if (error) throw error;
    },
    onSuccess: (_d, v) => {
      toast.success(v.retiree ? "Pièce retirée de la liste." : "Pièce remise dans la liste.");
      qc.invalidateQueries({ queryKey: ["commandes"] });
    },
    onError: (e) => toast.error(messageErreur(e)),
  });

  if (pieces.isLoading) return <p role="status">Chargement des pièces.</p>;
  if (pieces.error)
    return (
      <p role="alert" className="font-bold text-rose-text">
        {messageErreur(pieces.error)}
      </p>
    );
  const liste = pieces.data ?? [];
  if (liste.length === 0) return <p>Aucune pièce à commander pour cette journée.</p>;

  return (
    <ul className="space-y-3" aria-label="Pièces à commander">
      {liste.map((p) =>
        p.source === "devis" ? (
          <LigneDevisACommander
            key={`d-${p.id}`}
            p={p}
            occupe={retirer.isPending}
            onRetirer={(retiree) => retirer.mutate({ id: p.id, retiree })}
          />
        ) : (
          <li key={`f-${p.id}`} className="rounded-lg border-2 bg-card p-3">
            <label
              htmlFor={`cmd-${p.id}`}
              className="flex min-h-12 cursor-pointer items-start gap-3"
            >
              <input
                id={`cmd-${p.id}`}
                type="checkbox"
                className="mt-1 size-7 shrink-0 accent-primary"
                checked={p.commandee}
                disabled={marquer.isPending}
                onChange={(e) => marquer.mutate({ id: p.id, commandee: e.target.checked })}
              />
              <span className="flex-1">
                <span className="block text-lg font-bold">
                  {p.libelle}
                  {p.reference ? ` (${p.reference})` : ""} : {quantiteFr(p.quantite)}
                </span>
                <span className="block text-sm">
                  Fiche {p.fiche_reference}, {p.client}
                </span>
                <span className="block text-sm font-bold">
                  {p.commandee
                    ? `Commandée${p.modifie_le ? `, notée le ${dateHeure(p.modifie_le)}` : ""}`
                    : "À commander"}
                </span>
              </span>
            </label>
          </li>
        ),
      )}
    </ul>
  );
}

/** Pièce d'un devis : provenance (numéro et état du devis), stock, case « retirée de la liste ». */
function LigneDevisACommander({
  p,
  occupe,
  onRetirer,
}: {
  p: Piece;
  occupe: boolean;
  onRetirer: (retiree: boolean) => void;
}) {
  const id = `cmd-devis-${p.id}`;
  const refuse = p.etat_devis === "refuse";
  return (
    <li className={"rounded-lg border-2 bg-card p-3" + (refuse || p.retiree ? " opacity-70" : "")}>
      <label htmlFor={id} className="flex min-h-12 cursor-pointer items-start gap-3">
        <input
          id={id}
          type="checkbox"
          className="mt-1 size-7 shrink-0 accent-primary"
          checked={p.retiree}
          disabled={occupe}
          onChange={(e) => onRetirer(e.target.checked)}
        />
        <span className="flex-1">
          <span className="block text-lg font-bold">
            {p.libelle}
            {p.reference ? ` (${p.reference})` : ""} : {quantiteFr(p.quantite)}
          </span>
          <span className="block text-sm">
            Devis {p.devis_reference}, {ETAT_DEVIS_PIECE[p.etat_devis ?? ""] ?? "en attente"}
            {dateDevis(p.devis_date) ? `, du ${dateDevis(p.devis_date)}` : ""}
            {p.fiche_reference ? `, fiche ${p.fiche_reference}` : ""}, {p.client}
          </span>
          <span className="block text-sm font-bold">
            {p.retiree
              ? "Retirée de la liste"
              : refuse
                ? "Devis refusé : pièce jamais rappelée"
                : libelleStock[lireEtatStock(p.etat_stock)]}
          </span>
          <span className="block text-sm">Cocher pour retirer de la liste</span>
        </span>
      </label>
    </li>
  );
}
