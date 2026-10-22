import type { ReactNode } from "react";

export function Card({
  title,
  action,
  children,
  wide = false,
}: {
  title?: string;
  action?: ReactNode;
  children: ReactNode;
  wide?: boolean;
}) {
  return (
    <section className={`card ${wide ? "" : ""}`}>
      {title && (
        <header className="card-header">
          <h2 className="t-headline">{title}</h2>
          {action}
        </header>
      )}
      <div className="card-body">{children}</div>
    </section>
  );
}

export function Stat({
  label,
  value,
  sub,
  bar,
}: {
  label: string;
  value: string;
  sub?: string;
  bar?: { fraction: number; tone?: "accent" | "warn" | "danger" };
}) {
  return (
    <div className="card stat">
      <span className="stat-label">{label}</span>
      <span className="stat-value">{value}</span>
      {bar && (
        <div className={`bar ${bar.tone && bar.tone !== "accent" ? bar.tone : ""}`}>
          <span
            style={{
              width: `${Math.min(100, Math.max(0, bar.fraction * 100)).toFixed(1)}%`,
            }}
          />
        </div>
      )}
      {sub && <span className="stat-sub">{sub}</span>}
    </div>
  );
}

export function Pill({
  kind = "neutral",
  children,
}: {
  kind?: "neutral" | "success" | "warning" | "danger" | "accent";
  children: ReactNode;
}) {
  return <span className={`pill ${kind === "neutral" ? "" : kind}`}>{children}</span>;
}

export function Loading({ label = "Loading…" }: { label?: string }) {
  return (
    <div className="empty" role="status">
      <span className="spinner" aria-hidden="true" />
      <span>{label}</span>
    </div>
  );
}

export function Skeleton({ height = 16 }: { height?: number }) {
  return <div className="skeleton" style={{ height }} aria-hidden="true" />;
}

export function EmptyState({
  title,
  detail,
}: {
  title: string;
  detail?: string;
}) {
  return (
    <div className="empty">
      <strong className="t-body">{title}</strong>
      {detail && <span className="t-footnote">{detail}</span>}
    </div>
  );
}

export function ErrorBanner({ message }: { message: string }) {
  return (
    <div className="banner error" role="alert">
      {message}
    </div>
  );
}