import { useEffect, useState } from "react";
import { api, ApiError, setUnauthorizedHandler } from "./api";
import { ToastProvider } from "./components/Toasts";
import { Loading } from "./components/ui";
import { Audit } from "./pages/Audit";
import { Login } from "./pages/Login";
import { Logs } from "./pages/Logs";
import { Overview } from "./pages/Overview";
import { Service } from "./pages/Service";
import { Sessions } from "./pages/Sessions";
import { Shares } from "./pages/Shares";
import { Storage } from "./pages/Storage";
import { useTheme, type ThemeChoice } from "./hooks";
import type { ConsoleUser } from "./types";

const NAV = [
  { key: "overview", label: "Overview", path: "M3 3h7v7H3zM14 3h7v7h-7zM3 14h7v7H3zM14 14h7v7h-7z" },
  {
    key: "sessions",
    label: "Sessions",
    path: "M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8zM4 21v-1a6 6 0 0 1 6-6h4a6 6 0 0 1 6 6v1",
  },
  {
    key: "shares",
    label: "Shares",
    path: "M10 13a5 5 0 0 0 7 0l2-2a5 5 0 0 0-7-7l-1 1M14 11a5 5 0 0 0-7 0l-2 2a5 5 0 0 0 7 7l1-1",
  },
  {
    key: "storage",
    label: "Storage",
    path: "M3 6a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z",
  },
  {
    key: "audit",
    label: "Audit",
    path: "M8 6h13M8 12h13M8 18h13M3.5 6h.01M3.5 12h.01M3.5 18h.01",
  },
  { key: "logs", label: "Logs", path: "M4 17l6-5-6-5M12 19h8" },
  {
    key: "service",
    label: "Service",
    path: "M4 21v-7M4 10V3M12 21v-9M12 8V3M20 21v-5M20 12V3M1 14h6M9 8h6M17 16h6",
  },
] as const;

type RouteKey = (typeof NAV)[number]["key"];

function readRoute(): RouteKey {
  const value = window.location.hash.replace(/^#\/?/, "");
  return (NAV.some((item) => item.key === value) ? value : "overview") as RouteKey;
}

function Icon({ path }: { path: string }) {
  return (
    <svg
      className="nav-icon"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.8"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <path d={path} />
    </svg>
  );
}

function Shell({ user, onSignOut }: { user: ConsoleUser; onSignOut: () => Promise<void> }) {
  const [route, setRoute] = useState<RouteKey>(readRoute);
  const [theme, setTheme] = useTheme();
  const [signingOut, setSigningOut] = useState(false);

  const signOut = async () => {
    if (signingOut) return;
    setSigningOut(true);
    try {
      await onSignOut();
    } finally {
      setSigningOut(false);
    }
  };

  useEffect(() => {
    const onHash = () => setRoute(readRoute());
    window.addEventListener("hashchange", onHash);
    return () => window.removeEventListener("hashchange", onHash);
  }, []);

  const navigate = (key: RouteKey) => {
    window.location.hash = `#/${key}`;
    setRoute(key);
  };

  const current = NAV.find((item) => item.key === route) ?? NAV[0];

  return (
    <div className="shell">
      <aside className="sidebar">
        <div className="brand">
          <span className="brand-mark" aria-hidden="true">
            N
          </span>
          <div>
            <div className="brand-name">NexaDrive</div>
            <div className="brand-sub">Local console</div>
          </div>
        </div>

        <nav className="nav" aria-label="Console sections">
          {NAV.map((item) => (
            <button
              key={item.key}
              className="nav-item"
              aria-current={route === item.key ? "page" : undefined}
              onClick={() => navigate(item.key)}
            >
              <Icon path={item.path} />
              {item.label}
            </button>
          ))}
        </nav>

        <div className="sidebar-footer">
          <div className="user-chip">
            <strong className="t-sub">{user.display_name || user.username}</strong>
            <span className="t-caption muted">
              {user.username} · {user.role}
            </span>
          </div>
          <div className="segmented" role="group" aria-label="Theme">
            {(["auto", "light", "dark"] as ThemeChoice[]).map((choice) => (
              <button
                key={choice}
                aria-pressed={theme === choice}
                onClick={() => setTheme(choice)}
              >
                {choice}
              </button>
            ))}
          </div>
          <button
            className="btn btn-ghost btn-sm"
            onClick={() => void signOut()}
            disabled={signingOut}
            aria-busy={signingOut}
          >
            {signingOut ? "Signing out…" : "Sign out"}
          </button>
        </div>
      </aside>

      <main className="main">
        <header className="topbar">
          <h1 className="t-title1">{current.label}</h1>
          <span className="pill">
            <span className="dot" aria-hidden="true" /> loopback only
          </span>
        </header>

        <div className="content">
          {route === "overview" && <Overview />}
          {route === "sessions" && <Sessions />}
          {route === "shares" && <Shares />}
          {route === "storage" && <Storage />}
          {route === "audit" && <Audit />}
          {route === "logs" && <Logs />}
          {route === "service" && <Service />}
        </div>
      </main>
    </div>
  );
}

type AuthPhase = "checking" | "signed-in" | "signed-out";

function Console() {
  const [phase, setPhase] = useState<AuthPhase>("checking");
  const [user, setUser] = useState<ConsoleUser | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  useEffect(() => {
    let alive = true;

    // Any later `401` (expired cookie, revoked session) drops straight back to
    // the sign-in screen instead of leaving a dead shell on screen.
    setUnauthorizedHandler(() => {
      if (!alive) return;
      setUser(null);
      setNotice(null);
      setPhase("signed-out");
    });

    api
      .session()
      .then((current) => {
        if (!alive) return;
        setUser(current);
        setPhase("signed-in");
      })
      .catch((err) => {
        if (!alive) return;
        setUser(null);
        if (err instanceof ApiError && err.status !== 401) {
          setNotice(err.message);
        } else if (!(err instanceof ApiError)) {
          setNotice("Could not reach the console server. Is it running?");
        }
        setPhase("signed-out");
      });

    return () => {
      alive = false;
      setUnauthorizedHandler(null);
    };
  }, []);

  const onSignOut = async () => {
    try {
      await api.logout();
    } catch {
      /* Server-side session may already be gone; drop local state regardless. */
    }
    setUser(null);
    setNotice(null);
    setPhase("signed-out");
  };

  if (phase === "checking") {
    return (
      <div className="login-wrap">
        <Loading label="Checking your session…" />
      </div>
    );
  }

  if (phase === "signed-in" && user) {
    return <Shell user={user} onSignOut={onSignOut} />;
  }

  return (
    <Login
      notice={notice}
      onSuccess={(next) => {
        setUser(next);
        setNotice(null);
        setPhase("signed-in");
      }}
    />
  );
}

export function App() {
  return (
    <ToastProvider>
      <Console />
    </ToastProvider>
  );
}