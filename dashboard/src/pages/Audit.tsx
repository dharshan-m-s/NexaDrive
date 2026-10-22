import { useEffect, useState } from "react";
import { api } from "../api";
import { Card, EmptyState, ErrorBanner, Loading, Pill } from "../components/ui";
import { formatDateTime, formatNumber, formatRelative } from "../format";
import { usePolling } from "../hooks";

const PAGE_SIZE = 50;

function outcomeKind(outcome: string | null | undefined) {
  if (outcome === "success") return "success" as const;
  if (outcome === "denied") return "danger" as const;
  if (outcome === "failed") return "warning" as const;
  return "neutral" as const;
}

export function Audit() {
  const [search, setSearch] = useState("");
  const [query, setQuery] = useState("");
  const [outcome, setOutcome] = useState("");
  const [offset, setOffset] = useState(0);

  useEffect(() => {
    const timer = window.setTimeout(() => {
      setQuery(search.trim());
      setOffset(0);
    }, 300);
    return () => window.clearTimeout(timer);
  }, [search]);

  useEffect(() => setOffset(0), [outcome]);

  const page = usePolling(
    () =>
      api.audit({
        q: query || undefined,
        outcome: outcome || undefined,
        limit: PAGE_SIZE,
        offset,
      }),
    30_000,
    [query, outcome, offset],
  );

  if (page.loading && !page.data) return <Loading label="Loading audit log…" />;
  if (page.error && !page.data) return <ErrorBanner message={page.error} />;
  const data = page.data;
  if (!data) return null;

  const from = data.total === 0 ? 0 : offset + 1;
  const to = Math.min(offset + PAGE_SIZE, data.total);

  return (
    <Card
      title="Audit log"
      action={
        <span className="t-caption muted">
          {formatNumber(from)}–{formatNumber(to)} of {formatNumber(data.total)}
        </span>
      }
    >
      <div className="toolbar" style={{ marginBottom: 14 }}>
        <input
          className="input"
          placeholder="Search actor, action, target…"
          value={search}
          onChange={(event) => setSearch(event.target.value)}
          aria-label="Search audit log"
        />
        <select
          className="select"
          value={outcome}
          onChange={(event) => setOutcome(event.target.value)}
          aria-label="Filter by outcome"
        >
          <option value="">All outcomes</option>
          <option value="success">Success</option>
          <option value="denied">Denied</option>
          <option value="failed">Failed</option>
        </select>
        <span className="grow" />
        <button
          className="btn btn-sm"
          onClick={() => setOffset(Math.max(0, offset - PAGE_SIZE))}
          disabled={offset === 0}
        >
          Newer
        </button>
        <button
          className="btn btn-sm"
          onClick={() => setOffset(offset + PAGE_SIZE)}
          disabled={to >= data.total}
        >
          Older
        </button>
      </div>

      {data.items.length === 0 ? (
        <EmptyState
          title="No matching events"
          detail={query || outcome ? "Try different filters." : undefined}
        />
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
                <th>Detail</th>
              </tr>
            </thead>
            <tbody>
              {data.items.map((event) => (
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
                  <td className="muted">{event.detail ?? ""}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </Card>
  );
}