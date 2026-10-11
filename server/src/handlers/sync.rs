use axum::{
    Json,
    extract::{Query, State},
    http::StatusCode,
};
use chrono::{DateTime, Utc};
use sqlx::{
    Row,
    sqlite::{SqlitePool, SqliteRow},
};
use std::path::Path;
use tokio::fs;
use uuid::Uuid;

use crate::{
    error::AppError,
    handlers::{admin::audit, files::delete_one_to_trash, upload::sha256_file},
    models::{
        IdQuery, RenameDeviceRequest, SyncDeleteRequest, SyncDeltaQuery, SyncDeviceResponse,
        SyncEntry, SyncManifestQuery, SyncManifestResponse,
    },
    paths::{safe_relative_path, user_root},
    state::AppState,
};

pub(crate) async fn sync_delta(
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
            platform: query.platform,
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

pub(crate) async fn sync_manifest(
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
    let device_name: String = if device_name.is_empty() {
        "NexaDrive desktop".to_string()
    } else {
        // Bounded, multi-byte safe: a device name is user-visible metadata and
        // must never be able to bloat a row or panic on a UTF-8 boundary.
        device_name.chars().take(64).collect()
    };
    // A device re-announcing itself keeps its id (and therefore its identity
    // in the Sync Center list); a revoked or unknown id is re-registered, so a
    // revocation never bricks a machine's sync permanently. The platform is
    // refreshed on every call, including for devices that predate the column.
    let platform = normalize_platform(query.platform.as_deref());
    let device_id = resolve_sync_device(
        &state.db,
        user_id,
        query.device_id,
        &device_name,
        platform.as_deref(),
    )
    .await?;

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

pub(crate) async fn collect_sync_entries(
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

/// How a sync request should be bound to a device row.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum DeviceLink {
    /// A known id owned by this account: refresh name/platform/last-seen.
    Refresh(Uuid),
    /// An id we have never seen but which is free: adopt it verbatim.
    Adopt(Uuid),
    /// No id supplied: reuse the newest row matching this name and platform.
    AdoptExisting(Uuid),
    /// Nothing to reuse: create a fresh row.
    Mint,
}

/// The device-identity decision, as a pure function.
///
/// Extracted so the security-critical branch is unit-testable without a
/// database: an id that belongs to *another account* is never adopted, no
/// matter what the client asks for.
///
/// The motivating bug: `POST /api/sync/manifest` used to mint a brand-new
/// random id whenever the supplied id was unknown. Two syncs starting together
/// on a fresh install — the shell's startup sync and the Sync Center's manual
/// sync — both sent `device_id: null` (neither had persisted the server's reply
/// yet), so one machine registered two devices. The Sync Center then showed
/// repeated, indistinguishable "NexaDrive desktop" rows. Adopting the client's
/// id makes concurrent first syncs converge on one row, and the no-id path now
/// adopts an existing name+platform row instead of appending another.
pub(crate) fn plan_device_link(
    requested: Option<Uuid>,
    requested_owner: Option<Uuid>,
    caller: Uuid,
    same_name_platform: Option<Uuid>,
) -> DeviceLink {
    match requested {
        Some(id) => match requested_owner {
            Some(owner) if owner == caller => DeviceLink::Refresh(id),
            // Registered to somebody else — never hijack it.
            Some(_) => DeviceLink::Mint,
            None => DeviceLink::Adopt(id),
        },
        None => match same_name_platform {
            Some(id) => DeviceLink::AdoptExisting(id),
            None => DeviceLink::Mint,
        },
    }
}

/// Binds a sync request to a device row, creating one only when there is
/// genuinely nothing to reuse.
pub(crate) async fn resolve_sync_device(
    db: &SqlitePool,
    user_id: Uuid,
    requested: Option<Uuid>,
    name: &str,
    platform: Option<&str>,
) -> Result<Uuid, AppError> {
    let requested_owner: Option<Uuid> = match requested {
        Some(id) => {
            sqlx::query_scalar("SELECT user_id FROM sync_devices WHERE id=$1")
                .bind(id)
                .fetch_optional(db)
                .await?
        }
        None => None,
    };
    let same_name_platform: Option<Uuid> = if requested.is_none() {
        sqlx::query_scalar(
            "SELECT id FROM sync_devices WHERE user_id=$1 AND name=$2 AND platform IS $3 \
             ORDER BY last_seen_at DESC LIMIT 1",
        )
        .bind(user_id)
        .bind(name)
        .bind(platform)
        .fetch_optional(db)
        .await?
    } else {
        None
    };

    let link = plan_device_link(requested, requested_owner, user_id, same_name_platform);

    let touch = |id: Uuid| async move {
        sqlx::query("UPDATE sync_devices SET last_seen_at=CURRENT_TIMESTAMP, name=$3, platform=COALESCE($4, platform) WHERE id=$1 AND user_id=$2")
            .bind(id)
            .bind(user_id)
            .bind(name)
            .bind(platform)
            .execute(db)
            .await?;
        Ok::<Uuid, AppError>(id)
    };

    let insert = |id: Uuid| async move {
        sqlx::query("INSERT INTO sync_devices(id,user_id,name,platform) VALUES($1,$2,$3,$4)")
            .bind(id)
            .bind(user_id)
            .bind(name)
            .bind(platform)
            .execute(db)
            .await?;
        Ok::<Uuid, AppError>(id)
    };

    match link {
        DeviceLink::Refresh(id) | DeviceLink::AdoptExisting(id) => touch(id).await,
        DeviceLink::Adopt(id) => match insert(id).await {
            Ok(id) => Ok(id),
            // A concurrent first sync from the same machine inserted this very
            // id a moment ago. Same device, same id — that is success, not a
            // conflict, so refresh it rather than reporting an error.
            Err(AppError::Database(sqlx::Error::Database(e))) if e.is_unique_violation() => {
                touch(id).await
            }
            Err(e) => Err(e),
        },
        DeviceLink::Mint => insert(Uuid::new_v4()).await,
    }
}

pub(crate) async fn list_sync_devices(
    State(state): State<AppState>,
    axum::extract::Extension(user_id): axum::extract::Extension<Uuid>,
) -> Result<Json<Vec<SyncDeviceResponse>>, AppError> {
    let rows = sqlx::query("SELECT id,name,platform,last_seen_at,created_at FROM sync_devices WHERE user_id=$1 ORDER BY last_seen_at DESC").bind(user_id).fetch_all(&state.db).await?;
    Ok(Json(
        rows.into_iter()
            .map(|r| SyncDeviceResponse {
                id: r.get("id"),
                name: r.get("name"),
                platform: r.get("platform"),
                last_seen_at: r.get("last_seen_at"),
                created_at: r.get("created_at"),
            })
            .collect(),
    ))
}

/// Renames a linked device. Only the owner's own devices are reachable, and a
/// rename never resurrects a revoked device (the row must already exist).
pub(crate) async fn rename_sync_device(
    State(state): State<AppState>,
    axum::extract::Extension(user_id): axum::extract::Extension<Uuid>,
    Json(payload): Json<RenameDeviceRequest>,
) -> Result<StatusCode, AppError> {
    let name = payload.name.trim();
    if name.is_empty() || name.chars().count() > 64 {
        return Err(AppError::BadRequest(
            "Device name must be 1-64 characters".into(),
        ));
    }
    let result = sqlx::query("UPDATE sync_devices SET name=$3 WHERE id=$1 AND user_id=$2")
        .bind(payload.id)
        .bind(user_id)
        .bind(name)
        .execute(&state.db)
        .await?;
    if result.rows_affected() == 0 {
        return Err(AppError::NotFound);
    }
    audit(
        &state.db,
        user_id,
        "sync_device_rename",
        Some(&payload.id.to_string()),
    )
    .await?;
    Ok(StatusCode::NO_CONTENT)
}

pub(crate) async fn delete_sync_device(
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

pub(crate) async fn sync_delete(
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

/// Normalises a client-reported platform string to a small known set, so the
/// device list can render a correct icon and an arbitrary client string can
/// never reach the UI.
pub(crate) fn normalize_platform(raw: Option<&str>) -> Option<String> {
    let value = raw?.trim().to_ascii_lowercase();
    let normalized = match value.as_str() {
        "android" => "android",
        "windows" | "win32" => "windows",
        "linux" => "linux",
        "macos" | "mac" | "darwin" => "macos",
        _ => return None,
    };
    Some(normalized.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    // ------------------------------------------------------------ sync devices
    // Duplicate "NexaDrive desktop" rows came from two syncs racing on a fresh
    // install. These pin the identity decision that replaced the race.

    fn uid(n: u8) -> Uuid {
        Uuid::from_bytes([n; 16])
    }

    #[test]
    fn a_known_device_id_is_refreshed_in_place() {
        assert_eq!(
            plan_device_link(Some(uid(1)), Some(uid(7)), uid(7), None),
            DeviceLink::Refresh(uid(1)),
        );
    }

    #[test]
    fn an_unknown_free_device_id_is_adopted_verbatim() {
        // This is what makes two concurrent first syncs from one machine
        // converge on a single row instead of registering it twice.
        assert_eq!(
            plan_device_link(Some(uid(1)), None, uid(7), None),
            DeviceLink::Adopt(uid(1)),
        );
    }

    #[test]
    fn another_accounts_device_id_is_never_hijacked() {
        let link = plan_device_link(Some(uid(1)), Some(uid(99)), uid(7), None);
        assert_eq!(link, DeviceLink::Mint);
        assert_ne!(
            link,
            DeviceLink::Adopt(uid(1)),
            "adopting would hand another user's sync identity to this account"
        );
    }

    #[test]
    fn a_request_without_an_id_reuses_the_matching_row() {
        assert_eq!(
            plan_device_link(None, None, uid(7), Some(uid(2))),
            DeviceLink::AdoptExisting(uid(2)),
        );
    }

    #[test]
    fn a_request_without_an_id_and_no_match_mints_once() {
        assert_eq!(plan_device_link(None, None, uid(7), None), DeviceLink::Mint,);
    }

    #[test]
    fn a_supplied_id_ignores_the_name_platform_fallback() {
        // A client that sends an id owns its identity; it must not be folded
        // into an unrelated row that merely shares its display name.
        assert_ne!(
            plan_device_link(Some(uid(1)), None, uid(7), Some(uid(2))),
            DeviceLink::AdoptExisting(uid(2)),
        );
    }

    #[test]
    fn platform_strings_are_normalised_to_a_known_set() {
        assert_eq!(normalize_platform(Some("Android")), Some("android".into()));
        assert_eq!(normalize_platform(Some(" win32 ")), Some("windows".into()));
        assert_eq!(normalize_platform(Some("darwin")), Some("macos".into()));
        // Anything unrecognised is dropped rather than stored and rendered.
        assert_eq!(normalize_platform(Some("<script>")), None);
        assert_eq!(normalize_platform(None), None);
    }
}
