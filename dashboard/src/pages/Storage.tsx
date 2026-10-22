import { useEffect, useMemo, useState } from "react";
import { api, ApiError } from "../api";
import { useToast } from "../components/Toasts";
import { Card, EmptyState, ErrorBanner, Loading, Pill } from "../components/ui";
import {
  formatBytes,
  formatDateTime,
  formatNumber,
  formatPercent,
  formatRelative,
} from "../format";
import { usePolling } from "../hooks";
import type { IntegrityResponse } from "../types";

export function Storage() {
  const toast = useToast();
  const summary = usePolling(() => api.storage(), 60_000);
  const users = useMemo(() => summary.data?.users ?? [], [summary.data]);

  const [userId, setUserId] = useState("");
  const [path, setPath] = useState("");
  const [integrity, setIntegrity] = useState<IntegrityResponse | null>(null);
  const [checking, setChecking] = useState(false);

  useEffect(() => {
    if (!userId && users.length > 0) setUserId(users[0]!.user_id);
    if (userId && users.length > 0 && !users.some((user) => user.user_id === userId)) {
      setUserId(users[0]!.user_id);
    }
  }, [users, userId]);

  useEffect(() => {
    setPath("");
    setIntegrity(null);
  }, [userId]);

  const browse = usePolling(
    () => (userId ? api.browse(userId, path) : Promise.resolve(null)),
    30_000,
    [userId, path],
  );

  const runCheck = async () => {
    if (!userId) return;
    setChecking(true);
    try {
      const result = await api.integrity(userId, 500);
      setIntegrity(result);
      toast.push(
        result.issues.length === 0
          ? `Checked ${formatNumber(result.checked)} files — all present.`
          : `Checked ${formatNumber(result.checked)} files — ${formatNumber(result.issues.length)} issue(s).`,
        result.issues.length === 0 ? "success" : "error",
      );
    } catch (err) {
      toast.push(
        err instanceof ApiError ? err.message : "Integrity check failed.",
        "error",
      );
    } finally {
      setChecking(false);
    }
  };

  if (summary.loading && !summary.data) return <Loading label="Scanning storage…" />;
  if (summary.error && !summary.data) return <ErrorBanner message={summary.error} />;
  const data = summary.data;
  if (!data) return null;

  const crumbs: { label: string; path: string }[] = [{ label: "root", path: "" }];
  {
    let accumulated = "";
    for (const segment of path.split("/").filter(Boolean)) {
      accumulated = accumulated ? `${accumulated}/${segment}` : segment;
      crumbs.push({ label: segment, path: accumulated });
    }
  }

  return (
    <>
      <div className="grid">
        <div className="card stat">
          <span className="stat-label">Stored</span>
          <span className="stat-value">{formatBytes(data.total_bytes)}</span>
          <span className="stat-sub">
            {formatNumber(data.total_files)} files · {formatBytes(data.trash_bytes)} in trash
          </span>
        </div>
        <div className="card stat">
          <span className="stat-label">Accounts using storage</span>
          <span className="stat-value">{formatNumber(data.users.length)}</span>
          <span className="stat-sub">Scanned {formatRelative(data.scanned_at)}</span>
        </div>
      </div>

      <Card title="Usage by account">
        {data.users.length === 0 ? (
          <EmptyState title="No accounts" />
        ) : (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>Account</th>
                  <th className="numeric">Files</th>
                  <th className="numeric">Size</th>
                  <th>Quota</th>
                </tr>
              </thead>
              <tbody>
                {data.users.map((user) => {
                  const fraction =
                    user.quota_bytes && user.quota_bytes > 0
                      ? user.bytes / user.quota_bytes
                      : data.total_bytes > 0
                        ? user.bytes / data.total_bytes
                        : 0;
                  return (
                    <tr
                      key={user.user_id}
                      onClick={() => setUserId(user.user_id)}
                      style={{ cursor: "pointer" }}
                    >
                      <td>
                        <div className="row">
                          <span>{user.username}</span>
                          {user.disabled && <Pill kind="warning">disabled</Pill>}
                          {user.user_id === userId && <Pill kind="accent">viewing</Pill>}
                        </div>
                        <div className="bar" style={{ marginTop: 6, maxWidth: 320 }}>
                          <span
                            style={{ width: `${Math.min(100, fraction * 100).toFixed(1)}%` }}
                          />
                        </div>
                      </td>
                      <td className="numeric">{formatNumber(user.files)}</td>
                      <td className="numeric">{formatBytes(user.bytes)}</td>
                      <td>
                        {user.quota_bytes && user.quota_bytes > 0
                          ? `${formatBytes(user.bytes)} of ${formatBytes(user.quota_bytes)} (${formatPercent(fraction * 100, 1)})`
                          : "Unlimited"}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </Card>

      <Card
        title="Browse files"
        action={
          <div className="row">
            <select
              className="select"
              value={userId}
              onChange={(event) => setUserId(event.target.value)}
              aria-label="Account to browse"
            >
              {users.map((user) => (
                <option key={user.user_id} value={user.user_id}>
                  {user.username}
                </option>
              ))}
            </select>
            <button className="btn btn-sm" onClick={runCheck} disabled={!userId || checking}>
              {checking ? "Checking…" : "Verify files"}
            </button>
          </div>
        }
      >
        <div className="breadcrumb" style={{ marginBottom: 10 }}>
          {crumbs.map((crumb, index) => (
            <span key={crumb.path} className="row" style={{ gap: 4 }}>
              {index > 0 && <span className="muted-3">/</span>}
              <button onClick={() => setPath(crumb.path)}>{crumb.label}</button>
            </span>
          ))}
        </div>

        {browse.loading && !browse.data ? (
          <Loading label="Opening folder…" />
        ) : browse.error ? (
          <ErrorBanner message={browse.error} />
        ) : !browse.data || browse.data.entries.length === 0 ? (
          <EmptyState title="Empty folder" detail="Nothing stored at this path yet." />
        ) : (
          <div className="stack" style={{ gap: 2 }}>
            {browse.data.entries.map((entry) => (
              <div
                key={entry.name}
                className={`file-row ${entry.kind === "folder" ? "folder" : ""}`}
                onClick={() => {
                  if (entry.kind !== "folder") return;
                  setPath(path ? `${path}/${entry.name}` : entry.name);
                }}
              >
                <span aria-hidden="true">{entry.kind === "folder" ? "📁" : "📄"}</span>
                <span className="name">{entry.name}</span>
                <span className="t-caption muted">
                  {entry.kind === "folder" ? "folder" : formatBytes(entry.size)}
                </span>
                {entry.modified_at && (
                  <span className="t-caption muted-3" title={formatDateTime(entry.modified_at)}>
                    {formatRelative(entry.modified_at)}
                  </span>
                )}
              </div>
            ))}
            {browse.data.truncated && (
              <p className="t-caption muted">Showing the first 500 entries in this folder.</p>
            )}
          </div>
        )}

        {integrity && (
          <div style={{ marginTop: 16 }}>
            <div className="spread" style={{ marginBottom: 8 }}>
              <strong className="t-sub">
                Verification: {formatNumber(integrity.checked)} checked ·{" "}
                {formatNumber(integrity.missing)} missing ·{" "}
                {formatNumber(integrity.size_mismatch)} size mismatches
              </strong>
              <Pill kind={integrity.issues.length === 0 ? "success" : "danger"}>
                {integrity.issues.length === 0 ? "healthy" : `${integrity.issues.length} issues`}
              </Pill>
            </div>
            {integrity.issues.length > 0 && (
              <div className="table-wrap">
                <table>
                  <thead>
                    <tr>
                      <th>Path</th>
                      <th>Problem</th>
                      <th>Detail</th>
                    </tr>
                  </thead>
                  <tbody>
                    {integrity.issues.map((issue, index) => (
                      <tr key={`${issue.path}-${index}`}>
                        <td className="t-mono">{issue.path}</td>
                        <td>{issue.kind}</td>
                        <td className="muted">{issue.detail}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </div>
        )}
      </Card>
    </>
  );
}