import { useEffect, useState } from "react";
import { toast } from "sonner";
import { AlertTriangle, CheckCircle2, Minus, Plus, Trash2, XCircle } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { euros, messageErreur, totaux } from "@/lib/format";
import type { Avis } from "@/lib/devis";
import { etatPiece, libelleStock, lireStockPieces, type EtatStock } from "@/lib/stock";
import { lireEtatsLignesDevis, type EtatLigneDevis } from "@/lib/commandes";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

export type LigneDevis = {
  id: string;
  piece_id: string | null;
  libelle: string;
  quantite: number;
  prix_unitaire_ht: number;
  taux_tva: number;
  ordre: number;
};
export type PieceCatalogue = {
  id: string;
  reference: string;
  libelle: string;
  prix_vente_ht: number;
  taux_tva?: number;
};

/** Lignes conseillées d'un devis : quantité, prix, retrait, ajout depuis le catalogue ou en ligne libre. */
export function LignesDevis({
  devisId,
  lignes,
  catalogue,
  lectureSeule,
  onChange,
}: {
  devisId: string;
  lignes: LigneDevis[];
  catalogue: PieceCatalogue[];
  lectureSeule: boolean;
  onChange: () => void;
}) {
  const [recherche, setRecherche] = useState("");
  const [libre, setLibre] = useState("");
  const trouvees = recherche.trim()
    ? catalogue.filter((c) =>
        `${c.reference} ${c.libelle}`.toLowerCase().includes(recherche.trim().toLowerCase()),
      )
    : [];
  // Stock de chaque pièce du catalogue (agent STOCK) ; en cas d'échec, « Stock inconnu », jamais bloquant.
  const [stock, setStock] = useState<Map<string, EtatStock>>(new Map());
  useEffect(() => {
    let actif = true;
    void supabase.rpc("stock_pieces").then(({ data, error }) => {
      if (actif && !error) setStock(lireStockPieces(data));
    });
    return () => {
      actif = false;
    };
  }, []);
  // Liste « À commander » (V4) : état de chaque ligne reliée au catalogue ; en cas d'échec, aucune case, jamais bloquant.
  const [etats, setEtats] = useState<Map<string, EtatLigneDevis>>(new Map());
  const [relire, setRelire] = useState(0);
  const cleLignes = lignes.map((l) => `${l.id}:${l.piece_id ?? ""}`).join(",");
  useEffect(() => {
    let actif = true;
    void supabase.rpc("devis_pieces_etat", { p_devis: devisId }).then(({ data, error }) => {
      if (actif && !error) setEtats(lireEtatsLignesDevis(data));
    });
    return () => {
      actif = false;
    };
  }, [devisId, cleLignes, relire]);
  async function retirer(ligneId: string, retiree: boolean) {
    const { error } = await supabase.rpc("devis_piece_retirer", {
      p_ligne: ligneId,
      p_retiree: retiree,
    });
    if (error) toast.error(`Non enregistré : ${messageErreur(error)}`);
    else
      toast.success(
        retiree
          ? "Pièce retirée de la liste À commander."
          : "Pièce remise dans la liste À commander.",
      );
    setRelire((n) => n + 1);
  }
  const ordreSuivant = lignes.reduce((m, l) => Math.max(m, l.ordre), 0) + 1;

  async function exec(p: PromiseLike<{ error: unknown }>) {
    const { error } = await p;
    if (error) toast.error(`Non enregistré : ${messageErreur(error)}`);
    onChange();
  }
  const t = totaux(lignes);

  return (
    <div className="space-y-3">
      {lignes.length === 0 && <p>Aucune réparation conseillée pour l'instant.</p>}
      <ul className="space-y-3">
        {lignes.map((l) => (
          <li key={l.id} className="rounded-lg border-2 p-3">
            <p className="font-bold">{l.libelle}</p>
            {l.piece_id && <EtiquetteStock etat={etatPiece(stock, l.piece_id)} />}
            {etats.has(l.id) && (
              <CaseACommander ligneId={l.id} etat={etats.get(l.id)!} onRetirer={retirer} />
            )}
            <div className="mt-2 flex flex-wrap items-center gap-2">
              <Button
                size="icon"
                variant="outline"
                aria-label={`Retirer une unité de ${l.libelle}`}
                disabled={lectureSeule || Number(l.quantite) <= 1}
                onClick={() =>
                  exec(
                    supabase
                      .from("devis_lignes")
                      .update({ quantite: Number(l.quantite) - 1 })
                      .eq("id", l.id),
                  )
                }
              >
                <Minus aria-hidden />
              </Button>
              <span className="min-w-10 text-center text-lg font-bold" aria-label="Quantité">
                {Number(l.quantite)}
              </span>
              <Button
                size="icon"
                variant="outline"
                aria-label={`Ajouter une unité de ${l.libelle}`}
                disabled={lectureSeule}
                onClick={() =>
                  exec(
                    supabase
                      .from("devis_lignes")
                      .update({ quantite: Number(l.quantite) + 1 })
                      .eq("id", l.id),
                  )
                }
              >
                <Plus aria-hidden />
              </Button>
              <Label htmlFor={`devis-prix-${l.id}`} className="ml-2">
                Prix HT
              </Label>
              <Input
                id={`devis-prix-${l.id}`}
                type="number"
                inputMode="decimal"
                step="0.01"
                min="0"
                className="h-12 w-28"
                disabled={lectureSeule}
                defaultValue={Number(l.prix_unitaire_ht)}
                onBlur={(e) => {
                  const v = Number(e.target.value);
                  if (!Number.isNaN(v) && v >= 0 && v !== Number(l.prix_unitaire_ht))
                    exec(
                      supabase.from("devis_lignes").update({ prix_unitaire_ht: v }).eq("id", l.id),
                    );
                }}
              />
              {!lectureSeule && (
                <Button
                  variant="ghost"
                  aria-label={`Supprimer ${l.libelle}`}
                  onClick={() => exec(supabase.from("devis_lignes").delete().eq("id", l.id))}
                >
                  <Trash2 aria-hidden /> Retirer
                </Button>
              )}
            </div>
          </li>
        ))}
      </ul>
      <p className="font-bold">
        Total : {euros(t.ht)} HT, {euros(t.ttc)} TTC
      </p>

      {!lectureSeule && (
        <div className="space-y-3 border-t pt-3">
          <Label htmlFor={`devis-recherche-${devisId}`}>
            Ajouter une pièce du catalogue (référence ou libellé)
          </Label>
          <Input
            id={`devis-recherche-${devisId}`}
            className="h-12"
            value={recherche}
            onChange={(e) => setRecherche(e.target.value)}
            autoComplete="off"
          />
          {trouvees.length > 0 && (
            <ul className="space-y-2">
              {trouvees.slice(0, 8).map((c) => (
                <li key={c.id}>
                  <Button
                    variant="outline"
                    className="w-full justify-between"
                    onClick={() => {
                      setRecherche("");
                      exec(
                        supabase.from("devis_lignes").insert({
                          devis_id: devisId,
                          piece_id: c.id,
                          libelle: c.libelle,
                          quantite: 1,
                          prix_unitaire_ht: Number(c.prix_vente_ht),
                          taux_tva: Number(c.taux_tva ?? 20),
                          ordre: ordreSuivant,
                        }),
                      );
                    }}
                  >
                    <span>
                      {c.libelle} <EtiquetteStock etat={etatPiece(stock, c.id)} />
                    </span>
                    <span>{euros(Number(c.prix_vente_ht))}</span>
                  </Button>
                </li>
              ))}
            </ul>
          )}
          {recherche.trim() && trouvees.length === 0 && <p>Aucune pièce trouvée.</p>}
          <Label htmlFor={`devis-libre-${devisId}`}>Ou une réparation libre</Label>
          <div className="flex gap-2">
            <Input
              id={`devis-libre-${devisId}`}
              className="h-12"
              maxLength={200}
              value={libre}
              onChange={(e) => setLibre(e.target.value)}
            />
            <Button
              disabled={!libre.trim()}
              onClick={() => {
                const l = libre.trim();
                setLibre("");
                exec(
                  supabase.from("devis_lignes").insert({
                    devis_id: devisId,
                    libelle: l,
                    quantite: 1,
                    prix_unitaire_ht: 0,
                    ordre: ordreSuivant,
                  }),
                );
              }}
            >
              Ajouter
            </Button>
          </div>
        </div>
      )}
    </div>
  );
}

/** Case de la liste « À commander » pour une pièce du devis qui n'est pas en stock (V4). */
function CaseACommander({
  ligneId,
  etat,
  onRetirer,
}: {
  ligneId: string;
  etat: EtatLigneDevis;
  onRetirer: (ligneId: string, retiree: boolean) => void;
}) {
  if (etat.doublon === "fiche")
    return <p className="mt-1 text-sm">Déjà dans la liste À commander par la fiche.</p>;
  if (etat.doublon === "devis")
    return <p className="mt-1 text-sm">Déjà dans la liste À commander par un autre devis.</p>;
  const id = `devis-a-commander-${ligneId}`;
  return (
    <label htmlFor={id} className="mt-2 flex min-h-12 cursor-pointer items-center gap-3">
      <input
        id={id}
        type="checkbox"
        className="size-7 shrink-0 accent-primary"
        checked={!etat.retiree}
        onChange={(e) => onRetirer(ligneId, !e.target.checked)}
      />
      <span>
        Dans la liste À commander
        {etat.etatDevis === "refuse" ? " (devis refusé : jamais rappelée)" : ""}
      </span>
    </label>
  );
}

/** Stock de la pièce lu dans Axonaut : en stock, à commander, ou inconnu (pièce non reliée ou lecture absente). */
function EtiquetteStock({ etat }: { etat: EtatStock }) {
  return (
    <span
      className={
        "ml-1 inline-block rounded px-2 py-0.5 text-sm font-normal " +
        (etat === "en_stock"
          ? "bg-success-soft"
          : etat === "a_commander"
            ? "bg-warning-soft"
            : "bg-muted")
      }
    >
      {libelleStock[etat]}
    </span>
  );
}

/** Avis des contrôles simples du devis (code classique, aucune IA). */
export function AvisDevis({ avis, erreur }: { avis: Avis[]; erreur?: string | null }) {
  return (
    <section aria-label="Contrôles du devis" className="space-y-2">
      {erreur && (
        <p role="alert" className="font-bold text-rose-text">
          Contrôle impossible : {erreur}
        </p>
      )}
      <ul className="space-y-2">
        {avis.map((a, i) => (
          <li
            key={i}
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
                  ? "À corriger"
                  : a.niveau === "attention"
                    ? "Attention"
                    : "Correct"}
              </strong>{" "}
              : {a.message}
            </span>
          </li>
        ))}
      </ul>
    </section>
  );
}
