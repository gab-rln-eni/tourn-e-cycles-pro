import { afterEach, describe, expect, it, vi } from "vitest";
import {
  appelerWorkflow,
  avisBruts,
  corpsCreation,
  decisionValide,
  jetonValide,
  lienReponse,
  lireReponseN8n,
  uuidValide,
} from "@/lib/devis.server";
import { lireAvis } from "@/lib/devis";

const JETON = "a".repeat(64);

describe("parcours devis : jeton, décision, lien", () => {
  it("accepte seulement un jeton de 64 caractères hexadécimaux", () => {
    expect(jetonValide(JETON)).toBe(true);
    expect(jetonValide("A".repeat(64))).toBe(false);
    expect(jetonValide("a".repeat(63))).toBe(false);
    expect(jetonValide("")).toBe(false);
    expect(jetonValide(undefined)).toBe(false);
  });
  it("refuse un identifiant de devis qui n'est pas un UUID", () => {
    expect(uuidValide("db11b3fb-6a90-4648-a0b2-acfd09c8c494")).toBe(true);
    expect(uuidValide("1; drop")).toBe(false);
    expect(uuidValide("")).toBe(false);
  });
  it("accepte seulement accepte ou refuse", () => {
    expect(decisionValide("accepte")).toBe(true);
    expect(decisionValide("refuse")).toBe(true);
    expect(decisionValide("oui")).toBe(false);
  });
  it("construit le lien de la page du cycliste sans double barre", () => {
    expect(lienReponse("https://app.exemple/", JETON)).toBe(`https://app.exemple/devis/${JETON}`);
  });
  it("ajoute le lien de réponse aux données préparées par la base", () => {
    expect(corpsCreation({ reference: "DV-1" }, "https://l")).toEqual({
      reference: "DV-1",
      lien_reponse: "https://l",
    });
  });
});

describe("parcours devis : lecture des réponses de n8n", () => {
  it("nominal : ok et résultat", () => {
    const r = lireReponseN8n(
      200,
      JSON.stringify({ ok: true, erreur: "", resultat: { axonaut_devis_id: "42" } }),
    );
    expect(r).toEqual({ ok: true, erreur: "", resultat: { axonaut_devis_id: "42" } });
  });
  it("vide : corps vide ou illisible, échec lisible", () => {
    expect(lireReponseN8n(200, "").ok).toBe(false);
    expect(lireReponseN8n(200, "[]").erreur).toContain("illisible");
  });
  it("erreur : HTTP 500 ou 403, échec avec message", () => {
    expect(lireReponseN8n(500, JSON.stringify({ message: "x" })).erreur).toContain("500");
    const r = lireReponseN8n(403, "Authorization data is wrong!");
    expect(r.ok).toBe(false);
    expect(r.erreur).toContain("403");
  });
  it("ok absent ou faux : échec", () => {
    expect(lireReponseN8n(200, JSON.stringify({ erreur: "Axonaut a refusé" })).ok).toBe(false);
  });
  it("avis de contrôle : formes inattendues ignorées", () => {
    expect(avisBruts([{ niveau: "erreur", message: "m" }, null, 3])).toEqual([
      { niveau: "erreur", message: "m" },
    ]);
    expect(avisBruts("x")).toEqual([]);
    expect(lireAvis([{ niveau: "bizarre", message: "m" }])).toEqual([
      { niveau: "ok", message: "m" },
    ]);
  });
});

describe("parcours devis : appel du webhook", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
    vi.unstubAllEnvs();
  });
  it("non configuré : aucun appel", async () => {
    vi.stubEnv("N8N_BASE_URL", "");
    vi.stubEnv("TC_SECRET", "");
    const f = vi.fn();
    vi.stubGlobal("fetch", f);
    expect((await appelerWorkflow("tc-devis-creer", {})).erreur).toContain("non configuré");
    expect(f).not.toHaveBeenCalled();
  });
  it("nominal : chemin neuf, secret en en-tête, corps JSON", async () => {
    vi.stubEnv("N8N_BASE_URL", "https://n8n.exemple/");
    vi.stubEnv("TC_SECRET", "s3cret");
    const f = vi
      .fn()
      .mockResolvedValue(
        new Response(JSON.stringify({ ok: true, erreur: "", resultat: {} }), { status: 200 }),
      );
    vi.stubGlobal("fetch", f);
    const r = await appelerWorkflow("tc-devis-decision", { decision: "accepte" });
    expect(r.ok).toBe(true);
    const [url, init] = f.mock.calls[0] as [string, RequestInit];
    expect(url).toBe("https://n8n.exemple/webhook/tc-devis-decision");
    expect((init.headers as Record<string, string>)["x-tc-secret"]).toBe("s3cret");
    expect(JSON.parse(String(init.body))).toEqual({ decision: "accepte" });
  });
  it("erreur : n8n injoignable, jamais d'exception", async () => {
    vi.stubEnv("N8N_BASE_URL", "https://n8n.exemple");
    vi.stubEnv("TC_SECRET", "s3cret");
    vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new TypeError("fetch failed")));
    const r = await appelerWorkflow("tc-devis-creer", {});
    expect(r.ok).toBe(false);
    expect(r.erreur).toContain("injoignable");
  });
});
