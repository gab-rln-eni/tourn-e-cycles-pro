import { createFileRoute } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import { useState } from "react";
import { Check } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { prevenirN8n } from "@/lib/declencher";
import { PARTIES, dateLongue, messageErreur } from "@/lib/format";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";

export const Route = createFileRoute("/inscription")({
  ssr: false,
  validateSearch: (s: Record<string, unknown>) => ({
    c: typeof s["c"] === "string" ? (s["c"] as string) : undefined,
    e: typeof s["e"] === "string" ? (s["e"] as string) : undefined,
  }),
  head: () => ({
    meta: [
      { title: "Inscription à la journée vélo | Tournée Cycles" },
      {
        name: "description",
        content: "Inscrivez votre vélo à la journée de maintenance de votre entreprise.",
      },
    ],
  }),
  component: Inscription,
});

type Journee = {
  id: string;
  site: string;
  adresse: string;
  date_intervention: string;
  code: string;
  complet: boolean;
};
type Cle =
  | "evenement"
  | "nom"
  | "prenom"
  | "telephone"
  | "email"
  | "code_postal"
  | "type_velo"
  | "partie_signalee"
  | "consentement";
type Ouverts = { entreprise: string; evenements: Journee[] } | null;

const TYPES = [
  { value: "vae", label: "Électrique (VAE)" },
  { value: "musculaire", label: "Musculaire" },
];

function Choix({
  name,
  legende,
  options,
  valeur,
  onChange,
  erreur,
}: {
  name: string;
  legende: string;
  options: { value: string; label: string }[];
  valeur: string;
  onChange: (v: string) => void;
  erreur?: string | undefined;
}) {
  return (
    <fieldset aria-describedby={erreur ? `err-${name}` : undefined}>
      <legend className="font-bold">
        {legende} <span className="text-rose-text">(obligatoire)</span>
      </legend>
      <div className="mt-2 grid grid-cols-2 gap-2">
        {options.map((o) => {
          const actif = valeur === o.value;
          return (
            <label
              key={o.value}
              className={
                "tap flex cursor-pointer items-center gap-2 rounded-lg border-2 px-3 py-2 font-bold focus-within:outline-3 focus-within:outline-ring " +
                (actif
                  ? "border-primary bg-primary text-primary-foreground"
                  : "border-border bg-card")
              }
            >
              <input
                type="radio"
                name={name}
                value={o.value}
                checked={actif}
                onChange={() => onChange(o.value)}
                className="sr-only"
              />
              {actif && <Check aria-hidden />}
              {o.label}
            </label>
          );
        })}
      </div>
      {erreur && (
        <p id={`err-${name}`} className="mt-1 font-bold text-rose-text">
          {erreur}
        </p>
      )}
    </fieldset>
  );
}

