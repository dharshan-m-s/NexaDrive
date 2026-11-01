import { useCallback, useEffect, useRef, useState } from "react";

export interface PollState<T> {
  data: T | null;
  error: string | null;
  loading: boolean;
  refresh: () => void;
}

/**
 * Loads data immediately and then every `intervalMs`, staying quiet about
 * transient refresh failures once a first successful payload exists.
 */
export function usePolling<T>(
  loader: () => Promise<T>,
  intervalMs: number,
  deps: unknown[] = [],
): PollState<T> {
  const [data, setData] = useState<T | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const loaderRef = useRef(loader);
  loaderRef.current = loader;
  const hasDataRef = useRef(false);
  const inFlightRef = useRef(false);
  const [tick, setTick] = useState(0);

  const refresh = useCallback(() => setTick((t) => t + 1), []);

  useEffect(() => {
    let cancelled = false;
    let timer: number | undefined;

    const run = async () => {
      // A manual refresh or dependency change can restart this effect while
      // the previous request is still in flight. Do not overlap those calls.
      if (inFlightRef.current) {
        if (!cancelled && intervalMs > 0) {
          timer = window.setTimeout(() => void run(), intervalMs);
        }
        return;
      }
      inFlightRef.current = true;
      try {
        const value = await loaderRef.current();
        if (cancelled) return;
        hasDataRef.current = true;
        setData(value);
        setError(null);
      } catch (err) {
        if (cancelled) return;
        if (!hasDataRef.current) {
          setError(err instanceof Error ? err.message : "Request failed");
        }
      } finally {
        inFlightRef.current = false;
        if (!cancelled) {
          setLoading(false);
          if (intervalMs > 0) {
            timer = window.setTimeout(() => void run(), intervalMs);
          }
        }
      }
    };

    void run();
    return () => {
      cancelled = true;
      if (timer !== undefined) window.clearTimeout(timer);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [intervalMs, tick, ...deps]);

  return { data, error, loading, refresh };
}

/** Tracks a CSS media query. */
export function useMediaQuery(query: string): boolean {
  const [matches, setMatches] = useState(() =>
    typeof window !== "undefined" ? window.matchMedia(query).matches : false,
  );
  useEffect(() => {
    const list = window.matchMedia(query);
    const handler = (event: MediaQueryListEvent) => setMatches(event.matches);
    setMatches(list.matches);
    list.addEventListener("change", handler);
    return () => list.removeEventListener("change", handler);
  }, [query]);
  return matches;
}

export type ThemeChoice = "auto" | "light" | "dark";

/** Applies the theme choice to <html data-theme> and remembers it. */
export function useTheme(): [ThemeChoice, (choice: ThemeChoice) => void] {
  const [choice, setChoice] = useState<ThemeChoice>(() => {
    const stored = localStorage.getItem("nexa-console-theme");
    return stored === "light" || stored === "dark" ? stored : "auto";
  });
  const prefersDark = useMediaQuery("(prefers-color-scheme: dark)");

  useEffect(() => {
    const resolved = choice === "auto" ? (prefersDark ? "dark" : "light") : choice;
    document.documentElement.dataset.theme = resolved;
  }, [choice, prefersDark]);

  const choose = useCallback((next: ThemeChoice) => {
    setChoice(next);
    if (next === "auto") localStorage.removeItem("nexa-console-theme");
    else localStorage.setItem("nexa-console-theme", next);
  }, []);

  return [choice, choose];
}