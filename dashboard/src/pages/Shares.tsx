import { useState } from "react";
import { api, ApiError } from "../api";
import { Modal } from "../components/Modal";
import { useToast } from "../components/Toasts";
import { Card, EmptyState, ErrorBanner, Loading, Pill } from "../components/ui";
import { formatDateTime, formatNumber, formatRelative } from "../format";
import { usePolling } from "../hooks";
import type { ShareRow } from "../types";

export function Shares() {
  const toast = useToast();
  const [target, setTarget] = useState<ShareRow | null>(null);
  const [busy, setBusy] = useState(false);

  const page = usePolling(() => api.shares({ limit: 100 }), 30_000);

  const revoke = async () => {
    if (!target) return;
    setBusy(true);
    try {
      await api.revokeShare(target.id);
      toast.push("Share revoked.", "success");
      setTarget(null);
      page.refresh();
    } catch (err) {
      toast.push(err instanceof ApiError ? err.message : "Could not revoke share.", "error");
    } finally {
      setBusy(false);
    }
  };

  if (page.loading && !page.data) return <Loading label="Loading shares…" />;
  if (page.error && !page.data) return <ErrorBanner message={page.error} />;
  const data = page.data;

  return (
    <>
      <Card
        title="Shares"
        action={
          <span className="t-caption muted">
            {data ? `${formatNumber(data.total)} active` : ""}
          </span>
        }
      >
        {!data || data.items.length === 0 ? (
          <EmptyState
            title="Nothing is shared"
            detail="Links and user-to-user shares appear here."
          />
        ) : (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>Path</th>
                  <th>Owner</th>
                  <th>Recipient</th>
                  <th>Permission</th>
                  <th>Type</th>
                  <th>Created</th>
                  <th>Expires</th>
                  <th aria-label="Actions" />
                </tr>
              </thead>
              <tbody>
                {data.items.map((share) => (
                  <tr key={share.id}>
                    <td className="t-mono">{share.path}</td>
                    <td>{share.owner}</td>
                    <td>{share.recipient ?? "—"}</td>
                    <td>
                      <Pill kind="accent">{share.permission}</Pill>
                    </td>
                    <td>{share.is_link ? "Link" : "Direct"}</td>
                    <td title={formatDateTime(share.created_at)}>
                      {formatRelative(share.created_at)}
                    </td>
                    <td title={share.expires_at ? formatDateTime(share.expires_at) : undefined}>
                      {share.expires_at ? formatRelative(share.expires_at) : "Never"}
                    </td>
                    <td style={{ textAlign: "right" }}>
                      <button className="btn btn-sm btn-ghost" onClick={() => setTarget(share)}>
                        Revoke
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>

      {target && (
        <Modal title="Revoke share" onClose={() => !busy && setTarget(null)}>
          <p className="t-sub muted">
            Revoke access to <code className="t-mono">{target.path}</code>
            {target.recipient ? ` for ${target.recipient}` : ""}? Anyone using this
            share or link will lose access immediately.
          </p>
          <div className="modal-actions">
            <button className="btn btn-ghost" onClick={() => setTarget(null)} disabled={busy}>
              Cancel
            </button>
            <button className="btn btn-danger" onClick={revoke} disabled={busy}>
              {busy ? "Revoking…" : "Revoke share"}
            </button>
          </div>
        </Modal>
      )}
    </>
  );
}