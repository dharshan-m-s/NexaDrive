use axum::{
    Json,
    extract::{Query, State},
    http::StatusCode,
};
use chrono::{DateTime, Utc};
use std::{
    fs::FileType,
    path::{Path, PathBuf},
};
use tokio::fs;
use uuid::Uuid;

use crate::{
    auth::require_write_access,
    error::AppError,
    handlers::{admin::audit, storage::folder_size, upload, upload::ensure_quota},
    models::{
        ActionResponse, BatchRequest, CreateFolderRequest, FileEntry, PathQuery, PhotoEntry,
        RenameRequest, SearchQuery, TransferRequest,
    },
    paths::{is_photo, safe_relative_path, sanitize_name, trash_root, user_root},
    state::AppState,
};

pub(crate) async fn list_files(
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
        // A partially uploaded file is an implementation detail of the
        // transfer, not something the user should see in their folder.
        if upload::is_staging_name(&name) {
            continue;
        }
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

pub(crate) async fn search_files(
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
            if upload::is_staging_name(&name) {
                continue;
            }
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

pub(crate) async fn rename_file(
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

pub(crate) async fn move_file(
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

pub(crate) async fn copy_file(
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
        ensure_quota(state, user_id, incoming, None).await?;
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

pub(crate) async fn batch_files(
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

pub(crate) async fn ensure_supported_entry(path: &Path) -> Result<FileType, AppError> {
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

pub(crate) async fn delete_one_to_trash(
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

pub(crate) async fn create_folder(
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

pub(crate) async fn list_photos(
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
                let name = entry.file_name().to_string_lossy().to_string();
                if upload::is_staging_name(&name) {
                    continue;
                }
                let metadata = match entry.metadata().await {
                    Ok(metadata) => metadata,
                    Err(e) if e.kind() == std::io::ErrorKind::NotFound => continue,
                    Err(e) => return Err(AppError::Io(e)),
                };
                let relative = path
                    .strip_prefix(&root)
                    .map_err(|_| AppError::Internal)?
                    .to_string_lossy()
                    .replace('\\', "/");
                photos.push(PhotoEntry {
                    name,
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

pub(crate) async fn delete_file(
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
