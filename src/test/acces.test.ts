import { describe, expect, it } from "vitest";
import { finDeJourneeParis } from "@/lib/acces";

// Lot L3 : date d'expiration envoyée à la base (fin de journée, heure de Paris).
describe("accès des prestataires : date d'expiration", () => {
  it("nominal : heure d'été (+02:00) et d'hiver (+01:00)", () => {
    expect(finDeJourneeParis("2026-10-20")).toBe("2026-10-20T23:59:59+02:00");
    expect(finDeJourneeParis("2026-11-20")).toBe("2026-11-20T23:59:59+01:00");
  });
  it("vide : date absente", () => {
    expect(finDeJourneeParis("")).toBe("");
  });
  it("erreur : date invalide ou mal formée", () => {
    expect(finDeJourneeParis("2026-02-31")).toBe("");
    expect(finDeJourneeParis("20/10/2026")).toBe("");
  });
});
