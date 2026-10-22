import { api } from "../api";
import { Sparkline } from "../components/Sparkline";
import { Card, EmptyState, ErrorBanner, Loading, Pill, Stat } from "../components/ui";
import {
  formatBytes,
  formatDateTime,
  formatDuration,
  formatNumber,
  formatPercent,
  formatRelative,
} from "../format";
import { usePolling } from "../hooks";

function outcomeKind(outcome: string | null | undefined) {
  if (outcome === "success") return "success" as const;
  if (outcome === "denied") return "danger" as const;
  if (outcome === "failed") return "warning" as const;
  return "neutral" as const;
}

export function Overview() {
  const overview = usePolling(api.overview, 10_000);
  const metrics = usePolling(() => api.metrics(15), 5_000);

  if (overview.loading && !overview.data) return <Loading label="Loading overview…" />;
  if (overview.error && !overview.data) return <ErrorBanner message={overview.error} />;
  const data = overview.data;
  if (!data) return null;

  const diskUsed = data.disk.total_bytes - data.disk.free_bytes;
  const events = data.recent_events;
  const samples = metrics.data?.samples ?? [];

  return (
    <>
      {data.unavailable.length > 0 && (
        <div className="banner" role="status">
          Some host metrics are unavailable ({data.unavailable.join(", ")}). They
          are shown as “—” rather than estimated.
        </div>
      )}

      <section className="card hero">
        <div className="hero-main">
          <div className="row">
            <Pill kind="success">
              <span className="dot" aria-hidden="true" /> {data.status}
            </Pill>
            <Pill kind="accent">v{data.version}</Pill>
            <Pill>API {data.api_version}</Pill>
          </div>
          <h2 className="t-title1">NexaDrive is running</h2>
          <p className="t-footnote muted">
            Instance {data.instance_id} · pid {data.pid} · up{" "}
            {formatDuration(data.uptime_seconds)} · since {formatDateTime(data.started_at)}
          </p>
        </div>
        <div className="hero-stats">
          <div>
            <div className="stat-label">Listening</div>
            <div className="t-sub t-mono">{data.bind_addr}</div>
          </div>
          <div>
            <div className="stat-label">Console</div>
            <div className="t-sub t-mono">{data.console_bind_addr}</div>
          </div>
          <div>
            <div className="stat-label">Public URL</div>
            <div className="t-sub">
              {data.public_url_configured ? "Configured" : "Not configured"}
            </div>
          </div>
        </div>
      </section>

      {data.auth_failures.length > 0 && (
        <div className="banner" role="alert">
          <strong>Recent sign-in failures.</strong>{" "}
          {data.auth_failures
            .map((failure) => `${failure.subject} (${failure.failures}×)`)
            .join(", ")}
        </div>
      )}

      <div className="grid">
        <Stat
          label="Accounts"
          value={formatNumber(data.users.total)}
          sub={`${data.users.admins} admin · ${data.users.disabled} disabled`}
        />
        <Stat
          label="Active sessions"
          value={formatNumber(data.sessions.active)}
          sub={`${data.sessions.subjects} account(s) signed in · ${data.sessions.expired} expired`}
        />
        <Stat
          label="Storage"
          value={formatBytes(data.files.total_bytes)}
          sub={`${formatNumber(data.files.total_files)} files · ${formatBytes(data.files.trash_bytes)} in trash`}
        />
        <Stat
          label="Disk"
          value={formatPercent(data.disk.used_percent)}
          bar={{ fraction: data.disk.used_percent / 100, tone: data.disk.used_percent > 90 ? "danger" : data.disk.used_percent > 75 ? "warn" : "accent" }}
          sub={`${formatBytes(diskUsed)} used of ${formatBytes(data.disk.total_bytes)}${
            data.disk.mount ? ` on ${data.disk.mount} (${data.disk.fs_type})` : ""
          }`}
        />
        <Stat
          label="Database"
          value={formatBytes(data.database.size_bytes)}
          sub={
            data.database.ok === null
              ? "Integrity check pending"
              : data.database.ok
                ? `quick_check ok${data.database.checked_at ? ` · ${formatRelative(data.database.checked_at)}` : ""}`
                : `Problem: ${data.database.detail ?? "unknown"}`
          }
        />
        <Stat
          label="Requests"
          value={formatNumber(data.activity.requests_total)}
          sub={`${formatNumber(data.activity.requests_5m)} in 5m · ${formatNumber(data.activity.errors_total)} errors · ${data.activity.avg_latency_ms.toFixed(1)} ms avg`}
        />
      </div>

      <Card title="Activity" action={<span className="t-caption muted">last 15 minutes</span>}>
        <div className="grid grid-wide">
          <Sparkline
            samples={samples}
            value={(sample) => sample.requests}
            label="Requests per 5s"
            format={(value) => `${value.toFixed(0)} req`}
          />
          <Sparkline
            samples={samples}
            value={(sample) => sample.latency_ms}
            label="Mean latency"
            format={(value) => `${value.toFixed(1)} ms`}
            color="var(--success)"
          />
          <Sparkline
            samples={samples}
            value={(sample) => sample.cpu_percent}
            label="Machine CPU"
            format={(value) => `${value.toFixed(1)}%`}
            color="var(--warning)"
          />
          <Sparkline
            samples={samples}
            value={(sample) => sample.server_mem_mb}
            label="Server memory"
            format={(value) => `${value.toFixed(0)} MB`}
            color="var(--accent-contrast)"
          />
        </div>
      </Card>

      <Card title="Host" action={<span className="t-caption muted">in-memory, this process only</span>}>
        <dl className="kv">
          <dt>Load average</dt>
          <dd>
            {data.system.load1 === null
              ? "—"
              : `${data.system.load1.toFixed(2)} / ${data.system.load5?.toFixed(2) ?? "—"} / ${data.system.load15?.toFixed(2) ?? "—"}`}
          </dd>
          <dt>Memory</dt>
          <dd>
            {data.system.mem_total_bytes === null
              ? "—"
              : `${formatBytes(data.system.mem_available_bytes)} free of ${formatBytes(data.system.mem_total_bytes)} (${formatPercent(data.system.mem_used_percent)} used)`}
          </dd>
          <dt>Server CPU</dt>
          <dd>
            {data.system.server_cpu_percent === null
              ? "—"
              : formatPercent(data.system.server_cpu_percent, 1)}
          </dd>
          <dt>Server RSS</dt>
          <dd>{formatBytes(data.system.server_mem_bytes)}</dd>
        </dl>
      </Card>

      <Card title="Recent events">
        {events.length === 0 ? (
          <EmptyState title="No audit events yet" />
        ) : (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>When</th>
                  <th>Actor</th>
                  <th>Action</th>
                  <th>Target</th>
                  <th>Outcome</th>
                </tr>
              </thead>
              <tbody>
                {events.map((event) => (
                  <tr key={event.id}>
                    <td title={formatDateTime(event.created_at)}>
                      {formatRelative(event.created_at)}
                    </td>
                    <td>{event.actor ?? "—"}</td>
                    <td className="t-mono">{event.action}</td>
                    <td className="t-mono">{event.target ?? event.path ?? "—"}</td>
                    <td>
                      <Pill kind={outcomeKind(event.outcome)}>
                        {event.outcome ?? "recorded"}
                      </Pill>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>
    </>
  );
}