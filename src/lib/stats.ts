// Lot L2 : calcul des statistiques par entreprise à partir des lignes de la vue stats_entreprises.
export type LigneStat = {
  entreprise_id: string;
  entreprise: string;
  site: string;
  date_intervention: string;
  genre: "velo" | "organe" | "piece" | string;
  libelle: string;
  quantite: number;
};

export type Filtre = { entreprise: string | null; site: string | null; du: string; au: string };

export type Resultat = {
  velos: number;
  journees: number;
  parType: { libelle: string; total: number }[];
  organes: { libelle: string; total: number }[];
  pieces: { libelle: string; total: number }[];
};

/** Garde les lignes de l'entreprise, du site (tous si null) et de la période (bornes incluses, vides = ouvertes). */
export function filtrer(lignes: LigneStat[], f: Filtre): LigneStat[] {
  return lignes.filter(
    (l) =>
      (!f.entreprise || l.entreprise_id === f.entreprise) &&
      (!f.site || l.site === f.site) &&
      (!f.du || l.date_intervention >= f.du) &&
      (!f.au || l.date_intervention <= f.au),
  );
}

function cumul(lignes: LigneStat[], genre: string) {
  const m = new Map<string, number>();
  for (const l of lignes)
    if (l.genre === genre) m.set(l.libelle, (m.get(l.libelle) ?? 0) + Number(l.quantite));
  return [...m.entries()]
    .map(([libelle, total]) => ({ libelle, total: Math.round(total * 100) / 100 }))
    .sort((a, b) => b.total - a.total || a.libelle.localeCompare(b.libelle, "fr"));
}

/** Vélos vus, organes en défaut les plus fréquents et pièces changées, sur les lignes déjà filtrées. */
export function calculer(lignes: LigneStat[]): Resultat {
  const velos = lignes.filter((l) => l.genre === "velo");
  return {
    velos: velos.length,
    journees: new Set(velos.map((l) => `${l.date_intervention}|${l.site}`)).size,
    parType: cumul(lignes, "velo"),
    organes: cumul(lignes, "organe"),
    pieces: cumul(lignes, "piece"),
  };
}
