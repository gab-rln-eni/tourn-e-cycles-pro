export function dateLongue(iso: string | null | undefined) {
  if (!iso) return "";
  const [y = 1970, m = 1, d = 1] = iso.slice(0, 10).split("-").map(Number);
  return new Date(y, m - 1, d).toLocaleDateString("fr-FR", {
    weekday: "long",
    day: "numeric",
    month: "long",
    year: "numeric",
  });
}

export function dateHeure(iso: string | null | undefined) {
  if (!iso) return "";
  return new Date(iso).toLocaleString("fr-FR", {
    day: "numeric",
    month: "long",
    hour: "2-digit",
    minute: "2-digit",
  });
}

export function euros(n: number) {
  return n.toLocaleString("fr-FR", { style: "currency", currency: "EUR" });
}

export function todayISO() {
  const d = new Date();
  const p = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}

export const TYPE_VELO: Record<string, string> = {
  vae: "Électrique (VAE)",
  musculaire: "Musculaire",
};

export const PARTIES: { value: string; label: string }[] = [
  { value: "freins", label: "Freins" },
  { value: "roues", label: "Roues et pneus" },
  { value: "transmission", label: "Vitesses et chaîne" },
  { value: "direction", label: "Direction" },
  { value: "cadre", label: "Cadre" },
  { value: "autre", label: "Autre" },
  { value: "inconnu", label: "Je ne sais pas" },
];
export const PARTIE_LABEL: Record<string, string> = Object.fromEntries(
  PARTIES.map((p) => [p.value, p.label]),
);

export const STATUT_FACTURE: Record<string, string> = {
  a_preparer: "À préparer",
  brouillon: "Brouillon prêt",
  a_valider: "À valider",
  validee: "Validée",
  envoyee: "Envoyée",
  echec: "Échec",
};

export const ETATS = [
  { value: "bon", label: "Bon" },
  { value: "a_regler", label: "À régler" },
  { value: "a_reparer", label: "À réparer" },
  { value: "a_changer", label: "À changer" },
] as const;
export const ETAT_LABEL: Record<string, string> = Object.fromEntries(
  ETATS.map((e) => [e.value, e.label]),
);

export function totaux(lignes: { quantite: number; prix_unitaire_ht: number; taux_tva: number }[]) {
  const ht = lignes.reduce((s, l) => s + Number(l.quantite) * Number(l.prix_unitaire_ht), 0);
  const tva = lignes.reduce(
    (s, l) => s + (Number(l.quantite) * Number(l.prix_unitaire_ht) * Number(l.taux_tva)) / 100,
    0,
  );
  const r = (n: number) => Math.round(n * 100) / 100;
  return { ht: r(ht), tva: r(tva), ttc: r(ht + tva) };
}

export function messageErreur(e: unknown) {
  if (e && typeof e === "object" && "message" in e) return String((e as { message: unknown }).message);
  return "Une erreur est survenue. Réessayez.";
}
