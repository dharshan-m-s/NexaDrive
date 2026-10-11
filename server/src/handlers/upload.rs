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
use std::path::Path;
use tokio::{
    fs,
    io::{AsyncSeekExt, AsyncWriteExt},
};
use uuid::Uuid;

use crate::{
    auth::require_write_access,
    error::AppError,
    handlers::{admin::audit, storage::tree_stats},
    models::{ChunkQuery, FileEntry, UploadStatusQuery},
    paths::{safe_relative_path, user_root},
    state::AppState,
};

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

pub(crate) async fn ensure_quota(
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

pub(crate) async fn upload_chunk(
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

pub(crate) async fn recover_upload_jobs(
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

pub(crate) async fn cleanup_stale_uploads(root: &Path) -> Result<(), std::io::Error> {
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
