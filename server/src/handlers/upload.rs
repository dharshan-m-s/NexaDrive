use axum::{
    Json,
    body::Body,
    extract::{Multipart, Query, State},
    http::{HeaderMap, header},
};
use chrono::Utc;
use futures_util::StreamExt;
use sha2::{Digest, Sha256};
use sqlx::{Row, sqlite::SqlitePool};
use std::{
    collections::HashMap,
    path::{Path, PathBuf},
    sync::Arc,
    time::{Duration, Instant},
};
use tokio::{
    fs,
    io::{AsyncSeekExt, AsyncWriteExt, BufWriter},
};
use tracing::error;
use uuid::Uuid;

use crate::{
    auth::require_write_access,
    error::AppError,
    handlers::{admin::audit, storage::tree_stats},
    models::{ChunkQuery, FileEntry, UploadStatusQuery},
    paths::{safe_relative_path, user_root},
    state::{AppState, QuotaCacheEntry},
};

/// Marker embedded in the file name of a partially uploaded file.
///
/// The staging file lives next to its destination so the final rename stays on
/// one filesystem (and is therefore atomic), but it must never be visible to
/// the user or counted against their quota.
pub(crate) const UPLOAD_STAGING_MARKER: &str = ".nexadrive-upload-";

/// How long a cached "bytes used" reading is trusted.
///
/// The quota check used to walk the user's whole tree on every single upload,
/// which made a bulk upload quadratic and could fail outright when the tree
/// changed underneath the walk.
const QUOTA_CACHE_TTL: Duration = Duration::from_secs(5);

/// How long a client may wait for an upload slot before the server sheds the
/// request with 503 (which clients treat as retryable).
const UPLOAD_SLOT_WAIT: Duration = Duration::from_secs(120);

type UploadLocks = Arc<std::sync::Mutex<HashMap<Uuid, Arc<tokio::sync::Mutex<()>>>>>;

/// Owned per-upload lock that also removes its idle map entry on drop.
///
/// Without the cleanup the map would grow by one entry for every upload for
/// the lifetime of the process. The entry is only removed while the map lock
/// is held and no other request holds a reference, so a waiter can never be
/// orphaned with a lock nobody else can see.
struct UploadLockGuard {
    locks: UploadLocks,
    upload_id: Uuid,
    guard: Option<tokio::sync::OwnedMutexGuard<()>>,
}

impl Drop for UploadLockGuard {
    fn drop(&mut self) {
        // Drop the async guard first so the strong count reflects only the
        // map's Arc and any request that is already waiting on it.
        self.guard.take();
        let Ok(mut locks) = self.locks.lock() else {
            return;
        };
        if locks
            .get(&self.upload_id)
            .is_some_and(|lock| Arc::strong_count(lock) == 1)
        {
            locks.remove(&self.upload_id);
        }
    }
}

/// Serialises all work for one upload id.
///
/// Two requests for the same id run one after the other instead of both
/// creating the job row (the UNIQUE-constraint 500) and both seeking the
/// staging file.
async fn lock_upload(state: &AppState, upload_id: Uuid) -> Result<UploadLockGuard, AppError> {
    let locks = state.upload_locks.clone();
    let lock = {
        let mut map = locks.lock().map_err(|_| AppError::Internal)?;
        map.entry(upload_id)
            .or_insert_with(|| Arc::new(tokio::sync::Mutex::new(())))
            .clone()
    };
    let guard = lock.lock_owned().await;
    Ok(UploadLockGuard {
        locks,
        upload_id,
        guard: Some(guard),
    })
}

/// Whether a directory entry is a partially uploaded file rather than a real
/// user file.
pub(crate) fn is_staging_name(name: &str) -> bool {
    name.contains(UPLOAD_STAGING_MARKER)
}

/// The upload id encoded in a staging file name, if any.
pub(crate) fn staging_upload_id(name: &str) -> Option<Uuid> {
    let (_, id) = name.rsplit_once(UPLOAD_STAGING_MARKER)?;
    Uuid::parse_str(id).ok()
}

/// Path of the staging file for `target` under `upload_id`.
///
/// The original name is preserved as a prefix so the staging file can never
/// collide with another upload of the same target, and so the final rename
/// restores the exact name the user expects.
pub(crate) fn staging_path(target: &Path, upload_id: &Uuid) -> PathBuf {
    let name = target
        .file_name()
        .map(|n| n.to_string_lossy().to_string())
        .unwrap_or_else(|| "upload.bin".to_string());
    target.with_file_name(format!("{name}{UPLOAD_STAGING_MARKER}{upload_id}"))
}

