import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { homeFor, useAuth } from "@/lib/auth";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";

export const Route = createFileRoute("/")({
  head: () => ({
    meta: [
      { title: "Tournée Cycles, l'atelier vélo qui vient à vous" },
      { name: "description", content: "Atelier mobile de réparation de vélos en entreprise, à Lyon." },
      { property: "og:title", content: "Tournée Cycles" },
      { property: "og:description", content: "L'atelier vélo qui vient à vous." },
    ],
  }),
  component: Accueil,
});

function Accueil() {
  const { data } = useAuth();
  const navigate = useNavigate();
  const [ouvert, setOuvert] = useState(false);
  const [creer, setCreer] = useState(false);
  const [email, setEmail] = useState("");
  const [mdp, setMdp] = useState("");
  const [erreur, setErreur] = useState("");
  const [info, setInfo] = useState("");

  useEffect(() => {
    if (data?.user) {
      const h = homeFor(data.roles);
      if (h) navigate({ to: h });
    }
  }, [data, navigate]);

  async function envoyer(e: React.FormEvent) {
    e.preventDefault();
    setErreur("");
    setInfo("");
    if (creer) {
      const { error } = await supabase.auth.signUp({
        email,
        password: mdp,
        options: { emailRedirectTo: window.location.origin },
      });
      if (error) setErreur("Création impossible. Vérifiez l'email et un mot de passe de 8 caractères au moins.");
      else setInfo("Compte créé. Ouvrez l'email reçu pour confirmer votre adresse.");
    } else {
      const { error } = await supabase.auth.signInWithPassword({ email, password: mdp });
      if (error)
        setErreur(
          error.message.includes("confirmed")
            ? "Confirmez votre email avant de vous connecter."
            : "Email ou mot de passe incorrect.",
        );
      else setOuvert(false);
    }
  }

  const sansAcces = data?.user && !homeFor(data.roles);

  return (
    <section className="py-12 text-center">
      <h1 className="text-4xl font-bold text-primary">Tournée Cycles</h1>
      <p className="mt-3 text-xl">L'atelier vélo qui vient à vous.</p>
      {sansAcces ? (
        <p role="alert" className="mx-auto mt-8 max-w-md rounded-lg border-l-8 border-rose bg-card p-4 font-bold">
          Votre accès n'est pas actif. Contactez Tournée Cycles.
        </p>
      ) : (
        !data?.user && (
          <Button size="lg" className="mt-8 w-full sm:w-auto" onClick={() => setOuvert(true)}>
            Se connecter
          </Button>
        )
      )}
      <Dialog open={ouvert} onOpenChange={setOuvert}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{creer ? "Créer un compte" : "Se connecter"}</DialogTitle>
            <DialogDescription>Avec votre email et votre mot de passe.</DialogDescription>
          </DialogHeader>
          <form onSubmit={envoyer} className="space-y-4 text-left">
            <div>
              <Label htmlFor="email">Email</Label>
              <Input id="email" type="email" autoComplete="email" required className="h-12" value={email} onChange={(e) => setEmail(e.target.value)} aria-describedby={erreur ? "err-login" : undefined} />
            </div>
            <div>
              <Label htmlFor="mdp">Mot de passe</Label>
              <Input id="mdp" type="password" required minLength={creer ? 8 : undefined} className="h-12" value={mdp} onChange={(e) => setMdp(e.target.value)} />
            </div>
            {erreur && <p id="err-login" role="alert" className="font-bold text-rose-text">{erreur}</p>}
            {info && <p role="status" className="font-bold text-primary-text">{info}</p>}
            <Button type="submit" className="w-full">{creer ? "Créer le compte" : "Se connecter"}</Button>
            <Button type="button" variant="link" className="w-full" onClick={() => setCreer(!creer)}>
              {creer ? "J'ai déjà un compte" : "Créer un compte"}
            </Button>
          </form>
        </DialogContent>
      </Dialog>
    </section>
  );
}
