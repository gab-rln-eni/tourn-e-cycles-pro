import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useMemo, useState } from "react";
import { toast } from "sonner";
import { Check, Minus, Plus, Trash2 } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { prevenirN8n } from "@/lib/declencher";
import { requireRoles } from "@/lib/auth";
import { GROUPES } from "@/lib/referentiel";
import { ETATS, PARTIE_LABEL, TYPE_VELO, dateLongue, euros, messageErreur } from "@/lib/format";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
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

export const Route = createFileRoute("/fiche/$inscriptionId")({
  ssr: false,
  beforeLoad: requireRoles(["dirigeant", "mecanicien"]),
  head: () => ({
    meta: [
      { title: "Fiche de maintenance | Tournée Cycles" },
      { name: "description", content: "Fiche de maintenance d'un vélo." },
    ],
  }),
  component: FichePage,
});

type Point = { etat: string; constats: string[]; remarque: string };
type Piece = {
  id: string;
  piece_id: string | null;
  libelle: string;
  quantite: number;
  prix_unitaire_ht: number;
  a_commander: boolean;
};

const cle = (g: string, p: string) => `${g}|${p}`;

function FichePage() {
  const { inscriptionId } = Route.useParams();
  const qc = useQueryClient();
  const navigate = useNavigate();

  const donnees = useQuery({
    queryKey: ["fiche", inscriptionId],
    queryFn: async () => {
      const { data: insc, error: e1 } = await supabase
        .from("inscriptions")
        .select("*, evenements(site, date_intervention, entreprises(nom))")
        .eq("id", inscriptionId)
        .single();
      if (e1) throw e1;
      let { data: fiche } = await supabase
        .from("fiches")
        .select("*")
        .eq("inscription_id", inscriptionId)
        .maybeSingle();
      if (!fiche) {
        const { data: cree, error: e2 } = await supabase
          .from("fiches")
          .insert({ inscription_id: inscriptionId })
          .select("*")
          .single();
        if (e2) throw e2;
        fiche = cree;
      }
      const [pts, pcs, cat] = await Promise.all([
        supabase.from("fiche_points").select("*").eq("fiche_id", fiche.id),
        supabase.from("pieces_posees").select("*").eq("fiche_id", fiche.id).order("created_at"),
        supabase.from("pieces_catalogue").select("*").eq("actif", true).order("libelle"),
      ]);
      if (pts.error) throw pts.error;
      if (pcs.error) throw pcs.error;
      if (cat.error) throw cat.error;
      return { insc, fiche, points: pts.data, pieces: pcs.data, catalogue: cat.data };
    },
  });

  if (donnees.isLoading) return <p role="status">Chargement de la fiche.</p>;
  if (donnees.error || !donnees.data)
    return (
      <p role="alert" className="font-bold text-rose-text">
        Fiche introuvable. {messageErreur(donnees.error)}
      </p>
    );

  const { insc, fiche, points, pieces, catalogue } = donnees.data;
  const ev = insc.evenements as unknown as {
    site: string;
    date_intervention: string;
    entreprises: { nom: string } | null;
  } | null;
  const terminee = fiche.statut === "terminee";
  const recharger = () => qc.invalidateQueries({ queryKey: ["fiche", inscriptionId] });

  return (
    <div className="space-y-6">
      <Link
        to="/journee"
        className="tap inline-flex items-center font-bold text-primary-text underline"
      >
        Retour à la journée
      </Link>
      <header className="rounded-xl bg-card p-4 shadow-sm">
        <h1 className="text-2xl font-bold text-primary">
          {insc.prenom} {insc.nom}
        </h1>
        <p className="mt-1">
          {TYPE_VELO[insc.type_velo] ?? insc.type_velo}
          {insc.velo_modele ? `, ${insc.velo_modele}` : ""}
        </p>
        <p className="mt-1">
          <strong>Problème signalé :</strong>{" "}
          {PARTIE_LABEL[insc.partie_signalee] ?? insc.partie_signalee}
          {insc.probleme_percu ? `. ${insc.probleme_percu}` : ""}
        </p>
        {ev && (
          <p className="mt-1 text-sm">
            {ev.entreprises?.nom}, {ev.site}, {dateLongue(ev.date_intervention)}
          </p>
        )}
        <p className="mt-2 font-bold" role="status">
          {terminee ? "Fiche terminée" : "Fiche en cours"}
        </p>
      </header>

      <Organes ficheId={fiche.id} points={points} lectureSeule={terminee} onChange={recharger} />

      <Pieces
        ficheId={fiche.id}
        pieces={pieces}
        catalogue={catalogue}
        lectureSeule={terminee}
        onChange={recharger}
      />

      <Commentaire ficheId={fiche.id} initial={fiche.commentaire ?? ""} lectureSeule={terminee} />

      {!terminee && (
        <Terminer
          ficheId={fiche.id}
          onDone={async () => {
            await qc.invalidateQueries();
            navigate({ to: "/journee" });
          }}
        />
      )}
    </div>
  );
}

