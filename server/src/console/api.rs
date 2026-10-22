use std::path::{Path, PathBuf};

use axum::{
    Json,
    extract::{Extension, Path as AxumPath, Query, State},
    http::StatusCode,
};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    API_VERSION,
    error::AppError,
    handlers::admin::audit_event,
    metrics::{mount_info, read_disk, read_loadavg, read_meminfo},
    models::{AuditResponse, RevokeSessionsResponse},
    paths::{safe_relative_path, user_root},
    state::AppState,
    storage_stats,
};

// ============================================================== overview

#[derive(Serialize)]
pub(crate) struct UserCounts {
    pub(crate) total: i64,
    pub(crate) admins: i64,
    pub(crate) disabled: i64,
}

#[derive(Serialize)]
pub(crate) struct SessionCounts {
    pub(crate) active: i64,
    pub(crate) expired: i64,
    pub(crate) subjects: i64,
}

#[derive(Serialize)]
pub(crate) struct FileCounts {
    pub(crate) total_files: u64,
    pub(crate) total_bytes: u64,
    pub(crate) trash_bytes: u64,
}

#[derive(Serialize)]
pub(crate) struct DiskStats {
    pub(crate) mount: Option<String>,
    pub(crate) fs_type: Option<String>,
    pub(crate) total_bytes: u64,
    pub(crate) free_bytes: u64,
    pub(crate) used_percent: f64,
}

#[derive(Serialize)]
pub(crate) struct DbStats {
    pub(crate) size_bytes: u64,
    pub(crate) ok: Option<bool>,
    pub(crate) detail: Option<String>,
    pub(crate) checked_at: Option<DateTime<Utc>>,
}

#[derive(Serialize)]
pub(crate) struct SystemStats {
    pub(crate) cpu_percent: Option<f64>,
    pub(crate) load1: Option<f64>,
    pub(crate) load5: Option<f64>,
    pub(crate) load15: Option<f64>,
    pub(crate) mem_total_bytes: Option<u64>,
    pub(crate) mem_available_bytes: Option<u64>,
    pub(crate) mem_used_percent: Option<f64>,
    pub(crate) server_cpu_percent: Option<f64>,
    pub(crate) server_mem_bytes: Option<u64>,
}

#[derive(Serialize)]
pub(crate) struct ActivityStats {
    pub(crate) requests_total: u64,
    pub(crate) errors_total: u64,
    pub(crate) avg_latency_ms: f64,
    pub(crate) requests_5m: u64,
    pub(crate) errors_5m: u64,
}

#[derive(Serialize)]
pub(crate) struct AuthFailure {
    pub(crate) subject: String,
    pub(crate) failures: u32,
    pub(crate) window_age_seconds: u64,
}

#[derive(Serialize)]
pub(crate) struct Overview {
    pub(crate) status: &'static str,
    pub(crate) version: &'static str,
    pub(crate) api_version: &'static str,
    pub(crate) instance_id: Uuid,
    pub(crate) started_at: DateTime<Utc>,
    pub(crate) uptime_seconds: i64,
    pub(crate) pid: u32,
    pub(crate) bind_addr: String,
    pub(crate) console_bind_addr: String,
    pub(crate) public_url_configured: bool,
    pub(crate) users: UserCounts,
    pub(crate) sessions: SessionCounts,
    pub(crate) files: FileCounts,
    pub(crate) disk: DiskStats,
    pub(crate) database: DbStats,
    pub(crate) system: SystemStats,
    pub(crate) activity: ActivityStats,
    pub(crate) auth_failures: Vec<AuthFailure>,
    pub(crate) recent_events: Vec<AuditResponse>,
    pub(crate) unavailable: Vec<String>,
}

fn auth_failures(state: &AppState) -> Vec<AuthFailure> {
    let mut out = Vec::new();
    for (map, prefix) in [
        (&state.login_attempts, "client"),
        (&state.console_attempts, "console"),
    ] {
        if let Ok(guard) = map.lock() {
            for (key, entry) in guard.iter() {
                if entry.failures > 0 {
                    let subject = key
                        .strip_prefix("user:")
                        .or_else(|| key.strip_prefix("console:"))
                        .unwrap_or(key);
                    out.push(AuthFailure {
                        subject: format!("{prefix}:{subject}"),
                        failures: entry.failures,
                        window_age_seconds: entry.window_started.elapsed().as_secs(),
                    });
                }
            }
        }
    }
    out.sort_by_key(|a| std::cmp::Reverse(a.failures));
    out.truncate(20);
    out
}