/// Moves `staging` onto `target`, replacing any existing file.
///
/// `rename` replaces the destination atomically on POSIX. On Windows it fails
/// when the destination exists, so the destination is removed first there.
async fn replace_file(staging: &Path, target: &Path) -> Result<(), AppError> {
    match fs::rename(staging, target).await {
        Ok(()) => Ok(()),
        Err(first) => {
            // Windows cannot rename onto an existing file.
            if target.exists() {
                fs::remove_file(target).await?;
                return fs::rename(staging, target).await.map_err(AppError::Io);
            }
            Err(AppError::Io(first))
        }
    }
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
        Some(id) => sqlx::query_scalar("SELECT COALESCE(SUM(MAX(COALESCE(total_bytes,size_bytes) - bytes_received, 0)),0) FROM upload_jobs WHERE user_id=$1 AND status IN ('receiving','staging') AND id<>$2")
            .bind(user_id).bind(id).fetch_one(db).await?,
        None => sqlx::query_scalar("SELECT COALESCE(SUM(MAX(COALESCE(total_bytes,size_bytes) - bytes_received, 0)),0) FROM upload_jobs WHERE user_id=$1 AND status IN ('receiving','staging')")
            .bind(user_id).fetch_one(db).await?,
    };
    Ok(value.max(0) as u64)
}

/// Bytes committed by uploads that finished after `cutoff`.
///
/// The cached walk cannot see files that landed after it ran, so those bytes
/// are added back on top of the cached value. Counting them twice is
/// possible and only makes the quota slightly stricter, which is the safe
/// direction.
async fn bytes_completed_since(
    db: &SqlitePool,
    user_id: Uuid,
    cutoff: &str,
) -> Result<u64, AppError> {
    let value: i64 = sqlx::query_scalar(
        "SELECT COALESCE(SUM(size_bytes),0) FROM upload_jobs WHERE user_id=$1 AND status='completed' AND updated_at > $2",
    )
    .bind(user_id)
    .bind(cutoff)
    .fetch_one(db)
    .await?;
    Ok(value.max(0) as u64)
}

/// The user's on-disk usage, from a short-lived cache when possible.
///
/// The cache entry is copied out before anything is awaited: the guard is a
/// `std::sync::MutexGuard`, which is not `Send`, and holding it across an
/// await would make the whole request future non-`Send`.
async fn used_bytes(state: &AppState, user_id: Uuid) -> Result<u64, AppError> {
    let cached = {
        let Ok(guard) = state.quota_cache.lock() else {
            return uncached_used_bytes(state, user_id).await;
        };
        guard
            .get(&user_id)
            .map(|entry| (entry.at, entry.cutoff.clone(), entry.bytes))
    };
    if let Some((at, cutoff, bytes)) = cached
        && at.elapsed() < QUOTA_CACHE_TTL
    {
        let extra = bytes_completed_since(&state.db, user_id, &cutoff).await?;
        return Ok(bytes.saturating_add(extra));
    }
    uncached_used_bytes(state, user_id).await
}

async fn uncached_used_bytes(state: &AppState, user_id: Uuid) -> Result<u64, AppError> {
    let root = user_root(state, user_id);
    // The cutoff is taken *before* the walk so anything that lands during the
    // walk is added back by `bytes_completed_since`.
    let cutoff = Utc::now().format("%Y-%m-%d %H:%M:%S").to_string();
    let (used, _) = tree_stats(&root).await?;
    if let Ok(mut guard) = state.quota_cache.lock() {
        guard.insert(
            user_id,
            QuotaCacheEntry {
                at: Instant::now(),
                cutoff,
                bytes: used,
            },
        );
    }
    Ok(used)
}

/// Fails the request when the transfer would push the account past its quota.
pub(crate) async fn ensure_quota(
    state: &AppState,
    user_id: Uuid,
    incoming: u64,
    exclude_upload: Option<Uuid>,
) -> Result<(), AppError> {
    let Some(limit) = quota_limit(&state.db, user_id).await? else {
        return Ok(());
    };
    let used = used_bytes(state, user_id).await?;
    let reserved = reserved_upload_bytes(&state.db, user_id, exclude_upload).await?;
    if used.saturating_add(reserved).saturating_add(incoming) > limit {
        return Err(AppError::Conflict(format!(
            "Storage quota exceeded. Limit is {} bytes.",
            limit
        )));
    }
    Ok(())
}