function Inscription() {
  const { c, e } = Route.useSearch();
  const q = useQuery({
    queryKey: ["ouverts", c],
    enabled: !!c,
    queryFn: async () => {
      const { data, error } = await supabase.rpc("evenements_ouverts", { p_code_entreprise: c! });
      if (error) throw error;
      return data as unknown as Ouverts;
    },
  });

  const [f, setF] = useState({
    evenement_id: "",
    nom: "",
    prenom: "",
    telephone: "",
    email: "",
    code_postal: "",
    type_velo: "",
    partie_signalee: "",
    velo_modele: "",
    probleme_percu: "",
    consentement: false,
  });
  const [erreurs, setErreurs] = useState<Partial<Record<Cle, string>>>({});
  const [erreurServeur, setErreurServeur] = useState("");
  const [envoi, setEnvoi] = useState(false);
  const [fait, setFait] = useState<{
    entreprise: string;
    site: string;
    date_intervention: string;
  } | null>(null);

  if (!c) return <SansCode />;
  if (q.isLoading) return <p role="status">Chargement.</p>;
  if (q.error)
    return (
      <p role="alert" className="font-bold text-rose-text">
        {messageErreur(q.error)}
      </p>
    );
  if (!q.data) return <SansCode />;

  const { entreprise, evenements } = q.data;
  const preselection = e ? evenements.find((j) => j.code === e) : undefined;
  const evId = f.evenement_id || preselection?.id || "";
  const journee = evenements.find((j) => j.id === evId);
  const set = (k: keyof typeof f, v: string | boolean) => setF((s) => ({ ...s, [k]: v }));

  if (fait)
    return (
      <section className="space-y-3 rounded-xl bg-card p-6 text-center shadow-sm" role="status">
        <h1 className="text-3xl font-bold text-primary">Inscription enregistrée</h1>
        <p className="text-lg">
          {fait.entreprise}, {fait.site}
        </p>
        <p className="text-lg font-bold">{dateLongue(fait.date_intervention)}</p>
        <p>Venez avec votre vélo à l'heure indiquée par votre entreprise.</p>
      </section>
    );

  function verifier() {
    const er: Partial<Record<Cle, string>> = {};
    if (!evId) er.evenement = "Choisissez votre journée.";
    if (!f.nom.trim()) er.nom = "Indiquez votre nom.";
    if (!f.prenom.trim()) er.prenom = "Indiquez votre prénom.";
    if (!/^[0-9]{10}$/.test(f.telephone.replace(/[\s.-]/g, "")))
      er.telephone = "Le téléphone doit comporter 10 chiffres.";
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(f.email.trim()))
      er.email = "L'adresse email n'est pas valide.";
    if (!/^[0-9]{5}$/.test(f.code_postal.trim()))
      er.code_postal = "Le code postal doit comporter 5 chiffres.";
    if (!f.type_velo) er.type_velo = "Choisissez le type de vélo.";
    if (!f.partie_signalee) er.partie_signalee = "Choisissez la partie du vélo qui pose problème.";
    if (!f.consentement) er.consentement = "Vous devez cocher la case de consentement.";
    return er;
  }

  async function envoyer(ev: React.FormEvent) {
    ev.preventDefault();
    setErreurServeur("");
    const er = verifier();
    setErreurs(er);
    if (Object.keys(er).length) return;
    if (journee?.complet) {
      setErreurServeur("Cette journée est complète.");
      return;
    }
    setEnvoi(true);
    // V4 (TC-23) : inscrire_v4 refuse une seconde inscription du même mail à la même journée, puis appelle inscrire.
    const { data, error } = await supabase.rpc("inscrire_v4", {
      p: { ...f, evenement_id: evId, code_entreprise: c },
    });
    setEnvoi(false);
    if (error) setErreurServeur(messageErreur(error));
    else {
      prevenirN8n();
      setFait(data as unknown as { entreprise: string; site: string; date_intervention: string });
    }
  }

  const champ = (
    id: "nom" | "prenom" | "telephone" | "email" | "code_postal",
    label: string,
    props: React.ComponentProps<typeof Input> = {},
  ) => (
    <div>
      <Label htmlFor={id}>
        {label} <span className="text-rose-text">(obligatoire)</span>
      </Label>
      <Input
        id={id}
        className="h-12"
        value={f[id]}
        onChange={(x) => set(id, x.target.value)}
        aria-invalid={!!erreurs[id]}
        aria-describedby={erreurs[id] ? `err-${id}` : undefined}
        {...props}
      />
      {erreurs[id] && (
        <p id={`err-${id}`} className="mt-1 font-bold text-rose-text">
          {erreurs[id]}
        </p>
      )}
    </div>
  );

  return (
    <form onSubmit={envoyer} noValidate className="space-y-5">
      <h1 className="text-3xl font-bold text-primary">
        {preselection
          ? `Journée vélo du ${dateLongue(preselection.date_intervention)}`
          : "Inscription à la journée vélo"}
      </h1>
      <p className="text-lg">{entreprise}</p>

      {evenements.length === 0 ? (
        <p role="status" className="font-bold">
          Aucune journée ouverte pour le moment.
        </p>
      ) : (
        <fieldset aria-describedby={erreurs.evenement ? "err-evenement" : undefined}>
          <legend className="font-bold">
            Votre journée <span className="text-rose-text">(obligatoire)</span>
          </legend>
          <div className="mt-2 space-y-2">
            {evenements.map((j) => {
              const actif = evId === j.id;
              return (
                <label
                  key={j.id}
                  className={
                    "tap flex cursor-pointer items-center gap-3 rounded-lg border-2 p-3 focus-within:outline-3 focus-within:outline-ring " +
                    (j.complet ? "opacity-60 " : "") +
                    (actif
                      ? "border-primary bg-primary text-primary-foreground"
                      : "border-border bg-card")
                  }
                >
                  <input
                    type="radio"
                    name="journee"
                    className="sr-only"
                    checked={actif}
                    disabled={j.complet}
                    onChange={() => set("evenement_id", j.id)}
                  />
                  {actif && <Check aria-hidden />}
                  <span>
                    <strong>{dateLongue(j.date_intervention)}</strong>, {j.site}
                    {j.complet ? " (complet)" : ""}
                  </span>
                </label>
              );
            })}
          </div>
          {erreurs.evenement && (
            <p id="err-evenement" className="mt-1 font-bold text-rose-text">
              {erreurs.evenement}
            </p>
          )}
        </fieldset>
      )}

      {evenements.length > 0 && (
        <>
          {champ("nom", "Nom", { autoComplete: "family-name", maxLength: 100 })}
          {champ("prenom", "Prénom", { autoComplete: "given-name", maxLength: 100 })}
          {champ("telephone", "Téléphone", { type: "tel", inputMode: "tel", autoComplete: "tel" })}
          {champ("email", "Email", { type: "email", autoComplete: "email", maxLength: 255 })}
          {champ("code_postal", "Code postal", {
            inputMode: "numeric",
            autoComplete: "postal-code",
            maxLength: 5,
          })}
          <Choix
            name="type_velo"
            legende="Type de vélo"
            options={TYPES}
            valeur={f.type_velo}
            onChange={(v) => set("type_velo", v)}
            erreur={erreurs.type_velo}
          />
          <Choix
            name="partie_signalee"
            legende="Partie du vélo qui pose problème"
            options={PARTIES}
            valeur={f.partie_signalee}
            onChange={(v) => set("partie_signalee", v)}
            erreur={erreurs.partie_signalee}
          />
          <div>
            <Label htmlFor="velo_modele">Marque et modèle du vélo (facultatif)</Label>
            <Input
              id="velo_modele"
              className="h-12"
              maxLength={100}
              value={f.velo_modele}
              onChange={(x) => set("velo_modele", x.target.value)}
            />
          </div>
          <div>
            <Label htmlFor="probleme_percu">
              Décrivez le problème (facultatif, 300 caractères)
            </Label>
            <Textarea
              id="probleme_percu"
              maxLength={300}
              className="min-h-24"
              value={f.probleme_percu}
              onChange={(x) => set("probleme_percu", x.target.value)}
            />
          </div>
          <div>
            <label className="tap flex items-start gap-3">
              <input
                type="checkbox"
                className="mt-1 size-6 shrink-0"
                checked={f.consentement}
                onChange={(x) => set("consentement", x.target.checked)}
                aria-describedby={erreurs.consentement ? "err-consentement" : undefined}
              />
              <span>
                J'accepte que Tournée Cycles utilise ces informations pour organiser la journée,
                réparer mon vélo et établir la facture.{" "}
                <span className="text-rose-text">(obligatoire)</span>
              </span>
            </label>
            {erreurs.consentement && (
              <p id="err-consentement" className="mt-1 font-bold text-rose-text">
                {erreurs.consentement}
              </p>
            )}
          </div>
          <p className="rounded-lg border-l-8 border-primary bg-card p-4">
            Tournée Cycles est labellisé Bonus Répar Sport & Cycle. Les informations obligatoires
            sont celles demandées pour en bénéficier.
          </p>
          {erreurServeur && (
            <p role="alert" className="font-bold text-rose-text">
              {erreurServeur}
            </p>
          )}
          <Button type="submit" size="lg" className="w-full" disabled={envoi}>
            Envoyer mon inscription
          </Button>
        </>
      )}
    </form>
  );
}

function SansCode() {
  return (
    <section className="rounded-xl bg-card p-6 text-center shadow-sm">
      <h1 className="text-2xl font-bold text-primary">Inscription à la journée vélo</h1>
      <p role="alert" className="mt-3 text-lg font-bold">
        Utilisez le lien transmis par votre entreprise.
      </p>
    </section>
  );
}