pub(crate) async fn overview(
    State(state): State<AppState>,
    Extension(_admin_id): Extension<Uuid>,
) -> Result<Json<Overview>, AppError> {
    let mut unavailable = Vec::new();

    let users = sqlx::query(
        "SELECT COUNT(*) AS total, \
         SUM(CASE WHEN role='admin' THEN 1 ELSE 0 END) AS admins, \
         SUM(CASE WHEN disabled THEN 1 ELSE 0 END) AS disabled FROM users",
    )
    .fetch_one(&state.db)
    .await?;

    let sessions = sqlx::query(
        "SELECT SUM(CASE WHEN expires_at > CURRENT_TIMESTAMP THEN 1 ELSE 0 END) AS active, \
         SUM(CASE WHEN expires_at <= CURRENT_TIMESTAMP THEN 1 ELSE 0 END) AS expired, \
         COUNT(DISTINCT user_id) AS subjects FROM sessions",
    )
    .fetch_one(&state.db)
    .await?;

    let storage = storage_stats::cached(&state, 60).await?;

    let samples = state.metrics.samples();
    let latest = samples.last();
    let cutoff = Utc::now() - chrono::Duration::seconds(300);
    let (requests_5m, errors_5m) = samples
        .iter()
        .filter(|s| s.at > cutoff)
        .fold((0u64, 0u64), |(r, e), s| (r + s.requests, e + s.errors));

    let (requests_total, errors_total, avg_latency_ms) = state.metrics.totals();

    let disk_read = read_disk(&state.storage_root);
    let (disk_total, disk_free) = match disk_read {
        Ok(v) => v,
        Err(_) => {
            unavailable.push("disk".into());
            (0, 0)
        }
    };
    let (mount, fs_type) = match mount_info(&state.storage_root) {
        Some((m, f)) => (Some(m), Some(f)),
        None => {
            unavailable.push("mount".into());
            (None, None)
        }
    };
    let used_percent = if disk_total > 0 {
        (disk_total - disk_free) as f64 / disk_total as f64 * 100.0
    } else {
        0.0
    };

    let mem = read_meminfo();
    let (mem_total, mem_available, mem_used_percent) = match mem {
        Ok((t, a)) => {
            let total = t * 1024;
            let avail = a * 1024;
            let used = if total > 0 {
                (total - avail) as f64 / total as f64 * 100.0
            } else {
                0.0
            };
            (Some(total), Some(avail), Some(used))
        }
        Err(_) => {
            unavailable.push("memory".into());
            (None, None, None)
        }
    };
    let load = read_loadavg();
    if load.is_none() {
        unavailable.push("load".into());
    }

    let db_check = state.metrics.last_db_check();
    let db_size = state
        .metrics
        .last_db_check()
        .map(|c| c.size_bytes)
        .unwrap_or_else(|| crate::metrics::db_size_bytes(&state.config.database_path));

    let recent_events = sqlx::query(
        "SELECT a.id, a.action, a.path, a.target, a.outcome, a.detail, a.created_at, \
         u.username AS actor FROM audit_logs a LEFT JOIN users u ON u.id=a.user_id \
         ORDER BY a.created_at DESC LIMIT 12",
    )
    .fetch_all(&state.db)
    .await?
    .into_iter()
    .map(|r| AuditResponse {
        id: r.get("id"),
        actor: r.get("actor"),
        action: r.get("action"),
        path: r.get("path"),
        target: r.get("target"),
        outcome: r.get("outcome"),
        detail: r.get("detail"),
        created_at: r.get("created_at"),
    })
    .collect();

    Ok(Json(Overview {
        status: "ok",
        version: env!("CARGO_PKG_VERSION"),
        api_version: API_VERSION,
        instance_id: state.instance_id,
        started_at: state.started_at,
        uptime_seconds: (Utc::now() - state.started_at).num_seconds(),
        pid: std::process::id(),
        bind_addr: state.config.bind_addr.clone(),
        console_bind_addr: state.config.console_bind_addr.clone(),
        public_url_configured: state.config.public_url.is_some(),
        users: UserCounts {
            total: users.get::<Option<i64>, _>("total").unwrap_or(0),
            admins: users.get::<Option<i64>, _>("admins").unwrap_or(0),
            disabled: users.get::<Option<i64>, _>("disabled").unwrap_or(0),
        },
        sessions: SessionCounts {
            active: sessions.get::<Option<i64>, _>("active").unwrap_or(0),
            expired: sessions.get::<Option<i64>, _>("expired").unwrap_or(0),
            subjects: sessions.get::<Option<i64>, _>("subjects").unwrap_or(0),
        },
        files: FileCounts {
            total_files: storage.total_files,
            total_bytes: storage.total_bytes,
            trash_bytes: storage.trash_bytes,
        },
        disk: DiskStats {
            mount,
            fs_type,
            total_bytes: disk_total,
            free_bytes: disk_free,
            used_percent,
        },
        database: DbStats {
            size_bytes: db_size,
            ok: db_check.as_ref().map(|c| c.ok),
            detail: db_check.as_ref().map(|c| c.detail.clone()),
            checked_at: db_check.as_ref().map(|c| c.at),
        },
        system: SystemStats {
            cpu_percent: latest.and_then(|s| s.cpu_percent),
            load1: load.map(|l| l.0),
            load5: load.map(|l| l.1),
            load15: load.map(|l| l.2),
            mem_total_bytes: mem_total,
            mem_available_bytes: mem_available,
            mem_used_percent,
            server_cpu_percent: latest.and_then(|s| s.server_cpu_percent),
            server_mem_bytes: latest
                .and_then(|s| s.server_mem_mb)
                .map(|mb| (mb * 1_048_576.0) as u64),
        },
        activity: ActivityStats {
            requests_total,
            errors_total,
            avg_latency_ms,
            requests_5m,
            errors_5m,
        },
        auth_failures: auth_failures(&state),
        recent_events,
        unavailable,
    }))
}