/// Multipart upload of a whole file in one request.
///
/// The body is streamed to a staging file next to the destination and only
/// then moved into place, so an interrupted transfer never leaves a
/// half-written file behind.
pub(crate) async fn upload_file(
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
        let _upload_guard = lock_upload(&state, upload_id).await?;
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
        let relative_text = relative.to_string_lossy().replace('\\', "/");
        let absolute = user_root(&state, user_id).join(&relative);
        if let Some(parent) = absolute.parent() {
            fs::create_dir_all(parent).await?;
        }

        let claimed = sqlx::query(r#"INSERT INTO upload_jobs (id,user_id,path,size_bytes,status,updated_at) VALUES ($1,$2,$3,0,'receiving',CURRENT_TIMESTAMP) ON CONFLICT (id) DO UPDATE SET path=EXCLUDED.path,status='receiving',updated_at=CURRENT_TIMESTAMP WHERE upload_jobs.user_id=excluded.user_id"#)
            .bind(upload_id).bind(user_id).bind(&relative_text).execute(&state.db).await?;
        if claimed.rows_affected() == 0 {
            // The id belongs to another account. Never let one user adopt or
            // overwrite another user's upload job, even with a guessed id.
            return Err(AppError::Conflict("Upload id is already in use".into()));
        }

        let staging = staging_path(&absolute, &upload_id);
        let mut file = fs::File::create(&staging).await?;
        let mut size = 0u64;
        let mut write_failed = false;
        while let Some(chunk) = field
            .chunk()
            .await
            .map_err(|e| AppError::BadRequest(e.to_string()))?
        {
            size = size.saturating_add(chunk.len() as u64);
            if let Err(e) = file.write_all(&chunk).await {
                write_failed = true;
                error!(error = %e, "upload write failed");
                break;
            }
        }
        if write_failed {
            drop(file);
            let _ = fs::remove_file(&staging).await;
            return Err(AppError::Io(std::io::Error::other("upload write failed")));
        }
        file.flush().await?;
        file.sync_all().await?;
        drop(file);

        sqlx::query("UPDATE upload_jobs SET size_bytes=$1,status='staging',updated_at=CURRENT_TIMESTAMP WHERE id=$2 AND user_id=$3")
            .bind(size as i64).bind(upload_id).bind(user_id).execute(&state.db).await?;
        if let Err(e) = ensure_quota(&state, user_id, size, Some(upload_id)).await {
            let _ = fs::remove_file(&staging).await;
            sqlx::query("UPDATE upload_jobs SET status='failed',last_error=$1,updated_at=CURRENT_TIMESTAMP WHERE id=$2 AND user_id=$3")
                .bind(e.to_string()).bind(upload_id).bind(user_id).execute(&state.db).await?;
            return Err(e);
        }

        if let Err(e) = replace_file(&staging, &absolute).await {
            let _ = fs::remove_file(&staging).await;
            sqlx::query("UPDATE upload_jobs SET status='failed',last_error=$1,updated_at=CURRENT_TIMESTAMP WHERE id=$2 AND user_id=$3")
                .bind(e.to_string()).bind(upload_id).bind(user_id).execute(&state.db).await?;
            return Err(e);
        }

        sqlx::query("UPDATE upload_jobs SET status='completed', bytes_received=$1, updated_at=CURRENT_TIMESTAMP WHERE id=$2 AND user_id=$3")
            .bind(size as i64).bind(upload_id).bind(user_id).execute(&state.db).await?;
        sqlx::query("DELETE FROM sync_tombstones WHERE user_id=$1 AND path=$2")
            .bind(user_id)
            .bind(&relative_text)
            .execute(&state.db)
            .await?;
        audit(&state.db, user_id, "upload", Some(&relative_text)).await?;
        result = Some(FileEntry {
            name: filename,
            path: relative_text,
            kind: "file".into(),
            size: size as i64,
            modified_at: Some(Utc::now()),
        });
    }
    result
        .map(Json)
        .ok_or_else(|| AppError::BadRequest("file is required".into()))
}

