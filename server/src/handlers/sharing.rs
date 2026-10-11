use axum::{
    Json,
    extract::{Query, State},
    http::{HeaderMap, StatusCode, header},
    response::Response,
};
use chrono::{DateTime, Utc};
use sqlx::{Row, sqlite::SqlitePool};
use std::{
    path::{Path, PathBuf},
    time::{Duration, Instant},
};
use tokio::fs;
use uuid::Uuid;

use crate::{
    auth::{
        clear_share_download_attempts, new_token, permission_allows,
        register_failed_share_download, token_hash,
    },
    error::AppError,
    handlers::{
        admin::audit, download::file_response, files::ensure_supported_entry, storage::folder_size,
    },
    models::{
        ActionResponse, CreateShareRequest, FileEntry, IdQuery, PathQuery, ShareResponse,
        SharedActionRequest, SharedQuery, SharedRootResponse,
    },
    paths::{safe_relative_path, sanitize_name, trash_root, user_root},
    state::AppState,
};

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

pub(crate) async fn list_shares(
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

/// Whether a share request may be satisfied as a public link.
///
/// A link resolves to exactly one file download, so directories are only
/// shareable with a named NexaDrive user.
fn link_share_is_allowed(is_dir: bool, has_recipient: bool) -> bool {
    !is_dir || has_recipient
}

pub(crate) async fn create_share(
    State(state): State<AppState>,
    axum::extract::Extension(owner_id): axum::extract::Extension<Uuid>,
    Json(payload): Json<CreateShareRequest>,
) -> Result<Json<ShareResponse>, AppError> {
    let path = safe_relative_path(&payload.path)?;
    if path.as_os_str().is_empty() {
        return Err(AppError::BadRequest("Cannot share the root".into()));
    }
    let file_type = ensure_supported_entry(&user_root(&state, owner_id).join(&path)).await?;
    if !matches!(payload.permission.as_str(), "read" | "write") {
        return Err(AppError::BadRequest(
            "Permission must be read or write".into(),
        ));
    }
    // A public link only ever resolves to a single file download, so a link to
    // a directory would be created and then fail for every recipient. Refuse
    // it up front instead of handing out a broken URL. Folder sharing to a
    // named user still works (the recipient browses it through /api/shared).
    if !link_share_is_allowed(file_type.is_dir(), payload.username.is_some()) {
        return Err(AppError::BadRequest(
            "Folders cannot be shared as public links. Share the folder with a NexaDrive user instead."
                .into(),
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

pub(crate) async fn delete_share(
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

pub(crate) async fn list_shared(
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

pub(crate) async fn list_shared_items(
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

pub(crate) async fn download_shared_file(
    State(state): State<AppState>,
    axum::extract::Extension(user_id): axum::extract::Extension<Uuid>,
    Query(query): Query<SharedQuery>,
    headers: HeaderMap,
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
    audit(
        &state.db,
        user_id,
        "shared_download",
        Some(&format!("{}:{}", query.share_id, rel.to_string_lossy())),
    )
    .await?;
    let requested_range = headers
        .get(header::RANGE)
        .and_then(|v| v.to_str().ok())
        .map(str::to_string);
    Ok(file_response(file, &md, &name, requested_range.as_deref()).await)
}

pub(crate) async fn shared_action(
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
pub(crate) async fn public_share_download(
    State(state): State<AppState>,
    axum::extract::Path(token): axum::extract::Path<String>,
    Query(query): Query<PathQuery>,
    headers: HeaderMap,
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
    let token_id = token_hash(&token);
    audit(
        &state.db,
        owner_id,
        "public_share_download",
        Some(&format!("{}:{}", token_id, rel.to_string_lossy())),
    )
    .await?;
    let requested_range = headers
        .get(header::RANGE)
        .and_then(|v| v.to_str().ok())
        .map(str::to_string);
    Ok(file_response(file, &metadata, &name, requested_range.as_deref()).await)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn link_shares_of_directories_are_refused() {
        // `/api/shares` must not hand out a public link that can never resolve.
        assert!(
            link_share_is_allowed(false, false),
            "file link shares are allowed"
        );
        assert!(
            link_share_is_allowed(false, true),
            "file shares to a user work"
        );
        assert!(
            link_share_is_allowed(true, true),
            "folder shares to a user work"
        );
        assert!(
            !link_share_is_allowed(true, false),
            "folder link shares do not"
        );
    }
}