// ============================================================== metrics

#[derive(Deserialize)]
pub(crate) struct MetricsQuery {
    #[serde(default)]
    pub(crate) minutes: Option<i64>,
}

#[derive(Serialize)]
pub(crate) struct MetricsHistory {
    pub(crate) samples: Vec<crate::metrics::MetricSample>,
    pub(crate) interval_seconds: u64,
}

pub(crate) async fn metrics_history(
    State(state): State<AppState>,
    Extension(_admin_id): Extension<Uuid>,
    Query(query): Query<MetricsQuery>,
) -> Result<Json<MetricsHistory>, AppError> {
    let minutes = query.minutes.unwrap_or(15).clamp(1, 60);
    let since = Utc::now() - chrono::Duration::minutes(minutes);
    let samples = state
        .metrics
        .samples()
        .into_iter()
        .filter(|s| s.at >= since)
        .collect();
    Ok(Json(MetricsHistory {
        samples,
        interval_seconds: 5,
    }))
}

// ============================================================== sessions

#[derive(Deserialize)]
pub(crate) struct SessionsQuery {
    #[serde(default)]
    pub(crate) q: Option<String>,
    #[serde(default)]
    pub(crate) status: Option<String>,
    #[serde(default)]
    pub(crate) limit: Option<i64>,
    #[serde(default)]
    pub(crate) offset: Option<i64>,
}

#[derive(Serialize)]
pub(crate) struct SessionRow {
    pub(crate) id: Uuid,
    pub(crate) user_id: Uuid,
    pub(crate) username: String,
    pub(crate) display_name: String,
    pub(crate) created_at: DateTime<Utc>,
    pub(crate) last_activity_at: DateTime<Utc>,
    pub(crate) expires_at: DateTime<Utc>,
    pub(crate) status: String,
    pub(crate) device_name: Option<String>,
    pub(crate) platform: Option<String>,
}

#[derive(Serialize)]
pub(crate) struct SessionsPage {
    pub(crate) items: Vec<SessionRow>,
    pub(crate) total: i64,
}