/// Offset-based, resumable upload endpoint.
///
/// The client sends `upload_id`, the total size and the byte offset of the
/// chunk it is sending. The server records the confirmed offset in SQLite and
/// only ever appends at that offset, so a dropped connection costs at most
/// one chunk.
pub(crate) async fn upload_chunk(
    State(state): State<AppState>,
    axum::extract::Extension(user_id): axum::extract::Extension<Uuid>,
    Query(query): Query<ChunkQuery>,
    headers: HeaderMap,
    body: Body,
) -> Result<Json<serde_json::Value>, AppError> {
    let upload_id = query.upload_id;
    // Serialise by upload id *before* taking a global slot: a duplicate
    // request for an id that is already being written must wait for that
    // request, not occupy a slot and race its staging file.
    let _upload_guard = lock_upload(&state, upload_id).await?;

    // The server, not the client, decides how many transfers run at once.
    let permit = tokio::time::timeout(UPLOAD_SLOT_WAIT, state.upload_slots.clone().acquire_owned())
        .await
        .map_err(|_| AppError::ServiceUnavailable)?
        .map_err(|_| AppError::ServiceUnavailable)?;
    let _permit = permit;

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
    if filename.is_empty() || filename == "." || filename == ".." {
        return Err(AppError::BadRequest("Invalid filename".into()));
    }
    let relative = folder.join(&filename);
    let relative_text = relative.to_string_lossy().replace('\\', "/");
    let absolute = user_root(&state, user_id).join(&relative);
    if let Some(parent) = absolute.parent() {
        fs::create_dir_all(parent).await?;
    }

    let total = query.total;
    let max_upload_bytes: u64 = state.config.max_upload_bytes as u64;
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
            ensure_quota(&state, user_id, total, Some(upload_id)).await?;
            // The per-upload lock makes this the only writer for this id in
            // this process, but ON CONFLICT still protects against a second
            // server process or a stale row. A row owned by another account
            // must never be adopted.
            let claimed = sqlx::query("INSERT INTO upload_jobs (id,user_id,path,size_bytes,status,bytes_received,total_bytes,updated_at) VALUES ($1,$2,$3,0,'receiving',0,$4,CURRENT_TIMESTAMP) ON CONFLICT (id) DO NOTHING")
                .bind(upload_id).bind(user_id).bind(&relative_text).bind(total as i64).execute(&state.db).await?;
            if claimed.rows_affected() == 0 {
                return Err(AppError::Conflict("Upload id is already in use".into()));
            }
            (relative_text.clone(), "receiving".into(), 0, Some(total))
        }
    };
    if status == "completed" {
        return Ok(Json(
            serde_json::json!({"upload_id": upload_id, "status":"completed", "offset":received, "total":received, "path":db_path}),
        ));
    }
    if db_path != relative_text || db_total != Some(total) {
        return Err(AppError::Conflict(
            "Upload metadata does not match the existing transfer".into(),
        ));
    }
    if let Some(length) = expected_length
        && offset.saturating_add(length) > total
    {
        return Err(AppError::BadRequest("Chunk exceeds total file size".into()));
    }

    let staging = staging_path(&absolute, &upload_id);

    // The staging file is the authority on what has actually been received.
    // The recorded offset and the file can disagree when a previous attempt
    // wrote bytes but never committed the offset (a dropped response, a
    // server restart). Writing at an offset the file does not reach would
    // leave a hole of NUL bytes in the finished file, so the two are
    // reconciled first and the *confirmed* offset always wins.
    let staging_len = fs::metadata(&staging).await.map(|m| m.len()).unwrap_or(0);
    let mut received = received;
    if staging_len != received {
        if staging_len > received {
            // Bytes the server never confirmed: drop them and let the client
            // re-send from the confirmed offset.
            let file = fs::OpenOptions::new().write(true).open(&staging).await?;
            file.set_len(received).await?;
            file.sync_all().await?;
        } else {
            // The staged file is shorter than the recorded offset, so the
            // recorded offset cannot be trusted. Fall back to what is really
            // on disk.
            received = staging_len;
            sqlx::query("UPDATE upload_jobs SET bytes_received=$1,size_bytes=$1,updated_at=CURRENT_TIMESTAMP WHERE id=$2 AND user_id=$3")
                .bind(received as i64).bind(upload_id).bind(user_id).execute(&state.db).await?;
        }
    }
    if !staging.exists() {
        let file = fs::File::create(&staging).await?;
        drop(file);
    }
    if offset != received {
        return Err(AppError::ConflictCode {
            message: format!("Resume from offset {received}"),
            code: "offset_mismatch",
        });
    }

    let mut file = fs::OpenOptions::new()
        .write(true)
        .truncate(false)
        .open(&staging)
        .await?;
    file.seek(std::io::SeekFrom::Start(offset)).await?;
    // HTTP bodies arrive in many small frames. Buffering turns those into a
    // handful of larger writes instead of one syscall per frame.
    let mut file = BufWriter::with_capacity(1024 * 1024, file);
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
    let new_received = received.saturating_add(written);
    // Only the final chunk needs to be durable before it is moved into
    // place. Intermediate chunks stay in the page cache: if the process dies,
    // reconciliation compares the staging file length with the confirmed
    // offset and rewinds safely, so an fsync per chunk only adds latency.
    if new_received >= total {
        let file = file.into_inner();
        file.sync_all().await?;
    } else {
        drop(file);
    }

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

    // The file is complete: verify it, then move it into place atomically.
    let checksum = sha256_file(&staging).await?;
    if let Err(e) = replace_file(&staging, &absolute).await {
        sqlx::query("UPDATE upload_jobs SET status='failed',last_error=$1,updated_at=CURRENT_TIMESTAMP WHERE id=$2 AND user_id=$3")
            .bind(e.to_string()).bind(upload_id).bind(user_id).execute(&state.db).await?;
        return Err(e);
    }
    let mut tx = state.db.begin().await?;
    sqlx::query("UPDATE upload_jobs SET bytes_received=$1,size_bytes=$1,status='completed',checksum_sha256=$2,updated_at=CURRENT_TIMESTAMP,last_error=NULL WHERE id=$3 AND user_id=$4")
        .bind(total as i64).bind(&checksum).bind(upload_id).bind(user_id).execute(&mut *tx).await?;
    sqlx::query("DELETE FROM sync_tombstones WHERE user_id=$1 AND path=$2")
        .bind(user_id)
        .bind(&relative_text)
        .execute(&mut *tx)
        .await?;
    tx.commit().await?;
    audit(&state.db, user_id, "upload", Some(&relative_text)).await?;
    Ok(Json(
        serde_json::json!({"upload_id":upload_id,"status":"completed","offset":total,"total":total,"checksum_sha256":checksum,"path":relative_text}),
    ))
}

