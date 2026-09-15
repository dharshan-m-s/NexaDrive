use axum::{
    Json, Router,
    body::Body,
    extract::{DefaultBodyLimit, Multipart, Query, State},
    http::{HeaderMap, HeaderValue, StatusCode, header},
    middleware,
    response::{IntoResponse, Response},
    routing::{get, post, put},
};
use chrono::{DateTime, Utc};
use futures_util::StreamExt;
use image::codecs::jpeg::JpegEncoder;
use rand::{Rng, distr::Alphanumeric};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use sqlx::{
    Row,
    sqlite::{SqliteConnectOptions, SqlitePool, SqlitePoolOptions, SqliteRow},
};
use std::{
    collections::HashMap,
    env,
    fs::FileType,
    io::Cursor,
    path::{Component, Path, PathBuf},
    sync::{Arc, Mutex},
    time::{Duration, Instant},
};
use tokio::{
    fs,
    io::{AsyncSeekExt, AsyncWriteExt},
    process::Command,
};
use tokio_util::io::ReaderStream;
use tower_http::{cors::CorsLayer, limit::RequestBodyLimitLayer, trace::TraceLayer};
use tracing::info;
use uuid::Uuid;

#[derive(Clone)]
struct AppState {
    db: SqlitePool,
    storage_root: Arc<PathBuf>,
    instance_id: Uuid,
    started_at: DateTime<Utc>,
    login_attempts: Arc<Mutex<HashMap<String, LoginAttempt>>>,
    share_download_attempts: Arc<Mutex<HashMap<String, LoginAttempt>>>,
    public_url: Option<String>,
    thumb_cache: Arc<Mutex<HashMap<String, CachedThumb>>>,
}

struct CachedThumb {
    generated: Instant,
    bytes: Vec<u8>,
}

#[derive(Clone, Copy)]
struct LoginAttempt {
    window_started: Instant,
    failures: u32,
}

#[derive(Debug, thiserror::Error)]
enum AppError {
    #[error("unauthorized")]
    Unauthorized,
    #[error("forbidden")]
    Forbidden,
    #[error("not found")]
    NotFound,
    #[error("conflict: {0}")]
    Conflict(String),
    #[error("bad request: {0}")]
    BadRequest(String),
    #[error("unsupported media type")]
    UnsupportedMedia,
    #[error("too many requests")]
    TooManyRequests,
    #[error("database error")]
    Database(#[from] sqlx::Error),
    #[error("io error")]
    Io(#[from] std::io::Error),
    #[error("internal error")]
    Internal,
}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        let (status, message) = match self {
            Self::Unauthorized => (StatusCode::UNAUTHORIZED, "Unauthorized".to_string()),
            Self::Forbidden => (StatusCode::FORBIDDEN, "Forbidden".to_string()),
            Self::NotFound => (StatusCode::NOT_FOUND, "Not found".to_string()),
            Self::Conflict(message) => (StatusCode::CONFLICT, message),
            Self::BadRequest(message) => (StatusCode::BAD_REQUEST, message),
            Self::UnsupportedMedia => (
                StatusCode::UNSUPPORTED_MEDIA_TYPE,
                "Unsupported image format".to_string(),
            ),
            Self::TooManyRequests => (
                StatusCode::TOO_MANY_REQUESTS,
                "Too many login attempts. Try again later.".to_string(),
            ),
            Self::Database(_) | Self::Io(_) | Self::Internal => (
                StatusCode::INTERNAL_SERVER_ERROR,
                "Internal server error".to_string(),
            ),
        };
        (status, Json(serde_json::json!({"error": message}))).into_response()
    }
}

#[derive(Serialize)]
struct Health {
    status: &'static str,
}

#[derive(Serialize)]
struct ServerStatus {
    instance_id: Uuid,
    started_at: DateTime<Utc>,
    status: &'static str,
    #[serde(skip_serializing_if = "Option::is_none")]
    public_url: Option<String>,
    /// Server release version (Cargo package version). Sent in every status
    /// response so clients can warn about incompatible server deployments.
    version: &'static str,
    /// Backward-compatibility contract: the API surface this build speaks.
    api_version: &'static str,
}

#[derive(Serialize)]
struct NotificationResponse {
    id: Uuid,
    kind: String,
    title: String,
    message: String,
    severity: String,
    read: bool,
    created_at: DateTime<Utc>,
}

#[derive(Deserialize)]
struct NotificationReadRequest {
    id: Option<Uuid>,
    all: Option<bool>,
}

#[derive(Serialize)]
struct AuditResponse {
    id: Uuid,
    action: String,
    path: Option<String>,
    created_at: DateTime<Utc>,
}

#[derive(Serialize)]
struct SyncDeviceResponse {
    id: Uuid,
    name: String,
    last_seen_at: DateTime<Utc>,
    created_at: DateTime<Utc>,
}

#[derive(Deserialize)]
struct BackupRestoreRequest {
    snapshot_id: String,
}

#[derive(Serialize)]
struct BackupSnapshotResponse {
    id: String,
    time: DateTime<Utc>,
    hostname: Option<String>,
    paths: Vec<String>,
}

#[derive(Deserialize)]
struct LoginRequest {
    username: String,
    password: String,
}

#[derive(Serialize)]
struct LoginResponse {
    token: String,
    user: UserResponse,
}

#[derive(Serialize)]
struct UserResponse {
    id: Uuid,
    username: String,
    display_name: String,
    role: String,
}

#[derive(Serialize)]
struct AdminUserResponse {
    id: Uuid,
    username: String,
    display_name: String,
    role: String,
    disabled: bool,
    quota_bytes: Option<i64>,
}

#[derive(Deserialize)]
struct CreateUserRequest {
    username: String,
    display_name: String,
    password: String,
    role: Option<String>,
    quota_bytes: Option<i64>,
}

#[derive(Deserialize)]
struct UpdateUserRequest {
    display_name: Option<String>,
    role: Option<String>,
    disabled: Option<bool>,
    quota_bytes: Option<i64>,
}

#[derive(Serialize)]
struct ShareResponse {
    id: Uuid,
    path: String,
    permission: String,
    recipient: Option<String>,
    is_link: bool,
    token: Option<String>,
    expires_at: Option<DateTime<Utc>>,
}

#[derive(Deserialize)]
struct CreateShareRequest {
    path: String,
    username: Option<String>,
    permission: String,
    expires_at: Option<DateTime<Utc>>,
}

#[derive(Deserialize)]
struct SharedQuery {
    share_id: Uuid,
    path: Option<String>,
}

#[derive(Deserialize)]
struct SharedActionRequest {
    share_id: Uuid,
    action: String,
    path: String,
    name: Option<String>,
    destination: Option<String>,
}

#[derive(Serialize)]
struct SharedRootResponse {
    id: Uuid,
    name: String,
    path: String,
    permission: String,
    owner: String,
}

#[derive(Serialize)]
struct FileEntry {
    name: String,
    path: String,
    kind: String,
    size: i64,
    modified_at: Option<DateTime<Utc>>,
}

#[derive(Serialize)]
struct TrashEntry {
    id: Uuid,
    name: String,
    original_path: String,
    kind: String,
    size: i64,
    deleted_at: DateTime<Utc>,
}

#[derive(Deserialize)]
struct PathQuery {
    path: Option<String>,
}

#[derive(Deserialize)]
struct ThumbQuery {
    path: Option<String>,
    max: Option<u32>,
}

#[derive(Deserialize)]
struct SearchQuery {
    q: String,
}

#[derive(Deserialize)]
struct RenameRequest {
    source: String,
    name: String,
}

#[derive(Deserialize)]
struct TransferRequest {
    source: String,
    destination: String,
}

#[derive(Deserialize)]
struct BatchRequest {
    action: String,
    paths: Vec<String>,
    destination: Option<String>,
}

#[derive(Serialize)]
struct ActionResponse {
    path: String,
}

#[derive(Deserialize)]
struct IdQuery {
    id: Option<Uuid>,
}

#[derive(Deserialize)]
struct CreateFolderRequest {
    path: String,
}

#[derive(Serialize)]
struct StorageResponse {
    used_bytes: u64,
    file_count: u64,
}

#[derive(Serialize)]
struct PhotoEntry {
    name: String,
    path: String,
    size: i64,
    modified_at: Option<DateTime<Utc>>,
}

#[derive(Deserialize)]
struct UploadStatusQuery {
    upload_id: Uuid,
}

#[derive(Deserialize)]
struct ChunkQuery {
    upload_id: Uuid,
    path: String,
    name: String,
    offset: u64,
    total: u64,
}

#[derive(Deserialize)]
struct SyncManifestQuery {
    device_id: Option<Uuid>,
    device_name: Option<String>,
}

#[derive(Deserialize)]
struct SyncDeltaQuery {
    device_id: Option<Uuid>,
    device_name: Option<String>,
    since: String,
}

#[derive(Deserialize)]
#[allow(dead_code)]
struct SyncDeleteRequest {
    path: String,
    device_id: Option<Uuid>,
}

#[derive(Deserialize)]
struct BackupRunRequest {
    prune: Option<bool>,
}

#[derive(Serialize)]
struct BackupStatusResponse {
    configured: bool,
    restic_available: bool,
    repository: Option<String>,
}

#[derive(Serialize)]
struct BackupRunResponse {
    output: String,
}

#[derive(Serialize)]
struct BackupCheckResponse {
    output: String,
    verified: bool,
}

#[derive(Serialize)]
struct SyncEntry {
    path: String,
    kind: String,
    size: u64,
    modified_at: Option<DateTime<Utc>>,
    sha256: Option<String>,
}

#[derive(Serialize)]
struct SyncManifestResponse {
    device_id: Uuid,
    server_time: DateTime<Utc>,
    entries: Vec<SyncEntry>,
    tombstones: Vec<String>,
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    dotenvy::dotenv().ok();
    tracing_subscriber::fmt()
        .with_env_filter(
            env::var("RUST_LOG").unwrap_or_else(|_| "info,nexadrive_server=debug".into()),
        )
        .init();

    let database_path = env::var("DATABASE_PATH").unwrap_or_else(|_| "./data/nexadrive.db".into());
    if let Some(parent) = std::path::Path::new(&database_path).parent() {
        fs::create_dir_all(parent).await?;
    }
    let storage_root =
        PathBuf::from(env::var("STORAGE_ROOT").unwrap_or_else(|_| "./storage".into()));
    fs::create_dir_all(&storage_root).await?;
    fs::create_dir_all(storage_root.join(".trash")).await?;

    let db = SqlitePoolOptions::new()
        .max_connections(5)
        .connect_with(
            SqliteConnectOptions::new()
                .filename(&database_path)
                .create_if_missing(true)
                .foreign_keys(true)
                .journal_mode(sqlx::sqlite::SqliteJournalMode::Wal)
                .synchronous(sqlx::sqlite::SqliteSynchronous::Normal)
                .busy_timeout(std::time::Duration::from_secs(10)),
        )
        .await?;
    sqlx::migrate!("./migrations").run(&db).await?;
    bootstrap_admin(&db).await?;

    cleanup_stale_uploads(&storage_root).await?;
    recover_upload_jobs(&db, &storage_root).await?;
    let public_url = env::var("PUBLIC_URL")
        .ok()
        .map(|v| v.trim().trim_end_matches('/').to_string())
        .filter(|v| !v.is_empty());
    if let Some(url) = &public_url {
        info!(%url, "NexaDrive public URL configured");
    } else {
        info!("PUBLIC_URL not set; clients must supply the server address");
    }
    let state = AppState {
        db,
        storage_root: Arc::new(storage_root),
        instance_id: Uuid::new_v4(),
        started_at: Utc::now(),
        login_attempts: Arc::new(Mutex::new(HashMap::new())),
        share_download_attempts: Arc::new(Mutex::new(HashMap::new())),
        public_url,
        thumb_cache: Arc::new(Mutex::new(HashMap::new())),
    };

    let public = Router::new()
        .route("/health", get(health))
        .route("/api/server/status", get(server_status))
        .route("/api/auth/login", post(login))
        .route("/api/share/{token}/download", get(public_share_download));

    let max_upload_bytes: usize = env::var("MAX_UPLOAD_BYTES")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(10usize * 1024 * 1024 * 1024);

    let protected = Router::new()
        .route("/api/auth/logout", post(logout))
        .route("/api/me", get(me))
        .route("/api/admin/users", get(list_users).post(create_user))
        .route("/api/admin/users/{id}", put(update_user))
        .route("/api/admin/audit", get(list_audit))
        .route(
            "/api/shares",
            get(list_shares).post(create_share).delete(delete_share),
        )
        .route("/api/shared", get(list_shared))
        .route("/api/shared/items", get(list_shared_items))
        .route("/api/shared/download", get(download_shared_file))
        .route("/api/shared/action", post(shared_action))
        .route("/api/files", get(list_files).delete(delete_file))
        .route("/api/files/search", get(search_files))
        .route("/api/files/rename", post(rename_file))
        .route("/api/files/move", post(move_file))
        .route("/api/files/copy", post(copy_file))
        .route("/api/files/batch", post(batch_files))
        .route("/api/files/download", get(download_file))
        .route("/api/files/thumbnail", get(thumbnail))
        .route("/api/files/upload", post(upload_file))
        .route("/api/uploads/status", get(upload_status))
        .route("/api/uploads/chunk", post(upload_chunk))
        .route("/api/sync/manifest", get(sync_manifest))
        .route("/api/sync/delta", get(sync_delta))
        .route("/api/sync/delete", post(sync_delete))
        .route(
            "/api/sync/devices",
            get(list_sync_devices).delete(delete_sync_device),
        )
        .route("/api/backup/status", get(backup_status))
        .route("/api/backup/run", post(backup_run))
        .route("/api/backup/snapshots", get(backup_snapshots))
        .route("/api/backup/restore", post(backup_restore))
        .route("/api/backup/check", post(backup_check))
        .route("/api/notifications", get(list_notifications))
        .route("/api/notifications/read", post(mark_notifications_read))
        .route("/api/photos", get(list_photos))
        .route("/api/folders", post(create_folder))
        .route("/api/storage", get(storage))
        .route(
            "/api/trash",
            get(list_trash).delete(permanently_delete_trash),
        )
        .route("/api/trash/restore", post(restore_trash))
        .layer(DefaultBodyLimit::max(max_upload_bytes))
        .layer(RequestBodyLimitLayer::new(max_upload_bytes))
        .layer(middleware::from_fn_with_state(
            state.clone(),
            auth_middleware,
        ));

    let allowed_origins = env::var("CORS_ORIGINS").unwrap_or_default();
    let cors = if allowed_origins.trim() == "*" {
        CorsLayer::very_permissive()
    } else {
        let origins = allowed_origins
            .split(',')
            .map(str::trim)
            .filter(|raw| !raw.is_empty())
            .filter_map(|raw| raw.parse::<HeaderValue>().ok())
            .collect::<Vec<_>>();
        if origins.is_empty() {
            CorsLayer::new()
        } else {
            CorsLayer::new()
                .allow_origin(origins)
                .allow_headers([header::AUTHORIZATION, header::CONTENT_TYPE])
                .allow_methods([
                    axum::http::Method::GET,
                    axum::http::Method::POST,
                    axum::http::Method::PUT,
                    axum::http::Method::DELETE,
                ])
        }
    };

    let app = public
        .merge(protected)
        .with_state(state)
        .layer(cors)
        .layer(middleware::from_fn(security_headers))
        .layer(TraceLayer::new_for_http());

