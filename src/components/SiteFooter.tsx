import { useState } from "react";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";

type Cle = "mentions" | "confidentialite" | "cookies";

const TEXTES: Record<Cle, { titre: string; corps: React.ReactNode }> = {
  mentions: {
    titre: "Mentions légales",
    corps: (
      <>
        <p>
          <strong>Éditeur :</strong> Tournée Cycles, application de démonstration.
        </p>
        <p>
          <strong>Hébergeur :</strong> à compléter.
        </p>
      </>
    ),
  },
  confidentialite: {
    titre: "Confidentialité",
    corps: (
      <>
        <p>
          Données traitées à l'inscription : nom, prénom, téléphone, email, code postal, vélo et
          problème signalé.
        </p>
        <p>
          Elles servent à organiser la journée, réaliser la maintenance, établir la facture et
          bénéficier du label Bonus Répar Sport & Cycle. Elles ne sont pas réutilisées à d'autres
          fins.
        </p>
        <p>
          Vous pouvez demander l'accès, la rectification ou la suppression de vos données auprès de
          Tournée Cycles.
        </p>
      </>
    ),
  },
  cookies: {
    titre: "Cookies",
    corps: (
      <p>
        Nous utilisons uniquement ce qui est strictement nécessaire à la connexion. Aucune mesure
        d'audience, aucun traceur tiers.
      </p>
    ),
  },
};

export function SiteFooter() {
  const [ouvert, setOuvert] = useState<Cle | null>(null);
  const t = ouvert ? TEXTES[ouvert] : null;
  return (
    <footer className="mt-12 border-t bg-card">
      <div className="mx-auto flex max-w-3xl flex-wrap items-center gap-x-2 gap-y-1 px-4 py-4 text-sm">
        <span>Tournée Cycles, démonstration</span>
        {(Object.keys(TEXTES) as Cle[]).map((k) => (
          <span key={k} className="flex items-center gap-2">
            <span aria-hidden="true">|</span>
            <button
              type="button"
              className="tap px-1 text-primary-text underline underline-offset-4"
              onClick={() => setOuvert(k)}
            >
              {TEXTES[k].titre}
            </button>
          </span>
        ))}
      </div>
      <Dialog open={!!ouvert} onOpenChange={(o) => !o && setOuvert(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{t?.titre}</DialogTitle>
            <DialogDescription className="sr-only">{t?.titre}</DialogDescription>
          </DialogHeader>
          <div className="space-y-3">{t?.corps}</div>
        </DialogContent>
      </Dialog>
    </footer>
  );
}