pub(crate) async fn list_all_sessions(
    State(state): State<AppState>,
    Extension(_admin_id): Extension<Uuid>,
    Query(query): Query<SessionsQuery>,
) -> Result<Json<SessionsPage>, AppError> {
    let limit = query.limit.unwrap_or(50).clamp(1, 200);
    let offset = query.offset.unwrap_or(0).max(0);
    let search = query
        .q
        .map(|v| v.trim().to_string())
        .filter(|v| !v.is_empty() && v.len() <= 64);
    let status = query.status.filter(|v| v == "active" || v == "expired");

    let total: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM sessions s JOIN users u ON u.id=s.user_id \
         WHERE ($1 IS NULL OR u.username LIKE '%'||$1||'%') \
         AND ($2 IS NULL OR ($2='active' AND s.expires_at>CURRENT_TIMESTAMP) \
              OR ($2='expired' AND s.expires_at<=CURRENT_TIMESTAMP))",
    )
    .bind(search.as_deref())
    .bind(status.as_deref())
    .fetch_one(&state.db)
    .await?;

    let rows = sqlx::query(
        "SELECT s.id, s.user_id, u.username, u.display_name, s.created_at, \
         COALESCE(s.last_activity_at, s.created_at) AS last_activity_at, s.expires_at, \
         s.device_name, s.platform, \
         CASE WHEN s.expires_at > CURRENT_TIMESTAMP THEN 'active' ELSE 'expired' END AS status \
         FROM sessions s JOIN users u ON u.id=s.user_id \
         WHERE ($1 IS NULL OR u.username LIKE '%'||$1||'%') \
         AND ($2 IS NULL OR ($2='active' AND s.expires_at>CURRENT_TIMESTAMP) \
              OR ($2='expired' AND s.expires_at<=CURRENT_TIMESTAMP)) \
         ORDER BY last_activity_at DESC LIMIT $3 OFFSET $4",
    )
    .bind(search.as_deref())
    .bind(status.as_deref())
    .bind(limit)
    .bind(offset)
    .fetch_all(&state.db)
    .await?;

    let items = rows
        .into_iter()
        .map(|r| SessionRow {
            id: r.get("id"),
            user_id: r.get("user_id"),
            username: r.get("username"),
            display_name: r.get("display_name"),
            created_at: r.get("created_at"),
            last_activity_at: r.get("last_activity_at"),
            expires_at: r.get("expires_at"),
            status: r.get("status"),
            device_name: r.get("device_name"),
            platform: r.get("platform"),
        })
        .collect();

    Ok(Json(SessionsPage { items, total }))
}

pub(crate) async fn revoke_session(
    State(state): State<AppState>,
    Extension(admin_id): Extension<Uuid>,
    AxumPath(id): AxumPath<Uuid>,
) -> Result<Json<RevokeSessionsResponse>, AppError> {
    let result = sqlx::query("DELETE FROM sessions WHERE id=$1")
        .bind(id)
        .execute(&state.db)
        .await?;
    if result.rows_affected() == 0 {
        return Err(AppError::NotFound);
    }
    audit_event(
        &state.db,
        admin_id,
        "console_revoke_session",
        Some(&id.to_string()),
        "success",
        None,
    )
    .await?;
    Ok(Json(RevokeSessionsResponse {
        revoked: result.rows_affected(),
    }))
}

#[derive(Deserialize)]
pub(crate) struct RevokeAllRequest {
    pub(crate) password: String,
    pub(crate) confirm: String,
}

pub(crate) async fn revoke_all_sessions(
    State(state): State<AppState>,
    Extension(admin_id): Extension<Uuid>,
    Json(payload): Json<RevokeAllRequest>,
) -> Result<Json<RevokeSessionsResponse>, AppError> {
    if payload.confirm != "REVOKE_ALL" {
        return Err(AppError::BadRequest(
            "Type REVOKE_ALL to confirm a system-wide sign-out".into(),
        ));
    }
    crate::console::session::confirm_password(&state, admin_id, &payload.password).await?;
    let result = sqlx::query("DELETE FROM sessions")
        .execute(&state.db)
        .await?;
    audit_event(
        &state.db,
        admin_id,
        "console_revoke_all_sessions",
        Some("all client sessions"),
        "success",
        Some("system-wide sign-out"),
    )
    .await?;
    Ok(Json(RevokeSessionsResponse {
        revoked: result.rows_affected(),
    }))
}

// ============================================================== shares

#[derive(Deserialize)]
pub(crate) struct PageQuery {
    #[serde(default)]
    pub(crate) limit: Option<i64>,
    #[serde(default)]
    pub(crate) offset: Option<i64>,
}

#[derive(Serialize)]
pub(crate) struct ShareRow {
    pub(crate) id: Uuid,
    pub(crate) path: String,
    pub(crate) permission: String,
    pub(crate) is_link: bool,
    pub(crate) owner: String,
    pub(crate) recipient: Option<String>,
    pub(crate) created_at: DateTime<Utc>,
    pub(crate) expires_at: Option<DateTime<Utc>>,
}