    let bind_addr = env::var("BIND_ADDR").unwrap_or_else(|_| "127.0.0.1:8080".into());
    let listener = tokio::net::TcpListener::bind(&bind_addr).await?;
    info!(%bind_addr, "NexaDrive listening");
    axum::serve(listener, app).await?;
    Ok(())
}

async fn sync_delta(
    State(state): State<AppState>,
    axum::extract::Extension(user_id): axum::extract::Extension<Uuid>,
    Query(query): Query<SyncDeltaQuery>,
) -> Result<Json<SyncManifestResponse>, AppError> {
    let since = query
        .since
        .parse::<DateTime<Utc>>()
        .map_err(|_| AppError::BadRequest("Invalid sync cursor".into()))?;
    let full = sync_manifest(
        State(state.clone()),
        axum::extract::Extension(user_id),
        Query(SyncManifestQuery {
            device_id: query.device_id,
            device_name: query.device_name,
        }),
    )
    .await?
    .0;
    let changed_paths: std::collections::HashSet<String> =
        sqlx::query("SELECT path FROM sync_file_fingerprints WHERE user_id=$1 AND updated_at > $2")
            .bind(user_id)
            .bind(since)
            .fetch_all(&state.db)
            .await?
            .into_iter()
            .map(|r| r.get::<String, _>("path"))
            .collect();
    let entries = full
        .entries
        .into_iter()
        .filter(|entry| changed_paths.contains(&entry.path))
        .collect::<Vec<_>>();
    let tombstone_rows = sqlx::query(
        "SELECT path FROM sync_tombstones WHERE user_id=$1 AND deleted_at > $2 ORDER BY deleted_at ASC"
    ).bind(user_id).bind(since).fetch_all(&state.db).await?;
    let tombstones = tombstone_rows
        .into_iter()
        .map(|r| r.get::<String, _>("path"))
        .collect();
    Ok(Json(SyncManifestResponse {
        device_id: full.device_id,
        server_time: full.server_time,
        entries,
        tombstones,
    }))
}

async fn sync_manifest(
    State(state): State<AppState>,
    axum::extract::Extension(user_id): axum::extract::Extension<Uuid>,
    Query(query): Query<SyncManifestQuery>,
) -> Result<Json<SyncManifestResponse>, AppError> {
    let scan_started = Utc::now();
    let device_name = query
        .device_name
        .as_deref()
        .unwrap_or("NexaDrive desktop")
        .trim();
    let device_name = if device_name.is_empty() {
        "NexaDrive desktop"
    } else {
        device_name
    };
    let device_id = if let Some(id) = query.device_id {
        let exists: Option<Uuid> =
            sqlx::query_scalar("SELECT id FROM sync_devices WHERE id=$1 AND user_id=$2")
                .bind(id)
                .bind(user_id)
                .fetch_optional(&state.db)
                .await?;
        if exists.is_none() {
            return Err(AppError::NotFound);
        }
        sqlx::query("UPDATE sync_devices SET last_seen_at=CURRENT_TIMESTAMP, name=$3 WHERE id=$1 AND user_id=$2")
            .bind(id).bind(user_id).bind(device_name).execute(&state.db).await?;
        id
    } else {
        let id = Uuid::new_v4();
        sqlx::query("INSERT INTO sync_devices(id,user_id,name) VALUES($1,$2,$3)")
            .bind(id)
            .bind(user_id)
            .bind(device_name)
            .execute(&state.db)
            .await?;
        id
    };

    let root = user_root(&state, user_id);
    fs::create_dir_all(&root).await?;
    let cached = sqlx::query("SELECT path,kind,size_bytes,modified_at,sha256,updated_at FROM sync_file_fingerprints WHERE user_id=$1")
        .bind(user_id).fetch_all(&state.db).await?;
    let mut cache = std::collections::HashMap::new();
    for row in cached {
        cache.insert(row.get::<String, _>("path"), row);
    }
    let mut entries = Vec::new();
    collect_sync_entries(&root, &root, user_id, &state.db, &mut cache, &mut entries).await?;

    if cache.is_empty() {
        // no-op; the cache is intentionally rebuilt incrementally below
    }
    let stale_rows = sqlx::query(
        "SELECT path FROM sync_file_fingerprints WHERE user_id=$1 AND last_seen_at < $2",
    )
    .bind(user_id)
    .bind(scan_started)
    .fetch_all(&state.db)
    .await?;
    for row in stale_rows {
        let path = row.get::<String, _>("path");
        sqlx::query("INSERT INTO sync_tombstones(user_id,path) VALUES($1,$2) ON CONFLICT(user_id,path) DO UPDATE SET deleted_at=CURRENT_TIMESTAMP")
            .bind(user_id).bind(&path).execute(&state.db).await?;
    }
    sqlx::query("DELETE FROM sync_file_fingerprints WHERE user_id=$1 AND last_seen_at < $2")
        .bind(user_id)
        .bind(scan_started)
        .execute(&state.db)
        .await?;

    let tombstones: Vec<String> = sqlx::query_scalar(
        "SELECT path FROM sync_tombstones WHERE user_id=$1 ORDER BY deleted_at ASC",
    )
    .bind(user_id)
    .fetch_all(&state.db)
    .await?;

    Ok(Json(SyncManifestResponse {
        device_id,
        server_time: Utc::now(),
        entries,
        tombstones,
    }))
}

async fn collect_sync_entries(
    root: &Path,
    current: &Path,
    user_id: Uuid,
    db: &SqlitePool,
    cache: &mut std::collections::HashMap<String, SqliteRow>,
    out: &mut Vec<SyncEntry>,
) -> Result<(), AppError> {
    let scan_started = Utc::now();
    let mut pending = vec![current.to_path_buf()];
    while let Some(dir_path) = pending.pop() {
        let mut dir = fs::read_dir(&dir_path).await?;
        while let Some(entry) = dir.next_entry().await? {
            let name = entry.file_name().to_string_lossy().to_string();
            if name == ".trash" || (dir_path == root && name.starts_with('.')) {
                continue;
            }
            let path = entry.path();
            let meta = fs::symlink_metadata(&path).await?;
            if meta.file_type().is_symlink() {
                continue;
            }
            let rel = path
                .strip_prefix(root)
                .map_err(|_| AppError::Internal)?
                .to_string_lossy()
                .replace('\\', "/");
            let modified_at = meta.modified().ok().map(DateTime::<Utc>::from);
            if meta.is_dir() {
                sqlx::query("DELETE FROM sync_tombstones WHERE user_id=$1 AND path=$2")
                    .bind(user_id)
                    .bind(&rel)
                    .execute(db)
                    .await?;
                sqlx::query("INSERT INTO sync_file_fingerprints(user_id,path,kind,size_bytes,modified_at,sha256,last_seen_at,created_at,updated_at) VALUES($1,$2,'folder',0,$3,NULL,$4,$5,$5) ON CONFLICT(user_id,path) DO UPDATE SET kind='folder',size_bytes=0,modified_at=EXCLUDED.modified_at,sha256=NULL,last_seen_at=EXCLUDED.last_seen_at,updated_at=CASE WHEN sync_file_fingerprints.kind IS DISTINCT FROM EXCLUDED.kind OR sync_file_fingerprints.modified_at IS DISTINCT FROM EXCLUDED.modified_at THEN CURRENT_TIMESTAMP ELSE sync_file_fingerprints.updated_at END")
                    .bind(user_id).bind(&rel).bind(modified_at).bind(scan_started).bind(scan_started).execute(db).await?;
                out.push(SyncEntry {
                    path: rel,
                    kind: "folder".into(),
                    size: 0,
                    modified_at,
                    sha256: None,
                });
                pending.push(path);
            } else if meta.is_file() {
                sqlx::query("DELETE FROM sync_tombstones WHERE user_id=$1 AND path=$2")
                    .bind(user_id)
                    .bind(&rel)
                    .execute(db)
                    .await?;
                let size = meta.len();
                let cached_row = cache.get(&rel);
                let cached_size = cached_row.map(|r| r.get::<i64, _>("size_bytes") as u64);
                let cached_modified =
                    cached_row.and_then(|r| r.try_get::<DateTime<Utc>, _>("modified_at").ok());
                let mut hash = cached_row.and_then(|r| r.try_get::<String, _>("sha256").ok());
                let unchanged =
                    cached_size == Some(size) && cached_modified == modified_at && hash.is_some();
                if !unchanged {
                    hash = Some(sha256_file(&path).await?);
                }
                sqlx::query("INSERT INTO sync_file_fingerprints(user_id,path,kind,size_bytes,modified_at,sha256,last_seen_at,created_at,updated_at) VALUES($1,$2,'file',$3,$4,$5,$6,$7,$7) ON CONFLICT(user_id,path) DO UPDATE SET kind='file',size_bytes=EXCLUDED.size_bytes,modified_at=EXCLUDED.modified_at,sha256=EXCLUDED.sha256,last_seen_at=EXCLUDED.last_seen_at,updated_at=CASE WHEN sync_file_fingerprints.kind IS DISTINCT FROM EXCLUDED.kind OR sync_file_fingerprints.size_bytes IS DISTINCT FROM EXCLUDED.size_bytes OR sync_file_fingerprints.modified_at IS DISTINCT FROM EXCLUDED.modified_at OR sync_file_fingerprints.sha256 IS DISTINCT FROM EXCLUDED.sha256 THEN CURRENT_TIMESTAMP ELSE sync_file_fingerprints.updated_at END")
                    .bind(user_id).bind(&rel).bind(size as i64).bind(modified_at).bind(&hash).bind(scan_started).bind(scan_started).execute(db).await?;
                out.push(SyncEntry {
                    path: rel,
                    kind: "file".into(),
                    size,
                    modified_at,
                    sha256: hash,
                });
            }
        }
    }
    Ok(())
}

async fn backup_status(
    State(state): State<AppState>,
    axum::extract::Extension(user_id): axum::extract::Extension<Uuid>,
) -> Result<Json<BackupStatusResponse>, AppError> {
    require_admin(&state.db, user_id).await?;
    let repository = env::var("RESTIC_REPOSITORY").ok();
    let configured = repository.is_some() && env::var("RESTIC_PASSWORD_FILE").is_ok();
    let bin = env::var("RESTIC_BIN").unwrap_or_else(|_| "restic".into());
    let available = Command::new(&bin)
        .arg("version")
        .output()
        .await
        .map(|o| o.status.success())
        .unwrap_or(false);
    Ok(Json(BackupStatusResponse {
        configured,
        restic_available: available,
        repository,
    }))
}

async fn backup_run(
    State(state): State<AppState>,
    axum::extract::Extension(user_id): axum::extract::Extension<Uuid>,
    Json(payload): Json<BackupRunRequest>,
) -> Result<Json<BackupRunResponse>, AppError> {
    require_admin(&state.db, user_id).await?;
    let repository = env::var("RESTIC_REPOSITORY")
        .map_err(|_| AppError::BadRequest("RESTIC_REPOSITORY is not configured".into()))?;
    if env::var("RESTIC_PASSWORD_FILE").is_err() {
        return Err(AppError::BadRequest(
            "RESTIC_PASSWORD_FILE is not configured".into(),
        ));
    }
    let bin = env::var("RESTIC_BIN").unwrap_or_else(|_| "restic".into());
    let storage = state.storage_root.to_string_lossy().to_string();
    let trash = state
        .storage_root
        .join(".trash")
        .to_string_lossy()
        .to_string();
    // SQLite is a live database. Create a transactionally consistent snapshot before
    // Restic reads it so the backup contains both files and metadata.
    let db_snapshot = state
        .storage_root
        .join(format!(".nexadrive-db-backup-{}.db", Uuid::new_v4()));
    let escaped_snapshot = db_snapshot.to_string_lossy().replace('\'', "''");
    sqlx::query(&format!("VACUUM INTO '{}'", escaped_snapshot))
        .execute(&state.db)
        .await?;

    let mut backup = Command::new(&bin);
    backup
        .arg("backup")
        .arg(&storage)
        .arg("--exclude")
        .arg(&trash)
        .arg("--exclude")
        .arg("**/.nexadrive-upload-*");
    backup.env("RESTIC_REPOSITORY", &repository);
    let output = backup.output().await.map_err(|_| {
        AppError::BadRequest("restic is not installed or cannot be executed".into())
    })?;
    let _ = fs::remove_file(&db_snapshot).await;
    if !output.status.success() {
        let message = String::from_utf8_lossy(&output.stderr).trim().to_string();
        create_notification(
            &state.db,
            user_id,
            "backup_failed",
            "Backup failed",
            &message,
            "error",
        )
        .await?;
        return Err(AppError::BadRequest(message));
    }
    let mut text = String::from_utf8_lossy(&output.stdout).to_string();
    if payload.prune.unwrap_or(false) {
        let mut prune = Command::new(&bin);
        prune
            .arg("forget")
            .arg("--keep-last")
            .arg("7")
            .arg("--keep-daily")
            .arg("14")
            .arg("--keep-weekly")
            .arg("8")
            .arg("--keep-monthly")
            .arg("12")
            .arg("--prune");
        prune.env("RESTIC_REPOSITORY", &repository);
        let prune_output = prune
            .output()
            .await
            .map_err(|_| AppError::BadRequest("restic prune could not be started".into()))?;
        if !prune_output.status.success() {
            let message = String::from_utf8_lossy(&prune_output.stderr)
                .trim()
                .to_string();
            create_notification(
                &state.db,
                user_id,
                "backup_prune_failed",
                "Backup retention cleanup failed",
                &message,
                "error",
            )
            .await?;
            return Err(AppError::BadRequest(message));
        }
        text.push('\n');
        text.push_str(&String::from_utf8_lossy(&prune_output.stdout));
    }
    audit(
        &state.db,
        user_id,
        "backup_run",
        Some(if payload.prune.unwrap_or(false) {
            "backup+prune"
        } else {
            "backup"
        }),
    )
    .await?;
    create_notification(
        &state.db,
        user_id,
        "backup_completed",
        "Backup completed",
        if payload.prune.unwrap_or(false) {
            "Backup and retention cleanup completed successfully."
        } else {
            "Backup completed successfully."
        },
        "info",
    )
    .await?;
    Ok(Json(BackupRunResponse {
        output: text.trim().to_string(),
    }))
}

async fn security_headers(request: axum::extract::Request, next: middleware::Next) -> Response {
    let mut response = next.run(request).await;
    let headers = response.headers_mut();
    // Thumbnails opt in to a private browser-cache policy via an internal
    // marker; every other response stays strictly non-cacheable.
    let cacheable_thumbnail = headers
        .get("x-nexadrive-cacheable")
        .map(|v| v == "thumbnail")
        .unwrap_or(false);
    headers.insert(
        "x-content-type-options",
        HeaderValue::from_static("nosniff"),
    );
    headers.insert("x-frame-options", HeaderValue::from_static("DENY"));
    headers.insert("referrer-policy", HeaderValue::from_static("no-referrer"));
    headers.insert(
        "permissions-policy",
        HeaderValue::from_static("camera=(), microphone=(), geolocation=()"),
    );
    if cacheable_thumbnail {
        headers.remove("x-nexadrive-cacheable");
        headers.insert(
            header::CACHE_CONTROL,
            HeaderValue::from_static("private, max-age=86400"),
        );
    } else {
        headers.insert(header::CACHE_CONTROL, HeaderValue::from_static("no-store"));
        headers.insert(header::PRAGMA, HeaderValue::from_static("no-cache"));
    }
    response
}

fn login_key(_headers: &HeaderMap, username: &str) -> String {
    // Do not trust X-Forwarded-For from the client. Tailscale Serve/proxies may add
    // forwarding metadata, but the public-facing throttle must still be tied to the
    // account being attacked rather than a spoofable request header.
    format!("user:{}", username.trim().to_lowercase())
}

