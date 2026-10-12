// Référentiel de la fiche de maintenance (repris de la fiche papier).
export type PointDef = { nom: string; constats?: string[] };
export type GroupeDef = { nom: string; points: PointDef[] };

const roue: PointDef[] = [
  "Serrage",
  "Centrage",
  "Voile",
  "Moyeu",
  "Position de la valve",
  "Sens de rotation du pneu",
  "Usure du pneu",
  "Pression",
  "Tension des rayons",
  "État des rayons",
].map((nom) => ({ nom }));
roue.push({ nom: "Surface de freinage de la jante", constats: ["Usée", "Chocs", "Rayures", "Graisse"] });

const frein: PointDef[] = [
  "Efficacité",
  "Serrage de l'étrier",
  "État de l'étrier",
  "Patins ou plaquettes",
  "Usure",
  "Position",
  "Serrage",
].map((nom) => ({ nom }));

const disque = ["Usé", "Voile", "Graisse", "Choc"];
const p = (noms: string[]) => noms.map((nom) => ({ nom }));

export const GROUPES: GroupeDef[] = [
  { nom: "Roue avant", points: roue },
  { nom: "Roue arrière", points: roue },
  { nom: "Cadre", points: p(["Cadre", "Fourche"]) },
  { nom: "Frein avant", points: frein },
  { nom: "Frein arrière", points: frein },
  {
    nom: "Câblerie",
    points: [
      ...p([
        "Câble de frein avant",
        "Gaine de frein avant",
        "Câble de frein arrière",
        "Gaine de frein arrière",
        "Levier de frein gauche",
        "Levier de frein droit",
      ]),
      { nom: "Disque avant", constats: disque },
      { nom: "Disque arrière", constats: disque },
    ],
  },
  {
    nom: "Direction",
    points: p([
      "Jeu de direction (serrage)",
      "Jeu de direction (rotation et roulements)",
      "Cintre",
      "Cintre (serrage)",
      "Cintre (position)",
      "Potence",
      "Potence (serrage)",
      "Enfoncement du plongeur",
      "Poignées ou ruban",
    ]),
  },
  {
    nom: "Transmission",
    points: p([
      "Manette gauche",
      "Manette droite",
      "Câble gauche",
      "Gaine gauche",
      "Câble droit",
      "Gaine droite",
      "Dérailleur avant (état)",
      "Dérailleur avant (position)",
      "Dérailleur avant (fonctionnement)",
      "Pédalier",
      "Plateaux",
      "Boîtier de pédalier",
      "Boîtier de pédalier (serrage)",
      "Chaîne",
      "Dérailleur arrière (état)",
      "Dérailleur arrière (position)",
      "Dérailleur arrière (fonctionnement)",
      "Cassette",
      "Patte de dérailleur",
    ]),
  },
  { nom: "Position", points: p(["Tige de selle", "Selle", "Pédales"]) },
];
