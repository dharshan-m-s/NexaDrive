import type {
  AuditPage,
  BrowseResponse,
  ConsoleUser,
  DbCheck,
  IntegrityResponse,
  LogResponse,
  LoginResponse,
  MetricsHistory,
  Overview,
  RevokeResponse,
  ServiceStatus,
  SessionsPage,
  SharesPage,
  StorageSummary,
} from "./types";

export class ApiError extends Error {
  status: number;
  constructor(status: number, message: string) {
    super(message);
    this.name = "ApiError";
    this.status = status;
  }
}

/**
 * Extracts the CSRF double-submit token from a cookie string. Exported for
 * tests; the browser path uses `document.cookie`.
 */
export function csrfHeaderFromCookie(cookie: string, name = "nexa_console_csrf"): string | null {
  for (const pair of cookie.split(";")) {
    const [key, ...rest] = pair.split("=");
    if (key?.trim() === name) {
      const value = rest.join("=").trim();
      return value.length > 0 ? value : null;
    }
  }
  return null;
}

let unauthorizedHandler: (() => void) | null = null;

/**
 * Registered by the app shell so any `401` anywhere drops the local session and
 * returns the user to the sign-in screen without every page having to special
 * case it. Pass `null` to unregister.
 */
export function setUnauthorizedHandler(handler: (() => void) | null) {
  unauthorizedHandler = handler;
}

function csrfHeader(): string | undefined {
  if (typeof document === "undefined") return undefined;
  const value = csrfHeaderFromCookie(document.cookie);
  return value ?? undefined;
}

async function request<T>(
  path: string,
  options: { method?: string; body?: unknown } = {},
): Promise<T> {
  const method = options.method ?? "GET";
  const headers: Record<string, string> = {};
  if (options.body !== undefined) headers["content-type"] = "application/json";
  if (method !== "GET" && method !== "HEAD") {
    const csrf = csrfHeader();
    if (csrf) headers["x-csrf-token"] = csrf;
  }

  const response = await fetch(path, {
    method,
    headers,
    credentials: "same-origin",
    body: options.body !== undefined ? JSON.stringify(options.body) : undefined,
  });

  if (!response.ok) {
    let message = `Request failed (${response.status})`;
    try {
      const data = (await response.json()) as { error?: string };
      if (typeof data.error === "string" && data.error.length > 0) message = data.error;
    } catch {
      /* non-JSON error body */
    }
    if (response.status === 401) unauthorizedHandler?.();
    throw new ApiError(response.status, message);
  }
  if (response.status === 204) return undefined as T;
  return (await response.json()) as T;
}

function query(params: Record<string, string | number | undefined | null>): string {
  const search = new URLSearchParams();
  for (const [key, value] of Object.entries(params)) {
    if (value !== undefined && value !== null && value !== "") search.set(key, String(value));
  }
  const encoded = search.toString();
  return encoded ? `?${encoded}` : "";
}

export const api = {
  login: (username: string, password: string) =>
    request<LoginResponse>("/api/console/login", {
      method: "POST",
      body: { username, password },
    }),
  logout: () => request<void>("/api/console/logout", { method: "POST" }),
  session: () => request<ConsoleUser>("/api/console/session"),

  overview: () => request<Overview>("/api/console/overview"),
  metrics: (minutes = 15) =>
    request<MetricsHistory>(`/api/console/metrics${query({ minutes })}`),

  sessions: (params: { q?: string; status?: string; limit?: number; offset?: number } = {}) =>
    request<SessionsPage>(`/api/console/sessions${query(params)}`),
  revokeSession: (id: string) =>
    request<RevokeResponse>(`/api/console/sessions/${encodeURIComponent(id)}`, {
      method: "DELETE",
    }),
  revokeAllSessions: (password: string, confirm: string) =>
    request<RevokeResponse>("/api/console/sessions/revoke-all", {
      method: "POST",
      body: { password, confirm },
    }),

  shares: (params: { limit?: number; offset?: number } = {}) =>
    request<SharesPage>(`/api/console/shares${query(params)}`),
  revokeShare: (id: string) =>
    request<void>(`/api/console/shares/${encodeURIComponent(id)}`, { method: "DELETE" }),

  storage: () => request<StorageSummary>("/api/console/storage"),
  browse: (userId: string, path = "") =>
    request<BrowseResponse>(`/api/console/storage/browse${query({ user: userId, path })}`),
  integrity: (userId: string, limit = 500) =>
    request<IntegrityResponse>(`/api/console/storage/integrity${query({ user: userId, limit })}`),

  audit: (params: { q?: string; outcome?: string; limit?: number; offset?: number } = {}) =>
    request<AuditPage>(`/api/console/audit${query(params)}`),

  service: () => request<ServiceStatus>("/api/console/service"),
  logs: (limit = 200) => request<LogResponse>(`/api/console/service/logs${query({ limit })}`),
  restartService: (password: string, confirm: string) =>
    request<{ accepted: boolean; message: string }>("/api/console/service/restart", {
      method: "POST",
      body: { password, confirm },
    }),

  dbIntegrity: (force = false) =>
    request<DbCheck>(`/api/console/database/integrity${query({ force: force ? "true" : undefined })}`),
};