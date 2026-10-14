import { describe, expect, it } from "vitest";
import { lireEssai } from "@/lib/commandes.server";
import { refuserSansSecret } from "@/lib/liaison.server";
import { quantiteFr } from "@/lib/format";

// Lot L1 : route du rappel (mode essai, secret) et affichage des quantités.
describe("rappel des pièces à commander", () => {
  it("nominal : essai vrai seulement si demandé explicitement", () => {
    expect(lireEssai('{"essai": true}')).toBe(true);
    expect(lireEssai('{"essai": false}')).toBe(false);
  });
  it("vide : corps absent ou vide, mode normal", () => {
    expect(lireEssai("")).toBe(false);
    expect(lireEssai("   ")).toBe(false);
    expect(lireEssai("{}")).toBe(false);
  });
  it("erreur : corps illisible ou essai non booléen, mode normal", () => {
    expect(lireEssai("{essai")).toBe(false);
    expect(lireEssai('{"essai": "true"}')).toBe(false);
    expect(lireEssai("[true]")).toBe(false);
  });
  it("refuse sans secret (401) et sans configuration (503)", () => {
    const r = new Request("https://app/api/public/rappel-commandes", { method: "POST" });
    expect(refuserSansSecret(r, "s3cret")?.status).toBe(401);
    expect(refuserSansSecret(r, undefined)?.status).toBe(503);
    const ok = new Request("https://app/x", {
      method: "POST",
      headers: { "x-tc-secret": "s3cret" },
    });
    expect(refuserSansSecret(ok, "s3cret")).toBeNull();
  });
  it("affiche les quantités avec une virgule", () => {
    expect(quantiteFr(0.5)).toBe("0,5");
    expect(quantiteFr(2)).toBe("2");
  });
});
