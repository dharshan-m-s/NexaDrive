import { useState } from "react";
import { api, ApiError } from "../api";
import { PasswordConfirmModal } from "../components/PasswordConfirmModal";
import { useToast } from "../components/Toasts";
import { Card, ErrorBanner, Loading, Pill } from "../components/ui";
import {
  formatBytes,
  formatDateTime,
  formatDuration,
  formatPercent,
  formatRelative,
} from "../format";
import { usePolling } from "../hooks";
import type { DbCheck } from "../types";

export function Service() {
  const toast = useToast();
  const service = usePolling(() => api.service(), 15_000);
  const db = usePolling(() => api.dbIntegrity(false), 60_000);
  const [checking, setChecking] = useState(false);
  const [restartOpen, setRestartOpen] = useState(false);
  const [busy, setBusy] = useState(false);

  const runCheck = async (force: boolean) => {
    setChecking(true);
    try {
      const result: DbCheck = await api.dbIntegrity(force);
      toast.push(
        result.ok ? "Database quick_check passed." : `Database problem: ${result.detail}`,
        result.ok ? "success" : "error",
      );
      db.refresh();
    } catch (err) {
      toast.push(err instanceof ApiError ? err.message : "Check failed.", "error");
    } finally {
      setChecking(false);
    }
  };

  const restart = async (password: string) => {
    setBusy(true);
    try {
      const result = await api.restartService(password, "RESTART");
      toast.push(result.message, "success");
      setRestartOpen(false);
    } catch (err) {
      toast.push(
        err instanceof ApiError ? err.message : "Restart request failed.",
        "error",
      );
    } finally {
      setBusy(false);
    }
  };

  if (service.loading && !service.data) return <Loading label="Loading service status…" />;
  if (service.error && !service.data) return <ErrorBanner message={service.error} />;
  const status = service.data;
  if (!status) return null;

  const diskUsed = status.disk_total_bytes - status.disk_free_bytes;

  return (
    <>
      <Card title={status.unit} action={<Pill kind="success">
        <span className="dot" aria-hidden="true" /> running
      </Pill>}>
        <dl className="kv">
          <dt>Version</dt>
          <dd>
            {status.version} (API {status.api_version})
          </dd>
          <dt>Instance</dt>
          <dd className="t-mono">{status.instance_id}</dd>
          <dt>Process</dt>
          <dd>
            pid {status.pid} · up {formatDuration(status.uptime_seconds)} · started{" "}
            {formatDateTime(status.started_at)}
          </dd>
          <dt>Listening</dt>
          <dd className="t-mono">
            {status.bind_addr} (public) · {status.console_bind_addr} (console)
          </dd>
          <dt>Disk</dt>
          <dd>
            {formatBytes(diskUsed)} used of {formatBytes(status.disk_total_bytes)} on{" "}
            {status.mount ?? "unknown"} ({status.fs_type ?? "unknown"}) ·{" "}
            {formatPercent((diskUsed / Math.max(status.disk_total_bytes, 1)) * 100)} used
          </dd>
        </dl>
      </Card>

      <Card
        title="Database integrity"
        action={
          <button className="btn btn-sm" onClick={() => runCheck(true)} disabled={checking}>
            {checking ? "Checking…" : "Run quick_check"}
          </button>
        }
      >
        {db.loading && !db.data ? (
          <Loading label="Checking database…" />
        ) : db.error && !db.data ? (
          <ErrorBanner message={db.error} />
        ) : db.data ? (
          <div className="spread">
            <Pill kind={db.data.ok ? "success" : "danger"}>
              {db.data.ok ? "healthy" : "problem"}
            </Pill>
            <div className="grow">
              <div className="t-sub">{db.data.detail}</div>
              <div className="t-caption muted">
                Last run {formatRelative(db.data.at)} · file size{" "}
                {formatBytes(db.data.size_bytes)}
              </div>
            </div>
          </div>
        ) : null}
      </Card>

      <Card title="Restart service">
        <p className="t-sub muted" style={{ marginBottom: 12 }}>
          Requests a restart through the fixed helper command configured by the
          administrator. This console connection will briefly drop and
          auto-refresh.
        </p>
        {status.restart_enabled ? (
          <button className="btn btn-danger" onClick={() => setRestartOpen(true)}>
            Restart NexaDrive
          </button>
        ) : (
          <button className="btn btn-danger" disabled>
            Restart disabled
          </button>
        )}
        {!status.restart_enabled && (
          <p className="t-caption muted" style={{ marginTop: 8 }}>
            Restarts are disabled by default. Enable them by setting{" "}
            <code className="t-mono">CONSOLE_ALLOW_RESTART=true</code> and{" "}
            <code className="t-mono">CONSOLE_RESTART_HELPER</code> in{" "}
            <code className="t-mono">/etc/nexadrive/server.env</code>, then reinstalling
            the service.
          </p>
        )}
      </Card>

      {restartOpen && (
        <PasswordConfirmModal
          title="Restart NexaDrive"
          description="The server will stop and come back up within a few seconds. Enter your admin password to request the restart."
          confirmLabel="Restart"
          confirmPhrase="RESTART"
          busy={busy}
          onCancel={() => !busy && setRestartOpen(false)}
          onConfirm={restart}
        />
      )}
    </>
  );
}