#[derive(Serialize)]
pub(crate) struct SharesPage {
    pub(crate) items: Vec<ShareRow>,
    pub(crate) total: i64,
}

pub(crate) async fn list_all_shares(
    State(state): State<AppState>,
    Extension(_admin_id): Extension<Uuid>,
    Query(query): Query<PageQuery>,
) -> Result<Json<SharesPage>, AppError> {
    let limit = query.limit.unwrap_or(50).clamp(1, 200);
    let offset = query.offset.unwrap_or(0).max(0);
    let total: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM shares")
        .fetch_one(&state.db)
        .await?;
    let rows = sqlx::query(
        "SELECT s.id, s.path, s.permission, s.is_link, s.created_at, s.expires_at, \
         o.username AS owner, r.username AS recipient \
         FROM shares s LEFT JOIN users o ON o.id=s.owner_id \
         LEFT JOIN users r ON r.id=s.recipient_user_id \
         ORDER BY s.created_at DESC LIMIT $1 OFFSET $2",
    )
    .bind(limit)
    .bind(offset)
    .fetch_all(&state.db)
    .await?;
    let items = rows
        .into_iter()
        .map(|r| ShareRow {
            id: r.get("id"),
            path: r.get("path"),
            permission: r.get("permission"),
            is_link: r.get("is_link"),
            owner: r.get("owner"),
            recipient: r.get("recipient"),
            created_at: r.get("created_at"),
            expires_at: r.get("expires_at"),
        })
        .collect();
    Ok(Json(SharesPage { items, total }))
}

pub(crate) async fn revoke_share(
    State(state): State<AppState>,
    Extension(admin_id): Extension<Uuid>,
    AxumPath(id): AxumPath<Uuid>,
) -> Result<StatusCode, AppError> {
    let result = sqlx::query("DELETE FROM shares WHERE id=$1")
        .bind(id)
        .execute(&state.db)
        .await?;
    if result.rows_affected() == 0 {
        return Err(AppError::NotFound);
    }
    audit_event(
        &state.db,
        admin_id,
        "console_revoke_share",
        Some(&id.to_string()),
        "success",
        None,
    )
    .await?;
    Ok(StatusCode::NO_CONTENT)
}

// ============================================================== storage

#[derive(Serialize)]
pub(crate) struct StorageSummaryResponse {
    pub(crate) total_bytes: u64,
    pub(crate) total_files: u64,
    pub(crate) trash_bytes: u64,
    pub(crate) users: Vec<storage_stats::UserStorage>,
    pub(crate) scanned_at: DateTime<Utc>,
}

pub(crate) async fn storage_summary(
    State(state): State<AppState>,
    Extension(_admin_id): Extension<Uuid>,
) -> Result<Json<StorageSummaryResponse>, AppError> {
    let s = storage_stats::cached(&state, 60).await?;
    Ok(Json(StorageSummaryResponse {
        total_bytes: s.total_bytes,
        total_files: s.total_files,
        trash_bytes: s.trash_bytes,
        users: s.users,
        scanned_at: s.scanned_at,
    }))
}

#[derive(Deserialize)]
pub(crate) struct BrowseQuery {
    pub(crate) user: Uuid,
    #[serde(default)]
    pub(crate) path: Option<String>,
}

#[derive(Serialize)]
pub(crate) struct BrowseEntry {
    pub(crate) name: String,
    pub(crate) kind: String,
    pub(crate) size: u64,
    pub(crate) modified_at: Option<DateTime<Utc>>,
}

#[derive(Serialize)]
pub(crate) struct BrowseResponse {
    pub(crate) user_id: Uuid,
    pub(crate) username: String,
    pub(crate) path: String,
    pub(crate) parent: Option<String>,
    pub(crate) entries: Vec<BrowseEntry>,
    pub(crate) truncated: bool,
}

const BROWSE_LIMIT: usize = 500;

fn dir_inside_root(dir: &Path, root: &Path) -> bool {
    match (dir.canonicalize(), root.canonicalize()) {
        (Ok(d), Ok(r)) => d.starts_with(r),
        _ => false,
    }
}