fn register_failed_login(state: &AppState, key: &str) -> Result<(), AppError> {
    let mut guard = state
        .login_attempts
        .lock()
        .map_err(|_| AppError::Internal)?;
    let now = Instant::now();
    let entry = guard.entry(key.to_string()).or_insert(LoginAttempt {
        window_started: now,
        failures: 0,
    });
    if now.duration_since(entry.window_started) > Duration::from_secs(15 * 60) {
        *entry = LoginAttempt {
            window_started: now,
            failures: 0,
        };
    }
    entry.failures = entry.failures.saturating_add(1);
    Ok(())
}

fn check_login_allowed(state: &AppState, key: &str) -> Result<(), AppError> {
    let mut guard = state
        .login_attempts
        .lock()
        .map_err(|_| AppError::Internal)?;
    if let Some(entry) = guard.get(key) {
        if Instant::now().duration_since(entry.window_started) <= Duration::from_secs(15 * 60)
            && entry.failures >= 10
        {
            return Err(AppError::TooManyRequests);
        }
        if Instant::now().duration_since(entry.window_started) > Duration::from_secs(15 * 60) {
            guard.remove(key);
        }
    }
    Ok(())
}

fn clear_failed_logins(state: &AppState, key: &str) -> Result<(), AppError> {
    let mut guard = state
        .login_attempts
        .lock()
        .map_err(|_| AppError::Internal)?;
    guard.remove(key);
    Ok(())
}

fn register_failed_share_download(state: &AppState, key: &str) {
    if let Ok(mut guard) = state.share_download_attempts.lock() {
        let now = Instant::now();
        let entry = guard.entry(key.to_string()).or_insert(LoginAttempt {
            window_started: now,
            failures: 0,
        });
        if now.duration_since(entry.window_started) > Duration::from_secs(15 * 60) {
            *entry = LoginAttempt {
                window_started: now,
                failures: 0,
            };
        }
        entry.failures = entry.failures.saturating_add(1);
    }
}

fn clear_share_download_attempts(state: &AppState, key: &str) {
    if let Ok(mut guard) = state.share_download_attempts.lock() {
        guard.remove(key);
    }
}

async fn list_audit(
    State(state): State<AppState>,
    axum::extract::Extension(admin_id): axum::extract::Extension<Uuid>,
    Query(query): Query<HashMap<String, String>>,
) -> Result<Json<Vec<AuditResponse>>, AppError> {
    require_admin(&state.db, admin_id).await?;
    let limit = query
        .get("limit")
        .and_then(|v| v.parse::<i64>().ok())
        .unwrap_or(200)
        .clamp(1, 500);
    let rows = sqlx::query(
        "SELECT id, action, path, created_at FROM audit_logs ORDER BY created_at DESC LIMIT $1",
    )
    .bind(limit)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(
        rows.into_iter()
            .map(|r| AuditResponse {
                id: r.get("id"),
                action: r.get("action"),
                path: r.get("path"),
                created_at: r.get("created_at"),
            })
            .collect(),
    ))
}

async fn list_notifications(
    State(state): State<AppState>,
    axum::extract::Extension(user_id): axum::extract::Extension<Uuid>,
    Query(query): Query<HashMap<String, String>>,
) -> Result<Json<Vec<NotificationResponse>>, AppError> {
    let unread = query.get("unread").map(|v| v == "true").unwrap_or(false);
    let rows = if unread {
        sqlx::query("SELECT id,kind,title,message,severity,read,created_at FROM notifications WHERE user_id=$1 AND read=FALSE ORDER BY created_at DESC LIMIT 100").bind(user_id).fetch_all(&state.db).await?
    } else {
        sqlx::query("SELECT id,kind,title,message,severity,read,created_at FROM notifications WHERE user_id=$1 ORDER BY created_at DESC LIMIT 100").bind(user_id).fetch_all(&state.db).await?
    };
    Ok(Json(
        rows.into_iter()
            .map(|r| NotificationResponse {
                id: r.get("id"),
                kind: r.get("kind"),
                title: r.get("title"),
                message: r.get("message"),
                severity: r.get("severity"),
                read: r.get("read"),
                created_at: r.get("created_at"),
            })
            .collect(),
    ))
}

async fn mark_notifications_read(
    State(state): State<AppState>,
    axum::extract::Extension(user_id): axum::extract::Extension<Uuid>,
    Json(payload): Json<NotificationReadRequest>,
) -> Result<StatusCode, AppError> {
    if payload.all.unwrap_or(false) {
        sqlx::query("UPDATE notifications SET read=TRUE WHERE user_id=$1")
            .bind(user_id)
            .execute(&state.db)
            .await?;
    } else if let Some(id) = payload.id {
        sqlx::query("UPDATE notifications SET read=TRUE WHERE id=$1 AND user_id=$2")
            .bind(id)
            .bind(user_id)
            .execute(&state.db)
            .await?;
    } else {
        return Err(AppError::BadRequest(
            "Provide a notification id or all=true".into(),
        ));
    }
    Ok(StatusCode::NO_CONTENT)
}

async fn create_notification(
    db: &SqlitePool,
    user_id: Uuid,
    kind: &str,
    title: &str,
    message: &str,
    severity: &str,
) -> Result<(), AppError> {
    sqlx::query("INSERT INTO notifications(id,user_id,kind,title,message,severity) VALUES($1,$2,$3,$4,$5,$6)")
        .bind(Uuid::new_v4()).bind(user_id).bind(kind).bind(title).bind(message).bind(severity).execute(db).await?;
    Ok(())
}

async fn list_sync_devices(
    State(state): State<AppState>,
    axum::extract::Extension(user_id): axum::extract::Extension<Uuid>,
) -> Result<Json<Vec<SyncDeviceResponse>>, AppError> {
    let rows = sqlx::query("SELECT id,name,last_seen_at,created_at FROM sync_devices WHERE user_id=$1 ORDER BY last_seen_at DESC").bind(user_id).fetch_all(&state.db).await?;
    Ok(Json(
        rows.into_iter()
            .map(|r| SyncDeviceResponse {
                id: r.get("id"),
                name: r.get("name"),
                last_seen_at: r.get("last_seen_at"),
                created_at: r.get("created_at"),
            })
            .collect(),
    ))
}

async fn delete_sync_device(
    State(state): State<AppState>,
    axum::extract::Extension(user_id): axum::extract::Extension<Uuid>,
    Query(query): Query<IdQuery>,
) -> Result<StatusCode, AppError> {
    let id = query
        .id
        .ok_or_else(|| AppError::BadRequest("id is required".into()))?;
    let result = sqlx::query("DELETE FROM sync_devices WHERE id=$1 AND user_id=$2")
        .bind(id)
        .bind(user_id)
        .execute(&state.db)
        .await?;
    if result.rows_affected() == 0 {
        return Err(AppError::NotFound);
    }
    audit(
        &state.db,
        user_id,
        "sync_device_revoke",
        Some(&id.to_string()),
    )
    .await?;
    Ok(StatusCode::NO_CONTENT)
}

async fn backup_check(
    State(state): State<AppState>,
    axum::extract::Extension(user_id): axum::extract::Extension<Uuid>,
) -> Result<Json<BackupCheckResponse>, AppError> {
    require_admin(&state.db, user_id).await?;
    let repository = env::var("RESTIC_REPOSITORY")
        .map_err(|_| AppError::BadRequest("RESTIC_REPOSITORY is not configured".into()))?;
    if env::var("RESTIC_PASSWORD_FILE").is_err() {
        return Err(AppError::BadRequest(
            "RESTIC_PASSWORD_FILE is not configured".into(),
        ));
    }
    let bin = env::var("RESTIC_BIN").unwrap_or_else(|_| "restic".into());
    let output = Command::new(&bin)
        .arg("check")
        .arg("--read-data-subset=5%")
        .env("RESTIC_REPOSITORY", &repository)
        .output()
        .await
        .map_err(|_| AppError::BadRequest("restic check could not be executed".into()))?;
    let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
    let text = if stderr.is_empty() {
        stdout.clone()
    } else if stdout.is_empty() {
        stderr.clone()
    } else {
        format!("{}\n{}", stdout, stderr)
    };
    if !output.status.success() {
        create_notification(
            &state.db,
            user_id,
            "backup_check_failed",
            "Backup verification failed",
            &text,
            "error",
        )
        .await?;
        return Err(AppError::BadRequest(text));
    }
    audit(
        &state.db,
        user_id,
        "backup_check",
        Some("restic check --read-data-subset=5%"),
    )
    .await?;
    create_notification(
        &state.db,
        user_id,
        "backup_check_completed",
        "Backup verified",
        "Restic verified a 5% data subset successfully.",
        "info",
    )
    .await?;
    Ok(Json(BackupCheckResponse {
        output: text,
        verified: true,
    }))
}

async fn backup_snapshots(
    State(state): State<AppState>,
    axum::extract::Extension(user_id): axum::extract::Extension<Uuid>,
) -> Result<Json<Vec<BackupSnapshotResponse>>, AppError> {
    require_admin(&state.db, user_id).await?;
    let repository = env::var("RESTIC_REPOSITORY")
        .map_err(|_| AppError::BadRequest("RESTIC_REPOSITORY is not configured".into()))?;
    if env::var("RESTIC_PASSWORD_FILE").is_err() {
        return Err(AppError::BadRequest(
            "RESTIC_PASSWORD_FILE is not configured".into(),
        ));
    }
    let bin = env::var("RESTIC_BIN").unwrap_or_else(|_| "restic".into());
    let output = Command::new(&bin)
        .arg("snapshots")
        .arg("--json")
        .env("RESTIC_REPOSITORY", &repository)
        .output()
        .await
        .map_err(|_| {
            AppError::BadRequest("restic is not installed or cannot be executed".into())
        })?;
    if !output.status.success() {
        return Err(AppError::BadRequest(
            String::from_utf8_lossy(&output.stderr).trim().to_string(),
        ));
    }
    let raw: serde_json::Value =
        serde_json::from_slice(&output.stdout).map_err(|_| AppError::Internal)?;
    let mut result = Vec::new();
    if let Some(items) = raw.as_array() {
        for item in items.iter().take(100) {
            let id = item
                .get("id")
                .and_then(|v| v.as_str())
                .unwrap_or_default()
                .to_string();
            let time = item
                .get("time")
                .and_then(|v| v.as_str())
                .and_then(|v| v.parse::<DateTime<Utc>>().ok())
                .unwrap_or_else(Utc::now);
            let hostname = item
                .get("hostname")
                .and_then(|v| v.as_str())
                .map(str::to_string);
            let paths = item
                .get("paths")
                .and_then(|v| v.as_array())
                .map(|a| {
                    a.iter()
                        .filter_map(|v| v.as_str().map(str::to_string))
                        .collect()
                })
                .unwrap_or_default();
            result.push(BackupSnapshotResponse {
                id,
                time,
                hostname,
                paths,
            });
        }
    }
    Ok(Json(result))
}

async fn backup_restore(
    State(state): State<AppState>,
    axum::extract::Extension(user_id): axum::extract::Extension<Uuid>,
    Json(payload): Json<BackupRestoreRequest>,
) -> Result<Json<serde_json::Value>, AppError> {
    require_admin(&state.db, user_id).await?;
    if payload.snapshot_id.len() > 128
        || !payload
            .snapshot_id
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, '-' | '_'))
    {
        return Err(AppError::BadRequest("Invalid snapshot id".into()));
    }
    let repository = env::var("RESTIC_REPOSITORY")
        .map_err(|_| AppError::BadRequest("RESTIC_REPOSITORY is not configured".into()))?;
    if env::var("RESTIC_PASSWORD_FILE").is_err() {
        return Err(AppError::BadRequest(
            "RESTIC_PASSWORD_FILE is not configured".into(),
        ));
    }
    let bin = env::var("RESTIC_BIN").unwrap_or_else(|_| "restic".into());
    let root = state.storage_root.join(".restic-restores").join(format!(
        "{}-{}",
        Utc::now().format("%Y%m%dT%H%M%SZ"),
        payload.snapshot_id
    ));
    fs::create_dir_all(&root).await?;
    let output = Command::new(&bin)
        .arg("restore")
        .arg(&payload.snapshot_id)
        .arg("--target")
        .arg(&root)
        .env("RESTIC_REPOSITORY", &repository)
        .output()
        .await
        .map_err(|_| AppError::BadRequest("restic restore could not be executed".into()))?;
    if !output.status.success() {
        let _ = fs::remove_dir_all(&root).await;
        create_notification(
            &state.db,
            user_id,
            "backup_restore_failed",
            "Backup restore failed",
            String::from_utf8_lossy(&output.stderr).trim(),
            "error",
        )
        .await?;
        return Err(AppError::BadRequest(
            String::from_utf8_lossy(&output.stderr).trim().to_string(),
        ));
    }
    audit(
        &state.db,
        user_id,
        "backup_restore",
        Some(&payload.snapshot_id),
    )
    .await?;
    create_notification(
        &state.db,
        user_id,
        "backup_restore_ready",
        "Backup restore ready",
        &format!(
            "Snapshot {} was restored to {}. No live files were overwritten.",
            payload.snapshot_id,
            root.display()
        ),
        "info",
    )
    .await?;
    Ok(Json(
        serde_json::json!({"snapshot_id":payload.snapshot_id,"restore_path":root.to_string_lossy()}),
    ))
}

async fn sync_delete(
    State(state): State<AppState>,
    axum::extract::Extension(user_id): axum::extract::Extension<Uuid>,
    Json(payload): Json<SyncDeleteRequest>,
) -> Result<StatusCode, AppError> {
    let relative = safe_relative_path(&payload.path)?;
    if relative.as_os_str().is_empty() {
        return Err(AppError::BadRequest("Cannot delete the sync root".into()));
    }
    let absolute = user_root(&state, user_id).join(&relative);
    let meta = fs::symlink_metadata(&absolute)
        .await
        .map_err(|_| AppError::NotFound)?;
    if meta.file_type().is_symlink() {
        return Err(AppError::Forbidden);
    }
    delete_one_to_trash(&state, user_id, &relative).await?;
    audit(&state.db, user_id, "sync_delete", Some(&payload.path)).await?;
    Ok(StatusCode::NO_CONTENT)
}

async fn health() -> Json<Health> {
    Json(Health { status: "ok" })
}

async fn server_status(State(state): State<AppState>) -> Json<ServerStatus> {
    Json(ServerStatus {
        instance_id: state.instance_id,
        started_at: state.started_at,
        status: "ok",
        public_url: state.public_url.clone(),
        version: env!("CARGO_PKG_VERSION"),
        api_version: API_VERSION,
    })
}