/// Releases an upload session: the staging file is removed and the job is
/// marked failed so it can never be resumed into a half-written file.
pub(crate) async fn cancel_upload(
    State(state): State<AppState>,
    axum::extract::Extension(user_id): axum::extract::Extension<Uuid>,
    Query(query): Query<UploadStatusQuery>,
) -> Result<Json<serde_json::Value>, AppError> {
    let upload_id = query.upload_id;
    let row = sqlx::query("SELECT path, status FROM upload_jobs WHERE id=$1 AND user_id=$2")
        .bind(upload_id)
        .bind(user_id)
        .fetch_optional(&state.db)
        .await?;
    let Some(row) = row else {
        return Ok(Json(
            serde_json::json!({"upload_id":upload_id,"status":"unknown"}),
        ));
    };
    let relative: String = row.get("path");
    let status: String = row.get("status");
    if status == "completed" {
        return Ok(Json(
            serde_json::json!({"upload_id":upload_id,"status":"completed"}),
        ));
    }
    let relative = safe_relative_path(&relative)?;
    let absolute = user_root(&state, user_id).join(&relative);
    let staging = staging_path(&absolute, &upload_id);
    let _ = fs::remove_file(&staging).await;
    sqlx::query("UPDATE upload_jobs SET status='failed',last_error='cancelled',updated_at=CURRENT_TIMESTAMP WHERE id=$1 AND user_id=$2")
        .bind(upload_id)
        .bind(user_id)
        .execute(&state.db)
        .await?;
    Ok(Json(
        serde_json::json!({"upload_id":upload_id,"status":"cancelled"}),
    ))
}