pub(crate) async fn browse(
    State(state): State<AppState>,
    Extension(_admin_id): Extension<Uuid>,
    Query(query): Query<BrowseQuery>,
) -> Result<Json<BrowseResponse>, AppError> {
    let username: String = sqlx::query_scalar("SELECT username FROM users WHERE id=$1")
        .bind(query.user)
        .fetch_optional(&state.db)
        .await?
        .ok_or(AppError::NotFound)?;

    let rel = safe_relative_path(query.path.as_deref().unwrap_or(""))?;
    let root = user_root(&state, query.user);
    let dir = root.join(&rel);
    if !tokio::fs::try_exists(&dir).await.unwrap_or(false) {
        // A brand-new account has no directory on disk yet; its root is simply
        // empty. Deeper paths that do not exist are a genuine 404.
        if rel.as_os_str().is_empty() {
            return Ok(Json(BrowseResponse {
                user_id: query.user,
                username,
                path: String::new(),
                parent: None,
                entries: Vec::new(),
                truncated: false,
            }));
        }
        return Err(AppError::NotFound);
    }
    if !dir_inside_root(&dir, &root) {
        return Err(AppError::Forbidden);
    }

    let mut reader = tokio::fs::read_dir(&dir).await?;
    let mut entries = Vec::new();
    let mut truncated = false;
    while let Some(entry) = reader.next_entry().await? {
        let meta = match tokio::fs::symlink_metadata(entry.path()).await {
            Ok(m) => m,
            Err(_) => continue,
        };
        let file_type = meta.file_type();
        if file_type.is_symlink() {
            continue;
        }
        let kind = if file_type.is_dir() {
            "folder"
        } else if file_type.is_file() {
            "file"
        } else {
            continue;
        };
        let name = entry.file_name().to_string_lossy().to_string();
        let modified_at = meta.modified().ok().map(DateTime::<Utc>::from);
        entries.push(BrowseEntry {
            name,
            kind: kind.into(),
            size: if file_type.is_file() { meta.len() } else { 0 },
            modified_at,
        });
        if entries.len() >= BROWSE_LIMIT {
            truncated = true;
            break;
        }
    }
    entries.sort_by(|a, b| {
        (b.kind == "folder")
            .cmp(&(a.kind == "folder"))
            .then_with(|| a.name.to_lowercase().cmp(&b.name.to_lowercase()))
    });

    let rel_str = rel.to_string_lossy().to_string();
    let parent = if rel_str.is_empty() {
        None
    } else {
        PathBuf::from(&rel_str)
            .parent()
            .map(|p| p.to_string_lossy().to_string())
            .filter(|p| !p.is_empty())
    };

    Ok(Json(BrowseResponse {
        user_id: query.user,
        username,
        path: rel_str,
        parent,
        entries,
        truncated,
    }))
}

#[derive(Deserialize)]
pub(crate) struct IntegrityQuery {
    pub(crate) user: Uuid,
    #[serde(default)]
    pub(crate) limit: Option<i64>,
}

#[derive(Serialize)]
pub(crate) struct IntegrityIssue {
    pub(crate) path: String,
    pub(crate) kind: String,
    pub(crate) detail: String,
}

#[derive(Serialize)]
pub(crate) struct IntegrityResponse {
    pub(crate) user_id: Uuid,
    pub(crate) checked: i64,
    pub(crate) missing: i64,
    pub(crate) size_mismatch: i64,
    pub(crate) issues: Vec<IntegrityIssue>,
    pub(crate) truncated: bool,
    pub(crate) dry_run: bool,
}

pub(crate) async fn storage_integrity(
    State(state): State<AppState>,
    Extension(_admin_id): Extension<Uuid>,
    Query(query): Query<IntegrityQuery>,
) -> Result<Json<IntegrityResponse>, AppError> {
    let limit = query.limit.unwrap_or(500).clamp(1, 5000);
    let rows = sqlx::query(
        "SELECT path, kind, size_bytes FROM sync_file_fingerprints \
         WHERE user_id=$1 AND kind='file' ORDER BY path LIMIT $2",
    )
    .bind(query.user)
    .bind(limit)
    .fetch_all(&state.db)
    .await?;

    let root = user_root(&state, query.user);
    let mut missing = 0i64;
    let mut size_mismatch = 0i64;
    let mut issues = Vec::new();
    let mut days = 0i64;
    for row in &rows {
        days += 1;
        let rel_str: String = row.get("path");
        let Ok(rel) = safe_relative_path(&rel_str) else {
            continue;
        };
        let disk = root.join(&rel);
        match tokio::fs::symlink_metadata(&disk).await {
            Ok(meta) if meta.is_file() => {
                let expected: i64 = row.get("size_bytes");
                if meta.len() as i64 != expected {
                    size_mismatch += 1;
                    if issues.len() < 100 {
                        issues.push(IntegrityIssue {
                            path: rel_str,
                            kind: "size_mismatch".into(),
                            detail: format!(
                                "metadata {} bytes, disk {} bytes",
                                expected,
                                meta.len()
                            ),
                        });
                    }
                }
            }
            _ => {
                missing += 1;
                if issues.len() < 100 {
                    issues.push(IntegrityIssue {
                        path: rel_str,
                        kind: "missing".into(),
                        detail: "recorded in metadata but absent on disk".into(),
                    });
                }
            }
        }
    }

    Ok(Json(IntegrityResponse {
        user_id: query.user,
        checked: days,
        missing,
        size_mismatch,
        issues,
        truncated: days >= limit,
        dry_run: true,
    }))
}