function Organes({
  ficheId,
  points,
  lectureSeule,
  onChange,
}: {
  ficheId: string;
  points: {
    groupe: string;
    point: string;
    etat: string;
    constats: string[];
    remarque: string | null;
  }[];
  lectureSeule: boolean;
  onChange: () => void;
}) {
  const initial = useMemo(() => {
    const m: Record<string, Point> = {};
    for (const p of points)
      m[cle(p.groupe, p.point)] = {
        etat: p.etat,
        constats: p.constats ?? [],
        remarque: p.remarque ?? "",
      };
    return m;
  }, [points]);
  const [etats, setEtats] = useState<Record<string, Point>>(initial);

  async function enregistrer(groupe: string, point: string, v: Point) {
    setEtats((s) => ({ ...s, [cle(groupe, point)]: v }));
    const neutre = v.etat === "bon" && v.constats.length === 0 && !v.remarque.trim();
    const res = neutre
      ? await supabase.from("fiche_points").delete().match({ fiche_id: ficheId, groupe, point })
      : await supabase.from("fiche_points").upsert(
          {
            fiche_id: ficheId,
            groupe,
            point,
            etat: v.etat,
            constats: v.constats,
            remarque: v.remarque.trim() || null,
          },
          { onConflict: "fiche_id,groupe,point" },
        );
    if (res.error) {
      toast.error(`Non enregistré : ${messageErreur(res.error)}`);
      onChange();
    }
  }

  async function toutBon(groupe: string) {
    const { error } = await supabase
      .from("fiche_points")
      .delete()
      .match({ fiche_id: ficheId, groupe });
    if (error) {
      toast.error(`Non enregistré : ${messageErreur(error)}`);
      return;
    }
    setEtats((s) =>
      Object.fromEntries(Object.entries(s).filter(([k]) => !k.startsWith(`${groupe}|`))),
    );
    toast.success(`${groupe} : tout est bon`);
  }

  return (
    <section aria-labelledby="titre-organes" className="space-y-3">
      <h2 id="titre-organes" className="text-xl font-bold">
        Contrôle du vélo
      </h2>
      {GROUPES.map((g) => {
        const nbSignales = g.points.filter((p) => {
          const v = etats[cle(g.nom, p.nom)];
          return v && (v.etat !== "bon" || v.constats.length > 0);
        }).length;
        return (
          <details key={g.nom} className="rounded-xl bg-card shadow-sm">
            <summary className="tap flex cursor-pointer items-center justify-between gap-2 p-4 text-lg font-bold">
              <span>{g.nom}</span>
              <span
                className={
                  nbSignales
                    ? "rounded-full bg-rose px-3 py-1 text-sm text-white"
                    : "text-sm text-primary-text"
                }
              >
                {nbSignales ? `${nbSignales} à voir` : "Bon"}
              </span>
            </summary>
            <div className="space-y-4 px-4 pb-4">
              {!lectureSeule && (
                <Button variant="outline" className="w-full" onClick={() => toutBon(g.nom)}>
                  <Check aria-hidden /> Tout est bon
                </Button>
              )}
              {g.points.map((p) => {
                const v = etats[cle(g.nom, p.nom)] ?? { etat: "bon", constats: [], remarque: "" };
                const id = `${g.nom}-${p.nom}`.replace(/[^a-zA-Z0-9]/g, "-");
                return (
                  <fieldset key={p.nom} className="border-t pt-3" disabled={lectureSeule}>
                    <legend className="font-bold">{p.nom}</legend>
                    {p.constats ? (
                      <div className="mt-2 grid grid-cols-2 gap-2">
                        {p.constats.map((c) => {
                          const coche = v.constats.includes(c);
                          return (
                            <label
                              key={c}
                              className="tap flex items-center gap-3 rounded-lg border-2 px-3 py-2"
                            >
                              <input
                                type="checkbox"
                                className="size-6"
                                checked={coche}
                                onChange={() =>
                                  enregistrer(g.nom, p.nom, {
                                    ...v,
                                    constats: coche
                                      ? v.constats.filter((x) => x !== c)
                                      : [...v.constats, c],
                                  })
                                }
                              />
                              {c}
                            </label>
                          );
                        })}
                      </div>
                    ) : (
                      <div className="mt-2 grid grid-cols-2 gap-2 sm:grid-cols-4">
                        {ETATS.map((e) => {
                          const actif = v.etat === e.value;
                          return (
                            <button
                              key={e.value}
                              type="button"
                              aria-pressed={actif}
                              onClick={() => enregistrer(g.nom, p.nom, { ...v, etat: e.value })}
                              className={
                                "tap flex items-center justify-center gap-2 rounded-lg border-2 px-2 py-2 font-bold " +
                                (actif
                                  ? e.value === "bon"
                                    ? "border-primary bg-primary text-primary-foreground"
                                    : "border-rose bg-rose text-white"
                                  : "border-border bg-card")
                              }
                            >
                              {actif && <Check aria-hidden />}
                              {e.label}
                            </button>
                          );
                        })}
                      </div>
                    )}
                    <Label htmlFor={id} className="mt-2 block text-sm">
                      Remarque (facultative)
                    </Label>
                    <Input
                      id={id}
                      maxLength={500}
                      className="h-12"
                      defaultValue={v.remarque}
                      onBlur={(ev) => {
                        if (ev.target.value !== v.remarque)
                          enregistrer(g.nom, p.nom, { ...v, remarque: ev.target.value });
                      }}
                    />
                  </fieldset>
                );
              })}
            </div>
          </details>
        );
      })}
    </section>
  );
}

