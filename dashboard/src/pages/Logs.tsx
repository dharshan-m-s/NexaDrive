import { useState } from "react";
import { api } from "../api";
import { Card, EmptyState, ErrorBanner, Loading } from "../components/ui";
import { usePolling } from "../hooks";

export function Logs() {
  const [limit, setLimit] = useState(200);
  const [auto, setAuto] = useState(true);

  const logs = usePolling(() => api.logs(limit), auto ? 5_000 : 0, [limit, auto]);

  return (
    <Card
      title="Service logs"
      action={
        <div className="row">
          <label className="t-footnote muted row" style={{ gap: 6 }}>
            <input
              type="checkbox"
              checked={auto}
              onChange={(event) => setAuto(event.target.checked)}
            />
            Live
          </label>
          <select
            className="select"
            value={limit}
            onChange={(event) => setLimit(Number(event.target.value))}
            aria-label="Number of lines"
          >
            <option value={100}>100 lines</option>
            <option value={200}>200 lines</option>
            <option value={500}>500 lines</option>
          </select>
          <button className="btn btn-sm" onClick={logs.refresh}>
            Refresh
          </button>
        </div>
      }
    >
      {logs.loading && !logs.data ? (
        <Loading label="Reading logs…" />
      ) : logs.error && !logs.data ? (
        <ErrorBanner message={logs.error} />
      ) : !logs.data || logs.data.lines.length === 0 ? (
        <EmptyState title="No log lines" detail="Nothing has been logged recently." />
      ) : (
        <>
          <div className="logview" role="log" aria-label="Recent server log output">
            {logs.data.lines.map((line, index) => (
              <span
                key={index}
                className={`logline ${/denied|error|warn/i.test(line) ? "denied" : ""}`}
              >
                {line}
              </span>
            ))}
          </div>
          <p className="t-caption muted" style={{ marginTop: 10 }}>
            Newest first. {logs.data.note}
          </p>
        </>
      )}
    </Card>
  );
}