// ============================================================== audit

#[derive(Deserialize)]
pub(crate) struct AuditQuery {
    #[serde(default)]
    pub(crate) q: Option<String>,
    #[serde(default)]
    pub(crate) outcome: Option<String>,
    #[serde(default)]
    pub(crate) limit: Option<i64>,
    #[serde(default)]
    pub(crate) offset: Option<i64>,
}

#[derive(Serialize)]
pub(crate) struct AuditPage {
    pub(crate) items: Vec<AuditResponse>,
    pub(crate) total: i64,
}

pub(crate) async fn audit_log(
    State(state): State<AppState>,
    Extension(_admin_id): Extension<Uuid>,
    Query(query): Query<AuditQuery>,
) -> Result<Json<AuditPage>, AppError> {
    let limit = query.limit.unwrap_or(50).clamp(1, 200);
    let offset = query.offset.unwrap_or(0).max(0);
    let search = query
        .q
        .map(|v| v.trim().to_string())
        .filter(|v| !v.is_empty() && v.len() <= 64);
    let outcome = query
        .outcome
        .filter(|v| v == "success" || v == "denied" || v == "failed");

    let total: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM audit_logs a LEFT JOIN users u ON u.id=a.user_id \
         WHERE ($1 IS NULL OR a.action LIKE '%'||$1||'%' OR a.target LIKE '%'||$1||'%' \
              OR u.username LIKE '%'||$1||'%') \
         AND ($2 IS NULL OR a.outcome = $2)",
    )
    .bind(search.as_deref())
    .bind(outcome.as_deref())
    .fetch_one(&state.db)
    .await?;

    let rows = sqlx::query(
        "SELECT a.id, a.action, a.path, a.target, a.outcome, a.detail, a.created_at, \
         u.username AS actor FROM audit_logs a LEFT JOIN users u ON u.id=a.user_id \
         WHERE ($1 IS NULL OR a.action LIKE '%'||$1||'%' OR a.target LIKE '%'||$1||'%' \
              OR u.username LIKE '%'||$1||'%') \
         AND ($2 IS NULL OR a.outcome = $2) \
         ORDER BY a.created_at DESC LIMIT $3 OFFSET $4",
    )
    .bind(search.as_deref())
    .bind(outcome.as_deref())
    .bind(limit)
    .bind(offset)
    .fetch_all(&state.db)
    .await?;

    let items = rows
        .into_iter()
        .map(|r| AuditResponse {
            id: r.get("id"),
            actor: r.get("actor"),
            action: r.get("action"),
            path: r.get("path"),
            target: r.get("target"),
            outcome: r.get("outcome"),
            detail: r.get("detail"),
            created_at: r.get("created_at"),
        })
        .collect();

    Ok(Json(AuditPage { items, total }))
}

// ============================================================== service

#[derive(Serialize)]
pub(crate) struct ServiceStatus {
    pub(crate) unit: &'static str,
    pub(crate) pid: u32,
    pub(crate) version: &'static str,
    pub(crate) api_version: &'static str,
    pub(crate) instance_id: Uuid,
    pub(crate) started_at: DateTime<Utc>,
    pub(crate) uptime_seconds: i64,
    pub(crate) bind_addr: String,
    pub(crate) console_bind_addr: String,
    pub(crate) mount: Option<String>,
    pub(crate) fs_type: Option<String>,
    pub(crate) disk_total_bytes: u64,
    pub(crate) disk_free_bytes: u64,
    pub(crate) restart_enabled: bool,
}