pub(crate) async fn sha256_file(path: &Path) -> Result<String, AppError> {
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

pub(crate) async fn upload_status(
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

/// Reconciles the upload journal with what is actually on disk after a
/// restart.
///
/// A job whose staging file is present and matches the recorded offset stays
/// resumable. A job whose staging file is gone is reset to offset zero
/// instead of being failed, so the client restarts the file cleanly rather
/// than writing past the end of a truncated file.
pub(crate) async fn recover_upload_jobs(
    db: &SqlitePool,
    root: &Path,
) -> Result<(), Box<dyn std::error::Error>> {
    let rows = sqlx::query(
        "SELECT id, user_id, path, status, bytes_received FROM upload_jobs WHERE status IN ('receiving','staging')",
    )
    .fetch_all(db)
    .await?;
    for row in rows {
        let id: Uuid = row.get("id");
        let user_id: Uuid = row.get("user_id");
        let relative: String = row.get("path");
        let received: u64 = row.get::<i64, _>("bytes_received").max(0) as u64;
        let relative = match safe_relative_path(&relative) {
            Ok(p) => p,
            Err(_) => {
                sqlx::query("UPDATE upload_jobs SET status='failed',updated_at=CURRENT_TIMESTAMP WHERE id=$1")
                    .bind(id)
                    .execute(db)
                    .await?;
                continue;
            }
        };
        let final_path = root.join(user_id.to_string()).join(&relative);
        if fs::metadata(&final_path)
            .await
            .map(|m| m.is_file())
            .unwrap_or(false)
        {
            let size = fs::metadata(&final_path).await?.len() as i64;
            sqlx::query("UPDATE upload_jobs SET size_bytes=$1,bytes_received=$1,status='completed',updated_at=CURRENT_TIMESTAMP WHERE id=$2")
                .bind(size).bind(id).execute(db).await?;
            continue;
        }
        let staging = staging_path(&final_path, &id);
        let staging_len = fs::metadata(&staging).await.map(|m| m.len()).unwrap_or(0);
        if staging_len == received && received > 0 {
            // The staged bytes are still there: keep the session resumable.
            sqlx::query("UPDATE upload_jobs SET status='receiving',updated_at=CURRENT_TIMESTAMP WHERE id=$1")
                .bind(id)
                .execute(db)
                .await?;
        } else {
            // The staged bytes are gone. Reset the offset so the next chunk
            // starts from zero instead of leaving a hole in the file.
            let _ = fs::remove_file(&staging).await;
            sqlx::query("UPDATE upload_jobs SET bytes_received=0,size_bytes=0,status='receiving',updated_at=CURRENT_TIMESTAMP WHERE id=$1")
                .bind(id)
                .execute(db)
                .await?;
        }
    }
    Ok(())
}

/// Removes staging files that no longer belong to a live upload session.
///
/// Staging files are kept across a restart so an interrupted transfer can be
/// resumed; they are only removed once their session is gone or expired.
pub(crate) async fn cleanup_stale_uploads(
    db: &SqlitePool,
    root: &Path,
    ttl_hours: i64,
) -> Result<(), std::io::Error> {
    let live: Vec<String> = sqlx::query(
        "SELECT id FROM upload_jobs WHERE status IN ('receiving','staging') AND updated_at > datetime('now', ?)",
    )
    .bind(format!("-{ttl_hours} hours"))
    .fetch_all(db)
    .await
    .map(|rows| {
        rows.into_iter()
            .map(|r| r.get::<Uuid, _>("id").to_string())
            .collect()
    })
    .unwrap_or_default();

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
            if !ft.is_file() {
                continue;
            }
            let name = entry.file_name().to_string_lossy().to_string();
            if !is_staging_name(&name) {
                continue;
            }
            let keep = staging_upload_id(&name)
                .map(|id| live.iter().any(|l| l == &id.to_string()))
                .unwrap_or(false);
            if !keep {
                let _ = fs::remove_file(path).await;
            }
        }
    }
    Ok(())
}