function Pieces({
  ficheId,
  pieces,
  catalogue,
  lectureSeule,
  onChange,
}: {
  ficheId: string;
  pieces: Piece[];
  catalogue: { id: string; reference: string; libelle: string; prix_vente_ht: number }[];
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

  async function exec(p: PromiseLike<{ error: unknown }>) {
    const { error } = await p;
    if (error) toast.error(`Non enregistré : ${messageErreur(error)}`);
    onChange();
  }

  const total = pieces.reduce((s, p) => s + Number(p.quantite) * Number(p.prix_unitaire_ht), 0);

  return (
    <section aria-labelledby="titre-pieces" className="space-y-3 rounded-xl bg-card p-4 shadow-sm">
      <h2 id="titre-pieces" className="text-xl font-bold">
        Pièces posées
      </h2>
      {pieces.length === 0 && <p>Aucune pièce posée.</p>}
      <ul className="space-y-3">
        {pieces.map((p) => (
          <li key={p.id} className="rounded-lg border-2 p-3">
            <p className="font-bold">{p.libelle}</p>
            <div className="mt-2 flex flex-wrap items-center gap-2">
              <Button
                size="icon"
                variant="outline"
                aria-label={`Retirer une unité de ${p.libelle}`}
                disabled={lectureSeule || Number(p.quantite) <= 1}
                onClick={() =>
                  exec(
                    supabase
                      .from("pieces_posees")
                      .update({ quantite: Number(p.quantite) - 1 })
                      .eq("id", p.id),
                  )
                }
              >
                <Minus aria-hidden />
              </Button>
              <span className="min-w-10 text-center text-lg font-bold" aria-label="Quantité">
                {Number(p.quantite)}
              </span>
              <Button
                size="icon"
                variant="outline"
                aria-label={`Ajouter une unité de ${p.libelle}`}
                disabled={lectureSeule}
                onClick={() =>
                  exec(
                    supabase
                      .from("pieces_posees")
                      .update({ quantite: Number(p.quantite) + 1 })
                      .eq("id", p.id),
                  )
                }
              >
                <Plus aria-hidden />
              </Button>
              <Label htmlFor={`prix-${p.id}`} className="ml-2">
                Prix HT
              </Label>
              <Input
                id={`prix-${p.id}`}
                type="number"
                inputMode="decimal"
                step="0.01"
                min="0"
                className="h-12 w-28"
                disabled={lectureSeule}
                defaultValue={Number(p.prix_unitaire_ht)}
                onBlur={(e) => {
                  const v = Number(e.target.value);
                  if (!Number.isNaN(v) && v >= 0 && v !== Number(p.prix_unitaire_ht))
                    exec(
                      supabase.from("pieces_posees").update({ prix_unitaire_ht: v }).eq("id", p.id),
                    );
                }}
              />
            </div>
            <div className="mt-2 flex flex-wrap items-center justify-between gap-2">
              <label className="tap flex items-center gap-3">
                <input
                  type="checkbox"
                  className="size-6"
                  checked={p.a_commander}
                  disabled={lectureSeule}
                  onChange={() =>
                    exec(
                      supabase
                        .from("pieces_posees")
                        .update({ a_commander: !p.a_commander })
                        .eq("id", p.id),
                    )
                  }
                />
                À commander
              </label>
              {!lectureSeule && (
                <Button
                  variant="ghost"
                  onClick={() => exec(supabase.from("pieces_posees").delete().eq("id", p.id))}
                  aria-label={`Supprimer ${p.libelle}`}
                >
                  <Trash2 aria-hidden /> Retirer
                </Button>
              )}
            </div>
          </li>
        ))}
      </ul>
      <p className="font-bold">Total des pièces : {euros(total)} HT</p>

      {!lectureSeule && (
        <div className="space-y-3 border-t pt-3">
          <Label htmlFor="recherche-piece">
            Ajouter une pièce du catalogue (référence ou libellé)
          </Label>
          <Input
            id="recherche-piece"
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
                        supabase.from("pieces_posees").insert({
                          fiche_id: ficheId,
                          piece_id: c.id,
                          libelle: c.libelle,
                          quantite: 1,
                          prix_unitaire_ht: Number(c.prix_vente_ht),
                        }),
                      );
                    }}
                  >
                    <span>{c.libelle}</span>
                    <span>{euros(Number(c.prix_vente_ht))}</span>
                  </Button>
                </li>
              ))}
            </ul>
          )}
          {recherche.trim() && trouvees.length === 0 && <p>Aucune pièce trouvée.</p>}
          <Label htmlFor="ligne-libre">Ou une ligne libre</Label>
          <div className="flex gap-2">
            <Input
              id="ligne-libre"
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
                  supabase
                    .from("pieces_posees")
                    .insert({ fiche_id: ficheId, libelle: l, quantite: 1, prix_unitaire_ht: 0 }),
                );
              }}
            >
              Ajouter
            </Button>
          </div>
        </div>
      )}
    </section>
  );
}

