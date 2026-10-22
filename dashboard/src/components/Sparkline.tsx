import type { MetricSample } from "../types";

interface SparklineProps {
  samples: MetricSample[];
  value: (sample: MetricSample) => number | null;
  label: string;
  format: (value: number) => string;
  color?: string;
  height?: number;
}

const WIDTH = 600;

/**
 * A dependency-free area sparkline. Missing points are skipped; the chart is
 * only drawn when at least two real samples exist, otherwise an honest
 * "collecting" note is shown.
 */
export function Sparkline({
  samples,
  value,
  label,
  format,
  color = "var(--accent)",
  height = 96,
}: SparklineProps) {
  const points = samples
    .map((sample) => ({ at: sample.at, value: value(sample) }))
    .filter((point): point is { at: string; value: number } => point.value !== null);

  const latest = points.length > 0 ? points[points.length - 1]!.value : null;

  if (points.length < 2) {
    return (
      <div>
        <div className="spread">
          <span className="t-footnote muted">{label}</span>
          <span className="grow" />
          <span className="t-footnote muted">
            {latest !== null ? format(latest) : "collecting samples…"}
          </span>
        </div>
        <div className="chart-empty">Collecting samples every 5 seconds…</div>
      </div>
    );
  }

  const max = Math.max(...points.map((point) => point.value), 0.00001);
  const stepX = WIDTH / (points.length - 1);
  const line = points
    .map((point, index) => {
      const x = index * stepX;
      const y = height - (point.value / max) * (height - 8) - 4;
      return `${index === 0 ? "M" : "L"}${x.toFixed(1)},${y.toFixed(1)}`;
    })
    .join(" ");
  const area = `${line} L${WIDTH},${height} L0,${height} Z`;

  return (
    <div>
      <div className="spread">
        <span className="t-footnote muted">{label}</span>
        <span className="grow" />
        <span className="t-footnote" style={{ fontVariantNumeric: "tabular-nums" }}>
          {latest !== null ? format(latest) : "—"}
        </span>
      </div>
      <svg
        className="chart"
        viewBox={`0 0 ${WIDTH} ${height}`}
        preserveAspectRatio="none"
        role="img"
        aria-label={`${label} over the last ${points.length * 5} seconds`}
      >
        <path d={area} fill={color} opacity="0.14" />
        <path d={line} fill="none" stroke={color} strokeWidth="2" />
      </svg>
    </div>
  );
}