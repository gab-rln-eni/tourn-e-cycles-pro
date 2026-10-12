import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import {
  Outlet,
  Link,
  createRootRouteWithContext,
  useRouter,
  HeadContent,
  Scripts,
  type ErrorComponentProps,
} from "@tanstack/react-router";
import { useEffect, type ReactNode } from "react";

import appCss from "../styles.css?url";
import { reportLovableError } from "../lib/lovable-error-reporting";
import { supabase } from "@/integrations/supabase/client";
import { SiteHeader } from "@/components/SiteHeader";
import { SiteFooter } from "@/components/SiteFooter";
import { Toaster } from "@/components/ui/sonner";

function NotFoundComponent() {
  return (
    <div className="flex min-h-[50vh] items-center justify-center px-4">
      <div className="max-w-md text-center">
        <h1 className="text-3xl font-bold">Page introuvable</h1>
        <Link to="/" className="mt-6 inline-flex min-h-12 items-center rounded-lg bg-primary px-5 font-bold text-primary-foreground">
          Retour à l'accueil
        </Link>
      </div>
    </div>
  );
}

function ErrorComponent({ error, reset }: ErrorComponentProps) {
  console.error(error);
  const router = useRouter();
  useEffect(() => {
    reportLovableError(error, { boundary: "tanstack_root_error_component" });
  }, [error]);

  return (
    <div className="flex min-h-[50vh] items-center justify-center px-4">
      <div className="max-w-md text-center">
        <h1 className="text-xl font-bold">Cette page ne s'est pas chargée</h1>
        <p className="mt-2">Réessayez ou revenez à l'accueil.</p>
        <div className="mt-6 flex flex-wrap justify-center gap-2">
          <button
            onClick={() => {
              router.invalidate();
              reset();
            }}
            className="min-h-12 rounded-lg bg-primary px-5 font-bold text-primary-foreground"
          >
            Réessayer
          </button>
          <a href="/" className="inline-flex min-h-12 items-center rounded-lg border-2 border-primary px-5 font-bold text-primary-text">
            Accueil
          </a>
        </div>
      </div>
    </div>
  );
}

export const Route = createRootRouteWithContext<{ queryClient: QueryClient }>()({
  head: () => ({
    meta: [
      { charSet: "utf-8" },
      { name: "viewport", content: "width=device-width, initial-scale=1" },
      { title: "Tournée Cycles" },
      { name: "description", content: "L'atelier vélo qui vient à vous, à Lyon." },
      { property: "og:title", content: "Tournée Cycles" },
      { property: "og:description", content: "L'atelier vélo qui vient à vous, à Lyon." },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary_large_image" },
    ],
    links: [
      { rel: "preconnect", href: "https://fonts.googleapis.com" },
      { rel: "preconnect", href: "https://fonts.gstatic.com", crossOrigin: "anonymous" },
      {
        rel: "stylesheet",
        href: "https://fonts.googleapis.com/css2?family=Atkinson+Hyperlegible:wght@400;700&display=swap",
      },
      { rel: "stylesheet", href: appCss },
      { rel: "icon", href: "/favicon.ico", type: "image/x-icon" },
    ],
  }),
  shellComponent: RootShell,
  component: RootComponent,
  notFoundComponent: NotFoundComponent,
  errorComponent: ErrorComponent,
});

function RootShell({ children }: { children: ReactNode }) {
  return (
    <html lang="fr">
      <head>
        <HeadContent />
      </head>
      <body>
        {children}
        <Scripts />
      </body>
    </html>
  );
}

function RootComponent() {
  const { queryClient } = Route.useRouteContext();
  const router = useRouter();

  useEffect(() => {
    const { data } = supabase.auth.onAuthStateChange((event) => {
      if (event !== "SIGNED_IN" && event !== "SIGNED_OUT" && event !== "USER_UPDATED") return;
      router.invalidate();
      if (event !== "SIGNED_OUT") queryClient.invalidateQueries();
    });
    return () => data.subscription.unsubscribe();
  }, [router, queryClient]);

  return (
    <QueryClientProvider client={queryClient}>
      <div className="flex min-h-screen flex-col">
        <a href="#contenu" className="sr-only focus:not-sr-only focus:p-3">
          Aller au contenu
        </a>
        <SiteHeader />
        <main id="contenu" className="mx-auto w-full max-w-3xl flex-1 px-4 py-6">
          <Outlet />
        </main>
        <SiteFooter />
      </div>
      <Toaster position="top-center" richColors />
    </QueryClientProvider>
  );
}
