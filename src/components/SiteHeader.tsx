import { Link, useNavigate } from "@tanstack/react-router";
import { useQueryClient } from "@tanstack/react-query";
import { CircleUserRound, LogOut } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/lib/auth";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";

export function SiteHeader() {
  const { data } = useAuth();
  const qc = useQueryClient();
  const navigate = useNavigate();
  const roles = data?.roles ?? [];
  const voitJournee = roles.includes("dirigeant") || roles.includes("mecanicien");
  const voitBureau = roles.includes("dirigeant") || roles.includes("atelier");

  async function deconnexion() {
    await qc.cancelQueries();
    qc.clear();
    await supabase.auth.signOut();
    navigate({ to: "/", replace: true });
  }

  const lien =
    "tap inline-flex items-center rounded-lg px-3 font-bold text-primary-text hover:bg-muted [&.active]:bg-primary [&.active]:text-primary-foreground";

  return (
    <header className="sticky top-0 z-30 border-b bg-card">
      <div className="mx-auto flex max-w-3xl items-center gap-2 px-4 py-2">
        <Link to="/" className="tap mr-auto inline-flex items-center text-xl font-bold text-primary-text">
          Tournée Cycles
        </Link>
        {data?.user && (
          <nav aria-label="Navigation principale" className="flex items-center gap-1">
            {voitJournee && (
              <Link to="/journee" className={lien}>
                La journée
              </Link>
            )}
            {voitBureau && (
              <Link to="/bureau" className={lien}>
                Bureau
              </Link>
            )}
            {voitBureau && (
              <Link to="/commandes" className={lien}>
                À commander
              </Link>
            )}
            <DropdownMenu>
              <DropdownMenuTrigger
                className="tap inline-flex items-center justify-center rounded-lg hover:bg-muted"
                aria-label="Mon compte"
              >
                <CircleUserRound className="size-7" aria-hidden="true" />
              </DropdownMenuTrigger>
              <DropdownMenuContent align="end" className="min-w-56">
                <DropdownMenuLabel className="text-sm font-normal break-all">
                  {data.user.email}
                </DropdownMenuLabel>
                <DropdownMenuSeparator />
                <DropdownMenuItem onSelect={deconnexion} className="min-h-12 text-base">
                  <LogOut aria-hidden="true" /> Se déconnecter
                </DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>
          </nav>
        )}
      </div>
    </header>
  );
}