pub(crate) async fn service_status(
    State(state): State<AppState>,
    Extension(_admin_id): Extension<Uuid>,
) -> Result<Json<ServiceStatus>, AppError> {
    let (mount, fs_type) = mount_info(&state.storage_root).unzip();
    let (total, free) = read_disk(&state.storage_root).unwrap_or((0, 0));
    Ok(Json(ServiceStatus {
        unit: "nexadrive.service",
        pid: std::process::id(),
        version: env!("CARGO_PKG_VERSION"),
        api_version: API_VERSION,
        instance_id: state.instance_id,
        started_at: state.started_at,
        uptime_seconds: (Utc::now() - state.started_at).num_seconds(),
        bind_addr: state.config.bind_addr.clone(),
        console_bind_addr: state.config.console_bind_addr.clone(),
        mount,
        fs_type,
        disk_total_bytes: total,
        disk_free_bytes: free,
        restart_enabled: state.config.console_allow_restart,
    }))
}

#[derive(Deserialize)]
pub(crate) struct LogQuery {
    #[serde(default)]
    pub(crate) limit: Option<usize>,
}

#[derive(Serialize)]
pub(crate) struct LogResponse {
    pub(crate) lines: Vec<String>,
    pub(crate) note: &'static str,
}

pub(crate) async fn service_logs(
    State(state): State<AppState>,
    Extension(_admin_id): Extension<Uuid>,
    Query(query): Query<LogQuery>,
) -> Result<Json<LogResponse>, AppError> {
    let limit = query.limit.unwrap_or(200);
    Ok(Json(LogResponse {
        lines: state.logs.recent(limit),
        note: "In-memory ring of this server process's recent output (redacted). Not the systemd journal.",
    }))
}

#[derive(Deserialize)]
pub(crate) struct RestartRequest {
    pub(crate) password: String,
    pub(crate) confirm: String,
}

pub(crate) async fn service_restart(
    State(state): State<AppState>,
    Extension(admin_id): Extension<Uuid>,
    Json(payload): Json<RestartRequest>,
) -> Result<Json<serde_json::Value>, AppError> {
    if !state.config.console_allow_restart {
        return Err(AppError::Conflict(
            "Service restart is disabled. Set CONSOLE_ALLOW_RESTART=true and install the helper to enable it.".into(),
        ));
    }
    if payload.confirm != "RESTART" {
        return Err(AppError::BadRequest(
            "Type RESTART to confirm the restart".into(),
        ));
    }
    crate::console::session::confirm_password(&state, admin_id, &payload.password).await?;

    let helper = &state.config.console_restart_helper;
    if !Path::new(helper).is_absolute() {
        return Err(AppError::Internal);
    }
    if !tokio::fs::try_exists(helper).await.unwrap_or(false) {
        return Err(AppError::Conflict(
            "The restart helper is not installed".into(),
        ));
    }

    audit_event(
        &state.db,
        admin_id,
        "console_restart_service",
        Some("nexadrive.service"),
        "success",
        Some("restart requested"),
    )
    .await?;

    // Fixed helper path, no arguments, no shell. The helper is expected to run
    // a narrowly scoped `systemctl restart nexadrive` via sudoers.
    match tokio::process::Command::new(helper).spawn() {
        Ok(_) => Ok(Json(
            serde_json::json!({"accepted": true, "message": "Restart requested. The service may briefly drop this connection."}),
        )),
        Err(_) => Err(AppError::Internal),
    }
}

#[derive(Deserialize)]
pub(crate) struct DbIntegrityQuery {
    #[serde(default)]
    pub(crate) force: Option<bool>,
}

pub(crate) async fn db_integrity(
    State(state): State<AppState>,
    Extension(_admin_id): Extension<Uuid>,
    Query(query): Query<DbIntegrityQuery>,
) -> Result<Json<crate::metrics::DbCheck>, AppError> {
    let force = query.force.unwrap_or(false);
    Ok(Json(
        state
            .metrics
            .check_db(&state.db, &state.config.database_path, force)
            .await,
    ))
}

pub(crate) async fn console_health(State(state): State<AppState>) -> Json<serde_json::Value> {
    Json(serde_json::json!({
        "status": "ok",
        "console": "ok",
        "started_at": state.started_at,
    }))
}
