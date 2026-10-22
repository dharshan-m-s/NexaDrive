import { useState, type FormEvent } from "react";
import { api, ApiError } from "../api";
import type { ConsoleUser } from "../types";

interface LoginProps {
  onSuccess: (user: ConsoleUser) => void;
  /** A message about the *initial* session probe, shown until the first submit. */
  notice?: string | null;
}

/**
 * Sign-in screen for the loopback console. The server is the authority: this
 * only collects credentials and turns the response into a session for the rest
 * of the shell. Errors are announced inline so they are readable by a screen
 * reader as well as on screen.
 */
export function Login({ onSuccess, notice }: LoginProps) {
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const banner = error ?? notice ?? null;

  const canSubmit = username.trim().length > 0 && password.length > 0 && !busy;

  const submit = async (event: FormEvent) => {
    event.preventDefault();
    if (!canSubmit) return;
    setBusy(true);
    setError(null);
    try {
      const { user } = await api.login(username.trim(), password);
      onSuccess(user);
    } catch (err) {
      setError(
        err instanceof ApiError
          ? err.message
          : "Could not reach the console server. Is it running?",
      );
      setBusy(false);
    }
  };

  return (
    <div className="login-wrap">
      <main className="login-card">
        <div className="login-brand">
          <span className="login-mark" aria-hidden="true">
            N
          </span>
          <div>
            <h1 className="brand-name">NexaDrive</h1>
            <div className="brand-sub">Administrator console</div>
          </div>
        </div>

        <form className="stack" onSubmit={submit} noValidate>
          <div className="field">
            <label htmlFor="console-username">Username</label>
            <input
              id="console-username"
              className="input"
              type="text"
              autoComplete="username"
              autoCapitalize="none"
              spellCheck={false}
              autoFocus
              value={username}
              onChange={(event) => setUsername(event.target.value)}
              disabled={busy}
              required
            />
          </div>

          <div className="field">
            <label htmlFor="console-password">Password</label>
            <input
              id="console-password"
              className="input"
              type="password"
              autoComplete="current-password"
              value={password}
              onChange={(event) => setPassword(event.target.value)}
              disabled={busy}
              required
            />
          </div>

          {banner && (
            <div className="banner error" role="alert">
              {banner}
            </div>
          )}

          <button
            type="submit"
            className="btn btn-primary"
            disabled={!canSubmit}
            aria-busy={busy}
          >
            {busy ? "Signing in…" : "Sign in"}
          </button>
        </form>

        <p className="t-footnote muted">
          Sign-in is limited to administrators and served from this machine only.
        </p>
      </main>
    </div>
  );
}
