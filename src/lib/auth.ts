import { redirect } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import type { User } from "@supabase/supabase-js";
import { supabase } from "@/integrations/supabase/client";
import type { Database } from "@/integrations/supabase/types";

export type AppRole = Database["public"]["Enums"]["app_role"];

export type AuthInfo = { user: User | null; roles: AppRole[] };

export async function fetchAuth(): Promise<AuthInfo> {
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return { user: null, roles: [] };
  const { data } = await supabase.rpc("mes_roles");
  return { user, roles: (data ?? []) as AppRole[] };
}

export function useAuth() {
  return useQuery({
    queryKey: ["auth"],
    queryFn: fetchAuth,
    enabled: typeof window !== "undefined",
    staleTime: 30_000,
  });
}

/** beforeLoad gate: redirects to "/" if the user lacks every allowed role. */
export function requireRoles(allowed: AppRole[]) {
  return async () => {
    const info = await fetchAuth();
    if (!info.user || !info.roles.some((r) => allowed.includes(r))) {
      throw redirect({ to: "/" });
    }
    return { auth: info as { user: User; roles: AppRole[] } };
  };
}

export function homeFor(roles: AppRole[]): "/journee" | "/bureau" | null {
  if (roles.includes("dirigeant") || roles.includes("mecanicien")) return "/journee";
  if (roles.includes("atelier")) return "/bureau";
  return null;
}

export function useEmail(userId: string | null | undefined) {
  return useQuery({
    queryKey: ["email", userId],
    enabled: !!userId,
    staleTime: Infinity,
    queryFn: async () => {
      const { data } = await supabase.rpc("email_utilisateur", { p_user: userId! });
      return data ?? "";
    },
  });
}
