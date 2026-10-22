export interface ConsoleUser {
  id: string;
  username: string;
  display_name: string;
  role: string;
}

export interface LoginResponse {
  user: ConsoleUser;
  csrf_token: string;
}

export interface UserCounts {
  total: number;
  admins: number;
  disabled: number;
}

export interface SessionCounts {
  active: number;
  expired: number;
  subjects: number;
}

export interface FileCounts {
  total_files: number;
  total_bytes: number;
  trash_bytes: number;
}

export interface DiskStats {
  mount: string | null;
  fs_type: string | null;
  total_bytes: number;
  free_bytes: number;
  used_percent: number;
}

export interface DbStats {
  size_bytes: number;
  ok: boolean | null;
  detail: string | null;
  checked_at: string | null;
}

export interface SystemStats {
  cpu_percent: number | null;
  load1: number | null;
  load5: number | null;
  load15: number | null;
  mem_total_bytes: number | null;
  mem_available_bytes: number | null;
  mem_used_percent: number | null;
  server_cpu_percent: number | null;
  server_mem_bytes: number | null;
}

export interface ActivityStats {
  requests_total: number;
  errors_total: number;
  avg_latency_ms: number;
  requests_5m: number;
  errors_5m: number;
}

export interface AuthFailure {
  subject: string;
  failures: number;
  window_age_seconds: number;
}

export interface AuditEvent {
  id: string;
  actor?: string | null;
  action: string;
  path?: string | null;
  target?: string | null;
  outcome?: string | null;
  detail?: string | null;
  created_at: string;
}

export interface Overview {
  status: string;
  version: string;
  api_version: string;
  instance_id: string;
  started_at: string;
  uptime_seconds: number;
  pid: number;
  bind_addr: string;
  console_bind_addr: string;
  public_url_configured: boolean;
  users: UserCounts;
  sessions: SessionCounts;
  files: FileCounts;
  disk: DiskStats;
  database: DbStats;
  system: SystemStats;
  activity: ActivityStats;
  auth_failures: AuthFailure[];
  recent_events: AuditEvent[];
  unavailable: string[];
}

export interface MetricSample {
  at: string;
  requests: number;
  errors: number;
  latency_ms: number | null;
  cpu_percent: number | null;
  mem_used_mb: number | null;
  mem_total_mb: number | null;
  server_cpu_percent: number | null;
  server_mem_mb: number | null;
  disk_free_gb: number | null;
  disk_total_gb: number | null;
}

export interface MetricsHistory {
  samples: MetricSample[];
  interval_seconds: number;
}

export interface SessionRow {
  id: string;
  user_id: string;
  username: string;
  display_name: string;
  created_at: string;
  last_activity_at: string;
  expires_at: string;
  status: "active" | "expired" | string;
  device_name: string | null;
  platform: string | null;
}

export interface SessionsPage {
  items: SessionRow[];
  total: number;
}

export interface ShareRow {
  id: string;
  path: string;
  permission: string;
  is_link: boolean;
  owner: string;
  recipient: string | null;
  created_at: string;
  expires_at: string | null;
}

export interface SharesPage {
  items: ShareRow[];
  total: number;
}

export interface UserStorage {
  user_id: string;
  username: string;
  disabled: boolean;
  bytes: number;
  files: number;
  quota_bytes: number | null;
}

export interface StorageSummary {
  total_bytes: number;
  total_files: number;
  trash_bytes: number;
  users: UserStorage[];
  scanned_at: string;
}

export interface BrowseEntry {
  name: string;
  kind: "folder" | "file" | string;
  size: number;
  modified_at: string | null;
}

export interface BrowseResponse {
  user_id: string;
  username: string;
  path: string;
  parent: string | null;
  entries: BrowseEntry[];
  truncated: boolean;
}

export interface IntegrityIssue {
  path: string;
  kind: string;
  detail: string;
}

export interface IntegrityResponse {
  user_id: string;
  checked: number;
  missing: number;
  size_mismatch: number;
  issues: IntegrityIssue[];
  truncated: boolean;
  dry_run: boolean;
}

export interface ServiceStatus {
  unit: string;
  pid: number;
  version: string;
  api_version: string;
  instance_id: string;
  started_at: string;
  uptime_seconds: number;
  bind_addr: string;
  console_bind_addr: string;
  mount: string | null;
  fs_type: string | null;
  disk_total_bytes: number;
  disk_free_bytes: number;
  restart_enabled: boolean;
}

export interface LogResponse {
  lines: string[];
  note: string;
}

export interface DbCheck {
  ok: boolean;
  detail: string;
  size_bytes: number;
  at: string;
}

export interface AuditPage {
  items: AuditEvent[];
  total: number;
}

export interface RevokeResponse {
  revoked: number;
}