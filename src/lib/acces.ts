// Lot L3 : accès des prestataires (types et aides de l'écran).
export type Acces = {
  id: string;
  email: string;
  role: "dirigeant" | "mecanicien" | "atelier";
  expire_le: string | null;
  revoque_le: string | null;
  created_at: string;
  etat: "actif" | "expire" | "retire";
  protege: boolean;
};

export const ROLE_ACCES: Record<string, string> = {
  dirigeant: "Dirigeant",
  mecanicien: "Mécanicien",
  atelier: "Atelier",
};

/** Date AAAA-MM-JJ : fin de cette journée à Paris (23:59:59), en ISO avec décalage ; chaîne vide si date invalide. */
export function finDeJourneeParis(date: string): string {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) return "";
  const [y, m, d] = date.split("-").map(Number) as [number, number, number];
  const utc = Date.UTC(y, m - 1, d, 23, 59, 59);
  if (new Date(utc).getUTCDate() !== d) return "";
  // Décalage de Paris ce jour-là (heure d'été ou d'hiver), lu par Intl
  const parts = new Intl.DateTimeFormat("en-GB", {
    timeZone: "Europe/Paris",
    timeZoneName: "shortOffset",
  }).formatToParts(new Date(utc));
  const off = parts.find((p) => p.type === "timeZoneName")?.value ?? "GMT+1";
  const mm = /GMT([+-])(\d{1,2})(?::(\d{2}))?/.exec(off);
  const signe = mm ? mm[1] : "+";
  const h = mm ? mm[2]!.padStart(2, "0") : "01";
  const min = mm?.[3] ?? "00";
  return `${date}T23:59:59${signe}${h}:${min}`;
}
