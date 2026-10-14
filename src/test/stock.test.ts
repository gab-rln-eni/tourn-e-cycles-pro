import { describe, expect, it } from "vitest";
import { etatPiece, libelleStock, lireStockPieces } from "@/lib/stock";
import { lireStocks } from "@/lib/stock.server";
import { refuserSansSecret } from "@/lib/liaison.server";

// Agent STOCK : lecture du stock pour l'écran du devis, corps de la route d'écriture, secret des routes neuves.
describe("stock des pièces au devis", () => {
  it("nominal : états lus par pièce", () => {
    const m = lireStockPieces([
      { piece_id: "a", etat: "en_stock" },
      { piece_id: "b", etat: "a_commander" },
      { piece_id: "c", etat: "inconnu" },
    ]);
    expect(etatPiece(m, "a")).toBe("en_stock");
    expect(etatPiece(m, "b")).toBe("a_commander");
    expect(etatPiece(m, "c")).toBe("inconnu");
    expect(libelleStock[etatPiece(m, "b")]).toBe("À commander");
  });
  it("vide : réponse vide ou pièce absente, inconnu", () => {
    expect(etatPiece(lireStockPieces([]), "a")).toBe("inconnu");
    expect(etatPiece(lireStockPieces(null), "a")).toBe("inconnu");
  });
  it("erreur : forme inattendue, inconnu sans exception", () => {
    const m = lireStockPieces([{ piece_id: "a", etat: "beaucoup" }, 3, null, { etat: "en_stock" }]);
    expect(etatPiece(m, "a")).toBe("inconnu");
    expect(lireStockPieces({ piece_id: "a" }).size).toBe(0);
  });
});

describe("route d'écriture du stock", () => {
  it("nominal et vide", () => {
    expect(lireStocks('{"stocks": [{"axonaut_produit_id": "1", "stock": 2}]}')).toHaveLength(1);
    expect(lireStocks('{"stocks": []}')).toEqual([]);
  });
  it("erreur : corps illisible ou sans tableau", () => {
    expect(lireStocks("")).toBeNull();
    expect(lireStocks("{stocks")).toBeNull();
    expect(lireStocks('{"stocks": 3}')).toBeNull();
    expect(lireStocks("[]")).toBeNull();
  });
  it("refuse sans secret ou avec un mauvais secret (401)", () => {
    const sans = new Request("https://app/api/public/demandes-a-traiter-v2", { method: "POST" });
    const faux = new Request("https://app/api/public/demandes-a-traiter-v2", {
      method: "POST",
      headers: { "x-tc-secret": "faux" },
    });
    expect(refuserSansSecret(sans, "s3cret")?.status).toBe(401);
    expect(refuserSansSecret(faux, "s3cret")?.status).toBe(401);
  });
});