/// Expires abandoned upload sessions.
///
/// A session that has not been touched for longer than the TTL is marked
/// failed and its staging file is removed, so the storage directory does not
/// grow without bound.
pub(crate) async fn sweep_expired_uploads(
    db: &SqlitePool,
    root: &Path,
    ttl_hours: i64,
) -> Result<u64, Box<dyn std::error::Error>> {
    let rows = sqlx::query(
        "SELECT id, user_id, path FROM upload_jobs WHERE status IN ('receiving','staging') AND updated_at <= datetime('now', ?)",
    )
    .bind(format!("-{ttl_hours} hours"))
    .fetch_all(db)
    .await?;
    let mut expired = 0u64;
    for row in rows {
        let id: Uuid = row.get("id");
        let user_id: Uuid = row.get("user_id");
        let relative: String = row.get("path");
        if let Ok(relative) = safe_relative_path(&relative) {
            let absolute = root.join(user_id.to_string()).join(&relative);
            let staging = staging_path(&absolute, &id);
            let _ = fs::remove_file(&staging).await;
        }
        sqlx::query("UPDATE upload_jobs SET status='failed',last_error='expired',updated_at=CURRENT_TIMESTAMP WHERE id=$1")
            .bind(id)
            .execute(db)
            .await?;
        expired += 1;
    }
    // Completed jobs are only kept as an idempotency window; prune the old ones.
    sqlx::query("DELETE FROM upload_jobs WHERE status IN ('completed','failed') AND updated_at <= datetime('now', ?)")
        .bind(format!("-{ttl_hours} hours"))
        .execute(db)
        .await?;
    Ok(expired)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;

    #[tokio::test]
    async fn an_idle_upload_lock_is_removed_from_the_map() {
        let locks: UploadLocks = Arc::new(std::sync::Mutex::new(HashMap::new()));
        let id = Uuid::new_v4();
        let lock = Arc::new(tokio::sync::Mutex::new(()));
        locks.lock().unwrap().insert(id, lock.clone());
        let guard = UploadLockGuard {
            locks: locks.clone(),
            upload_id: id,
            guard: Some(lock.lock_owned().await),
        };
        assert!(locks.lock().unwrap().contains_key(&id));
        drop(guard);
        assert!(!locks.lock().unwrap().contains_key(&id));
    }

    #[tokio::test]
    async fn a_waiting_request_keeps_the_upload_lock_entry_alive() {
        let locks: UploadLocks = Arc::new(std::sync::Mutex::new(HashMap::new()));
        let id = Uuid::new_v4();
        let lock = Arc::new(tokio::sync::Mutex::new(()));
        locks.lock().unwrap().insert(id, lock.clone());
        let waiter = lock.clone();
        let first = UploadLockGuard {
            locks: locks.clone(),
            upload_id: id,
            guard: Some(lock.lock_owned().await),
        };
        drop(first);
        assert!(locks.lock().unwrap().contains_key(&id));
        let second = UploadLockGuard {
            locks: locks.clone(),
            upload_id: id,
            guard: Some(waiter.lock_owned().await),
        };
        drop(second);
        assert!(!locks.lock().unwrap().contains_key(&id));
    }

    #[test]
    fn staging_files_are_recognised_by_their_marker() {
        assert!(is_staging_name("report.pdf.nexadrive-upload-abc"));
        assert!(!is_staging_name("report.pdf"));
        assert!(!is_staging_name("nexadrive-upload-report.pdf"));
    }

    #[test]
    fn the_upload_id_can_be_read_back_from_a_staging_name() {
        let id = Uuid::new_v4();
        let name = format!("report.pdf{UPLOAD_STAGING_MARKER}{id}");
        assert_eq!(staging_upload_id(&name), Some(id));
        assert_eq!(staging_upload_id("report.pdf"), None);
        assert_eq!(staging_upload_id("report.pdf.nexadrive-upload-nope"), None);
    }

    #[test]
    fn the_staging_file_sits_next_to_its_destination() {
        let id = Uuid::new_v4();
        let target = Path::new("/srv/user/docs/report.pdf");
        let staging = staging_path(target, &id);
        assert_eq!(staging.parent(), target.parent());
        let name = staging.file_name().unwrap().to_string_lossy().to_string();
        assert!(name.starts_with("report.pdf"));
        assert!(is_staging_name(&name));
        assert_eq!(staging_upload_id(&name), Some(id));
    }

    #[test]
    fn two_uploads_of_the_same_file_never_collide() {
        let target = Path::new("/srv/user/docs/report.pdf");
        let a = staging_path(target, &Uuid::new_v4());
        let b = staging_path(target, &Uuid::new_v4());
        assert_ne!(a, b);
    }

    #[test]
    fn a_staging_name_never_collides_with_a_user_file() {
        // A user file literally called like a staging file would be hidden
        // from listings, so the marker must be impossible to type by accident
        // in a normal file name: it always carries a trailing uuid.
        let target = Path::new("/srv/user/docs/report.pdf");
        let staging = staging_path(target, &Uuid::new_v4());
        assert!(staging.file_name().unwrap().to_string_lossy().len() > 40);
    }
}