function Commentaire({
  ficheId,
  initial,
  lectureSeule,
}: {
  ficheId: string;
  initial: string;
  lectureSeule: boolean;
}) {
  return (
    <section className="rounded-xl bg-card p-4 shadow-sm">
      <Label htmlFor="commentaire" className="text-xl font-bold">
        Commentaire général
      </Label>
      <Textarea
        id="commentaire"
        className="mt-2 min-h-28"
        maxLength={2000}
        disabled={lectureSeule}
        defaultValue={initial}
        onBlur={async (e) => {
          if (e.target.value === initial) return;
          const { error } = await supabase
            .from("fiches")
            .update({ commentaire: e.target.value.trim() || null })
            .eq("id", ficheId);
          if (error) toast.error(`Non enregistré : ${messageErreur(error)}`);
        }}
      />
    </section>
  );
}

function Terminer({ ficheId, onDone }: { ficheId: string; onDone: () => void }) {
  const [ouvert, setOuvert] = useState(false);
  const m = useMutation({
    mutationFn: async () => {
      const { error } = await supabase.rpc("terminer_fiche", { p_fiche: ficheId });
      if (error) throw error;
    },
    onSuccess: () => {
      prevenirN8n();
      toast.success("Fiche terminée. La facture est à préparer au bureau.");
      onDone();
    },
    onError: (e) => toast.error(messageErreur(e)),
  });
  return (
    <>
      <Button size="lg" className="w-full" onClick={() => setOuvert(true)}>
        Fiche terminée
      </Button>
      <AlertDialog open={ouvert} onOpenChange={setOuvert}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Terminer la fiche ?</AlertDialogTitle>
            <AlertDialogDescription>
              La fiche ne pourra plus être modifiée et la facture du vélo sera créée, à préparer au
              bureau.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel className="min-h-12">Annuler</AlertDialogCancel>
            <AlertDialogAction
              className="min-h-12"
              onClick={() => m.mutate()}
              disabled={m.isPending}
            >
              Terminer la fiche
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </>
  );
}