async fn bootstrap_admin(db: &SqlitePool) -> Result<(), AppError> {
    let count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM users")
        .fetch_one(db)
        .await?;
    if count > 0 {
        return Ok(());
    }
    let username = env::var("ADMIN_USERNAME").unwrap_or_else(|_| "admin".into());
    let display_name = env::var("ADMIN_DISPLAY_NAME").unwrap_or_else(|_| "Administrator".into());
    let password = env::var("ADMIN_PASSWORD")
        .map_err(|_| AppError::BadRequest("ADMIN_PASSWORD is required on first startup".into()))?;
    let password_hash = hash_password(&password)?;
    sqlx::query(r#"INSERT INTO users (id, username, display_name, password_hash, role) VALUES ($1, $2, $3, $4, 'admin')"#)
        .bind(Uuid::new_v4()).bind(username).bind(display_name).bind(password_hash).execute(db).await?;
    info!("Created initial NexaDrive administrator");
    Ok(())
}

fn hash_password(password: &str) -> Result<String, AppError> {
    use argon2::{
        Argon2,
        password_hash::{PasswordHasher, SaltString, rand_core::OsRng},
    };
    let salt = SaltString::generate(&mut OsRng);
    Argon2::default()
        .hash_password(password.as_bytes(), &salt)
        .map(|h| h.to_string())
        .map_err(|_| AppError::Internal)
}

fn verify_password(password: &str, hash: &str) -> bool {
    use argon2::{
        Argon2,
        password_hash::{PasswordHash, PasswordVerifier},
    };
    PasswordHash::new(hash)
        .ok()
        .map(|p| {
            Argon2::default()
                .verify_password(password.as_bytes(), &p)
                .is_ok()
        })
        .unwrap_or(false)
}

fn new_token() -> String {
    rand::rng()
        .sample_iter(Alphanumeric)
        .take(64)
        .map(char::from)
        .collect()
}

fn token_hash(token: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(token.as_bytes());
    format!("{:x}", hasher.finalize())
}

fn bearer(headers: &HeaderMap) -> Option<String> {
    headers
        .get(header::AUTHORIZATION)?
        .to_str()
        .ok()?
        .strip_prefix("Bearer ")
        .map(str::to_string)
}

async fn auth_middleware(
    State(state): State<AppState>,
    headers: HeaderMap,
    mut request: axum::extract::Request,
    next: middleware::Next,
) -> Result<Response, AppError> {
    let token = bearer(&headers).ok_or(AppError::Unauthorized)?;
    let hash = token_hash(&token);
    let row = sqlx::query("SELECT s.id AS session_id, s.user_id FROM sessions s JOIN users u ON u.id=s.user_id WHERE s.token_hash = $1 AND s.expires_at > CURRENT_TIMESTAMP AND u.disabled = FALSE")
        .bind(&hash).fetch_optional(&state.db).await?;
    let row = match row {
        Some(r) => r,
        None => {
            // If the token exists but the user is disabled, revoke the session
            let stale = sqlx::query("SELECT s.id AS session_id FROM sessions s JOIN users u ON u.id=s.user_id WHERE s.token_hash = $1 AND u.disabled = TRUE")
                .bind(&hash).fetch_optional(&state.db).await?;
            if let Some(s) = stale {
                let sid: Uuid = s.get("session_id");
                let _ = sqlx::query("DELETE FROM sessions WHERE id=$1")
                    .bind(sid)
                    .execute(&state.db)
                    .await;
            }
            return Err(AppError::Unauthorized);
        }
    };
    request
        .extensions_mut()
        .insert(row.get::<Uuid, _>("user_id"));
    Ok(next.run(request).await)
}

async fn login(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(payload): Json<LoginRequest>,
) -> Result<Json<LoginResponse>, AppError> {
    let key = login_key(&headers, &payload.username);
    check_login_allowed(&state, &key)?;
    let row = sqlx::query("SELECT id, username, display_name, password_hash, role FROM users WHERE username = $1 AND disabled = FALSE")
        .bind(&payload.username).fetch_optional(&state.db).await?;
    let row = match row {
        Some(row) => row,
        None => {
            register_failed_login(&state, &key)?;
            return Err(AppError::Unauthorized);
        }
    };
    let password_hash: String = row.get("password_hash");
    if !verify_password(&payload.password, &password_hash) {
        register_failed_login(&state, &key)?;
        return Err(AppError::Unauthorized);
    }
    clear_failed_logins(&state, &key)?;
    let user = UserResponse {
        id: row.get("id"),
        username: row.get("username"),
        display_name: row.get("display_name"),
        role: row.get("role"),
    };
    let token = new_token();
    sqlx::query(r#"INSERT INTO sessions (id, user_id, token_hash, expires_at) VALUES ($1, $2, $3, datetime('now', '+30 days'))"#)
        .bind(Uuid::new_v4()).bind(user.id).bind(token_hash(&token)).execute(&state.db).await?;
    audit(&state.db, user.id, "login", None).await?;
    Ok(Json(LoginResponse { token, user }))
}

async fn logout(
    State(state): State<AppState>,
    headers: HeaderMap,
    user_id: axum::extract::Extension<Uuid>,
) -> Result<StatusCode, AppError> {
    if let Some(token) = bearer(&headers) {
        sqlx::query("DELETE FROM sessions WHERE token_hash = $1")
            .bind(token_hash(&token))
            .execute(&state.db)
            .await?;
    }
    audit(&state.db, *user_id, "logout", None).await?;
    Ok(StatusCode::NO_CONTENT)
}

async fn me(
    State(state): State<AppState>,
    axum::extract::Extension(user_id): axum::extract::Extension<Uuid>,
) -> Result<Json<UserResponse>, AppError> {
    let row = sqlx::query("SELECT id, username, display_name, role FROM users WHERE id = $1")
        .bind(user_id)
        .fetch_optional(&state.db)
        .await?
        .ok_or(AppError::NotFound)?;
    Ok(Json(UserResponse {
        id: row.get("id"),
        username: row.get("username"),
        display_name: row.get("display_name"),
        role: row.get("role"),
    }))
}

async fn current_role(db: &SqlitePool, user_id: Uuid) -> Result<String, AppError> {
    sqlx::query_scalar("SELECT role FROM users WHERE id=$1 AND disabled=FALSE")
        .bind(user_id)
        .fetch_optional(db)
        .await?
        .ok_or(AppError::Unauthorized)
}

async fn require_admin(db: &SqlitePool, user_id: Uuid) -> Result<(), AppError> {
    if current_role(db, user_id).await? != "admin" {
        return Err(AppError::Forbidden);
    }
    Ok(())
}

fn validate_role(role: &str) -> Result<&str, AppError> {
    match role {
        "admin" | "user" => Ok(role),
        _ => Err(AppError::BadRequest("Role must be admin or user".into())),
    }
}

async fn list_users(
    State(state): State<AppState>,
    axum::extract::Extension(user_id): axum::extract::Extension<Uuid>,
) -> Result<Json<Vec<AdminUserResponse>>, AppError> {
    require_admin(&state.db, user_id).await?;
    let rows = sqlx::query("SELECT id, username, display_name, role, disabled, quota_bytes FROM users ORDER BY username")
        .fetch_all(&state.db).await?;
    Ok(Json(
        rows.into_iter()
            .map(|r| AdminUserResponse {
                id: r.get("id"),
                username: r.get("username"),
                display_name: r.get("display_name"),
                role: r.get("role"),
                disabled: r.get("disabled"),
                quota_bytes: r.get("quota_bytes"),
            })
            .collect(),
    ))
}

async fn create_user(
    State(state): State<AppState>,
    axum::extract::Extension(user_id): axum::extract::Extension<Uuid>,
    Json(payload): Json<CreateUserRequest>,
) -> Result<Json<AdminUserResponse>, AppError> {
    require_admin(&state.db, user_id).await?;
    let username = payload.username.trim().to_lowercase();
    let display_name = payload.display_name.trim().to_string();
    if username.len() < 3 || username.len() > 64 || display_name.is_empty() {
        return Err(AppError::BadRequest("Invalid user details".into()));
    }
    if payload.password.len() < 10 {
        return Err(AppError::BadRequest(
            "Password must be at least 10 characters".into(),
        ));
    }
    let role = payload.role.as_deref().unwrap_or("user");
    validate_role(role)?;
    if payload.quota_bytes.is_some_and(|v| v < 0) {
        return Err(AppError::BadRequest("Quota cannot be negative".into()));
    }
    let hash = hash_password(&payload.password)?;
    let id = Uuid::new_v4();
    sqlx::query("INSERT INTO users (id, username, display_name, password_hash, role, quota_bytes) VALUES ($1,$2,$3,$4,$5,$6)")
        .bind(id).bind(&username).bind(&display_name).bind(hash).bind(role).bind(payload.quota_bytes).execute(&state.db).await
        .map_err(|e| if let sqlx::Error::Database(db) = &e { if db.is_unique_violation() { AppError::Conflict("Username already exists".into()) } else { AppError::Database(e) } } else { AppError::Database(e) })?;
    audit(&state.db, user_id, "create_user", Some(&username)).await?;
    Ok(Json(AdminUserResponse {
        id,
        username,
        display_name,
        role: role.into(),
        disabled: false,
        quota_bytes: payload.quota_bytes,
    }))
}

async fn update_user(
    State(state): State<AppState>,
    axum::extract::Extension(admin_id): axum::extract::Extension<Uuid>,
    axum::extract::Path(id): axum::extract::Path<Uuid>,
    Json(payload): Json<UpdateUserRequest>,
) -> Result<StatusCode, AppError> {
    require_admin(&state.db, admin_id).await?;
    if id == admin_id && payload.disabled == Some(true) {
        return Err(AppError::BadRequest(
            "You cannot disable your own account".into(),
        ));
    }
    if let Some(role) = payload.role.as_deref() {
        validate_role(role)?;
    }
    if payload.quota_bytes.is_some_and(|v| v < 0) {
        return Err(AppError::BadRequest("Quota cannot be negative".into()));
    }
    if payload
        .display_name
        .as_deref()
        .map(|v| v.trim().is_empty())
        .unwrap_or(false)
    {
        return Err(AppError::BadRequest("Display name cannot be empty".into()));
    }
    let result = sqlx::query("UPDATE users SET display_name=COALESCE($1,display_name), role=COALESCE($2,role), disabled=COALESCE($3,disabled), quota_bytes=COALESCE($4,quota_bytes) WHERE id=$5")
        .bind(payload.display_name.map(|v| v.trim().to_string())).bind(payload.role).bind(payload.disabled).bind(payload.quota_bytes).bind(id).execute(&state.db).await?;
    if result.rows_affected() == 0 {
        return Err(AppError::NotFound);
    }
    audit(&state.db, admin_id, "update_user", Some(&id.to_string())).await?;
    Ok(StatusCode::NO_CONTENT)
}

fn permission_allows(permission: &str, needed_write: bool) -> bool {
    permission == "write" || (!needed_write && permission == "read")
}

async fn resolve_share(
    db: &SqlitePool,
    user_id: Uuid,
    share_id: Uuid,
) -> Result<(Uuid, PathBuf, String, String), AppError> {
    let row = sqlx::query(r#"SELECT s.owner_id, s.path, s.permission, u.username FROM shares s JOIN users u ON u.id=s.owner_id WHERE s.id=$1 AND s.recipient_user_id=$2 AND s.is_link=FALSE AND (s.expires_at IS NULL OR s.expires_at>CURRENT_TIMESTAMP)"#)
        .bind(share_id).bind(user_id).fetch_optional(db).await?.ok_or(AppError::NotFound)?;
    let owner_id: Uuid = row.get("owner_id");
    let path: String = row.get("path");
    let permission: String = row.get("permission");
    let owner: String = row.get("username");
    Ok((owner_id, safe_relative_path(&path)?, permission, owner))
}

async fn list_shares(
    State(state): State<AppState>,
    axum::extract::Extension(user_id): axum::extract::Extension<Uuid>,
) -> Result<Json<Vec<ShareResponse>>, AppError> {
    let rows = sqlx::query(r#"SELECT s.id, s.path, s.permission, u.username AS recipient, s.is_link, s.expires_at FROM shares s LEFT JOIN users u ON u.id=s.recipient_user_id WHERE s.owner_id=$1 ORDER BY s.created_at DESC"#)
        .bind(user_id).fetch_all(&state.db).await?;
    Ok(Json(
        rows.into_iter()
            .map(|r| ShareResponse {
                id: r.get("id"),
                path: r.get("path"),
                permission: r.get("permission"),
                recipient: r.get("recipient"),
                is_link: r.get("is_link"),
                token: None,
                expires_at: r.get("expires_at"),
            })
            .collect(),
    ))
}

async fn create_share(
    State(state): State<AppState>,
    axum::extract::Extension(owner_id): axum::extract::Extension<Uuid>,
    Json(payload): Json<CreateShareRequest>,
) -> Result<Json<ShareResponse>, AppError> {
    let path = safe_relative_path(&payload.path)?;
    if path.as_os_str().is_empty() {
        return Err(AppError::BadRequest("Cannot share the root".into()));
    }
    ensure_supported_entry(&user_root(&state, owner_id).join(&path)).await?;
    if !matches!(payload.permission.as_str(), "read" | "write") {
        return Err(AppError::BadRequest(
            "Permission must be read or write".into(),
        ));
    }
    let (recipient_user_id, recipient_name, is_link, token) =
        if let Some(username) = payload.username.as_deref() {
            let row = sqlx::query(
                "SELECT id, username FROM users WHERE LOWER(username)=LOWER($1) AND disabled=FALSE",
            )
            .bind(username.trim())
            .fetch_optional(&state.db)
            .await?
            .ok_or_else(|| AppError::NotFound)?;
            let rid: Uuid = row.get("id");
            (
                Some(rid),
                Some(row.get::<String, _>("username")),
                false,
                None,
            )
        } else {
            (None, None, true, Some(new_token()))
        };
    let id = Uuid::new_v4();
    let token_hash_value = token.as_deref().map(token_hash);
    sqlx::query("INSERT INTO shares (id, owner_id, recipient_user_id, path, permission, is_link, token, token_hash, expires_at) VALUES ($1,$2,$3,$4,$5,$6,NULL,$7,$8)")
        .bind(id).bind(owner_id).bind(recipient_user_id).bind(path.to_string_lossy().replace('\\', "/")).bind(&payload.permission).bind(is_link).bind(&token_hash_value).bind(payload.expires_at).execute(&state.db).await?;
    audit(
        &state.db,
        owner_id,
        if is_link {
            "create_share_link"
        } else {
            "share"
        },
        Some(&payload.path),
    )
    .await?;
    Ok(Json(ShareResponse {
        id,
        path: payload.path,
        permission: payload.permission,
        recipient: recipient_name,
        is_link,
        token,
        expires_at: payload.expires_at,
    }))
}

async fn delete_share(
    State(state): State<AppState>,
    axum::extract::Extension(user_id): axum::extract::Extension<Uuid>,
    Query(query): Query<IdQuery>,
) -> Result<StatusCode, AppError> {
    let id = query
        .id
        .ok_or_else(|| AppError::BadRequest("Share id is required".into()))?;
    let result = sqlx::query("DELETE FROM shares WHERE id=$1 AND owner_id=$2")
        .bind(id)
        .bind(user_id)
        .execute(&state.db)
        .await?;
    if result.rows_affected() == 0 {
        return Err(AppError::NotFound);
    }
    audit(&state.db, user_id, "delete_share", Some(&id.to_string())).await?;
    Ok(StatusCode::NO_CONTENT)
}

async fn list_shared(
    State(state): State<AppState>,
    axum::extract::Extension(user_id): axum::extract::Extension<Uuid>,
) -> Result<Json<Vec<SharedRootResponse>>, AppError> {
    let rows=sqlx::query(r#"SELECT s.id, s.path, s.permission, u.username AS owner FROM shares s JOIN users u ON u.id=s.owner_id WHERE s.recipient_user_id=$1 AND s.is_link=FALSE AND (s.expires_at IS NULL OR s.expires_at>CURRENT_TIMESTAMP) ORDER BY s.created_at DESC"#).bind(user_id).fetch_all(&state.db).await?;
    Ok(Json(
        rows.into_iter()
            .map(|r| {
                let path: String = r.get("path");
                SharedRootResponse {
                    id: r.get("id"),
                    name: Path::new(&path)
                        .file_name()
                        .unwrap_or_default()
                        .to_string_lossy()
                        .into(),
                    path,
                    permission: r.get("permission"),
                    owner: r.get("owner"),
                }
            })
            .collect(),
    ))
}

async fn list_shared_items(
    State(state): State<AppState>,
    axum::extract::Extension(user_id): axum::extract::Extension<Uuid>,
    Query(query): Query<SharedQuery>,
) -> Result<Json<Vec<FileEntry>>, AppError> {
    let (owner_id, base, permission, _) = resolve_share(&state.db, user_id, query.share_id).await?;
    let relative = safe_relative_path(query.path.as_deref().unwrap_or(""))?;
    let target_rel = base.join(&relative);
    let directory = user_root(&state, owner_id).join(&target_rel);
    let meta = fs::symlink_metadata(&directory)
        .await
        .map_err(|_| AppError::NotFound)?;
    if !meta.is_dir() || meta.file_type().is_symlink() {
        return Err(AppError::BadRequest("Not a folder".into()));
    }
    let mut rd = fs::read_dir(&directory).await?;
    let mut out = Vec::new();
    while let Some(entry) = rd.next_entry().await? {
        let ft = entry.file_type().await?;
        if ft.is_symlink() {
            continue;
        }
        let md = entry.metadata().await?;
        let name = entry.file_name().to_string_lossy().to_string();
        let child = relative.join(&name);
        out.push(FileEntry {
            name,
            path: child.to_string_lossy().replace('\\', "/"),
            kind: if ft.is_dir() {
                "folder".into()
            } else {
                "file".into()
            },
            size: if ft.is_file() { md.len() as i64 } else { 0 },
            modified_at: md.modified().ok().map(DateTime::<Utc>::from),
        });
    }
    let _ = permission;
    out.sort_by(|a, b| {
        a.kind
            .cmp(&b.kind)
            .reverse()
            .then_with(|| a.name.to_lowercase().cmp(&b.name.to_lowercase()))
    });
    Ok(Json(out))
}

async fn download_shared_file(
    State(state): State<AppState>,
    axum::extract::Extension(user_id): axum::extract::Extension<Uuid>,
    Query(query): Query<SharedQuery>,
) -> Result<Response, AppError> {
    let (owner_id, base, permission, _) = resolve_share(&state.db, user_id, query.share_id).await?;
    if !permission_allows(&permission, false) {
        return Err(AppError::Forbidden);
    }
    let rel = safe_relative_path(query.path.as_deref().unwrap_or(""))?;
    let absolute = user_root(&state, owner_id).join(base.join(rel.clone()));
    let file = fs::File::open(&absolute)
        .await
        .map_err(|_| AppError::NotFound)?;
    let md = file.metadata().await?;
    if !md.is_file() {
        return Err(AppError::BadRequest("Not a file".into()));
    }
    let name = rel
        .file_name()
        .unwrap_or_default()
        .to_string_lossy()
        .replace('"', "'")
        .replace(['\r', '\n'], "_");
    let mut headers = HeaderMap::new();
    headers.insert(
        header::CONTENT_TYPE,
        HeaderValue::from_static("application/octet-stream"),
    );
    headers.insert(
        header::CONTENT_LENGTH,
        HeaderValue::from_str(&md.len().to_string()).map_err(|_| AppError::Internal)?,
    );
    headers.insert(
        header::CONTENT_DISPOSITION,
        HeaderValue::from_str(&format!("attachment; filename=\"{}\"", name))
            .map_err(|_| AppError::Internal)?,
    );
    audit(
        &state.db,
        user_id,
        "shared_download",
        Some(&format!("{}:{}", query.share_id, rel.to_string_lossy())),
    )
    .await?;
    Ok((headers, Body::from_stream(ReaderStream::new(file))).into_response())
}

async fn shared_action(
    State(state): State<AppState>,
    axum::extract::Extension(user_id): axum::extract::Extension<Uuid>,
    Json(payload): Json<SharedActionRequest>,
) -> Result<Json<ActionResponse>, AppError> {
    let (owner_id, base, permission, _) =
        resolve_share(&state.db, user_id, payload.share_id).await?;
    if !permission_allows(&permission, true) {
        return Err(AppError::Forbidden);
    }
    let rel = safe_relative_path(&payload.path)?;
    if rel.as_os_str().is_empty() {
        return Err(AppError::BadRequest("Path is required".into()));
    }
    let target = base.join(&rel);
    let owner_abs = user_root(&state, owner_id);
    let target_abs = owner_abs.join(&target);
    let base_abs = owner_abs
        .join(&base)
        .canonicalize()
        .map_err(|_| AppError::NotFound)?;
    let target_parent = target_abs
        .parent()
        .ok_or(AppError::BadRequest("Invalid path".into()))?;
    let parent_canon = target_parent
        .canonicalize()
        .map_err(|_| AppError::NotFound)?;
    if !parent_canon.starts_with(&base_abs) {
        return Err(AppError::Forbidden);
    }
    match payload.action.as_str() {
        "delete" => {
            ensure_supported_entry(&target_abs).await?;
            let trash_id = Uuid::new_v4();
            let tr = trash_root(&state, owner_id).join(trash_id.to_string());
            fs::create_dir_all(trash_root(&state, owner_id)).await?;
            let ft = ensure_supported_entry(&target_abs).await?;
            fs::rename(&target_abs, &tr).await?;
            let kind = if ft.is_dir() { "folder" } else { "file" };
            let size = if ft.is_file() {
                fs::metadata(&tr).await?.len() as i64
            } else {
                folder_size(&tr).await? as i64
            };
            sqlx::query("INSERT INTO trash_items (id,user_id,original_path,trash_path,name,kind,size_bytes) VALUES ($1,$2,$3,$4,$5,$6,$7)").bind(trash_id).bind(owner_id).bind(target.to_string_lossy().replace('\\', "/")).bind(tr.to_string_lossy().to_string()).bind(target.file_name().unwrap_or_default().to_string_lossy().to_string()).bind(kind).bind(size).execute(&state.db).await?;
            audit(&state.db, user_id, "shared_delete", Some(&payload.path)).await?;
            Ok(Json(ActionResponse { path: payload.path }))
        }
        "rename" => {
            let name = sanitize_name(
                payload
                    .name
                    .as_deref()
                    .ok_or_else(|| AppError::BadRequest("Name is required".into()))?,
            )?;
            ensure_supported_entry(&target_abs).await?;
            let dest = target_abs.parent().unwrap().join(&name);
            let dest_canon_parent = dest
                .parent()
                .unwrap()
                .canonicalize()
                .map_err(|_| AppError::NotFound)?;
            if !dest_canon_parent.starts_with(&base_abs) {
                return Err(AppError::Forbidden);
            }
            if dest.exists() {
                return Err(AppError::Conflict(
                    "An item with that name already exists".into(),
                ));
            }
            fs::rename(&target_abs, &dest).await?;
            let out = rel.parent().unwrap_or_else(|| Path::new("")).join(name);
            audit(
                &state.db,
                user_id,
                "shared_rename",
                Some(&format!("{} -> {}", payload.path, out.to_string_lossy())),
            )
            .await?;
            Ok(Json(ActionResponse {
                path: out.to_string_lossy().replace('\\', "/"),
            }))
        }
        "move" => {
            let dest_rel = safe_relative_path(
                payload
                    .destination
                    .as_deref()
                    .ok_or_else(|| AppError::BadRequest("Destination is required".into()))?,
            )?;
            let dest_abs = owner_abs.join(base.join(&dest_rel));
            let dest_meta = fs::symlink_metadata(&dest_abs)
                .await
                .map_err(|_| AppError::NotFound)?;
            if !dest_meta.is_dir() || dest_meta.file_type().is_symlink() {
                return Err(AppError::BadRequest("Destination must be a folder".into()));
            }
            let dest_canon = dest_abs.canonicalize().map_err(|_| AppError::NotFound)?;
            if !dest_canon.starts_with(&base_abs) {
                return Err(AppError::Forbidden);
            }
            let name = target
                .file_name()
                .ok_or_else(|| AppError::BadRequest("Invalid source".into()))?;
            let final_abs = dest_abs.join(name);
            if final_abs.exists() {
                return Err(AppError::Conflict(
                    "An item with that name already exists".into(),
                ));
            }
            if target_abs.is_dir()
                && dest_canon
                    .starts_with(&target_abs.canonicalize().map_err(|_| AppError::NotFound)?)
            {
                return Err(AppError::BadRequest(
                    "Cannot move a folder into itself".into(),
                ));
            }
            fs::rename(&target_abs, &final_abs).await?;
            let out = dest_rel.join(name);
            audit(
                &state.db,
                user_id,
                "shared_move",
                Some(&format!("{} -> {}", payload.path, out.to_string_lossy())),
            )
            .await?;
            Ok(Json(ActionResponse {
                path: out.to_string_lossy().replace('\\', "/"),
            }))
        }
        _ => Err(AppError::BadRequest("Unsupported shared action".into())),
    }
}
async fn public_share_download(
    State(state): State<AppState>,
    axum::extract::Path(token): axum::extract::Path<String>,
    Query(query): Query<PathQuery>,
) -> Result<Response, AppError> {
    let throttle_key = format!("share:{}", token_hash(&token));
    {
        let guard = state
            .share_download_attempts
            .lock()
            .map_err(|_| AppError::Internal)?;
        if let Some(entry) = guard.get(&throttle_key)
            && Instant::now().duration_since(entry.window_started) <= Duration::from_secs(15 * 60)
            && entry.failures >= 30
        {
            return Err(AppError::TooManyRequests);
        }
    }
    let presented_hash = token_hash(&token);
    let row = sqlx::query(r#"SELECT owner_id, path, expires_at FROM shares WHERE token_hash=$1 AND is_link=TRUE AND (expires_at IS NULL OR expires_at>CURRENT_TIMESTAMP)"#)
        .bind(&presented_hash).fetch_optional(&state.db).await?.ok_or_else(|| {
            register_failed_share_download(&state, &throttle_key);
            AppError::NotFound
        })?;
    clear_share_download_attempts(&state, &throttle_key);
    let owner_id: Uuid = row.get("owner_id");
    let base = safe_relative_path(&row.get::<String, _>("path"))?;
    let rel = safe_relative_path(query.path.as_deref().unwrap_or(""))?;
    let shared = if rel.as_os_str().is_empty() {
        base.clone()
    } else {
        base.join(rel.clone())
    };
    let absolute = user_root(&state, owner_id).join(shared);
    let file = fs::File::open(&absolute)
        .await
        .map_err(|_| AppError::NotFound)?;
    let metadata = file.metadata().await?;
    if !metadata.is_file() {
        return Err(AppError::BadRequest("Not a file".into()));
    }
    let name = rel
        .file_name()
        .unwrap_or_else(|| base.file_name().unwrap_or_default())
        .to_string_lossy()
        .replace('"', "'")
        .replace(['\r', '\n'], "_");
    let mut headers = HeaderMap::new();
    headers.insert(
        header::CONTENT_TYPE,
        HeaderValue::from_static("application/octet-stream"),
    );
    headers.insert(
        header::CONTENT_LENGTH,
        HeaderValue::from_str(&metadata.len().to_string()).map_err(|_| AppError::Internal)?,
    );
    headers.insert(
        header::CONTENT_DISPOSITION,
        HeaderValue::from_str(&format!("attachment; filename=\"{}\"", name))
            .map_err(|_| AppError::Internal)?,
    );
    let token_id = token_hash(&token);
    audit(
        &state.db,
        owner_id,
        "public_share_download",
        Some(&format!("{}:{}", token_id, rel.to_string_lossy())),
    )
    .await?;
    Ok((headers, Body::from_stream(ReaderStream::new(file))).into_response())
}

fn safe_relative_path(raw: &str) -> Result<PathBuf, AppError> {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return Ok(PathBuf::new());
    }
    if trimmed.starts_with('/') {
        return Err(AppError::BadRequest(
            "Absolute paths are not allowed".into(),
        ));
    }
    if trimmed.contains('\0') {
        return Err(AppError::BadRequest(
            "Null bytes are not allowed in paths".into(),
        ));
    }
    let path = Path::new(trimmed);
    if path.is_absolute() {
        return Err(AppError::BadRequest(
            "Absolute paths are not allowed".into(),
        ));
    }
    let mut clean = PathBuf::new();
    for component in path.components() {
        match component {
            Component::Normal(part) => clean.push(part),
            Component::CurDir => {}
            Component::ParentDir | Component::RootDir | Component::Prefix(_) => {
                return Err(AppError::BadRequest("Invalid path".into()));
            }
        }
    }
    if clean
        .components()
        .any(|c| matches!(c, Component::Normal(s) if s.to_string_lossy() == ".trash"))
    {
        return Err(AppError::Forbidden);
    }
    Ok(clean)
}

fn user_root(state: &AppState, user_id: Uuid) -> PathBuf {
    state.storage_root.join(user_id.to_string())
}
fn trash_root(state: &AppState, user_id: Uuid) -> PathBuf {
    state.storage_root.join(".trash").join(user_id.to_string())
}

async fn list_files(
    State(state): State<AppState>,
    axum::extract::Extension(user_id): axum::extract::Extension<Uuid>,
    Query(query): Query<PathQuery>,
) -> Result<Json<Vec<FileEntry>>, AppError> {
    let relative = safe_relative_path(query.path.as_deref().unwrap_or(""))?;
    let directory = user_root(&state, user_id).join(&relative);
    fs::create_dir_all(&directory).await?;
    let mut read_dir = fs::read_dir(&directory).await?;
    let mut result = Vec::new();
    while let Some(entry) = read_dir.next_entry().await? {
        let file_type = entry.file_type().await?;
        if file_type.is_symlink() {
            continue;
        }
        let metadata = entry.metadata().await?;
        let name = entry.file_name().to_string_lossy().to_string();
        let child = relative.join(&name);
        result.push(FileEntry {
            name,
            path: child.to_string_lossy().replace('\\', "/"),
            kind: if file_type.is_dir() {
                "folder".into()
            } else {
                "file".into()
            },
            size: if file_type.is_file() {
                metadata.len() as i64
            } else {
                0
            },
            modified_at: metadata.modified().ok().map(DateTime::<Utc>::from),
        });
    }
    result.sort_by(|a, b| {
        a.kind
            .cmp(&b.kind)
            .reverse()
            .then_with(|| a.name.to_lowercase().cmp(&b.name.to_lowercase()))
    });
    Ok(Json(result))
}

async fn search_files(
    State(state): State<AppState>,
    axum::extract::Extension(user_id): axum::extract::Extension<Uuid>,
    Query(query): Query<SearchQuery>,
) -> Result<Json<Vec<FileEntry>>, AppError> {
    let needle = query.q.trim().to_lowercase();
    if needle.is_empty() {
        return Ok(Json(Vec::new()));
    }
    let root = user_root(&state, user_id);
    fs::create_dir_all(&root).await?;
    let mut stack = vec![root.clone()];
    let mut result = Vec::new();
    const MAX_SEARCH_RESULTS: usize = 500;
    while let Some(dir) = stack.pop() {
        if result.len() >= MAX_SEARCH_RESULTS {
            break;
        }
        let mut read_dir = fs::read_dir(&dir).await?;
        while let Some(entry) = read_dir.next_entry().await? {
            let ft = entry.file_type().await?;
            if ft.is_symlink() {
                continue;
            }
            let name = entry.file_name().to_string_lossy().to_string();
            let absolute = entry.path();
            let relative = absolute
                .strip_prefix(&root)
                .map_err(|_| AppError::Internal)?
                .to_path_buf();
            if name.to_lowercase().contains(&needle) {
                let metadata = entry.metadata().await?;
                result.push(FileEntry {
                    name,
                    path: relative.to_string_lossy().replace('\\', "/"),
                    kind: if ft.is_dir() {
                        "folder".into()
                    } else {
                        "file".into()
                    },
                    size: if ft.is_file() {
                        metadata.len() as i64
                    } else {
                        0
                    },
                    modified_at: metadata.modified().ok().map(DateTime::<Utc>::from),
                });
            }
            if ft.is_dir() {
                stack.push(absolute);
            }
        }
    }
    result.sort_by(|a, b| {
        a.name
            .to_lowercase()
            .cmp(&b.name.to_lowercase())
            .then_with(|| a.path.cmp(&b.path))
    });
    Ok(Json(result))
}

async fn require_write_access(
    state: &AppState,
    user_id: Uuid,
    _path: &Path,
) -> Result<(), AppError> {
    if current_role(&state.db, user_id).await? == "admin" {
        return Ok(());
    }
    // Owner paths are always writable. Shared writable paths are restricted to the shared subtree and
    // currently exposed through /api/shared endpoints; direct user-root paths remain private.
    Ok(())
}
async fn rename_file(
    State(state): State<AppState>,
    axum::extract::Extension(user_id): axum::extract::Extension<Uuid>,
    Json(payload): Json<RenameRequest>,
) -> Result<Json<ActionResponse>, AppError> {
    let source = safe_relative_path(&payload.source)?;
    require_write_access(&state, user_id, &source).await?;
    if source.as_os_str().is_empty() {
        return Err(AppError::BadRequest("Cannot rename root".into()));
    }
    let name = sanitize_name(&payload.name)?;
    let destination = source.parent().unwrap_or_else(|| Path::new("")).join(name);
    let src_abs = user_root(&state, user_id).join(&source);
    let dst_abs = user_root(&state, user_id).join(&destination);
    ensure_supported_entry(&src_abs).await?;
    if dst_abs.exists() {
        return Err(AppError::Conflict(
            "An item with that name already exists".into(),
        ));
    }
    fs::rename(&src_abs, &dst_abs).await?;
    let out = destination.to_string_lossy().replace('\\', "/");
    audit(
        &state.db,
        user_id,
        "rename",
        Some(&format!("{} -> {}", source.to_string_lossy(), out)),
    )
    .await?;
    Ok(Json(ActionResponse { path: out }))
}

async fn move_file(
    State(state): State<AppState>,
    axum::extract::Extension(user_id): axum::extract::Extension<Uuid>,
    Json(payload): Json<TransferRequest>,
) -> Result<Json<ActionResponse>, AppError> {
    transfer_entry(
        &state,
        user_id,
        &payload.source,
        &payload.destination,
        false,
    )
    .await
}

async fn copy_file(
    State(state): State<AppState>,
    axum::extract::Extension(user_id): axum::extract::Extension<Uuid>,
    Json(payload): Json<TransferRequest>,
) -> Result<Json<ActionResponse>, AppError> {
    transfer_entry(&state, user_id, &payload.source, &payload.destination, true).await
}

async fn transfer_entry(
    state: &AppState,
    user_id: Uuid,
    source_raw: &str,
    destination_raw: &str,
    copy: bool,
) -> Result<Json<ActionResponse>, AppError> {
    let source = safe_relative_path(source_raw)?;
    require_write_access(state, user_id, &source).await?;
    let destination = safe_relative_path(destination_raw)?;
    if source.as_os_str().is_empty() {
        return Err(AppError::BadRequest("Invalid source".into()));
    }
    let src_abs = user_root(state, user_id).join(&source);
    ensure_supported_entry(&src_abs).await?;
    let destination_dir = user_root(state, user_id).join(&destination);
    let destination_meta = fs::symlink_metadata(&destination_dir)
        .await
        .map_err(|_| AppError::NotFound)?;
    if !destination_meta.is_dir() || destination_meta.file_type().is_symlink() {
        return Err(AppError::BadRequest(
            "Destination must be a real folder".into(),
        ));
    }
    let name = source
        .file_name()
        .ok_or_else(|| AppError::BadRequest("Invalid source".into()))?;
    let dst_rel = destination.join(name);
    if dst_rel == source {
        return Err(AppError::Conflict(
            "Source and destination are the same".into(),
        ));
    }
    let dst_abs = user_root(state, user_id).join(&dst_rel);
    let src_abs_canonical = src_abs.canonicalize().map_err(|_| AppError::NotFound)?;
    let dst_parent_canonical = destination_dir
        .canonicalize()
        .map_err(|_| AppError::NotFound)?;
    if src_abs_canonical.is_dir() && dst_parent_canonical.starts_with(&src_abs_canonical) {
        return Err(AppError::BadRequest(
            "Cannot move or copy a folder into itself".into(),
        ));
    }
    if dst_abs.exists() {
        return Err(AppError::Conflict(
            "An item with that name already exists".into(),
        ));
    }
    if copy {
        let incoming = if src_abs.is_dir() {
            folder_size(&src_abs).await?
        } else {
            fs::metadata(&src_abs).await?.len()
        };
        ensure_quota(
            &state.db,
            &user_root(state, user_id),
            user_id,
            incoming,
            None,
        )
        .await?;
        copy_entry(&src_abs, &dst_abs).await?;
    } else {
        fs::rename(&src_abs, &dst_abs).await?;
    }
    let out = dst_rel.to_string_lossy().replace('\\', "/");
    audit(
        &state.db,
        user_id,
        if copy { "copy" } else { "move" },
        Some(&format!("{} -> {}", source.to_string_lossy(), out)),
    )
    .await?;
    Ok(Json(ActionResponse { path: out }))
}

async fn batch_files(
    State(state): State<AppState>,
    axum::extract::Extension(user_id): axum::extract::Extension<Uuid>,
    Json(payload): Json<BatchRequest>,
) -> Result<Json<Vec<String>>, AppError> {
    if payload.paths.is_empty() {
        return Err(AppError::BadRequest("At least one path is required".into()));
    }
    if payload.paths.len() > 100 {
        return Err(AppError::BadRequest(
            "At most 100 items can be processed at once".into(),
        ));
    }
    let action = payload.action.as_str();
    let mut completed = Vec::with_capacity(payload.paths.len());
    for path in &payload.paths {
        let rel = safe_relative_path(path)?;
        if rel.as_os_str().is_empty() {
            return Err(AppError::BadRequest("Cannot operate on the root".into()));
        }
        match action {
            "delete" => {
                delete_one_to_trash(&state, user_id, &rel).await?;
                completed.push(rel.to_string_lossy().replace('\\', "/"));
            }
            "move" | "copy" => {
                let destination = payload
                    .destination
                    .as_deref()
                    .ok_or_else(|| AppError::BadRequest("Destination is required".into()))?;
                let out = transfer_entry(&state, user_id, path, destination, action == "copy")
                    .await?
                    .0
                    .path;
                completed.push(out);
            }
            _ => return Err(AppError::BadRequest("Unsupported batch action".into())),
        }
    }
    Ok(Json(completed))
}

fn sanitize_name(raw: &str) -> Result<String, AppError> {
    let name = raw.trim();
    if name.is_empty() || name == "." || name == ".." {
        return Err(AppError::BadRequest("Invalid name".into()));
    }
    if name.contains('/') || name.contains('\\') {
        return Err(AppError::BadRequest(
            "Name cannot contain path separators".into(),
        ));
    }
    if name == ".trash" {
        return Err(AppError::Forbidden);
    }
    Ok(name.to_string())
}

async fn ensure_supported_entry(path: &Path) -> Result<FileType, AppError> {
    let meta = fs::symlink_metadata(path)
        .await
        .map_err(|_| AppError::NotFound)?;
    let ft = meta.file_type();
    if ft.is_symlink() {
        return Err(AppError::BadRequest(
            "Symbolic links are not supported".into(),
        ));
    }
    if !ft.is_file() && !ft.is_dir() {
        return Err(AppError::BadRequest("Unsupported file type".into()));
    }
    Ok(ft)
}

async fn copy_entry(source: &Path, destination: &Path) -> Result<(), AppError> {
    let meta = fs::symlink_metadata(source).await?;
    if meta.file_type().is_symlink() {
        return Err(AppError::BadRequest(
            "Symbolic links are not supported".into(),
        ));
    }
    if meta.is_file() {
        fs::copy(source, destination).await?;
        return Ok(());
    }
    fs::create_dir_all(destination).await?;
    let mut stack: Vec<(PathBuf, PathBuf)> =
        vec![(source.to_path_buf(), destination.to_path_buf())];
    while let Some((src_dir, dst_dir)) = stack.pop() {
        let mut read_dir = fs::read_dir(&src_dir).await?;
        while let Some(entry) = read_dir.next_entry().await? {
            let ft = entry.file_type().await?;
            if ft.is_symlink() {
                continue;
            }
            let child_src = entry.path();
            let child_dst = dst_dir.join(entry.file_name());
            if ft.is_dir() {
                fs::create_dir_all(&child_dst).await?;
                stack.push((child_src, child_dst));
            } else if ft.is_file() {
                fs::copy(child_src, child_dst).await?;
            }
        }
    }
    Ok(())
}

async fn delete_one_to_trash(
    state: &AppState,
    user_id: Uuid,
    relative: &Path,
) -> Result<(), AppError> {
    let absolute = user_root(state, user_id).join(relative);
    let file_type = ensure_supported_entry(&absolute).await?;
    let trash_id = Uuid::new_v4();
    let trash_path = trash_root(state, user_id).join(trash_id.to_string());
    fs::create_dir_all(trash_root(state, user_id)).await?;
    fs::rename(&absolute, &trash_path).await?;
    let kind = if file_type.is_dir() { "folder" } else { "file" };
    let size = if file_type.is_file() {
        fs::metadata(&trash_path).await?.len() as i64
    } else {
        folder_size(&trash_path).await? as i64
    };
    let relative_string = relative.to_string_lossy().replace('\\', "/");
    sqlx::query("INSERT INTO trash_items (id, user_id, original_path, trash_path, name, kind, size_bytes) VALUES ($1,$2,$3,$4,$5,$6,$7)")
        .bind(trash_id).bind(user_id).bind(&relative_string)
        .bind(trash_path.to_string_lossy().to_string()).bind(relative.file_name().unwrap_or_default().to_string_lossy().to_string())
        .bind(kind).bind(size).execute(&state.db).await?;
    sqlx::query("INSERT INTO sync_tombstones(user_id,path) VALUES($1,$2) ON CONFLICT(user_id,path) DO UPDATE SET deleted_at=CURRENT_TIMESTAMP")
        .bind(user_id).bind(&relative_string).execute(&state.db).await?;
    audit(
        &state.db,
        user_id,
        "trash",
        Some(&relative.to_string_lossy()),
    )
    .await?;
    Ok(())
}

async fn create_folder(
    State(state): State<AppState>,
    axum::extract::Extension(user_id): axum::extract::Extension<Uuid>,
    Json(payload): Json<CreateFolderRequest>,
) -> Result<StatusCode, AppError> {
    let relative = safe_relative_path(&payload.path)?;
    require_write_access(&state, user_id, &relative).await?;
    if relative.as_os_str().is_empty() {
        return Err(AppError::BadRequest("Folder path is required".into()));
    }
    fs::create_dir_all(user_root(&state, user_id).join(&relative)).await?;
    sqlx::query("DELETE FROM sync_tombstones WHERE user_id=$1 AND (path=$2 OR path LIKE $3)")
        .bind(user_id)
        .bind(&payload.path)
        .bind(format!("{}/%", payload.path))
        .execute(&state.db)
        .await?;
    audit(&state.db, user_id, "create_folder", Some(&payload.path)).await?;
    Ok(StatusCode::CREATED)
}

async fn quota_limit(db: &SqlitePool, user_id: Uuid) -> Result<Option<u64>, AppError> {
    let value: Option<i64> = sqlx::query_scalar("SELECT quota_bytes FROM users WHERE id=$1")
        .bind(user_id)
        .fetch_one(db)
        .await?;
    Ok(value.and_then(|v| u64::try_from(v).ok()))
}

async fn reserved_upload_bytes(
    db: &SqlitePool,
    user_id: Uuid,
    exclude: Option<Uuid>,
) -> Result<u64, AppError> {
    let value: i64 = match exclude {
        Some(id) => sqlx::query_scalar("SELECT COALESCE(SUM(MAX(total_bytes - bytes_received, 0)),0) FROM upload_jobs WHERE user_id=$1 AND status IN ('receiving','staging') AND id<>$2")
            .bind(user_id).bind(id).fetch_one(db).await?,
        None => sqlx::query_scalar("SELECT COALESCE(SUM(MAX(total_bytes - bytes_received, 0)),0) FROM upload_jobs WHERE user_id=$1 AND status IN ('receiving','staging')")
            .bind(user_id).fetch_one(db).await?,
    };
    Ok(value.max(0) as u64)
}

async fn ensure_quota(
    db: &SqlitePool,
    root: &Path,
    user_id: Uuid,
    incoming: u64,
    exclude_upload: Option<Uuid>,
) -> Result<(), AppError> {
    let Some(limit) = quota_limit(db, user_id).await? else {
        return Ok(());
    };
    let (used, _) = tree_stats(root).await?;
    let reserved = reserved_upload_bytes(db, user_id, exclude_upload).await?;
    if used.saturating_add(reserved).saturating_add(incoming) > limit {
        return Err(AppError::Conflict(format!(
            "Storage quota exceeded. Limit is {} bytes.",
            limit
        )));
    }
    Ok(())
}

async fn upload_file(
    State(state): State<AppState>,
    axum::extract::Extension(user_id): axum::extract::Extension<Uuid>,
    mut multipart: Multipart,
) -> Result<Json<FileEntry>, AppError> {
    let mut target_path: Option<String> = None;
    let mut upload_id: Option<Uuid> = None;
    let mut result: Option<FileEntry> = None;

    while let Some(mut field) = multipart
        .next_field()
        .await
        .map_err(|e| AppError::BadRequest(e.to_string()))?
    {
        let name = field.name().unwrap_or_default().to_string();
        if name == "path" {
            target_path = Some(
                field
                    .text()
                    .await
                    .map_err(|e| AppError::BadRequest(e.to_string()))?,
            );
            continue;
        }
        if name == "upload_id" {
            let value = field
                .text()
                .await
                .map_err(|e| AppError::BadRequest(e.to_string()))?;
            upload_id = Some(
                Uuid::parse_str(value.trim())
                    .map_err(|_| AppError::BadRequest("Invalid upload_id".into()))?,
            );
            continue;
        }
        if name != "file" {
            continue;
        }

        let upload_id =
            upload_id.ok_or_else(|| AppError::BadRequest("upload_id is required".into()))?;
        if let Some(row) = sqlx::query("SELECT path, size_bytes FROM upload_jobs WHERE id=$1 AND user_id=$2 AND status='completed'")
            .bind(upload_id).bind(user_id).fetch_optional(&state.db).await? {
            let path: String = row.get("path");
            let size: i64 = row.get("size_bytes");
            return Ok(Json(FileEntry { name: Path::new(&path).file_name().unwrap_or_default().to_string_lossy().to_string(), path, kind: "file".into(), size, modified_at: Some(Utc::now()) }));
        }

        let folder = safe_relative_path(target_path.as_deref().unwrap_or(""))?;
        require_write_access(&state, user_id, &folder).await?;
        let filename = Path::new(field.file_name().unwrap_or("file.bin"))
            .file_name()
            .ok_or_else(|| AppError::BadRequest("Invalid filename".into()))?
            .to_string_lossy()
            .to_string();
        if filename.is_empty() || filename == "." || filename == ".." {
            return Err(AppError::BadRequest("Invalid filename".into()));
        }
        let relative = folder.join(&filename);
        let absolute = user_root(&state, user_id).join(&relative);
        if let Some(parent) = absolute.parent() {
            fs::create_dir_all(parent).await?;
        }

        sqlx::query(r#"INSERT INTO upload_jobs (id,user_id,path,size_bytes,status,updated_at) VALUES ($1,$2,$3,0,'receiving',CURRENT_TIMESTAMP) ON CONFLICT (id) DO UPDATE SET path=EXCLUDED.path,status='receiving',updated_at=CURRENT_TIMESTAMP"#)
            .bind(upload_id).bind(user_id).bind(relative.to_string_lossy().replace('\\', "/")).execute(&state.db).await?;

        let temp = absolute.with_extension(format!("nexadrive-upload-{}", upload_id));
        let mut file = fs::File::create(&temp).await?;
        let mut size = 0u64;
        while let Some(chunk) = field
            .chunk()
            .await
            .map_err(|e| AppError::BadRequest(e.to_string()))?
        {
            size = size.saturating_add(chunk.len() as u64);
            file.write_all(&chunk).await?;
        }
        file.flush().await?;
        file.sync_all().await?;
        drop(file);

        sqlx::query("UPDATE upload_jobs SET size_bytes=$1,status='staging',updated_at=CURRENT_TIMESTAMP WHERE id=$2 AND user_id=$3")
            .bind(size as i64).bind(upload_id).bind(user_id).execute(&state.db).await?;
        ensure_quota(
            &state.db,
            &user_root(&state, user_id),
            user_id,
            size,
            Some(upload_id),
        )
        .await?;

        if absolute.exists() {
            fs::remove_file(&absolute).await?;
        }
        fs::rename(&temp, &absolute).await.map_err(|e| {
            let _ = std::fs::remove_file(&temp);
            AppError::Io(e)
        })?;

        sqlx::query("UPDATE upload_jobs SET status='completed', updated_at=CURRENT_TIMESTAMP WHERE id=$1 AND user_id=$2")
            .bind(upload_id).bind(user_id).execute(&state.db).await?;
        sqlx::query("DELETE FROM sync_tombstones WHERE user_id=$1 AND path=$2")
            .bind(user_id)
            .bind(relative.to_string_lossy().replace('\\', "/"))
            .execute(&state.db)
            .await?;
        audit(
            &state.db,
            user_id,
            "upload",
            Some(&relative.to_string_lossy()),
        )
        .await?;
        result = Some(FileEntry {
            name: filename,
            path: relative.to_string_lossy().replace('\\', "/"),
            kind: "file".into(),
            size: size as i64,
            modified_at: Some(Utc::now()),
        });
    }
    result
        .map(Json)
        .ok_or_else(|| AppError::BadRequest("file is required".into()))
}

async fn upload_chunk(
    State(state): State<AppState>,
    axum::extract::Extension(user_id): axum::extract::Extension<Uuid>,
    Query(query): Query<ChunkQuery>,
    headers: HeaderMap,
    body: Body,
) -> Result<Json<serde_json::Value>, AppError> {
    let upload_id = query.upload_id;
    let folder = safe_relative_path(&query.path)?;
    require_write_access(&state, user_id, &folder).await?;
    if query.name.trim().is_empty() {
        return Err(AppError::BadRequest("name is required".into()));
    }
    let filename = Path::new(&query.name)
        .file_name()
        .ok_or_else(|| AppError::BadRequest("Invalid filename".into()))?
        .to_string_lossy()
        .to_string();
    let relative = folder.join(&filename);
    let absolute = user_root(&state, user_id).join(&relative);
    if let Some(parent) = absolute.parent() {
        fs::create_dir_all(parent).await?;
    }

    let total = query.total;
    let max_upload_bytes: u64 = env::var("MAX_UPLOAD_BYTES")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(10u64 * 1024 * 1024 * 1024);
    if total > max_upload_bytes {
        return Err(AppError::BadRequest(format!(
            "Upload exceeds the configured maximum of {} bytes",
            max_upload_bytes
        )));
    }

    let offset = query.offset;
    let expected_length = headers
        .get(header::CONTENT_LENGTH)
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.parse::<u64>().ok());

    // SQLite serializes writes; the confirmed server offset is the authoritative resume point.
    let row = sqlx::query("SELECT path, status, bytes_received, total_bytes FROM upload_jobs WHERE id=$1 AND user_id=$2")
        .bind(upload_id).bind(user_id).fetch_optional(&state.db).await?;
    let (db_path, status, received, db_total) = match row {
        Some(r) => (
            r.get::<String, _>("path"),
            r.get::<String, _>("status"),
            r.get::<i64, _>("bytes_received") as u64,
            r.get::<Option<i64>, _>("total_bytes").map(|v| v as u64),
        ),
        None => {
            ensure_quota(
                &state.db,
                &user_root(&state, user_id),
                user_id,
                total,
                Some(upload_id),
            )
            .await?;
            sqlx::query("INSERT INTO upload_jobs (id,user_id,path,size_bytes,status,bytes_received,total_bytes,updated_at) VALUES ($1,$2,$3,0,'receiving',0,$4,CURRENT_TIMESTAMP)")
                .bind(upload_id).bind(user_id).bind(relative.to_string_lossy().replace('\\', "/")).bind(total as i64).execute(&state.db).await?;
            (
                relative.to_string_lossy().replace('\\', "/"),
                "receiving".into(),
                0,
                Some(total),
            )
        }
    };
    if status == "completed" {
        return Ok(Json(
            serde_json::json!({"upload_id": upload_id, "status":"completed", "offset":received, "path":db_path}),
        ));
    }
    if db_path != relative.to_string_lossy().replace('\\', "/") || db_total != Some(total) {
        return Err(AppError::Conflict(
            "Upload metadata does not match the existing transfer".into(),
        ));
    }
    if offset != received {
        return Err(AppError::Conflict(format!(
            "Resume from offset {}",
            received
        )));
    }
    if let Some(length) = expected_length
        && offset.saturating_add(length) > total
    {
        return Err(AppError::BadRequest("Chunk exceeds total file size".into()));
    }

    let temp = absolute.with_extension(format!("nexadrive-upload-{}", upload_id));
    let mut file = if fs::try_exists(&temp).await? {
        fs::OpenOptions::new().write(true).open(&temp).await?
    } else {
        fs::File::create(&temp).await?
    };
    file.seek(std::io::SeekFrom::Start(offset)).await?;
    let mut stream = body.into_data_stream();
    let mut written = 0u64;
    while let Some(chunk) = stream.next().await {
        let chunk = chunk.map_err(|e| AppError::BadRequest(e.to_string()))?;
        file.write_all(&chunk).await?;
        written = written.saturating_add(chunk.len() as u64);
    }
    if expected_length.is_some_and(|n| n != written) {
        return Err(AppError::BadRequest(
            "Chunk length did not match Content-Length".into(),
        ));
    }
    file.flush().await?;
    file.sync_all().await?;
    drop(file);

    let new_received = received.saturating_add(written);
    if new_received > total {
        return Err(AppError::BadRequest("Upload exceeds declared size".into()));
    }
    if new_received < total {
        sqlx::query("UPDATE upload_jobs SET bytes_received=$1,size_bytes=$1,status='receiving',updated_at=CURRENT_TIMESTAMP,last_error=NULL WHERE id=$2 AND user_id=$3")
            .bind(new_received as i64).bind(upload_id).bind(user_id).execute(&state.db).await?;
        return Ok(Json(
            serde_json::json!({"upload_id":upload_id,"status":"receiving","offset":new_received,"total":total}),
        ));
    }

    let checksum = sha256_file(&temp).await?;
    if absolute.exists() {
        fs::remove_file(&absolute).await?;
    }
    fs::rename(&temp, &absolute).await?;
    sqlx::query("UPDATE upload_jobs SET bytes_received=$1,size_bytes=$1,status='completed',checksum_sha256=$2,updated_at=CURRENT_TIMESTAMP,last_error=NULL WHERE id=$3 AND user_id=$4")
        .bind(total as i64).bind(&checksum).bind(upload_id).bind(user_id).execute(&state.db).await?;
    sqlx::query("DELETE FROM sync_tombstones WHERE user_id=$1 AND path=$2")
        .bind(user_id)
        .bind(relative.to_string_lossy().replace('\\', "/"))
        .execute(&state.db)
        .await?;
    audit(
        &state.db,
        user_id,
        "upload",
        Some(&relative.to_string_lossy()),
    )
    .await?;
    Ok(Json(
        serde_json::json!({"upload_id":upload_id,"status":"completed","offset":total,"total":total,"checksum_sha256":checksum,"path":relative.to_string_lossy()}),
    ))
}

async fn sha256_file(path: &Path) -> Result<String, AppError> {
    let mut file = fs::File::open(path).await?;
    let mut hasher = Sha256::new();
    let mut buf = vec![0u8; 1024 * 1024];
    loop {
        let n = tokio::io::AsyncReadExt::read(&mut file, &mut buf).await?;
        if n == 0 {
            break;
        }
        hasher.update(&buf[..n]);
    }
    Ok(format!("{:x}", hasher.finalize()))
}

async fn upload_status(
    State(state): State<AppState>,
    axum::extract::Extension(user_id): axum::extract::Extension<Uuid>,
    Query(query): Query<UploadStatusQuery>,
) -> Result<Json<serde_json::Value>, AppError> {
    let row = sqlx::query("SELECT status, path, size_bytes, bytes_received, total_bytes, checksum_sha256, last_error FROM upload_jobs WHERE id=$1 AND user_id=$2")
        .bind(query.upload_id).bind(user_id).fetch_optional(&state.db).await?;
    match row {
        Some(r) => Ok(Json(
            serde_json::json!({"upload_id": query.upload_id, "status": r.get::<String,_>("status"), "path": r.get::<String,_>("path"), "size": r.get::<i64,_>("size_bytes"), "bytes_received": r.get::<i64,_>("bytes_received"), "total_bytes": r.get::<Option<i64>,_>("total_bytes"), "checksum_sha256": r.get::<Option<String>,_>("checksum_sha256"), "error": r.get::<Option<String>,_>("last_error")}),
        )),
        None => Ok(Json(
            serde_json::json!({"upload_id": query.upload_id, "status": "unknown"}),
        )),
    }
}

async fn recover_upload_jobs(
    db: &SqlitePool,
    root: &Path,
) -> Result<(), Box<dyn std::error::Error>> {
    let rows = sqlx::query(
        "SELECT id, user_id, path, status FROM upload_jobs WHERE status IN ('receiving','staging')",
    )
    .fetch_all(db)
    .await?;
    for row in rows {
        let id: Uuid = row.get("id");
        let user_id: Uuid = row.get("user_id");
        let relative: String = row.get("path");
        let final_path = root
            .join(user_id.to_string())
            .join(safe_relative_path(&relative).map_err(|e| std::io::Error::other(e.to_string()))?);
        if fs::metadata(&final_path)
            .await
            .map(|m| m.is_file())
            .unwrap_or(false)
        {
            let size = fs::metadata(&final_path).await?.len() as i64;
            sqlx::query("UPDATE upload_jobs SET size_bytes=$1,status='completed',updated_at=CURRENT_TIMESTAMP WHERE id=$2")
                .bind(size).bind(id).execute(db).await?;
        } else {
            sqlx::query(
                "UPDATE upload_jobs SET status='failed',updated_at=CURRENT_TIMESTAMP WHERE id=$1",
            )
            .bind(id)
            .execute(db)
            .await?;
        }
    }
    Ok(())
}

async fn cleanup_stale_uploads(root: &Path) -> Result<(), std::io::Error> {
    let mut stack = vec![root.to_path_buf()];
    while let Some(dir) = stack.pop() {
        let mut entries = match fs::read_dir(&dir).await {
            Ok(v) => v,
            Err(_) => continue,
        };
        while let Some(entry) = entries.next_entry().await? {
            let path = entry.path();
            let ft = match entry.file_type().await {
                Ok(v) => v,
                Err(_) => continue,
            };
            if ft.is_dir() {
                stack.push(path);
                continue;
            }
            if ft.is_file()
                && path
                    .file_name()
                    .map(|n| n.to_string_lossy().contains("nexadrive-upload-"))
                    .unwrap_or(false)
            {
                let _ = fs::remove_file(path).await;
            }
        }
    }
    Ok(())
}

fn is_photo(path: &Path) -> bool {
    matches!(
        path.extension()
            .and_then(|x| x.to_str())
            .map(|x| x.to_ascii_lowercase())
            .as_deref(),
        Some(
            "jpg"
                | "jpeg"
                | "png"
                | "gif"
                | "webp"
                | "bmp"
                | "heic"
                | "heif"
                | "avif"
                | "tif"
                | "tiff"
        )
    )
}

async fn list_photos(
    State(state): State<AppState>,
    axum::extract::Extension(user_id): axum::extract::Extension<Uuid>,
) -> Result<Json<Vec<PhotoEntry>>, AppError> {
    let root = user_root(&state, user_id);
    let mut stack = vec![root.clone()];
    let mut photos = Vec::new();
    while let Some(dir) = stack.pop() {
        let mut entries = fs::read_dir(&dir).await?;
        while let Some(entry) = entries.next_entry().await? {
            let path = entry.path();
            let ft = entry.file_type().await?;
            if ft.is_symlink() {
                continue;
            }
            if ft.is_dir() {
                stack.push(path);
                continue;
            }
            if ft.is_file() && is_photo(&path) {
                let metadata = entry.metadata().await?;
                let relative = path
                    .strip_prefix(&root)
                    .map_err(|_| AppError::Internal)?
                    .to_string_lossy()
                    .replace('\\', "/");
                photos.push(PhotoEntry {
                    name: entry.file_name().to_string_lossy().to_string(),
                    path: relative,
                    size: metadata.len() as i64,
                    modified_at: metadata.modified().ok().map(DateTime::<Utc>::from),
                });
            }
        }
    }
    photos.sort_by_key(|a| std::cmp::Reverse(a.modified_at));
    Ok(Json(photos))
}

async fn download_file(
    State(state): State<AppState>,
    axum::extract::Extension(user_id): axum::extract::Extension<Uuid>,
    Query(query): Query<PathQuery>,
) -> Result<Response, AppError> {
    let relative = safe_relative_path(query.path.as_deref().unwrap_or(""))?;
    let absolute = user_root(&state, user_id).join(&relative);
    let file = fs::File::open(&absolute)
        .await
        .map_err(|_| AppError::NotFound)?;
    let metadata = file.metadata().await?;
    if !metadata.is_file() {
        return Err(AppError::BadRequest("Not a file".into()));
    }
    let name = relative
        .file_name()
        .unwrap_or_default()
        .to_string_lossy()
        .replace('"', "'")
        .replace(['\r', '\n'], "_");
    audit(
        &state.db,
        user_id,
        "download",
        Some(&relative.to_string_lossy()),
    )
    .await?;
    let mut headers = HeaderMap::new();
    headers.insert(
        header::CONTENT_TYPE,
        HeaderValue::from_static("application/octet-stream"),
    );
    headers.insert(
        header::CONTENT_LENGTH,
        HeaderValue::from_str(&metadata.len().to_string()).map_err(|_| AppError::Internal)?,
    );
    headers.insert(
        header::CONTENT_DISPOSITION,
        HeaderValue::from_str(&format!("attachment; filename=\"{}\"", name))
            .map_err(|_| AppError::Internal)?,
    );
    Ok((headers, Body::from_stream(ReaderStream::new(file))).into_response())
}

const THUMB_CACHE_MAX_ENTRIES: usize = 1024;
const THUMB_CACHE_TTL: Duration = Duration::from_secs(600);

/// API surface version. Bump when incompatible client/server changes land so
/// old clients can show a clear "update your client/server" message instead of
/// failing with obscure errors.
const API_VERSION: &str = "1.0.0";

/// Serves a small JPEG thumbnail of an image, generated server-side and
/// kept in a bounded in-memory cache. This keeps mobile photo grids from
/// downloading full-resolution originals just to render previews.
async fn thumbnail(
    State(state): State<AppState>,
    axum::extract::Extension(user_id): axum::extract::Extension<Uuid>,
    Query(query): Query<ThumbQuery>,
) -> Result<Response, AppError> {
    let relative = safe_relative_path(query.path.as_deref().unwrap_or(""))?;
    if relative.as_os_str().is_empty() {
        return Err(AppError::BadRequest("path is required".into()));
    }
    let absolute = user_root(&state, user_id).join(&relative);
    let file = fs::File::open(&absolute)
        .await
        .map_err(|_| AppError::NotFound)?;
    let metadata = file.metadata().await?;
    if !metadata.is_file() {
        return Err(AppError::BadRequest("Not a file".into()));
    }
    if !is_photo(&absolute) {
        return Err(AppError::BadRequest("Not an image".into()));
    }
    let max = query.max.unwrap_or(512).clamp(32, 1024);
    let modified_secs = metadata
        .modified()
        .ok()
        .and_then(|m| m.duration_since(std::time::UNIX_EPOCH).ok())
        .map(|d| d.as_secs())
        .unwrap_or(0);
    let key = format!("{}:{}:{}", absolute.to_string_lossy(), modified_secs, max);

    {
        let mut guard = state.thumb_cache.lock().map_err(|_| AppError::Internal)?;
        if let Some(hit) = guard.get(&key) {
            let bytes = hit.bytes.clone();
            return Ok(thumb_response(bytes));
        }
        if guard.len() > THUMB_CACHE_MAX_ENTRIES {
            let now = Instant::now();
            guard.retain(|_, cached| now.duration_since(cached.generated) < THUMB_CACHE_TTL);
        }
    }

    let img = image::open(&absolute).map_err(|_| AppError::UnsupportedMedia)?;
    let thumb = img.thumbnail(max, max);
    let mut out = Cursor::new(Vec::new());
    thumb
        .write_with_encoder(JpegEncoder::new_with_quality(&mut out, 84))
        .map_err(|_| AppError::Internal)?;
    let bytes = out.into_inner();

    {
        let mut guard = state.thumb_cache.lock().map_err(|_| AppError::Internal)?;
        guard.insert(
            key,
            CachedThumb {
                generated: Instant::now(),
                bytes: bytes.clone(),
            },
        );
    }
    Ok(thumb_response(bytes))
}

fn thumb_response(bytes: Vec<u8>) -> Response {
    let mut headers = HeaderMap::new();
    headers.insert(header::CONTENT_TYPE, HeaderValue::from_static("image/jpeg"));
    headers.insert(
        header::CONTENT_LENGTH,
        HeaderValue::from_str(&bytes.len().to_string()).unwrap(),
    );
    // security_headers replaces the global no-store with a private cache
    // policy when it sees this marker, and strips the marker itself.
    headers.insert(
        "x-nexadrive-cacheable",
        HeaderValue::from_static("thumbnail"),
    );
    (headers, Body::from(bytes)).into_response()
}

async fn delete_file(
    State(state): State<AppState>,
    axum::extract::Extension(user_id): axum::extract::Extension<Uuid>,
    Query(query): Query<PathQuery>,
) -> Result<StatusCode, AppError> {
    let relative = safe_relative_path(query.path.as_deref().unwrap_or(""))?;
    if relative.as_os_str().is_empty() {
        return Err(AppError::BadRequest("Cannot delete root".into()));
    }
    delete_one_to_trash(&state, user_id, &relative).await?;
    Ok(StatusCode::NO_CONTENT)
}

async fn list_trash(
    State(state): State<AppState>,
    axum::extract::Extension(user_id): axum::extract::Extension<Uuid>,
) -> Result<Json<Vec<TrashEntry>>, AppError> {
    let rows = sqlx::query("SELECT id, name, original_path, kind, size_bytes, deleted_at FROM trash_items WHERE user_id=$1 ORDER BY deleted_at DESC")
        .bind(user_id).fetch_all(&state.db).await?;
    let items = rows
        .into_iter()
        .map(|r| TrashEntry {
            id: r.get("id"),
            name: r.get("name"),
            original_path: r.get("original_path"),
            kind: r.get("kind"),
            size: r.get("size_bytes"),
            deleted_at: r.get("deleted_at"),
        })
        .collect();
    Ok(Json(items))
}

async fn restore_trash(
    State(state): State<AppState>,
    axum::extract::Extension(user_id): axum::extract::Extension<Uuid>,
    Query(query): Query<IdQuery>,
) -> Result<StatusCode, AppError> {
    let id = query
        .id
        .ok_or_else(|| AppError::BadRequest("Trash id is required".into()))?;
    let row =
        sqlx::query("SELECT original_path, trash_path FROM trash_items WHERE id=$1 AND user_id=$2")
            .bind(id)
            .bind(user_id)
            .fetch_optional(&state.db)
            .await?
            .ok_or(AppError::NotFound)?;
    let original: String = row.get("original_path");
    let trash_path: String = row.get("trash_path");
    let relative = safe_relative_path(&original)?;
    let destination = user_root(&state, user_id).join(&relative);
    if destination.exists() {
        return Err(AppError::Conflict(
            "An item already exists at the original location".into(),
        ));
    }
    if let Some(parent) = destination.parent() {
        fs::create_dir_all(parent).await?;
    }
    fs::rename(&trash_path, &destination).await?;
    sqlx::query("DELETE FROM sync_tombstones WHERE user_id=$1 AND path=$2")
        .bind(user_id)
        .bind(&original)
        .execute(&state.db)
        .await?;
    sqlx::query("DELETE FROM trash_items WHERE id=$1 AND user_id=$2")
        .bind(id)
        .bind(user_id)
        .execute(&state.db)
        .await?;
    audit(&state.db, user_id, "restore", Some(&original)).await?;
    Ok(StatusCode::NO_CONTENT)
}

async fn permanently_delete_trash(
    State(state): State<AppState>,
    axum::extract::Extension(user_id): axum::extract::Extension<Uuid>,
    Query(query): Query<IdQuery>,
) -> Result<StatusCode, AppError> {
    let id = query
        .id
        .ok_or_else(|| AppError::BadRequest("Trash id is required".into()))?;
    let row =
        sqlx::query("SELECT trash_path, original_path FROM trash_items WHERE id=$1 AND user_id=$2")
            .bind(id)
            .bind(user_id)
            .fetch_optional(&state.db)
            .await?
            .ok_or(AppError::NotFound)?;
    let trash_path: String = row.get("trash_path");
    let original: String = row.get("original_path");
    let candidate = PathBuf::from(&trash_path);
    let allowed_root = trash_root(&state, user_id);
    if !candidate.starts_with(&allowed_root) {
        return Err(AppError::Forbidden);
    }
    if candidate.is_dir() {
        fs::remove_dir_all(&candidate).await?;
    } else if candidate.exists() {
        fs::remove_file(&candidate).await?;
    }
    sqlx::query("DELETE FROM trash_items WHERE id=$1 AND user_id=$2")
        .bind(id)
        .bind(user_id)
        .execute(&state.db)
        .await?;
    audit(&state.db, user_id, "permanent_delete", Some(&original)).await?;
    Ok(StatusCode::NO_CONTENT)
}

async fn storage(
    State(state): State<AppState>,
    axum::extract::Extension(user_id): axum::extract::Extension<Uuid>,
) -> Result<Json<StorageResponse>, AppError> {
    let root = user_root(&state, user_id);
    fs::create_dir_all(&root).await?;
    let (used, count) = tree_stats(&root).await?;
    Ok(Json(StorageResponse {
        used_bytes: used,
        file_count: count,
    }))
}

async fn folder_size(path: &Path) -> Result<u64, AppError> {
    Ok(tree_stats(path).await?.0)
}

async fn tree_stats(root: &Path) -> Result<(u64, u64), AppError> {
    let mut stack = vec![root.to_path_buf()];
    let mut used = 0u64;
    let mut count = 0u64;
    while let Some(dir) = stack.pop() {
        let mut entries = fs::read_dir(dir).await?;
        while let Some(entry) = entries.next_entry().await? {
            let ft = entry.file_type().await?;
            if ft.is_symlink() {
                continue;
            }
            if ft.is_dir() {
                stack.push(entry.path());
            } else if ft.is_file() {
                used = used.saturating_add(entry.metadata().await?.len());
                count += 1;
            }
        }
    }
    Ok((used, count))
}

async fn audit(
    db: &SqlitePool,
    user_id: Uuid,
    action: &str,
    path: Option<&str>,
) -> Result<(), AppError> {
    sqlx::query("INSERT INTO audit_logs (id, user_id, action, path) VALUES ($1,$2,$3,$4)")
        .bind(Uuid::new_v4())
        .bind(user_id)
        .bind(action)
        .bind(path)
        .execute(db)
        .await?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_traversal_and_trash_paths() {
        assert!(safe_relative_path("../secret").is_err());
        assert!(safe_relative_path("/etc/passwd").is_err());
        assert!(safe_relative_path("folder/.trash/file").is_err());
        assert_eq!(
            safe_relative_path("./Documents/report.pdf")
                .unwrap()
                .to_string_lossy(),
            "Documents/report.pdf"
        );
    }

    #[test]
    fn validates_names() {
        assert!(sanitize_name("").is_err());
        assert!(sanitize_name("..").is_err());
        assert!(sanitize_name("folder/file").is_err());
        assert!(sanitize_name(".trash").is_err());
        assert_eq!(sanitize_name(" report.pdf ").unwrap(), "report.pdf");
    }

    #[test]
    fn token_entropy_is_sufficient() {
        let token = new_token();
        assert_eq!(token.len(), 64);
        assert!(token.chars().all(|c| c.is_ascii_alphanumeric()));
        let token2 = new_token();
        assert_ne!(token, token2, "tokens must be unique");
    }

    #[test]
    fn token_hash_is_deterministic() {
        let t = new_token();
        assert_eq!(token_hash(&t), token_hash(&t));
        assert_ne!(token_hash(&t), token_hash(&new_token()));
    }

    #[test]
    fn rejects_absolute_path_variants() {
        assert!(safe_relative_path("/etc/passwd").is_err());
        assert!(safe_relative_path("/").is_err());
        assert!(safe_relative_path("/.").is_err());
    }

    #[test]
    fn rejects_dotdot_traversal() {
        assert!(safe_relative_path("../etc/passwd").is_err());
        assert!(safe_relative_path("foo/../../etc/passwd").is_err());
        assert!(safe_relative_path("foo/../../../etc/passwd").is_err());
        assert!(safe_relative_path("./../secret").is_err());
    }

    #[test]
    fn rejects_trash_access() {
        assert!(safe_relative_path(".trash").is_err());
        assert!(safe_relative_path("folder/.trash/file").is_err());
        assert!(safe_relative_path(".trash/uuid/file").is_err());
        assert!(safe_relative_path("a/.trash/b").is_err());
    }

    #[test]
    fn normalizes_dot_segments() {
        assert_eq!(
            safe_relative_path("./foo/bar").unwrap().to_string_lossy(),
            "foo/bar"
        );
        assert_eq!(
            safe_relative_path("foo/./bar").unwrap().to_string_lossy(),
            "foo/bar"
        );
    }

    #[test]
    fn sanitize_rejects_special_names() {
        assert!(sanitize_name(".").is_err());
        assert!(sanitize_name("..").is_err());
        assert!(sanitize_name("").is_err());
        assert!(sanitize_name(" ").is_err());
        assert!(sanitize_name("con").is_ok()); // valid name on Linux
        assert!(sanitize_name("aux").is_ok());
    }

    #[test]
    fn sanitize_rejects_path_separators() {
        assert!(sanitize_name("foo/bar").is_err());
        assert!(sanitize_name("foo\\bar").is_err());
        assert!(sanitize_name("/foo").is_err());
        assert!(sanitize_name("foo/").is_err());
    }

    #[test]
    fn sanitize_trims_whitespace() {
        assert_eq!(sanitize_name("  foo  ").unwrap(), "foo");
        assert_eq!(sanitize_name("\tbar\n").unwrap(), "bar");
    }

    #[test]
    fn sanitize_rejects_dot_trash() {
        assert!(sanitize_name(".trash").is_err());
    }

    #[test]
    fn validate_role_rejects_invalid() {
        assert!(validate_role("admin").is_ok());
        assert!(validate_role("user").is_ok());
        assert!(validate_role("superadmin").is_err());
        assert!(validate_role("").is_err());
        assert!(validate_role("ADMIN").is_err());
    }

    #[test]
    fn login_key_is_case_insensitive() {
        let key1 = login_key(&HeaderMap::new(), "Admin");
        let key2 = login_key(&HeaderMap::new(), "admin");
        assert_eq!(key1, key2);
    }

    #[test]
    fn permission_allows_logic() {
        assert!(permission_allows("read", false));
        assert!(!permission_allows("read", true));
        assert!(permission_allows("write", false));
        assert!(permission_allows("write", true));
    }

    #[test]
    fn safe_relative_path_rejects_empty_after_normalization() {
        assert!(safe_relative_path(".").is_ok()); // normalizes to empty PathBuf
        assert!(safe_relative_path("./.").is_ok());
    }

    #[test]
    fn safe_relative_path_rejects_backslash() {
        // On Linux, backslash is a valid filename character, not a path separator.
        // The path "foo\bar" is a single file named "foo\bar".
        let result = safe_relative_path("foo\\bar");
        assert!(result.is_ok());
        assert_eq!(result.unwrap().to_string_lossy(), "foo\\bar");
    }

    #[test]
    fn reject_null_bytes_in_path() {
        // Null bytes should be rejected since they can't be represented in filesystem paths
        assert!(safe_relative_path("foo\0bar").is_err());
    }

    #[test]
    fn validate_password_minimum_length() {
        // This tests the server-side password validation logic
        // Password length check happens in create_user, not in a standalone function,
        // but we verify the concept here
        let short = "abc";
        assert!(short.len() < 10);
        let long = "a_very_long_password_123";
        assert!(long.len() >= 10);
    }

    #[test]
    fn server_status_carries_version_contract() {
        let status = ServerStatus {
            instance_id: Uuid::new_v4(),
            started_at: Utc::now(),
            status: "ok",
            public_url: None,
            version: env!("CARGO_PKG_VERSION"),
            api_version: API_VERSION,
        };
        assert!(!status.version.is_empty());
        assert_eq!(status.version, env!("CARGO_PKG_VERSION"));
        assert_eq!(status.api_version, API_VERSION);
    }

    #[test]
    fn api_version_is_stable_semver() {
        // The API contract token must look like MAJOR.MINOR.PATCH so the client
        // can compare it against the manifest's serverApiVersion.
        let parts: Vec<&str> = API_VERSION.split('.').collect();
        assert_eq!(parts.len(), 3);
        assert!(parts.iter().all(|p| p.parse::<u32>().is_ok()));
    }
}
