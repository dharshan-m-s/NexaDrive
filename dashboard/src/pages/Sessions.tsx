import { useEffect, useState } from "react";
import { api, ApiError } from "../api";
import { Modal } from "../components/Modal";
import { PasswordConfirmModal } from "../components/PasswordConfirmModal";
import { useToast } from "../components/Toasts";
import { Card, EmptyState, ErrorBanner, Loading, Pill } from "../components/ui";
import { formatDateTime, formatNumber, formatRelative } from "../format";
import { usePolling } from "../hooks";
import type { SessionRow } from "../types";

function statusKind(status: string) {
  return status === "active" ? ("success" as const) : ("neutral" as const);
}

export function Sessions() {
  const toast = useToast();
  const [search, setSearch] = useState("");
  const [query, setQuery] = useState("");
  const [status, setStatus] = useState("");
  const [target, setTarget] = useState<SessionRow | null>(null);
  const [revokeAllOpen, setRevokeAllOpen] = useState(false);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    const timer = window.setTimeout(() => setQuery(search.trim()), 300);
    return () => window.clearTimeout(timer);
  }, [search]);

  const page = usePolling(
    () => api.sessions({ q: query || undefined, status: status || undefined, limit: 100 }),
    15_000,
    [query, status],
  );

  const revokeOne = async () => {
    if (!target) return;
    setBusy(true);
    try {
      await api.revokeSession(target.id);
      toast.push(`Signed out ${target.username}.`, "success");
      setTarget(null);
      page.refresh();
    } catch (err) {
      toast.push(err instanceof ApiError ? err.message : "Could not revoke session.", "error");
    } finally {
      setBusy(false);
    }
  };

  const revokeAll = async (password: string) => {
    setBusy(true);
    try {
      const result = await api.revokeAllSessions(password, "REVOKE_ALL");
      toast.push(
        `Revoked ${formatNumber(result.revoked)} active session(s).`,
        "success",
      );
      setRevokeAllOpen(false);
      page.refresh();
    } catch (err) {
      toast.push(
        err instanceof ApiError ? err.message : "Could not revoke sessions.",
        "error",
      );
    } finally {
      setBusy(false);
    }
  };

  if (page.loading && !page.data) return <Loading label="Loading sessions…" />;
  if (page.error && !page.data) return <ErrorBanner message={page.error} />;
  const data = page.data;

  return (
    <>
      <Card
        title="Sessions"
        action={
          <span className="t-caption muted">
            {data ? `${formatNumber(data.total)} ${query || status ? "matching" : "total"}` : ""}
          </span>
        }
      >
        <div className="toolbar" style={{ marginBottom: 14 }}>
          <input
            className="input"
            placeholder="Search user, device…"
            value={search}
            onChange={(event) => setSearch(event.target.value)}
            aria-label="Search sessions"
          />
          <select
            className="select"
            value={status}
            onChange={(event) => setStatus(event.target.value)}
            aria-label="Filter by status"
          >
            <option value="">All statuses</option>
            <option value="active">Active</option>
            <option value="expired">Expired</option>
          </select>
          <span className="grow" />
          <button
            className="btn btn-danger"
            onClick={() => setRevokeAllOpen(true)}
            disabled={!data || data.items.length === 0}
          >
            Revoke all sessions
          </button>
        </div>

        {!data || data.items.length === 0 ? (
          <EmptyState
            title={query || status ? "No sessions match" : "No sessions yet"}
            detail={
              query || status
                ? "Try a different search or filter."
                : "Clients appear here once they sign in."
            }
          />
        ) : (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>User</th>
                  <th>Device</th>
                  <th>Created</th>
                  <th>Last activity</th>
                  <th>Expires</th>
                  <th>Status</th>
                  <th aria-label="Actions" />
                </tr>
              </thead>
              <tbody>
                {data.items.map((session) => (
                  <tr key={session.id}>
                    <td>
                      <div>{session.display_name}</div>
                      <div className="t-caption muted">{session.username}</div>
                    </td>
                    <td>
                      <div>{session.device_name ?? "—"}</div>
                      <div className="t-caption muted">{session.platform ?? ""}</div>
                    </td>
                    <td title={formatDateTime(session.created_at)}>
                      {formatRelative(session.created_at)}
                    </td>
                    <td title={formatDateTime(session.last_activity_at)}>
                      {formatRelative(session.last_activity_at)}
                    </td>
                    <td title={formatDateTime(session.expires_at)}>
                      {formatRelative(session.expires_at)}
                    </td>
                    <td>
                      <Pill kind={statusKind(session.status)}>{session.status}</Pill>
                    </td>
                    <td style={{ textAlign: "right" }}>
                      {session.status === "active" && (
                        <button
                          className="btn btn-sm btn-ghost"
                          onClick={() => setTarget(session)}
                        >
                          Revoke
                        </button>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>

      {target && (
        <Modal title="Revoke session" onClose={() => !busy && setTarget(null)}>
          <p className="t-sub muted">
            Sign out <strong>{target.display_name}</strong>'s session on{" "}
            {target.device_name ?? "an unnamed device"}? The client will need to
            sign in again. This cannot be undone.
          </p>
          <div className="modal-actions">
            <button className="btn btn-ghost" onClick={() => setTarget(null)} disabled={busy}>
              Cancel
            </button>
            <button className="btn btn-danger" onClick={revokeOne} disabled={busy}>
              {busy ? "Revoking…" : "Revoke session"}
            </button>
          </div>
        </Modal>
      )}

      {revokeAllOpen && (
        <PasswordConfirmModal
          title="Revoke all sessions"
          description="Every active client session will be signed out immediately, including your own devices. Enter your admin password to continue."
          confirmLabel="Revoke all"
          confirmPhrase="REVOKE_ALL"
          busy={busy}
          onCancel={() => !busy && setRevokeAllOpen(false)}
          onConfirm={revokeAll}
        />
      )}
    </>
  );
}