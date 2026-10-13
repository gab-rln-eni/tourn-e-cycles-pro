import { describe, expect, it } from "vitest";
import { egaliteConstante, refuserSansSecret } from "@/lib/liaison.server";

const requete = (secret?: string) =>
  new Request("https://exemple.test/api/public/demandes-a-traiter", {
    method: "POST",
    headers: secret === undefined ? {} : { "x-tc-secret": secret },
  });

describe("liaison avec n8n : contrôle du secret", () => {
  it("compare deux chaînes", () => {
    expect(egaliteConstante("abc", "abc")).toBe(true);
    expect(egaliteConstante("abc", "abd")).toBe(false);
    expect(egaliteConstante("abc", "abcd")).toBe(false);
    expect(egaliteConstante("", "")).toBe(true);
  });

  it("refuse si TC_SECRET n'est pas configuré (503)", () => {
    expect(refuserSansSecret(requete("x"), undefined)?.status).toBe(503);
  });

  it("refuse un en-tête absent ou faux (401)", () => {
    expect(refuserSansSecret(requete(), "bon-secret")?.status).toBe(401);
    expect(refuserSansSecret(requete("mauvais"), "bon-secret")?.status).toBe(401);
  });

  it("laisse passer le bon secret", () => {
    expect(refuserSansSecret(requete("bon-secret"), "bon-secret")).toBeNull();
  });
});
